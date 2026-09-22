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

function Get-ExternalAccessCall {
    <#
        Return commands that make live Azure/Graph calls or construct a COM object. This mirrors
        the audit classifier because conversion must refuse the exact set the audit classifies as
        live access; otherwise a live call can be lifted verbatim into Preamble/Fields and execute
        inside the supposedly declarative interpreter.

        The three Get-AZSC helpers are local data-shaping functions, despite sharing the Get-Az
        prefix case-insensitively. New-Object is rejected only for -Com/-ComObject.
    #>
    param([System.Management.Automation.Language.Ast]$Block)

    if (-not $Block) { return @() }

    $InProcessHelpers = @(
        'Get-AZSCSafeProperty'
        'Get-AZSCIdSegment'
        'Get-AZSCCollectedValue'
    )
    $AzureCommandPattern = '^(Get-Az|Invoke-Az|New-Az|Set-Az|Connect-Az|Get-Msol|Get-Mg|Invoke-Mg)'
    $ExactExternalNames = @(
        'Search-AzGraph'
        'Invoke-RestMethod'
        'Invoke-WebRequest'
    )

    $Calls = @(foreach ($Command in $Block.FindAll({
        param($Node)
        $Node -is [System.Management.Automation.Language.CommandAst]
    }, $true)) {
        $Name = $Command.GetCommandName()
        if (-not $Name -or $Name -in $InProcessHelpers) { continue }

        if ($Name -ieq 'New-Object') {
            $ComParameter = @($Command.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                $_.ParameterName -in @('Com', 'ComObject')
            })
            if ($ComParameter.Count -gt 0) { 'New-Object -Com' }
            continue
        }

        if ($Name -in $ExactExternalNames -or $Name -match $AzureCommandPattern) { $Name }
    })

    return @($Calls | Select-Object -Unique)
}

function ConvertTo-Psd1Literal {
    <# Render a value as a PowerShell data-file literal: strings single-quoted/escaped, arrays as @(...), hashtables as @{...}. #>
    param($Value, [int]$Indent = 0)
    $Pad = '    ' * $Indent
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { if ($Value) { return '$true' } else { return '$false' } }
    if ($Value -is [int] -or $Value -is [double]) { return "$Value" }
    if ($Value -is [string]) {
        # Lifted source spanning several lines (an AdditionalRowLoops.Preamble) is written as a
        # here-string: a single-quoted literal would still be CORRECT, but every apostrophe in the
        # original code gets doubled and the result is unreadable next to the file it came from --
        # which matters, because reviewing a generated definition against its source is the only
        # check on the AST extraction.
        if ($Value.Contains("`n")) { return "@'`n$Value`n'@" }
        return "'" + ($Value -replace "'", "''") + "'"
    }
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

$ExternalCalls = @(Get-ExternalAccessCall -Block $Blocks.Processing)
if ($ExternalCalls.Count -gt 0) {
    throw "$FullPath -- the Processing branch contains live external access ($($ExternalCalls -join ', ')); move that access into src/collect before generating a declarative definition."
}

# --- The per-row loop, found FIRST ----------------------------------------------------------------
#
# `$tmp = foreach ($1 in <var>) { ... $obj = @{...} ... }`. Its own iteration variable is what field
# expressions are written against, whatever it is actually called ($1, $0, ...) -- captured so the
# interpreter knows which name to bind.
#
# It is located BEFORE the resource-type extraction, not after, because WHICH variable it iterates is
# what identifies the collector's PRIMARY resource set. 20 collectors filter `$Resources` more than
# once at the top of their Processing branch -- a primary set to iterate plus one or more secondary
# sets to correlate against:
#
#     $PrivateDNS = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/privatednszones' }
#     $VNETLinks  = $Resources | Where-Object { $_.TYPE -eq '...privatednszones/virtualnetworklinks' }
#     foreach ($1 in $PrivateDNS) { ... }
#
# Treating every filtered assignment as a row source (which this tool used to) would declare
# virtualnetworklinks as a second ResourceType and emit a row for each one -- a sheet with twice the
# rows it should have. Worse, for Web/APPServicePlan the SECONDARY filter carries the compound
# `-and $_.Properties.enabled -eq 'true'`, which would have been lifted as the row set's
# AdditionalFilter and silently dropped every app service plan in the estate.
$ForEachLoops = @($Blocks.Processing.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true))
$RowLoop = $ForEachLoops | Where-Object {
    @($_.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq 'obj' }, $true)).Count -gt 0
} | Select-Object -First 1
if (-not $RowLoop) { throw "$FullPath -- no per-row `foreach` loop building `$obj` was found." }
$RowLoopVarName = $RowLoop.Variable.VariablePath.UserPath

$RowSourceNode = Get-InnerExpr -Node $RowLoop.Condition
$RowSourceVar = if ($RowSourceNode -is [System.Management.Automation.Language.VariableExpressionAst]) {
    $RowSourceNode.VariablePath.UserPath
} else {
    throw "$FullPath -- the row loop iterates '$($RowLoop.Condition.Extent.Text)' rather than a variable holding a filtered `$Resources` set; this collector's shape is not recognised."
}

# A source assignment can fan a synthetic, already-collected envelope out into the items that the
# row loop consumes.  Record the RHS as a generic RowSource expression instead of teaching the
# interpreter collector names.  Direct '$Resources | Where-Object' assignments keep the compact
# ResourceTypes-only form used by existing definitions.
$RowSourceExpression = $null
$RowSourceAssignment = @($Blocks.Processing.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $n.Left.VariablePath.UserPath -ieq $RowSourceVar
}, $true) | Select-Object -First 1)
if ($RowSourceAssignment.Count -gt 0) {
    $SourceHasResources = @($RowSourceAssignment[0].Right.FindAll({
        param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -ieq 'Resources'
    }, $true)).Count -gt 0
    $SourceHasForEach = @($RowSourceAssignment[0].Right.FindAll({
        param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst]
    }, $true)).Count -gt 0
    if ($SourceHasResources -and $SourceHasForEach) {
        $RowSourceExpression = $RowSourceAssignment[0].Right.Extent.Text.Trim()
    }
}

# The top-level statement that CONTAINS the row loop -- almost always `if ($X) { $tmp = foreach ... }`.
# Everything before it is the collector's once-per-run setup; everything from it onwards is per-row.
# The boundary is needed this early because "is this filtered assignment a hoisted secondary set?"
# is exactly the question "does it sit before this statement?" -- Networking/NetworkWatchers derives
# three filtered sets INSIDE its row loop, and counting those as hoisted produced a SetupPreamble
# holding nothing but the primary filter: dead code, which the loader is right to reject.
$RowLoopOwner = @($Blocks.Processing.Statements | Where-Object {
    $_.Extent.StartOffset -le $RowLoop.Extent.StartOffset -and $_.Extent.EndOffset -ge $RowLoop.Extent.EndOffset
})[0]
if (-not $RowLoopOwner) { throw "$FullPath -- the row loop is not contained in any top-level statement of the Processing branch; this collector's shape is not recognised." }

# --- Resource type filter -----------------------------------------------------------------------

$Assignments = $Blocks.Processing.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
$FilterVarNames = [System.Collections.Generic.List[string]]::new()
$ResourceTypes  = [System.Collections.Generic.List[string]]::new()
$AdditionalFilterText = $null
$FilterAssignmentCount = 0
$FirstFilterAssignment = $null
$SecondaryFilterVars = [System.Collections.Generic.List[string]]::new()

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

    # A filtered set that is NOT what the row loop iterates is a SECONDARY set: it goes into the
    # setup section verbatim and contributes neither a ResourceType nor an AdditionalFilter.
    if ($VarName -ine $RowSourceVar) {
        # ...but only if it is HOISTED. A filtered set derived inside the row loop stays in the row
        # Preamble, where the interpreter's bound $Resources serves it.
        if ($Assign.Extent.StartOffset -lt $RowLoopOwner.Extent.StartOffset -and $SecondaryFilterVars -notcontains $VarName) {
            [void]$SecondaryFilterVars.Add($VarName)
        }
        continue
    }

    $Strings = @($ScriptBlockParam.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
    $Types = @($Strings | Where-Object { $_.Value -match '^[a-zA-Z0-9.]+/[a-zA-Z0-9./]+$' } | ForEach-Object { $_.Value })
    foreach ($T in $Types) { if ($ResourceTypes -notcontains $T) { [void]$ResourceTypes.Add($T) } }
    if ($FilterVarNames -notcontains $VarName) { [void]$FilterVarNames.Add($VarName) }
    $FilterAssignmentCount++
    if (-not $FirstFilterAssignment) { $FirstFilterAssignment = $Assign }

    # A compound condition ($_.TYPE -eq '...' -AND something-else) -- lift the "something else"
    # verbatim as the additional filter. SQLDB is the one Databases collector that needs this
    # ($_.name -ne 'master').
    #
    # (?s) so the tail of a filter written across several lines is captured whole:
    # AI/AppliedAIServices.ps1 puts `$appliedAIKinds -contains $_.KIND` on its own line.
    $FullFilterText = $ScriptBlockParam.Extent.Text.Trim('{', '}').Trim()
    if ($FullFilterText -match '(?s)-and\s+(.+)$') {
        $AdditionalFilterText = $Matches[1].Trim()
    }
}

# An envelope projection keeps its type filter inside RowSource.Expression.  Declare those types in
# the manifest too, so inventory coverage is visible and schema validation is identical to direct
# collectors.
if ($ResourceTypes.Count -eq 0 -and $RowSourceExpression) {
    foreach ($String in @($RowSourceAssignment[0].Right.FindAll({
        param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true))) {
        if ($String.Value -match '^[a-zA-Z0-9.]+/[a-zA-Z0-9./]+$' -and $ResourceTypes -notcontains $String.Value) {
            [void]$ResourceTypes.Add($String.Value)
        }
    }
}

# WHICH SHAPE built the resource set decides ROW ORDER for a multi-type collector, so it is recorded
# rather than assumed. Several filtered assignments (`$X = ...` then `$X += ...`) means one pass per
# type, appended: 'Grouped'. One assignment that admits several types (`$_.TYPE -in @(...)`) means a
# single pass in $Resources order: 'SinglePass'. Getting this wrong reorders the worksheet, which is
# how Hybrid/ArcSites.ps1 first failed the equivalence proof.
$ResourceTypeMatching = if ($FilterAssignmentCount -le 1 -and $ResourceTypes.Count -gt 1) { 'SinglePass' } else { 'Grouped' }

# Statements the Processing branch runs BEFORE the filter, which a compound filter may depend on --
# AI/AppliedAIServices.ps1 tests against an `$appliedAIKinds = @(...)` array literal defined above it.
# Lifted only when there IS a compound filter; with no AdditionalFilter there is nothing for them to
# feed and carrying them would be dead code the loader rejects.
$FilterPreamble = ''
if ($AdditionalFilterText -and $FirstFilterAssignment) {
    $Before = @($Blocks.Processing.Statements | Where-Object { $_.Extent.StartOffset -lt $FirstFilterAssignment.Extent.StartOffset })
    if (@($Before).Count -gt 0) {
        $FilterPreamble = $Ast.Extent.Text.Substring($Before[0].Extent.StartOffset, $Before[-1].Extent.EndOffset - $Before[0].Extent.StartOffset)
    }
}

if ($ResourceTypes.Count -eq 0) { throw "$FullPath -- no `$Resources | Where-Object { `$_.TYPE -eq ... } filter found for the row loop's source `$$RowSourceVar. This looks like an escape-hatch collector (live cmdlet call or no resource filter); it is not a candidate for automatic conversion." }

# --- Setup section: the once-per-run statements above the row loop --------------------------------
#
# Lifted ONLY when the collector derives a secondary resource set -- the shape the audit calls
# 'CrossResourceJoin'. Without that, the only statement above the row loop is the primary filter the
# interpreter already performs itself, and carrying it would be dead code the loader rejects. This
# is why the 124 definitions converted before this key existed regenerate byte-identically.
#
# The range is CONTIGUOUS and verbatim, from the first top-level statement to the last one before the
# statement that contains the row loop, rather than a hand-picked subset: the secondary filters are
# interleaved with the primary one in source order (Management/AutomationAccounts declares its
# runbooks set FIRST), and several collectors compute an intermediate the secondary sets depend on.
$SetupPreamble  = ''
$SetupVariables = [System.Collections.Generic.List[string]]::new()
if (@($SecondaryFilterVars).Count -gt 0) {
    $SetupStatements = @($Blocks.Processing.Statements | Where-Object { $_.Extent.StartOffset -lt $RowLoopOwner.Extent.StartOffset })
    if (@($SetupStatements).Count -gt 0) {
        $SetupPreamble = $Ast.Extent.Text.Substring(
            $SetupStatements[0].Extent.StartOffset,
            $SetupStatements[-1].Extent.EndOffset - $SetupStatements[0].Extent.StartOffset)

        # Every name assigned anywhere in that range, including inside an `if` block --
        # Compute/AVDAzureLocal builds its combined set across four of them. `if` does not open a
        # scope in PowerShell, so those assignments are locals of the setup script just the same.
        foreach ($Statement in $SetupStatements) {
            foreach ($Assign in $Statement.FindAll({
                param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                          $n.Left -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true)) {
                # An assignment inside a `Where-Object {...}` or `ForEach-Object {...}` body is a
                # local of THAT scriptblock, not of the setup scope, and declaring it would make the
                # interpreter's "SetupPreamble never assigned this" check throw on a healthy
                # definition.
                $InScriptBlock = $false
                $Parent = $Assign.Parent
                while ($null -ne $Parent -and $Parent -ne $Statement) {
                    if ($Parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $InScriptBlock = $true; break }
                    $Parent = $Parent.Parent
                }
                if ($InScriptBlock) { continue }

                $AssignedName = $Assign.Left.VariablePath.UserPath
                if ($SetupVariables -notcontains $AssignedName) { [void]$SetupVariables.Add($AssignedName) }
            }
        }
    }
}

# Join detection itself lives in Invoke-CollectorAudit.ps1 (AB#5658). A CrossResourceJoin against a
# set derived from $Resources is expressible (it becomes the setup section above); a join against a
# LIVE call is not, and the audit's LiveCmdletCall reason is what still disqualifies a collector.

# --- Row expansion: the nest of foreach loops from the resource down to the tag loop -------------
#
# A collector's row loop is a chain: setup statements, then (0..n) fan-out loops, then the tag loop.
# Each LEVEL of that chain has its own setup statements, and every level's must be preserved:
#
#     foreach ($1 in $VirtualNetwork) {         <- row loop
#         $data = $1.PROPERTIES ...             <- Preamble
#         foreach ($2 in $data.subnets) {       <- AdditionalRowLoops[0]
#             $ConsumedIPs = ... ; $Prefix = ...    <- AdditionalRowLoops[0].Preamble
#             foreach ($Tag in $Tags) { $obj = @{...} }
#         }
#     }
#
# The first version of this extraction walked the loops with FindAll and captured only the ROW
# level's preamble, so every local computed inside a fan-out loop was silently dropped:
# Security/Vault.ps1 lost all three of its permission strings, Networking/NATGateway.ps1 lost its
# public IP columns, and Networking/VirtualNetwork.ps1 lost the subnet prefix arithmetic entirely.
# The descent is therefore structural and per level, not a flat search.
$FileText = $Ast.Extent.Text

function Get-StatementRangeText {
    param([System.Management.Automation.Language.Ast[]]$Statements, [string]$Text)
    if (@($Statements).Count -eq 0) { return '' }
    $Start = $Statements[0].Extent.StartOffset
    $End   = $Statements[-1].Extent.EndOffset
    return $Text.Substring($Start, $End - $Start)
}

function Test-ContainsObjAssignment {
    param([System.Management.Automation.Language.Ast]$Node)
    return @($Node.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Left.VariablePath.UserPath -ieq 'obj'
    }, $true)).Count -gt 0
}

function Get-RowExpansion {
    <#
        Split one loop body into its own setup statements plus, if it fans out further, the nested
        loop chain below it. The descent terminates where `$obj = @{ ... }` is a statement of THIS
        body -- i.e. at the level that actually emits rows -- rather than at a loop variable named
        'Tag'. Two reasons that distinction matters:

          * `Networking/RouteTables.ps1` calls its tag variable `$TagKey`, so a name test mistook
            the tag loop for another fan-out level and then failed to find a loop below it.
          * 25 collectors (all 15 convertible Identity ones, 9 Management ones, Monitor/Outages)
            have NO tag loop whatsoever -- one row per resource. A descent that requires a tag loop
            rejects every one of them, which is why they were the single largest block of
            "shape is not recognised" failures.

        Candidate loops are additionally required to CONTAIN the `$obj` assignment, which excludes
        the retirement fold's `foreach ($Retire in $Retired)` structurally instead of by name.
    #>
    param(
        [System.Management.Automation.Language.StatementBlockAst]$Body,
        [string]$Text,
        [string]$Where
    )

    $ObjHere = @($Body.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $_.Left.VariablePath.UserPath -ieq 'obj'
    })
    if (@($ObjHere).Count -gt 0) {
        $Preamble = Get-StatementRangeText -Statements @($Body.Statements | Where-Object { $_.Extent.StartOffset -lt $ObjHere[0].Extent.StartOffset }) -Text $Text
        return [PSCustomObject]@{ Preamble = $Preamble; Loops = @(); RowCondition = $null; ConditionalFieldIf = $null }
    }

    $Candidates = @($Body.Statements |
        Where-Object { $_ -is [System.Management.Automation.Language.ForEachStatementAst] } |
        Where-Object { Test-ContainsObjAssignment -Node $_ })
    if (@($Candidates).Count -eq 0) {
        # Two deliberately narrow conditional shapes are declarative too:
        #
        # * a guard with no else (AdvisorScore): it suppresses all rows for a resource, but the
        #   nested loop and fields are otherwise ordinary; and
        # * two branches with the same loop topology (PublicIP): only individual field values
        #   differ. Those values are merged below into `if (...) { ... } else { ... }` field
        #   expressions. Different loop depth is NOT accepted -- that changes row cardinality and
        #   needs a richer, separately designed schema.
        $Conditional = @($Body.Statements |
            Where-Object { $_ -is [System.Management.Automation.Language.IfStatementAst] } |
            Where-Object { Test-ContainsObjAssignment -Node $_ })
        if (@($Conditional).Count -ne 1) {
            throw "$Where -- no row-emitting ``foreach`` or ```$obj`` assignment at this level; this collector's shape is not recognised."
        }

        $If = $Conditional[0]
        if (@($If.Clauses).Count -ne 1) {
            throw "$Where -- a conditional row shape has more than one condition; this collector needs manual conversion."
        }
        $Before = Get-StatementRangeText -Statements @($Body.Statements | Where-Object { $_.Extent.StartOffset -lt $If.Extent.StartOffset }) -Text $Text
        $Then = Get-RowExpansion -Body $If.Clauses[0].Item2 -Text $Text -Where $Where
        if (-not $If.ElseClause) {
            $Condition = $If.Clauses[0].Item1.Extent.Text.Trim()
            if ($Then.RowCondition) { $Condition = "($Condition) -and ($($Then.RowCondition))" }
            return [PSCustomObject]@{
                Preamble = (@($Before, $Then.Preamble) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
                Loops = @($Then.Loops)
                RowCondition = $Condition
                ConditionalFieldIf = $Then.ConditionalFieldIf
            }
        }

        $Else = Get-RowExpansion -Body $If.ElseClause -Text $Text -Where $Where
        $SamePreamble = $Then.Preamble.Trim() -eq $Else.Preamble.Trim()
        $SameCondition = [string]$Then.RowCondition -eq [string]$Else.RowCondition
        $SameLoops = (ConvertTo-Json -InputObject @($Then.Loops) -Depth 8 -Compress) -eq (ConvertTo-Json -InputObject @($Else.Loops) -Depth 8 -Compress)
        if (-not ($SamePreamble -and $SameCondition -and $SameLoops)) {
            throw "$Where -- conditional branches have different row-loop topology or setup; this collector needs manual conversion."
        }
        return [PSCustomObject]@{
            Preamble = (@($Before, $Then.Preamble) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
            Loops = @($Then.Loops)
            RowCondition = $Then.RowCondition
            ConditionalFieldIf = $If
        }
    }
    $BoundaryLoop = $Candidates[-1]
    $Preamble = Get-StatementRangeText -Statements @($Body.Statements | Where-Object { $_.Extent.StartOffset -lt $BoundaryLoop.Extent.StartOffset }) -Text $Text

    $SourceExprNode = Get-InnerExpr -Node $BoundaryLoop.Condition
    $SourceRef = if ($SourceExprNode -is [System.Management.Automation.Language.VariableExpressionAst]) {
        '$' + $SourceExprNode.VariablePath.UserPath
    } else {
        $BoundaryLoop.Condition.Extent.Text
    }

    $Inner = Get-RowExpansion -Body $BoundaryLoop.Body -Text $Text -Where $Where
    $Loop = [ordered]@{
        Variable = $BoundaryLoop.Variable.VariablePath.UserPath
        Source   = $SourceRef
        Preamble = $Inner.Preamble
    }
    return [PSCustomObject]@{
        Preamble = $Preamble
        Loops = @(@($Loop) + @($Inner.Loops))
        RowCondition = $Inner.RowCondition
        ConditionalFieldIf = $Inner.ConditionalFieldIf
    }
}

$Expansion = Get-RowExpansion -Body $RowLoop.Body -Text $FileText -Where $FullPath
$Preamble  = $Expansion.Preamble
if ($Name -eq 'PublicIP') {
    # An unattached public IP has `ipConfiguration = {}`. Preserve its legacy `$null` result
    # under v3 StrictMode rather than directly reading a missing `.id` property.
    $Preamble = $Preamble -replace '\$data\.ipConfiguration\.id', "(Get-AZSCSafeProperty -InputObject `$data -Path 'ipConfiguration.id')"
    $Preamble = $Preamble -replace '\$data\.natGateway\.id', "(Get-AZSCSafeProperty -InputObject `$data -Path 'natGateway.id')"
}
$AllLoops  = @($Expansion.Loops)
$RowCondition = $Expansion.RowCondition

# The INNERMOST loop is the tag loop when it iterates $Tags -- recorded as its own key rather than
# left implicit, because it is not universal (25 collectors have none) and not always called 'Tag'
# (RouteTables uses $TagKey). Every loop above it is a genuine per-resource fan-out.
$TagLoop = $null
if (@($AllLoops).Count -gt 0 -and $AllLoops[-1].Source -match '^\$Tags$') {
    $TagLoop  = $AllLoops[-1]
    $AllLoops = @($AllLoops | Select-Object -SkipLast 1)
}

$AdditionalRowLoops = [System.Collections.Generic.List[object]]::new()
foreach ($Loop in @($AllLoops)) { [void]$AdditionalRowLoops.Add($Loop) }

# --- Fields (verbatim expression text from the $obj = @{...} hashtable) -------------------------

$ObjAssignments = $RowLoop.Body.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $n.Left.VariablePath.UserPath -ieq 'obj'
}, $true)
if (@($ObjAssignments).Count -eq 0) { throw "$FullPath -- no `$obj = @{...}` hashtable literal found." }

function Get-ObjectFields {
    param([System.Management.Automation.Language.AssignmentStatementAst]$Assignment)
    $HashtableNode = Get-InnerExpr -Node $Assignment.Right
    if ($HashtableNode -isnot [System.Management.Automation.Language.HashtableAst]) { throw "$FullPath -- `$obj`'s right-hand side is not a plain hashtable literal; this collector needs manual conversion." }
    $Result = [ordered]@{}
    foreach ($Pair in $HashtableNode.KeyValuePairs) {
        if ($Pair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $Result[$Pair.Item1.Value] = $Pair.Item2.Extent.Text.Trim()
        }
    }
    return $Result
}

function ConvertTo-StrictSafeCollectorText {
    param([AllowNull()][string]$Text)
    if ($Name -ne 'PublicIP' -or [string]::IsNullOrEmpty($Text)) { return $Text }
    $Safe = $Text -replace '\$data\.ipConfiguration\.id', "(Get-AZSCSafeProperty -InputObject `$data -Path 'ipConfiguration.id')"
    return $Safe -replace '\$data\.natGateway\.id', "(Get-AZSCSafeProperty -InputObject `$data -Path 'natGateway.id')"
}

$FirstObj = $ObjAssignments[0]
$FirstFields = Get-ObjectFields -Assignment $FirstObj
$Fields = [System.Collections.Generic.List[hashtable]]::new()
if ($Expansion.ConditionalFieldIf) {
    $If = $Expansion.ConditionalFieldIf
    $ThenObjects = @($If.Clauses[0].Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq 'obj' }, $true))
    $ElseObjects = @($If.ElseClause.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq 'obj' }, $true))
    if ($ThenObjects.Count -ne 1 -or $ElseObjects.Count -ne 1) { throw "$FullPath -- conditional row branches must each contain exactly one `$obj` literal; this collector needs manual conversion." }
    $ThenFields = Get-ObjectFields -Assignment $ThenObjects[0]
    $ElseFields = Get-ObjectFields -Assignment $ElseObjects[0]
    if ((@($ThenFields.Keys) -join "`0") -ne (@($ElseFields.Keys) -join "`0")) { throw "$FullPath -- conditional row branches declare different fields; this collector needs manual conversion." }
    $Condition = $If.Clauses[0].Item1.Extent.Text.Trim()
    foreach ($FieldName in $ThenFields.Keys) {
        $ThenExpression = $ThenFields[$FieldName]
        $ElseExpression = $ElseFields[$FieldName]
        $Expression = if ($ThenExpression -eq $ElseExpression) { $ThenExpression } else { "if ($Condition) { $ThenExpression } else { $ElseExpression }" }
        $Expression = ConvertTo-StrictSafeCollectorText -Text $Expression
        [void]$Fields.Add(@{ Name = $FieldName; Expression = $Expression })
    }
} else {
    foreach ($FieldName in $FirstFields.Keys) { [void]$Fields.Add(@{ Name = $FieldName; Expression = (ConvertTo-StrictSafeCollectorText -Text $FirstFields[$FieldName]) }) }
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
    # NOT defaulted to the two standard names when the original adds neither. 10 of the Monitor
    # collectors (ActivityLogAlertRules, AutoscaleSettings, MonitorWorkbooks, ...) PROCESS Tag Name /
    # Tag Value but never export them -- their Reporting branch has no `if ($InTag)` block at all.
    # Assuming the default added two columns to those sheets under -IncludeTags that no shipped
    # release has ever contained.
    $Report.TagColumns = @($AllColumns | Where-Object { $_ -in @('Tag Name', 'Tag Value') })

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
    ResourceTypes        = @($ResourceTypes)
    ResourceTypeMatching = $ResourceTypeMatching
    AdditionalFilter    = $AdditionalFilterText
    FilterPreamble      = $FilterPreamble
    RowLoopVariable     = $RowLoopVarName
    SetupPreamble       = $SetupPreamble
    SetupVariables      = @($SetupVariables)
    Preamble            = $Preamble
    RowCondition        = $RowCondition
    AdditionalRowLoops  = @($AdditionalRowLoops | ForEach-Object { [ordered]@{ Variable = $_.Variable; Source = $_.Source; Preamble = $_.Preamble } })
    TagLoop             = if ($TagLoop) { [ordered]@{ Variable = $TagLoop.Variable; Source = $TagLoop.Source; Preamble = $TagLoop.Preamble } } else { $null }
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

# Omit the key entirely for ordinary direct-resource collectors so their generated definitions
# remain byte-identical.  Insert it beside RowLoopVariable only for the envelope-fan-out shape.
if ($RowSourceExpression) {
    $RowLoopIndex = [array]::IndexOf([object[]]@($Definition.Keys), 'RowLoopVariable')
    $Definition.Insert($RowLoopIndex + 1, 'RowSource', [ordered]@{ Expression = $RowSourceExpression })
}

$Psd1Text = "@{`n" + (($Definition.GetEnumerator() | ForEach-Object {
    if ($_.Key -eq 'FilterPreamble' -and -not [string]::IsNullOrWhiteSpace($_.Value)) {
        "    FilterPreamble = @'`n$($_.Value)`n'@"
    } elseif ($_.Key -eq 'SetupPreamble' -and -not [string]::IsNullOrWhiteSpace($_.Value)) {
        "    SetupPreamble = @'`n$($_.Value)`n'@"
    } elseif ($_.Key -eq 'SetupPreamble') {
        # Omitted entirely rather than written as '': the loader treats an empty SetupPreamble with
        # a non-empty SetupVariables as an error, and a pair of always-empty keys on 124 files is
        # noise that hides the 15 where the section is load-bearing.
        $null
    } elseif ($_.Key -eq 'SetupVariables' -and @($_.Value).Count -eq 0) {
        $null
    } elseif ($_.Key -eq 'RowCondition' -and [string]::IsNullOrWhiteSpace($_.Value)) {
        # Preserve byte-for-byte regeneration for the existing, unconditional definitions. A row
        # condition is emitted only for the narrow guard shape this converter recognises.
        $null
    } elseif ($_.Key -eq 'Preamble') {
        # A here-string, not ConvertTo-Psd1Literal's normal single-quoted escaping -- preamble
        # source commonly contains its own single AND double quotes, and a here-string needs no
        # escaping of either.
        "    Preamble = @'`n$($_.Value)`n'@"
    } else {
        "    $($_.Key) = $(ConvertTo-Psd1Literal -Value $_.Value -Indent 1)"
    }
} | Where-Object { $null -ne $_ }) -join "`n`n") + "`n}`n"

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
