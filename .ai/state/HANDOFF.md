# Handoff

## Session 2026-08-13 — AB#405 live progress implementation and v3.12.5 release

The static v3.12.4 progress line has been replaced on branch
`agent/ab405-live-progress-3.12.5` with a real Spectre auto-refreshing progress host. Its spinner
and elapsed-time column are owned by Spectre's refresh loop, so they continue moving while the
PowerShell execution thread is blocked inside a long Azure call. The Azure operation has an
execute-once boundary: startup failures fall back before work begins, while any failure after work
begins is propagated without replaying collection.

The operator rejected black phase text on dark blue. The product and updated mockup now use bright
cyan/white foreground labels on the terminal's normal background, never a colored background; the
phase/state words remain meaningful without color. `-NoProgress` was added, and CI, redirected,
non-interactive, and missing-module paths retain native/log-friendly behavior. Progress sites in
extraction and collector processing route through the shared helper with native fallbacks.

Version and documentation are staged for v3.12.5, "The compass keeps moving." Focused Pester 5.7.1
passed 57/57. A direct smoke against PwshSpectreConsole 2.6.3 successfully rendered a three-second
blocking operation, accepted a task update, completed, and returned the operation result. Full
validation, protected PR/merge, CI/docs, tag, and PowerShell Gallery publication remain in progress.

## Session 2026-08-13 — AB#405 progress-TUI audit and concept mockup

The operator reported that the inventory elapsed timer froze after the ARG sweep and remembered a
planned rich PowerShell progress solution. The reference is confirmed as `PwshSpectreConsole`.
Azure Boards feature AB#405, "Integrate PwshSpectreConsole for rich terminal TUI progress display
in Azure Scout," is Closed, but its stated acceptance criteria required live multi-bar progress,
long-operation spinners, CI fallback, and `-NoProgress`. The released implementation only detects
the optional module and calls `Write-SpectreHost` for a static styled line; native extraction timing
is updated only at subphase boundaries. The observed frozen timer is therefore consistent with the
implementation and shows that the original feature was closed without its core live-refresh UX.

An in-conversation design mockup was created at
`D:/tmp/azure-scout-spectre-mockup.html`. It demonstrates the intended experience: an independently
ticking overall and phase timer, animated current-operation spinner, overall and per-phase status,
resource/dataset counts, recent activity, and a heartbeat indicator. No product code was changed.

## Session 2026-08-13 — AzureScout 3.12.4 merged and published

The operator approved the protected merge and publication. Product PR #2 merged as
`0ad57f073e89ded38e9014fdd7b69b4926670d69`; release PR #3 merged as
`ec3750d423f452e3a27c4d0548d8052b5868d139`. Both approvals were recorded against the exact PR
heads before squash merge. The release commit's post-merge CI run `31742722594` and documentation
build/deploy run `31742722585` completed successfully. HCS ephemeral runners serviced the jobs,
and the Default runner group's public-repository allowance was restored to `false` afterward.

Annotated tag `v3.12.4` and the GitHub Release point to the exact release merge commit. The final
PowerShell Gallery module was constructed from `git archive v3.12.4` using the established
allow-list: five root files, `config`, `manifests`, `src`, and `archived/Modules` mapped to
`Modules`. It contains 732 files (8,736,748 bytes); all 674 PowerShell files parse, the manifest
reports 3.12.4, a fresh process imports 22 exports, and gitleaks is clean.

PowerShell Gallery accepted AzureScout 3.12.4. A fresh public `Save-Module` download contained the
same 732 package files with zero missing, extra, or SHA-256-mismatched paths. Both staged and
downloaded artifacts have deterministic tree hash
`f678d4244e67a3225af26e8cb82288a8317e7e855e70fc5c9c37e9f6219984f3`. The downloaded package
fresh-imported as 3.12.4 with 22 exports. The Gallery page, GitHub Release, and Labs documentation
all returned HTTP 200.

No 3.12.4 release work remains. These state updates are intentionally local post-release notes;
the immutable release tag and published package do not include them.

## Session 2026-08-12 — HCS runner onboarding and target CI green

PR `Hybrid-Solutions-Cloud/azure-scout#1` is open from
`agent/ab7279-run-errors-3.12.3` to `main`. Current tested tip is
`0df4e63614e146dc8fdea17c11cab97613fdfc9d`.

The HCS Governance `ci-runners` standard was applied to every workflow: CI, docs, inventory,
and stale automation now target the HCS self-hosted Linux fleet. Live Azure inspection showed
the Hybrid-Solutions-Cloud ACA runner job is deployed, but KEDA did not wake it for this public
repository because the org Default runner group has `allows_public_repositories=false`.
For these trusted same-repository PR checks, the setting was temporarily enabled only until the
ephemeral runners claimed their jobs, then restored to `false`. The Windows VMSS described by the
standard is not deployed (`deployWindowsRunner=false`), so the cross-platform AzureScout CI job
runs on HCS Linux.

Clean Linux runners exposed missing CI prerequisites and genuine portability assumptions. CI now
installs all `AzureScout.psd1` RequiredModules, sets `TEMP`/`TMP`, provisions .NET 8 for OpenXML,
and supplies an inert `az` command surface solely so Pester can prove the product never invokes
Azure CLI. Product/test portability fixes anchor fallback collector definitions to the module,
sanitize report names with the portable Windows-invalid-character superset, and use embedded JPEG
bytes instead of System.Drawing in PDF tests.

Final target results at `0df4e636`:

- HCS CI run 31630406334: success; Pester 3,591/3,591, 0 failed, 0 skipped, 0 not run; standalone
  StrictMode guard success; PSScriptAnalyzer 0 errors (551 non-blocking warnings).
- HCS documentation run 31630406332: success.
- Focused portability regression set: 105/105 locally, zero failed containers.
- The authoritative Windows/local full gate remains 3,593/3,593 at product commit `2c5be8f5`.

Do not merge or release until the protected PR review requirement is satisfied. PowerShell Gallery
3.12.3 is not published.

## Session 2026-08-12 — post-cutover complete collector gate

The canonical product branch is `agent/ab7279-run-errors-3.12.3`. The three recovered
`Collect.RawInventory.Tests.ps1` failures were test-harness isolation defects: default non-ARG
phases had expanded, but the fixture did not provide inert doubles for those helpers. The focused
file now passes 56/56 under the CI-pinned Pester 5.7.1 without ambient Azure calls.

The first complete 134-file run at `02ddd381` produced 3,462 passes and six failures. Five were
stale or StrictMode-sensitive test contracts; one was a real shaping defect: synthetic `AZSC/*`
transport envelopes were included in `opsPosture.diagnosticCoverage` even though the reference KQL
runs only against Azure's `resources` table. `ConvertFrom-ScoutInventory` now excludes those
synthetic rows. A subsequent run passed every assertion but exposed a file-discovery container
failure in `Collector.VanishingParent.Tests.ps1`, where optional manifest preamble properties were
read unsafely under ambient StrictMode. That discovery path is now key-guarded.

Authoritative local result: exact product commit
`2c5be8f54fc8f363871ea6017f6a2e9dcf9a298e`, 134 files, 3,593 passed, zero failed, zero skipped,
zero not run, zero failed containers, clean before and after. Result JSON:
`D:/tmp/azsc-full-final-2c5be8f54fc8f363871ea6017f6a2e9dcf9a298e-result.json`.

The legacy public site was also simplified at source commit `67469c8a`: it has no nav/sidebar/footer
or content below the three move cards, and its documentation action points to
`https://labs.hybridsolutions.cloud/azure-scout/`. The old documentation deployment succeeded and
the live legacy URL returned HTTP 200 with the new Labs and GitHub links and no old docs URL.

Next: push this branch with the target-org GitHub App, require target CI/docs green, then open and
complete the protected PR before any 3.12.3 release or PowerShell Gallery publication.

## Session 2026-08-12 — AzureScout copy cutover to Hybrid-Solutions-Cloud

The user replaced the blocked GitHub ownership-transfer approach with a copy-and-cutover. The
source repository was not deleted or transferred. Its `main` now contains legacy landing commit
`406cbabf1f81bfaa961532194f1773ec999e958a`; source documentation deployment run `31607587273`
succeeded, and `https://thisismydemo.cloud/azure-scout/` returns HTTP 200 with links to both new
canonical locations.

The public target repository is `Hybrid-Solutions-Cloud/azure-scout`, GitHub ID `1332126664`.
The independent canonical clone is `D:/git/hybrid-solutions-cloud/azure-scout`; its `origin` points
directly to the target. Target `main` is the validated migration-only commit
`11783cd54c766dc4707e2003418e076d61afa8ee`. It does not contain the seven untested 3.12.3 product
commits. Manifest 3.12.2 validated, 285 changed PowerShell files parsed, VitePress built, and the
docs/version gate passed 8/8 with no skips.

Git parity is verified: the source has 45 branches and the target has 46, with the only additional
branch being the recovered `agent/ab7279-run-errors-3.12.3`. Every shared branch object matches
except intentionally divergent `main` and `gh-pages`. All 82 advertised tag refs match exactly.
The 42 source release records were recreated against those tags; the source remains authoritative
for original publication timestamps. Target branch protection matches the source: strict update,
one approving review, no force pushes, and no deletions. Documentation run `31608227519` and Pages
run `31608350559` succeeded. The canonical root and a representative guide deep link return HTTP
200. Target CI run `31608229740` was still running at this handoff checkpoint.

The HCS registry was updated in the isolated platform worktree and merged through ADO PR 17 as
platform commit `053edfe981d74b97082b04dd6203de98cf7956c1`. It registers `azure-scout` with
`org=Hybrid-Solutions-Cloud`, `local_path=D:/git/hybrid-solutions-cloud/azure-scout`, and
`docs_platform=vitepress`. Platform Docs build 557 and MCP build/deploy 558 were running at this
checkpoint. The user's unrelated dirty platform checkout files were not staged or changed.

The product branch was rebuilt cleanly on canonical target `main` by cherry-picking only the seven
product/test commits. Its product tip immediately before this state-only update is `8a1bd611`.
Resume by reproducing the same three focused raw-inventory failures described below, fix the proven
owner, complete the focused suite, and then run the full zero-failure/zero-skip gate.

## Session 2026-08-12 — crash recovery for 3.12.3 collector correctness

The laptop crash is confirmed by Windows boot time: the machine restarted at 03:31:32. The active
branch is `agent/ab7279-run-errors-3.12.3` at `1460b0ecd258d7f33ee8d4679eb8ecf761be5055`, seven
local commits ahead of `origin/main`. The working tree was clean at recovery start, and none of the
seven 3.12.3 commits has been pushed. The manifest is version 3.12.3.

The seven commits preserve the post-3.12.2 fixes for honest ARM-child, Entra, management-group,
Defender, Azure DevOps, logging/progress, disabled-subscription, and dynamically loaded collector
helper behavior. The changelog records a completed read-only HCS live acceptance that reconciled all
278 released collectors against independent queries, including explicit filtered/empty/not-assessed
outcomes. That live reconciliation is distinct from the complete automated Pester gate.

The complete automated gate is **not finished and not green**. An exact-HEAD all-134-suite run was
started at 03:20:35 using `D:/tmp/azsc-full-suite.ps1`. Its stream logs are under
`D:/tmp/azsc-final-full-1460b0ecd258d7f33ee8d4679eb8ecf761be5055-*.log`; they stopped at 03:24:40,
before the runner wrote its result JSON, and the reboot followed. Therefore that run has no valid
summary and must not be counted as a pass. An earlier affected regression batch passed 174/174 with
zero skips before the final helper-dependency commit. Earlier exact-commit shards at `07dbfb8` found
14 failures that prompted the subsequent helper-lifetime and test-isolation commits.

The recovery-session exact-HEAD run of `tests/Collect.RawInventory.Tests.ps1` confirmed the two new
helper-lifetime tests pass, but exposed three failures before the diagnostic command timed out:

- `derives query scope only from enabled subscription container rows` received a null scope instead
  of `enabled-sub` at line 176.
- `appends ARM child rows exactly once when requested` could not resolve property `id` at line 248.
- `merges ARM-child failures into source health without dropping successful rows` hit the same
  missing `id` shape at line 264.

No source fix was attempted during crash recovery. Resume by reproducing and isolating those three
failures, repair product or fixture ownership as evidence dictates, rerun the complete
`Collect.RawInventory.Tests.ps1` suite to completion, then run all 134 Pester files against one exact
clean commit with zero failures, skips, not-run tests, or failed containers. Only after that gate is
green should the branch be pushed and 3.12.3 proceed to PR/release verification.

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

The next exact-commit attempt passed shards 0 and 1 (900/900 and 747/747). Shard 2 found two more
stale/conflicting test contracts: the direct React assessment fixture contained a successful
Advisor row but omitted `advisorAvailable=true`, and the StrictMode member-enumeration suite still
required orchestration to append the duplicate Managed Identity REST field that this release
deliberately removed. The fixture now declares successful Advisor availability; the API contract
checks the six fields still consumed and explicitly forbids Managed Identity append. Their focused
rerun passed 92/92 with zero skips. A superseding exact-commit three-shard gate remains required.

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
the GitHub Release is <https://github.com/Hybrid-Solutions-Cloud/azure-scout/releases/tag/v3.12.1>, and
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
The GitHub Release is <https://github.com/Hybrid-Solutions-Cloud/azure-scout/releases/tag/v3.12.0>, and the
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

## 2026-09-18 — performance implementation after live-run investigation

User explicitly authorized immediate code fixes during the active scan. Implementation is isolated in `D:/git/hybrid-solutions-cloud/azure-scout-performance`, branch `fix/scout-run-performance`, based on release 3.17.0 / ee8c62fb. Installed module and scan process remain untouched.

Changes: run-owned universal discovery context propagated through diagram, processing, and assessment; independent collector/health overlays; timestamp scalar traversal guard; one lazy JSON query index shared across assessment groups, gates, joins and denominator queries; detached finding evidence; discovery/query debug timing and progress; close stale extraction progress ID 0; carry forward requested resource-tag menu correction.

ADO: AB#9300, AB#9301, AB#9302, AB#9303, AB#9304. Remaining live-run defects remain separate, including comprehensive logging AB#9298.

Validation so far: first focused set 94 passed, 0 failed (Pester 6.2.0). Pester 5.7.1 broader assessment and integration suites running; do not claim final green yet. A coverage overlay bug caught by existing tests was fixed (filter null resource IDs before matching). New runtime checks cover shared discovery, separate coverage views, wrong-snapshot rejection, timestamp traversal, query reuse, detached evidence, actual diagram and processing reuse. Parser checked clean; analyzer running.

Controlled benchmark: synthetic 5,000 rows, 12 identical queries, old implementation 11,789 ms versus shared index 1,464 ms (8.05x); identical match counts, one parse. This is query-only, not an end-to-end scan estimate. Evidence: D:/tmp/scout-query-benchmark.json. Test logs: D:/tmp/scout-performance-assessment.log and D:/tmp/scout-performance-integration.log; summary JSONs written at completion.

Live scan at 21:02 reached Assess: Web; process 27036 remains active. Do not interrupt or modify its module/output. No new release, commit, or PR yet. Next: finish tests/analyzer, correct any regressions, record ADO implementation evidence, review diff, commit scoped fix. Broad historical report/auth/recovery requests must not be claimed complete based on this performance patch.

### Performance patch review state (2026-09-18)

Committed product changes as `e65fd8de`, pushed using the GitHub App to `fix/scout-run-performance`; draft PR https://github.com/Hybrid-Solutions-Cloud/azure-scout/pull/17. Full hosted CI run 35412072719 and documentation run 35412072694 are running. Do not claim released or merged.

Local verification: 332 assessment tests passed; 151 processing/discovery/service-coverage/React tests passed; 31 final report-contract tests passed. Companion reuse/fallback tests passed. An old source-string assertion expected the previous renderer filter and failed; it was replaced with a behavior check and the entire 31-test contract suite passed. Parser/diff whitespace checks clean; analyzer errors zero (196 pre-existing/advisory warnings across changed source). Pester 5.7.1 used for final suites.

Additional fix/bug AB#9306: per-assessment JSON evidence was reserialized from the complete collect for every companion. Reuse root export by byte-preserving copy, avoid duplicate findings serialization, and log companion start/finish. Tests verify no serialization when source exists, identical bytes, same-path handling and missing-source fallback. Existing report file layout remains intact.

ADO 9300/9301/9302/9303/9304/9306 are Active with PR/verification evidence. AB#9298 (comprehensive always-debug logging) and the other live collection defects are still open and are not fixed by this patch. No historical broader task should be closed solely on these changes.

Original 3.17.0 scan completed at 21:13:17; logged total runtime 4h54m24.899s. React output is assessment-report/report-react.html, plus root/per-assessment findings and evidence, diagram and inventory JSON. Installed module, console process and customer run artifacts were not modified.

Next: inspect full CI/docs results, fix any failure, then mark PR ready if green. Merge/release has not been performed. Working-tree .ai state updates remain local, outside the product commit; original workspace retains its pre-existing menu edits.

### Actual-data replay verification

Read-only offline rule replay against the completed scan's collect.json: 41 assessment groups, 550 baseline findings and 550 replay findings, zero differences in Assessment/Id/Framework/Area/Status/EvidenceCount signatures, one JSON parse, 24.233 seconds (832 MiB process private memory at completion). This excludes input loading, collection, discovery, aggregate scoring and report rendering. No Azure calls. Evidence summary: D:/tmp/scout-performance-replay-summary.json; scratch harness: D:/tmp/scout-performance-replay.ps1.

Read-only discovery replay including inventory plus Advisor: 7,217 input rows, 1,535 resources, 1,602 relationships, matching the completed run's ReportCache/Discovery.json totals. One build in 66.823 seconds, reused view 2.806 seconds; identical summaries. Input loading excluded. Earlier raw-only view produced 1,174 resources/1,241 relationships; this is expected because Advisor belongs to the processing view. Import-ScoutReportInventory then hydrates the final collect.discovery from the processing cache, preserving the combined report view. Evidence summary: D:/tmp/scout-performance-discovery-replay-summary.json.

Final output audit: all 41 original assessment folders have findings.json and evidence.json; root React exists (27,283,267 bytes). Root findings: Pass123, Fail158, Manual247, NotAssessed12, Unknown10; no Error verdicts. Artifact presence does not close the filed collection gaps. Documentation CI passed; full CI still in progress as of 21:27 local.

### Final verified review handoff (2026-09-18 21:37 local)

PR #17 is READY FOR REVIEW (draft=false), head e65fd8dead50ba711a7a4848f5425d4f36842c8c. Full hosted CI 35412072719 succeeded on that exact head: 3,909 tests, zero failures/errors/skips/not-run; StrictMode guard and static analysis succeeded. Documentation build 35412072694 succeeded on the same head. Test artifact downloaded to D:/tmp/scout-performance-ci-results.zip; summary D:/tmp/scout-performance-ci-summary.json. ADO 9300/9301/9302/9303/9304/9306 histories updated with CI and ready-for-review state; bugs remain Active because the change is not released.

NO merge, version bump, package publish, installed-module replacement, or fresh Azure scan performed. Product work is committed/pushed; only local .ai state files remain modified in the performance worktree. Next delivery step is PR review/merge and release if requested. Broader collection/logging bugs remain open. Never report the 24.233-second offline rule replay as total scan runtime.

## Completed-run remaining-defect audit

Re-read final scout-run.log, console transcript and collection-health.json following the operator's question about unimplemented findings. Confirmed six existing bugs remain outside PR #17: AB#9294 unsupported Graph sign-in projection, AB#9295 malformed Graph request misclassified as role denial, AB#9296 Sentinel connector HTTP 400, AB#9297 Sentinel ingestion TableName union collision, AB#9298 comprehensive always-debug durable logging, AB#9299 NIC effective NSG/route HTTP 400. Selected discovery/query/companion progress messages in PR #17 do not complete AB#9298. Repeated transcript pipeline-stopped messages are not fully diagnosed; scan completed successfully and those messages alone do not establish cancellation.

Separate coverage constraints remain in the saved health ledger: missing delegated Graph scopes, Entra licensing responses (including PIM), four vaults with metadata HTTP403, and Defender regulatory compliance unavailable without the required plan. Do not misclassify these as the sign-in projection bug. No new late-stage fatal failure found in the completion log. This was a status audit; no code or installed module changed.

## 3.17.1 implementation and release in progress (2026-09-18 23:50 local)

User demanded completion through release; do NOT stop again at a PR-ready status. Active performance worktree branch fix/scout-run-performance, final head ee56449f6ee5c149cb3f1576555bae1fd94c6f55. PR17 title now "fix(reliability): faster scans and complete diagnostics in 3.17.1". New commits 6a4c2149 (remaining six defects), 4da77207 (preserve plain error messages), ee56449f (remove discovery pipeline short circuit). Version bumped to3.17.1 with changelog. Product tree clean; .ai state locally modified.

Implemented AB9294-9299: v1.0 signIn projection removes authenticationRequirement; audit distinguishes non403 requests from role denial; shared Get-ScoutHttpFailure retains status/service codes/body messages and unwraps nested provider errors; Sentinel exact not-onboarded400 becomes explicit NotAssessed/NotApplicable source operation; other400s remain Unavailable; KQL internal __AzureScoutIngestionSourceTable preserves exported TableName; private-endpoint/detached NICs retain NotApplicable envelopes without unsupported POSTs; logs capture private Scout debug/verbose/warnings and real SDK streams independently of console, redact credentials, buffer pre-start diagnostics, retain exceptions, preserve success output, avoid Debug Inquire. Wrapped central Graph, ARM child, operational and ARG requests. Existing quiet-warning root hook remains compatible.

Pipeline-stop transcript noise was reproduced in actual-data discovery and traced to enrichment ForEach/Where/Select-Object -First1. Replaced with bounded foreach. Added regression verifies first payload semantics and absence of transcript pipeline-stopped records.

Tests: first collection/logging suite151 tests had2 test issues (obsolete source assertion prohibiting local preference changes, global logger stub shadowed by newly loaded local logger). Fixed assertions to runtime caller-preference isolation and Pester Mock. Expanded suite176 had175pass/1failure: plain "metrics denied" gained HTTPunknownprefix. 4da77207 fixes that compatibility issue. Final follow-up ResourceCompleteness/Operational/HttpFailure suite37/37passed, including all previously failing behavior. Full final-head CI is authoritative and still pending:35419493393, docs35419493392success. Older CI35419209268 corresponds6a4c2149 and may fail the known plain-message test; CI35419353026 corresponds4da77207. Do not mistake older CI for final head. Prior performance CI35412072719all3909passed.

Actual-data replay with durable log+transcript: D:/tmp/scout-corrected-discovery-replay-summary.json ->7217rows,1535resources,1602relationships,Builds1,FirstSeconds125.684,ReuseSeconds5.426,SummaryEqualtrue,965MiBprivate. Zero pipeline-stopped messages in D:/tmp/scout-corrected-discovery-log/scout-console.log. Runtime includes logging and concurrent test/system contention, excludes initialJSONload for reported timer. Prior unlogged66.823/2.806seconds remains separate evidence. Original41group/550finding replay24.233seconds/oneparse unchanged; no full new Azure scan.

Actual SDK verification: fresh process imported Az.Accounts, cached context, one read-only GET/subscriptions?api-version=2022-12-01 through Invoke-ScoutDiagnosticOperation. HTTP200/PSHttpResponse,80DEBUGrecords with consoleDebugdisabled; authorizationredacted; zero unredactedBearerheaders/JWTshapedvalues. Summary D:/tmp/scout-sdk-log-verification-summary.json; private log D:/tmp/scout-sdk-log-verification/scout-run.log.

ADO9294-9299nowActive with implementation history. Performance9300/9301/9302/9303/9304/9306Active. Release updates still needed for all12. Existing 3.17.0/PR16 scope already delivered authreuse,tenantretry,scope-firstmenu,reportparity (3898tests,53Entra/recovery,headlessEdge and310dataset/550findingprivate renderer replay). Do not claim new work or retest all that unnecessarily. Customer reference path EXISTS now withHTML/collect/evidence/findings, but original August logs/external scripts stillabsent. Original investigation goal tool remainsBlocked; .ai/state/RELIABILITY_REFERENCE.md now records all concerns, evidence, remedies, and remaining external evidence limits. Do not claim original historical rescoring proven.

Release helpers prepared but NOT EXECUTED:
- D:/tmp/scout-3171-merge.ps1: App auth, checks PR17 expectedhead ee56449f, requires build+test-and-lint success; tolerates onlysuccess/skipped/neutral otherchecks (docsdeployskipped onPRexpected), squashmerges viaApp API; writesD:/tmp/scout-3171-merge-commit.txt.
- D:/tmp/scout-3171-stage.ps1 -Commit <merge>: worktreeperformance; requires mergedPR17exactsha; archives source/config/manifests/docsroot into D:/tmp/scout-merged-3.17.1-<timestamp>/AzureScout; parser+import+recoveryparameterchecks; hashes; writesD:/tmp/scout-3171-package-path.txt. Need gitfetchoriginmain aftermerge soobjectexists (Appauth mayneeded ifnormalfetchfails; publicread gh/gitworks).
- D:/tmp/scout-3171-publish.ps1 -SecretName psgallery-api-key: verifiesstageversion/hashes, publishes. Dedicated azure-scoutpublishersecretprevious403; usepsgallery-api-key.
- D:/tmp/scout-3171-verify.ps1: Save-Module3.17.1freshdownload, allsourcehashmatches/extraneousfilescheck, freshimport, writesD:/tmp/scout-3171-gallery-verification.json.
- D:/tmp/scout-3171-release.ps1: Appauth, requiresmergedPR17exactsha, createsGitHubv3.17.1release fromD:/tmp/scout-3171-release-notes.md; writesD:/tmp/scout-3171-release-result.json. NotescurrentlyclaimfullCIintended; executeonlyaftergreen.
- PushhelperD:/tmp/scout-performance-github.ps1 -ActionPush. PRbodyhelperD:/tmp/scout-performance-pr-update.ps1readsD:/tmp/scout-performance-pr.md; rewritebodyfinalvalidationbeforemerge. AllauthfreshKVinmemory,no secretsprinted/saved.

Outstandingtoolsessions: CIremote asabove; localSDK91320completed; correctiontests2474completed37pass; correcteddiscovery84293completed; push63101likelycompleted (poll ifneeded). All local work snapshots now completed. Original userPID27036idlewith~10GiBprivate; leaveitandartifactsuntouched. Do NOT killuserprocess. Need finish finalCI, fixanynewfailures, thenmerge/publish/GitHubrelease/Galleryverify and safe side-by-side installation if useful, ADOResolved, stateupdatesbothworktrees. Finalanswer mustsayreleasedversionandverificationwithoutrequiringuseranotherprompt.

### Final release-head correction and additional verification (2026-09-19 00:04)

Final head is now85a9910a446242485fdd7ff7fac60b0e39535c2d, adding release version synchronization inRELEASES.md,docs/project/changelog.md,docs/project/roadmap.md. All17releasecontracttests passed locally. Apppushcomplete. CI35419964151running,docs35419964147passed. Mergehelper expectedHead updated to85a9910a. Earlierhead ee56449f fullCI35419493393 completed3922total/3919pass/3fail, failures ONLY the three now-corrected versionreferencechecks; zerootherfailures/skips. 6a4c2149CIhadoneadditional already-fixedplainmessagecompatibilityfailure.

Final-code assessment replay withalways-debugfilelogging:41groups,550baseline/replayedfindings,zero signaturedifferences,oneparse,81.64seconds,473MiBprivate. D:/tmp/scout-final-assessment-replay-summary.json. Timeincludesfileloggingandconcurrentlocalwork, notfullcloudscan. ActualNICpayload auditnowconfirmsall6NICsareprivateendpointNICswithnovirtualMachine; matchesapplicabilityfix. D:/tmp/scout-nic-applicability-evidence.json. DurableSDKverification80DEBUGrecords,HTTP200,Authorizationredacted,noJWTshapedvalues. CorrecteddiscoverysummaryD:/tmp/scout-final-discovery-verification.json includes0pipeline-stoppedmessages.

Preparedrelease-gatedADOresolutionD:/tmp/scout-3171-resolve-bugs.ps1 for12bugs; itrequiresGalleryhash/importverificationandGitHubreleaseevidencebeforeResolved. Do notexecuteuntilreleasecomplete. Packageinstallationstill3.17.0inC:/Users/KristopherTurner/Documents/PowerShell/Modules/AzureScout/3.17.0. Install3.17.1sidebysidethenverifyfreshprocess; user'soldPSprocessremainsloaded3.17.0, finaltelluserusefreshPowerShellsession. Do notkillorreloadtheirprocess.

### Release published; final local installation in progress (2026-09-19 00:26)

Final CI35419964151 succeeded on85a9910a:3922total,0failures/errors/skips/notrun. PSSA,StrictMode,docsallpassed; artifact D:/tmp/scout-3171-ci-results.zip andsummaryD:/tmp/scout-3171-ci-summary.json. PR17bodyupdatedwithfinalvalidation, mergedusingGitHubApp to11be3687b7b94d55e66d6acba515ad9698ba6c26. gitfetchoriginmaincompleted; gitdiff85a9910a...11be3687empty, exactlytestedtree. Sourcebranchremains85a9910a.

PackageD:/tmp/scout-merged-3.17.1-20260919001437/AzureScoutpassedfreshWindowsimport,527files,zeroParserErrors; hashesadjacenthashes.json. PackagepathstoredD:/tmp/scout-3171-package-path.txt. PublishedsuccessfullytoPSGalleryusingpsgallery-api-key. GitHubreleasecreatedhttps://github.com/Hybrid-Solutions-Cloud/azure-scout/releases/tag/v3.17.1, target11be3687, evidenceD:/tmp/scout-3171-release-result.json. Main docsdeployment35420734563success; automaticmainCI35420734546maystillrunbuttreeidenticaltothepassedPR.

ACTIVE TOOL SESSION10137: D:/tmp/scout-3171-verify.ps1. Save-Module downloaded3.17.1anddependenciesintoD:/tmp/scout-gallery-3.17.1-20260919002231. It has printed "Gallery source hashes match. Importing the downloaded module." All527filesmatch;freshWindowsdependencyimporttakes~4minutesonthismachine. AfterimportscriptwritesD:/tmp/scout-3171-gallery-verification.json, removesitsownscratchmodulefromitsownprocess, Install-Module3.17.1-ScopeCurrentUser-Force-AllowClobber-SkipPublisherCheck-AcceptLicense, importsinstalledexactversion,andchecksall527installedfilehashes. WritesD:/tmp/scout-3171-installed-verification.json. Do notstartasecondinstallorstopuserPID27036. Poll10137untilcomplete. Galleryverification/installedverificationfilesnotyetconfirmedwrittenasofthishandoff.

Afterthat: executeD:/tmp/scout-3171-resolve-bugs.ps1(guardsGalleryverificationandreleaseevidence) toResolved12bugs9294-9299,9300-9304,9306. UpdateRELIABILITY_REFERENCE.md/CURRENT_TASK.md/HANDOFF.mdinbothworktreeswithcompletedreleaseandinstalledpath. OriginalgoalinvestigationtoolstillBlockedhistorically;standingreferencefulfillsinvestigation/planningobjectivewithhonestexternal-script/originalAugustloglimits,considercompleteoncefinaldeliveryfinished. Finalresponsesay3.17.1released/installed,3922testspassed,12bugsResolved,andusenewPowerShellsessionbecauseuserexistingprocessstillloads3.17.0. Do notclaimfreshend-to-endcloudscanorverificationofmissingoriginalcustomerexportscripts.

## Completed release and installation — 2026-09-19

AzureScout 3.17.1 is published in Gallery and GitHub, installed side by side at C:/Users/KristopherTurner/Documents/PowerShell/Modules/AzureScout/3.17.1, and verified by fresh import and all 527 file hashes. Gallery verification: D:/tmp/scout-3171-gallery-verification.json. Installed verification: D:/tmp/scout-3171-installed-verification.json. The installer warned about already-loaded dependency versions; it retained them and successfully installed/imported AzureScout. No user process was interrupted and no old module version was deleted.

All twelve ADO bugs are Resolved: 9294,9295,9296,9297,9298,9299,9300,9301,9302,9303,9304,9306. Evidence: D:/tmp/scout-3171-resolved-bugs.json. Each history links the release, PR and Gallery package, with CI, replay, SDK logging and scope limits. PR17 merged at11be3687b7b94d55e66d6acba515ad9698ba6c26; tested head85a9910a446242485fdd7ff7fac60b0e39535c2d has identical tree. All3922 tests passed with no failures/errors/skips/notrun; static analysis, StrictMode and docs passed. GitHub release https://github.com/Hybrid-Solutions-Cloud/azure-scout/releases/tag/v3.17.1.

RELIABILITY_REFERENCE.md is the standing investigation/solution record. Corrected its customer artifact inventory: four root reports plus per-assessment companions and51backups,137files total, zero logs/scripts. Original August logs/external export scripts remain unavailable; do not claim historical reconstruction or external script compatibility has been verified. All feasible source fixes from the completed September scan are implemented/released. No new complete cloud scan was run; replay timings must not be described as end-to-end scan duration.

All local verification/install/publish tool processes completed successfully. Existing user PowerShell process27036 and original scan reports remain untouched. A new PowerShell session is needed to load3.17.1. Source branch fix/scout-run-performance remains at85a9910a; origin/main is11be3687. Product work is committed and released. Only local .ai state changes remain, copied to both worktrees; canonical pre-existing menu edits remain intact. No further release action is pending.

The original investigation/planning goal is marked complete. The standing reference distinguishes released fixes from historical questions that still lack original logs or export scripts.

