#Requires -Version 7.0
<#
.SYNOPSIS
    Classify every inventory collector under Modules/Public/InventoryModules by AST shape (AB#5658).

.DESCRIPTION
    The first step of the declarative-collector rebuild (AB#5656, Epic AB#5638) needs a factual
    answer to "how many of the 176 collectors are pure data-shaping, and what specifically makes
    the rest not that" — before any schema gets designed. This script answers it by parsing every
    collector with the PowerShell AST (`[System.Management.Automation.Language.Parser]::ParseFile`),
    never by regex-matching source text, so the classification cannot be fooled by comments,
    string literals, or reformatted whitespace.

    Discovery reuses `src/pipeline/Get-ScoutCollector.ps1` — the single discovery implementation
    the deterministic-pipeline work (AB#5649) established — rather than re-walking the filesystem,
    per the epic's explicit instruction not to grow a second copy of collector discovery.

    For each collector this records:

      * the Azure resource type(s) its Processing branch filters `$Resources` by
      * the field names of the row it builds (from the near-universal `$obj = @{ ... }`
        hashtable-literal convention — 175 of 176 files use it) and the ordered Excel export
        column list (from the `$Exc.Add('...')` calls in its Reporting branch)
      * whether it correlates against `$Sub` (subscription name lookup) and/or
        `$Retirements`/`$Unsupported` (retirement cross-reference) — both are treated as
        STANDARD PRIMITIVES because they are near-universal, not as escape-hatch triggers
      * whether it filters `$Resources` by MORE THAN ONE resource type and then correlates
        between those sets inside its per-row loop — a genuine cross-resource JOIN
      * whether it calls any cmdlet that reaches out to Azure/Graph itself (`Get-Az*`,
        `Invoke-Az*`, `Invoke-RestMethod`, `Invoke-WebRequest`, `Get-Msol*`, `Get-Mg*`,
        `Invoke-Mg*`) instead of shaping the `$Resources` array it was handed

    A collector is classified EscapeHatch when it has a cross-resource join, a live cmdlet call,
    or (for the two Identity files) is written against an API that was never implemented — and
    PureShaping otherwise.

.PARAMETER InventoryRoot
    Path to the InventoryModules directory. Defaults to the repo's own.

.PARAMETER OutputJson
    Where to write the machine-readable audit. Defaults to tests/fixtures/collector-audit.json.

.OUTPUTS
    PSCustomObject per collector, and (as a side effect) the JSON fixture file.

.NOTES
    Tracks ADO AB#5658 (Feature AB#5656, Epic AB#5638). Read-only — it does not modify any
    collector, and it does not run any of them.
#>
[CmdletBinding()]
param(
    [string]$InventoryRoot = (Join-Path $PSScriptRoot '..\Modules\Public\InventoryModules'),
    [string]$OutputJson = (Join-Path $PSScriptRoot '..\tests\fixtures\collector-audit.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\src\pipeline\Get-ScoutCollector.ps1')

# --- AST helpers -----------------------------------------------------------------------------

function Get-InnerExpression {
    <#
        Peel a bare expression (assignment right-hand side, if-condition) out of the wrapper AST
        nodes the parser puts around it. `$x = @{...}` and `if ($Task -eq 'Processing')` both
        parse their expression as a one-element PipelineAst containing a CommandExpressionAst,
        not as the bare HashtableAst/BinaryExpressionAst directly -- every extractor in this
        script needs the unwrapped node, so it is centralised here rather than re-derived per call
        site.
    #>
    param([System.Management.Automation.Language.Ast]$Node)

    $Current = $Node
    while ($true) {
        if ($Current -is [System.Management.Automation.Language.PipelineAst] -and $Current.PipelineElements.Count -eq 1) {
            $Current = $Current.PipelineElements[0]
            continue
        }
        if ($Current -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Current = $Current.Expression
            continue
        }
        break
    }
    return $Current
}

function Test-AzScoutTaskBranch {
    <#
        True when $Node is the `If ($Task -eq '<Value>')` statement's clause condition — the
        gate every one of the 174 Standard collectors uses to switch between Processing and
        Reporting. Matched structurally (BinaryExpressionAst over a $Task variable read and a
        string constant), not by source text, so casing/spacing/brace-placement never matters.
    #>
    param(
        [System.Management.Automation.Language.ExpressionAst]$Node,
        [string]$Value
    )
    if ($Node -isnot [System.Management.Automation.Language.BinaryExpressionAst]) { return $false }
    if ($Node.Operator -notin @('Ieq', 'Ceq', 'Eq')) { return $false }
    $Left  = $Node.Left
    $Right = $Node.Right
    $IsTaskVar = { param($E) $E -is [System.Management.Automation.Language.VariableExpressionAst] -and $E.VariablePath.UserPath -ieq 'Task' }
    $IsValue   = { param($E) $E -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $E.Value -ieq $Value }
    return ((& $IsTaskVar $Left) -and (& $IsValue $Right)) -or ((& $IsTaskVar $Right) -and (& $IsValue $Left))
}

function Get-ProcessingBlock {
    <# The StatementBlockAst body of the `$Task -eq 'Processing'` clause, or $null. #>
    param([System.Management.Automation.Language.Ast]$Ast)

    $IfStatements = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true)
    foreach ($If in $IfStatements) {
        foreach ($Clause in $If.Clauses) {
            # $Clause is a Tuple<PipelineBaseAst, StatementBlockAst>
            $CondExpr = Get-InnerExpression -Node $Clause.Item1
            if (Test-AzScoutTaskBranch -Node $CondExpr -Value 'Processing') {
                return $Clause.Item2
            }
        }
    }
    return $null
}

function Get-ResourceTypeFilters {
    <#
        Every `$Var = $Resources | Where-Object { ... $_.TYPE ... }` assignment in the block, as
        an ordered map of variable name -> the resource-type string constant(s) it filters on.
        Order of first appearance is preserved because the first such variable is, in every
        collector inspected, the one the per-row loop iterates.
    #>
    param([System.Management.Automation.Language.Ast]$Block)

    $Result = [ordered]@{}
    if (-not $Block) { return $Result }

    $Assignments = $Block.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
    foreach ($Assign in $Assignments) {
        if ($Assign.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        $VarName = $Assign.Left.VariablePath.UserPath

        $Rhs = $Assign.Right
        if ($Rhs -is [System.Management.Automation.Language.PipelineAst]) {
            $Elements = $Rhs.PipelineElements
        } elseif ($Rhs -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Elements = @($Rhs)
        } else { continue }

        if ($Elements.Count -lt 2) { continue }
        $Source = $Elements[0]
        $SourceExpr = if ($Source -is [System.Management.Automation.Language.CommandExpressionAst]) { $Source.Expression } else { $null }
        $IsResourcesVar = $SourceExpr -is [System.Management.Automation.Language.VariableExpressionAst] -and $SourceExpr.VariablePath.UserPath -ieq 'Resources'
        if (-not $IsResourcesVar) { continue }

        $WhereCmd = $Elements | Where-Object {
            $_ -is [System.Management.Automation.Language.CommandAst] -and $_.GetCommandName() -ieq 'Where-Object'
        } | Select-Object -First 1
        if (-not $WhereCmd) { continue }

        # Pull every string constant compared against a `$_.TYPE`/`$_.Type` member read inside
        # the filter script block — covers `-eq`, `-ieq`, `-in @(...)`, `-contains`.
        $ScriptBlockParam = $WhereCmd.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } | Select-Object -First 1
        $TypeValues = @()
        if ($ScriptBlockParam) {
            # Every .FindAll() result is force-wrapped in @() before .Count: it returns a lazy
            # IEnumerable, not a concrete collection, and an empty one is not guaranteed to carry
            # an intrinsic Count property under StrictMode -- the exact "empty collection is not
            # a value" trap this repo's own engine rebuild exists to remove (AB#5629/5633/5653).
            $MemberReads = @($ScriptBlockParam.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.MemberExpressionAst] -and
                $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Expression.VariablePath.UserPath -eq '_' -and
                $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $n.Member.Value -ieq 'TYPE'
            }, $true))
            if ($MemberReads.Count -gt 0) {
                $Strings = @($ScriptBlockParam.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
                $TypeValues = @($Strings | Where-Object { $_.Value -match '^[a-z0-9.]+/[a-z0-9./]+$' } | ForEach-Object { $_.Value } | Select-Object -Unique)
            }
        }

        if (@($TypeValues).Count -gt 0) {
            # Databases/RedisCache.ps1 (and others) build one variable across TWO statements --
            # `$RedisCache = @(); $RedisCache += ... 'microsoft.cache/redis'; $RedisCache +=
            # ... 'microsoft.cache/redisenterprise'` -- a union of two resource types into ONE
            # row loop, not a join. First-wins would silently drop the second type from the
            # result. Union them under the same key instead.
            #
            # Deliberately NOT `$Result[$VarName] = if (...) { @($Result[$VarName] + ...) }` --
            # reading and reassigning the same dictionary-indexer expression inside one
            # statement collapsed the two-element array into a single concatenated string in
            # testing. Reading the prior value into a plain variable first avoids it.
            $Existing = if ($Result.Contains($VarName)) { $Result[$VarName] } else { $null }
            $Result[$VarName] = if ($Existing) {
                @(@($Existing) + @($TypeValues) | Select-Object -Unique)
            } else {
                $TypeValues
            }
        }
    }
    return $Result
}

function Get-HashtableFieldNames {
    <# Ordered, de-duplicated key list of every `$obj = @{ 'Key' = ...; ... }` literal in the block. #>
    param([System.Management.Automation.Language.Ast]$Block)

    $Names = [System.Collections.Specialized.OrderedDictionary]::new()
    if (-not $Block) { return @() }

    $Assignments = $Block.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Left.VariablePath.UserPath -ieq 'obj'
    }, $true)

    foreach ($Assign in $Assignments) {
        # The parser wraps `$obj = @{...}`'s right-hand side in a one-element PipelineAst holding
        # a CommandExpressionAst, not a bare HashtableAst -- Get-InnerExpression peels both off.
        $Rhs = Get-InnerExpression -Node $Assign.Right
        $Hashtable = if ($Rhs -is [System.Management.Automation.Language.HashtableAst]) { $Rhs }
                     elseif ($Rhs -is [System.Management.Automation.Language.ConvertExpressionAst] -and $Rhs.Child -is [System.Management.Automation.Language.HashtableAst]) { $Rhs.Child }
                     else { $null }
        if (-not $Hashtable) { continue }
        foreach ($Pair in $Hashtable.KeyValuePairs) {
            $Key = $Pair.Item1
            if ($Key -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                if (-not $Names.Contains($Key.Value)) { $Names.Add($Key.Value, $true) }
            }
        }
    }
    return @($Names.Keys)
}

function Get-ExportColumns {
    <#
        Ordered `$Exc.Add('Column')` list from the Reporting branch (`$Task -ne 'Processing'`).
        `.Add(...)` is a method call, not a command invocation, so the parser represents it as
        an InvokeMemberExpressionAst -- matching CommandAst here (an earlier draft's mistake)
        matches nothing, since no such node exists in the file.
    #>
    param([System.Management.Automation.Language.Ast]$Ast)

    $Adds = $Ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Expression.VariablePath.UserPath -ieq 'Exc' -and
        $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $n.Member.Value -ieq 'Add'
    }, $true)

    # @() wraps the FOREACH EXPRESSION ITSELF, not its result: `$x = foreach(){}; @($x)` turns a
    # true zero-match foreach (which assigns $null) into a one-element array holding that $null,
    # not an empty array -- the same "$null is not an empty collection" trap documented across
    # this repo's own StrictMode history.
    $Columns = @(foreach ($Add in $Adds) {
        if (@($Add.Arguments).Count -gt 0 -and $Add.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $Add.Arguments[0].Value
        }
    })
    return $Columns
}

function Get-ExternalCalls {
    <#
        Cmdlets in the block that reach Azure/Graph themselves rather than shaping the
        $Resources array the collector was handed. Write-AZSCLog and the ImportExcel/collection
        cmdlets (Where-Object, ForEach-Object, Select-Object, New-Object, Get-Date, Measure-Object,
        Export-Excel, New-ExcelStyle, New-ConditionalText) are the declarative vocabulary and are
        excluded deliberately.
    #>
    param([System.Management.Automation.Language.Ast]$Block)

    if (-not $Block) { return @() }
    $Pattern = '^(Get-Az(?!ureADServicePrincipal$)|Invoke-Az|New-Az|Set-Az|Connect-Az|Invoke-RestMethod$|Invoke-WebRequest$|Get-Msol|Get-Mg|Invoke-Mg)'
    $Commands = $Block.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    $Names = @(foreach ($Cmd in $Commands) {
        $Name = $Cmd.GetCommandName()
        if ($Name -and $Name -match $Pattern) { $Name }
    })
    return @($Names | Select-Object -Unique)
}

function Get-RowLoop {
    <#
        The ForEachStatementAst that builds one row per iteration -- identified as the (usually
        outermost) foreach whose body contains the `$obj = @{...}` assignment. Its own iteration
        variable is NOT necessarily the first resource-type filter declared in the file: e.g.
        Management/AutomationAccounts.ps1 filters `$runbook` before `$autacc` but its row loop is
        `foreach ($0 in $autacc)`, correlating back to `$runbook` inside the loop -- a join found
        only by asking which variable the loop actually iterates, never by declaration order.
    #>
    param([System.Management.Automation.Language.Ast]$Block)

    if (-not $Block) { return $null }
    $ForEachLoops = @($Block.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true))
    return $ForEachLoops | Where-Object {
        @($_.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq 'obj' }, $true)).Count -gt 0
    } | Select-Object -First 1
}

function Get-RowLoopSourceVariableName {
    <# The variable name a row loop iterates over, e.g. 'autacc' for `foreach ($0 in $autacc)`. #>
    param([System.Management.Automation.Language.ForEachStatementAst]$RowLoop)

    if (-not $RowLoop) { return $null }
    $Source = Get-InnerExpression -Node $RowLoop.Condition
    if ($Source -is [System.Management.Automation.Language.VariableExpressionAst]) { return $Source.VariablePath.UserPath }
    return $null
}

function Test-RowLoopReferencesVariable {
    <# True when $VarName is read anywhere inside the given per-row loop body (a real join/correlation, not an unused filter). #>
    param([System.Management.Automation.Language.ForEachStatementAst]$RowLoop, [string]$VarName)

    if (-not $RowLoop) { return $false }
    $Reads = @($RowLoop.Body.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -ieq $VarName
    }, $true))
    return $Reads.Count -gt 0
}

# --- Per-collector audit ------------------------------------------------------------------------

function Get-CollectorAuditRecord {
    param([PSCustomObject]$Collector)

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Collector.Path, [ref]$Tokens, [ref]$ParseErrors)

    $Record = [ordered]@{
        Name                    = $Collector.Name
        Category                = $Collector.FolderCategory
        Path                    = ($Collector.Path -replace [regex]::Escape((Resolve-Path (Join-Path $PSScriptRoot '..')).Path + '\'), '').Replace('\', '/')
        Contract                = $Collector.Contract
        ParseErrorCount         = @($ParseErrors).Count
        ResourceTypes           = @()
        ResourceTypeFilterCount = 0
        HasCompoundFilter       = $false
        ProcessingFields        = @()
        ProcessingFieldCount    = 0
        ExportColumns           = @()
        ExportColumnCount       = 0
        UsesSubCorrelation      = $false
        UsesRetirementLookup    = $false
        CrossResourceJoin       = $false
        JoinedResourceTypes     = @()
        ExternalCalls           = @()
        Classification          = 'PureShaping'
        EscapeHatchReasons      = @()
    }

    if ($Collector.Contract -eq 'Unsupported') {
        # Identity/IdentityProviders and Identity/SecurityDefaults — written against
        # Register-AZSCInventoryModule / Get-AZSCProcessedData / $Context.EntraData, an API
        # that exists only as a mock in tests/Identity.Module.Tests.ps1 (see Get-ScoutCollector.ps1
        # and docs/design/decisions/deterministic-pipeline.md §5.3). Never produced a row.
        $Record.Classification = 'EscapeHatch'
        $Record.EscapeHatchReasons = @('UnimplementedContract: written against Register-AZSCInventoryModule/$Context.EntraData, which the module never implements')
        $RecordFields = @($Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $n.Left.VariablePath.UserPath -ieq 'Record'
        }, $true))
        if ($RecordFields.Count -gt 0) {
            # `[PSCustomObject][ordered]@{...}` is TWO stacked casts around the hashtable
            # literal -- peel ConvertExpressionAst.Child repeatedly (not just once) until the
            # HashtableAst itself is reached.
            $Rhs = Get-InnerExpression -Node $RecordFields[0].Right
            while ($Rhs -is [System.Management.Automation.Language.ConvertExpressionAst]) { $Rhs = $Rhs.Child }
            if ($Rhs -is [System.Management.Automation.Language.HashtableAst]) {
                $Record.ProcessingFields = @($Rhs.KeyValuePairs | ForEach-Object {
                    if ($_.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Item1.Value }
                })
                $Record.ProcessingFieldCount = @($Record.ProcessingFields).Count
            }
        }
        return [PSCustomObject]$Record
    }

    $ProcessingBlock = Get-ProcessingBlock -Ast $Ast

    $ResourceFilters = Get-ResourceTypeFilters -Block $ProcessingBlock
    $Record.ResourceTypeFilterCount = $ResourceFilters.Count
    $Record.ResourceTypes = @($ResourceFilters.Values | ForEach-Object { $_ } | Select-Object -Unique)
    $Record.HasCompoundFilter = @($ResourceFilters.Values | Where-Object { @($_).Count -gt 1 }).Count -gt 0

    # Every call site that stores a possibly-empty function result wraps the CALL ITSELF in
    # @() -- `$x = Get-Foo` collapses a true zero-item result to $null (function output, like
    # any pipeline, flattens empty arrays away), and @() only recovers an empty array when it
    # wraps the point where the objects are produced, not a $null read back out of $x afterwards.
    $Record.ProcessingFields = @(Get-HashtableFieldNames -Block $ProcessingBlock)
    $Record.ProcessingFieldCount = @($Record.ProcessingFields).Count

    $Record.ExportColumns = @(Get-ExportColumns -Ast $Ast)
    $Record.ExportColumnCount = @($Record.ExportColumns).Count

    $Record.UsesSubCorrelation = ($ProcessingBlock -and @($ProcessingBlock.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -ieq 'Sub'
    }, $true)).Count -gt 0)

    $Record.UsesRetirementLookup = ($ProcessingBlock -and @($ProcessingBlock.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -in @('Retirements', 'Unsupported')
    }, $true)).Count -gt 0)

    $Record.ExternalCalls = @(Get-ExternalCalls -Block $ProcessingBlock)

    # A cross-resource join is more than one distinct resource-type filter variable, where a
    # variable OTHER than the one the per-row loop actually iterates is read inside that loop --
    # i.e. genuinely correlated, not merely computed and left unused. The row-loop variable is
    # found structurally (which filter variable does `foreach (...)` with the $obj assignment
    # iterate?), not assumed to be the first one declared -- declaration order and loop order
    # disagree in at least one file (Management/AutomationAccounts.ps1).
    $VarNames = @($ResourceFilters.Keys)
    if ($VarNames.Count -gt 1 -and $ProcessingBlock) {
        $RowLoop = Get-RowLoop -Block $ProcessingBlock
        $RowLoopVar = Get-RowLoopSourceVariableName -RowLoop $RowLoop
        $Secondary = $VarNames | Where-Object { $_ -ne $RowLoopVar }
        $Joined = @($Secondary | Where-Object { Test-RowLoopReferencesVariable -RowLoop $RowLoop -VarName $_ })
        if ($Joined.Count -gt 0) {
            $Record.CrossResourceJoin = $true
            $Record.JoinedResourceTypes = @($Joined | ForEach-Object { $ResourceFilters[$_] } | ForEach-Object { $_ })
        }
        elseif ($RowLoopVar -and $VarNames -notcontains $RowLoopVar) {
            # The row loop iterates a variable that is none of the declared resource-type
            # filters — e.g. Compute/AVDAzureLocal.ps1 unions $arcAvd + $hciAvd + a synthesized
            # set into $combined before looping over $combined. Still more than one Azure
            # resource type feeding a single row shape, just combined ahead of the loop instead
            # of correlated inside it — the same escape hatch by another route.
            $Record.CrossResourceJoin = $true
            $Record.JoinedResourceTypes = @($ResourceFilters.Values | ForEach-Object { $_ })
        }
    }

    $Reasons = @()
    if ($Record.CrossResourceJoin) {
        $Reasons += "CrossResourceJoin: correlates against $($Record.JoinedResourceTypes -join ', ') inside the per-row loop"
    }
    if (@($Record.ExternalCalls).Count -gt 0) {
        $Reasons += "LiveCmdletCall: $($Record.ExternalCalls -join ', ')"
    }
    if ($Record.ResourceTypeFilterCount -eq 0) {
        $Reasons += 'NoResourcesFilter: the Processing branch does not filter $Resources by $_.TYPE at all (builds its row set another way)'
    }
    if (@($Reasons).Count -gt 0) {
        $Record.Classification = 'EscapeHatch'
        $Record.EscapeHatchReasons = $Reasons
    }

    return [PSCustomObject]$Record
}

# --- Run -----------------------------------------------------------------------------------------

$InventoryRoot = (Resolve-Path $InventoryRoot).Path
$Collectors = @(Get-ScoutCollector -InventoryRoot $InventoryRoot -Category 'All')

Write-Verbose "[CollectorAudit] $($Collectors.Count) collectors discovered under $InventoryRoot"

$Audit = @($Collectors | Sort-Object FolderCategory, Name | ForEach-Object { Get-CollectorAuditRecord -Collector $_ })

$OutputDir = Split-Path -Parent $OutputJson
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$Audit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputJson -Encoding utf8

$PureCount   = @($Audit | Where-Object { $_.Classification -eq 'PureShaping' }).Count
$EscapeCount = @($Audit | Where-Object { $_.Classification -eq 'EscapeHatch' }).Count

Write-Host "[CollectorAudit] $($Audit.Count) collectors audited: $PureCount PureShaping, $EscapeCount EscapeHatch"
Write-Host "[CollectorAudit] Wrote $OutputJson"

$Audit
