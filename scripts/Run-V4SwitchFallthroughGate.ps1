param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$exporter = Join-Path $PSScriptRoot "Export-StructuralModelV4.ps1"
$normalizer = Join-Path $PSScriptRoot "Normalize-StaticExecutionModelV4.ps1"
$validator = Join-Path $PSScriptRoot "Validate-StaticExecutionModelV4.ps1"

foreach ($path in @($exporter, $normalizer, $validator)) {
    if (-not (Test-Path $path)) {
        throw "Missing required script: $path"
    }
}

$jobs = @(
    [pscustomobject]@{
        Language = "java"
        Source = Join-Path $repoRoot "fixtures\fallthrough-probe\java-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\fallthrough\java"
        TargetMethod = "exerciseFallthrough"
        ExplicitGoto = $false
    },
    [pscustomobject]@{
        Language = "typescript"
        Source = Join-Path $repoRoot "fixtures\fallthrough-probe\typescript-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\fallthrough\typescript"
        TargetMethod = "exerciseFallthrough"
        ExplicitGoto = $false
    },
    [pscustomobject]@{
        Language = "csharp"
        Source = Join-Path $repoRoot "fixtures\fallthrough-probe\csharp-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\fallthrough\csharp"
        TargetMethod = "ExerciseFallthrough"
        ExplicitGoto = $true
    }
)

$results = [System.Collections.Generic.List[object]]::new()

foreach ($job in $jobs) {
    Write-Host ""
    Write-Host "================================"
    Write-Host ("SWITCH FALLTHROUGH GATE: " + $job.Language.ToUpperInvariant())
    Write-Host "================================"

    New-Item -ItemType Directory -Force -Path $job.Output | Out-Null

    & $exporter `
        -Language $job.Language `
        -Source $job.Source `
        -OutputDirectory $job.Output

    $rawPath = Join-Path $job.Output "raw-structural-model-v4.json"
    $modelPath = Join-Path $job.Output "static-execution-model-v4.json"
    $reportPath = Join-Path $job.Output "normalization-report.json"
    $gateReportPath = Join-Path $job.Output "fallthrough-gate-report.json"

    if (-not (Test-Path $rawPath)) {
        throw "Raw structural model missing: $rawPath"
    }

    & $normalizer `
        -RawStructuralModelPath $rawPath `
        -Language $job.Language `
        -SourceRoot $job.Source `
        -OutputPath $modelPath

    & $validator -Path $modelPath | Out-Host

    $model = Get-Content $modelPath -Raw | ConvertFrom-Json
    $normalizationReport = Get-Content $reportPath -Raw | ConvertFrom-Json

    $target = @(
        $model.methods |
            Where-Object { $_.name -eq $job.TargetMethod }
    ) | Select-Object -First 1

    if (-not $target) {
        throw "Target method not found: $($job.TargetMethod)"
    }

    $switchControls = @(
        $model.controls |
            Where-Object {
                $_.method -eq $target.fullName -and
                $_.kind -eq "SWITCH"
            }
    )

    if ($switchControls.Count -ne 1) {
        throw "Expected exactly one SWITCH, found: $($switchControls.Count)"
    }

    $switchControl = $switchControls[0]
    $branches = @($switchControl.branches)

    if ($branches.Count -ne 3) {
        throw "Expected exactly 3 SWITCH branches, found: $($branches.Count)"
    }

    $branchKinds = @($branches | ForEach-Object { [string]$_.kind })
    if (
        $branchKinds[0] -ne "CASE" -or
        $branchKinds[1] -ne "CASE" -or
        $branchKinds[2] -ne "DEFAULT"
    ) {
        throw "Unexpected branch order: $($branchKinds -join ', ')"
    }

    $expressionById = @{}
    foreach ($expression in @($model.expressions)) {
        $expressionById[[string]$expression.id] = $expression
    }

    $controlById = @{}
    foreach ($control in @($model.controls)) {
        $controlById[[string]$control.id] = $control
    }

    function Get-BranchExpressionTexts {
        param([object]$Branch)

        $texts = [System.Collections.Generic.List[string]]::new()

        foreach ($step in @($Branch.body)) {
            if (
                [string]$step.kind -eq "EXPRESSION" -and
                $expressionById.ContainsKey([string]$step.id)
            ) {
                $texts.Add([string]$expressionById[[string]$step.id].source.text)
            }
        }

        return @($texts)
    }

    function Get-BranchControlKinds {
        param([object]$Branch)

        $kinds = [System.Collections.Generic.List[string]]::new()

        foreach ($step in @($Branch.body)) {
            if (
                [string]$step.kind -eq "CONTROL" -and
                $controlById.ContainsKey([string]$step.id)
            ) {
                $kinds.Add([string]$controlById[[string]$step.id].kind)
            }
        }

        return @($kinds)
    }

    $firstTexts = @(Get-BranchExpressionTexts $branches[0])
    $secondTexts = @(Get-BranchExpressionTexts $branches[1])
    $defaultTexts = @(Get-BranchExpressionTexts $branches[2])

    $firstControlKinds = @(Get-BranchControlKinds $branches[0])
    $secondControlKinds = @(Get-BranchControlKinds $branches[1])

    if (@($firstTexts | Where-Object { $_ -match '(?i)callA\s*\(' }).Count -lt 1) {
        throw "First CASE lost callA"
    }

    if (@($secondTexts | Where-Object { $_ -match '(?i)callB\s*\(' }).Count -lt 1) {
        throw "Second CASE lost callB"
    }

    if (@($defaultTexts | Where-Object { $_ -match '(?i)callDefault\s*\(' }).Count -lt 1) {
        throw "DEFAULT lost callDefault"
    }

    if ($firstControlKinds -contains "BREAK") {
        throw "First CASE unexpectedly contains BREAK"
    }

    if ($secondControlKinds -notcontains "BREAK") {
        throw "Second CASE lost BREAK"
    }

    $terminatingKinds = @("BREAK", "RETURN", "THROW")
    $firstTerminates = $false

    foreach ($kind in $firstControlKinds) {
        if ($terminatingKinds -contains $kind) {
            $firstTerminates = $true
            break
        }
    }

    if ($job.ExplicitGoto) {
        # C# forbids implicit fallthrough from a non-empty case. The fixture uses
        # `goto case 2`; this gate checks branch preservation only and records
        # explicit-goto semantics separately.
        $fallthroughRepresentable = $true
        $basis = "ordered SWITCH branches; explicit C# goto-case remains source evidence"
    }
    else {
        if ($firstTerminates) {
            throw "First CASE terminates, so implicit fallthrough cannot be represented"
        }

        $fallthroughRepresentable = $true
        $basis = "ordered SWITCH branches + first CASE has no BREAK/RETURN/THROW"
    }

    if ([int]$normalizationReport.unmappedRawControls -ne 0) {
        throw "Unmapped raw controls: $($normalizationReport.unmappedRawControls)"
    }

    if ([int]$normalizationReport.unmappedRawCalls -ne 0) {
        throw "Unmapped raw calls: $($normalizationReport.unmappedRawCalls)"
    }

    $gateReport = [ordered]@{
        language = $job.Language
        targetMethod = $target.fullName
        switchControlId = $switchControl.id
        branchOrder = @(
            $branches |
                ForEach-Object {
                    [ordered]@{
                        id = $_.id
                        kind = $_.kind
                        label = $_.label
                    }
                }
        )
        firstCaseExpressionTexts = $firstTexts
        firstCaseControlKinds = $firstControlKinds
        secondCaseExpressionTexts = $secondTexts
        secondCaseControlKinds = $secondControlKinds
        defaultExpressionTexts = $defaultTexts
        fallthroughRepresentable = $fallthroughRepresentable
        basis = $basis
        schemaChangeRequired = $false
        result = "PASS"
    }

    $gateReport |
        ConvertTo-Json -Depth 20 |
        Set-Content -Path $gateReportPath -Encoding UTF8

    $results.Add(
        [pscustomobject]@{
            Language = $job.Language
            Branches = $branches.Count
            FirstCaseBreak = ($firstControlKinds -contains "BREAK")
            SecondCaseBreak = ($secondControlKinds -contains "BREAK")
            Representable = $fallthroughRepresentable
            Report = $gateReportPath
        }
    )
}

Write-Host ""
Write-Host "================================"
Write-Host "SWITCH FALLTHROUGH GATE PASS"
Write-Host "================================"
Write-Host ""
$results | Format-Table -AutoSize
Write-Host ""
Write-Host "Conclusion:"
Write-Host "  Current v4 SWITCH representation is sufficient for the tested fallthrough shape."
Write-Host "  No schema change is required by this gate."
