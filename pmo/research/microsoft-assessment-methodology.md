# How Microsoft assesses and reports Azure Landing Zone / CAF / WAF posture

Research input for the v3.3.4 reporting engine rebuild. Every claim below is sourced.
Scope: report *structure* and *score explanation* patterns Microsoft itself uses — not
general CAF prose.

---

## 1. Azure Landing Zone Review (learn.microsoft.com/assessments)

- **What it is**: a self-service questionnaire, ~30 minutes, multiple-choice/multiple-response,
  that reviews "Azure platform readiness" and the customer's landing zone plan. Designed for
  customers with 2+ years of Azure experience, but usable earlier to find investment areas.
  Source: [Azure Landing Zone Review](https://learn.microsoft.com/en-us/assessments/21765fea-dfe6-4bc4-8bb7-db9df5a6f6c0/), [Azure Essentials show walkthrough](https://learn.microsoft.com/en-us/shows/azure-essentials-show/assess-your-cloud-environment-with-the-azure-landing-zone-review).
- **Results page contents** (per the Microsoft Assessments platform FAQ, which governs every
  assessment on the platform including this one):
  1. An **overall score** used to benchmark "where you are on your journey."
  2. **Curated next steps and tailored recommendations per category**, each with a link to
     supporting Learn documentation.
  3. A **share/export mechanism** — social sharing, and CSV export when signed in.
  4. The design intent stated explicitly: "help you determine what concrete actions you can
     take to improve your journey" — i.e., the score exists to justify a call to action, not
     as an end in itself.
  Source: [Microsoft Assessments FAQ — what information does the results page provide](https://learn.microsoft.com/assessments/support/#what-is-microsoft-assessments).
- Retaking the assessment and tracking score-over-time is a first-class feature — the tool
  assumes the customer will act, then re-run, then compare.

**Takeaway for azure-scout**: every Microsoft assessment result page pairs *score → recommendation
→ link to guidance → path to re-measure*. A score with no adjacent "what to do about it, and where
it comes from" is not the Microsoft pattern.

---

## 2. Azure landing zone design areas (CAF Ready) — what "compliant" means per area

The Azure landing zone conceptual architecture is organized into **eight lettered design areas**
(A–I, skipping D/H in the current diagram), each with a stated objective a review can be scored
against:

| Area | Design area | Objective |
|---|---|---|
| A | Azure billing and Microsoft Entra tenant | Correct tenant creation, enrollment, and billing setup |
| B | Identity and access management | The primary security boundary in the public cloud |
| C | Resource organization | Subscription design and management-group hierarchy that scales |
| E | Network topology and connectivity | Foundational networking decisions |
| — | Resource organization / Governance | Mechanisms and processes for maintaining control over platforms, apps, resources |
| — | Security | Security is a first-class design area, cross-cutting through greenfield/brownfield guidance |
| — | Management | Operations, monitoring |
| — | Platform automation and DevOps | IaC and automated landing zone deployment |

Sources: [Azure landing zone design areas and conceptual architecture](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas), [Design area: Azure governance](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/governance), [Design area: Security](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/security), [Azure Virtual Desktop landing zone design guide — "eight design areas"](https://learn.microsoft.com/azure/architecture/landing-zones/azure-virtual-desktop/design-guide).

Each design-area article follows the same fixed sub-structure: **Design area overview → Design
considerations → Design recommendations**, so "compliant" per area means: the environment's
configuration matches the stated recommendations for that area, not an arbitrary numeric
threshold. There is no official CAF numeric weighting of the eight areas relative to each other —
weighting is introduced downstream, by the review tooling (see §3) or by MCSB/Secure Score (§6),
not by the CAF conceptual model itself.

**Takeaway for azure-scout**: the product's per-assessment structure (Identity, Networking,
Governance, Security, Management, DevOps, Resource Organization, Billing) already mirrors these
eight areas by name. The report should say so explicitly — map each azure-scout assessment
category to its CAF design-area name and link, so the reader can verify the report is following
a documented Microsoft taxonomy rather than an invented one.

---

## 3. Azure Review Checklists (github.com/Azure/review-checklists) — the ALZ checklist schema

This is Microsoft's own open-source tool for doing landing zone / WAF design reviews at scale
(used internally by Microsoft field teams and partners). It is the closest real-world analogue
to what azure-scout produces.

- **Item schema** (from `checklists/alz_checklist.en.json`), one JSON object per checklist row:

  | Field | Purpose | Example |
  |---|---|---|
  | `guid` | Stable identity for the check, survives renumbering | `70c15989-c726-42c7-b0d3-24b7375b9201` |
  | `id` | Human-readable item code, tied to the design-area letter | `A01.01` |
  | `category` | Design area | `Azure Billing and Microsoft Entra ID Tenants` |
  | `subcategory` | Sub-topic within the area | `Microsoft Entra ID Tenants` |
  | `text` | The actual recommendation being checked | "Use one Entra tenant for managing your Azure resources…" |
  | `description` | Optional longer explanation | — |
  | `severity` | High / Medium / Low | `Medium` |
  | `waf` | Which WAF pillar the item maps to | `Operations` |
  | `service` | Azure service the item concerns | `Entra` |
  | `link` | Deep link to the CAF/Learn guidance for this exact item | `https://learn.microsoft.com/azure/cloud-adoption-framework/...` |
  | `training` | Optional Microsoft Learn training module link | — |
  | `graph` | Optional Azure Resource Graph KQL query that can auto-detect the item | — |
  | `ammp` | Boolean flag marking the item in-scope for the Azure Migration and Modernization Program variant | — |

  Source: [Azure/review-checklists](https://github.com/Azure/review-checklists), raw schema inspection of `checklists/alz_checklist.en.json`.

- **Reporting mechanism**: the JSON compiles into an Excel workbook. Reviewers work row by row —
  either area-by-area (Networking, then Security, etc.) or severity-first (all High items across
  every area first) — setting a status per row and adding a Comments field to record remediation
  owner or the reason a deviation is accepted. A **Dashboard worksheet** aggregates status counts
  into a graphical "review progress" view. There's also an Azure Monitor workbook and a
  Power BI path for the same data. Source: [Azure/review-checklists README](https://github.com/Azure/review-checklists).

**Takeaway for azure-scout**: this is the closest Microsoft-native precedent for a per-finding
evidence table. Azure-scout's findings should carry the same fields this schema treats as
load-bearing: a stable id, severity, WAF pillar mapping, and — critically — a **direct link to
the Learn guidance for that exact rule**, not just a category name. Today's reports don't
consistently carry that link (see gap table, §8).

---

## 4. Well-Architected Review assessment — pillar scores and recommendation prioritization

- **Structure**: ~60 questions across the five WAF pillars (Reliability, Security, Cost
  Optimization, Operational Excellence, Performance Efficiency), roughly 60 minutes, informed
  optionally by live Azure Advisor recommendations for the target subscription/resource group.
  Source: [Azure Well-Architected Review](https://learn.microsoft.com/en-us/assessments/azure-architecture-review/), [Complete an Azure Well-Architected Review assessment](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations).
- **Milestones, not a single point-in-time score**: the tool explicitly supports re-running the
  assessment as a "milestone" and comparing it to a prior milestone — brownfield workloads are
  expected to be re-assessed on a cadence (Microsoft's own example: every four months). The
  report is framed as a **continuous-improvement loop diagram**: assess → prioritize → implement
  → re-assess.
- **Recommendation identity and prioritization**: every recommendation carries a pillar code plus
  number (e.g., `SE:05` = Security pillar, article 5), so a reader can trace any single
  recommendation back to the exact WAF guidance article. Recommendations are explicitly
  characterized by **severity, effort, and business impact**, and the guidance surfaces a
  curated **top-5 "priority actions"** — meaningful improvement for manageable effort — rather
  than dumping the full backlog on the reader at once.
- **Export path**: results export to CSV for import into the team's backlog/ADO/GitHub, with a
  published DevOps tooling recipe for that import (`WellArchitected-Tools/WARP/devops`).
- Sources: [Complete an Azure Well-Architected Review assessment](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations), [WAF review assessment updates](https://techcommunity.microsoft.com/blog/azurearchitectureblog/azure-well-architected-review-assessment-updates/3981023).

**Takeaway for azure-scout**: (1) recommendations need a stable pillar+number code the reader can
look up, exactly like `SE:05`; (2) the report should curate a small "top N now" list distinct
from the full findings table — a wall of findings with no ordering is not the Microsoft pattern;
(3) framing every report as one point in a milestone series (even if azure-scout doesn't yet
store history) sets the right reader expectation.

---

## 5. AzGovViz / partner-led ALZ assessments — what's actually delivered

Search for concrete AzGovViz/partner-ALZ-assessment deliverable examples did not surface a
citable, authoritative Microsoft-owned description of the artifact set beyond what's already
covered by the Review Checklists tool (§3) and the ALZ Bicep/accelerator governance defaults
referenced from the CAF governance design-area page. I did not find a primary source strong
enough to state new claims here without weakening the rest of the document's sourcing standard —
flagging this as an open gap rather than asserting something unverified. The CAF governance page
does confirm one relevant fact: **Microsoft's own accelerators (ALZ-Bicep) ship default policy
assignments as the operational expression of "governance design area compliance"** — i.e.,
in Microsoft's own tooling, governance compliance is ultimately checked against Azure Policy
assignment state, not narrative. Source: [Design area: Azure governance](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/governance#design-area-review).

---

## 6. Microsoft Cloud Security Benchmark / Defender for Cloud Secure Score — the "score = weighted controls" pattern

This is the strongest, most concrete precedent for **explaining a score to a reader**, and the
one the v3.3.4 rebuild should copy most directly.

- **Foundation**: Secure Score is generated from MCSB assessment findings. Only built-in MCSB
  recommendations count toward the score; **Preview recommendations are explicitly excluded** and
  labeled as such — this is the "not assessed" handling azure-scout needs.
- **Controls, not raw findings, are the scoring unit**: individual recommendations are grouped
  into named **security controls** (e.g., "Enable MFA," "Secure management ports," "Remediate
  vulnerabilities"). Each control has a **fixed max score**, published in a table, that reflects
  its relative security importance and is constant across every environment — MFA is worth 10
  points everywhere; "Implement security best practices" is worth 0 points everywhere (informational
  only, doesn't move the number).
- **The exact formula, shown to the reader**:
  - Per control: `current score = (max score / total resources in scope) × healthy resources`.
    Example given verbatim in the docs: max score 6, 78 total resources, 4 healthy →
    `6/78 = 0.0769` per resource → `0.0769 × 4 = 0.31` current score.
  - Per subscription: `secure score % = (Σ current scores of all controls) / (Σ max scores of all controls) × 100`.
  - Across multiple subscriptions: a **weighted sum**, not an average of percentages — each
    subscription's weight is its combined healthy+unhealthy resource count. The docs explicitly
    warn readers not to try to hand-recompute the aggregate from the per-control numbers shown in
    the UI, because the weighting isn't visible at that level — the UI already tells the reader
    "the math is more than what you can see, trust the aggregate."
  - **"Not assessed" handling**: if a subscription has zero resources in scope for a given
    control (no healthy or unhealthy resources), that control is dropped entirely from that
    subscription's calculation — neither its current nor its max points are counted. This is the
    concrete precedent for "N/A collectors shouldn't silently count as a zero."
  - **Potential score increase** is shown per control: `(max score/total resources) × unhealthy
    resources` — i.e., exactly what the reader gains by fixing everything in that one control,
    which is how Defender for Cloud tells the reader what to work on first.
- **Presentation**: overall score shown prominently as a single percentage plus its underlying
  numerator/denominator; a dedicated Secure Score page breaks it down per subscription and per
  management group; the Recommendations page's "Secure score recommendations" tab lists every
  control with columns for **Max score / Current score / Potential score increase / Insights**
  (Fix / Enforce / Deny badges); a Power BI "Secure Score Over Time" template tracks the trend and
  even calls out a "detected changes that might affect your secure score" table when the number
  moves, distinguishing real remediation from resource churn.
- Source: [Secure score in Microsoft Defender for Cloud](https://learn.microsoft.com/en-us/azure/defender-for-cloud/secure-score-security-controls) — includes the full worked formula, the fixed max-score table for all 15 controls, and the multi-subscription weighting caveat quoted above.

**Takeaway for azure-scout**: this is the single best model for the "how to read this score"
section the reporting engine needs. It answers, concretely, the numbers azure-scout currently
leaves unexplained:
- Show the **denominator** (how many resources/checks were in scope for this area) next to any
  score, not just the numeric result.
- Publish a **fixed, documented weight per assessment/rule** so a 10/10 always means the same
  thing across tenants (Secure Score's per-control max score is fixed for every environment;
  azure-scout's per-rule severity/weight should be too, and should be printed in the report, not
  just used silently by the scoring engine).
- Treat **rules with zero applicable resources as excluded from the denominator**, and say so in
  the report ("N of M rules not applicable in this tenant") rather than silently scoring them 0
  or 10.
- Show, per area, what the score would become if every open finding in that area were fixed —
  the "potential score increase" column — so remediation prioritization has a number attached,
  not just a severity label.

---

## 7. Cross-cutting pattern across every Microsoft source above

Every artifact examined — the Landing Zone Review results page, the WAF Review milestone/export
model, the Review Checklists dashboard, and Secure Score — repeats the same four elements in the
same order:

1. **A score the reader can audit**: numerator, denominator, and what's excluded and why.
2. **A stable identifier per finding/recommendation** (`A01.01`, `SE:05`, a control name, a
   checklist `guid`) that survives report regeneration and can be tracked over time.
3. **A direct link from the finding to Microsoft's own guidance for fixing it** — never just a
   category name.
4. **A curated, prioritized subset for action** (top 5, "potential score increase," Fix/Enforce/Deny
   badges) that is visibly separate from the exhaustive findings list.

None of the four sources present an unexplained bare score with no legend, and none present an
undifferentiated wall of findings with no ranking.

---

## 8. Gap table — azure-scout today vs. the Microsoft-style pattern

| Microsoft pattern | azure-scout today | Gap / filed bug |
|---|---|---|
| Score shown with numerator/denominator and a legend explaining the scale | `Export-Pptx.ps1`'s Executive Summary renders bare score cards (`Get-ScoutScoreColor`/`Get-ScoutPptxProp 'Score'`) with no denominator, no "N rules assessed, M not applicable" text, no legend slide | Unexplained 10/10 scores with no methodology (already filed) |
| Fixed, documented per-item weight, same across every environment (Secure Score's per-control max) | Assessment rule weights exist in the scoring engine (`src/assess/rules/*.yaml`) but are not surfaced in the rendered report — the reader sees only the rolled-up number | No methodology/legend section in the report (already filed) |
| "Not assessed" / N-A items excluded from the denominator, and disclosed as excluded | Not confirmed as consistently modeled in the renderer output — no visible "N/A" accounting alongside scores | Related to the unexplained-score bug; worth a check during the v3.3.4 methodology section build |
| Dashboard aggregates progress visually (Review Checklists' Dashboard worksheet; Secure Score tile) | Dashboard reported as rendering blank in current output | Blank dashboard (already filed) |
| Every finding/report carries a stable, human-meaningful identity (`A01.01`, `SE:05`, workload name in the WAF assessment title) | Reports have been shipped without a clear per-tenant/per-assessment identifying name | Unnamed reports (already filed) |
| Direct link from each finding to the exact Learn/CAF guidance article for that rule (Review Checklists' `link`/`training` fields) | Findings carry category/severity but link-to-guidance coverage is inconsistent per the collector audit corpus findings memory | Design-input for v3.3.4: add a `link` field to the rule schema, mirroring `alz_checklist.en.json` |
| Curated "priority actions" (WAF's top-5) / "potential score increase" ranking (Secure Score) distinct from the full findings table | Findings render as one flat table with no now/next/later split | Design-input for v3.3.4: add a remediation roadmap section |
| Milestone/re-run framing — score-over-time is a first-class concept | No score-history or trend concept in the current renderer set | Out of scope for v3.3.4 per the corpus-based, single-snapshot rendering model, but worth flagging for the reporting engine's data model going forward |

This maps directly onto AB#6904–6912 as filed (blank dashboard, unexplained 10/10 scores, missing
methodology/legend, unnamed reports) — every one of those four defects is the azure-scout-specific
instance of a pattern Microsoft's own tooling treats as mandatory in all four sources reviewed.

---

## 9. Concrete recommendation for the v3.3.4 per-assessment report structure

Order, modeled directly on the sources above (Secure Score for the scoring math, WAF Review for
the milestone/priority framing, Review Checklists for the finding schema, Landing Zone Review for
the results-page shape):

1. **Cover / title** — tenant name, assessment name, generation timestamp. Every report must be
   self-identifying (closes the "unnamed reports" gap).
2. **Executive summary** — overall score(s) per framework, one sentence per area on direction of
   travel, and the curated "priority actions" list (WAF's top-5 pattern) — not the full findings
   table.
3. **Scoring methodology ("How to read this report")** — a fixed, reusable section, not
   generated per-tenant: explain the scale, state that weights are fixed per rule/design area
   (name where the weight table lives), explain N/A handling and how it's excluded from the
   denominator, and give one worked example in the same style as the Secure Score docs
   (`max / total resources in scope × healthy = current score`). This single section closes the
   "no methodology/legend" gap for every report the engine produces.
4. **Per-design-area scorecard** — one row/card per CAF design area (mapped explicitly to the
   eight design areas in §2, by name, with the Learn link for that area), each showing:
   `current score / max score`, resources or checks assessed, checks not applicable, and the
   "potential score increase if fixed" number, exactly as Secure Score's control table does.
5. **Findings with evidence** — the Review Checklists schema fields per row: stable id,
   category/subcategory, severity, WAF pillar, the resource(s) affected (the evidence), and a
   direct Learn/CAF guidance link per finding, not just per category.
6. **Prioritized remediation roadmap** — now / next / later phases (a defensible way to operationalize
   WAF's severity+effort+impact triage without requiring a live effort-scoring interview), each
   item carrying its Learn link, mirroring WAF Review's CSV-to-backlog export intent even if
   azure-scout's own export is a table rather than a literal CSV handoff.
7. **Appendix** — full raw findings table (the exhaustive list this structure deliberately keeps
   out of the executive summary), collector coverage notes, and the fixed weight table referenced
   in the methodology section.

This gives every report the four cross-cutting elements from §7 — auditable score, stable
identifiers, guidance links, and a curated action list — in the same order Microsoft's own
assessment tooling uses them.

---

## 10. ADDENDUM (2026-08-03 session 2) — the full Microsoft Assessments catalogue and results-page anatomy

The owner pushed back that the earlier sections above didn't scan the full Microsoft Assessments
catalogue or dissect the results page itself, citing the FAQ's "what information does the results
page provide" answer and its labelled screenshot. This addendum closes that gap.

### 10.1 The results-page screenshot is a dead link — flagging, not guessing

The FAQ embeds `![Results page overview.](media/resultspage.png)` at
[learn.microsoft.com/en-us/assessments/support/#what-information-does-the-results-page-provide-](https://learn.microsoft.com/en-us/assessments/support/#what-is-microsoft-assessments).
I fetched that image directly (`https://learn.microsoft.com/en-us/assessments/media/resultspage.png`)
and it returns **HTTP 404** — Microsoft's own docs site serves a "not found" HTML page in its
place, confirmed via a direct `curl` request with response headers showing `HTTP/1.1 404 Not
Found`. I also checked the likely source repo
(`raw.githubusercontent.com/MicrosoftDocs/assessments-pr/live/assessments-pr/support/media/resultspage.png`)
— also 404. **I could not verify any element-by-element description of the annotated screenshot.
Do not treat any description of "the labelled callouts" as sourced — none exists in what I could
retrieve.** The only description of the results page content is the FAQ's prose (already captured
in §1 above and restated in §10.2), which is the actual verifiable content, not the image.

### 10.2 What the results page provides — restated precisely from the FAQ prose (the only verifiable source)

Direct quotes from [learn.microsoft.com/en-us/assessments/support/](https://learn.microsoft.com/en-us/assessments/support/):

> "This page will provide you with an overall score helping you benchmark where you are on your
> journey. It also provides curated next steps and tailored recommendations per category with
> links to additional documentation to read. You can share your assessment's results on social
> media platforms (Twitter, LinkedIn, Facebook, and Email)... The goal is to help you determine
> what concrete actions you can take to improve your journey."

> "Yes. If you're logged in, Assessment results can be share[d] with those you trust. Likewise,
> Assessment results can be exported to a CSV file; which also requires being logged into the
> platform."

So the results page's verifiable content model is: **overall score (for benchmarking) → curated
next steps → tailored recommendations per category, each with a documentation link → social share
→ CSV export (sign-in required for both share and export)**. No further structural detail (e.g.,
where the score sits relative to the recommendations, whether categories are tabs or scroll
sections, whether there's a chart) is stated in text anywhere I could reach — anything more
specific than the above is unverifiable from this source and should not be asserted.

### 10.3 The full assessment catalogue — this is much larger than the 2026 "launch four"

The FAQ's "What assessments are available at launch?" answer (Cloud Journey Tracker, Governance
Benchmark, Well-Architected Review, SMAT) describes the **platform's original 2020 launch set**,
not today's catalogue. The current catalogue, per
[learn.microsoft.com/en-us/assessments/browse/](https://learn.microsoft.com/en-us/assessments/browse/?page=1&pagesize=30)
and [learn.microsoft.com/en-us/assessments/](https://learn.microsoft.com/en-us/assessments/), is
organized two ways simultaneously: by **lifecycle phase** (Define, Plan, Prepare, Adopt, Govern,
Manage) and by **product/workload**. It now spans at minimum (confirmed present, not exhaustive —
the browse page paginates):

- **Strategy/adoption**: Cloud Adoption Strategy Evaluator, Cloud Journey Tracker, Governance
  Benchmark
- **Landing zone / platform**: Azure Landing Zone Review, Azure VMware Solution Landing Zone
  Assessment Review
- **Migration**: Strategic Migration Assessment and Readiness Tool (SMAT/SMART — the FAQ and
  browse page spell the acronym differently, flagging the inconsistency rather than picking one),
  App and Data Modernization Readiness Tool
- **DevOps**: DevOps Capability Assessment
- **AI**: AI Readiness Assessment (7 pillars: Business Strategy, AI Governance & Security, Data
  Foundations, AI Strategy & Experience, Organization & Culture, Infrastructure for AI, Model
  Management), AI Engineer Skill Assessment
- **Data/analytics**: Analytics Journey Tracker
- **Well-Architected — one "Core" review plus at least 10 workload-specific variants**, confirmed
  from [the WAF implementation guide's own list](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations#specialized-well-architected-reviews):
  Core Well-Architected Review, AI workload, Analytics, Azure AI Search, Azure Virtual Desktop
  workload, Data Services, SaaS workload, plus (from the browse page) Azure Machine Learning,
  Azure Local, Azure VMware Solution workload, Oracle on Azure IaaS workload, and a separate
  "Well-Architected Framework Maturity Model Assessment."
- **Partner-enablement assessments** (a distinct category, not customer-facing posture
  assessments): Azure Virtual Desktop \| Microsoft Partner, Azure Stack HCI \| Microsoft Partners,
  Azure VMware Solution (AVS) \| Microsoft Partner, Microsoft Cloud for Retail/Sustainability
  Adoption Guides \| Microsoft Partners.
- **Non-Azure-infra**: Power Platform Solution Assessment.

**This directly answers the owner's question "did you scan all their WAF/CAF assessment tools":
no single "WAF/CAF assessment" exists as one tool — Microsoft ships one Core WAF Review plus 10+
technology-specific WAF variants (AVD, AVS, AI, SaaS, Analytics, Data Services, Oracle, Azure
Local, Azure ML, Azure AI Search), each reusing the same five-pillar structure and results-page
mechanics documented in §1/§4/§10.2, scoped to that workload type's own ~30–60 question set.**
azure-scout's per-assessment-category structure is closer to this "one framework, many scoped
instances" model than to a single monolithic assessment — worth stating explicitly in the report's
methodology section.

Sources: [Assessments home](https://learn.microsoft.com/en-us/assessments/), [Assessments browse
page](https://learn.microsoft.com/en-us/assessments/browse/?page=1&pagesize=30), [WAF
implementation guide — specialized reviews list](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations#specialized-well-architected-reviews).

### 10.4 What a Microsoft recommendation looks like as a unit — the exact CSV schema (verified, not inferred)

I pulled the actual sample export file Microsoft ships with its own DevOps import tooling:
[`Azure_Well_Architected_Review_Sample.csv`](https://raw.githubusercontent.com/Azure/WellArchitected-Tools/main/WARP/devops/Azure_Well_Architected_Review_Sample.csv)
in [Azure/WellArchitected-Tools](https://github.com/Azure/WellArchitected-Tools). This is the
CSV export contract in question #5 below, and it's also the ground truth for what a
"recommendation as a unit" contains — more precise than any prose description could be.

**Header row, verbatim:**
```
Category,Link-Text,Link,Priority,ReportingCategory,ReportingSubcategory,Weight,Context,CompleteY/N,Note
```

**Sample data rows, verbatim:**
```
Reliability,"RE:04 - Define healthy, degraded, and unhealthy states.",https://learn.microsoft.com/azure/well-architected/reliability/metrics#building-a-health-model,High,RE:04,,80,,N,
Security,SE:05 - Secure high-impact accounts.,https://learn.microsoft.com/azure/well-architected/security/identity-access#critical-impact-accounts,High,SE:05,,100,,N,
```

The file also opens with a small header block above the data table giving per-pillar rollups,
e.g. `Your overall results,Critical,'0/120'` and `Reliability,Critical,'0/200'` — a
criticality-banded score (not a bare percentage) sits above the recommendation rows in the same
file.

**So a Microsoft recommendation-as-a-unit is exactly 10 fields:**

| Field | What it is | azure-scout equivalent today |
|---|---|---|
| `Category` | The WAF pillar name (Reliability, Security, ...) | We have this (assessment category) |
| `Link-Text` | The recommendation title, already including its pillar code, e.g. `"RE:04 - Define healthy, degraded, and unhealthy states."` | We render title + severity + remediation text — no pillar+number code prefix baked into the title |
| `Link` | Direct URL to the Learn guidance for that exact recommendation | Per the prior session's audit, link-to-guidance coverage is inconsistent (§8 of this doc) |
| `Priority` | A banded value (`High` seen here) — not a raw score | We show severity, comparable |
| `ReportingCategory` | The stable code (`RE:04`, `SE:05`) — this is the identifier that survives a re-run | **We do not have this.** This is the single biggest structural gap: a stable per-recommendation code separate from its prose title |
| `ReportingSubcategory` | Present as a schema field but empty in both sample rows — a finer-grained bucket under the code, apparently rarely used | Not applicable / no equivalent needed |
| `Weight` | A numeric weight per recommendation (`80`, `100` in the samples) — this is the scoring contribution, exposed in the raw export even though the live UI (per §6 of this doc, Secure Score) tends to hide the arithmetic | Assessment rule weights exist in `src/assess/rules/*.yaml` but aren't surfaced in the rendered report (already a filed gap, §8) |
| `Context` | Present as a schema field, empty in the samples — presumably free text for where in the workload the recommendation applies | No direct equivalent found |
| `CompleteY/N` | A remediation-tracking flag — `N` in both samples, meant to be edited by the customer as they work the backlog | We don't ship a field for the customer to mark remediation progress inside the artifact itself |
| `Note` | Free-text field for the customer's own annotation, empty in samples | No direct equivalent |

**Answering question 1 directly: what azure-scout is precisely missing versus this unit is (a) a
stable per-recommendation code distinct from the title (`RE:04` style), (b) a numeric weight
exposed alongside the recommendation rather than only used internally by the scoring engine, and
(c) two customer-editable fields (`CompleteY/N`, `Note`) that make the exported artifact a working
document rather than a read-only report.** We already have category, a link (inconsistently), and
priority/severity — those three are not gaps.

Sources: [Azure_Well_Architected_Review_Sample.csv, raw](https://raw.githubusercontent.com/Azure/WellArchitected-Tools/main/WARP/devops/Azure_Well_Architected_Review_Sample.csv), [Azure/WellArchitected-Tools WARP/devops README](https://github.com/Azure/WellArchitected-Tools/tree/main/WARP/devops#readme).

### 10.5 How recommendations are prioritized and grouped (question 2)

From [Complete an Azure Well-Architected Review assessment](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations),
fetched directly this session:

- Grouping is **by pillar first** (`Category` in the CSV), then by the `ReportingCategory` code
  within a pillar (`RE:04`, `SE:05`, etc. — these codes correspond one-to-one with numbered
  articles in the WAF pillar guidance).
- There is **no single Microsoft-computed "do these first" ranking baked into the export** — the
  CSV's `Priority` column (`High` in the samples) is the only ordering signal Microsoft ships in
  the data itself. The doc is explicit that final prioritization is a **human judgment step**:
  "Workload owners and key stakeholders should prioritize the recommendations in accordance with
  the team's standard work prioritization process, factoring in the applicability of the
  recommendations and any tradeoffs." A recommendation can explicitly be "assigned to a specific
  owner," "postponed," or "dismissed" — i.e., the tool hands over a prioritized-by-severity list
  and expects the workload team, not the tool, to do the final triage.
- This **corrects/nuances a claim in §4 of this document** (the "curated top-5 priority actions"
  characterization) — I could not re-find a citable source this session that shows Microsoft's
  tooling auto-generating a top-5 list; what is verified is the `Priority` banding (`High` etc.)
  plus pillar/code grouping, and an explicit statement that final ranking is left to the reader.
  Treat the "top-5" framing in §4 as **unverified** going forward unless a fresh primary source is
  found — the WAF review updates blog cited there should be re-checked before repeating that claim.

**Answering question 2 directly:** grouping is by pillar → by numbered code. Prioritization is a
`Priority` band (High/Medium/Low, inferred from the one visible value `High`) computed by the
tool, but the final "do these first" ordering is explicitly left to the customer's own backlog
process, not auto-curated by Microsoft into a fixed top-N list in what I could verify.

### 10.6 How the score is presented so the reader trusts it (question 3)

Two distinct, verified patterns exist depending on which Microsoft tool you look at:

1. **Banded criticality score with a fraction, shown per pillar, above the recommendation table**
   (WAF Review CSV export, §10.4): `'0/120'` overall, `'0/200'` Reliability, `'0/100'` Security —
   a **numerator/denominator pair with a criticality label** (`Critical`), not a bare percentage.
   This matches and reinforces the Secure Score numerator/denominator pattern already documented
   in §6 of this file — it's now confirmed as a second, independent Microsoft source doing the
   same thing (raw score + max score shown together, never just a percentage).
2. **Benchmark framing** (results-page FAQ, §10.2): the score's stated purpose is "helping you
   benchmark where you are on your journey" — Microsoft frames the number as a position-in-journey
   marker, not an absolute pass/fail grade.
3. **Progress-over-time framing** (§10.7 below) — trust is also built by showing the score is
   expected to move, and giving the reader the mechanism (milestones) to prove it moved because of
   their own remediation work, not measurement noise.

**Answering question 3 directly:** numerator/denominator with a banded label, framed explicitly as
a benchmark/journey marker rather than a final grade, backed by an explicit re-measurement
mechanism (milestones) so the reader can verify movement is real. No per-category weighted
contribution breakdown was found in the WAF Review sources this session beyond the per-pillar
fraction already shown in the CSV header block — Secure Score (§6) remains the stronger source for
per-control contribution math specifically.

### 10.7 Milestones / retake / comparison — how it compares to azure-scout's Drift tab (question 4)

From the same implementation guide, verified this session:

- "Use the milestone feature of the assessment to track this change over time, using the prior
  milestone as a baseline."
- Sign-in is a hard requirement for milestones: "You should always sign in when you take
  assessments so that the tool can generate milestones," and a stated cross-profile limitation:
  "Assessments are tied to a Microsoft Learn profile. They can't be transferred to or accessed by
  other profiles."
- A **recommended cadence is given explicitly for brownfield workloads**: "Set a cadence, for
  example every four months, and use milestones to track how the workload design can continue to
  improve."
- Naming discipline is called out as a tip: "Use meaningful milestone names to indicate when
  you're evaluating the workload" and "Choose a meaningful name for the assessment... include the
  workload's name" — i.e., Microsoft's own guidance treats an unnamed/un-timestamped assessment
  run as an anti-pattern, directly reinforcing the "unnamed reports" gap already filed against
  azure-scout in §8.
- The improvement loop is explicitly drawn as a diagram: assess → prioritize → implement →
  re-assess, with the milestone comparison as the mechanism that closes the loop.

**No further detail on the comparison UI itself** (e.g., whether it's a side-by-side table, a line
chart, a diff view) was recoverable from the text-only fetch of this page — that would require
rendering the live authenticated tool, which is out of scope here. Flag this as unverified.

**Answering question 4 directly, and how it compares to our Drift tab:** Microsoft's milestone
model is (a) named runs, (b) an explicit recommended cadence stated to the user, (c) prior-run as
baseline, (d) tied to sign-in/profile identity so history persists centrally rather than being a
one-off artifact. Whatever azure-scout's Drift tab already does structurally, the concrete
Microsoft-sourced additions worth checking it against are: does it **name each run** meaningfully,
does it **state a recommended cadence** to the reader (Microsoft explicitly tells the user "every
four months" — a number, not just "re-run periodically"), and does it make **prior-run-as-baseline**
explicit rather than implicit. I did not re-open the Drift tab's current implementation this
session to compare feature-for-feature — that comparison should be done directly against
`src/report/renderers/` by whoever owns that file, using this list as the checklist.

### 10.8 CSV export contract — answered fully in §10.4

Restating for question 5's exact ask: the column list is
`Category, Link-Text, Link, Priority, ReportingCategory, ReportingSubcategory, Weight, Context, CompleteY/N, Note`
— 10 columns, plus a small non-tabular header block above the data giving `Your overall results`
and per-pillar `'current/max'` fractions with a criticality label. Source quoted verbatim in
§10.4.  This is a **cheap, concrete target to match or beat**: azure-scout's CSV export should be
checked against this 10-column shape specifically for the two customer-workflow columns Microsoft
includes that a pure report-generator wouldn't think to add — `CompleteY/N` and `Note` — since
those are what make the export usable as a working backlog artifact rather than a snapshot.

---

## Sources

- [Azure Landing Zone Review](https://learn.microsoft.com/en-us/assessments/21765fea-dfe6-4bc4-8bb7-db9df5a6f6c0/)
- [Assess your cloud environment with the Azure Landing Zone Review (show)](https://learn.microsoft.com/en-us/shows/azure-essentials-show/assess-your-cloud-environment-with-the-azure-landing-zone-review)
- [Microsoft Assessments — Frequently asked questions](https://learn.microsoft.com/assessments/support/)
- [Azure landing zone design areas and conceptual architecture](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas)
- [Design area: Azure governance](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/governance)
- [Design area: Security](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/security)
- [Azure Virtual Desktop landing zone design guide](https://learn.microsoft.com/azure/architecture/landing-zones/azure-virtual-desktop/design-guide)
- [What is an Azure landing zone?](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [Azure/review-checklists (GitHub repo)](https://github.com/Azure/review-checklists)
- [alz_checklist.en.json (raw schema)](https://raw.githubusercontent.com/Azure/review-checklists/main/checklists/alz_checklist.en.json)
- [Azure Well-Architected Review](https://learn.microsoft.com/en-us/assessments/azure-architecture-review/)
- [Complete an Azure Well-Architected Review assessment](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations)
- [Azure Well-Architected Review Assessment Updates (Community Hub)](https://techcommunity.microsoft.com/blog/azurearchitectureblog/azure-well-architected-review-assessment-updates/3981023)
- [Secure score in Microsoft Defender for Cloud](https://learn.microsoft.com/en-us/azure/defender-for-cloud/secure-score-security-controls)
- [Microsoft Assessments home](https://learn.microsoft.com/en-us/assessments/)
- [Microsoft Assessments browse/catalogue page](https://learn.microsoft.com/en-us/assessments/browse/?page=1&pagesize=30)
- [Microsoft Assessments FAQ — results page + CSV export](https://learn.microsoft.com/en-us/assessments/support/)
- [Azure/WellArchitected-Tools — WARP/devops README](https://github.com/Azure/WellArchitected-Tools/tree/main/WARP/devops#readme)
- [Azure_Well_Architected_Review_Sample.csv (raw)](https://raw.githubusercontent.com/Azure/WellArchitected-Tools/main/WARP/devops/Azure_Well_Architected_Review_Sample.csv)
- [Complete an Azure Well-Architected Review assessment — specialized reviews list](https://learn.microsoft.com/en-us/azure/well-architected/design-guides/implementing-recommendations)
- Unverifiable this session (flagged, not asserted): `https://learn.microsoft.com/en-us/assessments/media/resultspage.png` — returns HTTP 404 as of 2026-08-04, confirmed via direct `curl` fetch with response headers.

## Repo cross-reference

- Current executive-summary/score-card rendering: `D:\git\thisismydemo\azure-scout\src\report\renderers\Export-Pptx.ps1` (score cards ~line 979, per-area score table ~line 1072, no methodology/legend slide, no denominator shown).
- Assessment rule definitions (where fixed weights should live/be surfaced): `D:\git\thisismydemo\azure-scout\src\assess\rules\*.yaml`.
