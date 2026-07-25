<#
    AB#5636 — cost data is optional enrichment and must never cost the caller their inventory.

    The original catch block ran `throw $_.Exception.Message` with an unreachable
    `$Costs = @()` on the line after it, so the intended fallback never executed and any
    Cost Management failure destroyed the entire run. On a machine without
    Az.CostManagement installed, -IncludeCosts lost the whole report.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Modules/Private/Main/Write-AZTIRunLog.ps1')
    . (Join-Path $script:RepoRoot 'Modules/Private/Extraction/Get-AZTICostInventory.ps1')

    # Pester cannot mock a command that does not exist, and the whole point of AB#5636 is
    # that Az.CostManagement may be absent. Stub it so the mocks below have something to
    # replace; the real module, when present, takes precedence outside these tests.
    if (-not (Get-Command Invoke-AzCostManagementQuery -ErrorAction SilentlyContinue)) {
        function global:Invoke-AzCostManagementQuery {
            param($Type, $Scope, $Timeframe, $DatasetGranularity, $DatasetGrouping,
                  $DatasetAggregation, $TimePeriodFrom, $TimePeriodTo, $Debug)
        }
    }

    $script:Subs = @(
        [pscustomobject]@{ id = 'sub-1'; name = 'First subscription' }
        [pscustomobject]@{ id = 'sub-2'; name = 'Second subscription' }
    )
}

Describe 'Get-AZSCCostInventory resilience' {

    It 'completes instead of throwing when Az.CostManagement is not installed' {
        Mock -CommandName Invoke-AzCostManagementQuery -MockWith {
            throw "The term 'Invoke-AzCostManagementQuery' is not recognized as a name of a cmdlet, function, script file, or executable program."
        }
        { Get-AZSCCostInventory -Subscriptions $script:Subs -Days 60 -Granularity 'Monthly' -WarningAction SilentlyContinue } |
            Should -Not -Throw
    }

    It 'names the install command so the operator can act on it' {
        Mock -CommandName Invoke-AzCostManagementQuery -MockWith {
            throw "The term 'Invoke-AzCostManagementQuery' is not recognized as a name of a cmdlet, function, script file, or executable program."
        }
        # Captured by stream redirection rather than -WarningVariable: Get-AZSCCostInventory
        # is a simple function, so the common warning parameters are not reliable here.
        $Warnings = @(Get-AZSCCostInventory -Subscriptions $script:Subs -Days 60 -Granularity 'Monthly' 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        ($Warnings -join ' ') | Should -Match 'Install-Module Az.CostManagement'
    }

    It 'still returns one row per subscription, with empty cost data' {
        Mock -CommandName Invoke-AzCostManagementQuery -MockWith { throw 'Cost Management is unavailable' }
        $Result = @(Get-AZSCCostInventory -Subscriptions $script:Subs -Days 60 -Granularity 'Monthly' -WarningAction SilentlyContinue)
        $Result.Count | Should -Be 2
        @($Result[0].CostData).Count | Should -Be 0
        $Result[1].SubscriptionName | Should -Be 'Second subscription'
    }

    It 'keeps collecting the remaining subscriptions after one fails' {
        # One bad subscription must not take the others down with it.
        Mock -CommandName Invoke-AzCostManagementQuery -MockWith {
            if ($Scope -like '*sub-1*') { throw 'Subscription not enrolled for Cost Management' }
            return @([pscustomobject]@{ PreTaxCost = 42 })
        }
        $Result = @(Get-AZSCCostInventory -Subscriptions $script:Subs -Days 60 -Granularity 'Monthly' -WarningAction SilentlyContinue)
        @($Result[0].CostData).Count | Should -Be 0
        @($Result[1].CostData).Count | Should -Be 1
    }

    It 'warns with the underlying message for a non-dependency failure' {
        Mock -CommandName Invoke-AzCostManagementQuery -MockWith { throw 'Subscription not enrolled for Cost Management' }
        $Warnings = @(Get-AZSCCostInventory -Subscriptions $script:Subs -Days 60 -Granularity 'Monthly' 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        ($Warnings -join ' ') | Should -Match 'not enrolled for Cost Management'
    }

    It 'returns the cost data unchanged on the success path' {
        Mock -CommandName Invoke-AzCostManagementQuery -MockWith { return @([pscustomobject]@{ PreTaxCost = 7 }) }
        $Result = @(Get-AZSCCostInventory -Subscriptions $script:Subs -Days 60 -Granularity 'Monthly')
        $Result.Count | Should -Be 2
        $Result[0].CostData[0].PreTaxCost | Should -Be 7
    }
}

Describe 'Cost dependency stays opt-in' {

    It 'does NOT auto-install Az.CostManagement on module import' {
        # Auto-installing it drags in a newer Az.Accounts as a dependency. On a machine that
        # already has Az.Accounts that leaves two versions side by side, and every subsequent
        # Import-Module dies with a stack overflow inside Az.Accounts' assembly-load-context
        # resolver. Observed on a working machine, caused by exactly this line. (AB#5636)
        $Psm1 = Get-Content -Path (Join-Path $script:RepoRoot 'AzureScout.psm1')
        $Bootstrap = $Psm1 | Where-Object { $_ -notmatch '^\s*#' }
        ($Bootstrap -join "`n") | Should -Not -Match "'Az\.CostManagement'"
    }

    It 'documents Az.CostManagement as an optional prerequisite instead' {
        $Prereq = Get-Content -Raw -Path (Join-Path $script:RepoRoot 'docs/prerequisites.md')
        $Prereq | Should -Match 'Az\.CostManagement'
        $Prereq | Should -Match 'IncludeCosts'
    }
}

Describe 'The dead-code fallback is gone' {

    It 'no longer rethrows out of the cost collector' {
        $Raw = Get-Content -Path (Join-Path $script:RepoRoot 'Modules/Private/Extraction/Get-AZTICostInventory.ps1')
        $Active = ($Raw | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $Active | Should -Not -Match 'throw \$_\.Exception\.Message'
    }
}
