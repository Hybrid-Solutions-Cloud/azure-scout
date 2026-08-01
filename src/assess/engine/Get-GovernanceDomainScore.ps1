#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Convert the Cloud Governance framework's per-domain 0-100 percentage scores (already
    produced by Get-Score) into a 1-10 domain maturity score, one per CAF Govern risk
    category (AB#6459, Feature AB#6458, Epic AB#6454).

.DESCRIPTION
    Get-Score already computes a weighted-mean 0-100 percentage score per (Framework, Area)
    group from Pass/Partial/Fail findings. This function does NOT run a second scoring pass
    or duplicate any rule -- it takes the SAME Areas Get-Score already produced (filtered to
    Framework -eq 'Cloud Governance', the seven caf.govern.*.yaml rule files) and relabels
    each area's percentage onto a 1-10 scale.

    Why 1-10 and not something reused: CAF's Govern methodology publishes no maturity model
    or level scheme at all (unlike WAF, which publishes an explicit 5-level model that
    Get-MaturityLevel.ps1 already buckets scores into). There is nothing Microsoft-published
    to relabel here, so the 1-10 scale is entirely Scout's own invention -- see
    docs/design/governance-domain-maturity-scale.md for the full reconciliation with
    Get-MaturityLevel's WAF 5-level model, which this is deliberately NOT the same scale as.

    Mapping: Score1To10 = Max(1, Min(10, Round(PercentScore / 10))). A 1-10 scale (not 0-10)
    is used because "1" reads as "minimally present" and a governance domain that was
    actually SCORED (at least one Pass/Partial/Fail rule) always has some evidence, even if
    every rule failed -- 0% still floors to 1, not 0, so the number never collapses to
    "looks like nothing was measured".

    NotAssessed (AB#6844/AB#6845 false-pass class): a domain where every rule in it is
    Manual/Unknown/Error (Get-Score's denominator is 0, so PercentScore is $null) renders
    Score = $null and NotAssessed = $true here -- never a fabricated 1 or a misleading 10.
    A caller MUST check NotAssessed before displaying Score, exactly as Get-Score's own
    $null-Score convention already requires downstream.

.PARAMETER Areas
    The Areas array from Get-Score's output (or any array of objects carrying Area/Score/
    Pass/Partial/Fail/Manual/Unknown/Error).

.PARAMETER Framework
    The framework name to filter to. Defaults to 'Cloud Governance' (the caf.govern.*.yaml
    rule files' `framework:` value); overridable for tests.

.NOTES
    Tracks ADO Story AB#6459 (Feature AB#6458, Epic AB#6454).
#>
function ConvertTo-ScoutGovernanceScale {
    # Shared 0-100 -> 1-10 mapping, factored out so the per-domain conversion below and any
    # overall/headline conversion (Export-GovernanceReport.ps1) use the exact same arithmetic
    # and can never drift apart.
    param([AllowNull()][Nullable[double]] $PercentScore)
    if ($null -eq $PercentScore) { return $null }
    return [Math]::Max(1, [Math]::Min(10, [Math]::Round($PercentScore / 10.0, 0, [System.MidpointRounding]::AwayFromZero)))
}

function Get-GovernanceDomainScore {
    param(
        [Parameter(Mandatory)] $Areas,
        [string] $Framework = 'Cloud Governance'
    )

    # @() wrap is load-bearing: Where-Object over zero matches collapses to $null on
    # assignment, and $null.Count throws PropertyNotFoundException under
    # Set-StrictMode -Version Latest (the same pattern documented throughout Get-Score.ps1).
    $domains = @($Areas | Where-Object { $_.Framework -eq $Framework })

    # Write-Output -NoEnumerate, NOT `return , @(...)`: the comma operator wraps an ALREADY
    # zero-length array into a ONE-element array whose sole element is the empty array (a
    # classic PowerShell gotcha) -- an empty $Areas input would then return Count -eq 1 with
    # that one "domain" carrying no Area/Score properties at all, throwing under StrictMode
    # the moment a caller reads .Area. -NoEnumerate preserves a real, possibly-empty array's
    # identity across the return boundary instead (the same fix Resolve-JsonPath.ps1 uses).
    $result = @($domains | Sort-Object Area | ForEach-Object {
            $pct = $_.Score
            $notAssessed = ($null -eq $pct)
            $score1To10 = ConvertTo-ScoutGovernanceScale -PercentScore $pct
            [pscustomobject]@{
                Area         = $_.Area
                PercentScore = $pct
                Score        = $score1To10
                NotAssessed  = $notAssessed
                # Carried through unchanged from Get-Score's Areas entry so a renderer never
                # has to re-derive them (and can never desync from the percentage score).
                Pass         = $_.Pass
                Partial      = $_.Partial
                Fail         = $_.Fail
                Manual       = $_.Manual
                Unknown      = $_.Unknown
                Error        = $_.Error
            }
        })
    Write-Output -NoEnumerate $result
}
