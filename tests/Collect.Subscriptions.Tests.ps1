#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:root = Split-Path -Parent $PSScriptRoot
    . "$script:root/src/collect/Get-ScoutSubscriptions.ps1"
}

Describe 'Get-AZSCSubscriptions runnable scope' {
    BeforeEach {
        function global:Get-AzSubscription {
            param($TenantId, $WarningAction, $Debug)
            $null = $TenantId, $WarningAction, $Debug
            @(
                [pscustomobject]@{ Id = 'enabled-sub'; Name = 'Enabled'; State = 'Enabled' }
                [pscustomobject]@{ Id = 'disabled-sub'; Name = 'Disabled'; State = 'Disabled' }
                [pscustomobject]@{ Id = 'legacy-sub'; Name = 'Legacy shape' }
            )
        }
    }

    AfterEach {
        Remove-Item Function:\Get-AzSubscription -Force -ErrorAction SilentlyContinue
    }

    It 'excludes explicitly disabled subscriptions while retaining enabled and legacy shapes' {
        $subscriptions = @(Get-AZSCSubscriptions -TenantID 'tenant-one' -PlatOS 'PowerShell')

        @($subscriptions.Id) | Should -Be @('enabled-sub', 'legacy-sub')
    }

    It 'does not return an explicitly requested disabled subscription' {
        $subscriptions = @(Get-AZSCSubscriptions -TenantID 'tenant-one' -SubscriptionID 'disabled-sub' -PlatOS 'PowerShell')

        $subscriptions | Should -BeNullOrEmpty
    }
}
