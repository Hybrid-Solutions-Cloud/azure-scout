# Handoff

## Session 2026-08-04 (later) — v3.5.1: three defects v3.5.0 believed were fine

All three were found by *using* the product or by auditing claims, not by reading test output.

1. **The wizard offered every format except React.** `Start-AZSCWizard.ps1` chose the
   assessment format list only when assessment was selected *and inventory was not*, so the
   commonest path of all — Inventory **and** Assessment — fell through to the inventory-only
   list, which contains no React. The assessment list it skipped still offered six held
   renderers, defaulting to `Html`. Fixed to offer `React`/`Json`/`JsonEvidence` on any
   assessment run, defaulting to React. `tests/Assessment.MenuHonesty.Tests.ps1` now parses
   `$script:ScoutHeldRenderers` and fails if the menu offers a held format — proved to bite by
   stashing the fix and re-running (3 real failures naming `Html`).
2. **`Compare-Benchmark` crashed on any tenant with MGs but no policy assignments** —
   `policyAssignments.properties.displayName` over an empty array resolves against the array
   object under StrictMode. 1 of 8 corpus tenants (ptlmgmt) produced no report at all.
   Fixed with `ForEach-Object`; regression test in `Assessment.Governance.Tests.ps1`; all 8
   tenants now render.
3. **The diagram-overlap gate inspected zero diagrams.** `tests/diagram-fixture-build.mjs`
   wrote flat keys; the template and real payload use dotted paths. Fixture builder corrected
   (the template is the payload contract's source of truth). Checker now reads 13 nodes / 9
   edges of network topology and 18 / 17 of MG hierarchy, and was proved to fail on a
   manufactured overlap.

**Lesson worth keeping**: a held-renderer decision must be enforced at *every* surface that
names a format — core, parameters, docs **and** the interactive menu; and a green gate is
worth nothing until you have watched it fail.

### Also this session

- Mockup **v7** adds four network diagrams (VNet hub-and-spoke with unpeered VNets flagged,
  hybrid site-to-site, private link & DNS, internet exposure) — the owner's standard is that
  **the mockup is the contract**, and that approved elements are added to, never replaced.
- **The connectivity gap**: the assessment collect carries a peering *count* rather than the
  pairs, and the VPN gateway but not its connections — while the inventory pipeline already
  has 21 networking collectors holding that relationship data. Board: **AB#7050** with tasks
  **AB#7051–7058** (collect peering pairs / VPN connections / ExpressRoute + vWAN / route
  tables; render connectivity, hybrid, edge-and-delivery, private-link).
- Board hygiene: 11 report items reparented off the closed AB#6878 onto AB#6928; AB#6906
  closed (one file per run, not per assessment); AB#6913 and AB#7026 closed; AB#6936 reopened
  after an audit found its "every view" criterion unmet.


## Session 2026-08-04 — v3.5.0 shipped: the v6 multi-page React report

The owner iterated the target-state mockup through v3→v6 (complete conformance register →
multi-page IA → blade inventory on the 18-category taxonomy → Diagrams page → exports/theme),
approved v6 verbatim ("lets code this exactly like this"), and it was implemented, verified,
merged and released the same day.

### Shipped (PR #245, squash-merged to main; tag v3.5.0; PSGallery published; installed locally)

- `src/report/templates/report-react.html.template` — fully rewritten to the v6 page model:
  Overview / Inventory & audit / Assessments / Diagrams / Data & drift / Remediation plan,
  client-side from `window.__SCOUT_DATA__`. Blade inventory (18 documented categories with
  portal labels, zeros listed with absence blades, filter+sort item tables, tenant structure,
  audit callouts, full cost-optimization blade), complete register per assessment (gap block
  per fail, manual agenda, What's-next), Diagrams page (kept the collision-free diagram
  kernel for MG/VNet; estate + gaps bars ported; full-screen zoom/pan overlay), view-depth +
  theme toggles, Markdown/JSON/CSV exports.
- `src/report/renderers/Export-React.ps1` — R-04 conformance fix only: the `Get-Score` call
  for per-assessment slices replaced with an inline (Framework|Area) status tally over the
  already-scored findings. Payload unchanged (it already carried everything v6 needs).
- Docs: every report page states all other assessment formats are ON HOLD (the inventory
  pipeline's Markdown/AsciiDoc/Excel exports are NOT held and say so);
  `docs/reference/react-report-section-contract.md` rewritten to the v6 IA; version-sync
  ledgers (RELEASES.md, docs/project/roadmap.md, docs/project/changelog.md) carry 3.5.0.
- Also on the branch and now in main: the JToken evidence fix (3%→82% named evidence),
  learnUrl+weight on findings, AHB collector fields + FINOPS-O04 (AB#7035), report identity
  parameters.

### Verification

React 55/55; Conformance + PerAssessmentContract + DiagramOverlap green (123/123 after the
R-04 fix); CI green on the merge commit (2,932 passed); full local suite green apart from the
documented installed-module collision noise; browser walk of the rendered template against
the real tppoc corpus payload (all pages, 55/55 gap blocks). Docs build green.

### The mockup lineage (for future design iterations)

`D:\tmp\azure-scout-react-mockups\_build\build-register.mjs` generates the approved mockup
from `_facts/tppoc-real-payload.json`; artifact 52190986-84da-4a86-89a7-b8735e700cfa.
Category-mapping decisions (owner-confirmed): FinOps → cost blade; Advisor → General;
PIM/RBAC → Identity; DevOps → DevOps; cost cleanup is not a category.

### Open / next

- Board updated for v3.5.0: AB#6936/6937 Resolved, AB#7035 Closed, AB#6938 Active (its ALZ
  benchmark AC is unmet because no BENCH-* rules were ever authored — that plus per-rule
  learnUrl/whyItMatters YAML is the remaining 6938 scope), AB#6928 Active (8/13 children
  open). Tags corrected to v3.5.0.
- **Owner decisions pending**: (1) AB#7035/7036/7037 are Tasks parented directly to Feature
  AB#6928 — the board standard wants a Story/Bug parent; reparent or accept. (2) The board
  tag vocabulary (`scripts/Test-BoardConformance.ps1:72-76`) contains no version tags, so
  the `v3.5.0` tag on four stories is flagged as non-vocabulary — add `vX.Y.Z` tags to the
  vocabulary or drop version tags and let release comments carry the fact.
- AB#6938 per-assessment depth continues: per-rule `learnUrl` + `whyItMatters` in rule YAML
  (the client-side keyword map is the interim); AB#7036 cost projections; AB#7037 AzL AHB.
- diagram-fixture-build.mjs prints "(skip) no data in fixture" against current corpus
  collect.json shapes — non-blocking, worth wiring real fixtures.
- A fresh tenant collect will light up the AHB audit callout (corpus predates licenseType).
