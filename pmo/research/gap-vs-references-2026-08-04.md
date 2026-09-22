# Gap analysis — tonight's React report vs the reference deliverables

**Date:** 2026-08-04. **Compared:** the current `report-react.html.template` (branch
`feat/ab6928-react-report-v2`, tppoc render) against the BECU teardown
(`R4-reference-deliverable-teardown.md`) and the documenter/Microsoft/ARI notes
(`report-design-references.md`). Requested by the owner after reviewing the tppoc example:
*"it is getting better.. but still doesn't compare to those examples."* He is right. This is the
measured delta, not a defence.

## The BECU chapter unit vs our chapter unit

BECU, measured: `Chapter → scorecard table (maturity, risk, why it matters) → Current State
→ 1–3 tables AT RESOURCE GRAIN → 0–1 figure`, ×7 identical.

Ours tonight: `Area chapter → prose sentence(s) → ONE findings table → (no figure)`.

| # | BECU has | We have tonight | Verdict |
|--:|---|---|---|
| 1 | **Per-chapter scorecard table** — maturity band, risk level, why the domain matters | One scorecard table for the whole assessment at the top; chapters open with prose only | ❌ missing |
| 2 | **Findings tables at RESOURCE grain** — rows are resources with real columns | Rows are *rules*; resources hide behind a click-to-expand; remediation is a long sentence **crammed into one cell** (same defect class the owner flagged on drift) | ❌ wrong grain |
| 3 | **0–1 figure per chapter** | 2 figures per assessment (score-by-area, roadmap), none per chapter | ❌ missing |
| 4 | **Current State = multi-paragraph narrative** naming what exists | 2–4 generated sentences of counts | ⚠️ thin |
| 5 | Exec summary front matter: **in-scope inventory, findings dashboard, methodology, KRIs, 30-day plan, infra overview** (6 named tables + 4 figures before Chapter 1) | KPI row + spotlight finding + severity donut | ❌ mostly missing |
| 6 | **Maturity summary + 90-day roadmap** as closing chapter, 3 tables | Roadmap diagram only, no tables | ⚠️ partial |
| 7 | **Appendices** (subscription detail, SP inventory, gap register) keeping the body narrative | None — long content sits inline or nowhere | ❌ missing |
| 8 | Cover, Document Information, TOC | ✅ have (cover, identity block, TOC in consultant) | ✅ |
| 9 | Benchmark conformance as a named story | ✅ added tonight | ✅ |
| 10 | Absence-fails explained in words | ✅ added tonight | ✅ |

## Inventory vs the documenter family

| # | Documenters have | We have tonight | Verdict |
|--:|---|---|---|
| 11 | **Per-domain tables with domain-specific columns** (VM: name/size/OS/power state; network: vnet/prefix/peering) | Generic first-5-columns of whatever the collector emitted | ❌ the big one |
| 12 | Narrative per domain | One generated sentence + sample table | ⚠️ thin |
| 13 | Estate summary + counts | ✅ added tonight (lede, KPIs, by-category/by-region bars) | ✅ |
| 14 | Audit callouts | ✅ added tonight (5 checks) — documenters have more | ⚠️ partial |
| 15 | Topology / org diagrams | ✅ have (kernel-drawn, collision-checked) | ✅ |

## Cross-cutting

| # | References have | We have | Verdict |
|--:|---|---|---|
| 16 | **Prose density** — BECU is 5,643 paragraphs; consultants write sentences a customer reads | Generated single sentences | ❌ the qualitative gap behind "it just isn't there" |
| 17 | Microsoft: **curated next steps** separate from the findings list | Roadmap diagram only | ⚠️ partial |
| 18 | Drift as a readable section | ✅ fixed tonight (was JSON.stringify into one cell) | ✅ |

## What closes the most gap per unit of work (ordered)

1. **#2 resource-grain findings tables** — when a rule fails against N resources, the table rows
   are the N resources (name, RG, subscription, what's wrong), not one rule row. The evidence
   pipeline now supplies this; the renderer just doesn't lay it out. Also un-crams remediation
   from a table cell into a paragraph under the chapter.
2. **#1 per-chapter scorecard table** — maturity band, weight, checks passed/failed, risk verdict
   per design area. Data already in `areas[]`.
3. **#5 exec-summary front matter** — in-scope inventory table + findings dashboard + methodology
   note are all derivable from the payload today.
4. **#11 per-domain inventory columns** — a per-category column map (VMs, VNets, storage, …)
   replacing first-5-columns. Mechanical but long; one category at a time.
5. **#3 per-chapter figure** — severity mini-bars per area from the kernel.
6. **#16 prose** — narrative templates per CAF area (what good looks like, what we observed,
   what it means) rather than a counting sentence. Biggest lift, biggest feel difference.

Items 1–3 are hours each, not days. Item 6 is where "consultant-grade" actually lives and should
be designed per assessment (AB#6938's real scope), not generated generically.
