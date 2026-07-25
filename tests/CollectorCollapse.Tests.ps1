#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5543 — collapsing the duplicate inventory/assessment collection passes.

    Inventory and assessment used to each run their own Azure Resource Graph pass over the same
    resource types. `Invoke-Collect -FromInventory` now shapes the assessment's scalars from the
    rows an inventory pass already fetched.

    These tests pin the two things that make that safe:
      1. every projection reproduces the KQL semantics exactly (including the null-vs-zero and
         null-vs-false cases that a naive PowerShell rewrite silently gets wrong), and
      2. supplying -FromInventory does not re-query Azure, except for the one query that
         genuinely cannot be served from inventory rows.

    Pure-logic tests — no Azure connection.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/collect/ConvertFrom-ScoutInventory.ps1"

    function New-Resource {
        param([string] $Type, [string] $Name = 'r1', [hashtable] $Properties = @{}, [hashtable] $Extra = @{})
        $obj = [ordered]@{
            id             = "/subscriptions/sub1/resourceGroups/rg1/providers/$Type/$Name"
            name           = $Name
            type           = $Type
            location       = 'eastus'
            resourceGroup  = 'rg1'
            subscriptionId = 'sub1'
            properties     = [pscustomobject] $Properties
        }
        foreach ($k in $Extra.Keys) { $obj[$k] = $Extra[$k] }
        return [pscustomobject] $obj
    }
}

Describe 'ConvertFrom-ScoutInventory — KQL semantics are preserved' {

    It 'reports peeringCount as null when the peerings array is absent (KQL array_length(null) is null, not 0)' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{}
        ) -ResourceContainers @()
        $shaped['virtualNetworks'][0].peeringCount | Should -BeNullOrEmpty
    }

    It 'counts peerings when present' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{
                virtualNetworkPeerings = @(1, 2, 3)
            }
        ) -ResourceContainers @()
        $shaped['virtualNetworks'][0].peeringCount | Should -Be 3
    }

    It 'leaves a missing bool as null rather than false (KQL tobool(null) is null)' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.keyvault/vaults' -Properties @{}
        ) -ResourceContainers @()
        $shaped['keyVaults'][0].softDelete | Should -BeNullOrEmpty
        $shaped['keyVaults'][0].purgeProtection | Should -BeNullOrEmpty
    }

    It 'preserves an explicit false' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.keyvault/vaults' -Properties @{ enableSoftDelete = $false }
        ) -ResourceContainers @()
        $shaped['keyVaults'][0].softDelete | Should -BeExactly $false
    }

    It 'computes subnet utilisation as used / (2^(32-prefix) - 5)' {
        # /24 => 256 - 5 = 251 usable; 2 IP configs => 0.8%
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{
                subnets = @(
                    [pscustomobject]@{
                        name       = 'snet1'
                        properties = [pscustomobject]@{
                            addressPrefix    = '10.0.0.0/24'
                            ipConfigurations = @(1, 2)
                        }
                    }
                )
            }
        ) -ResourceContainers @()
        $shaped['subnets'][0].total | Should -Be 251
        $shaped['subnets'][0].used | Should -Be 2
        $shaped['subnets'][0].ipUtilizationPct | Should -Be 0.8
    }

    It 'keeps only Allow + Inbound NSG rules from an internet-equivalent source' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/networksecuritygroups' -Properties @{
                securityRules = @(
                    [pscustomobject]@{ name = 'open'; properties = [pscustomobject]@{ access = 'Allow'; direction = 'Inbound'; sourceAddressPrefix = '*'; destinationPortRange = '22' } }
                    [pscustomobject]@{ name = 'deny'; properties = [pscustomobject]@{ access = 'Deny'; direction = 'Inbound'; sourceAddressPrefix = '*'; destinationPortRange = '80' } }
                    [pscustomobject]@{ name = 'out'; properties = [pscustomobject]@{ access = 'Allow'; direction = 'Outbound'; sourceAddressPrefix = '*'; destinationPortRange = '443' } }
                    [pscustomobject]@{ name = 'scoped'; properties = [pscustomobject]@{ access = 'Allow'; direction = 'Inbound'; sourceAddressPrefix = '10.0.0.0/8'; destinationPortRange = '3389' } }
                )
            }
        ) -ResourceContainers @()
        $shaped['nsgPublicInbound'].Count | Should -Be 1
        $shaped['nsgPublicInbound'][0].rule | Should -Be 'open'
        $shaped['nsgPublicInbound'][0].port | Should -Be '22'
    }

    It 'splits a private endpoint target id into provider and type, falling back to the manual connection' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/privateendpoints' -Properties @{
                manualPrivateLinkServiceConnections = @(
                    [pscustomobject]@{ properties = [pscustomobject]@{ privateLinkServiceId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sa1' } }
                )
            }
        ) -ResourceContainers @()
        $shaped['privateEndpoints'][0].targetProvider | Should -Be 'microsoft.storage'
        $shaped['privateEndpoints'][0].targetType | Should -Be 'storageaccounts'
    }

    It 'marks allPoolsZoned only when every AKS pool has zones' {
        $mixed = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.containerservice/managedclusters' -Properties @{
                agentPoolProfiles = @(
                    [pscustomobject]@{ availabilityZones = @('1', '2') }
                    [pscustomobject]@{ availabilityZones = $null }
                )
            }
        ) -ResourceContainers @()
        $mixed['aksClusters'][0].allPoolsZoned | Should -BeExactly $false

        $allZoned = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.containerservice/managedclusters' -Properties @{
                agentPoolProfiles = @([pscustomobject]@{ availabilityZones = @('1') })
            }
        ) -ResourceContainers @()
        $allZoned['aksClusters'][0].allPoolsZoned | Should -BeExactly $true
    }

    It 'derives zoneRedundant from the zones column and zoneEligible from the region list' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.compute/virtualmachines' -Name 'vm1' -Properties @{ hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2s_v5' } } -Extra @{ zones = @('1') }
            New-Resource -Type 'microsoft.compute/virtualmachines' -Name 'vm2' -Properties @{} -Extra @{ zones = $null; location = 'nowhereland' }
        ) -ResourceContainers @()
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm1').zoneRedundant | Should -BeExactly $true
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm1').zoneEligible | Should -BeExactly $true
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm2').zoneRedundant | Should -BeExactly $false
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm2').zoneEligible | Should -BeExactly $false
    }

    It 'takes the parent policy name from the rule-collection-group resource id' {
        $group = New-Resource -Type 'microsoft.network/firewallpolicies/rulecollectiongroups' -Properties @{ priority = 100; ruleCollections = @() }
        $group.id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/firewallPolicies/pol1/ruleCollectionGroups/grp1'
        $shaped = ConvertFrom-ScoutInventory -Resources @($group) -ResourceContainers @()
        $shaped['firewallPolicyRuleGroups'][0].policyName | Should -Be 'pol1'
        $shaped['firewallPolicyRuleGroups'][0].priority | Should -Be 100
    }

    It 'strips the extension suffix to recover the Arc machine id' {
        $ext = New-Resource -Type 'microsoft.hybridcompute/machines/extensions' -Properties @{ type = 'MDE.Windows' }
        $ext.id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/m1/extensions/MDE'
        $shaped = ConvertFrom-ScoutInventory -Resources @($ext) -ResourceContainers @()
        $shaped['arcExtensions'][0].machineId | Should -Be '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/m1'
    }

    It 'de-duplicates rows that appear in both the resources and networkresources tables' {
        $vnet = New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{ virtualNetworkPeerings = @(1) }
        $shaped = ConvertFrom-ScoutInventory -Resources @($vnet, $vnet) -ResourceContainers @()
        $shaped['virtualNetworks'].Count | Should -Be 1
    }

    It 'projects subscriptions and resource groups out of the container rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @(
            [pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'Sub One'; subscriptionId = 'sub1'; properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null }
            [pscustomobject]@{ type = 'microsoft.resources/subscriptions/resourcegroups'; name = 'rg1'; subscriptionId = 'sub1' }
        )
        $shaped['subscriptions'].Count | Should -Be 1
        $shaped['subscriptions'][0].id | Should -Be 'sub1'
        $shaped['subscriptions'][0].state | Should -Be 'Enabled'
        $shaped['deployments'].Count | Should -Be 1
        $shaped['deployments'][0].name | Should -Be 'rg1'
    }

    It 'summarises diagnostic coverage per resource type' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.storage/storageaccounts' -Name 'a' -Properties @{ diagnosticSettings = [pscustomobject]@{ x = 1 } }
            New-Resource -Type 'microsoft.storage/storageaccounts' -Name 'b' -Properties @{}
        ) -ResourceContainers @()
        $row = $shaped['diagnosticCoverage'] | Where-Object type -EQ 'microsoft.storage/storageaccounts'
        $row.total | Should -Be 2
        $row.withDiag | Should -Be 1
        $row.coveragePct | Should -Be 50
    }

    It 'never produces sqlDefenderPricing — that query reads SecurityResources, which inventory does not collect' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        $shaped.ContainsKey('sqlDefenderPricing') | Should -BeFalse
    }
}

Describe 'Invoke-Collect -FromInventory — collects once, not twice' {

    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        # Stub the Az.ResourceGraph surface so the collector runs with no Azure connection and we
        # can count exactly which queries still reach Resource Graph.
        function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }
        . "$root/src/collect/Invoke-Collect.ps1"
    }

    It 'sends only the query that cannot be served from inventory to Resource Graph' {
        $script:argQueries = @()
        function Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip,
                [string] $ManagementGroup, [string[]] $Subscription,
                [string] $ErrorAction
            )
            $script:argQueries += $Query
            return @()
        }

        $inventory = [pscustomobject]@{
            Resources          = @(
                [pscustomobject]@{
                    id = '/subscriptions/sub1/resourceGroups/rg1/providers/microsoft.keyvault/vaults/kv1'
                    name = 'kv1'; type = 'microsoft.keyvault/vaults'; location = 'eastus'
                    resourceGroup = 'rg1'; subscriptionId = 'sub1'
                    properties = [pscustomobject]@{ enableSoftDelete = $true; enablePurgeProtection = $true }
                }
            )
            ResourceContainers = @(
                [pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'Sub One'; subscriptionId = 'sub1'; properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null }
            )
        }

        $collect = Invoke-Collect -FromInventory $inventory

        # Exactly one query type still goes to Azure: the SecurityResources pricings lookup.
        $script:argQueries.Count | Should -Be 1
        $script:argQueries[0] | Should -Match 'SecurityResources'
        $script:argQueries[0] | Should -Match 'microsoft.security/pricings'

        # And the assessment data really was populated from the inventory rows.
        $collect.domains.security.keyVaults.Count | Should -Be 1
        $collect.domains.security.keyVaults[0].softDelete | Should -BeExactly $true
        $collect.subscriptions.Count | Should -Be 1
        $collect.subscriptions[0].id | Should -Be 'sub1'
    }

    It 'still queries Resource Graph for every query when no inventory is supplied' {
        $script:argQueries = @()
        function Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip,
                [string] $ManagementGroup, [string[]] $Subscription,
                [string] $ErrorAction
            )
            $script:argQueries += $Query
            return @()
        }

        Invoke-Collect | Out-Null
        # The assessment-only path is unchanged: every typed query still runs.
        $script:argQueries.Count | Should -BeGreaterThan 30
    }
}
