---
description: Every CAF, WAF and specialised assessment Azure Scout performs, with the rule files and rule counts behind each.
---

# Assessment Catalogue

Azure Scout ships **73 assessments** backed by **72 rule files** holding
**2020 rules**, of which **669 are evaluated automatically** and
**1351 require manual confirmation**.

Run one, several, or all of them:

```powershell
Invoke-AzureScout -TenantID '<guid>' -Assessment 'LandingZone'
Invoke-AzureScout -TenantID '<guid>' -Assessment 'WAF: Security','Assess: Networking'
Invoke-AzureScout -TenantID '<guid>' -Assessment 'All'
```

::: tip This page is generated
Regenerate it with `scripts/Build-AssessmentCatalog.ps1`. Rows and counts come from
`manifests/assessments.psd1` and `src/assess/rules/`; `tests/DocsAssessmentCatalog.Tests.ps1`
fails the build if the committed page and a fresh regeneration disagree. Do not hand-edit it.
:::

**40 of the 73 assessments ingest governance data** and therefore need ARM `Reader`
at the **tenant-root management group** to resolve fully; below that scope they degrade to an
explicit `Unknown` rather than a false zero. They are marked **Gov** in the tables below.
See [Auth & permissions per scan type](../assessment/assessment-permissions.md).

::: warning Manual rules are questions, not failures
A manual rule is one no collected data can decide — a process control, or a source Azure
does not expose. Unanswered, it is excluded from the score rather than counted as a failure.
Answered, it is scored: every run writes `assessment-questions.csv`, and `-AssessmentAnswers`
feeds the answers back. See [Questionnaire Answers](../assessment/questionnaire-answers.md).
:::

## Cloud Adoption Framework (11)

| Assessment | What it covers | Rules | Automated | Manual | Gov | Rule files |
|---|---|--:|--:|--:|:-:|---|
| **CAF: Azure billing and Microsoft Entra tenant** | CAF landing zone design area — Azure billing and Microsoft Entra ID tenant setup | 6 | 0 | 6 | **Gov** | `caf.billing` |
| **CAF: Azure Landing Zone** | CAF/WAF landing zone audit (all areas) | 93 | 60 | 33 | **Gov** | `caf.billing`<br>`caf.identity`<br>`caf.network`<br>`caf.resourceorg`<br>`caf.security`<br>`caf.management`<br>`caf.governance`<br>`caf.platformauto`<br>`waf.cost`<br>`waf.operational`<br>`waf.performance`<br>`waf.reliability`<br>`waf.security`<br>`xr.crossresource` |
| **CAF: Govern** | CAF Govern methodology -- 1-10 maturity score per risk category (regulatory compliance, security, cost, operations, data, resource management, AI) plus the governance process (team, risk register, policies, audits); radar + heatmap report. Replaces Microsoft's Cloud Governance assessment, retired January 2027 | 54 | 26 | 28 | **Gov** | `caf.govern.ai`<br>`caf.govern.cm`<br>`caf.govern.dg`<br>`caf.govern.op`<br>`caf.govern.proc`<br>`caf.govern.rc`<br>`caf.govern.rm`<br>`caf.govern.sc` |
| **CAF: Governance** | CAF landing zone design area — Governance (policy & compliance) | 7 | 4 | 3 | **Gov** | `caf.governance` |
| **CAF: Identity and access management** | CAF landing zone design area — Identity and access management | 7 | 4 | 3 | **Gov** | `caf.identity` |
| **CAF: Management** | CAF landing zone design area — Management (monitoring, operations baseline) | 6 | 5 | 1 | **Gov** | `caf.management` |
| **CAF: Migrate readiness** | CAF migration readiness across plan, prepare, execute, optimise and decommission -- CAF Plan + CAF Migrate, 49 rules (see docs/frameworks/smart-question-set.md) | 49 | 18 | 31 | **Gov** | `smart.migration` |
| **CAF: Network topology and connectivity** | CAF landing zone design area — Network topology and connectivity | 7 | 6 | 1 | **Gov** | `caf.network` |
| **CAF: Platform automation and DevOps** | CAF landing zone design area — Platform automation and DevOps | 6 | 2 | 4 | **Gov** | `caf.platformauto` |
| **CAF: Resource organization** | CAF landing zone design area — Resource organization (management groups, subscriptions, tags) | 6 | 4 | 2 | **Gov** | `caf.resourceorg` |
| **CAF: Security** | CAF landing zone design area — Security | 7 | 6 | 1 | **Gov** | `caf.security` |

## Well-Architected Framework (15)

| Assessment | What it covers | Rules | Automated | Manual | Gov | Rule files |
|---|---|--:|--:|--:|:-:|---|
| **WAF: Analytics** | Analytics technology review (Well-Architected guides for Azure Databricks, Event Hubs, Log Analytics and Microsoft Fabric) -- 74 items across all 5 pillars; see docs/frameworks/waf-analytics-checklist.md | 74 | 18 | 56 | **Gov** | `waf.analytics` |
| **WAF: Azure AI Search** | Azure AI Search technology review (no Microsoft service guide; Scout reading of the product reliability, security, cost and performance articles) -- 37 items across all 5 pillars; tier, replicas, public access, private endpoints, key authentication | 37 | 8 | 29 | **Gov** | `waf.aisearch` |
| **WAF: Azure Local** | Well-Architected Framework — Azure Local (platform 2311+ and Azure Local VMs) workload review | 33 | 7 | 26 | **Gov** | `waf.azurelocal.cost`<br>`waf.azurelocal.operational`<br>`waf.azurelocal.performance`<br>`waf.azurelocal.reliability`<br>`waf.azurelocal.security` |
| **WAF: Azure Machine Learning** | Azure Machine Learning technology review (Well-Architected service guide) -- 44 items across all 5 pillars; workspace network isolation, public access, private endpoints, identity; see docs/frameworks/waf-machine-learning-checklist.md | 44 | 6 | 38 | **Gov** | `waf.machinelearning` |
| **WAF: Cost Optimization** | Well-Architected Framework — Cost Optimization pillar only | 9 | 6 | 3 | **Gov** | `waf.cost` |
| **WAF: Data Services** | Data Services technology review (Well-Architected guides for Azure SQL Database, SQL Managed Instance, Cosmos DB, PostgreSQL, MySQL, Azure Managed Redis, HorizonDB and Blob Storage) -- 104 items across all 5 pillars; see docs/frameworks/waf-data-services-checklist.md | 104 | 49 | 55 | **Gov** | `waf.dataservices` |
| **WAF: Go-Live** | Go-live readiness review -- 57 launch-gate items from the five Well-Architected design review checklists (SLOs and DR, security baseline, monitoring and alerting, cost guardrails, safe deployment, performance). Microsoft publishes only a landing page for its Go-Live assessment, so this is Scout's own review, not comparable to it | 57 | 35 | 22 | **Gov** | `waf.golive` |
| **WAF: Maturity Model** | Well-Architected Framework — maturity levels per pillar (same rules as the five WAF pillar assessments, different output framing) | 35 | 23 | 12 | **Gov** | `waf.reliability`<br>`waf.security`<br>`waf.cost`<br>`waf.operational`<br>`waf.performance` |
| **WAF: Mission Critical** | Mission-critical workload review -- 81 items across the 8 design areas of Microsoft's mission-critical guidance (application design, platform, data platform, networking, health modeling, deployment and testing, security, operations); 41 scored from collected data, 40 questionnaire items. Scout's reading of the guidance; Microsoft does not publish the assessment's questions | 81 | 41 | 40 | **Gov** | `waf.missioncritical` |
| **WAF: Operational Excellence** | Well-Architected Framework — Operational Excellence pillar only | 6 | 4 | 2 | **Gov** | `waf.operational` |
| **WAF: Performance Efficiency** | Well-Architected Framework — Performance Efficiency pillar only | 6 | 4 | 2 | **Gov** | `waf.performance` |
| **WAF: Reliability** | Well-Architected Framework — Reliability pillar only | 7 | 4 | 3 | **Gov** | `waf.reliability` |
| **WAF: Security** | Well-Architected Framework — Security pillar only | 7 | 5 | 2 | **Gov** | `waf.security` |
| **WAF: Service Guides** | Well-Architected Framework service guides -- 214 items (126 automated) from the Configuration recommendations of 20 Azure service guides: AKS, App Service, Functions, Container Apps, API Management, Service Bus, Event Grid, Firewall, Application Gateway, Load Balancer, Virtual Network, Virtual Machines and scale sets, Disk, Application Insights, Front Door, Traffic Manager, Virtual WAN, ExpressRoute, Files and NetApp Files. A guide is assessed only when the estate has that service; see docs/frameworks/waf-service-guides-checklist.md | 214 | 130 | 84 |  | `waf.serviceguides` |
| **WAF: Sustainability** | Sustainability workload review -- 67 items from the five pillar sustainability recommendation pages and sustainable AI design; idle and orphaned resources, autoscale, edge protections and Advisor cost findings are scored, carbon and application-efficiency items are questionnaire items. Scout's reading of the guidance | 67 | 20 | 47 | **Gov** | `waf.sustainability` |

## Service category slices (18)

| Assessment | What it covers | Rules | Automated | Manual | Gov | Rule files |
|---|---|--:|--:|--:|:-:|---|
| **Assess: AI** | AI/Cognitive private access and responsible-AI posture | 5 | 4 | 1 |  | `caf.ai` |
| **Assess: AI Workload** | AI workload review (Well-Architected Framework AI workload guidance) -- all 10 AI design areas: 35 Microsoft-tabled items plus Scout-derived items for Data platform, Testing and evaluation, Workload personas and the AI architecture pattern (63 rules, mostly questionnaire items); see docs/frameworks/waf-ai-workload-checklist.md | 63 | 9 | 54 | **Gov** | `waf.ai` |
| **Assess: Analytics** | Analytics data governance and network isolation | 5 | 3 | 2 |  | `caf.analytics` |
| **Assess: AVD Workload** | AVD-on-Azure-Local workload review (Well-Architected Framework) -- 20 items across all 5 pillars; scoped to AVD deployed on Azure Local, not general Azure Virtual Desktop | 20 | 6 | 14 |  | `waf.avd` |
| **Assess: Compliance** | Regulatory compliance — scores every Azure Policy regulatory-compliance initiative assigned in the scanned scope (MCSB, CIS, ISO 27001, NIST, PCI-DSS, ...) from compliance state Azure already evaluated | — | — | — |  | `compliance.initiative` |
| **Assess: Compute** | VM resilience, zones, backup, right-size, orphans | 22 | 14 | 8 |  | `waf.reliability`<br>`waf.cost`<br>`waf.performance` |
| **Assess: Containers** | AKS private clusters, RBAC, registry hardening | 8 | 7 | 1 |  | `caf.containers` |
| **Assess: Databases** | SQL/DB private access, TDE, zone redundancy | 7 | 4 | 3 |  | `caf.databases` |
| **Assess: Hybrid** | Arc onboarding, agent currency, Azure Local | 6 | 4 | 2 |  | `caf.hybrid` |
| **Assess: Identity** | Identity & access — PIM, Conditional Access, RBAC | 7 | 4 | 3 | **Gov** | `caf.identity` |
| **Assess: Integration** | Messaging redundancy and APIM network isolation | 6 | 6 | 0 |  | `caf.integration` |
| **Assess: IoT** | IoT Hub/DPS network isolation and device auth | 13 | 8 | 5 |  | `caf.iot` |
| **Assess: Management** | Governance, policy, cost, backup, automation, update manager | 19 | 9 | 10 | **Gov** | `caf.governance`<br>`caf.management`<br>`caf.billing` |
| **Assess: Monitor** | Monitoring, alerting, diagnostics coverage | 12 | 9 | 3 |  | `caf.management`<br>`waf.operational` |
| **Assess: Networking** | Network topology, firewall, DDoS, exposure, private link | 7 | 6 | 1 |  | `caf.network` |
| **Assess: Security** | Defender, Key Vault, secure score, exposure | 14 | 11 | 3 |  | `caf.security`<br>`waf.security` |
| **Assess: Storage** | Storage public access, TLS, encryption, redundancy | 6 | 5 | 1 |  | `caf.storage` |
| **Assess: Web** | App Service HTTPS-only, TLS, managed identity | 6 | 5 | 1 |  | `caf.web` |

## Specialised and workload assessments (29)

| Assessment | What it covers | Rules | Automated | Manual | Gov | Rule files |
|---|---|--:|--:|--:|:-:|---|
| **Microsoft: AI Readiness** | AI Readiness Assessment -- 64 Scout-derived items (53 questionnaire items, 11 automated checks) across Microsoft's seven pillars: Business Strategy, AI Governance & Security, Data Foundations, AI Strategy & Experience, Organization & Culture, Infrastructure for AI, Model Management. Microsoft does not publish the questions; items are Scout's reading of the CAF AI adoption and AI agent guidance | 64 | 11 | 53 | **Gov** | `ai.readiness` |
| **Microsoft: Analytics Journey Tracker** | Analytics Journey Tracker -- data and analytics capability against the CAF unified data platform guidance and the Microsoft Fabric adoption roadmap, 52 items in 7 areas; Scout-derived questions and areas (Microsoft names five maturity levels but publishes neither pillars nor questions). 47 are questionnaire items; 5 check Data Factory and Synapse settings | 52 | 5 | 47 |  | `analytics.journey` |
| **Microsoft: App and Data Modernization** | App and Data Modernization Readiness Tool -- readiness against the Azure App Modernization Guidance, 62 items in 9 areas; Scout-derived questions (Microsoft does not publish the text). 52 are questionnaire items; 10 read IaC deployments, diagnostics, Azure DevOps, SQL, web app and policy settings. On-premises applications are not visible to Scout | 62 | 10 | 52 | **Gov** | `appmod.readiness` |
| **Microsoft: Azure Advisor** | Azure Advisor recommendations scored by category (Reliability, Security, Performance, Cost, Operational excellence) and impact, with service-retirement notices and the Advisor score -- 15 items; reports Not assessed when Advisor was skipped | 15 | 12 | 3 |  | `advisor.recommendations` |
| **Microsoft: CASA** | Cloud Adoption Security Assessment — cloud security maturity aligned to the CAF Secure methodology (question text is Scout's own inference from the published CAF Secure checklist, not Microsoft's numbered CASA questions; see docs/frameworks/casa-question-set.md) | 31 | 12 | 19 | **Gov** | `casa.security` |
| **Microsoft: Cloud for Financial Services Well-Architected** | Microsoft for Financial Services (formerly Cloud for Financial Services) Well-Architected for Industry review -- 40 Scout-derived questionnaire items across the five pillars plus compliance and governance; Scout does not read Dataverse data yet (see docs/frameworks/cloud-for-financial-services-question-set.md) | 40 | 0 | 40 |  | `mcfs.wellarchitected` |
| **Microsoft: DevOps Capability** | DevOps Capability Assessment -- scores against the Microsoft DevOps Resource Center's five practice phases (docs/frameworks/devops-capability-question-set.md). The assessment itself and its question numbering are INFERRED, not Microsoft-published. A DIFFERENT, narrower assessment than "CAF: Platform automation and DevOps" (the landing-zone design area) -- the two overlap in subject but are not the same enumeration. Azure DevOps access is opt-in (-IncludeDevOps) and sits behind its own auth boundary; when it was not granted, the affected findings report NotAssessed, never a scored zero. | 18 | 9 | 9 | **Gov** | `devops.capability` |
| **Microsoft: FinOps Review** | FinOps Review -- scores against the FinOps Framework 2026 (FinOps Foundation 2026-03-20 update) as used by Microsoft's FinOps Review (New): the 22 Microsoft Learn capabilities plus Executive Strategy Alignment, 23 rules (docs/frameworks/finops-review-question-set.md). The assessment itself and its question numbering are INFERRED, not Microsoft-published -- Microsoft names the assessment and publishes the framework, but not the assessment's own question text. Cost data sits behind the EA/MCA billing permission system, a different boundary than ARM Reader; when that gate blocks the pull, the affected findings report NotAssessed, never a scored zero. | 23 | 7 | 16 | **Gov** | `finops.review` |
| **Microsoft: GenAIOps Maturity** | GenAIOps Maturity Model Assessment -- 30 Scout-derived items (28 questionnaire items, 2 automated checks): four maturity levels (initial, defined, managed, optimized) across seven dimensions. Scout reports the share of statements met per dimension and does not reproduce Microsoft's 0-28 points | 30 | 2 | 28 | **Gov** | `genaiops.maturity` |
| **Microsoft: Generative AI Technical** | Technical Assessment for Generative AI in Azure -- 50 Scout-derived items (40 questionnaire items, 10 automated checks): team skills, solution design, grounding data, security, responsible AI, reliability, operations and cost. Microsoft does not publish the questions; items are Scout's reading of the WAF AI workload and Microsoft Foundry guidance | 50 | 10 | 40 | **Gov** | `genai.technical` |
| **Microsoft: M365 Copilot Data Security** | Microsoft 365 Copilot data security readiness (oversharing, sensitivity labels, governance, audit, retention, agents) -- 40 Scout-derived questionnaire items from Microsoft's Copilot data protection and Purview guidance; Microsoft does not publish the assessment's questions and Scout does not read Microsoft 365 data yet (see docs/frameworks/m365-copilot-data-security-question-set.md) | 40 | 0 | 40 |  | `m365.copilot.datasecurity` |
| **Microsoft: Platform Engineering** | Platform Engineering Technical Assessment -- Microsoft's Platform Engineering Capability Model (investment, adoption, governance, provisioning and management, interfaces, measurement and feedback), 36 items; Scout-derived questions (Microsoft does not publish the text). 30 are questionnaire items; 6 read Azure Policy, role assignments, budgets, deployment records and Azure DevOps pipelines | 36 | 6 | 30 | **Gov** | `platform.engineering` |
| **Microsoft: Power Platform Adoption** | Power Platform Adoption Assessment: strategy and business value, administration and governance, nurture and adoption -- 41 items. Questionnaire only; question text is Scout's reading of the Power Platform adoption and CoE guidance (see docs/frameworks/power-platform-adoption-question-set.md) | 41 | 0 | 41 |  | `pp.adoption` |
| **Microsoft: Power Platform Solution** | Power Platform Solution Assessment: functionality, user experience and alignment with business goals -- 37 items. Questionnaire only; question text is Scout's reading of Power Platform ALM, adoption and Well-Architected guidance (see docs/frameworks/power-platform-solution-question-set.md) | 37 | 0 | 37 |  | `pp.solution` |
| **Microsoft: Power Platform Well-Architected** | Power Platform Well-Architected: reliability, security, operational excellence, performance efficiency and experience optimization -- 49 items from Microsoft's published checklists. Questionnaire only: Scout does not read Power Platform data yet (see docs/frameworks/power-platform-well-architected-checklist.md) | 49 | 0 | 49 |  | `pp.wellarchitected` |
| **Microsoft: Sustainability Manager Well-Architected** | Dynamics 365 Sustainability (formerly Microsoft Sustainability Manager) well-architected review -- 47 Scout-derived questionnaire items from Microsoft's implementation and Well-Architected for Industry guidance; Scout does not read Dataverse data yet (see docs/frameworks/sustainability-manager-well-architected-question-set.md) | 47 | 0 | 47 |  | `msm.wellarchitected` |
| **Microsoft: Well-Architected Reliability Assessment** | Well-Architected Reliability Assessment (WARA) from the data Scout already collected, backed by the Azure Proactive Resiliency Library (APRL) -- 38 items (36 automated) across compute, containers, web, databases, storage, backup, networking and integration: zones, redundancy SKUs, backup coverage, Key Vault protection, gateway and load-balancer SKUs | 38 | 37 | 1 |  | `wara.reliability` |
| **Microsoft: Windows 11 Migration Readiness** | Windows 11 migration readiness (planning, hardware, app compatibility, management, security, operations) -- 34 Scout-derived questionnaire items from Microsoft's Windows 11 planning guidance; Windows 10 reached end of support on 2025-10-14. Scout does not read client device data yet (see docs/frameworks/windows-11-readiness-question-set.md) | 34 | 0 | 34 |  | `win11.readiness` |
| **Scout: Cost Optimization** | Cost / TCO data pull | 9 | 6 | 3 |  | `waf.cost` |
| **Scout: Cross-Resource** | Findings that require two collected datasets correlated | 6 | 6 | 0 |  | `xr.crossresource` |
| **Scout: Governance Baseline** | Management sub-bundle — policy assignments, locks, budgets | 7 | 4 | 3 | **Gov** | `caf.governance` |
| **Scout: Monitoring Baseline** | Monitor sub-bundle (subset of "Assess: Monitor") — diagnostic settings coverage only | 6 | 4 | 2 |  | `waf.operational` |
| **Scout: Update Manager** | Management sub-bundle (subset of "Assess: Management") — patch/update compliance only | 6 | 5 | 1 |  | `caf.management` |
| **Workload: AVD** | Azure Virtual Desktop workload review (AVD in Azure) -- 30 items across all 5 WAF pillars from Microsoft's current AVD guidance; host pools, session hosts, scaling plans, workspaces, private endpoints and session-host VMs | 30 | 16 | 14 |  | `waf.avd.azure` |
| **Workload: AVS** | Azure VMware Solution workload — Reliability, Security, and Governance coverage (no published WAF pillar service guide exists for AVS; see docs/frameworks/waf-avs-workload-checklist.md) | 26 | 8 | 18 | **Gov** | `avs.workload` |
| **Workload: AVS Landing Zone** | Azure VMware Solution Landing Zone Assessment Review — platform readiness (see docs/frameworks/avs-landing-zone-question-set.md) | 25 | 9 | 16 | **Gov** | `caf.avslandingzone` |
| **Workload: Oracle on Azure IaaS** | Oracle on Azure IaaS workload review -- 34 items across all 5 WAF pillars from Microsoft's Oracle on Azure VM guidance; automated checks cover VMs built from Oracle Marketplace images, the rest is answered through the questionnaire. Not Oracle Database@Azure | 34 | 9 | 25 |  | `waf.oracle` |
| **Workload: SaaS** | Azure Well-Architected SaaS workload review -- 108 Scout-derived items (95 questionnaire items, 13 automated checks) across the SaaS design areas: billing and cost, governance, resource organization, identity, compute, networking, data, DevOps, incident management and AI strategy. Microsoft does not publish the assessment's questions (see docs/frameworks/waf-saas-checklist.md) | 108 | 13 | 95 | **Gov** | `waf.saas` |
| **Workload: SAP on Azure** | SAP on Azure workload review -- 38 items across all 5 WAF pillars from Microsoft's current SAP on Azure guidance; registered virtual instances, instance VMs, load balancers, backup, Azure Monitor for SAP solutions, disks and networking. SAP not registered with Azure Center for SAP solutions is answered through the questionnaire | 38 | 14 | 24 |  | `waf.sap` |

## Rule files

Each file declares one framework area. An assessment selects files by glob.

| Rule file | Rules | Automated | Manual |
|---|--:|--:|--:|
| `advisor.recommendations` | 15 | 12 | 3 |
| `ai.readiness` | 64 | 11 | 53 |
| `analytics.journey` | 52 | 5 | 47 |
| `appmod.readiness` | 62 | 10 | 52 |
| `avs.workload` | 26 | 8 | 18 |
| `caf.ai` | 5 | 4 | 1 |
| `caf.analytics` | 5 | 3 | 2 |
| `caf.avslandingzone` | 25 | 9 | 16 |
| `caf.billing` | 6 | 0 | 6 |
| `caf.containers` | 8 | 7 | 1 |
| `caf.databases` | 7 | 4 | 3 |
| `caf.govern.ai` | 4 | 2 | 2 |
| `caf.govern.cm` | 8 | 5 | 3 |
| `caf.govern.dg` | 6 | 4 | 2 |
| `caf.govern.op` | 6 | 4 | 2 |
| `caf.govern.proc` | 11 | 0 | 11 |
| `caf.govern.rc` | 5 | 2 | 3 |
| `caf.govern.rm` | 7 | 5 | 2 |
| `caf.govern.sc` | 7 | 4 | 3 |
| `caf.governance` | 7 | 4 | 3 |
| `caf.hybrid` | 6 | 4 | 2 |
| `caf.identity` | 7 | 4 | 3 |
| `caf.integration` | 6 | 6 | 0 |
| `caf.iot` | 13 | 8 | 5 |
| `caf.management` | 6 | 5 | 1 |
| `caf.network` | 7 | 6 | 1 |
| `caf.platformauto` | 6 | 2 | 4 |
| `caf.resourceorg` | 6 | 4 | 2 |
| `caf.security` | 7 | 6 | 1 |
| `caf.storage` | 6 | 5 | 1 |
| `caf.web` | 6 | 5 | 1 |
| `casa.security` | 31 | 12 | 19 |
| `compliance.initiative` | 0 | 0 | 0 |
| `devops.capability` | 18 | 9 | 9 |
| `finops.review` | 23 | 7 | 16 |
| `genai.technical` | 50 | 10 | 40 |
| `genaiops.maturity` | 30 | 2 | 28 |
| `m365.copilot.datasecurity` | 40 | 0 | 40 |
| `mcfs.wellarchitected` | 40 | 0 | 40 |
| `msm.wellarchitected` | 47 | 0 | 47 |
| `platform.engineering` | 36 | 6 | 30 |
| `pp.adoption` | 41 | 0 | 41 |
| `pp.solution` | 37 | 0 | 37 |
| `pp.wellarchitected` | 49 | 0 | 49 |
| `smart.migration` | 49 | 18 | 31 |
| `waf.ai` | 63 | 9 | 54 |
| `waf.aisearch` | 37 | 8 | 29 |
| `waf.analytics` | 74 | 18 | 56 |
| `waf.avd` | 20 | 6 | 14 |
| `waf.avd.azure` | 30 | 16 | 14 |
| `waf.azurelocal.cost` | 6 | 2 | 4 |
| `waf.azurelocal.operational` | 6 | 4 | 2 |
| `waf.azurelocal.performance` | 6 | 0 | 6 |
| `waf.azurelocal.reliability` | 6 | 1 | 5 |
| `waf.azurelocal.security` | 9 | 0 | 9 |
| `waf.cost` | 9 | 6 | 3 |
| `waf.dataservices` | 104 | 49 | 55 |
| `waf.golive` | 57 | 35 | 22 |
| `waf.machinelearning` | 44 | 6 | 38 |
| `waf.missioncritical` | 81 | 41 | 40 |
| `waf.operational` | 6 | 4 | 2 |
| `waf.oracle` | 34 | 9 | 25 |
| `waf.performance` | 6 | 4 | 2 |
| `waf.reliability` | 7 | 4 | 3 |
| `waf.saas` | 108 | 13 | 95 |
| `waf.sap` | 38 | 14 | 24 |
| `waf.security` | 7 | 5 | 2 |
| `waf.serviceguides` | 214 | 130 | 84 |
| `waf.sustainability` | 67 | 20 | 47 |
| `wara.reliability` | 38 | 37 | 1 |
| `win11.readiness` | 34 | 0 | 34 |
| `xr.crossresource` | 6 | 6 | 0 |

**Total — 72 files, 2020 rules, 669 automated, 1351 manual.**


