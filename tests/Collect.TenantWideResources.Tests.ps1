#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/collect/ConvertTo-ScoutManagementGroupHierarchy.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/collect/Get-ScoutTenantWideResource.ps1')

    function Get-TestEnvelope {
        param(
            [Parameter(Mandatory)] [object[]]$Resources,
            [Parameter(Mandatory)] [string]$Type
        )
        @($Resources | Where-Object type -eq $Type)[0]
    }

    function Get-TestManagementGroupTree {
        $Subscription = [PSCustomObject]@{
            Type        = '/subscriptions'
            Name        = 'sub-1'
            DisplayName = 'Production'
        }
        $Child = [PSCustomObject]@{
            Type              = '/providers/Microsoft.Management/managementGroups'
            Name              = 'platform'
            DisplayName       = 'Platform'
            ParentName        = 'root'
            ParentDisplayName = 'Tenant Root'
            TenantId          = 'tenant-1'
            Children          = @()
        }
        [PSCustomObject]@{
            Type        = '/providers/Microsoft.Management/managementGroups'
            Name        = 'root'
            DisplayName = 'Tenant Root'
            TenantId    = 'tenant-1'
            Children    = @($Child, $Subscription)
        }
    }
}

Describe 'ConvertTo-ScoutManagementGroupHierarchy' {
    It 'flattens the tree in deterministic pre-order with depth, path, and direct-child counts' {
        $Rows = @(ConvertTo-ScoutManagementGroupHierarchy -Root (Get-TestManagementGroupTree))

        @($Rows).Count | Should -Be 2
        @($Rows.'Management Group ID') | Should -Be @('root', 'platform')
        $Rows[0].'Full Path' | Should -Be 'Tenant Root'
        $Rows[0].'Hierarchy Depth' | Should -Be 0
        $Rows[0].'Parent Management Group' | Should -Be 'Tenant Root'
        $Rows[0].'Direct Child MGs' | Should -Be 1
        $Rows[0].'Direct Subscriptions' | Should -Be 1
        $Rows[0].'Direct Subscription Names' | Should -Be 'Production'
        $Rows[1].'Display Name' | Should -Be '    Platform'
        $Rows[1].'Full Path' | Should -Be 'Tenant Root / Platform'
        $Rows[1].'Hierarchy Depth' | Should -Be 1
        $Rows[1].'Parent Management Group' | Should -Be 'Tenant Root'
    }

    It 'accepts missing Children as an empty child collection under StrictMode' {
        $RootWithoutChildren = [PSCustomObject]@{
            Name        = 'root'
            DisplayName = 'Root'
            TenantId    = 'tenant-1'
        }
        $Rows = @(ConvertTo-ScoutManagementGroupHierarchy -Root $RootWithoutChildren)

        @($Rows).Count | Should -Be 1
        $Rows[0].'Direct Child MGs' | Should -Be 0
        $Rows[0].'Direct Subscriptions' | Should -Be 0
    }
}

Describe 'Get-ScoutTenantWideResource - integration contract' {
    BeforeEach {
        Mock Get-AzRoleDefinition {
            @(
                [PSCustomObject]@{ Id = 'role-1'; Name = 'Custom Operator'; IsCustom = $true }
            )
        }
        Mock Get-AzContext {
            [PSCustomObject]@{
                Tenant = [PSCustomObject]@{ Id = 'tenant-1' }
            }
        }
        Mock Get-AzManagementGroup { @() }
        Mock Get-AzManagementGroup {
                Get-TestManagementGroupTree
        } -ParameterFilter { $GroupId -eq 'tenant-1' -and $Expand -and $Recurse }
    }

    It 'returns exactly four typed envelopes in stable order' {
        $Resources = @(Get-ScoutTenantWideResource -ApiResources @())

        @($Resources.type) | Should -Be @(
            'AZSC/Management/RoleDefinition'
            'AZSC/Management/ManagementGroup'
            'AZSC/Management/PolicyDefinition'
            'AZSC/Management/PolicySetDefinition'
        )
        foreach ($Resource in $Resources) {
            $Resource.PSObject.Properties.Name | Should -Contain 'properties'
            $Resource.properties.GetType() | Should -Be ([object[]])
        }
    }

    It 'surfaces already-collected policy payloads without making another policy call' {
        $Policy1 = [PSCustomObject]@{ id = 'policy-1'; name = 'one' }
        $Policy2 = [PSCustomObject]@{ id = 'policy-2'; name = 'two' }
        $Set1 = [PSCustomObject]@{ id = 'set-1'; name = 'initiative' }
        $ApiResources = @(
            [PSCustomObject]@{
                PolicyDefinitions    = @($Policy1)
                PolicySetDefinitions = @($Set1)
            }
            [PSCustomObject]@{
                PolicyDefinitions    = @($Policy2)
                PolicySetDefinitions = $null
            }
        )

        $Resources = @(Get-ScoutTenantWideResource -ApiResources $ApiResources)
        $Policies = Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/PolicyDefinition'
        $PolicySets = Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/PolicySetDefinition'

        @($Policies.properties.id) | Should -Be @('policy-1', 'policy-2')
        @($PolicySets.properties.id) | Should -Be @('set-1')

        $Source = Get-Content -LiteralPath (
            Join-Path -Path $script:RepoRoot -ChildPath 'src/collect/Get-ScoutTenantWideResource.ps1'
        ) -Raw
        $Source | Should -Not -Match 'Get-AzPolicyDefinition|Get-AzPolicySetDefinition'
    }

    It 'queries custom roles once and preserves the returned objects' {
        $Resources = @(Get-ScoutTenantWideResource -ApiResources @())
        $Roles = Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/RoleDefinition'

        @($Roles.properties).Count | Should -Be 1
        $Roles.properties[0].Name | Should -Be 'Custom Operator'
        Should -Invoke Get-AzRoleDefinition -Times 1 -Exactly -ParameterFilter {
            $Custom -and $ErrorAction -eq 'Stop'
        }
    }

    It 'uses one tenant-root recursive expansion when it succeeds' {
        $Resources = @(Get-ScoutTenantWideResource -ApiResources @())
        $Groups = Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/ManagementGroup'

        @($Groups.properties).Count | Should -Be 2
        Should -Invoke Get-AzManagementGroup -Times 1 -Exactly -ParameterFilter {
            $GroupId -eq 'tenant-1' -and $Expand -and $Recurse
        }
        Should -Invoke Get-AzManagementGroup -Times 0 -Exactly -ParameterFilter {
            [string]::IsNullOrWhiteSpace([string]$GroupId)
        }
    }
}

Describe 'Get-ScoutTenantWideResource - management-group fallback' {
    BeforeEach {
        Mock Get-AzRoleDefinition { @() }
        Mock Get-AzContext {
            [PSCustomObject]@{ Tenant = [PSCustomObject]@{ Id = 'tenant-1' } }
        }
        Mock Get-AzManagementGroup {
            @(
                [PSCustomObject]@{ Name = 'root' }
                [PSCustomObject]@{ Name = 'child' }
            )
        } -ParameterFilter { [string]::IsNullOrWhiteSpace([string]$GroupId) }
        Mock Get-AzManagementGroup {
            Get-TestManagementGroupTree
        } -ParameterFilter { $GroupId -eq 'root' }
        Mock Get-AzManagementGroup {
            [PSCustomObject]@{
                Name              = 'child'
                DisplayName       = 'Child'
                ParentName        = 'root'
                ParentDisplayName = 'Tenant Root'
                TenantId          = 'tenant-1'
                Children          = @()
            }
        } -ParameterFilter { $GroupId -eq 'child' }
        Mock Get-AzManagementGroup {
            throw 'tenant root is not readable'
        } -ParameterFilter { $GroupId -eq 'tenant-1' }
    }

    It 'enumerates, expands every visible group by id, and keeps roots so subtrees are not duplicated' {
        $Resources = @(Get-ScoutTenantWideResource -ApiResources @())
        $Groups = Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/ManagementGroup'

        @($Groups.properties.'Management Group ID') | Should -Be @('root', 'platform')
        Should -Invoke Get-AzManagementGroup -Times 1 -Exactly -ParameterFilter {
            [string]::IsNullOrWhiteSpace([string]$GroupId)
        }
        Should -Invoke Get-AzManagementGroup -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'root' }
        Should -Invoke Get-AzManagementGroup -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'child' }
    }
}

Describe 'Get-ScoutTenantWideResource - permission degradation' {
    BeforeEach {
        Mock Get-AzContext {
            [PSCustomObject]@{ Tenant = [PSCustomObject]@{ Id = 'tenant-1' } }
        }
        Mock Get-AzRoleDefinition { throw 'role read forbidden' }
        Mock Get-AzManagementGroup { throw 'management group read forbidden' }
    }

    It 'returns empty affected envelopes with warnings and preserves policy output' {
        $ApiResources = @(
            [PSCustomObject]@{
                PolicyDefinitions    = @([PSCustomObject]@{ id = 'policy-1' })
                PolicySetDefinitions = @()
            }
        )
        $Warnings = @()
        $Resources = @(
            Get-ScoutTenantWideResource -ApiResources $ApiResources -WarningVariable +Warnings
        )

        @((Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/RoleDefinition').properties).Count |
            Should -Be 0
        @((Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/ManagementGroup').properties).Count |
            Should -Be 0
        @((Get-TestEnvelope -Resources $Resources -Type 'AZSC/Management/PolicyDefinition').properties).Count |
            Should -Be 1
        @($Warnings).Count | Should -Be 2
        ($Warnings -join ' ') | Should -Match 'custom role definitions could not be read'
        ($Warnings -join ' ') | Should -Match 'management groups could not be read'
    }

    It 'records exact tenant-wide coverage gaps without changing the four-envelope contract' {
        $health = [System.Collections.Generic.List[object]]::new()

        $resources = @(Get-ScoutTenantWideResource -ApiResources @() -CollectionHealth $health `
                -WarningAction SilentlyContinue)

        $resources.Count | Should -Be 4
        @($health).Count | Should -Be 2
        @($health.SourceDataset) | Should -Contain 'CustomRoleDefinitions'
        @($health.SourceDataset) | Should -Contain 'ManagementGroups'
        ($health | Where-Object SourceDataset -eq 'ManagementGroups').Reason | Should -Match 'Management Group Reader'
    }
}
