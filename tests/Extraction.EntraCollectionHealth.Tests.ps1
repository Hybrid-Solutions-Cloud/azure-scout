#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src/collect/Get-ScoutEntraQueryCatalog.ps1')
    . (Join-Path $script:RepoRoot 'src/Start-AZTIExtractionOrchestration.ps1')

    function Start-AZSCEntraExtraction {
        param([string] $TenantID)
        return [pscustomobject]@{
            EntraResources = @()
            QueryOutcomes  = @($script:EntraOutcomes)
        }
    }

    function Resolve-ScoutOrphanedRoleAssignment {
        param([object[]] $Resources, [object[]] $EntraQueryOutcomes)
        return @($Resources)
    }
}

Describe 'Start-AZSCExtractionOrchestration Entra collection health' {
    BeforeEach {
        $script:EntraOutcomes = @(
            [pscustomobject]@{
                Type = 'entra/identityproviders'; Name = 'Identity Providers'
                Status = 'NotAssessed'; Reason = 'No released Scout collector consumes this dataset.'
            }
            [pscustomobject]@{
                Type = 'entra/securitydefaults'; Name = 'Security Defaults'
                Status = 'NotAssessed'; Reason = 'No released Scout collector consumes this dataset.'
            }
            [pscustomobject]@{
                Type = 'entra/users'; Name = 'Users'; Status = 'Success'; Reason = $null
            }
        )
    }

    It 'preserves disabled query outcomes without marking a healthy run Partial' {
        $result = Start-AZSCExtractionOrchestration -Scope EntraOnly -TenantID 'tenant-test'

        # Only the opt-in sources that were not requested appear, and only as not assessed.
        @($result.CollectionHealth | Where-Object Status -ne 'NotAssessed').Count | Should -Be 0
        @($result.CollectionHealth | Where-Object Dataset -like 'Entra/*').Count | Should -Be 0
    }

    It 'marks Okta, on-premises identity and Azure DevOps as not requested when their switches are absent' {
        $result = Start-AZSCExtractionOrchestration -Scope EntraOnly -TenantID 'tenant-test'
        $notRequested = @($result.CollectionHealth | Where-Object Operation -eq 'Not requested')

        @($notRequested.Dataset | Sort-Object) | Should -Be @('Azure DevOps', 'HybridIdentity/Local', 'Okta')
        @($notRequested.Status | Sort-Object -Unique) | Should -Be @('NotAssessed')
        @(($notRequested | Where-Object Dataset -eq 'Okta').ResourceTypes) | Should -Be @('AZSC/Okta/*')
        @(($notRequested | Where-Object Dataset -eq 'Azure DevOps').Collectors) | Should -Contain 'DevOps/DevOpsProjects'
    }

    It 'retains an enabled Entra failure while excluding disabled catalog entries' {
        $script:EntraOutcomes[2] = [pscustomobject]@{
            Type = 'entra/users'; Name = 'Users'; Status = 'Failed'; Reason = 'simulated failure'
        }

        $result = Start-AZSCExtractionOrchestration -Scope EntraOnly -TenantID 'tenant-test'
        $entraHealth = @($result.CollectionHealth | Where-Object Dataset -like 'Entra/*')

        $entraHealth.Count | Should -Be 1
        $entraHealth[0].Dataset | Should -Be 'Entra/Users'
        $entraHealth[0].Status | Should -Be 'Failed'
        @($entraHealth[0].ResourceTypes) | Should -Be @('entra/users')
    }
}
