# Fixtures for tests/Assessment.DepthWiring.Tests.ps1: one case per rule converted by the AB#9300 depth wiring.
# Pass / Fail / NotAssessed are collect fragments in the shape ConvertFrom-ScoutInventory produces. Dot-sourced in
# BEFORE DISCOVERY (so -ForEach can expand them) and again in BeforeAll (so a test body can read them).
Set-StrictMode -Version Latest
# ---- the cases: one per converted rule --------------------------------------------------------------
# Pass / Fail / NotAssessed are collect fragments in the shape ConvertFrom-ScoutInventory produces.
$zoneRegionlessWorkspace = @{ id = 'w-nozone'; location = 'brazilsoutheast'; replicationEnabled = $null }
$script:Cases = @(
    @{
        Id = 'CAF-RES-04'; Set = 'caf.resourceorg'; FailCount = 1
        Pass = @{ subscriptions = @(@{ id = 'sub-a'; managementGroupLevels = 3 }, @{ id = 'sub-b'; managementGroupLevels = 2 }) }
        Fail = @{ subscriptions = @(@{ id = 'sub-a'; managementGroupLevels = 1 }, @{ id = 'sub-b'; managementGroupLevels = 3 }) }
        NotAssessed = @{ subscriptions = @(@{ id = 'sub-a'; managementGroupLevels = $null }) }
    }
    @{
        Id = 'CAF-CON-07'; Set = 'caf.containers'; FailCount = 2
        Pass = @{
            domains = @{ containers = @{ containerRegistries = @(@{ id = 'r1'; subscriptionId = 'sub-a' }) } }
            security = @{ defenderPlans = @(@{ name = 'Containers'; subscriptionId = 'SUB-A'; properties = @{ pricingTier = 'Standard' } }, @{ name = 'VirtualMachines'; subscriptionId = 'sub-a'; properties = @{ pricingTier = 'Free' } }) }
        }
        Fail = @{
            domains = @{ containers = @{ containerRegistries = @(@{ id = 'r1'; subscriptionId = 'sub-a' }, @{ id = 'r2'; subscriptionId = 'sub-b' }) } }
            security = @{ defenderPlans = @(@{ name = 'Containers'; subscriptionId = 'sub-a'; properties = @{ pricingTier = 'Free' } }) }
        }
        NotAssessed = @{
            domains = @{ containers = @{ containerRegistries = @(@{ id = 'r1'; subscriptionId = 'sub-a' }) } }
            security = @{ defenderPlans = @() }
        }
    }
    @{
        Id = 'WAF-DATA-PG-09'; Set = 'waf.dataservices'; FailCount = 2
        Pass = @{ domains = @{ databases = @{ postgreSqlFlexibleServers = @(@{ id = 'pg1'; customMaintenanceWindow = 'Enabled' }) } } }
        Fail = @{ domains = @{ databases = @{ postgreSqlFlexibleServers = @(@{ id = 'pg1'; customMaintenanceWindow = 'Disabled' }, @{ id = 'pg2'; customMaintenanceWindow = '' }) } } }
        NotAssessed = @{ domains = @{ databases = @{ postgreSqlFlexibleServers = @() } } }
    }
    @{
        Id = 'WAF-MC-HM-10'; Set = 'waf.missioncritical'; FailCount = 0
        Pass = @{ subscriptions = @(@{ id = 'sub-a' }); monitor = @{ activityLogAlertRules = @(@{ name = 'a1'; category = 'ServiceHealth'; enabled = $true }) } }
        Fail = @{ subscriptions = @(@{ id = 'sub-a' }); monitor = @{ activityLogAlertRules = @(@{ name = 'a1'; category = 'Administrative'; enabled = $true }, @{ name = 'a2'; category = 'ServiceHealth'; enabled = $false }) } }
        NotAssessed = @{ subscriptions = @(); monitor = @{ activityLogAlertRules = @() } }
    }
    @{
        Id = 'WAF-SVC-AKS-13'; Set = 'waf.serviceguides'; FailCount = 2
        Pass = @{ domains = @{ containers = @{ aksClusters = @(@{ id = 'aks1'; azurePolicyAddon = $true }) } } }
        Fail = @{ domains = @{ containers = @{ aksClusters = @(@{ id = 'aks1'; azurePolicyAddon = $false }, @{ id = 'aks2'; azurePolicyAddon = $null }) } } }
        NotAssessed = @{ domains = @{ containers = @{ aksClusters = @() } } }
    }
    @{
        Id = 'WAF-SVC-ACA-09'; Set = 'waf.serviceguides'; FailCount = 1
        Pass = @{ domains = @{ containers = @{ containerApps = @(@{ id = 'ca1'; containerCount = 2; containersWithoutAllProbes = 0 }) } } }
        Fail = @{ domains = @{ containers = @{ containerApps = @(@{ id = 'ca1'; containerCount = 2; containersWithoutAllProbes = 1 }, @{ id = 'ca2'; containerCount = 1; containersWithoutAllProbes = 0 }) } } }
        NotAssessed = @{ domains = @{ containers = @{ containerApps = @(@{ id = 'ca1'; containerCount = $null; containersWithoutAllProbes = 0 }) } } }
    }
    @{
        Id = 'WAF-SVC-ACA-11'; Set = 'waf.serviceguides'; FailCount = 1
        Pass = @{ domains = @{ containers = @{ containerAppEnvironments = @(@{ id = 'e1'; logDestination = 'azure-monitor'; logsExported = $true }) } } }
        Fail = @{ domains = @{ containers = @{ containerAppEnvironments = @(@{ id = 'e1'; logDestination = 'none'; logsExported = $false }, @{ id = 'e2'; logDestination = 'log-analytics'; logsExported = $true }) } } }
        NotAssessed = @{ domains = @{ containers = @{ containerAppEnvironments = @() } } }
    }
    @{
        Id = 'WAF-SVC-APIM-09'; Set = 'waf.serviceguides'; FailCount = 2
        Pass = @{ domains = @{ integration = @{ apiManagement = @(@{ id = 'a1'; legacyProtocolEnabled = $false; legacyCipherEnabled = $false }, @{ id = 'a2'; legacyProtocolEnabled = $null; legacyCipherEnabled = $null }) } } }
        Fail = @{ domains = @{ integration = @{ apiManagement = @(@{ id = 'a1'; legacyProtocolEnabled = $true; legacyCipherEnabled = $false }, @{ id = 'a2'; legacyProtocolEnabled = $false; legacyCipherEnabled = $true }, @{ id = 'a3'; legacyProtocolEnabled = $false; legacyCipherEnabled = $false }) } } }
        NotAssessed = @{ domains = @{ integration = @{ apiManagement = @() } } }
    }
    @{
        Id = 'WAF-SVC-FW-06'; Set = 'waf.serviceguides'; FailCount = 1
        Pass = @{ networking = @{ firewallPolicies = @(@{ id = 'p1'; hasBasePolicy = $false; idpsTlsDnsEnabled = $true }, @{ id = 'child'; hasBasePolicy = $true; idpsTlsDnsEnabled = $false }) } }
        Fail = @{ networking = @{ firewallPolicies = @(@{ id = 'p1'; hasBasePolicy = $false; idpsTlsDnsEnabled = $false }, @{ id = 'p2'; hasBasePolicy = $false; idpsTlsDnsEnabled = $true }, @{ id = 'child'; hasBasePolicy = $true; idpsTlsDnsEnabled = $false }) } }
        NotAssessed = @{ networking = @{ firewallPolicies = @() } }
    }
    @{
        Id = 'WAF-SVC-APPI-05'; Set = 'waf.serviceguides'; FailCount = 3
        Pass = @{ monitor = @{ appInsights = @(@{ id = 'ai1'; disableLocalAuth = $true; disableIpMasking = $false }, @{ id = 'ai2'; disableLocalAuth = $true; disableIpMasking = $null }) } }
        Fail = @{ monitor = @{ appInsights = @(@{ id = 'ai1'; disableLocalAuth = $null; disableIpMasking = $false }, @{ id = 'ai2'; disableLocalAuth = $false; disableIpMasking = $false }, @{ id = 'ai3'; disableLocalAuth = $true; disableIpMasking = $true }, @{ id = 'ai4'; disableLocalAuth = $true; disableIpMasking = $false }) } }
        NotAssessed = @{ monitor = @{ appInsights = @() } }
    }
    @{
        Id = 'WAF-SVC-TM-04'; Set = 'waf.serviceguides'; FailCount = 3
        Pass = @{ networking = @{ trafficManagerProfiles = @(@{ id = 'tm1'; dnsTtl = 30; alwaysServeEndpointCount = 0 }, @{ id = 'tm2'; dnsTtl = $null; alwaysServeEndpointCount = 0 }) } }
        Fail = @{ networking = @{ trafficManagerProfiles = @(@{ id = 'tm1'; dnsTtl = 60; alwaysServeEndpointCount = 0 }, @{ id = 'tm2'; dnsTtl = 300; alwaysServeEndpointCount = 0 }, @{ id = 'tm3'; dnsTtl = 10; alwaysServeEndpointCount = 1 }, @{ id = 'tm4'; dnsTtl = 59; alwaysServeEndpointCount = 0 }) } }
        NotAssessed = @{ networking = @{ trafficManagerProfiles = @() } }
    }
    @{
        Id = 'WAF-SVC-VWAN-05'; Set = 'waf.serviceguides'; FailCount = 1
        Pass = @{ networking = @{ virtualHubs = @(@{ name = 'h1'; hasExpressRouteGateway = $true; hasVpnGateway = $true; routingPreference = 'ExpressRoute'; expressRouteBackedUp = $true }, @{ name = 'h2'; hasExpressRouteGateway = $false; hasVpnGateway = $false; routingPreference = 'ExpressRoute'; expressRouteBackedUp = $false }) } }
        Fail = @{ networking = @{ virtualHubs = @(@{ name = 'h1'; hasExpressRouteGateway = $true; hasVpnGateway = $false; routingPreference = 'ExpressRoute'; expressRouteBackedUp = $false }, @{ name = 'h2'; hasExpressRouteGateway = $true; hasVpnGateway = $true; routingPreference = 'ExpressRoute'; expressRouteBackedUp = $true }) } }
        NotAssessed = @{ networking = @{ virtualHubs = @(@{ name = 'h2'; hasExpressRouteGateway = $false; hasVpnGateway = $true; routingPreference = 'ExpressRoute'; expressRouteBackedUp = $false }) } }
    }
    @{
        Id = 'WAF-ANALYTICS-RE-10'; Set = 'waf.analytics'; FailCount = 1
        Pass = @{ management = @{ logAnalyticsWorkspaces = @(@{ id = 'w1'; location = 'eastus'; replicationEnabled = $null }, @{ id = 'w2'; location = 'SwedenCentral'; replicationEnabled = $false }, @{ id = 'w3'; location = 'brazilsoutheast'; replicationEnabled = $true }) } }
        Fail = @{ management = @{ logAnalyticsWorkspaces = @(@{ id = 'w1'; location = 'eastus'; replicationEnabled = $null }, $zoneRegionlessWorkspace, @{ id = 'w3'; location = 'brazilsoutheast'; replicationEnabled = $true }) } }
        NotAssessed = @{ management = @{ logAnalyticsWorkspaces = @() } }
    }
    @{
        Id = 'WAF-GOLIVE-SE-01'; Set = 'waf.golive'; FailCount = 1
        Pass = @{ subscriptions = @(@{ id = 'sub-a' }, @{ id = 'sub-b' }); security = @{ defenderSecureScores = @(@{ SubscriptionId = 'SUB-A'; Percentage = 0.4 }, @{ SubscriptionId = 'sub-b'; Percentage = 0.6 }) } }
        Fail = @{ subscriptions = @(@{ id = 'sub-a' }, @{ id = 'sub-b' }); security = @{ defenderSecureScores = @(@{ SubscriptionId = 'sub-a'; Percentage = 0.4 }) } }
        NotAssessed = @{ subscriptions = @(@{ id = 'sub-a' }); security = @{ defenderSecureScores = @() } }
    }
    @{
        Id = 'WAF-CO-07'; Set = 'waf.cost'; FailCount = 2
        Pass = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $true; lifecyclePolicies = @(@{ storageAccountId = 's1'; premium = $false; policyPresent = $true; enabledRuleCount = 2; tieringRuleCount = 1; deleteRuleCount = 1 }) } } }
        Fail = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $true; lifecyclePolicies = @(@{ storageAccountId = 's1'; premium = $false; policyPresent = $false; ruleCount = 0; enabledRuleCount = 0; tieringRuleCount = 0; deleteRuleCount = 0 }, @{ storageAccountId = 's2'; premium = $false; policyPresent = $true; ruleCount = 3; enabledRuleCount = 0; tieringRuleCount = 0; deleteRuleCount = 0 }, @{ storageAccountId = 's3'; premium = $false; policyPresent = $true; enabledRuleCount = 1; tieringRuleCount = 1; deleteRuleCount = 0 }) } } }
        NotAssessed = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $false; lifecyclePolicies = @() } } }
    }
    @{
        Id = 'WAF-DATA-BLOB-13'; Set = 'waf.dataservices'; FailCount = 1
        Pass = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $true; lifecyclePolicies = @(@{ storageAccountId = 's1'; premium = $false; enabledRuleCount = 1; tieringRuleCount = 1; deleteRuleCount = 0 }, @{ storageAccountId = 's2'; premium = $true; enabledRuleCount = 0; tieringRuleCount = 0; deleteRuleCount = 0 }) } } }
        Fail = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $true; lifecyclePolicies = @(@{ storageAccountId = 's1'; premium = $false; enabledRuleCount = 1; tieringRuleCount = 0; deleteRuleCount = 1 }, @{ storageAccountId = 's2'; premium = $true; enabledRuleCount = 0; tieringRuleCount = 0; deleteRuleCount = 0 }, @{ storageAccountId = 's3'; premium = $false; enabledRuleCount = 1; tieringRuleCount = 2; deleteRuleCount = 0 }) } } }
        NotAssessed = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $false; lifecyclePolicies = @() } } }
    }
    @{
        Id = 'WAF-SUS-CO-09'; Set = 'waf.sustainability'; FailCount = 1
        Pass = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $true; lifecyclePolicies = @(@{ storageAccountId = 's1'; premium = $false; enabledRuleCount = 1; tieringRuleCount = 1; deleteRuleCount = 0 }, @{ storageAccountId = 's2'; premium = $true; enabledRuleCount = 1; tieringRuleCount = 0; deleteRuleCount = 1 }) } } }
        Fail = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $true; lifecyclePolicies = @(@{ storageAccountId = 's1'; premium = $false; enabledRuleCount = 0; tieringRuleCount = 0; deleteRuleCount = 0 }, @{ storageAccountId = 's2'; premium = $true; enabledRuleCount = 1; tieringRuleCount = 0; deleteRuleCount = 1 }) } } }
        NotAssessed = @{ domains = @{ storage = @{ lifecyclePoliciesMeasured = $false; lifecyclePolicies = @() } } }
    }
)
