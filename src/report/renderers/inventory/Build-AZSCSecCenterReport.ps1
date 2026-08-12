#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Module for Security Center Report

.DESCRIPTION
This script processes and creates the Security Center sheet in the Excel report.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Private/3.ReportingFunctions/Build-AZSCSecCenterReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Build-AZSCSecCenterReport {
    param($File, $Sec, $TableStyle)
    $condtxtsec = $(New-ConditionalText High -Range G:G
    New-ConditionalText High -Range L:L)

    # [PSCustomObject]$null throws ("cannot call a method on a null-valued expression") under
    # StrictMode — guard so a job that returned no Security Center data doesn't crash the report.
    $(if ($Sec) { [PSCustomObject]$Sec } else { @() }) |
    ForEach-Object { $_ } |
    Select-Object 'Subscription',
    'Resource Group',
    'Resource Type',
    'Resource Name',
    'Categories',
    'Control',
    'Severity',
    'Status',
    'Remediation',
    'Remediation Effort',
    'User Impact',
    'Threats' |
    Export-Excel -Path $File -WorksheetName 'SecurityCenter' -AutoSize -MaxAutoSizeRows 100 -MoveToStart -TableName 'SecurityCenter' -TableStyle $tableStyle -ConditionalText $condtxtsec
}