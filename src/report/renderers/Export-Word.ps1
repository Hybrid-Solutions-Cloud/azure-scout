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
    $cacheDir = Join-Path -Path $repoRoot -ChildPath 'output' -AdditionalChildPath '.tools', 'openxml', $Script:ScoutDocxOpenXmlVersion
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

function Add-ScoutDocxStyleDefinition {
    <#
    .SYNOPSIS
        Create the StyleDefinitionsPart and declare the named styles the document uses.

    .DESCRIPTION
        AB#6874, clauses W-01 and W-02. Phase 0 measured that the generated .docx contained
        THREE package parts -- _rels/.rels, [Content_Types].xml, word/document.xml -- and that
        0 of its 1,803 paragraphs carried a pStyle. Every heading was direct run formatting, so
        Word had no idea any line was a heading.

        That single fact explains four separate symptoms at once: no navigation pane, no possible
        TOC field (a TOC collects heading STYLES, and there were none), no cross-references, and
        nothing a partner could restyle to their brand.

        Sizes here are half-points (w:sz), which is why they are double the point size used by
        the direct-formatting helpers.
    #>
    param([Parameter(Mandatory)]$MainPart)

    # PowerShell 7 generic-method syntax. `AddNewPart([type])` binds to no overload -- AddNewPart
    # is generic over the part type, not a parameter taking one.
    $stylePart = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.StyleDefinitionsPart]()
    $styles = New-ScoutDocxEl "$Script:ScoutDocxWNs.Styles"

    # Heading 1-3 carry the built-in style IDs Word looks for. A custom ID would render
    # identically and still produce no navigation pane, because Word keys the outline off these.
    $spec = @(
        @{ Id = 'Heading1'; Name = 'heading 1'; SizeHalfPt = 44; Outline = 0; Before = 240; After = 120 }
        @{ Id = 'Heading2'; Name = 'heading 2'; SizeHalfPt = 32; Outline = 1; Before = 200; After = 100 }
        @{ Id = 'Heading3'; Name = 'heading 3'; SizeHalfPt = 26; Outline = 2; Before = 160; After = 80 }
    )

    foreach ($s in $spec) {
        $style = New-ScoutDocxEl "$Script:ScoutDocxWNs.Style"
        $style.Type = [DocumentFormat.OpenXml.Wordprocessing.StyleValues]::Paragraph
        $style.StyleId = $s.Id
        # PrimaryStyle marks it as one Word offers in the styles gallery, which is also what
        # makes it available as a TOC source in the UI.
        $style.CustomStyle = $false

        $name = New-ScoutDocxEl "$Script:ScoutDocxWNs.StyleName"
        $name.Val = $s.Name
        $style.Append($name)

        # CHILD ORDER IS PART OF THE SCHEMA, not a style choice. CT_PPrBase fixes the sequence
        # keepNext -> spacing -> outlineLvl, and CT_RPr fixes rFonts -> b -> color -> sz.
        # Appending them in any other order produces a package Word still opens but that fails
        # Sch_UnexpectedElementContentExpectingComplex under the SDK validator -- which the
        # Report.Word suite gates on.
        $pPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.StyleParagraphProperties"
        $keepNext = New-ScoutDocxEl "$Script:ScoutDocxWNs.KeepNext"
        $pPr.Append($keepNext)
        # AB#6875, clause W-06. numId 1 is the multilevel chapter list declared in the numbering
        # part; binding it HERE rather than at each heading call site is what makes "4.2" a
        # property of being a level-2 heading. CT_PPrBase puts numPr after keepNext and before
        # spacing -- the same schema ordering the outlineLvl comment below is about.
        $numPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.NumberingProperties"
        $ilvl = New-ScoutDocxEl "$Script:ScoutDocxWNs.NumberingLevelReference"
        $ilvl.Val = [int]$s.Outline
        $numPr.Append($ilvl)
        $numId = New-ScoutDocxEl "$Script:ScoutDocxWNs.NumberingId"
        $numId.Val = 1
        $numPr.Append($numId)
        $pPr.Append($numPr)
        $spacing = New-ScoutDocxEl "$Script:ScoutDocxWNs.SpacingBetweenLines"
        $spacing.Before = [string]$s.Before
        $spacing.After = [string]$s.After
        $pPr.Append($spacing)
        $outline = New-ScoutDocxEl "$Script:ScoutDocxWNs.OutlineLevel"
        $outline.Val = [int]$s.Outline
        $pPr.Append($outline)
        $style.Append($pPr)

        $rPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.StyleRunProperties"
        $fonts = New-ScoutDocxEl "$Script:ScoutDocxWNs.RunFonts"
        $fonts.Ascii = 'Segoe UI Semibold'
        $fonts.HighAnsi = 'Segoe UI Semibold'
        $rPr.Append($fonts)
        $bold = New-ScoutDocxEl "$Script:ScoutDocxWNs.Bold"
        $rPr.Append($bold)
        $color = New-ScoutDocxEl "$Script:ScoutDocxWNs.Color"
        $color.Val = $Script:ScoutDocxNavy
        $rPr.Append($color)
        $sz = New-ScoutDocxEl "$Script:ScoutDocxWNs.FontSize"
        $sz.Val = [string]$s.SizeHalfPt
        $rPr.Append($sz)
        $style.Append($rPr)

        $styles.Append($style)
    }

    # AB#6875, clause W-01. Heading1-3 above are the outline; these are the rest of what a
    # rebrandable document needs -- a Normal that actually carries the document defaults, a Title
    # for the cover, a Caption for figures, Header/Footer for the running furniture, toc 1-3 so
    # Word has somewhere to put the entries the TOC field collects, and a named table style.
    #
    # These are appended as XML rather than built from typed objects for one reason: CT_Style
    # child order is long and strict, and a 40-line append sequence per style hides the shape
    # being declared. The InnerXml setter parses through the same schema-aware reader, so an
    # ordering mistake still fails the validator the Report.Word suite gates on.
    $extra = @(
        @{ Type = 'paragraph'; Id = 'Normal'; Default = $true; Xml = '<w:name w:val="Normal"/><w:qFormat/>' }
        @{ Type = 'paragraph'; Id = 'Title'; Xml = @"
<w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
<w:pPr><w:spacing w:before="0" w:after="160"/><w:contextualSpacing/><w:jc w:val="center"/></w:pPr>
<w:rPr><w:rFonts w:ascii="Segoe UI Semibold" w:hAnsi="Segoe UI Semibold"/><w:b/><w:color w:val="$($Script:ScoutDocxNavy)"/><w:sz w:val="64"/></w:rPr>
"@ }
        @{ Type = 'paragraph'; Id = 'Caption'; Xml = @"
<w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
<w:pPr><w:spacing w:before="0" w:after="200"/></w:pPr>
<w:rPr><w:i/><w:color w:val="$($Script:ScoutDocxGray)"/><w:sz w:val="18"/></w:rPr>
"@ }
        @{ Type = 'paragraph'; Id = 'Header'; Xml = @"
<w:name w:val="header"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr>
<w:rPr><w:color w:val="$($Script:ScoutDocxGray)"/><w:sz w:val="16"/></w:rPr>
"@ }
        @{ Type = 'paragraph'; Id = 'Footer'; Xml = @"
<w:name w:val="footer"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr>
<w:rPr><w:color w:val="$($Script:ScoutDocxGray)"/><w:sz w:val="16"/></w:rPr>
"@ }
        @{ Type = 'paragraph'; Id = 'TOC1'; Xml = '<w:name w:val="toc 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:before="120" w:after="0"/></w:pPr><w:rPr><w:b/></w:rPr>' }
        @{ Type = 'paragraph'; Id = 'TOC2'; Xml = '<w:name w:val="toc 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:after="0"/><w:ind w:left="240"/></w:pPr>' }
        @{ Type = 'paragraph'; Id = 'TOC3'; Xml = '<w:name w:val="toc 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:after="0"/><w:ind w:left="480"/></w:pPr>' }
        @{ Type = 'paragraph'; Id = 'ListParagraph'; Xml = '<w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="60"/><w:ind w:left="720"/><w:contextualSpacing/></w:pPr>' }
        @{ Type = 'table'; Id = 'ScoutTable'; Xml = @"
<w:name w:val="Scout Table"/><w:uiPriority w:val="59"/><w:qFormat/>
<w:tblPr>
  <w:tblBorders>
    <w:top w:val="single" w:sz="4" w:space="0" w:color="$($Script:ScoutDocxLine)"/>
    <w:left w:val="single" w:sz="4" w:space="0" w:color="$($Script:ScoutDocxLine)"/>
    <w:bottom w:val="single" w:sz="4" w:space="0" w:color="$($Script:ScoutDocxLine)"/>
    <w:right w:val="single" w:sz="4" w:space="0" w:color="$($Script:ScoutDocxLine)"/>
    <w:insideH w:val="single" w:sz="4" w:space="0" w:color="$($Script:ScoutDocxLine)"/>
    <w:insideV w:val="single" w:sz="4" w:space="0" w:color="$($Script:ScoutDocxLine)"/>
  </w:tblBorders>
</w:tblPr>
<w:tblStylePr w:type="firstRow">
  <w:rPr><w:b/><w:color w:val="$($Script:ScoutDocxPaper)"/></w:rPr>
  <w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$($Script:ScoutDocxNavy)"/></w:tcPr>
</w:tblStylePr>
"@ }
    )

    foreach ($e in $extra) {
        $style = New-ScoutDocxEl "$Script:ScoutDocxWNs.Style"
        $style.Type = switch ($e.Type) {
            'table' { [DocumentFormat.OpenXml.Wordprocessing.StyleValues]::Table }
            default { [DocumentFormat.OpenXml.Wordprocessing.StyleValues]::Paragraph }
        }
        $style.StyleId = $e.Id
        $style.CustomStyle = $false
        if ($e.ContainsKey('Default')) { $style.Default = [bool]$e.Default }
        $style.InnerXml = $e.Xml
        $styles.Append($style)
    }

    # docDefaults is the FIRST child of w:styles (CT_Styles: docDefaults, latentStyles, style*),
    # so it is inserted rather than appended. It is what makes Segoe UI the document font instead
    # of every run having to declare it.
    $docDefaults = New-ScoutDocxEl "$Script:ScoutDocxWNs.DocDefaults"
    $docDefaults.InnerXml = @"
<w:rPrDefault><w:rPr><w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI" w:cs="Segoe UI"/><w:color w:val="$($Script:ScoutDocxInk)"/><w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>
"@
    $styles.InsertAt($docDefaults, 0)

    $stylePart.Styles = $styles
    return $stylePart
}

function Add-ScoutDocxNumberingPart {
    <#
    .SYNOPSIS
        Declare the chapter-numbering and bullet lists, and bind Heading1-3 to the first.

    .DESCRIPTION
        AB#6875, clause W-06. The reference deliverable has 14 NUMBERED sections and every
        cross-reference in its text ("see 4.2") depends on that numbering being real. Scout's
        headings were unnumbered text, so a reader had no way to refer to one.

        numId 1 is the multilevel chapter list, bound to the heading styles by w:pStyle so a
        heading is numbered by virtue of BEING a heading -- nothing at the call site has to
        count. numId 2 is the plain bullet the summary lists use.
    #>
    param([Parameter(Mandatory)]$MainPart)

    $part = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.NumberingDefinitionsPart]()
    $xml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:multiLevelType w:val="multilevel"/>
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="Heading1"/>
      <w:lvlText w:val="%1"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="0" w:firstLine="0"/></w:pPr>
    </w:lvl>
    <w:lvl w:ilvl="1">
      <w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="Heading2"/>
      <w:lvlText w:val="%1.%2"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="0" w:firstLine="0"/></w:pPr>
    </w:lvl>
    <w:lvl w:ilvl="2">
      <w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="Heading3"/>
      <w:lvlText w:val="%1.%2.%3"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="0" w:firstLine="0"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:abstractNum w:abstractNumId="1">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/><w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
      <w:rPr><w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI" w:hint="default"/></w:rPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>
"@
    Set-ScoutDocxPartXml -Part $part -Xml $xml
    return $part
}

function Add-ScoutDocxThemePart {
    <#
    .SYNOPSIS
        Declare the document theme carrying the Scout palette.

    .DESCRIPTION
        AB#6875, clause W-07. Every colour the body uses is declared here as a theme slot, which
        is what makes the document rebrandable: a partner swaps the clrScheme and the whole
        deliverable follows. Without a theme part the hex values in the body are the only
        definition of the brand, and there is nothing to swap.

        The twelve slots are the full Scout chrome palette -- the conformance test asserts that
        no run in the body carries a hex absent from this list, so adding a colour to a renderer
        means adding it here too. That coupling is deliberate.
    #>
    param([Parameter(Mandatory)]$MainPart)

    $part = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.ThemePart]()
    $line = '<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
    $fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    $xml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Azure Scout">
  <a:themeElements>
    <a:clrScheme name="Azure Scout">
      <a:dk1><a:srgbClr val="$($Script:ScoutDocxInk)"/></a:dk1>
      <a:lt1><a:srgbClr val="$($Script:ScoutDocxPaper)"/></a:lt1>
      <a:dk2><a:srgbClr val="$($Script:ScoutDocxNavy)"/></a:dk2>
      <a:lt2><a:srgbClr val="$($Script:ScoutDocxMist)"/></a:lt2>
      <a:accent1><a:srgbClr val="$($Script:ScoutDocxSteel)"/></a:accent1>
      <a:accent2><a:srgbClr val="$($Script:ScoutDocxGreen)"/></a:accent2>
      <a:accent3><a:srgbClr val="$($Script:ScoutDocxGold)"/></a:accent3>
      <a:accent4><a:srgbClr val="$($Script:ScoutDocxRed)"/></a:accent4>
      <a:accent5><a:srgbClr val="$($Script:ScoutDocxGray)"/></a:accent5>
      <a:accent6><a:srgbClr val="$($Script:ScoutDocxLine)"/></a:accent6>
      <a:hlink><a:srgbClr val="$($Script:ScoutDocxSteel)"/></a:hlink>
      <a:folHlink><a:srgbClr val="$($Script:ScoutDocxGray)"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Azure Scout">
      <a:majorFont><a:latin typeface="Segoe UI Semibold"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
      <a:minorFont><a:latin typeface="Segoe UI"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
    </a:fontScheme>
    <a:fmtScheme name="Azure Scout">
      <a:fillStyleLst>$fill$fill$fill</a:fillStyleLst>
      <a:lnStyleLst>$line$line$line</a:lnStyleLst>
      <a:effectStyleLst>
        <a:effectStyle><a:effectLst/></a:effectStyle>
        <a:effectStyle><a:effectLst/></a:effectStyle>
        <a:effectStyle><a:effectLst/></a:effectStyle>
      </a:effectStyleLst>
      <a:bgFillStyleLst>$fill$fill$fill</a:bgFillStyleLst>
    </a:fmtScheme>
  </a:themeElements>
</a:theme>
"@
    Set-ScoutDocxPartXml -Part $part -Xml $xml
    return $part
}

function Add-ScoutDocxHeaderPart {
    <#
    .SYNOPSIS
        The running header — assessment name left, classification right.

    .DESCRIPTION
        AB#6875, clause W-03. A page pulled out of a 40-page deliverable and put in front of
        someone has to say what it is and how far it may travel. That is the whole job of the
        header, and Scout's documents had none.
    #>
    param([Parameter(Mandatory)]$MainPart, [string]$Title, [string]$Classification)

    $part = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.HeaderPart]()
    $xml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Header"/>
      <w:pBdr><w:bottom w:val="single" w:sz="4" w:space="4" w:color="$($Script:ScoutDocxLine)"/></w:pBdr>
      <w:tabs><w:tab w:val="right" w:pos="9360"/></w:tabs>
    </w:pPr>
    <w:r><w:t xml:space="preserve">$(ConvertTo-ScoutDocxXmlText $Title)</w:t></w:r>
    <w:r><w:tab/><w:t xml:space="preserve">$(ConvertTo-ScoutDocxXmlText $Classification)</w:t></w:r>
  </w:p>
</w:hdr>
"@
    Set-ScoutDocxPartXml -Part $part -Xml $xml
    return $part
}

function Add-ScoutDocxFooterPart {
    <#
    .SYNOPSIS
        The running footer — provenance left, "Page N of M" right, as real fields.

    .DESCRIPTION
        AB#6875, clause W-04. PAGE and NUMPAGES are FIELDS, not text: they have to survive the
        document being edited, re-paginated or have a section inserted. A rendered page number
        would be wrong the moment anyone touched the file, which is worse than none.
    #>
    param([Parameter(Mandatory)]$MainPart, [string]$Provenance)

    $part = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.FooterPart]()
    $xml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Footer"/>
      <w:pBdr><w:top w:val="single" w:sz="4" w:space="4" w:color="$($Script:ScoutDocxLine)"/></w:pBdr>
      <w:tabs><w:tab w:val="right" w:pos="9360"/></w:tabs>
    </w:pPr>
    <w:r><w:t xml:space="preserve">$(ConvertTo-ScoutDocxXmlText $Provenance)</w:t></w:r>
    <w:r><w:tab/><w:t xml:space="preserve">Page </w:t></w:r>
    <w:r><w:fldChar w:fldCharType="begin"/></w:r>
    <w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate"/></w:r>
    <w:r><w:t>1</w:t></w:r>
    <w:r><w:fldChar w:fldCharType="end"/></w:r>
    <w:r><w:t xml:space="preserve"> of </w:t></w:r>
    <w:r><w:fldChar w:fldCharType="begin"/></w:r>
    <w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate"/></w:r>
    <w:r><w:t>1</w:t></w:r>
    <w:r><w:fldChar w:fldCharType="end"/></w:r>
  </w:p>
</w:ftr>
"@
    Set-ScoutDocxPartXml -Part $part -Xml $xml
    return $part
}

function Add-ScoutDocxBlankHeaderFooterPart {
    <#
    .SYNOPSIS
        Empty first-page header and footer, so the cover carries no running furniture.
    #>
    param([Parameter(Mandatory)]$MainPart)

    $hdr = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.HeaderPart]()
    Set-ScoutDocxPartXml -Part $hdr -Xml '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Header"/></w:pPr></w:p></w:hdr>'
    $ftr = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.FooterPart]()
    Set-ScoutDocxPartXml -Part $ftr -Xml '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Footer"/></w:pPr></w:p></w:ftr>'
    return @{ Header = $hdr; Footer = $ftr }
}

function Add-ScoutDocxSettingsPart {
    <#
    .SYNOPSIS
        Document settings, carrying updateFields so the TOC builds on first open.

    .DESCRIPTION
        AB#6875. A TOC field emitted by a generator has no cached result, so without this Word
        shows the placeholder text until someone knows to press F9. updateFields makes Word
        offer to build it on open, which is the difference between a working TOC and one the
        reader has to be told about.
    #>
    param([Parameter(Mandatory)]$MainPart)

    $part = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.DocumentSettingsPart]()
    Set-ScoutDocxPartXml -Part $part -Xml '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:updateFields w:val="true"/></w:settings>'
    return $part
}

function Set-ScoutDocxPartXml {
    # Feeds raw part XML through the SDK's own reader, so a malformed or mis-ordered part fails
    # the validator rather than shipping a package Word silently repairs.
    param([Parameter(Mandatory)]$Part, [Parameter(Mandatory)][string]$Xml)
    $ms = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($Xml))
    try { $Part.FeedData($ms) } finally { $ms.Dispose() }
}

function Get-ScoutDocxReportVersion {
    # AB#6875, clause W-09. Read from the module manifest rather than hardcoded -- a version in
    # the Document Information block that does not track the module is worse than no version,
    # because a reader will trust it.
    [OutputType([string])]
    param()
    try {
        $repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $manifest = Join-Path $repoRoot 'AzureScout.psd1'
        if (Test-Path $manifest) {
            $data = Import-PowerShellDataFile -Path $manifest -ErrorAction Stop
            if ($data.ContainsKey('ModuleVersion')) { return "Azure Scout $($data.ModuleVersion)" }
        }
    }
    catch {
        # A missing or unreadable manifest is not a reason to fail a render.
        Write-Verbose "Export-Word: could not read the module version ($_)."
    }
    return 'Azure Scout (version not resolved)'
}

function ConvertTo-ScoutDocxXmlText {
    # Tenant names and scopes are attacker-adjacent free text as far as this renderer is
    # concerned -- they come from Azure, not from us. Escaping here keeps a resource named
    # "A & B <prod>" from producing a package Word refuses to open.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return ($Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
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

# AB#6875, clause W-13. A table longer than this belongs in an appendix — past roughly a page
# the reader has stopped reading and started scrolling, and the narrative it was supporting is
# already off-screen. The body keeps a bounded extract and a pointer.
$Script:ScoutDocxBodyTableMaxRows = 30

# Front-matter constants. Classification is what tells a reader how far the document may travel;
# a deliverable carrying real tenant findings is not a public document, and saying so is the
# renderer's job, not the reader's guess.
$Script:ScoutDocxClassification = 'CONFIDENTIAL — prepared for the named client'
$Script:ScoutDocxAuthor = 'Azure Scout'
$Script:ScoutDocxProvenance = 'Azure Resource Graph and Microsoft Graph, read-only, collected by Azure Scout'

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
    $para = New-ScoutDocxPara -Runs $runs -SpaceBeforePt $spaceBefore -SpaceAfterPt 6 -KeepNext $true

    # AB#6874, clause W-02. The pStyle is what makes this a HEADING rather than large bold text.
    # Without it Word builds no navigation pane and a TOC field collects nothing, which is
    # exactly what Phase 0 measured: 0 of 1,803 paragraphs styled.
    #
    # The direct formatting above is deliberately KEPT alongside it. The style supplies the
    # outline level and the semantics; the direct run properties guarantee the document still
    # looks right in a reader that ignores the style part, and they render identically because
    # both describe the same Segoe UI Semibold navy.
    $pStyle = New-ScoutDocxEl "$Script:ScoutDocxWNs.ParagraphStyleId"
    $pStyle.Val = "Heading$([Math]::Min([Math]::Max($Level, 1), 3))"
    # Generic, like AddNewPart above -- `GetFirstChild([type])` binds to no overload.
    $pPr = $para.GetFirstChild[DocumentFormat.OpenXml.Wordprocessing.ParagraphProperties]()
    if ($null -eq $pPr) {
        $pPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.ParagraphProperties"
        $para.InsertAt($pPr, 0)
    }
    $pPr.InsertAt($pStyle, 0)

    $Body.Append($para)
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Collect', Justification = 'Kept for signature parity -- mirrors Export-Pdf.ps1''s Export-ScoutPdfHtmlFallback pattern (see this function''s region header).')]
    param($Findings, $Collect, [string] $OutputPath, [string] $Reason)
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $json = ($Findings | ConvertTo-Json -Depth 100) -replace '</', '<\/'
    $safeReason = $Reason -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $generatedOn = Get-ScoutDocxProp -Obj $Findings -Name 'GeneratedOn' -Default '(unknown)'
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

function New-ScoutDocxCoverParagraph {
    <#
    .SYNOPSIS
        The cover page — the four facts that make a deliverable read as "for them".

    .DESCRIPTION
        AB#6875, clause W-08. The reference deliverable's cover carries client, assessment,
        scan date and classification, and every one of those is load-bearing: without the
        client name the document is generic, without the scan date its numbers are undated
        claims, and without a classification nobody knows how far it may travel.
    #>
    param(
        $Body,
        [string]$Title,
        [string]$Subtitle,
        [string]$MetaLine,
        [string]$ClientName,
        [string]$ScanDate,
        [string]$Classification = $Script:ScoutDocxClassification
    )

    $wmRuns = New-ScoutDocxList
    $wmRuns.Add((New-ScoutDocxRun -Text 'AZURE SCOUT' -SizePt 12 -Hex $Script:ScoutDocxSteel -Bold $true))
    $Body.Append((New-ScoutDocxPara -Runs $wmRuns -Align 'center' -SpaceBeforePt 60 -SpaceAfterPt 12))

    # The cover title takes the Title STYLE, not direct formatting -- it is the one paragraph a
    # rebranding partner is guaranteed to want to restyle.
    $titleRuns = New-ScoutDocxList
    $titleRuns.Add((New-ScoutDocxRun -Text $Title -SizePt 32 -Hex $Script:ScoutDocxNavy -Bold $true -Font 'Segoe UI Semibold'))
    $titlePara = New-ScoutDocxPara -Runs $titleRuns -Align 'center' -SpaceAfterPt 8
    Set-ScoutDocxParaStyle -Paragraph $titlePara -StyleId 'Title'
    $Body.Append($titlePara)

    if ($Subtitle) {
        $subRuns = New-ScoutDocxList
        $subRuns.Add((New-ScoutDocxRun -Text $Subtitle -SizePt 15 -Hex $Script:ScoutDocxGray))
        $Body.Append((New-ScoutDocxPara -Runs $subRuns -Align 'center' -SpaceAfterPt 24))
    }

    if ($ClientName) {
        $clientRuns = New-ScoutDocxList
        $clientRuns.Add((New-ScoutDocxRun -Text 'Prepared for' -SizePt 10 -Hex $Script:ScoutDocxGray))
        $Body.Append((New-ScoutDocxPara -Runs $clientRuns -Align 'center' -SpaceAfterPt 2))
        $nameRuns = New-ScoutDocxList
        $nameRuns.Add((New-ScoutDocxRun -Text $ClientName -SizePt 18 -Hex $Script:ScoutDocxNavy -Bold $true -Font 'Segoe UI Semibold'))
        $Body.Append((New-ScoutDocxPara -Runs $nameRuns -Align 'center' -SpaceAfterPt 20))
    }

    if ($ScanDate) {
        $dateRuns = New-ScoutDocxList
        $dateRuns.Add((New-ScoutDocxRun -Text "Scan date: $ScanDate" -SizePt 11 -Hex $Script:ScoutDocxInk))
        $Body.Append((New-ScoutDocxPara -Runs $dateRuns -Align 'center' -SpaceAfterPt 6))
    }

    if ($MetaLine) {
        $metaRuns = New-ScoutDocxList
        $metaRuns.Add((New-ScoutDocxRun -Text $MetaLine -SizePt 11 -Hex $Script:ScoutDocxGray -Italic $true))
        $Body.Append((New-ScoutDocxPara -Runs $metaRuns -Align 'center' -SpaceAfterPt 6))
    }

    if ($Classification) {
        # Rendered as a full-width banded row rather than a paragraph: on a cover it has to read
        # as a stamp, not as another line of body text the eye skips.
        #
        # The List[object] here is not stylistic. `@($cell)` ENUMERATES the cell -- every
        # OpenXmlElement is IEnumerable over its own children -- so it would produce an array of
        # the cell's tcPr and paragraph, both already parented, and the append fails with
        # "part of a tree". That is the same unrolling trap this file's header documents for
        # `return ,$x`, and it bites on the way IN as well as on the way out.
        $clsCells = New-ScoutDocxList
        $clsCells.Add((New-ScoutDocxCell -Text $Classification -WidthIn 6.5 -SizePt 10 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy -Align 'center'))
        $clsRows = New-ScoutDocxList
        $clsRows.Add((New-ScoutDocxRow -Cells $clsCells))
        $Body.Append((New-ScoutDocxTable -ColWidthsIn @(6.5) -Rows $clsRows))
    }
}

function New-ScoutDocxDocumentInformation {
    <#
    .SYNOPSIS
        The Document Information block — what makes the numbers auditable.

    .DESCRIPTION
        AB#6875, clause W-09. This is the block that separates a consultancy deliverable from a
        tool's output: it states where the data came from, when, at what version, and against
        which frameworks. A reader who disagrees with a finding can go and check it.

        Note it is deliberately NOT numbered as a chapter -- it is front matter, the same as the
        cover, so it uses a styled non-heading paragraph rather than Heading1.
    #>
    param($Body, [string]$Version, [string]$Author, $Frameworks, [string]$Provenance, [string]$ScanDate, [string]$Scope)

    $labelRuns = New-ScoutDocxList
    $labelRuns.Add((New-ScoutDocxRun -Text 'Document Information' -SizePt 16 -Hex $Script:ScoutDocxNavy -Bold $true -Font 'Segoe UI Semibold'))
    $Body.Append((New-ScoutDocxPara -Runs $labelRuns -SpaceBeforePt 12 -SpaceAfterPt 8 -KeepNext $true))

    $fwNames = @(@($Frameworks) | ForEach-Object { "$(Get-ScoutDocxProp -Obj $_ -Name 'Framework')" } | Where-Object { $_ })
    $fwText = if ($fwNames.Count -gt 0) { [string]::Join(', ', $fwNames) } else { 'None scored for this run' }

    $rowSpec = [ordered]@{
        'Report version'         = $Version
        'Author'                 = $Author
        'Frameworks referenced'  = $fwText
        'Source data provenance' = $Provenance
        'Scan date'              = $ScanDate
        'Scope'                  = $(if ($Scope) { $Scope } else { 'Not recorded' })
    }

    $rows = New-ScoutDocxList
    $header = New-ScoutDocxList
    $header.Add((New-ScoutDocxCell -Text 'Field' -WidthIn 2.0 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    $header.Add((New-ScoutDocxCell -Text 'Value' -WidthIn 4.5 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

    $r = 0
    foreach ($k in $rowSpec.Keys) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $cells = New-ScoutDocxList
        $cells.Add((New-ScoutDocxCell -Text $k -WidthIn 2.0 -Bold $true -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text "$($rowSpec[$k])" -WidthIn 4.5 -FillHex $bg))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @(2.0, 4.5) -Rows $rows))
}

function New-ScoutDocxTableOfContents {
    <#
    .SYNOPSIS
        A real TOC field.

    .DESCRIPTION
        AB#6875, clause W-05. The previous "table of contents" was a list of plain paragraphs:
        it did not link, did not update, and did not know the page numbers. This is the field
        Word itself resolves against the heading styles, which is why W-01/W-02 had to land
        first -- a TOC field over an unstyled document collects nothing.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = '"Table of Contents" is a fixed English term with no valid singular form.')]
    param($Body)

    $headRuns = New-ScoutDocxList
    $headRuns.Add((New-ScoutDocxRun -Text 'Contents' -SizePt 16 -Hex $Script:ScoutDocxNavy -Bold $true -Font 'Segoe UI Semibold'))
    $Body.Append((New-ScoutDocxPara -Runs $headRuns -SpaceBeforePt 12 -SpaceAfterPt 8 -KeepNext $true))

    $p = New-ScoutDocxEl "$Script:ScoutDocxWNs.Paragraph"
    $p.InnerXml = @'
<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>
<w:r><w:instrText xml:space="preserve"> TOC \o "1-3" \h \z \u </w:instrText></w:r>
<w:r><w:fldChar w:fldCharType="separate"/></w:r>
<w:r><w:rPr><w:i/><w:color w:val="595959"/></w:rPr><w:t xml:space="preserve">Select this line and press F9 to build the table of contents.</w:t></w:r>
<w:r><w:fldChar w:fldCharType="end"/></w:r>
'@
    $Body.Append($p)
}

function Set-ScoutDocxParaStyle {
    # Puts a pStyle at the head of a paragraph's properties, creating the properties element if
    # the paragraph has none. Same insert-at-zero rule Add-ScoutDocxHeading documents: pStyle is
    # the FIRST child of CT_PPr, always.
    param([Parameter(Mandatory)]$Paragraph, [Parameter(Mandatory)][string]$StyleId)
    $pStyle = New-ScoutDocxEl "$Script:ScoutDocxWNs.ParagraphStyleId"
    $pStyle.Val = $StyleId
    $pPr = $Paragraph.GetFirstChild[DocumentFormat.OpenXml.Wordprocessing.ParagraphProperties]()
    if ($null -eq $pPr) {
        $pPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.ParagraphProperties"
        $Paragraph.InsertAt($pPr, 0)
    }
    $pPr.InsertAt($pStyle, 0)
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
            $score = Get-ScoutDocxProp -Obj $fw -Name 'Score'
            $scoreText = if ($null -eq $score) { 'Not scored' } else { "$score / 100" }
            $cells = New-ScoutDocxList
            $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $fw -Name 'Framework')" -WidthIn 3.0 -FillHex $bg))
            $cells.Add((New-ScoutDocxCell -Text $scoreText -WidthIn 3.0 -Bold $true -Hex (Get-ScoutDocxScoreColor $score) -FillHex $bg -Align 'center'))
            $rows.Add((New-ScoutDocxRow -Cells $cells))
        }
        $Body.Append((New-ScoutDocxTable -ColWidthsIn @(3.0, 3.0) -Rows $rows))
    }

    $areaArr = @($Areas)
    $passSum = ($areaArr | ForEach-Object { Get-ScoutDocxProp -Obj $_ -Name 'Pass' -Default 0 } | Measure-Object -Sum).Sum
    $partialSum = ($areaArr | ForEach-Object { Get-ScoutDocxProp -Obj $_ -Name 'Partial' -Default 0 } | Measure-Object -Sum).Sum
    $failSum = ($areaArr | ForEach-Object { Get-ScoutDocxProp -Obj $_ -Name 'Fail' -Default 0 } | Measure-Object -Sum).Sum
    $manualCount = @($Manual).Count
    $errorCount = @($Errors).Count
    $highGaps = @($Gaps | Where-Object { (Get-ScoutDocxSeverityLabel (Get-ScoutDocxProp -Obj $_ -Name 'Severity')) -eq 'HIGH' }).Count

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

function New-ScoutDocxAreaScorecard {
    <#
    .SYNOPSIS
        The chapter-level scorecard — the first thing under every domain heading.

    .DESCRIPTION
        AB#6875, clause W-11. The reference deliverable opens every chapter with the same shape:
        scorecard, current state, findings, actions. The scorecard exists so a reader who reads
        ONLY the first table of each chapter still leaves with the right picture.

        "Not assessed" is a first-class column here (clause W-17). Rolling manual controls into
        a zero would misreport the estate as failing controls nobody has looked at.
    #>
    param($Body, $Area)

    $score = Get-ScoutDocxProp -Obj $Area -Name 'Score'
    $scoreText = if ($null -eq $score) { 'Not assessed' } else { "$score / 100" }
    $pass = Get-ScoutDocxProp -Obj $Area -Name 'Pass' -Default 0
    $partial = Get-ScoutDocxProp -Obj $Area -Name 'Partial' -Default 0
    $fail = Get-ScoutDocxProp -Obj $Area -Name 'Fail' -Default 0
    $notAssessed = Get-ScoutDocxProp -Obj $Area -Name 'Manual' -Default 0

    $spec = [ordered]@{
        'Alignment score' = $scoreText
        'Pass'            = "$pass"
        'Partial'         = "$partial"
        'Fail'            = "$fail"
        'Not assessed'    = "$notAssessed"
    }

    $header = New-ScoutDocxList
    $values = New-ScoutDocxList
    foreach ($k in $spec.Keys) {
        $header.Add((New-ScoutDocxCell -Text $k -WidthIn 1.3 -SizePt 9 -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy -Align 'center'))
        $hex = if ($k -eq 'Alignment score') { Get-ScoutDocxScoreColor $score } else { $Script:ScoutDocxInk }
        $values.Add((New-ScoutDocxCell -Text $spec[$k] -WidthIn 1.3 -SizePt 12 -Bold $true -Hex $hex -FillHex $Script:ScoutDocxMist -Align 'center'))
    }
    $rows = New-ScoutDocxList
    $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))
    $rows.Add((New-ScoutDocxRow -Cells $values))
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @(1.3, 1.3, 1.3, 1.3, 1.3) -Rows $rows))
}

function Get-ScoutDocxCurrentState {
    <#
    .SYNOPSIS
        The Current State sentence for one chapter.

    .DESCRIPTION
        AB#6875, clauses W-11 and W-16. This is deliberately a COMPARATIVE/AGGREGATE sentence
        about the whole area rather than a per-rule template -- "13 of 19 controls in this area
        are aligned" is a property of the run, and it is the kind of sentence a non-specialist
        can act on. A per-rule restatement of the table below it adds nothing.

        Clause W-17 is why "not assessed" is stated separately and never folded into the failures.
    #>
    [OutputType([string])]
    param($Area)

    $pass = [int](Get-ScoutDocxProp -Obj $Area -Name 'Pass' -Default 0)
    $partial = [int](Get-ScoutDocxProp -Obj $Area -Name 'Partial' -Default 0)
    $fail = [int](Get-ScoutDocxProp -Obj $Area -Name 'Fail' -Default 0)
    $manual = [int](Get-ScoutDocxProp -Obj $Area -Name 'Manual' -Default 0)
    $automated = $pass + $partial + $fail

    if ($automated -eq 0 -and $manual -eq 0) {
        return 'No controls were evaluated in this area for this run.'
    }
    if ($automated -eq 0) {
        return "None of the $manual control(s) in this area can be evaluated automatically; all $manual are pending manual review and are reported as Not assessed, not as failures."
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("$pass of $automated automatically evaluated control(s) in this area are aligned")
    if ($partial -gt 0) { $parts.Add("$partial are partially aligned") }
    if ($fail -gt 0) { $parts.Add("$fail are not aligned") }
    $sentence = [string]::Join(', ', $parts) + '.'
    if ($manual -gt 0) {
        $sentence += " A further $manual control(s) require manual review and are reported as Not assessed."
    }
    return $sentence
}

function New-ScoutDocxActionItem {
    <#
    .SYNOPSIS
        The action items closing a chapter — owner and effort per row, so it can be assigned.

    .DESCRIPTION
        AB#6875, clause W-11. A findings table describes; an action table assigns. Effort is
        derived from severity rather than invented, and the owner column is stated as unassigned
        rather than guessed -- claiming an owner the run cannot know would be exactly the kind of
        unmeasured assertion clause W-17 exists to stop.
    #>
    param($Body, $AreaFindings)

    $actionable = @(@($AreaFindings) | Where-Object {
            $s = "$(Get-ScoutDocxProp -Obj $_ -Name 'Status')"
            $s -eq 'Fail' -or $s -eq 'Partial'
        } | Sort-Object @{ Expression = { Get-ScoutDocxSeverityRank (Get-ScoutDocxProp -Obj $_ -Name 'Severity') } }, Id)

    Add-ScoutDocxHeading -Body $Body -Text 'Action items' -Level 3
    if ($actionable.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No action items — every automatically evaluated control in this area is aligned.' -Hex $Script:ScoutDocxGreen
        return
    }

    $rows = New-ScoutDocxList
    $header = New-ScoutDocxList
    foreach ($h in 'Id', 'Action', 'Effort', 'Owner') {
        $w = switch ($h) { 'Id' { 1.2 } 'Action' { 3.3 } 'Effort' { 1.0 } default { 1.0 } }
        $header.Add((New-ScoutDocxCell -Text $h -WidthIn $w -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    }
    $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

    $r = 0
    foreach ($f in $actionable) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $remediation = "$(Get-ScoutDocxProp -Obj $f -Name 'Remediation')"
        if (-not $remediation.Trim()) { $remediation = "$(Get-ScoutDocxProp -Obj $f -Name 'Title')" }
        $effort = switch (Get-ScoutDocxSeverityRank (Get-ScoutDocxProp -Obj $f -Name 'Severity')) {
            0 { 'High' }
            1 { 'Medium' }
            2 { 'Low' }
            default { 'Unsized' }
        }
        $cells = New-ScoutDocxList
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $f -Name 'Id')" -WidthIn 1.2 -SizePt 9 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text $remediation -WidthIn 3.3 -SizePt 9 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text $effort -WidthIn 1.0 -SizePt 9 -FillHex $bg -Align 'center'))
        $cells.Add((New-ScoutDocxCell -Text 'Unassigned' -WidthIn 1.0 -SizePt 9 -Hex $Script:ScoutDocxGray -FillHex $bg -Align 'center'))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @(1.2, 3.3, 1.0, 1.0) -Rows $rows))
}

function New-ScoutDocxFindingsTable {
    # The findings table for one chapter, as an element rather than appended in place -- clause
    # W-13 needs the SAME table emitted either in the body or in the appendix depending on its
    # length, and building it twice is how the two drift apart.
    param($AreaFindings)

    $rows = New-ScoutDocxList
    $header = New-ScoutDocxList
    foreach ($h in 'Id', 'Severity', 'Status', 'Title') {
        $w = switch ($h) { 'Id' { 1.3 } 'Severity' { 1.0 } 'Status' { 1.0 } default { 3.2 } }
        $header.Add((New-ScoutDocxCell -Text $h -WidthIn $w -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    }
    $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

    $r = 0
    foreach ($f in (@($AreaFindings) | Sort-Object @{ Expression = { Get-ScoutDocxSeverityRank (Get-ScoutDocxProp -Obj $_ -Name 'Severity') } }, Id)) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $sevLabel = Get-ScoutDocxSeverityLabel (Get-ScoutDocxProp -Obj $f -Name 'Severity')
        $sevColor = Get-ScoutDocxSeverityColor (Get-ScoutDocxProp -Obj $f -Name 'Severity')
        # Clause W-17: a manual control is Not assessed, never a zero and never a pass.
        $status = "$(Get-ScoutDocxProp -Obj $f -Name 'Status')"
        if ($status -eq 'Manual') { $status = 'Not assessed' }
        $cells = New-ScoutDocxList
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $f -Name 'Id')" -WidthIn 1.3 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text $sevLabel -WidthIn 1.0 -Bold $true -Hex $Script:ScoutDocxPaper -FillHex $sevColor -Align 'center'))
        $cells.Add((New-ScoutDocxCell -Text $status -WidthIn 1.0 -FillHex $bg -Align 'center'))
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $f -Name 'Title')" -WidthIn 3.2 -FillHex $bg))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    return , (New-ScoutDocxTable -ColWidthsIn @(1.3, 1.0, 1.0, 3.2) -Rows $rows)
}

function New-ScoutDocxAreaFindingsSection {
    <#
    .SYNOPSIS
        One numbered chapter per assessed domain, in the reference deliverable's shape.

    .DESCRIPTION
        AB#6875, clause W-11: scorecard -> Current State -> findings table -> action items, in
        that order, for every domain. Phase 0's document was a flat list of tables under one
        heading, which is why it read as a tool's output rather than as chapters.

        Clause W-13: a findings table longer than $Script:ScoutDocxBodyTableMaxRows rows is
        emitted to the appendix instead, and the body keeps a pointer. The returned list is the
        appendix worklist -- the caller emits it after the last chapter.
    #>
    param($Body, $Areas, $AllFindings)

    $appendix = [System.Collections.Generic.List[object]]::new()

    Add-ScoutDocxHeading -Body $Body -Text 'Findings by Area' -Level 1

    # @(...) wraps the WHOLE pipeline, not just $Areas -- Sort-Object over zero
    # input emits nothing, which collapses a bare assignment to $null (and
    # $null.Count throws under Set-StrictMode -Version Latest). Same
    # load-bearing pattern Get-Score.ps1 documents for its own Pass/Fail counters.
    $sortedAreas = @(@($Areas) | Sort-Object Framework, Area)
    if ($sortedAreas.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No areas were assessed for this run.' -Hex $Script:ScoutDocxGray
        return , $appendix
    }

    foreach ($area in $sortedAreas) {
        $framework = Get-ScoutDocxProp -Obj $area -Name 'Framework'
        $areaName = Get-ScoutDocxProp -Obj $area -Name 'Area'
        $score = Get-ScoutDocxProp -Obj $area -Name 'Score'
        $scoreText = if ($null -eq $score) { 'not scored' } else { "$score / 100" }
        Add-ScoutDocxHeading -Body $Body -Text "$framework — $areaName (Score: $scoreText)" -Level 2

        New-ScoutDocxAreaScorecard -Body $Body -Area $area

        Add-ScoutDocxHeading -Body $Body -Text 'Current state' -Level 3
        Add-ScoutDocxParagraph -Body $Body -Text (Get-ScoutDocxCurrentState -Area $area)

        $areaFindings = @($AllFindings | Where-Object {
                (Get-ScoutDocxProp -Obj $_ -Name 'Framework') -eq $framework -and (Get-ScoutDocxProp -Obj $_ -Name 'Area') -eq $areaName
            })

        Add-ScoutDocxHeading -Body $Body -Text 'Findings' -Level 3

        if ($areaFindings.Count -eq 0) {
            Add-ScoutDocxParagraph -Body $Body -Text 'No individual findings recorded for this area.' -Hex $Script:ScoutDocxGray -Italic $true
            New-ScoutDocxActionItem -Body $Body -AreaFindings $areaFindings
            continue
        }

        # Clause W-13. Past the row cap the table stops supporting the narrative and starts
        # burying it, so the long ones move to the appendix and the body keeps a pointer.
        if ($areaFindings.Count -gt $Script:ScoutDocxBodyTableMaxRows) {
            $appendixLabel = "Appendix $([char](64 + $appendix.Count + 1))"
            $appendix.Add([pscustomobject]@{
                    Label    = $appendixLabel
                    Title    = "$framework — $areaName findings"
                    Findings = $areaFindings
                })
            Add-ScoutDocxParagraph -Body $Body -Text "$($areaFindings.Count) findings were recorded for this area — the full table is in $appendixLabel." -Italic $true -Hex $Script:ScoutDocxGray
        }
        else {
            $Body.Append((New-ScoutDocxFindingsTable -AreaFindings $areaFindings))
        }

        New-ScoutDocxActionItem -Body $Body -AreaFindings $areaFindings
        Add-ScoutDocxParagraph -Body $Body -Text ' ' -SizePt 4
    }

    return , $appendix
}

function New-ScoutDocxAppendix {
    <#
    .SYNOPSIS
        Emit the long tables the body deferred.

    .DESCRIPTION
        AB#6875, clause W-13. Each appendix carries the SAME table the body would have shown,
        built by the same function, so there is no second rendering path to drift.
    #>
    param($Body, $Appendix)

    $items = @($Appendix)
    if ($items.Count -eq 0) { return }

    Add-ScoutDocxPageBreak -Body $Body
    Add-ScoutDocxHeading -Body $Body -Text 'Appendices' -Level 1
    Add-ScoutDocxParagraph -Body $Body -Text 'Tables deferred from the body because of their length. Each is the complete list for its chapter.' -Hex $Script:ScoutDocxGray -Italic $true

    foreach ($a in $items) {
        Add-ScoutDocxHeading -Body $Body -Text "$($a.Label) — $($a.Title)" -Level 2
        $Body.Append((New-ScoutDocxFindingsTable -AreaFindings $a.Findings))
        Add-ScoutDocxParagraph -Body $Body -Text ' ' -SizePt 4
    }
}

function Get-ScoutDocxEvidenceSummary {
    <#
    .SYNOPSIS
        The supporting number for one finding, as a short cell string.

    .DESCRIPTION
        AB#6862/AB#6892, clause W-14. The hard case is a finding with NO evidence, which Phase 0
        found on 42 of 57 failing controls. Those are not renderer failures: an `exists` rule
        fails precisely BECAUSE its query matched nothing, so there is no resource to name and
        there never will be.

        What such a row still owes the reader is the SCOPE -- what was looked for. "None found"
        beats an empty cell, because an empty cell is indistinguishable from a rule that never
        ran. Where the engine supplied a denominator (AB#6892), the row states "N of M", which is
        the reference deliverable's defining property.
    #>
    [OutputType([string])]
    param($Gap)

    $count = Get-ScoutDocxProp -Obj $Gap -Name 'EvidenceCount'
    $denom = Get-ScoutDocxProp -Obj $Gap -Name 'Denominator'

    if ($null -eq $count) { return '' }

    $n = 0
    try { $n = [int]$count } catch { return '' }

    # "17 of 198" -- only when the engine actually resolved a denominator. $null means the rule
    # has no denominator concept; 0 would be a claim that no candidates exist, which is different.
    if ($null -ne $denom) {
        $m = 0
        try { $m = [int]$denom } catch { $m = 0 }
        if ($m -gt 0) { return "$n of $m" }
    }

    if ($n -eq 0) { return 'None found' }
    if ($n -eq 1) { return '1 resource' }
    return "$n resources"
}

function New-ScoutDocxGapsSection {
    param($Body, $Gaps)

    Add-ScoutDocxHeading -Body $Body -Text 'Prioritized Gaps' -Level 1

    # @() wraps the whole pipeline for the same reason New-ScoutDocxAreaFindingsSection
    # wraps its Sort-Object above -- zero-input Sort-Object collapses to $null otherwise.
    $sorted = @(@($Gaps) | Sort-Object @{ Expression = { Get-ScoutDocxSeverityRank (Get-ScoutDocxProp -Obj $_ -Name 'Severity') } }, Area)
    $top = @($sorted | Select-Object -First $Script:ScoutDocxMaxGaps)

    if ($top.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body -Text 'No prioritized gaps — all assessed rules are passing.' -Hex $Script:ScoutDocxGreen
        return
    }

    # AB#6862/AB#6892, clause W-14. The table was Severity | Area | Gap and nothing else, so a
    # reader got a verdict with no supporting number and no resource to act on. Phase 0 measured
    # the consequence: 0 ARM ids in the whole document across three real tenants, and three
    # unrelated estates producing documents within 258 bytes of each other.
    #
    # The fourth column is the reference deliverable's defining property -- "60 of 198 storage
    # accounts", never "storage accounts are misconfigured".
    $rows = New-ScoutDocxList
    $header = New-ScoutDocxList
    foreach ($h in 'Severity', 'Area', 'Gap', 'Evidence') {
        $w = switch ($h) { 'Severity' { 1.0 } 'Area' { 1.4 } 'Gap' { 2.6 } default { 1.5 } }
        $header.Add((New-ScoutDocxCell -Text $h -WidthIn $w -Hex $Script:ScoutDocxPaper -Bold $true -FillHex $Script:ScoutDocxNavy))
    }
    $rows.Add((New-ScoutDocxRow -Cells $header -Header $true))

    $r = 0
    foreach ($gap in $top) {
        $r++
        $bg = if ($r % 2 -eq 0) { $Script:ScoutDocxMist } else { $Script:ScoutDocxPaper }
        $sevLabel = Get-ScoutDocxSeverityLabel (Get-ScoutDocxProp -Obj $gap -Name 'Severity')
        $sevColor = Get-ScoutDocxSeverityColor (Get-ScoutDocxProp -Obj $gap -Name 'Severity')
        $cells = New-ScoutDocxList
        $cells.Add((New-ScoutDocxCell -Text $sevLabel -WidthIn 1.0 -Bold $true -Hex $Script:ScoutDocxPaper -FillHex $sevColor -Align 'center'))
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $gap -Name 'Area')" -WidthIn 1.4 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $gap -Name 'Title')" -WidthIn 2.6 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text (Get-ScoutDocxEvidenceSummary $gap) -WidthIn 1.5 -FillHex $bg -SizePt 9))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @(1.0, 1.4, 2.6, 1.5) -Rows $rows))

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
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $m -Name 'Area')" -WidthIn 2.0 -FillHex $bg))
        $cells.Add((New-ScoutDocxCell -Text "$(Get-ScoutDocxProp -Obj $m -Name 'Title')" -WidthIn 4.5 -FillHex $bg))
        $rows.Add((New-ScoutDocxRow -Cells $cells))
    }
    $Body.Append((New-ScoutDocxTable -ColWidthsIn @(2.0, 4.5) -Rows $rows))

    $truncated = $items.Count - $shown.Count
    if ($truncated -gt 0) {
        Add-ScoutDocxParagraph -Body $Body -Text "+$truncated more not shown — see the evidence pack (Excel tier) for the full list." -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true
    }
}

function Add-ScoutDocxFigure {
    <#
    .SYNOPSIS
        Embed one rasterised figure as an image part, with a styled caption beneath it.

    .DESCRIPTION
        AB#6885, clauses W-12 and D-03. The figure is EMBEDDED as a package part, not linked: a
        deliverable emailed to a client has to carry its own pictures, and a linked image is a
        broken image the moment the document leaves the machine that made it.

        EMU ("English Metric Units") are the DrawingML unit -- 914,400 per inch, and 9,525 per
        pixel at 96 DPI. The image is scaled down to the text width when it would otherwise
        overflow the margins, preserving aspect, because a figure wider than the page prints
        cropped rather than small.
    #>
    param(
        $Body,
        [Parameter(Mandatory)]$MainPart,
        [Parameter(Mandatory)]$Figure,
        [Parameter(Mandatory)][int]$Index,
        [double]$MaxWidthIn = 7.0
    )

    # AddNewPart<ImagePart>(contentType), not AddImagePart: the convenience overload was removed
    # in DocumentFormat.OpenXml 3.x, which is the version this renderer pins.
    $imagePart = $MainPart.AddNewPart[DocumentFormat.OpenXml.Packaging.ImagePart]('image/png')
    $ms = [System.IO.MemoryStream]::new([byte[]]$Figure.Bytes)
    try { $imagePart.FeedData($ms) } finally { $ms.Dispose() }
    $relId = $MainPart.GetIdOfPart($imagePart)

    $emuPerPx = 9525
    $cx = [int64]$Figure.Width * $emuPerPx
    $cy = [int64]$Figure.Height * $emuPerPx
    $maxCx = [int64]($MaxWidthIn * 914400)
    if ($cx -gt $maxCx) {
        $cy = [int64][math]::Round($cy * ($maxCx / $cx))
        $cx = $maxCx
    }

    $p = New-ScoutDocxEl "$Script:ScoutDocxWNs.Paragraph"
    $p.InnerXml = @"
<w:pPr><w:jc w:val="center"/></w:pPr>
<w:r>
  <w:drawing>
    <wp:inline distT="0" distB="0" distL="0" distR="0" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
      <wp:extent cx="$cx" cy="$cy"/>
      <wp:effectExtent l="0" t="0" r="0" b="0"/>
      <wp:docPr id="$Index" name="Figure $Index"/>
      <wp:cNvGraphicFramePr>
        <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>
      </wp:cNvGraphicFramePr>
      <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
            <pic:nvPicPr>
              <pic:cNvPr id="$Index" name="$(ConvertTo-ScoutDocxXmlText $Figure.Name).png"/>
              <pic:cNvPicPr/>
            </pic:nvPicPr>
            <pic:blipFill>
              <a:blip r:embed="$relId" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
              <a:stretch><a:fillRect/></a:stretch>
            </pic:blipFill>
            <pic:spPr>
              <a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>
              <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
            </pic:spPr>
          </pic:pic>
        </a:graphicData>
      </a:graphic>
    </wp:inline>
  </w:drawing>
</w:r>
"@
    $Body.Append($p)

    $capRuns = New-ScoutDocxList
    $capRuns.Add((New-ScoutDocxRun -Text $Figure.Caption -SizePt 9 -Hex $Script:ScoutDocxGray -Italic $true))
    $capPara = New-ScoutDocxPara -Runs $capRuns -Align 'center' -SpaceAfterPt 12
    Set-ScoutDocxParaStyle -Paragraph $capPara -StyleId 'Caption'
    $Body.Append($capPara)
}

function Add-ScoutDocxFigureSection {
    <#
    .SYNOPSIS
        Render and embed the report's figures, or say plainly that there are none.

    .DESCRIPTION
        AB#6885, clause W-12: "a figure that failed to render is omitted with a caption saying
        so -- never a broken reference." That is why the whole section is inside one try/catch
        and why the empty case writes a sentence rather than nothing: a reader who expected a
        chart and finds blank space cannot tell a rendering failure from a design decision.
    #>
    param($Body, [Parameter(Mandatory)]$MainPart, $Findings, [string]$OutputPath)

    Add-ScoutDocxHeading -Body $Body -Text 'Figures' -Level 1

    $figures = @()
    try {
        if (-not (Get-Command -Name Export-ScoutFigureSet -ErrorAction SilentlyContinue)) {
            . "$PSScriptRoot/../Build-ScoutFigure.ps1"
        }
        $figures = @(Export-ScoutFigureSet -Findings $Findings -OutputPath $OutputPath)
    }
    catch {
        Write-Warning "Export-Word: the figure set did not render ($($_.Exception.Message)) -- the document says so rather than leaving a gap."
        $figures = @()
    }

    if ($figures.Count -eq 0) {
        Add-ScoutDocxParagraph -Body $Body `
            -Text 'No figures were produced for this run. This is stated rather than left blank so it is clear the charts were not silently dropped.' `
            -Hex $Script:ScoutDocxGray -Italic $true
        return
    }

    $i = 0
    foreach ($fig in $figures) {
        $i++
        try {
            Add-ScoutDocxFigure -Body $Body -MainPart $MainPart -Figure $fig -Index $i
        }
        catch {
            Write-Warning "Export-Word: figure '$($fig.Name)' could not be embedded ($($_.Exception.Message)) -- omitted."
            Add-ScoutDocxParagraph -Body $Body -Text "Figure $i ($($fig.Name)) could not be embedded in this document. The rendered PNG is in the run's figures/ folder." `
                -Hex $Script:ScoutDocxGray -Italic $true
        }
    }
}

function New-ScoutDocxSectionProperty {
    # US Letter, portrait, 1" top/bottom, 0.75" left/right — twips (dxa) throughout.
    #
    # AB#6875, clauses W-03/W-04: the header and footer parts exist only if the SECTION
    # references them, which is the half of this that Phase 0's package was missing. CT_SectPr
    # fixes headerReference/footerReference as the FIRST children -- before pgSz -- and titlePg
    # after the column definition, so the cover can carry its own (blank) furniture.
    param($HeaderRelId, $FooterRelId, $FirstHeaderRelId, $FirstFooterRelId)

    $sectPr = New-ScoutDocxEl "$Script:ScoutDocxWNs.SectionProperties"

    foreach ($ref in @(
            @{ Rel = $FirstHeaderRelId; Kind = 'header'; Type = 'First' }
            @{ Rel = $HeaderRelId; Kind = 'header'; Type = 'Default' }
            @{ Rel = $FirstFooterRelId; Kind = 'footer'; Type = 'First' }
            @{ Rel = $FooterRelId; Kind = 'footer'; Type = 'Default' }
        )) {
        if (-not $ref.Rel) { continue }
        $el = if ($ref.Kind -eq 'header') {
            New-ScoutDocxEl "$Script:ScoutDocxWNs.HeaderReference"
        }
        else {
            New-ScoutDocxEl "$Script:ScoutDocxWNs.FooterReference"
        }
        $el.Id = $ref.Rel
        $el.Type = [DocumentFormat.OpenXml.Wordprocessing.HeaderFooterValues]::"$($ref.Type)"
        $sectPr.Append($el)
    }

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
    if ($FirstHeaderRelId -or $FirstFooterRelId) {
        $sectPr.Append((New-ScoutDocxEl "$Script:ScoutDocxWNs.TitlePage"))
    }
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

    .PARAMETER OutputPath
        Directory the rendered assessment_report.docx is written into.
    #>
    param($Findings, $Collect, [string] $OutputPath)

    try {
        Import-ScoutDocxOpenXmlAssembly

        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        $outFile = Join-Path $OutputPath 'assessment_report.docx'
        if (Test-Path $outFile) { Remove-Item $outFile -Force }

        $frameworks = @(Get-ScoutDocxProp -Obj $Findings -Name 'Frameworks')
        $areas = @(Get-ScoutDocxProp -Obj $Findings -Name 'Areas')
        $gaps = @(Get-ScoutDocxProp -Obj $Findings -Name 'Gaps')
        $manual = @(Get-ScoutDocxProp -Obj $Findings -Name 'Manual')
        $errors = @(Get-ScoutDocxProp -Obj $Findings -Name 'Errors')
        $allFindings = @(Get-ScoutDocxProp -Obj $Findings -Name 'Findings')
        $generatedOn = Get-ScoutDocxProp -Obj $Findings -Name 'GeneratedOn'
        $generatedText = if ($generatedOn) {
            try { ([datetime]$generatedOn).ToString('yyyy-MM-dd') } catch { "$generatedOn" }
        } else { (Get-Date).ToString('yyyy-MM-dd') }

        $meta = Get-ScoutDocxProp -Obj $Collect -Name '_meta'
        $scope = Get-ScoutDocxProp -Obj $meta -Name 'scope'
        $mgId = Get-ScoutDocxProp -Obj $meta -Name 'managementGroupId'
        $metaParts = [System.Collections.Generic.List[string]]::new()
        $metaParts.Add("Generated $generatedText")
        if ($scope) { $metaParts.Add("Scope: $scope") }
        if ($mgId) { $metaParts.Add("Management Group: $mgId") }
        $metaLine = [string]::Join('  ·  ', $metaParts)

        # AB#6875, clause W-08. The cover has to name the CLIENT, and the run only knows the
        # tenant, so the tenant is the client name. Trying several keys rather than one is
        # deliberate: _meta's shape has changed across collector generations and a cover that
        # silently says "Azure tenant" because a key was renamed is the exact failure this
        # clause exists to catch.
        $clientName = $null
        foreach ($key in 'tenantDisplayName', 'tenantName', 'tenantDomain', 'tenant', 'tenantId') {
            $v = Get-ScoutDocxProp -Obj $meta -Name $key
            if ($v) { $clientName = "$v"; break }
        }
        if (-not $clientName) { $clientName = 'Azure tenant (not identified in this run)' }

        $assessmentName = 'Azure Landing Zone Assessment'
        $reportVersion = Get-ScoutDocxReportVersion

        $doc = [DocumentFormat.OpenXml.Packaging.WordprocessingDocument]::Create($outFile, [DocumentFormat.OpenXml.WordprocessingDocumentType]::Document)
        $mainPart = $doc.AddMainDocumentPart()
        # AB#6874 (W-01). Added BEFORE the body is populated so every heading emitted below has a
        # style to reference. Phase 0 measured the absence of this part as the root formatting
        # defect -- no styles means no navigation pane, no TOC field, and no rebranding.
        $null = Add-ScoutDocxStyleDefinition -MainPart $mainPart
        # AB#6875 (W-06/W-07 and the TOC's supporting settings). Same ordering rule: every part a
        # body element references has to exist before the body is written.
        $null = Add-ScoutDocxNumberingPart -MainPart $mainPart
        $null = Add-ScoutDocxThemePart -MainPart $mainPart
        $null = Add-ScoutDocxSettingsPart -MainPart $mainPart

        # W-03/W-04. The cover takes blank first-page furniture so the running header and page
        # numbering start on the first content page, the way a bound deliverable does.
        $headerPart = Add-ScoutDocxHeaderPart -MainPart $mainPart -Title $assessmentName -Classification $Script:ScoutDocxClassification
        $footerPart = Add-ScoutDocxFooterPart -MainPart $mainPart -Provenance "$clientName  ·  Scanned $generatedText"
        $blank = Add-ScoutDocxBlankHeaderFooterPart -MainPart $mainPart

        $mainPart.Document = New-ScoutDocxEl "$Script:ScoutDocxWNs.Document"
        $body = New-ScoutDocxEl "$Script:ScoutDocxWNs.Body"
        $mainPart.Document.Append($body)

        # ---- Cover (W-08) ----
        New-ScoutDocxCoverParagraph -Body $body -Title $assessmentName `
            -Subtitle 'Executive Assessment — CAF & WAF Alignment' -MetaLine $metaLine `
            -ClientName $clientName -ScanDate $generatedText
        Add-ScoutDocxPageBreak -Body $body

        # ---- Document Information (W-09) ----
        New-ScoutDocxDocumentInformation -Body $body -Version $reportVersion -Author $Script:ScoutDocxAuthor `
            -Frameworks $frameworks -Provenance $Script:ScoutDocxProvenance -ScanDate $generatedText -Scope $scope

        # ---- Contents (W-05) ----
        New-ScoutDocxTableOfContents -Body $body
        Add-ScoutDocxPageBreak -Body $body

        # ---- Executive Summary (W-10 — conclusion before detail) ----
        New-ScoutDocxExecSummary -Body $body -Frameworks $frameworks -Areas $areas -Gaps $gaps -Manual $manual -Errors $errors
        Add-ScoutDocxPageBreak -Body $body

        # ---- Figures (W-12, D-01/D-03) ----
        # Placed after the summary and before the detail: a figure is an argument about the whole
        # run, so it belongs where the run is being characterised, not buried among the tables.
        Add-ScoutDocxFigureSection -Body $body -MainPart $mainPart -Findings $Findings -OutputPath $OutputPath
        Add-ScoutDocxPageBreak -Body $body

        # ---- Findings by Area (W-11), deferring long tables to the appendix (W-13) ----
        $appendix = New-ScoutDocxAreaFindingsSection -Body $body -Areas $areas -AllFindings $allFindings
        Add-ScoutDocxPageBreak -Body $body

        # ---- Prioritized Gaps ----
        New-ScoutDocxGapsSection -Body $body -Gaps $gaps
        Add-ScoutDocxPageBreak -Body $body

        # ---- Manual Review Worklist ----
        New-ScoutDocxManualSection -Body $body -Manual $manual

        # ---- Appendices (W-13) ----
        New-ScoutDocxAppendix -Body $body -Appendix $appendix

        # ---- Section properties (must be the last child of w:body) ----
        $body.Append((New-ScoutDocxSectionProperty `
                    -HeaderRelId $mainPart.GetIdOfPart($headerPart) `
                    -FooterRelId $mainPart.GetIdOfPart($footerPart) `
                    -FirstHeaderRelId $mainPart.GetIdOfPart($blank.Header) `
                    -FirstFooterRelId $mainPart.GetIdOfPart($blank.Footer)))

        $mainPart.Document.Save()
        $doc.Dispose()

        return $outFile
    }
    catch {
        Write-Warning "Export-Word: .docx generation failed ($_) -- writing an HTML fallback instead."
        return (Export-ScoutDocxHtmlFallback -Findings $Findings -Collect $Collect -OutputPath $OutputPath -Reason $_.Exception.Message)
    }
}
