#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7091 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Networking coverage-gap close-out.
    Pins the 4 ordinary, ARG-indexed ARM types wired in this pass: cdnProfiles (`microsoft.cdn/
    profiles`), networkManagers (`microsoft.network/networkmanagers`), firewallPolicies
    (`microsoft.network/firewallpolicies`), networkFunctions (`microsoft.hybridnetwork/
    networkfunctions`, folds in AB#7071 -- zero collector anywhere for this type prior to this
    pass).

    Route Server and Azure Enclave are deliberately NOT wired here -- see the cdnProfiles KQL
    comment in Invoke-Collect.ps1 and docs/reference/service-coverage-gap.md for why.

    Both collect paths are exercised: `ConvertFrom-ScoutInventory` (the default, single-pass
    shaping path) and `Invoke-Collect -Source TypedQueries` (the live KQL pack), same standard as
    tests/Collect.AB7110Plumbing.Tests.ps1.
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
        (New-FixtureRow -Type 'microsoft.cdn/profiles' -Name 'cdn1' -Sku 'Standard_Microsoft' -Properties @{
                provisioningState = 'Succeeded'; frontDoorId = 'fd-guid-1'
            })
        (New-FixtureRow -Type 'microsoft.network/networkmanagers' -Name 'nm1' -Properties @{
                provisioningState = 'Succeeded'
                networkManagerScopes = [pscustomobject]@{ subscriptions = @('/subscriptions/aaa', '/subscriptions/bbb') }
                networkManagerScopeAccesses = @('Connectivity', 'SecurityAdmin')
            })
        (New-FixtureRow -Type 'microsoft.network/firewallpolicies' -Name 'fwp1' -Properties @{
                sku = [pscustomobject]@{ tier = 'Premium' }
                provisioningState = 'Succeeded'; threatIntelMode = 'Deny'
                ruleCollectionGroups = @([pscustomobject]@{ id = 'rcg1' }, [pscustomobject]@{ id = 'rcg2' })
            })
        (New-FixtureRow -Type 'microsoft.hybridnetwork/networkfunctions' -Name 'nf1' -Properties @{
                provisioningState = 'Succeeded'; vendorProvisioningState = 'Succeeded'; serviceKey = 'svc-key-1'
            })
    )

    $script:TypedRows = @{
        'microsoft.cdn/profiles' = [pscustomobject]@{ id = $script:FixtureRows[0].id; name = 'cdn1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Standard_Microsoft'; provisioningState = 'Succeeded'; frontDoorId = 'fd-guid-1' }
        'microsoft.network/networkmanagers' = [pscustomobject]@{ id = $script:FixtureRows[1].id; name = 'nm1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; provisioningState = 'Succeeded'; scopeSubscriptionCount = 2; scopeAccesses = 'Connectivity,SecurityAdmin' }
        'microsoft.network/firewallpolicies' = [pscustomobject]@{ id = $script:FixtureRows[2].id; name = 'fwp1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; sku = 'Premium'; provisioningState = 'Succeeded'; threatIntelMode = 'Deny'; ruleCollectionGroupCount = 2 }
        'microsoft.hybridnetwork/networkfunctions' = [pscustomobject]@{ id = $script:FixtureRows[3].id; name = 'nf1'; resourceGroup = 'rg-plumb'; subscriptionId = 'aaa'; location = 'eastus'; provisioningState = 'Succeeded'; vendorProvisioningState = 'Succeeded'; serviceKey = 'svc-key-1' }
    }

    function New-PlumbingSearchAzGraph {
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

Describe 'ConvertFrom-ScoutInventory shapes the 4 AB#7091 Networking datasets from a populated estate' {

    BeforeAll {
        $script:Shaped = ConvertFrom-ScoutInventory -Resources $script:FixtureRows -ResourceContainers @()
    }

    It 'shapes cdnProfiles' {
        $row = @($script:Shaped['cdnProfiles'])[0]
        $row.name | Should -Be 'cdn1'
        $row.sku | Should -Be 'Standard_Microsoft'
        $row.provisioningState | Should -Be 'Succeeded'
        $row.frontDoorId | Should -Be 'fd-guid-1'
    }

    It 'shapes networkManagers with a computed scopeSubscriptionCount' {
        $row = @($script:Shaped['networkManagers'])[0]
        $row.name | Should -Be 'nm1'
        $row.provisioningState | Should -Be 'Succeeded'
        $row.scopeSubscriptionCount | Should -Be 2
        $row.scopeAccesses | Should -Be 'Connectivity,SecurityAdmin'
    }

    It 'shapes firewallPolicies with a computed ruleCollectionGroupCount' {
        $row = @($script:Shaped['firewallPolicies'])[0]
        $row.name | Should -Be 'fwp1'
        $row.sku | Should -Be 'Premium'
        $row.threatIntelMode | Should -Be 'Deny'
        $row.ruleCollectionGroupCount | Should -Be 2
    }

    It 'shapes networkFunctions' {
        $row = @($script:Shaped['networkFunctions'])[0]
        $row.name | Should -Be 'nf1'
        $row.provisioningState | Should -Be 'Succeeded'
        $row.vendorProvisioningState | Should -Be 'Succeeded'
        $row.serviceKey | Should -Be 'svc-key-1'
    }
}

Describe 'ConvertFrom-ScoutInventory seeds all 4 AB#7091 keys as empty arrays on an empty estate' {

    BeforeAll {
        $script:EmptyShaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
    }

    It '<Key> is present and empty' -TestCases @(
        @{ Key = 'cdnProfiles' }, @{ Key = 'networkManagers' },
        @{ Key = 'firewallPolicies' }, @{ Key = 'networkFunctions' }
    ) {
        param($Key)
        $script:EmptyShaped.ContainsKey($Key) | Should -BeTrue
        @($script:EmptyShaped[$Key]).Count | Should -Be 0
    }
}

Describe 'Invoke-Collect (default, single-pass inverted path) reaches all 4 AB#7091 keys' {

    BeforeAll {
        New-PlumbingSearchAzGraph
        $script:Collect = Invoke-Collect -WarningAction SilentlyContinue
    }

    It 'places the 4 Networking coverage-gap datasets under networking{}' {
        $script:Collect.networking.cdnProfiles[0].sku | Should -Be 'Standard_Microsoft'
        $script:Collect.networking.networkManagers[0].scopeSubscriptionCount | Should -Be 2
        $script:Collect.networking.firewallPolicies[0].threatIntelMode | Should -Be 'Deny'
        $script:Collect.networking.networkFunctions[0].serviceKey | Should -Be 'svc-key-1'
    }
}
