#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Emit the raw evidence pack: one sheet per area, all findings. Retained tier.
    Also emits a small set of visual dashboard tabs (native Excel PivotTables +
    PivotCharts) summarizing the same findings/collect data before the raw
    per-area sheets.

.NOTES
    Uses ImportExcel if available; falls back to CSV-per-area. Tracks ADO Story AB#5049.

    Dashboard tabs (AB#322): Findings-by-Severity, Score-by-Area, Pass-Fail-Manual
    and Resource-Counts. Built with ImportExcel's -PivotTableName/-PivotRows/
    -PivotData/-IncludePivotChart/-PivotChartType — the same module this file
    already depends on for the evidence sheets, so no new dependency is added.

    Each dashboard is backed by a small hidden staging worksheet (the pivot
    cache's source range) plus a visible worksheet holding the PivotTable and
    PivotChart, generated with ImportExcel/EPPlus's refreshOnLoad="1" pivot
    cache flag. KNOWN LIMITATION: because there is no Excel host running in
    this (or most CI/headless) environments, the PivotTable's cells are written
    without pre-computed values -- Excel computes and displays them the moment
    the workbook is opened (refreshOnLoad triggers an automatic refresh). This
    is inherent to any headless-generated OOXML PivotTable, not a defect in
    this renderer; a byte/zip-level check confirms the pivot cache, pivot
    table and chart parts are present and well-formed, and Excel itself
    renders them correctly once opened.

    A dashboard tab is only created when its underlying data actually has at
    least one row to summarize (e.g. no Resource-Counts tab when -Collect is
    $null or has no countable arrays) -- no empty dashboards.
#>

# Safe nested/optional property access -- $Findings/$Collect may be plain
# deserialized PSCustomObjects missing keys the dashboards don't require, and
# Set-StrictMode -Version Latest throws on a missing-property dot-access.
# Named distinctly from every other renderer's identically-purposed helper
# (Export-Pptx's Get-ScoutProp, Export-Pdf's Get-ScoutPdfProp, etc.) because
# every renderer file is dot-sourced into the same session (AB#5045's
# Export-Report dispatcher) and same-named function definitions would collide.
function Get-ScoutExcelProp {
    param($Obj, [Parameter(Mandatory)][string] $Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value } else { return $Default }
}

<#
.SYNOPSIS
    Flatten the raw Collect object into {Category, ResourceType, Label, Count}
    rows for the Resource-Counts dashboard -- no invented data, just a count of
    whatever arrays are actually present under each top-level collect category.
#>
function Get-ScoutExcelResourceCount {
    param($Collect)
    $rows = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Collect) { return $rows.ToArray() }

    foreach ($catProp in $Collect.PSObject.Properties) {
        if ($catProp.Name -eq '_meta') { continue }
        $catVal = $catProp.Value
        if ($null -eq $catVal) { continue }

        if ($catVal -is [System.Collections.IEnumerable] -and $catVal -isnot [string]) {
            # Top-level category is itself a resource array (e.g. subscriptions).
            $count = @($catVal).Count
            if ($count -gt 0) {
                $rows.Add([pscustomobject]@{
                        Category     = $catProp.Name
                        ResourceType = $catProp.Name
                        Label        = $catProp.Name
                        Count        = $count
                    })
            }
            continue
        }

        if ($catVal -is [System.Management.Automation.PSCustomObject]) {
            foreach ($subProp in $catVal.PSObject.Properties) {
                $subVal = $subProp.Value
                if ($null -eq $subVal) { continue }
                if ($subVal -is [System.Collections.IEnumerable] -and $subVal -isnot [string]) {
                    $count = @($subVal).Count
                    if ($count -gt 0) {
                        $rows.Add([pscustomobject]@{
                                Category     = $catProp.Name
                                ResourceType = $subProp.Name
                                Label        = "$($catProp.Name)/$($subProp.Name)"
                                Count        = $count
                            })
                    }
                }
            }
        }
    }
    return $rows.ToArray()
}

<#
.SYNOPSIS
    Build one dashboard tab: write $Rows to a hidden staging sheet, then add a
    native PivotTable + PivotChart worksheet named $SheetName on top of it.
    No-op (returns $false) when $Rows is empty -- callers rely on this to skip
    dashboards with no underlying data.
#>
function Add-ScoutExcelPivotDashboard {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $SheetName,
        [Parameter(Mandatory)][string] $SourceSheetName,
        [AllowEmptyCollection()][array] $Rows,
        [Parameter(Mandatory)][string] $PivotRowField,
        [Parameter(Mandatory)][hashtable] $PivotDataFields,
        [Parameter(Mandatory)][string] $PivotChartType,
        [switch] $Activate
    )
    if (-not $Rows -or @($Rows).Count -eq 0) { return $false }

    # Module-qualified (ImportExcel\Export-Excel), not the bare cmdlet name: this
    # file's own top-level function is also named Export-Excel, and depending on
    # the scope this file was dot-sourced into (e.g. a Pester BeforeAll's scope
    # sits closer than global), a bare call here can resolve back to our own
    # function instead of ImportExcel's cmdlet and recurse. Module-qualifying is
    # unambiguous regardless of scope/import order.
    $Rows | ImportExcel\Export-Excel -Path $Path -WorksheetName $SourceSheetName -AutoSize

    $pivotParams = @{
        Path              = $Path
        WorksheetName     = $SourceSheetName
        Append            = $true
        PivotTableName    = $SheetName
        PivotRows         = $PivotRowField
        PivotData         = $PivotDataFields
        IncludePivotChart = $true
        PivotChartType    = $PivotChartType
        HideSheet         = $SourceSheetName
    }
    if ($Activate) { $pivotParams.Activate = $true }
    ImportExcel\Export-Excel @pivotParams
    return $true
}

<#
.SYNOPSIS
    Add the AB#322 visual dashboard tabs (Findings-by-Severity, Score-by-Area,
    Pass-Fail-Manual, Resource-Counts) to $Path, ahead of the raw per-area
    evidence sheets Export-Excel appends afterwards. This workbook has no
    separate summary/overview sheet of its own (it's the raw evidence pack),
    so the dashboards -- rather than a pre-existing overview tab -- are the
    first visible content; every raw per-area sheet the caller appends next
    lands after them.
#>
function Add-ScoutExcelDashboard {
    param($Findings, $Collect, [string] $Path)

    $allFindings = @(Get-ScoutExcelProp -Obj $Findings -Name 'Findings' -Default @())
    $areas = @(Get-ScoutExcelProp -Obj $Findings -Name 'Areas' -Default @())
    $dashboardSheets = [System.Collections.Generic.List[string]]::new()

    # Findings-by-Severity: count of findings per severity (Pie).
    $severityRows = @($allFindings | Where-Object { $_.Severity } |
            Select-Object Id, Severity)
    if (Add-ScoutExcelPivotDashboard -Path $Path -SheetName 'Findings-by-Severity' `
            -SourceSheetName '_dash_src_severity' -Rows $severityRows `
            -PivotRowField 'Severity' -PivotDataFields @{ Id = 'Count' } `
            -PivotChartType 'Pie' -Activate) {
        $dashboardSheets.Add('Findings-by-Severity')
    }

    # Score-by-Area: per-area compliance score (ColumnClustered).
    $scoreRows = @($areas | Where-Object { $null -ne $_.Score } | ForEach-Object {
            [pscustomobject]@{ Label = "$($_.Framework) - $($_.Area)"; Score = $_.Score }
        })
    if (Add-ScoutExcelPivotDashboard -Path $Path -SheetName 'Score-by-Area' `
            -SourceSheetName '_dash_src_area_score' -Rows $scoreRows `
            -PivotRowField 'Label' -PivotDataFields @{ Score = 'Average' } `
            -PivotChartType 'ColumnClustered') {
        $dashboardSheets.Add('Score-by-Area')
    }

    # Pass-Fail-Manual: per-area rule-outcome breakdown (ColumnStacked).
    $passFailRows = @($areas | ForEach-Object {
            [pscustomobject]@{
                Label  = "$($_.Framework) - $($_.Area)"
                Pass   = $_.Pass
                Fail   = $_.Fail
                Manual = $_.Manual
            }
        })
    if (Add-ScoutExcelPivotDashboard -Path $Path -SheetName 'Pass-Fail-Manual' `
            -SourceSheetName '_dash_src_pass_fail_manual' -Rows $passFailRows `
            -PivotRowField 'Label' -PivotDataFields @{ Pass = 'Sum'; Fail = 'Sum'; Manual = 'Sum' } `
            -PivotChartType 'ColumnStacked') {
        $dashboardSheets.Add('Pass-Fail-Manual')
    }

    # Resource-Counts: collected resource inventory by type (BarClustered).
    $resourceRows = @(Get-ScoutExcelResourceCount $Collect)
    if (Add-ScoutExcelPivotDashboard -Path $Path -SheetName 'Resource-Counts' `
            -SourceSheetName '_dash_src_resource_counts' -Rows $resourceRows `
            -PivotRowField 'Label' -PivotDataFields @{ Count = 'Sum' } `
            -PivotChartType 'BarClustered') {
        $dashboardSheets.Add('Resource-Counts')
    }

    if ($dashboardSheets.Count -eq 0) { return }

    # Single consistent tab color across every dashboard sheet so they read as
    # one visual group, distinct from the plain (uncolored) per-area evidence
    # sheets appended after them.
    $pkg = Open-ExcelPackage -Path $Path
    try {
        foreach ($name in $dashboardSheets) {
            $ws = $pkg.Workbook.Worksheets[$name]
            if ($ws) { $ws.TabColor = [System.Drawing.Color]::FromArgb(0x1F, 0x6F, 0xE8) }
        }
    }
    finally {
        Close-ExcelPackage $pkg
    }
}

#region v2 gap-inventory workbook (AB#6857 — Cover, legend, contents index, per-gap tabs)

<#
    The reference workbook attached to AB#6443 is only useful because of two things the v1
    export has neither of:

      1. A Cover tab carrying the scope, the source, the classification, a four-value VERDICT
         LEGEND, and a contents index naming every tab with its record count.
      2. A per-row Verdict on every gap tab. That column is what turns "149 non-group Owner
         assignments" into "141 deliberate vending service principals plus 8 humans". Without
         it a raw count is noise, and a workbook of raw counts gets closed.

    Scout's verdicts are heuristic and the Cover says so in the legend. They sort the list so
    a human triages the interesting rows first; they do not stand in for that human.
#>

function Add-ScoutExcelCoverSheet {
    param($Model, [string] $Path)

    $meta = Get-ScoutExcelProp -Obj $Model -Name 'Meta'
    $eng = Get-ScoutExcelProp -Obj $Model -Name 'Engagement'
    $scope = Get-ScoutExcelProp -Obj $Model -Name 'Scope'
    $coverage = Get-ScoutExcelProp -Obj $Model -Name 'Coverage'
    $gaps = @(Get-ScoutExcelProp -Obj $Model -Name 'GapRegister' -Default @())

    $rows = [System.Collections.Generic.List[object]]::new()
    function Add-Row([string]$a, [string]$b) { $rows.Add([pscustomobject]@{ Item = $a; Value = $b }) }

    Add-Row 'Azure Scout — Gap Inventory Workbook' ''
    Add-Row 'Companion to' 'the assessment report generated in the same run'
    Add-Row 'Generated' "$(Get-ScoutExcelProp -Obj $meta -Name 'GeneratedOn' -Default '(unknown)')"
    Add-Row 'Run ID' "$(Get-ScoutExcelProp -Obj $meta -Name 'RunId' -Default '(not recorded)')"
    Add-Row 'Tenant' "$(Get-ScoutExcelProp -Obj $eng -Name 'TenantId' -Default '(not recorded)')"
    Add-Row 'Scope' "$(Get-ScoutExcelProp -Obj $meta -Name 'Scope' -Default '(not recorded)')"
    Add-Row 'Management group' "$(Get-ScoutExcelProp -Obj $meta -Name 'ManagementGroupId' -Default '(tenant root / not specified)')"
    Add-Row 'In-scope subscriptions' "$(Get-ScoutExcelProp -Obj $scope -Name 'SubscriptionCount' -Default 0)"
    Add-Row 'Source' 'Azure Scout collect.json — read-only ARM, Resource Graph and Microsoft Graph queries. No tenant state was modified.'
    Add-Row 'Classification' "$(Get-ScoutExcelProp -Obj $eng -Name 'Classification' -Default 'CONFIDENTIAL')"
    Add-Row '' ''

    Add-Row 'VERDICT LEGEND' 'Every row on every gap tab carries one of these four values'
    Add-Row 'Real - investigate' 'Genuine in-scope concern; requires engineering review or remediation.'
    Add-Row 'Platform-required - deliberate pattern' 'By design — Azure-managed resource groups, landing-zone vending service principals, platform-deployed identities.'
    Add-Row 'Sandbox - out of scope by design' 'Sandbox, vending-test or test-harness placement, exempt from production guard-rails by design.'
    Add-Row 'Inherited from legacy' 'Sits outside the in-scope landing zones; likely to disappear as the legacy estate is decommissioned.'
    Add-Row 'HOW TO READ THE VERDICT' 'Scout assigns it heuristically from resource naming and placement, to sort the list. It is NOT a confirmed judgement — every row still needs review by someone who knows the estate.'
    Add-Row '' ''

    Add-Row 'COVERAGE' ''
    Add-Row 'Open gaps' "$($gaps.Count)"
    Add-Row 'Domains assessed' "$(Get-ScoutExcelProp -Obj $coverage -Name 'AssessedDomains' -Default 0)"
    Add-Row 'Domains NOT assessed' "$(Get-ScoutExcelProp -Obj $coverage -Name 'NotAssessedDomains' -Default 0) — no automated evidence collected; neither a pass nor a failure is claimed"
    Add-Row 'Controls requiring manual review' "$(Get-ScoutExcelProp -Obj $coverage -Name 'ManualReviewItems' -Default 0)"
    Add-Row 'Controls that returned no data' "$(Get-ScoutExcelProp -Obj $coverage -Name 'NotAssessedItems' -Default 0)"
    Add-Row '' ''

    Add-Row 'CONTENTS' 'Tab | records | verdict mix'
    foreach ($g in $gaps) {
        $ev = @(Get-ScoutExcelProp -Obj $g -Name 'Evidence' -Default @())
        $mix = if ($ev.Count -eq 0) { 'no resource-level evidence retained' }
        else {
            (($ev | Group-Object Verdict | Sort-Object { -1 * $_.Count } |
                    ForEach-Object { "$($_.Count) $($_.Name)" }) -join '; ')
        }
        # The record count is the RETAINED rows, and where evidence was truncated the affected
        # total is larger. Saying both here stops the index from reading as a total.
        $count = if ($g.EvidenceTruncated) { "$($ev.Count) of $($g.EvidenceCount) affected" } else { "$($ev.Count)" }
        Add-Row "$($g.GapId) — $($g.Domain)" "$count | $mix"
    }

    $rows | ImportExcel\Export-Excel -Path $Path -WorksheetName 'Cover' -AutoSize
}

function Add-ScoutExcelGapSheets {
    param($Model, [string] $Path)

    $gaps = @(Get-ScoutExcelProp -Obj $Model -Name 'GapRegister' -Default @())

    # One consolidated register tab first — the single view the reference workbook's reader
    # opens after the cover.
    $registerRows = foreach ($g in $gaps) {
        [pscustomobject]@{
            GapId             = $g.GapId
            Domain            = $g.Domain
            RuleId            = $g.RuleId
            Finding           = $g.Title
            Severity          = $g.Severity
            AffectedTotal     = $g.EvidenceCount
            RowsRetained      = @(Get-ScoutExcelProp -Obj $g -Name 'Evidence' -Default @()).Count
            EvidenceTruncated = $g.EvidenceTruncated
            TargetState       = $g.TargetState
            ClosureAction     = $g.ClosureAction
            Owner             = $g.Owner
            Effort            = $g.Effort
            Phase             = $g.Phase
        }
    }
    if (@($registerRows).Count -gt 0) {
        @($registerRows) | ImportExcel\Export-Excel -Path $Path -WorksheetName 'Gap_Register' -AutoSize -FreezeTopRow -AutoFilter
    }

    # Then one tab per gap that actually has resource-level evidence behind it.
    $used = @{}
    foreach ($g in $gaps) {
        $ev = @(Get-ScoutExcelProp -Obj $g -Name 'Evidence' -Default @())
        if ($ev.Count -eq 0) { continue }

        # Excel worksheet names cap at 31 characters, and a truncated collision silently
        # -Appends two gaps' rows into one sheet (AB#5091, hit once already in this file).
        $base = ("$($g.GapId)_$($g.Domain)" -replace '[^\w]', '_')
        $sheet = $base.Substring(0, [math]::Min(31, $base.Length))
        if ($used.ContainsKey($sheet)) {
            $used[$sheet]++
            $suffix = "~$($used[$sheet])"
            $sheet = $base.Substring(0, [math]::Min(31 - $suffix.Length, $base.Length)) + $suffix
        }
        else { $used[$sheet] = 1 }

        $rows = foreach ($e in $ev) {
            [pscustomobject]@{
                GapId            = $g.GapId
                Severity         = $g.Severity
                SubscriptionName = $e.SubscriptionName
                SubscriptionId   = $e.SubscriptionId
                ResourceGroup    = $e.ResourceGroup
                ResourceName     = $e.ResourceName
                ResourceType     = $e.ResourceType
                Location         = $e.Location
                ResourceId       = $e.ResourceId
                Observation      = $e.Observation
                Verdict          = $e.Verdict
                VerdictSource    = $e.VerdictSource
                ClosureAction    = $g.ClosureAction
                Owner            = $g.Owner
            }
        }

        $verdictColours = @(
            New-ConditionalText -Text 'Real - investigate' -Range 'K:K' -ConditionalType ContainsText -BackgroundColor LightPink
            New-ConditionalText -Text 'Platform-required' -Range 'K:K' -ConditionalType ContainsText -BackgroundColor LightBlue
            New-ConditionalText -Text 'Sandbox' -Range 'K:K' -ConditionalType ContainsText -BackgroundColor LightGray
            New-ConditionalText -Text 'Inherited from legacy' -Range 'K:K' -ConditionalType ContainsText -BackgroundColor Wheat
        )
        @($rows) | ImportExcel\Export-Excel -Path $Path -WorksheetName $sheet -AutoSize -FreezeTopRow -AutoFilter -ConditionalText $verdictColours
    }
}

#endregion

function Export-Excel {
    <#
    .PARAMETER Model
        Optional — the report model from Build-ScoutReportModel (AB#6852). When present the
        workbook gains a Cover sheet (scope, source, verdict legend, contents index), a
        consolidated Gap_Register sheet, and one sheet per gap carrying its affected resources
        with full ARM ids and a per-row triage Verdict. The existing per-area evidence sheets
        and the pivot dashboard are retained, not replaced.
    #>
    param($Findings, $Collect, [string] $OutputPath, $Model = $null)
    $xlsx = "$OutputPath/assessment_evidence.xlsx"
    # $Findings.Findings dots directly into a possibly-$null $Findings, or a
    # $Findings object that legitimately omits the key (e.g. a caller-built test
    # fixture) -- both throw PropertyNotFoundException under Set-StrictMode
    # -Version Latest, same reasoning as every Get-ScoutExcelProp call above.
    $allFindings = @(Get-ScoutExcelProp -Obj $Findings -Name 'Findings' -Default @())
    # AB#6857: prefer the report model, exactly as Export-Word and Export-Pptx do.
    $reportModel = $Model
    if (-not $reportModel -and (Get-Command Build-ScoutReportModel -ErrorAction SilentlyContinue)) {
        try { $reportModel = Build-ScoutReportModel -Findings $Findings -Collect $Collect }
        catch { Write-Warning "Export-Excel: could not build the report model ($($_.Exception.Message)) -- writing the evidence sheets only." }
    }

    if (Get-Module -ListAvailable -Name ImportExcel) {
        Import-Module ImportExcel
        # Cover first so it is the sheet the workbook opens on.
        if ($reportModel) {
            Add-ScoutExcelCoverSheet -Model $reportModel -Path $xlsx
            Add-ScoutExcelGapSheets -Model $reportModel -Path $xlsx
        }
        Add-ScoutExcelDashboard -Findings $Findings -Collect $Collect -Path $xlsx
        # Excel worksheet names cap at 31 chars. Truncating alone can collapse two
        # similarly-prefixed areas into one sheet and -Append silently interleaves
        # their evidence. Disambiguate on collision (AB#5091).
        $used = @{}
        $allFindings | Group-Object Area | ForEach-Object {
            $base = ($_.Name -replace '[^\w]', '_')
            $sheet = $base.Substring(0, [math]::Min(31, $base.Length))
            if ($used.ContainsKey($sheet)) {
                $used[$sheet]++
                $suffix = "~$($used[$sheet])"
                $sheet = $base.Substring(0, [math]::Min(31 - $suffix.Length, $base.Length)) + $suffix
            }
            else { $used[$sheet] = 1 }
            # Module-qualified for the same reason as Add-ScoutExcelPivotDashboard's
            # ImportExcel\Export-Excel calls above (AB#322) -- a bare call can
            # recurse into this file's own Export-Excel depending on dot-source scope.
            # AB#6793 -- the three compliance states (Pass/Fail/NotAssessed) must be visually
            # distinguishable, not just distinguishable in the underlying data. Applies to every
            # assessment's evidence sheet, not only compliance ones: a YAML rule set never emits
            # 'NotAssessed' today, so this is a no-op there and a genuine three-colour distinction
            # on a compliance sheet.
            $statusConditions = @(
                New-ConditionalText -Text 'Pass' -Range 'D:D' -ConditionalType ContainsText -BackgroundColor LightGreen
                New-ConditionalText -Text 'Fail' -Range 'D:D' -ConditionalType ContainsText -BackgroundColor LightPink
                New-ConditionalText -Text 'NotAssessed' -Range 'D:D' -ConditionalType ContainsText -BackgroundColor LightBlue
            )
            $_.Group | Select-Object Id, Framework, Severity, Status, EvidenceCount, Title, Remediation |
                ImportExcel\Export-Excel -Path $xlsx -WorksheetName $sheet -AutoSize -Append -ConditionalText $statusConditions
        }
    }
    else {
        Write-Warning 'ImportExcel module not found — writing CSV evidence pack instead.'
        $evDir = Join-Path $OutputPath 'evidence'
        New-Item -ItemType Directory -Path $evDir -Force | Out-Null
        $allFindings | Group-Object Area | ForEach-Object {
            $name = ($_.Name -replace '[^\w]', '_')
            $_.Group | Export-Csv "$evDir/$name.csv" -NoTypeInformation
        }
    }
}
