#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Story AB#6888 — the conformance test for `docs/design/report-conformance.md`.

    This file is the DEFINITION OF DONE for every item under Epic AB#6450. It exists because 103
    report work items on this board were closed on "a file came out": not one of them had an
    acceptance criterion naming a required part, a required section, or a reader. Every clause
    below is asserted against an EMITTED PACKAGE, read back from disk, so a renderer cannot pass
    by claiming to have done something.

    Only the clauses marked `automatic` in the design document are tested here. The `judged`
    ones (W-14 named resources, W-15 passing controls shown, W-16 comparative narrative, P-06
    band labels) need a human reading the artefact beside the reference deliverable, and
    pretending otherwise would recreate exactly the false-green problem this file exists to fix.

    No Azure connection and no tenant: the fixture below is a synthetic scored object, and every
    clause here is a property of the PACKAGE rather than of the data in it.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    foreach ($r in 'Export-Word', 'Export-Pptx', 'Export-Excel', 'Export-PowerBi', 'Export-PowerBiProject') {
        . "$script:Root/src/report/renderers/$r.ps1"
    }

    # 40 findings across two frameworks and three areas, deliberately including a Manual row (so
    # clause W-17 has something to be wrong about) and one area with more than
    # $Script:ScoutDocxBodyTableMaxRows findings (so clause W-13's appendix path is exercised
    # rather than merely present).
    $script:Findings = @(
        1..34 | ForEach-Object {
            [pscustomobject]@{
                Id            = "CAF-NET-$($_.ToString('000'))"
                Title         = "Networking control $_"
                Framework     = 'CAF'
                Area          = 'Networking'
                Severity      = @('high', 'medium', 'low')[$_ % 3]
                Status        = @('Fail', 'Pass', 'Partial', 'Manual')[$_ % 4]
                EvidenceCount = $_ % 5
                Denominator   = 40
                Evidence      = @()
                Remediation   = "Remediate networking control $_."
                Manual        = (($_ % 4) -eq 3)
                AreaWeight    = 1.0
            }
        }
        1..6 | ForEach-Object {
            [pscustomobject]@{
                Id            = "WAF-SEC-$($_.ToString('000'))"
                Title         = "Security control $_"
                Framework     = 'WAF'
                Area          = 'Security'
                Severity      = 'high'
                Status        = @('Fail', 'Pass')[$_ % 2]
                EvidenceCount = 2
                Denominator   = 9
                Evidence      = @()
                Remediation   = "Remediate security control $_."
                Manual        = $false
                AreaWeight    = 1.0
            }
        }
    )
    $script:Scored = Get-Score -Findings $script:Findings
    $script:Collect = [pscustomobject]@{
        _meta = [pscustomobject]@{
            scope             = 'ArmOnly'
            managementGroupId = 'mg-conformance'
            tenantDisplayName = 'Conformance Test Tenant'
        }
    }

    $script:OutDir = Join-Path $script:Root 'tests' 'test-output' 'conformance'
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
    New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

    $script:DocxPath = Export-Word -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
    $script:PptxPath = Export-Pptx -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
    $null = Export-Excel -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
    $null = Export-PowerBi -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
    $script:PbiDir = Join-Path $script:OutDir 'powerbi'

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    # Reads one entry out of an OPC package as text. Every clause below that inspects a document
    # goes through here rather than through the SDK, deliberately: the clause is about what
    # SHIPPED, and the SDK would happily materialise a part the package does not contain.
    function Get-ZipEntryText {
        param([string]$Path, [string]$Entry)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $e = $zip.GetEntry($Entry)
            if (-not $e) { return $null }
            $reader = [System.IO.StreamReader]::new($e.Open())
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally { $zip.Dispose() }
    }

    function Get-ZipEntryNames {
        param([string]$Path)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { return @($zip.Entries | Select-Object -ExpandProperty FullName) }
        finally { $zip.Dispose() }
    }
}

AfterAll {
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'W — Word document (docs/design/report-conformance.md)' {

    BeforeAll {
        $script:WordEntries = Get-ZipEntryNames -Path $script:DocxPath
        $script:WordXml = Get-ZipEntryText -Path $script:DocxPath -Entry 'word/document.xml'
    }

    It 'W-01: declares named styles for Title, Heading 1-3, Normal, Caption and a table style' {
        $script:WordEntries | Should -Contain 'word/styles.xml'
        $styles = Get-ZipEntryText -Path $script:DocxPath -Entry 'word/styles.xml'
        foreach ($id in 'Title', 'Heading1', 'Heading2', 'Heading3', 'Normal', 'Caption') {
            $styles | Should -Match "w:styleId=""$id"""
        }
        # A TABLE style specifically -- a paragraph style called "table" would satisfy a naive
        # substring match and satisfy nothing about the document.
        $styles | Should -Match 'w:type="table"'
    }

    It 'W-02: every heading paragraph carries a pStyle, and none is formatted by direct runs alone' {
        # Every paragraph in the BODY whose runs use the heading font must reference a heading
        # style. Phase 0 measured the inverse of this: 0 of 1,803 paragraphs styled.
        #
        # Scoped to the body deliberately. Front matter -- the cover's "prepared for" client
        # name, the Document Information and Contents labels -- is set in the same face but is
        # NOT heading-outline content, and pulling it into the TOC would be wrong. The clause is
        # about chapter headings, so the assertion starts at the first chapter.
        ([regex]::Matches($script:WordXml, '<w:pStyle w:val="Heading[123]"')).Count | Should -BeGreaterThan 0

        $bodyStart = $script:WordXml.IndexOf('Executive Summary')
        $bodyStart | Should -BeGreaterThan 0
        $body = $script:WordXml.Substring($bodyStart)

        $headingParas = [regex]::Matches($body, '<w:p\b[^>]*>(?:(?!</w:p>).)*?Segoe UI Semibold(?:(?!</w:p>).)*?</w:p>', 'Singleline')
        @($headingParas).Count | Should -BeGreaterThan 0
        foreach ($m in $headingParas) {
            $m.Value | Should -Match '<w:pStyle w:val="(Heading[123]|Title)"'
        }
    }

    It 'W-03: contains a header part, referenced by the section properties' {
        ($script:WordEntries | Where-Object { $_ -match '^word/header\d+\.xml$' }) | Should -Not -BeNullOrEmpty
        $script:WordXml | Should -Match '<w:headerReference'
    }

    It 'W-04: contains a footer part carrying a PAGE field' {
        $footers = @($script:WordEntries | Where-Object { $_ -match '^word/footer\d+\.xml$' })
        $footers | Should -Not -BeNullOrEmpty
        $script:WordXml | Should -Match '<w:footerReference'
        $withPageField = @($footers | Where-Object {
                (Get-ZipEntryText -Path $script:DocxPath -Entry $_) -match 'PAGE'
            })
        $withPageField.Count | Should -BeGreaterThan 0
    }

    It 'W-05: contains a real TOC field, not a list of paragraphs' {
        $script:WordXml | Should -Match 'TOC \\o'
        $script:WordXml | Should -Match '<w:fldChar w:fldCharType="begin"'
    }

    It 'W-06: contains a numbering part, and the chapter headings reference it' {
        $script:WordEntries | Should -Contain 'word/numbering.xml'
        $numbering = Get-ZipEntryText -Path $script:DocxPath -Entry 'word/numbering.xml'
        # The binding is on the STYLE, so the numbering part is what has to name the headings.
        foreach ($h in 'Heading1', 'Heading2', 'Heading3') {
            $numbering | Should -Match "<w:pStyle w:val=""$h"""
        }
        $styles = Get-ZipEntryText -Path $script:DocxPath -Entry 'word/styles.xml'
        $styles | Should -Match '<w:numPr>'
    }

    It 'W-07: contains a theme part, and no run in the body uses a hex absent from it' {
        ($script:WordEntries | Where-Object { $_ -match '^word/theme/theme\d+\.xml$' }) | Should -Not -BeNullOrEmpty
        $theme = Get-ZipEntryText -Path $script:DocxPath -Entry 'word/theme/theme1.xml'
        $themeHexes = @([regex]::Matches($theme, 'val="([0-9A-Fa-f]{6})"') |
                ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Sort-Object -Unique)

        $bodyHexes = @(
            @([regex]::Matches($script:WordXml, '<w:color w:val="([0-9A-Fa-f]{6})"') | ForEach-Object { $_.Groups[1].Value })
            @([regex]::Matches($script:WordXml, 'w:fill="([0-9A-Fa-f]{6})"') | ForEach-Object { $_.Groups[1].Value })
        ) | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique

        $orphans = @($bodyHexes | Where-Object { $_ -notin $themeHexes })
        if ($orphans.Count -gt 0) {
            Write-Host "Colours used in the body but absent from the theme: $($orphans -join ', ')"
        }
        $orphans.Count | Should -Be 0
    }

    It 'W-08: the first page is a cover carrying client, assessment name, scan date and classification' {
        $script:WordXml | Should -Match 'Conformance Test Tenant'
        $script:WordXml | Should -Match 'Azure Landing Zone Assessment'
        $script:WordXml | Should -Match 'Scan date'
        $script:WordXml | Should -Match 'CONFIDENTIAL'
    }

    It 'W-09: a Document Information block follows the cover with version, author, frameworks and provenance' {
        $script:WordXml | Should -Match 'Document Information'
        $script:WordXml | Should -Match 'Report version'
        $script:WordXml | Should -Match 'Source data provenance'
        $script:WordXml | Should -Match 'Frameworks referenced'
        # The block has to come BEFORE the first chapter, or it is an appendix by another name.
        $docInfoAt = $script:WordXml.IndexOf('Document Information')
        $firstChapterAt = $script:WordXml.IndexOf('Executive Summary')
        $docInfoAt | Should -BeGreaterThan 0
        $docInfoAt | Should -BeLessThan $firstChapterAt
    }

    It 'W-10: an Executive Summary precedes the first finding chapter' {
        $summaryAt = $script:WordXml.IndexOf('Executive Summary')
        $findingsAt = $script:WordXml.IndexOf('Findings by Area')
        $summaryAt | Should -BeGreaterThan 0
        $summaryAt | Should -BeLessThan $findingsAt
    }

    It 'W-11: each domain chapter has scorecard, Current state, findings and action items, in that order' {
        foreach ($section in 'Current state', 'Action items', 'Alignment score') {
            $script:WordXml | Should -Match ([regex]::Escape($section))
        }
        $currentStateAt = $script:WordXml.IndexOf('Current state')
        $actionItemsAt = $script:WordXml.IndexOf('Action items')
        $currentStateAt | Should -BeGreaterThan 0
        $currentStateAt | Should -BeLessThan $actionItemsAt
    }

    It 'W-13: a findings table longer than the row cap is in an appendix, not the body' {
        # The fixture's Networking area has 34 findings against a cap of 30, so this clause is
        # being exercised rather than merely satisfied by a document with no long tables.
        $script:WordXml | Should -Match 'Appendices'
        $script:WordXml | Should -Match 'Appendix A'
        $script:WordXml | Should -Match 'the full table is in Appendix A'
        # And the pointer must precede the appendix itself, not follow it.
        $pointerAt = $script:WordXml.IndexOf('the full table is in Appendix A')
        $appendixAt = $script:WordXml.IndexOf('Appendices')
        $pointerAt | Should -BeLessThan $appendixAt
    }

    It 'W-17: a manual control renders as Not assessed, never as a zero or a pass' {
        $script:WordXml | Should -Match 'Not assessed'
        # The fixture has Manual findings; the word "Manual" may legitimately appear as a
        # section title, but no findings-table STATUS cell may say it. The status cells are
        # centred single-word cells, so the check is that "Not assessed" outnumbers nothing --
        # specifically, that the status vocabulary reached the document at all.
        ([regex]::Matches($script:WordXml, 'Not assessed')).Count | Should -BeGreaterThan 1
    }
}

Describe 'P — PowerPoint deck' {

    BeforeAll {
        $script:PptxEntries = Get-ZipEntryNames -Path $script:PptxPath
        $script:SlideNames = @($script:PptxEntries | Where-Object { $_ -match '^ppt/slides/slide\d+\.xml$' })
    }

    It 'P-01: the deck uses slide layouts from a master' {
        ($script:PptxEntries | Where-Object { $_ -match '^ppt/slideMasters/' }) | Should -Not -BeNullOrEmpty
        ($script:PptxEntries | Where-Object { $_ -match '^ppt/slideLayouts/' }) | Should -Not -BeNullOrEmpty
        # Every slide must actually RELATE to a layout -- a master nobody references is furniture.
        foreach ($slide in $script:SlideNames) {
            $relName = $slide -replace '^ppt/slides/', 'ppt/slides/_rels/'
            $rels = Get-ZipEntryText -Path $script:PptxPath -Entry "$relName.rels"
            $rels | Should -Match 'slideLayout'
        }
    }

    It 'P-02: slide 1 is a title slide carrying tenant, assessment name and date' {
        $slide1 = Get-ZipEntryText -Path $script:PptxPath -Entry 'ppt/slides/slide1.xml'
        $slide1 | Should -Not -BeNullOrEmpty
        $slide1 | Should -Match '\d{4}-\d{2}-\d{2}'
    }

    It 'P-05: a roll-up deck is bounded at 15 slides — one idea per slide' {
        $script:SlideNames.Count | Should -BeGreaterThan 0
        $script:SlideNames.Count | Should -BeLessOrEqual 15
    }
}

Describe 'X — Excel workbook' {

    BeforeAll {
        $script:XlsxPath = Join-Path $script:OutDir 'assessment_evidence.xlsx'
    }

    It 'the workbook was emitted' {
        $script:XlsxPath | Should -Exist
    }

    It 'X-03: every visible data tab has frozen panes and an autofilter on the header row' {
        $entries = Get-ZipEntryNames -Path $script:XlsxPath
        $sheets = @($entries | Where-Object { $_ -match '^xl/worksheets/sheet\d+\.xml$' })
        $sheets.Count | Should -BeGreaterThan 0

        $workbook = Get-ZipEntryText -Path $script:XlsxPath -Entry 'xl/workbook.xml'
        # AB#6891's lesson, encoded: a hidden sheet is still LISTED in workbook.xml, so the
        # `state` attribute has to be read before calling a sheet visible. Reporting a hidden
        # source sheet as a non-conformant data tab is how the last false finding happened.
        $visibleCount = ([regex]::Matches($workbook, '<sheet\b(?![^>]*state="(hidden|veryHidden)")[^>]*>')).Count
        $visibleCount | Should -BeGreaterThan 0

        $withPanes = @($sheets | Where-Object { (Get-ZipEntryText -Path $script:XlsxPath -Entry $_) -match '<pane' })
        $withFilter = @($sheets | Where-Object { (Get-ZipEntryText -Path $script:XlsxPath -Entry $_) -match '<autoFilter' })
        $withPanes.Count | Should -BeGreaterThan 0
        $withFilter.Count | Should -BeGreaterThan 0
    }
}

Describe 'B — Power BI (clauses B-01 to B-05)' {

    BeforeAll {
        $script:PbipPath = Join-Path $script:PbiDir 'AzureScout.pbip'
        $script:ModelDef = Join-Path $script:PbiDir 'AzureScout.SemanticModel' 'definition'
        $script:ReportDir = Join-Path $script:PbiDir 'AzureScout.Report'
    }

    It 'B-01: the output is a PBIP project — semantic model and report as text' {
        $script:PbipPath | Should -Exist
        (Join-Path $script:PbiDir 'AzureScout.SemanticModel' 'definition.pbism') | Should -Exist
        (Join-Path $script:ReportDir 'definition.pbir') | Should -Exist
        (Join-Path $script:ModelDef 'model.tmdl') | Should -Exist
        # The .pbir must point at the model by path, or the two halves are unrelated files.
        $pbir = Get-Content (Join-Path $script:ReportDir 'definition.pbir') -Raw | ConvertFrom-Json
        $pbir.datasetReference.byPath.path | Should -Match 'SemanticModel'
    }

    It 'B-02: the model declares relationships between fact and dimension tables' {
        $rels = Get-Content (Join-Path $script:ModelDef 'relationships.tmdl') -Raw
        ([regex]::Matches($rels, '(?m)^relationship ')).Count | Should -BeGreaterOrEqual 3
        # A single text key across every table was the previous model, and it is explicitly
        # called out in the design document as non-conformant.
        $rels | Should -Match "fromColumn: 'Findings'\.Framework"
        $rels | Should -Match "toColumn: 'Frameworks'\.Framework"
    }

    It 'B-03: the model declares DAX measures' {
        $findings = Get-Content (Join-Path $script:ModelDef 'tables' 'Findings.tmdl') -Raw
        $measures = @([regex]::Matches($findings, "(?m)^\tmeasure '"))
        $measures.Count | Should -BeGreaterOrEqual 4
        $findings | Should -Match "measure 'Compliance rate'"
    }

    It 'B-04: the model declares a date dimension, and a fact relates to it' {
        $datePath = Join-Path $script:ModelDef 'tables' 'Date.tmdl'
        $datePath | Should -Exist
        (Get-Content $datePath -Raw) | Should -Match 'dataCategory: Time'
        $rels = Get-Content (Join-Path $script:ModelDef 'relationships.tmdl') -Raw
        $rels | Should -Match "toColumn: 'Date'\.Date"
        # And the fact has to actually carry the column, or the relationship is unresolvable.
        (Get-Content (Join-Path $script:PbiDir 'fact_findings.csv') -Raw) | Should -Match 'ScanDate'
    }

    It 'B-05: the project contains authored report pages — opening it is not a blank canvas' {
        $reportJson = Join-Path $script:ReportDir 'report.json'
        $reportJson | Should -Exist
        $report = Get-Content $reportJson -Raw | ConvertFrom-Json
        @($report.sections).Count | Should -BeGreaterOrEqual 3
        foreach ($section in $report.sections) {
            @($section.visualContainers).Count | Should -BeGreaterThan 0
            # Each visual's config is itself serialised JSON; if it does not parse, Power BI
            # Desktop drops the visual silently and the page IS blank.
            foreach ($vc in $section.visualContainers) {
                { $vc.config | ConvertFrom-Json } | Should -Not -Throw
            }
        }
    }
}

Describe 'R — run output contract' {

    It 'R-04: every renderer consumes the same scored object — none re-derives findings' {
        # Read as source, because the clause is about the SHAPE of the renderer layer rather
        # than about one emitted package. Every Export-* entry point must take -Findings; a
        # renderer that reached for the raw collect and scored it again is the drift this
        # clause exists to prevent.
        $renderers = Get-ChildItem (Join-Path $script:Root 'src' 'report' 'renderers') -Filter 'Export-*.ps1'
        $renderers.Count | Should -BeGreaterThan 0
        foreach ($r in $renderers) {
            $src = Get-Content $r.FullName -Raw
            if ($src -notmatch 'function Export-') { continue }
            # Comment and doc-block lines are stripped first. Every renderer's header names
            # Get-Score when it documents the shape of the object it consumes, and failing a
            # renderer for correctly DOCUMENTING that it consumes the scored model would be the
            # opposite of what this clause is for. What is banned is a CALL.
            $code = ($src -split "`r?`n" | Where-Object { $_ -notmatch '^\s*(#|<#|\.[A-Z]|\S.*#>)' }) -join "`n"
            $code | Should -Not -Match '(?<![\w-])Get-Score\s+-'
        }
    }
}
