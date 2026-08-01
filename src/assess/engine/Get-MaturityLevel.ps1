#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Map a WAF pillar's 0-100 percentage score onto Microsoft's published five-level
    Well-Architected Framework maturity model (AB#6800).

.DESCRIPTION
    Reuses the SAME WAF pillar rule evaluation Get-Score already produces -- no
    duplicated rule definitions, no second scoring pass. This function only relabels
    a percentage score into Microsoft's maturity vocabulary.

    The five level NAMES and FOCUS descriptions below are copied verbatim from
    "What is the Azure Well-Architected Framework? -- Adopt a maturity model"
    (learn.microsoft.com/azure/well-architected/what-is-well-architected-framework,
    verified 2026-08-01). Microsoft does not publish a numeric score-to-level
    threshold -- the maturity model is a qualitative curriculum a workload team
    self-assesses against, not a percentage banding. The 0-100 -> Level 1-5 banding
    below is Scout's OWN interpretation (evenly split into five 20-point bands), so a
    customer reading a report can see exactly which points are Microsoft's and which
    are Scout's derived mapping. This is called out again in
    docs/design/waf-maturity-model-mapping.md.

.NOTES
    Tracks ADO Story AB#6800 (Feature AB#6746, Epic AB#6454).
#>
function Get-MaturityLevel {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Nullable[double]] $Score   # 0-100, or $null when the pillar has no scorable rules yet
    )

    $levels = @(
        [pscustomobject]@{ Level = 1; Name = 'Establish a solid foundation on Azure'; Focus = "Focus on leveraging Azure's core and native functionalities, while taking advantage of well-established cloud design patterns and best practices." }
        [pscustomobject]@{ Level = 2; Name = 'Build workload assets'; Focus = 'Address technical challenges on components directly owned by the workload team, including application code, deployment assets, and operational procedures.' }
        [pscustomobject]@{ Level = 3; Name = 'Be production-ready'; Focus = 'Involve business stakeholders in decision-making and consider tradeoffs with other pillars.' }
        [pscustomobject]@{ Level = 4; Name = 'Learn from production'; Focus = 'Shift focus to maintaining a stable environment, managing change, and accommodating new requirements based on business changes and production learnings.' }
        [pscustomobject]@{ Level = 5; Name = 'Future-proof with agility'; Focus = "Strive for aspirational quality -- adept at change to handle new market conditions and changes to external influences." }
    )

    if ($null -eq $Score) {
        return [pscustomobject]@{ Level = $null; Name = 'Unknown'; Focus = 'No scorable rules were evaluated for this pillar.' }
    }

    # Even five-way banding of the 0-100 score. 0-19 -> Level 1 ... 80-100 -> Level 5.
    $band = [Math]::Min(4, [Math]::Floor($Score / 20))
    return $levels[$band]
}
