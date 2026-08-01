#Requires -Version 7.0
#Requires -Modules Pester

<#
    Word renderer v2 — the consulting-grade document structure (Task AB#6856, User Story
    AB#6443, Feature AB#6449, Epic AB#6450).

    The v1 document emitted five sections whose every table was Id / Severity / Status / Title.
    These tests assert the sections that replaced it exist, and — more importantly — that the
    three places the document could tell a lie do not:

      * a domain with no evidence must read "Not assessed", never carry a score;
      * an uncollected inventory count must read as a blind spot, never as a zero;
      * a truncated resource list must say it is partial, never present itself as complete.

    Renders a real .docx and reads the text back out of the OPC package, so a section that
    silently fails to append is caught rather than assumed.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Get-GovernanceDomainScore.ps1"
    . "$root/src/report/Build-ScoutReportModel.ps1"
    . "$root/src/report/renderers/Export-Word.ps1"

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Get-DocxText {
        param([string] $Path)
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' }
            $sr = [IO.StreamReader]::new($entry.Open())
            $xml = $sr.ReadToEnd()
            $sr.Dispose()
            # Strip tags; w:t runs concatenate, which is all these assertions need.
            $text = $xml -replace '<[^>]+>', '' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>'
            return $text
        }
        finally { $zip.Dispose() }
    }

    function New-Finding {
        param(
            [string] $Id, [string] $Area, [string] $Status, [string] $Severity = 'high',
            [int] $EvidenceCount = 0, $Evidence = @(), [bool] $Truncated = $false,
            [string] $Title = 'A control', $TargetState = $null, $Owner = $null, $Phase = $null
        )
        [pscustomobject]@{
            Id = $Id; Title = $Title; Framework = 'Cloud Governance'; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = $EvidenceCount; Evidence = $Evidence
            EvidenceTruncated = $Truncated; EvidenceCap = 25
            Remediation = "Remediate $Id."; Manual = $false
            TargetState = $TargetState; Owner = $Owner; Effort = 'M'; Phase = $Phase
        }
    }

    function New-Area {
        param([string] $Area, $Score, [int] $Pass = 2, [int] $Fail = 1, [int] $Manual = 0)
        [pscustomobject]@{
            Framework = 'Cloud Governance'; Area = $Area; Score = $Score; Weight = 1.0
            Pass = $Pass; Partial = 0; Fail = $Fail; Manual = $Manual; Unknown = 0; Error = 0
        }
    }

    $Script:Collect = [pscustomobject]@{
        subscriptions = @(
            [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled' }
        )
        networking = [pscustomobject]@{ virtualNetworks = @(1, 2, 3) }
        _meta = [pscustomobject]@{ scope = 'All'; managementGroupId = 'mg-root'; tenantId = 'tenant-abc' }
    }

    $Script:Evidence = @(
        [pscustomobject]@{
            id   = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/stpayments01'
            name = 'stpayments01'; type = 'Microsoft.Storage/storageAccounts'
        }
    )

    $Script:Findings = @(
        New-Finding -Id 'SEC-01' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 1 `
            -Evidence $Script:Evidence -Title 'Storage accounts should disable public network access' `
            -TargetState 'PublicNetworkAccess=Disabled' -Owner 'Network Engineering' -Phase 1
        New-Finding -Id 'SEC-02' -Area 'Security' -Status 'Pass' -EvidenceCount 9 -Title 'Tag taxonomy applied'
        New-Finding -Id 'OPS-01' -Area 'Operations' -Status 'NotAssessed' -Severity 'medium' -Title 'Billing export configured'
    )

    $Script:Scored = [pscustomobject]@{
        GeneratedOn = '2026-08-01T10:00:00.0000000Z'
        Frameworks = @([pscustomobject]@{ Framework = 'Cloud Governance'; Score = 60; Version = 'CAF Govern' })
        Areas = @((New-Area -Area 'Security' -Score 60), (New-Area -Area 'Operations' -Score $null))
        Gaps = @(); Manual = @(); Errors = @(); Findings = $Script:Findings
    }

    $Script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-wordv2-$([guid]::NewGuid().ToString('N'))"
    $Script:Model = Build-ScoutReportModel -Findings $Script:Scored -Collect $Script:Collect -RunId 'run-v2'
    $Script:DocPath = Export-Word -Findings $Script:Scored -Collect $Script:Collect -OutputPath $Script:OutDir -Model $Script:Model
    $Script:Text = if ($Script:DocPath -like '*.docx') { Get-DocxText -Path $Script:DocPath } else { '' }
}

AfterAll {
    if ($Script:OutDir -and (Test-Path $Script:OutDir)) {
        Remove-Item $Script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Word v2 renders a real .docx' {
    It 'produces assessment_report.docx, not the HTML fallback' {
        $Script:DocPath | Should -BeLike '*assessment_report.docx'
        Test-Path $Script:DocPath | Should -BeTrue
    }
}

Describe 'Word v2 section inventory' {
    It 'renders every section the design calls for' -ForEach @(
        @{ Section = 'Document Information' }
        @{ Section = 'Contents' }
        @{ Section = 'Executive Summary' }
        @{ Section = 'In-scope inventory' }
        @{ Section = 'Composite maturity' }
        @{ Section = 'Findings Dashboard' }
        @{ Section = 'Maturity Scoring Methodology' }
        @{ Section = 'Key Risk Indicators' }
        @{ Section = 'Prioritised Focus Areas' }
        @{ Section = 'Overall Maturity Summary' }
        @{ Section = '90-Day Remediation Roadmap' }
        @{ Section = 'Exit criteria' }
        @{ Section = 'Appendix A' }
        @{ Section = 'Appendix B' }
        @{ Section = 'Scope & Assumptions' }
    ) {
        $Script:Text | Should -BeLike "*$Section*"
    }

    It 'renders one chapter per domain' {
        $Script:Text | Should -BeLike '*Chapter 1*'
        $Script:Text | Should -BeLike '*Chapter 2*'
    }

    It 'publishes the maturity rubric bands so a reader can interpret the score' {
        $Script:Text | Should -BeLike '*Initial / Reactive*'
        $Script:Text | Should -BeLike '*Optimised*'
    }
}

Describe 'Word v2 carries the data v1 discarded' {
    It 'names the affected resource, not just the rule that failed' {
        # The single defect that made every previous report unusable (Bug AB#6862).
        $Script:Text | Should -BeLike '*stpayments01*'
    }

    It 'names the subscription the affected resource lives in' {
        $Script:Text | Should -BeLike '*sub-prod*'
    }

    It 'renders the remediation action' {
        $Script:Text | Should -BeLike '*Remediate SEC-01*'
    }

    It 'renders the target state that closes the gap' {
        $Script:Text | Should -BeLike '*PublicNetworkAccess=Disabled*'
    }

    It 'renders the accountable owner on the roadmap' {
        $Script:Text | Should -BeLike '*Network Engineering*'
    }
}

Describe 'Word v2 honesty guarantees' {
    It 'renders a domain with no evidence as Not assessed, never with a score' {
        $Script:Text | Should -BeLike '*Not assessed*'
        $Script:Text | Should -BeLike '*No automated evidence was collected for this domain*'
    }

    It 'states that the composite excludes the unassessed domain rather than averaging in a zero' {
        $Script:Text | Should -BeLike '*excluded from the composite*'
    }

    It 'names uncollected inventory as a blind spot rather than showing it as zero' {
        $Script:Text | Should -BeLike '*blind spots, not zeroes*'
    }

    It 'labels the triage verdicts as heuristic, not as confirmed judgement' {
        $Script:Text | Should -BeLike '*not a confirmed judgement*'
    }

    It 'states the 1-10 scale is Scout''s own and not a Microsoft-published model' {
        $Script:Text | Should -BeLike "*Azure Scout*own*"
    }
}

Describe 'Word v2 truncated evidence' {
    It 'says the resource list is partial when evidence was capped' {
        $findings = @(
            New-Finding -Id 'BIG-01' -Area 'Security' -Status 'Fail' -EvidenceCount 198 -Truncated $true `
                -Evidence @(1..25 | ForEach-Object { [pscustomobject]@{ name = "sa$_" } }) `
                -Title 'Storage accounts should disable shared key access'
        )
        $scored = [pscustomobject]@{
            GeneratedOn = '2026-08-01T10:00:00.0000000Z'
            Frameworks = @(); Areas = @((New-Area -Area 'Security' -Score 20)); Gaps = @()
            Manual = @(); Errors = @(); Findings = $findings
        }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-wordv2t-$([guid]::NewGuid().ToString('N'))"
        try {
            $path = Export-Word -Findings $scored -Collect $Script:Collect -OutputPath $dir
            $text = Get-DocxText -Path $path
            $text | Should -BeLike '*198 affected (showing first 25)*'
            $text | Should -BeLike '*resource list above is partial*'
            $text | Should -BeLike '*affected totals themselves are complete*'
        }
        finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Word v2 degrades rather than failing' {
    It 'renders a document when there are no findings at all' {
        $scored = [pscustomobject]@{
            GeneratedOn = '2026-08-01T10:00:00.0000000Z'
            Frameworks = @(); Areas = @(); Gaps = @(); Manual = @(); Errors = @(); Findings = @()
        }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-wordv2e-$([guid]::NewGuid().ToString('N'))"
        try {
            $path = Export-Word -Findings $scored -Collect ([pscustomobject]@{}) -OutputPath $dir
            $path | Should -BeLike '*assessment_report.docx'
            $text = Get-DocxText -Path $path
            $text | Should -BeLike '*No open gaps*'
        }
        finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
