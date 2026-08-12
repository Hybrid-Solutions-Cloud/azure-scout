#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6928 (Epic AB#7099) -- assessment-collect coverage for the CONNECTIVITY relationship
    types. Pins the four new networking keys and the two extended ones:

      NEW:      vnetPeerings, vpnConnections, localNetworkGateways, virtualHubs
      EXTENDED: expressRouteCircuits (+serviceProviderName, +peeringLocation, +bandwidthInMbps),
                routeTables (+subnetCount, +routes summary, +defaultRouteNextHopType)

    Both collect paths are exercised, same standard as tests/Collect.AB7110Plumbing.Tests.ps1:
    `ConvertFrom-ScoutInventory` (the default, single-pass shaping path) and
    `Invoke-Collect -Source TypedQueries` (the live KQL pack).

    Also pinned here: the VPN connection pre-shared key VALUE never reaches the payload --
    only the sharedKeyPresent bool does (hard rule: no secrets in any collected file).
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent

    # Neutralise Import-Module so `Import-Module Az.ResourceGraph` inside Invoke-Collect cannot
    # pull the real cmdlet into the session and make a live call.
    function Import-Module {         [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    function Get-AZSCManagementGroups {         [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
param($ManagementGroup, $Subscriptions) return $Subscriptions }

    $script:SharedKeyFixtureValue = 'fixture-psk-value-never-shipped'

    function New-FixtureRow {
        param([string] $Type, [string] $Name, [hashtable] $Properties, [string] $Sku)
        [pscustomobject]@{
            id             = "/subscriptions/aaa/resourceGroups/rg-conn/providers/$Type/$Name"
            name           = $Name
            type           = $Type
            location       = 'eastus'
            resourceGroup  = 'rg-conn'
            subscriptionId = 'aaa'
            tenantId       = 'ten'
            kind           = $null
            sku            = if ($Sku) { [pscustomobject]@{ name = $Sku } } else { $null }
            plan           = $null
            identity       = $null
            zones          = $null
            extendedLocation = $null
            managedBy      = $null
            tags           = $null
            properties     = [pscustomobject] $Properties
        }
    }

    $script:FixtureRows = @(
        (New-FixtureRow -Type 'microsoft.network/virtualnetworks' -Name 'vnet-hub' -Properties @{
                enableDdosProtection   = $false
                virtualNetworkPeerings = @(
                    [pscustomobject]@{
                        name       = 'hub-to-spoke1'
                        properties = [pscustomobject]@{
                            remoteVirtualNetwork = [pscustomobject]@{ id = '/subscriptions/bbb/resourceGroups/rg-spoke/providers/Microsoft.Network/virtualNetworks/vnet-spoke1' }
                            peeringState         = 'Connected'
                            allowGatewayTransit  = $true
                            useRemoteGateways    = $false
                        }
                    }
                    [pscustomobject]@{
                        name       = 'hub-to-spoke2'
                        properties = [pscustomobject]@{
                            remoteVirtualNetwork = [pscustomobject]@{ id = '/subscriptions/bbb/resourceGroups/rg-spoke/providers/Microsoft.Network/virtualNetworks/vnet-spoke2' }
                            peeringState         = 'Disconnected'
                            allowGatewayTransit  = $false
                            useRemoteGateways    = $true
                        }
                    }
                )
            })
        (New-FixtureRow -Type 'microsoft.network/connections' -Name 'cn-onprem' -Properties @{
                connectionType       = 'IPsec'
                connectionStatus     = 'Connected'
                sharedKey            = 'fixture-psk-value-never-shipped'
                virtualNetworkGateway1 = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-conn/providers/Microsoft.Network/virtualNetworkGateways/vgw-hub' }
                localNetworkGateway2   = [pscustomobject]@{
                    id         = '/subscriptions/aaa/resourceGroups/rg-conn/providers/Microsoft.Network/localNetworkGateways/lng-hq'
                    properties = [pscustomobject]@{
                        localNetworkAddressSpace = [pscustomobject]@{ addressPrefixes = @('10.100.0.0/16', '10.101.0.0/16') }
                    }
                }
            })
        (New-FixtureRow -Type 'microsoft.network/localnetworkgateways' -Name 'lng-hq' -Properties @{
                gatewayIpAddress         = '203.0.113.10'
                localNetworkAddressSpace = [pscustomobject]@{ addressPrefixes = @('10.100.0.0/16', '10.101.0.0/16') }
            })
        (New-FixtureRow -Type 'microsoft.network/virtualhubs' -Name 'hub-eastus' -Properties @{
                addressPrefix = '10.200.0.0/23'
                virtualWan    = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-conn/providers/Microsoft.Network/virtualWans/vwan-corp' }
            })
        (New-FixtureRow -Type 'microsoft.network/expressroutecircuits' -Name 'erc-dc1' -Sku 'Premium_MeteredData' -Properties @{
                circuitProvisioningState         = 'Enabled'
                serviceProviderProvisioningState = 'Provisioned'
                serviceProviderProperties        = [pscustomobject]@{
                    serviceProviderName = 'Equinix'
                    peeringLocation     = 'Washington DC'
                    bandwidthInMbps     = 1000
                }
            })
        (New-FixtureRow -Type 'microsoft.network/routetables' -Name 'rt-forced' -Properties @{
                disableBgpRoutePropagation = $true
                subnets = @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-conn/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/snet-1' })
                routes  = @(
                    [pscustomobject]@{
                        name       = 'default'
                        properties = [pscustomobject]@{ addressPrefix = '0.0.0.0/0'; nextHopType = 'VirtualAppliance' }
                    }
                    [pscustomobject]@{
                        name       = 'to-onprem'
                        properties = [pscustomobject]@{ addressPrefix = '10.100.0.0/16'; nextHopType = 'VirtualNetworkGateway' }
                    }
                )
            })
        # A route table with ZERO routes -- the AB#6845 vanishing-parent class. Its row must
        # survive with an empty routes summary.
        (New-FixtureRow -Type 'microsoft.network/routetables' -Name 'rt-empty' -Properties @{
                disableBgpRoutePropagation = $false
                routes = @()
            })
    )

    # Typed-query response rows -- field names match each KQL block's `project` list. Dispatched
    # by a query fragment UNIQUE to that query (several queries share a resource-type string:
    # vnetPeerings/virtualNetworks/subnets all name microsoft.network/virtualnetworks, and
    # vpnConnections/networkConnections both name microsoft.network/connections).
    $script:TypedDispatch = @(
        @{ Pattern = 'remoteVirtualNetwork'; Rows = @(
                [pscustomobject]@{ vnet = 'vnet-hub'; resourceGroup = 'rg-conn'; subscriptionId = 'aaa'; remoteVnetId = '/subscriptions/bbb/resourceGroups/rg-spoke/providers/Microsoft.Network/virtualNetworks/vnet-spoke1'; remoteVnetName = 'vnet-spoke1'; peeringState = 'Connected'; allowGatewayTransit = $true; useRemoteGateways = $false }
            ) }
        @{ Pattern = 'sharedKey'; Rows = @(
                [pscustomobject]@{ name = 'cn-onprem'; resourceGroup = 'rg-conn'; subscriptionId = 'aaa'; gatewayName = 'vgw-hub'; connectionType = 'IPsec'; connectionStatus = 'Connected'; localNetworkGatewayName = 'lng-hq'; localAddressPrefixes = '10.100.0.0/16,10.101.0.0/16'; sharedKeyPresent = $true }
            ) }
        @{ Pattern = 'microsoft.network/localnetworkgateways'; Rows = @(
                [pscustomobject]@{ name = 'lng-hq'; resourceGroup = 'rg-conn'; subscriptionId = 'aaa'; gatewayIpAddress = '203.0.113.10'; addressPrefixes = '10.100.0.0/16,10.101.0.0/16' }
            ) }
        @{ Pattern = 'microsoft.network/virtualhubs'; Rows = @(
                [pscustomobject]@{ name = 'hub-eastus'; resourceGroup = 'rg-conn'; subscriptionId = 'aaa'; addressPrefix = '10.200.0.0/23'; virtualWanName = 'vwan-corp' }
            ) }
        @{ Pattern = 'microsoft.network/expressroutecircuits'; Rows = @(
                [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-conn/providers/microsoft.network/expressroutecircuits/erc-dc1'; name = 'erc-dc1'; resourceGroup = 'rg-conn'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Premium_MeteredData'; circuitProvisioningState = 'Enabled'; serviceProviderProvisioningState = 'Provisioned'; serviceProviderName = 'Equinix'; peeringLocation = 'Washington DC'; bandwidthInMbps = 1000 }
            ) }
        @{ Pattern = 'microsoft.network/routetables'; Rows = @(
                [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-conn/providers/microsoft.network/routetables/rt-forced'; name = 'rt-forced'; resourceGroup = 'rg-conn'; subscriptionId = 'aaa'; location = 'eastus'; routeCount = 2; subnetCount = 1; disableBgpRoutePropagation = $true; routes = 'default:0.0.0.0/0->VirtualAppliance; to-onprem:10.100.0.0/16->VirtualNetworkGateway'; defaultRouteNextHopType = 'VirtualAppliance' }
            ) }
    )

    function New-ConnectivitySearchAzGraph {
        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            $isRawProjection = $Query -match 'project id,name,type,tenantId,kind'
            if ($isRawProjection -and $Query -match '^resourcecontainers\b') { return @() }
            if ($isRawProjection -and $Query -match '^resources\b') { return $script:FixtureRows }
            if ($isRawProjection) { return @() }
            if ($Query -match 'SecurityResources') { return @() }
            foreach ($entry in $script:TypedDispatch) {
                if ($Query -match [regex]::Escape($entry.Pattern)) { return @($entry.Rows) }
            }
            return @()
        }
    }
}

AfterAll {
    Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-ScoutInventory shapes the AB#6928 connectivity datasets from a populated estate' {

    BeforeAll {
        $script:Shaped = ConvertFrom-ScoutInventory -Resources $script:FixtureRows -ResourceContainers @()
    }

    It 'shapes one vnetPeerings row per peering pair' {
        @($script:Shaped['vnetPeerings']).Count | Should -Be 2
    }
    It 'shapes vnetPeerings with the remote VNet named from its id' {
        $row = @($script:Shaped['vnetPeerings'])[0]
        $row.vnet | Should -Be 'vnet-hub'
        $row.resourceGroup | Should -Be 'rg-conn'
        $row.remoteVnetId | Should -Match 'virtualNetworks/vnet-spoke1$'
        $row.remoteVnetName | Should -Be 'vnet-spoke1'
        $row.peeringState | Should -Be 'Connected'
        $row.allowGatewayTransit | Should -BeTrue
        $row.useRemoteGateways | Should -BeFalse
    }
    It 'shapes the second peering with its own gateway flags' {
        $row = @($script:Shaped['vnetPeerings'])[1]
        $row.remoteVnetName | Should -Be 'vnet-spoke2'
        $row.peeringState | Should -Be 'Disconnected'
        $row.allowGatewayTransit | Should -BeFalse
        $row.useRemoteGateways | Should -BeTrue
    }
    It 'shapes vpnConnections with both relationship endpoints named' {
        $row = @($script:Shaped['vpnConnections'])[0]
        $row.name | Should -Be 'cn-onprem'
        $row.gatewayName | Should -Be 'vgw-hub'
        $row.connectionType | Should -Be 'IPsec'
        $row.connectionStatus | Should -Be 'Connected'
        $row.localNetworkGatewayName | Should -Be 'lng-hq'
        $row.localAddressPrefixes | Should -Be '10.100.0.0/16,10.101.0.0/16'
    }
    It 'reports sharedKeyPresent as a bool and NEVER the key value' {
        $row = @($script:Shaped['vpnConnections'])[0]
        $row.sharedKeyPresent | Should -BeTrue
        $row.sharedKeyPresent | Should -BeOfType [bool]
        ($row | ConvertTo-Json -Depth 5) | Should -Not -Match ([regex]::Escape($script:SharedKeyFixtureValue))
    }
    It 'shapes localNetworkGateways with a joined address-prefix string' {
        $row = @($script:Shaped['localNetworkGateways'])[0]
        $row.name | Should -Be 'lng-hq'
        $row.gatewayIpAddress | Should -Be '203.0.113.10'
        $row.addressPrefixes | Should -Be '10.100.0.0/16,10.101.0.0/16'
    }
    It 'shapes virtualHubs with the owning vWAN named from its id' {
        $row = @($script:Shaped['virtualHubs'])[0]
        $row.name | Should -Be 'hub-eastus'
        $row.addressPrefix | Should -Be '10.200.0.0/23'
        $row.virtualWanName | Should -Be 'vwan-corp'
    }
    It 'shapes expressRouteCircuits with the AB#6928 provider relationship fields' {
        $row = @($script:Shaped['expressRouteCircuits'])[0]
        $row.serviceProviderName | Should -Be 'Equinix'
        $row.peeringLocation | Should -Be 'Washington DC'
        $row.bandwidthInMbps | Should -Be 1000
        $row.bandwidthInMbps | Should -BeOfType [int]
        $row.sku | Should -Be 'Premium_MeteredData'
    }
    It 'shapes routeTables with the per-route summary and flags the 0.0.0.0/0 next hop' {
        $row = @($script:Shaped['routeTables'] | Where-Object { $_.name -eq 'rt-forced' })
        $row.routeCount | Should -Be 2
        $row.subnetCount | Should -Be 1
        $row.disableBgpRoutePropagation | Should -BeTrue
        $row.routes | Should -Be 'default:0.0.0.0/0->VirtualAppliance; to-onprem:10.100.0.0/16->VirtualNetworkGateway'
        $row.defaultRouteNextHopType | Should -Be 'VirtualAppliance'
    }
    It 'keeps a route table with zero routes as a parent row (AB#6845 class)' {
        $row = @($script:Shaped['routeTables'] | Where-Object { $_.name -eq 'rt-empty' })
        $row | Should -Not -BeNullOrEmpty
        $row.routeCount | Should -Be 0
        $row.routes | Should -Be ''
        $row.defaultRouteNextHopType | Should -Be ''
    }
}

Describe 'ConvertFrom-ScoutInventory seeds the AB#6928 keys as empty arrays on an empty estate' {

    BeforeAll {
        $script:EmptyShaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
    }

    It '<Key> is present and empty' -TestCases @(
        @{ Key = 'vnetPeerings' }, @{ Key = 'vpnConnections' },
        @{ Key = 'localNetworkGateways' }, @{ Key = 'virtualHubs' },
        @{ Key = 'expressRouteCircuits' }, @{ Key = 'routeTables' }
    ) {
        param($Key)
        $script:EmptyShaped.ContainsKey($Key) | Should -BeTrue
        @($script:EmptyShaped[$Key]).Count | Should -Be 0
    }
}

Describe 'Invoke-Collect (default, single-pass inverted path) reaches the AB#6928 keys' {

    BeforeAll {
        New-ConnectivitySearchAzGraph
        $script:Collect = Invoke-Collect -WarningAction SilentlyContinue
    }

    It 'places the connectivity datasets under networking{}' {
        $script:Collect.networking.vnetPeerings[0].remoteVnetName | Should -Be 'vnet-spoke1'
        $script:Collect.networking.vpnConnections[0].gatewayName | Should -Be 'vgw-hub'
        $script:Collect.networking.vpnConnections[0].sharedKeyPresent | Should -BeTrue
        $script:Collect.networking.localNetworkGateways[0].gatewayIpAddress | Should -Be '203.0.113.10'
        $script:Collect.networking.virtualHubs[0].virtualWanName | Should -Be 'vwan-corp'
        $script:Collect.networking.expressRouteCircuits[0].serviceProviderName | Should -Be 'Equinix'
        @($script:Collect.networking.routeTables | Where-Object { $_.name -eq 'rt-forced' }).defaultRouteNextHopType |
            Should -Be 'VirtualAppliance'
    }

    It 'the serialized collect payload never contains the pre-shared key value' {
        ($script:Collect | ConvertTo-Json -Depth 20) | Should -Not -Match ([regex]::Escape($script:SharedKeyFixtureValue))
    }
}

Describe 'Invoke-Collect -Source TypedQueries reaches the same AB#6928 keys via the live KQL pack' {

    BeforeAll {
        New-ConnectivitySearchAzGraph
        $script:TypedCollect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue
    }

    It 'places the connectivity datasets under networking{}' {
        $script:TypedCollect.networking.vnetPeerings[0].remoteVnetName | Should -Be 'vnet-spoke1'
        $script:TypedCollect.networking.vnetPeerings[0].allowGatewayTransit | Should -BeTrue
        $script:TypedCollect.networking.vpnConnections[0].localNetworkGatewayName | Should -Be 'lng-hq'
        $script:TypedCollect.networking.vpnConnections[0].localAddressPrefixes | Should -Be '10.100.0.0/16,10.101.0.0/16'
        $script:TypedCollect.networking.localNetworkGateways[0].addressPrefixes | Should -Be '10.100.0.0/16,10.101.0.0/16'
        $script:TypedCollect.networking.virtualHubs[0].addressPrefix | Should -Be '10.200.0.0/23'
        $script:TypedCollect.networking.expressRouteCircuits[0].bandwidthInMbps | Should -Be 1000
        $script:TypedCollect.networking.routeTables[0].routes | Should -Match '0\.0\.0\.0/0->VirtualAppliance'
        $script:TypedCollect.networking.routeTables[0].subnetCount | Should -Be 1
    }

    It 'the serialized typed collect payload never contains the pre-shared key value' {
        ($script:TypedCollect | ConvertTo-Json -Depth 20) | Should -Not -Match ([regex]::Escape($script:SharedKeyFixtureValue))
    }
}
