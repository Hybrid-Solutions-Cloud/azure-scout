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
            foreach ($Tag in $Tags) {
                @{ '<Field.Name>' = (<Field.Expression>); ... }
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
    Tracks ADO AB#5657/AB#5659 (Feature AB#5656, Epic AB#5638). Deliberately NOT wired into
    `Invoke-ScoutProcessing` yet -- this is the schema's proof of equivalence
    (`tests/DeclarativeCollectorEquivalence.Tests.ps1`), not a live-pipeline cutover. See the
    ADR §3 for why that is staged separately.
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

    $FieldLines = (@($Definition.Fields) | ForEach-Object {
        $QuotedName = $_.Name -replace "'", "''"
        "        '$QuotedName' = ($($_.Expression))"
    }) -join "`n"

    $OpenLoops  = ''
    $CloseLoops = ''
    foreach ($Loop in @($Definition.AdditionalRowLoops)) {
        $OpenLoops  += "foreach (`$$($Loop.Variable) in $($Loop.Source)) {`n"
        $CloseLoops  = "}`n" + $CloseLoops
    }

    @"
$($Definition.Preamble)

$OpenLoops
foreach (`$Tag in `$Tags) {
    @{
$FieldLines
    }
    if (`$ResUCount -eq 1) { `$ResUCount = 0 }
}
$CloseLoops
"@
}

function Invoke-ScoutDeclarativeProcessing {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [PSCustomObject]$Definition,
        [Parameter(Mandatory)] [hashtable]$Context
    )

    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'

    $Resources    = $Context['Resources']
    $Sub          = $Context['Subscriptions']
    $Retirements  = $Context['Retirements']
    $Unsupported  = $Context['Unsupported']

    # Matched resources are grouped BY DECLARED TYPE, in the order ResourceTypes lists them, and
    # keep their original relative order within each type. That is not cosmetic: a multi-type
    # collector builds its set by appending one filtered pass per type --
    #
    #     $RedisCache  = $Resources | Where-Object { $_.TYPE -eq 'microsoft.cache/redis' }
    #     $RedisCache += $Resources | Where-Object { $_.TYPE -eq 'microsoft.cache/redisenterprise' }
    #
    # -- so every redis row precedes every redisenterprise row regardless of how the two are
    # interleaved in $Resources. A single `-contains` pass over $Resources instead preserves the
    # arrival order, which silently reorders the rows (and therefore the worksheet) whenever the
    # estate interleaves the types. Single-type collectors -- 12 of the 13 Databases ones -- are
    # unaffected either way, since one group in $Resources order IS $Resources order.
    $Matched = @(foreach ($Type in @($Definition.ResourceTypes)) {
        $Resources | Where-Object { $_.TYPE -eq $Type }
    })

    if ($Definition.AdditionalFilter) {
        $ExtraFilter = [scriptblock]::Create($Definition.AdditionalFilter)
        $Matched = @($Matched | Where-Object $ExtraFilter)
    }

    if (@($Matched).Count -eq 0) { return @() }

    $RowScriptText = Build-ScoutDeclarativeRowScript -Definition $Definition
    $RowScriptBlock = [scriptblock]::Create($RowScriptText)

    $Rows = foreach ($Resource in $Matched) {
        $Variables = [System.Collections.Generic.List[psvariable]]::new()
        $Variables.Add([psvariable]::new($Definition.RowLoopVariable, $Resource))
        $Variables.Add([psvariable]::new('SUB', $Sub))
        $Variables.Add([psvariable]::new('Retirements', $Retirements))
        $Variables.Add([psvariable]::new('Unsupported', $Unsupported))

        $RowScriptBlock.InvokeWithContext($null, $Variables)
    }

    @($Rows)
}

function Invoke-ScoutDeclarativeReporting {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [PSCustomObject]$Definition,
        [Parameter(Mandatory)] [hashtable]$Context
    )

    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'

    $SmaResources = $Context['SmaResources']
    if (-not $SmaResources -or @($SmaResources).Count -eq 0) { return }

    $InTag     = $Context['InTag']
    $File      = $Context['File']
    $TableStyle = $Context['TableStyle']
    $Export    = $Definition.Export

    $RowUnits = @($SmaResources | ForEach-Object { $_.'Resource U' } | Measure-Object -Sum).Sum
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
