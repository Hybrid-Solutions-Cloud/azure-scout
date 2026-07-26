#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Per-subscription actual-cost data, grouped by type/resource group/location/service --
    ported into src/collect from Modules/Private/Extraction/Get-AZTICostInventory.ps1
    (AB#5639/5647).

.DESCRIPTION
    Cost Management is an opt-in Az module (`Az.CostManagement`) that is deliberately NOT in
    this repo's auto-installed dependency list (AzureScout.psm1's own `.NOTES` explain why:
    installing it drags in a newer `Az.Accounts`, and two `Az.Accounts` versions side by side
    crash every subsequent module import with a stack overflow). Cost data is therefore
    OPTIONAL ENRICHMENT that must never cost the caller their run.

.PARAMETER Subscriptions
    Subscription objects with `.id` and `.name`.

.PARAMETER Days
    When >= 365, queries the full previous calendar year (Jan 1 -- Dec 31). Otherwise queries
    from the start of two months ago through end-of-today, matching the legacy function.

.PARAMETER Granularity
    Passed straight through to `Invoke-AzCostManagementQuery -DatasetGranularity` (e.g.
    'Monthly', 'Daily').

.OUTPUTS
    One `[pscustomobject]` per subscription: `SubscriptionId`, `SubscriptionName`, `CostData`
    (the `Invoke-AzCostManagementQuery` result rows, or `@()` if cost data could not be
    retrieved for that subscription -- NEVER `$null`, so a caller's `@($x.CostData).Count`
    is always safe under StrictMode).

.NOTES
    Tracks ADO AB#5639 (Task AB#5647, Epic AB#5638).

    THE NON-FATAL GUARANTEE IS THE POINT (mirrors the fix already shipped in the legacy
    function for AB#5636): a missing `Az.CostManagement` module, or any other Cost
    Management failure, degrades that ONE subscription's `CostData` to `@()` with a
    `Write-Warning` naming the cause -- it never throws uncaught, and it never aborts
    collection for any OTHER subscription. The historical defect this guards against was a
    bare `throw $_.Exception.Message` followed by an unreachable `$Costs = @()` fallback
    that could never run; every `catch` block here ends in an assignment, not a `throw`.
#>
function Get-ScoutCostInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Subscriptions,
        [int]    $Days = 60,
        [string] $Granularity = 'Monthly'
    )

    $today = Get-Date
    $endDate = Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour 23 -Minute 59 -Second 59 -Millisecond 0

    if ($Days -ge 365) {
        $startDate = Get-Date -Year $endDate.AddYears(-1).Year -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 1
        $endDate   = Get-Date -Year $startDate.Year -Month 12 -Day 31 -Hour 23 -Minute 59 -Second 59 -Millisecond 0
    }
    else {
        $startDate = (Get-Date -Day 1).AddMonths(-2)
    }

    $grouping = @(
        @{ Name = 'ResourceType'; Type = 'Dimension' }
        @{ Name = 'ResourceGroup'; Type = 'Dimension' }
        @{ Name = 'ResourceLocation'; Type = 'Dimension' }
        @{ Name = 'ServiceName'; Type = 'Dimension' }
    )
    $aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } }

    $costManagementAvailable = [bool](Get-Command Invoke-AzCostManagementQuery -ErrorAction SilentlyContinue)
    if (-not $costManagementAvailable) {
        Write-Warning "Get-ScoutCostInventory: the Az.CostManagement module is not installed -- every subscription's CostData will be empty. Install it with 'Install-Module Az.CostManagement -Scope CurrentUser' to include cost data."
    }

    $result = foreach ($subscription in $Subscriptions) {
        $subId   = $subscription.id
        $subName = if ($subscription.PSObject.Properties['name']) { $subscription.name } else { $subId }
        $scope   = "/subscriptions/$subId/"
        $costs   = @()

        if ($costManagementAvailable) {
            try {
                $costs = @(Invoke-AzCostManagementQuery -Type ActualCost -Scope $scope -Timeframe Custom `
                        -DatasetGranularity $Granularity -DatasetGrouping $grouping -DatasetAggregation $aggregation `
                        -TimePeriodFrom $startDate -TimePeriodTo $endDate -ErrorAction Stop)
            }
            catch {
                # Cost data is optional enrichment -- it must never cost the caller their
                # inventory (AB#5636's defect class: a bare `throw` here previously aborted
                # the whole run and made the `$costs = @()` fallback unreachable).
                $costs = @()
                Write-Warning "Get-ScoutCostInventory: cost data skipped for subscription '$subName': $($_.Exception.Message)"
            }
        }

        [pscustomobject]@{
            SubscriptionId   = $subId
            SubscriptionName = $subName
            CostData         = $costs
        }
    }

    return @($result)
}
