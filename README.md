---
ArtifactType: Excel spreadsheet and JSON with full Azure Scout
Language: PowerShell
Platform: Windows / Linux / Mac
Tags: PowerShell, Azure, Inventory, Entra ID, Excel Report, JSON
---

<div align="center">

![AzureScout](https://raw.githubusercontent.com/thisismydemo/azure-scout/main/docs/images/azurescout-banner.svg)

# AzureScout

### See everything. Own your cloud.

[![GitHub](https://img.shields.io/github/license/thisismydemo/azure-scout)](https://github.com/thisismydemo/azure-scout/blob/main/LICENSE)
[![GitHub repo size](https://img.shields.io/github/repo-size/thisismydemo/azure-scout)](https://github.com/thisismydemo/azure-scout)
[![GitHub last commit](https://img.shields.io/github/last-commit/thisismydemo/azure-scout)](https://github.com/thisismydemo/azure-scout/commits/main)
[![GitHub top language](https://img.shields.io/github/languages/top/thisismydemo/azure-scout)](https://github.com/thisismydemo/azure-scout)
[![Azure](https://badgen.net/badge/icon/azure?icon=azure&label)](https://azure.microsoft.com)

</div>

## Overview

**AzureScout** (AZSC) is a PowerShell module that generates detailed Excel and JSON reports of an Azure tenant, covering both ARM resources and Entra ID (Azure AD) objects. It is designed for Cloud Administrators and technical professionals who need a consolidated view of their Azure environment.

> **v3.0.0 architecture:** inventory collectors are declarative definitions in
> `manifests/collectors`; AzureScout no longer ships or executes a per-collector PowerShell
> fallback tree. See the [v3.0.0 release notes](docs/v3.0.0.md).

> **Built on [Azure Resource Inventory (ARI)](https://github.com/microsoft/ARI)**
>
> AzureScout is a fork of Microsoft's [Azure Resource Inventory](https://github.com/microsoft/ARI) (ARI) v3.6.11, created by **[Claudio Merola](https://github.com/Claudio-Merola)** and **[Renato Gregio](https://github.com/RenatoGregio)**. The ARI project provided the entire foundation — 154 ARM inventory modules, draw.io diagram engine, Excel reporting pipeline, and Azure Automation support — that AzureScout builds upon. We are deeply grateful for their work.
>
> See [CREDITS.md](CREDITS.md) for full attribution and [Differences from ARI](docs/ari-differences.md) for what AzureScout has changed.

## Key Features
- ARM and Entra ID inventory
- Azure DevOps inventory — projects, pipelines, service connections, repos, agent pools
- Excel and JSON output
- Scoped execution (ARM-only, Entra-only, or both)
- Streamlined authentication
- Permission checker
- Network diagrams
- Run isolation — a rescan never overwrites the previous run's data
- Unattended execution via Azure Automation Account or GitHub Actions
- Cross-platform (Windows, Linux, Mac)

## Quick Start

### Prerequisites
- PowerShell 7.0+
- Azure account with read access
- For Entra ID inventory: Directory.Read.All permissions

### Installation

```powershell
git clone https://github.com/thisismydemo/azure-scout.git
Import-Module ./azure-scout/AzureScout.psd1
```

## Usage Example

```powershell
# Import the module
Import-Module AzureScout

# Guided wizard — no parameters needed. Signs you in, checks your rights,
# then gives you a checklist of everything Scout can run.
Invoke-AzureScout

# Scored CAF/WAF assessment (same command, different mode)
Invoke-AzureScout -Assessment LandingZone -OutputFormat Html

# Full inventory (ARM + Entra ID)
Invoke-AzureScout -TenantID <your-tenant-id>

# ARM-only
Invoke-AzureScout -TenantID <your-tenant-id> -Scope ArmOnly

# Entra ID only
Invoke-AzureScout -TenantID <your-tenant-id> -Scope EntraOnly

# Narrow to specific categories
Invoke-AzureScout -TenantID <your-tenant-id> -Category Compute,Networking

# Include Azure DevOps
Invoke-AzureScout -TenantID <your-tenant-id> -IncludeDevOps

# Name this run's output folder
Invoke-AzureScout -TenantID <your-tenant-id> -RunName 'Production-TenantA'
```

## Category Quick Reference

`-Category` narrows a scan to one or more categories. Values are the canonical short
names; Microsoft's portal long names are accepted as aliases.

| `-Category` | Report section heading | Aliases also accepted | Modules |
|---|---|---|---|
| `AI` | AI + machine learning | `AI + machine learning`, `Machine Learning` | 27 |
| `Analytics` | Analytics | — | 6 |
| `Compute` | Compute | — | 14 |
| `Containers` | Containers | — | 6 |
| `Databases` | Databases | — | 13 |
| `Hybrid` | Hybrid + multicloud | `Hybrid + multicloud` | 16 |
| `Identity` | Identity | — | 18 |
| `Integration` | Integration | — | 2 |
| `IoT` | Internet of Things | `Internet of Things` | 1 |
| `Management` | Management and governance | `Management and governance`, `DevOps`, `Migration` | 19 |
| `Monitor` | Monitor | `Monitoring` | 24 |
| `Networking` | Networking | `Networking + CDN` | 21 |
| `Security` | Security | — | 5 |
| `Storage` | Storage | — | 2 |
| `Web` | Web and mobile | `Web & Mobile`, `Mobile` | 2 |

Note that `Monitor` is canonical, not `Monitoring`. Matching is case-insensitive. The
complete mapping — every alias, manifest definition, and the resource types behind each
heading — is in the [Category Reference](docs/category-reference.md).

## Documentation

For detailed guides, module catalog, parameters, permissions, troubleshooting, testing, and contributing, see:

- [Full Documentation](docs/index.md)
- [Prerequisites & Required Modules](docs/prerequisites.md)
- [Authentication](docs/authentication.md)
- [Usage Guide](docs/usage.md)
- [Parameters Reference](docs/parameters.md)
- [Permissions](docs/permissions.md)
- [Category Filtering](docs/category-filtering.md)
- [Category Reference](docs/category-reference.md)
- [Output Files & Formats](docs/output.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Azure Automation Account](docs/automation.md)
- [GitHub Actions](docs/github-actions.md)
- [Azure DevOps](docs/azure-devops.md)
- [Validation Matrix](docs/validation-matrix.md)
- [ARM Modules](docs/arm-modules.md)
- [Entra Modules](docs/entra-modules.md)
- [Testing](docs/testing.md)
- [v3.0.0 release notes](docs/v3.0.0.md)
- [Contributing](docs/contributing.md)
- [Credits & Attribution](docs/credits.md)

## License

Licensed under the MIT License — see [LICENSE](LICENSE) for details.
