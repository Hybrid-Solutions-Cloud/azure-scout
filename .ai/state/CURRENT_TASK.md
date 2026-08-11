# Current Task: AB#7279 — release AzureScout 3.12.0 scan optimizations

- Status: **FOCUSED GATES GREEN — FULL FROZEN SUITE NEXT**
- Started 2026-08-10 from `main` at `5286217`.
- Target: publish the exact validated 3.11.0 package to PowerShell Gallery, then begin a separate
  measured optimization change set. AzureScout 3.11.0 has been published, byte-for-byte verified,
  installed, and released on GitHub. The optimization change set is now versioned as 3.12.0.

## 3.12.0 scope

- Manifest-derived category extraction plans filter Resource Graph server-side and skip unrelated
  phases; All, unknown, and assessment-backed paths preserve the full dependency set.
- Combined runs reuse inventory security/policy sweeps and fall back only for missing datasets.
- Recovery vault, protected-item, and storage-context calls are cached at subscription/vault scope.
- ARM REST list calls follow nextLink and retry only transient 408/429/5xx responses; fixed sleeps
  on every successful call are removed.
- Focused integration is green at 149/149 with zero failed/skipped/not-run/failed containers;
  parser, manifest, PSSA Error, StrictMode, diff, release, and version-sync gates are green.

## 3.11.0 scope

- One live output contract everywhere: `React`, `Json`, `JsonEvidence`; `All` means all three.
- Held legacy names bind for compatibility, warn, skip, and fall back to React when necessary.
- Inventory-only React/evidence reuse the completed collection offline with no assessment rules or
  Azure/Graph fallback; inventory Json retains its established schema.
- Detailed DEBUG/VERBOSE phase, collector, row-count, timing, rule, and renderer data is written to
  `scout-run.log` by default without increasing console noise.
- Standalone assessment automation uploads selected live artifacts; pipeline summaries report
  requested and effective formats separately.

## Release gates

1. Full Pester suite on the frozen candidate: zero failed, skipped, not-run, or failed containers.
2. Parser, collector-definition, StrictMode, manifest/version, documentation, and secret checks.
3. Commit with `AB#7279`, push through GitHub, and require green CI on the exact commit.
4. Tag `v3.11.0`, build an allow-listed package from that tag, and validate/import the staged module.
5. Publish that exact package, download it from PowerShell Gallery, and compare every file hash.

Local release-candidate validation is complete: three deterministic Pester shards passed
3,454/3,454 with zero failed, skipped, not-run, or failed containers. The provisional allow-listed
package also parses, imports, and passes its secret scan. GitHub CI on the exact commit is the next
release authority.

## Optimization work after publication

Start with measurable call-count reductions: reuse the security/policy sweep in combined runs,
cache recovery-vault/protected-item and operational enrichment lookups per subscription, thread
category/dependency plans into extraction, add pagination and consistent Retry-After handling, then
consider bounded concurrency only for calls that do not mutate shared Az context.
