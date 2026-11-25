# AI Readiness -- enumerated source for the Microsoft AI Readiness Assessment

**Enumerated 2026-11-25. Verification method and limits are stated below -- read them before quoting
any coverage number from this page.**

Scout's `ai.readiness.yaml` scores the review in Microsoft's
[AI Readiness Assessment](https://learn.microsoft.com/en-us/assessments/94f1c697-9ba7-4d47-ad83-7c6bd94b1505/),
an enterprise-level assessment of organisational preparedness across seven pillars: Business Strategy, AI
Governance & Security, Data Foundations, AI Strategy & Experience, Organization & Culture, Infrastructure for AI
and Model Management. `src/assess/rules/ai.readiness.yaml` is written against this page only, and every rule
cites an item number from the tables below. Most items are organisational, so they are **manual** questions
answered with `-AssessmentAnswers`; the infrastructure, governance and data items that Azure data can answer
are **automated**.

## Source

| Field | Value |
|---|---|
| Assessment | [AI Readiness Assessment](https://learn.microsoft.com/en-us/assessments/94f1c697-9ba7-4d47-ad83-7c6bd94b1505/) (seven pillars; question text not published) |
| Framework version | Cloud Adoption Framework AI adoption and AI agent adoption guidance on Microsoft Learn, current as of the extraction date (no published version number) |
| Extraction date | 2026-11-25 |
| Verification method | The seven pillar names come from the assessment's own description. Each source page below was fetched with the Microsoft Learn MCP tools (`microsoft_docs_fetch`, `microsoft_docs_search`) on 2026-11-25. Every property an automated item reads was checked against the collect.json contract in `src/collect/Invoke-Collect.ps1`. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions and scoring are not published, so the items
below are **Scout-derived**: Scout's reading of the CAF AI adoption pages (strategy, plan, ready, govern, secure,
manage) and the CAF AI agent adoption pages, grouped under the seven pillar names the assessment uses. The
`AIRDY-*` IDs are Scout's own, and the assignment of an item to a pillar is Scout's judgement. Microsoft reports
readiness as a stage (Exploring, Planning, Implementing, Scaling, Realizing); Scout reports a percentage per
pillar and does not map it to those stages.

Sources:

- [STR] [AI adoption (CAF AI strategy)](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/strategy)
- [PLN] [Plan for AI adoption](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/plan)
- [RDY] [Architecture and governance for AI (AI ready)](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/ready)
- [GOVP] [Govern Azure platform services (PaaS) for AI](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/platform/governance)
- [SECP] [Secure Azure platform services (PaaS) for AI](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/platform/security)
- [SEC] [Guidance to set up your organization's AI security process](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/secure)
- [RAIP] [Responsible AI policies](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/responsible-ai-policies)
- [AGS] [AI agent adoption strategy](https://learn.microsoft.com/azure/cloud-adoption-framework/ai-agents/)
- [AGO] [Organizational readiness for AI agents](https://learn.microsoft.com/azure/cloud-adoption-framework/ai-agents/organizational-readiness)
- [AMM] [Agentic AI adoption maturity model](https://learn.microsoft.com/agents/adoption-maturity-model/)
- [MLO] [MLOps and GenAIOps for AI workloads on Azure](https://learn.microsoft.com/azure/well-architected/ai/mlops-genaiops)
- [OPS] [AI workload operations on Azure](https://learn.microsoft.com/azure/well-architected/ai/operations)

Automated items are **gated**: they run only when the resources they judge exist, so an estate without
them reports those items Not assessed rather than passed or failed. Manual items are answered with
`-AssessmentAnswers` (see [Questionnaire Answers](../assessment/questionnaire-answers.md)); where collected
Azure data bears on the question it is attached to the item as evidence.

## The enumeration -- 64 items across 7 pillars

### Business strategy (BS) -- 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| AIRDY-BS-01 | The business outcomes AI is expected to support are defined | Manual | STR |
| AIRDY-BS-02 | Use cases are prioritised jointly by business and IT on outcomes, not novelty | Manual | PLN, AGO |
| AIRDY-BS-03 | Success measures are defined before deployment and value is tracked | Manual | PLN, AMM |
| AIRDY-BS-04 | Each use case is matched to the right technique (automation, RAG or agent) | Manual | AGS |
| AIRDY-BS-05 | Buy, build or customise is decided against the Microsoft AI decision tree | Manual -- `domains.ai.cognitiveAccounts` attached as evidence | STR |
| AIRDY-BS-06 | Executives sponsor AI visibly and set a common direction | Manual | STR |
| AIRDY-BS-07 | AI spend is budgeted and managed | Manual -- `governance.budgets` attached as evidence | PLN, AGO |
| AIRDY-BS-08 | Business processes are redesigned for human and AI collaboration | Manual | AMM |

### AI governance and security (GS) -- 12 items

| # | Item | Scout | Source |
|---|---|---|---|
| AIRDY-GS-01 | AI governance is owned centrally with Responsible AI policies | Manual | STR, RAIP |
| AIRDY-GS-02 | AI use cases pass a Responsible AI review before release | Manual | PLN, RAIP |
| AIRDY-GS-03 | A complete inventory of AI assets is kept | Manual -- `domains.ai.cognitiveAccounts` attached as evidence | SEC |
| AIRDY-GS-04 | Azure Policy assignments govern AI deployments | Automated -- `governance.policyAssignments` | GOVP |
| AIRDY-GS-05 | Azure AI accounts have a managed identity | Automated -- `domains.ai.cognitiveAccounts` | GOVP, SECP |
| AIRDY-GS-06 | Azure AI accounts do not accept API keys | Automated -- `domains.ai.cognitiveAccounts` | SECP |
| AIRDY-GS-07 | Azure AI accounts have public network access disabled | Automated -- `domains.ai.cognitiveAccounts` | GOVP |
| AIRDY-GS-08 | Defender for Cloud threat protection for AI services is enabled | Automated -- `security.defenderPlans` | GOVP, SEC |
| AIRDY-GS-09 | Sensitive data is classified and labelled before AI uses it | Manual -- `domains.analytics.purviewAccounts` attached as evidence | SECP, SEC |
| AIRDY-GS-10 | Access to AI resources is least privilege, with just-in-time administration | Manual | GOVP |
| AIRDY-GS-11 | AI agents have their own governed identities and limited tool permissions | Manual | SECP, AGS |
| AIRDY-GS-12 | Regulatory, residency and compliance requirements for AI are mapped | Manual -- `domains.ai.cognitiveAccounts` attached as evidence | PLN, GOVP |

### Data foundations (DF) -- 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| AIRDY-DF-01 | The data each AI capability needs is identified | Manual | STR |
| AIRDY-DF-02 | A data catalogue governs the data estate | Automated -- `domains.analytics.purviewAccounts` | STR, SEC |
| AIRDY-DF-03 | Data quality standards are defined and measured | Manual -- `domains.analytics.dataFactories` attached as evidence | STR |
| AIRDY-DF-04 | A unified data platform serves AI and analytics | Manual -- `domains.analytics.fabricCapacities` attached as evidence | STR |
| AIRDY-DF-05 | Data lineage and provenance can be shown | Manual | MLO |
| AIRDY-DF-06 | Data boundaries are defined for each AI workload | Manual | SECP |
| AIRDY-DF-07 | Data factories do not accept public network access | Automated -- `domains.analytics.dataFactories` | SECP |
| AIRDY-DF-08 | Grounding data and search indexes are kept fresh | Manual -- `domains.ai.searchServices` attached as evidence | MLO |

### AI strategy and experience (SX) -- 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| AIRDY-SX-01 | AI experiences are designed around user goals | Manual | AMM |
| AIRDY-SX-02 | Hand-offs between AI and people are clear | Manual | AMM |
| AIRDY-SX-03 | User feedback improves AI experiences | Manual | AMM, MLO |
| AIRDY-SX-04 | AI experiences are consistent across solutions | Manual | AMM |
| AIRDY-SX-05 | The set of approved AI solutions is defined and available | Manual | STR, AGS |
| AIRDY-SX-06 | Employees have access to approved AI together with training | Manual | STR |
| AIRDY-SX-07 | The AI strategy is revisited as telemetry and maturity grow | Manual | AMM |
| AIRDY-SX-08 | Responsible AI is part of the strategy and builds trust | Manual | AMM, RAIP |

### Organization and culture (OC) -- 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| AIRDY-OC-01 | Roles and ownership for AI are defined | Manual | AGO |
| AIRDY-OC-02 | AI skills are assessed and a training plan exists | Manual | AGO, PLN |
| AIRDY-OC-03 | A cross-functional team or Center of Excellence supports AI adoption | Manual | STR, AGO |
| AIRDY-OC-04 | Change management prepares people for new roles and processes | Manual | AGO |
| AIRDY-OC-05 | Culture and incentives encourage responsible experimentation | Manual | AMM |
| AIRDY-OC-06 | A community of practice shares AI lessons | Manual | AMM |
| AIRDY-OC-07 | Employees can raise concerns about AI use | Manual | RAIP |
| AIRDY-OC-08 | Financial management for AI is in place | Manual | AGO |

### Infrastructure for AI (IN) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| AIRDY-IN-01 | AI workloads use the existing Azure landing zone architecture | Manual -- `governance.managementGroups` attached as evidence | RDY |
| AIRDY-IN-02 | The platform chosen carries the least operational responsibility that meets the need | Manual -- `domains.ai.mlWorkspaces` attached as evidence | STR |
| AIRDY-IN-03 | Model quotas and capacity are planned | Manual | GOVP |
| AIRDY-IN-04 | Azure AI accounts have a private endpoint | Automated -- `domains.ai.cognitiveAccounts` | GOVP, SECP |
| AIRDY-IN-05 | Machine learning workspaces have public network access disabled | Automated -- `domains.ai.mlWorkspaces` | GOVP |
| AIRDY-IN-06 | Machine learning workspaces use managed network isolation | Automated -- `domains.ai.mlWorkspaces` | GOVP |
| AIRDY-IN-07 | AI Search services have public network access disabled | Automated -- `domains.ai.searchServices` | GOVP |
| AIRDY-IN-08 | AI workloads are monitored and alerted on | Manual -- `opsPosture.diagnosticCoverage` attached as evidence | OPS, GOVP |
| AIRDY-IN-09 | Business continuity covers AI model endpoints | Manual | GOVP |
| AIRDY-IN-10 | Infrastructure for custom models is justified and right-sized | Manual | STR |

### Model management (MM) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| AIRDY-MM-01 | A list of approved models is maintained | Manual | GOVP, MLO |
| AIRDY-MM-02 | Model selection weighs fit, cost and risk | Manual | GOVP, MLO |
| AIRDY-MM-03 | Model versions are pinned and retirement dates are tracked | Manual | GOVP |
| AIRDY-MM-04 | Models are evaluated before production | Manual | MLO |
| AIRDY-MM-05 | Prompt and model changes are managed with rollback | Manual | GOVP, MLO |
| AIRDY-MM-06 | Model drift and decay are monitored | Manual | MLO, OPS |
| AIRDY-MM-07 | A workspace or registry tracks custom models and experiments | Manual -- `domains.ai.mlWorkspaces` attached as evidence | MLO |
| AIRDY-MM-08 | Fine-tuning is governed | Manual | MLO |
| AIRDY-MM-09 | Content safety guardrails are bound to every model deployment | Manual | MLO, OPS |
| AIRDY-MM-10 | MLOps and GenAIOps practices operate the model lifecycle | Manual | MLO |

## Summary

| Area | Items | Automated | Manual |
|---|---|---|---|
| Business strategy | 8 | 0 | 8 |
| AI governance and security | 12 | 5 | 7 |
| Data foundations | 8 | 2 | 6 |
| AI strategy and experience | 8 | 0 | 8 |
| Organization and culture | 8 | 0 | 8 |
| Infrastructure for AI | 10 | 4 | 6 |
| Model management | 10 | 0 | 10 |
| **Total** | **64** | **11** | **53** |

An estate with no AI resources reports the automated items Not assessed, so its score rests on the answers to the
manual items. That is deliberate: "no AI resources yet" is a fact about the estate, not a pass.
