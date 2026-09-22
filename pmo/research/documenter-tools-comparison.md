# Get to the Cloud Documenter tools — research for azure-scout report content

Researched 2026-08-03. Sources: GitHub repos (README + raw source files fetched directly),
azuredocumenter.com, gettothe.cloud blog post. All three tools share one architecture:
a PowerShell collector (`Get-Azure*Inventory.ps1`) writes JSON, a local HTTP server
(`Start-*Server.ps1`) serves a single-page `index.html` + `app.js` + `styles.css` dashboard,
with jsPDF-driven PDF export and JSON export. WAF scoring is externalized to a
`waf-config.json` the user can edit.

Everything below is cited with the exact URL or file I pulled it from. Where WebFetch
summarized rather than quoted, I've marked it **(paraphrased by fetch, not a direct quote)**.
I could not browse a live rendered sample report or screenshot — none were embedded in the
pages I fetched — so all conclusions about visual layout come from HTML/CSS/JS structure,
not a rendered image.

---

## 1. Exact report section/tab list

### Landing Zone Documenter (most relevant to azure-scout)
Source: `raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-landingzone/main/index.html`

Sidebar nav, 10 sections:

1. Overview
2. Management Groups
3. Subscriptions
4. Policies (3 subsections: Policy Definitions, Policy Initiatives, Policy Assignments)
5. Role Assignments
6. Networking (9 subsections: Virtual Networks, VNet Peerings, VPN Gateways, Virtual WANs, Azure Firewalls, Firewall Policies, Network Security Groups, Private DNS Zones, Private Endpoints)
7. Virtual Machines
8. Governance (3 subsections: Budgets, Resource Locks, Common Tags)
9. Resource Diagram (interactive vis.js topology)
10. CAF/WAF Scoring Configuration

PDF export (from README) adds: Cover page → Executive Summary → CAF assessment (7 categories) → WAF pillar analysis (5 pillars) → detailed resource tables → recommendations/references. Source: README via WebFetch.

### Azure Local Documenter
Source: `raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-local/main/index.html`

14 sections: Overview, WAF Assessment, Cost Analysis, Clusters, Nodes, Agent & Software Versions, Logical Networks, Images, Storage Paths, Custom Locations, Arc Resource Bridges, Arc Gateways, Licensed Machines, Virtual Machines.

### AVD Documenter
Source: README via WebFetch (github.com/GetToThe-Cloud/documenter-azure-azurevirtualdesktop).
Host Pools, Session Hosts, Workspaces, Application Groups, Scaling Plans, Virtual Networks,
Compute Galleries, plus WAF Assessment (40+ rules) and connection diagrams.

---

## 2. How a single section is structured

**Overview section (Landing Zone tool):** 12–14 metric cards in a grid — icon, big number (`<h3>`), label. Pure counts (Management Groups, Subscriptions, Policy Definitions/Initiatives/Assignments, Role Assignments, VNets, VNet Peerings, Virtual WANs, Private Endpoints, Private DNS Zones, VMs, Budgets, Resource Locks). No narrative text sits above the cards. Source: index.html structural fetch.

**Detail sections (e.g. Networking):** each resource type is its own subsection with its own `<table>`. No rollup/summary row sits above the table within the subsection itself — the only rollup is the Overview page's counts. This is a flat "one table per resource type" model, not a summary-then-detail model within a section.

**Table column choices are notably wide and Azure-specific**, e.g.:
- VNet Peerings: Name, Source VNet, Remote VNet, State, Allow VNet Access, Allow Forwarded Traffic, Allow Gateway Transit, Use Remote Gateways, Provisioning
- Firewall Policies: Name, RG, Location, Tier, Total Rules, App Rules, Network Rules, NAT Rules, Intrusion Detection, Subscription
- Azure Local hardware table: Name, Cluster, Status, Manufacturer, Model, Serial Number, Cores, Memory (GB), Solution Version, Last Updated, Workload, Agent Version, Location (source: `app.js` `renderNodes()`, quoted literal `<th>` string)

Every table carries the **Subscription** column even in single-subscription views — this is how they signal multi-subscription scope without a separate subscription-switcher UI.

**Diagrams sit in their own dedicated nav section** ("Resource Diagram"), not inline inside the Networking section — it's a standalone vis.js canvas with click-to-inspect nodes, not embedded per-subsection. Source: app.js fetch, edges/nodes code quoted above.

---

## 3. WAF pillar assessment — scoring model, presentation, remediation

Both `waf-config.json` files (Landing Zone and Azure Local) are structurally identical:
version, 5 pillars, each pillar = array of checks with `id`, `name`, `weight`, pass criteria (implemented as JS predicate, not stored as data), and a `recommendation` string shown only on failure.

**Landing Zone pillars/checks** (11 checks total, weight 1 each — an unweighted average):
- Reliability: Network Redundancy, Resource Protection, Hybrid Connectivity
- Security: Policy Enforcement, Access Control, Network Segmentation, Firewall Protection
- Cost Optimization: Budget Management, Cost Tracking, SKU Controls
- Operational Excellence: Management Hierarchy, Subscription Strategy, Monitoring & Logging
- Performance Efficiency: Scalable Network, High-Performance Connectivity, Deployment Automation

Score = passed checks ÷ total checks per pillar, as a plain percentage. Overall WAF score = average of the 5 pillar percentages. Four-band verdict: Excellent ≥80 (green), Good 60–79 (blue), Fair 40–59 (amber), Needs Improvement <40 (red). Source: `waf-config.json` raw fetch.

**Azure Local pillars/checks** are meaningfully more sophisticated: checks carry a **weight of 1, 2, or 3** (not flat), and most have a **pass / warning / fail three-state** rather than binary pass/fail — e.g. "System updates applied" passes at ≥90% nodes patched, warns at ≥70%, otherwise fails; warnings score at 50% weight. 14 checks, 22 max weighted points. Source: `waf-config.json` raw fetch.

**Per-check rendering (both tools' `app.js`)** — this is the concrete UI pattern:
```
<div class="waf-check-item waf-check-${status}">
  <div class="waf-check-icon">${icon}</div>          <!-- ✅ ⚠️ ❌ -->
  <div class="waf-check-content">
    <div class="waf-check-title">${check.name}</div>
    <div class="waf-check-desc">${check.message}</div>      <!-- computed result text -->
    ${!check.pass && check.recommendation ?
      `<div class="waf-check-recommendation">💡 ${check.recommendation}</div>` : ''}
  </div>
</div>
```
Source: `app.js` quoted verbatim (Azure Local tool). Weight is stored but **never displayed to the user** — no arithmetic is shown, just the final percentage and a status badge per pillar. The Landing Zone PDF exporter is even thinner: it doesn't render individual checks at all in the PDF, only category-level score/percentage plus a bullet list of `finding` strings tagged ✓/⚠/✗ with no per-finding weight or recommendation shown in the PDF (only in the live HTML dashboard). Source: `app.js` PDF-export fetch, quoted code.

**Compared to azure-scout:** azure-scout already shows score arithmetic per the owner's own account; these tools do **not** — they hide the weighting entirely and only ever show a percentage + status badge + one-line message + conditional one-line recommendation. **This is not something to copy** — showing the arithmetic is already a differentiator worth keeping (see §6). The one genuinely better idea here is the **three-state pass/warning/fail model with partial credit** (Azure Local tool) versus a flat binary pass/fail, and **variable check weights** (1/2/3) versus flat weight-1 checks (Landing Zone tool) — both make a score feel proportionate to severity rather than "one missing NSG = same penalty as no firewall at all."

---

## 4. Interaction model — search, filter, navigation

- **Navigation:** single fixed left sidebar, `onclick="showSection()"` + `data-section` routing, one active section shown at a time (classic SPA tab-switch, no deep-linking/URL-hash observed in the fetched code, no breadcrumbs).
- **Search:** simple per-table client-side substring filter — `filterTable(searchId, tableId)` iterates `<tr>` elements and does `textContent.toUpperCase().indexOf(filter) > -1`, hiding non-matching rows via `display:none`. This exists **per table**, not as a single global search box across all sections. Source: Azure Local `app.js`, code quoted above.
- **Cluster filter (Azure Local only):** a `<select>` dropdown (`#clusterFilter`) that re-renders the VM table filtered to one cluster — the only example of a non-text filter control found.
- **The Landing Zone tool's `app.js` has no search/filter code at all** — tables render once via `.innerHTML` and stay static. This is a meaningful capability gap in the tool most relevant to us. Source: WebFetch summary of that file, explicit: "Not implemented in the provided code."
- **Drill-down:** node click → details panel (diagram), row click → modal (VM details, subnet details, node extensions). No section-to-section cross-linking evident (e.g. clicking a subscription doesn't jump to its VMs).

**Compared to azure-scout:** the owner told us we already have per-section filters and a left rail — on the evidence here, that already matches or beats the Landing Zone tool (which has zero search) and roughly matches the Azure Local tool (per-table substring search, one dropdown). **No interaction-model idea here is worth adopting** — this is the one area where these tools are behind us, not ahead.

---

## 5. Ideas we should steal, ranked

1. **A dedicated Cost Analysis section with Azure Hybrid Benefit savings math, shown as concrete dollar figures.** The Azure Local tool computes `$10/physical-core/month` list price, current monthly/yearly cost, cores-with-HB vs cores-without-HB, adoption rate %, and "potential monthly/yearly savings if all nodes enable Hybrid Benefit" — all rendered as cost cards plus a per-node cost breakdown table. Source: `app.js` `renderCostAnalysis()`, quoted formulas. **Justification:** this converts a compliance finding ("HB not enabled") into a dollar number an executive reads in one glance — exactly the "make report content substantial" gap the owner flagged. We already collect Azure Hybrid Benefit state for Azure Local per the corpus notes; we're not yet turning it into a cost projection.

2. **Three-state (pass/warning/fail) WAF checks with partial credit, replacing pure binary pass/fail where a metric is naturally a percentage** (e.g. "% nodes patched", "% policy compliance"). **Justification:** a check that's 85% true shouldn't score identically to one that's 0% true; the Azure Local `waf-config.json` model is a clean, easy-to-replicate JSON shape (`weight`, pass threshold, warn threshold, three message variants).

3. **Variable per-check weighting (1–3) instead of flat weight-1 checks.** **Justification:** lets "no firewall at all" outweigh "one missing tag policy" in the pillar score without hand-tuning the percentage math — cheap to add if our current scoring engine treats all checks equally.

4. **A hardware/node inventory table with the exact column set they use for Azure Local**: Manufacturer, Model, Serial Number, Cores, Memory (GB), Solution Version, Agent Version, Last Updated, Workload — above/beside the VM list, not merged into it. **Justification:** for Azure Local assessments specifically this is the kind of physical-asset detail an infrastructure consulting deliverable is expected to carry, and it's a natural fit if we already collect cluster/node data.

5. **A single "Common Tags" governance subsection listing the actual tag keys/values in use across the estate** (not just a compliance pass/fail on "tagging exists"). **Justification:** turns a governance check into an inventory artifact a customer can act on directly (e.g., "you have 6 competing environment-tag spellings").

6. **Firewall/NSG rule-count columns on the resource table itself** (Total Rules, App Rules, Network Rules, NAT Rules, Intrusion Detection Mode) rather than only a pass/fail "firewall exists" check. **Justification:** gives the reader the actual configuration texture, closing part of the "thin content" gap without needing a new assessment — it's richer rendering of data we likely already collect for a firewall-exists check.

7. **VNet Peering detail table with the individual boolean flags** (Allow VNet Access, Allow Forwarded Traffic, Allow Gateway Transit, Use Remote Gateways) rather than a collapsed "peering exists" fact. **Justification:** these flags are exactly the kind of thing that silently misconfigures hub-spoke connectivity and a consultant would call out by name.

---

## 6. Ideas we should NOT copy

- **Binary/flat scoring exposed with no arithmetic shown to the user (Landing Zone tool).** azure-scout already shows score arithmetic; hiding it (as both these tools do in their live dashboards) would be a regression for an *assessment* product where the customer needs to see why they lost points, not just a badge.
- **PDF export that drops per-check detail entirely and only shows category-level bullets** (Landing Zone tool's PDF renderer). For an assessment deliverable meant to leave the room with the customer, dropping the individual findings from the exported artifact (keeping them only in the live HTML) undermines the "audit-ready documentation" pitch the tool markets itself on. Our PDF/Word export should keep parity with the HTML detail.
- **No global search, per-table-only filtering with zero cross-section search (both tools).** This is worse than what azure-scout already has; not something to imitate.
- **Static single-tenant, single-run scope with no run history/comparison** — nothing in either tool's structure suggests trend-over-time or run-to-run diffing. Not a "don't copy" so much as a non-feature; azure-scout's assessment framing (score an estate, tell them what to fix) benefits from being distinct from a point-in-time documentation snapshot, so this isn't a gap worth chasing from their example.
- **Unweighted WAF-pillar checks with weight fields that exist in JSON but are never surfaced in the UI (Landing Zone tool).** If we adopt weighting (idea #3 above), we should actually *show* it, unlike their implementation — this is deliberately calling out their omission as something to improve on rather than replicate.

---

## 7. Gap list — things they document/compute that azure-scout apparently does not

Cross-checked against the "58 collect keys, 30 with data" audit noted in memory (`collector-audit-corpus-findings.md`) and the Azure Local field-fix history in memory — I could not directly re-verify the current collector manifest in this session, so treat the "azure-scout does not" side of each row as **unverified, flag for confirmation** rather than settled fact:

| Gap | Evidence they do it | Confidence azure-scout lacks it |
|---|---|---|
| Cost projection (monthly/yearly $ at a fixed core price) for Azure Local, with Hybrid Benefit savings math | `app.js` `renderCostAnalysis()`, quoted formulas above | High — no cost-projection collector or renderer surfaced in prior session memory; this is a genuine candidate work item |
| Azure Hybrid Benefit adoption % and per-node HB flag surfaced as its own analysis (not just a raw collector field) | Azure Local `waf-config.json` `cost-001` check + `app.js` cost cards | Medium — HB *state* is likely collected (memory references AHB elsewhere in the codebase's history) but the savings-math presentation layer is the gap, not the raw data |
| VNet peering boolean-flag detail table (4 flags) as a standalone view | Landing Zone `index.html`, table column list | Unverified — need to check our networking collector's peering fields |
| Firewall Policy rule-count breakdown (App/Network/NAT rule counts, Intrusion Detection mode) as its own table | Landing Zone `index.html`, table column list | Unverified — need to check our firewall/network security collector |
| Interactive topology diagram with click-to-inspect resource details panel | Landing Zone `app.js`, vis.js edges/nodes code | Partial — azure-scout has inline-SVG diagrams per the task brief, but click-to-inspect interactivity on the diagram itself is not confirmed |
| Node hardware serial number + solution/agent version tracking table for Azure Local | Azure Local `app.js` `renderNodes()`, quoted `<th>` list | Unverified — need to check whether our Azure Local collectors capture serial number and solution version, or only cluster/node identity |

**Recommendation:** the cost-projection/Hybrid-Benefit-savings gap (row 1) is concrete enough to raise as a work item without further verification — it's a net-new report section, not a missing field. The other rows need a quick pass against the actual collector manifest before filing anything, since I did not re-open the collector inventory in this session.

---

---

## 8. UNIFIED RANKED "WHAT TO STEAL" LIST — Get-to-the-Cloud documenters + Microsoft Assessments platform

This supersedes §5 as the single ranked list the owner asked for, spanning both research passes.
Full detail and sourcing for the Microsoft items is in the companion file
[`pmo/research/microsoft-assessment-methodology.md`](microsoft-assessment-methodology.md) §10 —
this list gives the one-line justification and points back there for the citation.

1. **Populate `learnUrl`/guidance link on every finding, and add it as its own column in the CSV
   export.** Verified against the real rendered payload this session: `learnUrl` is empty on every
   sampled finding (`learnUrl=False` on all four checked), and our CSV export's actual column set
   is `Id,Title,Severity,Assessment,Group,Remediation` — no link column at all. Microsoft's own WAF
   Review export treats `Link` as a core column, populated with a direct URL to the guidance
   article for that exact recommendation, on every row. **Justification:** this is the real
   "recommendation as a unit" gap — not the identifier (see the corrections note at the end of this
   file), the *guidance link*. A finding with remediation prose but nowhere to click for the
   authoritative how-to is thinner than what Microsoft ships, and it's a data/wiring gap, not a
   design gap — the collectors and rule files already carry enough to point at CAF/WAF/Learn
   articles per rule; the field just isn't populated or exported. Source: `microsoft-assessment-methodology.md` §10.4.

2. **A dedicated Cost Analysis section with Azure Hybrid Benefit savings math**, shown as concrete
   dollar figures (current monthly/yearly cost, potential savings, per-node breakdown).
   **Justification:** converts a compliance finding into a number an executive reads in one
   glance; genuinely new content, not a rendering change. Source: documenter-azure-local `app.js`
   `renderCostAnalysis()`, §1–3 above.

3. **Expose the per-recommendation weight/score contribution in the rendered output, not just
   internally in the scoring engine** — both Microsoft's WAF Review CSV (`Weight` column, e.g. 80,
   100) and Secure Score's published max-score table do this; azure-scout's rule weights exist in
   `src/assess/rules/*.yaml` but aren't surfaced. **Justification:** lets the reader see exactly
   how much a fix is worth before they commit to doing it — this is what makes a "potential score
   increase" number crediblely computable in the report itself, not just claimed.

4. **A numerator/denominator score presentation with a banded criticality label**, confirmed
   independently in two Microsoft sources (Secure Score's `current/max` and the WAF Review CSV's
   `'0/120' Critical` header block) — never a bare percentage. **Justification:** azure-scout
   apparently already shows arithmetic per the owner's brief; this is confirmation the pattern is
   right, and a reminder to keep the criticality band alongside the fraction, not just the number.

5. **Two customer-editable fields in the exported artifact**: a remediation-status flag
   (`CompleteY/N`) and a free-text note field, present in Microsoft's CSV schema.
   **Justification:** turns the export from a read-only snapshot into a working backlog document —
   cheap to add to azure-scout's existing CSV export and directly closes part of the "thin content"
   complaint by making the artifact something the customer keeps using after the meeting ends.

6. **Three-state (pass/warning/fail) checks with partial credit and variable per-check weight
   (1–3)**, from the Azure Local documenter's `waf-config.json`, replacing flat binary/weight-1
   checks. **Justification:** a check that's 85% true shouldn't score identically to one at 0% —
   the JSON shape (`weight`, pass threshold, warn threshold, three message variants) is a cheap,
   direct pattern to replicate.

7. **State explicitly, in the methodology section, that "one framework, many scoped instances" is
   the model** — Microsoft ships one Core WAF Review plus 10+ technology-specific variants (AVD,
   AVS, AI, SaaS, Analytics, Data Services, Oracle, Azure Local, Azure ML, Azure AI Search) reusing
   the same five-pillar mechanics. **Justification:** azure-scout's per-assessment-category
   structure already matches this shape; saying so explicitly borrows Microsoft's own credibility
   framing rather than looking like a home-grown taxonomy. Source: `microsoft-assessment-methodology.md` §10.3.

8. **A hardware/node inventory table with the exact column set** the Azure Local documenter uses:
   Manufacturer, Model, Serial Number, Cores, Memory (GB), Solution Version, Agent Version, Last
   Updated, Workload. **Justification:** the kind of physical-asset detail an infrastructure
   consulting deliverable is expected to carry, if we already collect cluster/node data.

9. **State a recommended re-assessment cadence to the reader explicitly** ("every four months" is
   Microsoft's own stated number for brownfield workloads), and name each report run meaningfully,
   rather than leaving re-run timing and naming implicit. **Justification:** cheap, no new
   collector work, and directly reinforces trust in a Drift/trend feature by giving the reader a
   concrete expectation instead of "re-run periodically." Source: `microsoft-assessment-methodology.md` §10.7.

10. **A "Common Tags" governance subsection listing actual tag keys/values in use**, and
    **firewall/NSG rule-count columns** (Total Rules, App Rules, Network Rules, NAT Rules,
    Intrusion Detection mode) on the resource table itself, and **VNet peering boolean-flag detail**
    (Allow VNet Access, Allow Forwarded Traffic, Allow Gateway Transit, Use Remote Gateways) —
    three smaller Get-to-the-Cloud ideas, grouped because they're the same move: replace a
    collapsed pass/fail fact with the actual configuration texture the collector likely already
    has. **Justification:** cheapest wins in the whole list — no new assessment logic, just richer
    rendering of existing fields.

**Explicitly not re-ranked here but still valid** (see §6 above for full reasoning): don't copy
the documenters' habit of hiding score arithmetic, don't copy their PDF export dropping per-check
detail to category bullets only, don't copy their weak/absent global search.

**A strength worth stating in the report, not a gap**: azure-scout already has Microsoft's stable
per-recommendation code pattern. Verified against the real rendered payload: rule ids are
`landingzone:WAF-RE-05`, `landingzone:CAF-MGT-04`, `landingzone:BENCH-POL-Audit-ResourceLocks` —
directly comparable to `RE:04`/`SE:05`, and our ids are namespaced by assessment slug
(`landingzone:`, etc.), which Microsoft's are not — theirs collide if two workload-scoped WAF
variants both use `RE:04`. Our CSV export already carries `Id` as its first column. Nothing to
build here; the methodology section should say plainly that findings carry a stable, namespaced id
today, since that's a genuine parity point with (and slight improvement on) Microsoft's own model.

---

## Corrections log

This research file has had two claims revised after the initial draft. Recording both here rather
than silently editing them out, so a reader who saw the earlier version knows what changed and why.

1. **"Top-5 priority actions" claim retracted.** An earlier pass in
   `microsoft-assessment-methodology.md` §4 claimed Microsoft's WAF Review surfaces a curated
   "top-5 priority actions" list. A follow-up session could not re-verify that claim from a primary
   source — what's actually confirmed is a `Priority` band (`High`, etc.) plus pillar/code
   grouping, with the implementation guide stating final prioritization is an explicit human
   judgment step by the workload team, not an auto-generated top-N list. Treat the "top-5" claim as
   retracted pending a fresh source — see `microsoft-assessment-methodology.md` §10.5.

2. **"Stable per-recommendation code" was misidentified as our top gap — it isn't a gap at all.**
   The original §8 ranked "a stable per-recommendation code separate from the title" as azure-scout's
   #1 gap versus Microsoft's `RE:04`/`SE:05` pattern. That was wrong: azure-scout already has this,
   verified against the real rendered payload (`landingzone:WAF-RE-05`,
   `landingzone:CAF-MGT-04`, `landingzone:BENCH-POL-Audit-ResourceLocks` — namespaced by assessment
   slug, already the first column in our CSV export). The same verification pass exposed the
   genuine gap in its place: `learnUrl` is empty on every sampled finding, and our CSV export has
   no `Link` column at all (`Id,Title,Severity,Assessment,Group,Remediation`), while Microsoft
   treats `Link` as a core, populated column on every recommendation row. §8's ranked list has been
   corrected to reflect this — the missing guidance link is now item 1, and the stable-id point is
   recorded as a confirmed strength, not a gap.

---

## Drift tab vs. Microsoft's milestone model — feature-for-feature comparison

Read directly: `D:\git\thisismydemo\azure-scout\src\report\Get-ScoutDrift.ps1`.

Microsoft's milestone model, from `microsoft-assessment-methodology.md` §10.7, has four elements:
(a) named runs, (b) an explicitly stated recommended cadence, (c) prior-run-as-baseline, (d)
sign-in-tied history so runs persist centrally across devices/sessions.

| Element | Microsoft's model | azure-scout's `Get-ScoutDrift.ps1` | Verdict |
|---|---|---|---|
| **Run identity** | User assigns a meaningful milestone *name* ("include the workload's name," "use meaningful milestone names to indicate when you're evaluating the workload") | `-RunId` is a caller-supplied string, documented as expected to be "the assessment core's `yyyyMMdd_HHmmss` run folder name" (line 52–55) — a timestamp-derived identifier, not a human-authored label | **Gap.** Our run identity is machine-generated and unlabeled; there's no field for a human name like "Q3 remediation check-in" or "post-firewall-rollout re-check." Findings/history are keyed and diffed correctly by this id, but nothing in the object model captures *why* this run happened. |
| **Stated cadence** | Explicit, numeric: "Set a cadence, for example every four months" for brownfield workloads | No cadence concept anywhere in this file, its docstring, or its parameters | **Gap.** Nothing in the Drift feature or its surrounding docs tells the reader how often to re-run. This is cheap to add as report copy (doesn't require code changes to this file) — see ranked item 9 above. |
| **Prior-run baseline** | "Use the milestone feature... using the prior milestone as a baseline" | Explicit and well-built: picks "the most recent prior record whose RunId differs from the current RunId" (lines 131–133), returns an explicit `IsBaseline = $true` object with every finding classified `New` on a first run rather than throwing or returning nothing (docstring lines 34–38), and is tolerant of a missing or corrupt history file, treating either as "no history" without failing (lines 115–129) | **Parity — arguably ahead.** This is a more robust implementation of the same idea than anything described in Microsoft's docs (which don't state how the tool handles a first-ever run or a corrupted history record). Nothing to change here. |
| **History persistence model** | Tied to a signed-in Microsoft Learn profile; explicit warning that "assessments... can't be transferred to or accessed by other profiles" — i.e., centralized, identity-bound, but also portability-limited | A local, append-only `findings-history.json` file under a caller-supplied `-HistoryPath`, one compact record per run, replace-on-rerun for the same `RunId` (lines 209–221) | **Different trade-off, not simply worse.** No sign-in requirement and no vendor lock to a profile — the history travels with the output folder/`-HistoryPath`, which fits azure-scout's offline/corpus-driven model (per `corpus-tenant-data-dump.md` in memory) better than a cloud-profile-bound history would. The gap is narrower than it looks: what Microsoft gets from sign-in-binding is cross-device continuity without the customer managing a file; azure-scout could approximate that by documenting/standardizing where `-HistoryPath` should live per tenant (e.g., committed alongside the corpus) rather than by adopting sign-in. Not recommending a redesign here — flagging it as the one open question, not a confirmed gap. |
| **Per-finding drift classification** | Not specified at this granularity in any Microsoft source reviewed | New/Resolved/Regressed/Unchanged per finding id, plus a `Removed` count for findings that dropped out of scope between runs (lines 23–29, 173–181) | **azure-scout has a feature Microsoft's docs don't describe at all** — this four-state-plus-removed classification is more granular than anything sourced this session from Microsoft's own materials. Worth stating as a strength in the report, similar to the stable-id point above. |

**Net finding**: two real, cheap-to-close gaps (human-meaningful run naming, a stated re-assessment
cadence shown to the reader) and one open design question (whether to standardize/document
`-HistoryPath` placement to approximate cross-device continuity) — set against two areas where
`Get-ScoutDrift.ps1` is already equal to or more capable than what Microsoft's own tooling is
documented to do (baseline handling, per-finding drift granularity). This is not a "we're behind on
Drift" finding — it's a "the labels and the stated cadence are missing, the mechanics are solid"
finding.

---

## Sources

- https://github.com/GetToThe-Cloud/documenter-azure-landingzone (README, via WebFetch)
- https://raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-landingzone/main/index.html
- https://raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-landingzone/main/app.js
- https://raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-landingzone/main/waf-config.json
- https://github.com/GetToThe-Cloud/documenter-azure-local (README, via WebFetch)
- https://raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-local/main/index.html
- https://raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-local/main/app.js
- https://raw.githubusercontent.com/GetToThe-Cloud/documenter-azure-local/main/waf-config.json
- https://github.com/GetToThe-Cloud/documenter-azure-azurevirtualdesktop (README, via WebFetch)
- https://azuredocumenter.com
- https://www.gettothe.cloud/tool-azure-landing-zone-documenter/
- Microsoft Assessments sources for §8 are cited in full in `pmo/research/microsoft-assessment-methodology.md` §10; key ones: https://learn.microsoft.com/en-us/assessments/support/, https://learn.microsoft.com/en-us/assessments/browse/?page=1&pagesize=30, https://raw.githubusercontent.com/Azure/WellArchitected-Tools/main/WARP/devops/Azure_Well_Architected_Review_Sample.csv, https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations
