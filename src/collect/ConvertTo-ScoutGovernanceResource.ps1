#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Turn the four governance datasets into the typed envelopes their inventory collectors render.

.DESCRIPTION
    A PURE TRANSFORM. It reads only what `Get-ScoutGovernanceDataset` already collected and makes
    no Azure call of any kind -- which is what lets AB#6779's four worksheets exist without adding
    a round trip. `tests/Collect.Governance.Tests.ps1` proves the no-call claim by running this
    function with every Azure cmdlet stubbed to throw.

    Flattening happens HERE rather than in the collector manifests for two reasons:

      * a manifest expression runs under the declarative interpreter, where an absent nested
        property is a StrictMode throw that loses the whole worksheet (AB#6839/AB#6844). Guarding
        it is ordinary PowerShell here and an unreadable one-liner there;
      * the subscription NAME, the role NAME and the scope KIND each need a lookup or a derivation
        that no single field expression can express.

    Same contract as `Get-ScoutTenantWideResource` (AB#5933/AB#6755): every envelope is returned
    even when its rows array is empty, so an estate with no budgets renders an empty Budgets
    worksheet rather than no worksheet at all.

.PARAMETER Governance
    The `Get-ScoutGovernanceDataset` output object. Any absent key degrades that one envelope to
    zero rows.

.PARAMETER Subscriptions
    Subscription objects with `.id`/`.name`, used to name the subscription a scope belongs to.

.OUTPUTS
    Exactly four PSCustomObjects, in stable type order, each with `type` and `properties`:
      AZSC/Governance/RoleAssignment
      AZSC/Governance/PolicyAssignment
      AZSC/Governance/ResourceLock
      AZSC/Governance/Budget

.NOTES
    Tracks ADO Task AB#6780/AB#6781/AB#6782/AB#6783 (Story AB#6779).
#>

function Get-ScoutGovernanceValue {
    <#
        StrictMode-safe read of a dotted path off an arbitrarily-shaped payload.

        Under `Set-StrictMode -Version Latest` a missing property on an EXISTING object throws
        rather than returning $null, and a governance payload is exactly where that bites: an
        assignment with no `condition`, a budget with no `forecastSpend`, a lock with no `notes`.
        Every read below goes through here for that reason.
    #>
    [CmdletBinding()]
    param([object] $InputObject, [Parameter(Mandatory)][string] $Path)

    $cursor = $InputObject
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $cursor) { return $null }
        if ($cursor -is [System.Collections.IDictionary]) {
            $key = @($cursor.Keys) | Where-Object { [string]$_ -ieq $segment } | Select-Object -First 1
            if ($null -eq $key) { return $null }
            $cursor = $cursor[$key]
            continue
        }
        $property = $cursor.PSObject.Properties | Where-Object { $_.Name -ieq $segment } | Select-Object -First 1
        if ($null -eq $property) { return $null }
        $cursor = $property.Value
    }
    return $cursor
}

function Get-ScoutGovernanceScopeKind {
    <#
        What a governance scope is ATTACHED to, derived from the scope string alone.

        This is the column that makes a role-assignment worksheet readable: an Owner assignment at
        a management group and an Owner assignment on one storage account are the same row shape
        and wildly different findings.
    #>
    [CmdletBinding()]
    param([string] $Scope)

    if ([string]::IsNullOrWhiteSpace($Scope)) { return 'Unknown' }
    $trimmed = $Scope.Trim().TrimEnd('/')
    if ($trimmed -match '(?i)^/providers/Microsoft\.Management/managementGroups/[^/]+$') { return 'Management Group' }
    if ($trimmed -match '(?i)^/$' -or $trimmed -eq '') { return 'Tenant Root' }

    $segments = @($trimmed -split '/' | Where-Object { $_ })
    if ($segments.Count -eq 0) { return 'Tenant Root' }
    if ($segments[0] -ieq 'subscriptions') {
        if ($segments.Count -eq 2) { return 'Subscription' }
        if ($segments.Count -eq 4 -and $segments[2] -ieq 'resourceGroups') { return 'Resource Group' }
        return 'Resource'
    }
    return 'Other'
}

function Get-ScoutGovernanceSubscriptionId {
    <# The subscription a scope/ARM id belongs to, or $null for a management-group scope. #>
    [CmdletBinding()]
    param([string] $Scope)

    if ([string]::IsNullOrWhiteSpace($Scope)) { return $null }
    $match = [regex]::Match($Scope, '(?i)/subscriptions/([0-9a-f-]{36})')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function ConvertTo-ScoutGovernanceResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [object] $Governance,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Subscriptions = @()
    )

    # ---- lookups ------------------------------------------------------------------------------
    $subscriptionNames = @{}
    foreach ($subscription in @($Subscriptions)) {
        if ($null -eq $subscription) { continue }
        $id = Get-ScoutGovernanceValue -InputObject $subscription -Path 'id'
        if ([string]::IsNullOrWhiteSpace([string]$id)) { continue }
        $name = Get-ScoutGovernanceValue -InputObject $subscription -Path 'name'
        $subscriptionNames[[string]$id] = if ([string]::IsNullOrWhiteSpace([string]$name)) { [string]$id } else { [string]$name }
    }

    function Resolve-ScoutGovernanceSubscriptionName([string] $Scope) {
        $id = Get-ScoutGovernanceSubscriptionId -Scope $Scope
        if (-not $id) { return $null }
        if ($subscriptionNames.ContainsKey($id)) { return $subscriptionNames[$id] }
        return $id
    }

    $dataset = if ($null -ne $Governance) { $Governance } else { [pscustomobject]@{} }
    function Get-ScoutGovernanceSet([string] $Name) {
        $value = Get-ScoutGovernanceValue -InputObject $dataset -Path $Name
        return @($value | Where-Object { $null -ne $_ })
    }

    # Role definitions, keyed by the LAST segment of their ARM id -- the GUID a role assignment's
    # roleDefinitionId ends with. Keying on the whole id would miss every assignment made at a
    # different scope than the definition was read at, which is most of them.
    $roleNames = @{}
    foreach ($definition in (Get-ScoutGovernanceSet 'roleDefinitions')) {
        $id = [string](Get-ScoutGovernanceValue -InputObject $definition -Path 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $guid = @($id.TrimEnd('/') -split '/')[-1]
        if ([string]::IsNullOrWhiteSpace($guid)) { continue }
        $roleNames[$guid.ToLowerInvariant()] = [pscustomobject]@{
            Name = [string](Get-ScoutGovernanceValue -InputObject $definition -Path 'properties.roleName')
            Type = [string](Get-ScoutGovernanceValue -InputObject $definition -Path 'properties.type')
        }
    }

    # ---- Role assignments ---------------------------------------------------------------------
    $roleAssignmentRows = @(
        foreach ($assignment in (Get-ScoutGovernanceSet 'roleAssignments')) {
            $scope = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.scope')
            $assignmentId = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'id')
            # A role assignment's own id is always rooted at the scope it applies to, so it is a
            # sound fallback when the payload omits properties.scope.
            if ([string]::IsNullOrWhiteSpace($scope) -and -not [string]::IsNullOrWhiteSpace($assignmentId)) {
                $scope = ($assignmentId -split '(?i)/providers/Microsoft\.Authorization/roleAssignments/')[0]
            }

            $roleDefinitionId = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.roleDefinitionId')
            $roleGuid = if ([string]::IsNullOrWhiteSpace($roleDefinitionId)) { '' } else { @($roleDefinitionId.TrimEnd('/') -split '/')[-1] }
            $role = if ($roleGuid -and $roleNames.ContainsKey($roleGuid.ToLowerInvariant())) { $roleNames[$roleGuid.ToLowerInvariant()] } else { $null }
            # Never blank. An unresolved role reads as the GUID it actually is, so the row says
            # "we could not name this" instead of looking like an assignment to nothing.
            $roleName = if ($role -and -not [string]::IsNullOrWhiteSpace($role.Name)) { $role.Name }
                        elseif ($roleGuid) { "Unresolved ($roleGuid)" }
                        else { $null }

            [pscustomobject]@{
                'Subscription'       = Resolve-ScoutGovernanceSubscriptionName $scope
                'Scope Type'         = Get-ScoutGovernanceScopeKind -Scope $scope
                'Scope'              = $scope
                'Role Name'          = $roleName
                'Role Type'          = if ($role) { $role.Type } else { $null }
                'Principal ID'       = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.principalId')
                'Principal Type'     = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.principalType')
                'Condition'          = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.condition')
                'Description'        = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.description')
                'Created On'         = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.createdOn')
                'Assignment Name'    = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'name')
                'Role Definition ID' = $roleDefinitionId
                'ID'                 = $assignmentId
            }
        }
    )

    # ---- Policy assignments -------------------------------------------------------------------
    $policyAssignmentRows = @(
        foreach ($assignment in (Get-ScoutGovernanceSet 'policyAssignments')) {
            $scope = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.scope')
            $assignmentId = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'id')
            if ([string]::IsNullOrWhiteSpace($scope) -and -not [string]::IsNullOrWhiteSpace($assignmentId)) {
                $scope = ($assignmentId -split '(?i)/providers/Microsoft\.Authorization/policyAssignments/')[0]
            }

            $definitionId = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.policyDefinitionId')
            # Initiative vs single policy is the first thing anyone asks of this sheet, and the
            # only place the answer lives is the provider segment of the definition id.
            $definitionKind = if ($definitionId -match '(?i)/policySetDefinitions/') { 'Initiative' }
                              elseif ($definitionId -match '(?i)/policyDefinitions/') { 'Policy' }
                              else { $null }

            $parameters = Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.parameters'
            $parameterCount = if ($null -eq $parameters) { 0 }
                              elseif ($parameters -is [System.Collections.IDictionary]) { @($parameters.Keys).Count }
                              else { @($parameters.PSObject.Properties).Count }

            $notScopes = @(Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.notScopes' | Where-Object { $_ })

            [pscustomobject]@{
                'Subscription'      = Resolve-ScoutGovernanceSubscriptionName $scope
                'Scope Type'        = Get-ScoutGovernanceScopeKind -Scope $scope
                'Scope'             = $scope
                'Assignment Name'   = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'name')
                'Display Name'      = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.displayName')
                'Assigned'          = $definitionKind
                'Definition'        = if ($definitionId) { @($definitionId.TrimEnd('/') -split '/')[-1] } else { $null }
                'Enforcement Mode'  = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.enforcementMode')
                'Excluded Scopes'   = $notScopes.Count
                'Parameters'        = $parameterCount
                'Description'       = [string](Get-ScoutGovernanceValue -InputObject $assignment -Path 'properties.description')
                'Definition ID'     = $definitionId
                'ID'                = $assignmentId
            }
        }
    )

    # ---- Resource locks -----------------------------------------------------------------------
    $resourceLockRows = @(
        foreach ($lock in (Get-ScoutGovernanceSet 'resourceLocks')) {
            $lockId = [string](Get-ScoutGovernanceValue -InputObject $lock -Path 'id')
            # A lock's ARM id is `<locked scope>/providers/Microsoft.Authorization/locks/<name>`,
            # so the scope it protects is the id with that suffix removed. This is the whole point
            # of the sheet -- "what is protected from deletion" is a question about the SCOPE, not
            # about the lock resource.
            $scope = if ([string]::IsNullOrWhiteSpace($lockId)) { '' }
                     else { ($lockId -split '(?i)/providers/Microsoft\.Authorization/locks/')[0] }

            [pscustomobject]@{
                'Subscription'    = Resolve-ScoutGovernanceSubscriptionName $scope
                'Scope Type'      = Get-ScoutGovernanceScopeKind -Scope $scope
                'Protects'        = $scope
                'Lock Name'       = [string](Get-ScoutGovernanceValue -InputObject $lock -Path 'name')
                'Lock Level'      = [string](Get-ScoutGovernanceValue -InputObject $lock -Path 'properties.level')
                'Notes'           = [string](Get-ScoutGovernanceValue -InputObject $lock -Path 'properties.notes')
                'ID'              = $lockId
            }
        }
    )

    # ---- Budgets ------------------------------------------------------------------------------
    $budgetRows = @(
        foreach ($budget in (Get-ScoutGovernanceSet 'budgets')) {
            $budgetId = [string](Get-ScoutGovernanceValue -InputObject $budget -Path 'id')
            $amount = Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.amount'
            $spent = Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.currentSpend.amount'

            # The one number an operator actually reads. Computed here and not in a field
            # expression because a budget with amount 0 is legal ARM and a divide there would take
            # the worksheet down rather than blank one cell.
            $usedPct = $null
            if ($null -ne $amount -and $null -ne $spent) {
                $amountValue = 0.0; $spentValue = 0.0
                if ([double]::TryParse([string]$amount, [ref]$amountValue) -and
                    [double]::TryParse([string]$spent, [ref]$spentValue) -and
                    $amountValue -gt 0) {
                    $usedPct = [math]::Round(($spentValue / $amountValue) * 100, 1)
                }
            }

            $notifications = Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.notifications'
            $notificationCount = if ($null -eq $notifications) { 0 }
                                 elseif ($notifications -is [System.Collections.IDictionary]) { @($notifications.Keys).Count }
                                 else { @($notifications.PSObject.Properties).Count }

            [pscustomobject]@{
                'Subscription'      = Resolve-ScoutGovernanceSubscriptionName $budgetId
                'Name'              = [string](Get-ScoutGovernanceValue -InputObject $budget -Path 'name')
                'Category'          = [string](Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.category')
                'Amount'            = $amount
                'Currency'          = [string](Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.currentSpend.unit')
                'Time Grain'        = [string](Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.timeGrain')
                'Start Date'        = [string](Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.timePeriod.startDate')
                'End Date'          = [string](Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.timePeriod.endDate')
                'Current Spend'     = $spent
                'Forecast Spend'    = Get-ScoutGovernanceValue -InputObject $budget -Path 'properties.forecastSpend.amount'
                'Budget Used %'     = $usedPct
                'Alerts Configured' = $notificationCount
                'ID'                = $budgetId
            }
        }
    )

    @(
        [PSCustomObject]@{
            type       = 'AZSC/Governance/RoleAssignment'
            properties = @($roleAssignmentRows)
        }
        [PSCustomObject]@{
            type       = 'AZSC/Governance/PolicyAssignment'
            properties = @($policyAssignmentRows)
        }
        [PSCustomObject]@{
            type       = 'AZSC/Governance/ResourceLock'
            properties = @($resourceLockRows)
        }
        [PSCustomObject]@{
            type       = 'AZSC/Governance/Budget'
            properties = @($budgetRows)
        }
    )
}
