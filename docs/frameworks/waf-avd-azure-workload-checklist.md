# WAF — enumerated source for the Azure Virtual Desktop workload assessment (AVD in Azure)

**Enumerated 2026-11-24. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.avd.yaml` scores Azure Virtual Desktop deployed **on Azure Local** (see
[waf-avd-workload-checklist.md](waf-avd-workload-checklist.md)). This page enumerates the companion
review for AVD running **in Azure**, which is the scope of Microsoft's
[Azure Well-Architected Azure Virtual Desktop workload](https://learn.microsoft.com/en-us/assessments/1ef67c4e-b8d1-4193-b850-d192089ae33d/)
assessment. `src/assess/rules/waf.avd.azure.yaml` is written against this page only, and every
rule cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Azure Well-Architected Azure Virtual Desktop workload](https://learn.microsoft.com/en-us/assessments/1ef67c4e-b8d1-4193-b850-d192089ae33d/) (60 minutes, multiple choice; question text not published) |
| Framework version | Azure Virtual Desktop guidance on Microsoft Learn, current; ARM `Microsoft.DesktopVirtualization` latest GA API 2025-10-10 |
| Extraction date | 2026-11-24 |
| Verification method | Each source page below was fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-24. Every ARM property an automated item reads was checked against the `Microsoft.DesktopVirtualization` ARM template reference or the SDK reference. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published, and the WAF
AVD design-area pages (`well-architected/azure-virtual-desktop/*`) now redirect to AVD product
pages or return 404. The items below are **Scout's** reading of the live AVD guidance, and the
`WAF-AVDAZ-*` IDs are Scout's.

Sources:

- [SEC] [Security recommendations for Azure Virtual Desktop](https://learn.microsoft.com/azure/virtual-desktop/security-recommendations)
- [BCDR] [Multiregion business continuity for Azure Virtual Desktop](https://learn.microsoft.com/azure/architecture/example-scenario/azure-virtual-desktop/azure-virtual-desktop-multi-region-bcdr)
- [SVOC] [Start VM on Connect](https://learn.microsoft.com/azure/virtual-desktop/start-virtual-machine-connect)
- [AUTO] [Autoscale scaling plans](https://learn.microsoft.com/azure/virtual-desktop/autoscale-scenarios)
- [VAL] [Configure a validation environment](https://learn.microsoft.com/azure/virtual-desktop/configure-validation-environment)
- [SAU] [Scheduled Agent Updates](https://learn.microsoft.com/azure/virtual-desktop/scheduled-agent-updates)
- [PL] [Private Link with Azure Virtual Desktop](https://learn.microsoft.com/azure/virtual-desktop/private-link-setup)
- [INS] [Azure Virtual Desktop Insights](https://learn.microsoft.com/azure/virtual-desktop/insights)
- [FSL] [Storage options for FSLogix profile containers](https://learn.microsoft.com/azure/virtual-desktop/store-fslogix-profile)
- [DEP] [Deploy Azure Virtual Desktop](https://learn.microsoft.com/azure/virtual-desktop/deploy-azure-virtual-desktop)

Automated items are **gated**: they run only when the relevant AVD resources exist, so an estate
with no AVD reports them Not assessed. Joins to virtual machines use the session host's
`resourceId`; session hosts on Azure Local are not Azure VMs, so they drop out of those items
rather than being mis-scored.

## The enumeration — 30 items across the five pillars

### Reliability (WAF-AVDAZ-RE) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AVDAZ-RE-01 | Session-host VMs are deployed in availability zones | ✅ session host → VM with no zone in a zone-capable region | BCDR, DEP |
| WAF-AVDAZ-RE-02 | Session hosts are healthy (Shutdown is not a failure) | ✅ session-host status | INS |
| WAF-AVDAZ-RE-03 | FSLogix profile storage is zone- or geo-redundant | ❌ Manual — storage accounts attached | BCDR, FSL |
| WAF-AVDAZ-RE-04 | Profile shares are backed up | ❌ Manual — protected items attached | BCDR |
| WAF-AVDAZ-RE-05 | The golden image is in a Compute Gallery and replicated to the recovery region | ❌ Manual | BCDR |
| WAF-AVDAZ-RE-06 | A business continuity model is defined and recovery is tested | ❌ Manual | BCDR |

### Security (WAF-AVDAZ-SE) — 11 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AVDAZ-SE-01 | Host pool public network access is restricted | ✅ `publicNetworkAccess` | PL |
| WAF-AVDAZ-SE-02 | Workspace public network access is disabled | ✅ `publicNetworkAccess` | PL |
| WAF-AVDAZ-SE-03 | Host pools have a private endpoint | ✅ host pool → private endpoint | PL |
| WAF-AVDAZ-SE-04 | Workspaces have a private endpoint | ✅ workspace → private endpoint | PL |
| WAF-AVDAZ-SE-05 | Microsoft Defender for Servers is enabled | ✅ Defender plan tier (per subscription) | SEC |
| WAF-AVDAZ-SE-06 | MFA and Conditional Access are required for AVD | ❌ Manual — needs Microsoft Graph | SEC |
| WAF-AVDAZ-SE-07 | Session hosts use Trusted Launch or Confidential VMs, with encryption at host | ❌ Manual | SEC, DEP |
| WAF-AVDAZ-SE-08 | No direct RDP or public inbound to session hosts | ❌ Manual — internet-open NSG rules attached | SEC |
| WAF-AVDAZ-SE-09 | Session hosts are assessed for updates automatically | ✅ session host → VM `assessmentMode` | SEC |
| WAF-AVDAZ-SE-10 | Session hosts are hardened in the guest | ❌ Manual — Intune / Group Policy | SEC |
| WAF-AVDAZ-SE-11 | Device redirection is restricted | ❌ Manual | SEC |

### Cost optimization (WAF-AVDAZ-CO) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AVDAZ-CO-01 | Every pooled host pool has an enabled scaling plan | ✅ pooled host pool → enabled scaling-plan assignment | AUTO |
| WAF-AVDAZ-CO-02 | Personal host pools use Start VM on Connect | ✅ `startVMOnConnect` | SVOC |
| WAF-AVDAZ-CO-03 | Windows licence benefit is applied to session hosts | ✅ session host → Windows VM with no `licenseType` | DEP |
| WAF-AVDAZ-CO-04 | Pooled host pools set a deliberate maximum session limit | ✅ `maxSessionLimit` at the default | AUTO |
| WAF-AVDAZ-CO-05 | Session-host sizes and profile storage tier match measured demand | ❌ Manual — VMs attached | FSL |

### Operational excellence (WAF-AVDAZ-OE) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AVDAZ-OE-01 | A validation host pool exists for service updates | ✅ `validationEnvironment` | VAL |
| WAF-AVDAZ-OE-02 | Agent updates are scheduled | ✅ `agentUpdate.type` | SAU |
| WAF-AVDAZ-OE-03 | Host pools, workspaces and session hosts send diagnostics to Log Analytics | ❌ Manual — data collection rules attached | INS |
| WAF-AVDAZ-OE-04 | No session-host component update has failed | ✅ `updateState` | SAU, INS |
| WAF-AVDAZ-OE-05 | Service Health and metric alerts cover AVD | ❌ Manual — activity-log alert rules attached | SEC |

### Performance efficiency (WAF-AVDAZ-PE) — 3 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-AVDAZ-PE-01 | Session-host OS disks are Premium SSD | ❌ Manual | DEP |
| WAF-AVDAZ-PE-02 | Profile storage is in the host pool's region and sized for the user count | ❌ Manual — host pools attached | FSL |
| WAF-AVDAZ-PE-03 | RDP Shortpath (UDP) is used | ❌ Manual | PL |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 6 | 2 | 4 |
| Security | 11 | 6 | 5 |
| Cost optimization | 5 | 4 | 1 |
| Operational excellence | 5 | 3 | 2 |
| Performance efficiency | 3 | 0 | 3 |
| **Total** | **30** | **15** | **15** |

Fields added to the assessment collection for these items (2026-11-24): host pool `id`, `location`,
`startVMOnConnect`, `validationEnvironment`, `publicNetworkAccess`, `agentUpdateType`,
`preferredAppGroupType`; session host `resourceId`, `updateState`; scaling plan `enabledHostPools`;
and a new `compute.avdWorkspaces` dataset. The host pool registration token is never collected.
