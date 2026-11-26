#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300 -- the "WAF: Service Guides" assessment (src/assess/rules/waf.serviceguides.yaml).

    Pins, against small collect objects built here with no Azure connection:
      - the rule file's shape: unique ids (also across every rule file), each id enumerated in
        docs/frameworks/waf-service-guides-checklist.md, titles and remediation starting with their id,
        every rule gated on the resource type it assesses
      - a COMPLIANT estate: every automated rule Pass, every manual rule Manual
      - a NON-COMPLIANT estate: every automated rule Fail, so no rule is vacuous
      - an EMPTY estate: every rule NotAssessed
      - "absent means bad" and null handling, joins that depend on id casing, and the web-app /
        function-app and AKS node scale set splits
      - the manual rules converted to automated now their data is collected: CASA-AV-03, AV-05,
        PM-04, SS-01 and IR-02, WAF-OE-06 (and CASA-AV-04, which deliberately stays manual)
      - the four service-guide items converted with the phase 4 batch 2 per-resource ARM reads
        (WAF-SVC-APP-13 and APP-14 from web app configuration and basic-authentication policies,
        WAF-SVC-FILES-05 and FILES-06 from the file service properties), each gated on its Measured
        flag so a run that never read the setting is Not assessed instead of a pass

    Automated rules are proven twice, once failing and once passing, so a query that always passes or
    always fails cannot slip through.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    Import-Module powershell-yaml -ErrorAction Stop
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Get-RuleSet.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Resolve-JsonPath.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Resolve-RuleJoin.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Invoke-Rule.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/Invoke-Assessment.ps1')

    $script:RuleFile = Join-Path -Path $script:Root -ChildPath 'src/assess/rules/waf.serviceguides.yaml'
    $script:DocFile = Join-Path -Path $script:Root -ChildPath 'docs/frameworks/waf-service-guides-checklist.md'
    $script:Set = @(Get-RuleSet -Patterns @('waf.serviceguides'))[0]

    function Invoke-ServiceGuideAssessment {
        param($Estate)
        $json = $Estate | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        @(Invoke-Assessment -Collect $json -RuleSet @($script:Set) -Assessment 'WAF: Service Guides')
    }

    function Get-DiagnosticRow {
        param([string] $Type, [double] $Percent)
        [ordered]@{ type = $Type; total = 2; withDiag = [int]($Percent / 50); coveragePct = $Percent }
    }

    # One estate with at least one resource of every type the rule file assesses. -Good builds a
    # compliant one; otherwise every automated rule has something to fail on.
    function New-ServiceGuideEstate {
        param([bool] $Good)

        $sub = '/subscriptions/sub-test/resourceGroups/rg-test/providers'
        $id = @{
            Vnet = "$sub/Microsoft.Network/virtualNetworks/vnet1"
            Vm   = "$sub/Microsoft.Compute/virtualMachines/vm1"
            Vmss = "$sub/Microsoft.Compute/virtualMachineScaleSets/vmss1"
            Plan = "$sub/Microsoft.Web/serverfarms/plan1"
            Apim = "$sub/Microsoft.ApiManagement/service/apim1"
            Sb   = "$sub/Microsoft.ServiceBus/namespaces/sb1"
            Eg   = "$sub/Microsoft.EventGrid/topics/eg1"
        }
        $pct = if ($Good) { 100.0 } else { 50.0 }
        $diagTypes = 'microsoft.web/sites', 'microsoft.apimanagement/service', 'microsoft.servicebus/namespaces',
            'microsoft.eventgrid/topics', 'microsoft.network/azurefirewalls', 'microsoft.network/applicationgateways',
            'microsoft.network/loadbalancers', 'microsoft.cdn/profiles', 'microsoft.network/trafficmanagerprofiles',
            'microsoft.network/vpngateways'

        # ---- networking ----
        $networking = [ordered]@{}
        $networking.virtualNetworks = @([ordered]@{ id = $id.Vnet; name = 'vnet1'; location = 'eastus'; ddosEnabled = $Good; encryptionEnabled = $Good })
        $networking.subnets = @([ordered]@{ vnet = 'vnet1'; subnet = 's1'; ipUtilizationPct = $(if ($Good) { 10 } else { 85 }) })
        $networking.nsgPublicInbound = @(if (-not $Good) { [ordered]@{ nsg = 'nsg1'; rule = 'any'; port = '*' } })
        $networking.privateEndpoints = @(if ($Good) {
                [ordered]@{ name = 'pe1'; targetResourceId = $id.Sb.ToUpperInvariant() }
                [ordered]@{ name = 'pe2'; targetResourceId = $id.Eg }
            })
        $networking.networkManagers = @(if ($Good) { [ordered]@{ name = 'avnm' } })
        $networking.publicIPAddresses = @(if ($Good) {
                [ordered]@{ name = 'pip1'; location = 'eastus'; skuName = 'Standard'; zoneCount = 3; attached = $true }
            }
            else {
                [ordered]@{ name = 'pip-basic'; location = 'eastus'; skuName = 'Basic'; zoneCount = $null; attached = $false }
                [ordered]@{ name = 'pip-nozone'; location = 'eastus'; skuName = 'Standard'; zoneCount = $null; attached = $true }
            })
        $networking.flowLogs = @(if ($Good) {
                [ordered]@{ id = 'fl1'; enabled = $true; targetResourceId = $id.Vnet.ToLowerInvariant(); trafficAnalytics = $true }
            }
            else {
                [ordered]@{ id = 'fl1'; enabled = $true; targetResourceId = "$sub/microsoft.network/virtualnetworks/other"; trafficAnalytics = $false }
            })
        $networking.azureFirewalls = @(if ($Good) {
                [ordered]@{ name = 'fw1'; sku = 'AZFW_VNet'; tier = 'Premium'; zoneCount = 3; hasPolicy = $true; threatIntelMode = 'Deny' }
                [ordered]@{ name = 'fw-hub'; sku = 'AZFW_Hub'; tier = 'Premium'; zoneCount = 3; hasPolicy = $true; threatIntelMode = 'Deny' }
            }
            else {
                [ordered]@{ name = 'fw1'; sku = 'AZFW_VNet'; tier = 'Standard'; zoneCount = $null; hasPolicy = $false; threatIntelMode = 'Alert' }
            })
        $networking.firewallPolicies = @([ordered]@{ name = 'fwp1'; sku = $(if ($Good) { 'Premium' } else { 'Standard' }); threatIntelMode = $(if ($Good) { 'Deny' } else { 'Alert' })
                idpsEnabled = $Good; tlsInspectionEnabled = $Good; dnsProxyEnabled = $Good; hasBasePolicy = $false; idpsTlsDnsEnabled = $Good })
        $networking.routeTables = @([ordered]@{ name = 'rt1'; subnetCount = 1; defaultRouteNextHopType = 'VirtualAppliance' })
        $networking.networkWatchers = @([ordered]@{ name = 'nw1' })
        $networking.applicationGateways = @(if ($Good) {
                [ordered]@{ name = 'agw1'; location = 'eastus'; tier = 'WAF_v2'; wafEnabled = $true; zoneCount = 3; probeCount = 2; autoscaleMin = 2; autoscaleMax = 125
                    sslPolicyType = 'Predefined'; sslPolicyName = 'AppGwSslPolicy20220101'; sslMinProtocol = 'TLSv1_2' }
            }
            else {
                [ordered]@{ name = 'agw-v1'; location = 'eastus'; tier = 'Standard'; wafEnabled = $false; zoneCount = $null; probeCount = 0; autoscaleMin = $null; autoscaleMax = 10
                    sslPolicyType = ''; sslPolicyName = ''; sslMinProtocol = '' }
                [ordered]@{ name = 'agw-v2'; location = 'eastus'; tier = 'Standard_v2'; wafEnabled = $false; zoneCount = $null; probeCount = 0; autoscaleMin = $null; autoscaleMax = $null
                    sslPolicyType = ''; sslPolicyName = ''; sslMinProtocol = '' }
            })
        $networking.loadBalancers = @(if ($Good) {
                [ordered]@{ name = 'lb1'; location = 'eastus'; sku = 'Standard'; tier = 'Regional'; hasPublicFrontend = $false; probeCount = 1; ruleCount = 1; minFrontendZoneCount = 3 }
            }
            else {
                [ordered]@{ name = 'lb-basic'; location = 'eastus'; sku = 'Basic'; tier = 'Regional'; hasPublicFrontend = $true; probeCount = 0; ruleCount = 0; minFrontendZoneCount = 0 }
                [ordered]@{ name = 'lb-internal'; location = 'eastus'; sku = 'Standard'; tier = 'Regional'; hasPublicFrontend = $false; probeCount = 1; ruleCount = 1; minFrontendZoneCount = 1 }
            })
        $networking.trafficManagerProfiles = @([ordered]@{ name = 'tm1'; endpointCount = $(if ($Good) { 2 } else { 1 }); monitorStatus = $(if ($Good) { 'Online' } else { 'Degraded' })
                dnsTtl = $(if ($Good) { 30 } else { 300 }); alwaysServeEndpointCount = $(if ($Good) { 0 } else { 1 }) })
        $networking.virtualWans = @([ordered]@{ name = 'wan1'; wanType = $(if ($Good) { 'Standard' } else { 'Basic' }) })
        $networking.virtualHubs = @([ordered]@{ name = 'hub1'; virtualWanName = 'wan1'; hasExpressRouteGateway = $true; hasVpnGateway = $Good; routingPreference = 'ExpressRoute'; expressRouteBackedUp = $Good })
        $networking.vpnConnections = @([ordered]@{ name = 'conn1' })
        $networking.expressRouteCircuits = @(if ($Good) {
                [ordered]@{ name = 'er1'; serviceProviderProvisioningState = 'Provisioned' }
                [ordered]@{ name = 'er2'; serviceProviderProvisioningState = 'Provisioned' }
            }
            else {
                [ordered]@{ name = 'er1'; serviceProviderProvisioningState = 'NotProvisioned' }
            })
        $networking.vpnGateways = @(if ($Good) {
                [ordered]@{ name = 'ergw'; gatewayType = 'ExpressRoute'; sku = 'ErGw1AZ' }
                [ordered]@{ name = 'vpngw'; gatewayType = 'Vpn'; sku = 'VpnGw1AZ' }
            }
            else {
                [ordered]@{ name = 'ergw'; gatewayType = 'ExpressRoute'; sku = 'Standard' }
            })
        $networking.cdnProfiles = @([ordered]@{ name = 'afd1'; sku = $(if ($Good) { 'Premium_AzureFrontDoor' } else { 'Standard_AzureFrontDoor' }) })

        # ---- compute ----
        $compute = [ordered]@{}
        $compute.virtualMachines = @(if ($Good) {
                [ordered]@{ id = $id.Vm; name = 'vm1'; zoneEligible = $true; zoneRedundant = $true; osType = 'Windows'; licenseType = 'Windows_Server'; patchMode = 'AutomaticByPlatform'
                    unmanagedOsDisk = $false; securityType = 'TrustedLaunch'; encryptionAtHost = $true; bootDiagnostics = $true; identityType = 'SystemAssigned' }
            }
            else {
                [ordered]@{ id = $id.Vm; name = 'vm1'; zoneEligible = $true; zoneRedundant = $false; osType = 'Windows'; licenseType = ''; patchMode = 'Manual'
                    unmanagedOsDisk = $true; securityType = ''; encryptionAtHost = $null; bootDiagnostics = $false; identityType = '' }
            })
        $compute.virtualMachineScaleSets = @(if ($Good) {
                [ordered]@{ id = $id.Vmss; name = 'vmss1'; resourceGroup = 'rg-test'; location = 'eastus'; zoneCount = 3; orchestrationMode = 'Flexible'; automaticRepairs = $true; upgradeMode = 'Automatic'; encryptionAtHost = $true }
            }
            else {
                [ordered]@{ id = $id.Vmss; name = 'vmss1'; resourceGroup = 'rg-test'; location = 'eastus'; zoneCount = 1; orchestrationMode = 'Uniform'; automaticRepairs = $false; upgradeMode = 'Manual'; encryptionAtHost = $null }
            })

        # ---- management / monitor / governance / security ----
        $management = [ordered]@{
            backupProtectedItems      = @(if ($Good) { [ordered]@{ name = 'bi1'; sourceResourceId = $id.Vm.ToUpperInvariant() } })
            maintenanceConfigurations = @([ordered]@{ name = 'mc1' })
        }
        $autoscaleTargets = if ($Good) { $id.Vmss, $id.Apim, $id.Plan } else { @() }
        $monitor = [ordered]@{
            appInsights         = @(if ($Good) {
                    [ordered]@{ name = 'ai1'; workspaceBased = $true; disableLocalAuth = $true; disableIpMasking = $false; publicNetworkAccessForIngestion = 'Disabled'; publicNetworkAccessForQuery = 'Disabled' }
                }
                else {
                    [ordered]@{ name = 'ai1'; workspaceBased = $false; disableLocalAuth = $null; disableIpMasking = $true; publicNetworkAccessForIngestion = 'Enabled'; publicNetworkAccessForQuery = 'Enabled' }
                })
            autoscaleSettings   = @(if ($Good) { foreach ($t in $autoscaleTargets) { [ordered]@{ name = 'as'; enabled = $true; targetResourceUri = $t.ToLowerInvariant() } } }
                else { [ordered]@{ name = 'as-off'; enabled = $false; targetResourceUri = $id.Vmss.ToLowerInvariant() } })
            metricAlertRules    = @([ordered]@{ name = 'ma1'; enabled = $true; actionGroupCount = 1 })
            dataCollectionRules = @([ordered]@{ name = 'dcr1' })
        }
        $plans = 'AppServices', 'Api', 'VirtualMachines'
        $tier = if ($Good) { 'Standard' } else { 'Free' }
        $security = [ordered]@{
            defenderPlans = @(foreach ($p in $plans) { [ordered]@{ name = $p; properties = [ordered]@{ pricingTier = $tier } } })
            wafPolicies   = @(if ($Good) {
                    [ordered]@{ name = 'wp-agw'; type = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'; mode = 'Prevention' }
                    [ordered]@{ name = 'wp-afd'; type = 'microsoft.network/frontdoorwebapplicationfirewallpolicies'; mode = 'Prevention' }
                }
                else {
                    [ordered]@{ name = 'wp-agw'; type = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'; mode = 'Detection' }
                })
        }

        # ---- domains ----
        $web = [ordered]@{}
        $webGood = [ordered]@{ identityType = 'SystemAssigned'; httpsOnly = $true; minTls = '1.2'; publicNetworkAccess = 'Disabled'; vnetIntegrated = $true; customDomainBound = $true }
        $webBad = [ordered]@{ identityType = ''; httpsOnly = $false; minTls = '1.0'; publicNetworkAccess = 'Enabled'; vnetIntegrated = $false; customDomainBound = $false }
        $webProps = if ($Good) { $webGood } else { $webBad }
        $web.webApps = @(foreach ($app in @(@{ n = 'app1'; k = 'app,linux' }, @{ n = 'func1'; k = 'functionapp,linux' })) {
                $row = [ordered]@{ id = "$sub/Microsoft.Web/sites/$($app.n)"; name = $app.n; kind = $app.k }
                foreach ($key in $webProps.Keys) { $row[$key] = $webProps[$key] }
                $row
            })
        # AB#9300 phase 4 batch 2: per-site configuration and basic-authentication policies, one row per site
        # keyed by the lower-cased site id. The function app is deliberately "bad" on Always On in the bad
        # estate, to prove WAF-SVC-APP-13 is limited to web apps.
        $web.webAppConfigMeasured = $true
        $web.webAppBasicAuthMeasured = $true
        $web.webAppConfig = @(foreach ($app in @('app1', 'func1')) {
                $siteId = "$sub/Microsoft.Web/sites/$app".ToLowerInvariant()
                if ($Good) { [ordered]@{ webAppId = $siteId; name = $app; ftpsState = 'FtpsOnly'; alwaysOn = $true; healthCheckPathSet = $true; remoteDebuggingEnabled = $false; http20Enabled = $true; minTlsVersion = '1.2'; scmMinTlsVersion = '1.2' } }
                else { [ordered]@{ webAppId = $siteId; name = $app; ftpsState = 'AllAllowed'; alwaysOn = $false; healthCheckPathSet = $false; remoteDebuggingEnabled = $true; http20Enabled = $false; minTlsVersion = '1.0'; scmMinTlsVersion = '1.0' } }
            })
        $web.webAppBasicAuth = @(foreach ($app in @('app1', 'func1')) {
                [ordered]@{ webAppId = "$sub/Microsoft.Web/sites/$app".ToLowerInvariant(); name = $app; ftpBasicAuthAllowed = (-not $Good); scmBasicAuthAllowed = (-not $Good) }
            })
        $web.appServicePlans = @(if ($Good) {
                [ordered]@{ id = $id.Plan; name = 'plan1'; location = 'eastus'; tier = 'PremiumV3'; zoneRedundant = $true; instanceCount = 3 }
            }
            else {
                [ordered]@{ id = "$sub/Microsoft.Web/serverfarms/plan-basic"; name = 'plan-basic'; location = 'eastus'; tier = 'Basic'; zoneRedundant = $false; instanceCount = 1 }
                [ordered]@{ id = $id.Plan; name = 'plan1'; location = 'eastus'; tier = 'PremiumV3'; zoneRedundant = $false; instanceCount = 1 }
            })

        $containers = [ordered]@{}
        $containers.aksClusters = @(if ($Good) {
                [ordered]@{ id = "$sub/Microsoft.ContainerService/managedClusters/aks1"; name = 'aks1'; location = 'eastus'; tier = 'Standard'; allPoolsZoned = $true; aadIntegrated = $true
                    disableLocalAccounts = $true; azureRbac = $true; privateCluster = $false; authorizedIpRangeCount = 2; workloadIdentity = $true; defenderEnabled = $true
                    networkPolicyEnabled = $true; upgradeChannel = 'stable'; allPoolsAutoscale = $true; azurePolicyAddon = $true }
            }
            else {
                [ordered]@{ id = "$sub/Microsoft.ContainerService/managedClusters/aks1"; name = 'aks1'; location = 'eastus'; tier = 'Free'; allPoolsZoned = $false; aadIntegrated = $false
                    disableLocalAccounts = $null; azureRbac = $false; privateCluster = $false; authorizedIpRangeCount = $null; workloadIdentity = $false; defenderEnabled = $null
                    networkPolicyEnabled = $false; upgradeChannel = 'none'; allPoolsAutoscale = $false; azurePolicyAddon = $null }
            })
        $containers.containerApps = @([ordered]@{ name = 'ca1'; externalIngress = $true; minReplicas = $(if ($Good) { 3 } else { 0 }); allowInsecure = (-not $Good); identityType = $(if ($Good) { 'SystemAssigned' } else { '' })
                containerCount = 1; containersWithoutAllProbes = $(if ($Good) { 0 } else { 1 }) })
        $containers.containerAppEnvironments = @([ordered]@{ name = 'cae1'; location = 'eastus'; zoneRedundant = $Good; internal = $Good; vnetIntegrated = $Good; publicNetworkAccess = $(if ($Good) { 'Disabled' } else { 'Enabled' })
                logDestination = $(if ($Good) { 'azure-monitor' } else { 'none' }); logsExported = $Good })

        $storage = [ordered]@{}
        $storage.storageAccounts = @(if ($Good) {
                [ordered]@{ id = "$sub/Microsoft.Storage/storageAccounts/st1"; name = 'st1'; kind = 'StorageV2'; sku = 'Standard_ZRS'; minTls = 'TLS1_2'; httpsOnly = $true; publicNetworkAccess = 'Disabled'; networkDefaultDeny = $true }
            }
            else {
                [ordered]@{ id = "$sub/Microsoft.Storage/storageAccounts/st1"; name = 'st1'; kind = 'StorageV2'; sku = 'Standard_LRS'; minTls = ''; httpsOnly = $false; publicNetworkAccess = 'Enabled'; networkDefaultDeny = $false }
            })
        # AB#9300 phase 4 batch 2: file service properties, keyed by the lower-cased account id. null SMB strings
        # mean every version and algorithm is allowed.
        $storage.fileServicePropertiesMeasured = $true
        $storage.fileServiceProperties = @([ordered]@{
                storageAccountId = "$sub/Microsoft.Storage/storageAccounts/st1".ToLowerInvariant(); name = 'st1'
                shareDeleteRetentionEnabled = $Good; shareDeleteRetentionDays = $(if ($Good) { 14 } else { $null })
                smbVersions = $(if ($Good) { 'SMB3.1.1' } else { $null }); smbChannelEncryption = $(if ($Good) { 'AES-256-GCM' } else { $null })
                smbAuthenticationMethods = $(if ($Good) { 'Kerberos' } else { $null })
            })
        $storage.managedDisks = @(if ($Good) {
                [ordered]@{ id = 'd1'; name = 'd1'; location = 'eastus'; sku = 'Premium_ZRS'; diskState = 'Attached'; zoneCount = 3; publicNetworkAccess = 'Disabled'; encryptionType = 'EncryptionAtRestWithCustomerKey' }
            }
            else {
                [ordered]@{ id = 'd1'; name = 'd1'; location = 'eastus'; sku = 'Premium_LRS'; diskState = 'Attached'; zoneCount = $null; publicNetworkAccess = 'Enabled'; encryptionType = 'EncryptionAtRestWithPlatformKey' }
                [ordered]@{ id = 'd2'; name = 'd2'; location = 'eastus'; sku = 'Standard_LRS'; diskState = 'Attached'; zoneCount = $null; publicNetworkAccess = ''; encryptionType = '' }
            })
        $storage.netAppVolumes = @([ordered]@{ id = 'v1'; name = 'vol1'; provisioningState = 'Succeeded'; usageThresholdGB = 100 })

        $integration = [ordered]@{}
        $integration.apiManagement = @(if ($Good) {
                [ordered]@{ id = $id.Apim; name = 'apim1'; sku = 'Premium'; virtualNetworkType = 'None'; zoneCount = 3; capacity = 2; additionalRegionCount = 1; publicNetworkAccess = 'Disabled'; identityType = 'SystemAssigned'
                    legacyProtocolEnabled = $false; legacyCipherEnabled = $false }
            }
            else {
                [ordered]@{ id = $id.Apim; name = 'apim1'; sku = 'Premium'; virtualNetworkType = 'None'; zoneCount = $null; capacity = 1; additionalRegionCount = $null; publicNetworkAccess = ''; identityType = ''
                    legacyProtocolEnabled = $true; legacyCipherEnabled = $true }
            })
        $integration.serviceBusNamespaces = @(if ($Good) {
                [ordered]@{ id = $id.Sb; name = 'sb1'; location = 'eastus'; tier = 'Premium'; zoneRedundant = $true; geoReplicaCount = 2; disableLocalAuth = $true; minimumTlsVersion = '1.2'; publicAccess = 'Disabled'; cmkKeySource = 'Microsoft.KeyVault' }
            }
            else {
                [ordered]@{ id = "$sub/Microsoft.ServiceBus/namespaces/sb-std"; name = 'sb-std'; location = 'eastus'; tier = 'Standard'; zoneRedundant = $false; geoReplicaCount = $null; disableLocalAuth = $null; minimumTlsVersion = ''; publicAccess = 'Enabled'; cmkKeySource = '' }
                [ordered]@{ id = $id.Sb; name = 'sb1'; location = 'eastus'; tier = 'Premium'; zoneRedundant = $true; geoReplicaCount = $null; disableLocalAuth = $null; minimumTlsVersion = ''; publicAccess = 'Enabled'; cmkKeySource = '' }
            })
        $integration.eventGrid = @(if ($Good) {
                [ordered]@{ id = $id.Eg; name = 'eg1'; type = 'microsoft.eventgrid/topics'; publicNetworkAccess = 'Disabled'; inboundIpRuleCount = 0; minimumTlsVersion = '1.2'; disableLocalAuth = $true; identityType = 'SystemAssigned' }
            }
            else {
                [ordered]@{ id = $id.Eg; name = 'eg1'; type = 'microsoft.eventgrid/topics'; publicNetworkAccess = 'Enabled'; inboundIpRuleCount = $null; minimumTlsVersion = '1.0'; disableLocalAuth = $null; identityType = '' }
            })

        [ordered]@{
            networking = $networking
            compute    = $compute
            management = $management
            monitor    = $monitor
            governance = [ordered]@{ resourceLocks = @([ordered]@{ name = 'lock1' }) }
            security   = $security
            opsPosture = [ordered]@{
                diagnosticCoverageMeasured = $true
                diagnosticCoverage         = @(foreach ($t in $diagTypes) { Get-DiagnosticRow -Type $t -Percent $pct })
            }
            domains    = [ordered]@{ web = $web; containers = $containers; storage = $storage; integration = $integration }
        }
    }

    function New-EmptyServiceGuideEstate {
        [ordered]@{
            networking = [ordered]@{ virtualNetworks = @(); subnets = @(); nsgPublicInbound = @(); privateEndpoints = @(); networkManagers = @(); publicIPAddresses = @(); flowLogs = @()
                azureFirewalls = @(); firewallPolicies = @(); applicationGateways = @(); loadBalancers = @(); trafficManagerProfiles = @(); virtualWans = @(); expressRouteCircuits = @()
                vpnGateways = @(); cdnProfiles = @() }
            compute    = [ordered]@{ virtualMachines = @(); virtualMachineScaleSets = @() }
            management = [ordered]@{ backupProtectedItems = @() }
            monitor    = [ordered]@{ appInsights = @(); autoscaleSettings = @() }
            security   = [ordered]@{ defenderPlans = @(); wafPolicies = @() }
            opsPosture = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $false }
            domains    = [ordered]@{
                web = [ordered]@{ webApps = @(); appServicePlans = @(); webAppConfig = @(); webAppConfigMeasured = $false; webAppBasicAuth = @(); webAppBasicAuthMeasured = $false }
                containers = [ordered]@{ aksClusters = @(); containerApps = @(); containerAppEnvironments = @() }
                storage = [ordered]@{ storageAccounts = @(); managedDisks = @(); netAppVolumes = @(); fileServiceProperties = @(); fileServicePropertiesMeasured = $false }
                integration = [ordered]@{ apiManagement = @(); serviceBusNamespaces = @(); eventGrid = @() }
            }
        }
    }

    $script:Good = Invoke-ServiceGuideAssessment -Estate (New-ServiceGuideEstate -Good $true)
    $script:Bad = Invoke-ServiceGuideAssessment -Estate (New-ServiceGuideEstate -Good $false)
    $script:Empty = Invoke-ServiceGuideAssessment -Estate (New-EmptyServiceGuideEstate)
    $script:Rules = @($script:Set.Rules)
    $script:Automated = @($script:Rules | Where-Object { -not $_.manual })
    $script:Manual = @($script:Rules | Where-Object { $_.manual })
    $script:Doc = Get-Content -LiteralPath $script:DocFile -Raw
}

Describe 'waf.serviceguides.yaml -- shape' {
    It 'declares the WAF-SVC framework with a service-guides area and a frameworkversion citing its checklist' {
        $script:Set.Framework | Should -Be 'WAF-SVC'
        $script:Set.Area | Should -Be 'Service guides'
        $script:Set.Area | Should -Not -BeIn @('Reliability', 'Security', 'Cost optimization', 'Operational excellence', 'Performance efficiency')
        $script:Set.FrameworkVersion | Should -Match 'waf-service-guides-checklist\.md'
    }

    It 'loads 214 rules, 138 automated and 76 manual, with unique ids' {
        $script:Rules.Count | Should -Be 214
        $script:Automated.Count | Should -Be 138
        $script:Manual.Count | Should -Be 76
        @($script:Rules.id | Select-Object -Unique).Count | Should -Be 214
    }

    It 'names every id WAF-SVC plus a service code and two digits, covers all 21 service sections, and never reuses an id in another rule file' {
        $codes = 'AKS', 'APP', 'FUNC', 'ACA', 'APIM', 'SB', 'EG', 'FW', 'AGW', 'LB', 'VNET', 'VM', 'VMSS', 'DISK', 'APPI', 'AFD', 'TM', 'VWAN', 'ER', 'FILES', 'ANF'
        foreach ($rule in $script:Rules) { $rule.id | Should -Match '^WAF-SVC-[A-Z]+-\d\d$' }
        foreach ($code in $codes) { @($script:Rules | Where-Object { $_.id -like "WAF-SVC-$code-*" }).Count | Should -BeGreaterThan 0 -Because "$code must have rules" }

        $elsewhere = foreach ($file in Get-ChildItem -LiteralPath (Split-Path $script:RuleFile) -Filter '*.yaml' -File | Where-Object Name -ne 'waf.serviceguides.yaml') {
            $doc = ConvertFrom-Yaml (Get-Content -LiteralPath $file.FullName -Raw)
            foreach ($r in @($doc.rules)) { if ([string]$r.id -like 'WAF-SVC-*') { "$($file.Name):$($r.id)" } }
        }
        @($elsewhere) | Should -BeNullOrEmpty
    }

    It 'starts every title and every remediation with its own id' {
        foreach ($rule in $script:Rules) {
            $rule.title | Should -BeLike "$($rule.id). *"
            $rule.remediation | Should -BeLike "$($rule.id). *"
        }
    }

    It 'gates every rule, automated or manual, on the resource type it assesses' {
        $ungated = @($script:Rules | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.assert.gate) } | ForEach-Object { $_.id })
        $ungated | Should -BeNullOrEmpty
    }

    It 'keeps every manual rule as assert.type manual and every automated rule off it' {
        foreach ($r in $script:Manual) { $r.assert.type | Should -Be 'manual' }
        foreach ($r in $script:Automated) { $r.assert.type | Should -Not -Be 'manual' }
    }

    It 'only uses supported join shapes (leftOnly or leftMatched on a collected id key) and no grouping parentheses in a filter' {
        foreach ($r in $script:Rules) {
            if ($r.ContainsKey('join') -and $r.join) {
                $r.join.mode | Should -BeIn @('leftOnly', 'leftMatched')
                $r.join.left | Should -Match '\]$'
                $r.join.right | Should -Match '\]$'
            }
            foreach ($path in @(if ($r.ContainsKey('query')) { [string]$r.query }; [string]$r.assert.gate)) {
                # a filter body may contain "(" only as "?(" or inside a regex literal between slashes
                $stripped = [regex]::Replace($path, '/(\\.|[^/])*/i?', '').Replace('?(', '')
                $stripped | Should -Not -Match '\(' -Because "$($r.id) uses a grouping parenthesis"
                $stripped | Should -Not -Match '&&.*\|\||\|\|.*&&' -Because "$($r.id) mixes && and ||"
            }
        }
    }
}

Describe 'waf-service-guides-checklist.md' {
    It 'carries the Shape B header every enumeration file needs' {
        $script:Doc | Should -Match '\*\*Enumerated 2026-11-25\.'
        $script:Doc | Should -Match '\| Framework version \|'
        $script:Doc | Should -Match '\| Extraction date \| 2026-11-25 \|'
        $script:Doc | Should -Match '\| Verification method \|'
        $script:Doc | Should -Match 'https://learn\.microsoft\.com/azure/well-architected/service-guides'
    }

    It 'enumerates every rule id and no id that has no rule' {
        $missing = @($script:Rules | Where-Object { $script:Doc -notmatch [regex]::Escape($_.id) } | ForEach-Object { $_.id })
        $missing | Should -BeNullOrEmpty
        $inDoc = @([regex]::Matches($script:Doc, 'WAF-SVC-[A-Z]+-\d\d') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $orphans = @($inDoc | Where-Object { $_ -notin $script:Rules.id })
        $orphans | Should -BeNullOrEmpty
    }

    It 'cites the URL of every service guide' {
        foreach ($slug in 'azure-kubernetes-service', 'app-service-web-apps', 'azure-functions', 'azure-container-apps', 'azure-api-management', 'azure-service-bus', 'azure-event-grid',
            'azure-firewall', 'azure-application-gateway', 'azure-load-balancer', 'virtual-network', 'virtual-machines', 'azure-disk-storage', 'application-insights',
            'azure-front-door', 'azure-traffic-manager', 'azure-virtual-wan', 'azure-expressroute', 'azure-files', 'azure-netapp-files') {
            $script:Doc | Should -Match "https://learn\.microsoft\.com/azure/well-architected/service-guides/$slug"
        }
    }

    It 'states the same totals the rule file holds' {
        $script:Doc | Should -Match '\| \*\*Total\*\* \| \*\*214\*\* \| \*\*138\*\* \| \*\*76\*\* \|'
    }
}

Describe 'A compliant estate' {
    It 'produces no Error finding and one finding per rule' {
        @($script:Good | Where-Object Status -eq 'Error').Count | Should -Be 0
        $script:Good.Count | Should -Be 214
    }

    It 'passes every automated rule' {
        $notPass = @($script:Good | Where-Object { -not $_.Manual -and $_.Status -ne 'Pass' } | ForEach-Object { "$($_.Id)=$($_.Status)" })
        $notPass | Should -BeNullOrEmpty
    }

    It 'leaves every manual rule Manual, never NotAssessed, because every guide has a resource' {
        $notManual = @($script:Good | Where-Object { $_.Manual -and $_.Status -ne 'Manual' } | ForEach-Object { "$($_.Id)=$($_.Status)" })
        $notManual | Should -BeNullOrEmpty
    }
}

Describe 'A non-compliant estate' {
    It 'produces no Error finding' {
        @($script:Bad | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'fails every automated rule, so no query is vacuous' {
        $notFail = @($script:Bad | Where-Object { -not $_.Manual -and $_.Status -ne 'Fail' } | ForEach-Object { "$($_.Id)=$($_.Status)" })
        $notFail | Should -BeNullOrEmpty
    }

    It 'names the offending resources of a failing rule' {
        ($script:Bad | Where-Object Id -eq 'WAF-SVC-SB-04').EvidenceCount | Should -Be 2
        ($script:Bad | Where-Object Id -eq 'WAF-SVC-SB-06').EvidenceCount | Should -Be 1 -Because 'only the Premium namespace is in scope'
        ($script:Bad | Where-Object Id -eq 'WAF-SVC-DISK-02').EvidenceCount | Should -Be 1 -Because 'only the Standard HDD disk breaks it'
        ($script:Bad | Where-Object Id -eq 'WAF-SVC-VNET-01').EvidenceCount | Should -Be 1
    }

    It 'attaches the closest evidence to a manual rule' {
        $aks = $script:Bad | Where-Object Id -eq 'WAF-SVC-AKS-12'
        $aks.Status | Should -Be 'Manual'
        $aks.EvidenceCount | Should -Be 1
    }
}

Describe 'An estate with none of these services' {
    It 'reports every rule, automated or manual, NotAssessed' {
        $script:Empty.Count | Should -Be 214
        @($script:Empty | Where-Object Status -ne 'NotAssessed').Count | Should -Be 0
    }
}

Describe 'Absent means bad, and null handling' {
    It 'scores <Id> as <Status> when <Name>' -ForEach @(
        @{ Name = 'a Service Bus namespace omits disableLocalAuth'; Id = 'WAF-SVC-SB-04'; Status = 'Fail'; Mutate = { param($e) $e.domains.integration.serviceBusNamespaces[0].disableLocalAuth = $null } }
        @{ Name = 'a Service Bus namespace omits its TLS version'; Id = 'WAF-SVC-SB-05'; Status = 'Fail'; Mutate = { param($e) $e.domains.integration.serviceBusNamespaces[0].minimumTlsVersion = '' } }
        @{ Name = 'a Premium namespace is secured by a perimeter'; Id = 'WAF-SVC-SB-06'; Status = 'Pass'; Mutate = { param($e) $e.domains.integration.serviceBusNamespaces[0].publicAccess = 'SecuredByPerimeter' } }
        @{ Name = 'an Event Grid topic omits disableLocalAuth'; Id = 'WAF-SVC-EG-01'; Status = 'Fail'; Mutate = { param($e) $e.domains.integration.eventGrid[0].disableLocalAuth = $null } }
        @{ Name = 'an Event Grid topic is public with a null IP rule count'; Id = 'WAF-SVC-EG-02'; Status = 'Fail'; Mutate = { param($e) $e.domains.integration.eventGrid[0].publicNetworkAccess = 'Enabled'; $e.domains.integration.eventGrid[0].inboundIpRuleCount = $null } }
        @{ Name = 'an Event Grid topic is public but has IP rules'; Id = 'WAF-SVC-EG-02'; Status = 'Pass'; Mutate = { param($e) $e.domains.integration.eventGrid[0].publicNetworkAccess = 'Enabled'; $e.domains.integration.eventGrid[0].inboundIpRuleCount = 3 } }
        @{ Name = 'a storage account omits its minimum TLS version'; Id = 'WAF-SVC-FILES-02'; Status = 'Fail'; Mutate = { param($e) $e.domains.storage.storageAccounts[0].minTls = '' } }
        @{ Name = 'a storage account is public but behind a deny-by-default firewall'; Id = 'WAF-SVC-FILES-04'; Status = 'Pass'; Mutate = { param($e) $e.domains.storage.storageAccounts[0].publicNetworkAccess = 'Enabled' } }
        @{ Name = 'a public AKS cluster reports no authorized ranges'; Id = 'WAF-SVC-AKS-06'; Status = 'Fail'; Mutate = { param($e) $e.domains.containers.aksClusters[0].authorizedIpRangeCount = $null } }
        @{ Name = 'a private AKS cluster reports no authorized ranges'; Id = 'WAF-SVC-AKS-06'; Status = 'Pass'; Mutate = { param($e) $e.domains.containers.aksClusters[0].privateCluster = $true; $e.domains.containers.aksClusters[0].authorizedIpRangeCount = $null } }
        @{ Name = 'an AKS cluster omits disableLocalAccounts'; Id = 'WAF-SVC-AKS-04'; Status = 'Fail'; Mutate = { param($e) $e.domains.containers.aksClusters[0].disableLocalAccounts = $null } }
        @{ Name = 'an AKS cluster has no upgrade channel'; Id = 'WAF-SVC-AKS-10'; Status = 'Fail'; Mutate = { param($e) $e.domains.containers.aksClusters[0].upgradeChannel = '' } }
        @{ Name = 'a firewall reports no zone count'; Id = 'WAF-SVC-FW-01'; Status = 'Fail'; Mutate = { param($e) $e.networking.azureFirewalls[0].zoneCount = $null } }
        @{ Name = 'a classic firewall runs Alert, not Deny'; Id = 'WAF-SVC-FW-04'; Status = 'Fail'; Mutate = { param($e) $e.networking.azureFirewalls[0].hasPolicy = $false; $e.networking.azureFirewalls[0].threatIntelMode = 'Alert' } }
        @{ Name = 'a Basic-tier classic firewall cannot run Deny'; Id = 'WAF-SVC-FW-04'; Status = 'Pass'; Mutate = { param($e) $e.networking.azureFirewalls[0].hasPolicy = $false; $e.networking.azureFirewalls[0].tier = 'Basic'; $e.networking.azureFirewalls[0].threatIntelMode = 'Alert' } }
        @{ Name = 'a v2 gateway has no autoscale maximum'; Id = 'WAF-SVC-AGW-07'; Status = 'Fail'; Mutate = { param($e) $e.networking.applicationGateways[0].autoscaleMax = $null } }
        @{ Name = 'a gateway sets a TLS 1.0 minimum'; Id = 'WAF-SVC-AGW-06'; Status = 'Fail'; Mutate = { param($e) $e.networking.applicationGateways[0].sslPolicyType = 'Custom'; $e.networking.applicationGateways[0].sslMinProtocol = 'TLSv1_0' } }
        @{ Name = 'a gateway is in a region with no zones'; Id = 'WAF-SVC-AGW-02'; Status = 'Pass'; Mutate = { param($e) $e.networking.applicationGateways[0].location = 'westus'; $e.networking.applicationGateways[0].zoneCount = $null } }
        @{ Name = 'a virtual machine omits encryptionAtHost'; Id = 'WAF-SVC-VM-04'; Status = 'Fail'; Mutate = { param($e) $e.compute.virtualMachines[0].encryptionAtHost = $null } }
        @{ Name = 'a virtual machine is in a region with no zones'; Id = 'WAF-SVC-VM-01'; Status = 'Pass'; Mutate = { param($e) $e.compute.virtualMachines[0].zoneEligible = $false; $e.compute.virtualMachines[0].zoneRedundant = $false } }
        @{ Name = 'a Premium API Management instance omits its unit count'; Id = 'WAF-SVC-APIM-02'; Status = 'Fail'; Mutate = { param($e) $e.domains.integration.apiManagement[0].capacity = $null } }
        @{ Name = 'a Developer API Management instance has one unit'; Id = 'WAF-SVC-APIM-02'; Status = 'Pass'; Mutate = { param($e) $e.domains.integration.apiManagement[0].sku = 'Developer'; $e.domains.integration.apiManagement[0].capacity = 1 } }
        @{ Name = 'a container app with ingress omits minReplicas'; Id = 'WAF-SVC-ACA-02'; Status = 'Fail'; Mutate = { param($e) $e.domains.containers.containerApps[0].minReplicas = $null } }
        @{ Name = 'a container app has no ingress and scales to zero'; Id = 'WAF-SVC-ACA-02'; Status = 'Pass'; Mutate = { param($e) $e.domains.containers.containerApps[0].externalIngress = $null; $e.domains.containers.containerApps[0].minReplicas = 0 } }
        @{ Name = 'a disk omits publicNetworkAccess'; Id = 'WAF-SVC-DISK-04'; Status = 'Fail'; Mutate = { param($e) $e.domains.storage.managedDisks[0].publicNetworkAccess = '' } }
        @{ Name = 'an LRS disk is in a region with no zones'; Id = 'WAF-SVC-DISK-01'; Status = 'Pass'; Mutate = { param($e) $d = $e.domains.storage.managedDisks[0]; $d.sku = 'Premium_LRS'; $d.location = 'westus'; $d.zoneCount = $null } }
        @{ Name = 'an internal load balancer sits in a region with no zones'; Id = 'WAF-SVC-LB-04'; Status = 'Pass'; Mutate = { param($e) $l = $e.networking.loadBalancers[0]; $l.location = 'westus'; $l.minFrontendZoneCount = 0 } }
        @{ Name = 'a public load balancer has an unzoned frontend'; Id = 'WAF-SVC-LB-04'; Status = 'Pass'; Mutate = { param($e) $l = $e.networking.loadBalancers[0]; $l.hasPublicFrontend = $true; $l.minFrontendZoneCount = 0 } }
        @{ Name = 'an Application Insights component omits disableLocalAuth'; Id = 'WAF-SVC-APPI-02'; Status = 'Fail'; Mutate = { param($e) $e.monitor.appInsights[0].disableLocalAuth = $null } }
        @{ Name = 'a scale set omits automaticRepairs'; Id = 'WAF-SVC-VMSS-02'; Status = 'Fail'; Mutate = { param($e) $e.compute.virtualMachineScaleSets[0].automaticRepairs = $null } }
        @{ Name = 'a Flexible scale set has no upgrade policy'; Id = 'WAF-SVC-VMSS-05'; Status = 'Pass'; Mutate = { param($e) $e.compute.virtualMachineScaleSets[0].upgradeMode = '' } }
        @{ Name = 'a virtual network omits encryptionEnabled'; Id = 'WAF-SVC-VNET-04'; Status = 'Fail'; Mutate = { param($e) $e.networking.virtualNetworks[0].encryptionEnabled = $null } }
        @{ Name = 'a public IP address has no zone count'; Id = 'WAF-SVC-VNET-02'; Status = 'Fail'; Mutate = { param($e) $e.networking.publicIPAddresses[0].zoneCount = $null } }
        @{ Name = 'a Basic public IP address is unzoned'; Id = 'WAF-SVC-VNET-02'; Status = 'Pass'; Mutate = { param($e) $e.networking.publicIPAddresses[0].skuName = 'Basic'; $e.networking.publicIPAddresses[0].zoneCount = $null } }
    ) {
        $estate = New-ServiceGuideEstate -Good $true
        & $Mutate $estate
        $finding = Invoke-ServiceGuideAssessment -Estate $estate | Where-Object Id -eq $Id
        $finding.Status | Should -Be $Status
    }
}

Describe 'Joins are not defeated by id casing, and scope is honest' {
    It 'matches a virtual network to its flow log whatever the casing of either resource id' {
        $estate = New-ServiceGuideEstate -Good $true
        $estate.networking.virtualNetworks[0].id = $estate.networking.virtualNetworks[0].id.ToUpperInvariant()
        $estate.networking.flowLogs[0].targetResourceId = $estate.networking.flowLogs[0].targetResourceId.ToLowerInvariant()
        (Invoke-ServiceGuideAssessment -Estate $estate | Where-Object Id -eq 'WAF-SVC-VNET-08').Status | Should -Be 'Pass'
    }

    It 'fails a virtual network whose only flow log is disabled' {
        $estate = New-ServiceGuideEstate -Good $true
        $estate.networking.flowLogs[0].enabled = $false
        $findings = Invoke-ServiceGuideAssessment -Estate $estate
        ($findings | Where-Object Id -eq 'WAF-SVC-VNET-08').Status | Should -Be 'Fail'
    }

    It 'matches a virtual machine to its backup item and a namespace to its private endpoint whatever the id casing' {
        $findings = $script:Good
        ($findings | Where-Object Id -eq 'WAF-SVC-VM-02').Status | Should -Be 'Pass'
        ($findings | Where-Object Id -eq 'WAF-SVC-SB-07').Status | Should -Be 'Pass'
        ($findings | Where-Object Id -eq 'WAF-SVC-EG-05').Status | Should -Be 'Pass'
    }

    It 'skips scale sets in an AKS node resource group (MC_*), and assesses nothing when those are all there is' {
        $estate = New-ServiceGuideEstate -Good $false
        $estate.compute.virtualMachineScaleSets = @([ordered]@{ id = 'x'; name = 'aks-nodepool1-vmss'; resourceGroup = 'MC_rg_aks_eastus'; location = 'eastus'; zoneCount = $null; orchestrationMode = 'Uniform'; automaticRepairs = $false; upgradeMode = 'Manual'; encryptionAtHost = $null })
        $findings = Invoke-ServiceGuideAssessment -Estate $estate
        @($findings | Where-Object { $_.Id -like 'WAF-SVC-VMSS-*' -and $_.Status -ne 'NotAssessed' }).Count | Should -Be 0

        $estate.compute.virtualMachineScaleSets += [ordered]@{ id = 'y'; name = 'real'; resourceGroup = 'rg-test'; location = 'eastus'; zoneCount = $null; orchestrationMode = 'Uniform'; automaticRepairs = $false; upgradeMode = 'Manual'; encryptionAtHost = $null }
        $findings = Invoke-ServiceGuideAssessment -Estate $estate
        ($findings | Where-Object Id -eq 'WAF-SVC-VMSS-02').EvidenceCount | Should -Be 1
    }

    It 'keeps web app rules to web apps and function app rules to function apps' {
        $estate = New-ServiceGuideEstate -Good $false
        $estate.domains.web.webApps = @($estate.domains.web.webApps | Where-Object { $_.kind -like 'functionapp*' })
        $findings = Invoke-ServiceGuideAssessment -Estate $estate
        ($findings | Where-Object Id -eq 'WAF-SVC-APP-06').Status | Should -Be 'NotAssessed'
        ($findings | Where-Object Id -eq 'WAF-SVC-FUNC-02').Status | Should -Be 'Fail'

        $estate = New-ServiceGuideEstate -Good $false
        $estate.domains.web.webApps = @($estate.domains.web.webApps | Where-Object { $_.kind -notlike 'functionapp*' })
        $findings = Invoke-ServiceGuideAssessment -Estate $estate
        ($findings | Where-Object Id -eq 'WAF-SVC-APP-06').Status | Should -Be 'Fail'
        ($findings | Where-Object Id -eq 'WAF-SVC-FUNC-02').Status | Should -Be 'NotAssessed'
    }

    It 'leaves a guide NotAssessed when only its diagnostic-settings coverage is unmeasured' {
        $estate = New-ServiceGuideEstate -Good $true
        $estate.opsPosture.diagnosticCoverage = @()
        $findings = Invoke-ServiceGuideAssessment -Estate $estate
        foreach ($id in 'WAF-SVC-APP-12', 'WAF-SVC-APIM-08', 'WAF-SVC-SB-09', 'WAF-SVC-EG-06', 'WAF-SVC-FW-11', 'WAF-SVC-AGW-09', 'WAF-SVC-LB-06', 'WAF-SVC-AFD-03', 'WAF-SVC-TM-03', 'WAF-SVC-VWAN-03') {
            ($findings | Where-Object Id -eq $id).Status | Should -Be 'NotAssessed' -Because "$id must not fail what was never measured"
        }
        ($findings | Where-Object Id -eq 'WAF-SVC-SB-04').Status | Should -Be 'Pass'
    }
}

Describe 'Manual rules converted now that their data is collected (CASA and WAF-OE-06)' {
    BeforeAll {
        $script:CasaSet = @(Get-RuleSet -Patterns @('casa.*'))[0]
        $script:OpsSet = @(Get-RuleSet -Patterns @('waf.operational'))[0]

        function Invoke-OneRule {
            param($Set, [string] $Id, $Collect)
            $rule = @($Set.Rules | Where-Object { $_.id -eq $Id })[0]
            Invoke-Rule -Rule $rule -Collect $Collect -Area $Set.Area -Framework $Set.Framework
        }
        function Get-ScaleCollect { param($Scale, $Auto) [pscustomobject]@{ compute = [pscustomobject]@{ virtualMachineScaleSets = @($Scale) }; monitor = [pscustomobject]@{ autoscaleSettings = @($Auto) } } }
        function Get-LbCollect { param($Lb) [pscustomobject]@{ networking = [pscustomobject]@{ loadBalancers = @($Lb) } } }
        function Get-AlertCollect { param($Rule) [pscustomobject]@{ monitor = [pscustomobject]@{ metricAlertRules = @($Rule) } } }
    }

    It 'keeps CASA at 31 rules, now 12 automated and 19 manual, and CASA-AV-04 manual' {
        $script:CasaSet.Rules.Count | Should -Be 31
        @($script:CasaSet.Rules | Where-Object { -not $_.manual }).Count | Should -Be 12
        @($script:CasaSet.Rules | Where-Object { $_.manual }).Count | Should -Be 19
        foreach ($id in 'CASA-AV-03', 'CASA-AV-05', 'CASA-PM-04', 'CASA-SS-01', 'CASA-IR-02') {
            @($script:CasaSet.Rules | Where-Object { $_.id -eq $id })[0].manual | Should -BeFalse -Because "$id reads collected data now"
        }
        @($script:CasaSet.Rules | Where-Object { $_.id -eq 'CASA-AV-04' })[0].manual | Should -BeTrue
    }

    It 'CASA-PM-04 is Not assessed with no secure score collected, and passes once one is' {
        $none = [pscustomobject]@{ security = [pscustomobject]@{ defenderSecureScores = @() } }
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-PM-04' -Collect $none).Status | Should -Be 'NotAssessed'
        $some = [pscustomobject]@{ security = [pscustomobject]@{ defenderSecureScores = @([pscustomobject]@{ Name = 'ascScore'; SubscriptionId = 's1' }) } }
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-PM-04' -Collect $some).Status | Should -Be 'Pass'
    }

    It 'CASA-SS-01 is Not assessed without scores, fails with scores but no assessments, and passes with both' {
        $none = [pscustomobject]@{ security = [pscustomobject]@{ defenderSecureScores = @(); defenderAssessments = @() } }
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-SS-01' -Collect $none).Status | Should -Be 'NotAssessed'
        $score = @([pscustomobject]@{ Name = 'ascScore' })
        $scoreOnly = [pscustomobject]@{ security = [pscustomobject]@{ defenderSecureScores = $score; defenderAssessments = @() } }
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-SS-01' -Collect $scoreOnly).Status | Should -Be 'Fail'
        $both = [pscustomobject]@{ security = [pscustomobject]@{ defenderSecureScores = $score; defenderAssessments = @([pscustomobject]@{ Name = 'a1' }) } }
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-SS-01' -Collect $both).Status | Should -Be 'Pass'
    }

    It 'CASA-IR-02 fails with no Sentinel onboarding and passes with one' {
        $none = [pscustomobject]@{ domains = [pscustomobject]@{ security = [pscustomobject]@{ sentinelWorkspaces = @() } } }
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-IR-02' -Collect $none).Status | Should -Be 'Fail'
        $some = [pscustomobject]@{ domains = [pscustomobject]@{ security = [pscustomobject]@{ sentinelWorkspaces = @([pscustomobject]@{ name = 'law1'; provisioningState = 'Succeeded' }) } } }
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-IR-02' -Collect $some).Status | Should -Be 'Pass'
    }

    It 'CASA-AV-03 needs a scale set to assess, ignores AKS node scale sets, and wants an ENABLED autoscale setting' {
        $vmss = [pscustomobject]@{ name = 'vmss1'; resourceGroup = 'rg-app' }
        $aksVmss = [pscustomobject]@{ name = 'aks-nodepool1'; resourceGroup = 'MC_rg_aks_eastus' }
        $enabled = [pscustomobject]@{ name = 'as1'; enabled = $true }
        $disabled = [pscustomobject]@{ name = 'as1'; enabled = $false }

        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-03' -Collect (Get-ScaleCollect -Scale @() -Auto @())).Status | Should -Be 'NotAssessed'
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-03' -Collect (Get-ScaleCollect -Scale $aksVmss -Auto @())).Status | Should -Be 'NotAssessed'
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-03' -Collect (Get-ScaleCollect -Scale $vmss -Auto @())).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-03' -Collect (Get-ScaleCollect -Scale $vmss -Auto $disabled)).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-03' -Collect (Get-ScaleCollect -Scale $vmss -Auto $enabled)).Status | Should -Be 'Pass'
    }

    It 'CASA-AV-04 stays Manual however many chaos experiments exist, and attaches them as evidence' {
        $none = [pscustomobject]@{ devops = [pscustomobject]@{ chaosExperiments = @() } }
        $some = [pscustomobject]@{ devops = [pscustomobject]@{ chaosExperiments = @([pscustomobject]@{ name = 'exp1' }, [pscustomobject]@{ name = 'exp2' }) } }
        $withNone = Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-04' -Collect $none
        $withSome = Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-04' -Collect $some
        $withNone.Status | Should -Be 'Manual'
        $withSome.Status | Should -Be 'Manual'
        $withSome.EvidenceCount | Should -Be 2
    }

    It 'CASA-AV-05 lists load balancers with no health probe and is Not assessed with none' {
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-05' -Collect (Get-LbCollect -Lb @())).Status | Should -Be 'NotAssessed'
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-05' -Collect (Get-LbCollect -Lb ([pscustomobject]@{ name = 'lb1'; probeCount = 0 }))).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-05' -Collect (Get-LbCollect -Lb ([pscustomobject]@{ name = 'lb1'; probeCount = $null }))).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:CasaSet -Id 'CASA-AV-05' -Collect (Get-LbCollect -Lb ([pscustomobject]@{ name = 'lb1'; probeCount = 2 }))).Status | Should -Be 'Pass'
    }

    It 'WAF-OE-06 wants an enabled metric alert rule that has an action group' {
        @($script:OpsSet.Rules | Where-Object { $_.id -eq 'WAF-OE-06' })[0].manual | Should -BeFalse
        (Invoke-OneRule -Set $script:OpsSet -Id 'WAF-OE-06' -Collect (Get-AlertCollect -Rule @())).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:OpsSet -Id 'WAF-OE-06' -Collect (Get-AlertCollect -Rule ([pscustomobject]@{ enabled = $true; actionGroupCount = 0 }))).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:OpsSet -Id 'WAF-OE-06' -Collect (Get-AlertCollect -Rule ([pscustomobject]@{ enabled = $false; actionGroupCount = 1 }))).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:OpsSet -Id 'WAF-OE-06' -Collect (Get-AlertCollect -Rule ([pscustomobject]@{ enabled = $true; actionGroupCount = $null }))).Status | Should -Be 'Fail'
        (Invoke-OneRule -Set $script:OpsSet -Id 'WAF-OE-06' -Collect (Get-AlertCollect -Rule ([pscustomobject]@{ enabled = $true; actionGroupCount = 1 }))).Status | Should -Be 'Pass'
    }
}

Describe 'Service-guide items converted with the phase 4 batch 2 per-resource ARM reads' {
    It 'scores <Id> as Fail with <Count> offending rows on the bad estate and Pass on the good one' -ForEach @(
        @{ Id = 'WAF-SVC-APP-13'; Count = 1 }   # app1 only: the function app is left out of the web-app join
        @{ Id = 'WAF-SVC-APP-14'; Count = 4 }   # two basic-authentication rows and two configuration rows
        @{ Id = 'WAF-SVC-FILES-05'; Count = 1 }
        @{ Id = 'WAF-SVC-FILES-06'; Count = 1 }
    ) {
        $bad = $script:Bad | Where-Object Id -eq $Id
        $bad.Status | Should -Be 'Fail'
        $bad.EvidenceCount | Should -Be $Count
        $bad.Manual | Should -BeFalse
        ($script:Good | Where-Object Id -eq $Id).Status | Should -Be 'Pass'
    }

    It 'reports <Id> NotAssessed, not Pass, when <Flag> is false even though the rows exist' -ForEach @(
        @{ Id = 'WAF-SVC-APP-13'; Flag = 'webAppConfigMeasured'; Section = 'web' }
        @{ Id = 'WAF-SVC-APP-14'; Flag = 'webAppBasicAuthMeasured'; Section = 'web' }
        @{ Id = 'WAF-SVC-FILES-05'; Flag = 'fileServicePropertiesMeasured'; Section = 'storage' }
        @{ Id = 'WAF-SVC-FILES-06'; Flag = 'fileServicePropertiesMeasured'; Section = 'storage' }
    ) {
        $estate = New-ServiceGuideEstate -Good $false
        $estate.domains[$Section][$Flag] = $false
        $findings = Invoke-ServiceGuideAssessment -Estate $estate
        ($findings | Where-Object Id -eq $Id).Status | Should -Be 'NotAssessed'
        @($findings | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'scores <Id> as <Status> when <Name>' -ForEach @(
        @{ Name = 'only the health check path is missing'; Id = 'WAF-SVC-APP-13'; Status = 'Fail'; Mutate = { param($e) $e.domains.web.webAppConfig[0].healthCheckPathSet = $false } }
        @{ Name = 'only Always On is off'; Id = 'WAF-SVC-APP-13'; Status = 'Fail'; Mutate = { param($e) $e.domains.web.webAppConfig[0].alwaysOn = $false } }
        @{ Name = 'the only site with Always On off is a function app'; Id = 'WAF-SVC-APP-13'; Status = 'Pass'; Mutate = { param($e) $e.domains.web.webAppConfig[1].alwaysOn = $false; $e.domains.web.webAppConfig[1].healthCheckPathSet = $false } }
        @{ Name = 'a site config row has no matching web app in the inventory'; Id = 'WAF-SVC-APP-13'; Status = 'Pass'; Mutate = { param($e) $e.domains.web.webAppConfig[0].webAppId = '/subscriptions/x/resourcegroups/y/providers/microsoft.web/sites/gone'; $e.domains.web.webAppConfig[0].alwaysOn = $false } }
        @{ Name = 'the web app id differs in casing from the configuration row'; Id = 'WAF-SVC-APP-13'; Status = 'Fail'; Mutate = { param($e) $e.domains.web.webApps[0].id = $e.domains.web.webApps[0].id.ToUpperInvariant(); $e.domains.web.webAppConfig[0].alwaysOn = $false } }
        @{ Name = 'FTP basic authentication is allowed'; Id = 'WAF-SVC-APP-14'; Status = 'Fail'; Mutate = { param($e) $e.domains.web.webAppBasicAuth[0].ftpBasicAuthAllowed = $true } }
        @{ Name = 'SCM basic authentication is allowed'; Id = 'WAF-SVC-APP-14'; Status = 'Fail'; Mutate = { param($e) $e.domains.web.webAppBasicAuth[0].scmBasicAuthAllowed = $true } }
        @{ Name = 'a basic-authentication policy was not returned (null)'; Id = 'WAF-SVC-APP-14'; Status = 'Pass'; Mutate = { param($e) $e.domains.web.webAppBasicAuth[0].ftpBasicAuthAllowed = $null; $e.domains.web.webAppBasicAuth[0].scmBasicAuthAllowed = $null } }
        @{ Name = 'FTP accepts plain FTP'; Id = 'WAF-SVC-APP-14'; Status = 'Fail'; Mutate = { param($e) $e.domains.web.webAppConfig[0].ftpsState = 'AllAllowed' } }
        @{ Name = 'FTP is disabled'; Id = 'WAF-SVC-APP-14'; Status = 'Pass'; Mutate = { param($e) $e.domains.web.webAppConfig[0].ftpsState = 'Disabled' } }
        @{ Name = 'the FTPS state was not returned (null)'; Id = 'WAF-SVC-APP-14'; Status = 'Pass'; Mutate = { param($e) $e.domains.web.webAppConfig[0].ftpsState = $null } }
        @{ Name = 'remote debugging is on'; Id = 'WAF-SVC-APP-14'; Status = 'Fail'; Mutate = { param($e) $e.domains.web.webAppConfig[1].remoteDebuggingEnabled = $true } }
        @{ Name = 'share soft delete is off on one account'; Id = 'WAF-SVC-FILES-05'; Status = 'Fail'; Mutate = { param($e) $e.domains.storage.fileServiceProperties[0].shareDeleteRetentionEnabled = $false } }
        @{ Name = 'SMB allows version 3.0 as well as 3.1.1'; Id = 'WAF-SVC-FILES-06'; Status = 'Fail'; Mutate = { param($e) $e.domains.storage.fileServiceProperties[0].smbVersions = 'SMB3.0;SMB3.1.1' } }
        @{ Name = 'SMB channel encryption allows AES-128-GCM too'; Id = 'WAF-SVC-FILES-06'; Status = 'Fail'; Mutate = { param($e) $e.domains.storage.fileServiceProperties[0].smbChannelEncryption = 'AES-128-GCM;AES-256-GCM' } }
        @{ Name = 'SMB versions were never restricted (null allows every version)'; Id = 'WAF-SVC-FILES-06'; Status = 'Fail'; Mutate = { param($e) $e.domains.storage.fileServiceProperties[0].smbVersions = $null } }
        @{ Name = 'SMB is restricted to 3.1.1 and AES-256-GCM'; Id = 'WAF-SVC-FILES-06'; Status = 'Pass'; Mutate = { param($e) $e.domains.storage.fileServiceProperties[0].smbVersions = 'SMB3.1.1'; $e.domains.storage.fileServiceProperties[0].smbChannelEncryption = 'AES-256-GCM' } }
    ) {
        $estate = New-ServiceGuideEstate -Good $true
        & $Mutate $estate
        $finding = Invoke-ServiceGuideAssessment -Estate $estate | Where-Object Id -eq $Id
        $finding.Status | Should -Be $Status
    }

    It 'names the offending site, not just a count, in the web-app join evidence' {
        $apps = @(($script:Bad | Where-Object Id -eq 'WAF-SVC-APP-13').Evidence)
        $apps.Count | Should -Be 1
        $apps[0].Left.name | Should -Be 'app1'
        $apps[0].Right.name | Should -Be 'app1'
    }
}
