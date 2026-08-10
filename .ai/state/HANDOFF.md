# Handoff

## Session 2026-08-10 — v3.10.2 tenant-first wizard correction

Immediate use of published 3.10.1 exposed three wizard defects. Access-token Az contexts put GUIDs
in `Account.Id`/`Tenant.Id`, so the wizard displayed identifiers instead of the user and tenant
name. Rejecting that context did not reliably enforce the intended fresh-login -> accessible-tenant
picker flow, and the default ARM inventory ran `Test-AZSCPermissions -Scope All`, producing a
blocking cross-tenant Graph token error before the operator opted into Entra collection.

Current working tree prepares 3.10.2:

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

Verification so far: a live read-only display/tenant-list probe resolved a real user, real tenant
name, and six tenant choices; focused wizard/login tests passed 19/19; unified entry-point tests
passed 38/38; the seven-file release/permission/wizard shard passed 153/153 with zero skips.
GitHub issue #259 and AB#7278 were reopened; AB#7278 is Active with reason Regression.

Next: run parser/PSSA/StrictMode/docs/package gates, commit/push with AB#7278, wait for GitHub CI,
tag the green commit v3.10.2, stage the exact 725-file allow-listed package, publish to PSGallery,
clean-download verify, install CurrentUser, rerun the wizard display/tenant probe, then close #259
and AB#7278 with evidence.

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
