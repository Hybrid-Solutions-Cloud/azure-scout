#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Main module for Excel Report Building

.DESCRIPTION
This module is the main module for building the Excel Report.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/0.MainFunctions/Start-AZSCReporOrchestration.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
Function Start-AZSCReporOrchestration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Automation', Justification = "Declared to match this function's call signature -- callers invoke it with this named/positional argument; removing the parameter would break them even though this implementation does not need the value.")]
    Param($ReportCache,
    $SecurityCenter,
    $File,
    $Quotas,
    $SkipPolicy,
    $SkipAdvisory,
    $Automation,
    $TableStyle,
    $IncludeCosts,
    # Security / Policy / Advisory / Subscriptions results from the processing phase. These
    # used to be harvested from background jobs inside Start-AZSCExtraReports (AB#5649).
    $ExtraData)
    # ── StrictMode boundary (AB#5633) ────────────────────────────────────────────────
    # This is the v1 inventory engine, forked from microsoft/ARI. It was written without
    # StrictMode and carries ~800 property reads that are only valid without it -- chained
    # reads over API payloads whose shape varies by tenant, and member enumeration over
    # collections that are legitimately empty.
    #
    # The v2 assessment platform under src/ sets `Set-StrictMode -Version Latest` at FILE
    # scope, and AzureScout.psm1 dot-sources those files, so StrictMode was silently applied
    # to the whole module -- this engine included. Nothing here was ever tested under it.
    # The result was a run that aborted on a perfectly normal Azure response, in a different
    # place on every tenant, because the faults are data-dependent: an empty API result set,
    # an estate with no VMs, a subscription with no quota rows.
    #
    # StrictMode is dynamically scoped, so turning it off here covers this call tree only.
    # The assessment platform is invoked from Invoke-AzureScout's own scope and keeps
    # StrictMode in full force -- it was written for it and its tests depend on it.
    #
    # This restores the behaviour v1 shipped with for years. It is not a licence to write
    # sloppy code here: the genuine defects found alongside this (a job wait that never
    # waited, an unreachable error fallback, a rethrow that destroyed optional data) were
    # fixed properly rather than papered over.
    Set-StrictMode -Off


    Write-Progress -activity 'Azure Inventory' -Status "65% Complete." -PercentComplete 65 -CurrentOperation "Starting the Report Phase.."

    <############################################################## REPORT CREATION ###################################################################>
    try {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Resource Reporting Cache.')
        Start-AZSCExcelJob -ReportCache $ReportCache -TableStyle $TableStyle -File $File

        <############################################################## REPORT EXTRA DETAILS ###################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Reporting Extra Details.')
        Start-AZSCExcelExtraData -File $File

        <############################################################## EXTRA REPORTS ###################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Default Data Reporting.')

        Start-AZSCExtraReports -File $File -Quotas $Quotas -SecurityCenter $SecurityCenter -SkipPolicy $SkipPolicy -SkipAdvisory $SkipAdvisory -IncludeCosts $IncludeCosts -TableStyle $TableStyle -ReportCache $ReportCache -ExtraData $ExtraData
    } catch {
        Write-Warning "Excel export failed (the file might be locked by another process). Skipping Excel generation. Error: $_"
    }

}
