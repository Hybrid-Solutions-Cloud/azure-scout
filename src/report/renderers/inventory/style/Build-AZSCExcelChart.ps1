<#
.Synopsis
Module for Excel Chart Creation

.DESCRIPTION
This script creates charts in the Overview sheet of the Excel report.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/3.ReportingFunctions/StyleFunctions/Build-AZSCExcelChart.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

<#
.SYNOPSIS
Adds one Overview pivot table (and its pivot chart) only when the source worksheet can
actually back a pivot.

.DESCRIPTION
Wraps ImportExcel's Add-PivotTable with the pre-condition every call site in
Build-AZSCExcelChart needs and none of them fully had.

ImportExcel builds the pivot's source range itself, from
`$SourceWorksheet.Cells[$SourceWorksheet.Dimension.Address]` (Add-PivotTable.ps1 line 92,
7.8.10). A worksheet that exists but holds no cells has a `$null` Dimension, so that
expression becomes `Cells[$null]` and throws "Index operation failed; the array index
evaluated to null" -- which Add-PivotTable catches and downgrades to
"WARNING: Failed adding PivotTable '<name>'", immediately followed by
"WARNING: Failed adding chart for pivotable '<name>': Cannot bind argument to parameter
'PivotTable' because it is null". The run completes and the pivot plus its chart are
silently absent from Overview.

An empty-but-present worksheet is normal, not exotic: Build-AZSCSubsReport always writes
the 'Subscriptions' worksheet even when the run collected zero subscription rows, and the
inventory renderers do the same for their own tabs. So testing `if ($PTParams.SourceWorkSheet)`
-- which six branches in this file did and the rest did not -- is not enough: the sheet must
exist AND have a dimension. That gap is what made the "P6"/"ChartP6" pivot vanish from
full-scale reports while a small synthetic repro passed. (AB#5666)

Guarding rather than warning is deliberate: no pivot is buildable from an empty sheet, so
there is nothing for an operator to act on. The skip is recorded with Write-Debug, on the
same channel as the rest of this renderer.

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)
#>
function Add-AZSCOverviewPivot {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] [hashtable] $PivotParams,
        [switch] $NoLegend
    )

    $Sheet = $PivotParams['SourceWorkSheet']
    # A worksheet lookup through `Worksheets | Where-Object` yields $null when nothing
    # matched and a bare object when one did -- but a multi-match would yield an array, and
    # indexing/property-reading that would not be the same thing. Normalise first.
    if ($Sheet -is [array]) { $Sheet = if ($Sheet.Count -gt 0) { $Sheet[0] } else { $null } }

    if (-not $Sheet) {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Skipping pivot '$($PivotParams['PivotTableName'])': source worksheet is absent.")
        return
    }
    if ($null -eq $Sheet.Dimension) {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Skipping pivot '$($PivotParams['PivotTableName'])': source worksheet '$($Sheet.Name)' has no data rows.")
        return
    }

    # -NoLegend is only forwarded when the caller actually passed it: several $PTParams
    # hashtables already carry a NoLegend key, and supplying the parameter as well as the
    # splatted key is a duplicate-parameter error.
    if ($PSBoundParameters.ContainsKey('NoLegend')) {
        Add-PivotTable @PivotParams -NoLegend:$NoLegend
    }
    else {
        Add-PivotTable @PivotParams
    }
}

function Build-AZSCExcelChart {
    Param($Excel, $Overview, $IncludeCosts)

    $WS = $Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Overview' }

    # Resolve a worksheet by name WITHOUT dereferencing $excel.'<Name>' directly. That property
    # access throws "The property '<Name>' cannot be found on this object" whenever the estate
    # produced no such worksheet (no public IPs, no disks, no VMs...), which killed the entire
    # report after every worksheet had already been written. Returning $null instead lets the
    # existing `if ($PTParams.SourceWorkSheet)` guards do their job. (AB#5567)
    $GetSheet = { param([string] $SheetName) $Excel.Workbook.Worksheets | Where-Object { $_.Name -eq $SheetName } }

    # Each $P<n>Name below is assigned only inside a worksheet-exists branch, but is read
    # unconditionally afterwards by the matching $DrawP<n>.RichText.Add($P<n>Name) call. On an
    # estate where none of a group's branches match -- P7 ('Virtual Machines') and P9 have a
    # SINGLE conditional assignment, so this is easy to hit -- the read threw "The variable
    # '$P7Name' cannot be retrieved because it has not been set" and killed the whole report
    # after extraction, processing and every worksheet had already succeeded. Initialising them
    # up front means a pivot that could not be built simply gets no title instead. Same defect
    # class as AB#5547. (AB#5567)
    $P0Name = ''; $P1Name = ''; $P2Name = ''; $P3Name = ''; $P4Name = ''
    $P5Name = ''; $P6Name = ''; $P7Name = ''; $P8Name = ''; $P9Name = ''

    $DrawP00 = $WS.Drawings | Where-Object { $_.Name -eq 'TP00' }
    $P00Name = 'Reported Resources'
    $DrawP00.RichText.Add($P00Name).Size = 16

    if([bool]$IncludeCosts)
        {
            $PTParams = @{
                PivotTableName          = "P00"
                Address                 = $excel.Overview.cells["BA5"] # top-left corner of the table
                SourceWorkSheet         = (& $GetSheet 'Subscriptions')
                PivotRows               = @("Subscription")
                PivotData               = @{"Cost" = "Sum" }
                PivotColumns            = @("Month")
                PivotTableStyle         = $TableStyle
                IncludePivotChart       = $true
                ChartType               = "ColumnStacked3D"
                ChartRow                = 1 # place the chart below row 22nd
                ChartColumn             = 9
                Activate                = $true
                PivotNumberFormat       = 'Currency'
                PivotFilter             = 'Resource Type'
                PivotTotals             = 'Rows'
                ShowCategory            = $false
                NoLegend                = $true
                ChartTitle              = 'Azure Cost per Subscription'
                ShowPercent             = $true
                ChartHeight             = 400
                ChartWidth              = 950
                ChartRowOffSetPixels    = 0
                ChartColumnOffSetPixels = 5
            }
            Add-AZSCOverviewPivot -PivotParams $PTParams
        }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Reservation Advisor' }) -and -not ($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Cost Management' })) {
        # Only use Reservation Advisor pivot when there is no dedicated Cost Management tab.
        # When the Cost Management tab exists, reservation data lives there — keep Overview lean.
        $PTParams = @{
            PivotTableName          = "P00"
            Address                 = $excel.Overview.cells["BA5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Reservation Advisor')
            PivotRows               = @("Subscription")
            PivotData               = @{"Net Savings" = "Sum" }
            PivotTableStyle         = $TableStyle
            IncludePivotChart       = $true
            ChartType               = "ColumnStacked3D"
            ChartRow                = 1 # place the chart below row 22nd
            ChartColumn             = 9
            Activate                = $true
            PivotNumberFormat       = '$#'
            PivotFilter             = 'Recommended Size'
            PivotTotals             = 'Both'
            ShowCategory            = $false
            NoLegend                = $true
            ChartTitle              = 'Potential Net Savings (VM Reservation)'
            ShowPercent             = $true
            ChartHeight             = 400
            ChartWidth              = 950
            ChartRowOffSetPixels    = 0
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }
    else
        {
            Add-ExcelChart -Worksheet $excel.Overview -ChartType Area3D -XRange "AzureTabs[Name]" -YRange "AzureTabs[Size]" -SeriesHeader 'Resources', 'Count' -Column 9 -Row 1 -Height 400 -Width 950 -RowOffSetPixels 0 -ColumnOffSetPixels 5 -NoLegend
        }

    if([bool]$IncludeCosts)
        {
            $P0Name = 'CostPerRegion'
            $PTParams = @{
                PivotTableName          = "P0"
                Address                 = $excel.Overview.cells["BG5"] # top-left corner of the table
                SourceWorkSheet         = (& $GetSheet 'Subscriptions')
                PivotRows               = @("Location")
                PivotData               = @{"Cost" = "Sum" }
                PivotColumns            = @("Month")
                PivotTableStyle         = $tableStyle
                IncludePivotChart       = $true
                ChartType               = "BarStacked3D"
                ChartRow                = 13 # place the chart below row 22nd
                ChartColumn             = 2
                Activate                = $true
                PivotNumberFormat       = 'Currency'
                PivotFilter             = 'Subscription'
                ChartTitle              = 'Cost by Azure Region'
                ShowPercent             = $true
                ChartHeight             = 275
                ChartWidth              = 445
                ChartRowOffSetPixels    = 5
                ChartColumnOffSetPixels = 5
            }
            Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Outages' }) -and $Overview -eq 1) {
        $P0Name = 'Outages'
        $PTParams = @{
            PivotTableName          = "P0"
            Address                 = $excel.Overview.cells["BG5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Outages')
            PivotRows               = @("Impacted Services")
            PivotData               = @{"Impacted Services" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarStacked3D"
            ChartRow                = 13 # place the chart below row 22nd
            ChartColumn             = 2
            Activate                = $true
            PivotFilter             = 'Subscription'
            ChartTitle              = 'Outages (Last 6 Months)'
            ShowPercent             = $true
            ChartHeight             = 275
            ChartWidth              = 445
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Advisor' }) -and $Overview -eq 2) {
        $P0Name = 'Advisories'
        $PTParams = @{
            PivotTableName          = "P0"
            Address                 = $excel.Overview.cells["BG5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Advisor')
            PivotRows               = @("Category")
            PivotData               = @{"Category" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarStacked3D"
            ChartRow                = 13 # place the chart below row 22nd
            ChartColumn             = 2
            Activate                = $true
            PivotFilter             = 'Impact'
            ChartTitle              = 'Advisor'
            ShowPercent             = $true
            ChartHeight             = 275
            ChartWidth              = 445
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    else {
        $P0Name = 'Public IPs'
        # Resolve the worksheet through the Worksheets collection rather than dereferencing
        # $excel.'Public IPs' directly. On an estate with no public IPs that worksheet does not
        # exist and the direct property access THROWS "The property 'Public IPs' cannot be found
        # on this object" while the hashtable is being built -- before the
        # `if ($PTParams.SourceWorkSheet)` guard below ever runs. This mirrors the
        # Worksheets | Where-Object lookup the Advisor/Security branches above already use.
        # (AB#5567)
        $PublicIpSheet = $Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Public IPs' }
        $PTParams = @{
            PivotTableName          = "P0"
            Address                 = $excel.Overview.cells["BG5"] # top-left corner of the table
            SourceWorkSheet         = $PublicIpSheet
            PivotRows               = @("Use")
            PivotData               = @{"Use" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarStacked3D"
            ChartRow                = 13 # place the chart below row 22nd
            ChartColumn             = 2
            Activate                = $true
            PivotFilter             = 'location'
            ChartTitle              = 'Public IPs'
            ShowPercent             = $true
            ChartHeight             = 275
            ChartWidth              = 445
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        if ($PTParams.SourceWorkSheet) {
            Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
        }
    }

    $DrawP0 = $WS.Drawings | Where-Object { $_.Name -eq 'TP0' }
    $DrawP0.RichText.Add($P0Name) | Out-Null

    if([bool]$IncludeCosts)
        {
            $P1Name = 'TotalCostsPerSubscription'
            $PTParams = @{
                PivotTableName          = "P1"
                Address                 = $excel.Overview.cells["DK6"] # top-left corner of the table
                SourceWorkSheet         = (& $GetSheet 'Subscriptions')
                PivotRows               = @('Month')
                PivotColumns            = @("Resource Type")
                PivotData               = @{"Cost" = "Sum" }
                PivotTableStyle         = $tableStyle
                IncludePivotChart       = $true
                ChartType               = "BarClustered"
                ChartRow                = 27 # place the chart below row 22nd
                ChartColumn             = 2
                Activate                = $true
                PivotNumberFormat       = 'Currency'
                ShowCategory            = $false
                ChartTitle              = 'Cost by Resource Type'
                NoLegend                = $true
                ShowPercent             = $true
                ChartHeight             = 655
                ChartWidth              = 570
                ChartRowOffSetPixels    = 5
                ChartColumnOffSetPixels = 5
            }
            Add-AZSCOverviewPivot -PivotParams $PTParams
        }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'AdvisorScore' }) -and $Overview -eq 1) {
        $P1Name = 'AdvisorScore'
        $PTParams = @{
            PivotTableName          = "P1"
            Address                 = $excel.Overview.cells["DK6"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'AdvisorScore')
            PivotRows               = @("Category")
            PivotData               = @{"Latest Score (%)" = "average" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarClustered"
            ChartRow                = 27 # place the chart below row 22nd
            ChartColumn             = 2
            Activate                = $true
            #PivotNumberFormat       = '0'
            ShowCategory            = $false
            PivotFilter             = 'Subscription'
            ChartTitle              = 'Advisor Score (%)'
            NoLegend                = $true
            ShowPercent             = $true
            ChartHeight             = 655
            ChartWidth              = 570
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Subscriptions' }) -and $Overview -eq 2) {
        $P1Name = 'Subscriptions'
        $PTParams = @{
            PivotTableName          = "P1"
            Address                 = $excel.Overview.cells["DK6"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Subscriptions')
            PivotRows               = @("Subscription")
            PivotData               = @{"Resources Count" = "sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarClustered"
            ChartRow                = 27 # place the chart below row 22nd
            ChartColumn             = 2
            Activate                = $true
            PivotFilter             = 'Resource Group'
            ChartTitle              = 'Resources by Subscription'
            NoLegend                = $true
            ShowPercent             = $true
            ChartHeight             = 655
            ChartWidth              = 570
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Quota Usage' }) -and $Overview -eq 1) {
        $P1Name = 'Quota Usage'
        $PTParams = @{
            PivotTableName          = "P1"
            Address                 = $excel.Overview.cells["DK6"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Quota Usage')
            PivotRows               = @("Region")
            PivotData               = @{"vCPUs Available" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarClustered"
            ChartRow                = 27 # place the chart below row 22nd
            ChartColumn             = 2
            Activate                = $true
            PivotFilter             = 'Limit'
            ChartTitle              = 'Available Quota (vCPUs)'
            NoLegend                = $true
            ShowPercent             = $true
            ChartHeight             = 655
            ChartWidth              = 570
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }
    else {
        $P1Name = 'Virtual Networks'
        $PTParams = @{
            PivotTableName          = "P1"
            Address                 = $excel.Overview.cells["DK6"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Virtual Networks')
            PivotRows               = @("Name")
            PivotData               = @{"Available IPs" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarClustered"
            ChartRow                = 27 # place the chart below row 22nd
            ChartColumn             = 2
            Activate                = $true
            PivotFilter             = 'Location'
            ChartTitle              = 'Available IPs (Per Virtual Network)'
            NoLegend                = $true
            ShowPercent             = $true
            ChartHeight             = 655
            ChartWidth              = 570
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        if ($PTParams.SourceWorkSheet) {
            Add-AZSCOverviewPivot -PivotParams $PTParams
        }
    }
    $DrawP1 = $WS.Drawings | Where-Object { $_.Name -eq 'TP1' }
    $DrawP1.RichText.Add($P1Name) | Out-Null

    if (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Policy' }) -and $Overview -eq 1) {
        $P2Name = 'Policy'
        $PTParams = @{
            PivotTableName          = "P2"
            Address                 = $excel.Overview.cells["BT5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Policy')
            PivotRows               = @("Policy Category")
            PivotData               = @{"Policy" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "ColumnStacked3D"
            ChartRow                = 21 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            PivotFilter             = 'Policy Type'
            ChartTitle              = 'Policies by Category'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Advisor' }) -and $Overview -eq 2) {
        $P2Name = 'Annual Savings'
        $PTParams = @{
            PivotTableName          = "P2"
            Address                 = $excel.Overview.cells["BT5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Advisor')
            PivotRows               = @("Savings Currency")
            PivotData               = @{"Annual Savings" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "ColumnStacked3D"
            ChartRow                = 21 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            ChartTitle              = 'Potential Savings'
            PivotFilter             = 'Savings Region'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
            PivotNumberFormat       = '#,##0.00'
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    else {
        $P2Name = 'Virtual Networks'
        $PTParams = @{
            PivotTableName          = "P2"
            Address                 = $excel.Overview.cells["BT5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Virtual Networks')
            PivotRows               = @("Location")
            PivotData               = @{"Location" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "ColumnStacked3D"
            ChartRow                = 21 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            ChartTitle              = 'Virtual Networks'
            PivotFilter             = 'Subscription'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        if ($PTParams.SourceWorkSheet) {
            Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
        }
    }

    $DrawP2 = $WS.Drawings | Where-Object { $_.Name -eq 'TP2' }
    $DrawP2.RichText.Add($P2Name) | Out-Null

    if (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Support Tickets' }) -and $Overview -eq 1) {
        $P3Name = 'Support Tickets'
        $PTParams = @{
            PivotTableName          = "P3"
            Address                 = $excel.Overview.cells["BZ5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Support Tickets')
            PivotRows               = @("Status")
            PivotData               = @{"Status" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "Pie3D"
            ChartRow                = 34 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            PivotFilter             = 'Current Severity'
            ChartTitle              = 'Support Tickets'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'AKS' }) -and $Overview -eq 2) {
        $P3Name = 'Azure Kubernetes'
        $PTParams = @{
            PivotTableName          = "P3"
            Address                 = $excel.Overview.cells["BZ5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'AKS')
            PivotRows               = @("Kubernetes Version")
            PivotData               = @{"Clusters" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "Pie3D"
            ChartRow                = 34 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            ChartTitle              = 'AKS Versions'
            PivotFilter             = 'Node Pool Size'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }
    else {
        $P3Name = 'Storage Accounts'
        $PTParams = @{
            PivotTableName          = "P3"
            Address                 = $excel.Overview.cells["BZ5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Storage Accounts')
            PivotRows               = @("Tier")
            PivotData               = @{"Tier" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "Pie3D"
            ChartRow                = 34 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            PivotFilter             = 'SKU'
            ChartTitle              = 'Storage Accounts'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        if ($PTParams.SourceWorkSheet) {
            Add-AZSCOverviewPivot -PivotParams $PTParams
        }
    }
    $DrawP3 = $WS.Drawings | Where-Object { $_.Name -eq 'TP3' }
    $DrawP3.RichText.Add($P3Name) | Out-Null

    if (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Outages' }) -and $Overview -eq 1) {
        $P4Name = 'Outages'
        $PTParams = @{
            PivotTableName          = "P4"
            Address                 = $excel.Overview.cells["CF5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Outages')
            PivotRows               = @("Subscription")
            PivotData               = @{"Outage ID" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "ColumnStacked3D"
            ChartRow                = 47 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            PivotFilter             = 'Event Level'
            ChartTitle              = 'Outages per Subscription'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    elseif (($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Quota Usage' }) -and $Overview -eq 2) {
        $P4Name = 'Quota Usage'
        $PTParams = @{
            PivotTableName          = "P4"
            Address                 = $excel.Overview.cells["CF5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Quota Usage')
            PivotRows               = @("Region")
            PivotData               = @{"vCPUs Available" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "ColumnStacked3D"
            ChartRow                = 47 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            PivotFilter             = 'Limit'
            ChartTitle              = 'Available Quota (vCPUs)'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    else {
        $P4Name = 'VM Disks'
        $PTParams = @{
            PivotTableName          = "P4"
            Address                 = $excel.Overview.cells["CF5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Disks')
            PivotRows               = @("Disk State")
            PivotData               = @{"Disk State" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "ColumnStacked3D"
            ChartRow                = 47 # place the chart below row 22nd
            ChartColumn             = 11
            Activate                = $true
            PivotFilter             = 'SKU'
            ChartTitle              = 'VM Disks'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        if ($PTParams.SourceWorkSheet) {
            Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
        }
    }

    $DrawP4 = $WS.Drawings | Where-Object { $_.Name -eq 'TP4' }
    $DrawP4.RichText.Add($P4Name) | Out-Null

    if ($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Virtual Machines' }) {
        $P5Name = 'Virtual Machines'
        $PTParams = @{
            PivotTableName          = "P5"
            Address                 = $excel.Overview.cells["CL7"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Virtual Machines')
            PivotRows               = @("VM Size")
            PivotData               = @{"Resource U" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarClustered"
            ChartRow                = 21 # place the chart below row 22nd
            ChartColumn             = 16
            Activate                = $true
            NoLegend                = $true
            ChartTitle              = 'Virtual Machines by Serie'
            PivotFilter             = 'OS Type', 'Location', 'Power State'
            ShowPercent             = $true
            ChartHeight             = 775
            ChartWidth              = 502
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    } else {
        $P5Name = 'Virtual Networks'
        $PTParams = @{
            PivotTableName          = "P5"
            Address                 = $excel.Overview.cells["CL7"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Virtual Networks')
            PivotRows               = @("Name")
            PivotData               = @{"Available IPs" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarClustered"
            ChartRow                = 21 # place the chart below row 22nd
            ChartColumn             = 16
            Activate                = $true
            NoLegend                = $true
            ChartTitle              = 'Available IPs (Per Virtual Network)'
            PivotFilter             = 'Location'
            ShowPercent             = $true
            ChartHeight             = 775
            ChartWidth              = 502
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 5
        }
        if ($PTParams.SourceWorkSheet) {
            Add-AZSCOverviewPivot -PivotParams $PTParams
        }
    }

    $DrawP5 = $WS.Drawings | Where-Object { $_.Name -eq 'TP5' }
    $DrawP5.RichText.Add($P5Name) | Out-Null

    if([bool]$IncludeCosts)
        {
            $P6Name = 'Cost per Month'
            $PTParams = @{
                PivotTableName          = "P6"
                Address                 = $excel.Overview.cells["CR5"] # top-left corner of the table
                SourceWorkSheet         = (& $GetSheet 'Subscriptions')
                PivotRows               = @("Month")
                PivotData               = @{"Cost" = "sum" }
                PivotTableStyle         = $tableStyle
                IncludePivotChart       = $true
                ChartType               = "ColumnStacked3D"
                ChartRow                = 1 # place the chart below row 22nd
                ChartColumn             = 24
                Activate                = $true
                PivotNumberFormat       = 'Currency'
                PivotFilter             = 'Subscription'
                ChartTitle              = 'Cost per Month'
                NoLegend                = $true
                ShowPercent             = $true
                ChartHeight             = 400
                ChartWidth              = 315
                ChartRowOffSetPixels    = 0
                ChartColumnOffSetPixels = 0
            }
            Add-AZSCOverviewPivot -PivotParams $PTParams
        }
    else
        {
    # FIXED (AB#5666). This branch used to call Add-PivotTable unguarded and lost the P6 pivot
    # plus its ChartP6 chart at full scale, with:
    #   WARNING: Failed adding PivotTable 'P6': Index operation failed; the array index
    #   evaluated to null.
    #   WARNING: Failed adding chart for pivotable 'P6': Cannot bind argument to parameter
    #   'PivotTable' because it is null.
    # Root cause: the 'Subscriptions' worksheet EXISTED but was EMPTY, so ImportExcel's
    # `$SourceWorksheet.Cells[$SourceWorksheet.Dimension.Address]` became `Cells[$null]`.
    # It was empty because the harness that surfaced this (tests/Test-ExcelFromDataDump.ps1)
    # still fed subscriptions through the pre-AB#5649 background job instead of -ExtraData, so
    # Build-AZSCSubsReport received $null and wrote a header-less, row-less sheet -- and a real
    # run against an estate with no subscription rows lands in exactly the same place. The
    # earlier 3-row synthetic repro could not reproduce it precisely because 3 rows give the
    # sheet a Dimension. Add-AZSCOverviewPivot (top of this file) now checks the dimension, not
    # just the sheet's existence, for every pivot in this function.
    $P6Name = 'Resources by Location'
    $PTParams = @{
        PivotTableName          = "P6"
        Address                 = $excel.Overview.cells["CR5"] # top-left corner of the table
        SourceWorkSheet         = (& $GetSheet 'Subscriptions')
        PivotRows               = @("Location")
        PivotData               = @{"Resources Count" = "sum" }
        PivotTableStyle         = $tableStyle
        IncludePivotChart       = $true
        ChartType               = "ColumnStacked3D"
        ChartRow                = 1 # place the chart below row 22nd
        ChartColumn             = 24
        Activate                = $true
        PivotFilter             = 'Resource Type'
        ChartTitle              = 'Resources by Location'
        NoLegend                = $true
        ShowPercent             = $true
        ChartHeight             = 400
        ChartWidth              = 315
        ChartRowOffSetPixels    = 0
        ChartColumnOffSetPixels = 0
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }

    $DrawP6 = $WS.Drawings | Where-Object { $_.Name -eq 'TP6' }
    $DrawP6.RichText.Add($P6Name) | Out-Null

    if ($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Virtual Machines' }) {
        $P7Name = 'Virtual Machines'
        $PTParams = @{
            PivotTableName          = "P7"
            Address                 = $excel.Overview.cells["CY5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Virtual Machines')
            PivotRows               = @("OS Type")
            PivotData               = @{"Resource U" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "Pie3D"
            ChartRow                = 21 # place the chart below row 22nd
            ChartColumn             = 24
            Activate                = $true
            NoLegend                = $true
            ChartTitle              = 'VMs by OS'
            PivotFilter             = 'Location'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 0
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }

    $DrawP7 = $WS.Drawings | Where-Object { $_.Name -eq 'TP7' }
    $DrawP7.RichText.Add($P7Name) | Out-Null

    if ($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Advisor' }) {
        $P8Name = 'Advisories'
        $PTParams = @{
            PivotTableName          = "P8"
            Address                 = $excel.Overview.cells["DE5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Advisor')
            PivotRows               = @("Impact")
            PivotData               = @{"Impact" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarStacked3D"
            ChartRow                = 34
            ChartColumn             = 24
            Activate                = $true
            PivotFilter             = 'Category'
            ChartTitle              = 'Advisor'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 0
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    elseif ($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Load Balancers' }) {
        $P8Name = 'Load Balancers'
        $PTParams = @{
            PivotTableName          = "P8"
            Address                 = $excel.Overview.cells["DE5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Load Balancers')
            PivotRows               = @("Usage")
            PivotData               = @{"Usage" = "Count" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarStacked3D"
            ChartRow                = 34
            ChartColumn             = 24
            Activate                = $true
            PivotFilter             = 'Location'
            ChartTitle              = 'Load Balancers'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 0
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    elseif ($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Virtual Machines' }) {
        $P8Name = 'VMs per Region'
        $PTParams = @{
            PivotTableName          = "P8"
            Address                 = $excel.Overview.cells["DE5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Virtual Machines')
            PivotRows               = @("Location")
            PivotData               = @{"Resource U" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarStacked3D"
            ChartRow                = 34
            ChartColumn             = 24
            Activate                = $true
            PivotFilter             = 'Subscription'
            ChartTitle              = 'VMs by Region'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 0
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }
    else{
        $P8Name = 'Resources per Region'
        $PTParams = @{
            PivotTableName          = "P8"
            Address                 = $excel.Overview.cells["DE5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Subscriptions')
            PivotRows               = @("Location")
            PivotData               = @{"Resources Count" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "BarStacked3D"
            ChartRow                = 34
            ChartColumn             = 24
            Activate                = $true
            PivotFilter             = 'Subscription'
            ChartTitle              = 'Resources by Location'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 0
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams -NoLegend
    }

    $DrawP8 = $WS.Drawings | Where-Object { $_.Name -eq 'TP8' }
    $DrawP8.RichText.Add($P8Name) | Out-Null

    if ($Excel.Workbook.Worksheets | Where-Object { $_.Name -eq 'Virtual Machines' }) {
        $P9Name = 'Virtual Machines'
        $PTParams = @{
            PivotTableName          = "P9"
            Address                 = $excel.Overview.cells["BM5"] # top-left corner of the table
            SourceWorkSheet         = (& $GetSheet 'Virtual Machines')
            PivotRows               = @("Boot Diagnostics")
            PivotData               = @{"Resource U" = "Sum" }
            PivotTableStyle         = $tableStyle
            IncludePivotChart       = $true
            ChartType               = "Pie3D"
            ChartRow                = 47
            ChartColumn             = 24
            Activate                = $true
            NoLegend                = $true
            ChartTitle              = 'Boot Diagnostics'
            PivotFilter             = 'Location'
            ShowPercent             = $true
            ChartHeight             = 255
            ChartWidth              = 315
            ChartRowOffSetPixels    = 5
            ChartColumnOffSetPixels = 0
        }
        Add-AZSCOverviewPivot -PivotParams $PTParams
    }

    $DrawP9 = $WS.Drawings | Where-Object { $_.Name -eq 'TP9' }
    $DrawP9.RichText.Add($P9Name) | Out-Null

}
