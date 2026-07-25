# Handoff

<!--
  Written at the END of every session by whichever tool was used.
  This is the single most important cross-tool file — the next session
  (possibly a different tool) starts by reading it.
-->

## Last session (2026-07-25, Claude Code) — v2.4.0 SHIPPED: one command, guided wizard, docs collapsed

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
