<#
.Synopsis
Parameter-translation shim: maps the v1 ARM REST contract onto src/collect.

.DESCRIPTION
This function used to BE the inventory engine's ARM REST layer -- it acquired its own token,
built seven URLs by hand and drove them per subscription, duplicating what
Get-ScoutApiResources (src/collect/Get-ScoutApiResources.ps1) was already written to do. That
is what AB#5648 retired. It now issues no HTTP call of its own.

The five datasets are the ones Resource Graph does not index, because they are not resources:
Microsoft.ResourceHealth/events, Microsoft.ManagedIdentity/userAssignedIdentities,
Microsoft.Advisor/advisorScore, Microsoft.Consumption/reservationRecommendations, and the
Policy assignment-summary / definition / set-definition triple.

The v1 contract is preserved exactly at this boundary:
  - one result element per subscription, in subscription order;
  - each element is a HASHTABLE, because Get-AZSCCollectedValue's IDictionary branch is what
    Start-AZSCExtractionOrchestration has always exercised for these results;
  - the v1 key names, which are NOT the src/collect property names and are load-bearing --
    Start-AZSCExtractionOrchestration reads 'ReservationRecomen', 'PolicyAssign', 'PolicyDef'
    and 'PolicySetDef' by string;
  - an unknown -AzureEnvironment writes the v1 message and returns nothing;
  - a token acquisition failure returns nothing rather than throwing;
  - a single endpoint failing degrades that ONE field for that ONE subscription to a falsy
    value and the run continues.

One deliberate behaviour change, called out rather than hidden: v1 wrapped all three Policy
calls in a SINGLE try/catch, so a failure on the first (the policyStates summarize, which is
the one most likely to be denied) discarded the two definition lists that were never even
attempted. src/collect issues them independently, so a partial Policy result is now possible
where v1 produced none. That is the same defect class as AB#5636 -- one optional dataset
failing must not destroy its neighbours.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/Extraction/Get-AZTIAPIResources.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Tracks ADO AB#5648 (Epic AB#5638). Original v1 implementation: Claudio Merola, 15th Oct 2024.
#>
function Get-AZSCAPIResources {
    Param($Subscriptions, $AzureEnvironment, $SkipPolicy)

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Starting API Inventory (src/collect, AB#5648)')

    # Preserved verbatim from the v1 contract: an environment with no known ARM management
    # host is reported to the operator and yields no API data, rather than failing the run.
    $KnownEnvironments = @('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')
    if ($AzureEnvironment -notin $KnownEnvironments) {
        Write-Host ('Invalid Azure Environment for API Rest Inventory: ' + $AzureEnvironment) -ForegroundColor Red
        return
    }

    # v1 iterated $Subscriptions with foreach, so a $null or empty list produced no rows and no
    # error. Get-ScoutApiResources declares -Subscriptions mandatory, which would prompt.
    if (-not $Subscriptions) { return }

    $Skip = [bool]$SkipPolicy

    $Collected = Get-ScoutApiResources -Subscriptions @($Subscriptions) `
        -AzureEnvironment $AzureEnvironment -SkipPolicy:$Skip

    # Back to the v1 hashtable shape and the v1 key names.
    #
    # The `if (...) { ... } else { $null }` on the four resource fields is NOT decoration and
    # must not be simplified to a direct assignment. v1 wrote exactly that construct, and an
    # `if` statement used as a value flows through the pipeline, which UNROLLS a
    # single-element array to a scalar. v1's Policy fields were plain assignments and did not
    # unroll. Get-ScoutApiResources now returns the wire shape unchanged for every field, so
    # this is where the v1 shapes are reproduced -- four unrolled, three not.
    $APIResults = foreach ($Entry in @($Collected)) {

        # Plain assignments, deliberately, for the same reason the four fields below use an
        # `if` EXPRESSION: an assignment preserves an array, an if-expression unrolls a
        # single-element one. v1 assigned the Policy fields and unrolled the other four, and
        # the difference is visible in $ReturnData.PolicyDef.
        if ($Skip) {
            # v1 initialised these to '' and left them that way when -SkipPolicy was set.
            $PolicyAssign = ''
            $PolicyDef = ''
            $PolicySetDef = ''
        }
        else {
            $PolicyAssign = $Entry.PolicyAssignments
            $PolicyDef = $Entry.PolicyDefinitions
            $PolicySetDef = $Entry.PolicySetDefinitions
        }

        @{
            'Subscription'       = $Entry.Subscription
            'ResourceHealth'     = if ($Entry.ResourceHealth) { $Entry.ResourceHealth } else { $null }
            'ManagedIdentities'  = if ($Entry.ManagedIdentities) { $Entry.ManagedIdentities } else { $null }
            'AdvisorScore'       = if ($Entry.AdvisorScore) { $Entry.AdvisorScore } else { $null }
            'ReservationRecomen' = if ($Entry.ReservationRecommendations) { $Entry.ReservationRecommendations } else { $null }
            'PolicyAssign'       = $PolicyAssign
            'PolicyDef'          = $PolicyDef
            'PolicySetDef'       = $PolicySetDef
        }
    }

    return $APIResults
}
