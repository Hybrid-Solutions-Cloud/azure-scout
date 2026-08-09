#Requires -Version 7.0
#Requires -Modules Pester

<#
    Pester tests for src/collect/Get-ScoutCostInventory.ps1 (AB#5639/5647, Epic AB#5638).

    Invoke-AzCostManagementQuery is mocked (or deliberately left undefined, to simulate
    Az.CostManagement not being installed) throughout -- no live Azure connection is made.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/collect/Get-ScoutCostInventory.ps1"

    $script:subs = @(
        [pscustomobject]@{ id = 'sub-1'; name = 'sub-one' }
        [pscustomobject]@{ id = 'sub-2'; name = 'sub-two' }
    )
}

Describe 'Get-ScoutCostInventory -- Az.CostManagement not installed' {
    It 'never throws, warns once with the install command, and returns @() CostData for every subscription' {
        # No Invoke-AzCostManagementQuery function defined at all -- Get-Command must not find it.
        { Get-ScoutCostInventory -Subscriptions $script:subs -WarningAction SilentlyContinue } | Should -Not -Throw
        $result = @(Get-ScoutCostInventory -Subscriptions $script:subs -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 2
        @($result[0].CostData).Count | Should -Be 0
        @($result[1].CostData).Count | Should -Be 0
        ($warnings -join "`n") | Should -Match 'Az.CostManagement'
        ($warnings -join "`n") | Should -Match 'Install-Module'
    }
}

Describe 'Get-ScoutCostInventory -- happy path' {
    It 'returns CostData rows per subscription when Az.CostManagement succeeds' {
        function Invoke-AzCostManagementQuery {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest)
            return @([pscustomobject]@{ PreTaxCost = 42.5 })
        }
        $result = @(Get-ScoutCostInventory -Subscriptions $script:subs)
        $result.Count | Should -Be 2
        $result[0].SubscriptionId | Should -Be 'sub-1'
        $result[0].CostData[0].PreTaxCost | Should -Be 42.5
    }
}

Describe 'Get-ScoutCostInventory -- per-subscription resilience (AB#5636 regression guard)' {
    It 'degrades ONLY the failing subscription to empty CostData and keeps collecting the rest -- never throws' {
        function Invoke-AzCostManagementQuery {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([string] $Scope, [Parameter(ValueFromRemainingArguments)] $Rest)
            if ($Scope -match 'sub-1') { throw 'Cost Management API transient error' }
            return @([pscustomobject]@{ PreTaxCost = 10 })
        }
        { Get-ScoutCostInventory -Subscriptions $script:subs -WarningAction SilentlyContinue } | Should -Not -Throw
        $result = @(Get-ScoutCostInventory -Subscriptions $script:subs -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 2
        @(($result | Where-Object SubscriptionId -eq 'sub-1').CostData).Count | Should -Be 0
        (($result | Where-Object SubscriptionId -eq 'sub-2').CostData)[0].PreTaxCost | Should -Be 10
        ($warnings -join "`n") | Should -Match "sub-one"
    }
}

Describe 'Get-ScoutCostInventory -- date range selection' {
    It 'queries the full previous calendar year when -Days is >= 365' {
        $script:capturedFrom = $null
        $script:capturedTo = $null
        function Invoke-AzCostManagementQuery {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([datetime] $TimePeriodFrom, [datetime] $TimePeriodTo, [Parameter(ValueFromRemainingArguments)] $Rest)
            $script:capturedFrom = $TimePeriodFrom
            $script:capturedTo = $TimePeriodTo
            return @()
        }
        Get-ScoutCostInventory -Subscriptions @($script:subs[0]) -Days 365 | Out-Null
        $script:capturedFrom.Month | Should -Be 1
        $script:capturedFrom.Day | Should -Be 1
        $script:capturedTo.Month | Should -Be 12
        $script:capturedTo.Day | Should -Be 31
        $script:capturedFrom.Year | Should -Be $script:capturedTo.Year
    }
}
