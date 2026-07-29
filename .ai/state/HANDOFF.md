# Handoff

<!--
  Written at the END of every session by whichever tool was used.
  This is the single most important cross-tool file — the next session
  (possibly a different tool) starts by reading it.
-->

## IN PROGRESS (2026-07-28, Codex) — code-derived v3.0.0 engine rebuild

### Latest release/runtime verification (2026-07-28, Codex)

- **New unshipped follow-up:** `981f6cd` removes the permanently retired App Insights
  `exportconfiguration` and `WorkItemConfigs` child-endpoint paths (AB#6154/6155) from
  `Get-ScoutArmChildResource`. Its focused contract suite is **9/9** and includes App
  Insights parents while asserting neither URI can be called. Pushed to `main`, but not
  yet included in a Gallery patch; do not resolve AB#6154/6155 until the next published
  package is verified.

- **Published and tagged:** `v3.0.1` is pushed to `main` (`23586c6`), has a GitHub release,
  and is published to the PowerShell Gallery. It contains the common-parameter wizard fix
  (`d00db3e`) and tenant-scoped context fix (`2fdf47d`, `131d60d`).
- **Gallery proof:** downloaded 3.0.1 to
  `D:\tmp\AzureScoutGalleryVerify-3.0.1-20260728-220950`, imported it in a fresh
  `pwsh -NoProfile` process, and verified version 3.0.1, exactly 21 exports,
  `Invoke-AzureScout` present, and `Invoke-ScoutAssessment` absent.
- **Gallery live proof:** `D:\tmp\AzureScoutGallery301Live-20260728-221420` completed
  in 3:37 against the explicit requested tenant. `scout-run.log` reports 174 declarative,
  0 failed, 0 skipped collectors and a written Excel report. Console audit found zero empty-
  tenant/unrelated-tenant warnings, no `exportconfiguration`/`WorkItemConfigs` requests, and
  no raw `ResourceGroupNotFound`/error-record output.
- **Focused verification:** wizard eligibility Pester 4/4; context restore 9/9;
  VM quota + subscription security sweep 13/13; permission audit 46/46 (1 skipped);
  docs-version sync 8/8. The source tenant-scoped run also completed before publishing.
- **ADO evidence/state updates:** AB#6060, #6059, #6159, #5958 → Resolved. AB#6150,
  #6151, #6148 → Closed (Task workflow supports New/Active/Closed, not Resolved).
  Each has a concise evidence history entry. Do not infer the remaining runtime child bugs
  are complete merely from the clean live run; inspect their individual fixture/acceptance
  coverage before resolving them.
- **Known local residue:** Git tracks no `Modules/` files and the Gallery package has none,
  but an empty untracked `D:\git\thisismydemo\azure-scout\Modules` directory remains.
  The filesystem policy blocked its deletion; do not claim the literal local `Test-Path Modules`
  acceptance check is met until that residue is removed.

### Latest release-hardening progress (2026-07-28)

- **Released:** commit `df06aaa` was pushed to `main`, annotated tag `v3.0.0` was pushed, GitHub
  release created, and PowerShell Gallery resolves `AzureScout` **3.0.0** successfully. The
  Gallery publish used `hcs-vault-azure-scout-powershellgallery-publisher-api-key` from
  `kv-hcs-vault-01`; no secret was written to the repository.

- Repointed active output, reporting, helper, and permission-audit tests to `src/` after retiring
  `Modules/Private`; permission-audit no-context tests now mock Azure context so they remain offline.
  Verified: OutputFormat **41 passed / 1 skipped**, PermissionAudit **46 passed / 1 skipped**,
  Private.Reporting **86/86**.
- Retired the obsolete source-script golden-capture command and the duplicate legacy
  ManagementGroups test; the current `Collect.TenantWideResources` suite owns and verifies the
  management-group fallback (**27/27** with schema and cutover tests). Resource-type reporting now
  reads the manifest catalog (**174 files, 152 declared types**) rather than deleted scripts.
- Version/doc release work is now at **3.0.0**: manifest, CHANGELOG, README/doc release page,
  roadmap, docs changelog, and release ledger are aligned. `Test-ModuleManifest`, clean
  import/smoke (`Invoke-AzureScout` exported), `git diff --check`, and DocsVersionSync **8/8** pass.
- Current contract evidence remains: 174/174 strict direct collectors; golden rows **174/174**;
  golden worksheets **348/348** in bounded groups. Remaining pre-publication work is broad suite
  completion, packaging/CI review, commit/tag, and authenticated publication. Do not claim the
  PowerShell Gallery release exists yet.
- Broad-suite batch two exposed and fixed a real StrictMode interpolation defect in
  `Get-ScoutOperationalCollectorEnrichment`: `$VmName?api-version` parsed as variable
  `$VmName?api`. It now uses `${VmName}`; focused operational-enrichment suite **4/4** passes.

### Strict declarative proof correction (2026-07-28, Codex — current)

- **Corrected prior completion evidence:** catalog coverage (174 manifests) and captured golden
  output (174 records) did **not** prove that every manifest executes under StrictMode against
  optional/missing data.  A direct 174-definition Processing sweep found **142** runtime failures;
  do not represent the declarative rebuild as complete or release-ready.
- `src/pipeline/Invoke-ScoutDeclarativeCollector.ps1` now preserves two legacy output contracts
  explicitly while keeping StrictMode enabled: an absent subscription lookup produces an empty
  Subscription cell, and the legacy no-tag sentinel produces empty tag cells.  Direct failures
  dropped **142 → 112**.  A focused golden regression test for those two cases passes (**1/0**),
  and `ManifestCollectorRuntime.Tests.ps1` remains **2/0**.
- `scripts/New-ScoutCollectorFixture.ps1` now materialises a parent resource when a definition
  resolves `$1.PARENTID` via `$Resources`; regenerated AI fixture.  AI direct execution failures
  are now **0/27** after extending synthetic path coverage and correcting the retirement fold
  compiler typo (`$Retired.ServiceID` → per-item `$Retire.ServiceID`). `AI/HealthInsights` also
  has an explicit safe language-resource lookup and correct retirement local bindings. This
  fixture change invalidates AI golden input hashes; recapture only after confirming the legacy
  reference has the same intended contract.
- Remaining global failure categories include retirement lookup locals, ARM-child/joined-resource
  fixture topology, fixed string/index assumptions, and optional nested property reads.  Fix them
  as explicit definition/fixture contracts; **do not reintroduce StrictMode Off** to make the
  proof pass.

### Latest strict sweep (2026-07-28, Codex)

- Regenerated every non-Database category fixture using the updated generator.  The direct
  Processing sweep is now **51 failures / 174 definitions** (down from 142), with AI **0/27**.
- Remaining exact collectors are logged by the current direct sweep; largest shared cluster is
  17 projected/joined objects missing the expected `name` member (primarily Hybrid plus Monitor).
  Other clusters: 8 missing nested `properties` envelopes, 3 fixed indexes, and named individual
  prefetch shapes (AVD, Security, management policy/role, network).  Golden records are stale for
  regenerated fixture hashes and must not be claimed green until recaptured after all runtime
  errors are cleared.

### Parallel strictness fixes received (2026-07-28, Codex)

- Fixed all fixed split-index reads in `Compute/AvailabilitySets`, `Containers/ARO`, and
  `Storage/NetApp` in both legacy reference scripts and manifests, using `Get-AZSCIdSegment`.
  Added `tests/CollectorIdSegmentRegression.Tests.ps1`; focused Pester **3/0**.  The direct
  global runtime sweep is now **43/174 failures** (the nested-properties batch was partially
  applied during this run; wait for its focused proof before using this count as final).
- The eight nested-properties manifests (`Analytics/Streamanalytics`; `Databases/RedisCache`,
  `SQLMIDB`, `SQLSERVER`, `SQLVM`; `Management/Backup`; `Networking/AzureFirewall`,
  `NetworkSecurityGroup`) now pass focused strict Processing with rows **7,3,2,2,2,7,7,14**.
  They intentionally drift from the legacy sources because optional data handling is now
  explicit; the current validator’s source-drift check must be retired in favour of golden proof
  before deleting legacy source. Do not “fix” this by reverting the safe manifests.
- Projected-name cluster completed: Hybrid subscription-name fields, Management policy definitions,
  Monitor autoscale/outages, Networking ExpressRoute, and DefenderPricing were made safe and their
  fixtures regenerated. Full direct strict Processing audit now reports **21 failures / 174**,
  down from 142. Exact residual list: Compute AVD/AVDScalingPlans/VMSS; Containers AKS;
  Hybrid ArcServerOperationalData; Identity AppRegistrations/ServicePrincipals; Management
  AllSubscriptions/CustomRoleDefinitions/ManagementGroups/PolicyComplianceStates; Monitor
  AutoscaleSettings/SubscriptionDiagnosticSettings; Networking Connections/Frontdoor/RouteTables;
  Security DefenderAlerts/DefenderAssessments/DefenderPricing/DefenderSecureScore; Web APPServicePlan.

### Strict execution milestone / golden-capture blocker (2026-07-28, Codex)

- **Latest verification (2026-07-28):** the direct 174-definition StrictMode Processing audit is
  **174/174 clean**. The row-equivalence gate is **174/174 passed**. The workbook proof is fully
  green when run in bounded category groups (the all-at-once 348-case run exceeds the shell's
  120-second cap): AI **54/54**; Analytics+Compute+Containers+Databases+Hybrid+Identity
  **142/142**; Networking **42/42**; Integration+IoT+Management+Monitor+Security+Storage+Web
  **110/110** — **348/348 passed** total. `Invoke-ScoutDeclarativeReporting` was corrected to
  safe-read optional `Resource U` while totaling worksheet rows; `Networking/VirtualNetwork`
  exposed that StrictMode-only renderer bug.
- **Next in progress:** retire `Invoke-ScoutCollector -Imperative`, the processing kill-switch,
  and `Modules/Public/InventoryModules` only after re-pointing/removing the obsolete source-drift
  test contracts. Current cutover tests still deliberately assert legacy fallback/kill-switch
  behavior and must be rewritten as declarative-only invariants before deletion. Then run module
  suites and full solution, update docs/version, and publish v3.0.0. Do not claim release ready.

- Full direct declarative Processing audit is now **0 failures / 174 definitions** under
  StrictMode.  Do not confuse this with the golden/workbook gate: fixtures and golden files have
  changed materially and require recapture plus comparison.
- Golden recapture succeeded through AI, Analytics, Containers, Databases, Hybrid, Identity,
  Integration, IoT, and Management; it stopped in **Compute/VirtualMachine** because the
  imperative reference emitted no rows for the regenerated fixture. The capture script correctly
  refused to write a vacuous golden record. Diagnose that legacy fixture/source contract before
  completing Compute and remaining categories, then run the full 700-test golden suite.
- Fixed primary resource TYPE restoration in `New-ScoutCollectorFixture.ps1`, regenerated Compute
  and Storage, and completed golden record capture for every category. Full 700-test golden run
  was allowed to execute for 120 seconds but timed out after entering workbook proofs; early
  failures are meaningful—not a harness defect. The declarative compiler safely corrects the
  legacy retirement-fold loop variable, so manifests now emit retirement data while legacy source
  reference scripts emit blanks (`Retired.ServiceID` instead of per-item `Retire.ServiceID`).
  Reconcile reference source behavior and recapture; do not change golden assertions to accept
  both outputs.
- Corrected the retirement fold in **88 legacy reference collectors** (and HealthInsights’ two
  analogous bindings); AST parse clean and no `$Retired.ServiceID` / `$Retired.RetirementDate`
  remains in the inventory tree. All 174 golden records have now been recaptured from that
  corrected reference, including Compute/VirtualMachine and StorageAccounts after the primary
  TYPE fixture fix. Full golden test still needs a successful completion (normal shell timeout is
  120 seconds; the direct run previously reached workbook proofs and exposed the now-fixed
  retirement mismatches).

**Do not use ADO status as completion evidence.** A fresh code audit established that the engine
rebuild is still materially incomplete: `Modules/` holds 221 `.ps1` files (176 collectors + 45
other engine files), 138 collector definitions exist, 20 StrictMode weakening sites exist, live
reporting walks and executes the collector `.ps1` tree, and `Invoke-ScoutAssessment` remains an
exported/live internal name. The repo's detailed and code-derived sequence is in
`scripts/trees/v3-engine-completion*.psd1`.

### Current code state (updated 2026-07-28)

- **174/174** collector definitions now exist and the runtime catalog is manifest-first:
  `Get-ScoutCollector -DefinitionRoot manifests/collectors` discovers all 174 without an
  InventoryModules root. `tests/ManifestCollectorRuntime.Tests.ps1`: **2/0**; deterministic
  pipeline regression: **44/0**.
- JSON, Markdown, Excel, AsciiDoc and Power BI inventory renderers use the manifest section
  index. Combined manifest renderer gate: **30/0** after the entry-point assertion correction.
- `Modules/Private/Main` and `Modules/Public/PublicFunctions` are empty. Their implementations
  now reside under `src/`; `AzureScout.psm1` loads `src/` only. Public API + clean import:
  **62/0** (agent broader public relocation proof: **89/0**); private-main relocation proof:
  **133/0**.
- `Invoke-ScoutAssessment` is removed; internal callers use `Invoke-ScoutAssessmentCore`.
  The clean-process test must set `$ErrorActionPreference = 'Stop'` before asserting the missing
  command (without it, command-not-found is nonterminating and falsely returns exit 1).
- `Modules/` currently contains only the **174** legacy inventory collector scripts. An agent is
  actively retiring these and moving the validator/tests from source-drift proof to the committed
  manifest/golden proof. Do not call the release complete until this is done and full validation,
  docs/version/roadmap and publish are complete.
- Golden capture update: records were added for AI/MLComputes, MLDatasets, MLDatastores,
  MLEndpoints, MLModels, MLPipelines, OpenAIDeployments and SearchIndexes. Capture then stopped
  honestly at `Compute/AVDApplications`: `tests/fixtures/collector-equivalence/Compute.json`
  has no entry for that collector. The golden gate therefore cannot yet prove all 174 manifests;
  build missing fixture coverage before deleting any collector script.

### Golden-proof expansion update (2026-07-28, Codex)

- The golden catalog now has **174 files for 174 collector definitions**. Capture was expanded
  using the still-present legacy scripts; added outputs include all new AI, Compute, Hybrid,
  Management, Monitor, Networking, Security, and Storage definitions.
- `scripts/New-ScoutCollectorFixture.ps1` was hardened for date/time-shaped leaves, RowCondition
  literal names, loop-filter literals, RowSource prefetch envelopes, subscription-correlated
  security envelopes, and reverse primary-to-joined-resource references (VirtualWAN).
- Do **not** yet delete `Modules/Public/InventoryModules`: full
  `tests/DeclarativeCollectorGolden.Tests.ps1` is red. Its concrete failures are fixture-hash
  mismatch for existing golden files after category fixtures were regenerated (e.g. AI), and a
  mutation-proof fixture shape issue (`properties` missing). Recapture every golden whose fixture
  hash changed, then fix that mutation proof, before source deletion.

### Completed this session — safe prerequisite work

- Added `src/report/Get-ScoutReportSectionIndex.ps1` and
  `tests/Report.SectionIndex.Tests.ps1`: deterministic, manifest-derived report section index.
  It does not change production report routing before every collector has a definition. Pester:
  **7 passed / 0 failed**; PSScriptAnalyzer: 0 findings.
- Added golden collector proof tooling:
  `scripts/CollectorGolden.Common.ps1`, `scripts/Export-ScoutGoldenRowSet.ps1`,
  `tests/DeclarativeCollectorGolden.Tests.ps1`, and **138** committed golden records under
  `tests/fixtures/collector-golden/`. The golden suite proves all definition output against
  recorded imperative output without invoking `-Imperative`: **555 passed / 0 failed / 0 skipped**
  (138 row proofs + 276 tagged/untagged workbook comparisons).
- Corrected collector audit/conversion tooling in `scripts/Invoke-CollectorAudit.ps1`,
  `scripts/ConvertTo-ScoutCollectorDefinition.ps1`, `tests/CollectorTooling.Tests.ps1`,
  `tests/fixtures/collector-audit.json`, and `docs/design/collector-audit.md`. The AST classifier
  now detects `Search-AzGraph` / COM access and excludes local helpers; the converter refuses to
  emit a definition containing live external access. Focused + schema + coverage: **29 passed / 0
  failed**; parser/analyzer: 0 errors. The current audit is **174 collectors: 126 pure-shaping /
  48 escape-hatch**.
- Removed the two dead Identity collector scripts (`IdentityProviders`, `SecurityDefaults`) plus
  their never-implemented registration-contract handling in discovery, processing, Excel
  reporting, tests, and audit. Code proof: no `Register-AZSCInventoryModule` remains under
  `src/` or `Modules/`; collector count is now **174** and missing definitions are **36**.
  Focused identity + deterministic-pipeline Pester: **144 passed / 0 failed**.
- Added and independently tested three collection prerequisites, not yet wired into the
  production inventory flow: `Get-ScoutArmChildResource` (14 child datasets),
  `Get-ScoutSubscriptionSecurityPolicySweep` (per-subscription Defender/policy/diagnostics),
  and `Get-ScoutTenantWideResource` plus `ConvertTo-ScoutManagementGroupHierarchy` (role,
  management-group, policy, policy-set datasets). Combined focused Pester: **30 passed / 0
  failed**; the ARM-child suite also passed its wider Collect regression set (**102 / 0**).
- Wired those prefetch helpers into `Get-ScoutRawInventory` behind explicit opt-in switches
  (`IncludeArmChildResources`, `IncludeSubscriptionSecurityPolicy`,
  `IncludeTenantWideResources`) while retaining the default output contract. Focused raw
  inventory integration: **17 passed / 0 failed**.
- Extended declarative conversion for two safe non-flat patterns: `RowCondition` (AdvisorScore)
  and equal-topology conditional field merging (PublicIP). Added their definitions and focused
  imperative-vs-declarative proof (**2 / 0**). Definition validation is now **140 definitions**.
- Removed both StrictMode weakenings from `Invoke-ScoutDeclarativeCollector`, removed its stale
  guard allow-list entry, and added AST regression coverage. Declarative cutover suite:
  **37 / 0**; StrictMode guard now reports **18** weakening sites (3 live, 15 legacy Modules).
- Current tree progress after the first source-cutover batches: **174 collector scripts / 168
  definitions / 6 missing definitions**. The source cutovers use raw-inventory opt-in synthetic
  rows; do not count a manifest as complete until its imperative/declarative proof passes. A full
  equivalence run exceeded the 120-second command limit and must be rerun with sufficient time.

### Corrected code facts and next sequence

- Of the current **34** missing definitions, all are escape-hatch shapes requiring prefetch or
  deliberate data-shaping conversion. The final target remains **174 definitions, zero collector
  scripts**.
- The 20 StrictMode weakening sites are all reachable; the current guard's 15 `DEAD` labels are
  incorrect. Fix reachability evidence, then harden all call trees.
- Before deleting any collector: finish golden proof/drift migration (now started), prefetch all
  live-access clusters, convert/test every remaining collector, and route Excel/JSON/Markdown/
  AsciiDoc/PowerBI reporting through manifest definitions. Then merge/relocate 45 non-collector
  files, invert discovery, remove fallbacks, delete `Modules/`, remove `Invoke-ScoutAssessment`,
  update docs/release metadata, run full validation + live verification, and publish v3.0.0.

## Board update (2026-07-28, Codex) — AB#323 is now standards-compliant

**ADO-only change; no repository code or documentation changed.** The existing multi-tenant
Epic **AB#5410** remains the parent. Its feature **AB#323** was not linked to the epic and
had no delivery decomposition. It is now title/description/AC/tag complete and parented to
AB#5410 as **"Add cross-tenant inventory scanning"** (P4 backlog).

Created and verified the full required hierarchy:

- **AB#6360** Define the cross-tenant access model
  - Tasks **AB#6363–6365**: audit current assumptions; validate Azure Lighthouse delegated
    access; document whether Lighthouse is required.
- **AB#6361** Collect authorized external subscriptions
  - Tasks **AB#6366–6368**: discovery; read-only multi-tenant collection; per-scope
    failure containment.
- **AB#6362** Produce tenant-aware inventory output
  - Tasks **AB#6369–6371**: tenant identity stamping; cache/output isolation; report validation.

All three User Stories have descriptions, 3 testable AC each, P4 priority, valid vocabulary tags,
and parent AB#323. All nine Tasks have descriptions, P4 priority, valid tags, and their correct
User Story parent. REST read-back confirmed the full **AB#5410 → AB#323 → Story → Task** chain.

The first story deliberately makes the Azure Lighthouse decision evidence-based: it validates
whether Lighthouse is needed rather than treating it as a prerequisite.

## Board update (2026-07-28, Codex) — AB#5093 served-web backlog is fully decomposed

**ADO-only change; no repository code or documentation changed.** **AB#5093** already was the
correct standalone Epic. Its 11 Features were parented properly but had no User Stories or Tasks.
All unscheduled web items are now P4 backlog, including the epic and every Feature.

Created 11 User Stories and 40 Tasks — one complete delivery decomposition under each Feature:

- **AB#6372 / 6373–6376** browser inventory portal (AB#346)
- **AB#6377 / 6378–6380** worker Azure-context preservation (AB#350)
- **AB#6381 / 6382–6385** bounded web collection requests (AB#352)
- **AB#6386 / 6387–6390** nonblocking background collection (AB#381)
- **AB#6391 / 6392–6395** collection progress publication (AB#382)
- **AB#6396 / 6397–6400** named collection stages (AB#383)
- **AB#6401 / 6402–6405** overlapping-collection guard (AB#384)
- **AB#6406 / 6407–6410** cache-backed inventory serving (AB#385)
- **AB#6411 / 6412–6414** PowerShell 7 web launch (AB#388)
- **AB#6415 / 6416–6418** worker cleanup (AB#403)
- **AB#6419 / 6420–6422** duplicate-poll prevention (AB#404)

AB#388 was corrected from a `.cmd` / `.sh` launcher proposal to a cross-platform **PowerShell 7**
launcher, as the global scripting standard forbids Batch and Bash scripts. AB#350 and AB#352
received missing web-portal/relevant functional tags.

REST read-back: **63 items total — 1 Epic, 11 Features, 11 User Stories, 40 Tasks; 0 non-P4;
0 Features without Stories; 0 Stories without Tasks; 0 Tasks missing descriptions; 0 Stories
missing acceptance criteria.**

## Last session (2026-07-25, Claude Code) — AB#5649: the processing phase has no background jobs left

**First phase of Epic AB#5638 delivered. The inventory processing phase no longer uses
background jobs or nested runspaces, and three real defects it had been hiding are fixed.**

### What replaced what

`Start-AZSCProcessJob` (or `Start-AZSCAutProcessJob` under `-Automation`) created one
`Start-Job` per category; each of those created one `[PowerShell]::Create()` runspace per
collector; `Wait-AZSCJob` waited; `Build-AZSCCacheFiles` harvested and destroyed. That is now
four functions under **`src/pipeline/`**:

| Function | Responsibility |
|---|---|
| `Get-ScoutCollector` | Discovery — pure function of the filesystem + category filter |
| `Invoke-ScoutCollector` | Run ONE collector in-process, contain its failure, time it |
| `Invoke-ScoutProcessing` | Run all 176 in a fixed order, group by category, write the cache |
| `Write-ScoutCacheFile` | Write one category — takes **data**, not job names |

**Deleted:** `Start-AZTIProcessJob.ps1`, `Start-AZTIAutProcessJob.ps1`, `Build-AZTICacheFiles.ps1`,
`Invoke-AZTIAdvisoryJob.ps1`, `Invoke-AZTIPolicyJob.ps1`, `Invoke-AZTISecurityCenterJob.ps1`,
`Invoke-AZTISubJob.ps1`. `Modules/Private/Processing/` is down to **2** files.

Rationale, alternatives and consequences: **`docs/design/decisions/deterministic-pipeline.md`**.

### Three real defects, all pre-existing, all surfaced by running collectors in-process

1. **The Security Center sheet has been empty in every release that had one.**
   `Invoke-AZSCSecurityCenterJob` was called with `-SecurityCenter $SecurityCenter` against a
   param block that declared no such parameter. **PowerShell does not reject an unknown named
   argument to a simple function** — it collects it into `$args` and carries on. So
   `$SecurityCenter` was undefined in the wrapper, `$null` crossed the job boundary as
   `-Security`, and `foreach ($1 in $Security)` iterated nothing. Now passes `$Security`.
2. **Five collectors threw on their first log call.**
   `Monitor/SubscriptionDiagnosticSettings` + the four `Security/Defender*` call
   `Write-AZSCLog -Color 'Cyan'` and `-Level Verbose`; the function accepted neither.
   Signature widened.
3. **Per-file `.CATEGORY` filtering never worked.** The regex required a line break between the
   keyword and its value; all 176 collectors write `.CATEGORY Compute` on one line, so it never
   matched and every collector fell back to its folder name. Both forms accepted now — no
   present behaviour change, since nothing declares a category different from its folder.

Plus **four more copies of the AB#5629 `NotStarted` race** in the security/policy/advisory/
subscription harvest (`State -eq 'Running'` never matches a not-yet-started job). Gone with the
jobs.

### Known limitation, now reported instead of silent

`Identity/IdentityProviders.ps1` and `Identity/SecurityDefaults.ps1` are written against
`Register-AZSCInventoryModule` / `Get-AZSCProcessedData` / `$Context.EntraData` — an API that
exists **only as a mock in `tests/Identity.Module.Tests.ps1`** and was never implemented. They
have never produced a row. Discovery now tags them `Contract = 'Unsupported'` and the pipeline
reports them as skipped rather than executing them, so a genuine failure is not buried under two
guaranteed ones. Porting them is **AB#5656**.

### Verification

- Pester **1782 / 0 / 3** across 65 files (26 new in `tests/DeterministicPipeline.Tests.ps1`).
- PSScriptAnalyzer **0 Error-severity** on all changed files.
- **All 176 real collectors smoke-run in-process** against a synthetic estate: 176 discovered,
  2 skipped by contract, 0 pipeline failures. The 10 remaining collector errors are the
  synthetic fixture lacking type-specific nested fields — adding date fields alone took the
  count 16 → 10, which is what identifies them as fixture shape, not defects.
- Determinism pinned by a test that **hashes the cache files across two runs** of the same input.
- A test asserts the pipeline **starts no background jobs**.

### ⚠ Not done, deliberately — AB#5653 stays open

**`Wait-AZSCJob` still exists and is still called** by `Invoke-AzureScout` for the draw.io
diagram wait. That subsystem starts nested jobs of its own (`Start-AZTIDiagramJob`,
`Start-AZTIDrawIODiagram`, `Start-AZTIDiagramNetwork`); folding it in would have made this change
untestable in one step. **AB#5649 (Feature) therefore also stays open** — it closes when AB#5653
does. AB#5650/5651/5652/5654/5655 are Resolved with per-item evidence.

**StrictMode is still off for collectors** — that is AB#5667's job, with the recorded
live-payload fixtures needed to do it safely.

### Live-tenant verified — and it found two more bugs the suite could not

Four runs against This Is My Demo (`d6fc73cf`). The first two **failed in the reporting phase**,
and both causes were real:

1. **`@($null).Count` is 1, not 0.** `Start-AZSCExcelJob` guarded on
   `@($SmaResources).count -gt 0`, so a collector with **no** cache entry scored 1 and was
   invoked anyway — all 176 ran in Reporting mode on every build instead of the ~30 with rows.
   Harmless until it reached the two Identity files whose top-level statement is
   `Register-AZSCInventoryModule`; invoking them at all threw and killed the Excel build.
2. **All four exporters read `$CacheData.$ModName` unguarded**
   (`Export-AZSCJsonReport`/`Markdown`/`AsciiDoc`/`PowerBI`) — under StrictMode that throws
   *"The property 'IdentityProviders' cannot be found on this object"*. **This one is a
   regression from the skip**: the old pipeline created a hashtable key for every module file
   even when it produced nothing, so the read always resolved. All four now check first. They
   were fixed in one pass rather than one live run at a time.

**Final live run — complete, all formats:**

```
Processing Phase Finished: 00:00:01:57
Report Complete. Total Runtime was: 00:00:05:16
Total Resources on Azure: 117  |  Total Resources on Excel: 416
Advisories 547 | Policies 3 | Security Advisories 484
Power BI: 35 files / 602 rows.  Excel + JSON + Markdown + AsciiDoc all written.
1 of 176 collectors failed: Management/ManagementGroups (needs MG permissions — environment)
```

**The Security Center fix is proven on real data: the `SecurityCenter` worksheet now carries
484 rows.** It was empty in every shipped release. `Subscriptions` 48, `Advisor` 547,
`Policy` 26 — all four converted paths produce data.

**Determinism proven on real data.** Two consecutive full runs, compared collector-section by
collector-section from the JSON report: **32 sections compared, 31 byte-identical.** The single
difference (`containers/containerApp` 8 → 9) was verified against Resource Graph — the tenant
really does have 9 now, so the first run caught one mid-creation. That is the estate changing,
not the pipeline.

---

## Previous session (2026-07-25, Claude Code) — v2.5.3 SHIPPED, and the engine rewrite is approved

**The operator's run crashed with `The property 'ReservationRecomen' cannot be found on this
object`. It turned out to be six crashes stacked behind each other, one root cause, and it ended
with the owner approving a full rewrite of the inventory engine.**

### Root cause — read this before touching anything in `Modules/`

Every `src/*.ps1` calls `Set-StrictMode -Version Latest` at **file** scope, and `AzureScout.psm1`
dot-sources them — so StrictMode applied to the **whole module**, including the v1 inventory engine
forked from `microsoft/ARI`, which was never written for it.

Under StrictMode, member enumeration over a collection (`$coll.Prop`) throws *"property cannot be
found"* when the enumeration yields **nothing at all**. That is what an **empty collection** on
every element produces — the empties flatten away. **A `$null` value is safe; an empty one is not.**

Azure returns `{ "value": [] }` for a subscription with no reservation recommendations. A perfectly
healthy tenant crashed the run. Data-dependent, which is why 1697 tests and three earlier live runs
never saw it.

### Six crashes, each only reachable once the previous cleared

| Where | Fault |
|---|---|
| `Start-AZTIExtractionOrchestration.ps1:59-65` | 7 member-enumeration reads → `Get-AZSCCollectedValue` |
| `Get-AZTIVMQuotas.ps1` / `Get-AZTIVMSkuDetails.ps1` | `$_.subscriptionId` / `$_.TYPE` over the **mixed** `$Resources` array — aborted the pipeline, so **no** subscription got quota data |
| 6 sites + `Wait-AZTIJob.ps1` | `(Get-Job \| Where-Object).Name` threw when nothing matched; `Wait-AZSCJob` then rejected the empty list |
| `Build-AZTIQuotaReport.ps1` | `$AzQuota.properties.Data` |
| `Start-AZTISecCenterJob.ps1` | `.Split('/')[7]`/`[8]` — a subscription-scoped Defender assessment id has only 7 segments |
| `Start-AZTIDiagramJob.ps1` | `$Job.Runspace.IsCompleted` — `PowerShellAsyncResult` has no `.Runspace`, so the wait was a **no-op** and `EndInvoke` raced its own work. v2.5.2 fixed the identical line in only one of its two copies |

Plus **AB#5636**: `Get-AZSCCostInventory` ended its catch in `throw $_.Exception.Message` with an
**unreachable** `$Costs = @()` after it, so a missing `Az.CostManagement` destroyed the whole report.

### The boundary — 17 entry points, not 5

An AST sweep found **~800** module-scope reads only valid without StrictMode. Chasing them one live
run at a time was hopeless (~7 min per discovery), so the engine entry points now `Set-StrictMode
-Off` for their own call tree. **It had to be applied at 17 places, not 5**: `Start-Job` script
blocks **re-import the module**, so module-scope StrictMode returns inside the job even when the
caller opted out — the opt-out must sit on each job/diagram function itself.
`tests/StrictModeMemberEnumeration.Tests.ps1` pins both halves: engine off, `src/` on, and the
`.psm1` must never disable it module-wide.

### Added — the run log (AB#5634/5635)

`Modules/Private/Main/Write-AZTIRunLog.ps1`. Every run writes `scout-run.log` (metadata header,
phase boundaries with elapsed time and counts, warnings, and on failure the **full error record with
script, line and script stack trace**) plus `scout-console.log`. A `trap` in `Invoke-AzureScout`
catches anything, logs it, prints the path, and rethrows with **`break`** — a bare `throw` in a trap
raises `ScriptHalted` and destroys the original error.

**The operator asked for this and was right — it found two of the six defects on its first run.**

### Shipped

Commit `97e6031`, tag `v2.5.3`, GitHub release, **PSGallery 2.5.3**, and installed into the
operator's module path. Live run: **6:43**, 105 resources, 425 Excel rows, 37 Power BI files / 989
rows, all formats written. Pester **1766 / 0 / 3**. Board 240 items, **0 conformance failures**,
137 GitHub issues linked.

### ⚠ I broke the operator's machine and had to repair it

Adding `Az.CostManagement` to the auto-install bootstrap made PowerShellGet pull down
**`Az.Accounts 5.5.1`** as a dependency (the main install then failed on admin rights). Two
side-by-side `Az.Accounts` versions make **every** `Import-Module` die with a stack overflow inside
Az.Accounts' own assembly-load-context resolver. Removed 5.5.1 with the operator's approval.
**Never add an `Az.*` module to that bootstrap.** `Az.CostManagement` is an optional documented
prerequisite instead, and a test asserts it stays out.

### APPROVED — Epic AB#5638, rebuild the engine

The owner challenged why we are running the ARI fork at all, and approved a full rewrite:
**AB#5638** Epic → Features **AB#5639** (one collector), **AB#5649** (deterministic pipeline),
**AB#5656** (declarative collectors), **AB#5662** (unified reporting), **AB#5667** (StrictMode +
live-payload fixtures) → 15 User Stories → 15 Tasks, all conformant.

**Start with AB#5649** — deleting the background-job machinery kills the whole crash class.
The end state is the deletion of `Modules/`.

---

## Previous session (2026-07-25, Claude Code) — v2.5.2 SHIPPED: runs are now deterministic

**Both remaining open questions from v2.5.1 are root-caused, fixed, released and verified. Nothing
is left as an unknown.**

### AB#5629 — a whole report category could silently vanish

`ReportCache/Compute.json` came back **5,158 bytes on one run and 470 on the next**, same tenant,
same scope. Every Compute module reported zero rows while the hashtable keys were still present —
which located the loss at the **job** level, not the collector.

**It was a race, not Resource Graph throttling.** `Start-Job` is asynchronous, so a job created
moments earlier sits in `NotStarted`. That state satisfied neither `Wait-AZSCJob`'s loop condition
(`State -eq 'Running'`) nor `Start-AZSCProcessJob`'s batch filter, so it was never waited on —
then `Build-AZSCCacheFiles` ran `Receive-Job` (nothing to receive) and `Remove-Job`, destroying it.

A second, independent bug in the same path: `While ($Job.Runspace.IsCompleted -contains $false)`
was a **no-op**. Those handles are `PowerShellAsyncResult` and have **no `Runspace` property**, so
the expression was empty and `-contains $false` was always false. Proven in isolation before
fixing.

| File | Change |
|---|---|
| `Wait-AZTIJob.ps1` | wait on every non-terminal state, not just `Running` |
| `Start-AZTIProcessJob.ps1` | include `NotStarted` in the batch wait; `$Job.Runspace.IsCompleted` → `$Job.IsCompleted` |
| `Build-AZTICacheFiles.ps1` | warn when a job is harvested non-`Completed`, or a category returns nothing |
| `Build-AZTIExcelComObject.ps1` | detect a missing `Excel.Application` ProgID and explain, instead of a raw `0x80040154` |

`tests/JobWait.Tests.ps1` (5 tests) pins the contract and pins the `Runspace`-vs-`IsCompleted`
distinction so the no-op cannot come back.

### Verified — three consecutive live runs, byte-identical

227 Azure resources · 994 Excel rows · 40 Power BI files / 1013 rows · 166 Azure DevOps resources ·
**0** empty-category warnings · **0** raw COM errors. Runtimes 4:49 / 4:13 / 4:07. Before the fix
these varied run to run.

Tag `v2.5.2`, GitHub release, **PSGallery → 2.5.2**. Board: 199 items, 183 Closed, **0 conformance
failures**, 134 GitHub issues linked. Pester **1697 / 0 / 3**.

### Diagnostic note worth keeping

**An empty `ReportCache` folder after a successful run is not data loss** — a completed run cleans
it up. Earlier runs only left cache files behind because they *crashed* before cleanup. I nearly
misread that as a regression.

### Trap repeated a third time

I wrote `AB#5568` into five files before creating the item; the real id came back **`5629`**. All
references corrected. **Create the work item first, then write its id.** This has now happened
three times in this repo (5418, 5548, 5568).

---

## Previous session (2026-07-25, Claude Code) — v2.5.1 SHIPPED: Scout now completes a live run

**The headline: before this session, `Invoke-AzureScout` could not finish a full run against a real
tenant. It can now.** The operator asked "test it on mine", and the live run found **seven** defects
that **1692 passing tests did not**.

### Why the suite missed all seven

Nothing drove the extraction → processing → reporting chain against real collector output. Every
test either mocked Azure or exercised a unit in isolation. A green suite was not evidence the
product worked, and it should not be treated as such again.

| Phase | Defect | Item |
|---|---|---|
| Extraction | `$MGContainerExtension` consumed unconditionally, assigned only in the `-ManagementGroup` branch | AB#5547 |
| Processing | 41 `.IsPresent` reads on params not declared `[switch]` (`$null` when omitted) | AB#5547 |
| Reporting | ImportExcel throws on `-Style`/`-TableName` over a zero-row worksheet | AB#5567 |
| Reporting | Cost + update-manager sheets read `$vm.Name`/`$vm.Size`/`OS SKU`; collector emits `VM Name`/`VM Size`/`OS Version` — **those sheets had never carried VM rows** | AB#5567 |
| Charts | 29 `$excel.'<Name>'` dereferences throw when the estate has no such worksheet | AB#5567 |
| Charts | 10 pivot titles read before assignment (P7, P9 have a single branch) | AB#5567 |
| Markdown | `"$totalResources_"` — trailing italic underscore parsed into the identifier | AB#5567 |

### Live verification (This Is My Demo, tenant `d6fc73cf…`)

```
Azure DevOps Extraction Complete: 166 total resources
Report Complete. Total Runtime: 00:03:58
Total Resources on Azure: 227  |  Total Resources on Excel: 994
Files: 40  |  Total rows: 1013
```

**`-IncludeDevOps` is live-verified for the first time** — 74 projects, 4 pipelines, 4 service
connections, 74 repositories, 10 agent pools — closing the "36 mocked tests only" gap that had been
open since v2.3.0. The auth decision holds: the Azure sign-in is reused for an Entra token, no PAT.

### Release

Tag `v2.5.1`, GitHub release, **PSGallery `Find-Module AzureScout` → 2.5.1**. Board: 198 items,
182 Closed, **0 conformance failures**, 133 GitHub issues all linked. Pester **1692 / 0 / 3**.

### Traps hit this session — read before repeating

- ⚠ **PSGallery caps manifest `ReleaseNotes` at 10,600 characters.** The cumulative string hit
  10,788 and the push was rejected with a 400. It now carries only the three most recent releases
  plus a CHANGELOG link. **Do not go back to appending every release.**
- ⚠ **`az` CLI and `Az` PowerShell keep separate contexts** and were signed into *different
  tenants*. Scout's inventory path uses the Az PowerShell context. Check `Get-AzContext` before
  claiming anything ran against a given tenant — and check whether a login already succeeded before
  asking the operator to do it again.
- ⚠ **I wrote `AB#5548` into six code comments before creating the item; the real id came back
  `5567`.** All references were corrected. Never write a work-item id that has not been returned by
  the API. This is the second occurrence.
- ⚠ StrictMode is **dynamically scoped**. The v1 inventory path does not set it, so these bugs only
  bite when the caller does — but the HCS scripting standard requires it of every script, and four
  of the seven defects above threw *without* StrictMode too.

### Open questions carried forward

- **Compute collection is non-deterministic** — `ReportCache/Compute.json` was 5,158 bytes on one
  run and 470 on the next, same scope. Possibly ARG throttling. No work item yet.
- `Build-AZSCExcelComObject` needs Excel installed via COM (`0x80040154`); non-fatal, and the
  reason `lite` defaults to true.

---

## Previous session (2026-07-25, Claude Code) — v2.5.0 SHIPPED: one collection pass (AB#5543)

**The backlog outside web and multi-tenant is now empty.** Board: 196 items — **180 Closed / 14
New / 2 Removed**, and all 14 open items are Epic AB#5093 (web app, 11 children) and Epic
AB#5410/AB#323 (multi-tenant) — the two areas the owner excluded. Conformance: **0 ADO failures,
0 GitHub reconcile failures.**

### What shipped

A combined inventory + assessment run queried Azure **twice** over the same resource types.
`Start-AZSCGraphExtraction` (note: **AZTI** prefix on disk —
`Modules/Private/Extraction/Start-AZTIGraphExtraction.ps1`) already projects the full `properties`
bag from `resources`, `networkresources` and `resourcecontainers`, a superset of what the
assessment's typed queries re-fetched.

| File | What |
|---|---|
| `src/collect/ConvertFrom-ScoutInventory.ps1` (new) | Shapes every assessment scalar from inventory rows, mirroring the KQL field for field |
| `src/collect/Invoke-Collect.ps1` | New `-FromInventory`; queries satisfied from inventory skip ARG entirely |
| `src/Invoke-ScoutAssessment.ps1` | New `-FromInventory`, threaded to `Invoke-Collect` |
| `Modules/Public/PublicFunctions/Invoke-AzureScout.ps1` | The wizard "both" path now **defers** the assessment until after the inventory pass, so the rows exist to hand over |
| `tests/CollectorCollapse.Tests.ps1` (new) | 17 tests |

**Measured result:** with `-FromInventory` the collector reaches Resource Graph **once**; without
it, **30+** times. The one remaining query is `sqlDefenderPricing` — it reads the
`SecurityResources` table (`Microsoft.Security/pricings`), which inventory only touches under
`-SecurityCenter` and then filters to `microsoft.security/assessments`, so those rows are
genuinely never present. That is a real limit, not an oversight.

### Why this was safe to do now

The KQL stays the reference implementation — an assessment-only run is completely unchanged and
still issues the full pack. A shaping failure **falls back** to Resource Graph rather than costing
the caller their assessment. The tests pin the four semantics a naive PowerShell rewrite silently
breaks:

- `array_length(null)` is **null**, not `0` — a VNet with no peerings array must report
  `peeringCount` null or rules filtering `> 0` change behaviour.
- `tobool(null)` is **null**, not `$false` — returning false would flip rules testing for explicit false.
- subnet capacity is `2^(32-prefix) - 5`.
- `allPoolsZoned` only when **every** AKS pool has zones.

### Bug found while shaping, not in any work item

Rows appear in **both** the `resources` and `networkresources` tables. Without de-duplication by
resource id, a VNet present in both is counted twice and inflates every existence-count rule.
De-duped in `ConvertFrom-ScoutInventory`, with a regression test.

### Release

Tag `v2.5.0`, GitHub release created, **PSGallery `Find-Module AzureScout` → 2.5.0**. Commits
`a138d2e` (feature) and the release-metadata commit after it. Pester **1688 pass / 0 fail /
3 skip** (up from 1671). Analyzer **0 Error-severity**. Docs site builds clean.

Two stale statements the release surfaced and corrected: the manifest `ReleaseNotes` still
asserted the now-false "inventory and assessment still collect their Azure data independently",
and the `RELEASES.md` 2.4.0 row was still marked 🟡 in-progress after that release had shipped.

⚠ **Publish trap:** `Publish-Module` needs the folder name to match the module name. The repo
folder is `azure-scout`, the module is `AzureScout` — publishing the repo root fails with "no
valid module was found with that path". Stage into a folder literally named `AzureScout` first.

---

## Previous session (2026-07-25, Claude Code) — post-v2.4.0 conformance sweep: board back to zero failures

**Question asked: is the solution done?** Code: yes. Board: it was not, and every failure was created
by the previous session.

`./scripts/Test-BoardConformance.ps1` reported **15 failures**, all on the three items v2.4.0 created
(AB#5540, AB#5541, AB#5543). The previous session wrote those items without running the conformance
script it had itself committed for exactly this purpose. Fixed:

| Failure | Fix |
|---|---|
| No acceptance criteria on any of the three (need 2 / 3 / 3) | Wrote AC as `<ul><li>` — the checker counts `<li>`, so plain text scores 0 |
| 9 non-vocabulary tags (`api-surface`, `regression`, `onboarding`, `ux`, `architecture`, `collect`, `performance`, `tech-debt`) | Remapped to the approved vocabulary via `op=replace` |
| AB#5540 (Bug) and AB#5541 (User Story) parented straight to Epic AB#5023 | Created Feature **AB#5544** (entry-point unification, Closed) as their parent |
| AB#5543 (New) hanging off Closed Epic AB#5023 | Created Epic **AB#5545** *Collapse the Azure Scout collection layer onto a single pass*; AB#5543 reparented under it |
| AB#5540 Bug with no GitHub master record | Filed **GH#182**, typed Bug, labels `ado-tracked`+`resolved`, closed completed, hyperlinked from ADO |
| AB#5540 / AB#5541 still `Resolved` after shipping in v2.4.0 | Moved to `Closed`, along with the new Feature AB#5544 |

**Now: 196 items — 178 Closed / 16 New / 2 Removed. 0 ADO failures, 0 GitHub reconcile failures,
131 GitHub issues all linked. No item is left in Resolved.**

### Release state verified live, not asserted

- PowerShell Gallery: `Find-Module AzureScout` returns **2.4.0**, published 2026-07-25 14:29.
- `AzureScout.psd1` `ModuleVersion = '2.4.0'`; `CHANGELOG.md` newest heading is `[2.4.0]`.
- "Build and Deploy Documentation" succeeded on `a63712d`, the last docs-touching commit. `d2e07f7`
  touched only `.ai/state/HANDOFF.md`, so the deployed site was already current.

### Docs bug found and fixed

`docs/changelog.md` — the summary table stopped at **v2.2.0**. Both v2.3.0 and v2.4.0 were missing, so
the published changelog page understated the product by two minor releases. Added both rows. (v2.2.1 is
still absent by the page's existing convention of listing minor releases only — left alone deliberately.)

`.ai/state/CURRENT_TASK.md` still described v2.3.0 as the current release; rewritten.

⚠ **Trap hit again:** hardcoding the area path as `This Is My Demo - Azure Scout\Platform` fails with
`TF401347`. The project name contains U+2014 and the console mangles it. The fix script now reads both
the area and iteration trees from `_apis/wit/classificationnodes` and uses those strings verbatim. This
is already in the memory notes — read them before writing to the board.

**Verification:** `npm run docs:build` clean. Conformance script **PASS**.

---

## Previous session (2026-07-25, Claude Code) — v2.4.0 SHIPPED: one command, guided wizard, docs collapsed

**v2.4.0 is released and live on the PowerShell Gallery** (published 2026-07-25 14:29).
Tag `v2.4.0`, GitHub release created, `main` at `a63712d`.

Delivered across three commits:

| Commit | What |
|---|---|
| `d5f3b45` | Entry-point unification + wizard (AB#5540, AB#5541) |
| `8cd8c2e` | Site-wide docs collapse + v2.4.0 release prep |
| `a63712d` | Known-limitation notes linked to AB#5543 |

### Docs sweep — done

Every page that framed inventory and assessment as two products now frames them as two modes.
Runnable examples in `assessment.md`, `assessment-permissions.md`, and `src/README.md` use
`Invoke-AzureScout -Assessment` (`-OutputPath`→`-ReportDir`, `-ManagementGroupId`→`-ManagementGroup`).
"v1 inventory"/"v2 assessment" replaced with "inventory mode"/"assessment mode" throughout.

**Two more false PowerShell-5.1 claims** were found and fixed beyond the three in `d5f3b45`:
`assessment-prerequisites.md` ("the v1 inventory cmdlet … still runs on Windows PowerShell 5.1")
and `folder-structure.md` (annotated the manifest as "PowerShellVersion 5.1, CompatiblePSEditions
Desktop+Core"). Historical roadmap rows describing what v2.2.0 shipped were left alone — accurate
as history.

`parameters.md` also corrected two behaviours documented as no-ops that are not: `-Scope EntraOnly`
throws in assessment mode, and `-Category` really does filter the collect.

### ⚠ Still open — AB#5543

**Feature AB#5543** (`New`, area `Collect`, under Epic 5023) now tracks the duplicate collection
passes. NOT fixed in v2.4.0, deliberately: `Invoke-Collect` computes its scalars in KQL
(`mv-expand`, `coalesce`, `array_length`, cross-table joins on `securityresources`/
`networkresources`), and reimplementing ~30 projections in PowerShell against in-memory rows
risks silently corrupting assessment scores. It needs its own design + verification cycle.
Acceptance criteria are on the work item. Known-limitation notes in `CHANGELOG.md`,
`docs/overview.md`, and `docs/roadmap.md` all cite AB#5543.

Key finding for whoever picks it up: `Start-AZSCGraphExtraction.ps1` already pulls the **full
`resources` table with `properties` projected** — a superset of what the assessment's 26 typed
queries re-fetch. The data is already in memory; the work is the shaping, not the fetching.

---

## Previous session (2026-07-25, Claude Code) — ONE COMMAND: inventory + assessment unified, wizard added

**Trigger:** the operator challenged the published
[Overview: Inventory vs Assessment](https://thisismydemo.cloud/azure-scout/overview.html) page —
"azure scout is fucking azure scout … who told you to split this?"

They were right, and it was our error. Feature **AB#5024** ("Build the module registry and
`Invoke-AzureScout` entry point", Closed) specified **one** entry point. The v2 CAF/WAF scaffold
(commit `6dcd0ae`, 2026-07-20) shipped a second public cmdlet `Invoke-ScoutAssessment` anyway,
and ~13 docs pages were then written around the split. The overview page justified it partly on a
differing PowerShell floor that never existed — the manifest has always been
`PowerShellVersion = '7.0'` + `CompatiblePSEditions = @('Core')`.

### Delivered — commit `d5f3b45` on `main` (pushed)

| Item | What |
|---|---|
| **AB#5540** (Bug, Resolved) | Inventory + assessment collapsed onto `Invoke-AzureScout`. `-Assessment`, `-CollectOnly`, `-FromCollect` added. Assessment mode now honours the inventory sign-in params (it previously required a pre-existing `Connect-AzAccount` silently). `-OutputFormat` widened `[string]`→`[string[]]`, ValidateSet 8→15, cross-mode misuse throws an actionable error. `Invoke-ScoutAssessment` retained, **deprecated, remove in v3.0.0**. |
| **AB#5541** (User Story, Resolved) | Guided wizard on a bare `Invoke-AzureScout`: sign-in → tenant pick → rights check → checklists (run type / categories / assessments / formats / report dir, all pre-selected) → prints the equivalent one-line command. Gated on `Test-AZSCInteractiveHost`; **never** fires in CI or with redirected stdin. `-NoWizard` forces the old path. `Start-AZSCWizard` exported. |

New file `Modules/Public/PublicFunctions/Start-AZSCWizard.ps1`; new test file
`tests/UnifiedEntryPoint.Tests.ps1` (25 tests).

**Verification:** Pester **1671 passed / 0 failed / 3 skipped**. VitePress build clean.
PSScriptAnalyzer clean apart from the repo-wide pre-existing `PSAvoidUsingWriteHost`.

### ⚠ Open — the real architectural problem, NOT yet fixed

The operator's follow-up landed harder than the naming issue: *"how can you do an assessment
without understanding the inventory?"* Confirmed in code — **the two modes collect Azure data
twice**:

- inventory → ~176 per-resource-type modules under `Modules/Public/InventoryModules/` (15 categories)
- assessment → its own **26-query** ARG pack in `src/collect/Invoke-Collect.ps1`

…over the same resource types (`microsoft.storage/storageaccounts`, `microsoft.sql/servers`,
`microsoft.network/*` …). Running both queries Azure twice. The assessment manifest even has an
`Estate` entry described as *"Full digital estate inventory (no scoring)"* — the assessment layer
reimplementing inventory.

Documented as a Known Limitation in `CHANGELOG.md` and a warning box in `docs/overview.md`.
**No ADO item exists for this yet — create one and collapse the two collection passes.**

### Also still open

Docs sweep is partial. `docs/overview.md`, `docs/prerequisites.md`, `docs/assessment.md`, and the
VitePress nav are corrected. Still presenting `Invoke-ScoutAssessment` as the primary entry point:
`index.md`, `usage.md`, `parameters.md`, `authentication.md`, `permissions.md`,
`folder-structure.md`, `roadmap.md`, `assessment-prerequisites.md`, `assessment-permissions.md`,
plus `README.md` and `src/README.md`.

⚠ **Trap for next session:** `AB#5418` is **not** a Scout item — it belongs to `project-42.dev` in
a different ADO project. It was used by mistake mid-session and has been purged from the repo.
Verify every work-item ID against the live board before writing it into code.

---

## Previous session (2026-07-25, Claude Code) — v2.3.0 SHIPPED: backlog closed except web + multi-tenant

**Every open work item other than the two deliberately-excluded areas is built, tested, released,
PSGallery-published, and Closed on the board.**

Board: **191 items — 175 Closed / 14 New / 2 Removed**.
`./scripts/Test-BoardConformance.ps1` → **0 ADO failures, 0 GitHub reconcile failures.**

### What shipped (v2.3.0)

Epic **AB#5411** (collection hardening) is Closed. Epic **AB#5410** retains only AB#323.

| Item | What |
|---|---|
| AB#331 | Run isolation — each invocation gets its own run folder; `-RunName`, `-Force`, `Clear-AZSCCacheFolder -OlderThan` |
| AB#368 | Caller's subscription context restored in a `finally` at all five `Set-AzContext` sites |
| AB#351 | Post-login management group probe + cyan role tip; never aborts the run |
| AB#327 | Azure DevOps inventory via `-IncludeDevOps` — five worksheets, service-connection-to-subscription cross-reference |
| AB#328 | Composite `action.yml` at repo root; fixed the non-functional `azure-inventory.yml` |
| AB#343 | `docs/automation.md` (eight-step guide) plus two real runbook fixes |
| AB#318 / AB#5417 | `docs/category-reference.md` plus the README quick-reference table |
| AB#315 | `docs/validation-matrix.md` — per-check automated vs live-tenant coverage |

Commits `7c4380b`, `6574b76`, `9f3ba68`, `cad2b42`. Tag `v2.3.0`. GitHub release created.
PSGallery: `Find-Module AzureScout` returns **2.3.0**.

### Decisions made — do not relitigate

- **Azure DevOps auth reuses the Azure sign-in**, requesting an Entra token for resource
  `499b84ac-1321-427f-aa17-267ca6975798`. `-DevOpsPat` is the fallback, not the default. This
  answers the work item's open question about PAT vs OAuth.
- **ADO collectors live in `Management/`**, not a new `DevOps` category folder — the existing
  `DevOps` to `Management` alias already declared that is where DevOps work lands.
- **The GitHub Action ships as `action.yml` in this repo**, not a separate `azure-scout-action`
  repo, so there is no second artifact to version.
- **`lite` defaults to `true`** in the Action: chart customization drives Excel over COM and no
  hosted runner has Excel installed.
- **AB#321 `-WhatIf` is marked Won't do** on the roadmap — Scout is read-only, so there is no state
  change to preview.

### Bugs found and fixed that were not in any work item

- `Set-AzStorageBlobContent` lacked `-Force`, so the **second** scheduled runbook run failed with
  "blob already exists" and the report never landed.
- `$Debug.IsPresent` is always `$null` (`-Debug` is a common parameter, not a declared one), so the
  runbook diagnostic log never uploaded.
- `docs/category-structure.md` documented `Networking + CDN` as an alias absent from
  `$_categoryAliasMap`. Added the alias rather than deleting the documentation line.
- `tests/AzureScout.Tests.ps1` pinned the version to the literal `2.2.1` and broke CI on the bump.
  It now asserts the manifest against the newest `CHANGELOG.md` heading, so it needs no edit next
  release.
- `docs/testing.md` claimed 29 files / ~1,240 tests / 237 scripts. Real: 56 / 1,648 / 274.

### Verification status

- Pester **1,648 passed, 0 failed, 3 skipped** across 56 files (66 new).
- PSScriptAnalyzer **0 Error-severity** findings across `Modules/`. The `Write-Host` warnings are
  pre-existing and non-blocking — CI only fails on Error severity.
- CI run `30147596840` succeeded. Docs site builds clean.
- **Not verified against a live tenant.** The Azure DevOps collectors are covered by 36 mocked tests
  only; nobody has pointed `-IncludeDevOps` at a real organization yet. That is the highest-value
  next check — `docs/validation-matrix.md` lists every live-tenant row.

### Deliberately still open (14 items)

- **Epic AB#5093** — served web application, 11 children. Never approved for build; needs a
  go/no-go. Web and PowerShell are ONE product at parity, never rival feature sets.
- **AB#323** under Epic AB#5410 — multi-tenant Lighthouse cross-tenant scanning. Its run-isolation
  prerequisite shipped in v2.3.0.

---

## Previous session (2026-07-25, Claude Code) — ADO/GitHub conformance drive COMPLETE (W2 + W3b + W4)

**Result: the board and the GitHub issue set now reconcile exactly, with zero standards violations.**
Verification script: `scratchpad/conformance.ps1` — **185 ADO items, 0 conformance failures; 130 GitHub
issues, 130 linked, 0 reconcile failures.**

**W2 — tag vocabulary (was the last open item from the 2026-07-21 audit).**
- Created **AB#5385** in *Platform Engineering* (User Story, Standards and Governance, P3).
- Platform Engineering **PR 10** (`standards/scout-product-tags`, commit `3ca991c`, merge `4f87398`)
  added a **Product-surface tags** group to `docs/standards/work-items.md`: `powershell`, `cli`,
  `web-portal`, `cross-surface`, `module-enhancement`, `reporting`, `resilience`, `delivery`,
  `config`, `future-roadmap`. Merged; Platform Docs Deploy run 299 succeeded. AB#5385 → Closed.
- The group note states explicitly that a surface tag says *where work lands*, never a per-surface
  feature set — parity work is `cross-surface`.
- Consolidated rather than blessed: `web-interface`→`web-portal`, `far-future`→`future-roadmap`,
  `feature-parity`→`cross-surface`, `pdf-export`→`reporting`, `progress-ux`→`cli`. Remapped on
  9 Scout items (323, 328, 332, 379, 394, 395, 405, 5093, 5094). **0 non-vocabulary tags remain.**
- ⚠️ GOTCHA: an ADO PATCH of `System.Tags` with `op=add` **appends**; you must use `op=replace`.

**Split source-of-truth violation fixed — Bugs are GitHub-master.**
18 ADO-native Bugs (AB#5076–5092 audit findings + AB#5247 v2.2.1 crash-hardening) had no GitHub
record. Filed **GH#164–181** (native type Bug, labels `ado-tracked`+`resolved`), closed as completed,
and hyperlinked back to their ADO items. **0 ADO Bugs now lack a GitHub master record.**

**W4 — GitHub ↔ ADO reconcile (work-item-sync Flow 1).**
- Created the missing reserved workflow labels: `needs-triage`, `in-progress`, `resolved`,
  `wont-fix`, `roadmap`, `ado-managed`, `cross-repo`.
- 91 previously-linked issues: filled native issue type on 58 untyped, applied the Flow 1 status
  label + a status comment on 69, closed GH#9 as not-planned (AB#321 Removed).
- 21 closed GitHub issues had **no ADO record** (closed before the mirror ran). Backfilled
  **AB#5392–5407** (1 Feature, 1 Bug, 14 User Stories, all Resolved, parented under AB#5246/5251),
  and linked the two duplicate docs-migration issues (GH#34/35) to the existing AB#5248.
- ⚠️ I ran the reconcile script twice against a stale plan and double-posted the status comment on
  69 issues; `scratchpad/gh-dedupe-comments.ps1` deleted the 69 duplicates. Rebuild the plan file
  before re-running any apply script.
- ⚠️ GOTCHA: `System.AreaPath` must be read back from the classification-node API and sent verbatim —
  the project name's em-dash gets mangled by console round-tripping (TF401347).
- ⚠️ GOTCHA: `gh issue list --json` uses the **GraphQL** quota; when it is exhausted, fall back to
  `gh api repos/<repo>/issues` (REST), filtering out entries that carry a `pull_request` key.

**Board now: 185 items — 158 Resolved / 23 New / 3 Closed / 1 Removed.**
GitHub: 130 issues — 90 open / 40 closed.

**Resolved → Closed, done.** All 158 Resolved items moved to **Closed** (closing criteria met: AC
verified during delivery, code shipped in v2.2.1, linked issues carry a status comment, successors
exist) and the 68 still-open linked GitHub issues were closed as completed with a status comment.

**W5 — `docs/design/task-list.md` is now generated, not hand-maintained (AB#345, Closed).**
`scripts/Build-TaskList.ps1` renders the page from the live board (WIQL + workitemsbatch) plus the
GitHub issue set, grouped by epic into open / delivered / dropped. Auth is the ambient `az` session
and the `gh` CLI — no PAT stored. Regenerate with `./scripts/Build-TaskList.ps1`.
- ⚠️ GOTCHA: VitePress compiles Markdown as a Vue template, so a work-item title containing
  `<domain>` fails the build as an unclosed tag. The generator HTML-escapes titles.
- Verified: `npm run docs:build` green, Pester **1582 pass / 0 fail / 3 skip**, analyzer clean apart
  from the repo-wide BOM style warning.

**Final state: 185 ADO items — 162 Closed / 22 New / 1 Removed. 130 GitHub issues, all linked.
`conformance.ps1`: 0 ADO failures, 0 GitHub reconcile failures.**

**Defect the owner caught after the drive — closed epic owning open work.** 12 open items were still
parented to **AB#5023**, an Epic that had been *Closed* as a roll-up. A closed epic cannot own open
work: the roll-up reports done, and the items vanish from epic-level planning, which is why they kept
getting labelled "polish" and skipped. Fixed by creating the two epics that were missing:
- **AB#5410** *Integrate Azure Scout with external platforms and multi-tenant estates* (P3) —
  AB#323, 327, 328, 332, 343. Build-or-close decision, nothing started. AB#323 and AB#332 are the
  same capability filed twice; linked as Related with a comment, to be collapsed on decision.
- **AB#5411** *Harden the Azure Scout collection run and close the remaining documentation gaps*
  (P2) — AB#315, 318, 331, 351, 368. The only open work needing no product decision.
- **AB#350** (Save-AzContext for the background collection runspace) and **AB#352** (browser-side
  AbortController on the collection fetch) moved to **AB#5093** — both are web-app plumbing, not
  module work.
**Type-hierarchy violations — 12 found and fixed.** The owner pushed back that these are standards
rules, not judgement calls. Correct. `work-items.md` dictates **Epic → Feature → User Story → Task,
with Bug a peer of User Story** (so a Bug's parent is a *Feature*). I had only ever checked that a
parent *existed*, never that it was the right *type*. 12 items were Bugs or User Stories parented
straight to an Epic:
- AB#335–340, 347 (v1 inventory defects) → reparented to the existing Feature **AB#5251** (v1
  foundation), which is also their correct theme — they were under the CAF/WAF epic.
- Created the four missing intermediate Features: **AB#5414** StrictMode crash-class hardening
  (→5247), **AB#5415** agent/session-protocol scaffold (→5250), **AB#5416** work-tracking and
  roadmap generation (→341, 345), **AB#5417** report documentation gaps (→318, open under 5411).

**Duplicate resolved by the standard, not by preference.** AB#332 was the same capability as AB#323
filed twice. The board precedent set by AB#321 is the rule: redundant item → **Removed**, and Flow 1
mirrors that down as `wont-fix` + a not-planned close on the GitHub master (GH#21). AB#323/GH#11
(filed first) survives as the single multi-tenant record.

**`scripts/Test-BoardConformance.ps1` is now committed** — it enforces every rule above, including
the parent-**type** check and the closed-parent check, and exits non-zero so it can gate a pipeline.
Analyzer clean. **Run it before claiming the board conforms.**

**Board: 191 items — 165 Closed / 24 New / 2 Removed. 3 open epics: 5093 (11), 5410 (4), 5411 (5+1).**

**Note (not a defect):** GH#1/3/30/31 are typed `Task` in GitHub but Feature/User Story in ADO.
GitHub is master for Flow 1 types, so both sides were left alone.

**Branch:** main — commits `999839c` (handoff), `b1d931b` (generator + regenerated task list) —
pushed. The rest of the drive wrote to ADO, GitHub, and the Platform Engineering repo.
**Scripts:** `scratchpad/{board,tag-remap,close-5385,link-map,gh-labels,gh-bug-backfill,gh-reconcile-plan,gh-reconcile-apply,gh-dedupe-comments,ado-backfill-gh,conformance}.ps1`.

## Prior session (2026-07-24, Claude Code) — ADO standards conformance drive (IN PROGRESS)

**Directive (user, emphatic):** make ADO/GitHub 100% accurate and able to track the project exactly;
**create items for ALL work done**; **fully follow the ADO standards in the HCS Governance MCP**;
**delete NOTHING** (esp. `docs/design/task-list.md`) until the board is provably exact. Decisions the
user considers already-made: tags → follow standard = add via PR (keep them); backlog backfill → all.
Do NOT re-ask (they were angry that I did).

**Standards pulled from MCP** `get_standard(work-items / work-item-sync / github-issues)`. Board scanned:
163 items. Conformance is GOOD — Description/Priority/Parent/Area(≤2)/Iteration all clean. Gaps found:
(1) 43 items carry non-vocabulary tags [web-portal, cross-surface, module-enhancement, future-roadmap,
reporting, resilience, etc.]; (2) 2 epics missing AC; (3) 2 non-verb titles; (4) 2 roll-up epics unclosed.
Git↔board: AB#15/4941/4942 are Platform-project cross-refs (fine); **40 commits on main have no AB#** =
untracked work to backfill.

**✅ Done + verified this session (ADO REST PATCH via platform PAT):**
- AB#5093 retitled verb-first + 3 AC (stays New, far-future). AB#5094 retitled + 3 AC (stays Resolved).
- AB#5023 → **Closed**; AB#5056 → **Closed** (roll-ups; all children delivered in v2.x). Verified by GET.
- Gaps 2/3/4 cleared. No files deleted. No commits this session (ADO-only writes).

**⏳ Remaining (next session — recipes in memory `directive-ado-100pct-accurate-2026-07-24`):**
- **W2** tag vocabulary: PR to `platform` work-items standard adding the in-use Scout product tags
  (consolidate web-interface→web-portal, far-future→future-roadmap, feature-parity→cross-surface).
- **W3** backfill: create standards-compliant ADO items for the 40 untracked commit streams (crash-
  hardening / docs migration / scaffold / Phase 0-21) — reconcile against existing resolved epics first
  to avoid duplicates.
- **W4** reconcile GitHub issues 1:1 with ADO state/labels (work-item-sync Flow 1).
- **W5** ONLY after the board is exact: decide task-list.md fate (delete or make generated). Not before.
- Open: mass Resolved→Closed for the 137 shipped items (decide in W4).

**Branch:** main (clean, no code changes). **Scripts:** scratchpad/ado-{reconcile,fullboard,conformance,wave1,verify}.ps1.

## Last session (2026-07-23, Claude Code) — backlog drive: ~72 items resolved

**Big picture:** Cleared essentially the entire *tractable* backlog in one session — every bug,
every already-built item (board reconciliation), and every small real gap. 12 commits pushed to
`main`; full Pester suite **1342 pass / 0 fail / 3 skip** throughout; analyzer 0 Errors across
`src`+`Modules`. ADO: **~72 items** moved to Resolved (or Removed) with per-item commit/file evidence.

- **5 v1 bugs (AB#335/336/337/339/340):** automation cache null-path, 0% progress bar, unassigned
  `$JobNames`, dropped `$VMQuotas`, and the echo-only CI workflow → real SPN run.
- **AB#367** tag aggregation (dedup per key) · **AB#369** module auto-update (notify-default, CI-guarded)
  · **AB#5046** `report.pbit` (wired the existing tested `New-AZSCPowerBITemplate` generator — validated
  structurally only; open in Power BI Desktop before a release depends on it) · **AB#317** test+lint CI
  pipeline (+ justified SecureString suppression in `Connect-AZSCLoginSession` so the gate is green) ·
  **AB#349** UPN/subscription auth banner.
- **AB#5068/5071/5075** collector rule depth: new `sqlDefenderPricing` / `purviewAccounts` queries +
  `iotHubs.disableLocalAuth`; flipped CAF-DB-04, CAF-ANL-02 and new CAF-IOT-06 to automated (141 rules,
  0 dup IDs). Rest stay manual with in-file ARG-absence citations.
- **AB#347** Entra "fails with Global Admin" → proven *not* a code bug (Graph delegated-scope/consent;
  degrades per-endpoint). Documented required scopes in `docs/entra-modules.md`.
- **AB#338** verified already-fixed → Resolved · **AB#321** `-WhatIf` on read-only tool → Removed.
- **Phase 0 reconciliation:** 55 already-shipped items (assessment stories, collectors/scoring, rule-depth
  categories) moved New→Resolved after spot-verifying every key artifact exists. Open items: 126 → ~54.

**Commits:** `18bf37d`, `ec7cd98`, `035ddfa`, `10fcae8`, `147d57e`, `4467355`, `b40ad7f`, `eb1b172`,
`1bd67ba` (+ this handoff). All pushed.

**What remains (needs the owner's direction — NOT bugs or unbuilt-by-omission):** the net-new **served
web-portal** vision (AB#346 + AB#373–405: HTTP listener, runspaces, vis.js topology, html2canvas/jsPDF,
browser upload/download, Spectre TUI) and major net-new integrations (Lighthouse multi-tenant AB#323/332,
cost-anomaly AB#324, IaC-gap AB#325, Fabric AB#329, ECharts AB#344, docx/pdf AB#333/334, Automation
Account AB#343). This is weeks of work and a genuine product fork — the standing task says get a go/no-go
before building the portal. A build plan + estimate is owed to the owner before starting.
**Small polish partials still open (quick next-session wins):** AB#315 phase-matrix doc, AB#318 alias doc,
AB#351 MG access probe, AB#368 cross-sub context restore; AB#386/389/396 partially overlap the React
report (do NOT close as done). Epics AB#5023/5056 close when their children are all done.

## Earlier same session (2026-07-23, Claude Code) — backlog Phase 1 detail

- **What changed and why:** Fixed the five real defects in the legacy v1 (AZSC) inventory
  path — all silent because that path has no StrictMode, so bad references degraded to
  `$null` rather than throwing.
  - **AB#335** `Start-AZTIAutProcessJob.ps1` — added missing `$DefaultPath` param and pass
    it from `Start-AZTIProcessOrchestration.ps1:38`; automation-mode batch cache writes no
    longer target a null path.
  - **AB#336** `Build-AZTICacheFiles.ps1:30` — undeclared `$ReportCounter` → `$Counter`;
    progress bar advances instead of sticking at 0%.
  - **AB#337** `Start-AZTIProcessOrchestration.ps1` — automation branch now assigns
    `$JobNames` after `Wait-Job` so the final `Build-AZSCCacheFiles` flush gets the job list.
  - **AB#339** `Start-AZTIExtractionOrchestration.ps1` — `$VMQuotas` initialised to `$null`
    up top and the premature `Remove-Variable` dropped; the `Quotas` return field is now
    populated and safe under `-SkipVMDetails`.
  - **AB#340** `.github/workflows/azure-inventory.yml` — replaced the echo-only simulation
    with a real headless run: validates SPN secrets, installs Az + AzureScout from PSGallery,
    authenticates non-interactively via `Invoke-AzureScout -TenantID/-AppId/-Secret`, runs
    the inventory, uploads reports as an artifact. Required repo secrets documented in-file.
  - Also fixed a stale test (`AzureScout.Tests.ps1` asserted version 2.0.1 → 2.1.0) and
    marked bugs #24/#25/#26/#28/#29 fixed in `docs/design/task-list.md`.
- **Commands / tests run:** full Pester suite **1325 pass / 0 fail / 3 skip** (the version
  test was the only failure and is now fixed); all 4 edited modules parse clean and pass
  PSScriptAnalyzer with **no new** findings (remaining warnings are pre-existing Write-Host/
  ShouldProcess/BOM style).
- **Branch:** main — 2 per-concern commits `18bf37d` (code) + `ec7cd98` (CI) — pushed: yes.
- **ADO:** AB#335, 336, 337, 339, 340 all New → **Resolved** with commit-evidence comments.
- **Next backlog waves (from the standing task):** Phase 0 board reconciliation (~58
  already-built items to Close — do per-item, respect the no-overreach policy); Phase 2 real
  gaps (AB#5046 report.pbit template, AB#367 tag-key aggregation, AB#369 module auto-update,
  AB#317 real test-running CI); Phase 3 collector rule depth (5068/5071/5075); Phase 4 web
  portal (~26 items, AB#373-405 — needs an architecture go/no-go before building).

## Prior session (2026-07-23, Claude Code) — v2.1.0 feature trio

- **What changed and why:** Delivered the three items that were parked as "v2.1.0 /
  blocked". (1) **AB#5041** — new native governance collector `Import-Governance`
  (`src/ingest/`) replaces the AzGovViz hard dependency: pulls policy/role/MG data
  from Azure Resource Graph + budgets/locks via ambient-token ARM REST. The ALZ
  benchmark is no longer blocked on any upstream AzGovViz fix. (2) **AB#5050** —
  `Invoke-ScoutPipeline` (`src/`), a headless one-command collect→assess→report with
  a CI-facing `pipeline-summary.json` and exit codes. (3) **AB#5053** — `Export-React`
  self-contained interactive report + `Get-ScoutDrift` cross-run drift, wired into the
  orchestrator (`-OutputFormat React`).
- **Files touched:** new `src/ingest/Import-Governance.ps1`, `src/Invoke-ScoutPipeline.ps1`,
  `src/report/renderers/Export-React.ps1`, `src/report/Get-ScoutDrift.ps1`,
  `src/report/templates/report-react.html.template`; edited `src/Invoke-ScoutAssessment.ps1`,
  `src/report/Export-Report.ps1`, `src/assess/Compare-Benchmark.ps1`,
  `src/collect/Invoke-Collect.ps1`, `manifests/assessments.psd1`, `AzureScout.psd1`;
  5 new test files; 13 docs/design files updated.
- **Commands / tests run:** full Pester suite **1325 pass / 0 fail / 3 skip**; VitePress
  `npm run docs:build` green (0 dead links). Governance collector **live-verified** via
  SPN against the HCS tenant (real ARG policy/role data, rules scored real Pass/Fail,
  benchmark guard correct). Real-orchestrator E2E produced a 220KB self-contained React
  report + drift across two runs. One integration bug found & fixed by E2E: Export-React's
  return path leaked into Invoke-ScoutAssessment's output (reporter loop now `| Out-Null`;
  regression test added).
- **Branch:** main — committed (5 per-concern commits `1379826..ee7ebfa`) — pushed: yes.
- **ADO:** AB#5041, AB#5050, AB#5053 all moved New → **Resolved** with commit evidence.
- **Blockers / open decision:** these three constitute **v2.1.0** but it is NOT yet cut or
  published. Release docs are staged as "v2.1.0 — Unreleased". Awaiting the owner's go to
  cut the version bump + tag + GitHub release + PSGallery publish (PSGallery key is in
  kv-hcs-vault-01 as `hcs-vault-azure-scout-powershellgallery-publisher-api-key`).

## Prior session (2026-07-23, Claude Code)

- **What changed and why:** Full remaining-backlog implementation pass (multi-agent).
  (1) Collector extensions in `src/collect/Invoke-Collect.ps1` + 9 rule files — 16 rules
  flipped manual→automated (AB#5057). (2) AB#5044 PPTX renderer rewritten on
  DocumentFormat.OpenXml — `build_deck.py` deleted, no Python anywhere; smoke test added.
  (3) First-ever runtime verification: 4 StrictMode engine defects fixed
  (`Resolve-JsonPath`, `Get-Score`, `Invoke-Rule`, `Invoke-ScoutAssessment`); canonical
  fixture `tests/datadump/sample-collect.json` added. (4) Live-tenant verification (HCS,
  read-only SPN via HCS Governance MCP broker): fixed ARG `-Skip 0` paging (2 files),
  `mv-expand kind=outer`, `kind` reserved keyword, AzGovViz interactive-prompt hang.
  (5) master-plan.md §8 rewritten to delivered state; §10 PPTX dependency row updated.
- **Files touched:** `src/collect/Invoke-Collect.ps1`, 9× `src/assess/rules/*.yaml`,
  `src/assess/engine/{Resolve-JsonPath,Get-Score,Invoke-Rule}.ps1`,
  `src/Invoke-ScoutAssessment.ps1`, `src/ingest/{Invoke-ArgQueryPack,Import-AzGovViz}.ps1`,
  `src/report/renderers/Export-Pptx.ps1`, `src/report/Export-Report.ps1`,
  `src/report/templates/build_deck.py` (deleted), `tests/Assessment.Engine.Tests.ps1`,
  `tests/Test-PptxFromDataDump.ps1` (new), `tests/datadump/sample-collect.json` (new),
  `.gitignore`, `docs/design/master-plan.md`, `docs/design/decisions/pptx-renderer.md`.
- **Commands / tests run and results:** Engine Pester 6/6; full suite 1263 pass / 1
  pre-existing fail (manifest author metadata: test expects `thisismydemo`, manifest says
  `Kristopher Turner` — owner decision pending) / 3 skip. Offline end-to-end: all tiers,
  all 22 manifest entries. Live end-to-end (`Invoke-ScoutAssessment -Assessment
  LandingZone -OutputFormat All`): every ARG query OK, 140 findings
  (Pass 47 / Manual 46 / Fail 45 / Unknown 2), all 5 tiers rendered incl. PPTX. Final
  sweep: 9/9 AST clean, 23 YAML / 139 rules / 0 dup IDs, Test-ModuleManifest OK.
- **Branch:** main — committed: yes (5 per-concern commits this session) — pushed: yes.
- **Blockers:** none for code. Governance/AzGovViz ingest still unexercised live (needs
  `-ManagementGroupId` + MG-root Reader + Graph read perms for the SPN).
- **Exact next steps:**
  1. Approve Platform Engineering PR #5 (tag vocabulary) in ADO — owner action.
  2. Decide manifest author mismatch (change manifest `Author` vs. fix test).
  3. Optional: designer `deck.pptx.template` to replace the programmatic slide master.
  4. Update ADO board states for items whose acceptance criteria verification now meets.
  5. Live AzGovViz/governance ingest run once MG-scope permissions are confirmed.
