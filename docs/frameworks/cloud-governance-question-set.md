# CAF Govern — enumerated source for the Cloud Governance assessment (Assess: CAF Govern)

**Enumerated 2026-11-24. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

**Framework version:** Not versioned by Microsoft — the Cloud Adoption Framework Govern methodology
carries no release number. The extraction date above (2026-11-24) is the version, per
`docs/frameworks/README.md`; re-date this line when this file is next re-verified. This replaces the
2026-08-01 enumeration, which was built from the CAF Govern pages as read alongside the retired
interactive assessment; every item below is now cited to a CAF Govern page directly.

> **Source:** <https://learn.microsoft.com/azure/cloud-adoption-framework/govern/>

This is the AB#6811 enumeration for target #8 in the audit's fourteen-assessment programme
(`pmo/audits/AZURE-SCOUT-AUDIT.md` §14): *"Cloud Governance — policy data already collected …
Policy compliance state is collected and scored by nothing."* The audit's §8 Table 3 identifies this
as the **CAF Govern methodology** — a different axis from the "Governance" *design area* that
`caf.governance.yaml` already scores (that design area is part of Ready, covered in
`pmo/audits/AZURE-SCOUT-AUDIT.md` §8 Table 2, not this document). Per DQ12, no `caf.govern.yaml` (or
similarly named methodology file) is written until this enumeration exists.

## Why this page was re-based

Microsoft deletes its interactive **Cloud Governance** assessment on the Microsoft Assessments
platform in **January 2027**. Scout's earlier enumeration took the five-step process and seven
categories from the CAF Govern documentation but described itself as "almost certainly built on" that
assessment, whose question text was never published. That framing is retired. Scout's *Assess: Cloud
Governance* (its `Frameworks` entry is **CAF: Govern**) is now defined by the CAF Govern methodology
itself — the five-step process, the seven risk categories, the example risk register and the example
policies Microsoft publishes — and is extended to everything those pages now describe, not only what
the retired assessment asked.

The framework key inside the rule files stays `Cloud Governance`: the domain-score and report code
groups on it, and the assessment keeps its name as an alias.

## What CAF Govern is

Microsoft ships **two** distinct things under "governance," and this file is about the second one:

1. `caf.governance.yaml`'s subject — the Ready methodology's **Governance design area**, one of the
   8 landing-zone design areas, already enumerated and scored (10 recommendations, ~70% coverage
   per the audit).
2. **This file's subject** — the **Govern methodology**, one of CAF's seven core methodologies
   (Strategy, Plan, Ready, Adopt, Govern, Secure, Manage). Govern is a **five-step continuous
   process** — build a governance team, assess cloud risks, document policies, enforce policies,
   monitor compliance — applied across **seven risk categories**: regulatory compliance, security,
   cost, operations, data, resource management, AI. Step 1 is done once; steps 2 to 5 repeat.

Scout's rules therefore split along both axes. The **seven categories** are the seven scored areas
that read Azure (RC, SC, CM, OP, DG, RM, AI). The **process** (steps 1 to 3, plus the audit, review
and change-control practices around steps 4 and 5) is an eighth area, **Governance Process**
(`PROC`), that no Azure resource can evidence: every item in it is a manual question, scored when the
operator answers it (see [Questionnaire Answers](../assessment/questionnaire-answers.md)) and shown as
*Not assessed* until then.

## Verification method — and the limits

**What was read (2026-11-24):**

| Source | What it gave |
|---|---|
| [Build a cloud governance team](https://learn.microsoft.com/azure/cloud-adoption-framework/govern/) | Step 1: team function, members, executive sponsor, authority, scope, RACI matrix |
| [Assess cloud risks](https://learn.microsoft.com/azure/cloud-adoption-framework/govern/assess-cloud-risks) | Step 2: identify, analyse, document, communicate, review; the twelve-field risk register and example list |
| [Document cloud governance policies](https://learn.microsoft.com/azure/cloud-adoption-framework/govern/document-cloud-governance-policies) | Step 3: standard policy format and fields, distribution, review and change control; the sixteen example policies RC01 to AI02 |
| [Enforce cloud governance policies](https://learn.microsoft.com/azure/cloud-adoption-framework/govern/enforce-cloud-governance-policies) | Step 4: enforcement approach, per-category "Automate … governance" Azure facilitation, manual enforcement, example compliance checklists |
| [Monitor cloud compliance](https://learn.microsoft.com/azure/cloud-adoption-framework/govern/monitor-cloud-governance) | Step 5: per-category "Configure monitoring for … governance" and the cloud governance alerts guidance, remediation plan, regular audits |

**Limits.** The `CGOV-*` identifiers below are **Scout's own**; Microsoft does not number these
items. Microsoft's example policy IDs (RC01 to AI02) are examples, not requirements, and are cited
here only where a Scout rule reads the thing the example describes.

**Shelf life.** CAF Govern is actively maintained content (the AI category and the monitor and
enforce pages were all extended recently); re-verify before quoting. The AI content-filtering
built-in policies are **preview** definitions: their identifiers can change at general availability.

## The enumeration

"Scout can evidence?" uses three marks: ✅ a rule scores it from collected Azure data; ⚠️ a rule
scores part of it, or reads evidence but cannot score it; ❌ not observable from Azure, so the item is
a manual question. Citations name the CAF Govern page anchor each item comes from.

### RC — Regulatory compliance

Citations: `monitor-cloud-governance#configure-monitoring-for-regulatory-compliance-governance`,
`enforce-cloud-governance-policies#automate-regulatory-compliance-governance`,
`monitor-cloud-governance#azure-facilitation-configuring-cloud-governance-alerts`.

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-RC-01 | Policy compliance dashboards are used to get compliance data on assigned policies | ✅ `domains.management.policyComplianceStates` (needs `-IncludePolicyCompliance`) |
| CGOV-RC-02 | Causes of noncompliance are determined and root-caused, not just observed | ❌ Compliance state is collected; no root-cause field |
| CGOV-RC-03 | A built-in regulatory-compliance initiative (PCI DSS, HIPAA/HITRUST, ISO 27001, NIST, CMMC, FedRAMP, …) is assigned | ✅ Policy assignment whose initiative display name names a recognised standard; a renamed assignment is not recognised |
| CGOV-RC-04 | Alerts are configured for regulatory noncompliance | ❌ Activity-log alert rules are listed as evidence; their condition is not collected |
| CGOV-RC-05 | Sensitive-data compliance is monitored and reported on a defined cadence in Microsoft Purview | ❌ Purview accounts listed as evidence; scans and report cadence are not collected |

### SC — Security

Citations: `monitor-cloud-governance#configure-monitoring-for-security-governance`,
`enforce-cloud-governance-policies#automate-security-governance`,
`monitor-cloud-governance#azure-facilitation-configuring-cloud-governance-alerts`.

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-SC-01 | Security recommendations are reviewed and secure score is monitored over time | ⚠️ Partial — `security.defenderSecureScores` and `defenderAssessments` are point-in-time, not a trend |
| CGOV-SC-02 | A regulatory-compliance dashboard is checked against common security frameworks (MCSB, CIS, etc.) | ⚠️ Partial — `domains.management.policyComplianceStates` carries the data; nothing distinguishes which framework initiative each state belongs to |
| CGOV-SC-03 | Identity governance monitoring is configured — audit/sign-in/provisioning logs, identity secure score, an identity-governance dashboard; MFA and access reviews | ❌ Sign-in/audit logs are not collected |
| CGOV-SC-04 | Defender for Cloud paid plans are enabled so security alerts are generated | ✅ `security.defenderPlans` (`pricingTier == Standard`); not assessed when no plan rows were collected |
| CGOV-SC-05 | Just-in-time privileged access is used (PIM eligible assignments) | ⚠️ `governance.pimEligibility`; the ingestor never collects it today (needs Entra ID P2 and a Graph permission), so this reads *Not assessed* |
| CGOV-SC-06 | Defender security alerts are reviewed, routed to an owner and resolved | ❌ `security.defenderAlerts` listed as evidence only (rows exist only with `-IncludePolicyCompliance`) |
| CGOV-SC-07 | A security-standard initiative (MCSB, CIS, NIST SP 800-53, ISO 27001) is assigned | ✅ Policy assignment whose initiative display name names the standard |

### CM — Cost management

Citations: `monitor-cloud-governance#configure-monitoring-for-cost-management-governance`,
`enforce-cloud-governance-policies#automate-cost-governance`,
`monitor-cloud-governance#azure-facilitation-configuring-cloud-governance-alerts`.

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-CM-01 | Cost analysis gives full visibility into cloud costs | ⚠️ Partial — reservations and Advisor score give partial visibility; no full cost-analysis dataset |
| CGOV-CM-02 | Budgets are created that align with the desired cloud investment | ✅ `governance.budgets` (subscription scope) |
| CGOV-CM-03 | Cost-optimization recommendations are used to detect idle resources | ✅ `$.advisor[?(@.Category == 'Cost')]`, `$.costCleanup.orphanedDisks`, `$.costCleanup.orphanedPips` |
| CGOV-CM-04 | Cost anomalies are identified and a cost anomaly alert is configured | ❌ The alert (a Cost Management scheduled action) is not collected; `finops.anomalies` is listed as evidence. `src/analyze/Get-ScoutCostAnomaly.ps1` exists but nothing in `Invoke-Collect.ps1` calls it |
| CGOV-CM-05 | Budget alerts are set at the resource-group level (Microsoft example policy CM01) | ❌ Budgets are listed per subscription only, so a resource-group budget cannot be proven absent; any collected resource-group budget row is shown as evidence |
| CGOV-CM-06 | Every budget has alert notifications configured | ✅ `governance.budgets[*].properties.notifications` |
| CGOV-CM-07 | Cost-intensive resource types are blocked by a "Not allowed resource types" policy | ✅ Policy assignment of the built-in definition |
| CGOV-CM-08 | Tag inheritance for cost allocation is enforced by Azure Policy | ⚠️ The "Inherit a tag" policy route only; the Cost Management tag-inheritance setting is not collected |

### OP — Operations

Citations: `monitor-cloud-governance#configure-monitoring-for-operations-governance`,
`enforce-cloud-governance-policies#automate-operations-governance`,
`monitor-cloud-governance#azure-facilitation-configuring-cloud-governance-alerts`.

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-OP-01 | Policy compliance is tracked for operations-scoped governance policies | ✅ `domains.management.policyComplianceStates` (generic — not operations-specific) |
| CGOV-OP-02 | Logs and metrics are monitored for availability and performance | ⚠️ Partial — `management.logAnalyticsWorkspaces` existence only, not coverage or content |
| CGOV-OP-03 | Advisor is used to monitor reliability/security/performance/cost, with alerts set on new recommendations | ❌ An Advisor alert **is** an activity-log alert rule (category `Recommendation`); Scout collects the rule but not its condition, so it cannot be told from other activity-log alerts. Rows are listed as evidence |
| CGOV-OP-04 | Service Health and Resource Health alerts are configured | ❌ Same limitation: both are activity-log alert rules whose condition is not collected |
| CGOV-OP-05 | Activity-log alert rules are enabled and routed to an action group | ✅ `monitor.activityLogAlertRules` (`enabled` and `actionGroupCount > 0`) — the readable half of OP-03/OP-04 |
| CGOV-OP-06 | Alerts are configured on specific logs and metrics | ✅ `monitor.metricAlertRules`, `monitor.scheduledQueryRules` (enabled) — existence only |

### DG — Data

Citations: `monitor-cloud-governance#configure-monitoring-for-data-governance`,
`enforce-cloud-governance-policies#automate-data-governance`.

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-DG-01 | Data compliance, management, and usage are monitored (Microsoft Purview) | ⚠️ `domains.analytics.purviewAccounts` — a deployed account is necessary but not sufficient evidence |
| CGOV-DG-02 | Dashboards monitor compliance with data-plane policies | ❌ Data-plane policy state is not collected |
| CGOV-DG-03 | Encryption policies are assigned (secure transfer, minimum TLS version, customer-managed keys) | ✅ Policy assignment of the built-in definitions, or the Microsoft cloud security benchmark initiative that contains them |
| CGOV-DG-04 | Encryption in transit: every storage account requires secure transfer | ✅ `domains.storage.storageAccounts[*].httpsOnly` |
| CGOV-DG-05 | Encryption in transit: every storage account enforces TLS 1.2 or higher | ✅ `domains.storage.storageAccounts[*].minTls` |
| CGOV-DG-06 | Data lifecycle policies are enabled for all sensitive data (Microsoft example policy DG02) | ❌ Storage management policies and Purview retention are not collected |

### RM — Resource management

Citations: `monitor-cloud-governance#configure-monitoring-for-resource-management-governance`,
`enforce-cloud-governance-policies#automate-resource-management-governance`.

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-RM-01 | Policies on resource deployments — e.g. tag-enforcement policies — are monitored for compliance | ⚠️ `governance.policyAssignments` existence; the specific policies are RM-03 to RM-05 |
| CGOV-RM-02 | A resource-management hierarchy exists (management groups beyond the tenant root) | ✅ `governance.managementGroups` |
| CGOV-RM-03 | Deployments are restricted to approved regions by an "Allowed locations" policy | ✅ Policy assignment of the built-in definitions |
| CGOV-RM-04 | Resource types that add unnecessary risk are restricted by a resource-type policy | ✅ Policy assignment of "Not allowed resource types" or "Allowed resource types" |
| CGOV-RM-05 | Tags are enforced by Azure Policy (require, add, append or inherit a tag) | ✅ Policy assignment of the built-in tag definitions |
| CGOV-RM-06 | A tagging and naming strategy is defined and applied | ❌ A document, not a resource property (collected tags are listed as evidence) |
| CGOV-RM-07 | Infrastructure as code is used to deploy resources (Microsoft example policy RM01) | ❌ `management.deployments` listed as evidence; source control and pipeline use are not collected |

### AI — Artificial intelligence

Citations: `monitor-cloud-governance#configure-monitoring-for-ai-governance`,
`enforce-cloud-governance-policies#automate-ai-governance`,
`monitor-cloud-governance#azure-facilitation-configuring-cloud-governance-alerts` (AI governance alerts).

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-AI-01 | AI system outputs are monitored — abuse monitoring and content filtering configured | ❌ Content filters (`raiPolicies`) and abuse monitoring are not collected; AI-03 scores the readable part |
| CGOV-AI-02 | Customer-facing AI systems are red-teamed on a recurring cadence | ❌ Organisational/process; no Azure artefact records a red-team cadence |
| CGOV-AI-03 | AI content filtering is enforced by Azure Policy | ✅ Policy assignment of the (preview) Cognitive Services content-filtering definitions, or a policy named for content filtering. Evidences the policy is assigned, not that deployments are at "medium or higher" |
| CGOV-AI-04 | Microsoft Defender for AI Services is enabled | ✅ `security.defenderPlans` (plan `AI`, `Standard`); not assessed when no plan rows were collected |

### PROC — The governance process itself

Citations: `govern/` (step 1), `assess-cloud-risks` (step 2), `document-cloud-governance-policies`
(step 3), `enforce-cloud-governance-policies` and `monitor-cloud-governance` (steps 4 and 5). All
eleven are organisational — Scout reads the *result* of governance being enforced, never the process
that produced the policy — so each is a manual question, scored when answered.

| # | Item | Scout can evidence? |
|---|---|---|
| CGOV-PROC-01 | A cloud governance team is formally established with a charter, defined membership and cross-functional representation | ❌ Organisational |
| CGOV-PROC-02 | Governance policies are documented in a standard format (policy ID, category, risk ID, statement, purpose, scope, remediation, monitoring tool) | ❌ Organisational — Azure Policy objects carry a display name and description, not this authoring standard |
| CGOV-PROC-03 | Policies are distributed via a centralised repository, with compliance checklists for teams | ❌ Organisational |
| CGOV-PROC-04 | A compliance baseline was established and is tracked against over time | ❌ Scout collects a single point-in-time snapshot per run; no historical baseline is retained between runs |
| CGOV-PROC-05 | Noncompliance remediation has a defined timeline and escalation path scaled to risk severity | ❌ Organisational |
| CGOV-PROC-06 | A named executive sponsor grants the team its authority, and a RACI matrix assigns governance tasks | ❌ Organisational |
| CGOV-PROC-07 | A risk register exists with Microsoft's twelve fields and is reviewed on a schedule | ❌ Organisational |
| CGOV-PROC-08 | Every governance policy is linked to a risk ID and names the tool that monitors it | ❌ Azure Policy assignments carry no risk ID |
| CGOV-PROC-09 | Governance training is provided to the teams the policies apply to | ❌ Organisational |
| CGOV-PROC-10 | Internal audits (and external audits where required) validate compliance monitoring | ❌ Organisational |
| CGOV-PROC-11 | Policy change control: scheduled and event-based review, and a defined way to add, edit or remove policies | ❌ Organisational |

The twelve risk-register fields CGOV-PROC-07 asks about are Microsoft's: ID, management status,
category, description, probability, impact, priority, level (major threat, subrisk, risk driver),
management strategy (mitigate, accept, avoid or transfer), management enforcement, owner and closure
date.

## Microsoft's example policies and where Scout reads them

Microsoft publishes sixteen example governance policies. They are examples of what an organisation's
policy statements might say, not requirements; this table shows which Scout rule reads the thing each
one describes.

| Example | Statement (short) | Scout rule |
|---|---|---|
| RC01 | Purview must monitor sensitive data | CGOV-DG-01, CGOV-RC-05 |
| RC02 | Daily sensitive-data compliance reports from Purview | CGOV-RC-05 |
| SC01 | MFA enabled for all users | CGOV-SC-03 (manual) |
| SC02 | Monthly access reviews in ID Governance | CGOV-SC-03 (manual) |
| SC03 | One specified GitHub organisation hosts all code | Not read — GitHub is outside Scout's collection |
| SC04 | Public libraries go through the quarantine pattern | Not read — a development practice |
| CM01 | Budget alerts at resource-group level | CGOV-CM-05 (manual), CGOV-CM-02, CGOV-CM-06 |
| CM02 | Advisor cost recommendations reviewed | CGOV-CM-03 |
| OP01 | Production workloads active-passive across regions | Not read here — covered by the reliability assessments |
| OP02 | Mission-critical workloads active-active across regions | Not read here — covered by the reliability assessments |
| DG01 | Encryption in transit and at rest, monitored by Azure Policy | CGOV-DG-03, CGOV-DG-04, CGOV-DG-05 |
| DG02 | Data lifecycle policies in Purview | CGOV-DG-06 (manual) |
| RM01 | Bicep used to deploy resources | CGOV-RM-07 (manual) |
| RM02 | Tags enforced by Azure Policy | CGOV-RM-05 |
| AI01 | AI content filtering at medium or higher | CGOV-AI-03 (assigned), CGOV-AI-01 (manual) |
| AI02 | Customer-facing AI red-teamed monthly | CGOV-AI-02 (manual) |

## What this means for the rule file

**54 items: 26 are scored from data Scout collects, 28 are manual questions.** The 28 manual items are
the process (11), plus 17 inside the risk categories where the thing being asked is a human review, a
setting in a tenant service Scout does not read, or a rule's condition that is not collected.

How the automated rules avoid a false Fail, because absence of evidence is not evidence of absence:

- Rules that read **policy assignments** (RC-03, SC-07, CM-07, CM-08, DG-03, RM-03 to RM-05, AI-03) are
  gated on `governance.policyAssignmentsAvailable`: if the policy read failed they report *Not
  assessed*. They recognise **direct assignments** by built-in definition identifier (or, for an
  initiative, by its display name). An assignment made under a custom name, or a definition wrapped
  inside a custom initiative, is not recognised — the remediation text on each rule says so.
- Rules that read **Defender plans** (SC-04, AI-04) are gated on the plan rows themselves: no rows
  means *Not assessed*, never "plans are off". SC-05 (PIM) is gated on
  `governance.pimEligibilityAvailable`, which is always false today.
- Rules that compute a **percentage** (CM-06, DG-04, DG-05) report *Unknown* when there is nothing to
  measure a percentage of (no budgets, no storage accounts), never a 0% Fail.
- Rules that read **Monitor** or **Storage** data need those categories in the assessment's collect
  (`Monitor` for OP-05/OP-06, `Storage` for DG-04/DG-05). A saved collect made without them is
  refused up front by the collect-provenance check rather than scored as empty.

The Governance Process area is excluded from the headline score until at least one of its questions is
answered, exactly as a manual rule in any other area is. A tenant that answers none of them is not
penalised for it; it is simply shown *Not assessed*.

`Management/PolicyComplianceStates` remains the single largest lever: RC-01, SC-02 and OP-01 all
resolve to it, and it is populated only when the collect is run with `-IncludePolicyCompliance`.
