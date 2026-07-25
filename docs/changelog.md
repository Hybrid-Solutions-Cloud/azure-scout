---
description: Release history and version changelog for AzureScout.
---

# Changelog

The full changelog is maintained in the repository root and rendered on GitHub.

[View CHANGELOG.md on GitHub](https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md)

## Summary

AzureScout follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

| Version | Highlights |
|---------|------------|
| **v2.4.0** (2026-07-25) | **One command** — inventory and assessment became modes of `Invoke-AzureScout` rather than two cmdlets (`-Assessment`, `-CollectOnly`, `-FromCollect`); assessment mode now honours the inventory sign-in parameters; `-OutputFormat` widened to accept several renderers in one run. A **guided setup wizard** opens when `Invoke-AzureScout` is run with no parameters at a terminal, and never fires in CI. `Invoke-ScoutAssessment` is deprecated for removal in v3.0.0 |
| **v2.3.0** (2026-07-25) | Run isolation (each invocation gets its own run folder, `-RunName`, `-Force`, `Clear-AZSCCacheFolder -OlderThan`), the caller's subscription context restored after multi-subscription runs, a post-login management-group probe, **Azure DevOps inventory** via `-IncludeDevOps` (five worksheets plus service-connection-to-subscription cross-reference), a composite `action.yml` for GitHub Actions, and new automation, category-reference, and validation-matrix documentation |
| **v2.2.0** (2026-07-24) | Four new report tiers (`Word`, `EChartsDashboard`, `Pdf`, `JsonEvidence`), Excel visual dashboard tabs, a much richer interactive React report (topology, MG hierarchy, KPI cards, Governance section, drill-downs) + `report.pbit` generation, new offline analysis (`Get-ScoutInventoryDrift`, `Get-ScoutCostAnomaly`, `Get-ScoutIacGap`), IoT deep coverage (DPS + Digital Twins), tag aggregation, deeper Database/Analytics/IoT rule automation, collector/pipeline resilience, assessment config load/save (`Import-ScoutConfig`/`Export-ScoutConfig`), a CI pipeline, a real `azure-inventory` workflow, and five v1 inventory bug fixes |
| **v2.1.0** (2026-07-23) | Native governance collector (`Import-Governance`, no more AzGovViz dependency by default), unattended one-command pipeline (`Invoke-ScoutPipeline`), and a React report + cross-run drift tracking (`-OutputFormat React`, `Get-ScoutDrift`) |
| **v2.0.0** | **CAF/WAF Assessment Platform** — read-only assessment engine (139 rules across 8 CAF design areas + 5 WAF pillars), ARG collect layer, AzGovViz/Advisor/ARG ingest, ALZ benchmark, tiered reporting (Power BI / HTML / OpenXML PowerPoint / Excel / JSON), per-domain analytics via `Invoke-ScoutAssessment`. Runtime-verified offline + live tenant. Breaking: `findings.json` contract; assessment requires PowerShell 7 |
| **v1.0.0** | Full rename to AzureScout (AZSC prefix), 154 ARM modules, 17 Entra ID modules, Excel + JSON + Markdown + AsciiDoc output, draw.io diagrams, permission pre-flight, category filtering |
