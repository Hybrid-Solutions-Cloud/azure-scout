#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7061 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Azure Local child resources.

    `manifests/collectors/Hybrid/*.psd1` already exists for nine ordinary, ARG-indexed resource
    types this assessment collect never queried (ArcDataControllers, ArcGateways, ArcKubernetes,
    ArcResourceBridge, ArcSQLManagedInstances, ArcSQLServers, GalleryImages,
    MarketplaceGalleryImages, StorageContainers) -- the manifests ran, produced rows, and the rows
    never reached src/collect/Invoke-Collect.ps1's payload. Same class of defect AB#7064/7065/7066
    fixed for their respective slices: pure plumbing, not new collection logic.

    VirtualMachines and ArcSites are deliberately NOT covered here -- both are already wired via
    the ARM-child sweep (Resource Graph does not index their synthetic types), confirmed by
    docs/reference/collector-payload-coverage.md's Hybrid "wired via a synthetic type" table.
    ArcServerOperationalData is also not covered -- its ResourceTypes is
    `microsoft.hybridcompute/machines`, the same type `arcServers` already queries; only a
    separate per-machine REST envelope (not made on this collect pass) would add its
    distinguishing operational fields, which is out of scope for pure plumbing.

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

    $script:HybridChildKeys = @(
        'arcDataControllers', 'arcGateways', 'arcKubernetes', 'arcResourceBridge',
        'arcSqlManagedInstances', 'arcSqlServers', 'galleryImages',
        'marketplaceGalleryImages', 'storageContainers'
    )

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

    function Get-FixtureHybridChildRows {
        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.azurearcdata/datacontrollers/dc1'
                name = 'dc1'; type = 'microsoft.azurearcdata/datacontrollers'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    infrastructure = 'azure_stack_hci'
                    k8sRaw = [pscustomobject]@{ metadata = [pscustomobject]@{ namespace = 'arc' } }
                    provisioningState = 'Succeeded'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.hybridcompute/gateways/gw1'
                name = 'gw1'; type = 'microsoft.hybridcompute/gateways'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'; gatewayType = 'Public'
                    gatewayEndpoint = 'gw1.eastus.arc.azure.com'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.kubernetes/connectedclusters/k8s1'
                name = 'k8s1'; type = 'microsoft.kubernetes/connectedclusters'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'; connectivityStatus = 'Connected'
                    distribution = 'aks_management'; kubernetesVersion = '1.29.0'
                    totalNodeCount = 3
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.resourceconnector/appliances/brg1'
                name = 'brg1'; type = 'microsoft.resourceconnector/appliances'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'; status = 'Running'; distro = 'AKSEdge'
                    version = '1.2.3'
                    infrastructureConfig = [pscustomobject]@{ provider = 'HCI' }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.azurearcdata/sqlmanagedinstances/mi1'
                name = 'mi1'; type = 'microsoft.azurearcdata/sqlmanagedinstances'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Ready'
                    dataControllerId = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.azurearcdata/datacontrollers/dc1'
                    tier = 'BusinessCritical'
                    vCores = [pscustomobject]@{ request = 4; limit = 8 }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.azurearcdata/sqlserverinstances/sql1'
                name = 'sql1'; type = 'microsoft.azurearcdata/sqlserverinstances'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'; version = '2022'; edition = 'Enterprise'
                    licenseType = 'PAYG'; vCore = 8; patchLevel = '16.0.4085.2'
                    azureDefenderStatus = 'Protected'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.azurestackhci/galleryimages/img1'
                name = 'img1'; type = 'microsoft.azurestackhci/galleryimages'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'; osType = 'Windows'; hyperVGeneration = 'V2'
                    identifier = [pscustomobject]@{ publisher = 'MicrosoftWindowsServer'; offer = 'WindowsServer'; sku = '2022-datacenter-azure-edition' }
                    version = [pscustomobject]@{ name = '1.0.0' }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.azurestackhci/marketplacegalleryimages/mimg1'
                name = 'mimg1'; type = 'microsoft.azurestackhci/marketplacegalleryimages'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'
                    status = [pscustomobject]@{ provisioningStatus = [pscustomobject]@{ status = 'Succeeded' } }
                    osType = 'Linux'; hyperVGeneration = 'V2'
                    identifier = [pscustomobject]@{ publisher = 'Canonical'; offer = 'UbuntuServer'; sku = '22_04-lts' }
                    version = [pscustomobject]@{ name = '22.04.202601010' }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.azurestackhci/storagecontainers/sc1'
                name = 'sc1'; type = 'microsoft.azurestackhci/storagecontainers'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'
                    status = [pscustomobject]@{
                        provisioningStatus = [pscustomobject]@{ status = 'Succeeded' }
                        availableSizeBytes = 107374182400
                        containerSizeBytes = 214748364800
                    }
                    path = 'C:\ClusterStorage\UserStorage_1\sc1'
                }
            }
        )
    }
}

Describe 'ConvertFrom-ScoutInventory -- Azure Local child resources (AB#7061)' {

    It 'shapes every one of the nine Hybrid child keys, populated from the raw rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)

        foreach ($key in $script:HybridChildKeys) {
            $shaped.ContainsKey($key) | Should -BeTrue -Because "ConvertFrom-ScoutInventory must shape '$key'"
            @($shaped[$key]).Count | Should -Be 1 -Because "the fixture carries exactly one $key row"
        }
    }

    It 'shapes every key as an empty array (never throws, never missing) on an empty estate' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        foreach ($key in $script:HybridChildKeys) {
            $shaped.ContainsKey($key) | Should -BeTrue
            @($shaped[$key]).Count | Should -Be 0
        }
    }

    It 'projects arcDataControllers scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $dc = $shaped['arcDataControllers'][0]
        $dc.name | Should -Be 'dc1'
        $dc.infrastructure | Should -Be 'azure_stack_hci'
        $dc.k8sNamespace | Should -Be 'arc'
        $dc.provisioningState | Should -Be 'Succeeded'
    }

    It 'projects arcGateways scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $gw = $shaped['arcGateways'][0]
        $gw.gatewayType | Should -Be 'Public'
        $gw.gatewayEndpoint | Should -Match 'gw1.eastus.arc.azure.com'
    }

    It 'projects arcKubernetes scalar fields including totalNodeCount correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $k8s = $shaped['arcKubernetes'][0]
        $k8s.connectivityStatus | Should -Be 'Connected'
        $k8s.kubernetesVersion | Should -Be '1.29.0'
        $k8s.totalNodeCount | Should -Be 3
    }

    It 'projects arcResourceBridge scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $brg = $shaped['arcResourceBridge'][0]
        $brg.status | Should -Be 'Running'
        $brg.distro | Should -Be 'AKSEdge'
        $brg.infrastructureProvider | Should -Be 'HCI'
    }

    It 'projects arcSqlManagedInstances vCores request/limit correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $mi = $shaped['arcSqlManagedInstances'][0]
        $mi.tier | Should -Be 'BusinessCritical'
        $mi.vCoresRequest | Should -Be 4
        $mi.vCoresLimit | Should -Be 8
    }

    It 'projects arcSqlServers scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $sql = $shaped['arcSqlServers'][0]
        $sql.edition | Should -Be 'Enterprise'
        $sql.vCore | Should -Be 8
        $sql.azureDefenderStatus | Should -Be 'Protected'
    }

    It 'projects galleryImages identifier fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $img = $shaped['galleryImages'][0]
        $img.publisher | Should -Be 'MicrosoftWindowsServer'
        $img.sku | Should -Be '2022-datacenter-azure-edition'
        $img.imageVersion | Should -Be '1.0.0'
    }

    It 'projects marketplaceGalleryImages status and identifier fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $mimg = $shaped['marketplaceGalleryImages'][0]
        $mimg.status | Should -Be 'Succeeded'
        $mimg.publisher | Should -Be 'Canonical'
        $mimg.offer | Should -Be 'UbuntuServer'
    }

    It 'projects storageContainers size fields converted to GB correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureHybridChildRows) -ResourceContainers @(New-MockSubscriptionRow)
        $sc = $shaped['storageContainers'][0]
        $sc.path | Should -Match 'sc1'
        $sc.availableSizeGB | Should -Be 100
        $sc.containerSizeGB | Should -Be 200
    }
}

Describe 'Invoke-Collect -- Azure Local child resource keys reach collect.hybrid.* on both paths (AB#7061)' {

    It 'the typed-query path (-Source TypedQueries) populates collect.hybrid.*' {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'microsoft\.azurearcdata/datacontrollers') {
                return @([pscustomobject]@{ id = 'dc1'; name = 'dc1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        infrastructure = 'azure_stack_hci'; k8sNamespace = 'arc'; provisioningState = 'Succeeded' })
            }
            if ($Query -match 'microsoft\.hybridcompute/gateways') {
                return @([pscustomobject]@{ id = 'gw1'; name = 'gw1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; gatewayType = 'Public'; gatewayEndpoint = 'gw1' })
            }
            if ($Query -match 'microsoft\.kubernetes/connectedclusters') {
                return @([pscustomobject]@{ id = 'k8s1'; name = 'k8s1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; connectivityStatus = 'Connected'; distribution = 'aks_management'
                        kubernetesVersion = '1.29.0'; totalNodeCount = 3 })
            }
            if ($Query -match 'microsoft\.resourceconnector/appliances') {
                return @([pscustomobject]@{ id = 'brg1'; name = 'brg1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; status = 'Running'; distro = 'AKSEdge'; version = '1.2.3'
                        infrastructureProvider = 'HCI' })
            }
            if ($Query -match 'microsoft\.azurearcdata/sqlmanagedinstances') {
                return @([pscustomobject]@{ id = 'mi1'; name = 'mi1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Ready'; dataControllerId = 'dc1'; tier = 'BusinessCritical'
                        vCoresRequest = 4; vCoresLimit = 8 })
            }
            if ($Query -match 'microsoft\.azurearcdata/sqlserverinstances') {
                return @([pscustomobject]@{ id = 'sql1'; name = 'sql1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; version = '2022'; edition = 'Enterprise'; licenseType = 'PAYG'
                        vCore = 8; patchLevel = '16.0.4085.2'; azureDefenderStatus = 'Protected' })
            }
            if ($Query -match 'microsoft\.azurestackhci/galleryimages') {
                return @([pscustomobject]@{ id = 'img1'; name = 'img1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; osType = 'Windows'; hyperVGeneration = 'V2'
                        publisher = 'MicrosoftWindowsServer'; offer = 'WindowsServer'; sku = '2022-datacenter-azure-edition'
                        imageVersion = '1.0.0' })
            }
            if ($Query -match 'microsoft\.azurestackhci/marketplacegalleryimages') {
                return @([pscustomobject]@{ id = 'mimg1'; name = 'mimg1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; status = 'Succeeded'; osType = 'Linux'; hyperVGeneration = 'V2'
                        publisher = 'Canonical'; offer = 'UbuntuServer'; sku = '22_04-lts'; imageVersion = '22.04.202601010' })
            }
            if ($Query -match 'microsoft\.azurestackhci/storagecontainers') {
                return @([pscustomobject]@{ id = 'sc1'; name = 'sc1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; status = 'Succeeded'; path = 'C:\ClusterStorage\UserStorage_1\sc1'
                        availableSizeGB = 100; containerSizeGB = 200 })
            }
            return @()
        }

        try {
            $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

            $collect.domains.hybrid.PSObject.Properties.Name | Should -Contain 'arcDataControllers'
            @($collect.domains.hybrid.arcDataControllers).Count | Should -Be 1
            @($collect.domains.hybrid.arcGateways).Count | Should -Be 1
            @($collect.domains.hybrid.arcKubernetes).Count | Should -Be 1
            @($collect.domains.hybrid.arcResourceBridge).Count | Should -Be 1
            @($collect.domains.hybrid.arcSqlManagedInstances).Count | Should -Be 1
            @($collect.domains.hybrid.arcSqlServers).Count | Should -Be 1
            @($collect.domains.hybrid.galleryImages).Count | Should -Be 1
            @($collect.domains.hybrid.marketplaceGalleryImages).Count | Should -Be 1
            @($collect.domains.hybrid.storageContainers).Count | Should -Be 1

            $collect.domains.hybrid.arcDataControllers[0].name | Should -Be 'dc1'
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'the default inverted path (-FromInventory) populates collect.hybrid.* from raw rows' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixtureHybridChildRows
            ResourceContainers = @(New-MockSubscriptionRow)
        }

        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            # Only sqlDefenderPricing is a live query on the inverted path; every Hybrid child key
            # must come from the raw rows already handed in via -FromInventory.
            return @()
        }

        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue

            foreach ($key in $script:HybridChildKeys) {
                @($collect.domains.hybrid.$key).Count | Should -Be 1 -Because "'$key' must reach collect.hybrid via -FromInventory"
            }

            $collect.domains.hybrid.storageContainers[0].availableSizeGB | Should -Be 100
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'every Azure Local child key is present, even as an empty array, on a completely empty estate' {
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
            foreach ($key in $script:HybridChildKeys) {
                { @($collect.domains.hybrid.$key).Count } | Should -Not -Throw
                @($collect.domains.hybrid.$key).Count | Should -Be 0
            }
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'existing hybrid keys (arcServers, arcSites, azureLocalVirtualMachineInstances) are unaffected' {
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
            $collect.domains.hybrid.PSObject.Properties.Name | Should -Contain 'arcServers'
            $collect.domains.hybrid.PSObject.Properties.Name | Should -Contain 'arcSites'
            $collect.domains.hybrid.PSObject.Properties.Name | Should -Contain 'azureLocalVirtualMachineInstances'
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }
}
