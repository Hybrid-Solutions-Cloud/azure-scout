# Current task

<!-- What is being worked on right now. Keep it short; update as work moves. -->

## IN FLIGHT — Epic AB#5638: rebuild the inventory engine

**Approved by the owner on 2026-07-25.** The board tree is created and conformant
(AB#5638 Epic → 5 Features → 15 User Stories → 15 Tasks, AB#5639–5673).

The engine under `Modules/` is a fork of `microsoft/ARI` inherited at v1.0.0. It was written
without StrictMode; an AST sweep found **~800 module-scope property reads that are only valid
without it**. Because every fault is data-dependent, it aborts on normal Azure responses in a
different place on every tenant — v2.5.3 alone fixed **six** crashes, each only reachable once the
previous cleared. v2.5.3 contains the damage by disabling StrictMode at **17** entry points. That
is a stopgap, not a foundation.

Five phases, each shipping as a working release, ending in the deletion of `Modules/`:

| Feature | What |
|---|---|
| **AB#5639** | One collector — `src/collect/Invoke-Collect.ps1` becomes the only code that queries Azure |
| **AB#5649** | Deterministic pipeline — delete the `Start-Job` / `[PowerShell]::Create()` machinery |
| **AB#5656** | The 176 collectors become declarative definitions |
| **AB#5662** | One reporting layer — `src/report/*` replaces `Modules/Private/Reporting/*` |
| **AB#5667** | StrictMode everywhere + recorded live-payload fixtures |

**Start with AB#5649 (the pipeline)** — it eliminates the entire crash class on its own.

## v2.5.3 — SHIPPED 2026-07-25

Commit `97e6031`, tag `v2.5.3`, GitHub release, **PSGallery 2.5.3 published 21:47**, and installed
into the operator's module path. Board: 240 items, **0 conformance failures**, 137 GitHub issues all
linked. Pester **1766 / 0 / 3**.

Live run verified end to end: **6:43**, 105 resources, 425 Excel rows, 37 Power BI files / 989 rows,
Excel + JSON + Markdown + AsciiDoc + draw.io all written.

**Every run now writes `scout-run.log` + `scout-console.log` into its run folder** — phases, counts,
warnings, and on failure the full error record with script, line and stack trace. It found two of
the six defects on its first run.

---

**Previously: nothing in flight. Nothing known-broken and unfixed.**

v2.5.2 shipped 2026-07-25, live on the PowerShell Gallery, docs deployed, board conformant
(`./scripts/Test-BoardConformance.ps1` → 0 ADO failures, 0 GitHub reconcile failures across 199
items — 183 Closed / 14 New / 2 Removed).

**Scout completes a full live run, and now does so deterministically.** Three consecutive runs
against This Is My Demo produced byte-identical results: 227 Azure resources, 994 Excel rows, 40
Power BI files / 1013 rows, 166 Azure DevOps resources, 0 empty-category warnings, 0 raw COM
errors. `-IncludeDevOps` is live-verified.

All 14 open items are the two areas the owner excluded:

1. **Epic AB#5093** — the served web application (11 children). Needs a go/no-go.
2. **Epic AB#5410 / AB#323** — multi-tenant Lighthouse cross-tenant scanning.

## Resolved this session — do not re-open as unknowns

- **Compute collection non-determinism** → root-caused and fixed as **AB#5629**. It was a job-wait
  race, not Resource Graph throttling: `Start-Job` is asynchronous, a `NotStarted` job was never
  waited on, then harvested and destroyed empty.
- **Excel COM `0x80040154`** → fixed under AB#5629. A missing `Excel.Application` ProgID is now
  detected up front and explained; it no longer surfaces a raw error.
- **An empty `ReportCache` folder after a successful run is NOT data loss.** A completed run cleans
  it up. Earlier runs only left cache files behind because they crashed before cleanup.

## Standing constraint

The manifest `ReleaseNotes` string may not exceed **10,600 characters** or PSGallery rejects the
push. It carries only the three most recent releases plus a CHANGELOG link — do not go back to
appending every release.

<!--
  Optional advisory model hint the next tool should honour if available.
  Never overrides an explicit per-session model flag the operator has set.
  Example: suggested-model: opus
-->
<!-- suggested-model:  -->
