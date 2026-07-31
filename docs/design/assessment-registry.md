---
description: The catalogue of every Azure Scout assessment — description, category, sub-bundles, CAF areas, WAF pillars, default report tiers, and tags.
---

# Assessment Registry

`manifests/assessments.psd1` has **24 entries**, categorized and tagged. Run
one with `Invoke-AzureScout -Assessment <Name>`. **24 registry entries is not
24 assessments** — read the warning below before treating that number as a
coverage claim.

::: warning What 24 entries actually breaks down into
**`LandingZone` is the one real roll-up assessment** — every other entry is a
narrower view over the same rule set, a genuinely separate small assessment,
or not an assessment at all:

- **15 per-category slices**, prefixed `Assess: ` (`Assess: Compute`,
  `Assess: Security`, …). They collided with Scout's fifteen **inventory**
  category names — `Compute` filters what gets *collected*, `Assess: Compute`
  filters what gets *scored* — so they're now prefixed to stop the two
  different things sitting side by side under one label (quote the value —
  it has a colon and a space: `-Assessment 'Assess: Compute'`). The old
  unprefixed name still resolves — `Resolve-ScoutAssessmentName` maps it to
  the prefixed one and warns — so an existing script keeps working. This is a
  named stopgap: a future release retires these fifteen once per-WAF-pillar
  and per-CAF-design-area assessments exist to replace them (see the
  14-target programme on the
  [Roadmap](../roadmap.md#caf-waf-assessment-programme)).
- **4 sub-bundles**, narrower still than a category (`Governance`, `Policy`,
  `UpdateManager`, `Monitoring`). `Governance` and `Policy` below are
  presently byte-identical (same `Category`/`Collect`/`Ingest`/`Rules`) — a
  known duplicate flagged for cleanup, not a documentation error.
- **`Estate` is not really an assessment** — it declares no `Rules`, so it
  scores nothing; it is a full inventory pull that happens to live in this
  registry. The interactive wizard filters the menu to entries that actually
  have a matching rule file behind them (an entry that runs and returns
  nothing reads as "no findings," which is worse than not offering it), so
  **`Estate` does not appear in the wizard**. It still runs if you name it
  directly: `-Assessment Estate`.

That leaves **4 genuinely distinct assessments**: `LandingZone` (the
roll-up), `Cost` (targeted cost/TCO pull), `CrossResource` (findings that
need two collected datasets correlated), and `SMART` (migration readiness,
scored against its own enumerated source — see
[SMART's framework page](../frameworks/smart-question-set.md)).
:::

::: info What `Category`/`Collect` scope in practice
Each assessment declares a `Collect` list in the manifest, and the Collect
layer (`Invoke-Collect.ps1`) **does** use it to filter which Resource Graph
queries run — every query is tagged with the category name(s) whose rule
files reference its output, including cross-domain references, and
`subscriptions` always runs as base data. Passing `Collect = @('*')` (as
`LandingZone` and `Estate` both do) runs every query. What else differs
between assessments: which **ingestors** run (`Ingest` — `Governance`,
native and the default for the 5 governance-data assessments; `AdvisorScores`;
or the opt-in third-party `AzGovViz`), and which **rule files** are scored
(`Rules`) against the collected data. `ArgQueryPack` is retired — a manifest
entry that still names it in `Ingest` is now silently ignored, not run. See
[Assessment guide — Collect is now actually scoped by
category](../assessment.md#architecture-three-layers-json-on-disk) for the
full explanation.
:::

Source of truth: [`manifests/assessments.psd1`](https://github.com/thisismydemo/azure-scout/blob/main/manifests/assessments.psd1).
Tracks Epic **AB#5056** (foundation **AB#5057**).

Minimum auth per assessment (ARM Reader vs. the AzGovViz-only Graph
permissions): [Auth & permissions per scan type](../assessment-permissions.md).

## Cross-category roll-ups

| Assessment | Description | Category | Rules | Frameworks | Default report tiers | Tags |
|---|---|---|---|---|---|---|
| `LandingZone` | CAF/WAF landing zone audit (all areas) | `*` | `caf.*`, `waf.*`, `xr.*` | CAF: all 8 areas · WAF: all 5 pillars · XR: Cross-resource posture | PowerBi, Html, Pptx, React | caf, waf, landing-zone, cross-resource |
| `Estate` | Full digital estate inventory (no scoring) | `*` | — (inventory) | — | Excel, PowerBi | inventory |
| `Cost` | Cost / TCO data pull | `*` | `waf.cost` | WAF: Cost optimization | Excel, PowerBi | waf, cost |

## Per-category assessments

Legacy unprefixed names (`Management`, `Compute`, …) still resolve — see the
`Assess: ` note above.

| Assessment | Description | Category | Rule files | CAF areas / WAF pillars | Default report tiers | Tags |
|---|---|---|---|---|---|---|
| `Assess: Management` | Governance, policy, cost, backup, automation, update manager | Management | `caf.governance`, `caf.management`, `caf.billing` | CAF Governance/Management/Billing · WAF Operational/Cost | Html, Excel | caf, governance, management |
| `Assess: Monitor` | Monitoring, alerting, diagnostics coverage | Monitor | `caf.management`, `waf.operational` | CAF Management & monitoring · WAF Operational excellence | Html, Excel | waf, monitor |
| `Assess: Networking` | Network topology, firewall, DDoS, exposure, private link | Networking | `caf.network` | CAF Network topology & connectivity · WAF Security | Html, Excel | caf, networking |
| `Assess: Identity` | Identity & access — PIM, Conditional Access, RBAC | Identity | `caf.identity` | CAF Identity & access · WAF Security | Html, Excel | caf, identity |
| `Assess: Security` | Defender, Key Vault, secure score, exposure | Security | `caf.security`, `waf.security` | CAF Security · WAF Security | Html, Excel | caf, waf, security |
| `Assess: Compute` | VM resilience, zones, backup, right-size, orphans | Compute | `waf.reliability`, `waf.cost`, `waf.performance` | WAF Reliability/Cost/Performance | Html, Excel | waf, compute |
| `Assess: Storage` | Storage public access, TLS, encryption, redundancy | Storage | `caf.storage`, `waf.storage` | CAF Security · WAF Reliability | Html, Excel | caf, waf, storage |
| `Assess: Databases` | SQL/DB private access, TDE, zone redundancy | Databases | `caf.databases` | CAF Security · WAF Reliability | Html, Excel | caf, databases |
| `Assess: Containers` | AKS private clusters, RBAC, registry hardening | Containers | `caf.containers` | CAF Security · WAF Reliability | Html, Excel | caf, containers |
| `Assess: Web` | App Service HTTPS-only, TLS, managed identity | Web | `caf.web` | CAF Security · WAF Security | Html, Excel | caf, web |
| `Assess: Analytics` | Analytics data governance and network isolation | Analytics | `caf.analytics` | CAF Governance · WAF Security | Html, Excel | caf, analytics |
| `Assess: AI` | AI/Cognitive private access and responsible-AI posture | AI | `caf.ai` | CAF Governance · WAF Security | Html, Excel | caf, ai |
| `Assess: Integration` | Messaging redundancy and APIM network isolation | Integration | `caf.integration` | CAF Network & connectivity · WAF Reliability | Html, Excel | caf, integration |
| `Assess: Hybrid` | Arc onboarding, agent currency, Azure Local | Hybrid | `caf.hybrid` | CAF Management & monitoring · WAF Operational | Html, Excel | caf, hybrid |
| `Assess: IoT` | IoT Hub/DPS network isolation and device auth | IoT | `caf.iot` | CAF Security · WAF Security | Html, Excel | caf, iot |

## Sub-bundles (finer scope inside a category)

| Assessment | Description | Parent category | Rules | Default report tiers |
|---|---|---|---|---|
| `Governance` | Management sub-bundle — policy assignments, locks, budgets | Management | `caf.governance` | Html |
| `Policy` | Management sub-bundle — Azure Policy assignment/enforcement | Management | `caf.governance` | Html |
| `UpdateManager` | Management sub-bundle — patch/update compliance | Management | `caf.management` | Html |
| `Monitoring` | Monitor sub-bundle — diagnostic settings coverage | Monitor | `waf.operational` | Html |

## Migration readiness and cross-resource correlation

Two entries that don't fit the roll-up/category/sub-bundle shape above.

| Assessment | Description | Category | Rules | Frameworks | Default report tiers | Tags |
|---|---|---|---|---|---|---|
| `SMART` | Strategic Migration Assessment — migration readiness, scored against its own enumerated source (see [SMART's framework page](../frameworks/smart-question-set.md)) | Migration | `smart.*` | CAF: Migrate · SMART: readiness | Html, Excel | caf, migration, smart |
| `CrossResource` | Findings that require two collected datasets correlated (e.g. "which VMs have no backup") | `*` | `xr.*` | XR: Cross-resource posture | Html, Excel | cross-resource, waf, caf |

`SMART` additionally declares `RequiresData` — the wizard hides it unless the
current tenant's `collect.json` actually has Azure Migrate project,
discovery-site, or migration-service data, so a tenant that hasn't started a
migration doesn't get a manufactured "Unknown" result offered as a real
choice.

## Examples

```powershell
Invoke-AzureScout -Assessment 'Assess: Management'                    # governance + policy + update manager, scored
Invoke-AzureScout -Assessment 'Assess: Monitor'                       # monitoring/diagnostics only
Invoke-AzureScout -Assessment 'Assess: Networking','Assess: Security' -OutputFormat Html
Invoke-AzureScout -Assessment LandingZone -OutputFormat PowerBi,Html,Pptx
Invoke-AzureScout -Assessment LandingZone -InventoryAndAssessment      # collect once, get both reports
```

## Adding an assessment

1. Add a rule file `caf.<domain>.yaml` / `waf.<domain>.yaml` under `src/assess/rules/`.
2. Add an entry to `manifests/assessments.psd1` with `Category`, `Collect`, `Rules`, `Frameworks`, `Tags`, `Reporters`.
3. Add a row to this table. No core code change is required.
