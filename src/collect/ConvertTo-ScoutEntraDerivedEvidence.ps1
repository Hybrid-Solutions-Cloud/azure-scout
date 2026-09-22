#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Derive review-ready Entra posture rows from retained Microsoft Graph evidence.

.DESCRIPTION
    Produces correlation rows for report-only Conditional Access impact, legacy authentication,
    emergency-access candidates, and privileged-role assignment schedules. Source responses remain
    untouched in raw-inventory.json; every derived row names the retained input datasets it used.
#>
function ConvertTo-ScoutEntraDerivedEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $EntraResources,
        [Parameter(Mandatory)][string] $TenantID
    )

    function Get-Value {
        param([AllowNull()]$Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        $property = $Object.PSObject.Properties[$Name]
        if ($property) { return $property.Value }
        return $null
    }

    function New-DerivedRow {
        param([string]$Type, [string]$Id, [string]$Name, $Properties, [string[]]$Inputs)
        [pscustomobject][ordered]@{
            id         = $Id
            name       = $Name
            TYPE       = $Type
            tenantId   = $TenantID
            properties = [pscustomobject]$Properties
            AZSC       = [pscustomobject][ordered]@{
                Source      = 'Derived from retained Microsoft Graph evidence'
                Dataset     = $Type
                Operation   = 'Correlation'
                Inputs      = @($Inputs)
                CollectedAt = (Get-Date).ToString('o')
            }
        }
    }

    function Mask-Upn {
        param([string]$Upn)
        if ([string]::IsNullOrWhiteSpace($Upn) -or $Upn -notmatch '@') { return '[masked]' }
        $parts = $Upn -split '@', 2
        $local = $parts[0]
        $masked = if ($local.Length -le 2) { ('*' * $local.Length) }
                  else { $local.Substring(0, 1) + ('*' * ($local.Length - 2)) + $local.Substring($local.Length - 1, 1) }
        return "$masked@$($parts[1])"
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $byType = @{}
    foreach ($resource in @($EntraResources)) {
        if ($null -eq $resource -or -not $resource.PSObject.Properties['TYPE']) { continue }
        $key = ([string]$resource.TYPE).ToLowerInvariant()
        if (-not $byType.ContainsKey($key)) { $byType[$key] = [System.Collections.Generic.List[object]]::new() }
        $byType[$key].Add($resource)
    }
    function Get-TypeRows {
        param([string]$Type)
        if ($byType.ContainsKey($Type)) { return @($byType[$Type]) }
        return @()
    }

    $policies = @(Get-TypeRows 'entra/conditionalaccesspolicies')
    $signIns = @(Get-TypeRows 'entra/signins')
    foreach ($policy in @($policies | Where-Object { (Get-Value $_.properties 'state') -eq 'enabledForReportingButNotEnforced' })) {
        $policyId = [string](Get-Value $policy.properties 'id')
        $impact = @{ reportOnlyFailure = 0; reportOnlySuccess = 0; reportOnlyInterrupted = 0; other = 0 }
        foreach ($signIn in $signIns) {
            foreach ($applied in @((Get-Value $signIn.properties 'appliedConditionalAccessPolicies'))) {
                if ([string](Get-Value $applied 'id') -ne $policyId) { continue }
                $result = [string](Get-Value $applied 'result')
                if ($impact.ContainsKey($result)) { $impact[$result]++ } else { $impact.other++ }
            }
        }
        $rows.Add((New-DerivedRow -Type 'entra/conditionalaccessreportonlyimpact' -Id $policyId -Name ([string]$policy.name) -Inputs @('entra/conditionalaccesspolicies', 'entra/signins') -Properties ([ordered]@{
                    policyId = $policyId
                    displayName = $policy.name
                    reportOnlyFailure = $impact.reportOnlyFailure
                    reportOnlySuccess = $impact.reportOnlySuccess
                    reportOnlyInterrupted = $impact.reportOnlyInterrupted
                    otherResult = $impact.other
                    observedSignIns = $impact.reportOnlyFailure + $impact.reportOnlySuccess + $impact.reportOnlyInterrupted + $impact.other
                    windowDays = 30
                })))
    }

    $legacyClients = @('Exchange ActiveSync', 'IMAP', 'POP', 'SMTP', 'MAPI', 'Other clients')
    $legacyGroups = @($signIns | Where-Object {
            [string](Get-Value $_.properties 'clientAppUsed') -in $legacyClients -and
            [int](Get-Value (Get-Value $_.properties 'status') 'errorCode') -eq 0
        } | Group-Object { [string](Get-Value $_.properties 'userPrincipalName') } | Sort-Object Count -Descending)
    foreach ($group in $legacyGroups) {
        $upn = [string]$group.Name
        $lastDate = @($group.Group | ForEach-Object { Get-Value $_.properties 'createdDateTime' } | Sort-Object -Descending | Select-Object -First 1)
        $rows.Add((New-DerivedRow -Type 'entra/legacyauthsummary' -Id $upn -Name (Mask-Upn $upn) -Inputs @('entra/signins') -Properties ([ordered]@{
                    maskedUserPrincipalName = Mask-Upn $upn
                    successfulSignIns = $group.Count
                    clientApps = @($group.Group | ForEach-Object { Get-Value $_.properties 'clientAppUsed' } | Sort-Object -Unique)
                    lastSignInDateTime = if ($lastDate.Count -gt 0) { $lastDate[0] } else { $null }
                    windowDays = 30
                })))
    }

    $users = @(Get-TypeRows 'entra/users')
    $registrations = @(Get-TypeRows 'entra/authenticationmethodregistrations')
    $activeSchedules = @(Get-TypeRows 'entra/roleassignmentschedules')
    $eligibleSchedules = @(Get-TypeRows 'entra/roleeligibilityschedules')
    $legacyAssignments = @(Get-TypeRows 'entra/pimassignments')
    $principalRows = @($users + @(Get-TypeRows 'entra/groups') + @(Get-TypeRows 'entra/serviceprincipals'))
    $principalById = @{}
    foreach ($principal in $principalRows) {
        if ($principal.id) { $principalById[[string]$principal.id] = $principal }
    }
    $registrationById = @{}
    foreach ($registration in $registrations) {
        if ($registration.id) { $registrationById[[string]$registration.id] = $registration }
    }

    $enabledUsers = @($users | Where-Object { (Get-Value $_.properties 'accountEnabled') -ne $false })
    $enabledRegistered = @($enabledUsers | Where-Object {
            $registrationById.ContainsKey([string]$_.id) -and
            (Get-Value $registrationById[[string]$_.id].properties 'isMfaRegistered') -eq $true
        })
    $adminRegistrations = @($registrations | Where-Object { (Get-Value $_.properties 'isAdmin') -eq $true })
    $adminRegistered = @($adminRegistrations | Where-Object { (Get-Value $_.properties 'isMfaRegistered') -eq $true })
    $phishingResistant = @($registrations | Where-Object {
            @((Get-Value $_.properties 'methodsRegistered') | Where-Object {
                    [string]$_ -match '(?i)fido|passkey|windowsHello|certificate'
                }).Count -gt 0
        })
    if ($users.Count -gt 0 -or $registrations.Count -gt 0) {
        $rows.Add((New-DerivedRow -Type 'entra/mfaregistrationsummary' -Id $TenantID -Name 'MFA registration summary' -Inputs @('entra/users', 'entra/authenticationmethodregistrations') -Properties ([ordered]@{
                    enabledUserCount = $enabledUsers.Count
                    enabledMfaRegisteredCount = $enabledRegistered.Count
                    enabledMfaRegisteredPercent = if ($enabledUsers.Count -gt 0) { [math]::Round(100 * $enabledRegistered.Count / $enabledUsers.Count, 2) } else { $null }
                    adminCount = $adminRegistrations.Count
                    adminMfaRegisteredCount = $adminRegistered.Count
                    adminMfaRegisteredPercent = if ($adminRegistrations.Count -gt 0) { [math]::Round(100 * $adminRegistered.Count / $adminRegistrations.Count, 2) } else { $null }
                    phishingResistantRegisteredCount = $phishingResistant.Count
                })))
    }

    $privilegedRows = [System.Collections.Generic.List[object]]::new()
    foreach ($set in @(
            [pscustomobject]@{ Rows = $activeSchedules; AssignmentType = 'Active' },
            [pscustomobject]@{ Rows = $eligibleSchedules; AssignmentType = 'Eligible' }
        )) {
        foreach ($assignment in @($set.Rows)) {
            $p = $assignment.properties
            $principalId = [string](Get-Value $p 'principalId')
            $principal = if ($principalById.ContainsKey($principalId)) { $principalById[$principalId] } else { $null }
            $roleDefinition = Get-Value $p 'roleDefinition'
            $end = Get-Value $p 'endDateTime'
            $effectiveType = if ($set.AssignmentType -eq 'Eligible') { 'Eligible' }
                             elseif ($null -eq $end -or [string]::IsNullOrWhiteSpace([string]$end)) { 'Permanent' }
                             else { 'Active time-bound' }
            $lastSignIn = @($signIns | Where-Object { [string](Get-Value $_.properties 'userId') -eq $principalId } | Sort-Object {
                    $date = Get-Value $_.properties 'createdDateTime'
                    if ($date) { [datetime]$date } else { [datetime]::MinValue }
                } -Descending | Select-Object -First 1)
            $lastDate = if ($lastSignIn.Count -gt 0) { Get-Value $lastSignIn[0].properties 'createdDateTime' } else { $null }
            $principalType = if ($principal) { [string]$principal.TYPE -replace '^entra/', '' } else { [string](Get-Value $p 'principalType') }
            $privilegedRow = New-DerivedRow -Type 'entra/privilegedassignments' -Id ([string](Get-Value $p 'id')) -Name ([string](Get-Value $roleDefinition 'displayName')) -Inputs @('entra/roleassignmentschedules', 'entra/roleeligibilityschedules', 'entra/users', 'entra/groups', 'entra/serviceprincipals', 'entra/signins') -Properties ([ordered]@{
                        roleName = Get-Value $roleDefinition 'displayName'
                        roleDefinitionId = Get-Value $p 'roleDefinitionId'
                        principalId = $principalId
                        principalType = $principalType
                        principalName = if ($principal) { $principal.name } else { $null }
                        assignmentType = $effectiveType
                        membership = if ($principalType -match '(?i)group') { 'Group' } else { [string](Get-Value $p 'memberType') }
                        startDateTime = Get-Value $p 'startDateTime'
                        endDateTime = $end
                        accountEnabled = if ($principal) { Get-Value $principal.properties 'accountEnabled' } else { $null }
                        lastSignInDateTime = $lastDate
                        stalePermanent90Days = $effectiveType -eq 'Permanent' -and ($null -eq $lastDate -or [datetime]$lastDate -lt (Get-Date).ToUniversalTime().AddDays(-90))
                    })
            $rows.Add($privilegedRow)
            $privilegedRows.Add($privilegedRow)
        }
    }
    foreach ($roleGroup in @($privilegedRows | Group-Object { [string]$_.properties.roleName })) {
        $rows.Add((New-DerivedRow -Type 'entra/privilegedassignmentsummary' -Id ([string]$roleGroup.Name) -Name ([string]$roleGroup.Name) -Inputs @('entra/privilegedassignments') -Properties ([ordered]@{
                    roleName = $roleGroup.Name
                    permanentCount = @($roleGroup.Group | Where-Object { $_.properties.assignmentType -eq 'Permanent' }).Count
                    eligibleCount = @($roleGroup.Group | Where-Object { $_.properties.assignmentType -eq 'Eligible' }).Count
                    activeTimeBoundCount = @($roleGroup.Group | Where-Object { $_.properties.assignmentType -eq 'Active time-bound' }).Count
                    stalePermanent90DaysCount = @($roleGroup.Group | Where-Object { $_.properties.stalePermanent90Days -eq $true }).Count
                })))
    }

    $enabledPolicies = @($policies | Where-Object { (Get-Value $_.properties 'state') -eq 'enabled' })
    if ($enabledPolicies.Count -gt 0) {
        $excludedSets = @()
        foreach ($policy in $enabledPolicies) {
            $conditions = Get-Value $policy.properties 'conditions'
            $userCondition = Get-Value $conditions 'users'
            $excludedSets += ,@((Get-Value $userCondition 'excludeUsers') | Where-Object { $_ -and $_ -notin @('GuestsOrExternalUsers', 'All') })
        }
        $directCandidates = if ($excludedSets.Count -gt 0) {
            @($excludedSets[0] | Where-Object {
                    $candidate = [string]$_
                    @($excludedSets | Where-Object { $_ -notcontains $candidate }).Count -eq 0
                } | Sort-Object -Unique)
        }
        else { @() }

        foreach ($principalId in $directCandidates) {
            if (-not $principalById.ContainsKey([string]$principalId)) { continue }
            $user = $principalById[[string]$principalId]
            if ($user.TYPE -ne 'entra/users') { continue }
            $registration = if ($registrationById.ContainsKey([string]$principalId)) { $registrationById[[string]$principalId] } else { $null }
            $userSignIns = @($signIns | Where-Object { [string](Get-Value $_.properties 'userId') -eq [string]$principalId } | Sort-Object {
                    $date = Get-Value $_.properties 'createdDateTime'
                    if ($date) { [datetime]$date } else { [datetime]::MinValue }
                } -Descending)
            $assignedRoles = @($legacyAssignments | Where-Object { [string](Get-Value $_.properties 'principalId') -eq [string]$principalId } | ForEach-Object { Get-Value (Get-Value $_.properties 'roleDefinition') 'displayName' } | Where-Object { $_ } | Sort-Object -Unique)
            $rows.Add((New-DerivedRow -Type 'entra/breakglasscandidates' -Id ([string]$principalId) -Name (Mask-Upn ([string]$user.name)) -Inputs @('entra/conditionalaccesspolicies', 'entra/users', 'entra/authenticationmethodregistrations', 'entra/signins', 'entra/pimassignments') -Properties ([ordered]@{
                        maskedUserPrincipalName = Mask-Upn ([string]$user.name)
                        cloudOnly = -not [bool](Get-Value $user.properties 'onPremisesSyncEnabled')
                        accountEnabled = Get-Value $user.properties 'accountEnabled'
                        lastSignInDateTime = if ($userSignIns.Count -gt 0) { Get-Value $userSignIns[0].properties 'createdDateTime' } else { $null }
                        isMfaRegistered = if ($registration) { Get-Value $registration.properties 'isMfaRegistered' } else { $null }
                        methodsRegistered = if ($registration) { @(Get-Value $registration.properties 'methodsRegistered') } else { @() }
                        assignedRoles = $assignedRoles
                        excludedFromEnabledPolicyCount = $enabledPolicies.Count
                        evidenceScope = 'Direct user exclusions only; group and directory-role exclusions are not inferred.'
                    })))
        }
    }

    return $rows.ToArray()
}
