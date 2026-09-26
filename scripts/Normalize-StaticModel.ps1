param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$Language,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [switch]$IncludeTests
)

$ErrorActionPreference = "Stop"

$InputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $InputPath
)

$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $OutputPath
)

$outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)

if ($outputDirectory) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$model = Get-Content $InputPath -Raw | ConvertFrom-Json

# ============================================================
# FILTERS
# ============================================================

function Test-SyntheticMethodName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $true
    }

    if ($Name -in @(
        "<module>",
        "<body>",
        "<fakeNew>",
        "<metaClassCallHandler>"
    )) {
        return $true
    }

    if ($Name -match "<metaClassAdapter>|<meta>$") {
        return $true
    }

    return $false
}

function Test-SyntheticTypeName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $true
    }

    if ($Name -in @(
        "<module>",
        "<body>",
        "<fakeNew>",
        "<metaClassCallHandler>",
        ":program"
    )) {
        return $true
    }

    if ($Name -match "<metaClassAdapter>|<meta>$") {
        return $true
    }

    return $false
}

function Test-IsTestArtifact {
    param(
        [string]$File,
        [string]$FullName
    )

    if (
        $File -and
        $File -match '(^|[\\/])(test|tests|testing)([\\/]|$)'
    ) {
        return $true
    }

    if (
        $FullName -and
        $FullName -match '(^|[.:\\/])(test|tests|testing)([.:\\/]|$)'
    ) {
        return $true
    }

    return $false
}

function Test-IsTestTarget {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return $false
    }

    return $Target -match '(^|[.:\\/])(test|tests|testing)([.:\\/]|$)'
}

$excludedTestMethods = @(
    $model.methods |
        Where-Object {
            Test-IsTestArtifact `
                ([string]$_.file) `
                ([string]$_.fullName)
        }
).Count

$excludedTestTypes = @(
    $model.types |
        Where-Object {
            Test-IsTestArtifact `
                ([string]$_.file) `
                ([string]$_.fullName)
        }
).Count

# ============================================================
# METHODS
# ============================================================

$cleanMethods = @(
    $model.methods |
        Where-Object {

            if (Test-SyntheticMethodName ([string]$_.name)) {
                return $false
            }

            if (
                -not $IncludeTests -and
                (Test-IsTestArtifact `
                    ([string]$_.file) `
                    ([string]$_.fullName))
            ) {
                return $false
            }

            return $true
        }
)

$methodFullNames = [System.Collections.Generic.HashSet[string]]::new()

foreach ($method in $cleanMethods) {
    [void]$methodFullNames.Add([string]$method.fullName)
}

# ============================================================
# TYPES
# ============================================================

$cleanTypes = @(
    $model.types |
        Where-Object {

            if (Test-SyntheticTypeName ([string]$_.name)) {
                return $false
            }

            # Python / JS can expose method-like TYPE_DECL nodes.
            if ($methodFullNames.Contains([string]$_.fullName)) {
                return $false
            }

            if (
                -not $IncludeTests -and
                (Test-IsTestArtifact `
                    ([string]$_.file) `
                    ([string]$_.fullName))
            ) {
                return $false
            }

            return $true
        }
)

function Resolve-TypeFullName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    if ($Name -eq "ANY") {
        return $null
    }

    $exact = @(
        $cleanTypes |
            Where-Object {
                $_.fullName -eq $Name
            }
    )

    if ($exact.Count -eq 1) {
        return [string]$exact[0].fullName
    }

    $byName = @(
        $cleanTypes |
            Where-Object {
                $_.name -eq $Name
            }
    )

    if ($byName.Count -eq 1) {
        return [string]$byName[0].fullName
    }

    $suffix = @(
        $cleanTypes |
            Where-Object {
                $_.fullName -like "*.$Name" -or
                $_.fullName -like "*:$Name"
            }
    )

    if ($suffix.Count -eq 1) {
        return [string]$suffix[0].fullName
    }

    return $null
}

$types = @(
    foreach ($type in $cleanTypes) {

        $internalBases = [System.Collections.Generic.HashSet[string]]::new()
        $unresolvedBases = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($base in @($type.inheritsFrom)) {

            $rawBase = [string]$base

            if (
                [string]::IsNullOrWhiteSpace($rawBase) -or
                $rawBase -eq "ANY"
            ) {
                continue
            }

            $resolved = Resolve-TypeFullName $rawBase

            if ($resolved) {
                [void]$internalBases.Add($resolved)
            }
            else {
                [void]$unresolvedBases.Add($rawBase)
            }
        }

        [pscustomobject]@{
            name            = [string]$type.name
            fullName        = [string]$type.fullName
            file            = [string]$type.file
            inheritsFrom    = @($internalBases | Sort-Object)
            unresolvedBases = @($unresolvedBases | Sort-Object)
        }
    }
)

$methods = @(
    foreach ($method in $cleanMethods) {

        [pscustomobject]@{
            name       = [string]$method.name
            fullName   = [string]$method.fullName
            owner      = [string]$method.owner
            file       = [string]$method.file
            line       = $method.line
            conditions = @($method.conditions)
        }
    }
)

# ============================================================
# SIGNATURE HELPERS
# ============================================================

function Get-ParameterArity {
    param([string]$FullName)

    if ([string]::IsNullOrWhiteSpace($FullName)) {
        return $null
    }

    $open = $FullName.LastIndexOf("(")
    $close = $FullName.LastIndexOf(")")

    if (
        $open -lt 0 -or
        $close -lt $open
    ) {
        return $null
    }

    $inside = $FullName.Substring(
        $open + 1,
        $close - $open - 1
    )

    if ([string]::IsNullOrWhiteSpace($inside)) {
        return 0
    }

    $angle = 0
    $square = 0
    $paren = 0
    $count = 1

    foreach ($ch in $inside.ToCharArray()) {

        switch ($ch) {
            '<' { $angle++ }
            '>' {
                if ($angle -gt 0) {
                    $angle--
                }
            }
            '[' { $square++ }
            ']' {
                if ($square -gt 0) {
                    $square--
                }
            }
            '(' { $paren++ }
            ')' {
                if ($paren -gt 0) {
                    $paren--
                }
            }
            ',' {
                if (
                    $angle -eq 0 -and
                    $square -eq 0 -and
                    $paren -eq 0
                ) {
                    $count++
                }
            }
        }
    }

    return $count
}

function Test-TargetAliasMatch {
    param(
        [string]$Target,
        [string]$Alias
    )

    if (
        [string]::IsNullOrWhiteSpace($Target) -or
        [string]::IsNullOrWhiteSpace($Alias)
    ) {
        return $false
    }

    if ($Target -eq $Alias) {
        return $true
    }

    # IMPORTANT:
    # Require an actual method-signature boundary.
    #
    # This prevents:
    #
    #   SavedImagesDialog.show.DefaultTableModel$0.<init>
    #
    # from matching:
    #
    #   SavedImagesDialog.show
    #
    if ($Target.StartsWith($Alias + ":")) {
        return $true
    }

    if ($Target.StartsWith($Alias + "(")) {
        return $true
    }

    return $false
}

function Resolve-TargetMethod {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return @()
    }

    if ($Target -eq "<unknownFullName>") {
        return @()
    }

    # Exact match always wins.
    $exact = @(
        $methods |
            Where-Object {
                $_.fullName -eq $Target
            }
    )

    if ($exact.Count -gt 0) {
        return @($exact)
    }

    $candidates = @(
        foreach ($method in $methods) {

            $owner = [string]$method.owner
            $name = [string]$method.name

            if (
                [string]::IsNullOrWhiteSpace($owner) -or
                [string]::IsNullOrWhiteSpace($name)
            ) {
                continue
            }

            $dotAlias = $owner + "." + $name
            $colonAlias = $owner + ":" + $name

            if (
                (Test-TargetAliasMatch $Target $dotAlias) -or
                (Test-TargetAliasMatch $Target $colonAlias)
            ) {
                $method
            }
        }
    )

    if ($candidates.Count -le 1) {
        return @($candidates)
    }

    # Overload protection:
    # if possible, require matching parameter count.
    $targetArity = Get-ParameterArity $Target

    if ($null -ne $targetArity) {

        $sameArity = @(
            $candidates |
                Where-Object {
                    (Get-ParameterArity $_.fullName) -eq $targetArity
                }
        )

        if ($sameArity.Count -gt 0) {
            return @($sameArity)
        }
    }

    return @($candidates)
}

# ============================================================
# TYPE HIERARCHY
# ============================================================

function Get-DescendantTypeNames {
    param([string]$BaseType)

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()

    $queue.Enqueue($BaseType)

    while ($queue.Count -gt 0) {

        $current = $queue.Dequeue()

        foreach ($type in $types) {

            if (@($type.inheritsFrom) -contains $current) {

                if ($seen.Add([string]$type.fullName)) {
                    $queue.Enqueue([string]$type.fullName)
                }
            }
        }
    }

    return @($seen)
}

function Expand-PolymorphicTargets {
    param([object[]]$TargetMethods)

    $result = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($method in @($TargetMethods)) {

        if (-not $method) {
            continue
        }

        if ($seen.Add([string]$method.fullName)) {
            $result.Add($method)
        }

        $methodName = [string]$method.name

        # Constructors, class initializers, lambdas and other
        # synthetic methods are not virtual dispatch sites.
        if ($methodName.StartsWith("<")) {
            continue
        }

        $owner = [string]$method.owner

        if ([string]::IsNullOrWhiteSpace($owner)) {
            continue
        }

        $arity = Get-ParameterArity ([string]$method.fullName)

        foreach ($descendant in @(Get-DescendantTypeNames $owner)) {

            $implementations = @(
                $methods |
                    Where-Object {

                        if (
                            $_.owner -ne $descendant -or
                            $_.name -ne $methodName
                        ) {
                            return $false
                        }

                        if ($null -eq $arity) {
                            return $true
                        }

                        $candidateArity = Get-ParameterArity $_.fullName

                        if ($null -eq $candidateArity) {
                            return $true
                        }

                        return $candidateArity -eq $arity
                    }
            )

            foreach ($implementation in $implementations) {

                if ($seen.Add([string]$implementation.fullName)) {
                    $result.Add($implementation)
                }
            }
        }
    }

    return @($result)
}

# ============================================================
# INTERNAL OWNER LOOKUP FOR UNRESOLVED CALLS
# ============================================================

function Get-InternalOwnerForTarget {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return $null
    }

    $matches = @(
        $types |
            Where-Object {

                $prefix = [string]$_.fullName

                $Target.StartsWith($prefix + ".") -or
                $Target.StartsWith($prefix + ":")
            } |
            Sort-Object {
                $_.fullName.Length
            } -Descending
    )

    if ($matches.Count -gt 0) {
        return $matches[0]
    }

    return $null
}

# ============================================================
# CALLS
# ============================================================

$calls = [System.Collections.Generic.List[object]]::new()
$externalCalls = [System.Collections.Generic.List[object]]::new()

foreach ($call in @($model.calls)) {

    $caller = @(
        $methods |
            Where-Object {
                $_.fullName -eq $call.caller
            }
    ) |
    Select-Object -First 1

    # Test callers disappear automatically because they are
    # not present in $methods.
    if (-not $caller) {
        continue
    }

    $rawTargets = [System.Collections.Generic.List[string]]::new()

    if (
        $call.directTarget -and
        $call.directTarget -ne "<unknownFullName>"
    ) {
        $target = [string]$call.directTarget

        if (
            $IncludeTests -or
            -not (Test-IsTestTarget $target)
        ) {
            $rawTargets.Add($target)
        }
    }

    foreach ($targetValue in @($call.possibleTargets)) {

        if (
            -not $targetValue -or
            $targetValue -eq "<unknownFullName>"
        ) {
            continue
        }

        $target = [string]$targetValue

        if (
            -not $IncludeTests -and
            (Test-IsTestTarget $target)
        ) {
            continue
        }

        if (-not $rawTargets.Contains($target)) {
            $rawTargets.Add($target)
        }
    }

    $resolvedTargets = [System.Collections.Generic.List[object]]::new()
    $resolvedSeen = [System.Collections.Generic.HashSet[string]]::new()

    $unresolvedTargets = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($rawTarget in $rawTargets) {

        $resolved = @(
            Resolve-TargetMethod $rawTarget
        )

        if ($resolved.Count -eq 0) {
            [void]$unresolvedTargets.Add($rawTarget)
            continue
        }

        foreach ($method in $resolved) {

            if ($resolvedSeen.Add([string]$method.fullName)) {
                $resolvedTargets.Add($method)
            }
        }
    }

    # --------------------------------------------------------
    # Declared target
    # --------------------------------------------------------

    $declaredTarget = $null
    $resolvedDeclared = $null

    if (
        $call.directTarget -and
        $call.directTarget -ne "<unknownFullName>"
    ) {

        $resolvedDeclared = @(
            Resolve-TargetMethod ([string]$call.directTarget)
        ) |
        Select-Object -First 1

        if ($resolvedDeclared) {
            $declaredTarget = [string]$resolvedDeclared.fullName
        }
        else {
            $declaredTarget = [string]$call.directTarget
        }
    }
    elseif ($resolvedTargets.Count -eq 1) {
        $declaredTarget = [string]$resolvedTargets[0].fullName
    }

    # --------------------------------------------------------
    # Hierarchy expansion
    # --------------------------------------------------------

    $beforeExpansion = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($method in $resolvedTargets) {
        [void]$beforeExpansion.Add([string]$method.fullName)
    }

    $expandedTargets = @(
        Expand-PolymorphicTargets @($resolvedTargets)
    )

    $possibleTargets = @(
        $expandedTargets |
            ForEach-Object {
                [string]$_.fullName
            } |
            Sort-Object -Unique
    )

    $hierarchyAdded = @(
        $possibleTargets |
            Where-Object {
                -not $beforeExpansion.Contains([string]$_)
            }
    )

    # Everything besides the declared method is exposed
    # separately as dispatch alternatives.
    $dispatchTargets = @(
        $possibleTargets |
            Where-Object {
                -not $declaredTarget -or
                $_ -ne $declaredTarget
            } |
            Sort-Object -Unique
    )

    $resolution = if ($hierarchyAdded.Count -gt 0) {
        "joern+hierarchy"
    }
    else {
        "joern"
    }

    # --------------------------------------------------------
    # Internal application call
    # --------------------------------------------------------

    if ($possibleTargets.Count -gt 0) {

        $calls.Add(
            [pscustomobject]@{
                caller            = [string]$caller.fullName
                callerOwner       = [string]$caller.owner
                file              = [string]$call.file
                line              = $call.line
                code              = [string]$call.code
                declaredTarget    = $declaredTarget
                dispatchTargets   = @($dispatchTargets)
                possibleTargets   = @($possibleTargets)
                unresolvedTargets = @($unresolvedTargets | Sort-Object)
                resolution        = $resolution
            }
        )

        continue
    }

    # --------------------------------------------------------
    # External / unresolved call
    # --------------------------------------------------------

    $externalTargetList = @(
        $unresolvedTargets |
            Sort-Object
    )

    if (
        $externalTargetList.Count -eq 0 -and
        $call.directTarget -and
        $call.directTarget -ne "<unknownFullName>"
    ) {
        $externalTargetList = @(
            [string]$call.directTarget
        )
    }

    if ($externalTargetList.Count -eq 0) {
        continue
    }

    $primaryTarget = [string]$externalTargetList[0]

    $ownerType = Get-InternalOwnerForTarget $primaryTarget

    $classification = if ($ownerType) {
        "unresolved-on-internal-type"
    }
    else {
        "external"
    }

    $externalCalls.Add(
        [pscustomobject]@{
            caller              = [string]$caller.fullName
            callerOwner         = [string]$caller.owner
            file                = [string]$call.file
            line                = $call.line
            code                = [string]$call.code

            # compatibility
            target              = $primaryTarget

            targets             = @($externalTargetList)
            classification      = $classification
            internalOwner       = if ($ownerType) {
                                      [string]$ownerType.fullName
                                  }
                                  else {
                                      $null
                                  }
            unresolvedBaseHints = if ($ownerType) {
                                      @($ownerType.unresolvedBases)
                                  }
                                  else {
                                      @()
                                  }
        }
    )
}

# ============================================================
# RESULT
# ============================================================

$scope = if ($IncludeTests) {
    "all"
}
else {
    "production"
}

$result = [ordered]@{
    schemaVersion = 3
    language      = $Language
    scope         = $scope

    summary = [ordered]@{
        types               = $types.Count
        methods             = $methods.Count
        internalCalls       = $calls.Count
        externalCalls       = $externalCalls.Count
        excludedTestTypes   = if ($IncludeTests) { 0 } else { $excludedTestTypes }
        excludedTestMethods = if ($IncludeTests) { 0 } else { $excludedTestMethods }
    }

    types         = @($types)
    methods       = @($methods)
    calls         = @($calls)
    externalCalls = @($externalCalls)
}

$json = $result | ConvertTo-Json -Depth 40

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText(
    $OutputPath,
    $json,
    $utf8NoBom
)

# ============================================================
# HUMAN-READABLE REPORT
# ============================================================

$reportPath = [System.IO.Path]::ChangeExtension(
    $OutputPath,
    ".txt"
)

$report = New-Object System.Text.StringBuilder

[void]$report.AppendLine("APPLICATION STATIC MODEL")
[void]$report.AppendLine("========================")
[void]$report.AppendLine("")
[void]$report.AppendLine("Schema:   3")
[void]$report.AppendLine("Language: $Language")
[void]$report.AppendLine("Scope:    $scope")
[void]$report.AppendLine("")
[void]$report.AppendLine("Types:          $($types.Count)")
[void]$report.AppendLine("Methods:        $($methods.Count)")
[void]$report.AppendLine("Internal calls: $($calls.Count)")
[void]$report.AppendLine("External calls: $($externalCalls.Count)")
[void]$report.AppendLine("")

[void]$report.AppendLine("APPLICATION CALL GRAPH")
[void]$report.AppendLine("----------------------")

$grouped = $calls |
    Group-Object caller |
    Sort-Object Name

foreach ($group in $grouped) {

    [void]$report.AppendLine("")
    [void]$report.AppendLine($group.Name)

    foreach ($call in $group.Group) {

        [void]$report.AppendLine(
            "  -> $($call.code) [line $($call.line)]"
        )

        if ($call.declaredTarget) {
            [void]$report.AppendLine(
                "     declared: $($call.declaredTarget)"
            )
        }

        if ($call.dispatchTargets.Count -gt 0) {
            [void]$report.AppendLine(
                "     dispatch:"
            )

            foreach ($target in $call.dispatchTargets) {
                [void]$report.AppendLine(
                    "       - $target"
                )
            }
        }

        [void]$report.AppendLine(
            "     resolution: $($call.resolution)"
        )
    }
}

[System.IO.File]::WriteAllText(
    $reportPath,
    $report.ToString(),
    $utf8NoBom
)

Write-Host ""
Write-Host "Normalized v3: $Language"
Write-Host "  Scope:                 $scope"
Write-Host "  Types:                 $($types.Count)"
Write-Host "  Methods:               $($methods.Count)"
Write-Host "  Internal calls:        $($calls.Count)"
Write-Host "  External calls:        $($externalCalls.Count)"
Write-Host "  Excluded test types:   $(if ($IncludeTests) { 0 } else { $excludedTestTypes })"
Write-Host "  Excluded test methods: $(if ($IncludeTests) { 0 } else { $excludedTestMethods })"
Write-Host "  JSON: $OutputPath"
Write-Host "  TXT:  $reportPath"