param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

$pathResolved = (
    Resolve-Path $Path
).Path

$model = Get-Content $pathResolved -Raw | ConvertFrom-Json

$errors = [System.Collections.Generic.List[string]]::new()

function Add-Error {
    param([string]$Message)
    $errors.Add($Message)
}

if ($model.schemaVersion -ne 3) {
    Add-Error "schemaVersion must be 3"
}

if ($model.scope -notin @("production", "all")) {
    Add-Error "Invalid scope: $($model.scope)"
}

$typeNames = [System.Collections.Generic.HashSet[string]]::new()

foreach ($type in @($model.types)) {
    if (-not $typeNames.Add([string]$type.fullName)) {
        Add-Error "Duplicate type: $($type.fullName)"
    }
}

$methodNames = [System.Collections.Generic.HashSet[string]]::new()

foreach ($method in @($model.methods)) {
    if (-not $methodNames.Add([string]$method.fullName)) {
        Add-Error "Duplicate method: $($method.fullName)"
    }
}

# Summary consistency

if ([int]$model.summary.types -ne @($model.types).Count) {
    Add-Error "summary.types does not match types array"
}

if ([int]$model.summary.methods -ne @($model.methods).Count) {
    Add-Error "summary.methods does not match methods array"
}

if ([int]$model.summary.internalCalls -ne @($model.calls).Count) {
    Add-Error "summary.internalCalls does not match calls array"
}

if ([int]$model.summary.externalCalls -ne @($model.externalCalls).Count) {
    Add-Error "summary.externalCalls does not match externalCalls array"
}

# Type hierarchy

foreach ($type in @($model.types)) {

    foreach ($base in @($type.inheritsFrom)) {

        if (-not $typeNames.Contains([string]$base)) {
            Add-Error "Internal base type missing: $($type.fullName) -> $base"
        }
    }
}

# Internal calls

foreach ($call in @($model.calls)) {

    if (-not $methodNames.Contains([string]$call.caller)) {
        Add-Error "Caller does not exist: $($call.caller)"
    }

    foreach ($target in @($call.possibleTargets)) {

        if (-not $methodNames.Contains([string]$target)) {
            Add-Error "Possible target does not exist: $target"
        }
    }

    foreach ($target in @($call.dispatchTargets)) {

        if (@($call.possibleTargets) -notcontains $target) {
            Add-Error "dispatchTarget is not in possibleTargets: $target"
        }

        if (
            $call.declaredTarget -and
            $target -eq $call.declaredTarget
        ) {
            Add-Error "dispatchTargets contains declaredTarget: $target"
        }
    }
}

# External calls must still have internal callers

foreach ($call in @($model.externalCalls)) {

    if (-not $methodNames.Contains([string]$call.caller)) {
        Add-Error "External call caller does not exist: $($call.caller)"
    }

    if (
        $call.classification -eq "unresolved-on-internal-type" -and
        -not $call.internalOwner
    ) {
        Add-Error "unresolved-on-internal-type has no internalOwner"
    }
}

# Production model must not leak tests

if ($model.scope -eq "production") {

    foreach ($method in @($model.methods)) {

        if (
            $method.file -match '(^|[\\/])(test|tests|testing)([\\/]|$)' -or
            $method.fullName -match '(^|[.:\\/])(test|tests|testing)([.:\\/]|$)'
        ) {
            Add-Error "Test method leaked into production model: $($method.fullName)"
        }
    }

    foreach ($call in @($model.calls)) {

        foreach ($target in @($call.possibleTargets)) {

            if (
                $target -match '(^|[.:\\/])(test|tests|testing)([.:\\/]|$)'
            ) {
                Add-Error "Test target leaked into production model: $target"
            }
        }
    }
}

if ($errors.Count -gt 0) {

    Write-Host ""
    Write-Host "FAIL: $pathResolved"
    Write-Host ""

    $errors |
        Sort-Object -Unique |
        ForEach-Object {
            Write-Host "  - $_"
        }

    throw "Application model validation failed with $($errors.Count) error(s)"
}

Write-Host "PASS  $pathResolved"

[pscustomobject]@{
    Language      = $model.language
    Scope         = $model.scope
    Types         = @($model.types).Count
    Methods       = @($model.methods).Count
    InternalCalls = @($model.calls).Count
    ExternalCalls = @($model.externalCalls).Count
}