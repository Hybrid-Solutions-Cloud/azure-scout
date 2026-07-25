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
