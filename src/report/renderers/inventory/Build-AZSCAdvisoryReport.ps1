#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Module for Advisory Report

.DESCRIPTION
This script processes and creates the Advisory sheet in the Excel report.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Private/3.ReportingFunctions/Build-AZSCAdvisoryReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.9
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Build-AZSCAdvisoryReport {
    param($File, $Adv, $TableStyle)
    $condtxtadv = @()
    $condtxtadv += New-ConditionalText High -Range H:H
    $condtxtadv += New-ConditionalText Security -Range G:G -BackgroundColor Wheat

    $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '#,##0.00' -Range O:O

    # [PSCustomObject]$null throws ("cannot call a method on a null-valued expression") under
    # StrictMode — guard so a job that returned no Advisory data doesn't crash the report.
    $(if ($Adv) { [PSCustomObject]$Adv } else { @() }) |
    ForEach-Object { $_ } |
    Select-Object 'Subscription',
    'Resource Group',
    'Resource Type',
    'Name',
    'Detailed Type',
    'Detailed Name',
    'Category',
    'Impact',
    'Description',
    'SKU',
    'Term',
    'Look-back Period',
    'Quantity',
    'Savings Currency',
    'Annual Savings',
    'Savings Region' |
    Export-Excel -Path $File -WorksheetName 'Advisor' -AutoSize -MaxAutoSizeRows 100 -TableName 'AzureAdvisory' -MoveToStart -TableStyle $tableStyle -Style $Style -ConditionalText $condtxtadv
}