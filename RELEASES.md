# Releases & Builds

This document tracks every Azure Scout **build** and **release**: what shipped,
when, the version, the driving ADO work, and the linked GitHub milestone. It is
the human-readable companion to [`CHANGELOG.md`](CHANGELOG.md) (which records the
detailed change list) — this file is the at-a-glance ledger of *builds and
releases over time*.

- **Versioning:** [Semantic Versioning](https://semver.org/) — `MAJOR.MINOR.PATCH`.
- **Source of truth:** ADO Boards (`This Is My Demo — Azure Scout`) for planning;
  GitHub for intake. Commits/PRs link work with `AB#<id>`.
- **Cadence:** minor releases per completed Feature cluster; patch releases for
  fixes; builds cut from `main` after CI is green.

---

## Release status legend

| Symbol | Meaning |
|---|---|
| ✅ | Released |
| 🟡 | In progress / building |
| 🔵 | Planned |

---

## Releases

| Version | Date | Status | Theme | Driving ADO work |
|---|---|---|---|---|
| **1.0.0** | 2026-02-25 | ✅ | Fork from microsoft/ARI → AzureScout; 170+ ARM modules, 15 Entra modules, Excel/JSON/Markdown output, draw.io diagrams, category filtering, permission pre-flight | — |
| **1.1.0** | _TBD_ | 🔵 | Quality & reliability — Pester suite, CI, throttling/retry, `-WhatIf`, non-destructive cache | AB#315–#352 |
| **1.2.0** | _TBD_ | 🔵 | Collector depth — governance, networking, private-endpoint, and policy collectors | AB#353–#405 |
| **2.0.0** | 2026-07-23 | ✅ | **CAF/WAF assessment platform** — assessment engine (139 rules), ARG collect layer, AzGovViz/Advisor/ARG ingest, ALZ benchmark, tiered reporting (Power BI / HTML / OpenXML PPTX / Excel / JSON); per-domain analytics foundation. Runtime-verified offline + live tenant. | **Epic AB#5023** (AB#5024, 5027, 5031, 5034, 5044) + **Epic AB#5056** (AB#5057–5060) |
| **2.1.0** | 2026-07-23 | ✅ | **Platform hardening** — native governance collector (AB#5041), unattended pipeline (AB#5050), and React report / drift tracking (AB#5053). Full per-category rule depth (Epic AB#5056) continues in a later release | **Epic AB#5023** (AB#5041, AB#5050, AB#5053) + **Epic AB#5056** (Features AB#5061–#5075) |
| **2.2.1** | 2026-07-24 | 🟡 | **Robustness + PowerShell 7 enforcement** — repo-wide fix of the `.Count`-on-null/scalar crash class (~180 sites across `Modules/Private`, `Modules/Public` 106 files, `src/`, and the permission audit) that threw on PS 5.1 / StrictMode; manifest now requires PowerShell 7 with a clear fail-fast. Fixes the reported `Invoke-AzureScout -EntraAudit` crash | AB#347 + crash-class sweep |
| **2.4.0** | 2026-07-25 | ✅ | **One command, and a guided wizard** — inventory and assessment collapsed onto a single `Invoke-AzureScout` with an `-Assessment` switch, restoring the entry point AB#5024 specified (AB#5540); a bare `Invoke-AzureScout` now opens a guided wizard that signs you in, verifies your rights, and presents a pre-selected checklist of everything Scout can run (AB#5541); `-OutputFormat` widened to accept several renderers per run; `Invoke-ScoutAssessment` deprecated for removal in v3.0.0; corrected docs that claimed a PowerShell 5.1 floor the module never had | **Epic AB#5023** (AB#5540, AB#5541) |
| **2.8.0** | 2026-07-26 | ✅ | **Collection actually happens once** — a default assessment collect now issues **4** Azure Resource Graph queries instead of **35** (Epic **AB#5638** → **AB#5648**). v2.7.0 shipped the single-pass collection functions but **nothing called them** — outside tests the only reference to any of them was a comment — so the round-trip count was unchanged. They are now the real path. Both numbers were re-derived by counting invocations against a stub in place of `Search-AzGraph`, and both are pinned by hard count assertions in `tests/Collect.SinglePassInversion.Tests.ps1`, because a query count with no test regresses silently within a release. It is **4 rather than 1** for stated reasons: three raw tables (`resourcecontainers`, `resources`, `networkresources`) plus `sqlDefenderPricing`, which reads `SecurityResources` and genuinely cannot be served from inventory. The inventory extraction path stays at **8** because those are eight *distinct* ARG tables — `resourcecontainers`, `resources`, `networkresources`, `SupportResources`, `recoveryservicesresources`, `desktopvirtualizationresources`, `advisorresources`, retirements — not filters over one table; merging them would drop datasets. What changed there is **ownership rather than count**: one paging implementation instead of two. `Modules/Private/Extraction/Invoke-AZTIInventoryLoop.ps1` — the legacy paging, batching and retry engine — is **deleted**, with a test asserting both that the file is absent and that no AST command node anywhere in `Modules/` or `src/` still calls it. `Start-AZTIGraphExtraction` is reduced to a shim that builds no query text and issues no ARG call; its resource-group, tag and management-group filter clauses moved into `Get-ScoutRawInventory` reproducing the legacy `if`/`elseif` precedence exactly. **Fixed, and it would have shipped as a blank report section invisible to 2144 passing tests:** the raw pass omits the `tags` column unless asked, while the collect contract aggregates its top-level `tags` key from `subscriptions[*].tags` (AB#367), so the inverted path returned an **empty `tags` array for every estate**. **Trade-offs stated but not yet measured:** the raw pass carries the full `properties` bag where the typed queries carried narrow projections, so on a large estate the number of 1000-row pages can *rise* even as the query count falls; and `-Categories` no longer reduces what is **fetched**, only what is shaped. `-Source TypedQueries` is the escape hatch for a narrow single-category collect and is unchanged at 35 queries. **Not done and not claimed:** the non-ARG half — `Get-ScoutApiResources`, `Get-ScoutVmQuotas`, `Get-ScoutVmSkuDetails` and `Get-ScoutCostInventory` remain dead code, and a live run still uses the v1 implementations for ARM REST resources, VM quota/SKU lookups and Cost Management. Live-verified: **5:11**, 124 resources, 438 Excel rows, 42 worksheets, 452 security advisories, **zero leftover background jobs**. Suite **2160 / 0 / 4**. | **Epic AB#5638** → **AB#5648** |
| **2.7.0** | 2026-07-26 | ✅ | **Reporting leaves `Modules/`, Excel COM is deleted, and the first collector category becomes data** — second phase of the engine rebuild (Epic **AB#5638**). All 26 inventory report renderers moved from `Modules/Private/Reporting/` to `src/report/renderers/inventory/` and `.../style/`, each file renamed so it matches the function it defines — the legacy `AZTI`-file / `AZSC`-function mismatch is gone, with function names unchanged so no call site changed behaviour. `Build-AZTIExcelComObject.ps1` is **deleted**: chart styling runs on EPPlus/ImportExcel only through the new `Build-AZSCExcelChartStyle`. COM is why `-Lite` defaulted to true and why the module surfaced a raw `0x80040154 REGDB_E_CLASSNOTREG` on every machine and CI runner without Excel installed; no live COM call remains in `src/`, `Modules/` or `tests/`. Verified against a live tenant on a machine with no Excel: **42 worksheets, `SecurityCenter` at 489 rows**. The **13 Databases collectors are now `.psd1` data** interpreted by `Invoke-ScoutDeclarativeCollector`, each pinned by an equivalence test that compares the imperative and declarative paths key-by-key on processed rows *and* cell-by-cell on the written `.xlsx`, under both `-IncludeTags` states — which found two interpreter defects that would have silently changed shipped reports: tag columns were **appended rather than inserted** (reordering the last three columns of every tagged worksheet, since all 13 collectors add their trailing column after the tag block), and `ResourceTypes` was a **membership test rather than a grouping**. An AST audit of all 176 collectors ships as `docs/design/collector-audit.md`: of the 163 remaining, **115 are mechanically convertible, 48 must stay hand-written** (29 live cmdlet calls, 20 cross-resource joins, 10 never filter `$Resources`, 2 unimplemented). A **single-pass collection layer** landed in `src/collect/` — five functions plus a map covering 128 ARM types and 17 cognitive-services kinds, one raw pass satisfying **34 of 35** collect queries (`sqlDefenderPricing` reads `SecurityResources` and genuinely cannot be served from inventory) — but this is **capability only**: no production code calls it, so ARG round-trips are unchanged from v2.6.0 and the inversion remains **AB#5648**. **Fixed:** an unbound `[string[]]` parameter is `$null` and `@($null).Count` is **1**, not 0, so `Invoke-Collect`'s subscription-resolution branch gated on `.Count -eq 0` never fired on the default path — the subscription list was never derived from `resourcecontainers` and every later table degraded to a single un-batched tenant-wide call with none of the documented per-batch isolation; the existing test passed either way because it asserted only container count. Same `@($null).Count` class as the v2.6.0 empty-Excel-loop defect. | **Epic AB#5638** → **AB#5662**, **AB#5656**, **AB#5639**, **AB#5667** |
| **2.6.0** | 2026-07-25 | ✅ | **The engine no longer uses background jobs** — first phase of the engine rebuild (Epic **AB#5638**). Processing created one `Start-Job` per category, each creating one `[PowerShell]::Create()` runspace per collector; every defect of the v2.5.x wave lived in that coordination, not in the collectors. All 176 collectors now run **in-process in a fixed order**, so identical input produces an identical report cache — proven live: two consecutive runs, 32 collector sections, **31 byte-identical**, the one difference verified against Resource Graph as a real estate change. Each collector failure is contained individually. `Wait-AZSCJob` and the whole job machinery are **deleted**. **Fixed, all pre-existing:** the **Security Center worksheet had been empty in every release that had one** (an undeclared parameter silently became `$null` across the job boundary — PowerShell routes unknown named arguments to `$args` rather than rejecting them); five collectors threw on their first `Write-AZSCLog -Color` call; per-file `.CATEGORY` filtering had never matched a single file; the Excel loop invoked every collector regardless of data because `@($null).Count` is 1; and all four exporters read the cache unguarded. | **Epic AB#5638** → **AB#5649** (AB#5650–5655) |
| **2.5.3** | 2026-07-25 | ✅ | **Empty is not null** — a full inventory run aborted with `The property 'ReservationRecomen' cannot be found on this object`. Under StrictMode, member enumeration over a collection reports a property missing when the enumeration yields nothing at all, and an **empty collection** on every element produces exactly that. Azure returns `{ "value": [] }` for a subscription with no reservation recommendations, so a healthy tenant crashed the run — data-dependent, which is why 1697 tests and three live runs missed it. Swept the same class out of the VM quota and SKU collectors, fixed a diagram job wait that had never waited (the `.Runspace` no-op v2.5.2 fixed in only one of two copies), and stopped an unavailable Cost Management API destroying the whole report. **Added: a per-run diagnostic log** — `scout-run.log` and `scout-console.log` in every run folder, with the full error record and script stack trace on failure. | **AB#5633**, **AB#5636** (Feature AB#5414) + **AB#5634/AB#5635** |
| **2.5.2** | 2026-07-25 | ✅ | **Determinism** — a job-wait race let a still-`NotStarted` job be harvested and destroyed before it ran, silently dropping an entire category from the report (`Compute.json` 5,158 bytes on one run, 470 on the next). The wait loop and batch filter now treat every non-terminal state as pending; a dropped category warns instead of vanishing; a machine without Excel gets a plain explanation rather than a raw COM error. Verified by three byte-identical consecutive live runs. | **AB#5629** (Feature AB#5414) |
| **2.5.1** | 2026-07-25 | ✅ | **Live-run hardening** — seven defects that stopped a full `Invoke-AzureScout` run from completing against a real tenant: an uninitialised extraction variable, 41 `.IsPresent` reads on untyped parameters, Excel styling/tables over empty worksheets, VM property names the Compute collector never emitted, 29 unguarded worksheet dereferences, 10 pivot titles read before assignment, and a Markdown interpolation bug. First live-tenant verification of the `-IncludeDevOps` collectors (166 resources across 74 projects). | **AB#5547**, **AB#5567** (Feature AB#5414) |
| **2.5.0** | 2026-07-25 | ✅ | **One collection pass** — a combined inventory + assessment run now queries Azure once instead of twice. The assessment shapes its scalars from the rows the inventory pass already fetched (`ConvertFrom-ScoutInventory`, `-FromInventory` on `Invoke-Collect`/`Invoke-ScoutAssessment`) rather than issuing its own Resource Graph pack; only the Defender for SQL pricing lookup still reaches Resource Graph, because it reads a table the inventory does not collect. Assessment-only runs are unchanged and the KQL remains the reference implementation. | **Epic AB#5545** (AB#5543) |
| **2.3.0** | 2026-07-25 | 🟡 | **Collection hardening + external platform integrations** — run isolation so a rescan never destroys the previous run (AB#331); cross-subscription context restore (AB#368); post-login management group probe (AB#351); Azure DevOps inventory with the service-connection-to-subscription cross-reference (AB#327); a composite GitHub Action (AB#328); the Automation Account guide that never existed plus two runbook upload fixes (AB#343); category reference and validation matrix docs (AB#318, AB#5417, AB#315) | **Epic AB#5411** (AB#315, 331, 351, 368, 5417→318) + **Epic AB#5410** (AB#327, 328, 343) |
| **2.2.0** | 2026-07-24 | ✅ | **Report tiers, deeper analytics, hardened collectors** — Word/ECharts/PDF/JSON-evidence report tiers, Excel visual dashboards, richer React report visuals + `report.pbit`, cost anomaly + IaC gap + resource-drift analysis, IoT deep coverage, tag aggregation, collector/pipeline resilience, assessment config load/save, CI pipeline, five v1 bug fixes | AB#322, 324–326, 330, 333, 344, 349, 367, 369, 373–375, 379, 394–402, 405, 5046, 5068, 5071, 5075 + AB#335–340, 342, 347 |

> **2.0.0 is a major bump** because the reporting overhaul demotes Excel-first
> output to an evidence tier and introduces the `findings.json` contract — a
> breaking change to the output surface.

---

## 2.2.0 — 2026-07-24

Delivered on `main` in the current development line (not yet tagged or published):

- **New report tiers** — `Export-Word` (`.docx` via OpenXML, AB#333), `Export-EChartsDashboard` (offline ECharts HTML, AB#344), `Export-Pdf` (dependency-free, AB#379/394/395), and `Export-JsonEvidence` (resources-only JSON evidence, AB#396) — all wired into `Export-Report` and `-OutputFormat` on `Invoke-ScoutAssessment`/`Invoke-ScoutPipeline`.
- **Excel visual dashboard tabs** (AB#322) — pivot-chart dashboards in the assessment Excel evidence tier.
- **Richer React report + `report.pbit`** (AB#376–378, 380, 386, 387, 389–393, 5046) — topology diagram, MG hierarchy, 14 KPI cards, Governance section, drill-downs, search/filter, badges, tooltips; Power BI tier now also emits a `.pbit` bound to the star-schema CSVs.
- **New offline analysis** — `Get-ScoutInventoryDrift` (cross-run resource drift, AB#326), `Get-ScoutCostAnomaly` (cost outlier detection, AB#324), `Get-ScoutIacGap` (Bicep/ARM-JSON coverage gaps, AB#325). None call Azure.
- **Collect layer depth** — IoT deep coverage (DPS + Digital Twins, AB#330), tag-value aggregation (AB#367), deeper Database/Analytics/IoT rule automation (AB#5068/5071/5075), and collector/pipeline resilience + live progress (AB#397–402, 405).
- **Assessment config load/save** — `Import-ScoutConfig` / `Export-ScoutConfig` (AB#373–375).
- **Platform** — CI pipeline (AB#317), a real (non-simulated) `azure-inventory` workflow (AB#340), UPN/subscription auth banner (AB#349), five v1 inventory bug fixes (AB#335–340), draw.io merge/StrictMode repairs (AB#342), documented Entra Graph delegated scopes (AB#347/338).

Full detail: [`CHANGELOG.md` § 2.2.0](CHANGELOG.md#220---2026-07-24).

---

## 2.1.0 — 2026-07-23

Delivered on `main`, tagged and released:

- **Native governance collector** (`src/ingest/Import-Governance.ps1`, AB#5041) — replaces the AzGovViz hard dependency as the default governance collector. Populates `collect.json`'s `governance` object natively from Azure Resource Graph (policy assignments, role assignments, management groups) plus ambient-token ARM REST (budgets, locks). Needs only Reader at the management-group root — no cloned repo, no `AzAPICall` install prompt, fully unattended. `AzGovViz` remains available as an opt-in `Ingest` value. Live-verified against the HCS tenant.
- **Unattended pipeline** (`Invoke-ScoutPipeline`, AB#5050) — one command runs collect → assess → report headless into a single dated run folder, fully non-interactive, with a read-only permission pre-flight and a `PartialSuccess` degrade path on exporter failure. Writes `pipeline-summary.json` / `.md`.
- **React report + cross-run drift** (`Export-React`, `Get-ScoutDrift`, AB#5053) — a new self-contained `report-react.html` (`-OutputFormat React`) with client-side filter/sort/search and a Drift tab, plus cross-run drift computation (New / Resolved / Regressed / Unchanged, weighted score delta) tracked in an append-only `.scout-history/findings-history.json`.

Still open for 2.1.0 when it was cut: full per-category rule depth (Epic AB#5056, Features AB#5061–#5075) — continues to track under Epic AB#5056.

---

## Builds

Builds are cut from `main` once CI passes. Record each build here as it is produced.

| Build | Commit | Date | From version | Artifacts | Notes |
|---|---|---|---|---|---|
| v2.0.0 | `0518c7a` | 2026-07-23 | 2.0.0 | `AzureScout` module (PSGallery), GitHub release `v2.0.0` | First assessment-platform release. Verified offline (Pester) + against a live tenant (140 findings, all report tiers). |
| v2.1.0 | `a189b9e` | 2026-07-23 | 2.1.0 | `AzureScout` module (PSGallery), GitHub release `v2.1.0` | Platform hardening — native governance, unattended pipeline, React report + drift. |

---

## How a release is cut

1. All Features in the target release's ADO cluster reach **Done** (acceptance criteria verified).
2. `CHANGELOG.md` `[Unreleased]` section is finalized and dated under the new version heading.
3. `ModuleVersion` bumped in `AzureScout.psd1`.
4. CI (Pester + `mkdocs build --strict`) is green on `main`.
5. Tag `vX.Y.Z`, cut the build, add a row to **Builds** above, and flip the release row to ✅.
6. GitHub release notes generated from the `CHANGELOG.md` section; ADO Features linked via `AB#<id>`.
