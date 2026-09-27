param(
    [Parameter(Mandatory = $true)]
    [string]$V3ModelPath,

    [Parameter(Mandatory = $true)]
    [string]$V4ModelPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$V3ModelPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($V3ModelPath)
$V4ModelPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($V4ModelPath)
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

foreach ($path in @($V3ModelPath, $V4ModelPath)) {
    if (-not (Test-Path $path)) {
        throw "Model not found: $path"
    }
}

$outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
if ($outputDirectory) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$v3 = Get-Content $V3ModelPath -Raw | ConvertFrom-Json
$v4 = Get-Content $V4ModelPath -Raw | ConvertFrom-Json

if ([int]$v3.schemaVersion -ne 3) {
    throw "Expected v3 model"
}

if ([int]$v4.schemaVersion -ne 4) {
    throw "Expected v4 model"
}

if ([string]$v3.language -ne [string]$v4.language) {
    throw "Language mismatch"
}

if ([string]$v3.scope -ne [string]$v4.scope) {
    throw "Scope mismatch"
}

function Get-SortedUniqueStrings {
    param([object[]]$Values)

    return @(
        $Values |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function New-InternalSignature {
    param(
        [string]$Caller,
        [object]$Line,
        [string]$DeclaredTarget,
        [object[]]$DispatchTargets,
        [object[]]$PossibleTargets,
        [object[]]$UnresolvedTargets,
        [string]$Resolution
    )

    $payload = [ordered]@{
        caller            = $Caller
        line              = $(if ($null -eq $Line) { $null } else { [int]$Line })
        classification    = "internal"
        declaredTarget    = $(if ([string]::IsNullOrWhiteSpace($DeclaredTarget)) { $null } else { $DeclaredTarget })
        dispatchTargets   = @(Get-SortedUniqueStrings $DispatchTargets)
        possibleTargets   = @(Get-SortedUniqueStrings $PossibleTargets)
        unresolvedTargets = @(Get-SortedUniqueStrings $UnresolvedTargets)
        resolution        = $Resolution
    }

    return ($payload | ConvertTo-Json -Depth 20 -Compress)
}

function New-ExternalSignature {
    param(
        [string]$Caller,
        [object]$Line,
        [string]$Classification,
        [object[]]$Targets,
        [string]$InternalOwner,
        [object[]]$UnresolvedBaseHints
    )

    $payload = [ordered]@{
        caller              = $Caller
        line                = $(if ($null -eq $Line) { $null } else { [int]$Line })
        classification      = $Classification
        targets             = @(Get-SortedUniqueStrings $Targets)
        internalOwner       = $(if ([string]::IsNullOrWhiteSpace($InternalOwner)) { $null } else { $InternalOwner })
        unresolvedBaseHints = @(Get-SortedUniqueStrings $UnresolvedBaseHints)
    }

    return ($payload | ConvertTo-Json -Depth 20 -Compress)
}

function Test-KnownV3OnlyLowering {
    param([object]$Record)

    $code = [string]$Record.code

    if (
        $code -match '\$iterLocal' -or
        $code -match 'iteratorNonEmptyOrException' -or
        $code -match '(^|[^A-Za-z0-9_])tmp[0-9]+([^A-Za-z0-9_]|$)' -or
        $code -match '_iterator_' -or
        $code -match '_result_' -or
        $code -match '(^|[^A-Za-z0-9_])_idx_([^A-Za-z0-9_]|$)' -or
        $code -match '\.hasNext\s*\(' -or
        $code -match '\.next\s*\(' -or
        $code -match '__next__\s*\(' -or
        $code -match '__iter__\s*\(' -or
        $code -match '\.iterator\s*\('
    ) {
        return $true
    }

    $targets = @()

    if ($Record.classification -eq "internal") {
        $targets += @($Record.possibleTargets)
        $targets += @($Record.unresolvedTargets)
        if ($Record.declaredTarget) {
            $targets += @($Record.declaredTarget)
        }
    }
    else {
        $targets += @($Record.targets)
    }

    foreach ($targetValue in $targets) {
        $target = [string]$targetValue

        if (
            $target -match '(^|[.:])hasNext([:(]|$)' -or
            $target -match '(^|[.:])next([:(]|$)' -or
            $target -match '(^|[.:])__next__([:(]|$)' -or
            $target -match '(^|[.:])__iter__([:(]|$)' -or
            $target -match '(^|[.:])iterator([:(]|$)' -or
            $target -match 'iteratorNonEmptyOrException'
        ) {
            return $true
        }
    }

    return $false
}

$v3Methods = [System.Collections.Generic.HashSet[string]]::new()
foreach ($method in @($v3.methods)) {
    [void]$v3Methods.Add([string]$method.fullName)
}

$v4Methods = [System.Collections.Generic.HashSet[string]]::new()
foreach ($method in @($v4.methods)) {
    [void]$v4Methods.Add([string]$method.fullName)
}

$sharedMethods = [System.Collections.Generic.HashSet[string]]::new()
foreach ($name in $v4Methods) {
    if ($v3Methods.Contains($name)) {
        [void]$sharedMethods.Add($name)
    }
}

$v3OnlyMethods = @(
    $v3Methods |
        Where-Object { -not $v4Methods.Contains($_) } |
        Sort-Object
)

$v4OnlyMethods = @(
    $v4Methods |
        Where-Object { -not $v3Methods.Contains($_) } |
        Sort-Object
)

$v3Records = [System.Collections.Generic.List[object]]::new()
$v4Records = [System.Collections.Generic.List[object]]::new()

$ignoredV3NonSharedCaller = 0
$ignoredV4NonSharedCaller = 0
$ignoredV4NoTargetEvidence = 0

foreach ($call in @($v3.calls)) {
    $caller = [string]$call.caller

    if (-not $sharedMethods.Contains($caller)) {
        $ignoredV3NonSharedCaller++
        continue
    }

    $signature = New-InternalSignature `
        $caller `
        $call.line `
        ([string]$call.declaredTarget) `
        @($call.dispatchTargets) `
        @($call.possibleTargets) `
        @($call.unresolvedTargets) `
        ([string]$call.resolution)

    $v3Records.Add(
        [pscustomobject]@{
            signature      = $signature
            classification = "internal"
            caller         = $caller
            line           = $call.line
            code           = [string]$call.code
            declaredTarget = [string]$call.declaredTarget
            possibleTargets = @($call.possibleTargets)
            unresolvedTargets = @($call.unresolvedTargets)
            targets        = @()
        }
    )
}

foreach ($call in @($v3.externalCalls)) {
    $caller = [string]$call.caller

    if (-not $sharedMethods.Contains($caller)) {
        $ignoredV3NonSharedCaller++
        continue
    }

    $signature = New-ExternalSignature `
        $caller `
        $call.line `
        ([string]$call.classification) `
        @($call.targets) `
        ([string]$call.internalOwner) `
        @($call.unresolvedBaseHints)

    $v3Records.Add(
        [pscustomobject]@{
            signature      = $signature
            classification = [string]$call.classification
            caller         = $caller
            line           = $call.line
            code           = [string]$call.code
            declaredTarget = ""
            possibleTargets = @()
            unresolvedTargets = @()
            targets        = @($call.targets)
        }
    )
}

$expressionById = @{}
foreach ($expression in @($v4.expressions)) {
    $expressionById[[string]$expression.id] = $expression
}

foreach ($call in @($v4.callSites)) {
    $caller = [string]$call.caller

    if (-not $sharedMethods.Contains($caller)) {
        $ignoredV4NonSharedCaller++
        continue
    }

    $code = ""
    if ($expressionById.ContainsKey([string]$call.expressionId)) {
        $code = [string]$expressionById[[string]$call.expressionId].source.text
    }

    $line = $null
    if ($expressionById.ContainsKey([string]$call.expressionId)) {
        $line = $expressionById[[string]$call.expressionId].source.line
    }

    if ([string]$call.classification -eq "internal") {
        $signature = New-InternalSignature `
            $caller `
            $line `
            ([string]$call.declaredTarget) `
            @($call.dispatchTargets) `
            @($call.possibleTargets) `
            @($call.unresolvedTargets) `
            ([string]$call.resolution)

        $v4Records.Add(
            [pscustomobject]@{
                signature      = $signature
                classification = "internal"
                caller         = $caller
                line           = $line
                code           = $code
                id             = [string]$call.id
            }
        )

        continue
    }

    $targets = @(Get-SortedUniqueStrings @($call.possibleTargets))

    if (
        $targets.Count -eq 0 -and
        @($call.unresolvedTargets).Count -eq 0 -and
        [string]::IsNullOrWhiteSpace([string]$call.declaredTarget)
    ) {
        $ignoredV4NoTargetEvidence++
        continue
    }

    $signature = New-ExternalSignature `
        $caller `
        $line `
        ([string]$call.classification) `
        @($targets) `
        ([string]$call.internalOwner) `
        @($call.unresolvedBaseHints)

    $v4Records.Add(
        [pscustomobject]@{
            signature      = $signature
            classification = [string]$call.classification
            caller         = $caller
            line           = $line
            code           = $code
            id             = [string]$call.id
        }
    )
}

$v3Buckets = @{}
foreach ($record in @($v3Records)) {
    $key = [string]$record.signature

    if (-not $v3Buckets.ContainsKey($key)) {
        $v3Buckets[$key] = [System.Collections.Generic.List[object]]::new()
    }

    $v3Buckets[$key].Add($record)
}

$mismatches = [System.Collections.Generic.List[object]]::new()
$matched = 0

foreach ($record in @($v4Records)) {
    $key = [string]$record.signature

    if (
        $v3Buckets.ContainsKey($key) -and
        $v3Buckets[$key].Count -gt 0
    ) {
        $v3Buckets[$key].RemoveAt(0)
        $matched++
        continue
    }

    $mismatches.Add(
        [pscustomobject][ordered]@{
            caller         = [string]$record.caller
            line           = $record.line
            code           = [string]$record.code
            classification = [string]$record.classification
            v4CallSiteId   = [string]$record.id
            signature      = [string]$record.signature
        }
    )
}

$knownV3OnlyLowering = [System.Collections.Generic.List[object]]::new()
$unexpectedV3Only = [System.Collections.Generic.List[object]]::new()

foreach ($key in @($v3Buckets.Keys)) {
    foreach ($record in @($v3Buckets[$key])) {
        $entry = [pscustomobject][ordered]@{
            caller         = [string]$record.caller
            line           = $record.line
            code           = [string]$record.code
            classification = [string]$record.classification
            signature      = [string]$record.signature
        }

        if (Test-KnownV3OnlyLowering $record) {
            $knownV3OnlyLowering.Add($entry)
        }
        else {
            $unexpectedV3Only.Add($entry)
        }
    }
}

$result = if (
    $mismatches.Count -eq 0 -and
    $unexpectedV3Only.Count -eq 0
) {
    "PASS"
}
else {
    "FAIL"
}

$report = [ordered]@{
    gate                       = "v3-v4-target-resolution"
    language                   = [string]$v4.language
    scope                      = [string]$v4.scope
    sharedMethods              = $sharedMethods.Count
    v3OnlyMethods              = @($v3OnlyMethods)
    v4OnlyMethods              = @($v4OnlyMethods)
    v3ComparableCalls          = $v3Records.Count
    v4ComparableCalls          = $v4Records.Count
    matchedV4Calls             = $matched
    ignoredV3NonSharedCaller   = $ignoredV3NonSharedCaller
    ignoredV4NonSharedCaller   = $ignoredV4NonSharedCaller
    ignoredV4NoTargetEvidence  = $ignoredV4NoTargetEvidence
    knownV3OnlyLoweringCount   = $knownV3OnlyLowering.Count
    unexpectedV3OnlyCount      = $unexpectedV3Only.Count
    v4MismatchCount            = $mismatches.Count
    v4Mismatches               = @($mismatches)
    knownV3OnlyLowering        = @($knownV3OnlyLowering)
    unexpectedV3Only           = @($unexpectedV3Only)
    result                     = $result
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
    $OutputPath,
    ($report | ConvertTo-Json -Depth 40),
    $utf8NoBom
)

Write-Host ""
Write-Host "TARGET RESOLUTION PARITY"
Write-Host "------------------------"
Write-Host ("Language:                    " + $report.language)
Write-Host ("Shared methods:              " + $report.sharedMethods)
Write-Host ("V3 comparable calls:         " + $report.v3ComparableCalls)
Write-Host ("V4 comparable calls:         " + $report.v4ComparableCalls)
Write-Host ("Matched V4 calls:            " + $report.matchedV4Calls)
Write-Host ("Known V3-only lowering:      " + $report.knownV3OnlyLoweringCount)
Write-Host ("Unexpected V3-only calls:    " + $report.unexpectedV3OnlyCount)
Write-Host ("V4 mismatches:               " + $report.v4MismatchCount)
Write-Host ("Result:                      " + $report.result)
Write-Host ("Report:                      " + $OutputPath)

if ($result -ne "PASS") {
    throw "V3/V4 target-resolution parity failed for $($report.language)"
}
