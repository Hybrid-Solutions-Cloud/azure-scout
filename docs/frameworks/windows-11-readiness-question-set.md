# Windows 11 migration readiness — enumerated source for the Windows 11 Pro Migration Readiness Assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `win11.readiness.yaml` is a readiness review for moving a fleet of Windows client devices to Windows 11:
planning, hardware eligibility, applications, management and update control, the security baseline, and operations.
It is Scout's counterpart to Microsoft's
[Windows 11 Pro Migration Readiness Assessment](https://learn.microsoft.com/en-us/assessments/1020523c-e223-432c-8be1-ebbb348f8130/).
`src/assess/rules/win11.readiness.yaml` is written against this page only, and every rule cites an item number from
the tables below. Every item is a **manual** question answered with `-AssessmentAnswers`, because Scout does not
read client devices. Azure Arc-enabled servers and Azure virtual machines are not client devices and are never used
as evidence for these items.

## Source

| Field | Value |
|---|---|
| Assessment | [Windows 11 Pro Migration Readiness Assessment](https://learn.microsoft.com/en-us/assessments/1020523c-e223-432c-8be1-ebbb348f8130/) (question text not published) |
| Framework version | Windows 11 planning, readiness and servicing guidance on Microsoft Learn, current as of the extraction date; no published version number |
| Extraction date | 2026-11-25 |
| Verification method | Pages marked `fetched` in the source list were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Pages marked `search excerpt` were read through `microsoft_docs_search` excerpts on the same day, not in full. The Microsoft Graph interfaces named in the last section were checked against Learn reference pages the same day. No device or Intune tenant was read. |

## Product status

Checked against Microsoft Learn on 2026-11-25.

- **Windows 10 has reached end of support.** Windows 10 version 22H2 was the final version, and support ended on
  2025-10-14. Devices still on Windows 10 no longer receive free security updates; the paid Extended Security Updates
  (ESU) programme is the only route to updates. The migration is therefore no longer ahead of a deadline, and
  WIN11-PL-05 asks what has been decided for each device that remains.
- **Lifecycle of the editions.** Learn states that Home, Pro, Pro for Workstations and Pro for Education editions of
  Windows 11 receive 24 months of support from the general availability date of a version, and Enterprise and
  Education editions 36 months. WIN11-PL-04 asks whether the servicing strategy allows for this.
- **Tooling.** Readiness is read from Intune endpoint analytics (Work from anywhere). Windows Autopatch supports
  Windows 11 Pro among its editions, with licence prerequisites such as Microsoft 365 Business Premium or Windows
  Enterprise E3 (WIN11-MG-04).
- **Nothing is retired or renamed** in the guidance used here.

## The one thing this enumeration is NOT

**The questions are Scout-derived, not Microsoft's.** The assessment's question text is not published, so the items
below are Scout's reading of the guidance listed above. The `WIN11-*` IDs, and the assignment of an item to a group,
are Scout's own.

**Scout does not read this product's data yet.** Scout reads Azure (Resource Graph and ARM) and one Microsoft Entra
policy. It does not read Intune, Configuration Manager or Windows client devices, and the collect.json contract in
`src/collect/Invoke-Collect.ps1` holds no client device data. Azure Arc-enabled servers (`domains.hybrid.arcServers`)
and Azure virtual machines are servers and workloads, not the user devices this assessment is about, so they are not
used as evidence. Every rule is therefore `manual: true` with `query: null`: it is exported as a question by
`Export-ScoutAssessmentQuestion`, answered with `-AssessmentAnswers` (see
[Questionnaire Answers](../assessment/questionnaire-answers.md)), and stays Manual and out of the score until
answered.

Sources:

- [PLAN] [Plan for Windows 11](https://learn.microsoft.com/windows/whats-new/windows-11-plan) -- fetched
- [REQ] [Windows 11 requirements](https://learn.microsoft.com/windows/whats-new/windows-11-requirements) -- fetched
- [RDY] [Define readiness criteria](https://learn.microsoft.com/windows/deployment/update/plan-define-readiness) -- fetched
- [INF] [Evaluate infrastructure and tools](https://learn.microsoft.com/windows/deployment/update/eval-infra-tools) -- fetched
- [STRAT] [Define update strategy with a calendar](https://learn.microsoft.com/windows/deployment/update/plan-define-strategy) -- fetched
- [TEST] [Windows 11 application compatibility testing guidelines](https://learn.microsoft.com/windows/compatibility/windows-11/testing-guidelines) -- fetched
- [WFA] [Work from anywhere report (endpoint analytics, Windows 11 hardware readiness)](https://learn.microsoft.com/intune/endpoint-analytics/work-from-anywhere) -- search excerpt
- [UPG] [Upgrade devices to Windows 11 using feature updates (Intune)](https://learn.microsoft.com/intune/device-updates/windows/upgrade-to-windows-11) -- search excerpt
- [AP] [Windows Autopatch prerequisites](https://learn.microsoft.com/windows/deployment/windows-autopatch/prepare/windows-autopatch-prerequisites) -- search excerpt
- [ESU] [Extended Security Updates (ESU) program for Windows 10](https://learn.microsoft.com/windows/whats-new/extended-security-updates) -- search excerpt
- [LIFE] [Lifecycle FAQ - Windows](https://learn.microsoft.com/lifecycle/faq/windows) -- search excerpt
- [ZT] [Apply principles of Zero Trust to Microsoft Copilot (steps 2 to 5 describe device management and Windows protection capabilities)](https://learn.microsoft.com/security/zero-trust/copilots/zero-trust-microsoft-365-copilot) -- fetched

Every item is **manual**: it is exported as a question and scored only when answered with `-AssessmentAnswers`
(see [Questionnaire Answers](../assessment/questionnaire-answers.md)).

## The enumeration — 34 items across 6 groups

### Plan and servicing strategy (WIN11-PL) — 6 items

| # | Item | Scout | Source |
|---|---|---|---|
| WIN11-PL-01 | A Windows 11 deployment plan exists, with scope, schedule and a process manager who can pause it | Manual | PLAN, RDY |
| WIN11-PL-02 | The roles the deployment needs are filled (application owners, end-user computing, operations, security, stakeholders) | Manual | RDY |
| WIN11-PL-03 | Readiness criteria and go or no-go thresholds are defined, including acceptable call and incident trends | Manual | RDY, INF |
| WIN11-PL-04 | A servicing strategy with a calendar is defined, and the lifecycle of the edition in use is known | Manual | STRAT, PLAN |
| WIN11-PL-05 | Every device still on Windows 10 has a recorded decision now that Windows 10 has reached end of support (2025-10-14) | Manual | ESU, LIFE |
| WIN11-PL-06 | Windows Insider Program for Business, Release Preview channel, is used to validate infrastructure and applications ahead of releases | Manual | PLAN |

### Hardware eligibility (WIN11-HW) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| WIN11-HW-01 | Every device is inventoried and assessed against the Windows 11 hardware requirements | Manual | REQ, PLAN |
| WIN11-HW-02 | A readiness report is used for managed devices (Intune endpoint analytics, Configuration Manager tenant attach, or equivalent) | Manual | WFA, UPG |
| WIN11-HW-03 | Devices reported as not capable or unknown have an owner and an action | Manual | WFA |
| WIN11-HW-04 | Capable devices with TPM or Secure Boot switched off in firmware are found and fixed | Manual | REQ |
| WIN11-HW-05 | The hardware refresh plan prioritises devices that cannot upgrade | Manual | PLAN |
| WIN11-HW-06 | Virtual machines meet the Windows 11 virtual machine requirements | Manual | REQ |
| WIN11-HW-07 | Windows 10 devices meet the direct upgrade prerequisites, and S mode devices have been switched out | Manual | REQ |
| WIN11-HW-08 | Feature-specific hardware needs of the organisation are checked (Windows Hello, Teams peripherals, Client Hyper-V, BitLocker to Go) | Manual | REQ |

### Applications and peripherals (WIN11-AP) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| WIN11-AP-01 | Applications are inventoried and classified as critical, important or not important, with priority and severity defined | Manual | RDY |
| WIN11-AP-02 | Each critical and important application has an owner and a test plan | Manual | RDY, TEST |
| WIN11-AP-03 | Applications were tested on Windows 11 using the Microsoft testing guidelines, including the upgrade scenario | Manual | TEST |
| WIN11-AP-04 | App Assure is used for compatibility issues the organisation cannot resolve | Manual | PLAN |
| WIN11-AP-05 | Drivers, printers, scanners and line-of-business hardware were validated for Windows 11 | Manual | PLAN, RDY |

### Management, deployment and update control (WIN11-MG) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| WIN11-MG-01 | Endpoint management tools are current and support Windows 11 | Manual | INF, PLAN |
| WIN11-MG-02 | Devices are Microsoft Entra joined or hybrid joined and enrolled for management | Manual | AP, UPG |
| WIN11-MG-03 | Feature update policies target Windows 11, and the handling of devices that cannot run it is decided | Manual | UPG |
| WIN11-MG-04 | Windows Autopatch rings or an equivalent staged rollout is configured, and the licence and edition prerequisites are met | Manual | AP, STRAT |
| WIN11-MG-05 | Existing update policies, administrative templates and WSUS settings were reviewed for conflict with the new policies | Manual | INF |
| WIN11-MG-06 | The deployment method is chosen: in-place upgrade through feature updates, or new and reprovisioned devices | Manual | PLAN |
| WIN11-MG-07 | Deployment progress, failures and safeguard holds are monitored through update reporting | Manual | PLAN, UPG |

### Security baseline (WIN11-SC) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| WIN11-SC-01 | Microsoft security baselines for Windows 11 are applied and kept current | Manual | INF |
| WIN11-SC-02 | Device protection features are enabled: BitLocker, Windows Hello for Business, Defender Firewall, SmartScreen, application control | Manual | ZT |
| WIN11-SC-03 | Compliance policies and Conditional Access require healthy, compliant devices | Manual -- Conditional Access policies and device compliance are not in collect.json | ZT |
| WIN11-SC-04 | The security team reviewed and approved the baseline and tools before pilot | Manual | RDY |

### Operations and user readiness (WIN11-OP) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| WIN11-OP-01 | Support readiness is in place: documentation, process changes and a defined rollback | Manual | RDY, INF |
| WIN11-OP-02 | Users are told what changes and how to get help | Manual | RDY |
| WIN11-OP-03 | A pilot group is representative of the organisation before broad deployment | Manual | RDY, STRAT |
| WIN11-OP-04 | Ongoing servicing is planned: monthly quality updates and an annual feature update | Manual | PLAN, STRAT |

## Summary

| Group | Items | Automated | Manual |
|---|---|---|---|
| Plan and servicing strategy | 6 | 0 | 6 |
| Hardware eligibility | 8 | 0 | 8 |
| Applications and peripherals | 5 | 0 | 5 |
| Management, deployment and update control | 7 | 0 | 7 |
| Security baseline | 4 | 0 | 4 |
| Operations and user readiness | 4 | 0 | 4 |
| **Total** | **34** | **0** | **34** |

## What an automated version would need

Everything below needs a Microsoft Graph app registration with read-only application permissions and tenant admin
consent, a new collect section for device data, and a gate on each rule so a tenant that was not read reports Not
assessed instead of Pass. Intune data covers only devices enrolled in Intune, co-managed, or tenant attached.

| Items | What would be read | Interface and permission |
|---|---|---|
| WIN11-HW-01, HW-02, HW-03 | Windows 11 hardware readiness for each device and the top hardware blockers | Microsoft Graph v1.0 Intune endpoint analytics: `userExperienceAnalyticsWorkFromAnywhereDevice` (`upgradeEligibility` is `upgraded`, `unknown`, `notCapable` or `capable`) and `userExperienceAnalyticsWorkFromAnywhereHardwareReadinessMetric` (`totalDeviceCount`, `upgradeEligibleDeviceCount` and the failed-check percentages for RAM, storage and processor cores). The read permission for these resources was not confirmed in this pass; `DeviceManagementManagedDevices.Read.All` is the documented read permission for the sibling managed device APIs. |
| WIN11-HW-07, MG-02, PL-05 | Operating system version, edition and join state of each device | Microsoft Graph v1.0 `GET /deviceManagement/managedDevices` (`operatingSystem`, `osVersion`, `complianceState`, `managementAgent`); `DeviceManagementManagedDevices.Read.All`. The Intune report `DevicesWithInventory` also carries `OSVersion`, `JoinType`, `SkuFamily`, `ProcessorArchitecture` and the TPM fields. |
| WIN11-MG-03, MG-04, MG-07 | Feature update policies, rings and deployment progress | Windows Autopatch in Microsoft Graph: `admin/windows/updates/deployments` and the catalog entries, plus the policy and ring resources in beta (`featureUpdatePolicy`, `featureUpdateRing`). The feature update APIs use the beta endpoint and are subject to change. |
| WIN11-SC-03 | Conditional Access that requires compliant devices, and Intune compliance policy | Microsoft Graph v1.0 `GET /identity/conditionalAccess/policies`; `Policy.Read.All`. Compliance policy APIs were not researched in this pass. |

Items about planning, applications, people and process (WIN11-PL, WIN11-AP, WIN11-OP) have no API behind them and
stay manual in any version. Application compatibility results come from testing, not from an inventory call.
