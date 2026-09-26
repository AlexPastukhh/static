param(
    [string]$ModelPath,
    [string]$SourceRoot = "C:\gd-cap\java-src",
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

if (-not $ModelPath) {
    $ModelPath = Join-Path $repoRoot "results\real-projects\gd-cap\application-model.json"
}

$ModelPath = (Resolve-Path $ModelPath).Path
$templatePath = Join-Path $repoRoot "viewer\static-trace-v2.template.html"
$configPath   = Join-Path $repoRoot "config\static-trace-viewer.config.json"
$outputPath   = Join-Path $repoRoot "viewer\gd-cap-trace-v2.html"

foreach ($p in @($templatePath, $configPath, $ModelPath)) {
    if (-not (Test-Path $p)) { throw "Missing file: $p" }
}

$modelJson  = [IO.File]::ReadAllText($ModelPath).Replace("</script>", "<\/script>")
$configJson = [IO.File]::ReadAllText($configPath).Replace("</script>", "<\/script>")
$template   = [IO.File]::ReadAllText($templatePath)

$template = $template.Replace("__MODEL_JSON__", $modelJson)
$template = $template.Replace("__CONFIG_JSON__", $configJson)
$template = $template.Replace("__SOURCE_ROOT__", ($SourceRoot | ConvertTo-Json -Compress))

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($outputPath, $template, $utf8)

Write-Host ""
Write-Host "Static Trace Explorer V2"
Write-Host "Viewer: $outputPath"
Write-Host "Config: $configPath"
Write-Host "Vision: $(Join-Path $repoRoot 'docs\STATIC_TRACE_EXPLORER_VISION.md')"
Write-Host ""

if (-not $NoOpen) {
    $browser = @(
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    $url = "file:///" + ($outputPath -replace '\\','/')
    if ($browser) { Start-Process $browser $url } else { Invoke-Item $outputPath }
}
