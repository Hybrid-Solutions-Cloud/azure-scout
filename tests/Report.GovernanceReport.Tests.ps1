#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/report/renderers/Export-GovernanceReport.ps1 -- the consultant-grade
    Cloud Governance report (1-10 domain maturity score, radar chart, domain x status
    heatmap). ADO Story AB#6459, Feature AB#6458, Epic AB#6454.

    No Azure connection, no external network access required -- reuses
    Export-EChartsDashboard.ps1's vendored, fully offline ECharts library.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/assess/engine/Get-GovernanceDomainScore.ps1"
    . "$script:Root/src/report/renderers/Export-EChartsDashboard.ps1"   # loads $Script:ScoutEChartsLibJs
    . "$script:Root/src/report/renderers/Export-GovernanceReport.ps1"

    function New-GovFinding {
        param($Id, $Area, $Status, $Manual = $false)
        [pscustomobject]@{
            Id = $Id; Title = "$Id title"; Framework = 'Cloud Governance'; Area = $Area
            Severity = 'medium'; Status = $Status; EvidenceCount = 1; Evidence = @()
            Remediation = "Remediate $Id."; Manual = $Manual; AreaWeight = 1.0
        }
    }

    # Six of the seven domains carry a mix of Pass/Fail; Artificial Intelligence is entirely
    # Manual, so it must render as "Not assessed", never a fabricated score (AB#6844/#6845).
    $script:Findings = @(
        (New-GovFinding 'CGOV-RC-01' 'Regulatory Compliance' 'Pass')
        (New-GovFinding 'CGOV-RC-02' 'Regulatory Compliance' 'Manual' $true)
        (New-GovFinding 'CGOV-SC-02' 'Security' 'Pass')
        (New-GovFinding 'CGOV-CM-02' 'Cost Management' 'Fail')
        (New-GovFinding 'CGOV-CM-03' 'Cost Management' 'Pass')
        (New-GovFinding 'CGOV-OP-01' 'Operations' 'Pass')
        (New-GovFinding 'CGOV-DG-01' 'Data' 'Fail')
        (New-GovFinding 'CGOV-RM-01' 'Resource Management' 'Pass')
        (New-GovFinding 'CGOV-AI-01' 'Artificial Intelligence' 'Manual' $true)
        (New-GovFinding 'CGOV-AI-02' 'Artificial Intelligence' 'Manual' $true)
    )
    $script:Scored = Get-Score -Findings $script:Findings

    $script:Collect = [pscustomobject]@{
        _meta = [pscustomobject]@{ scope = 'ArmOnly'; managementGroupId = 'mg-test-01'; generatedOn = (Get-Date).ToString('o') }
    }

    $script:OutDir = Join-Path $script:Root 'tests' 'test-output' 'governance-report'
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
    New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

    function Get-GovPayload {
        param([string]$Html)
        $match = [regex]::Match($Html, 'window\.__GOV_DATA__ = (\{.*?\});(?=\s*</script>)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $match.Success | Should -BeTrue -Because 'the embedded window.__GOV_DATA__ payload must be present and well-formed'
        return ($match.Groups[1].Value | ConvertFrom-Json -Depth 20)
    }
}

AfterAll {
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Export-GovernanceReport -- basic structure and offline self-containment (AB#6459)' {
    BeforeAll {
        $script:ReportPath = Export-GovernanceReport -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Html = Get-Content $script:ReportPath -Raw
        $script:Payload = Get-GovPayload -Html $script:Html
    }

    It 'writes governance_report.html into -OutputPath and returns its path' {
        $script:ReportPath | Should -Exist
        (Split-Path $script:ReportPath -Leaf) | Should -Be 'governance_report.html'
    }

    It 'has no external CDN / network references / external fonts (strict CSP, offline)' {
        $script:Html | Should -Not -Match 'src\s*=\s*"http'
        $script:Html | Should -Not -Match "src\s*=\s*'http"
        $script:Html | Should -Not -Match 'href\s*=\s*"http'
        $script:Html | Should -Not -Match "href\s*=\s*'http"
        $script:Html | Should -Not -Match 'cdn\.'
        $script:Html | Should -Not -Match 'fonts\.googleapis'
        $script:Html | Should -Not -Match '@import\s+url\('
    }

    It 'is a single self-contained file (inline style/script only, no linked css or external js)' {
        $script:Html | Should -Match '<style>'
        $script:Html | Should -Match '<script>'
        $script:Html | Should -Not -Match '<link[^>]+rel="stylesheet"'
        $script:Html | Should -Not -Match '<script[^>]+src='
    }

    It 'reuses the SAME vendored Apache ECharts v5.6.0 library Export-EChartsDashboard.ps1 carries (no second charting mechanism)' {
        $script:Html | Should -Match 'version="5\.6\.0"'
        $script:Html | Should -Match 'Apache Software Foundation'
        $script:Payload.HasEchartsLib | Should -BeTrue
    }

    It 'declares both required chart containers (radar + heatmap)' {
        $script:Html | Should -Match 'id="chart-radar"'
        $script:Html | Should -Match 'id="chart-heatmap"'
    }

    It 'wires a light/dark theme toggle' {
        $script:Html | Should -Match 'id="theme-toggle"'
        $script:Html | Should -Match 'data-theme="dark"'
    }

    It 'renders in a standard browser as valid, well-formed HTML with a doctype and closing tags' {
        $script:Html | Should -Match '(?i)^\s*<!DOCTYPE html>'
        $script:Html | Should -Match '</html>\s*$'
        $script:Html | Should -Match '<body>'
        $script:Html | Should -Match '</body>'
    }
}

Describe 'Export-GovernanceReport -- seven-domain data correctness (AB#6459)' {
    BeforeAll {
        $script:ReportPath2 = Export-GovernanceReport -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Payload2 = Get-GovPayload -Html (Get-Content $script:ReportPath2 -Raw)
    }

    It 'produces exactly seven domains, matching CAF Govern''s seven risk categories' {
        $script:Payload2.Domains.Count | Should -Be 7
        ($script:Payload2.Domains.Area | Sort-Object) | Should -Be @('Artificial Intelligence', 'Cost Management', 'Data', 'Operations', 'Regulatory Compliance', 'Resource Management', 'Security')
    }

    It 'gives every scored (non-Manual-only) domain a 1-10 score' {
        $scoredDomains = @($script:Payload2.Domains | Where-Object { -not $_.NotAssessed })
        $scoredDomains.Count | Should -BeGreaterThan 0
        foreach ($d in $scoredDomains) {
            $d.Score | Should -BeGreaterOrEqual 1
            $d.Score | Should -BeLessOrEqual 10
        }
    }

    It 'marks the all-Manual Artificial Intelligence domain NotAssessed, never a fabricated score' {
        $ai = $script:Payload2.Domains | Where-Object Area -eq 'Artificial Intelligence'
        $ai.NotAssessed | Should -BeTrue
        ($null -eq $ai.Score) | Should -BeTrue
    }

    It 'renders "Not assessed" text in the page for the AI domain, not a number or blank cell' {
        $html = Get-Content $script:ReportPath2 -Raw
        $html | Should -Match 'Not assessed'
    }

    It 'surfaces a not-assessed callout listing Artificial Intelligence by name' {
        $html = Get-Content $script:ReportPath2 -Raw
        $html | Should -Match 'not-assessed-callout'
        $html | Should -Match 'Artificial Intelligence'
    }

    It 'computes an overall headline score consistent with the framework-level percentage' {
        ($null -eq $script:Payload2.OverallScore) | Should -BeFalse
        $script:Payload2.OverallScore | Should -BeGreaterOrEqual 1
        $script:Payload2.OverallScore | Should -BeLessOrEqual 10
    }
}

Describe 'Export-GovernanceReport -- zero-governance-data tenant (the false-pass class, AB#6839/#6844/#6845)' {
    BeforeAll {
        # A collect run scored against a RuleSet that never loaded caf.govern.*.yaml (e.g. a
        # narrower assessment) produces zero Cloud Governance areas -- must NOT render an
        # empty/blank page.
        $script:EmptyScored = Get-Score -Findings @()
        $script:ReportPath3 = Export-GovernanceReport -Findings $script:EmptyScored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Payload3 = Get-GovPayload -Html (Get-Content $script:ReportPath3 -Raw)
    }

    It 'still renders all seven expected domain names, every one Not assessed' {
        $script:Payload3.Domains.Count | Should -Be 7
        $script:Payload3.Domains | ForEach-Object { $_.NotAssessed | Should -BeTrue }
    }

    It 'renders the overall score as Not assessed (null), never a fabricated headline number' {
        ($null -eq $script:Payload3.OverallScore) | Should -BeTrue
    }

    It 'the rendered HTML shows "Not assessed" text, not a blank or a zero' {
        $html = Get-Content $script:ReportPath3 -Raw
        $html | Should -Match 'Not assessed'
    }
}

Describe 'Export-GovernanceReport -- non-fatal on failure (mirrors Export-EChartsDashboard.ps1''s pattern)' {
    It 'never throws back into the caller even when Findings is $null' {
        { Export-GovernanceReport -Findings $null -Collect $null -OutputPath $script:OutDir } | Should -Not -Throw
    }
}
