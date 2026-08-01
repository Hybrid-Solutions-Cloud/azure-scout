# WAF Maturity Model mapping (AB#6800)

## What Microsoft publishes

The Well-Architected Framework includes a published five-level maturity model, described in
["What is the Azure Well-Architected Framework? — Adopt a maturity model"](https://learn.microsoft.com/en-us/azure/well-architected/what-is-well-architected-framework#adopt-a-maturity-model)
and expanded per-pillar in five maturity-model pages (
[Reliability](https://learn.microsoft.com/en-us/azure/well-architected/reliability/maturity-model),
[Security](https://learn.microsoft.com/en-us/azure/well-architected/security/maturity-model),
[Cost Optimization](https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/maturity-model),
[Operational Excellence](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/maturity-model),
[Performance Efficiency](https://learn.microsoft.com/en-us/azure/well-architected/performance-efficiency/maturity-model)).
Verified 2026-08-01.

| Level | Name | Focus |
|---|---|---|
| 1 | Establish a solid foundation on Azure | Leverage Azure's core/native functionality and well-established cloud design patterns. |
| 2 | Build workload assets | Address technical challenges on components the workload team directly owns. |
| 3 | Be production-ready | Involve business stakeholders; consider cross-pillar tradeoffs. |
| 4 | Learn from production | Maintain stability, manage change, absorb production learnings. |
| 5 | Future-proof with agility | Aspirational quality; adapt readily to new requirements. |

**Microsoft does not publish a numeric score-to-level threshold.** The maturity model is a
qualitative, self-assessed curriculum for a workload team — Microsoft's own maturity-model
assessment tool (https://learn.microsoft.com/en-us/assessments/af7d9889-8cb2-4b8b-b6bb-e5a2e2f2a59c)
asks structured questions and returns a level per pillar; it is not a percentage-of-checklist-items
calculation. Scout has no equivalent structured-question flow, only a scored rule set per pillar,
so a score-to-level mapping is unavoidably Scout's own derived step. This document exists so that
step is never presented as something Microsoft defined.

## What Scout does

`src/assess/engine/Get-MaturityLevel.ps1` takes the SAME 0-100 score `Get-Score` already computes
for a WAF pillar (`Areas[].Score` where `Framework -eq 'WAF'`) and buckets it into one of the five
levels above using an even 20-point-wide band:

| Score range | Level |
|---|---|
| 0-19 | 1 — Establish a solid foundation on Azure |
| 20-39 | 2 — Build workload assets |
| 40-59 | 3 — Be production-ready |
| 60-79 | 4 — Learn from production |
| 80-100 | 5 — Future-proof with agility |

This is Scout's own banding, explicitly not a Microsoft-published threshold — the level **names**
and **focus descriptions** are copied verbatim from Microsoft's page; only the score-to-band
arithmetic is Scout's.

## No duplicated rule definitions

`Get-Score` computes `MaturityLevel` inline, from the percentage score it already produced for
each Area and Framework — it does not run a second rule pass, and no rule file is duplicated for
the `WAF Maturity Model` registry entry (`manifests/assessments.psd1`), which uses the exact same
`Rules` glob (`waf.reliability`, `waf.security`, `waf.cost`, `waf.operational`, `waf.performance`)
as the five per-pillar assessments and the `LandingZone` roll-up. Running the WAF Maturity Model
assessment and running the five WAF pillar assessments against the same collect.json produces
identical percentage scores; the maturity model assessment differs only in that its report
surfaces `MaturityLevel` alongside the percentage, per pillar.

`Get-Score` populates `MaturityLevel` on every framework/area entry, not just WAF ones, via a
soft dependency (`Get-Command Get-MaturityLevel -ErrorAction SilentlyContinue`) — a caller that
has not dot-sourced `Get-MaturityLevel.ps1` gets scores exactly as before, with `MaturityLevel`
left `$null`. CAF/XR/SMART areas get a maturity level value too (the same 5-level bucketing
applied to their percentage score) since the function is framework-agnostic; only the WAF Maturity
Model registry entry's *name and report framing* claims it as "the" maturity model, matching
Microsoft's WAF-specific model.
