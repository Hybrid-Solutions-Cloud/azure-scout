#Requires -Version 7.0
#Requires -Modules Pester
#Requires -Modules Az.ResourceGraph

<#
    AB#6792 (Feature AB#6744) — "issues no Azure call beyond what an inventory run already
    makes". Pinned the same way tests/Collect.TenantWideProductionSplat.Tests.ps1 pins its
    production splat: mock the one function that actually calls Azure
    (Get-ScoutSubscriptionSecurityPolicySweep -> Get-AzPolicyState) and assert it is called
    exactly when, and only when, a compliance-scoring assessment asked for it.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    Import-Module Az.ResourceGraph -ErrorAction Stop
    . "$script:Root/src/collect/Invoke-Collect.ps1"
}

Describe 'AB#6792 — the policy-compliance sweep is opt-in on Invoke-Collect' {

    BeforeEach {
        Mock Search-AzGraph {
            if ($Query -match 'microsoft\.resources/subscriptions') {
                return @([pscustomobject]@{ id = 'sub-1'; name = 'Sub One'; state = 'Enabled'; tags = $null })
            }
            return @()
        }
        $script:SweepCalls = 0
        function Get-ScoutSubscriptionSecurityPolicySweep {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([object[]] $Subscriptions)
            $script:SweepCalls++
            @(
                [pscustomobject]@{
                    subscriptionId = 'sub-1'; subscriptionName = 'Sub One'
                    properties = [pscustomobject]@{
                        PolicyComplianceStates = @(
                            [pscustomobject]@{ PolicySetDefinitionId = 'init-1'; PolicyDefinitionId = 'p-1'; PolicyDefinitionName = 'Test policy'; ComplianceState = 'Compliant' }
                        )
                    }
                }
            )
        }
    }

    It 'does NOT call the compliance sweep on an ordinary (non-compliance) assessment collect' {
        $null = Invoke-Collect -Source TypedQueries -Categories @('Management')

        $script:SweepCalls | Should -Be 0
    }

    It 'calls the compliance sweep exactly once when -IncludePolicyCompliance is set' {
        $null = Invoke-Collect -Source TypedQueries -Categories @('Management') -IncludePolicyCompliance

        $script:SweepCalls | Should -Be 1
    }

    It 'threads the collected rows into domains.management.policyComplianceStates' {
        $collect = Invoke-Collect -Source TypedQueries -Categories @('Management') -IncludePolicyCompliance

        @($collect.domains.management.policyComplianceStates).Count | Should -Be 1
        $collect.domains.management.policyComplianceStates[0].PolicyDefinitionId | Should -Be 'p-1'
    }

    It 'a sweep failure degrades to empty compliance data, never throws the whole collect' {
        function Get-ScoutSubscriptionSecurityPolicySweep {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([object[]] $Subscriptions) throw 'Azure is having a day' }

        { $null = Invoke-Collect -Source TypedQueries -Categories @('Management') -IncludePolicyCompliance -WarningAction SilentlyContinue } | Should -Not -Throw
        $collect = Invoke-Collect -Source TypedQueries -Categories @('Management') -IncludePolicyCompliance -WarningAction SilentlyContinue
        @($collect.domains.management.policyComplianceStates).Count | Should -Be 0
    }
}

Describe 'AB#6792 — Invoke-ScoutAssessmentCore only asks for the sweep when Assess: Compliance is selected' {

    It 'sets IncludePolicyCompliance only for a Compliance-flagged manifest entry' {
        $source = Get-Content -Raw "$script:Root/src/Invoke-ScoutAssessmentCore.ps1"

        $source | Should -Match "ContainsKey\('Compliance'\)"
        $source | Should -Match 'IncludePolicyCompliance\s*=\s*\$true'
    }
}
