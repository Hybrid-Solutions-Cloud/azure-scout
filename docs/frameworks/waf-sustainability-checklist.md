# WAF — enumerated source for the Sustainability Well-Architected Review

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.sustainability.yaml` scores an estate against Microsoft's sustainability workload
guidance, the scope of the
[Sustainability Well-Architected Review](https://learn.microsoft.com/en-us/assessments/f236012a-0070-45db-b94c-fe8de0799f38/)
assessment. The file is written against this page only, and every rule cites an item number from
the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Sustainability \| Well-Architected Review](https://learn.microsoft.com/en-us/assessments/f236012a-0070-45db-b94c-fe8de0799f38/) (30 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Sustainability workload guidance on Microsoft Learn (unversioned; the extraction date is the version) |
| Extraction date | 2026-11-25 |
| Verification method | The workload index, the design methodology, the five per-pillar recommendation pages and the sustainable AI design page below were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. The assessment landing page was also fetched. The "What is sustainability?" overview page was not read. Every property an automated item reads was checked against the collect.json contract in `src/collect/Invoke-Collect.ps1`; ARM semantics come from those existing projections and were not re-checked against a live estate. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published. The items
below are **Scout's** reading of the guidance, one item per recommendation topic (or per automatable
signal within a topic), and the `WAF-SUS-*` IDs are Scout's.

Two notes on the source:

- The sustainability workload index links its assessment as
  `a24b1079-29a4-4d22-b678-376e84884f76`; that page and `f236012a-0070-45db-b94c-fe8de0799f38` both
  render as "Sustainability | Well-Architected Review". Scout cites the second, as requested.
- Carbon emissions are not collected by Scout, so every emissions item (baseline, targets, SCI) is
  Manual. The cost-based items rest on Microsoft's own statement that cost is a practical proxy for
  sustainability.

Sources:

- [IDX] [Sustainability workload documentation](https://learn.microsoft.com/azure/well-architected/sustainability/)
- [MTH] [Design methodology for sustainable workloads](https://learn.microsoft.com/azure/well-architected/sustainability/sustainability-design-methodology)
- [REL] [Reliability recommendations](https://learn.microsoft.com/azure/well-architected/sustainability/sustainability-reliability-recommendations)
- [SEC] [Security recommendations](https://learn.microsoft.com/azure/well-architected/sustainability/sustainability-security-recommendations)
- [COST] [Cost Optimization recommendations](https://learn.microsoft.com/azure/well-architected/sustainability/sustainability-cost-optimization-recommendations)
- [OPS] [Operational Excellence recommendations](https://learn.microsoft.com/azure/well-architected/sustainability/sustainability-operational-excellence-recommendations)
- [PERF] [Performance Efficiency recommendations](https://learn.microsoft.com/azure/well-architected/sustainability/sustainability-performance-efficiency-recommendations)
- [AI] [Sustainable AI design for workloads](https://learn.microsoft.com/azure/well-architected/sustainability/sustainable-ai-design)

## Scope: an estate, not a workload

Scout scans subscriptions, not one workload. An automated item reports on **every** resource of
that type in the scanned scope. Idle and orphaned resources, autoscale coverage, Advisor findings
and edge protections are what Scout can see; region choice, application efficiency and carbon
accounting are not, and are Manual.

Automated items are **gated**: they run only when the relevant resources (or Advisor data, or
governance data) exist, so an estate with none reports them Not assessed rather than passed.
Items marked "name heuristic" match a policy assignment's display name and miss a differently
named one.

## The enumeration — 67 items

### Reliability (WAF-SUS-RE) — 16 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SUS-RE-01 | Failure amplification is prevented (circuit breakers, throttling, graceful degradation, dependency isolation) | ❌ Manual | REL · Prevent failure amplification |
| WAF-SUS-RE-02 | Resiliency is matched to business requirements, and multi-region and failover capacity are justified | ❌ Manual | REL · Design resiliency intentionally |
| WAF-SUS-RE-03 | Backup, replication and retention strategies are reviewed against recovery needs | ❌ Manual — backup policies attached | REL · Design resiliency intentionally; PERF · Reduce storage footprint |
| WAF-SUS-RE-04 | Burst demand is smoothed with asynchronous processing, queues and batching | ❌ Manual | REL · Stabilize demand to reduce waste |
| WAF-SUS-RE-05 | No autoscale setting is switched off | ✅ autoscale `enabled` | REL · Stabilize demand; Factor sustainability into platform choices; COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-06 | Standard, Premium and Isolated App Service plans are scaled by an enabled autoscale setting | ✅ App Service plan → enabled autoscale setting | COST · Reduce idle and baseline platform waste; PERF · Balance with scalability needs |
| WAF-SUS-RE-07 | Managed PaaS, serverless and containers are used where they fit, and platform versions are kept current | ❌ Manual — virtual machines attached | REL · Factor sustainability into platform choices; COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-08 | No unattached managed disks remain | ✅ unattached disks | REL · Factor sustainability into platform choices (remove orphaned resources); COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-09 | No public IP addresses are left unassociated | ✅ unassociated public IPs | REL · Factor sustainability into platform choices (remove orphaned resources); COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-10 | No snapshot outlives the disk it was taken from | ✅ snapshot → source disk | COST · Control storage growth over time (remove stale data) |
| WAF-SUS-RE-11 | No load balancer has an empty set of backend pools | ✅ `backendPoolCount` | REL · Factor sustainability into platform choices (remove zombie workloads); COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-12 | No NAT gateway is attached to zero subnets | ✅ `subnetCount` | REL · Factor sustainability into platform choices (remove zombie workloads); COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-13 | Non-production environments are shut down or scaled down when not in use | ❌ Manual | REL · Factor sustainability into platform choices; COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-14 | Spot VMs are used only for interrupt-tolerant workloads | ❌ Manual | REL · Factor sustainability into platform choices; COST · Reduce idle and baseline platform waste |
| WAF-SUS-RE-15 | Deployment regions weigh carbon intensity, latency and resiliency together | ❌ Manual | REL · Factor sustainability into platform choices; COST · Use geography and timing deliberately |
| WAF-SUS-RE-16 | Load testing and chaos engineering are proportionate, scheduled and scoped | ❌ Manual — chaos experiments attached | REL · Run tests that provide meaningful resiliency validation |

### Security (WAF-SUS-SE) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SUS-SE-01 | Web application firewall policies run in Prevention mode | ✅ policy `mode` | SEC · Prevent malicious activity from driving unnecessary resource consumption |
| WAF-SUS-SE-02 | Application Gateways have the web application firewall enabled | ✅ `wafEnabled` | SEC · Prevent malicious activity from driving unnecessary resource consumption |
| WAF-SUS-SE-03 | Virtual networks are protected by Azure DDoS Network Protection | ✅ virtual network `ddosEnabled` | SEC · Prevent malicious activity from driving unnecessary resource consumption |
| WAF-SUS-SE-04 | Rate limiting, throttling and identity-based access limit abusive usage | ❌ Manual — API Management attached | SEC · Prevent malicious activity from driving unnecessary resource consumption |
| WAF-SUS-SE-05 | Storage accounts deny public network access by default | ✅ `networkDefaultDeny` | SEC · Security hardening improves sustainability by reducing workload footprint |
| WAF-SUS-SE-06 | SQL servers do not allow public network access | ✅ `publicNetworkAccess` | SEC · Security hardening improves sustainability by reducing workload footprint |
| WAF-SUS-SE-07 | Security telemetry is filtered at the source and collected for a purpose | ❌ Manual — data collection rules attached | SEC · Reduce security data collection and processing overhead |
| WAF-SUS-SE-08 | Security controls sit close to traffic sources, and routing through central inspection is limited to traffic that needs it | ❌ Manual — firewalls attached | SEC · Improve centralized network security efficiency |

### Cost optimization (WAF-SUS-CO) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SUS-CO-01 | Cost Management budgets exist to give workload owners accountability | ✅ budget exists (estate-wide) | COST · Make cost visible and actionable |
| WAF-SUS-CO-02 | High-impact Advisor cost recommendations are addressed | ✅ Advisor cost, high impact | COST · Make cost visible and actionable; MTH · Measure and track carbon impact |
| WAF-SUS-CO-03 | Advisor has no open finding of idle, unused or underutilized resources | ✅ Advisor cost text match (any impact) | COST · Reduce idle and baseline platform waste; MTH · Apply a shared responsibility mindset |
| WAF-SUS-CO-04 | Observability spend and telemetry retention are part of the optimization scope | ❌ Manual — workspaces retaining over 90 days attached | COST · Make cost visible and actionable; Control storage growth over time |
| WAF-SUS-CO-05 | Service tiers and reservations match actual usage | ❌ Manual — reservations attached | COST · Reduce idle and baseline platform waste |
| WAF-SUS-CO-06 | CI/CD and engineering workflows are proportionate to the change | ❌ Manual | COST · Keep engineering workflows proportionate; Reduce idle and baseline platform waste |
| WAF-SUS-CO-07 | Region and timing of execution are chosen deliberately, including lower-carbon regions and flexible batch windows | ❌ Manual | COST · Use geography and timing deliberately; MTH · Build carbon-aware applications |
| WAF-SUS-CO-08 | Cross-region replication and routing serve a clear workload need | ❌ Manual — geo-replicated storage accounts attached | COST · Use geography and timing deliberately; Limit delivery-path amplification |
| WAF-SUS-CO-09 | Storage tiers follow access patterns, and stale or duplicated data is removed on purpose | ❌ Manual | COST · Control storage growth over time |
| WAF-SUS-CO-10 | Cost is tracked per workload or feature, with explicit efficiency baselines for critical systems | ❌ Manual | COST · Make cost visible and actionable; Reduce structural waste in the application layer |

### Operational excellence (WAF-SUS-OE) — 11 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SUS-OE-01 | A baseline of current carbon emissions exists for every workload and service | ❌ Manual | OPS · Monitor and measure sustainability; MTH · Measure and track carbon impact |
| WAF-SUS-OE-02 | Carbon reduction targets are defined for the workload and its components | ❌ Manual | OPS · Monitor and measure sustainability |
| WAF-SUS-OE-03 | A measurable metric such as the Software Carbon Intensity score is tracked alongside SLOs | ❌ Manual | OPS · Monitor and measure sustainability; MTH · Measure and track carbon impact |
| WAF-SUS-OE-04 | The impact of sustainability changes is recorded and assessed | ❌ Manual | OPS · Monitor and measure sustainability |
| WAF-SUS-OE-05 | Azure Policy assignments exist to drive consistent behaviour | ✅ policy assignment exists (estate-wide) | OPS · Use policy to drive behavior to support sustainability |
| WAF-SUS-OE-06 | A sustainability-focused policy initiative is assigned | ✅ assignment named for sustainability or carbon (name heuristic) | OPS · Use policy to drive behavior to support sustainability |
| WAF-SUS-OE-07 | A policy requires or inherits tags for sustainability reporting | ✅ tag policy assignment (name heuristic) | OPS · Use policy to drive behavior to support sustainability |
| WAF-SUS-OE-08 | Data lifecycle and telemetry-intake policies keep only necessary data | ❌ Manual — data collection rules attached | OPS · Use policy to drive behavior to support sustainability |
| WAF-SUS-OE-09 | Policy compliance is reviewed regularly for further optimization | ❌ Manual | OPS · Use policy to drive behavior to support sustainability |
| WAF-SUS-OE-10 | A sustainability community, training and shared guidance exist | ❌ Manual | OPS · Build culture around sustainability; MTH · Evolve sustainability practices with the ecosystem |
| WAF-SUS-OE-11 | Sustainability objectives sit in governance, reviews and KPIs, and good results are recognized | ❌ Manual | OPS · Build culture around sustainability; MTH · Promote sustainability as a success measure |

### Performance efficiency (WAF-SUS-PE) — 12 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SUS-PE-01 | API communication is efficient, throttled, cached and monitored | ❌ Manual — API Management attached | PERF · Improve application efficiency; COST · Reduce structural waste in the application layer |
| WAF-SUS-PE-02 | Rendering strategy and user interface are chosen for efficiency | ❌ Manual | PERF · Improve application efficiency |
| WAF-SUS-PE-03 | Workloads are profiled, with CPU and memory baselines and quality gates in deployment pipelines | ❌ Manual | PERF · Optimize compute resources |
| WAF-SUS-PE-04 | Specialized compute such as GPUs is evaluated where it improves efficiency | ❌ Manual | PERF · Optimize compute resources |
| WAF-SUS-PE-05 | CDN, caching and compression reduce network traffic | ❌ Manual — CDN profiles attached | PERF · Reduce network traversal; COST · Limit delivery-path amplification |
| WAF-SUS-PE-06 | Workloads and dependencies are placed close to users and to each other | ❌ Manual | PERF · Reduce network traversal |
| WAF-SUS-PE-07 | Storage is compressed, queries are optimized and data is aligned to access tiers | ❌ Manual | PERF · Reduce storage footprint |
| WAF-SUS-PE-08 | Service tiers match demand and dynamic scaling is preferred over fixed capacity | ❌ Manual — App Service plans attached | PERF · Balance with scalability needs |
| WAF-SUS-PE-09 | CI/CD pipelines cache build outputs | ❌ Manual | PERF · Drive efficiency in deployments; COST · Keep engineering workflows proportionate |
| WAF-SUS-PE-10 | Virtual machines use platform-orchestrated patching | ✅ `patchMode` | PERF · Use modern technology |
| WAF-SUS-PE-11 | Legacy applications are identified and modernized to cloud-native or optimized PaaS | ❌ Manual | PERF · Use modern technology |
| WAF-SUS-PE-12 | Caches use Azure Managed Redis rather than the retiring Azure Cache for Redis | ✅ cache `type` | PERF · Use modern technology |

### Sustainable AI design (WAF-SUS-AI) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SUS-AI-01 | Model size is matched to the problem, favoring small language models where they suffice | ❌ Manual — AI services accounts attached | AI · Model design recommendations |
| WAF-SUS-AI-02 | Pretrained models and fine-tuning are preferred to training from scratch | ❌ Manual | AI · Model design recommendations |
| WAF-SUS-AI-03 | Training runs in a low-carbon region with carbon-aware scheduling | ❌ Manual — ML workspaces attached | AI · Model design recommendations (training region); Data design recommendations (regional data strategy) |
| WAF-SUS-AI-04 | Model and result caching avoid redundant computation | ❌ Manual | AI · Model design recommendations |
| WAF-SUS-AI-05 | Data is reused, filtered, sampled and cleaned before training, with efficient ingestion | ❌ Manual | AI · Data design recommendations |
| WAF-SUS-AI-06 | Storage, regional data placement and disaster recovery are optimized for energy | ❌ Manual | AI · Data design recommendations |
| WAF-SUS-AI-07 | Edge processing is considered where it cuts data movement | ❌ Manual | AI · Data design recommendations |
| WAF-SUS-AI-08 | Inference is deployed and scaled with carbon intensity in mind | ❌ Manual | AI · Operational design recommendations |
| WAF-SUS-AI-09 | Retraining is threshold-based, driven by model decay detection rather than a fixed frequency | ❌ Manual | AI · Operational design recommendations |
| WAF-SUS-AI-10 | Sustainability metrics sit in AI monitoring and MLOps, with controlled rollout and rollback | ❌ Manual | AI · Operational design recommendations; OPS · Monitor and measure sustainability |

## Summary

| Pillar lens | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 16 | 7 | 9 |
| Security | 8 | 5 | 3 |
| Cost optimization | 10 | 3 | 7 |
| Operational excellence | 11 | 3 | 8 |
| Performance efficiency | 12 | 2 | 10 |
| Sustainable AI design | 10 | 0 | 10 |
| **Total** | **67** | **20** | **47** |

Where an item says "attached", Scout carries the matching resources as evidence on the Manual
finding but does not score them.