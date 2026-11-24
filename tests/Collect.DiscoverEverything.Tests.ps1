#Requires -Version 7.0
#Requires -Modules Pester

<#
    Everything deployed in Azure must have a way to be discovered (AB#9300).

    1. Every Azure Resource Graph table is either swept for discovery or excluded with a reason,
       so a table cannot be silently left out.
    2. The Resource Manager cross-check adds what Resource Graph did not return, and only that.

    No live Azure calls: Get-AzAccessToken, Invoke-RestMethod and Start-Sleep are stubbed.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/collect/Get-ScoutResourceGraphDiscoveryTable.ps1"
    . "$root/src/collect/Get-ScoutArmResourceCrossCheck.ps1"

    # Every table in the Resource Graph table reference
    # (learn.microsoft.com/azure/governance/resource-graph/reference/supported-tables-resources,
    # updated 2026-11-17). When Microsoft adds a table, add it here and classify it.
    $script:AllResourceGraphTables = @(
        'advisorresources', 'aksresources', 'alertsmanagementresources', 'apicenterresources', 'appserviceresources',
        'authorizationresources', 'awsresources', 'azurebusinesscontinuityresources', 'azuredevopsplatformresources',
        'batchresources', 'capabilityresources', 'changesafetyresources', 'chaosresources', 'cognitiveservicesresources',
        'communitygalleryresources', 'computeartifactresources', 'computeresources', 'containerserviceeventresources',
        'deploymentresourcechanges', 'deploymentresources', 'desktopvirtualizationresources', 'dnsresources',
        'edgeorderresources', 'elasticsanresources', 'extendedlocationresources', 'extensibilityresourcechanges',
        'featureresources', 'gcpresources', 'guestconfigurationresources', 'healthresourcechanges', 'healthresources',
        'impactreportresources', 'insightsresources', 'iotsecurityresources', 'kubernetesconfigurationresources',
        'kustoresources', 'machinesinventoryinsightsresources', 'maintenanceresourcechanges', 'maintenanceresources',
        'managedservicesresources', 'metricresources', 'migrateresources', 'monitorresources', 'networkresourcechanges',
        'networkresources', 'orbitalresources', 'patchassessmentresources', 'patchinstallationresources', 'policyresources',
        'quotaresourcechanges', 'recoveryservicesresources', 'resourcechanges', 'resourcecontainerchanges',
        'resourcecontainers', 'resources', 'saashubresources', 'securityresources', 'servicefabricresources',
        'servicehealthresources', 'sharedgalleryresources', 'spotresources', 'supercomputerinfraresources', 'tagsresources'
    )

    function Get-AzAccessToken {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Synthetic test token, not a secret.')]
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        [pscustomobject]@{ Token = (ConvertTo-SecureString -String 'test-token' -AsPlainText -Force) }
    }
    function Start-Sleep {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'No real waiting in a unit test.')]
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
    }
    function New-KnownIdSet {
        param([string[]] $Ids)
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($id in @($Ids)) { $null = $set.Add($id) }
        , $set
    }
}

Describe 'Resource Graph discovery tables' {
    It 'classifies every Resource Graph table as swept or excluded, never both' {
        $included = @(Get-ScoutResourceGraphDiscoveryTable | ForEach-Object Table)
        $excluded = @(Get-ScoutResourceGraphDiscoveryTable -Excluded | ForEach-Object Table)

        @($included | Where-Object { $_ -in $excluded }) | Should -BeNullOrEmpty
        @($script:AllResourceGraphTables | Where-Object { $_ -notin $included -and $_ -notin $excluded }) | Should -BeNullOrEmpty
        @($included + $excluded | Where-Object { $_ -notin $script:AllResourceGraphTables }) | Should -BeNullOrEmpty
    }

    It 'gives a reason for every excluded table' {
        foreach ($table in Get-ScoutResourceGraphDiscoveryTable -Excluded) {
            $table.Reason | Should -Not -BeNullOrEmpty -Because $table.Table
        }
    }

    It 'sweeps the tables that hold deployed governance, hybrid and configuration resources' {
        $included = @(Get-ScoutResourceGraphDiscoveryTable | ForEach-Object Table)
        foreach ($table in 'authorizationresources', 'policyresources', 'managedservicesresources', 'guestconfigurationresources',
            'maintenanceresources', 'kubernetesconfigurationresources', 'extendedlocationresources', 'insightsresources',
            'recoveryservicesresources', 'dnsresources', 'elasticsanresources', 'servicefabricresources', 'aksresources') {
            $included | Should -Contain $table
        }
    }

    It 'keeps compliance states, built-in definitions and run history out of discovery' {
        $tables = @{}
        foreach ($table in Get-ScoutResourceGraphDiscoveryTable) { $tables[$table.Table] = [string]$table.Filter }
        $tables['policyresources'] | Should -Not -Match 'policystates'
        $tables['policyresources'] | Should -Match "!in~ \('BuiltIn','Static'\)"
        $tables['authorizationresources'] | Should -Match 'CustomRole'
        $tables['deploymentresources'] | Should -Match 'deployments/operations'
        $tables['recoveryservicesresources'] | Should -Match 'jobs'
    }
}

Describe 'Get-ScoutArmResourceCrossCheck' {
    It 'returns only resources Resource Graph did not return, following every page' {
        function Invoke-RestMethod {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Offline stub.')]
            param([string] $Uri, [Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            if ($Uri -match 'page2') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = '/subscriptions/s1/resourceGroups/RG-B/providers/Microsoft.New/widgets/w2'; name = 'w2'; type = 'Microsoft.New/widgets'; location = 'eastus'; tags = [pscustomobject]@{ env = 'prod' } }) }
            }
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ id = '/subscriptions/s1/resourceGroups/rg-a/providers/Microsoft.Compute/virtualMachines/vm1'; name = 'vm1'; type = 'Microsoft.Compute/virtualMachines'; location = 'eastus' }
                    [pscustomobject]@{ id = '/subscriptions/s1/resourceGroups/rg-a/providers/Microsoft.New/widgets/w1'; name = 'w1'; type = 'Microsoft.New/widgets'; location = 'eastus'; sku = [pscustomobject]@{ name = 'S1' } }
                )
                nextLink = 'https://management.azure.com/subscriptions/s1/resources?page2'
            }
        }
        $known = New-KnownIdSet -Ids @('/SUBSCRIPTIONS/S1/resourceGroups/rg-a/providers/Microsoft.Compute/virtualMachines/vm1')

        $result = Get-ScoutArmResourceCrossCheck -SubscriptionIds @('s1') -KnownIds $known

        $result.Listed | Should -Be 3
        @($result.Rows).Count | Should -Be 2
        @($result.Rows | ForEach-Object name) | Should -Be @('w1', 'w2')
        $result.Rows[0].type | Should -Be 'microsoft.new/widgets'
        $result.Rows[0].resourceGroup | Should -Be 'rg-a'
        $result.Rows[0].subscriptionId | Should -Be 's1'
        $result.Rows[0].sku.name | Should -Be 'S1'
        $result.Rows[0].AZSCSource | Should -Be 'ArmResourceList'
        $result.Rows[0].properties | Should -BeNullOrEmpty
        @($result.Health).Count | Should -Be 0
        $known.Contains('/subscriptions/s1/resourceGroups/rg-a/providers/Microsoft.New/widgets/w1') | Should -BeTrue
    }

    It 'honours the resource-group and tag filters of the run' {
        function Invoke-RestMethod {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Offline stub.')]
            param([string] $Uri, [Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Uri, $Rest
            [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = '/subscriptions/s1/resourceGroups/keep/providers/Microsoft.New/widgets/a'; name = 'a'; type = 'Microsoft.New/widgets'; tags = [pscustomobject]@{ Env = 'Prod' } }
                    [pscustomobject]@{ id = '/subscriptions/s1/resourceGroups/keep/providers/Microsoft.New/widgets/b'; name = 'b'; type = 'Microsoft.New/widgets'; tags = [pscustomobject]@{ Env = 'Dev' } }
                    [pscustomobject]@{ id = '/subscriptions/s1/resourceGroups/other/providers/Microsoft.New/widgets/c'; name = 'c'; type = 'Microsoft.New/widgets'; tags = [pscustomobject]@{ Env = 'Prod' } }
                ) }
        }
        $result = Get-ScoutArmResourceCrossCheck -SubscriptionIds @('s1') -KnownIds (New-KnownIdSet) -ResourceGroups @('KEEP') -TagKey 'env' -TagValue 'prod'
        @($result.Rows | ForEach-Object name) | Should -Be @('a')
    }

    It 'retries a throttled list and reports a subscription that still fails as unavailable' {
        $script:calls = @{}
        function Invoke-RestMethod {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Offline stub.')]
            param([string] $Uri, [Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            $sub = if ($Uri -match '/subscriptions/([^/]+)/') { $Matches[1] } else { 'x' }
            $script:calls[$sub] = 1 + [int]$script:calls[$sub]
            if ($sub -eq 'flaky' -and $script:calls[$sub] -eq 1) {
                throw [System.Net.Http.HttpRequestException]::new('An error occurred while sending the request.', [System.IO.IOException]::new('Unable to read data from the transport connection: An existing connection was forcibly closed by the remote host.'))
            }
            if ($sub -eq 'broken') { throw 'AuthorizationFailed: no access' }
            [pscustomobject]@{ value = @([pscustomobject]@{ id = "/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.New/widgets/w"; name = 'w'; type = 'Microsoft.New/widgets' }) }
        }

        $result = Get-ScoutArmResourceCrossCheck -SubscriptionIds @('flaky', 'broken') -KnownIds (New-KnownIdSet)

        $script:calls['flaky'] | Should -Be 2
        $script:calls['broken'] | Should -Be 1
        @($result.Rows).Count | Should -Be 1
        @($result.Health).Count | Should -Be 1
        $result.Health[0].Status | Should -Be 'Unavailable'
        $result.Health[0].Dataset | Should -Match 'broken'
        @($result.Operations | Where-Object Status -eq 'Failed').Count | Should -Be 1
    }

    It 'reports the whole check as unavailable when no Resource Manager token can be had' {
        function Get-AzAccessToken { throw 'no context' }
        $result = Get-ScoutArmResourceCrossCheck -SubscriptionIds @('s1') -KnownIds (New-KnownIdSet)
        @($result.Rows).Count | Should -Be 0
        $result.Health[0].Status | Should -Be 'Unavailable'
        $result.Health[0].Reason | Should -Match 'access token'
    }
}
