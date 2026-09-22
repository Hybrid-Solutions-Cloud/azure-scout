#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Emit star-schema CSVs and copy the .pbit template bound to them.

.NOTES
    Tracks ADO Story AB#5046. AB#6860 (Feature AB#6449, Epic AB#6450) extended the model with
    a fact table at RESOURCE grain plus the dimensions needed to slice it.

    Before that extension the star schema carried four tables joined on AreaKey and never
    exported evidence at all, so the one question a Power BI consumer actually wants to ask —
    "which subscriptions carry the most open findings, and what should each owner do first" —
    could not be asked of it. fact_evidence answers it; dim_subscription, dim_domain,
    dim_severity and dim_roadmap_phase are what make it sliceable.

    The four original tables and the AreaKey join are unchanged, so an existing report bound to
    this folder keeps working.
#>
function Export-PowerBi {
    param($Findings, $Collect, [string] $OutputPath, $Model = $null)
    $pbiDir = Join-Path $OutputPath 'powerbi'
    New-Item -ItemType Directory -Path $pbiDir -Force | Out-Null

    # Emit a normalized AreaKey (lowercased, trimmed "framework|area") into both
    # the area and findings tables so the Power BI relationship binds on a stable
    # key instead of fragile raw-text (Framework, Area) equality (AB#5092).
    function New-AreaKey($fw, $ar) { ("{0}|{1}" -f $fw, $ar).ToLower().Trim() }

    # $Findings.Areas/.Frameworks/.Gaps/.Findings dot directly into a possibly-
    # $null $Findings (e.g. a standalone re-render from a hand-edited/partial
    # findings.json) -- $null.Areas throws PropertyNotFoundException under
    # Set-StrictMode -Version Latest rather than returning $null, unlike every
    # other renderer in this folder (which all read through a Get-Scout*Prop
    # helper for exactly this reason). @() degrades to empty CSVs, not a crash.
    function Get-ScoutPowerBiProp {
        param($Obj, [Parameter(Mandatory)][string] $Name)
        if ($null -eq $Obj) { return @() }
        $prop = $Obj.PSObject.Properties[$Name]
        if ($prop) { return @($prop.Value) } else { return @() }
    }

    (Get-ScoutPowerBiProp $Findings 'Areas') | Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, * |
        Export-Csv "$pbiDir/fact_area_scores.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Frameworks') | Export-Csv "$pbiDir/fact_framework.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Gaps') | Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, * |
        Export-Csv "$pbiDir/dim_gaps.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Findings') |
        Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, Id, Framework, Area, Severity, Status, EvidenceCount, Title, Remediation, Manual |
        Export-Csv "$pbiDir/fact_findings.csv" -NoTypeInformation

    # ---- AB#6860: resource-grain fact + its dimensions ----
    # Optional, exactly as in every other renderer: without a model the four tables above are
    # still emitted and the .pbit still binds them, so a caller re-rendering a hand-edited
    # findings.json is not broken by this addition.
    $reportModel = $Model
    if (-not $reportModel -and (Get-Command Build-ScoutReportModel -ErrorAction SilentlyContinue)) {
        try { $reportModel = Build-ScoutReportModel -Findings $Findings -Collect $Collect }
        catch { Write-Warning "Export-PowerBi: could not build the report model ($($_.Exception.Message)) -- emitting the base star schema only." }
    }

    if ($reportModel) {
        $gaps = @(Get-ScoutPowerBiProp $reportModel 'GapRegister')

        # One row per affected resource. The Verdict column travels with it, and so does
        # VerdictSource -- a consumer filtering on "Real - investigate" has to be able to see
        # that the classification was heuristic, or the filter quietly becomes a claim.
        $evidenceRows = foreach ($g in $gaps) {
            foreach ($e in @(Get-ScoutPowerBiProp $g 'Evidence')) {
                [pscustomobject]@{
                    GapId            = $g.GapId
                    RuleId           = $e.RuleId
                    Domain           = $g.Domain
                    Severity         = $g.Severity
                    Phase            = $g.Phase
                    Owner            = $g.Owner
                    SubscriptionId   = $e.SubscriptionId
                    SubscriptionName = $e.SubscriptionName
                    ResourceGroup    = $e.ResourceGroup
                    ResourceName     = $e.ResourceName
                    ResourceId       = $e.ResourceId
                    ResourceType     = $e.ResourceType
                    Location         = $e.Location
                    Verdict          = $e.Verdict
                    VerdictSource    = $e.VerdictSource
                }
            }
        }
        @($evidenceRows) | Export-Csv "$pbiDir/fact_evidence.csv" -NoTypeInformation

        # dim_gap_register carries the columns fact_evidence deliberately does not repeat:
        # the observed total (which is NOT the row count of fact_evidence when evidence was
        # truncated), the target state, and the closure action.
        @($gaps | Select-Object GapId, RuleId, Framework, Domain, Title, Severity, EvidenceCount,
            EvidenceShown, EvidenceTruncated, TargetState, ClosureAction, Owner, Effort, Phase |
            ForEach-Object { $_ }) | Export-Csv "$pbiDir/dim_gap_register.csv" -NoTypeInformation

        @(Get-ScoutPowerBiProp (Get-ScoutPowerBiProp $reportModel 'Scope' | Select-Object -First 1) 'Subscriptions') |
            Export-Csv "$pbiDir/dim_subscription.csv" -NoTypeInformation

        @(Get-ScoutPowerBiProp (Get-ScoutPowerBiProp $reportModel 'Maturity' | Select-Object -First 1) 'Domains') |
            Select-Object Framework, Domain, Score, Band, NotAssessed, PercentScore, Pass, Partial, Fail, Manual, Unknown, Error |
            Export-Csv "$pbiDir/dim_domain.csv" -NoTypeInformation

        # A fixed severity dimension with an explicit sort order, so a Power BI axis orders
        # CRITICAL before LOW instead of alphabetically. UNKNOWN sorts last, never first
        # (the same AB#5089 rule the gap list follows).
        @(
            [pscustomobject]@{ Severity = 'CRITICAL'; SortOrder = 1 }
            [pscustomobject]@{ Severity = 'HIGH'; SortOrder = 2 }
            [pscustomobject]@{ Severity = 'MEDIUM'; SortOrder = 3 }
            [pscustomobject]@{ Severity = 'LOW'; SortOrder = 4 }
            [pscustomobject]@{ Severity = 'GOOD'; SortOrder = 5 }
            [pscustomobject]@{ Severity = 'UNKNOWN'; SortOrder = 99 }
        ) | Export-Csv "$pbiDir/dim_severity.csv" -NoTypeInformation

        @(Get-ScoutPowerBiProp (Get-ScoutPowerBiProp $reportModel 'Roadmap' | Select-Object -First 1) 'Phases') |
            Select-Object Phase, Name, DayRange, @{ n = 'ItemCount'; e = { @($_.Items).Count } } |
            Export-Csv "$pbiDir/dim_roadmap_phase.csv" -NoTypeInformation
    }

    # Generate the Power BI Template (.pbit) bound to the star-schema CSVs above.
    # Uses the schema-agnostic generator (New-AZSCPowerBITemplate), which builds the
    # DataModelSchema and Power Query (M) directly from the CSV headers — so there is
    # no static template to maintain or check in (AB#5046). Failure is non-fatal: the
    # CSVs + README still let a user import the star schema by hand.
    $pbitPath = Join-Path $pbiDir 'report.pbit'
    $pbitMade = $false
    try {
        if (-not (Get-Command -Name New-AZSCPowerBITemplate -ErrorAction SilentlyContinue)) {
            # AB#5662: New-AZSCPowerBITemplate.ps1 moved from Modules/Private/Reporting to
            # src/report/renderers/inventory as part of the reporting-layer consolidation.
            . "$PSScriptRoot/inventory/New-AZSCPowerBITemplate.ps1"
        }
        New-AZSCPowerBITemplate -PowerBIDir $pbiDir -OutputFile $pbitPath | Out-Null
        $pbitMade = Test-Path $pbitPath
    }
    catch {
        Write-Warning ("Power BI .pbit generation skipped: {0}. The star-schema CSVs and README below are still available for manual import." -f $_.Exception.Message)
    }

    $pbitLine = if ($pbitMade) {
        "Open report.pbit in Power BI Desktop and click Refresh when prompted (the model was built from a snapshot)."
    } else {
        "No report.pbit was generated; import the CSVs below manually in Power BI Desktop."
    }
    @"
$pbitLine
If the CSV folder has moved, re-point the FolderPath parameter to:
  $pbiDir
The model is a star schema: fact_findings + dim_gaps + fact_area_scores + fact_framework, joined on AreaKey.

When a report model was available this folder also contains a resource-grain fact and its
dimensions (AB#6860):
  fact_evidence      one row per affected resource, with its subscription, resource group,
                     resource id and triage Verdict. VerdictSource is always 'heuristic' --
                     the verdict sorts the list, it does not confirm it.
  dim_gap_register   one row per gap: the observed total (NOT the fact_evidence row count when
                     evidence was truncated), target state, closure action, owner, effort, phase.
  dim_subscription   join fact_evidence[SubscriptionId] -> dim_subscription[Id]
  dim_domain         join on Domain; carries Score, Band and NotAssessed
  dim_severity       carries SortOrder so an axis orders CRITICAL before LOW, not alphabetically
  dim_roadmap_phase  join on Phase

Counting rows of fact_evidence gives affected RESOURCES. For affected totals use
dim_gap_register[EvidenceCount] -- where EvidenceTruncated is true, fact_evidence holds only
the first EvidenceShown of them.
"@ | Out-File "$pbiDir/README.txt"
}
