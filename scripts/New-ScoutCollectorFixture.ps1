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

function Get-CommandArgument {
    <# The value bound to one named parameter of a CommandAst, or the Nth positional argument. #>
    param(
        [System.Management.Automation.Language.CommandAst]$Command,
        [string]$ParameterName,
        [int]$Position
    )

    $Elements  = @($Command.CommandElements)
    $Positional = [System.Collections.Generic.List[object]]::new()

    for ($i = 1; $i -lt $Elements.Count; $i++) {
        $Element = $Elements[$i]
        if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($Element.ParameterName -ine $ParameterName) {
                # A switch takes no argument, so the token after it is positional, not its value.
                # Only -InputObject/-Path/-Id/-Index/-Name carry one here; -Enumerate does not.
                if ($Element.ParameterName -imatch '^(InputObject|Path|Id|Index|Name)$' -and
                    $null -eq $Element.Argument -and $i + 1 -lt $Elements.Count) { $i++ }
                continue
            }
            if ($null -ne $Element.Argument) { return $Element.Argument }
            if ($i + 1 -lt $Elements.Count) { return $Elements[$i + 1] }
            return $null
        }
        [void]$Positional.Add($Element)
    }

    if ($PSBoundParameters.ContainsKey('Position') -and $Position -lt $Positional.Count) {
        return $Positional[$Position]
    }
    return $null
}

$script:ShapeAccessorCommands = @('get-azscsafeproperty', 'get-azscidsegment', 'get-azticollectedvalue')

function Test-ShapeAccessorCommand {
    <# True when this pipeline element is one of the StrictMode-safe property accessors. #>
    param([System.Management.Automation.Language.Ast]$Node)
    if ($Node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
    $Name = $Node.GetCommandName()
    if (-not $Name) { return $false }
    return $script:ShapeAccessorCommands -contains $Name.ToLowerInvariant()
}

function Resolve-ShapeAccessorPath {
    <#
        The StrictMode-safe accessors (AB#5671) hide a property path from the member walk: after
        the conversion, `$data.networkacls.defaultaction` reads

            Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.defaultaction' -Enumerate

        and every node in that path is a STRING, not a MemberExpressionAst. Without this the walk
        learns nothing from those expressions, the fixture leaves the properties absent, and the
        equivalence proof goes vacuous in the worst possible way: BOTH paths read an absent
        property, BOTH get $null, and the rows match while proving nothing about the field.

        Returns @{ Handled; Node } rather than just a node, so the caller can tell "this was an
        accessor whose subject did not resolve" from "this was not an accessor at all".
    #>
    param(
        [System.Management.Automation.Language.Ast]$Command,
        [System.Management.Automation.Language.Ast]$Subject,
        [hashtable]$Aliases
    )

    $Miss = @{ Handled = $false; Node = $null }

    if ($Command -is [System.Management.Automation.Language.CommandExpressionAst]) { return $Miss }
    if ($Command -isnot [System.Management.Automation.Language.CommandAst]) { return $Miss }

    $Name = $Command.GetCommandName()
    if (-not $Name) { return $Miss }

    switch ($Name.ToLowerInvariant()) {
        'get-azscsafeproperty' {
            $Target = if ($Subject) { $Subject } else { Get-CommandArgument -Command $Command -ParameterName 'InputObject' -Position 0 }
            $PathArg = Get-CommandArgument -Command $Command -ParameterName 'Path' -Position $(if ($Subject) { 0 } else { 1 })
            if ($PathArg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return @{ Handled = $true; Node = $null } }

            $Node = Resolve-ShapePath -Node $Target -Aliases $Aliases
            if (-not $Node) { return @{ Handled = $true; Node = $null } }

            foreach ($Segment in ($PathArg.Value -split '\.')) {
                if ([string]::IsNullOrWhiteSpace($Segment)) { continue }
                if ($script:ReflectionMembers -contains $Segment.ToLowerInvariant()) { return @{ Handled = $true; Node = $null } }
                if ($script:CollectionMembers -contains $Segment.ToLowerInvariant()) {
                    [void]$Node.Usages.Add('array'); $Node.IsArray = $true
                    return @{ Handled = $true; Node = $null }
                }
                $Node = Get-ShapeChild -Node $Node -Name $Segment
            }

            # -Enumerate is deliberately ignored. It governs how INTERMEDIATE segments behave when
            # one of them is a collection, and the converter emits it on nearly every call whether
            # the chain crosses an array or not -- so it says nothing about the shape of the leaf.
            # Array-ness is still learned the same way it always was, from `@(...)`, `.count`, and
            # foreach over the path.
            return @{ Handled = $true; Node = $Node }
        }
        'get-azscidsegment' {
            # Replaces `$x.split('/')[8]`, so the subject must be an ARM path, not an opaque string.
            $Target = if ($Subject) { $Subject } else { Get-CommandArgument -Command $Command -ParameterName 'Id' -Position 0 }
            $Node = Resolve-ShapePath -Node $Target -Aliases $Aliases
            if ($Node) { [void]$Node.Usages.Add('method:split') }
            return @{ Handled = $true; Node = $null }
        }
        'get-azticollectedvalue' {
            $Target = Get-CommandArgument -Command $Command -ParameterName 'InputObject' -Position 0
            $NameArg = Get-CommandArgument -Command $Command -ParameterName 'Name' -Position 1
            if ($NameArg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return @{ Handled = $true; Node = $null } }
            $Node = Resolve-ShapePath -Node $Target -Aliases $Aliases
            if (-not $Node) { return @{ Handled = $true; Node = $null } }
            return @{ Handled = $true; Node = (Get-ShapeChild -Node $Node -Name $NameArg.Value) }
        }
    }

    return $Miss
}

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
    if ($Node -is [System.Management.Automation.Language.PipelineAst] -and $Node.PipelineElements.Count -eq 2) {
        # `$data | Get-AZSCSafeProperty -Path 'x'` -- the accessor's subject arrives by pipeline
        # rather than by -InputObject, so the two-element pipeline IS the property path. Handled
        # here and not in Add-ShapeUsageFromPipelines, which binds $_ and would learn nothing:
        # the accessor names its property in a string, not as a member of $_.
        $Accessor = Resolve-ShapeAccessorPath -Command $Node.PipelineElements[1] `
            -Subject $Node.PipelineElements[0] -Aliases $Aliases
        if ($Accessor.Handled) { return $Accessor.Node }
    }
    if ($Node -is [System.Management.Automation.Language.PipelineAst] -and $Node.PipelineElements.Count -gt 1) {
        # A pipeline of SHAPE-PRESERVING stages resolves to the shape of its source. `Where-Object`
        # and `Sort-Object` select and reorder items; they do not change what an item looks like.
        #
        # This is what makes a join's PARTNER get a shape at all. Every one of these collectors
        # writes `$Matches = $Partners | Where-Object { ... }` and then reads `$Match.properties.x`
        # off the result; without the pass-through the result aliased to nothing, the partner was
        # synthesised with only the properties its own predicate mentions, and every joined column
        # read $null -- on BOTH paths, so the equivalence test passed and proved nothing about the
        # join. Deliberately NOT extended to `Select-Object`, which with a property list or a
        # calculated property produces a different shape.
        $ShapePreserving = @('where-object', 'sort-object')
        $Tail = @($Node.PipelineElements | Select-Object -Skip 1)
        $AllPreserving = $true
        foreach ($Stage in $Tail) {
            if ($Stage -isnot [System.Management.Automation.Language.CommandAst]) { $AllPreserving = $false; break }
            $StageName = $Stage.GetCommandName()
            if (-not $StageName -or $ShapePreserving -notcontains $StageName.ToLowerInvariant()) { $AllPreserving = $false; break }
        }
        if ($AllPreserving) {
            $Source = Resolve-ShapePath -Node $Node.PipelineElements[0] -Aliases $Aliases
            if ($Source) { return $Source }
        }
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
        # The expression is also commonly the SOURCE of a following pipeline, for example
        # `@($data.profiles) | ForEach-Object { $_.name }`.  Returning $null here made the
        # pipeline walker lose the element shape, so fixtures emitted string profiles and the
        # strict declarative collector correctly threw on their missing `name`.  Preserve the
        # marked node so downstream pipeline analysis can bind `$_` to its element.
        return $Inner
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

    if ($Node -is [System.Management.Automation.Language.CommandAst]) {
        $Accessor = Resolve-ShapeAccessorPath -Command $Node -Subject $null -Aliases $Aliases
        if ($Accessor.Handled) { return $Accessor.Node }
        return $null
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
        # `$data | Get-AZSCSafeProperty -Path 'x'` is a pipeline whose downstream stage reads ONE
        # property off the subject WHOLE -- it is the accessor spelling of `$data.x`, not an
        # enumeration of it. Binding $_ here would call Get-ShapeElement on the subject and declare
        # $data an array, which turned VMDisk's entire PROPERTIES object into a list of objects.
        if (Test-ShapeAccessorCommand -Node $Pipeline.PipelineElements[-1]) { continue }

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
                        $n -is [System.Management.Automation.Language.ConvertExpressionAst] -or
                        $n -is [System.Management.Automation.Language.CommandAst]
                    }, $true)) {
                    $null = Resolve-ShapePath -Node $Node -Aliases $Local
                }
                Add-ShapeUsageFromOperators -Ast $Block -Aliases $Local
                Add-ShapeUsageFromCommands  -Ast $Block -Aliases $Local
            }
        }
    }
}

function Get-DefinitionSecondarySets {
    <#
        The resource sets a definition's SetupPreamble derives from `$Resources` for a type OTHER
        than the one it iterates -- the join half of the 13 collectors converted under AB#5659.

        Without a fixture entry for those types the join matches nothing, every joined column falls
        to its not-found sentinel ('none', $false, $null) on BOTH paths, and the equivalence test
        passes while proving nothing about the half of the collector that the conversion actually
        had to extend the schema for. That is precisely the vacuous pass this generator exists to
        prevent, so the secondary types are read back out of the setup source here.
    #>
    param([PSCustomObject]$Definition)

    $Sets  = [System.Collections.Generic.List[object]]::new()
    $Seen  = [System.Collections.Generic.HashSet[string]]::new()

    # BOTH places a join can live. The 13 collectors converted with a SetupPreamble hoist theirs
    # above the row loop; Networking/NetworkWatchers derives its three (flowLogs, connMonitors,
    # packetCaptures) INSIDE the row loop, so they are in the row Preamble instead and the setup
    # section is empty. Scanning only the setup left all three of its sub-resource columns reading
    # their empty-collection value on every fixture row.
    $Sources = @($Definition.SetupPreamble, (Build-ScoutDeclarativeRowScript -Definition $Definition))

    foreach ($Source in $Sources) {
        if ([string]::IsNullOrWhiteSpace($Source)) { continue }
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$null, [ref]$null)

        foreach ($Assign in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            if ($Assign.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $Text = $Assign.Right.Extent.Text
            if ($Text -notmatch '(?i)\$Resources') { continue }

            # Quoted EITHER way. Web/APPServicePlan writes its join type in double quotes
            # ("microsoft.insights/autoscalesettings") where every other collector uses single;
            # a single-quote-only pattern silently gave it no join partner, so 'Autoscale Enabled'
            # read $false on all six variants and the column was never actually tested.
            $Types = @([regex]::Matches($Text, "['""]([a-zA-Z0-9.]+/[a-zA-Z0-9./]+)['""]") |
                ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            # The collector's OWN types are excluded: the primary filter is carried in the setup
            # range verbatim (it is contiguous source), and re-emitting resources for it would
            # double the row count of every sheet.
            $Types = @($Types | Where-Object { $Type = $_; -not (@($Definition.ResourceTypes) | Where-Object { $_ -ieq $Type }) })
            if (@($Types).Count -eq 0) { continue }

            $Variable = $Assign.Left.VariablePath.UserPath
            if (-not $Seen.Add($Variable)) { continue }
            $Sets.Add([PSCustomObject]@{ Variable = $Variable; ResourceTypes = $Types })
        }
    }
    return @($Sets)
}

function Get-JoinCorrelationPaths {
    <#
        The property of a secondary resource that has to carry the PRIMARY resource's id for the
        collector's own join predicate to match, e.g. Web/APPServicePlan's

            $AutoScale = ($APPAutoScale | Where-Object { $_.Properties.targetResourceUri -eq $1.id })

        A generated resource whose targetResourceUri is the generic placeholder never matches, so
        'Autoscale Enabled' would read $false on all six variants of every fixture ever generated.

        `$_.id` itself is excluded: the id is already synthesised as a CHILD path of the primary id,
        which satisfies both the `-eq` and the `-like ($1.id + '*')` spellings while still looking
        like a real ARM sub-resource id to the `.split('/')` reads further down.
    #>
    param([string]$ScriptText, [string]$RowLoopVariable, [string]$SetVariable)

    $Pairs = [System.Collections.Generic.List[object]]::new()
    $Seen  = [System.Collections.Generic.HashSet[string]]::new()

    # ONLY the `Where-Object` bodies fed by THIS secondary set. Scanning the whole row script also
    # matched `$SUB | Where-Object { $_.id -eq $1.subscriptionId }` and the identical retirement
    # fold, and the resulting 'id => subscriptionId' pair overwrote the partner's carefully built
    # child-of-primary id with a subscription GUID -- which broke the joins that WERE working
    # rather than fixing the ones that were not.
    $Anchor = [regex]::Escape('$' + $SetVariable)
    foreach ($Start in [regex]::Matches($ScriptText, $Anchor + '\s*\|\s*Where-Object\s*\{')) {
        # Balanced-brace scan: a join predicate can itself contain a `{ }` (a Select-Object
        # calculated property), so the first `}` is not reliably the end of the block.
        $Open  = $ScriptText.IndexOf('{', $Start.Index + $Start.Length - 1)
        if ($Open -lt 0) { continue }
        $Depth = 0
        $End   = -1
        for ($i = $Open; $i -lt $ScriptText.Length; $i++) {
            if ($ScriptText[$i] -eq '{') { $Depth++ }
            elseif ($ScriptText[$i] -eq '}') { $Depth--; if ($Depth -eq 0) { $End = $i; break } }
        }
        if ($End -lt 0) { continue }
        $Body = $ScriptText.Substring($Open + 1, $End - $Open - 1)

        $Row = [regex]::Escape('$' + $RowLoopVariable)
        # The row-variable member is captured too, not assumed to be `id`: Containers/AKS correlates
        # on `$_.Location -eq $1.location` and `$_.SubId -eq $1.subscriptionId`.
        foreach ($Spelling in @(
                @{ Pattern = '\$_\.((?:\w+\.)*\w+)\s*-\w+\s+' + $Row + '\.(\w+)\b'; PartnerGroup = 1; RowGroup = 2 }
                @{ Pattern = $Row + '\.(\w+)\s*-\w+\s+\$_\.((?:\w+\.)*\w+)';        PartnerGroup = 2; RowGroup = 1 })) {
            foreach ($Match in [regex]::Matches($Body, $Spelling.Pattern)) {
                $PartnerPath = $Match.Groups[$Spelling.PartnerGroup].Value
                $RowMember   = $Match.Groups[$Spelling.RowGroup].Value
                # The partner id is already synthesised as a CHILD of the primary id, which satisfies
                # both `-eq` and `-like ($1.id + '*')`; rewriting it to the bare primary id would
                # break the `.split('/')` reads further down.
                if ($PartnerPath -ieq 'id' -and $RowMember -ieq 'id') { continue }
                if (-not $Seen.Add("$PartnerPath=>$RowMember")) { continue }
                $Pairs.Add([PSCustomObject]@{ PartnerPath = $PartnerPath; RowMember = $RowMember })
            }
        }
    }
    return @($Pairs)
}

function Build-CollectorShape {
    <#
        Walk one definition's per-resource script and return the shape of the resource it reads.
        Repeated passes, not one: an alias assigned from another alias only resolves once its
        source has been registered, and AST enumeration order is not assignment order.
    #>
    param([PSCustomObject]$Definition, [object[]]$SecondarySets = @())

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

    # A setup variable is seeded as its own ROOT, marked a collection, so that the existing
    # pipeline machinery binds `$_` inside `$VNETLinks | Where-Object { ... }` to its element and
    # accumulates the joined resource's shape there instead of discarding it as an unknown name.
    $SecondaryRoots = [ordered]@{}
    foreach ($Set in @($SecondarySets)) {
        $Node = New-ShapeNode -Name $Set.Variable
        $null = Get-ShapeElement -Node $Node
        $SecondaryRoots[$Set.Variable] = $Node
        $Aliases[$Set.Variable] = $Node
    }

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
                $n -is [System.Management.Automation.Language.ConvertExpressionAst] -or
                $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)) {
            $null = Resolve-ShapePath -Node $Member -Aliases $Aliases
        }
        Add-ShapeUsageFromOperators -Ast $Ast -Aliases $Aliases
        Add-ShapeUsageFromCommands  -Ast $Ast -Aliases $Aliases
        Add-ShapeUsageFromPipelines -Ast $Ast -Aliases $Aliases
    }

    return [PSCustomObject]@{ Root = $Root; Secondary = $SecondaryRoots }
}

# --- Value synthesis --------------------------------------------------------------------------

# Legacy preambles retain fixed split indexes from several ARM resource shapes.  Give every
# synthetic path ample segments so a coverage fixture reaches the row contract first.
$script:PathValue = (0..32 | ForEach-Object { "seg$_" }) -join '/'
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
    # Property names such as timeCreated carry their temporal cue as a prefix rather than a
    # suffix.  They are frequently cast with [datetime] in lifted preambles, so synthetic text
    # makes both the reference capture and declarative proof fail before producing a row.
    if ($Node.Name -match '(?i)(date|time|created)$') { return $script:DateValue }
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
        [System.Collections.IDictionary]$Tags,
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

    # Additional row loops may filter their source (`Where { $_.aggregationLevel -eq
    # 'Monthly' }`).  Populate that predicate's member wherever it occurs in the generated
    # shape so the loop has at least one reachable item.  This is data derived from the
    # manifest expression, not a collector-name exception.
    foreach ($Loop in @($Definition.AdditionalRowLoops)) {
        $LoopFilterText = "$($Definition.Preamble)`n$($Loop.Preamble)`n$($Loop.Source)"
        if ($LoopFilterText -match '\$_\.([A-Za-z0-9_]+)\s*-eq\s*''([^'']+)''') {
            $Member = $Matches[1]; $Value = $Matches[2]
            $Stack = [System.Collections.Generic.Stack[object]]::new()
            $Stack.Push($Body)
            while ($Stack.Count -gt 0) {
                $Current = $Stack.Pop()
                if ($Current -is [System.Collections.IDictionary]) {
                    foreach ($Key in @($Current.Keys)) {
                        if ($Key -ieq $Member) { $Current[$Key] = $Value }
                        $Stack.Push($Current[$Key])
                    }
                } elseif ($Current -is [System.Collections.IEnumerable] -and $Current -isnot [string]) {
                    foreach ($Item in $Current) { $Stack.Push($Item) }
                }
            }
        }
    }

    # RowSource collectors project nested prefetch envelopes instead of iterating a resource
    # directly (for example SecurityPolicySweep.PROPERTIES.PolicyComplianceStates).  Populate a
    # representative projected object from the manifest field expressions so the same fixture
    # reaches both the legacy reference and declarative row source.
    $RowSourceExpression = if ($Definition.PSObject.Properties.Name -contains 'RowSource' -and
        $null -ne $Definition.RowSource -and
        $Definition.RowSource.PSObject.Properties.Name -contains 'Expression') {
        [string]$Definition.RowSource.Expression
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($RowSourceExpression) -and
        $RowSourceExpression -match '(?i)PROPERTIES\.([A-Za-z0-9_]+)') {
        $CollectionName = $Matches[1]
        $PropertiesKey = Resolve-FixtureKey -Body $Body -Name 'PROPERTIES'
        if ($Body[$PropertiesKey] -isnot [System.Collections.IDictionary]) { $Body[$PropertiesKey] = [ordered]@{} }
        $State = [ordered]@{}
        foreach ($Field in @($Definition.Fields)) {
            foreach ($Match in @([regex]::Matches([string]$Field.Expression, '\$[A-Za-z][A-Za-z0-9_]*\.([A-Za-z0-9_]+)'))) {
                $Member = $Match.Groups[1].Value
                if (-not $State.Contains($Member)) { $State[$Member] = if ($Member -match '(?i)(date|time|created|stamp)$') { $script:DateValue } else { 'res-value' } }
            }
        }
        # A subscription-scoped RowSource commonly filters projected objects by an Id containing
        # the sweep subscription. Preserve that contract in the fixture so the projection reaches
        # its rows instead of being filtered out before field evaluation.
        if ($RowSourceExpression -match '(?i)/subscriptions/\$\(\$sweep\.subscriptionId\)/') {
            $State['Id'] = "/subscriptions/$SubscriptionId/resourceGroups/rg-fixture-01/providers/Microsoft.Security/assessments/fixture-assessment"
        }
        if ($State.Count -eq 0) { $State['Name'] = 'res-value' }
        $Body[$PropertiesKey][$CollectionName] = @($State)
    }

    # RowCondition is evaluated by the declarative interpreter after resource selection.  It is
    # distinct from AdditionalFilter, so the latter's fixture resolver cannot make a resource
    # such as AdvisorScore (which gates on `$1.name`) reach its row loop.  Use the first quoted
    # condition literal as the deterministic primary name; the full collector still validates
    # that its remaining condition semantics are satisfied.
    if (-not [string]::IsNullOrWhiteSpace($Definition.RowCondition) -and
        $Definition.RowCondition -match "'([^']+)'") {
        $Body[(Resolve-FixtureKey -Body $Body -Name 'NAME')] = $Matches[1]
    }

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

function Resolve-FixtureKey {
    <#
        The existing key that matches $Name case-insensitively, or $Name itself.

        ARM payloads and this generator disagree on case -- a resource carries 'PROPERTIES' but a
        join predicate is written `$_.Properties.targetResourceUri`. Adding a second key that
        differs only in case produces JSON that ConvertFrom-Json rejects as a duplicate property,
        so the write has to land on the key that is already there.
    #>
    param($Body, [string]$Name)
    foreach ($Key in @($Body.Keys)) { if ($Key -ieq $Name) { return $Key } }
    return $Name
}

function Set-FixtureValue {
    <# Assign a dotted path, creating intermediate objects. `$_.properties.description` is two deep. #>
    param($Body, [string]$Path, $Value)

    $Segments = @($Path -split '\.')
    $Cursor   = $Body
    for ($i = 0; $i -lt $Segments.Count - 1; $i++) {
        $Segment = Resolve-FixtureKey -Body $Cursor -Name $Segments[$i]
        if (-not $Cursor.Contains($Segment) -or $Cursor[$Segment] -isnot [System.Collections.IDictionary]) {
            $Cursor[$Segment] = [ordered]@{}
        }
        $Cursor = $Cursor[$Segment]
    }
    $Cursor[(Resolve-FixtureKey -Body $Cursor -Name $Segments[-1])] = $Value
}

function New-FixtureJoinedResource {
    <#
        One resource of a SECONDARY type, built to be found by the collector's own join predicate
        for exactly one primary resource.

        Its id is a CHILD path of the primary's, which is what both spellings in the estate need --
        `-like ($1.id + '*')` (Networking/PrivateDNS) and `-like "$($1.id)/*"`
        (Networking/NetworkWatchers) -- while still being a real ARM id with enough segments for the
        fixed `.split('/')[8]` indexes downstream to resolve.
    #>
    param(
        [PSCustomObject]$ShapeNode,
        [string]$ResourceType,
        [string]$PrimaryId,
        [string]$Slug,
        [string]$SubscriptionId,
        [object[]]$Correlations,
        $PrimaryBody
    )

    # The shape accumulated on the ELEMENT of the setup variable is the shape of one joined
    # resource; the node itself is the collection.
    $ItemNode = if ($null -ne $ShapeNode.Element) { $ShapeNode.Element } else { $ShapeNode }
    $Body = ConvertTo-ShapeValue -Node $ItemNode
    if ($Body -isnot [System.Collections.IDictionary]) { $Body = [ordered]@{} }

    $Leaf = @($ResourceType -split '/')[-1]
    $Body[(Resolve-FixtureKey -Body $Body -Name 'id')]             = "$PrimaryId/$Leaf/$Slug"
    $Body[(Resolve-FixtureKey -Body $Body -Name 'NAME')]           = $Slug
    $Body[(Resolve-FixtureKey -Body $Body -Name 'TYPE')]           = $ResourceType
    $Body[(Resolve-FixtureKey -Body $Body -Name 'subscriptionId')] = $SubscriptionId
    if (-not $Body.Contains((Resolve-FixtureKey -Body $Body -Name 'RESOURCEGROUP'))) { $Body['RESOURCEGROUP'] = 'rg-fixture-01' }
    if (-not $Body.Contains((Resolve-FixtureKey -Body $Body -Name 'LOCATION')))      { $Body['LOCATION']      = 'eastus' }
    if (-not $Body.Contains((Resolve-FixtureKey -Body $Body -Name 'PROPERTIES')))    { $Body['PROPERTIES']    = [ordered]@{} }
    $Body[(Resolve-FixtureKey -Body $Body -Name 'tags')] = [ordered]@{}

    foreach ($Pair in @($Correlations)) {
        # The value comes from the PRIMARY resource that this partner is being built for, so the
        # collector's own predicate is satisfied by construction rather than by luck.
        $Key = Resolve-FixtureKey -Body $PrimaryBody -Name $Pair.RowMember
        if (-not $PrimaryBody.Contains($Key)) { continue }
        Set-FixtureValue -Body $Body -Path $Pair.PartnerPath -Value $PrimaryBody[$Key]
    }

    return $Body
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

# [ordered], not @{}: a plain hashtable's enumeration order is not stable BETWEEN PROCESSES, so the
# two-tag variant serialised its tags in a different order on most regenerations. Every category
# fixture then showed a spurious diff, and -- worse -- the ORDER of the two tag rows a two-tag
# resource expands into was not reproducible, which is the one thing a "the fixtures are current"
# CI check cannot tolerate. Both paths read the same file, so this was never an equivalence
# failure; it was an undetectable one.
$Variants = @(
    @{ Suffix = 'a'; Tags = [ordered]@{ env = 'prod' };                    Sub = $script:SubscriptionId; Retire = 0 }
    @{ Suffix = 'b'; Tags = [ordered]@{ env = 'prod'; owner = 'platform' }; Sub = $script:SubscriptionId; Retire = 0 }
    @{ Suffix = 'c'; Tags = [ordered]@{};                                   Sub = $script:SubscriptionId; Retire = 0 }
    @{ Suffix = 'd'; Tags = [ordered]@{ env = 'dev' };                      Sub = '00000000-0000-0000-0000-0000000000ff'; Retire = 0 }
    @{ Suffix = 'e'; Tags = [ordered]@{ env = 'prod' };                     Sub = $script:SubscriptionId; Retire = 1 }
    @{ Suffix = 'f'; Tags = [ordered]@{ env = 'prod' };                     Sub = $script:SubscriptionId; Retire = 2 }
)

foreach ($File in (Get-ChildItem -LiteralPath $DefinitionDir -Filter '*.psd1' | Sort-Object Name)) {
    $Definition     = Get-ScoutCollectorDefinition -Path $File.FullName
    $SecondarySets  = @(Get-DefinitionSecondarySets -Definition $Definition)
    $ShapeResult    = Build-CollectorShape -Definition $Definition -SecondarySets $SecondarySets
    $Shape          = $ShapeResult.Root
    $RowScriptText  = Build-ScoutDeclarativeRowScript -Definition $Definition
    $Correlations   = @{}
    foreach ($Set in $SecondarySets) {
        $Correlations[$Set.Variable] = @(Get-JoinCorrelationPaths -ScriptText $RowScriptText `
            -RowLoopVariable $Definition.RowLoopVariable -SetVariable $Set.Variable)
    }

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

            # Some legacy preambles assign an ARM child collection to a local and an
            # AdditionalRowLoop then indexes a slash-delimited member (`$pv.split('/')[8]`).
            # Populate that property as an array of a valid path so the fixture reaches the
            # loop body instead of failing on a scalar placeholder.
            foreach ($Loop in @($Definition.AdditionalRowLoops)) {
                $LoopVariable = [regex]::Escape([string]$Loop.Variable)
                if ($Loop.Preamble -notmatch ('\$' + $LoopVariable + '\.split\(')) { continue }
                $SourceVariableMatch = [regex]::Match([string]$Loop.Source, '^\$(\w+)$')
                if (-not $SourceVariableMatch.Success) { continue }
                $SourceVariable = [regex]::Escape($SourceVariableMatch.Groups[1].Value)
                $PropertyMatch = [regex]::Match([string]$Definition.Preamble, '\$' + $SourceVariable + '\s*=.*?\$data\.([A-Za-z0-9_]+)')
                if (-not $PropertyMatch.Success) { continue }
                $PropertiesKey = Resolve-FixtureKey -Body $Resource -Name 'PROPERTIES'
                if ($Resource[$PropertiesKey] -isnot [System.Collections.IDictionary]) { $Resource[$PropertiesKey] = [ordered]@{} }
                $Resource[$PropertiesKey][$PropertyMatch.Groups[1].Value] = @($script:PathValue)
            }

            # ARM child collectors frequently recover their workspace/parent from the same raw
            # inventory set (`$Resources | Where-Object { $_.id -eq $1.PARENTID }`).  A literal
            # PARENTID fixture value only exercised the legacy non-StrictMode null path; it could
            # never prove the declared parent columns.  Materialise the parent and wire its ID
            # before adding the child.  The parent type is deliberately outside this definition's
            # ResourceTypes, so it is available to the join but cannot become an output row.
            if ([regex]::IsMatch("$($Definition.Preamble)`n$($Definition.SetupPreamble)", '\$Resources\s*\|\s*Where-Object\s*\{\s*\$_\.id\s*-eq\s*\$1\.PARENTID')) {
                $ParentId = "/subscriptions/$($Variant.Sub)/resourceGroups/rg-fixture-01/providers/AZSC/FixtureParents/$Slug-parent"
                $ParentKey = Resolve-FixtureKey -Body $Resource -Name 'PARENTID'
                $Resource[$ParentKey] = $ParentId
                $Resources.Add([ordered]@{
                    id = $ParentId
                    NAME = "$Slug-parent"
                    RESOURCEGROUP = 'rg-fixture-01'
                    LOCATION = 'eastus'
                    TYPE = 'AZSC/FixtureParents'
                })
            }

            # The shape walk can encounter a `TYPE` literal in a preamble join (for example an
            # operational-envelope lookup) and leave that derived value on the primary object.
            # ResourceTypes is the authoritative identity of the primary row: restore it here,
            # immediately before it enters the fixture estate, so a collector's own selection is
            # always exercised and an operational partner remains a separate joined resource.
            $Resource[(Resolve-FixtureKey -Body $Resource -Name 'TYPE')] = $ResourceType
            $Resources.Add($Resource)

            # One joined resource per secondary type PER PRIMARY, not one per collector: the join
            # predicate correlates on the primary's own id, so a single shared partner would match
            # exactly one of the six variants and leave the other five reading the not-found
            # sentinel. Variant 'c' is deliberately left WITHOUT a partner so the unmatched branch
            # ('none', $false, $null) stays covered too -- that branch is what every one of these
            # collectors did on every fixture before this existed, and it must not silently stop
            # being tested.
            if ($Variant.Suffix -ne 'c') {
                foreach ($Set in $SecondarySets) {
                    $SecondaryShape = $ShapeResult.Secondary[$Set.Variable]
                    $JoinIndex = 0
                    foreach ($JoinType in @($Set.ResourceTypes)) {
                        $JoinIndex++
                        $Joined = New-FixtureJoinedResource -ShapeNode $SecondaryShape -ResourceType $JoinType `
                            -PrimaryId $Id -Slug "$Slug-join$JoinIndex" -SubscriptionId $Variant.Sub `
                            -Correlations $Correlations[$Set.Variable] -PrimaryBody $Resource
                        $Resources.Add($Joined)

                        # Reverse references are stored on the primary (for example a virtual
                        # WAN has properties.virtualHubs[].id) rather than in a Where-Object
                        # predicate over the joined set.  Wire those declared primary paths to
                        # the joined ID so the topology is reachable in the fixture.
                        $JoinLeaf = (@($JoinType -split '/')[-1] -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
                        foreach ($Match in @([regex]::Matches("$($Definition.Preamble)`n$($Definition.SetupPreamble)", '(?i)\$data\.([A-Za-z0-9_]+)\.id'))) {
                            $Collection = $Match.Groups[1].Value
                            if ((($Collection -replace '[^A-Za-z0-9]', '').ToLowerInvariant()) -ne $JoinLeaf) { continue }
                            $PropertiesKey = Resolve-FixtureKey -Body $Resource -Name 'PROPERTIES'
                            if ($Resource[$PropertiesKey] -isnot [System.Collections.IDictionary]) { $Resource[$PropertiesKey] = [ordered]@{} }
                            $Resource[$PropertiesKey][$Collection] = @([ordered]@{ id = $Joined.id })
                        }
                    }
                }
            }

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
