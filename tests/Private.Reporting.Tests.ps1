#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the inventory report renderer (src/report/renderers/inventory).

.DESCRIPTION
    Tests the inventory Excel report engine: file existence, syntax, function
    definitions, and two real end-to-end checks --

      - "Inventory Excel end-to-end" builds a tiny real ReportCache (one real
        InventoryModules collector's Reporting-mode output, plus a synthetic
        Subscriptions sheet exactly as Start-AZSCExtraReports produces one) and
        runs the actual Start-AZSCReporOrchestration -> Start-AZSCExcelCustomization
        call chain the product uses, then asserts on the real .xlsx it writes:
        worksheet names, row counts and column headers. This is the acceptance
        test AB#5662/AB#5665 call for: a real workbook from a real ReportCache.

      - "Build-AZSCExcelChartStyle (EPPlus-native, no COM)" unit-tests the
        replacement for the retired Build-AZSCExcelComObject.ps1 directly against
        a minimal workbook containing a named pivot chart and the Overview panel
        shapes, proving the COM-free styling actually applies and persists.

    No live Azure authentication is required. Skips (Pester -Skip) when
    ImportExcel isn't installed, matching the other Report.*.Tests.ps1 files.

.NOTES
    Author:  AzureScout Contributors
    Version: 2.0.0 -- AB#5662/AB#5665 (moved from Modules/Private/Reporting to
    src/report/renderers/inventory; retired the COM-dependent chart styler)
#>

BeforeDiscovery {
    $script:HasImportExcel = [bool](Get-Module -ListAvailable -Name ImportExcel)
}

BeforeAll {
    $script:HasImportExcel   = [bool](Get-Module -ListAvailable -Name ImportExcel)
    $script:ModuleRoot       = Split-Path -Parent $PSScriptRoot

    # Collectors are executed here as bare scriptblocks, NOT through the imported module, so any
    # private helper they call has to be dot-sourced in explicitly. Get-AZSCSafeProperty is the
    # StrictMode-safe dotted-path read that converted collectors use instead of a raw `$data.a.b`
    # chain (which throws when an intermediate segment is genuinely ABSENT rather than $null), and
    # Get-AZSCCollectedValue is its member-ENUMERATION counterpart for a read over a collection
    # that may be empty. Both are needed here from AB#5671 onwards.
    . (Join-Path $script:ModuleRoot 'src' 'Get-AZSCSafeProperty.ps1')
    . (Join-Path $script:ModuleRoot 'src' 'Get-AZTICollectedValue.ps1')
    # Get-AZSCIdSegment (AB#5671) guards the FIXED .split('/')[8] index ~30 collectors use to pull
    # a name out of a related resource id -- an out-of-range index THROWS under StrictMode, where
    # without it the same expression quietly returned $null.
    . (Join-Path $script:ModuleRoot 'src' 'Get-AZSCIdSegment.ps1')
    $script:InventoryPath    = Join-Path $script:ModuleRoot 'src' 'report' 'renderers' 'inventory'
    $script:StylePath        = Join-Path $script:InventoryPath 'style'
    # Unique per run -- a fixed folder that BeforeAll deletes lets two concurrent runs of this
    # suite on one machine destroy each other's workbooks mid-assertion (AB#5666).
    $script:TempDir          = Join-Path ([System.IO.Path]::GetTempPath()) ("AZSC_InventoryReportingTests_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =====================================================================
# FILE EXISTENCE
# =====================================================================
Describe 'src/report/renderers/inventory Module Files Exist' {
    $reportingFiles = @(
        'Build-AZSCAdvisoryReport.ps1',
        'Build-AZSCCostManagementReport.ps1',
        'Build-AZSCMonitorReport.ps1',
        'Build-AZSCPolicyReport.ps1',
        'Build-AZSCQuotaReport.ps1',
        'Build-AZSCSecCenterReport.ps1',
        'Build-AZSCSecurityOverviewReport.ps1',
        'Build-AZSCSubsReport.ps1',
        'Build-AZSCUpdateManagerReport.ps1',
        'Export-AZSCAsciiDocReport.ps1',
        'Export-AZSCJsonReport.ps1',
        'Export-AZSCMarkdownReport.ps1',
        'Export-AZSCPowerBIReport.ps1',
        'New-AZSCPowerBITemplate.ps1',
        'Start-AZSCExcelExtraData.ps1',
        'Start-AZSCExcelJob.ps1',
        'Start-AZSCExtraReports.ps1'
    )

    It '<_> exists' -ForEach $reportingFiles {
        Join-Path $script:InventoryPath $_ | Should -Exist
    }
}

Describe 'src/report/renderers/inventory/style Files Exist' {
    $styleFiles = @(
        'Build-AZSCExcelChart.ps1',
        'Build-AZSCExcelChartStyle.ps1',
        'Build-AZSCExcelInitialBlock.ps1',
        'Out-AZSCReportResults.ps1',
        'Start-AZSCExcelCustomization.ps1',
        'Start-AZSCExcelOrdening.ps1'
    )

    It '<_> exists' -ForEach $styleFiles {
        Join-Path $script:StylePath $_ | Should -Exist
    }

    It 'Retirement.kql exists' {
        Join-Path $script:StylePath 'Retirement.kql' | Should -Exist
    }

    It 'Support.json exists' {
        Join-Path $script:StylePath 'Support.json' | Should -Exist
    }

    It 'The retired COM-based Build-AZSCExcelComObject.ps1 is gone (AB#5665)' {
        Join-Path $script:StylePath 'Build-AZSCExcelComObject.ps1' | Should -Not -Exist
    }
}

# =====================================================================
# SYNTAX VALIDATION
# =====================================================================
Describe 'src/report/renderers/inventory Script Syntax Validation' {
    $reportingFiles = @(
        'Build-AZSCAdvisoryReport.ps1',
        'Build-AZSCCostManagementReport.ps1',
        'Build-AZSCMonitorReport.ps1',
        'Build-AZSCPolicyReport.ps1',
        'Build-AZSCQuotaReport.ps1',
        'Build-AZSCSecCenterReport.ps1',
        'Build-AZSCSecurityOverviewReport.ps1',
        'Build-AZSCSubsReport.ps1',
        'Build-AZSCUpdateManagerReport.ps1',
        'Export-AZSCAsciiDocReport.ps1',
        'Export-AZSCJsonReport.ps1',
        'Export-AZSCMarkdownReport.ps1',
        'Export-AZSCPowerBIReport.ps1',
        'New-AZSCPowerBITemplate.ps1',
        'Start-AZSCExcelExtraData.ps1',
        'Start-AZSCExcelJob.ps1',
        'Start-AZSCExtraReports.ps1'
    )

    It '<_> parses without errors' -ForEach $reportingFiles {
        $filePath = Join-Path $script:InventoryPath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    $styleScripts = @(
        'Build-AZSCExcelChart.ps1',
        'Build-AZSCExcelChartStyle.ps1',
        'Build-AZSCExcelInitialBlock.ps1',
        'Out-AZSCReportResults.ps1',
        'Start-AZSCExcelCustomization.ps1',
        'Start-AZSCExcelOrdening.ps1'
    )

    It 'style/<_> parses without errors' -ForEach $styleScripts {
        $filePath = Join-Path $script:StylePath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}

# =====================================================================
# FUNCTION DEFINITIONS
# =====================================================================
Describe 'src/report/renderers/inventory Function Definitions' {

    It 'Build-AZSCAdvisoryReport.ps1 defines Build-AZSCAdvisoryReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCAdvisoryReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCAdvisoryReport'
    }

    It 'Build-AZSCCostManagementReport.ps1 defines Build-AZSCCostManagementReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCCostManagementReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCCostManagementReport'
    }

    It 'Build-AZSCMonitorReport.ps1 defines Build-AZSCMonitorReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCMonitorReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCMonitorReport'
    }

    It 'Build-AZSCPolicyReport.ps1 defines Build-AZSCPolicyReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCPolicyReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCPolicyReport'
    }

    It 'Build-AZSCQuotaReport.ps1 defines Build-AZSCQuotaReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCQuotaReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCQuotaReport'
    }

    It 'Build-AZSCSecCenterReport.ps1 defines Build-AZSCSecCenterReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCSecCenterReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCSecCenterReport'
    }

    It 'Build-AZSCSecurityOverviewReport.ps1 defines Build-AZSCSecurityOverviewReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCSecurityOverviewReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCSecurityOverviewReport'
    }

    It 'Build-AZSCSubsReport.ps1 defines Build-AZSCSubsReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCSubsReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCSubsReport'
    }

    It 'Build-AZSCUpdateManagerReport.ps1 defines Build-AZSCUpdateManagerReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Build-AZSCUpdateManagerReport.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCUpdateManagerReport'
    }

    It 'Export-AZSCJsonReport.ps1 defines Export-AZSCJsonReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Export-AZSCJsonReport.ps1') -Raw
        $content | Should -Match 'function\s+Export-AZSCJsonReport'
    }

    It 'Export-AZSCMarkdownReport.ps1 defines Export-AZSCMarkdownReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Export-AZSCMarkdownReport.ps1') -Raw
        $content | Should -Match 'function\s+Export-AZSCMarkdownReport'
    }

    It 'Export-AZSCAsciiDocReport.ps1 defines Export-AZSCAsciiDocReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Export-AZSCAsciiDocReport.ps1') -Raw
        $content | Should -Match 'function\s+Export-AZSCAsciiDocReport'
    }

    It 'Export-AZSCPowerBIReport.ps1 defines Export-AZSCPowerBIReport' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Export-AZSCPowerBIReport.ps1') -Raw
        $content | Should -Match 'function\s+Export-AZSCPowerBIReport'
    }

    It 'New-AZSCPowerBITemplate.ps1 defines New-AZSCPowerBITemplate' {
        $content = Get-Content (Join-Path $script:InventoryPath 'New-AZSCPowerBITemplate.ps1') -Raw
        $content | Should -Match 'function\s+New-AZSCPowerBITemplate'
    }

    It 'Start-AZSCExcelExtraData.ps1 defines Start-AZSCExcelExtraData' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Start-AZSCExcelExtraData.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCExcelExtraData'
    }

    It 'Start-AZSCExcelJob.ps1 defines Start-AZSCExcelJob' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Start-AZSCExcelJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCExcelJob'
    }

    It 'Start-AZSCExtraReports.ps1 defines Start-AZSCExtraReports' {
        $content = Get-Content (Join-Path $script:InventoryPath 'Start-AZSCExtraReports.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCExtraReports'
    }
}

Describe 'src/report/renderers/inventory/style Function Definitions' {

    It 'Build-AZSCExcelChart.ps1 defines Build-AZSCExcelChart' {
        $content = Get-Content (Join-Path $script:StylePath 'Build-AZSCExcelChart.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCExcelChart'
    }

    It 'Build-AZSCExcelChartStyle.ps1 defines Build-AZSCExcelChartStyle' {
        $content = Get-Content (Join-Path $script:StylePath 'Build-AZSCExcelChartStyle.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCExcelChartStyle'
    }

    It 'Build-AZSCExcelInitialBlock.ps1 defines Build-AZSCInitialBlock' {
        $content = Get-Content (Join-Path $script:StylePath 'Build-AZSCExcelInitialBlock.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCInitialBlock'
    }

    It 'Out-AZSCReportResults.ps1 defines Out-AZSCReportResults' {
        $content = Get-Content (Join-Path $script:StylePath 'Out-AZSCReportResults.ps1') -Raw
        $content | Should -Match 'function\s+Out-AZSCReportResults'
    }

    It 'Start-AZSCExcelCustomization.ps1 defines Start-AZSCExcelCustomization' {
        $content = Get-Content (Join-Path $script:StylePath 'Start-AZSCExcelCustomization.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCExcelCustomization'
    }

    It 'Start-AZSCExcelOrdening.ps1 defines Start-AZSCExcelOrdening' {
        $content = Get-Content (Join-Path $script:StylePath 'Start-AZSCExcelOrdening.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCExcelOrdening'
    }
}

# =====================================================================
# SUPPORT.JSON VALIDATION
# =====================================================================
Describe 'Support.json — valid JSON structure' {
    It 'Is valid JSON' {
        $jsonPath = Join-Path $script:StylePath 'Support.json'
        $content = Get-Content $jsonPath -Raw
        { $content | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Contains retirement/support data' {
        $jsonPath = Join-Path $script:StylePath 'Support.json'
        $data = Get-Content $jsonPath -Raw | ConvertFrom-Json
        $data | Should -Not -BeNullOrEmpty
    }
}

# =====================================================================
# AB#5665 — no Excel COM anywhere in the inventory renderer tree
# =====================================================================
Describe 'Inventory renderer has no Excel COM dependency (AB#5665)' {
    It 'No file actually invokes -ComObject or GetTypeFromProgID (comments describing the retired COM path are fine)' {
        $hits = Get-ChildItem -Path $script:InventoryPath -Recurse -Filter '*.ps1' |
            Select-String -Pattern '-ComObject\b|GetTypeFromProgID'
        $hits | Should -BeNullOrEmpty
    }
}

# =====================================================================
# END-TO-END — real ReportCache -> real .xlsx, through the real pipeline
# =====================================================================
Describe 'Inventory Excel end-to-end (real ReportCache -> real workbook)' -Skip:(-not $script:HasImportExcel) {

    BeforeAll {
        Import-Module ImportExcel

        # Only what this test needs -- not the whole module (no Azure auth, no
        # dependency-install bootstrap). Order doesn't matter: these are all
        # function definitions, resolved at call time.
        . (Join-Path $script:ModuleRoot 'src' 'Clear-AZTIMemory.ps1')
        . (Join-Path $script:ModuleRoot 'src' 'Start-AZTIReporOrchestration.ps1')
        . (Join-Path $script:ModuleRoot 'src' 'pipeline' 'Get-ScoutCollectorDefinition.ps1')
        . (Join-Path $script:ModuleRoot 'src' 'pipeline' 'Invoke-ScoutDeclarativeCollector.ps1')
        . (Join-Path $script:ModuleRoot 'src' 'report' 'Get-ScoutReportSectionIndex.ps1')
        . (Join-Path $script:InventoryPath 'Start-AZSCExcelJob.ps1')
        . (Join-Path $script:InventoryPath 'Start-AZSCExcelExtraData.ps1')
        . (Join-Path $script:InventoryPath 'Start-AZSCExtraReports.ps1')
        . (Join-Path $script:InventoryPath 'Build-AZSCSubsReport.ps1')
        # Start-AZSCExtraReports' Phase 10 (specialized tabs) runs unconditionally whenever
        # $ReportCache is truthy -- these four are always dot-sourced by the real module,
        # so the test needs them too even though this fixture has no data for any of them.
        . (Join-Path $script:InventoryPath 'Build-AZSCCostManagementReport.ps1')
        . (Join-Path $script:InventoryPath 'Build-AZSCSecurityOverviewReport.ps1')
        . (Join-Path $script:InventoryPath 'Build-AZSCUpdateManagerReport.ps1')
        . (Join-Path $script:InventoryPath 'Build-AZSCMonitorReport.ps1')
        . (Join-Path $script:StylePath 'Start-AZSCExcelCustomization.ps1')
        . (Join-Path $script:StylePath 'Start-AZSCExcelOrdening.ps1')
        . (Join-Path $script:StylePath 'Build-AZSCExcelChart.ps1')
        . (Join-Path $script:StylePath 'Build-AZSCExcelChartStyle.ps1')
        . (Join-Path $script:StylePath 'Build-AZSCExcelInitialBlock.ps1')

        $script:RunDir       = Join-Path $script:TempDir 'e2e'
        $script:ReportCache  = Join-Path $script:RunDir 'ReportCache'
        New-Item -ItemType Directory -Path $script:ReportCache -Force | Out-Null

        # Real Reporting-mode row shape for Modules/Public/InventoryModules/IoT/IOTHubs.ps1
        # (lifted from tests/datadump/sample-report.json's arm.iot.iOTHubs fixture) -- two
        # rows, matching exactly what ReportCache/IoT.json would hold after a live Processing
        # phase populated it.
        $script:IotHubRows = @(
            [pscustomobject]@{
                Subscription = 'scout-prod-001'; 'Resource Group' = 'rg-scout-prod-eus'
                Name = 'scout-prod-iothubs-1'; Location = 'eastus'
                'Retiring Feature' = $null; 'Retiring Date' = $null
                SKU = 'Standard'; 'SKU Tier' = 'Standard'; Role = 'sample-Role-0'; State = 'Succeeded'
                'IP Filter Rules' = '10.1.0.10'; 'Event Retention Time In Days' = '2026-01-15T10:30:00Z'
                'Event Partition Count' = 2; 'Events Path' = 'sample-Events Path-0'
                'Max Delivery Count' = 2; 'Host Name' = 'sample-Host Name-0'; 'Resource U' = 1
            },
            [pscustomobject]@{
                Subscription = 'scout-dev-001'; 'Resource Group' = 'rg-scout-dev-eus'
                Name = 'scout-dev-iothubs-1'; Location = 'eastus'
                'Retiring Feature' = $null; 'Retiring Date' = $null
                SKU = 'Standard'; 'SKU Tier' = 'Standard'; Role = 'sample-Role-1'; State = 'Succeeded'
                'IP Filter Rules' = '10.1.0.11'; 'Event Retention Time In Days' = '2026-01-15T10:30:00Z'
                'Event Partition Count' = 2; 'Events Path' = 'sample-Events Path-1'
                'Max Delivery Count' = 2; 'Host Name' = 'sample-Host Name-1'; 'Resource U' = 1
            }
        )
        @{ IOTHubs = $script:IotHubRows } | ConvertTo-Json -Depth 10 |
            Out-File (Join-Path $script:ReportCache 'IoT.json') -Encoding utf8

        # Start-AZSCExtraReports always builds the Subscriptions sheet (Build-AZSCSubsReport),
        # regardless of Quotas/SecurityCenter/Policy/Advisory flags -- give it the ExtraData
        # shape Start-AZSCExtraJobs would hand it (AB#5649).
        $script:ExtraData = @{
            Subscriptions = @(
                [pscustomobject]@{
                    Subscription = 'scout-prod-001'; SubscriptionId = '00000000-1111-2222-3333-444444444444'
                    'Resource Group' = '(test data)'; Location = '(test data)'; 'Resource Type' = '(test data)'
                    'Resources Count' = 0
                }
            )
        }

        $script:Xlsx = Join-Path $script:RunDir 'inventory-e2e.xlsx'

        Start-AZSCReporOrchestration -ReportCache $script:ReportCache -SecurityCenter ([switch]::new($false)) `
            -File $script:Xlsx -Quotas $null -SkipPolicy ([switch]::new($true)) -SkipAdvisory ([switch]::new($true)) `
            -IncludeCosts ([switch]::new($false)) -Automation ([switch]::new($false)) -TableStyle 'Light19' `
            -ExtraData $script:ExtraData

        $script:TotalRes = Start-AZSCExcelCustomization -File $script:Xlsx -TableStyle 'Light19' -PlatOS 'Windows' `
            -Subscriptions @() -ExtractionRunTime ([System.Diagnostics.Stopwatch]::new()) `
            -ProcessingRunTime ([System.Diagnostics.Stopwatch]::new()) -ReportingRunTime ([System.Diagnostics.Stopwatch]::new()) `
            -IncludeCosts ([switch]::new($false)) -RunLite $false -Overview $null -Category $null
    }

    It 'Writes the .xlsx file' {
        $script:Xlsx | Should -Exist
    }

    It 'Writes the IOTHubs data worksheet with the right row count and headers' {
        $pkg = Open-ExcelPackage -Path $script:Xlsx
        try {
            $ws = $pkg.Workbook.Worksheets['IOTHubs']
            $ws | Should -Not -BeNullOrEmpty

            $rows = Import-Excel -ExcelPackage $pkg -WorksheetName 'IOTHubs'
            @($rows).Count | Should -Be $script:IotHubRows.Count

            $expectedHeaders = @('Subscription', 'Resource Group', 'Name', 'Location',
                'Retiring Feature', 'Retiring Date', 'SKU', 'SKU Tier', 'Role', 'State',
                'IP Filter Rules', 'Event Retention Time In Days', 'Event Partition Count',
                'Events Path', 'Max Delivery Count', 'Host Name', 'Resource U')
            @($rows[0].PSObject.Properties.Name) | Should -Be $expectedHeaders
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }

    It 'Writes the Subscriptions worksheet (always built by Start-AZSCExtraReports)' {
        $pkg = Open-ExcelPackage -Path $script:Xlsx
        try {
            $pkg.Workbook.Worksheets['Subscriptions'] | Should -Not -BeNullOrEmpty
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }

    It 'Builds the Overview sheet as the first worksheet, with the AzureTabs summary table' {
        $pkg = Open-ExcelPackage -Path $script:Xlsx
        try {
            $ov = $pkg.Workbook.Worksheets['Overview']
            $ov | Should -Not -BeNullOrEmpty
            $ov.Index | Should -Be 1
            ($ov.Tables | Where-Object { $_.Name -like 'AzureTabs*' }) | Should -Not -BeNullOrEmpty
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }

    It 'Returns a non-zero total resource count' {
        $script:TotalRes | Should -BeGreaterThan 0
    }

    It 'Applied tab colors with no Excel COM (AB#5665 -- EPPlus-native only)' {
        $pkg = Open-ExcelPackage -Path $script:Xlsx
        try {
            # Compare RGB, not ToKnownColor() -- round-tripping through EPPlus's OOXML
            # ARGB storage loses the "named color" flag, so a value that started as
            # Color.FromName('DarkBlue') reads back as an unnamed color with the same RGB.
            $ov = $pkg.Workbook.Worksheets['Overview']
            $darkBlue = [System.Drawing.Color]::FromName('DarkBlue')
            $ov.TabColor.R | Should -Be $darkBlue.R
            $ov.TabColor.G | Should -Be $darkBlue.G
            $ov.TabColor.B | Should -Be $darkBlue.B
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }
}

# =====================================================================
# UNIT — Build-AZSCExcelChartStyle applies EPPlus-native styling (AB#5665)
# =====================================================================
Describe 'Build-AZSCExcelChartStyle (EPPlus-native, no COM)' -Skip:(-not $script:HasImportExcel) {

    BeforeAll {
        Import-Module ImportExcel
        . (Join-Path $script:StylePath 'Build-AZSCExcelChartStyle.ps1')

        $script:StyleXlsx = Join-Path $script:TempDir 'chartstyle-unit.xlsx'
        if (Test-Path $script:StyleXlsx) { Remove-Item $script:StyleXlsx -Force }

        1..3 | ForEach-Object { [pscustomobject]@{ Cat = "C$_"; Val = $_ * 2 } } |
            Export-Excel -Path $script:StyleXlsx -WorksheetName 'Data' -AutoSize
        '' | Export-Excel -Path $script:StyleXlsx -WorksheetName 'Overview' -MoveToStart

        $excel = Open-ExcelPackage -Path $script:StyleXlsx
        Add-PivotTable -PivotTableName 'P0' -Address $excel.Overview.Cells['A1'] -SourceWorkSheet $excel.Data `
            -PivotRows 'Cat' -PivotData @{ Val = 'Sum' } -IncludePivotChart -ChartType ColumnClustered
        $ws = $excel.Workbook.Worksheets['Overview']
        # Same shapes Build-AZSCInitialBlock draws unconditionally on every real report.
        $shape = $ws.Drawings.AddShape('AZSC', 'RoundRect')
        $shape.SetSize(445, 240)
        $shape.SetPosition(1, 0, 2, 5)
        Close-ExcelPackage $excel

        Build-AZSCExcelChartStyle -File $script:StyleXlsx
    }

    It 'Sets a non-default native EPPlus chart style on the named pivot chart (no COM ChartStyle)' {
        $pkg = Open-ExcelPackage -Path $script:StyleXlsx
        try {
            $chart = $pkg.Workbook.Worksheets['Overview'].Drawings['ChartP0']
            $chart | Should -Not -BeNullOrEmpty
            $chart.Style | Should -Not -Be ([OfficeOpenXml.Drawing.Chart.eChartStyle]::None)
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }

    It 'Fills and de-borders the AZSC info panel without Excel COM' {
        $pkg = Open-ExcelPackage -Path $script:StyleXlsx
        try {
            $shape = $pkg.Workbook.Worksheets['Overview'].Drawings['AZSC']
            $shape | Should -Not -BeNullOrEmpty
            # EPPlus doesn't round-trip alpha on a solid shape fill (reads back A=0
            # regardless of what was set) -- compare RGB only.
            $shape.Fill.Color.R | Should -Be 38
            $shape.Fill.Color.G | Should -Be 38
            $shape.Fill.Color.B | Should -Be 38
            $shape.Border.Width | Should -Be 0
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }

    It 'Never invoked Excel COM to do it' {
        Get-Process -Name 'EXCEL' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

# =====================================================================
# REGRESSION — the P6 pivot/chart defect, root-caused and fixed (AB#5666)
#
# Was: an unguarded Add-PivotTable in Build-AZSCExcelChart's P6 branch. When the
# 'Subscriptions' worksheet existed but held no rows, ImportExcel's
# `$SourceWorksheet.Cells[$SourceWorksheet.Dimension.Address]` became `Cells[$null]`
# and Add-PivotTable swallowed "Index operation failed; the array index evaluated to
# null" into a warning, so P6 and its ChartP6 chart were silently missing from the
# Overview sheet while the report still reported success.
#
# The empty sheet is a real state, not a harness artefact: Build-AZSCSubsReport always
# writes 'Subscriptions', even for a run that collected zero subscription rows.
#
# These two tests pin both halves: the empty source must be skipped cleanly (no
# warning, no crash), and a populated source must actually produce P6 + ChartP6.
# =====================================================================
Describe 'Build-AZSCExcelChart P6 pivot (AB#5666)' -Skip:(-not $script:HasImportExcel) {

    BeforeAll {
        Import-Module ImportExcel
        . (Join-Path $script:StylePath 'Build-AZSCExcelChart.ps1')

        # Builds a workbook shaped like the real one at the point Build-AZSCExcelChart runs:
        # an 'Overview' sheet carrying the TP00/TP0..TP9 title shapes
        # Build-AZSCExcelInitialBlock draws and the 'AzureTabs' summary table
        # Start-AZSCExcelCustomization writes, plus a 'Subscriptions' sheet with the columns
        # Build-AZSCSubsReport writes in non-cost mode. -Rows @() reproduces the
        # empty-but-present sheet that caused the defect.
        function script:New-P6Workbook {
            param([string] $Path, [object[]] $Rows)

            if (Test-Path $Path) { Remove-Item $Path -Force }

            $Shaped = @(
                $Rows | Select-Object 'Subscription', 'Resource Group', 'Location',
                                      'Resource Type', 'Resources Count'
            )
            $ExcelArgs = @{ Path = $Path; WorksheetName = 'Subscriptions' }
            if ($Shaped.Count -gt 0) { $ExcelArgs.TableName = 'SubsTable_1'; $ExcelArgs.TableStyle = 'Light19' }
            $Shaped | Export-Excel @ExcelArgs

            '' | Export-Excel -Path $Path -WorksheetName 'Overview' -MoveToStart

            # The P00 fallback branch draws an Add-ExcelChart over the AzureTabs table by name,
            # so it has to exist or Build-AZSCExcelChart throws before it reaches P6.
            @(
                [pscustomobject]@{ Name = 'Subscriptions'; Size = 1 }
                [pscustomobject]@{ Name = 'IOTHubs';       Size = 2 }
            ) | Export-Excel -Path $Path -WorksheetName 'Overview' -TableName 'AzureTabs' `
                             -StartRow 6 -StartColumn 1

            $pkg = Open-ExcelPackage -Path $Path
            $ws  = $pkg.Workbook.Worksheets['Overview']
            foreach ($name in @('TP00') + (0..9 | ForEach-Object { "TP$_" })) {
                $shape = $ws.Drawings.AddShape($name, 'RoundRect')
                $shape.SetSize(100, 20)
                $shape.SetPosition($ws.Drawings.Count * 2, 0, 60, 0)
            }
            Close-ExcelPackage $pkg

            return $Path
        }

        # Build-AZSCExcelChart is not an advanced function (bare Param, no [CmdletBinding()]),
        # so -WarningVariable is not available -- capture stream 3 instead.
        #
        # $tableStyle is deliberately a local here, not an argument: Build-AZSCExcelChart has no
        # TableStyle parameter and reads $TableStyle/$tableStyle out of its caller's scope, which
        # in production is Start-AZSCExcelCustomization's -TableStyle parameter. Without it every
        # PivotTableStyle in the hashtables is $null and Add-PivotTable's [TableStyles] parameter
        # cast fails, so the caller's scope has to be reproduced for the pivots to build at all.
        function script:Invoke-P6ChartBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'tableStyle',
                Justification = 'Read by Build-AZSCExcelChart through dynamic scoping, not by this function - see comment above.')]
            param($Package)
            $tableStyle = 'Light19'
            $captured = Build-AZSCExcelChart -Excel $Package -Overview $null `
                            -IncludeCosts ([switch]::new($false)) 3>&1
            return @($captured | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        }

        $script:P6Rows = @(
            [pscustomobject]@{ Subscription = 'scout-prod-001'; 'Resource Group' = 'rg-a'; Location = 'eastus';  'Resource Type' = 'microsoft.compute/virtualmachines'; 'Resources Count' = 4 }
            [pscustomobject]@{ Subscription = 'scout-dev-001';  'Resource Group' = 'rg-b'; Location = 'westus2'; 'Resource Type' = 'microsoft.storage/storageaccounts'; 'Resources Count' = 2 }
            [pscustomobject]@{ Subscription = 'scout-dev-001';  'Resource Group' = 'rg-c'; Location = 'eastus';  'Resource Type' = 'microsoft.network/virtualnetworks'; 'Resources Count' = 1 }
        )
    }

    It 'Skips P6 cleanly when the Subscriptions worksheet exists but is empty (no pivot warning)' {
        $xlsx = script:New-P6Workbook -Path (Join-Path $script:TempDir 'p6-empty.xlsx') -Rows @()

        $pkg = Open-ExcelPackage -Path $xlsx
        try {
            # Prove the precondition this regression needs: present, but no dimension.
            $pkg.Workbook.Worksheets['Subscriptions'] | Should -Not -BeNullOrEmpty
            $pkg.Workbook.Worksheets['Subscriptions'].Dimension | Should -BeNullOrEmpty

            $warnings = script:Invoke-P6ChartBuild -Package $pkg

            ($warnings | Where-Object { $_.Message -match 'P6' }) | Should -BeNullOrEmpty
            $pkg.Workbook.Worksheets['Overview'].Drawings['ChartP6'] | Should -BeNullOrEmpty
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }

    It 'Builds the P6 pivot and its ChartP6 chart when the Subscriptions worksheet has rows' {
        $xlsx = script:New-P6Workbook -Path (Join-Path $script:TempDir 'p6-populated.xlsx') -Rows $script:P6Rows

        $pkg = Open-ExcelPackage -Path $xlsx
        try {
            $warnings = script:Invoke-P6ChartBuild -Package $pkg

            ($warnings | Where-Object { $_.Message -match 'P6' }) | Should -BeNullOrEmpty

            $ov    = $pkg.Workbook.Worksheets['Overview']
            $pivot = $ov.PivotTables | Where-Object { $_.Name -eq 'P6' }
            $pivot | Should -Not -BeNullOrEmpty
            @($pivot.RowFields  | ForEach-Object { $_.Name }) | Should -Contain 'Location'
            @($pivot.PageFields | ForEach-Object { $_.Name }) | Should -Contain 'Resource Type'
            @($pivot.DataFields).Count | Should -Be 1
            $ov.Drawings['ChartP6'] | Should -Not -BeNullOrEmpty
        }
        finally {
            Close-ExcelPackage $pkg -NoSave
        }
    }
}
