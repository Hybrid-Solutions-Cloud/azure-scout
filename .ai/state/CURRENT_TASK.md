# Current Task: AB#7279 — release AzureScout 3.12.2 live-run correctness

- Status: **IMPLEMENTED — COMMIT, EXACT-HEAD FULL SUITE, AND PUBLICATION NEXT**
- Branch: `agent/ab7279-live-run-correctness-3.12.2`
- Base: AzureScout 3.12.1 (`c1e1a91457df06339a9c92c40ae6a7a125359800`)
- Target: publish the exact tested 3.12.2 package to PowerShell Gallery.

## Scope

- Classify known Entra licence/scope/unconsumed availability before HTTP calls in both permission
  preflight and extraction; preserve unexpected failures as visible unavailable datasets.
- Remove the held Azure Lighthouse collector/query from every released runtime contract.
- Retry oversized Security Center Resource Graph results with smaller projected pages.
- Treat expected lifecycle-policy/Advisor 404 and unregistered Defender pricing as normal absence.
- Filter null resources before orphaned role-assignment resolution.
- Propagate upstream availability through `collector-rowcounts.json` and `collection-health.json`.
- Retain raw inventory, report cache, diagram cache, and all evidence after successful completion.
- Clarify total guided-command time versus scan/log execution time.
- Run one selected-scope authentication/preflight in guided combined mode; make management-group,
  provider, Graph, and overall-readiness output reflect what the selected identity can collect.

## Verification completed

- Actual completed run log reconciled: every warning class maps to a product fix; no unaccounted
  ERROR records.
- Focused live-error/runtime/retention gate: 268 passed, 0 failed/skipped/not-run/containers.
- Graph permission/preflight gate: 103 passed, 0 failed/skipped/not-run/containers.
- Version/release/docs/catalog gate: 45 passed, 0 failed/skipped/not-run/containers.
- Manifest validates as 3.12.2; generated catalogs match all 278 released collectors.
- Final guided/preflight regression batch: 219 passed, zero failures/skips/not-run/containers.
- Release/docs contracts: 32 passed; docs build, parser, PSScriptAnalyzer Error, StrictMode,
  manifest, and diff gates passed.
- First frozen full-suite attempt: shards 0 and 1 passed 794/794 and 739/739; shard 2 found two
  stale contracts, now corrected. ContextIdentity passes 5/5 and golden coverage is exactly
  278 definitions/278 records with no missing/extra entries. Superseding full suite is required.

## Release gates remaining

1. Secret scan and commit the frozen candidate with `AB#7279`.
2. Run the complete zero-failure/zero-skip Pester gate
   against that exact clean commit.
3. Push with the GitHub App token, require green PR CI/docs, merge, and require green main CI/docs.
4. Tag `v3.12.2`, build an allow-listed package from the tag, validate/import/secret-scan it.
5. Publish the exact staged package, download from PowerShell Gallery, compare every file hash,
   install 3.12.2, and run a fresh-process smoke.
