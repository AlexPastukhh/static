param(
    [string]$Source = "C:\gd-cap\java-src",
    [string]$OutputDirectory = "",
    [switch]$ReuseCpg,
    [int]$ExpectedTypes = 103,
    [int]$ExpectedMethods = 715,
    [int]$ExpectedExcludedTestTypes = 44,
    [int]$ExpectedExcludedTestMethods = 106
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "results\v4-fixtures\gd-cap"
}

$sourcePath = (Resolve-Path $Source).Path
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $OutputDirectory
)

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$exporter = Join-Path $PSScriptRoot "Export-StructuralModelV4.ps1"
$normalizer = Join-Path $PSScriptRoot "Normalize-StaticExecutionModelV4.ps1"
$validator = Join-Path $PSScriptRoot "Validate-StaticExecutionModelV4.ps1"

foreach ($required in @($exporter, $normalizer, $validator)) {
    if (-not (Test-Path $required)) {
        throw "Missing required script: $required"
    }
}

$rawPath = Join-Path $outputPath "raw-structural-model-v4.json"
$modelPath = Join-Path $outputPath "static-execution-model-v4.json"
$normalizationReportPath = Join-Path $outputPath "normalization-report.json"
$gateReportPath = Join-Path $outputPath "gd-cap-v4-gate-report.json"

Write-Host ""
Write-Host "================================"
Write-Host "GD-CAP WHOLE PROJECT V4 GATE"
Write-Host "================================"
Write-Host ("Source: " + $sourcePath)
Write-Host ("Output: " + $outputPath)
Write-Host ""

& $exporter `
    -Language "java" `
    -Source $sourcePath `
    -OutputDirectory $outputPath `
    -ReuseCpg:$ReuseCpg

if (-not (Test-Path $rawPath)) {
    throw "Raw v4 model was not created: $rawPath"
}

& $normalizer `
    -RawStructuralModelPath $rawPath `
    -Language "java" `
    -SourceRoot $sourcePath `
    -OutputPath $modelPath

if (-not (Test-Path $modelPath)) {
    throw "Normalized v4 model was not created: $modelPath"
}

& $validator -Path $modelPath | Out-Host

$model = Get-Content $modelPath -Raw | ConvertFrom-Json
$normalizationReport = Get-Content $normalizationReportPath -Raw | ConvertFrom-Json

$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-GateFailure {
    param([string]$Message)
    $failures.Add($Message)
    Write-Host ("FAIL: " + $Message)
}

function Add-GateWarning {
    param([string]$Message)
    $warnings.Add($Message)
    Write-Host ("WARN: " + $Message)
}

function Assert-EqualInt {
    param(
        [string]$Name,
        [int]$Actual,
        [int]$Expected
    )

    if ($Actual -ne $Expected) {
        Add-GateFailure ($Name + " expected " + $Expected + ", actual " + $Actual)
    }
}

function Assert-Zero {
    param(
        [string]$Name,
        [int]$Actual
    )

    if ($Actual -ne 0) {
        Add-GateFailure ($Name + " expected 0, actual " + $Actual)
    }
}

# ---------------------------------------------------------------------------
# Whole-project regression baseline
# ---------------------------------------------------------------------------

Assert-EqualInt "production types" ([int]$model.summary.types) $ExpectedTypes
Assert-EqualInt "production methods" ([int]$model.summary.methods) $ExpectedMethods
Assert-EqualInt "excluded test types" ([int]$model.summary.excludedTestTypes) $ExpectedExcludedTestTypes
Assert-EqualInt "excluded test methods" ([int]$model.summary.excludedTestMethods) $ExpectedExcludedTestMethods

Assert-Zero "normalization id collisions" ([int]$normalizationReport.idCollisions)
Assert-Zero "unmapped raw calls" ([int]$normalizationReport.unmappedRawCalls)
Assert-Zero "unmapped raw controls" ([int]$normalizationReport.unmappedRawControls)
Assert-Zero "unsupported control steps" ([int]$normalizationReport.unsupportedControlSteps)
Assert-Zero "unsupported block steps" ([int]$normalizationReport.unsupportedBlockSteps)
Assert-Zero "unresolved source snippets" ([int]$normalizationReport.unresolvedSourceSnippets)

# ---------------------------------------------------------------------------
# Model referential integrity beyond schema validation
# ---------------------------------------------------------------------------

$expressionById = @{}
foreach ($expression in @($model.expressions)) {
    $expressionById[[string]$expression.id] = $expression
}

$controlById = @{}
foreach ($control in @($model.controls)) {
    $controlById[[string]$control.id] = $control
}

$callSiteById = @{}
foreach ($callSite in @($model.callSites)) {
    $callSiteById[[string]$callSite.id] = $callSite

    if (-not $expressionById.ContainsKey([string]$callSite.expressionId)) {
        Add-GateFailure ("Call site references missing expression: " + [string]$callSite.id)
    }
}

foreach ($expression in @($model.expressions)) {
    if ($expression.callSiteId) {
        if (-not $callSiteById.ContainsKey([string]$expression.callSiteId)) {
            Add-GateFailure ("Expression references missing call site: " + [string]$expression.id)
        }
    }

    foreach ($child in @($expression.children)) {
        if (-not $expressionById.ContainsKey([string]$child.expressionId)) {
            Add-GateFailure ("Expression child reference missing: " + [string]$expression.id)
        }
    }
}

# ---------------------------------------------------------------------------
# CopyNoteMaterialFeature.copyMany acceptance
# ---------------------------------------------------------------------------

$copyManyMatches = @(
    $model.methods |
        Where-Object {
            $_.name -eq "copyMany" -and
            $_.owner -like "*gdcap.features.copy.CopyNoteMaterialFeature*"
        }
)

if ($copyManyMatches.Count -ne 1) {
    Add-GateFailure ("Expected exactly one CopyNoteMaterialFeature.copyMany, found " + $copyManyMatches.Count)
    $copyMany = $null
}
else {
    $copyMany = $copyManyMatches[0]
}

$copyManyControlCounts = [ordered]@{}
$copyManyCallTexts = @()
$copyManyPossibleTargets = @()

if ($copyMany) {
    $fileNormalized = ([string]$copyMany.source.file).Replace('\', '/')
    if (-not $fileNormalized.EndsWith("gdcap/features/copy/CopyNoteMaterialFeature.java")) {
        Add-GateFailure ("copyMany source file is unexpected: " + [string]$copyMany.source.file)
    }

    if ([int]$copyMany.source.line -ne 50) {
        Add-GateFailure ("copyMany source line expected 50, actual " + [string]$copyMany.source.line)
    }

    if ([string]$copyMany.returnType -notlike "*CopyOutcome*") {
        Add-GateFailure ("copyMany return type is unexpected: " + [string]$copyMany.returnType)
    }

    $parameterNames = @($copyMany.parameters | ForEach-Object { [string]$_.name })
    $expectedParameterNames = @(
        "sourceFolder",
        "sourceNote",
        "sourceElements",
        "targetFolder",
        "targetNote",
        "newElementIds"
    )

    if (($parameterNames -join "|") -ne ($expectedParameterNames -join "|")) {
        Add-GateFailure ("copyMany parameters are unexpected: " + ($parameterNames -join ", "))
    }

    if ($parameterNames -contains "this") {
        Add-GateFailure "copyMany contains synthetic implicit receiver parameter 'this'"
    }

    $copyManyControls = @(
        $model.controls |
            Where-Object { $_.method -eq $copyMany.fullName }
    )

    foreach ($kind in @("IF", "FOR", "FOREACH", "TRY", "THROW", "RETURN")) {
        $count = @($copyManyControls | Where-Object { $_.kind -eq $kind }).Count
        $copyManyControlCounts[$kind] = $count
    }

    if ([int]$copyManyControlCounts["IF"] -lt 10) {
        Add-GateFailure ("copyMany IF count too low: " + [string]$copyManyControlCounts["IF"])
    }

    if ([int]$copyManyControlCounts["FOR"] -lt 1) {
        Add-GateFailure "copyMany lost classic FOR"
    }

    if ([int]$copyManyControlCounts["FOREACH"] -lt 6) {
        Add-GateFailure ("copyMany FOREACH count too low: " + [string]$copyManyControlCounts["FOREACH"])
    }

    if ([int]$copyManyControlCounts["TRY"] -lt 2) {
        Add-GateFailure ("copyMany TRY count too low: " + [string]$copyManyControlCounts["TRY"])
    }

    if ([int]$copyManyControlCounts["THROW"] -lt 10) {
        Add-GateFailure ("copyMany THROW count too low: " + [string]$copyManyControlCounts["THROW"])
    }

    if ([int]$copyManyControlCounts["RETURN"] -lt 1) {
        Add-GateFailure "copyMany lost RETURN"
    }

    $copyManyTryControls = @(
        $copyManyControls |
            Where-Object { $_.kind -eq "TRY" }
    )

    foreach ($tryControl in $copyManyTryControls) {
        $branchKinds = @($tryControl.branches | ForEach-Object { [string]$_.kind })

        if ($branchKinds -notcontains "TRY") {
            Add-GateFailure ("TRY control missing TRY branch: " + [string]$tryControl.id)
        }

        if ($branchKinds -notcontains "CATCH") {
            Add-GateFailure ("TRY control missing CATCH branch: " + [string]$tryControl.id)
        }
    }

    $copyManyCallSites = @(
        $model.callSites |
            Where-Object { $_.caller -eq $copyMany.fullName }
    )

    foreach ($callSite in $copyManyCallSites) {
        if ($expressionById.ContainsKey([string]$callSite.expressionId)) {
            $copyManyCallTexts += [string]$expressionById[[string]$callSite.expressionId].source.text
        }

        foreach ($target in @($callSite.possibleTargets)) {
            $copyManyPossibleTargets += [string]$target
        }
    }

    $requiredCallPatterns = @(
        "FolderPath\.normalize\s*\(\s*sourceFolder\s*\)",
        "FolderPath\.normalize\s*\(\s*targetFolder\s*\)",
        "noteSafePersistence\.load\s*\(\s*sourceFolder\s*,\s*sourceNote\s*\)",
        "noteSafePersistence\.load\s*\(\s*targetFolder\s*,\s*targetNote\s*\)",
        "noteSafePersistence\.canModify\s*\(",
        "prepareOne\s*\(",
        "cleanupCreatedAssets\s*\(",
        "noteSafePersistence\.save\s*\(",
        "targetContainsAnyElement\s*\("
    )

    foreach ($pattern in $requiredCallPatterns) {
        $matchCount = @($copyManyCallTexts | Where-Object { $_ -match $pattern }).Count
        if ($matchCount -lt 1) {
            Add-GateFailure ("copyMany missing source-level call pattern: " + $pattern)
        }
    }

    $requiredInternalTargetPatterns = @(
        "*CopyNoteMaterialFeature.prepareOne*",
        "*CopyNoteMaterialFeature.cleanupCreatedAssets*",
        "*CopyNoteMaterialFeature.targetContainsAnyElement*",
        "*NoteSafePersistence.load*",
        "*NoteSafePersistence.canModify*",
        "*NoteSafePersistence.save*"
    )

    foreach ($targetPattern in $requiredInternalTargetPatterns) {
        $targetMatches = @(
            $copyManyPossibleTargets |
                Where-Object { $_ -like $targetPattern }
        )

        if ($targetMatches.Count -lt 1) {
            Add-GateFailure ("copyMany missing resolved internal target: " + $targetPattern)
        }
    }

    $loweringTargetPatterns = @(
        "java.util.Iterator.hasNext:*",
        "java.util.Iterator.next:*",
        "java.util.List.iterator:*",
        "java.lang.Iterable.iterator:*"
    )

    foreach ($targetPattern in $loweringTargetPatterns) {
        $loweringMatches = @(
            $copyManyPossibleTargets |
                Where-Object { $_ -like $targetPattern }
        )

        if ($loweringMatches.Count -gt 0) {
            Add-GateFailure ("copyMany leaked iterator lowering target: " + $targetPattern)
        }
    }

    # Every copyMany control must be reachable from the method body or from a branch
    # of another copyMany control. This catches the orphan-control class of bugs.
    $placedControlIds = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($step in @($copyMany.body)) {
        if ([string]$step.kind -eq "CONTROL") {
            [void]$placedControlIds.Add([string]$step.id)
        }
    }

    foreach ($control in $copyManyControls) {
        foreach ($branch in @($control.branches)) {
            foreach ($step in @($branch.body)) {
                if ([string]$step.kind -eq "CONTROL") {
                    [void]$placedControlIds.Add([string]$step.id)
                }
            }
        }
    }

    foreach ($control in $copyManyControls) {
        if (-not $placedControlIds.Contains([string]$control.id)) {
            Add-GateFailure ("copyMany orphan control: " + [string]$control.kind + " " + [string]$control.id)
        }
    }
}

# ---------------------------------------------------------------------------
# Gate report
# ---------------------------------------------------------------------------

$gateResult = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }

$gateReport = [ordered]@{
    gate = "gd-cap-v4-whole-project"
    result = $gateResult
    source = $sourcePath
    modelPath = $modelPath
    normalizationReportPath = $normalizationReportPath

    expectedBaseline = [ordered]@{
        types = $ExpectedTypes
        methods = $ExpectedMethods
        excludedTestTypes = $ExpectedExcludedTestTypes
        excludedTestMethods = $ExpectedExcludedTestMethods
    }

    actualSummary = $model.summary

    normalization = [ordered]@{
        rawTypes = $normalizationReport.rawTypes
        rawMethods = $normalizationReport.rawMethods
        rawNonOperatorCalls = $normalizationReport.rawNonOperatorCalls
        rawControls = $normalizationReport.rawControls
        normalizedCallSites = $normalizationReport.normalizedCallSites
        normalizedControls = $normalizationReport.normalizedControls
        syntheticNodesSuppressed = $normalizationReport.syntheticNodesSuppressed
        foreachNormalizations = $normalizationReport.foreachNormalizations
        throwRaiseNormalizations = $normalizationReport.throwRaiseNormalizations
        unmappedRawCalls = $normalizationReport.unmappedRawCalls
        unmappedRawCallByName = $normalizationReport.unmappedRawCallByName
        unmappedRawCallSamples = $normalizationReport.unmappedRawCallSamples
        unmappedRawControls = $normalizationReport.unmappedRawControls
        unsupportedControlSteps = $normalizationReport.unsupportedControlSteps
        unsupportedBlockSteps = $normalizationReport.unsupportedBlockSteps
        unresolvedSourceSnippets = $normalizationReport.unresolvedSourceSnippets
        idCollisions = $normalizationReport.idCollisions
    }

    copyMany = if ($copyMany) {
        [ordered]@{
            fullName = $copyMany.fullName
            owner = $copyMany.owner
            source = $copyMany.source
            returnType = $copyMany.returnType
            parameterNames = @($copyMany.parameters | ForEach-Object { [string]$_.name })
            bodySteps = @($copyMany.body).Count
            callSites = @(
                $model.callSites |
                    Where-Object { $_.caller -eq $copyMany.fullName }
            ).Count
            controls = $copyManyControlCounts
            callTexts = @($copyManyCallTexts | Sort-Object -Unique)
            possibleTargets = @($copyManyPossibleTargets | Sort-Object -Unique)
        }
    }
    else {
        $null
    }

    failures = @($failures)
    warnings = @($warnings)
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$gateJson = $gateReport | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($gateReportPath, $gateJson, $utf8NoBom)

Write-Host ""
Write-Host "================================"
Write-Host ("GD-CAP V4 GATE " + $gateResult)
Write-Host "================================"
Write-Host ("Types:              " + [string]$model.summary.types)
Write-Host ("Methods:            " + [string]$model.summary.methods)
Write-Host ("Call sites:         " + [string]$model.summary.callSites)
Write-Host ("Expressions:        " + [string]$model.summary.expressions)
Write-Host ("Controls:           " + [string]$model.summary.controls)
Write-Host ("Unmapped calls:     " + [string]$normalizationReport.unmappedRawCalls)
Write-Host ("Unmapped controls:  " + [string]$normalizationReport.unmappedRawControls)
Write-Host ("Gate report:        " + $gateReportPath)
Write-Host ""

if ($failures.Count -gt 0) {
    throw ("GD-CAP V4 gate failed with " + $failures.Count + " issue(s). Report: " + $gateReportPath)
}

Write-Host "GD-CAP WHOLE PROJECT V4 GATE PASS"
