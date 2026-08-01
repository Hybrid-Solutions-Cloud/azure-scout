# Reporting engine v2 — design

**Work item:** User Story AB#6443 (Feature AB#6449, Epic AB#6450)
**Status:** Design — approved scope, tasks created beneath AB#6443
**Date:** 2026-08-01

---

## 1. The problem, stated plainly

Azure Scout's renderers do not produce a deliverable. They produce a dump of rule
results.

The Word renderer — the flagship document — emits five sections: a cover, a table of
framework percentage scores, a `Id / Severity / Status / Title` table per area, a top-50
gap table with the same four columns, and a manual-review list. Every row is a rule id
and a rule title. There is no narrative, no number describing the estate, no named
resource, no recommended action, no owner, no sequence, no target state.

The engine already computes more than this. `Invoke-Rule.ps1` attaches
`EvidenceCount`, up to 25 rows of `Evidence` (the actual matched Azure objects), and a
`Remediation` string to every finding. **Word, PDF and PPTX read none of those three
fields.** The data required to write "60 of 198 storage accounts had Public Network
Access enabled" is present in the findings object at render time and is discarded.

That is the gap. It is not a styling problem.

## 2. The reference bar

Seven deliverables from a prior manual engagement are attached to AB#6443 and were read
in full. They set the target. Reduced to structure:

### 2.1 The Word report (43 tables, 9 figures, 146 paragraphs)

| Section | What it contains |
|---|---|
| Cover | Title, framework line, org / project / tenant / in-scope MGs / in-scope subs / date / classification |
| Document Information | Version, author, review date, classification, **frameworks referenced**, distribution list, source-data provenance |
| Table of Contents | 14 numbered entries |
| Executive Summary → In-scope inventory | Stat tiles: subs by environment, MGs, VNets, subnets, storage, private endpoints, policy assignments, SPs/MIs |
| Executive Summary → narrative | Three prose blocks: what is structurally sound, what drags the score down, **how to read the score** |
| Findings Dashboard | One row per domain: score, *what is working*, *what needs attention* |
| Maturity Scoring Methodology | The 1–10 rubric with five named bands, plus what each domain's score weights |
| Key Risk Indicators | Risk area / current state **with the supporting number** / severity — including `GOOD` rows for deliberate strengths |
| Initial 30-Days Plan | Numbered workstreams with an outcome sentence each |
| Infrastructure Overview | Prose description of the estate |
| Top 5 Immediate Action Items | Five paragraphs naming specific resources and the exact change |
| Prioritised Focus Areas | Domains ranked by composite urgency: rank / domain / score / status / priority |
| Chapters 1–7 (one per domain) | `Maturity Score: n/10 \| Status`, **WHY THIS MATTERS**, **Current State** prose, a domain inventory table, and a **per-subscription findings & action items** table |
| Overall Maturity Summary | Domain / current / 90-day target / gap / priority, with a composite row |
| 90-Day Remediation Roadmap | Three 30-day phases; each row is domain / action / **owner** / **window** |
| Exit criteria | Seven measurable statements |
| Appendix A | Every in-scope subscription: id, MG, quota tier, MDfC score, free-plan count, diag-setting count, assignment count, non-compliant record count |
| Appendix B | Service principal inventory with headline counts |
| Appendix C | **Consolidated gap register** — domain / current state (observed) / target state / severity / closure action |
| Scope & Assumptions | Who requested it, who ran it, what is explicitly out of scope, what the score means |

### 2.2 The PowerPoint executive readout (11 slides)

Title · Scope & approach (4 stat tiles + methodology paragraph + accountability split) ·
Executive summary (3 numbered takeaways) · Section scorecard (7 domain tiles, each a
number + band label, plus a band average) · Control-stack slide · Key Risk Indicators
(two columns, severity-graded, `GOOD` rows included) · Risk heatmap · One deep-dive slide
for the single actively-exploitable item · Gap summary grouped by accountable team ·
Roadmap timeline with quarter markers and T-shirt effort sizing.

### 2.3 The Excel gap-inventory workbook (13 tabs)

A **Cover** tab carrying scope, source, classification, a four-value **legend**, and a
contents index of every tab with its record count and a one-line verdict mix. Then one
tab per gap class (deprecated policy assignments, deprecated policy-set entries, policy
exemptions, non-group Owner, non-group UAA, orphaned role assignments, unused custom
roles, storage public-network, storage public-blob, storage TLS 1.0, …), each with the
full record set, full ARM ids, and — the load-bearing column — a per-row **Verdict**:

- `Real — investigate`
- `Platform-required / deliberate vending pattern`
- `Sandbox / out-of-scope by design`
- `Inherited from legacy / TenantRoot`

This is what turns 149 raw Owner assignments into "141 deliberate vending SPs + 8
humans". Without it a raw count is noise.

## 3. What the reference implies that Scout does not have

1. **A per-domain 1–10 maturity score with named bands.** Partially present:
   `Get-GovernanceDomainScore.ps1` relabels the 0–100 percentage onto 1–10 for the seven
   CAF Govern categories, and `Export-GovernanceReport.ps1` charts it. It is not in the
   Word, PDF or PPTX output, and there is no rubric text anywhere.
2. **A target state per gap.** Rules carry `remediation` (an action) but no
   `targetState` (the condition that closes it). The gap register needs both.
3. **An owner and a window per action.** Nothing in the rule schema carries these.
4. **"Why this matters" per domain.** Nothing carries this.
5. **Resource-level attribution.** `Evidence` holds the matched objects but nothing
   projects them to `(subscription, resource name, resource id)` for a per-subscription
   findings table.
6. **A triage verdict per evidence row.** Nothing supports classifying a hit as
   by-design vs real.
7. **A composite score, a target, and a phased roadmap.** Nothing derives these.
8. **Provenance and scope declaration.** `_meta.scope` / `_meta.managementGroupId` exist;
   in-scope MG list, subscription counts by environment, exclusions and the source-scan
   date do not.

## 4. The architectural decision

**Every renderer stops deriving its own view of the run. A single builder produces one
report model; renderers become presentation only.**

Today five renderers independently walk `$Findings` and each drops a different subset —
which is precisely why Word loses evidence, Power BI loses it too, and the governance
1–10 score exists in exactly one HTML page. Adding narrative to five renderers
independently would multiply that divergence by the size of the new surface.

```
collect.json ─┐
              ├─→ Get-Score ─→ findings.json ─┐
rules/*.yaml ─┘                               ├─→ Build-ScoutReportModel ─→ report-model.json
                                              │           │
                             manifests/report-narrative.yaml           │
                                                          │
        ┌────────────┬────────────┬───────────┬───────────┼───────────┐
      Word          PDF         PPTX        Excel      Power BI     HTML/React
```

`report-model.json` is a committed contract, versioned with a `SchemaVersion` field, and
is itself an output artefact (a consumer can build their own renderer against it).

### 4.1 The model

```
ReportModel
  SchemaVersion        "2.0"
  Engagement           Organisation, Project, TenantId, AssessmentDate, Classification,
                       Author, DistributionList, SourceDataProvenance, FrameworksReferenced[]
  Scope                InScopeManagementGroups[], InScopeSubscriptions[], Exclusions[],
                       Assumptions[]
  Inventory            Tiles[] { Label, Value, Unit }          ← counted from Collect
  Maturity
    Rubric             Bands[] { Min, Max, Level, Description }
    Domains[]          { Domain, Score, Band, NotAssessed, PercentScore,
                         Pass, Partial, Fail, Manual, Unknown, Error,
                         WhyThisMatters, CurrentState, WhatIsWorking, WhatNeedsAttention,
                         TargetScore, Priority }
    Composite          { Current, Target, Gap, Band }
  KeyRiskIndicators[]  { RiskArea, CurrentState, Severity, SupportingCount }
  FocusAreas[]         { Rank, Domain, Score, Status, Priority }
  GapRegister[]        { GapId, Domain, CurrentStateObserved, TargetState, Severity,
                         ClosureAction, Owner, Effort, EvidenceRef }
  Roadmap
    Phases[]           { Phase, DayRange, Items[] { Domain, Action, Owner, Window } }
    ExitCriteria[]
  Evidence[]           { GapId, RuleId, SubscriptionId, SubscriptionName,
                         ResourceGroup, ResourceName, ResourceId, ResourceType,
                         Observation, Verdict }
  Appendices
    Subscriptions[]    per-subscription detail rows
    Findings[]         the raw scored findings, unchanged, for traceability
  Meta                 GeneratedOn, ScoutVersion, RunId, Scope, ManagementGroupId
```

### 4.2 Where the narrative comes from

Prose is **authored, not generated**. A new `manifests/report-narrative.yaml` carries,
per domain: `whyThisMatters`, the `targetScore`, and the sentence templates for
`whatIsWorking` / `whatNeedsAttention` with `{count}` / `{total}` placeholders bound to
rule ids. `CurrentState` is assembled from the domain's failing rules and their evidence
counts against those templates.

This is a hard constraint and it is the same constraint the audit imposes elsewhere: the
report may not assert anything the collected data does not support. A generated sentence
is bound to a rule id and an evidence count, or it is not emitted.

### 4.3 Rule schema additions

Three optional keys per rule, defaulting to `null`:

```yaml
- id: CGOV-SC-02
  title: "..."
  severity: high
  remediation: "..."        # existing — the action
  targetState: "..."        # NEW — the condition that closes the gap
  owner: "Security Engineering"   # NEW — the accountable function
  effort: M                 # NEW — S | M | L | XL (4-8 / 8-12 / 12-16 / 16+ weeks)
  phase: 1                  # NEW — 1 | 2 | 3, which 30-day phase it belongs to
```

Absent keys degrade gracefully: the gap register renders `—` for owner, the roadmap
places unphased items in Phase 1, and the effort column is omitted if no rule in the run
declares one. No rule file is invalidated by this change.

### 4.4 Three-state discipline carries into every new surface

Per audit DQ8 and `Export-GovernanceReport.ps1`'s existing `NotAssessed` handling: a
domain with a zero denominator is **`Not assessed`**, never a fabricated `0`, in the
maturity table, the radar, the scorecard slide, the composite average (excluded from the
mean, and the exclusion stated), and the gap register. A KRI whose supporting count could
not be collected is emitted with its count as `unknown`, never as `0`.

## 5. Per-renderer target

| Renderer | Today | v2 |
|---|---|---|
| **Word** | 5 sections, 4 columns each | The full §2.1 structure: doc-info block, TOC, exec summary with tiles + narrative, findings dashboard, rubric, KRIs, focus areas, one chapter per domain with why/current-state/per-subscription table, maturity summary, 90-day roadmap, exit criteria, appendices A–C |
| **PDF** | Hand-rolled cover + findings table + gaps + manual | Mirrors Word section-for-section; embeds the architecture diagram (Bug AB#6737, Feature AB#379) |
| **PPTX** | Title / exec / area tables / gaps / manual / next steps | The §2.2 eleven-slide readout: stat tiles, domain scorecard with bands, KRI two-column, heatmap, deep-dive, gaps by owner, roadmap timeline |
| **Excel** | Findings sheets + pivot dashboard | The §2.3 workbook: Cover with scope/legend/contents index, one tab per gap class with full ARM ids and a Verdict column, plus the existing findings sheets retained |
| **Power BI** | 4 flat CSVs on `AreaKey` | Star schema extended with `fact_evidence` (resource grain), `dim_subscription`, `dim_domain`, `dim_severity`, `dim_roadmap_phase` |
| **HTML / React / ECharts / Governance** | Unchanged shape | Re-pointed at `report-model.json`; the governance radar keeps its current design |

## 6. Task breakdown

Created beneath User Story AB#6443. Ordering is dependency-driven — T1 gates everything.

| # | Work item | Task | Depends on |
|---|---|---|---|
| T1 | AB#6852 | `Build-ScoutReportModel.ps1` + `report-model.json` schema + fixture + golden | — |
| T2 | AB#6853 | Rule schema: `targetState` / `owner` / `effort` / `phase`; populate `caf.govern.*` | — |
| T3 | AB#6854 | `manifests/report-narrative.yaml` + narrative binding, evidence-bound only | T1, T2 |
| T4 | AB#6855 | Evidence projection to resource grain + triage verdict classifier | T1 |
| T5 | AB#6856 | Word renderer v2 | T1–T4 |
| T6 | AB#6857 | Excel workbook v2 (cover / legend / contents / per-class tabs / verdict) | T1, T4 |
| T7 | AB#6858 | PPTX executive readout v2 | T1–T3 |
| T8 | AB#6859 | PDF renderer v2 + diagram embed | T1–T3, AB#6737 |
| T9 | AB#6860 | Power BI star schema v2 | T1, T4 |
| T10 | AB#6861 | Register `GovernanceReport` in the `All` reporter list | — |

## 7. Defects found during this research

Recorded here so they are not lost, and raised as bugs beneath Feature AB#6449:

1. **`GovernanceReport` is unreachable from `-OutputFormat All`.** *(Bug AB#6863)*
   `Invoke-ScoutAssessmentCore.ps1:263` lists ten reporters and omits it. The renderer
   ships, is tested, and no production caller can invoke it via the `All` path.
2. **Word / PDF / PPTX discard `Evidence`, `EvidenceCount` and `Remediation`.** *(Bug AB#6862)* The
   fields are populated on every finding and read by none of the three document
   renderers. This is the single largest cause of the "reports say nothing" complaint.
3. **`Invoke-Rule.ps1:124` caps evidence at 25 rows with no truncation flag.** *(Bug AB#6864)* A finding
   with 198 matches renders identically to one with 26. The count survives in
   `EvidenceCount`, but any renderer walking `Evidence` silently under-reports, and
   nothing tells it that it is.

## 8. Non-goals

- No new Azure API calls. Every number in the report comes from data already collected.
- No tenant writes. Scout stays read-only.
- No second entry point. This is the same `Export-Report` dispatch, same wizard, same
  `-OutputFormat`.
- No external service dependency at render time. Offline generation is preserved,
  including the OpenXML NuGet cache pattern and the vendored ECharts build.
