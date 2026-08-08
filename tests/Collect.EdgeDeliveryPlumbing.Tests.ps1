#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6928 (Epic AB#7099) -- assessment-collect coverage for the EDGE-AND-DELIVERY types.
    Pins the six extended networking keys:

      loadBalancers          (+backendPoolCount, +hasPublicFrontend)
      applicationGateways    (+wafEnabled, +listenerCount, +backendPoolCount)
      frontDoors             (+sku, +endpointCount)  -- classic microsoft.network/frontdoors,
                                                        the type Networking/Frontdoor.psd1 targets
      trafficManagerProfiles (+monitorStatus, +endpointCount)
      natGateways            (+publicIpCount, +subnetCount)
      bastionHosts           (+vnet, parsed from the ipConfiguration subnet id)

    Both collect paths are exercised, same standard as tests/Collect.AB7110Plumbing.Tests.ps1
    and tests/Collect.ConnectivityPlumbing.Tests.ps1: `ConvertFrom-ScoutInventory` (the default,
    single-pass shaping path) and `Invoke-Collect -Source TypedQueries` (the live KQL pack).

    Also pinned: an internal-only load balancer (no public frontend) keeps its parent row with
    hasPublicFrontend $false -- no mv-expand is involved, so the AB#6845 vanishing-parent class
    is avoided by construction; and a non-WAF application gateway reads wafEnabled $false.
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

    function New-FixtureRow {
        param([string] $Type, [string] $Name, [hashtable] $Properties, [string] $Sku)
        [pscustomobject]@{
            id             = "/subscriptions/aaa/resourceGroups/rg-edge/providers/$Type/$Name"
            name           = $Name
            type           = $Type
            location       = 'eastus'
            resourceGroup  = 'rg-edge'
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
        (New-FixtureRow -Type 'microsoft.network/loadbalancers' -Name 'lb-public' -Sku 'Standard' -Properties @{
                frontendIPConfigurations = @(
                    [pscustomobject]@{
                        name       = 'fe-pub'
                        properties = [pscustomobject]@{
                            publicIPAddress = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-edge/providers/Microsoft.Network/publicIPAddresses/pip-lb' }
                        }
                    }
                )
                backendAddressPools = @([pscustomobject]@{ name = 'bp1' }, [pscustomobject]@{ name = 'bp2' })
            })
        # Internal-only LB -- must keep its row with hasPublicFrontend $false and 0 pools.
        (New-FixtureRow -Type 'microsoft.network/loadbalancers' -Name 'lb-internal' -Sku 'Standard' -Properties @{
                frontendIPConfigurations = @(
                    [pscustomobject]@{
                        name       = 'fe-int'
                        properties = [pscustomobject]@{ privateIPAddress = '10.0.1.4' }
                    }
                )
                backendAddressPools = @()
            })
        (New-FixtureRow -Type 'microsoft.network/applicationgateways' -Name 'agw-waf' -Sku 'WAF_v2' -Properties @{
                sku = [pscustomobject]@{ name = 'WAF_v2'; tier = 'WAF_v2' }
                provisioningState = 'Succeeded'
                webApplicationFirewallConfiguration = [pscustomobject]@{ enabled = $true }
                httpListeners       = @([pscustomobject]@{ name = 'l1' }, [pscustomobject]@{ name = 'l2' })
                backendAddressPools = @([pscustomobject]@{ name = 'bp1' })
            })
        # Standard_v2 tier, no WAF config -- wafEnabled must read $false.
        (New-FixtureRow -Type 'microsoft.network/applicationgateways' -Name 'agw-std' -Sku 'Standard_v2' -Properties @{
                sku = [pscustomobject]@{ name = 'Standard_v2'; tier = 'Standard_v2' }
                provisioningState   = 'Succeeded'
                httpListeners       = @([pscustomobject]@{ name = 'l1' })
                backendAddressPools = @([pscustomobject]@{ name = 'bp1' })
            })
        (New-FixtureRow -Type 'microsoft.network/frontdoors' -Name 'fd1' -Properties @{
                provisioningState = 'Succeeded'
                enabledState      = 'Enabled'
                frontendEndpoints = @(
                    [pscustomobject]@{ name = 'fe1'; properties = [pscustomobject]@{ hostName = 'fd1.azurefd.net' } }
                    [pscustomobject]@{ name = 'fe2'; properties = [pscustomobject]@{ hostName = 'www.contoso.com' } }
                )
            })
        (New-FixtureRow -Type 'microsoft.network/trafficmanagerprofiles' -Name 'tm1' -Properties @{
                profileStatus        = 'Enabled'
                trafficRoutingMethod = 'Performance'
                monitorConfig        = [pscustomobject]@{ profileMonitorStatus = 'Online' }
                endpoints            = @([pscustomobject]@{ name = 'ep1' }, [pscustomobject]@{ name = 'ep2' }, [pscustomobject]@{ name = 'ep3' })
            })
        (New-FixtureRow -Type 'microsoft.network/natgateways' -Name 'nat1' -Sku 'Standard' -Properties @{
                idleTimeoutInMinutes = 4
                publicIpAddresses    = @(
                    [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-edge/providers/Microsoft.Network/publicIPAddresses/pip-nat1' }
                    [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-edge/providers/Microsoft.Network/publicIPAddresses/pip-nat2' }
                )
                subnets              = @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-edge/providers/Microsoft.Network/virtualNetworks/vnet-edge/subnets/snet-1' })
            })
        (New-FixtureRow -Type 'microsoft.network/bastionhosts' -Name 'bas1' -Sku 'Standard' -Properties @{
                provisioningState = 'Succeeded'
                ipConfigurations  = @(
                    [pscustomobject]@{
                        name       = 'bastionIpConfig'
                        properties = [pscustomobject]@{
                            subnet = [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-edge/providers/Microsoft.Network/virtualNetworks/vnet-edge/subnets/AzureBastionSubnet' }
                        }
                    }
                )
            })
    )

    # Typed-query response rows -- field names match each KQL block's `project` list. Each of
    # the six queries names a resource-type string unique within this dispatch table.
    $script:TypedDispatch = @(
        @{ Pattern = 'microsoft.network/loadbalancers'; Rows = @(
                [pscustomobject]@{ id = $script:FixtureRows[0].id; name = 'lb-public'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; frontendIpCount = 1; backendPoolCount = 2; hasPublicFrontend = $true }
                [pscustomobject]@{ id = $script:FixtureRows[1].id; name = 'lb-internal'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; frontendIpCount = 1; backendPoolCount = 0; hasPublicFrontend = $false }
            ) }
        @{ Pattern = 'microsoft.network/applicationgateways'; Rows = @(
                [pscustomobject]@{ id = $script:FixtureRows[2].id; name = 'agw-waf'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'WAF_v2'; tier = 'WAF_v2'; provisioningState = 'Succeeded'; wafEnabled = $true; listenerCount = 2; backendPoolCount = 1 }
                [pscustomobject]@{ id = $script:FixtureRows[3].id; name = 'agw-std'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard_v2'; tier = 'Standard_v2'; provisioningState = 'Succeeded'; wafEnabled = $false; listenerCount = 1; backendPoolCount = 1 }
            ) }
        @{ Pattern = 'microsoft.network/frontdoors'; Rows = @(
                [pscustomobject]@{ id = $script:FixtureRows[4].id; name = 'fd1'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; sku = ''; provisioningState = 'Succeeded'; enabledState = 'Enabled'; endpointCount = 2 }
            ) }
        @{ Pattern = 'microsoft.network/trafficmanagerprofiles'; Rows = @(
                [pscustomobject]@{ id = $script:FixtureRows[5].id; name = 'tm1'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; profileStatus = 'Enabled'; trafficRoutingMethod = 'Performance'; monitorStatus = 'Online'; endpointCount = 3 }
            ) }
        @{ Pattern = 'microsoft.network/natgateways'; Rows = @(
                [pscustomobject]@{ id = $script:FixtureRows[6].id; name = 'nat1'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; idleTimeoutInMinutes = 4; publicIpCount = 2; subnetCount = 1 }
            ) }
        @{ Pattern = 'microsoft.network/bastionhosts'; Rows = @(
                [pscustomobject]@{ id = $script:FixtureRows[7].id; name = 'bas1'; resourceGroup = 'rg-edge'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard'; provisioningState = 'Succeeded'; vnet = 'vnet-edge' }
            ) }
    )

    function New-EdgeDeliverySearchAzGraph {
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

Describe 'ConvertFrom-ScoutInventory shapes the AB#6928 edge-and-delivery datasets from a populated estate' {

    BeforeAll {
        $script:Shaped = ConvertFrom-ScoutInventory -Resources $script:FixtureRows -ResourceContainers @()
    }

    It 'shapes loadBalancers with backend pools and a detected public frontend' {
        $row = @($script:Shaped['loadBalancers'] | Where-Object { $_.name -eq 'lb-public' })
        $row.sku | Should -Be 'Standard'
        $row.frontendIpCount | Should -Be 1
        $row.backendPoolCount | Should -Be 2
        $row.hasPublicFrontend | Should -BeTrue
        $row.hasPublicFrontend | Should -BeOfType [bool]
    }
    It 'keeps an internal-only load balancer as a parent row with hasPublicFrontend false' {
        $row = @($script:Shaped['loadBalancers'] | Where-Object { $_.name -eq 'lb-internal' })
        $row | Should -Not -BeNullOrEmpty
        $row.hasPublicFrontend | Should -BeFalse
        $row.backendPoolCount | Should -Be 0
    }
    It 'shapes applicationGateways with WAF, listener, and backend-pool detail' {
        $row = @($script:Shaped['applicationGateways'] | Where-Object { $_.name -eq 'agw-waf' })
        $row.sku | Should -Be 'WAF_v2'
        $row.tier | Should -Be 'WAF_v2'
        $row.wafEnabled | Should -BeTrue
        $row.wafEnabled | Should -BeOfType [bool]
        $row.listenerCount | Should -Be 2
        $row.backendPoolCount | Should -Be 1
    }
    It 'reads wafEnabled false on a Standard_v2 gateway with no WAF config' {
        $row = @($script:Shaped['applicationGateways'] | Where-Object { $_.name -eq 'agw-std' })
        $row.wafEnabled | Should -BeFalse
        $row.listenerCount | Should -Be 1
    }
    It 'shapes frontDoors (classic) with an endpoint count and an empty sku' {
        $row = @($script:Shaped['frontDoors'])[0]
        $row.name | Should -Be 'fd1'
        $row.sku | Should -Be ''
        $row.enabledState | Should -Be 'Enabled'
        $row.endpointCount | Should -Be 2
    }
    It 'shapes trafficManagerProfiles with the probe verdict and endpoint count' {
        $row = @($script:Shaped['trafficManagerProfiles'])[0]
        $row.trafficRoutingMethod | Should -Be 'Performance'
        $row.monitorStatus | Should -Be 'Online'
        $row.endpointCount | Should -Be 3
    }
    It 'shapes natGateways with public IP and subnet counts' {
        $row = @($script:Shaped['natGateways'])[0]
        $row.sku | Should -Be 'Standard'
        $row.publicIpCount | Should -Be 2
        $row.subnetCount | Should -Be 1
    }
    It 'shapes bastionHosts naming the owning VNet from the subnet id' {
        $row = @($script:Shaped['bastionHosts'])[0]
        $row.name | Should -Be 'bas1'
        $row.sku | Should -Be 'Standard'
        $row.vnet | Should -Be 'vnet-edge'
    }
}

Describe 'ConvertFrom-ScoutInventory seeds the AB#6928 edge-and-delivery keys as empty arrays on an empty estate' {

    BeforeAll {
        $script:EmptyShaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
    }

    It '<Key> is present and empty' -TestCases @(
        @{ Key = 'loadBalancers' }, @{ Key = 'applicationGateways' }, @{ Key = 'frontDoors' },
        @{ Key = 'trafficManagerProfiles' }, @{ Key = 'natGateways' }, @{ Key = 'bastionHosts' }
    ) {
        param($Key)
        $script:EmptyShaped.ContainsKey($Key) | Should -BeTrue
        @($script:EmptyShaped[$Key]).Count | Should -Be 0
    }
}

Describe 'Invoke-Collect (default, single-pass inverted path) reaches the AB#6928 edge-and-delivery fields' {

    BeforeAll {
        New-EdgeDeliverySearchAzGraph
        $script:Collect = Invoke-Collect -WarningAction SilentlyContinue
    }

    It 'places the edge-and-delivery detail under networking{}' {
        @($script:Collect.networking.loadBalancers | Where-Object { $_.name -eq 'lb-public' }).hasPublicFrontend | Should -BeTrue
        @($script:Collect.networking.loadBalancers | Where-Object { $_.name -eq 'lb-internal' }).hasPublicFrontend | Should -BeFalse
        @($script:Collect.networking.applicationGateways | Where-Object { $_.name -eq 'agw-waf' }).wafEnabled | Should -BeTrue
        @($script:Collect.networking.applicationGateways | Where-Object { $_.name -eq 'agw-std' }).wafEnabled | Should -BeFalse
        $script:Collect.networking.frontDoors[0].endpointCount | Should -Be 2
        $script:Collect.networking.trafficManagerProfiles[0].monitorStatus | Should -Be 'Online'
        $script:Collect.networking.natGateways[0].publicIpCount | Should -Be 2
        $script:Collect.networking.bastionHosts[0].vnet | Should -Be 'vnet-edge'
    }
}

Describe 'Invoke-Collect -Source TypedQueries reaches the same AB#6928 edge-and-delivery fields via the live KQL pack' {

    BeforeAll {
        New-EdgeDeliverySearchAzGraph
        $script:TypedCollect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue
    }

    It 'places the edge-and-delivery detail under networking{}' {
        @($script:TypedCollect.networking.loadBalancers | Where-Object { $_.name -eq 'lb-public' }).backendPoolCount | Should -Be 2
        @($script:TypedCollect.networking.loadBalancers | Where-Object { $_.name -eq 'lb-internal' }).hasPublicFrontend | Should -BeFalse
        @($script:TypedCollect.networking.applicationGateways | Where-Object { $_.name -eq 'agw-waf' }).listenerCount | Should -Be 2
        @($script:TypedCollect.networking.applicationGateways | Where-Object { $_.name -eq 'agw-std' }).wafEnabled | Should -BeFalse
        $script:TypedCollect.networking.frontDoors[0].endpointCount | Should -Be 2
        $script:TypedCollect.networking.frontDoors[0].sku | Should -Be ''
        $script:TypedCollect.networking.trafficManagerProfiles[0].endpointCount | Should -Be 3
        $script:TypedCollect.networking.natGateways[0].subnetCount | Should -Be 1
        $script:TypedCollect.networking.bastionHosts[0].vnet | Should -Be 'vnet-edge'
    }
}
