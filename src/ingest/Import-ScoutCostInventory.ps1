#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Native FinOps cost ingestor — populate collect.json's `finops` object from
    Get-ScoutCostInventory (and, when available, Get-ScoutCostAnomaly), and make the
    EA/MCA billing gate a first-class, queryable signal rather than a silent empty array.

.DESCRIPTION
    AB#6826 (Feature AB#6749, Epic AB#6454). The `caf.finops.yaml` rule set (see
    docs/frameworks/finops-review-question-set.md) needs to tell a genuinely blocked cost
    pull apart from a genuinely zero-spend estate — a `countEquals: 0` assert cannot make
    that distinction on its own, so this ingestor computes an explicit `available` boolean
    findings can gate on (Invoke-Rule's `assert.gate`, AB#6826).

    Two independent reasons cost data can be unavailable, both surfaced here:
      1. `Az.CostManagement` is not installed (Scout deliberately does not auto-install it
         -- see Get-ScoutCostInventory's own header for why). Deterministic, no Azure call
         needed to detect it.
      2. The signed-in identity lacks Cost Management Reader (or equivalent EA/MCA billing)
         rights. Get-ScoutCostInventory already degrades this to an empty CostData array
         PER SUBSCRIPTION with a Write-Warning naming the cause (AB#5636's non-fatal
         guarantee) -- this ingestor listens for those warnings and, when EVERY queried
         subscription came back both empty and warned, treats the whole pull as blocked
         rather than a clean "no cost anomalies" answer. A MIXED result (some subscriptions
         blocked, some not) is reported `available = $true` with the blocked subscriptions
         named separately, because "some data is missing" and "no data was ever gathered"
         are different findings.

.PARAMETER Collect
    The collect object to attach/merge `finops` onto. Invoke-Collect.ps1 already stamps
    `finops.reservations` (an ARM/Resource Graph signal, Reader-scoped, never billing-gated)
    before this ingestor runs; this function extends that object rather than replacing it.

.PARAMETER FromInventory
    Optional `Get-ScoutCostInventory`-shaped rows from a combined `-InventoryAndAssessment
    -IncludeCosts` run (`$ExtractionData.Costs`) -- when supplied, no new Azure call is made
    (the collect-once pattern every other ingestor here already follows).

.OUTPUTS
    $Collect, with `finops.available`, `finops.moduleAvailable`, `finops.costRows`,
    `finops.blockedSubscriptions`, and `finops.anomalies` populated.

.NOTES
    Read-only throughout -- every call below is a GET. Never throws: a cost-pull failure
    must not cost the caller their assessment, the same guarantee Get-ScoutCostInventory
    itself makes.
#>
function Import-ScoutCostInventory {
    [CmdletBinding()]
    param($Collect, [object[]] $FromInventory)

    # Start from whatever finops shape already exists on $Collect (Invoke-Collect's
    # `reservations` stub) so this ingestor extends it instead of clobbering it.
    $existing = if ($Collect -and $Collect.PSObject.Properties['finops'] -and $Collect.finops) { $Collect.finops } else { $null }
    $reservations = if ($existing -and $existing.PSObject.Properties['reservations']) { @($existing.reservations) } else { @() }
    $reservationRecommendations = if ($existing -and $existing.PSObject.Properties['reservationRecommendations']) { @($existing.reservationRecommendations) } else { @() }

    $moduleAvailable = [bool](Get-Command Invoke-AzCostManagementQuery -ErrorAction SilentlyContinue)

    $costResult = @()
    $finopsWarnings = @()
    $usedInventoryPass = $false
    if ($null -ne $FromInventory -and @($FromInventory).Count -gt 0) {
        $costResult = @($FromInventory)
        $usedInventoryPass = $true
        Write-Verbose "Import-ScoutCostInventory: reusing $($costResult.Count) subscription cost record(s) from the inventory pass -- no Azure call made."
    }
    elseif ($moduleAvailable) {
        if (-not (Get-Command Get-ScoutCostInventory -ErrorAction SilentlyContinue)) {
            try { . (Join-Path $PSScriptRoot '..' 'collect' 'Get-ScoutCostInventory.ps1') } catch { Write-Warning "Import-ScoutCostInventory: could not load Get-ScoutCostInventory: $($_.Exception.Message)" }
        }
        $subs = @(if ($Collect -and $Collect.PSObject.Properties['subscriptions'] -and $Collect.subscriptions) { $Collect.subscriptions } else { @() })
        if ($subs.Count -gt 0 -and (Get-Command Get-ScoutCostInventory -ErrorAction SilentlyContinue)) {
            try {
                # `if` blocks do not introduce a new PowerShell scope, so $costWarnings set here
                # via -WarningVariable is directly visible below without any script-scope hop.
                $costResult = @(Get-ScoutCostInventory -Subscriptions $subs -WarningVariable costWarnings -WarningAction SilentlyContinue)
                $finopsWarnings = @($costWarnings | ForEach-Object { [string]$_ })
            }
            catch {
                Write-Warning "Import-ScoutCostInventory: cost pull failed, treating as blocked rather than zero-spend: $($_.Exception.Message)"
                $costResult = @()
            }
        }
    }

    # ---- flatten into per-row evidence + detect blocked subscriptions ----
    # Row order [cost, usageDate, resourceType, resourceGroup, resourceLocation, serviceName,
    # currency] matches Get-ScoutCostAnomaly's own documented mapping for this exact shape --
    # keeping the same mapping here means the two never silently drift apart.
    $costRows = [System.Collections.Generic.List[object]]::new()
    $blockedSubscriptions = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $costResult) {
        if (-not $item) { continue }
        $subName = if ($item.PSObject.Properties['SubscriptionName']) { [string]$item.SubscriptionName } else { $null }
        $subId   = if ($item.PSObject.Properties['SubscriptionId'])   { [string]$item.SubscriptionId }   else { $null }
        $data    = if ($item.PSObject.Properties['CostData']) { $item.CostData } else { $null }
        # Wrapped around the WHOLE if/elseif/else, not around `$data.Row` inside each branch:
        # an if-block yields its body through the output stream, which ENUMERATES a collection
        # passing through it -- `$rows = if (...) { @($data.Row) }` would flatten the one-row
        # array `$data.Row` down to that row's own scalar elements, so `$rows.Count` reads 7 (the
        # row's fields) instead of 1 (one row). Same trap this codebase's Invoke-Collect.ps1
        # comments document repeatedly; found here by this feature's own unit test, not live.
        $rows = @(if ($data -and $data.PSObject.Properties['Row']) { $data.Row } elseif ($data) { $data } else { @() })

        if ($rows.Count -eq 0) {
            # Empty AND (module unavailable this whole pull, or this specific subscription
            # warned) reads as blocked, not "zero spend" -- AB#6826's sharp AC.
            $subWarned = -not $usedInventoryPass -and $subName -and @($finopsWarnings | Where-Object { $_ -match [regex]::Escape($subName) }).Count -gt 0
            if (-not $moduleAvailable -or $subWarned) { [void]$blockedSubscriptions.Add($(if ($subName) { $subName } else { $subId })) }
            continue
        }

        foreach ($row in $rows) {
            $r = @($row)
            if ($r.Count -lt 6) { continue }
            $cost = $null
            try { $cost = [double]$r[0] } catch { continue }
            $costRows.Add([pscustomobject]@{
                    SubscriptionId   = $subId
                    SubscriptionName = $subName
                    Cost             = $cost
                    UsageDate        = [string]$r[1]
                    ResourceType     = [string]$r[2]
                    ResourceGroup    = [string]$r[3]
                    ResourceLocation = [string]$r[4]
                    ServiceName      = [string]$r[5]
                    Currency         = if ($r.Count -gt 6) { [string]$r[6] } else { $null }
                })
        }
    }

    # `available`: the module resolved (or a combined-run pull already happened) AND it is
    # not the case that every queried subscription came back blocked. A tenant with zero
    # subscriptions is trivially "available" (nothing to block) -- an empty estate, not a
    # blocked one. Written as a plain if-chain, not a nested ternary, on purpose -- this is
    # the exact boolean the "blocked cost pull must never render as zero" AC hinges on, and a
    # misread ternary here would be the single most consequential bug in this file.
    $totalSubs = @($costResult).Count
    if (-not $moduleAvailable -and -not $usedInventoryPass) {
        $available = $false
    }
    elseif ($totalSubs -eq 0) {
        $available = $true
    }
    else {
        $available = $blockedSubscriptions.Count -lt $totalSubs
    }

    # ---- anomalies (AB#6826 -- wires Get-ScoutCostAnomaly into the collect pipeline for the
    # first time; it was tested but never called anywhere before this) ----
    $anomalies = @()
    if ($available -and $costResult.Count -gt 0) {
        try {
            if (-not (Get-Command Get-ScoutCostAnomaly -ErrorAction SilentlyContinue)) {
                . (Join-Path $PSScriptRoot '..' 'analyze' 'Get-ScoutCostAnomaly.ps1')
            }
            $anomalyResult = Get-ScoutCostAnomaly -CostData $costResult
            if ($anomalyResult -and $anomalyResult.HasData) { $anomalies = @($anomalyResult.Anomalies) }
        }
        catch {
            Write-Warning "Import-ScoutCostInventory: anomaly detection failed, continuing without it: $($_.Exception.Message)"
        }
    }

    $finops = [pscustomobject]@{
        available             = [bool]$available
        moduleAvailable       = [bool]$moduleAvailable
        costRows              = @($costRows)
        blockedSubscriptions  = @($blockedSubscriptions)
        anomalies             = @($anomalies)
        reservations          = @($reservations)
        reservationRecommendations = @($reservationRecommendations)
    }
    $Collect | Add-Member -NotePropertyName finops -NotePropertyValue $finops -Force
    return $Collect
}
