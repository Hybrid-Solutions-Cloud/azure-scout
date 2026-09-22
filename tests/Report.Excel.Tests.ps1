#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/report/renderers/Export-Excel.ps1 -- the raw evidence
    pack renderer plus its AB#322 visual dashboard tabs (Findings-by-Severity,
    Score-by-Area, Pass-Fail-Manual, Resource-Counts). Renders against a
    synthetic scored Findings set (same pattern tests/Report.React.Tests.ps1
    and tests/Assessment.Engine.Tests.ps1 use, via Get-Score) plus the repo's
    existing tests/datadump/sample-collect.json fixture for -Collect. No Azure
    connection, no external network access required. Requires the ImportExcel
    module to be installed locally -- skips (Pester -Skip) when it isn't,
    mirroring how the renderer itself degrades to a CSV evidence pack.
#>

# BeforeDiscovery so $script:HasImportExcel is available at Describe -Skip
# evaluation time (Pester v5 evaluates -Skip during Discovery). Recomputed
# again (redundantly, but cheaply) inside BeforeAll below -- Discovery- and
# Run-phase script scopes are not guaranteed to share variable state.
BeforeDiscovery {
    $script:HasImportExcel = [bool](Get-Module -ListAvailable -Name ImportExcel)
}

BeforeAll {
    $script:HasImportExcel = [bool](Get-Module -ListAvailable -Name ImportExcel)
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/report/renderers/Export-Excel.ps1"
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if ($script:HasImportExcel) { Import-Module ImportExcel }

    function New-ExcelTestFinding {
        param($Id, $Framework, $Area, $Status, $Severity = 'medium', $Weight = 1.0)
        [pscustomobject]@{
            Id = $Id; Title = "$Id title"; Framework = $Framework; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = 2; Evidence = @(); Remediation = "Remediate $Id."
            Manual = ($Status -eq 'Manual'); AreaWeight = $Weight
        }
    }

    $script:RawFindings = @(
        (New-ExcelTestFinding 'net-1' 'CAF' 'Networking' 'Pass' 'low')
        (New-ExcelTestFinding 'net-2' 'CAF' 'Networking' 'Fail' 'high')
        (New-ExcelTestFinding 'sec-1' 'WAF' 'Security' 'Partial' 'medium')
        (New-ExcelTestFinding 'sec-2' 'WAF' 'Security' 'Manual')
        (New-ExcelTestFinding 'sec-3' 'WAF' 'Security' 'Unknown')
    )
    $script:Scored = Get-Score -Findings $script:RawFindings

    $script:CollectPath = Join-Path $script:Root 'tests' 'datadump' 'sample-collect.json'
    $script:Collect = Get-Content $script:CollectPath -Raw | ConvertFrom-Json -Depth 100

    function Get-ExcelDashboardName {
        param($Path)
        $pkg = Open-ExcelPackage -Path $Path
        try { return @($pkg.Workbook.Worksheets | Select-Object -ExpandProperty Name) }
        finally { Close-ExcelPackage $pkg -NoSave }
    }

    function Get-ExcelZipEntryName {
        param($Path)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { return @($zip.Entries.FullName) }
        finally { $zip.Dispose() }
    }
}

Describe 'Export-Excel -- dashboard tabs (AB#322)' -Skip:(-not $script:HasImportExcel) {
    BeforeAll {
        $script:OutDir = Join-Path $script:Root 'tests' 'test-output' 'excel-dashboards'
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
        New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

        Export-ScoutEvidenceWorkbook -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Xlsx = Join-Path $script:OutDir 'assessment_evidence.xlsx'
    }
    AfterAll {
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'produces assessment_evidence.xlsx' {
        $script:Xlsx | Should -Exist
    }

    It 'creates all four dashboard worksheets when Collect has countable data' {
        $names = Get-ExcelDashboardName -Path $script:Xlsx
        foreach ($tab in 'Findings-by-Severity', 'Score-by-Area', 'Pass-Fail-Manual', 'Resource-Counts') {
            $names | Should -Contain $tab
        }
    }

    It 'hides the staging source worksheets behind each dashboard' {
        $pkg = Open-ExcelPackage -Path $script:Xlsx
        try {
            foreach ($src in '_dash_src_severity', '_dash_src_area_score', '_dash_src_pass_fail_manual', '_dash_src_resource_counts') {
                $ws = $pkg.Workbook.Worksheets[$src]
                $ws | Should -Not -BeNullOrEmpty
                $ws.Hidden | Should -Not -Be 'Visible'
            }
        }
        finally { Close-ExcelPackage $pkg -NoSave }
    }

    It 'applies a consistent, distinct tab color to every dashboard sheet' {
        $pkg = Open-ExcelPackage -Path $script:Xlsx
        try {
            $colors = foreach ($tab in 'Findings-by-Severity', 'Score-by-Area', 'Pass-Fail-Manual', 'Resource-Counts') {
                $pkg.Workbook.Worksheets[$tab].TabColor.ToArgb()
            }
            @($colors | Select-Object -Unique).Count | Should -Be 1
            $colors[0] | Should -Not -Be 0
        }
        finally { Close-ExcelPackage $pkg -NoSave }
    }

    It 'positions dashboard tabs before the raw per-area evidence sheets' {
        $pkg = Open-ExcelPackage -Path $script:Xlsx
        try {
            $dashIndex = $pkg.Workbook.Worksheets['Resource-Counts'].Index
            $areaIndex = $pkg.Workbook.Worksheets['Networking'].Index
            $dashIndex | Should -BeLessThan $areaIndex
        }
        finally { Close-ExcelPackage $pkg -NoSave }
    }

    It 'writes valid, well-formed native PivotTable/PivotChart OOXML parts for every dashboard' {
        $entries = Get-ExcelZipEntryName -Path $script:Xlsx
        (@($entries | Where-Object { $_ -match '^xl/pivotTables/pivotTable\d+\.xml$' })).Count | Should -Be 4
        (@($entries | Where-Object { $_ -match '^xl/pivotCache/pivotCacheDefinition\d+\.xml$' })).Count | Should -Be 4
        (@($entries | Where-Object { $_ -match '^xl/charts/chart\d+\.xml$' })).Count | Should -Be 4
        $entries | Should -Contain 'xl/workbook.xml'
    }

    It 'still emits the raw per-area evidence sheets after the dashboards' {
        $names = Get-ExcelDashboardName -Path $script:Xlsx
        $names | Should -Contain 'Networking'
        $names | Should -Contain 'Security'
    }
}

Describe 'Export-Excel -- dashboards omit when data is absent (no empty dashboards)' -Skip:(-not $script:HasImportExcel) {
    BeforeAll {
        $script:OutDir = Join-Path $script:Root 'tests' 'test-output' 'excel-dashboards-nocollect'
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
        New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

        Export-ScoutEvidenceWorkbook -Findings $script:Scored -Collect $null -OutputPath $script:OutDir
        $script:Xlsx = Join-Path $script:OutDir 'assessment_evidence.xlsx'
    }
    AfterAll {
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still produces the three findings-based dashboards' {
        $names = Get-ExcelDashboardName -Path $script:Xlsx
        foreach ($tab in 'Findings-by-Severity', 'Score-by-Area', 'Pass-Fail-Manual') {
            $names | Should -Contain $tab
        }
    }

    It 'omits Resource-Counts entirely when -Collect is $null' {
        $names = Get-ExcelDashboardName -Path $script:Xlsx
        $names | Should -Not -Contain 'Resource-Counts'
        $names | Should -Not -Contain '_dash_src_resource_counts'
    }
}

Describe 'Export-Excel -- $null -Findings crash class (StrictMode sweep)' {
    # $Findings.Findings previously dotted directly into a possibly-$null
    # $Findings, throwing PropertyNotFoundException under Set-StrictMode
    # -Version Latest instead of degrading gracefully like every other
    # renderer in this folder (which all read through Get-ScoutExcelProp).
    It 'does not throw when -Findings is $null' {
        $dir = Join-Path $script:Root 'tests' 'test-output' 'excel-null-findings'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        try {
            { Export-ScoutEvidenceWorkbook -Findings $null -Collect $null -OutputPath $dir } | Should -Not -Throw
        }
        finally {
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Get-ScoutExcelResourceCount' {
    It 'returns an empty array for a $null Collect' {
        @(Get-ScoutExcelResourceCount -Collect $null).Count | Should -Be 0
    }

    It 'flattens category/sub-property arrays into Category/ResourceType/Count rows' {
        $collect = [pscustomobject]@{
            networking = [pscustomobject]@{
                virtualNetworks = @(@{ id = 1 }, @{ id = 2 })
                subnets         = @()
            }
            subscriptions = @(@{ id = 'sub-1' })
            _meta         = [pscustomobject]@{ scope = 'ArmOnly' }
        }
        $rows = @(Get-ScoutExcelResourceCount -Collect $collect)
        $vnetRow = $rows | Where-Object { $_.Category -eq 'networking' -and $_.ResourceType -eq 'virtualNetworks' }
        $vnetRow | Should -Not -BeNullOrEmpty
        $vnetRow.Count | Should -Be 2
        ($rows.ResourceType) | Should -Not -Contain 'subnets'
        $subRow = $rows | Where-Object { $_.Category -eq 'subscriptions' }
        $subRow | Should -Not -BeNullOrEmpty
        $subRow.Count | Should -Be 1
    }
}
