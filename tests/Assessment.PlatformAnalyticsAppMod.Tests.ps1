#Requires -Version 7.0
#Requires -Modules Pester, powershell-yaml

<#
    AB#9300: three Microsoft assessments that are mostly organisational questionnaires:
      - Platform Engineering Technical Assessment   (platform.engineering.yaml,  PLATENG-*)
      - Analytics Journey Tracker                   (analytics.journey.yaml,     ANLJT-*)
      - App and Data Modernization Readiness Tool   (appmod.readiness.yaml,      APPMOD-*)

    Microsoft publishes none of the three assessments' question text, so every item is Scout's
    reading of the published guidance. This file pins that the enumerations in docs/frameworks and
    the rule files agree, that ids are unique across every rule file, that the manual questions
    reach the questionnaire export and score once answered, that each automated rule passes and
    fails on a built collect object, that gated rules report NotAssessed on an empty estate, and
    that nothing errors.

    The manifests/assessments.psd1 entries for these assessments are added separately, so the
    export test builds its own manifest hashtable.

    No Azure connection. Fixtures are built here; none is captured from a live estate.
#>

# Top-level so both Pester phases can see it: -ForEach data is built during Discovery.
function Get-AutomatedExpectation {
    @(
        # id, status on the good estate, status on the bad estate
        @{ Id = 'PLATENG-GOV-02'; Rules = 'platform.engineering'; GoodStatus = 'Pass'; BadStatus = 'Pass' }   # an assignment exists in both; the enforcement rule below is the one that differs
        @{ Id = 'PLATENG-GOV-03'; Rules = 'platform.engineering'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'PLATENG-GOV-07'; Rules = 'platform.engineering'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'PLATENG-GOV-08'; Rules = 'platform.engineering'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'PLATENG-PRV-01'; Rules = 'platform.engineering'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'PLATENG-PRV-02'; Rules = 'platform.engineering'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'ANLJT-GOV-10'; Rules = 'analytics.journey'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'ANLJT-GOV-11'; Rules = 'analytics.journey'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'ANLJT-GOV-12'; Rules = 'analytics.journey'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'ANLJT-GOV-13'; Rules = 'analytics.journey'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'ANLJT-GOV-14'; Rules = 'analytics.journey'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-INF-07'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-INF-08'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-PRC-01'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-PRC-05'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Pass' }
        @{ Id = 'APPMOD-DAT-08'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-DAT-09'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-APP-07'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-APP-08'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-AIR-06'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Fail' }
        @{ Id = 'APPMOD-SEC-04'; Rules = 'appmod.readiness'; GoodStatus = 'Pass'; BadStatus = 'Pass' }
    )
}

BeforeDiscovery {
    $script:AutomatedExpectations = @(Get-AutomatedExpectation)
    $expect = @(Get-AutomatedExpectation)
    $script:Cases = @(
        @{ Name = 'Microsoft: Platform Engineering'; Rules = 'platform.engineering'; AutoIds = @($expect | Where-Object { $_.Rules -eq 'platform.engineering' } | ForEach-Object { $_.Id }); Prefix = 'PLATENG'; Doc = 'platform-engineering-question-set.md'; Framework = 'PLATFORM-ENG'; Items = 36; Auto = 6; Manual = 30 }
        @{ Name = 'Microsoft: Analytics Journey Tracker'; Rules = 'analytics.journey'; AutoIds = @($expect | Where-Object { $_.Rules -eq 'analytics.journey' } | ForEach-Object { $_.Id }); Prefix = 'ANLJT'; Doc = 'analytics-journey-question-set.md'; Framework = 'ANALYTICS-JOURNEY'; Items = 52; Auto = 5; Manual = 47 }
        @{ Name = 'Microsoft: App and Data Modernization'; Rules = 'appmod.readiness'; AutoIds = @($expect | Where-Object { $_.Rules -eq 'appmod.readiness' } | ForEach-Object { $_.Id }); Prefix = 'APPMOD'; Doc = 'app-modernization-question-set.md'; Framework = 'APPMOD'; Items = 62; Auto = 10; Manual = 52 }
    )
}

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml -ErrorAction Stop

    $script:RuleDir = Join-Path $script:root 'src/assess/rules'
    $script:Manifest = @{
        'Microsoft: Platform Engineering'       = @{ Rules = @('platform.engineering'); Category = '*'; Collect = @('*'); Ingest = @(); Frameworks = @('x'); Tags = @(); Reporters = @('Html') }
        'Microsoft: Analytics Journey Tracker'  = @{ Rules = @('analytics.journey'); Category = '*'; Collect = @('*'); Ingest = @(); Frameworks = @('x'); Tags = @(); Reporters = @('Html') }
        'Microsoft: App and Data Modernization' = @{ Rules = @('appmod.readiness'); Category = '*'; Collect = @('*'); Ingest = @(); Frameworks = @('x'); Tags = @(); Reporters = @('Html') }
    }

    function Get-TestRuleDoc {
        param([string] $Rules)
        ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir "$Rules.yaml") -Raw)
    }

    function Invoke-TestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    function ConvertTo-TestFindingMap {
        param($Findings)
        $map = @{}
        foreach ($f in $Findings) { $map[[string]$f.Id] = $f }
        $map
    }

    $script:FactoryId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers/Microsoft.DataFactory/factories/adf1'

    # An estate where every gate the automated rules use is open and every rule passes.
    function New-GoodCollect {
        [ordered]@{
            governance = [ordered]@{
                policyAssignmentsAvailable = $true
                policyAssignments          = @([ordered]@{ properties = [ordered]@{ enforcementMode = 'Default' } })
                roleAssignmentsAvailable   = $true
                roleAssignments            = @([ordered]@{ properties = [ordered]@{ principalType = 'Group' } })
                budgetsAvailable           = $true
                budgets                    = @([ordered]@{ name = 'budget1' })
            }
            management = [ordered]@{ deployments = @([ordered]@{ name = 'd1'; properties = [ordered]@{ templateHash = '123456' } }) }
            devops     = [ordered]@{
                available    = $true
                pipelines    = @([ordered]@{ ConfigurationType = 'yaml' }, [ordered]@{ ConfigurationType = 'yaml' })
                repositories = @([ordered]@{ name = 'repo1' })
            }
            opsPosture = [ordered]@{
                diagnosticCoverageMeasured = $true
                diagnosticCoverage         = @([ordered]@{ type = 'microsoft.keyvault/vaults'; total = 2; withDiag = 2; coveragePct = 100 })
            }
            networking = [ordered]@{ privateEndpoints = @([ordered]@{ name = 'pe1'; targetResourceId = $script:FactoryId }) }
            domains    = [ordered]@{
                analytics   = [ordered]@{
                    dataFactories      = @([ordered]@{ id = $script:FactoryId; name = 'adf1'; publicNetworkAccess = 'Disabled'; identityType = 'SystemAssigned' })
                    synapseWorkspaces  = @([ordered]@{ name = 'syn1'; publicAccess = 'Disabled'; managedVnetEnabled = $true })
                    fabricCapacities   = @([ordered]@{ name = 'fab1'; sku = 'F2'; state = 'Active' })
                }
                databases   = [ordered]@{
                    sqlServers         = @([ordered]@{ name = 'sql1'; publicNetworkAccess = 'Disabled' })
                    sqlDefenderPricing = @([ordered]@{ pricingTier = 'Standard' })
                }
                web         = [ordered]@{ webApps = @([ordered]@{ name = 'app1'; httpsOnly = $true; minTls = '1.2' }) }
                integration = [ordered]@{ apiManagement = @([ordered]@{ name = 'apim1' }) }
            }
            compute = [ordered]@{ virtualMachines = @([ordered]@{ name = 'vm1'; osType = 'Linux' }) }
        }
    }

    # The same estate, broken in every way each automated rule can detect.
    function New-BadCollect {
        [ordered]@{
            governance = [ordered]@{
                policyAssignmentsAvailable = $true
                policyAssignments          = @([ordered]@{ properties = [ordered]@{ enforcementMode = 'DoNotEnforce' } })
                roleAssignmentsAvailable   = $true
                roleAssignments            = @(1..60 | ForEach-Object { [ordered]@{ properties = [ordered]@{ principalType = 'User' } } })
                budgetsAvailable           = $true
                budgets                    = @()
            }
            management = [ordered]@{ deployments = @([ordered]@{ name = 'd1'; properties = [ordered]@{ template = 'x' } }) }
            devops     = [ordered]@{
                available    = $true
                pipelines    = @([ordered]@{ ConfigurationType = 'designerJson' }, [ordered]@{ ConfigurationType = 'designerJson' })
                repositories = @()
            }
            opsPosture = [ordered]@{
                diagnosticCoverageMeasured = $true
                diagnosticCoverage         = @([ordered]@{ type = 'microsoft.keyvault/vaults'; total = 2; withDiag = 0; coveragePct = 0 })
            }
            networking = [ordered]@{ privateEndpoints = @() }
            domains    = [ordered]@{
                analytics   = [ordered]@{
                    dataFactories     = @([ordered]@{ id = $script:FactoryId; name = 'adf1'; publicNetworkAccess = 'Enabled'; identityType = '' })
                    synapseWorkspaces = @([ordered]@{ name = 'syn1'; publicAccess = 'Enabled'; managedVnetEnabled = $false })
                }
                databases   = [ordered]@{
                    sqlServers         = @([ordered]@{ name = 'sql1'; publicNetworkAccess = 'Enabled' })
                    sqlDefenderPricing = @([ordered]@{ pricingTier = 'Free' })
                }
                web         = [ordered]@{ webApps = @([ordered]@{ name = 'app1'; httpsOnly = $false; minTls = '1.0' }) }
                integration = [ordered]@{ apiManagement = @() }
            }
        }
    }

    $script:Good = @{}
    $script:Bad = @{}
    foreach ($pattern in 'platform.engineering', 'analytics.journey', 'appmod.readiness') {
        $script:Good[$pattern] = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern $pattern -Collect (New-GoodCollect) -Assessment "good $pattern")
        $script:Bad[$pattern] = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern $pattern -Collect (New-BadCollect) -Assessment "bad $pattern")
    }
    $script:Empty = @{}
    foreach ($pattern in 'platform.engineering', 'analytics.journey', 'appmod.readiness') {
        $script:Empty[$pattern] = @(Invoke-TestRuleSet -Pattern $pattern -Collect ([ordered]@{}) -Assessment "empty $pattern")
    }
}

Describe '<Name>: rule file and enumeration agree' -ForEach $script:Cases {
    BeforeAll {
        $script:ruleDoc = Get-TestRuleDoc -Rules $Rules
        $script:docText = Get-Content (Join-Path $script:root "docs/frameworks/$Doc") -Raw
        $script:ruleText = Get-Content (Join-Path $script:RuleDir "$Rules.yaml") -Raw
    }

    It 'declares its framework, a framework version and the expected rule counts' {
        $script:ruleDoc.framework | Should -Be $Framework
        $script:ruleDoc.frameworkversion | Should -Match 'Scout-derived'
        $script:ruleDoc.frameworkversion | Should -Match ([regex]::Escape("($Items items"))
        @($script:ruleDoc.rules).Count | Should -Be $Items
        @($script:ruleDoc.rules | Where-Object { $_.manual }).Count | Should -Be $Manual
        @($script:ruleDoc.rules | Where-Object { -not $_.manual }).Count | Should -Be $Auto
    }

    It 'uses only ids with its own prefix, with no duplicates inside the file' {
        $ids = @($script:ruleDoc.rules.id)
        @($ids | Where-Object { $_ -notmatch "^$Prefix-[A-Z]+-\d{2}$" }) | Should -BeNullOrEmpty
        @($ids | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }

    It 'has ids that appear in no other rule file' {
        $mine = @($script:ruleDoc.rules.id)
        $others = foreach ($f in Get-ChildItem $script:RuleDir -Filter '*.yaml' | Where-Object BaseName -ne $Rules) {
            $d = ConvertFrom-Yaml (Get-Content $f.FullName -Raw)
            if ($d -and $d.ContainsKey('rules')) { foreach ($r in @($d.rules)) { if ($r -and $r.ContainsKey('id')) { [string]$r.id } } }
        }
        @($mine | Where-Object { $_ -in $others }) | Should -BeNullOrEmpty
    }

    It 'cites every rule id in the enumeration page, and every id on the page is a rule' {
        $inDoc = @([regex]::Matches($script:docText, "(?m)^\|\s*($Prefix-[A-Z]+-\d{2})\s*\|") | ForEach-Object { $_.Groups[1].Value })
        @($inDoc | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        $ruleIds = @($script:ruleDoc.rules.id)
        @($ruleIds | Where-Object { $_ -notin $inDoc }) | Should -BeNullOrEmpty
        @($inDoc | Where-Object { $_ -notin $ruleIds }) | Should -BeNullOrEmpty
    }

    It 'starts every title and remediation with the rule id' {
        foreach ($r in @($script:ruleDoc.rules)) {
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
        }
    }

    It 'marks every rule either manual or automated and never both' {
        foreach ($r in @($script:ruleDoc.rules)) {
            if ($r.manual) { $r.assert.type | Should -Be 'manual' }
            else { $r.assert.type | Should -Not -Be 'manual' }
        }
    }

    It 'gates every automated rule' {
        foreach ($r in @($script:ruleDoc.rules | Where-Object { -not $_.manual })) {
            $r.assert.ContainsKey('gate') | Should -BeTrue -Because "$($r.id) must report Not assessed on an estate without the data it reads"
        }
    }

    It 'has a pass/fail expectation for every automated rule, and none for a rule that is not automated' {
        $auto = @($script:ruleDoc.rules | Where-Object { -not $_.manual } | ForEach-Object { $_.id })
        @($auto | Where-Object { $_ -notin $AutoIds }) | Should -BeNullOrEmpty
        @($AutoIds | Where-Object { $_ -notin $auto }) | Should -BeNullOrEmpty
    }

    It 'has the Shape B header FrameworkCurrency.Tests.ps1 parses' {
        $script:docText | Should -Match '\*\*Enumerated 2026-11-25\.'
        $script:docText | Should -Match '(?m)^\| Field \| Value \|\r?$'
        $script:docText | Should -Match '(?m)^\| Framework version \| \S'
        $script:docText | Should -Match '(?m)^\| Extraction date \| 2026-11-25 \|\r?$'
        $script:docText | Should -Match '(?m)^\| Verification method \| \S'
    }

    It 'says the questions are Scout-derived and carries no subscription path' {
        $script:docText | Should -Match 'Scout'
        $script:docText | Should -Match 'not Microsoft''s question list'
        $script:docText | Should -Not -Match '/subscriptions/'
        $script:ruleText | Should -Not -Match '/subscriptions/'
    }
}

Describe '<Name>: manual questions export for answering' -ForEach $script:Cases {
    BeforeAll {
        $script:rows = @(& $script:Module { param($n, $m) Get-ScoutAssessmentQuestion -Assessment $n -Manifest $m } $Name $script:Manifest)
        $script:docRules = Get-TestRuleDoc -Rules $Rules
    }

    It 'lists every manual rule once and no automated rule' {
        $script:rows.Count | Should -Be $Manual
        @($script:rows.RuleId | Select-Object -Unique).Count | Should -Be $Manual
        $manualIds = @($script:docRules.rules | Where-Object { $_.manual } | ForEach-Object { $_.id })
        @($script:rows.RuleId | Where-Object { $_ -notin $manualIds }) | Should -BeNullOrEmpty
    }

    It 'gives each question its text, guidance, framework and assessment name' {
        foreach ($row in $script:rows) {
            $row.Question | Should -Not -BeNullOrEmpty
            $row.Guidance | Should -Not -BeNullOrEmpty
            $row.Framework | Should -Be $Framework
            $row.Assessment | Should -Be $Name
        }
    }
}

Describe '<Name>: an estate with none of the resources' -ForEach $script:Cases {
    BeforeAll { $script:found = @($script:Empty[$Rules]) }

    It 'evaluates every rule without an error' {
        $script:found.Count | Should -Be $Items
        @($script:found | Where-Object Status -eq 'Error') | Should -BeNullOrEmpty
    }

    It 'leaves every manual question unscored (Manual)' {
        $m = @($script:found | Where-Object Manual)
        $m.Count | Should -Be $Manual
        @($m | Where-Object Status -ne 'Manual') | Should -BeNullOrEmpty
    }

    It 'reports every automated rule Not assessed, never Pass or Fail' {
        $a = @($script:found | Where-Object { -not $_.Manual })
        $a.Count | Should -Be $Auto
        @($a | Where-Object Status -ne 'NotAssessed') | Should -BeNullOrEmpty
    }
}

Describe 'Automated rules pass and fail on the data they read' {
    It '<Id> is <GoodStatus> on a healthy estate and <BadStatus> on a broken one' -ForEach $script:AutomatedExpectations {
        $script:Good[$Rules][$Id].Status | Should -Be $GoodStatus
        $script:Bad[$Rules][$Id].Status | Should -Be $BadStatus
    }

    It 'names the offending resources as evidence when a rule fails' {
        $script:Bad['analytics.journey']['ANLJT-GOV-10'].EvidenceCount | Should -Be 1
        $script:Bad['appmod.readiness']['APPMOD-APP-07'].EvidenceCount | Should -Be 1
        $script:Bad['platform.engineering']['PLATENG-GOV-07'].EvidenceCount | Should -Be 60
    }

    It 'scores PLATENG-PRV-02 as Partial when only some pipelines are YAML' {
        $collect = New-GoodCollect
        $collect.devops.pipelines = @([ordered]@{ ConfigurationType = 'yaml' }, [ordered]@{ ConfigurationType = 'designerJson' })
        $f = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'platform.engineering' -Collect $collect -Assessment 'partial')
        $f['PLATENG-PRV-02'].Status | Should -Be 'Partial'
    }
}

Describe 'Gates close on missing data, not on a bad result' {
    It 'reports the Azure DevOps rules Not assessed when -IncludeDevOps was not used' {
        $collect = New-GoodCollect
        $collect.devops = [ordered]@{ available = $false; pipelines = @(); repositories = @() }
        $pe = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'platform.engineering' -Collect $collect -Assessment 'nodevops')
        $am = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'appmod.readiness' -Collect $collect -Assessment 'nodevops')
        $pe['PLATENG-PRV-02'].Status | Should -Be 'NotAssessed'
        $am['APPMOD-PRC-01'].Status | Should -Be 'NotAssessed'
        $am['APPMOD-PRC-05'].Status | Should -Be 'NotAssessed'
    }

    It 'reports the policy rules Not assessed when the policy read did not succeed' {
        $collect = New-GoodCollect
        $collect.governance.policyAssignmentsAvailable = $false
        $collect.governance.policyAssignments = @()
        $pe = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'platform.engineering' -Collect $collect -Assessment 'nopolicy')
        $am = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'appmod.readiness' -Collect $collect -Assessment 'nopolicy')
        $pe['PLATENG-GOV-02'].Status | Should -Be 'NotAssessed'
        $pe['PLATENG-GOV-03'].Status | Should -Be 'NotAssessed'
        $am['APPMOD-SEC-04'].Status | Should -Be 'NotAssessed'
    }

    It 'reports the Data Factory rules Not assessed on an estate with Synapse only' {
        $collect = New-GoodCollect
        $collect.domains.analytics.dataFactories = @()
        $f = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'analytics.journey' -Collect $collect -Assessment 'nofactory')
        foreach ($id in 'ANLJT-GOV-10', 'ANLJT-GOV-11', 'ANLJT-GOV-12') { $f[$id].Status | Should -Be 'NotAssessed' }
        foreach ($id in 'ANLJT-GOV-13', 'ANLJT-GOV-14') { $f[$id].Status | Should -Be 'Pass' }
    }

    It 'reports the SQL and web app rules Not assessed on an estate without them' {
        $collect = New-GoodCollect
        $collect.domains.databases = [ordered]@{ sqlServers = @(); sqlDefenderPricing = @() }
        $collect.domains.web = [ordered]@{ webApps = @() }
        $f = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'appmod.readiness' -Collect $collect -Assessment 'nosql')
        foreach ($id in 'APPMOD-DAT-08', 'APPMOD-DAT-09', 'APPMOD-APP-07', 'APPMOD-APP-08', 'APPMOD-AIR-06') { $f[$id].Status | Should -Be 'NotAssessed' }
    }

    It 'matches a Data Factory to its private endpoint without regard to case' {
        $collect = New-GoodCollect
        $collect.networking.privateEndpoints = @([ordered]@{ name = 'pe1'; targetResourceId = $script:FactoryId.ToUpperInvariant() })
        $f = ConvertTo-TestFindingMap (Invoke-TestRuleSet -Pattern 'analytics.journey' -Collect $collect -Assessment 'case')
        $f['ANLJT-GOV-11'].Status | Should -Be 'Pass'
    }
}

Describe 'Manual questions carry the evidence Scout collected' {
    It 'attaches evidence but never scores the question' {
        $a = $script:Good['analytics.journey']['ANLJT-ARC-02']
        $a.Status | Should -Be 'Manual'
        $a.EvidenceCount | Should -Be 1
        $p = $script:Good['platform.engineering']['PLATENG-ADO-01']
        $p.Status | Should -Be 'Manual'
        $m = $script:Good['appmod.readiness']['APPMOD-INV-01']
        $m.Status | Should -Be 'Manual'
        $m.EvidenceCount | Should -Be 1
    }
}

Describe '<Name>: answered questions score' -ForEach $script:Cases {
    BeforeAll {
        $script:answerBase = @($script:Empty[$Rules])
        function New-TestAnswer { param([string] $Word, [string] $Status) @{ Answer = $Word; Status = $Status; Note = ''; AnsweredBy = 'test'; AnsweredAt = '2026-11-25' } }
        function Get-TestAreaScore {
            param($Findings, [hashtable] $Answers)
            $copies = @($Findings | ForEach-Object { $_.PSObject.Copy() })   # Set-ScoutFindingAnswer edits findings in place
            & $script:Module { param($f, $a) Get-Score -Findings @(Set-ScoutFindingAnswer -Findings $f -Answers $a) } $copies $Answers
        }
    }

    It 'scores 100 when every manual question is answered Yes, and counts none as unanswered' {
        $answers = @{}
        foreach ($f in $script:answerBase | Where-Object Manual) { $answers[[string]$f.Id] = New-TestAnswer 'Yes' 'Pass' }
        $score = Get-TestAreaScore -Findings $script:answerBase -Answers $answers
        $area = @($score.Areas)[0]
        $area.Score | Should -Be 100
        $area.Manual | Should -Be 0
    }

    It 'scores 0 when every manual question is answered No' {
        $answers = @{}
        foreach ($f in $script:answerBase | Where-Object Manual) { $answers[[string]$f.Id] = New-TestAnswer 'No' 'Fail' }
        $score = Get-TestAreaScore -Findings $script:answerBase -Answers $answers
        @($score.Areas)[0].Score | Should -Be 0
    }

    It 'scores between 0 and 100 for a mix, and leaves N/A out of the score' {
        $manual = @($script:answerBase | Where-Object Manual)
        $answers = @{}
        for ($i = 0; $i -lt $manual.Count; $i++) {
            $answers[[string]$manual[$i].Id] = switch ($i % 3) {
                0 { New-TestAnswer 'Yes' 'Pass' }
                1 { New-TestAnswer 'No' 'Fail' }
                default { New-TestAnswer 'N/A' 'NotApplicable' }
            }
        }
        $score = Get-TestAreaScore -Findings $script:answerBase -Answers $answers
        $area = @($score.Areas)[0]
        $area.Score | Should -BeGreaterThan 0
        $area.Score | Should -BeLessThan 100
        $area.Manual | Should -Be 0
    }

    It 'leaves unanswered questions Manual and out of the score' {
        $score = Get-TestAreaScore -Findings $script:answerBase -Answers @{}
        $area = @($score.Areas)[0]
        $area.Manual | Should -Be $Manual
    }

    It 'never lets an answer override an automated rule' {
        $good = @($script:Good[$Rules].Values)
        $auto = @($good | Where-Object { -not $_.Manual } | Select-Object -First 1)
        $answers = @{ ([string]$auto[0].Id) = (New-TestAnswer 'No' 'Fail') }
        $out = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } $good $answers)
        $kept = $out | Where-Object Id -eq $auto[0].Id
        $kept.Status | Should -Be $auto[0].Status
        $kept.Source | Should -Be 'Data'
    }
}
