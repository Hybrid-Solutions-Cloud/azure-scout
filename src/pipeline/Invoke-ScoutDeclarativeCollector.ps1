#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Run one declarative collector definition for the Processing or Reporting task (AB#5657/AB#5659).

.DESCRIPTION
    The one interpreter every converted `.psd1` collector definition shares. It contains no
    collector-specific knowledge: it does not know what a "retirement lookup" or a "tag" is, it
    just filters `$Resources`, runs the definition's own `Preamble` once per matched resource
    (verbatim source lifted from the original collector -- see
    `docs/design/decisions/declarative-collectors.md`), evaluates each `Fields` entry's
    expression in the scope that preamble just populated, and exports the result the same way
    `Invoke-ScoutCollector` would for a hand-written `.ps1`.

    PROCESSING builds one script per matched resource:

        <Preamble, verbatim>
        foreach ($<AdditionalRowLoop.Variable> in <AdditionalRowLoop.Source>) {   # 0 or more, nested
            <AdditionalRowLoop.Preamble, verbatim>
            foreach ($<TagLoop.Variable> in <TagLoop.Source>) {                   # omitted when TagLoop is $null
                @{ '<Field.Name>' = <Field.Expression>; ... }
                if ($ResUCount -eq 1) { $ResUCount = 0 }
            }
        }

    run with `RowLoopVariable`, `SUB`, `Retirements` and `Unsupported` pre-bound via
    `ScriptBlock.InvokeWithContext` -- the same technique that keeps the audit's AST extraction
    (AB#5658) safe, applied here to execution instead of parsing. One execution per RESOURCE, not
    per row, matches the original collectors' own granularity; running Preamble once per emitted
    row instead would still be correct (it is a pure function of the resource) but wastefully
    re-derives the same locals for every tag.

    REPORTING rebuilds the `$Exc` column list, conditional-formatting rules and Excel style from
    the definition's `Export` section and calls `Export-Excel` exactly as the original collector's
    Reporting branch did.

.PARAMETER Definition
    A definition object from `Get-ScoutCollectorDefinition`.

.PARAMETER Context
    The same context hashtable `Invoke-ScoutCollector` accepts: Resources, Subscriptions, InTag,
    Retirements, Unsupported, Task, File, SmaResources, TableStyle.

.OUTPUTS
    Processing: an array of row hashtables. Reporting: nothing (writes to Context.File).

.NOTES
    Tracks ADO AB#5657/AB#5659/AB#5656 (Feature AB#5656, Epic AB#5638).

    This is the live collector path. `Invoke-ScoutCollector` routes every catalog entry here,
    so a defect in this interpreter is a defect in a customer's report. Golden row and workbook
    contracts preserve the behavior independently of the retired source scripts.
#>
function Invoke-ScoutDeclarativeCollector {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [PSCustomObject]$Definition,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Context
    )

    if ($Context['Task'] -eq 'Processing') {
        return Invoke-ScoutDeclarativeProcessing -Definition $Definition -Context $Context
    }
    return Invoke-ScoutDeclarativeReporting -Definition $Definition -Context $Context
}

function Build-ScoutDeclarativeRowScript {
    <# Compose the per-resource script text described in the function help above. #>
    param([PSCustomObject]$Definition)

    # In 88 lifted collectors, the retirement fold declares `$Retire` but then reads the
    # surrounding collection as `$Retired.ServiceID`.  That happened to work for one item with
    # StrictMode off, but fails as soon as the fixture exercises the documented many-retirement
    # case.  The per-item variable is the only correct binding; repair this known mechanical
    # legacy typo during compilation rather than weaken StrictMode or encode it 88 times.
    $PreambleText = [string]$Definition.Preamble -replace '\$Retired\.ServiceID', '$Retire.ServiceID'

    # Expressions are emitted UNWRAPPED, exactly as the original collector's own `$obj = @{ ... }`
    # hashtable literal wrote them. Two separate reasons, each of which broke a real collector when
    # the first draft wrapped them in `( ... )`:
    #
    #   * A field's source text is not always an EXPRESSION. `Containers/ARO.ps1` and
    #     `Containers/ContainerRegistries.ps1` (among others) write a field as a multi-line
    #     `if (...) { ... } else { ... }` STATEMENT. A hashtable literal accepts a statement as a
    #     value; `( ... )` accepts only a pipeline, so `('Name' = (if (...) ...))` is a PARSE error
    #     -- "The term 'if' is not recognized as a name of a cmdlet". Every field of every such
    #     collector was unreachable.
    #   * `$( ... )` is not a safe substitute either: a subexpression collects the output STREAM,
    #     so `$(@(1))` is the scalar 1 and `$(@())` is `$null`, where the original produced a
    #     one-element array and an empty array respectively. Silently changing the shape of an
    #     array-valued field ('Zone' and friends) is exactly the class of difference the
    #     equivalence proof exists to catch.
    #
    # Not wrapping at all is therefore both the compatible AND the faithful choice: the interpreter
    # reproduces the original hashtable literal, character for character, per field.
    $FieldLines = (@($Definition.Fields) | ForEach-Object {
        $QuotedName = $_.Name -replace "'", "''"
        "        '$QuotedName' = $($_.Expression)"
    }) -join "`n"

    # Each extra loop may carry its OWN preamble -- the statements the original collector runs once
    # per item of the fanned-out collection, before it starts emitting rows for that item. Without
    # this, `Security/Vault.ps1` (which derives its three permission strings per access policy) and
    # `Networking/NATGateway.ps1` and `Networking/VirtualNetwork.ps1` (per subnet) silently produced
    # $null for every field computed inside the loop, where the original produced ''. The row-level
    # Preamble cannot cover it: those statements depend on the loop variable, which does not exist
    # yet when the row preamble runs.
    # The tag loop is the LAST entry of the loop nest, not a fixed frame around the row -- 25
    # collectors have no tag loop at all and RouteTables calls its variable $TagKey, so both the
    # existence and the naming come from the definition.
    $Nest = [System.Collections.Generic.List[object]]::new()
    foreach ($Loop in @($Definition.AdditionalRowLoops)) { $Nest.Add($Loop) }
    if ($Definition.TagLoop) { $Nest.Add($Definition.TagLoop) }

    $OpenLoops  = ''
    $CloseLoops = ''
    $LoopIndex = 0
    foreach ($Loop in $Nest) {
        $LoopIndex++
        $EmitNullWhenEmpty = if ($Loop -is [System.Collections.IDictionary]) {
            $Loop.Contains('EmitNullWhenEmpty') -and [bool]$Loop['EmitNullWhenEmpty']
        } else {
            (@($Loop.PSObject.Properties.Name) -contains 'EmitNullWhenEmpty') -and [bool]$Loop.EmitNullWhenEmpty
        }
        if ($EmitNullWhenEmpty) {
            # A conditional imperative branch can emit a row even when an associated collection
            # is empty.  Preserve that topology generically by materialising one null loop item;
            # do it before foreach because a subexpression drops a bare null from its output
            # stream.  The generated variable is unique per nesting level and never visible to
            # collector fields.
            $LoopValues = "`$__scoutLoopValues$LoopIndex"
            $OpenLoops += "$LoopValues = @($($Loop.Source))`n"
            $OpenLoops += "if (@($LoopValues).Count -eq 0) { $LoopValues = @(`$null) }`n"
            $OpenLoops += "foreach (`$$($Loop.Variable) in $LoopValues) {`n"
        } else {
            $OpenLoops  += "foreach (`$$($Loop.Variable) in $($Loop.Source)) {`n"
        }
        # Legacy collectors use the string sentinel '0' when a resource has no tags, then
        # read `$Tag.Name` / `$Tag.Value`.  With StrictMode that sentinel has no such members.
        # Preserve the legacy row shape explicitly: an untagged row has empty tag cells, rather
        # than weakening StrictMode for every lifted definition.  Do this only for definitions
        # that actually use the property form; collectors such as RouteTables intentionally use
        # their tag-loop value directly.
        $UsesTagNameOrValue = $false
        if ($Definition.TagLoop -and $Loop.Variable -eq $Definition.TagLoop.Variable) {
            $TagMemberPattern = '\$' + [regex]::Escape([string]$Loop.Variable) + '\.(Name|Value)\b'
            $UsesTagNameOrValue = @($Definition.Fields | Where-Object {
                [regex]::IsMatch([string]$_.Expression, $TagMemberPattern)
            }).Count -gt 0
        }
        if ($UsesTagNameOrValue) {
            $OpenLoops += "if (`$null -eq `$$($Loop.Variable) -or `$$($Loop.Variable).PSObject.Properties.Match('Name').Count -eq 0 -or `$$($Loop.Variable).PSObject.Properties.Match('Value').Count -eq 0) { `$$($Loop.Variable) = [pscustomobject]@{ Name = `$null; Value = `$null } }`n"
        }
        # Get-ScoutCollectorDefinition normalises every entry to Variable/Source/Preamble, so the
        # key is always present here even when the original loop body had no setup statements.
        if (-not [string]::IsNullOrWhiteSpace($Loop.Preamble)) {
            $OpenLoops += "$($Loop.Preamble)`n"
        }
        $CloseLoops  = "}`n" + $CloseLoops
    }

    # A deliberately absent subscription is one of the canonical fixture cases.  The original
    # collectors rendered an empty Subscription cell because they ran without StrictMode; make
    # that contract explicit for the conventional `$sub*` lookup locals without loosening the
    # interpreter.  Other preamble locals are intentionally not papered over here: those require
    # a collector-specific definition/fixture correction.
    $SubscriptionFallbacks = [System.Collections.Generic.List[string]]::new()
    $DeclaredSubscriptions = [regex]::Matches($PreambleText, '\$(sub\w*)\s*=') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    foreach ($VariableName in $DeclaredSubscriptions) {
        if ([regex]::IsMatch(($Definition.Fields.Expression -join "`n"), '\$' + [regex]::Escape($VariableName) + '\.Name\b')) {
            $SubscriptionFallbacks.Add("if (-not (Test-Path -LiteralPath 'variable:$VariableName') -or `$null -eq `$$VariableName) { `$$VariableName = [pscustomobject]@{ Name = `$null } }")
        }
    }

    $Body = @"
$PreambleText
$($SubscriptionFallbacks -join "`n")

$OpenLoops
    @{
$FieldLines
    }
    if (`$ResUCount -eq 1) { `$ResUCount = 0 }
$CloseLoops
"@
    if ([string]::IsNullOrWhiteSpace($Definition.RowCondition)) { return $Body }
    return "if ($($Definition.RowCondition)) {`n$Body`n}"
}

function Invoke-ScoutDeclarativeProcessing {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [PSCustomObject]$Definition,
        [Parameter(Mandatory)] [hashtable]$Context
    )

    # This interpreter is production engine code, not lifted collector source. Its inputs are
    # schema-normalised by Get-ScoutCollectorDefinition and the context is a hashtable, so keep
    # the module's StrictMode contract while it evaluates a definition.
    $ErrorActionPreference = 'Continue'

    $Resources    = $Context['Resources']
    $Sub          = $Context['Subscriptions']
    $Retirements  = $Context['Retirements']
    $Unsupported  = $Context['Unsupported']

    # ROW ORDER IS THE SHEET'S ORDER, and how a multi-type collector builds its resource set decides
    # it. There are two shapes in the estate and they are NOT interchangeable:
    #
    #   'Grouped'    -- one filtered pass per type, appended:
    #                     $RedisCache  = $Resources | Where-Object { $_.TYPE -eq 'microsoft.cache/redis' }
    #                     $RedisCache += $Resources | Where-Object { $_.TYPE -eq 'microsoft.cache/redisenterprise' }
    #                   Every redis row precedes every redisenterprise row however the two interleave
    #                   in $Resources.
    #   'SinglePass'  -- ONE pass whose condition admits several types:
    #                     $arcSites = $Resources | Where-Object { $_.TYPE -in @('microsoft.azurestackhci/sites', ...) }
    #                   Rows come out in $Resources order, types interleaved.
    #
    # `Hybrid/ArcSites.ps1` is the second shape, and interpreting it as the first reordered its
    # worksheet -- caught by the equivalence proof, which is why the mode is declared per collector
    # instead of assumed. For a single-type collector the two are identical.
    $Matched = if ($Definition.RowSource) {
        # A schema-validated projection lets any envelope fan out without service-specific
        # interpreter logic.  Its input is limited to values the imperative Processing branch had.
        $SourceVariables = [System.Collections.Generic.List[psvariable]]::new()
        $SourceVariables.Add([psvariable]::new('Resources', $Resources))
        $SourceVariables.Add([psvariable]::new('SUB', $Sub))
        $SourceVariables.Add([psvariable]::new('Retirements', $Retirements))
        $SourceVariables.Add([psvariable]::new('Unsupported', $Unsupported))
        $RowSourceBlock = [scriptblock]::Create($Definition.RowSource.Expression)
        @($RowSourceBlock.InvokeWithContext($null, $SourceVariables))
    } elseif ($Definition.ResourceTypeMatching -eq 'SinglePass') {
        @($Resources | Where-Object { @($Definition.ResourceTypes) -contains $_.TYPE })
    } else {
        @(foreach ($Type in @($Definition.ResourceTypes)) {
            $Resources | Where-Object { $_.TYPE -eq $Type }
        })
    }

    if ($Definition.AdditionalFilter) {
        # The filter may need locals the Processing branch set up before it -- `AI/AppliedAIServices.ps1`
        # tests `$appliedAIKinds -contains $_.KIND` against an array literal defined two lines earlier.
        # FilterPreamble carries those statements verbatim, prepended INSIDE the Where-Object block:
        # assignments emit nothing, so the block's only output is still the condition itself.
        $FilterText = if ([string]::IsNullOrWhiteSpace($Definition.FilterPreamble)) {
            $Definition.AdditionalFilter
        } else {
            "$($Definition.FilterPreamble)`n$($Definition.AdditionalFilter)"
        }
        $ExtraFilter = [scriptblock]::Create($FilterText)
        $Matched = @($Matched | Where-Object $ExtraFilter)
    }

    if (@($Matched).Count -eq 0) { return @() }

    # ONCE-PER-COLLECTOR SETUP (AB#5659). The 15 collectors the audit called 'CrossResourceJoin'
    # hoist one or more secondary `$X = $Resources | Where-Object { $_.TYPE -eq '<other type>' }`
    # passes above their row loop and correlate against them per resource. Those statements are
    # lifted verbatim into SetupPreamble and run HERE -- once -- rather than inside the row script,
    # so a 5,000-NIC estate does not re-filter all 5,000 public IPs 5,000 times.
    #
    # The declared names are recovered by appending a `Get-Variable` per name to the lifted source
    # and reading the PSVariable objects back out of the invocation's output stream: there is no
    # other way to see the scope InvokeWithContext created. A name the preamble never assigned
    # comes back missing and THROWS -- it does not bind $null and carry on, because a join variable
    # that quietly became $null is a whole column of blanks in a shipped report.
    $SetupBindings = [System.Collections.Generic.List[psvariable]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Definition.SetupPreamble)) {
        # -ErrorAction Ignore, not SilentlyContinue: SilentlyContinue still appends to $Error, and
        # Invoke-ScoutProcessing's AB#402 error detection reads $Error.
        $Harvest = (@($Definition.SetupVariables) | ForEach-Object {
            "Get-Variable -Name '$($_ -replace "'", "''")' -ErrorAction Ignore"
        }) -join "`n"
        $SetupScript = [scriptblock]::Create("$($Definition.SetupPreamble)`n$Harvest")

        $SetupContext = [System.Collections.Generic.List[psvariable]]::new()
        $SetupContext.Add([psvariable]::new('Resources', $Resources))
        $SetupContext.Add([psvariable]::new('SUB', $Sub))
        $SetupContext.Add([psvariable]::new('Retirements', $Retirements))
        $SetupContext.Add([psvariable]::new('Unsupported', $Unsupported))

        $Produced = @($SetupScript.InvokeWithContext($null, $SetupContext))
        $ByName = @{}
        foreach ($Item in $Produced) {
            # The lifted source may legitimately emit its own output (a bare expression statement),
            # so select the PSVariables out rather than assuming the stream is only the harvest.
            #
            # Tested with `-is` and used AS IS -- deliberately NOT unwrapped first. Items returned
            # through the output stream are PSObject-wrapped, but `.BaseObject` is not reachable by
            # plain member access on a wrapped object: member lookup resolves against the BASE type,
            # PSVariable has no BaseObject; reading it would be an invalid member access. Every
            # harvested variable was silently discarded that way, which is worth spelling out
            # because the symptom was not a blank column -- the declared-name check below turned it
            # into a throw naming all 13 collectors at once, which is the only reason it took
            # minutes to find rather than a release.
            if ($Item -is [psvariable]) { $ByName[$Item.Name] = $Item }
        }

        $MissingSetup = @(@($Definition.SetupVariables) | Where-Object { -not $ByName.ContainsKey($_) })
        if (@($MissingSetup).Count -gt 0) {
            throw "Collector definition '$($Definition.Path)' declares SetupVariables its SetupPreamble never assigned: $($MissingSetup -join ', ')."
        }
        foreach ($Name in @($Definition.SetupVariables)) { $SetupBindings.Add($ByName[$Name]) }
    }

    $RowScriptText = Build-ScoutDeclarativeRowScript -Definition $Definition
    $RowScriptBlock = [scriptblock]::Create($RowScriptText)

    $Rows = foreach ($Resource in $Matched) {
        $Variables = [System.Collections.Generic.List[psvariable]]::new()
        $Variables.Add([psvariable]::new($Definition.RowLoopVariable, $Resource))
        $Variables.Add([psvariable]::new('SUB', $Sub))
        $Variables.Add([psvariable]::new('Retirements', $Retirements))
        $Variables.Add([psvariable]::new('Unsupported', $Unsupported))
        # Bound unconditionally, matching the original collectors' own scope: Networking/NetworkWatchers
        # does its three sub-resource joins INSIDE the row loop rather than hoisting them, and lifting
        # those statements without $Resources in scope produced three empty columns.
        $Variables.Add([psvariable]::new('Resources', $Resources))
        foreach ($Binding in $SetupBindings) { $Variables.Add($Binding) }

        try {
            $RowScriptBlock.InvokeWithContext($null, $Variables)
        }
        catch [System.Management.Automation.MethodInvocationException] {
            # InvokeWithContext is a .NET method call, so SOME of what the row script throws comes
            # back with an extra layer: `Exception calling "InvokeWithContext" with "2"
            # argument(s): "<the real message>"`. The imperative collector -- same failure, same
            # data -- reports the inner message on its own, and that text is what reaches the
            # customer's run log through Invoke-ScoutCollector's warning. Leaving the layer on
            # would change the wording of every contained-collector failure on the release that
            # switches paths, for no reason connected to what actually failed.
            #
            # Unwrap ONE layer, and only when the inner exception is a PowerShell RuntimeException
            # -- measured, that is exactly the case where the layer was added. The two shapes:
            #
            #   [datetime]$null  ->  MethodInvocationException("...InvokeWithContext...")
            #                          -> RuntimeException("Cannot convert null...")   <- relayed
            #   'x'.Substring(9) ->  MethodInvocationException("Exception calling "Substring"...")
            #                          -> ArgumentOutOfRangeException(...)             <- NOT relayed
            #
            # In the second, InvokeWithContext adds nothing: the MethodInvocationException IS the
            # script's own error and the imperative path reports it verbatim, so unwrapping there
            # would strip a layer the imperative path keeps -- swapping one message difference for
            # another. Typed rather than matched on the word "InvokeWithContext", which is a
            # localisable string.
            $Inner = $_.Exception.InnerException
            if ($Inner -is [System.Management.Automation.RuntimeException]) { throw $Inner }
            throw
        }
    }

    @($Rows)
}

function Invoke-ScoutDeclarativeReporting {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [PSCustomObject]$Definition,
        [Parameter(Mandatory)] [hashtable]$Context
    )

    # Reporting consumes the same schema-normalised definition contract as Processing. Do not
    # weaken StrictMode here: missing export metadata is a definition defect and must fail loudly.
    $ErrorActionPreference = 'Continue'

    $SmaResources = $Context['SmaResources']
    if (-not $SmaResources -or @($SmaResources).Count -eq 0) { return }

    $InTag     = $Context['InTag']
    $File      = $Context['File']
    $TableStyle = $Context['TableStyle']
    $Export    = $Definition.Export

    # Some legacy collectors intentionally emit detail rows without Resource U.  Reporting
    # must treat those as a zero contribution rather than dereferencing a missing member
    # under StrictMode.
    $RowUnits = @($SmaResources | ForEach-Object { Get-AZSCSafeProperty -InputObject $_ -Path 'Resource U' } | Measure-Object -Sum).Sum
    $TableName = "$($Export.TableNamePrefix)$RowUnits"

    $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat $Export.NumberFormat

    $ConditionalText = @(foreach ($Line in @($Export.ConditionalText)) {
        & ([scriptblock]::Create($Line))
    })

    # Column order is the sheet's contract. The original collectors build $Exc by calling
    # $Exc.Add(...) in source order with the two Tag columns added inside `if ($InTag)` -- which
    # is very often NOT at the end (all 13 Databases collectors add 'Resource U' afterwards). So
    # the tag block is INSERTED at the recorded position, not appended.
    $Columns = [System.Collections.Generic.List[string]]::new()
    foreach ($Col in @($Export.Columns)) { $Columns.Add($Col) }
    if ($InTag) {
        $InsertAt = $Columns.Count
        if (-not [string]::IsNullOrWhiteSpace($Export.TagColumnsBefore)) {
            $Found = $Columns.IndexOf($Export.TagColumnsBefore)
            if ($Found -ge 0) { $InsertAt = $Found }
        }
        foreach ($Col in @($Export.TagColumns)) {
            $Columns.Insert($InsertAt, $Col)
            $InsertAt++
        }
    }

    $ExportParams = @{
        Path          = $File
        WorksheetName = $Export.WorksheetName
        AutoSize      = $true
        MaxAutoSizeRows = 100
        TableName     = $TableName
        TableStyle    = $TableStyle
        Style         = $Style
    }
    if (@($ConditionalText).Count -gt 0) { $ExportParams['ConditionalText'] = $ConditionalText }

    $SmaResources |
        ForEach-Object { [PSCustomObject]$_ } |
        Select-Object $Columns |
        Export-Excel @ExportParams
}
