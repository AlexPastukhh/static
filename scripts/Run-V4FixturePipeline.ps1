param(
    [switch]$ReuseCpg
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$exporter = Join-Path $PSScriptRoot "Export-StructuralModelV4.ps1"

if (-not (Test-Path $exporter)) {
    throw "Missing exporter: $exporter"
}

$jobs = @(
    @{
        Language = "java"
        Source = Join-Path $repoRoot "fixtures\structural-probe\java-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\java"
    },
    @{
        Language = "python"
        Source = Join-Path $repoRoot "fixtures\structural-probe\python-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\python"
    },
    @{
        Language = "typescript"
        Source = Join-Path $repoRoot "fixtures\structural-probe\typescript-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\typescript"
    },
    @{
        Language = "csharp"
        Source = Join-Path $repoRoot "fixtures\structural-probe\csharp-src"
        Output = Join-Path $repoRoot "results\v4-fixtures\csharp"
    }
)

$results = @()

foreach ($job in $jobs) {
    Write-Host ""
    Write-Host "================================"
    Write-Host ("RAW FIXTURE: " + $job.Language.ToUpperInvariant())
    Write-Host "================================"

    $params = @{
        Language = $job.Language
        Source = $job.Source
        OutputDirectory = $job.Output
    }

    if ($ReuseCpg) {
        $params.ReuseCpg = $true
    }

    & $exporter @params

    $rawPath = Join-Path $job.Output "raw-structural-model-v4.json"

    if (-not (Test-Path $rawPath)) {
        throw "Fixture raw model missing: $rawPath"
    }

    $raw = Get-Content $rawPath -Raw | ConvertFrom-Json

    $results += [pscustomobject]@{
        Language = $job.Language
        Types = [int]$raw.summary.types
        Methods = [int]$raw.summary.methods
        AstNodes = [int]$raw.summary.astNodes
        Calls = [int]$raw.summary.callsIncludingOperators
        Controls = [int]$raw.summary.controlStructures
        RawModel = $rawPath
    }
}

Write-Host ""
Write-Host "================================"
Write-Host "V4 FIXTURE PIPELINE - PHASE A"
Write-Host "================================"
Write-Host ""
$results | Format-Table -AutoSize
Write-Host ""
Write-Host "Phase A complete: all-method raw exports are parseable."
Write-Host "Semantic v4 normalization is the next implementation phase."
