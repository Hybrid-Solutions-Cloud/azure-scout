#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5648 — Management/ManagementGroups was the one collector failing on EVERY live run.

    The failure was reported as "Cannot process command because of one or more missing mandatory
    parameters: GroupName" and read for a long time as a permissions problem. It is not: it is a
    parameter-binding failure. `Get-AzManagementGroup -Expand -Recurse` with no `-GroupId`
    selects a parameter set that requires GroupName, so the call fails before it reaches Azure,
    and a binding failure is TERMINATING -- `-ErrorAction SilentlyContinue` cannot suppress it.

    A try/catch was added earlier, which stopped it taking the collector down. It did not make
    the fallback work: it returned nothing every time, so the "Management Groups" sheet was
    empty for any tenant whose root management-group id is not the tenant id.

    These tests drive the collector's Processing branch with stubs and assert on the CALLS it
    makes, because "does not throw" was already true while the collector produced no rows.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:collector = Join-Path $script:root 'Modules/Public/InventoryModules/Management/ManagementGroups.ps1'

    function Invoke-ManagementGroupsCollector {
        <#
            Runs the collector's Processing branch with Get-AzContext / Get-AzManagementGroup
            replaced by the supplied stub text, and returns both the emitted rows and the
            recorded calls. The stubs are injected after param() the same way
            tests/Management.Module.Tests.ps1 does it.
        #>
        param([Parameter(Mandatory)] [string] $Stubs)

        $content = Get-Content -Path $script:collector -Raw

        # FIRST param() only. `-replace` rewrites every match, and the collector defines a
        # second param() inside its recursive Expand-MgHierarchy helper -- injecting there put
        # the call recorder inside a function that runs once per node, so it was reset on every
        # recursion and every assertion about calls silently measured nothing.
        $rx = [regex]::new('param\([^)]*\)')
        $content = $rx.Replace($content, { param($m) "$($m.Value)`n$Stubs`n" }, 1)

        $sb = [ScriptBlock]::Create($content)
        Invoke-Command -ScriptBlock $sb -ArgumentList $null, $null, $null, @(), $null, 'Processing', $null, $null, 'Light20', $null
    }
}

Describe 'AB#5648 — ManagementGroups falls back by enumerating, not by mis-binding' {

    It 'never calls Get-AzManagementGroup with -Expand/-Recurse and no -GroupId' {
        # This is the defect itself. Asserted on the CALL, because the symptom (an empty sheet)
        # is indistinguishable from a tenant that genuinely has no management groups.
        $stubs = @'
$global:MGCalls = [System.Collections.Generic.List[string]]::new()
function Get-AzContext { $null }
function Get-AzManagementGroup {
    param([string]$GroupId, [switch]$Expand, [switch]$Recurse, $ErrorAction)
    $global:MGCalls.Add("GroupId=$GroupId Expand=$($Expand.IsPresent) Recurse=$($Recurse.IsPresent)")
    if (-not $GroupId) {
        return @(
            [PSCustomObject]@{ Name = 'mg-root'; DisplayName = 'Contoso Root'; TenantId = 'ten' }
            [PSCustomObject]@{ Name = 'mg-dept-it'; DisplayName = 'IT Department'; TenantId = 'ten' }
        )
    }
    if ($GroupId -eq 'mg-root') {
        return [PSCustomObject]@{
            Name = 'mg-root'; DisplayName = 'Contoso Root'; TenantId = 'ten'; ParentName = $null
            Children = @(
                [PSCustomObject]@{
                    Name = 'mg-dept-it'; DisplayName = 'IT Department'; TenantId = 'ten'
                    Type = 'Microsoft.Management/managementGroups'
                    ParentName = 'mg-root'; ParentDisplayName = 'Contoso Root'
                    Children = @([PSCustomObject]@{ Name = 'sub-1'; DisplayName = 'Production'; Type = '/subscriptions'; Children = @() })
                }
            )
        }
    }
    return [PSCustomObject]@{
        Name = 'mg-dept-it'; DisplayName = 'IT Department'; TenantId = 'ten'
        ParentName = 'mg-root'; ParentDisplayName = 'Contoso Root'; Children = @()
    }
}
'@
        Invoke-ManagementGroupsCollector -Stubs $stubs | Out-Null

        $bad = @($global:MGCalls | Where-Object { $_ -match 'GroupId= ' -or $_ -match 'GroupId=$' } |
                Where-Object { $_ -match 'Expand=True' })
        $bad -join '; ' | Should -BeNullOrEmpty -Because 'that combination fails parameter binding before Azure is reached'
    }

    It 'enumerates first, then expands each group by id' {
        $stubs = @'
$global:MGCalls = [System.Collections.Generic.List[string]]::new()
function Get-AzContext { $null }
function Get-AzManagementGroup {
    param([string]$GroupId, [switch]$Expand, [switch]$Recurse, $ErrorAction)
    $global:MGCalls.Add("GroupId=$GroupId Expand=$($Expand.IsPresent)")
    if (-not $GroupId) {
        return @([PSCustomObject]@{ Name = 'mg-root'; DisplayName = 'Contoso Root'; TenantId = 'ten' })
    }
    return [PSCustomObject]@{
        Name = 'mg-root'; DisplayName = 'Contoso Root'; TenantId = 'ten'; ParentName = $null; Children = @()
    }
}
'@
        Invoke-ManagementGroupsCollector -Stubs $stubs | Out-Null

        $global:MGCalls[0] | Should -Be 'GroupId= Expand=False' -Because 'the listing call takes no switches'
        $global:MGCalls[1] | Should -Be 'GroupId=mg-root Expand=True'
    }

    It 'produces hierarchy rows from the fallback, where it used to produce none' {
        $stubs = @'
function Get-AzContext { $null }
function Get-AzManagementGroup {
    param([string]$GroupId, [switch]$Expand, [switch]$Recurse, $ErrorAction)
    if (-not $GroupId) {
        return @(
            [PSCustomObject]@{ Name = 'mg-root'; DisplayName = 'Contoso Root'; TenantId = 'ten' }
            [PSCustomObject]@{ Name = 'mg-dept-it'; DisplayName = 'IT Department'; TenantId = 'ten' }
        )
    }
    if ($GroupId -eq 'mg-root') {
        return [PSCustomObject]@{
            Name = 'mg-root'; DisplayName = 'Contoso Root'; TenantId = 'ten'; ParentName = $null
            Children = @(
                [PSCustomObject]@{
                    Name = 'mg-dept-it'; DisplayName = 'IT Department'; TenantId = 'ten'
                    Type = 'Microsoft.Management/managementGroups'
                    ParentName = 'mg-root'; ParentDisplayName = 'Contoso Root'
                    Children = @([PSCustomObject]@{ Name = 'sub-1'; DisplayName = 'Production'; Type = '/subscriptions'; Children = @() })
                }
            )
        }
    }
    return [PSCustomObject]@{
        Name = 'mg-dept-it'; DisplayName = 'IT Department'; TenantId = 'ten'
        ParentName = 'mg-root'; ParentDisplayName = 'Contoso Root'
        Type = 'Microsoft.Management/managementGroups'
        Children = @([PSCustomObject]@{ Name = 'sub-1'; DisplayName = 'Production'; Type = '/subscriptions'; Children = @() })
    }
}
'@
        $rows = @(Invoke-ManagementGroupsCollector -Stubs $stubs)

        # Root + its one child MG. mg-dept-it is expanded too (it is in the listing), but it is
        # NOT a root -- emitting it separately would render the same subtree twice.
        $rows.Count | Should -Be 2
        @($rows | Where-Object { $_.'Management Group ID' -eq 'mg-root' }).Count | Should -Be 1
        @($rows | Where-Object { $_.'Management Group ID' -eq 'mg-dept-it' }).Count | Should -Be 1

        $root = $rows | Where-Object { $_.'Management Group ID' -eq 'mg-root' }
        $root.'Parent Management Group' | Should -Be 'Tenant Root'
        $root.'Direct Child MGs' | Should -Be 1

        $child = $rows | Where-Object { $_.'Management Group ID' -eq 'mg-dept-it' }
        $child.'Hierarchy Depth' | Should -Be 1
        $child.'Direct Subscriptions' | Should -Be 1
        $child.'Direct Subscription Names' | Should -Be 'Production'
    }

    It 'still prefers the single tenant-root call when it succeeds' {
        # The fallback is a fallback: a tenant whose root-MG id IS the tenant id must still cost
        # exactly one call, not one-per-group.
        $stubs = @'
$global:MGCalls = [System.Collections.Generic.List[string]]::new()
function Get-AzContext { [PSCustomObject]@{ Tenant = [PSCustomObject]@{ Id = 'ten' } } }
function Get-AzManagementGroup {
    param([string]$GroupId, [switch]$Expand, [switch]$Recurse, $ErrorAction)
    $global:MGCalls.Add("GroupId=$GroupId")
    return [PSCustomObject]@{ Name = 'ten'; DisplayName = 'Tenant Root'; TenantId = 'ten'; ParentName = $null; Children = @() }
}
'@
        $rows = @(Invoke-ManagementGroupsCollector -Stubs $stubs)
        $global:MGCalls.Count | Should -Be 1
        $global:MGCalls[0] | Should -Be 'GroupId=ten'
        $rows.Count | Should -Be 1
    }

    It 'returns no rows, and does not throw, when the caller can see no management groups' {
        $stubs = @'
function Get-AzContext { $null }
function Get-AzManagementGroup { param([string]$GroupId, [switch]$Expand, [switch]$Recurse, $ErrorAction) $null }
'@
        { Invoke-ManagementGroupsCollector -Stubs $stubs } | Should -Not -Throw
        # Assigned OUTSIDE the Should scriptblock: a scriptblock passed to Should runs in its
        # own scope, so an assignment inside it leaves $rows $null out here -- and @($null).Count
        # is 1, not 0, so the assertion would have been measuring nothing.
        $rows = @(Invoke-ManagementGroupsCollector -Stubs $stubs)
        $rows.Count | Should -Be 0
    }

    It 'survives a listing call that throws outright' {
        $stubs = @'
function Get-AzContext { $null }
function Get-AzManagementGroup { param([string]$GroupId, [switch]$Expand, [switch]$Recurse, $ErrorAction) throw 'AuthorizationFailed' }
'@
        { Invoke-ManagementGroupsCollector -Stubs $stubs } | Should -Not -Throw
    }
}

AfterAll {
    Remove-Variable -Name MGCalls -Scope Global -ErrorAction SilentlyContinue
}
