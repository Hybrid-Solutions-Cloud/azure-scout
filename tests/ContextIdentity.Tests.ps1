#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $env:AZURESCOUT_SKIP_UPDATE_CHECK = '1'
    Import-Module (Join-Path -Path $script:ModuleRoot -ChildPath 'AzureScout.psd1') -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object ModuleBase -eq $script:ModuleRoot | Select-Object -First 1
}

Describe 'Azure context display identity' {
    It 'resolves access-token GUIDs to the matching CLI user and tenant names' {
        $Result = & $script:Module {
            Mock Get-AZSCAccessibleTenant {
                @([pscustomobject]@{ Id = 'tenant-one'; Name = 'Tenant One' })
            }
            Mock Get-AZSCAzureCliAccount {
                [pscustomobject]@{
                    TenantId          = 'tenant-one'
                    TenantDisplayName = 'Tenant One'
                    UserName           = 'operator@example.test'
                }
            }

            Resolve-AZSCContextIdentity -Context ([pscustomobject]@{
                    Account = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Type = 'AccessToken' }
                    Tenant  = [pscustomobject]@{ Id = 'tenant-one' }
                })
        }

        $Result.AccountDisplayName | Should -Be 'operator@example.test'
        $Result.TenantDisplayName | Should -Be 'Tenant One'
    }

    It 'does not use Azure CLI identity data from a different tenant' {
        $Result = & $script:Module {
            Mock Get-AZSCAccessibleTenant { @() }
            Mock Get-AZSCAzureCliAccount {
                [pscustomobject]@{
                    TenantId          = 'other-tenant'
                    TenantDisplayName = 'Wrong Tenant'
                    UserName           = 'wrong@example.test'
                }
            }

            Resolve-AZSCContextIdentity -Context ([pscustomobject]@{
                    Account = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Type = 'AccessToken' }
                    Tenant  = [pscustomobject]@{ Id = 'target-tenant' }
                })
        }

        $Result.AccountDisplayName | Should -Be '11111111-1111-1111-1111-111111111111'
        $Result.TenantDisplayName | Should -Be 'target-tenant'
    }

    It 'falls back to unique Azure CLI tenants when Get-AzTenant is unavailable' {
        $Result = & $script:Module {
            Mock Get-AzTenant { throw 'access-token context has no tenant enumeration token' }
            Mock Get-AZSCAzureCliTenant {
                @(
                    [pscustomobject]@{ Id = 'tenant-two'; Name = 'Tenant Two' }
                    [pscustomobject]@{ Id = 'tenant-one'; Name = 'Tenant One' }
                    [pscustomobject]@{ Id = 'tenant-one'; Name = 'Tenant One' }
                )
            }

            @(Get-AZSCAccessibleTenant)
        }

        $Result.Count | Should -Be 2
        $Result.Name | Should -Be @('Tenant One', 'Tenant Two')
    }
}

Describe 'Wizard tenant-first behavior' {
    It 'keeps the confirmed tenant without opening a tenant or subscription selector' {
        & $script:Module {
            Mock Write-Host {}
            Mock Get-AzContext {
                [pscustomobject]@{
                    Account = [pscustomobject]@{ Id = 'operator@example.test' }
                    Tenant  = [pscustomobject]@{ Id = 'tenant-one' }
                }
            }
            Mock Resolve-AZSCContextIdentity {
                [pscustomobject]@{
                    AccountDisplayName = 'operator@example.test'
                    TenantDisplayName  = 'Tenant One'
                    TenantId           = 'tenant-one'
                }
            }
            Mock Read-AZSCWizardConfirm { $true } -ParameterFilter { $Prompt -eq 'Use this account and tenant?' }
            Mock Test-AZSCPermissions { [pscustomobject]@{ Details = @(); OverallReadiness = 'ARMOnly' } }
            Mock Read-AZSCWizardChoice { $null } -ParameterFilter { $Title -eq 'Choose a run type' }
            Mock Get-AZSCAccessibleTenant { throw 'confirmed tenant must not enumerate tenants' }
            Mock Connect-AZSCLoginSession { throw 'confirmed tenant must not authenticate again' }

            $null = Start-AZSCWizard -AzureEnvironment AzureCloud -PlatOS Windows

            Should -Not -Invoke Get-AZSCAccessibleTenant
            Should -Not -Invoke Connect-AZSCLoginSession
        }
    }

    It 'forces login after N and leaves permission validation to the selected-scope run preflight' {
        & $script:Module {
            Mock Write-Host {}
            Mock Get-AzContext {
                [pscustomobject]@{
                    Account = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Type = 'AccessToken' }
                    Tenant  = [pscustomobject]@{ Id = 'tenant-old' }
                }
            }
            Mock Resolve-AZSCContextIdentity {
                [pscustomobject]@{
                    AccountDisplayName = 'operator@example.test'
                    TenantDisplayName  = 'Tenant Old'
                    TenantId           = 'tenant-old'
                }
            }
            Mock Read-AZSCWizardConfirm {
                if ($Prompt -eq 'Use this account and tenant?') { return $false }
                if ($Prompt -like 'Sign in with a device code*') { return $false }
                return $false
            }
            Mock Connect-AZSCLoginSession { 'tenant-default' }
            Mock Get-AZSCAccessibleTenant {
                @(
                    [pscustomobject]@{ Id = 'tenant-one'; Name = 'Tenant One' }
                    [pscustomobject]@{ Id = 'tenant-two'; Name = 'Tenant Two' }
                )
            }
            Mock Read-AZSCWizardChoice {
                if ($Title -eq 'Select the tenant to scan') { return 'tenant-two' }
                if ($Title -eq 'Choose a run type') { return $null }
            }
            Mock Test-AZSCPermissions { [pscustomobject]@{ Details = @(); OverallReadiness = 'ARMOnly' } }

            $null = Start-AZSCWizard -AzureEnvironment AzureCloud -PlatOS Windows

            Should -Invoke Connect-AZSCLoginSession -Times 1 -Exactly -ParameterFilter { $ForceLogin }
            Should -Invoke Read-AZSCWizardChoice -Times 1 -Exactly -ParameterFilter { $Title -eq 'Select the tenant to scan' }
            Should -Not -Invoke Test-AZSCPermissions
        }
    }
}
