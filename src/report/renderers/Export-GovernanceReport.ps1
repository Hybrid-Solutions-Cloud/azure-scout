#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Render the consultant-grade Cloud Governance assessment report -- a self-contained,
    offline HTML document with a 1-10 domain maturity score per CAF Govern risk category, a
    radar chart across the seven domains, and a domain-by-status heatmap (AB#6459, Feature
    AB#6458, Epic AB#6454).

.DESCRIPTION
    Consumes the SAME scored Findings object every other Export-* renderer in this folder
    consumes (Get-Score's GeneratedOn/Frameworks/Areas/Gaps/Manual/Errors/Findings), filtered
    to the 'Cloud Governance' framework (the seven caf.govern.*.yaml rule files -- Regulatory
    Compliance, Security, Cost Management, Operations, Data, Resource Management, Artificial
    Intelligence). Get-GovernanceDomainScore.ps1 relabels each domain's existing 0-100
    percentage score onto a 1-10 scale; no rule is duplicated and no second evaluation pass
    runs. See docs/design/governance-domain-maturity-scale.md for why 1-10 (not WAF's
    5-level model, which Get-MaturityLevel.ps1 already covers for WAF pillars -- a DIFFERENT
    framework at a DIFFERENT granularity; this report never mixes the two scales on one axis).

    OFFLINE / CSP: reuses Export-EChartsDashboard.ps1's vendored Apache ECharts v5.6.0 build
    ($Script:ScoutEChartsLibJs) rather than introducing a second charting mechanism or a CDN
    reference. AzureScout.psm1 dot-sources every src/**/*.ps1 file into the module's own
    script scope, so a `$Script:`-scoped variable set in one dot-sourced file is visible to
    every other dot-sourced file in the same module (the same soft-dependency shape
    Get-Score.ps1/Get-MaturityLevel.ps1 already use) -- read via
    Get-Variable -Scope Script so a caller that has NOT loaded Export-EChartsDashboard.ps1
    (e.g. a narrow unit test) degrades to the fallback banner rather than throwing.

    THE FALSE-PASS CLASS THIS REPORT MUST NOT JOIN (AB#6839/#6844/#6845): a domain whose
    every rule is Manual/Unknown/Error has Get-Score's denominator at 0, so its percentage
    score is $null and Get-GovernanceDomainScore marks it NotAssessed = $true. This report
    renders those domains as "Not assessed" text (never a fabricated low score, and never
    silently dropped from the domain list or the heatmap) and plots them as a gap (null) in
    the radar line rather than a 0 -- a 0 on a 1-10 radar would visually read as "assessed
    and scored worst", which is exactly the false-pass-adjacent misreading this exists to
    prevent. See the "no automated evidence" callout the template renders below the radar.

.PARAMETER Findings
    The scored Findings object from Get-Score (run against the caf.govern.* rule files, or
    any RuleSet including them -- e.g. LandingZone's caf.*).

.PARAMETER Collect
    The raw Collect object. Only used for _meta.scope/_meta.managementGroupId (title-bar
    context); every read is StrictMode-safe optional access via the same
    Get-ScoutEchartsProp-style accessor pattern Export-EChartsDashboard.ps1 uses.

.PARAMETER OutputPath
    Folder to write governance_report.html into. Created if missing.

.OUTPUTS
    [string] the full path to the written governance_report.html file (or, on a genuine
    render failure, a minimal self-contained fallback HTML file -- this renderer never
    throws back into Export-Report.ps1's dispatch loop).

.NOTES
    Tracks ADO Story AB#6459 (Feature AB#6458, Epic AB#6454).
#>

#region Palette (mirrors Export-EChartsDashboard.ps1/Export-Pptx.ps1/Export-Word.ps1's navy/steel/gold corporate palette)

$Script:ScoutGovNavy = '1F4E78'
$Script:ScoutGovSteel = '2E75B6'
$Script:ScoutGovGreen = '2E7D32'
$Script:ScoutGovGold = 'B8860B'
$Script:ScoutGovRed = 'B00020'
$Script:ScoutGovGray = '595959'

#endregion

#region Data helpers

function Get-ScoutGovProp {
    param($Obj, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $Default }
}

function Get-ScoutGovScoreColor {
    # 1-10 scale color banding -- distinct thresholds from
    # Get-ScoutEchartsScoreColor's 0-100 banding (>=80/>=50), scaled proportionally
    # (>=8/>=5 on a 1-10 scale) so the two renderers stay visually consistent.
    param($Score)
    if ($null -eq $Score) { return $Script:ScoutGovGray }
    if ($Score -ge 8) { return $Script:ScoutGovGreen }
    if ($Score -ge 5) { return $Script:ScoutGovGold }
    return $Script:ScoutGovRed
}

#endregion

#region HTML fallback (non-fatal-on-failure, mirrors Export-EChartsDashboard.ps1's pattern)

function Export-ScoutGovernanceHtmlFallback {
    param($Findings, [string] $OutputPath, [string] $Reason)
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $safeReason = $Reason -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $generatedOn = Get-ScoutGovProp -Obj $Findings -Name 'GeneratedOn' -Default '(unknown)'
    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Azure Scout — Cloud Governance Report (fallback)</title>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; color:#1a1a1a; margin: 2rem; }
  .banner { background:#B00020; color:#fff; padding: 0.75rem 1rem; margin-bottom:1rem; }
</style>
</head>
<body>
<div class="banner">
  Governance report generation failed for this run -- this is a minimal HTML placeholder, not the real report.
  Reason: $safeReason
</div>
<h1>Azure Scout — Cloud Governance Report</h1>
<p>Generated: $generatedOn</p>
</body>
</html>
"@
    $path = Join-Path $OutputPath 'governance_report_fallback.html'
    $html | Out-File -FilePath $path -Encoding utf8
    return $path
}

#endregion

#region Report HTML shell (CSS + client-side JS, theme-aware, ECharts-or-plain-table fallback)

$Script:ScoutGovShellTemplate = @'
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Azure Scout — Cloud Governance Report</title>
<style>
  :root {
    --bg: #F6F9FD; --panel: #FFFFFF; --ink: #1A1A1A; --gray: #595959;
    --line: #E2E2E2; --navy: #1F4E78; --gold: #B8860B;
  }
  html[data-theme="dark"] {
    --bg: #14181D; --panel: #1E242B; --ink: #EAEDF0; --gray: #A9B4BF;
    --line: #333B44; --navy: #6EA8DC; --gold: #E0B84A;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: 'Segoe UI', Arial, sans-serif; background: var(--bg); color: var(--ink);
    transition: background-color 0.15s ease, color 0.15s ease;
  }
  header {
    background: var(--navy); color: #fff; padding: 1.1rem 1.5rem; display: flex;
    align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 0.5rem;
  }
  header h1 { margin: 0; font-size: 1.35rem; }
  header .meta { font-size: 0.85rem; opacity: 0.85; }
  #theme-toggle {
    background: transparent; border: 1px solid #ffffff66; color: #fff; padding: 0.35rem 0.8rem;
    border-radius: 4px; cursor: pointer; font-size: 0.85rem;
  }
  #theme-toggle:hover { background: #ffffff22; }
  .headline {
    display: flex; align-items: baseline; gap: 0.75rem; padding: 1rem 1.5rem;
  }
  .headline .score { font-size: 2.4rem; font-weight: 700; color: var(--navy); }
  .headline .label { font-size: 0.95rem; color: var(--gray); }
  .not-assessed-callout {
    background: #B8860B22; border: 1px solid var(--gold); color: var(--ink);
    padding: 0.6rem 1rem; margin: 0 1.5rem 0.5rem 1.5rem; border-radius: 6px; font-size: 0.85rem;
  }
  .grid {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 1rem; padding: 1.25rem;
  }
  .card {
    background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 0.9rem 1rem;
  }
  .card h2 { margin: 0 0 0.5rem 0; font-size: 1rem; color: var(--navy); }
  .chart { width: 100%; height: 380px; }
  table.domain-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  table.domain-table th, table.domain-table td { padding: 0.4rem 0.5rem; border-bottom: 1px solid var(--line); text-align: left; }
  table.domain-table th { color: var(--gray); font-weight: 600; }
  .pill { display: inline-block; padding: 0.1rem 0.55rem; border-radius: 999px; color: #fff; font-weight: 600; font-size: 0.8rem; }
  footer { text-align: center; color: var(--gray); font-size: 0.78rem; padding: 1rem; }
</style>
</head>
<body>
<header>
  <div>
    <h1>Azure Scout — Cloud Governance Report</h1>
    <div class="meta" id="meta-line"></div>
  </div>
  <button id="theme-toggle" type="button">Toggle theme</button>
</header>
<div class="headline">
  <span class="score" id="overall-score">--</span>
  <span class="label">overall governance maturity (1-10 scale, Scout's own -- see the report footer)</span>
</div>
<div id="not-assessed-slot"></div>
<div id="fallback-banner-slot"></div>
<div class="grid">
  <div class="card"><h2>Domain Maturity — Radar (1-10 per CAF Govern risk category)</h2><div class="chart" id="chart-radar"></div></div>
  <div class="card"><h2>Domain × Status — Heatmap</h2><div class="chart" id="chart-heatmap"></div></div>
  <div class="card" style="grid-column: 1 / -1;">
    <h2>Seven Governance Domains</h2>
    <table class="domain-table" id="domain-table">
      <thead><tr><th>Domain</th><th>Score</th><th>Pass</th><th>Partial</th><th>Fail</th><th>Manual</th><th>Unknown</th></tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>
<footer>
  Generated by Azure Scout — fully self-contained, works offline. The 1-10 domain scale is
  Scout's own (CAF Govern publishes no numeric maturity model); it is not comparable to the
  Well-Architected Framework's separate 5-level maturity model shown on WAF pillar reports.
</footer>
<script>
window.__GOV_DATA__ = /*__GOV_DATA__*/;
</script>
<script>
/*__ECHARTS_LIB__*/
</script>
<script>
(function () {
  'use strict';
  var DATA = window.__GOV_DATA__;
  var metaEl = document.getElementById('meta-line');
  var metaParts = [];
  if (DATA.Meta && DATA.Meta.GeneratedOn) { metaParts.push('Generated ' + DATA.Meta.GeneratedOn); }
  if (DATA.Meta && DATA.Meta.Scope) { metaParts.push('Scope: ' + DATA.Meta.Scope); }
  if (DATA.Meta && DATA.Meta.ManagementGroupId) { metaParts.push('Management Group: ' + DATA.Meta.ManagementGroupId); }
  metaEl.textContent = metaParts.join('  ·  ');

  document.getElementById('overall-score').textContent =
    (DATA.OverallScore === null || DATA.OverallScore === undefined) ? 'Not assessed' : String(DATA.OverallScore) + ' / 10';

  var notAssessedDomains = DATA.Domains.filter(function (d) { return d.NotAssessed; }).map(function (d) { return d.Area; });
  if (notAssessedDomains.length > 0) {
    var callout = document.createElement('div');
    callout.className = 'not-assessed-callout';
    callout.textContent = 'Not assessed (no automated evidence collected -- shown as a gap in the radar, never a fabricated score): ' + notAssessedDomains.join(', ');
    document.getElementById('not-assessed-slot').appendChild(callout);
  }

  // ---- domain table (always rendered, chart library or not) ----
  var tbody = document.querySelector('#domain-table tbody');
  DATA.Domains.forEach(function (d) {
    var tr = document.createElement('tr');
    function td(text) { var c = document.createElement('td'); c.textContent = text; return c; }
    tr.appendChild(td(d.Area));
    var scoreCell = document.createElement('td');
    if (d.NotAssessed) {
      scoreCell.textContent = 'Not assessed';
    } else {
      var pill = document.createElement('span');
      pill.className = 'pill';
      pill.style.background = d.Color;
      pill.textContent = d.Score + ' / 10';
      scoreCell.appendChild(pill);
    }
    tr.appendChild(scoreCell);
    tr.appendChild(td(d.Pass));
    tr.appendChild(td(d.Partial));
    tr.appendChild(td(d.Fail));
    tr.appendChild(td(d.Manual));
    tr.appendChild(td(d.Unknown));
    tbody.appendChild(tr);
  });

  var HAS_ECHARTS = !!(DATA.HasEchartsLib && typeof echarts !== 'undefined');
  var charts = {};

  function getThemeColors() {
    var dark = document.documentElement.getAttribute('data-theme') === 'dark';
    return {
      text: dark ? '#EAEDF0' : '#1A1A1A',
      axis: dark ? '#333B44' : '#E2E2E2',
      bg: 'transparent'
    };
  }

  function renderRadar() {
    var el = document.getElementById('chart-radar');
    var chart = charts.radar || echarts.init(el);
    charts.radar = chart;
    var c = getThemeColors();
    var indicators = DATA.Domains.map(function (d) { return { name: d.Area, max: 10 }; });
    // NotAssessed domains plot as null -- ECharts breaks the radar line at a null point
    // rather than drawing a false "0" vertex, which would visually read as "assessed and
    // scored worst" instead of "no automated evidence" (see this file's header .DESCRIPTION).
    var values = DATA.Domains.map(function (d) { return d.NotAssessed ? null : d.Score; });
    chart.setOption({
      backgroundColor: c.bg,
      textStyle: { color: c.text },
      tooltip: {},
      radar: {
        indicator: indicators,
        axisName: { color: c.text },
        splitLine: { lineStyle: { color: c.axis } },
        splitArea: { show: false },
        axisLine: { lineStyle: { color: c.axis } }
      },
      series: [{
        type: 'radar',
        data: [{ value: values, name: 'Domain maturity (1-10)', areaStyle: { opacity: 0.15 }, lineStyle: { color: '#2E75B6' }, itemStyle: { color: '#2E75B6' } }]
      }]
    }, true);
  }

  function renderHeatmap() {
    var el = document.getElementById('chart-heatmap');
    var chart = charts.heatmap || echarts.init(el);
    charts.heatmap = chart;
    var c = getThemeColors();
    var domains = DATA.Domains.map(function (d) { return d.Area; });
    var statuses = ['Pass', 'Partial', 'Fail', 'Manual', 'Unknown'];
    var cells = [];
    var max = 1;
    DATA.Domains.forEach(function (d, di) {
      statuses.forEach(function (s, si) {
        var v = d[s] || 0;
        if (v > max) { max = v; }
        cells.push([si, di, v]);
      });
    });
    chart.setOption({
      backgroundColor: c.bg,
      textStyle: { color: c.text },
      tooltip: { position: 'top' },
      grid: { left: '22%', right: '6%', top: 10, bottom: 40 },
      xAxis: { type: 'category', data: statuses, axisLine: { lineStyle: { color: c.axis } }, axisLabel: { color: c.text }, splitArea: { show: true } },
      yAxis: { type: 'category', data: domains, axisLine: { lineStyle: { color: c.axis } }, axisLabel: { color: c.text }, splitArea: { show: true } },
      visualMap: {
        min: 0, max: max, calculable: true, orient: 'horizontal', left: 'center', bottom: 0,
        textStyle: { color: c.text }, inRange: { color: ['#F6F9FD', '#2E75B6', '#1F4E78'] }
      },
      series: [{
        type: 'heatmap',
        data: cells,
        label: { show: true, color: c.text },
        emphasis: { itemStyle: { shadowBlur: 6, shadowColor: 'rgba(0,0,0,0.3)' } }
      }]
    }, true);
  }

  function renderFallbackTableNote() {
    var banner = document.createElement('div');
    banner.className = 'not-assessed-callout';
    banner.textContent = 'ECharts library was not available for this build -- the radar and heatmap charts are not rendered; the domain table above carries the same data.';
    document.getElementById('fallback-banner-slot').appendChild(banner);
  }

  function renderAll() {
    if (HAS_ECHARTS) { renderRadar(); renderHeatmap(); } else { renderFallbackTableNote(); }
  }

  document.getElementById('theme-toggle').addEventListener('click', function () {
    var cur = document.documentElement.getAttribute('data-theme');
    document.documentElement.setAttribute('data-theme', cur === 'dark' ? 'light' : 'dark');
    if (HAS_ECHARTS) { renderRadar(); renderHeatmap(); }
  });

  window.addEventListener('resize', function () {
    if (!HAS_ECHARTS) { return; }
    Object.keys(charts).forEach(function (k) { charts[k].resize(); });
  });

  renderAll();
})();
</script>
</body>
</html>
'@

#endregion

function Export-GovernanceReport {
    <#
    .SYNOPSIS
        Renders the self-contained Cloud Governance assessment report (radar + heatmap +
        1-10 domain table). See this file's header comment-based help for the full design
        writeup (AB#6459).
    #>
    param($Findings, $Collect, [string] $OutputPath)

    try {
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        $areas = @(Get-ScoutGovProp -Obj $Findings -Name 'Areas')
        $generatedOn = Get-ScoutGovProp -Obj $Findings -Name 'GeneratedOn'

        $metaSrc = Get-ScoutGovProp -Obj $Collect -Name '_meta'
        $scope = Get-ScoutGovProp -Obj $metaSrc -Name 'scope'
        $mgId = Get-ScoutGovProp -Obj $metaSrc -Name 'managementGroupId'

        # NOT wrapped in @(): Get-GovernanceDomainScore returns its array through
        # `Write-Output -NoEnumerate`, so @() here would produce a one-element array whose
        # sole element is the (possibly empty) real array -- the same gotcha
        # Invoke-Assessment.ps1 documents for Resolve-JsonPath's callers.
        $domainScores = Get-GovernanceDomainScore -Areas $areas -Framework 'Cloud Governance'

        # AB#6459 AC: seven governance domains. A collect run scored against a RuleSet that
        # never loaded the caf.govern.*.yaml files produces zero Cloud Governance areas --
        # surface that honestly (all seven "Not assessed") rather than rendering an empty
        # page, the same "absence is visible, not silent" principle NotAssessed already
        # follows elsewhere in this codebase.
        $expectedDomains = @('Regulatory Compliance', 'Security', 'Cost Management', 'Operations', 'Data', 'Resource Management', 'Artificial Intelligence')
        if ($domainScores.Count -eq 0) {
            $domainScores = @($expectedDomains | ForEach-Object {
                    [pscustomobject]@{
                        Area = $_; PercentScore = $null; Score = $null; NotAssessed = $true
                        Pass = 0; Partial = 0; Fail = 0; Manual = 0; Unknown = 0; Error = 0
                    }
                })
        }

        $domainPayload = @($domainScores | ForEach-Object {
                [pscustomobject]@{
                    Area        = $_.Area
                    Score       = $_.Score
                    NotAssessed = $_.NotAssessed
                    Color       = "#$(Get-ScoutGovScoreColor $_.Score)"
                    Pass        = $_.Pass
                    Partial     = $_.Partial
                    Fail        = $_.Fail
                    Manual      = $_.Manual
                    Unknown     = $_.Unknown
                }
            })

        # Overall headline: the Cloud Governance framework's own weighted-mean percentage
        # (already computed by Get-Score across the seven domains, AreaWeight-weighted --
        # AB#5087), relabeled onto the same 1-10 scale as the per-domain figures via the
        # exact same ConvertTo-ScoutGovernanceScale helper, so the headline and the seven
        # domain numbers can never use different arithmetic.
        $frameworks = @(Get-ScoutGovProp -Obj $Findings -Name 'Frameworks')
        $govFramework = $frameworks | Where-Object { $_.Framework -eq 'Cloud Governance' } | Select-Object -First 1
        $overallPct = if ($govFramework) { Get-ScoutGovProp -Obj $govFramework -Name 'Score' } else { $null }
        $overallScore = ConvertTo-ScoutGovernanceScale -PercentScore $overallPct

        $hasLib = [bool](Get-Variable -Name ScoutEChartsLibJs -Scope Script -ErrorAction SilentlyContinue) -and
                  -not [string]::IsNullOrWhiteSpace($Script:ScoutEChartsLibJs)

        $payload = [pscustomobject]@{
            Meta          = [pscustomobject]@{ GeneratedOn = $generatedOn; Scope = $scope; ManagementGroupId = $mgId }
            Domains       = $domainPayload
            OverallScore  = $overallScore
            HasEchartsLib = $hasLib
        }

        # </script> inside embedded JSON would otherwise close the <script> tag early.
        $json = ($payload | ConvertTo-Json -Depth 20) -replace '</', '<\/'

        $html = $Script:ScoutGovShellTemplate.Replace('/*__GOV_DATA__*/', $json)
        $html = $html.Replace('/*__ECHARTS_LIB__*/', $(if ($hasLib) { $Script:ScoutEChartsLibJs } else { '' }))

        $outFile = Join-Path $OutputPath 'governance_report.html'
        $html | Out-File -FilePath $outFile -Encoding utf8

        return $outFile
    }
    catch {
        Write-Warning "Export-GovernanceReport: report generation failed ($_) -- writing a minimal HTML placeholder instead."
        return (Export-ScoutGovernanceHtmlFallback -Findings $Findings -OutputPath $OutputPath -Reason $_.Exception.Message)
    }
}
