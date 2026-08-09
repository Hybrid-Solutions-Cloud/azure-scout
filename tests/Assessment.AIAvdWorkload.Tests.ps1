#Requires -Version 7.0
#Requires -Modules Pester
#Requires -Modules Az.ResourceGraph

<#
    Pester tests for the AI workload (AB#6818) and AVD-on-Azure-Local workload (AB#6819)
    assessments (Feature AB#6748, Epic AB#6454):
      - src/collect/Invoke-Collect.ps1's new `mlWorkspaces`/`searchServices` (domains.ai) and
        `avdHostPools`/`avdSessionHosts`/`avdScalingPlans` (compute) / `logicalNetworks`
        (domains.hybrid) queries, plus the `nodeCount` addition to `azureLocalClusters`.
      - src/assess/rules/waf.ai.yaml (WAF-AI-*) and waf.avd.yaml (WAF-AVD-*).
      - manifests/assessments.psd1's 'Assess: AI Workload' / 'Assess: AVD Workload' entries.

    Search-AzGraph is mocked throughout for the collector tests -- no live Azure connection is
    made. The rule-engine tests use Resolve-JsonPath/Invoke-Rule directly against synthetic
    collect objects -- no YAML mutation. Each automated (non-manual) rule is proven non-vacuous:
    both a Fail/violating case and a Pass/clean case are exercised.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module Az.ResourceGraph -ErrorAction Stop
    Import-Module powershell-yaml -ErrorAction Stop
    . "$root/src/collect/Invoke-Collect.ps1"
    . "$root/src/assess/engine/Resolve-JsonPath.ps1"
    . "$root/src/assess/engine/Invoke-Rule.ps1"
    . "$root/src/assess/engine/Get-RuleSet.ps1"
}

Describe 'Invoke-Collect AI workload additions (AB#6818)' {
    BeforeEach {
        Mock Search-AzGraph {
            if ($Query -match 'microsoft\.machinelearningservices/workspaces') {
                return @(
                    [pscustomobject]@{ name = 'mlw-prod'; resourceGroup = 'rg-ai'; workspaceKind = 'Default'; publicAccess = 'Enabled'; identityType = 'SystemAssigned' }
                )
            }
            if ($Query -match 'microsoft\.search/searchservices') {
                return @(
                    [pscustomobject]@{ name = 'srch-prod'; resourceGroup = 'rg-ai'; sku = 'standard' }
                )
            }
            return @()
        }
    }

    It 'queries Microsoft.MachineLearningServices/workspaces and shapes it into domains.ai.mlWorkspaces' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('AI')
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.machinelearningservices/workspaces' } -Times 1
        $result.domains.ai.mlWorkspaces.Count | Should -Be 1
        $result.domains.ai.mlWorkspaces[0].name | Should -Be 'mlw-prod'
    }

    It 'queries Microsoft.Search/searchServices and shapes it into domains.ai.searchServices' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('AI')
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.search/searchservices' } -Times 1
        $result.domains.ai.searchServices.Count | Should -Be 1
        $result.domains.ai.searchServices[0].name | Should -Be 'srch-prod'
    }

    It 'still collects the pre-existing cognitiveAccounts query unchanged' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('AI')
        $result.domains.ai.PSObject.Properties.Name | Should -Contain 'cognitiveAccounts'
    }

    It 'the new AI queries are skipped when -Categories excludes AI' {
        Invoke-Collect -Source TypedQueries -Categories @('Security') | Out-Null
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.machinelearningservices/workspaces' } -Times 0 -Exactly
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.search/searchservices' } -Times 0 -Exactly
    }
}

Describe 'Invoke-Collect AVD-on-Azure-Local workload additions (AB#6819)' {
    BeforeEach {
        Mock Search-AzGraph {
            if ($Query -match 'microsoft\.desktopvirtualization/hostpools/sessionhosts') {
                return @(
                    [pscustomobject]@{ name = 'sh1.contoso.com'; hostPoolName = '/hp1'; status = 'Available'; agentVersion = '1.0.9.0' }
                    [pscustomobject]@{ name = 'sh2.contoso.com'; hostPoolName = '/hp1'; status = 'Unavailable'; agentVersion = '1.0.9.0' }
                )
            }
            elseif ($Query -match 'microsoft\.desktopvirtualization/hostpools') {
                return @(
                    [pscustomobject]@{ name = 'hp1'; resourceGroup = 'rg-avd'; hostPoolType = 'Pooled'; loadBalancerType = 'BreadthFirst'; maxSessionLimit = 10 }
                )
            }
            if ($Query -match 'microsoft\.desktopvirtualization/scalingplans') {
                return @(
                    [pscustomobject]@{ name = 'sp1'; resourceGroup = 'rg-avd'; hostPoolRefCount = 1 }
                )
            }
            if ($Query -match 'microsoft\.azurestackhci/logicalnetworks') {
                return @(
                    [pscustomobject]@{ name = 'ln1'; resourceGroup = 'rg-hci' }
                )
            }
            if ($Query -match 'microsoft\.azurestackhci/clusters') {
                return @(
                    [pscustomobject]@{ name = 'cluster1'; resourceGroup = 'rg-hci'; connectivityStatus = 'Connected'; nodeCount = 2 }
                )
            }
            return @()
        }
    }

    It 'queries hostpools and shapes it into compute.avdHostPools' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('Compute')
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.desktopvirtualization/hostpools"' } -Times 1
        $result.compute.avdHostPools.Count | Should -Be 1
        $result.compute.avdHostPools[0].hostPoolType | Should -Be 'Pooled'
    }

    It 'queries sessionhosts and shapes it into compute.avdSessionHosts' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('Compute')
        $result.compute.avdSessionHosts.Count | Should -Be 2
        ($result.compute.avdSessionHosts | Where-Object status -eq 'Unavailable').Count | Should -Be 1
    }

    It 'queries scalingplans and shapes it into compute.avdScalingPlans' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('Compute')
        $result.compute.avdScalingPlans.Count | Should -Be 1
    }

    It 'queries logicalnetworks and shapes it into domains.hybrid.logicalNetworks' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('Hybrid')
        $result.domains.hybrid.logicalNetworks.Count | Should -Be 1
    }

    It 'projects nodeCount onto azureLocalClusters' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('Hybrid')
        $result.domains.hybrid.azureLocalClusters[0].nodeCount | Should -Be 2
    }

    It 'the new AVD/Hybrid queries are skipped when -Categories excludes both' {
        Invoke-Collect -Source TypedQueries -Categories @('Security') | Out-Null
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.desktopvirtualization' } -Times 0 -Exactly
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.azurestackhci/logicalnetworks' } -Times 0 -Exactly
    }
}

Describe 'waf.ai.yaml rule set (AB#6818)' {
    BeforeAll {
        $script:ruleSet = Get-RuleSet -Patterns @('waf.ai')
    }

    It 'loads all 34 enumerated WAF-AI-* items with no duplicate ids' {
        $script:ruleSet.Rules.Count | Should -Be 34
        ($script:ruleSet.Rules.id | Sort-Object -Unique).Count | Should -Be 34
    }

    It 'declares framework WAF-AI, not WAF, because it is a workload review spanning multiple design areas' {
        $script:ruleSet.Framework | Should -Be 'WAF-AI'
    }

    It 'carries a non-empty frameworkversion citing the enumeration file' {
        $script:ruleSet.FrameworkVersion | Should -Match 'waf-ai-workload-checklist\.md'
    }

    It 'every rule id/title cites its WAF-AI checklist item id' {
        foreach ($rule in $script:ruleSet.Rules) {
            $rule.id | Should -Match '^WAF-AI-[A-Z]+-\d\d$'
            $escapedId = [regex]::Escape($rule.id); $rule.title | Should -Match $escapedId
        }
    }

    It 'every rule marked manual with no query has assert.type manual (no invented automation on unanswerable items)' {
        $unanswerable = $script:ruleSet.Rules | Where-Object { $_.manual -and -not $_.query }
        $unanswerable.Count | Should -BeGreaterThan 0
        foreach ($rule in $unanswerable) {
            $rule.assert.type | Should -Be 'manual'
        }
    }

    It 'WAF-AI-GROUND-02 fails (evidence-empty) when no AI Search service was collected' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AI-GROUND-02'
        $rule.manual | Should -BeFalse
        $collect = [pscustomobject]@{ domains = [pscustomobject]@{ ai = [pscustomobject]@{ searchServices = @() } } }
        $finding = Invoke-Rule -Rule $rule -Collect $collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Fail'
    }

    It 'WAF-AI-GROUND-02 passes and names the specific search service when one exists' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AI-GROUND-02'
        $collect = [pscustomobject]@{ domains = [pscustomobject]@{ ai = [pscustomobject]@{ searchServices = @([pscustomobject]@{ name = 'srch-prod'; resourceGroup = 'rg-ai'; sku = 'standard' }) } } }
        $finding = Invoke-Rule -Rule $rule -Collect $collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Pass'
        # AB#6938: Evidence is now always a real array (Invoke-Rule.ps1 wraps the single-match
        # case in @()), never a bare Newtonsoft JObject -- indexing with a string key relied on
        # JObject's OWN property indexer, which is exactly the shape that fragmented into orphan
        # one-field rows three layers down in Export-React. Index the array, then read the field.
        $finding.Evidence[0].name.ToString() | Should -Be 'srch-prod'
    }

    It 'WAF-AI-MLOPS-01 fails when no ML workspace was collected, passes and names it when one exists' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AI-MLOPS-01'
        $rule.manual | Should -BeFalse

        $empty = [pscustomobject]@{ domains = [pscustomobject]@{ ai = [pscustomobject]@{ mlWorkspaces = @() } } }
        (Invoke-Rule -Rule $rule -Collect $empty -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Fail'

        $populated = [pscustomobject]@{ domains = [pscustomobject]@{ ai = [pscustomobject]@{ mlWorkspaces = @([pscustomobject]@{ name = 'mlw-prod'; workspaceKind = 'Default' }) } } }
        $finding = Invoke-Rule -Rule $rule -Collect $populated -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Pass'
        # AB#6938: see the note on WAF-AI-GROUND-02 above -- Evidence is a real array now.
        $finding.Evidence[0].name.ToString() | Should -Be 'mlw-prod'
    }

    It 'a manual rule with a real query still resolves and surfaces evidence (WAF-AI-APPD-06)' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AI-APPD-06'
        $rule.manual | Should -BeTrue
        $rule.query | Should -Not -BeNullOrEmpty
        $collect = [pscustomobject]@{ domains = [pscustomobject]@{ ai = [pscustomobject]@{ mlWorkspaces = @([pscustomobject]@{ name = 'mlw-prod' }) } } }
        $finding = Invoke-Rule -Rule $rule -Collect $collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Manual'
        $finding.EvidenceCount | Should -Be 1
        @($finding.Evidence)[0]['name'].ToString() | Should -Be 'mlw-prod'
    }
}

Describe 'waf.avd.yaml rule set (AB#6819)' {
    BeforeAll {
        $script:ruleSet = Get-RuleSet -Patterns @('waf.avd')

        $script:collect = [pscustomobject]@{
            compute = [pscustomobject]@{
                virtualMachines = @()
                avdHostPools    = @([pscustomobject]@{ name = 'hp1'; resourceGroup = 'rg-avd'; hostPoolType = 'Pooled'; loadBalancerType = 'BreadthFirst'; maxSessionLimit = 10 })
                avdSessionHosts = @(
                    [pscustomobject]@{ name = 'sh1.contoso.com'; hostPoolName = '/hp1'; status = 'Available'; agentVersion = '1.0.9.0' }
                    [pscustomobject]@{ name = 'sh2.contoso.com'; hostPoolName = '/hp1'; status = 'Unavailable'; agentVersion = '1.0.9.0' }
                )
                avdScalingPlans = @()
            }
            management = [pscustomobject]@{
                backupProtectedItems  = @()
                logAnalyticsWorkspaces = @()
            }
            domains = [pscustomobject]@{
                hybrid = [pscustomobject]@{
                    azureLocalClusters = @([pscustomobject]@{ name = 'cluster1'; resourceGroup = 'rg-hci'; connectivityStatus = 'Connected'; nodeCount = 1 })
                    arcExtensions      = @()
                    logicalNetworks    = @()
                }
                management = [pscustomobject]@{ policyComplianceStates = @() }
            }
        }
    }

    It 'loads all 20 enumerated WAF-AVD-* items with no duplicate ids' {
        $script:ruleSet.Rules.Count | Should -Be 20
        ($script:ruleSet.Rules.id | Sort-Object -Unique).Count | Should -Be 20
    }

    It 'declares framework WAF-AVD, not WAF, because one file spans all five pillars' {
        $script:ruleSet.Framework | Should -Be 'WAF-AVD'
    }

    It 'declares area as a workload label, not one of the five WAF pillars (the gate this file must not cheat)' {
        $wafPillars = @('Reliability', 'Security', 'Cost optimization', 'Operational excellence', 'Performance efficiency')
        $script:ruleSet.Area | Should -Not -BeIn $wafPillars
    }

    It 'every rule id/title cites its WAF-AVD checklist item id' {
        foreach ($rule in $script:ruleSet.Rules) {
            $rule.id | Should -Match '^WAF-AVD-[A-Z]+-\d\d$'
            $escapedId = [regex]::Escape($rule.id); $rule.title | Should -Match $escapedId
        }
    }

    It 'WAF-AVD-RE-01 fails and names the single-node cluster' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-RE-01'
        $finding = Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Fail'
        # AB#6938: see the note on WAF-AI-GROUND-02 above -- Evidence is a real array now.
        $finding.Evidence[0].name.ToString() | Should -Be 'cluster1'
    }

    It 'WAF-AVD-RE-01 passes when the cluster reports 2+ nodes, and does not misreport an unreported cluster as single-node' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-RE-01'
        $healthy = [pscustomobject]@{ domains = [pscustomobject]@{ hybrid = [pscustomobject]@{ azureLocalClusters = @([pscustomobject]@{ name = 'cluster1'; nodeCount = 2 }) } } }
        (Invoke-Rule -Rule $rule -Collect $healthy -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Pass'

        $unreported = [pscustomobject]@{ domains = [pscustomobject]@{ hybrid = [pscustomobject]@{ azureLocalClusters = @([pscustomobject]@{ name = 'cluster2'; nodeCount = $null }) } } }
        (Invoke-Rule -Rule $rule -Collect $unreported -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Pass'
    }

    It 'WAF-AVD-RE-03 fails and names the unavailable session host' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-RE-03'
        $finding = Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Fail'
        # AB#6938: see the note on WAF-AI-GROUND-02 above -- Evidence is a real array now.
        $finding.Evidence[0].name.ToString() | Should -Be 'sh2.contoso.com'
    }

    It 'WAF-AVD-RE-03 passes when every session host is Available' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-RE-03'
        $healthy = [pscustomobject]@{ compute = [pscustomobject]@{ avdSessionHosts = @([pscustomobject]@{ name = 'sh1.contoso.com'; status = 'Available' }) } }
        (Invoke-Rule -Rule $rule -Collect $healthy -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Pass'
    }

    It 'WAF-AVD-SE-04 fails with no logical network, passes and names it once one is collected' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-SE-04'
        (Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Fail'

        $withLn = [pscustomobject]@{ domains = [pscustomobject]@{ hybrid = [pscustomobject]@{ logicalNetworks = @([pscustomobject]@{ name = 'ln1' }) } } }
        $finding = Invoke-Rule -Rule $rule -Collect $withLn -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Pass'
        # AB#6938: see the note on WAF-AI-GROUND-02 above -- Evidence is a real array now.
        $finding.Evidence[0].name.ToString() | Should -Be 'ln1'
    }

    It 'WAF-AVD-CO-06 fails with no scaling plan, passes and names it once one is collected' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-CO-06'
        (Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Fail'

        $withSp = [pscustomobject]@{ compute = [pscustomobject]@{ avdScalingPlans = @([pscustomobject]@{ name = 'sp1'; hostPoolRefCount = 1 }) } }
        $finding = Invoke-Rule -Rule $rule -Collect $withSp -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Pass'
        # AB#6938: see the note on WAF-AI-GROUND-02 above -- Evidence is a real array now.
        $finding.Evidence[0].name.ToString() | Should -Be 'sp1'
    }

    It 'WAF-AVD-OE-03 fails with no Arc extension, passes once one exists' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-OE-03'
        (Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Fail'

        $withExt = [pscustomobject]@{ domains = [pscustomobject]@{ hybrid = [pscustomobject]@{ arcExtensions = @([pscustomobject]@{ name = 'ext1'; machineId = 'm1' }) } } }
        (Invoke-Rule -Rule $rule -Collect $withExt -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Pass'
    }

    It 'WAF-AVD-OE-04 fails with no Log Analytics workspace, passes once one exists' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'WAF-AVD-OE-04'
        (Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Fail'

        $withWs = [pscustomobject]@{ management = [pscustomobject]@{ logAnalyticsWorkspaces = @([pscustomobject]@{ name = 'law1'; retentionInDays = 90 }) } }
        (Invoke-Rule -Rule $rule -Collect $withWs -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework).Status | Should -Be 'Pass'
    }

    It 'every rule marked manual with no query has assert.type manual (no invented automation on unanswerable items)' {
        $unanswerable = $script:ruleSet.Rules | Where-Object { $_.manual -and -not $_.query }
        $unanswerable.Count | Should -BeGreaterThan 0
        foreach ($rule in $unanswerable) {
            $rule.assert.type | Should -Be 'manual'
        }
    }
}

Describe 'manifests/assessments.psd1 — AI/AVD workload entries (AB#6818/AB#6819)' {
    BeforeAll {
        $script:Manifest = Import-PowerShellDataFile (Join-Path -Path $root -ChildPath 'manifests/assessments.psd1')
    }

    It 'has an AI Workload entry collecting only AI and scoring waf.ai' {
        $entry = $script:Manifest['Assess: AI Workload']
        $entry | Should -Not -BeNullOrEmpty
        $entry.Collect | Should -Be @('AI')
        $entry.Rules | Should -Be @('waf.ai')
    }

    It 'has an AVD Workload entry collecting Compute and Storage and scoring waf.avd' {
        $entry = $script:Manifest['Assess: AVD Workload']
        $entry | Should -Not -BeNullOrEmpty
        $entry.Collect | Should -Be @('Compute', 'Storage')
        $entry.Rules | Should -Be @('waf.avd')
    }

    It 'the AVD Workload description names the Azure-Local scope limitation, not general AVD' {
        $script:Manifest['Assess: AVD Workload'].Description | Should -Match 'Azure-Local'
    }

    It 'both entries have a rule file behind them, so Get-ScoutAvailableAssessment would offer them (AB#6763)' {
        . (Join-Path -Path $root -ChildPath 'src/assess/Get-ScoutAvailableAssessment.ps1')
        $ruleDir = Join-Path -Path $root -ChildPath 'src/assess/rules'
        $available = @(Get-ScoutAvailableAssessment -Manifest $script:Manifest -RuleDirectory $ruleDir)
        $available | Should -Contain 'Assess: AI Workload'
        $available | Should -Contain 'Assess: AVD Workload'
    }
}
