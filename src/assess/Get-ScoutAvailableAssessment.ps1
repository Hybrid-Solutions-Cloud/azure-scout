#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Return the registry entries Scout can actually run, in menu order.

.DESCRIPTION
    AB#6763. Fixing the wizard's manifest path (AB#6754) turned a hard-coded one-entry list into
    the whole registry. Not every registry entry is an assessment a customer can usefully select:
    `Estate` declares `Rules = @()` and scores nothing at all, and any future entry whose rule
    glob matches no file on disk would behave the same way.

    That is the failure this function exists to prevent, and it is the same one that made the
    twelve provably-broken collectors worth retiring: **an entry that runs and returns nothing is
    read as "no findings".** A short honest menu beats a long dishonest one.

    Availability is decided by evidence, not by a flag someone has to remember to set:

      - the entry declares at least one rule glob, AND
      - at least one file in the rules directory matches one of those globs.

    So an assessment is visible exactly when rules exist behind it. Adding a rule file makes its
    entry appear; deleting the last one makes it disappear. Nothing to keep in sync.

    `RequiresData` gating is deliberately NOT done here. That gate asks a different question --
    "does this tenant have anything for it to score?" -- it needs a collect.json, and the wizard
    already applies it on top of this list.

.PARAMETER Manifest
    The loaded `manifests/assessments.psd1` hashtable.

.PARAMETER RuleDirectory
    Where the rule files live. Defaults to `src/assess/rules` resolved from this file.

.OUTPUTS
    [string[]] — available assessment names, sorted, suitable for a menu.

.NOTES
    Tracks ADO AB#6763 (Feature AB#6742, Epic AB#6731).
#>
function Get-ScoutAvailableAssessment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Manifest,

        [string] $RuleDirectory
    )

    if ([string]::IsNullOrWhiteSpace($RuleDirectory)) {
        $RuleDirectory = Join-Path $PSScriptRoot 'rules'
    }

    # A missing rules directory means nothing is runnable. Returning an empty menu is the honest
    # answer; inventing one would put the caller back where AB#6763 started.
    if (-not (Test-Path -LiteralPath $RuleDirectory)) {
        Write-Warning "Get-ScoutAvailableAssessment: no rules directory at '$RuleDirectory' — no assessment can be offered."
        return @()
    }

    $ruleNames = @(Get-ChildItem -LiteralPath $RuleDirectory -Filter '*.yaml' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName })

    $available = foreach ($name in @($Manifest.Keys)) {
        $spec = $Manifest[$name]
        if ($null -eq $spec) { continue }

        # $spec is a Hashtable out of a .psd1 and most entries are hand-written, so an absent
        # `Rules` key is a real possibility -- and dotting into one throws under StrictMode
        # rather than returning $null.
        $patterns = if ($spec -is [hashtable] -and $spec.ContainsKey('Rules')) { @($spec.Rules) } else { @() }
        $patterns = @($patterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($patterns.Count -eq 0) {
            Write-Verbose "Get-ScoutAvailableAssessment: '$name' declares no rules — it scores nothing, so it is not offered (AB#6763)."
            continue
        }

        $matched = @($ruleNames | Where-Object { $rn = $_; @($patterns | Where-Object { $rn -like $_ }).Count -gt 0 })
        if ($matched.Count -eq 0) {
            Write-Verbose "Get-ScoutAvailableAssessment: '$name' declares rules ($($patterns -join ', ')) but no rule file matches — it would return nothing, so it is not offered (AB#6763)."
            continue
        }

        $name
    }

    return @(@($available) | Sort-Object)
}
