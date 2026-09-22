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
Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone'      # CAF/WAF assessment
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
| Output | The React report (`report-react.html`) plus selected JSON results/evidence | The React report (`report-react.html`) plus selected JSON results/evidence |
| `-OutputFormat` | `React`, `Json`, `JsonEvidence`, or `All` | `React`, `Json`, `JsonEvidence`, or `All` |
| Full guide | [Usage Guide](./usage.md) | [Assessment mode](../assessment/assessment.md) |

::: danger One global output contract
The **React report is the one supported document in every run mode**. Word, PDF, Excel,
PowerPoint, Power BI, standalone HTML, ECharts dashboard, Markdown-file, AsciiDoc, and governance
renderers are **on hold** (**AB#6922**) —
they are being rebuilt to generate *from* the React report rather than alongside it, so a document
and the page it came from can never disagree. Export to Markdown, JSON, CSV, PDF (print) or a
standalone HTML copy from the report page itself.

Asking for a held format by name still binds: the run warns, skips it, and renders the React
report, so a run never returns an empty folder. `Json` / `JsonEvidence` are data, not documents,
and are never held. There is no inventory-only renderer carve-out. See
[Report tiers](../assessment/configuration.md#report-tiers).
:::

Both modes are the same module, the same sign-in, the same `-TenantID`, `-Scope`, `-Category`, and
`-ReportDir` parameters, and the same output-format contract.

## Running both

An assessment scores your estate, so it needs to know what's in it. To get the raw inventory
*and* the scored analysis from a single run — and a single collection from Azure — add
`-InventoryAndAssessment` (alias `-Both`) alongside `-Assessment`:

```powershell
Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -InventoryAndAssessment -ReportDir ./scout
```

The wizard's **Both** choice sets the same switch behind the scenes. Before this switch
existed, the collect-once path was reachable only by answering that wizard prompt — a script
or CI pipeline had no equivalent, and had to invoke the command twice back to back:

```powershell
Invoke-AzureScout -ReportDir ./scout                          # inventory — collects from Azure
Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -ReportDir ./scout  # assessment — collects again
```

That still works, but it pays for two collections against Azure instead of one.

::: tip One collection pass
The inventory pass already fetches the full property bag for every resource, and the
assessment shapes its scores from those rows instead of re-querying the same resource types.
Exactly one Resource Graph query still runs in a combined pass — the Defender for SQL pricing
lookup, which reads a table the inventory does not collect. An assessment-only run is
unchanged and still issues the full query pack.
:::

## Requirements

**PowerShell 7.0 or later, on PowerShell Core.** That applies to the whole module, both modes
— `AzureScout.psd1` declares `PowerShellVersion = '7.0'` and `CompatiblePSEditions = @('Core')`,
so `Import-Module` rejects Windows PowerShell 5.1 outright.

See [Prerequisites & Required Modules](./prerequisites.md) for the module list, and
[Assessment Prerequisites](../assessment/assessment-prerequisites.md) for the extra dependencies the
PowerPoint and PDF report tiers need — those tiers are currently on hold, so nothing in an
assessment run needs them today.

## Assessment command migration

The former standalone assessment command was a second entry point in v2.3.0 and
earlier. It was removed in v3.0.0. Use the unified switch:

The removed `Invoke-ScoutAssessment` command and its standalone HTML output are both legacy. Use
the unified entry point and live React renderer:

```powershell
Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -OutputFormat React
```

Every parameter maps across unchanged, except `-OutputPath`, which is `-ReportDir` on
`Invoke-AzureScout`.

::: tip Next steps
- [Prerequisites & Required Modules](./prerequisites.md) — what to install first.
- [Usage Guide](./usage.md) — inventory mode in depth.
- [Assessment mode](../assessment/assessment.md) — the CAF/WAF rules, scoring, and report tiers.
- [Parameters Reference](./parameters.md) — every switch on the one command.
:::
