---
description: One command, two modes. Invoke-AzureScout runs the inventory, the CAF/WAF assessment, or both — with a guided wizard if you run it with no parameters.
---

# Overview

AzureScout is **one command**: `Invoke-AzureScout`.

It has two modes. Inventory tells you *what's in your tenant*. Assessment scores that
estate against Microsoft's Cloud Adoption Framework and Well-Architected Framework.
You pick a mode with a switch — not with a different tool.

```powershell
Install-Module -Name AzureScout
Connect-AzAccount

Invoke-AzureScout                              # guided wizard — pick everything from a menu
Invoke-AzureScout -NoWizard                    # inventory, default settings
Invoke-AzureScout -Assessment LandingZone      # CAF/WAF assessment
```

## Just run it

Run `Invoke-AzureScout` with no parameters and you get a wizard. It signs you in, checks the
account actually holds the rights the scan needs, then hands you a checklist of everything
Scout can do — all of it pre-selected, so you uncheck what you don't want:

```
  Step 3/5 — What to run
  ────────────────────────────────────────────────────────

  Resource categories to inventory
    [x]  1. AI
    [x]  2. Analytics
    [x]  3. Compute
    ...

   Toggle with numbers (e.g. "3" or "3,5,9"), a = all, n = none,
   Enter = accept, q = quit
```

The last step prints the equivalent one-line command, so the wizard also teaches you the
parameters for when you want to script it later.

The wizard **only** opens in an interactive session. CI, scheduled tasks, containers, and
anything with redirected input fall straight through to the default inventory run — a bare
`Invoke-AzureScout` in a pipeline can never block on a prompt. Use `-NoWizard` to force that
same behaviour at a terminal.

## The two modes

| | Inventory (default) | Assessment (`-Assessment`) |
|:--|:--|:--|
| Answers | "What's in my tenant?" | "How well does it conform to CAF/WAF?" |
| Output | Excel, JSON, Markdown, AsciiDoc, Power BI CSVs | Scored `findings.json`, HTML, Power BI, PowerPoint, React, Excel evidence |
| `-OutputFormat` | `All`, `Excel`, `Json`, `Markdown`, `AsciiDoc`, `PowerBI` | `Html`, `Pptx`, `React`, `Pdf`, `Word`, `EChartsDashboard`, `JsonEvidence`, plus `Excel`/`Json`/`PowerBI` |
| Full guide | [Usage Guide](usage.md) | [Assessment mode](assessment.md) |

Both modes are the same module, the same sign-in, and the same `-TenantID`, `-Scope`,
`-Category`, and `-ReportDir` parameters. Mixing a format across modes fails with a message
telling you which switch you actually wanted, rather than quietly producing nothing.

## Running both

An assessment scores your estate, so it needs to know what's in it. To get the raw inventory
*and* the scored analysis from a single run, pick **Both** in the wizard — or run the two
modes back to back:

```powershell
Invoke-AzureScout -ReportDir ./scout                          # inventory
Invoke-AzureScout -Assessment LandingZone -ReportDir ./scout  # assessment
```

::: warning Known limitation
The two modes currently collect their Azure data separately — the inventory runs its own
per-resource-type modules, and the assessment runs its own Resource Graph query pack. Running
both therefore queries Azure twice. Collapsing them onto a single collection pass is tracked
work; until it lands, a "Both" run costs roughly two scans' worth of API calls.
:::

## Requirements

**PowerShell 7.0 or later, on PowerShell Core.** That applies to the whole module, both modes
— `AzureScout.psd1` declares `PowerShellVersion = '7.0'` and `CompatiblePSEditions = @('Core')`,
so `Import-Module` rejects Windows PowerShell 5.1 outright.

See [Prerequisites & Required Modules](prerequisites.md) for the module list, and
[Assessment Prerequisites](assessment-prerequisites.md) for the extra dependencies the
PowerPoint and PDF report tiers need.

## Migrating from `Invoke-ScoutAssessment`

`Invoke-ScoutAssessment` was a second entry point in v2.3.0 and earlier. It still works, but
it is **deprecated** and will be removed in v3.0.0. Move to the switch:

```powershell
# Before
Invoke-ScoutAssessment -Assessment LandingZone -OutputFormat Html

# After
Invoke-AzureScout -Assessment LandingZone -OutputFormat Html
```

Every parameter maps across unchanged, except `-OutputPath`, which is `-ReportDir` on
`Invoke-AzureScout`.

::: tip Next steps
- [Prerequisites & Required Modules](prerequisites.md) — what to install first.
- [Usage Guide](usage.md) — inventory mode in depth.
- [Assessment mode](assessment.md) — the CAF/WAF rules, scoring, and report tiers.
- [Parameters Reference](parameters.md) — every switch on the one command.
:::
