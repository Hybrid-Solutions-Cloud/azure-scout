# WAF — enumerated source for the Azure AI Search technology review

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.aisearch.yaml` scores the Azure AI Search review. Microsoft publishes no Well-Architected service guide for this service, so this page enumerates the current product guidance that covers the same ground, item by item. The rule file is written against this page only; every rule cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Azure Cognitive Search — Well-Architected Review](https://learn.microsoft.com/en-us/assessments/783533b2-403a-4985-8c60-97db4910f741/) (30 minutes, multiple choice and multiple response; question text not published; page still uses the old product name) |
| Framework version | Azure AI Search (Foundry IQ) product documentation on Microsoft Learn, current at extraction; ARM Microsoft.Search searchServices latest API 2026-11-01 |
| Extraction date | 2026-11-25 |
| Verification method | The Well-Architected service-guide catalog was fetched on 2026-11-25 and has no Azure AI Search entry. The reliability, security best-practices, performance-tips and cost articles named below were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool the same day, and the searchServices ARM template reference was read to confirm the properties the automated items use (replicaCount, publicNetworkAccess, disableLocalAuth, sku, computeType, encryptionWithCmk, networkRuleSet, semanticSearch, upgradeAvailable). |

## The one thing this enumeration is NOT

**It is not Microsoft's question list, and there is no Microsoft Well-Architected checklist for this service.** The items below are **Scout's** reading of the product articles and the `WAF-AISEARCH-*` ids are Scout's. Where the product article is the only source, the source code says so.

Sources (the code after each item names the page and section; -C is a workload design checklist bullet, -R a configuration recommendations row):

- [ARCH] [Create an Azure AI Search index based on file content and metadata](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/search-blob-metadata) (Well-Architected considerations: replicas and SLA)
- [COST] [Plan and manage costs](https://learn.microsoft.com/azure/search/search-sku-manage-costs)
- [PERF] [Tips for better performance](https://learn.microsoft.com/azure/search/search-performance-tips)
- [REL] [Reliability in Foundry IQ (Azure AI Search)](https://learn.microsoft.com/azure/search/search-reliability)
- [SEC] [Secure a Foundry IQ (Azure AI Search) service](https://learn.microsoft.com/azure/search/search-security-best-practices)

The service is documented as Foundry IQ (Azure AI Search) and offers Dedicated and Serverless pricing models. The Serverless model has no replica or partition count, so replica rules skip `sku = serverless`. The older `waf.ai` rule set also scores search services (WAF-AI-DATA-07 and -08); this review is separate and does not replace it.

## The enumeration — 37 items

### Reliability (WAF-AISEARCH-RE) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AISEARCH-RE-01 | The service is on a billable tier (not Free) | ✅ service sku | REL |
| WAF-AISEARCH-RE-02 | Dedicated services have at least two replicas | ✅ replicaCount below 2 on a billable dedicated tier | REL, ARCH |
| WAF-AISEARCH-RE-03 | Services that update indexes have at least three replicas | ❌ Manual — whether a workload writes to the index is not collected; services below three replicas attached | REL |
| WAF-AISEARCH-RE-04 | The service is in a region that supports availability zones | ❌ Manual — region support list is not collected; services attached with region | REL |
| WAF-AISEARCH-RE-05 | A multi-region approach exists for regional failure | ❌ Manual — architecture judgement; services attached | REL |
| WAF-AISEARCH-RE-06 | The index can be rebuilt or restored from source data | ❌ Manual — data-plane recovery, not ARM | REL |
| WAF-AISEARCH-RE-07 | A delete lock protects the search service | ❌ Manual — resource locks attached | REL, SEC |
| WAF-AISEARCH-RE-08 | Clients retry transient faults with exponential backoff | ❌ Manual — client code, not ARM | REL |
| WAF-AISEARCH-RE-09 | Resource Health and Service Health alerts are configured | ❌ Manual — activity-log alert rules attached (estate-wide) | REL |
| WAF-AISEARCH-RE-10 | Dependencies of indexers, skills and vectorizers are reliable | ❌ Manual — dependency review, not ARM | REL |

### Security (WAF-AISEARCH-SE) — 11 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AISEARCH-SE-01 | Inbound public network access is disabled | ✅ publicNetworkAccess | SEC |
| WAF-AISEARCH-SE-02 | Each search service has a private endpoint | ✅ search service to private endpoint join | SEC |
| WAF-AISEARCH-SE-03 | API-key authentication is disabled in favour of Microsoft Entra role-based access | ✅ disableLocalAuth | SEC |
| WAF-AISEARCH-SE-04 | The service has a managed identity for outbound connections | ✅ identity type (none or empty is a finding) | SEC |
| WAF-AISEARCH-SE-05 | Outbound connections to protected data use shared private links, a trusted-service exception or firewall exceptions | ❌ Manual — shared private links are child resources, not collected | SEC |
| WAF-AISEARCH-SE-06 | Customer-managed key encryption is used where required | ❌ Manual — the service-wide CMK enforcement setting is collected and the services that do not enforce it are attached, but CMK is chosen per index (data plane), so a service that does not enforce it is not a finding | SEC |
| WAF-AISEARCH-SE-07 | Confidential compute is used only where regulation requires it | ❌ Manual — computeType is not collected (proposed projection in the report); services attached | SEC |
| WAF-AISEARCH-SE-08 | Document-level access control or security filters trim results per caller | ❌ Manual — data-plane design, not ARM | SEC |
| WAF-AISEARCH-SE-09 | Access to individual indexes follows least privilege | ❌ Manual — role design, not collected per service | SEC |
| WAF-AISEARCH-SE-10 | Diagnostic logging is on and alerts watch for anomalous activity | ❌ Manual — type not yet in the diagnostic-settings sweep (proposed in the report) | SEC |
| WAF-AISEARCH-SE-11 | An IP firewall or network security perimeter limits inbound access when public access stays on | ✅ public access on with no IP rule (a perimeter is reported as SecuredByPerimeter and is not flagged) | SEC |

### Cost optimization (WAF-AISEARCH-CO) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AISEARCH-CO-01 | The pricing model and tier are the lightest that meet the need | ❌ Manual — workload shape is judgement; services attached | COST |
| WAF-AISEARCH-CO-02 | Replicas and partitions are added only when index size, throughput or availability needs them | ❌ Manual — services attached with replica and partition counts; utilisation is not collected | COST |
| WAF-AISEARCH-CO-03 | Higher tiers are weighed against more partitions or replicas of a lower tier | ❌ Manual — services attached | PERF, COST |
| WAF-AISEARCH-CO-04 | Related resources are in the same region | ❌ Manual — regions attached; related resources are not linked | COST |
| WAF-AISEARCH-CO-05 | Incremental indexing, an enrichment cache and a knowledge store limit repeated enrichment cost | ❌ Manual — indexer configuration, not collected | COST |
| WAF-AISEARCH-CO-06 | Semantic ranker and agentic retrieval plans are set deliberately | ❌ Manual — services on the billed standard semantic plan attached; whether it is needed is judgement and the agentic plan is not collected | COST |
| WAF-AISEARCH-CO-07 | Budgets and cost alerts exist for the workload | ❌ Manual — budgets attached (estate-wide) | COST |

### Operational excellence (WAF-AISEARCH-OE) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AISEARCH-OE-01 | Metrics for queries per second, latency, throttling and indexer runs are monitored | ❌ Manual — metric alert rules attached (estate-wide) | SEC, COST |
| WAF-AISEARCH-OE-02 | Services and indexes are deployed as code | ❌ Manual — deployment method is not an ARM property | SEC |
| WAF-AISEARCH-OE-03 | Service upgrades are applied | ❌ Manual — upgradeAvailable is still not projected; services attached | PERF |
| WAF-AISEARCH-OE-04 | Azure Policy audits logging and private endpoint use and resources are tagged | ❌ Manual — policy assignment scope, not collected per service | SEC |
| WAF-AISEARCH-OE-05 | Indexes are updated side by side so queries never see half-built data | ❌ Manual — data-plane practice, not ARM | REL, PERF |

### Performance efficiency (WAF-AISEARCH-PE) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AISEARCH-PE-01 | Index schema attributes are selective | ❌ Manual — index definitions are data plane, not collected | PERF |
| WAF-AISEARCH-PE-02 | Queries are designed for performance | ❌ Manual — query code, not ARM | PERF |
| WAF-AISEARCH-PE-03 | Capacity matches load: replicas for query volume, partitions for slow single queries and index size | ❌ Manual — utilisation is not collected; services attached | PERF |
| WAF-AISEARCH-PE-04 | The application, data sources and search service are in the same region | ❌ Manual — regions attached; the application is not linked | PERF, COST |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 10 | 2 | 8 |
| Security | 11 | 5 | 6 |
| Cost optimization | 7 | 0 | 7 |
| Operational excellence | 5 | 0 | 5 |
| Performance efficiency | 4 | 0 | 4 |
| **Total** | **37** | **7** | **30** |

Every automated item is gated on its resources (or its diagnostic-coverage rows) existing, so an estate
without them reports the item Not assessed. The rules live in `src/assess/rules/waf.aisearch.yaml`.
