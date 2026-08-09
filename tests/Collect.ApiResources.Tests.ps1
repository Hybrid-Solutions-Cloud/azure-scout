#Requires -Version 7.0
#Requires -Modules Pester

<#
    Pester tests for src/collect/Get-ScoutApiResources.ps1 (AB#5639/5645, Epic AB#5638).

    Get-AzAccessToken / Invoke-RestMethod are mocked throughout -- no live Azure connection
    is made, and no real bearer token is ever produced or logged.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/collect/Get-ScoutApiResources.ps1"

    # The real function is deliberately polite to ARM (Start-Sleep between calls) -- no need
    # to actually wait in a unit test.
    function Start-Sleep {         [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }

    function Get-AzAccessToken {
                [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Synthetic fake-credential value used only to satisfy a SecureString-typed mock return in this test -- not a real secret.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest)
        [pscustomobject]@{ Token = (ConvertTo-SecureString -String 'fake-token' -AsPlainText -Force) }
    }

    $script:subs = @(
        [pscustomobject]@{ id = 'sub-1'; name = 'sub-one' }
        [pscustomobject]@{ id = 'sub-2'; name = 'sub-two' }
    )
}

Describe 'Get-ScoutApiResources -- happy path' {
    It 'returns one row per subscription with every field populated' {
        function Invoke-RestMethod {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([string] $Uri, [hashtable] $Headers, [string] $Method)
            if ($Uri -match 'ResourceHealth') { return [pscustomobject]@{ value = @('health-event') } }
            if ($Uri -match 'ManagedIdentity') { return [pscustomobject]@{ value = @('identity-1') } }
            if ($Uri -match 'advisorScore') { return [pscustomobject]@{ value = @('score-1') } }
            if ($Uri -match 'reservationRecommendations') { return [pscustomobject]@{ value = @('reservation-1') } }
            if ($Uri -match 'Microsoft.Edge/sites') { return [pscustomobject]@{ value = @('site-1') } }
            if ($Uri -match 'policyStates') { return [pscustomobject]@{ value = @('policy-state-1') } }
            if ($Uri -match 'policySetDefinitions') { return [pscustomobject]@{ value = @('set-def-1') } }
            if ($Uri -match 'policyDefinitions') { return [pscustomobject]@{ value = @('def-1') } }
            return [pscustomobject]@{ value = @() }
        }
        $result = @(Get-ScoutApiResources -Subscriptions $script:subs)
        $result.Count | Should -Be 2
        $result[0].Subscription | Should -Be 'sub-1'
        $result[0].ResourceHealth | Should -Be @('health-event')
        $result[0].ManagedIdentities | Should -Be @('identity-1')
        $result[0].AdvisorScore | Should -Be @('score-1')
        $result[0].ReservationRecommendations | Should -Be @('reservation-1')
        $result[0].ArcSites | Should -Be @('site-1')
        $result[0].PolicyAssignments | Should -Be @('policy-state-1')
    }

    It 'calls Microsoft.Edge/sites once per subscription (AB#6801)' {
        $script:edgeCalls = 0
        function Invoke-RestMethod {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([string] $Uri, [hashtable] $Headers, [string] $Method)
            if ($Uri -match 'Microsoft\.Edge/sites\?api-version=2024-02-01-preview') { $script:edgeCalls++ }
            return [pscustomobject]@{ value = @() }
        }
        Get-ScoutApiResources -Subscriptions $script:subs | Out-Null
        $script:edgeCalls | Should -Be 2
    }
}

Describe 'Get-ScoutApiResources -- per-call resilience' {
    It 'degrades only the failing field to $null and keeps every other field and every other subscription' {
        function Invoke-RestMethod {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([string] $Uri, [hashtable] $Headers, [string] $Method)
            if ($Uri -match 'ManagedIdentity') { throw 'AuthorizationFailed' }
            return [pscustomobject]@{ value = @('ok') }
        }
        $result = @(Get-ScoutApiResources -Subscriptions $script:subs)
        $result.Count | Should -Be 2
        $result[0].ManagedIdentities | Should -BeNullOrEmpty
        $result[0].ResourceHealth | Should -Be @('ok')
        $result[1].ManagedIdentities | Should -BeNullOrEmpty
        $result[1].ResourceHealth | Should -Be @('ok')
    }

    It 'does not throw and returns an empty result when the access token cannot be acquired' {
        function Get-AzAccessToken { throw 'no context' }
        { Get-ScoutApiResources -Subscriptions $script:subs -WarningAction SilentlyContinue } | Should -Not -Throw
        @(Get-ScoutApiResources -Subscriptions $script:subs -WarningAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe 'Get-ScoutApiResources -- SkipPolicy' {
    It 'skips all three policy calls when -SkipPolicy is supplied' {
        $script:policyCalls = 0
        function Invoke-RestMethod {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([string] $Uri, [hashtable] $Headers, [string] $Method)
            if ($Uri -match 'policy' -or $Uri -match 'Policy') { $script:policyCalls++ }
            return [pscustomobject]@{ value = @() }
        }
        Get-ScoutApiResources -Subscriptions $script:subs -SkipPolicy | Out-Null
        $script:policyCalls | Should -Be 0
    }
}
