param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("java", "python", "typescript", "javascript", "csharp")]
    [string]$Language,

    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$MethodName,

    [string]$OwnerContains = "",

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [switch]$ReuseCpg
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = (Resolve-Path $Source).Path
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)

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

$probeScript = Join-Path $PSScriptRoot "joern-structural-probe.sc"

if (-not (Test-Path $probeScript)) {
    throw "Probe script not found: $probeScript"
}

$cpg = Join-Path $outputPath "cpg.bin"
$outJson = Join-Path $outputPath "structural-probe.json"

Write-Host ""
Write-Host "================================"
Write-Host "JOERN STRUCTURAL PROBE V3"
Write-Host "================================"
Write-Host "Language:       $Language"
Write-Host "Source:         $sourcePath"
Write-Host "Method:         $MethodName"
Write-Host "Owner contains: $OwnerContains"
Write-Host "Output:         $outputPath"
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

    $cpgParam = '"cpgFile=' + $cpgJoern + '"'
    $outParam = '"outFile=' + $outJoern + '"'
    $methodParam = '"methodName=' + $MethodName + '"'
    $ownerParam = '"ownerContains=' + $OwnerContains + '"'

    Write-Host ""
    Write-Host "===== 2. EXPORT RAW STRUCTURE ====="

    & $joernBat `
        --script $probeScript `
        --param $cpgParam `
        --param $outParam `
        --param $methodParam `
        --param $ownerParam

    if ($LASTEXITCODE -ne 0) {
        throw "Joern structural probe failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $outJson)) {
    throw "Probe JSON was not created: $outJson"
}

Write-Host ""
Write-Host "===== 3. VALIDATE JSON ====="

$probe = Get-Content $outJson -Raw | ConvertFrom-Json

if ([int]$probe.probeVersion -ne 3) {
    throw "Unexpected probe version: $($probe.probeVersion)"
}

if ($probe.method.name -ne $MethodName) {
    throw "Unexpected method in probe: $($probe.method.name)"
}

Write-Host ""
Write-Host "================================"
Write-Host "PROBE COMPLETE"
Write-Host "================================"
Write-Host ("Method:       " + $probe.method.fullName)
Write-Host ("Owner:        " + $probe.method.owner)
Write-Host ("AST nodes:    " + $probe.summary.astNodes)
Write-Host ("Calls:        " + $probe.summary.callsIncludingOperators)
Write-Host ("Controls:     " + $probe.summary.controlStructures)
Write-Host ("CFG nodes:    " + $probe.summary.cfgNodes)
Write-Host ("CFG edges:    " + $probe.summary.cfgEdges)
Write-Host ""
Write-Host "JSON:"
Write-Host $outJson
