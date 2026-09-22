#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Aggregate findings into area/framework scores and a prioritized gap list.

.NOTES
    - Manual / Unknown / Error / NA are excluded from the score denominator but
      surfaced as counts so broken content is visible, not silently dropped (AB#5088).
    - Framework score is weighted by each area's AreaWeight, not a flat mean, so a
      3-rule area does not sway the headline like a 40-rule area (AB#5087).
    - Unknown/absent severities sort LAST in the gap list, not first (AB#5089).
    Tracks ADO Story AB#5036 and Bugs AB#5087/#5088/#5089.
#>
function Get-Score {
    param($Findings)

    # AB#6800 -- reuses the pillar rule findings already computed below to attach a WAF maturity
    # level (Microsoft's published 5-level model) alongside the existing percentage score. This
    # is a relabeling of the SAME score, not a second evaluation pass, so it costs nothing and
    # cannot desync from the percentage. Soft dependency: a caller that hasn't dot-sourced
    # Get-MaturityLevel.ps1 still gets scores exactly as before, just without the MaturityLevel
    # property being populated (falls back to $null).
    $maturityAvailable = [bool](Get-Command Get-MaturityLevel -ErrorAction SilentlyContinue)

    $statusWeight = @{ Pass = 1.0; Partial = 0.5; Fail = 0.0 }   # Manual/Unknown/Error excluded

    $areas = $Findings | Group-Object Framework, Area | ForEach-Object {
        $scorable = $_.Group | Where-Object { $_.Status -in 'Pass', 'Partial', 'Fail' }
        $den = ($scorable | Measure-Object).Count
        $num = ($scorable | ForEach-Object { $statusWeight[$_.Status] } | Measure-Object -Sum).Sum
        # AreaWeight is uniform within an area; take the first (default 1.0 if absent).
        $weight = 1.0
        $wf = $_.Group | Where-Object { $null -ne $_.PSObject.Properties['AreaWeight'] } | Select-Object -First 1
        if ($wf) { $weight = [double]$wf.AreaWeight }
        # AB#6817 -- carry the framework version through to the score output so any coverage
        # figure this object feeds names the version/date it was measured against. Findings
        # built by fixtures that predate this field simply have no FrameworkVersion property;
        # PSObject.Properties[...] is $null in that case rather than throwing under StrictMode.
        $vf = $_.Group | Where-Object {
            $null -ne $_.PSObject.Properties['FrameworkVersion'] -and $_.FrameworkVersion
        } | Select-Object -First 1
        $version = if ($vf) { $vf.FrameworkVersion } else { $null }
        $areaScore = if ($den -gt 0) { [math]::Round($num / $den * 100, 0, [System.MidpointRounding]::AwayFromZero) } else { $null }
        [pscustomobject]@{
            Framework     = $_.Group[0].Framework
            Area          = $_.Group[0].Area
            Weight        = $weight
            Version       = $version
            Score         = $areaScore
            MaturityLevel = if ($maturityAvailable) { Get-MaturityLevel -Score $areaScore } else { $null }
            # @(...) wrap is load-bearing: a Where-Object match of zero items collapses
            # to $null, and $null.Count throws PropertyNotFoundException under
            # Set-StrictMode -Version Latest — @() forces a real (possibly empty) array.
            Pass      = @($_.Group | Where-Object Status -eq 'Pass').Count
            Partial   = @($_.Group | Where-Object Status -eq 'Partial').Count
            Fail      = @($_.Group | Where-Object Status -eq 'Fail').Count
            Manual    = @($_.Group | Where-Object Status -eq 'Manual').Count
            Unknown   = @($_.Group | Where-Object Status -eq 'Unknown').Count
            Error     = @($_.Group | Where-Object Status -eq 'Error').Count
            # AB#6793 — the third compliance state. Deliberately excluded from `$scorable`
            # above (never a pass, never a fail, never in the score denominator) but still
            # counted and surfaced, the same way Manual/Unknown/Error are, so it is visible
            # rather than silently vanishing from every count.
            NotAssessed = @($_.Group | Where-Object Status -eq 'NotAssessed').Count
        }
    }

    $frameworks = $areas | Where-Object { $null -ne $_.Score } | Group-Object Framework | ForEach-Object {
        # Weighted average of area scores by AreaWeight (AB#5087).
        $wsum = ($_.Group | ForEach-Object { $_.Weight } | Measure-Object -Sum).Sum
        $wnum = ($_.Group | ForEach-Object { $_.Score * $_.Weight } | Measure-Object -Sum).Sum
        # A framework can contain areas sourced from different published baselines. Preserve
        # the complete distinct set; selecting the first area falsely labeled the whole score
        # with an arbitrary design-area version.
        $frameworkVersions = @($_.Group | ForEach-Object { $_.Version } | Where-Object { $_ } | Sort-Object -Unique)
        $fwScore = if ($wsum -gt 0) { [math]::Round($wnum / $wsum, 0, [System.MidpointRounding]::AwayFromZero) } else { $null }
        [pscustomobject]@{
            Framework     = $_.Name
            Score         = $fwScore
            Version       = if ($frameworkVersions.Count -gt 0) { $frameworkVersions -join '; ' } else { $null }
            Versions      = $frameworkVersions
            MaturityLevel = if ($maturityAvailable) { Get-MaturityLevel -Score $fwScore } else { $null }
            Unknown       = ($_.Group | Measure-Object Unknown -Sum).Sum
            Error         = ($_.Group | Measure-Object Error -Sum).Sum
        }
    }

    # prioritized gap list: fails first, weighted by severity; unknown/missing severity sorts LAST.
    # @(...) wraps below are load-bearing for the same reason as the Pass/Fail/etc.
    # counters above: a pipeline that emits zero objects collapses to $null on
    # assignment, and callers downstream expect a (possibly empty) collection.
    $sevRank = @{ high = 0; medium = 1; low = 2 }
    $gaps = @($Findings | Where-Object Status -eq 'Fail' |
        Sort-Object @{ E = { if ($_.Severity -and $sevRank.ContainsKey($_.Severity)) { $sevRank[$_.Severity] } else { 99 } } }, Area |
        Select-Object Id, Framework, Area, Severity, Title, Remediation)

    [pscustomobject]@{
        GeneratedOn = (Get-Date).ToString('o')
        Frameworks  = @($frameworks)
        Areas       = @($areas)
        Gaps        = $gaps
        Manual      = @($Findings | Where-Object Status -eq 'Manual')
        Errors      = @($Findings | Where-Object Status -in 'Error', 'Unknown')
        # AB#6793 — kept separate from Errors/Unknown: a control Azure has never evaluated is not
        # a Scout error, and lumping it in there would read as "something broke" rather than "not
        # assessed", which is the wrong signal for an operator deciding whether to assign an
        # initiative.
        NotAssessed = @($Findings | Where-Object Status -eq 'NotAssessed')
        Findings    = @($Findings)
    }
}
