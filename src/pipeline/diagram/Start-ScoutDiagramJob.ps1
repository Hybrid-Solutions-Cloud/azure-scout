<#
# Relocated from Modules/Public/PublicFunctions/Diagram for the v3 pipeline.
.Synopsis
Build the resource lookup the draw.io diagram builders consume.

.DESCRIPTION
Filters the resource set by the types the network and organisation diagrams draw, and returns
them as a hashtable keyed by the short names those builders expect.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/PublicFunctions/Diagram/Start-AZSCDiagramJob.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

Function Start-AZSCDiagramJob {
    Param($Resources, $Automation)
    # ── StrictMode boundary (AB#5633, revised by AB#5649) ────────────────────────────
    # v1 inventory engine (forked from microsoft/ARI), written without StrictMode: it reads
    # optional fields off Azure payloads whose shape varies by tenant. Removing this opt-out
    # altogether is AB#5667's job, with the recorded live-payload fixtures needed to do it
    # safely. StrictMode is dynamically scoped, so this covers this call tree only.
    Set-StrictMode -Off

    <#
        AB#5649 — this was 290 lines and is now a table.

        It used to be TWO copies of the same work behind an if/else on $Automation:

          * -Automation: Start-ThreadJob containing 27 `Where-Object` filters.
          * otherwise:   Start-Job containing 27 SEPARATE `[PowerShell]::Create()` runspaces,
                         one per resource type, each running a single Where-Object; then 27
                         BeginInvoke calls, a wait loop, 27 EndInvoke calls and 27 Dispose
                         calls — to perform 27 array filters over an in-memory collection.

        Both assembled the identical 27-key hashtable, so the two copies were pure duplication
        of a mapping that is really just data. The runspace copy also carried its own instance
        of the `$Job.Runspace.IsCompleted` no-op wait (AB#5629/AB#5633): PowerShellAsyncResult
        has no .Runspace, so the loop never waited and EndInvoke raced its own work.

        Filtering an in-memory array needs no concurrency at all. One pass over $Resources now
        bucket-sorts every type at once, which is also strictly less work than 27 passes.

        $Automation is kept on the signature for caller compatibility and is no longer read —
        there is no job left for it to choose a flavour of.
    #>

    # Key -> resource type. The keys are the names the diagram builders index by; several
    # deliberately differ from the type (AKS, VM, AppGtw…), which is why this stays an explicit
    # map rather than something derived from the type string.
    $TypeMap = [ordered]@{
        'AZVGWs'      = 'microsoft.network/virtualnetworkgateways'
        'AZLGWs'      = 'microsoft.network/localnetworkgateways'
        'AZVNETs'     = 'microsoft.network/virtualnetworks'
        'AZCONs'      = 'microsoft.network/connections'
        'AZEXPROUTEs' = 'microsoft.network/expressroutecircuits'
        'PIPs'        = 'microsoft.network/publicipaddresses'
        'AZVWAN'      = 'microsoft.network/virtualwans'
        'AZVHUB'      = 'microsoft.network/virtualhubs'
        'AZVPNSITES'  = 'microsoft.network/vpnsites'
        'AZVERs'      = 'microsoft.network/expressroutegateways'
        'AKS'         = 'microsoft.containerservice/managedclusters'
        'VMSS'        = 'microsoft.compute/virtualmachinescalesets'
        'NIC'         = 'microsoft.network/networkinterfaces'
        'PrivEnd'     = 'microsoft.network/privateendpoints'
        'VM'          = 'microsoft.compute/virtualmachines'
        'ARO'         = 'microsoft.redhatopenshift/openshiftclusters'
        'Kusto'       = 'microsoft.kusto/clusters'
        'AppGtw'      = 'microsoft.network/applicationgateways'
        'Databricks'  = 'microsoft.databricks/workspaces'
        'AppWeb'      = 'microsoft.web/sites'
        'APIM'        = 'microsoft.apimanagement/service'
        'LB'          = 'microsoft.network/loadbalancers'
        'Bastion'     = 'microsoft.network/bastionhosts'
        'FW'          = 'microsoft.network/azurefirewalls'
        'NetProf'     = 'microsoft.network/networkprofiles'
        'Container'   = 'microsoft.containerinstance/containergroups'
        'ANF'         = 'microsoft.netapp/netappaccounts/capacitypools/volumes'
    }

    # Bucket-sort in a single pass. The original compared with -eq, which is case-insensitive
    # for strings, so the types above are lower-cased and matched against a lower-cased key.
    $Buckets = @{}
    foreach ($Key in $TypeMap.Keys) { $Buckets[$TypeMap[$Key]] = [System.Collections.Generic.List[object]]::new() }

    foreach ($Resource in $Resources) {
        if ($null -eq $Resource) { continue }
        $Type = [string]$Resource.Type
        if (-not $Type) { continue }
        $Type = $Type.ToLowerInvariant()
        if ($Buckets.ContainsKey($Type)) { $Buckets[$Type].Add($Resource) }
    }

    $Variables = @{}
    foreach ($Key in $TypeMap.Keys) {
        $Matched = $Buckets[$TypeMap[$Key]]

        # $null for "none", NOT an empty collection — matching what `$Resources | Where-Object`
        # produced. The distinction is load-bearing downstream: under StrictMode, member
        # enumeration over an EMPTY collection throws "property cannot be found", while the same
        # read over $null is safe. That is the AB#5633 crash class; handing the diagram builders
        # empty lists instead of $null would walk straight back into it.
        $Variables[$Key] = if ($Matched.Count -eq 0) { $null }
                           elseif ($Matched.Count -eq 1) { $Matched[0] }
                           else { $Matched.ToArray() }
    }

    $Variables
}
