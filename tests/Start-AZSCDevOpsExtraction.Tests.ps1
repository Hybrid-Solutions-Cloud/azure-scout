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

    It 'keeps an authoritative zero-project response clean and still queries organization agent pools' {
        Mock Invoke-AZSCDevOpsRestPage {
            return [pscustomobject]@{ Headers = @{}; Body = [pscustomobject]@{ value = @() } }
        }
        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-a' -Organization 'contoso'

        @($result.DevOpsResources).Count | Should -Be 0
        @($result.CollectionHealth).Count | Should -Be 0
        Should -Invoke Invoke-AZSCDevOpsRestPage -Times 1 -ParameterFilter { $Uri -match '/_apis/projects' }
        Should -Invoke Invoke-AZSCDevOpsRestPage -Times 1 -ParameterFilter { $Uri -match '/_apis/distributedtask/pools' }
    }

    It 'reports rejected DevOps authentication as unavailable instead of claiming the organization is empty' {
        Mock Invoke-AZSCDevOpsRestPage {
            $exception = [System.Exception]::new('The request was rejected.')
            $exception.Data['StatusCode'] = 401
            throw $exception
        }

        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-a' -Organization 'contoso'
        $health = @($result.CollectionHealth)

        @($result.DevOpsResources).Count | Should -Be 0
        $health.Count | Should -Be 5
        @($health.Status | Sort-Object -Unique) | Should -Be @('Unavailable')
        @($health.Collectors) | Should -Contain 'DevOps/DevOpsProjects'
        @($health.Collectors) | Should -Contain 'DevOps/DevOpsAgentPools'
        @($health.Reason) -join ' ' | Should -Match 'HTTP 401'
    }

    It 'marks only the affected DevOps dataset partial when one project endpoint fails' {
        Mock Invoke-AZSCDevOpsRestPage {
            if ($Uri -match '/_apis/projects') {
                return [pscustomobject]@{
                    Headers = @{}
                    Body = [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{ id = 'p1'; name = 'one' },
                            [pscustomobject]@{ id = 'p2'; name = 'two' }
                        )
                    }
                }
            }
            if ($Uri -match '/one/_apis/pipelines') {
                $exception = [System.Exception]::new('Pipeline access denied.')
                $exception.Data['StatusCode'] = 403
                throw $exception
            }
            return [pscustomobject]@{ Headers = @{}; Body = [pscustomobject]@{ value = @() } }
        }

        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-a' -Organization 'contoso'
        $health = @($result.CollectionHealth)

        @($result.DevOpsResources | Where-Object type -eq 'devops/projects').Count | Should -Be 2
        $health.Count | Should -Be 1
        $health[0].Dataset | Should -Be 'Azure DevOps: Pipelines'
        $health[0].Status | Should -Be 'Partial'
        $health[0].Collectors | Should -Be @('DevOps/DevOpsPipelines')
        $health[0].Reason | Should -Match 'HTTP 403'
    }

    It 'threads DevOps collection health into the orchestration result contract' {
        $source = Get-Content -LiteralPath (Join-Path $script:Root 'src/Start-AZTIExtractionOrchestration.ps1') -Raw
        $source | Should -Match "DevOpsData\.PSObject\.Properties\['CollectionHealth'\]"
        $source | Should -Match 'CollectionHealth\.Add\(\$health\)'
    }
}
