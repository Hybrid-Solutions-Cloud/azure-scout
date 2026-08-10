#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:Root 'src/collect/Start-ScoutDevOpsExtraction.ps1')
}

Describe 'Start-AZSCDevOpsExtraction paging' {
    BeforeEach {
        Mock Get-AzAccessToken { [pscustomobject]@{ Token = 'token' } }
        $script:projectPage = 0
        Mock Invoke-AZSCDevOpsRestPage {
            if ($Uri -match '/_apis/projects') {
                $script:projectPage++
                if ($script:projectPage -eq 1) {
                    return [pscustomobject]@{
                        Headers = @{ 'x-ms-continuationtoken' = 'next page' }
                        Body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'p1'; name = 'one' }) }
                    }
                }
                return [pscustomobject]@{ Headers = @{}; Body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'p2'; name = 'two' }) } }
            }
            return [pscustomobject]@{ Headers = @{}; Body = [pscustomobject]@{ value = @() } }
        }
    }

    It 'follows continuation tokens and includes each page exactly once' {
        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-a' -Organization 'contoso'
        $projects = @($result.DevOpsResources | Where-Object type -eq 'devops/projects')

        $projects.Count | Should -Be 2
        @($projects.name) | Should -Be @('one', 'two')
        Should -Invoke Invoke-AZSCDevOpsRestPage -Times 2 -ParameterFilter { $Uri -match '/_apis/projects' }
        Should -Invoke Invoke-AZSCDevOpsRestPage -Times 1 -ParameterFilter { $Uri -match 'continuationToken=next%20page' }
    }

    It 'captures response headers from the real REST wrapper' {
        $source = Get-Content -LiteralPath (Join-Path $script:Root 'src/collect/Start-ScoutDevOpsExtraction.ps1') -Raw
        $source | Should -Match 'Invoke-RestMethod.*-ResponseHeadersVariable responseHeaders'
    }
}
