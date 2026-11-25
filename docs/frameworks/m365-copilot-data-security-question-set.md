# Microsoft 365 Copilot data security — enumerated source for the Data Security for Copilot for Microsoft 365 assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `m365.copilot.datasecurity.yaml` is a readiness review of the data-security work that comes before and
alongside a Microsoft 365 Copilot deployment: finding and fixing oversharing, labelling and protecting data,
putting guardrails around Copilot, auditing its use and meeting AI regulations. It is Scout's counterpart to
Microsoft's [Data Security for Copilot for Microsoft 365](https://learn.microsoft.com/en-us/assessments/dde5dcfc-77d3-4f71-aa3f-cc98fa893e99/)
assessment. `src/assess/rules/m365.copilot.datasecurity.yaml` is written against this page only, and every rule
cites an item number from the tables below. Every item is a **manual** question answered with
`-AssessmentAnswers`, because Scout does not read Microsoft 365 data.

## Source

| Field | Value |
|---|---|
| Assessment | [Data Security for Copilot for Microsoft 365](https://learn.microsoft.com/en-us/assessments/dde5dcfc-77d3-4f71-aa3f-cc98fa893e99/) (question text not published) |
| Framework version | Microsoft 365 Copilot data security guidance on Microsoft Learn (secure-and-govern blueprint, Zero Trust for Copilot, SharePoint Advanced Management), current as of the extraction date; no published version number |
| Extraction date | 2026-11-25 |
| Verification method | Pages marked `fetched` in the source list were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Pages marked `search excerpt` were read through `microsoft_docs_search` excerpts on the same day, not in full. The Microsoft Graph and SharePoint interfaces named in the last section were checked against Learn reference pages the same day. No Microsoft 365 tenant was read. |

## Product status

Checked against Microsoft Learn on 2026-11-25.

- **Renamed, not retired.** The assessment still carries the old name "Copilot for Microsoft 365". Current Learn
  guidance calls the product Microsoft 365 Copilot, and the deployment blueprint and Purview DLP pages say Microsoft
  Copilot. The items apply to the product under its current name.
- **A feature in the guidance is retiring.** Restricted SharePoint Search is retiring: Learn states that from
  2026-07-31 new enablement is blocked, and points to Restricted Content Discovery for controlling discoverability.
  M365CP-RO-05 asks how an existing allow list is being retired.
- **Renamed DLP location.** The Purview DLP policy location that governs Copilot is titled "Microsoft Copilot,
  Copilot Chat, and Copilot Cowork" on current pages. M365CP-GR-01 to GR-03 use it. Learn's Purview service
  description lists the sensitivity-label condition (keep labelled files and emails out of Copilot) as included in
  Microsoft 365 E5 licensing and not in E3, and prompt protection as available to all Copilot users.
- **Current structure.** Microsoft's blueprint has three pillars: remediate oversharing, set up guardrails, meet
  regulations. The groups below follow it, with separate groups for sensitivity labels, audit and agents.

## The one thing this enumeration is NOT

**The questions are Scout-derived, not Microsoft's.** The assessment's question text is not published, so the items
below are Scout's reading of the guidance listed above. The `M365CP-*` IDs, and the assignment of an item to a
group, are Scout's own.

**Scout does not read this product's data yet.** Scout reads Azure (Resource Graph and ARM) and one Microsoft Entra
policy. It does not call Microsoft Graph for sensitivity labels, SharePoint or Purview, and the collect.json contract
in `src/collect/Invoke-Collect.ps1` holds no Conditional Access, label, sharing, audit or DLP data. The only
Graph-backed field, `domains.identity.externalIdentitiesPolicy`, answers none of these items. So every rule is
`manual: true` with `query: null`: it is exported as a question by `Export-ScoutAssessmentQuestion`, answered with
`-AssessmentAnswers` (see [Questionnaire Answers](../assessment/questionnaire-answers.md)), and stays Manual and out
of the score until answered. Items marked in the table as needing Entra data are the first that an automated version
could take over.

Sources:

- [BP] [Secure and govern Microsoft Copilot: Foundational deployment guidance (remediate oversharing, set up guardrails, meet regulations)](https://learn.microsoft.com/copilot/plan/secure-govern-copilot-foundational-deployment-guidance) -- fetched
- [ARCH] [Data protection and auditing for Microsoft Copilot](https://learn.microsoft.com/copilot/plan/architecture-data-protection-auditing) -- fetched
- [ZT] [Apply principles of Zero Trust to Microsoft Copilot](https://learn.microsoft.com/security/zero-trust/copilots/zero-trust-microsoft-365-copilot) -- fetched
- [SAM] [What is SharePoint Advanced Management?](https://learn.microsoft.com/sharepoint/advanced-management) -- fetched
- [SAMR] [Get ready for Microsoft Copilot and agents with SharePoint Advanced Management](https://learn.microsoft.com/sharepoint/get-ready-copilot-sharepoint-advanced-management) -- search excerpt
- [RCD] [Restrict discovery of SharePoint sites and content (Restricted Content Discovery)](https://learn.microsoft.com/sharepoint/restricted-content-discovery) -- search excerpt
- [RSS] [Restricted SharePoint Search (retiring)](https://learn.microsoft.com/sharepoint/restricted-sharepoint-search) -- search excerpt
- [DAG] [Manage Data access governance reports by using SharePoint Online PowerShell](https://learn.microsoft.com/sharepoint/powershell-for-data-access-governance) -- search excerpt
- [DLP] [Use Microsoft Purview Data Loss Prevention to protect interactions with Microsoft 365 Copilot, Copilot Chat, and Cowork](https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about) -- search excerpt
- [AGT] [Secure and govern Microsoft 365 Copilot agents (Purview deployment model, steps 1 to 4)](https://learn.microsoft.com/purview/deploymentmodels/depmod-sc-agents-deployment) -- fetched (overview and step 1)
- [SHADOW] [Step 3: Block sensitive data going to sanctioned AI apps (Purview deployment model)](https://learn.microsoft.com/purview/deploymentmodels/depmod-data-leak-shadow-ai-step3) -- search excerpt

Every item is **manual**: it is exported as a question and scored only when answered with `-AssessmentAnswers`
(see [Questionnaire Answers](../assessment/questionnaire-answers.md)).

## The enumeration — 40 items across 6 groups

### Remediate oversharing (M365CP-RO) — 11 items

| # | Item | Scout | Source |
|---|---|---|---|
| M365CP-RO-01 | Oversharing was assessed (Purview data risk assessment or equivalent) before Copilot licences were assigned | Manual | BP, ZT, AGT |
| M365CP-RO-02 | SharePoint data access governance reports are reviewed for broad exposure | Manual | SAM, DAG |
| M365CP-RO-03 | High-risk sites are identified from overlapping risk signals and each has a remediation owner | Manual | SAMR |
| M365CP-RO-04 | Restricted Content Discovery is applied to sites that need review before Copilot can surface them | Manual | RCD, SAMR |
| M365CP-RO-05 | Restricted SharePoint Search, if used, is temporary and has an exit plan (the feature is retiring) | Manual | RSS |
| M365CP-RO-06 | Site access reviews or attestations are run by site owners for overshared sites | Manual | SAM, SAMR |
| M365CP-RO-07 | Every site has owners, and inactive sites are detected and handled | Manual | SAM |
| M365CP-RO-08 | Restricted access control limits the most sensitive sites and OneDrive locations to named security groups | Manual | SAM, ARCH |
| M365CP-RO-09 | External sharing defaults and guest settings were reviewed when Copilot was introduced | Manual | ZT |
| M365CP-RO-10 | Teams and project sites are protected at baseline, sensitive or highly sensitive level | Manual | ZT |
| M365CP-RO-11 | Stale and low-value content is reduced so Copilot does not ground on it | Manual | AGT, ZT, SAM |

### Sensitivity labels and information protection (M365CP-SL) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| M365CP-SL-01 | A classification taxonomy exists and sensitivity labels are created and published to users | Manual | ZT, ARCH |
| M365CP-SL-02 | Sensitivity labels are enabled for Office files in SharePoint and OneDrive | Manual | ZT |
| M365CP-SL-03 | Default labelling and mandatory labelling are decided deliberately | Manual | ZT |
| M365CP-SL-04 | Container labels protect SharePoint sites and teams that hold sensitive data (Microsoft 365 E5 capability) | Manual | ZT |
| M365CP-SL-05 | Automatic labelling finds and labels sensitive content beyond what users label by hand (Microsoft 365 E5 capability) | Manual | ZT |
| M365CP-SL-06 | Encryption and usage rights are set with Copilot behaviour in mind (VIEW and EXTRACT) | Manual | ARCH |

### Guardrails: DLP, identity, devices and threat protection (M365CP-GR) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| M365CP-GR-01 | A DLP policy for the Copilot location keeps labelled files and emails out of Copilot processing | Manual | DLP |
| M365CP-GR-02 | A DLP policy blocks sensitive information types in prompts and is enforced, not left in simulation | Manual | DLP |
| M365CP-GR-03 | Sensitive prompts are prevented from being sent to external web search | Manual | DLP |
| M365CP-GR-04 | Insider risk management covers risky AI usage | Manual | AGT, SHADOW |
| M365CP-GR-05 | Conditional Access requires MFA for all users and administrators and blocks legacy authentication, including Microsoft 365 services | Manual -- Conditional Access policies are not in collect.json | ZT |
| M365CP-GR-06 | Risk-based access, Privileged Identity Management and access reviews are in place (Entra ID P2 capability) | Manual -- risk policies, PIM eligibility and access reviews are not in collect.json | ZT |
| M365CP-GR-07 | Devices are enrolled and compliant, and app protection policies cover Copilot-capable apps | Manual | ZT |
| M365CP-GR-08 | Threat protection for email, endpoints and identities is deployed and feeds a SIEM | Manual | ZT |
| M365CP-GR-09 | Endpoint and browser data protection limits sensitive data going to unsanctioned AI apps | Manual | SHADOW |

### Audit, retention and investigation (M365CP-AU) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| M365CP-AU-01 | Microsoft Purview Audit is on and Copilot interactions are being logged | Manual | AGT, ARCH |
| M365CP-AU-02 | Retention policies cover Copilot interactions | Manual | ARCH |
| M365CP-AU-03 | eDiscovery and Communication Compliance cover Copilot interaction data | Manual | ARCH, ZT |
| M365CP-AU-04 | Retention for cloud attachments preserves versions of files Copilot referenced | Manual | ARCH |
| M365CP-AU-05 | DSPM for AI recommendations are reviewed regularly, especially when users are added | Manual | ZT, AGT |

### Regulations and operating model (M365CP-RG) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| M365CP-RG-01 | Compliance Manager assessments cover the AI regulations that apply | Manual | BP, ZT, AGT |
| M365CP-RG-02 | Audit and legal requirements for AI interaction records are defined | Manual | BP |
| M365CP-RG-03 | Protections are rolled out in phases before Copilot licences are assigned to each group of users | Manual | ZT |
| M365CP-RG-04 | Owners and responsibilities are defined across SharePoint, Purview, identity and security teams | Manual | BP |
| M365CP-RG-05 | Users and site owners are trained on Copilot and on sharing responsibly | Manual | ZT |

### Agents (M365CP-AG) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| M365CP-AG-01 | The SharePoint and Dataverse content agents use as knowledge is labelled and not overshared | Manual | AGT |
| M365CP-AG-02 | Sensitive information in Dataverse is discovered with Purview | Manual | AGT |
| M365CP-AG-03 | Agent creation and agent access to SharePoint and OneDrive are monitored | Manual | SAM |
| M365CP-AG-04 | Agent interactions are protected, retained and governed like Copilot interactions | Manual | AGT |

## Summary

| Group | Items | Automated | Manual |
|---|---|---|---|
| Remediate oversharing | 11 | 0 | 11 |
| Sensitivity labels and information protection | 6 | 0 | 6 |
| Guardrails: DLP, identity, devices and threat protection | 9 | 0 | 9 |
| Audit, retention and investigation | 5 | 0 | 5 |
| Regulations and operating model | 5 | 0 | 5 |
| Agents | 4 | 0 | 4 |
| **Total** | **40** | **0** | **40** |

## What an automated version would need

Everything below needs a Microsoft Graph app registration with read-only application permissions and tenant admin
consent, a new collect section for Microsoft 365 data, and a gate on each rule (an "available" flag, the way
`governance.budgetsAvailable` works) so a tenant that was not read reports Not assessed instead of Pass.

| Items | What would be read | Interface and permission |
|---|---|---|
| M365CP-SL-01, SL-02 | Sensitivity labels defined and published | Microsoft Graph beta `GET /security/informationProtection/sensitivityLabels`; application permission `InformationProtectionPolicy.Read.All` (delegated `InformationProtectionPolicy.Read`). Beta APIs are not supported in production. |
| M365CP-RO-09 | Tenant sharing level, domain restriction mode, guest resharing | Microsoft Graph v1.0 `GET /admin/sharepoint/settings` (`sharingCapability`, `sharingDomainRestrictionMode`, `isResharingByExternalUsersEnabled`); `SharePointTenantSettings.Read.All` |
| M365CP-RO-02, RO-03, RO-06, RO-07, RO-08, SL-04 | Site-level oversharing: too many users, Everyone except external users, Anyone and organisation-wide links, labelled sites | SharePoint Online PowerShell (`Microsoft.Online.SharePoint.PowerShell` 16.0.25409 or later): `Start-SPODataAccessGovernanceInsight` (needs a SharePoint Advanced Management licence) and the data access governance report cmdlets. No Graph equivalent was found on Learn. |
| M365CP-RO-04, RO-05 | Restricted Content Discovery per site; delegation | SharePoint Online PowerShell: `Get-SPOSite` property `RestrictContentOrgWideSearch`, `Get-SPOTenant` property `DelegateRestrictedContentDiscoverabilityManagement`, `Start-SPORestrictedContentDiscoverabilityReport` |
| M365CP-GR-05, GR-06 | Conditional Access policies (MFA, legacy authentication block, risk policies) | Microsoft Graph v1.0 `GET /identity/conditionalAccess/policies`; `Policy.Read.All`. PIM eligibility and access review definitions are separate Graph APIs that were not researched in this pass. |
| M365CP-GR-07 | Device enrolment and compliance | Microsoft Graph v1.0 `GET /deviceManagement/managedDevices`; `DeviceManagementManagedDevices.Read.All` |
| M365CP-AU-01 | Audit queries for Copilot activity | Microsoft Graph v1.0 `POST /security/auditLog/queries` (auditLogQuery); `AuditLogsQuery.Read.All` |
| M365CP-AU-05, AG-03 | Copilot interaction history | Microsoft Graph v1.0 `GET /copilot/users/{id}/interactionHistory/getAllEnterpriseInteractions`; application permission `AiEnterpriseInteraction.Read.All`; needs a Copilot licence, and excludes Copilot Studio agent interactions |
| M365CP-GR-01 to GR-04, AU-02, AU-03, RG-01 | DLP policies on the Copilot location, retention policies, insider risk and Compliance Manager | Security & Compliance PowerShell (`Connect-IPPSSession` from the Exchange Online PowerShell module). Cmdlet names for these policies were not verified in this pass, and no Graph read API for DLP policy was found. |

Items about organisation, training and rollout (M365CP-RG-02 to RG-05, RO-01, RO-10, RO-11) have no API behind
them and stay manual in any version.
