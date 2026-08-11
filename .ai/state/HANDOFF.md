# Handoff

## Session 2026-08-11 — 3.12.2 post-review source-honesty closure

PR #263's three review findings and the subsequent adversarial source-ownership audit are resolved
in the working tree. Permission preflight now applies exact delegated-scope absence only to catalog
entries explicitly marked `RequireDelegatedScope`; normal User/Group/Application/Policy endpoints
are probed. Disabled `Collect=false` Entra entries remain visible in raw query outcomes but are not
promoted to failed collection health.

Raw inventory failures now carry exact dataset and collector ownership, including filtered network
queries, parent-derived ARM child collectors, Backup/AVD/Patch/Advisor dependencies, and manifests
that actually consume retirement data. Exact collector ownership is authoritative downstream.
Assessment collection preserves that provenance and fails closed for unavailable selected evidence
without blocking unrelated categories. A complete raw-pass failure cannot become a clean empty
assessment. Combined mode catches only this marked assessment-unavailable condition, skips scoring,
and continues producing the honest inventory deliverable.

Advisor evidence now distinguishes successful empty, unavailable, and intentionally skipped data;
every and only rule querying `$.advisor` gates on `advisorAvailable`. `-SkipAdvisory` performs no
Advisor call and yields NotAssessed rather than a false Pass. User-assigned managed identities now
have one authoritative Resource Graph source in selective, full, pre-collected, and fallback paths.
Scored assessment `-Category` values are unioned with manifest-required categories so a user filter
cannot omit evidence and create false Passes. Inventory-only/collect-only filtering behavior remains
available for non-scoring use. Reassessment from a saved `collect.json` now validates its recorded
categories and applicable failed source health before scoring; incomplete or legacy artifacts without
provable coverage throw the same typed `AssessmentSourceUnavailable` condition instead of treating
missing evidence as a Pass. The canonical saved-collect fixture now records full provenance.

Settled focused evidence: 90/90 assessment/entry-point tests, 118/118 affected release/runtime tests,
and 26/26 managed-identity/source-health tests, all with zero failures/skips. Independent runtime and
release audits found no remaining demonstrated production blocker. Parser, StrictMode,
PSScriptAnalyzer Error, release/docs contracts, docs build, diff check, secret scan, manifest/import,
and allow-listed package inventory checks pass. The final settled 20-suite affected gate passed
427/427 with zero failures/skips/not-run/container failures. The candidate commit includes the new
`tests/Extraction.EntraCollectionHealth.Tests.ps1`; the remaining release sequence is the complete
zero-skip Pester suite on a clean superseding commit, then push/merge/tag/build/publish/verify 3.12.2.

The first exact-commit full-suite attempt found one stale contract in
`Collect.SinglePassInversion.Tests.ps1`: it still expected the typed query pack to recover a total
raw-pass outage, even though that fallback cannot recreate raw-only child/API evidence and was
intentionally removed. The test now requires the typed `AssessmentSourceUnavailable` failure.
The combined routing test also shadows `Get-AzContext` so it cannot read or print the developer's
ambient cached identity. Their focused rerun passed 51/51 with zero skips; a superseding clean
commit and all three exact-commit shards are required.

## Session 2026-08-11 — 3.12.2 guided-run preflight correction

A second live customer run exposed duplicate and contradictory preflight UX after the initial
3.12.2 correctness commit. The wizard no longer runs an ARM-only audit before it knows whether the
operator selected Entra; after confirmation, `Invoke-AzureScout` now performs one login and one
authoritative audit for the selected scope. The login banner no longer performs its own management
group probe. The audit now proves management-group visibility through actual enumeration, treats a
provider check as a one-subscription sample without tenant-wide registration recommendations,
excludes disabled/unconsumed Graph catalog entries, and emits exactly one mutually exclusive
READY/PARTIAL verdict. A combined-run regression is fully mocked and cannot touch the developer's
active Az context.

Post-fix verification: the focused runtime/preflight batch passed 219/219 with zero failed, skipped,
not-run, or failed-container results; release/docs contracts passed 32/32; VitePress built; all
changed PowerShell parsed; PSScriptAnalyzer Error severity is zero; StrictMode guard, manifest
3.12.2 validation, and diff check passed. The first frozen full-suite pass found two stale release
contracts: ContextIdentity still expected the deliberately removed wizard audit, and the golden
directory retained the deliberately removed Lighthouse record. The wizard contract now requires no
early audit (5/5 focused pass), and golden coverage is again exactly 278 definitions/278 records
with no missing or extra names. A superseding commit and exact-HEAD full-suite/release work remain.

The second frozen attempt found one nondeterministic ModuleUpdate test: a normal AzureScout import
in another parallel shard could recreate the production-wide temp throttle marker between this
test's cleanup and assertion. `Test-AZSCModuleUpdate` now accepts an optional `ThrottlePath` while
production keeps the same default; the suite uses a GUID-isolated marker directory. ModuleUpdate
passes 11/11 with no skips. A new superseding commit and complete exact-HEAD rerun are required.

## Session 2026-08-11 — 3.12.2 live-run correctness implemented

The completed customer run at `C:\AzureScout\2026-08-11_133426_189_d6fc73cf` was reconciled
against the code. Every warning class has an implemented regression: known P2/delegated-scope and
unconsumed Entra endpoints are classified before HTTP calls in both preflight and extraction;
Azure Lighthouse is removed from the released manifest/query/plan contract; Security Center ARG
responses use a narrow projection and shrink their page after payload-limit failures; expected
storage lifecycle/Advisor 404s and unregistered Defender pricing remain quiet; null resources are
filtered before orphaned-role enrichment; and upstream unavailable datasets flow into collector
availability plus `collection-health.json` instead of appearing as clean empty data.

The operator additionally required every discovery artifact to survive completion. The final
`ReportCache` purge was removed. `raw-inventory.json`, `collector-rowcounts.json`,
`collection-health.json`, `ReportCache`, and `DiagramCache` now remain in the run folder until an
operator explicitly invokes age-based cleanup. A mocked public-entry completion test creates raw
and processed cache files and requires both to remain.

Version metadata is synchronized to 3.12.2 in the manifest, changelog, release ledger, docs
changelog, and roadmap. Generated catalogs match 278 released manifests after Lighthouse removal.
Verification so far: 268/268 focused runtime/live-error/retention tests, 103/103 permission/Entra
tests, and 45/45 release/docs/catalog tests passed with zero skips, not-run cases, or failed
containers. `Test-ModuleManifest` reports 3.12.2. Remaining work: static/docs/secret gates, commit the
frozen candidate, complete full Pester on the exact clean commit, push/PR/CI/merge, tag/package,
publish to PowerShell Gallery, and verify the downloaded/installed artifact byte-for-byte.

## Session 2026-08-11 — completed 3.12.1 live-run error audit

Read-only audit of `C:\AzureScout\2026-08-11_133426_189_d6fc73cf` is complete. The guided
Both/All run completed in 11m43s and produced inventory JSON, React, findings and evidence, but it
was not complete: `scout-run.log` contains 25 warnings and `scout-console.log` captured 16 raw
terminating error records. Confirmed product defects are: unfinished Lighthouse collection is
incorrectly live and queries the disallowed `managedserviceresources` ARG table; the Security Center
ARG query requests full assessment payloads and exceeded ARG's 16 MiB response limit (25,512,374
bytes), leaving the legacy Security findings input empty; permission-audit availability decisions
do not reach Entra extraction, so known-unavailable Risky User/Verified ID calls and two unconsumed
Identity Provider/Security Defaults calls are still executed and logged as failures; one null element
in the 1,506-resource array causes `Resolve-ScoutOrphanedRoleAssignment` parameter binding to reject
the whole array, leaving role-assignment display-name/orphan enrichment unresolved; expected storage
lifecycle-policy 404s, an unregistered Microsoft.Security provider and absent Advisor score leak as
raw warnings/terminating errors; upstream unavailable datasets are later reported as ordinary Empty
collectors and the summary incorrectly says `Collectors failed: 0`.

The repair plan is: (1) remove Lighthouse from every live collection/category/docs contract until
implemented; (2) project only Security Center fields consumed downstream and use a payload-safe page
size, while propagating query availability; (3) build one Entra collection plan shared by preflight
and extraction, skipping unlicensed, delegated-scope-unavailable and unconsumed queries without an
HTTP call and recording structured NotAssessed outcomes; (4) filter null resource elements before
enrichment/return and make the resolver explicitly tolerate them; (5) classify expected 404/provider
absence as Empty/Unavailable rather than warnings and prevent caught API errors leaking into the
console transcript; (6) carry upstream availability into collector row counts, report health and the
final run summary; (7) clarify total interactive time versus scan execution time. Regression gates
must exercise the exact guided-menu path, assert zero calls for known-unavailable Entra endpoints,
handle a 2,000+ row Security fixture, enrich an array containing null, prove All never queries
Lighthouse, and require zero raw `TerminatingError` transcript entries for expected absence. After
focused tests, run the complete zero-failure/zero-skip Pester gate and a live read-only menu smoke
before a patch release.

## Session 2026-08-11 — v3.12.1 one-sign-in Graph authentication hotfix

AzureScout 3.12.1 is released. PR #262 merged to main as
`7660d9cbd6b20f0c125b13832b1554f1bec48d8c`; annotated tag `v3.12.1` points to that release,
the GitHub Release is <https://github.com/thisismydemo/azure-scout/releases/tag/v3.12.1>, and
the PowerShell Gallery package is <https://www.powershellgallery.com/packages/AzureScout/3.12.1>.

The live 3.12.0 failure was a split identity: ARM used the account and tenant selected in the Az
PowerShell context, while Graph always used the ambient Azure CLI account. The target tenant rejected
that unrelated CLI identity with AADSTS500213, and Entra extraction repeated the same token failure for
all 20 catalog entries. `Get-AZSCGraphToken` now uses only `Get-AzAccessToken` for the requested tenant,
caches by endpoint/tenant/selected account, and never starts or recommends a second Azure CLI sign-in.
Entra extraction authenticates once before its query loop, emits one common failure, makes zero dataset
requests after that failure, and derives the displayed resource-type count from the live catalog.

Verification on the release candidate: auth/Graph/Entra/permission suites 155/155; unified entry and
permission integration 105/105; release/version contracts 17/17; docs contracts 13/13; parser,
PSScriptAnalyzer Error severity, StrictMode, manifest, diff, and secret gates passed. Both PR workflows
passed on `74daace`; main CI and docs passed on `7660d9c`. The final 726-file artifact contains 668
parser-clean PowerShell files and passed a read-only live `/v1.0/users` request in the selected tenant
without a second sign-in. A fresh public `Save-Module` download matched all 726 staged files with zero
missing, extra, or SHA-256-mismatched files and imported 22 commands as version 3.12.1.

Permission wording confirmed for customer use: the only Entra directory-role assignment for the
supported interactive user read scan is `Global Reader`; Azure RBAC `Reader` remains separate. Optional
cost visibility, Entra licence tiers, Graph OAuth scopes, and Azure DevOps access are prerequisites or
service-specific access boundaries, not additional Entra role assignments. Two Verified ID datasets may
remain Not assessed under a user token because no directory role can add their missing OAuth scopes.

## Session 2026-08-10 — v3.12.0 performance release published under AB#7279

AzureScout 3.12.0 is released and installed. PR #261 merged as
`8f1d2fcd92ad70dbd4dc962eabe815651f28ea55`; annotated tag `v3.12.0` peels to that exact merge commit.
The GitHub Release is <https://github.com/thisismydemo/azure-scout/releases/tag/v3.12.0>, and the
PowerShell Gallery package is <https://www.powershellgallery.com/packages/AzureScout/3.12.0>.

The release implements four measured call-count reductions. A manifest-derived category plan reaches
extraction and applies server-side Resource Graph type filters while preserving full collection for
All, unknown, and assessment-backed paths. Combined runs reuse the inventory security/policy sweep,
treating successful-empty and unavailable datasets as authoritative and falling back only for genuinely
missing inputs. Operational enrichment lists Recovery Services vaults once per subscription, protected
items once per vault, and enters storage context once per subscription while preserving output order and
failure envelopes. The ARM REST sweep follows `nextLink`, retries only transient 408/429/5xx responses
with Retry-After/jitter, and removes roughly 1.9 seconds of fixed successful-request sleep per subscription.

The first PR CI run on `edee2130` caught a real compatibility defect: the pagination aggregator wrapped
the single `policyStates/summarize` response object in an extra array. Correction commit `65b7b2b` now
preserves exact wire shape for single-page responses and aggregates only multi-page GET lists. The frozen
corrected candidate passed the full deterministic suite in three shards: 750/750, 865/865, and 1,859/1,859
— **3,474 passed, 0 failed, 0 skipped, 0 not run, 0 failed containers**. Focused compatibility tests,
parser checks, PSScriptAnalyzer Error-severity analysis, StrictMode guard, collector validation, docs build,
manifest/version synchronization, diff check, and package secret scan also passed.

Exact-candidate PR CI and docs passed on `65b7b2b`. After merge, main CI run 31454366929 passed in 16m54s
and docs run 31454366937 passed in 40s on the release commit. The allow-listed tag-built package contains
726 files / 8,582,341 bytes; all 668 PowerShell files parse, the manifest reports 3.12.0, and a fresh process
imports 22 commands. A clean public `Save-Module` download matched all 726 staged files byte-for-byte with
zero missing, extra, or SHA-256-mismatched files. CurrentUser installation path is
`C:\Users\KristopherTurner\Documents\PowerShell\Modules\AzureScout\3.12.0`; a fresh process imports the
installed module as version 3.12.0 with 22 exports.

## Session 2026-08-10 — 3.11.0 release candidate frozen under AB#7279

The operator confirmed the product-wide live output contract from the documentation: only `React`,
`Json`, and `JsonEvidence` are live; legacy document/worksheet renderers have been held for many
releases. The 3.11.0 candidate now applies that contract to inventory, assessment, combined, wizard,
unattended pipeline, GitHub Action, and GitHub workflow surfaces. `All` expands to the three live
formats; explicit held names warn/skip and held-only requests fall back to React. Inventory Json
preserves the existing exporter schema; inventory React/evidence reuse the completed collection in a
strict offline mode with no assessment rules or live Azure/Graph fallback. Combined runs render once.
Standalone assessment automation uploads selected live artifacts before returning; pipeline summaries
retain requested formats but report effective formats as the deliverables.

Detailed logging is also implemented: DEBUG/VERBOSE extraction subphase start/end/status/rows/timing,
raw dump and processing timing, collector results, assessment ingest, per-rule evidence/timing, and
renderer timing are written to `scout-run.log` by default without changing console preferences.
Report catch blocks can pass exceptions to the logger and record their type/available stack detail
without the error handler itself throwing.

Version metadata is synchronized to 3.11.0 in AzureScout.psd1, CHANGELOG.md, RELEASES.md,
docs/project/changelog.md, and docs/project/roadmap.md, tied to Bug AB#7279. Focused verification on
the frozen candidate includes: runtime output suites 38/38, 41/41, 216/216, 25/25, 65/65, 1/1;
pipeline 23/23; logging/pipeline 78/78; release/docs 32/32; documentation build passed; collector
definition and StrictMode guards passed; 24 changed PowerShell files parsed with zero errors; diff
check clean except core.autocrlf warnings. No Azure collection calls were made.

The complete frozen-candidate suite then passed in three deterministic shards: 772/772, 1,980/1,980,
and 702/702 — **3,454 passed, 0 failed, 0 skipped, 0 not run, 0 failed containers**. The provisional
allow-listed package contains 726 files / 8,551,907 bytes; all 668 PowerShell files parse, the staged
manifest reports 3.11.0, a clean process imports 22 exported functions, and the package secret scan
has zero hits. PSGallery 3.10.2 resolves and 3.11.0 is absent/available.

Next: commit/push through GitHub, wait for exact-commit CI, tag v3.11.0, stage the allow-listed package
from that tag, publish to PSGallery, and verify a clean
Gallery download byte-for-byte. Only after 3.11.0 is published should performance optimization edits
begin. Confirmed optimization targets: repeated security/policy sweeps, multiplicative operational
enrichment calls, missing category-to-extraction planning, serial/unpaged ARM/API sweeps, and fragmented
retry behavior.

## Session 2026-08-10 — v3.10.2 tenant-first wizard correction

Immediate use of published 3.10.1 exposed three wizard defects. Access-token Az contexts put GUIDs
in `Account.Id`/`Tenant.Id`, so the wizard displayed identifiers instead of the user and tenant
name. Rejecting that context did not reliably enforce the intended fresh-login -> accessible-tenant
picker flow, and the default ARM inventory ran `Test-AZSCPermissions -Scope All`, producing a
blocking cross-tenant Graph token error before the operator opted into Entra collection.

AzureScout 3.10.2 is released and installed:

- `Resolve-AZSCContextIdentity` resolves same-tenant user and tenant display names, using Az tenant
  metadata first and Azure CLI only as an access-token fallback.
- Y keeps the confirmed tenant and does not enumerate tenants or authenticate again.
- N passes `-ForceLogin`, suppresses Az LoginExperienceV2's subscription selector at process scope,
  and displays a deduplicated list of accessible tenants. Azure CLI subscription cache is used only
  as a fallback source of tenant identities and is grouped by tenant; subscriptions are never shown
  as the scan-scope selector.
- Tenant-wide runs continue to enumerate all subscriptions internally. Only explicit
  `-SubscriptionID` narrows the scan.
- Wizard permission preflight is `ArmOnly`; the operator must explicitly opt into Entra collection
  before `Scope All` can request a Graph token.
- Manifest, changelog, release ledger, docs changelog, and roadmap are synchronized to 3.10.2.

Release evidence:

- Release commit/tag: `2a15a3f7e885ad3775e984ae2acaee63781aa316` / `v3.10.2`.
- GitHub CI run 290 and documentation deployment both passed on the exact release commit.
- The seven-file release/permission/wizard shard passed 153/153 with zero failures or skips;
  parser, PSSA, StrictMode, docs, manifest, release contract, and secret checks passed.
- The tag was exported into an allow-listed 726-file package. It differs from the 3.10.1 package
  footprint only by `src/Get-AZSCContextIdentity.ps1`.
- PSGallery indexes AzureScout 3.10.2. A clean `Save-Module` download matched all 726 staged files
  byte-for-byte with zero missing, extra, or SHA256-mismatched files.
- CurrentUser installation path is
  `C:\Users\KristopherTurner\Documents\PowerShell\Modules\AzureScout\3.10.2`.
- A fresh-process installed-package probe imported version 3.10.2 with 22 exports, resolved the
  account and tenant display names, and enumerated six accessible tenants.
- GitHub issue #259 and AB#7278 were closed with the release evidence.

## Session 2026-08-10 — v3.10.1 published; GitHub CI line-ending follow-up

AzureScout 3.10.1 is released and usable. The original Both + React/JsonEvidence startup failure
was fixed, audited, committed, pushed, tagged, packaged, smoke-tested against the approved existing
Az context, published to PowerShell Gallery, downloaded back from the Gallery, and installed for the
current user.

### Release outcome

- Release commit/tag: `5991acc2b00fb7a4ce1910bfd1d432193bcc95b3` / `v3.10.1` on GitHub `main`.
- GitHub issue: `#259`; Azure Boards bug/reference: `AB#7278`.
- PSGallery resolves `AzureScout` version `3.10.1`; a clean `Save-Module` download matched all 725
  files in the exact staged/tagged package with zero SHA256 mismatches.
- Installed path: `C:\Users\KristopherTurner\Documents\PowerShell\Modules\AzureScout\3.10.1`.
- Fresh-process import reports 3.10.1 and exports 22 functions.
- Real read-only combined smoke used the exact affected route and completed with 504 resources,
  React HTML, three assessment/evidence JSON files, and two inventory-evidence files. Output:
  `D:\tmp\azure-scout-live-smoke-3.10.1-20260810-131052`.
- Exact release package staging path:
  `D:\tmp\psgallery-stage-3.10.1-5991acc\AzureScout`.
- Local release-candidate verification before publication: 3,422 passed, 0 failed, 0 skipped,
  0 not run, 0 failed containers; parser, StrictMode, release/version, docs, package inventory,
  secret scan, and clean-download checks passed.

### GitHub Actions follow-up

The first GitHub CI run for the release commit failed only in the test harness: Windows checkout
converted `tests/fixtures/collector-equivalence/DevOps.json` from LF to CRLF, while
`Get-ScoutFixtureSha256` hashed raw bytes. This caused 72 identical fixture-identity failures.
The module/package and real smoke remained successful.

Current uncommitted follow-up:

- `scripts/CollectorGolden.Common.ps1` canonicalises fixture line endings to LF while preserving
  every other byte (including a UTF-8 BOM), emits canonical hashes for new records, and accepts the
  historical CRLF digest for existing records.
- `tests/CollectorGolden.Common.Tests.ps1` proves LF/CRLF equivalence, BOM identity, legacy CRLF
  compatibility, and the exact committed DevOps hash after simulated CRLF checkout.
- `tests/ReactReport.DiagramOverlap.Tests.ps1` registers optional local banked-corpus cases only when
  their inputs exist. GitHub no longer reports two unavailable local corpus cases as skipped;
  deterministic report/diagram tests remain mandatory.

Verification for the follow-up: focused 7/7 passed with zero skips; all 279 golden records across
18 fixtures accept the canonical/legacy identity; three files parse cleanly; `git diff --check` and
diff secret scan passed. PSScriptAnalyzer reports only the file's two pre-existing warnings
(`Write-Host` and the non-ASCII file BOM rule). The full 1,121-test golden execution produced no
failure output but exceeded the local 10-minute command ceiling before returning a result; GitHub
must supply the authoritative full-suite result on the follow-up commit.

Next action: commit the CI-only follow-up as `fix(ci): canonicalize golden fixture hashing AB#7278`,
push `main`, and wait for GitHub CI. Do not move `v3.10.1` or republish the Gallery package: the
follow-up changes only scripts/tests excluded from the 725-file published package.

## Session 2026-08-10 — repository-wide audit after Both + React/JsonEvidence startup failure

The operator explicitly requested a multi-agent audit after confirming the failing wizard selection
was **Both** (Inventory + Assessment), with React and JsonEvidence. Runtime, assessment/reporting,
and release/quality surfaces were audited in parallel, then the complete Pester suite was split into
three deterministic shards and rerun against the settled working tree.

### State and scope

- Branch: `main`; release target `v3.10.1`; GitHub issue `#259`; Azure Boards Bug `AB#7278`.
  All audit, version, and release-document changes are ready for the authorized commit/push/publish
  sequence.
- The installed PSGallery `AzureScout` 3.10.0 remains unchanged and still contains the original
  startup bug. Import the repository's `AzureScout.psd1` to exercise the fixes locally.
- The supplied tenant identifier was not written into the diff.
- The final automated verification was local/mocked and did not use a real tenant. During the *first* audit
  shard, a missing test mock allowed read-only Defender ARM requests for synthetic subscription IDs;
  Azure rejected them with HTTP 400 and no mutation occurred. All 12 affected suites now shadow the
  non-ARG Defender and External Identities sweeps; their focused 133-test rerun and the final distributed
  suite observed no external Azure activity.

### Confirmed defects fixed

- **Original Both-mode failure:** the inventory-format guard now rejects React/JsonEvidence only when
  no deferred assessment exists. A full mocked Both + React + JsonEvidence invocation completes the
  inventory phase, deferred assessment, reporting, and cleanup.
- **StrictMode/runtime:** initialized non-Excel result/JSON variables; preserved empty arrays in the
  Excel renderer; fixed module-update fallback when no module is already loaded; eliminated remaining
  unset/scalar-array paths found by the suite; required PS7/StrictMode/terminating-error directives are
  now enforced across `src`, `scripts`, the root module, and root scripts.
- **Tenant/context safety:** Entra and External Identities Graph calls receive the requested TenantID;
  subscription switches require a successful matching context before queries; the warning environment
  and login experience are restored in `finally` blocks.
- **Permissions and isolation:** permission checks validate the current caller with a live read instead
  of accepting another principal's Reader role; report/run folders and permission-output filenames are
  collision-safe; diagram jobs are owned, awaited, received, and removed per run.
- **Collection:** Azure DevOps continuation tokens are followed; sovereign Graph endpoints are mapped;
  VM quota calls reject a mismatched selected context; IoT Hub/DPS/Digital Twins rows now project IDs
  required for private-endpoint correlation; cache pruning is scoped and guarded.
- **Assessment correctness:** manifest collection categories now cover automated-rule dependencies;
  governance read failures and unavailable PIM data gate rules to NotAssessed; compliance headlines are
  withheld when control coverage is incomplete; percentage rules correlate distinct resource IDs;
  malformed rules produce complete Error findings instead of terminating the run.
- **Reporting:** React uses canonical area weights/scores and preserves distinct statuses, real evidence
  totals/truncation, framework versions, framework rollups, and mixed-currency uncertainty; CSV exports
  neutralize spreadsheet-formula prefixes.
- **Release/CI:** corrected Azure Pipelines parameters/formats, hardened GitHub CI's Pester result gate,
  split read-only docs PR builds from main deployment, made the bundled action import its own manifest,
  declared required modules in the manifest instead of installing during import, and corrected docs and
  examples to advertise only live formats. Release contract tests were added.

### Verification

- Final distributed Pester coverage: **3,422 passed; 0 failed; 0 skipped; 0 not run; 0 failed
  containers**. The former 79 skips were removed: 77 conditional bookkeeping cases now generate only
  applicable tests, and 2 reflection-dependent default checks now use PowerShell AST assertions.
- The 12 suites that could leak fake subscription IDs to ambient Azure/Graph paths passed **133/133**
  behind file-local inert collector shadows, with no live-call warnings.
- Exact affected-suite reruns included the Both route, permission audit, module update, VM quota,
  governance/compliance, IoT, React/Power BI, deterministic pipeline, DevOps paging, run isolation,
  release contracts, and StrictMode guard.
- Parsed **131 changed PowerShell files** with zero errors; prior YAML validation remained clean.
- `scripts/Test-StrictModeGuard.ps1`: pass (17 documented weakening sites, no new or stale entries,
  and no directive violations).
- PSScriptAnalyzer on the final touched runtime files: 0 findings / 0 errors.
- `git diff --check`: pass. VitePress docs build: pass; it reports only the existing >500 kB chunk
  optimization warning.
- Version synchronization/release contracts: **15/15**; manifest version `3.10.1`; PSGallery version
  slot confirmed available; release-note length 625 characters.

### Known residual release/technical-debt risks

- The release uses the proven v3.10.0 allow-listed package footprint: 725 files from the five root
  module/doc files plus `config`, `manifests`, `src`, and `archived/Modules` mapped to `Modules`.
- GitHub workflow actions are still referenced by mutable major tags (`@v4`) rather than immutable
  commit SHAs. This is a supply-chain hardening item, not a runtime defect fixed in this session.
- The StrictMode allow-list still documents 2 live and 15 dead compatibility weakening sites. The guard
  prevents growth, but removing those sites is separate cleanup.
- No real-tenant smoke test was run. Before release, run Both + React + JsonEvidence against an approved
  test tenant, then validate the generated inventory and assessment artifacts.

### Next operator action

Commit with `AB#7278`, push `main`, wait for GitHub checks, tag `v3.10.1`, build the allow-listed package
from that exact tag, run the read-only combined-run smoke, publish to PSGallery, then verify a clean
Gallery download/import.

## Session 2026-08-10 — fixed v3.10.0 assessment startup routing failure

An operator running the installed PSGallery module 3.10.0 chose the wizard's combined
Inventory + Assessment path with React and JsonEvidence and received the line-660 error
claiming those formats require `-Assessment`. This is a deterministic routing defect, not an
Azure-context or tenant issue.

- `Invoke-AzureScout` correctly enters assessment mode and stores `$assessArgs` in
  `$deferredAssessArgs` for `RunBoth` / `-InventoryAndAssessment`, then continues into the
  inventory phase.
- The inventory guard at `src/Invoke-AzureScout.ps1:657-660` unconditionally rejects React and
  JsonEvidence, even though they are destined for that deferred assessment.
- Reproduced against the installed 3.10.0 module using `-FromCollect` with a nonexistent path,
  which avoids Azure access and still fails at line 660 before the path is read.
- Existing tests prove inventory-only rejection and deferred-assessment wiring independently,
  but none exercises their interaction with an assessment-only output format.
- The operator confirmed they selected **Both**. An earlier assistant message incorrectly stated
  Assessment-only; that interpretation was explicitly corrected. The exact failing path is Both +
  React + JsonEvidence: the assessment is deferred correctly, then the inventory-format guard
  rejects the deferred assessment formats before collection begins.
- The inventory format guard now rejects assessment-only formats only when no deferred assessment
  exists. This also repairs the independently broken combined path.
- Product change: `src/Invoke-AzureScout.ps1`.
- Regression coverage: `tests/Assessment.CollectOnce.Tests.ps1` and
  `tests/UnifiedEntryPoint.Tests.ps1`; the latter drives the real mocked wizard for Both mode and
  executes `-Assessment ... -InventoryAndAssessment -OutputFormat React,JsonEvidence` through two
  mocked login calls, proving it passes the former line-660 guard into the inventory phase.
- Verification: the new collect-once assertion was observed failing before the product patch.
  `Assessment.CollectOnce.Tests.ps1` plus `UnifiedEntryPoint.Tests.ps1` passed 61/61 after the
  final minimal fix, including the exact Both + React + JsonEvidence route. Output formats and
  menu honesty also passed in the earlier focused run (part of 107 passes with 1 pre-existing
  reflection skip). Parser and `git diff --check` passed for all changed PowerShell files.
  PSScriptAnalyzer reported only the file's pre-existing Write-Host/BOM warnings; no changed line
  introduced an analyzer finding. HCS `validate(iac-powershell)` could not execute its commands
  because the validator misidentified its own `$results`/`$config` variables as missing commands.
- Branch: `main` (working tree only; not committed or released). The installed PSGallery 3.10.0
  copy remains unchanged; import the repository manifest to exercise the local fix immediately.

## Session 2026-08-04 (later) — v3.5.1: three defects v3.5.0 believed were fine

All three were found by *using* the product or by auditing claims, not by reading test output.

1. **The wizard offered every format except React.** `Start-AZSCWizard.ps1` chose the
   assessment format list only when assessment was selected *and inventory was not*, so the
   commonest path of all — Inventory **and** Assessment — fell through to the inventory-only
   list, which contains no React. The assessment list it skipped still offered six held
   renderers, defaulting to `Html`. Fixed to offer `React`/`Json`/`JsonEvidence` on any
   assessment run, defaulting to React. `tests/Assessment.MenuHonesty.Tests.ps1` now parses
   `$script:ScoutHeldRenderers` and fails if the menu offers a held format — proved to bite by
   stashing the fix and re-running (3 real failures naming `Html`).
2. **`Compare-Benchmark` crashed on any tenant with MGs but no policy assignments** —
   `policyAssignments.properties.displayName` over an empty array resolves against the array
   object under StrictMode. 1 of 8 corpus tenants (ptlmgmt) produced no report at all.
   Fixed with `ForEach-Object`; regression test in `Assessment.Governance.Tests.ps1`; all 8
   tenants now render.
3. **The diagram-overlap gate inspected zero diagrams.** `tests/diagram-fixture-build.mjs`
   wrote flat keys; the template and real payload use dotted paths. Fixture builder corrected
   (the template is the payload contract's source of truth). Checker now reads 13 nodes / 9
   edges of network topology and 18 / 17 of MG hierarchy, and was proved to fail on a
   manufactured overlap.

**Lesson worth keeping**: a held-renderer decision must be enforced at *every* surface that
names a format — core, parameters, docs **and** the interactive menu; and a green gate is
worth nothing until you have watched it fail.

### Also this session

- Mockup **v7** adds four network diagrams (VNet hub-and-spoke with unpeered VNets flagged,
  hybrid site-to-site, private link & DNS, internet exposure) — the owner's standard is that
  **the mockup is the contract**, and that approved elements are added to, never replaced.
- **The connectivity gap**: the assessment collect carries a peering *count* rather than the
  pairs, and the VPN gateway but not its connections — while the inventory pipeline already
  has 21 networking collectors holding that relationship data. Board: **AB#7050** with tasks
  **AB#7051–7058** (collect peering pairs / VPN connections / ExpressRoute + vWAN / route
  tables; render connectivity, hybrid, edge-and-delivery, private-link).
- Board hygiene: 11 report items reparented off the closed AB#6878 onto AB#6928; AB#6906
  closed (one file per run, not per assessment); AB#6913 and AB#7026 closed; AB#6936 reopened
  after an audit found its "every view" criterion unmet.


## Session 2026-08-04 — v3.5.0 shipped: the v6 multi-page React report

The owner iterated the target-state mockup through v3→v6 (complete conformance register →
multi-page IA → blade inventory on the 18-category taxonomy → Diagrams page → exports/theme),
approved v6 verbatim ("lets code this exactly like this"), and it was implemented, verified,
merged and released the same day.

### Shipped (PR #245, squash-merged to main; tag v3.5.0; PSGallery published; installed locally)

- `src/report/templates/report-react.html.template` — fully rewritten to the v6 page model:
  Overview / Inventory & audit / Assessments / Diagrams / Data & drift / Remediation plan,
  client-side from `window.__SCOUT_DATA__`. Blade inventory (18 documented categories with
  portal labels, zeros listed with absence blades, filter+sort item tables, tenant structure,
  audit callouts, full cost-optimization blade), complete register per assessment (gap block
  per fail, manual agenda, What's-next), Diagrams page (kept the collision-free diagram
  kernel for MG/VNet; estate + gaps bars ported; full-screen zoom/pan overlay), view-depth +
  theme toggles, Markdown/JSON/CSV exports.
- `src/report/renderers/Export-React.ps1` — R-04 conformance fix only: the `Get-Score` call
  for per-assessment slices replaced with an inline (Framework|Area) status tally over the
  already-scored findings. Payload unchanged (it already carried everything v6 needs).
- Docs: every report page states all other assessment formats are ON HOLD (the inventory
  pipeline's Markdown/AsciiDoc/Excel exports are NOT held and say so);
  `docs/reference/react-report-section-contract.md` rewritten to the v6 IA; version-sync
  ledgers (RELEASES.md, docs/project/roadmap.md, docs/project/changelog.md) carry 3.5.0.
- Also on the branch and now in main: the JToken evidence fix (3%→82% named evidence),
  learnUrl+weight on findings, AHB collector fields + FINOPS-O04 (AB#7035), report identity
  parameters.

### Verification

React 55/55; Conformance + PerAssessmentContract + DiagramOverlap green (123/123 after the
R-04 fix); CI green on the merge commit (2,932 passed); full local suite green apart from the
documented installed-module collision noise; browser walk of the rendered template against
the real tppoc corpus payload (all pages, 55/55 gap blocks). Docs build green.

### The mockup lineage (for future design iterations)

`D:\tmp\azure-scout-react-mockups\_build\build-register.mjs` generates the approved mockup
from `_facts/tppoc-real-payload.json`; artifact 52190986-84da-4a86-89a7-b8735e700cfa.
Category-mapping decisions (owner-confirmed): FinOps → cost blade; Advisor → General;
PIM/RBAC → Identity; DevOps → DevOps; cost cleanup is not a category.

### Open / next

- Board updated for v3.5.0: AB#6936/6937 Resolved, AB#7035 Closed, AB#6938 Active (its ALZ
  benchmark AC is unmet because no BENCH-* rules were ever authored — that plus per-rule
  learnUrl/whyItMatters YAML is the remaining 6938 scope), AB#6928 Active (8/13 children
  open). Tags corrected to v3.5.0.
- **Owner decisions pending**: (1) AB#7035/7036/7037 are Tasks parented directly to Feature
  AB#6928 — the board standard wants a Story/Bug parent; reparent or accept. (2) The board
  tag vocabulary (`scripts/Test-BoardConformance.ps1:72-76`) contains no version tags, so
  the `v3.5.0` tag on four stories is flagged as non-vocabulary — add `vX.Y.Z` tags to the
  vocabulary or drop version tags and let release comments carry the fact.
- AB#6938 per-assessment depth continues: per-rule `learnUrl` + `whyItMatters` in rule YAML
  (the client-side keyword map is the interim); AB#7036 cost projections; AB#7037 AzL AHB.
- diagram-fixture-build.mjs prints "(skip) no data in fixture" against current corpus
  collect.json shapes — non-blocking, worth wiring real fixtures.
- A fresh tenant collect will light up the AHB audit callout (corpus predates licenseType).
