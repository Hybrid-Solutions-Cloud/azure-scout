<#
.Synopsis
Module for Quota Report

.DESCRIPTION
This script processes and creates the Quota Usage sheet in the Excel report.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Private/3.ReportingFunctions/Build-AZSCQuotaReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Build-AZSCQuotaReport {
    param($File, $AzQuota, $TableStyle)

    # Guarded twice over. $AzQuota / $AzQuota.properties can be $null (no VM quota data
    # collected), and a plain property chain on $null throws under StrictMode. Separately,
    # $AzQuota.properties.Data is MEMBER ENUMERATION over a collection: under StrictMode that
    # reports 'Data' as missing whenever the enumeration yields nothing at all -- which is what
    # an empty or absent Data on every element produces. An estate with no VM quota rows is a
    # normal outcome, not an error. Accumulate element-wise instead. (AB#5633)
    $QuotaProperties = @()
    if ($AzQuota -and $AzQuota.PSObject.Properties.Name -contains 'properties') {
        $QuotaProperties = @($AzQuota.properties | Where-Object { $null -ne $_ })
    }

    $Total = 0
    foreach ($Quota in $QuotaProperties) {
        if ($Quota.PSObject.Properties.Name -contains 'Data') { $Total += @($Quota.Data).Count }
    }

    $tmp = foreach($Quota in $QuotaProperties)
    {
        if ($Quota.PSObject.Properties.Name -notcontains 'Data') { continue }
        foreach($Data in @($Quota.Data))
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