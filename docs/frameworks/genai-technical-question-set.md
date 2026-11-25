# Generative AI -- enumerated source for the Technical Assessment for Generative AI in Azure

**Enumerated 2026-11-25. Verification method and limits are stated below -- read them before quoting
any coverage number from this page.**

Scout's `genai.technical.yaml` scores the review in Microsoft's
[Technical Assessment for Generative AI in Azure](https://learn.microsoft.com/en-us/assessments/443670b4-11d1-4dd7-8128-b2bdb7a2bf2f/),
which checks a team's readiness to develop, run and maintain Azure AI solutions in production.
`src/assess/rules/genai.technical.yaml` is written against this page only, and every rule cites an item number
from the tables below. The design and operating practices are **manual** questions answered with
`-AssessmentAnswers`; the platform configuration Azure data can show is **automated**.

## Source

| Field | Value |
|---|---|
| Assessment | [Technical Assessment for Generative AI in Azure](https://learn.microsoft.com/en-us/assessments/443670b4-11d1-4dd7-8128-b2bdb7a2bf2f/) (question text not published) |
| Framework version | Well-Architected AI workload guidance and Microsoft Foundry guidance on Microsoft Learn, current as of the extraction date (no published version number) |
| Extraction date | 2026-11-25 |
| Verification method | Each source page below was fetched or searched with the Microsoft Learn MCP tools (`microsoft_docs_fetch`, `microsoft_docs_search`) on 2026-11-25. Every property an automated item reads was checked against the collect.json contract in `src/collect/Invoke-Collect.ps1`. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published, so the items below are
**Scout-derived**: Scout's reading of the Well-Architected AI workload guidance and the Microsoft Foundry guidance,
grouped into eight readiness areas of Scout's own. The `GENAI-*` IDs are Scout's. The area grouping is Scout's
judgement, not Microsoft's. This page overlaps [waf-ai-workload-checklist.md](waf-ai-workload-checklist.md) on
purpose: that page reviews a workload against design areas, this one asks whether the team and platform are ready
for production.

Sources:

- [WAFO] [MLOps and GenAIOps for AI workloads on Azure (WAF AI workload)](https://learn.microsoft.com/azure/well-architected/ai/mlops-genaiops)
- [OPS] [AI workload operations on Azure (WAF AI workload)](https://learn.microsoft.com/azure/well-architected/ai/operations)
- [RAIP] [Responsible AI in Azure workloads (WAF AI workload)](https://learn.microsoft.com/azure/well-architected/ai/responsible-ai)
- [GAO] [Generative AI operations for organizations with MLOps investments](https://learn.microsoft.com/azure/architecture/ai-ml/guide/genaiops-for-mlops)
- [BSL] [Baseline Microsoft Foundry chat reference architecture](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-chat)
- [FND] [Microsoft Foundry architecture](https://learn.microsoft.com/azure/foundry/concepts/architecture)
- [NIS] [How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
- [SECB] [Azure security baseline for Microsoft Foundry](https://learn.microsoft.com/security/benchmark/azure/baselines/azure-ai-foundry-security-baseline)
- [GOVP] [Govern Azure platform services (PaaS) for AI](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/platform/governance)
- [GOVI] [Governance for AI on Azure infrastructure](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/infrastructure/governance)
- [SECP] [Secure Azure platform services (PaaS) for AI](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/platform/security)
- [SEC] [Guidance to set up your organization's AI security process](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/secure)

Automated items are **gated**: they run only when the resources they judge exist, so an estate without
them reports those items Not assessed rather than passed or failed. Manual items are answered with
`-AssessmentAnswers` (see [Questionnaire Answers](../assessment/questionnaire-answers.md)); where collected
Azure data bears on the question it is attached to the item as evidence.

## The enumeration -- 50 items across 8 readiness areas

### Team skills and delivery (TS) -- 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-TS-01 | The team has the skills to build and run generative AI solutions | Manual | WAFO, GAO |
| GENAI-TS-02 | Use cases are validated with a proof of value before production build | Manual | WAFO |
| GENAI-TS-03 | The team understands model quotas, limits and regional availability | Manual | FND, GOVP |
| GENAI-TS-04 | Data scientists review experiments with prompts and retrieval | Manual | GAO |
| GENAI-TS-05 | Runbooks exist for routine, unplanned and emergency AI operations | Manual | WAFO |

### Solution design (SD) -- 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-SD-01 | Models are selected by evaluating candidates against requirements | Manual | GAO, FND |
| GENAI-SD-02 | The technical pattern (prompting, retrieval-augmented generation or fine-tuning) is chosen with a rationale | Manual | GAO |
| GENAI-SD-03 | The orchestration layer is separated from the model and the data stores | Manual | GAO, BSL |
| GENAI-SD-04 | Agent tools and permissions are scoped to each agent's task | Manual | SECP, BSL |
| GENAI-SD-05 | A gateway sits in front of model endpoints | Manual -- `domains.integration.apiManagement` attached as evidence | GAO |
| GENAI-SD-06 | Related AI resources are deployed in the same region | Manual -- `domains.ai.cognitiveAccounts` attached as evidence | WAFO |
| GENAI-SD-07 | Managed platforms are preferred over custom hosting | Manual -- `domains.ai.mlWorkspaces` attached as evidence | GAO |
| GENAI-SD-08 | The model deployment type matches residency and throughput needs | Manual | FND |

### Grounding data and search (DG) -- 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-DG-01 | Grounding data sources are selected and prepared deliberately | Manual | GAO, WAFO |
| GENAI-DG-02 | Search indexes are kept fresh and can be rebuilt | Manual -- `domains.ai.searchServices` attached as evidence | GAO |
| GENAI-DG-03 | AI Search services are not on the free tier and have at least two replicas | Automated -- `domains.ai.searchServices` | WAFO |
| GENAI-DG-04 | AI Search services do not accept API keys | Automated -- `domains.ai.searchServices` | SECP |
| GENAI-DG-05 | AI Search services have public network access disabled | Automated -- `domains.ai.searchServices` | SECP, NIS |
| GENAI-DG-06 | Retrieval respects each user's access to the underlying data | Manual | SECP, BSL |

### Security and identity (SE) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-SE-01 | Azure AI accounts do not accept API keys | Automated -- `domains.ai.cognitiveAccounts` | SECP |
| GENAI-SE-02 | Azure AI accounts have a managed identity | Automated -- `domains.ai.cognitiveAccounts` | SECP, BSL |
| GENAI-SE-03 | Azure AI accounts have public network access disabled | Automated -- `domains.ai.cognitiveAccounts` | NIS, SECB |
| GENAI-SE-04 | Azure AI accounts have a private endpoint | Automated -- `domains.ai.cognitiveAccounts` | NIS, SECB |
| GENAI-SE-05 | Machine learning workspaces have public network access disabled | Automated -- `domains.ai.mlWorkspaces` | NIS |
| GENAI-SE-06 | Machine learning workspaces use managed network isolation | Automated -- `domains.ai.mlWorkspaces` | NIS, FND |
| GENAI-SE-07 | Defender for Cloud threat protection for AI services is enabled | Automated -- `security.defenderPlans` | GOVP |
| GENAI-SE-08 | Customer-managed keys protect data where policy requires them | Manual -- `domains.ai.cognitiveAccounts` attached as evidence | SECP |
| GENAI-SE-09 | The threat model covers prompt injection, data leakage, data poisoning and wallet abuse | Manual | SEC |
| GENAI-SE-10 | Access to AI resources is least privilege, with separate identities per environment | Manual | GOVP, GOVI |

### Responsible AI and content safety (RA) -- 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-RA-01 | A content filter policy is bound to every model deployment | Manual | FND, BSL |
| GENAI-RA-02 | Prompt injection and jailbreak protection is enabled | Manual | FND, SEC |
| GENAI-RA-03 | A Responsible AI impact assessment is complete | Manual | WAFO, RAIP |
| GENAI-RA-04 | Adversarial testing is done before release | Manual | SEC |
| GENAI-RA-05 | Human oversight and user transparency are designed in | Manual | RAIP |
| GENAI-RA-06 | Interactions are auditable and sensitive data in them is visible | Manual -- `domains.analytics.purviewAccounts` attached as evidence | BSL |

### Reliability and capacity (RC) -- 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-RC-01 | Throttling and quota errors are handled | Manual | GAO, GOVP |
| GENAI-RC-02 | Production capacity is planned, with provisioned throughput where demand is steady | Manual | GOVP, FND |
| GENAI-RC-03 | Disaster recovery covers model endpoints, indexes and orchestration | Manual | GOVP |
| GENAI-RC-04 | Model retirement dates are tracked and replacement is tested ahead of time | Manual | GOVP |
| GENAI-RC-05 | Reliability targets are defined for each AI component | Manual | WAFO |

### Operations and monitoring (OP) -- 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-OP-01 | Diagnostic logs from AI resources go to a central workspace | Manual -- `opsPosture.diagnosticCoverage` attached as evidence | OPS, FND |
| GENAI-OP-02 | Latency, token usage, throttling and output quality are monitored | Manual | OPS, GAO |
| GENAI-OP-03 | Alerts exist for AI service health and quality | Manual -- `monitor.metricAlertRules` attached as evidence | GOVP |
| GENAI-OP-04 | Evaluation runs in the delivery pipeline and in pre-production | Manual | GAO |
| GENAI-OP-05 | Quality drift and model decay are monitored in production | Manual | GAO, WAFO |
| GENAI-OP-06 | Prompts, indexes and orchestration are under source control and deployed as code | Manual -- `management.deployments` attached as evidence | WAFO |

### Cost and performance (CO) -- 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAI-CO-01 | Models are matched to the task, with smaller models for simple work | Manual | GOVP |
| GENAI-CO-02 | Token use is controlled | Manual | GOVP |
| GENAI-CO-03 | Cost is tracked per workload against a budget | Manual -- `governance.budgets` attached as evidence | GOVP |
| GENAI-CO-04 | Performance benchmarks are set through experimentation | Manual | WAFO |

## Summary

| Area | Items | Automated | Manual |
|---|---|---|---|
| Team skills and delivery | 5 | 0 | 5 |
| Solution design | 8 | 0 | 8 |
| Grounding data and search | 6 | 3 | 3 |
| Security and identity | 10 | 7 | 3 |
| Responsible AI and content safety | 6 | 0 | 6 |
| Reliability and capacity | 5 | 0 | 5 |
| Operations and monitoring | 6 | 0 | 6 |
| Cost and performance | 4 | 0 | 4 |
| **Total** | **50** | **10** | **40** |

The AI Search, Azure AI account and machine learning workspace items read the same collected properties as the
Well-Architected AI workload review; an estate scored under both sees the same underlying finding twice, under two
different ids.
