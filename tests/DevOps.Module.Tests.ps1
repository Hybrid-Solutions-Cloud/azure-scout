#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Azure DevOps extraction and its five collector modules.

.DESCRIPTION
    Covers AB#327. The extraction is exercised against a mocked Azure DevOps REST API;
    the collector modules are exercised in both the Processing and Reporting phases.
    No live Azure or Azure DevOps authentication is required.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
#>

BeforeAll {
    $script:ModuleRoot     = Split-Path -Parent $PSScriptRoot
    $script:ExtractionPath = Join-Path $script:ModuleRoot 'Modules' 'Private' 'Extraction'
    $script:ModulePath     = Join-Path $script:ModuleRoot 'Modules' 'Public' 'InventoryModules' 'Management'

    . (Join-Path $script:ExtractionPath 'Start-AZTIDevOpsExtraction.ps1')

    # Pseudo-resources in the shape Start-AZSCDevOpsExtraction produces, for the
    # collector-module tests.
    $script:DevOpsResources = @(
        [PSCustomObject]@{
            id = 'contoso/proj-1'; name = 'Payments'; type = 'devops/projects'
            tenantId = 'tenant-1'; organization = 'contoso'
            properties = [PSCustomObject]@{
                id = 'proj-1'; description = 'Payments platform'; state = 'wellFormed'
                visibility = 'private'; revision = 42; lastUpdateTime = '2026-07-01T10:00:00Z'
                url = 'https://dev.azure.com/contoso/_apis/projects/proj-1'
            }
        }
        [PSCustomObject]@{
            id = 'contoso/1'; name = 'payments-ci'; type = 'devops/pipelines'
            tenantId = 'tenant-1'; organization = 'contoso'
            properties = [PSCustomObject]@{
                id = 1; revision = 3; projectName = 'Payments'; folder = '\'
                url = 'https://dev.azure.com/contoso/_apis/pipelines/1'
                configuration = [PSCustomObject]@{ type = 'yaml'; path = '/azure-pipelines.yml' }
            }
        }
        [PSCustomObject]@{
            id = 'contoso/ep-1'; name = 'prod-arm'; type = 'devops/serviceconnections'
            tenantId = 'tenant-1'; organization = 'contoso'
            properties = [PSCustomObject]@{
                type = 'azurerm'; projectName = 'Payments'; isShared = $false; isReady = $true
                data = [PSCustomObject]@{ subscriptionId = 'sub-in-scope'; subscriptionName = 'Production' }
                authorization = [PSCustomObject]@{
                    scheme = 'WorkloadIdentityFederation'
                    parameters = [PSCustomObject]@{ serviceprincipalid = 'spn-guid' }
                }
            }
        }
        [PSCustomObject]@{
            id = 'contoso/ep-2'; name = 'legacy-arm'; type = 'devops/serviceconnections'
            tenantId = 'tenant-1'; organization = 'contoso'
            properties = [PSCustomObject]@{
                type = 'azurerm'; projectName = 'Payments'; isShared = $false; isReady = $true
                data = [PSCustomObject]@{ subscriptionId = 'sub-elsewhere'; subscriptionName = 'Other' }
                authorization = [PSCustomObject]@{
                    scheme = 'ServicePrincipal'
                    parameters = [PSCustomObject]@{ serviceprincipalid = 'spn-old' }
                }
            }
        }
        [PSCustomObject]@{
            id = 'contoso/repo-1'; name = 'payments-api'; type = 'devops/repositories'
            tenantId = 'tenant-1'; organization = 'contoso'
            properties = [PSCustomObject]@{
                projectName = 'Payments'; defaultBranch = 'refs/heads/main'
                size = 5242880; isDisabled = $false
                webUrl = 'https://dev.azure.com/contoso/Payments/_git/payments-api'
            }
        }
        [PSCustomObject]@{
            id = 'contoso/pool-1'; name = 'Azure Pipelines'; type = 'devops/agentpools'
            tenantId = 'tenant-1'; organization = 'contoso'
            properties = [PSCustomObject]@{
                id = 1; isHosted = $true; poolType = 'automation'; size = 10
                autoProvision = $true; isLegacy = $false; createdOn = '2025-01-01T00:00:00Z'
                owner = [PSCustomObject]@{ displayName = 'Project Collection Admins' }
            }
        }
        [PSCustomObject]@{
            id = 'contoso/pool-2'; name = 'onprem-linux'; type = 'devops/agentpools'
            tenantId = 'tenant-1'; organization = 'contoso'
            properties = [PSCustomObject]@{
                id = 2; isHosted = $false; poolType = 'automation'; size = 4
                autoProvision = $false; isLegacy = $false; createdOn = '2025-06-01T00:00:00Z'
                owner = [PSCustomObject]@{ displayName = 'Platform Team' }
            }
        }
    )

    $script:Subs = @(
        [PSCustomObject]@{ Id = 'sub-in-scope'; Name = 'Production' }
    )

    function Invoke-CollectorProcessing {
        param([string]$ModuleFile)
        $path = Join-Path $script:ModulePath $ModuleFile
        return & $path $null $script:Subs $false $script:DevOpsResources @() 'Processing' $null $null $null $null
    }
}

Describe 'Start-AZSCDevOpsExtraction — authentication (AB#327)' {

    It 'Uses basic auth when a PAT is supplied and does not request an Azure token' {
        Mock Get-AzAccessToken { throw 'should not be called' }
        Mock Invoke-RestMethod { [PSCustomObject]@{ value = @() } }

        $null = Start-AZSCDevOpsExtraction -TenantID 't' -Organization @('contoso') -Pat 'fake-pat'

        Should -Invoke Get-AzAccessToken -Times 0 -Exactly
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Headers.Authorization -like 'Basic *' }
    }

    It 'Falls back to an Entra token for the Azure DevOps resource when no PAT is given' {
        Mock Get-AzAccessToken { [PSCustomObject]@{ Token = 'entra-token' } }
        Mock Invoke-RestMethod { [PSCustomObject]@{ value = @() } }

        $null = Start-AZSCDevOpsExtraction -TenantID 't' -Organization @('contoso')

        Should -Invoke Get-AzAccessToken -Times 1 -Exactly -ParameterFilter {
            $ResourceUrl -eq '499b84ac-1321-427f-aa17-267ca6975798'
        }
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Headers.Authorization -eq 'Bearer entra-token' }
    }

    It 'Unwraps a SecureString token from newer Az versions' {
        Mock Get-AzAccessToken {
            [PSCustomObject]@{ Token = (ConvertTo-SecureString 'secure-token' -AsPlainText -Force) }
        }
        Mock Invoke-RestMethod { [PSCustomObject]@{ value = @() } }

        $null = Start-AZSCDevOpsExtraction -TenantID 't' -Organization @('contoso')

        Should -Invoke Invoke-RestMethod -ParameterFilter { $Headers.Authorization -eq 'Bearer secure-token' }
    }

    It 'Returns empty and does not throw when no token can be acquired' {
        Mock Get-AzAccessToken { throw 'no context' }
        Mock Write-Warning { }

        $result = Start-AZSCDevOpsExtraction -TenantID 't' -Organization @('contoso')

        @($result.DevOpsResources).Count | Should -Be 0
    }
}

Describe 'Start-AZSCDevOpsExtraction — collection (AB#327)' {

    BeforeEach {
        Mock Get-AzAccessToken { [PSCustomObject]@{ Token = 'entra-token' } }
        Mock Invoke-RestMethod {
            if ($Uri -match '/_apis/projects')              { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'p1'; name = 'Payments'; state = 'wellFormed' }) } }
            if ($Uri -match '/_apis/pipelines')             { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 1; name = 'ci' }) } }
            if ($Uri -match '/serviceendpoint/endpoints')   { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'e1'; name = 'arm' }) } }
            if ($Uri -match '/git/repositories')            { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'r1'; name = 'api' }) } }
            if ($Uri -match '/distributedtask/pools')       { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 1; name = 'pool' }) } }
            return [PSCustomObject]@{ value = @() }
        }
    }

    It 'Produces one normalized resource per item across all five types' {
        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso')
        @($result.DevOpsResources).Count | Should -Be 5
    }

    It 'Stamps the synthetic type onto every resource' {
        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso')
        $types = @($result.DevOpsResources.type) | Sort-Object
        $types -join ',' | Should -Be 'devops/agentpools,devops/pipelines,devops/projects,devops/repositories,devops/serviceconnections'
    }

    It 'Prefixes each resource id with the organization so two orgs cannot collide' {
        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso')
        foreach ($r in $result.DevOpsResources) { $r.id | Should -BeLike 'contoso/*' }
    }

    It 'Stamps the tenant ID onto every resource' {
        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso')
        foreach ($r in $result.DevOpsResources) { $r.tenantId | Should -Be 'tenant-1' }
    }

    It 'Scans every organization it is given' {
        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso', 'fabrikam')
        @($result.DevOpsResources).Count | Should -Be 10
        @($result.DevOpsResources | Where-Object { $_.organization -eq 'fabrikam' }).Count | Should -Be 5
    }

    It 'Discovers organizations from the signed-in profile when none are supplied' {
        Mock Invoke-RestMethod {
            if ($Uri -match '/profile/profiles/me') { return [PSCustomObject]@{ id = 'member-1' } }
            if ($Uri -match '/_apis/accounts')      { return [PSCustomObject]@{ value = @([PSCustomObject]@{ accountName = 'discovered-org' }) } }
            if ($Uri -match '/_apis/projects')      { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'p1'; name = 'P' }) } }
            return [PSCustomObject]@{ value = @() }
        }

        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1'

        @($result.DevOpsResources | Where-Object { $_.organization -eq 'discovered-org' }).Count | Should -BeGreaterThan 0
    }

    It 'Warns and returns empty when discovery finds no organizations' {
        Mock Invoke-RestMethod { [PSCustomObject]@{ } }
        Mock Write-Warning { }

        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1'

        @($result.DevOpsResources).Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1 -Exactly
    }

    It 'Keeps collecting other data when one endpoint returns 403' {
        Mock Invoke-RestMethod {
            if ($Uri -match '/serviceendpoint/endpoints') { throw 'Access denied' }
            if ($Uri -match '/_apis/projects')            { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'p1'; name = 'P' }) } }
            if ($Uri -match '/_apis/pipelines')           { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 1; name = 'ci' }) } }
            return [PSCustomObject]@{ value = @() }
        }

        $result = Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso')

        @($result.DevOpsResources | Where-Object { $_.type -eq 'devops/serviceconnections' }).Count | Should -Be 0
        @($result.DevOpsResources | Where-Object { $_.type -eq 'devops/pipelines' }).Count | Should -Be 1
    }

    It 'Skips an organization with no project access without throwing' {
        Mock Invoke-RestMethod { throw 'Access denied' }
        { Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso') } | Should -Not -Throw
    }

    It 'Issues only GET requests — Azure Scout is read-only' {
        $null = Start-AZSCDevOpsExtraction -TenantID 'tenant-1' -Organization @('contoso')
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -ne 'Get' } -Times 0 -Exactly
    }
}

Describe 'DevOpsProjects collector (AB#327)' {

    It 'Emits one row per project' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsProjects.ps1')
        $rows.Count | Should -Be 1
    }

    It 'Maps the project fields' {
        $row = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsProjects.ps1')[0]
        $row.'Organization' | Should -Be 'contoso'
        $row.'Project Name' | Should -Be 'Payments'
        $row.'State'        | Should -Be 'wellFormed'
        $row.'Visibility'   | Should -Be 'private'
    }

    It 'Formats the last update timestamp' {
        $row = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsProjects.ps1')[0]
        $row.'Last Updated' | Should -Match '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$'
    }
}

Describe 'DevOpsPipelines collector (AB#327)' {

    It 'Emits one row per pipeline' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsPipelines.ps1')
        $rows.Count | Should -Be 1
    }

    It 'Reports a root-folder pipeline as (root) rather than a bare backslash' {
        $row = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsPipelines.ps1')[0]
        $row.'Folder' | Should -Be '(root)'
    }

    It 'Flattens the YAML configuration' {
        $row = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsPipelines.ps1')[0]
        $row.'Configuration Type' | Should -Be 'yaml'
        $row.'YAML Path'          | Should -Be '/azure-pipelines.yml'
    }

    It 'Carries the owning project name' {
        $row = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsPipelines.ps1')[0]
        $row.'Project' | Should -Be 'Payments'
    }
}

Describe 'DevOpsServiceConnections collector (AB#327)' {

    It 'Emits one row per service connection' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsServiceConnections.ps1')
        $rows.Count | Should -Be 2
    }

    It 'Marks a connection targeting an in-scope subscription' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsServiceConnections.ps1')
        $inScope = $rows | Where-Object { $_.'Connection Name' -eq 'prod-arm' }
        $inScope.'Subscription In Scope' | Should -Be 'Yes'
    }

    It 'Marks a connection targeting a subscription outside the scan' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsServiceConnections.ps1')
        $outOfScope = $rows | Where-Object { $_.'Connection Name' -eq 'legacy-arm' }
        $outOfScope.'Subscription In Scope' | Should -Be 'No'
    }

    It 'Flags workload identity federation as credential free' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsServiceConnections.ps1')
        $federated = $rows | Where-Object { $_.'Connection Name' -eq 'prod-arm' }
        $federated.'Credential Free' | Should -Be 'Yes'
    }

    It 'Flags a service principal connection as not credential free' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsServiceConnections.ps1')
        $spn = $rows | Where-Object { $_.'Connection Name' -eq 'legacy-arm' }
        $spn.'Credential Free' | Should -Be 'No'
    }

    It 'Surfaces the service principal ID for an ARM connection' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsServiceConnections.ps1')
        $spn = $rows | Where-Object { $_.'Connection Name' -eq 'legacy-arm' }
        $spn.'Service Principal ID' | Should -Be 'spn-old'
    }
}

Describe 'DevOpsRepositories collector (AB#327)' {

    It 'Emits one row per repository' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsRepositories.ps1')
        $rows.Count | Should -Be 1
    }

    It 'Shortens the default branch ref' {
        $row = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsRepositories.ps1')[0]
        $row.'Default Branch' | Should -Be 'main'
    }

    It 'Converts the repository size to megabytes' {
        $row = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsRepositories.ps1')[0]
        $row.'Size (MB)' | Should -Be 5
    }
}

Describe 'DevOpsAgentPools collector (AB#327)' {

    It 'Emits one row per agent pool' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsAgentPools.ps1')
        $rows.Count | Should -Be 2
    }

    It 'Labels a Microsoft-hosted pool' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsAgentPools.ps1')
        $hosted = $rows | Where-Object { $_.'Pool Name' -eq 'Azure Pipelines' }
        $hosted.'Hosting Model' | Should -Be 'Microsoft-hosted'
    }

    It 'Labels a self-hosted pool — the set carrying patching and capacity obligations' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsAgentPools.ps1')
        $selfHosted = $rows | Where-Object { $_.'Pool Name' -eq 'onprem-linux' }
        $selfHosted.'Hosting Model' | Should -Be 'Self-hosted'
    }

    It 'Surfaces the pool owner' {
        $rows = @(Invoke-CollectorProcessing -ModuleFile 'DevOpsAgentPools.ps1')
        $selfHosted = $rows | Where-Object { $_.'Pool Name' -eq 'onprem-linux' }
        $selfHosted.'Owner' | Should -Be 'Platform Team'
    }
}

Describe 'DevOps collectors — no matching resources' {

    It 'Every collector returns nothing when the resource array holds no DevOps data' {
        foreach ($file in 'DevOpsProjects.ps1', 'DevOpsPipelines.ps1', 'DevOpsServiceConnections.ps1', 'DevOpsRepositories.ps1', 'DevOpsAgentPools.ps1') {
            $path = Join-Path $script:ModulePath $file
            $rows = @(& $path $null $script:Subs $false @() @() 'Processing' $null $null $null $null)
            $rows.Count | Should -Be 0 -Because "$file should emit nothing for an empty resource set"
        }
    }

    It 'Every collector survives a resource array holding only unrelated types' {
        $unrelated = @([PSCustomObject]@{ id = 'x'; name = 'vm'; type = 'microsoft.compute/virtualmachines'; properties = [PSCustomObject]@{} })
        foreach ($file in 'DevOpsProjects.ps1', 'DevOpsPipelines.ps1', 'DevOpsServiceConnections.ps1', 'DevOpsRepositories.ps1', 'DevOpsAgentPools.ps1') {
            $path = Join-Path $script:ModulePath $file
            { & $path $null $script:Subs $false $unrelated @() 'Processing' $null $null $null $null } | Should -Not -Throw
        }
    }
}
