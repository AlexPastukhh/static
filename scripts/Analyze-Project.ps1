param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("java", "python", "typescript", "javascript", "csharp")]
    [string]$Language,

    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent

$sourcePath = (
    Resolve-Path $Source
).Path

$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Output
)

New-Item `
    -ItemType Directory `
    -Force `
    -Path $outputPath |
    Out-Null

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

$joernCli = Split-Path $joernBat -Parent

$frontend = switch ($Language) {
    "java" {
        Join-Path $joernCli "javasrc2cpg.bat"
    }

    "python" {
        Join-Path $joernCli "pysrc2cpg.bat"
    }

    "typescript" {
        Join-Path $joernCli "jssrc2cpg.bat"
    }

    "javascript" {
        Join-Path $joernCli "jssrc2cpg.bat"
    }

    "csharp" {
        Join-Path $joernCli "csharpsrc2cpg.bat"
    }
}

if (-not (Test-Path $frontend)) {
    throw "Frontend not found: $frontend"
}

$exportScript = Join-Path $PSScriptRoot "joern-export.sc"
$normalizer = Join-Path $PSScriptRoot "Normalize-StaticModel.ps1"

if (-not (Test-Path $exportScript)) {
    throw "Exporter not found: $exportScript"
}

if (-not (Test-Path $normalizer)) {
    throw "Normalizer not found: $normalizer"
}

$cpg = Join-Path $outputPath "cpg.bin"

if (Test-Path $cpg) {
    Remove-Item $cpg -Force
}

Write-Host ""
Write-Host "================================"
Write-Host "STATIC ANALYSIS"
Write-Host "================================"
Write-Host "Language: $Language"
Write-Host "Source:   $sourcePath"
Write-Host "Output:   $outputPath"
Write-Host ""

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
    throw "CPG was not created"
}

Write-Host ""
Write-Host "CPG:"
Get-Item $cpg |
    Select-Object FullName, Length

# Joern creates its workspace relative to the current directory,
# so run it consistently from repository root.

Push-Location $repoRoot

try {

    $workspaceProject = Join-Path $repoRoot "workspace\cpg.bin"

    if (Test-Path $workspaceProject) {
        Remove-Item $workspaceProject -Recurse -Force
    }

    $cpgJoern = $cpg.Replace('\', '/')
    $outJoern = $outputPath.Replace('\', '/')

    # Windows joern.bat requires the quotes to be part
    # of the --param argument.
    $cpgParam = '"cpgFile=' + $cpgJoern + '"'
    $outParam = '"outDir=' + $outJoern + '"'

    Write-Host ""
    Write-Host "===== 2. EXPORT CPG MODEL ====="

    & $joernBat `
        --script $exportScript `
        --param $cpgParam `
        --param $outParam

    if ($LASTEXITCODE -ne 0) {
        throw "Joern exporter failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$rawModel = Join-Path $outputPath "static-model.json"

if (-not (Test-Path $rawModel)) {
    throw "Raw static model was not created"
}

$finalModel = Join-Path $outputPath "application-model.json"

Write-Host ""
Write-Host "===== 3. NORMALIZE ====="

& $normalizer `
    -InputPath $rawModel `
    -Language $Language `
    -OutputPath $finalModel

if (-not (Test-Path $finalModel)) {
    throw "Normalized application model was not created"
}

$model = Get-Content $finalModel -Raw |
    ConvertFrom-Json

Write-Host ""
Write-Host "================================"
Write-Host "ANALYSIS COMPLETE"
Write-Host "================================"
Write-Host ""

$model.summary | Format-List

Write-Host "JSON:"
Write-Host "  $finalModel"

Write-Host ""
Write-Host "Human-readable:"
Write-Host "  $([System.IO.Path]::ChangeExtension($finalModel, '.txt'))"