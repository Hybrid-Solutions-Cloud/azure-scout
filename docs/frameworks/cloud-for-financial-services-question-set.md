# Cloud for Financial Services Well-Architected — enumerated source for the Microsoft Cloud for Financial Services Well-Architected for Industry assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `mcfs.wellarchitected.yaml` reviews a financial services workload against the Well-Architected for Industry
guidance and the Microsoft financial services guidance (landing zones, policy, compliance tools, operational
resilience). It is Scout's counterpart to the
[Microsoft Cloud for Financial Services | Well-Architected for Industry](https://learn.microsoft.com/en-us/assessments/85444ed4-5423-440a-aae0-a03a70981d6c/)
assessment, which Microsoft Learn now lists as the Microsoft for Financial Services Assessment.
`src/assess/rules/mcfs.wellarchitected.yaml` is written against this page only, and every rule cites an item number
from the tables below. Every item is a **manual** question answered with `-AssessmentAnswers`.

## Source

| Field | Value |
|---|---|
| Assessment | [Microsoft Cloud for Financial Services | Well-Architected for Industry](https://learn.microsoft.com/en-us/assessments/85444ed4-5423-440a-aae0-a03a70981d6c/) (question text not published; Learn lists it as the Microsoft for Financial Services Assessment, covering configuration and extension scenarios across the five pillars) |
| Framework version | Well-Architected for Industry pillar overviews and Microsoft for Financial Services guidance on Microsoft Learn, current as of the extraction date; no published version number |
| Extraction date | 2026-11-25 |
| Verification method | Pages marked `fetched` in the source list were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Pages marked `search excerpt` were read through `microsoft_docs_search` excerpts on the same day, not in full. The URL for the product-specific Well-Architected pages (`industry/well-architected/financial-services/`) returned the What is Microsoft for Financial Services page when fetched, so no assessment-specific design, deployment or monitoring page could be read. No tenant was read. |

## Product status

Checked against Microsoft Learn on 2026-11-25.

- **Renamed, not retired.** Microsoft Cloud for Financial Services is now **Microsoft for Financial Services**.
  Learn's Well-Architected for Industry overview lists this same assessment as the "Microsoft for Financial Services
  Assessment" and describes it as covering configuration and extension scenarios across the reliability, cost,
  operational excellence, security and performance efficiency pillars. Only archived release-plan pages keep the old
  product name. Scout keeps the `MCFS-` prefix and the catalog assessment name.
- **Limit of the source.** The product-specific Well-Architected pages did not return content of their own (see the
  verification method). The items rest on the five pillar overviews and the financial services pages instead, so they
  are broader and less product-specific than Microsoft's assessment is likely to be.
- **Deprecated components.** Learn lists these as deprecated and not available for deployment: Financial Meeting
  Prep (2025-10-01, replaced by the LSEG Workspace app in Teams), the financial document analysis skill for agents
  (2025-08-04, replaced by Azure AI Search and Azure OpenAI), Intelligent appointments (2024-05-22), Collaboration
  Manager for Loans, the loan tracker and sample loan onboarding portal, and Banking customer intelligence
  (2023-09-01), and the Dynamics 365 financial services accelerator (2021-07-01). MCFS-OE-05 asks whether any is in use.

## The one thing this enumeration is NOT

**The questions are Scout-derived, not Microsoft's.** The assessment's question text is not published, so the items
below are Scout's reading of the guidance listed above. The `MCFS-*` IDs, and the assignment of an item to a group,
are Scout's own.

**Scout does not read this product's data yet.** Microsoft for Financial Services is built on Dynamics 365, Power
Platform and Azure. Scout reads the Azure part (Resource Graph and ARM) through its other assessments, and one
Microsoft Entra policy; it does not read Dataverse, Power Platform or Dynamics 365 data and the collect.json contract
in `src/collect/Invoke-Collect.ps1` holds no Conditional Access data. So every rule is `manual: true` with
`query: null`: it is exported as a question by `Export-ScoutAssessmentQuestion`, answered with `-AssessmentAnswers`
(see [Questionnaire Answers](../assessment/questionnaire-answers.md)), and stays Manual and out of the score until
answered. Where the Azure part of the estate bears on an item, run the Azure assessments (for example the landing
zone, security and reliability reviews) alongside this one.

Sources:

- [WAI] [Overview of Well-Architected for Industry (lists the Microsoft for Financial Services assessment)](https://learn.microsoft.com/industry/well-architected/overview) -- fetched
- [REL] [Overview of the reliability pillar (Well-Architected for Industry)](https://learn.microsoft.com/industry/well-architected/reliability) -- fetched
- [SEC] [Overview of the security pillar (Well-Architected for Industry)](https://learn.microsoft.com/industry/well-architected/security) -- fetched
- [COST] [Overview of the cost optimization pillar (Well-Architected for Industry)](https://learn.microsoft.com/industry/well-architected/cost-optimization) -- fetched
- [OPE] [Overview of the operational excellence pillar (Well-Architected for Industry)](https://learn.microsoft.com/industry/well-architected/operation-excellence) -- fetched
- [PERF] [Overview of the performance efficiency pillar (Well-Architected for Industry)](https://learn.microsoft.com/industry/well-architected/performance-efficiency) -- fetched
- [FSI] [What is Microsoft for Financial Services?](https://learn.microsoft.com/industry/financial-services/fsi-overview) -- fetched
- [CT] [Microsoft compliance tools (financial services)](https://learn.microsoft.com/industry/financial-services/microsoft-compliance-tools) -- fetched
- [RES] [Strengthening operational resilience and reducing concentration risk in financial services](https://learn.microsoft.com/compliance/assurance/assurance-fsi-resilience) -- fetched
- [GOVF] [Infrastructure governance (financial services)](https://learn.microsoft.com/industry/financial-services/infra-governance-fsi) -- search excerpt
- [AZ] [Microsoft Azure for financial services (Payment HSM, confidential computing)](https://learn.microsoft.com/industry/financial-services/microsoft-azure-fsi) -- search excerpt
- [M365F] [Microsoft 365 for financial services (data residency, double key encryption, customer-managed keys)](https://learn.microsoft.com/industry/financial-services/microsoft-365-fsi) -- search excerpt
- [ENAB] [Cloud service enablement framework for regulated financial institutions](https://learn.microsoft.com/industry/financial-services/service-enablement-framework) -- search excerpt
- [DEPR] [Deprecations in Microsoft for Financial Services](https://learn.microsoft.com/industry/financial-services/fsi-deprecation) -- search excerpt
- [PPWA] [What is Power Platform Well-Architected?](https://learn.microsoft.com/power-platform/well-architected/what-is-power-well-architected) -- search excerpt
- [DM] [Overview of Microsoft for Financial Services entities (Common Data Model)](https://learn.microsoft.com/common-data-model/schema/core/industrycommon/financialservices/overview) -- search excerpt

Every item is **manual**: it is exported as a question and scored only when answered with `-AssessmentAnswers`
(see [Questionnaire Answers](../assessment/questionnaire-answers.md)).

## The enumeration — 40 items across 7 groups

### Reliability (MCFS-RE) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| MCFS-RE-01 | Business-critical services are identified, with recovery objectives and impact tolerances set for each | Manual | REL, RES |
| MCFS-RE-02 | Workloads are designed for availability: multiple zones, redundancy of network and data, design for failure | Manual | REL, RES, AZ |
| MCFS-RE-03 | Changes are deployed by automation, with testing and validation, and with safe rollout techniques | Manual | REL |
| MCFS-RE-04 | Failures are detected, isolated and recovered through monitoring, alerting, and tested disaster recovery and continuity plans | Manual | REL, RES |
| MCFS-RE-05 | Capacity is planned and workloads scale to demand | Manual | REL, FSI |
| MCFS-RE-06 | Dependencies on cloud providers and third parties are mapped to critical use cases, and concentration risk is assessed | Manual | RES |
| MCFS-RE-07 | Exit plans exist for services that support critical or important functions | Manual | RES |

### Security (MCFS-SE) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| MCFS-SE-01 | Security governance covers monitoring, logging and a tested incident response plan with escalation | Manual | SEC |
| MCFS-SE-02 | Identity and access follow least privilege, with multifactor authentication and strong identity management | Manual -- Conditional Access policies are not in collect.json | SEC, FSI |
| MCFS-SE-03 | Customer security responsibilities for each service type (IaaS, PaaS, SaaS) are written down and owned | Manual | WAI, SEC |
| MCFS-SE-04 | Network, host and application layers have security controls that limit the effect of an attack | Manual | SEC, AZ |
| MCFS-SE-05 | Data is classified, encrypted at rest and in transit, and retained by policy; the strongest controls are used for the most sensitive data | Manual | SEC, FSI, AZ, M365F |
| MCFS-SE-06 | Applications and AI services built on the platform follow secure development and AI governance practices | Manual | SEC, FSI |
| MCFS-SE-07 | Defender for Cloud and Purview Compliance Manager are used to find and track security and compliance gaps | Manual | CT |
| MCFS-SE-08 | Payment cryptography uses a certified payment HSM where payment transactions are processed (if applicable) | Manual | AZ |
| MCFS-SE-09 | Data residency and sovereignty needs are met with the right residency, key and cloud options | Manual | FSI, M365F |

### Cost optimization (MCFS-CO) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| MCFS-CO-01 | Services use the right pricing model and size, with reservations or savings plans where use is steady | Manual | COST |
| MCFS-CO-02 | Supply is matched to demand through autoscaling and usage-based options | Manual | COST |
| MCFS-CO-03 | Idle and under-used resources are found and removed or right-sized | Manual | COST |
| MCFS-CO-04 | Costs are managed over time: budgets, tagging and cost allocation, plus licence and Dataverse storage management | Manual | COST |

### Operational excellence (MCFS-OE) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| MCFS-OE-01 | Azure, Power Platform and Dynamics 365 components are monitored together, with analytics exported for review | Manual | OPE |
| MCFS-OE-02 | Routine operations are automated to reduce manual effort and error | Manual | OPE |
| MCFS-OE-03 | Release engineering uses separate environments, solution lifecycle management and quality checks | Manual | OPE, PPWA |
| MCFS-OE-04 | Support processes, runbooks and incident handling cover the whole solution | Manual | OPE, WAI |
| MCFS-OE-05 | No deprecated Microsoft for Financial Services component is deployed or planned | Manual | DEPR |

### Performance efficiency (MCFS-PE) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| MCFS-PE-01 | Resource types and architecture were chosen for the performance each workload needs | Manual | PERF |
| MCFS-PE-02 | Workloads scale up and down, and caching and network optimisation are used where latency matters | Manual | PERF, RES |
| MCFS-PE-03 | Performance is logged and monitored so problems are found before users report them | Manual | PERF |
| MCFS-PE-04 | Power Platform and Dataverse service limits are designed for | Manual | PERF, PPWA |

### Configuration and extension (MCFS-CE) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| MCFS-CE-01 | The standard financial services data model and out-of-the-box configuration are used before anything is customised | Manual | DM, FSI |
| MCFS-CE-02 | Extensions use supported techniques and add to the standard solution without changing its managed components | Manual | PPWA, WAI |
| MCFS-CE-03 | Data model extensions are documented, owned and reviewed for upgrade impact | Manual | DM, PPWA |
| MCFS-CE-04 | Integrations with core banking and other systems are designed, documented and tested for failure | Manual | FSI, REL |
| MCFS-CE-05 | Copilots and AI features added through extension are scoped, secured and governed | Manual | FSI, SEC |

### Governance, compliance and operational resilience (MCFS-GV) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| MCFS-GV-01 | An Azure landing zone, with platform and application landing zones, hosts the Azure workloads | Manual | FSI, GOVF |
| MCFS-GV-02 | Azure Policy initiatives enforce the organisation and regulatory controls, with a compliance view | Manual | GOVF, FSI |
| MCFS-GV-03 | Applicable financial services regulations are identified for each jurisdiction and mapped to controls | Manual | RES, CT |
| MCFS-GV-04 | Cloud risk governance, risk tolerance and risk appetite are updated at least annually | Manual | RES |
| MCFS-GV-05 | New cloud services pass a service enablement review before production use | Manual | ENAB |
| MCFS-GV-06 | Audit evidence is available: Microsoft attestations and the Service Trust Portal are used for the Microsoft-responsible controls | Manual | FSI, CT |

## Summary

| Group | Items | Automated | Manual |
|---|---|---|---|
| Reliability | 7 | 0 | 7 |
| Security | 9 | 0 | 9 |
| Cost optimization | 4 | 0 | 4 |
| Operational excellence | 5 | 0 | 5 |
| Performance efficiency | 4 | 0 | 4 |
| Configuration and extension | 5 | 0 | 5 |
| Governance, compliance and operational resilience | 6 | 0 | 6 |
| **Total** | **40** | **0** | **40** |

## What an automated version would need

Everything below needs read-only access to the environment, a new collect section, and a gate on each rule so an
environment that was not read reports Not assessed instead of Pass.

| Items | What would be read | Interface and permission |
|---|---|---|
| MCFS-GV-01, GV-02, RE-02, SE-04, SE-07, CO-04 | Landing zone, policy assignments, zones, network controls, Defender plans, budgets and tags on the Azure side | Azure Resource Graph and ARM, which Scout already reads (see the Azure rule files) |
| MCFS-SE-02 | Conditional Access and multifactor policy | Microsoft Graph v1.0 `GET /identity/conditionalAccess/policies`; `Policy.Read.All` |
| MCFS-OE-03, OE-05, CE-02, CE-03 | Installed solutions, managed or unmanaged state, and which deprecated components are present | Dataverse Web API tables `solution` and `solutioncomponent` (not researched in this pass) |
| MCFS-OE-01 | Dataverse auditing and Application Insights export | Dataverse Web API `organizations` columns `isauditenabled`, `auditretentionperiodv2`; Power Platform admin center data export |
| MCFS-SE-07 | Compliance Manager assessments and improvement actions | No read API for Compliance Manager was found on Learn in this pass |

Items about risk governance, exit plans, regulation mapping, operating model and design intent (most of MCFS-RE,
MCFS-GV and MCFS-CE) have no API behind them and stay manual in any version.
