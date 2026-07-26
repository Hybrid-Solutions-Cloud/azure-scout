#Requires -Version 7.0
<#
.SYNOPSIS
    Derive the authoritative ARM resource-type list the 176 InventoryModules collectors
    filter `$Resources` by, straight from the AST -- not by grepping for a text pattern.

.DESCRIPTION
    Every one of the 176 `Modules/Public/InventoryModules/*/*.ps1` collectors is a pure
    function of the shared `$Resources` array: it filters that array down to the rows it
    cares about with `$_.TYPE -eq/-in/-like '<type>'` and shapes the matches. There was no
    single list of exactly which ARM types those 176 filters name -- which is what
    `src/collect/Invoke-Collect.ps1` (Task AB#5639/5641) needs in order to know how much of
    the legacy extraction surface its own query pack already reproduces.

    This walks the real PowerShell AST (System.Management.Automation.Language.Parser) of
    every collector file, looking for a `BinaryExpressionAst` whose left side reads the
    `TYPE` (or `KIND`) member off the pipeline variable (`$_`, or a `foreach` loop variable
    the file uses instead, e.g. `$1`) and whose operator is one of `-eq/-ieq/-ceq`,
    `-in/-iin/-cin`, `-like/-ilike/-clike`, or `-match/-imatch/-cmatch`. AST parsing (not
    regex over the source text) is deliberate: it survives multi-line `-in @(...)` arrays,
    ignores types that only appear inside comments, and does not get confused by string
    interpolation or a `-like`/`-match` wildcard/regex fragment that is not a literal type.

.PARAMETER InventoryRoot
    Path to the InventoryModules directory. Defaults to the repo's own copy.

.PARAMETER AsJson
    Emit the coverage report as JSON instead of the default table + summary text.

.OUTPUTS
    Without -AsJson: a summary count line plus a table of every distinct ARM type, how many
    collectors reference it, and which collector(s) do.
    With -AsJson: `[pscustomobject]@{ Type; CollectorCount; Collectors[] }[]`, sorted by
    Type, plus the `-like`/`-match` fragments recorded separately (they name a pattern, not
    a literal type, so they are not folded into the same coverage count).

.NOTES
    Tracks ADO AB#5639 (US 5640 / Task 5641, Epic AB#5638).

    A `-like`/`-match` right-hand side is reported as a *fragment*, not a type: e.g.
    `'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'`
    used with `-like` here happens to be a literal (no wildcard), but the AST walk cannot
    assume that in general -- a real wildcard/regex fragment could match many types Resource
    Graph would need `startswith()`/`matches regex` to reproduce, not `==`. Both are listed
    so a human reviewing coverage can judge each on its own but only `-eq`/`-in` literals are
    counted in the type/coverage totals: they are the only forms Invoke-Collect can safely
    translate as `type =~ "<value>"` in KQL.
#>
[CmdletBinding()]
param(
    [string] $InventoryRoot = (Join-Path $PSScriptRoot '..' 'Modules' 'Public' 'InventoryModules'),
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InventoryRoot = (Resolve-Path $InventoryRoot).Path

$eqOperators    = @('Ieq', 'Ceq', 'Eq')
$inOperators    = @('Iin', 'Cin', 'In')
$patternOperators = @('Ilike', 'Clike', 'Like', 'Imatch', 'Cmatch', 'Match')

# member names the collectors read off the pipeline row to decide what a resource is.
$typeMembers = @('TYPE', 'KIND')

$typeHits    = [ordered]@{}   # type value -> HashSet[collector name]
$patternHits = [System.Collections.Generic.List[object]]::new()

function Test-TypeMemberAccess {
    <#
    .SYNOPSIS
        True when $node is a MemberExpressionAst reading .TYPE/.KIND off *some* variable
        (the pipeline variable in every real case seen in this codebase: $_, or a foreach
        alias like $1/$vm).
    #>
    param($Node)
    if ($Node -isnot [System.Management.Automation.Language.MemberExpressionAst]) { return $false }
    if ($Node.Expression -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
    $memberName = if ($Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $Node.Member.Value } else { $null }
    return [bool]($memberName -and ($typeMembers -contains $memberName.ToUpperInvariant()))
}

function Get-StringLiterals {
    <#
    .SYNOPSIS
        Pull every string-constant literal out of an expression: a bare string for -eq, or
        every element of an array-literal for -in.
    #>
    param($Node)
    switch ($Node) {
        { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } { return , $_.Value }
        { $_ -is [System.Management.Automation.Language.ArrayLiteralAst] } {
            return @($_.Elements | ForEach-Object { Get-StringLiterals $_ } | Where-Object { $_ })
        }
        { $_ -is [System.Management.Automation.Language.ArrayExpressionAst] } {
            $inner = $_.SubExpression.Statements | ForEach-Object {
                if ($_ -is [System.Management.Automation.Language.PipelineAst]) {
                    $_.PipelineElements | ForEach-Object {
                        if ($_ -is [System.Management.Automation.Language.CommandExpressionAst]) { Get-StringLiterals $_.Expression }
                    }
                }
            }
            return @($inner | Where-Object { $_ })
        }
        default { return @() }
    }
}

$files = @(Get-ChildItem -LiteralPath $InventoryRoot -Recurse -Filter '*.ps1' -File | Sort-Object FullName)

foreach ($file in $files) {
    $collectorName = $file.BaseName
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $errors)
    if ($errors -and @($errors).Count -gt 0) {
        Write-Warning "Get-CollectorResourceTypeMap: '$($file.Name)' has $(@($errors).Count) parse error(s) -- skipping AST walk for this file."
        continue
    }

    $binaryOps = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)

    foreach ($bin in $binaryOps) {
        if (-not (Test-TypeMemberAccess $bin.Left)) { continue }
        $opText = $bin.Operator.ToString()

        if ($eqOperators -contains $opText -or $inOperators -contains $opText) {
            foreach ($value in (Get-StringLiterals $bin.Right)) {
                $key = $value.ToLowerInvariant()
                if (-not $typeHits.Contains($key)) { $typeHits[$key] = [System.Collections.Generic.HashSet[string]]::new() }
                [void] $typeHits[$key].Add($collectorName)
            }
        }
        elseif ($patternOperators -contains $opText) {
            foreach ($value in (Get-StringLiterals $bin.Right)) {
                $patternHits.Add([pscustomobject]@{ Collector = $collectorName; Operator = $opText; Fragment = $value })
            }
        }
    }
}

$typeReport = @(
    foreach ($key in ($typeHits.Keys | Sort-Object)) {
        [pscustomobject]@{
            Type           = $key
            CollectorCount = $typeHits[$key].Count
            Collectors     = @($typeHits[$key] | Sort-Object)
        }
    }
)

if ($AsJson) {
    [pscustomobject]@{
        GeneratedOn   = (Get-Date).ToString('o')
        CollectorRoot = $InventoryRoot
        FileCount     = $files.Count
        TypeCount     = $typeReport.Count
        Types         = $typeReport
        PatternHits   = @($patternHits)
    } | ConvertTo-Json -Depth 6
    return
}

Write-Host "Scanned $($files.Count) collector files under $InventoryRoot"
Write-Host "Distinct ARM types referenced via -eq/-in: $($typeReport.Count)"
Write-Host "Pattern (-like/-match) fragments (reported separately, not counted above): $($patternHits.Count)"
Write-Host ''
$typeReport | Format-Table -AutoSize Type, CollectorCount
if ($patternHits.Count -gt 0) {
    Write-Host ''
    Write-Host '-- -like / -match fragments (reviewed by hand, not folded into the type count) --'
    $patternHits | Format-Table -AutoSize
}
