---
description: Planned features, future enhancements, and the long-term vision for AzureScout.
---

# Roadmap

*See everything. Own your cloud.*

This page outlines what's planned, what's in progress, and what's been delivered.
Community contributions are welcome — see [Contributing](contributing.md) to get involved.

> The consolidated architecture, work-item index, audit findings, and delivery
> plan live in the [Master Design & Plan](design/master-plan.md). This roadmap is
> the public-facing summary of it.

## Current Release — v2.5.0 — One Collection Pass

Released 25 July 2026, published to the PowerShell Gallery.

A combined inventory + assessment run now queries Azure **once** (AB#5543). The inventory pass
already projects the full property bag for every resource, so the assessment shapes its scores
from those rows rather than re-issuing its own Resource Graph pack over the same resource types.
One query still goes to Azure in a combined run — the Defender for SQL pricing lookup, which
reads a table the inventory does not collect. The assessment-only path is unchanged.

Full detail: [CHANGELOG.md § 2.5.0](https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md#250---2026-07-25).

## Previous Release — v2.4.0 — One Command, and a Guided Wizard

Released 25 July 2026, published to the PowerShell Gallery.

| Capability | What shipped |
|---|---|
| One entry point | Inventory and assessment are modes of a single `Invoke-AzureScout`, not two cmdlets. `-Assessment` selects the CAF/WAF assessment; `-CollectOnly` and `-FromCollect` moved across too. Assessment mode now honours the inventory sign-in parameters, which the standalone cmdlet never did (AB#5540) |
| Guided wizard | A bare `Invoke-AzureScout` in an interactive session signs you in, lets you pick the tenant, verifies your rights, then offers pre-selected checklists for run type, categories/assessments, formats, and report directory — and prints the equivalent one-liner. Never fires in CI; `-NoWizard` opts out (AB#5541) |
| Output formats | `-OutputFormat` accepts several renderers in one run and spans both modes; a wrong-mode format now throws an error naming the switch you wanted |
| Deprecation | `Invoke-ScoutAssessment` still works but will be removed in v3.0.0 |
| Documentation | Corrected pages claiming a PowerShell 5.1 floor the module never had, and collapsed the "Inventory vs Assessment" framing across the site |

Full detail: [CHANGELOG.md § 2.4.0](https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md#240---2026-07-25).

::: tip Resolved in v2.5.0
The duplicate collection pass described here was collapsed in v2.5.0 (AB#5543) — a combined run
now collects from Azure once.
:::

## v2.3.0 — Collection Hardening & External Platform Integrations

Released 25 July 2026, published to the PowerShell Gallery. Closes the collection-hardening
epic and the external-platform integrations.

| Capability | What shipped |
|---|---|
| Run isolation | Every invocation writes to its own run folder, so a rescan — or a scan of a second tenant — can no longer destroy the previous run's cache or report. `-RunName`, `-Force`, `Clear-AZSCCacheFolder -OlderThan <days>` (AB#331) |
| Azure DevOps inventory | `-IncludeDevOps` adds projects, pipelines, service connections, repositories, and agent pools. The service-connection sheet cross-references each ARM connection against the subscriptions in scope (AB#327) |
| Unattended execution | Composite GitHub Action at the repository root (AB#328); the eight-step [Azure Automation Account](automation.md) guide plus two runbook upload fixes (AB#343) |
| Reliability | Subscription context restored in a `finally` at all five `Set-AzContext` sites (AB#368); post-login management group access probe naming the role to assign (AB#351) |
| Documentation | [Category Reference](category-reference.md) (AB#318/5417) and [Validation Matrix](validation-matrix.md) (AB#315) |

Full detail: [CHANGELOG.md § 2.3.0](https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md#230---2026-07-25).

## v2.2.0 — Report Tiers, Deeper Analytics, Hardened Collectors

Four new report tiers, richer visuals on the existing ones, three new offline analysis
functions, deeper collector coverage, and a round of platform hardening on top of v2.1.0.

| Capability | What shipped |
|---|---|
| Report tiers | `Word` (`.docx` via OpenXML, AB#333), `EChartsDashboard` (offline ECharts HTML, AB#344), `Pdf` (dependency-free, AB#379/394/395), `JsonEvidence` (resources-only, AB#396) — all on `Export-Report` / `-OutputFormat` |
| Reporting depth | Excel visual dashboard tabs with pivot charts (AB#322); richer React report — topology diagram, MG hierarchy, 14 KPI cards, Governance section, drill-downs, search/filter, badges, tooltips (AB#376–378, 380, 386, 387, 389–393); `report.pbit` generation (AB#5046) |
| New analysis | `Get-ScoutInventoryDrift` (cross-run resource drift, AB#326), `Get-ScoutCostAnomaly` (cost outliers, AB#324), `Get-ScoutIacGap` (Bicep/IaC coverage gaps, AB#325) — all offline, never call Azure |
| Collect layer | IoT deep coverage — DPS + Digital Twins (AB#330); tag-value aggregation (AB#367); deeper Database/Analytics/IoT rule automation (AB#5068/5071/5075); per-subscription collector/pipeline resilience + live progress (AB#397–402, 405) |
| Config | `Import-ScoutConfig` / `Export-ScoutConfig` (AB#373–375) — save/reload a benchmark + rule-selection + threshold-override config as JSON, with a safe fallback to the built-in default |
| Platform | CI pipeline (AB#317); a real, non-simulated `azure-inventory` workflow (AB#340); module auto-update check (AB#369); login auth banner (AB#349); five v1 inventory bug fixes (AB#335–340); draw.io merge/StrictMode repairs (AB#342); documented Entra Graph delegated scopes (AB#347/338) |

Full detail: [CHANGELOG.md § 2.2.0](https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md#220---2026-07-24).

## v2.1.0 — Platform Hardening

Released 23 July 2026. Native governance collector (AB#5041), unattended
one-command pipeline (AB#5050), and the React report variant + cross-run
drift tracking (AB#5053). See the
[v2.1.0 section](#major-—-v2-1-0-—-platform-hardening-epic-ab-5023-carryover-—-released-2026-07-23)
below for the full breakdown.

## v2.0.0 — CAF/WAF Assessment Platform

Released 23 July 2026. Turns AzureScout from an inventory tool into a read-only
CAF/WAF landing-zone assessment. Runtime-verified offline (Pester) and against a
live Azure tenant.

| Capability | What shipped |
|---|---|
| Assessment engine | Declarative YAML rules (JSONPath + assert types), dual CAF/WAF scoring, prioritized gap list — **139 rules across 8 CAF design areas + 5 WAF pillars** |
| Collect + ingest | Read-only ARG collect layer (`collect.json`); native governance collector (v2.1.0) / ARG query pack / Advisor ingest — AzGovViz retained as opt-in only |
| ALZ benchmark | Live tenant diffed against a canonical ALZ reference |
| Tiered reporting | Power BI, self-contained HTML, executive **PowerPoint (OpenXML SDK — no Python)**, Excel + JSON evidence |
| Per-domain analytics | Every discovery category runnable + tagged: `Invoke-AzureScout -Assessment <Category>` |
| Entry point | `Invoke-AzureScout -Assessment` (run one/some/all), read-only permission pre-flight |

> **Breaking:** introduces the `findings.json` contract and demotes Excel-first
> output to an evidence tier. Assessment features require PowerShell 7.

Deferred to v2.1.0: full per-category rule depth (AB#5061–5075). The native
governance collector (AB#5041), the fully unattended pipeline (AB#5050), and
the React report variant + cross-run drift tracking (AB#5053) shipped in
v2.1.0; four new report tiers, deeper analysis functions, and collector
hardening shipped in v2.2.0 above.

## Previous Release — v1.0.0

Released February 2026.

| Area | What's included |
|------|-----------------|
| Excel Reports | 171 worksheets (154 ARM + 17 Entra ID) covering all 15 Azure resource categories |
| Category Filtering | `-Category` parameter to scope runs to specific resource types |
| AI / ML Coverage | 27 modules: OpenAI, AI Foundry, Azure ML, Cognitive Services, Bot Services, Search |
| AVD Coverage | 6 modules: Host Pools, App Groups, Workspaces, Session Hosts, Scaling Plans, Applications |
| Arc Coverage | Sites, SQL Servers, Data Controllers, SQL Managed Instances, Arc-enabled Kubernetes enhancements |
| VM & Arc Enrichment | Backup status, Site Recovery, Update Manager, Advisor score, Monitor metrics, Cost estimates |
| Monitor Coverage | 24 modules: Diagnostic settings, alert rules, DCRs, App Insights deep data, autoscale, workbooks |
| Markdown / AsciiDoc Export | `-OutputFormat Markdown\|AsciiDoc` generates portable reports alongside Excel/JSON |
| Permission Audit | `Invoke-AZSCPermissionAudit` with ARM + Graph checks, color output, Markdown/AsciiDoc export |
| Subscription & MG Completeness | Captures ALL subscriptions (including empty/disabled) and full MG hierarchy |
| Module Naming | Renamed from *AzureTenantInventory* to *AzureScout* (prefix: `AZSC`) |

## Near-term — v1.1.0

Focus: quality, reliability, and community onboarding.

| Feature | Description | Status |
|---------|-------------|--------|
| Pester test suite | Full unit + integration tests for all public functions and key private functions | :white_check_mark: Done — 1,648 tests across 56 files, run offline |
| PSGallery publish | Publish `AzureScout` module to PowerShell Gallery | :white_check_mark: Done (v2.0.0) |
| GitHub Actions CI | Run Pester tests on PR + push; block merge on failure | :white_check_mark: Done — `ci.yml` runs Pester + PSScriptAnalyzer on every push and PR |
| Category alias documentation | Comprehensive table of all accepted `-Category` aliases and their canonical names | :white_check_mark: Done (v2.3.0, AB#318/AB#5417) — see [Category Reference](category-reference.md) |
| Resource provider pre-flight | Warn before scan when required providers are not registered in a subscription | :white_check_mark: Done — `-CheckResourceProviders` |
| Throttling / retry improvements | Exponential backoff on 429 responses, honouring `Retry-After`, plus 5xx retry | :white_check_mark: Done — `Invoke-AZSCGraphRequest` (`-MaxRetries`, default 5) |
| `Invoke-AzureScout -WhatIf` | Show which modules would run without actually executing | :x: Won't do (AB#321) — Azure Scout is read-only, so `-WhatIf` has no state change to preview |
| Non-destructive cache | Prevent `ReportCache` and `DiagramCache` from being overwritten on subsequent runs. Each invocation writes to a timestamped (or `-RunName` named) subfolder. Previous scan data is never lost unless `-Force` is specified. `Clear-AZSCCacheFolder -OlderThan <days>` for cleanup. | :white_check_mark: Done (v2.3.0, AB#331) |
| Cross-subscription context restore | Restore the caller's subscription context after every per-subscription loop, including on error | :white_check_mark: Done (v2.3.0, AB#368) |
| Management group access probe | Report management group visibility at login and name the role to assign when it is missing | :white_check_mark: Done (v2.3.0, AB#351) |

### Visual Dashboard Tabs (DarkBlue "overview-style" worksheets)

Phase 10 added raw data tabs (Cost Management, Security Overview, Azure Update Manager, Azure Monitor) that collect data into flat tables. The next step is to add **visual dashboard tabs** — styled like the Overview sheet (DarkBlue tab color, EPPlus shapes, pivot charts) — that summarize and visualize the data from those raw tabs.

| Dashboard | Charts / Visualizations | Status |
|-----------|-------------------------|--------|
| Cost Dashboard | Cost by Resource Type (bar), Cost by Subscription (pie), Cost by Region (column), Cost by SKU (bar) | :blue_circle: Planned |
| Security Dashboard | Assessments by Severity (pie), Findings by Subscription (bar), Defender Plans (column), Active Alerts by Severity (bar) | :blue_circle: Planned |
| Update Manager Dashboard | Machines by Platform (pie), Machines by OS Type (pie), Machines by Region (column), Machines by Power State (bar), Machines by Subscription (bar) | :blue_circle: Planned |
| Monitor Dashboard | Alert Rules by Subscription (bar), Action Groups by Subscription (pie), DCRs by Subscription (column), App Insights by Subscription (bar) | :blue_circle: Planned |

Each dashboard tab will:

- Use DarkBlue tab color (matching Overview, Subscriptions, Advisor)
- Be pinned after the Overview sheet group via `MoveAfter` in the ordering function
- Contain EPPlus pivot tables + charts generated by `Build-AZSCDashboardTabs`
- Only appear when the corresponding raw data tab has data (no empty dashboards)

## Medium-term — v1.2.0

Focus: depth, breadth, and multi-tenant scenarios.

| Feature | Description | Status |
|---------|-------------|--------|
| Multi-tenant scanning (Lighthouse) | `-TenantID` accepts multiple tenant IDs. Authenticates to each tenant sequentially, runs the full extraction → processing → reporting pipeline per tenant. Supports combined workbook (with Tenant column) or separate per-tenant workbooks via `-MergeOutput` switch. Auth failure on one tenant does not block others. The run-isolation prerequisite shipped in v2.3.0 (AB#331). | :bulb: Idea (AB#323) |
| Word document export (#22) | Shipped as `-OutputFormat Word` on `Invoke-ScoutAssessment` (v2.2.0): `Export-Word` generates a self-contained `.docx` via OpenXML, no Python. | :white_check_mark: Done (v2.2.0, AB#333) |
| PDF report export (#23) | Shipped as `-OutputFormat Pdf` on `Invoke-ScoutAssessment` (v2.2.0): `Export-Pdf` is a hand-rolled, dependency-free renderer (cover, executive summary, per-area findings table, gaps, manual review). | :white_check_mark: Done (v2.2.0, AB#379/394/395) |
| Cost anomaly detection | Shipped as the offline `Get-ScoutCostAnomaly` function (v2.2.0) — flags statistical outliers (spike/z-score/IQR) in an already-collected cost dataset; never calls Azure. | :white_check_mark: Done (v2.2.0, AB#324) |
| Bicep / IaC gap detection | Shipped as the offline `Get-ScoutIacGap` function (v2.2.0) — compares discovered resources against a folder of Bicep/ARM-JSON templates and flags unmanaged resources; never calls Azure. | :white_check_mark: Done (v2.2.0, AB#325) |
| Resource drift reporting | Shipped as the offline `Get-ScoutInventoryDrift` function (v2.2.0) — compares the current `collect.json` against the previous run's snapshot and reports Added/Removed/Changed resources. | :white_check_mark: Done (v2.2.0, AB#326) |
| Azure DevOps integration | Shipped as `-IncludeDevOps` (v2.3.0) — inventories projects, pipelines, service connections, repositories, and agent pools across one or more organizations, adding five worksheets. Authentication reuses the current Azure sign-in; `-DevOpsPat` covers a separate identity. The ADO Service Connections sheet cross-references each ARM connection against the subscriptions in scope. | :white_check_mark: Done (v2.3.0, AB#327) |
| GitHub Actions module | Shipped as a composite `action.yml` at the repository root (v2.3.0) — `uses: thisismydemo/azure-scout@v2` installs the module, authenticates, collects, and uploads reports as an artifact. | :white_check_mark: Done (v2.3.0, AB#328) |
| Azure Automation Account | Shipped as first-class unattended execution (v2.3.0) — the eight-step setup guide now exists, plus fixes for the blob-upload collision on a second scheduled run and the diagnostic log that never uploaded. | :white_check_mark: Done (v2.3.0, AB#343) |
| Fabric / Power BI export (#17) | `-OutputFormat PowerBI` generates a flat normalized CSV bundle (`PowerBI/` folder) with `_metadata.csv`, `Subscriptions.csv`, per-module `Resources_*.csv` and `Entra_*.csv` files, and a `_relationships.json` star-schema manifest for Power BI Desktop / Microsoft Fabric | :white_check_mark: Done |
| IoT deep coverage | Shipped in the assessment Collect layer (v2.2.0) — `Invoke-Collect` gains Device Provisioning Service and Azure Digital Twins queries; new `caf.iot` rules score them. | :white_check_mark: Done (v2.2.0, AB#330) |

## Major — v2.0.0 — CAF/WAF Assessment Platform (Epic AB#5023) — Delivered

Turned inventory into a **scored CAF/WAF landing-zone assessment**. Collection stays as-is; a three-layer, JSON-on-disk architecture (`collect.json` → `findings.json` → deliverables) adds assessment and rebuilds reporting. Read-only throughout. **Shipped in v2.0.0 (2026-07-23).**

| Capability | Description | Status |
|---|---|---|
| Assessment engine | Declarative YAML rules (JSONPath + assert types), dual CAF/WAF scoring, prioritized gap list | :white_check_mark: Done (AB#5027, AB#5034) |
| CAF/WAF rule content | 8 CAF design areas + 5 WAF pillars — 139 rules across 23 version-controlled files | :white_check_mark: Done (AB#5031, AB#5057) |
| Ingest layer | Fold an ARG query pack and Advisor into one `collect.json`; governance now ingested natively by default (see v2.1.0 below) — Azure Governance Visualizer remains available as an opt-in ingestor | :white_check_mark: Done (AB#5037) |
| ALZ benchmark diff | Compare the live tenant against a canonical ALZ reference (MG archetypes, required policies) | :white_check_mark: Done — engine + native governance collection, no upstream AzGovViz dependency (AB#5041, v2.1.0) |
| Tiered reporting | Power BI (primary), self-contained HTML, executive PPTX (OpenXML SDK); Excel/JSON retained as evidence | :white_check_mark: Done (AB#5044) |
| Module registry + entry point | `-Assessment` run one/some/all; read-only permission pre-flight | :white_check_mark: Done (AB#5024); unattended one-command pipeline :white_check_mark: Done (AB#5050, v2.1.0) |
| React report + drift tracking | Richer React report variant and cross-run score-drift tracking | :white_check_mark: Done (AB#5053, v2.1.0) |

## Major — v2.1.0 — Platform Hardening (Epic AB#5023 carryover) — Released 2026-07-23

Three more Epic AB#5023 capabilities shipped ahead of the full per-domain
analytics epic below. Tagged and released as `v2.1.0` — see
[`RELEASES.md`](https://github.com/thisismydemo/azure-scout/blob/main/RELEASES.md)
for the build ledger.

| Capability | Description | Status |
|---|---|---|
| Native governance collector | `Import-Governance` replaces the AzGovViz hard dependency as the **default** governance collector — populates `collect.json`'s `governance` object natively from Azure Resource Graph and ambient-token ARM REST, needing only Reader at the management-group root. No cloned repo, no `AzAPICall` install prompt, fully unattended, StrictMode-safe. Live-verified against the HCS tenant. `AzGovViz` remains available as an opt-in `Ingest` value; nothing depends on it by default anymore. | :white_check_mark: Done (AB#5041) |
| Unattended pipeline | `Invoke-ScoutPipeline` runs collect → assess → report headless into one dated run folder — non-interactive throughout, runs the read-only permission pre-flight first, and degrades to `PartialSuccess` (rather than losing output) if an exporter fails. Writes `pipeline-summary.json`/`.md`. | :white_check_mark: Done (AB#5050) |
| React report + cross-run drift | `-OutputFormat React` renders a single self-contained `report-react.html` (client-side filter/sort/search, summary dashboard, Drift tab). `Get-ScoutDrift` computes cross-run New / Resolved / Regressed / Unchanged findings plus a weighted score delta, tracked in an append-only `.scout-history/findings-history.json`. | :white_check_mark: Done (AB#5053) |

Not included in v2.1.0: full per-category rule depth (AB#5061–5075) — tracked
below. Four new report tiers, richer report visuals, and three new offline
analysis functions shipped in v2.2.0 next.

## Major — v2.2.0 — Report Tiers, Deeper Analytics, Hardened Collectors

Delivered on `main` — not yet tagged/published, see
[`RELEASES.md`](https://github.com/thisismydemo/azure-scout/blob/main/RELEASES.md)
for cut status.

| Capability | Description | Status |
|---|---|---|
| Report tiers — Word/ECharts/PDF/JSON evidence | `Export-Word` (`.docx` via OpenXML), `Export-EChartsDashboard` (offline ECharts HTML, no CDN), `Export-Pdf` (hand-rolled, dependency-free), `Export-JsonEvidence` (resources-only JSON, no assessment metadata/scores). All wired into `Export-Report` and `-OutputFormat` on `Invoke-ScoutAssessment`/`Invoke-ScoutPipeline`. | :white_check_mark: Done (AB#333, AB#344, AB#396, AB#379/394/395) |
| Excel visual dashboard tabs | Native ImportExcel PivotTable/PivotChart dashboard sheets in the assessment Excel evidence tier: Findings-by-Severity (pie), Score-by-Area (column), Pass-Fail-Manual (stacked column), Resource-Counts (bar) — omitted when a sheet's data is empty. | :white_check_mark: Done (AB#322) |
| Richer React report + `report.pbit` | The self-contained `report-react.html` gains a vis.js VNet topology diagram, an MG-hierarchy diagram, 14 KPI cards, an Azure Firewall drill-down, a Governance section (budgets/locks/tag chips), a policy-enforcement badge, per-section search/filter, clickable rows with a side panel, and scope tooltips. The Power BI tier also generates a `report.pbit` bound to the star-schema CSVs. | :white_check_mark: Done (AB#376–378, 380, 386, 387, 389–393, AB#5046) |
| Cross-run resource drift | `Get-ScoutInventoryDrift` — offline, compares the current `collect.json` against the previous run and reports Added/Removed/Changed resources, complementing the existing findings-level `Get-ScoutDrift` (v2.1.0). | :white_check_mark: Done (AB#326) |
| Cost anomaly detection | `Get-ScoutCostAnomaly` — offline, flags statistical outliers (month-over-month spike, z-score, IQR) in an already-collected cost dataset. | :white_check_mark: Done (AB#324) |
| Bicep / IaC gap detection | `Get-ScoutIacGap` — offline, compares discovered resources against a folder of Bicep/ARM-JSON templates (best-effort text/JSON parsing) and flags resources not represented in any template. | :white_check_mark: Done (AB#325) |
| IoT deep coverage | `Invoke-Collect` gains Device Provisioning Service and Azure Digital Twins queries; new `caf.iot` rules score them. | :white_check_mark: Done (AB#330) |
| Tag aggregation | `Invoke-Collect` aggregates tag values to their unique set per key across subscriptions instead of last-write-wins. | :white_check_mark: Done (AB#367) |
| Database/Analytics/IoT rule depth | New `sqlDefenderPricing`/`purviewAccounts` collect queries plus `iotHubs.disableLocalAuth`; CAF-DB-04, CAF-ANL-02, and new CAF-IOT-06 flip from `Manual` to automated. | :white_check_mark: Done (AB#5068, AB#5071, AB#5075) |
| Collector/pipeline resilience + progress | Per-subscription try/catch/continue in `Invoke-Collect`; a management-group role-requirement hint on RP/authorization errors; an empty-data guard; a pipeline `HadErrors` summary flag; live `Write-ScoutProgress` output during collection. | :white_check_mark: Done (AB#397–402, AB#405) |
| Assessment config load/save | `Import-ScoutConfig` / `Export-ScoutConfig` — load/save an alternative benchmark, rule-selection patterns, and per-rule threshold overrides as JSON; never throws on a bad file (falls back to the built-in default with a warning). | :white_check_mark: Done (AB#373–375) |
| Platform hardening | CI pipeline (`ci.yml`); a real, non-simulated `azure-inventory` workflow; module auto-update check on import; UPN/subscription auth banner; five v1 inventory bug fixes; draw.io merge/StrictMode repairs; documented Entra Graph delegated scopes. | :white_check_mark: Done (AB#317, AB#340, AB#369, AB#349, AB#335–340, AB#342, AB#347/338) |

Not yet included: full per-category rule depth (AB#5061–5075) — tracked below
under Epic AB#5056.

## Major — v2.1.0 — Per-Domain CAF/WAF Analytics (Epic AB#5056)

Focus: extend CAF/WAF analytics to **every** Scout category, not just the landing-zone roll-up. Each of the 15 discovery categories becomes an **independently runnable, categorized and tagged assessment** — so you can run and score *just* Governance, *just* Monitoring, *just* Update Manager, etc.

| Capability | Description | Status |
|---|---|---|
| Assessment taxonomy & tagging | Manifest gains `Category` / `Frameworks` / `Tags`; `-Assessment <Category>` runs scoped discovery + scoped scoring; sub-bundles (Governance/Policy/UpdateManager under Management, Monitoring under Monitor) | :blue_circle: Planned (AB#5057) |
| Per-category coverage | CAF/WAF rule coverage authored for each category — Management, Monitor, Networking, Identity, Security, Compute, Storage, Databases, Containers, Web, Analytics, AI, Integration, Hybrid, IoT | :blue_circle: Planned (AB#5061–AB#5075) |
| Registry document | A table of every possible assessment: category, sub-bundles, CAF areas, WAF pillars, tags | :blue_circle: Planned (AB#5057) |

See [`RELEASES.md`](https://github.com/thisismydemo/azure-scout/blob/main/RELEASES.md) for the build/release ledger.

## Far-future — Web version of Azure Scout (Epic AB#5093)

> A **web-UI version with the same capabilities as the PowerShell version** — same engine,
> browser instead of terminal. **Far-future, not scheduled.** Only the web-only plumbing
> (server, runspace, progress polling, launchers) is unique to it. The actual product features
> are **buildable in the PowerShell version now** (Epic AB#5094) and the web version inherits them.


> **Status: under evaluation — NOT committed.** This is a possible future direction, not
> planned work, and it would be a **departure from the current "no portals" stance** in the
> [Long-term Vision](#long-term-vision) below. Captured here so the direction is tracked and
> can be decided deliberately rather than drifting into the backlog.

A **served web-application** as a **second delivery surface** for the same engine — not a
different product. It would run a local HTTP listener with a browser UI (background-runspace
collection with live progress, interactive vis.js topology, in-browser PDF export, config
upload/download). **The web portal must reach FEATURE PARITY with the PowerShell version** —
every product feature is available through both surfaces; neither has a feature the other
lacks. Only the *delivery plumbing* below is web-specific. It is weeks of net-new engineering
(web server + JS front-end + IPC layer).

**Web delivery surface — plumbing only (Epic AB#5093, exploratory):**

| Area | Web-surface plumbing (no PowerShell equivalent) | Status |
|---|---|---|
| Server core | HTTP listener + background runspace, file-based progress IPC (client polls), named stages %, concurrent-collection guard, cached-inventory serving, runspace disposal, double-poll guard | :bulb: Exploratory (AB#381–385, 403, 404) |
| Launchers | `start.cmd` / `start.sh` to launch the server | :bulb: Exploratory (AB#388) |

### Feature parity — shared across both surfaces (Epic AB#5094)

The product **features** below are **not web-only or PowerShell-only — they belong to both
surfaces**. They live in the core product and are surfaced through the PowerShell module (CLI +
static/React reports) *and* the web portal. Same capability, per-surface delivery:

- **Report visuals** (in the React/HTML report today, and the web portal later): vis.js VNet
  topology + click-to-details + reset/fit controls, MG-hierarchy diagram, per-section
  search/filter, clickable rows + side panel, 14 KPI cards, Azure Firewall drill-down,
  Governance section (budgets/locks/tag chips), policy-enforcement badge, scope tooltips,
  resources-only JSON evidence export (AB#376–378, 380, 386, 387, 389–393, 396). *Several
  partially exist in the React report already — extend them.*
- **WAF config load/save + report PDF export** (PowerShell via parameters/file output; web via
  browser upload/download + in-browser render) (AB#373–375, 379, 394, 395).
- **Collector / pipeline resilience** (shared engine): per-subscription try/catch/continue, MG
  role-requirement hint, false RP-registration-error swallow, per-group firewall-parse-error
  logging, empty-data guard, pipeline-`HadErrors` warning capture (AB#397–402).
- **Live-progress UX** — same feature, per-surface delivery: Spectre.Console TUI in the CLI,
  browser progress in the web portal (AB#405).

## Long-term Vision

AzureScout aims to be the definitive open-source Azure visibility tool for:

- **Architects** — understand the full shape of a tenant before designing changes
- **Security teams** — identify misconfigured, unmonitored, or over-privileged resources
- **FinOps practitioners** — surface cost waste, reservation opportunities, and untagged resources
- **Managed service providers** — generate client-ready reports across multiple tenants

The tool will remain **open-source, PowerShell-native, and Excel-friendly** — no agents, no portals, no licensing fees.

## Completed Phases

All implementation phases from the original migration plan are complete.
See the [Changelog](changelog.md) for the full history.

| Phase | Summary |
|-------|---------|
| Phase 1-9 | Core engine, module loading, Excel generation, JSON output, Draw.io diagrams, auth methods, connection handling, permission pre-flight |
| Phase 10 | Specialized Excel tabs: Cost Management, Security Overview, Azure Update Manager, Azure Monitor |
| Phase 11 | All-subscriptions + full MG hierarchy enumeration |
| Phase 12 | ARM-only default scope, permission documentation, README overhaul |
| Phase 13 | 15 new Azure Monitor/Insights modules |
| Phase 14 | 15 new AI/ML modules |
| Phase 15 | 6 AVD modules + AVD on Azure Local/Arc detection |
| Phase 16 | Arc site configs, Arc SQL Server, Arc Data Services enhancements |
| Phase 17 | VM + Arc deep enrichment (metrics, backup, DR, cost, advisor) |
| Phase 18 | Category folder alignment + `.CATEGORY` metadata parsing |
| Phase 19 | Richer progress indicators, clear permission error messages |
| Phase 20 | `Invoke-AZSCPermissionAudit` + `Test-AZSCPermissions` refactor |
| Phase 21 | Markdown + AsciiDoc export, `Export-AZSCMarkdownReport`, `Export-AZSCAsciiDocReport` |

## Suggest a Feature

Open an issue at [github.com/thisismydemo/azure-scout/issues](https://github.com/thisismydemo/azure-scout/issues) with the label `enhancement`.

Pull requests are welcome — see [Contributing](contributing.md) for guidelines.

## Fork Attribution

::: info Fork Attribution
**AzureScout is a fork of [Azure Resource Inventory (ARI)](https://github.com/microsoft/ARI)** by Microsoft, originally created by [Claudio Merola](https://github.com/Claudio-Merola) and [Renato Gregio](https://github.com/RenatoGregio). The ARI project provided the entire foundation that AzureScout builds upon — its ARM inventory module set, the draw.io diagram engine, Excel reporting, and more. AzureScout is now at 159 ARM + 17 Entra ID = 176 inventory modules — see [ARM Modules](arm-modules.md) and [Entra ID Modules](entra-modules.md). We are deeply grateful for their work.

See [Credits & Attribution](credits.md) for full details, or [Differences from ARI](ari-differences.md) for what has changed.
:::
