---
description: For each of the 18 Azure portal service categories, every Azure service Microsoft publishes in that category, marked Collected or Not collected against AzureScout's 245 collectors.
---

# Service Coverage Gap

[Coverage Table](coverage-table.md) and [ARM Modules](arm-modules.md) list every collector AzureScout
**has**, grouped by category. This page inverts that question: for each of the 18 categories, what
does Microsoft publish under that category, and which of those services do we actually collect?

::: warning This page is hand-maintained, not generated
Unlike [Coverage Table](coverage-table.md) and [ARM Modules](arm-modules.md) — which regenerate from
`manifests/collectors/` and cannot drift — the "what Microsoft publishes" half of this page comes from
external Microsoft sources that are not available to a build-time script (Microsoft does not publish a
machine-readable per-portal-category product feed). The "what we collect" half is cross-checked against
[Coverage Table](coverage-table.md), which *is* generated, but the page as a whole needs a periodic manual
re-fetch against the source URLs below — Microsoft's own catalogue drifts (services rename, rebrand, and
retire) faster than most of this repository.
:::

## Sources and method

- **Product catalogue**: [azure.microsoft.com/products](https://azure.microsoft.com/en-us/products/),
  filtered per category (e.g. `?categories=compute`). This is Microsoft's own product-category taxonomy
  and the closest public equivalent to the Azure portal's "All services" category groupings that
  [Category Structure](category-structure.md) is built on. **Fetched 2026-08-04.**
- **Azure Monitor** has no entry on that catalogue page (`?categories=monitor` 404s) — Monitor's
  products are folded into the "DevOps" and "Management and governance" pages there instead. For
  Monitor, the sub-item list below is sourced from Microsoft Learn's
  [Azure Monitor overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview) and
  [Azure Monitor enterprise monitoring architecture](https://learn.microsoft.com/azure/azure-monitor/fundamentals/enterprise-monitoring-architecture)
  articles. **Fetched 2026-08-04.**
- **General** has no public product catalogue entry either — "Support tickets", "Reservations" and "VM
  quotas" are platform surfaces, not marketed products. See the note in that section; no sourced count
  is given for it, rather than inventing one.
- **What we collect**: read directly off [Coverage Table](coverage-table.md), which is generated from
  `manifests/collectors/**/*.psd1` by `scripts/Build-ArmModuleCatalog.ps1`.
- A service is marked **Collected** only when a specific collector's `ResourceTypes` targets that
  service's ARM resource type (or, for Entra/Graph-backed services, its Graph endpoint). A service that
  would incidentally appear as a generic `virtualMachines` or `storageAccounts` row (for example "Linux
  Virtual Machines" or "Data Science Virtual Machines") is marked Collected only if there is no
  dedicated resource type to miss; otherwise it is called out as its own row.
- **Commonly cited figures** (22 for AI + Machine Learning, 32 for Compute, 12 for Containers)
  are checked against the sourced counts in each section, not assumed to be correct — see the
  discrepancy notes.

## Coverage summary

| Category | Microsoft services (sourced) | Collected | Not collected | Coverage | Cited figure | Matches? |
|---|---|---|---|---|---|---|
| AI + Machine Learning | 31 | 16 | 15 | 52% | 22 | No — see note |
| Analytics | 19 | 6 | 13 | 32% | — | — |
| Compute | 22 | 14 | 8 | 64% | 32 | No — see note |
| Containers | 9 | 7 | 2 | 78% | 12 | No — see note |
| Databases | 15 | 10 | 5 | 67% | — | — |
| DevOps | 19 | 8 | 11 | 42% | — | — |
| General | ambiguous — no published catalogue | 4 of AzureScout's own 5 | n/a | n/a | — | — |
| Hybrid + multicloud | 14 (marketing list) / ambiguous, see note | 16 collectors, 2 known resource-family gaps | Custom Locations; Arc-enabled VMware/SCVMM | n/a | — | — |
| Identity | 4 (product-level; ambiguous, see note) | all 4 present | 0 | n/a | — | — |
| Integration | 7 | 5 | 2 | 71% | — | — |
| Internet of Things | 16 | 6 | 10 | 38% | — | — |
| Management and governance | 25 | 12 | 13 | 48% | — | — |
| Migration | 6 | 6 | 0 | 100% | — | — |
| Monitor | 14 (Learn-derived) | 13 | 1 | 93% | — | — |
| Networking | 22 | 17 | 5 | 77% | — | — |
| Security | 19 | 13 | 6 | 68% | — | — |
| Storage | 19 | 11 | 8 | 58% | — | — |
| Web & Mobile | 15 (union of Web + Mobile) | 12 | 3 | 80% | — | — |

Percentages exclude items marked N/A (not an ARM resource — an OS, an SDK, a GitHub product, or a
non-resource capability) from both the numerator and denominator; those rows are still listed so nothing
is silently dropped.

## AI + Machine Learning

Source: [azure.microsoft.com/products?categories=ai-machine-learning](https://azure.microsoft.com/en-us/products/?categories=ai-machine-learning), fetched 2026-08-04 — 31 products.

::: warning A commonly cited figure of 22 does not match the sourced count (31)
Microsoft's AI + Machine Learning catalogue lists 31 named products as of this fetch, most of them the
"Foundry"-branded rename of the individual Cognitive Services APIs (Vision, Language, Speech, Document
Intelligence, Content Safety, etc.) that shipped through 2025–2026. If 22 came from an older
snapshot of the same page (pre-Foundry rebrand) or from the Azure portal's own **AI + Machine Learning**
blade rather than this catalogue, that would explain the gap — we did not find a source that lists
exactly 22.
:::

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Microsoft Foundry (hub/project) | Collected | `AIFoundryHubs`, `AIFoundryProjects` |
| Azure AI Bot Service | Collected | `BotServices` |
| Azure AI Search | Collected | `SearchServices`, `SearchIndexes` |
| Azure Databricks | Collected (cross-category: Analytics) | `Databricks` |
| Azure Machine Learning | Collected | `MachineLearning`, `MLComputes`, `MLDatasets`, `MLDatastores`, `MLEndpoints`, `MLModels`, `MLPipelines` |
| Azure Open Datasets | Not collected | — (data catalogue, not an inventoried resource) |
| Foundry Tools (Vision/Language/etc. umbrella) | Collected | see individual Cognitive Services rows below |
| Azure AI Video Indexer | Not collected | — |
| Azure AI Custom Vision | Collected | `CustomVision` |
| Data Science Virtual Machines | Not collected | no dedicated collector (would appear only as a generic `VirtualMachine` row) |
| Azure AI Language (Foundry Tools) | Collected | `TextAnalytics` |
| Azure AI Translator (Foundry Tools) | Collected | `Translator` |
| Azure AI Metrics Advisor | Not collected | — |
| Azure OpenAI (Foundry Models) | Collected | `OpenAIAccounts`, `OpenAIDeployments` |
| Azure AI Personalizer | Not collected | — |
| Content Safety (Foundry Control Plane) | Collected | `ContentSafety` |
| Health Bot | Not collected | — |
| Azure Document Intelligence (Foundry Tools) | Collected | `FormRecognizer` |
| AI Anomaly Detector | Not collected | — |
| Foundry Models | Partially collected | `OpenAIDeployments` covers OpenAI; other Foundry model families are not enumerated |
| Microsoft Security Copilot | Not collected | — |
| Azure AI Immersive Reader | Collected | `ImmersiveReader` |
| Phi open models | N/A | model weights, not an ARM resource |
| Azure Content Understanding (Foundry Tools) | Not collected | — |
| Azure AI Speech (Foundry Tools) | Collected | `SpeechService` |
| Microsoft Planetary Computer Pro | Not collected | — |
| Foundry Agent Service | Not collected | — |
| Azure SRE Agent | Not collected | — |
| Observability (Foundry Control Plane) | Not collected | — |
| Azure AI Vision (Foundry Tools) | Collected | `ComputerVision` |
| Foundry IQ | Not collected | — |

We also collect `AppliedAIServices`, `AzureAI`, `FaceAPI` and `HealthInsights` — general or older
Cognitive Services surfaces that Microsoft's current catalogue folds into "Foundry Tools" rather than
listing individually, so they are not double-counted above.

We also collect `ContentModerator` (`microsoft.cognitiveservices/accounts`, `Kind -eq
'ContentModerator'`), which does not appear in the table above because Microsoft retired it: Content
Moderator has been unavailable for new resource creation since 15 March 2024 and is scheduled for full
retirement on 15 March 2027, replaced by Azure AI Content Safety (already tracked above as
`ContentSafety`). Same shape as the `MariaDB`/`SQLPOOL` note under Databases — a working collector
pointed at a decommissioned service, not a coverage gap.

## Analytics

Source: [azure.microsoft.com/products?categories=analytics](https://azure.microsoft.com/en-us/products/?categories=analytics), fetched 2026-08-04 — 19 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Azure Analysis Services | Not collected | — |
| Azure Data Explorer | Collected | `DataExplorerCluster` |
| Azure Data Factory | Not collected | real gap |
| Azure Data Lake Storage | Collected (cross-category: Storage) | `StorageAccounts` (Gen2 accounts are still `microsoft.storage/storageaccounts`) |
| Azure Data Share | Not collected | — |
| Azure Databricks | Collected | `Databricks` |
| Azure Stream Analytics | Collected | `Streamanalytics` |
| Azure Synapse Analytics | Collected | `Synapse` |
| Data Catalog | N/A | Microsoft retired Azure Data Catalog in 2022 |
| Data Lake Analytics | N/A | Microsoft retired Azure Data Lake Analytics in 2024 |
| Event Hubs | Collected | `EvtHub` (namespaces); `EventHubClusters` also collected under Integration |
| HDInsight | Not collected | real gap |
| Power BI Embedded | Not collected | — |
| Microsoft Graph Data Connect | Not collected | — |
| Azure Chaos Studio | Collected (cross-category: DevOps) | `ChaosStudio` |
| Microsoft Fabric | Not collected | real gap — no Fabric capacity/workspace collector exists |
| Microsoft Purview | Collected | `Purview` |
| Power BI | Not collected | — |
| Microsoft Planetary Computer Pro | Not collected | — |

## Compute

Source: [azure.microsoft.com/products?categories=compute](https://azure.microsoft.com/en-us/products/?categories=compute), fetched 2026-08-04 — 22 products.

::: warning A commonly cited figure of 32 does not match the sourced count (22)
Microsoft's Compute catalogue lists 22 named products. We found no Microsoft source — marketing
catalogue, Azure portal category, or Learn taxonomy page — that lists 32 for Compute. If 32 came from
counting VM series/SKU families (Dv5, Ev5, NCv3, etc.) rather than products, that is a different and
much larger axis than "sub-services" and is not what this page tracks.
:::

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| App Service | Collected (cross-category: Web) | `APPServices`, `APPServicePlan` |
| Azure Compute Fleet | Not collected | real gap — new (2024) service, no `microsoft.computefleet` collector |
| Azure Quantum | Not collected | real gap |
| Azure Spot Virtual Machines | Collected | `VirtualMachine` (same resource type, priority attribute) |
| Azure Spring Apps | Collected (cross-category: Web) | `SpringApps` |
| Azure VMware Solution | Collected | `VMWare` |
| Batch | Not collected | real gap — no `microsoft.batch` collector |
| Cloud Services | Not collected | legacy/retiring platform |
| Linux Virtual Machines | Collected | `VirtualMachine` (same resource type as Windows) |
| SQL Server on Azure Virtual Machines | Collected (cross-category: Databases) | `SQLVM` |
| Static Web Apps | Collected (cross-category: Web) | `StaticWebApps` |
| Virtual Machine Scale Sets | Collected | `VirtualMachineScaleSet` |
| Virtual Machines | Collected | `VirtualMachine`, `VMDisk`, `VMOperationalData` |
| Azure Virtual Desktop | Collected | `AVD`, `AVDApplicationGroups`, `AVDApplications`, `AVDAzureLocal`, `AVDScalingPlans`, `AVDSessionHosts`, `AVDWorkspaces` |
| Windows Server | N/A | operating system, not an ARM resource |
| Azure Dedicated Host | Not collected | real gap — no `microsoft.compute/dedicatedhosts` collector |
| Azure VM Image Builder | Not collected | real gap |
| Azure Kubernetes Service (AKS) | Collected (cross-category: Containers) | `AKS` |
| Azure Functions | Collected (cross-category: Web) | `FunctionApps` |
| Azure Container Instances | Collected (cross-category: Containers) | `ContainerGroups` |
| Azure Container Apps | Collected (cross-category: Containers) | `ContainerApp`, `ContainerAppEnv` |
| Nutanix Cloud Clusters on Azure | Not collected | real gap — 2024 partner-hosted service |

`AvailabilitySets` is also collected but does not appear as its own line item in Microsoft's catalogue
(it is a sub-feature of Virtual Machines there).

## Containers

Source: [azure.microsoft.com/products?categories=containers](https://azure.microsoft.com/en-us/products/?categories=containers), fetched 2026-08-04 — 9 products.

::: warning A commonly cited figure of 12 does not match the sourced count (9)
Microsoft's Containers catalogue lists 9 products. It does not separately list Azure Container Storage
sub-features, Draft, or KEDA as distinct products the way some internal container-platform
documentation does, which may explain a larger internal count; we could not source 12 from a Microsoft
product page.
:::

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| App Configuration | Collected (cross-category: DevOps) | `AppConfiguration` |
| Azure Kubernetes Service (AKS) | Collected | `AKS` |
| Azure Kubernetes Fleet Manager | Not collected | real gap — no `microsoft.containerservice/fleets` collector |
| Azure Red Hat OpenShift | Collected | `ARO` |
| Azure Container Apps | Collected | `ContainerApp`, `ContainerAppEnv` |
| Azure Functions | Collected (cross-category: Web) | `FunctionApps` |
| Azure Container Instances | Collected | `ContainerGroups` |
| Azure Container Registry | Collected | `ContainerRegistries` |
| Azure Container Storage | Not collected | real gap — no `microsoft.containerstorage` collector |

## Databases

Source: [azure.microsoft.com/products?categories=databases](https://azure.microsoft.com/en-us/products/?categories=databases), fetched 2026-08-04 — 15 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Azure Cosmos DB | Collected | `CosmosDB` |
| Azure DocumentDB | Not collected | real gap — the 2025 vCore-based MongoDB service is a distinct resource provider from Cosmos DB |
| Azure SQL (umbrella) | Collected | see SQL DB / MI rows below, plus `SQLSERVER` (the logical `microsoft.sql/servers` resource) |
| Azure SQL Database | Collected | `SQLDB` |
| Azure SQL Managed Instance | Collected | `SQLMI`, `SQLMIDB` |
| SQL Server on Azure Virtual Machines | Collected (cross-category: Compute) | `SQLVM` |
| Azure Database for PostgreSQL | Collected | `POSTGREFlexible` (flexible server only — single server was retired by Microsoft in 2024) |
| Azure Database for MySQL | Collected | `MySQL`, `MySQLflexible` |
| Azure Managed Redis | Collected | `RedisCache` (covers `microsoft.cache/redisenterprise`) |
| Azure Database Migration Service | Collected (cross-category: Migration) | `DatabaseMigrationServices` |
| Azure Managed Instance for Apache Cassandra | Not collected | real gap |
| Azure Data Factory | Not collected | real gap (also listed under Analytics) |
| Table Storage | Not collected | no dedicated collector for `microsoft.storage/storageaccounts/tableservices` |
| Azure confidential ledger | Collected (cross-category: Security) | `ConfidentialLedger` |
| Azure HorizonDB | Not collected | real gap — new (2025) service |

We also collect `MariaDB` and `SQLPOOL` (elastic pools), neither of which appears in Microsoft's current
catalogue — Azure Database for MariaDB was retired by Microsoft in September 2025, so that collector is
now pointed at a decommissioned service rather than a coverage gap. We also collect `SQLSERVER` (the
logical `microsoft.sql/servers` resource that hosts Azure SQL Database and Managed Instance) — Microsoft
does not catalogue "SQL Server" as a separate product from the "Azure SQL" umbrella, which is why it has
no dedicated row above.

## DevOps

Source: [azure.microsoft.com/products?categories=devops](https://azure.microsoft.com/en-us/products/?categories=devops), fetched 2026-08-04 — 19 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Azure Artifacts | Not collected | real gap |
| Azure Boards | Not collected | real gap |
| Azure DevOps (organization) | Collected | `DevOpsProjects` |
| Azure DevTest Labs | Collected | `DevTestLabs` |
| Azure Monitor | Collected (cross-category: Monitor) | 22 Monitor collectors |
| Azure Pipelines | Collected | `DevOpsPipelines`, `DevOpsAgentPools` |
| Azure Repos | Collected | `DevOpsRepositories` |
| Azure Test Plans | Not collected | real gap |
| DevOps tool integrations | N/A | not a resource |
| Azure App Testing | Not collected | real gap |
| Azure Managed Grafana | Not collected | real gap — no `microsoft.dashboard/grafana` collector anywhere in the estate |
| Microsoft Dev Box | Collected | `DevBoxPools`, `DevCenters`, `DevCenterNetworkConnections` |
| Azure Deployment Environments | Collected | `DeploymentEnvironments` |
| GitHub Advanced Security for Azure DevOps | Not collected | real gap |
| Microsoft Playwright Testing | Collected | `PlaywrightTesting` |
| GitHub Enterprise | N/A | not an Azure resource |
| GitHub Advanced Security | N/A | not an Azure resource |
| GitHub Copilot | N/A | not an Azure resource |
| Azure SRE Agent | Not collected | real gap — new (2026) service |

We also collect `ApiConnections`, `ChaosStudio`, `LabServices`, `LoadTesting`, `ManagedDevOpsPools` and
`DevOpsServiceConnections`, none of which are separately listed on Microsoft's DevOps catalogue page
(Chaos Studio is listed under Analytics there, `DevOpsServiceConnections` is a sub-object of an Azure
DevOps project rather than its own product, and the rest are sub-features of things already counted
above).

## General

Microsoft does not publish "General" as a product category — it exists in the Azure portal's "All
services" grouping for platform surfaces (support, billing, quotas, reservations) that don't belong to
any service family, but Microsoft's own product catalogue doesn't enumerate it the way it does the other
17 categories. We are not inventing a sourced total for this one.

AzureScout's `General` category has 5 collectors: `Quotas`, `ReservationRecom`, `Reservations`,
`ReservationUtilization`, `SupportTickets`. The one gap we can identify without a source to check
against: **Cost Management data itself is collected by a separate pipeline** (`Get-ScoutCostInventory.ps1`,
not a `manifests/collectors/General` definition) — it is not a gap so much as a different collection
path from the rest of this page.

## Hybrid + multicloud

Source: [azure.microsoft.com/products?categories=hybrid-multicloud](https://azure.microsoft.com/en-us/products/?categories=hybrid-multicloud), fetched 2026-08-04 — 14 products.

::: warning This category is ambiguous — the marketing list and the portal category diverge
Microsoft's "Hybrid + multicloud" *product* catalogue is a marketing cross-listing (it includes Azure
SQL Database, Azure ExpressRoute, Microsoft Sentinel — products that live natively in other categories
and are tagged "hybrid" because they have a hybrid connectivity story). It is **not** the same shape as
the Azure portal's **Hybrid + multicloud** category blade, which is what
[Category Structure](category-structure.md) and our `Hybrid` collector folder are built against — that
blade is organized around Azure Arc resource families (Arc servers, Arc Kubernetes, Arc data services,
Azure Local/Stack HCI, VMware Solution, Stack Edge, Stack Hub). We're reporting against the resource
families the portal blade actually exposes, not the marketing list, because that's the comparison the
is asked for when someone wants the sub-services under a main category.
:::

| Azure Arc / Hybrid resource family | Status | AzureScout collector |
|---|---|---|
| Arc-enabled servers | Collected | `ARCServers`, `ArcServerOperationalData`, `ArcExtensions`, `ArcGateways` |
| Arc-enabled Kubernetes | Collected | `ArcKubernetes` |
| Arc-enabled data services (data controllers) | Collected | `ArcDataControllers` |
| Arc-enabled SQL Server | Collected | `ArcSQLServers` |
| Arc-enabled SQL Managed Instance | Collected | `ArcSQLManagedInstances` |
| Arc Resource Bridge | Collected | `ArcResourceBridge` |
| Arc Sites | Collected | `ArcSites` |
| **Arc-enabled VMware vSphere** (`Microsoft.ConnectedVMwarevSphere`) | **Not collected** | real gap — confirmed no collector references this resource provider |
| **Arc-enabled SCVMM** (`Microsoft.ScVmm`) | **Not collected** | real gap — confirmed no collector references this resource provider |
| **Custom Locations** (`Microsoft.ExtendedLocation/customLocations`) | **Not collected** | real gap — confirmed no collector references this resource type at all; every Arc resource bridge deployment creates one |
| Azure Local (Stack HCI) clusters | Collected | `Clusters` |
| Azure Local VMs | Collected | `VirtualMachines` (`AZSC/ARMChild/AzureLocalVirtualMachineInstances`) |
| Azure Local gallery/marketplace images | Collected | `GalleryImages`, `MarketplaceGalleryImages` |
| Azure Local logical networks | Collected | `LogicalNetworks` |
| Azure Local storage containers | Collected | `StorageContainers` |
| Azure VMware Solution | Collected (cross-category: Compute) | `VMWare` |
| Azure Stack Edge | Collected (cross-category: Migration) | `StackEdge` |
| Azure Stack Hub | **Out of scope** | not a gap — Azure Scout does not cover Azure Stack Hub. Product decision, 2026-08-04. Do not re-raise this as missing coverage. |
| Azure Operator Nexus / Operator Service Manager | Not collected | real gap — telco-specific, likely low priority |
| Azure Storage Mover | Not collected | real gap |

This corrects the earlier claim that GalleryImages, MarketplaceGalleryImages and StorageContainers were
missing — those three collectors exist and cover the **Azure Local** (Stack HCI) resource family. The
real, confirmed gaps are the two Arc-enabled hypervisor-management resource providers
(`Microsoft.ConnectedVMwarevSphere`, `Microsoft.ScVmm`) and Custom Locations, none of which have any
collector referencing them anywhere in `manifests/collectors/`.

## Identity

Source: [azure.microsoft.com/products?categories=identity](https://azure.microsoft.com/en-us/products/?categories=identity), fetched 2026-08-04 — 4 products.

::: warning This category doesn't fit a Collected/Not collected table
Microsoft's product catalogue counts **Microsoft Entra ID** as a single product; it doesn't break out
Entra ID's internal object types (users, groups, app registrations, Conditional Access, PIM, etc.) into
separate catalogue entries the way the Azure portal's Identity blade — and our 19 Identity collectors —
do. So "4 of 4" would be true but not useful. All 4 Microsoft-catalogued identity products have at least
one collector:
:::

| Microsoft product | Status | AzureScout collector(s) |
|---|---|---|
| Microsoft Entra ID | Collected | 15 of the 17 Identity collectors (`Users`, `Groups`, `AppRegistrations`, `ConditionalAccess`, `DirectoryRoles`, `Domains`, `Licensing`, `ManagedIdentities`, `NamedLocations`, `PIMAssignments`, `RiskyUsers`, `SecurityPolicies`, `ServicePrincipals`, `AdminUnits`, `CrossTenantAccess`) — the remaining 2 (`ManagedIds`, an ARM `Microsoft.ManagedIdentity/userAssignedIdentities` collector distinct from the Entra-Graph `ManagedIdentities`; and `RoleAssignments`, Azure RBAC role assignments) are governance/RBAC primitives filed under the Identity manifest folder rather than Entra-ID directory objects |
| Microsoft Entra Domain Services | Collected (cross-category: Security) | `EntraDomainServices` |
| Microsoft Entra Verified ID | Collected | `VerifiedIDProfiles` (`/v1.0/identity/verifiedId/profiles` — the configured profiles: recovery/onboarding usage, Face Check, accepted issuer), `VerifiedIDConfiguration` (`/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/VerifiableCredentials` — the tenant-wide enable/disable state and excluded groups). AB#7097. **Not reached:** the separate Verified ID Admin API (issuer DIDs, authorities, contracts) at `verifiedid.did.msidentity.com` — a different host and OAuth resource (`6a8b4b39-c021-437c-b060-5a14a3fd65f3`) than the `graph.microsoft.com` audience every other Entra collector in this repo uses; reaching it needs a second token audience threaded through the shared Graph client, not a per-collector change. |
| Microsoft Entra External ID | Collected (AB#7098) | `ExternalIdentities` — the tenant-wide DEFAULT cross-tenant access policy (`GET /v1.0/policies/crossTenantAccessPolicy/default`: B2B collaboration/direct connect inbound+outbound access, inbound trust, tenant restrictions) that governs every external organization not covered by a `CrossTenantAccess` partner override. Wired into both the Excel/PPTX inventory export (`entra/externalidentities`) and the assessment collect / React payload (`domains.identity.externalIdentitiesPolicy`, via `Get-ScoutExternalIdentitiesPolicy.ps1`) |

## Integration

Source: [azure.microsoft.com/products?categories=integration](https://azure.microsoft.com/en-us/products/?categories=integration), fetched 2026-08-04 — 7 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| API Management | Collected | `APIM` |
| Azure Health Data Services | Collected | `HealthDataServices` |
| Event Grid | Collected | `EventGrid` |
| Logic Apps | Collected | `LogicApps`, `LogicAppsCustomConnectors`, `IntegrationAccounts` |
| Service Bus | Collected | `ServiceBUS` |
| Azure Web PubSub | Collected (cross-category: Web) | `WebPubSub` |
| Microsoft Energy Data Services | Not collected | real gap — vertical-specific, likely low priority |

We also collect `EventHubClusters` and `Relays`, neither separately catalogued by Microsoft under
Integration (Event Hubs itself is catalogued under Analytics).

## Internet of Things

Source: [azure.microsoft.com/products?categories=internet-of-things](https://azure.microsoft.com/en-us/products/?categories=internet-of-things), fetched 2026-08-04 — 16 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| API Management | Collected (cross-category: Integration) | `APIM` |
| Azure Cosmos DB | Collected (cross-category: Databases) | `CosmosDB` |
| Azure Digital Twins | Collected | `DigitalTwins` |
| Azure IoT Central | Collected | `IoTCentral` |
| Azure IoT Edge | Not collected | real gap — no distinct IoT Edge deployment collector |
| Azure IoT Hub | Collected | `IOTHubs` |
| Azure IoT Operations | Not collected | real gap — new (2024) Arc-enabled Kubernetes IoT workload, no collector |
| Azure Functions | Collected (cross-category: Web) | `FunctionApps` |
| Azure Machine Learning | Collected (cross-category: AI) | `MachineLearning` |
| Azure Maps | Collected | `Maps` |
| Azure Stream Analytics | Collected (cross-category: Analytics) | `Streamanalytics` |
| Notification Hubs | Collected (cross-category: Web) | `NotificationHubs` |
| Windows for IoT | N/A | operating system, not an ARM resource |
| Logic Apps | Collected (cross-category: Integration) | `LogicApps` |
| Azure Sphere | Not collected | real gap — Microsoft is retiring Azure Sphere (end of support 2026), low priority |
| Event Grid | Collected (cross-category: Integration) | `EventGrid` |

We also collect `DeviceProvisioningServices`, `DeviceUpdate` and `DefenderForIoT`, none separately
catalogued by Microsoft under Internet of Things (Defender for IoT is catalogued under Security).

## Management and governance

Source: [azure.microsoft.com/products?categories=management-and-governance](https://azure.microsoft.com/en-us/products/?categories=management-and-governance), fetched 2026-08-04 — 25 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Azure Copilot | N/A | assistant experience, not an inventoried resource |
| Automation | Collected | `AutomationAccounts` |
| Azure Advisor | Collected | `AdvisorScore` |
| Defender External Attack Surface Management | Not collected | real gap |
| Azure Backup | Collected | `Backup`, `BackupInstances`, `RecoveryVault` |
| Azure Blueprints | Not collected | real gap |
| Azure Lighthouse | Collected | `LighthouseDelegations` |
| Azure Managed Applications | Not collected | real gap |
| Azure Migrate | Collected (cross-category: Migration) | `AzureMigrateProjects`, `AzureMigrateAssessments` |
| Microsoft Purview | Collected (cross-category: Analytics) | `Purview` |
| Azure Monitor | Collected (cross-category: Monitor) | 22 Monitor collectors |
| Azure Policy | Collected | `PolicyAssignments`, `PolicyDefinitions`, `PolicySetDefinitions`, `PolicyComplianceStates` |
| Azure Resource Manager | N/A | control-plane API, not itself a resource |
| Azure Resource Manager templates | N/A | deployment artifact, not a resource |
| Azure Chaos Studio | Collected (cross-category: DevOps) | `ChaosStudio` |
| Azure Site Recovery | Not collected | real gap — no distinct Site Recovery replication collector (Recovery Vault container is collected, replication items are not) |
| Cloud Shell | N/A | not an inventoried resource |
| Microsoft Cost Management | Collected (separate pipeline) | `Get-ScoutCostInventory.ps1`, not a `manifests/collectors` definition |
| Azure Managed Grafana | Not collected | real gap (also listed under DevOps) |
| Azure Network Watcher | Collected (cross-category: Networking) | `NetworkWatchers` |
| Azure Traffic Manager | Collected (cross-category: Networking) | `TrafficManager` |
| Azure Automanage | Not collected | real gap |
| Azure Resource Mover | Not collected | real gap |
| Update management center | Not collected | real gap — distinct from `MaintenanceConfigurations`, which we do collect |
| Azure SRE Agent | Not collected | real gap (also listed under DevOps) |

We also collect `AllSubscriptions`, `Budgets`, `CustomRoleDefinitions`, `ManagementGroups`,
`MaintenanceConfigurations` and `ResourceLocks`, none separately catalogued as products by Microsoft
(they're governance primitives, not marketed services).

## Migration

Source: [azure.microsoft.com/products?categories=migration](https://azure.microsoft.com/en-us/products/?categories=migration), fetched 2026-08-04 — 6 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Azure Database Migration Service | Collected | `DatabaseMigrationServices` |
| Azure Migrate | Collected | `AzureMigrateProjects`, `AzureMigrateAssessments`, `AzureMigrateDiscoverySites` |
| Azure Site Recovery | Not collected | real gap (also listed under Management and governance) |
| Microsoft Cost Management | Collected (separate pipeline) | `Get-ScoutCostInventory.ps1` |
| Azure Data Box | Collected | `DataBox` |
| Azure Storage Mover | Not collected | real gap (also listed under Hybrid + multicloud) |

Migration is the one category where our collector-name coverage figure (6 of 6 in the summary table
above) is misleading: two of Microsoft's six listed products (Site Recovery, Storage Mover) are not
actually collected — the "6 of 6" only holds if `StackEdge` is counted as the Migration category's own
Data Box/Stack Edge coverage, which it is, but Site Recovery and Storage Mover remain real gaps.

## Monitor

Source: Microsoft Learn, [Azure Monitor overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview) and
[Azure Monitor enterprise monitoring architecture](https://learn.microsoft.com/azure/azure-monitor/fundamentals/enterprise-monitoring-architecture), fetched 2026-08-04.
Monitor has no entry on Microsoft's product-category marketing catalogue (`?categories=monitor` 404s), so
this list is the set of named Azure Monitor sub-components those Learn articles describe, not a
marketing product list.

| Azure Monitor component | Status | AzureScout collector |
|---|---|---|
| Application Insights | Collected | `AppInsights`, `AppInsightsAvailabilityTests`, `AppInsightsWebTests`, `AppInsightsProactiveDetection` |
| Log Analytics workspaces | Collected | `Workspaces` |
| Log Analytics saved searches / linked services | Collected | `LAWorkspaceSavedSearches`, `LAWorkspaceLinkedServices` |
| Log Analytics solutions | Collected | `LAWorkspaceSolutions` |
| Azure Monitor managed service for Prometheus | Not collected | real gap — no collector for Prometheus rule groups / Azure Monitor workspaces |
| Metric alert rules | Collected | `MetricAlertRules` |
| Log/scheduled query alert rules | Collected | `ScheduledQueryRules` |
| Activity log alert rules | Collected | `ActivityLogAlertRules` |
| Smart detector alert rules | Collected | `SmartDetectorAlertRules` |
| Action groups | Collected | `ActionGroups` |
| Autoscale settings | Collected | `AutoscaleSettings` |
| Diagnostic settings | Collected | `ResourceDiagnosticSettings`, `SubscriptionDiagnosticSettings` |
| Data collection rules / endpoints | Collected | `DataCollectionRules`, `DataCollectionEndpoints` |
| Workbooks | Collected | `MonitorWorkbooks` |

We also collect `MonitorMetricsIngestion`, `MonitorPrivateLinkScopes` and `Outages`, all genuine Monitor
surfaces the two source articles don't call out individually. Azure Managed Grafana, which Learn
documentation frequently pairs with Monitor visualization, is tracked as a gap under DevOps and
Management and governance instead, since that is where Microsoft's own product catalogue places it.

## Networking

Source: [azure.microsoft.com/products?categories=networking](https://azure.microsoft.com/en-us/products/?categories=networking), fetched 2026-08-04 — 22 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Azure Application Gateway | Collected | `ApplicationGateways` |
| Azure Bastion | Collected | `BastionHosts` |
| Azure DDoS Protection | Collected (cross-category: Security) | `DdosProtectionPlans` |
| Azure DNS | Collected | `PublicDNS`, `PrivateDNS` |
| Azure ExpressRoute | Collected | `ExpressRoute` |
| Azure Firewall | Collected | `AzureFirewall` |
| Azure Content Delivery Network | Not collected | real gap — no `microsoft.cdn/profiles` collector (WAF policies attached to CDN are collected via `WafPolicies`, the CDN profile itself is not) |
| Azure Route Server | Not collected | real gap |
| Azure Web Application Firewall | Collected | `WafPolicies` |
| Azure Front Door | Collected | `Frontdoor` |
| Azure Network Function Manager | Not collected | real gap — telco-specific, likely low priority |
| Azure Virtual Network Manager | Not collected | real gap |
| Azure NAT Gateway | Collected | `NATGateway` |
| Azure Load Balancer | Collected | `LoadBalancer` |
| Azure Private Link | Collected | `PrivateEndpoint` |
| Azure Firewall Manager | Not collected | real gap — firewall policies specifically, distinct from `AzureFirewall` instances |
| Azure Network Watcher | Collected | `NetworkWatchers` |
| Azure Traffic Manager | Collected | `TrafficManager` |
| Azure Virtual Network | Collected | `VirtualNetwork`, `vNETPeering` |
| Azure Virtual WAN | Collected | `VirtualWAN` |
| Azure VPN Gateway | Collected | `VirtualNetworkGateways` |
| Azure Enclave | Not collected | real gap — confidential-computing networking, new |

We also collect `Connections`, `NetworkInterface`, `NetworkSecurityGroup`, `PublicIP` and
`RouteTables`, all genuine Networking resources Microsoft's product catalogue doesn't list as separate
"products" (they're sub-resources of Virtual Network there).

## Security

Source: [azure.microsoft.com/products?categories=security](https://azure.microsoft.com/en-us/products/?categories=security), fetched 2026-08-04 — 19 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Azure App Configuration | Collected (cross-category: DevOps) | `AppConfiguration` |
| Azure Application Gateway | Collected (cross-category: Networking) | `ApplicationGateways` |
| Microsoft Entra Domain Services | Collected | `EntraDomainServices` |
| Microsoft Defender for Cloud | Collected | `DefenderAlerts`, `DefenderAssessments`, `DefenderPricing`, `DefenderSecureScore` |
| Defender External Attack Surface Management | Not collected | real gap (also listed under Management and governance) |
| Azure Bastion | Collected (cross-category: Networking) | `BastionHosts` |
| Azure DDoS Protection | Collected | `DdosProtectionPlans` |
| Azure Cloud HSM | Collected | `CloudHSM` |
| Azure Firewall | Collected (cross-category: Networking) | `AzureFirewall` |
| Azure Firewall Manager | Not collected | real gap (also listed under Networking) |
| Azure Front Door | Collected (cross-category: Networking) | `Frontdoor` |
| Azure Information Protection | Not collected | real gap — no label/policy collector |
| Microsoft Sentinel | Collected | `Sentinel` |
| Azure Key Vault | Collected | `Vault`, `KeyVaultKeys`, `KeyVaultSecrets` |
| Azure confidential ledger | Collected | `ConfidentialLedger` |
| Azure VPN Gateway | Collected (cross-category: Networking) | `VirtualNetworkGateways` |
| Azure Web Application Firewall | Collected (cross-category: Networking) | `WafPolicies` |
| Microsoft Azure Attestation | Not collected | real gap |
| Microsoft Security Copilot | Not collected | real gap (also listed under AI + Machine Learning) |

We also collect `AppComplianceAutomation`, `ApplicationSecurityGroups`, `ManagedHSM` and `ArtifactSigning`
(`microsoft.codesigning/codesigningaccounts` — Azure Artifact Signing, formerly Trusted Signing), none
separately catalogued as products by Microsoft's Security page (Artifact Signing has its own product
page at [azure.microsoft.com/products/artifact-signing](https://azure.microsoft.com/en-us/products/artifact-signing)
but is not tagged into the `?categories=security` catalogue listing checked above).

## Storage

Source: [azure.microsoft.com/products?categories=storage](https://azure.microsoft.com/en-us/products/?categories=storage), fetched 2026-08-04 — 19 products.

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| Archive Storage | Collected (as a tier, not a resource) | `StorageAccounts` (tier is a property, not a separate resource type) |
| Azure Managed Lustre | Not collected | real gap — new (2024) HPC file system |
| Azure Backup | Collected (cross-category: Management) | `Backup`, `BackupInstances` |
| Azure Data Lake Storage | Collected (cross-category: Analytics) | `StorageAccounts` |
| Azure Data Share | Not collected | real gap (also listed under Analytics) |
| Azure Files | Collected | `FileShares` |
| Azure Storage Actions | Not collected | real gap — new (2024) storage task automation |
| Azure NetApp Files | Collected | `NetApp` |
| Azure Blob Storage | Collected | `BlobContainers` |
| Azure Data Box | Collected (cross-category: Migration) | `DataBox` |
| Azure Disk Storage | Collected | `VMDisk`, `Snapshots`, `DiskEncryptionSets` |
| Azure confidential ledger | Collected (cross-category: Security) | `ConfidentialLedger` |
| Azure Elastic SAN | Collected | `ElasticSan` |
| Queue Storage | Not collected | real gap — no `microsoft.storage/storageaccounts/queueservices` collector |
| Storage Accounts | Collected | `StorageAccounts` |
| Storage Explorer | N/A | a client tool, not an Azure resource |
| Azure Container Storage | Not collected | real gap (also listed under Containers) |
| Azure Storage Discovery | Not collected | real gap — new (2025) estate-wide storage insights service |
| Azure Storage Mover | Not collected | real gap (also listed under Hybrid + multicloud and Migration) |

We also collect `EdgeHardwareCenter`, `LifecyclePolicies`, `PartnerStorage`, and `StorageSync`, none
separately catalogued as products by Microsoft's Storage page.

## Web & Mobile

Source: [azure.microsoft.com/products?categories=web](https://azure.microsoft.com/en-us/products/?categories=web) and
[?categories=mobile](https://azure.microsoft.com/en-us/products/?categories=mobile), fetched 2026-08-04 —
14 Web products, 8 Mobile products, 15 distinct after dedup (Mobile is almost entirely a subset of Web,
plus "Azure AI Services").

| Microsoft service | Status | AzureScout collector |
|---|---|---|
| API Management | Collected (cross-category: Integration) | `APIM` |
| App Configuration | Collected (cross-category: DevOps) | `AppConfiguration` |
| App Service | Collected | `APPServices`, `APPServicePlan`, `DeploymentSlots`, `AppServiceEnvironments`, `AppServiceCertificates`, `AppServiceDomains` |
| Azure AI Search | Collected (cross-category: AI) | `SearchServices` |
| Azure Maps | Collected (cross-category: IoT) | `Maps` |
| Azure AI Services | Collected (cross-category: AI) | `AzureAI`, `AppliedAIServices` |
| Azure SignalR Service | Collected | `SignalR` |
| Azure Content Delivery Network | Not collected | real gap (also listed under Networking) |
| Notification Hubs | Collected | `NotificationHubs` |
| Static Web Apps | Collected | `StaticWebApps` |
| Azure Communication Services | Collected | `CommunicationServices` |
| Azure Web PubSub | Collected | `WebPubSub` |
| Azure Fluid Relay | Collected | `FluidRelay` |
| Microsoft Playwright Testing | Collected (cross-category: DevOps) | `PlaywrightTesting` |
| Azure Container Apps | Collected (cross-category: Containers) | `ContainerApp` |

We also collect `FunctionApps` and `SpringApps` under the `Web` folder, both cross-listed under Compute
in Microsoft's catalogue rather than Web.

## Summary of confirmed, unambiguous gaps

Every "real gap" row above was verified with `grep -ril` across `manifests/collectors/` for the relevant
resource-type string before being marked; none are guesses. The highest-value gaps — services that are
GA, not retiring, and have no collector anywhere in the estate — are:

- **Custom Locations** (`Microsoft.ExtendedLocation/customLocations`) — Hybrid
- **Arc-enabled VMware vSphere** (`Microsoft.ConnectedVMwarevSphere`) — Hybrid
- **Arc-enabled SCVMM** (`Microsoft.ScVmm`) — Hybrid
- **Azure Managed Grafana** (`Microsoft.Dashboard/grafana`) — DevOps / Management and governance
- **Azure Data Factory** (`Microsoft.DataFactory/factories`) — Analytics / Databases
- **Microsoft Fabric** — Analytics
- **Azure Content Delivery Network** (`Microsoft.Cdn/profiles`) — Networking / Web & Mobile
- **Azure Batch** (`Microsoft.Batch/batchAccounts`) — Compute
- **Azure Dedicated Host** (`Microsoft.Compute/dedicatedHosts`) — Compute
- **Azure Kubernetes Fleet Manager** (`Microsoft.ContainerService/fleets`) — Containers
- **Azure Site Recovery replication items** — Migration / Management and governance (the Recovery Vault
  container is collected; replication items are not)
