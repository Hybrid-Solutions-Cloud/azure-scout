# Power Platform Well-Architected — enumerated source for the Power Platform Well-Architected assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `pp.wellarchitected.yaml` scores Microsoft's
[Power Platform Well-Architected](https://learn.microsoft.com/en-us/assessments/689fd8d9-1000-4cbb-8096-a6c8f3294fc7/)
assessment, which examines the reliability, security, operational excellence, performance efficiency and user
experience of a workload design. `src/assess/rules/pp.wellarchitected.yaml` is written against this page only,
and every rule cites an item from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Power Platform Well-Architected](https://learn.microsoft.com/en-us/assessments/689fd8d9-1000-4cbb-8096-a6c8f3294fc7/) (60 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Power Platform Well-Architected pillar checklists on Microsoft Learn, current (Reliability RE:01-08, Security SE:01-10, Operational Excellence OE:01-11, Performance Efficiency PE:01-10, Experience Optimization XO:01-10); no version number is published |
| Extraction date | 2026-11-25 |
| Verification method | The assessment page, the pillars page and each of the five pillar checklist pages were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25, and every code and recommendation below was copied from those tables. Per-item guidance links are the checklist's own links. The individual guidance articles were not each read in full. Power Platform API names in the last section were checked against the Learn permission reference and REST reference overview. |

## The questions are Scout-derived

**This is not Microsoft's question list.** Microsoft does not publish the assessment's questions. What it does
publish is the pillar checklists, each recommendation carrying a code (RE:01, SE:01 and so on). Scout turns each
checklist recommendation into one yes/no statement, so the `PPWAF-*` identifiers carry Microsoft's codes (`PPWAF-RE-01`
is Microsoft's RE:01) but the wording of every question is Scout's paraphrase, and the assessment's own multiple-choice
questions may split, merge or reorder them. A score from this file says how the workload sits against the published
checklist. It is not the score Microsoft's assessment would return.

## Scout does not read Power Platform data yet

Scout collects Azure Resource Manager, Resource Graph and a small set of Microsoft Graph data. It does not call the
Power Platform admin APIs, so it has no inventory of environments, data policies, apps or flows. All
49 items are therefore **manual**: each rule has `manual: true` and `query: null`, and the answer comes
from the questionnaire ([Questionnaire Answers](../assessment/questionnaire-answers.md)). Unanswered items show as Manual and are left
out of the score; they are never counted as failures. Entra Conditional Access, which SE:05 touches, is read by
Scout's Entra inventory but is not part of the assessment collection, so it cannot be used as evidence either.

Sources, the pillar checklists:

- [RE] [Recommendation checklist for Reliability](https://learn.microsoft.com/power-platform/well-architected/reliability/checklist)
- [SE] [Recommendation checklist for Security](https://learn.microsoft.com/power-platform/well-architected/security/checklist)
- [OE] [Recommendation checklist for Operational Excellence](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/checklist)
- [PE] [Recommendation checklist for Performance Efficiency](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/checklist)
- [XO] [Design review checklist for Experience Optimization](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/checklist)

## The enumeration — 49 items across the five pillars

### Reliability (PPWAF-RE) — 8 items

| # | Microsoft code | Item (Scout paraphrase) | Scout |
|---|---|---|---|
| PPWAF-RE-01 | [RE:01](https://learn.microsoft.com/power-platform/well-architected/reliability/simplify) | The workload design is aligned to business objectives and kept free of unnecessary complexity | Manual — questionnaire |
| PPWAF-RE-02 | [RE:02](https://learn.microsoft.com/power-platform/well-architected/reliability/identify-flows) | User and system flows are identified and rated by criticality | Manual — questionnaire |
| PPWAF-RE-03 | [RE:03](https://learn.microsoft.com/power-platform/well-architected/reliability/failure-mode-analysis) | Failure mode analysis has been performed on the solution components | Manual — questionnaire |
| PPWAF-RE-04 | [RE:04](https://learn.microsoft.com/power-platform/well-architected/reliability/metrics) | Reliability and recovery targets are defined for components, flows and the solution, and a health model describes healthy, degraded and unhealthy states | Manual — questionnaire |
| PPWAF-RE-05 | [RE:05](https://learn.microsoft.com/power-platform/well-architected/reliability/handle-transient-faults) | Error handling and transient fault handling are built into apps, flows and integrations | Manual — questionnaire |
| PPWAF-RE-06 | [RE:06](https://learn.microsoft.com/power-platform/well-architected/reliability/testing-strategy) | Resiliency and availability scenarios are tested, including simulated malfunction and load | Manual — questionnaire |
| PPWAF-RE-07 | [RE:07](https://learn.microsoft.com/power-platform/well-architected/reliability/disaster-recovery) | Business continuity and disaster recovery plans are structured, documented, tested and aligned to the recovery targets | Manual — questionnaire |
| PPWAF-RE-08 | [RE:08](https://learn.microsoft.com/power-platform/well-architected/reliability/monitoring-alerting-strategy) | The workload's health indicators are measured and published | Manual — questionnaire |

### Security (PPWAF-SE) — 10 items

| # | Microsoft code | Item (Scout paraphrase) | Scout |
|---|---|---|---|
| PPWAF-SE-01 | [SE:01](https://learn.microsoft.com/power-platform/well-architected/security/establish-baseline) | A security baseline aligned to compliance requirements, industry standards and platform recommendations is established and regularly measured against | Manual — questionnaire |
| PPWAF-SE-02 | [SE:02](https://learn.microsoft.com/power-platform/well-architected/security/secure-development-lifecycle) | A secure development lifecycle with a hardened, mostly automated and auditable supply chain is maintained, and threat modelling informs design | Manual — questionnaire |
| PPWAF-SE-03 | [SE:03](https://learn.microsoft.com/power-platform/well-architected/security/data-classification) | Sensitivity and information-type labels are applied to workload data and to the systems that process it | Manual — questionnaire |
| PPWAF-SE-04 | [SE:04](https://learn.microsoft.com/power-platform/well-architected/security/segmentation) | Intentional segmentation and perimeters exist across environments, roles and responsibilities, workload identities and resource organisation | Manual — questionnaire |
| PPWAF-SE-05 | [SE:05](https://learn.microsoft.com/power-platform/well-architected/security/identity-access) | Identity and access management is strict, conditional and auditable for all users, team members and system components | Manual — questionnaire |
| PPWAF-SE-06 | [SE:06](https://learn.microsoft.com/power-platform/well-architected/security/encryption) | Data is encrypted with modern industry-standard methods, with scope aligned to data classification and platform-native methods preferred | Manual — questionnaire |
| PPWAF-SE-07 | [SE:07](https://learn.microsoft.com/power-platform/well-architected/security/application-secrets) | Application secrets are stored hardened, access is restricted and audited, and rotation is regular and can be done in an emergency | Manual — questionnaire |
| PPWAF-SE-08 | [SE:08](https://learn.microsoft.com/power-platform/well-architected/security/monitor-threats) | A holistic monitoring strategy with modern threat detection alerts reliably into existing security operations processes | Manual — questionnaire |
| PPWAF-SE-09 | [SE:09](https://learn.microsoft.com/power-platform/well-architected/security/testing) | A comprehensive security testing regimen prevents issues, validates threat prevention and tests threat detection | Manual — questionnaire |
| PPWAF-SE-10 | [SE:10](https://learn.microsoft.com/power-platform/well-architected/security/incident-response) | Incident response procedures are defined and tested, covering localized issues through disaster recovery, with clear owners | Manual — questionnaire |

### Operational Excellence (PPWAF-OE) — 11 items

| # | Microsoft code | Item (Scout paraphrase) | Scout |
|---|---|---|---|
| PPWAF-OE-01 | [OE:01](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/fusion-culture) | Team specialisations are integrated into a fusion practice with clear decision making, responsibilities, continuous improvement and a blameless culture | Manual — questionnaire |
| PPWAF-OE-02 | [OE:02](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/formalize-operations-tasks) | Routine, as-needed and emergency operational tasks are formalised through documentation, checklists or automation | Manual — questionnaire |
| PPWAF-OE-03 | [OE:03](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/formalize-development-practices) | Ideation and planning follow a formal process with a common prioritised backlog and sufficiently detailed specifications | Manual — questionnaire |
| PPWAF-OE-04 | [OE:04](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/tools-processes) | Development and quality assurance practices are optimised and standardised across tooling, source control, design patterns, documentation and style guides | Manual — questionnaire |
| PPWAF-OE-05 | [OE:05](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/workload-supply-chain) | A workload supply chain drives changes through predictable, automated pipelines that test and promote across environments | Manual — questionnaire |
| PPWAF-OE-06 | [OE:06](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/observability) | A monitoring system captures and exposes operational telemetry, metrics and logs to validate design choices | Manual — questionnaire |
| PPWAF-OE-07 | [OE:07](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/emergency-response) | An emergency operations practice exists with health signals, actionable alerts and defined human responsibilities including on-call, incident management, emergency access and postmortems | Manual — questionnaire |
| PPWAF-OE-08 | [OE:08](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/automate-tasks) | Procedural tasks that do not benefit from human judgement are automated, preferring off-the-shelf automation, and automation is treated as a workload component | Manual — questionnaire |
| PPWAF-OE-09 | [OE:09](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/enable-automation) | Automation for lifecycle, governance and compliance guardrails is designed up front using platform features, not retrofitted | Manual — questionnaire |
| PPWAF-OE-10 | [OE:10](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/safe-deployments) | Safe deployment practices are defined: small, incremental, quality-gated releases that cover routine and emergency (hotfix) deployments | Manual — questionnaire |
| PPWAF-OE-11 | [OE:11](https://learn.microsoft.com/power-platform/well-architected/operational-excellence/mitigation-strategy) | A deployment failure mitigation strategy provides rapid recovery through rollback, feature disablement or native deployment-pattern capabilities | Manual — questionnaire |

### Performance Efficiency (PPWAF-PE) — 10 items

| # | Microsoft code | Item (Scout paraphrase) | Scout |
|---|---|---|---|
| PPWAF-PE-01 | [PE:01](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/performance-targets) | Numerical performance targets tied to workload requirements are defined for all workload flows | Manual — questionnaire |
| PPWAF-PE-02 | [PE:02](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/performance-planning) | Performance planning is done ahead of predicted changes in usage such as seasonal peaks, product updates, campaigns, events or regulatory changes | Manual — questionnaire |
| PPWAF-PE-03 | [PE:03](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/select-services) | Services and product features are selected to meet performance targets and expected capacity changes, weighing platform features against custom builds | Manual — questionnaire |
| PPWAF-PE-04 | [PE:04](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/collect-performance-data) | Automatic, continuous and meaningful performance metrics and logs are collected at application, platform, data and operating system levels | Manual — questionnaire |
| PPWAF-PE-05 | [PE:05](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/performance-test) | Performance is tested regularly in an environment that matches production and compared with targets and benchmarks | Manual — questionnaire |
| PPWAF-PE-06 | [PE:06](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/optimize-code) | Logic is performant and offloads responsibilities to the platform, used only when necessary and for its intended purpose | Manual — questionnaire |
| PPWAF-PE-07 | [PE:07](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/prioritize-critical-flows) | The performance of critical flows is prioritised when allocating resources and optimisation effort | Manual — questionnaire |
| PPWAF-PE-08 | [PE:08](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/optimize-data-performance) | Data usage is optimised so data stores fit their intended and actual use in the workload | Manual — questionnaire |
| PPWAF-PE-09 | [PE:09](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/respond-live-performance-issues) | A plan for live performance issues gives clear communication lines and responsibilities, captures lessons and returns to normal faster next time | Manual — questionnaire |
| PPWAF-PE-10 | [PE:10](https://learn.microsoft.com/power-platform/well-architected/performance-efficiency/continuous-performance-optimize) | Performance is optimised continuously, focusing on components whose performance deteriorates over time such as databases and networking | Manual — questionnaire |

### Experience Optimization (PPWAF-XO) — 10 items

| # | Microsoft code | Item (Scout paraphrase) | Scout |
|---|---|---|---|
| PPWAF-XO-01 | [XO:01](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/user-centered-design) | The workload is designed to meet users' expectations and requirements and provides a positive, useful experience | Manual — questionnaire |
| PPWAF-XO-02 | [XO:02](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/design-standards) | Established standards, conventions, guidelines and common design patterns are followed, with consistent design elements, terminology and interactions | Manual — questionnaire |
| PPWAF-XO-03 | [XO:03](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/information-architecture) | A consistent information architecture is implemented, with consistent navigation, contextual clues, visual indicators and user-friendly labels | Manual — questionnaire |
| PPWAF-XO-04 | [XO:04](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/usability) | Ease of use is prioritised, minimising user effort, maximising task efficiency and streamlining complex processes | Manual — questionnaire |
| PPWAF-XO-05 | [XO:05](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/feedback-guidance) | Notifications and messages give meaningful, useful and simple guidance, feedback on actions and next steps | Manual — questionnaire |
| PPWAF-XO-06 | [XO:06](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/layout) | Layouts are optimised for different contexts and devices and remain usable across screen sizes and resolutions | Manual — questionnaire |
| PPWAF-XO-07 | [XO:07](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/visual-design) | User perception and aesthetics are optimised with visually appealing, engaging experiences | Manual — questionnaire |
| PPWAF-XO-08 | [XO:08](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/interaction-design) | Interaction design best practices help users complete tasks and keep context | Manual — questionnaire |
| PPWAF-XO-09 | [XO:09](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/user-interface-content) | Interface content is task-focused, professional in tone and gives clear direction | Manual — questionnaire |
| PPWAF-XO-10 | [XO:10](https://learn.microsoft.com/power-platform/well-architected/experience-optimization/conversation-design) | Conversations are designed around users' needs and the AI's objectives, with clear capabilities, natural interactions and fallback mechanisms | Manual — questionnaire |

XO:10 applies only to workloads with conversational AI; answer N/A otherwise and it is left out of the score.

## What an automated version would need

Authentication is a different permission surface from the Azure Resource Manager Reader role every other
Scout rule reads through: the Power Platform API takes a token for `https://api.powerplatform.com/.default`
issued to a Microsoft Entra app registration, and the admin PowerShell module signs in as a Power Platform
administrator. An automated version would therefore be opt-in, like `-IncludeDevOps`, and every rule
reading it would be gated so "switch off" or "no access" reads Not assessed rather than "nothing is
configured".

These are the sources that would answer the most items, with the names as they appear on Microsoft Learn today.
A source is only useful where it can show a setting or an inventory. Items about team practice (OE-01, OE-03, SE-02,
XO-01 to XO-09 and most of PE) will stay questionnaire items whatever is collected.

| Source | What it would show | Items it would answer or inform |
|---|---|---|
| Power Platform API, `EnvironmentManagement` namespace (`EnvironmentManagement.Environments.Read`, `.Groups.Read`, `.Settings.Read`; REST `https://api.powerplatform.com/environmentmanagement/...`) | Environments with type, region and group membership; environment groups; environment management settings; managed-governance state; backups; business continuity (failover) state | SE-04 (segmentation), OE-05 and OE-10 (separate stages), RE-07 (backup and disaster recovery state), SE-01 (settings against a baseline) |
| Power Platform API, `Governance` namespace (rule-based policies, environment group rule assignments) | Governance rules applied to environment groups | SE-01, OE-09 (guardrails planned up front) |
| Power Platform API, `Security` namespace (`Security.Recommendations.Read`) and the admin centre Security overview score | Tenant security recommendations and score | SE-01, SE-08 |
| Power Platform API, `Analytics` namespace (`Analytics.AdvisorRecommendations.Read`) and the Power Platform for Admins V2 connector (`Get Recommendations`) | Admin centre recommended actions | OE-06, PE-10, RE-08 |
| Admin PowerShell module `Microsoft.PowerApps.Administration.PowerShell`: `Get-DlpPolicy`, `Get-AdminDlpPolicy` | Data policies, connector classification and scope | SE-04, SE-05, SE-07 (connectors that carry credentials) |
| Admin PowerShell `Get-TenantSettings`, `Get-AdminPowerAppEnvironment` (managed-environment `governanceConfiguration`) | Tenant settings; whether each environment is managed | SE-01, SE-04, OE-09 |
| Power Platform API, `PowerApps.Apps.Read` and `PowerAutomate.Flows.Read`; `Authorization.RoleAssignments.Read` | Inventory of apps and flows with owners; Power Platform role assignments | SE-05, OE-02, OE-08, RE-02 (what flows exist to be rated) |
| Dataverse Web API, per environment: `solution`, `environmentvariabledefinition` and `connectionreference` tables (the `ismanaged` column shows managed or unmanaged) | Whether assets sit in solutions, managed versus unmanaged, use of environment variables and connection references | OE-04, OE-05, OE-10 |
| Microsoft Purview audit log (Power Platform activity logging) | Admin and maker activity, connector events, data policy events | SE-08, OE-06, OE-07 |
| Microsoft Graph: Entra Conditional Access policies (already read by Scout's Entra inventory, not yet in `collect.json`) | Whether Power Platform sign-in is covered by conditional access and MFA | SE-05 |
| Azure Resource Graph (Scout already reads this) | Application Insights components and Log Analytics workspaces that Power Platform could be exporting to; they are visible, but nothing links them to a Power Platform environment without the admin API | RE-08, OE-06, PE-04 |

The Power Platform API reference states that the management plane is being brought to parity with the admin centre
and that new features will be API-first. Some of these APIs are marked preview on Learn today, so each would need
its current status confirmed before a rule relied on it.
