# Power Platform Solution Assessment — enumerated question set

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `pp.solution.yaml` scores Microsoft's [Power Platform Solution Assessment](https://learn.microsoft.com/en-us/assessments/a5c3b65d-bf7e-4743-850a-0437ae692690/), a review of a solution from its functionality and user experience through to its alignment with business goals. `src/assess/rules/pp.solution.yaml` is written against this page only, and every rule cites an item from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Power Platform Solution Assessment](https://learn.microsoft.com/en-us/assessments/a5c3b65d-bf7e-4743-850a-0437ae692690/) (60 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Power Platform ALM, adoption and Well-Architected guidance on Microsoft Learn, current; the assessment itself is unversioned and its questions are unpublished |
| Extraction date | 2026-11-25 |
| Verification method | The assessment page, the Power Platform guidance landing page, the adoption overview pages and the Well-Architected pillar checklists named under Sources were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. ALM and several adoption articles were read as Microsoft Learn search excerpts only, as marked. Power Platform API and Dataverse names in the last section were checked against the Learn permission reference, REST reference overview and Dataverse table reference. |

## The questions are Scout-derived

**This is not Microsoft's question list.** Microsoft describes the assessment as covering "every aspect of the solution, from functionality and user experience to its alignment with overall business goals" and publishes neither its questions nor their numbering. Unlike the Well-Architected assessment there is no single published checklist behind it. The items below are **Scout's** reading of the Power Platform guidance named per row (application lifecycle management, the adoption guidance and the Well-Architected checklists), grouped under the three themes Microsoft names plus delivery and operation. The `PPSOL-*` identifiers are Scout's. A score from this file is Scout's questionnaire score against that reading, not the score Microsoft's assessment would return.

## Scout does not read Power Platform data yet

Scout collects Azure Resource Manager, Resource Graph and a small set of Microsoft Graph data. It does not call the
Power Platform admin APIs, so it has no inventory of environments, data policies, apps or flows. All
37 items are therefore **manual**: each rule has `manual: true` and `query: null`, and the answer comes
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
- <https://learn.microsoft.com/power-platform/guidance/adoption/ready-overview>
- <https://learn.microsoft.com/power-platform/guidance/adoption/solution-envisioning>
- <https://learn.microsoft.com/power-platform/guidance/adoption/strategy-best-practices>
- <https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist>
- <https://learn.microsoft.com/power-platform/well-architected/operational-excellence/checklist>
- <https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/checklist>
- <https://learn.microsoft.com/power-platform/well-architected/pillars>
- <https://learn.microsoft.com/power-platform/well-architected/reliability/checklist>
- <https://learn.microsoft.com/power-platform/well-architected/security/checklist>

Cited per item, but read only as the title and one-line summary on the overview pages above, or as a Microsoft Learn search excerpt. The article itself was not opened in full:

- <https://learn.microsoft.com/microsoft-copilot-studio/guidance/alm>
- <https://learn.microsoft.com/power-platform/alm/overview-alm>
- <https://learn.microsoft.com/power-platform/guidance/adoption/alm>
- <https://learn.microsoft.com/power-platform/guidance/adoption/application-modernization>
- <https://learn.microsoft.com/power-platform/guidance/adoption/business-value>
- <https://learn.microsoft.com/power-platform/guidance/adoption/cds-usage>
- <https://learn.microsoft.com/power-platform/guidance/adoption/data-retention>
- <https://learn.microsoft.com/power-platform/guidance/adoption/dlp-strategy>
- <https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy>
- <https://learn.microsoft.com/power-platform/guidance/adoption/license-assignment-strategies>
- <https://learn.microsoft.com/power-platform/guidance/adoption/plan-disaster-recovery>
- <https://learn.microsoft.com/power-platform/guidance/adoption/plan-mission-critical>
- <https://learn.microsoft.com/power-platform/guidance/adoption/roles>
- <https://learn.microsoft.com/power-platform/guidance/adoption/support-strategy>
- <https://learn.microsoft.com/power-platform/guidance/adoption/training-strategy>

## The enumeration — 37 items across 5 groups

### Business alignment (PPSOL-BG) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPSOL-BG-01 | The solution has documented business objectives and measurable success criteria agreed before build | Manual — questionnaire | [power-platform/guidance/adoption/alm](https://learn.microsoft.com/power-platform/guidance/adoption/alm)<br>[power-platform/guidance/adoption/business-value](https://learn.microsoft.com/power-platform/guidance/adoption/business-value) |
| PPSOL-BG-02 | A business owner and an executive sponsor are named for the solution | Manual — questionnaire | [power-platform/guidance/adoption/strategy-best-practices](https://learn.microsoft.com/power-platform/guidance/adoption/strategy-best-practices)<br>[power-platform/guidance/adoption/roles](https://learn.microsoft.com/power-platform/guidance/adoption/roles) |
| PPSOL-BG-03 | Business, IT, end-user and compliance stakeholders took part in defining the solution | Manual — questionnaire | [power-platform/guidance/adoption/solution-envisioning](https://learn.microsoft.com/power-platform/guidance/adoption/solution-envisioning) |
| PPSOL-BG-04 | The solution's business value is measured and reported after go-live | Manual — questionnaire | [power-platform/guidance/adoption/business-value](https://learn.microsoft.com/power-platform/guidance/adoption/business-value) |
| PPSOL-BG-05 | Power Platform was chosen deliberately against alternatives, and the level of formality is set by the solution's complexity and criticality | Manual — questionnaire | [power-platform/guidance/adoption/alm](https://learn.microsoft.com/power-platform/guidance/adoption/alm)<br>[power-platform/guidance/adoption/application-modernization](https://learn.microsoft.com/power-platform/guidance/adoption/application-modernization) |
| PPSOL-BG-06 | The solution is classified by criticality and the classification sets its availability, support and recovery requirements | Manual — questionnaire | [power-platform/guidance/adoption/plan-mission-critical](https://learn.microsoft.com/power-platform/guidance/adoption/plan-mission-critical)<br>[power-platform/guidance/adoption/availability-overview](https://learn.microsoft.com/power-platform/guidance/adoption/availability-overview) |

### Functionality and design (PPSOL-FN) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPSOL-FN-01 | Requirements are captured, prioritised by business value and traceable to solution components | Manual — questionnaire | [power-platform/guidance/adoption/alm](https://learn.microsoft.com/power-platform/guidance/adoption/alm)<br>[power-platform/well-architected/operational-excellence/checklist](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/checklist) |
| PPSOL-FN-02 | All components (apps, flows, agents, tables and other assets) are held in Dataverse solutions rather than built loose | Manual — questionnaire | [power-platform/alm/overview-alm](https://learn.microsoft.com/power-platform/alm/overview-alm)<br>[power-platform/guidance/adoption/environment-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy) |
| PPSOL-FN-03 | The data model is designed deliberately, with the data store, tables and relationships chosen and documented for the workload | Manual — questionnaire | [power-platform/well-architected/performance-efficiency/checklist](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/checklist)<br>[power-platform/alm/overview-alm](https://learn.microsoft.com/power-platform/alm/overview-alm) |
| PPSOL-FN-04 | Security roles and sharing follow least privilege for each type of user | Manual — questionnaire | [power-platform/well-architected/security/checklist](https://learn.microsoft.com/power-platform/well-architected/security/checklist)<br>[power-platform/guidance/adoption/roles](https://learn.microsoft.com/power-platform/guidance/adoption/roles) |
| PPSOL-FN-05 | Connectors and connections are approved under the tenant data policies, and shared solutions use service identities rather than a maker's personal connection | Manual — questionnaire | [power-platform/guidance/adoption/dlp-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/dlp-strategy)<br>[power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale) |
| PPSOL-FN-06 | Environment-specific settings are held in environment variables and connection references, not hard-coded | Manual — questionnaire | [microsoft-copilot-studio/guidance/alm](https://learn.microsoft.com/microsoft-copilot-studio/guidance/alm)<br>[power-platform/alm/overview-alm](https://learn.microsoft.com/power-platform/alm/overview-alm) |
| PPSOL-FN-07 | Integrations with other systems are documented, with error handling and platform request limits taken into account | Manual — questionnaire | [power-platform/well-architected/reliability/checklist](https://learn.microsoft.com/power-platform/well-architected/reliability/checklist)<br>[power-platform/well-architected/performance-efficiency/checklist](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/checklist) |
| PPSOL-FN-08 | Licences needed by every user and component (premium connectors, per-user or per-app, capacity) are identified before rollout | Manual — questionnaire | [power-platform/guidance/adoption/license-assignment-strategies](https://learn.microsoft.com/power-platform/guidance/adoption/license-assignment-strategies)<br>[power-platform/guidance/adoption/cds-usage](https://learn.microsoft.com/power-platform/guidance/adoption/cds-usage) |
| PPSOL-FN-09 | Apps and flows have a named owner, and ownership survives a maker leaving | Manual — questionnaire | [power-platform/guidance/adoption/roles](https://learn.microsoft.com/power-platform/guidance/adoption/roles)<br>[power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale) |
| PPSOL-FN-10 | AI components (agents, AI Builder models, Copilot features) have a defined purpose, boundaries, human oversight and a responsible-AI review | Manual — questionnaire | [power-platform/guidance/adoption/solution-envisioning](https://learn.microsoft.com/power-platform/guidance/adoption/solution-envisioning)<br>[power-platform/well-architected/experience-optimization/checklist](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist) |

### User experience (PPSOL-UX) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPSOL-UX-01 | The target users and their tasks are identified, and users were involved in the design | Manual — questionnaire | [power-platform/well-architected/experience-optimization/checklist](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist) |
| PPSOL-UX-02 | The interface follows consistent design standards, navigation and terminology | Manual — questionnaire | [power-platform/well-architected/experience-optimization/checklist](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist) |
| PPSOL-UX-03 | Accessibility needs are designed for and tested | Manual — questionnaire | [power-platform/well-architected/experience-optimization/checklist](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist) |
| PPSOL-UX-04 | The layout works on the devices and screen sizes users have | Manual — questionnaire | [power-platform/well-architected/experience-optimization/checklist](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist) |
| PPSOL-UX-05 | App and flow response times meet defined targets and are measured with real users | Manual — questionnaire | [power-platform/well-architected/performance-efficiency/checklist](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/checklist) |
| PPSOL-UX-06 | Messages, notifications and errors tell users what happened and what to do next | Manual — questionnaire | [power-platform/well-architected/experience-optimization/checklist](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist) |
| PPSOL-UX-07 | Users are onboarded with training and help content for the solution | Manual — questionnaire | [power-platform/guidance/adoption/training-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/training-strategy)<br>[power-platform/guidance/adoption/ready-overview](https://learn.microsoft.com/power-platform/guidance/adoption/ready-overview) |
| PPSOL-UX-08 | Users have a channel for feedback and enhancement requests, and it is acted on | Manual — questionnaire | [power-platform/guidance/adoption/govern-at-scale](https://learn.microsoft.com/power-platform/guidance/adoption/govern-at-scale)<br>[power-platform/well-architected/experience-optimization/checklist](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist) |

### Delivery and ALM (PPSOL-DL) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPSOL-DL-01 | Separate development, test and production environments are used | Manual — questionnaire | [power-platform/alm/overview-alm](https://learn.microsoft.com/power-platform/alm/overview-alm)<br>[power-platform/guidance/adoption/environment-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy) |
| PPSOL-DL-02 | Solutions are held in source control as the source of truth | Manual — questionnaire | [power-platform/alm/overview-alm](https://learn.microsoft.com/power-platform/alm/overview-alm)<br>[power-platform/guidance/adoption/application-modernization](https://learn.microsoft.com/power-platform/guidance/adoption/application-modernization) |
| PPSOL-DL-03 | Deployments between environments are automated through pipelines | Manual — questionnaire | [power-platform/guidance/adoption/alm](https://learn.microsoft.com/power-platform/guidance/adoption/alm)<br>[power-platform/guidance/adoption/application-modernization](https://learn.microsoft.com/power-platform/guidance/adoption/application-modernization) |
| PPSOL-DL-04 | Solution checker, or an equivalent static check, is run and its findings resolved before deployment | Manual — questionnaire | [power-platform/guidance/adoption/environment-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy) |
| PPSOL-DL-05 | Managed solutions with version numbers are deployed to test and production | Manual — questionnaire | [power-platform/alm/overview-alm](https://learn.microsoft.com/power-platform/alm/overview-alm) |
| PPSOL-DL-06 | Functional, regression and user acceptance testing are defined and performed before release | Manual — questionnaire | [power-platform/well-architected/operational-excellence/checklist](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/checklist)<br>[power-platform/guidance/adoption/alm](https://learn.microsoft.com/power-platform/guidance/adoption/alm) |
| PPSOL-DL-07 | A rollback or feature-disable plan exists for failed releases | Manual — questionnaire | [power-platform/well-architected/operational-excellence/checklist](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/checklist) |
| PPSOL-DL-08 | Design, data model and support runbook documentation is current | Manual — questionnaire | [power-platform/well-architected/operational-excellence/checklist](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/checklist) |

### Operate (PPSOL-OP) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| PPSOL-OP-01 | Solution health is monitored with alerts, using the admin centre Monitor area, Application Insights or an equivalent | Manual — questionnaire | [power-platform/guidance/adoption/observability](https://learn.microsoft.com/power-platform/guidance/adoption/observability) |
| PPSOL-OP-02 | A support model and escalation path for the solution is defined and known to users | Manual — questionnaire | [power-platform/guidance/adoption/support-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/support-strategy)<br>[power-platform/guidance/adoption/operate-overview](https://learn.microsoft.com/power-platform/guidance/adoption/operate-overview) |
| PPSOL-OP-03 | Backup, restore and retention for the solution's environment and data are understood and tested | Manual — questionnaire | [power-platform/guidance/adoption/data-retention](https://learn.microsoft.com/power-platform/guidance/adoption/data-retention)<br>[power-platform/guidance/adoption/plan-disaster-recovery](https://learn.microsoft.com/power-platform/guidance/adoption/plan-disaster-recovery) |
| PPSOL-OP-04 | Capacity and licence consumption of the solution is monitored | Manual — questionnaire | [power-platform/guidance/adoption/observability](https://learn.microsoft.com/power-platform/guidance/adoption/observability)<br>[power-platform/guidance/adoption/cds-usage](https://learn.microsoft.com/power-platform/guidance/adoption/cds-usage) |
| PPSOL-OP-05 | Criteria for retiring the solution and its environment are defined | Manual — questionnaire | [power-platform/guidance/adoption/environment-strategy](https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy)<br>[power-platform/guidance/adoption/admin-best-practices](https://learn.microsoft.com/power-platform/guidance/adoption/admin-best-practices) |

PPSOL-UX-03 (accessibility) and PPSOL-DL-05 (managed solutions with version numbers) are Scout additions drawn from the wider ALM and user-experience guidance rather than a line on a published checklist.

## What an automated version would need

Authentication is a different permission surface from the Azure Resource Manager Reader role every other
Scout rule reads through: the Power Platform API takes a token for `https://api.powerplatform.com/.default`
issued to a Microsoft Entra app registration, and the admin PowerShell module signs in as a Power Platform
administrator. An automated version would therefore be opt-in, like `-IncludeDevOps`, and every rule
reading it would be gated so "switch off" or "no access" reads Not assessed rather than "nothing is
configured".

| Source | What it would show | Items it would answer or inform |
|---|---|---|
| Power Platform API, `EnvironmentManagement` namespace (`EnvironmentManagement.Environments.Read`, `.Groups.Read`, `.Settings.Read`) | Environments with type and group membership; environment management settings; backups and business continuity state | PPSOL-DL-01 (separate stages), PPSOL-OP-03 (backup and restore), PPSOL-OP-05 (inactive environments) |
| Dataverse Web API, per environment: the `solution`, `environmentvariabledefinition` and `connectionreference` tables (the `ismanaged` column shows managed or unmanaged) | Whether assets sit in solutions, managed versus unmanaged, use of environment variables and connection references | PPSOL-FN-02, PPSOL-FN-06, PPSOL-DL-05 |
| Power Platform API, `PowerApps.Apps.Read` and `PowerAutomate.Flows.Read` | Apps and flows with owners and state | PPSOL-FN-09 (ownership), PPSOL-FN-05 (connections in use) |
| Admin PowerShell module `Microsoft.PowerApps.Administration.PowerShell`: `Get-DlpPolicy`, `Get-AdminDlpPolicy`, `Get-AdminPowerAppConnector` | Data policies and the connectors in use, including custom connectors | PPSOL-FN-05 |
| Power Platform API, `Licensing` namespace (`Licensing.Allocations.Read`, `Licensing.BillingPolicies.Read`) and the admin centre capacity reports | Allocations, billing policies and capacity | PPSOL-FN-08, PPSOL-OP-04 |
| Power Platform API, `Analytics` namespace (`Analytics.AdvisorRecommendations.Read`) | Admin centre recommended actions for the tenant | PPSOL-OP-01 |
| Azure Resource Graph (Scout already reads this) | Application Insights and Log Analytics resources that a solution could be sending telemetry to; nothing links them to a solution without the admin API | PPSOL-OP-01 |

Most of this assessment will stay a questionnaire whatever is collected. Business alignment (PPSOL-BG), user
experience (PPSOL-UX) and testing and documentation (PPSOL-DL-04 to PPSOL-DL-08) describe how a team works, not how
a resource is configured. Roughly ten items could be answered or cross-checked from the sources above. Some of
these APIs are marked preview on Learn today, so each would need its current status confirmed before a rule relied
on it.