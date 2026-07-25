# Current task

<!-- What is being worked on right now. Keep it short; update as work moves. -->

**Nothing in flight. Everything except the web application and multi-tenant is delivered.**

v2.5.0 shipped 2026-07-25, live on the PowerShell Gallery, docs site deployed, board conformant
(`./scripts/Test-BoardConformance.ps1` → 0 ADO failures, 0 GitHub reconcile failures).

Board: **196 items — 180 Closed / 14 New / 2 Removed.** All 14 open items are the two areas the
owner deliberately excluded:

1. **Epic AB#5093** — the served web application (11 children). Needs a go/no-go. Web and
   PowerShell are ONE product at parity, never rival feature sets.
2. **Epic AB#5410 / AB#323** — multi-tenant Lighthouse cross-tenant scanning.

There is **no open engineering work outside those two areas.**

## The one thing still unverified

**Live-tenant validation of `-IncludeDevOps`.** The Azure DevOps collectors are covered by 36
mocked tests only and have never run against a real organization. This needs a real Azure DevOps
org to point at — it is a verification gap, not unbuilt code. See `docs/validation-matrix.md`.

<!--
  Optional advisory model hint the next tool should honour if available.
  Never overrides an explicit per-session model flag the operator has set.
  Example: suggested-model: opus
-->
<!-- suggested-model:  -->
