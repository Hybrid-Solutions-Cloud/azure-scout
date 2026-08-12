#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Module for Reporting Results Output

.DESCRIPTION
This script outputs the results of the Azure Resource Inventory report generation.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/3.ReportingFunctions/StyleFunctions/Out-AZSCReportResults.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Out-AZSCReportResults {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Called by name from src/Invoke-AzureScout.ps1 (outside this task''s src/report+src/assess scope) plus tests; renaming would break out-of-scope callers.')]
    param (
        [string]$Measure,
        [string]$ResourcesCount,
        [string]$TotalRes,
        [string]$File,
        [string]$AdvisoryData,
        [string]$PolicyData,
        [string]$SecurityCenterData,
        [string]$DDFile,
        [switch]$ExcelRendered,
        $SkipAdvisory,
        $SkipPolicy,
        $SecurityCenter,
        $SkipAPIs,
        $SkipDiagram
    )

    Write-Host ('Report complete. Total command time (including guided setup): ') -NoNewline -ForegroundColor Green
    Write-Host $Measure -ForegroundColor Cyan
    Write-Host ('Total Resources on Azure: ') -NoNewline
    Write-Host $ResourcesCount -ForegroundColor Cyan
    if ($ExcelRendered) {
        Write-Host ('Total Resources on Excel: ') -NoNewline
        Write-Host $TotalRes -ForegroundColor Cyan
    }
    if (![bool]$SkipAdvisory)
        {
            if(![string]::IsNullOrEmpty($AdvisoryData))
            {
                Write-Host ('Total Advisories: ') -NoNewline
                write-host $AdvisoryData -ForegroundColor Cyan
            }
        }
    if (![bool]$SkipPolicy -and ![bool]$SkipAPIs)
        {
            if(![string]::IsNullOrEmpty($PolicyData))
                {
                    Write-Host ('Total Policies: ') -NoNewline
                    write-host $PolicyData -ForegroundColor Cyan
                }
        }
    if ([bool]$SecurityCenter)
        {
            if(![string]::IsNullOrEmpty($SecurityCenterData))
                {
                    Write-Host ('Total Security Advisories: ' + $SecurityCenterData)
                }
        }

    if ($ExcelRendered) {
        Write-Host ''
        Write-Host ('Excel file saved at: ') -NoNewline
        write-host $File -ForegroundColor Cyan
        Write-Host ''
    }

    if(![bool]$SkipDiagram)
        {
            Write-Host ('Draw.io Diagram file saved at: ') -NoNewline
            write-host $DDFile -ForegroundColor Cyan
            Write-Host ''
        }
}
