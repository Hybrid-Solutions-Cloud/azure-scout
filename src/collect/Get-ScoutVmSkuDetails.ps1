#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Per-location VM SKU capability details -- ported into src/collect from
    Modules/Private/Extraction/ResourceDetails/Get-AZTIVMSkuDetails.ps1 (AB#5639/5646).

.DESCRIPTION
    `Get-AzComputeResourceSku` is another ARM data-plane call (region-scoped, not
    subscription-scoped) with no Resource Graph table -- the same class of gap
    `Get-ScoutVmQuotas` fills. The type map this task derived from the 176 legacy collectors
    confirms the same three collectors (AKS, VirtualMachine, VirtualMachineScaleSet) also
    filter for a synthetic `'AZSC/VM/SKU'`-typed row alongside `'AZSC/VM/Quotas'`.

.PARAMETER Resources
    The mixed resource row set to derive the distinct set of locations from. Every row is
    guarded with a `PSObject.Properties` check before `type`/`location` is read -- the same
    mixed-array defect class `Get-ScoutVmQuotas` guards against (AB#5633).

.OUTPUTS
    `[pscustomobject]` with `type = 'AZSC/VM/SKU'` and `properties` holding one entry per
    distinct location actually in use: `Location`, `SKUs` (the full `Get-AzComputeResourceSku`
    result for that location). The literal `type` string is preserved EXACTLY as the legacy
    function emits it.

.NOTES
    Tracks ADO AB#5639 (Task AB#5646, Epic AB#5638).
#>
function Get-ScoutVmSkuDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object[]] $Resources
    )

    $vmTypes = @('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets')
    $vmRows = @(@($Resources) | Where-Object {
            $null -ne $_ -and
            $_.PSObject.Properties.Name -contains 'type' -and
            ([string] $_.type).ToLowerInvariant() -in $vmTypes
        })

    $locations = @(
        $vmRows | Where-Object { $_.PSObject.Properties.Name -contains 'location' -and $_.location } |
            Select-Object -ExpandProperty location -Unique
    )

    $skuData = foreach ($location in $locations) {
        try {
            $skus = Get-AzComputeResourceSku -Location $location -ErrorAction Stop
        }
        catch {
            Write-Warning "Get-ScoutVmSkuDetails: SKU lookup failed for location '$location' -- skipping: $($_.Exception.Message)"
            continue
        }
        [pscustomobject]@{
            Location = $location
            SKUs     = $skus
        }
    }

    return [pscustomobject]@{
        type       = 'AZSC/VM/SKU'
        properties = @($skuData)
    }
}
