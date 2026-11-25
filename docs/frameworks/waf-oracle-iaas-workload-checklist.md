# WAF — enumerated source for the Oracle on Azure IaaS workload assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

This page enumerates the review that Microsoft publishes as
[Azure Well-Architected Oracle on Azure IaaS workload](https://learn.microsoft.com/en-us/assessments/d3acb4d8-8045-4635-9a31-0bcb3b10724a/),
for Oracle software that the customer runs and manages on Azure virtual machines.
`src/assess/rules/waf.oracle.yaml` is written against this page only, and every rule cites an item
number from the tables below.

It is **not** [Oracle Database@Azure](https://learn.microsoft.com/azure/oracle/oracle-db/database-overview),
the OCI-managed Exadata service in Azure datacenters (`oracle.database/*` resources). That service has
different resources and a different responsibility split, and is out of scope for this review.

## Source

| Field | Value |
|---|---|
| Assessment | [Azure Well-Architected Oracle on Azure IaaS workload](https://learn.microsoft.com/en-us/assessments/d3acb4d8-8045-4635-9a31-0bcb3b10724a/) (30 minutes, multiple choice and multiple response; question text not published) |
| Framework version | Oracle on Azure virtual machines guidance on Microsoft Learn, current |
| Extraction date | 2026-11-25 |
| Verification method | Each source page below was fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25, except [SEC] and [APP], which were read only as search excerpts. Every ARM property an automated item reads (image reference, storage profile, network interface) was checked against the `Microsoft.Compute` and `Microsoft.Network` ARM template references. The properties were not exercised against a live Oracle estate. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published, and the
Well-Architected Oracle IaaS workload pages (`well-architected/oracle-iaas/*`) now redirect to the
Oracle on Azure product documentation. The items below are **Scout's** reading of the live
Oracle-on-Azure-VM guidance, and the `WAF-ORA-*` IDs are Scout's. Where an item has no Oracle page
behind it (WAF-ORA-CO-04, CO-05 and OE-01) it is Scout's application of the general Well-Architected
pillar, and the table says so.

Sources:

- [OV] [Overview of Oracle applications and solutions on Azure](https://learn.microsoft.com/azure/virtual-machines/workloads/oracle/oracle-considerations)
- [REF] [Architectures for Oracle database on Azure Virtual Machines](https://learn.microsoft.com/azure/virtual-machines/workloads/oracle/oracle-reference-architecture)
- [BKP] [Backup strategies for Oracle Database on an Azure Linux VM](https://learn.microsoft.com/azure/virtual-machines/workloads/oracle/oracle-database-backup-strategies)
- [DES] [Architectures for Oracle Database Enterprise Edition on Azure](https://learn.microsoft.com/azure/virtual-machines/workloads/oracle/oracle-design)
- [PERF] [Performance best practices for Oracle on Azure VMs](https://learn.microsoft.com/azure/virtual-machines/workloads/oracle/oracle-performance-best-practice)
- [HUB] [Oracle on Azure](https://learn.microsoft.com/azure/well-architected/oracle-iaas/) (the page this URL now redirects to)
- [SEC] [Security best practices for IaaS workloads in Azure](https://learn.microsoft.com/azure/security/fundamentals/iaas) (search excerpt only)
- [APP] [Architectures for Oracle applications with database on Azure Virtual Machines](https://learn.microsoft.com/azure/virtual-machines/workloads/oracle/deploy-application-oracle-database-azure) (search excerpt only)

## How Scout recognises an Oracle VM

ARM cannot say "this VM runs an Oracle database". The only control-plane signal Scout reads is the
**Azure Marketplace image**: a VM built from an image whose publisher is `Oracle` (Oracle Linux and
Oracle Database images), taken from the universal discovery index (`$.discovery.Resources[*]`) at
`Properties.storageProfile.imageReference.publisher`. No Oracle-specific projection exists yet.

- Automated items are **gated** on at least one such VM. An estate without one reports them Not
  assessed, never passed.
- An Oracle database on Red Hat, another endorsed distribution or a custom image is **invisible** to the
  automated items, which then report Not assessed. The manual items stay answerable through the
  questionnaire.
- An Oracle Linux VM that runs no Oracle software would still be scored; each automated remediation
  says the rule keys on the image.
- Everything that depends on the database itself (Data Guard, RMAN, AWR sizing, licensing, ASM, Far
  Sync, Oracle Enterprise Manager) is manual by nature.

## The enumeration — 34 items across the five pillars

### Reliability (WAF-ORA-RE) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ORA-RE-01 | Oracle VMs are deployed to availability zones in zone-capable regions | ✅ Oracle-image VM → VM with no zone in a zone-capable region | REF, OV |
| WAF-ORA-RE-02 | Database HA uses Data Guard or GoldenGate across separate zones, not RAC alone | ❌ Manual — Oracle-image VMs attached | REF, OV |
| WAF-ORA-RE-03 | A DR standby exists in another region, with Far Sync where zero data loss over distance is needed | ❌ Manual | REF |
| WAF-ORA-RE-04 | A backup strategy is in place and restores are tested | ❌ Manual — protected items attached | BKP, OV |
| WAF-ORA-RE-05 | Backups survive a regional outage | ❌ Manual — recovery vaults attached | BKP |
| WAF-ORA-RE-06 | The application tier uses cloud-native resilience patterns | ❌ Manual | REF |

### Security (WAF-ORA-SE) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ORA-SE-01 | Oracle VMs have no public IP address | ✅ Oracle-image VM → network interface with a public IP | DES |
| WAF-ORA-SE-02 | Microsoft Defender for Servers is enabled | ✅ Defender plan tier (per subscription) | SEC |
| WAF-ORA-SE-03 | Oracle VMs are assessed for operating-system updates automatically | ✅ Oracle-image VM → VM `assessmentMode` | REF, SEC |
| WAF-ORA-SE-04 | Administrators reach database VMs only through a bastion host or jumpbox | ❌ Manual — internet-open NSG rules attached | DES, APP |
| WAF-ORA-SE-05 | Application and database tiers sit in separate subnets under subnet-level NSG policy | ❌ Manual | DES |
| WAF-ORA-SE-06 | Data at rest and in transit is encrypted, including backup media | ❌ Manual — disk encryption sets attached | DES, BKP, APP |
| WAF-ORA-SE-07 | Azure RBAC gives each team the least privilege it needs | ❌ Manual | APP |

### Cost optimization (WAF-ORA-CO) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ORA-CO-01 | VM size derives from AWR or Statspack and uses constrained vCPU sizes where core count drives licence cost | ❌ Manual — Oracle-image VMs attached | OV, DES, REF |
| WAF-ORA-CO-02 | Oracle licence entitlement matches the deployed vCPUs under bring-your-own-licence | ❌ Manual | OV |
| WAF-ORA-CO-03 | Storage choice balances price and performance, with lower tiers for development and test | ❌ Manual | PERF |
| WAF-ORA-CO-04 | Non-production Oracle VMs are deallocated when idle (Scout's application of the pillar) | ❌ Manual | DES |
| WAF-ORA-CO-05 | Steady production capacity is covered by reservations or savings plans (Scout's application of the pillar) | ❌ Manual — reservations attached | — |

### Operational excellence (WAF-ORA-OE) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ORA-OE-01 | Oracle workloads are identifiable in Azure (Scout's addition, so reviews can scope them) | ❌ Manual — VMs with Oracle-like names attached | — |
| WAF-ORA-OE-02 | Azure Monitor with VM insights collects the disk metrics Oracle needs | ❌ Manual — data collection rules attached | REF |
| WAF-ORA-OE-03 | Oracle Enterprise Manager provides database-layer monitoring on its own VM | ❌ Manual | REF, DES |
| WAF-ORA-OE-04 | Alerts cover disk saturation and Service Health for the Oracle regions | ❌ Manual — metric alert rules attached | REF |
| WAF-ORA-OE-05 | No update installation has failed on an Oracle VM | ✅ Oracle-image VM → failed patch installation | REF |
| WAF-ORA-OE-06 | Database patching and maintenance are automated and scheduled | ❌ Manual | REF |
| WAF-ORA-OE-07 | Infrastructure and database configuration are deployed as code | ❌ Manual | OV |
| WAF-ORA-OE-08 | File systems mount managed disks by device UUID, not device name | ❌ Manual | REF |

### Performance efficiency (WAF-ORA-PE) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ORA-PE-01 | Oracle VMs have no Standard HDD or Standard SSD data disks | ✅ `dataDisks[].managedDisk.storageAccountType` | PERF, DES |
| WAF-ORA-PE-02 | Oracle VMs boot from a Premium SSD operating-system disk | ✅ `osDisk.managedDisk.storageAccountType` | DES |
| WAF-ORA-PE-03 | No Oracle data disk uses read-write host caching | ✅ `dataDisks[].caching` | DES |
| WAF-ORA-PE-04 | Accelerated networking is enabled on every network interface of every Oracle VM | ✅ Oracle-image VM → network interface with it off | DES |
| WAF-ORA-PE-05 | VM series is memory optimised with a memory-to-vCore ratio suited to Oracle | ❌ Manual — Oracle-image VMs attached | PERF |
| WAF-ORA-PE-06 | Redo, temp and undo are on separate disks; Write Accelerator or Ultra Disk for redo | ❌ Manual | DES |
| WAF-ORA-PE-07 | Disk performance was load-tested and sized by IOPS, not capacity | ❌ Manual | DES |
| WAF-ORA-PE-08 | Guest and placement tuning follows the Oracle on Azure guidance | ❌ Manual | DES, REF |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 6 | 1 | 5 |
| Security | 7 | 3 | 4 |
| Cost optimization | 5 | 0 | 5 |
| Operational excellence | 8 | 1 | 7 |
| Performance efficiency | 8 | 4 | 4 |
| **Total** | **34** | **9** | **25** |

## What is not covered

- **Oracle Database@Azure** (`oracle.database/*`) — see above.
- **Oracle on VMs built from non-Oracle images** — invisible to the automated items (see above).
- **Oracle RAC** is not supported on Azure; the review treats Data Guard or GoldenGate as the
  high-availability mechanism.
- **Disk-to-VM scoping** is read from the VM's own `storageProfile`, so a data disk attached to an
  Oracle-image VM is scored even if the VM is a non-database server. Disks themselves are not joined
  (the managed-disk projection carries no `managedBy`).
- Several automated items read **estate-wide** data (Defender plans) and flag a subscription, not only
  the Oracle machines in it; the rule text says so.
