# WAF — enumerated source for the Mission Critical Well-Architected Review

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.missioncritical.yaml` scores an estate against Microsoft's mission-critical workload
guidance, the scope of the
[Mission Critical Well-Architected Review](https://learn.microsoft.com/en-us/assessments/23513bdb-e8a2-4f0b-8b6b-191ee1f52d34/)
assessment. The file is written against this page only, and every rule cites an item number from
the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Mission Critical \| Well-Architected Review](https://learn.microsoft.com/en-us/assessments/23513bdb-e8a2-4f0b-8b6b-191ee1f52d34/) (30-60 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Mission-critical workload guidance on Microsoft Learn (unversioned; the extraction date is the version) |
| Extraction date | 2026-11-25 |
| Verification method | The overview and all eight design-area pages below were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. The assessment landing page was fetched; its guidance page was read through a search excerpt only. Every property an automated item reads was checked against the collect.json contract in `src/collect/Invoke-Collect.ps1`; ARM semantics come from those existing projections and were not re-checked against a live estate. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published. The items
below are **Scout's** reading of the mission-critical guidance, organised by the eight design areas
the overview names, and the `WAF-MC-*` IDs are Scout's.

Sources:

- [OVR] [Mission-critical workloads](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-overview)
- [ASM] [Well-Architected assessment for mission-critical workloads](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-assessment)
- [AD] [Application design](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-application-design)
- [AP] [Application platform](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-application-platform)
- [DP] [Data platform](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-data-platform)
- [NC] [Networking and connectivity](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-networking-connectivity)
- [HM] [Health modeling for workloads](https://learn.microsoft.com/azure/well-architected/design-guides/health-modeling)
- [DT] [Deployment and testing](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-deployment-testing)
- [SEC] [Security](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-security)
- [OPS] [Operational procedures](https://learn.microsoft.com/azure/well-architected/mission-critical/mission-critical-operational-procedures)

## Scope: an estate, not a workload

Scout scans subscriptions, not one workload. An automated item therefore reports on **every**
resource of that type in the scanned scope, and says so in its remediation text. Items that need a
fact Scout cannot read (health model design, SLOs, branching policy, threat models) are Manual:
they carry the evidence Scout does hold, and a person answers them.

Automated items are **gated**: they run only when the relevant resources exist, so an estate with
none of them reports those items Not assessed rather than passed. Estate-wide "exists" items are
gated on the estate having at least one scanned subscription.

One reading rests on a value Scout has not seen in a live estate: WAF-MC-DP-04 excludes SQL system
databases by their `System` tier. Estate-wide proxies (WAF-MC-AD-02, the region count) are
necessary-but-not-sufficient signals and say so in their remediation text.

## The enumeration — 81 items across the eight design areas

### Application design (WAF-MC-AD) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-AD-01 | Scale units are defined, with the limits that trigger scaling and a capacity model behind them | ❌ Manual | AD · Scale-unit architecture |
| WAF-MC-AD-02 | Resources are deployed in at least two Azure regions (estate-wide signal) | ✅ distinct `location` count on managed disks (estate-wide) | AD · Global distribution; AP · Global distribution of platform resources |
| WAF-MC-AD-03 | Components are loosely coupled and communicate through asynchronous, event-driven messaging | ❌ Manual — Service Bus namespaces attached | AD · Loosely coupled event-driven architecture |
| WAF-MC-AD-04 | Application code implements resiliency patterns and uses vendor SDK resiliency features | ❌ Manual | AD · Resiliency patterns and error handling; Programming language selection |
| WAF-MC-AD-05 | Health endpoints reflect the service's own ability to function, and every request carries a correlation ID | ❌ Manual — Application Insights components attached | AD · Resiliency patterns and error handling |
| WAF-MC-AD-06 | The landing-zone subscription is dedicated to the application | ❌ Manual — subscriptions attached | AD · Scale-unit architecture (landing zone note) |

### Application platform (WAF-MC-AP) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-AP-01 | The number of regions matches the availability target, and the composite SLO is calculated per user flow | ❌ Manual | AP · Global distribution of platform resources |
| WAF-MC-AP-02 | Recovery point and recovery time objectives are defined and validated | ❌ Manual | AP · Global distribution of platform resources |
| WAF-MC-AP-03 | Virtual machines are deployed in availability zones | ✅ `zoneRedundant` where the region has zones | AP · Constrained migrations via IaaS |
| WAF-MC-AP-04 | AKS node pools are spread across availability zones | ✅ `allPoolsZoned` | AP · AKS reliability |
| WAF-MC-AP-05 | Container registries use the Premium tier, which geo-replication and zone redundancy require | ✅ registry `sku` | AP · Container registry |
| WAF-MC-AP-06 | Standard, Premium and Isolated App Service plans are scaled by an enabled autoscale setting | ✅ App Service plan → enabled autoscale setting | OPS · Application operations; AD · Scale-unit architecture |
| WAF-MC-AP-07 | Application components are containerized, immutable and replaceable | ❌ Manual — container apps attached | AP · Containerization; Container hosting and orchestration |
| WAF-MC-AP-08 | Virtual machines are used only where required, in scale sets, and are not accessed individually | ❌ Manual — virtual machines attached | AP · Constrained migrations via IaaS; Serverless compute |

### Data platform (WAF-MC-DP) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-DP-01 | Data growth is forecast and housekeeping (TTL, tiering, offload) keeps volume within platform limits | ❌ Manual | DP · Data platform selection criteria (capacity and growth) |
| WAF-MC-DP-02 | Read and write throughput and latency are monitored against a capacity model and scale automatically | ❌ Manual | DP · Data platform selection criteria (throughput and latency) |
| WAF-MC-DP-03 | The data platform supports the active/active model, with replicas across zones and regions | ❌ Manual — Cosmos DB accounts attached | DP · Globally distributed multi-region write datastore |
| WAF-MC-DP-04 | SQL databases are zone-redundant | ✅ `zoneRedundant`, system databases excluded | DP · Relational data technologies |
| WAF-MC-DP-05 | Relational databases fail over to a secondary region and use zone-redundant high availability | ❌ Manual — PostgreSQL flexible servers attached | DP · Relational data technologies |
| WAF-MC-DP-06 | Event Hubs namespaces are zone-redundant | ✅ `zoneRedundant` | DP · Throughput and latency (asynchronous messaging) |
| WAF-MC-DP-07 | Caches use Azure Managed Redis rather than the retiring Azure Cache for Redis | ✅ cache `type` | DP · Caching for hot tier data |
| WAF-MC-DP-08 | Storage accounts use zone-redundant or geo-redundant replication | ✅ storage `sku` | DP · Consistency and governance (replicas across zones) |
| WAF-MC-DP-09 | Backup, restore and failover are validated through chaos testing in the delivery process | ❌ Manual | DP · Consistency and governance; OPS · Application operations |

### Networking and connectivity (WAF-MC-NC) — 14 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-NC-01 | A global routing service fronts the regional deployment stamps | ✅ Front Door, Front Door (CDN) or Traffic Manager profile exists | NC · Global traffic routing |
| WAF-MC-NC-02 | Web application firewall policies run in Prevention mode | ✅ policy `mode` | NC · Application delivery services |
| WAF-MC-NC-03 | Application Gateways have the web application firewall enabled | ✅ `wafEnabled` | NC · Application delivery services |
| WAF-MC-NC-04 | Load balancers use the Standard SKU | ✅ load balancer `sku` | NC · Application delivery services |
| WAF-MC-NC-05 | Virtual networks are protected by Azure DDoS Network Protection | ✅ virtual network `ddosEnabled` | NC · Application delivery services; SEC · Network intrusion protection |
| WAF-MC-NC-06 | Storage accounts deny public network access by default | ✅ `networkDefaultDeny` | NC · Virtual network integration; SEC · Network intrusion protection |
| WAF-MC-NC-07 | SQL servers do not allow public network access | ✅ `publicNetworkAccess` | NC · Virtual network integration |
| WAF-MC-NC-08 | Cosmos DB accounts do not allow public network access | ✅ `publicNetworkAccess` | NC · Virtual network integration |
| WAF-MC-NC-09 | No network security group rule opens RDP or SSH to the internet | ✅ internet-open inbound rule on port 22, 3389 or `*` | NC · Micro-segmentation and Kubernetes network policies |
| WAF-MC-NC-10 | AKS clusters enforce Kubernetes network policy | ✅ `networkPolicyEnabled` | NC · Micro-segmentation and Kubernetes network policies |
| WAF-MC-NC-11 | Administrative access uses Azure Bastion or another proxied private connection | ❌ Manual — Bastion hosts attached | NC · Virtual network integration |
| WAF-MC-NC-12 | Outbound internet traffic uses NAT Gateway and, where inspection is required, Azure Firewall | ❌ Manual — NAT gateways attached | NC · Internet egress |
| WAF-MC-NC-13 | Front Door and Traffic Manager are configured for fast failover and locked to the intended path | ❌ Manual — Front Door profiles attached | NC · Global traffic routing (Front Door and Traffic Manager recommendations) |
| WAF-MC-NC-14 | Network address space is sized and non-overlapping, traffic is logged, and stamps are independent | ❌ Manual — virtual networks attached | NC · Virtual network integration; Inter-zone and inter-region connectivity; SEC · Network intrusion protection |

### Health modeling and observability (WAF-MC-HM) — 12 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-HM-01 | A health model maps signals from every user flow and component to healthy, degraded and unhealthy states | ❌ Manual | HM · Build a health model; Azure facilitation |
| WAF-MC-HM-02 | SLIs and SLOs are defined for the workload and each business flow | ❌ Manual | HM · Map to reliability metrics |
| WAF-MC-HM-03 | A Log Analytics workspace exists as the unified data sink | ✅ workspace exists | OPS · Monitoring and health modeling; AD · Resiliency patterns and error handling |
| WAF-MC-HM-04 | Diagnostic settings cover at least 80% of each resource type | ✅ `coveragePct` per type, gated on a measured sweep | HM · Use platform metrics and logs |
| WAF-MC-HM-05 | Application Insights components are workspace-based | ✅ `ingestionMode` | OPS · Monitoring and health modeling; HM · Implement distributed tracing |
| WAF-MC-HM-06 | Availability tests probe the application from outside | ✅ enabled availability test exists | HM · Use health probes |
| WAF-MC-HM-07 | Enabled metric alert rules are wired to an action group | ✅ `actionGroupCount` | OPS · Application operations (critical alerts and audiences) |
| WAF-MC-HM-08 | Alert rules exist for the workload | ✅ enabled metric or log search alert exists | HM · Set actionable alerts |
| WAF-MC-HM-09 | An enabled action group exists to route alerts | ✅ enabled action group exists | OPS · Application operations (critical alerts and audiences) |
| WAF-MC-HM-10 | Service Health alerts cover the services and regions in use | ❌ Manual — activity-log alert rules attached | AD · Resiliency patterns and error handling (Azure Service Health) |
| WAF-MC-HM-11 | Data collection rules deliver host and container telemetry to Log Analytics | ✅ rule with a Log Analytics destination exists | AP · Containerization (monitoring); HM · Use platform metrics and logs |
| WAF-MC-HM-12 | Alerts are tuned so only actionable ones reach operators | ❌ Manual | OPS · Application operations; HM · Set actionable alerts |

### Deployment and testing (WAF-MC-DT) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-DT-01 | Production changes use ephemeral blue/green deployments with automated traffic transition | ❌ Manual — deployment slots attached | DT · Zero-downtime deployment; Ephemeral blue/green deployments |
| WAF-MC-DT-02 | Production, test and development use separate subscriptions, and each regional stamp has its own | ❌ Manual — subscriptions attached | DT · Application environments; Subscription-scoped deployment |
| WAF-MC-DT-03 | At least one staging environment fully reflects production and is exercised with synthetic load | ❌ Manual | DT · Application environments |
| WAF-MC-DT-04 | All infrastructure is deployed as code and manual operations against environments are prohibited | ❌ Manual | DT · Infrastructure as code deployments |
| WAF-MC-DT-05 | An Azure Load Testing resource exists | ✅ Load Testing resource exists | DT · Continuous validation and testing |
| WAF-MC-DT-06 | Azure Chaos Studio experiments exist | ✅ Chaos experiment exists | DT · Continuous validation and testing |
| WAF-MC-DT-07 | Smoke, UI, stress, performance and penetration tests run automatically in the pipeline | ❌ Manual | DT · Continuous validation and testing |
| WAF-MC-DT-08 | Deployment tooling is highly available, replicated across regions and reaches private data planes | ❌ Manual — Managed DevOps pools attached | DT · DevOps tools; SEC · Network intrusion protection |
| WAF-MC-DT-09 | Source control enforces a branching strategy, and the software supply chain is scanned | ❌ Manual | DT · Branching strategy; Continuous validation and testing |

### Security (WAF-MC-SE) — 13 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-SE-01 | Microsoft Defender for Servers is enabled | ✅ Defender plan tier (per subscription) | SEC · Alignment with the Zero Trust model |
| WAF-MC-SE-02 | Microsoft Defender for SQL is enabled | ✅ Defender for SQL tier (per subscription) | SEC · Alignment with the Zero Trust model |
| WAF-MC-SE-03 | Azure Policy assignments enforce the security and reliability baseline | ✅ policy assignment exists (estate-wide) | SEC · Policy-driven governance |
| WAF-MC-SE-04 | Key vaults have soft delete and purge protection | ✅ `softDelete`, `purgeProtection` | SEC · Data integrity protection |
| WAF-MC-SE-05 | Cosmos DB accounts disable key-based authentication | ✅ `disableLocalAuth` | SEC · Alignment with the Zero Trust model |
| WAF-MC-SE-06 | Container registry admin accounts are disabled | ✅ `adminEnabled` | AP · Container registry |
| WAF-MC-SE-07 | Container registries restrict public network access | ✅ `publicAccess` | AP · Container registry |
| WAF-MC-SE-08 | Managed identities and Azure RBAC secure service-to-service and data-plane access | ❌ Manual — managed identities attached | SEC · Alignment with the Zero Trust model |
| WAF-MC-SE-09 | No one holds standing write access to production; emergency access is just-in-time with break-glass accounts | ❌ Manual — permanent, standing privileged role assignments (`governance.roleAssignmentSchedules`) attached; which scopes are production is not known | SEC · Alignment with the Zero Trust model; OPS · DevOps processes |
| WAF-MC-SE-10 | Threat modeling is current and engineering budget is set aside for mitigations | ❌ Manual | SEC · Threat modeling |
| WAF-MC-SE-11 | Security testing runs in the delivery pipeline and lower environments have a defined posture | ❌ Manual | SEC · Alignment with the Zero Trust model |
| WAF-MC-SE-12 | Keys and certificates are rotated automatically, with one key vault per regional stamp | ❌ Manual — key vaults attached | SEC · Data integrity protection; OPS · Secret management |
| WAF-MC-SE-13 | Authentication keeps working during identity outages, and identity and activity logs are retained centrally | ❌ Manual | SEC · Alignment with the Zero Trust model; Policy-driven governance |

### Operational procedures (WAF-MC-OP) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-MC-OP-01 | Every change to application and infrastructure flows through automation | ❌ Manual | OPS · DevOps processes; Update management |
| WAF-MC-OP-02 | 20-40% of engineering capacity goes to platform and reliability improvement, against common engineering criteria | ❌ Manual | OPS · DevOps processes |
| WAF-MC-OP-03 | Virtual machines are protected by Azure Backup | ✅ virtual machine → backup protected item | OPS · Application operations |
| WAF-MC-OP-04 | No protected item reports a failed last backup | ✅ `lastBackupStatus` | OPS · Application operations |
| WAF-MC-OP-05 | No autoscale setting is switched off | ✅ autoscale `enabled` | OPS · Application operations; DP · Throughput and latency |
| WAF-MC-OP-06 | Resource locks protect long-lived resources | ✅ lock exists (estate-wide) | OPS · Application operations |
| WAF-MC-OP-07 | Virtual machines use platform-orchestrated patching | ✅ `patchMode` | OPS · IaaS-specific considerations when using VMs |
| WAF-MC-OP-08 | Failover is automated or codified, and recovery operations are practised | ❌ Manual | OPS · Application operations |
| WAF-MC-OP-09 | Kubernetes versions and cluster components are kept current and old images are purged | ❌ Manual — AKS clusters attached | OPS · Update management |
| WAF-MC-OP-10 | A tagging schema is enforced by policy, and certificates renew through built-in platform capabilities | ❌ Manual — tag policy assignments attached | SEC · Policy-driven governance; OPS · Application operations |

## Summary

| Design area | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Application design | 6 | 1 | 5 |
| Application platform | 8 | 4 | 4 |
| Data platform | 9 | 4 | 5 |
| Networking and connectivity | 14 | 10 | 4 |
| Health modeling and observability | 12 | 8 | 4 |
| Deployment and testing | 9 | 2 | 7 |
| Security | 13 | 7 | 6 |
| Operational procedures | 10 | 5 | 5 |
| **Total** | **81** | **41** | **40** |

Where an item says "attached", Scout carries the matching resources as evidence on the Manual
finding but does not score them.