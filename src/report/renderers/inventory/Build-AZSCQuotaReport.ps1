#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    #
    # The guard has to filter, not just wrap: `@($null).Count` is 1, NOT 0, so the original
    # `if (@($ExcelVar).Count -gt 0)` was true even when the foreach above produced nothing and
    # $ExcelVar was $null -- it then read $null[0].Total and only escaped a crash because
    # Start-AZSCReporOrchestration runs this call tree with `Set-StrictMode -Off`, silently
    # yielding the table name 'QuotaTable_' instead of 'QuotaTable_0'. Same defect class as the
    # v2.6.0 empty-Excel-loop and the v2.7.0 Invoke-Collect subscription-resolution defects.
    # $ExcelVar itself is deliberately left alone -- the rest of this function consumes it.
    # (AB#5666)
    $QuotaRows = @($ExcelVar | Where-Object { $null -ne $_ })
    $TableName = if ($QuotaRows.Count -gt 0) { 'QuotaTable_' + $QuotaRows[0].Total } else { 'QuotaTable_0' }
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