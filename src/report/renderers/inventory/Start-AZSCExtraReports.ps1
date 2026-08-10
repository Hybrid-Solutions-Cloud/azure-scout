#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Module for Extra Reports

.DESCRIPTION
This script processes and creates additional report sheets such as Quotas, Security Center, Policies, and Advisory.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/3.ReportingFunctions/Start-AZSCExtraReports.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Start-AZSCExtraReports {
    # $ExtraData is the hashtable returned by Start-AZSCExtraJobs — Security, Policy, Advisory
    # and Subscriptions. It replaces the Receive-Job harvest that used to sit in this function
    # (AB#5649); see the note at each use site.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Called by name from src/Invoke-AzureScout.ps1, src/Start-AZTIReporOrchestration.ps1 and src/pipeline/Start-ScoutExtraJobs.ps1 (outside this task''s src/report+src/assess scope) plus several tests; renaming would break out-of-scope callers.')]
    Param($File, $Quotas, $SecurityCenter, $SkipPolicy, $SkipAdvisory, $IncludeCosts, $TableStyle, $ReportCache, $ExtraData)

    if ($null -eq $ExtraData) { $ExtraData = @{} }

    Write-Progress -activity 'Azure Inventory' -Status "70% Complete." -PercentComplete 70 -CurrentOperation "Reporting Extra Resources.."

    <################################################ QUOTAS #######################################################>

    if(![string]::IsNullOrEmpty($Quotas))
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Quota Usage Sheet.')
            Write-Progress -Id 1 -activity 'Azure Resource Inventory Quota Usage' -Status "50% Complete." -PercentComplete 50 -CurrentOperation "Building Quota Sheet"

            Build-AZSCQuotaReport -File $File -AzQuota $Quotas -TableStyle $TableStyle

            Write-Progress -Id 1 -activity 'Azure Resource Inventory Quota Usage' -Status "100% Complete." -Completed
        }

    <################################################ SECURITY CENTER #######################################################>

    # AB#5649 — the four harvests below used to be
    #     while (get-job -Name 'X' | Where-Object { $_.State -eq 'Running' }) { ... }
    #     $Data = Receive-Job -Name 'X'; Remove-Job -Name 'X'
    # which is the AB#5629 defect in four more places: 'Running' does not match a job that is
    # still 'NotStarted', so the wait could fall straight through, Receive-Job returned nothing
    # and Remove-Job destroyed the job — the sheet silently came back empty. The data is now
    # computed in-process during the processing phase and handed over directly.
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking if Should Generate Security Center Sheet.')
    if ([bool]$SecurityCenter) {
        $Sec = $ExtraData['Security']
        if ($null -ne $Sec)
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Security Center Sheet.')
                Write-Progress -Id 1 -activity 'Processing Security Center Advisories' -Status "50% Complete." -PercentComplete 50

                Build-AZSCSecCenterReport -File $File -Sec $Sec -TableStyle $TableStyle

                Write-Progress -Id 1 -activity 'Processing Security Center Advisories'  -Status "100% Complete." -Completed
            }

    }

    <################################################ POLICY #######################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking if Should Generate Policy Sheet.')
    if (![bool]$SkipPolicy) {
        $Pol = $ExtraData['Policy']
        if ($null -ne $Pol)
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Policy Sheet.')
                Write-Progress -Id 1 -activity 'Processing Policies' -Status "50% Complete." -PercentComplete 50

                Build-AZSCPolicyReport -File $File -Pol $Pol -TableStyle $TableStyle

                Write-Progress -Id 1 -activity 'Processing Policies'  -Status "100% Complete." -Completed
            }
    }

    <################################################ ADVISOR #######################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking if Should Generate Advisory Sheet.')
    if (![bool]$SkipAdvisory) {
        $Adv = $ExtraData['Advisory']
        if ($null -ne $Adv)
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Advisor Sheet.')
                Write-Progress -Id 1 -activity 'Processing Advisories' -Status "50% Complete." -PercentComplete 50

                Build-AZSCAdvisoryReport -File $File -Adv $Adv -TableStyle $TableStyle

                Write-Progress -Id 1 -activity 'Processing Advisories'  -Status "100% Complete." -Completed
            }
    }

    <################################################################### SUBSCRIPTIONS ###################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Subscription sheet.')

    Write-Progress -activity 'Azure Resource Inventory Subscriptions' -Status "50% Complete." -PercentComplete 50 -CurrentOperation "Building Subscriptions Sheet"

    $AzSubs = $ExtraData['Subscriptions']

    Build-AZSCSubsReport -File $File -Sub $AzSubs -IncludeCosts $IncludeCosts -TableStyle $TableStyle

    Clear-AZSCMemory

    Write-Progress -activity 'Azure Resource Inventory Subscriptions' -Status "100% Complete." -Completed

    Write-Progress -activity 'Azure Inventory' -Status "80% Complete." -PercentComplete 80 -CurrentOperation "Completed Extra Resources Reporting.."

    <################################################ PHASE 10 — SPECIALIZED TABS #######################################################>

    if ($ReportCache) {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Building Phase 10 specialized report tabs.')

        Write-Progress -Id 1 -activity 'Building Cost Management tab' -Status "50% Complete." -PercentComplete 50
        Build-AZSCCostManagementReport -File $File -ReportCache $ReportCache -TableStyle $TableStyle
        Write-Progress -Id 1 -activity 'Building Cost Management tab' -Completed

        Write-Progress -Id 1 -activity 'Building Security Overview tab' -Status "50% Complete." -PercentComplete 50
        Build-AZSCSecurityOverviewReport -File $File -ReportCache $ReportCache -TableStyle $TableStyle
        Write-Progress -Id 1 -activity 'Building Security Overview tab' -Completed

        Write-Progress -Id 1 -activity 'Building Azure Update Manager tab' -Status "50% Complete." -PercentComplete 50
        Build-AZSCUpdateManagerReport -File $File -ReportCache $ReportCache -TableStyle $TableStyle
        Write-Progress -Id 1 -activity 'Building Azure Update Manager tab' -Completed

        Write-Progress -Id 1 -activity 'Building Azure Monitor tab' -Status "50% Complete." -PercentComplete 50
        Build-AZSCMonitorReport -File $File -ReportCache $ReportCache -TableStyle $TableStyle
        Write-Progress -Id 1 -activity 'Building Azure Monitor tab' -Completed
    }
}