<#
.Synopsis
Run the non-collector processing work (security, policy, advisory, subscriptions, diagram).

.DESCRIPTION
Runs the security-centre, policy, advisory and subscription processing in-process and returns
their results, then starts the draw.io diagram work. Formerly this started one background job
per item; see the AB#5649 notes on the function for why that changed.

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
    # ── StrictMode boundary ──────────────────────────────────────────────────────────
    # This is the v1 inventory engine, forked from microsoft/ARI, written without StrictMode
    # and carrying property reads over API payloads whose shape varies by tenant. StrictMode is
    # dynamically scoped, so turning it off here covers this call tree only; the assessment
    # platform under src/ keeps it in full force. Turning it on here is AB#5667's job, together
    # with the recorded live-payload fixtures needed to do it safely.
    Set-StrictMode -Off

    <#
        AB#5649 — these four ran as background jobs and now run in-process.

        Each was a wrapper whose entire body was "Start-Job { import-module <this module>;
        Start-AZSC<X>Job ... }". That bought no parallelism worth having and cost three things:

        1. THE SAME NotStarted RACE AS AB#5629, still live in v2.5.3. The harvest side in
           Start-AZSCExtraReports waited with
               while (get-job -Name 'Policy' | Where-Object { $_.State -eq 'Running' })
           which does not match a job that has not started yet. Start-Job is asynchronous, so
           that wait could fall straight through, Receive-Job would return nothing and
           Remove-Job would destroy the job — the Policy, Advisory, Security and Subscriptions
           sheets could each silently come back empty. The resource pipeline's copy of this bug
           was fixed; these four copies were missed.

        2. THE STRICTMODE LEAK. `import-module` inside the job re-imported this module, so
           module-scope StrictMode applied again inside the job even when the caller had opted
           out. That is why the v2.5.3 opt-out had to be repeated at 17 entry points rather
           than 5 — every one of these job bodies was one of them.

        3. SILENTLY WRONG ARGUMENTS. Invoke-AZSCSecurityCenterJob was called with
           `-SecurityCenter $SecurityCenter`, but its parameter block declared no such
           parameter. PowerShell does not reject an unknown named argument to a simple
           function — it collects it into $args and carries on — so $SecurityCenter was
           undefined inside the wrapper, $null crossed the job boundary as the -Security
           argument, and Start-AZSCSecCenterJob's `foreach ($1 in $Security)` iterated nothing.
           The Security Center sheet has been empty in every release that had one. Calling the
           function directly is what surfaced it, and it is fixed below by passing $Security.

        The four wrapper files (Invoke-AZTI{Advisory,Policy,SecurityCenter,Sub}Job.ps1) are
        deleted; there is nothing left for them to wrap. The draw.io diagram work still runs as
        a job and keeps its wrapper — that subsystem starts nested jobs of its own and is a
        separate piece of work.

        Returns a hashtable the reporting phase consumes instead of calling Receive-Job.
    #>

    $Results = @{
        Security      = $null
        Policy        = $null
        Advisory      = $null
        Subscriptions = $null
    }

    <######################################################### DRAW IO DIAGRAM JOB ######################################################################>

    # Resolve the full module path so the diagram job can import it even when not in PSModulePath
    $LoadedModule = Get-Module -Name AzureScout
    if ($LoadedModule) {
        $AZSCModule = $LoadedModule.Path
    } else {
        $AZSCModule = 'AzureScout'
    }

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking if Draw.io Diagram Job Should be Run.')
    if (![bool]$SkipDiagram) {
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Draw.io Diagram Processing Job.')
        Invoke-AZSCDrawIOJob -Subscriptions $Subscriptions -Resources $Resources -Advisories $Advisories -DDFile $DDFile -DiagramCache $DiagramCache -FullEnv $FullEnv -ResourceContainers $ResourceContainers -Automation $Automation -AZSCModule $AZSCModule
    }

    <######################################################### SECURITY CENTER ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking If Should Process Security Center.')
    if (![string]::IsNullOrEmpty($SecurityCenter))
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Security Center.')
            try {
                # $Security, NOT $SecurityCenter -- see note 3 above. $SecurityCenter is the
                # switch that says whether to do this at all; $Security carries the rows.
                $Results.Security = Start-AZSCSecCenterJob -Subscriptions $Subscriptions -Security $Security
            }
            catch {
                Write-Warning "[AzureScout] Security Center processing failed and was skipped: $($_.Exception.Message)"
            }
        }

    <######################################################### POLICY ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking If Should Process Policy.')
    if (![bool]$SkipPolicy) {
        if (![string]::IsNullOrEmpty($PolicyAssign) -and ![string]::IsNullOrEmpty($PolicyDef))
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Policy.')
                try {
                    $Results.Policy = Start-AZSCPolicyJob -Subscriptions $Subscriptions -PolicySetDef $PolicySetDef -PolicyAssign $PolicyAssign -PolicyDef $PolicyDef
                }
                catch {
                    Write-Warning "[AzureScout] Policy processing failed and was skipped: $($_.Exception.Message)"
                }
            }
    }

    <######################################################### ADVISORY ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking If Should Process Advisory.')
    if (![bool]$SkipAdvisory) {
        if (![string]::IsNullOrEmpty($Advisories))
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Advisory.')
                try {
                    $Results.Advisory = Start-AZSCAdvisoryJob -Advisories $Advisories
                }
                catch {
                    Write-Warning "[AzureScout] Advisory processing failed and was skipped: $($_.Exception.Message)"
                }
            }
    }

    <######################################################### SUBSCRIPTIONS ######################################################################>

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Subscriptions.')
    try {
        $Results.Subscriptions = Start-AZSCSubscriptionJob -Subscriptions $Subscriptions -Resources $Resources -CostData $CostData
    }
    catch {
        Write-Warning "[AzureScout] Subscription processing failed and was skipped: $($_.Exception.Message)"
    }

    $Results
}
