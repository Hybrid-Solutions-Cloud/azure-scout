#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: the four Microsoft Well-Architected technology reviews added after the workload
    reviews -- Azure Machine Learning, Azure AI Search, Analytics and Data Services. Each rule set
    is run against small collect objects built here, so every automated rule's Pass and Fail is
    pinned, every gated rule is proven NotAssessed on an estate without its resources, no rule
    errors, and every rule id is enumerated in its docs/frameworks page.

    Microsoft does not publish these assessments' question text, so the docs are Scout's reading of
    the service guides; the tests pin Scout's own enumeration, not Microsoft's.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml

    function Invoke-ScoutTestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    function ConvertTo-ById {
        param($Findings)
        $map = @{}
        foreach ($f in $Findings) { $map[[string]$f.Id] = $f }
        $map
    }

    $script:P = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'
    function Get-TestPrivateEndpoint { param([string] $Target) [ordered]@{ targetResourceId = $Target; targetProvider = 'x'; targetType = 'y' } }
}

Describe 'Technology review rule files' {
    BeforeAll {
        $script:Reviews = @(
            @{ File = 'waf.machinelearning'; Framework = 'WAF-ML'; Doc = 'waf-machine-learning-checklist.md'; Rules = 44; Auto = 5 }
            @{ File = 'waf.aisearch'; Framework = 'WAF-AISEARCH'; Doc = 'waf-ai-search-checklist.md'; Rules = 37; Auto = 5 }
            @{ File = 'waf.analytics'; Framework = 'WAF-ANALYTICS'; Doc = 'waf-analytics-checklist.md'; Rules = 74; Auto = 8 }
            @{ File = 'waf.dataservices'; Framework = 'WAF-DATA'; Doc = 'waf-data-services-checklist.md'; Rules = 100; Auto = 22 }
        )
    }

    It '<File> loads <Rules> rules with unique ids, each citing its own id in title and remediation' -ForEach @(
        @{ File = 'waf.machinelearning'; Rules = 44 }
        @{ File = 'waf.aisearch'; Rules = 37 }
        @{ File = 'waf.analytics'; Rules = 74 }
        @{ File = 'waf.dataservices'; Rules = 100 }
    ) {
        $set = & $script:Module { param($f) Get-RuleSet -Patterns $f } $File
        @($set.Rules).Count | Should -Be $Rules
        @($set.Rules.id | Select-Object -Unique).Count | Should -Be $Rules
        foreach ($r in $set.Rules) {
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
        }
    }

    It '<File> declares framework <Framework>, a version and the number of automated rules <Auto>' -ForEach @(
        @{ File = 'waf.machinelearning'; Framework = 'WAF-ML'; Auto = 5 }
        @{ File = 'waf.aisearch'; Framework = 'WAF-AISEARCH'; Auto = 5 }
        @{ File = 'waf.analytics'; Framework = 'WAF-ANALYTICS'; Auto = 8 }
        @{ File = 'waf.dataservices'; Framework = 'WAF-DATA'; Auto = 22 }
    ) {
        $set = & $script:Module { param($f) Get-RuleSet -Patterns $f } $File
        $set.Framework | Should -Be $Framework
        $set.FrameworkVersion | Should -Not -BeNullOrEmpty
        @($set.Rules | Where-Object { -not $_.manual }).Count | Should -Be $Auto
        foreach ($r in $set.Rules) {
            if ($r.manual) { $r.assert.type | Should -Be 'manual' }
            else { $r.assert.gate | Should -Not -BeNullOrEmpty -Because "$($r.id) is automated and must be gated on its resources" }
        }
    }

    It 'every rule id is enumerated in its checklist doc' -ForEach @(
        @{ File = 'waf.machinelearning'; Doc = 'waf-machine-learning-checklist.md' }
        @{ File = 'waf.aisearch'; Doc = 'waf-ai-search-checklist.md' }
        @{ File = 'waf.analytics'; Doc = 'waf-analytics-checklist.md' }
        @{ File = 'waf.dataservices'; Doc = 'waf-data-services-checklist.md' }
    ) {
        $set = & $script:Module { param($f) Get-RuleSet -Patterns $f } $File
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        foreach ($r in $set.Rules) { $doc | Should -Match "\| $([regex]::Escape([string]$r.id)) \|" -Because "$($r.id) must be a row in $Doc" }
    }

    It 'every checklist doc states that Microsoft does not publish the question text' -ForEach @(
        @{ Doc = 'waf-machine-learning-checklist.md' }
        @{ Doc = 'waf-ai-search-checklist.md' }
        @{ Doc = 'waf-analytics-checklist.md' }
        @{ Doc = 'waf-data-services-checklist.md' }
    ) {
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        $doc | Should -Match 'question text not published'
        $doc | Should -Match '\*\*Enumerated \d{4}-\d{2}-\d{2}\.'
        $doc | Should -Match '\| Framework version \|'
        $doc | Should -Match '\| Extraction date \|'
        $doc | Should -Match '\| Verification method \|'
    }
}

Describe 'Technology review: Azure Machine Learning' {
    BeforeAll {
        $p = $script:P
        $bad = [ordered]@{
            domains    = [ordered]@{
                ai      = [ordered]@{ mlWorkspaces = @(
                        [ordered]@{ id = "$p/Microsoft.MachineLearningServices/workspaces/bad"; name = 'bad'; location = 'x'; workspaceKind = 'Default'; publicAccess = 'Enabled'; identityType = ''; isolationMode = 'Disabled' }
                        [ordered]@{ id = "$p/Microsoft.MachineLearningServices/workspaces/good"; name = 'good'; location = 'x'; workspaceKind = 'Default'; publicAccess = 'Disabled'; identityType = 'SystemAssigned'; isolationMode = 'AllowOnlyApprovedOutbound' }
                    ) }
                storage = [ordered]@{ storageAccounts = @() }
            }
            networking = [ordered]@{ privateEndpoints = @((Get-TestPrivateEndpoint "$p/Microsoft.MachineLearningServices/workspaces/good")) }
            governance = [ordered]@{ roleAssignments = @() }
            monitor    = [ordered]@{ appInsights = @(); autoscaleSettings = @() }
            finops     = [ordered]@{ reservations = @() }
            opsPosture = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $false }
        }
        $good = [ordered]@{
            domains    = [ordered]@{
                ai      = [ordered]@{ mlWorkspaces = @(
                        [ordered]@{ id = "$p/Microsoft.MachineLearningServices/workspaces/good"; name = 'good'; location = 'x'; workspaceKind = 'Default'; publicAccess = 'Disabled'; identityType = 'SystemAssigned'; isolationMode = 'AllowOnlyApprovedOutbound' }
                        [ordered]@{ id = "$p/Microsoft.MachineLearningServices/workspaces/proj"; name = 'proj'; location = 'x'; workspaceKind = 'Project'; publicAccess = 'Disabled'; identityType = 'SystemAssigned'; isolationMode = 'AllowOnlyApprovedOutbound' }
                    ) }
                storage = [ordered]@{ storageAccounts = @() }
            }
            networking = [ordered]@{ privateEndpoints = @((Get-TestPrivateEndpoint "$p/Microsoft.MachineLearningServices/workspaces/good")) }
            governance = [ordered]@{ roleAssignments = @() }
            monitor    = [ordered]@{ appInsights = @(); autoscaleSettings = @() }
            finops     = [ordered]@{ reservations = @() }
            opsPosture = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $false }
        }
        $script:MlBad = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.machinelearning' -Collect $bad -Assessment 'WAF: Azure Machine Learning')
        $script:MlGood = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.machinelearning' -Collect $good -Assessment 'WAF: Azure Machine Learning')
    }

    It 'produces no Error findings' {
        @($script:MlBad.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
        @($script:MlGood.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'scores <Id> as Fail on a non-compliant workspace and Pass on a compliant one' -ForEach @(
        @{ Id = 'WAF-ML-SE-02' }   # no managed network
        @{ Id = 'WAF-ML-SE-03' }   # public network access
        @{ Id = 'WAF-ML-SE-04' }   # no private endpoint (Project kind skipped on the good estate)
        @{ Id = 'WAF-ML-SE-05' }   # outbound not approved-only
        @{ Id = 'WAF-ML-SE-07' }   # no managed identity
    ) {
        $script:MlBad[$Id].Status | Should -Be 'Fail'
        $script:MlGood[$Id].Status | Should -Be 'Pass'
    }

    It 'names only the offending workspace in a failing join' {
        $script:MlBad['WAF-ML-SE-04'].EvidenceCount | Should -Be 1
    }

    It 'leaves the judgement items Manual with their evidence attached' {
        $script:MlBad['WAF-ML-RE-01'].Status | Should -Be 'Manual'
        $script:MlBad['WAF-ML-RE-01'].EvidenceCount | Should -Be 2
    }
}

Describe 'Technology review: Azure AI Search' {
    BeforeAll {
        $p = $script:P
        $mk = {
            param($Name, $Sku, $Replicas, $Public, $LocalAuthOff)
            [ordered]@{ id = "$p/Microsoft.Search/searchServices/$Name"; name = $Name; location = 'x'; sku = $Sku; publicAccess = $Public; disableLocalAuth = $LocalAuthOff; replicaCount = $Replicas }
        }
        $dom = {
            param($Services, $Pes)
            [ordered]@{
                domains    = [ordered]@{ ai = [ordered]@{ searchServices = @($Services) } }
                networking = [ordered]@{ privateEndpoints = @($Pes) }
                governance = [ordered]@{ resourceLocks = @(); budgets = @() }
                monitor    = [ordered]@{ activityLogAlertRules = @(); metricAlertRules = @() }
                opsPosture = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $false }
            }
        }
        $bad = & $dom @(
            (& $mk 'free' 'free' 1 'enabled' $false)
            (& $mk 'basic1' 'basic' 1 'Enabled' $false)
            (& $mk 'good' 'standard' 3 'Disabled' $true)
        ) @((Get-TestPrivateEndpoint "$p/Microsoft.Search/searchServices/good"))
        $good = & $dom @(
            (& $mk 'good' 'standard' 3 'Disabled' $true)
            (& $mk 'serverless' 'serverless' $null 'Disabled' $true)
        ) @((Get-TestPrivateEndpoint "$p/Microsoft.Search/searchServices/good"), (Get-TestPrivateEndpoint "$p/Microsoft.Search/searchServices/serverless"))
        $script:SrBad = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.aisearch' -Collect $bad -Assessment 'WAF: Azure AI Search')
        $script:SrGood = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.aisearch' -Collect $good -Assessment 'WAF: Azure AI Search')
    }

    It 'produces no Error findings' {
        @($script:SrBad.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
        @($script:SrGood.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'scores <Id> as Fail with <Count> offenders on the bad estate and Pass on the good one' -ForEach @(
        @{ Id = 'WAF-AISEARCH-RE-01'; Count = 1 }   # the free tier
        @{ Id = 'WAF-AISEARCH-RE-02'; Count = 1 }   # basic with one replica; free is flagged by RE-01, serverless skipped
        @{ Id = 'WAF-AISEARCH-SE-01'; Count = 2 }
        @{ Id = 'WAF-AISEARCH-SE-02'; Count = 2 }
        @{ Id = 'WAF-AISEARCH-SE-03'; Count = 2 }
    ) {
        $script:SrBad[$Id].Status | Should -Be 'Fail'
        $script:SrBad[$Id].EvidenceCount | Should -Be $Count
        $script:SrGood[$Id].Status | Should -Be 'Pass'
    }
}

Describe 'Technology review: Analytics' {
    BeforeAll {
        $p = $script:P
        $mk = {
            param($Eh, $Dbx, $La, $Fab, $Cov)
            [ordered]@{
                domains       = [ordered]@{
                    integration = [ordered]@{ eventHubNamespaces = @($Eh) }
                    analytics   = [ordered]@{ databricksWorkspaces = @($Dbx); fabricCapacities = @($Fab) }
                    security    = [ordered]@{ sentinelWorkspaces = @() }
                }
                management    = [ordered]@{ logAnalyticsWorkspaces = @($La) }
                networking    = [ordered]@{ privateEndpoints = @((Get-TestPrivateEndpoint "$p/Microsoft.Databricks/workspaces/dbx-good")) }
                monitor       = [ordered]@{ metricAlertRules = @(); dataCollectionRules = @(); dataCollectionEndpoints = @(); scheduledQueryRules = @(); privateLinkScopes = @(); workbooks = @() }
                governance    = [ordered]@{ budgets = @(); resourceLocks = @() }
                finops        = [ordered]@{ reservations = @() }
                opsPosture    = [ordered]@{ diagnosticCoverage = @($Cov); diagnosticCoverageMeasured = $true }
            }
        }
        $bad = & $mk @(
            [ordered]@{ name = 'eh-bad'; zoneRedundant = $false; publicAccess = 'Enabled'; autoInflateEnabled = $false }
        ) @(
            [ordered]@{ id = "$p/Microsoft.Databricks/workspaces/dbx-bad"; name = 'dbx-bad'; sku = 'trial' }
        ) @(
            [ordered]@{ name = 'la-bad'; retentionInDays = 7 }
        ) @(
            [ordered]@{ id = 'f1'; name = 'f1'; sku = 'F2'; state = 'Failed' }
        ) @(
            [ordered]@{ type = 'microsoft.eventhub/namespaces'; total = 2; withDiag = 1; coveragePct = 50 }
            [ordered]@{ type = 'microsoft.operationalinsights/workspaces'; total = 1; withDiag = 0; coveragePct = 0 }
        )
        $good = & $mk @(
            [ordered]@{ name = 'eh-good'; zoneRedundant = $true; publicAccess = 'Disabled'; autoInflateEnabled = $true }
        ) @(
            [ordered]@{ id = "$p/Microsoft.Databricks/workspaces/dbx-good"; name = 'dbx-good'; sku = 'premium' }
        ) @(
            [ordered]@{ name = 'la-good'; retentionInDays = 90 }
        ) @(
            [ordered]@{ id = 'f1'; name = 'f1'; sku = 'F2'; state = 'Paused' }
        ) @(
            [ordered]@{ type = 'microsoft.eventhub/namespaces'; total = 2; withDiag = 2; coveragePct = 100 }
            [ordered]@{ type = 'microsoft.operationalinsights/workspaces'; total = 1; withDiag = 1; coveragePct = 100 }
        )
        $script:AnBad = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.analytics' -Collect $bad -Assessment 'WAF: Analytics')
        $script:AnGood = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.analytics' -Collect $good -Assessment 'WAF: Analytics')
    }

    It 'produces no Error findings' {
        @($script:AnBad.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
        @($script:AnGood.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'scores <Id> as Fail on the bad estate and Pass on the good one' -ForEach @(
        @{ Id = 'WAF-ANALYTICS-RE-06' }   # Event Hubs not zone redundant
        @{ Id = 'WAF-ANALYTICS-RE-13' }   # retention under 30 days
        @{ Id = 'WAF-ANALYTICS-RE-16' }   # Fabric capacity Failed; Paused is not a failure
        @{ Id = 'WAF-ANALYTICS-SE-02' }   # Databricks without a private endpoint
        @{ Id = 'WAF-ANALYTICS-SE-10' }   # Event Hubs public
        @{ Id = 'WAF-ANALYTICS-SE-14' }   # Event Hubs diagnostics at 50 percent
        @{ Id = 'WAF-ANALYTICS-SE-19' }   # workspace diagnostics at 0 percent
        @{ Id = 'WAF-ANALYTICS-CO-04' }   # trial Databricks
    ) {
        $script:AnBad[$Id].Status | Should -Be 'Fail'
        $script:AnGood[$Id].Status | Should -Be 'Pass'
    }
}

Describe 'Technology review: Data Services' {
    BeforeAll {
        $p = $script:P
        $mk = {
            param([bool] $Compliant)
            $pe = @()
            $id = { param($t) "$p/$t" }
            $cos = [ordered]@{ id = (& $id 'Microsoft.DocumentDB/databaseAccounts/cos'); name = 'cos'; kind = 'GlobalDocumentDB'; publicNetworkAccess = $(if ($Compliant) { 'Disabled' } else { 'Enabled' }); disableLocalAuth = $Compliant }
            $red = [ordered]@{ id = (& $id 'Microsoft.Cache/redisEnterprise/red'); name = 'red'; type = 'microsoft.cache/redisenterprise'; sku = 'Balanced_B5'; publicNetworkAccess = $(if ($Compliant) { 'Disabled' } else { 'Enabled' }) }
            $sto = [ordered]@{ id = (& $id 'Microsoft.Storage/storageAccounts/sto'); name = 'sto'; sku = $(if ($Compliant) { 'Standard_ZRS' } else { 'Standard_LRS' }); publicAccess = (-not $Compliant); httpsOnly = $Compliant; minTls = $(if ($Compliant) { 'TLS1_2' } else { 'TLS1_0' }); networkDefaultDeny = $Compliant }
            if ($Compliant) { $pe = @((Get-TestPrivateEndpoint $cos.id), (Get-TestPrivateEndpoint $red.id), (Get-TestPrivateEndpoint $sto.id)) }
            $cov = $(if ($Compliant) { 100 } else { 0 })
            [ordered]@{
                domains    = [ordered]@{
                    databases = [ordered]@{
                        sqlDatabases              = @(
                            [ordered]@{ name = 'db1'; resourceGroup = 'rg'; zoneRedundant = $Compliant; tier = 'GeneralPurpose' }
                            [ordered]@{ name = 'master'; resourceGroup = 'rg'; zoneRedundant = $false; tier = 'System' }
                        )
                        sqlServers                = @([ordered]@{ name = 'srv'; resourceGroup = 'rg'; publicNetworkAccess = $(if ($Compliant) { 'Disabled' } else { 'Enabled' }) })
                        sqlDefenderPricing        = @([ordered]@{ subscriptionId = 's'; name = 'sqlservers'; pricingTier = $(if ($Compliant) { 'Standard' } else { 'Free' }) })
                        sqlManagedInstances       = @([ordered]@{ id = (& $id 'Microsoft.Sql/managedInstances/mi'); name = 'mi'; sku = 'GP_Gen5'; publicDataEndpointEnabled = (-not $Compliant); vCores = 4 })
                        sqlElasticPools           = @()
                        cosmosDbAccounts          = @($cos)
                        postgreSqlFlexibleServers = @([ordered]@{ id = (& $id 'Microsoft.DBforPostgreSQL/flexibleServers/pg'); name = 'pg'; sku = 'Standard_D2s_v3'; version = '16'; publicNetworkAccess = $(if ($Compliant) { 'Disabled' } else { 'Enabled' }) })
                        mySqlFlexibleServers      = @([ordered]@{ id = (& $id 'Microsoft.DBforMySQL/flexibleServers/my'); name = 'my'; sku = 'Standard_D2ds_v4'; version = '8.0'; publicNetworkAccess = $(if ($Compliant) { 'Disabled' } else { 'Enabled' }) })
                        redisCaches               = @($red)
                    }
                    storage   = [ordered]@{ storageAccounts = @($sto) }
                    security  = [ordered]@{ keyVaults = @() }
                }
                networking = [ordered]@{ privateEndpoints = @($pe) }
                security   = [ordered]@{ defenderPlans = @() }
                governance = [ordered]@{ resourceLocks = @() }
                monitor    = [ordered]@{ metricAlertRules = @(); activityLogAlertRules = @() }
                management = [ordered]@{ backupProtectedItems = @(); maintenanceConfigurations = @() }
                finops     = [ordered]@{ reservations = @() }
                opsPosture = [ordered]@{
                    diagnosticCoverageMeasured = $true
                    diagnosticCoverage         = @(
                        foreach ($t in 'microsoft.sql/servers/databases', 'microsoft.documentdb/databaseaccounts', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.storage/storageaccounts') {
                            [ordered]@{ type = $t; total = 1; withDiag = [int]($cov / 100); coveragePct = $cov }
                        }
                    )
                }
            }
        }
        $script:DtBad = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.dataservices' -Collect (& $mk $false) -Assessment 'WAF: Data Services')
        $script:DtGood = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern 'waf.dataservices' -Collect (& $mk $true) -Assessment 'WAF: Data Services')
    }

    It 'produces no Error findings' {
        @($script:DtBad.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
        @($script:DtGood.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'scores <Id> as Fail on the bad estate and Pass on the good one' -ForEach @(
        @{ Id = 'WAF-DATA-SQL-01' }    # master is excluded; db1 is the only offender on the bad estate
        @{ Id = 'WAF-DATA-SQL-06' }
        @{ Id = 'WAF-DATA-SQL-10' }
        @{ Id = 'WAF-DATA-SQL-15' }
        @{ Id = 'WAF-DATA-MI-03' }
        @{ Id = 'WAF-DATA-COS-05' }
        @{ Id = 'WAF-DATA-COS-06' }
        @{ Id = 'WAF-DATA-COS-07' }
        @{ Id = 'WAF-DATA-COS-10' }
        @{ Id = 'WAF-DATA-PG-03' }
        @{ Id = 'WAF-DATA-PG-08' }
        @{ Id = 'WAF-DATA-MYS-03' }
        @{ Id = 'WAF-DATA-MYS-06' }
        @{ Id = 'WAF-DATA-RED-04' }
        @{ Id = 'WAF-DATA-RED-05' }
        @{ Id = 'WAF-DATA-BLOB-01' }
        @{ Id = 'WAF-DATA-BLOB-02' }
        @{ Id = 'WAF-DATA-BLOB-03' }
        @{ Id = 'WAF-DATA-BLOB-04' }
        @{ Id = 'WAF-DATA-BLOB-05' }
        @{ Id = 'WAF-DATA-BLOB-09' }
        @{ Id = 'WAF-DATA-BLOB-12' }
    ) {
        $script:DtBad[$Id].Status | Should -Be 'Fail'
        $script:DtGood[$Id].Status | Should -Be 'Pass'
    }

    It 'excludes the master database from the zone-redundancy rule' {
        $script:DtBad['WAF-DATA-SQL-01'].EvidenceCount | Should -Be 1
    }

    It 'keeps Azure HorizonDB items Manual because no HorizonDB dataset is collected' {
        foreach ($id in $script:DtBad.Keys | Where-Object { $_ -like 'WAF-DATA-HZ-*' }) { $script:DtBad[$id].Status | Should -Be 'Manual' }
        @($script:DtBad.Keys | Where-Object { $_ -like 'WAF-DATA-HZ-*' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Technology reviews on an estate with none of the resources' {
    BeforeAll {
        $empty = [ordered]@{
            domains    = [ordered]@{
                ai          = [ordered]@{ cognitiveAccounts = @(); mlWorkspaces = @(); searchServices = @() }
                analytics   = [ordered]@{ databricksWorkspaces = @(); fabricCapacities = @(); synapseWorkspaces = @() }
                integration = [ordered]@{ eventHubNamespaces = @() }
                databases   = [ordered]@{ sqlDatabases = @(); sqlServers = @(); sqlDefenderPricing = @(); sqlManagedInstances = @(); sqlElasticPools = @(); cosmosDbAccounts = @(); postgreSqlFlexibleServers = @(); mySqlFlexibleServers = @(); redisCaches = @() }
                storage     = [ordered]@{ storageAccounts = @() }
                security    = [ordered]@{ keyVaults = @(); sentinelWorkspaces = @() }
            }
            management = [ordered]@{ logAnalyticsWorkspaces = @(); backupProtectedItems = @(); maintenanceConfigurations = @() }
            networking = [ordered]@{ privateEndpoints = @() }
            opsPosture = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $true }
        }
        $script:Empty = @{}
        foreach ($f in 'waf.machinelearning', 'waf.aisearch', 'waf.analytics', 'waf.dataservices') {
            $script:Empty[$f] = @(Invoke-ScoutTestRuleSet -Pattern $f -Collect $empty -Assessment "Empty $f")
        }
    }

    It '<File> reports every automated rule NotAssessed and never Pass, Fail or Error' -ForEach @(
        @{ File = 'waf.machinelearning'; Auto = 5 }
        @{ File = 'waf.aisearch'; Auto = 5 }
        @{ File = 'waf.analytics'; Auto = 8 }
        @{ File = 'waf.dataservices'; Auto = 22 }
    ) {
        $findings = $script:Empty[$File]
        @($findings | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Error' }).Count | Should -Be 0
        @($findings | Where-Object Status -eq 'NotAssessed').Count | Should -Be $Auto
    }

    It '<File> returns every other rule as Manual' -ForEach @(
        @{ File = 'waf.machinelearning'; Manual = 39 }
        @{ File = 'waf.aisearch'; Manual = 32 }
        @{ File = 'waf.analytics'; Manual = 66 }
        @{ File = 'waf.dataservices'; Manual = 78 }
    ) {
        @($script:Empty[$File] | Where-Object Status -eq 'Manual').Count | Should -Be $Manual
    }
}
