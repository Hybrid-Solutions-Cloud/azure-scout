#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Shape the Entra directory role assignments (and, when they were read, the PIM eligibility
    schedules) the inventory pass already collected into `domains.identity.directoryRoles`.

.DESCRIPTION
    Who holds Global Administrator or Privileged Role Administrator decides who can change
    Conditional Access and every other Entra control that governs access to Azure. Scout read those
    assignments (`entra/pimassignments`, which despite its name is the directory role ASSIGNMENT
    list) into `entraResources` during the inventory pass; no assessment could see them.

    This function makes NO Graph call. The rows exist only when the inventory pass ran Entra, and
    `Collected` is $false with a `Reason` otherwise. Eligibility
    (`entra/roleeligibilityschedules`) needs the delegated scope RoleEligibilitySchedule.Read.Directory,
    which the cached sign-in Scout normally runs under does not carry, so on most runs
    `eligibilityCollected` is $false and `eligibility` is empty -- that is a statement that it was
    NOT read, never that nobody is eligible.

    `principalType` is looked up from the user, group and service principal rows of the same pass
    (an id found in none of them -- or no such rows -- reads $null). No display name, user principal
    name or mail address is kept: ids and the role's own name only.

.PARAMETER EntraResources
    The `entraResources` rows of an inventory pass, or $null.

.PARAMETER EntraQueryOutcomes
    The inventory pass's per-query outcomes (Type, Status, Reason), or $null.

.OUTPUTS
    One [pscustomobject], never $null: Collected, Reason, assignments[], eligibilityCollected,
    eligibilityReason, eligibility[].
#>
function Get-ScoutDirectoryRolePosture {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [object[]] $EntraResources,
        [AllowNull()] [object[]] $EntraQueryOutcomes
    )

    function Get-ScoutDrValue {
        param($InputObject, [string[]] $Path)
        $cursor = $InputObject
        foreach ($segment in $Path) {
            if ($null -eq $cursor) { return $null }
            if ($cursor -is [System.Collections.IDictionary]) {
                $hit = $null
                foreach ($key in $cursor.Keys) { if ([string]$key -ieq $segment) { $hit = $key; break } }
                if ($null -eq $hit) { return $null }
                $cursor = $cursor[$hit]
                continue
            }
            $property = $cursor.PSObject.Properties[$segment]
            if ($null -eq $property) { return $null }
            $cursor = $property.Value
        }
        return $cursor
    }

    function New-ScoutDrResult {
        param([bool] $Collected, [string] $Reason, [object[]] $Assignments, [bool] $EligibilityCollected,
            [string] $EligibilityReason, [object[]] $Eligibility)
        [pscustomobject][ordered]@{
            Collected            = $Collected
            Reason               = if ($Collected) { $null } else { $Reason }
            assignments          = @($Assignments)
            eligibilityCollected = $EligibilityCollected
            eligibilityReason    = if ($EligibilityCollected) { $null } else { $EligibilityReason }
            eligibility          = @($Eligibility)
        }
    }

    try {
        $rows = @($EntraResources | Where-Object { $null -ne $_ })
        $outcomes = @($EntraQueryOutcomes | Where-Object { $null -ne $_ })

        function Get-ScoutDrSlice {
            param([string] $Type)
            $typed = @($rows | Where-Object {
                    $rowType = if ($_.PSObject.Properties['TYPE']) { $_.TYPE } elseif ($_.PSObject.Properties['type']) { $_.type } else { $null }
                    [string]$rowType -ieq $Type
                })
            $outcome = @($outcomes | Where-Object { $_.PSObject.Properties['Type'] -and [string]$_.Type -ieq $Type }) | Select-Object -Last 1
            $status = if ($outcome -and $outcome.PSObject.Properties['Status']) { [string]$outcome.Status } else { $null }
            $reason = if ($outcome -and $outcome.PSObject.Properties['Reason'] -and $outcome.Reason) { [string]$outcome.Reason } else { $null }
            [pscustomobject]@{
                Rows     = @($typed | ForEach-Object {
                        if ($_.PSObject.Properties['properties']) { $_.properties } elseif ($_.PSObject.Properties['PROPERTIES']) { $_.PROPERTIES } else { $null }
                    } | Where-Object { $null -ne $_ })
                Answered = (($typed.Count -gt 0) -or ($status -in @('Success', 'Empty')))
                Status   = $status
                Reason   = $reason
            }
        }

        $assignmentSlice = Get-ScoutDrSlice -Type 'entra/pimassignments'
        if (-not $assignmentSlice.Answered) {
            $why = if ($assignmentSlice.Status) {
                "The Entra inventory pass reported $($assignmentSlice.Status) for directory role assignments$(if ($assignmentSlice.Reason) { ': ' + ($assignmentSlice.Reason -replace '\s+', ' ') })."
            }
            else { 'The Entra inventory pass did not run, so directory role assignments were not read.' }
            return New-ScoutDrResult -Collected $false -Reason $why -Assignments @() -EligibilityCollected $false `
                -EligibilityReason 'Directory role assignments were not read, so eligibility was not either.' -Eligibility @()
        }

        # principalId -> 'User' | 'Group' | 'ServicePrincipal', from rows this pass already holds.
        $principalTypes = @{}
        foreach ($pair in @(@('entra/users', 'User'), @('entra/groups', 'Group'), @('entra/serviceprincipals', 'ServicePrincipal'))) {
            foreach ($principal in @((Get-ScoutDrSlice -Type $pair[0]).Rows)) {
                $principalId = [string](Get-ScoutDrValue $principal @('id'))
                if ($principalId -and -not $principalTypes.ContainsKey($principalId)) { $principalTypes[$principalId] = $pair[1] }
            }
        }

        function ConvertTo-ScoutDrRow {
            param($Row, [bool] $Schedule)
            $principalId = [string](Get-ScoutDrValue $Row @('principalId'))
            $out = [ordered]@{
                principalId      = $principalId
                principalType    = if ($principalId -and $principalTypes.ContainsKey($principalId)) { $principalTypes[$principalId] } else { $null }
                roleDefinitionId = [string](Get-ScoutDrValue $Row @('roleDefinitionId'))
                roleName         = [string](Get-ScoutDrValue $Row @('roleDefinition', 'displayName'))
                directoryScopeId = [string](Get-ScoutDrValue $Row @('directoryScopeId'))
            }
            if ($Schedule) {
                $out['status'] = [string](Get-ScoutDrValue $Row @('status'))
                $out['memberType'] = [string](Get-ScoutDrValue $Row @('memberType'))
                $end = Get-ScoutDrValue $Row @('scheduleInfo', 'expiration', 'endDateTime')
                $out['endDateTime'] = if ($null -eq $end) { $null } else { [string]$end }
            }
            [pscustomobject]$out
        }

        $assignments = @($assignmentSlice.Rows | ForEach-Object { ConvertTo-ScoutDrRow -Row $_ -Schedule $false })

        $eligibilitySlice = Get-ScoutDrSlice -Type 'entra/roleeligibilityschedules'
        if ($eligibilitySlice.Answered) {
            $eligibility = @($eligibilitySlice.Rows | ForEach-Object { ConvertTo-ScoutDrRow -Row $_ -Schedule $true })
            return New-ScoutDrResult -Collected $true -Reason $null -Assignments $assignments -EligibilityCollected $true `
                -EligibilityReason $null -Eligibility $eligibility
        }
        $eligibilityWhy = if ($eligibilitySlice.Status) {
            "The Entra inventory pass reported $($eligibilitySlice.Status) for directory role eligibility schedules$(if ($eligibilitySlice.Reason) { ': ' + ($eligibilitySlice.Reason -replace '\s+', ' ') })."
        }
        else { 'The Entra inventory pass did not read directory role eligibility schedules.' }
        return New-ScoutDrResult -Collected $true -Reason $null -Assignments $assignments -EligibilityCollected $false `
            -EligibilityReason $eligibilityWhy -Eligibility @()
    }
    catch {
        return New-ScoutDrResult -Collected $false -Reason ("Directory role collection failed: $($_.Exception.Message)") -Assignments @() `
            -EligibilityCollected $false -EligibilityReason 'Directory role collection failed.' -Eligibility @()
    }
}
