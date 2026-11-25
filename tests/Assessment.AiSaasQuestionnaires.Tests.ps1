#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: four questionnaire-style Microsoft assessments -- the Azure Well-Architected SaaS workload,
    the AI Readiness Assessment, the Technical Assessment for Generative AI in Azure and the GenAIOps
    Maturity Model Assessment.

    Microsoft does not publish these assessments' question text, so every rule is Scout-derived and is
    mostly `manual: true`, answered through -AssessmentAnswers. Pinned here:
      - rule ids are unique inside each file and across every rule file, each is enumerated in its
        docs/frameworks page (and the page lists nothing else), and title and remediation start with the id;
      - every manual rule is exported as a question by Get-ScoutAssessmentQuestion, and answering the
        questions scores them (Set-ScoutFindingAnswer then Get-Score);
      - every automated rule passes on a clean collect, fails on a broken one, and reports NotAssessed on
        an estate without the resources it judges;
      - no rule errors.

    The collect objects below are built here from the collect.json contract in
    src/collect/Invoke-Collect.ps1. They are not captured from a live estate.
#>

BeforeDiscovery {
    $script:SetCases = @(
        @{ Name = 'Workload: SaaS'; Pattern = 'waf.saas'; Framework = 'WAF-SAAS'; Area = 'SaaS workload'; Doc = 'waf-saas-checklist.md'
            Total = 108; NAuto = 13; NManual = 95
            AreaCounts = @{ BC = 10; GV = 10; RO = 7; ID = 10; CP = 10; NW = 10; DT = 14; DO = 12; IM = 13; AI = 12 } }
        @{ Name = 'Microsoft: AI Readiness'; Pattern = 'ai.readiness'; Framework = 'AI-READINESS'; Area = 'AI readiness'; Doc = 'ai-readiness-question-set.md'
            Total = 64; NAuto = 11; NManual = 53
            AreaCounts = @{ BS = 8; GS = 12; DF = 8; SX = 8; OC = 8; IN = 10; MM = 10 } }
        @{ Name = 'Microsoft: Generative AI Technical'; Pattern = 'genai.technical'; Framework = 'GENAI-TECH'; Area = 'Generative AI technical readiness'; Doc = 'genai-technical-question-set.md'
            Total = 50; NAuto = 10; NManual = 40
            AreaCounts = @{ TS = 5; SD = 8; DG = 6; SE = 10; RA = 6; RC = 5; OP = 6; CO = 4 } }
        @{ Name = 'Microsoft: GenAIOps Maturity'; Pattern = 'genaiops.maturity'; Framework = 'GENAIOPS'; Area = 'GenAIOps maturity'; Doc = 'genaiops-maturity-question-set.md'
            Total = 30; NAuto = 2; NManual = 28
            AreaCounts = @{ PD = 4; AM = 4; EV = 4; DP = 4; MN = 4; CS = 5; RM = 5 } }
    )

    # One row per automated rule: the number of evidence rows it reports on the broken estate.
    $script:FailCases = @(
        @{ Pattern = 'waf.saas'; Id = 'SAAS-BC-05'; Evidence = 0 }   # budgets available, none exist
        @{ Pattern = 'waf.saas'; Id = 'SAAS-GV-02'; Evidence = 0 }   # policy data available, no assignment
        @{ Pattern = 'waf.saas'; Id = 'SAAS-GV-03'; Evidence = 0 }   # lock data available, no lock
        @{ Pattern = 'waf.saas'; Id = 'SAAS-GV-04'; Evidence = 1 }   # Defender CSPM on Free
        @{ Pattern = 'waf.saas'; Id = 'SAAS-CP-05'; Evidence = 1 }   # one disabled autoscale setting
        @{ Pattern = 'waf.saas'; Id = 'SAAS-CP-08'; Evidence = 1 }   # one zone-capable VM with no zone; a VM in a region without zones is not scored
        @{ Pattern = 'waf.saas'; Id = 'SAAS-CP-09'; Evidence = 1 }   # one AKS cluster with an unzoned pool
        @{ Pattern = 'waf.saas'; Id = 'SAAS-NW-03'; Evidence = 1 }   # one Application Gateway without WAF
        @{ Pattern = 'waf.saas'; Id = 'SAAS-NW-05'; Evidence = 1 }   # one storage account open to all networks
        @{ Pattern = 'waf.saas'; Id = 'SAAS-DT-09'; Evidence = 1 }   # SQL server with public access
        @{ Pattern = 'waf.saas'; Id = 'SAAS-DT-10'; Evidence = 1 }   # Cosmos DB account with public access
        @{ Pattern = 'waf.saas'; Id = 'SAAS-DT-11'; Evidence = 1 }   # Cosmos DB account with keys enabled
        @{ Pattern = 'waf.saas'; Id = 'SAAS-IM-04'; Evidence = 1 }   # one disabled action group
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-GS-04'; Evidence = 0 }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-GS-05'; Evidence = 1 }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-GS-06'; Evidence = 1 }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-GS-07'; Evidence = 1 }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-GS-08'; Evidence = 0 }   # Defender for AI services on Free
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-DF-02'; Evidence = 0 }   # storage exists, no Purview account
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-DF-07'; Evidence = 1 }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-IN-04'; Evidence = 1 }   # AI account with no private endpoint
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-IN-05'; Evidence = 1 }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-IN-06'; Evidence = 1 }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-IN-07'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-DG-03'; Evidence = 1 }   # free-tier search service
        @{ Pattern = 'genai.technical'; Id = 'GENAI-DG-04'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-DG-05'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-SE-01'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-SE-02'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-SE-03'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-SE-04'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-SE-05'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-SE-06'; Evidence = 1 }
        @{ Pattern = 'genai.technical'; Id = 'GENAI-SE-07'; Evidence = 0 }
        @{ Pattern = 'genaiops.maturity'; Id = 'GENAIOPS-CS-05'; Evidence = 0 }
        @{ Pattern = 'genaiops.maturity'; Id = 'GENAIOPS-RM-05'; Evidence = 0 }
    )

    # Automated rules whose gate is an AI resource: they must go quiet when only the AI resources are removed.
    $script:AiGatedIds = @(
        'AIRDY-GS-05', 'AIRDY-GS-06', 'AIRDY-GS-07', 'AIRDY-GS-08', 'AIRDY-IN-04', 'AIRDY-IN-05', 'AIRDY-IN-06', 'AIRDY-IN-07'
        'GENAI-DG-03', 'GENAI-DG-04', 'GENAI-DG-05', 'GENAI-SE-01', 'GENAI-SE-02', 'GENAI-SE-03', 'GENAI-SE-04', 'GENAI-SE-05', 'GENAI-SE-06', 'GENAI-SE-07'
        'GENAIOPS-CS-05'
    )

    # Per set: the automated rules the failure table must cover, and the ones gated on AI resources.
    foreach ($case in $script:SetCases) {
        $case.FailIds = @($script:FailCases | Where-Object { $_.Pattern -eq $case.Pattern } | ForEach-Object { $_.Id })
        # GENAI- does not match GENAIOPS-: the character after GENAI differs.
        $idPattern = @{ 'waf.saas' = '^SAAS-'; 'ai.readiness' = '^AIRDY-'; 'genai.technical' = '^GENAI-'; 'genaiops.maturity' = '^GENAIOPS-' }[$case.Pattern]
        $case.IdPattern = $idPattern
        $case.Prefix = $idPattern.TrimStart('^')
        $case.AiIds = @($script:AiGatedIds | Where-Object { $_ -match $idPattern })
    }
}

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml

    # The real manifests/assessments.psd1 entries are added by the caller; the questionnaire export is
    # exercised here against an equivalent manifest built in the test.
    $script:Manifest = @{
        'Workload: SaaS'                     = @{ Rules = @('waf.saas'); Category = 'Management'; Collect = @('*'); Ingest = @('Governance') }
        'Microsoft: AI Readiness'            = @{ Rules = @('ai.readiness'); Category = 'AI'; Collect = @('*'); Ingest = @('Governance') }
        'Microsoft: Generative AI Technical' = @{ Rules = @('genai.technical'); Category = 'AI'; Collect = @('*'); Ingest = @('Governance') }
        'Microsoft: GenAIOps Maturity'       = @{ Rules = @('genaiops.maturity'); Category = 'AI'; Collect = @('*'); Ingest = @('Governance') }
    }

    $script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'

    function Invoke-ScoutTestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    function ConvertTo-ScoutFindingMap {
        param($Findings)
        $map = @{}
        foreach ($f in $Findings) { $map[[string]$f.Id] = $f }
        $map
    }

    # Builds a collect object. Clean passes every automated rule; Bad breaks each exactly once (one
    # offending row per dataset, plus a healthy or out-of-scope neighbour that must NOT be counted);
    # Empty has none of the gating resources and reports every availability flag false.
    function Get-EstateFixture {
        param([ValidateSet('Clean', 'Bad', 'Empty')] [string] $Mode)

        $emptyCollect = [ordered]@{
            subscriptions = @(); tags = @()
            governance    = [ordered]@{
                policyAssignments = @(); policyAssignmentsAvailable = $false; resourceLocks = @(); resourceLocksAvailable = $false
                budgets = @(); budgetsAvailable = $false; roleAssignments = @(); roleAssignmentsAvailable = $false; managementGroups = @()
            }
            security      = [ordered]@{ defenderPlans = @(); ddosProtectionPlans = @() }
            monitor       = [ordered]@{ autoscaleSettings = @(); actionGroups = @(); metricAlertRules = @(); appInsights = @() }
            compute       = [ordered]@{ virtualMachines = @() }
            networking    = [ordered]@{ applicationGateways = @(); privateEndpoints = @(); nsgPublicInbound = @(); natGateways = @() }
            management    = [ordered]@{ deployments = @(); managedApplications = @(); logAnalyticsWorkspaces = @() }
            finops        = [ordered]@{ reservations = @(); anomalies = @() }
            costCleanup   = [ordered]@{ orphanedDisks = @(); orphanedPips = @() }
            opsPosture    = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $false }
            domains       = [ordered]@{
                storage   = [ordered]@{ storageAccounts = @() }
                databases = [ordered]@{ sqlServers = @(); sqlDatabases = @(); cosmosDbAccounts = @() }
                containers = [ordered]@{ aksClusters = @() }
                identity  = [ordered]@{ managedIdentities = @() }
                integration = [ordered]@{ apiManagement = @() }
                analytics = [ordered]@{ purviewAccounts = @(); dataFactories = @(); fabricCapacities = @() }
                ai        = [ordered]@{ cognitiveAccounts = @(); mlWorkspaces = @(); searchServices = @() }
            }
        }
        if ($Mode -eq 'Empty') { return $emptyCollect }

        $bad = $Mode -eq 'Bad'
        $aoai = "$script:Sub/Microsoft.CognitiveServices/accounts/aoai1"
        $c = $emptyCollect

        $c.subscriptions = @([ordered]@{ id = 'sub1' })
        $c.governance.policyAssignmentsAvailable = $true; $c.governance.resourceLocksAvailable = $true
        $c.governance.budgetsAvailable = $true; $c.governance.roleAssignmentsAvailable = $true
        if (-not $bad) {
            $c.governance.policyAssignments = @([ordered]@{ id = 'pa1'; name = 'policy' })
            $c.governance.resourceLocks = @([ordered]@{ name = 'lock1' })
            $c.governance.budgets = @([ordered]@{ name = 'budget1' })
            $c.domains.analytics.purviewAccounts = @([ordered]@{ name = 'purview1' })
        }

        $tier = if ($bad) { 'Free' } else { 'Standard' }
        $c.security.defenderPlans = @(
            [ordered]@{ name = 'CloudPosture'; properties = [ordered]@{ pricingTier = $tier } }
            [ordered]@{ name = 'AI'; properties = [ordered]@{ pricingTier = $tier } }
        )

        $c.monitor.autoscaleSettings = @([ordered]@{ id = 'as1'; enabled = (-not $bad) })
        $c.monitor.actionGroups = @([ordered]@{ id = 'ag1'; enabled = (-not $bad) })

        # vm-nozones sits in a region without availability zones: broken in BOTH variants and never scored.
        $c.compute.virtualMachines = @(
            [ordered]@{ id = "$script:Sub/Microsoft.Compute/virtualMachines/vm1"; name = 'vm1'; zoneEligible = $true; zoneRedundant = (-not $bad) }
            [ordered]@{ id = "$script:Sub/Microsoft.Compute/virtualMachines/vm-nozones"; name = 'vm-nozones'; zoneEligible = $false; zoneRedundant = $false }
        )
        $c.domains.containers.aksClusters = @([ordered]@{ name = 'aks1'; allPoolsZoned = (-not $bad) })
        $c.networking.applicationGateways = @([ordered]@{ id = 'agw1'; wafEnabled = (-not $bad) })
        $c.domains.storage.storageAccounts = @([ordered]@{ id = 'sa1'; name = 'sa1'; networkDefaultDeny = (-not $bad); publicAccess = $false })

        $publicState = if ($bad) { 'Enabled' } else { 'Disabled' }
        $c.domains.databases.sqlServers = @([ordered]@{ name = 'sql1'; publicNetworkAccess = $publicState })
        $c.domains.databases.cosmosDbAccounts = @([ordered]@{ id = 'cosmos1'; name = 'cosmos1'; publicNetworkAccess = $publicState; disableLocalAuth = (-not $bad) })
        $c.domains.analytics.dataFactories = @([ordered]@{ name = 'adf1'; publicNetworkAccess = $publicState })

        $identity = if ($bad) { 'None' } else { 'SystemAssigned' }
        $c.domains.ai.cognitiveAccounts = @([ordered]@{
                id = $aoai; name = 'aoai1'; location = 'westeurope'; accountKind = 'OpenAI'; identityType = $identity
                publicAccess = $publicState; disableLocalAuth = (-not $bad); cmkEnabled = $true
            })
        # The private endpoint that covers the account exists only in the clean estate.
        if (-not $bad) { $c.networking.privateEndpoints = @([ordered]@{ targetResourceId = $aoai.ToUpperInvariant(); targetProvider = 'microsoft.cognitiveservices'; targetType = 'accounts' }) }

        $isolation = if ($bad) { 'Disabled' } else { 'AllowOnlyApprovedOutbound' }
        $c.domains.ai.mlWorkspaces = @([ordered]@{ id = 'ml1'; name = 'ml1'; workspaceKind = 'Default'; publicAccess = $publicState; identityType = 'SystemAssigned'; isolationMode = $isolation })
        $c.domains.ai.searchServices = @([ordered]@{
                id = 'search1'; name = 'search1'; sku = $(if ($bad) { 'free' } else { 'standard' })
                publicAccess = $(if ($bad) { 'enabled' } else { 'disabled' }); disableLocalAuth = (-not $bad); replicaCount = $(if ($bad) { 1 } else { 3 })
            })
        return $c
    }

    $script:Clean = Get-EstateFixture -Mode Clean
    $script:Bad = Get-EstateFixture -Mode Bad
    $script:Empty = Get-EstateFixture -Mode Empty

    # Per pattern: findings on each estate, the loaded rule set and the doc text.
    $script:Run = @{}
    foreach ($case in @(
            @{ Name = 'Workload: SaaS'; Pattern = 'waf.saas' }, @{ Name = 'Microsoft: AI Readiness'; Pattern = 'ai.readiness' }
            @{ Name = 'Microsoft: Generative AI Technical'; Pattern = 'genai.technical' }, @{ Name = 'Microsoft: GenAIOps Maturity'; Pattern = 'genaiops.maturity' })) {
        $script:Run[$case.Pattern] = @{
            Set   = @(& $script:Module { param($p) Get-RuleSet -Patterns $p } $case.Pattern)
            Clean = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern $case.Pattern -Collect $script:Clean -Assessment $case.Name)
            Bad   = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern $case.Pattern -Collect $script:Bad -Assessment $case.Name)
            Empty = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern $case.Pattern -Collect $script:Empty -Assessment $case.Name)
        }
    }
}

Describe 'Questionnaire assessments - rule file shape' {
    It '<Name> loads one rule set for framework <Framework> with <Total> rules' -ForEach $script:SetCases {
        $set = $script:Run[$Pattern].Set
        $set.Count | Should -Be 1
        $set[0].Framework | Should -Be $Framework
        $set[0].Area | Should -Be $Area
        $set[0].FrameworkVersion | Should -BeLike '*verified 2026-11-25*'
        @($set[0].Rules).Count | Should -Be $Total
        @($set[0].Rules.id | Select-Object -Unique).Count | Should -Be $Total
    }

    It '<Name> has <NAuto> automated and <NManual> manual rules, every automated one gated and every manual one flagged' -ForEach $script:SetCases {
        $rules = @($script:Run[$Pattern].Set[0].Rules)
        $auto = @($rules | Where-Object { -not $_.manual })
        $manual = @($rules | Where-Object { $_.manual })
        $auto.Count | Should -Be $NAuto
        $manual.Count | Should -Be $NManual
        foreach ($r in $auto) {
            $r.assert.ContainsKey('gate') | Should -BeTrue -Because "$($r.id) must report NotAssessed on an estate without the resources it judges"
            [string]::IsNullOrWhiteSpace([string]$r.assert.gate) | Should -BeFalse
            $r.assert.type | Should -Not -Be 'manual'
        }
        foreach ($r in $manual) { $r.assert.type | Should -Be 'manual' }
    }

    It '<Name> title and remediation start with the rule id, and every severity is valid' -ForEach $script:SetCases {
        foreach ($r in $script:Run[$Pattern].Set[0].Rules) {
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
            $r.severity | Should -BeIn 'high', 'medium', 'low'
        }
    }

    It '<Name> covers each area with the expected number of items' -ForEach $script:SetCases {
        $rules = @($script:Run[$Pattern].Set[0].Rules)
        foreach ($k in $AreaCounts.Keys) {
            @($rules | Where-Object { ([string]$_.id -split '-')[-2] -eq $k }).Count | Should -Be $AreaCounts[$k] -Because "area $k"
        }
        ($AreaCounts.Values | Measure-Object -Sum).Sum | Should -Be $Total
    }

    It '<Name> has every rule id enumerated in docs/frameworks/<Doc>, and the doc enumerates nothing else' -ForEach $script:SetCases {
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        $ids = @($script:Run[$Pattern].Set[0].Rules | ForEach-Object { [string]$_.id })
        foreach ($id in $ids) { $doc | Should -Match ([regex]::Escape($id)) }
        $prefix = ($ids[0] -split '-')[0]
        $docIds = @([regex]::Matches($doc, "\b$prefix-[A-Z]{2}-\d{2}\b") | ForEach-Object Value | Select-Object -Unique)
        $docIds.Count | Should -Be $Total
        @($docIds | Where-Object { $_ -notin $ids }).Count | Should -Be 0
    }

    It '<Name> doc carries the Shape B header and says the questions are Scout-derived' -ForEach $script:SetCases {
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        $doc | Should -Match '\*\*Enumerated 2026-11-25\.'
        $doc | Should -Match '\| Field \| Value \|'
        $doc | Should -Match '\| Framework version \|'
        $doc | Should -Match '\| Extraction date \| 2026-11-25 \|'
        $doc | Should -Match '\| Verification method \|'
        $doc | Should -Match 'Scout-derived'
    }
}

Describe 'Questionnaire assessments - ids are unique across every rule file' {
    It 'no rule id is used twice anywhere under src/assess/rules' {
        $seen = @{}
        $dupes = [System.Collections.Generic.List[string]]::new()
        foreach ($file in Get-ChildItem "$script:root/src/assess/rules" -Filter '*.yaml' -File) {
            $doc = ConvertFrom-Yaml (Get-Content $file.FullName -Raw)
            if ($null -eq $doc -or -not $doc.ContainsKey('rules')) { continue }
            foreach ($rule in @($doc.rules)) {
                $id = [string]$rule.id
                if ($seen.ContainsKey($id)) { $dupes.Add("$id ($($seen[$id]) and $($file.Name))") } else { $seen[$id] = $file.Name }
            }
        }
        $dupes | Should -BeNullOrEmpty
    }

    It '<Name> uses only ids that start with <Prefix>' -ForEach $script:SetCases {
        $ids = @($script:Run[$Pattern].Set[0].Rules | ForEach-Object { [string]$_.id })
        $ids.Count | Should -Be $Total
        foreach ($id in $ids) { $id.StartsWith($Prefix, [System.StringComparison]::Ordinal) | Should -BeTrue -Because $id }
    }
}

Describe 'Questionnaire assessments - manual questions export and score' {
    It '<Name> exports every manual rule exactly once through Get-ScoutAssessmentQuestion' -ForEach $script:SetCases {
        $rows = @(& $script:Module { param($n, $m) Get-ScoutAssessmentQuestion -Assessment $n -Manifest $m } $Name $script:Manifest)
        $rows.Count | Should -Be $NManual
        @($rows.RuleId | Select-Object -Unique).Count | Should -Be $NManual
        $manualIds = @($script:Run[$Pattern].Set[0].Rules | Where-Object { $_.manual } | ForEach-Object { [string]$_.id })
        foreach ($row in $rows) {
            $row.RuleId | Should -BeIn $manualIds
            $row.Question | Should -BeLike "$($row.RuleId). *"
            $row.Guidance | Should -BeLike "$($row.RuleId). *"
            $row.Framework | Should -Be $Framework
            $row.Area | Should -Be $Area
        }
    }

    It '<Name> leaves every manual rule Manual and out of the score until it is answered' -ForEach $script:SetCases {
        $findings = @($script:Run[$Pattern].Empty.Values)
        @($findings | Where-Object Status -eq 'Manual').Count | Should -Be $NManual
        $score = & $script:Module { param($f) Get-Score -Findings $f } $findings
        $area = @($score.Areas | Where-Object Area -eq $Area)[0]
        $area.Manual | Should -Be $NManual
    }

    It '<Name> scores answered questions: all Yes is 100, all No is 0, a mix is between, N/A is left out' -ForEach $script:SetCases {
        $manualIds = @($script:Run[$Pattern].Set[0].Rules | Where-Object { $_.manual } | ForEach-Object { [string]$_.id })
        $makeAnswers = {
            param([scriptblock] $Pick)
            $a = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
            $n = 0
            foreach ($id in $manualIds) {
                $word, $status = & $Pick $n
                $a[$id] = @{ Answer = $word; Status = $status; Note = ''; AnsweredBy = ''; AnsweredAt = '' }
                $n++
            }
            $a
        }
        $score = {
            param($Answers)
            $fresh = @(Invoke-ScoutTestRuleSet -Pattern $Pattern -Collect $script:Empty -Assessment $Name)
            $answered = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } $fresh $Answers)
            $result = & $script:Module { param($f) Get-Score -Findings $f } $answered
            [pscustomobject]@{ Findings = $answered; Area = @($result.Areas | Where-Object Area -eq $Area)[0] }
        }

        $yes = & $score (& $makeAnswers { 'Yes', 'Pass' })
        $yes.Area.Score | Should -Be 100
        $yes.Area.Manual | Should -Be 0
        @($yes.Findings | Where-Object { $_.Manual -and $_.Source -eq 'Answer' }).Count | Should -Be $NManual

        $no = & $score (& $makeAnswers { 'No', 'Fail' })
        $no.Area.Score | Should -Be 0

        $mix = & $score (& $makeAnswers { param($n) if ($n % 2) { 'Yes', 'Pass' } else { 'No', 'Fail' } })
        $mix.Area.Score | Should -BeGreaterThan 0
        $mix.Area.Score | Should -BeLessThan 100

        $na = & $score (& $makeAnswers { param($n) if ($n -eq 0) { 'N/A', 'NotApplicable' } else { 'Yes', 'Pass' } })
        @($na.Findings | Where-Object { $_.Id -eq $manualIds[0] })[0].Status | Should -Be 'NotAssessed'
        $na.Area.Score | Should -Be 100
    }

    It 'a manual answer never overrides an automated rule' {
        $fresh = @(Invoke-ScoutTestRuleSet -Pattern 'waf.saas' -Collect $script:Bad -Assessment 'Workload: SaaS')
        $answers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $answers['SAAS-CP-08'] = @{ Answer = 'Yes'; Status = 'Pass'; Note = 'trust me'; AnsweredBy = ''; AnsweredAt = '' }
        $out = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } $fresh $answers)
        $f = $out | Where-Object Id -eq 'SAAS-CP-08'
        $f.Status | Should -Be 'Fail'
        $f.Source | Should -Be 'Data'
    }
}

Describe 'Questionnaire assessments - automated rules' {
    It '<Name> produces no Error findings on a clean, a broken or an empty estate' -ForEach $script:SetCases {
        $run = $script:Run[$Pattern]
        @($run.Clean.Values + $run.Bad.Values + $run.Empty.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
        @($run.Clean.Values).Count | Should -Be $Total
    }

    It '<Name> passes every automated rule on the clean estate' -ForEach $script:SetCases {
        $auto = @($script:Run[$Pattern].Set[0].Rules | Where-Object { -not $_.manual })
        $auto.Count | Should -Be $NAuto
        foreach ($r in $auto) { $script:Run[$Pattern].Clean[[string]$r.id].Status | Should -Be 'Pass' -Because "$($r.id) on the clean collect" }
    }

    It '<Name> failure table covers every automated rule exactly once' -ForEach $script:SetCases {
        $auto = @($script:Run[$Pattern].Set[0].Rules | Where-Object { -not $_.manual } | ForEach-Object { [string]$_.id })
        @($FailIds | Sort-Object) | Should -Be @($auto | Sort-Object)
    }

    It 'scores <Id> as Fail on the broken estate with <Evidence> evidence rows' -ForEach $script:FailCases {
        $f = $script:Run[$Pattern].Bad[$Id]
        $f.Status | Should -Be 'Fail'
        $f.EvidenceCount | Should -Be $Evidence
    }

    It '<Name> reports every automated rule NotAssessed on an estate without the resources it judges' -ForEach $script:SetCases {
        $run = $script:Run[$Pattern]
        foreach ($r in @($run.Set[0].Rules | Where-Object { -not $_.manual })) {
            $run.Empty[[string]$r.id].Status | Should -Be 'NotAssessed' -Because "$($r.id) must not pass or fail an estate without its resources"
        }
        @($run.Empty.Values | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Error', 'Unknown' }).Count | Should -Be 0
        @($run.Empty.Values | Where-Object Status -eq 'Manual').Count | Should -Be $NManual
    }

    It '<Name> leaves the AI-gated rules NotAssessed when only the AI resources are missing' -ForEach ($script:SetCases | Where-Object { $_.AiIds.Count -gt 0 }) {
        $noAi = Get-EstateFixture -Mode Bad
        $noAi.domains.ai = [ordered]@{ cognitiveAccounts = @(); mlWorkspaces = @(); searchServices = @() }
        $f = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern $Pattern -Collect $noAi -Assessment $Name)
        foreach ($id in $AiIds) { $f[$id].Status | Should -Be 'NotAssessed' -Because "$id keys on AI resources" }
        $AiIds.Count | Should -BeGreaterThan 0
    }

    It 'treats a private endpoint on an account as covering it, whatever the id casing' {
        $script:Run['ai.readiness'].Clean['AIRDY-IN-04'].Status | Should -Be 'Pass'
        $script:Run['genai.technical'].Clean['GENAI-SE-04'].Status | Should -Be 'Pass'
    }

    It 'does not score a VM in a region without availability zones' {
        $script:Run['waf.saas'].Clean['SAAS-CP-08'].Status | Should -Be 'Pass'
        $script:Run['waf.saas'].Bad['SAAS-CP-08'].EvidenceCount | Should -Be 1
    }

    It 'attaches Azure evidence to manual rules without scoring them' {
        $f = $script:Run['genai.technical'].Clean['GENAI-SD-06']
        $f.Status | Should -Be 'Manual'
        $f.EvidenceCount | Should -Be 1
        $script:Run['waf.saas'].Clean['SAAS-NW-02'].Status | Should -Be 'Manual'
    }
}
