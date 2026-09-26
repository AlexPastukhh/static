param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

$pathResolved = (Resolve-Path $Path).Path
$model = Get-Content $pathResolved -Raw | ConvertFrom-Json

$errors = [System.Collections.Generic.List[string]]::new()

function Add-Error {
    param([string]$Message)
    $errors.Add($Message)
}

function Add-Unique {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string]$Value,
        [string]$Kind
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Add-Error "$Kind has an empty id/name"
        return
    }

    if (-not $Set.Add($Value)) {
        Add-Error "Duplicate $Kind: $Value"
    }
}

if ([int]$model.schemaVersion -ne 4) {
    Add-Error "schemaVersion must be 4"
}

if ($model.scope -notin @("production", "all")) {
    Add-Error "Invalid scope: $($model.scope)"
}

$typeNames = [System.Collections.Generic.HashSet[string]]::new()
$methodNames = [System.Collections.Generic.HashSet[string]]::new()
$callIds = [System.Collections.Generic.HashSet[string]]::new()
$expressionIds = [System.Collections.Generic.HashSet[string]]::new()
$controlIds = [System.Collections.Generic.HashSet[string]]::new()
$branchIds = [System.Collections.Generic.HashSet[string]]::new()

foreach ($type in @($model.types)) {
    Add-Unique $typeNames ([string]$type.fullName) "type"
}

foreach ($method in @($model.methods)) {
    Add-Unique $methodNames ([string]$method.fullName) "method"
}

foreach ($call in @($model.callSites)) {
    Add-Unique $callIds ([string]$call.id) "callSite"
}

foreach ($expression in @($model.expressions)) {
    Add-Unique $expressionIds ([string]$expression.id) "expression"
}

foreach ($control in @($model.controls)) {
    Add-Unique $controlIds ([string]$control.id) "control"

    foreach ($branch in @($control.branches)) {
        Add-Unique $branchIds ([string]$branch.id) "branch"
    }
}

$externalCount = @(
    $model.callSites |
        Where-Object { $_.classification -ne "internal" }
).Count

$summaryChecks = @(
    @("types", @($model.types).Count),
    @("methods", @($model.methods).Count),
    @("callSites", @($model.callSites).Count),
    @("externalCallSites", $externalCount),
    @("expressions", @($model.expressions).Count),
    @("controls", @($model.controls).Count)
)

foreach ($check in $summaryChecks) {
    $name = [string]$check[0]
    $actual = [int]$check[1]
    $expected = [int]$model.summary.$name

    if ($expected -ne $actual) {
        Add-Error "summary.$name does not match model: expected=$expected actual=$actual"
    }
}

function Test-StepRefs {
    param(
        [object[]]$Steps,
        [string]$Context
    )

    foreach ($step in @($Steps)) {
        $id = [string]$step.id

        switch ([string]$step.kind) {
            "EXPRESSION" {
                if (-not $expressionIds.Contains($id)) {
                    Add-Error "Dangling expression step in $Context`: $id"
                }
            }
            "CONTROL" {
                if (-not $controlIds.Contains($id)) {
                    Add-Error "Dangling control step in $Context`: $id"
                }
            }
            default {
                Add-Error "Invalid step kind in $Context`: $($step.kind)"
            }
        }
    }
}

function Test-Source {
    param(
        [object]$Source,
        [string]$Context
    )

    if (-not $Source) {
        return
    }

    if ($Source.file -match "\\") {
        Add-Error "Source path must use / separators in $Context`: $($Source.file)"
    }

    if ($null -ne $Source.line -and [int]$Source.line -lt 1) {
        Add-Error "Source line must be 1-based in $Context"
    }

    if ($null -ne $Source.column -and [int]$Source.column -lt 1) {
        Add-Error "Source column must be 1-based in $Context"
    }
}

foreach ($method in @($model.methods)) {
    Test-StepRefs @($method.body) "method $($method.fullName)"
    Test-Source $method.source "method $($method.fullName)"

    $indexes = @($method.parameters | ForEach-Object { [int]$_.index })
    if (($indexes | Sort-Object -Unique).Count -ne $indexes.Count) {
        Add-Error "Duplicate parameter index in method: $($method.fullName)"
    }

    for ($i = 0; $i -lt $indexes.Count; $i++) {
        if (($indexes | Sort-Object)[$i] -ne $i) {
            Add-Error "Parameter indexes must be normalized to 0..N-1: $($method.fullName)"
            break
        }
    }

    foreach ($parameter in @($method.parameters)) {
        Test-Source $parameter.source "parameter $($method.fullName).$($parameter.name)"
    }
}

$callExpressionCounts = @{}

foreach ($expression in @($model.expressions)) {
    $method = [string]$expression.method

    if (-not $methodNames.Contains($method)) {
        Add-Error "Expression method does not exist: $($expression.id) -> $method"
    }

    Test-Source $expression.source "expression $($expression.id)"

    foreach ($child in @($expression.children)) {
        if (-not $expressionIds.Contains([string]$child.expressionId)) {
            Add-Error "Expression child does not exist: $($expression.id) -> $($child.expressionId)"
        }
    }

    if ($expression.kind -eq "CALL") {
        if (-not $expression.callSiteId) {
            Add-Error "CALL expression has no callSiteId: $($expression.id)"
        }
        elseif (-not $callIds.Contains([string]$expression.callSiteId)) {
            Add-Error "CALL expression references missing callSite: $($expression.id) -> $($expression.callSiteId)"
        }
        else {
            $key = [string]$expression.callSiteId
            if (-not $callExpressionCounts.ContainsKey($key)) {
                $callExpressionCounts[$key] = 0
            }
            $callExpressionCounts[$key]++
        }
    }
    elseif ($expression.callSiteId) {
        Add-Error "Non-CALL expression has callSiteId: $($expression.id)"
    }
}

foreach ($call in @($model.callSites)) {
    $id = [string]$call.id

    if (-not $methodNames.Contains([string]$call.caller)) {
        Add-Error "Call caller does not exist: $id -> $($call.caller)"
    }

    if (-not $expressionIds.Contains([string]$call.expressionId)) {
        Add-Error "Call expression does not exist: $id -> $($call.expressionId)"
    }

    $expr = @(
        $model.expressions |
            Where-Object { $_.id -eq $call.expressionId }
    ) | Select-Object -First 1

    if ($expr -and $expr.callSiteId -ne $id) {
        Add-Error "Call/expression back-reference mismatch: $id <-> $($call.expressionId)"
    }

    $refCount = 0
    if ($callExpressionCounts.ContainsKey($id)) {
        $refCount = [int]$callExpressionCounts[$id]
    }

    if ($refCount -ne 1) {
        Add-Error "CallSite must be referenced by exactly one CALL expression: $id count=$refCount"
    }

    foreach ($target in @($call.dispatchTargets)) {
        if (@($call.possibleTargets) -notcontains $target) {
            Add-Error "dispatchTarget is not in possibleTargets: $id -> $target"
        }
    }

    if ($call.classification -eq "internal") {
        foreach ($target in @($call.possibleTargets)) {
            if (-not $methodNames.Contains([string]$target)) {
                Add-Error "Internal possible target does not exist: $id -> $target"
            }
        }
    }

    if (
        $call.classification -eq "unresolved-on-internal-type" -and
        -not $call.internalOwner
    ) {
        Add-Error "unresolved-on-internal-type has no internalOwner: $id"
    }
}

foreach ($control in @($model.controls)) {
    $id = [string]$control.id

    if (-not $methodNames.Contains([string]$control.method)) {
        Add-Error "Control method does not exist: $id -> $($control.method)"
    }

    Test-Source $control.source "control $id"

    foreach ($exprId in @(
        $control.conditionExpressionId,
        $control.valueExpressionId,
        $control.iterableExpressionId
    ) + @($control.initExpressionIds) + @($control.updateExpressionIds)) {

        if ($exprId -and -not $expressionIds.Contains([string]$exprId)) {
            Add-Error "Control references missing expression: $id -> $exprId"
        }
    }

    if ($control.iterationBinding) {
        Test-Source $control.iterationBinding "iteration binding $id"
    }

    if ($control.kind -eq "FOREACH") {
        if (-not $control.iterableExpressionId) {
            Add-Error "FOREACH has no iterableExpressionId: $id"
        }
        if (-not $control.iterationBinding) {
            Add-Error "FOREACH has no iterationBinding: $id"
        }
    }

    if ($control.kind -eq "IF") {
        $branchKinds = @($control.branches | ForEach-Object { $_.kind })
        if ($branchKinds -notcontains "TRUE" -or $branchKinds -notcontains "FALSE") {
            Add-Error "IF must have TRUE and FALSE branches: $id"
        }
    }

    foreach ($branch in @($control.branches)) {
        Test-StepRefs @($branch.body) "branch $($branch.id)"
        if ($branch.source) {
            Test-Source $branch.source "branch $($branch.id)"
        }
    }
}

foreach ($type in @($model.types)) {
    if ($type.file -match "\\") {
        Add-Error "Type path must use / separators: $($type.fullName) -> $($type.file)"
    }

    foreach ($base in @($type.inheritsFrom)) {
        if (-not $typeNames.Contains([string]$base)) {
            Add-Error "Internal base type missing: $($type.fullName) -> $base"
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "FAIL: $pathResolved"
    Write-Host ""

    $errors |
        Sort-Object -Unique |
        ForEach-Object { Write-Host "  - $_" }

    throw "Static Execution Model v4 validation failed with $($errors.Count) error(s)"
}

Write-Host "PASS  $pathResolved"

[pscustomobject]@{
    Language          = $model.language
    Scope             = $model.scope
    Types             = @($model.types).Count
    Methods           = @($model.methods).Count
    CallSites         = @($model.callSites).Count
    ExternalCallSites = $externalCount
    Expressions       = @($model.expressions).Count
    Controls          = @($model.controls).Count
}
