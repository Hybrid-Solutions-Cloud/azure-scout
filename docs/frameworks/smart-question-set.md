# SMART — enumerated source for the Strategic Migration Assessment

> **Source:** <https://learn.microsoft.com/assessments/Strategic-Migration-Assessment/>
> **Framework version:** Not versioned by Microsoft — SMART is a living interactive tool with no
> published release number. Treat the extraction date below as the version.
> **Extracted:** 2026-07-31
> **Verification method:** Manual read of the SMART landing page plus the five CAF pages it draws
> on (full list in "Verification method" below). No API or transcript exists for SMART's own
> question text — see the warning below.

**Enumerated 2026-07-31. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

The audit's DQ12 records why this file exists: *"Writing rules against a framework you have not
enumerated is how `waf.storage.yaml` happened"* — a rule file scoring a WAF pillar that does not
exist. `smart.migration.yaml` is written against this enumeration and nothing else, and every rule
in it cites an item number from the tables below.

## What SMART is

Microsoft's **Strategic Migration Assessment and Readiness Tool**
(<https://learn.microsoft.com/assessments/Strategic-Migration-Assessment/>) — a 15-minute
multiple-choice readiness questionnaire that prepares an organisation for a scale migration to
Azure. It is listed under **Plan** in the Cloud Adoption Framework's tools and templates
(<https://learn.microsoft.com/azure/cloud-adoption-framework/resources/tools-templates>), whose
description names its subject areas: *"business planning, training, security, and governance."*

## Verification method — and the one thing this enumeration is NOT

**What was read (2026-07-31):**

| Source | What it gave |
|---|---|
| The SMART assessment landing page | The tool's stated purpose and its four named subject areas |
| CAF *Tools and templates* | SMART's placement in the Plan phase |
| CAF *Plan your migration* (`migrate/plan-migration`) | The five-step migration sequence and the readiness/skills step |
| CAF *Select your cloud migration strategies* | The 8 R's and the business-driver-to-strategy mapping |
| CAF *Build migration plan with Azure Migrate* (`migrate/concepts-migration-planning`) | Assessment-driven prioritisation and the "start small" sequencing guidance |
| CAF *Assess your workloads for cloud migration* | The named discovery/assessment/migration tooling |

**⚠️ Microsoft's own question TEXT and question NUMBERS are not published.** SMART is delivered
only as an interactive assessment; its items are not in the documentation, not in an API, and not
extractable from the page, which renders a client-side application shell. Anyone claiming to have
transcribed Microsoft's numbered SMART questions from documentation has invented them.

So this enumeration is **the published CAF Migrate content SMART assesses readiness against**,
organised under SMART's four stated subject areas plus the two the CAF Migrate sequence adds. The
`SMART-*` identifiers below are **Scout's**, stable and citable, and they are not Microsoft item
numbers. Any coverage percentage published against this file must say so.

**Shelf life.** Microsoft is actively rewriting CAF pages (see the audit's §8 currency warnings).
Re-verify before quoting, and re-date this page when you do.

## The enumeration

### A — Business planning (SMART subject area 1)

| # | Item | Source | Scout can evidence? |
|---|---|---|---|
| SMART-A1 | Business goals for the migration are defined and agreed with stakeholders | `plan/select-cloud-migration-strategy` | ❌ Organisational |
| SMART-A2 | A business driver is identified per workload, and maps to one of the 8 R's | `plan/select-cloud-migration-strategy` | ❌ Organisational |
| SMART-A3 | A gap analysis exists between each workload's current and target state | `plan/select-cloud-migration-strategy` | ❌ Organisational |
| SMART-A4 | Migration waves are sequenced lowest-risk first, not all-at-once | `migrate/concepts-migration-planning` | ⚠️ Partial — assessment groups |

### B — People, skills and training (SMART subject area 2)

| # | Item | Source | Scout can evidence? |
|---|---|---|---|
| SMART-B1 | The team's Azure and migration-tooling skills have been evaluated | `migrate/plan-migration` | ❌ Organisational |
| SMART-B2 | External expertise is engaged where a capability gap was found | `migrate/plan-migration` | ❌ Organisational |

### C — Migration process and tooling (the CAF Migrate sequence)

| # | Item | Source | Scout can evidence? |
|---|---|---|---|
| SMART-C1 | An Azure Migrate project exists for the estate being migrated | `migrate/concepts-migration-planning` | ✅ `Migration/AzureMigrateProjects` |
| SMART-C2 | Discovery is running — a discovery site is registered and reporting | `plan/assess-workloads-for-cloud-migration` | ✅ `Migration/AzureMigrateDiscoverySites` |
| SMART-C3 | Assessments have been created, not just a project | `migrate/assessment-report` | ✅ `Migration/AzureMigrateAssessments` |
| SMART-C4 | Database workloads have a migration path — DMS or an equivalent | `plan/assess-workloads-for-cloud-migration` | ✅ `Migration/DatabaseMigrationServices` |
| SMART-C5 | Bulk data transfer is planned where the volume needs it (Data Box / Stack Edge) | `plan/assess-workloads-for-cloud-migration` | ✅ `Migration/DataBox`, `Migration/StackEdge` |
| SMART-C6 | Migrate projects are not left publicly reachable when private access was intended | `migrate/migrate-services-overview` | ✅ `publicNetworkAccess` on the project |

### D — Landing zone readiness (CAF Ready, prerequisite of `migrate/plan-migration`)

| # | Item | Source | Scout can evidence? |
|---|---|---|---|
| SMART-D1 | An Azure landing zone exists before workloads are migrated into it | `migrate/plan-migration` prerequisites | ✅ via the `CAF: Azure Landing Zone` assessment |
| SMART-D2 | Target subscriptions are organised under a management group hierarchy | CAF Ready | ✅ `Management/ManagementGroups` |

### E — Security (SMART subject area 3)

| # | Item | Source | Scout can evidence? |
|---|---|---|---|
| SMART-E1 | Migrated servers land under Defender for Cloud coverage | CAF Secure | ✅ `Security/DefenderPricing` |
| SMART-E2 | Migration tooling and target resources use private connectivity where required | CAF Ready | ✅ cross-resource rules (`xr.*`) |

### F — Governance (SMART subject area 4)

| # | Item | Source | Scout can evidence? |
|---|---|---|---|
| SMART-F1 | Policy is applied to the target scope before workloads arrive | CAF Govern | ✅ `Management/PolicyComplianceStates` |
| SMART-F2 | Migrated workloads are brought under backup protection | CAF Manage — *Define reliability requirements* | ✅ cross-resource rule `XR-BKP-01` |

## What this means for the rule file

Six of the eighteen items are **organisational** — a tool reading ARM cannot evidence whether a
business case was agreed. `smart.migration.yaml` marks those `manual: true` with the item cited, so
they appear in the report as questions for the customer rather than silently disappearing. That is
the difference between "SMART coverage is 12 of 18 automatable" and a fabricated score of 100%.
