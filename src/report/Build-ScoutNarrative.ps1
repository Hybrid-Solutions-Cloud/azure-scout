#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Compose the assessment narrative — the prose an executive actually reads (AB#6854,
    Feature AB#6449, Epic AB#6450).

.DESCRIPTION
    THE PROBLEM THIS SOLVES, AND WHY A TEMPLATE CANNOT SOLVE IT.

    A per-rule template produces "1 of 3 scorable controls in this domain are satisfied."
    That is true, mechanical, and nobody reads it. The reference report attached to AB#6443
    writes:

        "The four-point gap to a top-band score is driven by operational governance and
         security hygiene, not by architecture. The principal drag-down factors are storage
         data-plane exposure (60 of 198 storage accounts with public network reach enabled)..."

    Decompose that and the difference is not vocabulary, it is that **every interesting
    sentence is comparative or aggregate**. "The four-point gap" compares current to target.
    "the highest of the seven" ranks a domain against its peers. "hygiene, not architecture"
    classifies the SHAPE of the failures. "60 of 198" is a proportion. None of those facts
    exist on any single rule — they are properties of the run as a whole.

    So this file does not template sentences. It derives a set of comparative facts about the
    run (Get-ScoutNarrativeFact), and composes prose from the facts that are actually true.
    A sentence whose supporting fact could not be derived is NOT emitted — never emitted with
    a placeholder, never emitted with a hedge. That is the same rule the rest of the report
    model follows, applied to prose, where it matters most: a report is judged on its
    sentences, and one confident sentence about something nobody measured discredits the
    other forty.

    WHAT IS DELIBERATELY NOT HERE. No sentence characterises business impact, regulatory
    exposure, or the customer's intent. Scout collected resource configuration; it did not
    interview anyone. "on a member-data platform" is a phrase a consultant earned by knowing
    the client, and generating it from a storage-account count would be fabrication.

.NOTES
    Tracks ADO Task AB#6854, beneath User Story AB#6443. Design:
    docs/design/reporting-engine-v2.md §4.2.
#>

#region Fact derivation

function Get-ScoutNarrativeFact {
    <#
    .SYNOPSIS
        Derive the comparative facts the narrative is composed from.

    .DESCRIPTION
        Each fact is either derivable from the run or absent. Absent facts suppress the
        sentences that depend on them rather than producing a hedged version of them.

    .OUTPUTS
        A pscustomobject whose properties are individually nullable.
    #>
    param($Model)

    $maturity = Get-ScoutModelProp $Model 'Maturity'
    $domains = @(Get-ScoutModelProp $maturity 'Domains' -Default @())
    $composite = Get-ScoutModelProp $maturity 'Composite'
    $gaps = @(Get-ScoutModelProp $Model 'GapRegister' -Default @())
    $assessed = @($domains | Where-Object { -not $_.NotAssessed -and $null -ne $_.Score })

    $strongest = $null; $weakest = $null; $spread = $null
    if ($assessed.Count -gt 0) {
        $ordered = @($assessed | Sort-Object Score)
        $weakest = $ordered[0]
        $strongest = $ordered[-1]
        $spread = $strongest.Score - $weakest.Score
    }

    # Concentration: do the failures sit in a handful of findings, or are they spread across
    # the estate? This is the fact behind "a hardening programme, not a re-architecture" —
    # a few high-blast-radius configuration gaps read very differently from many small ones.
    $totalAffected = 0
    foreach ($g in $gaps) { $totalAffected += [int](Get-ScoutModelProp $g 'EvidenceCount' -Default 0) }
    $topThree = @($gaps | Sort-Object { -1 * [int](Get-ScoutModelProp $_ 'EvidenceCount' -Default 0) } | Select-Object -First 3)
    $topThreeAffected = 0
    foreach ($g in $topThree) { $topThreeAffected += [int](Get-ScoutModelProp $g 'EvidenceCount' -Default 0) }
    $concentration = if ($totalAffected -gt 0) { [Math]::Round($topThreeAffected / $totalAffected * 100) } else { $null }

    # How many distinct subscriptions do the affected resources actually touch? "concentrated
    # in 3 of 101 subscriptions" and "estate-wide" are different remediation programmes.
    $subs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($g in $gaps) {
        foreach ($e in @(Get-ScoutModelProp $g 'Evidence' -Default @())) {
            $s = Get-ScoutModelProp $e 'SubscriptionId'
            if ($s) { [void]$subs.Add("$s") }
        }
    }

    $bySeverity = @{}
    foreach ($g in $gaps) {
        $s = "$(Get-ScoutModelProp $g 'Severity' -Default 'UNKNOWN')"
        if (-not $bySeverity.ContainsKey($s)) { $bySeverity[$s] = 0 }
        $bySeverity[$s]++
    }

    # Which domains carry the CRITICAL/HIGH weight — the "driven by X, not Y" fact.
    $severeByDomain = @{}
    foreach ($g in @($gaps | Where-Object { $_.Severity -in 'CRITICAL', 'HIGH' })) {
        $d = "$(Get-ScoutModelProp $g 'Domain')"
        if (-not $severeByDomain.ContainsKey($d)) { $severeByDomain[$d] = 0 }
        $severeByDomain[$d]++
    }
    $drivingDomains = @($severeByDomain.GetEnumerator() | Sort-Object { -1 * $_.Value } | Select-Object -First 2 |
        ForEach-Object { $_.Key })

    # Domains with no severe gaps at all — the "not by architecture" half of the contrast.
    $cleanDomains = @($assessed | Where-Object { -not $severeByDomain.ContainsKey("$($_.Domain)") } |
        Sort-Object { -1 * $_.Score } | ForEach-Object { $_.Domain })

    $largest = if ($topThree.Count -gt 0) { $topThree[0] } else { $null }

    return [pscustomobject]@{
        AssessedDomainCount    = $assessed.Count
        NotAssessedDomainCount = @($domains | Where-Object { $_.NotAssessed }).Count
        DomainCount            = $domains.Count
        StrongestDomain        = $strongest
        WeakestDomain          = $weakest
        ScoreSpread            = $spread
        CompositeScore         = Get-ScoutModelProp $composite 'Current'
        CompositeBand          = Get-ScoutModelProp $composite 'Band'
        CompositeTarget        = Get-ScoutModelProp $composite 'Target'
        CompositeGap           = Get-ScoutModelProp $composite 'Gap'
        GapCount               = $gaps.Count
        SevereGapCount         = @($gaps | Where-Object { $_.Severity -in 'CRITICAL', 'HIGH' }).Count
        SeverityBreakdown      = $bySeverity
        TotalAffectedResources = $totalAffected
        TopThreeGaps           = $topThree
        ConcentrationPercent   = $concentration
        AffectedSubscriptions  = $subs.Count
        InScopeSubscriptions   = [int](Get-ScoutModelProp (Get-ScoutModelProp $Model 'Scope') 'SubscriptionCount' -Default 0)
        DrivingDomains         = $drivingDomains
        CleanDomains           = $cleanDomains
        LargestGap             = $largest
        ManagedBandDomains     = @($assessed | Where-Object { $_.Score -ge 7 })
        DefinedOrBelowDomains  = @($assessed | Where-Object { $_.Score -lt 7 })
    }
}

#endregion

#region Composition helpers

function Join-ScoutList {
    <#
    .SYNOPSIS
        "a", "a and b", "a, b and c" — an Oxford-comma-free English list.
    #>
    param([string[]] $Items)
    $items = @($Items | Where-Object { $_ })
    if ($items.Count -eq 0) { return '' }
    if ($items.Count -eq 1) { return $items[0] }
    if ($items.Count -eq 2) { return "$($items[0]) and $($items[1])" }
    return (($items[0..($items.Count - 2)]) -join ', ') + ' and ' + $items[-1]
}

function Format-ScoutProportion {
    param([int] $Part, [int] $Whole)
    if ($Whole -le 0) { return "$Part" }
    return '{0:N0} of {1:N0}' -f $Part, $Whole
}

function Format-ScoutCount {
    <#
    .SYNOPSIS
        "1 resource" / "60 resources" — never "1 resource(s)".

    .NOTES
        Parenthesised plurals are the single clearest tell that a document was generated
        rather than written, and a reader who spots one starts discounting the analysis
        around it. Cheap to avoid, so it is not avoided by exception.
    #>
    param([int] $Count, [string] $Singular, [string] $Plural = $null)
    $noun = if ($Count -eq 1) { $Singular } elseif ($Plural) { $Plural } else { "${Singular}s" }
    return ('{0:N0} {1}' -f $Count, $noun)
}

function Get-ScoutVerb {
    <#
    .SYNOPSIS
        Subject-verb agreement for a count-led clause.
    #>
    param([int] $Count, [string] $Singular, [string] $Plural)
    if ($Count -eq 1) { return $Singular }
    return $Plural
}

#endregion

#region Executive narrative

function New-ScoutExecutiveNarrative {
    <#
    .SYNOPSIS
        The three paragraphs the executive summary leads with, each with a named lead.

    .OUTPUTS
        An array of { Lead, Text }. A paragraph whose supporting facts are absent is not
        emitted at all — the section renders shorter rather than vaguer.
    #>
    param($Model, $Facts = $null)

    $f = if ($Facts) { $Facts } else { Get-ScoutNarrativeFact -Model $Model }
    $paras = [System.Collections.Generic.List[object]]::new()

    # ---- 1. What is holding up ----
    if ($f.StrongestDomain -and $f.AssessedDomainCount -ge 2) {
        $s = [System.Text.StringBuilder]::new()
        [void]$s.Append("$($f.StrongestDomain.Domain) is the strongest of the $($f.AssessedDomainCount) domains that produced a scorable result, at $($f.StrongestDomain.Score) / 10 — the $($f.StrongestDomain.Band) band.")
        if ($f.ManagedBandDomains.Count -gt 1) {
            $names = @($f.ManagedBandDomains | Sort-Object { -1 * $_.Score } | ForEach-Object { "$($_.Domain) at $($_.Score)" })
            [void]$s.Append(" $($f.ManagedBandDomains.Count) domains sit at 7 / 10 or above — $(Join-ScoutList $names) — and need routine refinement rather than a programme.")
        }
        elseif ($f.CleanDomains.Count -gt 0) {
            # Agreement matters: a single-item list takes "carries". Prose that trips over its
            # own grammar reads as machine-generated regardless of how good the analysis is,
            # and the reader discounts the analysis with it.
            $verb = if ($f.CleanDomains.Count -eq 1) { 'carries' } else { 'carry' }
            [void]$s.Append(" $(Join-ScoutList $f.CleanDomains) $verb no critical or high-severity gaps at all.")
        }
        $paras.Add([pscustomobject]@{ Lead = 'Where the estate is sound'; Text = $s.ToString() })
    }

    # ---- 2. What is dragging it down, and what KIND of problem it is ----
    if ($f.GapCount -gt 0 -and $f.WeakestDomain) {
        $s = [System.Text.StringBuilder]::new()

        if ($null -ne $f.CompositeGap -and $f.CompositeGap -gt 0) {
            [void]$s.Append("The $($f.CompositeGap)-point gap to the target composite is concentrated, not diffuse.")
        }
        else {
            [void]$s.Append('The open findings are concentrated, not diffuse.')
        }

        if ($f.DrivingDomains.Count -gt 0) {
            $contrast = if ($f.CleanDomains.Count -gt 0) {
                " — driven by $(Join-ScoutList $f.DrivingDomains), not by $(Join-ScoutList @($f.CleanDomains | Select-Object -First 2))"
            } else {
                " — driven by $(Join-ScoutList $f.DrivingDomains)"
            }
            [void]$s.Append(" $($f.SevereGapCount) of the $($f.GapCount) open gaps are critical or high severity$contrast.")
        }

        if ($f.LargestGap -and [int]$f.LargestGap.EvidenceCount -gt 0) {
            [void]$s.Append(" The single largest blast radius is '$($f.LargestGap.Title)', affecting $(Format-ScoutCount ([int]$f.LargestGap.EvidenceCount) 'resource').")
        }

        if ($null -ne $f.ConcentrationPercent -and $f.GapCount -ge 4) {
            [void]$s.Append(" The three largest findings account for $($f.ConcentrationPercent)% of all affected resources, so a small number of changes moves most of the number.")
        }

        if ($f.AffectedSubscriptions -gt 0 -and $f.InScopeSubscriptions -gt 0) {
            [void]$s.Append(" Affected resources sit in $(Format-ScoutProportion $f.AffectedSubscriptions $f.InScopeSubscriptions) in-scope subscriptions.")
        }

        $paras.Add([pscustomobject]@{ Lead = 'What is driving the score down'; Text = $s.ToString() })
    }

    # ---- 3. How to read the number ----
    if ($null -ne $f.CompositeScore) {
        $s = [System.Text.StringBuilder]::new()
        [void]$s.Append("On the maturity rubric (1-2 Initial, 3-4 Emerging, 5-6 Defined, 7-8 Managed, 9-10 Optimised), a composite of $($f.CompositeScore) / 10 places the assessed scope in the $($f.CompositeBand) band.")
        if ($f.ManagedBandDomains.Count -gt 0 -and $f.DefinedOrBelowDomains.Count -gt 0) {
            $isAre = if ($f.ManagedBandDomains.Count -eq 1) { 'domain is' } else { 'domains are' }
            $remIs = if ($f.DefinedOrBelowDomains.Count -eq 1) { 'is' } else { 'are' }
            [void]$s.Append(" $($f.ManagedBandDomains.Count) $isAre already at Managed or better; the remaining $($f.DefinedOrBelowDomains.Count) $remIs where the lift concentrates.")
        }
        if ($null -ne $f.ScoreSpread -and $f.ScoreSpread -ge 3) {
            [void]$s.Append(" The $($f.ScoreSpread)-point spread between $($f.StrongestDomain.Domain) and $($f.WeakestDomain.Domain) is wide enough that the composite alone understates both: read the per-domain figures.")
        }
        if ($f.NotAssessedDomainCount -gt 0) {
            # Never softened. A composite computed over a subset must say so in the same
            # breath it is quoted, or the reader takes it as covering everything.
            [void]$s.Append(" $($f.NotAssessedDomainCount) of the $($f.DomainCount) domains collected no automated evidence and are excluded from this figure entirely — they are not scored as zero, and the composite says nothing about them.")
        }
        $paras.Add([pscustomobject]@{ Lead = 'Reading the score'; Text = $s.ToString() })
    }

    # A run where nothing was assessed gets one honest paragraph rather than three empty ones.
    if ($paras.Count -eq 0) {
        $paras.Add([pscustomobject]@{
                Lead = 'No assessable result'
                Text = 'This run produced no scorable result in any domain. No maturity position, ranking or remediation priority can be stated from it. The coverage section below records what was collected and what was not.'
            })
    }

    return , $paras.ToArray()
}

#endregion

#region Domain narrative

function New-ScoutDomainNarrative {
    <#
    .SYNOPSIS
        The 'Current state' prose for one domain chapter.

    .DESCRIPTION
        Composed from the domain's own counts plus its position relative to the other domains —
        the ranking is what makes it read as an assessment rather than a tally.
    #>
    param($Domain, $Model, $Facts = $null)

    $f = if ($Facts) { $Facts } else { Get-ScoutNarrativeFact -Model $Model }

    if ($Domain.NotAssessed) {
        return ('No automated evidence was collected for this domain in this run, so no current state can be described and no score can be claimed. ' +
            'This is a coverage gap, not a pass and not a failure, and it is excluded from the composite rather than counted as a zero.')
    }

    $gaps = @(@(Get-ScoutModelProp $Model 'GapRegister' -Default @()) | Where-Object { "$($_.Domain)" -eq "$($Domain.Domain)" })
    $severe = @($gaps | Where-Object { $_.Severity -in 'CRITICAL', 'HIGH' })
    $scorable = [int]$Domain.Pass + [int]$Domain.Partial + [int]$Domain.Fail

    $s = [System.Text.StringBuilder]::new()

    # Opening claim: the score, and where it sits against its peers.
    [void]$s.Append("This domain scores $($Domain.Score) / 10 — the $($Domain.Band) band")
    if ($f.AssessedDomainCount -ge 2 -and $f.StrongestDomain -and $f.WeakestDomain) {
        if ("$($Domain.Domain)" -eq "$($f.StrongestDomain.Domain)") {
            [void]$s.Append(", the highest of the $($f.AssessedDomainCount) assessed domains")
        }
        elseif ("$($Domain.Domain)" -eq "$($f.WeakestDomain.Domain)") {
            [void]$s.Append(", the lowest of the $($f.AssessedDomainCount) assessed domains")
        }
    }
    [void]$s.Append('. ')

    # The evidence behind it.
    if ($scorable -gt 0) {
        $pass = [int]$Domain.Pass
        $controls = Get-ScoutVerb -Count $scorable -Singular 'control is' -Plural 'controls are'
        [void]$s.Append("$(Format-ScoutProportion $pass $scorable) scorable $controls satisfied")
        if ([int]$Domain.Partial -gt 0) { [void]$s.Append(", $([int]$Domain.Partial) partially") }
        if ([int]$Domain.Fail -gt 0) {
            $isAre = Get-ScoutVerb -Count ([int]$Domain.Fail) -Singular 'is' -Plural 'are'
            [void]$s.Append(", and $([int]$Domain.Fail) $isAre not")
        }
        [void]$s.Append('. ')
    }

    # What that means in resources, not rules — the translation a reader actually needs.
    if ($gaps.Count -gt 0) {
        $affected = 0
        foreach ($g in $gaps) { $affected += [int](Get-ScoutModelProp $g 'EvidenceCount' -Default 0) }
        if ($affected -gt 0) {
            $subject = Get-ScoutVerb -Count $gaps.Count -Singular 'That finding touches' -Plural 'Those findings touch'
            [void]$s.Append("$subject $(Format-ScoutCount $affected 'resource') in scope. ")
        }
        if ($severe.Count -gt 0) {
            $titles = @($severe | Sort-Object { -1 * [int]$_.EvidenceCount } | Select-Object -First 2 |
                ForEach-Object { "$($_.Title) ($('{0:N0}' -f [int]$_.EvidenceCount) affected)" })
            $isAre = Get-ScoutVerb -Count $severe.Count -Singular 'is' -Plural 'are'
            [void]$s.Append("$($severe.Count) $isAre critical or high severity, led by $(Join-ScoutList $titles). ")
        }
        else {
            [void]$s.Append('None is critical or high severity, so this domain is a refinement rather than a remediation priority. ')
        }
    }
    else {
        [void]$s.Append('There are no open gaps in this domain. ')
    }

    # Controls excluded from the score, stated rather than quietly dropped.
    $manual = [int]$Domain.Manual
    $noData = [int]$Domain.Unknown + [int]$Domain.Error
    $excluded = $manual + $noData
    if ($excluded -gt 0) {
        $couldNot = Get-ScoutVerb -Count $excluded -Singular 'control could' -Plural 'controls could'
        [void]$s.Append("A further $excluded $couldNot not be scored automatically")
        $clauses = [System.Collections.Generic.List[string]]::new()
        if ($manual -gt 0) {
            $needs = Get-ScoutVerb -Count $manual -Singular 'needs' -Plural 'need'
            $clauses.Add("$manual $needs manual confirmation")
        }
        if ($noData -gt 0) {
            $returned = Get-ScoutVerb -Count $noData -Singular 'returned' -Plural 'returned'
            $clauses.Add("$noData $returned no usable data")
        }
        if ($clauses.Count -gt 0) { [void]$s.Append(" — $(Join-ScoutList $clauses.ToArray())") }
        $areIs = Get-ScoutVerb -Count $excluded -Singular 'it is' -Plural 'they are'
        [void]$s.Append(" — so $areIs excluded from the score above rather than counted as failures.")
    }

    return $s.ToString().Trim()
}

#endregion

function Add-ScoutNarrativeToModel {
    <#
    .SYNOPSIS
        Attach the composed narrative to a report model, in place.

    .NOTES
        Called by Build-ScoutReportModel after the domains and gap register exist, because
        every sentence here is derived from them. Never fatal: a narrative failure degrades
        the report to its tables, which is the pre-v2 behaviour, rather than losing the run.
    #>
    param($Model)

    try {
        $facts = Get-ScoutNarrativeFact -Model $Model
        $exec = New-ScoutExecutiveNarrative -Model $Model -Facts $facts

        foreach ($d in @(Get-ScoutModelProp (Get-ScoutModelProp $Model 'Maturity') 'Domains' -Default @())) {
            $text = New-ScoutDomainNarrative -Domain $d -Model $Model -Facts $facts
            $d.CurrentState = $text
        }

        $Model | Add-Member -NotePropertyName 'Narrative' -NotePropertyValue ([pscustomobject]@{
                Executive = $exec
                Facts     = $facts
            }) -Force
    }
    catch {
        Write-Warning "Add-ScoutNarrativeToModel: narrative composition skipped ($($_.Exception.Message)) -- the report renders its tables without prose."
    }
    return $Model
}
