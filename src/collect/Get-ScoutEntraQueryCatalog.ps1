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
