param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("java", "python", "typescript", "javascript", "csharp")]
    [string]$Language,

    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [switch]$ReuseCpg
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = (Resolve-Path $Source).Path
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $OutputDirectory
)

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$joernBat = (
    Get-ChildItem `
        (Join-Path $repoRoot "tools\joern") `
        -Recurse `
        -Filter "joern.bat" |
    Select-Object -First 1
).FullName

if (-not $joernBat) {
    throw "joern.bat not found under $repoRoot\tools\joern"
}

$joernCli = Split-Path $joernBat -Parent

$frontend = switch ($Language) {
    "java"       { Join-Path $joernCli "javasrc2cpg.bat" }
    "python"     { Join-Path $joernCli "pysrc2cpg.bat" }
    "typescript" { Join-Path $joernCli "jssrc2cpg.bat" }
    "javascript" { Join-Path $joernCli "jssrc2cpg.bat" }
    "csharp"     { Join-Path $joernCli "csharpsrc2cpg.bat" }
}

if (-not (Test-Path $frontend)) {
    throw "Frontend not found: $frontend"
}

$exportScript = Join-Path $PSScriptRoot "joern-structural-export-v4.sc"

if (-not (Test-Path $exportScript)) {
    throw "V4 structural exporter not found: $exportScript"
}

$cpg = Join-Path $outputPath "cpg.bin"
$outJson = Join-Path $outputPath "raw-structural-model-v4.json"

Write-Host ""
Write-Host "================================"
Write-Host "V4 RAW STRUCTURAL EXPORT"
Write-Host "================================"
Write-Host "Language: $Language"
Write-Host "Source:   $sourcePath"
Write-Host "Output:   $outputPath"
Write-Host ""

if (-not $ReuseCpg -or -not (Test-Path $cpg)) {
    if (Test-Path $cpg) {
        Remove-Item $cpg -Force
    }

    Write-Host "===== 1. BUILD CPG ====="

    if ($Language -eq "typescript" -or $Language -eq "javascript") {
        & $frontend `
            --exclude "node_modules" `
            --exclude "dist" `
            -o $cpg `
            $sourcePath
    }
    elseif ($Language -eq "java") {
        & $frontend `
            --enable-file-content `
            -o $cpg `
            $sourcePath
    }
    else {
        & $frontend `
            -o $cpg `
            $sourcePath
    }

    if ($LASTEXITCODE -ne 0) {
        throw "CPG frontend failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path $cpg)) {
        throw "CPG was not created: $cpg"
    }
}
else {
    Write-Host "===== 1. REUSE CPG ====="
    Write-Host $cpg
}

Push-Location $repoRoot

try {
    $workspaceProject = Join-Path $repoRoot "workspace\cpg.bin"

    if (Test-Path $workspaceProject) {
        Remove-Item $workspaceProject -Recurse -Force
    }

    $cpgJoern = $cpg.Replace('\', '/')
    $outJoern = $outJson.Replace('\', '/')

    # Windows joern.bat requires quotes to be part of each --param argument.
    $cpgParam = '"cpgFile=' + $cpgJoern + '"'
    $outParam = '"outFile=' + $outJoern + '"'

    Write-Host ""
    Write-Host "===== 2. EXPORT ALL-METHOD RAW STRUCTURE ====="

    & $joernBat `
        --script $exportScript `
        --param $cpgParam `
        --param $outParam

    if ($LASTEXITCODE -ne 0) {
        throw "Joern v4 structural exporter failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $outJson)) {
    throw "Raw v4 structural JSON was not created: $outJson"
}

Write-Host ""
Write-Host "===== 3. VALIDATE RAW JSON ====="

$raw = Get-Content $outJson -Raw | ConvertFrom-Json

if ([int]$raw.rawStructuralVersion -ne 1) {
    throw "Unexpected raw structural version: $($raw.rawStructuralVersion)"
}

if (@($raw.methods).Count -ne [int]$raw.summary.methods) {
    throw "Raw summary.methods mismatch"
}

if (@($raw.types).Count -ne [int]$raw.summary.types) {
    throw "Raw summary.types mismatch"
}

$methodCalls = @(
    $raw.methods |
        ForEach-Object { @($_.calls).Count } |
        Measure-Object -Sum
).Sum

if ([int]$methodCalls -ne [int]$raw.summary.callsIncludingOperators) {
    throw "Raw summary.callsIncludingOperators mismatch"
}

$methodControls = @(
    $raw.methods |
        ForEach-Object { @($_.controlStructures).Count } |
        Measure-Object -Sum
).Sum

if ([int]$methodControls -ne [int]$raw.summary.controlStructures) {
    throw "Raw summary.controlStructures mismatch"
}

Write-Host ""
Write-Host "================================"
Write-Host "V4 RAW EXPORT COMPLETE"
Write-Host "================================"
Write-Host ("Types:      " + $raw.summary.types)
Write-Host ("Methods:    " + $raw.summary.methods)
Write-Host ("AST nodes:  " + $raw.summary.astNodes)
Write-Host ("Calls:      " + $raw.summary.callsIncludingOperators)
Write-Host ("Controls:   " + $raw.summary.controlStructures)
Write-Host ""
Write-Host "JSON:"
Write-Host $outJson
