<#
.Synopsis
Parameter-translation shim: maps the v1 VM-quota contract onto src/collect.

.DESCRIPTION
This function used to BE the inventory engine's quota layer. It is now a shim over
Get-ScoutVmQuotas (src/collect/Get-ScoutVmQuotas.ps1), which is the single implementation.
AB#5648 retired the duplicate.

Get-AzVMUsage is a per-region, per-subscription ARM call with no Resource Graph table, so it
cannot be folded into Get-ScoutRawInventory no matter how the raw row set is shaped. Only the
(subscription, location) pairs that actually contain a VM or VMSS are queried -- the same
targeted strategy v1 used.

The v1 contract is preserved exactly at this boundary: a single object with
`type = 'AZSC/VM/Quotas'` and `properties` holding one `Location`/`SubId`/`Subscription`/`Data`
entry per pair, `Data` filtered to `CurrentValue -ge 1`. Compute/VirtualMachine,
Compute/VirtualMachineScaleSet and Containers/AKS all match on that literal type string, so it
is load-bearing.

$Resources is a MIXED array -- Resource Graph rows carry subscriptionId/type, the ARM REST rows
appended alongside them do not. A bare `$_.subscriptionId` on one of those aborts the pipeline
under StrictMode, which meant NO quota was collected for ANY subscription rather than just the
offending one (AB#5633). Get-ScoutVmQuotas keeps that property-existence guard.

Two behaviour differences from the retired implementation, both deliberate:
  - a Get-AzVMUsage failure for one (subscription, location) pair now warns and skips that pair
    instead of terminating the whole quota pass;
  - a VM row with no location no longer produces an empty-string location lookup.

Both are the AB#5633 defect class: one bad row must not cost the caller every other row.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/Extraction/ResourceDetails/Get-AZTIVMQuotas.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Tracks ADO AB#5648 (Epic AB#5638). Original v1 implementation: Claudio Merola, 15th Oct 2024.
The caller's original Az context is restored by Get-ScoutVmQuotas in a finally block -- the
quota lookup switches context per subscription, and leaving the caller parked in the last one
was a real defect fixed once already (AB#368).
#>
function Get-AZSCVMQuotas {
    Param ($Subscriptions, $Resources)

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Getting VM Quota Details (src/collect, AB#5648)')

    # v1 iterated $Subscriptions with foreach, so a $null or empty list produced no rows and no
    # error -- but it still returned the typed envelope, which the collectors filter for.
    if (-not $Subscriptions) {
        return [PSCustomObject]@{
            'type'       = 'AZSC/VM/Quotas'
            'properties' = @()
        }
    }

    return Get-ScoutVmQuotas -Subscriptions @($Subscriptions) -Resources $Resources
}
