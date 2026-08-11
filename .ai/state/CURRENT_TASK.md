# Current Task: AB#7279 — release AzureScout 3.12.2 live-run correctness

- Status: **IMPLEMENTED, REVIEWED, AND FOCUSED-GREEN — EXACT-HEAD FULL SUITE AND PUBLICATION NEXT**
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

- Post-review correctness repairs close all three PR findings plus the follow-on source-ownership
  audit: delegated Graph scope checks apply only to catalog-declared delegated-only endpoints;
  disabled Entra catalog entries no longer poison collection health; raw ARG failures carry exact
  source/collector ownership; assessments fail closed only for selected affected evidence; skipped,
  empty, failed, and healthy Advisor evidence remain distinct; managed identities have one ARG
  owner; an explicit scored-assessment category can broaden but never narrow required evidence;
  and saved `-FromCollect` artifacts must prove required category and source-health coverage before
  they can be scored.
- Latest settled affected gates: assessment/entry point 90/90; release/runtime 118/118;
  managed-identity/source-health 26/26; all with zero failures or skips. Parser, StrictMode,
  PSScriptAnalyzer Error, release/docs contracts, docs build, secret scan, manifest/import, package
  inventory, and diff checks pass. Independent runtime and release audits report no demonstrated
  production blocker.
- Saved-collect provenance/report compatibility gate: 98/98 passed with zero failures/skips.
- Final settled affected gate: 427/427 passed across 20 suites with zero failures, skips,
  not-run tests, or failed containers.

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
- Second frozen attempt: shard 1 passed 739/739; shard 0 found a parallel-process race in the
  machine-wide update-check marker. The throttle path is now injectable for tests, production
  retains its default, and ModuleUpdate passes 11/11. A new exact-HEAD full suite is required.

## Release gates remaining

1. Commit the frozen candidate, including the new Entra collection-health regression, with `AB#7279`.
2. Run the complete zero-failure/zero-skip Pester gate
   against that exact clean commit.
3. Push with the GitHub App token, require green PR CI/docs, merge, and require green main CI/docs.
4. Tag `v3.12.2`, build an allow-listed package from the tag, validate/import/secret-scan it.
5. Publish the exact staged package, download from PowerShell Gallery, compare every file hash,
   install 3.12.2, and run a fresh-process smoke.
