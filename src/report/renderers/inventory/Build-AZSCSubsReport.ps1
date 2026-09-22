<#
.Synopsis
Module for Subscription Report

.DESCRIPTION
This script processes and creates the Subscription sheet in the Excel report.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/3.ReportingFunctions/Build-AZSCSubsReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Build-AZSCSubsReport {
    param($File, $Sub, $IncludeCosts, $TableStyle)
    # Guarded: $Sub can be $null (job returned no subscription data), and a plain property
    # chain / .count on that throws under StrictMode.
    $SubUniqueCount = if ($Sub) { @($Sub.Subscription | Select-Object -Unique).count } else { 0 }
    $TableName = ('SubsTable_'+$SubUniqueCount)

    # ImportExcel resolves a -Style range against the written worksheet. On a sheet with ZERO
    # data rows that range resolves to nothing and Set-ExcelRange throws "The property
    # 'HorizontalAlignment' cannot be found on this object" (verified against ImportExcel
    # 7.8.10). -TableName has the same problem: there is no range to turn into a table. So the
    # styling and table arguments are only supplied when there is at least one row; an empty
    # subscription set still produces the worksheet, just unstyled, instead of killing the run
    # after extraction and processing have already succeeded. (AB#5567)
    if ([bool]$IncludeCosts)
        {
            $Rows = @(
                $(if ($Sub) { [PSCustomObject]$Sub } else { @() }) |
                    ForEach-Object { $_ } |
                    Select-Object 'Subscription',
                    'Resource Group',
                    'Location',
                    'Resource Type',
                    'Service Name',
                    'Currency',
                    'Month',
                    'Year',
                    'Cost',
                    'Detailed Cost'
            )

            $ExcelArgs = @{ Path = $File; WorksheetName = 'Subscriptions' }
            if ($Rows.Count -gt 0)
                {
                    $Style = @()
                    $Style += New-ExcelStyle -AutoSize -HorizontalAlignment Center -NumberFormat '0'
                    $Style += New-ExcelStyle -Width 55 -NumberFormat '$#,#########0.000000000' -Range J:J
                    $Style += New-ExcelStyle -AutoSize -NumberFormat '$#,##0.00' -Range I:I
                    $ExcelArgs.TableName  = $TableName
                    $ExcelArgs.TableStyle = $TableStyle
                    $ExcelArgs.Style      = $Style
                }
            $Rows | Export-Excel @ExcelArgs
        }
    else
        {
            $Rows = @(
                $(if ($Sub) { [PSCustomObject]$Sub } else { @() }) |
                    ForEach-Object { $_ } |
                    Select-Object 'Subscription',
                    'Resource Group',
                    'Location',
                    'Resource Type',
                    'Resources Count'
            )

            $ExcelArgs = @{ Path = $File; WorksheetName = 'Subscriptions'; AutoSize = $true; MaxAutoSizeRows = 100 }
            if ($Rows.Count -gt 0)
                {
                    $ExcelArgs.TableName  = $TableName
                    $ExcelArgs.TableStyle = $TableStyle
                    $ExcelArgs.Style      = New-ExcelStyle -HorizontalAlignment Center -NumberFormat '0'
                }
            $Rows | Export-Excel @ExcelArgs
        }

}