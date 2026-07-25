# Current task

<!-- What is being worked on right now. Keep it short; update as work moves. -->

**Nothing in flight.** v2.4.0 shipped 2026-07-25, is live on the PowerShell Gallery, and the docs
site is deployed. The board conforms: `./scripts/Test-BoardConformance.ps1` reports 0 ADO failures
and 0 GitHub reconcile failures across 196 items (178 Closed / 16 New / 2 Removed).

Three things remain open, in the order they can be picked up:

1. **AB#5543** — collapse the duplicate inventory and assessment collection passes. This is the only
   open item that needs **no owner decision**; it is engineering work with acceptance criteria on the
   item. It now sits under its own Epic **AB#5545**, because its former parent AB#5023 is Closed and a
   closed epic cannot own open work.
2. **Epic AB#5093** — the served web application (11 children). Never approved for build; needs a
   go/no-go. Web and PowerShell are ONE product at parity, never rival feature sets.
3. **AB#323** under Epic AB#5410 — multi-tenant Lighthouse cross-tenant scanning. Its run-isolation
   prerequisite shipped in v2.3.0, so it is unblocked.

The one verification task that needs no decision: **live-tenant validation of `-IncludeDevOps`**. The
Azure DevOps collectors are covered by 36 mocked tests only and have never run against a real
organization. See `docs/validation-matrix.md`.

<!--
  Optional advisory model hint the next tool should honour if available.
  Never overrides an explicit per-session model flag the operator has set.
  Example: suggested-model: opus
-->
<!-- suggested-model:  -->
