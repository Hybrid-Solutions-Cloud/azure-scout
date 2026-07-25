<#
.Synopsis
Module responsible for starting additional processing jobs for Azure Resources.

.DESCRIPTION
This module handles the execution of extra jobs such as Draw.IO diagrams, Security Center processing, Policy evaluations, and Advisory processing for Azure Resources.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/2.ProcessingFunctions/Start-AZSCExtraJobs.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Start-AZSCExtraJobs {
    Param ($SkipDiagram,
            $SkipAdvisory,
            $SkipPolicy,
            $SecurityCenter,
            $Subscriptions,
            $Resources,
            $Advisories,
            $DDFile,
            $DiagramCache,
            $FullEnv,
            $ResourceContainers,
            $Security,
            $PolicyDef,
            $PolicySetDef,
            $PolicyAssign,
            $Automation,
            $IncludeCosts,
            $CostData)
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


    # Resolve the full module path so background jobs can import it even when not in PSModulePath
    $LoadedModule = Get-Module -Name AzureScout
    if ($LoadedModule) {
        $AZSCModule = $LoadedModule.Path
    } else {
        $AZSCModule = 'AzureScout'
    }

    <######################################################### DRAW IO DIAGRAM JOB ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking if Draw.io Diagram Job Should be Run.')
    if (![bool]$SkipDiagram) {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Draw.io Diagram Processing Job.')
        Invoke-AZSCDrawIOJob -Subscriptions $Subscriptions -Resources $Resources -Advisories $Advisories -DDFile $DDFile -DiagramCache $DiagramCache -FullEnv $FullEnv -ResourceContainers $ResourceContainers -Automation $Automation -AZSCModule $AZSCModule
    }

    <######################################################### VISIO DIAGRAM JOB ######################################################################>
    <#
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking if Visio Diagram Job Should be Run.')
    if ($Diagram.IsPresent) {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Visio Diagram Processing Job.')
        Start-job -Name 'VisioDiagram' -ScriptBlock {

            If ($($args[5]) -eq $true) {
                $ModuSeq = (New-Object System.Net.WebClient).DownloadString($($args[7]) + '/Extras/VisioDiagram.ps1')
            }
            Else {
                $ModuSeq0 = New-Object System.IO.StreamReader($($args[0]) + '\Extras\VisioDiagram.ps1')
                $ModuSeq = $ModuSeq0.ReadToEnd()
                $ModuSeq0.Dispose()
            }

            $ScriptBlock = [Scriptblock]::Create($ModuSeq)

            $VisioRun = ([PowerShell]::Create()).AddScript($ScriptBlock).AddArgument($($args[1])).AddArgument($($args[2])).AddArgument($($args[3])).AddArgument($($args[4]))

            $VisioJob = $VisioRun.BeginInvoke()

            while ($VisioJob.IsCompleted -contains $false) {}

            $VisioRun.EndInvoke($VisioJob)

            $VisioRun.Dispose()

        } -ArgumentList $PSScriptRoot, $Subscriptions, $Resources, $Advisories, $DFile, $RunOnline, $Repo, $RawRepo   | Out-Null
    }
    #>

    <######################################################### SECURITY CENTER JOB ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking If Should Run Security Center Job.')
    if (![string]::IsNullOrEmpty($SecurityCenter))
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Security Processing Job.')
            Invoke-AZSCSecurityCenterJob -Subscriptions $Subscriptions -Automation $Automation -Resources $Resources -SecurityCenter $SecurityCenter -AZSCModule $AZSCModule
        }

    <######################################################### POLICY JOB ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking If Should Run Policy Job.')
    if (![bool]$SkipPolicy) {
        if (![string]::IsNullOrEmpty($PolicyAssign) -and ![string]::IsNullOrEmpty($PolicyDef))
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Policy Processing Job.')
                Invoke-AZSCPolicyJob -Subscriptions $Subscriptions -PolicySetDef $PolicySetDef -PolicyAssign $PolicyAssign -PolicyDef $PolicyDef -AZSCModule $AZSCModule -Automation $Automation
            }
    }

    <######################################################### ADVISORY JOB ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking If Should Run Advisory Job.')
    if (![bool]$SkipAdvisory) {
        if (![string]::IsNullOrEmpty($Advisories))
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Advisory Processing Job.')
                Invoke-AZSCAdvisoryJob -Advisories $Advisories -AZSCModule $AZSCModule -Automation $Automation
            }
    }

    <######################################################### SUBSCRIPTIONS JOB ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Subscriptions Processing job.')
    Invoke-AZSCSubJob -Subscriptions $Subscriptions -Automation $Automation -Resources $Resources -CostData $CostData -AZSCModule $AZSCModule
}
