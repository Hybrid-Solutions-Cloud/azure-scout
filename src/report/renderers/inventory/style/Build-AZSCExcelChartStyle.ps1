#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Module for Excel Chart/Shape Style Finishing (EPPlus-native, no Excel COM)

.DESCRIPTION
Applies the same cosmetic finishing the old Build-AZSCExcelComObject used to apply by
driving a live Excel.Application over COM: chart-style presets on the Overview sheet's
named pivot charts (ChartP0..ChartP9), and fill/border finishing on the RoundRect info
panels (AZSC, RGs, TP00, TP0..TP9) drawn by Build-AZSCInitialBlock / Start-AZSCExcelOrdening.

.NOTES
AB#5662/AB#5665 -- replaces StyleFunctions/Build-AZTIExcelComObject.ps1. That predecessor
drove a live spreadsheet application instance over COM (ProgID "Excel.Application"), which
fails with 0x80040154 REGDB_E_CLASSNOTREG on every machine and CI runner without a local
Excel install -- exactly why -Lite (which skipped this whole step) defaulted to true. This
file does the same finishing work through EPPlus/ImportExcel directly, on the already-open
workbook, with no Excel host required at all.

Two deliberate approximations versus the retired COM path, because EPPlus 4.5.3 (the
version ImportExcel vendors) doesn't expose the same style model Excel's object model does:

  - Chart style: Excel COM's `.ChartStyle` (values like 222/268/294/315) is the *extended*
    Office 2013+ chart style/colors gallery. EPPlus's `ExcelChart.Style` property is the
    older `eChartStyle` enum (Style1-Style48, the original OOXML `<c:style val="n"/>`
    element) -- a different numbering scheme entirely, not a 1:1 mapping. $ChartStyleMap
    below picks a reasonable native EPPlus style per chart instead of trying to reproduce
    the exact extended-gallery look.
  - "No border" on the info panels: COM set `.border.ColorIndex`/`.border.LineStyle` to
    xlColorIndexNone/xlLineStyleNone. The EPPlus-equivalent property
    (`Border.Fill.Style = NoFill`) does not round-trip through Open-ExcelPackage in this
    EPPlus version -- it reads back as SolidFill after save. `Border.Width = 0` does
    persist and is visually equivalent (a zero-width line renders as no line), so that is
    used instead.

Every step here is independently try/catch-guarded and only Write-Debug on failure: this
runs after the report is already built and saved, so a missing chart/shape on a
data-shape this estate never produced (e.g. no Virtual Machines -> no ChartP7) must never
turn a successful report into a failed run, exactly as the retired COM path's
`if ($WSheet.Shapes | Where-Object {...})` guards intended.

.COMPONENT
This PowerShell Module is part of Azure Scout (AzureScout)
#>

function Build-AZSCExcelChartStyle {
    param($File)

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Applying EPPlus-native chart/shape style finishing (no Excel COM).')

    $Excel = Open-ExcelPackage -Path $File
    try {
        $WSheet = $Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Overview' }
        if (-not $WSheet) {
            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - No Overview sheet found; skipping chart/shape style finishing.')
            return
        }

        # ── Chart style presets ─────────────────────────────────────────────
        # Mirrors the old COM ChartP0..ChartP9 style assignment, mapped onto the nearest
        # native EPPlus eChartStyle value (see .NOTES). Charts are named "Chart<PivotTableName>"
        # by ImportExcel's Add-PivotTable, so "ChartP0" backs the "P0" pivot table Build-AZSCExcelChart builds.
        $ChartStyleMap = [ordered]@{
            'ChartP0' = 'Style2';  'ChartP1' = 'Style3';  'ChartP2' = 'Style2';  'ChartP3' = 'Style4'
            'ChartP4' = 'Style2';  'ChartP5' = 'Style3';  'ChartP6' = 'Style2';  'ChartP7' = 'Style4'
            'ChartP8' = 'Style2';  'ChartP9' = 'Style4'
        }
        foreach ($chartName in $ChartStyleMap.Keys) {
            $chart = $WSheet.Drawings[$chartName]
            if ($chart -is [OfficeOpenXml.Drawing.Chart.ExcelChart]) {
                try {
                    $chart.Style = [OfficeOpenXml.Drawing.Chart.eChartStyle]$ChartStyleMap[$chartName]
                }
                catch {
                    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Could not style chart '$chartName': $_")
                }
            }
        }

        # Any other pivot chart on Overview not covered above (e.g. dashboard-tab charts
        # added later) gets one consistent fallback style, matching the old COM code's
        # catch-all `-notin $NoChangeChart -and -like 'Chart*'` branch.
        foreach ($drawing in $WSheet.Drawings) {
            if ($drawing.Name -like 'Chart*' -and -not $ChartStyleMap.Contains($drawing.Name) -and $drawing -is [OfficeOpenXml.Drawing.Chart.ExcelChart]) {
                try {
                    $drawing.Style = [OfficeOpenXml.Drawing.Chart.eChartStyle]::Style5
                }
                catch {
                    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Could not style chart '$($drawing.Name)': $_")
                }
            }
        }

        # ── Info-panel shape finishing ───────────────────────────────────────
        # AZSC (the "about this report" panel) and RGs (total-resources panel) plus the
        # TP00/TP0-TP9 tab-title panels drawn by Build-AZSCInitialBlock/Start-AZSCExcelOrdening.
        $PanelShapes = @('AZSC', 'RGs', 'TP00') + (0..9 | ForEach-Object { "TP$_" })
        foreach ($shapeName in $PanelShapes) {
            $shape = $WSheet.Drawings[$shapeName]
            if ($shape -is [OfficeOpenXml.Drawing.ExcelShape]) {
                try {
                    $shape.Fill.Color = [System.Drawing.Color]::FromArgb(38, 38, 38)
                    $shape.Border.Width = 0
                }
                catch {
                    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Could not finish shape '$shapeName': $_")
                }
            }
        }

        # ── Tab colors ────────────────────────────────────────────────────────
        # No COM needed for this at all -- EPPlus's TabColor is a plain worksheet property.
        $BlueTabs = @('Overview', 'Policy', 'Advisor', 'Security Center', 'Subscriptions',
            'Quota Usage', 'AdvisorScore', 'Outages', 'Support Tickets', 'Reservation Advisor')
        foreach ($sheet in $Excel.Workbook.Worksheets) {
            try {
                $sheet.TabColor = if ($sheet.Name -in $BlueTabs) {
                    [System.Drawing.Color]::FromName('DarkBlue')
                }
                else {
                    [System.Drawing.Color]::FromName('LightGray')
                }
            }
            catch {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Could not set tab color for '$($sheet.Name)': $_")
            }
        }
    }
    finally {
        Close-ExcelPackage $Excel
    }
}
