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
- [GPV1] [Upgrade to a general-purpose v2 storage account](https://learn.microsoft.com/azure/storage/common/storage-account-upgrade) and the general-purpose v1 and legacy blob storage retirement pages (used for WAF-DATA-BLOB-16 only; the Blob Storage Well-Architected guide does not carry it)

Collected datasets map as follows: `domains.databases.sqlServers`, `sqlDatabases`, `sqlManagedInstances`, `cosmosDbAccounts`, `postgreSqlFlexibleServers`, `mySqlFlexibleServers`, `redisCaches` (Azure Managed Redis is `microsoft.cache/redisenterprise`; the classic cache shares the dataset) and `domains.storage.storageAccounts`. Azure HorizonDB is not collected, so its items are manual.

The datasets now carry the settings the first pass lacked: SQL server `id`, `minimalTlsVersion` and `entraOnlyAuth`; database and managed-instance backup redundancy; managed-instance zone redundancy and customer-managed-key flag; Cosmos region and zone-redundant-region counts, automatic failover, backup type, network filter and key flag; PostgreSQL and MySQL high-availability mode, geo-redundant backup and (PostgreSQL) authentication; Redis TLS, non-TLS port, access-key setting and high availability; and storage shared-key access, key source and public network access. An absent string is `''` and an absent boolean is `null` in the collection, and Newtonsoft JSONPath never matches a missing property with `==` or `!=` but does match a `null` or `''` value with `!=`. Rules where absence is itself the finding are therefore written as "is not the good value" (storage minimum TLS, shared-key access, the SQL Entra-only flag). Two limits to know: the Cosmos zone item is satisfied by one zone-redundant region (a filter cannot compare two fields), and the Redis access-key setting is only projected for classic caches, so that rule is scoped to them.

Items that mix an automated check with something ARM does not carry (active geo-replication links, the immutable audit target and Always Encrypted, the user-assigned identity, vault soft delete, role assignments, failover tests) have been narrowed to the part that can be scored, and the doc row says what is left for a human.

## The enumeration — 104 items

### Azure SQL Database (WAF-DATA-SQL) — 19 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-SQL-01 | Reliability | SQL databases are zone redundant | ✅ database zoneRedundant (master excluded) | SQL-RE-R |
| WAF-DATA-SQL-02 | Reliability | Active geo-replication or failover groups protect against a regional failure | ✅ `sqlFailoverGroups` `failoverGroupCount` (a server with no failover group is a finding; active geo-replication links are not collected, so a server protected by links alone is an exception to record); gated on `sqlFailoverGroupsMeasured` | SQL-RE-C, SQL-RE-R |
| WAF-DATA-SQL-03 | Reliability | Backups cover point-in-time restore, geo-restore and long-term retention, with immutability | ❌ Manual — backup policy is a child resource, not collected | SQL-RE-R |
| WAF-DATA-SQL-04 | Reliability | Critical databases use the Business Critical or Hyperscale tier | ❌ Manual — the tier of each database is attached; which are critical is judgement | SQL-RE-C |
| WAF-DATA-SQL-05 | Reliability | Applications retry with backoff and isolate connection pools by function | ❌ Manual — client code, not ARM | SQL-RE-C, SQL-RE-R |
| WAF-DATA-SQL-06 | Security | SQL servers have public network access disabled | ✅ server publicNetworkAccess | SQL-SE-R |
| WAF-DATA-SQL-07 | Security | Each SQL server has a private endpoint | ✅ server to private endpoint join | SQL-SE-R |
| WAF-DATA-SQL-08 | Security | The minimum TLS version is 1.2 or higher | ✅ minimalTlsVersion; only 1.2 and 1.3 pass, so an empty value (which allows every version), None, 1.0 and 1.1 are findings | SQL-SE-R |
| WAF-DATA-SQL-09 | Security | SQL authentication is disabled and Microsoft Entra-only authentication is on | ✅ Entra-only flag; an absent flag (no Entra administrator) is a finding | SQL-SE-R |
| WAF-DATA-SQL-10 | Security | Microsoft Defender for SQL is on Standard | ✅ subscription Defender for SQL tier | SQL-SE-R |
| WAF-DATA-SQL-11 | Security | Auditing is on with immutable storage, and sensitive data is protected with Always Encrypted or ledger | ✅ `sqlServerAuditing` `auditingState` (only Enabled passes); the immutable audit target and column encryption are not collected; gated on `sqlServerAuditingMeasured` | SQL-SE-R |
| WAF-DATA-SQL-12 | Cost optimization | The service tier, serverless and elastic pools match each database's use | ❌ Manual — elastic pools attached; databases are in the reliability item | SQL-CO-R |
| WAF-DATA-SQL-13 | Cost optimization | Reserved capacity and Azure Hybrid Benefit are used for steady workloads | ❌ Manual — reservations attached | SQL-CO-R |
| WAF-DATA-SQL-14 | Cost optimization | Backup storage consumption is tuned and queries are optimised to cut resource use | ❌ Manual — metrics, not ARM | SQL-CO-R |
| WAF-DATA-SQL-15 | Operational excellence | SQL databases send diagnostics to Log Analytics | ✅ diagnostic-settings coverage for the database type | SQL-OE-R |
| WAF-DATA-SQL-16 | Operational excellence | SQL projects deploy through CI/CD and servers are backed up with Azure Backup | ❌ Manual — practice, not ARM | SQL-OE-R |
| WAF-DATA-SQL-17 | Performance efficiency | Query Store, automatic tuning and performance recommendations are enabled and acted on | ❌ Manual — database-scoped configuration, not collected | SQL-PE-R |
| WAF-DATA-SQL-18 | Performance efficiency | The vCore model, read scale-out and connection pooling are used | ❌ Manual — databases attached with tier and replica count; connection pooling is client code | SQL-PE-C, SQL-PE-R |
| WAF-DATA-SQL-19 | Reliability | Database backup storage is geo-redundant or geo-zone-redundant | ✅ backup storage redundancy (master excluded); local, zone-only and empty values are findings | SQL-RE-C |

### Azure SQL Managed Instance (WAF-DATA-MI) — 11 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-MI-01 | Reliability | Managed instances are zone redundant | ✅ zoneRedundant; failover groups are child resources, not collected, so that half of the guide item is not scored | MI-RE |
| WAF-DATA-MI-02 | Reliability | Backup storage is geo-redundant or geo-zone-redundant | ✅ backup storage redundancy; local, zone-only and empty values are findings. Retention against the recovery point objective is not collected | MI-RE |
| WAF-DATA-MI-03 | Security | The public data endpoint is off | ✅ publicDataEndpointEnabled | MI-SE |
| WAF-DATA-MI-04 | Security | Cross-network access uses private endpoints | ❌ Manual — private endpoints attached | MI-SE |
| WAF-DATA-MI-05 | Security | Microsoft Entra-only authentication is used | ✅ Entra-only flag; an absent flag is a finding. The user-assigned identity half is not collected | MI-SE |
| WAF-DATA-MI-06 | Security | TDE uses a customer-managed key | ❌ Manual — customer-managed keys are requirement-driven; the instances not on a customer-managed key (cmkEnabled is not true) are attached as evidence, and the vault's soft delete and purge protection are not read | MI-SE |
| WAF-DATA-MI-07 | Security | Defender for SQL is on, SQL Agent is off if unused, and the subnet NSG denies by default | ❌ Manual — agent, NSG and subnet detail are not collected per instance | MI-SE |
| WAF-DATA-MI-08 | Security | Server and operator auditing go to blob storage and Azure Monitor logs | ✅ diagnostic-settings coverage for the managed-instance type (a setting present, not which categories or targets) | MI-SE |
| WAF-DATA-MI-09 | Cost optimization | vCores and service tier are right-sized, with reservations and Azure Hybrid Benefit | ❌ Manual — instances attached with sku and vCores | MI-CO |
| WAF-DATA-MI-10 | Operational excellence | Maintenance windows and the update policy are chosen deliberately | ❌ Manual — maintenance configurations attached (estate-wide) | MI-OE |
| WAF-DATA-MI-11 | Performance efficiency | The service tier, vCores and storage are validated against the workload | ❌ Manual — instances attached | MI-PE |

### Azure Cosmos DB (WAF-DATA-COS) — 17 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-COS-01 | Reliability | Cosmos DB accounts are distributed across availability zones | ✅ count of zone-redundant regions; an account with none is a finding (partial coverage is not detectable) | COS-RE-R |
| WAF-DATA-COS-02 | Reliability | Accounts span at least two regions | ✅ region count | COS-RE-R |
| WAF-DATA-COS-03 | Reliability | Service-managed failover is enabled | ✅ enableAutomaticFailover on multi-region, single-write accounts | COS-RE-R |
| WAF-DATA-COS-04 | Reliability | Continuous backup with point-in-time restore is configured | ✅ backup policy type is Continuous | COS-RE-C |
| WAF-DATA-COS-05 | Security | Cosmos DB accounts have public network access disabled | ✅ account publicNetworkAccess | COS-SE-R |
| WAF-DATA-COS-06 | Security | Each Cosmos DB account has a private endpoint | ✅ account to private endpoint join | COS-SE-R |
| WAF-DATA-COS-07 | Security | Key-based (local) authentication is disabled in favour of Microsoft Entra ID | ✅ disableLocalAuth | COS-SE-R |
| WAF-DATA-COS-08 | Security | Accounts that accept public traffic limit it with virtual network rules or IP firewall rules | ✅ public access on with no virtual network filter and no IP rules. Role-based access is not read | COS-SE-R |
| WAF-DATA-COS-09 | Security | Microsoft Defender for Azure Cosmos DB is enabled | ❌ Manual — Defender plan row attached; the plan name was not re-verified | COS-SE-R |
| WAF-DATA-COS-10 | Security | Cosmos DB accounts send control-plane logs and metrics to Log Analytics | ✅ diagnostic-settings coverage for the account type | COS-SE-C, COS-SE-R |
| WAF-DATA-COS-11 | Security | Data is encrypted with customer-managed keys where regulation requires | ❌ Manual — customer-managed keys are requirement-driven; the accounts not on a customer-managed key are attached as evidence | COS-SE-C |
| WAF-DATA-COS-12 | Cost optimization | The throughput model, indexing policy, TTL and consistency level are chosen for cost | ❌ Manual — container and database settings are data plane | COS-CO-R |
| WAF-DATA-COS-13 | Cost optimization | Normalised RU consumption is monitored and alerted | ❌ Manual — metric alert rules attached (estate-wide) | COS-CO-R |
| WAF-DATA-COS-14 | Operational excellence | Accounts and containers deploy as code and SDKs are current | ❌ Manual — practice, not ARM | COS-OE-R |
| WAF-DATA-COS-15 | Operational excellence | Throttling, host resources and key metrics have alerts | ❌ Manual — metric alert rules attached (estate-wide) | COS-OE-R |
| WAF-DATA-COS-16 | Performance efficiency | Data model, partition key and queries are designed for performance | ❌ Manual — data-plane design | COS-PE-R |
| WAF-DATA-COS-17 | Performance efficiency | Regions are close to users and multi-region writes are used where clients are distributed | ❌ Manual — accounts attached with location, region count and multi-region writes; where the users are is not collected | COS-PE-R |

### Azure Database for PostgreSQL (WAF-DATA-PG) — 10 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-PG-01 | Reliability | PostgreSQL servers use zone-redundant high availability | ✅ highAvailability.mode is ZoneRedundant | PG-RE-R |
| WAF-DATA-PG-02 | Reliability | Geo-redundant backup protects against regional failure | ✅ geo-redundant backup is Enabled; a cross-region replica (the alternative) is not collected | PG-RE-R |
| WAF-DATA-PG-03 | Security | PostgreSQL servers have public network access disabled | ✅ network.publicNetworkAccess | PG-SE-R |
| WAF-DATA-PG-04 | Security | Microsoft Entra authentication is enabled | ✅ authConfig.activeDirectoryAuth; password authentication is collected for the follow-up. Managed identities are not collected | PG-SE-R |
| WAF-DATA-PG-05 | Security | Private Link endpoints and network security groups or firewall rules segment access | ❌ Manual — private endpoints attached; pairing is not computed because private-access servers need none | PG-SE-R |
| WAF-DATA-PG-06 | Security | Defender for Cloud, row-level security, customer-managed keys, confidential compute and connection throttling are used where needed | ❌ Manual — servers attached with data-encryption type; server parameters and features are not collected | PG-SE-R |
| WAF-DATA-PG-07 | Cost optimization | The tier and SKU fit the load, with scaling and start or stop for non-production | ❌ Manual — servers attached with sku | PG-CO-R |
| WAF-DATA-PG-08 | Operational excellence | PostgreSQL servers send diagnostics to Log Analytics | ✅ diagnostic-settings coverage for the server type | PG-OE-R |
| WAF-DATA-PG-09 | Operational excellence | Backups, maintenance windows and major-version currency are managed | ❌ Manual — servers attached with version and backup retention days | PG-OE-R |
| WAF-DATA-PG-10 | Performance efficiency | Query Store, Query Performance Insight, index tuning, intelligent tuning and PgBouncer are used | ❌ Manual — server parameters, not collected | PG-PE-R |

### Azure Database for MySQL (WAF-DATA-MYS) — 9 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-MYS-01 | Reliability | MySQL servers use zone-redundant or same-zone high availability | ✅ highAvailability.mode is ZoneRedundant or SameZone; failover tests are not collected | MYS-RE-R |
| WAF-DATA-MYS-02 | Reliability | Tables have explicit primary keys and clients retry with backoff | ❌ Manual — schema, not ARM | MYS-RE-R |
| WAF-DATA-MYS-03 | Security | MySQL servers have public network access disabled | ✅ network.publicNetworkAccess | MYS-SE-R |
| WAF-DATA-MYS-04 | Security | TLS 1.3 is set and secure transport is required | ❌ Manual — server parameters are child resources, not collected | MYS-SE-R |
| WAF-DATA-MYS-05 | Security | Microsoft Entra-only authentication is used and admin credentials are held in Key Vault | ❌ Manual — authentication settings are not collected | MYS-SE-R |
| WAF-DATA-MYS-06 | Security | MySQL servers send diagnostic and audit logs to Log Analytics | ✅ diagnostic-settings coverage for the server type | MYS-SE-R |
| WAF-DATA-MYS-07 | Cost optimization | Server size, reservations, maintenance window and stop or start are chosen for cost | ❌ Manual — servers attached with sku | MYS-CO-R |
| WAF-DATA-MYS-08 | Operational excellence | Backups, restore tests and monitoring are in place | ❌ Manual — servers attached with geo-redundant backup and retention days; restore tests and monitoring are practice, not ARM | MYS-OE |
| WAF-DATA-MYS-09 | Performance efficiency | The compute tier, storage IOPS and connection handling suit the workload | ❌ Manual — servers attached | MYS-PE |

### Azure Managed Redis (WAF-DATA-RED) — 11 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-RED-01 | Reliability | Redis high availability is on | ✅ highAvailability on Redis Enterprise, and classic Basic tier (no replica) is a finding; zone count and allocation policy attached for review | AMR-RE-R |
| WAF-DATA-RED-02 | Reliability | Active geo-replication, persistence and scheduled exports match the recovery need | ❌ Manual — replication and persistence are not collected | AMR-RE-R |
| WAF-DATA-RED-03 | Reliability | Clients use bounded retries with backoff and separate connection and command timeouts | ❌ Manual — client code, not ARM | AMR-RE-R |
| WAF-DATA-RED-04 | Security | Redis caches have public network access disabled | ✅ publicNetworkAccess | AMR-SE-R |
| WAF-DATA-RED-05 | Security | Each Redis cache has a private endpoint | ✅ cache to private endpoint join | AMR-SE-R |
| WAF-DATA-RED-06 | Security | Access-key authentication is disabled in favour of Microsoft Entra authentication | ✅ `disableAccessKeyAuthentication` on classic caches (an explicit false is a finding; a cache that returned no flag is not scored) and `redisEnterpriseDatabases` `accessKeysAuthentication` on Redis Enterprise databases (Enabled is a finding) | AMR-SE-R |
| WAF-DATA-RED-07 | Security | Non-TLS access is disabled and the minimum TLS version is 1.2 | ✅ enableNonSslPort and minimumTlsVersion. Certificate validation and customer-managed keys are not collected | AMR-SE-R |
| WAF-DATA-RED-08 | Security | ConnectionEvents diagnostics and activity logs are collected | ✅ diagnostic-settings coverage for the classic and Enterprise Redis types (a setting present, not which categories) | AMR-SE-R |
| WAF-DATA-RED-09 | Cost optimization | The tier and SKU fit memory and compute needs, with reservations for steady usage and no-HA only for disposable environments | ❌ Manual — caches attached with sku (now read for classic caches), capacity and high availability | AMR-CO-R |
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

### Azure Blob Storage (WAF-DATA-BLOB) — 17 items

| # | Pillar | Item | Scout | Source |
|---|---|---|---|---|
| WAF-DATA-BLOB-01 | Security | Anonymous blob access is disabled on storage accounts | ✅ allowBlobPublicAccess | BLOB-SE-R |
| WAF-DATA-BLOB-02 | Security | Secure transfer (HTTPS) is required | ✅ supportsHttpsTrafficOnly | BLOB-SE-C, BLOB-SE-S |
| WAF-DATA-BLOB-03 | Security | The minimum TLS version is 1.2 | ✅ minimumTlsVersion; only TLS1_2 and TLS1_3 pass, so an account that never set it (which allows TLS 1.0) is a finding | BLOB-SE-R |
| WAF-DATA-BLOB-04 | Security | The storage firewall denies by default | ✅ networkAcls.defaultAction | BLOB-SE-C, BLOB-SE-R |
| WAF-DATA-BLOB-05 | Security | Each storage account has a private endpoint for clients that run in Azure | ✅ account to private endpoint join (any service) | BLOB-SE-R |
| WAF-DATA-BLOB-06 | Security | Shared Key authorisation is disallowed and access uses Microsoft Entra RBAC | ✅ allowSharedKeyAccess; only an explicit false passes, so an absent flag (allowed) is a finding | BLOB-SE-R, BLOB-SE-S |
| WAF-DATA-BLOB-07 | Security | Customer-managed keys protect data where required | ❌ Manual — customer-managed keys are requirement-driven; the accounts whose key source is not Key Vault are attached as evidence. Defender for Storage is WAF-DATA-BLOB-17 | BLOB-SE-C, BLOB-SE-R |
| WAF-DATA-BLOB-08 | Security | Critical data is immutable and the account is protected by a resource lock | ❌ Manual — resource locks attached (estate-wide) | BLOB-SE-C, BLOB-SE-R |
| WAF-DATA-BLOB-09 | Reliability | Storage accounts use zone-redundant or geo-redundant replication | ✅ account sku redundancy | BLOB-RE-C |
| WAF-DATA-BLOB-10 | Reliability | Soft delete, versioning and point-in-time restore are enabled | ✅ `blobServiceProperties` `deleteRetentionEnabled`, `containerDeleteRetentionEnabled`, `versioningEnabled` and `pointInTimeRestoreEnabled` (any false is a finding; Data Lake and premium accounts cannot use versioning or restore, so record them as exceptions); gated on `blobServicePropertiesMeasured` | BLOB-RE-R |
| WAF-DATA-BLOB-11 | Reliability | Vaulted backup for blobs and a tested recovery plan exist | ❌ Manual — protected items attached (estate-wide) | BLOB-RE-C, BLOB-RE-R |
| WAF-DATA-BLOB-12 | Operational excellence | Storage accounts send diagnostic logs and metrics to Log Analytics | ✅ diagnostic-settings coverage for the storage account type | BLOB-RE-C |
| WAF-DATA-BLOB-13 | Cost optimization | Access tiers and lifecycle management move cold data to cheaper tiers | ❌ Manual — lifecycle policies are not collected (proposed in the report); accounts attached | BLOB-CO |
| WAF-DATA-BLOB-14 | Performance efficiency | Account type, tier and region match throughput and latency needs | ❌ Manual — accounts attached with kind, sku and region | BLOB-PE |
| WAF-DATA-BLOB-15 | Security | Public network access is disabled on storage accounts | ✅ publicNetworkAccess; Disabled and SecuredByPerimeter pass, an absent value (enabled) is a finding. Added with the storage security projection | BLOB-SE-S |
| WAF-DATA-BLOB-16 | Cost optimization | Storage accounts are general-purpose v2 or a premium kind, not a legacy general-purpose v1 or blob-only account | ✅ account kind (Storage, StorageV1 and BlobStorage are findings). Added with the storage security projection; the source is the general-purpose v1 and legacy blob retirement guidance, not the Well-Architected guide | GPV1 |
| WAF-DATA-BLOB-17 | Security | Defender for Storage detects threats | ❌ Manual — Defender plan row attached; the plan name was not re-verified. Split from WAF-DATA-BLOB-07 | BLOB-SE-C, BLOB-SE-R |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 25 | 15 | 10 |
| Security | 46 | 30 | 16 |
| Cost optimization | 12 | 1 | 11 |
| Operational excellence | 11 | 3 | 8 |
| Performance efficiency | 10 | 0 | 10 |
| **Total** | **104** | **49** | **55** |

Every automated item is gated on its resources, its diagnostic-coverage rows, or the `<name>Measured` flag of the per-resource ARM
read it scores (blob service, SQL auditing and failover groups, Redis Enterprise databases), so an estate without them, or a run that
never read the setting, reports the item Not assessed. The rules live in `src/assess/rules/waf.dataservices.yaml`.
