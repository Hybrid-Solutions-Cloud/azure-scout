#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Auto-assemble a Word (.docx) assessment report from scored findings via the
    OpenXML SDK (DocumentFormat.OpenXml) — no Word install required.

.DESCRIPTION
    Renders a print/share-friendly Word document directly from the scored
    Findings object (the output of Get-Score: GeneratedOn/Frameworks/Areas/
    Gaps/Manual/Errors/Findings) plus the raw Collect object (only its optional
    _meta.scope / _meta.managementGroupId are read, mirroring Export-Pptx).
    Every part of the .docx OPC package (document body, section properties,
    tables) is constructed programmatically with the OpenXML SDK
    (DocumentFormat.OpenXml.Wordprocessing) — the same accepted design used by
    Export-Pptx.ps1 for the executive deck (AB#5044).

    Section inventory:
      1. Cover           — title, subtitle, generated date/scope/mgmt-group
      2. Executive Summary — framework score table + rollup counts
      3. Findings by Area  — one heading + findings table per assessed area
      4. Prioritized Gaps  — Severity/Area/Gap table, sorted worst-first,
                             capped at top $Script:ScoutDocxMaxGaps rows
      5. Manual Review     — outstanding manual-review worklist, capped at
                             $Script:ScoutDocxMaxManual rows

    ASSEMBLY ACQUISITION: reuses the exact acquire-once-and-cache pattern
    Export-Pptx.ps1 established (Import-ScoutOpenXmlAssembly) — a throwaway
    dotnet-build csproj that pulls DocumentFormat.OpenXml from NuGet on first
    use and caches the DLLs under output/.tools/openxml/<version>. This file
    defines its own copy (Import-ScoutDocxOpenXmlAssembly) rather than calling
    Export-Pptx.ps1's function directly, so this renderer stays fully
    self-contained and loadable on its own (every existing renderer test
    harness in tests/ dot-sources only the one renderer .ps1 file it needs) —
    but it deliberately points at the SAME cache directory and version pin, so
    a prior Export-Pptx run (or Pptx Pester run) that already populated the
    cache means this renderer's first use costs nothing extra: Wordprocessing
    types live in the very same DocumentFormat.OpenXml.dll the deck renderer
    already downloaded.

.NOTES
    Tracks ADO Story AB#333.

    OpenXML SDK GOTCHA (also documented in Export-Pptx.ps1): every
    OpenXmlElement implements IEnumerable<OpenXmlElement> over its own
    children, and PowerShell's function-output pipeline auto-enumerates any
    IEnumerable it sees. A bare "return $element" silently flattens the
    element into its (often zero) children instead of returning the element
    itself — every helper below returns via the unary comma operator
    (`return ,$x`) to suppress that unrolling. The same is true of a plain
    System.Collections.Generic.List[object] (also IEnumerable), so
    New-ScoutDocxList follows the same pattern. Do not remove the commas.

    Non-fatal on failure: the whole render is wrapped in try/catch. If
    anything throws (a broken OpenXML acquire, a malformed Findings object,
    etc.) this writes a self-contained "assessment_word_fallback.html" next
    to where the .docx would have gone (mirroring Export-Pdf.ps1's
    Export-ScoutPdfHtmlFallback pattern) instead of throwing and aborting the
    whole multi-renderer Export-Report loop in the assessment core.
#>

#region Assembly acquisition (first-use NuGet acquire + cache, no committed binaries)

# Pinned so every run resolves the exact same OpenXML SDK build; bump deliberately.
# Deliberately the same version Export-Pptx.ps1 pins — see this file's header.
$Script:ScoutDocxOpenXmlVersion = '3.0.2'

function Import-ScoutDocxOpenXmlAssembly {
    [CmdletBinding()]
    param()

    # Idempotent within a process — a prior Export-Pptx (or Export-Word) call
    # in the same pwsh session already loaded these.
    $loaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'DocumentFormat.OpenXml' }
    if ($loaded) { return }

    $repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    $cacheDir = Join-Path $repoRoot 'output' '.tools' 'openxml' $Script:ScoutDocxOpenXmlVersion
    $requiredDlls = @('DocumentFormat.OpenXml.Framework.dll', 'System.IO.Packaging.dll', 'DocumentFormat.OpenXml.dll')

    $haveAll = -not ($requiredDlls | Where-Object { -not (Test-Path (Join-Path $cacheDir $_)) })
    if (-not $haveAll) {
        if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
            throw "Export-Word: DocumentFormat.OpenXml $($Script:ScoutDocxOpenXmlVersion) is not cached at '$cacheDir' and the 'dotnet' SDK is not on PATH to acquire it. Install the .NET SDK (or pre-seed the cache folder with the three DLLs above) and retry."
        }

        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "AzScoutOpenXmlAcquire_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $tempProj = Join-Path $tempDir 'acquire.csproj'
        @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>disable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <CopyLocalLockFileAssemblies>true</CopyLocalLockFileAssemblies>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="DocumentFormat.OpenXml" Version="$($Script:ScoutDocxOpenXmlVersion)" />
  </ItemGroup>
</Project>
"@ | Out-File -FilePath $tempProj -Encoding utf8

        Write-Host "[Export-Word] Acquiring DocumentFormat.OpenXml $($Script:ScoutDocxOpenXmlVersion) via dotnet/NuGet (first use — cached under $cacheDir for subsequent runs)..." -ForegroundColor Cyan
        $buildOutput = & dotnet build $tempProj -c Release -o $cacheDir --nologo 2>&1
        $exitCode = $LASTEXITCODE
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem $cacheDir -Filter 'acquire.*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        if ($exitCode -ne 0 -or -not (Test-Path (Join-Path $cacheDir 'DocumentFormat.OpenXml.dll'))) {
            throw "Export-Word: could not acquire DocumentFormat.OpenXml $($Script:ScoutDocxOpenXmlVersion) (offline, and nothing cached at '$cacheDir'?). dotnet build exit code $exitCode.`n$($buildOutput -join "`n")"
        }
        Write-Host "[Export-Word] DocumentFormat.OpenXml $($Script:ScoutDocxOpenXmlVersion) cached at $cacheDir" -ForegroundColor Green
    }

    foreach ($dll in $requiredDlls) {
        Add-Type -Path (Join-Path $cacheDir $dll) -ErrorAction Stop
    }
}

#endregion

#region Low-level OpenXML element helpers

$Script:ScoutDocxWNs = 'DocumentFormat.OpenXml.Wordprocessing'

function New-ScoutDocxEl {
    param([Parameter(Mandatory)][string]$TypeName)
    $o = New-Object -TypeName $TypeName
    return , $o
}

function New-ScoutDocxList {
    return , ([System.Collections.Generic.List[object]]::new())
}

function ScoutDocxDxa {
    # Twentieths of a point ("dxa") — the unit w:tblGrid/w:tcW/w:pgSz/w:pgMar all use.
    # 1440 dxa per inch.
    param([double]$Inches)
    return [int64][math]::Round($Inches * 1440)
}

#endregion

#region Palette (mirrors Export-Pptx.ps1's navy/steel/gold corporate palette)

$Script:ScoutDocxNavy = '1F4E78'
$Script:ScoutDocxSteel = '2E75B6'
$Script:ScoutDocxGreen = '2E7D32'
$Script:ScoutDocxGold = 'B8860B'
$Script:ScoutDocxRed = 'B00020'
$Script:ScoutDocxInk = '1A1A1A'
$Script:ScoutDocxPaper = 'FFFFFF'
$Script:ScoutDocxMist = 'F6F9FD'
$Script:ScoutDocxLine = 'D9D9D9'
$Script:ScoutDocxGray = '595959'

# Bounds on the doc's longer, unbounded-in-theory lists — a document naturally
# paginates (unlike a slide deck), so these are generous, but still finite so a
# pathological Findings object (thousands of gaps) can't produce a runaway render.
$Script:ScoutDocxMaxGaps = 50
$Script:ScoutDocxMaxManual = 100

#endregion

#region Paragraph / run helpers

function New-ScoutDocxRun {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [double]$SizePt = 11,
        [string]$Hex = $Script:ScoutDocxInk,
        [bool]$Bold = $false,
        [bool]$Italic = $false,
        [string]$Font = 'Segoe UI'
    )
    $run = New-ScoutDocxEl "$Script:ScoutDocxWNs.Run"
    $rPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.RunProperties"
    $rFonts = New-ScoutDocxEl "$Script:ScoutDocxWNs.RunFonts"
    $rFonts.Ascii = $Font
    $rFonts.HighAnsi = $Font
    $rPr.Append($rFonts)
    if ($Bold) { $rPr.Append((New-ScoutDocxEl "$Script:ScoutDocxWNs.Bold")) }
    if ($Italic) { $rPr.Append((New-ScoutDocxEl "$Script:ScoutDocxWNs.Italic")) }
    # CT_RPr child order (ECMA-376 §17.3.2.30) requires color BEFORE sz/szCs —
    # putting FontSize first (as an earlier draft of this file did) validates
    # as a schema error ("unexpected child element w:color") even though Word
    # itself tolerates it; keep this order to stay strictly schema-valid.
    $color = New-ScoutDocxEl "$Script:ScoutDocxWNs.Color"
    $color.Val = $Hex
    $rPr.Append($color)
    $sz = New-ScoutDocxEl "$Script:ScoutDocxWNs.FontSize"
    $sz.Val = "$([int][math]::Round($SizePt * 2))"
    $rPr.Append($sz)
    $run.Append($rPr)
    $t = New-ScoutDocxEl "$Script:ScoutDocxWNs.Text"
    $t.Text = $Text
    $t.Space = [DocumentFormat.OpenXml.SpaceProcessingModeValues]::Preserve
    $run.Append($t)
    return , $run
}

function New-ScoutDocxBreakRun {
    # A page-break run — appended as its own run inside the last paragraph of a
    # section so the next content starts on a fresh page.
    $run = New-ScoutDocxEl "$Script:ScoutDocxWNs.Run"
    $br = New-ScoutDocxEl "$Script:ScoutDocxWNs.Break"
    $br.Type = [DocumentFormat.OpenXml.Wordprocessing.BreakValues]::Page
    $run.Append($br)
    return , $run
}

function New-ScoutDocxPara {
    param(
        $Runs,
        [string]$Align = $null,
        [double]$SpaceBeforePt = 0,
        [double]$SpaceAfterPt = 6,
        [bool]$KeepNext = $false
    )
    $p = New-ScoutDocxEl "$Script:ScoutDocxWNs.Paragraph"
    $pPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.ParagraphProperties"
    $any = $false
    # CT_PPrBase child order (ECMA-376 §17.3.1.26) is keepNext, then spacing,
    # then jc — appending Justification first (as an earlier draft did)
    # validates as a schema error ("unexpected child element w:keepNext"/
    # "w:spacing" showing up after w:jc). Keep this order.
    if ($KeepNext) {
        $pPr.Append((New-ScoutDocxEl "$Script:ScoutDocxWNs.KeepNext"))
        $any = $true
    }
    if ($SpaceBeforePt -gt 0 -or $SpaceAfterPt -gt 0) {
        $spacing = New-ScoutDocxEl "$Script:ScoutDocxWNs.SpacingBetweenLines"
        if ($SpaceBeforePt -gt 0) { $spacing.Before = "$([int][math]::Round($SpaceBeforePt * 20))" }
        if ($SpaceAfterPt -gt 0) { $spacing.After = "$([int][math]::Round($SpaceAfterPt * 20))" }
        $pPr.Append($spacing)
        $any = $true
    }
    if ($Align) {
        $jc = New-ScoutDocxEl "$Script:ScoutDocxWNs.Justification"
        $jc.Val = switch ($Align) {
            'center' { [DocumentFormat.OpenXml.Wordprocessing.JustificationValues]::Center }
            'right' { [DocumentFormat.OpenXml.Wordprocessing.JustificationValues]::Right }
            default { [DocumentFormat.OpenXml.Wordprocessing.JustificationValues]::Left }
        }
        $pPr.Append($jc)
        $any = $true
    }
    if ($any) { $p.Append($pPr) }
    foreach ($r in $Runs) { $p.Append($r) }
    return , $p
}

function Add-ScoutDocxHeading {
    param($Body, [Parameter(Mandatory)][string]$Text, [int]$Level = 1)
    $sizePt = switch ($Level) { 1 { 22 } 2 { 16 } default { 13 } }
    $runs = New-ScoutDocxList
    $runs.Add((New-ScoutDocxRun -Text $Text -SizePt $sizePt -Hex $Script:ScoutDocxNavy -Bold $true -Font 'Segoe UI Semibold'))
    $spaceBefore = if ($Level -eq 1) { 12 } else { 8 }
    $Body.Append((New-ScoutDocxPara -Runs $runs -SpaceBeforePt $spaceBefore -SpaceAfterPt 6 -KeepNext $true))
}

function Add-ScoutDocxParagraph {
    param($Body, [Parameter(Mandatory)][AllowEmptyString()][string]$Text, [double]$SizePt = 11, [string]$Hex = $Script:ScoutDocxInk, [bool]$Italic = $false, [string]$Align = $null)
    $runs = New-ScoutDocxList
    $runs.Add((New-ScoutDocxRun -Text $Text -SizePt $SizePt -Hex $Hex -Italic $Italic))
    $Body.Append((New-ScoutDocxPara -Runs $runs -Align $Align))
}

function Add-ScoutDocxPageBreak {
    param($Body)
    $runs = New-ScoutDocxList
    $runs.Add((New-ScoutDocxBreakRun))
    $p = New-ScoutDocxEl "$Script:ScoutDocxWNs.Paragraph"
    foreach ($r in $runs) { $p.Append($r) }
    $Body.Append($p)
}

#endregion

#region Table helpers

function New-ScoutDocxShading {
    param([Parameter(Mandatory)][string]$Hex)
    $sh = New-ScoutDocxEl "$Script:ScoutDocxWNs.Shading"
    $sh.Val = [DocumentFormat.OpenXml.Wordprocessing.ShadingPatternValues]::Clear
    $sh.Color = 'auto'
    $sh.Fill = $Hex
    return , $sh
}

function New-ScoutDocxCell {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][double]$WidthIn,
        [double]$SizePt = 10,
        [string]$Hex = $Script:ScoutDocxInk,
        [bool]$Bold = $false,
        [string]$FillHex = $null,
        [string]$Align = $null
    )
    $tc = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableCell"
    $tcPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableCellProperties"
    $tcW = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableCellWidth"
    $tcW.Width = "$(ScoutDocxDxa $WidthIn)"
    $tcW.Type = [DocumentFormat.OpenXml.Wordprocessing.TableWidthUnitValues]::Dxa
    $tcPr.Append($tcW)
    if ($FillHex) { $tcPr.Append((New-ScoutDocxShading -Hex $FillHex)) }
    $vAlign = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableCellVerticalAlignment"
    $vAlign.Val = [DocumentFormat.OpenXml.Wordprocessing.TableVerticalAlignmentValues]::Center
    $tcPr.Append($vAlign)
    $tc.Append($tcPr)
    $runs = New-ScoutDocxList
    $runs.Add((New-ScoutDocxRun -Text $Text -SizePt $SizePt -Hex $Hex -Bold $Bold))
    $tc.Append((New-ScoutDocxPara -Runs $runs -Align $Align -SpaceAfterPt 0))
    return , $tc
}

function New-ScoutDocxRow {
    param($Cells, [bool]$Header = $false)
    $tr = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableRow"
    if ($Header) {
        $trPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableRowProperties"
        # AB#394-style header repeat (the same idea Export-Pdf.ps1 hand-rolls for
        # its findings table): w:tblHeader marks this row to repeat on every page
        # a long table spills onto, without duplicating it in the source content.
        $trPr.Append((New-ScoutDocxEl "$Script:ScoutDocxWNs.TableHeader"))
        $tr.Append($trPr)
    }
    foreach ($c in $Cells) { $tr.Append($c) }
    return , $tr
}

function New-ScoutDocxTable {
    param([Parameter(Mandatory)][double[]]$ColWidthsIn, [Parameter(Mandatory)]$Rows)
    $tbl = New-ScoutDocxEl "$Script:ScoutDocxWNs.Table"
    $tblPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableProperties"

    $tblW = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableWidth"
    $tblW.Width = '5000'
    $tblW.Type = [DocumentFormat.OpenXml.Wordprocessing.TableWidthUnitValues]::Pct
    $tblPr.Append($tblW)

    $borders = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableBorders"
    # CT_TblBorders child order (ECMA-376 §17.4.38) is top, left, bottom,
    # right, insideH, insideV — NOT top/bottom/left/right.
    foreach ($side in 'TopBorder', 'LeftBorder', 'BottomBorder', 'RightBorder', 'InsideHorizontalBorder', 'InsideVerticalBorder') {
        $b = New-ScoutDocxEl "$Script:ScoutDocxWNs.$side"
        $b.Val = [DocumentFormat.OpenXml.Wordprocessing.BorderValues]::Single
        $b.Size = [uint32]4
        $b.Color = $Script:ScoutDocxLine
        $borders.Append($b)
    }
    $tblPr.Append($borders)

    $tblLook = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableLook"
    $tblLook.FirstRow = $true
    $tblLook.LastRow = $false
    $tblLook.FirstColumn = $false
    $tblLook.LastColumn = $false
    $tblLook.NoHorizontalBand = $false
    $tblLook.NoVerticalBand = $true
    $tblPr.Append($tblLook)

    $tbl.Append($tblPr)

    $grid = New-ScoutDocxEl "$Script:ScoutDocxWNs.TableGrid"
    foreach ($w in $ColWidthsIn) {
        $gc = New-ScoutDocxEl "$Script:ScoutDocxWNs.GridColumn"
        $gc.Width = "$(ScoutDocxDxa $w)"
        $grid.Append($gc)
    }
    $tbl.Append($grid)

    foreach ($r in $Rows) { $tbl.Append($r) }
    return , $tbl
}

#endregion

#region Data helpers (safe property access, score/severity bands — mirrors Export-Pptx.ps1)

function Get-ScoutDocxProp {
    param($Obj, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $Default }
}

function Get-ScoutDocxScoreColor {
    param($Score)
    if ($null -eq $Score) { return $Script:ScoutDocxGray }
    if ($Score -ge 80) { return $Script:ScoutDocxGreen }
    if ($Score -ge 50) { return $Script:ScoutDocxGold }
    return $Script:ScoutDocxRed
}

$Script:ScoutDocxSeverityRank = @{ high = 0; medium = 1; low = 2 }

function Get-ScoutDocxSeverityRank {
    # AB#5089-style guard: null/missing/unrecognized severity sorts LAST, never throws.
    param($Severity)
    if ($Severity) {
        $key = $Severity.ToString().Trim().ToLowerInvariant()
        if ($Script:ScoutDocxSeverityRank.ContainsKey($key)) { return $Script:ScoutDocxSeverityRank[$key] }
    }
    return 99
}

function Get-ScoutDocxSeverityLabel {
    param($Severity)
    if ($Severity -and "$Severity".Trim()) { return "$Severity".ToUpperInvariant() }
    return 'UNKNOWN'
}

function Get-ScoutDocxSeverityColor {
    param($Severity)
    if (-not $Severity) { return $Script:ScoutDocxGray }
    switch ($Severity.ToString().Trim().ToLowerInvariant()) {
        'high' { return $Script:ScoutDocxRed }
        'medium' { return $Script:ScoutDocxGold }
        'low' { return $Script:ScoutDocxSteel }
        default { return $Script:ScoutDocxGray }
    }
}

#endregion

#region HTML fallback (non-fatal-on-failure companion, mirrors Export-Pdf.ps1's pattern)

function Export-ScoutDocxHtmlFallback {
    param($Findings, $Collect, [string] $OutputPath, [string] $Reason)
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $json = ($Findings | ConvertTo-Json -Depth 100) -replace '</', '<\/'
    $safeReason = $Reason -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $generatedOn = Get-ScoutDocxProp $Findings 'GeneratedOn' '(unknown)'
    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Azure Scout Assessment Report (fallback)</title>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; color:#1a1a1a; margin: 2rem; }
  .banner { background:#B00020; color:#fff; padding: 0.75rem 1rem; margin-bottom:1rem; }
</style>
</head>
<body>
<div class="banner">
  Word (.docx) generation failed for this run -- this is a plain HTML fallback, not a renamed non-docx file.
  Reason: $safeReason
</div>
<h1>Azure Scout Assessment Report</h1>
<p>Generated: $generatedOn</p>
<script>window.__FINDINGS__ = $json;</script>
</body>
</html>
"@
    $path = Join-Path $OutputPath 'assessment_word_fallback.html'
    $html | Out-File -FilePath $path -Encoding utf8
    return $path
}

#endregion

#region Section builders

function New-ScoutDocxCoverParagraphs {
    param($Body, [string]$Title, [string]$Subtitle, [string]$MetaLine)

    $wmRuns = New-ScoutDocxList
    $wmRuns.Add((New-ScoutDocxRun -Text 'AZURE SCOUT' -SizePt 12 -Hex $Script:ScoutDocxSteel -Bold $true))
    $Body.Append((New-ScoutDocxPara -Runs $wmRuns -Align 'center' -SpaceBeforePt 60 -SpaceAfterPt 12))

    $titleRuns = New-ScoutDocxList
    $titleRuns.Add((New-ScoutDocxRun -Text $Title -SizePt 32 -Hex $Script:ScoutDocxNavy -Bold $true -Font 'Segoe UI Semibold'))
    $Body.Append((New-ScoutDocxPara -Runs $titleRuns -Align 'center' -SpaceAfterPt 8))

    if ($Subtitle) {
        $subRuns = New-ScoutDocxList
        $subRuns.Add((New-ScoutDocxRun -Text $Subtitle -SizePt 15 -Hex $Script:ScoutDocxGray))
        $Body.Append((New-ScoutDocxPara -Runs $subRuns -Align 'center' -SpaceAfterPt 24))
    }

    if ($MetaLine) {
        $metaRuns = New-ScoutDocxList
        $metaRuns.Add((New-ScoutDocxRun -Text $MetaLine -SizePt 11 -Hex $Script:ScoutDocxGray -Italic $true))
        $Body.Append((New-ScoutDocxPara -Runs $metaRuns -Align 'center' -SpaceAfterPt 6))
    }
}

function New-ScoutDocxExecSummary {
    param($Body, $Frameworks, $Areas, $Gaps, $Manual, $Errors)

    Add-ScoutDocxHeading -Body $Body -Text 'Executive Summary' -Level 1

    if (@($Frameworks).Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No framework scored for this run.' -Hex $Script:ScoutDocxGray
    }
    else {
        $rows = New-ScoutDocxList
        $header = New-ScoutDocxList
        $header.Add((New-ScoutDocxCell -Text 'Framework' -WidthIn 3.0 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
        $header.Add((New-ScoutDocxCell -Text 'Alignment Score' -WidthIn 3.0 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy -Align 'center'))
        $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

        $r = 0
        foreach ($fw in @($Frameworks)) {
            $r++
            $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
            $score = Get-ScoutDocxProp $fw 'Score'
            $scoreText = if ($null -eq $score) { 'Not scored' } else { "$score / 100" }
            $cells = New-ScoutDocxList
            $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $fw 'Framework')" -WidthIn 3.0 -FillHex $bg))
            $cells.Add((New-ScoutDocxCell -Text $scoreText -WidthIn 3.0 -Bold $true -Hex (Get-ScoutDocxScoreColor $score) -FillHex $bg -Align 'center'))
            $rows.Add((New-ScoutDocxRow -Cells $cells))
        }
        $Body.Append((New-ScoutDocxTable -ColWidthsIn @(3.0, 3.0) -Rows $rows))
    }

    $areaArr = @($Areas)
    $passSum = ($areaArr | ForEach-Object { Get-ScoutDocxProp $_ 'Pass' 0 } | Measure-Object -Sum).Sum
    $partialSum = ($areaArr | ForEach-Object { Get-ScoutDocxProp $_ 'Partial' 0 } | Measure-Object -Sum).Sum
    $failSum = ($areaArr | ForEach-Object { Get-ScoutDocxProp $_ 'Fail' 0 } | Measure-Object -Sum).Sum
    $manualCount = @($Manual).Count
    $errorCount = @($Errors).Count
    $highGaps = @($Gaps | Where-Object { (Get-ScoutDocxSeverityLabel (Get-ScoutDocxProp $_ 'Severity')) -eq 'HIGH' }).Count

    Add-ScoutDocxParagraph -Body $Body -Text ' ' -SizePt 4
    foreach ($line in @(
            "Areas assessed: $($areaArr.Count)"
            "Rules evaluated — Pass: $passSum, Partial: $partialSum, Fail: $failSum"
            "Critical (High severity) gaps: $highGaps"
            "Manual review items pending: $manualCount"
            "Unknown/Error findings (check collector permissions): $errorCount"
        )) {
        Add-ScoutDocxParagraph -Body $Body -Text "•   $line" -SizePt 12
    }
}

function New-ScoutDocxAreaFindingsSection {
    param($Body, $Areas, $AllFindings)

    Add-ScoutDocxHeading -Body $Body -Text 'Findings by Area' -Level 1

    # @(...) wraps the WHOLE pipeline, not just $Areas -- Sort-Object over zero
    # input emits nothing, which collapses a bare assignment to $null (and
    # $null.Count throws under Set-StrictMode -Version Latest). Same
    # load-bearing pattern Get-Score.ps1 documents for its own Pass/Fail counters.
    $sortedAreas = @(@($Areas) | Sort-Object Framework, Area)
    if ($sortedAreas.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No areas were assessed for this run.' -Hex $Script:ScoutDocxGray
        return
    }

    foreach ($area in $sortedAreas) {
        $framework = Get-ScoutDocxProp $area 'Framework'
        $areaName = Get-ScoutDocxProp $area 'Area'
        $score = Get-ScoutDocxProp $area 'Score'
        $scoreText = if ($null -eq $score) { 'not scored' } else { "$score / 100" }
        Add-ScoutDocxHeading -Body $Body -Text "$framework — $areaName (Score: $scoreText)" -Level 2

        $areaFindings = @($AllFindings | Where-Object {
                (Get-ScoutDocxProp $_ 'Framework') -eq $framework -and (Get-ScoutDocxProp $_ 'Area') -eq $areaName
            })

        if ($areaFindings.Count -eq 0) {
            Add-ScoutDocxParagraph -Body $Body -Text 'No individual findings recorded for this area.' -Hex $Script:ScoutDocxGray -Italic $true
            continue
        }

        $rows = New-ScoutDocxList
        $header = New-ScoutDocxList
        foreach ($h in 'Id', 'Severity', 'Status', 'Title') {
            $w = switch ($h) { 'Id' { 1.3 } 'Severity' { 1.0 } 'Status' { 1.0 } default { 3.2 } }
            $header.Add((New-ScoutDocxCell -Text $h -WidthIn $w -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
        }
        $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

        $r = 0
        foreach ($f in ($areaFindings | Sort-Object @{ Expression = { Get-ScoutDocxSeverityRank (Get-ScoutDocxProp $_ 'Severity') } }, Id)) {
            $r++
            $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
            $sevLabel = Get-ScoutDocxSeverityLabel (Get-ScoutDocxProp $f 'Severity')
            $sevColor = Get-ScoutDocxSeverityColor (Get-ScoutDocxProp $f 'Severity')
            $cells = New-ScoutDocxList
            $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $f 'Id')" -WidthIn 1.3 -FillHex $bg))
            $cells.Add((New-ScoutDocxCell -Text $sevLabel -WidthIn 1.0 -Bold $true -Hex $Script:ScoutDocxPaper -FillHex $sevColor -Align 'center'))
            $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $f 'Status')" -WidthIn 1.0 -FillHex $bg -Align 'center'))
            $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $f 'Title')" -WidthIn 3.2 -FillHex $bg))
            $rows.Add((New-ScoutDocxRow -Cells $cells))
        }
        $Body.Append((New-ScoutDocxTable -ColWidthsIn @(1.3, 1.0, 1.0, 3.2) -Rows $rows))
        Add-ScoutDocxParagraph -Body $Body -Text ' ' -SizePt 4
    }
}

function New-ScoutDocxGapsSection {
    param($Body, $Gaps)

    Add-ScoutDocxHeading -Body $Body -Text 'Prioritized Gaps' -Level 1

    # @() wraps the whole pipeline for the same reason New-ScoutDocxAreaFindingsSection
    # wraps its Sort-Object above -- zero-input Sort-Object collapses to $null otherwise.
    $sorted = @(@($Gaps) | Sort-Object @{ Expression = { Get-ScoutDocxSeverityRank (Get-ScoutDocxProp $_ 'Severity') } }, Area)
    $top = @($sorted | Select-Object -First $Script:ScoutDocxMaxGaps)

    if ($top.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No prioritized gaps — all assessed rules are passing.' -Hex $Script:ScoutDocxGreen
        return
    }

    $rows = New-ScoutDocxList
    $header = New-ScoutDocxList
    foreach ($h in 'Severity', 'Area', 'Gap') {
        $w = switch ($h) { 'Severity' { 1.1 } 'Area' { 1.7 } default { 3.7 } }
        $header.Add((New-ScoutDocxCell -Text $h -WidthIn $w -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    }
    $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

    $r = 0
    foreach ($gap in $top) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $sevLabel = Get-ScoutDocxSeverityLabel (Get-ScoutDocxProp $gap 'Severity')
        $sevColor = Get-ScoutDocxSeverityColor (Get-ScoutDocxProp $gap 'Severity')
        $cells = New-ScoutDocxList
        $cells.Add((New-ScoutDocxCell -Text $sevLabel -WidthIn 1.1 -Bold $true -Hex $Script:ScoutDocxPaper -FillHex $sevColor -Align 'center'))
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $gap 'Area')" -WidthIn 1.7 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $gap 'Title')" -WidthIn 3.7 -FillHex $bg))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @(1.1, 1.7, 3.7) -Rows $rows))

    $truncated = @($sorted).Count - $top.Count
    if ($truncated -gt 0) {
        Add-ScoutDocxParagraph -Body $Body -Text "+$truncated more not shown — see the evidence pack (Excel tier) for the full list." -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true
    }
}

function New-ScoutDocxManualSection {
    param($Body, $Manual)

    Add-ScoutDocxHeading -Body $Body -Text 'Manual Review Worklist' -Level 1

    $items = @($Manual)
    if ($items.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No manual review items — full automated coverage for the selected assessment(s).' -Hex $Script:ScoutDocxGreen
        return
    }

    $shown = @($items | Select-Object -First $Script:ScoutDocxMaxManual)
    $rows = New-ScoutDocxList
    $header = New-ScoutDocxList
    $header.Add((New-ScoutDocxCell -Text 'Area' -WidthIn 2.0 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    $header.Add((New-ScoutDocxCell -Text 'Item' -WidthIn 4.5 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

    $r = 0
    foreach ($m in $shown) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $cells = New-ScoutDocxList
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $m 'Area')" -WidthIn 2.0 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp $m 'Title')" -WidthIn 4.5 -FillHex $bg))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @(2.0, 4.5) -Rows $rows))

    $truncated = $items.Count - $shown.Count
    if ($truncated -gt 0) {
        Add-ScoutDocxParagraph -Body $Body -Text "+$truncated more not shown — see the evidence pack (Excel tier) for the full list." -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true
    }
}

#region v2 section builders (AB#6856 — driven by the report model, not by raw findings)

<#
    Everything in this region reads Build-ScoutReportModel's output. The v1 sections above are
    retained and still run when no model is available (a caller re-rendering a hand-edited
    findings.json, or a narrow unit test that dot-sources only this file), because a renderer
    that hard-fails without its model is worse than one that renders less.

    The rule these sections hold to: a number that was not collected is rendered as "not
    collected", never as 0, and a domain that could not be assessed is rendered as "Not
    assessed", never as a score. Every section below has at least one branch that exists only
    to keep that true.
#>

function Get-ScoutDocxBandColor {
    param([AllowNull()] $Score)
    if ($null -eq $Score) { return $Script:ScoutDocxGray }
    if ($Score -ge 9) { return $Script:ScoutDocxGreen }
    if ($Score -ge 7) { return $Script:ScoutDocxSteel }
    if ($Score -ge 5) { return $Script:ScoutDocxGold }
    return $Script:ScoutDocxRed
}

function Add-ScoutDocxKeyValueTable {
    param($Body, $Pairs, [double]$KeyWidthIn = 2.0, [double]$ValueWidthIn = 4.5)
    $rows = New-ScoutDocxList
    $r = 0
    foreach ($p in $Pairs) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $cells = New-ScoutDocxList
        $cells.Add((New-ScoutDocxCell -Text $p.Key -WidthIn $KeyWidthIn -Bold $true -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text $p.Value -WidthIn $ValueWidthIn -FillHex $bg))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @($KeyWidthIn, $ValueWidthIn) -Rows $rows))
}

function Add-ScoutDocxGridTable {
    <#
    .SYNOPSIS
        A header row plus data rows, with per-cell fill/colour overrides.

    .PARAMETER Rows
        Array of arrays. Each inner array holds one row's cell specs:
        @{ Text = '...'; Bold = $false; Hex = '...'; FillHex = '...'; Align = 'center' }
    #>
    param($Body, [string[]]$Headers, [double[]]$Widths, $Rows)

    # A caller building rows with `$rows = foreach (...) { , @(...) }` gets a jagged array
    # back for two-or-more rows, but for exactly ONE row PowerShell's output stream enumerates
    # the unary-comma wrapper away and hands us the row's own cells as the top-level
    # collection. Normalise here rather than in nine call sites: a ROW is an array of cell
    # specs, so a collection whose first element is a cell spec (a dictionary) IS one row.
    # Without this, every table that happened to have a single data row rendered as a wall of
    # empty cells -- and, because the whole renderer is wrapped in a catch that falls back to
    # HTML, the symptom was a silently missing .docx rather than an error anyone would read.
    $normalised = @($Rows)
    if ($normalised.Count -gt 0 -and $normalised[0] -is [System.Collections.IDictionary]) {
        $normalised = @(, $normalised)
    }

    $tblRows = New-ScoutDocxList
    $header = New-ScoutDocxList
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $header.Add((New-ScoutDocxCell -Text $Headers[$i] -WidthIn $Widths[$i] -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    }
    $tblRows.Add((New-ScoutDocxRow -Cells $header -Header $true))

    $r = 0
    foreach ($row in $normalised) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $cells = New-ScoutDocxList
        for ($i = 0; $i -lt $Widths.Count; $i++) {
            $cellSpecs = @($row)
            $spec = if ($i -lt $cellSpecs.Count -and $cellSpecs[$i] -is [System.Collections.IDictionary]) { $cellSpecs[$i] } else { @{ Text = '' } }
            $text = if ($spec.ContainsKey('Text') -and $null -ne $spec.Text) { "$($spec.Text)" } else { '' }
            $fill = if ($spec.ContainsKey('FillHex') -and $spec.FillHex) { $spec.FillHex } else { $bg }
            $hex = if ($spec.ContainsKey('Hex') -and $spec.Hex) { $spec.Hex } else { $Script:ScoutDocxInk }
            $bold = if ($spec.ContainsKey('Bold')) { [bool]$spec.Bold } else { $false }
            $align = if ($spec.ContainsKey('Align')) { $spec.Align } else { $null }
            $cells.Add((New-ScoutDocxCell -Text $text -WidthIn $Widths[$i] -Hex $hex -Bold $bold -FillHex $fill -Align $align))
        }
        $tblRows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn $Widths -Rows $tblRows))
}

function New-ScoutDocxDocumentInfo {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Document Information' -Level 1

    $eng = Get-ScoutDocxProp $Model 'Engagement'
    $meta = Get-ScoutDocxProp $Model 'Meta'
    $scope = Get-ScoutDocxProp $Model 'Scope'

    $frameworks = @(Get-ScoutDocxProp $eng 'FrameworksReferenced')
    $fwText = if ($frameworks.Count -gt 0) {
        ($frameworks | ForEach-Object {
            $v = Get-ScoutDocxProp $_ 'Version'
            if ($v) { "$(Get-ScoutDocxProp $_ 'Framework') ($v)" } else { "$(Get-ScoutDocxProp $_ 'Framework')" }
        }) -join '; '
    } else { 'None recorded for this run' }

    $generated = Get-ScoutDocxProp $meta 'GeneratedOn'
    $generatedText = if ($generated) { try { ([datetime]$generated).ToString('d MMMM yyyy') } catch { "$generated" } } else { '(unknown)' }

    $pairs = @(
        @{ Key = 'Assessment date'; Value = $generatedText }
        @{ Key = 'Tenant ID'; Value = "$(Get-ScoutDocxProp $eng 'TenantId' '(not recorded)')" }
        @{ Key = 'Scope'; Value = "$(Get-ScoutDocxProp $meta 'Scope' '(not recorded)')" }
        @{ Key = 'Management group'; Value = "$(Get-ScoutDocxProp $meta 'ManagementGroupId' '(tenant root / not specified)')" }
        @{ Key = 'In-scope subscriptions'; Value = "$(Get-ScoutDocxProp $scope 'SubscriptionCount' 0)" }
        @{ Key = 'Frameworks referenced'; Value = $fwText }
        @{ Key = 'Classification'; Value = "$(Get-ScoutDocxProp $eng 'Classification')" }
        @{ Key = 'Source data'; Value = 'Azure Scout collect.json for this run — read-only ARM, Resource Graph and Microsoft Graph queries. No tenant state was modified.' }
        @{ Key = 'Run ID'; Value = "$(Get-ScoutDocxProp $meta 'RunId' '(not recorded)')" }
    )
    Add-ScoutDocxKeyValueTable -Body $Body -Pairs $pairs
}

function New-ScoutDocxTableOfContents {
    param($Body, $Sections)
    Add-ScoutDocxHeading -Body $Body -Text 'Contents' -Level 1
    $n = 0
    foreach ($s in $Sections) {
        $n++
        Add-ScoutDocxParagraph -Body $Body -Text ("{0:D2}.   {1}" -f $n, $s) -SizePt 11
    }
}

function New-ScoutDocxInventorySection {
    param($Body, $Model)

    $tiles = @(Get-ScoutDocxProp (Get-ScoutDocxProp $Model 'Inventory') 'Tiles')
    $collected = @($tiles | Where-Object { $_.Collected })
    $missing = @($tiles | Where-Object { -not $_.Collected })

    Add-ScoutDocxHeading -Body $Body -Text 'In-scope inventory' -Level 2

    if ($collected.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No inventory counts were collected for this run.' -Hex $Script:ScoutDocxGray -Italic $true
    }
    else {
        $rows = foreach ($t in $collected) {
            , @(
                @{ Text = $t.Label }
                @{ Text = '{0:N0}' -f $t.Value; Bold = $true; Align = 'right' }
            )
        }
        Add-ScoutDocxGridTable -Body $Body -Headers @('Resource', 'In scope') -Widths @(4.0, 2.5) -Rows $rows
    }

    if ($missing.Count -gt 0) {
        # Stated, not hidden. A tile silently absent reads as "this estate has none of those",
        # which is a different and much more comfortable claim than "we did not look".
        Add-ScoutDocxParagraph -Body $Body `
            -Text ("Not collected for this run, and therefore not counted above: {0}. These are blind spots, not zeroes." -f (($missing | ForEach-Object { $_.Label }) -join ', ')) `
            -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true
    }
}

function New-ScoutDocxExecSummaryV2 {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Executive Summary' -Level 1

    New-ScoutDocxInventorySection -Body $Body -Model $Model

    $maturity = Get-ScoutDocxProp $Model 'Maturity'
    $composite = Get-ScoutDocxProp $maturity 'Composite'
    $current = Get-ScoutDocxProp $composite 'Current'
    $band = Get-ScoutDocxProp $composite 'Band'
    $assessed = Get-ScoutDocxProp $composite 'AssessedDomainCount' 0
    $excluded = Get-ScoutDocxProp $composite 'ExcludedDomainCount' 0

    Add-ScoutDocxHeading -Body $Body -Text 'Composite maturity' -Level 2
    if ($null -eq $current) {
        $naRuns = New-ScoutDocxList
        $naRuns.Add((New-ScoutDocxRun -Text 'Not assessed' -SizePt 18 -Hex $Script:ScoutDocxGray -Bold $true))
        $naRuns.Add((New-ScoutDocxRun -Text '   no domain in this run produced a scorable result.' -SizePt 12 -Hex $Script:ScoutDocxGray))
        $Body.Append((New-ScoutDocxPara -Runs $naRuns -SpaceAfterPt 4))
    }
    else {
        $runs = New-ScoutDocxList
        $runs.Add((New-ScoutDocxRun -Text "$current / 10" -SizePt 24 -Hex (Get-ScoutDocxBandColor $current) -Bold $true))
        $runs.Add((New-ScoutDocxRun -Text "   $band" -SizePt 13 -Hex $Script:ScoutDocxGray))
        $Body.Append((New-ScoutDocxPara -Runs $runs -SpaceAfterPt 4))
        Add-ScoutDocxParagraph -Body $Body `
            -Text ("The composite is the unweighted mean of the {0} domain(s) that produced a scorable result." -f $assessed) `
            -SizePt 10 -Hex $Script:ScoutDocxGray
    }

    if ($excluded -gt 0) {
        Add-ScoutDocxParagraph -Body $Body `
            -Text ("{0} domain(s) are excluded from the composite because no automated evidence was collected for them. They are shown as 'Not assessed' throughout this report and are never scored as zero — a zero would read as 'measured and found worst' rather than 'not measured'." -f $excluded) `
            -SizePt 10 -Hex $Script:ScoutDocxGold

    }

    # Rollup counts
    $coverage = Get-ScoutDocxProp $Model 'Coverage'
    $gaps = @(Get-ScoutDocxProp $Model 'GapRegister')
    $critical = @($gaps | Where-Object { $_.Severity -in 'CRITICAL', 'HIGH' }).Count
    Add-ScoutDocxParagraph -Body $Body -Text ' ' -SizePt 4
    foreach ($line in @(
            "Open gaps in the register: $(@($gaps).Count)"
            "Of those, CRITICAL or HIGH severity: $critical"
            "Domains assessed: $(Get-ScoutDocxProp $coverage 'AssessedDomains' 0) — not assessed: $(Get-ScoutDocxProp $coverage 'NotAssessedDomains' 0)"
            "Controls requiring manual review: $(Get-ScoutDocxProp $coverage 'ManualReviewItems' 0)"
            "Controls that returned no data (gated or uncollected): $(Get-ScoutDocxProp $coverage 'NotAssessedItems' 0)"
            "Controls that errored (check collector permissions): $(Get-ScoutDocxProp $coverage 'ErrorItems' 0)"
        )) {
        Add-ScoutDocxParagraph -Body $Body -Text "•   $line" -SizePt 12
    }
}

function New-ScoutDocxFindingsDashboard {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Findings Dashboard' -Level 1
    Add-ScoutDocxParagraph -Body $Body -Text 'One line per domain: the maturity score, and the balance of controls behind it. The domain chapters below carry the supporting detail.' -SizePt 10 -Hex $Script:ScoutDocxGray

    $domains = @(Get-ScoutDocxProp (Get-ScoutDocxProp $Model 'Maturity') 'Domains')
    if ($domains.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No domains were assessed for this run.' -Hex $Script:ScoutDocxGray -Italic $true
        return
    }

    $rows = foreach ($d in $domains) {
        $scoreText = if ($d.NotAssessed) { 'Not assessed' } else { "$($d.Score) / 10" }
        , @(
            @{ Text = $d.Domain }
            @{ Text = $scoreText; Bold = $true; Hex = (Get-ScoutDocxBandColor $d.Score); Align = 'center' }
            @{ Text = $d.Band; Align = 'center' }
            @{ Text = "$($d.Pass)"; Align = 'center' }
            @{ Text = "$($d.Partial)"; Align = 'center' }
            @{ Text = "$($d.Fail)"; Align = 'center' }
            @{ Text = "$($d.Manual)"; Align = 'center' }
        )
    }
    Add-ScoutDocxGridTable -Body $Body `
        -Headers @('Domain', 'Score', 'Band', 'Pass', 'Partial', 'Fail', 'Manual') `
        -Widths @(1.9, 1.0, 1.2, 0.6, 0.7, 0.6, 0.7) -Rows $rows
}

function New-ScoutDocxMethodology {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Maturity Scoring Methodology' -Level 1
    Add-ScoutDocxParagraph -Body $Body -Text ('Each domain is scored on a 1-10 scale derived from the observed control state across the assessed scope. ' +
        'A domain score is its share of passing controls (a partial counts as a half) rescaled to 1-10; the composite is the unweighted arithmetic mean of the ' +
        'domains that produced a scorable result. Controls that are manual, errored, or returned no data are excluded from the denominator rather than counted as failures.')

    $rubric = @(Get-ScoutDocxProp (Get-ScoutDocxProp $Model 'Maturity') 'Rubric')
    $rows = foreach ($b in $rubric) {
        , @(
            @{ Text = "$($b.Min) – $($b.Max)"; Align = 'center'; Bold = $true }
            @{ Text = $b.Level; Bold = $true }
            @{ Text = $b.Description }
        )
    }
    Add-ScoutDocxGridTable -Body $Body -Headers @('Score band', 'Maturity level', 'Description') -Widths @(1.0, 1.6, 4.0) -Rows $rows

    Add-ScoutDocxParagraph -Body $Body -Text ('This 1-10 scale is Azure Scout''s own. Microsoft''s Cloud Adoption Framework Govern methodology publishes no numeric ' +
        'maturity model, so there is nothing published to relabel; the scale is not comparable to the Well-Architected Framework''s separate five-level maturity ' +
        'model, and the two are never plotted on one axis.') -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true
}

function New-ScoutDocxKriSection {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Key Risk Indicators' -Level 1

    $kris = @(Get-ScoutDocxProp $Model 'KeyRiskIndicators')
    if ($kris.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No key risk indicators were derived for this run.' -Hex $Script:ScoutDocxGray -Italic $true
        return
    }

    Add-ScoutDocxParagraph -Body $Body -Text 'Every row carries the count that supports it. Rows graded GOOD are deliberate strengths, included so the table reads as an assessment rather than an indictment.' -SizePt 10 -Hex $Script:ScoutDocxGray

    $rows = foreach ($k in $kris) {
        $sevColor = switch ("$($k.Severity)".ToUpperInvariant()) {
            'CRITICAL' { $Script:ScoutDocxRed }
            'HIGH' { $Script:ScoutDocxRed }
            'MEDIUM' { $Script:ScoutDocxGold }
            'LOW' { $Script:ScoutDocxSteel }
            'GOOD' { $Script:ScoutDocxGreen }
            default { $Script:ScoutDocxGray }
        }
        $countText = if ($null -eq $k.SupportingCount) { 'not collected' } else { '{0:N0}' -f $k.SupportingCount }
        , @(
            @{ Text = $k.RiskArea }
            @{ Text = $k.Domain }
            @{ Text = $countText; Align = 'right' }
            @{ Text = "$($k.Severity)"; Bold = $true; Hex = $Script:ScoutDocxPaper; FillHex = $sevColor; Align = 'center' }
        )
    }
    Add-ScoutDocxGridTable -Body $Body -Headers @('Risk area', 'Domain', 'Count', 'Severity') -Widths @(3.2, 1.4, 0.9, 1.0) -Rows $rows
}

function New-ScoutDocxFocusAreaSection {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Prioritised Focus Areas' -Level 1
    Add-ScoutDocxParagraph -Body $Body -Text 'Domains ranked by urgency — lowest maturity first, ties broken by the number of open gaps.' -SizePt 10 -Hex $Script:ScoutDocxGray

    $focus = @(Get-ScoutDocxProp $Model 'FocusAreas')
    if ($focus.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No domain produced a scorable result, so nothing can be ranked.' -Hex $Script:ScoutDocxGray -Italic $true
        return
    }

    $rows = foreach ($f in $focus) {
        , @(
            @{ Text = "$($f.Rank)"; Align = 'center'; Bold = $true }
            @{ Text = $f.Domain }
            @{ Text = "$($f.Score) / 10"; Align = 'center'; Bold = $true; Hex = (Get-ScoutDocxBandColor $f.Score) }
            @{ Text = "$($f.OpenGaps)"; Align = 'center' }
            @{ Text = $f.Status; Align = 'center' }
            @{ Text = $f.Priority; Align = 'center'; Bold = $true }
        )
    }
    Add-ScoutDocxGridTable -Body $Body -Headers @('Rank', 'Domain', 'Score', 'Open gaps', 'Status', 'Priority') `
        -Widths @(0.6, 2.2, 0.9, 0.9, 1.0, 1.1) -Rows $rows
}

function New-ScoutDocxDomainChapters {
    param($Body, $Model)

    $domains = @(Get-ScoutDocxProp (Get-ScoutDocxProp $Model 'Maturity') 'Domains')
    $gaps = @(Get-ScoutDocxProp $Model 'GapRegister')

    $n = 0
    foreach ($d in $domains) {
        $n++
        Add-ScoutDocxPageBreak -Body $Body
        Add-ScoutDocxHeading -Body $Body -Text ("Chapter {0} — {1}" -f $n, $d.Domain) -Level 1

        $scoreText = if ($d.NotAssessed) { 'Not assessed' } else { "$($d.Score)/10" }
        $runs = New-ScoutDocxList
        $runs.Add((New-ScoutDocxRun -Text "Maturity Score: $scoreText" -SizePt 12 -Hex (Get-ScoutDocxBandColor $d.Score) -Bold $true))
        $runs.Add((New-ScoutDocxRun -Text "   |   Band: $($d.Band)" -SizePt 12 -Hex $Script:ScoutDocxGray))
        $Body.Append((New-ScoutDocxPara -Runs $runs -SpaceAfterPt 8))

        if ($d.WhyThisMatters) {
            Add-ScoutDocxHeading -Body $Body -Text 'Why this matters' -Level 2
            Add-ScoutDocxParagraph -Body $Body -Text "$($d.WhyThisMatters)"
        }

        Add-ScoutDocxHeading -Body $Body -Text 'Current state' -Level 2
        if ($d.NotAssessed) {
            # The load-bearing branch. Inventing a current-state sentence for a domain with no
            # evidence is precisely the failure this report exists to stop.
            Add-ScoutDocxParagraph -Body $Body -Text ('No automated evidence was collected for this domain in this run, so no current state can be described and no score can be claimed. ' +
                'This is a coverage gap, not a pass and not a failure.') -Hex $Script:ScoutDocxGold
        }
        elseif ($d.CurrentState) {
            Add-ScoutDocxParagraph -Body $Body -Text "$($d.CurrentState)"
        }
        else {
            $total = [int]$d.Pass + [int]$d.Partial + [int]$d.Fail
            Add-ScoutDocxParagraph -Body $Body -Text ("{0} of {1} scorable controls in this domain are satisfied, {2} partially, and {3} are not. {4} further control(s) require manual review and are excluded from the score." -f `
                    $d.Pass, $total, $d.Partial, $d.Fail, $d.Manual)
        }

        $domainGaps = @($gaps | Where-Object { "$($_.Domain)" -eq "$($d.Domain)" })
        Add-ScoutDocxHeading -Body $Body -Text 'Findings and action items' -Level 2
        if ($domainGaps.Count -eq 0) {
            Add-ScoutDocxParagraph -Body $Body -Text 'No open gaps in this domain.' -Hex $Script:ScoutDocxGreen
            continue
        }

        $rows = foreach ($g in $domainGaps) {
            $observed = if ($g.EvidenceTruncated) {
                "{0} affected (showing first {1})" -f $g.EvidenceCount, $g.EvidenceShown
            } else {
                "{0} affected" -f $g.EvidenceCount
            }
            , @(
                @{ Text = $g.GapId; Align = 'center' }
                @{ Text = $g.Title }
                @{ Text = $observed; Align = 'center' }
                @{ Text = $g.Severity; Bold = $true; Align = 'center' }
                @{ Text = $(if ($g.ClosureAction) { $g.ClosureAction } else { '—' }) }
            )
        }
        Add-ScoutDocxGridTable -Body $Body -Headers @('Gap', 'Finding', 'Observed', 'Severity', 'Recommended action') `
            -Widths @(0.5, 2.0, 1.0, 0.8, 2.2) -Rows $rows

        # The named resources. This is the section whose absence made every previous report
        # unusable: "a rule failed" with no way to know what failed.
        $withEvidence = @($domainGaps | Where-Object { @($_.Evidence).Count -gt 0 })
        if ($withEvidence.Count -gt 0) {
            Add-ScoutDocxHeading -Body $Body -Text 'Affected resources' -Level 2
            $evRows = foreach ($g in $withEvidence) {
                foreach ($e in @($g.Evidence)) {
                    , @(
                        @{ Text = $g.GapId; Align = 'center' }
                        @{ Text = $(if ($e.SubscriptionName) { $e.SubscriptionName } elseif ($e.SubscriptionId) { $e.SubscriptionId } else { '—' }) }
                        @{ Text = $(if ($e.ResourceGroup) { $e.ResourceGroup } else { '—' }) }
                        @{ Text = $(if ($e.ResourceName) { $e.ResourceName } else { '—' }) }
                        @{ Text = $e.Verdict }
                    )
                }
            }
            Add-ScoutDocxGridTable -Body $Body -Headers @('Gap', 'Subscription', 'Resource group', 'Resource', 'Triage verdict') `
                -Widths @(0.5, 1.7, 1.5, 1.7, 1.6) -Rows $evRows
            Add-ScoutDocxParagraph -Body $Body -Text ('Triage verdicts are a heuristic first pass over resource naming and placement, produced to sort the list — not a confirmed judgement. ' +
                'Each row still needs review by someone who knows the estate.') -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true

            $truncated = @($withEvidence | Where-Object { $_.EvidenceTruncated })
            if ($truncated.Count -gt 0) {
                # Deliberately does NOT restate the cap as its own number. The Observed column
                # above already carries the exact "N affected (showing first M)" per gap, and a
                # second, separately-derived figure here can disagree with it — which is worse
                # than saying less.
                Add-ScoutDocxParagraph -Body $Body -Text ("The resource list above is partial for {0} of these gap(s) — see the 'showing first' counts in the findings table. The affected totals themselves are complete." -f `
                        $truncated.Count) -SizePt 9 -Hex $Script:ScoutDocxGold -Italic $true
            }
        }
    }
}

function New-ScoutDocxMaturitySummary {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Overall Maturity Summary' -Level 1

    $maturity = Get-ScoutDocxProp $Model 'Maturity'
    $domains = @(Get-ScoutDocxProp $maturity 'Domains')
    $composite = Get-ScoutDocxProp $maturity 'Composite'

    $rows = foreach ($d in $domains) {
        $cur = if ($d.NotAssessed) { 'Not assessed' } else { "$($d.Score)" }
        $tgt = if ($null -ne $d.TargetScore) { "$($d.TargetScore)" } else { '—' }
        $gap = if (-not $d.NotAssessed -and $null -ne $d.TargetScore) { '+{0}' -f ($d.TargetScore - $d.Score) } else { '—' }
        , @(
            @{ Text = $d.Domain }
            @{ Text = $cur; Align = 'center'; Bold = $true; Hex = (Get-ScoutDocxBandColor $d.Score) }
            @{ Text = $tgt; Align = 'center' }
            @{ Text = $gap; Align = 'center' }
            @{ Text = $d.Band; Align = 'center' }
        )
    }

    $compCur = Get-ScoutDocxProp $composite 'Current'
    $rows = @($rows) + @(, @(
            @{ Text = 'Composite'; Bold = $true; FillHex = $Script:ScoutDocxMist }
            @{ Text = $(if ($null -eq $compCur) { 'Not assessed' } else { "$compCur" }); Bold = $true; Align = 'center'; FillHex = $Script:ScoutDocxMist }
            @{ Text = $(if ($null -ne (Get-ScoutDocxProp $composite 'Target')) { "$(Get-ScoutDocxProp $composite 'Target')" } else { '—' }); Align = 'center'; FillHex = $Script:ScoutDocxMist }
            @{ Text = $(if ($null -ne (Get-ScoutDocxProp $composite 'Gap')) { "+$(Get-ScoutDocxProp $composite 'Gap')" } else { '—' }); Align = 'center'; FillHex = $Script:ScoutDocxMist }
            @{ Text = "$(Get-ScoutDocxProp $composite 'Band')"; Align = 'center'; Bold = $true; FillHex = $Script:ScoutDocxMist }
        ))

    Add-ScoutDocxGridTable -Body $Body -Headers @('Domain', 'Current', 'Target', 'Gap', 'Band') `
        -Widths @(2.4, 1.1, 1.0, 0.8, 1.4) -Rows $rows
}

function New-ScoutDocxRoadmapSection {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text '90-Day Remediation Roadmap' -Level 1
    Add-ScoutDocxParagraph -Body $Body -Text 'Three 30-day phases. An action is placed by its rule when the rule declares a phase; otherwise by severity, and the table says which.' -SizePt 10 -Hex $Script:ScoutDocxGray

    $roadmap = Get-ScoutDocxProp $Model 'Roadmap'
    foreach ($phase in @(Get-ScoutDocxProp $roadmap 'Phases')) {
        Add-ScoutDocxHeading -Body $Body -Text ("Phase {0} — {1} ({2})" -f $phase.Phase, $phase.Name, $phase.DayRange) -Level 2
        $items = @($phase.Items)
        if ($items.Count -eq 0) {
            Add-ScoutDocxParagraph -Body $Body -Text 'No actions fall into this phase.' -Hex $Script:ScoutDocxGray -Italic $true
            continue
        }
        $rows = foreach ($i in $items) {
            , @(
                @{ Text = $i.GapId; Align = 'center' }
                @{ Text = $i.Domain }
                @{ Text = $(if ($i.Action) { $i.Action } else { '—' }) }
                @{ Text = $(if ($i.Owner) { $i.Owner } else { '—' }) }
                @{ Text = $(if ($i.Effort) { $i.Effort } else { '—' }); Align = 'center' }
                @{ Text = $(if ($i.PhaseSource -eq 'rule') { 'declared' } else { 'by severity' }); Align = 'center' }
            )
        }
        Add-ScoutDocxGridTable -Body $Body -Headers @('Gap', 'Domain', 'Action', 'Owner', 'Effort', 'Sequenced') `
            -Widths @(0.5, 1.2, 2.4, 1.3, 0.5, 0.9) -Rows $rows
    }

    $exit = @(Get-ScoutDocxProp $roadmap 'ExitCriteria')
    if ($exit.Count -gt 0) {
        Add-ScoutDocxHeading -Body $Body -Text 'Exit criteria' -Level 2
        foreach ($c in $exit) { Add-ScoutDocxParagraph -Body $Body -Text "•   $c" -SizePt 11 }
    }
}

function New-ScoutDocxAppendixSubscriptions {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Appendix A — Subscription Detail' -Level 1

    $subs = @(Get-ScoutDocxProp (Get-ScoutDocxProp $Model 'Scope') 'Subscriptions')
    if ($subs.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No subscription inventory was collected for this run.' -Hex $Script:ScoutDocxGray -Italic $true
        return
    }

    $gaps = @(Get-ScoutDocxProp $Model 'GapRegister')
    $bySub = @{}
    foreach ($g in $gaps) {
        foreach ($e in @($g.Evidence)) {
            $key = if ($e.SubscriptionId) { "$($e.SubscriptionId)" } else { continue }
            if (-not $bySub.ContainsKey($key)) { $bySub[$key] = 0 }
            $bySub[$key]++
        }
    }

    $rows = foreach ($s in $subs) {
        $id = "$($s.Id)"
        , @(
            @{ Text = "$($s.Name)" }
            @{ Text = $id }
            @{ Text = "$($s.State)"; Align = 'center' }
            @{ Text = $(if ($bySub.ContainsKey($id)) { "$($bySub[$id])" } else { '0' }); Align = 'center' }
        )
    }
    Add-ScoutDocxGridTable -Body $Body -Headers @('Subscription', 'Subscription ID', 'State', 'Affected resources') `
        -Widths @(2.0, 2.6, 0.9, 1.2) -Rows $rows
}

function New-ScoutDocxAppendixGapRegister {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Appendix B — Consolidated Gap Register' -Level 1

    $gaps = @(Get-ScoutDocxProp $Model 'GapRegister')
    if ($gaps.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No open gaps — every scorable control in the assessed scope is satisfied.' -Hex $Script:ScoutDocxGreen
        return
    }

    $bySeverity = $gaps | Group-Object Severity | ForEach-Object { "$($_.Count) $($_.Name)" }
    Add-ScoutDocxParagraph -Body $Body -Text ("{0} gaps total — {1}. Grouped by domain and ordered by severity within each group." -f $gaps.Count, ($bySeverity -join ', '))

    $rows = foreach ($g in $gaps) {
        , @(
            @{ Text = $g.GapId; Align = 'center' }
            @{ Text = $g.Domain }
            @{ Text = "$($g.Title) ($($g.EvidenceCount) affected)" }
            @{ Text = $(if ($g.TargetState) { $g.TargetState } else { '—' }) }
            @{ Text = $g.Severity; Bold = $true; Align = 'center' }
            @{ Text = $(if ($g.ClosureAction) { $g.ClosureAction } else { '—' }) }
        )
    }
    Add-ScoutDocxGridTable -Body $Body -Headers @('Gap', 'Domain', 'Current state (observed)', 'Target state', 'Severity', 'Closure action') `
        -Widths @(0.45, 1.0, 1.7, 1.6, 0.7, 1.55) -Rows $rows

    $noTarget = @($gaps | Where-Object { -not $_.TargetState }).Count
    if ($noTarget -gt 0) {
        Add-ScoutDocxParagraph -Body $Body -Text ("{0} gap(s) carry no target state because their rule does not declare one. The closure action still applies; the target-state column is left blank rather than guessed." -f $noTarget) `
            -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true
    }
}

function New-ScoutDocxScopeAndAssumptions {
    param($Body, $Model)

    Add-ScoutDocxHeading -Body $Body -Text 'Scope & Assumptions' -Level 1

    $meta = Get-ScoutDocxProp $Model 'Meta'
    $scope = Get-ScoutDocxProp $Model 'Scope'
    $coverage = Get-ScoutDocxProp $Model 'Coverage'

    Add-ScoutDocxParagraph -Body $Body -Text ("This assessment covers {0} subscription(s) under scope '{1}'{2}. Findings reflect the state of the estate at the time of the scan; any remediation carried out since is not captured." -f `
        (Get-ScoutDocxProp $scope 'SubscriptionCount' 0),
        (Get-ScoutDocxProp $meta 'Scope' 'All'),
        $(if (Get-ScoutDocxProp $meta 'ManagementGroupId') { ", rooted at management group $(Get-ScoutDocxProp $meta 'ManagementGroupId')" } else { '' }))

    foreach ($line in @(
            'Azure Scout is read-only. No tenant state was created, modified or deleted to produce this report.'
            'Inheritance-based controls are treated as effective at descendant scope unless an explicit override was observed.'
            ("{0} control(s) require manual review and are excluded from every score in this report." -f (Get-ScoutDocxProp $coverage 'ManualReviewItems' 0))
            ("{0} control(s) returned no data — the source was gated behind a permission Scout does not hold, or was not collected. Neither a pass nor a failure is claimed for these." -f (Get-ScoutDocxProp $coverage 'NotAssessedItems' 0))
            'The 1-10 maturity scale is Azure Scout''s own and is not a Microsoft-published model.'
            'Triage verdicts on affected resources are heuristic suggestions, not confirmed judgements.'
        )) {
        Add-ScoutDocxParagraph -Body $Body -Text "•   $line" -SizePt 11
    }
}

#endregion

function New-ScoutDocxSectionProperties {
    # US Letter, portrait, 1" top/bottom, 0.75" left/right — twips (dxa) throughout.
    $sectPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.SectionProperties"
    $pgSz = New-ScoutDocxEl "$Script:ScoutDocxWNs.PageSize"
    $pgSz.Width = [uint32](ScoutDocxDxa 8.5)
    $pgSz.Height = [uint32](ScoutDocxDxa 11)
    $sectPr.Append($pgSz)
    $pgMar = New-ScoutDocxEl "$Script:ScoutDocxWNs.PageMargin"
    $pgMar.Top = [int32](ScoutDocxDxa 1.0)
    $pgMar.Bottom = [int32](ScoutDocxDxa 1.0)
    $pgMar.Left = [uint32](ScoutDocxDxa 0.75)
    $pgMar.Right = [uint32](ScoutDocxDxa 0.75)
    $pgMar.Header = [uint32](ScoutDocxDxa 0.5)
    $pgMar.Footer = [uint32](ScoutDocxDxa 0.5)
    $pgMar.Gutter = [uint32]0
    $sectPr.Append($pgMar)
    return , $sectPr
}

#endregion

function Export-Word {
    <#
    .SYNOPSIS
        Renders the Word (.docx) assessment report for a scored Findings object.

    .PARAMETER Findings
        The scored object returned by Get-Score (GeneratedOn/Frameworks/Areas/
        Gaps/Manual/Errors/Findings).

    .PARAMETER Collect
        Optional — the raw collect object (same one Export-Html/-Excel/-Pptx
        already receive from Export-Report.ps1). Used only to surface scope /
        management-group context on the cover page when present.

    .PARAMETER Model
        Optional — the report model from Build-ScoutReportModel (AB#6852). When present, the
        document renders the full v2 structure: document information, contents, executive
        summary with inventory tiles and composite maturity, findings dashboard, scoring
        methodology, key risk indicators, prioritised focus areas, one chapter per domain with
        its affected resources named, overall maturity summary, the 90-day roadmap, and the
        appendices including the consolidated gap register.

        When absent — a caller re-rendering a hand-edited findings.json, or a unit test that
        dot-sources only this file — Export-Word first tries to build the model itself, and
        falls back to the pre-v2 section set only if Build-ScoutReportModel is not loaded. A
        renderer that hard-fails without its model would be worse than one that renders less.

    .PARAMETER OutputPath
        Directory the rendered assessment_report.docx is written into.
    #>
    param($Findings, $Collect, [string] $OutputPath, $Model = $null)

    try {
        Import-ScoutDocxOpenXmlAssembly

        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        $outFile = Join-Path $OutputPath 'assessment_report.docx'
        if (Test-Path $outFile) { Remove-Item $outFile -Force }

        $frameworks = @(Get-ScoutDocxProp $Findings 'Frameworks')
        $areas = @(Get-ScoutDocxProp $Findings 'Areas')
        $gaps = @(Get-ScoutDocxProp $Findings 'Gaps')
        $manual = @(Get-ScoutDocxProp $Findings 'Manual')
        $errors = @(Get-ScoutDocxProp $Findings 'Errors')
        $allFindings = @(Get-ScoutDocxProp $Findings 'Findings')
        $generatedOn = Get-ScoutDocxProp $Findings 'GeneratedOn'
        $generatedText = if ($generatedOn) {
            try { ([datetime]$generatedOn).ToString('yyyy-MM-dd') } catch { "$generatedOn" }
        } else { (Get-Date).ToString('yyyy-MM-dd') }

        $scope = Get-ScoutDocxProp (Get-ScoutDocxProp $Collect '_meta') 'scope'
        $mgId = Get-ScoutDocxProp (Get-ScoutDocxProp $Collect '_meta') 'managementGroupId'
        $metaParts = [System.Collections.Generic.List[string]]::new()
        $metaParts.Add("Generated $generatedText")
        if ($scope) { $metaParts.Add("Scope: $scope") }
        if ($mgId) { $metaParts.Add("Management Group: $mgId") }
        $metaLine = [string]::Join('  ·  ', $metaParts)

        $doc = [DocumentFormat.OpenXml.Packaging.WordprocessingDocument]::Create($outFile, [DocumentFormat.OpenXml.WordprocessingDocumentType]::Document)
        $mainPart = $doc.AddMainDocumentPart()
        $mainPart.Document = New-ScoutDocxEl "$Script:ScoutDocxWNs.Document"
        $body = New-ScoutDocxEl "$Script:ScoutDocxWNs.Body"
        $mainPart.Document.Append($body)

        # ---- Cover ----
        New-ScoutDocxCoverParagraphs -Body $body -Title 'Azure Landing Zone Assessment' `
            -Subtitle 'Executive Assessment — CAF & WAF Alignment' -MetaLine $metaLine
        Add-ScoutDocxPageBreak -Body $body

        # AB#6856: prefer the report model. A caller that did not pass one still gets the v2
        # document as long as Build-ScoutReportModel is loaded; only a genuinely standalone
        # dot-source of this single file falls back to the pre-v2 sections.
        $reportModel = $Model
        if (-not $reportModel -and (Get-Command Build-ScoutReportModel -ErrorAction SilentlyContinue)) {
            try { $reportModel = Build-ScoutReportModel -Findings $Findings -Collect $Collect }
            catch { Write-Warning "Export-Word: could not build the report model ($($_.Exception.Message)) -- falling back to the summary sections." }
        }

        if ($reportModel) {
            $sections = @(
                'Document Information', 'Executive Summary', 'Findings Dashboard',
                'Maturity Scoring Methodology', 'Key Risk Indicators', 'Prioritised Focus Areas',
                'Domain Chapters', 'Overall Maturity Summary', '90-Day Remediation Roadmap',
                'Appendix A — Subscription Detail', 'Appendix B — Consolidated Gap Register',
                'Scope & Assumptions'
            )
            New-ScoutDocxDocumentInfo -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxTableOfContents -Body $body -Sections $sections
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxExecSummaryV2 -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxFindingsDashboard -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxMethodology -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxKriSection -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxFocusAreaSection -Body $body -Model $reportModel

            New-ScoutDocxDomainChapters -Body $body -Model $reportModel

            Add-ScoutDocxPageBreak -Body $body
            New-ScoutDocxMaturitySummary -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxRoadmapSection -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxAppendixSubscriptions -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxAppendixGapRegister -Body $body -Model $reportModel
            Add-ScoutDocxPageBreak -Body $body

            # Manual review is still its own worklist — it is the only section a reader can
            # act on without any Azure data behind it.
            New-ScoutDocxManualSection -Body $body -Manual $manual
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxScopeAndAssumptions -Body $body -Model $reportModel
        }
        else {
            # ---- Pre-v2 fallback: summary sections only ----
            New-ScoutDocxExecSummary -Body $body -Frameworks $frameworks -Areas $areas -Gaps $gaps -Manual $manual -Errors $errors
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxAreaFindingsSection -Body $body -Areas $areas -AllFindings $allFindings
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxGapsSection -Body $body -Gaps $gaps
            Add-ScoutDocxPageBreak -Body $body

            New-ScoutDocxManualSection -Body $body -Manual $manual
        }

        # ---- Section properties (must be the last child of w:body) ----
        $body.Append((New-ScoutDocxSectionProperties))

        $mainPart.Document.Save()
        $doc.Dispose()

        return $outFile
    }
    catch {
        Write-Warning "Export-Word: .docx generation failed ($_) -- writing an HTML fallback instead."
        return (Export-ScoutDocxHtmlFallback -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Reason $_.Exception.Message)
    }
}
