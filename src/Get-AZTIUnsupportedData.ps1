<#
.Synopsis
Retrieve unsupported data for Azure Resource Inventory

.DESCRIPTION
This module retrieves unsupported data from a predefined JSON file for Azure Resource Inventory.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/0.MainFunctions/Get-AZSCUnsupportedData.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Get-AZSCUnsupportedData {

    # AB#5662: Support.json moved from Modules/Private/Reporting/StyleFunctions to
    # src/report/renderers/inventory/style as part of the reporting-layer consolidation.
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $SupportFile = Join-Path -Path $RepoRoot -ChildPath 'src' -AdditionalChildPath 'report', 'renderers', 'inventory', 'style', 'Support.json'
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Validating file: '+$SupportFile)

    $Unsupported = Get-Content -Path $SupportFile | ConvertFrom-Json

    return $Unsupported
}
