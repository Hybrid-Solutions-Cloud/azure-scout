# WAF — enumerated source for the Data Services technology review

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.dataservices.yaml` scores the Data Services review. This page enumerates the Well-Architected service guides for Azure SQL Database, SQL Managed Instance, Cosmos DB, Database for PostgreSQL, Database for MySQL, Azure Managed Redis, Azure HorizonDB and Blob Storage, item by item. The rule file is written against this page only; every rule cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Data Services — Well-Architected Review](https://learn.microsoft.com/en-us/assessments/azure-architecture-review-data/) (question text not published) |
| Framework version | Azure Well-Architected Framework service guides for the Databases category plus Azure Blob Storage, current at extraction (Azure Managed Redis added October 2026) |
| Extraction date | 2026-11-25 |
| Verification method | The service-guide catalog was fetched on 2026-11-25. The Azure SQL Database and Azure Cosmos DB guides were fetched in full; the PostgreSQL, SQL Managed Instance, Azure Managed Redis, Azure HorizonDB, MySQL and Blob Storage guides were read through the Microsoft Learn MCP search excerpts of their configuration-recommendation tables. Rows not returned by those excerpts are summarised, mainly the SQL Managed Instance reliability, cost and performance sections, the MySQL reliability section beyond its first row, the Blob Storage cost, operations and performance sections, and the Azure Managed Redis tradeoffs. Re-read the full pages at the next recheck. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The review's questions are not published. The items below are **Scout's** reading of the guides and the `WAF-DATA-*` ids are Scout's. The Cosmos DB guide covers the NoSQL API only; the MySQL guide covers flexible server (single server is retired).

Sources (the code after each item names the page and section; -C is a workload design checklist bullet, -R a configuration recommendations row):

- [AMR] [Architecture best practices for Azure Managed Redis](https://learn.microsoft.com/azure/well-architected/service-guides/azure-managed-redis)
- [BLOB] [Architecture best practices for Azure Blob Storage](https://learn.microsoft.com/azure/well-architected/service-guides/azure-blob-storage) and [Security recommendations for Blob storage](https://learn.microsoft.com/azure/storage/blobs/security-recommendations) (code S)
- [COS] [Architecture best practices for Azure Cosmos DB for NoSQL](https://learn.microsoft.com/azure/well-architected/service-guides/cosmos-db)
- [HZ] [Architecture best practices for Azure HorizonDB](https://learn.microsoft.com/azure/well-architected/service-guides/azure-horizondb)
- [MI] [Architecture best practices for Azure SQL Managed Instance](https://learn.microsoft.com/azure/well-architected/service-guides/azure-sql-managed-instance/reliability) (security section read; other pillars summarised)
- [MYS] [Architecture best practices for Azure Database for MySQL](https://learn.microsoft.com/azure/well-architected/service-guides/azure-database-for-mysql) and its [cost optimization](https://learn.microsoft.com/azure/well-architected/service-guides/azure-db-mysql-cost-optimization) page
- [PG] [Architecture best practices for Azure Database for PostgreSQL](https://learn.microsoft.com/azure/well-architected/service-guides/postgresql)
- [SQL] [Architecture best practices for Azure SQL Database](https://learn.microsoft.com/azure/well-architected/service-guides/azure-sql-database)

Collected datasets map as follows: `domains.databases.sqlServers`, `sqlDatabases`, `sqlManagedInstances`, `cosmosDbAccounts`, `postgreSqlFlexibleServers`, `mySqlFlexibleServers`, `redisCaches` (Azure Managed Redis is `microsoft.cache/redisenterprise`; the classic cache shares the dataset) and `domains.storage.storageAccounts`. Azure HorizonDB is not collected, so its items are manual.

## The enumeration — 100 items

### Azure SQL Database (WAF-DATA-SQL) — 18 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-SQL-01 | Reliability | SQL databases are zone redundant | ✅ database zoneRedundant (master excluded) | SQL-RE-R |
| WAF-DATA-SQL-02 | Reliability | Active geo-replication or failover groups protect against a regional failure | ❌ Manual — failover groups and replica links are child resources, not collected (proposed in the report); servers attached | SQL-RE-C, SQL-RE-R |
| WAF-DATA-SQL-03 | Reliability | Backups cover point-in-time restore, geo-restore and long-term retention, with immutability | ❌ Manual — backup policy is a child resource, not collected | SQL-RE-R |
| WAF-DATA-SQL-04 | Reliability | Critical databases use the Business Critical or Hyperscale tier | ❌ Manual — the tier of each database is attached; which are critical is judgement | SQL-RE-C |
| WAF-DATA-SQL-05 | Reliability | Applications retry with backoff and isolate connection pools by function | ❌ Manual — client code, not ARM | SQL-RE-C, SQL-RE-R |
| WAF-DATA-SQL-06 | Security | SQL servers have public network access disabled | ✅ server publicNetworkAccess | SQL-SE-R |
| WAF-DATA-SQL-07 | Security | Each SQL server has a private endpoint | ❌ Manual — server id is not projected (proposed in the report); private endpoints attached | SQL-SE-R |
| WAF-DATA-SQL-08 | Security | The minimum TLS version is 1.2 or higher | ❌ Manual — minimalTlsVersion is not collected (proposed in the report); servers attached | SQL-SE-R |
| WAF-DATA-SQL-09 | Security | SQL authentication is disabled and Microsoft Entra-only authentication is on | ❌ Manual — the Entra-only flag is not collected (proposed in the report); servers attached | SQL-SE-R |
| WAF-DATA-SQL-10 | Security | Microsoft Defender for SQL is on Standard | ✅ subscription Defender for SQL tier | SQL-SE-R |
| WAF-DATA-SQL-11 | Security | Auditing is on with immutable storage, and sensitive data is protected with Always Encrypted or ledger | ❌ Manual — auditing and column encryption are not collected | SQL-SE-R |
| WAF-DATA-SQL-12 | Cost optimization | The service tier, serverless and elastic pools match each database's use | ❌ Manual — elastic pools attached; databases are in the reliability item | SQL-CO-R |
| WAF-DATA-SQL-13 | Cost optimization | Reserved capacity and Azure Hybrid Benefit are used for steady workloads | ❌ Manual — reservations attached | SQL-CO-R |
| WAF-DATA-SQL-14 | Cost optimization | Backup storage consumption is tuned and queries are optimised to cut resource use | ❌ Manual — metrics, not ARM | SQL-CO-R |
| WAF-DATA-SQL-15 | Operational excellence | SQL databases send diagnostics to Log Analytics | ✅ diagnostic-settings coverage for the database type | SQL-OE-R |
| WAF-DATA-SQL-16 | Operational excellence | SQL projects deploy through CI/CD and servers are backed up with Azure Backup | ❌ Manual — practice, not ARM | SQL-OE-R |
| WAF-DATA-SQL-17 | Performance efficiency | Query Store, automatic tuning and performance recommendations are enabled and acted on | ❌ Manual — database-scoped configuration, not collected | SQL-PE-R |
| WAF-DATA-SQL-18 | Performance efficiency | The vCore model, read scale-out and connection pooling are used | ❌ Manual — databases attached | SQL-PE-C, SQL-PE-R |

### Azure SQL Managed Instance (WAF-DATA-MI) — 11 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-MI-01 | Reliability | Managed instances are zone redundant and covered by failover groups | ❌ Manual — zoneRedundant and failover groups are not collected (proposed in the report); instances attached | MI-RE |
| WAF-DATA-MI-02 | Reliability | Backups meet RPO, including geo-redundancy where policy allows | ❌ Manual — backup settings are not collected | MI-RE |
| WAF-DATA-MI-03 | Security | The public data endpoint is off | ✅ publicDataEndpointEnabled | MI-SE |
| WAF-DATA-MI-04 | Security | Cross-network access uses private endpoints | ❌ Manual — private endpoints attached | MI-SE |
| WAF-DATA-MI-05 | Security | Microsoft Entra-only authentication and a user-assigned identity are used | ❌ Manual — the setting is not collected (proposed in the report); instances attached | MI-SE |
| WAF-DATA-MI-06 | Security | TDE uses customer-managed keys in a Key Vault with soft delete and purge protection | ❌ Manual — the protector configuration is not collected; Key Vaults attached | MI-SE |
| WAF-DATA-MI-07 | Security | Defender for SQL is on, SQL Agent is off if unused, and the subnet NSG denies by default | ❌ Manual — agent, NSG and subnet detail are not collected per instance | MI-SE |
| WAF-DATA-MI-08 | Security | Server and operator auditing go to blob storage and Azure Monitor logs | ❌ Manual — type not yet in the diagnostic-settings sweep (proposed in the report) | MI-SE |
| WAF-DATA-MI-09 | Cost optimization | vCores and service tier are right-sized, with reservations and Azure Hybrid Benefit | ❌ Manual — instances attached with sku and vCores | MI-CO |
| WAF-DATA-MI-10 | Operational excellence | Maintenance windows and the update policy are chosen deliberately | ❌ Manual — maintenance configurations attached (estate-wide) | MI-OE |
| WAF-DATA-MI-11 | Performance efficiency | The service tier, vCores and storage are validated against the workload | ❌ Manual — instances attached | MI-PE |

### Azure Cosmos DB (WAF-DATA-COS) — 17 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-COS-01 | Reliability | Cosmos DB accounts are distributed across availability zones | ❌ Manual — the per-region isZoneRedundant flag is not collected (proposed in the report); accounts attached | COS-RE-R |
| WAF-DATA-COS-02 | Reliability | Accounts span at least two regions | ❌ Manual — the locations list is not collected (proposed in the report); accounts attached | COS-RE-R |
| WAF-DATA-COS-03 | Reliability | Service-managed failover is enabled | ❌ Manual — enableAutomaticFailover is not collected (proposed in the report); accounts attached | COS-RE-R |
| WAF-DATA-COS-04 | Reliability | Continuous backup with point-in-time restore is configured | ❌ Manual — the backup policy type is not collected (proposed in the report); accounts attached | COS-RE-C |
| WAF-DATA-COS-05 | Security | Cosmos DB accounts have public network access disabled | ✅ account publicNetworkAccess | COS-SE-R |
| WAF-DATA-COS-06 | Security | Each Cosmos DB account has a private endpoint | ✅ account to private endpoint join | COS-SE-R |
| WAF-DATA-COS-07 | Security | Key-based (local) authentication is disabled in favour of Microsoft Entra ID | ✅ disableLocalAuth | COS-SE-R |
| WAF-DATA-COS-08 | Security | Access is limited by RBAC at control and data plane, with virtual network rules and NSGs | ❌ Manual — network rules are not collected (proposed in the report); accounts attached | COS-SE-R |
| WAF-DATA-COS-09 | Security | Microsoft Defender for Azure Cosmos DB is enabled | ❌ Manual — Defender plan row attached; the plan name was not re-verified | COS-SE-R |
| WAF-DATA-COS-10 | Security | Cosmos DB accounts send control-plane logs and metrics to Log Analytics | ✅ diagnostic-settings coverage for the account type | COS-SE-C, COS-SE-R |
| WAF-DATA-COS-11 | Security | Data is encrypted with customer-managed keys where regulation requires | ❌ Manual — the key setting is not collected (proposed in the report); accounts attached | COS-SE-C |
| WAF-DATA-COS-12 | Cost optimization | The throughput model, indexing policy, TTL and consistency level are chosen for cost | ❌ Manual — container and database settings are data plane | COS-CO-R |
| WAF-DATA-COS-13 | Cost optimization | Normalised RU consumption is monitored and alerted | ❌ Manual — metric alert rules attached (estate-wide) | COS-CO-R |
| WAF-DATA-COS-14 | Operational excellence | Accounts and containers deploy as code and SDKs are current | ❌ Manual — practice, not ARM | COS-OE-R |
| WAF-DATA-COS-15 | Operational excellence | Throttling, host resources and key metrics have alerts | ❌ Manual — metric alert rules attached (estate-wide) | COS-OE-R |
| WAF-DATA-COS-16 | Performance efficiency | Data model, partition key and queries are designed for performance | ❌ Manual — data-plane design | COS-PE-R |
| WAF-DATA-COS-17 | Performance efficiency | Regions are close to users and multi-region writes are used where clients are distributed | ❌ Manual — accounts attached with location | COS-PE-R |

### Azure Database for PostgreSQL (WAF-DATA-PG) — 10 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-PG-01 | Reliability | PostgreSQL servers use zone-redundant high availability | ❌ Manual — the HA mode is not collected (proposed in the report); servers attached | PG-RE-R |
| WAF-DATA-PG-02 | Reliability | Geo-redundant backups or a cross-region replica protect against regional failure, and restores are tested | ❌ Manual — the backup redundancy is not collected (proposed in the report); servers attached | PG-RE-R |
| WAF-DATA-PG-03 | Security | PostgreSQL servers have public network access disabled | ✅ network.publicNetworkAccess | PG-SE-R |
| WAF-DATA-PG-04 | Security | Microsoft Entra authentication is used, with managed identities | ❌ Manual — the authentication configuration is not collected (proposed in the report); servers attached | PG-SE-R |
| WAF-DATA-PG-05 | Security | Private Link endpoints and network security groups or firewall rules segment access | ❌ Manual — private endpoints attached; pairing is not computed because private-access servers need none | PG-SE-R |
| WAF-DATA-PG-06 | Security | Defender for Cloud, row-level security, customer-managed keys, confidential compute and connection throttling are used where needed | ❌ Manual — server parameters and features are not collected | PG-SE-R |
| WAF-DATA-PG-07 | Cost optimization | The tier and SKU fit the load, with scaling and start or stop for non-production | ❌ Manual — servers attached with sku | PG-CO-R |
| WAF-DATA-PG-08 | Operational excellence | PostgreSQL servers send diagnostics to Log Analytics | ✅ diagnostic-settings coverage for the server type | PG-OE-R |
| WAF-DATA-PG-09 | Operational excellence | Backups, maintenance windows and major-version currency are managed | ❌ Manual — servers attached with version | PG-OE-R |
| WAF-DATA-PG-10 | Performance efficiency | Query Store, Query Performance Insight, index tuning, intelligent tuning and PgBouncer are used | ❌ Manual — server parameters, not collected | PG-PE-R |

### Azure Database for MySQL (WAF-DATA-MYS) — 9 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-MYS-01 | Reliability | MySQL servers use zone-redundant or local-redundant high availability and tested failover | ❌ Manual — the HA mode is not collected (proposed in the report); servers attached | MYS-RE-R |
| WAF-DATA-MYS-02 | Reliability | Tables have explicit primary keys and clients retry with backoff | ❌ Manual — schema, not ARM | MYS-RE-R |
| WAF-DATA-MYS-03 | Security | MySQL servers have public network access disabled | ✅ network.publicNetworkAccess | MYS-SE-R |
| WAF-DATA-MYS-04 | Security | TLS 1.3 is set and secure transport is required | ❌ Manual — server parameters are child resources, not collected | MYS-SE-R |
| WAF-DATA-MYS-05 | Security | Microsoft Entra-only authentication is used and admin credentials are held in Key Vault | ❌ Manual — authentication settings are not collected | MYS-SE-R |
| WAF-DATA-MYS-06 | Security | MySQL servers send diagnostic and audit logs to Log Analytics | ✅ diagnostic-settings coverage for the server type | MYS-SE-R |
| WAF-DATA-MYS-07 | Cost optimization | Server size, reservations, maintenance window and stop or start are chosen for cost | ❌ Manual — servers attached with sku | MYS-CO-R |
| WAF-DATA-MYS-08 | Operational excellence | Backups, restore tests and monitoring are in place | ❌ Manual — backup configuration is not collected | MYS-OE |
| WAF-DATA-MYS-09 | Performance efficiency | The compute tier, storage IOPS and connection handling suit the workload | ❌ Manual — servers attached | MYS-PE |

### Azure Managed Redis (WAF-DATA-RED) — 11 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-RED-01 | Reliability | Redis high availability is on, in a zone-capable region | ❌ Manual — the HA setting is not collected (proposed in the report); caches attached | AMR-RE-R |
| WAF-DATA-RED-02 | Reliability | Active geo-replication, persistence and scheduled exports match the recovery need | ❌ Manual — replication and persistence are not collected | AMR-RE-R |
| WAF-DATA-RED-03 | Reliability | Clients use bounded retries with backoff and separate connection and command timeouts | ❌ Manual — client code, not ARM | AMR-RE-R |
| WAF-DATA-RED-04 | Security | Redis caches have public network access disabled | ✅ publicNetworkAccess | AMR-SE-R |
| WAF-DATA-RED-05 | Security | Each Redis cache has a private endpoint | ✅ cache to private endpoint join | AMR-SE-R |
| WAF-DATA-RED-06 | Security | Microsoft Entra authentication with a managed identity is used and access keys are disabled | ❌ Manual — the access-key setting is not collected (proposed in the report); caches attached | AMR-SE-R |
| WAF-DATA-RED-07 | Security | Non-TLS access is disabled, clients validate the certificate, and customer-managed keys are set at creation where required | ❌ Manual — TLS and encryption settings are not collected (proposed in the report); caches attached | AMR-SE-R |
| WAF-DATA-RED-08 | Security | ConnectionEvents diagnostics and activity logs are collected | ❌ Manual — type not yet in the diagnostic-settings sweep (proposed in the report) | AMR-SE-R |
| WAF-DATA-RED-09 | Cost optimization | The tier and SKU fit memory and compute needs, with reservations for steady usage and no-HA only for disposable environments | ❌ Manual — caches attached with sku | AMR-CO-R |
| WAF-DATA-RED-10 | Operational excellence | Instances deploy as code with health gates, dashboards, alerts and tested recovery runbooks | ❌ Manual — practice, not ARM | AMR-OE-R |
| WAF-DATA-RED-11 | Performance efficiency | OSS clustering, connection reuse, pipelining and co-location with the application are used | ❌ Manual — caches attached with location | AMR-PE-R |

### Azure HorizonDB (WAF-DATA-HZ) — 10 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-HZ-01 | Reliability | Production clusters have at least one reader node and ZoneRedundant high availability | ❌ Manual — HorizonDB is not collected yet (proposed dataset in the report) | HZ-RE-R |
| WAF-DATA-HZ-02 | Reliability | Applications use cluster endpoints with retry, and backup retention and geo-redundant backup match recovery needs | ❌ Manual — not collected | HZ-RE-R |
| WAF-DATA-HZ-03 | Reliability | Resource Health alerts exist for each cluster | ❌ Manual — activity-log alert rules attached (estate-wide) | HZ-RE-R |
| WAF-DATA-HZ-04 | Security | Production clusters use private endpoints, or tightly scoped firewall rules, never all-Azure-services access | ❌ Manual — not collected | HZ-SE-R |
| WAF-DATA-HZ-05 | Security | TLS 1.3 and secure transport are required and clients verify the server certificate | ❌ Manual — not collected | HZ-SE-R |
| WAF-DATA-HZ-06 | Security | Microsoft Entra-only authentication with managed identities is used, with least-privilege roles and a short extension allow-list | ❌ Manual — not collected | HZ-SE-R |
| WAF-DATA-HZ-07 | Security | pgaudit is on and audit logs go to Log Analytics, with Azure RBAC at least privilege on management actions | ❌ Manual — not collected | HZ-SE-R |
| WAF-DATA-HZ-08 | Cost optimization | Cost model, backup retention, geo-redundant backup and savings plan are chosen deliberately | ❌ Manual — not collected | HZ-CO-C |
| WAF-DATA-HZ-09 | Operational excellence | Clusters deploy as code with parameter groups, and monitoring covers per-node metrics | ❌ Manual — not collected | HZ-OE-C |
| WAF-DATA-HZ-10 | Performance efficiency | Processor type, read endpoint use, pooling and query store are set from load tests | ❌ Manual — not collected | HZ-PE-R |

### Azure Blob Storage (WAF-DATA-BLOB) — 14 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-BLOB-01 | Security | Anonymous blob access is disabled on storage accounts | ✅ allowBlobPublicAccess | BLOB-SE-R |
| WAF-DATA-BLOB-02 | Security | Secure transfer (HTTPS) is required | ✅ supportsHttpsTrafficOnly | BLOB-SE-C, BLOB-SE-S |
| WAF-DATA-BLOB-03 | Security | The minimum TLS version is 1.2 | ✅ minimumTlsVersion | BLOB-SE-R |
| WAF-DATA-BLOB-04 | Security | The storage firewall denies by default | ✅ networkAcls.defaultAction | BLOB-SE-C, BLOB-SE-R |
| WAF-DATA-BLOB-05 | Security | Each storage account has a private endpoint for clients that run in Azure | ✅ account to private endpoint join (any service) | BLOB-SE-R |
| WAF-DATA-BLOB-06 | Security | Shared Key authorisation is disallowed and access uses Microsoft Entra RBAC | ❌ Manual — allowSharedKeyAccess is not collected (proposed in the report); accounts attached | BLOB-SE-R, BLOB-SE-S |
| WAF-DATA-BLOB-07 | Security | Customer-managed keys protect data where required, and Defender for Storage detects threats | ❌ Manual — Defender plan row attached; CMK setting is not collected | BLOB-SE-C, BLOB-SE-R |
| WAF-DATA-BLOB-08 | Security | Critical data is immutable and the account is protected by a resource lock | ❌ Manual — resource locks attached (estate-wide) | BLOB-SE-C, BLOB-SE-R |
| WAF-DATA-BLOB-09 | Reliability | Storage accounts use zone-redundant or geo-redundant replication | ✅ account sku redundancy | BLOB-RE-C |
| WAF-DATA-BLOB-10 | Reliability | Soft delete, versioning and point-in-time restore are enabled | ❌ Manual — the blob-service data-protection settings are not collected (proposed in the report); accounts attached | BLOB-RE-R |
| WAF-DATA-BLOB-11 | Reliability | Vaulted backup for blobs and a tested recovery plan exist | ❌ Manual — protected items attached (estate-wide) | BLOB-RE-C, BLOB-RE-R |
| WAF-DATA-BLOB-12 | Operational excellence | Storage accounts send diagnostic logs and metrics to Log Analytics | ✅ diagnostic-settings coverage for the storage account type | BLOB-RE-C |
| WAF-DATA-BLOB-13 | Cost optimization | Access tiers and lifecycle management move cold data to cheaper tiers | ❌ Manual — lifecycle policies are not collected (proposed in the report); accounts attached | BLOB-CO |
| WAF-DATA-BLOB-14 | Performance efficiency | Account type, tier and region match throughput and latency needs | ❌ Manual — accounts attached with sku | BLOB-PE |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 24 | 2 | 22 |
| Security | 44 | 17 | 27 |
| Cost optimization | 11 | 0 | 11 |
| Operational excellence | 11 | 3 | 8 |
| Performance efficiency | 10 | 0 | 10 |
| **Total** | **100** | **22** | **78** |

Every automated item is gated on its resources (or its diagnostic-coverage rows) existing, so an estate
without them reports the item Not assessed. The rules live in `src/assess/rules/waf.dataservices.yaml`.
