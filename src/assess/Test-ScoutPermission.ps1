#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Verify the read-only access each selected assessment needs and emit remediation.

.NOTES
    Read-only throughout. Tracks ADO Story AB#5051.
#>
function Test-ScoutPermission {
    param([string[]] $Assessment, $Manifest)
    $results = @()

    # ARM: Reader at MG root
    $ctx = Get-AzContext
    $mgReader = Get-AzRoleAssignment -Scope "/providers/Microsoft.Management/managementGroups/$($ctx.Tenant.Id)" `
        -SignInName $ctx.Account.Id -ErrorAction SilentlyContinue |
        Where-Object RoleDefinitionName -eq 'Reader'
    $results += [pscustomobject]@{
        Check = 'ARM Reader @ MG root'; Ok = [bool]$mgReader
        Fix   = 'Assign Reader at the tenant root management group scope.'
    }

    # AB#7358. These assessments inspect key metadata collected by the Key Vault LIST operation.
    # Generic ARM Reader can see deployable child resources but not the complete object list.
    # Key Vault Reader supplies metadata list/read actions without secret-value or private-key
    # access. The live collector still records per-vault health because a root assignment is only
    # the recommended shape; customers may grant this role at individual vault scopes instead.
    $KeyVaultMetadataAssessments = @('Workload: AVS', 'Microsoft: CASA')
    if (@($Assessment | Where-Object { $_ -in $KeyVaultMetadataAssessments }).Count -gt 0) {
        $keyVaultReader = Get-AzRoleAssignment `
            -Scope "/providers/Microsoft.Management/managementGroups/$($ctx.Tenant.Id)" `
            -SignInName $ctx.Account.Id -ErrorAction SilentlyContinue |
            Where-Object RoleDefinitionName -eq 'Key Vault Reader'
        $results += [pscustomobject]@{
            Check = 'Key Vault Reader @ MG root'; Ok = [bool]$keyVaultReader
            Fix   = 'Assign metadata-only Key Vault Reader at the tenant root management group or on every Key Vault in assessment scope. This role cannot read secret values.'
        }
    }

    # Graph app permissions needed when ingesting the governance visualizer.
    # Two independent guards here: (1) $Manifest itself can be $null (a caller
    # that never loaded manifests/assessments.psd1) -- indexing $null[$_] throws
    # "Cannot index into a null array", not $null, so it must be checked before
    # the bracket lookup runs at all; (2) $Manifest[$_] is $null whenever $_ is
    # an assessment name that isn't actually a key in the manifest -- e.g. a
    # caller-supplied name never validated against the manifest -- and
    # `$null.Ingest` throws PropertyNotFoundException, not $null, under
    # Set-StrictMode -Version Latest, so guard the lookup before dotting into it.
    if ($Assessment | Where-Object { $def = if ($null -ne $Manifest) { $Manifest[$_] } else { $null }; $def -and (@($def.Ingest) -contains 'AzGovViz') }) {
        foreach ($p in 'User.Read.All', 'Group.Read.All', 'Application.Read.All', 'PrivilegedAccess.Read.AzureResources') {
            $results += [pscustomobject]@{
                Check = "Graph: $p"; Ok = $null
                Fix   = "Grant application permission $p with admin consent (or use Directory Readers)."
            }
        }
    }
    # Out-Host (not a bare, unassigned Format-Table call) -- an unassigned
    # Format-Table's format objects (FormatStartData/FormatEntryData/...) go
    # straight to the SUCCESS stream like any other pipeline output, which
    # silently prepended them onto this function's real return value below.
    # A caller that reads a named property off each returned item (e.g.
    # Invoke-ScoutPipeline.ps1's `$_.Check`) then throws
    # PropertyNotFoundException under Set-StrictMode -Version Latest the
    # moment it reaches one of those format objects -- this is the exact
    # crash a real caller hit in the permission-audit path. Out-Host renders
    # the same table for an interactive caller without adding anything to
    # the output stream.
    $results | Format-Table -AutoSize | Out-Host
    return $results
}
