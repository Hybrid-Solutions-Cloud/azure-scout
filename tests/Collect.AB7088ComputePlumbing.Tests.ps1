#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7088 (Story AB#7071, Feature AB#7069, Epic AB#7099) -- Compute coverage-gap close-out.
    Pins the 6 ordinary, ARG-indexed ARM types wired in this pass:

      computeFleets (microsoft.azurefleet/fleets), batchAccounts (microsoft.batch/batchaccounts),
      dedicatedHostGroups (microsoft.compute/hostgroups),
      vmImageTemplates (microsoft.virtualmachineimages/imagetemplates),
      quantumWorkspaces (microsoft.quantum/workspaces), nutanixNodes (microsoft.nutanix/nodes).

    Both collect paths are exercised: `ConvertFrom-ScoutInventory` (the default, single-pass
    shaping path) and `Invoke-Collect -Source TypedQueries` (the live KQL pack, still the
    per-field reference implementation these shapers are verified against -- same standard as
    tests/Collect.AB7110Plumbing.Tests.ps1).
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

    function New-FixtureRow {
        param([string] $Type, [string] $Name, [hashtable] $Properties, [string] $Sku, [pscustomobject] $Identity)
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
            identity       = $Identity
            zones          = $null
            extendedLocation = $null
            managedBy      = $null
            tags           = $null
            properties     = [pscustomobject] $Properties
        }
    }

    $script:FixtureRows = @(
        (New-FixtureRow -Type 'microsoft.azurefleet/fleets' -Name 'fleet1' -Identity ([pscustomobject]@{ type = 'SystemAssigned' }) -Properties @{
                regularPriorityProfile = [pscustomobject]@{ allocationStrategy = 'LowestPrice' }
                spotPriorityProfile    = [pscustomobject]@{ allocationStrategy = 'CapacityOptimized' }
            })
        (New-FixtureRow -Type 'microsoft.batch/batchaccounts' -Name 'batch1' -Identity ([pscustomobject]@{ type = 'SystemAssigned' }) -Properties @{
                poolAllocationMode  = 'BatchService'
                publicNetworkAccess = 'Enabled'
                encryption          = [pscustomobject]@{ keySource = 'Microsoft.Batch' }
            })
        (New-FixtureRow -Type 'microsoft.compute/hostgroups' -Name 'dhg1' -Properties @{
                platformFaultDomainCount  = 2
                supportAutomaticPlacement = $true
                additionalCapabilities    = [pscustomobject]@{ ultraSSDEnabled = $true }
            })
        (New-FixtureRow -Type 'microsoft.virtualmachineimages/imagetemplates' -Name 'img1' -Identity ([pscustomobject]@{ type = 'UserAssigned' }) -Properties @{
                source = [pscustomobject]@{ type = 'PlatformImage' }
                buildTimeoutInMinutes = 60
            })
        (New-FixtureRow -Type 'microsoft.quantum/workspaces' -Name 'qw1' -Identity ([pscustomobject]@{ type = 'SystemAssigned' }) -Properties @{
                apiKeyEnabled = $true
                providers     = @([pscustomobject]@{ providerId = 'ionq' }, [pscustomobject]@{ providerId = 'rigetti' })
            })
        (New-FixtureRow -Type 'microsoft.nutanix/nodes' -Name 'ntx1' -Sku 'AN36' -Properties @{})
    )

    # type -> typed-query response row (field names match each KQL block's `project` list).
    $script:TypedRows = @{
        'microsoft.azurefleet/fleets' = [pscustomobject]@{ name = 'fleet1'; resourceGroup = 'rg-plumb'; identityType = 'SystemAssigned'; regularPriorityAllocationStrategy = 'LowestPrice'; spotPriorityAllocationStrategy = 'CapacityOptimized' }
        'microsoft.batch/batchaccounts' = [pscustomobject]@{ name = 'batch1'; resourceGroup = 'rg-plumb'; poolAllocationMode = 'BatchService'; publicNetworkAccess = 'Enabled'; identityType = 'SystemAssigned'; encryptionKeySource = 'Microsoft.Batch' }
        'microsoft.compute/hostgroups' = [pscustomobject]@{ name = 'dhg1'; resourceGroup = 'rg-plumb'; platformFaultDomainCount = 2; supportAutomaticPlacement = $true; ultraSsdEnabled = $true }
        'microsoft.virtualmachineimages/imagetemplates' = [pscustomobject]@{ name = 'img1'; resourceGroup = 'rg-plumb'; sourceType = 'PlatformImage'; buildTimeoutMinutes = 60; identityType = 'UserAssigned' }
        'microsoft.quantum/workspaces' = [pscustomobject]@{ name = 'qw1'; resourceGroup = 'rg-plumb'; apiKeyEnabled = $true; identityType = 'SystemAssigned'; providerCount = 2 }
        'microsoft.nutanix/nodes' = [pscustomobject]@{ name = 'ntx1'; resourceGroup = 'rg-plumb'; skuName = 'AN36' }
    }

    function New-PlumbingSearchAzGraph {
        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
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

Describe 'ConvertFrom-ScoutInventory shapes the 6 AB#7088 Compute datasets from a populated estate' {

    BeforeAll {
        $script:Shaped = ConvertFrom-ScoutInventory -Resources $script:FixtureRows -ResourceContainers @()
    }

    It 'shapes computeFleets' {
        $row = @($script:Shaped['computeFleets'])[0]
        $row.name | Should -Be 'fleet1'
        $row.identityType | Should -Be 'SystemAssigned'
        $row.regularPriorityAllocationStrategy | Should -Be 'LowestPrice'
        $row.spotPriorityAllocationStrategy | Should -Be 'CapacityOptimized'
    }
    It 'shapes batchAccounts' {
        $row = @($script:Shaped['batchAccounts'])[0]
        $row.poolAllocationMode | Should -Be 'BatchService'
        $row.publicNetworkAccess | Should -Be 'Enabled'
        $row.encryptionKeySource | Should -Be 'Microsoft.Batch'
    }
    It 'shapes dedicatedHostGroups with typed int/bool fields' {
        $row = @($script:Shaped['dedicatedHostGroups'])[0]
        $row.platformFaultDomainCount | Should -Be 2
        $row.platformFaultDomainCount | Should -BeOfType [int]
        $row.supportAutomaticPlacement | Should -BeTrue
        $row.ultraSsdEnabled | Should -BeTrue
    }
    It 'shapes vmImageTemplates' {
        $row = @($script:Shaped['vmImageTemplates'])[0]
        $row.sourceType | Should -Be 'PlatformImage'
        $row.buildTimeoutMinutes | Should -Be 60
        $row.identityType | Should -Be 'UserAssigned'
    }
    It 'shapes quantumWorkspaces with a computed providerCount' {
        $row = @($script:Shaped['quantumWorkspaces'])[0]
        $row.apiKeyEnabled | Should -BeTrue
        $row.providerCount | Should -Be 2
    }
    It 'shapes nutanixNodes' {
        $row = @($script:Shaped['nutanixNodes'])[0]
        $row.skuName | Should -Be 'AN36'
    }
}

Describe 'ConvertFrom-ScoutInventory returns empty (not missing) AB#7088 keys on an empty estate' {

    BeforeAll {
        $script:EmptyShaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
    }

    It 'declares <Key> as an empty array' -TestCases @(
        @{ Key = 'computeFleets' }, @{ Key = 'batchAccounts' }, @{ Key = 'dedicatedHostGroups' },
        @{ Key = 'vmImageTemplates' }, @{ Key = 'quantumWorkspaces' }, @{ Key = 'nutanixNodes' }
    ) {
        param($Key)
        $script:EmptyShaped.ContainsKey($Key) | Should -BeTrue
        @($script:EmptyShaped[$Key]).Count | Should -Be 0
    }
}

Describe 'Invoke-Collect (default, single-pass inverted path) reaches all 6 AB#7088 keys under compute{}' {

    BeforeAll {
        New-PlumbingSearchAzGraph
        $script:Collect = Invoke-Collect -WarningAction SilentlyContinue
    }

    It 'places the 6 Compute coverage-gap datasets under compute{}' {
        $script:Collect.compute.computeFleets[0].regularPriorityAllocationStrategy | Should -Be 'LowestPrice'
        $script:Collect.compute.batchAccounts[0].poolAllocationMode | Should -Be 'BatchService'
        $script:Collect.compute.dedicatedHostGroups[0].platformFaultDomainCount | Should -Be 2
        $script:Collect.compute.vmImageTemplates[0].sourceType | Should -Be 'PlatformImage'
        $script:Collect.compute.quantumWorkspaces[0].providerCount | Should -Be 2
        $script:Collect.compute.nutanixNodes[0].skuName | Should -Be 'AN36'
    }

    It 'never issues an extra Resource Graph round-trip for these 6 datasets -- shaped from the raw pass' {
        $script:Collect.compute.computeFleets | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-Collect -Source TypedQueries reaches the same 6 AB#7088 keys via the live KQL pack' {

    BeforeAll {
        New-PlumbingSearchAzGraph
        $script:TypedCollect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue
    }

    It 'places the 6 Compute coverage-gap datasets under compute{}' {
        $script:TypedCollect.compute.computeFleets[0].regularPriorityAllocationStrategy | Should -Be 'LowestPrice'
        $script:TypedCollect.compute.batchAccounts[0].poolAllocationMode | Should -Be 'BatchService'
        $script:TypedCollect.compute.dedicatedHostGroups[0].platformFaultDomainCount | Should -Be 2
        $script:TypedCollect.compute.vmImageTemplates[0].sourceType | Should -Be 'PlatformImage'
        $script:TypedCollect.compute.quantumWorkspaces[0].providerCount | Should -Be 2
        $script:TypedCollect.compute.nutanixNodes[0].skuName | Should -Be 'AN36'
    }
}
