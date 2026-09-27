param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent

$joernBat = (
    Get-ChildItem `
        (Join-Path $repoRoot "tools\joern") `
        -Recurse `
        -Filter "joern.bat" |
    Select-Object -First 1
).FullName

if (-not $joernBat) {
    throw "joern.bat not found"
}

$v3Exporter = Join-Path $PSScriptRoot "joern-export.sc"
$v3Normalizer = Join-Path $PSScriptRoot "Normalize-StaticModel.ps1"
$v3Validator = Join-Path $PSScriptRoot "Validate-ApplicationModel.ps1"
$v4Normalizer = Join-Path $PSScriptRoot "Normalize-StaticExecutionModelV4.ps1"
$v4Validator = Join-Path $PSScriptRoot "Validate-StaticExecutionModelV4.ps1"
$comparator = Join-Path $PSScriptRoot "Compare-V3V4TargetResolution.ps1"

foreach ($path in @(
    $v3Exporter,
    $v3Normalizer,
    $v3Validator,
    $v4Normalizer,
    $v4Validator,
    $comparator
)) {
    if (-not (Test-Path $path)) {
        throw "Missing required file: $path"
    }
}

$jobs = @(
    [pscustomobject]@{
        Language = "java"
        Source = Join-Path $repoRoot "fixtures\structural-probe\java-src"
        V4 = Join-Path $repoRoot "results\v4-fixtures\java"
    },
    [pscustomobject]@{
        Language = "python"
        Source = Join-Path $repoRoot "fixtures\structural-probe\python-src"
        V4 = Join-Path $repoRoot "results\v4-fixtures\python"
    },
    [pscustomobject]@{
        Language = "typescript"
        Source = Join-Path $repoRoot "fixtures\structural-probe\typescript-src"
        V4 = Join-Path $repoRoot "results\v4-fixtures\typescript"
    },
    [pscustomobject]@{
        Language = "csharp"
        Source = Join-Path $repoRoot "fixtures\structural-probe\csharp-src"
        V4 = Join-Path $repoRoot "results\v4-fixtures\csharp"
    }
)

$results = [System.Collections.Generic.List[object]]::new()

foreach ($job in $jobs) {
    Write-Host ""
    Write-Host "================================"
    Write-Host ("TARGET PARITY: " + $job.Language.ToUpperInvariant())
    Write-Host "================================"

    $cpg = Join-Path $job.V4 "cpg.bin"
    $rawV4 = Join-Path $job.V4 "raw-structural-model-v4.json"
    $modelV4 = Join-Path $job.V4 "static-execution-model-v4.json"

    foreach ($path in @($cpg, $rawV4)) {
        if (-not (Test-Path $path)) {
            throw "Phase A/B2 prerequisite missing: $path"
        }
    }

    # Re-normalize V4 with the parity-aligned target resolver.
    & $v4Normalizer `
        -RawStructuralModelPath $rawV4 `
        -Language $job.Language `
        -SourceRoot $job.Source `
        -OutputPath $modelV4

    & $v4Validator -Path $modelV4 | Out-Host

    $oracleDir = Join-Path $repoRoot ("results\v4-fixtures\target-parity\" + $job.Language + "\v3-oracle")
    New-Item -ItemType Directory -Force -Path $oracleDir | Out-Null

    Push-Location $repoRoot
    try {
        $workspaceProject = Join-Path $repoRoot "workspace\cpg.bin"

        if (Test-Path $workspaceProject) {
            Remove-Item $workspaceProject -Recurse -Force
        }

        $cpgJoern = $cpg.Replace('\', '/')
        $outJoern = $oracleDir.Replace('\', '/')

        $cpgParam = '"cpgFile=' + $cpgJoern + '"'
        $outParam = '"outDir=' + $outJoern + '"'

        & $joernBat `
            --script $v3Exporter `
            --param $cpgParam `
            --param $outParam

        if ($LASTEXITCODE -ne 0) {
            throw "V3 Joern exporter failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $rawV3 = Join-Path $oracleDir "static-model.json"
    $modelV3 = Join-Path $oracleDir "application-model.json"

    if (-not (Test-Path $rawV3)) {
        throw "V3 raw oracle missing: $rawV3"
    }

    & $v3Normalizer `
        -InputPath $rawV3 `
        -Language $job.Language `
        -OutputPath $modelV3

    & $v3Validator -Path $modelV3 | Out-Host

    $reportPath = Join-Path $oracleDir "target-resolution-parity-report.json"

    & $comparator `
        -V3ModelPath $modelV3 `
        -V4ModelPath $modelV4 `
        -OutputPath $reportPath

    $report = Get-Content $reportPath -Raw | ConvertFrom-Json

    $results.Add(
        [pscustomobject]@{
            Language         = $job.Language
            SharedMethods    = $report.sharedMethods
            V3Calls          = $report.v3ComparableCalls
            V4Calls          = $report.v4ComparableCalls
            Matched          = $report.matchedV4Calls
            V3LoweringExtras = $report.knownV3OnlyLoweringCount
            Result           = $report.result
        }
    )
}

Write-Host ""
Write-Host "================================"
Write-Host "V3/V4 TARGET RESOLUTION GATE PASS"
Write-Host "================================"
Write-Host ""
$results | Format-Table -AutoSize
Write-Host ""
Write-Host "The V3 oracle was generated from the same CPG.bin used by V4."
Write-Host "No V3 application-model.json was used as a V4 normalizer input."
