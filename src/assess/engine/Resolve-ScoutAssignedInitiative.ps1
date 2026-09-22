#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Discover which built-in Azure Policy regulatory-compliance initiatives are actually
    assigned in the scanned scope (AB#6794), from data Scout already collects.

.DESCRIPTION
    "Assigned" here means observably assigned: at least one row exists for it in
    domains.management.policyComplianceStates. An initiative that Scout can see the
    DEFINITION of (domains.management.policyInitiatives) but that produced zero
    compliance rows has never been assigned in this scope — offering it would mean
    guessing at a score with nothing behind it, which is exactly the false-pass class
    AB#6793 exists to prevent. It is silently not returned, not returned-and-marked-
    unavailable, because there is nothing for a caller to render for it (no control
    list, no version confirmation beyond the definition) — see the .NOTES for the one
    case (definition known, zero compliance rows) this deliberately still excludes.

    Only PolicyType 'BuiltIn' initiatives are considered. A tenant's own custom
    initiative is not a "regulatory compliance framework" in the sense AB#6794 asks
    for, and Scout has no way to know what a custom initiative's controls MEAN.

    Two versions of the same framework (e.g. two CIS Azure Foundations releases
    assigned side by side) are two independent entries here, keyed by the initiative's
    id — which is version-specific by construction in Azure Policy — never merged.

.PARAMETER Collect
    The assessment collect object.

.OUTPUTS
    [pscustomobject[]] with Id (PolicySetDefinitionId), DisplayName, Version,
    PolicyType, PolicyCount (from the definition, when known) — sorted by DisplayName
    then Version for a stable menu/report order.

.NOTES
    Tracks AB#6794 (Feature AB#6744, Epic AB#6454).
#>
function Resolve-ScoutAssignedInitiative {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Collect
    )

    $states = @()
    if ($null -ne $Collect -and $Collect.PSObject.Properties['domains'] -and $null -ne $Collect.domains -and
        $Collect.domains.PSObject.Properties['management'] -and $null -ne $Collect.domains.management -and
        $Collect.domains.management.PSObject.Properties['policyComplianceStates'] -and $null -ne $Collect.domains.management.policyComplianceStates) {
        $states = @($Collect.domains.management.policyComplianceStates)
    }

    $definitions = @()
    if ($null -ne $Collect -and $Collect.PSObject.Properties['domains'] -and $null -ne $Collect.domains -and
        $Collect.domains.PSObject.Properties['management'] -and $null -ne $Collect.domains.management -and
        $Collect.domains.management.PSObject.Properties['policyInitiatives'] -and $null -ne $Collect.domains.management.policyInitiatives) {
        $definitions = @($Collect.domains.management.policyInitiatives)
    }

    # The set of initiative ids that produced at least one compliance row -- the observable
    # definition of "assigned" this function uses.
    $assignedIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($state in $states) {
        if ($state -and $state.PSObject.Properties['PolicySetDefinitionId'] -and $state.PolicySetDefinitionId) {
            [void]$assignedIds.Add([string]$state.PolicySetDefinitionId)
        }
    }

    if ($assignedIds.Count -eq 0) { return @() }

    # Index definitions by id, built-in only.
    #
    # AB#6792 -- what happens when a compliance row names an initiative Scout has no definition
    # for was WRONG, and a live run against tenant tppoc caught it. Policy compliance state and
    # policy set definitions are two SEPARATE Azure calls; the definitions sweep can return
    # nothing while the compliance sweep returns hundreds of rows. In that case every id fell to
    # the else branch below, the function returned an empty set, and the assessment produced
    # ZERO findings -- against 469 real compliance rows scoring 29.6%. Silence reading as
    # "nothing to report" is precisely the false-negative class this Epic exists to remove.
    #
    # The refusal to SCORE an initiative that cannot be confirmed BuiltIn is correct and is kept:
    # presenting a customer's custom initiative under a framework's name would be actively
    # misleading. But refusing to score is not the same as saying nothing. Each unconfirmable
    # initiative is now returned marked Unconfirmed so the caller can render it as Not assessed
    # and name it, rather than dropping it on the floor.
    $definitionById = @{}
    foreach ($def in $definitions) {
        if (-not $def -or -not $def.PSObject.Properties['Id'] -or -not $def.Id) { continue }
        $policyType = if ($def.PSObject.Properties['PolicyType']) { [string]$def.PolicyType } else { $null }
        if ($policyType -and $policyType -ne 'BuiltIn') { continue }
        $definitionById[[string]$def.Id] = $def
    }

    $results = foreach ($id in $assignedIds) {
        $def = $definitionById[$id]
        if ($def) {
            [pscustomobject]@{
                Id          = $id
                DisplayName = if ($def.PSObject.Properties['DisplayName'] -and $def.DisplayName) { [string]$def.DisplayName } else { $id }
                Version     = if ($def.PSObject.Properties['Version'] -and $def.Version) { [string]$def.Version } else { 'N/A' }
                PolicyType  = 'BuiltIn'
                PolicyCount = if ($def.PSObject.Properties['PolicyCount']) { $def.PolicyCount } else { $null }
                Unconfirmed = $false
            }
        }
        else {
            # No matching BuiltIn definition -- either the definitions sweep failed or was
            # skipped, or this id belongs to a custom initiative (excluded above). Either way it
            # cannot be confirmed BuiltIn, so it is NOT scored. It is still returned, flagged, so
            # the caller renders it as Not assessed and names it. See the block comment above.
            [pscustomobject]@{
                Id          = $id
                DisplayName = $id
                Version     = 'N/A'
                PolicyType  = 'Unconfirmed'
                PolicyCount = $null
                Unconfirmed = $true
            }
        }
    }

    return @(@($results | Where-Object { $_ }) | Sort-Object DisplayName, Version)
}
