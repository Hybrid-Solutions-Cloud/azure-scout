# Current Task: AB#7279 — validate AzureScout 3.12.3 in its new HCS home

- Status: **REPOSITORY CUTOVER COMPLETE; THREE FOCUSED FAILURES AND FULL TEST GATE REMAIN**
- Canonical repo: `https://github.com/Hybrid-Solutions-Cloud/azure-scout`
- Canonical local path: `D:/git/hybrid-solutions-cloud/azure-scout`
- Branch: `agent/ab7279-run-errors-3.12.3`
- Base: migration-only `main` at `11783cd54c766dc4707e2003418e076d61afa8ee`
- Target: release AzureScout 3.12.3 only after one exact-commit complete test pass.

## Repository cutover state

- The source repository remains at `thisismydemo/azure-scout` as the historical issue, PR,
  workflow, and original release-timestamp record. Its landing page links to the new homes.
- All source branches and tags were mirrored. The recovered local product branch was added and
  then rebuilt cleanly on the new canonical `main` from its seven product/test commits.
- Target Pages, documentation deployment, releases, and branch protection are configured.
- The HCS platform registry change merged as ADO PR 17; its docs and MCP deployment pipelines must
  finish before the live MCP can resolve the new registry identity.

## Product scope already implemented

- ARM-child, Entra, management-group, Defender, and Azure DevOps failures report honest source
  availability rather than silently becoming empty successful evidence.
- Disabled subscriptions are retained in inventory but excluded from downstream query scope.
- Dynamically loaded optional helpers and their dependencies survive for the collection phase and
  are removed afterward.
- Operational collection emits bounded progress, durable heartbeats, and terminal log status.
- A read-only HCS live acceptance reconciled all 278 released collectors against independent
  queries. That live reconciliation does not replace the automated gate.

## Known focused failures recovered after the laptop crash

`tests/Collect.RawInventory.Tests.ps1` exposed three failures on the pre-cutover product tip:

1. Enabled subscription scope was received as null rather than `enabled-sub`.
2. The ARM-child append test could not resolve property `id`.
3. The ARM-child health merge test hit the same missing-`id` shape.

The failure ownership must be diagnosed before changing product code or fixtures.

## Required gates

1. Reproduce and isolate all three raw-inventory failures in the canonical clone.
2. Fix the demonstrated product or fixture defect and run the complete focused suite with zero
   failures, skips, not-run tests, or failed containers.
3. Run every Pester file against one exact clean commit with the same zero-tolerance criteria.
4. Require green target-repository CI and documentation checks.
5. Only then open/complete the product PR, tag 3.12.3, stage the allow-listed package, validate and
   secret-scan it, publish to PowerShell Gallery, download it back, and compare package hashes.

## PowerShell Gallery transition

Published 3.12.2 metadata still points to the legacy project/source URLs. The legacy project URL
now provides the move notice. The 3.12.3 manifest carries the canonical HCS documentation,
license, and icon URLs; do not publish it until the complete product gate passes.
