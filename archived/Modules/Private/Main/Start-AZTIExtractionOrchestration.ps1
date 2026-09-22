<#
.Synopsis
Extraction orchestration for Azure Resource Inventory

.DESCRIPTION
This module orchestrates the extraction of resources for Azure Resource Inventory.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Private/0.MainFunctions/Start-AZSCExtractionOrchestration.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.11
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Start-AZSCExtractionOrchestration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Automation', Justification = "Declared to match this function's call signature -- callers invoke it with this named/positional argument; removing the parameter would break them even though this implementation does not need the value.")]
    Param($ManagementGroup, $Subscriptions, $SubscriptionID, $SkipPolicy, $ResourceGroup, $SecurityCenter, $SkipAdvisory, $IncludeTags, $TagKey, $TagValue, $SkipAPIs, $SkipVMDetails, $IncludeCosts, $Automation, $AzureEnvironment,
        [ValidateSet('All', 'ArmOnly', 'EntraOnly')]
        [string]$Scope = 'All',
        [string]$TenantID,
        [switch]$IncludeDevOps,
        [string[]]$DevOpsOrganization,
        [string]$DevOpsPat
    )
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


    $Resources = @()
    $ResourceContainers = @()
    $Advisories = @()
    $Security = @()
    $Retirements = @()
    $EntraResources = @()
    $PolicyAssign = $null
    $PolicyDef = $null
    $PolicySetDef = $null
    $Costs = $null
    $VMQuotas = $null

    # ── ARM Extraction (skip when Scope = EntraOnly) ──
    if ($Scope -ne 'EntraOnly') {
        $GraphData = Start-AZSCGraphExtraction -ManagementGroup $ManagementGroup -Subscriptions $Subscriptions -SubscriptionID $SubscriptionID -ResourceGroup $ResourceGroup -SecurityCenter $SecurityCenter -SkipAdvisory $SkipAdvisory -IncludeTags $IncludeTags -TagKey $TagKey -TagValue $TagValue -AzureEnvironment $AzureEnvironment

        $Resources = $GraphData.Resources
        $ResourceContainers = $GraphData.ResourceContainers
        $Advisories = $GraphData.Advisories
        $Security = $GraphData.Security
        $Retirements = $GraphData.Retirements

        Remove-Variable -Name GraphData -ErrorAction SilentlyContinue

        if(![bool]$SkipAPIs)
            {
                Write-Progress -activity 'Azure Inventory' -Status "12% Complete." -PercentComplete 12 -CurrentOperation "Starting API Extraction.."
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Getting API Resources.')
                $APIResults = Get-AZSCAPIResources -Subscriptions $Subscriptions -AzureEnvironment $AzureEnvironment -SkipPolicy $SkipPolicy
                # Read element-wise, NOT via member enumeration ($APIResults.ReservationRecomen).
                # The module runs under Set-StrictMode -Version Latest (every src/*.ps1 sets it at
                # file scope and the .psm1 dot-sources them), and member enumeration throws
                # "The property 'X' cannot be found on this object" when the enumeration yields
                # nothing at all -- which is exactly what an EMPTY collection on every element
                # produces. An empty collection is a normal Azure response: a subscription with no
                # reservation recommendations returns { "value": [] }, so a healthy tenant was
                # aborting the whole run here. $null values were never the problem; empty ones
                # were. (AB#5633)
                $Resources += Get-AZSCCollectedValue -InputObject $APIResults -Name 'ResourceHealth'
                $Resources += Get-AZSCCollectedValue -InputObject $APIResults -Name 'ManagedIdentities'
                $Resources += Get-AZSCCollectedValue -InputObject $APIResults -Name 'AdvisorScore'
                $Resources += Get-AZSCCollectedValue -InputObject $APIResults -Name 'ReservationRecomen'
                $PolicyAssign = Get-AZSCCollectedValue -InputObject $APIResults -Name 'PolicyAssign'
                $PolicyDef = Get-AZSCCollectedValue -InputObject $APIResults -Name 'PolicyDef'
                $PolicySetDef = Get-AZSCCollectedValue -InputObject $APIResults -Name 'PolicySetDef'
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'API Resource Inventory Finished.')
                Remove-Variable APIResults -ErrorAction SilentlyContinue
            }

        if ([bool]$IncludeCosts) {
            $Costs = Get-AZSCCostInventory -Subscriptions $Subscriptions -Days 60 -Granularity 'Monthly'
        }

        if (![bool]$SkipVMDetails)
            {
                Write-Host 'Gathering VM Extra Details: ' -NoNewline
                Write-Host 'Quotas' -ForegroundColor Cyan
                Write-Progress -activity 'Azure Inventory' -Status "13% Complete." -PercentComplete 13 -CurrentOperation "Starting VM Details Extraction.."

                $VMQuotas = Get-AZSCVMQuotas -Subscriptions $Subscriptions -Resources $Resources

                $Resources += $VMQuotas

                # NOTE: $VMQuotas is intentionally NOT removed here — it is returned
                # separately as the 'Quotas' field of $ReturnData below. Removing it
                # (as the original code did) left 'Quotas' permanently null.

                Write-Host 'Gathering VM Extra Details: ' -NoNewline
                Write-Host 'Size SKU' -ForegroundColor Cyan

                $VMSkuDetails = Get-AZSCVMSkuDetails -Resources $Resources

                $Resources += $VMSkuDetails

                Remove-Variable -Name VMSkuDetails -ErrorAction SilentlyContinue

            }
    }
    else {
        Write-Host 'Scope is EntraOnly — ' -NoNewline -ForegroundColor Yellow
        Write-Host 'Skipping ARM resource extraction' -ForegroundColor Yellow
    }

    # ── Entra ID Extraction (when Scope = All or EntraOnly) ──
    if ($Scope -in @('All', 'EntraOnly')) {
        if ([string]::IsNullOrEmpty($TenantID)) {
            Write-Warning 'TenantID is required for Entra ID extraction but was not provided. Skipping Entra extraction.'
        }
        else {
            Write-Progress -activity 'Azure Inventory' -Status "15% Complete." -PercentComplete 15 -CurrentOperation "Starting Entra ID Extraction.."
            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Starting Entra ID extraction for tenant: ' + $TenantID)

            $EntraData = Start-AZSCEntraExtraction -TenantID $TenantID
            $EntraResources = if ($EntraData) { $EntraData.EntraResources } else { @() }

            # Merge Entra resources into the main Resources array. Guarded so a $null
            # EntraResources doesn't add a spurious null element to $Resources, which
            # would crash later property-chain access (e.g. '.type') under StrictMode.
            if ($EntraResources) { $Resources += $EntraResources }

            Remove-Variable -Name EntraData -ErrorAction SilentlyContinue

            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Entra ID extraction complete. ' + @($EntraResources).Count + ' resources added.')
        }
    }

    # ── Azure DevOps Extraction (opt-in via -IncludeDevOps) ──
    # Opt-in rather than scope-driven: Azure DevOps is a separate service with its own
    # authorization, and an inventory run should not fail or stall on it by default.
    if ($IncludeDevOps.IsPresent) {
        Write-Progress -activity 'Azure Inventory' -Status "18% Complete." -PercentComplete 18 -CurrentOperation "Starting Azure DevOps Extraction.."
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Starting Azure DevOps extraction.')

        $DevOpsData = Start-AZSCDevOpsExtraction -TenantID $TenantID -Organization $DevOpsOrganization -Pat $DevOpsPat
        $DevOpsResources = if ($DevOpsData) { $DevOpsData.DevOpsResources } else { @() }

        # Guarded exactly as the Entra merge is: a $null here would add a null element to
        # $Resources and crash later property-chain access under StrictMode.
        if ($DevOpsResources) { $Resources += $DevOpsResources }

        Remove-Variable -Name DevOpsData -ErrorAction SilentlyContinue

        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Azure DevOps extraction complete. ' + @($DevOpsResources).Count + ' resources added.')
    }

    $ResourcesCount = [string]@($Resources).Count
    $AdvisoryCount = [string]@($Advisories).Count
    $SecCenterCount = [string]@($Security).Count
    # $PolicyAssign's shape varies (empty string, a single REST payload, or an array of
    # per-subscription payloads) — a plain property chain throws under StrictMode whenever
    # 'policyAssignments' isn't present on whatever shape it currently is.
    $PolicyCount = try { [string]@($PolicyAssign.policyAssignments).Count } catch { '0' }

    $ReturnData = [PSCustomObject]@{
        Resources          = $Resources
        EntraResources     = $EntraResources
        Quotas             = $VMQuotas
        Costs              = $Costs
        ResourceContainers = $ResourceContainers
        Advisories         = $Advisories
        ResourcesCount     = $ResourcesCount
        AdvisoryCount      = $AdvisoryCount
        SecCenterCount     = $SecCenterCount
        Security           = $Security
        Retirements        = $Retirements
        PolicyCount        = $PolicyCount
        PolicyAssign       = $PolicyAssign
        PolicyDef          = $PolicyDef
        PolicySetDef       = $PolicySetDef
    }

    return $ReturnData
}
