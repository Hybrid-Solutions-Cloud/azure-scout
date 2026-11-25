# CAF Migrate readiness — enumerated source (formerly the Strategic Migration Assessment)

> **Source:** <https://learn.microsoft.com/azure/cloud-adoption-framework/plan/> and
> <https://learn.microsoft.com/azure/cloud-adoption-framework/migrate/plan-migration> (CAF Plan and
> CAF Migrate, every page named in the tables below)
> **Framework version:** Not versioned by Microsoft — CAF Plan and CAF Migrate are living
> documentation with no published release number. Treat the extraction date below as the version.
> **Extracted:** 2026-11-24
> **Verification method:** Manual read of each CAF Plan and CAF Migrate page cited in the tables
> below, on the extraction date. The retired SMART tool's own question text was never published and
> cannot be checked — see the warning below.

**Enumerated 2026-11-24. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

## Why this page changed

Microsoft deletes the **Strategic Migration Assessment and Readiness Tool** (SMART) in January
2027 (<https://learn.microsoft.com/assessments/Strategic-Migration-Assessment/>). It was a
15-minute multiple-choice readiness questionnaire listed under **Plan** in the Cloud Adoption
Framework's tools and templates, whose description named its subject areas: *"business planning,
training, security, and governance."*

Scout's assessment of this name was never a copy of SMART — Microsoft did not publish SMART's
questions, so Scout enumerated the CAF content SMART drew on. That content still exists. This
page now enumerates it directly, from **CAF Plan** and **CAF Migrate**, and extends it to cover
the whole migration sequence: plan, prepare, execute, optimise, decommission.

The `SMART-*` identifiers are kept, unchanged, for the items that existed before the re-base, so
questionnaire answer files already saved against them keep working. New items continue the same
scheme. The assessment itself is now named **CAF: Migrate readiness**, and `Microsoft: SMART
Migration` and `SMART` remain accepted as aliases.

The audit's DQ12 records why this file exists: *"Writing rules against a framework you have not
enumerated is how `waf.storage.yaml` happened"* — a rule file scoring a WAF pillar that does not
exist. `smart.migration.yaml` is written against this enumeration and nothing else, and every rule
in it cites an item number from the tables below.

## Verification method — and the one thing this enumeration is NOT

**What was read (2026-11-24):**

| Source | What it gave |
|---|---|
| CAF *Plan your migration* (`migrate/plan-migration`) | The five-step sequence, readiness and skills, data migration path, wave sequencing, migration method, rollback plan, stakeholder approval |
| CAF *Migration wave planning* (`migrate/migration-wave-planning`) | Grouping workloads into waves |
| CAF *Select your cloud migration strategies* (`plan/select-cloud-migration-strategy`) | The 8 R's and the business-driver-to-strategy mapping |
| CAF *Assess your workloads for cloud migration* (`plan/assess-workloads-for-cloud-migration`) | Discovery and assessment tooling, dependencies, compliance, SLA/RPO/RTO, application code, databases, risk register |
| CAF *Discover your existing workload inventory* (`plan/discover-existing-workload-inventory`) | The workload inventory and the discovery tools |
| CAF *Migration adoption plan* (`plan/migration-adoption-plan`) | Per-workload business details and management group placement |
| CAF *Prepare your organization for the cloud* and *Prepare your people for the cloud* (`plan/`) | Cloud responsibilities, skills |
| CAF *Prepare workloads for the cloud* (`migrate/prepare-workloads-cloud`) | Environment subscriptions, compatibility, testing, infrastructure as code |
| CAF *Execute migration to cloud* (`migrate/execute-migration`) | Change freeze, cutover, data integrity, fallback, stabilisation |
| CAF *Optimize workloads after migration* (`migrate/optimize-workloads-after-migration`) | Monitoring, cost, backup validation, hybrid dependencies |
| CAF *Decommission source workloads* (`migrate/decommission-source-workload`) | Approval and data retention |

**⚠️ What this is not.** Microsoft's SMART question text and numbering were never published —
SMART was delivered only as an interactive assessment, and the identifiers below are **Scout's**,
not Microsoft's. This enumeration is the CAF content a migration-readiness review rests on, not a
transcription of the retired tool. Any coverage percentage published against this file must say
so.

**Product name.** Microsoft's Azure Migrate documentation now calls the product **Azure Catalyst**.
The Azure resource types are unchanged (`microsoft.migrate/*`), so Scout's queries still match.
Where the tables say "Azure Migrate", read either name.

**One source is a product page, not CAF.** SMART-C6 (public network access on a migrate project)
has no current CAF source. It is checked against the product guide
<https://learn.microsoft.com/azure/migrate/how-to-use-azure-migrate-with-private-endpoints>, which
also says the project may need to allow traffic from all networks. That is why Scout asks the
question and shows evidence instead of scoring it Fail.

**Shelf life.** Microsoft is actively rewriting CAF pages (see the audit's §8 currency warnings).
Re-verify before quoting, and re-date this page when you do.

## The enumeration

All sources are under `https://learn.microsoft.com/azure/cloud-adoption-framework/`. "Evidence"
says what Scout reads. **Manual** items are questions for the customer; a tool reading ARM cannot
evidence whether a business case was agreed.

### A — Business planning and strategy (CAF Plan)

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-A1 | Business goals for the migration are defined and agreed with stakeholders | `plan/select-cloud-migration-strategy#determine-business-drivers-before-migration` | Manual |
| SMART-A2 | A business driver is identified per workload, and maps to one of the 8 R's | `plan/select-cloud-migration-strategy#determine-business-drivers-before-migration` | Manual |
| SMART-A3 | A gap analysis exists between each workload's current and target state | `plan/select-cloud-migration-strategy#determine-business-drivers-before-migration` | Manual |
| SMART-A4 | Migration waves are sequenced lowest-risk first | `migrate/plan-migration#determine-the-migration-sequence`, `migrate/migration-wave-planning` | Manual |
| SMART-A5 | The cloud operating model and responsibilities are defined | `plan/prepare-organization-for-cloud#plan-your-cloud-responsibilities` | Manual |
| SMART-A6 | A cost estimate exists for the target Azure architecture | `plan/estimate-total-cost-of-ownership` | Manual |

SMART-A4 previously cited `migrate/concepts-migration-planning`. That page is an Azure Migrate
product page, not CAF, and is no longer used.

### B — People, skills and training

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-B1 | The team's Azure and migration-tooling skills have been evaluated | `migrate/plan-migration#assess-migration-readiness-and-skills` | Manual |
| SMART-B2 | External expertise is engaged where a capability gap was found | `migrate/plan-migration#assess-migration-readiness-and-skills`, `plan/prepare-people-for-cloud` | Manual |

### C — Discovery, assessment and tooling

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-C1 | An Azure Migrate project exists for the estate being migrated | `plan/discover-existing-workload-inventory#discover-workload-inventory` | Automated — `Migration/AzureMigrateProjects` |
| SMART-C2 | Discovery is running — a discovery site is registered | `plan/discover-existing-workload-inventory#discover-workload-inventory`, tool table in `plan/assess-workloads-for-cloud-migration` | Automated — `Migration/AzureMigrateDiscoverySites` |
| SMART-C3 | Assessments have been created, not just a project | `plan/assess-workloads-for-cloud-migration` | Automated — assessment projects |
| SMART-C4 | Database workloads have a migration path — DMS or an equivalent | `plan/assess-workloads-for-cloud-migration#assess-databases`, `migrate/execute-migration` | Automated — `Migration/DatabaseMigrationServices` |
| SMART-C5 | Bulk data transfer is planned where the volume needs it (Data Box / Stack Edge) | `migrate/plan-migration#choose-your-data-migration-path` | Manual, pre-filled with any Data Box or Stack Edge found |
| SMART-C6 | Azure Migrate project public network access has been reviewed | Product guide (no current CAF source), see above | Manual, pre-filled with projects that allow public access |
| SMART-C7 | A private migration path exists — an ExpressRoute circuit or a VPN gateway | `migrate/plan-migration#choose-your-data-migration-path` | Automated — `Networking/ExpressRouteCircuits`, `Networking/VirtualNetworkGateways` |

SMART-C5 reads its evidence but does not score it: CAF ranks the data migration path as
ExpressRoute, then VPN, then Data Box for large offline transfers, then the public internet for
non-sensitive data. Having no Data Box is not a failure.

SMART-C6 was previously an automated check that failed when public access was enabled. It is now
manual, because enabling private endpoints can still leave the project allowing traffic from all
networks, which contradicts the old assertion.

### D — Landing zone readiness (CAF Ready, prerequisite of `migrate/plan-migration`)

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-D1 | An Azure landing zone exists before workloads are migrated into it | `migrate/plan-migration` prerequisites (CAF Ready) | Manual — use the `CAF: Azure Landing Zone` assessment |
| SMART-D2 | Target subscriptions are organised under a management group hierarchy | `plan/migration-adoption-plan`, `migrate/prepare-workloads-cloud#deploy-all-workload-resources` | Automated — `Management/ManagementGroups` |
| SMART-D3 | Workload environments are separated across subscriptions | `migrate/prepare-workloads-cloud#deploy-all-workload-resources` | Automated — subscription count (see note) |
| SMART-D4 | Role-based access control is assigned in the target scope | `migrate/prepare-workloads-cloud#deploy-all-workload-resources` | Automated — `governance.roleAssignments` |
| SMART-D5 | A cost management budget exists for the target scope | `migrate/prepare-workloads-cloud#deploy-all-workload-resources`, `migrate/optimize-workloads-after-migration#validate-cost-monitoring` | Automated — `governance.budgets` |

SMART-D3 counts the subscriptions Scout scanned. It does not read which environment each hosts,
so a scan scoped to a single subscription fails it by construction.

### E — Security

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-E1 | Migrated servers land under Defender for Cloud coverage | `migrate/prepare-workloads-cloud#resolve-compatibility-issues`, `migrate/optimize-workloads-after-migration` | Automated — `Security/DefenderPricing` |
| SMART-E2 | Target resources use private connectivity where required | `migrate/plan-migration#choose-your-data-migration-path` | Automated — `networking.privateEndpoints`; the `xr.*` rules score per-resource coverage |

### F — Governance and recovery

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-F1 | Policy is applied to the target scope before workloads arrive | `migrate/prepare-workloads-cloud#deploy-all-workload-resources`, `plan/prepare-organization-for-cloud#plan-your-cloud-responsibilities` | Automated — `Management/PolicyComplianceStates` |
| SMART-F2 | Migrated workloads are brought under backup protection | `migrate/optimize-workloads-after-migration#validate-critical-configurations` | Automated — virtual machines joined to backup protected items (same evidence as `XR-BKP-01`) |

### G — Workload assessment (CAF Plan)

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-G1 | A workload inventory exists with business details for each workload | `plan/discover-existing-workload-inventory`, `plan/migration-adoption-plan#details-on-each-workload` | Manual |
| SMART-G2 | Internal and external dependencies are mapped and validated with workload owners | `plan/assess-workloads-for-cloud-migration#map-internal-and-external-dependencies` | Manual |
| SMART-G3 | Regulatory and compliance requirements are identified for each workload | `plan/assess-workloads-for-cloud-migration#assess-compliance-and-operational-requirements` | Manual |
| SMART-G4 | SLAs, RPOs and RTOs are documented for each workload | `plan/assess-workloads-for-cloud-migration#assess-compliance-and-operational-requirements` | Manual |
| SMART-G5 | Application code has been assessed for Azure compatibility | `plan/assess-workloads-for-cloud-migration#assess-application-code` | Manual |
| SMART-G6 | A risk register exists with mitigations, owners and status | `plan/assess-workloads-for-cloud-migration#create-and-maintain-a-risk-register` | Manual |
| SMART-G7 | No workload depends on an operating system that is out of support | `plan/assess-workloads-for-cloud-migration#assess-workload-components`, `migrate/prepare-workloads-cloud#resolve-compatibility-issues` | Manual — Scout does not collect the guest OS version |

### H — Migration plan and approval (CAF Migrate: plan)

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-H1 | A migration method is chosen for each workload | `migrate/plan-migration#choose-the-migration-method-for-each-workload` | Manual |
| SMART-H2 | The migration schedule avoids critical business events | `migrate/plan-migration#create-a-detailed-migration-schedule` | Manual |
| SMART-H3 | A rollback plan is defined and has been tested | `migrate/plan-migration#define-rollback-plan` | Manual |
| SMART-H4 | Stakeholders have signed off the migration plan and the rollback authority | `migrate/plan-migration#engage-stakeholders-on-migration-plan` | Manual |

### I — Prepare workloads (CAF Migrate: prepare)

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-I1 | Managed identities are in use instead of hard-coded accounts | `migrate/prepare-workloads-cloud#resolve-compatibility-issues` | Automated — user-assigned identities only (see note) |
| SMART-I2 | Network Watcher is available to validate connectivity | `migrate/prepare-workloads-cloud#validate-network-connectivity` | Automated — `Networking/NetworkWatchers` |
| SMART-I3 | Azure Load Testing is available to validate performance | `migrate/prepare-workloads-cloud#conduct-functional-and-performance-testing` | Automated — load testing resources |
| SMART-I4 | Functional, performance and user acceptance testing passed in the test environment | `migrate/prepare-workloads-cloud#validate-workload-functionality` | Manual |
| SMART-I5 | Infrastructure is defined as code and held in version control | `migrate/prepare-workloads-cloud#create-reusable-infrastructure` | Manual |

SMART-I1 reads user-assigned managed identities only. System-assigned identities on individual
resources are not collected, so an estate that uses only those fails the rule without being wrong.
SMART-I2 reports whether any Network Watcher exists; it does not check every target region. SMART-I3
is an existence check, and another load-testing tool is an acceptable alternative.

### J — Execute migration (CAF Migrate: execute)

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-J1 | A change freeze is in force on the source systems during the migration window | `migrate/execute-migration#implement-a-change-freeze` | Manual |
| SMART-J2 | Data integrity is validated after cutover | `migrate/execute-migration#execute-cutover` | Manual |
| SMART-J3 | The source environment is kept as a fallback through the stabilisation period | `migrate/execute-migration#maintain-fallback-option` | Manual |
| SMART-J4 | Stabilisation support is staffed and the CMDB is updated | `migrate/execute-migration#support-workload-during-stabilization` | Manual |

### K — Optimise and decommission (CAF Migrate)

| # | Item | Source | Evidence |
|---|---|---|---|
| SMART-K1 | Alert rules exist to monitor migrated workloads | `migrate/optimize-workloads-after-migration#validate-workload-monitoring` | Automated — metric, log-search and activity-log alert rules |
| SMART-K2 | Azure Hybrid Benefit is applied to eligible Windows Server virtual machines | `plan/assess-workloads-for-cloud-migration`, `migrate/decommission-source-workload#azure-tools-and-resources` | Automated — `compute.virtualMachines` license type |
| SMART-K3 | On-premises dependencies that cannot migrate are brought under Azure Arc | `migrate/plan-migration#address-split-environment-operations`, `migrate/optimize-workloads-after-migration#optimize-hybrid-and-multicloud-dependencies` | Manual, pre-filled with Arc-enabled servers found |
| SMART-K4 | Decommissioning of source workloads has formal stakeholder approval | `migrate/decommission-source-workload#obtain-stakeholder-approval-before-decommissioning` | Manual |
| SMART-K5 | Data that stays behind is classified and archived to meet retention obligations | `migrate/decommission-source-workload#preserve-data-for-compliance-and-recovery-needs` | Manual |

SMART-K2 cannot see licence entitlements: a Windows VM with no license type is a candidate, not
proof of overpayment. SMART-K3 never fails — an estate with nothing to keep on-premises has no Arc
servers and nothing wrong.

## What this means for the rule file

There are 49 items. 18 are **automated** — a tool reading ARM can evidence them. 31 are **manual**
because the answer is an agreement, a plan, a sign-off or a test result that lives outside Azure.
`smart.migration.yaml` marks those `manual: true` with the item cited, so they appear in the
report as questions for the customer rather than silently disappearing, and they are answerable
from a questionnaire answers file whether or not any migration data was collected. That is the
difference between "18 of 49 automatable" and a fabricated score of 100%.

When no Azure Migrate project, discovery site or migration service was collected, the rule file's
`requires` block holds the whole set at Unknown rather than scoring it, because zero unassessed
projects and no project at all are the same number and opposite findings. That covers the
automated items outside C as well (D to F, I, K), so an estate with no migration data gets no
automated score from this assessment; the manual items stay answerable from a questionnaire answers
file. A manual item that has evidence (C5, C6, K3) shows it, and never scores its absence.

## Related

- Rule file: `src/assess/rules/smart.migration.yaml`
- Assessment registry: `manifests/assessments.psd1` (assessment `CAF: Migrate readiness`)
