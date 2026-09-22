#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Collect tenant-wide policy, custom-role, and management-group synthetic resources.

.DESCRIPTION
    Produces the four typed resource envelopes that declarative collectors will consume after
    integration. Policy definitions are surfaced from Get-ScoutApiResources output already
    collected earlier in the collect phase. Custom roles are queried once for the tenant.
    Management groups are expanded once from the tenant root when possible, with the established
    enumerate-then-expand fallback for renamed or unreadable tenant roots.

    Every envelope is returned even when its properties array is empty. This makes the integration
    contract stable while allowing missing tenant-wide read permissions to degrade only the
    affected worksheet.

.PARAMETER ApiResources
    Per-subscription output from Get-ScoutApiResources. PolicyDefinitions and
    PolicySetDefinitions are flattened into their corresponding typed envelopes.

.OUTPUTS
    Exactly four PSCustomObjects, in stable type order. Each has `type` and `properties`:
      AZSC/Management/RoleDefinition
      AZSC/Management/ManagementGroup
      AZSC/Management/PolicyDefinition
      AZSC/Management/PolicySetDefinition

.NOTES
    Isolated collect-phase implementation for AB#5933 (Epic AB#5917). Invoke-Collect does not
    call this function yet; old collectors remain the live path until definitions are ready.
#>
function Get-ScoutTenantWideResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ApiResources
    )

    $PolicyDefinitions = @(
        foreach ($ApiResult in @($ApiResources)) {
            if ($null -ne $ApiResult -and
                $ApiResult.PSObject.Properties.Name -contains 'PolicyDefinitions' -and
                $null -ne $ApiResult.PolicyDefinitions) {
                @($ApiResult.PolicyDefinitions) | Where-Object { $null -ne $_ }
            }
        }
    )
    $PolicySetDefinitions = @(
        foreach ($ApiResult in @($ApiResources)) {
            if ($null -ne $ApiResult -and
                $ApiResult.PSObject.Properties.Name -contains 'PolicySetDefinitions' -and
                $null -ne $ApiResult.PolicySetDefinitions) {
                @($ApiResult.PolicySetDefinitions) | Where-Object { $null -ne $_ }
            }
        }
    )

    $CustomRoles = @()
    try {
        $CustomRoles = @(
            Get-AzRoleDefinition -Custom -ErrorAction Stop |
                Where-Object { $null -ne $_ }
        )
    }
    catch {
        Write-Warning (
            'Get-ScoutTenantWideResource: custom role definitions could not be read; ' +
            "returning zero role rows and continuing: $($_.Exception.Message)"
        )
    }

    $ExpandedRoots = @()
    $TenantId = $null
    try {
        $Context = Get-AzContext -ErrorAction SilentlyContinue
        if ($Context -and
            $Context.PSObject.Properties.Name -contains 'Tenant' -and
            $Context.Tenant -and
            $Context.Tenant.PSObject.Properties.Name -contains 'Id') {
            $TenantId = [string]$Context.Tenant.Id
        }
    }
    catch {
        Write-Verbose "Get-ScoutTenantWideResource: Azure context was unavailable: $($_.Exception.Message)"
    }

    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        try {
            $ExpandedRoots = @(
                Get-AzManagementGroup -GroupId $TenantId -Expand -Recurse -ErrorAction Stop |
                    Where-Object { $null -ne $_ }
            )
        }
        catch {
            Write-Verbose (
                "Get-ScoutTenantWideResource: tenant-root management-group expansion failed; " +
                "trying visible-group fallback: $($_.Exception.Message)"
            )
            $ExpandedRoots = @()
        }
    }

    if ($ExpandedRoots.Count -eq 0) {
        try {
            $VisibleGroups = @(
                Get-AzManagementGroup -ErrorAction Stop |
                    Where-Object {
                        $null -ne $_ -and
                        $_.PSObject.Properties.Name -contains 'Name' -and
                        -not [string]::IsNullOrWhiteSpace([string]$_.Name)
                    }
            )
            $ExpandedGroups = @(
                foreach ($VisibleGroup in $VisibleGroups) {
                    try {
                        Get-AzManagementGroup -GroupId $VisibleGroup.Name -Expand -Recurse -ErrorAction Stop
                    }
                    catch {
                        Write-Verbose (
                            "Get-ScoutTenantWideResource: management group '$($VisibleGroup.Name)' " +
                            "could not be expanded: $($_.Exception.Message)"
                        )
                    }
                }
            ) | Where-Object { $null -ne $_ }

            $RootGroups = @(
                $ExpandedGroups | Where-Object {
                    $_.PSObject.Properties.Name -notcontains 'ParentName' -or
                    [string]::IsNullOrWhiteSpace([string]$_.ParentName)
                }
            )
            $ExpandedRoots = if ($RootGroups.Count -gt 0) {
                $RootGroups
            }
            else {
                $ExpandedGroups
            }
        }
        catch {
            Write-Warning (
                'Get-ScoutTenantWideResource: management groups could not be read; ' +
                "returning zero management-group rows and continuing: $($_.Exception.Message)"
            )
            $ExpandedRoots = @()
        }
    }

    $ManagementGroups = @(
        if (@($ExpandedRoots).Count -gt 0) {
            ConvertTo-ScoutManagementGroupHierarchy -Root $ExpandedRoots
        }
    )

    @(
        [PSCustomObject]@{
            type       = 'AZSC/Management/RoleDefinition'
            properties = @($CustomRoles)
        }
        [PSCustomObject]@{
            type       = 'AZSC/Management/ManagementGroup'
            properties = @($ManagementGroups)
        }
        [PSCustomObject]@{
            type       = 'AZSC/Management/PolicyDefinition'
            properties = @($PolicyDefinitions)
        }
        [PSCustomObject]@{
            type       = 'AZSC/Management/PolicySetDefinition'
            properties = @($PolicySetDefinitions)
        }
    )
}
