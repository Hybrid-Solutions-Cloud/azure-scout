# Report design references — the quality bar

**Status:** living document. Owner-supplied references for what azure-scout's reporting should
look like. Added to as more are given. Read this before designing report content or visuals.

Tracked under Feature **AB#6928** (the React report the product ships) and Epic **AB#6450**.

---

## 1. The BECU deliverables — the depth bar

**Where:** attachments on ADO work item **AB#6443**. Teardown committed at
`pmo/research/R4-reference-deliverable-teardown.md`.
**Client data — never commit the files themselves.** Download to a scratch folder only.

Real consulting deliverables from a governance engagement. This is the bar for *depth*.

| Artefact | Measured structure |
|---|---|
| Word report | 5,643 paragraphs · **43 tables** · **9 figures** · 7 chapters |
| Deck | 11 slides · dense → visual → dense rhythm · 0 tables (all shapes) |
| Workbook | 13 sheets = Cover + **12 tabs, one per GAP CLASS** |

**What to take:**
- **The chapter unit, repeated identically:** domain scorecard table → *"Current State"* prose →
  1–3 findings tables → 0–1 figure.
- **Executive summary comes FIRST** — before chapter 1. The conclusion leads.
- Exec summary contains: in-scope inventory, findings dashboard, maturity methodology, KRIs,
  30-day plan, infrastructure overview.
- Ends with an Overall Maturity Summary & **90-day roadmap**, then appendices.
- Workbook organised **one tab per gap class**, named for the gap — not per collector, not per
  severity. Cover carries a contents index **with per-tab record counts**.
- The deck's **risk heatmap**, and its single highest-value slide: **"Potentially
  Actively-Exploitable Item"**.

---

## 2. Get to the Cloud — the "Documenter" family

**Where:** <https://azuredocumenter.com> ·
<https://www.gettothe.cloud/tool-azure-landing-zone-documenter/> ·
<https://www.gettothe.cloud/tool-azure-local-documenter/>
**Repos:** `github.com/GetToThe-Cloud/documenter-azure-landingzone` ·
`documenter-azure-local` · `documenter-azure-azurevirtualdesktop`

**Independent validation of our architecture:** they also ship an **interactive HTML5 report with
search and filtering, plus PDF export** — the same bet made in v3.3.4 when every other format went
on hold.

**What to take:**
- **Global search across the entire report**, not just per-section filters.
- **Concrete per-domain tables.** Their Azure Local report does hardware per node
  (manufacturer, model, cores, memory), VM detail with power states, logical networks, storage
  paths, Arc services and extensions. Specificity is what makes a document feel substantial.
- A **WAF assessment across the 5 pillars living inside the same HTML report**.
- Topology and connection diagrams.

**Coverage gaps this exposes — azure-scout collects neither today:**
- **Licensing / Azure Hybrid Benefit analysis**
- **Cost projections (monthly / yearly)**

---

## 3. Microsoft Assessments — the results-page anatomy

**Where:** <https://learn.microsoft.com/en-us/assessments/> ·
FAQ: <https://learn.microsoft.com/en-us/assessments/support/> ·
annotated results-page screenshot: `/assessments/media/resultspage.png`

**Catalogue:** Cloud Journey Tracker · Governance Benchmark · Azure Well-Architected Review ·
Strategic Migration Assessment and Readiness Tool (SMAT).

Owner's framing: *"even Microsoft has better results."*

**What to take:**
- An overall score presented as a **benchmark** — where you sit on the journey, not just a number.
- **Curated next steps** as a first-class element, separate from the full findings list.
- **Tailored recommendations per category**, each carrying its own guidance links.
- Results **exportable to CSV** and shareable.

Deeper analysis of Microsoft's scoring and structure: `pmo/research/microsoft-assessment-methodology.md`
(notably the Secure Score pattern — published formula, fixed per-control weights, N/A excluded
from *both* numerator and denominator, and a "potential score increase" per control).

---

## 4. microsoft/ARI — the project azure-scout forked from

**Where:** <https://github.com/microsoft/ARI>

Owner: *"even the solution we forked from — their reporting was way better."*
**Note:** he does **not** want Excel-first delivery back yet. Take the visualisation, not the
format.

**What to take — the diagrams are ARI's real strength:**
- **Network topology exported as draw.io XML with interactive hover** revealing resource detail,
  including peering detail; scope switchable (`-DiagramFullEnvironment`).
- An **organisation hierarchy** diagram.
- **Subscription-level resource maps.**
- Charts generated automatically — their `-Lite` switch exists purely to *skip* charts, which says
  how central they considered them.

**Also collects (cross-check against our 242 collectors):** Security Center, tags, Azure Policy,
**VM family specs — vCPUs, memory, quota** — Cost Management, Advisor.

---

## The standing instruction

> "All these examples… I want you to design and create a solution that provides more details,
> nicer looking graphs and charts, etc."
> — owner, 2026-08-04

So this is a **design** task, not only a port: richer per-assessment content **and** materially
better data visualisation.

## Related research in this folder

- `microsoft-assessment-methodology.md` — how Microsoft structures and explains assessment scores
- `R4-reference-deliverable-teardown.md` — the BECU structural teardown (structure only)
- `documenter-tools-comparison.md` — competitor/peer tooling comparison and ranked steal-list
- `azgovviz-methodology-evaluation.md` — Azure Governance Visualizer evaluation
