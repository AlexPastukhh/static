param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$normalizer = Join-Path $PSScriptRoot "Normalize-StaticExecutionModelV4.ps1"
$validator = Join-Path $PSScriptRoot "Validate-StaticExecutionModelV4.ps1"

if (-not (Test-Path $normalizer)) {
    throw "Missing normalizer: $normalizer"
}

if (-not (Test-Path $validator)) {
    throw "Missing validator: $validator"
}

$jobs = @(
    [pscustomobject]@{
        Language = "java"
        Source = Join-Path $repoRoot "fixtures\structural-probe\java-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\java"
        TargetMethod = "exercise"
        BranchControl = "SWITCH"
        ExpectClassicFor = $true
    },
    [pscustomobject]@{
        Language = "python"
        Source = Join-Path $repoRoot "fixtures\structural-probe\python-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\python"
        TargetMethod = "exercise_structural_probe"
        BranchControl = "MATCH"
        ExpectClassicFor = $false
    },
    [pscustomobject]@{
        Language = "typescript"
        Source = Join-Path $repoRoot "fixtures\structural-probe\typescript-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\typescript"
        TargetMethod = "exerciseStructuralProbe"
        BranchControl = "SWITCH"
        ExpectClassicFor = $true
    },
    [pscustomobject]@{
        Language = "csharp"
        Source = Join-Path $repoRoot "fixtures\structural-probe\csharp-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\csharp"
        TargetMethod = "ExerciseStructuralProbe"
        BranchControl = "SWITCH"
        ExpectClassicFor = $true
    }
)

$results = [System.Collections.Generic.List[object]]::new()

foreach ($job in $jobs) {
    Write-Host ""
    Write-Host "================================"
    Write-Host ("V4 NORMALIZE B2: " + $job.Language.ToUpperInvariant())
    Write-Host "================================"

    $rawPath = Join-Path $job.Output "raw-structural-model-v4.json"
    $modelPath = Join-Path $job.Output "static-execution-model-v4.json"
    $reportPath = Join-Path $job.Output "normalization-report.json"

    if (-not (Test-Path $rawPath)) {
        throw "Missing raw structural model: $rawPath"
    }

    & $normalizer `
        -RawStructuralModelPath $rawPath `
        -Language $job.Language `
        -SourceRoot $job.Source `
        -OutputPath $modelPath

    if (-not (Test-Path $modelPath)) {
        throw "Normalizer did not create: $modelPath"
    }

    & $validator -Path $modelPath | Out-Host

    $model = Get-Content $modelPath -Raw | ConvertFrom-Json
    $report = Get-Content $reportPath -Raw | ConvertFrom-Json

    $target = @(
        $model.methods |
            Where-Object { $_.name -eq $job.TargetMethod }
    ) | Select-Object -First 1

    if (-not $target) {
        throw "Target method missing after normalization: $($job.TargetMethod)"
    }

    # -------------------------------------------------------------------------
    # B1 regression assertions
    # -------------------------------------------------------------------------

    $parameterIndexes = @($target.parameters | ForEach-Object { [int]$_.index })
    for ($i = 0; $i -lt $parameterIndexes.Count; $i++) {
        if ($parameterIndexes[$i] -ne $i) {
            throw "Parameter indexes are not normalized for $($job.TargetMethod)"
        }
    }

    if (@($target.parameters | Where-Object { $_.name -eq "this" }).Count -gt 0) {
        throw "Synthetic this leaked into source parameters for $($job.TargetMethod)"
    }

    $targetControls = @(
        $model.controls |
            Where-Object { $_.method -eq $target.fullName }
    )

    $ifControls = @($targetControls | Where-Object { $_.kind -eq "IF" })
    if ($ifControls.Count -lt 1) {
        throw "No normalized IF controls for $($job.TargetMethod)"
    }

    foreach ($ifControl in $ifControls) {
        $branchKinds = @($ifControl.branches | ForEach-Object { $_.kind })
        if ($branchKinds -notcontains "TRUE" -or $branchKinds -notcontains "FALSE") {
            throw "IF without TRUE/FALSE branches: $($ifControl.id)"
        }
    }

    $expressionById = @{}
    foreach ($expression in @($model.expressions)) {
        $expressionById[[string]$expression.id] = $expression
    }

    $topIf = $ifControls | Sort-Object { $_.source.line } | Select-Object -First 1
    if (-not $topIf.conditionExpressionId) {
        throw "Top IF has no condition expression"
    }

    $condition = $expressionById[[string]$topIf.conditionExpressionId]
    if (-not $condition -or $condition.operator -ne "logical-and") {
        throw "Top IF condition is not normalized logical-and"
    }

    $hasLogicalOrChild = $false
    foreach ($child in @($condition.children)) {
        if ($expressionById.ContainsKey([string]$child.expressionId)) {
            $childExpression = $expressionById[[string]$child.expressionId]
            if ($childExpression.operator -eq "logical-or") {
                $hasLogicalOrChild = $true
            }
        }
    }

    if (-not $hasLogicalOrChild) {
        throw "Top IF lost nested logical-or structure"
    }

    $conditionalExpressions = @(
        $model.expressions |
            Where-Object {
                $_.method -eq $target.fullName -and
                $_.operator -eq "conditional"
            }
    )

    if ($conditionalExpressions.Count -lt 1) {
        throw "No normalized ternary/conditional expression"
    }

    $conditional = $conditionalExpressions | Select-Object -First 1
    $roles = @($conditional.children | ForEach-Object { $_.role })
    foreach ($requiredRole in @("CONDITION", "TRUE", "FALSE")) {
        if ($roles -notcontains $requiredRole) {
            throw "Conditional expression missing role: $requiredRole"
        }
    }

    $returns = @($targetControls | Where-Object { $_.kind -eq "RETURN" })
    if ($returns.Count -lt 2) {
        throw "Expected multiple RETURN controls in target fixture"
    }

    $sameLineGroups = @(
        $model.expressions |
            Where-Object {
                $_.method -eq $target.fullName -and
                $_.kind -eq "CALL" -and
                $_.source.text -match '(?i)nested\(value\)'
            } |
            Group-Object { [string]$_.source.line + "|" + [string]$_.source.text } |
            Where-Object { $_.Count -ge 2 }
    )

    if ($sameLineGroups.Count -lt 1) {
        throw "Repeated same-line nested calls were not preserved as distinct expressions"
    }

    foreach ($group in $sameLineGroups) {
        $ids = @($group.Group | ForEach-Object { $_.id } | Sort-Object -Unique)
        if ($ids.Count -ne $group.Count) {
            throw "Repeated same-line call ids are not unique"
        }
    }

    # -------------------------------------------------------------------------
    # B2 semantic assertions
    # -------------------------------------------------------------------------

    $foreachControls = @($targetControls | Where-Object { $_.kind -eq "FOREACH" })
    if ($foreachControls.Count -lt 1) {
        throw "No normalized FOREACH for $($job.TargetMethod)"
    }

    foreach ($foreachControl in $foreachControls) {
        if (-not $foreachControl.iterableExpressionId) {
            throw "FOREACH without iterableExpressionId: $($foreachControl.id)"
        }

        if (-not $foreachControl.iterationBinding) {
            throw "FOREACH without iterationBinding: $($foreachControl.id)"
        }

        $bodyBranches = @($foreachControl.branches | Where-Object { $_.kind -eq "BODY" })
        if ($bodyBranches.Count -ne 1) {
            throw "FOREACH must have exactly one BODY branch: $($foreachControl.id)"
        }

        if (@($bodyBranches[0].body).Count -eq 0) {
            throw "FOREACH BODY branch is empty after normalization: $($foreachControl.id)"
        }

        if (-not $expressionById.ContainsKey([string]$foreachControl.iterableExpressionId)) {
            throw "FOREACH iterable expression is missing: $($foreachControl.id)"
        }
    }

    $whileControls = @($targetControls | Where-Object { $_.kind -eq "WHILE" })
    if ($whileControls.Count -lt 1) {
        throw "Source while loop was not preserved as WHILE"
    }

    foreach ($whileControl in $whileControls) {
        if (-not $whileControl.conditionExpressionId) {
            throw "WHILE without condition: $($whileControl.id)"
        }
        if (@($whileControl.branches | Where-Object { $_.kind -eq "BODY" }).Count -ne 1) {
            throw "WHILE without one BODY branch: $($whileControl.id)"
        }
    }

    $forControls = @($targetControls | Where-Object { $_.kind -eq "FOR" })

    if ($job.ExpectClassicFor) {
        if ($forControls.Count -lt 1) {
            throw "Classic FOR was not normalized for $($job.Language)"
        }

        foreach ($forControl in $forControls) {
            if (-not $forControl.conditionExpressionId) {
                throw "FOR without condition: $($forControl.id)"
            }

            if (@($forControl.initExpressionIds).Count -lt 1) {
                throw "FOR without initExpressionIds: $($forControl.id)"
            }

            if (@($forControl.updateExpressionIds).Count -lt 1) {
                throw "FOR without updateExpressionIds: $($forControl.id)"
            }

            if (@($forControl.branches | Where-Object { $_.kind -eq "BODY" }).Count -ne 1) {
                throw "FOR without one BODY branch: $($forControl.id)"
            }
        }
    }
    elseif ($forControls.Count -gt 0) {
        throw "Python for-in lowering leaked as classic FOR"
    }

    $branchControls = @(
        $targetControls |
            Where-Object { $_.kind -eq $job.BranchControl }
    )

    if ($branchControls.Count -lt 1) {
        throw "Missing $($job.BranchControl) control"
    }

    $branchControl = $branchControls | Select-Object -First 1

    if (-not $branchControl.conditionExpressionId) {
        throw "$($job.BranchControl) has no condition/value expression"
    }

    $caseBranches = @($branchControl.branches | Where-Object { $_.kind -eq "CASE" })
    $defaultBranches = @($branchControl.branches | Where-Object { $_.kind -eq "DEFAULT" })

    if ($caseBranches.Count -lt 2 -or $defaultBranches.Count -ne 1) {
        throw "$($job.BranchControl) CASE/DEFAULT extraction is incomplete"
    }

    $tryControls = @($targetControls | Where-Object { $_.kind -eq "TRY" })
    if ($tryControls.Count -lt 1) {
        throw "TRY was not normalized"
    }

    foreach ($tryControl in $tryControls) {
        $tryKinds = @($tryControl.branches | ForEach-Object { $_.kind })
        foreach ($requiredKind in @("TRY", "CATCH", "FINALLY")) {
            if ($tryKinds -notcontains $requiredKind) {
                throw "TRY missing branch kind ${requiredKind}: $($tryControl.id)"
            }
        }
    }

    $throwControls = @($targetControls | Where-Object { $_.kind -eq "THROW" })
    if ($throwControls.Count -lt 1) {
        throw "THROW/raise was not normalized"
    }

    foreach ($throwControl in $throwControls) {
        if (-not $throwControl.valueExpressionId) {
            throw "THROW without valueExpressionId: $($throwControl.id)"
        }

        if (-not $expressionById.ContainsKey([string]$throwControl.valueExpressionId)) {
            throw "THROW value expression is missing: $($throwControl.id)"
        }
    }

    $breakControls = @($targetControls | Where-Object { $_.kind -eq "BREAK" })
    $continueControls = @($targetControls | Where-Object { $_.kind -eq "CONTINUE" })

    if ($breakControls.Count -lt 1) {
        throw "BREAK controls were not normalized"
    }

    if ($continueControls.Count -lt 1) {
        throw "CONTINUE controls were not normalized"
    }

    # Every target control must be placed in method.body or some Branch.body.
    $referencedControlIds = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($step in @($target.body)) {
        if ($step.kind -eq "CONTROL") {
            [void]$referencedControlIds.Add([string]$step.id)
        }
    }

    foreach ($control in $targetControls) {
        foreach ($branch in @($control.branches)) {
            foreach ($step in @($branch.body)) {
                if ($step.kind -eq "CONTROL") {
                    [void]$referencedControlIds.Add([string]$step.id)
                }
            }
        }
    }

    foreach ($control in $targetControls) {
        if (-not $referencedControlIds.Contains([string]$control.id)) {
            throw "Orphan control not placed in method/branch body: $($control.kind) $($control.id)"
        }
    }

    $syntheticLeak = @(
        $model.expressions |
            Where-Object {
                $_.method -eq $target.fullName -and
                $_.source.text -match '\$iterLocal|__next__\(|__iter__\(|_iterator_|_result_|iteratorNonEmptyOrException|(^|[^A-Za-z0-9_])tmp[0-9]+([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])_idx_([^A-Za-z0-9_]|$)'
            }
    )

    if ($syntheticLeak.Count -gt 0) {
        throw "Synthetic iterator lowering leaked into public expressions"
    }

    if ([int]$report.unmappedRawControls -ne 0) {
        throw "B2 left unmapped raw controls: $($report.unmappedRawControls)"
    }

    if ([int]$report.unmappedRawCalls -ne 0) {
        throw "B2 left unexplained raw non-operator calls: $($report.unmappedRawCalls)"
    }

    foreach ($source in @(
        @($model.methods | ForEach-Object { $_.source }) +
        @($model.expressions | ForEach-Object { $_.source }) +
        @($model.controls | ForEach-Object { $_.source })
    )) {
        if ($source -and $source.column -ne $null -and [int]$source.column -lt 1) {
            throw "Non-1-based public column found"
        }

        if ($source -and [string]$source.file -match '\\') {
            throw "Backslash leaked into public source path"
        }
    }

    $report.validationResult = "pass"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $reportPath,
        ($report | ConvertTo-Json -Depth 100),
        $utf8NoBom
    )

    $results.Add(
        [pscustomobject]@{
            Language = $job.Language
            Types = [int]$model.summary.types
            Methods = [int]$model.summary.methods
            CallSites = [int]$model.summary.callSites
            Expressions = [int]$model.summary.expressions
            Controls = [int]$model.summary.controls
            Foreach = [int]$report.foreachNormalizations
            ThrowRaise = [int]$report.throwRaiseNormalizations
            UnmappedCalls = [int]$report.unmappedRawCalls
            UnmappedControls = [int]$report.unmappedRawControls
        }
    )
}

Write-Host ""
Write-Host "================================"
Write-Host "V4 NORMALIZATION SLICE B2 PASS"
Write-Host "================================"
Write-Host ""
$results | Format-Table -AutoSize
Write-Host ""
Write-Host "B2 covers loops/FOREACH, SWITCH/MATCH, TRY/CATCH/FINALLY, THROW/raise, BREAK and CONTINUE placement."
