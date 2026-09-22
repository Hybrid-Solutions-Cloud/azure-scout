# Cloud Governance domain maturity scale (AB#6459)

## The two maturity numbers this repo now produces, and why they are not the same one

Azure Scout produces two different "maturity" figures, on two different scales, for two
different frameworks. This document exists so neither is ever mistaken for the other, and so
a report never puts them on the same axis as if they were comparable.

| | WAF Maturity Model | Cloud Governance domain score |
|---|---|---|
| Framework | Well-Architected Framework (5 pillars) | CAF Govern (7 risk categories) |
| Scale | 1-5, Microsoft-published level **names** and focus descriptions | 1-10, entirely Scout's own scale |
| Source of the banding | `Get-MaturityLevel.ps1` — Scout's own even 20-point split of the 0-100 pillar score (Microsoft publishes no numeric threshold; see `docs/design/waf-maturity-model-mapping.md`) | `Get-GovernanceDomainScore.ps1` — Scout's own linear /10 mapping of the 0-100 domain score |
| Underlying evaluation | The same WAF pillar rule files (`waf.reliability`, `waf.security`, `waf.cost`, `waf.operational`, `waf.performance`) `Get-Score` already scores for the five WAF pillar assessments and `CAF: Azure Landing Zone` | The seven `caf.govern.*.yaml` rule files (`docs/frameworks/cloud-governance-question-set.md`, AB#6811) |
| Why this scale | WAF publishes qualitative level names ("Establish a solid foundation on Azure" … "Future-proof with agility") that Scout relabels a percentage into | CAF Govern publishes **no** maturity model or level scheme at all — there is nothing Microsoft-published to relabel, so Scout had to invent a scale outright |

**Both are relabelings of a percentage `Get-Score` already computed — neither runs a second
rule-evaluation pass.** `Get-MaturityLevel` and `Get-GovernanceDomainScore` are pure functions
over `Get-Score`'s output; a rule file is never duplicated for either.

## Which one AB#6459 uses, and why

AB#6459 asks for "a 1-10 domain maturity score across the seven governance domains." That is
**not** WAF's 5-level model — it is a new scale for the Cloud Governance framework
specifically, because:

1. **CAF Govern has no published maturity model to reuse.** WAF's 5-level model is a Microsoft
   artifact Scout relabels; nothing equivalent exists for CAF Govern's five-step/seven-category
   structure (`docs/frameworks/cloud-governance-question-set.md`). A 1-10 scale here is
   unavoidably Scout's own invention, exactly as the 20-point WAF banding is Scout's own
   invention layered onto Microsoft's level **names** — the difference is Cloud Governance gets
   no Microsoft names to layer onto at all.
2. **1-10, not 0-10 or a repeat of WAF's 1-5.** Ten points gives finer resolution than a five-way
   WAF-style band across seven domains that otherwise read too coarsely against each other on a
   report page (a five-level band collapses roughly 3 rule outcomes into indistinguishable
   territory for domains carrying only 2-4 rules, e.g. Regulatory Compliance and Resource
   Management). The floor is 1, not 0: a domain that was genuinely scored (at least one
   Pass/Partial/Fail rule ran) always carries some evidence, even if every rule failed, so its
   number should never collapse to the same "0" a chart axis default would show for an
   unscored domain — that ambiguity is exactly the false-pass-adjacent failure mode this design
   avoids.

## The mapping

`ConvertTo-ScoutGovernanceScale` (`src/assess/engine/Get-GovernanceDomainScore.ps1`):

```
Score1To10 = Max(1, Min(10, Round(PercentScore / 10)))
```

| Percentage score | 1-10 score |
|---|---|
| 0-4% | 1 (floored, never 0) |
| 5-14% | 1 |
| 15-24% | 2 |
| … | … |
| 95-100% | 10 |

The same helper converts both the per-domain scores and the overall Cloud Governance framework
headline score (`Get-Score`'s `Frameworks[Framework='Cloud Governance'].Score`, itself the
AreaWeight-weighted mean of the seven domains, AB#5087), so the headline number and the seven
domain numbers can never use different arithmetic and silently disagree.

## What a tenant with zero governance data renders as

This is the specific false-pass class AB#6839/#6844/#6845 exist to kill, and it applies here
identically:

- A domain where **every** rule is `Manual`/`Unknown`/`Error` has `Get-Score`'s scoring
  denominator at 0, so `Areas[].Score` is `$null`.
- `Get-GovernanceDomainScore` sets `Score = $null` and `NotAssessed = $true` for that domain —
  **never** a fabricated `1` (which would read as "assessed, worst") and **never** a fabricated
  `10` (which would read as "assessed, perfect").
- `Export-GovernanceReport.ps1` renders `NotAssessed` domains as the literal text
  **"Not assessed"** in the domain table, plots them as a **gap (`null`)** in the radar line
  rather than drawing a `0` vertex (a `0` on a 1-10 radar visually reads as "worst score", the
  exact misleading signal this exists to prevent — see the renderer's own header comment), and
  surfaces a dedicated callout banner naming every not-assessed domain above the radar/heatmap.
- If a collect/scoring run never loaded the `caf.govern.*.yaml` rule files at all (e.g. a
  narrower assessment that does not include them), `Export-GovernanceReport.ps1` renders all
  seven domains as "Not assessed" rather than an empty page — absence is visible, never silent.

A tenant with genuinely zero policy assignments, zero budgets, and zero resource locks scores
**low** on the domains those rules cover (percentage near 0%, banded to `1`) — that is a real,
scored `Fail`, not `NotAssessed`. `NotAssessed` is reserved for "Scout could not evaluate this
at all" (every rule manual/errored/no data collected), never for "Scout evaluated this and it
failed."
