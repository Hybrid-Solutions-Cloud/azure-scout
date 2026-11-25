# WAF — enumerated source for the SAP on Azure workload assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

This page enumerates the review that Microsoft publishes as
[SAP on Azure | Well-Architected Review](https://learn.microsoft.com/en-us/assessments/b45998e4-8e92-41b1-a0bd-ab07e665db64/),
for SAP running on Azure virtual machines. `src/assess/rules/waf.sap.yaml` is written against this
page only, and every rule cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [SAP on Azure \| Well-Architected Review](https://learn.microsoft.com/en-us/assessments/b45998e4-8e92-41b1-a0bd-ab07e665db64/) (45 minutes, multiple choice and multiple response; question text not published) |
| Framework version | SAP on Azure guidance on Microsoft Learn, current; ARM `Microsoft.Workloads` REST reference, API versions 2023-04-01 and 2024-09-01 |
| Extraction date | 2026-11-25 |
| Verification method | Each source page below was fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25, except [NW], which was read only as a search excerpt. Every ARM property an automated item reads was checked against the `Microsoft.Workloads` REST reference pages (virtual instance, central instance, database instance, application server instance, monitor). The properties were not exercised against a live SAP estate. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published, and the
Well-Architected SAP workload pages (`well-architected/sap/*`) now redirect to the SAP on Azure
product documentation. The items below are **Scout's** reading of the live SAP guidance, and the
`WAF-SAP-*` IDs are Scout's.

Sources:

- [DC] [SAP workload planning and deployment checklist](https://learn.microsoft.com/azure/sap/workloads/deployment-checklist)
- [AZ] [SAP workload configurations with Azure Availability Zones](https://learn.microsoft.com/azure/sap/workloads/high-availability-zones)
- [AMS] [What is Azure Monitor for SAP solutions?](https://learn.microsoft.com/azure/sap/monitor/about-azure-monitor-sap-solutions)
- [VIS] Microsoft.Workloads REST reference: [SAP Virtual Instances](https://learn.microsoft.com/rest/api/workloads/sap-virtual-instances/get), [Central Instances](https://learn.microsoft.com/rest/api/workloads/sap-central-instances/get), [Database Instances](https://learn.microsoft.com/rest/api/workloads/sap-database-instances/get), [Application Server Instances](https://learn.microsoft.com/rest/api/workloads/sap-application-server-instances/get), [Monitors](https://learn.microsoft.com/rest/api/workloads/monitors/get)
- [HUB] [SAP on Azure documentation](https://learn.microsoft.com/azure/sap/get-started) (the page `well-architected/sap/get-started` redirects to)
- [NW] [Run SAP NetWeaver in Windows on Azure](https://learn.microsoft.com/azure/architecture/guide/sap/sap-netweaver) (search excerpt only)

## How Scout recognises an SAP estate

ARM has no "this VM runs SAP" flag. The one first-party signal is a **Virtual Instance for SAP
solutions** (`Microsoft.Workloads/sapVirtualInstances`) and its `centralInstances`,
`databaseInstances` and `applicationInstances` children, which Azure Center for SAP solutions creates
when a system is deployed or registered. Those types are indexed by Azure Resource Graph.

Scout reads them from the universal discovery index (`$.discovery.Resources[*]`), which keeps the
Resource Graph row of every discovered resource. No SAP-specific projection exists yet.

- Automated items are **gated** on those rows. An estate with no registered SAP system reports them
  Not assessed, never passed.
- An SAP estate that is **not** registered with Azure Center for SAP solutions is also reported Not
  assessed for the automated items. The manual items stay answerable through the questionnaire.
- VM-level automated items join the VM ids that the instances list in `vmDetails[].virtualMachineId`,
  so they only ever score machines Azure itself says belong to a registered SAP system.

## The enumeration — 38 items across the five pillars

### Reliability (WAF-SAP-RE) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SAP-RE-01 | SAP VMs are deployed to availability zones in zone-capable regions | ✅ instance VM → VM with no zone in a zone-capable region | AZ, DC |
| WAF-SAP-RE-02 | Production systems have an HA design for central services and the database | ❌ Manual — production virtual instances attached | AZ, DC |
| WAF-SAP-RE-03 | Registered SAP systems and central services report healthy | ✅ `health` of Unhealthy or Degraded | VIS |
| WAF-SAP-RE-04 | No SAP system is stuck in a failed deployment, installation or registration state | ✅ `state` ending in Failed | VIS |
| WAF-SAP-RE-05 | Failover clusters use a Standard SKU load balancer | ✅ instance load balancer → Basic SKU load balancer | AZ, DC |
| WAF-SAP-RE-06 | SAP VMs have an Azure Backup protected item | ✅ instance VM → no protected item | DC |
| WAF-SAP-RE-07 | Cross-region disaster recovery is designed and rehearsed | ❌ Manual | DC |
| WAF-SAP-RE-08 | Failover, backup and restore were tested and meet the recovery objectives | ❌ Manual | DC |

### Security (WAF-SAP-SE) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SAP-SE-01 | No network virtual appliance in the path between the SAP application and database layers | ❌ Manual | DC |
| WAF-SAP-SE-02 | Application and database layers share a virtual network (or directly peered ones) with scoped NSG and ASG rules | ❌ Manual | DC |
| WAF-SAP-SE-03 | SAP VMs accept no unplanned inbound traffic from the internet | ❌ Manual — internet-open NSG rules attached | DC, NW |
| WAF-SAP-SE-04 | Disk and storage encryption follows the SAP-specific rules | ❌ Manual — disk encryption sets attached | DC |
| WAF-SAP-SE-05 | Database-native encryption protects DBMS data and backups | ❌ Manual | DC |
| WAF-SAP-SE-06 | Azure RBAC separates SAP Basis, network and platform duties | ❌ Manual | DC |
| WAF-SAP-SE-07 | Microsoft Defender for Servers is enabled | ✅ Defender plan tier (per subscription); Scout's reading of the security-concept and hardening items | DC |
| WAF-SAP-SE-08 | SAP VMs are assessed for operating-system updates automatically | ✅ instance VM → VM `assessmentMode` | DC |
| WAF-SAP-SE-09 | Storage accounts that back SAP shared file systems have a private endpoint | ✅ attached storage account → private endpoint | DC |

### Cost optimization (WAF-SAP-CO) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SAP-CO-01 | Non-production SAP systems are shut down when not needed | ❌ Manual — non-production virtual instances attached | DC |
| WAF-SAP-CO-02 | Stable production systems use reservations or savings plans | ❌ Manual — reservations attached | DC |
| WAF-SAP-CO-03 | Sizing is reviewed continuously against measured utilisation | ❌ Manual | DC |
| WAF-SAP-CO-04 | Azure cost is reviewed per SAP system under an owned FinOps practice | ❌ Manual | DC, HUB |

### Operational excellence (WAF-SAP-OE) — 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SAP-OE-01 | Azure Monitor for SAP solutions is deployed | ✅ monitor resource exists | AMS, DC |
| WAF-SAP-OE-02 | No monitor resource is in a failed provisioning state | ✅ `provisioningState` | AMS, VIS |
| WAF-SAP-OE-03 | Monitor providers cover the OS, database, NetWeaver and cluster layers | ❌ Manual — monitors attached; provider instances are not collected | AMS |
| WAF-SAP-OE-04 | Deployment and configuration are automated | ❌ Manual | DC |
| WAF-SAP-OE-05 | Azure-specific SAP quality checks are run and acted on | ❌ Manual — virtual instances attached | DC |
| WAF-SAP-OE-06 | A playbook exists for planned Azure maintenance events | ❌ Manual — maintenance configurations attached | DC |
| WAF-SAP-OE-07 | Timeout and operating-system settings follow the Azure guidance | ❌ Manual | DC |
| WAF-SAP-OE-08 | Alerts and Service Health notifications cover the SAP landscape | ❌ Manual — activity-log alert rules attached | DC, AMS |
| WAF-SAP-OE-09 | No update installation has failed on an SAP VM | ✅ instance VM → failed patch installation | DC |
| WAF-SAP-OE-10 | Support prerequisites and supported release combinations are reviewed on a cadence | ❌ Manual | DC |

### Performance efficiency (WAF-SAP-PE) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-SAP-PE-01 | SAP VMs have no Standard HDD data disks | ✅ instance VM → VM with a Standard_LRS data disk | DC |
| WAF-SAP-PE-02 | SAP VMs have no Standard HDD operating-system disk (Scout extends the HDD guidance to OS disks) | ✅ instance VM → VM with a Standard_LRS OS disk | DC |
| WAF-SAP-PE-03 | Production database storage uses Premium SSD, Premium SSD v2, Ultra Disk or NetApp Files | ❌ Manual | DC |
| WAF-SAP-PE-04 | Disk striping, caching and Write Accelerator follow the DBMS guidance | ❌ Manual | DC |
| WAF-SAP-PE-05 | Accelerated networking is enabled on every network interface of every SAP VM | ✅ instance VM → network interface with it off | DC, AZ |
| WAF-SAP-PE-06 | Application-to-database latency was measured and is in an acceptable range | ❌ Manual | DC, AZ |
| WAF-SAP-PE-07 | VM sizes are SAP-certified, sized from measured demand, and tested against throughput limits | ❌ Manual | DC |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 8 | 5 | 3 |
| Security | 9 | 3 | 6 |
| Cost optimization | 4 | 0 | 4 |
| Operational excellence | 10 | 3 | 7 |
| Performance efficiency | 7 | 3 | 4 |
| **Total** | **38** | **14** | **24** |

## What is not covered

- **Anything inside the SAP application or the database** — kernel parameters, HANA system
  replication state, cluster configuration, SAP notes, interface inventory — is not visible to ARM.
  Those items are manual by nature.
- **SAP HANA on Azure Large Instances** is a different offering and is not scored here.
- **SAP systems that are not registered with Azure Center for SAP solutions** are invisible to the
  automated items (see above). A dedicated `domains.sap` projection and an image-based fallback
  (`RHEL-SAP`, `sles-sap` Marketplace offers) would extend coverage; neither exists yet.
- **Provider instances** under Azure Monitor for SAP solutions are not in Resource Graph, so the
  providers a monitor carries are checked manually (WAF-SAP-OE-03).
- Several automated items read **estate-wide** data (Defender plans, Basic load balancers) and
  therefore flag a subscription or load balancer, not only the SAP machines in it; the rule text says so.
