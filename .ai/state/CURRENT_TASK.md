# Current task

<!-- What is being worked on right now. Keep it short; update as work moves. -->

**Nothing in flight.** v2.5.1 shipped 2026-07-25, live on the PowerShell Gallery, docs deployed,
board conformant (`./scripts/Test-BoardConformance.ps1` → 0 ADO failures, 0 GitHub reconcile
failures across 198 items — 182 Closed / 14 New / 2 Removed).

**Scout now completes a full run against a live tenant.** It did not before this session. Verified
against This Is My Demo: 227 Azure resources, 994 Excel rows, 40 Power BI CSVs, plus JSON, Markdown
and the draw.io diagram. `-IncludeDevOps` is **live-verified** for the first time — 166 resources
across 74 projects — closing the long-standing "mock-tested only" gap.

All 14 open items are the two areas the owner excluded:

1. **Epic AB#5093** — the served web application (11 children). Needs a go/no-go.
2. **Epic AB#5410 / AB#323** — multi-tenant Lighthouse cross-tenant scanning.

## Known open questions (not work items yet)

- **Compute collection is non-deterministic.** Across otherwise-identical live runs,
  `ReportCache/Compute.json` came back as 5,158 bytes and then 470 bytes. Unexplained — possibly
  Resource Graph throttling. Worth a work item if it reproduces.
- **`Build-AZSCExcelComObject` needs Excel installed** (`0x80040154 Class not registered`). Emits a
  non-fatal error and the run completes; this is the existing reason `lite` defaults to true.
- **The manifest `ReleaseNotes` string is capacity-bound.** PSGallery rejects anything over 10,600
  characters. It now holds only the three most recent releases plus a CHANGELOG link; do not go
  back to appending every release.

<!--
  Optional advisory model hint the next tool should honour if available.
  Never overrides an explicit per-session model flag the operator has set.
  Example: suggested-model: opus
-->
<!-- suggested-model:  -->
