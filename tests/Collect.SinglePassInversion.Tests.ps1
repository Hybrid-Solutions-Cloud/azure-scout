#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5648 (Epic AB#5638) — the single-pass inversion, and the gate that keeps it.

    v2.7.0 shipped src/collect's collection functions as dead capability: nothing called them,
    so the product still reached Azure Resource Graph 35 times for an assessment collect and a
    second, separate 8-table time for an inventory extraction. This file pins the inverted
    wiring by COUNTING Resource Graph round-trips for each entry point, because that is the only
    property that actually regresses silently — every other assertion in the suite passes just
    as happily whether the data came from one pass or thirty-five.

    Measured on this branch (see the Describe blocks below for the assertions):

      | entry point                                     | before | after |
      |-------------------------------------------------|--------|-------|
      | Invoke-Collect, assessment-only (default)        |     35 |     4 |
      | Invoke-Collect -FromInventory (combined run)     |      1 |     1 |
      | Invoke-Collect -Source TypedQueries (opt-in)     |     35 |    35 |
      | Start-AZSCGraphExtraction, inventory default     |      8 |     8 |
      | combined inventory + assessment, end to end      |      9 |     9 |

    The two documented exceptions to "one pass", both asserted here:
      - `sqlDefenderPricing` reads the SecurityResources table (microsoft.security/pricings),
        which no inventory pass collects. It stays a live typed query.
      - `Retirements` is a file-backed KQL query with its own joins over service-health data.
        It cannot be derived from the raw row set either.

    Search-AzGraph is replaced by a counting stub throughout. No Azure connection.
#>

BeforeAll {
    # Invoke-Collect always performs these two non-ARG sweeps. Keep fake
    # subscriptions and tenants inside the test process.
    function Get-ScoutDefenderPlanSweep {
        param([object[]] $Subscriptions)
        $null = $Subscriptions
        return @()
    }

    function Get-ScoutExternalIdentitiesPolicy {
        param([string] $TenantID)
        $null = $TenantID
        return [pscustomobject]@{ Collected = $false }
    }

    # The raw path owns several non-ARG helpers. Keep this round-trip-count suite hermetic and
    # make their successful-empty contracts explicit; otherwise the optional loader imports the
    # real helper implementations and the fixture can reach the operator's ambient Az context.
    function Get-ScoutArmChildResource {
        param([object[]] $Resources, [string[]] $Dataset, [System.Collections.IList] $CollectionHealth)
        $null = $Resources; $null = $Dataset; $null = $CollectionHealth
        return @()
    }
    function Get-ScoutApiResources {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return @()
    }
    function Get-ScoutTenantWideResource {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return @()
    }
    function Get-ScoutGovernanceDataset {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return [pscustomobject]@{
            roleAssignments = @(); roleDefinitions = @(); policyAssignments = @()
            budgets = @(); resourceLocks = @()
        }
    }
    function Get-ScoutOperationalCollectorEnrichment {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return @()
    }
    function Get-ScoutSubscriptionSecurityPolicySweep {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return @()
    }
    function ConvertTo-ScoutAvdAzureLocalSessionHost {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return @()
    }
    function ConvertTo-ScoutArcSiteResource {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return @()
    }
    function Get-ScoutOutageResource {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        return @()
    }
    $script:root = Split-Path $PSScriptRoot -Parent

    # Neutralise Import-Module so `Import-Module Az.ResourceGraph` inside the functions under
    # test cannot pull the real cmdlet into the session and make a live call.
    function Import-Module {         [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"
    . "$script:root/src/collect/Start-ScoutGraphExtraction.ps1"

    function Get-AZSCManagementGroups {         [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
param($ManagementGroup, $Subscriptions) return $Subscriptions }

    # ---- the one fixture estate both paths are driven from ----
    # Raw rows carry the full properties bag exactly as Resource Graph indexes it; the typed
    # responses further down are the projections ARG would return for these same resources.
    function Get-FixtureContainerRows {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
        param()

        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa'; name = 'demo-sub'; type = 'microsoft.resources/subscriptions'
                subscriptionId = 'aaa'; location = $null; resourceGroup = $null
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tenantId = 'ten'
                # AB#9300 (depth wiring): the management group chain (leaf group, then the tenant root), whose length the
                # shaper and the typed query both project as managementGroupLevels.
                properties = [pscustomobject]@{ state = 'Enabled'; managementGroupAncestorsChain = @([pscustomobject]@{ name = 'mg-platform' }, [pscustomobject]@{ name = 'tenant-root' }) }
                tags = [pscustomobject]@{ Environment = 'Production'; CostCenter = 'CC-100' }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-net'; name = 'rg-net'
                type = 'microsoft.resources/subscriptions/resourcegroups'
                subscriptionId = 'aaa'; location = 'eastus'; resourceGroup = $null
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tenantId = 'ten'
                properties = [pscustomobject]@{ provisioningState = 'Succeeded' }; tags = $null
            }
        )
    }

    function Get-FixtureResourceRows {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
        param()

        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-net/providers/microsoft.network/virtualnetworks/vnet1'
                name = 'vnet1'; type = 'microsoft.network/virtualnetworks'; location = 'eastus'
                resourceGroup = 'rg-net'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    enableDdosProtection   = $false
                    encryption             = [pscustomobject]@{ enabled = $true }
                    virtualNetworkPeerings = @([pscustomobject]@{
                            name       = 'peer1'
                            properties = [pscustomobject]@{
                                remoteVirtualNetwork = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet2' }
                                peeringState         = 'Connected'
                                allowGatewayTransit  = $true
                                useRemoteGateways    = $false
                            }
                        })
                    subnets                = @(
                        [pscustomobject]@{
                            name = 'snet-app'
                            properties = [pscustomobject]@{
                                addressPrefix    = '10.0.1.0/24'
                                ipConfigurations = @([pscustomobject]@{ id = 'ipc1' }, [pscustomobject]@{ id = 'ipc2' })
                            }
                        }
                    )
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.keyvault/vaults/kv1'
                name = 'kv1'; type = 'microsoft.keyvault/vaults'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{ enableSoftDelete = $true; enablePurgeProtection = $false }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.compute/disks/disk-orphan'
                name = 'disk-orphan'; type = 'microsoft.compute/disks'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; plan = $null; identity = $null; zones = @('1')
                extendedLocation = $null; managedBy = $null; tags = $null
                sku = [pscustomobject]@{ name = 'Premium_LRS' }
                properties = [pscustomobject]@{
                    diskState = 'Unattached'; diskSizeGB = 128
                    networkAccessPolicy = 'DenyAll'; publicNetworkAccess = 'Disabled'
                    encryption = [pscustomobject]@{ type = 'EncryptionAtRestWithPlatformKey' }
                }
            }
            # AB#9300 phase 4 -- one row per dataset whose KQL gained fields (or is new), so the
            # equivalence below holds the shaper to what the KQL projects, field for field.
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-net/providers/microsoft.network/azurefirewalls/fw1'
                name = 'fw1'; type = 'microsoft.network/azurefirewalls'; location = 'eastus'
                resourceGroup = 'rg-net'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = @('1', '2', '3')
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    sku             = [pscustomobject]@{ name = 'AZFW_VNet'; tier = 'Premium' }
                    firewallPolicy  = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-net/providers/Microsoft.Network/firewallPolicies/pol1' }
                    threatIntelMode = 'Alert'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-net/providers/microsoft.network/publicipaddresses/pip1'
                name = 'pip1'; type = 'microsoft.network/publicipaddresses'; location = 'eastus'
                resourceGroup = 'rg-net'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; plan = $null; identity = $null; zones = @('1', '2', '3')
                extendedLocation = $null; managedBy = $null; tags = $null
                sku = [pscustomobject]@{ name = 'Standard'; tier = 'Regional' }
                properties = [pscustomobject]@{
                    publicIPAllocationMethod = 'Static'
                    ddosSettings             = [pscustomobject]@{ protectionMode = 'VirtualNetworkInherited' }
                    ipConfiguration          = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-net/providers/Microsoft.Network/networkInterfaces/nic1/ipConfigurations/ipc1' }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.cache/redis/redis-classic'
                name = 'redis-classic'; type = 'microsoft.cache/redis'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = @('1')
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    sku                            = [pscustomobject]@{ name = 'Premium'; family = 'P'; capacity = 1 }
                    publicNetworkAccess            = 'Disabled'
                    zonalAllocationPolicy          = 'Automatic'
                    replicasPerMaster              = 2
                    minimumTlsVersion              = '1.2'
                    enableNonSslPort               = $false
                    disableAccessKeyAuthentication = $true
                    redisConfiguration             = [pscustomobject]@{
                        'aad-enabled'                   = 'true'
                        'rdb-storage-connection-string' = 'SENTINEL-NOT-FOR-THE-PAYLOAD'
                    }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.cache/redisenterprise/redis-ent'
                name = 'redis-ent'; type = 'microsoft.cache/redisenterprise'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; plan = $null; identity = $null; zones = @('1', '2')
                extendedLocation = $null; managedBy = $null; tags = $null
                sku = [pscustomobject]@{ name = 'Enterprise_E10'; capacity = 2 }
                properties = [pscustomobject]@{
                    highAvailability = 'Enabled'; minimumTlsVersion = '1.2'; publicNetworkAccess = 'Disabled'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.documentdb/databaseaccounts/cosmos1'
                name = 'cosmos1'; type = 'microsoft.documentdb/databaseaccounts'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = 'GlobalDocumentDB'; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    publicNetworkAccess            = 'Disabled'
                    disableLocalAuth               = $true
                    locations                      = @(
                        [pscustomobject]@{ locationName = 'East US'; isZoneRedundant = $true }
                        [pscustomobject]@{ locationName = 'West US'; isZoneRedundant = $false }
                        [pscustomobject]@{ locationName = 'North Europe' }
                    )
                    enableAutomaticFailover        = $true
                    backupPolicy                   = [pscustomobject]@{ type = 'Continuous' }
                    enableMultipleWriteLocations   = $false
                    minimalTlsVersion              = 'Tls12'
                    isVirtualNetworkFilterEnabled  = $true
                    ipRules                        = @([pscustomobject]@{ ipAddressOrRange = '203.0.113.7' }, [pscustomobject]@{ ipAddressOrRange = '198.51.100.0/24' })
                    keyVaultKeyUri                 = 'https://kv-example.vault.azure.net/keys/cmk'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.containerservice/managedclusters/aks1'
                name = 'aks1'; type = 'microsoft.containerservice/managedclusters'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                sku = [pscustomobject]@{ name = 'Base'; tier = 'Standard' }
                properties = [pscustomobject]@{
                    kubernetesVersion    = '1.30.1'
                    enableRBAC           = $true
                    addonProfiles        = [pscustomobject]@{ azurepolicy = [pscustomobject]@{ enabled = $true } }
                    disableLocalAccounts = $true
                    apiServerAccessProfile = [pscustomobject]@{ enablePrivateCluster = $true; authorizedIPRanges = @('10.0.0.0/24', '10.1.0.0/24') }
                    networkProfile       = [pscustomobject]@{ networkPolicy = 'azure' }
                    aadProfile           = [pscustomobject]@{ managed = $true; enableAzureRBAC = $true }
                    autoUpgradeProfile   = [pscustomobject]@{ upgradeChannel = 'stable'; nodeOSUpgradeChannel = 'NodeImage' }
                    securityProfile      = [pscustomobject]@{
                        defender         = [pscustomobject]@{ securityMonitoring = [pscustomobject]@{ enabled = $true } }
                        workloadIdentity = [pscustomobject]@{ enabled = $true }
                    }
                    agentPoolProfiles    = @(
                        [pscustomobject]@{ name = 'system'; mode = 'System'; enableAutoScaling = $true; minCount = 2; maxCount = 5; count = 3; availabilityZones = @('1', '2', '3') }
                        [pscustomobject]@{ name = 'user'; mode = 'User'; enableAutoScaling = $false; count = 4; availabilityZones = @('1') }
                        [pscustomobject]@{ name = 'sys2'; mode = 'System'; count = 1; availabilityZones = $null }
                    )
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.compute/virtualmachines/vm1'
                name = 'vm1'; type = 'microsoft.compute/virtualmachines'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; zones = @('1')
                extendedLocation = $null; managedBy = $null; tags = $null
                identity = [pscustomobject]@{ type = 'SystemAssigned' }
                properties = [pscustomobject]@{
                    hardwareProfile   = [pscustomobject]@{ vmSize = 'Standard_D2s_v5' }
                    licenseType       = 'Windows_Server'
                    storageProfile    = [pscustomobject]@{ osDisk = [pscustomobject]@{ osType = 'Windows'; managedDisk = [pscustomobject]@{ storageAccountType = 'Premium_LRS' } } }
                    osProfile         = [pscustomobject]@{ windowsConfiguration = [pscustomobject]@{ patchSettings = [pscustomobject]@{ patchMode = 'AutomaticByPlatform'; assessmentMode = 'AutomaticByPlatform' } } }
                    securityProfile   = [pscustomobject]@{ securityType = 'TrustedLaunch'; encryptionAtHost = $true }
                    diagnosticsProfile = [pscustomobject]@{ bootDiagnostics = [pscustomobject]@{ enabled = $true } }
                }
            }
        )
    }

    # ---- the typed-query responses for the SAME estate ----
    # Hand-written to match what Resource Graph would project for the rows above. This is the
    # only honest way to compare the two implementations: if the typed pack and the shaping pack
    # disagree on a field, the equivalence test below fails rather than both being wrong
    # together (which is what happens when the "expected" side is generated by the code
    # under test).
    function Invoke-FixtureTypedQuery {
        param([string] $Query)
        if ($Query -match 'microsoft\.resources/subscriptions"') {
            return @([pscustomobject]@{ id = 'aaa'; name = 'demo-sub'; state = 'Enabled'
                    tags = [pscustomobject]@{ Environment = 'Production'; CostCenter = 'CC-100' }; managementGroupLevels = 2 })
        }
        if ($Query -match 'subscriptions/resourcegroups') {
            return @([pscustomobject]@{ name = 'rg-net'; subscriptionId = 'aaa' })
        }
        if ($Query -match 'peeringCount') {
            # id/location/encryptionEnabled are the AB#9300 phase 4 additions.
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-net/providers/microsoft.network/virtualnetworks/vnet1'
                    name = 'vnet1'; resourceGroup = 'rg-net'; subscriptionId = 'aaa'; location = 'eastus'
                    peeringCount = 1; ddosEnabled = $false; encryptionEnabled = $true })
        }
        # ---- AB#9300 phase 4: the typed answers for the rows added to Get-FixtureResourceRows. ----
        # Each is what the KQL in Invoke-Collect.ps1 projects for that row, written out by hand
        # (never derived from the shaper), so a field the shaper drops or renames fails the
        # equivalence instead of passing against itself.
        if ($Query -match 'microsoft\.network/azurefirewalls') {
            return @([pscustomobject]@{ name = 'fw1'; resourceGroup = 'rg-net'; subscriptionId = 'aaa'
                    sku = 'AZFW_VNet'; tier = 'Premium'; zoneCount = 3; hasPolicy = $true; threatIntelMode = 'Alert' })
        }
        # Must be matched on ddosProtectionMode: `orphanedPips` also names publicipaddresses, but
        # only the all-addresses dataset projects the DDoS mode (and `skuTier` is shared with
        # sqlElasticPools, so it cannot be the marker).
        if ($Query -match 'ddosProtectionMode') {
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-net/providers/microsoft.network/publicipaddresses/pip1'
                    name = 'pip1'; resourceGroup = 'rg-net'; location = 'eastus'; skuName = 'Standard'; skuTier = 'Regional'
                    zoneCount = 3; ddosProtectionMode = 'VirtualNetworkInherited'; allocationMethod = 'Static'; attached = $true })
        }
        if ($Query -match 'microsoft\.cache/redis') {
            return @(
                [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.cache/redis/redis-classic'
                    name = 'redis-classic'; type = 'microsoft.cache/redis'; resourceGroup = 'rg-app'; subscriptionId = 'aaa'; location = 'eastus'
                    sku = 'Premium'; skuFamily = 'P'; skuCapacity = 1; publicNetworkAccess = 'Disabled'
                    zoneCount = 1; zonalAllocationPolicy = 'Automatic'; replicasPerPrimary = 2; minimumTlsVersion = '1.2'
                    nonSslPortEnabled = $false; accessKeyAuthDisabled = $true; aadEnabled = $true; highAvailability = '' }
                [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.cache/redisenterprise/redis-ent'
                    name = 'redis-ent'; type = 'microsoft.cache/redisenterprise'; resourceGroup = 'rg-app'; subscriptionId = 'aaa'; location = 'eastus'
                    sku = 'Enterprise_E10'; skuFamily = ''; skuCapacity = $null; publicNetworkAccess = 'Disabled'
                    zoneCount = 2; zonalAllocationPolicy = ''; replicasPerPrimary = $null; minimumTlsVersion = '1.2'
                    nonSslPortEnabled = $null; accessKeyAuthDisabled = $null; aadEnabled = $null; highAvailability = 'Enabled' }
            )
        }
        if ($Query -match 'microsoft\.documentdb/databaseaccounts') {
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.documentdb/databaseaccounts/cosmos1'
                    name = 'cosmos1'; resourceGroup = 'rg-app'; subscriptionId = 'aaa'; location = 'eastus'; kind = 'GlobalDocumentDB'
                    publicNetworkAccess = 'Disabled'; disableLocalAuth = $true; regionCount = 3; zoneRedundantRegionCount = 1
                    automaticFailover = $true; backupType = 'Continuous'; multiRegionWrites = $false; minimalTlsVersion = 'Tls12'
                    vnetFilterEnabled = $true; ipRuleCount = 2; cmkEnabled = $true })
        }
        if ($Query -match 'microsoft\.containerservice/managedclusters') {
            # Pools: system (autoscale, min 2), user (fixed 4), sys2 (a SYSTEM pool with no autoscale
            # flag and a fixed count of 1). systemPoolMinNodes = min(2, 1) = 1; two of three pools
            # are zoned; one of three autoscales.
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.containerservice/managedclusters/aks1'
                    name = 'aks1'; resourceGroup = 'rg-app'; location = 'eastus'; k8sVersion = '1.30.1'
                    privateCluster = $true; rbacEnabled = $true; networkPolicyEnabled = $true; aadIntegrated = $true
                    allPoolsZoned = $false; tier = 'Standard'; systemPoolMinNodes = 1; allPoolsAutoscale = $false
                    disableLocalAccounts = $true; upgradeChannel = 'stable'; nodeOsUpgradeChannel = 'NodeImage'
                    authorizedIpRangeCount = 2; defenderEnabled = $true; workloadIdentity = $true; azureRbac = $true; azurePolicyAddon = $true })
        }
        if ($Query -match 'type =~ "microsoft\.compute/virtualmachines"') {
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.compute/virtualmachines/vm1'
                    name = 'vm1'; resourceGroup = 'rg-app'; subscriptionId = 'aaa'; location = 'eastus'
                    zoneRedundant = $true; zoneEligible = $true; size = 'Standard_D2s_v5'; licenseType = 'Windows_Server'
                    osType = 'Windows'; patchMode = 'AutomaticByPlatform'; assessmentMode = 'AutomaticByPlatform'
                    inAvailabilitySet = $false; unmanagedOsDisk = $false; osDiskType = 'Premium_LRS'
                    securityType = 'TrustedLaunch'; encryptionAtHost = $true; bootDiagnostics = $true
                    identityType = 'SystemAssigned' })
        }
        # AB#6928 vnetPeerings -- the per-peering mv-expand projection for peer1 above. Must be
        # checked ON the remoteVirtualNetwork marker: the parent virtualNetworks query also
        # names virtualNetworkPeerings (array_length), but only this query walks the pairs.
        if ($Query -match 'remoteVirtualNetwork') {
            return @([pscustomobject]@{ vnet = 'vnet1'; resourceGroup = 'rg-net'; subscriptionId = 'aaa'
                    remoteVnetId = '/subscriptions/aaa/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet2'
                    remoteVnetName = 'vnet2'; peeringState = 'Connected'
                    allowGatewayTransit = $true; useRemoteGateways = $false })
        }
        if ($Query -match 'ipUtilizationPct') {
            return @([pscustomobject]@{ vnet = 'vnet1'; subnet = 'snet-app'; prefix = '10.0.1.0/24'
                    total = 251; used = 2; ipUtilizationPct = [Math]::Round((2 / 251) * 100, 1) })
        }
        if ($Query -match 'microsoft\.keyvault/vaults') {
            # `id` is projected for the cross-resource joins (AB#6835); the shaped path reads it
            # off the raw row, so the typed emulation has to return it too or the two paths
            # legitimately disagree on the key SET.
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv1'
                    name = 'kv1'; resourceGroup = 'rg-app'; softDelete = $true; purgeProtection = $false })
        }
        if ($Query -match 'coveragePct') {
            # Diagnostic settings are not in any Resource Graph table, so the typed query now
            # matches nothing (AB#9300); the inventory path measures coverage only from the
            # diagnostic-settings ARM sweep, which this fixture has none of. Both paths: no rows.
            return @()
        }
        # managedDisks (AB#6835) and orphanedDisks BOTH mention diskState, so this branch must come
        # first and match on the filter that distinguishes them -- orphanedDisks is the one that
        # narrows to Unattached. Ordering these the other way round silently fed the orphan row to
        # both and the equivalence proof compared the wrong shape.
        if ($Query -match 'diskState' -and $Query -notmatch 'Unattached') {
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/Microsoft.Compute/disks/disk-orphan'
                    name = 'disk-orphan'; resourceGroup = 'rg-app'; subscriptionId = 'aaa'; location = 'eastus'
                    sku = 'Premium_LRS'; diskState = 'Unattached'; sizeGb = 128
                    zoneCount = 1; networkAccessPolicy = 'DenyAll'; publicNetworkAccess = 'Disabled'
                    encryptionType = 'EncryptionAtRestWithPlatformKey' })
        }
        if ($Query -match 'diskState') {
            return @([pscustomobject]@{ name = 'disk-orphan'; resourceGroup = 'rg-app'; location = 'eastus'
                    sku = 'Premium_LRS'; sizeGb = 128 })
        }
        return @()
    }

    # One stub, two dispatch modes. The raw pass is identified by its projection
    # (`project id,name,type,tenantId,kind,...`), which no typed query uses.
    function New-CountingSearchAzGraph {
        $script:argQueries = [System.Collections.Generic.List[string]]::new()
        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            $script:argQueries.Add($Query)
            $isRawProjection = $Query -match 'project id,name,type,tenantId,kind'
            if ($isRawProjection -and $Query -match '^resourcecontainers\b') { return Get-FixtureContainerRows }
            if ($isRawProjection -and $Query -match '^resources\b')           { return Get-FixtureResourceRows }
            if ($isRawProjection)                                            { return @() }
            return Invoke-FixtureTypedQuery -Query $Query
        }
    }
}

AfterAll {
    Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
}

Describe 'AB#5648 — Resource Graph round-trip count per entry point' {

    BeforeEach { New-CountingSearchAzGraph }

    It 'the DEFAULT assessment collect reaches Resource Graph exactly 10 times' {
        Invoke-Collect -WarningAction SilentlyContinue | Out-Null

        # Four raw tables carrying the `project id,name,type,tenantId,kind` marker, plus two more raw
        # tables that do NOT carry it (see below), plus the one query that genuinely cannot be
        # served from inventory.
        #
        # This was 4 until AB#6835 (recoveryservicesresources, for XR-BKP-01/02). It is 6 raw
        # round-trips as of AB#7107/AB#7108 (Story AB#7059, Feature AB#7069, Epic AB#7099):
        # `patchassessmentresources` and `patchinstallationresources` are Update Manager's OWN
        # Resource Graph tables (7-day/30-day retention respectively) -- read-only, same as every
        # other raw-pass table, but not derivable from `resources`/`networkresources` at all, so
        # collecting them costs two more round-trips. Raising this number further is a deliberate
        # contract change, and an EIGHTH would need the same justification in writing.
        #
        # The EIGHTH (AB#9300): `deploymentresources`. ARM deployment history is only in that table,
        # and it is the one signal of infrastructure-as-code the assessment rules score (WAF-OE-02/08,
        # CAF platform automation, DevOps, Platform Engineering). Without it those rules read a
        # property no collected row carried and could never pass.
        # TEN since issue #102: the combined run reads desktopvirtualizationresources (AVD session hosts)
        # and managedservicesresources (Lighthouse delegations) and this pass did not, so those two
        # datasets came back as clean empty arrays in assessment-only. Each is one more raw-pass
        # round-trip, requested only when a dataset that reads it is selected (a Security-only collect
        # still costs 7). Advisor adds a ELEVENTH only when an assessment declares the AdvisorScores
        # ingest (-IncludeAdvisories), which this default call does not.
        $script:argQueries.Count | Should -Be 10 -Because 'the inverted path is one raw pass (resourcecontainers, resources, networkresources, recoveryservicesresources, patchassessmentresources, patchinstallationresources, deploymentresources, desktopvirtualizationresources, managedservicesresources) plus sqlDefenderPricing'

        # patchassessmentresources/patchinstallationresources deliberately omit the `project
        # $columns` clause every OTHER raw table carries (Get-ScoutRawInventory.ps1's AB#6731
        # comment explains why: a `project` naming a column the table does not define fails the
        # whole query, and these two tables' schema is not guaranteed to match the `resources`
        # projection). That means the `project id,name,type,tenantId,kind` marker below only ever
        # matches 4 of the 6 raw-pass queries, not all 6 -- an accident of the heuristic, not a
        # sign the patch queries are typed/live queries.
        # 5 since AB#9300: deploymentresources carries the same projection marker. 7 since issue #102:
        # desktopvirtualizationresources and managedservicesresources carry it too.
        @($script:argQueries | Where-Object { $_ -match 'project id,name,type,tenantId,kind' }).Count | Should -Be 7
        @($script:argQueries | Where-Object { $_ -match '^deploymentresources' }).Count | Should -Be 1
        @($script:argQueries | Where-Object { $_ -match 'microsoft\.security/pricings' }).Count | Should -Be 1
        @($script:argQueries | Where-Object { $_ -match '^patchassessmentresources' }).Count | Should -Be 1
        @($script:argQueries | Where-Object { $_ -match '^patchinstallationresources' }).Count | Should -Be 1
    }

    It 'the queries outside the projection marker are the documented SecurityResources exception plus the two patch tables, nothing else' {
        Invoke-Collect -WarningAction SilentlyContinue | Out-Null
        $unmarked = @($script:argQueries | Where-Object { $_ -notmatch 'project id,name,type,tenantId,kind' })
        $unmarked.Count | Should -Be 3

        $securityException = @($unmarked | Where-Object { $_ -match 'SecurityResources' -and $_ -match 'microsoft\.security/pricings' })
        $securityException.Count | Should -Be 1

        $patchTables = @($unmarked | Where-Object { $_ -match '^patchassessmentresources' -or $_ -match '^patchinstallationresources' })
        $patchTables.Count | Should -Be 2
    }

    It 'the pre-inversion typed pack still costs more than 30 round-trips (the "before" number)' {
        Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue | Out-Null
        $script:argQueries.Count | Should -BeGreaterThan 30
        # And it makes no raw pass at all -- the two sources are genuinely alternatives.
        @($script:argQueries | Where-Object { $_ -match 'project id,name,type,tenantId,kind' }).Count | Should -Be 0
    }

    It 'a narrowed -Categories collect never costs more than the full run' {
        Invoke-Collect -Categories @('Security') -WarningAction SilentlyContinue | Out-Null
        $narrow = $script:argQueries.Count

        New-CountingSearchAzGraph
        Invoke-Collect -WarningAction SilentlyContinue | Out-Null
        $full = $script:argQueries.Count

        # The raw pass (resourcecontainers/resources/networkresources/recoveryservicesresources/
        # patchassessmentresources/patchinstallationresources) is NOT category-filtered -- it is
        # the same unconditional sweep regardless of -Categories, same as -IncludeBackupResources
        # was before it -- so a narrowed run costs the same 7 as the full run; it can never cost
        # MORE.
        $narrow | Should -BeLessOrEqual $full
        $narrow | Should -BeLessOrEqual 7
    }

    It '-FromInventory still costs exactly 1 (the combined-run path is unchanged)' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixtureResourceRows
            ResourceContainers = Get-FixtureContainerRows
        }
        Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue | Out-Null
        $script:argQueries.Count | Should -Be 1
        $script:argQueries[0] | Should -Match 'microsoft\.security/pricings'
    }

    It 'the inventory extraction path reaches Resource Graph 10 times, all from one function' {
        Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'aaa'; name = 'demo-sub' }) `
            -AzureEnvironment 'AzureCloud' -IncludeTags ([switch]$false) `
            -SkipAdvisory ([switch]$false) -SecurityCenter ([switch]$false) `
            3>$null 4>$null 6>$null | Out-Null

        # resourcecontainers, resources, networkresources, SupportResources,
        # recoveryservicesresources, desktopvirtualizationresources, patchassessmentresources,
        # patchinstallationresources, advisorresources, Retirements. Ten DISTINCT Resource Graph
        # tables -- this number cannot go to 1 without dropping datasets, and is reported as 10
        # rather than claimed as 1.
        #
        # This assertion said 8 and had been FAILING ON MAIN since v3.0.9 (AB#6731), which
        # replaced the per-machine `assessPatches` POST with reads of the two Update Manager
        # tables and did not update the count here. Corrected while running the suite for
        # AB#6741; the extra two round-trips are that change's, not this Epic's.
        #
        # This budget is deliberately tight and is meant to FAIL when a round-trip is added. That
        # is how it just proved something else: AB#6779 added four governance collectors
        # (RoleAssignments, ResourceLocks, PolicyAssignments, Budgets) whose acceptance criterion
        # was "no additional Azure API call, proven by comparing query counts before and after".
        # The governance renders cost ZERO new queries. Lighthouse is not a released Scout
        # surface and therefore contributes no managedserviceresources request.
        #
        # AB#9300 (3.18.6): a full inventory also reads every other Resource Graph table that
        # holds deployed resources, one query per table in Get-ScoutResourceGraphDiscoveryTable,
        # so anything deployed in Azure is discovered. Those are counted separately so the ten
        # above stay pinned.
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/collect/Get-ScoutResourceGraphDiscoveryTable.ps1')
        $discoveryTables = @(Get-ScoutResourceGraphDiscoveryTable).Count
        $script:argQueries.Count | Should -Be (10 + $discoveryTables)
        $discoveryTables | Should -Be 35
    }

    It 'a combined inventory + assessment run costs 11, not 43' {
        $extraction = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'aaa'; name = 'demo-sub' }) `
            -AzureEnvironment 'AzureCloud' -IncludeTags ([switch]$true) `
            -SkipAdvisory ([switch]$false) -SecurityCenter ([switch]$false) `
            3>$null 4>$null 6>$null
        Invoke-Collect -FromInventory $extraction -WarningAction SilentlyContinue | Out-Null

        # Ten inventory tables plus the one SecurityResources query. The combined run reuses
        # the extraction's rows, so the assessment adds ONE call, not five -- that is the property
        # this assertion protects, and it is unchanged by the Update Manager tables, by the
        # recoveryservicesresources pass AB#6835 added to the standalone assessment path, or by
        # The number that matters here is not 12; it is the DIFFERENCE of one against the
        # inventory-only assertion above. A combined run costing inventory+1 is the whole
        # collect-once guarantee. If this ever reads inventory+5, the assessment has stopped
        # reusing the extraction's rows and is querying Azure a second time.
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/collect/Get-ScoutResourceGraphDiscoveryTable.ps1')
        $discoveryTables = @(Get-ScoutResourceGraphDiscoveryTable).Count
        $script:argQueries.Count | Should -Be (11 + $discoveryTables) -Because 'ten inventory tables, one discovery query per Resource Graph table that holds deployed resources (AB#9300), plus the one SecurityResources query'
    }
}

Describe 'AB#5648 — the inverted path and the typed pack produce the same collect object' {

    BeforeEach { New-CountingSearchAzGraph }

    BeforeAll {
        function Get-ScoutFlatMap {
            <#
                Flatten a collect object into path -> scalar so two runs can be compared
                key BY KEY rather than by row count or by a whole-object JSON string (which
                would report a single useless "not equal" for any difference anywhere).
            #>
            param([Parameter(Mandatory)] [AllowNull()] $InputObject, [string] $Prefix = '')
            $map = [ordered]@{}
            if ($null -eq $InputObject) { $map[$Prefix] = '<null>'; return $map }
            if ($InputObject -is [string] -or $InputObject -is [bool] -or $InputObject -is [int] -or
                $InputObject -is [long] -or $InputObject -is [double] -or $InputObject -is [decimal]) {
                $map[$Prefix] = "$($InputObject.GetType().Name):$InputObject"
                return $map
            }
            if ($InputObject -is [System.Collections.IEnumerable]) {
                $index = 0
                foreach ($item in $InputObject) {
                    foreach ($entry in (Get-ScoutFlatMap -InputObject $item -Prefix "$Prefix[$index]").GetEnumerator()) {
                        $map[$entry.Key] = $entry.Value
                    }
                    $index++
                }
                $map["$Prefix.__count"] = $index
                return $map
            }
            foreach ($property in ($InputObject.PSObject.Properties | Sort-Object Name)) {
                foreach ($entry in (Get-ScoutFlatMap -InputObject $property.Value -Prefix "$Prefix.$($property.Name)").GetEnumerator()) {
                    $map[$entry.Key] = $entry.Value
                }
            }
            return $map
        }
    }

    It 'every populated key matches, field for field, between -Source Inventory and -Source TypedQueries' {
        $inverted = Invoke-Collect -WarningAction SilentlyContinue
        New-CountingSearchAzGraph
        $typed = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

        # opsPosture.diagnosticCoverage comes from a KQL `summarize ... by type`, whose row
        # ORDER Resource Graph does not define (the shaping path's Group-Object happens to
        # sort by type; ARG does not promise to). Sorting both sides keeps this an assertion
        # about the DATA rather than about an ordering neither implementation guarantees.
        foreach ($collect in @($inverted, $typed)) {
            $collect.opsPosture.diagnosticCoverage = @($collect.opsPosture.diagnosticCoverage | Sort-Object type)
        }

        # _meta carries a generation timestamp, so it is excluded and asserted separately.
        # discovery is intentionally source-specific: the Inventory path can prove universal
        # ARM-row completeness, while the legacy TypedQueries path has no raw resource corpus.
        $invertedMap = Get-ScoutFlatMap -InputObject ($inverted | Select-Object -ExcludeProperty _meta, discovery)
        $typedMap = Get-ScoutFlatMap -InputObject ($typed | Select-Object -ExcludeProperty _meta, discovery)

        # Same key SET first: a key present in one and absent in the other is the failure mode
        # that a value-only comparison misses entirely.
        $missingFromInverted = @($typedMap.Keys | Where-Object { -not $invertedMap.Contains($_) })
        $missingFromTyped = @($invertedMap.Keys | Where-Object { -not $typedMap.Contains($_) })
        $missingFromInverted -join ', ' | Should -BeNullOrEmpty
        $missingFromTyped -join ', ' | Should -BeNullOrEmpty

        # Then every value, reported as an explicit list of differing paths.
        $differences = @(
            foreach ($key in $typedMap.Keys) {
                if ("$($invertedMap[$key])" -ne "$($typedMap[$key])") {
                    "$key : inverted='$($invertedMap[$key])' typed='$($typedMap[$key])'"
                }
            }
        )
        $differences -join "`n" | Should -BeNullOrEmpty
    }

    It 'carries the subscription tag aggregation on the inverted path too (AB#367)' {
        # Regression guard for a defect found while writing this file: the raw pass omits the
        # `tags` COLUMN unless asked, and the top-level `tags` key is aggregated from
        # subscriptions[*].tags. Without -IncludeTags on the internal raw call the inverted path
        # returned an empty tags array for every estate -- a blank report section, no error.
        $collect = Invoke-Collect -WarningAction SilentlyContinue
        @($collect.tags).Count | Should -Be 2
        @($collect.tags | Where-Object { $_.key -eq 'Environment' }).values | Should -Be @('Production')
        @($collect.tags | Where-Object { $_.key -eq 'CostCenter' }).values | Should -Be @('CC-100')
    }

    It 'still populates sqlDefenderPricing from the live query on the inverted path' {
        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'microsoft\.security/pricings') {
                return @([pscustomobject]@{ subscriptionId = 'aaa'; name = 'SqlServers'; pricingTier = 'Standard' })
            }
            if ($Query -match 'project id,name,type,tenantId,kind' -and $Query -match '^resourcecontainers\b') { return Get-FixtureContainerRows }
            if ($Query -match 'project id,name,type,tenantId,kind' -and $Query -match '^resources\b') { return Get-FixtureResourceRows }
            return @()
        }
        try {
            $collect = Invoke-Collect -WarningAction SilentlyContinue
            @($collect.domains.databases.sqlDefenderPricing).Count | Should -Be 1
            $collect.domains.databases.sqlDefenderPricing[0].pricingTier | Should -Be 'Standard'
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed when the raw pass cannot prove required assessment evidence' {
        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'project id,name,type,tenantId,kind') { throw 'ARG is unavailable' }
            return Invoke-FixtureTypedQuery -Query $Query
        }
        try {
            # A typed-query fallback cannot recreate raw-only child/API datasets. Returning a
            # well-shaped empty collect here would let absence assertions fabricate Passes, so
            # the assessment contract now stops with the marker combined mode knows how to catch.
            $caught = $null
            try {
                Invoke-Collect -WarningAction SilentlyContinue | Out-Null
            }
            catch { $caught = $_ }

            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Data['AzureScoutFailureKind'] | Should -Be 'AssessmentSourceUnavailable'
            $caught.Exception.Message | Should -Match 'required inventory datasets are unavailable'
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }
}
