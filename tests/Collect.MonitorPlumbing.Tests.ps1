#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7064 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Azure Monitor plumbing.

    `manifests/collectors/Monitor/*.psd1` already exists for eight ordinary, ARG-indexed Monitor
    resource types (ActionGroups, ActivityLogAlertRules, AutoscaleSettings, DataCollectionEndpoints,
    DataCollectionRules, MetricAlertRules, ScheduledQueryRules, SmartDetectorAlertRules), listed as
    "not wired" in docs/reference/collector-payload-coverage.md's Monitor(20) table -- the manifests
    ran, produced rows, and the rows never reached src/collect/Invoke-Collect.ps1's payload. This is
    the same class of defect AB#7065/AB#7066 fixed for maintenanceConfigurations/policyDefinitions:
    pure plumbing, not new collection logic.

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

    $script:MonitorKeys = @(
        'dataCollectionRules', 'dataCollectionEndpoints', 'actionGroups', 'autoscaleSettings',
        'metricAlertRules', 'scheduledQueryRules', 'activityLogAlertRules', 'smartDetectorAlertRules'
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
        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/datacollectionrules/dcr1'
                name = 'dcr1'; type = 'microsoft.insights/datacollectionrules'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    dataCollectionEndpointId = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/datacollectionendpoints/dce1'
                    destinations = [pscustomobject]@{ logAnalytics = @([pscustomobject]@{ workspaceResourceId = 'law1' }) }
                    dataFlows = @([pscustomobject]@{ streams = @('Microsoft-Perf') })
                    immutableId = 'dcr-immutable-1'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/datacollectionendpoints/dce1'
                name = 'dce1'; type = 'microsoft.insights/datacollectionendpoints'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    networkAcls = [pscustomobject]@{ publicNetworkAccess = 'Enabled' }
                    configurationAccess = [pscustomobject]@{ endpoint = 'https://dce1.eastus.ingest.monitor.azure.com' }
                    immutableId = 'dce-immutable-1'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/actiongroups/ag1'
                name = 'ag1'; type = 'microsoft.insights/actiongroups'; location = 'Global'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    enabled = $true; groupShortName = 'ag1short'
                    emailReceivers = @([pscustomobject]@{ name = 'ops'; emailAddress = 'ops@example.com' })
                    smsReceivers = @(); webhookReceivers = @()
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/autoscalesettings/as1'
                name = 'as1'; type = 'microsoft.insights/autoscalesettings'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    enabled = $true
                    targetResourceUri = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachineScaleSets/vmss1'
                    profiles = @([pscustomobject]@{ name = 'default' })
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/metricalerts/ma1'
                name = 'ma1'; type = 'microsoft.insights/metricalerts'; location = 'Global'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    enabled = $true; severity = 2; autoMitigate = $true
                    scopes = @('/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1')
                    actions = @([pscustomobject]@{ actionGroupId = 'ag1' })
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/scheduledqueryrules/sq1'
                name = 'sq1'; type = 'microsoft.insights/scheduledqueryrules'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    enabled = $true; severity = 3; autoMitigate = $false; kind = 'LogAlert'
                    scopes = @('/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.OperationalInsights/workspaces/law1')
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.insights/activitylogalerts/ala1'
                name = 'ala1'; type = 'microsoft.insights/activitylogalerts'; location = 'Global'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    enabled = $true
                    scopes = @('/subscriptions/aaa')
                    actions = [pscustomobject]@{ actionGroups = @([pscustomobject]@{ actionGroupId = 'ag1' }) }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.alertsmanagement/smartdetectoralertrules/sda1'
                name = 'sda1'; type = 'microsoft.alertsmanagement/smartdetectoralertrules'; location = 'Global'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    state = 'Enabled'; severity = 'Sev3'; frequency = 'PT1M'
                    actionGroups = [pscustomobject]@{ groupIds = @('ag1') }
                }
            }
        )
    }
}

Describe 'ConvertFrom-ScoutInventory -- Monitor plumbing (AB#7064)' {

    It 'shapes every one of the eight Monitor keys, populated from the raw rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)

        foreach ($key in $script:MonitorKeys) {
            $shaped.ContainsKey($key) | Should -BeTrue -Because "ConvertFrom-ScoutInventory must shape '$key'"
            @($shaped[$key]).Count | Should -Be 1 -Because "the fixture carries exactly one $key row"
        }
    }

    It 'shapes every key as an empty array (never throws, never missing) on an empty estate' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        foreach ($key in $script:MonitorKeys) {
            $shaped.ContainsKey($key) | Should -BeTrue
            @($shaped[$key]).Count | Should -Be 0
        }
    }

    It 'projects dataCollectionRules scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $dcr = $shaped['dataCollectionRules'][0]
        $dcr.name | Should -Be 'dcr1'
        $dcr.dataCollectionEndpointId | Should -Match 'dce1'
        $dcr.hasLogAnalyticsDestination | Should -BeTrue
        $dcr.dataFlowCount | Should -Be 1
        $dcr.immutableId | Should -Be 'dcr-immutable-1'
    }

    It 'projects dataCollectionEndpoints scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $dce = $shaped['dataCollectionEndpoints'][0]
        $dce.name | Should -Be 'dce1'
        $dce.publicNetworkAccess | Should -Be 'Enabled'
        $dce.configurationAccessEndpoint | Should -Match 'dce1.eastus.ingest.monitor.azure.com'
    }

    It 'projects actionGroups receiver counts correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $ag = $shaped['actionGroups'][0]
        $ag.enabled | Should -BeTrue
        $ag.groupShortName | Should -Be 'ag1short'
        $ag.emailReceiverCount | Should -Be 1
        $ag.smsReceiverCount | Should -Be 0
        $ag.webhookReceiverCount | Should -Be 0
    }

    It 'projects metricAlertRules severity/scope/action counts correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $ma = $shaped['metricAlertRules'][0]
        $ma.severity | Should -Be 2
        $ma.autoMitigate | Should -BeTrue
        $ma.scopeCount | Should -Be 1
        $ma.actionGroupCount | Should -Be 1
    }

    It 'projects smartDetectorAlertRules state/severity/frequency and action group count correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureMonitorRows) -ResourceContainers @(New-MockSubscriptionRow)
        $sda = $shaped['smartDetectorAlertRules'][0]
        $sda.state | Should -Be 'Enabled'
        $sda.severity | Should -Be 'Sev3'
        $sda.frequency | Should -Be 'PT1M'
        $sda.actionGroupCount | Should -Be 1
    }
}

Describe 'Invoke-Collect -- Monitor keys reach the canonical contract on both paths (AB#7064)' {

    It 'the typed-query path (-Source TypedQueries) populates collect.monitor.*' {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'microsoft\.insights/datacollectionrules') {
                return @([pscustomobject]@{ id = 'dcr1'; name = 'dcr1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        dataCollectionEndpointId = 'dce1'; hasLogAnalyticsDestination = $true; dataFlowCount = 1; immutableId = 'x' })
            }
            if ($Query -match 'microsoft\.insights/datacollectionendpoints') {
                return @([pscustomobject]@{ id = 'dce1'; name = 'dce1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        publicNetworkAccess = 'Enabled'; configurationAccessEndpoint = 'https://dce1'; immutableId = 'y' })
            }
            if ($Query -match 'microsoft\.insights/actiongroups') {
                return @([pscustomobject]@{ id = 'ag1'; name = 'ag1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'
                        enabled = $true; groupShortName = 'ag1'; emailReceiverCount = 1; smsReceiverCount = 0; webhookReceiverCount = 0 })
            }
            if ($Query -match 'microsoft\.insights/autoscalesettings') {
                return @([pscustomobject]@{ id = 'as1'; name = 'as1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        enabled = $true; targetResourceUri = 'vmss1'; profileCount = 1 })
            }
            if ($Query -match 'microsoft\.insights/metricalerts') {
                return @([pscustomobject]@{ id = 'ma1'; name = 'ma1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'
                        enabled = $true; severity = 2; autoMitigate = $true; scopeCount = 1; actionGroupCount = 1 })
            }
            if ($Query -match 'microsoft\.insights/scheduledqueryrules') {
                return @([pscustomobject]@{ id = 'sq1'; name = 'sq1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'
                        enabled = $true; severity = 3; autoMitigate = $false; kind = 'LogAlert'; scopeCount = 1 })
            }
            if ($Query -match 'microsoft\.insights/activitylogalerts') {
                return @([pscustomobject]@{ id = 'ala1'; name = 'ala1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'
                        enabled = $true; scopeCount = 1; actionGroupCount = 1 })
            }
            if ($Query -match 'microsoft\.alertsmanagement/smartdetectoralertrules') {
                return @([pscustomobject]@{ id = 'sda1'; name = 'sda1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'
                        state = 'Enabled'; severity = 'Sev3'; frequency = 'PT1M'; actionGroupCount = 1 })
            }
            return @()
        }

        try {
            $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

            $collect.PSObject.Properties.Name | Should -Contain 'monitor'
            @($collect.monitor.dataCollectionRules).Count | Should -Be 1
            @($collect.monitor.dataCollectionEndpoints).Count | Should -Be 1
            @($collect.monitor.actionGroups).Count | Should -Be 1
            @($collect.monitor.autoscaleSettings).Count | Should -Be 1
            @($collect.monitor.metricAlertRules).Count | Should -Be 1
            @($collect.monitor.scheduledQueryRules).Count | Should -Be 1
            @($collect.monitor.activityLogAlertRules).Count | Should -Be 1
            @($collect.monitor.smartDetectorAlertRules).Count | Should -Be 1

            $collect.monitor.dataCollectionRules[0].name | Should -Be 'dcr1'
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'the default inverted path (-FromInventory) populates collect.monitor.* from raw rows' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixtureMonitorRows
            ResourceContainers = @(New-MockSubscriptionRow)
        }

        function global:Search-AzGraph {
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

            @($collect.monitor.dataCollectionRules).Count | Should -Be 1
            @($collect.monitor.dataCollectionEndpoints).Count | Should -Be 1
            @($collect.monitor.actionGroups).Count | Should -Be 1
            @($collect.monitor.autoscaleSettings).Count | Should -Be 1
            @($collect.monitor.metricAlertRules).Count | Should -Be 1
            @($collect.monitor.scheduledQueryRules).Count | Should -Be 1
            @($collect.monitor.activityLogAlertRules).Count | Should -Be 1
            @($collect.monitor.smartDetectorAlertRules).Count | Should -Be 1

            $collect.monitor.actionGroups[0].emailReceiverCount | Should -Be 1
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'every Monitor key is present, even as an empty array, on a completely empty estate' {
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
            $collect.monitor.PSObject.Properties.Name | Should -Be $script:MonitorKeys
            foreach ($key in $script:MonitorKeys) {
                { @($collect.monitor.$key).Count } | Should -Not -Throw
                @($collect.monitor.$key).Count | Should -Be 0
            }
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }
}
