#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
#Requires -Modules ImportExcel

<#
    AB#5656 / AB#5659 — the equivalence proof for declarative collector definitions.

    Feature AB#5656 replaces a hand-written collector .ps1 with a `.psd1` describing WHAT to
    filter and WHAT fields to produce, interpreted by one shared function
    (`Invoke-ScoutDeclarativeCollector`). The entire value of that change rests on a claim that
    nothing else in the repo checks: that the declarative definition produces THE SAME ROWS as
    the imperative collector it replaces. A schema-validation test proves a `.psd1` is
    well-formed; it proves nothing about whether the report changed.

    These tests run BOTH implementations over ONE shared fixture input and compare the results:

      * PROCESSING — every emitted row, in order, key by key and value by value. Not counts, not
        a sample: `tests/fixtures/databases-collector-input.json` is fed to
        `Invoke-ScoutCollector` (the legacy path, executing the original .ps1) and to
        `Invoke-ScoutDeclarativeCollector` (the new path, interpreting the .psd1), and the two
        row sequences must be indistinguishable.

      * REPORTING — both paths write a real .xlsx via Export-Excel and the two workbooks are
        read back and compared cell by cell, under BOTH `-InTag:$false` and `-InTag:$true`. The
        tag case is not redundant: the original collectors add their two Tag columns inside an
        `if ($InTag)` block that is NOT at the end of the column list, so a definition format
        that merely "appends TagColumns" silently reorders the last columns of every tagged
        sheet. That defect was found by this test and fixed via `Export.TagColumnsBefore`.

    The fixture is a superset of the mock estate `Databases.Module.Tests.ps1` already uses, plus
    the edge cases equivalence actually turns on: an untagged resource (the `$Tags = '0'`
    fallback), a two-tag resource (multi-row expansion and the ResUCount 1->0 transition), a
    `master` database (SQLDB's AdditionalFilter), resources with no privateEndpointConnections
    (the 'NONE' sentinel in the AdditionalRowLoops collectors), a resource whose subscription is
    absent from $Sub, a resource carrying two retirements (the many-branch of the retirement
    fold), an interleaved second `microsoft.cache/redis` after the `redisenterprise` entry (row
    ORDER in the one multi-type collector), and a storage account no Databases collector may
    ever match.

    Scope: the Databases category (13 collectors) is the pilot conversion — 100% pure-shaping per
    the audit (docs/design/collector-audit.md). The other 163 collectors have no definition yet
    and are deliberately not covered here.
#>

# Discovery-time list: one Describe per converted collector, so a failure names the collector.
$DeclarativeCollectors = @(
    @{ Name = 'CosmosDB' }
    @{ Name = 'MariaDB' }
    @{ Name = 'MySQL' }
    @{ Name = 'MySQLflexible' }
    @{ Name = 'POSTGRE' }
    @{ Name = 'POSTGREFlexible' }
    @{ Name = 'RedisCache' }
    @{ Name = 'SQLDB' }
    @{ Name = 'SQLMI' }
    @{ Name = 'SQLMIDB' }
    @{ Name = 'SQLPOOL' }
    @{ Name = 'SQLSERVER' }
    @{ Name = 'SQLVM' }
)

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')

    $script:CollectorDir  = Join-Path $script:RepoRoot 'Modules/Public/InventoryModules/Databases'
    $script:DefinitionDir = Join-Path $script:RepoRoot 'manifests/collectors/Databases'

    $script:Fixture = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests/fixtures/databases-collector-input.json') -Raw |
        ConvertFrom-Json

    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("scout-declarative-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:TempDir -ItemType Directory -Force

    # The ten-key context both paths receive. IDENTICAL OBJECT REFERENCES, deliberately: if each
    # path got its own deserialisation of the fixture, a difference in how the two were built
    # could mask (or manufacture) a difference in what the two produced.
    function New-EquivalenceContext {
        param([string]$Task = 'Processing', $File, $SmaResources, [bool]$InTag = $false)
        @{
            ScriptRoot   = $script:RepoRoot
            Subscriptions = $script:Fixture.subscriptions
            InTag        = $InTag
            Resources    = $script:Fixture.resources
            Retirements  = $script:Fixture.retirements
            Task         = $Task
            File         = $File
            SmaResources = $SmaResources
            TableStyle   = 'Light20'
            Unsupported  = $script:Fixture.unsupported
        }
    }

    function Get-LegacyRows {
        param([string]$Name)
        $Descriptor = [PSCustomObject]@{
            Name           = $Name
            FolderCategory = 'Databases'
            Path           = (Join-Path $script:CollectorDir "$Name.ps1")
        }
        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-EquivalenceContext)
        if (-not $Result.Success) { throw "Legacy collector '$Name' failed: $($Result.Error)" }
        @($Result.Rows)
    }

    function Get-DeclarativeRows {
        param([string]$Name)
        $Definition = Get-ScoutCollectorDefinition -Path (Join-Path $script:DefinitionDir "$Name.psd1")
        @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (New-EquivalenceContext))
    }

    # Render one row's value as a comparable string.
    #
    # Values are not all scalars: 'Zone' is a string[], several fields are $null, some are
    # numeric, and the retirement fold produces strings built from arrays. Comparing with -eq
    # would silently pass on an array-vs-scalar difference (PowerShell would compare
    # element-wise and return an array, which is truthy). A canonical JSON rendering compares
    # the SHAPE as well as the content, and distinguishes $null from '' from @().
    function ConvertTo-ComparableValue {
        param($Value)
        if ($null -eq $Value) { return '<null>' }
        if ($Value -is [string]) { return "s:$Value" }
        try { return 'j:' + (ConvertTo-Json -InputObject $Value -Depth 12 -Compress) }
        catch { return 'x:' + [string]$Value }
    }

    function ConvertTo-ComparableRow {
        param($Row)
        # Row keys come from a hashtable literal, so their enumeration order is not meaningful --
        # sort them. Column ORDER is a property of the Export section and is tested separately,
        # against the real worksheet.
        $Keys = @($Row.Keys | Sort-Object)
        ($Keys | ForEach-Object { "$_=$(ConvertTo-ComparableValue -Value $Row[$_])" }) -join '|'
    }

    # Run one collector's Reporting branch both ways and read the two sheets back.
    function Get-ReportingComparison {
        param([string]$Name, [bool]$InTag)

        $Rows = @(Get-LegacyRows -Name $Name)
        if ($Rows.Count -eq 0) { return $null }

        $Suffix     = if ($InTag) { 'tag' } else { 'notag' }
        $LegacyFile = Join-Path $script:TempDir "$Name-legacy-$Suffix.xlsx"
        $DeclFile   = Join-Path $script:TempDir "$Name-decl-$Suffix.xlsx"

        $Descriptor = [PSCustomObject]@{
            Name = $Name; FolderCategory = 'Databases'
            Path = (Join-Path $script:CollectorDir "$Name.ps1")
        }
        $LegacyResult = Invoke-ScoutCollector -Collector $Descriptor -Context (
            New-EquivalenceContext -Task 'Reporting' -File $LegacyFile -SmaResources $Rows -InTag $InTag)
        if (-not $LegacyResult.Success) { throw "Legacy reporting for '$Name' failed: $($LegacyResult.Error)" }

        $Definition = Get-ScoutCollectorDefinition -Path (Join-Path $script:DefinitionDir "$Name.psd1")
        Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (
            New-EquivalenceContext -Task 'Reporting' -File $DeclFile -SmaResources $Rows -InTag $InTag)

        [PSCustomObject]@{
            LegacyFile = $LegacyFile
            DeclFile   = $DeclFile
            Worksheet  = $Definition.Export.WorksheetName
        }
    }

    function ConvertTo-SheetText {
        param([string]$Path, [string]$Worksheet)
        $Sheet = Import-Excel -Path $Path -WorksheetName $Worksheet
        $Sheet = @($Sheet)
        if ($Sheet.Count -eq 0) { return '<empty>' }
        $Columns = @($Sheet[0].PSObject.Properties.Name)
        $Lines = [System.Collections.Generic.List[string]]::new()
        $Lines.Add(($Columns -join "`t"))
        foreach ($Row in $Sheet) {
            $Lines.Add((($Columns | ForEach-Object { [string]$Row.$_ }) -join "`t"))
        }
        $Lines -join "`n"
    }
}

AfterAll {
    if ($script:TempDir -and (Test-Path -LiteralPath $script:TempDir)) {
        Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Declarative collector definitions — coverage' {
    It 'has a .psd1 definition for every Databases collector' {
        $Collectors  = @(Get-ChildItem -LiteralPath $script:CollectorDir -Filter '*.ps1' | ForEach-Object BaseName | Sort-Object)
        $Definitions = @(Get-ChildItem -LiteralPath $script:DefinitionDir -Filter '*.psd1' | ForEach-Object BaseName | Sort-Object)
        ($Definitions -join ',') | Should -Be ($Collectors -join ',')
    }

    It 'loads every definition through the schema validator without error' {
        foreach ($File in (Get-ChildItem -LiteralPath $script:DefinitionDir -Filter '*.psd1')) {
            { Get-ScoutCollectorDefinition -Path $File.FullName } | Should -Not -Throw
        }
    }

    It 'reports the definition back through Get-ScoutCollector without a second discovery mechanism' {
        $Found = @(Get-ScoutCollector -InventoryRoot (Join-Path $script:RepoRoot 'Modules/Public/InventoryModules') -Category 'Databases')
        @($Found).Count | Should -Be 13
        @($Found | Where-Object { -not $_.HasDeclarativeDefinition }) | Should -BeNullOrEmpty
        foreach ($Collector in $Found) {
            $Collector.DefinitionPath | Should -Exist
            $Collector.Contract | Should -Be 'Standard'
        }
    }

    It 'reports HasDeclarativeDefinition = $false for an unconverted category, which is not a defect' {
        $Security = @(Get-ScoutCollector -InventoryRoot (Join-Path $script:RepoRoot 'Modules/Public/InventoryModules') -Category 'Security')
        @($Security).Count | Should -BeGreaterThan 0
        @($Security | Where-Object { $_.HasDeclarativeDefinition }) | Should -BeNullOrEmpty
        @($Security | Where-Object { $null -ne $_.DefinitionPath }) | Should -BeNullOrEmpty
    }
}

Describe 'Processing equivalence — <Name>' -ForEach $DeclarativeCollectors {
    BeforeAll {
        # @() at the CALL SITE, not just inside the helper: a function returning a one-element
        # array unrolls it on the way out, so $script:Legacy would be the bare hashtable and
        # $script:Legacy[0] would index it by the KEY 0 and hand back $null.
        $script:Legacy      = @(Get-LegacyRows -Name $Name)
        $script:Declarative = @(Get-DeclarativeRows -Name $Name)
    }

    It 'the fixture actually exercises this collector (a vacuous pass proves nothing)' {
        @($script:Legacy).Count | Should -BeGreaterThan 0
    }

    It 'emits the same number of rows' {
        @($script:Declarative).Count | Should -Be @($script:Legacy).Count
    }

    It 'emits the same field names on every row' {
        for ($i = 0; $i -lt @($script:Legacy).Count; $i++) {
            $LegacyKeys = (@($script:Legacy[$i].Keys | Sort-Object) -join ',')
            $DeclKeys   = (@($script:Declarative[$i].Keys | Sort-Object) -join ',')
            $DeclKeys | Should -Be $LegacyKeys -Because "row $i of $Name must carry the same columns"
        }
    }

    It 'emits the same values, in the same row order' {
        for ($i = 0; $i -lt @($script:Legacy).Count; $i++) {
            $L = ConvertTo-ComparableRow -Row $script:Legacy[$i]
            $D = ConvertTo-ComparableRow -Row $script:Declarative[$i]
            $D | Should -Be $L -Because "row $i of $Name must be identical to the imperative collector's"
        }
    }

    It 'expands tags into one row per tag, with Resource U set on the first row only' {
        # Guards the interpreter's own two bound variables ($Tag, $ResUCount) rather than
        # trusting that "same as legacy" also means "correct" — legacy and declarative could in
        # principle be identically wrong here, and this is the row-multiplying logic.
        $ByResource = $script:Declarative | Group-Object { $_['ID'] }
        foreach ($Group in $ByResource) {
            $Units = @($Group.Group | ForEach-Object { [int]$_['Resource U'] })
            ($Units | Measure-Object -Sum).Sum | Should -Be 1 -Because "resource $($Group.Name) must count as exactly one resource unit"
            $Units[0] | Should -Be 1
        }
    }
}

Describe 'Reporting equivalence — <Name>' -ForEach $DeclarativeCollectors {
    It 'writes an identical worksheet with InTag disabled' {
        $Comparison = Get-ReportingComparison -Name $Name -InTag $false
        $Comparison | Should -Not -BeNullOrEmpty
        $Comparison.LegacyFile | Should -Exist
        $Comparison.DeclFile   | Should -Exist
        (ConvertTo-SheetText -Path $Comparison.DeclFile   -Worksheet $Comparison.Worksheet) |
            Should -Be (ConvertTo-SheetText -Path $Comparison.LegacyFile -Worksheet $Comparison.Worksheet)
    }

    It 'writes an identical worksheet with InTag enabled, including where the Tag columns sit' {
        $Comparison = Get-ReportingComparison -Name $Name -InTag $true
        $Comparison | Should -Not -BeNullOrEmpty
        $LegacyText = ConvertTo-SheetText -Path $Comparison.LegacyFile -Worksheet $Comparison.Worksheet
        $DeclText   = ConvertTo-SheetText -Path $Comparison.DeclFile   -Worksheet $Comparison.Worksheet

        # Assert the header line explicitly as well as the whole sheet: a column-ORDER regression
        # and a column-CONTENT regression are different bugs and should not report as one.
        ($DeclText -split "`n")[0] | Should -Be ($LegacyText -split "`n")[0]
        $DeclText | Should -Be $LegacyText
    }
}

Describe 'Declarative interpreter — the properties the schema depends on' {
    It 'drops the master database, honouring SQLDB AdditionalFilter' {
        $Rows = @(Get-DeclarativeRows -Name 'SQLDB')
        @($Rows | Where-Object { $_['Name'] -eq 'master' }) | Should -BeNullOrEmpty
        $Rows.Count | Should -BeGreaterThan 0
    }

    It 'keeps every declared resource type grouped in ResourceTypes order, as the += original did' {
        # RedisCache is the only multi-type Databases collector. The fixture deliberately places a
        # second microsoft.cache/redis AFTER the microsoft.cache/redisenterprise entry, so a naive
        # single `-contains` pass over $Resources would interleave the two and reorder the sheet.
        $Rows  = @(Get-DeclarativeRows -Name 'RedisCache')
        $Types = @($Rows | ForEach-Object { $_['ID'] } | ForEach-Object {
            if ($_ -match '/providers/(microsoft\.cache/[^/]+)/') { $Matches[1] } else { 'unknown' }
        })
        $Types | Should -Not -Contain 'unknown'
        $FirstEnterprise = [array]::IndexOf($Types, 'microsoft.cache/redisenterprise')
        $FirstEnterprise | Should -BeGreaterThan 0
        @($Types[$FirstEnterprise..($Types.Count - 1)] | Where-Object { $_ -eq 'microsoft.cache/redis' }) |
            Should -BeNullOrEmpty -Because 'every redis row must precede every redisenterprise row'
    }

    It 'never emits a row for a resource type it did not declare' {
        # Re-derived from disk rather than read from the discovery-time $DeclarativeCollectors:
        # a file-scope variable used to build -ForEach is not in scope inside an It at run time.
        # Resolved via the fixture resource's own TYPE, not by parsing the ARM id: a sub-resource
        # id interleaves type and name segments (.../providers/microsoft.sql/servers/sql-prod/
        # databases/appdb), so the type is not a contiguous substring of the id.
        $TypeById = @{}
        foreach ($Resource in $script:Fixture.resources) { $TypeById[$Resource.id] = $Resource.TYPE }

        foreach ($Entry in (Get-ChildItem -LiteralPath $script:DefinitionDir -Filter '*.psd1')) {
            $Definition = Get-ScoutCollectorDefinition -Path $Entry.FullName
            foreach ($Row in @(Get-DeclarativeRows -Name $Entry.BaseName)) {
                $TypeById.ContainsKey($Row['ID']) | Should -BeTrue -Because "$($Entry.BaseName) emitted a row for an id not in the fixture: $($Row['ID'])"
                @($Definition.ResourceTypes) | Should -Contain $TypeById[$Row['ID']] -Because "$($Entry.BaseName) emitted a row for $($Row['ID'])"
            }
        }
    }

    It 'rejects a definition whose TagColumnsBefore names a column that does not exist' {
        # The insert position silently falling back to "append" is exactly the defect the key was
        # added to prevent, so a bad value must fail loudly at load rather than reorder a sheet.
        $Bad = Join-Path $script:TempDir 'bad-tagcolumnsbefore.psd1'
        Set-Content -LiteralPath $Bad -Encoding utf8 -Value @'
@{
    ResourceTypes = @('microsoft.sql/servers')
    RowLoopVariable = '1'
    Fields = @( @{ Name = 'ID'; Expression = '$1.id' } )
    Export = @{
        WorksheetName = 'X'
        Columns = @('ID')
        TagColumnsBefore = 'Not A Column'
    }
}
'@
        { Get-ScoutCollectorDefinition -Path $Bad } | Should -Throw '*TagColumnsBefore*'
    }
}
