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

            # The tenant-root probe used `-Expand -Recurse`, which builds the whole hierarchy: 65 s
            # on a live tenant before collection could start. It also returned ONE object (the root,
            # with the tree nested inside it), so the "N visible" count always said 1. Reading the
            # root alone proves the same access in about a second; the flat descendants list
            # (same permission, about a second) gives the real number of management groups.
            $ManagementGroups = @(
                if ([string]::IsNullOrWhiteSpace($TenantID)) {
                    Get-AzManagementGroup -ErrorAction Stop
                }
                else {
                    Get-AzManagementGroup -GroupId $TenantID -ErrorAction Stop
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

            $visibleCount = $ManagementGroups.Count
            if (-not [string]::IsNullOrWhiteSpace($TenantID) -and (Get-Command Invoke-AzRestMethod -ErrorAction SilentlyContinue)) {
                try {
                    $descendantGroups = 0
                    $path = "/providers/Microsoft.Management/managementGroups/$TenantID/descendants?api-version=2020-05-01"
                    while (-not [string]::IsNullOrWhiteSpace($path)) {
                        $response = Invoke-AzRestMethod -Path $path -Method GET -ErrorAction Stop
                        if ($null -eq $response -or [int]$response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)" }
                        $page = $response.Content | ConvertFrom-Json
                        $descendantGroups += @($page.value | Where-Object { [string]$_.type -match '(?i)/managementGroups$' }).Count
                        $path = if ($page.PSObject.Properties['nextLink'] -and $page.nextLink) { [string]$page.nextLink -replace '^https://[^/]+', '' } else { $null }
                    }
                    $visibleCount = 1 + $descendantGroups
                }
                catch {
                    # The count is informational; the root read above already proved access.
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Management group descendant count unavailable: '+$_.Exception.Message)
                }
            }

            return [PSCustomObject]@{
                HasAccess = $true
                Count     = $visibleCount
                Message   = 'Management groups : ' + $visibleCount + ' visible'
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
