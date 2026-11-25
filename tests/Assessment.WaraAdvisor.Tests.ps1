#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: the Well-Architected Reliability Assessment (WARA, backed by the Azure Proactive
    Resiliency Library) and the Azure Advisor recommendations assessment. Each rule set is run
    against small collect objects built here, so every automated rule's Pass/Fail is pinned, gated
    rules are proven NotAssessed on an estate without the resource, and no rule errors.

    Three WARA estates are built: a "bad" one where every automated rule has something to find, a
    "healthy" one where every automated rule passes, and an empty one where every rule is gated.
    A fourth block pins how a null or empty value is read (null zone counts, a null HA mode, an
    empty AKS tier) and the right-nested && / || filters WARA-ASP-02 and WARA-REDIS-01 use.
    Advisor gets the same three shapes, plus the "Advisor was skipped" shape the advisorAvailable
    gate exists for.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml

    function Invoke-ScoutTestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    function ConvertTo-ScoutFindingMap {
        param($Findings)
        $map = @{}
        foreach ($f in $Findings) { $map[[string]$f.Id] = $f }
        $map
    }

    function Get-ScoutNestedCollect {
        # A collect object holding only $Rows at the dotted $Path (e.g. 'domains.databases.redisCaches').
        param([string] $Path, $Rows)
        $segments = @($Path -split '\.')
        $node = [ordered]@{ $segments[-1] = @($Rows) }
        for ($i = $segments.Count - 2; $i -ge 0; $i--) { $node = [ordered]@{ $segments[$i] = $node } }
        $node
    }

    $sub = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'
    $script:VmGood = "$sub/Microsoft.Compute/virtualMachines/vm-good"

    # ---- WARA: an estate where every automated rule has at least one finding --------------------
    $script:WaraBad = [ordered]@{
        compute    = [ordered]@{
            virtualMachines = @(
                [ordered]@{ id = $script:VmGood; name = 'vm-good'; zoneEligible = $true; zoneRedundant = $true; size = 'Standard_D2s_v5'; inAvailabilitySet = $false; unmanagedOsDisk = $false }
                [ordered]@{ id = "$sub/Microsoft.Compute/virtualMachines/vm-bad"; name = 'vm-bad'; zoneEligible = $true; zoneRedundant = $false; size = 'Standard_B2s'; inAvailabilitySet = $true; unmanagedOsDisk = $true }
                [ordered]@{ id = "$sub/Microsoft.Compute/virtualMachines/vm-nozones"; name = 'vm-nozones'; zoneEligible = $false; zoneRedundant = $false; size = 'Standard_D2s_v5'; inAvailabilitySet = $true; unmanagedOsDisk = $null }
            )
            virtualMachineScaleSets = @(
                [ordered]@{ name = 'vmss-zonal'; zoneCount = 3; automaticRepairs = $true; orchestrationMode = 'Flexible' }
                [ordered]@{ name = 'vmss-nozone'; zoneCount = $null; automaticRepairs = $false; orchestrationMode = 'Flexible' }
                [ordered]@{ name = 'vmss-zero'; zoneCount = 0; automaticRepairs = $null; orchestrationMode = 'Uniform' }
                [ordered]@{ name = 'vmss-onezone'; zoneCount = 1; automaticRepairs = $true; orchestrationMode = 'Uniform' }
            )
        }
        management = [ordered]@{
            backupProtectedItems = @([ordered]@{ name = 'item1'; sourceResourceId = $script:VmGood })
            recoveryVaults       = @(
                [ordered]@{ name = 'rsv-bad'; softDelete = 'Disabled'; storageType = 'GeoRedundant'; crossRegion = 'False' }
                [ordered]@{ name = 'rsv-ok'; softDelete = 'Enabled'; storageType = 'LocallyRedundant'; crossRegion = 'False' }
            )
        }
        networking = [ordered]@{
            loadBalancers        = @(
                [ordered]@{ name = 'lb-std'; sku = 'Standard'; minFrontendZoneCount = 3 }
                [ordered]@{ name = 'lb-std-weak'; sku = 'Standard'; minFrontendZoneCount = 1 }
                [ordered]@{ name = 'lb-std-null'; sku = 'Standard'; minFrontendZoneCount = $null }
                [ordered]@{ name = 'lb-basic'; sku = 'Basic'; minFrontendZoneCount = 0 }
            )
            publicIPAddresses    = @(
                [ordered]@{ name = 'pip-zr'; skuName = 'Standard'; zoneCount = 3 }
                [ordered]@{ name = 'pip-nozone'; skuName = 'Standard'; zoneCount = $null }
                [ordered]@{ name = 'pip-zonal'; skuName = 'Standard'; zoneCount = 1 }
                [ordered]@{ name = 'pip-basic'; skuName = 'Basic'; zoneCount = $null }
            )
            applicationGateways  = @(
                [ordered]@{ name = 'agw-v2'; sku = 'Standard_v2'; tier = 'Standard_v2'; zoneCount = 3; autoscaleMax = 10 }
                [ordered]@{ name = 'agw-v2-fixed'; sku = 'Standard_v2'; tier = 'Standard_v2'; zoneCount = 3; autoscaleMax = $null }
                [ordered]@{ name = 'agw-v2-onezone'; sku = 'Standard_v2'; tier = 'Standard_v2'; zoneCount = 1; autoscaleMax = 5 }
                [ordered]@{ name = 'agw-v1'; sku = 'Standard_Medium'; tier = 'Standard'; zoneCount = $null; autoscaleMax = $null }
                [ordered]@{ name = 'agw-waf1'; sku = 'WAF_Medium'; tier = 'WAF'; zoneCount = 0; autoscaleMax = $null }
            )
            vpnGateways          = @(
                [ordered]@{ name = 'vpn-az'; gatewayType = 'Vpn'; sku = 'VpnGw1AZ'; activeActive = $true }
                [ordered]@{ name = 'vpn-old'; gatewayType = 'Vpn'; sku = 'VpnGw2'; activeActive = $false }
                [ordered]@{ name = 'vpn-aa-az'; gatewayType = 'Vpn'; sku = 'VpnGw2AZ'; activeActive = $false }
                [ordered]@{ name = 'vpn-basic'; gatewayType = 'Vpn'; sku = 'Basic'; activeActive = $false }
                [ordered]@{ name = 'er-az'; gatewayType = 'ExpressRoute'; sku = 'ErGw1AZ'; activeActive = $false }
                [ordered]@{ name = 'er-old'; gatewayType = 'ExpressRoute'; sku = 'Standard'; activeActive = $false }
            )
            expressRouteCircuits = @([ordered]@{ name = 'circuit1'; peeringLocation = 'LocationA'; serviceProviderName = 'ProviderA' })
            azureFirewalls       = @(
                [ordered]@{ name = 'fw-zr'; sku = 'AZFW_VNet'; tier = 'Premium'; zoneCount = 3 }
                [ordered]@{ name = 'fw-nozone'; sku = 'AZFW_VNet'; tier = 'Standard'; zoneCount = $null }
                [ordered]@{ name = 'fw-onezone'; sku = 'AZFW_VNet'; tier = 'Standard'; zoneCount = 1 }
            )
        }
        domains    = [ordered]@{
            storage     = [ordered]@{
                managedDisks    = @(
                    [ordered]@{ name = 'd-prem'; sku = 'Premium_LRS'; diskState = 'Attached' }
                    [ordered]@{ name = 'd-hdd'; sku = 'Standard_LRS'; diskState = 'Attached' }
                    [ordered]@{ name = 'd-spare'; sku = 'Standard_LRS'; diskState = 'Unattached' }
                )
                storageAccounts = @(
                    [ordered]@{ name = 's-zrs'; sku = 'Standard_ZRS' }
                    [ordered]@{ name = 's-lrs'; sku = 'Standard_LRS' }
                    [ordered]@{ name = 's-prem'; sku = 'Premium_LRS' }
                )
            }
            security    = [ordered]@{
                keyVaults = @(
                    [ordered]@{ name = 'kv-ok'; softDelete = $null; purgeProtection = $true }
                    [ordered]@{ name = 'kv-bad'; softDelete = $false; purgeProtection = $false }
                    [ordered]@{ name = 'kv-null'; softDelete = $null; purgeProtection = $null }
                )
            }
            containers  = [ordered]@{
                aksClusters         = @(
                    [ordered]@{ name = 'aks-ok'; allPoolsZoned = $true; aadIntegrated = $true; tier = 'Standard'; systemPoolMinNodes = 3; allPoolsAutoscale = $true }
                    [ordered]@{ name = 'aks-premium'; allPoolsZoned = $true; aadIntegrated = $true; tier = 'Premium'; systemPoolMinNodes = 5; allPoolsAutoscale = $true }
                    [ordered]@{ name = 'aks-bad'; allPoolsZoned = $false; aadIntegrated = $false; tier = 'Free'; systemPoolMinNodes = 1; allPoolsAutoscale = $false }
                    [ordered]@{ name = 'aks-empty-tier'; allPoolsZoned = $true; aadIntegrated = $true; tier = ''; systemPoolMinNodes = 3; allPoolsAutoscale = $true }
                    [ordered]@{ name = 'aks-few-nodes'; allPoolsZoned = $true; aadIntegrated = $true; tier = 'Standard'; systemPoolMinNodes = 2; allPoolsAutoscale = $true }
                    [ordered]@{ name = 'aks-no-scaler'; allPoolsZoned = $true; aadIntegrated = $true; tier = 'Standard'; systemPoolMinNodes = 3; allPoolsAutoscale = $false }
                    [ordered]@{ name = 'aks-null-nodes'; allPoolsZoned = $true; aadIntegrated = $true; tier = 'Standard'; systemPoolMinNodes = $null; allPoolsAutoscale = $true }
                )
                containerRegistries = @(
                    [ordered]@{ name = 'acr-prem'; sku = 'Premium' }
                    [ordered]@{ name = 'acr-basic'; sku = 'Basic' }
                )
            }
            web         = [ordered]@{
                appServicePlans = @(
                    [ordered]@{ name = 'plan-p1'; sku = 'P1v3'; reserved = $false; tier = 'PremiumV3'; zoneRedundant = $true; instanceCount = 3 }
                    [ordered]@{ name = 'plan-iso'; sku = 'I1v2'; reserved = $false; tier = 'IsolatedV2'; zoneRedundant = $true; instanceCount = 2 }
                    [ordered]@{ name = 'plan-b1'; sku = 'B1'; reserved = $false; tier = 'Basic'; zoneRedundant = $false; instanceCount = 1 }
                    [ordered]@{ name = 'plan-y1'; sku = 'Y1'; reserved = $false; tier = 'Dynamic'; zoneRedundant = $null; instanceCount = $null }
                    [ordered]@{ name = 'plan-s1'; sku = 'S1'; reserved = $false; tier = 'Standard'; zoneRedundant = $false; instanceCount = 2 }
                    [ordered]@{ name = 'plan-p-one'; sku = 'P1v3'; reserved = $false; tier = 'PremiumV3'; zoneRedundant = $true; instanceCount = 1 }
                    [ordered]@{ name = 'plan-p-null'; sku = 'P1v3'; reserved = $false; tier = 'PremiumV3'; zoneRedundant = $null; instanceCount = 3 }
                )
            }
            databases   = [ordered]@{
                sqlDatabases              = @(
                    [ordered]@{ name = 'master'; zoneRedundant = $false; tier = 'System' }
                    [ordered]@{ name = 'db-ok'; zoneRedundant = $true; tier = 'Premium' }
                    [ordered]@{ name = 'db-bad'; zoneRedundant = $false; tier = 'GeneralPurpose' }
                    [ordered]@{ name = 'db-null'; zoneRedundant = $null; tier = 'Basic' }
                )
                sqlServers                = @([ordered]@{ name = 'sql1' })
                cosmosDbAccounts          = @(
                    [ordered]@{ name = 'cosmos-ok'; regionCount = 2; zoneRedundantRegionCount = 2 }
                    [ordered]@{ name = 'cosmos-partial'; regionCount = 2; zoneRedundantRegionCount = 1 }   # the documented gap: not listed
                    [ordered]@{ name = 'cosmos-single'; regionCount = 1; zoneRedundantRegionCount = 1 }
                    [ordered]@{ name = 'cosmos-no-zones'; regionCount = 3; zoneRedundantRegionCount = 0 }
                    [ordered]@{ name = 'cosmos-null'; regionCount = $null; zoneRedundantRegionCount = $null }
                )
                redisCaches               = @(
                    [ordered]@{ name = 'redis-std'; type = 'microsoft.cache/redis'; sku = 'Standard'; zoneCount = $null; zonalAllocationPolicy = ''; highAvailability = '' }
                    [ordered]@{ name = 'redis-zonal'; type = 'microsoft.cache/redis'; sku = 'Premium'; zoneCount = 3; zonalAllocationPolicy = 'UserDefined'; highAvailability = '' }
                    [ordered]@{ name = 'redis-auto'; type = 'microsoft.cache/redis'; sku = 'Premium'; zoneCount = $null; zonalAllocationPolicy = 'Automatic'; highAvailability = '' }
                    [ordered]@{ name = 'redis-onezone'; type = 'microsoft.cache/redis'; sku = 'Premium'; zoneCount = 1; zonalAllocationPolicy = $null; highAvailability = $null }
                    [ordered]@{ name = 'ent-off'; type = 'microsoft.cache/redisenterprise'; sku = 'Enterprise_E10'; zoneCount = $null; zonalAllocationPolicy = ''; highAvailability = 'Disabled' }
                    [ordered]@{ name = 'ent-on'; type = 'microsoft.cache/redisenterprise'; sku = 'Enterprise_E10'; zoneCount = $null; zonalAllocationPolicy = ''; highAvailability = 'Enabled' }
                )
                postgreSqlFlexibleServers = @(
                    [ordered]@{ name = 'pg-zr'; haMode = 'ZoneRedundant' }
                    [ordered]@{ name = 'pg-same'; haMode = 'SameZone' }
                    [ordered]@{ name = 'pg-off'; haMode = 'Disabled' }
                    [ordered]@{ name = 'pg-null'; haMode = $null }
                    [ordered]@{ name = 'pg-empty'; haMode = '' }
                )
                mySqlFlexibleServers      = @(
                    [ordered]@{ name = 'my-zr'; haMode = 'ZoneRedundant' }
                    [ordered]@{ name = 'my-off'; haMode = 'Disabled' }
                    [ordered]@{ name = 'my-null'; haMode = $null }
                )
            }
            integration = [ordered]@{
                apiManagement      = @(
                    [ordered]@{ name = 'apim-prem'; sku = 'Premium' }
                    [ordered]@{ name = 'apim-dev'; sku = 'Developer' }
                )
                eventHubNamespaces = @(
                    [ordered]@{ name = 'eh-ok'; zoneRedundant = $true }
                    [ordered]@{ name = 'eh-bad'; zoneRedundant = $false }
                )
            }
        }
    }

    # ---- WARA: an estate where every automated rule passes --------------------------------------
    $script:WaraHealthy = [ordered]@{
        compute    = [ordered]@{
            virtualMachines         = @([ordered]@{ id = $script:VmGood; name = 'vm-good'; zoneEligible = $true; zoneRedundant = $true; size = 'Standard_D2s_v5'; inAvailabilitySet = $false; unmanagedOsDisk = $false })
            virtualMachineScaleSets = @([ordered]@{ name = 'vmss-zonal'; zoneCount = 3; automaticRepairs = $true; orchestrationMode = 'Flexible' })
        }
        management = [ordered]@{
            backupProtectedItems = @([ordered]@{ name = 'item1'; sourceResourceId = $script:VmGood })
            recoveryVaults       = @([ordered]@{ name = 'rsv-ok'; softDelete = 'Enabled'; storageType = 'GeoRedundant'; crossRegion = 'True' })
        }
        networking = [ordered]@{
            loadBalancers       = @([ordered]@{ name = 'lb-std'; sku = 'Standard'; minFrontendZoneCount = 3 })
            publicIPAddresses   = @([ordered]@{ name = 'pip-zr'; skuName = 'Standard'; zoneCount = 3 })
            applicationGateways = @([ordered]@{ name = 'agw-v2'; sku = 'WAF_v2'; tier = 'WAF_v2'; zoneCount = 3; autoscaleMax = 10 })
            azureFirewalls      = @([ordered]@{ name = 'fw-zr'; sku = 'AZFW_VNet'; tier = 'Premium'; zoneCount = 3 })
            vpnGateways         = @(
                [ordered]@{ name = 'vpn-az'; gatewayType = 'Vpn'; sku = 'VpnGw1AZ'; activeActive = $true }
                [ordered]@{ name = 'er-az'; gatewayType = 'ExpressRoute'; sku = 'ErGw2AZ'; activeActive = $false }
            )
        }
        domains    = [ordered]@{
            storage     = [ordered]@{
                managedDisks    = @([ordered]@{ name = 'd-prem'; sku = 'Premium_ZRS'; diskState = 'Attached' })
                storageAccounts = @([ordered]@{ name = 's-gzrs'; sku = 'Standard_GZRS' })
            }
            security    = [ordered]@{ keyVaults = @([ordered]@{ name = 'kv-ok'; softDelete = $true; purgeProtection = $true }) }
            containers  = [ordered]@{
                aksClusters         = @([ordered]@{ name = 'aks-ok'; allPoolsZoned = $true; aadIntegrated = $true; tier = 'Standard'; systemPoolMinNodes = 3; allPoolsAutoscale = $true })
                containerRegistries = @([ordered]@{ name = 'acr-prem'; sku = 'Premium' })
            }
            web         = [ordered]@{ appServicePlans = @([ordered]@{ name = 'plan-p1'; sku = 'P1v3'; reserved = $false; tier = 'PremiumV3'; zoneRedundant = $true; instanceCount = 3 }) }
            databases   = [ordered]@{
                sqlDatabases              = @(
                    [ordered]@{ name = 'master'; zoneRedundant = $false; tier = 'System' }
                    [ordered]@{ name = 'db-ok'; zoneRedundant = $true; tier = 'Premium' }
                )
                cosmosDbAccounts          = @([ordered]@{ name = 'cosmos-ok'; regionCount = 2; zoneRedundantRegionCount = 2 })
                redisCaches               = @(
                    [ordered]@{ name = 'redis-zonal'; type = 'microsoft.cache/redis'; sku = 'Premium'; zoneCount = 3; zonalAllocationPolicy = 'UserDefined'; highAvailability = '' }
                    [ordered]@{ name = 'ent-on'; type = 'microsoft.cache/redisenterprise'; sku = 'Enterprise_E10'; zoneCount = $null; zonalAllocationPolicy = ''; highAvailability = 'Enabled' }
                )
                postgreSqlFlexibleServers = @([ordered]@{ name = 'pg-zr'; haMode = 'ZoneRedundant' })
                mySqlFlexibleServers      = @([ordered]@{ name = 'my-zr'; haMode = 'ZoneRedundant' })
            }
            integration = [ordered]@{
                apiManagement      = @([ordered]@{ name = 'apim-prem'; sku = 'Premium' })
                eventHubNamespaces = @([ordered]@{ name = 'eh-ok'; zoneRedundant = $true })
            }
        }
    }

    # ---- WARA: an estate with none of the services ----------------------------------------------
    $script:WaraEmpty = [ordered]@{
        compute    = [ordered]@{ virtualMachines = @(); virtualMachineScaleSets = @() }
        management = [ordered]@{ backupProtectedItems = @(); recoveryVaults = @() }
        networking = [ordered]@{ loadBalancers = @(); publicIPAddresses = @(); applicationGateways = @(); vpnGateways = @(); expressRouteCircuits = @(); azureFirewalls = @() }
        domains    = [ordered]@{
            storage     = [ordered]@{ managedDisks = @(); storageAccounts = @() }
            security    = [ordered]@{ keyVaults = @() }
            containers  = [ordered]@{ aksClusters = @(); containerRegistries = @() }
            web         = [ordered]@{ appServicePlans = @() }
            databases   = [ordered]@{ sqlDatabases = @(); sqlServers = @(); cosmosDbAccounts = @(); redisCaches = @(); postgreSqlFlexibleServers = @(); mySqlFlexibleServers = @() }
            integration = [ordered]@{ apiManagement = @(); eventHubNamespaces = @() }
        }
    }

    $script:WaraBadFindings = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraBad -Assessment 'Microsoft: Well-Architected Reliability Assessment')
    $script:WaraBadById = ConvertTo-ScoutFindingMap $script:WaraBadFindings

    # ---- Advisor: a recommendation row, shaped as Import-AdvisorScores shapes it ----------------
    function Get-AdvisorRow {
        param([string] $Category, [string] $Impact, [string] $Problem = 'Example problem')
        [ordered]@{
            Category = $Category; Impact = $Impact; ImpactedField = 'microsoft.compute/virtualmachines'
            ImpactedValue = 'res1'; Subscription = '00000000-0000-0000-0000-000000000001'
            ShortDescriptionProblem = $Problem; ShortDescriptionSolution = 'Example solution'
        }
    }
    $script:AdvisorBad = [ordered]@{
        advisorAvailable = $true
        advisor          = @(
            Get-AdvisorRow -Category 'HighAvailability' -Impact 'High' -Problem 'Azure CDN Standard from Microsoft (classic) is retiring'
            Get-AdvisorRow -Category 'HighAvailability' -Impact 'Medium'
            Get-AdvisorRow -Category 'Security' -Impact 'High'
            Get-AdvisorRow -Category 'Security' -Impact 'Medium'
            Get-AdvisorRow -Category 'Security' -Impact 'Medium'
            Get-AdvisorRow -Category 'Performance' -Impact 'Medium'
            Get-AdvisorRow -Category 'Cost' -Impact 'High'
            Get-AdvisorRow -Category 'Cost' -Impact 'Medium'
            Get-AdvisorRow -Category 'OperationalExcellence' -Impact 'High' -Problem 'Create an Azure Service Health alert'
        )
        management       = [ordered]@{
            advisorScores = @(
                [ordered]@{ id = 'a'; name = 'Advisor'; subscriptionId = 's1'; lastRefreshedScore = 64.5 }
                [ordered]@{ id = 'b'; name = 'Advisor'; subscriptionId = 's2'; lastRefreshedScore = 88.0 }
            )
        }
        monitor          = [ordered]@{ activityLogAlertRules = @() }
    }
    $script:AdvisorClean = [ordered]@{
        advisorAvailable = $true
        advisor          = @()
        management       = [ordered]@{ advisorScores = @([ordered]@{ id = 'a'; name = 'Advisor'; subscriptionId = 's1'; lastRefreshedScore = 91.0 }) }
        monitor          = [ordered]@{ activityLogAlertRules = @() }
    }
    $script:AdvisorSkipped = [ordered]@{
        advisorAvailable = $false
        advisor          = @()
        management       = [ordered]@{ advisorScores = @() }
        monitor          = [ordered]@{ activityLogAlertRules = @() }
    }
    $script:AdvisorBadFindings = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $script:AdvisorBad -Assessment 'Microsoft: Azure Advisor')
    $script:AdvisorBadById = ConvertTo-ScoutFindingMap $script:AdvisorBadFindings
}

Describe 'WARA: Well-Architected Reliability Assessment (APRL-backed)' {
    BeforeAll {
        $script:WaraSet = & $script:Module { Get-RuleSet -Patterns 'wara.reliability' }
    }

    It 'loads one rule file named WARA with 38 rules, 36 automated and 2 manual' {
        @($script:WaraSet).Count | Should -Be 1
        $script:WaraSet.Framework | Should -Be 'WARA'
        $script:WaraSet.FrameworkVersion | Should -Not -BeNullOrEmpty
        @($script:WaraSet.Rules).Count | Should -Be 38
        @($script:WaraSet.Rules | Where-Object { -not $_.manual }).Count | Should -Be 36
        @($script:WaraSet.Rules | Where-Object { $_.manual }).Count | Should -Be 2
    }

    It 'has unique ids, and each title and remediation starts with its own id' {
        @($script:WaraSet.Rules.id | Select-Object -Unique).Count | Should -Be 38
        foreach ($r in $script:WaraSet.Rules) {
            $r.id | Should -Match '^WARA-[A-Z]+-[0-9]{2}$'
            $r.title | Should -BeLike "$($r.id).*"
            $r.remediation | Should -BeLike "$($r.id).*"
        }
    }

    It 'cites an APRL recommendation guid and a source URL on every rule, and gates every rule on its resource type' {
        foreach ($r in $script:WaraSet.Rules) {
            $r.aprl | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -Because "$($r.id) must name the APRL recommendation it paraphrases"
            $r.source | Should -BeLike 'https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2/tree/main/azure-resources/*' -Because "$($r.id) must cite its APRL folder"
            [string]$r.assert.gate | Should -Not -BeNullOrEmpty -Because "$($r.id) must report Not assessed on an estate without the service"
        }
    }

    It 'every rule id, and every guid it cites, is enumerated in the checklist doc' {
        $doc = Get-Content "$script:root/docs/frameworks/wara-aprl-checklist.md" -Raw
        foreach ($r in $script:WaraSet.Rules) {
            $doc | Should -Match ([regex]::Escape([string]$r.id))
            $doc | Should -Match ([regex]::Escape([string]$r.aprl))
        }
    }

    It 'carries no subscription resource id in the rule file or the doc' {
        $text = (Get-Content "$script:root/src/assess/rules/wara.reliability.yaml" -Raw) + (Get-Content "$script:root/docs/frameworks/wara-aprl-checklist.md" -Raw)
        # Only APRL recommendation guids are allowed; an ARM subscription path is not.
        $text | Should -Not -Match '/subscriptions/[0-9a-f]{8}-'
    }

    It 'produces no Error findings on the bad, healthy or empty estate' {
        @($script:WaraBadFindings | Where-Object Status -eq 'Error').Count | Should -Be 0
        $healthy = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraHealthy -Assessment 'x')
        @($healthy | Where-Object Status -eq 'Error').Count | Should -Be 0
        $empty = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraEmpty -Assessment 'x')
        @($empty | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'fails <Id> with <Count> offending resource(s)' -ForEach @(
        @{ Id = 'WARA-VM-01'; Count = 1 }     # vm-bad has no zone in a zone-capable region; vm-nozones is not eligible
        @{ Id = 'WARA-VM-02'; Count = 2 }     # vm-bad and vm-nozones have no protected item
        @{ Id = 'WARA-VM-03'; Count = 1 }     # Standard_B2s
        @{ Id = 'WARA-VM-04'; Count = 2 }     # vm-bad and vm-nozones are in an availability set; the machine outside one passes
        @{ Id = 'WARA-VM-05'; Count = 1 }     # vm-bad only; the null unmanagedOsDisk reads as managed
        @{ Id = 'WARA-VMSS-01'; Count = 2 }   # zoneCount null and 0 both list; one zone and three zones do not
        @{ Id = 'WARA-VMSS-02'; Count = 2 }   # an explicit false and a null automaticRepairs
        @{ Id = 'WARA-DSK-01'; Count = 1 }    # attached HDD; the unattached HDD and the Premium disk are not findings
        @{ Id = 'WARA-AKS-01'; Count = 1 }
        @{ Id = 'WARA-AKS-02'; Count = 1 }
        @{ Id = 'WARA-AKS-03'; Count = 5 }    # Free, empty tier, two system nodes, no autoscaler, null node floor; Standard and Premium with 3+ nodes pass
        @{ Id = 'WARA-ACR-01'; Count = 1 }
        @{ Id = 'WARA-ASP-01'; Count = 1 }    # B1 only; P1v3 and the consumption Y1 plan are not findings
        @{ Id = 'WARA-ASP-02'; Count = 3 }    # Standard not zone redundant, Premium on one instance, Premium with a null flag; Basic and consumption are out of scope
        @{ Id = 'WARA-SQL-01'; Count = 2 }    # db-bad and db-null; master and db-ok are not findings
        @{ Id = 'WARA-COSMOS-01'; Count = 3 } # one region, no zone-redundant region, null counts; the partly zone-redundant account is the documented gap
        @{ Id = 'WARA-REDIS-01'; Count = 3 }  # classic Standard, classic one-zone with null policy, Enterprise with HA Disabled
        @{ Id = 'WARA-PGSQL-01'; Count = 4 }  # SameZone, Disabled, null and empty
        @{ Id = 'WARA-MYSQL-01'; Count = 2 }  # Disabled and null
        @{ Id = 'WARA-STG-01'; Count = 2 }    # Standard_LRS and Premium_LRS
        @{ Id = 'WARA-KV-01'; Count = 1 }     # only the explicit false; null reads as on
        @{ Id = 'WARA-KV-02'; Count = 2 }     # false and null both lack purge protection
        @{ Id = 'WARA-RSV-01'; Count = 1 }
        @{ Id = 'WARA-RSV-02'; Count = 1 }    # geo-redundant without cross-region restore; the LRS vault is not a finding
        @{ Id = 'WARA-LB-01'; Count = 1 }
        @{ Id = 'WARA-LB-02'; Count = 2 }     # one-zone and null frontend on Standard; the Basic balancer is out of scope
        @{ Id = 'WARA-PIP-01'; Count = 2 }    # Standard with null zones and with one zone; the Basic address is out of scope
        @{ Id = 'WARA-PIP-02'; Count = 1 }
        @{ Id = 'WARA-AGW-01'; Count = 2 }    # Standard and WAF are v1
        @{ Id = 'WARA-AGW-02'; Count = 4 }    # fixed capacity, one zone, and both v1 gateways; the v2 gateway on three zones with autoscale passes
        @{ Id = 'WARA-VPN-01'; Count = 2 }    # VpnGw2 and Basic
        @{ Id = 'WARA-VPN-02'; Count = 2 }    # VpnGw2 and VpnGw2AZ; Basic is excluded, the active-active gateway passes
        @{ Id = 'WARA-ER-01'; Count = 1 }     # the Standard ExpressRoute gateway
        @{ Id = 'WARA-FW-01'; Count = 2 }     # null zones and one zone
        @{ Id = 'WARA-APIM-01'; Count = 1 }
        @{ Id = 'WARA-EH-01'; Count = 1 }
    ) {
        $script:WaraBadById[$Id].Status | Should -Be 'Fail'
        $script:WaraBadById[$Id].EvidenceCount | Should -Be $Count
    }

    It 'reports <Id> as Manual with its evidence attached' -ForEach @(
        @{ Id = 'WARA-SQL-02' }, @{ Id = 'WARA-ER-02' }
    ) {
        $script:WaraBadById[$Id].Status | Should -Be 'Manual'
        $script:WaraBadById[$Id].EvidenceCount | Should -BeGreaterThan 0
    }

    It 'fails every automated rule on the bad estate, so no rule is untested' {
        $automated = @($script:WaraSet.Rules | Where-Object { -not $_.manual } | ForEach-Object { $_.id })
        foreach ($id in $automated) {
            $script:WaraBadById[$id].Status | Should -Be 'Fail' -Because "$id must have something to find on the bad estate"
        }
    }

    It 'names the right resources in the evidence of the phase 4 rules' {
        $names = {
            param($id)
            @($script:WaraBadById[$id].Evidence | ForEach-Object { $_.SelectToken('name').ToString() }) | Sort-Object
        }
        (& $names 'WARA-VM-04') | Should -Be @('vm-bad', 'vm-nozones')
        (& $names 'WARA-VMSS-01') | Should -Be @('vmss-nozone', 'vmss-zero')
        (& $names 'WARA-LB-02') | Should -Be @('lb-std-null', 'lb-std-weak')
        (& $names 'WARA-AGW-02') | Should -Be @('agw-v1', 'agw-v2-fixed', 'agw-v2-onezone', 'agw-waf1')
        (& $names 'WARA-ASP-02') | Should -Be @('plan-p-null', 'plan-p-one', 'plan-s1')
        (& $names 'WARA-REDIS-01') | Should -Be @('ent-off', 'redis-onezone', 'redis-std')
        (& $names 'WARA-COSMOS-01') | Should -Be @('cosmos-no-zones', 'cosmos-null', 'cosmos-single')
        (& $names 'WARA-AKS-03') | Should -Be @('aks-bad', 'aks-empty-tier', 'aks-few-nodes', 'aks-no-scaler', 'aks-null-nodes')
    }

    It 'passes every automated rule on the healthy estate' {
        $healthy = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraHealthy -Assessment 'x')
        $automated = @($script:WaraSet.Rules | Where-Object { -not $_.manual } | ForEach-Object { $_.id })
        $automated.Count | Should -Be 36
        foreach ($id in $automated) {
            ($healthy | Where-Object Id -eq $id).Status | Should -Be 'Pass' -Because "$id must pass an estate that meets its condition"
        }
    }

    It 'reports every rule NotAssessed on an estate with none of the services' {
        $empty = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraEmpty -Assessment 'x')
        @($empty | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Manual', 'Error' }).Count | Should -Be 0
        @($empty | Where-Object Status -eq 'NotAssessed').Count | Should -Be 38
    }

    # How a null or empty value is read, one case per row. Rows are written the way Scout writes
    # them: a count Resource Graph cannot take the length of is null (no zones array), a string
    # property that ARM omits is empty.
    It 'reads <Case> as <Status> for <Id>' -ForEach @(
        @{ Case = 'a classic cache with an empty zonal policy and a null zone count'; Id = 'WARA-REDIS-01'; Status = 'Fail'; Path = 'domains.databases.redisCaches'
            Rows = @([ordered]@{ name = 'r'; type = 'microsoft.cache/redis'; zoneCount = $null; zonalAllocationPolicy = ''; highAvailability = '' }) }
        @{ Case = 'a classic cache with a null zonal policy and one zone'; Id = 'WARA-REDIS-01'; Status = 'Fail'; Path = 'domains.databases.redisCaches'
            Rows = @([ordered]@{ name = 'r'; type = 'microsoft.cache/redis'; zoneCount = 1; zonalAllocationPolicy = $null; highAvailability = $null }) }
        @{ Case = 'a classic cache with an Automatic zonal policy and a null zone count'; Id = 'WARA-REDIS-01'; Status = 'Pass'; Path = 'domains.databases.redisCaches'
            Rows = @([ordered]@{ name = 'r'; type = 'microsoft.cache/redis'; zoneCount = $null; zonalAllocationPolicy = 'Automatic'; highAvailability = '' }) }
        @{ Case = 'a classic cache on three zones with a null policy'; Id = 'WARA-REDIS-01'; Status = 'Pass'; Path = 'domains.databases.redisCaches'
            Rows = @([ordered]@{ name = 'r'; type = 'microsoft.cache/redis'; zoneCount = 3; zonalAllocationPolicy = $null; highAvailability = '' }) }
        @{ Case = 'an Enterprise cache with HA Enabled and no zones (the classic zone test must not apply to it)'; Id = 'WARA-REDIS-01'; Status = 'Pass'; Path = 'domains.databases.redisCaches'
            Rows = @([ordered]@{ name = 'r'; type = 'microsoft.cache/redisenterprise'; zoneCount = $null; zonalAllocationPolicy = ''; highAvailability = 'Enabled' }) }
        @{ Case = 'an Enterprise cache with HA Disabled'; Id = 'WARA-REDIS-01'; Status = 'Fail'; Path = 'domains.databases.redisCaches'
            Rows = @([ordered]@{ name = 'r'; type = 'microsoft.cache/redisenterprise'; zoneCount = 3; zonalAllocationPolicy = ''; highAvailability = 'Disabled' }) }
        @{ Case = 'a zonal policy key missing from the row altogether (a missing key matches nothing, and Scout always writes the key)'; Id = 'WARA-REDIS-01'; Status = 'Pass'; Path = 'domains.databases.redisCaches'
            Rows = @([ordered]@{ name = 'r'; type = 'microsoft.cache/redis'; zoneCount = 1; highAvailability = '' }) }
        @{ Case = 'a null HA mode'; Id = 'WARA-PGSQL-01'; Status = 'Fail'; Path = 'domains.databases.postgreSqlFlexibleServers'
            Rows = @([ordered]@{ name = 'p'; haMode = $null }) }
        @{ Case = 'an empty HA mode'; Id = 'WARA-PGSQL-01'; Status = 'Fail'; Path = 'domains.databases.postgreSqlFlexibleServers'
            Rows = @([ordered]@{ name = 'p'; haMode = '' }) }
        @{ Case = 'ZoneRedundant HA'; Id = 'WARA-PGSQL-01'; Status = 'Pass'; Path = 'domains.databases.postgreSqlFlexibleServers'
            Rows = @([ordered]@{ name = 'p'; haMode = 'ZoneRedundant' }) }
        @{ Case = 'a null HA mode'; Id = 'WARA-MYSQL-01'; Status = 'Fail'; Path = 'domains.databases.mySqlFlexibleServers'
            Rows = @([ordered]@{ name = 'm'; haMode = $null }) }
        @{ Case = 'a null zone count'; Id = 'WARA-VMSS-01'; Status = 'Fail'; Path = 'compute.virtualMachineScaleSets'
            Rows = @([ordered]@{ name = 'v'; zoneCount = $null; automaticRepairs = $true }) }
        @{ Case = 'a null automaticRepairs'; Id = 'WARA-VMSS-02'; Status = 'Fail'; Path = 'compute.virtualMachineScaleSets'
            Rows = @([ordered]@{ name = 'v'; zoneCount = 3; automaticRepairs = $null }) }
        @{ Case = 'a null inAvailabilitySet'; Id = 'WARA-VM-04'; Status = 'Pass'; Path = 'compute.virtualMachines'
            Rows = @([ordered]@{ name = 'v'; inAvailabilitySet = $null; unmanagedOsDisk = $null }) }
        @{ Case = 'a null unmanagedOsDisk'; Id = 'WARA-VM-05'; Status = 'Pass'; Path = 'compute.virtualMachines'
            Rows = @([ordered]@{ name = 'v'; inAvailabilitySet = $null; unmanagedOsDisk = $null }) }
        @{ Case = 'a null firewall zone count'; Id = 'WARA-FW-01'; Status = 'Fail'; Path = 'networking.azureFirewalls'
            Rows = @([ordered]@{ name = 'f'; zoneCount = $null }) }
        @{ Case = 'a Standard public IP with a null zone count'; Id = 'WARA-PIP-01'; Status = 'Fail'; Path = 'networking.publicIPAddresses'
            Rows = @([ordered]@{ name = 'p'; skuName = 'Standard'; zoneCount = $null }) }
        @{ Case = 'only a Basic public IP (nothing for PIP-01 to judge)'; Id = 'WARA-PIP-01'; Status = 'NotAssessed'; Path = 'networking.publicIPAddresses'
            Rows = @([ordered]@{ name = 'p'; skuName = 'Basic'; zoneCount = $null }) }
        @{ Case = 'only a Basic public IP'; Id = 'WARA-PIP-02'; Status = 'Fail'; Path = 'networking.publicIPAddresses'
            Rows = @([ordered]@{ name = 'p'; skuName = 'Basic'; zoneCount = $null }) }
        @{ Case = 'a Standard load balancer with a null weakest-frontend zone count'; Id = 'WARA-LB-02'; Status = 'Fail'; Path = 'networking.loadBalancers'
            Rows = @([ordered]@{ name = 'l'; sku = 'Standard'; minFrontendZoneCount = $null }) }
        @{ Case = 'only a Basic load balancer (nothing for LB-02 to judge)'; Id = 'WARA-LB-02'; Status = 'NotAssessed'; Path = 'networking.loadBalancers'
            Rows = @([ordered]@{ name = 'l'; sku = 'Basic'; minFrontendZoneCount = 0 }) }
        @{ Case = 'an empty AKS tier (ARM default Free) on an otherwise sound cluster'; Id = 'WARA-AKS-03'; Status = 'Fail'; Path = 'domains.containers.aksClusters'
            Rows = @([ordered]@{ name = 'a'; tier = ''; systemPoolMinNodes = 3; allPoolsAutoscale = $true }) }
        @{ Case = 'a null system pool floor'; Id = 'WARA-AKS-03'; Status = 'Fail'; Path = 'domains.containers.aksClusters'
            Rows = @([ordered]@{ name = 'a'; tier = 'Standard'; systemPoolMinNodes = $null; allPoolsAutoscale = $true }) }
        @{ Case = 'a Standard cluster with three system nodes and every pool autoscaling'; Id = 'WARA-AKS-03'; Status = 'Pass'; Path = 'domains.containers.aksClusters'
            Rows = @([ordered]@{ name = 'a'; tier = 'Standard'; systemPoolMinNodes = 3; allPoolsAutoscale = $true }) }
        @{ Case = 'null Cosmos region and zone counts'; Id = 'WARA-COSMOS-01'; Status = 'Fail'; Path = 'domains.databases.cosmosDbAccounts'
            Rows = @([ordered]@{ name = 'c'; regionCount = $null; zoneRedundantRegionCount = $null }) }
        @{ Case = 'a Premium plan with a null zone flag'; Id = 'WARA-ASP-02'; Status = 'Fail'; Path = 'domains.web.appServicePlans'
            Rows = @([ordered]@{ name = 'p'; tier = 'PremiumV3'; zoneRedundant = $null; instanceCount = 3 }) }
        @{ Case = 'only a Basic plan on one instance (out of scope, so the rule has nothing to judge)'; Id = 'WARA-ASP-02'; Status = 'NotAssessed'; Path = 'domains.web.appServicePlans'
            Rows = @([ordered]@{ name = 'p'; tier = 'Basic'; zoneRedundant = $false; instanceCount = 1 }) }
        @{ Case = 'a Basic plan on one instance beside a sound Premium plan (the instance test applies to Standard-and-above only)'; Id = 'WARA-ASP-02'; Status = 'Pass'; Path = 'domains.web.appServicePlans'
            Rows = @([ordered]@{ name = 'p'; tier = 'PremiumV3'; zoneRedundant = $true; instanceCount = 3 }, [ordered]@{ name = 'b'; tier = 'Basic'; zoneRedundant = $false; instanceCount = 1 }) }
        @{ Case = 'a zone-redundant Premium plan on one instance'; Id = 'WARA-ASP-02'; Status = 'Fail'; Path = 'domains.web.appServicePlans'
            Rows = @([ordered]@{ name = 'p'; tier = 'PremiumV3'; zoneRedundant = $true; instanceCount = 1 }) }
        @{ Case = 'a v2 gateway on three zones with a null autoscale maximum'; Id = 'WARA-AGW-02'; Status = 'Fail'; Path = 'networking.applicationGateways'
            Rows = @([ordered]@{ name = 'g'; tier = 'Standard_v2'; zoneCount = 3; autoscaleMax = $null }) }
        @{ Case = 'a v2 gateway with null zones and autoscale on'; Id = 'WARA-AGW-02'; Status = 'Fail'; Path = 'networking.applicationGateways'
            Rows = @([ordered]@{ name = 'g'; tier = 'Standard_v2'; zoneCount = $null; autoscaleMax = 10 }) }
    ) {
        $collect = Get-ScoutNestedCollect -Path $Path -Rows $Rows
        $f = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $collect -Assessment 'x') | Where-Object Id -eq $Id
        $f.Status | Should -Be $Status
    }

    It 'does not fail a SQL estate that holds only the master system database' {
        $onlyMaster = [ordered]@{ domains = [ordered]@{ databases = [ordered]@{ sqlDatabases = @([ordered]@{ name = 'master'; zoneRedundant = $false; tier = 'System' }) } } }
        $f = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $onlyMaster -Assessment 'x') | Where-Object Id -eq 'WARA-SQL-01'
        $f.Status | Should -Be 'NotAssessed'
    }
}

Describe 'ADVISOR: Azure Advisor recommendations assessment' {
    BeforeAll {
        $script:AdvisorSet = & $script:Module { Get-RuleSet -Patterns 'advisor.recommendations' }
        $script:AdvisorAutomated = @('ADVISOR-RE-01', 'ADVISOR-RE-02', 'ADVISOR-RE-03', 'ADVISOR-SE-01', 'ADVISOR-SE-02', 'ADVISOR-PE-01', 'ADVISOR-PE-02', 'ADVISOR-CO-01', 'ADVISOR-CO-02', 'ADVISOR-OE-01', 'ADVISOR-OE-02')
    }

    It 'loads one rule file named ADVISOR with 15 rules, 12 automated and 3 manual' {
        @($script:AdvisorSet).Count | Should -Be 1
        $script:AdvisorSet.Framework | Should -Be 'ADVISOR'
        $script:AdvisorSet.FrameworkVersion | Should -Not -BeNullOrEmpty
        @($script:AdvisorSet.Rules).Count | Should -Be 15
        @($script:AdvisorSet.Rules | Where-Object { -not $_.manual }).Count | Should -Be 12
        @($script:AdvisorSet.Rules | Where-Object { $_.manual }).Count | Should -Be 3
    }

    It 'has unique ids, and each title and remediation starts with its own id' {
        @($script:AdvisorSet.Rules.id | Select-Object -Unique).Count | Should -Be 15
        foreach ($r in $script:AdvisorSet.Rules) {
            $r.title | Should -BeLike "$($r.id).*"
            $r.remediation | Should -BeLike "$($r.id).*"
        }
    }

    It 'every rule id is enumerated in the Advisor doc' {
        $doc = Get-Content "$script:root/docs/frameworks/advisor-recommendations.md" -Raw
        foreach ($r in $script:AdvisorSet.Rules) { $doc | Should -Match ([regex]::Escape([string]$r.id)) }
    }

    It 'gates every rule that reads $.advisor on advisorAvailable and no other rule' {
        foreach ($r in $script:AdvisorSet.Rules) {
            $query = [string]$r.query
            $gate = if ($r.assert.ContainsKey('gate')) { [string]$r.assert.gate } else { '' }
            if ($query.StartsWith('$.advisor[')) { $gate | Should -Be '$.advisorAvailable' -Because "$($r.id) reads Advisor rows" }
            else { $gate | Should -Not -Be '$.advisorAvailable' -Because "$($r.id) does not read Advisor rows" }
        }
    }

    It 'produces no Error findings on the bad, clean or skipped estate' {
        @($script:AdvisorBadFindings | Where-Object Status -eq 'Error').Count | Should -Be 0
        foreach ($c in $script:AdvisorClean, $script:AdvisorSkipped) {
            @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $c -Assessment 'x' | Where-Object Status -eq 'Error').Count | Should -Be 0
        }
    }

    It 'scores <Id> as <Status> with <Count> row(s)' -ForEach @(
        @{ Id = 'ADVISOR-RE-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-RE-02'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-RE-03'; Status = 'Fail'; Count = 1 }   # the retiring-service row
        @{ Id = 'ADVISOR-SE-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-SE-02'; Status = 'Fail'; Count = 2 }
        @{ Id = 'ADVISOR-PE-01'; Status = 'Pass'; Count = 0 }   # no High performance row
        @{ Id = 'ADVISOR-PE-02'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-CO-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-CO-02'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-OE-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-OE-02'; Status = 'Pass'; Count = 0 }   # no Medium operational row
        @{ Id = 'ADVISOR-SC-01'; Status = 'Fail'; Count = 1 }   # one score of 64.5
    ) {
        $script:AdvisorBadById[$Id].Status | Should -Be $Status
        $script:AdvisorBadById[$Id].EvidenceCount | Should -Be $Count
    }

    It 'reports the three governance items Manual' {
        foreach ($id in 'ADVISOR-GOV-01', 'ADVISOR-GOV-02', 'ADVISOR-GOV-03') {
            $script:AdvisorBadById[$id].Status | Should -Be 'Manual'
        }
    }

    It 'passes every automated rule when Advisor was read and reported nothing' {
        $findings = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $script:AdvisorClean -Assessment 'x')
        foreach ($id in ($script:AdvisorAutomated + 'ADVISOR-SC-01')) {
            ($findings | Where-Object Id -eq $id).Status | Should -Be 'Pass' -Because "$id has nothing to report"
        }
    }

    It 'reports every Advisor-backed rule NotAssessed, not Pass, when Advisor was skipped' {
        $findings = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $script:AdvisorSkipped -Assessment 'x')
        foreach ($id in ($script:AdvisorAutomated + 'ADVISOR-SC-01')) {
            ($findings | Where-Object Id -eq $id).Status | Should -Be 'NotAssessed' -Because "$id must not pass an estate whose Advisor data was never read"
        }
    }

    It 'matches the retirement rule only on retirement wording' {
        $c = [ordered]@{
            advisorAvailable = $true
            advisor          = @(
                Get-AdvisorRow -Category 'OperationalExcellence' -Impact 'Medium' -Problem 'Create an Azure Service Health alert'
                Get-AdvisorRow -Category 'Cost' -Impact 'Medium' -Problem 'Right-size or shutdown underutilized virtual machines'
            )
        }
        $f = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $c -Assessment 'x') | Where-Object Id -eq 'ADVISOR-RE-03'
        $f.Status | Should -Be 'Pass'
    }
}
