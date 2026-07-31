---
description: Consolidated audit of Azure Scout — coverage, assessments, collectors, permissions — with the decision log.
---

# Azure Scout — Audit & Decisions

**Date:** 2026-07-31
**Scope:** ADO work items AB#6444, AB#6445, AB#6446, AB#6447 (Feature AB#6461)
**Method:** four parallel Opus audits over the full repo, cross-checked against Microsoft Learn,
plus findings that emerged in review afterwards.

## 1. Executive summary

Three questions were asked. Here are the answers.

| Question | Answer |
|---|---|
| Should Scout inventory more than 15 categories? | **Yes.** Azure has **18** official categories. Scout has 15. Missing: **General, DevOps, Migration**. |
| Should there be more assessments than LandingZone? | **Yes — and there is effectively only ONE today.** The registry's 22 entries are ~3 real assessments plus 19 filtered views of the same rule set. A separate path bug also hides 21 of the 22 menu entries. |
| Do the current assessments really cover CAF/WAF? | **No.** ~**10%** of CAF's design recommendations, ~**15%** of WAF's checklist items. |

**The four things that are wrong right now**, in priority order:

1. **Scout was not read-only.** It commanded every VM and Arc machine to run a patch scan on every
   run. **Fixed this session** — now reads Azure Update Manager instead.
2. **A one-line path bug** hides 21 of 22 assessment menu entries from the wizard.
3. **~40% of collected data is silently discarded** — Scout pulls it, then never writes it down.
4. **Nothing has ever been verified.** 0 of 174 collectors proven against real Azure; 12 provably
   return nothing, always.

---

## 2. Decision table

Legend: ✅ done · 🟡 agreed, not built · 🔲 not started · ❓ needs a decision

| # | Decision | Status | Decided by | Rationale | Where it stands |
|---|---|---|---|---|---|
| 1 | **Stop triggering patch assessments.** Read Azure Update Manager's Resource Graph tables instead of POSTing `assessPatches` per machine. | ✅ | Owner | *"To do a patch assessment is worthless cause that can take hours to run."* It was also an ARM **write** action, making a read-only tool mutate customer machines. | Implemented + 30/30 tests pass. Regression lock proven non-vacuous. **Uncommitted.** Not yet live-verified. |
| 2 | **Dump ALL raw collected data to a file**, regardless of whether a collector exists to display it. | 🟡 | Owner | *"Shouldn't all the data that is collected no matter what be dumped into a .json or some other file?"* Better than the audit's proposal (a summary of skipped types) — eliminates silent data loss entirely instead of reporting on it. | Agreed. Not built. |
| 3 | **Ship v3.0.9 without the diagram→PDF rasterisation fix.** | ✅ | Owner | Needs a new dependency (headless renderer) or a multi-week custom rasteriser. Not a point-release fix. | v3.0.9 shipped. **AB#6737 left open** with the scoping analysis recorded on it. |
| 4 | **Fix the wizard manifest path bug.** | ✅ **Decided — do it** | Owner | One line. Unlocks 21 menu entries. `src/Start-AZSCWizard.ps1:238` climbs three directory levels to find `manifests/assessments.psd1`; the file lives in `src/` so it needs one. It resolves outside the repo, `Test-Path` returns false, and it silently falls back to a hardcoded `@('LandingZone')`. | **Decision: change the three `Split-Path` calls to one.**<br><br>From:<br>`$manifestPath = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'manifests/assessments.psd1'`<br><br>To:<br>`$manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'manifests/assessments.psd1'`<br><br>Not yet applied. See §3.2. |
| 5 | **Drop Security Reader and Monitoring Reader** from the required role set. | 🔲 | — | Both are strict subsets of `Reader` for every call Scout makes. Monitoring Reader additionally grants ticket **creation** — a write Scout never uses. | Not started. |
| 6 | **Fix the readiness verdict** so a denied permission that empties a collector degrades the result. | 🔲 | — | Today only 4 of 9 Graph checks can turn the light red, so a green "READY" banner ships alongside empty security sheets. | Not started. |
| 7 | **Wizard `-DefaultSelected` after the path fix** — keep LandingZone-only pre-checked? | ❓ | **Needs owner** | Defensible (LandingZone is the roll-up containing everything), but right now it's an accident of the broken fallback, not a choice. | Open. |
| 8 | **De-duplicate the assessment registry.** `Governance`/`Policy` are behaviourally identical; `UpdateManager`/`Monitoring` are strict subsets of `Management`/`Monitor`. | ❓ | **Needs owner** | Four registry entries that add nothing a category filter doesn't already give. | Open — new finding, see §3.2. |
| 9 | **Add the three non-Microsoft categories?** (Backup & Recovery, Cost & Optimisation, Virtual Desktop) | ❓ | **Needs owner** | These are *opinion* — consulting-driven splits, not gaps against Microsoft's taxonomy. Distinct from DevOps/Migration/General, which are objective gaps. | Open. |
| 10 | **Build per-WAF-pillar / per-CAF-area / compliance assessments?** | ❓ | **Needs owner** | This is the *real* assessment gap and it remains unbuilt regardless of the wizard fix. See §3b for the full menu. | Open. |

---

## 3. Discovery findings

The five things that changed the picture. Two of these correct statements made earlier in review.

### 3.1 Azure has 18 categories — Scout has 15

**Correction:** it was stated earlier that Azure has no official category taxonomy. That was wrong.
The Azure portal's All Services page and Microsoft's resource-provider documentation both publish a
defined 18-category structure.

**Source:** <https://learn.microsoft.com/azure/role-based-access-control/resource-provider-operations>

| Microsoft category | Scout? | Microsoft category | Scout? |
|---|---|---|---|
| General | ❌ **missing** | Integration | ✅ |
| Compute | ✅ | Identity | ✅ |
| Networking | ✅ | Security | ✅ |
| Storage | ✅ | **DevOps** | ❌ **missing** |
| Web and Mobile | ✅ (as "Web") | **Migration** | ❌ **missing** |
| Containers | ✅ | Monitor | ✅ |
| Databases | ✅ | Management and governance | ✅ (as "Management") |
| Analytics | ✅ | Hybrid + multicloud | ✅ (as "Hybrid") |
| AI + machine learning | ✅ (as "AI") | Internet of Things | ✅ (as "IoT") |

Scout's taxonomy is clearly modelled on Microsoft's — it just stopped three short.

**DevOps is nearly free:** Scout already has **5 DevOps collectors**, currently misfiled under
`Management/`. Creating the category is largely a directory move.
**Migration has zero coverage** — Azure Migrate, Data Box, Database Migration Service, Azure Stack
Edge are all absent.

Separately, and distinct from categories: Scout collects **110 real ARM resource types across 52
resource providers**. Measured against Microsoft's own provider directory (152 providers across the
18 categories), that is **49 of 152 = 32% coverage**. Full per-category breakdown in §4.

> Two coverage numbers appear in this document and they are not in conflict — they use different
> denominators. **32%** is against Microsoft's published 152-provider directory (the strict,
> comparable figure). **40%** appears in the AB#6446 report against a broader ~130-provider working
> estimate. The precise figure is 32%; three providers Scout collects
> (`microsoft.azurearcdata`, `microsoft.classiccompute`, `microsoft.edgeconfig`) don't appear in
> Microsoft's directory at all, which is why the collected count reads 49 there and 52 elsewhere.

### 3.2 The "22 assessments" are really about three

**Correction:** it was stated earlier that Scout has 22 assessments with a bug hiding 21. That
overstated things. Reading `manifests/assessments.psd1` in full:

| Kind | Count | What they are |
|---|---|---|
| Real cross-cutting | 2 | `LandingZone` (all `caf.*` + `waf.*` rules), `Estate` (inventory, no scoring) |
| **Per-category slices** | **15** | Management, Monitor, Networking, Identity, Security, Compute, Storage, Databases, Containers, Web, Analytics, AI, Integration, Hybrid, IoT — **named identically to Scout's 15 categories**, each just setting `Category='<itself>'` |
| Sub-bundles | 4 | Governance, Policy, UpdateManager, Monitoring |
| Targeted pull | 1 | Cost |

**Verified duplication** (`manifests/assessments.psd1:141-160`):

- **`Governance` and `Policy` are behaviourally identical** — same `Category`, `Collect`, `Ingest`,
  and `Rules=@('caf.governance')`. Only the description and tags differ.
- **`UpdateManager`** (`caf.management`) is a strict subset of **`Management`**
  (`caf.governance` + `caf.management` + `caf.billing`).
- **`Monitoring`** (`waf.operational`) is a strict subset of **`Monitor`**
  (`caf.management` + `waf.operational`).

**So: one real assessment, an inventory mode, a cost pull, and 19 filtered views of the same rules.**

The original instinct — *"right now we just have LandingZones"* — was closer to the truth than the
correction was. Fixing the wizard bug yields **21 menu entries, not 21 new assessments**.

**The wizard bug itself is still real.** `src/Start-AZSCWizard.ps1:238` climbs **three** directory
levels to find the assessment manifest. The engine rewrite moved the file to `src/`, so it needs
**one**. It resolves to a path that doesn't exist, `Test-Path` returns false, and it silently falls
back to a hardcoded `@('LandingZone')`. No error, no warning, not even verbose output. It shipped
because there is **no wizard test at all**. `Invoke-AzureScout -Assessment <name>` is unaffected.

### 3.3 Scout collects nearly everything, then displays about 40%

This is a **display** gap, not a collection gap — which makes it far cheaper to fix than it sounds.

The query at `src/collect/Get-ScoutRawInventory.ps1:432` is:

```kql
resources | where type !in ('microsoft.logic/workflows','microsoft.portal/dashboards',
                           'microsoft.resources/templatespecs/versions','microsoft.resources/templatespecs')
```

That says **"everything EXCEPT these four"** — not a list of wanted types. Every resource of every
type comes back.

Then each of the 174 collectors selects the rows matching its own declared types, formats them, and
writes a worksheet. **Rows no collector asks for are never selected, and vanish when the process
exits.**

**Worked example.** A tenant contains an Azure Data Factory:
1. The query pulls it back — it's not excluded ✅
2. It sits in memory with everything else ✅
3. Scout looks for a collector wanting `microsoft.datafactory/factories`
4. **There isn't one.** Nobody wrote it.
5. The row is never selected. Program ends. Gone.

No error, no warning, no "1 resource skipped". **The report cannot distinguish "you don't have one"
from "Scout can't display it."**

> Think of a shop doing a full stock count. The counter walks the whole warehouse and writes down
> every single item. Then, typing up the report, he only types the items that have a pre-printed
> form — and burns his notes. The count was complete. The report isn't. And nothing tells you the
> difference.

**One genuine collection gap:** Logic Apps (`microsoft.logic/workflows`) really *is* excluded — it's
the first entry in that list. That one needs the query edited, not just a display template.

### 3.4 Scout was not read-only — now fixed

Scout POSTed `assessPatches` **once per VM and once per Arc machine, on every run**:

- `src/collect/Get-ScoutOperationalCollectorEnrichment.ps1:170` (VMs)
- `:178` (Arc machines)
- Enabled unconditionally at `src/collect/Start-ScoutGraphExtraction.ps1:78` — no operator switch

`assessPatches` is a **command**, not a query. It tells the machine to scan itself for missing
patches now. Azure classifies it as an `/action`, which is why the `Reader` role doesn't grant it.

**Proof it executed against real machines** — from the 2026-07-30 run log:

```
ArcServerOperationalData.PatchAssessment failed for '.../vm-test-vlan711': ARM returned status 409
```

**409 Conflict** = "an assessment is already running on this machine." Only obtainable if Scout
started one.

**Origin:** commit `48f822b`, 2026-02-24 — original Scout work, *not* inherited from the ARI fork.
It fed exactly two spreadsheet columns (`Pending Critical Patches`, `Pending Other Patches`) and was
carried through the v3 rebuild without anyone re-examining the verb. The wrong API was chosen for
the goal: `POST assessPatches` (*trigger a scan*) instead of reading the results Update Manager
already stores.

**The fix (implemented this session):** Azure Update Manager already writes its results into two
Resource Graph tables — `patchassessmentresources` (pending updates, 7-day retention) and
`patchinstallationresources` (installation history, 30-day retention) — both covering Azure VMs
*and* Arc machines. Scout now reads those.

Result: same report columns, **more** detail available than before (KB IDs, classifications, reboot
flags), **zero machines touched**, one tenant-wide query instead of one POST per machine, and plain
`Reader` becomes sufficient. Machines Update Manager hasn't assessed within 7 days now report
`NotAssessed` rather than a misleading zero.

### 3.5 Nothing has ever been verified

| Evidence class | Count | What it proves |
|---|---|---|
| Passes a golden test generated from its own definition | 174 | The interpreter is deterministic. Nothing about Azure. |
| Declared type observed in a real anonymised capture | 38 | The type string is real. No collector is ever run against that capture. |
| **Proven to emit correct rows from real Azure** | **0** | — |
| **Proven to emit ZERO rows, every run, every tenant** | **12** | Traced to specific defects. |
| Cannot emit on a default run (opt-in switches) | 20 | `entra/*` needs `-Scope All`; `devops/*` needs `-IncludeDevOps`. |
| Target a retired service | 4 | Dead weight. |

**At minimum 32 of 174 (18%) produced an empty worksheet on the 2026-07-30 run and could not have
done otherwise.** The other 142 are simply unknown.

**Why the test suite can't catch this:** `scripts/New-ScoutCollectorFixture.ps1` synthesises test
fixtures **from each collector definition's own AST**. `Hybrid/ArcSites` declares three resource
types that **do not exist in Azure** — the generator fabricates matching rows, the collector matches
them, the golden test passes forever. It would still pass if all 152 type strings were replaced with
gibberish.

**Among the 12 confirmed broken:** four Management collectors (CustomRoleDefinitions,
ManagementGroups, PolicyDefinitions, PolicySetDefinitions) gate on `-IncludeTenantWideResources`, **a
switch with no production caller anywhere in the repo**. This finally settles the long-running
ManagementGroups mystery — the permissions issue was the *second* problem; the first is that the
producer is never invoked at all.

**Evidence is destroyed by design:** `src/Invoke-AzureScout.ps1:1035` runs `Clear-AZSCCacheFolder`
unconditionally at the end of every run, deleting the only per-collector row-count evidence Scout
produces.

---

## 3b. Catalogue of possible CAF/WAF assessments

### Table 1 — WAF pillars as candidate assessments

Official checklist item counts verified 2026-07-30 by fetching each pillar's design-review checklist page directly. All five totals match the prior audit exactly (59 items). Scout rule counts are `- id:` occurrences in each file under `src/assess/rules/`.

The "assessable" figure is the subset of checklist items that can be evaluated from Azure control-plane telemetry at all. The rest are process, cultural, or design-intent items (define targets, run FMA, train staff, formalise practices) that no scanner can score without human input. Coverage is given against that subset, because coverage against the full 59 understates Scout by treating unscorable items as gaps.

| Pillar | Official checklist items | Machine-assessable subset | Scout rule file | Scout rule count | Est. coverage | Verdict |
|---|---|---|---|---|---|---|
| Reliability | 10 (`RE:01`–`RE:10`) | ~4 (`RE:05` redundancy, `RE:06` scaling, `RE:07` self-healing, `RE:10` health monitoring) | `waf.reliability.yaml` | 3 | ~75% of assessable / 30% of full | **Promote to a real assessment.** Thinnest file in the repo at 3 rules and the only pillar below 6. Add `RE:10` monitoring coverage and depth on `RE:05`. |
| Security | 12 (`SE:01`–`SE:12`) | ~7 (`SE:04` segmentation, `SE:05` IAM, `SE:06` networking, `SE:07` encryption, `SE:08` hardening, `SE:09` secrets, `SE:10` monitoring) | `waf.security.yaml` | 7 | ~100% of assessable / 58% of full | **Promote.** Best-aligned pillar. Depth per rule is the gap, not breadth. |
| Cost Optimization | 14 (`CO:01`–`CO:14`) | ~6 (`CO:03` cost data, `CO:05` rates/reservations, `CO:07` component costs, `CO:08` environment costs, `CO:10` data costs, `CO:12` scaling costs) | `waf.cost.yaml` | 6 | ~100% of assessable / 43% of full | **Promote.** Already surfaced separately as the registry's `Cost` view — that view should become this pillar assessment. |
| Operational Excellence | 11 (`OE:01`–`OE:11`) | ~4 (`OE:05` IaC, `OE:07` monitoring stack, `OE:10` automation, `OE:11` safe deployment) | `waf.operational.yaml` | 6 | ~100% of assessable / 55% of full | **Promote.** Largest pillar-to-telemetry gap: 7 of 11 items are unscorable process items. Report must say so rather than score them as failures. |
| Performance Efficiency | 12 (`PE:01`–`PE:12`) | ~5 (`PE:03` service/tier selection, `PE:04` measurement, `PE:05` scaling/partitioning, `PE:07` code+infrastructure, `PE:08` data) | `waf.performance.yaml` | 6 | ~100% of assessable / 50% of full | **Promote.** |
| **Total** | **59** | **~26** | 5 files | **28** | — | Five pillar assessments are viable today. |

Sources: [Reliability](https://learn.microsoft.com/en-us/azure/well-architected/reliability/checklist) · [Security](https://learn.microsoft.com/en-us/azure/well-architected/security/checklist) · [Cost Optimization](https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/checklist) · [Operational Excellence](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/checklist) · [Performance Efficiency](https://learn.microsoft.com/en-us/azure/well-architected/performance-efficiency/checklist)

The machine-assessable subsets are this audit's own judgement, applied consistently across pillars. They are not a Microsoft-published figure and are marked `unverified` as a citable number.

#### The `waf.storage.yaml` anomaly

`src/assess/rules/waf.storage.yaml` (5 rules) carries a `waf.` prefix but **storage is not a WAF pillar**. The Well-Architected Framework has exactly five pillars, confirmed on every checklist page above and on [What is the Well-Architected Framework?](https://learn.microsoft.com/en-us/azure/well-architected/what-is-well-architected-framework). Storage appears in WAF only as a *service guide*, which is a different artefact — service guides are per-service configuration advice that feeds the pillars, not a scoring axis alongside them.

The file also collides conceptually with `caf.storage.yaml` (6 rules), giving Scout two storage rule files under two different framework prefixes.

**What should happen to it:** redistribute its 5 rules into the pillar files they actually belong to — durability/replication rules to `waf.reliability.yaml`, encryption and public-access rules to `waf.security.yaml`, tiering/lifecycle rules to `waf.cost.yaml` — then delete the file. Keeping it means Scout reports a sixth WAF pillar that does not exist, which is the single most visible correctness defect in the rule set. If per-service grouping is wanted, model it explicitly as a WAF *service guide* axis with its own prefix (`svc.storage.yaml`), never as `waf.*`.

---

### Table 2 — CAF landing zone design areas as candidate assessments

Eight design areas confirmed against [Azure landing zone design areas and conceptual architecture](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-areas) — four "environment" design areas (billing/tenant, IAM, resource organization, network) and four "compliance" design areas (security, management, governance, platform automation). The count of 8 matches the prior audit.

Recommendation counts were verified by fetching **43 Microsoft Learn pages** across all eight areas, counting top-level bullets under `## Design recommendations` (and area-specific equivalents such as "Management group recommendations"). Totals differ materially from the prior audit — see the discrepancy note below the table.

| Design area | Official recommendations (verified) | Prior audit said | Scout rule file | Scout rule count | Est. coverage | Verdict |
|---|---|---|---|---|---|---|
| Azure billing and Microsoft Entra tenant | **42** (5 pages) | 42 | `caf.billing.yaml` | 7 | **~0%** — see misnaming note | **Highest-priority gap.** The one design area with a rule file that does not assess it at all. |
| Identity and access management | **65** (4 pages) | 69 | `caf.identity.yaml` | 7 | ~11% | Promote, but 7 rules against 65 recommendations is a token sample. IAM deserves the deepest rule set of any area. |
| Resource organization | **35** (3 pages) | 35 | `caf.resourceorg.yaml` | 6 | ~17% | Promote. Highly telemetry-friendly (management groups, subscriptions, tags) — cheapest area to raise coverage. |
| Network topology and connectivity | **123** formal (+ ~32 in rewritten numbered format ≈ **155**) across 14 pages | 141 | `caf.network.yaml` | 7 | ~5% | Promote. Largest design area by a wide margin and Scout's weakest ratio. Warrants splitting into sub-assessments (topology, IP addressing, DNS, ingress/egress, segmentation). |
| Security | **45** (3 pages) | ~100 | `caf.security.yaml` | 7 | ~16% | Promote. Prior audit's ~100 is not supported — see discrepancy note. |
| Management | **15** (5 pages) | 46 | `caf.management.yaml` | 6 | ~40% | Promote. Best-covered CAF area, and the prior audit badly overstated the target. |
| Governance | **10** (1 page, self-contained) | 42 | `caf.governance.yaml` | 7 | ~70% | Promote. Effectively near-complete; the prior audit's 42 appears to have counted design *considerations* (~40 bullets on that page) rather than recommendations. |
| Platform automation and DevOps | **30** formal (10 pages) | ~80 | `caf.platformauto.yaml` | 6 | ~20% | Promote with caution — most content is CI/CD process that Azure telemetry cannot observe. Realistic ceiling is low. |
| **Total** | **~365 formal** | ~394 | 8 files | **53** | ~15% | Eight design-area assessments are viable; three are severely under-ruled. |

Base URL for all design-area pages: `https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/`

**Discrepancy against the prior audit — use the verified figures.** The verified total is **~365**, not ~394. Three areas differ enough to matter:
- **Security: 45 verified, not ~100.** The prior figure likely double-counted the four `azure-best-practices` network-security pages that the security design area links to but which belong to the network design area.
- **Management: 15 verified, not 46.** Two of the five sub-pages have no recommendations section at all.
- **Governance: 10 verified, not 42.** That page's *considerations* section runs to ~40 bullets; the *recommendations* section is 10. Almost certainly a considerations/recommendations mix-up.
- **Network: 123 formal, not 141** — but with ~32 further recommendations now written as numbered task steps rather than bullets, the true figure is ~155, i.e. the prior audit understated this one.

**Caveat on all counts — Microsoft is mid-rewrite.** The `## Design considerations` / `## Design recommendations` structure is no longer universal. `virtual-wan-network-topology`, `connectivity-to-other-providers`, and `considerations/devops-teams-topologies` now have **no** design-recommendations heading; their ~41 combined recommendations are numbered task sections. Any count is therefore a snapshot, and a rule set pinned to bullet counts will drift. Four pages were not read (`subscription-vending`, `subscription-vending-product-lines`, `connectivity-to-other-providers-oci`, and the multi-tenant set), so ~365 is a floor, not a ceiling.

#### `caf.billing.yaml` is misnamed

`caf.billing.yaml` holds **cost-optimization rules** — the same subject matter as `waf.cost.yaml`, not the CAF "Azure billing and Microsoft Entra tenant" design area. That design area is about commercial and tenant *setup*, and its 42 recommendations cover things Scout does not touch:

- EA vs MCA vs CSP enrollment structure and which agreement the estate is on
- billing account → billing profile → invoice section hierarchy, and mapping it to organizational structure
- department/enrollment-account hierarchy and per-invoice-section budgets with alerts
- **subscription vending** as an automated self-service function
- **MFA required on every identity holding subscription-creation permissions** on a billing account, profile, or invoice section
- notification-contact email configured on the billing account, and periodic audit of billing RBAC role assignments
- Microsoft Entra tenant creation and whether one tenant or several is correct
- break-glass / emergency-access accounts excluded from Conditional Access

Verified against [Plan for the Microsoft customer agreement service](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/azure-billing-microsoft-customer-agreement), which states the MFA-on-subscription-creators and billing-RBAC-audit recommendations explicitly.

Consequence: **the billing/tenant design area has ~0% real coverage**, and Scout has two files scoring cost optimization while one of them claims to score tenant setup. Rename the existing file to `caf.cost.yaml` (or fold it into `waf.cost.yaml`, which it duplicates), and write a genuine `caf.billing.yaml` against the list above. Break-glass accounts, MFA on subscription creators, and billing RBAC assignments are all reachable from data Scout already collects, so this is a cheap, high-value gap to close.

---

### Table 3 — CAF methodologies as a second assessment axis

The Cloud Adoption Framework is organised into **seven core methodologies**, confirmed on [What is the Microsoft Cloud Adoption Framework?](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/overview): four sequential foundational methodologies (Strategy, Plan, Ready, Adopt) and three parallel operational ones (Govern, Secure, Manage). **Secure is a full methodology in its own right** — a change from older CAF material where security was folded into Govern.

Scout models **none** of the seven. Its 17 `caf.*.yaml` files map to the *design areas* of a single methodology (Ready), plus nine service-category files that sit outside the CAF structure entirely (`ai`, `analytics`, `containers`, `databases`, `hybrid`, `integration`, `iot`, `storage`, `web` — 62 of the 111 CAF rules). This is the more important structural finding of Table 2 and Table 3 combined: **Scout's "CAF" coverage is really "one methodology's design areas, plus a service taxonomy that CAF does not have."**

| Methodology | What it covers | Assessable from Azure telemetry? | Verdict |
|---|---|---|---|
| **1. Strategy** | Map business drivers to cloud outcomes; motivations, business justification, first adoption project. | **No.** Purely organisational. There is no Azure artefact that encodes a motivation statement. | **Do not build.** Any score would be fabricated. Offer as a questionnaire at most. |
| **2. Plan** | Operating model, cloud skills readiness, migration/adoption plan, cloud cost estimation. | **Barely.** Digital-estate inventory and cost forecasting are observable; skills plans and operating-model choice are not. | **Do not build as a scored assessment.** The observable part is already Scout's `Estate` inventory view. |
| **3. Ready** | Azure purchasing, tenant setup, platform landing zone, application landing zones — i.e. the 8 design areas. | **Yes, extensively.** This is the whole of Table 2. | **Already Scout's only real assessment.** Should be named honestly as "CAF Ready / Landing Zone", not "CAF". |
| **4. Adopt** | Migrate, modernise, or build cloud-native workloads. | **Partially.** Migration tooling state and workload modernity (PaaS vs IaaS ratio, container adoption, deprecated SKUs) are observable; adoption sequencing is not. | **Build second.** A "modernisation posture" assessment scoring IaaS-vs-PaaS mix, legacy SKUs, and OS/runtime end-of-support is genuinely useful and entirely telemetry-driven. |
| **5. Govern** | Assess cloud risks and mitigate them with Azure tooling, across seven risk categories (below). | **Yes, substantially** — via Azure Policy compliance state, which Scout collects and does not score (Table 4). | **Build first after Ready.** The cheapest high-value new assessment Scout can add. |
| **6. Secure** | Protect workloads: security posture modernisation, Zero Trust access controls, incident readiness. | **Yes** — Defender for Cloud secure score, MCSB compliance, identity posture. | **Build.** Overlaps WAF Security but scores the *estate*, not a workload — a genuinely different question. |
| **7. Manage** | Administer and optimise workloads: management baseline, monitoring, business continuity, operational compliance. | **Yes.** Backup/DR configuration, Log Analytics coverage, alert rules, Update Manager and agent deployment are all observable. | **Build.** Maps closely to the existing `caf.management.yaml`, which could be promoted and expanded to fill it. |

#### Current Govern taxonomy — verified

The prior audit's 7 categories are **confirmed correct**, though the abbreviations RC/SC/CM/OP/DG/RM/AI are Scout's shorthand, not Microsoft's. Microsoft names them, verbatim from [Assess cloud risks](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/govern/assess-cloud-risks):

| Category | Microsoft's wording | Scout shorthand |
|---|---|---|
| Regulatory compliance | "Identify regulatory compliance risks" | RC |
| Security | "Identify security risks" | SC |
| Cost | "Identify cost risks" | CM |
| Operations | "Identify operations risks" | OP |
| Data | "Identify data risks" | DG |
| Resource management | "Identify resource management risks" | RM |
| AI | "Identify AI risks" | AI |

The same seven appear as the `Category` field of the CAF risk register and in the Govern overview's domain list. Independently corroborated by the [FinOps toolkit Governance report](https://learn.microsoft.com/cloud-computing/finops/toolkit/power-bi/governance), which lists "regulatory compliance, security, operations, cost, data, resource management, and artificial intelligence (AI)".

Govern is also now a **five-step process** — build a governance team → assess risks → document policies → enforce policies → monitor compliance — with steps 2–5 running as a continuous cycle. An assessment could score steps 4 and 5 (enforcement and monitoring) from telemetry; steps 1–3 are organisational.

#### The five old governance disciplines are retired — verified

The legacy CAF governance disciplines (**Cost Management, Security Baseline, Identity Baseline, Resource Consistency, Deployment Acceleration**) no longer exist as a taxonomy. Two independent confirmations:

1. Fetching `https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/govern/governance-disciplines` **redirects** to [Build a cloud governance team](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/govern/build-cloud-governance-team) — the discipline hub page is gone, not merely moved.
2. Targeted search of Microsoft Learn for the five discipline names returns **no** current CAF Govern discipline pages; the only surviving hits are scenario-specific pages (SAP, Azure Arc) that use "governance disciplines" as a generic phrase.

The two discipline names that survive do so in a different sense and must not be treated as the old disciplines: **Deployment Acceleration** and **Cost Management** are now recommendation headings *inside* the Governance design area page (8 and 2 recommendations respectively — the whole of that page's 10). If Scout's rule metadata still tags rules with discipline names, those tags are stale.

---

### Table 4 — Compliance and benchmark assessments (none exist in Scout today)

**The economics here are unlike anything else in this catalogue.** Azure ships regulatory-compliance initiatives as built-in policy set definitions, and Azure Policy already evaluates every in-scope resource against them continuously. An assessment built on this reads a compliance result Azure has already computed — it does not re-implement hundreds of controls.

**Scout's position:** `Get-ScoutApiResources.ps1:151` calls `Microsoft.PolicyInsights/policyStates/latest/summarize`, and `Get-ScoutSubscriptionSecurityPolicySweep.ps1` and `Get-ScoutOperationalCollectorEnrichment.ps1:249` (`policyStates/latest/queryResults`) collect further policy state. Policy set definitions and definitions are collected too. **No rule scores any of it.** The four rules that mention policy (`caf.governance.yaml`, `caf.platformauto.yaml`) query `$.governance.policyAssignments` for assignment *existence*, `enforcementMode`, and presence of parameters — never compliance state.

**A naming defect worth fixing while you are here:** in `Get-ScoutApiResources.ps1:150-151` the field named `PolicyAssignments` is populated from the `policyStates/latest/summarize` endpoint, which returns a *compliance summary*, not assignments. Meanwhile `caf.hybrid.yaml:55` documents that `governance.policyAssignments` is populated by the AzGovViz ingest step. Two different shapes, one name.

The `Controls` column below is Microsoft's published **policy count** for each initiative — the number of policy definitions it contains, not the number of framework controls, which is generally lower (many controls need several policies). All names and counts are from [Azure Policy built-in initiative definitions](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-initiatives), verified 2026-07-30.

| Framework | Azure Policy built-in initiative name (exact) | Controls (= policies) | Buildable from Scout's data? | Priority |
|---|---|---|---|---|
| **Microsoft Cloud Security Benchmark** | `Microsoft cloud security benchmark` | 223 | **Yes — free.** Defender for Cloud's *default* initiative, so it is assigned in essentially every subscription. Compliance state is already in Scout's collected data. | **1 — build first.** Highest coverage, zero assignment prerequisite. |
| MCSB v2 (preview) | `[Preview]: Microsoft cloud security benchmark v2` | 414 | Yes, where assigned. Preview — do not make it the default. | 1b — support alongside v1. |
| **CIS Azure Foundations** | `CIS Azure Foundations v3.0.0` (current) | 53 | **Yes, if assigned.** Also available: `CIS Microsoft Azure Foundations Benchmark v2.0.0` (108), `v1.4.0` (167), `v1.3.0` (168), `v1.1.0` (152), `CIS Azure Foundations v2.1.0` (31) | **2.** Most-requested benchmark in customer conversations. Ship v3.0.0 and v2.0.0. |
| CIS Controls (non-Azure-specific) | `CIS Controls v8.1` | 167 | Yes, if assigned. | 4 |
| **NIST SP 800-53 Rev 5** | `NIST SP 800-53 Rev. 5` | 696 | **Yes, if assigned.** Also `NIST SP 800-53 R5.1.1` (221), the newer revision-5.1.1 set. | **3.** Largest initiative Azure ships; only meaningful via policy state — hand-writing 696 rules is not viable. |
| **NIST CSF** | `NIST CSF v2.0` | 103 | Yes, if assigned. | 3 |
| **ISO/IEC 27001** | `ISO/IEC 27001 2022` (current) | 58 | **Yes, if assigned.** Legacy `ISO 27001:2013` (448) still shipped. Companions: `ISO/IEC 27002 2022` (145), `ISO/IEC 27017 2015` (92, cloud-specific) | **2.** Ship the 2022 set; offer 2013 for customers mid-recertification. |
| **PCI-DSS v4** | `PCI DSS v4.0.1` (current) | 202 | **Yes, if assigned.** Also `PCI DSS v4` (269) and legacy `PCI v3.2.1:2018` (30) | 3 |
| **SOC 2** | `SOC 2 Type 2` | 307 | **Yes, if assigned.** Also `SOC 2023` (221) | 3 |
| **HIPAA / HITRUST** | `HITRUST/HIPAA` | 589 | **Yes, if assigned.** Also `HITRUST CSF v11.3` (216) | 3 |
| **FedRAMP Moderate** | `FedRAMP Moderate` | 641 | Yes, if assigned. | 4 (US public sector only) |
| **FedRAMP High** | `FedRAMP High` | 711 | Yes, if assigned. Largest US-federal set. | 4 (US public sector only) |
| **UK OFFICIAL** | `UK OFFICIAL and UK NHS` | 45 | Yes, if assigned. Single initiative covers both. | 4 |
| **Australian ISM** | `Australian Government ISM PROTECTED` | 38 | Yes, if assigned. Also `APRA CPS 234 2019` (18) for AU financial services. | 4 |
| CMMC | `CMMC 2.0 Level 2` (217); `Cybersecurity Maturity Model Certification (CMMC) Level 2 v1.9.0` (200); `CMMC Level 3` (142) | 142–217 | Yes, if assigned. | 5 |
| NIST SP 800-171 | `NIST 800-171 R3` (206); `NIST SP 800-171 Rev. 2` (435) | 206 / 435 | Yes, if assigned. | 5 |
| Canada Federal PBMM | `Canada Federal PBMM 3-1-2020` (189); legacy `Canada Federal PBMM` (41) | 189 | Yes, if assigned. | 5 |
| New Zealand ISM | `New Zealand ISM` (208); `NZISM v3.7` (209) | 208 | Yes, if assigned. | 5 |
| Spain ENS | `Spain ENS` | 821 | Yes, if assigned. Largest single initiative Azure ships. | 5 |
| Netherlands BIO | `NL BIO Cloud Theme V2` (278); `NL BIO Cloud Theme` (228) | 278 | Yes, if assigned. | 5 |
| SWIFT CSP-CSCF | `SWIFT Customer Security Controls Framework 2024` (193); `SWIFT CSP-CSCF v2022` (323) | 193 | Yes, if assigned. | 5 |
| South Korea ISMS-P | `K ISMS P 2023` | 364 | Yes, if assigned. | 5 |
| RMIT Malaysia | `RMIT Malaysia` | 183 | Yes, if assigned. | 5 |
| NIST AI RMF | `NIST AI RMF v1.0` | **1** | Technically yes, but a 1-policy initiative scores almost nothing. | Do not ship as an assessment — it would mislead. |
| CIS Kubernetes | `[Preview]: Kubernetes cluster should follow the security control recommendations of Center for Internet Security (CIS) Kubernetes benchmark` | 7 | Yes, AKS only. | 5 |

**Which frameworks have a built-in initiative:** all of the above. **Which would need hand-written rules:** none of the frameworks named in the brief. Every one — MCSB, CIS, NIST 800-53 Rev 5, NIST CSF, ISO 27001, PCI-DSS v4, SOC 2, HIPAA/HITRUST, FedRAMP Moderate and High, UK OFFICIAL, Australian ISM — ships as a built-in regulatory-compliance initiative. Hand-writing rules for any of them would duplicate work Azure already does and would drift from Microsoft's control mappings on every framework revision.

**The one real constraint, and it is a hard one:** apart from MCSB, an initiative returns compliance data **only where it has been assigned**. An unassigned initiative yields nothing — not a zero score, but no data at all. Scout must distinguish "assigned and non-compliant" from "never assessed" and report the second as a coverage gap, never as a pass or a fail. This distinction is the entire difference between a trustworthy compliance report and a dangerous one. Scout already collects `policySetDefinitions` per subscription, so detecting which initiatives are assigned is straightforward.

Suggested build order: read the summarised compliance state Scout already collects → render MCSB as a scored assessment → detect which other regulatory initiatives are assigned → expose each assigned one as its own assessment → for unassigned frameworks, emit a recommendation to assign the initiative rather than a score.

#### Microsoft's own review tooling as candidate structures

**Azure Well-Architected Review** — [Complete an Azure Well-Architected Review assessment](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations) states the core review "consists of approximately 60 questions based on the key recommendations from the Well-Architected Framework pillars", which corroborates the 59-item checklist total in Table 1. Take the "Core Well-Architected Review" when prompted; the platform also hosts narrower specialised reviews (AI workload, Analytics, Azure AI Search, Azure Virtual Desktop, Data Services, SaaS workload, Mission Critical). Azure Advisor now surfaces WAF assessments directly — see [Use Azure WAF assessments](https://learn.microsoft.com/en-us/azure/advisor/advisor-assessments) — which is the closest existing product to what Scout does and worth studying as both a structural model and a competitive reference.

**Azure Landing Zone Review** — the assessment exists on the Microsoft Assessments platform, but its question count and per-area weighting are **not published in Microsoft Learn documentation**. The prior audit's figures — 34 questions weighted Network 11, Identity 7, Platform automation 4, Billing 3, Resource org 3, Governance 3, Management 2, Security 2 — **could not be verified** from Learn and are marked `unverified`. Do not cite them as fact. Two observations that neither confirm nor refute them: the weighting is directionally consistent with the verified recommendation counts in Table 2 (network is by far the largest area at ~155, identity second at 65), but it is sharply inconsistent for Management (2 questions against 15 recommendations) and Security (2 questions against 45). Verifying this requires running the assessment on the Microsoft Assessments platform, which Learn's documentation tooling cannot reach.

Both review tools are worth adopting as *structure* regardless of Scout's rule content: they give customers a vocabulary they already recognise, and aligning Scout's output sections to them makes Scout's findings directly comparable to a Microsoft-run review.

---

### Framework currency warnings

Places where Microsoft's guidance has moved and Scout would now score against stale guidance. Each verified 2026-07-30.

| # | Warning | Status | Impact on Scout |
|---|---|---|---|
| 1 | **The five CAF governance disciplines are retired.** Cost Management, Security Baseline, Identity Baseline, Resource Consistency, and Deployment Acceleration no longer exist as a taxonomy. The `govern/governance-disciplines` URL redirects to [Build a cloud governance team](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/govern/build-cloud-governance-team). Govern is now a 5-step process across 7 risk categories. **Deployment Acceleration and Cost Management survive only as recommendation headings inside the Governance *design area*** — not as disciplines. | **Confirmed retired** | Any rule metadata, doc page, or report section using discipline names is stale. Re-tag to the 7 risk categories. |
| 2 | **Two new default management groups: `Security` and `Local`.** Both are now in the default ALZ hierarchy, not tailoring options. `Security` sits under `Platform` and holds SIEM/SOC tooling (Sentinel, syslog collectors). `Local` sits under `Landing zones` alongside `Corp` and `Online`, for Azure Local clusters and their workloads, which have different Azure Policy requirements. Microsoft now states "the default `Corp`, `Online`, and `Local` management groups provide an ideal starting point". Source: [Management groups](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups). | **Confirmed — both are default** | Any rule validating management-group hierarchy against a `Platform`/`Landing zones`/`Sandbox`/`Decommissioned` shape will now flag conforming estates as non-conforming. Note the tailoring page still describes `Security` as an example of tailoring while the design-area page treats it as default — Microsoft's own docs are inconsistent; trust the design-area page. |
| 3 | **Sovereignty has moved out of CAF into its own docset.** Sovereign Landing Zone content now lives under `learn.microsoft.com/azure/azure-sovereign-clouds/` (and `learn.microsoft.com/industry/sovereignty/`), not under CAF. SLZ is now positioned as an *architectural variant* layered onto an existing landing zone — "You don't need to replace your Azure landing zone implementation" — with L1–L3 policy tiers plus a Secure Landing Zone initiative. Some older Cloud for Sovereignty pages are explicitly banner-marked **archived and not being updated**. Sources: [Sovereign Landing Zone (SLZ)](https://learn.microsoft.com/azure/azure-sovereign-clouds/public/overview-sovereign-landing-zone) · [implementation options](https://learn.microsoft.com/azure/azure-sovereign-clouds/public/implementation-options) | **Confirmed moved** | Sovereignty is now a separate assessment axis, not a CAF design area. Any Scout link into CAF for sovereignty guidance is dead or archived. |
| 4 | **CAF explicitly states AI does NOT need its own landing zone.** From the [Azure landing zone FAQ](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/enterprise-scale/faq): *"Do I need a dedicated or separate AI landing zone? No, you do not need a separate AI landing zone."* AI workloads deploy into ordinary application landing zones. | **Confirmed** | Scout's `caf.ai.yaml` (5 rules) must not score for a separate AI landing zone or AI-specific platform subscriptions. The correct AI checks are management-group separation of internet-facing vs internal AI workloads, AI-specific Azure Policy on those groups, and AI resources in *workload* subscriptions — per [AI Ready](https://learn.microsoft.com/azure/cloud-adoption-framework/ai/ready). |
| 5 | **NEW — CAF now has seven methodologies, and `Secure` is one of them.** Secure is a peer of Govern and Manage, not a sub-topic of Govern. Foundational (Strategy, Plan, Ready, Adopt) are sequential; operational (Govern, Secure, Manage) run in parallel. Source: [CAF overview](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/overview). | **Newly flagged** | Scout models zero methodologies and its `caf.*` files cover only Ready's design areas. Naming them "CAF" overstates scope — see Table 3. |
| 6 | **NEW — the design area is "Azure billing and Microsoft Entra tenant", not "Active Directory tenant".** The design-areas index page still renders the legacy "Azure billing and Active Directory tenant" label in its table while the underlying pages use Microsoft Entra throughout. | **Newly flagged** | Cosmetic in Scout, but any doc text saying "Azure AD" is stale. Microsoft's own index page has not caught up — do not treat the index label as authoritative. |
| 7 | **NEW — Microsoft is rewriting design-area pages away from the `Design considerations` / `Design recommendations` structure.** At least three pages (`virtual-wan-network-topology`, `connectivity-to-other-providers`, `considerations/devops-teams-topologies`) have no recommendations heading at all; their ~41 combined recommendations are numbered task sections. Others use bespoke headings ("Management group recommendations", "Inventory and visibility recommendations"). | **Newly flagged** | Any coverage percentage Scout publishes against a recommendation count will silently drift as more pages are rewritten. If Scout states coverage numbers, date-stamp them and record the verification method. |
| 8 | **NEW — regulatory-compliance initiatives are versioned and the older versions are still shipped.** Azure simultaneously offers, e.g., six CIS Azure Foundations initiatives (v1.1.0 through v3.0.0), two ISO 27001 sets (2013 and 2022), three PCI sets, and both `NIST SP 800-53 Rev. 5` and `NIST SP 800-53 R5.1.1`. | **Newly flagged** | Scout must name the exact initiative version it scored. "CIS compliance: 72%" is meaningless across a 31-policy and a 168-policy initiative. |
| 9 | **NEW — `waf.storage.yaml` scores a WAF pillar that does not exist.** WAF has exactly five pillars. Storage is a WAF *service guide*, a different artefact. | **Newly flagged** | See Table 1. The most visible correctness defect in the rule set. |

---

## 3c. Minimum permissions to read and collect

**The short answer: `Reader` at the root management group covers every ARM resource provider Scout
collects — all 152 of them.** Azure's `Reader` role is defined as `*/read`, a single wildcard over
every control-plane read operation. There is no provider in the table below that needs more.

**No elevated roles are required.** Not Owner, not Contributor, not Global Administrator, not any
ADO admin role. Everything Scout does is a read.

### ARM resource providers — by category

| # | Category | Providers | Minimum permission | Role that grants it |
|---|---|---:|---|---|
| 1 | General | 8 | `*/read` | **Reader** |
| 2 | Compute | 12 | `*/read` | **Reader** |
| 3 | Networking | 2 | `*/read` | **Reader** |
| 4 | Storage | 6 | `*/read` | **Reader** |
| 5 | Web and Mobile | 5 | `*/read` | **Reader** |
| 6 | Containers | 4 | `*/read` | **Reader** |
| 7 | Databases | 8 | `*/read` | **Reader** |
| 8 | Analytics | 11 | `*/read` | **Reader** |
| 9 | AI + machine learning | 6 | `*/read` | **Reader** |
| 10 | Internet of Things | 11 | `*/read` | **Reader** |
| 11 | Integration | 15 | `*/read` | **Reader** |
| 12 | Identity (ARM only) | 5 | `*/read` | **Reader** |
| 13 | Security | 6 | `*/read` | **Reader** |
| 14 | DevOps | 7 | `*/read` | **Reader** |
| 15 | Migration | 5 | `*/read` | **Reader** |
| 16 | Monitor | 6 | `*/read` | **Reader** |
| 17 | Management and governance | 25 | `*/read` | **Reader** |
| 18 | Hybrid + multicloud | 10 | `*/read` | **Reader** |
| | **Total** | **152** | | **Reader — one assignment at root MG** |

### The calls that people assume need more — they don't

These are the ones worth stating explicitly, because they're the usual reason someone over-grants:

| What Scout calls | Specific permission | Reader enough? | Evidence |
|---|---|---|---|
| Defender alerts, assessments, pricing, secure score | `Microsoft.Security/*/read` | ✅ **Yes** | Subset of `*/read`. **Azure RBAC "Security Reader" is redundant** — note this is *not* the Entra role of the same name, which is separate and may be needed. |
| Diagnostic settings, metrics | `Microsoft.Insights/*/read` | ✅ **Yes** | Subset of `*/read`. **Monitoring Reader is redundant** — and it additionally grants `Microsoft.Support/*` (ticket *creation*), a write Scout never uses. |
| Cost Management query | `Microsoft.CostManagement/query/read` | ✅ **Yes** | Microsoft's [role-behaviour table](https://learn.microsoft.com/azure/cost-management-billing/costs/understand-work-scopes#azure-rbac-scopes) shows **Reader** = "Read only" on *Cost Analysis / Forecast / Query / Cost Details API*. **Cost Management Reader is redundant.** |
| Policy compliance state | `Microsoft.PolicyInsights/policyStates/queryResults/read`, `summarize/read` | ✅ **Yes** | Both `/read` and `/action` variants exist; the `/read` ones are covered by `Reader`. The `/action` variants belong to writer roles. |
| Advisor recommendations and score | `Microsoft.Advisor/*/read` | ✅ **Yes** | Subset of `*/read`. |
| VM quotas, SKUs | `Microsoft.Compute/locations/{usages,skus}/read` | ✅ **Yes** | Subset of `*/read`. |
| Patch data (Update Manager) | ARG tables `patchassessmentresources`, `patchinstallationresources` | ✅ **Yes** | Since the assessPatches fix. **Previously required a mutating `/action`** — see §3.4. |
| Management groups | `Microsoft.Management/managementGroups/read` | ⚠️ **Unconfirmed** | Reader must be assigned **at management-group scope**, not subscription scope. Whether that alone suffices, or **Management Group Reader** is genuinely additional, is untested — and currently confounded by a separate defect (§3.5). |

### These are FIVE separate permission systems

This is the part most commonly got wrong, including earlier drafts of this document. They are not
variants of one model — they are unrelated systems with different scoping, different portals, and
different approvers. **An Owner on every subscription in the tenant still reads zero directory
data, and zero billing data.**

| # | System | What it governs | Scope model | Example | Scout needs it for |
|---|---|---|---|---|---|
| 1 | **Azure RBAC** | Azure *resources* (ARM control plane) | MG → subscription → RG → resource | `Reader` | All 154 ARM collectors |
| 2 | **Entra directory roles** | The *directory* | Tenant-wide, no hierarchy | `Directory Readers` | 15 Entra collectors (`-Scope All`) |
| 3 | **Graph app permissions** | Directory, for *applications* | Per app registration, admin-consented | `User.Read.All` | Same 15, when running as a service principal |
| 4 | **Azure DevOps** | ADO orgs/projects | Per organisation / project | Project-level read | 5 DevOps collectors (`-IncludeDevOps`) |
| 5 | **Billing (EA/MCA)** | Billing accounts, profiles, invoice sections | Billing account → profile → invoice section | `Enterprise Administrator (read only)` | **Nothing today** — but gates cost data via two settings, and would be required for the CAF billing design area |

Systems 2 and 3 are two routes to the same data — pick one based on whether Scout runs as a user or
a service principal. Systems 1, 2/3, 4 and 5 are genuinely independent grants.

> ### ⚠️ Name collision — "Security Reader" exists in BOTH systems and they are different roles
>
> - **Azure RBAC "Security Reader"** — governs `Microsoft.Security/*` on Azure resources.
>   **Redundant**; `Reader` already covers it. This is the one to drop.
> - **Entra "Security Reader"** — governs Entra ID Protection, PIM, and sign-in/audit logs.
>   **A completely different role, and Scout may genuinely need it** (see below).
>
> Dropping the wrong one silently empties the risky-users and PIM worksheets. Always state which
> system a role belongs to.

### Entra ID — only if you run `-Scope All`

**Correction to an earlier draft of this document:** it recommended `Global Reader`. That is **not**
least-privilege — Microsoft classifies **Global Reader as a privileged role** (it is the read-only
counterpart to *Global Administrator*, spanning Microsoft 365, Exchange, SharePoint, Teams, Defender
and Purview — vastly more than Scout needs).

**Lower-privilege alternative — two narrow roles instead of one broad one:**

| Role | Privileged? | Covers | Scout data it unlocks |
|---|---|---|---|
| **`Directory Readers`** | **No** | Basic directory: users, groups, applications, service principals, org details | Users, Groups, Apps, ServicePrincipals, Organization, Domains |
| **`Security Reader`** *(Entra)* | Yes | ID Protection, PIM, Conditional Access, sign-in/audit logs | RiskyUsers, PIMAssignments, DirectoryRoles, ConditionalAccess, SecurityPolicies. **Required** — `Directory Readers` cannot read Conditional Access at all. NamedLocations is uncertain, see below. |
| `Reports Reader` | No | Sign-in and audit reports only | *Nothing Scout uses* — see `AuditLog.Read.All` below |
| ~~`Global Reader`~~ | **Yes** | Everything above **plus all of M365** | Works, but far more than required |

**Recommendation: `Directory Readers` + Entra `Security Reader`, not `Global Reader`.**
`Directory Readers` alone is enough if you skip risky-users and PIM data.

**Running as a service principal instead** — Graph *application* permissions, admin-consented:
`Organization.Read.All`, `User.Read.All`, `Group.Read.All`, `Application.Read.All`,
`RoleManagement.Read.Directory`, `Policy.Read.All`, `IdentityRiskyUser.Read.All`.

**Also needed but never checked by Scout:** `AdministrativeUnit.Read.All`, `Domain.Read.All`,
`IdentityProvider.Read.All` — their absence silently empties worksheets.
**`AuditLog.Read.All` is requested but no collector consumes it** — drop the ask.
Risky Users additionally requires an **Entra ID P2 licence**, regardless of role or permission.

#### Conditional Access boundary — RESOLVED

Checked against the published action lists in
[Microsoft Entra built-in roles](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference):

| Role | Conditional Access actions | Reads CA? |
|---|---|---|
| `Directory Readers` | **none — the action list contains no `conditionalAccessPolicies` entry at all** | ❌ **No** |
| **Entra `Security Reader`** | `conditionalAccessPolicies/standard/read`, `/owners/read`, `/policyAppliedTo/read` | ✅ Standard properties |
| `Global Reader` | `conditionalAccessPolicies/allProperties/read` | ✅ All properties |

**Conclusion: Entra `Security Reader` is required for Conditional Access — `Directory Readers`
alone cannot read it.** The two-role recommendation stands; it is not optional if you want the
ConditionalAccess worksheet populated.

#### Entra `Security Reader` — the verified actions Scout depends on

Read from the complete role definition (not a search excerpt) at
[Microsoft Entra built-in roles → Security Reader](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#security-reader):

| Action | Scout collector it enables |
|---|---|
| `microsoft.directory/conditionalAccessPolicies/standard/read` | ConditionalAccess |
| `microsoft.directory/conditionalAccessPolicies/owners/read` | ConditionalAccess |
| `microsoft.directory/conditionalAccessPolicies/policyAppliedTo/read` | ConditionalAccess |
| `microsoft.directory/namedLocations/standard/read` | **NamedLocations** |
| `microsoft.directory/identityProtection/allProperties/read` | RiskyUsers |
| `microsoft.directory/privilegedIdentityManagement/allProperties/read` | PIMAssignments |
| `microsoft.directory/policies/standard/read` | SecurityPolicies |
| `microsoft.directory/signInReports/allProperties/read` | *(unused — no collector)* |
| `microsoft.directory/auditLogs/allProperties/read` | *(unused — no collector)* |

**`Directory Readers` + Entra `Security Reader` covers every Entra collector Scout has.** No
`Global Reader` required.

> **Correction:** an earlier draft of this section claimed `Security Reader` lacked
> `namedLocations/standard/read` and that NamedLocations might therefore fail. That was wrong — it
> came from a truncated search result rather than the full role definition. The complete definition
> includes it. There is no NamedLocations gap.

The last two rows are worth noting for the opposite reason: `Security Reader` grants sign-in and
audit log read, and **no Scout collector consumes either** — consistent with the finding that
`AuditLog.Read.All` is requested but unused.

### Azure DevOps — only if you run `-IncludeDevOps`

A **fourth** system, unrelated to both Azure RBAC and Entra. Read-only **project-level** membership
(Stakeholder or Basic with read access) is sufficient — **no organisation administrator role is
required**. Scout has **zero pre-flight coverage** here, so a permission failure surfaces only under
`-Debug`.

### Cost and billing — a FIFTH permission system

Billing has its own role model, entirely separate from Azure RBAC. Critically:

> **"Subscription ownership alone doesn't provide access to EA historical charges, because
> subscription roles don't grant access to the EA billing scope."**
> — [MCA billing transition checklist](https://learn.microsoft.com/azure/cost-management-billing/microsoft-customer-agreement/checklist-microsoft-customer-agreement-billing-migration)

And billing scope doesn't even follow the same boundaries: **"Although RBAC scopes are bound to a
single directory, EA billing scopes aren't. An EA billing account may have subscriptions across any
number of Microsoft Entra directories."**
— [Understand and work with scopes](https://learn.microsoft.com/azure/cost-management-billing/costs/understand-work-scopes#billing-scopes)

#### Two different questions, two different answers

| What you want | Scope | Minimum access |
|---|---|---|
| **Cost of resources in a subscription** *(what Scout collects today)* | Azure RBAC | **`Reader`** + the view-charges gate below |
| **Invoices, EA enrollment structure, billing profiles, departments, billing RBAC** *(Scout collects none of this)* | Billing account | An actual **billing role** — see below |

**Everything Scout collects today is the first row.** `Get-ScoutCostInventory`, the VM/Arc
`EstimatedCost` calls, and `ReservationRecom` all query at subscription scope, so `Reader` covers
them. No billing role required.

#### Read-only billing roles, if you ever collect the second row

| Agreement | Read-only roles |
|---|---|
| **EA** | **Enterprise Administrator (read only)**, **Department Administrator (read only)** |
| **MCA** | **Billing account Reader**, **Billing profile Reader**, **Invoice section Reader** |
| Either | `Billing Reader` — an *Azure RBAC* role at subscription scope. **In preview, and unsupported in non-global clouds.** |

EA also has Enterprise Administrator, EA Purchaser, Department Administrator and Account Owner —
all write-capable. Scout would never need them.

#### ⚠️ The gates no role can satisfy — there are TWO, not one

Cost data can be empty with a perfectly correct role assignment:

| Gate | Applies to | Effect when disabled |
|---|---|---|
| **AO view charges** | Account Owners | No cost visibility |
| **DA view charges** | Department Administrators *and department read-only users* | **"Department users can't see costs at any level, even if they're an account or subscription owner."** |
| MCA equivalent | "Allow Azure subscription users to view and optimize costs" | Same effect |

Only an **Enterprise Administrator** (EA) or **Billing account owner** (MCA) can change these. Even
the `Billing Reader` RBAC role is subject to them — Microsoft states it explicitly: *"for that
Billing Reader to view billing information for the department or account, the Enterprise
Administrator must enable AO view charges or DA view charges policies."*

**This is almost certainly a more common cause of empty cost sheets than any permission problem**,
and Scout's pre-flight **cannot detect it by inspecting roles** — it would have to attempt the call
and interpret the failure.

#### Where this connects to the CAF gap

The CAF **"Azure billing and Microsoft Entra tenant"** design area (§3b, ~0% covered) is precisely
this second row — EA/MCA enrollment structure, department and invoice-section hierarchy, MFA on
subscription creators, billing RBAC assignments. Closing that gap is the one piece of work that
*would* require billing-scope read access. Worth knowing before scoping it.

### Verification status — read this before quoting the table

Everything above is **documentation analysis, not a tested result**. No run has been performed with
a `Reader`-only principal to confirm every collector still returns data.

The reasoning is sound and now Microsoft-doc-backed, but the honest position is: **probable, not
proven.** The test that settles it — a live run with a Reader-only service principal, comparing
per-collector row counts against a full-role run — is roughly half a day, and depends on the
per-collector row-count work (§6 item 9) existing first.

---

### Per-collector permission tables

### How to read these tables

The 174 collectors in `manifests/collectors/<Category>/*.psd1` **do not call Azure**. They are pure transforms over an in-memory `$Resources` bag. Every Azure call is made by ~13 functions in `src/collect/`. A collector's permission requirement is therefore the requirement of *the collect-layer function that produces the resource type it consumes*.

Access classes A–K are carried over from `docs/audits/AB6445-least-privilege-permissions-audit.md` §2.1:

| Class | Producer (`src/collect/`) | API surface |
|---|---|---|
| **A** | `Get-ScoutRawInventory.ps1` | Azure Resource Graph — `resources`, `resourcecontainers`, `recoveryservicesresources`, `desktopvirtualizationresources`, `advisorresources`, `securityresources`, `supportresources`, `patchassessmentresources`, `patchinstallationresources` |
| **B** | `Get-ScoutSubscriptionSecurityPolicySweep.ps1` | `Get-AzSecurity*`, `Get-AzDiagnosticSetting`, `Get-AzPolicyState` |
| **C** | `Get-ScoutArmChildResource.ps1` | `Invoke-AzRestMethod` GET on 12 ARM child paths |
| **D** | `Get-ScoutApiResources.ps1` | `Invoke-RestMethod` GET/POST on 7 ARM paths |
| **E** | `Get-ScoutTenantWideResource.ps1` | `Get-AzRoleDefinition -Custom`, `Get-AzManagementGroup -Expand -Recurse` |
| **F** | `Get-ScoutOperationalCollectorEnrichment.ps1` | `microsoft.insights/metrics`, `replicationEligibilityResults`, `Get-AzStorage*ServiceProperty` |
| **G** | *(retired)* | was `POST .../assessPatches`; replaced this session by ARG `patchassessmentresources` / `patchinstallationresources` — read-only. Class G no longer exists. |
| **H** | `Get-ScoutCostInventory.ps1` + enrichment cost half | `POST Microsoft.CostManagement/query` |
| **I** | `Get-ScoutVmQuotas.ps1`, `Get-ScoutVmSkuDetails.ps1` | `Get-AzVMUsage`, `Get-AzComputeResourceSku` |
| **J** | `Start-ScoutEntraExtraction.ps1` | Microsoft Graph `/v1.0/*` |
| **K** | `Start-ScoutDevOpsExtraction.ps1` | `dev.azure.com` / `app.vssps.visualstudio.com` REST |

**Four separate permission systems appear below. They are not interchangeable.** Every role name states its system.

1. **Azure RBAC** — Azure resources; scoped MG → subscription → RG → resource.
2. **Entra directory roles** — the directory; tenant-wide; no scope hierarchy.
3. **Microsoft Graph app permissions** — for service principals; require admin consent.
4. **Azure DevOps** — org/project security-group membership.

> ⚠️ **"Security Reader" exists in both Azure RBAC and Entra and they are different roles.** The **Azure RBAC** Security Reader is redundant here (a strict subset of Reader's `*/read`) and should not be granted. The **Entra** Security Reader is genuinely required for four Identity collectors. Wherever the name appears below it is qualified.

**`Verified` column:** `Doc` = confirmed against Microsoft Learn. `Untested` = derived by reasoning from the documented role definition, no live run. **Nothing here has been tested against a Reader-only principal** — no such run has been performed.

#### Established facts these tables rest on

| Fact | Source |
|---|---|
| Azure RBAC **`Reader`** = `Actions: */read`, `NotActions: none`, `DataActions: none`. Control plane only. | [Built-in roles — General](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/general) |
| **Cost Management query → `Reader` is sufficient.** `Microsoft.CostManagement/query/read` exists and Microsoft's role-behaviour table shows Reader = "Read only" on Cost Analysis / Forecast / Query / Cost Details API. **Cost Management Reader is redundant.** | [Assign access to Cost Management data](https://learn.microsoft.com/azure/cost-management-billing/costs/assign-access-acm-data), [Permissions — Management and governance](https://learn.microsoft.com/azure/role-based-access-control/permissions/management-and-governance#microsoftcostmanagement) |
| **Policy Insights → `Reader` is sufficient.** Both `policyStates/queryResults/{read,action}` and `policyStates/summarize/{read,action}` exist; the `/read` variants fall inside `*/read`. | [Permissions — Management and governance](https://learn.microsoft.com/azure/role-based-access-control/permissions/management-and-governance#microsoftpolicyinsights) |
| Azure RBAC **`Security Reader`** and **`Monitoring Reader`** are both redundant — strict subsets of `*/read` for every call Scout makes. Monitoring Reader additionally grants `Microsoft.Support/*`, which includes ticket **creation** (a write). | [Security roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/security#security-reader), [Monitor roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/monitor#monitoring-reader) |
| Patch data now comes from ARG tables `patchassessmentresources` / `patchinstallationresources` (read-only). The old `assessPatches` POST — an ARM `/action`, not a read — was removed. `src/collect/Get-ScoutRawInventory.ps1:455-476`, `Get-ScoutOperationalCollectorEnrichment.ps1:230-232`. | Repo code |

**Net effect: every one of the 154 ARM collectors is satisfied by Azure RBAC `Reader` alone.** No custom role, no Cost Management Reader, no Security Reader, no Monitoring Reader.

---

### Citation coverage

Every row of Tables A, B and C now carries a `Source`. The numbers, blunt:

| | Count |
|---|---:|
| Distinct ARM permission claims in Table A | **142** |
| Cited to a Microsoft Learn page | **133** (93.7%) |
| **`NOT FOUND`** — no Microsoft page lists the action | **9** (6.3%) |
| Entra claims in Table B | 15 collectors / 2 role definitions — **14 cited, 1 `NOT FOUND`** |
| Azure DevOps claims in Table C | 5 — **5 cited** |

**Providers that could not be verified — 3:**

| Provider | Status |
|---|---|
| `Microsoft.AzureArcData` | Appears on **no** `permissions/` category page. Only `sqlServerInstances/read` is citable, and only via `built-in-roles/databases`. `dataControllers/read` and `sqlManagedInstances/read` are uncited. |
| `Microsoft.ClassicCompute` | Appears on **no** `permissions/` category page. Classic (ASM) is retired; the provider has been dropped from the RBAC reference. |
| `Microsoft.EdgeConfig` | Appears on **no** page anywhere. Not a real resource provider. |

**The 9 `NOT FOUND` actions, and what each means:**

| Action | Finding |
|---|---|
| `Microsoft.AzureArcData/dataControllers/read` | Provider absent from RBAC docs; type is real (ARM template reference) |
| `Microsoft.AzureArcData/sqlManagedInstances/read` | Same |
| `Microsoft.ClassicCompute/domainNames/read` | Provider absent from RBAC docs; retired deployment model |
| `Microsoft.AzureStackHCI/sites/read` | Provider **is** documented — and lists **no `sites` type** |
| `Microsoft.HybridCompute/sites/read` | Provider **is** documented — and lists **no `sites` type** |
| `Microsoft.EdgeConfig/sites/read` | Provider does not exist |
| `Microsoft.DBforPostgreSQL/servers/read` | Provider **is** documented — lists **only `flexibleServers`**. Single Server is retired. |
| `Microsoft.Network/natGateways/read` | Provider documented; only `natGateways/join/action` listed. Type is real — the read action is simply undocumented. |
| `Microsoft.RecoveryServices/replicationEligibilityResults/read` | Provider documented; no `replicationEligibilityResults` type listed. The ARM API exists. |

**Two of these are code findings, not documentation gaps**, and they corroborate AB#6444 independently:

- **`Hybrid/ArcSites`** declares three provider/type pairs. `Microsoft.EdgeConfig` is not a provider at all, and neither `AzureStackHCI` nor `HybridCompute` has a `sites` type. All three targets are unreal — which is a complete explanation for a collector that emits zero rows in every tenant.
- **`Databases/POSTGRE`** targets `Microsoft.DBforPostgreSQL/servers`, a type Microsoft no longer documents. Only `flexibleServers` exists. Same conclusion.

The other seven are gaps in Microsoft's own reference, not in Scout. `Microsoft.Network/natGateways/read` in particular is plainly a documentation omission — the type is real and Scout returns rows from it.

**Source column format.** Values are anchors relative to `https://learn.microsoft.com/azure/role-based-access-control/` (e.g. `permissions/compute#microsoftcompute` →
<https://learn.microsoft.com/azure/role-based-access-control/permissions/compute#microsoftcompute>). Entra anchors are relative to `https://learn.microsoft.com/` (`entra/permissions-reference#...` →
<https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#security-reader>). Azure DevOps anchors are relative to `https://learn.microsoft.com/azure/` (`devops/...`).

Where several rows share one provider page the same reference repeats — that is expected. **The `Source` column is the evidence for the `Verified: Doc` claim; it does not upgrade `Untested` rows.** Nothing here has been run against a `Reader`-only principal.

---

### Table A — ARM collectors (154)

`Minimum permission` is the control-plane action the call authorizes on. All of them are `.../read` and therefore inside Reader's `*/read`.

#### AI (27)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| AIFoundryHubs | `microsoft.machinelearningservices/workspaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.MachineLearningServices/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| AIFoundryProjects | `microsoft.machinelearningservices/workspaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.MachineLearningServices/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| AppliedAIServices | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| AzureAI | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| BotServices | `microsoft.botservice/botservices` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.BotService/botServices/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftbotservice` |
| ComputerVision | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| ContentModerator | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| ContentSafety | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| CustomVision | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| FaceAPI | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| FormRecognizer | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| HealthInsights | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| ImmersiveReader | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| MachineLearning | `microsoft.machinelearningservices/workspaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.MachineLearningServices/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| MLComputes | `AZSC/ARMChild/MLComputes` | `Get-ScoutArmChildResource` — GET `{ws}/computes?api-version=2023-04-01` | C | `Microsoft.MachineLearningServices/workspaces/computes/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| MLDatasets | `AZSC/ARMChild/MLDatasets` | `Get-ScoutArmChildResource` — GET `{ws}/data` + `/versions` | C | `Microsoft.MachineLearningServices/workspaces/data/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| MLDatastores | `AZSC/ARMChild/MLDatastores` | `Get-ScoutArmChildResource` — GET `{ws}/datastores` | C | `Microsoft.MachineLearningServices/workspaces/datastores/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| MLEndpoints | `AZSC/ARMChild/MLEndpoints` | `Get-ScoutArmChildResource` — GET `{ws}/onlineEndpoints`, `/batchEndpoints`, `/deployments` | C | `Microsoft.MachineLearningServices/workspaces/onlineEndpoints/read`, `/batchEndpoints/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| MLModels | `AZSC/ARMChild/MLModels` | `Get-ScoutArmChildResource` — GET `{ws}/models` + `/versions` | C | `Microsoft.MachineLearningServices/workspaces/models/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| MLPipelines | `AZSC/ARMChild/MLPipelines` | `Get-ScoutArmChildResource` — GET `{ws}/jobs?$filter=jobType eq 'Pipeline'` | C | `Microsoft.MachineLearningServices/workspaces/jobs/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftmachinelearningservices` |
| OpenAIAccounts | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| OpenAIDeployments | `AZSC/ARMChild/OpenAIDeployments` | `Get-ScoutArmChildResource` — GET `{acct}/deployments?api-version=2023-05-01` | C | `Microsoft.CognitiveServices/accounts/deployments/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| SearchIndexes | `AZSC/ARMChild/SearchIndexes` | `Get-ScoutArmChildResource` — GET `{svc}/indexes?api-version=2023-11-01` | C | `Microsoft.Search/searchServices/indexes/read` (control plane) | Azure RBAC **Reader** | Untested | `permissions/ai-machine-learning#microsoftsearch` |
| SearchServices | `microsoft.search/searchservices` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Search/searchServices/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftsearch` |
| SpeechService | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| TextAnalytics | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |
| Translator | `microsoft.cognitiveservices/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.CognitiveServices/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/ai-machine-learning#microsoftcognitiveservices` |

*`SearchIndexes` marked Untested: the ARM control-plane `indexes` path is served by the Search management plane, but Search index enumeration also exists as a data-plane API. The collect layer uses `Invoke-AzRestMethod` against ARM, so it should authorize on `*/read`; not proven against a Reader-only principal.*

#### Analytics (6)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| Databricks | `microsoft.databricks/workspaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Databricks/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/analytics#microsoftdatabricks` |
| DataExplorerCluster | `microsoft.kusto/clusters` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Kusto/clusters/read` | Azure RBAC **Reader** | Doc | `permissions/analytics#microsoftkusto` |
| EvtHub | `microsoft.eventhub/namespaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.EventHub/namespaces/read` | Azure RBAC **Reader** | Doc | `permissions/integration#microsofteventhub` |
| Purview | `microsoft.purview/accounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Purview/accounts/read` | Azure RBAC **Reader** | Doc | `permissions/analytics#microsoftpurview` |
| Streamanalytics | `microsoft.streamanalytics/streamingjobs` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.StreamAnalytics/streamingJobs/read` | Azure RBAC **Reader** | Doc | `permissions/internet-of-things#microsoftstreamanalytics` |
| Synapse | `microsoft.synapse/workspaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Synapse/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/analytics#microsoftsynapse` |

#### Compute (14)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| AvailabilitySets | `microsoft.compute/availabilitysets` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Compute/availabilitySets/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftcompute` |
| AVD | `microsoft.desktopvirtualization/hostpools` | `Get-ScoutRawInventory` (ARG `desktopvirtualizationresources`) | A | `Microsoft.DesktopVirtualization/hostPools/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftdesktopvirtualization` |
| AVDApplicationGroups | `microsoft.desktopvirtualization/applicationgroups` | `Get-ScoutRawInventory` (ARG `desktopvirtualizationresources`) | A | `Microsoft.DesktopVirtualization/applicationGroups/read` | Azure RBAC **Reader** | Doc | n/a |
| AVDApplications | `AZSC/ARMChild/AVDApplications` | `Get-ScoutArmChildResource` — GET `{appgroup}/applications?api-version=2022-09-09` | C | `Microsoft.DesktopVirtualization/applicationGroups/applications/read` | Azure RBAC **Reader** | Doc | n/a |
| AVDAzureLocal | `AZSC/AVD/AzureLocalSessionHost` | `ConvertTo-ScoutAvdAzureLocalSessionHost` over ARG `microsoft.azurestackhci/*` + `desktopvirtualizationresources` | A (derived) | `Microsoft.AzureStackHCI/*/read` + `Microsoft.DesktopVirtualization/hostPools/sessionHosts/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftazurestackhci` + `permissions/compute#microsoftdesktopvirtualization` |
| AVDScalingPlans | `microsoft.desktopvirtualization/scalingplans` | `Get-ScoutRawInventory` (ARG `desktopvirtualizationresources`) | A | `Microsoft.DesktopVirtualization/scalingPlans/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftdesktopvirtualization` |
| AVDSessionHosts | `microsoft.desktopvirtualization/hostpools/sessionhosts` | `Get-ScoutRawInventory` (ARG `desktopvirtualizationresources`) | A | `Microsoft.DesktopVirtualization/hostPools/sessionHosts/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftdesktopvirtualization` |
| AVDWorkspaces | `microsoft.desktopvirtualization/workspaces` | `Get-ScoutRawInventory` (ARG `desktopvirtualizationresources`) | A | `Microsoft.DesktopVirtualization/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftdesktopvirtualization` |
| CloudServices | `microsoft.classiccompute/domainnames` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ClassicCompute/domainNames/read` | Azure RBAC **Reader** | Doc | **NOT FOUND** — `Microsoft.ClassicCompute` appears on no `permissions/` category page. Classic (ASM) deployments are retired; the provider has been dropped from the RBAC reference. |
| **VirtualMachine** | `microsoft.compute/virtualmachines` **+** `AZSC/Operational/VirtualMachine`, `AZSC/VM/SKU`, `AZSC/VM/Quotas` | `Get-ScoutRawInventory` **+** `Get-ScoutOperationalCollectorEnrichment` (metrics, `replicationEligibilityResults`, **POST CostManagement/query**) **+** `Get-ScoutVmQuotas` / `Get-ScoutVmSkuDetails` | A + F + H + I | `Microsoft.Compute/virtualMachines/read`, `microsoft.insights/metrics/read`, `Microsoft.RecoveryServices/replicationEligibilityResults/read`, `Microsoft.CostManagement/query/read`, `Microsoft.Compute/locations/usages/read`, `Microsoft.Compute/skus/read` | Azure RBAC **Reader** | Doc for reads; **Untested** for the cost POST authorizing on `/read` | `permissions/compute#microsoftcompute`, `permissions/monitor#microsoftinsights`, `permissions/management-and-governance#microsoftcostmanagement`. ⚠️ `Microsoft.RecoveryServices/replicationEligibilityResults/read` is **NOT FOUND** — `Microsoft.RecoveryServices` is documented but lists no `replicationEligibilityResults` type |
| VirtualMachineScaleSet | `microsoft.compute/virtualmachinescalesets` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Compute/virtualMachineScaleSets/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftcompute` |
| VMDisk | `microsoft.compute/disks` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Compute/disks/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftcompute` |
| **VMOperationalData** | `microsoft.compute/virtualmachines` **+** `AZSC/Operational/VMOperationalData` | `Get-ScoutRawInventory` (ARG `patchassessmentresources`, `patchinstallationresources`) → shaped by `Get-ScoutOperationalCollectorEnrichment` | A | `Microsoft.Compute/virtualMachines/read` + ARG read of the patch tables | Azure RBAC **Reader** | Doc — **was** the only Azure collector needing a non-read action; `assessPatches` POST removed this session | `permissions/compute#microsoftcompute` |
| VMWare | `Microsoft.AVS/privateClouds` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AVS/privateClouds/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftavs` |

#### Containers (6)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| AKS | `microsoft.containerservice/managedclusters` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ContainerService/managedClusters/read` | Azure RBAC **Reader** | Doc | `permissions/containers#microsoftcontainerservice` |
| ARO | `microsoft.redhatopenshift/openshiftclusters` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.RedHatOpenShift/openShiftClusters/read` | Azure RBAC **Reader** | Doc | `permissions/containers#microsoftredhatopenshift` |
| ContainerApp | `microsoft.app/containerapps` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.App/containerApps/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftapp` |
| ContainerAppEnv | `microsoft.app/managedenvironments` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.App/managedEnvironments/read` | Azure RBAC **Reader** | Doc | `permissions/compute#microsoftapp` |
| ContainerGroups | `microsoft.containerinstance/containergroups` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ContainerInstance/containerGroups/read` | Azure RBAC **Reader** | Doc | `permissions/containers#microsoftcontainerinstance` |
| ContainerRegistries | `microsoft.containerregistry/registries` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ContainerRegistry/registries/read` | Azure RBAC **Reader** | Doc | `permissions/containers#microsoftcontainerregistry` |

#### Databases (13)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| CosmosDB | `microsoft.documentdb/databaseaccounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.DocumentDB/databaseAccounts/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftdocumentdb` |
| MariaDB | `microsoft.dbformariadb/servers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.DBforMariaDB/servers/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftdbformariadb` |
| MySQL | `microsoft.dbformysql/servers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.DBforMySQL/servers/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftdbformysql` |
| MySQLflexible | `Microsoft.DBforMySQL/flexibleServers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.DBforMySQL/flexibleServers/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftdbformysql` |
| **POSTGRE** ⚠️ | `microsoft.dbforpostgresql/servers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.DBforPostgreSQL/servers/read` | Azure RBAC **Reader** | **BROKEN** — emits zero rows regardless of permission (AB#6444 §4) | **NOT FOUND** ⚠️ `permissions/databases#microsoftdbforpostgresql` lists **only `flexibleServers/read`** — there is no `servers` type. Single Server is retired; the collector targets a type that no longer exists. |
| POSTGREFlexible | `Microsoft.DBforPostgreSQL/flexibleServers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.DBforPostgreSQL/flexibleServers/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftdbforpostgresql` |
| RedisCache | `microsoft.cache/redis` + `microsoft.cache/redisenterprise` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Cache/redis/read`, `Microsoft.Cache/redisEnterprise/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftcache` |
| SQLDB | `microsoft.sql/servers/databases` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Sql/servers/databases/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftsql` |
| SQLMI | `microsoft.sql/managedInstances` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Sql/managedInstances/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftsql` |
| SQLMIDB | `microsoft.sql/managedinstances/databases` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Sql/managedInstances/databases/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftsql` |
| SQLPOOL | `microsoft.sql/servers/elasticPools` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Sql/servers/elasticPools/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftsql` |
| SQLSERVER | `microsoft.sql/servers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Sql/servers/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftsql` |
| SQLVM | `microsoft.sqlvirtualmachine/sqlvirtualmachines` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.SqlVirtualMachine/sqlVirtualMachines/read` | Azure RBAC **Reader** | Doc | `permissions/databases#microsoftsqlvirtualmachine` |

#### Hybrid (16)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| ArcDataControllers | `microsoft.azurearcdata/datacontrollers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureArcData/dataControllers/read` | Azure RBAC **Reader** | Doc | **NOT FOUND** — `Microsoft.AzureArcData` appears on no `permissions/` category page. The type exists in the ARM template reference; only `sqlServerInstances/read` is cited anywhere in RBAC docs. |
| ArcExtensions | `microsoft.hybridcompute/machines/extensions` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.HybridCompute/machines/extensions/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsofthybridcompute` |
| ArcGateways | `microsoft.hybridcompute/gateways` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.HybridCompute/gateways/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsofthybridcompute` |
| ArcKubernetes | `microsoft.kubernetes/connectedclusters` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Kubernetes/connectedClusters/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftkubernetes` |
| ArcResourceBridge | `microsoft.resourceconnector/appliances` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ResourceConnector/appliances/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftresourceconnector` |
| **ArcServerOperationalData** | `microsoft.hybridcompute/machines` **+** `AZSC/Operational/ArcServerOperationalData` | `Get-ScoutRawInventory` (ARG `patchassessmentresources`, `patchinstallationresources`) → shaped by `Get-ScoutOperationalCollectorEnrichment` | A | `Microsoft.HybridCompute/machines/read` + ARG read of the patch tables | Azure RBAC **Reader** | Doc — `assessPatches` POST removed this session | `permissions/hybrid-multicloud#microsofthybridcompute` |
| **ARCServers** | `microsoft.hybridcompute/machines` **+** `AZSC/Operational/ARCServers` | `Get-ScoutRawInventory` **+** `Get-ScoutOperationalCollectorEnrichment` (**POST** `policyStates/latest/queryResults`, **POST** `CostManagement/query`) | A + H | `Microsoft.HybridCompute/machines/read`, `Microsoft.PolicyInsights/policyStates/queryResults/read`, `Microsoft.CostManagement/query/read` | Azure RBAC **Reader** | Doc for the type read; **Untested** for the two POSTs authorizing on `/read` | `permissions/hybrid-multicloud#microsofthybridcompute`, `permissions/management-and-governance#microsoftpolicyinsights`, `permissions/management-and-governance#microsoftcostmanagement` |
| **ArcSites** ⚠️ | `microsoft.azurestackhci/sites` + `microsoft.edgeconfig/sites` + `microsoft.hybridcompute/sites` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureStackHCI/sites/read`, `Microsoft.EdgeConfig/sites/read`, `Microsoft.HybridCompute/sites/read` | Azure RBAC **Reader** | **BROKEN** — emits zero rows regardless of permission (AB#6444 §4) | **NOT FOUND — all three** ⚠️ `AzureStackHCI` and `HybridCompute` are documented at `permissions/hybrid-multicloud` but **neither lists a `sites` type**; `Microsoft.EdgeConfig` appears on **no** provider page. Corroborates AB#6444. |
| ArcSQLManagedInstances | `microsoft.azurearcdata/sqlmanagedinstances` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureArcData/sqlManagedInstances/read` | Azure RBAC **Reader** | Doc | **NOT FOUND** — same cause as `ArcDataControllers` |
| ArcSQLServers | `microsoft.azurearcdata/sqlserverinstances` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureArcData/sqlServerInstances/read` | Azure RBAC **Reader** | Doc | `built-in-roles/databases#azure-connected-sql-server-onboarding` — **not on any `permissions/` provider page** |
| Clusters | `microsoft.azurestackhci/clusters` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureStackHCI/clusters/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftazurestackhci` |
| GalleryImages | `microsoft.azurestackhci/galleryimages` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureStackHCI/galleryImages/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftazurestackhci` |
| LogicalNetworks | `microsoft.azurestackhci/logicalnetworks` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureStackHCI/logicalNetworks/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftazurestackhci` |
| MarketplaceGalleryImages | `microsoft.azurestackhci/marketplacegalleryimages` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureStackHCI/marketplaceGalleryImages/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftazurestackhci` |
| StorageContainers | `microsoft.azurestackhci/storagecontainers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureStackHCI/storageContainers/read` | Azure RBAC **Reader** | Doc | `permissions/hybrid-multicloud#microsoftazurestackhci` |
| **VirtualMachines** ⚠️ | `microsoft.azurestackhci/virtualmachineinstances` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AzureStackHCI/virtualMachineInstances/read` | Azure RBAC **Reader** | **BROKEN** — emits zero rows regardless of permission (AB#6444 §4) | `permissions/hybrid-multicloud#microsoftazurestackhci` |

#### Identity — the ARM one (1)

*The other 15 Identity collectors are Microsoft Graph and appear in Table B.*

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| ManagedIds | `Microsoft.ManagedIdentity/userAssignedIdentities` | `Get-ScoutApiResources` — GET `/subscriptions/{id}/providers/Microsoft.ManagedIdentity/userAssignedIdentities?api-version=2023-01-31` | D | `Microsoft.ManagedIdentity/userAssignedIdentities/read` | Azure RBAC **Reader** | Doc | `permissions/identity#microsoftmanagedidentity` |

#### Integration (2) · IoT (1)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| APIM | `microsoft.apimanagement/service` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ApiManagement/service/read` | Azure RBAC **Reader** | Doc | `permissions/integration#microsoftapimanagement` |
| ServiceBUS | `microsoft.servicebus/namespaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ServiceBus/namespaces/read` | Azure RBAC **Reader** | Doc | `permissions/integration#microsoftservicebus` |
| IOTHubs | `microsoft.devices/iothubs` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Devices/IotHubs/read` | Azure RBAC **Reader** | Doc | `permissions/internet-of-things#microsoftdevices` |

#### Management — ARM (14)

*The five DevOps collectors live in this category on disk but are Azure DevOps, not Azure RBAC — see Table C.*

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| AdvisorScore | `Microsoft.Advisor/advisorScore` | `Get-ScoutApiResources` — GET `/providers/Microsoft.Advisor/advisorScore?api-version=2023-01-01` | D | `Microsoft.Advisor/advisorScore/read` | Azure RBAC **Reader** | Doc | `permissions/management-and-governance#microsoftadvisor` |
| AllSubscriptions | `AZSC/Management/SubscriptionEnrichment` | `Get-ScoutOperationalCollectorEnrichment` over ARG `resourcecontainers` mgChain | F | `Microsoft.Resources/subscriptions/read`, `Microsoft.Management/managementGroups/read` | Azure RBAC **Reader** — **must be assigned at MG scope** for the mgChain to resolve | Untested | `permissions/management-and-governance#microsoftresources` + `permissions/management-and-governance#microsoftmanagement` |
| AutomationAccounts | `microsoft.automation/automationaccounts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Automation/automationAccounts/read` | Azure RBAC **Reader** | Doc | n/a |
| Backup | `microsoft.recoveryservices/vaults/backuppolicies` | `Get-ScoutRawInventory` (ARG `recoveryservicesresources`) | A | `Microsoft.RecoveryServices/vaults/backupPolicies/read` | Azure RBAC **Reader** | Doc | `permissions/management-and-governance#microsoftrecoveryservices` |
| **CustomRoleDefinitions** ⚠️ | `AZSC/Management/RoleDefinition` | `Get-ScoutTenantWideResource` — `Get-AzRoleDefinition -Custom` | E | `Microsoft.Authorization/roleDefinitions/read` | Azure RBAC **Reader** at MG scope | **BROKEN** — gated on `-IncludeTenantWideResources`, a switch with no production caller (AB#6444 §4). Permission answer is moot until wired. | `permissions/management-and-governance#microsoftauthorization` |
| **LighthouseDelegations** ⚠️ | `Microsoft.ManagedServices/registrationDefinitions` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.ManagedServices/registrationDefinitions/read` | Azure RBAC **Reader** | **BROKEN** — emits zero rows regardless of permission (AB#6444 §4) | `permissions/management-and-governance#microsoftmanagedservices` |
| MaintenanceConfigurations | `microsoft.maintenance/maintenanceconfigurations` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Maintenance/maintenanceConfigurations/read` | Azure RBAC **Reader** | Doc | `permissions/management-and-governance#microsoftmaintenance` |
| **ManagementGroups** ⚠️ | `AZSC/Management/ManagementGroup` | `Get-ScoutTenantWideResource` — `Get-AzManagementGroup -Expand -Recurse` | E | `Microsoft.Management/managementGroups/read` | Azure RBAC **Reader assigned at MG scope**; whether **Management Group Reader** is additionally required is **unresolved** | **BROKEN** — same `-IncludeTenantWideResources` gate. The permission question is confounded by the defect: no run has ever exercised this path in production. | `permissions/management-and-governance#microsoftmanagement` |
| PolicyComplianceStates | `AZSC/Subscription/SecurityPolicySweep` | `Get-ScoutSubscriptionSecurityPolicySweep` — `Get-AzPolicyState` | B | `Microsoft.PolicyInsights/policyStates/queryResults/read` | Azure RBAC **Reader** | Doc | `permissions/management-and-governance#microsoftpolicyinsights` |
| **PolicyDefinitions** ⚠️ | `AZSC/Management/PolicyDefinition` | `Get-ScoutTenantWideResource` (E); `Get-ScoutApiResources` also GETs `Microsoft.Authorization/policyDefinitions?api-version=2023-04-01` (D) | E / D | `Microsoft.Authorization/policyDefinitions/read` | Azure RBAC **Reader** | **BROKEN** — the collector consumes the class-E type, which the ungated switch never produces (AB#6444 §4) | `permissions/management-and-governance#microsoftauthorization` |
| **PolicySetDefinitions** ⚠️ | `AZSC/Management/PolicySetDefinition` | `Get-ScoutTenantWideResource` (E); `Get-ScoutApiResources` also GETs `Microsoft.Authorization/policySetDefinitions` (D) | E / D | `Microsoft.Authorization/policySetDefinitions/read` | Azure RBAC **Reader** | **BROKEN** — same cause | `permissions/management-and-governance#microsoftauthorization` |
| RecoveryVault | `microsoft.recoveryservices/vaults` | `Get-ScoutRawInventory` (ARG `recoveryservicesresources`) | A | `Microsoft.RecoveryServices/vaults/read` | Azure RBAC **Reader** | Doc | `permissions/management-and-governance#microsoftrecoveryservices` |
| ReservationRecom | `Microsoft.Consumption/reservationRecommendations` | `Get-ScoutApiResources` — GET `/providers/Microsoft.Consumption/reservationRecommendations?api-version=2023-05-01` | D | `Microsoft.Consumption/reservationRecommendations/read` | Azure RBAC **Reader** | Doc — **but gated by the EA/MCA billing setting; see note below** | `permissions/management-and-governance#microsoftconsumption` |
| SupportTickets | `Microsoft.Support/supportTickets` | `Get-ScoutRawInventory` (ARG `supportresources`; skipped in Azure US Government) | A | `Microsoft.Support/supportTickets/read` | Azure RBAC **Reader** | Doc | `permissions/general#microsoftsupport` |

#### Monitor (24)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| ActionGroups | `microsoft.insights/actiongroups` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/actionGroups/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| ActivityLogAlertRules | `microsoft.insights/activitylogalerts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/activityLogAlerts/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| AppInsights | `microsoft.insights/components` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/components/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| AppInsightsAvailabilityTests | `microsoft.insights/webtests` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/webTests/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| **AppInsightsContinuousExport** ⚠️ | `AZSC/ARMChild/AppInsightsContinuousExport` | **none** — `Get-ScoutArmChildResource` deliberately never produces this type (Azure retired the endpoint) | — | n/a | n/a | **BROKEN / RETIRED** — permanently empty; not a permission problem, but will look like one | n/a |
| AppInsightsProactiveDetection | `AZSC/ARMChild/AppInsightsProactiveDetection` | `Get-ScoutArmChildResource` — GET `{comp}/ProactiveDetectionConfigs?api-version=2018-05-01-preview` | C | `Microsoft.Insights/components/ProactiveDetectionConfigs/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| AppInsightsWebTests | `microsoft.insights/webtests` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/webTests/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| **AppInsightsWorkItems** ⚠️ | `AZSC/ARMChild/AppInsightsWorkItems` | **none** — endpoint retired by Azure | — | n/a | n/a | **BROKEN / RETIRED** — permanently empty | n/a |
| AutoscaleSettings | `microsoft.insights/autoscalesettings` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/autoscaleSettings/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| DataCollectionEndpoints | `microsoft.insights/datacollectionendpoints` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/dataCollectionEndpoints/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| DataCollectionRules | `microsoft.insights/datacollectionrules` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/dataCollectionRules/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| LAWorkspaceLinkedServices | `AZSC/ARMChild/LAWorkspaceLinkedServices` | `Get-ScoutArmChildResource` — GET `{ws}/linkedServices?api-version=2020-08-01` | C | `Microsoft.OperationalInsights/workspaces/linkedServices/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftoperationalinsights` |
| LAWorkspaceSavedSearches | `AZSC/ARMChild/LAWorkspaceSavedSearches` | `Get-ScoutArmChildResource` — GET `{ws}/savedSearches?api-version=2020-08-01` | C | `Microsoft.OperationalInsights/workspaces/savedSearches/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftoperationalinsights` |
| LAWorkspaceSolutions | `microsoft.operationsmanagement/solutions` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.OperationsManagement/solutions/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftoperationsmanagement` |
| MetricAlertRules | `microsoft.insights/metricalerts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/metricAlerts/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| MonitorMetricsIngestion | `microsoft.operationalinsights/workspaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.OperationalInsights/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftoperationalinsights` |
| MonitorPrivateLinkScopes | `microsoft.insights/privatelinkscopes` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/privateLinkScopes/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| MonitorWorkbooks | `microsoft.insights/workbooks` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/workbooks/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| **Outages** ⚠️ | `AZSC/Monitor/Outage` | `Get-ScoutApiResources` — GET `/providers/Microsoft.ResourceHealth/events?api-version=2022-10-01` → `Get-ScoutOutageResource` | D | `Microsoft.ResourceHealth/events/read` | Azure RBAC **Reader** | **BROKEN** — `Get-ScoutOutageResource` runs *before* the API merge, so it never sees the events (AB#6444 §4) | `permissions/management-and-governance#microsoftresourcehealth` |
| **ResourceDiagnosticSettings** ⚠️ | `microsoft.insights/diagnosticsettings` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/diagnosticSettings/read` | Azure RBAC **Reader** | **BROKEN** — emits zero rows regardless of permission (AB#6444 §4). Note: `diagnosticSettings` is an extension resource and is not returned by the ARG `resources` table. | `permissions/monitor#microsoftinsights` |
| ScheduledQueryRules | `microsoft.insights/scheduledqueryrules` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Insights/scheduledQueryRules/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| SmartDetectorAlertRules | `microsoft.alertsmanagement/smartdetectoralertrules` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.AlertsManagement/smartDetectorAlertRules/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftalertsmanagement` |
| SubscriptionDiagnosticSettings | `AZSC/Subscription/SecurityPolicySweep` | `Get-ScoutSubscriptionSecurityPolicySweep` — `Get-AzDiagnosticSetting` | B | `Microsoft.Insights/diagnosticSettings/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftinsights` |
| Workspaces | `microsoft.operationalinsights/workspaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.OperationalInsights/workspaces/read` | Azure RBAC **Reader** | Doc | `permissions/monitor#microsoftoperationalinsights` |

#### Networking (21)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| ApplicationGateways | `microsoft.network/applicationgateways` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/applicationGateways/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| AzureFirewall | `microsoft.network/azurefirewalls` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/azureFirewalls/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| BastionHosts | `microsoft.network/bastionhosts` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/bastionHosts/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| Connections | `microsoft.network/connections` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/connections/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| ExpressRoute | `microsoft.network/expressroutecircuits` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/expressRouteCircuits/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| Frontdoor | `microsoft.network/frontdoors` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/frontDoors/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| LoadBalancer | `microsoft.network/loadbalancers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/loadBalancers/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| NATGateway | `microsoft.network/natgateways` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/natGateways/read` | Azure RBAC **Reader** | Doc | **NOT FOUND** ⚠️ `permissions/networking#microsoftnetwork` lists only `natGateways/join/action` and the diagnostic-settings sub-paths — no `natGateways/read`. The type exists; the action is undocumented. `*/read` almost certainly still covers it. |
| NetworkInterface | `microsoft.network/networkinterfaces` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/networkInterfaces/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| NetworkSecurityGroup | `microsoft.network/networksecuritygroups` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/networkSecurityGroups/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| NetworkWatchers | `microsoft.network/networkwatchers` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/networkWatchers/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| PrivateDNS | `microsoft.network/privatednszones` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/privateDnsZones/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| PrivateEndpoint | `microsoft.network/privateendpoints` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/privateEndpoints/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| PublicDNS | `microsoft.network/dnszones` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/dnsZones/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| PublicIP | `microsoft.network/publicipaddresses` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/publicIPAddresses/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| RouteTables | `microsoft.network/routetables` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/routeTables/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| TrafficManager | `microsoft.network/trafficmanagerprofiles` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/trafficManagerProfiles/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| VirtualNetwork | `microsoft.network/virtualnetworks` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/virtualNetworks/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| VirtualNetworkGateways | `microsoft.network/virtualnetworkgateways` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/virtualNetworkGateways/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| VirtualWAN | `microsoft.network/virtualwans` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/virtualWans/read` | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |
| vNETPeering | `microsoft.network/virtualnetworks` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Network/virtualNetworks/read` (peerings are inline properties) | Azure RBAC **Reader** | Doc | `permissions/networking#microsoftnetwork` |

#### Security (5)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| DefenderAlerts | `AZSC/Subscription/SecurityPolicySweep` | `Get-ScoutSubscriptionSecurityPolicySweep` — `Get-AzSecurityAlert` | B | `Microsoft.Security/alerts/read` | Azure RBAC **Reader** (Azure RBAC *Security Reader* is redundant) | Doc | `permissions/security#microsoftsecurity` |
| DefenderAssessments | `AZSC/Subscription/SecurityPolicySweep` | `Get-ScoutSubscriptionSecurityPolicySweep` — `Get-AzSecurityAssessment`; also ARG `securityresources` | B / A | `Microsoft.Security/assessments/read` | Azure RBAC **Reader** | Doc | `permissions/security#microsoftsecurity` |
| DefenderPricing | `AZSC/Subscription/SecurityPolicySweep` | `Get-ScoutSubscriptionSecurityPolicySweep` — `Get-AzSecurityPricing` | B | `Microsoft.Security/pricings/read` | Azure RBAC **Reader** | Doc | `permissions/security#microsoftsecurity` |
| DefenderSecureScore | `AZSC/Subscription/SecurityPolicySweep` | `Get-ScoutSubscriptionSecurityPolicySweep` — `Get-AzSecuritySecureScore`, `Get-AzSecuritySecureScoreControl` | B | `Microsoft.Security/secureScores/read`, `/secureScoreControls/read` | Azure RBAC **Reader** | Doc | `permissions/security#microsoftsecurity` |
| Vault | `microsoft.keyvault/vaults` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.KeyVault/vaults/read` | Azure RBAC **Reader** | Doc — **control plane only.** Vault metadata, network ACLs, RBAC/access-policy mode, soft-delete and purge-protection flags. **No secret, key, or certificate value is read.** | `permissions/security#microsoftkeyvault` |

#### Storage (2) · Web (2)

| Collector | Resource type(s) collected | Producer (src/collect fn) | Access class | Minimum permission | Role required | Verified | Source |
|---|---|---|---|---|---|---|---|
| NetApp | `Microsoft.NetApp/netAppAccounts/capacityPools/volumes` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.NetApp/netAppAccounts/capacityPools/volumes/read` | Azure RBAC **Reader** | Doc | `permissions/storage#microsoftnetapp` |
| **StorageAccounts** | `microsoft.storage/storageaccounts` **+** `AZSC/Operational/StorageAccount` | `Get-ScoutRawInventory` **+** `Get-ScoutOperationalCollectorEnrichment` — `Get-AzStorageBlobServiceProperty`, `Get-AzStorageFileServiceProperty` | A + F | `Microsoft.Storage/storageAccounts/read`, `/blobServices/read`, `/fileServices/read` | Azure RBAC **Reader** | Doc — **control plane only.** Service *properties* (versioning, soft delete, CORS, retention). **No blob or file content, and no account keys, are read.** | `permissions/storage#microsoftstorage` |
| APPServicePlan | `microsoft.web/serverfarms` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Web/serverFarms/read` | Azure RBAC **Reader** | Doc | `permissions/web-and-mobile#microsoftweb` |
| APPServices | `microsoft.web/sites` | `Get-ScoutRawInventory` (ARG `resources`) | A | `Microsoft.Web/sites/read` | Azure RBAC **Reader** | Doc | `permissions/web-and-mobile#microsoftweb` |

---

### Table B — Entra / Identity collectors (15)

All produced by `src/collect/Start-ScoutEntraExtraction.ps1`, all against `/v1.0` (no `/beta`). Each query is individually wrapped in try/catch that prints `[SKIP]` and continues — **a denied permission produces an empty worksheet, never an error.**

**Two identity models, and they use different permission systems:**

- **Running as a user** (the normal case — the Graph token comes from `az account get-access-token`, so an interactive `az login` is required *in addition to* `Connect-AzAccount`): effective rights come from the user's **Entra directory role**, not from consented app roles. Use the "Entra role that grants it" column.
- **Running as a service principal**: an app-only token, requiring the **Graph application permissions** in the third column, each with admin consent.

**The `Entra role` answer is two roles, not one.** `Global Reader` works but Microsoft classifies it as a **privileged** role — the read-only counterpart to Global Administrator, spanning all of Microsoft 365. The lower-privilege pairing is **`Directory Readers`** (not privileged) for 11 collectors, plus **Entra `Security Reader`** (privileged, but scoped to security/ID Protection/Conditional Access) for the remaining 4.

**Conditional Access boundary — RESOLVED.** `Directory Readers` does **not** include `microsoft.directory/conditionalAccessPolicies/standard/read`. Microsoft's least-privilege-by-task table names **Entra `Security Reader`** as the least privileged role for "Read all configuration" and "Read named locations" under Conditional Access, and the Security Reader role definition lists `conditionalAccessPolicies/standard/read` explicitly. So **two roles are needed**, not one. Sources: [Least privileged roles by task — Conditional Access](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-by-task#security---conditional-access-least-privileged-roles), [Built-in roles — Security Reader](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#security-reader), [Built-in roles — Directory Readers](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#directory-readers).

| Collector | Graph endpoint | Graph permission | Entra role that grants it | Privileged? | Verified | Source |
|---|---|---|---|---|---|---|
| Users | `/v1.0/users` | `User.Read.All` | Entra **Directory Readers** (`microsoft.directory/users/standard/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| Groups | `/v1.0/groups` | `Group.Read.All` | Entra **Directory Readers** (`groups/standard/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| AppRegistrations | `/v1.0/applications` | `Application.Read.All` | Entra **Directory Readers** (`applications/standard/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| ServicePrincipals | `/v1.0/servicePrincipals` | `Application.Read.All` | Entra **Directory Readers** (`servicePrincipals/standard/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| ManagedIdentities | `/v1.0/servicePrincipals?$filter=servicePrincipalType eq 'ManagedIdentity'` | `Application.Read.All` | Entra **Directory Readers** (same action) | No | Doc | `entra/permissions-reference#directory-readers` |
| DirectoryRoles | `/v1.0/directoryRoles` | `RoleManagement.Read.Directory` | Entra **Directory Readers** (`directoryRoles/standard/read`, `/members/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| PIMAssignments | `/v1.0/roleManagement/directory/roleAssignments?$expand=principal,roleDefinition` | `RoleManagement.Read.Directory` | Entra **Directory Readers** (`roleAssignments/standard/read`, `roleDefinitions/standard/read`) | No | Doc for the directory-role path; **Untested** whether `$expand=principal` needs more | `entra/permissions-reference#directory-readers` |
| AdminUnits | `/v1.0/directory/administrativeUnits` | `AdministrativeUnit.Read.All` | Entra **Directory Readers** (`administrativeUnits/standard/read`, `/members/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| Domains | `/v1.0/domains` | `Domain.Read.All` | Entra **Directory Readers** (`domains/standard/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| Licensing | `/v1.0/subscribedSkus` | `Organization.Read.All` | Entra **Directory Readers** (`subscribedSkus/standard/read`) | No | Doc | `entra/permissions-reference#directory-readers` |
| **ConditionalAccess** | `/v1.0/identity/conditionalAccess/policies` | `Policy.Read.All` (or least-privileged `Policy.Read.ConditionalAccess`) | Entra **Security Reader** (`conditionalAccessPolicies/standard/read`) — **Directory Readers is NOT enough** | **Yes** | Doc | `entra/permissions-reference#security-reader` |
| **NamedLocations** | `/v1.0/identity/conditionalAccess/namedLocations` | `Policy.Read.All` | Entra **Security Reader** ("Read named locations", least privileged) | **Yes** | Doc | `entra/permissions-reference#security-reader` |
| **SecurityPolicies** | `/v1.0/policies/authorizationPolicy` | `Policy.Read.All` | Entra **Security Reader** (`authorizationPolicy/standard/read`) | **Yes** | Doc | `entra/permissions-reference#security-reader` |
| **RiskyUsers** | `/v1.0/identityProtection/riskyUsers` | `IdentityRiskyUser.Read.All` | Entra **Security Reader** (`identityProtection/allProperties/read`) | **Yes** | Doc — **also requires an Entra ID P2 licence.** A P1 tenant with the permission granted still returns nothing. | `entra/permissions-reference#security-reader` |
| **CrossTenantAccess** | `/v1.0/policies/crossTenantAccessPolicy/partners` | `Policy.Read.All` | Entra **Security Reader** covers cross-tenant policy *templates*; whether it covers the `partners` collection is **not stated in the role definition** | **Yes** (if Security Reader) | **Unverified** — falls back to **Global Reader** if Security Reader is insufficient | **NOT FOUND** — `entra/permissions-reference#security-reader` lists only `crossTenantAccessPolicy/partners/templates/.../standard/read`; there is **no** action for the `partners` collection itself in any role definition |

**Two Graph queries are issued that no collector consumes** — `/v1.0/identity/identityProviders` (`IdentityProvider.Read.All`) and `/v1.0/policies/identitySecurityDefaultsEnforcementPolicy`. Their output is discarded. `AuditLog.Read.All` is checked by the pre-flight but `/v1.0/auditLogs/signIns` is never called; it can be dropped from the ask entirely.

---

### Table C — Azure DevOps collectors (5)

**Azure DevOps is a fourth, entirely separate permission system.** These are DevOps security-group permissions — not Azure RBAC, not Entra directory roles. An identity with Owner on every Azure subscription and Global Administrator in Entra still gets zero rows here without DevOps org membership.

Auth: `Get-AzAccessToken -ResourceUrl '499b84ac-1321-427f-aa17-267ca6975798'` (the Azure DevOps first-party app) at `Start-ScoutDevOpsExtraction.ps1:83`, or a PAT via `-DevOpsPat`. Org discovery is `app.vssps.visualstudio.com/_apis/profile/profiles/me` then `/_apis/accounts?memberId=`.

| Collector | ADO API | Minimum ADO access | Verified | Source |
|---|---|---|---|---|
| DevOpsProjects | `GET https://dev.azure.com/{org}/_apis/projects?api-version=7.0` | Org member + project-level **View project-level information** | Untested | `devops/organizations/security/permissions#project-level-permissions` — *"To access project-level resources, the View project-level information permission must be set to Allow. This permission gates all other project-level permissions."* |
| DevOpsPipelines | `GET .../{org}/{project}/_apis/pipelines?api-version=7.0` | Project **View build pipeline** | Untested | `devops/organizations/security/permissions#pipeline-or-build-object-level` (`Build, ViewBuildDefinition`); role matrix at `devops/pipelines/policies/permissions#set-pipeline-permissions-in-azure-pipelines` shows **Readers** have *View build pipeline* |
| DevOpsServiceConnections | `GET .../{org}/{project}/_apis/serviceendpoint/endpoints?api-version=7.0` | **Reader** on service connections (returns metadata only — no secrets) | Untested | `devops/pipelines/policies/permissions#set-service-connection-security-in-azure-pipelines` — *"Reader: Can view service connections."* |
| DevOpsRepositories | `GET .../{org}/{project}/_apis/git/repositories?api-version=7.0` | **Read** on Git repositories | Untested | `devops/repos/git/set-git-repository-permissions#default-repository-permissions` — **Read** (clone, fetch, explore) is granted to the **Readers** group |
| DevOpsAgentPools | `GET .../{org}/_apis/distributedtask/pools?api-version=7.0` | Org-level **Reader** on agent pools | Untested | `devops/organizations/security/about-security-roles#agent-pool-security-roles,-project-level` — *"Reader: View the pool."* ⚠️ Documented as a **project-level** role; Scout calls the **org-level** `/_apis/distributedtask/pools` endpoint, so the org-level equivalent at `devops/pipelines/policies/permissions#set-agent-pool-security-in-azure-pipelines` (roles **Reader**, Service Account, Administrator) is the applicable one |

Also required, and easy to miss: the org's **"Third-party application access via OAuth"** policy must permit the token, and if the identity is a service principal it must be added to the DevOps org. Nothing in Scout's pre-flight validates any of this.

---

### Table D — Assessments

`manifests/assessments.psd1` declares **22 entries, but they are not 22 distinct things.** 15 are per-category slices of the same collect-and-score pipeline, 4 more are narrower sub-bundles of two of those, and `Governance` and `Policy` are byte-for-byte duplicates of each other (same Category, Collect, Ingest, Rules, Frameworks, Reporters — only `Tags` differ). The real shape is: 2 roll-ups, 15 category slices, 4 sub-bundles, 1 cost pull.

**No assessment needs a permission that its underlying collectors do not already need.** An assessment is rule evaluation over already-collected data.

| Assessment | Data it needs | Minimum permission set |
|---|---|---|
| **LandingZone** *(roll-up)* | Every category (`Collect = '*'`), all `caf.*` + `waf.*` rules | Azure RBAC **Reader** at root MG. Add Entra **Directory Readers** + Entra **Security Reader** for the Identity slice. |
| **Estate** *(roll-up)* | Every category, no scoring | Azure RBAC **Reader** at root MG |
| Management *(slice)* | Management collectors + Governance/ArgQueryPack/AdvisorScores ingest | Azure RBAC **Reader** — at **MG scope** for management-group and custom-role data |
| Monitor *(slice)* | Monitor collectors | Azure RBAC **Reader** |
| Networking *(slice)* | Networking collectors | Azure RBAC **Reader** |
| **Identity** *(slice)* | Identity **and** Security collectors — 15 Graph + 1 ARM | Azure RBAC **Reader** **+** Entra **Directory Readers** **+** Entra **Security Reader** (for Conditional Access, Named Locations, authorization policy, Risky Users) **+ Entra ID P2** for Risky Users |
| Security *(slice)* | Security collectors (Defender, Key Vault) | Azure RBAC **Reader** — control plane only; no Key Vault data-plane access |
| Compute *(slice)* | Compute collectors incl. VM enrichment | Azure RBAC **Reader** |
| Storage *(slice)* | Storage collectors | Azure RBAC **Reader** — no blob data-plane access |
| Databases *(slice)* | Databases collectors | Azure RBAC **Reader** |
| Containers *(slice)* | Containers collectors | Azure RBAC **Reader** |
| Web *(slice)* | Web collectors | Azure RBAC **Reader** |
| Analytics *(slice)* | Analytics collectors | Azure RBAC **Reader** |
| AI *(slice)* | AI collectors | Azure RBAC **Reader** |
| Integration *(slice)* | Integration collectors | Azure RBAC **Reader** |
| Hybrid *(slice)* | Hybrid collectors | Azure RBAC **Reader** |
| IoT *(slice)* | IoT collectors | Azure RBAC **Reader** |
| Governance *(sub-bundle of Management)* | Management collect + Governance ingest, `caf.governance` rules | Azure RBAC **Reader** at MG scope |
| **Policy** *(sub-bundle)* | **Identical to `Governance` in every field except `Tags`** | Azure RBAC **Reader** at MG scope — same as Governance |
| UpdateManager *(sub-bundle of Management)* | Management collect + ArgQueryPack; patch data from ARG `patchassessmentresources` / `patchinstallationresources` | Azure RBAC **Reader** — read-only since the `assessPatches` POST was removed |
| Monitoring *(sub-bundle of Monitor)* | Monitor collect, diagnostic-settings coverage | Azure RBAC **Reader** |
| **Cost** | Cost + Compute + Storage collect; `POST Microsoft.CostManagement/query` | Azure RBAC **Reader** **+ the EA/MCA billing setting below** (which is not a role) |

---

### Notes, exceptions, and things that are not roles

#### 1. No collector requires data-plane access — and Reader grants none

Azure RBAC `Reader` has `DataActions: []`. It grants **zero** data-plane access. That would be a hard blocker if any collector needed it. **None does — this was checked and is a clean result.**

- **Key Vault (`Security/Vault`)**: reads `microsoft.keyvault/vaults` from ARG only. No `Get-AzKeyVaultSecret` / `-Key` / `-Certificate` call exists anywhere in `src/`. Secret *names* are not read, let alone values.
- **Storage (`Storage/StorageAccounts`)**: `Get-AzStorageBlobServiceProperty` / `Get-AzStorageFileServiceProperty` are **control-plane** calls (`Microsoft.Storage/storageAccounts/blobServices/read`). No blob is enumerated or downloaded; no account key is listed (`listKeys` appears nowhere in `src/`).
- **DevOps service connections**: the REST endpoint returns connection metadata; secrets are never returned by that API.

**The one data-plane exception is an output feature, not a collector.** `-StorageAccount` calls `New-AzStorageContext -UseConnectedAccount` (`src/Invoke-AzureScout.ps1:705`) and then `Set-AzStorageBlobContent` (`:1055, :1061, :1067, :1080`) to upload the finished report. That is a data-plane **write** and needs **Storage Blob Data Contributor** on the destination container — a role Scout needs only if you ask it to publish its own output, and only on the one account you name.

#### 2. The EA/MCA billing gate — no role satisfies it

Cost data can be empty with a correct role assignment. Beyond RBAC, the billing account must permit subscription-scoped users to see cost:

- **EA**: the enrollment setting **"AO view charges"** (and **"DA view charges"**) must be enabled by the Enterprise Administrator.
- **MCA**: **"Allow Azure subscription users to view and optimize costs"** must be enabled at the billing profile.

With these off, `Microsoft.CostManagement/query` returns empty or 403 for a subscription-scoped principal **regardless of Reader, Cost Management Reader, or Cost Management Contributor**. This is not an RBAC role and cannot be granted with `New-AzRoleAssignment`; it must be changed by a billing administrator in the EA portal or Cost Management + Billing blade. Source: [Assign access to Cost Management data](https://learn.microsoft.com/azure/cost-management-billing/costs/assign-access-acm-data). Affects the **Cost** assessment, the `VirtualMachine` and `ARCServers` EstimatedCost fields, and `ReservationRecom`.

#### 3. Collectors with no meaningful permission answer — 12 provably broken

AB#6444 traced these to defects in code. They emit zero rows **in every tenant, on every run, at any permission level.** Granting more access does not change the output; they will *present* as a permission failure and are not one.

| Collector | Why it is broken |
|---|---|
| Databases/**POSTGRE** | Emits zero rows on every run (AB#6444 §4) |
| Hybrid/**ArcSites** | Emits zero rows on every run |
| Hybrid/**VirtualMachines** | Emits zero rows on every run |
| Management/**CustomRoleDefinitions** | Consumes `AZSC/Management/RoleDefinition`, produced only by `Get-ScoutTenantWideResource`, which is gated at `Get-ScoutRawInventory.ps1:594` on `-IncludeTenantWideResources` |
| Management/**ManagementGroups** | Same gate — `AZSC/Management/ManagementGroup` |
| Management/**PolicyDefinitions** | Same gate — `AZSC/Management/PolicyDefinition` |
| Management/**PolicySetDefinitions** | Same gate — `AZSC/Management/PolicySetDefinition` |
| Management/**LighthouseDelegations** | Emits zero rows on every run |
| Monitor/**Outages** | `Get-ScoutOutageResource` runs before the API merge, so it never sees the ResourceHealth events |
| Monitor/**ResourceDiagnosticSettings** | Emits zero rows on every run |
| Monitor/**AppInsightsContinuousExport** | No producer — Azure retired the endpoint. Permanently empty by design. |
| Monitor/**AppInsightsWorkItems** | No producer — endpoint retired. Permanently empty by design. |

**The `-IncludeTenantWideResources` switch has no production caller.** The string appears in exactly four places in the repo: the doc comment, the parameter declaration, the `if`, and one Pester test. Neither `Start-ScoutGraphExtraction.ps1:69-82` nor `Invoke-Collect.ps1:707` sets it. There is no operator flag that turns these four collectors on.

#### 4. Management groups — scope, and an unresolved question

Azure RBAC `Reader` must be assigned **at management-group scope**, not per-subscription, for management-group and cross-subscription hierarchy data to resolve. Subscription-scoped Reader silently returns an empty or flattened hierarchy — no error.

**Whether Reader at root MG alone is sufficient, or whether `Management Group Reader` is genuinely additional, is UNRESOLVED.** Repo history records that `ManagementGroups` returned no rows until Management Group Reader was granted, and that *both* parameter binding and permissions were implicated. That question is now confounded by defect #3 above: the collector's producer has never run in production, so no observation of it can distinguish "wrong permission" from "code path never executed". **Fix the switch first, then re-test the permission.** Do not grant Management Group Reader on the strength of this table alone.

Affected: `ManagementGroups`, `CustomRoleDefinitions`, `AllSubscriptions` (mgChain), and the `Management` / `Governance` / `Policy` assessments.

#### 5. Roles you should NOT grant

| Role | System | Why not |
|---|---|---|
| **Security Reader** | **Azure RBAC** | Every read it grants is inside Reader's `*/read`. Its only non-read actions are IoT Defender package downloads, which Scout never calls. Adds nothing. *(The Entra role of the same name IS needed — see Table B.)* |
| **Monitoring Reader** | Azure RBAC | Redundant against `*/read`, and grants `Microsoft.Support/*`, which includes support-ticket **creation**. Scout only reads `Microsoft.Support/supportTickets`. |
| **Cost Management Reader** | Azure RBAC | Redundant — `Microsoft.CostManagement/query/read` is inside `*/read`, and Microsoft's role-behaviour table shows Reader as "Read only" on the Query and Cost Details APIs. It also carries `Microsoft.Support/*`. The real cost blocker is the billing setting in note 2, which this role does not fix. |
| **Global Reader** | Entra | Works, but Microsoft classifies it as **privileged** — the read-only counterpart to Global Administrator across all of Microsoft 365. `Directory Readers` + Entra `Security Reader` covers the same 15 collectors with a narrower blast radius. Keep Global Reader only as the fallback for `CrossTenantAccess` (Table B, Unverified row). |
| **Virtual Machine Contributor** | Azure RBAC | Was previously needed for `assessPatches`. **No longer required** — patch data now comes from read-only ARG tables. Do not grant it. |

---

### Table E — The complete grant list

What a customer actually has to grant, by system.

#### (a) Inventory only — the default run

| System | Grant | Scope | Assignments |
|---|---|---|---|
| **Azure RBAC** | `Reader` | `/providers/Microsoft.Management/managementGroups/<tenant-root-mg-id>` | **1** |

**One role, one assignment.** Covers all 154 ARM collectors — every service inventory, all Defender data, policy compliance, Advisor, Monitor, patch assessment, storage and VM enrichment, quotas and SKUs. Nothing else, from any system.

```powershell
New-AzRoleAssignment -ObjectId <principalId> -RoleDefinitionName 'Reader' `
  -Scope '/providers/Microsoft.Management/managementGroups/<tenantRootId>'
```

Root-MG scope, not per-subscription, is what makes management-group hierarchy and cross-subscription rollups resolve.

#### (b) Inventory + assessment (CAF/WAF, no Entra, no DevOps)

| System | Grant | Scope | Assignments |
|---|---|---|---|
| **Azure RBAC** | `Reader` | root management group | **1** |

**Identical to (a).** The CAF/WAF rule engine scores data Scout has already collected; it issues no additional Azure calls. Every assessment in Table D except `Identity` and `Cost` runs on Reader alone.

For the **Cost** assessment, add a **non-role** prerequisite: EA **"AO view charges"** enabled, or MCA **"Allow Azure subscription users to view and optimize costs"** enabled. See note 2. There is no role that substitutes for this.

#### (c) Everything — including Entra and DevOps

| System | Grant | Scope | Privileged? | Notes |
|---|---|---|---|---|
| **Azure RBAC** | `Reader` | root management group | No | All 154 ARM collectors |
| **Entra directory role** | `Directory Readers` | tenant | No | 11 of the 15 Graph collectors: Users, Groups, AppRegistrations, ServicePrincipals, ManagedIdentities, DirectoryRoles, PIMAssignments, AdminUnits, Domains, Licensing |
| **Entra directory role** | `Security Reader` ⚠️ *Entra, not Azure RBAC* | tenant | **Yes** | ConditionalAccess, NamedLocations, SecurityPolicies, RiskyUsers. Substitute `Global Reader` only if `CrossTenantAccess` proves to need it. |
| **Azure DevOps** | Org membership + project-level read: View project-level information, View build pipeline, Reader on service connections, Read on Git repos, Reader on agent pools | per org / per project | n/a | The 5 DevOps collectors. Also needs the org's third-party-OAuth policy to permit the token. |
| *(if using `-StorageAccount`)* **Azure RBAC** | `Storage Blob Data Contributor` | the one destination storage account | No | Data-plane **write**, for uploading the finished report. Output only — no collector needs it. |

**Non-role prerequisites for (c):**

| Prerequisite | Needed for | Who grants it |
|---|---|---|
| EA **"AO view charges"** / MCA **"Allow Azure subscription users to view and optimize costs"** | all cost data | Billing administrator / Enterprise Administrator |
| **Entra ID P2 licence** | `RiskyUsers` only | Tenant licensing |
| **Azure CLI logged in** (`az login`) *in addition to* `Connect-AzAccount` | all 15 Graph collectors — `Get-AZSCGraphToken` shells to `az account get-access-token` | The operator, at run time |
| DevOps org **third-party application access via OAuth** enabled | the 5 DevOps collectors | DevOps org administrator |

**For a service principal instead of a user**, replace the two Entra directory roles with these admin-consented Microsoft Graph **application** permissions: `User.Read.All`, `Group.Read.All`, `Application.Read.All`, `RoleManagement.Read.Directory`, `AdministrativeUnit.Read.All`, `Domain.Read.All`, `Organization.Read.All`, `Policy.Read.All`, `IdentityRiskyUser.Read.All`. `AuditLog.Read.All` and `IdentityProvider.Read.All` are checked or queried but consumed by no collector — do not request them.

#### Summary count

| Capability | Azure RBAC roles | Entra roles | Graph app permissions (SP only) | DevOps | Non-role prerequisites |
|---|---|---|---|---|---|
| Inventory only | **1** (`Reader`) | 0 | 0 | 0 | 0 |
| + assessment | **1** (`Reader`) | 0 | 0 | 0 | 1 (billing, for Cost only) |
| + Entra | 1 | **2** (`Directory Readers`, `Security Reader`) | 9 | 0 | 2 (P2 for RiskyUsers, `az login`) |
| + DevOps | 1 | 2 | 9 | **org + 5 project/org reads** | 3 (+ OAuth policy) |
| + report upload | 2 (`+ Storage Blob Data Contributor`) | 2 | 9 | org + 5 | 3 |

---

## 4. Category coverage — Microsoft's services vs Scout's

### 1. General

**Scout has no category for General. Scout collects 1 of 8 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Marketplace add-ons / support plans | Microsoft.Addons | ❌ | — | P3? |
| Reservations and capacity | Microsoft.Capacity | ❌ | — | P2? |
| Commerce usage aggregates | Microsoft.Commerce | ❌ | — | P3? |
| Azure Marketplace | Microsoft.Marketplace | ❌ | — | P3? |
| Marketplace ordering / agreements | Microsoft.MarketplaceOrdering | ❌ | — | P3? |
| Azure Quotas | Microsoft.Quota | ❌ | — | P2? |
| Subscriptions | Microsoft.Subscription | ❌ | — | P3? |
| Azure Support | Microsoft.Support | ✅ | Management/SupportTickets | — |

> Note: `Management/AllSubscriptions` looks like subscription coverage but declares the synthetic type `AZSC/Management/SubscriptionEnrichment`, not `Microsoft.Subscription` — it enriches subscription metadata rather than reading the provider. `Microsoft.Capacity` is the reservation *purchase* surface; Scout's `Management/ReservationRecom` reads `Microsoft.Consumption/reservationRecommendations` instead, which is recommendations only, not what is actually owned.

### 2. Compute

**Scout collects 4 of 12 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Container Apps | microsoft.app | ✅ | Containers/ContainerApp, Containers/ContainerAppEnv | — |
| Azure Spring Apps | Microsoft.AppPlatform | ❌ | — | P2 |
| Azure VMware Solution | Microsoft.AVS | ✅ | Compute/VMWare | — |
| Azure Compute Fleet | Microsoft.AzureFleet | ❌ | — | P3? |
| Azure Batch | Microsoft.Batch | ❌ | — | P1 |
| Virtual Machines / Scale Sets | Microsoft.Compute | ✅ | Compute/VirtualMachine, Compute/VirtualMachineScaleSet, Compute/VMDisk +2 more | — |
| Compute limits | Microsoft.ComputeLimit | ❌ | — | P3? |
| Compute scheduling | Microsoft.ComputeSchedule | ❌ | — | P3? |
| Azure Arc-enabled VMware vSphere | microsoft.connectedvmwarevsphere | ❌ | — | P2? |
| Azure Virtual Desktop | Microsoft.DesktopVirtualization | ✅ | Compute/AVD, Compute/AVDSessionHosts, Compute/AVDWorkspaces +2 more | — |
| Azure Quantum | Microsoft.Quantum | ❌ | — | P3 |
| Service Fabric | Microsoft.ServiceFabric | ❌ | — | P2 |

> Note: `microsoft.app` (Container Apps) is a **Compute** provider in Microsoft's taxonomy but sits under Scout's `Containers/` folder — a defensible split, but it means Scout's Compute category is thinner than its manifest count suggests. `Microsoft.Compute` coverage is VM/VMSS/disk/availability-set only: galleries, images, snapshots, disk encryption sets, dedicated hosts, PPGs and capacity reservations are all uncollected (P2). Scout additionally collects `microsoft.classiccompute/domainnames` (`Compute/CloudServices`), a provider Microsoft no longer lists in this directory. Seven of Scout's 14 Compute manifests are AVD.

### 3. Networking

**Scout collects 1 of 2 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Content Delivery Network / Front Door Std+Premium | Microsoft.Cdn | ❌ | — | P1 |
| Virtual Network, Load Balancer, Firewall, ExpressRoute, DNS, Bastion, VPN, … | Microsoft.Network | ✅ | Networking/VirtualNetwork, Networking/NetworkSecurityGroup, Networking/LoadBalancer +18 more | — |

> Note: 50% provider coverage badly overstates the position, because Microsoft folds ~20 distinct services into `Microsoft.Network`. Scout covers 20 types under it but misses firewall policies (P1 — the report template already prints "Not collected"), WAF policies (P1), Virtual WAN children (hubs/gateways, P2), DDoS plans, Virtual Network Manager, Private Link services, ASGs and flow logs (all P2). **Retirement flag:** Scout's only Front Door coverage is `microsoft.network/frontdoors` — Front Door **classic, retiring 2027-03-31**. Every modern AFD deployment (`Microsoft.Cdn/profiles`) is invisible.

### 4. Storage

**Scout collects 2 of 6 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Data Share | Microsoft.DataShare | ❌ | — | P3 |
| Azure Elastic SAN | Microsoft.ElasticSan | ❌ | — | P2 |
| Azure NetApp Files | Microsoft.NetApp | ✅ | Storage/NetApp | — |
| Azure Storage | Microsoft.Storage | ✅ | Storage/StorageAccounts | — |
| Azure HPC Cache / Managed Lustre | Microsoft.StorageCache | ❌ | — | P2 |
| Azure File Sync | Microsoft.StorageSync | ❌ | — | P1 |

> Note: the thinnest category in Scout relative to real-world estate size. `Storage/NetApp` collects only `Microsoft.NetApp/netAppAccounts/capacityPools/volumes` — accounts and pools are not their own rows, so pool utilisation is invisible (P2). Under `Microsoft.Storage` only the account is read: blob containers and their public-access level, file shares, and lifecycle management policies are all uncollected (P1 each). Managed disks are collected but filed under `Compute/VMDisk`; AB6446 flags reclassifying them here as a judgement call.

### 5. Web and Mobile

**Scout collects 1 of 5 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| App Service Certificates | Microsoft.CertificateRegistration | ❌ | — | P2 |
| App Service domains | Microsoft.DomainRegistration | ❌ | — | P3 |
| Azure Maps | Microsoft.Maps | ❌ | — | P3 |
| Azure SignalR Service / Web PubSub | Microsoft.SignalRService | ❌ | — | P2 |
| App Service / Azure Functions | microsoft.web | ✅ | Web/APPServices, Web/APPServicePlan | — |

> Note: Function Apps and Logic Apps (Standard) **are** collected — they are `microsoft.web/sites` rows distinguished by `kind` — but there is no Function-App-specific projection (no runtime stack, no plan tier, no always-on). Missing under `microsoft.web` itself: App Service Environments, Static Web Apps and deployment slots (P1 each). App Configuration (`Microsoft.AppConfiguration`, P1) is a Web-adjacent gap that Microsoft files under Integration.

### 6. Containers

**Scout collects 4 of 4 providers in this category — the only category at 100%.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Container Instances | Microsoft.ContainerInstance | ✅ | Containers/ContainerGroups | — |
| Container Registry | Microsoft.ContainerRegistry | ✅ | Containers/ContainerRegistries | — |
| Azure Kubernetes Service | Microsoft.ContainerService | ✅ | Containers/AKS | — |
| Azure Red Hat OpenShift | Microsoft.RedHatOpenShift | ✅ | Containers/ARO | — |

> Note: provider coverage is complete but type coverage is not — AKS node pools (`.../managedClusters/agentPools`, P1), Container Apps jobs (`Microsoft.App/jobs`, P2) and AKS Fleet Manager (`.../fleets`, P2) are missing. Scout also files `microsoft.app` (Microsoft's Compute category) and Arc-enabled Kubernetes (`Microsoft.Kubernetes`, Microsoft's Hybrid category) elsewhere.

### 7. Databases

**Scout collects 7 of 8 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Cache for Redis / Managed Redis | Microsoft.Cache | ✅ | Databases/RedisCache | — |
| Azure Database for MariaDB | Microsoft.DBforMariaDB | ✅ | Databases/MariaDB | — |
| Azure Database for MySQL | Microsoft.DBforMySQL | ✅ | Databases/MySQL, Databases/MySQLflexible | — |
| Azure Database for PostgreSQL | Microsoft.DBforPostgreSQL | ✅ | Databases/POSTGRE, Databases/POSTGREFlexible | — |
| Azure Cosmos DB | Microsoft.DocumentDB | ✅ | Databases/CosmosDB | — |
| Inference Service | Microsoft.InferenceService | ❌ | — | P3? |
| Azure SQL Database / Managed Instance | Microsoft.Sql | ✅ | Databases/SQLSERVER, Databases/SQLDB, Databases/SQLMI +2 more | — |
| SQL Server on Azure VMs | Microsoft.SqlVirtualMachine | ✅ | Databases/SQLVM | — |

> Note: the strongest category after Containers. **Retirement flags:** `microsoft.cache/redisenterprise` (collected by `Databases/RedisCache` alongside `microsoft.cache/redis`) covers Enterprise/Enterprise Flash tiers, which **retire 2027-03-31** in favour of Azure Managed Redis — AB6446 recommends a retirement flag rather than a new collector. Azure Database for MariaDB is likewise end-of-life; `Databases/MariaDB` should be treated as a migration finding. Missing types: SQL failover groups, Cosmos DB for PostgreSQL and Mongo vCore (P2 each).

### 8. Analytics

**Scout collects 4 of 11 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Analysis Services | Microsoft.AnalysisServices | ❌ | — | P2 |
| Azure Databricks | Microsoft.Databricks | ✅ | Analytics/Databricks | — |
| Data Factory | Microsoft.DataFactory | ❌ | — | P1 |
| Data Lake Analytics | Microsoft.DataLakeAnalytics | ❌ | — | P3 |
| Azure Data Lake Storage Gen1 | Microsoft.DataLakeStore | ❌ | — | P3 |
| Microsoft Fabric | Microsoft.Fabric | ❌ | — | P1 |
| HDInsight | Microsoft.HDInsight | ❌ | — | P2 |
| Azure Data Explorer | Microsoft.Kusto | ✅ | Analytics/DataExplorerCluster | — |
| Power BI Embedded | Microsoft.PowerBIDedicated | ❌ | — | P2 |
| Microsoft Purview | Microsoft.Purview | ✅ | Analytics/Purview | — |
| Azure Synapse Analytics | Microsoft.Synapse | ✅ | Analytics/Synapse | — |

> Note: Scout's `Analytics/` folder also holds two collectors Microsoft classifies elsewhere — `Analytics/EvtHub` (`Microsoft.EventHub` → Integration; AB6446 recommends moving it) and `Analytics/Streamanalytics` (`Microsoft.StreamAnalytics` → Internet of Things). **Retirement flags:** Data Lake Storage/Analytics Gen1 retired 2024-02. Data Factory and Fabric are the two largest omissions in the data estate.

### 9. AI + machine learning

**Scout collects 4 of 6 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Bot Service | Microsoft.BotService | ✅ | AI/BotServices | — |
| Azure AI services (Cognitive Services) | Microsoft.CognitiveServices | ✅ | AI/AzureAI, AI/OpenAIAccounts, AI/ComputerVision +11 more | — |
| Azure AI Health Bot | Microsoft.HealthBot | ❌ | — | P3? |
| Azure Machine Learning | Microsoft.MachineLearningServices | ✅ | AI/MachineLearning, AI/AIFoundryHubs, AI/AIFoundryProjects | — |
| Azure AI Search | Microsoft.Search | ✅ | AI/SearchServices | — |
| Azure AI Video Indexer | Microsoft.VideoIndexer | ❌ | — | P3? |

> Note: AI's 27 manifests are the most misleading count in Scout. Fourteen of them are the *same* resource type — `microsoft.cognitiveservices/accounts` — split by `kind`, and three more share `microsoft.machinelearningservices/workspaces`. AI spans **four providers**, not 27 services. Eight further AI manifests are `AZSC/ARMChild/*` synthetic child collectors (ML models, datasets, endpoints, OpenAI deployments, search indexes) that read from an already-fetched parent rather than a provider of their own.

### 10. Internet of Things

**Scout collects 2 of 11 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Sphere | Microsoft.AzureSphere | ❌ | — | P3 |
| Device Registry | Microsoft.DeviceRegistry | ❌ | — | P2 |
| IoT Hub / Device Provisioning Service | Microsoft.Devices | ✅ | IoT/IOTHubs | — |
| Device Update for IoT Hub | Microsoft.DeviceUpdate | ❌ | — | P2 |
| Azure Digital Twins | Microsoft.DigitalTwins | ❌ | — | P2 |
| Azure Edge | Microsoft.Edge | ❌ | — | P3? |
| Edge Marketplace | Microsoft.EdgeMarketPlace | ❌ | — | P3? |
| IoT Central | Microsoft.IoTCentral | ❌ | — | P2 |
| Defender for IoT (firmware) | Microsoft.IoTFirmwareDefense | ❌ | — | P3? |
| IoT security | Microsoft.IoTSecurity | ❌ | — | P3? |
| Stream Analytics | Microsoft.StreamAnalytics | ✅ | Analytics/Streamanalytics | — |

> Note: Scout's own `IoT/` folder contains exactly **one** manifest — IoT Hub. The second ✅ in this table, Stream Analytics, lives under `Analytics/`, which is a defensible placement but means Microsoft's IoT category is served by a single Scout IoT collector. `Microsoft.Devices` is collected at the hub level only; Device Provisioning Service (`.../provisioningServices`) is a P1 gap — IoT Hub without DPS is half the story. Azure IoT Operations (`Microsoft.IoTOperations`, P2) is the strongest fit given Scout's Arc/Azure Local depth. **Retirement flag:** Time Series Insights retired 2025-07 (P3, do not build).

### 11. Integration

**Scout collects 3 of 15 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure API Center | Microsoft.ApiCenter | ❌ | — | P3? |
| API Management | Microsoft.ApiManagement | ✅ | Integration/APIM | — |
| Azure App Configuration | Microsoft.AppConfiguration | ❌ | — | P1 |
| Azure Communication Services | Microsoft.Communication | ❌ | — | P2 |
| Durable Functions / Durable Task | Microsoft.DurableTask | ❌ | — | P3? |
| Event Grid | Microsoft.EventGrid | ❌ | — | P1 |
| Event Hubs | Microsoft.EventHub | ✅ | Analytics/EvtHub | — |
| Azure API for FHIR | Microsoft.HealthcareApis | ❌ | — | P3 |
| Azure Health Data Services | Microsoft.HealthDataAIServices | ❌ | — | P3? |
| Logic Apps | Microsoft.Logic | ❌ | — | P1 |
| Notification Hubs | Microsoft.NotificationHubs | ❌ | — | P2 |
| Azure Relay | Microsoft.Relay | ❌ | — | P2 |
| Event Grid resource notifications | Microsoft.ResourceNotifications | ❌ | — | P3? |
| Service Bus | Microsoft.ServiceBus | ✅ | Integration/ServiceBUS | — |
| Services Hub | Microsoft.ServicesHub | ❌ | — | P3? |

> Note: **Logic Apps is the one true *collection* gap in the whole product** — `microsoft.logic/workflows` is explicitly excluded by the `!in` clause in the unfiltered ARG query (`src/collect/Get-ScoutRawInventory.ps1`), so unlike every other ❌ in this document it cannot be fixed by adding a manifest alone. Event Hubs is collected but filed under `Analytics/`; AB6446 recommends moving it here so the messaging story reads as one. Both collected providers are namespace/service-level only — no APIM APIs or products, no Service Bus queues or topics (P2).

### 12. Identity

**Scout collects 1 of 5 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Microsoft Entra Domain Services | Microsoft.AAD | ❌ | — | P2 |
| Entra IAM (aadiam) | microsoft.aadiam | ❌ | — | P3? |
| Microsoft Entra Connect Health | Microsoft.ADHybridHealthService | ❌ | — | P3? |
| Azure AD B2C | Microsoft.AzureActiveDirectory | ❌ | — | P2 |
| Managed identities | Microsoft.ManagedIdentity | ✅ | Identity/ManagedIds | — |

> Note: this table understates Scout badly and it is important not to read it as "Identity is broken". Scout has **16 Identity collectors**, but 15 of them declare `entra/…` pseudo-types (users, groups, service principals, conditional access, PIM assignments, risky users, licensing, …) and read Microsoft Graph, not ARM. Graph is outside this ARM-provider taxonomy entirely, so it cannot score here. Only `Identity/ManagedIds` is a real ARM type. The genuine ARM gap in this category is `Microsoft.Authorization/roleAssignments` (P1) — which Microsoft files under Management and governance, and which Scout already *ingests* for rule evaluation but never renders to a worksheet. Note also that `Identity/ManagedIds` (ARM) and `Identity/ManagedIdentities` (Graph) are two different collectors; AB6446 flags them for overlap verification.

### 13. Security

**Scout collects 1 of 6 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| App Compliance Automation | Microsoft.AppComplianceAutomation | ❌ | — | P3? |
| Azure Attestation | Microsoft.Attestation | ❌ | — | P3 |
| Azure Backup vaults / Data Protection | Microsoft.DataProtection | ❌ | — | P1 |
| Key Vault | Microsoft.KeyVault | ✅ | Security/Vault | — |
| Microsoft Defender for Cloud | Microsoft.Security | ❌ | — | P1 |
| Microsoft Sentinel | Microsoft.SecurityInsights | ❌ | — | P1 |

> Note: the ❌ on `Microsoft.Security` needs qualifying. Scout has four Defender collectors — `Security/DefenderAlerts`, `DefenderAssessments`, `DefenderPricing`, `DefenderSecureScore` — but all four declare the **synthetic** type `AZSC/Subscription/SecurityPolicySweep` and read from a REST sweep envelope, not from `Microsoft.Security/*` via ARG. So Defender data does reach the report; the provider is not queried as a first-class ARM type, and AB6446 rates promoting `Microsoft.Security/pricings` to a real sheet as P1. Of Scout's 5 Security manifests, exactly one (`Security/Vault`) is a real ARM resource type. Key Vault itself is collected at the vault level only — keys, secrets and certificates, and therefore expiry (the actual finding), are not (P1). WAF policies in all three flavours are P1 and span this category and Networking.

### 14. DevOps

**Scout has no category for DevOps. Scout collects 0 of 7 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Chaos Studio | Microsoft.Chaos | ❌ | — | P3 |
| Azure Deployment Environments / Dev Box | Microsoft.DevCenter | ❌ | — | P2 |
| Managed DevOps Pools | Microsoft.DevOpsInfrastructure | ❌ | — | P2 |
| Azure DevTest Labs | Microsoft.DevTestLab | ❌ | — | P3 |
| Azure Lab Services | Microsoft.LabServices | ❌ | — | P3 |
| Azure Load Testing | Microsoft.LoadTestService | ❌ | — | P3 |
| Azure DevOps | Microsoft.VisualStudio | ❌ | — | P3? |

> **Note — this category is nearly free to create.** Scout already ships **five DevOps collectors misfiled under `Management/`**: `Management/DevOpsProjects`, `Management/DevOpsPipelines`, `Management/DevOpsRepositories`, `Management/DevOpsAgentPools` and `Management/DevOpsServiceConnections`. They declare `devops/…` pseudo-types (`devops/projects`, `devops/pipelines`, `devops/repositories`, `devops/agentpools`, `devops/serviceconnections`), read the Azure DevOps REST API rather than ARM, and are already gated behind `-IncludeDevOps`. They score ❌ against `Microsoft.VisualStudio` because that ARM provider is not what they query — but promoting them to a real `DevOps/` category costs a directory move plus a category-alias decision, not new collection work. The ARM-side additions worth building on top are Managed DevOps Pools and Dev Center (P2 each).

### 15. Migration

**Scout has no category for Migration, and no collector anywhere touches it. Scout collects 0 of 5 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Data Box | Microsoft.DataBox | ❌ | — | P2 |
| Azure Stack Edge | Microsoft.DataBoxEdge | ❌ | — | P2 |
| Azure Database Migration Service | Microsoft.DataMigration | ❌ | — | P2 |
| Azure Migrate | Microsoft.Migrate | ❌ | — | P1 |
| Azure Migrate (discovery / OffAzure) | Microsoft.OffAzure | ❌ | — | P1 |

> Note: total zero — this is the only Microsoft top-level category with no coverage of any kind, not even a synthetic or REST-based collector. It is also the most surprising absence for a hybrid/Azure Local consultancy, where migration assessment is a core motion. `src/pipeline/diagram/Start-ScoutDiagramSubscription.ps1` names `microsoft.migrate/*` in its icon map — those are **diagram symbols only, with no query behind them**, and must not be read as coverage.

### 16. Monitor

**Scout collects 4 of 6 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Monitor alerts | Microsoft.AlertsManagement | ✅ | Monitor/SmartDetectorAlertRules | — |
| Azure Managed Grafana | Microsoft.Dashboard | ❌ | — | P2 |
| Azure Monitor / Application Insights | Microsoft.Insights | ✅ | Monitor/AppInsights, Monitor/MetricAlertRules, Monitor/DataCollectionRules +8 more | — |
| Azure Monitor workspace (Prometheus) | microsoft.monitor | ❌ | — | P1 |
| Log Analytics | Microsoft.OperationalInsights | ✅ | Monitor/Workspaces, Monitor/MonitorMetricsIngestion | — |
| Azure Monitor solutions | Microsoft.OperationsManagement | ✅ | Monitor/LAWorkspaceSolutions | — |

> Note: Scout's largest category by manifest count (24), of which 6 are `AZSC/ARMChild/*` synthetic child collectors (App Insights continuous export, proactive detection, work items; LA linked services and saved searches). `Microsoft.AlertsManagement` is collected for smart-detector rules only — Prometheus rule groups and alert processing rules are P2 gaps. AB6446 flags a likely duplicate here: `Monitor/AppInsightsWebTests` and `Monitor/AppInsightsAvailabilityTests` both target `microsoft.insights/webtests`, and only the former filters on `kind`.

### 17. Management and governance

**Scout collects 6 of 25 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Advisor | Microsoft.Advisor | ✅ | Management/AdvisorScore | — |
| Azure Policy / RBAC / ARM authorization | Microsoft.Authorization | ❌ | — | P1 |
| Azure Automation | Microsoft.Automation | ✅ | Management/AutomationAccounts | — |
| Cost Management + Billing | Microsoft.Billing | ❌ | — | P3? |
| Azure savings plans | Microsoft.BillingBenefits | ❌ | — | P3? |
| Azure Blueprints | Microsoft.Blueprint | ❌ | — | P3? |
| Azure carbon optimization | Microsoft.Carbon | ❌ | — | P3? |
| Consumption / budgets | Microsoft.Consumption | ✅ | Management/ReservationRecom | — |
| Cost Management | Microsoft.CostManagement | ❌ | — | P2? |
| Customer Lockbox | Microsoft.CustomerLockbox | ❌ | — | P3? |
| ARM feature flags | Microsoft.Features | ❌ | — | P3? |
| Guest Configuration | Microsoft.GuestConfiguration | ❌ | — | P3? |
| Microsoft Intune | Microsoft.Intune | ❌ | — | P3? |
| Azure Maintenance / Update Manager | Microsoft.Maintenance | ✅ | Management/MaintenanceConfigurations | — |
| Managed operations | Microsoft.ManagedOps | ❌ | — | P3? |
| Azure Lighthouse | Microsoft.ManagedServices | ✅ | Management/LighthouseDelegations | — |
| Management Groups | Microsoft.Management | ❌ | — | P2? |
| Azure Policy insights | Microsoft.PolicyInsights | ❌ | — | P2? |
| Azure portal (dashboards) | Microsoft.Portal | ❌ | — | P3? |
| Site Recovery / Recovery Services | Microsoft.RecoveryServices | ✅ | Management/RecoveryVault, Management/Backup | — |
| Azure Resource Graph | Microsoft.ResourceGraph | ❌ | — | P3? |
| Azure Service Health | Microsoft.ResourceHealth | ❌ | — | P2? |
| Azure Resource Manager (resources, RGs) | Microsoft.Resources | ❌ | — | P2 |
| Azure Managed Applications | Microsoft.Solutions | ❌ | — | P2 |
| SAP on Azure | Microsoft.Workloads | ❌ | — | P2 |

> Note: four ❌ rows here are covered by **synthetic** collectors rather than ARM provider queries, and should not be read as untouched. `Microsoft.Management` → `Management/ManagementGroups` (`AZSC/Management/ManagementGroup`); `Microsoft.Authorization` → `Management/PolicyDefinitions`, `Management/PolicySetDefinitions`, `Management/CustomRoleDefinitions` (all `AZSC/Management/*`); `Microsoft.PolicyInsights` → `Management/PolicyComplianceStates` (`AZSC/Subscription/SecurityPolicySweep`); `Microsoft.ResourceHealth` → `Monitor/Outages` (`AZSC/Monitor/Outage`). The real `Microsoft.Authorization` P1 gap is the *assignment* side — role assignments, resource locks and policy assignments are already ingested by `src/ingest/Import-Governance.ps1` to feed rules but never reach a worksheet, so they are near-free to surface. Same pattern for `Microsoft.Consumption/budgets`: ingested, never rendered. `Microsoft.ResourceGraph` is the query engine Scout runs on rather than an inventory target. **Retirement flag:** Azure Blueprints is deprecated in favour of Template Specs and deployment stacks — do not build.

### 18. Hybrid + multicloud

**Scout collects 4 of 10 providers in this category.**

| Azure service | Resource provider | Collected? | Scout collector | Priority |
|---|---|---|---|---|
| Azure Stack | Microsoft.AzureStack | ❌ | — | P3? |
| Azure Local (Azure Stack HCI) | Microsoft.AzureStackHCI | ✅ | Hybrid/Clusters, Hybrid/VirtualMachines, Hybrid/LogicalNetworks +4 more | — |
| Custom locations | Microsoft.ExtendedLocation | ❌ | — | P2? |
| Azure Arc-enabled servers | Microsoft.HybridCompute | ✅ | Hybrid/ARCServers, Hybrid/ArcExtensions, Hybrid/ArcGateways +2 more | — |
| Arc hybrid connectivity | Microsoft.HybridConnectivity | ❌ | — | P2? |
| AKS enabled by Arc / on Azure Local | Microsoft.HybridContainerService | ❌ | — | P2? |
| Azure Arc-enabled Kubernetes | Microsoft.Kubernetes | ✅ | Hybrid/ArcKubernetes | — |
| Arc Kubernetes configuration (GitOps/Flux) | Microsoft.KubernetesConfiguration | ❌ | — | P2? |
| Arc resource bridge | Microsoft.ResourceConnector | ✅ | Hybrid/ArcResourceBridge | — |
| Arc-enabled SCVMM | Microsoft.SCVMM | ❌ | — | P3? |

> Note: by depth rather than provider count this is Scout's strongest category — 16 manifests over 18 distinct types, and the Azure Stack HCI provider alone is covered by seven collectors (clusters, VM instances, logical networks, storage containers, gallery and marketplace images, sites). Scout additionally collects two providers Microsoft does not list in this directory at all: `microsoft.azurearcdata` (`Hybrid/ArcDataControllers`, `Hybrid/ArcSQLManagedInstances`, `Hybrid/ArcSQLServers`) and `microsoft.edgeconfig` (`Hybrid/ArcSites`). `Hybrid/ArcSites` is a single collector spanning three providers — `microsoft.hybridcompute/sites`, `microsoft.azurestackhci/sites` and `microsoft.edgeconfig/sites`. The remaining ❌ rows are all natural extensions of work Scout already does well, which is why they are graded P2? rather than P3?.

---

### Summary

| Category | Providers | Collected | Coverage % |
|---|---:|---:|---:|
| 1. General | 8 | 1 | 13% |
| 2. Compute | 12 | 4 | 33% |
| 3. Networking | 2 | 1 | 50% |
| 4. Storage | 6 | 2 | 33% |
| 5. Web and Mobile | 5 | 1 | 20% |
| 6. Containers | 4 | 4 | 100% |
| 7. Databases | 8 | 7 | 88% |
| 8. Analytics | 11 | 4 | 36% |
| 9. AI + machine learning | 6 | 4 | 67% |
| 10. Internet of Things | 11 | 2 | 18% |
| 11. Integration | 15 | 3 | 20% |
| 12. Identity | 5 | 1 | 20% |
| 13. Security | 6 | 1 | 17% |
| 14. DevOps | 7 | 0 | 0% |
| 15. Migration | 5 | 0 | 0% |
| 16. Monitor | 6 | 4 | 67% |
| 17. Management and governance | 25 | 6 | 24% |
| 18. Hybrid + multicloud | 10 | 4 | 40% |
| **Total** | **152** | **49** | **32%** |

> Three providers Scout collects do not appear in Microsoft's 18-category directory and so score nowhere above: `microsoft.azurearcdata`, `microsoft.classiccompute` and `microsoft.edgeconfig`. Adding them gives the 52-provider figure quoted in AB#6446. The denominator here (152) is Microsoft's role-based-access-control provider directory, which is narrower than the ~130–200 provider counts quoted elsewhere; the ratio, not the absolute number, is the comparable figure.

---

## 5. The four audits, summarised

### AB#6444 — Collector verification
**Verdict: 0 of 174 verified against real Azure; 12 provably always-empty.**
Detail in §3.5. Proposes a four-layer verification approach: a static resource-type existence gate
(~1 day, would have caught 11 of the 12 defects), retained per-collector row counts (~1 day, turns
every future run into evidence), running the 174 against the existing-but-unused real anonymised
capture (~2-3 days), and — explicitly *not* recommended at full scope — a canary subscription.
→ `AB6444-collector-verification-audit.md`

### AB#6445 — Least-privilege permissions
**Verdict: the minimum role set is `Reader` at root management group. Everything else is opt-in.**
Scout over-asks for **Security Reader** (redundant — strict subset of Reader for every call Scout
makes, yet nagged for on every subscription) and **Monitoring Reader** (redundant, *and* grants
`Microsoft.Support/*` = ticket creation, a write). `AuditLog.Read.All` is requested but no collector
consumes it.

The structural insight: the 174 collectors **don't call Azure at all** — they're transforms over an
in-memory bag. All Azure calls come from ~13 functions in `src/collect/`, so the permission matrix
collapses to 11 access classes.

Also found: Graph tokens come from `az account get-access-token`, so Scout silently requires a
*second* login beyond `Connect-AzAccount` and breaks under service-principal runs; Azure DevOps has
zero pre-flight coverage.
→ `AB6445-least-privilege-permissions-audit.md`

### AB#6446 — Service coverage gaps
**Verdict: 52 of ~130 providers ≈ 40% coverage; the taxonomy should grow.**
Detail in §3.1 and §4. Notable specifics: AI's 27 collectors are inflated (11 are the same resource
type split by `kind`); Storage's 2 is genuinely thin; Data Factory, modern Front Door
(`Microsoft.Cdn/profiles`), and backup *protected items* are absent — meaning **"which VMs have no
backup" is unanswerable today**. RBAC role assignments, resource locks, policy assignments and
budgets are **already ingested but never rendered** — near-free wins.
Recommends *against* building Media Services, Blockchain, and Mixed Reality (all retired).
→ `AB6446-service-coverage-gap-analysis.md`

### AB#6447 — CAF/WAF coverage
**Verdict: ~10% of CAF, ~15% of WAF.**
Root-caused the wizard path bug (§3.2). Found that **32% of all rules (47 of 148) are `manual: true`**
— they assert nothing and produce no verdict. Found that **Azure Policy compliance state is
collected through three separate code paths and never scored by any rule** — the most valuable
governance signal in Azure, paid for in query time and discarded. Found **two false-pass rules**
(`CAF-GOV-05`, `CAF-AUT-02`) that claim to verify policy drift correction but actually just check
whether an assignment has a parameters block.
→ `AB6447-caf-waf-coverage-audit.md`

---

## 6. Work plan

**Wrong right now** — defects, not enhancements:

| # | Work | Effort | Source |
|---|---|---|---|
| 1 | ✅ Patch assessment → read-only | **Done** | §3.4 |
| 2 | Fix the wizard manifest path | 15 min | §3.2 |
| 3 | Raw data dump for everything collected | Small | §3.3 |
| 4 | Wire `-IncludeTenantWideResources`; fix `Monitor/Outages` call ordering | 1-2 d | AB#6444 |
| 5 | Static resource-type existence gate | 1 d | AB#6444 |
| 6 | Per-collector row-count artifact, retained | 1 d | AB#6444 |
| 7 | Fix the readiness verdict; drop the two redundant roles | 1-2 d | AB#6445 |
| 8 | Fix the two false-pass rules; score the policy data already collected | Days | AB#6447 |
| 9 | Correct/retire the 5 bad resource-type strings | 2-3 d | AB#6444 |
| 10 | Un-exclude Logic Apps from the ARG query | Minutes | §3.3 |

**Additive** — new capability:

| # | Work | Effort |
|---|---|---|
| 11 | Create DevOps + Migration categories (DevOps is mostly a directory move) | Days |
| 12 | Build out the thin categories — Storage, Web, Integration, IoT, Security | ~1-2 wks |
| 13 | Surface already-ingested data: RBAC assignments, locks, policy assignments, budgets | Days |
| 14 | Deeper CAF/WAF rules toward real coverage | Weeks |
| 15 | **Score the Microsoft Cloud Security Benchmark** from policy compliance state Scout already collects — see §3b Table 4 | **Days, not weeks** |
| 16 | Detect which other regulatory initiatives are assigned; expose each as its own assessment (CIS, ISO 27001, NIST, PCI-DSS…) | Weeks |
| 17 | Per-WAF-pillar and per-CAF-area assessments | Weeks |

> **The highest-value item on this list may be #15.** Azure ships regulatory-compliance policy
> initiatives with the control evaluation already done — MCSB alone is 223 policies, is Defender for
> Cloud's *default* initiative, and is therefore assigned in essentially every subscription. Scout
> **already collects the compliance state** and no rule reads it. That turns "compliance
> assessment" from a rule-authoring project into a rendering job.
>
> **The hard constraint that comes with it:** apart from MCSB, an initiative only returns data
> where it has been *assigned*. Unassigned yields no data — not a zero score. Scout must report
> "never assessed" as a coverage gap, never as a pass or a fail. That distinction is the whole
> difference between a trustworthy compliance report and a dangerous one.

---

## Appendix — detailed reports

| Report | Work item |
|---|---|
| [`AB6444-collector-verification-audit.md`](AB6444-collector-verification-audit.md) | AB#6444 |
| [`AB6445-least-privilege-permissions-audit.md`](AB6445-least-privilege-permissions-audit.md) | AB#6445 |
| [`AB6446-service-coverage-gap-analysis.md`](AB6446-service-coverage-gap-analysis.md) | AB#6446 |
| [`AB6447-caf-waf-coverage-audit.md`](AB6447-caf-waf-coverage-audit.md) | AB#6447 |
