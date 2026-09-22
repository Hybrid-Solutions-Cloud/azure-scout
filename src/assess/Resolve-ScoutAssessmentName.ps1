#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Map an assessment name the caller typed onto a key that exists in the registry.

.DESCRIPTION
    AB#6762 prefixed the fifteen category-named registry entries with `Assess: ` so the wizard
    menu stops colliding with the fifteen identically-named inventory categories. That is a
    cosmetic change to a value people put in scripts, so it must not break them.

    This function is the compatibility layer. A name that exists in the manifest is returned
    unchanged. A name that does not is retried with the prefix; if that hits, the new value is
    returned and a warning names it, so the caller learns what to change without the run failing.
    A name that matches neither is returned unchanged for the caller's own validation to reject --
    this function's job is renaming, not authorisation.

    Matching is case-insensitive on both legs, because the registry lookup that follows it
    (`$manifest[$name]`) is a case-insensitive hashtable index and this must not be stricter than
    the thing it feeds.

.PARAMETER Name
    One or more assessment names as supplied by the caller.

.PARAMETER Manifest
    The loaded `manifests/assessments.psd1` hashtable.

.OUTPUTS
    [string[]] — one resolved name per input, in the order given.

.NOTES
    Tracks ADO AB#6762 (Feature AB#6742, Epic AB#6731). Delete this function when Release 3
    retires the fifteen entries outright — at that point the legacy names have no target and the
    honest outcome is the caller's "unknown assessment" error, not a silent redirect.
#>
function Resolve-ScoutAssessmentName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Name,

        [Parameter(Mandatory)]
        [hashtable] $Manifest
    )

    # Keys are compared through a case-insensitive set rather than `$Manifest.ContainsKey`,
    # because ContainsKey on the hashtable Import-PowerShellDataFile returns IS case-insensitive
    # today but that is a property of how it was constructed, not a documented guarantee.
    $known = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @($Manifest.Keys), [System.StringComparer]::OrdinalIgnoreCase)

    # The registry-key namespace rename: twelve entries gained a namespace prefix
    # (CAF: / Microsoft: / Scout: / Workload:). Same contract as the AB#6762 layer below —
    # every old key keeps working, with a warning naming the replacement.
    $aliasMap = @{
        'LandingZone'                    = 'CAF: Azure Landing Zone'
        'CASA'                           = 'Microsoft: CASA'
        'DevOps Capability Assessment'   = 'Microsoft: DevOps Capability'
        'SMART'                          = 'Microsoft: SMART Migration'
        'FinOps Review'                  = 'Microsoft: FinOps Review'
        'Cost'                           = 'Scout: Cost Optimization'
        'CrossResource'                  = 'Scout: Cross-Resource'
        'Monitoring'                     = 'Scout: Monitoring Baseline'
        'UpdateManager'                  = 'Scout: Update Manager'
        'Governance'                     = 'Scout: Governance Baseline'
        'AVS Workload'                   = 'Workload: AVS'
        'AVS Landing Zone'               = 'Workload: AVS Landing Zone'
    }

    foreach ($n in @($Name)) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        if ($known.Contains($n)) { $n; continue }

        if ($aliasMap.ContainsKey($n) -and $known.Contains($aliasMap[$n])) {
            $new = $aliasMap[$n]
            Write-Warning "'$n' is now '$new'; the old name keeps working."
            $new
            continue
        }

        $prefixed = "Assess: $n"
        if ($known.Contains($prefixed)) {
            Write-Warning "Assessment '$n' has been renamed to '$prefixed' (AB#6762) — running it. Update your script to the new name; the old one is accepted for now and will stop being accepted when the entry is retired."
            $prefixed
            continue
        }

        # Unknown either way. Hand it back untouched so the caller reports it, rather than
        # inventing a name that is wrong in a second way.
        $n
    }
}
