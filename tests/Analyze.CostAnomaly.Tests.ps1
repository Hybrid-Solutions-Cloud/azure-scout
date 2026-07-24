#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/analyze/Get-ScoutCostAnomaly.ps1 — cost anomaly
    detection (ADO Story AB#324). Uses synthetic cost datasets (both the raw
    Get-AZSCCostInventory shape and a pre-normalized shape) — no Azure
    connection required, no network calls.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/analyze/Get-ScoutCostAnomaly.ps1"

    # Raw Get-AZSCCostInventory shape: Row order is
    # [cost, usageDate, resourceType, resourceGroup, resourceLocation, serviceName, currency]
    function New-RawCostBlock {
        param([string] $SubscriptionId, [string] $SubscriptionName, [array] $Rows)
        [pscustomobject]@{
            SubscriptionId   = $SubscriptionId
            SubscriptionName = $SubscriptionName
            CostData         = [pscustomobject]@{ Row = $Rows }
        }
    }
}

Describe 'Get-ScoutCostAnomaly -- graceful degradation with no data' {
    It 'returns HasData = $false and a clear message for $null input' {
        $result = Get-ScoutCostAnomaly -CostData $null
        $result.HasData | Should -BeFalse
        $result.Message | Should -Not -BeNullOrEmpty
        $result.Anomalies | Should -BeNullOrEmpty
        $result.TopMovers | Should -BeNullOrEmpty
    }

    It 'returns HasData = $false for an empty array' {
        $result = Get-ScoutCostAnomaly -CostData @()
        $result.HasData | Should -BeFalse
        $result.RecordCount | Should -Be 0
    }

    It 'does not throw' {
        { Get-ScoutCostAnomaly -CostData $null } | Should -Not -Throw
    }
}

Describe 'Get-ScoutCostAnomaly -- flat data produces no anomalies' {
    BeforeAll {
        $flat = 1..6 | ForEach-Object {
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'virtualMachines'; Period = "2026-0$_"; Amount = 500.00 }
        }
        $script:Result = Get-ScoutCostAnomaly -CostData $flat -MinDataPoints 4
    }

    It 'flags zero anomalies against a perfectly flat series' {
        $script:Result.HasData | Should -BeTrue
        $script:Result.Anomalies.Count | Should -Be 0
    }

    It 'still returns top movers with zero delta' {
        $script:Result.TopMovers.Count | Should -BeGreaterThan 0
        $script:Result.TopMovers[0].DeltaAmount | Should -Be 0
    }
}

Describe 'Get-ScoutCostAnomaly -- injected spike is flagged (pre-normalized dataset)' {
    BeforeAll {
        $data = @(
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'virtualMachines'; Period = '2026-01'; Amount = 500.00 }
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'virtualMachines'; Period = '2026-02'; Amount = 510.00 }
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'virtualMachines'; Period = '2026-03'; Amount = 495.00 }
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'virtualMachines'; Period = '2026-04'; Amount = 505.00 }
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'virtualMachines'; Period = '2026-05'; Amount = 5000.00 }  # clear spike
            # unrelated flat group -- must not be flagged
            [pscustomobject]@{ Scope = 'sub-dev'; ResourceType = 'storageAccounts'; Period = '2026-01'; Amount = 50.00 }
            [pscustomobject]@{ Scope = 'sub-dev'; ResourceType = 'storageAccounts'; Period = '2026-02'; Amount = 50.00 }
            [pscustomobject]@{ Scope = 'sub-dev'; ResourceType = 'storageAccounts'; Period = '2026-03'; Amount = 50.00 }
            [pscustomobject]@{ Scope = 'sub-dev'; ResourceType = 'storageAccounts'; Period = '2026-04'; Amount = 50.00 }
        )
        $script:Result = Get-ScoutCostAnomaly -CostData $data -MinDataPoints 4
    }

    It 'flags the spiking group' {
        $script:Result.HasData | Should -BeTrue
        $script:Result.Anomalies.Count | Should -BeGreaterThan 0
        ($script:Result.Anomalies | Where-Object { $_.Scope -eq 'sub-prod' -and $_.ResourceType -eq 'virtualMachines' }).Count | Should -BeGreaterThan 0
    }

    It 'flags it with Critical or High severity' {
        $flagged = $script:Result.Anomalies | Where-Object { $_.Scope -eq 'sub-prod' }
        $flagged.Severity | Should -Contain 'Critical'
    }

    It 'does not flag the unrelated flat group' {
        @($script:Result.Anomalies | Where-Object { $_.Scope -eq 'sub-dev' }).Count | Should -Be 0
    }

    It 'reports the spike as the top mover' {
        $script:Result.TopMovers[0].Scope | Should -Be 'sub-prod'
        $script:Result.TopMovers[0].DeltaAmount | Should -BeGreaterThan 1000
    }
}

Describe 'Get-ScoutCostAnomaly -- raw Get-AZSCCostInventory shape is understood' {
    BeforeAll {
        $rows = @(
            , @(100.00, '2026-01-01', 'virtualMachines', 'rg-workload1', 'eastus', 'Virtual Machines', 'USD')
            , @(105.00, '2026-02-01', 'virtualMachines', 'rg-workload1', 'eastus', 'Virtual Machines', 'USD')
            , @(98.00, '2026-03-01', 'virtualMachines', 'rg-workload1', 'eastus', 'Virtual Machines', 'USD')
            , @(4000.00, '2026-04-01', 'virtualMachines', 'rg-workload1', 'eastus', 'Virtual Machines', 'USD')
        )
        $raw = @( New-RawCostBlock -SubscriptionId 'sub-0001' -SubscriptionName 'sub-prod' -Rows $rows )
        $script:Result = Get-ScoutCostAnomaly -CostData $raw -MinDataPoints 4
    }

    It 'normalizes and processes the raw extraction shape without throwing' {
        $script:Result.HasData | Should -BeTrue
        $script:Result.RecordCount | Should -Be 4
    }

    It 'flags the injected spike from the raw shape' {
        $script:Result.Anomalies.Count | Should -BeGreaterThan 0
        $script:Result.Anomalies[0].Scope | Should -Be 'sub-prod'
    }
}

Describe 'Get-ScoutCostAnomaly -- spike-only detection with short (2-period) series' {
    It 'flags a sudden spike even with only 2 periods (below MinDataPoints)' {
        $data = @(
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'sqlDatabases'; Period = '2026-01'; Amount = 200.00 }
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'sqlDatabases'; Period = '2026-02'; Amount = 900.00 }
        )
        $result = Get-ScoutCostAnomaly -CostData $data -MinDataPoints 4
        $result.Anomalies.Count | Should -Be 1
        $result.Anomalies[0].Method | Should -Be 'Spike'
    }

    It 'does not flag a mild 2-period change under the spike threshold' {
        $data = @(
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'sqlDatabases'; Period = '2026-01'; Amount = 200.00 }
            [pscustomobject]@{ Scope = 'sub-prod'; ResourceType = 'sqlDatabases'; Period = '2026-02'; Amount = 220.00 }
        )
        $result = Get-ScoutCostAnomaly -CostData $data
        $result.Anomalies.Count | Should -Be 0
    }
}
