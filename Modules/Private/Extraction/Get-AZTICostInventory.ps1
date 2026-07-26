<#
.Synopsis
Parameter-translation shim: maps the v1 cost-extraction contract onto src/collect.

.DESCRIPTION
This function used to BE the inventory engine's Cost Management layer. It is now a shim over
Get-ScoutCostInventory (src/collect/Get-ScoutCostInventory.ps1), which is the single
implementation of the Cost Management call. AB#5648 retired the duplicate.

The v1 contract is preserved exactly at this boundary:
  - one result element per subscription, in subscription order;
  - each element is a HASHTABLE with the keys SubscriptionId, SubscriptionName, CostData --
    src/collect emits [pscustomobject], and this shim converts, because Start-AZSCExtraJobs
    and Start-AZSCSubscriptionJob read `$Cost.CostData.Row` off whatever comes back and the
    hashtable shape is what has shipped;
  - CostData is `@()`, never `$null`, when cost data could not be retrieved;
  - the failure path warns and continues. It must NEVER throw. Cost data is optional
    enrichment: the historical defect (AB#5636) was a rethrow of the caught exception message,
    which made the empty-collection fallback on the very next line unreachable, so a machine
    without Az.CostManagement lost the entire report to -IncludeCosts.

Az.CostManagement is deliberately NOT auto-installed (see AzureScout.psm1): it drags in a
newer Az.Accounts, and two Az.Accounts versions side by side make every subsequent
Import-Module die inside Az.Accounts' own assembly-load-context resolver.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/Extraction/Get-AZTICostInventory.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Tracks ADO AB#5648 (Epic AB#5638). Original v1 implementation: Claudio Merola.
#>
function Get-AZSCCostInventory {
    Param($Subscriptions, $Days, $Granularity)

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Starting Cost Inventory Extraction (src/collect, AB#5648)')

    # v1 iterated $Subscriptions with foreach, so a $null or empty list produced no rows and no
    # error. Get-ScoutCostInventory declares -Subscriptions mandatory, which would prompt.
    if (-not $Subscriptions) { return }

    $CollectArgs = @{ Subscriptions = @($Subscriptions) }
    if ($PSBoundParameters.ContainsKey('Days') -and $null -ne $Days) { $CollectArgs.Days = [int]$Days }
    if (![string]::IsNullOrEmpty($Granularity)) { $CollectArgs.Granularity = $Granularity }

    $Collected = Get-ScoutCostInventory @CollectArgs

    # Back to the v1 hashtable shape, key for key.
    $Result = foreach ($Entry in @($Collected)) {
        @{
            SubscriptionId   = $Entry.SubscriptionId
            SubscriptionName = $Entry.SubscriptionName
            CostData         = $Entry.CostData
        }
    }

    return $Result
}
