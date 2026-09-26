$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$probe = Join-Path $PSScriptRoot "Run-StructuralProbe.ps1"

$jobs = @(
    @{
        Language = "python"
        Source = Join-Path $repoRoot "fixtures\structural-probe\python-src"
        MethodName = "exercise_structural_probe"
        Output = Join-Path $repoRoot "results\structural-probe\python-control-fixture-v3"
    },
    @{
        Language = "typescript"
        Source = Join-Path $repoRoot "fixtures\structural-probe\typescript-src"
        MethodName = "exerciseStructuralProbe"
        Output = Join-Path $repoRoot "results\structural-probe\typescript-control-fixture-v3"
    },
    @{
        Language = "csharp"
        Source = Join-Path $repoRoot "fixtures\structural-probe\csharp-src"
        MethodName = "ExerciseStructuralProbe"
        Output = Join-Path $repoRoot "results\structural-probe\csharp-control-fixture-v3"
    }
)

foreach ($job in $jobs) {
    & $probe `
        -Language $job.Language `
        -Source $job.Source `
        -MethodName $job.MethodName `
        -OwnerContains "" `
        -OutputDirectory $job.Output

    if ($LASTEXITCODE -ne 0) {
        throw "Structural probe failed for $($job.Language)"
    }
}

Write-Host ""
Write-Host "================================"
Write-Host "POLYGLOT PROBES COMPLETE"
Write-Host "================================"
Write-Host ""
Write-Host (Join-Path $repoRoot "results\structural-probe\python-control-fixture-v3\structural-probe.json")
Write-Host (Join-Path $repoRoot "results\structural-probe\typescript-control-fixture-v3\structural-probe.json")
Write-Host (Join-Path $repoRoot "results\structural-probe\csharp-control-fixture-v3\structural-probe.json")
