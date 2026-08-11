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

        @($result.CollectionHealth).Count | Should -Be 0
    }

    It 'retains an enabled Entra failure while excluding disabled catalog entries' {
        $script:EntraOutcomes[2] = [pscustomobject]@{
            Type = 'entra/users'; Name = 'Users'; Status = 'Failed'; Reason = 'simulated failure'
        }

        $result = Start-AZSCExtractionOrchestration -Scope EntraOnly -TenantID 'tenant-test'

        @($result.CollectionHealth).Count | Should -Be 1
        $result.CollectionHealth[0].Dataset | Should -Be 'Entra/Users'
        $result.CollectionHealth[0].Status | Should -Be 'Failed'
        @($result.CollectionHealth[0].ResourceTypes) | Should -Be @('entra/users')
    }
}
