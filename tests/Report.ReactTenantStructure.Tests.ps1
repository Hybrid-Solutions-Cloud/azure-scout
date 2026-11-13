#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Field scan 2026-10-05, inventory-only React report for a tenant with thirteen management
    groups and nine subscriptions:

      - the Tenant field showed the name of the first subscription;
      - "Management groups" showed 0, the Tenant structure page was empty and the
        management-group diagram said none were collected;
      - portal deep links were built without a tenant id.

    governance.managementGroups is filled only by the Governance ingestor (assessment runs).
    The Management/ManagementGroups collector had the full hierarchy the whole time. These
    tests defend the report building the hierarchy from the collected rows when the ingestor
    did not run, and naming the tenant from the Entra organization record.

    No Azure connection required.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/report/renderers/Export-React.ps1"

    function New-CollectedManagementGroupRow {
        param([string] $Id, [string] $Name, [string] $Path, [int] $Depth)
        # 'Parent Management Group' is deliberately the wrong constant the collector emits at
        # every depth; the report must not depend on it.
        [pscustomobject]@{
            'Management Group ID' = $Id; 'Display Name (Raw)' = $Name; 'Display Name' = (' ' * (4 * $Depth)) + $Name
            'Full Path' = $Path; 'Hierarchy Depth' = $Depth; 'Parent Management Group' = 'Tenant Root'
        }
    }

    function Get-ReactPayload {
        param($Collect, [string] $Name)
        $out = Join-Path $TestDrive $Name
        $null = Export-React -Findings (Get-Score -Findings @()) -Collect $Collect -OutputPath $out
        $html = Get-Content -Raw (Join-Path $out 'report-react.html')
        $start = $html.IndexOf('window.__SCOUT_DATA__ = ') + 'window.__SCOUT_DATA__ = '.Length
        $end = $html.IndexOf('</script>', $start)
        $html.Substring($start, $end - $start).Trim().TrimEnd(';') | ConvertFrom-Json -Depth 100 -AsHashtable
    }

    $script:TenantId = '22222222-2222-2222-2222-222222222222'
    $script:CollectedRows = @(
        New-CollectedManagementGroupRow -Id $script:TenantId -Name 'Tenant Root Group' -Path 'Tenant Root Group' -Depth 0
        New-CollectedManagementGroupRow -Id 'mg-platform' -Name 'Platform' -Path 'Tenant Root Group / Platform' -Depth 1
        New-CollectedManagementGroupRow -Id 'mg-identity' -Name 'Identity' -Path 'Tenant Root Group / Platform / Identity' -Depth 2
        New-CollectedManagementGroupRow -Id 'mg-landingzones' -Name 'Landing Zones' -Path 'Tenant Root Group / Landing Zones' -Depth 1
    )

    function New-InventoryOnlyCollect {
        param([object[]] $EntraResources = @(), [object[]] $GovernanceManagementGroups = @())
        [pscustomobject]@{
            _meta = [pscustomobject]@{ scope = 'All' }
            subscriptions = @([pscustomobject]@{ id = 'sub-1'; name = 'sub-first-in-the-list'; state = 'Enabled' })
            entraResources = $EntraResources
            governance = [pscustomobject]@{ managementGroups = $GovernanceManagementGroups; policyAssignments = @() }
            _reportInventory = [ordered]@{
                'collected.management.ManagementGroups' = [ordered]@{
                    label = 'Management → Management Groups (collected details)'; count = $script:CollectedRows.Count
                    countUnit = 'evidence rows'; resourceCount = $null; rows = $script:CollectedRows; truncated = $null
                    source = 'Management.json/ManagementGroups'
                }
            }
        }
    }
}

Describe 'React report — management groups in an inventory-only run' {
    BeforeAll {
        $script:Payload = Get-ReactPayload -Name 'mg-inventory' -Collect (New-InventoryOnlyCollect -EntraResources @(
            [pscustomobject]@{ id = $script:TenantId; name = 'Contoso Ltd'; TYPE = 'entra/organization'; tenantId = $script:TenantId }
        ))
        $script:Rows = @($script:Payload.inventory['governance.managementGroups'].rows)
    }

    It 'shows every collected management group' {
        $script:Payload.inventory['governance.managementGroups'].count | Should -Be 4
        @($script:Rows | ForEach-Object { $_.name }) | Should -Be @($script:TenantId, 'mg-platform', 'mg-identity', 'mg-landingzones')
    }

    It 'links each group to its real parent at every depth' {
        ($script:Rows | Where-Object name -eq $script:TenantId).parent | Should -Be ''
        ($script:Rows | Where-Object name -eq 'mg-platform').parent | Should -Be $script:TenantId
        ($script:Rows | Where-Object name -eq 'mg-identity').parent | Should -Be 'mg-platform'
        ($script:Rows | Where-Object name -eq 'mg-landingzones').parent | Should -Be $script:TenantId
    }

    It 'uses the un-indented display name' {
        ($script:Rows | Where-Object name -eq 'mg-identity').displayName | Should -Be 'Identity'
    }

    It 'names the tenant from the Entra organization record, never from a subscription' {
        $script:Payload.meta.tenantDisplayName | Should -Be 'Contoso Ltd'
    }

    It 'emits the tenant id the template needs for portal links' {
        $script:Payload.meta.tenantId | Should -Be $script:TenantId
    }
}

Describe 'React report — tenant name fallbacks' {
    It 'falls back to the tenant id when the root management group still has the default name and Entra was not collected' {
        $payload = Get-ReactPayload -Name 'mg-no-entra' -Collect (New-InventoryOnlyCollect)
        $payload.meta.tenantDisplayName | Should -Be $script:TenantId
        $payload.meta.tenantDisplayName | Should -Not -Be 'sub-first-in-the-list'
    }

    It 'keeps the Governance ingestor rows untouched when an assessment run supplied them' {
        $ingested = @(
            [pscustomobject]@{ name = 'root'; id = '/providers/Microsoft.Management/managementGroups/root'; displayName = 'Fabrikam'; parent = '' }
            [pscustomobject]@{ name = 'child'; id = '/providers/Microsoft.Management/managementGroups/child'; displayName = 'Child'; parent = 'root' }
        )
        $payload = Get-ReactPayload -Name 'mg-ingested' -Collect (New-InventoryOnlyCollect -GovernanceManagementGroups $ingested)
        $payload.inventory['governance.managementGroups'].count | Should -Be 2
        $payload.meta.tenantDisplayName | Should -Be 'Fabrikam'
    }
}
