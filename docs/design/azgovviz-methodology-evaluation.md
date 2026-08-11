# AzGovViz methodology evaluation (AB#6448)

**Story AB#6448, Feature AB#6458, Epic AB#6454.** Justifies the Cloud Governance report's
structure (`Export-GovernanceReport.ps1`, AB#6459) against what AzGovViz — the tool the Epic's
own description names as the source of this reporting gap — actually does. **Out of scope:
executing AzGovViz itself, and modifying any Azure resource. Scout is read-only**, and this
evaluation is a documentation exercise, not a code integration against the real tool.

Grounded in AzGovViz's published capabilities (verified 2026-08-01):
[Azure/Azure-Governance-Visualizer](https://github.com/Azure/Azure-Governance-Visualizer) /
[JulianHayward/Azure-MG-Sub-Governance-Reporting](https://github.com/JulianHayward/Azure-MG-Sub-Governance-Reporting)
(the canonical, actively-maintained repo; several other GitHub results for "AzGovViz" are
forks of the same project).

## What AzGovViz is

A PowerShell script that walks a Management Group hierarchy top-down via the ARM, Storage, and
Microsoft Graph APIs, capturing Azure Policy, RBAC, and related governance data, and rendering
it into a single-page HTML report plus CSV/Markdown/JSON exports. It is exclusively read-only.

## What AzGovViz does that Scout does not

| Capability | AzGovViz | Scout today | Verdict |
|---|---|---|---|
| **Management-group hierarchy tree visualization** with per-scope subscription/assignment/role counts | Yes — a rendered `HierarchyMap` | No — `governance.managementGroups` is collected but never rendered as a tree; only flat counts | **Worth adopting eventually, out of scope for this Feature.** AB#6459's AC calls for a radar chart and heatmap specifically, not a hierarchy visualization; adding a third, unrelated chart type here would scope-creep the Feature. Flagged for a future story if a hierarchy view is wanted. |
| **Microsoft Entra service-principal inventory with secret/certificate expiry tracking**, group-membership resolution, user-type classification | Yes | No — Scout has no Entra/Graph collector for this at all | **Confirmed real gap, rejected for THIS Feature.** This independently corroborates `docs/frameworks/cloud-governance-question-set.md`'s `CGOV-SC-03` finding (identity governance monitoring is unobservable from Scout's current data) — the same conclusion reached two different ways. Closing it needs a new Microsoft Graph collector, which is collection work, not reporting work; out of scope here, worth a future collector story. |
| **CAF naming-convention alignment checks** | Yes | No | **Rejected for this Feature** — a naming-convention linter is a distinct rule-authoring exercise unrelated to the governance maturity report; not blocking anything AB#6459 asks for. |
| **Orphaned policy/role definition detection** (`DefinitionInsights`) | Yes | Partial — Scout reads assignments, not orphaned *definitions* | **Rejected for this Feature**, same reasoning as naming checks — a distinct rule, not a reporting-structure decision. |
| **Markdown/Azure DevOps Wiki output with Mermaid diagrams** | Yes | No | **Rejected.** Scout's live renderer contract is React plus JSON data outputs. Use the React page's Markdown export rather than adding another standalone renderer. |

## What Scout already does that AzGovViz explicitly does not

| Capability | Scout | AzGovViz | Why it matters here |
|---|---|---|---|
| **Scoring / rating** | Yes — `Get-Score` produces weighted Pass/Partial/Fail percentages per area and framework; this Feature adds a 1-10 domain maturity number on top | **Explicitly does not.** AzGovViz's own documentation states it "focuses on enumeration, enrichment, and connection of governance artifacts rather than scoring posture." | This is Scout's actual differentiator and the entire reason AB#6459 exists — AzGovViz was never trying to solve "how mature is this tenant's governance," only "what governance artifacts exist and how do they connect." The Cloud Governance report is not a reimplementation of AzGovViz; it is the scoring layer AzGovViz deliberately does not provide. |
| **Multi-framework rule engine** (CAF design areas, WAF pillars, regulatory-compliance initiatives, SMART migration readiness, cross-resource correlation, and now CAF Govern) | Yes — one engine, many rule files | No — governance-artifact enumeration only, no framework mapping | Confirms the report's shape (reuse `Get-Score`'s existing Areas/Frameworks output, add a relabeling function) is the right fit for how Scout already works, rather than a bespoke governance-only pipeline. |
| **Fully offline / strict-CSP HTML output** | Yes — `Export-EChartsDashboard.ps1`'s vendored Apache ECharts v5.6.0 build, acquired once at authoring time, never fetched at render time | **No.** AzGovViz's HTML single-page report loads CSS from a CDN at render/view time. | **This is the decisive rejection.** AB#6459's AC explicitly requires "a strict CSP and offline operation... no CDN, no external fonts." AzGovViz's own report artifact would fail that requirement outright. `Export-GovernanceReport.ps1` deliberately reuses the same vendored-library mechanism `Export-EChartsDashboard.ps1` already built and tested (`$Script:ScoutEChartsLibJs`), rather than following AzGovViz's CDN-based approach or introducing a second charting dependency. |
| **Multiple renderer targets from one scored object** (historical design) | Yes | No — fixed HTML/CSV/Markdown/JSON | The legacy targets are now held. New document exports must derive from the React report model rather than a parallel one-off pipeline. |

## Decision

**Adopted:** the report-as-scoring-layer positioning (Scout's differentiator over AzGovViz),
the offline/vendored-library rendering approach already proven in `Export-EChartsDashboard.ps1`,
and reuse of the existing multi-framework rule engine rather than a bespoke governance-only code
path.

**Deliberately rejected for this Feature** (real capabilities, wrong scope): hierarchy tree
visualization, Entra service-principal/secret-expiry tracking, CAF naming-convention checks,
orphaned-definition detection, and Markdown/Wiki output. Each is a legitimate feature; none of
them is what AB#6459's AC (1-10 domain score, radar, heatmap, offline HTML/PDF) asks for, and
bundling them in would have turned a reporting story into a collector-and-rule-authoring
program. The Entra/secret-expiry gap in particular is tracked as a known, real limitation via
`CGOV-SC-03` in `src/assess/rules/caf.govern.sc.yaml` — visible in every governance report as
"Not assessed," not silently absent.
