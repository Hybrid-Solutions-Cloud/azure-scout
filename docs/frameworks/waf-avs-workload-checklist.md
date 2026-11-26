# WAF — enumerated source for the Azure VMware Solution workload assessment

**Enumerated 2026-08-01. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

The audit's DQ12 records why this file exists: *"Writing rules against a framework you have not
enumerated is how `waf.storage.yaml` happened"* — a rule file scoring a WAF pillar that does not
exist. The rule file, `src/assess/rules/avs.workload.yaml` (27 rules, 9 automated), is written against
this enumeration and nothing else, and every rule in it cites an item number from the tables below.

**What changed in 3.18.19.** Resource Graph indexes an Azure VMware Solution private cloud but not its
children, which is why most rows below were written as unanswerable. The children — clusters, datastores,
placement policies, add-ons, Global Reach connections, authorizations, cloud links, the NSX workload
network, iSCSI paths and maintenances — are now read from the Microsoft.AVS provider into
`domains.avs`, and the private cloud's own extended properties (customer-managed key state, the second
zone of a stretched cloud, a virtual network id) are projected. The rows they answer are updated below;
the rule for each is gated on the dataset's `Measured` flag, so a list Scout could not read is
**Not assessed**, never a Fail. Nothing secret is read: the SRM licence key, ExpressRoute authorization
keys and the Global Reach peer key never reach a row.

## What this assessment is, and what it turned out not to be

Microsoft ships an **"Azure VMware Solution Well-Architected Assessment Tool"**
(announced in the AVS "What's new" for August 2023, pointing to `https://aka.ms/avswafdocs`) — §14,
item 6 of `pmo/audits/AZURE-SCOUT-AUDIT.md` names this as a target. Verification for this file
attempted to locate a published, five-pillar WAF service guide for AVS analogous to the Azure Local
one (`azure/well-architected/service-guides/azure-local`).

**No such page exists at the time of this enumeration.** Two things were tried and both came back
negative:

1. A direct fetch of `https://learn.microsoft.com/en-us/azure/well-architected/azure-vmware/overview`
   — the URL the AVS reliability page itself links to for "production deployment recommendations" —
   **resolved to the generic "Azure Well-Architected Framework workloads" landing page**, not an
   AVS-specific service guide. This is the same link-rot pattern documented for the AVD checklist in
   this release and flagged generally in the audit's §8 currency warnings.
2. A Microsoft Learn documentation search for "Architecture best practices for Azure VMware
   Solution" (the naming pattern every other WAF service guide in this batch uses) returned no
   matching page.

So, unlike the other three checklists in this release, **there is no single Microsoft-published WAF
pillar checklist for AVS to transcribe.** What follows is not a fabrication of one — it's an honest
build from the closest genuinely published, structured content: the AVS **Reliability** pillar guide
(which does exist, in the standard `azure/reliability/` series) and the AVS **Security, governance,
and compliance** scenario guide (a Cloud Adoption Framework page, not a WAF pillar page, but the
closest thing Microsoft publishes to a numbered AVS security/governance checklist).

## Source

| Field | Value | Pillar coverage |
|---|---|---|
| [Reliability in Azure VMware Solution](https://learn.microsoft.com/en-us/azure/reliability/reliability-vmware-solution) | Azure Reliability documentation series (not WAF-branded, but pillar-aligned) | Reliability |
| [Security, governance, and compliance for Azure VMware Solution](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/azure-vmware/eslz-security-governance-and-compliance) | Cloud Adoption Framework scenario guide | Security + Governance (no WAF equivalent for Cost Optimization, Operational Excellence, or Performance Efficiency was located) |
| Framework version | n/a — see above; this is not the WAF pillar structure | — |
| Extraction date | 2026-08-01 | |
| Verification method | Both pages fetched in full via the Microsoft Learn MCP `microsoft_docs_fetch` tool. Every bulleted recommendation under each named subsection is transcribed below, grouped by the subsection heading Microsoft used (not by WAF pillar, since only Reliability genuinely maps to one). |

## What this enumeration is NOT, stated plainly

- **Not the WAF Cost Optimization, Operational Excellence, or Performance Efficiency pillars for
  AVS.** No published Microsoft content for those pillars, specific to AVS, was located in this
  pass. This is the largest gap of the four checklists in this release.
- **Not the interactive assessment tool's questions.** As with the other three checklists, the tool
  itself doesn't publish its question text.
- **Not Item #7 in the audit's programme** (Azure VMware Solution Landing Zone Assessment Review) —
  that is a distinct, ninth target in the audit's list and out of scope for this file, though the
  Security/Governance source below overlaps with landing-zone content because AVS's CAF scenario
  guide doesn't cleanly separate workload concerns from platform concerns the way the Azure Local
  guide does.

**Shelf life.** Given that the primary WAF-branded URL for this workload no longer resolves to
AVS-specific content, re-verify this enumeration before every future use, not just periodically.

## The enumeration — 27 items across 2 areas

### Reliability (WAF-AVS-RE) — 8 items

Source: [Reliability in Azure VMware Solution](https://learn.microsoft.com/en-us/azure/reliability/reliability-vmware-solution)

| # | Item | Scout collector |
|---|---|---|
| WAF-AVS-RE-01 | vSphere HA is enabled to restart VMs on healthy hosts after a host failure | ❌ Unanswerable — vSphere-internal HA configuration state isn't exposed via ARM/ARG |
| WAF-AVS-RE-02 | vSAN fault tolerance policies protect against storage-level transient faults | ❌ Unanswerable — vSAN storage-policy configuration is inside the private cloud, not ARM-readable |
| WAF-AVS-RE-03 | Applications handle transient faults with retry/circuit-breaker patterns | ❌ Unanswerable — application-code pattern |
| WAF-AVS-RE-04 | The private cloud uses a zonal or stretched-cluster deployment for availability-zone resilience | ✅ `Compute/VMWare` — zone/stretched-cluster configuration is an ARM property on the private cloud resource |
| WAF-AVS-RE-05 | Minimum host counts are met for the chosen resiliency configuration (for example, six hosts across two zones for a Gen 1 stretched cluster) | ✅ `domains.avs.clusters` — every cluster of every private cloud (not only the management cluster), held to 3 hosts, or 6 for a stretched (`DualZone`) private cloud; `Compute/VMWare` still shows the management cluster size |
| WAF-AVS-RE-06 | Multi-region resilience is achieved via separate private clouds with a documented DR solution, where business requirements need it | ⚠️ Partial — manual, with evidence: the private clouds that have a Site Recovery Manager or vSphere Replication add-on provisioned (`domains.avs.addons`); whether two private clouds are deliberately paired for DR isn't collected |
| WAF-AVS-RE-07 | Management-component backups (vCenter Server, NSX Manager, HCX Manager) and workload VM backups are both in place | ⚠️ Partial — management-component backup is Microsoft-managed and not collected; workload VM backup is visible via `Management/RecoveryVault`, `Management/BackupInstances` where Azure Backup is used |
| WAF-AVS-RE-08 | Maintenance windows are configured to reduce production impact from platform maintenance | ⚠️ Partial — manual, with evidence: the platform maintenance each private cloud has pending (`domains.avs.maintenances`: component, state, whether Microsoft scheduled it, start time); whether the time chosen suits the workloads is a judgement |

### Security (WAF-AVS-SEC) — 11 items

Source: [Security, governance, and compliance for Azure VMware Solution](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/azure-vmware/eslz-security-governance-and-compliance) — **Security** section

| # | Item | Scout collector |
|---|---|---|
| WAF-AVS-SEC-01 | Permanent Contributor access to the AVS resource group is limited (PIM, time-bound, justification-based) | ⚠️ Partial — manual; the permanent, standing Contributor assignments (`governance.roleAssignmentSchedules`, estate-wide) are attached as evidence, but which of them is scoped to the AVS resource group is for the reviewer |
| WAF-AVS-SEC-02 | `cloudadmin`/network-admin built-in accounts are centrally managed and used only in break-glass scenarios, with domain-services-sourced accounts for routine access | ❌ Unanswerable — vCenter/NSX-T-internal RBAC configuration, not ARM-readable |
| WAF-AVS-SEC-03 | Guest VM identity uses centralized AD DS/LDAP, integrated with Microsoft Entra ID | ⚠️ Partial — `Identity/*` collectors evidence Entra-side configuration; guest-VM domain-join state isn't collected |
| WAF-AVS-SEC-04 | Network security controls are implemented — traffic filtering, WAF/OWASP compliance, unified firewall management, DDoS protection | ⚠️ Partial — `Networking/*` collectors (Azure Firewall, WAF policy, DDoS protection plan) evidence the Azure-side controls; NSX-T-internal filtering isn't collected |
| WAF-AVS-SEC-05 | vSAN datastores use customer-managed key (CMK) encryption via Key Vault | ✅ `compute.privateClouds` — `encryption.status` (Enabled or Disabled) and `encryption.keyVaultProperties.keyState` (Connected or AccessDenied) are properties of the private cloud itself. Nothing inside a Key Vault is read: not the key, its version or the vault's URL. (This row was marked unanswerable in 3.18.18 on the reasoning that it needed the vault's contents; it does not.) |
| WAF-AVS-SEC-06 | vCenter Server access is via a dedicated privileged access workstation (PAW) | ❌ Unanswerable — an access-pattern practice |
| WAF-AVS-SEC-07 | Inbound and outbound internet traffic to/from guest workloads is logged and monitored (SIEM integration) | ⚠️ Partial — `opsPosture.diagnosticCoverage` has a `microsoft.avs/privateclouds` row: how many private clouds have a diagnostic setting forwarding the VMware syslog (vCenter, ESXi, NSX firewall and edge logs). Whether the NSX firewall rules have logging switched on, and whether the destination is the SIEM, isn't collected |
| WAF-AVS-SEC-08 | Backups are centrally managed with RBAC and delayed-delete/soft-delete protection | ✅ `Management/RecoveryVault` (soft-delete state), `Management/BackupInstances` |
| WAF-AVS-SEC-09 | Guest VMs use advanced threat detection (Defender for Cloud, Arc-enabled servers) | ✅ `Security/DefenderPricing`, `Hybrid/ARCServers` (where AVS guest VMs are Arc-onboarded) |
| WAF-AVS-SEC-10 | Guest VM OS and database encryption is enabled where sensitivity requires it | ❌ Unanswerable — guest-OS-level encryption state isn't ARM-readable |
| WAF-AVS-SEC-11 | Code/DevOps workflows for AVS-hosted workloads use modern auth (OAuth/OpenID Connect) | ❌ Unanswerable — application/pipeline configuration, not an AVS resource property |

### Governance (WAF-AVS-GOV) — 8 items

Source: same page — **Governance** section (Environment governance + Workload application and VM governance subsections)

| # | Item | Scout collector |
|---|---|---|
| WAF-AVS-GOV-01 | vSAN datastore utilization is monitored with alerts on the Percentage Datastore Disk Used metric | ⚠️ Partial — `Monitor/MetricAlertRules` can show an alert rule exists if scoped to the AVS private cloud; the specific metric target isn't distinguished |
| WAF-AVS-GOV-02 | VM templates use thin-provisioned storage policies rather than the thick-provisioned default | ❌ Unanswerable — vSAN storage-policy configuration, not ARM-readable |
| WAF-AVS-GOV-03 | Host quota is sized ahead of growth/DR needs, with periodic review | ❌ Unanswerable — a capacity-planning practice |
| WAF-AVS-GOV-04 | Failure-to-tolerate (FTT) vSAN settings match the cluster size for SLA compliance | ❌ Unanswerable — vSAN-internal storage policy |
| WAF-AVS-GOV-05 | Service Health alerts are configured for AVS service issues, planned maintenance, and advisories | ✅ `Monitor/ActivityLogAlertRules` scoped to the AVS resource, where configured |
| WAF-AVS-GOV-06 | Cost governance is in place — budgets, cost alerts, cost allocation for AVS spend | ⚠️ Partial — Cost Management budget collectors exist generally in Scout; AVS-node-specific cost allocation isn't a distinct collected field |
| WAF-AVS-GOV-07 | Azure PaaS services consumed by AVS workloads use private endpoints rather than public endpoints | ✅ `Networking/PrivateEndpoint` |
| WAF-AVS-GOV-08 | Workload VMs are onboarded to Azure Arc for policy, update, and tag management parity with native Azure resources | ✅ `Hybrid/ARCServers` |

## Summary

| Area | Items | Answerable (✅) | Partial (⚠️) | Unanswerable (❌) |
|---|---|---|---|---|
| Reliability | 8 | 2 | 3 | 3 |
| Security | 11 | 3 | 4 | 4 |
| Governance | 8 | 3 | 2 | 3 |
| **Total** | **27** | **8** | **9** | **10** |

8 of 27 items (30%) map cleanly to a collector, and 9 have an automated rule (`WAF-AVS-RE-04`, `RE-05`,
`SEC-04`, `SEC-05`, `SEC-07`, `SEC-09`, `GOV-06`, `GOV-07`, `GOV-08`); the rest are manual, three of them
carrying evidence. The 3.18.18 version of this table counted 7 / 7 / 13, but its Security row (2 / 3 / 6)
did not match the rows above it (2 / 4 / 5); the totals here are counted from the rows. This is still the
weakest-covered of the four checklists in this release, for two compounding reasons: much of what makes
an AVS deployment well-architected lives inside vCenter/NSX-T/vSAN configuration that neither Azure
Resource Graph nor the Microsoft.AVS provider exposes (10 of 27 items are unanswerable for exactly this
reason), and — unlike the other three workloads — there is no published Cost Optimization, Operational
Excellence, or Performance Efficiency source to enumerate in the first place.

## What this means for the rule file

`avs.workload.yaml` cites `WAF-AVS-*` item numbers and does not claim WAF-pillar coverage it doesn't
have — the honest framing is "Reliability, Security, and Governance coverage for AVS," not "the AVS
Well-Architected Review." Closing the Cost Optimization / Operational Excellence /
Performance Efficiency gap is a prerequisite follow-up task: either a working `aka.ms/avswafdocs`
mirror surfaces published text in a future Microsoft docs pass, or Scout accepts partial-pillar
coverage for this workload and says so in the report, the way this file does.
