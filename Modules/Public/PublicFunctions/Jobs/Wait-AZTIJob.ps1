<#
.Synopsis
Wait for AZSC Jobs to Complete

.DESCRIPTION
This script waits for the completion of specified AZSC jobs.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/PublicFunctions/Jobs/Wait-AZSCJob.ps1

.COMPONENT
    This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Wait-AZSCJob {
    Param($JobNames, $JobType, $LoopTime)

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Jobs Collector.')

    $c = 0

    # Waiting only on State -eq 'Running' returns IMMEDIATELY for a job that is still
    # 'NotStarted'. Start-Job is asynchronous, so a freshly-created job sits in NotStarted for a
    # moment before its runspace picks it up. The caller then harvests it with Receive-Job and
    # destroys it with Remove-Job, so that category's data silently comes back EMPTY -- which is
    # exactly the non-deterministic Compute.json (5,158 bytes on one run, 470 on the next, same
    # tenant and scope). Wait on every non-terminal state instead. (AB#5629)
    $PendingStates = @('NotStarted', 'Running', 'Stopping', 'Suspending', 'Suspended')

    while (get-job -Name $JobNames | Where-Object { $_.State -in $PendingStates }) {
        $jb = @(get-job -Name $JobNames)
        $c = (((($jb.count - (@($jb | Where-Object { $_.State -in $PendingStates })).Count)) / $jb.Count) * 100)
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"$JobType Jobs Still Pending: "+[string](@($jb | Where-Object { $_.State -in $PendingStates })).count)
        $c = [math]::Round($c)
        Write-Progress -Id 1 -activity "Processing $JobType Jobs" -Status "$c% Complete." -PercentComplete $c
        Start-Sleep -Seconds $LoopTime
    }
    Write-Progress -Id 1 -activity "Processing $JobType Jobs" -Status "100% Complete." -Completed

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Jobs Complete.')
}
