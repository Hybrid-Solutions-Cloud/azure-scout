#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Run the draw.io diagram build.

.DESCRIPTION
Builds the draw.io topology diagram for the collected resources.

.Link
https://github.com/thisismydemo/azure-scout/src/pipeline/Invoke-ScoutDrawIoJob.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Version: 3.6.5
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Invoke-AZSCDrawIOJob {
    Param($Subscriptions, $Resources, $Advisories, $DDFile, $DiagramCache, $FullEnv, $ResourceContainers, $Automation, $AZSCModule)

    <#
        AB#5649 — the last Wait-AZSCJob caller, and the last background job in the run
        orchestration.

        This used to branch on $Automation: automation called Start-AZSCDrawIODiagram directly,
        and every other run wrapped the identical call in `Start-Job -Name 'DrawDiagram'` whose
        body re-imported the module. Invoke-AzureScout then waited on that job name with
        Wait-AZSCJob and destroyed it with Remove-Job, several hundred lines later.

        Three reasons the job went:

        1. The automation branch already proved the direct call works — it has been the only
           code path in Azure Automation for as long as the branch has existed. Keeping a second
           implementation of the same call bought nothing but the chance to drift.
        2. `import-module` inside the job body re-applied module-scope StrictMode inside the job
           even when the caller had opted out. That is the mechanism that forced the v2.5.3
           opt-out to 17 entry points, and this was one of them.
        3. Failures inside the job surfaced only in DiagramLogFile.log, detached from the run.
           A diagram build that died left the run reporting success with no diagram and nothing
           on the console. It now raises through the caller's own trap and the run log.

        WHAT THIS COSTS: the diagram build no longer overlaps the Excel build. Measured on the
        live tenant it is ~1:40 of work that used to run alongside reporting. That is the
        deliberate trade — determinism and a visible failure over incidental concurrency, which
        is the whole premise of AB#5649. The automation path has always paid it.

        STILL JOB-BASED, tracked separately: the diagram builder's own internals —
        'Diagram_Organization' and 'Diagram_NetworkTopology' in Start-AZSCDrawIODiagram, and the
        nested Job_* fan-out inside Start-AZSCDiagramNetwork. Those do coarse-grained,
        genuinely long-running XML work and are a design question, not a mechanical collapse.
    #>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Draw.IO diagram build.')

    if ([bool]$Automation) { Write-Output 'Invoking Draw.Io main function.' }

    try
        {
            Start-AZSCDrawIODiagram -Subscriptions $Subscriptions -Resources $Resources -Advisories $Advisories -DDFile $DDFile -DiagramCache $DiagramCache -FullEnvironment $FullEnv -ResourceContainers $ResourceContainers -Automation $Automation -AZSCModule $AZSCModule
        }
    catch
        {
            # Contained: a diagram failure must not cost the caller their inventory report. It is
            # surfaced rather than buried in DiagramLogFile.log, which is what the job did.
            Write-Warning "[AzureScout] Draw.io diagram build failed and was skipped: $($_.Exception.Message)"

            if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
                Write-AZSCLog -Level 'WARN' -Message "Draw.io diagram build failed: $($_.Exception.Message)"
            }
        }
}
