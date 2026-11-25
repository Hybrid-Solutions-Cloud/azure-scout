# Analytics Journey Tracker — enumerated source for the Analytics Journey Tracker assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `analytics.journey.yaml` scores the data and analytics capabilities Microsoft's
[Analytics Journey Tracker](https://learn.microsoft.com/en-us/assessments/c7c36e71-70a1-463d-a0c9-2155692f9fca/)
evaluates. The tracker is a data strategy accelerator: it measures capabilities and processes
across several pillars at five maturity levels, then helps build use cases, initiatives and a
roadmap. This page lists the items Scout asks, and every rule in that file cites an item number
from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Analytics Journey Tracker](https://learn.microsoft.com/en-us/assessments/c7c36e71-70a1-463d-a0c9-2155692f9fca/) (90 minutes, multiple choice and multiple response; question text and pillar names not published) |
| Framework version | Cloud Adoption Framework unified data platform scenario (planning, architecture, data governance, Fabric governance, operational standards) and the Microsoft Fabric adoption roadmap with its maturity levels, current on Microsoft Learn at the extraction date. Not versioned by Microsoft |
| Extraction date | 2026-11-25 |
| Verification method | The assessment landing page, the CAF unified data platform overview, planning, architecture, data governance, Fabric governance and operational standards pages, the Fabric adoption roadmap maturity-levels page and the CAF cloud-scale analytics URL were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. The Fabric adoption roadmap data culture, executive sponsorship and overview pages and the Microsoft Purview data governance overview were read through `microsoft_docs_search` excerpts the same day. Every `collect.json` property an automated item reads was checked against the header contract in `src/collect/Invoke-Collect.ps1`. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list, and the pillars are not Microsoft's.** The tracker's landing
page names five maturity levels, **Initial** (non-existent, unpredictable, reactive), **Evolving**
(frequently reactive, ad hoc), **Acceptable** (well characterised, more proactive than reactive),
**Advanced** (measured and controlled, predictable) and **Optimized** (stable, flexible, fed back
through improvement loops), but it does not name its pillars or publish its questions. The seven
areas below, and the `ANLJT-*` IDs, are **Scout's** grouping of the published guidance.

Scout does not assign a maturity level. Each item is a practice the guidance describes, written
so it can be answered Yes, Partial or No; Yes and No sit near the Acceptable-or-better and
Initial-or-Evolving ends of the five levels. The score is the share of items met.

The Cloud Adoption Framework's former cloud-scale analytics scenario no longer exists: its URL now
serves the **Unified data platform** guidance, which is the source used here, together with the
Fabric adoption roadmap's maturity-level topics. Microsoft has also stopped creating new Microsoft
Purview data governance accounts and is consolidating data governance into Fabric, so Purview
accounts are attached as evidence and never required.

Sources:

- [OV] [Unified data platform adoption](https://learn.microsoft.com/azure/cloud-adoption-framework/data/executive-strategy-unified-data-platform)
- [PLAN] [Planning for a unified data platform](https://learn.microsoft.com/azure/cloud-adoption-framework/data/planning-unified-data-platform)
- [ARCH] [Architecture for a unified data platform](https://learn.microsoft.com/azure/cloud-adoption-framework/data/architecture-unified-data-platform)
- [DG] [Data governance in a unified data platform](https://learn.microsoft.com/azure/cloud-adoption-framework/data/data-governance-unified-data-platform)
- [FG] [Fabric governance in a unified data platform](https://learn.microsoft.com/azure/cloud-adoption-framework/data/fabric-governance-unified-data-platform)
- [OPS] [Operational standards for a unified data platform](https://learn.microsoft.com/azure/cloud-adoption-framework/data/operational-standards-unified-data-platform)
- [FAR] [Microsoft Fabric adoption roadmap](https://learn.microsoft.com/power-bi/guidance/fabric-adoption-roadmap)
- [FML] [Microsoft Fabric adoption roadmap maturity levels](https://learn.microsoft.com/power-bi/guidance/fabric-adoption-roadmap-maturity-levels)
- [FDC] [Microsoft Fabric adoption roadmap: Data culture](https://learn.microsoft.com/power-bi/guidance/fabric-adoption-roadmap-data-culture)
- [FES] [Microsoft Fabric adoption roadmap: Executive sponsorship](https://learn.microsoft.com/power-bi/guidance/fabric-adoption-roadmap-executive-sponsorship)
- [PUR] [Data governance with Microsoft Purview](https://learn.microsoft.com/purview/data-governance-overview)

## How the items are answered

Most items are questions about how the organization works, which no Azure API can read. They are
**manual** rules: Scout lists them in `assessment-questions.csv` (or `Export-ScoutAssessmentQuestion`),
and a person answers `Yes`, `Partial`, `No` or `N/A`. See
[Questionnaire answers](../assessment/questionnaire-answers.md). Where collected Azure data bears on
a question, it is attached to the item as evidence, but the answer still decides the score. Items
marked ✅ are **automated** and **gated**: they run only when the resources they read exist (or the
data source was collected), so an estate without them reports the item Not assessed, never Passed
or Failed, and an answer file cannot override them.

## The enumeration — 52 items across 7 areas

### Strategy and business alignment (ANLJT-STR) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| ANLJT-STR-01 | An executive sponsor with enough authority across the organization drives the data and analytics strategy | ❌ Manual | FES, FML |
| ANLJT-STR-02 | Data and analytics goals are aligned to business goals, and each data product supports a defined business outcome | ❌ Manual | PLAN, FAR |
| ANLJT-STR-03 | A prioritized roadmap of data products exists, with an investment case and a fund, defer or reject decision for each proposal | ❌ Manual | PLAN |
| ANLJT-STR-04 | Funded data products are reassessed as priorities change, and those whose value no longer justifies the cost are reduced or retired | ❌ Manual | PLAN |
| ANLJT-STR-05 | A data culture is built deliberately: goals are set to advance informed decision-making and progress is tracked | ❌ Manual | FDC |

### Organization, operating model and skills (ANLJT-ORG) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| ANLJT-ORG-01 | A federated operating model combines organization-wide governance with accountable data domains | ❌ Manual | PLAN |
| ANLJT-ORG-02 | Each data domain has one senior owner with the authority to set priorities and resolve competing needs | ❌ Manual | PLAN |
| ANLJT-ORG-03 | Policies and platform guardrails that need consistency are centralized, with a documented exception process | ❌ Manual | PLAN |
| ANLJT-ORG-04 | A Center of Excellence has clear goals and scope and includes representation from every key business unit | ❌ Manual | FML |
| ANLJT-ORG-05 | Staffing follows the data product roadmap, using dedicated, shared or external staff as sustained demand justifies | ❌ Manual | PLAN |
| ANLJT-ORG-06 | Skills gaps are identified from the roadmap and closed with applied training and validated credentials | ❌ Manual | PLAN |
| ANLJT-ORG-07 | A community of practice and a champions network support users, so the community does not rely on a few individuals | ❌ Manual | FML |
| ANLJT-ORG-08 | User support and change management are defined, so changes to solutions and processes do not disrupt or slow users | ❌ Manual | FAR |

### Architecture and platform (ANLJT-ARC) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| ANLJT-ARC-01 | The data platform uses the existing Azure landing zone, with data services in workload landing zones, not a separate architecture | ❌ Manual — Microsoft Fabric capacities attached | ARCH |
| ANLJT-ARC-02 | A unified platform for data products (such as Microsoft Fabric with OneLake) is chosen, and existing platforms such as Azure Databricks are kept where they still meet requirements | ❌ Manual — Microsoft Fabric capacities attached | OV, OPS |
| ANLJT-ARC-03 | Fabric capacity is deployed per data domain through its own workload landing zone subscription, in an approved default region | ❌ Manual — Microsoft Fabric capacities attached | ARCH |
| ANLJT-ARC-04 | Source data reaches OneLake with the least movement: shortcuts first, then mirroring, then copying | ❌ Manual | OPS |
| ANLJT-ARC-05 | Operational databases are protected from direct analytical and AI queries unless the database owner has approved the workload | ❌ Manual — SQL servers attached | OPS |
| ANLJT-ARC-06 | A medallion (progressive refinement) pattern is the preferred way to transform data that benefits from it | ❌ Manual — Azure Databricks workspaces attached | OPS |
| ANLJT-ARC-07 | Microsoft Purview, or the governance service you chose, is placed in a workload landing zone and owned centrally, with governance domains aligned to data domains | ❌ Manual — Microsoft Purview accounts attached | ARCH |

### Data governance and security (ANLJT-GOV) — 14 items

| # | Item | Scout | Source |
|---|---|---|---|
| ANLJT-GOV-01 | A data inventory policy defines which data must be discoverable, starting with data behind critical processes, enterprise reporting and AI | ❌ Manual — Microsoft Purview accounts attached | DG |
| ANLJT-GOV-02 | Shared business concepts have an approved definition and an accountable owner, published in a glossary | ❌ Manual | DG |
| ANLJT-GOV-03 | Legal and contractual obligations are turned into data requirements in a central register, and compliance posture is monitored | ❌ Manual | DG |
| ANLJT-GOV-04 | Lineage is captured for important data products to the depth governance decisions need | ❌ Manual | DG |
| ANLJT-GOV-05 | Retention and disposition rules are set per data classification and implemented in Azure data services | ❌ Manual | DG |
| ANLJT-GOV-06 | One classification model and sensitivity-label taxonomy is applied across platforms, and protection is verified across transitions | ❌ Manual | DG |
| ANLJT-GOV-07 | Sensitive data is detected consistently, and data loss prevention covers defined risk scenarios | ❌ Manual | DG |
| ANLJT-GOV-08 | Workspace roles go to Entra security groups, and item and OneLake data access are limited to what each audience needs | ❌ Manual | FG |
| ANLJT-GOV-09 | Fabric inbound and outbound network access follows the organization's private connectivity standard | ❌ Manual | FG |
| ANLJT-GOV-10 | Azure Data Factory instances do not allow public network access | ✅ Data Factory `publicNetworkAccess` | DG, FG |
| ANLJT-GOV-11 | Azure Data Factory instances have a private endpoint | ✅ Data Factory to private endpoint | DG, FG |
| ANLJT-GOV-12 | Azure Data Factory instances use a managed identity | ✅ Data Factory `identityType` | DG |
| ANLJT-GOV-13 | Azure Synapse workspaces do not allow public network access | ✅ Synapse `publicNetworkAccess` | DG, FG |
| ANLJT-GOV-14 | Azure Synapse workspaces use a managed virtual network | ✅ Synapse managed virtual network | DG, FG |

### Data product lifecycle and operations (ANLJT-OPS) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| ANLJT-OPS-01 | Every published data product has an accountable owner, supported purpose, intended use, access process and quality status | ❌ Manual | OPS |
| ANLJT-OPS-02 | Minimum metadata is defined, so consumers can find the owning domain, owner, supported use and quality commitment | ❌ Manual | OPS |
| ANLJT-OPS-03 | Data products are discoverable in a catalogue and endorsed (promotion, certification) with consistent meanings | ❌ Manual | OPS |
| ANLJT-OPS-04 | The uses each data product supports are defined, and uses that change risk need extra review | ❌ Manual | OPS |
| ANLJT-OPS-05 | Reliability requirements are set per business-criticality tier, and business-critical data products have a tested recovery process | ❌ Manual | OPS |
| ANLJT-OPS-06 | Breaking changes and retirement follow a defined process, with affected consumers identified and a transition period given | ❌ Manual | OPS |
| ANLJT-OPS-07 | Production data products are released through a repeatable process matched to release risk (Git integration, deployment pipelines) | ❌ Manual | FG |
| ANLJT-OPS-08 | Each production data product has a named operational owner, with monitoring and alerting proportionate to its criticality | ❌ Manual | FG |

### Cost management and FinOps (ANLJT-FIN) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| ANLJT-FIN-01 | Cost allocation (showback or chargeback) assigns spend, including shared Fabric capacity, to data domains | ❌ Manual — Microsoft Fabric capacities attached | PLAN |
| ANLJT-FIN-02 | Data domains forecast spend from planned capacity and observed consumption, and update the forecast | ❌ Manual | PLAN |
| ANLJT-FIN-03 | Spending is reviewed against budget and data product value on a regular cadence | ❌ Manual | PLAN |
| ANLJT-FIN-04 | Capacity reservations are bought only once usage is predictable | ❌ Manual — Azure reservations attached | PLAN |
| ANLJT-FIN-05 | Capacity changes follow evidence of sustained demand, changes to shared capacity need approval, and surge protection is used where needed | ❌ Manual | FG |

### Adoption and value (ANLJT-VAL) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| ANLJT-VAL-01 | KPIs or OKRs track data culture goals and the business value of analytics solutions | ❌ Manual | FDC, FML |
| ANLJT-VAL-02 | User adoption is tracked through awareness, understanding, momentum and proficiency, not only usage counts | ❌ Manual | FML |
| ANLJT-VAL-03 | Solutions move through defined adoption phases, with testing, endorsement and clear ownership by the time they are valuable | ❌ Manual | FML |
| ANLJT-VAL-04 | Feedback loops are in place so data products and the data culture keep improving | ❌ Manual | FDC |
| ANLJT-VAL-05 | AI and agent workloads are grounded on governed, trusted data products | ❌ Manual — Azure AI services accounts attached | OV |

## Summary

| Area | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Strategy and business alignment | 5 | 0 | 5 |
| Organization, operating model and skills | 8 | 0 | 8 |
| Architecture and platform | 7 | 0 | 7 |
| Data governance and security | 14 | 5 | 9 |
| Data product lifecycle and operations | 8 | 0 | 8 |
| Cost management and FinOps | 5 | 0 | 5 |
| Adoption and value | 5 | 0 | 5 |
| **Total** | **52** | **5** | **47** |

Only five of the 52 items can be judged from Azure data: public network access, private endpoints
and managed identity on Azure Data Factory, and public network access and managed virtual network
on Azure Synapse. Each runs only when the estate has those resources. Fabric capacities, Purview
accounts, Databricks workspaces, reservations and AI accounts are attached to some questions as
evidence only. Scout does not read Fabric tenant settings, workspaces, OneLake security, lineage or
Purview content, because none is an Azure Resource Manager resource.
