<#
.Synopsis
Module for Quota Report

.DESCRIPTION
This script processes and creates the Quota Usage sheet in the Excel report.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/3.ReportingFunctions/Build-AZSCQuotaReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Build-AZSCQuotaReport {
    param($File, $AzQuota, $TableStyle)

    # Guarded: $AzQuota / $AzQuota.properties can be $null (e.g. no VM quota data collected),
    # and a plain property chain on $null throws under StrictMode.
    $Total = if ($AzQuota -and $AzQuota.properties) { @($AzQuota.properties.Data).count } else { 0 }
    $tmp = foreach($Quota in $AzQuota.properties)
    {
        foreach($Data in $Quota.Data)
            {
                $FreevCPU = ''
                if($Data.Name.LocalizedValue -like '*vCPUs'){$FreevCPU = $Data.limit - $Data.CurrentValue}
                $obj = @{
                    'Subscription' = $Quota.Subscription;
                    'Region' = $Quota.Location;
                    'Current Usage' = $Data.currentValue;
                    'Limit' = $Data.limit;
                    'Quota' = $Data.Name.LocalizedValue;
                    'vCPUs Available' = $FreevCPU;
                    'Total' = $Total
                }
                $obj
            }
    }

    $ExcelVar = $tmp

    # Guarded: indexing [0] into a $null/empty $ExcelVar (no quota data at all) throws
    # "Cannot index into a null array" under StrictMode.
    $TableName = if (@($ExcelVar).Count -gt 0) { 'QuotaTable_' + $ExcelVar[0].Total } else { 'QuotaTable_0' }
    # [PSCustomObject]$null throws ("cannot call a method on a null-valued expression") under
    # StrictMode — guard so an environment with zero VM quota data doesn't crash the report.
    $(if ($ExcelVar) { [PSCustomObject]$ExcelVar } else { @() }) |
    ForEach-Object { $_ } |
    Select-Object -Unique 'Subscription',
    'Region',
    'Current Usage',
    'Limit',
    'Quota',
    'vCPUs Available' |
    Export-Excel -Path $File -WorksheetName 'Quota Usage' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $TableStyle -Numberformat '0' -MoveToEnd
}