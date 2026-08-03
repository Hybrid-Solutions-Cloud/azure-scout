---
description: Executive overview of Azure Scout and the exact least-privilege access it needs — Azure RBAC, Microsoft Entra, Microsoft Graph and Azure DevOps.
---

# Azure Scout — overview and required access

**Audience:** the sponsor approving the engagement, and the platform or security team granting the
access. Sections 1–2 are the executive summary; sections 3 onward are the access request.

---

## 1. What Azure Scout is

Azure Scout inventories an Azure estate and assesses it against Microsoft's own published
frameworks, then produces the deliverables an assessment engagement is normally written by hand:
a Word report, a PowerPoint readout, a PDF, an Excel evidence pack, an interactive HTML dashboard
and a Power BI project.

It is **read-only**. Scout never creates, modifies or deletes anything in the tenant, and it holds
no standing access — it runs under credentials you grant, for as long as you choose to grant them.

### What it answers

| Question | How |
|---|---|
| What is actually deployed? | Full resource inventory across every Azure service category, plus Microsoft Entra objects |
| How does it measure against Microsoft's guidance? | Scored against the **Cloud Adoption Framework** landing-zone design areas and the **Well-Architected Framework** pillars |
| Where is the regulatory exposure? | Microsoft Cloud Security Benchmark, plus every regulatory initiative already assigned in the scope |
| What should be fixed first? | Findings ranked by severity, each carrying its supporting number and the affected resource IDs |
| What was *not* checked? | Stated explicitly — see below |

### What makes the output usable

- **Every finding carries its supporting number and the affected resources.** "60 of 198 storage
  accounts", never "storage accounts are misconfigured". A finding that cannot be actioned is
  decoration.
- **"Not assessed" is a first-class result.** A control with no automated rule, or one whose data
  source was unavailable, is reported as *not assessed* — never as a pass and never as a zero. It
  is excluded from the compliance denominator rather than quietly counted as a failure.
- **The deck states what was out of scope**, and carries exactly one "act on this first" slide
  naming a specific item.
- **A triage column on every evidence row** — real / by-design / sandbox / legacy — seeded for
  your reviewer rather than guessed. This is what turns a raw finding list into a decision.

### What it is not

Scout does not read data. It reads the **control plane**: resource configuration, policy state and
directory metadata. It does not read blob contents, database rows, Key Vault secret *values*, mail
or documents. Key Vault items are read as names and expiry dates only.

---

## 2. How an engagement runs

1. Access is granted (section 3), typically for the duration of the assessment.
2. Scout runs from a workstation or a pipeline. A mid-size estate takes 10–30 minutes.
3. The collected data can be banked once and every report regenerated from it offline — so
   revisions cost seconds and require no further tenant access.
4. Deliverables are produced per assessment, plus a cross-assessment executive roll-up.

Access can be revoked the moment collection finishes; report generation needs none.

---

## 3. Azure RBAC — the control plane

### The recommended grant

| Role | Scope | Why |
|---|---|---|
| **Reader** | **Root management group** (Tenant Root Group) | One assignment, inherited by every management group, subscription and resource group beneath it |

This is the **entire Azure RBAC requirement**. Reader is a built-in role that confers no write,
no delete and no data-plane access.

Assigning at the root management group is preferred over per-subscription assignment for two
reasons: it is one auditable grant instead of many, and it means a subscription created mid-
engagement is covered without a second request.

> **Verified, not assumed:** Reader at the root management group is sufficient on its own. A
> separate *Management Group Reader* role is **not** required — the Reader role already carries
> the management-group read actions Scout uses.

### If root-level assignment is not permitted

Reader on each in-scope subscription works. The trade-off is explicit and should be recorded:
management-group hierarchy and any policy assigned above subscription level become invisible, so
governance findings will be reported as **not assessed** rather than silently passing.

### Optional additions

| Role | Scope | Needed only for |
|---|---|---|
| **Cost Management Reader** | Billing scope or subscription | Cost analysis (`-IncludeCosts`). Reader alone cannot query the cost APIs |

Nothing else. If a capability is unavailable, Scout reports it as not assessed and names the
missing permission — it does not fail the run and does not report a gap it could not measure.

---

## 4. Microsoft Entra ID — directory read access

Directory objects are read through **Microsoft Graph**. Two options:

### Option A — a delegated user (interactive runs)

Assign the built-in Entra role **Global Reader**. It is read-only across the directory and covers
every Graph call below in one grant.

### Option B — a service principal (automation, and the recommended route)

Grant **application permissions** on Microsoft Graph, each requiring admin consent. All are
`.Read`; none permits a write.

| Graph application permission | What Scout reads with it |
|---|---|
| `Directory.Read.All` | Baseline directory read |
| `User.Read.All` | User accounts and their state |
| `Group.Read.All` | Groups and membership |
| `Application.Read.All` | App registrations, service principals, credential expiry |
| `Policy.Read.All` | Conditional Access, authorisation and authentication method policies |
| `RoleManagement.Read.Directory` | Directory role assignments |
| `Organization.Read.All` | Tenant profile and licensing posture |
| `Domain.Read.All` | Verified domains and federation configuration |
| `AdministrativeUnit.Read.All` | Administrative units |
| `IdentityProvider.Read.All` | External identity providers |
| `IdentityRiskyUser.Read.All` | Identity Protection risk state (Entra ID P2) |
| `PrivilegedAccess.Read.AzureResources` | PIM eligibility and activation |

If a permission is withheld, the findings that depend on it are reported as **not assessed** and
name the permission — the run continues and the rest of the report is unaffected.

### Security data

Microsoft Defender for Cloud secure score, recommendations and alerts come through the **Azure
control plane** and are covered by the Reader assignment in section 3. **No separate Defender or
Sentinel role is required.** If Defender for Cloud is not enabled in scope, those findings are
reported as not assessed.

---

## 5. Azure DevOps — only if in scope

Azure DevOps is **off by default**. It is collected only when explicitly requested
(`-IncludeDevOps`), and Scout reads organisation and project configuration — never source code
and never build artefacts.

Authenticate with either the signed-in identity or a **Personal Access Token**. The PAT needs
**read-only** scopes:

| Scope | Reads |
|---|---|
| Project and Team (Read) | Organisations and projects |
| Build (Read) | Pipeline definitions |
| Code (Read) | Repository *metadata* — names, branch policies. **Not file contents** |
| Service Connections (Read) | Service endpoints and their authentication *type* |
| Agent Pools (Read) | Agent pool configuration |

A PAT should be issued for the engagement window and revoked afterwards. If DevOps access is
declined, the DevOps capability findings are reported as not assessed and nothing else changes.

---

## 6. Summary — the whole access request

| Plane | Grant | Scope |
|---|---|---|
| **Azure** | `Reader` | Root management group |
| **Azure** *(optional)* | `Cost Management Reader` | Billing scope — only for cost analysis |
| **Entra ID** | `Global Reader`, **or** the Graph application permissions in section 4 | Tenant |
| **Azure DevOps** *(optional)* | Read-only PAT | Organisation |

Every grant above is **read-only**. There is no write permission, no data-plane permission and no
standing access anywhere in this list.

---

## 7. Questions your security team will ask

**Does it exfiltrate anything?** No. Scout runs where you run it and writes its output to the
local path you specify. There is no telemetry, no phone-home and no cloud service component.

**Does it read our data?** No — control plane only. Not blob contents, database rows, Key Vault
secret values, mail or documents. Key Vault items are read as names and expiry dates.

**Can it change anything?** No. Every permission listed is read-only, and Scout has no write code
path.

**What if we grant less than the above?** The run still completes. Whatever could not be evaluated
is reported as **not assessed** and names the missing permission, so the gap is visible in the
report rather than hidden as a pass.

**How long do you need the access?** Only for the collection run. The collected data can be banked
once and all reporting done offline afterwards, so access can be revoked as soon as collection
finishes.
