# Current Task: Epic AB#6454 — Expand Azure Scout with deep governance and compliance analytics

- Status: **IN PROGRESS**
- Started 2026-08-01, off `main` at `449dd86`.
- Supersedes Epic 6452 (PSScriptAnalyzer), which is Closed.

## What this Epic is

Nine Features, roughly thirty User Stories. Mapped onto the release plan in
`docs/audits/AZURE-SCOUT-AUDIT.md` §16, it is **Releases 2 through 6**. Releases 0 and 1 were
Epic AB#6731 and are done.

| Feature | Release | Theme |
|---|---|---|
| AB#6744 | 2 | Score the compliance state Scout already collects |
| AB#6745 | 2b | Enumerate the source framework for every target assessment — **gates every rule file after it** |
| AB#6746 | 3 | Restructure LandingZone into per-pillar and per-design-area assessments |
| AB#6747 | 4 | Azure Local Well-Architected Review |
| AB#6748 | 5 | Workload assessments — AI, AVD, AVS, AVS LZ, CASA |
| AB#6749 | 6 | FinOps and DevOps capability assessments |
| AB#6455 | — | RBAC and Azure Policy data collectors |
| AB#6458 | — | Consultant-grade governance assessment report generator |
| AB#6461 | — | Validate assessment coverage and reporting (the four source audits) |

## Orchestration

Tier A dispatch per the HCS orchestration guidance: waves of at most eight concurrent agents,
worktree isolation for anything touching shared code paths, integrated one feature at a time
with an adversarial read of every acceptance criterion before anything is called done.

**Wave 1 — in flight**

| Agent | Stories | Isolation |
|---|---|---|
| WAF/CAF enumeration | AB#6745 (WAF pillars, CAF design areas) | main tree, docs only |
| Workload checklists | AB#6804, 6805–6808 | main tree, docs only |
| Question sets | AB#6809–6812, 6813–6815 | main tree, docs only |
| Currency rule | AB#6817 | main tree, docs + one test |
| Compliance scoring | AB#6744 — 6792, 6793, 6794, 6795 | `feat/ab6744-compliance` |
| Restructure | AB#6746 — 6796–6800 | `feat/ab6746-restructure` |
| Azure Local collectors | AB#6747 — 6801, 6802 | `feat/ab6747-azurelocal` |
| Remaining collectors | AB#6822–6825, 6828, 6829 | `feat/ab6822-collectors` |

**Wave 2 — blocked on wave 1's enumerations and restructure**

Rule files: AI + AVD (6818/6819), AVS + AVS LZ + CASA (6820/6821), Azure Local (6803),
FinOps + DevOps (6826/6827). Plus AB#6455/6456 orphaned-RBAC logic and AB#6458/6459/6448
governance report generator.

## Standing constraint

No rule file may be written for a target assessment until its source framework is tabulated
under `docs/frameworks/`. This is DQ12 and it is why AB#6745 is wave 1 and every rule file is
wave 2. Skipping it is how `waf.storage.yaml` came to score a WAF pillar that does not exist.
