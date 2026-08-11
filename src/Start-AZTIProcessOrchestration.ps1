#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Process orchestration for Azure Resource Inventory

.DESCRIPTION
This module orchestrates the processing of resources for Azure Resource Inventory.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/0.MainFunctions/Start-AZSCProcessOrchestration.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.9
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>

function Start-AZSCProcessOrchestration {
    # $Heavy is retained for caller compatibility but no longer does anything in this phase.
    # It only ever shrank the parallel job batch size to keep CPU and memory in check; with the
    # jobs gone (AB#5649) there is no batch to shrink, and peak memory is now one category at a
    # time regardless. It still applies to the extraction phase, which does its own throttling.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'File', Justification = "Declared to match this function's call signature -- callers invoke it with this named/positional argument; removing the parameter would break them even though this implementation does not need the value.")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Heavy', Justification = "Declared to match this function's call signature -- callers invoke it with this named/positional argument; removing the parameter would break them even though this implementation does not need the value.")]
    Param($Subscriptions, $Resources, $Retirements, $DefaultPath, $File, $Heavy, $InTag, $Automation, $Category, $CollectionHealth)
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


        Write-Progress -activity 'Azure Inventory' -Status "21% Complete." -PercentComplete 21 -CurrentOperation "Starting to process extracted data.."

        <######################################################### IMPORT UNSUPPORTED VERSION LIST ######################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Importing List of Unsupported Versions.')

        $Unsupported = Get-AZSCUnsupportedData

        <######################################################### RESOURCE PROCESSING ######################################################################>

        # AB#5649 -- the deterministic pipeline.
        #
        # This used to be four coordinated pieces of background-job machinery: create jobs
        # (Start-AZSCProcessJob, or Start-AZSCAutProcessJob under -Automation), wait for them
        # (Wait-AZSCJob), then harvest and destroy them (Build-AZSCCacheFiles). Every defect of
        # the v2.5.x wave lived in that coordination rather than in the collectors themselves --
        # a wait that excluded NotStarted jobs and then deleted them empty (AB#5629), a wait
        # loop reading a property that does not exist so it never waited at all, Get-Job
        # ordering that varied run to run, and the module re-import inside each job that leaked
        # StrictMode back in and forced the opt-out to 17 separate entry points.
        #
        # Collectors are pure functions of the resource set, so none of that concurrency was
        # ever required. Invoke-ScoutProcessing runs them in-process in a fixed order, contains
        # each collector's failure individually, and writes the same ReportCache layout. The
        # automation branch is gone because there are no jobs left for it to substitute -- both
        # modes now execute identical code and can no longer drift apart.
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing resources through the deterministic pipeline.')

        if ([bool]$Automation)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Resources')
            }

        $ProcessingSummary = Invoke-ScoutProcessing -Resources $Resources -Retirements $Retirements -Subscriptions $Subscriptions -DefaultPath $DefaultPath -InTag $InTag -Unsupported $Unsupported -Category $Category -CollectionHealth $CollectionHealth

        Remove-Variable -Name Unsupported -ErrorAction SilentlyContinue

        if ([bool]$Automation)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processed '+$ProcessingSummary.CollectorCount+' collectors across '+@($ProcessingSummary.Categories).Count+' categories.')
            }
        else
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Finished processing resources.')
            }

        Write-Progress -activity 'Azure Inventory' -Status "60% Complete." -PercentComplete 60 -CurrentOperation "Completed Data Processing Phase.."

}
