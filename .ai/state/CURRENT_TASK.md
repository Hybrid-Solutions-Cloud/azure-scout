# Current task

<!-- What is being worked on right now. Keep it short; update as work moves. -->

**Nothing in flight. Nothing known-broken and unfixed.**

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
