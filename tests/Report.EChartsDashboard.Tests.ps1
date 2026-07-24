#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/report/renderers/Export-EChartsDashboard.ps1 -- the
    self-contained Apache ECharts HTML dashboard renderer (ADO Story AB#344).
    No Azure connection, no external network access required -- the vendored
    ECharts library is embedded in the renderer file itself (see that file's
    header for the offline-bundle design decision), so this suite never
    fetches anything at test time either.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/report/renderers/Export-EChartsDashboard.ps1"

    function New-DashTestFinding {
        param($Id, $Framework, $Area, $Status, $Severity = 'medium', $Weight = 1.0)
        [pscustomobject]@{
            Id = $Id; Title = "$Id title"; Framework = $Framework; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = 2; Evidence = @(); Remediation = "Remediate $Id."
            Manual = ($Status -eq 'Manual'); AreaWeight = $Weight
        }
    }

    # Mirrors Export-Pptx.ps1/Export-Word.ps1's test fixtures: a mix of
    # statuses and deliberately blank/null/unrecognized severities on Fail
    # rows, so the severity-bucketing guard is genuinely exercised.
    $script:Findings = @(
        (New-DashTestFinding 'net-1' 'CAF' 'Networking' 'Pass' 'low')
        (New-DashTestFinding 'net-2' 'CAF' 'Networking' 'Fail' 'high')
        (New-DashTestFinding 'net-3' 'CAF' 'Networking' 'Fail' $null)
        (New-DashTestFinding 'net-4' 'CAF' 'Networking' 'Fail' '')
        (New-DashTestFinding 'net-5' 'CAF' 'Networking' 'Fail' 'bogus-severity')
        (New-DashTestFinding 'sec-1' 'WAF' 'Security' 'Partial' 'medium')
        (New-DashTestFinding 'sec-2' 'WAF' 'Security' 'Manual')
        (New-DashTestFinding 'sec-3' 'WAF' 'Security' 'Unknown')
    )
    $script:Scored = Get-Score -Findings $script:Findings

    $script:CollectPath = Join-Path $script:Root 'tests' 'datadump' 'sample-collect.json'
    $script:Collect = Get-Content $script:CollectPath -Raw | ConvertFrom-Json -Depth 100
    $script:Collect | Add-Member -NotePropertyName _meta -NotePropertyValue ([pscustomobject]@{
            scope = 'ArmOnly'; managementGroupId = 'mg-test-01'; generatedOn = (Get-Date).ToString('o')
        }) -Force

    $script:OutDir = Join-Path $script:Root 'tests' 'test-output' 'echarts'
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
    New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

    function Get-DashboardPayload {
        param([string]$Html)
        $match = [regex]::Match($Html, 'window\.__DASHBOARD_DATA__ = (\{.*?\});(?=\s*</script>)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $match.Success | Should -BeTrue -Because 'the embedded window.__DASHBOARD_DATA__ payload must be present and well-formed'
        return ($match.Groups[1].Value | ConvertFrom-Json -Depth 20)
    }
}

AfterAll {
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Export-EChartsDashboard -- basic structure and offline self-containment (AB#344)' {
    BeforeAll {
        $script:DashPath = Export-EChartsDashboard -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Html = Get-Content $script:DashPath -Raw
        $script:Payload = Get-DashboardPayload -Html $script:Html
    }

    It 'writes assessment_dashboard.html into -OutputPath and returns its path' {
        $script:DashPath | Should -Exist
        (Split-Path $script:DashPath -Leaf) | Should -Be 'assessment_dashboard.html'
    }

    It 'has no external CDN / network references (self-contained offline artifact)' {
        $script:Html | Should -Not -Match 'src\s*=\s*"http'
        $script:Html | Should -Not -Match "src\s*=\s*'http"
        $script:Html | Should -Not -Match 'href\s*=\s*"http'
        $script:Html | Should -Not -Match "href\s*=\s*'http"
        $script:Html | Should -Not -Match 'cdn\.'
    }

    It 'is a single self-contained file (inline style/script only, no linked css or external js)' {
        $script:Html | Should -Match '<style>'
        $script:Html | Should -Match '<script>'
        $script:Html | Should -Not -Match '<link[^>]+rel="stylesheet"'
        $script:Html | Should -Not -Match '<script[^>]+src='
    }

    It 'embeds the real vendored Apache ECharts v5.6.0 library and reports HasEchartsLib true' {
        $script:Html | Should -Match 'version="5\.6\.0"'
        $script:Html | Should -Match 'Apache Software Foundation'
        $script:Payload.HasEchartsLib | Should -BeTrue
    }

    It 'declares all four required chart containers' {
        $script:Html | Should -Match 'id="chart-severity"'
        $script:Html | Should -Match 'id="chart-area-score"'
        $script:Html | Should -Match 'id="chart-status"'
        $script:Html | Should -Match 'id="chart-resources"'
    }

    It 'wires a light/dark theme toggle' {
        $script:Html | Should -Match 'id="theme-toggle"'
        $script:Html | Should -Match 'data-theme="dark"'
        $script:Html | Should -Match "data-theme.*===.*'dark'"
    }
}

Describe 'Export-EChartsDashboard -- chart data correctness' {
    BeforeAll {
        $script:DashPath2 = Export-EChartsDashboard -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Payload2 = Get-DashboardPayload -Html (Get-Content $script:DashPath2 -Raw)
    }

    It 'buckets findings-by-severity into exactly High/Medium/Low/Unknown, summing to the total finding count' {
        $names = $script:Payload2.SeverityCounts.Name
        $names | Should -Be @('High', 'Medium', 'Low', 'Unknown')
        ($script:Payload2.SeverityCounts.Value | Measure-Object -Sum).Sum | Should -Be $script:Findings.Count
        # net-2 (high) is the only recognized-severity Fail; net-3/4/5 (null/blank/bogus)
        # all bucket into Unknown alongside sec-3's Unknown *status* row (severity 'medium').
        ($script:Payload2.SeverityCounts | Where-Object Name -eq 'High').Value | Should -Be 1
        ($script:Payload2.SeverityCounts | Where-Object Name -eq 'Unknown').Value | Should -Be 3
    }

    It 'produces one score-by-area entry per scored area, sorted by Framework/Area' {
        $script:Payload2.AreaScores.Count | Should -Be $script:Scored.Areas.Count
        $script:Payload2.AreaScores[0].Name | Should -Be 'CAF - Networking'
        $script:Payload2.AreaScores[1].Name | Should -Be 'WAF - Security'
    }

    It 'sums the pass/partial/fail/manual/unknown/error breakdown to the total finding count' {
        $names = $script:Payload2.StatusBreakdown.Name
        $names | Should -Be @('Pass', 'Partial', 'Fail', 'Manual', 'Unknown', 'Error')
        ($script:Payload2.StatusBreakdown.Value | Measure-Object -Sum).Sum | Should -Be $script:Findings.Count
        ($script:Payload2.StatusBreakdown | Where-Object Name -eq 'Fail').Value | Should -Be 4
        ($script:Payload2.StatusBreakdown | Where-Object Name -eq 'Manual').Value | Should -Be 1
    }

    It 'auto-discovers resource counts from the real sample-collect.json fixture, capped at 12, sorted descending' {
        $rc = $script:Payload2.ResourceCounts
        $rc.Count | Should -Be 12
        ($rc | Where-Object Name -eq 'Virtual Networks').Value | Should -Be 3
        ($rc | Where-Object Name -eq 'Virtual Machines').Value | Should -Be 3
        ($rc | Where-Object Name -eq 'Advisor').Value | Should -Be 10
        # descending order
        for ($i = 1; $i -lt $rc.Count; $i++) { $rc[$i - 1].Value | Should -BeGreaterOrEqual $rc[$i].Value }
    }
}

Describe 'Export-EChartsDashboard -- graceful degrade when Collect is absent (AB#344)' {
    It 'does not throw and embeds an empty ResourceCounts array when Collect is $null' {
        { $script:BareDashPath = Export-EChartsDashboard -Findings $script:Scored -Collect $null -OutputPath $script:OutDir } | Should -Not -Throw
        $payload = Get-DashboardPayload -Html (Get-Content $script:BareDashPath -Raw)
        @($payload.ResourceCounts).Count | Should -Be 0
    }

    It 'does not throw on an empty Findings set (zero severity/status entries, still valid HTML)' {
        $emptyScored = Get-Score -Findings @()
        { $script:EmptyDashPath = Export-EChartsDashboard -Findings $emptyScored -Collect $null -OutputPath $script:OutDir } | Should -Not -Throw
        $payload = Get-DashboardPayload -Html (Get-Content $script:EmptyDashPath -Raw)
        ($payload.SeverityCounts.Value | Measure-Object -Sum).Sum | Should -Be 0
        @($payload.AreaScores).Count | Should -Be 0
    }
}

Describe 'Export-EChartsDashboard -- SVG/CSS fallback when the vendored library is unavailable (AB#344)' {
    It 'degrades to the lightweight inline SVG/CSS fallback and honestly banners it, rather than shipping a broken chart library' {
        $saved = $Script:ScoutEChartsLibJs
        try {
            $Script:ScoutEChartsLibJs = ''
            $path = Export-EChartsDashboard -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
            $html = Get-Content $path -Raw
            $payload = Get-DashboardPayload -Html $html

            $payload.HasEchartsLib | Should -BeFalse
            $html | Should -Match 'function renderFallbackPie'
            $html | Should -Match 'function renderFallbackBar'
            $html | Should -Match 'ECharts library was not available for this build'
            # still self-contained -- the fallback path must not reach for a CDN either.
            $html | Should -Not -Match 'src\s*=\s*"http'
            $html | Should -Not -Match 'cdn\.'
            # and dramatically smaller, since the ~1MB vendored library is absent.
            $html.Length | Should -BeLessThan 100000
        }
        finally {
            $Script:ScoutEChartsLibJs = $saved
        }
    }
}

Describe 'Export-EChartsDashboard -- non-fatal on failure (AB#344)' {
    It 'writes a clearly-labeled HTML fallback instead of throwing when rendering fails' {
        $dir = Join-Path $script:Root 'tests' 'test-output' 'echarts-forcefail'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        $savedFn = ${function:Get-ScoutEchartsSeverityCounts}
        try {
            Set-Item function:Get-ScoutEchartsSeverityCounts -Value { throw 'forced failure for fallback test' }
            $allOutput = @(Export-EChartsDashboard -Findings $script:Scored -Collect $script:Collect -OutputPath $dir 3>&1)
            $path = $allOutput | Where-Object { $_ -is [string] } | Select-Object -First 1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            $path | Should -Exist
            (Split-Path $path -Leaf) | Should -Be 'assessment_dashboard_fallback.html'
            $content = Get-Content $path -Raw
            $content | Should -Match 'dashboard generation failed'
            $content | Should -Match 'forced failure for fallback test'
            @($warnings) | Where-Object { $_.Message -match 'dashboard generation failed' } | Should -Not -BeNullOrEmpty
        }
        finally {
            Set-Item function:Get-ScoutEchartsSeverityCounts -Value $savedFn
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Get-ScoutEchartsSeverityBucket / Get-ScoutEchartsLabel (unit)' {
    It 'buckets null/blank/unrecognized severities as Unknown and recognized ones by name, never throws' {
        Get-ScoutEchartsSeverityBucket $null | Should -Be 'Unknown'
        Get-ScoutEchartsSeverityBucket '' | Should -Be 'Unknown'
        Get-ScoutEchartsSeverityBucket 'not-a-real-severity' | Should -Be 'Unknown'
        Get-ScoutEchartsSeverityBucket 'HIGH' | Should -Be 'High'
        Get-ScoutEchartsSeverityBucket 'Medium' | Should -Be 'Medium'
        Get-ScoutEchartsSeverityBucket 'low' | Should -Be 'Low'
    }

    It 'converts camelCase Collect property names into human-readable Title Case labels' {
        Get-ScoutEchartsLabel 'virtualNetworks' | Should -Be 'Virtual Networks'
        Get-ScoutEchartsLabel 'nsgPublicInbound' | Should -Be 'Nsg Public Inbound'
        Get-ScoutEchartsLabel 'advisor' | Should -Be 'Advisor'
    }
}
