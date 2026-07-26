#Requires -Version 7.0
<#
.SYNOPSIS
    Generate the synthetic estate a category's declarative-collector equivalence proof runs on
    (AB#5659).

.DESCRIPTION
    `tests/DeclarativeCollectorEquivalence.Tests.ps1` proves a `.psd1` definition produces the
    same rows as the `.ps1` it was lifted from. That proof is only worth anything if the fixture
    it runs on actually REACHES every expression in the collector: a fixture whose resources have
    no `properties` bag makes both paths emit a row of nulls and compare equal, which proves
    nothing at all.

    Hand-authoring such a fixture for 115 collectors -- roughly 19 fields each, several of them
    nested three levels deep inside `properties` -- is not realistic, and the existing per-category
    mock estates in `tests/*.Module.Tests.ps1` populate only the handful of properties those tests
    assert on. So the estate is DERIVED FROM THE DEFINITION ITSELF: this script reads the same
    per-resource script text the interpreter builds (preamble + field expressions), walks its AST
    for every property path rooted at the collector's own row variable, and synthesises a resource
    with exactly those paths populated.

    That inverts the usual risk. A fixture written by hand tends to under-populate (silent vacuous
    pass); a fixture derived from the expressions cannot, because every path the collector reads is
    present by construction. What it CANNOT do is invent realistic VALUES -- see 'Honest limits'.

.NOTES
    HOW THE SHAPE IS DERIVED

    Only two roots are known a priori: the row variable (`$1` for almost every collector -- the
    definition records its real name) and, transitively, any local the preamble assigns from it
    (`$data = $1.PROPERTIES`, `$sku = $data.sku`) or any `foreach` variable bound to a collection
    reached from it (`foreach ($loc in $data.locations)`). Aliases are resolved by repeated passes
    over the AST until they stop changing, so a chain of three or four assignments resolves
    regardless of the order the nodes come back in.

    Leaf VALUES are inferred from how the expression uses the path, because the wrong kind of value
    makes both paths throw rather than diverge:

      * `.split('/')`, `-replace`, `.substring(...)`   -> a slash-delimited string with 16 segments,
                                                          so any fixed `[8]`/`[10]` index resolves
      * `[int]` / `[decimal]` casts, or arithmetic     -> a number
      * `[datetime]` cast, or a date-shaped name       -> an ISO-8601 timestamp
      * `@(...)`, `.count`, `foreach ($x in ...)`      -> an array (of objects, when the loop
                                                          variable's own sub-paths are read)
      * anything else                                  -> a short opaque string

    WHY VALUE CHOICE MATTERS FOR CORRECTNESS OF THE PROOF, NOT JUST COVERAGE

    If a field expression throws, the two paths do NOT fail the same way. The interpreter's row is
    one `@{ ... }` statement, so a throw emits nothing; the original collector assigns `$obj = @{...}`
    and then writes `$obj`, so a throw leaves the PREVIOUS iteration's `$obj` in scope and the
    collector emits a duplicate of the last good row. A fixture that provokes a throw therefore
    reports a difference that is real but is a property of the legacy code, not of the conversion.
    Values are chosen to keep every expression evaluable for that reason.

    THE SIX VARIANTS

    Per declared resource type, six resources, each carrying the whole shape and differing only in
    the case it exercises: one tag; two tags (row expansion and the `$ResUCount` 1->0 transition);
    no tags (the `$Tags = '0'` fallback); a subscription absent from `$Sub`; one retirement; two
    retirements (the many-branch of the retirement fold, which every collector copy-pastes). For a
    multi-type collector the types are emitted ROUND-ROBIN rather than grouped, so the fixture
    disproves rather than accommodates a `ResourceTypes`-as-membership-test interpretation
    (declarative-collectors.md §2.5).

    HONEST LIMITS

    Values are synthetic and semantically meaningless -- `res-value` where a real estate has
    `Standard_LRS`. This fixture proves the two implementations agree on the SAME input over the
    paths the collector reads; it does not prove either is correct about a real tenant, and it
    cannot surface a real-world shape nobody's expression anticipates (a property that is
    sometimes a string and sometimes an object). Recorded live payloads (AB#5667,
    `tests/fixtures/captured-*.json`) cover 29 resource types and are the right input for that
    question; they do not reach most of these collectors.

    Tracks ADO AB#5659 (Feature AB#5656, Epic AB#5638).

.PARAMETER Category
    Category folder under manifests/collectors to generate a fixture for.

.PARAMETER OutputPath
    Where to write the fixture. Defaults to
    tests/fixtures/collector-equivalence/<Category>.json.

.OUTPUTS
    The path written.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Category,

    [Parameter()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
. (Join-Path $RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')

# --- Shape tree -------------------------------------------------------------------------------
#
# One node per property path reached from the row variable. Children are named sub-properties;
# Element is the shape of an array's items (populated only when something iterates or indexes the
# node). Usages are the syntactic contexts the path appeared in, which is what picks its value.

function New-ShapeNode {
    param([string]$Name = '')
    [PSCustomObject]@{
        Name     = $Name
        Children = [ordered]@{}
        Element  = $null
        IsArray  = $false
        Usages   = [System.Collections.Generic.HashSet[string]]::new()
    }
}

function Get-ShapeChild {
    param([PSCustomObject]$Node, [string]$Name)
    foreach ($Key in @($Node.Children.Keys)) {
        if ($Key -ieq $Name) { return $Node.Children[$Key] }
    }
    $Child = New-ShapeNode -Name $Name
    $Node.Children[$Name] = $Child
    return $Child
}

function Get-ShapeElement {
    param([PSCustomObject]$Node)
    $Node.IsArray = $true
    if ($null -eq $Node.Element) { $Node.Element = New-ShapeNode -Name ($Node.Name + 'Item') }
    return $Node.Element
}

# Member names that describe a COLLECTION rather than a property of the payload. Treating
# `$data.ipFilterRules.count` as "a property called count" would make the node an object and the
# `[string]@(...).count` field render as an empty string on both paths -- equal, and vacuous.
$script:CollectionMembers = @('count', 'length')

# Reflection surfaces that are never part of an ARM payload. `$1.tags.psobject.properties` is the
# universal tag-detection idiom; tags are synthesised explicitly, so the walk must stop here rather
# than inventing a `psobject` property.
$script:ReflectionMembers = @('psobject', 'pstypenames', 'keys', 'values', 'getenumerator', 'gettype')

function Resolve-ShapePath {
    <#
        Map one AST expression node onto a shape node, or $null when it is not a property path
        rooted at something we know. Deliberately conservative: an unresolvable root yields $null
        and the walk simply learns nothing from that expression, rather than guessing.
    #>
    param(
        [System.Management.Automation.Language.Ast]$Node,
        [hashtable]$Aliases
    )

    if ($null -eq $Node) { return $null }

    if ($Node -is [System.Management.Automation.Language.ParenExpressionAst]) {
        return Resolve-ShapePath -Node $Node.Pipeline -Aliases $Aliases
    }
    if ($Node -is [System.Management.Automation.Language.PipelineAst] -and $Node.PipelineElements.Count -eq 1) {
        return Resolve-ShapePath -Node $Node.PipelineElements[0] -Aliases $Aliases
    }
    if ($Node -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Resolve-ShapePath -Node $Node.Expression -Aliases $Aliases
    }
    if ($Node -is [System.Management.Automation.Language.StatementBlockAst] -and $Node.Statements.Count -eq 1) {
        # The inside of `@( ... )` / `$( ... )` is a statement block, not a pipeline. Without this,
        # the near-universal `@($data.some.list).count -gt 1` idiom resolved to nothing and the
        # property came out a scalar string -- so the "more than one" branch of every
        # comma-joining field was never exercised by the fixture.
        return Resolve-ShapePath -Node $Node.Statements[0] -Aliases $Aliases
    }

    if ($Node -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $Key = $Node.VariablePath.UserPath
        foreach ($Alias in $Aliases.Keys) {
            if ($Alias -ieq $Key) { return $Aliases[$Alias] }
        }
        return $null
    }

    if ($Node -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        # @( <path> ) -- the path is being treated as a collection.
        $Inner = Resolve-ShapePath -Node $Node.SubExpression -Aliases $Aliases
        if ($Inner) { [void]$Inner.Usages.Add('array'); $Inner.IsArray = $true }
        return $null
    }

    if ($Node -is [System.Management.Automation.Language.IndexExpressionAst]) {
        $Target = Resolve-ShapePath -Node $Node.Target -Aliases $Aliases
        if (-not $Target) { return $null }
        [void]$Target.Usages.Add('index')
        return Get-ShapeElement -Node $Target
    }

    if ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        # A method call: record how the target is used, but the RESULT is not a property path.
        $Target = Resolve-ShapePath -Node $Node.Expression -Aliases $Aliases
        if ($Target -and $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            [void]$Target.Usages.Add('method:' + $Node.Member.Value.ToLowerInvariant())
        }
        return $null
    }

    if ($Node -is [System.Management.Automation.Language.MemberExpressionAst]) {
        if ($Node.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $null }
        $MemberName = $Node.Member.Value
        $Target = Resolve-ShapePath -Node $Node.Expression -Aliases $Aliases
        if (-not $Target) { return $null }

        if ($script:ReflectionMembers -contains $MemberName.ToLowerInvariant()) { return $null }
        if ($script:CollectionMembers -contains $MemberName.ToLowerInvariant()) {
            [void]$Target.Usages.Add('array')
            $Target.IsArray = $true
            return $null
        }
        return Get-ShapeChild -Node $Target -Name $MemberName
    }

    if ($Node -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $Inner = Resolve-ShapePath -Node $Node.Child -Aliases $Aliases
        if ($Inner) {
            $TypeName = $Node.Type.TypeName.Name.ToLowerInvariant()
            switch -Regex ($TypeName) {
                '^(int|int32|int64|long|double|decimal|single|float|uint32|uint64)$' { [void]$Inner.Usages.Add('number') }
                '^datetime$'                                                        { [void]$Inner.Usages.Add('datetime') }
                '^(array|object\[\]|string\[\])$'                                    { [void]$Inner.Usages.Add('array'); $Inner.IsArray = $true }
                default { }
            }
        }
        return $Inner
    }

    return $null
}

function Add-ShapeUsageFromOperators {
    <# Arithmetic and string operators tell us whether a leaf must be numeric. #>
    param([System.Management.Automation.Language.Ast]$Ast, [hashtable]$Aliases)

    foreach ($Binary in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)) {
        $Usage = switch ($Binary.Operator) {
            'Divide'   { 'number' }
            'Multiply' { 'number' }
            'Minus'    { 'number' }
            'Replace'  { 'path' }
            'Join'     { 'array' }
            'Split'    { 'path' }
            default    { $null }
        }
        if (-not $Usage) { continue }
        foreach ($Side in @($Binary.Left, $Binary.Right)) {
            $Node = Resolve-ShapePath -Node $Side -Aliases $Aliases
            if ($Node) {
                [void]$Node.Usages.Add($Usage)
                if ($Usage -eq 'array') { $Node.IsArray = $true }
            }
        }
    }
}

function Add-ShapeUsageFromCommands {
    <#
        A path handed to a date cmdlet or a [datetime] parse has to BE a date. `Analytics/EvtHub.ps1`
        writes `[string](get-date($data.createdAt))`, whose property name ('createdAt') gives no hint
        of that -- and a non-date value there does not produce a wrong row, it makes parameter
        binding throw, which takes the whole collector down.
    #>
    param([System.Management.Automation.Language.Ast]$Ast, [hashtable]$Aliases)

    $DateCommands = @('get-date', 'new-timespan', 'set-date')

    foreach ($Command in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $CommandName = $Command.GetCommandName()
        if (-not $CommandName -or $DateCommands -notcontains $CommandName.ToLowerInvariant()) { continue }
        foreach ($Element in $Command.CommandElements) {
            $Node = Resolve-ShapePath -Node $Element -Aliases $Aliases
            if ($Node) { [void]$Node.Usages.Add('datetime') }
        }
    }

    foreach ($Invoke in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
        if ($Invoke.Expression -isnot [System.Management.Automation.Language.TypeExpressionAst]) { continue }
        if ($Invoke.Expression.TypeName.Name -notmatch '(?i)^(datetime|timespan)$') { continue }
        foreach ($Argument in @($Invoke.Arguments)) {
            $Node = Resolve-ShapePath -Node $Argument -Aliases $Aliases
            if ($Node) { [void]$Node.Usages.Add('datetime') }
        }
    }
}

function Add-ShapeUsageFromPipelines {
    <#
        Resolve `$_` inside a script block that is piped a property path.

        `Hybrid/VirtualMachines.ps1` writes
        `$data.networkProfile.networkInterfaces | ForEach-Object { $_.id.split('/')[-1] }`, and
        `Databases/SQLMIDB.ps1` writes the same idea through `Select-Object @{Expression={$_.id...}}`.
        Both say "networkInterfaces is a collection whose items have an id that is an ARM path", and
        neither says it in a form the plain member walk can see -- so without this the property came
        out a single opaque string, `$_.id` was $null, and the ORIGINAL collector threw on `.split()`.

        `$_` is bound in a COPY of the alias map, never the shared one: `$_` is also the parameter of
        every `$SUB | Where-Object { $_.id -eq ... }` in the estate, and a global binding would
        attribute the subscription's properties to the resource.
    #>
    param([System.Management.Automation.Language.Ast]$Ast, [hashtable]$Aliases)

    foreach ($Pipeline in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.PipelineAst] -and $n.PipelineElements.Count -gt 1 }, $true)) {
        $Source = Resolve-ShapePath -Node $Pipeline.PipelineElements[0] -Aliases $Aliases
        if (-not $Source) { continue }

        $Local = @{}
        foreach ($Key in $Aliases.Keys) { $Local[$Key] = $Aliases[$Key] }
        $Local['_'] = Get-ShapeElement -Node $Source
        $Local['PSItem'] = $Local['_']

        foreach ($Element in @($Pipeline.PipelineElements | Select-Object -Skip 1)) {
            foreach ($Block in $Element.FindAll({ param($n) $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true)) {
                foreach ($Node in $Block.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.MemberExpressionAst] -or
                        $n -is [System.Management.Automation.Language.IndexExpressionAst] -or
                        $n -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                        $n -is [System.Management.Automation.Language.ConvertExpressionAst]
                    }, $true)) {
                    $null = Resolve-ShapePath -Node $Node -Aliases $Local
                }
                Add-ShapeUsageFromOperators -Ast $Block -Aliases $Local
                Add-ShapeUsageFromCommands  -Ast $Block -Aliases $Local
            }
        }
    }
}

function Build-CollectorShape {
    <#
        Walk one definition's per-resource script and return the shape of the resource it reads.
        Repeated passes, not one: an alias assigned from another alias only resolves once its
        source has been registered, and AST enumeration order is not assignment order.
    #>
    param([PSCustomObject]$Definition)

    $ScriptText = Build-ScoutDeclarativeRowScript -Definition $Definition
    if ($Definition.AdditionalFilter) {
        # $_ in the filter is the resource, the same object the row variable names. The filter is
        # included so a property only the FILTER reads (Outages tests properties.description) still
        # appears in the fixture -- otherwise the collector matches nothing and passes vacuously.
        $FilterText = $Definition.AdditionalFilter -replace '\$_', ('$' + $Definition.RowLoopVariable)
        $ScriptText = "$ScriptText`n`$null = ($FilterText)"
    }

    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$null, [ref]$null)

    $Root    = New-ShapeNode -Name 'resource'
    $Aliases = @{ $Definition.RowLoopVariable = $Root }

    for ($Pass = 0; $Pass -lt 6; $Pass++) {
        foreach ($Assign in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            if ($Assign.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $Target = Resolve-ShapePath -Node $Assign.Right -Aliases $Aliases
            if ($Target) { $Aliases[$Assign.Left.VariablePath.UserPath] = $Target }
        }
        foreach ($Loop in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
            $Source = Resolve-ShapePath -Node $Loop.Condition -Aliases $Aliases
            if ($Source) {
                $Aliases[$Loop.Variable.VariablePath.UserPath] = Get-ShapeElement -Node $Source
            }
        }
        foreach ($Member in $Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.MemberExpressionAst] -or
                $n -is [System.Management.Automation.Language.IndexExpressionAst] -or
                $n -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                $n -is [System.Management.Automation.Language.ConvertExpressionAst]
            }, $true)) {
            $null = Resolve-ShapePath -Node $Member -Aliases $Aliases
        }
        Add-ShapeUsageFromOperators -Ast $Ast -Aliases $Aliases
        Add-ShapeUsageFromCommands  -Ast $Ast -Aliases $Aliases
        Add-ShapeUsageFromPipelines -Ast $Ast -Aliases $Aliases
    }

    return $Root
}

# --- Value synthesis --------------------------------------------------------------------------

# 16 segments, so any fixed positional index a collector uses on a split id or a split
# sub-resource path ($_.id.split('/')[10] is the deepest in the estate) resolves to a real value
# instead of $null.
$script:PathValue = (0..15 | ForEach-Object { "seg$_" }) -join '/'
$script:DateValue = '2026-01-15T10:30:00.0000000Z'

function ConvertTo-ShapeValue {
    param([PSCustomObject]$Node, [int]$Depth = 0)

    if ($Depth -gt 12) { return 'res-value' }

    if ($Node.IsArray -or $null -ne $Node.Element) {
        # An array node can accumulate children TWO ways, and both have to end up on the items:
        #   * through the loop/index variable  -- foreach ($2 in $data.subnets) { $2.properties... }
        #     lands on Element;
        #   * through MEMBER ENUMERATION       -- $data.workerProfiles.subnetId reads a property of
        #     every item but is written as a property of the array, so it lands on Children.
        # The first version returned a bare two-string collection whenever Element had no children,
        # which dropped every member-enumerated property: ARO's worker vNET, Outages' impacted
        # services and Hybrid/VirtualMachines' NICs all came back $null and the ORIGINAL collector
        # then threw on `.split()`.
        $ItemChildren = [ordered]@{}
        foreach ($Key in @($Node.Children.Keys)) { $ItemChildren[$Key] = $Node.Children[$Key] }
        if ($null -ne $Node.Element) {
            foreach ($Key in @($Node.Element.Children.Keys)) { $ItemChildren[$Key] = $Node.Element.Children[$Key] }
        }

        if ($ItemChildren.Count -gt 0) {
            $Items = @(1, 2 | ForEach-Object {
                $Item = [ordered]@{}
                foreach ($Key in @($ItemChildren.Keys)) {
                    $Item[$Key] = ConvertTo-ShapeValue -Node $ItemChildren[$Key] -Depth ($Depth + 1)
                }
                , $Item
            })
            return $Items
        }
        # A bare collection: two opaque members is enough for `.count`, `-join` and an index of 0/1.
        return @('res-item-0', 'res-item-1')
    }

    if ($Node.Children.Count -gt 0) {
        $Object = [ordered]@{}
        foreach ($Key in @($Node.Children.Keys)) {
            $Object[$Key] = ConvertTo-ShapeValue -Node $Node.Children[$Key] -Depth ($Depth + 1)
        }
        return $Object
    }

    if ($Node.Usages.Contains('datetime')) { return $script:DateValue }
    if ($Node.Usages.Contains('number'))   { return 1024 }
    if ($Node.Usages.Contains('path') -or $Node.Usages.Contains('method:split') -or
        $Node.Usages.Contains('method:substring') -or $Node.Usages.Contains('method:indexof')) {
        return $script:PathValue
    }
    if ($Node.Name -match '(?i)(date|time)$') { return $script:DateValue }
    return 'res-value'
}

# --- Fixture assembly -------------------------------------------------------------------------

$script:SubscriptionId = '00000000-0000-0000-0000-000000000001'

function New-FixtureResource {
    param(
        [PSCustomObject]$Shape,
        [PSCustomObject]$Definition,
        [string]$ResourceType,
        [string]$Id,
        [string]$Name,
        [hashtable]$Tags,
        [string]$SubscriptionId
    )

    $Body = ConvertTo-ShapeValue -Node $Shape
    if ($Body -isnot [System.Collections.IDictionary]) { $Body = [ordered]@{} }

    # The five fields ARG returns on every row, whatever the resource type. Set AFTER the derived
    # shape so a collector that reads $1.id gets a real ARM id rather than the generic
    # slash-delimited placeholder the shape walk would have produced for it.
    $Body['id']             = $Id
    $Body['NAME']           = $Name
    $Body['TYPE']           = $ResourceType
    $Body['subscriptionId'] = $SubscriptionId
    if (-not $Body.Contains('RESOURCEGROUP')) { $Body['RESOURCEGROUP'] = 'rg-fixture-01' }
    if (-not $Body.Contains('LOCATION'))      { $Body['LOCATION']      = 'eastus' }
    if (-not $Body.Contains('resourceGroup')) { $Body['resourceGroup'] = 'rg-fixture-01' }
    if (-not $Body.Contains('location'))      { $Body['location']      = 'eastus' }
    if (-not $Body.Contains('PROPERTIES'))    { $Body['PROPERTIES']    = [ordered]@{} }
    $Body['tags'] = $Tags

    if ($Definition.AdditionalFilter) { $Body = Resolve-FixtureFilter -Body $Body -Definition $Definition }

    return $Body
}

function Test-FixtureFilter {
    <# Does this candidate resource actually pass the collector's own compound filter? #>
    param($Body, [PSCustomObject]$Definition)

    $Text = if ([string]::IsNullOrWhiteSpace($Definition.FilterPreamble)) {
        $Definition.AdditionalFilter
    } else {
        "$($Definition.FilterPreamble)`n$($Definition.AdditionalFilter)"
    }
    # Round-tripped through JSON so `$_` is the same PSCustomObject shape the collector sees at run
    # time, not an ordered dictionary that would answer `.KIND` differently.
    $Candidate = ($Body | ConvertTo-Json -Depth 24) | ConvertFrom-Json
    try { return [bool](@($Candidate | Where-Object ([scriptblock]::Create($Text))).Count -gt 0) }
    catch { return $false }
}

function Resolve-FixtureFilter {
    <#
        Make the resource pass the collector's compound filter, by search rather than by parsing the
        filter into a rule engine.

        14 AI collectors and several others are distinguished from every sibling collector on the
        same resource type ONLY by that filter -- `$_.kind -eq 'FormRecognizer'`,
        `$_.Kind -like 'CustomVision.*'`, `$appliedAIKinds -contains $_.KIND`,
        `$_.properties.description -like '*How can customers make incidents...*'`. A fixture that
        ignores it produces zero rows, and zero rows is a PASSING equivalence test that proves
        nothing, so this is not cosmetic.

        Rather than implement -eq/-like/-in/-contains/-match semantics a second time (and get one of
        them subtly wrong), every string literal appearing in the filter or its preamble is tried as
        the value of every property the filter reads, and the real filter is asked. Whatever it
        accepts is right by construction.
    #>
    param($Body, [PSCustomObject]$Definition)

    if (Test-FixtureFilter -Body $Body -Definition $Definition) { return $Body }

    $Text = "$($Definition.FilterPreamble)`n$($Definition.AdditionalFilter)"
    $Paths    = @([regex]::Matches($Definition.AdditionalFilter, '\$_((?:\.\w+)+)') | ForEach-Object { $_.Groups[1].Value.TrimStart('.') } | Select-Object -Unique)
    $Literals = @([regex]::Matches($Text, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ } | Select-Object -Unique)

    foreach ($Path in $Paths) {
        foreach ($Literal in $Literals) {
            $Trial = [ordered]@{}
            foreach ($Key in $Body.Keys) { $Trial[$Key] = $Body[$Key] }
            Set-FixtureValue -Body $Trial -Path $Path -Value $Literal
            if (Test-FixtureFilter -Body $Trial -Definition $Definition) { return $Trial }
        }
    }

    Write-Warning "[New-ScoutCollectorFixture] Could not satisfy the AdditionalFilter of $($Definition.Path); this collector will match nothing and its equivalence test would pass vacuously."
    return $Body
}

function Set-FixtureValue {
    <# Assign a dotted path, creating intermediate objects. `$_.properties.description` is two deep. #>
    param($Body, [string]$Path, $Value)

    $Segments = @($Path -split '\.')
    $Cursor   = $Body
    for ($i = 0; $i -lt $Segments.Count - 1; $i++) {
        $Segment = $Segments[$i]
        if (-not $Cursor.Contains($Segment) -or $Cursor[$Segment] -isnot [System.Collections.IDictionary]) {
            $Cursor[$Segment] = [ordered]@{}
        }
        $Cursor = $Cursor[$Segment]
    }
    $Cursor[$Segments[-1]] = $Value
}

$DefinitionDir = Join-Path $RepoRoot 'manifests' 'collectors' $Category
if (-not (Test-Path -LiteralPath $DefinitionDir)) { throw "No definitions for category '$Category' at $DefinitionDir" }

$Subscriptions = @(
    [ordered]@{ id = $script:SubscriptionId; Name = 'sub-fixture-01' }
)

$Collectors   = [ordered]@{}
$Retirements  = [System.Collections.Generic.List[object]]::new()
$Unsupported  = [System.Collections.Generic.List[object]]::new()

# Two unsupported entries so the retirement fold has both a one-feature and a many-feature case.
$Unsupported.Add([ordered]@{ Id = 'svc-1'; RetiringFeature = 'Fixture Feature One'; RetirementDate = '2027-03-31' })
$Unsupported.Add([ordered]@{ Id = 'svc-2'; RetiringFeature = 'Fixture Feature Two'; RetirementDate = '2028-06-30' })

$Variants = @(
    @{ Suffix = 'a'; Tags = @{ env = 'prod' };                    Sub = $script:SubscriptionId; Retire = 0 }
    @{ Suffix = 'b'; Tags = @{ env = 'prod'; owner = 'platform' }; Sub = $script:SubscriptionId; Retire = 0 }
    @{ Suffix = 'c'; Tags = @{};                                   Sub = $script:SubscriptionId; Retire = 0 }
    @{ Suffix = 'd'; Tags = @{ env = 'dev' };                      Sub = '00000000-0000-0000-0000-0000000000ff'; Retire = 0 }
    @{ Suffix = 'e'; Tags = @{ env = 'prod' };                     Sub = $script:SubscriptionId; Retire = 1 }
    @{ Suffix = 'f'; Tags = @{ env = 'prod' };                     Sub = $script:SubscriptionId; Retire = 2 }
)

foreach ($File in (Get-ChildItem -LiteralPath $DefinitionDir -Filter '*.psd1' | Sort-Object Name)) {
    $Definition = Get-ScoutCollectorDefinition -Path $File.FullName
    $Shape      = Build-CollectorShape -Definition $Definition

    $Resources = [System.Collections.Generic.List[object]]::new()

    # Round-robin over declared types rather than grouped: for a multi-type collector this is what
    # makes the fixture able to FAIL a `ResourceTypes`-as-membership-test interpretation (§2.5).
    foreach ($Variant in $Variants) {
        $TypeIndex = 0
        foreach ($ResourceType in @($Definition.ResourceTypes)) {
            $TypeIndex++
            $Slug = "$($File.BaseName)-t$TypeIndex$($Variant.Suffix)".ToLowerInvariant()
            $Segments = @($ResourceType -split '/')
            $Provider = $Segments[0]
            $IdPath   = "/subscriptions/$($Variant.Sub)/resourceGroups/rg-fixture-01/providers/$Provider"
            for ($s = 1; $s -lt $Segments.Count; $s++) {
                $IdPath += "/$($Segments[$s])/$Slug-$s"
            }
            $Id = $IdPath

            $Resource = New-FixtureResource -Shape $Shape -Definition $Definition -ResourceType $ResourceType `
                -Id $Id -Name $Slug -Tags $Variant.Tags -SubscriptionId $Variant.Sub

            $Resources.Add($Resource)

            if ($Variant.Retire -ge 1) { $Retirements.Add([ordered]@{ id = $Id; ServiceID = 'svc-1' }) }
            if ($Variant.Retire -ge 2) { $Retirements.Add([ordered]@{ id = $Id; ServiceID = 'svc-2' }) }
        }
    }

    $Collectors[$File.BaseName] = [ordered]@{ resources = @($Resources) }
}

$Fixture = [ordered]@{
    description   = "Synthetic per-collector estate for the $Category declarative-collector equivalence proof (AB#5659). GENERATED by scripts/New-ScoutCollectorFixture.ps1 -- regenerate rather than hand-edit."
    subscriptions = @($Subscriptions)
    retirements   = @($Retirements)
    unsupported   = @($Unsupported)
    collectors    = $Collectors
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $RepoRoot 'tests' 'fixtures' 'collector-equivalence' "$Category.json"
}
$OutputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$Fixture | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "[New-ScoutCollectorFixture] Wrote $OutputPath ($($Collectors.Count) collectors)"
$OutputPath
