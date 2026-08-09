#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7064 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Azure Monitor plumbing, remainder.

    The first AB#7064 slice wired eight ordinary Monitor collectors into `collect.monitor.*`.
    This is the five deferred collectors: `manifests/collectors/Monitor/AppInsights.psd1`,
    `MonitorWorkbooks.psd1`, `MonitorPrivateLinkScopes.psd1`, `LAWorkspaceSolutions.psd1`, and the
    `AppInsightsAvailabilityTests.psd1`/`AppInsightsWebTests.psd1` pair -- the latter two share one
    ARM resource type, `microsoft.insights/webtests`, distinguished only by the manifests'
    `AdditionalFilter` (AvailabilityTests has none, i.e. every Kind; WebTests filters
    `KIND -eq 'standard'`), so they combine into one `appInsightsAvailabilityTests` key carrying
    `kind` per row rather than two separate ARG round-trips over the same rows.

    Two collection paths must both reach every key:
      - Invoke-Collect -Source TypedQueries (the live KQL query pack)
      - Invoke-Collect -FromInventory / the default inverted path (ConvertFrom-ScoutInventory)

    Search-AzGraph is mocked throughout. No live Azure connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    function Import-Module {         [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    $script:MonitorKeys = @(
        'appInsights', 'workbooks', 'privateLinkScopes', 'workspaceSolutions',
        'appInsightsAvailabilityTests'
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

    function Get-FixtureMonitorRows {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
        param()

        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/components/ai1'
                name = 'ai1'; type = 'microsoft.insights/components'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = 'web'; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    Application_Type = 'web'; Flow_Type = 'Bluefield'
                    RetentionInDays = 90; SamplingPercentage = 100
                    IngestionMode = 'LogAnalytics'
                    publicNetworkAccessForIngestion = 'Enabled'
                    publicNetworkAccessForQuery = 'Enabled'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/workbooks/wb1'
                name = 'wb1'; type = 'microsoft.insights/workbooks'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = 'shared'; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    category = 'workbook'; sourceId = 'azure monitor'; version = 'Notebook/1.0'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/privatelinkscopes/pls1'
                name = 'pls1'; type = 'microsoft.insights/privatelinkscopes'; location = 'Global'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    accessModeSettings = [pscustomobject]@{ queryAccessMode = 'Open'; ingestionAccessMode = 'PrivateOnly' }
                    privateEndpointConnections = @([pscustomobject]@{ name = 'pe1' })
                    scopedResources = @([pscustomobject]@{ linkedResourceId = 'law1' }, [pscustomobject]@{ linkedResourceId = 'ai1' })
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.operationsmanagement/solutions/sol1'
                name = 'sol1'; type = 'microsoft.operationsmanagement/solutions'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                plan = [pscustomobject]@{ name = 'Updates'; publisher = 'Microsoft'; product = 'OMSGallery/Updates' }
                properties = [pscustomobject]@{ workspaceResourceId = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.OperationalInsights/workspaces/law1' }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/webtests/wt1'
                name = 'wt1'; type = 'microsoft.insights/webtests'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = 'standard'; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    Enabled = $true; Frequency = 300; Timeout = 30
                    Locations = @([pscustomobject]@{ Id = 'us-va-ash-azr' }, [pscustomobject]@{ Id = 'us-fl-mia-edge' })
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/webtests/wt2'
                name = 'wt2'; type = 'microsoft.insights/webtests'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = 'multistep'; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    Enabled = $true; Frequency = 900; Timeout = 120
                    SyntheticMonitorId = 'wt2-monitor-id'
                    Locations = @([pscustomobject]@{ Id = 'us-va-ash-azr' })
                }
            }
        )
    }
}

Describe 'ConvertFrom-ScoutInventory -- Monitor plumbing remainder (AB#7064)' {

    It 'shapes every one of the five Monitor keys, populated from the raw rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)

        foreach ($key in $script:MonitorKeys) {
            $shaped.ContainsKey($key) | Should -BeTrue -Because "ConvertFrom-ScoutInventory must shape '$key'"
        }
        @($shaped['appInsights']).Count | Should -Be 1
        @($shaped['workbooks']).Count | Should -Be 1
        @($shaped['privateLinkScopes']).Count | Should -Be 1
        @($shaped['workspaceSolutions']).Count | Should -Be 1
        # webtests: both wt1 (kind=standard) and wt2 (kind=multistep) land in the ONE combined
        # key -- AvailabilityTests' scope (no AdditionalFilter) reproduced without a second
        # ARG round-trip for WebTests' narrower (kind=standard) subset.
        @($shaped['appInsightsAvailabilityTests']).Count | Should -Be 2
    }

    It 'shapes every key as an empty array (never throws, never missing) on an empty estate' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        foreach ($key in $script:MonitorKeys) {
            $shaped.ContainsKey($key) | Should -BeTrue
            @($shaped[$key]).Count | Should -Be 0
        }
    }

    It 'projects appInsights scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $ai = $shaped['appInsights'][0]
        $ai.name | Should -Be 'ai1'
        $ai.applicationType | Should -Be 'web'
        $ai.flowType | Should -Be 'Bluefield'
        $ai.retentionInDays | Should -Be 90
        $ai.ingestionMode | Should -Be 'LogAnalytics'
        $ai.publicNetworkAccessForIngestion | Should -Be 'Enabled'
        $ai.publicNetworkAccessForQuery | Should -Be 'Enabled'
    }

    It 'projects workbooks scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $wb = $shaped['workbooks'][0]
        $wb.name | Should -Be 'wb1'
        $wb.kind | Should -Be 'shared'
        $wb.category | Should -Be 'workbook'
        $wb.sourceId | Should -Be 'azure monitor'
        $wb.version | Should -Be 'Notebook/1.0'
    }

    It 'projects privateLinkScopes access-mode and count fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $pls = $shaped['privateLinkScopes'][0]
        $pls.name | Should -Be 'pls1'
        $pls.accessMode | Should -Be 'Open'
        $pls.ingestionAccessMode | Should -Be 'PrivateOnly'
        $pls.privateEndpointConnectionCount | Should -Be 1
        $pls.scopedResourceCount | Should -Be 2
    }

    It 'projects workspaceSolutions plan fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $sol = $shaped['workspaceSolutions'][0]
        $sol.name | Should -Be 'sol1'
        $sol.planName | Should -Be 'Updates'
        $sol.planPublisher | Should -Be 'Microsoft'
        $sol.planProduct | Should -Be 'OMSGallery/Updates'
        $sol.workspaceResourceId | Should -Match 'law1'
    }

    It 'projects appInsightsAvailabilityTests kind/enabled/frequency/timeout/locations correctly for both rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $wt1 = $shaped['appInsightsAvailabilityTests'] | Where-Object { $_.name -eq 'wt1' }
        $wt1.kind | Should -Be 'standard'
        $wt1.enabled | Should -BeTrue
        $wt1.frequency | Should -Be 300
        $wt1.timeoutSeconds | Should -Be 30
        $wt1.testLocationCount | Should -Be 2

        $wt2 = $shaped['appInsightsAvailabilityTests'] | Where-Object { $_.name -eq 'wt2' }
        $wt2.kind | Should -Be 'multistep'
        $wt2.syntheticMonitorId | Should -Be 'wt2-monitor-id'
        $wt2.testLocationCount | Should -Be 1
    }

    It 'the appInsightsAvailabilityTests array can be filtered to the WebTests-only (kind=standard) subset' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $standardOnly = @($shaped['appInsightsAvailabilityTests'] | Where-Object { $_.kind -eq 'standard' })
        $standardOnly.Count | Should -Be 1
        $standardOnly[0].name | Should -Be 'wt1'
    }
}

Describe 'Invoke-Collect -- Monitor remainder keys reach the canonical contract on both paths (AB#7064)' {

    It 'the typed-query path (-Source TypedQueries) populates collect.monitor.*' {
        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'microsoft\.insights/components') {
                return @([pscustomobject]@{ id = 'ai1'; name = 'ai1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        applicationType = 'web'; flowType = 'Bluefield'; retentionInDays = 90; samplingPercentage = '100'
                        ingestionMode = 'LogAnalytics'; publicNetworkAccessForIngestion = 'Enabled'; publicNetworkAccessForQuery = 'Enabled' })
            }
            if ($Query -match 'microsoft\.insights/workbooks') {
                return @([pscustomobject]@{ id = 'wb1'; name = 'wb1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        kind = 'shared'; category = 'workbook'; sourceId = 'azure monitor'; version = 'Notebook/1.0' })
            }
            if ($Query -match 'microsoft\.insights/privatelinkscopes') {
                return @([pscustomobject]@{ id = 'pls1'; name = 'pls1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'Global'
                        accessMode = 'Open'; ingestionAccessMode = 'PrivateOnly'; privateEndpointConnectionCount = 1; scopedResourceCount = 2 })
            }
            if ($Query -match 'microsoft\.operationsmanagement/solutions') {
                return @([pscustomobject]@{ id = 'sol1'; name = 'sol1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        workspaceResourceId = 'law1'; planName = 'Updates'; planPublisher = 'Microsoft'; planProduct = 'OMSGallery/Updates' })
            }
            if ($Query -match 'microsoft\.insights/webtests') {
                return @(
                    [pscustomobject]@{ id = 'wt1'; name = 'wt1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        kind = 'standard'; enabled = $true; frequency = 300; timeoutSeconds = 30; syntheticMonitorId = $null; testLocationCount = 2 }
                    [pscustomobject]@{ id = 'wt2'; name = 'wt2'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        kind = 'multistep'; enabled = $true; frequency = 900; timeoutSeconds = 120; syntheticMonitorId = 'wt2-monitor-id'; testLocationCount = 1 }
                )
            }
            return @()
        }

        try {
            $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

            $collect.PSObject.Properties.Name | Should -Contain 'monitor'
            @($collect.monitor.appInsights).Count | Should -Be 1
            @($collect.monitor.workbooks).Count | Should -Be 1
            @($collect.monitor.privateLinkScopes).Count | Should -Be 1
            @($collect.monitor.workspaceSolutions).Count | Should -Be 1
            @($collect.monitor.appInsightsAvailabilityTests).Count | Should -Be 2

            $collect.monitor.appInsights[0].name | Should -Be 'ai1'
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'the default inverted path (-FromInventory) populates collect.monitor.* from raw rows' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixtureMonitorRows
            ResourceContainers = @(New-MockSubscriptionRow)
        }

        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            # Only sqlDefenderPricing is a live query on the inverted path; every Monitor key
            # must come from the raw rows already handed in via -FromInventory.
            return @()
        }

        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue

            @($collect.monitor.appInsights).Count | Should -Be 1
            @($collect.monitor.workbooks).Count | Should -Be 1
            @($collect.monitor.privateLinkScopes).Count | Should -Be 1
            @($collect.monitor.workspaceSolutions).Count | Should -Be 1
            @($collect.monitor.appInsightsAvailabilityTests).Count | Should -Be 2

            $collect.monitor.privateLinkScopes[0].scopedResourceCount | Should -Be 2
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'every Monitor remainder key is present, even as an empty array, on a completely empty estate' {
        $inventory = [pscustomobject]@{ Resources = @(); ResourceContainers = @() }
        function global:Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            return @()
        }
        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue
            foreach ($k in $script:MonitorKeys) { $collect.monitor.PSObject.Properties.Name | Should -Contain $k }
            foreach ($key in $script:MonitorKeys) {
                { @($collect.monitor.$key).Count } | Should -Not -Throw
                @($collect.monitor.$key).Count | Should -Be 0
            }
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }
}
