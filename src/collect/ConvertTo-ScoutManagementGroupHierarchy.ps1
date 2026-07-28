#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Flatten expanded Azure management-group trees for declarative collection.

.DESCRIPTION
    Converts one or more expanded Get-AzManagementGroup results into a deterministic pre-order
    row set. Each row carries the hierarchy values the inventory collector previously derived
    recursively inside its Processing branch. Subscription children are counted but are not
    emitted as management-group rows.

.PARAMETER Root
    Expanded management-group root objects. Each object may contain management-group and
    subscription entries in Children.

.OUTPUTS
    One PSCustomObject per management group, in root-before-descendants order.

.NOTES
    Collect-phase prerequisite for AB#5933 (Epic AB#5917).
#>
function ConvertTo-ScoutManagementGroupHierarchy {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]]$Root
    )

    begin {
        function Get-NodeValue {
            param(
                [AllowNull()] [object]$InputObject,
                [Parameter(Mandatory)] [string]$Name
            )

            if ($null -eq $InputObject -or
                $InputObject.PSObject.Properties.Name -notcontains $Name) {
                return $null
            }
            return $InputObject.$Name
        }

        function Expand-Node {
            param(
                [AllowNull()] [object]$Node,
                [int]$Depth = 0,
                [string]$ParentPath = ''
            )

            if ($null -eq $Node) { return }

            $Name = [string](Get-NodeValue -InputObject $Node -Name 'Name')
            $DisplayName = [string](Get-NodeValue -InputObject $Node -Name 'DisplayName')
            if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $Name }

            $NodePath = if ([string]::IsNullOrWhiteSpace($ParentPath)) {
                $DisplayName
            }
            else {
                "$ParentPath / $DisplayName"
            }

            $Children = @(
                if ($Node.PSObject.Properties.Name -contains 'Children' -and
                    $null -ne $Node.Children) {
                    @($Node.Children)
                }
            )
            $DirectGroups = @(
                $Children | Where-Object {
                    $null -ne $_ -and
                    $_.PSObject.Properties.Name -contains 'Type' -and
                    [string]$_.Type -like '*managementGroups'
                }
            )
            $DirectSubscriptions = @(
                $Children | Where-Object {
                    $null -ne $_ -and
                    $_.PSObject.Properties.Name -contains 'Type' -and
                    [string]$_.Type -like '*subscriptions'
                }
            )
            $DirectSubscriptionNames = @(
                $DirectSubscriptions | ForEach-Object {
                    [string](Get-NodeValue -InputObject $_ -Name 'DisplayName')
                } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            ) -join ', '

            $ParentName = [string](Get-NodeValue -InputObject $Node -Name 'ParentName')
            $ParentDisplayName = [string](Get-NodeValue -InputObject $Node -Name 'ParentDisplayName')
            if (-not [string]::IsNullOrWhiteSpace($ParentName) -and
                [string]::IsNullOrWhiteSpace($ParentDisplayName)) {
                $ParentDisplayName = $ParentName
            }

            [PSCustomObject][ordered]@{
                'Management Group ID'       = $Name
                'Display Name'              = ('    ' * $Depth) + $DisplayName
                'Display Name (Raw)'        = $DisplayName
                'Full Path'                 = $NodePath
                'Hierarchy Depth'           = $Depth
                'Parent Management Group'   = if ([string]::IsNullOrWhiteSpace($ParentName)) {
                    'Tenant Root'
                } else {
                    $ParentDisplayName
                }
                'Tenant ID'                 = Get-NodeValue -InputObject $Node -Name 'TenantId'
                'Direct Child MGs'          = $DirectGroups.Count
                'Direct Subscriptions'      = $DirectSubscriptions.Count
                'Direct Subscription Names' = $DirectSubscriptionNames
            }

            foreach ($Child in $DirectGroups) {
                Expand-Node -Node $Child -Depth ($Depth + 1) -ParentPath $NodePath
            }
        }
    }

    process {
        foreach ($RootNode in @($Root)) {
            Expand-Node -Node $RootNode
        }
    }
}
