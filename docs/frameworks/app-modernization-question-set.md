# App and Data Modernization — enumerated source for the App and Data Modernization Readiness Tool

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `appmod.readiness.yaml` scores the readiness factors behind Microsoft's
[App and Data Modernization Readiness Tool](https://learn.microsoft.com/en-us/assessments/50adbf76-60fb-47ce-a787-f9d5f52f6a48/).
The guidance says an organization is only as ready as its people, infrastructure, development
processes, data management, application estate and operations. This page lists the items Scout
asks, and every rule in that file cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [App and Data Modernization Readiness Tool](https://learn.microsoft.com/en-us/assessments/50adbf76-60fb-47ce-a787-f9d5f52f6a48/) (30 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Microsoft Azure App Modernization Guidance on Microsoft Learn, current at the extraction date. Not versioned by Microsoft |
| Extraction date | 2026-11-25 |
| Verification method | The assessment landing page and the guidance home, "Are you ready for application and data modernization?", maturity model, "Make an inventory and collect data", "Identity, security, and compliance best practices" and "The 6 Rs" pages were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Every `collect.json` property an automated item reads was checked against the header contract in `src/collect/Invoke-Collect.ps1`. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published. The items
below are **Scout's** reading of the readiness guidance, mainly the "Are you ready for application
and data modernization?" page, whose sections (organizational maturity, infrastructure, process,
data management, application estate, AI adoption and operations) set the areas used here. The
`APPMOD-*` IDs are Scout's.

The guidance also describes four maturity categories (traditional foundations, emerging pioneers,
agile innovators, digital champions). Scout asks whether the organization knows which it is in but
does not assign one, because the category depends on business readiness that Azure data cannot show.
The score is the share of items met.

Sources:

- [READY] [Are you ready for application and data modernization?](https://learn.microsoft.com/azure/app-modernization-guidance/assess/are-you-ready-for-application-and-data-modernization)
- [MAT] [Application modernization maturity model](https://learn.microsoft.com/azure/app-modernization-guidance/get-started/application-modernization-maturity-model)
- [INVN] [Make an inventory and collect data](https://learn.microsoft.com/azure/app-modernization-guidance/assess/make-an-inventory-and-collect-data)
- [PLAN6] [The 6 Rs of application modernization](https://learn.microsoft.com/azure/app-modernization-guidance/plan/the-6-rs-of-application-modernization)
- [LAUNCH] [Identity, security, and compliance best practices](https://learn.microsoft.com/azure/app-modernization-guidance/launch/identity-security-and-compliance-best-practices)

## How the items are answered

Most items are questions about how the organization works, which no Azure API can read. They are
**manual** rules: Scout lists them in `assessment-questions.csv` (or `Export-ScoutAssessmentQuestion`),
and a person answers `Yes`, `Partial`, `No` or `N/A`. See
[Questionnaire answers](../assessment/questionnaire-answers.md). Where collected Azure data bears on
a question, it is attached to the item as evidence, but the answer still decides the score. Items
marked ✅ are **automated** and **gated**: they run only when the resources they read exist (or the
data source was collected), so an estate without them reports the item Not assessed, never Passed
or Failed, and an answer file cannot override them.

## The enumeration — 62 items across 9 areas

### Organizational maturity and skills (APPMOD-ORG) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-ORG-01 | Developer teams' maturity in tools, culture and processes has been assessed, for example with the Developer Velocity Index, and the gaps are tracked | ❌ Manual | READY |
| APPMOD-ORG-02 | The organization knows which application modernization maturity category it is in (traditional foundations, emerging pioneers, agile innovators, digital champions) and plans work to match | ❌ Manual | MAT |
| APPMOD-ORG-03 | Stakeholders are aligned on modernization goals, scope and the order of work | ❌ Manual | MAT, READY |
| APPMOD-ORG-04 | Team skills are assessed regularly, and training closes the gaps in modern tools and platforms | ❌ Manual | READY |

### Estate inventory and assessment (APPMOD-INV) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-INV-01 | A complete inventory lists every application, database and infrastructure component, on-premises and in the cloud, with its purpose, usage and dependencies | ❌ Manual — Azure virtual machines attached | INVN |
| APPMOD-INV-02 | Dependencies among applications, databases and services are mapped | ❌ Manual | INVN |
| APPMOD-INV-03 | Application binaries and source code are assessed for cloud readiness, for example with Azure Migrate application and code assessment (AppCAT) | ❌ Manual | INVN |
| APPMOD-INV-04 | Data is classified by sensitivity, compliance requirements and business value | ❌ Manual | INVN |
| APPMOD-INV-05 | A security baseline exists, such as the Defender for Cloud secure score, with prioritized recommendations | ❌ Manual — Defender for Cloud secure scores attached | INVN |
| APPMOD-INV-06 | Regulatory and compliance requirements are identified before modernization plans are made, with evidence of compliance activities kept | ❌ Manual | INVN |
| APPMOD-INV-07 | A cost baseline exists (total cost of ownership) for current environments, with savings opportunities identified | ❌ Manual | INVN |

### Infrastructure and network readiness (APPMOD-INF) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-INF-01 | Current hardware and software can support modern applications and AI workloads | ❌ Manual | READY |
| APPMOD-INF-02 | Infrastructure can scale to meet future demand | ❌ Manual — Azure Monitor autoscale settings attached | READY |
| APPMOD-INF-03 | Network bandwidth and latency can handle the traffic and latency needs of modern applications | ❌ Manual — ExpressRoute circuits attached | READY |
| APPMOD-INF-04 | Redundant network paths provide high availability | ❌ Manual — VPN connections attached | READY |
| APPMOD-INF-05 | Network security measures protect applications and data | ❌ Manual — Azure Firewall policies attached | READY |
| APPMOD-INF-06 | The organization is ready for a hybrid cloud setup, with some resources on-premises and some in the cloud | ❌ Manual — Azure Arc-enabled servers attached | READY |
| APPMOD-INF-07 | Infrastructure is deployed through automation (infrastructure as code) instead of manual changes | ✅ deployment records with a template hash | READY |
| APPMOD-INF-08 | Monitoring tools track the performance, availability and security of infrastructure, and no resource type is left without diagnostics | ✅ diagnostic coverage by resource type | READY |

### Process readiness (APPMOD-PRC) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-PRC-01 | Source code is held in version-controlled repositories | ✅ Azure DevOps Git repositories (needs -IncludeDevOps) | READY |
| APPMOD-PRC-02 | A branching strategy, frequent commits and pull requests are standard practice | ❌ Manual | READY |
| APPMOD-PRC-03 | A code review process checks quality, consistency and adherence to best practice | ❌ Manual | READY |
| APPMOD-PRC-04 | Semantic versioning and a change log are maintained | ❌ Manual | READY |
| APPMOD-PRC-05 | Builds and deployments run through automated CI/CD pipelines | ✅ Azure DevOps pipelines (needs -IncludeDevOps) | READY |
| APPMOD-PRC-06 | Automated unit, integration and end-to-end tests run in the pipeline | ❌ Manual — Azure Playwright Testing resources attached | READY |
| APPMOD-PRC-07 | Monitoring and alerting track application performance and health after deployment | ❌ Manual — Application Insights components attached | READY |

### Data readiness (APPMOD-DAT) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-DAT-01 | Data sources, types, volumes and storage locations are known | ❌ Manual — Azure SQL databases attached | READY |
| APPMOD-DAT-02 | Data quality (accuracy, completeness, consistency) is evaluated and managed with cleansing and validation | ❌ Manual | READY |
| APPMOD-DAT-03 | Data governance policies cover data security, privacy and compliance | ❌ Manual | READY |
| APPMOD-DAT-04 | A modern data infrastructure with data lakes and warehouses makes structured and unstructured data available at scale | ❌ Manual — Azure Synapse workspaces attached | READY |
| APPMOD-DAT-05 | Real-time data processing is available where applications and models need timely data | ❌ Manual — Azure Stream Analytics jobs attached | READY |
| APPMOD-DAT-06 | Data can be integrated across systems and platforms | ❌ Manual — Azure Data Factory instances attached | READY |
| APPMOD-DAT-07 | The data migration plan includes cleansing, transformation and validation, and a target on modern platforms such as Azure SQL Database or PostgreSQL flexible server | ❌ Manual — Azure SQL servers attached | READY, INVN |
| APPMOD-DAT-08 | SQL servers do not allow public network access | ✅ SQL server `publicNetworkAccess` | READY, LAUNCH |
| APPMOD-DAT-09 | Microsoft Defender for SQL is enabled at the Standard tier | ✅ Defender for SQL pricing tier | READY |

### Application estate readiness (APPMOD-APP) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-APP-01 | Application health is measured (response times, error rates, resource use), and under-performing applications are identified | ❌ Manual — Application Insights components attached | READY |
| APPMOD-APP-02 | Each application's technology stack (languages, frameworks, databases) is reviewed for compatibility with modern platforms | ❌ Manual — Azure virtual machines attached | READY |
| APPMOD-APP-03 | Licensing agreements and support contracts for existing applications are reviewed | ❌ Manual — Azure virtual machines attached | READY |
| APPMOD-APP-04 | Applications are prioritized for modernization by business value and effort, for example with an Eisenhower matrix, with stakeholder pain points gathered | ❌ Manual | READY |
| APPMOD-APP-05 | A modernization strategy (rehost, replatform, refactor, rebuild, retire or retain) is chosen and evaluated for each application | ❌ Manual | PLAN6 |
| APPMOD-APP-06 | Applications move to PaaS or container platforms (App Service, Functions, AKS) where that improves scalability and management | ❌ Manual — App Service web apps attached | MAT, PLAN6 |
| APPMOD-APP-07 | App Service web apps accept HTTPS only | ✅ App Service `httpsOnly` | LAUNCH |
| APPMOD-APP-08 | App Service web apps require TLS 1.2 or later | ✅ App Service `minTlsVersion` | LAUNCH |

### AI readiness (APPMOD-AIR) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-AIR-01 | A responsible AI approach (transparency, accountability, fairness) is defined, with governance and oversight to mitigate bias | ❌ Manual | READY |
| APPMOD-AIR-02 | The choice between model training and retrieval-augmented generation (RAG) is made for each use case | ❌ Manual — Azure AI Search services attached | READY |
| APPMOD-AIR-03 | Machine learning operations (MLOps) streamline deployment, monitoring and management of AI models | ❌ Manual — Azure Machine Learning workspaces attached | READY |
| APPMOD-AIR-04 | Model versioning tracks changes and supports reproducibility and compliance | ❌ Manual | READY |
| APPMOD-AIR-05 | Data used with AI is protected with encryption, access controls and continuous monitoring | ❌ Manual — Azure AI services accounts attached | READY |
| APPMOD-AIR-06 | An API management solution exposes data and services securely to approved applications | ✅ API Management instances | READY |
| APPMOD-AIR-07 | Data drift is monitored, and models are retrained and updated when it occurs | ❌ Manual | READY |

### Operational readiness (APPMOD-OPS) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-OPS-01 | Continuous integration, continuous delivery, automation and continuous monitoring are adopted as DevOps practice | ❌ Manual | READY |
| APPMOD-OPS-02 | An incident response plan documents how to handle outages, and a post-incident review leads to preventive action | ❌ Manual — Azure Monitor action groups attached | READY |
| APPMOD-OPS-03 | A change control board (or an equivalent process) reviews significant changes and keeps detailed change logs | ❌ Manual | READY |
| APPMOD-OPS-04 | Teams can experiment, learn from failure and make small continuous improvements, using Agile methods such as Scrum or Kanban | ❌ Manual | READY |
| APPMOD-OPS-05 | Reliability and availability practices are applied to applications and services | ❌ Manual — Recovery Services vaults attached | READY |
| APPMOD-OPS-06 | Security is built into development and deployment (DevSecOps) | ❌ Manual | READY |
| APPMOD-OPS-07 | Compliance with industry regulations and standards is ensured | ❌ Manual | READY |

### Identity, security and compliance (APPMOD-SEC) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| APPMOD-SEC-01 | Applications use single sign-on with Microsoft Entra ID as the single source of identity | ❌ Manual | LAUNCH |
| APPMOD-SEC-02 | Multifactor authentication and Conditional Access protect all single sign-on integrations | ❌ Manual | LAUNCH |
| APPMOD-SEC-03 | Hybrid identity gives users one set of credentials across on-premises and cloud resources | ❌ Manual | LAUNCH |
| APPMOD-SEC-04 | Azure Policy assignments enforce organizational standards | ✅ Azure Policy assignments (needs an Azure Policy read) | LAUNCH |
| APPMOD-SEC-05 | Entra audit logs and reports are monitored to detect anomalies | ❌ Manual | LAUNCH |

## Summary

| Area | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Organizational maturity and skills | 4 | 0 | 4 |
| Estate inventory and assessment | 7 | 0 | 7 |
| Infrastructure and network readiness | 8 | 2 | 6 |
| Process readiness | 7 | 2 | 5 |
| Data readiness | 9 | 2 | 7 |
| Application estate readiness | 8 | 2 | 6 |
| AI readiness | 7 | 1 | 6 |
| Operational readiness | 7 | 0 | 7 |
| Identity, security and compliance | 5 | 1 | 4 |
| **Total** | **62** | **10** | **52** |

Ten of the 62 items can be judged from Azure data, each only on the signal it names. Four need
data that is not always collected: Azure DevOps repositories and pipelines need `-IncludeDevOps`,
the policy assignment item needs the Azure Policy read, and the diagnostic coverage item needs the
coverage measurement. Resources Scout found (virtual machines, SQL servers, Application Insights and
so on) are attached to some questions as evidence of the Azure part of the estate only. On-premises
applications, source hosts other than Azure DevOps, Microsoft Entra settings and the organizational
questions are not visible to Scout and are left to the person answering.
