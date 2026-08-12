#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Probes tenant-level management group access immediately after login.

.DESCRIPTION
Subscription Reader is enough to inventory resources but not enough to read the
management group tree, and the failure surfaces much later as an empty Management Groups
worksheet with no explanation. This probe calls Get-AzManagementGroup right after login
so the gap is visible up front: the count goes in the login summary, and an authorization
failure prints the exact role to assign.

The probe never aborts the run. A tenant where the identity has no management group
access is a supported configuration — collection simply continues at subscription scope.

.OUTPUTS
PSCustomObject with HasAccess (bool), Count (int), and Message (string).

.EXAMPLE
$mg = Test-AZSCManagementGroupAccess
if ($mg.HasAccess) { "Found $($mg.Count) management groups" }

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Work item: AB#351
#>

function Test-AZSCManagementGroupAccess {
    [CmdletBinding()]
    Param(
        [string]$TenantID
    )

    try
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Probing management group access.')

            $ManagementGroups = @(
                if ([string]::IsNullOrWhiteSpace($TenantID)) {
                    Get-AzManagementGroup -ErrorAction Stop
                }
                else {
                    Get-AzManagementGroup -GroupId $TenantID -Expand -Recurse -ErrorAction Stop
                }
            )

            if (-not [string]::IsNullOrWhiteSpace($TenantID) -and $ManagementGroups.Count -eq 0) {
                return [PSCustomObject]@{
                    HasAccess   = $false
                    Count       = 0
                    Message     = 'Management groups : tenant root returned no data'
                    FailureKind = 'Unavailable'
                    ErrorMessage = "Tenant root management group '$TenantID' returned no data."
                }
            }

            return [PSCustomObject]@{
                HasAccess = $true
                Count     = $ManagementGroups.Count
                Message   = 'Management groups : ' + $ManagementGroups.Count + ' visible'
                FailureKind = $null
                ErrorMessage = $null
            }
        }
    catch
        {
            $ErrorText = $_.Exception.Message

            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Management group probe failed: '+$ErrorText)

            # An authorization failure is the actionable case — the identity authenticated
            # fine, it just has no tenant-root role. Anything else (throttling, a transient
            # ARM error) is not something the operator can fix by assigning a role, so it
            # stays a debug-level detail.
            if ($ErrorText -match 'AuthorizationFailed' -or $ErrorText -match 'does not have authorization' -or $ErrorText -match 'Forbidden')
                {
                    Write-Host "  Tip: Assign 'Management Group Reader' at tenant root to enable management group collection." -ForegroundColor Cyan
                }

            return [PSCustomObject]@{
                HasAccess = $false
                Count     = 0
                Message   = 'Management groups : none visible'
                FailureKind = if ($ErrorText -match 'AuthorizationFailed|does not have authorization|Forbidden') { 'Authorization' } else { 'Operational' }
                ErrorMessage = $ErrorText
            }
        }
}
