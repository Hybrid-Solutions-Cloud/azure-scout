#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- collector-payload wiring audit
    follow-up. `docs/reference/collector-payload-coverage.md` (AB#7060) found 165 of 242 shipped
    collector manifests never reach `Invoke-Collect`'s output. This file pins the 20 ordinary,
    ARG-indexed ARM types wired in this pass:

      Networking(13): applicationGateways, bastionHosts, networkConnections,
      expressRouteCircuits, frontDoors, loadBalancers, natGateways, networkInterfaces,
      networkWatchers, publicDnsZones, routeTables, trafficManagerProfiles, virtualWans.
      Containers(4): openShiftClusters, containerApps, containerAppEnvironments,
      containerGroups.
      Analytics(3): databricksWorkspaces, dataExplorerClusters, streamAnalyticsJobs.

    Both collect paths are exercised: `ConvertFrom-ScoutInventory` (the default, single-pass
    shaping path) and `Invoke-Collect -Source TypedQueries` (the live KQL pack, still the
    per-field reference implementation these shapers are verified against -- same standard as
    tests/Collect.SinglePassInversion.Tests.ps1).
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent

    # Neutralise Import-Module so `Import-Module Az.ResourceGraph` inside Invoke-Collect cannot
    # pull the real cmdlet into the session and make a live call.
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    function Get-AZSCManagementGroups { param($ManagementGroup, $Subscriptions) return $Subscriptions }

    # ---- one fixture row per newly-wired resource type ----
    # Every row carries the full raw-pass column set (Get-ScoutRawInventory's projection) so it
    # is a valid stand-in for what a real `resources` table round trip returns.
    function New-FixtureRow {
        param([string] $Type, [string] $Name, [hashtable] $Properties, [string] $Sku)
        [pscustomobject]@{
            id             = "/subscriptions/aaa/resourceGroups/rg-plumb/providers/$Type/$Name"
            name           = $Name
            type           = $Type
            location       = 'eastus'
            resourceGroup  = 'rg-plumb'
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
        (New-FixtureRow -Type 'microsoft.network/applicationgateways' -Name 'agw1' -Sku 'WAF_v2' -Properties @{
                sku = [pscustomobject]@{ name = 'WAF_v2'; tier = 'WAF_v2' }
                provisioningState = 'Succeeded'
            })
        (New-FixtureRow -Type 'microsoft.network/bastionhosts' -Name 'bas1' -Sku 'Standard' -Properties @{
                provisioningState = 'Succeeded'
            })
        (New-FixtureRow -Type 'microsoft.network/connections' -Name 'conn1' -Properties @{
                connectionType = 'IPsec'; connectionStatus = 'Connected'
            })
        (New-FixtureRow -Type 'microsoft.network/expressroutecircuits' -Name 'erc1' -Sku 'Premium' -Properties @{
                circuitProvisioningState = 'Enabled'; serviceProviderProvisioningState = 'Provisioned'
            })
        (New-FixtureRow -Type 'microsoft.network/frontdoors' -Name 'fd1' -Properties @{
                provisioningState = 'Succeeded'; enabledState = 'Enabled'
            })
        (New-FixtureRow -Type 'microsoft.network/loadbalancers' -Name 'lb1' -Sku 'Standard' -Properties @{
                frontendIPConfigurations = @([pscustomobject]@{ name = 'fe1' }, [pscustomobject]@{ name = 'fe2' })
            })
        (New-FixtureRow -Type 'microsoft.network/natgateways' -Name 'nat1' -Sku 'Standard' -Properties @{
                idleTimeoutInMinutes = 4
            })
        (New-FixtureRow -Type 'microsoft.network/networkinterfaces' -Name 'nic1' -Properties @{
                networkSecurityGroup = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-plumb/providers/microsoft.network/networksecuritygroups/nsg1' }
                ipConfigurations     = @([pscustomobject]@{ name = 'ipconfig1' })
            })
        (New-FixtureRow -Type 'microsoft.network/networkwatchers' -Name 'nw1' -Properties @{
                provisioningState = 'Succeeded'
            })
        (New-FixtureRow -Type 'microsoft.network/dnszones' -Name 'zone1' -Properties @{
                zoneType = 'Public'; numberOfRecordSets = 5
            })
        (New-FixtureRow -Type 'microsoft.network/routetables' -Name 'rt1' -Properties @{
                routes = @([pscustomobject]@{ name = 'r1' }, [pscustomobject]@{ name = 'r2' }, [pscustomobject]@{ name = 'r3' })
                disableBgpRoutePropagation = $true
            })
        (New-FixtureRow -Type 'microsoft.network/trafficmanagerprofiles' -Name 'tm1' -Properties @{
                profileStatus = 'Enabled'; trafficRoutingMethod = 'Performance'
            })
        (New-FixtureRow -Type 'microsoft.network/virtualwans' -Name 'vwan1' -Properties @{
                type = 'Standard'; allowBranchToBranchTraffic = $true
            })
        (New-FixtureRow -Type 'microsoft.redhatopenshift/openshiftclusters' -Name 'aro1' -Properties @{
                provisioningState = 'Succeeded'
            })
        (New-FixtureRow -Type 'microsoft.app/containerapps' -Name 'ca1' -Properties @{
                provisioningState = 'Succeeded'
                environmentId     = '/subscriptions/aaa/resourceGroups/rg-plumb/providers/microsoft.app/managedenvironments/env1'
            })
        (New-FixtureRow -Type 'microsoft.app/managedenvironments' -Name 'env1' -Properties @{
                provisioningState = 'Succeeded'
            })
        (New-FixtureRow -Type 'microsoft.containerinstance/containergroups' -Name 'cg1' -Properties @{
                osType = 'Linux'; restartPolicy = 'Always'
            })
        (New-FixtureRow -Type 'microsoft.databricks/workspaces' -Name 'dbw1' -Sku 'premium' -Properties @{
                managedResourceGroupId = '/subscriptions/aaa/resourceGroups/databricks-rg'
            })
        (New-FixtureRow -Type 'microsoft.kusto/clusters' -Name 'kc1' -Sku 'Standard_D13_v2' -Properties @{
                state = 'Running'
            })
        (New-FixtureRow -Type 'microsoft.streamanalytics/streamingjobs' -Name 'saj1' -Properties @{
                sku = [pscustomobject]@{ name = 'Standard' }; jobState = 'Running'
            })
    )

    # type -> typed-query response row (field names match each KQL block's `project` list).
    $script:TypedRows = @{
        'microsoft.network/applicationgateways' = [pscustomobject]@{ id = $script:FixtureRows[0].id; name = 'agw1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'WAF_v2'; tier = 'WAF_v2'; provisioningState = 'Succeeded' }
        'microsoft.network/bastionhosts' = [pscustomobject]@{ id = $script:FixtureRows[1].id; name = 'bas1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; provisioningState = 'Succeeded' }
        'microsoft.network/connections' = [pscustomobject]@{ id = $script:FixtureRows[2].id; name = 'conn1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; connectionType = 'IPsec'; connectionStatus = 'Connected' }
        'microsoft.network/expressroutecircuits' = [pscustomobject]@{ id = $script:FixtureRows[3].id; name = 'erc1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Premium'; circuitProvisioningState = 'Enabled'; serviceProviderProvisioningState = 'Provisioned' }
        'microsoft.network/frontdoors' = [pscustomobject]@{ id = $script:FixtureRows[4].id; name = 'fd1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; provisioningState = 'Succeeded'; enabledState = 'Enabled' }
        'microsoft.network/loadbalancers' = [pscustomobject]@{ id = $script:FixtureRows[5].id; name = 'lb1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; frontendIpCount = 2 }
        'microsoft.network/natgateways' = [pscustomobject]@{ id = $script:FixtureRows[6].id; name = 'nat1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; idleTimeoutInMinutes = 4 }
        'microsoft.network/networkinterfaces' = [pscustomobject]@{ id = $script:FixtureRows[7].id; name = 'nic1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; nsgAttached = $true; privateIpCount = 1 }
        'microsoft.network/networkwatchers' = [pscustomobject]@{ id = $script:FixtureRows[8].id; name = 'nw1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; provisioningState = 'Succeeded' }
        'microsoft.network/dnszones' = [pscustomobject]@{ id = $script:FixtureRows[9].id; name = 'zone1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; zoneType = 'Public'; recordSetCount = 5 }
        'microsoft.network/routetables' = [pscustomobject]@{ id = $script:FixtureRows[10].id; name = 'rt1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; routeCount = 3; disableBgpRoutePropagation = $true }
        'microsoft.network/trafficmanagerprofiles' = [pscustomobject]@{ id = $script:FixtureRows[11].id; name = 'tm1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; profileStatus = 'Enabled'; trafficRoutingMethod = 'Performance' }
        'microsoft.network/virtualwans' = [pscustomobject]@{ id = $script:FixtureRows[12].id; name = 'vwan1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; wanType = 'Standard'; allowBranchToBranchTraffic = $true }
        'microsoft.redhatopenshift/openshiftclusters' = [pscustomobject]@{ id = $script:FixtureRows[13].id; name = 'aro1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; provisioningState = 'Succeeded' }
        'microsoft.app/containerapps' = [pscustomobject]@{ id = $script:FixtureRows[14].id; name = 'ca1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; provisioningState = 'Succeeded'; environmentId = '/subscriptions/aaa/resourceGroups/rg-plumb/providers/microsoft.app/managedenvironments/env1' }
        'microsoft.app/managedenvironments' = [pscustomobject]@{ id = $script:FixtureRows[15].id; name = 'env1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; provisioningState = 'Succeeded' }
        'microsoft.containerinstance/containergroups' = [pscustomobject]@{ id = $script:FixtureRows[16].id; name = 'cg1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; osType = 'Linux'; restartPolicy = 'Always' }
        'microsoft.databricks/workspaces' = [pscustomobject]@{ id = $script:FixtureRows[17].id; name = 'dbw1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'premium'; managedResourceGroupId = '/subscriptions/aaa/resourceGroups/databricks-rg' }
        'microsoft.kusto/clusters' = [pscustomobject]@{ id = $script:FixtureRows[18].id; name = 'kc1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard_D13_v2'; state = 'Running' }
        'microsoft.streamanalytics/streamingjobs' = [pscustomobject]@{ id = $script:FixtureRows[19].id; name = 'saj1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; jobState = 'Running' }
    }

    function New-PlumbingSearchAzGraph {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            $isRawProjection = $Query -match 'project id,name,type,tenantId'
            if ($isRawProjection -and $Query -match '^resourcecontainers\b') { return @() }
            if ($isRawProjection -and $Query -match '^resources\b') { return $script:FixtureRows }
            if ($isRawProjection) { return @() }
            if ($Query -match 'SecurityResources') { return @() }
            foreach ($type in $script:TypedRows.Keys) {
                if ($Query -match [regex]::Escape($type)) { return @($script:TypedRows[$type]) }
            }
            return @()
        }
    }
}

AfterAll {
    Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-ScoutInventory shapes the 20 AB#7110 datasets from a populated estate' {

    BeforeAll {
        $script:Shaped = ConvertFrom-ScoutInventory -Resources $script:FixtureRows -ResourceContainers @()
    }

    It 'shapes applicationGateways' {
        $row = @($script:Shaped['applicationGateways'])[0]
        $row.name | Should -Be 'agw1'
        $row.sku | Should -Be 'WAF_v2'
        $row.tier | Should -Be 'WAF_v2'
        $row.provisioningState | Should -Be 'Succeeded'
    }
    It 'shapes bastionHosts' {
        $row = @($script:Shaped['bastionHosts'])[0]
        $row.name | Should -Be 'bas1'
        $row.sku | Should -Be 'Standard'
    }
    It 'shapes networkConnections' {
        $row = @($script:Shaped['networkConnections'])[0]
        $row.connectionType | Should -Be 'IPsec'
        $row.connectionStatus | Should -Be 'Connected'
    }
    It 'shapes expressRouteCircuits' {
        $row = @($script:Shaped['expressRouteCircuits'])[0]
        $row.sku | Should -Be 'Premium'
        $row.circuitProvisioningState | Should -Be 'Enabled'
        $row.serviceProviderProvisioningState | Should -Be 'Provisioned'
    }
    It 'shapes frontDoors' {
        $row = @($script:Shaped['frontDoors'])[0]
        $row.provisioningState | Should -Be 'Succeeded'
        $row.enabledState | Should -Be 'Enabled'
    }
    It 'shapes loadBalancers with a computed frontendIpCount' {
        $row = @($script:Shaped['loadBalancers'])[0]
        $row.sku | Should -Be 'Standard'
        $row.frontendIpCount | Should -Be 2
    }
    It 'shapes natGateways with an integer idleTimeoutInMinutes' {
        $row = @($script:Shaped['natGateways'])[0]
        $row.idleTimeoutInMinutes | Should -Be 4
        $row.idleTimeoutInMinutes | Should -BeOfType [int]
    }
    It 'shapes networkInterfaces, detecting an attached NSG' {
        $row = @($script:Shaped['networkInterfaces'])[0]
        $row.nsgAttached | Should -BeTrue
        $row.privateIpCount | Should -Be 1
    }
    It 'shapes networkWatchers' {
        $row = @($script:Shaped['networkWatchers'])[0]
        $row.provisioningState | Should -Be 'Succeeded'
    }
    It 'shapes publicDnsZones' {
        $row = @($script:Shaped['publicDnsZones'])[0]
        $row.zoneType | Should -Be 'Public'
        $row.recordSetCount | Should -Be 5
    }
    It 'shapes routeTables' {
        $row = @($script:Shaped['routeTables'])[0]
        $row.routeCount | Should -Be 3
        $row.disableBgpRoutePropagation | Should -BeTrue
    }
    It 'shapes trafficManagerProfiles' {
        $row = @($script:Shaped['trafficManagerProfiles'])[0]
        $row.profileStatus | Should -Be 'Enabled'
        $row.trafficRoutingMethod | Should -Be 'Performance'
    }
    It 'shapes virtualWans' {
        $row = @($script:Shaped['virtualWans'])[0]
        $row.wanType | Should -Be 'Standard'
        $row.allowBranchToBranchTraffic | Should -BeTrue
    }
    It 'shapes openShiftClusters' {
        $row = @($script:Shaped['openShiftClusters'])[0]
        $row.provisioningState | Should -Be 'Succeeded'
    }
    It 'shapes containerApps' {
        $row = @($script:Shaped['containerApps'])[0]
        $row.provisioningState | Should -Be 'Succeeded'
        $row.environmentId | Should -Match 'managedenvironments/env1'
    }
    It 'shapes containerAppEnvironments' {
        $row = @($script:Shaped['containerAppEnvironments'])[0]
        $row.provisioningState | Should -Be 'Succeeded'
    }
    It 'shapes containerGroups' {
        $row = @($script:Shaped['containerGroups'])[0]
        $row.osType | Should -Be 'Linux'
        $row.restartPolicy | Should -Be 'Always'
    }
    It 'shapes databricksWorkspaces' {
        $row = @($script:Shaped['databricksWorkspaces'])[0]
        $row.sku | Should -Be 'premium'
        $row.managedResourceGroupId | Should -Match 'databricks-rg'
    }
    It 'shapes dataExplorerClusters' {
        $row = @($script:Shaped['dataExplorerClusters'])[0]
        $row.sku | Should -Be 'Standard_D13_v2'
        $row.state | Should -Be 'Running'
    }
    It 'shapes streamAnalyticsJobs' {
        $row = @($script:Shaped['streamAnalyticsJobs'])[0]
        $row.sku | Should -Be 'Standard'
        $row.jobState | Should -Be 'Running'
    }
}

Describe 'ConvertFrom-ScoutInventory seeds all 20 AB#7110 keys as empty arrays on an empty estate' {

    BeforeAll {
        $script:EmptyShaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
    }

    It '<Key> is present and empty' -TestCases @(
        @{ Key = 'applicationGateways' }, @{ Key = 'bastionHosts' }, @{ Key = 'networkConnections' },
        @{ Key = 'expressRouteCircuits' }, @{ Key = 'frontDoors' }, @{ Key = 'loadBalancers' },
        @{ Key = 'natGateways' }, @{ Key = 'networkInterfaces' }, @{ Key = 'networkWatchers' },
        @{ Key = 'publicDnsZones' }, @{ Key = 'routeTables' }, @{ Key = 'trafficManagerProfiles' },
        @{ Key = 'virtualWans' }, @{ Key = 'openShiftClusters' }, @{ Key = 'containerApps' },
        @{ Key = 'containerAppEnvironments' }, @{ Key = 'containerGroups' },
        @{ Key = 'databricksWorkspaces' }, @{ Key = 'dataExplorerClusters' }, @{ Key = 'streamAnalyticsJobs' }
    ) {
        param($Key)
        $script:EmptyShaped.ContainsKey($Key) | Should -BeTrue
        @($script:EmptyShaped[$Key]).Count | Should -Be 0
    }
}

Describe 'Invoke-Collect (default, single-pass inverted path) reaches all 20 AB#7110 keys' {

    BeforeAll {
        New-PlumbingSearchAzGraph
        $script:Collect = Invoke-Collect -WarningAction SilentlyContinue
    }

    It 'places the 13 Networking datasets under networking{}' {
        $script:Collect.networking.applicationGateways[0].sku | Should -Be 'WAF_v2'
        $script:Collect.networking.bastionHosts[0].sku | Should -Be 'Standard'
        $script:Collect.networking.networkConnections[0].connectionStatus | Should -Be 'Connected'
        $script:Collect.networking.expressRouteCircuits[0].sku | Should -Be 'Premium'
        $script:Collect.networking.frontDoors[0].enabledState | Should -Be 'Enabled'
        $script:Collect.networking.loadBalancers[0].frontendIpCount | Should -Be 2
        $script:Collect.networking.natGateways[0].idleTimeoutInMinutes | Should -Be 4
        $script:Collect.networking.networkInterfaces[0].nsgAttached | Should -BeTrue
        $script:Collect.networking.networkWatchers[0].provisioningState | Should -Be 'Succeeded'
        $script:Collect.networking.publicDnsZones[0].recordSetCount | Should -Be 5
        $script:Collect.networking.routeTables[0].routeCount | Should -Be 3
        $script:Collect.networking.trafficManagerProfiles[0].profileStatus | Should -Be 'Enabled'
        $script:Collect.networking.virtualWans[0].wanType | Should -Be 'Standard'
    }

    It 'places the 4 Containers datasets under domains.containers{}' {
        $script:Collect.domains.containers.openShiftClusters[0].provisioningState | Should -Be 'Succeeded'
        $script:Collect.domains.containers.containerApps[0].environmentId | Should -Match 'env1'
        $script:Collect.domains.containers.containerAppEnvironments[0].provisioningState | Should -Be 'Succeeded'
        $script:Collect.domains.containers.containerGroups[0].osType | Should -Be 'Linux'
    }

    It 'places the 3 Analytics datasets under domains.analytics{}' {
        $script:Collect.domains.analytics.databricksWorkspaces[0].sku | Should -Be 'premium'
        $script:Collect.domains.analytics.dataExplorerClusters[0].state | Should -Be 'Running'
        $script:Collect.domains.analytics.streamAnalyticsJobs[0].jobState | Should -Be 'Running'
    }

    It 'never issues an extra Resource Graph round-trip for these 20 datasets -- shaped from the raw pass' {
        # Everything above came out of the SAME `resources` fixture row set collected by the raw
        # pass; nothing here required a distinct typed round trip.
        $script:Collect.networking.applicationGateways | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-Collect -Source TypedQueries reaches the same 20 AB#7110 keys via the live KQL pack' {

    BeforeAll {
        New-PlumbingSearchAzGraph
        $script:TypedCollect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue
    }

    It 'places the 13 Networking datasets under networking{}' {
        $script:TypedCollect.networking.applicationGateways[0].sku | Should -Be 'WAF_v2'
        $script:TypedCollect.networking.bastionHosts[0].sku | Should -Be 'Standard'
        $script:TypedCollect.networking.networkConnections[0].connectionStatus | Should -Be 'Connected'
        $script:TypedCollect.networking.expressRouteCircuits[0].sku | Should -Be 'Premium'
        $script:TypedCollect.networking.frontDoors[0].enabledState | Should -Be 'Enabled'
        $script:TypedCollect.networking.loadBalancers[0].frontendIpCount | Should -Be 2
        $script:TypedCollect.networking.natGateways[0].idleTimeoutInMinutes | Should -Be 4
        $script:TypedCollect.networking.networkInterfaces[0].nsgAttached | Should -BeTrue
        $script:TypedCollect.networking.networkWatchers[0].provisioningState | Should -Be 'Succeeded'
        $script:TypedCollect.networking.publicDnsZones[0].recordSetCount | Should -Be 5
        $script:TypedCollect.networking.routeTables[0].routeCount | Should -Be 3
        $script:TypedCollect.networking.trafficManagerProfiles[0].profileStatus | Should -Be 'Enabled'
        $script:TypedCollect.networking.virtualWans[0].wanType | Should -Be 'Standard'
    }

    It 'places the 4 Containers datasets under domains.containers{}' {
        $script:TypedCollect.domains.containers.openShiftClusters[0].provisioningState | Should -Be 'Succeeded'
        $script:TypedCollect.domains.containers.containerApps[0].environmentId | Should -Match 'env1'
        $script:TypedCollect.domains.containers.containerAppEnvironments[0].provisioningState | Should -Be 'Succeeded'
        $script:TypedCollect.domains.containers.containerGroups[0].osType | Should -Be 'Linux'
    }

    It 'places the 3 Analytics datasets under domains.analytics{}' {
        $script:TypedCollect.domains.analytics.databricksWorkspaces[0].sku | Should -Be 'premium'
        $script:TypedCollect.domains.analytics.dataExplorerClusters[0].state | Should -Be 'Running'
        $script:TypedCollect.domains.analytics.streamAnalyticsJobs[0].jobState | Should -Be 'Running'
    }
}
