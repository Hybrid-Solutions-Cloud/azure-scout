#Requires -Version 7.0
#Requires -Modules Pester

<#
    PowerPoint executive readout v2 (Task AB#6858, User Story AB#6443, Feature AB#6449,
    Epic AB#6450).

    The v1 deck was the Word document with fewer rows. These tests assert the readout shape
    the reference deck uses, and the one thing a scorecard must never do: show a domain that
    was not assessed as a number. On a slide of big coloured tiles, a 0 is read as a grade.

    Renders a real .pptx and reads the slide XML back, so a slide that silently fails to
    append is caught rather than assumed.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Get-GovernanceDomainScore.ps1"
    . "$root/src/report/Build-ScoutReportModel.ps1"
    . "$root/src/report/renderers/Export-Pptx.ps1"

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Get-PptxText {
        param([string] $Path)
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $sb = [Text.StringBuilder]::new()
            $slides = @($zip.Entries | Where-Object { $_.FullName -match '^ppt/slides/slide\d+\.xml$' })
            foreach ($e in $slides) {
                $sr = [IO.StreamReader]::new($e.Open())
                [void]$sb.AppendLine(($sr.ReadToEnd() -replace '<[^>]+>', ' ' -replace '&amp;', '&'))
                $sr.Dispose()
            }
            return [pscustomobject]@{ Text = $sb.ToString(); SlideCount = $slides.Count }
        }
        finally { $zip.Dispose() }
    }

    function New-Finding {
        param(
            [string] $Id, [string] $Area, [string] $Status, [string] $Severity = 'high',
            [int] $EvidenceCount = 0, $Evidence = @(), [string] $Title = 'A control',
            $TargetState = $null, $Owner = $null, $Phase = $null
        )
        [pscustomobject]@{
            Id = $Id; Title = $Title; Framework = 'Cloud Governance'; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = $EvidenceCount; Evidence = $Evidence
            EvidenceTruncated = $false; EvidenceCap = 25
            Remediation = "Remediate $Id."; Manual = $false
            TargetState = $TargetState; Owner = $Owner; Effort = 'M'; Phase = $Phase
        }
    }

    function New-Area {
        param([string] $Area, $Score, [int] $Pass = 2, [int] $Fail = 1)
        [pscustomobject]@{
            Framework = 'Cloud Governance'; Area = $Area; Score = $Score; Weight = 1.0
            Pass = $Pass; Partial = 0; Fail = $Fail; Manual = 0; Unknown = 0; Error = 0
        }
    }

    $Script:Collect = [pscustomobject]@{
        subscriptions = @(
            [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled' }
        )
        networking = [pscustomobject]@{ virtualNetworks = @(1..14); subnets = @(1..52) }
        domains = [pscustomobject]@{ storage = [pscustomobject]@{ storageAccounts = @(1..198) } }
        _meta = [pscustomobject]@{ scope = 'All'; managementGroupId = 'mg-root'; tenantId = 'tenant-abc' }
    }

    $Script:Findings = @(
        New-Finding -Id 'SEC-01' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 60 `
            -Evidence @([pscustomobject]@{ name = 'stpayments01' }) `
            -Title 'Storage accounts should disable public network access' `
            -TargetState 'PublicNetworkAccess=Disabled' -Owner 'Network Engineering' -Phase 1
        New-Finding -Id 'SEC-02' -Area 'Security' -Status 'Pass' -EvidenceCount 41 -Title 'Key vaults have purge protection'
        New-Finding -Id 'OPS-01' -Area 'Operations' -Status 'Fail' -Severity 'medium' -EvidenceCount 1 `
            -Title 'Every subscription has a diagnostic setting' -Owner 'CCoE Platform' -Phase 2
        New-Finding -Id 'AI-01' -Area 'Artificial Intelligence' -Status 'NotAssessed' -Severity 'high' -Title 'AI workloads covered'
    )

    $Script:Scored = [pscustomobject]@{
        GeneratedOn = '2026-08-01T10:00:00.0000000Z'
        Frameworks = @([pscustomobject]@{ Framework = 'Cloud Governance'; Score = 55; Version = 'CAF Govern' })
        Areas = @(
            (New-Area -Area 'Security' -Score 45)
            (New-Area -Area 'Operations' -Score 72)
            (New-Area -Area 'Artificial Intelligence' -Score $null)
        )
        Gaps = @(); Manual = @(); Errors = @(); Findings = $Script:Findings
    }

    $Script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-pptxv2-$([guid]::NewGuid().ToString('N'))"
    $Script:Model = Build-ScoutReportModel -Findings $Script:Scored -Collect $Script:Collect -RunId 'run-v2'
    $Script:DeckPath = Export-Pptx -Findings $Script:Scored -Collect $Script:Collect -OutputPath $Script:OutDir -Model $Script:Model
    $Script:Deck = Get-PptxText -Path $Script:DeckPath
}

AfterAll {
    if ($Script:OutDir -and (Test-Path $Script:OutDir)) {
        Remove-Item $Script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'PPTX v2 renders a real deck' {
    It 'writes assessment_deck.pptx' {
        $Script:DeckPath | Should -BeLike '*assessment_deck.pptx'
        Test-Path $Script:DeckPath | Should -BeTrue
    }

    It 'renders the full readout, not the four-slide summary' {
        $Script:Deck.SlideCount | Should -BeGreaterOrEqual 9
    }
}

Describe 'PPTX v2 slide inventory' {
    It 'renders the readout slides the design calls for' -ForEach @(
        @{ Slide = 'Scope and Approach' }
        @{ Slide = 'Executive Summary' }
        @{ Slide = 'Domain Maturity Scorecard' }
        @{ Slide = 'Key Risk Indicators' }
        @{ Slide = 'Highest-Severity Finding' }
        @{ Slide = 'Gaps by Accountable Owner' }
        @{ Slide = '90-Day Remediation Roadmap' }
    ) {
        $Script:Deck.Text | Should -BeLike "*$Slide*"
    }

    It 'publishes the maturity rubric so a tile colour can be interpreted' {
        $Script:Deck.Text | Should -BeLike '*Defined*'
        $Script:Deck.Text | Should -BeLike '*Managed*'
    }

    It 'shows the three roadmap phases with their day ranges' {
        $Script:Deck.Text | Should -BeLike '*Days 0-30*'
        $Script:Deck.Text | Should -BeLike '*Days 30-60*'
        $Script:Deck.Text | Should -BeLike '*Days 60-90*'
    }

    It 'publishes the effort key rather than leaving S/M/L/XL unexplained' {
        $Script:Deck.Text | Should -BeLike '*4-8 weeks*'
    }
}

Describe 'PPTX v2 carries the data v1 discarded' {
    It 'states risks with their supporting counts' {
        $Script:Deck.Text | Should -BeLike '*60*'
    }

    It 'names the accountable owner' {
        $Script:Deck.Text | Should -BeLike '*Network Engineering*'
    }

    It 'names an affected resource on the deep-dive slide' {
        $Script:Deck.Text | Should -BeLike '*stpayments01*'
    }

    It 'carries the target state on the deep-dive slide' {
        $Script:Deck.Text | Should -BeLike '*PublicNetworkAccess=Disabled*'
    }
}

Describe 'PPTX v2 honesty guarantees' {
    It 'shows a not-assessed domain as an em-dash tile, never a zero' {
        $Script:Deck.Text | Should -BeLike '*Not assessed*'
        $Script:Deck.Text | Should -BeLike '*was not assessed, and is not a zero*'
    }

    It 'states the composite exclusion on the takeaways slide' {
        $Script:Deck.Text | Should -BeLike '*excluded from the composite*'
    }

    It 'names what was not collected on the scope slide rather than burying it' {
        $Script:Deck.Text | Should -BeLike '*Not collected in this run*'
    }

    It 'includes GOOD-graded strengths, not only failures' {
        $Script:Deck.Text | Should -BeLike '*GOOD*'
    }
}

Describe 'PPTX v2 degrades rather than failing' {
    It 'renders a deck when there are no findings at all' {
        $scored = [pscustomobject]@{
            GeneratedOn = '2026-08-01T10:00:00.0000000Z'
            Frameworks = @(); Areas = @(); Gaps = @(); Manual = @(); Errors = @(); Findings = @()
        }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-pptxv2e-$([guid]::NewGuid().ToString('N'))"
        try {
            $path = Export-Pptx -Findings $scored -Collect ([pscustomobject]@{}) -OutputPath $dir
            $deck = Get-PptxText -Path $path
            $deck.SlideCount | Should -BeGreaterThan 0
            $deck.Text | Should -BeLike '*No open gaps*'
        }
        finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
