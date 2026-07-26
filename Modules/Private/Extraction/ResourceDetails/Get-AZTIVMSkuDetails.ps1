<#
.Synopsis
Parameter-translation shim: maps the v1 VM-SKU contract onto src/collect.

.DESCRIPTION
This function used to BE the inventory engine's VM SKU layer. It is now a shim over
Get-ScoutVmSkuDetails (src/collect/Get-ScoutVmSkuDetails.ps1), which is the single
implementation. AB#5648 retired the duplicate.

Get-AzComputeResourceSku is a region-scoped ARM call with no Resource Graph table -- the same
class of gap Get-ScoutVmQuotas fills. Only the distinct locations that actually contain a VM or
VMSS are queried.

The v1 contract is preserved exactly at this boundary: a single object with
`type = 'AZSC/VM/SKU'` and `properties` holding one `Location`/`SKUs` entry per distinct
location. Compute/VirtualMachine, Compute/VirtualMachineScaleSet and Containers/AKS match on
that literal type string, so it is load-bearing.

Same mixed-array exposure as Get-AZSCVMQuotas: a bare `$_.TYPE` on an ARM REST row that has no
TYPE property aborts the run on the first such row (AB#5633). Get-ScoutVmSkuDetails keeps the
property-existence guard, and the guard on `location` before `-ExpandProperty location`.

One deliberate behaviour difference from the retired implementation: a Get-AzComputeResourceSku
failure for one location now warns and skips that location instead of terminating the whole SKU
pass. One bad region must not cost the caller every other region.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/Extraction/ResourceDetails/Get-AZTIVMSkuDetails.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Tracks ADO AB#5648 (Epic AB#5638). Original v1 implementation: Claudio Merola, Olli Uronen.
#>
function Get-AZSCVMSkuDetails {
    Param ($Resources)

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Getting VM SKU Details (src/collect, AB#5648)')

    return Get-ScoutVmSkuDetails -Resources $Resources
}
