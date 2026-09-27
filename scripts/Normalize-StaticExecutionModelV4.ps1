param(
    [Parameter(Mandatory = $true)]
    [string]$RawStructuralModelPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet("java", "python", "typescript", "javascript", "csharp")]
    [string]$Language,

    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [switch]$IncludeTests
)

$ErrorActionPreference = "Stop"

$RawStructuralModelPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RawStructuralModelPath)
$SourceRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceRoot)
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

if (-not (Test-Path $RawStructuralModelPath)) {
    throw "Raw structural model not found: $RawStructuralModelPath"
}

if (-not (Test-Path $SourceRoot)) {
    throw "Source root not found: $SourceRoot"
}

$outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
if ($outputDirectory) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$reportPath = Join-Path $outputDirectory "normalization-report.json"
$raw = Get-Content $RawStructuralModelPath -Raw | ConvertFrom-Json

if ([int]$raw.rawStructuralVersion -ne 1) {
    throw "Unsupported raw structural version: $($raw.rawStructuralVersion)"
}

# -----------------------------------------------------------------------------
# Report / diagnostics
# -----------------------------------------------------------------------------

$report = [ordered]@{
    phase                         = "B2"
    language                      = $Language
    scope                         = $(if ($IncludeTests) { "all" } else { "production" })
    rawTypes                      = @($raw.types).Count
    rawMethods                    = @($raw.methods).Count
    includedTypes                 = 0
    includedMethods               = 0
    excludedTestTypes             = 0
    excludedTestMethods           = 0
    syntheticTypesSuppressed      = 0
    syntheticMethodsSuppressed    = 0
    implicitReceiversSuppressed   = 0
    syntheticReceiversSuppressed  = 0
    rawCallsIncludingOperators    = 0
    rawNonOperatorCalls           = 0
    normalizedCallSites           = 0
    rawControls                   = 0
    includedRawNonOperatorCalls    = 0
    includedRawControls            = 0
    normalizedControls            = 0
    returnsNormalized             = 0
    syntheticNodesSuppressed      = 0
    foreachNormalizations         = 0
    throwRaiseNormalizations      = 0
    unmappedRawCalls              = 0
    unmappedRawCallByName          = @()
    unmappedRawCallSamples         = @()
    unmappedRawControls           = 0
    unsupportedControlSteps       = 0
    unsupportedBlockSteps         = 0
    sourceSlicesUsed              = 0
    sourceFallbacksUsed           = 0
    unresolvedSourceSnippets      = 0
    idCollisions                  = 0
    validationResult              = "pending-runner"
    warnings                      = @()
}

foreach ($m in @($raw.methods)) {
    $report.rawCallsIncludingOperators += @($m.calls).Count
    $report.rawNonOperatorCalls += @($m.calls | Where-Object { -not $_.isOperator }).Count
    $report.rawControls += @($m.controlStructures).Count
}

$warnings = [System.Collections.Generic.List[string]]::new()
$idRegistry = [System.Collections.Generic.HashSet[string]]::new()

function Add-Warning {
    param([string]$Message)
    $warnings.Add($Message)
}

function Register-NormalizedId {
    param([string]$Id)
    if (-not $idRegistry.Add($Id)) {
        $report.idCollisions++
        throw "Normalized id collision: $Id"
    }
}

# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------

function Normalize-FilePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return "<unknown>"
    }
    $value = $Path.Replace('\', '/')
    while ($value.StartsWith("./")) {
        $value = $value.Substring(2)
    }
    return $value
}

function Convert-PublicColumn {
    param([object]$Column)
    if ($null -eq $Column) {
        return $null
    }
    $value = [int]$Column
    if ($Language -in @("typescript", "javascript", "csharp")) {
        return $value + 1
    }
    return $value
}

function Convert-NullableType {
    param([string]$TypeName)
    if ([string]::IsNullOrWhiteSpace($TypeName)) {
        return $null
    }
    if ($TypeName -in @("ANY", "<unknown>", "<unknownFullName>")) {
        return $null
    }
    return $TypeName
}

function Get-HashId {
    param(
        [string]$Prefix,
        [string]$Seed
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
        $hash = $sha.ComputeHash($bytes)
        $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
        return $Prefix + ":" + $hex.Substring(0, 20)
    }
    finally {
        $sha.Dispose()
    }
}

function Test-SyntheticMethodName {
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

    if ($File) {
        $normalized = $File.Replace('\', '/')
        if ($normalized -match '(^|/)(test|tests|testing)(/|$)') {
            return $true
        }
    }

    if ($FullName -and $FullName -match '(^|[.:/])(test|tests|testing)([.:/]|$)') {
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

function Get-MethodKind {
    param([object]$Method)

    $name = [string]$Method.name
    $owner = [string]$Method.owner

    if ($name -eq "<init>") {
        return "CONSTRUCTOR"
    }

    if ($name -match "(?i)lambda") {
        return "LAMBDA"
    }

    if ([string]::IsNullOrWhiteSpace($owner)) {
        return "FUNCTION"
    }

    if (
        $Language -in @("typescript", "javascript") -and
        $owner.EndsWith("::program")
    ) {
        return "FUNCTION"
    }

    return "METHOD"
}

function Get-ParameterArity {
    param([string]$FullName)

    if ([string]::IsNullOrWhiteSpace($FullName)) {
        return $null
    }

    $open = $FullName.LastIndexOf("(")
    $close = $FullName.LastIndexOf(")")

    if ($open -lt 0 -or $close -lt $open) {
        return $null
    }

    $inside = $FullName.Substring($open + 1, $close - $open - 1)

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
            '>' { if ($angle -gt 0) { $angle-- } }
            '[' { $square++ }
            ']' { if ($square -gt 0) { $square-- } }
            '(' { $paren++ }
            ')' { if ($paren -gt 0) { $paren-- } }
            ',' {
                if ($angle -eq 0 -and $square -eq 0 -and $paren -eq 0) {
                    $count++
                }
            }
        }
    }

    return $count
}

function Test-PlaceholderSourceText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $true
    }

    $trimmed = $Text.Trim()

    if ($trimmed -in @(
        "<empty>",
        "if ... : ...",
        "match ... : ...",
        "while ... : ..."
    )) {
        return $true
    }

    return $false
}

function Split-JavaEnhancedForHeader {
    param([string]$SourceText)

    if ([string]::IsNullOrWhiteSpace($SourceText)) {
        return $null
    }

    $prefix = [System.Text.RegularExpressions.Regex]::Match(
        $SourceText,
        '^\s*for\s*\('
    )

    if (-not $prefix.Success) {
        return $null
    }

    $openIndex = $SourceText.IndexOf('(', $prefix.Index)
    if ($openIndex -lt 0) {
        return $null
    }

    $parenDepth = 0
    $squareDepth = 0
    $curlyDepth = 0
    $colonIndex = -1
    $closeIndex = -1
    $inString = $false
    $inChar = $false
    $escaped = $false

    for ($i = $openIndex + 1; $i -lt $SourceText.Length; $i++) {
        $ch = $SourceText[$i]

        if ($escaped) {
            $escaped = $false
            continue
        }

        if (($inString -or $inChar) -and $ch -eq '\') {
            $escaped = $true
            continue
        }

        if (-not $inChar -and $ch -eq '"') {
            $inString = -not $inString
            continue
        }

        if (-not $inString -and $ch -eq "'") {
            $inChar = -not $inChar
            continue
        }

        if ($inString -or $inChar) {
            continue
        }

        switch ($ch) {
            '(' {
                $parenDepth++
                continue
            }
            ')' {
                if ($parenDepth -gt 0) {
                    $parenDepth--
                    continue
                }

                $closeIndex = $i
                break
            }
            '[' {
                $squareDepth++
                continue
            }
            ']' {
                if ($squareDepth -gt 0) {
                    $squareDepth--
                }
                continue
            }
            '{' {
                $curlyDepth++
                continue
            }
            '}' {
                if ($curlyDepth -gt 0) {
                    $curlyDepth--
                }
                continue
            }
            ':' {
                if (
                    $colonIndex -lt 0 -and
                    $parenDepth -eq 0 -and
                    $squareDepth -eq 0 -and
                    $curlyDepth -eq 0
                ) {
                    $colonIndex = $i
                }
                continue
            }
        }

        if ($closeIndex -ge 0) {
            break
        }
    }

    if ($colonIndex -lt 0 -or $closeIndex -le $colonIndex) {
        return $null
    }

    $binding = $SourceText.Substring(
        $openIndex + 1,
        $colonIndex - $openIndex - 1
    ).Trim()

    $iterable = $SourceText.Substring(
        $colonIndex + 1,
        $closeIndex - $colonIndex - 1
    ).Trim()

    if (
        [string]::IsNullOrWhiteSpace($binding) -or
        [string]::IsNullOrWhiteSpace($iterable)
    ) {
        return $null
    }

    return [pscustomobject]@{
        binding  = $binding
        iterable = $iterable
    }
}

# -----------------------------------------------------------------------------
# Source text helpers
# -----------------------------------------------------------------------------

$sourceCache = @{}

function Get-SourceFileText {
    param([string]$ProjectRelativeFile)

    $file = Normalize-FilePath $ProjectRelativeFile

    if ($sourceCache.ContainsKey($file)) {
        return $sourceCache[$file]
    }

    # Joern can emit pseudo filenames such as <empty> for synthetic/frontend
    # nodes. They are provenance labels, not filesystem paths. Never pass them
    # to Test-Path/Join-Path on Windows because '<' and '>' are invalid path
    # characters.
    if (
        [string]::IsNullOrWhiteSpace($file) -or
        $file -match '^<[^>]+>$' -or
        $file -match '[<>:"|?*]'
    ) {
        $sourceCache[$file] = $null
        Add-Warning "Skipping non-filesystem raw source path: $file"
        return $null
    }

    $nativeRelative = $file.Replace('/', [System.IO.Path]::DirectorySeparatorChar)

    try {
        $candidate = Join-Path $SourceRoot $nativeRelative
    }
    catch {
        $sourceCache[$file] = $null
        Add-Warning "Could not build source path for raw file: $file"
        return $null
    }

    # File.Exists is deliberately used instead of Test-Path here. It returns
    # false for malformed/inaccessible file names instead of turning a raw CPG
    # pseudo path into a terminating PowerShell error.
    if (-not [System.IO.File]::Exists($candidate)) {
        $sourceCache[$file] = $null
        Add-Warning "Source file not found for raw path: $file"
        return $null
    }

    try {
        $content = [System.IO.File]::ReadAllText($candidate)
    }
    catch {
        $sourceCache[$file] = $null
        Add-Warning "Source file could not be read for raw path: $file"
        return $null
    }

    $sourceCache[$file] = $content
    return $content
}

function Get-LineFromText {
    param(
        [string]$Text,
        [object]$LineNumber
    )

    if ($null -eq $Text -or $null -eq $LineNumber) {
        return $null
    }

    $line = [int]$LineNumber
    if ($line -lt 1) {
        return $null
    }

    $lines = [System.Text.RegularExpressions.Regex]::Split($Text, "\r\n|\n|\r")

    if ($line -gt $lines.Length) {
        return $null
    }

    return $lines[$line - 1]
}

function Get-SourceSnippetText {
    param(
        [object]$Node,
        [string]$File
    )

    $sourceText = Get-SourceFileText $File

    if (
        $null -ne $sourceText -and
        $null -ne $Node.offset -and
        $null -ne $Node.offsetEnd
    ) {
        $start = [int]$Node.offset
        $end = [int]$Node.offsetEnd

        if (
            $start -ge 0 -and
            $end -gt $start -and
            $end -le $sourceText.Length
        ) {
            $report.sourceSlicesUsed++
            return $sourceText.Substring($start, $end - $start)
        }
    }

    $sourceCode = [string]$Node.sourceCode
    if (-not (Test-PlaceholderSourceText $sourceCode)) {
        $report.sourceFallbacksUsed++
        return $sourceCode.Trim()
    }

    $code = [string]$Node.code
    if (-not (Test-PlaceholderSourceText $code)) {
        $report.sourceFallbacksUsed++
        return $code.Trim()
    }

    if ($null -ne $sourceText) {
        $lineText = Get-LineFromText $sourceText $Node.line
        if (-not [string]::IsNullOrWhiteSpace($lineText)) {
            $report.sourceFallbacksUsed++
            return $lineText.Trim()
        }
    }

    $report.unresolvedSourceSnippets++
    Add-Warning "Could not reconstruct source snippet for node $($Node.id) in $File"
    return "<unknown-source>"
}

function New-SourceLocation {
    param(
        [string]$File,
        [object]$Line,
        [object]$Column
    )

    return [pscustomobject][ordered]@{
        file   = (Normalize-FilePath $File)
        line   = $(if ($null -eq $Line) { $null } else { [int]$Line })
        column = (Convert-PublicColumn $Column)
    }
}

function New-SourceSnippet {
    param(
        [object]$Node,
        [string]$File
    )

    return [pscustomobject][ordered]@{
        file   = (Normalize-FilePath $File)
        line   = $(if ($null -eq $Node.line) { $null } else { [int]$Node.line })
        column = (Convert-PublicColumn $Node.column)
        text   = (Get-SourceSnippetText $Node $File)
    }
}


function New-ExplicitSourceSnippet {
    param(
        [string]$File,
        [object]$Line,
        [object]$Column,
        [string]$Text
    )

    return [pscustomobject][ordered]@{
        file   = (Normalize-FilePath $File)
        line   = $(if ($null -eq $Line) { $null } else { [int]$Line })
        column = $(if ($null -eq $Column) { $null } else { [int]$Column })
        text   = $Text
    }
}

# -----------------------------------------------------------------------------
# Filter methods and types
# -----------------------------------------------------------------------------

$cleanRawMethods = @(
    foreach ($method in @($raw.methods)) {
        if (Test-SyntheticMethodName ([string]$method.name)) {
            $report.syntheticMethodsSuppressed++
            continue
        }

        if (
            -not $IncludeTests -and
            (Test-IsTestArtifact ([string]$method.file) ([string]$method.fullName))
        ) {
            $report.excludedTestMethods++
            continue
        }

        $method
    }
)

$cleanMethodFullNames = [System.Collections.Generic.HashSet[string]]::new()
foreach ($method in $cleanRawMethods) {
    [void]$cleanMethodFullNames.Add([string]$method.fullName)
}

$cleanRawTypes = @(
    foreach ($type in @($raw.types)) {
        if (Test-SyntheticTypeName ([string]$type.name)) {
            $report.syntheticTypesSuppressed++
            continue
        }

        if ($cleanMethodFullNames.Contains([string]$type.fullName)) {
            $report.syntheticTypesSuppressed++
            continue
        }

        if (
            -not $IncludeTests -and
            (Test-IsTestArtifact ([string]$type.file) ([string]$type.fullName))
        ) {
            $report.excludedTestTypes++
            continue
        }

        $type
    }
)

$report.includedMethods = $cleanRawMethods.Count
$report.includedTypes = $cleanRawTypes.Count

foreach ($includedRawMethod in $cleanRawMethods) {
    $report.includedRawNonOperatorCalls += @(
        $includedRawMethod.calls |
            Where-Object { -not $_.isOperator }
    ).Count
    $report.includedRawControls += @($includedRawMethod.controlStructures).Count
}

# -----------------------------------------------------------------------------
# Types
# -----------------------------------------------------------------------------

$typeByFullName = @{}
$typeBySimpleName = @{}

foreach ($type in $cleanRawTypes) {
    $typeByFullName[[string]$type.fullName] = $type

    $name = [string]$type.name
    if (-not $typeBySimpleName.ContainsKey($name)) {
        $typeBySimpleName[$name] = [System.Collections.Generic.List[object]]::new()
    }
    $typeBySimpleName[$name].Add($type)
}

function Resolve-TypeFullName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -eq "ANY") {
        return $null
    }

    if ($typeByFullName.ContainsKey($Name)) {
        return $Name
    }

    if ($typeBySimpleName.ContainsKey($Name)) {
        $sameName = @($typeBySimpleName[$Name])
        if ($sameName.Count -eq 1) {
            return [string]$sameName[0].fullName
        }
    }

    $suffix = @(
        $cleanRawTypes |
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
    foreach ($type in $cleanRawTypes) {
        $internalBases = [System.Collections.Generic.HashSet[string]]::new()
        $unresolvedBases = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($baseValue in @($type.inheritsFrom)) {
            $base = [string]$baseValue
            if ([string]::IsNullOrWhiteSpace($base) -or $base -eq "ANY") {
                continue
            }

            $resolved = Resolve-TypeFullName $base
            if ($resolved) {
                [void]$internalBases.Add($resolved)
            }
            else {
                [void]$unresolvedBases.Add($base)
            }
        }

        [pscustomobject][ordered]@{
            name            = [string]$type.name
            fullName        = [string]$type.fullName
            file            = (Normalize-FilePath ([string]$type.file))
            inheritsFrom    = @($internalBases | Sort-Object)
            unresolvedBases = @($unresolvedBases | Sort-Object)
        }
    }
)

# -----------------------------------------------------------------------------
# Methods
# -----------------------------------------------------------------------------

$methods = [System.Collections.Generic.List[object]]::new()
$methodByFullName = @{}
$rawMethodByFullName = @{}

foreach ($rawMethod in $cleanRawMethods) {
    $parameters = [System.Collections.Generic.List[object]]::new()

    $rawParameters = @($rawMethod.parameters | Sort-Object index, order)
    foreach ($parameter in $rawParameters) {
        if (
            [string]$parameter.name -eq "this" -and
            [int]$parameter.index -eq 0
        ) {
            $report.implicitReceiversSuppressed++
            continue
        }

        $parameters.Add(
            [pscustomobject][ordered]@{
                name   = [string]$parameter.name
                type   = (Convert-NullableType ([string]$parameter.typeFullName))
                index  = $parameters.Count
                source = (New-SourceLocation ([string]$rawMethod.file) $parameter.line $parameter.column)
            }
        )
    }

    $method = [pscustomobject][ordered]@{
        name       = [string]$rawMethod.name
        fullName   = [string]$rawMethod.fullName
        owner      = [string]$rawMethod.owner
        kind       = (Get-MethodKind $rawMethod)
        signature  = [string]$rawMethod.signature
        returnType = (Convert-NullableType ([string]$rawMethod.returnType))
        source     = (New-SourceLocation ([string]$rawMethod.file) $rawMethod.line $rawMethod.column)
        parameters = @($parameters)
        body       = @()
    }

    $methods.Add($method)
    $methodByFullName[$method.fullName] = $method
    $rawMethodByFullName[$method.fullName] = $rawMethod
}

# -----------------------------------------------------------------------------
# Target resolution / hierarchy
# -----------------------------------------------------------------------------

function Resolve-TargetMethodNames {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target) -or $Target -eq "<unknownFullName>") {
        return @()
    }

    if ($methodByFullName.ContainsKey($Target)) {
        return @($Target)
    }

    $matches = [System.Collections.Generic.List[string]]::new()

    foreach ($method in @($methods)) {
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

        foreach ($alias in @($dotAlias, $colonAlias)) {
            if (
                $Target -eq $alias -or
                $Target.StartsWith($alias + ":") -or
                $Target.StartsWith($alias + "(")
            ) {
                if (-not $matches.Contains([string]$method.fullName)) {
                    $matches.Add([string]$method.fullName)
                }
                break
            }
        }
    }

    if ($matches.Count -gt 1) {
        $targetArity = Get-ParameterArity $Target

        if ($null -ne $targetArity) {
            $sameArity = @(
                $matches |
                    Where-Object {
                        (Get-ParameterArity $_) -eq $targetArity
                    }
            )

            if ($sameArity.Count -gt 0) {
                return @($sameArity)
            }
        }
    }

    return @($matches)
}

$typeChildren = @{}
foreach ($type in $types) {
    foreach ($base in @($type.inheritsFrom)) {
        if (-not $typeChildren.ContainsKey([string]$base)) {
            $typeChildren[[string]$base] = [System.Collections.Generic.List[string]]::new()
        }
        $typeChildren[[string]$base].Add([string]$type.fullName)
    }
}

function Get-DescendantTypeNames {
    param([string]$BaseType)

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($BaseType)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $typeChildren.ContainsKey($current)) {
            continue
        }

        foreach ($child in @($typeChildren[$current])) {
            if ($seen.Add($child)) {
                $queue.Enqueue($child)
            }
        }
    }

    return @($seen)
}

function Expand-PolymorphicTargetNames {
    param([string[]]$ResolvedTargetNames)

    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $addedByHierarchy = $false

    foreach ($targetName in @($ResolvedTargetNames)) {
        if ($seen.Add($targetName)) {
            $result.Add($targetName)
        }

        if (-not $methodByFullName.ContainsKey($targetName)) {
            continue
        }

        $method = $methodByFullName[$targetName]
        if ([string]$method.name -like "<*") {
            continue
        }

        $owner = [string]$method.owner
        if ([string]::IsNullOrWhiteSpace($owner)) {
            continue
        }

        $arity = Get-ParameterArity $targetName

        foreach ($descendant in @(Get-DescendantTypeNames $owner)) {
            foreach ($candidate in @($methods)) {
                if (
                    [string]$candidate.owner -ne $descendant -or
                    [string]$candidate.name -ne [string]$method.name
                ) {
                    continue
                }

                $candidateArity = Get-ParameterArity ([string]$candidate.fullName)
                if (
                    $null -ne $arity -and
                    $null -ne $candidateArity -and
                    $candidateArity -ne $arity
                ) {
                    continue
                }

                if ($seen.Add([string]$candidate.fullName)) {
                    $result.Add([string]$candidate.fullName)
                    $addedByHierarchy = $true
                }
            }
        }
    }

    return [pscustomobject]@{
        targets          = @($result)
        addedByHierarchy = $addedByHierarchy
    }
}

function Find-InternalOwnerForTarget {
    param([string]$Target)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return $null
    }

    foreach ($type in @($types | Sort-Object { $_.fullName.Length } -Descending)) {
        $full = [string]$type.fullName

        if (
            $Target.StartsWith($full + ".") -or
            $Target.StartsWith($full + ":")
        ) {
            return $full
        }
    }

    return $null
}

# -----------------------------------------------------------------------------
# Expression / control output collections
# -----------------------------------------------------------------------------

$expressions = [System.Collections.Generic.List[object]]::new()
$callSites = [System.Collections.Generic.List[object]]::new()
$controls = [System.Collections.Generic.List[object]]::new()

$operatorNames = @{
    "<operator>.logicalAnd"       = "logical-and"
    "<operator>.logicalOr"        = "logical-or"
    "<operator>.logicalNot"       = "logical-not"
    "<operator>.not"              = "logical-not"
    "<operator>.conditional"      = "conditional"
    "<operator>.assignment"       = "assignment"
    "<operator>.addition"         = "addition"
    "<operator>.indexAccess"      = "index-access"
    "<operator>.fieldAccess"      = "field-access"
    "<operator>.equals"           = "equals"
    "<operator>.notEquals"        = "not-equals"
    "<operator>.greaterThan"      = "greater-than"
    "<operator>.lessThan"         = "less-than"
    "<operator>.greaterEqualsThan" = "greater-or-equal"
    "<operator>.lessEqualsThan"   = "less-or-equal"
    "<operator>.is"               = "is"
    "<operator>.postIncrement"    = "post-increment"
    "<operator>.raise"            = "raise"
}


# -----------------------------------------------------------------------------
# Per-method normalization slice B2
# -----------------------------------------------------------------------------

$normalizedRawNonOperatorCallIds = [System.Collections.Generic.HashSet[string]]::new()
$suppressedRawNodeIdsGlobal = [System.Collections.Generic.HashSet[string]]::new()

foreach ($rawMethod in $cleanRawMethods) {
    $methodFullName = [string]$rawMethod.fullName
    $method = $methodByFullName[$methodFullName]
    $file = Normalize-FilePath ([string]$rawMethod.file)

    $nodeById = @{}
    foreach ($node in @($rawMethod.astNodes)) {
        $nodeById[[string]$node.id] = $node
    }

    $callById = @{}
    foreach ($call in @($rawMethod.calls)) {
        $callById[[string]$call.id] = $call
    }

    $rawControlById = @{}
    foreach ($control in @($rawMethod.controlStructures)) {
        $rawControlById[[string]$control.id] = $control
    }

    $parentById = @{}
    foreach ($node in @($rawMethod.astNodes)) {
        $parentIds = @($node.parentIds)
        $parentById[[string]$node.id] = $(
            if ($parentIds.Count -gt 0) {
                [string]$parentIds[0]
            }
            else {
                $null
            }
        )
    }

    $getAstPath = {
        param([string]$RawId)

        $parts = [System.Collections.Generic.List[string]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $current = $RawId

        while (
            $current -and
            $nodeById.ContainsKey($current) -and
            $seen.Add($current)
        ) {
            $node = $nodeById[$current]
            $parts.Add(([int]$node.order).ToString())
            $current = $parentById[$current]
        }

        $array = @($parts)
        [array]::Reverse($array)
        return ($array -join ".")
    }

    $getExpressionId = {
        param([string]$RawId)

        $node = $nodeById[$RawId]
        $seed = @(
            $Language,
            $file,
            $methodFullName,
            "EXPR",
            [string]$node.line,
            [string](Convert-PublicColumn $node.column),
            (& $getAstPath $RawId)
        ) -join "|"

        return Get-HashId "expr" $seed
    }

    $expressionByRawId = @{}
    $semanticExpressionByKey = @{}

    $isSyntheticReceiver = {
        param(
            [object]$Call,
            [object]$Argument
        )

        if ([int]$Argument.argumentIndex -ne 0) {
            return $false
        }

        $callCode = ([string]$Call.code).Trim()
        $argumentCode = ([string]$Argument.code).Trim()

        if ($callCode -match '^[A-Za-z_$][A-Za-z0-9_$]*\s*\.') {
            return $false
        }

        if ($argumentCode -in @("this", "self")) {
            return $true
        }

        $owner = [string]$rawMethod.owner
        if ($owner -and $argumentCode -eq $owner) {
            return $true
        }

        if ($owner) {
            $ownerParts = [System.Text.RegularExpressions.Regex]::Split($owner, '[\.:$]')
            if ($ownerParts.Length -gt 0) {
                $shortOwner = $ownerParts[$ownerParts.Length - 1]
                if ($shortOwner -and $argumentCode -eq $shortOwner) {
                    return $true
                }
            }
        }

        # Java object construction has a synthetic allocation receiver
        # (`$objN`) on the <init> call. Suppress that receiver explicitly.
        if (
            [string]$Call.name -eq "<init>" -and
            $callCode -match '^\s*new\s+'
        ) {
            return $true
        }

        # Do not guess implicitness from "text before the first parenthesis".
        # That old heuristic incorrectly dropped real source receivers such as:
        #
        #   new ProcessBuilder(...).directory(...).redirectErrorStream(...)
        #
        # Explicit `this`/owner receivers were handled above. Everything else
        # is source-semantic and must remain in the expression tree.
        return $false
    }

    $buildExpression = $null
    $buildExpression = {
        param([string]$RawId)

        if ($expressionByRawId.ContainsKey($RawId)) {
            return [string]$expressionByRawId[$RawId]
        }

        if (-not $nodeById.ContainsKey($RawId)) {
            Add-Warning "Expression raw node missing: method=$methodFullName rawId=$RawId"
            return $null
        }

        $node = $nodeById[$RawId]
        $call = $null
        if ($callById.ContainsKey($RawId)) {
            $call = $callById[$RawId]
        }

        $kind = "VALUE"
        $operator = $null
        $children = [System.Collections.Generic.List[object]]::new()

        if ($call) {
            if ($call.isOperator) {
                $kind = "OPERATOR"
                $rawOperator = [string]$call.name
                if ($operatorNames.ContainsKey($rawOperator)) {
                    $operator = [string]$operatorNames[$rawOperator]
                }
                else {
                    $operator = $rawOperator.Replace("<operator>.", "")
                }
            }
            else {
                $kind = "CALL"
            }

            $arguments = @($call.arguments | Sort-Object argumentIndex, order, id)
            $sourceArgumentIndex = 0

            foreach ($argument in $arguments) {
                if (& $isSyntheticReceiver $call $argument) {
                    $report.syntheticReceiversSuppressed++
                    continue
                }

                $childId = & $buildExpression ([string]$argument.id)
                if (-not $childId) {
                    continue
                }

                $rawArgumentIndex = [int]$argument.argumentIndex
                $role = "OTHER"
                $index = $null

                if ($kind -eq "CALL") {
                    if ($rawArgumentIndex -eq 0) {
                        $role = "RECEIVER"
                        $index = 0
                    }
                    else {
                        $role = "ARGUMENT"
                        $index = $sourceArgumentIndex
                        $sourceArgumentIndex++
                    }
                }
                elseif ($operator -eq "conditional") {
                    switch ($rawArgumentIndex) {
                        1 { $role = "CONDITION"; $index = 0 }
                        2 { $role = "TRUE"; $index = 0 }
                        3 { $role = "FALSE"; $index = 0 }
                        default { $role = "OTHER"; $index = $null }
                    }
                }
                elseif ($operator -in @(
                    "logical-and",
                    "logical-or",
                    "logical-not",
                    "addition",
                    "equals",
                    "not-equals",
                    "greater-than",
                    "less-than",
                    "greater-or-equal",
                    "less-or-equal",
                    "is"
                )) {
                    $role = "OPERAND"
                    $index = [Math]::Max(0, $rawArgumentIndex - 1)
                }
                elseif ($operator -eq "index-access") {
                    if ($rawArgumentIndex -eq 1) {
                        $role = "BASE"
                    }
                    else {
                        $role = "INDEX"
                    }
                    $index = 0
                }
                elseif ($operator -eq "field-access") {
                    if ($rawArgumentIndex -eq 1) {
                        $role = "BASE"
                    }
                    else {
                        $role = "OTHER"
                    }
                    $index = [Math]::Max(0, $rawArgumentIndex - 1)
                }
                else {
                    if ($rawArgumentIndex -eq 2) {
                        $role = "VALUE"
                    }
                    else {
                        $role = "OTHER"
                    }
                    $index = [Math]::Max(0, $rawArgumentIndex - 1)
                }

                $children.Add(
                    [pscustomobject][ordered]@{
                        expressionId = $childId
                        role         = $role
                        index        = $index
                    }
                )
            }
        }
        else {
            $childIndex = 0

            foreach ($childValue in @($node.childIds)) {
                $childRawId = [string]$childValue

                if (-not $nodeById.ContainsKey($childRawId)) {
                    continue
                }

                # Java object construction exposes <operator>.alloc as lowering
                # evidence. It is not a source-level execution step.
                if (
                    $callById.ContainsKey($childRawId) -and
                    [string]$callById[$childRawId].name -eq "<operator>.alloc"
                ) {
                    continue
                }

                $childExpressionId = & $buildExpression $childRawId
                if (-not $childExpressionId) {
                    continue
                }

                $children.Add(
                    [pscustomobject][ordered]@{
                        expressionId = $childExpressionId
                        role         = "OTHER"
                        index        = $childIndex
                    }
                )
                $childIndex++
            }

            if ($children.Count -gt 0) {
                $kind = "OTHER"
            }
        }

        $expressionId = & $getExpressionId $RawId
        Register-NormalizedId $expressionId
        $expressionByRawId[$RawId] = $expressionId

        $nodeType = $null
        if ($node.PSObject.Properties.Name -contains "typeFullName") {
            $nodeType = [string]$node.typeFullName
        }
        if (-not $nodeType -and $call) {
            $nodeType = [string]$call.typeFullName
        }

        $expression = [pscustomobject][ordered]@{
            id         = $expressionId
            method     = $methodFullName
            kind       = $kind
            source     = (New-SourceSnippet $node $file)
            type       = (Convert-NullableType $nodeType)
            operator   = $operator
            callSiteId = $null
            children   = @($children)
            rawNodeIds = @($RawId)
        }

        $expressions.Add($expression)

        if ($kind -eq "CALL") {
            [void]$normalizedRawNonOperatorCallIds.Add($RawId)

            $callSeed = @(
                $Language,
                $file,
                $methodFullName,
                "CALLSITE",
                [string]$node.line,
                [string](Convert-PublicColumn $node.column),
                (& $getAstPath $RawId)
            ) -join "|"

            $callSiteId = Get-HashId "call" $callSeed
            Register-NormalizedId $callSiteId
            $expression.callSiteId = $callSiteId

            $rawTargets = [System.Collections.Generic.List[string]]::new()
            $directTarget = [string]$call.methodFullName

            if (
                $directTarget -and
                $directTarget -ne "<unknownFullName>" -and
                ($IncludeTests -or -not (Test-IsTestTarget $directTarget))
            ) {
                $rawTargets.Add($directTarget)
            }

            foreach ($targetValue in @($call.possibleTargets)) {
                $target = [string]$targetValue

                if (
                    [string]::IsNullOrWhiteSpace($target) -or
                    $target -eq "<unknownFullName>"
                ) {
                    continue
                }

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

            $resolved = [System.Collections.Generic.List[string]]::new()
            $unresolved = [System.Collections.Generic.List[string]]::new()

            foreach ($rawTarget in @($rawTargets)) {
                $matches = @(Resolve-TargetMethodNames $rawTarget)

                if ($matches.Count -gt 0) {
                    foreach ($match in $matches) {
                        if (-not $resolved.Contains([string]$match)) {
                            $resolved.Add([string]$match)
                        }
                    }
                }
                elseif (-not $unresolved.Contains([string]$rawTarget)) {
                    $unresolved.Add([string]$rawTarget)
                }
            }

            $declaredTarget = $null

            if ($directTarget -and $directTarget -ne "<unknownFullName>") {
                $directResolved = @(Resolve-TargetMethodNames $directTarget)

                if ($directResolved.Count -gt 0) {
                    $declaredTarget = [string]$directResolved[0]
                }
                else {
                    $declaredTarget = $directTarget
                }
            }
            elseif ($resolved.Count -eq 1) {
                $declaredTarget = [string]$resolved[0]
            }

            $expanded = Expand-PolymorphicTargetNames @($resolved)
            $possibleTargets = @()
            $dispatchTargets = @()
            $unresolvedTargets = @()
            $classification = "external"
            $resolution = "unresolved"
            $internalOwner = $null
            $unresolvedBaseHints = @()

            if (@($expanded.targets).Count -gt 0) {
                $possibleTargets = @($expanded.targets | Sort-Object -Unique)
                $dispatchTargets = @(
                    $possibleTargets |
                        Where-Object {
                            -not $declaredTarget -or
                            $_ -ne $declaredTarget
                        } |
                        Sort-Object -Unique
                )
                $unresolvedTargets = @($unresolved | Sort-Object -Unique)
                $classification = "internal"
                $resolution = $(if ($expanded.addedByHierarchy) { "joern+hierarchy" } else { "joern" })

                $firstTarget = [string]$possibleTargets[0]
                if ($methodByFullName.ContainsKey($firstTarget)) {
                    $internalOwner = [string]$methodByFullName[$firstTarget].owner
                }
            }
            else {
                $externalTargetList = @($unresolved | Sort-Object -Unique)

                if (
                    $externalTargetList.Count -eq 0 -and
                    $directTarget -and
                    $directTarget -ne "<unknownFullName>"
                ) {
                    $externalTargetList = @($directTarget)
                }

                $possibleTargets = @($externalTargetList)

                if ($externalTargetList.Count -gt 0) {
                    $primaryTarget = [string]$externalTargetList[0]
                    $internalOwner = Find-InternalOwnerForTarget $primaryTarget

                    if ($internalOwner) {
                        $classification = "unresolved-on-internal-type"
                        $resolution = "unresolved"
                        $unresolvedTargets = @($externalTargetList)

                        $ownerType = @(
                            $types |
                                Where-Object { $_.fullName -eq $internalOwner }
                        ) | Select-Object -First 1

                        if ($ownerType) {
                            $unresolvedBaseHints = @($ownerType.unresolvedBases | Sort-Object -Unique)
                        }
                    }
                    else {
                        $classification = "external"
                        $resolution = "joern"
                        $unresolvedTargets = @()
                    }
                }
            }

            $callSite = [pscustomobject][ordered]@{
                id                  = $callSiteId
                caller              = $methodFullName
                expressionId        = $expressionId
                declaredTarget      = $declaredTarget
                dispatchTargets     = @($dispatchTargets)
                possibleTargets     = @($possibleTargets)
                unresolvedTargets   = @($unresolvedTargets)
                resolution          = $resolution
                classification      = $classification
                internalOwner       = $internalOwner
                unresolvedBaseHints = @($unresolvedBaseHints)
                rawNodeIds          = @($RawId)
            }

            $callSites.Add($callSite)
            $report.normalizedCallSites++
        }

        return $expressionId
    }

    $getDescendantIds = {
        param([string]$RootId)

        $result = [System.Collections.Generic.List[string]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $queue = [System.Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($RootId)

        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            if (-not $seen.Add($current)) {
                continue
            }

            if (-not $nodeById.ContainsKey($current)) {
                continue
            }

            $result.Add($current)
            foreach ($childId in @($nodeById[$current].childIds)) {
                $queue.Enqueue([string]$childId)
            }
        }

        return @($result)
    }

    $getSourceSnippetPosition = {
        param(
            [object]$BaseSnippet,
            [string]$Needle
        )

        $line = $BaseSnippet.line
        $column = $BaseSnippet.column

        if (
            [string]::IsNullOrWhiteSpace($Needle) -or
            [string]::IsNullOrWhiteSpace([string]$BaseSnippet.text)
        ) {
            return [pscustomobject]@{
                line = $line
                column = $column
            }
        }

        $index = ([string]$BaseSnippet.text).IndexOf(
            $Needle,
            [System.StringComparison]::Ordinal
        )

        if ($index -lt 0) {
            return [pscustomobject]@{
                line = $line
                column = $column
            }
        }

        $prefixText = ([string]$BaseSnippet.text).Substring(0, $index)
        $parts = [System.Text.RegularExpressions.Regex]::Split(
            $prefixText,
            "\r\n|\n|\r"
        )

        if ($parts.Length -le 1) {
            if ($null -ne $column) {
                $column = [int]$column + $index
            }
        }
        else {
            if ($null -ne $line) {
                $line = [int]$line + $parts.Length - 1
            }
            $column = $parts[$parts.Length - 1].Length + 1
        }

        return [pscustomobject]@{
            line = $line
            column = $column
        }
    }

    $newSemanticExpression = {
        param(
            [string]$Key,
            [string]$Text,
            [object]$BaseSnippet,
            [string[]]$RawNodeIds
        )

        if ($semanticExpressionByKey.ContainsKey($Key)) {
            return [string]$semanticExpressionByKey[$Key]
        }

        $position = & $getSourceSnippetPosition $BaseSnippet $Text

        $seed = @(
            $Language,
            $file,
            $methodFullName,
            "SEMANTIC_EXPR",
            $Key,
            [string]$position.line,
            [string]$position.column,
            $Text
        ) -join "|"

        $expressionId = Get-HashId "expr" $seed
        Register-NormalizedId $expressionId
        $semanticExpressionByKey[$Key] = $expressionId

        $expressions.Add(
            [pscustomobject][ordered]@{
                id         = $expressionId
                method     = $methodFullName
                kind       = "VALUE"
                source     = (New-ExplicitSourceSnippet $file $position.line $position.column $Text)
                type       = $null
                operator   = $null
                callSiteId = $null
                children   = @()
                rawNodeIds = @($RawNodeIds | Sort-Object -Unique)
            }
        )

        return $expressionId
    }

    $findRawExpressionByText = {
        param(
            [string]$Text,
            [object]$NearLine
        )

        $trimmed = $Text.Trim()
        $candidates = [System.Collections.Generic.List[object]]::new()

        foreach ($node in @($rawMethod.astNodes)) {
            $code = ([string]$node.code).Trim()
            $sourceCode = ([string]$node.sourceCode).Trim()

            if ($code -ne $trimmed -and $sourceCode -ne $trimmed) {
                continue
            }

            $priority = 5
            switch ([string]$node.kind) {
                "Identifier" { $priority = 0 }
                "Literal"    { $priority = 1 }
                "Call"       { $priority = 2 }
                default      { $priority = 4 }
            }

            if ([string]$node.kind -eq "Call" -and $callById.ContainsKey([string]$node.id)) {
                $callName = [string]$callById[[string]$node.id].name
                if (
                    $callName -in @(
                        "iterator",
                        "hasNext",
                        "next",
                        "__iter__",
                        "__next__",
                        "<operator>.iterator"
                    ) -and
                    $trimmed -notmatch '\('
                ) {
                    $priority = 20
                }
            }

            $distance = 999999
            if ($null -ne $NearLine -and $null -ne $node.line) {
                $distance = [Math]::Abs([int]$node.line - [int]$NearLine)
            }

            $candidates.Add(
                [pscustomobject]@{
                    node = $node
                    priority = $priority
                    distance = $distance
                }
            )
        }

        $winner = @(
            $candidates |
                Sort-Object priority, distance, {
                    if ($null -eq $_.node.column) { 999999 } else { [int]$_.node.column }
                }, {
                    [int64]$_.node.id
                }
        ) | Select-Object -First 1

        if ($winner) {
            return [string]$winner.node.id
        }

        return $null
    }

    $findForeachIterableRawId = {
        param(
            [string]$Text,
            [object]$RawControl
        )

        $trimmed = $Text.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return $null
        }

        # Enhanced-for over arrays is lowered differently from Iterable-based
        # loops by the Java frontend. The iterable call can sit beside index/
        # length mechanics instead of below an `iterator()` call. Resolve the
        # original source call directly from header-line call evidence.
        $terminalCallName = $null
        $callMatches = [System.Text.RegularExpressions.Regex]::Matches(
            $trimmed,
            '(?<name>[A-Za-z_$][A-Za-z0-9_$]*)\s*\('
        )

        if ($callMatches.Count -gt 0) {
            $terminalCallName = [string]$callMatches[$callMatches.Count - 1].Groups["name"].Value
        }

        $candidateCalls = [System.Collections.Generic.List[object]]::new()

        foreach ($candidateCall in @($rawMethod.calls)) {
            if ($candidateCall.isOperator) {
                continue
            }

            $candidateName = [string]$candidateCall.name

            if ($candidateName -in @(
                "iterator",
                "hasNext",
                "next",
                "__iter__",
                "__next__",
                "<operator>.iterator"
            )) {
                continue
            }

            $distance = 999999
            if ($null -ne $RawControl.line -and $null -ne $candidateCall.line) {
                $distance = [Math]::Abs(
                    [int]$candidateCall.line - [int]$RawControl.line
                )
            }

            # Do not use unrelated body calls as iterable evidence. Normal
            # frontends keep the source iterable on the foreach header line.
            if ($distance -ne 0) {
                continue
            }

            $candidateCode = ([string]$candidateCall.code).Trim()
            $candidateSourceCode = ([string]$candidateCall.sourceCode).Trim()

            $priority = 50

            if (
                $candidateCode -eq $trimmed -or
                $candidateSourceCode -eq $trimmed
            ) {
                $priority = 0
            }
            elseif (
                $terminalCallName -and
                $candidateName -eq $terminalCallName
            ) {
                # javasrc2cpg can rewrite the receiver of array-valued
                # expressions (for example value.toCharArray()) to `this`
                # in raw code while keeping the method name and source line.
                $priority = 10
            }
            else {
                continue
            }

            $candidateCalls.Add(
                [pscustomobject]@{
                    call       = $candidateCall
                    priority   = $priority
                    codeLength = $candidateCode.Length
                }
            )
        }

        $winner = @(
            $candidateCalls |
                Sort-Object `
                    @{ Expression = "priority"; Descending = $false }, `
                    @{ Expression = "codeLength"; Descending = $true }, `
                    @{
                        Expression = {
                            if ($null -eq $_.call.column) {
                                999999
                            }
                            else {
                                [int]$_.call.column
                            }
                        }
                        Descending = $false
                    }, `
                    @{
                        Expression = {
                            [int64]$_.call.id
                        }
                        Descending = $false
                    }
        ) | Select-Object -First 1

        if ($winner) {
            return [string]$winner.call.id
        }

        # Identifiers, literals and non-call iterable expressions continue to
        # use the generic exact-text resolver.
        return & $findRawExpressionByText $trimmed $RawControl.line
    }

    $parseForeach = {
        param([object]$RawControl)

        $sourceText = (Get-SourceSnippetText $RawControl $file).Trim()
        $binding = $null
        $iterable = $null

        if ($Language -eq "java") {
            # Java enhanced-for is lowered to WHILE by the frontend, but
            # parserTypeName preserves the source construct. Prefer the raw
            # sourceCode for ForEachStmt because lowered node offsets/code may
            # describe iterator mechanics rather than the source header.
            if ([string]$RawControl.parserTypeName -eq "ForEachStmt") {
                $rawSourceCode = [string]$RawControl.sourceCode
                if (-not (Test-PlaceholderSourceText $rawSourceCode)) {
                    $sourceText = $rawSourceCode.Trim()
                }
            }

            $javaForeach = Split-JavaEnhancedForHeader $sourceText
            if ($javaForeach) {
                $binding = [string]$javaForeach.binding
                $iterable = [string]$javaForeach.iterable
            }
        }
        elseif ($Language -eq "python") {
            $firstLine = [System.Text.RegularExpressions.Regex]::Split(
                $sourceText,
                "\r\n|\n|\r"
            )[0]

            $match = [System.Text.RegularExpressions.Regex]::Match(
                $firstLine,
                '^\s*for\s+(?<binding>.+?)\s+in\s+(?<iterable>.+?)\s*:\s*$'
            )
            if ($match.Success) {
                $binding = $match.Groups["binding"].Value.Trim()
                $iterable = $match.Groups["iterable"].Value.Trim()
            }
        }
        elseif ($Language -in @("typescript", "javascript")) {
            $match = [System.Text.RegularExpressions.Regex]::Match(
                $sourceText,
                '^\s*for\s*\(\s*(?<binding>.+?)\s+of\s+(?<iterable>.+?)\s*\)\s*\{',
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )
            if ($match.Success) {
                $binding = $match.Groups["binding"].Value.Trim()
                $iterable = $match.Groups["iterable"].Value.Trim()
            }
        }
        elseif ($Language -eq "csharp") {
            $match = [System.Text.RegularExpressions.Regex]::Match(
                $sourceText,
                '^\s*foreach\s*\(\s*(?<binding>.+?)\s+in\s+(?<iterable>.+?)\s*\)',
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )
            if ($match.Success) {
                $binding = $match.Groups["binding"].Value.Trim()
                $iterable = $match.Groups["iterable"].Value.Trim()
            }
        }

        if (
            [string]::IsNullOrWhiteSpace($binding) -or
            [string]::IsNullOrWhiteSpace($iterable)
        ) {
            return $null
        }

        return [pscustomobject]@{
            binding  = $binding
            iterable = $iterable
            source   = $sourceText
        }
    }

    $foreachInfoByRawId = @{}

    foreach ($rawControl in @($rawMethod.controlStructures)) {
        if ([string]$rawControl.kind -notin @("FOR", "WHILE")) {
            continue
        }

        $foreachInfo = & $parseForeach $rawControl
        if ($foreachInfo) {
            $foreachInfoByRawId[[string]$rawControl.id] = $foreachInfo
        }
    }

    # Mark frontend iterator lowering so it cannot become a public body step.
    $suppressedRawNodeIds = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($foreachRawId in @($foreachInfoByRawId.Keys)) {
        $foreachControl = $rawControlById[$foreachRawId]
        $headerLine = $foreachControl.line
        $seedIds = [System.Collections.Generic.List[string]]::new()

        foreach ($node in @($rawMethod.astNodes)) {
            if ($null -ne $headerLine -and $null -ne $node.line -and [int]$node.line -ne [int]$headerLine) {
                continue
            }

            $nodeKind = [string]$node.kind

            # Aggregate container code can contain tmp/iterator lowering text.
            # Never suppress the container subtree because it can also contain
            # real source-semantic controls and business calls.
            if ($nodeKind -in @("Block", "ControlStructure", "Method")) {
                continue
            }

            $rawId = [string]$node.id
            $code = [string]$node.code
            $callName = ""
            if ($callById.ContainsKey($rawId)) {
                $callName = [string]$callById[$rawId].name
            }

            $isLowering = $false

            if (
                $code -match '\$iterLocal' -or
                $code -match 'iteratorNonEmptyOrException' -or
                $code -match '(^|[^A-Za-z0-9_])tmp[0-9]+([^A-Za-z0-9_]|$)' -or
                $code -match '_iterator_' -or
                $code -match '_result_' -or
                $code -match '(^|[^A-Za-z0-9_])_idx_([^A-Za-z0-9_]|$)'
            ) {
                $isLowering = $true
            }

            if ($callName -in @(
                "iterator",
                "hasNext",
                "next",
                "__iter__",
                "__next__",
                "<operator>.iterator"
            )) {
                $isLowering = $true
            }

            if ($isLowering) {
                $seedIds.Add($rawId)
            }
        }

        foreach ($seedId in @($seedIds)) {
            foreach ($descendantId in @(& $getDescendantIds $seedId)) {
                $candidateId = [string]$descendantId

                if ($candidateId -eq [string]$foreachRawId) {
                    continue
                }

                if (
                    $nodeById.ContainsKey($candidateId) -and
                    [string]$nodeById[$candidateId].kind -in @("Block", "ControlStructure", "Method")
                ) {
                    continue
                }

                [void]$suppressedRawNodeIds.Add($candidateId)
            }

            $current = $seedId
            while ($current -and $parentById.ContainsKey($current)) {
                $parentId = $parentById[$current]
                if (-not $parentId -or -not $nodeById.ContainsKey($parentId)) {
                    break
                }

                $parentNode = $nodeById[$parentId]
                if ([string]$parentNode.kind -notin @("Call", "Unknown")) {
                    break
                }

                [void]$suppressedRawNodeIds.Add($parentId)
                $current = $parentId
            }
        }
    }

    foreach ($suppressedId in @($suppressedRawNodeIds)) {
        [void]$suppressedRawNodeIdsGlobal.Add([string]$suppressedId)
    }

    $controlIdByRawId = @{}
    $returnControlIdByRawId = @{}
    $raiseControlIdByRawId = @{}

    $getControlSeed = {
        param(
            [object]$Node,
            [string]$SemanticKind,
            [string]$RawId
        )

        return @(
            $Language,
            $file,
            $methodFullName,
            "CONTROL:" + $SemanticKind,
            [string]$Node.line,
            [string](Convert-PublicColumn $Node.column),
            (& $getAstPath $RawId)
        ) -join "|"
    }

    $getExpressionIdsFromRoots = {
        param([object[]]$RootIds)

        $result = [System.Collections.Generic.List[string]]::new()

        foreach ($rootValue in @($RootIds)) {
            $rootId = [string]$rootValue
            if (-not $nodeById.ContainsKey($rootId)) {
                continue
            }

            $rootNode = $nodeById[$rootId]

            if ([string]$rootNode.kind -eq "Call") {
                $expressionId = & $buildExpression $rootId
                if ($expressionId) {
                    $result.Add($expressionId)
                }
                continue
            }

            if ([string]$rootNode.kind -eq "Block") {
                foreach ($childValue in @($rootNode.childIds)) {
                    $childId = [string]$childValue
                    if (
                        $nodeById.ContainsKey($childId) -and
                        [string]$nodeById[$childId].kind -eq "Call"
                    ) {
                        $expressionId = & $buildExpression $childId
                        if ($expressionId) {
                            $result.Add($expressionId)
                        }
                    }
                }
            }
        }

        return @($result)
    }

    $getSwitchSequenceIds = {
        param([object]$RawControl)

        $directIds = @($RawControl.directChildIds | ForEach-Object { [string]$_ })
        $directHasJumpTarget = $false

        foreach ($rawId in $directIds) {
            if (
                $nodeById.ContainsKey($rawId) -and
                [string]$nodeById[$rawId].kind -eq "JumpTarget"
            ) {
                $directHasJumpTarget = $true
                break
            }
        }

        if ($directHasJumpTarget) {
            return @(
                $directIds |
                    Where-Object {
                        $id = [string]$_
                        -not (@($RawControl.conditionRootIds | ForEach-Object { [string]$_ }) -contains $id)
                    }
            )
        }

        $bodyCandidates = [System.Collections.Generic.List[string]]::new()

        foreach ($rootValue in @($RawControl.trueBodyRootIds)) {
            $bodyCandidates.Add([string]$rootValue)
        }

        foreach ($rawId in $directIds) {
            if (
                $nodeById.ContainsKey($rawId) -and
                [string]$nodeById[$rawId].kind -eq "Block"
            ) {
                if (-not $bodyCandidates.Contains($rawId)) {
                    $bodyCandidates.Add($rawId)
                }
            }
        }

        foreach ($bodyId in @($bodyCandidates)) {
            if (-not $nodeById.ContainsKey($bodyId)) {
                continue
            }

            $bodyNode = $nodeById[$bodyId]
            if ([string]$bodyNode.kind -ne "Block") {
                continue
            }

            $children = @($bodyNode.childIds | ForEach-Object { [string]$_ })
            $hasJump = @(
                $children |
                    Where-Object {
                        $nodeById.ContainsKey($_) -and
                        [string]$nodeById[$_].kind -eq "JumpTarget"
                    }
            ).Count -gt 0

            if ($hasJump) {
                return $children
            }
        }

        return @()
    }

    $findThrowValueRawId = {
        param([object]$RawControl)

        $directRoots = @(
            $RawControl.directChildIds |
                ForEach-Object { [string]$_ }
        )

        # C# exposes `throw new X(...)` directly as the constructor Call.
        # Prefer that exact source expression before searching lowered
        # descendants used by Java/TypeScript frontends.
        foreach ($rootId in $directRoots) {
            if ($callById.ContainsKey($rootId)) {
                $directCall = $callById[$rootId]
                $directCode = ([string]$directCall.code).Trim()

                if (
                    -not $directCall.isOperator -and
                    $directCode -match '^new\s+'
                ) {
                    return $rootId
                }
            }
        }

        $candidateIds = [System.Collections.Generic.List[string]]::new()

        foreach ($rootId in $directRoots) {
            foreach ($rawId in @(& $getDescendantIds $rootId)) {
                if (
                    $callById.ContainsKey([string]$rawId) -and
                    -not $candidateIds.Contains([string]$rawId)
                ) {
                    $candidateIds.Add([string]$rawId)
                }
            }
        }

        $ranked = @(
            @(
                foreach ($rawId in @($candidateIds)) {
                    $call = $callById[$rawId]
                    $name = [string]$call.name
                    $code = ([string]$call.code).Trim()
                    $priority = 10

                    if ($name -eq "<init>" -and $code -match '^new\s+') {
                        $priority = 0
                    }
                    elseif ($name -eq "<operator>.new" -and $code -match '^new\s+') {
                        $priority = 1
                    }
                    elseif ($code -match '^new\s+' -and $name -ne "<operator>.alloc") {
                        $priority = 2
                    }
                    elseif ($name -eq "<operator>.alloc") {
                        $priority = 20
                    }
                    elseif ($name -eq "<operator>.assignment") {
                        $priority = 30
                    }

                    [pscustomobject]@{
                        id       = $rawId
                        priority = $priority
                    }
                }
            ) |
                Sort-Object priority, id
        )

        if (@($ranked).Count -gt 0) {
            return [string]$ranked[0].id
        }

        # Last-resort source-expression fallback: if the THROW owns one
        # direct non-container AST child, normalize that child rather than
        # emitting a THROW with a missing value.
        foreach ($rootId in $directRoots) {
            if (-not $nodeById.ContainsKey($rootId)) {
                continue
            }

            $rootNode = $nodeById[$rootId]
            if ([string]$rootNode.kind -notin @("Block", "ControlStructure", "Method")) {
                return $rootId
            }
        }

        return $null
    }

    foreach ($rawControl in @(
        $rawMethod.controlStructures |
            Sort-Object {
                if ($null -eq $_.line) { 999999 } else { [int]$_.line }
            }, order, id
    )) {
        $rawKind = [string]$rawControl.kind
        $rawId = [string]$rawControl.id

        if ($rawKind -in @("CATCH", "FINALLY")) {
            continue
        }

        if (-not $nodeById.ContainsKey($rawId)) {
            Add-Warning "Control raw node missing: method=$methodFullName rawId=$rawId kind=$rawKind"
            continue
        }

        $semanticKind = $null

        switch ($rawKind) {
            "IF"       { $semanticKind = "IF" }
            "SWITCH"   { $semanticKind = "SWITCH" }
            "MATCH"    { $semanticKind = "MATCH" }
            "FOR"      {
                if ($foreachInfoByRawId.ContainsKey($rawId)) {
                    $semanticKind = "FOREACH"
                }
                else {
                    $semanticKind = "FOR"
                }
            }
            "WHILE"    {
                if ($foreachInfoByRawId.ContainsKey($rawId)) {
                    $semanticKind = "FOREACH"
                }
                else {
                    $semanticKind = "WHILE"
                }
            }
            "DO"       { $semanticKind = "DO_WHILE" }
            "DO_WHILE" { $semanticKind = "DO_WHILE" }
            "TRY"      { $semanticKind = "TRY" }
            "THROW"    { $semanticKind = "THROW" }
            "BREAK"    { $semanticKind = "BREAK" }
            "CONTINUE" { $semanticKind = "CONTINUE" }
            default    { $semanticKind = $null }
        }

        if (-not $semanticKind) {
            continue
        }

        $node = $nodeById[$rawId]
        $seed = & $getControlSeed $node $semanticKind $rawId
        $controlId = Get-HashId "ctrl" $seed
        Register-NormalizedId $controlId
        $controlIdByRawId[$rawId] = $controlId

        $conditionExpressionId = $null
        $valueExpressionId = $null
        $iterableExpressionId = $null
        $iterationBinding = $null
        $initExpressionIds = @()
        $updateExpressionIds = @()
        $branches = [System.Collections.Generic.List[object]]::new()
        $rawNodeIds = [System.Collections.Generic.List[string]]::new()
        $rawNodeIds.Add($rawId)

        if ($semanticKind -in @("IF", "SWITCH", "MATCH", "FOR", "WHILE", "DO_WHILE")) {
            $conditionRoots = @($rawControl.conditionRootIds)
            if ($conditionRoots.Count -gt 0) {
                $conditionExpressionId = & $buildExpression ([string]$conditionRoots[0])
            }
        }

        if ($semanticKind -eq "IF") {
            $trueRoots = @($rawControl.ifTrueRootIds)
            if ($trueRoots.Count -eq 0) {
                $trueRoots = @($rawControl.trueBodyRootIds)
            }

            $falseRoots = @($rawControl.ifFalseRootIds)
            if ($falseRoots.Count -eq 0) {
                $falseRoots = @($rawControl.falseBodyRootIds)
            }

            foreach ($branchSpec in @(
                [pscustomobject]@{ kind = "TRUE"; roots = $trueRoots },
                [pscustomobject]@{ kind = "FALSE"; roots = $falseRoots }
            )) {
                $branchId = Get-HashId "branch" ($seed + "|BRANCH:" + $branchSpec.kind)
                Register-NormalizedId $branchId

                $branchObject = [pscustomobject][ordered]@{
                    id     = $branchId
                    kind   = [string]$branchSpec.kind
                    label  = $null
                    source = $null
                    body   = @()
                }

                Add-Member -InputObject $branchObject -NotePropertyName _rawRoots -NotePropertyValue @($branchSpec.roots)
                $branches.Add($branchObject)
            }
        }
        elseif ($semanticKind -in @("FOR", "WHILE", "DO_WHILE", "FOREACH")) {
            $bodyRoots = @()

            if ($semanticKind -eq "FOR") {
                $initExpressionIds = @(& $getExpressionIdsFromRoots @($rawControl.forInitRootIds))
                $updateExpressionIds = @(& $getExpressionIdsFromRoots @($rawControl.forUpdateRootIds))
                $bodyRoots = @($rawControl.forBodyRootIds)
            }
            elseif ($semanticKind -eq "FOREACH") {
                $conditionExpressionId = $null
                $initExpressionIds = @()
                $updateExpressionIds = @()

                $foreachInfo = $foreachInfoByRawId[$rawId]
                $baseSnippet = New-SourceSnippet $rawControl $file

                $bindingPosition = & $getSourceSnippetPosition $baseSnippet ([string]$foreachInfo.binding)
                $iterationBinding = New-ExplicitSourceSnippet `
                    $file `
                    $bindingPosition.line `
                    $bindingPosition.column `
                    ([string]$foreachInfo.binding)

                $iterableRawId = & $findForeachIterableRawId `
                    ([string]$foreachInfo.iterable) `
                    $rawControl

                if ($iterableRawId) {
                    $iterableExpressionId = & $buildExpression $iterableRawId
                }
                else {
                    $iterableExpressionId = & $newSemanticExpression `
                        ("FOREACH_ITERABLE:" + $rawId) `
                        ([string]$foreachInfo.iterable) `
                        $baseSnippet `
                        @($rawId)
                }

                if (@($rawControl.forBodyRootIds).Count -gt 0) {
                    $bodyRoots = @($rawControl.forBodyRootIds)
                }
                else {
                    $bodyRoots = @($rawControl.trueBodyRootIds)
                }

                $report.foreachNormalizations++
            }
            elseif ($semanticKind -eq "WHILE") {
                $bodyRoots = @($rawControl.trueBodyRootIds)
            }
            else {
                $bodyRoots = @($rawControl.doBodyRootIds)
                if ($bodyRoots.Count -eq 0) {
                    $bodyRoots = @($rawControl.trueBodyRootIds)
                }
            }

            $branchId = Get-HashId "branch" ($seed + "|BRANCH:BODY")
            Register-NormalizedId $branchId

            $branchObject = [pscustomobject][ordered]@{
                id     = $branchId
                kind   = "BODY"
                label  = $null
                source = $null
                body   = @()
            }

            Add-Member -InputObject $branchObject -NotePropertyName _rawRoots -NotePropertyValue @($bodyRoots)
            $branches.Add($branchObject)
        }
        elseif ($semanticKind -in @("SWITCH", "MATCH")) {
            $sequenceIds = @(& $getSwitchSequenceIds $rawControl)
            $currentBranch = $null
            $caseIndex = 0

            foreach ($itemValue in $sequenceIds) {
                $itemId = [string]$itemValue
                if (-not $nodeById.ContainsKey($itemId)) {
                    continue
                }

                $itemNode = $nodeById[$itemId]

                if ([string]$itemNode.kind -eq "JumpTarget") {
                    $rawLabel = ([string]$itemNode.code).Trim().TrimEnd([char]':')
                    $branchKind = "CASE"
                    $label = $rawLabel

                    if ($rawLabel -match '^(?i)default$') {
                        $branchKind = "DEFAULT"
                        $label = "default"
                    }
                    elseif ($rawLabel -notmatch '^(?i)case\s+') {
                        $label = "case " + $rawLabel
                    }

                    $branchId = Get-HashId "branch" (
                        $seed + "|BRANCH:" + $branchKind + ":" + $caseIndex + ":" + $label
                    )
                    Register-NormalizedId $branchId
                    $caseIndex++

                    $branchSource = $null
                    if ($null -ne $itemNode.line) {
                        $branchSource = New-SourceSnippet $itemNode $file
                    }

                    $currentBranch = [pscustomobject][ordered]@{
                        id     = $branchId
                        kind   = $branchKind
                        label  = $label
                        source = $branchSource
                        body   = @()
                    }

                    Add-Member -InputObject $currentBranch -NotePropertyName _rawNodes -NotePropertyValue ([System.Collections.Generic.List[string]]::new())
                    $branches.Add($currentBranch)
                    continue
                }

                if ($currentBranch) {
                    $currentBranch._rawNodes.Add($itemId)
                }
            }

            if ($branches.Count -eq 0) {
                Add-Warning "No CASE/DEFAULT branches found: method=$methodFullName control=$rawId"
            }
        }
        elseif ($semanticKind -eq "TRY") {
            $tryBranchId = Get-HashId "branch" ($seed + "|BRANCH:TRY")
            Register-NormalizedId $tryBranchId

            $tryBranch = [pscustomobject][ordered]@{
                id     = $tryBranchId
                kind   = "TRY"
                label  = $null
                source = $null
                body   = @()
            }

            Add-Member -InputObject $tryBranch -NotePropertyName _rawRoots -NotePropertyValue @($rawControl.tryBodyRootIds)
            $branches.Add($tryBranch)

            $catchIndex = 0
            foreach ($catchValue in @($rawControl.catchBodyRootIds)) {
                $catchRawId = [string]$catchValue
                [void]$rawNodeIds.Add($catchRawId)

                if (-not $rawControlById.ContainsKey($catchRawId)) {
                    Add-Warning "TRY catch root is not a raw control: method=$methodFullName rawId=$catchRawId"
                    continue
                }

                $catchControl = $rawControlById[$catchRawId]
                $catchBranchId = Get-HashId "branch" (
                    $seed + "|BRANCH:CATCH:" + $catchIndex + ":" + $catchRawId
                )
                Register-NormalizedId $catchBranchId
                $catchIndex++

                $catchSource = $null
                $catchLabel = "catch"

                if ($Language -eq "python") {
                    $catchLabel = "except"
                }
                else {
                    $catchSource = New-SourceSnippet $catchControl $file
                    $catchText = ([string]$catchSource.text).Trim()
                    if ($catchText) {
                        $catchLabel = [System.Text.RegularExpressions.Regex]::Split(
                            $catchText,
                            "\r\n|\n|\r"
                        )[0].Trim()
                    }
                }

                $catchBranch = [pscustomobject][ordered]@{
                    id     = $catchBranchId
                    kind   = "CATCH"
                    label  = $catchLabel
                    source = $catchSource
                    body   = @()
                }

                Add-Member -InputObject $catchBranch -NotePropertyName _rawRoots -NotePropertyValue @($catchControl.directChildIds)
                $branches.Add($catchBranch)
            }

            $finallyIndex = 0
            foreach ($finallyValue in @($rawControl.finallyBodyRootIds)) {
                $finallyRawId = [string]$finallyValue
                [void]$rawNodeIds.Add($finallyRawId)

                if (-not $rawControlById.ContainsKey($finallyRawId)) {
                    Add-Warning "TRY finally root is not a raw control: method=$methodFullName rawId=$finallyRawId"
                    continue
                }

                $finallyControl = $rawControlById[$finallyRawId]
                $finallyBranchId = Get-HashId "branch" (
                    $seed + "|BRANCH:FINALLY:" + $finallyIndex + ":" + $finallyRawId
                )
                Register-NormalizedId $finallyBranchId
                $finallyIndex++

                $finallySource = $null
                if ($Language -ne "python") {
                    $finallySource = New-SourceSnippet $finallyControl $file
                }

                $finallyBranch = [pscustomobject][ordered]@{
                    id     = $finallyBranchId
                    kind   = "FINALLY"
                    label  = "finally"
                    source = $finallySource
                    body   = @()
                }

                Add-Member -InputObject $finallyBranch -NotePropertyName _rawRoots -NotePropertyValue @($finallyControl.directChildIds)
                $branches.Add($finallyBranch)
            }
        }
        elseif ($semanticKind -eq "THROW") {
            $throwValueRawId = & $findThrowValueRawId $rawControl
            if ($throwValueRawId) {
                $valueExpressionId = & $buildExpression $throwValueRawId
            }
            $report.throwRaiseNormalizations++
        }

        $controls.Add(
            [pscustomobject][ordered]@{
                id                    = $controlId
                method                = $methodFullName
                kind                  = $semanticKind
                source                = (New-SourceSnippet $rawControl $file)
                conditionExpressionId = $conditionExpressionId
                valueExpressionId     = $valueExpressionId
                iterableExpressionId  = $iterableExpressionId
                iterationBinding      = $iterationBinding
                initExpressionIds     = @($initExpressionIds)
                updateExpressionIds   = @($updateExpressionIds)
                branches              = @($branches)
                rawNodeIds            = @($rawNodeIds | Sort-Object -Unique)
            }
        )

        $report.normalizedControls++
    }

    # Python raise is an operator call rather than a raw ControlStructure.
    foreach ($raiseCall in @(
        $rawMethod.calls |
            Where-Object { [string]$_.name -eq "<operator>.raise" }
    )) {
        $rawId = [string]$raiseCall.id

        if (-not $nodeById.ContainsKey($rawId)) {
            continue
        }

        $node = $nodeById[$rawId]
        $seed = & $getControlSeed $node "THROW" $rawId
        $controlId = Get-HashId "ctrl" $seed
        Register-NormalizedId $controlId
        $raiseControlIdByRawId[$rawId] = $controlId

        $valueExpressionId = $null
        $arguments = @($raiseCall.arguments | Sort-Object argumentIndex, order, id)
        if ($arguments.Count -gt 0) {
            $valueExpressionId = & $buildExpression ([string]$arguments[0].id)
        }

        $controls.Add(
            [pscustomobject][ordered]@{
                id                    = $controlId
                method                = $methodFullName
                kind                  = "THROW"
                source                = (New-SourceSnippet $node $file)
                conditionExpressionId = $null
                valueExpressionId     = $valueExpressionId
                iterableExpressionId  = $null
                iterationBinding      = $null
                initExpressionIds     = @()
                updateExpressionIds   = @()
                branches              = @()
                rawNodeIds            = @($rawId)
            }
        )

        $report.throwRaiseNormalizations++
        $report.normalizedControls++
    }

    $findReturnValueRawId = {
        param([object]$ReturnNode)

        $children = @($ReturnNode.childIds | ForEach-Object { [string]$_ })
        if ($children.Count -eq 0) {
            return $null
        }

        # Java lowers `return new X(...)` into a synthetic Block containing
        # allocation/assignment mechanics plus the real <init> call. Returning
        # the Block itself loses the constructor and all nested source calls.
        if ($Language -eq "java" -and $children.Count -eq 1) {
            $rootId = [string]$children[0]

            if (
                $nodeById.ContainsKey($rootId) -and
                [string]$nodeById[$rootId].kind -eq "Block"
            ) {
                $constructorCandidates = [System.Collections.Generic.List[object]]::new()

                foreach ($candidateId in @(& $getDescendantIds $rootId)) {
                    $candidateRawId = [string]$candidateId

                    if (-not $callById.ContainsKey($candidateRawId)) {
                        continue
                    }

                    $candidateCall = $callById[$candidateRawId]
                    if (
                        [string]$candidateCall.name -ne "<init>" -or
                        ([string]$candidateCall.code).Trim() -notmatch '^new\s+'
                    ) {
                        continue
                    }

                    $constructorCandidates.Add(
                        [pscustomobject]@{
                            id         = $candidateRawId
                            codeLength = ([string]$candidateCall.code).Length
                            order      = [int]$candidateCall.order
                        }
                    )
                }

                $outerConstructor = @(
                    $constructorCandidates |
                        Sort-Object `
                            @{ Expression = "codeLength"; Descending = $true }, `
                            @{ Expression = "order"; Descending = $false }, `
                            @{ Expression = "id"; Descending = $false }
                ) | Select-Object -First 1

                if ($outerConstructor) {
                    return [string]$outerConstructor.id
                }

                # Keep the wrapper as a semantic OTHER expression if this is
                # not constructor lowering. buildExpression now traverses
                # non-call wrapper children.
                return $rootId
            }
        }

        # Normal return expressions already expose their source expression as
        # the first AST child.
        return [string]$children[0]
    }

    # RETURN is an AST node, not a ControlStructure node.
    foreach ($node in @($rawMethod.astNodes)) {
        if ([string]$node.kind -ne "Return") {
            continue
        }

        $rawId = [string]$node.id
        $seed = & $getControlSeed $node "RETURN" $rawId
        $controlId = Get-HashId "ctrl" $seed
        Register-NormalizedId $controlId
        $returnControlIdByRawId[$rawId] = $controlId

        $valueExpressionId = $null
        $returnValueRawId = & $findReturnValueRawId $node

        if ($returnValueRawId) {
            $valueExpressionId = & $buildExpression ([string]$returnValueRawId)
        }

        $controls.Add(
            [pscustomobject][ordered]@{
                id                    = $controlId
                method                = $methodFullName
                kind                  = "RETURN"
                source                = (New-SourceSnippet $node $file)
                conditionExpressionId = $null
                valueExpressionId     = $valueExpressionId
                iterableExpressionId  = $null
                iterationBinding      = $null
                initExpressionIds     = @()
                updateExpressionIds   = @()
                branches              = @()
                rawNodeIds            = @($rawId)
            }
        )

        $report.returnsNormalized++
        $report.normalizedControls++
    }

    $getNodeSteps = $null
    $getNodeSteps = {
        param([object[]]$RawIds)

        $steps = [System.Collections.Generic.List[object]]::new()

        $nodes = @(
            foreach ($rawValue in @($RawIds)) {
                $rawId = [string]$rawValue
                if ($nodeById.ContainsKey($rawId)) {
                    $nodeById[$rawId]
                }
            }
        ) | Sort-Object order, {
            if ($null -eq $_.line) { 999999 } else { [int]$_.line }
        }, {
            if ($null -eq $_.column) { 999999 } else { [int]$_.column }
        }, id

        foreach ($child in $nodes) {
            $rawId = [string]$child.id
            $kind = [string]$child.kind

            # Semantic routing containers must be processed before lowering
            # suppression; otherwise a synthetic wrapper can hide a real
            # FOREACH/IF/RETURN subtree.
            if ($kind -eq "ControlStructure") {
                if ($controlIdByRawId.ContainsKey($rawId)) {
                    $steps.Add(
                        [pscustomobject][ordered]@{
                            kind = "CONTROL"
                            id   = [string]$controlIdByRawId[$rawId]
                        }
                    )
                }
                elseif (
                    $rawControlById.ContainsKey($rawId) -and
                    [string]$rawControlById[$rawId].kind -in @("CATCH", "FINALLY")
                ) {
                    # Owned by the enclosing TRY control.
                }
                else {
                    $report.unsupportedControlSteps++
                }
                continue
            }

            if ($kind -eq "Block") {
                foreach ($nestedStep in @(& $getNodeSteps @($child.childIds))) {
                    $steps.Add($nestedStep)
                }
                continue
            }

            if ($suppressedRawNodeIds.Contains($rawId)) {
                continue
            }

            if ($kind -eq "Call") {
                if ($raiseControlIdByRawId.ContainsKey($rawId)) {
                    $steps.Add(
                        [pscustomobject][ordered]@{
                            kind = "CONTROL"
                            id   = [string]$raiseControlIdByRawId[$rawId]
                        }
                    )
                    continue
                }

                $expressionId = & $buildExpression $rawId
                if ($expressionId) {
                    $steps.Add(
                        [pscustomobject][ordered]@{
                            kind = "EXPRESSION"
                            id   = $expressionId
                        }
                    )
                }
            }
            elseif ($kind -eq "Return") {
                if ($returnControlIdByRawId.ContainsKey($rawId)) {
                    $steps.Add(
                        [pscustomobject][ordered]@{
                            kind = "CONTROL"
                            id   = [string]$returnControlIdByRawId[$rawId]
                        }
                    )
                }
            }
            else {
                # Frontends can wrap source expressions in Local/Unknown/etc.
                # Recurse through those containers so real CALL roots are not
                # lost. We deliberately stop at Call/Return/ControlStructure
                # above, so nested calls are not emitted twice as body steps.
                foreach ($nestedStep in @(& $getNodeSteps @($child.childIds))) {
                    $steps.Add($nestedStep)
                }
            }
        }

        return @($steps)
    }

    # Fill every normalized branch now that all controls and RETURN/THROW nodes exist.
    foreach ($control in @($controls | Where-Object { $_.method -eq $methodFullName })) {
        foreach ($branch in @($control.branches)) {
            $body = [System.Collections.Generic.List[object]]::new()

            if ($branch.PSObject.Properties.Name -contains "_rawRoots") {
                foreach ($rootId in @($branch._rawRoots)) {
                    foreach ($step in @(& $getNodeSteps @([string]$rootId))) {
                        $body.Add($step)
                    }
                }
                $branch.PSObject.Properties.Remove("_rawRoots")
            }

            if ($branch.PSObject.Properties.Name -contains "_rawNodes") {
                foreach ($step in @(& $getNodeSteps @($branch._rawNodes))) {
                    $body.Add($step)
                }
                $branch.PSObject.Properties.Remove("_rawNodes")
            }

            $branch.body = @($body)
        }
    }

    $rootBlocks = @(
        $rawMethod.astNodes |
            Where-Object {
                $_.kind -eq "Block" -and
                @($_.parentIds | ForEach-Object { [string]$_ }) -contains [string]$rawMethod.id
            } |
            Sort-Object order
    )

    if ($rootBlocks.Count -gt 0) {
        $method.body = @(& $getNodeSteps @([string]$rootBlocks[0].id))
    }
    else {
        Add-Warning "Method has no root block: $methodFullName"
    }
}

# -----------------------------------------------------------------------------
# Final report counters and output
# -----------------------------------------------------------------------------

$includedRawNonOperatorCallIds = [System.Collections.Generic.HashSet[string]]::new()

foreach ($rawMethod in $cleanRawMethods) {
    foreach ($call in @($rawMethod.calls)) {
        if (-not $call.isOperator) {
            [void]$includedRawNonOperatorCallIds.Add([string]$call.id)
        }
    }
}

$unmappedCallCount = 0
$unmappedCallNameCounts = @{}
$unmappedCallSamples = [System.Collections.Generic.List[object]]::new()

foreach ($rawMethod in $cleanRawMethods) {
    foreach ($rawCall in @($rawMethod.calls)) {
        if ($rawCall.isOperator) {
            continue
        }

        $rawId = [string]$rawCall.id

        if ($normalizedRawNonOperatorCallIds.Contains($rawId)) {
            continue
        }

        if ($suppressedRawNodeIdsGlobal.Contains($rawId)) {
            continue
        }

        $unmappedCallCount++

        $callName = [string]$rawCall.name
        if ([string]::IsNullOrWhiteSpace($callName)) {
            $callName = "<unnamed>"
        }

        if (-not $unmappedCallNameCounts.ContainsKey($callName)) {
            $unmappedCallNameCounts[$callName] = 0
        }
        $unmappedCallNameCounts[$callName]++

        if ($unmappedCallSamples.Count -lt 100) {
            $unmappedCallSamples.Add(
                [pscustomobject][ordered]@{
                    rawId  = $rawId
                    caller = [string]$rawMethod.fullName
                    file   = (Normalize-FilePath ([string]$rawMethod.file))
                    line   = $rawCall.line
                    name   = $callName
                    code   = [string]$rawCall.code
                }
            )
        }
    }
}

$report.unmappedRawCalls = $unmappedCallCount
$report.unmappedRawCallByName = @(
    foreach ($entry in $unmappedCallNameCounts.GetEnumerator()) {
        [pscustomobject][ordered]@{
            name  = [string]$entry.Key
            count = [int]$entry.Value
        }
    }
) | Sort-Object `
        @{ Expression = "count"; Descending = $true }, `
        @{ Expression = "name"; Descending = $false }

$report.unmappedRawCallSamples = @($unmappedCallSamples)
$report.syntheticNodesSuppressed = @($suppressedRawNodeIdsGlobal).Count

$normalizedRawControlIds = [System.Collections.Generic.HashSet[string]]::new()
$allRawControlIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($rawMethod in $cleanRawMethods) {
    foreach ($rawControl in @($rawMethod.controlStructures)) {
        [void]$allRawControlIds.Add([string]$rawControl.id)
    }
}

$normalizedRawControlIds.Clear()
foreach ($control in @($controls)) {
    foreach ($rawId in @($control.rawNodeIds)) {
        if ($allRawControlIds.Contains([string]$rawId)) {
            [void]$normalizedRawControlIds.Add([string]$rawId)
        }
    }
}

$report.unmappedRawControls = [Math]::Max(
    0,
    $allRawControlIds.Count - $normalizedRawControlIds.Count
)

$externalCallSites = @(
    $callSites |
        Where-Object { $_.classification -ne "internal" }
).Count

$model = [pscustomobject][ordered]@{
    schemaVersion = 4
    language      = $Language
    scope         = $(if ($IncludeTests) { "all" } else { "production" })
    summary       = [pscustomobject][ordered]@{
        types               = @($types).Count
        methods             = @($methods).Count
        callSites           = @($callSites).Count
        externalCallSites   = $externalCallSites
        expressions         = @($expressions).Count
        controls            = @($controls).Count
        excludedTestTypes   = [int]$report.excludedTestTypes
        excludedTestMethods = [int]$report.excludedTestMethods
    }
    types         = @($types)
    methods       = @($methods)
    callSites     = @($callSites)
    expressions   = @($expressions)
    controls      = @($controls)
}

$report.warnings = @($warnings)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$modelJson = $model | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($OutputPath, $modelJson, $utf8NoBom)

$reportJson = ([pscustomobject]$report) | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($reportPath, $reportJson, $utf8NoBom)

Write-Host ""
Write-Host "================================"
Write-Host "V4 NORMALIZATION SLICE B2"
Write-Host "================================"
Write-Host ("Language:     " + $Language)
Write-Host ("Types:        " + $model.summary.types)
Write-Host ("Methods:      " + $model.summary.methods)
Write-Host ("Call sites:   " + $model.summary.callSites)
Write-Host ("Expressions:  " + $model.summary.expressions)
Write-Host ("Controls:     " + $model.summary.controls)
Write-Host ("FOREACH:      " + $report.foreachNormalizations)
Write-Host ("THROW/raise:  " + $report.throwRaiseNormalizations)
Write-Host ("Synthetic raw nodes suppressed: " + $report.syntheticNodesSuppressed)
Write-Host ("Unmapped raw controls:          " + $report.unmappedRawControls)
Write-Host ("Unmapped raw calls:             " + $report.unmappedRawCalls)
Write-Host ""
Write-Host "Model:"
Write-Host $OutputPath
Write-Host ""
Write-Host "Report:"
Write-Host $reportPath
