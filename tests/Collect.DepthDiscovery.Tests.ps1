#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#9300, 3.18.20 -- the depth datasets are DISCOVERABLE and reach collect.json.

    "Everything deployable must be discoverable." The discovery index (New-ScoutResourceDiscovery) treats an `AZSC/*` row as
    enrichment of a base resource with the same id and never lists it alone, which is right for a diagnostic setting and wrong for
    an origin group or a firewall rule: they are deployable ARM sub-resources with no Resource Graph row. ConvertTo-
    ScoutChildDiscoveryResource mirrors each under its real ARM type. This file holds:

      1. THE RULE: exactly the allow-listed, bounded sub-resource datasets are mirrored -- the 13 Azure VMware Solution ones, the 8
         batch-2 ones and the 26 depth ones -- and the record and user-data datasets are not (diagnostic settings, Log Analytics
         tables and saved searches, blob containers, file shares, queues and tables, the ML datasets, reservation utilisation ...).
      2. REAL TYPES: every mirrored type is one Azure's provider catalogue lists, except a short named list of children the
         catalogue omits (API Management's, SQL firewall rules, App Service config).
      3. THE INDEX: with the twins the index lists every sub-resource under its provider's category; without them it lists none.
      4. THE WIRING: Get-ScoutRawInventory runs the transform after the sweep and maps each dataset's health to its parent type.
      5. COLLECT.JSON: the assessment collect asks for the depth datasets, places each under its domain with its Measured flag, never
         carries a planted secret, reads every flag false when every GET is denied, and declares the same keys on the typed-query path.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/pipeline/Get-ScoutResourceCompleteness.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthChildHarness.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthFamilyCases.ps1')
    $script:Families = @(Get-DepthFamilyCase)
    $script:AllParents = @($script:Families | ForEach-Object { $_.Parents } | Sort-Object id -Unique)
    $script:AllRoutes = @{}
    foreach ($family in $script:Families) { foreach ($key in $family.Routes.Keys) { $script:AllRoutes[$key] = $family.Routes[$key] } }
    $script:DepthDatasets = @($script:Families | ForEach-Object { $_.Datasets })
    $script:AllSentinels = @($script:Families | ForEach-Object { $_.Sentinels } | Sort-Object -Unique)
    $script:MirrorSource = Get-Content (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1') -Raw
    $script:MirroredDatasets = @([regex]::Matches($script:MirrorSource, "'azsc/armchild/([a-z0-9]+)'\s*=") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

AfterAll { Remove-DepthStub }

Describe 'The discovery rule: which sub-resource datasets are mirrored under their real ARM type' {

    It 'mirrors exactly the 13 AVS, 8 batch-2 and 26 depth datasets, whose rows are allow-listed and bounded' {
        $expected = @(
            'AvsClusters', 'AvsDatastores', 'AvsPlacementPolicies', 'AvsAddons', 'AvsGlobalReachConnections', 'AvsAuthorizations', 'AvsCloudLinks',
            'AvsSegments', 'AvsDhcpConfigurations', 'AvsDnsServices', 'AvsGateways', 'AvsIscsiPaths', 'AvsMaintenances',
            'StorageBlobServiceProperties', 'StorageFileServiceProperties', 'SqlServerAuditing', 'SqlFailoverGroups', 'WebAppConfig',
            'WebAppBasicAuth', 'EventHubGeoDr', 'RedisEnterpriseDatabases'
        ) + $script:DepthDatasets
        $expected.Count | Should -Be 47
        $script:MirroredDatasets | Should -Be @($expected | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
    }

    It 'does not mirror a record or user-data dataset, or one that keeps a whole response' {
        foreach ($dataset in 'ResourceDiagnosticSettings', 'StorageLifecyclePolicies', 'LAWorkspaceTables', 'LAWorkspaceSavedSearches', 'SentinelDataConnectors',
            'SentinelIngestion', 'StorageBlobContainers', 'StorageFileShares', 'StorageQueues', 'StorageTables', 'MLComputes', 'MLDatasets', 'MLDatastores',
            'MLEndpoints', 'MLModels', 'MLPipelines', 'OpenAIDeployments', 'ReservationUtilization', 'BackupInstances', 'AVDApplications',
            'AppInsightsProactiveDetection', 'AzureLocalVirtualMachineInstances') {
            $script:MirroredDatasets | Should -Not -Contain $dataset.ToLowerInvariant() -Because "$dataset is not a bounded, allow-listed sub-resource dataset"
        }
        $other = [pscustomobject]@{ id = '/x/y'; name = 'y'; type = 'AZSC/ARMChild/StorageBlobContainers'; properties = [pscustomobject]@{} }
        @(ConvertTo-ScoutChildDiscoveryResource -Resources @($other)).Count | Should -Be 0
        @(ConvertTo-ScoutChildDiscoveryResource -Resources @()).Count | Should -Be 0
    }

    It 'maps every dataset to a real ARM type that the provider catalogue lists, bar the children it is known to omit' {
        $catalogue = @((Get-Content (Join-Path -Path $script:Root -ChildPath 'manifests/azure-provider-types.json') -Raw | ConvertFrom-Json).Types)
        $omitted = @(
            'microsoft.apimanagement/service/apis', 'microsoft.apimanagement/service/namedvalues', 'microsoft.apimanagement/service/policies',
            'microsoft.sql/servers/firewallrules', 'microsoft.web/sites/basicpublishingcredentialspolicies', 'microsoft.web/sites/config'
        )
        $types = @([regex]::Matches($script:MirrorSource, "=\s*'(microsoft\.[a-z0-9./]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $types.Count | Should -BeGreaterThan 40
        foreach ($type in $types) {
            if ($type -in $omitted) { continue }
            $catalogue | Should -Contain $type -Because "$type is a type Azure's provider catalogue lists"
        }
    }
}

Describe 'Every swept sub-resource is listed in the discovery index' {

    BeforeAll {
        Install-DepthStub -Routes $script:AllRoutes
        $script:Sweep = Invoke-DepthSweep -Resources $script:AllParents -Dataset $script:DepthDatasets
        $script:Twins = @(ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows))
    }

    It 'gives each swept row one twin with the real type, the parent''s location, group and subscription, and the same properties' {
        @($script:Sweep.Rows).Count | Should -BeGreaterThan 30
        $script:Twins.Count | Should -Be @($script:Sweep.Rows).Count
        foreach ($twin in $script:Twins) {
            $twin.AZSCDiscoveryTwin | Should -BeTrue
            $twin.type | Should -Match '^microsoft\.[a-z]+/'
            $twin.type | Should -Not -Match '^azsc/'
            $twin.location | Should -Be 'eastus'
            $twin.resourceGroup | Should -Be 'rg1'
            $twin.subscriptionId | Should -Be 'sub1'
        }
    }

    It 'lists every sub-resource in the index only when the twins are present, with the AZSC row attached as enrichment' {
        $without = New-ScoutResourceDiscovery -Resources (@($script:AllParents) + @($script:Sweep.Rows))
        $with = New-ScoutResourceDiscovery -Resources (@($script:AllParents) + @($script:Sweep.Rows) + @($script:Twins))
        $with.Resources.Count | Should -Be ($without.Resources.Count + $script:Twins.Count)
        $listedChildren = @($with.Resources | Where-Object { @($_.Enrichment).Count -ge 1 })
        $listedChildren.Count | Should -Be $script:Twins.Count -Because 'the AZSC row attaches to its twin'
        $with.Summary.Uncategorized | Should -Be 0 -Because 'every provider namespace has a category'
    }

    It 'carries no planted secret from any family into the discovery index' {
        $discovery = New-ScoutResourceDiscovery -Resources (@($script:AllParents) + @($script:Sweep.Rows) + @($script:Twins))
        $json = $discovery | ConvertTo-Json -Depth 14
        $json | Should -Match 'og1' -Because 'the positive control'
        foreach ($sentinel in $script:AllSentinels) { $json | Should -Not -Match ([regex]::Escape($sentinel)) -Because $sentinel }
    }

    It 'is wired into the raw inventory after the sweep, and every depth dataset maps its health to its parent type' {
        $raw = Get-Content (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutRawInventory.ps1') -Raw
        $raw | Should -Match "Import-ScoutRawInventoryHelper -CommandName 'ConvertTo-ScoutChildDiscoveryResource' -FileName 'ConvertTo-ScoutChildDiscoveryResource.ps1'"
        $raw.IndexOf('ConvertTo-ScoutChildDiscoveryResource -Resources') | Should -BeGreaterThan $raw.IndexOf('Get-ScoutArmChildResource -Resources')
        $plan = Get-Content (Join-Path -Path $script:Root -ChildPath 'src/Start-AZTIExtractionOrchestration.ps1') -Raw
        foreach ($dataset in $script:DepthDatasets) {
            $raw | Should -Match ("'azsc/armchild/{0}' = @\('microsoft\.[a-z/]+'\)" -f $dataset.ToLowerInvariant()) -Because "$dataset's health must map to its parent type"
            $plan | Should -Match "'$dataset'" -Because "$dataset is a supported ARM-child dataset"
        }
    }
}

Describe 'Invoke-Collect -- the depth datasets in collect.json' {

    BeforeAll {
        function Import-Module {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet so Invoke-Collect does not import Az modules during the test.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must accept whatever arguments the code under test passes.')]
            param([Parameter(ValueFromRemainingArguments)] $Rest)
        }
        function Get-ScoutDefenderPlanSweep {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
            param([object[]] $Subscriptions)
            return @()
        }
        function Get-ScoutExternalIdentitiesPolicy {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
            param([string] $TenantID)
            return [pscustomobject]@{ Collected = $false }
        }
        function Search-AzGraph {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            return @()
        }
        . (Join-Path -Path $script:Root -ChildPath 'src/collect/Invoke-Collect.ps1')

        # The raw pass is stubbed, but the ARM-child collector inside it is the real one.
        function global:Get-ScoutRawInventory {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature; only the ARM-child parameters are used.')]
            param([switch] $IncludeArmChildResources, [string[]] $ArmChildDataset, [Parameter(ValueFromRemainingArguments)] $Rest)
            $script:CapturedArmChildDataset = $ArmChildDataset
            $health = [System.Collections.Generic.List[object]]::new()
            $operations = [System.Collections.Generic.List[object]]::new()
            $children = @(Get-ScoutArmChildResource -Resources $script:RawParents -Dataset $ArmChildDataset `
                    -CollectionHealth $health -SourceOperations $operations -WarningAction SilentlyContinue)
            [pscustomobject]@{ Resources = @($script:RawParents) + $children; ResourceContainers = @(); SourceOperations = @($operations); CollectionHealth = @($health) }
        }
    }

    AfterAll { Remove-Item -Path 'Function:\Get-ScoutRawInventory' -Force -ErrorAction SilentlyContinue }

    Context 'every GET answered' {
        BeforeAll {
            $script:RawParents = @($script:AllParents)
            Install-DepthStub -Routes $script:AllRoutes
            $script:Collect = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
            $script:CollectJson = $script:Collect | ConvertTo-Json -Depth 20
        }

        It 'asks the assessment collect for all 26 depth datasets' {
            foreach ($dataset in $script:DepthDatasets) { @($script:CapturedArmChildDataset) | Should -Contain $dataset }
        }

        It 'places each dataset under its domain with a Measured flag that is true' {
            $placement = @{
                afd         = 'originGroups', 'origins', 'endpoints', 'routes', 'customDomains', 'securityPolicies'
                databases   = 'sqlBackupShortTerm', 'sqlBackupLongTerm', 'sqlTde', 'sqlFirewallRules', 'sqlEncryptionProtector', 'sqlSecurityAlertPolicies'
                hybrid      = 'azureLocalUpdateSummaries', 'azureLocalSecuritySettings', 'azureLocalArcSettings'
                integration = 'eventHubNetworkRuleSets', 'eventHubAuthorization', 'eventHubEntities', 'serviceBusNetworkRuleSets', 'serviceBusAuthorization', 'serviceBusQueues', 'serviceBusTopics', 'apimGlobalPolicy', 'apimApis', 'apimNamedValues'
                web         = 'webAppAuth'
            }
            foreach ($domain in $placement.Keys) {
                foreach ($key in $placement[$domain]) {
                    $script:Collect.domains.$domain.PSObject.Properties.Name | Should -Contain $key -Because "domains.$domain.$key"
                    $script:Collect.domains.$domain.PSObject.Properties.Name | Should -Contain "${key}Measured"
                    $script:Collect.domains.$domain."${key}Measured" | Should -BeTrue -Because "domains.$domain.$key"
                    @($script:Collect.domains.$domain.$key).Count | Should -BeGreaterThan 0 -Because "domains.$domain.$key"
                }
            }
            @($script:Collect.domains.afd.originGroups | Where-Object hasRedundantOrigins -eq $false).Count | Should -Be 1
            @($script:Collect.domains.databases.sqlTde | Where-Object enabled -eq $false).Count | Should -Be 1
        }

        It 'carries no planted secret, address or identifier anywhere in the serialised collect' {
            $script:CollectJson | Should -Match 'og1' -Because 'the positive control'
            foreach ($sentinel in $script:AllSentinels) { $script:CollectJson | Should -Not -Match ([regex]::Escape($sentinel)) -Because $sentinel }
        }
    }

    Context 'every GET denied' {
        BeforeAll {
            $script:RawParents = @($script:AllParents)
            Install-DepthStub -Routes $script:AllRoutes -Override { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' } }
            $script:Denied = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'leaves every depth dataset empty and every Measured flag false, so a rule reports NotAssessed' {
            foreach ($family in $script:Families) {
                foreach ($key in $family.Keys) {
                    $domain = if ($key -like 'afd*') { 'afd' } elseif ($key -like 'sql*') { 'databases' } elseif ($key -like 'azureLocal*') { 'hybrid' } elseif ($key -eq 'webAppAuth') { 'web' } else { 'integration' }
                    $name = if ($domain -eq 'afd') { $key.Substring(3, 1).ToLowerInvariant() + $key.Substring(4) } else { $key }
                    @($script:Denied.domains.$domain.$name).Count | Should -Be 0 -Because $key
                    $script:Denied.domains.$domain."${name}Measured" | Should -BeFalse -Because $key
                }
            }
        }
    }

    Context 'no parent of any depth type in the estate' {
        BeforeAll {
            $script:RawParents = @($script:Families[0].Unrelated)
            Install-DepthStub -Routes $script:AllRoutes
            $script:Quiet = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'asks nothing about any depth dataset and declares the section empty and unmeasured' {
            @($script:StubCalls | Where-Object { $_ -match '(?i)Microsoft\.(Cdn|Sql|AzureStackHCI|EventHub|ServiceBus|ApiManagement)|/sites/' }).Count | Should -Be 0
            $script:Quiet.domains.afd.originGroupsMeasured | Should -BeFalse
            $script:Quiet.domains.databases.sqlTdeMeasured | Should -BeFalse
            @($script:Quiet.domains.integration.apimNamedValues).Count | Should -Be 0
        }
    }

    Context 'the typed-query path (no ARM-child sweep)' {
        BeforeAll {
            Remove-Item -Path 'Function:\Get-ScoutRawInventory' -Force -ErrorAction SilentlyContinue
            $script:Typed = Invoke-Collect -Source TypedQueries -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'declares the same domains.afd keys as the inventory path, empty and unmeasured' {
            $script:Typed.domains.afd.PSObject.Properties.Name | Should -Be $script:Collect.domains.afd.PSObject.Properties.Name
            foreach ($property in $script:Typed.domains.afd.PSObject.Properties) {
                if ($property.Name -like '*Measured') { $property.Value | Should -BeFalse -Because $property.Name } else { @($property.Value).Count | Should -Be 0 -Because $property.Name }
            }
            $script:Typed.domains.databases.sqlFirewallRulesMeasured | Should -BeFalse
            $script:Typed.domains.hybrid.azureLocalSecuritySettingsMeasured | Should -BeFalse
            $script:Typed.domains.integration.serviceBusQueuesMeasured | Should -BeFalse
            $script:Typed.domains.web.webAppAuthMeasured | Should -BeFalse
        }
    }
}
