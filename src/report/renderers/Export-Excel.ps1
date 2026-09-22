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

    # AB#6883. Not every value reaching this helper is a property bag. Evidence rows in
    # particular are not uniformly shaped across collector generations -- some are objects, some
    # are plain strings, some are hashtables -- and `$Obj.PSObject.Properties[...]` throws
    # "The property 'Properties' cannot be found on this object" under StrictMode for the ones
    # that are not. The first real-tenant run produced that error eight times while the whole
    # conformance suite was green, which is precisely why fixture-only verification is not
    # enough.
    #
    # Hashtables are handled explicitly rather than left to PSObject: a hashtable's PSObject
    # exposes its .NET members (Keys, Count, ...), NOT its entries, so a key lookup through the
    # property bag silently returns $Default for a key that is right there.
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }

    $psObj = $Obj.PSObject
    if ($null -eq $psObj) { return $Default }
    $prop = $psObj.Properties[$Name]
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

function Get-ScoutExcelResourceId {
    <#
    .SYNOPSIS
        The ARM resource ids behind one finding, as a cell string.

    .DESCRIPTION
        AB#6883, clause X-04. Evidence rows arrive in several shapes across collector
        generations -- an array of objects with ResourceId, an array of plain id strings, or
        nothing at all -- so this reads defensively rather than assuming one. A rule that
        matched nothing has no id to give and never will; saying "None matched" is the honest
        rendering, and it is distinguishable from a blank cell, which is not.
    #>
    [OutputType([string])]
    param($Finding)

    $ev = Get-ScoutExcelProp -Obj $Finding -Name 'Evidence' -Default @()
    $ids = foreach ($e in @($ev)) {
        if ($null -eq $e) { continue }
        if ($e -is [string]) { $e; continue }
        $rid = Get-ScoutExcelProp -Obj $e -Name 'ResourceId' -Default $null
        if (-not $rid) { $rid = Get-ScoutExcelProp -Obj $e -Name 'id' -Default $null }
        if ($rid) { "$rid" }
    }
    $ids = @($ids | Where-Object { $_ } | Select-Object -Unique)
    if ($ids.Count -eq 0) { return 'None matched' }

    # AB#6864. The engine caps the Evidence payload, so what is in hand may be the first 25 of
    # far more. Saying "25 of 198 matched" is the difference between a complete list and a
    # sample -- and before the flag existed the two were indistinguishable in the workbook.
    $total = Get-ScoutExcelProp -Obj $Finding -Name 'EvidenceCount' -Default $ids.Count
    $truncated = [bool](Get-ScoutExcelProp -Obj $Finding -Name 'EvidenceTruncated' -Default $false)

    # A cell is capped in what a reader can usefully see; the full list stays in the JSON
    # evidence export, and the cell says how many it is not showing rather than truncating
    # silently.
    $shown = @($ids | Select-Object -First 10)
    $text = [string]::Join([Environment]::NewLine, $shown)
    if ($truncated) {
        # The engine truncated before this renderer ever saw the rows, so the honest statement is
        # about the TOTAL, not about the ten shown.
        $text += "$([Environment]::NewLine)($($ids.Count) of $total matched — full list in evidence.json)"
    }
    elseif ($ids.Count -gt $shown.Count) {
        $text += "$([Environment]::NewLine)(+$($ids.Count - $shown.Count) more — see evidence.json)"
    }
    return $text
}

function Get-ScoutExcelTriageSeed {
    <#
    .SYNOPSIS
        The starting triage verdict for one row.

    .DESCRIPTION
        AB#6883, clause X-05. Every gap row carries a verdict: real / by-design / sandbox /
        legacy. Scout cannot determine which -- that judgement needs someone who knows why the
        estate is the way it is -- so a passing control is closed out as "n/a" and everything
        else is seeded "review" for a human to replace. Guessing a verdict would be worse than
        leaving the column out, because a wrong "by-design" closes a real finding.
    #>
    [OutputType([string])]
    param($Finding)

    $status = "$(Get-ScoutExcelProp -Obj $Finding -Name 'Status' -Default '')"
    switch ($status) {
        'Pass' { return 'n/a — passing' }
        'Manual' { return 'review — not assessed' }
        'Unknown' { return 'review — could not evaluate' }
        'Error' { return 'review — collector error' }
        default { return 'review' }
    }
}

function Add-ScoutExcelCoverSheet {
    <#
    .SYNOPSIS
        Sheet 1 — scope, legend, and a contents index with a record count per tab.

    .DESCRIPTION
        AB#6883, clause X-01. A 39-tab workbook with no cover is a filing cabinet with no
        labels: the reader's first question is "which tab do I want and how big is it", and
        before this there was nowhere to answer it.

        Written LAST and then moved to position 1, because the record counts can only be
        computed once every other sheet exists — a cover written first would either be empty or
        would be a second place the counts are derived, free to drift from the sheets.
    #>
    param([Parameter(Mandatory)][string]$Path, [string]$ScanDate, [string]$Scope)

    $pkg = Open-ExcelPackage -Path $Path
    try {
        $existing = @($pkg.Workbook.Worksheets | Where-Object { $_.Name -eq 'Cover' })
        foreach ($ws in $existing) { $pkg.Workbook.Worksheets.Delete($ws) }
        $cover = $pkg.Workbook.Worksheets.Add('Cover')

        $row = 1
        function Set-CoverLine {
            param([int]$R, [string]$A, [string]$B = '', [bool]$Bold = $false, [int]$Size = 11)
            $cover.Cells[$R, 1].Value = $A
            $cover.Cells[$R, 1].Style.Font.Bold = $Bold
            $cover.Cells[$R, 1].Style.Font.Size = $Size
            if ($B) { $cover.Cells[$R, 2].Value = $B }
        }

        Set-CoverLine -R $row -A 'Azure Scout — assessment evidence pack' -Bold $true -Size 16; $row += 2
        Set-CoverLine -R $row -A 'Scan date' -B $ScanDate; $row++
        Set-CoverLine -R $row -A 'Scope' -B $(if ($Scope) { $Scope } else { 'Not recorded' }); $row++
        Set-CoverLine -R $row -A 'Classification' -B 'CONFIDENTIAL — prepared for the named client'; $row += 2

        Set-CoverLine -R $row -A 'Legend' -Bold $true -Size 13; $row++
        foreach ($l in @(
                @('Pass', 'The control was evaluated and is aligned.')
                @('Partial', 'The control was evaluated and is partially aligned.')
                @('Fail', 'The control was evaluated and is not aligned.')
                @('Not assessed', 'No automated rule exists, or it could not run. NOT a pass and NOT a failure.')
                @('Triage', 'real / by-design / sandbox / legacy — seeded as "review" for a human to replace.')
                @('ResourceId', 'The full ARM id. "None matched" means the rule found no candidate resources.')
            )) {
            Set-CoverLine -R $row -A $l[0] -B $l[1]; $row++
        }
        $row++

        Set-CoverLine -R $row -A 'Contents' -Bold $true -Size 13; $row++
        Set-CoverLine -R $row -A 'Tab' -B 'Records' -Bold $true; $row++
        foreach ($ws in $pkg.Workbook.Worksheets) {
            if ($ws.Name -eq 'Cover') { continue }
            # Hidden staging sheets are implementation detail; listing them in a client-facing
            # index would send the reader to a tab they should never open. The `state` check is
            # AB#6891's lesson: a hidden sheet is still enumerated here.
            if ($ws.Hidden -ne [OfficeOpenXml.eWorkSheetHidden]::Visible) { continue }
            $records = if ($ws.Dimension) { [Math]::Max(0, $ws.Dimension.End.Row - 1) } else { 0 }
            $cover.Cells[$row, 1].Value = $ws.Name
            $cover.Cells[$row, 2].Value = $records
            $row++
        }

        $cover.Column(1).Width = 34
        $cover.Column(2).Width = 78
        $pkg.Workbook.Worksheets.MoveToStart('Cover')
    }
    finally {
        Close-ExcelPackage $pkg
    }
}

function Export-ScoutEvidenceWorkbook {
    <#
    .SYNOPSIS
        Render the assessment evidence workbook.

    .DESCRIPTION
        AB#6883. RENAMED from `Export-Excel`, which was a name this file shared with the cmdlet
        exported by ImportExcel -- the module this very function imports. Once that import
        happened, ImportExcel's command shadowed ours for the rest of the session, so the
        dispatcher's `Export-Excel -Findings ...` resolved to theirs and died with "A parameter
        cannot be found that matches parameter name 'Findings'".

        It failed for every PER-ASSESSMENT workbook while the run-root one succeeded, because the
        root ran first and did the import. Only a real multi-assessment tenant run surfaced it.

        Resolving it by `function:` path is not enough: ImportExcel is a script module, so its
        Export-Excel is itself a FUNCTION and shadows ours in that drive too. A distinct name is
        the only fix that cannot be re-broken by import order.
    #>
    param($Findings, $Collect, [string] $OutputPath)
    $xlsx = "$OutputPath/assessment_evidence.xlsx"
    # $Findings.Findings dots directly into a possibly-$null $Findings, or a
    # $Findings object that legitimately omits the key (e.g. a caller-built test
    # fixture) -- both throw PropertyNotFoundException under Set-StrictMode
    # -Version Latest, same reasoning as every Get-ScoutExcelProp call above.
    $allFindings = @(Get-ScoutExcelProp -Obj $Findings -Name 'Findings' -Default @())
    if (Get-Module -ListAvailable -Name ImportExcel) {
        Import-Module ImportExcel
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
            # AB#6883, clauses X-04 and X-05. Two columns the evidence pack never had, and they
            # are the two that decide whether a row can be acted on:
            #
            #   ResourceId  the full ARM id. A finding a reader cannot locate in the portal is
            #               decoration. Where a rule matched nothing there is genuinely nothing
            #               to name, and the cell says so rather than sitting empty -- an empty
            #               cell is indistinguishable from a rule that never ran.
            #   Triage      real / by-design / sandbox / legacy. This is the single
            #               highest-value column in the reference gap workbook: it is what turns
            #               149 raw findings into "141 deliberate, 8 real". Scout cannot know
            #               the verdict, so it seeds the column and marks it for the reviewer
            #               rather than guessing one.
            $_.Group | Select-Object Id, Framework, Severity, Status, EvidenceCount,
            @{ n = 'ResourceId'; e = { Get-ScoutExcelResourceId -Finding $_ } },
            @{ n = 'Triage'; e = { Get-ScoutExcelTriageSeed -Finding $_ } },
            Title, Remediation |
                # AB#6883, clause X-03. FreezeTopRow and AutoFilter are not cosmetics on an
                # evidence tab: a gap workbook is read by scrolling and filtering, and without
                # them a reader 200 rows down has lost the header and cannot narrow to the rows
                # they came for. The reference gap workbook has both on all 13 tabs.
                ImportExcel\Export-Excel -Path $xlsx -WorksheetName $sheet -AutoSize -Append `
                    -FreezeTopRow -AutoFilter -ConditionalText $statusConditions
        }

        # Clause X-01. Last, so the record counts are read off the sheets that exist rather than
        # predicted; then moved to position 1 so it is the first thing opened.
        $generatedOn = Get-ScoutExcelProp -Obj $Findings -Name 'GeneratedOn' -Default $null
        $scanDate = if ($generatedOn) {
            try { ([datetime]$generatedOn).ToString('yyyy-MM-dd') } catch { "$generatedOn" }
        }
        else { (Get-Date).ToString('yyyy-MM-dd') }
        $scope = Get-ScoutExcelProp -Obj (Get-ScoutExcelProp -Obj $Collect -Name '_meta' -Default $null) -Name 'scope' -Default $null
        try {
            Add-ScoutExcelCoverSheet -Path $xlsx -ScanDate $scanDate -Scope $scope
        }
        catch {
            # A cover is worth having but not worth losing the evidence pack over.
            Write-Warning "Export-Excel: the cover sheet could not be written ($($_.Exception.Message)) — the evidence tabs are unaffected."
        }
    }
    else {
        Write-Warning 'ImportExcel module not found — writing CSV evidence pack instead.'
        $evDir = Join-Path $OutputPath 'evidence'
        New-Item -ItemType Directory -Path $evDir -Force | Out-Null
        $allFindings | Group-Object Area | ForEach-Object {
            $name = ($_.Name -replace '[^\w]', '_')
            $_.Group | ForEach-Object {
                $safe = [ordered]@{}
                foreach ($property in $_.PSObject.Properties) {
                    $value = $property.Value
                    if ($value -is [string] -and $value -match '^[\t\r\n ]*[=+\-@]') { $value = "'$value" }
                    $safe[$property.Name] = $value
                }
                [pscustomobject]$safe
            } | Export-Csv "$evDir/$name.csv" -NoTypeInformation
        }
    }
}
