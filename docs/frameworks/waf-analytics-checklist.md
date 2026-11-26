# WAF — enumerated source for the Analytics technology review

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.analytics.yaml` scores the Analytics review. This page enumerates the Well-Architected guidance for Azure Databricks, Azure Event Hubs, Log Analytics and Microsoft Fabric, item by item. The rule file is written against this page only; every rule cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Analytics — Well-Architected Review](https://learn.microsoft.com/en-us/assessments/5eaa8702-ebdb-44cf-8b40-17c3f3b63330/) (question text not published) |
| Framework version | Azure Well-Architected Framework service guides for Azure Databricks, Event Hubs and Log Analytics (service-guide catalog, Analytics category) and Microsoft Fabric workload guidance, current at extraction |
| Extraction date | 2026-11-25 |
| Verification method | The service-guide catalog was fetched on 2026-11-25. The Event Hubs and Log Analytics guides were fetched in full. For the Azure Databricks guide the first 260 characters of every configuration-recommendation row were read (the workload design checklists were not), so Databricks items rest on the row titles and need a full re-read at the next recheck. The Fabric overview, reliability and security pages were read from search excerpts. The Fabric cost, operational-excellence and performance-efficiency pages were not read beyond the overview's one-line focus statements, so those items are summary-level and must be re-read at the next recheck. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The review's questions are not published. The items below are **Scout's** reading of the guides and the `WAF-ANALYTICS-*` ids are Scout's. Synapse, Data Factory, Purview, Data Explorer and the other Analytics resource types have no Well-Architected service guide in the catalog, so they are not scored here (they are scored by the CAF Analytics rules).

Sources (the code after each item names the page and section; -C is a workload design checklist bullet, -R a configuration recommendations row):

- [DBX] [Architecture best practices for Azure Databricks](https://learn.microsoft.com/azure/well-architected/service-guides/azure-databricks)
- [EH] [Architecture best practices for Azure Event Hubs](https://learn.microsoft.com/azure/well-architected/service-guides/event-hubs)
- [FAB] [Microsoft Fabric workloads](https://learn.microsoft.com/azure/well-architected/microsoft-fabric/overview) and its reliability, security, cost optimization, operational excellence and performance efficiency pages
- [LA] [Architecture best practices for Log Analytics](https://learn.microsoft.com/azure/well-architected/service-guides/azure-log-analytics)

Log Analytics workspaces now carry location, pricing tier, daily cap, public network access for ingestion and query, local-authentication and access-control flags and workspace replication; Event Hubs namespaces carry zone redundancy, public network access, auto-inflate, tier, capacity, throughput ceiling, geo-replica count, local-authentication, minimum TLS and key source; Databricks workspaces carry virtual network injection, no-public-IP and public network access. An absent boolean is `null` in the collection, and Newtonsoft JSONPath never matches a missing property with `==` or `!=` but does match a `null` value with `!=`, so rules where absence is itself the finding (local authentication on) are written as "is not the good value". Items that mixed a scorable check with something ARM does not carry (cluster settings, geo-DR pairing, table-level RBAC, ingestion alerts) were narrowed to the part that can be scored, and the row says what is left for a human.

## The enumeration — 74 items

### Reliability (WAF-ANALYTICS-RE) — 16 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ANALYTICS-RE-01 | Databricks clusters autoscale with a minimum of two nodes and a maximum within quota | ❌ Manual — cluster settings are workspace data plane; workspaces attached | DBX-RE-R |
| WAF-ANALYTICS-RE-02 | Mission-critical Databricks workloads run across regions with automated backup of code, jobs and cluster configuration | ❌ Manual — workspaces attached with region | DBX-RE-R |
| WAF-ANALYTICS-RE-03 | Cluster pools keep prewarmed instances across several VM sizes in a family | ❌ Manual — pool configuration is data plane | DBX-RE-R |
| WAF-ANALYTICS-RE-04 | Delta time travel retention and the Unity Catalog metastore are protected | ❌ Manual — data-plane configuration | DBX-RE-R |
| WAF-ANALYTICS-RE-05 | Jobs retry with backoff and streaming checkpoints sit on zone-redundant storage | ❌ Manual — job and checkpoint configuration, not ARM | DBX-RE-R |
| WAF-ANALYTICS-RE-06 | Event Hubs namespaces are zone redundant | ✅ namespace zoneRedundant | EH-RE-R |
| WAF-ANALYTICS-RE-07 | Geo-replication or geo-disaster recovery is configured for regional failure | ✅ `eventHubGeoDr` `geoDrConfigured` false and no geo-replication (`geoReplicaCount` above 1), joined by namespace id; gated on `eventHubGeoDrMeasured` | EH-RE-C, EH-RE-R |
| WAF-ANALYTICS-RE-08 | Capacity is planned: throughput units, partition count and auto-inflate suit the load | ❌ Manual — namespaces attached with tier, capacity, auto-inflate and throughput ceiling; the load and the partition count are not collected | EH-RE-C, EH-RE-R |
| WAF-ANALYTICS-RE-09 | Alerts cover consumer lag, throughput utilisation and throttling, tied to SLOs | ❌ Manual — metric alert rules attached (estate-wide) | EH-RE-R |
| WAF-ANALYTICS-RE-10 | The Log Analytics workspace is in a region with data resilience and co-located with the workload and its collection endpoints | ✅ `location` against the zone-region list, and `replicationEnabled`; where the workload and the collection endpoints run is not collected | LA-RE-R |
| WAF-ANALYTICS-RE-11 | Critical logs are multicast or exported so they survive a regional outage | ❌ Manual — data-collection routing, not collected per workspace | LA-RE-R |
| WAF-ANALYTICS-RE-12 | Data collection rules are single-purpose, and a daily cap with alerts and a retention policy protect ingestion | ❌ Manual — data collection rules attached; the daily cap is scored by WAF-ANALYTICS-CO-11 and retention by RE-13 | LA-RE-R |
| WAF-ANALYTICS-RE-13 | Workspace retention is at least 30 days | ✅ retentionInDays (Scout threshold of 30) | LA-RE-R |
| WAF-ANALYTICS-RE-14 | Workspace health alerts and Workspace Insights are in use | ❌ Manual — scheduled query rules attached (estate-wide) | LA-RE-R |
| WAF-ANALYTICS-RE-15 | Fabric capacity resilience is configured: disaster-recovery setting, dedicated capacities for critical work and surge protection | ❌ Manual — capacity settings are not ARM properties; capacities attached | FAB-RE |
| WAF-ANALYTICS-RE-16 | Fabric capacities are healthy | ✅ capacity state | FAB-RE |

### Security (WAF-ANALYTICS-SE) — 22 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ANALYTICS-SE-01 | Databricks workspaces use virtual network injection | ✅ workspace vnetInjected (a customer virtual network id is set) | DBX-SE-R |
| WAF-ANALYTICS-SE-02 | Databricks workspaces have a private endpoint | ✅ workspace to private endpoint join | DBX-SE-R |
| WAF-ANALYTICS-SE-03 | Databricks clusters use secure cluster connectivity (no public IPs) with SSH off | ✅ workspace noPublicIp (enableNoPublicIp); an absent value is a finding. SSH is not collected | DBX-SE-R |
| WAF-ANALYTICS-SE-04 | Identity uses Microsoft Entra SSO with MFA and Conditional Access, and OAuth or service principals instead of personal access tokens | ❌ Manual — identity policy is read from Microsoft Graph and the workspace, not this collection | DBX-SE-R |
| WAF-ANALYTICS-SE-05 | Unity Catalog governs data access across workspaces | ❌ Manual — data-plane governance | DBX-SE-R |
| WAF-ANALYTICS-SE-06 | Workspace storage uses customer-managed keys where required | ❌ Manual — the workspace encryption block is not projected; workspaces attached | DBX-SE-R |
| WAF-ANALYTICS-SE-07 | Secrets live in Key Vault-backed scopes | ❌ Manual — data-plane configuration | DBX-SE-R |
| WAF-ANALYTICS-SE-08 | IP access lists and egress controls limit network reach | ❌ Manual — IP access lists are workspace configuration, not collected; workspaces that accept public network access attached | DBX-SE-R |
| WAF-ANALYTICS-SE-09 | Audit logging, enhanced security and compliance settings and the Security Analysis Tool are in use | ❌ Manual — data-plane configuration | DBX-SE-R |
| WAF-ANALYTICS-SE-10 | Event Hubs namespaces have public network access disabled | ✅ namespace publicNetworkAccess | EH-SE-R |
| WAF-ANALYTICS-SE-11 | Event Hubs authorizes with Microsoft Entra ID and SAS is disabled where managed identities are available | ✅ disableLocalAuth; only an explicit true passes, so an absent flag (SAS on) is a finding | EH-SE-R |
| WAF-ANALYTICS-SE-12 | Event Hubs enforces TLS 1.2 or higher | ✅ minimumTlsVersion of 1.0 or 1.1 is a finding; an absent value is the platform default and is not flagged | EH-SE-R |
| WAF-ANALYTICS-SE-13 | Event Hubs data is encrypted with customer-managed keys (and double encryption) where required | ❌ Manual — customer-managed keys are requirement-driven (and need Premium or Dedicated); the namespaces whose key source is not Key Vault are attached as evidence | EH-SE-R |
| WAF-ANALYTICS-SE-14 | Event Hubs namespaces send diagnostic logs to Log Analytics | ✅ diagnostic-settings coverage for the namespace type | EH-SE-R |
| WAF-ANALYTICS-SE-15 | Event Hubs connection strings are in Key Vault, with short-lived SAS where SAS is unavoidable | ❌ Manual — secret handling, not ARM | EH-SE-R |
| WAF-ANALYTICS-SE-16 | Log Analytics access is limited to private networks and Microsoft Entra authentication | ✅ public network access for ingestion and query, and disableLocalAuth; an absent disableLocalAuth (keys accepted) is a finding | LA-SE-R |
| WAF-ANALYTICS-SE-17 | Workspace access control mode is resource or workspace permissions, with table-level RBAC where needed | ✅ resource-permissions access flag (workspace-only or absent is a finding); table-level RBAC is not collected | LA-SE-R |
| WAF-ANALYTICS-SE-18 | Customer-managed keys protect workspace data where required | ❌ Manual — the dedicated-cluster link that carries the key is not projected | LA-SE-R |
| WAF-ANALYTICS-SE-19 | Log Analytics workspaces send their own diagnostic and query-audit logs to a destination | ✅ diagnostic-settings coverage for the workspace type | LA-SE-R |
| WAF-ANALYTICS-SE-20 | Audit and compliance data is exported to immutable storage and sensitive log data is filtered or obfuscated | ❌ Manual — data-export rules and transformations are not collected | LA-SE-R |
| WAF-ANALYTICS-SE-21 | Fabric workspaces are isolated, with RBAC, workspace identity and managed identities | ❌ Manual — tenant and workspace settings are not ARM properties | FAB-SE |
| WAF-ANALYTICS-SE-22 | Fabric uses private links, managed private endpoints, Conditional Access and customer-managed keys where required | ❌ Manual — tenant settings are not ARM properties; capacities attached | FAB-SE |

### Cost optimization (WAF-ANALYTICS-CO) — 13 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ANALYTICS-CO-01 | Databricks compute is cost-governed: job clusters, autoscaling, auto-termination and compute policies | ❌ Manual — cluster settings are data plane; workspaces attached | DBX-CO-R |
| WAF-ANALYTICS-CO-02 | Serverless SQL warehouses and jobs, pools and Photon are used where they cut cost | ❌ Manual — data-plane configuration | DBX-CO-R |
| WAF-ANALYTICS-CO-03 | Databricks reserved capacity covers predictable usage | ❌ Manual — reservations attached | DBX-CO-R |
| WAF-ANALYTICS-CO-04 | No Databricks workspace runs on the trial SKU | ✅ workspace sku (trial only; Standard versus Premium is judgement) | DBX-CO-R |
| WAF-ANALYTICS-CO-05 | Databricks cost is monitored with system tables, Cost Management budgets and tags | ❌ Manual — budgets attached (estate-wide) | DBX-CO-R |
| WAF-ANALYTICS-CO-06 | Delta tables are optimised and vacuumed on a schedule and data formats are efficient | ❌ Manual — data-plane maintenance | DBX-CO-R |
| WAF-ANALYTICS-CO-07 | Event Hubs tier, throughput, auto-inflate maximum and retention suit the workload | ❌ Manual — with evidence: each event hub's retention and whether Capture is on (`domains.integration.eventHubEntities`), beside the namespaces' tier, capacity and auto-inflate ceiling; whether they suit the workload is not collected | EH-CO-R |
| WAF-ANALYTICS-CO-08 | Event Hubs has budgets, policy limits and shutdown automation for non-production | ❌ Manual — budgets attached (estate-wide) | EH-CO-R |
| WAF-ANALYTICS-CO-09 | Log Analytics uses a commitment tier or dedicated cluster where volume justifies it | ❌ Manual — workspaces attached with pricing tier and daily cap; ingestion volume is a metric, not collected | LA-CO-R |
| WAF-ANALYTICS-CO-10 | Retention, archive, Basic logs and summary rules keep long-term log cost down | ❌ Manual — table plans are not collected | LA-CO-R |
| WAF-ANALYTICS-CO-11 | A daily cap guards against runaway cost | ✅ dailyQuotaGb (-1 or absent means no cap); the high-ingestion alerts are not tied to a workspace and are not scored | LA-CO-R |
| WAF-ANALYTICS-CO-12 | Microsoft Sentinel logs are in a separate workspace | ❌ Manual — Sentinel workspaces attached | LA-CO-R |
| WAF-ANALYTICS-CO-13 | Fabric capacity is sized to the workload, shared deliberately, paused or scaled by automation and monitored for utilisation | ❌ Manual — utilisation is not collected; capacities attached | FAB-CO |

### Operational excellence (WAF-ANALYTICS-OE) — 13 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ANALYTICS-OE-01 | Databricks workspaces are deployed with ARM or Bicep, with environment parameters | ❌ Manual — deployment method is not an ARM property | DBX-OE-R |
| WAF-ANALYTICS-OE-02 | Notebooks and code are in Git with CI/CD | ❌ Manual — practice, not ARM | DBX-OE-R |
| WAF-ANALYTICS-OE-03 | Databricks diagnostic settings send platform, audit and cluster logs to Log Analytics with alert rules | ✅ diagnostic-settings coverage for the Databricks workspace type (a setting present; categories and alert rules are not read) | DBX-OE-R |
| WAF-ANALYTICS-OE-04 | Pipelines enforce data-quality expectations, and workspace artefacts are backed up | ❌ Manual — data-plane practice | DBX-OE-R |
| WAF-ANALYTICS-OE-05 | Cluster lifecycle policies and environment-specific RBAC separate development, test and production | ❌ Manual — workspace configuration | DBX-OE-R |
| WAF-ANALYTICS-OE-06 | Event Hubs namespaces and hubs are deployed as code through staged pipelines | ❌ Manual — deployment method is not an ARM property | EH-OE-R |
| WAF-ANALYTICS-OE-07 | Event Hubs has dashboards, correlation-aware logging and runbook workbooks | ❌ Manual — workbooks attached (estate-wide) | EH-OE-R |
| WAF-ANALYTICS-OE-08 | Azure Policy enforces Event Hubs diagnostics, retention and network restrictions, and load tests precede release | ❌ Manual — policy and test practice, not collected per namespace | EH-OE-R |
| WAF-ANALYTICS-OE-09 | Log Analytics workspace architecture is deliberate: number, placement and production versus non-production separation | ❌ Manual — workspaces attached for counting | LA-OE-R |
| WAF-ANALYTICS-OE-10 | Log Analytics workspaces are deployed as code, through pipelines, with Azure Policy enforcing standards | ❌ Manual — deployment method is not an ARM property | LA-OE-R |
| WAF-ANALYTICS-OE-11 | Workspace health is monitored with Workspace Insights and operation-table alerts | ❌ Manual — scheduled query rules attached (estate-wide) | LA-OE-R |
| WAF-ANALYTICS-OE-12 | Workspaces are treated as static and protected from deletion | ❌ Manual — resource locks attached (estate-wide) | LA-OE-R |
| WAF-ANALYTICS-OE-13 | Fabric uses deployment pipelines, Git, automated testing, progressive rollout and workspace monitoring | ❌ Manual — tenant and workspace practice, not ARM | FAB-OE |

### Performance efficiency (WAF-ANALYTICS-PE) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ANALYTICS-PE-01 | Databricks cluster types and autoscale bounds match the workload | ❌ Manual — cluster settings are data plane; workspaces attached | DBX-PE-R |
| WAF-ANALYTICS-PE-02 | Delta tables are optimised, clustered and cached; Photon and adaptive query execution are on | ❌ Manual — data-plane configuration | DBX-PE-R |
| WAF-ANALYTICS-PE-03 | Serverless SQL warehouses serve BI and interactive queries, and streaming triggers match latency needs | ❌ Manual — data-plane configuration | DBX-PE-R |
| WAF-ANALYTICS-PE-04 | Event Hubs tier and partition count suit throughput and retention needs | ❌ Manual — with evidence: each event hub's partition count (`domains.integration.eventHubEntities`) beside the namespaces' tier and capacity; throughput needs are not collected | EH-PE-R |
| WAF-ANALYTICS-PE-05 | Standard namespaces have auto-inflate enabled | ✅ Standard tier with auto-inflate not on; Premium and Dedicated scaling is not collected | EH-PE-R |
| WAF-ANALYTICS-PE-06 | Producers and consumers are tuned: batching, prefetch, connection reuse and consumer groups | ❌ Manual — client code, not ARM | EH-PE-R |
| WAF-ANALYTICS-PE-07 | The Log Analytics workspace and its collection endpoints are deployed close to the workload | ❌ Manual — collection endpoints attached; workspace regions are on WAF-ANALYTICS-RE-10, the workload region is not collected | LA-PE-R |
| WAF-ANALYTICS-PE-08 | Slow queries are found with query auditing and data collection rules are split for performance and events | ❌ Manual — data collection rules attached | LA-PE-R |
| WAF-ANALYTICS-PE-09 | Service limits are reviewed and extra workspaces used where limits bind | ❌ Manual — quota values are not collected | LA-PE-R |
| WAF-ANALYTICS-PE-10 | Fabric capacities are right-sized, heavy workloads isolated, and queries, pipelines and refresh optimised | ❌ Manual — utilisation is not collected; capacities attached | FAB-PE |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 16 | 5 | 11 |
| Security | 22 | 10 | 12 |
| Cost optimization | 13 | 2 | 11 |
| Operational excellence | 13 | 1 | 12 |
| Performance efficiency | 10 | 1 | 9 |
| **Total** | **74** | **19** | **55** |

Every automated item is gated on its resources (or its diagnostic-coverage rows) existing, so an estate
without them reports the item Not assessed. The rules live in `src/assess/rules/waf.analytics.yaml`.
