# WAF — enumerated source for the Go-Live Well-Architected Review

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.golive.yaml` is a production-readiness review of an Azure estate. It stands in for
the [Go-Live Well-Architected Review](https://learn.microsoft.com/en-us/assessments/b0f9a229-5f82-4f19-ae61-b7be31131f4e/)
assessment, for which Scout found no more than a landing page. Every rule cites an item
number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Go-Live \| Well-Architected Review](https://learn.microsoft.com/en-us/assessments/b0f9a229-5f82-4f19-ae61-b7be31131f4e/) (30-60 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Azure Well-Architected Framework design review checklists on Microsoft Learn (unversioned; the extraction date is the version) |
| Extraction date | 2026-11-25 |
| Verification method | The assessment landing page and the five pillar design review checklists below were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Searches of Microsoft Learn for the assessment's title and for Azure go-live guidance returned nothing about it. Every property an automated item reads was checked against the collect.json contract in `src/collect/Invoke-Collect.ps1`; ARM semantics come from those existing projections and were not re-checked against a live estate. |

## What exists, and what this enumeration is NOT

**Scout found nothing published about this assessment beyond its landing page.** The page says the
assessment helps you "holistically evaluate an Azure workload in a go-forward motion across the five
tenets of the Well-Architected Framework". It names no design areas, no questions and no guidance
article, and Microsoft Learn searches returned no page that describes it. The only "go-live"
guidance Learn returns belongs to other products (Dynamics 365, Power Pages, SAP on Azure) and was
not used.

So this enumeration is **Scout's own production-readiness review, built from the five pillar
design review checklists**, with attention on the gates a team should clear before launch: service
level objectives defined, disaster recovery tested, monitoring and alerting in place, a security
baseline enforced, cost guardrails set, and a safe deployment path. Its items do **not** map to
Microsoft's questions, a Scout score is **not** comparable to a Go-Live Assessment result, and the
`WAF-GOLIVE-*` IDs are Scout's. Each item cites the checklist code it draws on.

Sources:

- [RE] [Design review checklist for Reliability](https://learn.microsoft.com/azure/well-architected/reliability/checklist) (RE:01 to RE:10)
- [SE] [Design review checklist for Security](https://learn.microsoft.com/azure/well-architected/security/checklist) (SE:01 to SE:12)
- [CO] [Design review checklist for Cost Optimization](https://learn.microsoft.com/azure/well-architected/cost-optimization/checklist) (CO:01 to CO:14)
- [OE] [Design review checklist for Operational Excellence](https://learn.microsoft.com/azure/well-architected/operational-excellence/checklist) (OE:01 to OE:11)
- [PE] [Design review checklist for Performance Efficiency](https://learn.microsoft.com/azure/well-architected/performance-efficiency/checklist) (PE:01 to PE:12)

## Scope: an estate, not a workload

Scout scans subscriptions, not one workload. An automated item reports on **every** resource of
that type in the scanned scope. Anything that needs a fact Scout cannot read (SLOs, runbooks,
rehearsals, threat models) is Manual: a person signs it off.

Automated items are **gated**: they run only when the relevant resources (or Advisor data, or
governance data) exist, so an estate with none reports them Not assessed rather than passed.
Items marked "name heuristic" match a policy assignment's display name and miss a differently
named one.

Two readings rest on values Scout has not seen in a live estate: the Advisor reliability and
operational-excellence category names (matched as `HighAvailability` or `Reliability`, and
`OperationalExcellence`), and the `System` tier that WAF-GOLIVE-RE-06 uses to exclude SQL system
databases.

## The enumeration — 57 items across the five pillars

### Reliability gates (WAF-GOLIVE-RE) — 14 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-GOLIVE-RE-01 | Critical user and system flows are identified and rated by business criticality | ❌ Manual | RE:02 |
| WAF-GOLIVE-RE-02 | Reliability and recovery targets (SLO, RTO, RPO) are defined and agreed | ❌ Manual | RE:04 |
| WAF-GOLIVE-RE-03 | Failure mode analysis is complete, with mitigations for each dependency | ❌ Manual | RE:03 |
| WAF-GOLIVE-RE-04 | Virtual machines are deployed in availability zones | ✅ `zoneRedundant` where the region has zones | RE:05 |
| WAF-GOLIVE-RE-05 | AKS node pools are spread across availability zones | ✅ `allPoolsZoned` | RE:05 |
| WAF-GOLIVE-RE-06 | SQL databases are zone-redundant | ✅ `zoneRedundant`, system databases excluded | RE:05 |
| WAF-GOLIVE-RE-07 | Storage accounts use zone-redundant or geo-redundant replication | ✅ storage `sku` | RE:05 |
| WAF-GOLIVE-RE-08 | No autoscale setting is switched off | ✅ autoscale `enabled` | RE:06 |
| WAF-GOLIVE-RE-09 | Virtual machines are protected by Azure Backup | ✅ virtual machine → backup protected item | RE:09 |
| WAF-GOLIVE-RE-10 | No protected item reports a failed last backup | ✅ `lastBackupStatus` | RE:09 |
| WAF-GOLIVE-RE-11 | Resiliency has been tested with load and fault-injection tests that meet the targets | ❌ Manual — chaos experiments attached | RE:08 |
| WAF-GOLIVE-RE-12 | A disaster recovery plan is documented and has been tested end to end | ❌ Manual | RE:09 |
| WAF-GOLIVE-RE-13 | Enabled metric alert rules are wired to an action group | ✅ `actionGroupCount` | RE:10 |
| WAF-GOLIVE-RE-14 | High-impact Advisor reliability recommendations are addressed | ✅ Advisor reliability, high impact | RE:05, RE:09 |

### Security gates (WAF-GOLIVE-SE) — 15 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-GOLIVE-SE-01 | A security baseline is established and the workload is measured against it | ❌ Manual | SE:01 |
| WAF-GOLIVE-SE-02 | Microsoft Defender for Servers is enabled | ✅ Defender plan tier (per subscription) | SE:01, SE:10 |
| WAF-GOLIVE-SE-03 | Microsoft Defender for SQL is enabled | ✅ Defender for SQL tier (per subscription) | SE:10 |
| WAF-GOLIVE-SE-04 | Azure Policy assignments enforce the security baseline | ✅ policy assignment exists (estate-wide) | SE:01 |
| WAF-GOLIVE-SE-05 | Access is least-privilege, conditional and auditable for users, operators and workload identities | ❌ Manual — enabled Conditional Access policies that require MFA attached | SE:05 |
| WAF-GOLIVE-SE-06 | No network security group rule opens RDP or SSH to the internet | ✅ internet-open inbound rule on port 22, 3389 or `*` | SE:06 |
| WAF-GOLIVE-SE-07 | Storage accounts deny public network access by default | ✅ `networkDefaultDeny` | SE:04, SE:06 |
| WAF-GOLIVE-SE-08 | SQL servers do not allow public network access | ✅ `publicNetworkAccess` | SE:04, SE:06 |
| WAF-GOLIVE-SE-09 | Storage accounts require secure transfer | ✅ `httpsOnly` | SE:07 |
| WAF-GOLIVE-SE-10 | Storage accounts require TLS 1.2 or later | ✅ `minTls` | SE:07 |
| WAF-GOLIVE-SE-11 | Key vaults have soft delete and purge protection | ✅ `softDelete`, `purgeProtection` | SE:09 |
| WAF-GOLIVE-SE-12 | Web application firewall policies run in Prevention mode | ✅ policy `mode` | SE:06, SE:08 |
| WAF-GOLIVE-SE-13 | Threat monitoring is live and incident response procedures have been tested | ❌ Manual | SE:10, SE:12 |
| WAF-GOLIVE-SE-14 | Secure development practice and a security testing regimen cover the release | ❌ Manual | SE:02, SE:11 |
| WAF-GOLIVE-SE-15 | High-impact Advisor security recommendations are addressed | ✅ Advisor security, high impact | SE:01, SE:08 |

### Cost guardrail gates (WAF-GOLIVE-CO) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-GOLIVE-CO-01 | A cost model exists with a budget that includes a buffer for unplanned spend | ❌ Manual | CO:02 |
| WAF-GOLIVE-CO-02 | Cost Management budgets with alerts exist | ✅ budget exists (estate-wide) | CO:03 |
| WAF-GOLIVE-CO-03 | Cost data is reviewed against the budget, with anomaly detection and alerts | ❌ Manual | CO:03 |
| WAF-GOLIVE-CO-04 | A policy limits what can be deployed (allowed locations, sizes or resource types) | ✅ guardrail policy assignment (name heuristic) | CO:04 |
| WAF-GOLIVE-CO-05 | No unattached managed disks remain | ✅ unattached disks | CO:07 |
| WAF-GOLIVE-CO-06 | No public IP addresses are left unassociated | ✅ unassociated public IPs | CO:07 |
| WAF-GOLIVE-CO-07 | High-impact Advisor cost recommendations are addressed | ✅ Advisor cost, high impact | CO:07, CO:12 |
| WAF-GOLIVE-CO-08 | Rates, reservations and licence benefits have been evaluated for steady-state usage | ❌ Manual — reservations attached | CO:05 |
| WAF-GOLIVE-CO-09 | Non-production and disaster recovery environments are sized and scheduled to their purpose | ❌ Manual | CO:08 |

### Safe deployment and operations gates (WAF-GOLIVE-OE) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-GOLIVE-OE-01 | Standard operating practices and runbooks exist for routine, ad-hoc and emergency operations | ❌ Manual | OE:01, OE:02 |
| WAF-GOLIVE-OE-02 | Infrastructure is deployed from code through a standard IaC approach | ❌ Manual | OE:05 |
| WAF-GOLIVE-OE-03 | Changes flow through automated pipelines with quality gates and testing across environments | ❌ Manual | OE:06, OE:09 |
| WAF-GOLIVE-OE-04 | A safe deployment plan exists, with progressive exposure and a tested rollback | ❌ Manual — deployment slots attached | OE:11 |
| WAF-GOLIVE-OE-05 | A Log Analytics workspace exists to receive operational telemetry | ✅ workspace exists | OE:07 |
| WAF-GOLIVE-OE-06 | Diagnostic settings cover at least 80% of each resource type | ✅ `coveragePct` per type, gated on a measured sweep | OE:07 |
| WAF-GOLIVE-OE-07 | An enabled action group exists to route alerts | ✅ enabled action group exists | OE:07, OE:08 |
| WAF-GOLIVE-OE-08 | An incident management process with defined roles is documented and has been rehearsed | ❌ Manual | OE:08 |
| WAF-GOLIVE-OE-09 | Virtual machines use platform-orchestrated patching | ✅ `patchMode` | OE:10 |
| WAF-GOLIVE-OE-10 | High-impact Advisor operational excellence recommendations are addressed | ✅ Advisor operational excellence, high impact | OE:07, OE:10 |

### Performance gates (WAF-GOLIVE-PE) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-GOLIVE-PE-01 | Numeric performance targets are defined for every workload flow | ❌ Manual | PE:01 |
| WAF-GOLIVE-PE-02 | Capacity planning is done for launch load and expected growth, including quotas | ❌ Manual | PE:02 |
| WAF-GOLIVE-PE-03 | No Free or Shared App Service plan is used | ✅ App Service plan `sku` | PE:03 |
| WAF-GOLIVE-PE-04 | No Azure AI Search service is on the Free tier | ✅ search service `sku` | PE:03 |
| WAF-GOLIVE-PE-05 | Application performance telemetry exists for web applications | ✅ Application Insights exists where web apps exist | PE:04 |
| WAF-GOLIVE-PE-06 | Standard, Premium and Isolated App Service plans are scaled by an enabled autoscale setting | ✅ App Service plan → enabled autoscale setting | PE:05 |
| WAF-GOLIVE-PE-07 | Performance has been tested in a production-like environment against the targets | ❌ Manual — Load Testing resources attached | PE:06 |
| WAF-GOLIVE-PE-08 | Critical flows are prioritized, and a response plan exists for live performance issues | ❌ Manual | PE:09, PE:11 |
| WAF-GOLIVE-PE-09 | High-impact Advisor performance recommendations are addressed | ✅ Advisor performance, high impact | PE:03, PE:12 |

## Summary

| Pillar gates | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability gates | 14 | 9 | 5 |
| Security gates | 15 | 11 | 4 |
| Cost guardrail gates | 9 | 5 | 4 |
| Safe deployment and operations gates | 10 | 5 | 5 |
| Performance gates | 9 | 5 | 4 |
| **Total** | **57** | **35** | **22** |

Where an item says "attached", Scout carries the matching resources as evidence on the Manual
finding but does not score them.