#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
#Requires -Modules ImportExcel

<#
    Proof-preservation prerequisite for Epic AB#5638.

    The retired source-script equivalence suite was replaced by committed canonical output. This
    suite verifies the same two contracts against that output:

      * every processed row, including order, keys, values and null/array shape;
      * every worksheet column and cell under both tag states.

    This file does not dot-source Invoke-ScoutCollector, does not read a collector .ps1, and does
    not invoke a source-script mode. It remains executable after the collector tree is gone.
    Records are updated only through a reviewed, documented behavior change.
#>

$script:GoldenDefinitionRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/collectors'
$GoldenCollectors = @(
    foreach ($Folder in (Get-ChildItem -LiteralPath $script:GoldenDefinitionRoot -Directory | Sort-Object Name)) {
        foreach ($File in (Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.psd1' -File | Sort-Object Name)) {
            @{ Category = $Folder.Name; Name = $File.BaseName }
        }
    }
)

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:GoldenDefinitionRoot = Join-Path $script:RepoRoot 'manifests/collectors'
    $script:GoldenRoot = Join-Path $script:RepoRoot 'tests/fixtures/collector-golden'

    . (Join-Path $script:RepoRoot 'scripts/CollectorGolden.Common.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')

    # Definitions call these pure accessors from lifted expressions. They are interpreter
    # dependencies, not references to the imperative collector implementation.
    . (Join-Path $script:RepoRoot 'src/Get-AZSCSafeProperty.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZTICollectedValue.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZSCIdSegment.ps1')

    $script:FixtureCache = @{}
    $script:GoldenCache = @{}
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("scout-golden-proof-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:TempDir -ItemType Directory -Force

    function Get-GoldenFixturePath {
        param([string]$Category)

        if ($Category -eq 'Databases') {
            return Join-Path $script:RepoRoot 'tests/fixtures/databases-collector-input.json'
        }
        return Join-Path $script:RepoRoot "tests/fixtures/collector-equivalence/$Category.json"
    }

    function Get-GoldenFixture {
        param([string]$Category)

        $Path = Get-GoldenFixturePath -Category $Category
        if (-not $script:FixtureCache.ContainsKey($Path)) {
            $script:FixtureCache[$Path] = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        return $script:FixtureCache[$Path]
    }

    function Get-CommittedGolden {
        param([string]$Category, [string]$Name)

        $Key = "$Category/$Name"
        if (-not $script:GoldenCache.ContainsKey($Key)) {
            $Path = Join-Path $script:GoldenRoot "$Category/$Name.json"
            $script:GoldenCache[$Key] = Import-ScoutGoldenOutput -Path $Path -FixturePath (
                Get-GoldenFixturePath -Category $Category
            )
        }
        return $script:GoldenCache[$Key]
    }

    function Get-GoldenVerificationContext {
        param(
            [string]$Category,
            [string]$Name,
            [string]$Task = 'Processing',
            $File,
            $SmaResources,
            [bool]$InTag = $false
        )

        $Fixture = Get-GoldenFixture -Category $Category
        $Resources = if ($Category -eq 'Databases') {
            $Fixture.resources
        }
        else {
            $CollectorFixture = $Fixture.collectors.PSObject.Properties[$Name]
            if ($null -eq $CollectorFixture) {
                throw "Fixture for category '$Category' has no collector entry named '$Name'."
            }
            $CollectorFixture.Value.resources
        }

        @{
            ScriptRoot    = $script:RepoRoot
            Subscriptions = $Fixture.subscriptions
            InTag         = $InTag
            Resources     = $Resources
            Retirements   = $Fixture.retirements
            Task          = $Task
            File          = $File
            SmaResources  = $SmaResources
            TableStyle    = 'Light20'
            Unsupported   = $Fixture.unsupported
        }
    }

    function Get-LiveDeclarativeRowSet {
        param([string]$Category, [string]$Name)

        $Definition = Get-ScoutCollectorDefinition -Path (
            Join-Path $script:RepoRoot "manifests/collectors/$Category/$Name.psd1"
        )
        return @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (
            Get-GoldenVerificationContext -Category $Category -Name $Name
        ))
    }

    function Get-LiveDeclarativeWorksheet {
        param([string]$Category, [string]$Name, [bool]$InTag, $Rows)

        $Definition = Get-ScoutCollectorDefinition -Path (
            Join-Path $script:RepoRoot "manifests/collectors/$Category/$Name.psd1"
        )
        $Suffix = if ($InTag) { 'tag' } else { 'notag' }
        $Path = Join-Path $script:TempDir "$Category-$Name-$Suffix.xlsx"

        Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (
            Get-GoldenVerificationContext -Category $Category -Name $Name -Task 'Reporting' `
                -File $Path -SmaResources $Rows -InTag $InTag
        )

        return ConvertTo-ScoutWorksheetText -Path $Path -Worksheet $Definition.Export.WorksheetName
    }
}

AfterAll {
    if ($script:TempDir -and (Test-Path -LiteralPath $script:TempDir)) {
        Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Golden collector proof - coverage and independence' {
    It 'has exactly one golden record for every definition' {
        $Definitions = @(
            Get-ChildItem -LiteralPath $script:GoldenDefinitionRoot -Filter '*.psd1' -File -Recurse |
                ForEach-Object { "$($_.Directory.Name)/$($_.BaseName)" } |
                Sort-Object
        )
        $Golden = @(
            Get-ChildItem -LiteralPath $script:GoldenRoot -Filter '*.json' -File -Recurse |
                ForEach-Object { "$($_.Directory.Name)/$($_.BaseName)" } |
                Sort-Object
        )

        $Golden -join "`n" | Should -Be ($Definitions -join "`n")
    }

    It 'has no executable dependency on the imperative collector path' {
        $Files = @(
            Join-Path $script:RepoRoot 'tests/DeclarativeCollectorGolden.Tests.ps1'
            Join-Path $script:RepoRoot 'scripts/CollectorGolden.Common.ps1'
        )

        foreach ($File in $Files) {
            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$Tokens, [ref]$Errors)
            @($Errors).Count | Should -Be 0

            $ImperativeCalls = @($Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and
                $Node.GetCommandName() -eq 'Invoke-ScoutCollector'
            }, $true))
            $ImperativeCalls | Should -BeNullOrEmpty -Because "$File must verify from data, not execute the reference collector"
        }
    }

    It 'fails the comparison when a definition field is mutated in memory' {
        $Category = 'Databases'
        $Name = 'SQLSERVER'
        $Golden = Get-CommittedGolden -Category $Category -Name $Name
        $Definition = Get-ScoutCollectorDefinition -Path (
            Join-Path $script:RepoRoot "manifests/collectors/$Category/$Name.psd1"
        )
        $Definition.Fields[0].Expression = "'golden-proof-mutation'"

        $Rows = @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (
            Get-GoldenVerificationContext -Category $Category -Name $Name
        ))
        $Comparable = @($Rows | ForEach-Object { ConvertTo-ScoutComparableRow -Row $_ })

        ($Comparable -join "`n") | Should -Not -Be (@($Golden.Rows) -join "`n")
    }

    It 'preserves legacy empty subscription and tag cells without weakening StrictMode' {
        # The AIFoundry fixture deliberately includes a resource whose subscription is absent
        # from $SUB and resources with no tags.  Legacy collectors yielded blank cells in both
        # cases because missing member reads returned $null.  The declarative path must express
        # that data contract explicitly, not disable StrictMode around lifted source.
        $Rows = @(Get-LiveDeclarativeRowSet -Category 'AI' -Name 'AIFoundryHubs')

        $Rows.Count | Should -BeGreaterThan 0
        @($Rows | Where-Object { $_['Subscription'] -eq $null }).Count | Should -BeGreaterThan 0
        @($Rows | Where-Object { $_['Tag Name'] -eq '' -and $_['Tag Value'] -eq '' }).Count | Should -BeGreaterThan 0
    }

    It 'keeps the VM collector running when a prefetched SKU repeats its MemoryGB capability' -Tag 'Runtime' {
        # Live Compute SKU payloads can contain a repeated capability value.  The operational
        # envelope deliberately preserves that shape; it must not make the report calculation
        # attempt to cast an object array to [double] and skip every VM row (AB#6152).
        $Fixture = Get-GoldenFixture -Category 'Compute'
        $Resources = @($Fixture.collectors.VirtualMachine.resources)
        $Vm = @($Resources | Where-Object { $_.TYPE -eq 'microsoft.compute/virtualmachines' } | Select-Object -First 1)
        $Vm | Should -Not -BeNullOrEmpty
        $Resources += [pscustomobject]@{
            type = 'AZSC/VM/SKU'
            id = 'synthetic-vm-sku'
            properties = [pscustomobject]@{
                Location = $Vm[0].location
                SKUs = @([pscustomobject]@{
                    Name = $Vm[0].PROPERTIES.hardwareProfile.vmSize
                    Family = 'Standard_D'
                    Capabilities = @([pscustomobject]@{ Name = 'MemoryGB'; Value = @('4', '4') })
                    LocationInfo = [pscustomobject]@{ ZoneDetails = [pscustomobject]@{ Name = ''; Capabilities = [pscustomobject]@{ Name = '' } } }
                })
            }
        }
        $Resources += [pscustomobject]@{
            type = 'AZSC/Operational/VirtualMachine'
            id = $Vm[0].id
            properties = [pscustomobject]@{
                EstimatedCost = [pscustomobject]@{ properties = [pscustomobject]@{ rows = @(@('42.5', 'USD')) } }
            }
        }
        $Definition = Get-ScoutCollectorDefinition -Path (Join-Path $script:RepoRoot 'manifests/collectors/Compute/VirtualMachine.psd1')
        $Context = Get-GoldenVerificationContext -Category 'Compute' -Name 'VirtualMachine'
        $Context.Resources = $Resources

        $Rows = @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $Context)
        @($Rows | Where-Object { $_['Est. Monthly Cost (USD)'] -eq 42.5 }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Golden processing proof - <Category>/<Name>' -ForEach $GoldenCollectors {
    BeforeAll {
        $script:CollectorGolden = Get-CommittedGolden -Category $Category -Name $Name
        $script:CollectorRows = @(Get-LiveDeclarativeRowSet -Category $Category -Name $Name)
        $script:ComparableRows = @(
            $script:CollectorRows | ForEach-Object { ConvertTo-ScoutComparableRow -Row $_ }
        )
    }

    It 'is exercised by the fixture' {
        $script:ComparableRows.Count | Should -BeGreaterThan 0
    }

    It 'matches every recorded row in order' {
        $script:ComparableRows.Count | Should -Be @($script:CollectorGolden.Rows).Count
        ($script:ComparableRows -join "`n") | Should -Be (@($script:CollectorGolden.Rows) -join "`n")
    }
}

Describe 'Golden workbook proof - <Category>/<Name>' -ForEach $GoldenCollectors {
    BeforeAll {
        $script:WorkbookGolden = Get-CommittedGolden -Category $Category -Name $Name
        $script:WorkbookRows = @(Get-LiveDeclarativeRowSet -Category $Category -Name $Name)
    }

    It 'matches every recorded cell with IncludeTags <InTag>' -Tag @('GoldenWorkbook', "GoldenWorkbook_$Category") -ForEach @(
        @{ InTag = $false; GoldenProperty = 'WithoutTags' }
        @{ InTag = $true; GoldenProperty = 'WithTags' }
    ) {
        $Actual = Get-LiveDeclarativeWorksheet -Category $Category -Name $Name -InTag $InTag -Rows $script:WorkbookRows
        $Expected = $script:WorkbookGolden.Workbook.$GoldenProperty

        ($Actual -split "`n")[0] | Should -Be ($Expected -split "`n")[0] -Because 'column order is part of the report contract'
        $Actual | Should -Be $Expected
    }
}
