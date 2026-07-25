# Current task

<!-- What is being worked on right now. Keep it short; update as work moves. -->

**Nothing in flight.** v2.3.0 shipped 2026-07-25 and closed the whole open backlog other than the
two areas held back by the owner.

Next action requires an owner decision, not engineering:

1. **Epic AB#5093** — the served web application (11 children). Never approved for build; needs a
   go/no-go. Web and PowerShell are ONE product at parity, never rival feature sets.
2. **AB#323** — multi-tenant Lighthouse cross-tenant scanning. Its run-isolation prerequisite
   shipped in v2.3.0, so it is now unblocked.

The one engineering task that needs no decision: **live-tenant validation of `-IncludeDevOps`**. The
Azure DevOps collectors are covered by 36 mocked tests only and have never run against a real
organization. See `docs/validation-matrix.md`.

<!--
  Optional advisory model hint the next tool should honour if available.
  Never overrides an explicit per-session model flag the operator has set.
  Example: suggested-model: opus
-->
<!-- suggested-model:  -->
