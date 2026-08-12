#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
# Relocated from Modules/Public/PublicFunctions/Jobs for the v3 pipeline.
.Synopsis
Start Security Center Job Module

.DESCRIPTION
This script processes and creates the Security Center sheet based on security resources.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Public/PublicFunctions/Jobs/Start-AZSCSecCenterJob.ps1

.COMPONENT
    This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Start-AZSCSecCenterJob {
    param($Subscriptions,$Security)
    # ── StrictMode boundary (AB#5633, revised by AB#5649) ────────────────────────────
    # v1 inventory engine (forked from microsoft/ARI), written without StrictMode: it reads
    # optional fields off Azure payloads whose shape varies by tenant, so a Defender assessment
    # or Advisor recommendation that simply omits one would abort the run.
    #
    # This function is now CALLED DIRECTLY by Start-AZSCExtraJobs, in-process. It used to run
    # inside a Start-Job script block that re-imported the module, which re-applied module-scope
    # StrictMode inside the job even when the caller had opted out -- that is why the v2.5.3
    # opt-out had to be repeated at 17 entry points. With the job gone, this opt-out covers the
    # functions own call tree and nothing else. Removing it altogether is AB#5667s job, with
    # the recorded live-payload fixtures needed to do it safely.
    Set-StrictMode -Off

        $obj = ''
        $tmp = @()

        foreach ($1 in $Security) {
            $data = $1.PROPERTIES

            # Defender assessment resource IDs are NOT all resource-scoped. A subscription- or
            # resource-group-scoped assessment looks like
            #   /subscriptions/<id>/providers/Microsoft.Security/assessments/<name>
            # which splits into 7 segments, so the fixed [7] and [8] reads below threw
            # "Index was outside the bounds of the array" and killed the whole Security Center
            # worksheet -- and with it the run. Read segments defensively. (AB#5633)
            $IdSegments = @()
            if ($data -and $data.resourceDetails -and $data.resourceDetails.Id) {
                $IdSegments = [string]::Concat($data.resourceDetails.Id).Split('/')
            }
            $SegAt = { param($i) if ($IdSegments.Count -gt $i) { $IdSegments[$i] } else { '' } }

            $sub1 = $Subscriptions | Where-Object { $_.id -eq (& $SegAt 2) }

            $obj = @{
                'Subscription'       = $sub1.Name;
                'Resource Group'     = $1.RESOURCEGROUP;
                'Resource Type'      = (& $SegAt 7);
                'Resource Name'      = (& $SegAt 8);
                'Categories'         = [string]$data.metadata.categories;
                'Control'            = $data.displayName;
                'Severity'           = $data.metadata.severity;
                'Status'             = $data.status.code;
                'Remediation'        = $data.metadata.remediationDescription;
                'Remediation Effort' = $data.metadata.implementationEffort;
                'User Impact'        = $data.metadata.userImpact;
                'Threats'            = [string]$data.metadata.threats
            }
            $tmp += $obj
        }
        $tmp
}
