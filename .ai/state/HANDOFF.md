# Handoff

## Session 2026-08-01 — Epic AB#6450 "Enhance the reporting engine with new formats"

Branch **`feat/ab6450-reporting-v2`** off `main` (`10d2dd6`). **Eight commits, not merged,
not pushed.** Working tree clean at `180e8c0`.

### The finding that framed the epic

The reports were not a styling problem. `Invoke-Rule.ps1` already attached `EvidenceCount`,
up to 25 matched Azure objects, and a `Remediation` string to every finding — and **Word,
PDF and PPTX read none of the three**. Every table in all three documents was
`Id / Severity / Status / Title`. The data needed to write "60 of 198 storage accounts had
public network access enabled" was present at render time and discarded.

Research input: the seven reference deliverables attached to User Story AB#6443 (a 5,600-line
Word governance report, an 11-slide executive deck, a 13-tab gap workbook) were downloaded
and read in full before any code. Structure recorded in `docs/design/reporting-engine-v2.md`.

### Architecture

One `Build-ScoutReportModel` derives the report **once** — engagement metadata, inventory
tiles, 1–10 domain maturity with rubric, key risk indicators, prioritised focus areas, a
consolidated gap register, evidence projected to resource grain with a triage verdict, and a
three-phase roadmap — into a versioned `report-model.json`. Renderers became presentation
only. Called from `Invoke-ScoutAssessmentCore.ps1` before the reporter loop and passed via
`Export-Report -Model`. **`$Model` is optional in every renderer** — each falls back to its
pre-v2 sections rather than failing, because the renderer test harnesses dot-source one file
at a time.

### Shipped

| Commit | Items | Summary |
|---|---|---|
| `c2cdb10` | 6450, 6853, 6863, 6864 | Design doc + engine contract. Evidence truncation made explicit (`EvidenceTruncated`/`EvidenceCap`); four optional rule keys (`targetState`/`owner`/`effort`/`phase`); `GovernanceReport` was missing from the `All` list **and both ValidateSets**, so a shipped, tested renderer was unreachable by any route. |
| `027cb42` | 6852, 6855, 6856 | `Build-ScoutReportModel` + Word v2 (15 sections, names affected resources). |
| `d7b30dd` | 6853 | All 18 `caf.govern.*` rules annotated. |
| `1d228c3` | 6858 | PPTX executive readout — 7 new slides. |
| `bc0ed97` | 6860 | Power BI `fact_evidence` at resource grain + 5 dimensions. |
| `a12642d` | 6857 | Excel workbook — Cover, verdict legend, contents index, per-gap tabs. |
| `3783a7e` | 6854 | **Narrative engine.** |
| `180e8c0` | 6858 | Lint fix. |

### The narrative engine is the notable result

The owner challenged mid-session whether this was a genuinely new process or the old
approach repackaged. On prose specifically the challenge was right, and the answer must not
be relitigated:

**A per-rule template cannot write the sentences that matter.** Decompose the reference
report's prose and every sentence carrying weight is **comparative or aggregate** — "the
four-point gap", "the highest of the seven", "hygiene, not architecture", "60 of 198". None
of those facts lives on a single rule; they are properties of the run as a whole.

So `Build-ScoutNarrative.ps1` is a **fact-derivation layer**, not a sentence library.
`Get-ScoutNarrativeFact` derives strongest/weakest domain and the spread, which domains carry
the severe findings versus which are clean, the concentration ratio of the top three gaps,
distinct subscriptions touched, largest blast radius. **A sentence whose supporting fact
cannot be derived is not emitted** — not hedged, not placeholdered.

Grammar is load-bearing, not cosmetic: "1 domain(s) are excluded" tells a reader a machine
wrote it and they discount the analysis with it. There is a test asserting zero `(s)` in any
output.

### Verification

405 tests passing, 0 failing — 162 across the six new v2 test files, 243 across the
pre-existing report and assessment files. `Build-ScoutNarrative.ps1` and
`Build-ScoutReportModel.ps1` both lint at **0 findings** under the repo's own
`PSScriptAnalyzerSettings.psd1`. **No live Azure run has been done against this branch.**

### Board

Closed: AB#6852, 6853, 6854, 6855, 6856, 6857, 6858, 6860, 6861. Resolved: AB#6863, 6864.
Still Active: **AB#6862** (Word and PPTX now render evidence and remediation; the PDF
renderer does not — comment added, deliberately left open).

### Still open

| Item | Why |
|---|---|
| **Figures — no work item yet** | The reference report has 9 (risk heatmap, MG hierarchy, maturity radar, inventory charts). The generated Word document has zero images. Not started. Create the item before building. |
| AB#6859 — PDF v2 | The only renderer still on v1, and the only one still discarding evidence. Should follow AB#6737 so the architecture diagram can embed. |
| AB#6737 | drawio → JPEG rasterisation; blocks the PDF diagram. |
| AB#379 | html2canvas PNG capture in PDF. |
| **Rule depth** | Scout has **18** Cloud Governance rules; the reference covers 101 subscriptions across 7 domains with per-subscription tables. A perfect renderer over 18 rules yields a good 12-page document, not a 40-page one. This is the real ceiling and it is rule-authoring work, not renderer work. Stated plainly to the owner. |

### Gotchas found this session

- **A single-row table collapses through PowerShell's output stream.**
  `$rows = foreach (...) { , @(cells) }` yields the row's own cells as the top-level
  collection when there is exactly ONE row, so every one-row table rendered as empty cells —
  invisible, because `Export-Word`'s catch falls back to HTML rather than reporting.
  Normalised in `Add-ScoutDocxGridTable`.
- **`return @()` from an accessor enumerates to nothing**, so a collected-but-empty array came
  back `$null` and rendered as "not collected". The unary comma fixes emptiness but
  double-wraps a non-empty array for `@()` callers, and **`Write-Output -NoEnumerate` returns
  a `List[object]` wrapper on PS7** (that broke 54 tests at once — every scalar came out as a
  collection). Resolution: presence and value are **separate questions** —
  `Test-ScoutModelPath` walks the property bag; `Get-ScoutModelProp` returns values plainly.
- **`$Rule.manual` throws under StrictMode** when a Hashtable rule omits the key. `severity`,
  `remediation` and `manual` now read through `Get-ScoutRuleKey`.
- **Pester evaluates a `Describe`'s `-Skip:` during DISCOVERY**, before any `BeforeAll` body
  runs. A flag set in `BeforeAll` is `$null` when `-Skip:` is read, so the whole file skips
  silently while reporting success. Probe at file scope.
