param(
    [string]$Source = "C:\gd-cap\java-src",
    [string]$OutputDirectory = "",
    [switch]$ReuseCpg
)

$repoRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "results\structural-probe\gd-cap-copyMany"
}

& (Join-Path $PSScriptRoot "Run-StructuralProbe.ps1") `
    -Language "java" `
    -Source $Source `
    -MethodName "copyMany" `
    -OwnerContains "gdcap.features.copy.CopyNoteMaterialFeature" `
    -OutputDirectory $OutputDirectory `
    -ReuseCpg:$ReuseCpg
