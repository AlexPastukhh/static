$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$templatePath = Join-Path $repoRoot "viewer\static-trace-v2.template.html"

if (-not (Test-Path $templatePath)) {
    throw "Missing template: $templatePath"
}

$html = [IO.File]::ReadAllText($templatePath)

$before = 'replaceAll("\\\\","/")'
$after  = 'replaceAll("\\","/")'

$countBefore = ([regex]::Matches($html, [regex]::Escape($before))).Count

if ($countBefore -eq 0) {
    throw "Expected broken Windows-path replacement was not found in template."
}

$html = $html.Replace($before, $after)

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($templatePath, $html, $utf8)

Write-Host "Fixed Windows path normalization."
Write-Host "Replacements: $countBefore"
Write-Host "Template: $templatePath"
Write-Host ""

$createScript = Join-Path $repoRoot "scripts\Create-StaticTraceExplorerV2.ps1"
if (-not (Test-Path $createScript)) {
    throw "Missing create script: $createScript"
}

& $createScript
