#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Collects the tenant's DEFAULT Microsoft Entra External ID / cross-tenant access
    configuration -- one Microsoft Graph call, no per-subscription loop.

.DESCRIPTION
    AB#7098 (Story AB#7071, Feature AB#7069, Epic AB#7099). Microsoft Entra External ID's
    governance-relevant surface is Graph-backed, not ARM/ARG-indexed, so it cannot be added to
    Invoke-Collect.ps1's KQL query pack the way an ordinary ARM resource type is (see that file's
    header -- `entra/*` Identity manifests are explicitly excluded from the ARG pass for exactly
    this reason). This mirrors the live-REST-call pattern Get-ScoutDefenderPlanSweep.ps1 already
    established: a small, self-contained collector Invoke-Collect.ps1 calls directly and folds
    into the canonical payload, alongside the ARG query results, rather than a second collection
    pipeline the React report never reads.

    Reads GET /v1.0/policies/crossTenantAccessPolicy/default (GA, Policy.Read.All) -- the
    tenant-wide DEFAULT that governs every external organization NOT covered by a specific
    partner override. This is deliberately the SAME Graph endpoint
    manifests/collectors/Identity/ExternalIdentities.psd1 declares (`entra/externalidentities`),
    read directly here rather than through the manifest/inventory pipeline: the inventory
    pipeline's Entra rows reach the Excel/PPTX export, not collect.json, and this Story's scope is
    the assessment collect / React payload specifically -- see Invoke-Collect.ps1's own doc
    comment on why `entra/*` types are excluded from that file's ARG pass.

    `/v1.0/policies/externalIdentitiesPolicy` (the self-service tenant-leave toggle) was
    considered and rejected as the target -- it is /beta-only and a single boolean, while the
    default cross-tenant access policy is GA and is the surface that actually governs whether B2B
    collaboration/direct connect is open by default and what inbound trust (MFA / compliant
    device / hybrid Azure AD join) this tenant extends to every unlisted external organization.

.OUTPUTS
    One [pscustomobject], NEVER $null -- callers get an honest `Collected = $false` on failure
    rather than a StrictMode throw on a missing key downstream. Fields: Collected,
    IsServiceDefault, B2BCollaborationInboundAccessType, B2BCollaborationOutboundAccessType,
    B2BDirectConnectInboundAccessType, B2BDirectConnectOutboundAccessType, InboundTrustMfa,
    InboundTrustCompliantDevice, InboundTrustHybridAzureADJoined, TenantRestrictionsAccessType.

.NOTES
    Tracks ADO AB#7098 (Story AB#7071, Feature AB#7069, Epic AB#7099).
#>
function Get-ScoutExternalIdentitiesPolicy {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantID
    )

    $notCollected = [pscustomobject]@{
        Collected                          = $false
        IsServiceDefault                   = $null
        B2BCollaborationInboundAccessType  = $null
        B2BCollaborationOutboundAccessType = $null
        B2BDirectConnectInboundAccessType  = $null
        B2BDirectConnectOutboundAccessType = $null
        InboundTrustMfa                    = $null
        InboundTrustCompliantDevice        = $null
        InboundTrustHybridAzureADJoined    = $null
        TenantRestrictionsAccessType       = $null
    }

    # SingleObject endpoint -- Invoke-AZSCGraphRequest returns the raw response object (no
    # '.value' wrapper) when the response carries no such property. -SinglePage is not strictly
    # required for a singleton response, but is set anyway so a future change to this endpoint's
    # shape can never accidentally start paginating a policy object.
    $result = Invoke-AZSCGraphRequest -Uri '/v1.0/policies/crossTenantAccessPolicy/default' -SinglePage -TenantID $TenantID

    if ($null -eq $result) { return $notCollected }

    [pscustomobject]@{
        Collected                          = $true
        IsServiceDefault                   = Get-AZSCSafeProperty -InputObject $result -Path 'isServiceDefault'
        B2BCollaborationInboundAccessType  = Get-AZSCSafeProperty -InputObject $result -Path 'b2bCollaborationInbound.applications.accessType'
        B2BCollaborationOutboundAccessType = Get-AZSCSafeProperty -InputObject $result -Path 'b2bCollaborationOutbound.applications.accessType'
        B2BDirectConnectInboundAccessType  = Get-AZSCSafeProperty -InputObject $result -Path 'b2bDirectConnectInbound.applications.accessType'
        B2BDirectConnectOutboundAccessType = Get-AZSCSafeProperty -InputObject $result -Path 'b2bDirectConnectOutbound.applications.accessType'
        InboundTrustMfa                    = Get-AZSCSafeProperty -InputObject $result -Path 'inboundTrust.isMfaAccepted'
        InboundTrustCompliantDevice        = Get-AZSCSafeProperty -InputObject $result -Path 'inboundTrust.isCompliantDeviceAccepted'
        InboundTrustHybridAzureADJoined    = Get-AZSCSafeProperty -InputObject $result -Path 'inboundTrust.isHybridAzureADJoinedDeviceAccepted'
        TenantRestrictionsAccessType       = Get-AZSCSafeProperty -InputObject $result -Path 'tenantRestrictions.usersAndGroups.accessType'
    }
}
