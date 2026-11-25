# GenAIOps -- enumerated source for the GenAIOps Maturity Model Assessment

**Enumerated 2026-11-25. Verification method and limits are stated below -- read them before quoting
any coverage number from this page.**

Scout's `genaiops.maturity.yaml` scores the review in Microsoft's
[GenAIOps Maturity Model Assessment](https://learn.microsoft.com/en-us/assessments/e14e1e9f-d339-4d7e-b2bb-24f056cf08b6/),
a questionnaire that places an organisation on a four-level maturity model for Generative Artificial Intelligence
Operations (GenAIOps, sometimes called LLMOps): initial, defined, managed and optimized.
`src/assess/rules/genaiops.maturity.yaml` is written against this page only, and every rule cites an item number
from the tables below. The maturity ladders are **manual** questions answered with `-AssessmentAnswers`; two
supporting checks that Azure data can answer are **automated**.

## Source

| Field | Value |
|---|---|
| Assessment | [GenAIOps Maturity Model Assessment](https://learn.microsoft.com/en-us/assessments/e14e1e9f-d339-4d7e-b2bb-24f056cf08b6/) (question text and points not published) |
| Framework version | GenAIOps maturity model guidance (four levels, score bands initial 0-9, maturing 10-14 and 15-19, optimized 20-28) on Microsoft Learn, current as of the extraction date |
| Extraction date | 2026-11-25 |
| Verification method | The maturity guidance page and the GenAIOps-for-MLOps page were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Every property an automated item reads was checked against the collect.json contract in `src/collect/Invoke-Collect.ps1`. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions and points are not published. The items below
are **Scout-derived**: for each of seven dimensions Scout writes four statements, one per maturity level, from that
level's description in Microsoft's maturity guidance and from the operating practices in the GenAIOps guidance
(prompt and data versioning, experimentation and evaluation, deployment automation, monitoring, content safety and
resource management). The `GENAIOPS-*` IDs, the dimension names and the level each statement is assigned to are
Scout's own judgement. Scout reports the share of statements met per dimension. It does not reproduce Microsoft's
0-28 points and does not place the organisation on a level.

Sources:

- [MAT] [Advance your maturity level for Generative Artificial Intelligence Operations (GenAIOps)](https://learn.microsoft.com/azure/machine-learning/prompt-flow/concept-llmops-maturity)
- [GAO] [Generative AI operations for organizations with MLOps investments](https://learn.microsoft.com/azure/architecture/ai-ml/guide/genaiops-for-mlops)
- [WAFO] [MLOps and GenAIOps for AI workloads on Azure](https://learn.microsoft.com/azure/well-architected/ai/mlops-genaiops)
- [SEC] [Guidance to set up your organization's AI security process](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/secure)

Automated items are **gated**: they run only when the resources they judge exist, so an estate without
them reports those items Not assessed rather than passed or failed. Manual items are answered with
`-AssessmentAnswers` (see [Questionnaire Answers](../assessment/questionnaire-answers.md)); where collected
Azure data bears on the question it is attached to the item as evidence.

## The enumeration -- 30 items across 7 dimensions

### Prompt design and orchestration (PD) -- 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAIOPS-PD-01 | Prompts are designed deliberately, with a system message and structure, not ad hoc | Manual | MAT; level 1 (initial) |
| GENAIOPS-PD-02 | More complex prompts are integrated into applications through an orchestration layer | Manual | MAT, GAO; level 2 (defined) |
| GENAIOPS-PD-03 | Prompts, orchestration and models are optimised for specific requirements | Manual | MAT, GAO; level 3 (managed) |
| GENAIOPS-PD-04 | The prompt and model strategy is revisited as large language models evolve | Manual | MAT; level 4 (optimized) |

### Asset management and versioning (AM) -- 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAIOPS-AM-01 | Prompts and configuration are kept in a shared, known place | Manual | MAT; level 1 (initial) |
| GENAIOPS-AM-02 | Prompts, datasets, indexes and orchestration code are under source control | Manual | MAT, GAO; level 2 (defined) |
| GENAIOPS-AM-03 | Advanced version control and rollback exist for prompts, models, indexes and orchestration | Manual | MAT, GAO; level 3 (managed) |
| GENAIOPS-AM-04 | A model and prompt catalogue is maintained and retirement dates are tracked | Manual | MAT, WAFO; level 4 (optimized) |

### Evaluation and experimentation (EV) -- 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAIOPS-EV-01 | Basic metrics evaluate application performance | Manual | MAT; level 1 (initial) |
| GENAIOPS-EV-02 | Evaluation uses groundedness, relevance and similarity | Manual | MAT, GAO; level 2 (defined) |
| GENAIOPS-EV-03 | Evaluations run automatically on every change, against agreed thresholds | Manual | MAT, GAO; level 3 (managed) |
| GENAIOPS-EV-04 | Evaluation continues in production with sampled traffic and human feedback | Manual | MAT, GAO; level 4 (optimized) |

### Deployment (DP) -- 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAIOPS-DP-01 | There is a repeatable way to deploy the generative AI application | Manual | MAT; level 1 (initial) |
| GENAIOPS-DP-02 | Deployment is systematic and integrated with CI/CD | Manual -- `management.deployments` attached as evidence | MAT, WAFO; level 2 (defined) |
| GENAIOPS-DP-03 | Structured deployment uses progressive exposure and side-by-side versions | Manual | MAT, GAO; level 3 (managed) |
| GENAIOPS-DP-04 | The pipeline automates build, evaluation, promotion and rollback end to end | Manual | MAT, WAFO; level 4 (optimized) |

### Monitoring and feedback (MN) -- 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAIOPS-MN-01 | Basic operational metrics are collected | Manual -- `opsPosture.diagnosticCoverage` attached as evidence | MAT; level 1 (initial) |
| GENAIOPS-MN-02 | Token usage, latency and throttling are monitored with alerts | Manual -- `monitor.metricAlertRules` attached as evidence | MAT, GAO; level 2 (defined) |
| GENAIOPS-MN-03 | Monitoring is proactive, with drift detection and user feedback | Manual | MAT, GAO; level 3 (managed) |
| GENAIOPS-MN-04 | Production learnings feed back into evaluation and improvement automatically | Manual | MAT, WAFO; level 4 (optimized) |

### Content safety and responsible AI (CS) -- 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAIOPS-CS-01 | Responsible AI and basic content filtering are considered | Manual | MAT; level 1 (initial) |
| GENAIOPS-CS-02 | Content safety is configured and ethical considerations are reviewed | Manual | MAT, GAO; level 2 (defined) |
| GENAIOPS-CS-03 | Content safety is comprehensive, covering prompts and completions | Manual | MAT, GAO; level 3 (managed) |
| GENAIOPS-CS-04 | Safety is evaluated continuously and reported | Manual | MAT; level 4 (optimized) |
| GENAIOPS-CS-05 | Defender for Cloud threat protection for AI services is enabled | Automated -- `security.defenderPlans` | GAO, SEC |

### Resource and cost management (RM) -- 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| GENAIOPS-RM-01 | Model quotas and token usage are understood | Manual | MAT, GAO; level 1 (initial) |
| GENAIOPS-RM-02 | Usage is tracked per application with budgets | Manual | MAT, GAO; level 2 (defined) |
| GENAIOPS-RM-03 | Capacity and cost are optimised per workload | Manual | MAT, WAFO; level 3 (managed) |
| GENAIOPS-RM-04 | Cost and capacity are forecast and governed centrally | Manual | MAT, WAFO; level 4 (optimized) |
| GENAIOPS-RM-05 | Azure budgets are set | Automated -- `governance.budgets` | GAO |

## Summary

| Area | Items | Automated | Manual |
|---|---|---|---|
| Prompt design and orchestration | 4 | 0 | 4 |
| Asset management and versioning | 4 | 0 | 4 |
| Evaluation and experimentation | 4 | 0 | 4 |
| Deployment | 4 | 0 | 4 |
| Monitoring and feedback | 4 | 0 | 4 |
| Content safety and responsible AI | 5 | 1 | 4 |
| Resource and cost management | 5 | 1 | 4 |
| **Total** | **30** | **2** | **28** |

Answer each statement independently. A statement marked with a higher level can be met while a lower one is not
(for example automated promotion without a documented procedure), and the report shows that unevenness rather than
hiding it. `GENAIOPS-CS-05` and `GENAIOPS-RM-05` are supporting checks outside the four-level ladders.
