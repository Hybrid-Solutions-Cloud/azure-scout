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

    # ---- AB#9300, 3.18.20: rules answered by the depth datasets (sub-resources Resource Graph does not index). The
    # fixtures use the field names ConvertFrom-ScoutInventory produces; tests/Collect.*ChildResources.Tests.ps1 prove
    # the shapes from real sweep rows. A row whose value is $null is one the sweep could not read, and is never a finding.
    @{
        Id = 'WAF-SVC-AFD-04'; Set = 'waf.serviceguides'; FailCount = 2
        Pass = @{
            networking = @{ cdnProfiles = @(@{ id = 'p1'; sku = 'Premium_AzureFrontDoor' }) }
            domains = @{ afd = @{ originGroupsMeasured = $true; originsMeasured = $true; originGroups = @(@{ name = 'og1'; hasRedundantOrigins = $true; probeGap = $false }) } }
        }
        Fail = @{
            networking = @{ cdnProfiles = @(@{ id = 'p1'; sku = 'Premium_AzureFrontDoor' }) }
            domains = @{ afd = @{ originGroupsMeasured = $true; originsMeasured = $true; originGroups = @(
                        @{ name = 'single'; hasRedundantOrigins = $false; probeGap = $false }
                        @{ name = 'noprobe'; hasRedundantOrigins = $true; probeGap = $true }
                        @{ name = 'unread'; hasRedundantOrigins = $null; probeGap = $null }) } }
        }
        NotAssessed = @{
            networking = @{ cdnProfiles = @(@{ id = 'p1'; sku = 'Premium_AzureFrontDoor' }) }
            domains = @{ afd = @{ originGroupsMeasured = $true; originsMeasured = $false; originGroups = @() } }
        }
    }
    @{
        Id = 'WAF-SVC-AFD-05'; Set = 'waf.serviceguides'; FailCount = 2
        Pass = @{
            networking = @{ cdnProfiles = @(@{ id = 'p1'; sku = 'Standard_AzureFrontDoor' }) }
            domains = @{ afd = @{ customDomainsMeasured = $true; customDomains = @(@{ name = 'd1'; tls12OrHigher = $true }, @{ name = 'd2'; tls12OrHigher = $null }) } }
        }
        Fail = @{
            networking = @{ cdnProfiles = @(@{ id = 'p1'; sku = 'Standard_AzureFrontDoor' }) }
            domains = @{ afd = @{ customDomainsMeasured = $true; customDomains = @(@{ name = 'd1'; tls12OrHigher = $false }, @{ name = 'd2'; tls12OrHigher = $false }, @{ name = 'd3'; tls12OrHigher = $true }) } }
        }
        NotAssessed = @{
            networking = @{ cdnProfiles = @(@{ id = 'p1'; sku = 'Standard_AzureFrontDoor' }) }
            domains = @{ afd = @{ customDomainsMeasured = $false; customDomains = @() } }
        }
    }
    @{
        Id = 'WAF-SVC-SB-12'; Set = 'waf.serviceguides'; FailCount = 1
        Pass = @{ domains = @{ integration = @{ serviceBusNamespaces = @(@{ id = 'n1' }); serviceBusNetworkRuleSetsMeasured = $true; serviceBusNetworkRuleSets = @(@{ name = 'n1'; allowsAllNetworks = $false }) } } }
        Fail = @{ domains = @{ integration = @{ serviceBusNamespaces = @(@{ id = 'n1' }, @{ id = 'n2' }, @{ id = 'n3' }); serviceBusNetworkRuleSetsMeasured = $true
                    serviceBusNetworkRuleSets = @(@{ name = 'n1'; allowsAllNetworks = $true }, @{ name = 'n2'; allowsAllNetworks = $false }, @{ name = 'n3'; allowsAllNetworks = $null }) } } }
        NotAssessed = @{ domains = @{ integration = @{ serviceBusNamespaces = @(@{ id = 'n1' }); serviceBusNetworkRuleSetsMeasured = $false; serviceBusNetworkRuleSets = @() } } }
    }
    @{
        Id = 'WAF-SVC-APIM-10'; Set = 'waf.serviceguides'; FailCount = 2
        Pass = @{ domains = @{ integration = @{ apiManagement = @(@{ id = 'a1' }); apimNamedValuesMeasured = $true; apimNamedValues = @(@{ name = 'a1'; namedValueCount = 3; secretCount = 2; inlineSecretCount = 0 }) } } }
        Fail = @{ domains = @{ integration = @{ apiManagement = @(@{ id = 'a1' }, @{ id = 'a2' }, @{ id = 'a3' }); apimNamedValuesMeasured = $true
                    apimNamedValues = @(@{ name = 'a1'; inlineSecretCount = 2 }, @{ name = 'a2'; inlineSecretCount = 1 }, @{ name = 'a3'; inlineSecretCount = 0 }) } } }
        NotAssessed = @{ domains = @{ integration = @{ apiManagement = @(@{ id = 'a1' }); apimNamedValuesMeasured = $false; apimNamedValues = @() } } }
    }
    @{
        Id = 'CAF-DB-03'; Set = 'caf.databases'; FailCount = 1
        Pass = @{ domains = @{ databases = @{ sqlTdeMeasured = $true; sqlTde = @(@{ databaseName = 'db1'; state = 'Enabled'; enabled = $true }, @{ databaseName = 'db2'; enabled = $null }) } } }
        Fail = @{ domains = @{ databases = @{ sqlTdeMeasured = $true; sqlTde = @(@{ databaseName = 'db1'; enabled = $false }, @{ databaseName = 'db2'; enabled = $true }, @{ databaseName = 'db3'; enabled = $null }) } } }
        NotAssessed = @{ domains = @{ databases = @{ sqlTdeMeasured = $false; sqlTde = @() } } }
    }
    @{
        Id = 'CAF-DB-05'; Set = 'caf.databases'; FailCount = 2
        Pass = @{ domains = @{ databases = @{ sqlBackupShortTermMeasured = $true; sqlBackupShortTerm = @(@{ databaseName = 'db1'; retentionDays = 7; meetsMinimumRetention = $true }, @{ databaseName = 'db2'; retentionDays = 35; meetsMinimumRetention = $true }) } } }
        Fail = @{ domains = @{ databases = @{ sqlBackupShortTermMeasured = $true; sqlBackupShortTerm = @(
                        @{ databaseName = 'db1'; retentionDays = 1; meetsMinimumRetention = $false }, @{ databaseName = 'db2'; retentionDays = 3; meetsMinimumRetention = $false }
                        @{ databaseName = 'db3'; retentionDays = 14; meetsMinimumRetention = $true }, @{ databaseName = 'db4'; retentionDays = $null; meetsMinimumRetention = $null }) } } }
        NotAssessed = @{ domains = @{ databases = @{ sqlBackupShortTermMeasured = $false; sqlBackupShortTerm = @() } } }
    }
    @{
        Id = 'CAF-DB-06'; Set = 'caf.databases'; FailCount = 2
        Pass = @{ domains = @{ databases = @{ sqlFirewallRulesMeasured = $true; sqlFirewallRules = @(@{ name = 's1'; ruleCount = 3; allowAllRuleCount = 0; allowAzureServicesRuleCount = 1; broadRangeRuleCount = 1 }) } } }
        Fail = @{ domains = @{ databases = @{ sqlFirewallRulesMeasured = $true; sqlFirewallRules = @(
                        @{ name = 's1'; ruleCount = 1; allowAllRuleCount = 1 }, @{ name = 's2'; ruleCount = 2; allowAllRuleCount = 2 }, @{ name = 's3'; ruleCount = 0; allowAllRuleCount = 0 }) } } }
        NotAssessed = @{ domains = @{ databases = @{ sqlFirewallRulesMeasured = $false; sqlFirewallRules = @() } } }
    }
    @{
        Id = 'WAF-AZLOCAL-SE-01'; Set = 'waf.azurelocal.security'; FailCount = 1
        Pass = @{ domains = @{ hybrid = @{ azureLocalSecuritySettingsMeasured = $true; azureLocalSecuritySettings = @(@{ clusterName = 'c1'; driftControlEnforced = $true }, @{ clusterName = 'c2'; driftControlEnforced = $null }) } } }
        Fail = @{ domains = @{ hybrid = @{ azureLocalSecuritySettingsMeasured = $true; azureLocalSecuritySettings = @(@{ clusterName = 'c1'; driftControlEnforced = $false }, @{ clusterName = 'c2'; driftControlEnforced = $true }, @{ clusterName = 'c3'; driftControlEnforced = $null }) } } }
        NotAssessed = @{ domains = @{ hybrid = @{ azureLocalSecuritySettingsMeasured = $false; azureLocalSecuritySettings = @() } } }
    }
)
