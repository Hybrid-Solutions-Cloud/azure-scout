# Advisor — enumerated source for the Azure Advisor recommendations assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Azure Advisor is Microsoft's own recommendation engine. It analyses resource configuration and usage
telemetry and raises recommendations in five categories, each rated High, Medium or Low impact.
`src/assess/rules/advisor.recommendations.yaml` scores **what Advisor reports for the estate**: it does
not re-derive Advisor's findings, it counts them per category and impact, flags service-retirement
notices, and checks the Advisor score. It is written against this page only, and every rule cites an
item number from the tables below.

## Source

| Field | Value |
|---|---|
| Source page | [Introduction to Azure Advisor](https://learn.microsoft.com/azure/advisor/advisor-overview); [Get Advisor recommendations in Azure Resource Graph](https://learn.microsoft.com/azure/advisor/advisor-azure-resource-graph); [Advisor score](https://learn.microsoft.com/azure/advisor/advisor-score); category references: [Reliability](https://learn.microsoft.com/azure/advisor/advisor-reference-reliability-recommendations), [Security](https://learn.microsoft.com/azure/advisor/advisor-security-recommendations), [Performance](https://learn.microsoft.com/azure/advisor/advisor-reference-performance-recommendations), [Cost](https://learn.microsoft.com/azure/advisor/advisor-reference-cost-recommendations), [Operational excellence](https://learn.microsoft.com/azure/advisor/advisor-reference-operational-excellence-recommendations) |
| Framework version | Azure Advisor categories (HighAvailability, Security, Performance, Cost, OperationalExcellence) and impact levels (High, Medium, Low) as documented on Microsoft Learn on the extraction date; ARG `advisorresources` table with the consolidated `recommendationStatus` field. Advisor is not versioned per recommendation, so the extraction date is the version. |
| Extraction date | 2026-11-25 |
| Verification method | The overview, Resource Graph, score and category-reference pages were read with the Microsoft Learn MCP `microsoft_docs_search` and `microsoft_docs_fetch` tools on 2026-11-25. The category names were confirmed against the Advisor SDK `Category` enum (HighAvailability, Security, Performance, Cost, OperationalExcellence). The shape of Scout's `advisor[]` rows was read from `src/ingest/Import-AdvisorScores.ps1` and the collection filter from `src/collect/Get-ScoutRawInventory.ps1`. Rules were NOT run against a live tenant for this page; the repository's own hand-off notes record a live collection that returned Advisor rows through this path. |

## What Scout already collects from Advisor

| Dataset | collect.json path | Fields | Notes |
|---|---|---|---|
| Recommendations | `$.advisor[]` (with `$.advisorAvailable`) | `Category`, `Impact`, `ImpactedField`, `ImpactedValue`, `Subscription`, `ShortDescriptionProblem`, `ShortDescriptionSolution` | Filled by `Import-AdvisorScores`. In the normal single-pass path the rows are `advisorresources` rows filtered to `properties.impact in (Medium, High)`. `advisorAvailable` is `false` when Advisor was skipped or could not be read, which is what turns every Advisor rule into Not assessed. |
| Scores | `$.management.advisorScores[]` | `id`, `name`, `subscriptionId`, `lastRefreshedScore` | From `microsoft.advisor/advisorscore`. Present on some collection paths only; the rule is gated on the rows existing. |

**Category names.** Advisor's API and Resource Graph call the Reliability category `HighAvailability`.
The rules match that spelling.

## Limits of the data, and the projection that would remove each

| Limit | Effect on the rules | What is needed |
|---|---|---|
| Low-impact recommendations are not collected (the collection filter keeps Medium and High) | No Low-impact rule can exist; ADVISOR-GOV-02 is Manual | Remove the `properties.impact` filter on the `Advisories` query in `Get-ScoutRawInventory.ps1`, or read Low separately. |
| The recommendation status is not carried | A recommendation that someone dismissed, postponed or completed still counts toward a Fail | Add `properties.recommendationStatus` (values `New`, `InProgress`, `Completed`, `Postponed`, `Dismissed`; verified on the Advisor Resource Graph page) to the `advisor[]` row, and filter rules to `New` and `InProgress`. |
| The stable recommendation type id is not carried | Per-recommendation rules (for example "Create an Azure Service Health alert") cannot key on the id and would have to match text | Add `properties.recommendationTypeId` (a GUID per recommendation type; verified on the Resource Graph page) to the row. The category-reference pages above list each type's id, so rules can then be written per recommendation. |
| The recommendation's resource id is not carried | `ImpactedField` is the resource type and `ImpactedValue` is the resource name, so two resources with the same name in different resource groups look alike, and a rule cannot join a recommendation to `compute.virtualMachines` | Add `properties.resourceMetadata.resourceId` (verified on the Resource Graph page) to the row. |
| The recommendation subcategory is not carried | Retirement notices (ADVISOR-RE-03) are found by matching the problem text, which can miss a differently worded notice | Add the subcategory (`ServiceUpgradeAndRetirement` for retirements, per the Advisor service-retirement guidance). The Resource Graph page reads it as `properties.recommendationSubCategory` on `microsoft.advisor/metadata` rows, joined to recommendations on `properties.recommendationTypeId`; whether the recommendation rows carry it directly is not confirmed. |
| Category and impact come from the recommendation row itself | If a future Resource Graph change moves them off the recommendation row, `Category` and `Impact` would read empty and every rule would pass | The Resource Graph page's samples take `recommendationCategory` and `recommendationImpact` from `microsoft.advisor/metadata`, joined on `properties.recommendationTypeId`. Scout's collected rows carry them directly today, so no change is needed now; a metadata join is the fallback. |
| Category-level scores may not be collected | Only a score-below-threshold check (ADVISOR-SC-01) is possible, not "Reliability score under N" | Collect the `microsoft.advisor/advisorscore/category` Resource Graph type (listed in the Resource Graph supported-types reference), or the REST `advisorScore` list that returns one entity per category. |

None of these projections was run against live Resource Graph output for this page. The property
names are as documented on Microsoft Learn.

## The enumeration — 15 items (12 automated, 3 manual)

Every Advisor-backed item is **gated** on `$.advisorAvailable`, so a run that skipped Advisor reports
Not assessed instead of a clean pass. A passing result means "Advisor reported nothing at this level
for the subscriptions it could read", not "nothing is wrong".

### Reliability (Advisor category `HighAvailability`) — 3 items

| # | Item | Scout | Source |
|---|---|---|---|
| ADVISOR-RE-01 | No High-impact reliability recommendation is open | ✅ `$.advisor` `Category == HighAvailability`, `Impact == High` | [Reliability recommendations](https://learn.microsoft.com/azure/advisor/advisor-reference-reliability-recommendations) |
| ADVISOR-RE-02 | No Medium-impact reliability recommendation is open | ✅ `Impact == Medium` | same |
| ADVISOR-RE-03 | No recommendation warns of a service retirement or deprecation | ✅ `ShortDescriptionProblem` matches retire / deprecate / end of support (text match; see limits) | [Use service upgrade and retirement recommendations](https://learn.microsoft.com/azure/advisor/advisor-how-to-use-service-upgrade-retirement-recommendations) |

### Security — 2 items

| # | Item | Scout | Source |
|---|---|---|---|
| ADVISOR-SE-01 | No High-impact security recommendation is open | ✅ `Category == Security`, `Impact == High` | [Security recommendations](https://learn.microsoft.com/azure/advisor/advisor-security-recommendations) |
| ADVISOR-SE-02 | No Medium-impact security recommendation is open | ✅ `Impact == Medium` | same |

### Performance — 2 items

| # | Item | Scout | Source |
|---|---|---|---|
| ADVISOR-PE-01 | No High-impact performance recommendation is open | ✅ `Category == Performance`, `Impact == High` | [Performance recommendations](https://learn.microsoft.com/azure/advisor/advisor-reference-performance-recommendations) |
| ADVISOR-PE-02 | No Medium-impact performance recommendation is open | ✅ `Impact == Medium` | same |

### Cost — 2 items

| # | Item | Scout | Source |
|---|---|---|---|
| ADVISOR-CO-01 | No High-impact cost recommendation is open | ✅ `Category == Cost`, `Impact == High` | [Cost recommendations](https://learn.microsoft.com/azure/advisor/advisor-reference-cost-recommendations) |
| ADVISOR-CO-02 | No Medium-impact cost recommendation is open | ✅ `Impact == Medium` | same |

### Operational excellence — 2 items

| # | Item | Scout | Source |
|---|---|---|---|
| ADVISOR-OE-01 | No High-impact operational excellence recommendation is open | ✅ `Category == OperationalExcellence`, `Impact == High` | [Operational excellence recommendations](https://learn.microsoft.com/azure/advisor/advisor-reference-operational-excellence-recommendations) |
| ADVISOR-OE-02 | No Medium-impact operational excellence recommendation is open | ✅ `Impact == Medium` | same |

### Advisor score — 1 item

| # | Item | Scout | Source |
|---|---|---|---|
| ADVISOR-SC-01 | No Advisor score is below 70 percent | ✅ `$.management.advisorScores` `lastRefreshedScore` (**70 is Scout's threshold; Microsoft publishes no pass mark**) | [Advisor score](https://learn.microsoft.com/azure/advisor/advisor-score) |

### Governance of the recommendation backlog — 3 items

| # | Item | Scout | Source |
|---|---|---|---|
| ADVISOR-GOV-01 | Postponed and dismissed recommendations carry a recorded reason and a review date | ❌ Manual — status not collected | [Advisor in Resource Graph](https://learn.microsoft.com/azure/advisor/advisor-azure-resource-graph) |
| ADVISOR-GOV-02 | Low-impact recommendations are reviewed on a schedule | ❌ Manual — Low impact not collected | [Introduction to Advisor](https://learn.microsoft.com/azure/advisor/advisor-overview) |
| ADVISOR-GOV-03 | Advisor recommendation alerts are routed to an action group | ❌ Manual — activity-log alert rules attached (estate-wide) | [Introduction to Advisor](https://learn.microsoft.com/azure/advisor/advisor-overview) |

## How this relates to the other Scout assessments that read Advisor

`waf.cost.yaml`, `waf.security.yaml`, `waf.performance.yaml`, `finops.review.yaml` and
`caf.govern.cm.yaml` each read `$.advisor` for one category and impact as part of a WAF pillar or
FinOps score. This assessment is the complete, category-by-category view of the same rows, scored on
its own framework (`ADVISOR`); it does not replace those pillar rules, and an Advisor finding can
appear in both.
