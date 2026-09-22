#Requires -Version 7.0
<#
.SYNOPSIS
    Sets Azure DevOps work-item states (and optionally adds a comment) for the Scout board.

.DESCRIPTION
    Board state changes used to be made from throwaway scripts in a scratch directory, which
    meant the writes actually applied to the board were not reviewable, not re-runnable, and not
    subject to the repo's standards. This script exists so every board write is committed code,
    alongside scripts/Test-BoardConformance.ps1.

    ALWAYS run scripts/Test-BoardConformance.ps1 afterwards. Skipping it once left 15 violations
    on the board.

    Traps this script encodes so callers do not rediscover them:

    - A work item cannot be CREATED in Resolved or Closed, and some types refuse a direct
      New -> Closed jump. The state walk (Active -> Resolved -> Closed) handles that.
    - PATCH needs Content-Type application/json-patch+json; comments need application/json and
      the 7.0-preview.3 API version.
    - System.Tags with op=add APPENDS rather than replaces. This script does not write tags; if
      you add that, use op=replace and send the complete semicolon-joined string.
    - An ordered dictionary with integer keys indexes by POSITION, not key -- iterate with
      .GetEnumerator(), never $plan[$id].

.PARAMETER State
    Hashtable mapping work-item id to target state, e.g. @{ 5648 = 'Active'; 5642 = 'Closed' }.

.PARAMETER Comment
    Optional hashtable mapping work-item id to a comment string to post after the state change.

.PARAMETER WhatIf
    Show what would be written without calling the API.

.EXAMPLE
    ./scripts/Set-BoardState.ps1 -State @{ 5648 = 'Active'; 5642 = 'Closed' }

.EXAMPLE
    ./scripts/Set-BoardState.ps1 -State @{ 5659 = 'Active' } -Comment @{ 5659 = 'Released in v2.9.0; 124 of 176 converted.' }

.NOTES
    Requires an authenticated Azure CLI session (az login). Reads no secrets from the repo.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [hashtable] $State,

    [hashtable] $Comment = @{},

    [string] $Organization = 'hybridcloudsolutions',

    # Scout project GUID. Using the GUID avoids the U+2014 em-dash in the project name, which
    # console encoding mangles into TF401347 Invalid tree name.
    [string] $ProjectId = '85b6e47e-a666-4a38-8c43-de87dd21aa56'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 499b84ac-1321-427f-aa17-267ca6975798 is the well-known Azure DevOps resource id.
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
if (-not $token) { throw 'Could not get an Azure DevOps access token. Run: az login' }

$patchHeaders   = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json-patch+json' }
$commentHeaders = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

function Set-WorkItemState {
    param([int] $Id, [string] $TargetState, [string] $Organization, [string] $ProjectId)

    $uri  = 'https://dev.azure.com/{0}/{1}/_apis/wit/workitems/{2}?api-version=7.0' -f $Organization, $ProjectId, $Id
    $body = ConvertTo-Json @(@{ op = 'add'; path = '/fields/System.State'; value = $TargetState }) -Depth 5
    try {
        Invoke-RestMethod -Uri $uri -Method PATCH -Headers $patchHeaders -Body $body -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Verbose "PATCH $Id -> $TargetState failed: $($_.Exception.Message)"
        return $false
    }
}

function Add-WorkItemComment {
    param([int] $Id, [string] $Text, [string] $Organization, [string] $ProjectId)

    $uri  = 'https://dev.azure.com/{0}/{1}/_apis/wit/workItems/{2}/comments?api-version=7.0-preview.3' -f $Organization, $ProjectId, $Id
    $body = @{ text = $Text } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $uri -Method POST -Headers $commentHeaders -Body $body -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Verbose "Comment on $Id failed: $($_.Exception.Message)"
        return $false
    }
}

$failed = 0

foreach ($entry in $State.GetEnumerator()) {
    $id     = [int] $entry.Key
    $target = [string] $entry.Value

    if (-not $PSCmdlet.ShouldProcess("work item $id", "set state to $target")) { continue }

    $ok = Set-WorkItemState -Id $id -TargetState $target -Organization $Organization -ProjectId $ProjectId

    if (-not $ok -and $target -eq 'Closed') {
        # Some work-item types refuse a direct New -> Closed transition.
        Set-WorkItemState -Id $id -TargetState 'Active'   -Organization $Organization -ProjectId $ProjectId | Out-Null
        Set-WorkItemState -Id $id -TargetState 'Resolved' -Organization $Organization -ProjectId $ProjectId | Out-Null
        $ok = Set-WorkItemState -Id $id -TargetState 'Closed' -Organization $Organization -ProjectId $ProjectId
    }

    if (-not $ok) { $failed++ }
    '{0} -> {1} : {2}' -f $id, $target, $(if ($ok) { 'OK' } else { 'FAILED' })
}

foreach ($entry in $Comment.GetEnumerator()) {
    $id   = [int] $entry.Key
    $text = [string] $entry.Value

    if (-not $PSCmdlet.ShouldProcess("work item $id", 'add comment')) { continue }

    $ok = Add-WorkItemComment -Id $id -Text $text -Organization $Organization -ProjectId $ProjectId
    if (-not $ok) { $failed++ }
    'comment {0} : {1}' -f $id, $(if ($ok) { 'OK' } else { 'FAILED' })
}

if ($failed -gt 0) {
    Write-Warning "$failed board write(s) failed."
}

Write-Host ''
Write-Host 'Now run: ./scripts/Test-BoardConformance.ps1' -ForegroundColor Yellow

exit ([int]($failed -gt 0))
