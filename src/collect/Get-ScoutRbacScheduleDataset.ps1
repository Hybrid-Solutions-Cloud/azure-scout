#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Read the Azure RBAC role eligibility and role assignment schedules (Privileged Identity
    Management for Azure resources) for every subscription, and normalise them into the rows
    collect.json carries.

.DESCRIPTION
    `Get-AzRoleEligibilitySchedule` was already called per subscription by
    Get-ScoutGovernanceDataset, and its rows were then DISCARDED: Invoke-Collect hard-coded
    `pimEligibility = @()` and Import-Governance hard-coded `pimEligibilityAvailable = $false`, so
    every rule that asks "is just-in-time privileged access used" read NotAssessed on every run
    even though the answer had been fetched. This function is the one place both consumers read it
    from (the raw pass through Get-ScoutGovernanceDataset, and the -Source TypedQueries path
    through Import-Governance), so the two collect.json paths carry the same keys.

    TWO READS PER SUBSCRIPTION, kept in one loop:

        Get-AzRoleEligibilitySchedule   who CAN elevate (eligible, not active)
        Get-AzRoleAssignmentSchedule    who HAS access now: AssignmentType 'Assigned' is active
                                        without an activation (standing access, permanent when
                                        EndDateTime is null); 'Activated' is an eligible
                                        assignment someone elevated into (just-in-time)

    Both are needed to tell standing access from just-in-time access for the privileged roles
    (Owner, Contributor, User Access Administrator, Role Based Access Control Administrator).
    An eligibility list alone cannot say how much standing access still exists beside it.

    ROWS ARE AN ALLOW-LIST, NEVER THE CMDLET OBJECT. The cmdlet's objects carry the principal's
    display name and e-mail address; neither belongs in collect.json (which feeds reports that are
    shared). Only identifiers and the facts a rule scores are kept.

    AVAILABILITY IS ALL-OR-NOTHING, ON PURPOSE. `pimEligibilityAvailable` is $true only when the
    eligibility read ANSWERED for every subscription (an empty answer counts: a subscription with no
    eligible assignments is a real answer). One refusal makes it $false and `pimEligibilityReason`
    says why, because "9 of 10 subscriptions use PIM" cannot be told from "PIM is not used" when
    the tenth never answered -- the rules gate on the flag and read NotAssessed, never Fail.
    `roleAssignmentSchedulesMeasured` is the same contract for the assignment-schedule read, and
    `privilegedAccessMeasured` is true only when both are (the standing-versus-eligible ratio needs
    both halves).

    Subscriptions are read 8 at a time when the real Az.Resources commands are in use (about 2.8
    seconds per subscription per read on a live tenant, so 42 subscriptions would otherwise add
    about four minutes); a test stand-in is never run in a worker runspace. A subscription whose
    parallel read failed transiently is read once more in the calling session.

.PARAMETER SubscriptionId
    Subscription ids to read. Duplicates are ignored.

.PARAMETER ThrottleLimit
    Concurrent subscriptions when the real commands are in use. 1 forces the serial path.

.OUTPUTS
    [pscustomobject]: pimEligibility[], pimEligibilityAvailable, pimEligibilityReason,
    roleAssignmentSchedules[], roleAssignmentSchedulesMeasured, roleAssignmentSchedulesReason,
    privilegedAccessMeasured, sourceOperations[]. Arrays are never $null.

.NOTES
    Read-only. Needs `Microsoft.Authorization/roleEligibilitySchedules/read` and
    `roleAssignmentSchedules/read` (both in the Reader role). An Entra ID P2 / Governance licence
    is NOT required to read the schedules; a tenant without PIM simply returns none.
#>
function Get-ScoutRbacScheduleDataset {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [string[]] $SubscriptionId = @(),

        [ValidateRange(1, 16)]
        [int] $ThrottleLimit = 8
    )

    # Built-in roles that can change who has access or change everything: the "privileged" set the
    # CAF/WAF identity guidance means when it says standing access to privileged roles. Ids, not
    # names, because a role is renamed far more often than it is re-issued an id.
    $privilegedRoleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($roleId in @(
            '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'   # Owner
            'b24988ac-6180-42a0-ab88-20f7382dd24c'   # Contributor
            '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'   # User Access Administrator
            'f58310d9-a9f6-439a-9e8d-f62e7b41a168'   # Role Based Access Control Administrator
        )) { [void]$privilegedRoleIds.Add($roleId) }

    function Get-ScoutRbacValue {
        param($InputObject, [string] $Name)
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IDictionary]) {
            foreach ($key in $InputObject.Keys) { if ([string]$key -ieq $Name) { return $InputObject[$key] } }
            return $null
        }
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -eq $property) { return $null }
        return $property.Value
    }

    function ConvertTo-ScoutRbacIsoDate {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [datetime]) {
            # The cmdlet returns UTC instants; an Unspecified kind must not be shifted as if local.
            $instant = if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) } else { $Value.ToUniversalTime() }
            return $instant.ToString('o')
        }
        if ($Value -is [System.DateTimeOffset]) { return $Value.UtcDateTime.ToString('o') }
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
            return $parsed.ToString('o')
        }
        return $text
    }

    function Get-ScoutRbacScopeType {
        param([string] $Scope, [string] $Fallback)
        if ([string]::IsNullOrWhiteSpace($Scope)) { return $(if ([string]::IsNullOrWhiteSpace($Fallback)) { $null } else { $Fallback }) }
        if ($Scope -match '(?i)/providers/Microsoft\.Management/managementGroups/[^/]+$') { return 'managementGroup' }
        if ($Scope -match '(?i)^/subscriptions/[^/]+$') { return 'subscription' }
        if ($Scope -match '(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$') { return 'resourceGroup' }
        if ($Scope -match '(?i)^/subscriptions/') { return 'resource' }
        if ($Scope -eq '/') { return 'tenant' }
        return $(if ([string]::IsNullOrWhiteSpace($Fallback)) { $null } else { $Fallback })
    }

    # A message is carried into collect.json and the report; strip the identifiers an exception
    # likes to quote (subscription and tenant ids) and cap its length.
    function Protect-ScoutRbacMessage {
        param([string] $Message)
        if ([string]::IsNullOrWhiteSpace($Message)) { return 'no error text' }
        $clean = [regex]::Replace($Message, '(?i)/subscriptions/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', '/subscriptions/{id}')
        $clean = [regex]::Replace($clean, '(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b', '{id}')
        $clean = ($clean -replace '\s+', ' ').Trim()
        if ($clean.Length -gt 300) { $clean = $clean.Substring(0, 300) + '...' }
        return $clean
    }

    # One normalised row. `accessType` is the field the rules union on:
    #   Eligible   an eligibility schedule (can elevate, not active)
    #   Standing   an active assignment that needed no activation (permanent when EndDateTime is null)
    #   Activated  an eligible assignment someone elevated into (just-in-time, always time-bound)
    function ConvertTo-ScoutRbacScheduleRow {
        param($Schedule, [ValidateSet('Eligible', 'Schedule')][string] $Kind)

        $roleDefinitionId = [string](Get-ScoutRbacValue $Schedule 'RoleDefinitionId')
        $roleGuid = if ($roleDefinitionId) { ($roleDefinitionId.TrimEnd('/') -split '/')[-1] } else { '' }
        $roleName = [string](Get-ScoutRbacValue $Schedule 'RoleDefinitionDisplayName')
        $scope = [string](Get-ScoutRbacValue $Schedule 'Scope')
        $endDate = ConvertTo-ScoutRbacIsoDate (Get-ScoutRbacValue $Schedule 'EndDateTime')

        $row = [ordered]@{
            id                = [string](Get-ScoutRbacValue $Schedule 'Id')
            principalId       = [string](Get-ScoutRbacValue $Schedule 'PrincipalId')
            principalType     = [string](Get-ScoutRbacValue $Schedule 'PrincipalType')
            roleDefinitionId  = $roleDefinitionId
            roleDefinitionName = $roleName
            scope             = $scope
            scopeType         = Get-ScoutRbacScopeType -Scope $scope -Fallback ([string](Get-ScoutRbacValue $Schedule 'ScopeType'))
            memberType        = [string](Get-ScoutRbacValue $Schedule 'MemberType')
            status            = [string](Get-ScoutRbacValue $Schedule 'Status')
            startDateTime     = ConvertTo-ScoutRbacIsoDate (Get-ScoutRbacValue $Schedule 'StartDateTime')
            endDateTime       = $endDate
            permanent         = ($null -eq $endDate)
            privilegedRole    = ($roleGuid -and $privilegedRoleIds.Contains($roleGuid))
        }
        if ($Kind -eq 'Eligible') {
            $row['accessType'] = 'Eligible'
        }
        else {
            $assignmentType = [string](Get-ScoutRbacValue $Schedule 'AssignmentType')
            $row['assignmentType'] = $assignmentType
            $row['accessType'] = if ($assignmentType -ieq 'Activated') { 'Activated' } else { 'Standing' }
        }
        return [pscustomobject]$row
    }

    # Distinct rows: a schedule inherited from a management group or the tenant root is returned
    # by the read of every subscription beneath it. The ARM id is unique per schedule; a row with
    # no id falls back to principal + role + scope.
    # Rows are emitted one by one; the caller wraps the call in @() so zero rows is an empty array.
    function Merge-ScoutRbacRow {
        param([object[]] $Rows)
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $Rows) {
            if ($null -eq $row) { continue }
            $key = if (-not [string]::IsNullOrWhiteSpace($row.id)) { 'id|' + $row.id }
                   else { 'k|{0}|{1}|{2}|{3}' -f $row.principalId, $row.roleDefinitionId, $row.scope, $row.accessType }
            if ($seen.Add($key)) { $row }
        }
    }

    # The read, as TEXT, so the serial path and the worker runspaces run one and the same logic
    # (a function defined here is not visible inside ForEach-Object -Parallel, and a scriptblock
    # variable cannot be passed in with $using).
    $readText = @'
param([string] $SubscriptionId)
$out = [pscustomobject]@{
    SubscriptionId = $SubscriptionId
    Eligibility = @(); EligibilityError = $null; EligibilityStartedAt = (Get-Date).ToString('o'); EligibilityCompletedAt = $null
    Schedules = @(); SchedulesError = $null; SchedulesStartedAt = $null; SchedulesCompletedAt = $null
}
try { $out.Eligibility = @(Get-AzRoleEligibilitySchedule -Scope "/subscriptions/$SubscriptionId" -ErrorAction Stop -WarningAction SilentlyContinue) }
catch { $out.EligibilityError = [string]$_.Exception.Message }
$out.EligibilityCompletedAt = (Get-Date).ToString('o')
$out.SchedulesStartedAt = (Get-Date).ToString('o')
try { $out.Schedules = @(Get-AzRoleAssignmentSchedule -Scope "/subscriptions/$SubscriptionId" -ErrorAction Stop -WarningAction SilentlyContinue) }
catch { $out.SchedulesError = [string]$_.Exception.Message }
$out.SchedulesCompletedAt = (Get-Date).ToString('o')
$out
'@

    $subscriptionIds = @($SubscriptionId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)

    $answers = @{}
    $transient = '(?i)429|too many requests|timed? ?out|temporar|service unavailable|bad gateway|gateway timeout|\b50[234]\b|connection'

    # ---- the real commands are read in worker runspaces; a mock or stand-in never is --------------
    function Test-ScoutRbacRealCommand {
        param([string] $Name)
        $command = Get-Command $Name -ErrorAction SilentlyContinue
        return ($null -ne $command -and (
                $command.CommandType -eq 'Cmdlet' -or
                ($command.CommandType -eq 'Function' -and [string]$command.ModuleName -eq 'Az.Resources')))
    }
    if ($subscriptionIds.Count -ge 2 -and $ThrottleLimit -gt 1 -and
        (Test-ScoutRbacRealCommand 'Get-AzRoleEligibilitySchedule') -and (Test-ScoutRbacRealCommand 'Get-AzRoleAssignmentSchedule')) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $subscriptionIds | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                & ([scriptblock]::Create($using:readText)) $_
            } | ForEach-Object { if ($null -ne $_) { $answers[[string]$_.SubscriptionId] = $_ } }
        }
        catch {
            Write-Verbose "Get-ScoutRbacScheduleDataset: concurrent read unavailable, reading one subscription at a time: $($_.Exception.Message)"
            $answers = @{}
        }
        Write-Verbose ('Get-ScoutRbacScheduleDataset: concurrent read answered {0} of {1} subscription(s) in {2} ms' -f $answers.Count, $subscriptionIds.Count, $timer.ElapsedMilliseconds)
    }

    $readBlock = [scriptblock]::Create($readText)
    foreach ($sub in $subscriptionIds) {
        $answer = if ($answers.ContainsKey($sub)) { $answers[$sub] } else { $null }
        $retry = $null -eq $answer -or
            ($answer.EligibilityError -and [string]$answer.EligibilityError -match $transient) -or
            ($answer.SchedulesError -and [string]$answer.SchedulesError -match $transient)
        if ($retry) { $answers[$sub] = & $readBlock $sub }
    }

    # ---- aggregate in the caller's order, so the output is deterministic -------------------------
    $eligibleRows = [System.Collections.Generic.List[object]]::new()
    $scheduleRows = [System.Collections.Generic.List[object]]::new()
    $operations = [System.Collections.Generic.List[object]]::new()
    $eligibilityFailures = [System.Collections.Generic.List[string]]::new()
    $scheduleFailures = [System.Collections.Generic.List[string]]::new()

    foreach ($sub in $subscriptionIds) {
        $answer = $answers[$sub]
        $scope = "/subscriptions/$sub"

        $eligibilityFailed = -not [string]::IsNullOrEmpty([string]$answer.EligibilityError)
        if (-not $eligibilityFailed) {
            foreach ($schedule in @($answer.Eligibility)) {
                if ($null -ne $schedule) { $eligibleRows.Add((ConvertTo-ScoutRbacScheduleRow -Schedule $schedule -Kind Eligible)) }
            }
        }
        else {
            $eligibilityFailures.Add((Protect-ScoutRbacMessage ([string]$answer.EligibilityError)))
            Write-Verbose ('Get-ScoutRbacScheduleDataset: PIM eligibility read failed for {0}: {1}' -f $sub, $answer.EligibilityError)
        }
        $operations.Add([pscustomobject]@{
                Source = 'Azure RBAC control plane'
                Dataset = 'PIM role eligibility schedules'
                SubscriptionId = $sub
                Operation = 'Get-AzRoleEligibilitySchedule'
                Scope = $scope
                Status = if ($eligibilityFailed) { 'Unavailable' } elseif (@($answer.Eligibility | Where-Object { $null -ne $_ }).Count -gt 0) { 'Success' } else { 'Empty' }
                Count = if ($eligibilityFailed) { 0 } else { @($answer.Eligibility | Where-Object { $null -ne $_ }).Count }
                Reason = if ($eligibilityFailed) { [string]$answer.EligibilityError } else { $null }
                StartedAt = $answer.EligibilityStartedAt
                CompletedAt = $answer.EligibilityCompletedAt
            })

        $schedulesFailed = -not [string]::IsNullOrEmpty([string]$answer.SchedulesError)
        if (-not $schedulesFailed) {
            foreach ($schedule in @($answer.Schedules)) {
                if ($null -ne $schedule) { $scheduleRows.Add((ConvertTo-ScoutRbacScheduleRow -Schedule $schedule -Kind Schedule)) }
            }
        }
        else {
            $scheduleFailures.Add((Protect-ScoutRbacMessage ([string]$answer.SchedulesError)))
            Write-Verbose ('Get-ScoutRbacScheduleDataset: role assignment schedule read failed for {0}: {1}' -f $sub, $answer.SchedulesError)
        }
        $operations.Add([pscustomobject]@{
                Source = 'Azure RBAC control plane'
                Dataset = 'Azure RBAC role assignment schedules'
                SubscriptionId = $sub
                Operation = 'Get-AzRoleAssignmentSchedule'
                Scope = $scope
                Status = if ($schedulesFailed) { 'Unavailable' } elseif (@($answer.Schedules | Where-Object { $null -ne $_ }).Count -gt 0) { 'Success' } else { 'Empty' }
                Count = if ($schedulesFailed) { 0 } else { @($answer.Schedules | Where-Object { $null -ne $_ }).Count }
                Reason = if ($schedulesFailed) { [string]$answer.SchedulesError } else { $null }
                StartedAt = $answer.SchedulesStartedAt
                CompletedAt = $answer.SchedulesCompletedAt
            })
    }

    function Get-ScoutRbacFailureSummary {
        param([string[]] $Failures, [int] $Total, [string] $Dataset)
        $detail = (@($Failures | Select-Object -Unique | Select-Object -First 2)) -join ' | '
        return ('The {0} read failed for {1} of {2} subscription(s): {3}' -f $Dataset, @($Failures).Count, $Total, $detail)
    }

    $noSubscriptions = $subscriptionIds.Count -eq 0
    $eligibilityAvailable = (-not $noSubscriptions) -and $eligibilityFailures.Count -eq 0
    $schedulesMeasured = (-not $noSubscriptions) -and $scheduleFailures.Count -eq 0
    $eligibilityReason = if ($eligibilityAvailable) { $null }
        elseif ($noSubscriptions) { 'No subscription was available to read PIM eligibility from.' }
        else { Get-ScoutRbacFailureSummary -Failures $eligibilityFailures.ToArray() -Total $subscriptionIds.Count -Dataset 'PIM eligibility' }
    $schedulesReason = if ($schedulesMeasured) { $null }
        elseif ($noSubscriptions) { 'No subscription was available to read role assignment schedules from.' }
        else { Get-ScoutRbacFailureSummary -Failures $scheduleFailures.ToArray() -Total $subscriptionIds.Count -Dataset 'role assignment schedule' }

    # One warning per dataset, not one per subscription: 42 refusals are one finding, and the
    # per-subscription detail is in the Verbose stream and in `sourceOperations`.
    if ($eligibilityReason -and -not $noSubscriptions) { Write-Warning "Get-ScoutRbacScheduleDataset: $eligibilityReason" }
    if ($schedulesReason -and -not $noSubscriptions) { Write-Warning "Get-ScoutRbacScheduleDataset: $schedulesReason" }

    return [pscustomobject]@{
        pimEligibility                  = @(Merge-ScoutRbacRow -Rows $eligibleRows.ToArray())
        pimEligibilityAvailable         = [bool]$eligibilityAvailable
        pimEligibilityReason            = $eligibilityReason
        roleAssignmentSchedules         = @(Merge-ScoutRbacRow -Rows $scheduleRows.ToArray())
        roleAssignmentSchedulesMeasured = [bool]$schedulesMeasured
        roleAssignmentSchedulesReason   = $schedulesReason
        privilegedAccessMeasured        = [bool]($eligibilityAvailable -and $schedulesMeasured)
        sourceOperations                = @($operations)
    }
}
