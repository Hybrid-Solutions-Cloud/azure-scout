#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    The Microsoft Graph queries Scout issues, and the permission each one needs.

.DESCRIPTION
    Single source of truth for the Entra half of collection. `Start-ScoutEntraExtraction` runs
    these queries; `Get-ScoutGraphPermissionImpact` joins them to the collector manifests so the
    pre-flight can say which collectors a denied permission will empty.

    Extracted into its own function for AB#6765. It used to be a literal inside the extraction
    loop, which meant the pre-flight had to keep a second, hand-maintained list of what mattered
    -- and that list was a hardcoded four entries, so a denied permission outside those four
    still printed "READY — Full ARM + Entra ID scan supported" while its worksheet rendered
    empty. One table, read by both, cannot drift.

    `Type` is the synthetic TYPE stamped on each normalised row, and it is the join key: a
    collector manifest declaring `ResourceTypes = @('entra/users')` consumes the Users query.

.OUTPUTS
    An ordered array of hashtables: Name, Uri, Type, NameProperty, Permission, and optionally
    SingleObject.

.NOTES
    Tracks ADO AB#6765 (Feature AB#6743, Epic AB#6731). Permissions are the delegated/application
    Graph scopes from the audit's Table B — docs/audits/AZURE-SCOUT-AUDIT.md section 9.
#>
function Get-ScoutEntraQueryCatalog {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # No unary comma: the catalog is never empty, so the usual "preserve an empty array" idiom
    # would only wrap seventeen hashtables inside one object and make every caller's @() count
    # read 1.
    @(
        @{
            Name         = 'Users'
            Uri          = '/v1.0/users?$select=id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime,assignedLicenses,onPremisesSyncEnabled,department,jobTitle,mail,lastPasswordChangeDateTime'
            Type         = 'entra/users'
            NameProperty = 'userPrincipalName'
            Permission   = 'User.Read.All'
        },
        @{
            Name         = 'Groups'
            Uri          = '/v1.0/groups?$select=id,displayName,groupTypes,securityEnabled,mailEnabled,isAssignableToRole,membershipRule,onPremisesSyncEnabled,description'
            Type         = 'entra/groups'
            NameProperty = 'displayName'
            Permission   = 'Group.Read.All'
        },
        @{
            Name         = 'Applications'
            Uri          = '/v1.0/applications?$select=id,displayName,appId,signInAudience,keyCredentials,passwordCredentials,requiredResourceAccess,publisherDomain,createdDateTime'
            Type         = 'entra/applications'
            NameProperty = 'displayName'
            Permission   = 'Application.Read.All'
        },
        @{
            Name         = 'Service Principals'
            Uri          = '/v1.0/servicePrincipals?$select=id,displayName,appId,servicePrincipalType,accountEnabled,appOwnerOrganizationId,keyCredentials,passwordCredentials,tags'
            Type         = 'entra/serviceprincipals'
            NameProperty = 'displayName'
            Permission   = 'Application.Read.All'
        },
        @{
            Name         = 'Managed Identities'
            Uri          = '/v1.0/servicePrincipals?$filter=servicePrincipalType eq ''ManagedIdentity''&$select=id,displayName,appId,servicePrincipalType,alternativeNames'
            Type         = 'entra/managedidentities'
            NameProperty = 'displayName'
            Permission   = 'Application.Read.All'
        },
        @{
            Name         = 'Directory Roles'
            Uri          = '/v1.0/directoryRoles?$select=id,displayName,roleTemplateId,description'
            Type         = 'entra/directoryroles'
            NameProperty = 'displayName'
            Permission   = 'RoleManagement.Read.Directory'
        },
        @{
            Name         = 'PIM Assignments'
            Uri          = '/v1.0/roleManagement/directory/roleAssignments?$expand=principal($select=id,displayName),roleDefinition($select=id,displayName)'
            Type         = 'entra/pimassignments'
            NameProperty = 'principalId'
            Permission   = 'RoleManagement.Read.Directory'
        },
        @{
            Name         = 'Conditional Access Policies'
            Uri          = '/v1.0/identity/conditionalAccess/policies'
            Type         = 'entra/conditionalaccesspolicies'
            NameProperty = 'displayName'
            Permission   = 'Policy.Read.All'
        },
        @{
            Name         = 'Named Locations'
            Uri          = '/v1.0/identity/conditionalAccess/namedLocations'
            Type         = 'entra/namedlocations'
            NameProperty = 'displayName'
            Permission   = 'Policy.Read.All'
        },
        @{
            Name         = 'Administrative Units'
            Uri          = '/v1.0/directory/administrativeUnits?$select=id,displayName,description,membershipType,membershipRule'
            Type         = 'entra/administrativeunits'
            NameProperty = 'displayName'
            Permission   = 'AdministrativeUnit.Read.All'
        },
        @{
            Name         = 'Domains'
            Uri          = '/v1.0/domains'
            Type         = 'entra/domains'
            NameProperty = 'id'
            Permission   = 'Domain.Read.All'
        },
        @{
            Name         = 'Subscribed SKUs'
            Uri          = '/v1.0/subscribedSkus'
            Type         = 'entra/subscribedskus'
            NameProperty = 'skuPartNumber'
            Permission   = 'Organization.Read.All'
        },
        @{
            Name         = 'Cross-Tenant Access'
            Uri          = '/v1.0/policies/crossTenantAccessPolicy/partners'
            Type         = 'entra/crosstenantaccess'
            NameProperty = 'tenantId'
            Permission   = 'Policy.Read.All'
        },
        @{
            # AB#7098 -- Microsoft Entra External ID, the second named Identity gap
            # (docs/reference/service-coverage-gap.md). This is the tenant-wide DEFAULT
            # cross-tenant access configuration -- b2b collaboration/direct connect and inbound
            # trust settings applied to every external organization NOT covered by a specific
            # 'Cross-Tenant Access' (above) partner override. GA in v1.0, distinct from both the
            # partner list above and 'Security Policies' (authorizationPolicy) below, and
            # currently uncollected: this is the actual "is our tenant open to external/guest
            # identities by default" surface, not a narrower per-partner or per-invite setting.
            # `/v1.0/policies/externalIdentitiesPolicy` (the self-service tenant-leave toggle)
            # was considered and rejected -- it is /beta-only and does not carry the B2B/guest
            # access posture this Story's owner named as the reason this item matters.
            Name         = 'External Identities'
            Uri          = '/v1.0/policies/crossTenantAccessPolicy/default'
            Type         = 'entra/externalidentities'
            NameProperty = 'isServiceDefault'
            SingleObject = $true
            Permission   = 'Policy.Read.All'
        },
        @{
            Name         = 'Security Policies'
            Uri          = '/v1.0/policies/authorizationPolicy'
            Type         = 'entra/securitypolicies'
            NameProperty = 'displayName'
            SingleObject = $true
            Permission   = 'Policy.Read.All'
        },
        @{
            Name         = 'Risky Users'
            Uri          = '/v1.0/identityProtection/riskyUsers'
            Type         = 'entra/riskyusers'
            NameProperty = 'userPrincipalName'
            Permission   = 'IdentityRiskyUser.Read.All'
        },
        @{
            # AB#7097. The tenant-wide toggle for Verified ID as an authentication method --
            # whether it is enabled, and which groups are in/out of scope. This is genuinely
            # under graph.microsoft.com (Invoke-AZSCGraphRequest's fixed base URL and single
            # Graph-audience token both hold), unlike the Verified ID Admin API (issuer DIDs,
            # authorities, contracts), which is served from a DIFFERENT host
            # (verifiedid.did.msidentity.com) under a DIFFERENT OAuth resource
            # (6a8b4b39-c021-437c-b060-5a14a3fd65f3) that this codebase's Graph token helper does
            # not acquire. Reaching that surface needs a second token audience threaded through
            # every entra/* collector's shared infrastructure -- out of scope for one collector.
            Name         = 'Verified ID Authentication Method'
            Uri          = '/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/VerifiableCredentials'
            Type         = 'entra/verifiedidconfiguration'
            NameProperty = 'id'
            SingleObject = $true
            Permission   = 'Policy.Read.AuthenticationMethod'
        },
        @{
            # AB#7097. Verified ID profiles (recovery / onboarding usage, Face Check config,
            # accepted issuer) -- the tenant-configured objects a Verified ID deployment actually
            # produces via the Entra admin center, GA under graph.microsoft.com. See the note
            # above the authentication-method entry for the admin-API (DID/authority) surface
            # this catalog deliberately does not reach.
            Name         = 'Verified ID Profiles'
            Uri          = '/v1.0/identity/verifiedId/profiles'
            Type         = 'entra/verifiedidprofiles'
            NameProperty = 'name'
            Permission   = 'VerifiedId-Profile.Read.All'
        },
        @{
            # No collector consumes this. It is kept in the catalog rather than deleted so the
            # impact table can say so out loud -- an unconsumed query is a permission Scout asks
            # for and does not need, and that belongs in the report, not in a comment.
            Name         = 'Identity Providers'
            Uri          = '/v1.0/identity/identityProviders'
            Type         = 'entra/identityproviders'
            NameProperty = 'displayName'
            Permission   = 'IdentityProvider.Read.All'
        },
        @{
            # Same: queried, normalised, and read by nothing.
            Name         = 'Security Defaults'
            Uri          = '/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
            Type         = 'entra/securitydefaults'
            NameProperty = 'displayName'
            SingleObject = $true
            Permission   = 'Policy.Read.All'
        }
    )
}
