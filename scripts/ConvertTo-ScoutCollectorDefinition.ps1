#Requires -Version 7.0
<#
.SYNOPSIS
    Convert a Standard-contract inventory collector into a declarative `.psd1` definition
    (AB#5660).

.DESCRIPTION
    Lifts a collector's resource-type filter, per-field expressions, and Excel export spec out
    of its PowerShell AST and writes them as a `.psd1` data file matching the schema in
    `docs/design/decisions/declarative-collectors.md`. Field expressions are copied VERBATIM —
    same source text, same local-variable names ($1, $data, $sub1, $Tag, $RetiringFeature,
    $RetiringDate, $ResUCount) the original collector used — so `Invoke-ScoutDeclarativeCollector`
    can evaluate them in an equivalent scope without any textual rewriting. That is what makes
    the equivalence proof in `tests/DeclarativeCollectorEquivalence.Tests.ps1` meaningful: the
    same expression runs both ways.

    This tool is only reliable for collectors the audit (AB#5658,
    `tests/fixtures/collector-audit.json`) classified `PureShaping` — it has no way to convert a
    cross-resource join or a live cmdlet call, and will refuse (with an explanatory error) rather
    than emit a definition that silently drops that logic. Escape-hatch collectors stay
    hand-written `.ps1` files by design (see the ADR §2.4).

    It is a STARTING POINT, not a one-shot black box: it does the mechanical AST extraction
    correctly, but the output should be reviewed against the original file before being trusted,
    the same way any generated code is.

.PARAMETER CollectorPath
    Path to the original collector .ps1 file.

.PARAMETER OutputPath
    Where to write the generated .psd1. Defaults to
    manifests/collectors/<Category>/<Name>.psd1 alongside the repo's other collector definitions.

.PARAMETER WhatIf
    Print the definition to the console instead of writing it.

.OUTPUTS
    The path written (or, under -WhatIf, the definition text).

.NOTES
    Tracks ADO AB#5660 (Feature AB#5656, Epic AB#5638).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$CollectorPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$Show
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-InnerExpr {
    <# Peel PipelineAst/CommandExpressionAst wrappers off an expression node -- see the audit script for why this is needed. #>
    param([System.Management.Automation.Language.Ast]$Node)
    $Current = $Node
    while ($true) {
        if ($Current -is [System.Management.Automation.Language.PipelineAst] -and $Current.PipelineElements.Count -eq 1) {
            $Current = $Current.PipelineElements[0]; continue
        }
        if ($Current -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Current = $Current.Expression; continue
        }
        break
    }
    return $Current
}

function Get-ProcessingAndReportingBlocks {
    param([System.Management.Automation.Language.Ast]$Ast)
    $IfStatements = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true)
    foreach ($If in $IfStatements) {
        $Clause = $If.Clauses[0]
        $Cond = Get-InnerExpr -Node $Clause.Item1
        if ($Cond -is [System.Management.Automation.Language.BinaryExpressionAst] -and $Cond.Operator -in @('Ieq', 'Ceq', 'Eq')) {
            $Left = $Cond.Left; $Right = $Cond.Right
            $TaskIsLeft  = $Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $Left.VariablePath.UserPath -ieq 'Task'
            $TaskIsRight = $Right -is [System.Management.Automation.Language.VariableExpressionAst] -and $Right.VariablePath.UserPath -ieq 'Task'
            $ValueNode = if ($TaskIsLeft) { $Right } elseif ($TaskIsRight) { $Left } else { $null }
            if ($ValueNode -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $ValueNode.Value -ieq 'Processing') {
                return [PSCustomObject]@{
                    Processing = $Clause.Item2
                    Reporting  = $If.ElseClause
                }
            }
        }
    }
    return [PSCustomObject]@{ Processing = $null; Reporting = $null }
}

function ConvertTo-Psd1Literal {
    <# Render a value as a PowerShell data-file literal: strings single-quoted/escaped, arrays as @(...), hashtables as @{...}. #>
    param($Value, [int]$Indent = 0)
    $Pad = '    ' * $Indent
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { if ($Value) { return '$true' } else { return '$false' } }
    if ($Value -is [int] -or $Value -is [double]) { return "$Value" }
    if ($Value -is [string]) { return "'" + ($Value -replace "'", "''") + "'" }
    if ($Value -is [System.Collections.IDictionary]) {
        $Lines = foreach ($Key in $Value.Keys) {
            "$Pad    $Key = $(ConvertTo-Psd1Literal -Value $Value[$Key] -Indent ($Indent + 1))"
        }
        return "@{`n" + ($Lines -join "`n") + "`n$Pad}"
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Items = @($Value)
        if ($Items.Count -eq 0) { return '@()' }
        $Lines = foreach ($Item in $Items) { "$Pad    $(ConvertTo-Psd1Literal -Value $Item -Indent ($Indent + 1))" }
        return "@(`n" + ($Lines -join "`n") + "`n$Pad)"
    }
    return "'" + ("$Value" -replace "'", "''") + "'"
}

# --- Parse ------------------------------------------------------------------------------------

$FullPath = (Resolve-Path -LiteralPath $CollectorPath).Path
$Tokens = $null; $Errors = $null
$Ast = [System.Management.Automation.Language.Parser]::ParseFile($FullPath, [ref]$Tokens, [ref]$Errors)
if (@($Errors).Count -gt 0) { throw "Parse errors in $FullPath`: $($Errors -join '; ')" }

$Name     = [System.IO.Path]::GetFileNameWithoutExtension($FullPath)
$Category = Split-Path -Leaf (Split-Path -Parent $FullPath)

$Blocks = Get-ProcessingAndReportingBlocks -Ast $Ast
if (-not $Blocks.Processing) { throw "Could not find the '`$Task -eq ''Processing''' branch in $FullPath -- is this a Standard-contract collector?" }

# --- Resource type filter -----------------------------------------------------------------------

$Assignments = $Blocks.Processing.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
$FilterVarNames = [System.Collections.Generic.List[string]]::new()
$ResourceTypes  = [System.Collections.Generic.List[string]]::new()
$AdditionalFilterText = $null
$RowLoopVarName = $null

foreach ($Assign in $Assignments) {
    if ($Assign.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
    $VarName = $Assign.Left.VariablePath.UserPath
    $Rhs = $Assign.Right
    $Elements = if ($Rhs -is [System.Management.Automation.Language.PipelineAst]) { $Rhs.PipelineElements } else { continue }
    if (@($Elements).Count -lt 2) { continue }
    $SourceExpr = Get-InnerExpr -Node $Elements[0]
    if (-not ($SourceExpr -is [System.Management.Automation.Language.VariableExpressionAst] -and $SourceExpr.VariablePath.UserPath -ieq 'Resources')) { continue }
    $WhereCmd = $Elements | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] -and $_.GetCommandName() -ieq 'Where-Object' } | Select-Object -First 1
    if (-not $WhereCmd) { continue }
    $ScriptBlockParam = $WhereCmd.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } | Select-Object -First 1
    if (-not $ScriptBlockParam) { continue }

    $TypeReads = @($ScriptBlockParam.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.MemberExpressionAst] -and
        $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Expression.VariablePath.UserPath -eq '_' -and
        $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $n.Member.Value -ieq 'TYPE'
    }, $true))
    if ($TypeReads.Count -eq 0) { continue }

    $Strings = @($ScriptBlockParam.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
    $Types = @($Strings | Where-Object { $_.Value -match '^[a-zA-Z0-9.]+/[a-zA-Z0-9./]+$' } | ForEach-Object { $_.Value })
    foreach ($T in $Types) { if ($ResourceTypes -notcontains $T) { [void]$ResourceTypes.Add($T) } }
    if ($FilterVarNames -notcontains $VarName) { [void]$FilterVarNames.Add($VarName) }

    # A compound condition ($_.TYPE -eq '...' -AND something-else) -- lift the "something else"
    # verbatim as the additional filter. SQLDB is the one Databases collector that needs this
    # ($_.name -ne 'master').
    $FullFilterText = $ScriptBlockParam.Extent.Text.Trim('{', '}').Trim()
    if ($FullFilterText -match '-and\s+(.+)$') {
        $AdditionalFilterText = $Matches[1].Trim()
    }
}

if ($ResourceTypes.Count -eq 0) { throw "$FullPath -- no `$Resources | Where-Object { `$_.TYPE -eq ... } filter found. This looks like an escape-hatch collector (live cmdlet call or no resource filter); it is not a candidate for automatic conversion." }

# The per-row loop: `$tmp = foreach ($1 in <var>) { ... $obj = @{...} ... }`. Its own iteration
# variable is what field expressions are written against, whatever it is actually called ($1,
# $0, etc.) -- captured so the interpreter knows which name to bind.
$ForEachLoops = @($Blocks.Processing.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true))
$RowLoop = $ForEachLoops | Where-Object {
    @($_.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq 'obj' }, $true)).Count -gt 0
} | Select-Object -First 1
if (-not $RowLoop) { throw "$FullPath -- no per-row `foreach` loop building `$obj` was found." }
$RowLoopVarName = $RowLoop.Variable.VariablePath.UserPath

# Join detection itself lives in Invoke-CollectorAudit.ps1 (AB#5658) -- this tool is only ever
# meant to run against collectors the audit already classified PureShaping, so a genuine
# cross-resource join should never reach here. It is not re-detected a second time.

# --- AdditionalRowLoops (rare: SQLMIDB-style per-resource fan-out before the tag loop) -----------

$AdditionalRowLoops = [System.Collections.Generic.List[hashtable]]::new()
$NestedLoops = @($RowLoop.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true))
foreach ($Nested in $NestedLoops) {
    $LoopVar = $Nested.Variable.VariablePath.UserPath
    if ($LoopVar -ieq 'Tag') { continue }               # the standard tag-expansion primitive
    if ($LoopVar -ieq 'Retire' -or $LoopVar -ieq 'Retirement') { continue }  # part of the retirement primitive
    # Only loops that are themselves ancestors of the Tag loop (i.e. wrap it) are a row fan-out;
    # a sibling loop used only to build a scalar (like the retirement fold) is not.
    $WrapsTagLoop = @($Nested.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Variable.VariablePath.UserPath -ieq 'Tag' }, $true)).Count -gt 0
    if (-not $WrapsTagLoop) { continue }

    # The collection itself (e.g. $pvteps) is computed IN THE PREAMBLE below, verbatim, like
    # everything else a collector's row loop sets up. AdditionalRowLoops only records which
    # already-preamble-computed variable the extra loop iterates -- not a second copy of how
    # it is computed.
    $SourceExprNode = Get-InnerExpr -Node $Nested.Condition
    $SourceRef = if ($SourceExprNode -is [System.Management.Automation.Language.VariableExpressionAst]) {
        '$' + $SourceExprNode.VariablePath.UserPath
    } else {
        $Nested.Condition.Extent.Text
    }
    [void]$AdditionalRowLoops.Add(@{ Variable = $LoopVar; Source = $SourceRef })
}

# --- Preamble: every per-resource setup statement, verbatim, before the row-expansion loop(s) ---
#
# Everything the row loop computes for ONE resource before it starts emitting rows -- the
# subscription lookup, the retirement fold, tag detection, and whatever collector-specific
# locals a particular file happens to need ($DBServer, $PoolId, $sku, ...) -- copied as exact
# source text, not reconstructed. The boundary is the row loop's OWN top-level foreach (the tag
# loop, or whatever wraps it via AdditionalRowLoops): everything before it is preamble, the loop
# itself and beyond is handled by the interpreter's row-expansion logic instead.
$FileText = $Ast.Extent.Text
$TopLevelForEach = @($RowLoop.Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.ForEachStatementAst] })
if (@($TopLevelForEach).Count -eq 0) { throw "$FullPath -- the row loop has no top-level tag/row-expansion `foreach`; this collector's shape is not recognised." }
$BoundaryLoop = $TopLevelForEach[-1]

$PreambleStatements = @($RowLoop.Body.Statements | Where-Object { $_.Extent.StartOffset -lt $BoundaryLoop.Extent.StartOffset })
$Preamble = ''
if (@($PreambleStatements).Count -gt 0) {
    $Start = $PreambleStatements[0].Extent.StartOffset
    $End   = $PreambleStatements[-1].Extent.EndOffset
    $Preamble = $FileText.Substring($Start, $End - $Start)
}

# --- Fields (verbatim expression text from the $obj = @{...} hashtable) -------------------------

$ObjAssignments = $RowLoop.Body.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $n.Left.VariablePath.UserPath -ieq 'obj'
}, $true)
if (@($ObjAssignments).Count -eq 0) { throw "$FullPath -- no `$obj = @{...}` hashtable literal found." }

$FirstObj = $ObjAssignments[0]
$HashtableNode = Get-InnerExpr -Node $FirstObj.Right
if ($HashtableNode -isnot [System.Management.Automation.Language.HashtableAst]) { throw "$FullPath -- `$obj`'s right-hand side is not a plain hashtable literal; this collector needs manual conversion." }

$Fields = [System.Collections.Generic.List[hashtable]]::new()
$SeenFieldNames = [System.Collections.Generic.HashSet[string]]::new()
foreach ($Pair in $HashtableNode.KeyValuePairs) {
    if ($Pair.Item1 -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
    $FieldName = $Pair.Item1.Value
    if (-not $SeenFieldNames.Add($FieldName)) { continue }
    $ExprText = $Pair.Item2.Extent.Text.Trim()
    [void]$Fields.Add(@{ Name = $FieldName; Expression = $ExprText })
}

# --- Reporting branch: worksheet name, table-name prefix, columns, conditional formatting -------

$Report = @{ WorksheetName = $Name; TableNamePrefix = "${Name}Table_"; Columns = @(); TagColumns = @('Tag Name', 'Tag Value'); TagColumnsBefore = $null; ConditionalText = @(); NumberFormat = '0' }

if ($Blocks.Reporting) {
    $AddCalls = $Blocks.Reporting.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Expression.VariablePath.UserPath -ieq 'Exc' -and
        $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $n.Member.Value -ieq 'Add'
    }, $true)
    $AllColumns = @(foreach ($Add in $AddCalls) {
        if (@($Add.Arguments).Count -gt 0 -and $Add.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $Add.Arguments[0].Value }
    })
    # The two Tag columns are always conditionally added inside `if ($InTag) {...}` -- split
    # them out of the plain column order into TagColumns, added only when $InTag is set.
    $Report.Columns    = @($AllColumns | Where-Object { $_ -notin @('Tag Name', 'Tag Value') })
    $Report.TagColumns = @($AllColumns | Where-Object { $_ -in @('Tag Name', 'Tag Value') })
    if (@($Report.TagColumns).Count -eq 0) { $Report.TagColumns = @('Tag Name', 'Tag Value') }

    # WHERE the tag columns sit is part of the sheet's contract, not a detail. All 13 Databases
    # collectors call $Exc.Add('Resource U') AFTER the `if ($InTag)` block, so the shipped column
    # order under -IncludeTags ends '... , Tag Name, Tag Value, Resource U' -- appending TagColumns
    # to the end of Columns (the schema's first draft) silently reordered the last three columns of
    # every tagged report. Record the column the tag block precedes so the interpreter can insert
    # rather than append; $null means the original really did add them last.
    $LastTagIndex = -1
    for ($c = 0; $c -lt $AllColumns.Count; $c++) {
        if ($AllColumns[$c] -in @('Tag Name', 'Tag Value')) { $LastTagIndex = $c }
    }
    if ($LastTagIndex -ge 0 -and $LastTagIndex -lt ($AllColumns.Count - 1)) {
        $Report.TagColumnsBefore = $AllColumns[$LastTagIndex + 1]
    }

    $ExportCalls = $Blocks.Reporting.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ieq 'Export-Excel' }, $true)
    if (@($ExportCalls).Count -gt 0) {
        $ExportCall = $ExportCalls[0]
        for ($i = 0; $i -lt $ExportCall.CommandElements.Count; $i++) {
            $Elem = $ExportCall.CommandElements[$i]
            if ($Elem -is [System.Management.Automation.Language.CommandParameterAst] -and $Elem.ParameterName -ieq 'WorksheetName') {
                $ValueNode = $ExportCall.CommandElements[$i + 1]
                if ($ValueNode -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $Report.WorksheetName = $ValueNode.Value }
                elseif ($ValueNode -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    # WorksheetName was assigned to a variable earlier ($SheetName = '...') -- resolve it.
                    $VarAssign = $Blocks.Reporting.FindAll({
                        param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq $ValueNode.VariablePath.UserPath
                    }, $true) | Select-Object -First 1
                    if ($VarAssign -and (Get-InnerExpr -Node $VarAssign.Right) -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $Report.WorksheetName = (Get-InnerExpr -Node $VarAssign.Right).Value
                    }
                }
            }
        }
    }

    $TableNameAssign = $Blocks.Reporting.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq 'TableName' }, $true) | Select-Object -First 1
    if ($TableNameAssign) {
        $Text = $TableNameAssign.Right.Extent.Text
        if ($Text -match "\('([^']+)'\s*\+") { $Report.TableNamePrefix = $Matches[1] }
    }

    $StyleCalls = $Blocks.Reporting.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ieq 'New-ExcelStyle' }, $true)
    if (@($StyleCalls).Count -gt 0) {
        $StyleText = $StyleCalls[0].Extent.Text
        if ($StyleText -match '-NumberFormat\s+([^\s]+)') { $Report.NumberFormat = $Matches[1].Trim("'", '"') }
    }

    $CondCalls = $Blocks.Reporting.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ieq 'New-ConditionalText' }, $true)
    $CondEntries = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($Call in $CondCalls) {
        [void]$CondEntries.Add(@{ SourceText = $Call.Extent.Text.Trim() })
    }
    $Report.ConditionalText = @($CondEntries | ForEach-Object { $_ })
}

# --- Assemble the definition ---------------------------------------------------------------------

$Definition = [ordered]@{
    ResourceTypes       = @($ResourceTypes)
    AdditionalFilter    = $AdditionalFilterText
    RowLoopVariable     = $RowLoopVarName
    Preamble            = $Preamble
    AdditionalRowLoops  = @($AdditionalRowLoops | ForEach-Object { [ordered]@{ Variable = $_.Variable; Source = $_.Source } })
    Fields              = @($Fields | ForEach-Object { [ordered]@{ Name = $_.Name; Expression = $_.Expression } })
    Export              = [ordered]@{
        WorksheetName    = $Report.WorksheetName
        TableNamePrefix  = $Report.TableNamePrefix
        Columns          = @($Report.Columns)
        TagColumns       = @($Report.TagColumns)
        TagColumnsBefore = $Report.TagColumnsBefore
        NumberFormat     = $Report.NumberFormat
        ConditionalText  = @($Report.ConditionalText | ForEach-Object { $_.SourceText })
    }
    SourceCollector     = ("Modules/Public/InventoryModules/$Category/$Name.ps1").Replace('\', '/')
}

$Psd1Text = "@{`n" + (($Definition.GetEnumerator() | ForEach-Object {
    if ($_.Key -eq 'Preamble') {
        # A here-string, not ConvertTo-Psd1Literal's normal single-quoted escaping -- preamble
        # source commonly contains its own single AND double quotes, and a here-string needs no
        # escaping of either.
        "    Preamble = @'`n$($_.Value)`n'@"
    } else {
        "    $($_.Key) = $(ConvertTo-Psd1Literal -Value $_.Value -Indent 1)"
    }
}) -join "`n`n") + "`n}`n"

$Header = @"
#
# GENERATED by scripts/ConvertTo-ScoutCollectorDefinition.ps1 from $($Definition.SourceCollector) (AB#5660).
# Field expressions are copied verbatim from the original collector and evaluate in an
# equivalent scope -- see docs/design/decisions/declarative-collectors.md.
# Review before trusting; regenerate rather than hand-patch if the source collector changes.
#
"@

$FullText = $Header + "`n" + $Psd1Text

if ($Show -or $WhatIfPreference) {
    $FullText
    return
}

if (-not $OutputPath) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $OutputPath = Join-Path $RepoRoot 'manifests' 'collectors' $Category "$Name.psd1"
}

$OutputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write declarative collector definition')) {
    Set-Content -LiteralPath $OutputPath -Value $FullText -Encoding utf8
    Write-Host "[ConvertTo-ScoutCollectorDefinition] Wrote $OutputPath"
}

$OutputPath
