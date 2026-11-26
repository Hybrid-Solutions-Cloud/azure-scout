#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for the Cloud Governance (CAF Govern) rule files
    (src/assess/rules/caf.govern.*.yaml) and the 1-10 domain maturity scale
    (src/assess/engine/Get-GovernanceDomainScore.ps1). ADO Story AB#6459, Feature AB#6458,
    Epic AB#6454. No Azure connection required.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    Import-Module powershell-yaml -ErrorAction Stop
    . "$script:Root/src/assess/engine/Get-RuleSet.ps1"
    . "$script:Root/src/assess/engine/Resolve-JsonPath.ps1"
    . "$script:Root/src/assess/engine/Resolve-RuleJoin.ps1"
    . "$script:Root/src/assess/engine/Invoke-Rule.ps1"
    . "$script:Root/src/assess/Invoke-Assessment.ps1"
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/assess/engine/Get-MaturityLevel.ps1"
    . "$script:Root/src/assess/engine/Get-GovernanceDomainScore.ps1"

    # The seven CAF Govern risk categories plus the governance PROCESS area (caf.govern.proc.yaml).
    $script:ExpectedDomains = @('Artificial Intelligence', 'Cost Management', 'Data', 'Governance Process', 'Operations', 'Regulatory Compliance', 'Resource Management', 'Security')

    function New-MockPolicyAssignment {
        param([string]$DisplayName, [string]$DefinitionId)
        [pscustomobject]@{
            id = "/providers/Microsoft.Authorization/policyAssignments/$([guid]::NewGuid())"
            properties = [pscustomobject]@{
                displayName = $DisplayName; policyDefinitionId = $DefinitionId; enforcementMode = 'Default'
            }
        }
    }

    # A fully-populated mock Collect: every automatable caf.govern.*.yaml query resolves to
    # at least one row, so every automated rule Passes -- this proves the "healthy tenant" path
    # scores cleanly, not just the empty-tenant path. CGOV-SC-05 reads the Azure RBAC PIM eligibility
    # schedules, which Scout now collects (governance.pimEligibility); the empty-tenant fixture below
    # leaves them unavailable, which is where its NotAssessed outcome is pinned.
    function New-MockGovernanceCollect {
        $def = '/providers/Microsoft.Authorization/policyDefinitions'
        $set = '/providers/Microsoft.Authorization/policySetDefinitions'
        [pscustomobject]@{
            governance = [pscustomobject]@{
                policyAssignmentsAvailable = $true
                roleAssignmentsAvailable   = $true
                budgetsAvailable           = $true
                resourceLocksAvailable     = $true
                pimEligibilityAvailable    = $true
                pimEligibility             = @([pscustomobject]@{ id = 'sched1'; principalId = 'p1'; principalType = 'User'; roleDefinitionName = 'Owner'; privilegedRole = $true; accessType = 'Eligible' })
                managementGroups = @(
                    [pscustomobject]@{ name = 'root' }, [pscustomobject]@{ name = 'platform' }, [pscustomobject]@{ name = 'landingzones' }
                )
                policyAssignments = @(
                    (New-MockPolicyAssignment 'PCI DSS v4.0.1' "$set/aaaaaaaa-0000-0000-0000-000000000001")
                    (New-MockPolicyAssignment 'Microsoft cloud security benchmark' "$set/bbbbbbbb-0000-0000-0000-000000000002")
                    (New-MockPolicyAssignment 'Block costly services' "$def/6c112d4e-5bc7-47ae-a041-ea2d9dccd749")
                    (New-MockPolicyAssignment 'CostCenter from RG' "$def/ea3f2387-9b95-492a-a190-fcdc54f7b070")
                    (New-MockPolicyAssignment 'Regions' "$def/e56962a6-4747-49cd-b67b-bf8b01975c4c")
                    (New-MockPolicyAssignment 'Foundry guardrail' "$def/930f48f9-f07e-427c-9494-52603581c6a9")
                )
                budgets       = @(
                    [pscustomobject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Consumption/budgets/monthly-cap'
                        name = 'monthly-cap'; properties = [pscustomobject]@{ notifications = [pscustomobject]@{ actual80 = [pscustomobject]@{ enabled = $true } } } }
                    [pscustomobject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app/providers/Microsoft.Consumption/budgets/app-cap'
                        name = 'app-cap'; properties = [pscustomobject]@{ notifications = [pscustomobject]@{ actual90 = [pscustomobject]@{ enabled = $true } } } }
                )
                resourceLocks = @([pscustomobject]@{ id = '/lock/1'; properties = [pscustomobject]@{ level = 'CanNotDelete' } })
            }
            management = [pscustomobject]@{
                logAnalyticsWorkspaces = @([pscustomobject]@{ id = '/law/1' })
                deployments = @([pscustomobject]@{ name = 'deploy-1' })
            }
            monitor = [pscustomobject]@{
                activityLogAlertRules = @([pscustomobject]@{ name = 'sh'; enabled = $true; scopeCount = 1; actionGroupCount = 1 })
                metricAlertRules      = @([pscustomobject]@{ name = 'cpu'; enabled = $true; actionGroupCount = 1 })
                scheduledQueryRules   = @()
            }
            security = [pscustomobject]@{
                defenderPlans = @(
                    [pscustomobject]@{ name = 'VirtualMachines'; properties = [pscustomobject]@{ pricingTier = 'Standard' } }
                    [pscustomobject]@{ name = 'AI'; properties = [pscustomobject]@{ pricingTier = 'Standard' } }
                )
                defenderAlerts = @()
            }
            tags = @([pscustomobject]@{ name = 'CostCenter' })
            advisor = @(
                [pscustomobject]@{ Category = 'Cost'; Impact = 'High' }
            )
            advisorAvailable = $true
            costCleanup = [pscustomobject]@{ orphanedDisks = @(); orphanedPips = @() }
            finops = [pscustomobject]@{ anomalies = @() }
            domains    = [pscustomobject]@{
                management = [pscustomobject]@{
                    policyComplianceStates = @([pscustomobject]@{ ComplianceState = 'Compliant' })
                }
                analytics  = [pscustomobject]@{
                    purviewAccounts = @([pscustomobject]@{ id = '/purview/1' })
                }
                storage = [pscustomobject]@{
                    storageAccounts = @(
                        [pscustomobject]@{ name = 'sa1'; httpsOnly = $true; minTls = 'TLS1_2' }
                        [pscustomobject]@{ name = 'sa2'; httpsOnly = $true; minTls = 'TLS1_3' }
                    )
                }
            }
        }
    }

    # AB#6839/#6844/#6845 sparse-payload regression fixture: every automatable dataset is
    # present but EMPTY (not missing, not $null -- the class of bug that throws under
    # StrictMode on the wrong shape and the class that silently false-passes on the wrong
    # count). Every automated rule must Fail (0 evidence, countGreaterThan/exists both false),
    # or read NotAssessed / Unknown where its own gate or empty denominator says so -- never
    # Error, never a false Pass.
    function New-EmptyGovernanceCollect {
        [pscustomobject]@{
            governance = [pscustomobject]@{
                policyAssignmentsAvailable = $true
                roleAssignmentsAvailable   = $true
                budgetsAvailable           = $true
                resourceLocksAvailable     = $true
                pimEligibilityAvailable    = $false
                policyAssignments = @()
                managementGroups  = @()
                budgets           = @()
                resourceLocks     = @()
                pimEligibility    = @()
            }
            management = [pscustomobject]@{ logAnalyticsWorkspaces = @(); deployments = @() }
            monitor    = [pscustomobject]@{ activityLogAlertRules = @(); metricAlertRules = @(); scheduledQueryRules = @() }
            security   = [pscustomobject]@{ defenderPlans = @(); defenderAlerts = @() }
            tags       = @()
            advisor    = @()
            advisorAvailable = $true
            costCleanup = [pscustomobject]@{ orphanedDisks = @(); orphanedPips = @() }
            finops     = [pscustomobject]@{ anomalies = @() }
            domains    = [pscustomobject]@{
                management = [pscustomobject]@{ policyComplianceStates = @() }
                analytics  = [pscustomobject]@{ purviewAccounts = @() }
                storage    = [pscustomobject]@{ storageAccounts = @() }
            }
        }
    }

    function Get-GovernanceFindings {
                [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
param($Collect)
        $ruleSet = Get-RuleSet -Patterns @('caf.govern.*')
        return Invoke-Assessment -Collect $Collect -RuleSet $ruleSet -Assessment 'CAF: Govern'
    }
}

Describe 'caf.govern.*.yaml -- rule file structure (AB#6459)' {
    BeforeAll {
        $script:RuleSet = Get-RuleSet -Patterns @('caf.govern.*')
    }

    It 'loads exactly eight rule files: one per CAF Govern risk category plus the governance process' {
        $script:RuleSet.Count | Should -Be 8
    }

    It 'declares the seven risk categories and the Governance Process area named in docs/frameworks/cloud-governance-question-set.md, nothing else' {
        ($script:RuleSet.Area | Sort-Object) | Should -Be $script:ExpectedDomains
    }

    It 'keeps rule ids unique across every file and in the CGOV-AREA-NN pattern' {
        $ids = @($script:RuleSet.Rules | ForEach-Object { $_.id })
        ($ids | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        foreach ($id in $ids) { $id | Should -Match '^CGOV-(RC|SC|CM|OP|DG|RM|AI|PROC)-\d{2}$' }
    }

    It 'keeps every pre-existing rule id (they are cited by reports, answers and docs)' {
        $ids = @($script:RuleSet.Rules | ForEach-Object { $_.id })
        foreach ($id in @(
                'CGOV-RC-01', 'CGOV-RC-02', 'CGOV-SC-01', 'CGOV-SC-02', 'CGOV-SC-03',
                'CGOV-CM-01', 'CGOV-CM-02', 'CGOV-CM-03', 'CGOV-CM-04',
                'CGOV-OP-01', 'CGOV-OP-02', 'CGOV-OP-03', 'CGOV-OP-04',
                'CGOV-DG-01', 'CGOV-DG-02', 'CGOV-RM-01', 'CGOV-AI-01', 'CGOV-AI-02')) {
            $ids | Should -Contain $id
        }
    }

    It 'carries the five documented process rules CGOV-PROC-01..05 as manual rules in the Governance Process area' {
        $proc = $script:RuleSet | Where-Object Area -eq 'Governance Process'
        $procIds = @($proc.Rules | ForEach-Object { $_.id })
        foreach ($n in 1..5) { $procIds | Should -Contain ('CGOV-PROC-{0:00}' -f $n) }
        foreach ($r in $proc.Rules) { $r.manual | Should -BeTrue -Because "$($r.id) is organisational -- no Azure resource records it" }
    }

    It 're-bases every file on the CAF Govern methodology and no longer cites the retired Cloud Governance assessment' {
        foreach ($set in $script:RuleSet) {
            $set.FrameworkVersion | Should -Match 'CAF Govern'
            $set.FrameworkVersion | Should -Match 'verified 2026-11-24'
            $set.FrameworkVersion | Should -Match 'cloud-adoption-framework/govern/'
        }
        foreach ($file in Get-ChildItem "$script:Root/src/assess/rules" -Filter 'caf.govern.*.yaml') {
            (Get-Content $file.FullName -Raw) | Should -Not -Match 'b1891add' -Because 'Microsoft deletes that assessment in January 2027'
        }
    }

    It 'declares "Cloud Governance" as the framework for every domain (so Get-Score groups them together)' {
        $script:RuleSet | ForEach-Object { $_.Framework | Should -Be 'Cloud Governance' }
    }

    It 'declares a frameworkversion on every domain (Get-RuleSet''s load-time guard, AB#6817)' {
        $script:RuleSet | ForEach-Object { [string]::IsNullOrWhiteSpace($_.FrameworkVersion) | Should -BeFalse -Because "$($_.Area) must name the version/date it was measured against" }
    }

    It 'declares at least one automated (non-manual) rule per risk category; only the organisational Governance Process area is manual-only' {
        foreach ($set in $script:RuleSet) {
            $automated = @($set.Rules | Where-Object { -not $_.manual })
            if ($set.Area -eq 'Governance Process') {
                $automated.Count | Should -Be 0 -Because 'a charter, a risk register and audits are not Azure resources -- every process item is manual by design'
            } else {
                $automated.Count | Should -BeGreaterThan 0 -Because "$($set.Area) must have at least one automatable rule or it can never score, only ever render Not assessed"
            }
        }
    }

    It 'gives every automated rule a query, and every manual rule assert type manual' {
        foreach ($rule in $script:RuleSet.Rules) {
            if ($rule.manual) { $rule.assert.type | Should -Be 'manual' -Because "$($rule.id)" }
            else { $rule.query | Should -Not -BeNullOrEmpty -Because "$($rule.id) is automated" }
        }
    }
}

Describe 'caf.govern.*.yaml -- scoring correctness on a fully-populated (healthy) tenant' {
    BeforeAll {
        $script:Findings = Get-GovernanceFindings -Collect (New-MockGovernanceCollect)
        $script:Scored = Get-Score -Findings $script:Findings
        $script:Domains = Get-GovernanceDomainScore -Areas $script:Scored.Areas
        $script:AllRules = @((Get-RuleSet -Patterns @('caf.govern.*')).Rules)
    }

    It 'produces a finding for every rule across all eight areas' {
        $expectedRuleCount = 5 + 7 + 8 + 6 + 6 + 7 + 4 + 11   # RC + SC + CM + OP + DG + RM + AI + PROC, per docs/frameworks/cloud-governance-question-set.md
        $script:Findings.Count | Should -Be $expectedRuleCount
        $script:Findings.Count | Should -Be $script:AllRules.Count
    }

    It 'Passes CGOV-RM-01 (policy assignments present) with real evidence' {
        ($script:Findings | Where-Object Id -eq 'CGOV-RM-01').Status | Should -Be 'Pass'
    }

    It 'Passes CGOV-CM-02 (budgets present)' {
        ($script:Findings | Where-Object Id -eq 'CGOV-CM-02').Status | Should -Be 'Pass'
    }

    It 'Passes CGOV-DG-01 (Purview account present)' {
        ($script:Findings | Where-Object Id -eq 'CGOV-DG-01').Status | Should -Be 'Pass'
    }

    It 'Passes every automated rule on the healthy fixture, CGOV-SC-05 included now that PIM eligibility is collected' {
        foreach ($rule in @($script:AllRules | Where-Object { -not $_.manual })) {
            $status = ($script:Findings | Where-Object Id -eq $rule.id).Status
            $status | Should -Be 'Pass' -Because "$($rule.id) has matching evidence in the healthy fixture"
        }
    }

    It 'marks every manual rule Manual (never scored as Pass/Fail without an answer) and attaches the evidence its query found' {
        foreach ($rule in @($script:AllRules | Where-Object { $_.manual })) {
            ($script:Findings | Where-Object Id -eq $rule.id).Status | Should -Be 'Manual'
        }
        (($script:Findings | Where-Object Id -eq 'CGOV-RC-04').EvidenceCount) | Should -Be 1 -Because 'the activity-log alert rule is pre-filled for the reviewer'
        (($script:Findings | Where-Object Id -eq 'CGOV-RM-07').EvidenceCount) | Should -Be 1
    }

    It 'scores the AI domain now that content-filter policy and Defender for AI are automated' {
        $ai = $script:Domains | Where-Object Area -eq 'Artificial Intelligence'
        $ai.NotAssessed | Should -BeFalse
        $ai.Pass | Should -Be 2
        $ai.Manual | Should -Be 2
    }

    It 'gives every domain a numeric 1-10 score except Governance Process, which is NotAssessed until answers are supplied' {
        $script:Domains.Count | Should -Be 8
        foreach ($d in $script:Domains) {
            if ($d.Area -eq 'Governance Process') {
                $d.NotAssessed | Should -BeTrue
                $d.Score | Should -BeNullOrEmpty
                $d.Manual | Should -Be 11
            } else {
                $d.NotAssessed | Should -BeFalse -Because "$($d.Area) has at least one automated Pass rule"
                $d.Score | Should -BeGreaterOrEqual 1
                $d.Score | Should -BeLessOrEqual 10
            }
        }
    }

    It 'leaves the unanswered Governance Process area out of the headline score' {
        $fw = $script:Scored.Frameworks | Where-Object Framework -eq 'Cloud Governance'
        $fw.Score | Should -Be 100 -Because 'every scored automated rule Passes and an unscored area carries no weight'
    }
}

Describe 'caf.govern.*.yaml -- new automated rules do not match unrelated data (negative controls)' {
    BeforeAll {
        $script:Neg = New-MockGovernanceCollect
        $def = '/providers/Microsoft.Authorization/policyDefinitions'
        $set = '/providers/Microsoft.Authorization/policySetDefinitions'
        # Near-miss assignments: none names a recognised standard or definition. 'specific'
        # contains the letters PCI, which a naive regex would take for the PCI DSS initiative.
        $script:Neg.governance.policyAssignments = @(
            (New-MockPolicyAssignment 'A specific naming thing' "$set/cccccccc-0000-0000-0000-000000000003")
            (New-MockPolicyAssignment 'Audit VM backups' "$def/dddddddd-0000-0000-0000-000000000004")
        )
        # A storage fleet that is only partly compliant.
        $script:Neg.domains.storage.storageAccounts = @(
            [pscustomobject]@{ name = 'sa1'; httpsOnly = $true;  minTls = 'TLS1_2' }
            [pscustomobject]@{ name = 'sa2'; httpsOnly = $false; minTls = 'TLS1_0' }
            [pscustomobject]@{ name = 'sa3'; httpsOnly = $true;  minTls = '' }
        )
        # Alert rules that are disabled or have nowhere to send.
        $script:Neg.monitor.activityLogAlertRules = @(
            [pscustomobject]@{ name = 'off'; enabled = $false; actionGroupCount = 2 }
            [pscustomobject]@{ name = 'mute'; enabled = $true; actionGroupCount = 0 }
        )
        $script:Neg.monitor.metricAlertRules = @([pscustomobject]@{ name = 'off'; enabled = $false })
        # Budgets at subscription scope: one has notifications, one does not.
        $script:Neg.governance.budgets = @(
            [pscustomobject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Consumption/budgets/a'; properties = [pscustomobject]@{ notifications = [pscustomobject]@{ n = 1 } } }
            [pscustomobject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Consumption/budgets/b'; properties = [pscustomobject]@{ amount = 10 } }
        )
        $script:Neg.security.defenderPlans = @(
            [pscustomobject]@{ name = 'VirtualMachines'; properties = [pscustomobject]@{ pricingTier = 'Free' } }
            [pscustomobject]@{ name = 'AI'; properties = [pscustomobject]@{ pricingTier = 'Free' } }
        )
        $script:NegFindings = Get-GovernanceFindings -Collect $script:Neg
    }

    It 'does not Error' {
        $script:NegFindings | Where-Object Status -eq 'Error' | Should -BeNullOrEmpty
    }

    It 'Fails the policy-recognition rules on assignments that name no recognised standard or definition' {
        foreach ($id in 'CGOV-RC-03', 'CGOV-SC-07', 'CGOV-CM-07', 'CGOV-CM-08', 'CGOV-DG-03', 'CGOV-RM-03', 'CGOV-RM-04', 'CGOV-RM-05', 'CGOV-AI-03') {
            ($script:NegFindings | Where-Object Id -eq $id).Status | Should -Be 'Fail' -Because "$id must not match an unrelated assignment"
        }
    }

    It 'reports a partly compliant storage fleet as Partial, not Pass' {
        ($script:NegFindings | Where-Object Id -eq 'CGOV-DG-04').Status | Should -Be 'Partial'
        ($script:NegFindings | Where-Object Id -eq 'CGOV-DG-05').Status | Should -Be 'Partial'
        ($script:NegFindings | Where-Object Id -eq 'CGOV-DG-05').EvidenceCount | Should -Be 1
    }

    It 'Fails alerting when every activity-log and metric rule is disabled or has no action group' {
        ($script:NegFindings | Where-Object Id -eq 'CGOV-OP-05').Status | Should -Be 'Fail'
        ($script:NegFindings | Where-Object Id -eq 'CGOV-OP-06').Status | Should -Be 'Fail'
    }

    It 'reports budgets with and without notifications as Partial' {
        ($script:NegFindings | Where-Object Id -eq 'CGOV-CM-06').Status | Should -Be 'Partial'
    }

    It 'Fails Defender plan rules when every plan is on the Free tier (the data is present, the plans are off)' {
        ($script:NegFindings | Where-Object Id -eq 'CGOV-SC-04').Status | Should -Be 'Fail'
        ($script:NegFindings | Where-Object Id -eq 'CGOV-AI-04').Status | Should -Be 'Fail'
    }

    It 'shows no evidence on the manual CGOV-CM-05 when only subscription-scope budgets were collected' {
        $f = $script:NegFindings | Where-Object Id -eq 'CGOV-CM-05'
        $f.Status | Should -Be 'Manual'
        $f.EvidenceCount | Should -Be 0
    }
}

Describe 'caf.govern.*.yaml -- the false-pass class: sparse/empty data must Fail, never silently Pass or Error (AB#6839/#6844/#6845)' {
    BeforeAll {
        $script:EmptyFindings = Get-GovernanceFindings -Collect (New-EmptyGovernanceCollect)
    }

    It 'does not throw and does not produce any Error status when every automatable dataset is present-but-empty' {
        $script:EmptyFindings | Where-Object Status -eq 'Error' | Should -BeNullOrEmpty
    }

    It 'Fails every automated rule that has evidence to look for (evidence count 0), rather than Passing on an absent denominator' {
        $failIds = @(
            'CGOV-RC-01', 'CGOV-RC-03', 'CGOV-SC-02', 'CGOV-SC-07',
            'CGOV-CM-02', 'CGOV-CM-03', 'CGOV-CM-07', 'CGOV-CM-08',
            'CGOV-OP-01', 'CGOV-OP-02', 'CGOV-OP-05', 'CGOV-OP-06',
            'CGOV-DG-01', 'CGOV-DG-03', 'CGOV-RM-01', 'CGOV-RM-02', 'CGOV-RM-03', 'CGOV-RM-04', 'CGOV-RM-05',
            'CGOV-AI-03')
        foreach ($id in $failIds) {
            (($script:EmptyFindings | Where-Object Id -eq $id).Status) | Should -Be 'Fail' -Because "$id has zero evidence rows and must Fail, not Pass or Unknown"
        }
    }

    It 'reads NotAssessed, never Fail or Pass, where the rule''s own data gate is closed (no Defender plan rows, no PIM data)' {
        foreach ($id in 'CGOV-SC-04', 'CGOV-SC-05', 'CGOV-AI-04') {
            (($script:EmptyFindings | Where-Object Id -eq $id).Status) | Should -Be 'NotAssessed' -Because "$id cannot tell 'plans off' from 'plans not collected'"
        }
    }

    It 'reads NotAssessed, never a 0% Fail or a Pass, where a percentage rule has no denominator (no budgets, no storage accounts)' {
        foreach ($id in 'CGOV-CM-06', 'CGOV-DG-04', 'CGOV-DG-05') {
            (($script:EmptyFindings | Where-Object Id -eq $id).Status) | Should -Be 'NotAssessed' -Because "$id has nothing to measure a percentage of"
        }
    }

    It 'a tenant whose policy data was not collected reads NotAssessed on the policy-recognition rules, never Fail' {
        $c = New-EmptyGovernanceCollect
        $c.governance.policyAssignmentsAvailable = $false
        $f = Get-GovernanceFindings -Collect $c
        foreach ($id in 'CGOV-RC-03', 'CGOV-SC-07', 'CGOV-CM-07', 'CGOV-RM-03', 'CGOV-RM-05', 'CGOV-AI-03', 'CGOV-DG-03') {
            (($f | Where-Object Id -eq $id).Status) | Should -Be 'NotAssessed'
        }
    }

    It 'a zero-policy-assignment tenant scores its policy-backed domains LOW (floored to 1), never a perfect 10' {
        $scored = Get-Score -Findings $script:EmptyFindings
        $domains = Get-GovernanceDomainScore -Areas $scored.Areas
        $rm = $domains | Where-Object Area -eq 'Resource Management'
        $rm.NotAssessed | Should -BeFalse -Because 'the rule DID run and DID fail -- this is a real Fail, not an unassessed domain'
        $rm.Score | Should -Be 1 -Because '0% floors to 1, never 0, and never a fabricated perfect score'
    }
}

Describe 'Get-GovernanceDomainScore -- 1-10 scale mapping (AB#6459)' {
    BeforeAll {
        function New-FakeArea {
            param([string]$Area, [Nullable[double]]$Score, [string]$Framework = 'Cloud Governance')
            [pscustomobject]@{ Framework = $Framework; Area = $Area; Score = $Score; Pass = 1; Partial = 0; Fail = 0; Manual = 0; Unknown = 0; Error = 0 }
        }
    }

    It 'floors 0% to 1, not 0' {
        $r = Get-GovernanceDomainScore -Areas @((New-FakeArea 'X' 0))
        $r[0].Score | Should -Be 1
    }

    It 'caps 100% at 10' {
        $r = Get-GovernanceDomainScore -Areas @((New-FakeArea 'X' 100))
        $r[0].Score | Should -Be 10
    }

    It 'rounds a mid-range percentage to the nearest whole point (55% -> 6)' {
        $r = Get-GovernanceDomainScore -Areas @((New-FakeArea 'X' 55))
        $r[0].Score | Should -Be 6
    }

    It 'renders NotAssessed = $true and Score = $null for a $null percentage, never a fabricated number' {
        $r = Get-GovernanceDomainScore -Areas @((New-FakeArea 'X' $null))
        $r[0].NotAssessed | Should -BeTrue
        $r[0].Score | Should -BeNullOrEmpty
    }

    It 'ignores areas from a different framework' {
        $r = Get-GovernanceDomainScore -Areas @((New-FakeArea 'Y' 90 -Framework 'WAF'))
        $r.Count | Should -Be 0
    }

    It 'sorts domains alphabetically by Area for deterministic report ordering' {
        $r = Get-GovernanceDomainScore -Areas @(
            (New-FakeArea 'Resource Management' 50)
            (New-FakeArea 'Artificial Intelligence' 50)
        )
        $r[0].Area | Should -Be 'Artificial Intelligence'
        $r[1].Area | Should -Be 'Resource Management'
    }
}

Describe 'caf.govern.proc.yaml -- answered process rules make the Governance Process area scorable' {
    It 'scores the area from answered Pass/Fail findings (the shape a questionnaire answer produces) and leaves Manual ones out' {
        function New-ProcFinding {
            param($Id, $Status)
            [pscustomobject]@{
                Id = $Id; Title = 't'; Framework = 'Cloud Governance'; Area = 'Governance Process'; Severity = 'medium'
                Status = $Status; EvidenceCount = 0; Evidence = @(); Remediation = ''; Manual = $true; AreaWeight = 0.142857
            }
        }
        $findings = @(
            (New-ProcFinding 'CGOV-PROC-01' 'Pass')
            (New-ProcFinding 'CGOV-PROC-02' 'Fail')
            (New-ProcFinding 'CGOV-PROC-03' 'Manual')
        )
        $proc = (Get-GovernanceDomainScore -Areas (Get-Score -Findings $findings).Areas) | Where-Object Area -eq 'Governance Process'
        $proc.NotAssessed | Should -BeFalse
        $proc.PercentScore | Should -Be 50
        $proc.Score | Should -Be 5
        $proc.Manual | Should -Be 1
    }
}
