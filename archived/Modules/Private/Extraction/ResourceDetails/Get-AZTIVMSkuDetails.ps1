<#
.Synopsis
Module responsible for retrieving Azure VM SKU details.

.DESCRIPTION
This module retrieves details about Azure VM SKUs available in specific locations.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Private/1.ExtractionFunctions/ResourceDetails/Get-AZSCVMSkuDetails.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola, Olli Uronen (Seppohto)
#>
function Get-AZSCVMSkuDetails {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Internal function name, called by that exact name elsewhere in the module; renaming is a breaking change out of scope for a lint-only pass.')]
    Param ($Resources)

    # Same exposure as Get-AZSCVMQuotas: this runs in module scope, where StrictMode is in
    # force, over a $Resources array that mixes Resource Graph rows with REST API rows that
    # carry no TYPE property. A bare $_.TYPE aborts the run on the first such row. The ~176
    # inventory modules use this same filter shape safely because they execute inside fresh
    # runspaces where StrictMode is not set. (AB#5633)
    $VMTypes = @('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets')
    $vm = @($Resources | Where-Object {
            $null -ne $_ -and
            $_.PSObject.Properties.Name -contains 'TYPE' -and
            $_.TYPE -in $VMTypes
        })

    # -ExpandProperty throws under StrictMode on a row without the property; filter to rows
    # that actually carry a location first.
    $Locations = @($vm |
        Where-Object { $_.PSObject.Properties.Name -contains 'location' -and $_.location } |
        Select-Object -ExpandProperty location -Unique)

    $VMskuData = Foreach($location in $Locations)
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Getting VM SKU Details: '+$location)
            $tmp = [PSCustomObject]@{
                Location    = $location
                SKUs        = Get-AzComputeResourceSku $location -Debug:$false
            }
            $tmp
        }

    $VMSkuDetails = [PSCustomObject]@{
        'type'          = 'AZSC/VM/SKU'
        'properties'    = $VMskuData
    }

    return $VMSkuDetails
}