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

    $script:ExpectedDomains = @('Artificial Intelligence', 'Cost Management', 'Data', 'Operations', 'Regulatory Compliance', 'Resource Management', 'Security')

    # A fully-populated mock Collect: every automatable caf.govern.*.yaml query resolves to
    # at least one row, so every automated rule Passes and NotAssessed never fires here --
    # this proves the "healthy tenant" path scores cleanly, not just the empty-tenant path.
    function New-MockGovernanceCollect {
        [pscustomobject]@{
            governance = [pscustomobject]@{
                policyAssignmentsAvailable = $true
                roleAssignmentsAvailable   = $true
                budgetsAvailable           = $true
                resourceLocksAvailable     = $true
                policyAssignments = @(
                    [pscustomobject]@{ id = '/pa/1'; properties = [pscustomobject]@{ enforcementMode = 'Default' } }
                )
                budgets       = @([pscustomobject]@{ id = '/budget/1'; name = 'monthly-cap' })
                resourceLocks = @([pscustomobject]@{ id = '/lock/1'; properties = [pscustomobject]@{ level = 'CanNotDelete' } })
            }
            management = [pscustomobject]@{
                logAnalyticsWorkspaces = @([pscustomobject]@{ id = '/law/1' })
            }
            advisor = @(
                [pscustomobject]@{ Category = 'Cost'; Impact = 'High' }
            )
            costCleanup = [pscustomobject]@{ orphanedDisks = @(); orphanedPips = @() }
            domains    = [pscustomobject]@{
                management = [pscustomobject]@{
                    policyComplianceStates = @([pscustomobject]@{ ComplianceState = 'Compliant' })
                }
                analytics  = [pscustomobject]@{
                    purviewAccounts = @([pscustomobject]@{ id = '/purview/1' })
                }
            }
        }
    }

    # AB#6839/#6844/#6845 sparse-payload regression fixture: every automatable dataset is
    # present but EMPTY (not missing, not $null -- the class of bug that throws under
    # StrictMode on the wrong shape and the class that silently false-passes on the wrong
    # count). Every automated rule must Fail (0 evidence, countGreaterThan/exists both false),
    # not Error, not a false Pass.
    function New-EmptyGovernanceCollect {
        [pscustomobject]@{
            governance = [pscustomobject]@{
                policyAssignmentsAvailable = $true
                roleAssignmentsAvailable   = $true
                budgetsAvailable           = $true
                resourceLocksAvailable     = $true
                policyAssignments = @()
                budgets           = @()
                resourceLocks     = @()
            }
            management = [pscustomobject]@{ logAnalyticsWorkspaces = @() }
            advisor    = @()
            costCleanup = [pscustomobject]@{ orphanedDisks = @(); orphanedPips = @() }
            domains    = [pscustomobject]@{
                management = [pscustomobject]@{ policyComplianceStates = @() }
                analytics  = [pscustomobject]@{ purviewAccounts = @() }
            }
        }
    }

    function Get-GovernanceFindings {
                [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
param($Collect)
        $ruleSet = Get-RuleSet -Patterns @('caf.govern.*')
        return Invoke-Assessment -Collect $Collect -RuleSet $ruleSet -Assessment 'Assess: Cloud Governance'
    }
}

Describe 'caf.govern.*.yaml -- rule file structure (AB#6459)' {
    BeforeAll {
        $script:RuleSet = Get-RuleSet -Patterns @('caf.govern.*')
    }

    It 'loads exactly seven rule files, one per CAF Govern risk category' {
        $script:RuleSet.Count | Should -Be 7
    }

    It 'declares the seven domains named in docs/frameworks/cloud-governance-question-set.md, no invented eighth domain' {
        ($script:RuleSet.Area | Sort-Object) | Should -Be $script:ExpectedDomains
    }

    It 'declares "Cloud Governance" as the framework for every domain (so Get-Score groups them together)' {
        $script:RuleSet | ForEach-Object { $_.Framework | Should -Be 'Cloud Governance' }
    }

    It 'declares a frameworkversion on every domain (Get-RuleSet''s load-time guard, AB#6817)' {
        $script:RuleSet | ForEach-Object { [string]::IsNullOrWhiteSpace($_.FrameworkVersion) | Should -BeFalse -Because "$($_.Area) must name the version/date it was measured against" }
    }

    It 'declares at least one automated (non-manual) rule per domain except AI (organisational-only per the enumeration)' {
        foreach ($set in $script:RuleSet) {
            $automated = @($set.Rules | Where-Object { -not $_.manual })
            if ($set.Area -eq 'Artificial Intelligence') {
                $automated.Count | Should -Be 0 -Because 'AI Foundry content-filter config is not collected -- both AI items are manual by design'
            } else {
                $automated.Count | Should -BeGreaterThan 0 -Because "$($set.Area) must have at least one automatable rule or it can never score, only ever render Not assessed"
            }
        }
    }
}

Describe 'caf.govern.*.yaml -- scoring correctness on a fully-populated (healthy) tenant' {
    BeforeAll {
        $script:Findings = Get-GovernanceFindings -Collect (New-MockGovernanceCollect)
        $script:Scored = Get-Score -Findings $script:Findings
        $script:Domains = Get-GovernanceDomainScore -Areas $script:Scored.Areas
    }

    It 'produces a finding for every rule across all seven domains' {
        $expectedRuleCount = 2 + 3 + 4 + 4 + 2 + 1 + 2   # RC + SC + CM + OP + DG + RM + AI, per docs/frameworks/cloud-governance-question-set.md
        $script:Findings.Count | Should -Be $expectedRuleCount
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

    It 'marks the manual-only AI domain Manual on every rule (never scored as Pass/Fail)' {
        $aiFindings = @($script:Findings | Where-Object Area -eq 'Artificial Intelligence')
        $aiFindings.Count | Should -Be 2
        $aiFindings | ForEach-Object { $_.Status | Should -Be 'Manual' }
    }

    It 'gives every domain except AI a numeric 1-10 score, and AI is NotAssessed' {
        foreach ($d in $script:Domains) {
            if ($d.Area -eq 'Artificial Intelligence') {
                $d.NotAssessed | Should -BeTrue
                $d.Score | Should -BeNullOrEmpty
            } else {
                $d.NotAssessed | Should -BeFalse -Because "$($d.Area) has at least one automated Pass rule"
                $d.Score | Should -BeGreaterOrEqual 1
                $d.Score | Should -BeLessOrEqual 10
            }
        }
    }
}

Describe 'caf.govern.*.yaml -- the false-pass class: sparse/empty data must Fail, never silently Pass or Error (AB#6839/#6844/#6845)' {
    BeforeAll {
        $script:EmptyFindings = Get-GovernanceFindings -Collect (New-EmptyGovernanceCollect)
    }

    It 'does not throw and does not produce any Error status when every automatable dataset is present-but-empty' {
        $script:EmptyFindings | Where-Object Status -eq 'Error' | Should -BeNullOrEmpty
    }

    It 'Fails every automated rule (evidence count 0), rather than Passing on an absent denominator' {
        $automatedIds = @('CGOV-RC-01', 'CGOV-SC-02', 'CGOV-CM-02', 'CGOV-CM-03', 'CGOV-OP-01', 'CGOV-OP-02', 'CGOV-DG-01', 'CGOV-RM-01')
        foreach ($id in $automatedIds) {
            (($script:EmptyFindings | Where-Object Id -eq $id).Status) | Should -Be 'Fail' -Because "$id has zero evidence rows and must Fail, not Pass or Unknown"
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
