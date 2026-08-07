#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Part 2 of the collector-payload
    wiring audit: Databases/DevOps/Identity/Management/Security/Storage/Web.

    Every manifest listed below is an ordinary, ARG-indexed `resources`-table row (confirmed
    against the Azure Resource Graph supported-tables-and-resource-types reference before being
    added, same standard as every other query in Invoke-Collect.ps1) that was collected but never
    reached the assessment payload, per docs/reference/collector-payload-coverage.md. This is the
    same class of defect AB#7061/7064/7065/7066 fixed -- pure plumbing, not new collection logic.

    Two collection paths must both reach every key:
      - Invoke-Collect -Source TypedQueries (the live KQL query pack)
      - Invoke-Collect -FromInventory / the default inverted path (ConvertFrom-ScoutInventory)

    Search-AzGraph is mocked throughout. No live Azure connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    # Key => [collect-payload path, ARM resource type used to build/match the fixture row]
    $script:PlumbingSpecs = [ordered]@{
        # Databases (domains.databases)
        cosmosDbAccounts           = @{ Path = 'domains.databases'; Type = 'microsoft.documentdb/databaseaccounts' }
        mariaDbServers             = @{ Path = 'domains.databases'; Type = 'microsoft.dbformariadb/servers' }
        mySqlServers               = @{ Path = 'domains.databases'; Type = 'microsoft.dbformysql/servers' }
        mySqlFlexibleServers       = @{ Path = 'domains.databases'; Type = 'microsoft.dbformysql/flexibleservers' }
        postgreSqlFlexibleServers  = @{ Path = 'domains.databases'; Type = 'microsoft.dbforpostgresql/flexibleservers' }
        redisCaches                = @{ Path = 'domains.databases'; Type = 'microsoft.cache/redis' }
        sqlManagedInstances        = @{ Path = 'domains.databases'; Type = 'microsoft.sql/managedinstances' }
        sqlManagedInstanceDatabases = @{ Path = 'domains.databases'; Type = 'microsoft.sql/managedinstances/databases' }
        sqlElasticPools            = @{ Path = 'domains.databases'; Type = 'microsoft.sql/servers/elasticpools' }
        sqlVirtualMachines         = @{ Path = 'domains.databases'; Type = 'microsoft.sqlvirtualmachine/sqlvirtualmachines' }
        # Web (domains.web)
        appServiceCertificates     = @{ Path = 'domains.web'; Type = 'microsoft.web/certificates' }
        appServiceDomains          = @{ Path = 'domains.web'; Type = 'microsoft.domainregistration/domains' }
        appServiceEnvironments     = @{ Path = 'domains.web'; Type = 'microsoft.web/hostingenvironments' }
        appServicePlans            = @{ Path = 'domains.web'; Type = 'microsoft.web/serverfarms' }
        communicationServices      = @{ Path = 'domains.web'; Type = 'microsoft.communication/communicationservices' }
        webAppDeploymentSlots      = @{ Path = 'domains.web'; Type = 'microsoft.web/sites/slots' }
        fluidRelayServers          = @{ Path = 'domains.web'; Type = 'microsoft.fluidrelay/fluidrelayservers' }
        notificationHubNamespaces  = @{ Path = 'domains.web'; Type = 'microsoft.notificationhubs/namespaces' }
        signalRServices            = @{ Path = 'domains.web'; Type = 'microsoft.signalrservice/signalr' }
        springApps                 = @{ Path = 'domains.web'; Type = 'microsoft.appplatform/spring' }
        staticWebApps              = @{ Path = 'domains.web'; Type = 'microsoft.web/staticsites' }
        webPubSubServices          = @{ Path = 'domains.web'; Type = 'microsoft.signalrservice/webpubsub' }
        # Security (domains.security)
        appComplianceReports       = @{ Path = 'domains.security'; Type = 'microsoft.appcomplianceautomation/reports' }
        applicationSecurityGroups  = @{ Path = 'domains.security'; Type = 'microsoft.network/applicationsecuritygroups' }
        artifactSigningAccounts    = @{ Path = 'domains.security'; Type = 'microsoft.codesigning/codesigningaccounts' }
        cloudHsmClusters           = @{ Path = 'domains.security'; Type = 'microsoft.hardwaresecuritymodules/cloudhsmclusters' }
        confidentialLedgers        = @{ Path = 'domains.security'; Type = 'microsoft.confidentialledger/ledgers' }
        ddosProtectionPlans        = @{ Path = 'domains.security'; Type = 'microsoft.network/ddosprotectionplans' }
        entraDomainServices        = @{ Path = 'domains.security'; Type = 'microsoft.aad/domainservices' }
        managedHsms                = @{ Path = 'domains.security'; Type = 'microsoft.keyvault/managedhsms' }
        sentinelWorkspaces         = @{ Path = 'domains.security'; Type = 'microsoft.securityinsights/onboardingstates' }
        wafPolicies                = @{ Path = 'domains.security'; Type = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies' }
        # Storage (domains.storage)
        edgeHardwareCenterOrders   = @{ Path = 'domains.storage'; Type = 'microsoft.edgeorder/orders' }
        elasticSanVolumeGroups     = @{ Path = 'domains.storage'; Type = 'microsoft.elasticsan/elasticsans' }
        netAppVolumes              = @{ Path = 'domains.storage'; Type = 'microsoft.netapp/netappaccounts/capacitypools/volumes' }
        partnerStorageResources    = @{ Path = 'domains.storage'; Type = 'purestorage.block/storagepools' }
        storageSyncServices        = @{ Path = 'domains.storage'; Type = 'microsoft.storagesync/storagesyncservices' }
        # Management (management)
        advisorScores               = @{ Path = 'management'; Type = 'microsoft.advisor/advisorscore' }
        automationAccounts          = @{ Path = 'management'; Type = 'microsoft.automation/automationaccounts' }
        recoveryVaultBackupPolicies = @{ Path = 'management'; Type = 'microsoft.recoveryservices/vaults/backuppolicies' }
        lighthouseDelegations       = @{ Path = 'management'; Type = 'microsoft.managedservices/registrationdefinitions' }
        # Identity (domains.identity)
        managedIdentities          = @{ Path = 'domains.identity'; Type = 'microsoft.managedidentity/userassignedidentities' }
        # DevOps (devops)
        apiConnections              = @{ Path = 'devops'; Type = 'microsoft.web/connections' }
        appConfigurationStores      = @{ Path = 'devops'; Type = 'microsoft.appconfiguration/configurationstores' }
        deploymentEnvironmentTypes  = @{ Path = 'devops'; Type = 'microsoft.devcenter/projects/environmenttypes' }
        devBoxPools                 = @{ Path = 'devops'; Type = 'microsoft.devcenter/projects/pools' }
        devCenterNetworkConnections = @{ Path = 'devops'; Type = 'microsoft.devcenter/networkconnections' }
        devTestLabs                 = @{ Path = 'devops'; Type = 'microsoft.devtestlab/labs' }
        labServicesLabs             = @{ Path = 'devops'; Type = 'microsoft.labservices/labs' }
    }

    function New-MockSubscriptionRow {
        param([string] $Id = 'aaa')
        [pscustomobject]@{
            id = "/subscriptions/$Id"; name = "sub-$Id"; type = 'microsoft.resources/subscriptions'
            subscriptionId = $Id; location = $null; resourceGroup = $null
            kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
            extendedLocation = $null; managedBy = $null; tenantId = 'ten'
            properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null
        }
    }

    function Get-FixturePlumbingRows {
        @($script:PlumbingSpecs.GetEnumerator() | ForEach-Object {
                $key = $_.Key
                $type = $_.Value.Type
                [pscustomobject]@{
                    id = "/subscriptions/aaa/resourceGroups/rg1/providers/$type/$key-1"
                    name = "$key-1"; type = $type; location = 'eastus'
                    resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                    kind = 'SomeKind'; sku = [pscustomobject]@{ name = 'Standard'; tier = 'Standard'; capacity = 4 }
                    plan = $null; identity = $null; zones = $null
                    extendedLocation = $null; managedBy = $null; tags = $null
                    properties = [pscustomobject]@{
                        provisioningState = 'Succeeded'; status = 'Succeeded'; state = 'Succeeded'
                        publicNetworkAccess = 'Enabled'; disableLocalAuth = $true
                        sslEnforcement = 'Enabled'; version = '8.0'
                        network = [pscustomobject]@{ publicNetworkAccess = 'Enabled' }
                        publicDataEndpointEnabled = $true
                        keyVaultId = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.KeyVault/vaults/kv1'
                        reserved = $false
                        triggerTime = 'Weekly'
                        virtualNetworks = @('/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Network/virtualNetworks/vnet1')
                        ledgerType = 'Public'
                        orderItemDetails = [pscustomobject]@{ orderItemStatus = [pscustomobject]@{ status = 'Delivered' } }
                        usageThreshold = 107374182400
                        incomingTrafficPolicy = 'AllowAllTraffic'
                        lastRefreshedScore = [pscustomobject]@{ score = 87.5 }
                        schedulePolicy = [pscustomobject]@{ scheduleRunFrequency = 'Daily' }
                        backupManagementType = 'AzureIaasVM'
                        authorizations = @([pscustomobject]@{ principalId = 'p1'; roleDefinitionId = 'r1' })
                        licenseType = 'Windows_Client'
                        domainJoinType = 'AzureADJoin'
                        policySettings = [pscustomobject]@{ mode = 'Prevention' }
                        sqlImageSku = 'Enterprise'
                        sqlServerLicenseType = 'PAYG'
                        zoneRedundant = $true
                    }
                }
            }
        )
    }

    function Get-CollectValueAtPath {
        param($Collect, [string] $Key, [string] $DotPath)
        $node = $Collect
        foreach ($segment in $DotPath.Split('.')) { $node = $node.$segment }
        return $node.$Key
    }
}

Describe 'ConvertFrom-ScoutInventory -- AB#7110 Part 2 plumbing (Databases/DevOps/Identity/Management/Security/Storage/Web)' {

    It 'shapes every one of the 49 new keys, populated from the raw rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        foreach ($key in $script:PlumbingSpecs.Keys) {
            $shaped.ContainsKey($key) | Should -BeTrue -Because "ConvertFrom-ScoutInventory must shape '$key'"
            @($shaped[$key]).Count | Should -Be 1 -Because "the fixture carries exactly one $key row"
        }
    }

    It 'shapes every new key as an empty array (never throws, never missing) on an empty estate' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        foreach ($key in $script:PlumbingSpecs.Keys) {
            $shaped.ContainsKey($key) | Should -BeTrue -Because "'$key' must always be a declared key"
            @($shaped[$key]).Count | Should -Be 0
        }
    }

    It 'projects cosmosDbAccounts scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['cosmosDbAccounts'][0]
        $row.publicNetworkAccess | Should -Be 'Enabled'
        $row.disableLocalAuth | Should -BeTrue
    }

    It 'projects appServicePlans scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['appServicePlans'][0]
        $row.sku | Should -Be 'Standard'
        $row.reserved | Should -BeFalse
    }

    It 'projects wafPolicies policyType/mode correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['wafPolicies'][0]
        $row.policyType | Should -Be 'applicationgatewaywebapplicationfirewallpolicies'
        $row.mode | Should -Be 'Prevention'
    }

    It 'projects storageSyncServices incomingTrafficPolicy correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['storageSyncServices'][0]
        $row.incomingTrafficPolicy | Should -Be 'AllowAllTraffic'
    }

    It 'projects advisorScores lastRefreshedScore correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['advisorScores'][0]
        $row.lastRefreshedScore | Should -Be 87.5
    }

    It 'projects lighthouseDelegations authorizationCount correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['lighthouseDelegations'][0]
        $row.authorizationCount | Should -Be 1
    }

    It 'projects managedIdentities minimal fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['managedIdentities'][0]
        $row.name | Should -Be 'managedIdentities-1'
        $row.location | Should -Be 'eastus'
    }

    It 'projects appConfigurationStores sku correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePlumbingRows) -ResourceContainers @(New-MockSubscriptionRow)
        $row = $shaped['appConfigurationStores'][0]
        $row.sku | Should -Be 'Standard'
    }

    It 'redisCaches matches BOTH microsoft.cache/redis and microsoft.cache/redisenterprise' {
        $rows = @(
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.cache/redis/r1'
                name = 'r1'; type = 'microsoft.cache/redis'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = [pscustomobject]@{ name = 'Premium' }; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{ publicNetworkAccess = 'Enabled' }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.cache/redisenterprise/r2'
                name = 'r2'; type = 'microsoft.cache/redisenterprise'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = [pscustomobject]@{ name = 'Enterprise_E10' }; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{ publicNetworkAccess = 'Disabled' }
            }
        )
        $shaped = ConvertFrom-ScoutInventory -Resources $rows -ResourceContainers @(New-MockSubscriptionRow)
        @($shaped['redisCaches']).Count | Should -Be 2
    }
}

Describe 'Invoke-Collect -- AB#7110 Part 2 keys reach the canonical contract on both paths' {

    It 'the typed-query path (-Source TypedQueries) populates every new collect key' {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            foreach ($spec in $script:PlumbingSpecs.GetEnumerator()) {
                $typeEscaped = [regex]::Escape($spec.Value.Type)
                if ($Query -match $typeEscaped) {
                    return @([pscustomobject]@{
                            id = "/subscriptions/aaa/resourceGroups/rg1/providers/$($spec.Value.Type)/$($spec.Key)-1"
                            name = "$($spec.Key)-1"; resourceGroup = 'rg1'
                            subscriptionId = 'aaa'; location = 'eastus'
                            type = $spec.Value.Type
                            sku = 'Standard'; skuName = 'Standard'; skuTier = 'Standard'
                            provisioningState = 'Succeeded'; status = 'Succeeded'; state = 'Succeeded'
                            publicNetworkAccess = 'Enabled'; disableLocalAuth = $true
                            sslEnforcement = 'Enabled'; version = '8.0'
                            publicDataEndpointEnabled = $true; vCores = 4
                            keyVaultId = 'kv1'; reserved = $false
                            triggerType = 'Weekly'; virtualNetworkCount = 1
                            ledgerType = 'Public'; orderStatus = 'Delivered'
                            usageThresholdGB = 100; incomingTrafficPolicy = 'AllowAllTraffic'
                            lastRefreshedScore = 87.5; backupManagementType = 'AzureIaasVM'
                            scheduleFrequency = 'Daily'; authorizationCount = 1
                            licenseType = 'Windows_Client'; domainJoinType = 'AzureADJoin'
                            policyType = 'applicationgatewaywebapplicationfirewallpolicies'; mode = 'Prevention'
                            sqlImageSku = 'Enterprise'; sqlServerLicenseType = 'PAYG'
                            zoneRedundant = $true; kind = 'GlobalDocumentDB'
                            siteName = 'site1'
                        })
                }
            }
            return @()
        }

        try {
            $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue
            foreach ($spec in $script:PlumbingSpecs.GetEnumerator()) {
                $value = Get-CollectValueAtPath -Collect $collect -Key $spec.Key -DotPath $spec.Value.Path
                @($value).Count | Should -Be 1 -Because "collect.$($spec.Value.Path).$($spec.Key) must be populated on the typed-query path"
            }
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'the default inverted path (-FromInventory) populates every new collect key from raw rows' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixturePlumbingRows
            ResourceContainers = @(New-MockSubscriptionRow)
        }

        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            # Only sqlDefenderPricing is a live query on the inverted path; every AB#7110 key must
            # come from the raw rows already handed in via -FromInventory.
            return @()
        }

        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue
            foreach ($spec in $script:PlumbingSpecs.GetEnumerator()) {
                $value = Get-CollectValueAtPath -Collect $collect -Key $spec.Key -DotPath $spec.Value.Path
                @($value).Count | Should -Be 1 -Because "collect.$($spec.Value.Path).$($spec.Key) must be populated on the -FromInventory path"
            }
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'every new key is present, even as an empty array, on a completely empty estate' {
        $inventory = [pscustomobject]@{ Resources = @(); ResourceContainers = @() }
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            return @()
        }
        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue
            foreach ($spec in $script:PlumbingSpecs.GetEnumerator()) {
                { Get-CollectValueAtPath -Collect $collect -Key $spec.Key -DotPath $spec.Value.Path } | Should -Not -Throw
                $value = Get-CollectValueAtPath -Collect $collect -Key $spec.Key -DotPath $spec.Value.Path
                @($value).Count | Should -Be 0
            }
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        # Belt-and-braces: guarantee no global Search-AzGraph mock survives this file, regardless
        # of which It above defined one last, so a later test file in the same Pester session never
        # inherits a stale mock (observed to otherwise make Get-ScoutGovernanceDataset's own
        # Search-AzGraph mock never get resolved, surfacing as "$UseTenantScope has not been set").
        Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
    }
}
