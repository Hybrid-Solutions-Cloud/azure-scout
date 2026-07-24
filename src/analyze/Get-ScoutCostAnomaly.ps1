#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Flag cost anomalies (statistical outliers, sudden spikes, top movers) in an
    already-collected cost dataset. Never calls Azure.

.DESCRIPTION
    Consumes cost data that was already collected elsewhere — either the raw
    shape `Get-AZSCCostInventory` (Modules/Private/Extraction/Get-AZTICostInventory.ps1)
    returns (an array of `{ SubscriptionId, SubscriptionName, CostData.Row[] }`
    blocks, where each `Row` is the Azure Cost Management query-result row order
    `[cost, usageDate, resourceType, resourceGroup, resourceLocation, serviceName,
    currency]` produced by that extraction's grouping/aggregation), or a
    pre-normalized cost dataset (an array of objects carrying `Amount`/`Cost` and
    `Period`/`Date`/`UsageDate`, plus optional `Scope`/`ResourceType`/
    `ResourceGroup`/`ServiceName`/`Location`/`ResourceId`). Both shapes are
    accepted through the same `-CostData` parameter — the function auto-detects
    which one it received.

    Records are grouped by `-GroupBy` (default `Scope`, `ResourceType` — the
    finest grain the current extraction's KQL grouping actually carries),
    aggregated (summed) per distinct `Period` within each group, then each
    group's period-ordered series is checked with THREE independent, additive
    techniques:

      1. Sudden spike  — month-over-month percent change between the two most
         recent periods in a group, flagged when |%change| >= -SpikeThresholdPct.
         Needs only 2 periods, so it is the only technique that reliably fires
         against the extraction's current 2-month default lookback (see
         LIMITATIONS below).
      2. Z-score       — |(value - group mean) / group stddev| >= -ZScoreThreshold.
         Needs >= -MinDataPoints periods in the group (default 4).
      3. IQR           — value outside [Q1 - k*IQR, Q3 + k*IQR] (k = -IqrMultiplier).
         Same -MinDataPoints gate as z-score.

    A flat/constant series (stddev = 0, IQR = 0) never flags under either
    statistical technique, by construction.

    Top movers are computed independently of the anomaly threshold — the
    largest absolute period-over-period dollar swing per group, always
    returned (subject to -TopMoversCount), so a caller can surface "what moved
    the most" even when nothing crossed a severity threshold.

.PARAMETER CostData
    The cost dataset to analyze. Accepts either the raw `Get-AZSCCostInventory`
    output shape, or a pre-normalized array of cost records. $null / an empty
    collection degrades gracefully (HasData = $false, clear Message, empty
    Anomalies/TopMovers) rather than throwing — this function never calls
    Azure and has no other way to obtain cost data.

.PARAMETER GroupBy
    Property names (present on the normalized record) to group the time
    series by before running anomaly detection. Defaults to `Scope`,
    `ResourceType` — the raw extraction's actual grouping grain. Pass e.g.
    `Scope`, `ResourceId` for a pre-normalized dataset that carries per-resource
    identifiers (the current collector-produced shape does not).

.PARAMETER ZScoreThreshold
    Minimum absolute z-score to flag a period as a statistical outlier.
    Default 2.5.

.PARAMETER IqrMultiplier
    Multiplier (k) applied to the interquartile range to compute the
    Tukey-style [Q1-k*IQR, Q3+k*IQR] outlier bounds. Default 1.5.

.PARAMETER SpikeThresholdPct
    Minimum absolute month-over-month percent change to flag a sudden spike.
    Default 75.

.PARAMETER MinDataPoints
    Minimum number of distinct periods a group must have before the z-score /
    IQR statistical checks run against it (spike detection only needs 2).
    Default 4.

.PARAMETER TopMoversCount
    Maximum number of top-mover entries to return, ranked by absolute
    period-over-period dollar delta. Default 5.

.OUTPUTS
    [pscustomobject] — HasData/Message/GeneratedOn/RecordCount/GroupCount/
    Anomalies[]/TopMovers[]. See tests/Analyze.CostAnomaly.Tests.ps1 for the
    exact shape exercised.

.NOTES
    Tracks ADO Story AB#324.

    LIMITATIONS (honest, by design):
      - The v2 collect pipeline (src/collect/Invoke-Collect.ps1) does NOT carry
        cost or cost-history data at all (only `costCleanup.orphanedDisks` /
        `orphanedPips` — cleanup candidates, not spend). Cost history only
        exists via the legacy `Get-AZSCCostInventory` extraction path, which
        defaults to a 2-month lookback (`-Days 60 -Granularity Monthly`) unless
        called with `-Days 365`+. With only 2 periods, z-score/IQR cannot run
        (MinDataPoints gate) — spike detection is the only technique that
        reliably fires against data collected with today's defaults.
      - That extraction also groups by ResourceType/ResourceGroup/
        ResourceLocation/ServiceName per subscription, NOT by individual
        resource — true per-resource-instance anomaly detection needs a
        pre-normalized dataset carrying a `ResourceId` field (supported via
        `-GroupBy Scope, ResourceId`), which nothing in this repo currently
        produces.
#>
function Get-ScoutCostAnomaly {
    [CmdletBinding()]
    param(
        $CostData,
        [string[]] $GroupBy = @('Scope', 'ResourceType'),
        [double] $ZScoreThreshold = 2.5,
        [double] $IqrMultiplier = 1.5,
        [double] $SpikeThresholdPct = 75,
        [int] $MinDataPoints = 4,
        [int] $TopMoversCount = 5
    )

    if (-not $GroupBy -or @($GroupBy).Count -eq 0) { $GroupBy = @('Scope', 'ResourceType') }

    function Get-CostAnomalyProp {
        param($Obj, [string] $Name)
        if ($null -eq $Obj) { return $null }
        $p = $Obj.PSObject.Properties[$Name]
        if ($p) { return $p.Value } else { return $null }
    }

    function Get-CostAnomalyPercentile {
        param([double[]] $SortedValues, [double] $Percentile)
        $n = $SortedValues.Count
        if ($n -eq 0) { return $null }
        if ($n -eq 1) { return $SortedValues[0] }
        $rank = ($Percentile / 100.0) * ($n - 1)
        $lowerIndex = [math]::Floor($rank)
        $upperIndex = [math]::Ceiling($rank)
        if ($lowerIndex -eq $upperIndex) { return $SortedValues[$lowerIndex] }
        $weight = $rank - $lowerIndex
        return $SortedValues[$lowerIndex] + ($weight * ($SortedValues[$upperIndex] - $SortedValues[$lowerIndex]))
    }

    function Get-CostAnomalyZSeverity {
        param([double] $AbsZ)
        if ($AbsZ -ge 4.0) { return 'Critical' }
        if ($AbsZ -ge 3.0) { return 'High' }
        return 'Medium'
    }

    function Get-CostAnomalySpikeSeverity {
        param([double] $AbsPct)
        if ($AbsPct -ge 300) { return 'Critical' }
        if ($AbsPct -ge 150) { return 'High' }
        return 'Medium'
    }

    function Get-CostAnomalyIqrSeverity {
        param([double] $Value, [double] $LowerBound, [double] $UpperBound, [double] $Iqr)
        if ($Iqr -le 0) { return 'Medium' }
        $distance = if ($Value -gt $UpperBound) { ($Value - $UpperBound) / $Iqr } else { ($LowerBound - $Value) / $Iqr }
        if ($distance -ge 3) { return 'Critical' }
        if ($distance -ge 1.5) { return 'High' }
        return 'Medium'
    }

    # ---- normalize into flat { Scope, ResourceType, ResourceGroup, Location, ServiceName, ResourceId, Currency, Period, Amount } records ----
    $records = [System.Collections.Generic.List[object]]::new()
    $items = @($CostData | Where-Object { $null -ne $_ })

    foreach ($item in $items) {
        # ---- raw Get-AZSCCostInventory shape: { SubscriptionId, SubscriptionName, CostData.Row[] }, or a bare CostData block itself ----
        $scope = $null
        $rows = $null
        $nestedCostData = Get-CostAnomalyProp $item 'CostData'
        if ($nestedCostData) {
            $rows = Get-CostAnomalyProp $nestedCostData 'Row'
            $scope = Get-CostAnomalyProp $item 'SubscriptionName'
            if ([string]::IsNullOrEmpty($scope)) { $scope = Get-CostAnomalyProp $item 'SubscriptionId' }
        }
        if (-not $rows) { $rows = Get-CostAnomalyProp $item 'Row' }

        if ($rows) {
            foreach ($row in @($rows)) {
                $r = @($row)
                if ($r.Count -lt 6) { continue }
                try { $amount = [double]$r[0] } catch { continue }
                $records.Add([pscustomobject]@{
                        Scope        = $scope
                        ResourceType = $r[2]
                        ResourceGroup= $r[3]
                        Location     = $r[4]
                        ServiceName  = $r[5]
                        ResourceId   = $null
                        Currency     = if ($r.Count -gt 6) { $r[6] } else { $null }
                        Period       = [string]$r[1]
                        Amount       = $amount
                    })
            }
            continue
        }

        # ---- pre-normalized record path ----
        $amountRaw = Get-CostAnomalyProp $item 'Amount'
        if ($null -eq $amountRaw) { $amountRaw = Get-CostAnomalyProp $item 'Cost' }
        if ($null -eq $amountRaw) { continue }
        try { $amount = [double]$amountRaw } catch { continue }

        $period = Get-CostAnomalyProp $item 'Period'
        if ([string]::IsNullOrEmpty($period)) { $period = Get-CostAnomalyProp $item 'Date' }
        if ([string]::IsNullOrEmpty($period)) { $period = Get-CostAnomalyProp $item 'UsageDate' }
        if ([string]::IsNullOrEmpty($period)) { continue }

        $scope = Get-CostAnomalyProp $item 'Scope'
        if ([string]::IsNullOrEmpty($scope)) { $scope = Get-CostAnomalyProp $item 'SubscriptionName' }
        if ([string]::IsNullOrEmpty($scope)) { $scope = Get-CostAnomalyProp $item 'SubscriptionId' }

        $records.Add([pscustomobject]@{
                Scope        = $scope
                ResourceType = Get-CostAnomalyProp $item 'ResourceType'
                ResourceGroup= Get-CostAnomalyProp $item 'ResourceGroup'
                Location     = Get-CostAnomalyProp $item 'Location'
                ServiceName  = Get-CostAnomalyProp $item 'ServiceName'
                ResourceId   = Get-CostAnomalyProp $item 'ResourceId'
                Currency     = Get-CostAnomalyProp $item 'Currency'
                Period       = [string]$period
                Amount       = $amount
            })
    }

    if ($records.Count -eq 0) {
        return [pscustomobject]@{
            HasData     = $false
            Message     = 'Get-ScoutCostAnomaly: no usable cost data was supplied. Pass -CostData with Get-AZSCCostInventory output (SubscriptionId/SubscriptionName/CostData.Row) or a pre-normalized cost dataset (Scope/Period/Amount) — no anomaly detection was performed.'
            GeneratedOn = (Get-Date).ToString('o')
            RecordCount = 0
            GroupCount  = 0
            Anomalies   = @()
            TopMovers   = @()
        }
    }

    # ---- group, aggregate per period, detect ----
    $groups = $records | Group-Object -Property $GroupBy
    $anomalies = [System.Collections.Generic.List[object]]::new()
    $movers = [System.Collections.Generic.List[object]]::new()
    $severityRank = @{ Critical = 3; High = 2; Medium = 1; Low = 0 }

    foreach ($g in $groups) {
        $groupKey = [ordered]@{}
        foreach ($k in $GroupBy) { $groupKey[$k] = Get-CostAnomalyProp $g.Group[0] $k }

        $byPeriod = $g.Group | Group-Object -Property Period | ForEach-Object {
            [pscustomobject]@{
                Period = $_.Name
                Amount = ($_.Group | Measure-Object -Property Amount -Sum).Sum
            }
        }
        $series = @($byPeriod | Sort-Object Period)
        $amounts = @($series | ForEach-Object { $_.Amount })
        $n = $amounts.Count
        if ($n -eq 0) { continue }

        # ---- spike (MoM) / new-spend mover ----
        if ($n -ge 2) {
            $prevAmount = $amounts[$n - 2]
            $currAmount = $amounts[$n - 1]
            $prevPeriod = $series[$n - 2].Period
            $currPeriod = $series[$n - 1].Period
            $deltaAmount = $currAmount - $prevAmount
            $deltaPct = if ($prevAmount -ne 0) { [math]::Round((($deltaAmount / [math]::Abs($prevAmount)) * 100), 2) } else { $null }

            $moverObj = [ordered]@{}
            foreach ($k in $GroupBy) { $moverObj[$k] = $groupKey[$k] }
            $moverObj['PreviousPeriod'] = $prevPeriod
            $moverObj['PreviousAmount'] = [math]::Round($prevAmount, 2)
            $moverObj['CurrentPeriod'] = $currPeriod
            $moverObj['CurrentAmount'] = [math]::Round($currAmount, 2)
            $moverObj['DeltaAmount'] = [math]::Round($deltaAmount, 2)
            $moverObj['DeltaPct'] = $deltaPct
            $movers.Add([pscustomobject]$moverObj)

            if ($null -ne $deltaPct -and [math]::Abs($deltaPct) -ge $SpikeThresholdPct) {
                $sev = Get-CostAnomalySpikeSeverity ([math]::Abs($deltaPct))
                $anomalyObj = [ordered]@{}
                foreach ($k in $GroupBy) { $anomalyObj[$k] = $groupKey[$k] }
                $anomalyObj['Period'] = $currPeriod
                $anomalyObj['Expected'] = [math]::Round($prevAmount, 2)
                $anomalyObj['Actual'] = [math]::Round($currAmount, 2)
                $anomalyObj['Deviation'] = $deltaPct
                $anomalyObj['Method'] = 'Spike'
                $anomalyObj['Severity'] = $sev
                $anomalyObj['Message'] = "Spend for '$(($groupKey.Values -join '/'))' in $currPeriod was $([math]::Round($currAmount,2)), a $deltaPct% change from $([math]::Round($prevAmount,2)) in $prevPeriod — sudden spike."
                $anomalies.Add([pscustomobject]$anomalyObj)
            }
        }
        elseif ($n -eq 1) {
            $moverObj = [ordered]@{}
            foreach ($k in $GroupBy) { $moverObj[$k] = $groupKey[$k] }
            $moverObj['PreviousPeriod'] = $null
            $moverObj['PreviousAmount'] = 0.0
            $moverObj['CurrentPeriod'] = $series[0].Period
            $moverObj['CurrentAmount'] = [math]::Round($amounts[0], 2)
            $moverObj['DeltaAmount'] = [math]::Round($amounts[0], 2)
            $moverObj['DeltaPct'] = $null
            $movers.Add([pscustomobject]$moverObj)
        }

        # ---- statistical outliers (z-score / IQR) ----
        if ($n -ge $MinDataPoints) {
            $mean = ($amounts | Measure-Object -Average).Average
            $variance = (($amounts | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum) / $n
            $stddev = [math]::Sqrt($variance)

            $sorted = @($amounts | Sort-Object)
            $q1 = Get-CostAnomalyPercentile -SortedValues $sorted -Percentile 25
            $q3 = Get-CostAnomalyPercentile -SortedValues $sorted -Percentile 75
            $iqr = $q3 - $q1
            $lowerBound = $q1 - ($IqrMultiplier * $iqr)
            $upperBound = $q3 + ($IqrMultiplier * $iqr)

            for ($i = 0; $i -lt $n; $i++) {
                $val = $amounts[$i]

                $flaggedZ = $false
                $z = 0.0
                if ($stddev -gt 0) {
                    $z = ($val - $mean) / $stddev
                    if ([math]::Abs($z) -ge $ZScoreThreshold) { $flaggedZ = $true }
                }
                $flaggedIqr = ($iqr -gt 0) -and (($val -lt $lowerBound) -or ($val -gt $upperBound))

                if (-not $flaggedZ -and -not $flaggedIqr) { continue }

                $method = if ($flaggedZ -and $flaggedIqr) { 'ZScore+IQR' } elseif ($flaggedZ) { 'ZScore' } else { 'IQR' }
                $severity = if ($flaggedZ) { Get-CostAnomalyZSeverity ([math]::Abs($z)) } else { Get-CostAnomalyIqrSeverity -Value $val -LowerBound $lowerBound -UpperBound $upperBound -Iqr $iqr }
                $deviation = if ($flaggedZ) { [math]::Round($z, 2) } else { [math]::Round((($val - $mean) / [math]::Max($iqr, 0.0001)), 2) }

                $anomalyObj = [ordered]@{}
                foreach ($k in $GroupBy) { $anomalyObj[$k] = $groupKey[$k] }
                $anomalyObj['Period'] = $series[$i].Period
                $anomalyObj['Expected'] = [math]::Round($mean, 2)
                $anomalyObj['Actual'] = [math]::Round($val, 2)
                $anomalyObj['Deviation'] = $deviation
                $anomalyObj['Method'] = $method
                $anomalyObj['Severity'] = $severity
                $anomalyObj['Message'] = "Spend for '$(($groupKey.Values -join '/'))' in $($series[$i].Period) was $([math]::Round($val,2)), a statistical outlier ($method) against the $n-period mean of $([math]::Round($mean,2))."
                $anomalies.Add([pscustomobject]$anomalyObj)
            }
        }
    }

    $sortedAnomalies = @($anomalies | Sort-Object -Property @{ Expression = { $severityRank[[string]$_.Severity] }; Descending = $true }, @{ Expression = { [math]::Abs($_.Deviation) }; Descending = $true })
    $topMovers = @($movers | Sort-Object -Property @{ Expression = { [math]::Abs($_.DeltaAmount) }; Descending = $true } | Select-Object -First $TopMoversCount)

    return [pscustomobject]@{
        HasData     = $true
        Message     = "Analyzed $($records.Count) cost record(s) across $($groups.Count) group(s); $($sortedAnomalies.Count) anomaly(ies) flagged."
        GeneratedOn = (Get-Date).ToString('o')
        RecordCount = $records.Count
        GroupCount  = $groups.Count
        Anomalies   = $sortedAnomalies
        TopMovers   = $topMovers
    }
}
