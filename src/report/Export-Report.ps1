#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Dispatch a requested renderer to its Export-* implementation.

.NOTES
    Every renderer reads the same findings.json. Tracks ADO Story AB#5045.
#>
function Export-Report {
    # $Drift (optional) is the cross-run drift object from Get-ScoutDrift; only the
    # React renderer consumes it (to populate its Drift tab). Other renderers ignore it.
    # $ReportIdentity (AB#6930, optional) is the operator-supplied report-identity hashtable
    # (clientName/classification/etc.); only the React renderer consumes it today -- see
    # Export-React's own -ReportIdentity doc comment for the neutral-default fallback.
    # $DefaultReportMode (AB#6928 follow-up, optional) -- which view lens the React report opens
    # on when the browser has nothing persisted yet; only the React renderer consumes it.
    param([string] $Renderer, $Findings, $Collect, [string] $OutputPath, $Drift = $null, [hashtable] $ReportIdentity = @{}, [string] $DefaultReportMode = 'Consultant')
    switch ($Renderer) {
        'PowerBi' { Export-PowerBi -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        'Html'    { Export-Html    -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        'Pptx'    { Export-Pptx    -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#6883. Renamed from Export-Excel: that name is also exported by ImportExcel, which the
        # renderer itself imports, so ImportExcel's command shadowed ours for every call after the
        # first and every PER-ASSESSMENT workbook failed with "A parameter cannot be found that
        # matches parameter name 'Findings'". Only a real multi-assessment run surfaced it.
        'Excel'   { Export-ScoutEvidenceWorkbook -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        'React'   { Export-React   -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Drift $Drift -ReportIdentity $ReportIdentity -DefaultReportMode $DefaultReportMode }
        'Json'    { $Findings | ConvertTo-Json -Depth 100 | Out-File "$OutputPath/findings.json" }
        # AB#396: resources-only evidence export (raw Collect only -- no assessment
        # metadata/scores/findings; see Export-JsonEvidence.ps1's own header for why).
        'JsonEvidence' { Export-JsonEvidence -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#379/394/395: hand-rolled, dependency-free .pdf renderer (cover, exec
        # summary, per-area findings table with repeating header, gaps, manual
        # review). See Export-Pdf.ps1's own header for the offline-PDF design.
        'Pdf' { Export-Pdf -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#333: Word (.docx) via OpenXML. AB#344: self-contained offline ECharts HTML dashboard.
        'Word' { Export-Word -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        'EChartsDashboard' { Export-EChartsDashboard -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        # AB#6459: consultant-grade Cloud Governance report -- 1-10 domain maturity score
        # per CAF Govern risk category, radar chart, domain x status heatmap.
        'GovernanceReport' { Export-GovernanceReport -Findings $Findings -Collect $Collect -OutputPath $OutputPath }
        default   { Write-Warning "Unknown renderer '$Renderer' — skipped." }
    }
}
