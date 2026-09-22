#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/report/Get-ScoutReportSectionIndex.ps1')

    $script:FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'AZSC_ReportSectionIndex_' + [guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $script:FixtureRoot -Force | Out-Null

    function Write-SectionIndexDefinition {
        param(
            [Parameter(Mandatory)] [string]$Category,
            [Parameter(Mandatory)] [string]$Name,
            [Parameter(Mandatory)] [string]$WorksheetName,
            [string[]]$ResourceTypes = @('microsoft.example/widgets')
        )

        $Directory = Join-Path $script:FixtureRoot $Category
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        $QuotedTypes = @($ResourceTypes | ForEach-Object { "        '$($_ -replace "'", "''")'" }) -join "`n"
        $DefinitionText = @"
@{
    ResourceTypes = @(
$QuotedTypes
    )
    RowLoopVariable = '1'
    Fields = @(
        @{ Name = 'Name'; Expression = '`$1.name' }
    )
    Export = @{
        WorksheetName = '$($WorksheetName -replace "'", "''")'
        Columns = @('Name')
    }
}
"@
        Set-Content -LiteralPath (Join-Path $Directory "$Name.psd1") -Value $DefinitionText -Encoding utf8
    }

    # Deliberately create these out of lexical order. Filesystem creation order must not affect
    # the index returned to report renderers.
    Write-SectionIndexDefinition -Category 'Zulu' -Name 'Second' -WorksheetName 'Zulu Second'
    Write-SectionIndexDefinition -Category 'Alpha' -Name 'ZuluName' -WorksheetName 'Alpha Zulu'
    Write-SectionIndexDefinition -Category 'Alpha' -Name 'AlphaName' -WorksheetName 'Alpha First' `
        -ResourceTypes @('AZSC/Example/Synthetic', 'microsoft.example/widgets')
    Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Alpha/README.txt') -Value 'not a definition'
}

AfterAll {
    if (Test-Path -LiteralPath $script:FixtureRoot) {
        Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force
    }
}

Describe 'Get-ScoutReportSectionIndex' {
    BeforeAll {
        $script:Index = @(Get-ScoutReportSectionIndex -DefinitionRoot $script:FixtureRoot)
    }

    It 'fails loudly when the definition root is missing' {
        $Missing = Join-Path $script:FixtureRoot 'missing'
        { Get-ScoutReportSectionIndex -DefinitionRoot $Missing } |
            Should -Throw '*Collector definition root not found*'
    }

    It 'returns only definition files in deterministic category/name order' {
        @($script:Index).Count | Should -Be 3
        @($script:Index | ForEach-Object { "$($_.Category)/$($_.Name)" }) |
            Should -Be @('Alpha/AlphaName', 'Alpha/ZuluName', 'Zulu/Second')
        @($script:Index.Order) | Should -Be @(0, 1, 2)
    }

    It 'provides the cache and worksheet fields report renderers need' {
        $Entry = $script:Index[0]
        $Entry.SectionName | Should -Be 'Alpha'
        $Entry.CacheFileName | Should -Be 'Alpha.json'
        $Entry.CacheKey | Should -Be 'AlphaName'
        $Entry.WorksheetName | Should -Be 'Alpha First'
        $Entry.DefinitionPath | Should -BeLike '*AlphaName.psd1'
    }

    It 'keeps all declared types but excludes synthetic types from the Azure type view' {
        @($script:Index[0].ResourceTypes) |
            Should -Be @('AZSC/Example/Synthetic', 'microsoft.example/widgets')
        @($script:Index[0].AzureResourceTypes) |
            Should -Be @('microsoft.example/widgets')
    }

    It 'filters categories without changing deterministic order' {
        $Filtered = @(
            Get-ScoutReportSectionIndex -DefinitionRoot $script:FixtureRoot -Category 'Zulu'
        )
        @($Filtered).Count | Should -Be 1
        $Filtered[0].Category | Should -Be 'Zulu'
        $Filtered[0].Order | Should -Be 0
    }

    It 'treats null, an empty category list, and All as no filter' {
        @(Get-ScoutReportSectionIndex -DefinitionRoot $script:FixtureRoot -Category $null).Count |
            Should -Be 3
        @(Get-ScoutReportSectionIndex -DefinitionRoot $script:FixtureRoot -Category @()).Count |
            Should -Be 3
        @(Get-ScoutReportSectionIndex -DefinitionRoot $script:FixtureRoot -Category 'All').Count |
            Should -Be 3
    }

    It 'indexes the shipped manifests without consulting the legacy collector tree' {
        $ShippedRoot = Join-Path $script:RepoRoot 'manifests/collectors'
        $Shipped = @(Get-ScoutReportSectionIndex -DefinitionRoot $ShippedRoot)
        $DefinitionCount = @(
            Get-ChildItem -LiteralPath $ShippedRoot -Recurse -Filter '*.psd1' -File
        ).Count

        @($Shipped).Count | Should -Be $DefinitionCount
        @($Shipped | Select-Object -ExpandProperty CacheKey -Unique).Count |
            Should -Be $DefinitionCount

        $IndexPath = Join-Path $script:RepoRoot 'src/report/Get-ScoutReportSectionIndex.ps1'
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $IndexPath,
            [ref]$Tokens,
            [ref]$ParseErrors
        )
        @($ParseErrors).Count | Should -Be 0
        # The token is assembled by concatenation so this test file does not match its own
        # pattern. It has to be built OUTSIDE the predicate: an assignment is not a valid
        # operand of -and, and PowerShell rejects it at parse time -- which is exactly what
        # happened. The whole container failed discovery, so every test in this file has
        # silently never run since it was written.
        $retiredCollectorToken = 'Inventory' + 'Modules'
        $LegacyPathLiterals = @(
            $Ast.FindAll(
                {
                    param($Node)
                    $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $Node.Value -match "$retiredCollectorToken|Modules[/\\]Public"
                }.GetNewClosure(),
                $true
            )
        )
        @($LegacyPathLiterals).Count | Should -Be 0
    }
}
