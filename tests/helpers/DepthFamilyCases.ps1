# Fixtures for the depth child-resource tests (AB#9300, 3.18.20): one "family" per service. Dot-source tests/helpers/
# DepthChildHarness.ps1 first (New-DepthParent, ConvertTo-DepthBody). Every property the allow-list excludes carries a
# SENTINEL value; none may reach a row, an operation, a shaped dataset or a discovery twin.
Set-StrictMode -Version Latest

function Get-DepthFamilyCase {
    $body = { param($Items) ConvertTo-DepthBody @{ value = @($Items) } }
    $storage = New-DepthParent -Type 'microsoft.storage/storageaccounts' -Path 'Microsoft.Storage/storageAccounts/st1'

    # ---- Front Door Standard / Premium ------------------------------------------------------------------------------
    $afd = New-DepthParent -Type 'microsoft.cdn/profiles' -Path 'Microsoft.Cdn/profiles/afd1' -Sku 'Premium_AzureFrontDoor'
    $classicCdn = New-DepthParent -Type 'microsoft.cdn/profiles' -Path 'Microsoft.Cdn/profiles/cdn1' -Sku 'Standard_Microsoft'
    $b = $afd.id
    $afdRoutes = [ordered]@{}
    $afdRoutes["$b/originGroups"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$b/originGroups/og1"; name = 'og1'; properties = @{ healthProbeSettings = @{ probePath = '/SENTINEL-PROBEPATH'; probeRequestType = 'HEAD'; probeProtocol = 'Https'; probeIntervalInSeconds = 30 }
                        loadBalancingSettings = @{ sampleSize = 4; successfulSamplesRequired = 3; additionalLatencyInMilliseconds = 50 }; sessionAffinityState = 'Disabled'; provisioningState = 'Succeeded' } }
                @{ id = "$b/originGroups/og2"; name = 'og2'; properties = @{ loadBalancingSettings = @{ sampleSize = 4; successfulSamplesRequired = 3 }; sessionAffinityState = 'Enabled'; provisioningState = 'Succeeded' } })) }
    $afdRoutes["$b/originGroups/og1/origins"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$b/originGroups/og1/origins/o1"; name = 'o1'; properties = @{ hostName = 'SENTINEL-HOST-1.example.test'; originHostHeader = 'SENTINEL-HOSTHEADER'; enabledState = 'Enabled'; priority = 1; weight = 500; enforceCertificateNameCheck = $true } }
                @{ id = "$b/originGroups/og1/origins/o2"; name = 'o2'; properties = @{ hostName = 'SENTINEL-HOST-2.example.test'; enabledState = 'Enabled'; priority = 1; weight = 500
                        sharedPrivateLinkResource = @{ privateLink = @{ id = '/x/SENTINEL-PRIVATELINK' }; requestMessage = 'SENTINEL-PLMESSAGE'; groupId = 'sites' } } })) }
    $afdRoutes["$b/originGroups/og2/origins"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$b/originGroups/og2/origins/o3"; name = 'o3'; properties = @{ hostName = 'SENTINEL-HOST-3.example.test'; enabledState = 'Enabled'; priority = 1; weight = 1000 } })) }
    $afdRoutes["$b/afdEndpoints"] = @{ Status = 200; Body = (& $body @(@{ id = "$b/afdEndpoints/ep1"; name = 'ep1'; properties = @{ hostName = 'SENTINEL-ENDPOINT.z01.azurefd.net'; enabledState = 'Enabled'; provisioningState = 'Succeeded' } })) }
    $afdRoutes["$b/afdEndpoints/ep1/routes"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$b/afdEndpoints/ep1/routes/r1"; name = 'r1'; properties = @{ enabledState = 'Enabled'; httpsRedirect = 'Enabled'; forwardingProtocol = 'HttpsOnly'; linkToDefaultDomain = 'Enabled'
                        supportedProtocols = @('Http', 'Https'); patternsToMatch = @('/SENTINEL-PATTERN/*'); originPath = '/SENTINEL-ORIGINPATH'; originGroup = @{ id = "$b/originGroups/og1" }
                        cacheConfiguration = @{ queryStringCachingBehavior = 'IgnoreQueryString'; compressionSettings = @{ isCompressionEnabled = $true } } } }
                @{ id = "$b/afdEndpoints/ep1/routes/r2"; name = 'r2'; properties = @{ enabledState = 'Enabled'; httpsRedirect = 'Disabled'; forwardingProtocol = 'HttpOnly'; supportedProtocols = @('Http', 'Https'); patternsToMatch = @('/*') } })) }
    $afdRoutes["$b/customDomains"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$b/customDomains/cd1"; name = 'cd1'; properties = @{ hostName = 'SENTINEL-DOMAIN.contoso.test'; domainValidationState = 'Approved'; validationProperties = @{ validationToken = 'SENTINEL-VALIDATIONTOKEN' }
                        tlsSettings = @{ certificateType = 'ManagedCertificate'; minimumTlsVersion = 'TLS12' } } }
                @{ id = "$b/customDomains/cd2"; name = 'cd2'; properties = @{ hostName = 'SENTINEL-DOMAIN2.contoso.test'; azureDnsZone = @{ id = '/x/SENTINEL-DNSZONE' }
                        tlsSettings = @{ certificateType = 'CustomerCertificate'; minimumTlsVersion = 'TLS10'; secret = @{ id = '/x/SENTINEL-SECRETREF' } } } })) }
    $afdRoutes["$b/securityPolicies"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$b/securityPolicies/sp1"; name = 'sp1'; properties = @{ parameters = @{ type = 'WebApplicationFirewall'; wafPolicy = @{ id = '/x/SENTINEL-WAFPOLICY' }
                            associations = @(@{ domains = @(@{ id = '/x/SENTINEL-ASSOC1' }, @{ id = '/x/SENTINEL-ASSOC2' }); patternsToMatch = @('/*') }) } } })) }
    $afdFamily = @{
        Name = 'Afd'; ApiVersion = '2025-04-15'; PositiveControl = 'og1'
        Datasets = @('AfdOriginGroups', 'AfdOrigins', 'AfdEndpoints', 'AfdRoutes', 'AfdCustomDomains', 'AfdSecurityPolicies')
        Keys = @('afdOriginGroups', 'afdOrigins', 'afdEndpoints', 'afdRoutes', 'afdCustomDomains', 'afdSecurityPolicies')
        FirstLevelKeys = @('afdOriginGroups', 'afdEndpoints', 'afdCustomDomains', 'afdSecurityPolicies')
        Parents = @($afd, $classicCdn); Unrelated = $storage; NotAsked = $classicCdn
        Routes = $afdRoutes
        ExpectedPaths = @('originGroups', 'originGroups/og1/origins', 'originGroups/og2/origins', 'afdEndpoints', 'afdEndpoints/ep1/routes', 'customDomains', 'securityPolicies') |
            ForEach-Object { "Microsoft.Cdn/profiles/afd1/$_" }
        Sentinels = @('SENTINEL-PROBEPATH', 'SENTINEL-HOST-1', 'SENTINEL-HOST-2', 'SENTINEL-HOST-3', 'SENTINEL-HOSTHEADER', 'SENTINEL-PRIVATELINK', 'SENTINEL-PLMESSAGE', 'SENTINEL-ENDPOINT',
            'SENTINEL-PATTERN', 'SENTINEL-ORIGINPATH', 'SENTINEL-DOMAIN', 'SENTINEL-VALIDATIONTOKEN', 'SENTINEL-DNSZONE', 'SENTINEL-SECRETREF', 'SENTINEL-WAFPOLICY', 'SENTINEL-ASSOC')
    }

    # ---- Azure SQL ----------------------------------------------------------------------------------------------------------
    $server = New-DepthParent -Type 'microsoft.sql/servers' -Path 'Microsoft.Sql/servers/sql1'
    $db = New-DepthParent -Type 'microsoft.sql/servers/databases' -Path 'Microsoft.Sql/servers/sql1/databases/db1' -Sku 'Standard' -Tier 'Standard'
    $master = New-DepthParent -Type 'microsoft.sql/servers/databases' -Path 'Microsoft.Sql/servers/sql1/databases/master' -Sku 'System' -Tier 'System'
    $pool = New-DepthParent -Type 'microsoft.sql/servers/databases' -Path 'Microsoft.Sql/servers/sql1/databases/dw1' -Sku 'DW100c' -Tier 'DataWarehouse'
    $sqlRoutes = [ordered]@{}
    $sqlRoutes["$($db.id)/backupShortTermRetentionPolicies"] = @{ Status = 200; Body = (& $body @(@{ id = "$($db.id)/backupShortTermRetentionPolicies/default"; name = 'default'; properties = @{ retentionDays = 3; diffBackupIntervalInHours = 12 } })) }
    $sqlRoutes["$($db.id)/backupLongTermRetentionPolicies"] = @{ Status = 200; Body = (& $body @(@{ id = "$($db.id)/backupLongTermRetentionPolicies/default"; name = 'default'; properties = @{ weeklyRetention = 'P4W'; monthlyRetention = 'PT0S'; yearlyRetention = 'PT0S'; weekOfYear = 1; timeBasedImmutability = 'Disabled' } })) }
    $sqlRoutes["$($db.id)/transparentDataEncryption"] = @{ Status = 200; Body = (& $body @(@{ id = "$($db.id)/transparentDataEncryption/current"; name = 'current'; properties = @{ state = 'Enabled'; scanState = 'None' } })) }
    $sqlRoutes["$($pool.id)/transparentDataEncryption"] = @{ Status = 200; Body = (& $body @(@{ id = "$($pool.id)/transparentDataEncryption/current"; name = 'current'; properties = @{ state = 'Disabled' } })) }
    $sqlRoutes["$($server.id)/firewallRules"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$($server.id)/firewallRules/AllowAll"; name = 'AllowAll'; properties = @{ startIpAddress = '0.0.0.0'; endIpAddress = '255.255.255.255' } }
                @{ id = "$($server.id)/firewallRules/AllowAllWindowsAzureIps"; name = 'AllowAllWindowsAzureIps'; properties = @{ startIpAddress = '0.0.0.0'; endIpAddress = '0.0.0.0' } }
                @{ id = "$($server.id)/firewallRules/office"; name = 'office'; properties = @{ startIpAddress = '203.0.113.77'; endIpAddress = '203.0.113.80' } }
                @{ id = "$($server.id)/firewallRules/wide"; name = 'wide'; properties = @{ startIpAddress = '10.0.0.0'; endIpAddress = '10.255.255.255' } })) }
    $sqlRoutes["$($server.id)/encryptionProtector"] = @{ Status = 200; Body = (& $body @(@{ id = "$($server.id)/encryptionProtector/current"; name = 'current'; kind = 'azurekeyvault'
                    properties = @{ serverKeyType = 'AzureKeyVault'; serverKeyName = 'SENTINEL-KEYNAME'; uri = 'https://SENTINEL-VAULT.vault.azure.net/keys/k/v'; thumbprint = 'SENTINEL-THUMBPRINT'; autoRotationEnabled = $true } })) }
    $sqlRoutes["$($server.id)/securityAlertPolicies"] = @{ Status = 200; Body = (& $body @(@{ id = "$($server.id)/securityAlertPolicies/Default"; name = 'Default'
                    properties = @{ state = 'Enabled'; emailAddresses = @('SENTINEL-EMAIL@example.test'); emailAccountAdmins = $true; disabledAlerts = @('Sql_Injection'); retentionDays = 30
                        storageEndpoint = 'https://SENTINEL-STORE.blob.core.windows.net'; storageAccountAccessKey = 'SENTINEL-STORAGEKEY' } })) }
    $sqlFamily = @{
        Name = 'Sql'; ApiVersion = '2025-01-01'; PositiveControl = 'db1'
        Datasets = @('SqlDatabaseBackupShortTerm', 'SqlDatabaseBackupLongTerm', 'SqlDatabaseTde', 'SqlServerFirewallRules', 'SqlServerEncryptionProtector', 'SqlServerSecurityAlertPolicies')
        Keys = @('sqlBackupShortTerm', 'sqlBackupLongTerm', 'sqlTde', 'sqlFirewallRules', 'sqlEncryptionProtector', 'sqlSecurityAlertPolicies')
        FirstLevelKeys = @('sqlBackupShortTerm', 'sqlBackupLongTerm', 'sqlTde', 'sqlFirewallRules', 'sqlEncryptionProtector', 'sqlSecurityAlertPolicies')
        Parents = @($server, $db, $master, $pool); Unrelated = $storage; NotAsked = $master
        Routes = $sqlRoutes
        ExpectedPaths = @(
            'Microsoft.Sql/servers/sql1/databases/db1/backupShortTermRetentionPolicies', 'Microsoft.Sql/servers/sql1/databases/db1/backupLongTermRetentionPolicies',
            'Microsoft.Sql/servers/sql1/databases/db1/transparentDataEncryption', 'Microsoft.Sql/servers/sql1/databases/dw1/transparentDataEncryption',
            'Microsoft.Sql/servers/sql1/firewallRules', 'Microsoft.Sql/servers/sql1/encryptionProtector', 'Microsoft.Sql/servers/sql1/securityAlertPolicies')
        Sentinels = @('203.0.113.77', '203.0.113.80', 'SENTINEL-KEYNAME', 'SENTINEL-VAULT', 'SENTINEL-THUMBPRINT', 'SENTINEL-EMAIL', 'SENTINEL-STORE', 'SENTINEL-STORAGEKEY', '10.255.255.255')
    }

    # ---- Azure Local clusters -----------------------------------------------------------------------------------------------------
    $cluster = New-DepthParent -Type 'microsoft.azurestackhci/clusters' -Path 'Microsoft.AzureStackHCI/clusters/hci1'
    $hciRoutes = [ordered]@{}
    $hciRoutes["$($cluster.id)/updateSummaries"] = @{ Status = 200; Body = (& $body @(@{ id = "$($cluster.id)/updateSummaries/default"; name = 'default'
                    properties = @{ state = 'UpdateAvailable'; healthState = 'Success'; currentVersion = '10.2411.0.24'; currentSbeVersion = '4.1.2'; lastUpdated = '2026-11-01T10:00:00Z'; lastChecked = '2026-11-25T10:00:00Z'
                        oemFamily = 'SENTINEL-OEM'; hardwareModel = 'SENTINEL-HARDWARE'; packageVersions = @(@{ packageType = 'Solution'; version = '10.2411' }, @{ packageType = 'Services'; version = '1.0' }) } })) }
    $hciRoutes["$($cluster.id)/securitySettings"] = @{ Status = 200; Body = (& $body @(@{ id = "$($cluster.id)/securitySettings/default"; name = 'default'
                    properties = @{ provisioningState = 'Succeeded'; securedCoreComplianceAssignment = 'ApplyAndAutoCorrect'; wdacComplianceAssignment = 'Audit'; smbEncryptionForIntraClusterTrafficComplianceAssignment = 'ApplyAndAutoCorrect'
                        securityComplianceStatus = @{ securedCoreCompliance = 'Compliant'; wdacCompliance = 'NonCompliant'; dataAtRestEncrypted = 'Compliant'; dataInTransitProtected = 'Compliant'; lastUpdated = '2026-11-25T09:00:00Z' } } })) }
    $hciRoutes["$($cluster.id)/arcSettings"] = @{ Status = 200; Body = (& $body @(@{ id = "$($cluster.id)/arcSettings/default"; name = 'default'
                    properties = @{ aggregateState = 'PartiallyConnected'; provisioningState = 'Succeeded'; arcInstanceResourceGroup = 'SENTINEL-ARCRG'; arcApplicationClientId = 'SENTINEL-APPID'
                        arcApplicationObjectId = 'SENTINEL-OBJID'; arcApplicationTenantId = 'SENTINEL-TENANT'; connectivityProperties = @{ enabled = $true; serviceConfigurations = @(@{ serviceName = 'WAC'; port = 6516 }) }
                        perNodeDetails = @(@{ name = 'SENTINEL-NODE1'; arcInstance = '/x/SENTINEL-ARCINSTANCE'; state = 'Succeeded' }, @{ name = 'SENTINEL-NODE2'; state = 'Disconnected' })
                        defaultExtensions = @(@{ category = 'ProductQualityAndSupport'; consentTime = '2026-01-01T00:00:00Z' }) } })) }
    $hciFamily = @{
        Name = 'AzureLocal'; ApiVersion = '2024-04-01'; PositiveControl = 'hci1'
        Datasets = @('AzureLocalUpdateSummaries', 'AzureLocalSecuritySettings', 'AzureLocalArcSettings')
        Keys = @('azureLocalUpdateSummaries', 'azureLocalSecuritySettings', 'azureLocalArcSettings')
        FirstLevelKeys = @('azureLocalUpdateSummaries', 'azureLocalSecuritySettings', 'azureLocalArcSettings')
        Parents = @($cluster); Unrelated = $storage; NotAsked = $null
        Routes = $hciRoutes
        ExpectedPaths = @('updateSummaries', 'securitySettings', 'arcSettings') | ForEach-Object { "Microsoft.AzureStackHCI/clusters/hci1/$_" }
        Sentinels = @('SENTINEL-OEM', 'SENTINEL-HARDWARE', 'SENTINEL-ARCRG', 'SENTINEL-APPID', 'SENTINEL-OBJID', 'SENTINEL-TENANT', 'SENTINEL-NODE1', 'SENTINEL-NODE2', 'SENTINEL-ARCINSTANCE')
    }

    # ---- Event Hubs and Service Bus -----------------------------------------------------------------------------------------------------
    $ehStd = New-DepthParent -Type 'microsoft.eventhub/namespaces' -Path 'Microsoft.EventHub/namespaces/ehstd' -Sku 'Standard'
    $ehBasic = New-DepthParent -Type 'microsoft.eventhub/namespaces' -Path 'Microsoft.EventHub/namespaces/ehbasic' -Sku 'Basic'
    $sbPrem = New-DepthParent -Type 'microsoft.servicebus/namespaces' -Path 'Microsoft.ServiceBus/namespaces/sbprem' -Sku 'Premium'
    $sbStd = New-DepthParent -Type 'microsoft.servicebus/namespaces' -Path 'Microsoft.ServiceBus/namespaces/sbstd' -Sku 'Standard'
    $msgRoutes = [ordered]@{}
    $msgRoutes["$($ehStd.id)/networkRuleSets"] = @{ Status = 200; Body = (& $body @(@{ id = "$($ehStd.id)/networkRuleSets/default"; name = 'default'
                    properties = @{ defaultAction = 'Deny'; publicNetworkAccess = 'Enabled'; trustedServiceAccessEnabled = $true; ipRules = @(@{ ipMask = '203.0.113.9'; action = 'Allow' }); virtualNetworkRules = @(@{ subnet = @{ id = '/x/SENTINEL-SUBNET' } }) } })) }
    foreach ($namespace in $ehStd, $ehBasic, $sbPrem, $sbStd) {
        $msgRoutes["$($namespace.id)/authorizationRules"] = @{ Status = 200; Body = (& $body @(
                    @{ id = "$($namespace.id)/authorizationRules/RootManageSharedAccessKey"; name = 'RootManageSharedAccessKey'; properties = @{ rights = @('Listen', 'Send', 'Manage') } }
                    @{ id = "$($namespace.id)/authorizationRules/sender"; name = 'sender'; properties = @{ rights = @('Send') } }
                    @{ id = "$($namespace.id)/authorizationRules/ops-admin"; name = 'ops-admin'; properties = @{ rights = @('Manage', 'Send', 'Listen') } })) }
    }
    foreach ($namespace in $ehStd, $ehBasic) {
        $msgRoutes["$($namespace.id)/eventhubs"] = @{ Status = 200; Body = (& $body @(@{ id = "$($namespace.id)/eventhubs/hub1"; name = 'hub1'
                        properties = @{ partitionCount = 4; messageRetentionInDays = 7; status = 'Active'; partitionIds = @('0', '1', '2', '3'); retentionDescription = @{ cleanupPolicy = 'Delete'; retentionTimeInHours = 168 }
                            captureDescription = @{ enabled = $true; intervalInSeconds = 300; sizeLimitInBytes = 314572800; destination = @{ name = 'EventHubArchive.AzureBlockBlob'; properties = @{ storageAccountResourceId = '/x/SENTINEL-CAPSTORE'; blobContainer = 'SENTINEL-CAPCONTAINER' } } } } })) }
    }
    $msgRoutes["$($sbPrem.id)/networkRuleSets"] = @{ Status = 200; Body = (& $body @(@{ id = "$($sbPrem.id)/networkRuleSets/default"; name = 'default'; properties = @{ defaultAction = 'Allow'; publicNetworkAccess = 'Enabled'; ipRules = @(); virtualNetworkRules = @() } })) }
    foreach ($namespace in $sbPrem, $sbStd) {
        $msgRoutes["$($namespace.id)/queues"] = @{ Status = 200; Body = (& $body @(@{ id = "$($namespace.id)/queues/q1"; name = 'q1'
                        properties = @{ maxDeliveryCount = 10; deadLetteringOnMessageExpiration = $true; requiresDuplicateDetection = $false; requiresSession = $false; enablePartitioning = $false; lockDuration = 'PT1M'
                            defaultMessageTimeToLive = 'P14D'; maxSizeInMegabytes = 1024; status = 'Active'; forwardTo = 'SENTINEL-FWD'; forwardDeadLetteredMessagesTo = 'SENTINEL-FWDDLQ' } })) }
        $msgRoutes["$($namespace.id)/topics"] = @{ Status = 200; Body = (& $body @(@{ id = "$($namespace.id)/topics/t1"; name = 't1'; properties = @{ requiresDuplicateDetection = $true; enablePartitioning = $true; subscriptionCount = 2; maxSizeInMegabytes = 1024; status = 'Active' } })) }
    }
    $msgPaths = @(
        'Microsoft.EventHub/namespaces/ehstd/networkRuleSets', 'Microsoft.EventHub/namespaces/ehstd/authorizationRules', 'Microsoft.EventHub/namespaces/ehstd/eventhubs',
        'Microsoft.EventHub/namespaces/ehbasic/authorizationRules', 'Microsoft.EventHub/namespaces/ehbasic/eventhubs',
        'Microsoft.ServiceBus/namespaces/sbprem/networkRuleSets', 'Microsoft.ServiceBus/namespaces/sbprem/authorizationRules', 'Microsoft.ServiceBus/namespaces/sbprem/queues', 'Microsoft.ServiceBus/namespaces/sbprem/topics',
        'Microsoft.ServiceBus/namespaces/sbstd/authorizationRules', 'Microsoft.ServiceBus/namespaces/sbstd/queues', 'Microsoft.ServiceBus/namespaces/sbstd/topics')
    $msgFamily = @{
        Name = 'Messaging'; ApiVersion = '2024-01-01'; PositiveControl = 'ehstd'
        Datasets = @('EventHubNetworkRuleSets', 'EventHubAuthorizationRules', 'EventHubEntities', 'ServiceBusNetworkRuleSets', 'ServiceBusAuthorizationRules', 'ServiceBusQueues', 'ServiceBusTopics')
        Keys = @('eventHubNetworkRuleSets', 'eventHubAuthorization', 'eventHubEntities', 'serviceBusNetworkRuleSets', 'serviceBusAuthorization', 'serviceBusQueues', 'serviceBusTopics')
        FirstLevelKeys = @('eventHubNetworkRuleSets', 'eventHubAuthorization', 'eventHubEntities', 'serviceBusNetworkRuleSets', 'serviceBusAuthorization', 'serviceBusQueues', 'serviceBusTopics')
        Parents = @($ehStd, $ehBasic, $sbPrem, $sbStd); Unrelated = $storage; NotAsked = $null
        Routes = $msgRoutes; ExpectedPaths = $msgPaths
        Sentinels = @('203.0.113.9', 'SENTINEL-SUBNET', 'SENTINEL-CAPSTORE', 'SENTINEL-CAPCONTAINER', 'SENTINEL-FWD')
    }

    # ---- App Service authentication ----------------------------------------------------------------------------------------------------
    $site = New-DepthParent -Type 'microsoft.web/sites' -Path 'Microsoft.Web/sites/web1'
    $webRoutes = [ordered]@{}
    $webRoutes["$($site.id)/config/authsettingsV2"] = @{ Status = 200; Body = (ConvertTo-DepthBody @{ id = "$($site.id)/config/authsettingsV2"; name = 'authsettingsV2'; type = 'Microsoft.Web/sites/config'
                properties = @{ platform = @{ enabled = $true; runtimeVersion = '~1' }
                    globalValidation = @{ requireAuthentication = $true; unauthenticatedClientAction = 'Return401'; excludedPaths = @('/SENTINEL-EXCLUDED', '/health'); redirectToProvider = 'azureactivedirectory' }
                    identityProviders = @{ azureActiveDirectory = @{ enabled = $true; registration = @{ clientId = 'SENTINEL-CLIENTID'; clientSecretSettingName = 'SENTINEL-SECRETSETTING'; openIdIssuer = 'https://SENTINEL-ISSUER.example.test/v2.0' } }
                        github = @{ enabled = $false; registration = @{ clientId = 'SENTINEL-GITHUBID'; clientSecretSettingName = 'SENTINEL-GHSECRET' } }
                        customOpenIdConnectProviders = @{ corp = @{ enabled = $true; registration = @{ clientId = 'SENTINEL-CUSTOMID' } } } }
                    httpSettings = @{ requireHttps = $true } } }) }
    $webFamily = @{
        Name = 'WebAuth'; ApiVersion = '2025-05-01'; PositiveControl = 'web1'
        Datasets = @('WebAppAuth'); Keys = @('webAppAuth'); FirstLevelKeys = @('webAppAuth')
        Parents = @($site); Unrelated = $storage; NotAsked = $null
        Routes = $webRoutes; ExpectedPaths = @('Microsoft.Web/sites/web1/config/authsettingsV2')
        Sentinels = @('SENTINEL-EXCLUDED', 'SENTINEL-CLIENTID', 'SENTINEL-SECRETSETTING', 'SENTINEL-ISSUER', 'SENTINEL-GITHUBID', 'SENTINEL-GHSECRET', 'SENTINEL-CUSTOMID')
    }

    # ---- API Management ----------------------------------------------------------------------------------------------------------------
    $apim = New-DepthParent -Type 'microsoft.apimanagement/service' -Path 'Microsoft.ApiManagement/service/apim1'
    $apimRoutes = [ordered]@{}
    $apimRoutes["$($apim.id)/policies"] = @{ Status = 200; Body = (& $body @(@{ id = "$($apim.id)/policies/policy"; name = 'policy'
                    properties = @{ format = 'xml'; value = '<policies><inbound><validate-jwt header-name="Authorization"><openid-config url="https://SENTINEL-XMLURL.example.test/.well-known"/></validate-jwt><rate-limit calls="5" renewal-period="60"/><set-header name="x-key"><value>SENTINEL-POLICYKEY</value></set-header></inbound></policies>' } })) }
    $apimRoutes["$($apim.id)/apis"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$($apim.id)/apis/a1"; name = 'a1'; properties = @{ displayName = 'SENTINEL-APINAME'; path = 'SENTINEL-APIPATH'; serviceUrl = 'https://SENTINEL-BACKEND.example.test'; protocols = @('https'); subscriptionRequired = $true
                        authenticationSettings = @{ oAuth2AuthenticationSettings = @(@{ authorizationServerId = 'SENTINEL-AUTHSERVER' }) } } }
                @{ id = "$($apim.id)/apis/a2"; name = 'a2'; properties = @{ displayName = 'two'; path = 'two'; protocols = @('http', 'https'); subscriptionRequired = $false } })) }
    $apimRoutes["$($apim.id)/namedValues"] = @{ Status = 200; Body = (& $body @(
                @{ id = "$($apim.id)/namedValues/nv1"; name = 'nv1'; properties = @{ displayName = 'SENTINEL-NVNAME1'; secret = $true; keyVault = @{ secretIdentifier = 'https://SENTINEL-KVSECRET.vault.azure.net/secrets/s' } } }
                @{ id = "$($apim.id)/namedValues/nv2"; name = 'nv2'; properties = @{ displayName = 'SENTINEL-NVNAME2'; secret = $true } }
                @{ id = "$($apim.id)/namedValues/nv3"; name = 'nv3'; properties = @{ displayName = 'SENTINEL-NVNAME3'; secret = $false; value = 'SENTINEL-NVVALUE' } })) }
    $apimFamily = @{
        Name = 'Apim'; ApiVersion = '2024-05-01'; PositiveControl = 'apim1'
        Datasets = @('ApimGlobalPolicy', 'ApimApis', 'ApimNamedValues'); Keys = @('apimGlobalPolicy', 'apimApis', 'apimNamedValues'); FirstLevelKeys = @('apimGlobalPolicy', 'apimApis', 'apimNamedValues')
        Parents = @($apim); Unrelated = $storage; NotAsked = $null
        Routes = $apimRoutes; ExpectedPaths = @('policies', 'apis', 'namedValues') | ForEach-Object { "Microsoft.ApiManagement/service/apim1/$_" }
        Sentinels = @('SENTINEL-XMLURL', 'SENTINEL-POLICYKEY', 'SENTINEL-APINAME', 'SENTINEL-APIPATH', 'SENTINEL-BACKEND', 'SENTINEL-AUTHSERVER', 'SENTINEL-NVNAME', 'SENTINEL-KVSECRET', 'SENTINEL-NVVALUE')
    }

    @($afdFamily, $sqlFamily, $hciFamily, $msgFamily, $webFamily, $apimFamily)
}
