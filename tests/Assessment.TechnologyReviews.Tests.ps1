#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: the four Microsoft Well-Architected technology reviews added after the workload
    reviews -- Azure Machine Learning, Azure AI Search, Analytics and Data Services. Each rule set
    is run against small collect objects built here, so every automated rule's Pass and Fail is
    pinned (with exact evidence counts), every gated rule is proven NotAssessed on an estate
    without its resources, no rule errors, and every rule id is enumerated in its docs/frameworks
    page.

    Phase 4 projected many more settings (TLS, Entra-only and local authentication, backup
    redundancy, regions, high availability, key source), which converted most of the manual
    items. Several of those are "absent means bad": a projected string is '' and a projected
    boolean or count is null when ARM does not return it, Newtonsoft JSONPath never matches a
    MISSING property with == or != but does match null and '' with !=, so the edge-case table at
    the end pins each of those with an explicit null and '' row.

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

    # A collect object holding ONE dataset at a dotted path (for example domains.storage.storageAccounts).
    # Every other section is absent, so gated rules on other datasets are NotAssessed and manual rules
    # report no evidence -- nothing else can interfere with the rule under test.
    function Get-TestCollectAt {
        param([string] $Path, $Rows)
        $root = [ordered]@{}
        $cursor = $root
        $segments = @($Path -split '\.')
        for ($i = 0; $i -lt $segments.Count - 1; $i++) {
            $cursor[$segments[$i]] = [ordered]@{}
            $cursor = $cursor[$segments[$i]]
        }
        $cursor[$segments[-1]] = @($Rows)
        $root
    }
}

Describe 'Technology review rule files' {
    BeforeAll {
        $script:Reviews = @(
            @{ File = 'waf.machinelearning'; Framework = 'WAF-ML'; Doc = 'waf-machine-learning-checklist.md'; Rules = 44; Auto = 6 }
            @{ File = 'waf.aisearch'; Framework = 'WAF-AISEARCH'; Doc = 'waf-ai-search-checklist.md'; Rules = 37; Auto = 8 }
            @{ File = 'waf.analytics'; Framework = 'WAF-ANALYTICS'; Doc = 'waf-analytics-checklist.md'; Rules = 74; Auto = 19 }
            @{ File = 'waf.dataservices'; Framework = 'WAF-DATA'; Doc = 'waf-data-services-checklist.md'; Rules = 104; Auto = 51 }
        )
    }

    It '<File> loads <Rules> rules with unique ids, each citing its own id in title and remediation' -ForEach @(
        @{ File = 'waf.machinelearning'; Rules = 44 }
        @{ File = 'waf.aisearch'; Rules = 37 }
        @{ File = 'waf.analytics'; Rules = 74 }
        @{ File = 'waf.dataservices'; Rules = 104 }
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
        @{ File = 'waf.machinelearning'; Framework = 'WAF-ML'; Auto = 6 }
        @{ File = 'waf.aisearch'; Framework = 'WAF-AISEARCH'; Auto = 8 }
        @{ File = 'waf.analytics'; Framework = 'WAF-ANALYTICS'; Auto = 19 }
        @{ File = 'waf.dataservices'; Framework = 'WAF-DATA'; Auto = 51 }
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

    It '<File> states its item count (<Rules>) in the framework version' -ForEach @(
        @{ File = 'waf.machinelearning'; Rules = 44 }
        @{ File = 'waf.aisearch'; Rules = 37 }
        @{ File = 'waf.analytics'; Rules = 74 }
        @{ File = 'waf.dataservices'; Rules = 104 }
    ) {
        $set = & $script:Module { param($f) Get-RuleSet -Patterns $f } $File
        $set.FrameworkVersion | Should -Match "\($Rules items\)"
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

    It '<Doc> marks automated rows with a tick and manual rows with a cross, matching the rule file (<File>)' -ForEach @(
        @{ File = 'waf.machinelearning'; Doc = 'waf-machine-learning-checklist.md' }
        @{ File = 'waf.aisearch'; Doc = 'waf-ai-search-checklist.md' }
        @{ File = 'waf.analytics'; Doc = 'waf-analytics-checklist.md' }
        @{ File = 'waf.dataservices'; Doc = 'waf-data-services-checklist.md' }
    ) {
        $set = & $script:Module { param($f) Get-RuleSet -Patterns $f } $File
        $lines = @(Get-Content "$script:root/docs/frameworks/$Doc")
        foreach ($r in $set.Rules) {
            $row = @($lines | Where-Object { $_ -match "^\| $([regex]::Escape([string]$r.id)) \|" })
            $row.Count | Should -Be 1 -Because "$($r.id) must be one row in $Doc"
            if ($r.manual) { $row[0] | Should -Match ("\| " + [char]0x274C + " ") -Because "$($r.id) is manual" }
            else { $row[0] | Should -Match ("\| " + [char]0x2705 + " ") -Because "$($r.id) is automated" }
        }
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

    It '<Doc> summary table states the same totals as the rule file (<File>)' -ForEach @(
        @{ File = 'waf.machinelearning'; Doc = 'waf-machine-learning-checklist.md' }
        @{ File = 'waf.aisearch'; Doc = 'waf-ai-search-checklist.md' }
        @{ File = 'waf.analytics'; Doc = 'waf-analytics-checklist.md' }
        @{ File = 'waf.dataservices'; Doc = 'waf-data-services-checklist.md' }
    ) {
        $set = & $script:Module { param($f) Get-RuleSet -Patterns $f } $File
        $total = @($set.Rules).Count
        $auto = @($set.Rules | Where-Object { -not $_.manual }).Count
        $manual = $total - $auto
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        $doc | Should -Match "\| \*\*Total\*\* \| \*\*$total\*\* \| \*\*$auto\*\* \| \*\*$manual\*\* \|"
    }
}

Describe 'Technology review: Azure Machine Learning' {
    BeforeAll {
        $p = $script:P
        $ws = {
            param($Name, $Kind, $Public, $Identity, $Isolation, $Cmk)
            [ordered]@{ id = "$p/Microsoft.MachineLearningServices/workspaces/$Name"; name = $Name; location = 'x'; workspaceKind = $Kind; publicAccess = $Public; identityType = $Identity; isolationMode = $Isolation; cmkStatus = $Cmk; hbiWorkspace = $false; v1LegacyMode = $false }
        }
        $dom = {
            param($Workspaces)
            [ordered]@{
                domains    = [ordered]@{
                    ai      = [ordered]@{ mlWorkspaces = @($Workspaces) }
                    storage = [ordered]@{ storageAccounts = @() }
                }
                networking = [ordered]@{ privateEndpoints = @((Get-TestPrivateEndpoint "$p/Microsoft.MachineLearningServices/workspaces/good")) }
                governance = [ordered]@{ roleAssignments = @() }
                monitor    = [ordered]@{ appInsights = @(); autoscaleSettings = @() }
                finops     = [ordered]@{ reservations = @() }
                opsPosture = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $false }
            }
        }
        # bad: no network isolation, public, no identity, and an ABSENT (null) encryption status
        $bad = & $dom @(
            (& $ws 'bad' 'Default' 'Enabled' '' 'Disabled' $null)
            (& $ws 'good' 'Default' 'Disabled' 'SystemAssigned' 'AllowOnlyApprovedOutbound' 'Enabled')
        )
        # good: the Foundry project workspace has no key of its own and is skipped by the rules that say so
        $good = & $dom @(
            (& $ws 'good' 'Default' 'Disabled' 'SystemAssigned' 'AllowOnlyApprovedOutbound' 'Enabled')
            (& $ws 'proj' 'Project' 'Disabled' 'SystemAssigned' 'AllowOnlyApprovedOutbound' '')
        )
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

    It 'names only the offending workspace in a failing rule' {
        $script:MlBad['WAF-ML-SE-04'].EvidenceCount | Should -Be 1
    }

    It 'keeps the customer-managed-key item Manual and attaches only the workspaces not on a key' {
        $script:MlBad['WAF-ML-SE-14'].Status | Should -Be 'Manual'
        $script:MlBad['WAF-ML-SE-14'].EvidenceCount | Should -Be 1   # bad has a null status; good has a key
        $script:MlGood['WAF-ML-SE-14'].Status | Should -Be 'Manual'
        $script:MlGood['WAF-ML-SE-14'].EvidenceCount | Should -Be 0   # the Project kind is skipped
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
            param($Name, $Sku, $Replicas, $Public, $LocalAuthOff, $Identity, $IpRules, $Cmk, $Semantic)
            [ordered]@{
                id = "$p/Microsoft.Search/searchServices/$Name"; name = $Name; location = 'x'; sku = $Sku; publicAccess = $Public
                disableLocalAuth = $LocalAuthOff; replicaCount = $Replicas; identityType = $Identity; ipRuleCount = $IpRules
                cmkEnforcement = $Cmk; semanticSearch = $Semantic; partitionCount = 1
            }
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
        # free: public with NO ip rules (null), no identity; basic1: public with three ip rules, identity None
        $bad = & $dom @(
            (& $mk 'free' 'free' 1 'enabled' $false '' $null 'Unspecified' 'disabled')
            (& $mk 'basic1' 'basic' 1 'Enabled' $false 'None' 3 'Disabled' 'standard')
            (& $mk 'good' 'standard' 3 'Disabled' $true 'SystemAssigned' 0 'Enabled' 'free')
        ) @((Get-TestPrivateEndpoint "$p/Microsoft.Search/searchServices/good"))
        $good = & $dom @(
            (& $mk 'good' 'standard' 3 'Disabled' $true 'SystemAssigned' 0 'Enabled' 'free')
            (& $mk 'serverless' 'serverless' $null 'Disabled' $true 'UserAssigned' $null 'Enabled' 'disabled')
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
        @{ Id = 'WAF-AISEARCH-SE-04'; Count = 2 }   # identity '' and None
        @{ Id = 'WAF-AISEARCH-SE-11'; Count = 1 }   # free is public with a null rule count; basic1 has rules and passes
    ) {
        $script:SrBad[$Id].Status | Should -Be 'Fail'
        $script:SrBad[$Id].EvidenceCount | Should -Be $Count
        $script:SrGood[$Id].Status | Should -Be 'Pass'
    }

    It 'keeps the per-index key item and the semantic plan item Manual, with only the services worth reviewing attached' {
        $script:SrBad['WAF-AISEARCH-SE-06'].Status | Should -Be 'Manual'
        $script:SrBad['WAF-AISEARCH-SE-06'].EvidenceCount | Should -Be 2   # free (Unspecified) and basic1 (Disabled); good enforces
        $script:SrGood['WAF-AISEARCH-SE-06'].EvidenceCount | Should -Be 0
        $script:SrBad['WAF-AISEARCH-CO-06'].Status | Should -Be 'Manual'
        $script:SrBad['WAF-AISEARCH-CO-06'].EvidenceCount | Should -Be 1   # basic1 is on the billed standard plan
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
        $eh = {
            param($Name, $Zone, $Public, $Sku, $AutoInflate, $LocalAuthOff, $Tls, $Key)
            [ordered]@{
                id = "$p/Microsoft.EventHub/namespaces/$Name"; name = $Name; location = 'x'; zoneRedundant = $Zone; publicAccess = $Public
                autoInflateEnabled = $AutoInflate; skuName = $Sku; capacity = 1; maxThroughputUnits = 0; geoReplicaCount = 0
                disableLocalAuth = $LocalAuthOff; minimumTlsVersion = $Tls; cmkKeySource = $Key; doubleEncryption = $false
            }
        }
        $dbx = {
            param($Name, $Sku, $Vnet, $NoPublicIp)
            [ordered]@{ id = "$p/Microsoft.Databricks/workspaces/$Name"; name = $Name; sku = $Sku; vnetInjected = $Vnet; noPublicIp = $NoPublicIp; publicNetworkAccess = 'Disabled' }
        }
        $la = {
            param($Name, $Retention, $Ingest, $Query, $LocalAuthOff, $Resource, $Quota, $Region = 'eastus')
            [ordered]@{
                id = "$p/Microsoft.OperationalInsights/workspaces/$Name"; name = $Name; location = $Region; retentionInDays = $Retention; skuName = 'PerGB2018'
                dailyQuotaGb = $Quota; publicNetworkAccessForIngestion = $Ingest; publicNetworkAccessForQuery = $Query; disableLocalAuth = $LocalAuthOff
                resourceContextAccess = $Resource; replicationEnabled = $false
            }
        }
        # eh-bad: not zone redundant, public, Standard without auto-inflate, SAS on, TLS 1.0, Microsoft-managed keys
        # eh-b2: SAS flag ABSENT (null), TLS ABSENT (''), Standard with auto-inflate
        # eh-b3: Premium without auto-inflate (not Standard, so PE-05 skips it); otherwise compliant
        $bad = & $mk @(
            (& $eh 'eh-bad' $false 'Enabled' 'Standard' $false $false '1.0' '')
            (& $eh 'eh-b2' $true 'Disabled' 'Standard' $true $null '' 'Microsoft.KeyVault')
            (& $eh 'eh-b3' $true 'Disabled' 'Premium' $false $true '1.2' 'Microsoft.KeyVault')
        ) @(
            (& $dbx 'dbx-bad' 'trial' $false $null)
            (& $dbx 'dbx-b2' 'premium' $true $false)
        ) @(
            (& $la 'la-bad' 7 'Enabled' 'Enabled' $null $false -1 'brazilsoutheast')   # not in a zone region, no replication (RE-10)
            (& $la 'la-b2' 90 'Disabled' 'Disabled' $true $true 10)
            (& $la 'la-b3' 90 'Disabled' 'Enabled' $true $null $null)
        ) @(
            [ordered]@{ id = 'f1'; name = 'f1'; sku = 'F2'; state = 'Failed' }
        ) @(
            [ordered]@{ type = 'microsoft.eventhub/namespaces'; total = 2; withDiag = 1; coveragePct = 50 }
            [ordered]@{ type = 'microsoft.operationalinsights/workspaces'; total = 1; withDiag = 0; coveragePct = 0 }
        )
        $good = & $mk @(
            (& $eh 'eh-good' $true 'Disabled' 'Standard' $true $true '1.2' 'Microsoft.KeyVault')
        ) @(
            (& $dbx 'dbx-good' 'premium' $true $true)
        ) @(
            (& $la 'la-good' 90 'Disabled' 'Disabled' $true $true 10)
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

    It 'scores <Id> as Fail with exactly <Count> offenders on the bad estate and Pass on the good one' -ForEach @(
        @{ Id = 'WAF-ANALYTICS-SE-01'; Count = 1 }   # dbx-bad is not injected
        @{ Id = 'WAF-ANALYTICS-SE-03'; Count = 2 }   # dbx-bad (null) and dbx-b2 (false)
        @{ Id = 'WAF-ANALYTICS-SE-11'; Count = 2 }   # eh-bad (false) and eh-b2 (null: absent means SAS on)
        @{ Id = 'WAF-ANALYTICS-SE-12'; Count = 1 }   # only the explicit 1.0; an empty value is not flagged
        @{ Id = 'WAF-ANALYTICS-SE-16'; Count = 2 }   # la-bad (public, key auth) and la-b3 (public query)
        @{ Id = 'WAF-ANALYTICS-SE-17'; Count = 2 }   # la-bad (false) and la-b3 (null)
        @{ Id = 'WAF-ANALYTICS-CO-11'; Count = 2 }   # la-bad (-1) and la-b3 (null) have no cap
        @{ Id = 'WAF-ANALYTICS-RE-10'; Count = 1 }   # la-bad is in a region without availability zones and does not replicate
        @{ Id = 'WAF-ANALYTICS-PE-05'; Count = 1 }   # eh-bad; Premium eh-b3 is skipped
    ) {
        $script:AnBad[$Id].Status | Should -Be 'Fail'
        $script:AnBad[$Id].EvidenceCount | Should -Be $Count
        $script:AnGood[$Id].Status | Should -Be 'Pass'
    }

    It 'keeps the customer-managed-key item Manual and attaches only the namespaces not on a key' {
        $script:AnBad['WAF-ANALYTICS-SE-13'].Status | Should -Be 'Manual'
        $script:AnBad['WAF-ANALYTICS-SE-13'].EvidenceCount | Should -Be 1   # eh-bad; the others use Key Vault keys
        $script:AnGood['WAF-ANALYTICS-SE-13'].Status | Should -Be 'Manual'
        $script:AnGood['WAF-ANALYTICS-SE-13'].EvidenceCount | Should -Be 0
    }

    It 'keeps the capacity and workspace-tier judgement items Manual with their evidence attached' {
        foreach ($id in 'WAF-ANALYTICS-RE-08', 'WAF-ANALYTICS-CO-07', 'WAF-ANALYTICS-PE-04') {
            $script:AnBad[$id].Status | Should -Be 'Manual'
            $script:AnBad[$id].EvidenceCount | Should -Be 3
        }
        foreach ($id in 'WAF-ANALYTICS-CO-09') {
            $script:AnBad[$id].Status | Should -Be 'Manual'
            $script:AnBad[$id].EvidenceCount | Should -Be 3
        }
    }
}

Describe 'Technology review: Data Services' {
    BeforeAll {
        $p = $script:P
        $mk = {
            param([bool] $Compliant)
            $id = { param($t) "$p/$t" }
            $pna = $(if ($Compliant) { 'Disabled' } else { 'Enabled' })

            # ---- SQL: servers (bad adds one with an ABSENT tls and Entra flag, and one fully compliant) ----
            $srv = [ordered]@{ id = (& $id 'Microsoft.Sql/servers/srv'); name = 'srv'; resourceGroup = 'rg'; location = 'x'; publicNetworkAccess = $pna; minimalTlsVersion = $(if ($Compliant) { '1.2' } else { '1.0' }); entraOnlyAuth = $Compliant; identityType = ''; cmkEnabled = $false }
            $srv2 = [ordered]@{ id = (& $id 'Microsoft.Sql/servers/srv2'); name = 'srv2'; resourceGroup = 'rg'; location = 'x'; publicNetworkAccess = 'Enabled'; minimalTlsVersion = ''; entraOnlyAuth = $null; identityType = ''; cmkEnabled = $false }
            $srv3 = [ordered]@{ id = (& $id 'Microsoft.Sql/servers/srv3'); name = 'srv3'; resourceGroup = 'rg'; location = 'x'; publicNetworkAccess = 'Disabled'; minimalTlsVersion = '1.3'; entraOnlyAuth = $true; identityType = 'UserAssigned'; cmkEnabled = $true }
            $sqlServers = @($srv); if (-not $Compliant) { $sqlServers += $srv2, $srv3 }

            # ---- SQL: databases (master is a system database: excluded from zone redundancy and backup redundancy) ----
            $dbs = @(
                [ordered]@{ id = (& $id 'Microsoft.Sql/servers/srv/databases/db1'); name = 'db1'; resourceGroup = 'rg'; location = 'x'; zoneRedundant = $Compliant; tier = 'GeneralPurpose'; backupRedundancy = $(if ($Compliant) { 'Geo' } else { 'Local' }); secondaryType = ''; haReplicaCount = 0 }
                [ordered]@{ id = (& $id 'Microsoft.Sql/servers/srv/databases/master'); name = 'master'; resourceGroup = 'rg'; location = 'x'; zoneRedundant = $false; tier = 'System'; backupRedundancy = ''; secondaryType = ''; haReplicaCount = $null }
            )
            if (-not $Compliant) {
                $dbs += [ordered]@{ id = (& $id 'Microsoft.Sql/servers/srv/databases/db2'); name = 'db2'; resourceGroup = 'rg'; location = 'x'; zoneRedundant = $true; tier = 'BusinessCritical'; backupRedundancy = 'Zone'; secondaryType = ''; haReplicaCount = 1 }
                $dbs += [ordered]@{ id = (& $id 'Microsoft.Sql/servers/srv/databases/db3'); name = 'db3'; resourceGroup = 'rg'; location = 'x'; zoneRedundant = $true; tier = 'Hyperscale'; backupRedundancy = 'GeoZone'; secondaryType = ''; haReplicaCount = 1 }
            }

            # ---- SQL managed instances ----
            $mi = [ordered]@{ id = (& $id 'Microsoft.Sql/managedInstances/mi'); name = 'mi'; sku = 'GP_Gen5'; publicDataEndpointEnabled = (-not $Compliant); vCores = 4; zoneRedundant = $Compliant; backupRedundancy = $(if ($Compliant) { 'Geo' } else { 'Local' }); entraOnlyAuth = $(if ($Compliant) { $true } else { $null }); minimalTlsVersion = '1.2'; cmkEnabled = $Compliant }
            $mis = @($mi)
            if (-not $Compliant) {
                $mis += [ordered]@{ id = (& $id 'Microsoft.Sql/managedInstances/mi2'); name = 'mi2'; sku = 'GP_Gen5'; publicDataEndpointEnabled = $false; vCores = 4; zoneRedundant = $true; backupRedundancy = 'Zone'; entraOnlyAuth = $false; minimalTlsVersion = '1.2'; cmkEnabled = $true }
                $mis += [ordered]@{ id = (& $id 'Microsoft.Sql/managedInstances/mi3'); name = 'mi3'; sku = 'GP_Gen5'; publicDataEndpointEnabled = $false; vCores = 4; zoneRedundant = $true; backupRedundancy = 'GeoZone'; entraOnlyAuth = $true; minimalTlsVersion = '1.2'; cmkEnabled = $true }
            }

            # ---- Cosmos DB: cos is the primary row; the bad estate adds a multi-region account with null flags,
            # a compliant multi-region account behind IP rules, and a multi-region-write account ----
            $cosRow = {
                param($Name, $Pna, $LocalAuthOff, $Regions, $ZoneRegions, $Failover, $MultiWrite, $Backup, $Vnet, $IpRules, $Cmk)
                [ordered]@{
                    id = (& $id "Microsoft.DocumentDB/databaseAccounts/$Name"); name = $Name; kind = 'GlobalDocumentDB'; publicNetworkAccess = $Pna; disableLocalAuth = $LocalAuthOff
                    regionCount = $Regions; zoneRedundantRegionCount = $ZoneRegions; automaticFailover = $Failover; backupType = $Backup; multiRegionWrites = $MultiWrite
                    minimalTlsVersion = 'Tls12'; vnetFilterEnabled = $Vnet; ipRuleCount = $IpRules; cmkEnabled = $Cmk
                }
            }
            $cos = $(if ($Compliant) { & $cosRow 'cos' 'Disabled' $true 2 2 $true $false 'Continuous' $true 0 $true } else { & $cosRow 'cos' 'Enabled' $false 1 0 $false $false 'Periodic' $false 0 $false })
            $cosAll = @($cos)
            if (-not $Compliant) {
                $cosAll += & $cosRow 'cos2' 'Enabled' $false 2 0 $null $false $null $true $null $null
                $cosAll += & $cosRow 'cos3' 'Enabled' $false 2 2 $true $false 'Continuous' $false 1 $true
                $cosAll += & $cosRow 'cos4' 'Disabled' $true 2 1 $null $true 'Continuous' $true 0 $true
            }

            # ---- PostgreSQL (pg2 has every new flag ABSENT) and MySQL ----
            $pgRow = {
                param($Name, $Pna, $Ha, $Geo, $Entra, $PwAuth, $Window = 'Enabled')
                [ordered]@{ id = (& $id "Microsoft.DBforPostgreSQL/flexibleServers/$Name"); name = $Name; sku = 'Standard_D2s_v3'; version = '16'; publicNetworkAccess = $Pna; tier = 'GeneralPurpose'; haMode = $Ha; geoBackup = $Geo; backupRetentionDays = 7; encryptionType = 'SystemManaged'; entraAuth = $Entra; passwordAuth = $PwAuth; customMaintenanceWindow = $Window }
            }
            $pgs = @($(if ($Compliant) { & $pgRow 'pg' 'Disabled' 'ZoneRedundant' 'Enabled' 'Enabled' 'Disabled' } else { & $pgRow 'pg' 'Enabled' 'SameZone' 'Disabled' 'Disabled' 'Enabled' 'Disabled' }))
            if (-not $Compliant) {
                $pgs += & $pgRow 'pg2' 'Enabled' '' $null $null $null ''
                $pgs += & $pgRow 'pg3' 'Disabled' 'ZoneRedundant' 'Enabled' 'Enabled' 'Disabled'
            }
            $myRow = {
                param($Name, $Pna, $Ha, $Geo)
                [ordered]@{ id = (& $id "Microsoft.DBforMySQL/flexibleServers/$Name"); name = $Name; sku = 'Standard_D2ds_v4'; version = '8.0'; publicNetworkAccess = $Pna; haMode = $Ha; geoBackup = $Geo; backupRetentionDays = 7; encryptionType = ''; storageAutoGrow = 'Enabled' }
            }
            $mys = @($(if ($Compliant) { & $myRow 'my' 'Disabled' 'ZoneRedundant' 'Enabled' } else { & $myRow 'my' 'Enabled' 'Disabled' 'Disabled' }))
            if (-not $Compliant) {
                $mys += & $myRow 'my2' 'Enabled' '' $null
                $mys += & $myRow 'my3' 'Disabled' 'SameZone' 'Enabled'
            }

            # ---- Redis: red is Redis Enterprise (key setting lives on a child database, so RED-06 skips it);
            # redc and redc2 are classic caches ----
            $redRow = {
                param($Name, $Type, $Sku, $Pna, $Ha, $KeyAuthOff, $NonSsl, $Tls)
                [ordered]@{ id = (& $id "Microsoft.Cache/$Name"); name = $Name; type = $Type; sku = $Sku; skuFamily = ''; skuCapacity = $null; publicNetworkAccess = $Pna; zoneCount = $null; zonalAllocationPolicy = ''; replicasPerPrimary = $null; minimumTlsVersion = $Tls; nonSslPortEnabled = $NonSsl; accessKeyAuthDisabled = $KeyAuthOff; aadEnabled = $null; highAvailability = $Ha }
            }
            $reds = @(
                $(if ($Compliant) { & $redRow 'red' 'microsoft.cache/redisenterprise' 'Balanced_B5' 'Disabled' 'Enabled' $null $null '1.2' } else { & $redRow 'red' 'microsoft.cache/redisenterprise' 'Balanced_B5' 'Enabled' 'Disabled' $null $null '1.2' })
                $(if ($Compliant) { & $redRow 'redc' 'microsoft.cache/redis' 'Premium' 'Disabled' '' $true $false '1.2' } else { & $redRow 'redc' 'microsoft.cache/redis' 'Basic' 'Enabled' '' $null $true '1.0' })
            )
            if (-not $Compliant) { $reds += & $redRow 'redc2' 'microsoft.cache/redis' 'Standard' 'Enabled' '' $false $false '1.1' }

            # ---- Storage: sto is the primary row; the bad estate adds one with every flag ABSENT, one compliant
            # row (TLS 1.3, the alternate Keyvault casing, perimeter) and one legacy blob-only account ----
            $stoRow = {
                param($Name, $Kind, $Sku, $PublicAccess, $Https, $Tls, $DefaultDeny, $SharedKey, $KeySource, $Pna)
                [ordered]@{
                    id = (& $id "Microsoft.Storage/storageAccounts/$Name"); name = $Name; location = 'x'; kind = $Kind; sku = $Sku; publicAccess = $PublicAccess; httpsOnly = $Https; minTls = $Tls
                    networkDefaultDeny = $DefaultDeny; sharedKeyAccess = $SharedKey; keySource = $KeySource; infrastructureEncryption = $false; publicNetworkAccess = $Pna
                    allowCrossTenantReplication = $false; defaultToOAuth = $true
                }
            }
            $sto = $(if ($Compliant) { & $stoRow 'sto' 'StorageV2' 'Standard_ZRS' $false $true 'TLS1_2' $true $false 'Microsoft.Keyvault' 'Disabled' } else { & $stoRow 'sto' 'Storage' 'Standard_LRS' $true $false 'TLS1_0' $false $true 'Microsoft.Storage' 'Enabled' })
            $stos = @($sto)
            if (-not $Compliant) {
                $stos += & $stoRow 'sto2' 'StorageV1' 'Standard_LRS' $false $true '' $true $null '' ''
                $stos += & $stoRow 'sto3' 'BlockBlobStorage' 'Premium_ZRS' $false $true 'TLS1_3' $true $false 'Microsoft.KeyVault' 'SecuredByPerimeter'
                $stos += & $stoRow 'sto4' 'BlobStorage' 'Standard_LRS' $false $true 'TLS1_1' $true $true 'Microsoft.Storage' 'Enabled'
            }

            # ---- phase 4 batch 2 per-resource ARM reads, each with its Measured flag ----
            # Blob service: sto has every protection off, sto2 has soft delete but no versioning or restore, sto3 is protected.
            $blobRow = {
                param($Name, $Delete, $Container, $Versioning, $Pitr)
                [ordered]@{ storageAccountId = (& $id "Microsoft.Storage/storageAccounts/$Name").ToLowerInvariant(); name = $Name; resourceGroup = 'rg'; subscriptionId = 's'; location = 'x'
                    deleteRetentionEnabled = $Delete; deleteRetentionDays = $(if ($Delete) { 14 } else { $null }); containerDeleteRetentionEnabled = $Container; containerDeleteRetentionDays = $(if ($Container) { 14 } else { $null })
                    versioningEnabled = $Versioning; changeFeedEnabled = $Pitr; pointInTimeRestoreEnabled = $Pitr }
            }
            $blobs = @($(if ($Compliant) { & $blobRow 'sto' $true $true $true $true } else { & $blobRow 'sto' $false $false $false $false }))
            if (-not $Compliant) { $blobs += (& $blobRow 'sto2' $true $true $false $false), (& $blobRow 'sto3' $true $true $true $true) }
            # Lifecycle management policies (depth wiring), one row per blob-capable account that was read: sto has no tiering rule on the bad
            # estate, sto3 is a premium block blob account (no access tiers), sto4 tiers. sto2 is general-purpose v1 and is never asked.
            $lifecycleRow = {
                param($Name, $Premium, $Tiering, $Delete)
                [ordered]@{ storageAccountId = (& $id "Microsoft.Storage/storageAccounts/$Name").ToLowerInvariant(); name = $Name; premium = $Premium; policyPresent = (($Tiering + $Delete) -gt 0)
                    ruleCount = ($Tiering + $Delete); enabledRuleCount = ($Tiering + $Delete); tieringRuleCount = $Tiering; deleteRuleCount = $Delete }
            }
            $lifecycle = @($(if ($Compliant) { & $lifecycleRow 'sto' $false 1 1 } else { & $lifecycleRow 'sto' $false 0 0 }))
            if (-not $Compliant) { $lifecycle += (& $lifecycleRow 'sto3' $true 0 0), (& $lifecycleRow 'sto4' $false 1 0) }
            # SQL auditing and failover groups, one row per server: srv is Disabled with no group, srv2 has an unreadable state and no group, srv3 is audited and in two groups.
            $auditRow = { param($Name, $State) [ordered]@{ sqlServerId = (& $id "Microsoft.Sql/servers/$Name").ToLowerInvariant(); name = $Name; resourceGroup = 'rg'; subscriptionId = 's'; location = 'x'; auditingState = $State; azureMonitorTargetEnabled = ($State -eq 'Enabled') } }
            $fogRow = { param($Name, $Count) [ordered]@{ sqlServerId = (& $id "Microsoft.Sql/servers/$Name").ToLowerInvariant(); name = $Name; resourceGroup = 'rg'; subscriptionId = 's'; location = 'x'; failoverGroupCount = $Count; automaticFailoverGroupCount = $Count; hasAutomaticFailover = ($Count -gt 0); failoverPolicies = @(if ($Count -gt 0) { 'Automatic' }) } }
            $audits = @($(if ($Compliant) { & $auditRow 'srv' 'Enabled' } else { & $auditRow 'srv' 'Disabled' }))
            $fogs = @($(if ($Compliant) { & $fogRow 'srv' 1 } else { & $fogRow 'srv' 0 }))
            if (-not $Compliant) { $audits += (& $auditRow 'srv2' $null), (& $auditRow 'srv3' 'Enabled'); $fogs += (& $fogRow 'srv2' 0), (& $fogRow 'srv3' 2) }
            # Redis Enterprise databases: the cluster `red` has the default database, with keys and plaintext allowed on the bad estate.
            $redDbs = @([ordered]@{ redisEnterpriseId = (& $id 'Microsoft.Cache/red').ToLowerInvariant(); name = 'default'; clusterName = 'red'; resourceGroup = 'rg'; subscriptionId = 's'; location = 'x'
                    accessKeysAuthentication = $(if ($Compliant) { 'Disabled' } else { 'Enabled' }); clientProtocol = $(if ($Compliant) { 'Encrypted' } else { 'Plaintext' })
                    persistenceAofEnabled = $false; persistenceAofFrequency = $null; persistenceRdbEnabled = $Compliant; persistenceRdbFrequency = $null; geoReplicationLinkCount = 0 })

            $pe = @()
            if ($Compliant) { $pe = @((Get-TestPrivateEndpoint $srv.id), (Get-TestPrivateEndpoint $cos.id), (Get-TestPrivateEndpoint $reds[0].id), (Get-TestPrivateEndpoint $reds[1].id), (Get-TestPrivateEndpoint $sto.id)) }
            else { $pe = @((Get-TestPrivateEndpoint $srv2.id), (Get-TestPrivateEndpoint $srv3.id)) }
            $cov = $(if ($Compliant) { 100 } else { 0 })
            [ordered]@{
                domains    = [ordered]@{
                    databases = [ordered]@{
                        sqlDatabases              = $dbs
                        sqlServers                = $sqlServers
                        sqlDefenderPricing        = @([ordered]@{ subscriptionId = 's'; name = 'sqlservers'; pricingTier = $(if ($Compliant) { 'Standard' } else { 'Free' }) })
                        sqlManagedInstances       = $mis
                        sqlElasticPools           = @()
                        cosmosDbAccounts          = $cosAll
                        postgreSqlFlexibleServers = $pgs
                        mySqlFlexibleServers      = $mys
                        redisCaches               = $reds
                        sqlServerAuditingMeasured = $true
                        sqlServerAuditing         = $audits
                        sqlFailoverGroupsMeasured = $true
                        sqlFailoverGroups         = $fogs
                        redisEnterpriseDatabasesMeasured = $true
                        redisEnterpriseDatabases  = $redDbs
                    }
                    storage   = [ordered]@{ storageAccounts = $stos; blobServicePropertiesMeasured = $true; blobServiceProperties = $blobs; lifecyclePoliciesMeasured = $true; lifecyclePolicies = $lifecycle }
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
                        foreach ($t in 'microsoft.sql/servers/databases', 'microsoft.documentdb/databaseaccounts', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.storage/storageaccounts', 'microsoft.sql/managedinstances', 'microsoft.cache/redis', 'microsoft.cache/redisenterprise') {
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
        @{ Id = 'WAF-DATA-BLOB-04' }
        @{ Id = 'WAF-DATA-BLOB-05' }
        @{ Id = 'WAF-DATA-BLOB-09' }
        @{ Id = 'WAF-DATA-BLOB-12' }
        @{ Id = 'WAF-DATA-SQL-02' }    # no failover group
        @{ Id = 'WAF-DATA-SQL-11' }    # auditing not enabled
        @{ Id = 'WAF-DATA-MI-08' }     # managed instance with no diagnostic setting
        @{ Id = 'WAF-DATA-RED-08' }    # classic and Enterprise Redis with no diagnostic setting
    ) {
        $script:DtBad[$Id].Status | Should -Be 'Fail'
        $script:DtGood[$Id].Status | Should -Be 'Pass'
    }

    It 'scores <Id> as Fail with exactly <Count> offenders on the bad estate and Pass on the good one' -ForEach @(
        @{ Id = 'WAF-DATA-SQL-01'; Count = 1 }     # db1; master excluded, db2 and db3 are zone redundant
        @{ Id = 'WAF-DATA-SQL-07'; Count = 1 }     # srv has no private endpoint; srv2 and srv3 do
        @{ Id = 'WAF-DATA-SQL-08'; Count = 2 }     # srv (1.0) and srv2 (empty: absent means every version)
        @{ Id = 'WAF-DATA-SQL-09'; Count = 2 }     # srv (false) and srv2 (null: no Entra administrator)
        @{ Id = 'WAF-DATA-SQL-19'; Count = 2 }     # db1 (Local) and db2 (Zone); master excluded, db3 is GeoZone
        @{ Id = 'WAF-DATA-MI-01'; Count = 1 }      # mi
        @{ Id = 'WAF-DATA-MI-02'; Count = 2 }      # mi (Local) and mi2 (Zone)
        @{ Id = 'WAF-DATA-MI-05'; Count = 2 }      # mi (null) and mi2 (false)
        @{ Id = 'WAF-DATA-COS-01'; Count = 2 }     # cos and cos2 have no zone-redundant region
        @{ Id = 'WAF-DATA-COS-02'; Count = 1 }     # cos is single region
        @{ Id = 'WAF-DATA-COS-03'; Count = 1 }     # cos2: two regions, single write, null failover; cos is single region, cos4 writes in many
        @{ Id = 'WAF-DATA-COS-04'; Count = 2 }     # cos (Periodic) and cos2 (null)
        @{ Id = 'WAF-DATA-COS-08'; Count = 1 }     # cos: public, no vnet filter, no ip rules; cos2 has a filter, cos3 has a rule
        @{ Id = 'WAF-DATA-PG-01'; Count = 2 }      # pg (SameZone) and pg2 (empty)
        @{ Id = 'WAF-DATA-PG-02'; Count = 2 }      # pg (Disabled) and pg2 (null)
        @{ Id = 'WAF-DATA-PG-04'; Count = 2 }      # pg (Disabled) and pg2 (null)
        @{ Id = 'WAF-DATA-MYS-01'; Count = 2 }     # my (Disabled) and my2 (empty); my3 is SameZone
        @{ Id = 'WAF-DATA-RED-01'; Count = 2 }     # red (HA Disabled) and redc (Basic); redc2 is Standard
        @{ Id = 'WAF-DATA-RED-06'; Count = 2 }     # redc2 (classic, keys on) and the Enterprise default database (keys Enabled); redc (null flag) is not scored and the cluster row never matches
        @{ Id = 'WAF-DATA-RED-07'; Count = 3 }     # redc (non-TLS port, 1.0), redc2 (1.1) and the Enterprise default database (Plaintext)
        @{ Id = 'WAF-DATA-BLOB-03'; Count = 3 }    # sto (TLS1_0), sto2 (empty: absent means 1.0), sto4 (TLS1_1)
        @{ Id = 'WAF-DATA-BLOB-06'; Count = 3 }    # sto (true), sto2 (null: absent means allowed), sto4 (true)
        @{ Id = 'WAF-DATA-BLOB-15'; Count = 3 }    # sto (Enabled), sto2 (empty), sto4 (Enabled); sto3 is perimeter
        @{ Id = 'WAF-DATA-BLOB-16'; Count = 3 }    # Storage, StorageV1 and BlobStorage
        @{ Id = 'WAF-DATA-SQL-02'; Count = 2 }     # srv and srv2 have no failover group; srv3 has two
        @{ Id = 'WAF-DATA-SQL-11'; Count = 2 }     # srv (Disabled) and srv2 (unreadable state); srv3 is Enabled
        @{ Id = 'WAF-DATA-PG-09'; Count = 2 }       # pg (platform window) and pg2 (no window reported); pg3 chose one
        @{ Id = 'WAF-DATA-BLOB-13'; Count = 1 }     # sto has no tiering rule; sto3 is premium (no tiers); sto4 tiers
        @{ Id = 'WAF-DATA-BLOB-10'; Count = 2 }    # sto (everything off) and sto2 (no versioning or restore); sto3 is protected
        @{ Id = 'WAF-DATA-MI-08'; Count = 1 }      # the managed-instance coverage row at 0 percent
        @{ Id = 'WAF-DATA-RED-08'; Count = 2 }     # the classic and the Enterprise coverage rows at 0 percent
    ) {
        $script:DtBad[$Id].Status | Should -Be 'Fail'
        $script:DtBad[$Id].EvidenceCount | Should -Be $Count
        $script:DtGood[$Id].Status | Should -Be 'Pass'
    }

    It 'excludes the master database from the zone-redundancy rule' {
        $script:DtBad['WAF-DATA-SQL-01'].EvidenceCount | Should -Be 1
    }

    It 'keeps Azure HorizonDB items Manual because no HorizonDB dataset is collected' {
        foreach ($id in $script:DtBad.Keys | Where-Object { $_ -like 'WAF-DATA-HZ-*' }) { $script:DtBad[$id].Status | Should -Be 'Manual' }
        @($script:DtBad.Keys | Where-Object { $_ -like 'WAF-DATA-HZ-*' }).Count | Should -BeGreaterThan 0
    }

    It 'keeps the customer-managed-key items Manual and attaches only the resources not on a key' -ForEach @(
        @{ Id = 'WAF-DATA-MI-06'; Count = 1 }     # mi; mi2 and mi3 use a key
        @{ Id = 'WAF-DATA-COS-11'; Count = 2 }    # cos (false) and cos2 (null)
        @{ Id = 'WAF-DATA-BLOB-07'; Count = 3 }   # sto, sto2 (empty) and sto4; sto3 uses the alternate Keyvault casing
    ) {
        $script:DtBad[$Id].Status | Should -Be 'Manual'
        $script:DtBad[$Id].EvidenceCount | Should -Be $Count
        $script:DtGood[$Id].Status | Should -Be 'Manual'
        $script:DtGood[$Id].EvidenceCount | Should -Be 0
    }

    It 'keeps the items ARM cannot answer Manual, with their evidence attached' {
        foreach ($id in 'WAF-DATA-RED-02', 'WAF-DATA-SQL-18', 'WAF-DATA-COS-17', 'WAF-DATA-MYS-08', 'WAF-DATA-RED-09', 'WAF-DATA-BLOB-14') {
            $script:DtBad[$id].Status | Should -Be 'Manual' -Because "$id needs a human"
        }
        $script:DtBad['WAF-DATA-COS-17'].EvidenceCount | Should -Be 4
        $script:DtBad['WAF-DATA-RED-02'].EvidenceCount | Should -Be 1   # the Enterprise databases are attached with persistence and link counts
        $script:DtBad['WAF-DATA-MYS-08'].EvidenceCount | Should -Be 3
        $script:DtBad['WAF-DATA-RED-09'].EvidenceCount | Should -Be 3
        $script:DtBad['WAF-DATA-BLOB-14'].EvidenceCount | Should -Be 4
    }
}

Describe 'Technology review: settings where an absent value is itself the finding' {
    BeforeAll {
        $p = $script:P
        # one compliant baseline row per dataset; each case overrides a single setting with an explicit
        # null, an empty string or a real value, and the rule under test must read it correctly
        $script:Baseline = @{
            'domains.storage.storageAccounts'          = [ordered]@{ id = "$p/Microsoft.Storage/storageAccounts/edge"; name = 'edge'; location = 'x'; kind = 'StorageV2'; sku = 'Standard_ZRS'; publicAccess = $false; httpsOnly = $true; minTls = 'TLS1_2'; networkDefaultDeny = $true; sharedKeyAccess = $false; keySource = 'Microsoft.Keyvault'; infrastructureEncryption = $false; publicNetworkAccess = 'Disabled' }
            'domains.databases.sqlServers'             = [ordered]@{ id = "$p/Microsoft.Sql/servers/edge"; name = 'edge'; location = 'x'; publicNetworkAccess = 'Disabled'; minimalTlsVersion = '1.2'; entraOnlyAuth = $true; identityType = 'UserAssigned'; cmkEnabled = $true }
            'domains.databases.sqlManagedInstances'    = [ordered]@{ id = "$p/Microsoft.Sql/managedInstances/edge"; name = 'edge'; publicDataEndpointEnabled = $false; zoneRedundant = $true; backupRedundancy = 'Geo'; entraOnlyAuth = $true; minimalTlsVersion = '1.2'; cmkEnabled = $true }
            'domains.databases.cosmosDbAccounts'       = [ordered]@{ id = "$p/Microsoft.DocumentDB/databaseAccounts/edge"; name = 'edge'; publicNetworkAccess = 'Disabled'; disableLocalAuth = $true; regionCount = 2; zoneRedundantRegionCount = 2; automaticFailover = $true; backupType = 'Continuous'; multiRegionWrites = $false; vnetFilterEnabled = $true; ipRuleCount = 0; cmkEnabled = $true }
            'domains.databases.redisCaches'            = [ordered]@{ id = "$p/Microsoft.Cache/Redis/edge"; name = 'edge'; type = 'microsoft.cache/redis'; sku = 'Premium'; publicNetworkAccess = 'Disabled'; minimumTlsVersion = '1.2'; nonSslPortEnabled = $false; accessKeyAuthDisabled = $true; highAvailability = '' }
            'domains.integration.eventHubNamespaces'   = [ordered]@{ id = "$p/Microsoft.EventHub/namespaces/edge"; name = 'edge'; zoneRedundant = $true; publicAccess = 'Disabled'; autoInflateEnabled = $true; skuName = 'Standard'; disableLocalAuth = $true; minimumTlsVersion = '1.2'; cmkKeySource = 'Microsoft.KeyVault' }
            'management.logAnalyticsWorkspaces'        = [ordered]@{ id = "$p/Microsoft.OperationalInsights/workspaces/edge"; name = 'edge'; location = 'x'; retentionInDays = 90; skuName = 'PerGB2018'; dailyQuotaGb = 10; publicNetworkAccessForIngestion = 'Disabled'; publicNetworkAccessForQuery = 'Disabled'; disableLocalAuth = $true; resourceContextAccess = $true; replicationEnabled = $false }
            'domains.analytics.databricksWorkspaces'   = [ordered]@{ id = "$p/Microsoft.Databricks/workspaces/edge"; name = 'edge'; sku = 'premium'; vnetInjected = $true; noPublicIp = $true; publicNetworkAccess = 'Disabled' }
            'domains.ai.searchServices'                = [ordered]@{ id = "$p/Microsoft.Search/searchServices/edge"; name = 'edge'; sku = 'standard'; publicAccess = 'Disabled'; disableLocalAuth = $true; replicaCount = 3; identityType = 'SystemAssigned'; cmkEnforcement = 'Enabled'; ipRuleCount = 2; semanticSearch = 'free'; partitionCount = 1 }
            'domains.ai.mlWorkspaces'                  = [ordered]@{ id = "$p/Microsoft.MachineLearningServices/workspaces/edge"; name = 'edge'; workspaceKind = 'Default'; publicAccess = 'Disabled'; identityType = 'SystemAssigned'; isolationMode = 'AllowOnlyApprovedOutbound'; cmkStatus = 'Enabled'; hbiWorkspace = $false; v1LegacyMode = $false }
        }
    }

    It '<Case>' -ForEach @(
        # ---- storage: absent minimumTlsVersion, shared-key flag, key source and public network access ----
        @{ Case = 'BLOB-03 flags a null minimum TLS version'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-03'; Path = 'domains.storage.storageAccounts'; Row = @{ minTls = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-03 flags an empty minimum TLS version'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-03'; Path = 'domains.storage.storageAccounts'; Row = @{ minTls = '' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-03 flags TLS1_1'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-03'; Path = 'domains.storage.storageAccounts'; Row = @{ minTls = 'TLS1_1' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-03 passes TLS1_2'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-03'; Path = 'domains.storage.storageAccounts'; Row = @{ minTls = 'TLS1_2' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'BLOB-03 passes TLS1_3'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-03'; Path = 'domains.storage.storageAccounts'; Row = @{ minTls = 'TLS1_3' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'BLOB-06 flags a null shared-key flag (absent means allowed)'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-06'; Path = 'domains.storage.storageAccounts'; Row = @{ sharedKeyAccess = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-06 flags shared key allowed'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-06'; Path = 'domains.storage.storageAccounts'; Row = @{ sharedKeyAccess = $true }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-06 passes shared key disallowed'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-06'; Path = 'domains.storage.storageAccounts'; Row = @{ sharedKeyAccess = $false }; Status = 'Pass'; Count = 0 }
        @{ Case = 'BLOB-07 lists an empty key source'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-07'; Path = 'domains.storage.storageAccounts'; Row = @{ keySource = '' }; Status = 'Manual'; Count = 1 }
        @{ Case = 'BLOB-07 lists a null key source'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-07'; Path = 'domains.storage.storageAccounts'; Row = @{ keySource = $null }; Status = 'Manual'; Count = 1 }
        @{ Case = 'BLOB-07 does not list the Keyvault spelling'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-07'; Path = 'domains.storage.storageAccounts'; Row = @{ keySource = 'Microsoft.Keyvault' }; Status = 'Manual'; Count = 0 }
        @{ Case = 'BLOB-07 does not list the KeyVault spelling'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-07'; Path = 'domains.storage.storageAccounts'; Row = @{ keySource = 'Microsoft.KeyVault' }; Status = 'Manual'; Count = 0 }
        @{ Case = 'BLOB-15 flags an empty public network access'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-15'; Path = 'domains.storage.storageAccounts'; Row = @{ publicNetworkAccess = '' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-15 flags a null public network access'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-15'; Path = 'domains.storage.storageAccounts'; Row = @{ publicNetworkAccess = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-15 passes a security perimeter'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-15'; Path = 'domains.storage.storageAccounts'; Row = @{ publicNetworkAccess = 'SecuredByPerimeter' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'BLOB-16 flags the legacy Storage kind'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-16'; Path = 'domains.storage.storageAccounts'; Row = @{ kind = 'Storage' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-16 flags the StorageV1 kind'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-16'; Path = 'domains.storage.storageAccounts'; Row = @{ kind = 'StorageV1' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'BLOB-16 passes a premium block blob account'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-BLOB-16'; Path = 'domains.storage.storageAccounts'; Row = @{ kind = 'BlockBlobStorage' }; Status = 'Pass'; Count = 0 }
        # ---- SQL servers and managed instances ----
        @{ Case = 'SQL-08 flags a null minimal TLS version'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-SQL-08'; Path = 'domains.databases.sqlServers'; Row = @{ minimalTlsVersion = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SQL-08 flags an empty minimal TLS version'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-SQL-08'; Path = 'domains.databases.sqlServers'; Row = @{ minimalTlsVersion = '' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SQL-08 flags None'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-SQL-08'; Path = 'domains.databases.sqlServers'; Row = @{ minimalTlsVersion = 'None' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SQL-08 flags 1.1'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-SQL-08'; Path = 'domains.databases.sqlServers'; Row = @{ minimalTlsVersion = '1.1' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SQL-08 passes 1.3'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-SQL-08'; Path = 'domains.databases.sqlServers'; Row = @{ minimalTlsVersion = '1.3' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'SQL-09 flags a null Entra-only flag (no Entra administrator)'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-SQL-09'; Path = 'domains.databases.sqlServers'; Row = @{ entraOnlyAuth = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SQL-09 flags SQL authentication still allowed'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-SQL-09'; Path = 'domains.databases.sqlServers'; Row = @{ entraOnlyAuth = $false }; Status = 'Fail'; Count = 1 }
        @{ Case = 'MI-05 flags a null Entra-only flag'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-MI-05'; Path = 'domains.databases.sqlManagedInstances'; Row = @{ entraOnlyAuth = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'MI-02 flags an empty backup redundancy'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-MI-02'; Path = 'domains.databases.sqlManagedInstances'; Row = @{ backupRedundancy = '' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'MI-02 passes geo-zone-redundant backups'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-MI-02'; Path = 'domains.databases.sqlManagedInstances'; Row = @{ backupRedundancy = 'GeoZone' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'MI-01 flags a null zone-redundancy flag'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-MI-01'; Path = 'domains.databases.sqlManagedInstances'; Row = @{ zoneRedundant = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'MI-06 lists a null key flag'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-MI-06'; Path = 'domains.databases.sqlManagedInstances'; Row = @{ cmkEnabled = $null }; Status = 'Manual'; Count = 1 }
        # ---- Cosmos DB: null counts and flags ----
        @{ Case = 'COS-01 flags a null zone-redundant region count'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-01'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ zoneRedundantRegionCount = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'COS-02 flags a null region count'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-02'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ regionCount = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'COS-03 flags a multi-region account with null write and failover flags'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-03'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ multiRegionWrites = $null; automaticFailover = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'COS-03 skips a single-region account'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-03'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ regionCount = 1; multiRegionWrites = $null; automaticFailover = $null }; Status = 'Pass'; Count = 0 }
        @{ Case = 'COS-03 skips a multi-region-write account'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-03'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ multiRegionWrites = $true; automaticFailover = $null }; Status = 'Pass'; Count = 0 }
        @{ Case = 'COS-04 flags a null backup type'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-04'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ backupType = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'COS-08 flags public access with null network filter and rule count'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-08'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ publicNetworkAccess = 'Enabled'; vnetFilterEnabled = $null; ipRuleCount = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'COS-08 passes public access limited by an IP rule'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-08'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ publicNetworkAccess = 'Enabled'; vnetFilterEnabled = $false; ipRuleCount = 2 }; Status = 'Pass'; Count = 0 }
        @{ Case = 'COS-11 lists a null key flag'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-COS-11'; Path = 'domains.databases.cosmosDbAccounts'; Row = @{ cmkEnabled = $null }; Status = 'Manual'; Count = 1 }
        # ---- Redis: the classic-only access-key rule ----
        @{ Case = 'RED-06 flags a classic cache whose access-key flag is explicitly false'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-RED-06'; Path = 'domains.databases.redisCaches'; Row = @{ accessKeyAuthDisabled = $false }; Status = 'Fail'; Count = 1 }
        @{ Case = 'RED-06 does not score a classic cache that returned no access-key flag (null)'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-RED-06'; Path = 'domains.databases.redisCaches'; Row = @{ accessKeyAuthDisabled = $null }; Status = 'Pass'; Count = 0 }
        @{ Case = 'RED-06 is not assessed when only Redis Enterprise caches exist'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-RED-06'; Path = 'domains.databases.redisCaches'; Row = @{ type = 'microsoft.cache/redisenterprise'; accessKeyAuthDisabled = $null }; Status = 'NotAssessed'; Count = 0 }
        @{ Case = 'RED-07 does not flag an absent TLS version'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-RED-07'; Path = 'domains.databases.redisCaches'; Row = @{ minimumTlsVersion = '' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'RED-07 flags the non-TLS port'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-RED-07'; Path = 'domains.databases.redisCaches'; Row = @{ nonSslPortEnabled = $true }; Status = 'Fail'; Count = 1 }
        @{ Case = 'RED-01 flags a Redis Enterprise cache with high availability disabled'; Pattern = 'waf.dataservices'; Id = 'WAF-DATA-RED-01'; Path = 'domains.databases.redisCaches'; Row = @{ type = 'microsoft.cache/redisenterprise'; sku = 'Balanced_B5'; highAvailability = 'Disabled' }; Status = 'Fail'; Count = 1 }
        # ---- Event Hubs ----
        @{ Case = 'SE-11 flags a null SAS-disabled flag (absent means SAS on)'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-11'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ disableLocalAuth = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SE-11 flags SAS still enabled'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-11'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ disableLocalAuth = $false }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SE-12 does not flag an absent TLS version'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-12'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ minimumTlsVersion = '' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'SE-12 does not flag a null TLS version'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-12'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ minimumTlsVersion = $null }; Status = 'Pass'; Count = 0 }
        @{ Case = 'SE-12 flags TLS 1.0'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-12'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ minimumTlsVersion = '1.0' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SE-13 lists an empty key source'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-13'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ cmkKeySource = '' }; Status = 'Manual'; Count = 1 }
        @{ Case = 'SE-13 does not list the Keyvault spelling'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-13'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ cmkKeySource = 'Microsoft.Keyvault' }; Status = 'Manual'; Count = 0 }
        @{ Case = 'PE-05 flags a Standard namespace with a null auto-inflate flag'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-PE-05'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ autoInflateEnabled = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'PE-05 skips a Basic namespace'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-PE-05'; Path = 'domains.integration.eventHubNamespaces'; Row = @{ skuName = 'Basic'; autoInflateEnabled = $false }; Status = 'Pass'; Count = 0 }
        # ---- Log Analytics ----
        @{ Case = 'SE-16 flags a null local-authentication flag'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-16'; Path = 'management.logAnalyticsWorkspaces'; Row = @{ disableLocalAuth = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SE-16 flags public ingestion'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-16'; Path = 'management.logAnalyticsWorkspaces'; Row = @{ publicNetworkAccessForIngestion = 'Enabled' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SE-16 passes a security perimeter'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-16'; Path = 'management.logAnalyticsWorkspaces'; Row = @{ publicNetworkAccessForIngestion = 'SecuredByPerimeter'; publicNetworkAccessForQuery = 'SecuredByPerimeter' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'SE-17 flags a null access-mode flag'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-17'; Path = 'management.logAnalyticsWorkspaces'; Row = @{ resourceContextAccess = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'CO-11 flags a daily cap of -1 (none)'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-CO-11'; Path = 'management.logAnalyticsWorkspaces'; Row = @{ dailyQuotaGb = -1 }; Status = 'Fail'; Count = 1 }
        @{ Case = 'CO-11 flags a null daily cap'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-CO-11'; Path = 'management.logAnalyticsWorkspaces'; Row = @{ dailyQuotaGb = $null }; Status = 'Fail'; Count = 1 }
        # ---- Databricks ----
        @{ Case = 'SE-01 flags a null injection flag'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-01'; Path = 'domains.analytics.databricksWorkspaces'; Row = @{ vnetInjected = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'SE-03 flags a null no-public-IP flag'; Pattern = 'waf.analytics'; Id = 'WAF-ANALYTICS-SE-03'; Path = 'domains.analytics.databricksWorkspaces'; Row = @{ noPublicIp = $null }; Status = 'Fail'; Count = 1 }
        # ---- AI Search ----
        @{ Case = 'AISEARCH-SE-04 flags an empty identity type'; Pattern = 'waf.aisearch'; Id = 'WAF-AISEARCH-SE-04'; Path = 'domains.ai.searchServices'; Row = @{ identityType = '' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'AISEARCH-SE-04 flags identity None'; Pattern = 'waf.aisearch'; Id = 'WAF-AISEARCH-SE-04'; Path = 'domains.ai.searchServices'; Row = @{ identityType = 'None' }; Status = 'Fail'; Count = 1 }
        @{ Case = 'AISEARCH-SE-04 passes a user-assigned identity'; Pattern = 'waf.aisearch'; Id = 'WAF-AISEARCH-SE-04'; Path = 'domains.ai.searchServices'; Row = @{ identityType = 'UserAssigned' }; Status = 'Pass'; Count = 0 }
        @{ Case = 'AISEARCH-SE-11 flags public access with a null rule count'; Pattern = 'waf.aisearch'; Id = 'WAF-AISEARCH-SE-11'; Path = 'domains.ai.searchServices'; Row = @{ publicAccess = 'Enabled'; ipRuleCount = $null }; Status = 'Fail'; Count = 1 }
        @{ Case = 'AISEARCH-SE-11 flags public access (lower case) with no rules'; Pattern = 'waf.aisearch'; Id = 'WAF-AISEARCH-SE-11'; Path = 'domains.ai.searchServices'; Row = @{ publicAccess = 'enabled'; ipRuleCount = 0 }; Status = 'Fail'; Count = 1 }
        @{ Case = 'AISEARCH-SE-11 passes public access with a rule'; Pattern = 'waf.aisearch'; Id = 'WAF-AISEARCH-SE-11'; Path = 'domains.ai.searchServices'; Row = @{ publicAccess = 'Enabled'; ipRuleCount = 2 }; Status = 'Pass'; Count = 0 }
        @{ Case = 'AISEARCH-SE-11 passes a security perimeter with a null rule count'; Pattern = 'waf.aisearch'; Id = 'WAF-AISEARCH-SE-11'; Path = 'domains.ai.searchServices'; Row = @{ publicAccess = 'SecuredByPerimeter'; ipRuleCount = $null }; Status = 'Pass'; Count = 0 }
        # ---- Machine Learning ----
        @{ Case = 'ML-SE-14 lists a null encryption status'; Pattern = 'waf.machinelearning'; Id = 'WAF-ML-SE-14'; Path = 'domains.ai.mlWorkspaces'; Row = @{ cmkStatus = $null }; Status = 'Manual'; Count = 1 }
        @{ Case = 'ML-SE-14 lists Disabled'; Pattern = 'waf.machinelearning'; Id = 'WAF-ML-SE-14'; Path = 'domains.ai.mlWorkspaces'; Row = @{ cmkStatus = 'Disabled' }; Status = 'Manual'; Count = 1 }
        @{ Case = 'ML-SE-14 does not list a Foundry project workspace'; Pattern = 'waf.machinelearning'; Id = 'WAF-ML-SE-14'; Path = 'domains.ai.mlWorkspaces'; Row = @{ workspaceKind = 'Project'; cmkStatus = '' }; Status = 'Manual'; Count = 0 }
    ) {
        # NOT $row: variable names are case-insensitive and the case table already binds $Row
        $merged = [ordered]@{}
        foreach ($k in $script:Baseline[$Path].Keys) { $merged[$k] = $script:Baseline[$Path][$k] }
        foreach ($k in $Row.Keys) { $merged[$k] = $Row[$k] }
        $collect = Get-TestCollectAt -Path $Path -Rows @($merged)
        $findings = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern $Pattern -Collect $collect -Assessment 'edge')
        @($findings.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
        $findings[$Id].Status | Should -Be $Status
        $findings[$Id].EvidenceCount | Should -Be $Count
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
        @{ File = 'waf.machinelearning'; Auto = 6 }
        @{ File = 'waf.aisearch'; Auto = 8 }
        @{ File = 'waf.analytics'; Auto = 19 }
        @{ File = 'waf.dataservices'; Auto = 51 }
    ) {
        $findings = $script:Empty[$File]
        @($findings | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Error' }).Count | Should -Be 0
        @($findings | Where-Object Status -eq 'NotAssessed').Count | Should -Be $Auto
    }

    It '<File> returns every other rule as Manual' -ForEach @(
        @{ File = 'waf.machinelearning'; Manual = 38 }
        @{ File = 'waf.aisearch'; Manual = 29 }
        @{ File = 'waf.analytics'; Manual = 55 }
        @{ File = 'waf.dataservices'; Manual = 53 }
    ) {
        @($script:Empty[$File] | Where-Object Status -eq 'Manual').Count | Should -Be $Manual
    }
}

Describe 'Technology review: per-resource ARM reads and diagnostic coverage (phase 4 batch 2)' {
    BeforeAll {
        $p = $script:P
        # Build a collect object from dotted-path datasets. Every dataset the rule gates on carries its
        # sibling <name>Measured flag, set from -Flags, exactly as the collect pipeline shapes it.
        function New-TestCollect {
            param([hashtable] $Data, [hashtable] $Flags = @{})
            $root = [ordered]@{}
            foreach ($entry in @($Data.GetEnumerator()) + @($Flags.GetEnumerator())) {
                $segments = @($entry.Key -split '\.')
                $cursor = $root
                for ($i = 0; $i -lt $segments.Count - 1; $i++) {
                    if (-not $cursor.Contains($segments[$i])) { $cursor[$segments[$i]] = [ordered]@{} }
                    $cursor = $cursor[$segments[$i]]
                }
                $cursor[$segments[-1]] = $entry.Value
            }
            $root
        }
        function Get-Coverage { param([string] $Type, [double] $Pct) [ordered]@{ type = $Type; total = 2; withDiag = [int]($Pct / 50); coveragePct = $Pct } }
        $script:Sa = "$p/Microsoft.Storage/storageAccounts/edge".ToLowerInvariant()
        $script:Sql = "$p/Microsoft.Sql/servers/edge".ToLowerInvariant()
        $script:Eh = "$p/Microsoft.EventHub/namespaces/edge"
        $script:Red = "$p/Microsoft.Cache/redisEnterprise/edge"
        function New-BlobRow { param([hashtable] $Over = @{}) $r = [ordered]@{ storageAccountId = $script:Sa; name = 'edge'; deleteRetentionEnabled = $true; deleteRetentionDays = 14; containerDeleteRetentionEnabled = $true; containerDeleteRetentionDays = 14; versioningEnabled = $true; changeFeedEnabled = $true; pointInTimeRestoreEnabled = $true }; foreach ($k in $Over.Keys) { $r[$k] = $Over[$k] }; $r }
        function New-ClassicCache { param($KeyAuthOff) [ordered]@{ id = "$p/Microsoft.Cache/Redis/classic"; name = 'classic'; type = 'microsoft.cache/redis'; sku = 'Premium'; publicNetworkAccess = 'Disabled'; minimumTlsVersion = '1.2'; nonSslPortEnabled = $false; accessKeyAuthDisabled = $KeyAuthOff; highAvailability = '' } }
        function New-EnterpriseCache { [ordered]@{ id = $script:Red; name = 'edge'; type = 'microsoft.cache/redisenterprise'; sku = 'Balanced_B5'; publicNetworkAccess = 'Disabled'; minimumTlsVersion = '1.2'; nonSslPortEnabled = $null; accessKeyAuthDisabled = $null; highAvailability = 'Enabled' } }
        function New-RedisDb { param($Keys, $Protocol) [ordered]@{ redisEnterpriseId = $script:Red.ToLowerInvariant(); name = 'default'; clusterName = 'edge'; accessKeysAuthentication = $Keys; clientProtocol = $Protocol; persistenceAofEnabled = $false; persistenceRdbEnabled = $false; geoReplicationLinkCount = 0 } }
        function New-EhNamespace { param($Geo, $Id = $script:Eh) [ordered]@{ id = $Id; name = 'edge'; zoneRedundant = $true; geoReplicaCount = $Geo; skuName = 'Premium' } }
        function New-GeoDr { param($Configured, $Id = $script:Eh.ToLowerInvariant()) [ordered]@{ eventHubNamespaceId = $Id; name = 'edge'; geoDrConfigured = $Configured } }
    }

    It '<Case>' -ForEach @(
        # ---- WAF-DATA-BLOB-10: blob service data protection ----
        @{ Case = 'BLOB-10 passes an account with all four protections on'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @(New-BlobRow) } @{ 'domains.storage.blobServicePropertiesMeasured' = $true } } }
        @{ Case = 'BLOB-10 flags blob soft delete off'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @(New-BlobRow @{ deleteRetentionEnabled = $false; deleteRetentionDays = $null }) } @{ 'domains.storage.blobServicePropertiesMeasured' = $true } } }
        @{ Case = 'BLOB-10 flags container soft delete off'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @(New-BlobRow @{ containerDeleteRetentionEnabled = $false }) } @{ 'domains.storage.blobServicePropertiesMeasured' = $true } } }
        @{ Case = 'BLOB-10 flags versioning off'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @(New-BlobRow @{ versioningEnabled = $false }) } @{ 'domains.storage.blobServicePropertiesMeasured' = $true } } }
        @{ Case = 'BLOB-10 flags point-in-time restore off'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @(New-BlobRow @{ pointInTimeRestoreEnabled = $false }) } @{ 'domains.storage.blobServicePropertiesMeasured' = $true } } }
        @{ Case = 'BLOB-10 is NotAssessed, never Pass, when the blob service was never read'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @() } @{ 'domains.storage.blobServicePropertiesMeasured' = $false } } }
        @{ Case = 'BLOB-10 is NotAssessed when rows exist but the Measured flag is false'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @(New-BlobRow @{ versioningEnabled = $false }) } @{ 'domains.storage.blobServicePropertiesMeasured' = $false } } }
        @{ Case = 'BLOB-10 passes when the read answered but no account had a blob service'; Id = 'WAF-DATA-BLOB-10'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.storage.blobServiceProperties' = @() } @{ 'domains.storage.blobServicePropertiesMeasured' = $true } } }
        # ---- WAF-DATA-SQL-02: failover groups ----
        @{ Case = 'SQL-02 flags a server with no failover group'; Id = 'WAF-DATA-SQL-02'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.databases.sqlFailoverGroups' = @([ordered]@{ sqlServerId = $script:Sql; name = 'edge'; failoverGroupCount = 0; automaticFailoverGroupCount = 0; hasAutomaticFailover = $false }) } @{ 'domains.databases.sqlFailoverGroupsMeasured' = $true } } }
        @{ Case = 'SQL-02 passes a server in a failover group'; Id = 'WAF-DATA-SQL-02'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.sqlFailoverGroups' = @([ordered]@{ sqlServerId = $script:Sql; name = 'edge'; failoverGroupCount = 1; automaticFailoverGroupCount = 0; hasAutomaticFailover = $false }) } @{ 'domains.databases.sqlFailoverGroupsMeasured' = $true } } }
        @{ Case = 'SQL-02 is NotAssessed when the failover groups were never read'; Id = 'WAF-DATA-SQL-02'; Pattern = 'waf.dataservices'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.sqlFailoverGroups' = @() } @{ 'domains.databases.sqlFailoverGroupsMeasured' = $false } } }
        # ---- WAF-DATA-SQL-11: auditing ----
        @{ Case = 'SQL-11 passes an audited server'; Id = 'WAF-DATA-SQL-11'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.sqlServerAuditing' = @([ordered]@{ sqlServerId = $script:Sql; name = 'edge'; auditingState = 'Enabled'; azureMonitorTargetEnabled = $true }) } @{ 'domains.databases.sqlServerAuditingMeasured' = $true } } }
        @{ Case = 'SQL-11 flags auditing Disabled'; Id = 'WAF-DATA-SQL-11'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.databases.sqlServerAuditing' = @([ordered]@{ sqlServerId = $script:Sql; name = 'edge'; auditingState = 'Disabled'; azureMonitorTargetEnabled = $false }) } @{ 'domains.databases.sqlServerAuditingMeasured' = $true } } }
        @{ Case = 'SQL-11 flags an auditing state the service did not return (null)'; Id = 'WAF-DATA-SQL-11'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.databases.sqlServerAuditing' = @([ordered]@{ sqlServerId = $script:Sql; name = 'edge'; auditingState = $null; azureMonitorTargetEnabled = $false }) } @{ 'domains.databases.sqlServerAuditingMeasured' = $true } } }
        @{ Case = 'SQL-11 is NotAssessed when auditing was never read'; Id = 'WAF-DATA-SQL-11'; Pattern = 'waf.dataservices'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.sqlServerAuditing' = @() } @{ 'domains.databases.sqlServerAuditingMeasured' = $false } } }
        # ---- WAF-DATA-RED-06 / RED-07: classic caches and Redis Enterprise databases in one query ----
        @{ Case = 'RED-06 assesses a classic-only estate with no Enterprise sweep (flag false = keys on)'; Id = 'WAF-DATA-RED-06'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @(New-ClassicCache $false); 'domains.databases.redisEnterpriseDatabases' = @() } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $false } } }
        @{ Case = 'RED-06 passes a classic cache with access keys disabled and no Enterprise sweep'; Id = 'WAF-DATA-RED-06'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @(New-ClassicCache $true); 'domains.databases.redisEnterpriseDatabases' = @() } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $false } } }
        @{ Case = 'RED-06 flags a Redis Enterprise database with access keys Enabled and never the cluster row'; Id = 'WAF-DATA-RED-06'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @(New-EnterpriseCache); 'domains.databases.redisEnterpriseDatabases' = @(New-RedisDb 'Enabled' 'Encrypted') } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $true } } }
        @{ Case = 'RED-06 passes a Redis Enterprise database with access keys Disabled'; Id = 'WAF-DATA-RED-06'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @(New-EnterpriseCache); 'domains.databases.redisEnterpriseDatabases' = @(New-RedisDb 'Disabled' 'Encrypted') } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $true } } }
        @{ Case = 'RED-06 is NotAssessed when only Redis Enterprise clusters exist and their databases were never read'; Id = 'WAF-DATA-RED-06'; Pattern = 'waf.dataservices'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @(New-EnterpriseCache); 'domains.databases.redisEnterpriseDatabases' = @() } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $false } } }
        @{ Case = 'RED-06 counts both a bad classic cache and a bad Enterprise database'; Id = 'WAF-DATA-RED-06'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 2; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @((New-ClassicCache $false), (New-EnterpriseCache)); 'domains.databases.redisEnterpriseDatabases' = @(New-RedisDb 'Enabled' 'Encrypted') } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $true } } }
        @{ Case = 'RED-07 flags a Redis Enterprise database that allows plaintext clients'; Id = 'WAF-DATA-RED-07'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @(New-EnterpriseCache); 'domains.databases.redisEnterpriseDatabases' = @(New-RedisDb 'Disabled' 'Plaintext') } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $true } } }
        @{ Case = 'RED-07 passes a Redis Enterprise database that requires encrypted clients'; Id = 'WAF-DATA-RED-07'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.databases.redisCaches' = @(New-EnterpriseCache); 'domains.databases.redisEnterpriseDatabases' = @(New-RedisDb 'Disabled' 'Encrypted') } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $true } } }
        @{ Case = 'RED-02 stays Manual and attaches the Enterprise databases'; Id = 'WAF-DATA-RED-02'; Pattern = 'waf.dataservices'; Status = 'Manual'; Count = 1; Build = { New-TestCollect @{ 'domains.databases.redisEnterpriseDatabases' = @(New-RedisDb 'Disabled' 'Encrypted') } @{ 'domains.databases.redisEnterpriseDatabasesMeasured' = $true } } }
        # ---- WAF-ANALYTICS-RE-07: Event Hubs geo-DR, joined to geo-replication ----
        @{ Case = 'RE-07 flags a namespace with neither a geo-DR pairing nor geo-replication'; Id = 'WAF-ANALYTICS-RE-07'; Pattern = 'waf.analytics'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'domains.integration.eventHubGeoDr' = @(New-GeoDr $false); 'domains.integration.eventHubNamespaces' = @(New-EhNamespace 1) } @{ 'domains.integration.eventHubGeoDrMeasured' = $true } } }
        @{ Case = 'RE-07 passes a namespace that is paired'; Id = 'WAF-ANALYTICS-RE-07'; Pattern = 'waf.analytics'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.integration.eventHubGeoDr' = @(New-GeoDr $true); 'domains.integration.eventHubNamespaces' = @(New-EhNamespace 1) } @{ 'domains.integration.eventHubGeoDrMeasured' = $true } } }
        @{ Case = 'RE-07 passes an unpaired namespace that uses geo-replication, whatever the id casing'; Id = 'WAF-ANALYTICS-RE-07'; Pattern = 'waf.analytics'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'domains.integration.eventHubGeoDr' = @(New-GeoDr $false $script:Eh.ToUpperInvariant()); 'domains.integration.eventHubNamespaces' = @(New-EhNamespace 2) } @{ 'domains.integration.eventHubGeoDrMeasured' = $true } } }
        @{ Case = 'RE-07 is NotAssessed when geo-DR was never read'; Id = 'WAF-ANALYTICS-RE-07'; Pattern = 'waf.analytics'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'domains.integration.eventHubGeoDr' = @(); 'domains.integration.eventHubNamespaces' = @(New-EhNamespace 1) } @{ 'domains.integration.eventHubGeoDrMeasured' = $false } } }
        # ---- diagnostic-settings coverage of the newly swept types ----
        @{ Case = 'ML-OE-07 flags a workspace with no diagnostic setting'; Id = 'WAF-ML-OE-07'; Pattern = 'waf.machinelearning'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.machinelearningservices/workspaces' 50) } } }
        @{ Case = 'ML-OE-07 passes full coverage'; Id = 'WAF-ML-OE-07'; Pattern = 'waf.machinelearning'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.machinelearningservices/workspaces' 100) } } }
        @{ Case = 'ML-OE-07 is NotAssessed when no workspace was checked, even if other types were'; Id = 'WAF-ML-OE-07'; Pattern = 'waf.machinelearning'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.databricks/workspaces' 0) } } }
        @{ Case = 'AISEARCH-SE-10 flags a search service with no diagnostic setting'; Id = 'WAF-AISEARCH-SE-10'; Pattern = 'waf.aisearch'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.search/searchservices' 0) } } }
        @{ Case = 'AISEARCH-SE-10 passes full coverage'; Id = 'WAF-AISEARCH-SE-10'; Pattern = 'waf.aisearch'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.search/searchservices' 100) } } }
        @{ Case = 'AISEARCH-SE-10 is NotAssessed with no coverage rows'; Id = 'WAF-AISEARCH-SE-10'; Pattern = 'waf.aisearch'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @() } } }
        @{ Case = 'ANALYTICS-OE-03 flags a Databricks workspace with no diagnostic setting'; Id = 'WAF-ANALYTICS-OE-03'; Pattern = 'waf.analytics'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.databricks/workspaces' 50) } } }
        @{ Case = 'ANALYTICS-OE-03 passes full coverage'; Id = 'WAF-ANALYTICS-OE-03'; Pattern = 'waf.analytics'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.databricks/workspaces' 100) } } }
        @{ Case = 'DATA-MI-08 flags a managed instance with no diagnostic setting'; Id = 'WAF-DATA-MI-08'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.sql/managedinstances' 0) } } }
        @{ Case = 'DATA-MI-08 passes full coverage'; Id = 'WAF-DATA-MI-08'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.sql/managedinstances' 100) } } }
        @{ Case = 'DATA-MI-08 is NotAssessed when only SQL servers (not managed instances) were checked'; Id = 'WAF-DATA-MI-08'; Pattern = 'waf.dataservices'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.sql/servers' 0) } } }
        @{ Case = 'DATA-RED-08 flags a classic Redis cache with no diagnostic setting'; Id = 'WAF-DATA-RED-08'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.cache/redis' 0) } } }
        @{ Case = 'DATA-RED-08 flags a Redis Enterprise cluster with no diagnostic setting'; Id = 'WAF-DATA-RED-08'; Pattern = 'waf.dataservices'; Status = 'Fail'; Count = 1; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.cache/redisenterprise' 50) } } }
        @{ Case = 'DATA-RED-08 passes when both Redis types are fully covered'; Id = 'WAF-DATA-RED-08'; Pattern = 'waf.dataservices'; Status = 'Pass'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @((Get-Coverage 'microsoft.cache/redis' 100), (Get-Coverage 'microsoft.cache/redisenterprise' 100)) } } }
        @{ Case = 'DATA-RED-08 is NotAssessed when no Redis type was checked'; Id = 'WAF-DATA-RED-08'; Pattern = 'waf.dataservices'; Status = 'NotAssessed'; Count = 0; Build = { New-TestCollect @{ 'opsPosture.diagnosticCoverage' = @(Get-Coverage 'microsoft.storage/storageaccounts' 0) } } }
    ) {
        $collect = & $Build
        $findings = ConvertTo-ById (Invoke-ScoutTestRuleSet -Pattern $Pattern -Collect $collect -Assessment 'phase4b2')
        @($findings.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
        $findings[$Id].Status | Should -Be $Status
        $findings[$Id].EvidenceCount | Should -Be $Count
    }
}
