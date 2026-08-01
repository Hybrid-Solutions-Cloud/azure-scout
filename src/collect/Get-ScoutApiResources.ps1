#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Per-subscription ARM REST data that Resource Graph does not index -- ported into
    src/collect from Modules/Private/Extraction/Get-AZTIAPIResources.ps1 (AB#5639/5645).

.DESCRIPTION
    Five of the legacy inventory engine's data points have no Resource Graph table at all,
    because they are not resources -- they are point-in-time computed/derived data ARM
    exposes only through its own control-plane REST endpoints:

        ResourceHealth        Microsoft.ResourceHealth/events (6-month history)
        ManagedIdentities     Microsoft.ManagedIdentity/userAssignedIdentities
        AdvisorScore          Microsoft.Advisor/advisorScore (the percentage score, distinct
                              from `Get-ScoutRawInventory -IncludeAdvisories`'s per-
                              recommendation rows, which DO come from Resource Graph)
        ReservationRecommendations   Microsoft.Consumption/reservationRecommendations
        Policy (assignments/definitions/set-definitions)   Microsoft.PolicyInsights /
                              Microsoft.Authorization -- Import-Governance
                              (src/ingest/Import-Governance.ps1) already covers policy
                              assignment/definition data for the assessment platform via its
                              own ARG + ambient-token calls; this is kept here only for
                              feature parity with the legacy per-subscription REST pull the
                              174-collector engine already depends on, not as a second source
                              the assessment platform should ALSO consume.
        ArcSites              Microsoft.Edge/sites (AB#6801) -- a normal, non-extension ARM
                              resource that can be created at subscription or resource-group
                              scope, but Resource Graph's supported-type reference does not list
                              `microsoft.edge/sites` among the `microsoft.edge/*` types it
                              indexes. It has no natural per-parent scope the way an extension
                              resource does, so it is listed once per subscription here rather
                              than through Get-ScoutArmChildResource.ps1's per-parent sweep.

    Every call is independently non-fatal: a single endpoint failing (missing RBAC,
    provider not registered, transient error) degrades that one field to $null for that one
    subscription and the run continues -- exactly the legacy function's existing behavior,
    carried forward unchanged.

.PARAMETER Subscriptions
    Subscription objects with `.id` and `.name` (the same shape `Get-ScoutRawInventory`'s
    `ResourceContainers`-derived subscription list, or the assessment platform's own
    `subscriptions` collect key, already provides).

.PARAMETER AzureEnvironment
    One of 'AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud' -- selects the ARM management
    endpoint host, matching the legacy function.

.PARAMETER SkipPolicy
    Skip the three Policy REST calls (assignment summary + both definition lists) -- these
    are the heaviest of the five calls and are already covered for the assessment platform
    by `Import-Governance`.

.OUTPUTS
    One `[pscustomobject]` per subscription: `Subscription` (id), `ResourceHealth`,
    `ManagedIdentities`, `AdvisorScore`, `ReservationRecommendations`, `ArcSites`,
    `PolicyAssignments`, `PolicyDefinitions`, `PolicySetDefinitions`. Any field whose REST call
    failed is `$null` for that subscription -- callers MUST NOT assume any field is populated.

.NOTES
    Tracks ADO AB#5639 (Task AB#5645, Epic AB#5638).

    Ported (not just wrapped) rather than calling the legacy `Get-AZSCAPIResources`
    directly: `src/` files are dot-sourced independently of `Modules/Private` load order (see
    AzureScout.psm1), and the legacy function's un-guarded property accesses on its own
    `$Token`/response objects predate this codebase's StrictMode-everywhere convention for
    `src/`. The HTTP call sequence, endpoints, and API versions are otherwise identical to
    the legacy implementation.

    Uses the caller's ambient Az context token (`Get-AzAccessToken`), same as
    `Import-Governance` and the legacy function -- no separate authentication path.
#>
function Get-ScoutApiResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Subscriptions,
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string] $AzureEnvironment = 'AzureCloud',
        [switch] $SkipPolicy,
        # AB#6755. The assessment collect pass needs this function for exactly two of its seven
        # calls -- the policy and policy-set DEFINITIONS that Get-ScoutTenantWideResource turns
        # into envelopes. The other five (resource health, managed identities, advisor score,
        # reservation recommendations, and the policyStates summarize POST) feed inventory
        # report collectors that an assessment run never renders, so paying for them there
        # would be five wasted round-trips and a second of pacing sleep per subscription.
        # Mutually exclusive with -SkipPolicy, which suppresses the very calls this keeps.
        [switch] $DefinitionsOnly
    )

    if ($DefinitionsOnly -and $SkipPolicy) {
        throw 'Get-ScoutApiResources: -DefinitionsOnly and -SkipPolicy cannot be combined -- together they would issue no calls at all.'
    }

    $managementHost = switch ($AzureEnvironment) {
        'AzureCloud'         { 'management.azure.com' }
        'AzureUSGovernment'  { 'management.usgovcloudapi.net' }
        'AzureChinaCloud'    { 'management.chinacloudapi.cn' }
    }

    try {
        $token = Get-AzAccessToken -AsSecureString -InformationAction SilentlyContinue -WarningAction SilentlyContinue
        $tokenPlainText = $token.Token | ConvertFrom-SecureString -AsPlainText
        $headers = @{ Authorization = "Bearer $tokenPlainText" }
    }
    catch {
        Write-Warning "Get-ScoutApiResources: could not acquire an access token -- skipping all REST calls: $($_.Exception.Message)"
        return @()
    }

    function Invoke-ScoutApiCall {
        param([string] $Uri, [string] $Method = 'GET', [string] $FieldName, [string] $SubscriptionName)
        try {
            $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method
            if ($null -eq $response) { return $null }
            # An ARM envelope always carries `value`, but a provider that is not registered can
            # answer with a bare object. v1 read `.value` with StrictMode off, so an absent
            # property was $null rather than a crash; keep that.
            if (-not $response.PSObject.Properties['value']) { return $null }
            $value = $response.value
            if ($null -eq $value) { return $null }
            # Comma operator: `return $value` UNROLLS a single-element array to a scalar, which
            # silently changes the shape of every endpoint that returned exactly one row. The
            # caller decides what shape it wants; this returns what the wire returned.
            return , $value
        }
        catch {
            Write-Verbose "Get-ScoutApiResources: '$FieldName' failed for subscription '$SubscriptionName' -- leaving it `$null and continuing: $($_.Exception.Message)"
            return $null
        }
    }

    $resourceHealthSince = (Get-Date).AddMonths(-6)

    $results = foreach ($subscription in $Subscriptions) {
        $subId   = $subscription.id
        $subName = if ($subscription.PSObject.Properties['name']) { $subscription.name } else { $subId }
        $base    = "https://$managementHost/subscriptions/$subId/providers"

        # Host output, in a src/ library function, deliberately: this loop issues up to seven
        # sequential REST calls per subscription with rate-limit sleeps between them, so on a
        # large tenant it is minutes of apparent silence. The legacy function printed this
        # exact line per subscription and AB#5648 preserves it rather than making the run look
        # hung. It is the only Write-Host under src/.
        #
        # AB#6755: a -DefinitionsOnly sweep is two fast GETs, not seven paced calls, and it runs
        # inside an assessment collect that prints its own progress. Announcing it per
        # subscription would be new console noise for a pass that is not slow enough to need it.
        if ($DefinitionsOnly) {
            Write-Verbose "Get-ScoutApiResources: reading policy definitions for subscription '$subName'."
        }
        else {
            Write-Host 'Running API Inventory at: ' -NoNewline
            Write-Host $subName -ForegroundColor Cyan
        }

        $resourceHealth             = $null
        $managedIdentities          = $null
        $advisorScore               = $null
        $reservationRecommendations = $null
        $arcSites                   = $null
        if (-not $DefinitionsOnly) {
            $resourceHealth = Invoke-ScoutApiCall -FieldName 'ResourceHealth' -SubscriptionName $subName `
                -Uri "$base/Microsoft.ResourceHealth/events?api-version=2022-10-01&queryStartTime=$resourceHealthSince"
            Start-Sleep -Milliseconds 200

            $managedIdentities = Invoke-ScoutApiCall -FieldName 'ManagedIdentities' -SubscriptionName $subName `
                -Uri "$base/Microsoft.ManagedIdentity/userAssignedIdentities?api-version=2023-01-31"
            Start-Sleep -Milliseconds 200

            $advisorScore = Invoke-ScoutApiCall -FieldName 'AdvisorScore' -SubscriptionName $subName `
                -Uri "$base/Microsoft.Advisor/advisorScore?api-version=2023-01-01"
            Start-Sleep -Milliseconds 200

            $reservationRecommendations = Invoke-ScoutApiCall -FieldName 'ReservationRecommendations' -SubscriptionName $subName `
                -Uri "$base/Microsoft.Consumption/reservationRecommendations?api-version=2023-05-01"
            Start-Sleep -Milliseconds 200

            # AB#6801: Microsoft.Edge/sites -- see the function synopsis for why this is a
            # per-subscription list rather than a per-parent ARM child sweep. Reader's `*/read`
            # wildcard covers `Microsoft.Edge/sites/read`; no new permission is required.
            $arcSites = Invoke-ScoutApiCall -FieldName 'ArcSites' -SubscriptionName $subName `
                -Uri "$base/Microsoft.Edge/sites?api-version=2024-02-01-preview"
            Start-Sleep -Milliseconds 200
        }

        $policyAssignments   = $null
        $policyDefinitions   = $null
        $policySetDefinitions = $null
        if (-not $SkipPolicy) {
            # The policyStates summarize POST is an inventory-report input, not a definition, so
            # -DefinitionsOnly skips it alongside the four above.
            if (-not $DefinitionsOnly) {
                $policyAssignments = Invoke-ScoutApiCall -Method 'POST' -FieldName 'PolicyAssignments' -SubscriptionName $subName `
                    -Uri "$base/Microsoft.PolicyInsights/policyStates/latest/summarize?api-version=2019-10-01"
                Start-Sleep -Milliseconds 200
            }
            $policySetDefinitions = Invoke-ScoutApiCall -FieldName 'PolicySetDefinitions' -SubscriptionName $subName `
                -Uri "$base/Microsoft.Authorization/policySetDefinitions?api-version=2023-04-01"
            Start-Sleep -Milliseconds 200
            $policyDefinitions = Invoke-ScoutApiCall -FieldName 'PolicyDefinitions' -SubscriptionName $subName `
                -Uri "$base/Microsoft.Authorization/policyDefinitions?api-version=2023-04-01"
        }

        # Matches the legacy per-subscription pacing exactly (200ms between calls, 300ms
        # between subscriptions) -- ARM throttles these control-plane endpoints per tenant.
        Start-Sleep -Milliseconds 300

        [pscustomobject]@{
            Subscription                = $subId
            ResourceHealth              = $resourceHealth
            ManagedIdentities           = $managedIdentities
            AdvisorScore                = $advisorScore
            ReservationRecommendations  = $reservationRecommendations
            ArcSites                    = $arcSites
            PolicyAssignments           = $policyAssignments
            PolicyDefinitions           = $policyDefinitions
            PolicySetDefinitions        = $policySetDefinitions
        }
    }

    return @($results)
}
