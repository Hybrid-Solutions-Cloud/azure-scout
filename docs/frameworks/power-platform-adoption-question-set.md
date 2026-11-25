# Power Platform Adoption Assessment — enumerated question set

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `pp.adoption.yaml` scores Microsoft's [Power Platform Adoption Assessment](https://learn.microsoft.com/en-us/assessments/3c62fd23-9d36-491c-8941-26d5553365f8/), an evaluation of an organisation's current use of Power Platform. `src/assess/rules/pp.adoption.yaml` is written against this page only, and every rule cites an item from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Power Platform Adoption Assessment](https://learn.microsoft.com/en-us/assessments/3c62fd23-9d36-491c-8941-26d5553365f8/) (30 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Power Platform adoption guidance and Center of Excellence guidance on Microsoft Learn, current; the assessment itself is unversioned and its questions are unpublished |
| Extraction date | 2026-11-25 |
| Verification method | The assessment page, the Power Platform guidance landing page, the adoption overview pages (strategy, plan, governance, readiness, security, operations, availability), the adoption assessment article and the adoption articles marked as read in full under Sources were fetched with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. The remaining adoption articles are cited from the title and one-line summary given on those overview pages. Power Platform API names in the last section were checked against the Learn permission reference and REST reference overview. |

## The questions are Scout-derived

**This is not Microsoft's question list.** Microsoft publishes the assessment's three areas (see the note below the tables) and neither its questions nor their numbering. The items below are **Scout's** reading of the Power Platform adoption guidance and Center of Excellence guidance named per row, spread across Microsoft's three areas. The `PPADOPT-*` identifiers are Scout's. A score from this file is Scout's questionnaire score against that reading, not the score Microsoft's assessment would return.

## Scout does not read Power Platform data yet

Scout collects Azure Resource Manager, Resource Graph and a small set of Microsoft Graph data. It does not call the
Power Platform admin APIs, so it has no inventory of environments, data policies, apps or flows. All
41 items are therefore **manual**: each rule has `manual: true` and `query: null`, and the answer comes
from the questionnaire ([Questionnaire Answers](../assessment/questionnaire-answers.md)). Unanswered items show as Manual and are left
out of the score; they are never counted as failures. No rule reads `collect.json`.

Sources:

Read in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25:

- <https://learn.microsoft.com/power-platform/guidance/>
- <https://learn.microsoft.com/power-platform/guidance/adoption/admin-best-practices>
- <https://learn.microsoft.com/power-platform/guidance/adoption/availability-overview>
- <https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale>
- <https://learn.microsoft.com/power-platform/guidance/adoption/observability>
- <https://learn.microsoft.com/power-platform/guidance/adoption/operate-overview>
- <https://learn.microsoft.com/power-platform/guidance/adoption/plan-overview>
- <https://learn.microsoft.com/power-platform/guidance/adoption/ready-overview>
- <https://learn.microsoft.com/power-platform/guidance/adoption/secure-overview>
- <https://learn.microsoft.com/power-platform/guidance/adoption/solution-envisioning>
- <https://learn.microsoft.com/power-platform/guidance/adoption/strategy-best-practices>
- <https://learn.microsoft.com/power-platform/guidance/adoption/take-assessment>

Cited per item, but read only as the title and one-line summary on the overview pages above, or as a Microsoft Learn search excerpt. The article itself was not opened in full:

- <https://learn.microsoft.com/power-platform/guidance/adoption/alm>
- <https://learn.microsoft.com/power-platform/guidance/adoption/application-modernization>
- <https://learn.microsoft.com/power-platform/guidance/adoption/assess-security-posture>
- <https://learn.microsoft.com/power-platform/guidance/adoption/business-value>
- <https://learn.microsoft.com/power-platform/guidance/adoption/cds-usage>
- <https://learn.microsoft.com/power-platform/guidance/adoption/coe>
- <https://learn.microsoft.com/power-platform/guidance/adoption/common-vision>
- <https://learn.microsoft.com/power-platform/guidance/adoption/community-goals>
- <https://learn.microsoft.com/power-platform/guidance/adoption/compliance>
- <https://learn.microsoft.com/power-platform/guidance/adoption/conditional-access>
- <https://learn.microsoft.com/power-platform/guidance/adoption/data-protection>
- <https://learn.microsoft.com/power-platform/guidance/adoption/data-retention>
- <https://learn.microsoft.com/power-platform/guidance/adoption/delivery-models>
- <https://learn.microsoft.com/power-platform/guidance/adoption/dlp-strategy>
- <https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy>
- <https://learn.microsoft.com/power-platform/guidance/adoption/executive-sponsorship>
- <https://learn.microsoft.com/power-platform/guidance/adoption/in-a-day>
- <https://learn.microsoft.com/power-platform/guidance/adoption/license-assignment-strategies>
- <https://learn.microsoft.com/power-platform/guidance/adoption/manage-default-environment>
- <https://learn.microsoft.com/power-platform/guidance/adoption/manage-resistance>
- <https://learn.microsoft.com/power-platform/guidance/adoption/maturity-model>
- <https://learn.microsoft.com/power-platform/guidance/adoption/nurture-best-practices>
- <https://learn.microsoft.com/power-platform/guidance/adoption/onboard-makers>
- <https://learn.microsoft.com/power-platform/guidance/adoption/plan-disaster-recovery>
- <https://learn.microsoft.com/power-platform/guidance/adoption/plan-mission-critical>
- <https://learn.microsoft.com/power-platform/guidance/adoption/pp-admin>
- <https://learn.microsoft.com/power-platform/guidance/adoption/reactive-governance>
- <https://learn.microsoft.com/power-platform/guidance/adoption/resource-usage>
- <https://learn.microsoft.com/power-platform/guidance/adoption/reusable>
- <https://learn.microsoft.com/power-platform/guidance/adoption/roles>
- <https://learn.microsoft.com/power-platform/guidance/adoption/secure-default-environment>
- <https://learn.microsoft.com/power-platform/guidance/adoption/security-posture-management>
- <https://learn.microsoft.com/power-platform/guidance/adoption/show-and-tell>
- <https://learn.microsoft.com/power-platform/guidance/adoption/support-strategy>
- <https://learn.microsoft.com/power-platform/guidance/adoption/threat-detection>
- <https://learn.microsoft.com/power-platform/guidance/adoption/training-strategy>
- <https://learn.microsoft.com/power-platform/guidance/adoption/vision>
- <https://learn.microsoft.com/power-platform/guidance/adoption/wiki-community>
- <https://learn.microsoft.com/power-platform/guidance/coe/overview>

## The enumeration — 41 items across 3 groups

### Strategy, vision and business value (PPADOPT-SV) — 11 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPADOPT-SV-01 | An adoption vision is documented in a way that addresses both business and technical stakeholders | Manual — questionnaire | [power-platform/guidance/adoption/vision](https://learn.microsoft.com/power-platform/guidance/adoption/vision)<br>[power-platform/guidance/adoption/strategy-best-practices](https://learn.microsoft.com/power-platform/guidance/adoption/strategy-best-practices) |
| PPADOPT-SV-02 | Measurable objectives, key results and key initiatives are defined for adoption | Manual — questionnaire | [power-platform/guidance/adoption/vision](https://learn.microsoft.com/power-platform/guidance/adoption/vision) |
| PPADOPT-SV-03 | The adoption strategy is aligned with the organisation's business goals and objectives | Manual — questionnaire | [power-platform/guidance/adoption/common-vision](https://learn.microsoft.com/power-platform/guidance/adoption/common-vision) |
| PPADOPT-SV-04 | How business value is measured and communicated is defined, and aligned with organisational objectives and key results | Manual — questionnaire | [power-platform/guidance/adoption/business-value](https://learn.microsoft.com/power-platform/guidance/adoption/business-value) |
| PPADOPT-SV-05 | An executive sponsor is secured and leadership is bought in | Manual — questionnaire | [power-platform/guidance/adoption/executive-sponsorship](https://learn.microsoft.com/power-platform/guidance/adoption/executive-sponsorship)<br>[power-platform/guidance/adoption/strategy-best-practices](https://learn.microsoft.com/power-platform/guidance/adoption/strategy-best-practices) |
| PPADOPT-SV-06 | A Center of Excellence is established to make use scalable, sustainable and secure | Manual — questionnaire | [power-platform/guidance/adoption/coe](https://learn.microsoft.com/power-platform/guidance/adoption/coe)<br>[power-platform/guidance/coe/overview](https://learn.microsoft.com/power-platform/guidance/coe/overview) |
| PPADOPT-SV-07 | Roles and responsibilities are defined for Power Platform admins, environment admins, makers and other stakeholders | Manual — questionnaire | [power-platform/guidance/adoption/roles](https://learn.microsoft.com/power-platform/guidance/adoption/roles)<br>[power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale) |
| PPADOPT-SV-08 | A delivery model is evaluated and chosen (centralised, decentralised or hybrid) | Manual — questionnaire | [power-platform/guidance/adoption/delivery-models](https://learn.microsoft.com/power-platform/guidance/adoption/delivery-models)<br>[power-platform/guidance/adoption/plan-overview](https://learn.microsoft.com/power-platform/guidance/adoption/plan-overview) |
| PPADOPT-SV-09 | A licence assignment strategy ensures return on investment, user adoption and optimised cost | Manual — questionnaire | [power-platform/guidance/adoption/license-assignment-strategies](https://learn.microsoft.com/power-platform/guidance/adoption/license-assignment-strategies)<br>[power-platform/guidance/adoption/plan-overview](https://learn.microsoft.com/power-platform/guidance/adoption/plan-overview) |
| PPADOPT-SV-10 | Application modernisation opportunities are identified and assessed for Power Platform | Manual — questionnaire | [power-platform/guidance/adoption/application-modernization](https://learn.microsoft.com/power-platform/guidance/adoption/application-modernization)<br>[power-platform/guidance/adoption/plan-overview](https://learn.microsoft.com/power-platform/guidance/adoption/plan-overview) |
| PPADOPT-SV-11 | Adoption maturity is assessed and a target stage is set | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale)<br>[power-platform/guidance/adoption/maturity-model](https://learn.microsoft.com/power-platform/guidance/adoption/maturity-model) |

### Administration, governance and support (PPADOPT-AG) — 19 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPADOPT-AG-01 | A dedicated Power Platform admin is designated to oversee operations, compliance and performance | Manual — questionnaire | [power-platform/guidance/adoption/pp-admin](https://learn.microsoft.com/power-platform/guidance/adoption/pp-admin)<br>[power-platform/guidance/adoption/admin-best-practices](https://learn.microsoft.com/power-platform/guidance/adoption/admin-best-practices) |
| PPADOPT-AG-02 | A governance framework with objectives, policies, roles and a delivery model is defined and reviewed | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale) |
| PPADOPT-AG-03 | A tenant environment strategy defines how environments are created, managed and decommissioned | Manual — questionnaire | [power-platform/guidance/adoption/environment-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy) |
| PPADOPT-AG-04 | Environment groups and rules are used to apply governance to environments in bulk | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale)<br>[power-platform/guidance/adoption/environment-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy) |
| PPADOPT-AG-05 | A data policy strategy classifies connectors and is communicated to makers | Manual — questionnaire | [power-platform/guidance/adoption/dlp-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/dlp-strategy) |
| PPADOPT-AG-06 | The default environment is governed and secured | Manual — questionnaire | [power-platform/guidance/adoption/manage-default-environment](https://learn.microsoft.com/power-platform/guidance/adoption/manage-default-environment)<br>[power-platform/guidance/adoption/secure-default-environment](https://learn.microsoft.com/power-platform/guidance/adoption/secure-default-environment) |
| PPADOPT-AG-07 | Managed environments are used for production and critical workloads | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale)<br>[power-platform/guidance/adoption/secure-overview](https://learn.microsoft.com/power-platform/guidance/adoption/secure-overview) |
| PPADOPT-AG-08 | Security posture is assessed and improved, using the admin centre security score and recommendations | Manual — questionnaire | [power-platform/guidance/adoption/assess-security-posture](https://learn.microsoft.com/power-platform/guidance/adoption/assess-security-posture)<br>[power-platform/guidance/adoption/security-posture-management](https://learn.microsoft.com/power-platform/guidance/adoption/security-posture-management) |
| PPADOPT-AG-09 | Maker, user and guest access is controlled with conditional access and multifactor authentication | Manual — questionnaire | [power-platform/guidance/adoption/conditional-access](https://learn.microsoft.com/power-platform/guidance/adoption/conditional-access)<br>[power-platform/guidance/adoption/secure-overview](https://learn.microsoft.com/power-platform/guidance/adoption/secure-overview) |
| PPADOPT-AG-10 | Threat detection and activity logging for Power Platform are enabled and monitored | Manual — questionnaire | [power-platform/guidance/adoption/threat-detection](https://learn.microsoft.com/power-platform/guidance/adoption/threat-detection)<br>[power-platform/guidance/adoption/observability](https://learn.microsoft.com/power-platform/guidance/adoption/observability) |
| PPADOPT-AG-11 | Compliance and data protection requirements are identified and met | Manual — questionnaire | [power-platform/guidance/adoption/compliance](https://learn.microsoft.com/power-platform/guidance/adoption/compliance)<br>[power-platform/guidance/adoption/data-protection](https://learn.microsoft.com/power-platform/guidance/adoption/data-protection) |
| PPADOPT-AG-12 | Reactive governance controls respond to non-compliant resources and incidents as they arise | Manual — questionnaire | [power-platform/guidance/adoption/reactive-governance](https://learn.microsoft.com/power-platform/guidance/adoption/reactive-governance) |
| PPADOPT-AG-13 | New environment, connector and access requests follow a formal, ideally automated, approval process | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale) |
| PPADOPT-AG-14 | Application lifecycle management practices are established | Manual — questionnaire | [power-platform/guidance/adoption/alm](https://learn.microsoft.com/power-platform/guidance/adoption/alm) |
| PPADOPT-AG-15 | Usage and adoption insights are monitored and reported | Manual — questionnaire | [power-platform/guidance/adoption/observability](https://learn.microsoft.com/power-platform/guidance/adoption/observability)<br>[power-platform/guidance/adoption/resource-usage](https://learn.microsoft.com/power-platform/guidance/adoption/resource-usage) |
| PPADOPT-AG-16 | Licence and capacity consumption are monitored | Manual — questionnaire | [power-platform/guidance/adoption/cds-usage](https://learn.microsoft.com/power-platform/guidance/adoption/cds-usage)<br>[power-platform/guidance/adoption/observability](https://learn.microsoft.com/power-platform/guidance/adoption/observability) |
| PPADOPT-AG-17 | A support strategy defines how users and makers get help | Manual — questionnaire | [power-platform/guidance/adoption/support-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/support-strategy)<br>[power-platform/guidance/adoption/operate-overview](https://learn.microsoft.com/power-platform/guidance/adoption/operate-overview) |
| PPADOPT-AG-18 | Mission-critical workloads are identified and have a disaster recovery plan, and data retention and mobility are addressed | Manual — questionnaire | [power-platform/guidance/adoption/plan-mission-critical](https://learn.microsoft.com/power-platform/guidance/adoption/plan-mission-critical)<br>[power-platform/guidance/adoption/plan-disaster-recovery](https://learn.microsoft.com/power-platform/guidance/adoption/plan-disaster-recovery)<br>[power-platform/guidance/adoption/data-retention](https://learn.microsoft.com/power-platform/guidance/adoption/data-retention) |
| PPADOPT-AG-19 | Admin centre recommendations are reviewed regularly and acted on | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale)<br>[power-platform/guidance/adoption/observability](https://learn.microsoft.com/power-platform/guidance/adoption/observability) |

### Nurture and adoption (PPADOPT-NA) — 11 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPADOPT-NA-01 | A training and upskilling strategy exists for makers and users | Manual — questionnaire | [power-platform/guidance/adoption/training-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/training-strategy)<br>[power-platform/guidance/adoption/ready-overview](https://learn.microsoft.com/power-platform/guidance/adoption/ready-overview) |
| PPADOPT-NA-02 | Internal training events are hosted to build Power Platform skills | Manual — questionnaire | [power-platform/guidance/adoption/in-a-day](https://learn.microsoft.com/power-platform/guidance/adoption/in-a-day)<br>[power-platform/guidance/adoption/ready-overview](https://learn.microsoft.com/power-platform/guidance/adoption/ready-overview) |
| PPADOPT-NA-03 | Tools to support the maker community are set up, such as a wiki, a SharePoint hub or chat channels | Manual — questionnaire | [power-platform/guidance/adoption/wiki-community](https://learn.microsoft.com/power-platform/guidance/adoption/wiki-community) |
| PPADOPT-NA-04 | Reusable templates and components are shared across the organisation | Manual — questionnaire | [power-platform/guidance/adoption/reusable](https://learn.microsoft.com/power-platform/guidance/adoption/reusable) |
| PPADOPT-NA-05 | High-value use cases are envisioned and prioritised through workshops with stakeholders | Manual — questionnaire | [power-platform/guidance/adoption/solution-envisioning](https://learn.microsoft.com/power-platform/guidance/adoption/solution-envisioning) |
| PPADOPT-NA-06 | Community purpose and goals are defined | Manual — questionnaire | [power-platform/guidance/adoption/community-goals](https://learn.microsoft.com/power-platform/guidance/adoption/community-goals) |
| PPADOPT-NA-07 | New makers are onboarded through a defined process | Manual — questionnaire | [power-platform/guidance/adoption/onboard-makers](https://learn.microsoft.com/power-platform/guidance/adoption/onboard-makers) |
| PPADOPT-NA-08 | Success stories are shared to build momentum | Manual — questionnaire | [power-platform/guidance/adoption/show-and-tell](https://learn.microsoft.com/power-platform/guidance/adoption/show-and-tell) |
| PPADOPT-NA-09 | Makers are nurtured and educated, with feedback gathered from them and from users | Manual — questionnaire | [power-platform/guidance/adoption/nurture-best-practices](https://learn.microsoft.com/power-platform/guidance/adoption/nurture-best-practices)<br>[power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale) |
| PPADOPT-NA-10 | Resistance to change is managed and common adoption anti-patterns are avoided | Manual — questionnaire | [power-platform/guidance/adoption/manage-resistance](https://learn.microsoft.com/power-platform/guidance/adoption/manage-resistance)<br>[power-platform/guidance/adoption/operate-overview](https://learn.microsoft.com/power-platform/guidance/adoption/operate-overview) |
| PPADOPT-NA-11 | Makers are told the governance rules, policies and guardrails before they build | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale)<br>[power-platform/guidance/adoption/dlp-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/dlp-strategy) |

The three group names are Microsoft's: the adoption assessment article says the assessment covers "Strategy, vision and business value", "Administration, governance and support" and "Nurture and adoption". The items inside each group are Scout's.

## What an automated version would need

Authentication is a different permission surface from the Azure Resource Manager Reader role every other
Scout rule reads through: the Power Platform API takes a token for `https://api.powerplatform.com/.default`
issued to a Microsoft Entra app registration, and the admin PowerShell module signs in as a Power Platform
administrator. An automated version would therefore be opt-in, like `-IncludeDevOps`, and every rule
reading it would be gated so "switch off" or "no access" reads Not assessed rather than "nothing is
configured".

| Source | What it would show | Items it would answer or inform |
|---|---|---|
| Power Platform API, `EnvironmentManagement` namespace (`EnvironmentManagement.Environments.Read`, `.Groups.Read`, `.Settings.Read`) and `Governance` namespace (rule-based policies on environment groups) | Environments, how they are grouped, and the governance rules applied to groups | PPADOPT-AG-03, PPADOPT-AG-04, PPADOPT-AG-07 |
| Admin PowerShell module `Microsoft.PowerApps.Administration.PowerShell`: `Get-DlpPolicy`, `Get-AdminDlpPolicy`, `Get-TenantSettings`, `Get-AdminPowerAppEnvironment` (managed-environment `governanceConfiguration`) | Data policies and connector classification; tenant settings such as who may create environments; which environments are managed | PPADOPT-AG-05, PPADOPT-AG-06, PPADOPT-AG-07 |
| Power Platform API, `Security` namespace (`Security.Recommendations.Read`) and the admin centre Security overview score | Security recommendations and score | PPADOPT-AG-08 |
| Power Platform API, `Analytics` namespace (`Analytics.AdvisorRecommendations.Read`) and the Power Platform for Admins V2 connector (`Get Recommendations`) | Admin centre recommended actions and whether they are open | PPADOPT-AG-19 |
| Power Platform API, `Authorization.RoleAssignments.Read` | Power Platform role assignments | PPADOPT-AG-01, PPADOPT-SV-07 |
| Power Platform API, `PowerApps.Apps.Read`, `PowerAutomate.Flows.Read`; `Licensing` namespace (`Licensing.Allocations.Read`, `Licensing.BillingPolicies.Read`) and the admin centre capacity reports | Inventory and usage of apps and flows; maker counts; licence allocation and capacity | PPADOPT-AG-15, PPADOPT-AG-16, PPADOPT-SV-09 |
| Microsoft Graph: Entra Conditional Access policies (already read by Scout's Entra inventory, not yet in `collect.json`) | Whether Power Platform sign-in and guest access are covered by conditional access | PPADOPT-AG-09 |
| Microsoft Purview audit log (Power Platform activity logging) | Whether activity is logged and where it goes | PPADOPT-AG-10 |
| Center of Excellence Starter Kit tables in Dataverse (inventory, maker and environment records, if the kit is installed) | A ready-made inventory of environments, apps, flows and makers, and whether a CoE is running | PPADOPT-SV-06, PPADOPT-AG-15 |

This is the assessment with the least that any API can answer. The strategy and nurture groups (PPADOPT-SV and
PPADOPT-NA, 22 of 41 items) describe vision, sponsorship, training and community, which no admin API records.
Only part of the administration group (PPADOPT-AG) could be answered or cross-checked from the sources above. Some of
these APIs are marked preview on Learn today, so each would need its current status confirmed before a rule relied
on it. The Center of Excellence Starter Kit table names above were not checked on Learn for this page; confirm them
before building on them.