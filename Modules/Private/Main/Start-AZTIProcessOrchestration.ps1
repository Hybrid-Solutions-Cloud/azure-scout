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
    Param($Subscriptions, $Resources, $Retirements, $DefaultPath, $File, $Heavy, $InTag, $Automation, $Category)
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

        <######################################################### RESOURCE GROUP JOB ######################################################################>

        if ([bool]$Automation)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Resources in Automation Mode')

                Start-AZSCAutProcessJob -Resources $Resources -Retirements $Retirements -Subscriptions $Subscriptions -Heavy $Heavy -InTag $InTag -Unsupported $Unsupported -Category $Category -DefaultPath $DefaultPath
            }
        else
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Resources in Regular Mode')

                Start-AZSCProcessJob -Resources $Resources -Retirements $Retirements -Subscriptions $Subscriptions -DefaultPath $DefaultPath -InTag $InTag -Heavy $Heavy -Unsupported $Unsupported -Category $Category
            }

        Remove-Variable -Name Unsupported -ErrorAction SilentlyContinue

        <############################################################## RESOURCES PROCESSING #############################################################>

        if ([bool]$Automation)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Waiting for Resource Jobs to Complete in Automation Mode')
                Get-Job | Where-Object {$_.name -like 'ResourceJob_*'} | Wait-Job
                $JobNames = @(Get-Job | Where-Object {$_.name -like 'ResourceJob_*'} | ForEach-Object { $_.Name })
            }
        else
            {
                $JobNames = @(Get-Job | Where-Object {$_.name -like 'ResourceJob_*'} | ForEach-Object { $_.Name })
                Wait-AZSCJob -JobNames $JobNames -JobType 'Resource' -LoopTime 5
            }

        if ([bool]$Automation)
            {
                Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Resources in Automation Mode')
            }
        else
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Finished Waiting for Resource Jobs.')
            }

        Build-AZSCCacheFiles -DefaultPath $DefaultPath -JobNames $JobNames

        Write-Progress -activity 'Azure Inventory' -Status "60% Complete." -PercentComplete 60 -CurrentOperation "Completed Data Processing Phase.."

}
