#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/report/renderers/Export-Pptx.ps1 -- the OpenXML-SDK
    executive-deck renderer (ADO Story AB#5048, Epic AB#5044).

    Focus: the empty/near-empty-input crash class found in a StrictMode sweep
    (no prior Pester coverage existed for this renderer). New-ScoutAreaTableSlides/
    New-ScoutGapsSlides/New-ScoutManualSlide and Export-Pptx's own slide-count
    plan each did `$x = @(...) | Sort-Object|Select-Object ...` WITHOUT an outer
    @() wrap around the whole pipeline -- a Sort-Object/Select-Object over zero
    input collapses the bare assignment to $null, and $null.Count throws
    PropertyNotFoundException under Set-StrictMode -Version Latest (this file's
    own Set-StrictMode -Version Latest applies). A scored Findings object with
    zero Areas/Gaps/Manual items -- e.g. a fresh assessment run with nothing
    collected yet, or every rule matched Pass -- hit this on every single run,
    not an obscure edge case.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/report/renderers/Export-Pptx.ps1"

    function New-PptxTestFinding {
        param($Id, $Framework, $Area, $Status, $Severity = 'medium', $Weight = 1.0)
        [pscustomobject]@{
            Id = $Id; Title = "$Id title text for the deck"; Framework = $Framework; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = 2; Evidence = @(); Remediation = "Remediate $Id."
            Manual = ($Status -eq 'Manual'); AreaWeight = $Weight
        }
    }

    $script:Findings = @(
        (New-PptxTestFinding 'CAF-NET-01' 'CAF' 'Networking' 'Pass' 'low')
        (New-PptxTestFinding 'CAF-NET-02' 'CAF' 'Networking' 'Fail' 'high')
        (New-PptxTestFinding 'WAF-SEC-01' 'WAF' 'Security' 'Fail' $null)
        (New-PptxTestFinding 'WAF-SEC-02' 'WAF' 'Security' 'Manual')
    )
    $script:Scored = Get-Score -Findings $script:Findings

    $script:Collect = [pscustomobject]@{
        _meta = [pscustomobject]@{ scope = 'ArmOnly'; managementGroupId = 'mg-test-01' }
    }

    function Get-PptxSlideEntries {
        # Returns via the unary-comma idiom (`return , @(...)`) so a zero- or
        # one-slide result reaches the caller as a real array rather than
        # collapsing to $null/a bare scalar -- callers must NOT re-wrap the call
        # itself in an outer @(...): @(a-function-that-returns-,@(...)) counts
        # the SINGLE returned array object as one pipeline item, double-wrapping
        # it into a one-element array-of-an-array. Capture directly instead
        # (`$slides = Get-PptxSlideEntries ...`), then @() that variable if
        # still-defensive re-wrapping is wanted.
        param([string]$Path)
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $ms = [System.IO.MemoryStream]::new($bytes)
        $zip = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Read)
        try {
            return , @($zip.Entries | Select-Object -ExpandProperty FullName | Where-Object { $_ -match '^ppt/slides/slide\d+\.xml$' })
        }
        finally {
            $zip.Dispose()
            $ms.Dispose()
        }
    }
}

Describe 'Export-Pptx -- basic deck generation AB#5048' {
    BeforeAll {
        $script:OutDir = Join-Path $script:Root 'tests' 'test-output' 'pptx'
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
        $script:DeckPath = Export-Pptx -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
    }
    AfterAll {
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes assessment_deck.pptx into -OutputPath and returns its path' {
        $script:DeckPath | Should -Exist
        (Split-Path $script:DeckPath -Leaf) | Should -Be 'assessment_deck.pptx'
    }

    It 'produces at least the minimum expected slide count (title/summary/area/gaps/manual/next-steps)' {
        $slides = Get-PptxSlideEntries -Path $script:DeckPath
        $slides.Count | Should -BeGreaterOrEqual 6
    }
}

Describe 'Export-Pptx -- empty-input crash class (StrictMode sweep)' {
    It 'does not throw when Areas/Gaps/Manual are all empty (fresh/all-Pass assessment)' {
        $dir = Join-Path $script:Root 'tests' 'test-output' 'pptx-empty'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        try {
            $emptyScored = Get-Score -Findings @()
            $emptyScored.Areas   | Should -BeNullOrEmpty
            $emptyScored.Gaps    | Should -BeNullOrEmpty
            $emptyScored.Manual  | Should -BeNullOrEmpty

            # Called directly (not wrapped in `{ } | Should -Not -Throw`) -- that
            # wrapper invokes the scriptblock in a child scope, so a `$path =`
            # assignment inside it never leaks back out to this variable; a throw
            # here still fails the It block on its own, so coverage is unchanged.
            $path = Export-Pptx -Findings $emptyScored -Collect $null -OutputPath $dir
            $path | Should -Exist
            (Split-Path $path -Leaf) | Should -Be 'assessment_deck.pptx'
        }
        finally {
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'does not throw when Areas/Gaps/Manual each carry exactly one item (single-item pipeline collapse)' {
        $dir = Join-Path $script:Root 'tests' 'test-output' 'pptx-single'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        try {
            $oneFinding = @(New-PptxTestFinding 'CAF-SOLO-01' 'CAF' 'Solo' 'Fail' 'high')
            $singleScored = Get-Score -Findings $oneFinding

            $path = Export-Pptx -Findings $singleScored -Collect $null -OutputPath $dir
            $path | Should -Exist
        }
        finally {
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'New-ScoutAreaTableSlides does not throw and no-ops on an empty -Areas array directly' {
        $pageRef = [ref] 2
        { New-ScoutAreaTableSlides -Shell ([pscustomobject]@{}) -Areas @() -PageCounter $pageRef -TotalPages 6 } | Should -Not -Throw
    }

    It 'New-ScoutGapsSlides does not throw on an empty -Gaps array directly' {
        $dir = Join-Path $script:Root 'tests' 'test-output' 'pptx-gaps-unit'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $shell = New-ScoutDeckShell -OutFile (Join-Path $dir 'unit.pptx')
            $pageRef = [ref] 3
            New-ScoutGapsSlides -Shell $shell -Gaps @() -PageCounter $pageRef -TotalPages 6
            $shell.Doc.Dispose()
        }
        finally {
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'New-ScoutManualSlide does not throw on an empty -Manual array directly' {
        $dir = Join-Path $script:Root 'tests' 'test-output' 'pptx-manual-unit'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $shell = New-ScoutDeckShell -OutFile (Join-Path $dir 'unit.pptx')
            $pageRef = [ref] 4
            New-ScoutManualSlide -Shell $shell -Manual @() -PageCounter $pageRef -TotalPages 6
            $shell.Doc.Dispose()
        }
        finally {
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
