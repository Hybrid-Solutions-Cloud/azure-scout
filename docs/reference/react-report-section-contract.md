---
description: The contract a section of the React report must satisfy — the v6 page structure, the register completeness rule, and how an assessment is added without touching the shell.
---

# The React report — section contract

**Status:** normative. Work item **AB#6936** (the React report framework), Feature AB#6928.
Describes the **v6** information architecture shipped in v3.5.0.

::: danger The React report is the one supported deliverable
Word, PDF, Excel, PowerPoint, Power BI, the standalone HTML renderer and the Markdown-file
renderer are **on hold** (**AB#6922**) and are not emitted. They are being rebuilt to generate
*from* this report rather than alongside it. Export to Markdown, JSON, CSV, PDF (print) or a
standalone HTML copy **from the report page itself**. `Json` / `JsonEvidence` are data, not
documents, and are never held. See [Report tiers](../assessment/configuration.md#report-tiers).
:::

This is the contract a report section must satisfy. It exists so that **adding an assessment is a
payload change plus, at most, one registered renderer — never an edit to the shell**.

If you find yourself editing navigation, view depth, theming, export, or the diagram kernel in
order to add an assessment, the contract has been broken. Fix the contract, not the shell.

---

## 1. The information architecture (v6)

The report is a **multi-page application inside one self-contained HTML file**. Page visibility is
driven by `data-page` on `<body>`; there is no routing, no fetch, and no second file. The top nav
is built from what actually ran — a page whose data is absent is not offered.

| Page | `data-page` | What it carries |
|---|---|---|
| **Overview** | `ov` | The collection-details strip (scope, tenant, timings, what was skipped and why — a strip on this page, **not** a global banner), the lede and KPI row, menu tiles into every other page, one gauge tile per assessment, and a single "act on this first" spotlight. |
| **Inventory & audit** | `inv` | A blade sidebar over the estate — see §2. |
| **Assessments** | `as` | Landing tiles: gauge, verdict sentence, area preview, pass/fail/manual counts. Each tile opens a per-assessment page. |
| **Per-assessment** | `a-<slug>` | The full conformance register for one assessment — see §3. |
| **Diagrams** | `dgm` | Blade-navigated figures: management-group hierarchy, VNets and subnets with IP-utilisation bars, estate top-10 bars, gaps-by-area severity bars. Each figure has a KPI context strip and a lede; nodes click through to the underlying blade; ⛶ opens a full-screen overlay with wheel zoom, drag pan, Fit and Esc. All inline SVG. |
| **Data & drift** | `data` | The unabridged all-findings table (fails ranked first), the evidence table, cross-run drift KPIs and tables, and provenance. |
| **Remediation plan** | `road` | Every fail, twice: a 90-day plan by area, and workstreams by team with a t-shirt size. Rows link back to their gap blocks. |

Orthogonal to the pages, and owned by the shell:

- **View depth** — Executive / Consultant / Data, set by `data-view` on `<body>`. This is a *depth*
  control, not a page: the same DOM, three amounts of it. Executive leads with the conclusion and
  a top-gaps summary; Consultant is the delivered engagement chapter; Data is everything,
  filterable and exportable, with nothing summarised away.
- **Theme** — light / dark, via CSS custom properties. Contrast floors are asserted, so a section
  must use the tokens rather than hard-coded colours.
- **Export** — Markdown, JSON, findings CSV, evidence CSV, Print/PDF, and a standalone HTML copy.
  Export walks the section registry; a section outside the registry silently vanishes from every
  export.

## 2. The inventory blade model

The Inventory & audit sidebar is **the eighteen documented categories, in fixed order, under their
Azure portal labels** — the taxonomy is defined once in
[Category Structure](./category-structure.md) and must not be re-derived or reordered here.

- Payload keys map onto those eighteen by `keyCat()`: RBAC / PIM / classic administrators →
  **Identity**; `governance.*` → **Management and governance**; Log Analytics and operational
  posture → **Monitor**; `domains.<x>` → its own category; Advisor, subscriptions and tags →
  **General**.
- Cost cleanup and FinOps datasets are **not** categories. They belong to the cost-optimization
  blade only.
- **A zero is listed, not hidden.** A category with no resources appears dimmed and opens an
  *absence* blade stating that the estate has none of that type — as distinct from the collector
  having failed, which the audit-callouts blade reports separately.
- Group summary blades sit above the category blades; the Tenant structure blade carries the
  management-group tree and subscriptions; the Cost optimization blade carries the opportunity
  arithmetic, cost checks with links back to their fix, Advisor cost rows, the FinOps dataset
  table with an empty-reason per dataset, and the cleanup tables.
- Category tables are filterable and sortable, bounded to a 480px scroll with a sticky header, and
  ellipsise at 80 characters with the full value on hover. Columns are chosen by density, not
  hard-coded per category.

## 3. The register completeness rule

**This is the rule the report exists to satisfy.** The owner's verdict on an earlier draft —
*"fancy marketing sites, not deep"*, a page showing 2 of 139 checks — is why it is normative.

A per-assessment page is a **complete conformance register**, not a highlights reel:

1. **Every check is listed.** Passes, fails and manual checks all appear in the register table for
   their area. A check that ran and passed is evidence of work done; omitting it makes the report
   unfalsifiable.
2. **Every fail gets a gap block.** Not the top five, not the criticals — every one. A gap block
   carries the evidence table (capped at 12 rows, with the true count stated), or the absence
   sentence where the finding *is* the absence; why it matters; a numbered fix; and the per-check
   Learn link.
3. **Every manual check is listed with the question it asks**, in the area's manual agenda. A
   manual check is an interview item, not a gap in the report.
4. **Scores show their arithmetic.** `percent` never appears without `formula`, `denominator` and
   `excludedCount` beside it — the Microsoft Secure Score pattern. The owner's review of an
   unexplained "10/10" is why this is non-negotiable.
5. **"What's next" closes the page** — a START HERE item, then per-domain Action / Owner / Window
   rows, each linking back to the gap block it came from.

Completeness must never regress for presentation. If a view depth needs to be shorter, it
summarises *above* the register; it does not delete rows from it.

Page structure, in order: breadcrumb → banded gauge with its formula → area band panel →
collapsible area chapters (register table → gap block per fail → manual agenda) → the
Executive-depth top-gaps summary → What's next.

## 4. What the shell owns, and you do not touch

| Concern | Owned by | Why you must not fork it |
|---|---|---|
| Pages and nav | `renderNav()` / `setPage()`, built from `ran` | Nav is derived from what actually ran. A hand-added entry desynchronises from the payload. |
| View depth (Executive / Consultant / Data) | `data-view` on `<body>` | One DOM, three depths. A section that renders its own switch breaks print and export. |
| Theme / palette | CSS custom properties | Contrast is measured and asserted. Hard-coded colours bypass the WCAG floors. |
| Export (Markdown / JSON / CSV / Print / standalone HTML) | the export menu and the section registry | Export walks the registry; an unregistered section vanishes from every export. |
| Diagrams | `window.__SCOUT_DIAGRAM_KERNEL__` | The kernel guarantees no text/box overlap and no line routed through a box. Hand-rolled SVG is not collision-checked. |
| Escaping | `esc()` | Everything rendered is untrusted tenant data. See §7. |

## 5. The payload shape a section receives

Everything renders client-side from `window.__SCOUT_DATA__`, emitted by
`src/report/renderers/Export-React.ps1`. An assessment entry in `assessments[]`:

```
{
  slug, name, framework,
  scope:   { checksTotal, ... },
  areas:   [ { name, percent, formula, denominator, excludedCount, weight } ],
  findings:[ { id, title, severity, status, area, remediation,
               learnUrl, weight, evidenceCount,
               evidence: [ { resourceName, resourceId, subscriptionId, detail } ] } ]
}
```

**Required of every section:**

1. **`slug` is the identity.** Composite finding ids are `"<slug>:<ruleId>"`. Nav, deep links,
   the per-assessment `data-page` key, export filenames and the resource index all key off it.
   `areas[]` names are deduplicated by `(framework, name)` — two areas called "Security" is a
   payload defect, not something a section works around.
2. **Every field is optional at render time.** Read through `safeArr()` / `dash()` /
   `Get-ReactSafeProp`. A section must render a defensible empty state, never throw. A section
   that throws takes the whole report down with it.
3. **Absence is a result, not a blank.** Many rules are `exists` / `countGreaterThan` assertions
   that fail *precisely because* the query returned nothing — there is no resource to name and the
   finding **is** the absence. Say so in words. Never render an empty evidence table and leave the
   reader to guess whether the check was broken.

## 6. The depth bar (Consultant view)

Set by the reference deliverables. Per chapter:

- a **domain scorecard** with visible arithmetic;
- a **"Current state"** paragraph per area, in prose, stating the score and what is open;
- **findings grouped by area**, not one flat list, priority-ordered (fails first, then severity);
- **at least one figure**, produced by the diagram kernel;
- **evidence naming real resources**, and every finding carrying a `learnUrl`.

## 7. Hard rules

- **Escape everything.** All rendered values pass through `esc()`. Resource names, tags and
  descriptions are attacker-influenceable tenant data in a file that gets emailed to executives.
- **No external requests, ever.** Inline CSS/JS/SVG only. A strict CSP blocks CDNs, and the report
  must render intact from a USB stick on an air-gapped laptop. This is why every figure is inline
  SVG rather than a diagram library.
- **No vendor marketing on the report surface.** Identity comes from the prompted
  company / client / title / classification block. Attribution belongs in the About panel, which
  print CSS hides.
- **No secrets, subscription ids or tenant ids in committed fixtures.**

## 8. Adding a new assessment section

1. Ensure the assessment emits the §5 payload shape. Nothing else is required for it to appear —
   the generic renderer picks it up, it gets a landing tile and an `a-<slug>` page, nav includes
   it, and export covers it.
2. **Only if it needs richer treatment than the generic renderer:** register a custom renderer
   against its slug. Registration is the extension point; editing the dispatch is not.
3. Add a contract test asserting the section renders at all three view depths and survives an
   empty payload.
4. The diagram overlap checker must pass (`tests/ReactReport.DiagramOverlap.Tests.ps1`).

## 9. Verification — how a section is accepted

Rendering without error is not acceptance. A section is done when:

- [ ] **the register is complete** — every check listed, a gap block for every fail, every manual
      check listed with its question (asserted by the completeness gate in
      `tests/Report.PerAssessmentContract.Tests.ps1`);
- [ ] it renders at all three view depths, and the three are materially different;
- [ ] it renders in both light and dark themes;
- [ ] it renders from an **empty** payload without throwing;
- [ ] every score displays its formula, denominator and exclusions;
- [ ] findings name real resources, or state in words why there is nothing to name;
- [ ] every finding carries a working `learnUrl`;
- [ ] at least one figure, drawn by the kernel, passing the overlap checker;
- [ ] it survives Markdown / JSON / CSV / Print / standalone-HTML export with content intact;
- [ ] **a human has opened the artefact.** A non-zero byte count is not evidence — the "0 empty
      artefacts" gate once passed green while the dashboard was blank.
