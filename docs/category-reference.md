---
description: Complete reference mapping every report section heading to its category alias, collector folder, and module count.
---

# Category Reference

Every section heading in an AzureScout report comes from a category. This page is the
mapping in both directions: heading → category → collector folder, and every alias the
`-Category` parameter accepts.

Use it when you see a heading in a report and want to know which collector produced it,
or when you want to re-run a scan narrowed to just that section.

::: tip Where the aliases live
The alias table is the `$_categoryAliasMap` hashtable in
`Modules/Public/PublicFunctions/Invoke-AzureScout.ps1`. Alias matching is
case-insensitive, so `iot`, `IoT`, and `INTERNET OF THINGS` all resolve identically.
:::

## Report section heading → category

| Report section heading | `-Category` value | Collector folder | Modules |
|---|---|---|---|
| AI + machine learning | `AI` | `Modules/Public/InventoryModules/AI/` | 27 |
| Analytics | `Analytics` | `Modules/Public/InventoryModules/Analytics/` | 6 |
| Compute | `Compute` | `Modules/Public/InventoryModules/Compute/` | 14 |
| Containers | `Containers` | `Modules/Public/InventoryModules/Containers/` | 6 |
| Databases | `Databases` | `Modules/Public/InventoryModules/Databases/` | 13 |
| Hybrid + multicloud | `Hybrid` | `Modules/Public/InventoryModules/Hybrid/` | 16 |
| Identity | `Identity` | `Modules/Public/InventoryModules/Identity/` | 18 |
| Integration | `Integration` | `Modules/Public/InventoryModules/Integration/` | 2 |
| Internet of Things | `IoT` | `Modules/Public/InventoryModules/IoT/` | 1 |
| Management and governance | `Management` | `Modules/Public/InventoryModules/Management/` | 19 |
| Monitor | `Monitor` | `Modules/Public/InventoryModules/Monitor/` | 24 |
| Networking | `Networking` | `Modules/Public/InventoryModules/Networking/` | 21 |
| Security | `Security` | `Modules/Public/InventoryModules/Security/` | 5 |
| Storage | `Storage` | `Modules/Public/InventoryModules/Storage/` | 2 |
| Web and mobile | `Web` | `Modules/Public/InventoryModules/Web/` | 2 |

**176 collector modules across 15 categories.** Counts are the `.ps1` file count in each
folder; one module generally maps to one worksheet in the Excel report.

The five Azure DevOps collectors sit under `Management`, which is why that count jumped in
v2.3.0. They only run when `-IncludeDevOps` is supplied — see [Azure DevOps](azure-devops.md).

## Accepted aliases

Every value below is accepted by `-Category` and normalised to the canonical short value
before any filtering happens. Anything not listed here must be passed as the canonical
value — `[ValidateSet]` rejects unknown input at parameter-binding time.

| Alias (accepted input) | Resolves to |
|---|---|
| `AI + machine learning` | `AI` |
| `AI+machine learning` | `AI` |
| `Machine Learning` | `AI` |
| `Internet of Things` | `IoT` |
| `Monitoring` | `Monitor` |
| `Management and governance` | `Management` |
| `Management & governance` | `Management` |
| `DevOps` | `Management` |
| `Migration` | `Management` |
| `Web & Mobile` | `Web` |
| `Web and mobile` | `Web` |
| `Mobile` | `Web` |
| `Hybrid + multicloud` | `Hybrid` |
| `Hybrid+multicloud` | `Hybrid` |
| `Networking + CDN` | `Networking` |
| `Networking+CDN` | `Networking` |

::: warning Monitor, not Monitoring
The canonical value is `Monitor`. `Monitoring` is accepted as an alias, but the folder,
the report heading, and the `[ValidateSet]` entry are all `Monitor`. Scripts should use
the canonical value.
:::

`DevOps` and `Migration` resolve to `Management` because those resource types are
collected by modules that live in the `Management` folder — there is no separate DevOps
or Migration collector folder to filter to.

## What each category covers

| Category | Representative collectors |
|---|---|
| `AI` | AI Foundry hubs and projects, Azure OpenAI, Cognitive Services, Bot Services, Computer Vision, ML workspaces |
| `Analytics` | Synapse, Databricks, Data Explorer clusters, Event Hubs, Stream Analytics, Purview |
| `Compute` | Virtual machines, scale sets, availability sets, and the full Azure Virtual Desktop set (host pools, session hosts, application groups, scaling plans) |
| `Containers` | AKS, ARO, Container Apps and environments, container groups, container registries |
| `Databases` | SQL, Cosmos DB, MySQL and flexible server, PostgreSQL and flexible server, MariaDB, Redis |
| `Hybrid` | Arc-enabled servers, Kubernetes, data controllers, SQL Server, extensions, gateways, resource bridge, Azure Local |
| `Identity` | Entra ID users, groups, app registrations, Conditional Access, PIM, directory roles, administrative units, domains |
| `Integration` | API Management, Service Bus |
| `IoT` | IoT Hubs |
| `Management` | Subscriptions, management groups, policy, custom role definitions, Automation Accounts, Backup, Advisor score, Lighthouse delegations, plus the five Azure DevOps collectors (projects, pipelines, service connections, repositories, agent pools) gated behind `-IncludeDevOps` |
| `Monitor` | Action groups, alert rules, Application Insights and its deep-data modules, data collection rules, diagnostic settings, Log Analytics |
| `Networking` | VNets, NSGs, load balancers, application gateways, Front Door, Azure Firewall, Bastion, ExpressRoute, VPN connections |
| `Security` | Microsoft Defender for Cloud alerts, assessments, pricing, secure score; Key Vault |
| `Storage` | Storage accounts, NetApp Files |
| `Web` | App Services, App Service plans |

## Filtering examples

```powershell
# One category, canonical value
Invoke-AzureScout -Category Compute

# Several categories
Invoke-AzureScout -Category Compute,Networking,Storage

# Portal long name — normalised to 'Hybrid'
Invoke-AzureScout -Category 'Hybrid + multicloud'

# Alias combined with a scope
Invoke-AzureScout -Scope All -Category Security,Identity

# Default: every category
Invoke-AzureScout
```

The report contains worksheets only for the categories you selected. The Overview tab
reports how many categories were selected and how many modules actually executed.

## Keeping this page accurate

The module counts here are derived from the collector folders. When you add or remove a
collector, update the counts in the first table; when you add an alias to
`$_categoryAliasMap`, add the row to the alias table. See
[Category Structure](category-structure.md) for the folder layout and
[Category Filtering](category-filtering.md) for how the filter is applied at runtime.
