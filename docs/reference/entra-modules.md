---
description: Complete catalog of AzureScout Microsoft Entra ID inventory modules.
---

# Entra ID Inventory Modules

## Overview

AzureScout's live Entra query catalog contains **26 entries**: 24 collected datasets and two
disabled coverage records whose results no released collector consumes. It extracts tenant-wide
identity and access-management data via Microsoft Graph, then retains every query outcome in the
raw evidence ledger.

Run Entra-only extraction with:

```powershell
Invoke-AzureScout -Scope EntraOnly
```

## How Entra Extraction Works

The `Start-AZSCEntraExtraction` function calls `Invoke-AZSCGraphRequest` for each Entra module, which:

1. Authenticates via the Graph token obtained during login
2. Queries the relevant Microsoft Graph endpoint
3. Handles pagination (following `@odata.nextLink`)
4. Normalizes each result into a consistent resource shape:

```json
{
  "id": "...",
  "name": "Display Name",
  "TYPE": "microsoft.graph/users",
  "tenantId": "00000000-...",
  "properties": { }
}
```

## Module Catalog

`Get-ScoutEntraQueryCatalog` (`src/collect/Get-ScoutEntraQueryCatalog.ps1`) is the single source
of truth for these 26 catalog entries — `Start-AZSCEntraExtraction` runs every enabled entry, and the
`-PermissionAudit` impact table is built by joining the same list against the collector
manifests, so the two can no longer drift the way a hand-maintained second copy could.

| Module | Graph Endpoint | Permission | Description |
|--------|----------------|------------|-------------|
| Users | `/users` | `User.Read.All` | All user accounts (members and guests) |
| Groups | `/groups` | `Group.Read.All` | Security groups, Microsoft 365 groups, distribution lists |
| Applications | `/applications` | `Application.Read.All` | Application registrations (app IDs, credentials, API permissions) |
| Service Principals | `/servicePrincipals` | `Application.Read.All` | Enterprise applications and service principals |
| Managed Identities | `/servicePrincipals` (filtered to `servicePrincipalType eq 'ManagedIdentity'`) | `Application.Read.All` | Managed identities (system and user-assigned), as seen from the Entra service-principal object |
| Directory Roles | `/directoryRoles` | `RoleManagement.Read.Directory` | Activated directory roles and their members |
| PIM Assignments | `/roleManagement/directory/roleAssignments` | `RoleManagement.Read.Directory` | Privileged Identity Management (PIM) role assignments |
| Conditional Access Policies | `/identity/conditionalAccess/policies` | `Policy.Read.All` | Conditional Access policies |
| Authentication Method Registration Details | `/reports/authenticationMethods/userRegistrationDetails` | `Reports.Read.All` | Per-user MFA registration, capability, and registered methods |
| Sign-ins (last 30 days) | `/auditLogs/signIns` | `AuditLog.Read.All` | CA report-only impact, legacy authentication, and last-sign-in correlations |
| Directory Role Assignment Schedules | `/roleManagement/directory/roleAssignmentSchedules` | `RoleAssignmentSchedule.Read.Directory` | Active/permanent PIM schedules |
| Directory Role Eligibility Schedules | `/roleManagement/directory/roleEligibilitySchedules` | `RoleEligibilitySchedule.Read.Directory` | Eligible PIM schedules |
| Access Review Definitions | `/identityGovernance/accessReviews/definitions` | `AccessReview.Read.All` | Access-review definitions and instances |
| Organization | `/organization` | `Directory.Read.All` | Entra Connect sync state and last sync time |
| Named Locations | `/identity/conditionalAccess/namedLocations` | `Policy.Read.All` | Trusted locations for conditional access |
| Administrative Units | `/directory/administrativeUnits` | `AdministrativeUnit.Read.All` | Administrative units for delegated management |
| Domains | `/domains` | `Domain.Read.All` | Verified and unverified domains |
| Subscribed SKUs | `/subscribedSkus` | `Organization.Read.All` | License SKUs and service plan assignments |
| Cross-Tenant Access | `/policies/crossTenantAccessPolicy/partners` | `Policy.Read.All` | B2B cross-tenant access settings |
| External Identities | `/policies/crossTenantAccessPolicy/default` | `Policy.Read.All` | Default inbound/outbound B2B trust posture |
| Security Policies | `/policies/authorizationPolicy` | `Policy.Read.All` | Tenant authorization policy |
| Risky Users | `/identityProtection/riskyUsers` | `IdentityRiskyUser.Read.All` | Users flagged by Identity Protection (requires Entra ID P2) |
| Verified ID Authentication Method | `/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/VerifiableCredentials` | `Policy.Read.AuthenticationMethod` | Tenant Verified ID authentication-method state and target groups |
| Verified ID Profiles | `/identity/verifiedId/profiles` | `VerifiedId-Profile.Read.All` | Configured Verified ID profiles |
| Identity Providers ⚠️ | `/identity/identityProviders` | `IdentityProvider.Read.All` | Configured external/social identity providers |
| Security Defaults ⚠️ | `/policies/identitySecurityDefaultsEnforcementPolicy` | `Policy.Read.All` | Tenant-wide security defaults enforcement state |

::: warning ⚠️ Collected, normalized, and read by nothing
`Identity Providers` and `Security Defaults` remain in the catalog as disabled coverage records,
but Scout does not issue those two requests. The raw query-outcome ledger states that no released
collector consumes them. `AuditLog.Read.All`, by contrast, now has multiple released consumers and
is required for the last-30-day correlation datasets.
:::

## Required Microsoft Graph Permissions

> **"I'm a Global Administrator but the Entra modules still fail with 403 — why?"**
>
> **Global Administrator is an Entra directory *role*, not a Microsoft Graph API *scope*.**
> Entra extraction uses the Graph token issued for the **same Az context account and tenant**
> that ARM collection uses (`Get-AzAccessToken`). That token only carries the delegated
> Graph scopes issued to the authentication client — your directory role does **not** widen
> those OAuth scopes. So an endpoint whose
> scope has not been consented returns `403 Forbidden` regardless of your role.

To read every module above, the signed-in identity needs these **delegated** Microsoft
Graph permissions carried by the selected identity's token (or application permissions on
your own service principal) — see the Permission column in the [Module Catalog](#module-catalog) above for
which permission unlocks which module:

| Permission | Unlocks |
|---|---|
| `User.Read.All` | Users |
| `Group.Read.All` | Groups |
| `Application.Read.All` | Applications, Service Principals, Managed Identities |
| `RoleManagement.Read.Directory` | Directory Roles, PIM Assignments |
| `Policy.Read.All` | Conditional Access Policies, Named Locations, Security Policies, Cross-Tenant Access, Security Defaults ⚠️ |
| `Reports.Read.All` | Authentication Method Registration Details |
| `AuditLog.Read.All` | Sign-ins (last 30 days) |
| `RoleAssignmentSchedule.Read.Directory` | Directory Role Assignment Schedules |
| `RoleEligibilitySchedule.Read.Directory` | Directory Role Eligibility Schedules |
| `AccessReview.Read.All` | Access Review Definitions |
| `Directory.Read.All` | Organization / hybrid sync state |
| `AdministrativeUnit.Read.All` | Administrative Units |
| `Domain.Read.All` | Domains |
| `Organization.Read.All` | Subscribed SKUs |
| `IdentityRiskyUser.Read.All` | Risky Users (Identity Protection — also requires Entra ID P2) |
| `IdentityProvider.Read.All` ⚠️ | Identity Providers |
| `Policy.Read.AuthenticationMethod` | Verified ID Authentication Method |
| `VerifiedId-Profile.Read.All` | Verified ID Profiles |

⚠️ marks the two permissions behind the unconsumed queries — granting them satisfies the
pre-flight but adds nothing to any report; see the warning above.

A broad `Directory.Read.All` grant also satisfies `User.Read.All`, `Group.Read.All` and
`Application.Read.All` in practice, since it is a superset scope, but the table above is the
minimum each query actually needs.

Grant/consent once (tenant admin), e.g.:

```powershell
# Re-establish the Az context for the exact account and tenant being scanned:
Connect-AzAccount -Tenant '<tenant-id>'
# For scopes the delegated token cannot carry, use AzureScout's service-principal parameters
# with the required Microsoft Graph application permissions admin-consented in Entra ID.
```

Endpoints requiring a licensing tier you don't have (e.g. Risky Users without Entra ID P2)
will still 403 — that is expected and is handled by [Graceful Degradation](#graceful-degradation)
below rather than aborting the run.

## Data Normalization

All collected Entra datasets produce output in the same normalized shape:

| Field | Source |
|-------|--------|
| `id` | Graph object `id` |
| `name` | `displayName` (or most relevant name field) |
| `TYPE` | Synthetic type string (e.g., `microsoft.graph/users`) |
| `tenantId` | Tenant ID from the current session |
| `properties` | Full Graph object properties |

This normalization allows ARM and Entra resources to be processed by the same reporting pipeline.

## Graceful Degradation

If a single Entra query fails (e.g., insufficient permissions for Conditional Access policies), the module:

- Logs a warning
- Continues with the remaining enabled queries
- Returns partial results rather than failing entirely

If *all* queries fail, the function returns an empty `EntraResources` collection.
