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
    # ── StrictMode boundary (AB#5633) ────────────────────────────────────────────────
    # v1 inventory engine (forked from microsoft/ARI), written without StrictMode. These job
    # functions run inside Start-Job script blocks that RE-IMPORT the module, so module-scope
    # StrictMode -- leaked in by src/*.ps1 setting it at file scope -- applies again inside the
    # job even though the calling orchestrator opted out. The opt-out has to be on the function
    # itself. Without it, a Defender assessment or Advisor recommendation whose payload simply
    # omits an optional field aborts the whole run.
    Set-StrictMode -Off


    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Jobs Collector.')

    $c = 0

    # Nothing to wait for is a valid state, not an error. Get-Job -Name rejects an empty or
    # null-containing collection with "Cannot validate argument on parameter 'Name'", so a run
    # whose jobs had all already completed and been harvested died here instead of carrying on
    # to build the report. Callers derive $JobNames from a Get-Job filter that can legitimately
    # match nothing. (AB#5633)
    $JobNames = @($JobNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($JobNames.Count -eq 0) {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"No pending $JobType jobs to wait for.")
        Write-Progress -Id 1 -activity "Processing $JobType Jobs" -Status "100% Complete." -Completed
        return
    }

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
