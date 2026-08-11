#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Parameter-translation shim: maps the v1 inventory extraction contract onto src/collect.

.DESCRIPTION
This function used to BE the inventory engine's Resource Graph layer -- it built eight query
strings by hand and drove them through Invoke-AZSCInventoryLoop's own paging/batching loop, in
parallel with (and duplicating) the Resource Graph work src/collect was already doing. That is
what AB#5648 retired.

It now builds no queries and issues no Resource Graph call. It translates the legacy parameter
names into Get-ScoutRawInventory's (src/collect/Get-ScoutRawInventory.ps1) and returns that
function's result under the field names the inventory pipeline has always consumed. All paging
(SkipToken rather than a manual offset), subscription batching, throttle retry and per-batch
error isolation now live in one place, and the query text is rendered from the same clause
builder the assessment path uses.

Behaviour differences from the deleted implementation, all deliberate:
  - Subscriptions are batched 1000 at a time instead of 200 (both are within the documented
    Resource Graph ceiling; 1000 issues fewer calls for a large tenant).
  - A throttled (429) response is retried with backoff before the batch is skipped. The old
    loop retried with a smaller -First page size instead, which does not help a throttle.
  - With no subscriptions resolved at all, the query runs tenant-wide rather than being sent
    with an empty -Subscription list.

.Link
https://github.com/thisismydemo/azure-scout/src/collect/Start-ScoutGraphExtraction.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Tracks ADO AB#5648 (Epic AB#5638). Original v1 implementation: Claudio Merola, 15th Oct 2024.
#>
Function Start-AZSCGraphExtraction {
    Param($ManagementGroup, $Subscriptions, $SubscriptionID, $ResourceGroup, $SecurityCenter, $SkipAdvisory, $IncludeTags, $TagKey, $TagValue, $AzureEnvironment, $SkipAPIs, $SkipPolicy, $CategoryPlan)

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Starting Extractor function (src/collect single-pass, AB#5648)')

    <###################################################### Subscriptions ######################################################################>

    Write-Progress -activity 'Azure Inventory' -Status '2% Complete.' -PercentComplete 2 -CurrentOperation 'Discovering Subscriptions..'

    if (![string]::IsNullOrEmpty($ManagementGroup)) {
        $Subscriptions = Get-AZSCManagementGroups -ManagementGroup $ManagementGroup -Subscriptions $Subscriptions
    }

    $Subscri = @(if ($Subscriptions) { $Subscriptions.id })
    $SubCount = [string]@($Subscri).Count

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Number of Subscriptions Found: ' + $SubCount)
    Write-Progress -activity 'Azure Inventory' -Status '3% Complete.' -PercentComplete 3 -CurrentOperation "$SubCount Subscriptions found.."

    # Preserved verbatim from the v1 contract: a resource-group filter is only meaningful
    # alongside an explicit subscription. Throw rather than Exit -- Exit kills the whole
    # host/runbook uncatchably (AB#5077).
    if (![string]::IsNullOrEmpty($ResourceGroup) -and [string]::IsNullOrEmpty($SubscriptionID)) {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Resource Group Name present, but missing Subscription ID.')
        throw 'If using the -ResourceGroup parameter, the -SubscriptionID must also be provided.'
    }

    Write-Progress -activity 'Azure Inventory' -Status '4% Complete.' -PercentComplete 4 -CurrentOperation 'Starting Resources extraction..'

    <######################################################## SINGLE COLLECTION PASS #######################################################>

    # The legacy row filters were an if/elseif chain (resource group, else tags, else management
    # group). Get-ScoutRawInventory reproduces that precedence itself, so all three are handed
    # over unconditionally and it decides -- there is no filter logic left in this file.
    $isSelectivePlan = $null -ne $CategoryPlan -and $CategoryPlan.PSObject.Properties['IsFull'] -and -not [bool]$CategoryPlan.IsFull
    $RawArgs = @{
        SubscriptionIds              = $Subscri
        IncludeSupportResources      = (($AzureEnvironment -ne 'AzureUSGovernment') -and (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeSupportResources))
        IncludeBackupResources       = (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeBackupResources)
        IncludeDesktopVirtualization = (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeDesktopVirtualization)
        IncludeUpdateManagerResources = (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeUpdateManagerResources)
        IncludeRetirements           = (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeRetirements)
        IncludeAdvisories            = ((-not [bool]$SkipAdvisory) -and (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeAdvisories))
        IncludeSecurityCenter        = [bool]$SecurityCenter
        IncludeArmChildResources     = (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeArmChildResources)
        IncludeOperationalCollectorEnrichment = (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeOperationalCollectorEnrichment)
        IncludeSubscriptionSecurityPolicy = (-not $isSelectivePlan -or [bool]$CategoryPlan.IncludeSubscriptionSecurityPolicy)
        # AB#6755. Tenant-wide collection -- management groups, custom role definitions, policy
        # definitions and policy set definitions -- is now UNCONDITIONAL and there is no longer
        # a parameter for it. It was gated by an AB#5933 migration switch no production caller
        # ever set, so those four worksheets were empty on every run for several releases.
        #
        # -SkipAPIs is passed through, but it only suppresses the ARM REST sweep. Management
        # groups and custom roles come from Az cmdlets and are collected regardless: they are
        # what a governance assessment reads, and gating them behind a "Resource Graph only"
        # flag was the second version of the same defect.
        #
        # The sweep costs this path no extra round-trips -- it is the same Get-ScoutApiResources
        # call Start-AZSCExtractionOrchestration used to run AFTER this function returned. The
        # results come back on $Raw.ApiResources and are handed up for that caller to reuse.
        SkipApiResourceSweep         = ([bool]$SkipAPIs -or ($isSelectivePlan -and -not [bool]$CategoryPlan.IncludeApiResourceSweep))
        SkipPolicy                   = [bool]$SkipPolicy
        IncludeTags                  = [bool]$IncludeTags
        AzureEnvironment             = $AzureEnvironment
    }
    if ($isSelectivePlan) {
        $RawArgs.CollectResourceTable = [bool]$CategoryPlan.CollectResourceTable
        $RawArgs.CollectNetworkTable = [bool]$CategoryPlan.CollectNetworkTable
        $RawArgs.CollectTenantWideResources = [bool]$CategoryPlan.CollectTenantWideResources
        $RawArgs.CollectGovernance = [bool]$CategoryPlan.CollectGovernance
        $RawArgs.ResourceTypes = @($CategoryPlan.ResourceTypes)
        if ([bool]$CategoryPlan.IncludeArmChildResources) {
            $RawArgs.ArmChildDataset = @($CategoryPlan.ArmChildDataset)
        }
    }
    if (![string]::IsNullOrEmpty($ResourceGroup)) { $RawArgs.ResourceGroups = @($ResourceGroup) }
    if (![string]::IsNullOrEmpty($TagKey))        { $RawArgs.TagKey = $TagKey }
    if (![string]::IsNullOrEmpty($TagValue))      { $RawArgs.TagValue = $TagValue }
    if (![string]::IsNullOrEmpty($ManagementGroup)) { $RawArgs.ManagementGroupName = $ManagementGroup }

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Invoking Get-ScoutRawInventory')
    $Raw = Get-ScoutRawInventory @RawArgs

    $CollectionHealth = @(
        if ($Raw.PSObject.Properties['CollectionHealth']) { $Raw.CollectionHealth }
    )
    if ([bool]$SkipAdvisory) {
        $CollectionHealth += [pscustomobject]@{
            Dataset       = 'Advisories'
            Status        = 'NotAssessed'
            Reason        = 'Advisor collection was explicitly disabled with -SkipAdvisory.'
            ResourceTypes = @('microsoft.advisor/recommendations')
            Collectors    = @('Compute/VMOperationalData', 'Hybrid/ArcServerOperationalData')
        }
    }

    $Resources = @($Raw.Resources)
    $ResourceContainers = @($Raw.ResourceContainers)
    $Advisories = @($Raw.Advisories)
    $Security = @($Raw.Security)
    $ResourceRetirements = @($Raw.Retirements)

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Number of Resource Containers: ' + $ResourceContainers.Count)
    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Number of Advisors: ' + $Advisories.Count)
    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Number of Security Center Advisors: ' + $Security.Count)
    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Number of Retirements: ' + $ResourceRetirements.Count)

    Write-Progress -activity 'Azure Inventory' -PercentComplete 10

    # Zero-resources guard: an (almost) empty result usually means a permission or scope
    # problem, not an empty tenant (AB#5080). Get-ScoutRawInventory raises its own version of
    # this warning; this one is kept because its wording names the -ManagementGroup /
    # -SubscriptionID parameters this entry point actually exposes.
    if ($Resources.Count -eq 0 -and $ResourceContainers.Count -eq 0) {
        Write-Warning ('[AzureScout] Extraction returned zero resources. Verify the identity has Reader ' +
            'at the target scope (root management group for full coverage) and that the -ManagementGroup/' +
            '-SubscriptionID scope is correct.')
    }

    return [PSCustomObject]@{
        Resources          = $Resources
        ResourceContainers = $ResourceContainers
        Advisories         = $Advisories
        Security           = $Security
        Retirements        = $ResourceRetirements
        # AB#6755 -- the ARM REST sweep the tenant-wide pass just ran, handed up so the
        # orchestration reuses it rather than repeating it.
        ApiResources       = @(if ($Raw.PSObject.Properties['ApiResources']) { $Raw.ApiResources })
        # AB#6779 -- the role/policy-assignment/lock/budget datasets the raw pass collected, so a
        # combined run's assessment half reads them instead of collecting them a second time.
        Governance         = $(if ($Raw.PSObject.Properties['Governance']) { $Raw.Governance } else { $null })
        CollectionHealth   = @($CollectionHealth)
    }
}
