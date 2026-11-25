# WARA — enumerated source for the Well-Architected Reliability Assessment (APRL-backed)

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Microsoft's Well-Architected Reliability Assessment (WARA) is an automated review of a workload's
reliability. Its tooling runs the Azure Resource Graph queries that the Azure Proactive Resiliency
Library (APRL) publishes for each Azure resource type, and turns the hits into an action plan.
`src/assess/rules/wara.reliability.yaml` does the same job from the data Scout has **already
collected** into `collect.json`, so it needs no extra Azure call and no extra permission. It is
written against this page only, and every rule cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Source page | [Azure Proactive Resiliency Library v2](https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2) (site: [aka.ms/aprl](https://azure.github.io/Azure-Proactive-Resiliency-Library-v2/)); [Well-Architected Reliability Assessment tooling](https://github.com/Azure/Well-Architected-Reliability-Assessment); [Reliability guides by service](https://learn.microsoft.com/azure/reliability/overview-reliability-guidance) |
| Framework version | APRL v2, `main` branch, as read on the extraction date (no release tags are published for APRL); WARA module release v1.0.6 (2025-05-22). Neither is versioned per recommendation, so the extraction date is the version. |
| Extraction date | 2026-11-25 |
| Verification method | For each resource type below, the `recommendations.yaml` under `azure-resources/<Provider>/<type>/` and the file listing of its `kql/` folder were read through the GitHub contents API and `raw.githubusercontent.com` on 2026-11-25; an `aprlGuid` is cited only after its `<guid>.kql` file name was seen in that folder's listing. The conditions are Scout's paraphrase, checked against the APRL query's described behaviour for VM zones, storage SKUs, VPN gateway SKUs, App Service tiers and SQL zone redundancy. Current-state claims (Application Gateway v1 retirement, VPN gateway non-AZ SKU retirement) were read from Microsoft Learn on the same date. The zone, tier, HA-mode, autoscale and instance-count items read fields that AB#9300 phase 4 added to `collect.json` (their names are in the header of `src/collect/Invoke-Collect.ps1`); a null count there means the resource has no such array, which Scout reads as "none". Rules were NOT run against a live tenant for this page. |

## Is APRL current, or has it been merged into something else?

Checked 2026-11-25, and **no, it has not been merged or retired**:

- The APRL repository (`Azure/Azure-Proactive-Resiliency-Library-v2`) is **not archived**, is licensed
  **MIT**, describes itself as the "source for Azure WAF reliability guidance and associated ARG
  queries", and was last pushed on 2026-11-23. Its README sends readers to the GitHub Pages site
  (`aka.ms/aprl`) unless they want to contribute. No deprecation or merge notice was found.
- The WARA tooling repository (`Azure/Well-Architected-Reliability-Assessment`) is **not archived**,
  is MIT licensed, and was last pushed on 2026-11-23. Its module has three commands:
  `Start-WARACollector`, `Start-WARAAnalyzer` and `Start-WARAReport`. The collector needs
  PowerShell 7.4 and the Az modules; the report step needs Windows with PowerPoint.
- Microsoft Learn's prose side of the same material is the
  [reliability guides by service](https://learn.microsoft.com/azure/reliability/overview-reliability-guidance)
  index (dozens of services, each with production-deployment, zone-failure, region-failure and
  maintenance sections). APRL recommendations link to those guides; the guides did not absorb APRL.
- Learn's [Reliability in Azure](https://learn.microsoft.com/azure/reliability/overview) page now also
  points at AI-assisted reliability services (Azure Resiliency capabilities, a resiliency agent in
  Azure Copilot, Azure SRE Agent). These sit alongside APRL; none of them replaces its query library.
- Azure Advisor's reliability recommendations overlap with APRL (some APRL items carry an
  Advisor `recommendationTypeId`), which is why the WARA module "uses outputs from the Azure
  Well-Architected Framework and Azure Advisor". Scout scores Advisor separately in
  [advisor-recommendations.md](advisor-recommendations.md).

## The one thing this enumeration is NOT

**It is not APRL, and it is not Microsoft's WARA score.** APRL holds a large number of recommendations
across more than 100 provider folders, most of them about configuration Scout does not collect (child
resources, metrics, Kubernetes objects, guest settings) or about application behaviour (retries,
connection reuse) that no inventory can see. This page covers the subset whose condition maps to a
property Scout collects, plus two Manual items (WARA-SQL-02, WARA-ER-02) that attach the nearest evidence. APRL's
own queries also differ in two ways Scout cannot match today: they filter to a region list that has
availability zones, and they read properties Scout's slimmer projections omit. Where Scout is coarser,
the rule's remediation says so.

APRL is MIT licensed. Nothing here is copied from it: titles and remediation are Scout's wording, and
each item cites the APRL recommendation it paraphrases by `aprlGuid` and repository folder. The
`aprlGuid` is also the file name of the recommendation's query (`kql/<aprlGuid>.kql`), so a reader can
check any item against the source. Folder URLs are of the form
`https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2/tree/main/azure-resources/<Provider>/<type>`.

## The enumeration — 38 items (36 automated, 2 manual)

Every item is **gated** on its own resource type existing: an estate without that service reports it
Not assessed, never passed. "Impact" is APRL's own rating for the recommendation; "Severity" is what
Scout's rule uses, lowered where the condition cannot tell production from test.

### Compute (APRL `Compute/virtualMachines`, `Compute/virtualMachineScaleSets`) — 8 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-VM-01 | Virtual machines in a zone-capable region are deployed to a zone | ✅ `compute.virtualMachines` `zoneEligible` / `zoneRedundant` | High | `2bd0be95-a825-6f47-a8c6-3db1fb5eb387` |
| WARA-VM-02 | Every virtual machine has an Azure Backup protected item | ✅ join `compute.virtualMachines.id` to `management.backupProtectedItems.sourceResourceId` | Medium | `1981f704-97b9-b645-9c57-33f8ded9261a` |
| WARA-VM-03 | Production virtual machines are not burstable B-series | ✅ `compute.virtualMachines` `size` | High | `3201dba8-d1da-4826-98a4-104066545170` |
| WARA-VM-04 | Virtual machines are not in an availability set (move to zones) | ✅ `compute.virtualMachines` `inAvailabilitySet` | High | `a8d25876-7951-b646-b4e8-880c9031596b` |
| WARA-VM-05 | Operating system disks are managed disks | ✅ `compute.virtualMachines` `unmanagedOsDisk` (a bool; the VHD uri is never collected) | High | `122d11d7-b91f-8747-a562-f56b79bcfbdc` |
| WARA-DSK-01 | Attached disks are Premium SSD or better where the workload needs the higher SLA | ✅ `domains.storage.managedDisks` `diskState`, `sku` | High (APRL); Medium (Scout) | `df0ff862-814d-45a3-95e4-4fad5a244ba6` |
| WARA-VMSS-01 | Scale sets are spread across availability zones (`zoneCount < 1`; regions without zones are false positives) | ✅ `compute.virtualMachineScaleSets` `zoneCount` | High | `1422c567-782c-7148-ac7c-5fc14cf45adc` |
| WARA-VMSS-02 | Automatic instance repairs are on | ✅ `virtualMachineScaleSets` `automaticRepairs` (null reads as off) | High | `820f4743-1f94-e946-ae0b-45efafd87962` |

### Containers (APRL `ContainerService/managedClusters`, `ContainerRegistry/registries`) — 4 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-AKS-01 | Every AKS node pool spans availability zones | ✅ `domains.containers.aksClusters` `allPoolsZoned` | High | `4f63619f-5001-439c-bacb-8de891287727` |
| WARA-AKS-02 | AKS uses Microsoft Entra ID integration, not local accounts | ✅ `aksClusters` `aadIntegrated` | High | `ca324d71-54b0-4a3e-b9e4-10e767daa9fc` |
| WARA-AKS-03 | Production clusters are Standard or Premium tier, autoscale, and keep three system nodes | ✅ `aksClusters` `tier` (empty reads as Free), `systemPoolMinNodes` < 3, `allPoolsAutoscale` false | High | `0611251f-e70f-4243-8ddd-cfe894bec2e7` |
| WARA-ACR-01 | Production container registries are Premium (zone redundancy, geo-replication) | ✅ `domains.containers.containerRegistries` `sku` | High (APRL); Medium (Scout) | `eb005943-40a8-194b-9db2-474d430046b7` |

### Web (APRL `Web/serverFarms`) — 2 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-ASP-01 | App Service plans are Standard, Premium or Isolated tier | ✅ `domains.web.appServicePlans` `sku` (Free, Shared and Basic flagged) | High | `b2113023-a553-2e41-9789-597e2fb54c31` |
| WARA-ASP-02 | Standard-and-above plans are zone redundant and run two or more instances | ✅ `appServicePlans` `tier`, `zoneRedundant`, `instanceCount` (Free, Shared, Basic and consumption are left to WARA-ASP-01) | High | `88cb90c2-3b99-814b-9820-821a63f600dd` |

### Databases and caches — 6 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-SQL-01 | Azure SQL databases are zone redundant | ✅ `domains.databases.sqlDatabases` `zoneRedundant` (`master` excluded) | High | `c0085c32-84c0-c247-bfa9-e70977cbf108` |
| WARA-SQL-02 | Critical SQL databases are geo-replicated or in a failover group | ❌ Manual — SQL servers attached; replicas are child resources | High | `74c2491d-048b-0041-a140-935960220e20` |
| WARA-COSMOS-01 | Cosmos DB spans more than one region and uses zones | ✅ `cosmosDbAccounts` `regionCount` < 2 or `zoneRedundantRegionCount` < 1 (JSONPath cannot compare the two counts, and automatic failover is not scored) | High | `43663217-a1d3-844b-80ea-571a2ce37c6c` |
| WARA-REDIS-01 | Redis caches are zone redundant (Premium or Enterprise) | ✅ `redisCaches` classic: `zoneCount` < 2 and `zonalAllocationPolicy` not Automatic; Enterprise: `highAvailability` Disabled | High | `5a44bd30-ae6a-4b81-9b68-dc3a8ffca4d8` |
| WARA-PGSQL-01 | PostgreSQL flexible servers use zone-redundant high availability | ✅ `postgreSqlFlexibleServers` `haMode` not ZoneRedundant | High | `ca87914f-aac4-4783-ab67-82a6f936f194` |
| WARA-MYSQL-01 | MySQL flexible servers use zone-redundant high availability | ✅ `mySqlFlexibleServers` `haMode` not ZoneRedundant | High | `88856605-53d8-4bbd-a75b-4a7b14939d32` |

### Storage and Key Vault (APRL `Storage/storageAccounts`, `KeyVault/vaults`) — 3 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-STG-01 | Storage accounts use zone or geo redundancy, not LRS | ✅ `domains.storage.storageAccounts` `sku` (ends `_LRS`) | High | `e6c7e1cc-2f47-264d-aa50-1da421314472` |
| WARA-KV-01 | Key Vault soft delete is on (only an explicit `false` is a finding) | ✅ `domains.security.keyVaults` `softDelete` | High | `1cca00d2-d9ab-8e42-a788-5d40f49405cb` |
| WARA-KV-02 | Key Vault purge protection is on | ✅ `keyVaults` `purgeProtection` | Medium | `70fcfe6d-00e9-5544-a63a-fff42b9f2edb` |

### Backup vaults (APRL `RecoveryServices/vaults`) — 2 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-RSV-01 | Vault soft delete is not disabled | ✅ `management.recoveryVaults` `softDelete` | Medium | `9e39919b-78af-4a0b-b70f-c548dae97c25` |
| WARA-RSV-02 | Geo-redundant vaults have cross-region restore on | ✅ `recoveryVaults` `storageType`, `crossRegion` | Medium | `1549b91f-2ea0-4d4f-ba2a-4596becbe3de` |

### Networking (APRL `Network/*`) — 11 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-LB-01 | Load balancers use the Standard SKU | ✅ `networking.loadBalancers` `sku` | High | `38c3bca1-97a1-eb42-8cd3-838b243f35ba` |
| WARA-LB-02 | Standard load balancer frontends are zone redundant (internal frontends are the reliable signal; a public frontend takes its zones from its public IP) | ✅ `loadBalancers` `minFrontendZoneCount` < 2 | High | `621dbc78-3745-4d32-8eac-9e65b27b7512` |
| WARA-PIP-01 | Standard public IPs are zone redundant | ✅ `networking.publicIPAddresses` `skuName`, `zoneCount` < 2 | High | `c63b81fb-7afc-894c-a840-91bb8a8dcfaf` |
| WARA-PIP-02 | No Basic public IPs | ✅ `publicIPAddresses` `skuName` | Medium | `5cea1501-6fe4-4ec4-ac8f-f72320eb18d3` |
| WARA-AGW-01 | Application gateways use v2 (v1 retired 2026-04-28) | ✅ `networking.applicationGateways` `tier` | High | `7893f0b3-8622-1d47-beed-4b50a19f7895` |
| WARA-AGW-02 | Application gateways span zones and autoscale | ✅ `applicationGateways` `zoneCount` < 2 or `autoscaleMax` null (v1 gateways also appear here) | High | `c9c00f2a-3888-714b-a72b-b4c9e8fcffb2` |
| WARA-VPN-01 | VPN gateways use zone-redundant (AZ) SKUs | ✅ `networking.vpnGateways` `gatewayType`, `sku` | High | `5b1933a6-90e4-f642-a01f-e58594e5aab2` |
| WARA-VPN-02 | VPN gateways run active-active (non-Basic) | ✅ `vpnGateways` `activeActive` | Medium | `281a2713-c0e0-3c48-b596-19f590c46671` |
| WARA-ER-01 | ExpressRoute gateways use zone-redundant (AZ) SKUs | ✅ `vpnGateways` where `gatewayType` is ExpressRoute | High | `bbe668b7-eb5c-c746-8b82-70afdedf0cae` |
| WARA-ER-02 | ExpressRoute uses two circuits at different peering locations | ❌ Manual — circuits attached with provider and location | High | `4d703025-dafc-f840-a183-5dc440456134` |
| WARA-FW-01 | Azure Firewalls are deployed across availability zones | ✅ `networking.azureFirewalls` `zoneCount` < 2 | High | `c72b7fee-1fa0-5b4b-98e5-54bcae95bb74` |

### Integration (APRL `ApiManagement/service`, `EventHub/namespaces`) — 2 items

| # | Item | Scout | APRL impact | aprlGuid |
|---|---|---|---|---|
| WARA-APIM-01 | Instances that need zone redundancy are Premium (Developer, Basic, Standard flagged) | ✅ `domains.integration.apiManagement` `sku` | High (APRL); Medium (Scout) | `baf3bfc0-32a2-4c0c-926d-c9bf0b49808e` |
| WARA-EH-01 | Event Hubs namespaces are zone redundant | ✅ `domains.integration.eventHubNamespaces` `zoneRedundant` | High | `84636c6c-b317-4722-b603-7b1ffc16384b` |

## Needs a new projection — recognised, not yet scored

This APRL item is still waiting for a projection: Scout's `collect.json` does not carry the dataset or
property, so **no rule exists** (a rule on a missing property would score nothing). The id is reserved
here so a rule can be added with the projection. (Seven items that used to be listed here, WARA-VM-04,
WARA-VM-05, WARA-VMSS-01, WARA-VMSS-02, WARA-PIP-01, WARA-PIP-02 and WARA-LB-02, became rules when
AB#9300 phase 4 added their fields.) "Verified" means the property path
was checked against Microsoft Learn or the APRL query description; none was confirmed against live
Resource Graph output for this page.

| Reserved id | Item (APRL) | Dataset and property needed | aprlGuid |
|---|---|---|---|
| WARA-VM-06 | Disks replicated to another region by Site Recovery (Medium) | `recoveryservicesresources` replication protected items | `cfe22a65-b1db-fd41-9e8e-d573922709ae` |

## How null and missing values are read

A count Resource Graph reports as null (for example `zoneCount` on a resource with no `zones` array)
means "none", and a null or empty `haMode`, `tier` or `zonalAllocationPolicy` is read the way ARM
defaults it (HA Disabled, AKS tier Free, no zonal allocation). JSONPath compares null as lower than any
number, so `zoneCount < 2` lists both 0 and null. A property that is missing from the row altogether
matches no comparison, so a missing key is never listed; Scout always writes the key.

Two rules (WARA-ASP-02 and WARA-REDIS-01) mix `&&` and `||` in one filter. Newtonsoft JSONPath has no
parentheses and nests the later operator to the right, so `a && b || c` reads `a && (b || c)` and
`a || b && c` reads `a || (b && c)`. `tests/Assessment.WaraAdvisor.Tests.ps1` pins both results.

## What a "Not assessed" or "Manual" result means here

- **Not assessed** — the resource type is absent from the collected estate (or its dataset was not
  collected). Nothing was checked.
- **Manual** — Scout found resources of that type and attached them as evidence, but the property that
  decides the question is not collected. Open each listed resource and answer the item by hand.
- **Pass / Fail** — the property was collected and the condition was evaluated for every listed
  resource. A Fail names the resources; read the remediation for the exceptions Scout cannot see
  (non-zone regions, test environments).
