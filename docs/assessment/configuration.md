---
description: Saving and loading an assessment configuration, the three live outputs, and held legacy renderers.
---

# Configuration and report tiers

How to pin an assessment's configuration so a run is reproducible, and what each output
tier produces.

## Assessment config load/save

`Import-ScoutConfig` / `Export-ScoutConfig` (AB#373–375) let you save and
reload the effective assessment config — an alternative benchmark,
rule-selection glob patterns, and per-rule threshold overrides — as a single
JSON file, mirroring exactly what the engine already consumes (no new schema
invented):

```powershell
# Load a config (falls back to the built-in ALZ reference benchmark if the
# file is absent, missing, or unparsable -- never throws)
$config = Import-ScoutConfig -ConfigPath ./my-config.json

# Round-trip: save the effective config back out
Export-ScoutConfig -Config $config -Path ./my-config.json -Force
```

Every key (`benchmark`, `rulePatterns`, `ruleOverrides`) is optional and
independently overridable. A missing/invalid `-ConfigPath` degrades to
"run with defaults" with a `Write-Warning` rather than aborting the
assessment.

## Report tiers

::: danger The React/HTML report is the one supported deliverable
**Word, PDF, Excel, PowerPoint, Power BI, standalone HTML, ECharts dashboard, Markdown-file,
AsciiDoc, and governance-report renderers are ON HOLD (AB#6922) and are not emitted.** This is a
global contract; inventory-only runs do not bypass the hold.

Azure Scout produces **one** report: a self-contained HTML/React document — a multi-page
application in a single file — that hosts the inventory and every assessment behind one shell, and
exports to Markdown, JSON, CSV, PDF (print) and a standalone HTML copy **from the page itself**.
The standalone document renderers still exist and are still tested, but they are being rebuilt to
generate **from** that report rather than alongside it, so a document and the page it came from
can never disagree.

Asking for a held format by name still binds — the run warns, skips it, and renders the React
report so you always get a deliverable. `-OutputFormat All` renders the React report plus the
machine-readable data exports. `Json` / `JsonEvidence` are data, not documents, and are never
held.

The report's structure is normative — see
[the React report section contract](../reference/react-report-section-contract.md).
:::

### Available now

| Tier | Output | Notes |
|------|--------|-------|
| **React** | `report-react.html` | **The deliverable.** Self-contained (CSS/JS inline, findings embedded as a JSON blob, no external/CDN requests) and a multi-page application in one file: **Overview**, **Inventory & audit** (a blade per Azure portal category), **Assessments** (landing tiles into a full conformance register per assessment), **Diagrams**, **Data & drift**, and a **Remediation plan**. Navigation is built from what actually ran. An **Executive / Consultant / Data** view-depth toggle, a light/dark theme toggle, and exports to Markdown, JSON, findings CSV, evidence CSV, Print/PDF and a standalone HTML copy. Every register lists every check — passes, fails and manual questions — with a gap block for each fail carrying its evidence, why it matters, a numbered fix and a Microsoft Learn link, and every score shown alongside its own arithmetic and what was excluded from the denominator. See [Cross-run drift](./analysis-features.md#cross-run-drift) and [the section contract](../reference/react-report-section-contract.md). |
| JSON | `AzureScout_Report_<timestamp>.json` for inventory-only; `findings.json` when assessments run | Machine-readable results. Inventory-only preserves the established AzureScout inventory JSON schema; assessment output carries assessment metadata, scores, and findings. Data, not a document; never held. |
| JSON evidence | `evidence.json` (`Export-JsonEvidence`) | Resources-only canonical Collect export (**AB#396**), including collection provenance and already-collected Entra rows — no scores, rules, or findings. |

### Coming soon

These renderers exist and are still tested, but are **not emitted** while the reporting engine is
rebuilt. They will return generated from the React report's model, so a document and the page it
came from can no longer disagree.

| Tier | Output | Status |
|------|--------|--------|
| PDF | `assessment_report.pdf` | **Coming soon.** Export to PDF from the React report today. |
| Word | `assessment_report.docx` | **Coming soon.** No Word artifact is emitted today; a native `.docx` is tracked as **AB#6923**. |
| Excel | `assessment_evidence.xlsx` | **Coming soon.** Export findings to CSV from the React report today. |
| PowerPoint | `assessment_deck.pptx` | **Coming soon.** |
| Power BI | `powerbi/*.csv` + `.pbit` | **Coming soon.** |
| HTML | `report.html` | **Coming soon** — superseded by the React report. |
| ECharts dashboard | `assessment_dashboard.html` | **Coming soon.** |
| Governance report | `governance_report.html` | **Coming soon.** |
| Markdown file | `*.md` | **Coming soon.** Export Markdown from the React report today. |
| AsciiDoc | `*.adoc` | **Coming soon.** |

