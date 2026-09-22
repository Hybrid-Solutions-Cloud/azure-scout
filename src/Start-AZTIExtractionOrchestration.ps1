#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
function Resolve-AZSCExtractionCategoryPlan {
    [CmdletBinding()]
    param(
        [string[]] $Category = @('All'),
        [switch] $PreserveAssessmentDependencies
    )

    $fullPlan = {
        [pscustomobject]@{
            IsFull                              = $true
            Categories                          = @('All')
            ResourceTypes                       = @()
            CollectResourceTable                = $true
            CollectNetworkTable                 = $true
            IncludeSupportResources             = $true
            IncludeBackupResources              = $true
            IncludeDesktopVirtualization        = $true
            IncludeUpdateManagerResources       = $true
            IncludeRetirements                   = $true
            IncludeAdvisories                    = $true
            IncludeArmChildResources             = $true
            ArmChildDataset                      = @('All')
            IncludeOperationalCollectorEnrichment = $true
            IncludeProviderResourceDetails        = $true
            IncludeSubscriptionSecurityPolicy   = $true
            IncludeApiResourceSweep              = $true
            CollectTenantWideResources           = $true
            CollectGovernance                    = $true
            IncludeEntra                         = $true
            IncludeDevOps                        = $true
            IncludeVmDetails                     = $true
        }
    }

    $requested = @($Category | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($PreserveAssessmentDependencies -or $requested.Count -eq 0 -or $requested -contains 'All') {
        return & $fullPlan
    }

    $collectorRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'manifests/collectors'
    $categoryFolders = @{}
    if (Test-Path -LiteralPath $collectorRoot -PathType Container) {
        foreach ($folder in @(Get-ChildItem -LiteralPath $collectorRoot -Directory -ErrorAction SilentlyContinue)) {
            $categoryFolders[[string]$folder.Name] = [string]$folder.FullName
        }
    }
    if ($categoryFolders.Count -eq 0 -or @($requested | Where-Object { -not $categoryFolders.ContainsKey($_) }).Count -gt 0) {
        return & $fullPlan
    }

    $manifestText = [System.Text.StringBuilder]::new()
    $declaredTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($categoryName in $requested) {
        foreach ($manifestPath in @(Get-ChildItem -LiteralPath $categoryFolders[$categoryName] -Filter '*.psd1' -File -ErrorAction SilentlyContinue)) {
            $text = Get-Content -LiteralPath $manifestPath.FullName -Raw
            [void]$manifestText.AppendLine($text)
            try {
                $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath.FullName
                foreach ($resourceType in @($manifest.ResourceTypes)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$resourceType)) {
                        [void]$declaredTypes.Add([string]$resourceType)
                    }
                }
            }
            catch {
                # An unreadable manifest makes selective extraction unsafe. Preserve the
                # established full-collection behavior instead of guessing at dependencies.
                return & $fullPlan
            }
        }
    }

    $allText = $manifestText.ToString()
    foreach ($match in [regex]::Matches($allText, '(?i)\b(?:microsoft\.[a-z0-9.-]+/[a-z0-9._/-]+|AZSC/[a-z0-9._/-]+|Entra/[a-z0-9._/-]+|DevOps/[a-z0-9._/-]+)')) {
        [void]$declaredTypes.Add($match.Value.TrimEnd('/'))
    }

    $azureTypes = @($declaredTypes | Where-Object { $_ -match '(?i)^microsoft\.' } | Sort-Object)
    $armChildNames = @($declaredTypes | Where-Object { $_ -match '(?i)^AZSC/ARMChild/' } | ForEach-Object { ($_ -split '/', 3)[2] })
    $supportedArmChildren = @(
        'MLComputes', 'MLDatasets', 'MLDatastores', 'MLEndpoints', 'MLModels', 'MLPipelines',
        'OpenAIDeployments', 'SearchIndexes', 'AVDApplications', 'AppInsightsProactiveDetection',
        'LAWorkspaceLinkedServices', 'LAWorkspaceSavedSearches', 'KeyVaultSecrets', 'KeyVaultKeys',
        'LAWorkspaceTables', 'SentinelDataConnectors', 'SentinelIngestion',
        'StorageBlobContainers', 'StorageFileShares', 'StorageLifecyclePolicies', 'StorageQueues',
        'StorageTables', 'BackupInstances', 'ResourceDiagnosticSettings', 'ReservationUtilization',
        'AzureLocalVirtualMachineInstances'
    )
    $armChildDataset = @($armChildNames | Where-Object { $_ -in $supportedArmChildren } | Sort-Object -Unique)
    $specialApiTypes = @(
        'microsoft.advisor/advisorscore',
        'microsoft.consumption/reservationrecommendations',
        'azsc/monitor/outage',
        'azsc/armchild/arcsites'
    )
    $hasType = {
        param([string] $Pattern)
        return [bool]@($declaredTypes | Where-Object { $_ -match $Pattern }).Count
    }
    $includeTenantWide = & $hasType '(?i)^AZSC/Management/'
    $includeApiSweep = $includeTenantWide -or [bool]@($declaredTypes | Where-Object { $_ -in $specialApiTypes }).Count

    return [pscustomobject]@{
        IsFull                              = $false
        Categories                          = $requested
        ResourceTypes                       = $azureTypes
        CollectResourceTable                = ($azureTypes.Count -gt 0)
        CollectNetworkTable                 = (& $hasType '(?i)^microsoft\.network/')
        IncludeSupportResources             = (& $hasType '(?i)^microsoft\.support/supporttickets$')
        IncludeBackupResources              = (& $hasType '(?i)^microsoft\.recoveryservices/.+(protecteditems|backuppolicies)$')
        IncludeDesktopVirtualization        = (& $hasType '(?i)^microsoft\.desktopvirtualization/')
        IncludeUpdateManagerResources       = [bool]@($requested | Where-Object { $_ -in @('Compute', 'Hybrid', 'Monitor') }).Count
        IncludeRetirements                   = ($allText -match '(?i)\$Retirements')
        IncludeAdvisories                    = $true
        IncludeArmChildResources             = ($armChildDataset.Count -gt 0)
        ArmChildDataset                      = $armChildDataset
        IncludeOperationalCollectorEnrichment = ((& $hasType '(?i)^AZSC/(Operational/|Management/SubscriptionEnrichment$)') -or $azureTypes.Count -gt 0)
        IncludeProviderResourceDetails        = ($azureTypes.Count -gt 0)
        IncludeSubscriptionSecurityPolicy   = (& $hasType '(?i)^AZSC/Subscription/SecurityPolicySweep$')
        IncludeApiResourceSweep              = $includeApiSweep
        CollectTenantWideResources           = $includeTenantWide
        CollectGovernance                    = (& $hasType '(?i)^AZSC/Governance/')
        IncludeEntra                         = ((& $hasType '(?i)^Entra/') -or $requested -contains 'Identity')
        IncludeDevOps                        = ((& $hasType '(?i)^DevOps/') -or $requested -contains 'DevOps')
        IncludeVmDetails                     = [bool]@($requested | Where-Object { $_ -in @('Compute', 'General') }).Count
    }
}

function Start-AZSCExtractionOrchestration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Automation', Justification = "Declared to match this function's call signature -- callers invoke it with this named/positional argument; removing the parameter would break them even though this implementation does not need the value.")]
    Param($ManagementGroup, $Subscriptions, $SubscriptionID, $SkipPolicy, $ResourceGroup, $SecurityCenter, $SkipAdvisory, $IncludeTags, $TagKey, $TagValue, $SkipAPIs, $SkipVMDetails, $IncludeCosts, $Automation, $AzureEnvironment,
        [ValidateSet('All', 'ArmOnly', 'EntraOnly')]
        [string]$Scope = 'All',
        [string]$TenantID,
        [switch]$IncludeDevOps,
        [string[]]$DevOpsOrganization,
        [string]$DevOpsPat,
        [switch]$IncludeOkta,
        [string]$OktaOrganizationUrl,
        [securestring]$OktaApiToken,
        [switch]$IncludeOnPremisesIdentity,
        [string[]]$Category = @('All'),
        [switch]$PreserveAssessmentDependencies
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
    $OktaResources = @()
    $HybridIdentityLocalResources = @()
    # AB#6456 -- Start-AZSCEntraExtraction's per-query success/failure record. Initialised here
    # (not only inside the Entra branch) for the same StrictMode reason $Governance is: an
    # ArmOnly run never enters that branch, and reading an unassigned variable throws.
    $EntraQueryOutcomes = @()
    $CollectionHealth = [System.Collections.Generic.List[object]]::new()
    $SourceOperations = [System.Collections.Generic.List[object]]::new()
    $PolicyAssign = $null
    $PolicyDef = $null
    $PolicySetDef = $null
    $Costs = $null
    $VMQuotas = $null
    $PreCollectedAPIResults = @()
    # Initialised here, not inside the ARM branch: an EntraOnly run never enters that branch and
    # reading an unassigned variable is a StrictMode throw, not a $null.
    $Governance = $null
    $extractionPlan = Resolve-AZSCExtractionCategoryPlan -Category $Category -PreserveAssessmentDependencies:$PreserveAssessmentDependencies

    # ── ARM Extraction (skip when Scope = EntraOnly) ──
    if ($Scope -ne 'EntraOnly') {
        $GraphData = Start-AZSCGraphExtraction -ManagementGroup $ManagementGroup -Subscriptions $Subscriptions -SubscriptionID $SubscriptionID -ResourceGroup $ResourceGroup -SecurityCenter $SecurityCenter -SkipAdvisory $SkipAdvisory -IncludeTags $IncludeTags -TagKey $TagKey -TagValue $TagValue -AzureEnvironment $AzureEnvironment -SkipAPIs $SkipAPIs -SkipPolicy $SkipPolicy -CategoryPlan $extractionPlan

        $Resources = $GraphData.Resources
        $ResourceContainers = $GraphData.ResourceContainers
        $Advisories = $GraphData.Advisories
        $Security = $GraphData.Security
        $Retirements = $GraphData.Retirements
        # AB#6755 -- the tenant-wide pass inside the raw extraction already ran the ARM REST
        # API sweep. Carry it out of $GraphData before that variable is dropped so the block
        # below reuses it instead of issuing the identical per-subscription calls a second time.
        $PreCollectedAPIResults = $GraphData.ApiResources
        # AB#6779 -- same reasoning for the governance datasets: the raw pass collected the role
        # assignments, policy assignments, locks and budgets once, and a combined run's assessment
        # half must read them from here rather than collect them again.
        $Governance = $(if ($GraphData.PSObject.Properties['Governance']) { $GraphData.Governance } else { $null })
        if ($GraphData.PSObject.Properties['CollectionHealth']) {
            foreach ($health in @($GraphData.CollectionHealth)) { if ($null -ne $health) { $CollectionHealth.Add($health) } }
        }
        if ($GraphData.PSObject.Properties['SourceOperations']) {
            foreach ($operation in @($GraphData.SourceOperations)) { if ($null -ne $operation) { $SourceOperations.Add($operation) } }
        }

        Remove-Variable -Name GraphData -ErrorAction SilentlyContinue

        if(![bool]$SkipAPIs -and $extractionPlan.IncludeApiResourceSweep)
            {
                if (Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue) {
                    Write-ScoutProgress -Activity 'Azure Inventory' -Status '12% Complete.' -PercentComplete 12 -CurrentOperation 'Starting API extraction'
                }
                else { Write-Progress -Activity 'Azure Inventory' -Status '12% Complete.' -PercentComplete 12 -CurrentOperation 'Starting API extraction' }
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Getting API Resources.')
                # The v3 collector implementation owns the ARM REST contract directly.  Do
                # not route this through a legacy Modules shim: src/collect is now the single
                # implementation and its field names are consumed below.
                #
                # AB#6755: prefer the sweep the raw extraction already ran. Falling back to a
                # fresh call keeps this correct if the tenant-wide pass was skipped or its
                # helpers could not be loaded -- it must never be the reason the four legacy
                # API datasets below go missing.
                $APIResults = if (@($PreCollectedAPIResults).Count -gt 0) {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Reusing the API sweep from the raw extraction pass (AB#6755).')
                    @($PreCollectedAPIResults)
                } else {
                    $apiFallbackArgs = @{
                        Subscriptions    = $Subscriptions
                        AzureEnvironment = $AzureEnvironment
                        SkipPolicy       = $SkipPolicy
                    }
                    if ((Get-Command Get-ScoutApiResources).Parameters.ContainsKey('SkipManagedIdentities')) {
                        $apiFallbackArgs.SkipManagedIdentities = $true
                    }
                    Get-ScoutApiResources @apiFallbackArgs
                }
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
                $Resources += Get-AZSCCollectedValue -InputObject $APIResults -Name 'AdvisorScore'
                $Resources += Get-AZSCCollectedValue -InputObject $APIResults -Name 'ReservationRecommendations'
                $PolicyAssign = Get-AZSCCollectedValue -InputObject $APIResults -Name 'PolicyAssignments'
                $PolicyDef = Get-AZSCCollectedValue -InputObject $APIResults -Name 'PolicyDefinitions'
                $PolicySetDef = Get-AZSCCollectedValue -InputObject $APIResults -Name 'PolicySetDefinitions'
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'API Resource Inventory Finished.')
                Remove-Variable APIResults -ErrorAction SilentlyContinue
            }

        if ([bool]$IncludeCosts) {
            $Costs = Get-ScoutCostInventory -Subscriptions $Subscriptions -Days 60 -Granularity 'Monthly'
        }

        if (![bool]$SkipVMDetails -and $extractionPlan.IncludeVmDetails)
            {
                Write-Host 'Gathering VM Extra Details: ' -NoNewline
                Write-Host 'Quotas' -ForegroundColor Cyan
                if (Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue) {
                    Write-ScoutProgress -Activity 'Azure Inventory' -Status '13% Complete.' -PercentComplete 13 -CurrentOperation 'Starting VM details extraction'
                }
                else { Write-Progress -Activity 'Azure Inventory' -Status '13% Complete.' -PercentComplete 13 -CurrentOperation 'Starting VM details extraction' }

                $VMQuotas = Get-ScoutVmQuotas -Subscriptions $Subscriptions -Resources $Resources

                $Resources += $VMQuotas

                # NOTE: $VMQuotas is intentionally NOT removed here — it is returned
                # separately as the 'Quotas' field of $ReturnData below. Removing it
                # (as the original code did) left 'Quotas' permanently null.

                Write-Host 'Gathering VM Extra Details: ' -NoNewline
                Write-Host 'Size SKU' -ForegroundColor Cyan

                $VMSkuDetails = Get-ScoutVmSkuDetails -Resources $Resources

                $Resources += $VMSkuDetails

                Remove-Variable -Name VMSkuDetails -ErrorAction SilentlyContinue

            }
    }
    else {
        Write-Host 'Scope is EntraOnly — ' -NoNewline -ForegroundColor Yellow
        Write-Host 'Skipping ARM resource extraction' -ForegroundColor Yellow
    }

    # ── Entra ID Extraction (when Scope = All or EntraOnly) ──
    if ($Scope -in @('All', 'EntraOnly') -and $extractionPlan.IncludeEntra) {
        if ([string]::IsNullOrEmpty($TenantID)) {
            Write-Warning 'TenantID is required for Entra ID extraction but was not provided. Skipping Entra extraction.'
        }
        else {
            if (Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue) {
                Write-ScoutProgress -Activity 'Azure Inventory' -Status '15% Complete.' -PercentComplete 15 -CurrentOperation 'Starting Entra ID extraction'
            }
            else { Write-Progress -Activity 'Azure Inventory' -Status '15% Complete.' -PercentComplete 15 -CurrentOperation 'Starting Entra ID extraction' }
            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Starting Entra ID extraction for tenant: ' + $TenantID)

            $EntraData = Start-AZSCEntraExtraction -TenantID $TenantID
            $EntraResources = if ($EntraData) { $EntraData.EntraResources } else { @() }
            # AB#6456 -- PSObject.Properties guard rather than a plain `.QueryOutcomes` read: an
            # EntraData produced by an older/mocked Start-AZSCEntraExtraction that predates this
            # field would throw a property-not-found under StrictMode instead of degrading.
            $EntraQueryOutcomes = if ($EntraData -and $EntraData.PSObject.Properties['QueryOutcomes']) { $EntraData.QueryOutcomes } else { @() }
            foreach ($operation in @($EntraQueryOutcomes)) {
                if ($null -ne $operation) { $SourceOperations.Add($operation) }
            }

            # Disabled catalog entries remain in QueryOutcomes so the raw discovery record is
            # complete, but they are not failed collection work and must not make an otherwise
            # healthy run Partial. Derive the set from the shared catalog instead of hardcoding
            # today's disabled types. Older standalone callers/mocks that do not load the
            # catalog preserve the historical behavior through an intentionally empty set.
            $disabledEntraTypes = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            if (Get-Command Get-ScoutEntraQueryCatalog -ErrorAction SilentlyContinue) {
                try {
                    foreach ($query in @(Get-ScoutEntraQueryCatalog)) {
                        if (
                            $query -is [System.Collections.IDictionary] -and
                            $query.ContainsKey('Collect') -and
                            -not [bool]$query['Collect'] -and
                            -not [string]::IsNullOrWhiteSpace([string]$query['Type'])
                        ) {
                            [void]$disabledEntraTypes.Add([string]$query['Type'])
                        }
                    }
                }
                catch {
                    Write-Verbose "Start-AZSCExtractionOrchestration: Entra catalog availability metadata could not be read; retaining all query outcomes in collection health: $($_.Exception.Message)"
                }
            }
            foreach ($outcome in @($EntraQueryOutcomes)) {
                if ($null -eq $outcome -or -not $outcome.PSObject.Properties['Status']) { continue }
                $outcomeType = if ($outcome.PSObject.Properties['Type']) { [string]$outcome.Type } else { '' }
                if ($disabledEntraTypes.Contains($outcomeType)) { continue }
                if ([string]$outcome.Status -in @('NotAssessed', 'Unavailable', 'Failed')) {
                    $CollectionHealth.Add([pscustomobject]@{
                            Dataset       = "Entra/$($outcome.Name)"
                            Status        = [string]$outcome.Status
                            Reason        = if ($outcome.PSObject.Properties['Reason']) { [string]$outcome.Reason } else { $null }
                            ResourceTypes = @($outcomeType)
                        })
                }
            }

            # Merge Entra resources into the main Resources array. Guarded so a $null
            # EntraResources doesn't add a spurious null element to $Resources, which
            # would crash later property-chain access (e.g. '.type') under StrictMode.
            if ($EntraResources) { $Resources += $EntraResources }

            Remove-Variable -Name EntraData -ErrorAction SilentlyContinue

            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Entra ID extraction complete. ' + @($EntraResources).Count + ' resources added.')
        }
    }

    # ── Orphaned role-assignment resolution — AB#6456 (Feature AB#6455, Epic AB#6454) ─────────
    #
    # Runs unconditionally, AFTER both branches above, because it needs whatever the two of them
    # produced without caring which ran: the governance envelope (from the ARM branch) and the
    # Entra principal rows + QueryOutcomes (from the Entra branch, when it ran at all). An ArmOnly
    # run, or a run with no -TenantID, still gets a Role Assignments worksheet -- every principal
    # in it just reads 'NotAssessed' rather than a guess, which is the whole point of the
    # QueryOutcomes contract (see Resolve-ScoutOrphanedRoleAssignment's own header).
    #
    # A missing command (an older module build, or a unit test that dot-sources only part of the
    # tree) degrades to "the Role Assignments worksheet keeps its unresolved columns" rather than
    # failing the run -- the same shape every other optional enrichment in this file uses.
    if (Get-Command Resolve-ScoutOrphanedRoleAssignment -ErrorAction SilentlyContinue) {
        try {
            # Commands that intentionally emit no value can become a literal null element when
            # appended with `+=`. One such element used to make PowerShell reject the entire
            # object[] argument before the resolver's own null guards could run.
            $Resources = @($Resources | Where-Object { $null -ne $_ })
            $Resources = Resolve-ScoutOrphanedRoleAssignment -Resources $Resources -EntraQueryOutcomes $EntraQueryOutcomes
        }
        catch {
            Write-Warning "Start-AZSCExtractionOrchestration: orphaned role-assignment resolution failed; the Role Assignments worksheet keeps its unresolved columns: $($_.Exception.Message)"
        }
    }

    # ── Azure DevOps Extraction (opt-in via -IncludeDevOps) ──
    # Opt-in rather than scope-driven: Azure DevOps is a separate service with its own
    # authorization, and an inventory run should not fail or stall on it by default.
    if ($IncludeDevOps.IsPresent -and $extractionPlan.IncludeDevOps) {
        if (Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue) {
            Write-ScoutProgress -Activity 'Azure Inventory' -Status '18% Complete.' -PercentComplete 18 -CurrentOperation 'Starting Azure DevOps extraction'
        }
        else { Write-Progress -Activity 'Azure Inventory' -Status '18% Complete.' -PercentComplete 18 -CurrentOperation 'Starting Azure DevOps extraction' }
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Starting Azure DevOps extraction.')

        $DevOpsData = Start-AZSCDevOpsExtraction -TenantID $TenantID -Organization $DevOpsOrganization -Pat $DevOpsPat
        $DevOpsResources = if ($DevOpsData) { $DevOpsData.DevOpsResources } else { @() }
        if ($DevOpsData -and $DevOpsData.PSObject.Properties['CollectionHealth']) {
            foreach ($health in @($DevOpsData.CollectionHealth)) {
                if ($null -ne $health) { $CollectionHealth.Add($health) }
            }
        }

        # Guarded exactly as the Entra merge is: a $null here would add a null element to
        # $Resources and crash later property-chain access under StrictMode.
        if ($DevOpsResources) { $Resources += $DevOpsResources }

        Remove-Variable -Name DevOpsData -ErrorAction SilentlyContinue

        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Azure DevOps extraction complete. ' + @($DevOpsResources).Count + ' resources added.')
    }

    # Okta is a separate identity control plane. It is explicitly opt-in and its SecureString
    # token is passed only to the read-only adapter; no token value enters Resources or logs.
    if ($IncludeOkta.IsPresent) {
        if (-not (Get-Command Get-ScoutOktaEvidence -ErrorAction SilentlyContinue)) {
            $CollectionHealth.Add([pscustomobject]@{
                    Dataset='Okta'; Operation='Load read-only adapter'; Status='Unavailable'
                    Reason='Get-ScoutOktaEvidence is not available in this module build.'
                    ResourceTypes=@('AZSC/Okta/*')
                })
        }
        else {
            $oktaData = Get-ScoutOktaEvidence -OrganizationUrl $OktaOrganizationUrl -ApiToken $OktaApiToken
            $OktaResources = @($oktaData.Resources)
            if ($OktaResources) { $Resources += $OktaResources }
            foreach ($operation in @($oktaData.SourceOperations)) {
                if ($null -ne $operation) { $SourceOperations.Add($operation) }
            }
            foreach ($health in @($oktaData.CollectionHealth)) {
                if ($null -ne $health) { $CollectionHealth.Add($health) }
            }
        }
    }

    if ($IncludeOnPremisesIdentity.IsPresent) {
        if (Get-Command Get-ScoutHybridIdentityLocalEvidence -ErrorAction SilentlyContinue) {
            $hybridLocalData=Get-ScoutHybridIdentityLocalEvidence
            $HybridIdentityLocalResources=@($hybridLocalData.Resources)
            if($HybridIdentityLocalResources){$Resources += $HybridIdentityLocalResources}
            foreach($operation in @($hybridLocalData.SourceOperations)){if($null-ne $operation){$SourceOperations.Add($operation)}}
            foreach($health in @($hybridLocalData.CollectionHealth)){if($null-ne $health){$CollectionHealth.Add($health)}}
        }else{
            $CollectionHealth.Add([pscustomobject]@{Dataset='HybridIdentity/Local';Operation='Load local adapter';Status='Unavailable';Reason='Get-ScoutHybridIdentityLocalEvidence is not available in this module build.';ResourceTypes=@('AZSC/HybridIdentity/*')})
        }
    }

    # Return a clean resource contract even when an optional producer emitted no pipeline value.
    $Resources = @($Resources | Where-Object { $null -ne $_ })

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
        OktaResources      = $OktaResources
        HybridIdentityLocalResources = $HybridIdentityLocalResources
        EntraQueryOutcomes = @($EntraQueryOutcomes)
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
        # AB#6779 -- consumed by Invoke-Collect via -FromInventory so a combined run's assessment
        # half never re-collects role assignments, policy assignments, locks or budgets.
        Governance         = $Governance
        CollectionHealth   = @($CollectionHealth)
        SourceOperations   = @($SourceOperations)
    }

    return $ReturnData
}
