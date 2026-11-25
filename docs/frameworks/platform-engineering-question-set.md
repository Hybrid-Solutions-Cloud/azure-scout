# Platform Engineering — enumerated source for the Platform Engineering Technical Assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `platform.engineering.yaml` scores the capability model behind Microsoft's
[Platform Engineering Technical Assessment](https://learn.microsoft.com/en-us/assessments/86bf5228-7b58-4854-b932-ac71402e0be4/).
The assessment is mostly organisational: it asks how staff and funds are allocated to the platform,
how teams find and adopt it, how policy and access are governed, how resources are provisioned,
what interfaces users get, and how success is measured. This page lists the items Scout asks, and
every rule in that file cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Platform Engineering Technical Assessment](https://learn.microsoft.com/en-us/assessments/86bf5228-7b58-4854-b932-ac71402e0be4/) (60 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Platform Engineering Capability Model on Microsoft Learn (six capabilities: investment, adoption, governance, provisioning and management, interfaces, measurement and feedback; five stages: Initial, Repeatable, Defined, Managed, Optimized). Not versioned by Microsoft, current at the extraction date |
| Extraction date | 2026-11-25 |
| Verification method | The assessment landing page and the platform engineering hub page were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. The six capability pages and the principles, self-service, plan and application-platform pages were read through `microsoft_docs_search` excerpts of their stage tables and key sections the same day. Every `collect.json` property an automated item reads was checked against the header contract in `src/collect/Invoke-Collect.ps1`. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published; its landing
page gives only the length, format and a promise of tailored recommendations. The items below are
**Scout's** reading of the published capability model, and the `PLATENG-*` IDs are Scout's.

The model places an organization at one of five stages for each capability. A stage is a description
of how the organization works, so Scout does not try to name one. Each item is instead a practice
the model describes, written so it can be answered Yes, Partial or No, and the score is the share
of items met, not a stage per capability.

Sources:

- [MODEL] [Use the Platform Engineering Capability Model](https://learn.microsoft.com/platform-engineering/platform-engineering-capability-model)
- [INV] [Investment: Allocate budget and demonstrate ROI](https://learn.microsoft.com/platform-engineering/investment)
- [ADO] [Adoption: Services, tools, and technologies](https://learn.microsoft.com/platform-engineering/adoption)
- [GOV] [Governance: Security and compliance policies](https://learn.microsoft.com/platform-engineering/governance)
- [PRV] [Provisioning and management](https://learn.microsoft.com/platform-engineering/provisioning-management)
- [INT] [Interfaces: Streamline provisioning and service requests](https://learn.microsoft.com/platform-engineering/interfaces)
- [MFB] [Measurement and feedback: Establish feedback loops](https://learn.microsoft.com/platform-engineering/measurement-feedback)
- [PRIN] [Platform engineering principles](https://learn.microsoft.com/platform-engineering/about/principles)
- [SELF] [Self-service with guardrails to empower developers](https://learn.microsoft.com/platform-engineering/about/self-service)
- [PLAN] [Plan and prioritize](https://learn.microsoft.com/platform-engineering/plan)
- [APPP] [Refine your application platform](https://learn.microsoft.com/platform-engineering/application-platform)
- [ENGS] [Apply software engineering systems](https://learn.microsoft.com/platform-engineering/engineering-systems)
- [DSS] [Design a developer self-service foundation](https://learn.microsoft.com/platform-engineering/developer-self-service)
- [CASE] [Case studies: Three platform engineering implementations](https://learn.microsoft.com/platform-engineering/case-study)

## How the items are answered

Most items are questions about how the organization works, which no Azure API can read. They are
**manual** rules: Scout lists them in `assessment-questions.csv` (or `Export-ScoutAssessmentQuestion`),
and a person answers `Yes`, `Partial`, `No` or `N/A`. See
[Questionnaire answers](../assessment/questionnaire-answers.md). Where collected Azure data bears on
a question, it is attached to the item as evidence, but the answer still decides the score. Items
marked ✅ are **automated** and **gated**: they run only when the resources they read exist (or the
data source was collected), so an estate without them reports the item Not assessed, never Passed
or Failed, and an answer file cannot override them.

## The enumeration — 36 items across 6 areas

### Investment (PLATENG-INV) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| PLATENG-INV-01 | Budget and people are deliberately allocated to maintain common platform capabilities, not left to voluntary effort | ❌ Manual | INV |
| PLATENG-INV-02 | The platform team is run like a product team, with product management, design, research and content roles alongside engineering | ❌ Manual | INV |
| PLATENG-INV-03 | A product roadmap, built from requirements gathered across engineering teams, sets the scope and priorities of the platform | ❌ Manual | INV, PLAN |
| PLATENG-INV-04 | Return on the platform investment is shown with measures beyond delivery speed, such as developer satisfaction and business outcomes | ❌ Manual | INV |
| PLATENG-INV-05 | Teams outside the platform team, engineering and non-engineering, have explicit funding to contribute to the platform | ❌ Manual | INV |

### Adoption (PLATENG-ADO) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| PLATENG-ADO-01 | Engineering teams can discover the platform's services, tools and technologies from a catalogue or portal, not by word of mouth | ❌ Manual — Dev Center catalogs and environment types attached | ADO, PRIN |
| PLATENG-ADO-02 | The platform states the value of each capability, and teams choose it over building their own rather than because it is mandated | ❌ Manual | ADO |
| PLATENG-ADO-03 | Use of platform capabilities is supported by templates, documentation, support forums and a clear route to help | ❌ Manual | ADO |
| PLATENG-ADO-04 | Internal advocates (champions, ambassadors, developer advocates) run an internal user community around the platform | ❌ Manual | ADO |
| PLATENG-ADO-05 | Engineering teams can contribute fixes and features back to the platform through reviewed pull requests | ❌ Manual | ADO |

### Governance (PLATENG-GOV) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| PLATENG-GOV-01 | Security, compliance and remediation policies are defined, centrally managed and documented for every team | ❌ Manual | GOV |
| PLATENG-GOV-02 | Security and compliance policies are implemented as Azure Policy assignments | ✅ Azure Policy assignments (needs an Azure Policy read) | GOV, APPP |
| PLATENG-GOV-03 | Assigned Azure policies are enforced rather than left in audit-only (DoNotEnforce) mode | ✅ assignments with `enforcementMode` DoNotEnforce | GOV, APPP |
| PLATENG-GOV-04 | Policy is managed as code: stored in version control, reviewed, tested and rolled out in rings | ❌ Manual | APPP |
| PLATENG-GOV-05 | Threats and policy violations are monitored, audited and corrected through a defined process | ❌ Manual | GOV |
| PLATENG-GOV-06 | Access to platform resources follows a formal role-based model aligned to job functions, with access provisioned through automation | ❌ Manual | GOV |
| PLATENG-GOV-07 | Access is granted through groups and roles rather than to many individual users | ✅ role assignments to individual users, fewer than 50 | GOV |
| PLATENG-GOV-08 | Cost is governed: budgets exist for the subscriptions the platform serves | ✅ budgets (needs a Cost Management read) | GOV |
| PLATENG-GOV-09 | Data and intellectual property are governed, including classification, licensing and code ownership | ❌ Manual | MODEL |

### Provisioning and management (PLATENG-PRV) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| PLATENG-PRV-01 | Infrastructure is provisioned from infrastructure-as-code templates, not by hand in the portal | ✅ deployment records with a template hash | PRV, SELF |
| PLATENG-PRV-02 | Delivery pipelines are defined as code (YAML) rather than built in the classic editor | ✅ Azure DevOps pipelines defined as YAML (needs -IncludeDevOps) | PRV, ENGS |
| PLATENG-PRV-03 | Provisioning requests follow a structured workflow with paved paths (golden paths) and approvals only where needed | ❌ Manual | PRV |
| PLATENG-PRV-04 | Provisioning is automated inside CI/CD pipelines, with governance and compliance checks built into the workflow | ❌ Manual | PRV |
| PLATENG-PRV-05 | Teams create standardized, preconfigured environments themselves, within controlled limits | ❌ Manual — Dev Center catalogs and environment types attached | PRV, SELF |
| PLATENG-PRV-06 | Resource allocation and use are visible on central dashboards, and scaling is automated from usage patterns | ❌ Manual — Azure Monitor autoscale settings attached | PRV |

### Interfaces (PLATENG-INT) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| PLATENG-INT-01 | Consistent, standard interfaces exist to provision and observe platform capabilities, with golden paths documented as templates | ❌ Manual — Dev Center and project resources attached | INT |
| PLATENG-INT-02 | Development environments are set up through the platform from a common path, not assembled by each team | ❌ Manual — Dev Box pools attached | INT |
| PLATENG-INT-03 | Tools to observe and diagnose deployed resources are provided on demand through the platform | ❌ Manual — Application Insights components attached | INT |
| PLATENG-INT-04 | An inventory or service catalogue lets users find assets and avoid duplicating them | ❌ Manual | PRIN, DSS |

### Measurement and feedback (PLATENG-MFB) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| PLATENG-MFB-01 | Platform success is measured with value-centric metrics tied to business goals, not only activity counts | ❌ Manual | MFB |
| PLATENG-MFB-02 | Software delivery performance of platform users (deployment frequency, lead time, change failure rate, time to restore) is measured | ❌ Manual | MFB, CASE |
| PLATENG-MFB-03 | User feedback is collected through structured mechanisms built into the platform, not only ad hoc | ❌ Manual | MFB |
| PLATENG-MFB-04 | Feedback is analysed and correlated with performance metrics to drive the platform roadmap | ❌ Manual | MFB |
| PLATENG-MFB-05 | Executives, platform users and product teams all take part in feedback loops | ❌ Manual | MFB |
| PLATENG-MFB-06 | Lessons learned and platform documentation are kept current and shared with all stakeholders | ❌ Manual | MFB |
| PLATENG-MFB-07 | Platform goals are set as objectives and key results (OKRs) agreed with leadership and scoped to business objectives | ❌ Manual | PLAN |

## Summary

| Area | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Investment | 5 | 0 | 5 |
| Adoption | 5 | 0 | 5 |
| Governance | 9 | 4 | 5 |
| Provisioning and management | 6 | 2 | 4 |
| Interfaces | 4 | 0 | 4 |
| Measurement and feedback | 7 | 0 | 7 |
| **Total** | **36** | **6** | **30** |

Only six of the 36 items can be judged from Azure data, and those only partly: Azure Policy
assignments and their enforcement mode, direct user role assignments, budgets, infrastructure-as-code
deployment records and YAML pipelines. Azure DevOps items need `-IncludeDevOps`; Azure Policy, role
assignment and budget items need those reads to have succeeded. Dev Center catalogs, Dev Box pools,
Application Insights and autoscale settings are attached to some questions as evidence only, because
a platform can be built on other tools and their absence proves nothing.
