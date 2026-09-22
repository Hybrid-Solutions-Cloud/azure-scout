#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Dispatch a requested renderer to its Export-* implementation.

.NOTES
    Every renderer reads the same findings.json. Tracks ADO Story AB#5045.
#>

function Get-ScoutRendererName {
    <#
    .SYNOPSIS
        The canonical list of renderer names Export-Report can dispatch — the single source
        of truth for what `-OutputFormat All` expands to.

    .NOTES
        AB#6863 (Feature AB#6449, Epic AB#6450). Invoke-ScoutAssessmentCore.ps1 used to carry
        its own hardcoded copy of this list, and it omitted 'GovernanceReport': the renderer
        shipped, was tested, and no production caller could reach it through the All path, so
        the only surface carrying the 1-10 CAF Govern domain maturity score never rendered on
        a default run. One list, read by both, so the next renderer added to the switch below
        cannot repeat it — and Export-Report.Tests.ps1 asserts the two stay in step.
    #>
    return @(
        'PowerBi'
        'Html'
        'Pptx'
        'Excel'
        'React'
        'Json'
        'JsonEvidence'
        'Pdf'
        'Word'
        'EChartsDashboard'
        'GovernanceReport'
    )
}
function Export-Report {
    # $Drift (optional) is the cross-run drift object from Get-ScoutDrift; only the
    # React renderer consumes it (to populate its Drift tab). Other renderers ignore it.
    #
    # $Model (optional, AB#6852) is the report model from Build-ScoutReportModel — the single
    # derivation of maturity, key risks, the gap register and the roadmap. It is optional on
    # purpose: a caller re-rendering a hand-edited findings.json, and every renderer test
    # harness that dot-sources one renderer file, both pass $null, and each renderer falls
    # back to its pre-v2 behaviour rather than failing.
    param([string] $Renderer, $Findings, $Collect, [string] $OutputPath, $Drift = $null, $Model = $null)
    switch ($Renderer) {
        # AB#6860 added a resource-grain fact table and its dimensions.
        'PowerBi' { Export-PowerBi -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Model $Model }
        'Html'    { Export-Html    -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#6858 rebuilt the deck as an executive readout against the report model.
        'Pptx'    { Export-Pptx    -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Model $Model }
        # AB#6857 added the cover, verdict legend, contents index and per-gap sheets.
        'Excel'   { Export-Excel   -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Model $Model }
        'React'   { Export-React   -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Drift $Drift }
        'Json'    { $Findings | ConvertTo-Json -Depth 100 | Out-File "$OutputPath/findings.json" }
        # AB#396: resources-only evidence export (raw Collect only -- no assessment
        # metadata/scores/findings; see Export-JsonEvidence.ps1's own header for why).
        'JsonEvidence' { Export-JsonEvidence -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#379/394/395: hand-rolled, dependency-free .pdf renderer (cover, exec
        # summary, per-area findings table with repeating header, gaps, manual
        # review). See Export-Pdf.ps1's own header for the offline-PDF design.
        'Pdf' { Export-Pdf -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#333: Word (.docx) via OpenXML. AB#6856 rebuilt it against the report model.
        # AB#344: self-contained offline ECharts HTML dashboard.
        'Word' { Export-Word -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Model $Model }
        'EChartsDashboard' { Export-EChartsDashboard -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#6459: consultant-grade Cloud Governance report -- 1-10 domain maturity score
        # per CAF Govern risk category, radar chart, domain x status heatmap.
        'GovernanceReport' { Export-GovernanceReport -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        default   { Write-Warning "Unknown renderer '$Renderer' — skipped." }
    }
}
