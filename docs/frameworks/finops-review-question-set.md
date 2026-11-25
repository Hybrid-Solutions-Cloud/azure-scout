# FinOps Review — enumerated source for the FinOps Review assessment

**Enumerated 2026-08-01; re-verified and aligned to the FinOps Framework 2026 on 2026-11-24.
Verification method and limits are stated below — read them before quoting any coverage number from
this page.**

**Framework version:** FinOps Framework 2026 (FinOps Foundation, 2026-03-20 update; 4 domains / 22
capabilities) per Microsoft FinOps Review (New) `60c02533-b280-4dec-ac5f-3f10cdd238b9`, verified
2026-11-24. Microsoft does not number the assessment itself; the verification date above is the
version, per `docs/frameworks/README.md`. Re-date this line when this file is next re-verified.

This is the AB#6814 enumeration for target #9 in the audit's fourteen-assessment programme
(`pmo/audits/AZURE-SCOUT-AUDIT.md` §14): *"FinOps Review — Cost surface exists … `waf.cost` (6
rules) + `caf.billing` (misnamed, holds cost rules)."* Neither existing file scores against the
FinOps Framework itself — they score WAF's Cost Optimization pillar and (mislabelled) cost-cleanup
rules respectively. Per DQ12, no FinOps-Framework-shaped rule file is written until this enumeration
exists.

## What the FinOps Review is

The **FinOps Review** is an interactive assessment on the Microsoft Assessments platform,
multiple-choice/multiple-response, described as *"a lightweight, self-guided assessment"* to
*"identify capability gaps."* It is published under two assessment ids, and as of 2026-11-24 **both
render the same "FinOps Review (New)" page**:

| Assessment id | Status |
|---|---|
| `60c02533-b280-4dec-ac5f-3f10cdd238b9` | The current "FinOps Review (New)" — <https://learn.microsoft.com/en-us/assessments/60c02533-b280-4dec-ac5f-3f10cdd238b9/>. This is the id Scout cites. |
| `ad1c0f6b-396b-44a4-924b-7a4c778a13d3` | The original FinOps Review id (<https://learn.microsoft.com/en-us/assessments/ad1c0f6b-396b-44a4-924b-7a4c778a13d3>). It now renders the same "(New)" page, so it is an alias, not a separate assessment. |

Its subject is the **FinOps Framework** from the FinOps Foundation. Microsoft publishes the framework
on Learn (<https://learn.microsoft.com/cloud-computing/finops/framework/finops-framework>, capability
list at <https://learn.microsoft.com/cloud-computing/finops/framework/capabilities>). The framework
organises **22 capabilities** into 4 domains — 3 operational domains (Understand usage and cost,
Quantify business value, Optimize usage and cost) plus one practice-management domain (Manage the
FinOps practice). This enumeration is built from that published capability list, using the 2026
capability names.

## What changed in the FinOps Framework (2025 and 2026)

The FinOps Foundation updates the framework each March
(<https://www.finops.org/insights/2026-finops-framework/>):

- **2025-03-20 update:** added the **Scopes** construct (how the framework is applied to a defined
  part of the estate or organisation) and renamed "Cloud Policy & Governance" to "Policy &
  Governance".
- **2026-03-20 update:** renamed several capabilities (table below) and added the **Executive
  Strategy Alignment** capability. The framework is still 4 domains / 22 capabilities, because
  Onboarding Workloads no longer appears in the Foundation's list (its Foundation page returns
  404).
- **Microsoft Learn lag:** the Learn capability list at the URL above still lists Onboarding
  Workloads and does not yet list Executive Strategy Alignment.

Scout resolves the mismatch by keeping both: **23 rules** — the 22 capabilities Microsoft Learn
lists (Onboarding Workloads kept, labelled as no longer in the Foundation 2026 list) plus
`FINOPS-M09` Executive Strategy Alignment. Rule ids are unchanged by the renames, so existing
questionnaire answer files keep working.

### Capability rename map

| Rule id | Previous name (Scout enumeration / earlier framework) | 2026 name (used in rule titles) |
|---|---|---|
| FINOPS-Q04 | Benchmarking | **KPIs & Benchmarking** |
| FINOPS-O01 | Architecting for the cloud | **Architecting & Workload Placement** |
| FINOPS-O02 | Workload optimization | **Usage Optimization** |
| FINOPS-O05 | Cloud sustainability | **Sustainability** |
| FINOPS-M04 | Policy and governance | **Governance, Policy & Risk** |
| FINOPS-M07 | FinOps tools and services | **Automation, Tools & Services** |
| FINOPS-M08 | Intersecting frameworks | **Intersecting Disciplines** |
| FINOPS-M03 | Onboarding workloads | Unchanged name, but **a Microsoft Learn capability no longer in the FinOps Foundation 2026 list** — kept and labelled |
| FINOPS-M09 | (did not exist) | **Executive Strategy Alignment** — new in 2026 |

Unchanged capabilities: Data ingestion (U01), Allocation (U02), Reporting & analytics (U03),
Anomaly management (U04), Planning & estimating (Q01), Forecasting (Q02), Budgeting (Q03), Unit
economics (Q05), Rate optimization (O03), Licensing & SaaS (O04), FinOps education & enablement
(M01), FinOps practice operations (M02), Invoicing & chargeback (M05), FinOps assessment (M06).

## Verification method — and the one thing this enumeration is NOT

**What was read (2026-08-01, re-checked 2026-11-24):**

| Source | What it gave |
|---|---|
| The FinOps Review (New) assessment landing page (`60c02533-…`) | Confirms the assessment exists, its duration/format, and that it is self-guided against the FinOps Framework. **No question text.** |
| [FinOps Foundation 2026 framework update](https://www.finops.org/insights/2026-finops-framework/) | The 2026 capability renames and the new Executive Strategy Alignment capability |
| [FinOps capabilities](https://learn.microsoft.com/cloud-computing/finops/framework/capabilities) | The Microsoft Learn 22-capability, 4-domain structure (still lists Onboarding Workloads) |
| [Optimize usage and cost](https://learn.microsoft.com/cloud-computing/finops/framework/optimize/optimize-cloud-usage-cost) | Per-capability definitions for the Optimize domain |
| [Quantify business value](https://learn.microsoft.com/cloud-computing/finops/framework/quantify/quantify-business-value) | Per-capability definitions for the Quantify domain |
| `src/collect/Get-ScoutCostInventory.ps1`, `src/analyze/Get-ScoutCostAnomaly.ps1` | Ground truth for what cost data Scout actually collects and computes, versus what is merely available as an unused function — read directly, not inferred from the audit |

**⚠️ The assessment's own question TEXT and NUMBERS are not published.** Microsoft publishes no
question text for the New review either. The `FINOPS-*` identifiers and the question wording below
are **Scout's own inference** from the published framework's capability names — Microsoft attributes
the framework itself to the FinOps Foundation, not to the assessment. A Scout score against this
file is not a Microsoft FinOps Review score.

**Shelf life.** The FinOps Framework updates every March and the FinOps toolkit ships monthly
releases (see the toolkit's own roadmap page); re-verify before quoting.

## The enumeration

### Understand usage and cost

| # | Item | Scout can evidence? |
|---|---|---|
| FINOPS-U01 | Cost and usage data is ingested from the cloud provider (and ideally other sources) into a single accessible repository | ⚠️ Partial — `src/collect/Get-ScoutCostInventory.ps1` (per-subscription cost grouped by type/resource group/location/service) exists but is **opt-in**: it requires `Az.CostManagement`, which is deliberately excluded from Scout's core manifest dependencies because installing it can force an incompatible `Az.Accounts` upgrade. No non-Azure source is ever ingested. |
| FINOPS-U02 | Cost is allocated meaningfully — broken down by tag, resource group, or business unit | ⚠️ Partial — cost is grouped by resource group/location/service/type per subscription; that grouping is not joined to `$.tags[*]`, so tag-based allocation is not currently possible from the same dataset |
| FINOPS-U03 | Cost and usage data is reported on and made visible to stakeholders | ⚠️ Partial — a "Costs" worksheet is produced via `Start-AZTIExtractionOrchestration.ps1`, but that call path is separate from the unified `-Assessment` entry point's `collect.json`, so no rule can currently query it |
| FINOPS-U04 | Anomalies (spikes, unexpected changes) are proactively identified and reacted to | ⚠️ Partial — `src/analyze/Get-ScoutCostAnomaly.ps1` implements three independent detection techniques (spike, z-score, IQR) against `Get-ScoutCostInventory` output, wired into the collect pipeline (AB#6826) |

### Quantify business value

| # | Item | Scout can evidence? |
|---|---|---|
| FINOPS-Q01 | Cost and usage of new or changing workloads is predicted before deployment | ❌ Not collected — no pre-deployment cost-estimation data source |
| FINOPS-Q02 | Future cost is forecast from historical trends | ✅ `Management/Budgets` ("Forecast Spend" field) |
| FINOPS-Q03 | Budgets are actively monitored and managed, with alerts configured | ✅ `Management/Budgets` ("Amount", "Current Spend", "Budget Used %", "Alerts Configured") |
| FINOPS-Q04 | **KPIs & Benchmarking** — cloud efficiency is measured with KPIs and benchmarked against internal teams or industry peers | ❌ Not collected — no KPI or benchmarking dataset |
| FINOPS-Q05 | Unit economics (cost per business unit of value) are calculated | ❌ Not collected — requires business-metric data outside Azure's control plane |

### Optimize usage and cost

| # | Item | Scout can evidence? |
|---|---|---|
| FINOPS-O01 | **Architecting & Workload Placement** — cloud solutions are architected for cost efficiency and placed deliberately during design/migration, not retrofitted after deployment | ❌ Design-time decision, not observable post-deployment |
| FINOPS-O02 | **Usage Optimization** — workload cost/usage is analyzed to identify efficiency opportunities | ✅ `$.advisor[?(@.Category == 'Cost')]`, `$.costCleanup.orphanedDisks[*]`, `$.costCleanup.orphanedPips[*]` |
| FINOPS-O03 | Rate optimization is pursued — reservations, savings plans, commitment-discount planning | ✅ `General/Reservations`, `General/ReservationRecom` |
| FINOPS-O04 | Software licenses and prepaid SaaS products (including Azure Hybrid Benefit) are tracked and fully utilized | ✅ Windows VMs without Azure Hybrid Benefit (`$.compute.virtualMachines` `licenseType`) |
| FINOPS-O05 | **Sustainability** — carbon emissions are measured alongside cost as part of cloud sustainability | ❌ Not collected — Scout has no Emissions/Carbon API collector |

### Manage the FinOps practice

This domain is almost entirely organisational — it describes running and maturing the FinOps
practice itself, not the resources it manages.

| # | Item | Scout can evidence? |
|---|---|---|
| FINOPS-M01 | A FinOps education and enablement programme exists | ❌ Organisational |
| FINOPS-M02 | FinOps practice operations (cadence, ownership, processes) are defined | ❌ Organisational |
| FINOPS-M03 | **Onboarding Workloads** — workloads are onboarded to the FinOps practice based on financial/technical feasibility. *Microsoft Learn capability, no longer in the FinOps Foundation 2026 list.* | ❌ Organisational |
| FINOPS-M04 | **Governance, Policy & Risk** — FinOps-specific policy and governance (cost-allocation tagging, spend guardrails) is enforced | ⚠️ Partial — `$.tags[*]`, `Management/PolicyAssignments` are generic governance signals, not FinOps-specific enforcement |
| FINOPS-M05 | Invoices are reconciled and cross-charged (chargeback/showback) to internal teams | ❌ Not collected — same billing-hierarchy gap `caf.billing.yaml`'s misnaming note documents (EA/MCA enrollment, invoice sections) |
| FINOPS-M06 | The FinOps practice's own maturity is periodically reassessed | ❌ Organisational — this is the meta-capability describing running assessments like this one |
| FINOPS-M07 | **Automation, Tools & Services** — FinOps tools, automation and services are selected and integrated to fit organizational needs | ❌ Organisational/tooling choice |
| FINOPS-M08 | **Intersecting Disciplines** — FinOps practices are aligned with intersecting disciplines (ITAM, ITSM, security, sustainability) | ❌ Organisational |
| FINOPS-M09 | **Executive Strategy Alignment** *(new in the 2026 framework)* — FinOps informs executive priorities, multi-year investment strategy, product prioritisation and strategic decision support | ❌ Organisational — manual rule |

## What this means for the rule file

`src/assess/rules/finops.review.yaml` holds **23 rules**: the 22 Microsoft Learn capabilities plus
`FINOPS-M09`. Of these, 7 are automated (U01, U04, Q02, Q03, O02, O03, O04), and 16 are manual
(U02, U03, Q01, Q04, Q05, O01, O05, M01–M09). The Manage domain (9 capabilities) is close to a hard
floor — it is organisational, and even tagging/policy gives only generic governance data, not
FinOps-specific signal. The more consequential finding is upstream of any rule file:
**`Get-ScoutCostInventory` is gated behind an opt-in module Scout deliberately does not install**, so
`FINOPS-U01` and `FINOPS-U04` — the "Understand usage and cost" domain's automated half, which every
other Optimize/Quantify capability ultimately depends on — only score in an environment where an
operator has separately installed `Az.CostManagement`; without it they report NotAssessed, never a
scored zero.
