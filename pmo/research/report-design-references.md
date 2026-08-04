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

## 5. Microsoft ALZ Review results page — the KBR example (added 2026-08-04)

**Where:** owner-supplied PDF (`Azure Landing Zone Review - KBR`, Desktop) + screenshots of the
live Learn assessments results page. Owner: *"do not have to copy exactly but this gives you an
idea."*

**What to take — the results presentation pattern:**
- **Overall result as a banded gauge**: one horizontal bar divided CRITICAL 0–67 / MODERATE
  67–133 / EXCELLENT 133–200 with a tick marker at *your* score ("Your result: 100/200"), a band
  chip ("MODERATE"), and a one-line verdict in words: *"Almost there. You have some room to
  improve but you are on track."* The band thresholds are visible — the reader sees where the
  next band starts.
- **"Categories that influenced your results"**: one compact tri-colour band bar PER design area
  (8 CAF areas + About-your-organization), each with its own tick marker and band label
  (EXCELLENT / MODERATE / CRITICAL) — nine areas comparable at a glance in one panel.
- **"Improve your results" — recommendations grouped by category**, each category block carrying:
  band chip, its own results-breakdown gauge ("Your result: 8/10"), then a table of
  **Recommendation (linked to Learn) | Priority | Notes** with a checkbox per row and an
  "Add a Note" affordance — the results page doubles as a working checklist.
- Filterable (All/…), **Export to CSV**, and 3-up next-step cards (accelerator, CAF guide,
  partner) at the top.

**Scout mapping:** the banded gauge + per-area band bars fit Executive mode and the consultant
domain scorecard directly (we already show arithmetic; add the band thresholds and verdict
sentence). The per-category recommendation table with Priority + Notes maps to our
findings-by-area, and a notes column that survives into CSV/Word export turns the report into
the working document the engagement actually uses. Our differentiator stays: theirs is
questionnaire-answered, ours is measured from the tenant.

## 6. Azure Local Documenter — inventory page screenshots (added 2026-08-04)

**Where:** owner-supplied screenshots of the Get-to-the-Cloud Azure Local Documenter running
(Overview + Cost Analysis pages). Owner: *"here are some examples for the inventory.. there is a
lot of improvements you can do using react."*

**What to take — the inventory presentation patterns:**
- **A per-category educational intro block** ("About Azure Local: …key components…") — two
  sentences of *what this technology is* before the data. Makes the inventory a document a
  customer learns from, not just a listing. Ours: short intro per category (what VNets are for /
  what to look for), collapsible.
- **Icon KPI card grid as the overview**: one card per category — icon, big count, label,
  clickable through to the section (2 Clusters · 6 Nodes · 36 Logical Networks…). Better landing
  than a table of counts.
- **The "Cost Optimization Opportunity" callout**: a visually distinct card that QUANTIFIES the
  saving ("By enabling Azure Hybrid Benefit on all nodes you could save Monthly $1,920 /
  Yearly $23,040") and ends with an explicit **Action:** line. Maps directly onto our new AHB
  rule — we can compute the same savings estimate from core counts.
- **Arithmetic visible on every number**: "$1920.00 · Based on $10/core/month",
  "1920.00 × 12 months", "0 of 6 nodes enabled". Same principle as our score formulas, applied
  to cost.
- **Status chips inside inventory tables** (amber "✗ NOT ENABLED" per node row) — state is
  legible per row, not only in a summary.
- **Provenance footer**: "Pricing as of 2024-03-04 … view official pricing" — every derived
  number carries its as-of date and source link.
- Header bar: "Last updated" timestamp + prominent **Export PDF**; connection banner naming the
  account and subscription the data came from.

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
