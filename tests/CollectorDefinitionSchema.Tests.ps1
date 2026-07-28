#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#5661 -- the schema-validation gate for declarative collector definitions.

    A `.psd1` definition is data that is executed, and almost every way of getting one wrong fails
    SILENTLY: an Export column no field produces is a blank column, a SetupVariable the preamble
    stopped assigning is an empty join, a definition that has drifted from its collector is two
    paths quietly running different source. None of those is a crash, and none of them is caught by
    the equivalence suite when the drift happens to be behaviour-preserving on the fixture --
    Compute/AvailabilitySets.psd1 sat drifted for a whole release with a green equivalence test.

    Two halves, deliberately:

      * the checks FIRE -- scripts/Test-ScoutCollectorDefinition.ps1 exits non-zero, and names the
        file, for each kind of breakage. Proven by writing a deliberately broken definition into a
        throwaway tree and running the real script against it. A gate nobody has ever seen fail is
        not a gate.
      * the real tree PASSES -- every definition under manifests/collectors satisfies all of it.

    The same script runs as its own CI step (.github/workflows/ci.yml) so a violation is annotated
    on the offending file in the PR diff rather than buried in a Pester summary; this file is what
    makes it run locally too.
#>

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:Validator  = Join-Path $script:RepoRoot 'scripts/Test-ScoutCollectorDefinition.ps1'

    # A private sandbox root. NOT under $env:TEMP\AZSC_*: about eighteen test files share a fixed
    # path there and Remove-Item it in their own BeforeAll.
    $script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("azsc-defschema-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:Sandbox -Force

    function New-BrokenDefinitionTree {
        <#
            Write ONE definition into a fresh throwaway tree and run the real validator over it.
            Returns the exit code and the captured output, so a test can assert both that it failed
            and that it said why.
        #>
        param([Parameter(Mandatory)][string]$Body)

        $Root = Join-Path $script:Sandbox ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $Root 'Probe') -Force
        Set-Content -LiteralPath (Join-Path $Root 'Probe/Broken.psd1') -Value $Body -Encoding utf8

        # -SkipDriftCheck / -SkipAllowListStaleCheck: a throwaway tree has no SourceCollector in
        # this repo, and contains none of the five allow-listed blank columns, so both of those
        # checks would fire for reasons that have nothing to do with what is being probed.
        $Output = & pwsh -NoProfile -File $script:Validator -DefinitionRoot $Root `
            -SkipDriftCheck -SkipAllowListStaleCheck 2>&1 | Out-String
        [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $Output }
    }

    # A definition that is valid in every respect, used as the base each probe breaks ONE thing in.
    # If this did not pass, every "it fails" assertion below would be vacuous.
    $script:ValidBody = @'
@{
    ResourceTypes = @('microsoft.sql/servers')
    ResourceTypeMatching = 'Grouped'
    RowLoopVariable = '1'
    Fields = @(
        @{ Name = 'ID';   Expression = '$1.id' }
        @{ Name = 'Name'; Expression = '$1.NAME' }
    )
    Export = @{
        WorksheetName = 'Probe'
        Columns = @('Name')
        # Explicit and EMPTY. Omitting the key falls back to the loader's historic default of
        # @('Tag Name', 'Tag Value'), and this probe declares neither as a Field -- which the
        # validator correctly reports as two columns that would be blank under -IncludeTags. Every
        # generated definition writes TagColumns explicitly, so the default only bites hand-written
        # ones like this.
        TagColumns = @()
    }
    SourceCollector = 'Modules/Public/InventoryModules/Databases/SQLSERVER.ps1'
}
'@
}

AfterAll {
    if ($script:Sandbox -and (Test-Path -LiteralPath $script:Sandbox)) {
        Remove-Item -LiteralPath $script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Collector definition validation (AB#5661) -- the gate fires' {
    It 'passes a definition that is correct in every respect' {
        $Result = New-BrokenDefinitionTree -Body $script:ValidBody
        $Result.ExitCode | Should -Be 0 -Because "otherwise every failure assertion below is vacuous. Output:`n$($Result.Output)"
    }

    It 'fails a definition that is not valid PowerShell data at all' {
        $Result = New-BrokenDefinitionTree -Body '@{ ResourceTypes = @( this is not a psd1'
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'Broken.psd1'
    }

    It 'fails a definition whose Export names a column no Field produces' {
        # THE defect this whole file exists for: Select-Object does not require the property to
        # exist, so this ships as a permanently blank column rather than as an error.
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "Columns = @\('Name'\)", "Columns = @('Name', 'Nmae')")
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match "Nmae"
        $Result.Output   | Should -Match 'BLANK column'
    }

    It 'fails a definition whose ResourceTypeMatching is not a recognised value' {
        # Not a fallback to the default: the two modes produce different ROW ORDER for a multi-type
        # collector, so guessing reorders a worksheet.
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "'Grouped'", "'Ungrouped'")
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'ResourceTypeMatching'
    }

    It 'fails a definition with no ResourceTypes' {
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "@\('microsoft.sql/servers'\)", '@()')
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'ResourceTypes'
    }

    It 'fails a definition that declares the same Field name twice' {
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "Name = 'Name'; Expression = '\`$1.NAME'", "Name = 'ID'; Expression = '`$1.NAME'")
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'more than once'
    }

    It 'fails a definition whose TagColumnsBefore names a column that does not exist' {
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "Columns = @\('Name'\)", "Columns = @('Name')`n        TagColumnsBefore = 'Not A Column'")
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'TagColumnsBefore'
    }

    It 'fails a definition whose SetupVariables the SetupPreamble never assigns' {
        # Written out in full rather than patched into $ValidBody with -replace: the replacement
        # side of -replace treats `$` as a group reference, so a body containing `$Resources` and
        # `$_` comes out mangled and the definition then fails for the wrong reason.
        $Body = @'
@{
    ResourceTypes = @('microsoft.sql/servers')
    ResourceTypeMatching = 'Grouped'
    RowLoopVariable = '1'
    SetupPreamble = '$Partners = $Resources | Where-Object { $_.TYPE -eq ''microsoft.sql/servers/databases'' }'
    SetupVariables = @('Partners', 'NeverAssigned')
    Fields = @(
        @{ Name = 'ID';   Expression = '$1.id' }
        @{ Name = 'Name'; Expression = '$1.NAME' }
    )
    Export = @{
        WorksheetName = 'Probe'
        Columns = @('Name')
        TagColumns = @()
    }
    SourceCollector = 'Modules/Public/InventoryModules/Databases/SQLSERVER.ps1'
}
'@
        $Result = New-BrokenDefinitionTree -Body $Body
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'NeverAssigned'
    }

    It 'fails a SetupPreamble with no SetupVariables, and SetupVariables with no SetupPreamble' {
        # Both directions, because either one alone is a section that reads as if it were doing
        # something and is not -- the same reason a FilterPreamble without a filter is an error.
        $Orphaned = $script:ValidBody -replace "RowLoopVariable = '1'", "RowLoopVariable = '1'`n    SetupPreamble = '`$X = 1'"
        (New-BrokenDefinitionTree -Body $Orphaned).ExitCode | Should -Be 1

        $Dangling = $script:ValidBody -replace "RowLoopVariable = '1'", "RowLoopVariable = '1'`n    SetupVariables = @('X')"
        (New-BrokenDefinitionTree -Body $Dangling).ExitCode | Should -Be 1
    }

    It 'fails a definition whose SetupVariables carry a leading dollar sign' {
        # `Get-Variable -Name '$X'` looks for a variable literally called '$X' and finds nothing --
        # a name that never binds, silently.
        $Body = $script:ValidBody -replace "RowLoopVariable = '1'", @"
RowLoopVariable = '1'
    SetupPreamble = '`$X = 1'
    SetupVariables = @('`$X')
"@
        $Result = New-BrokenDefinitionTree -Body $Body
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'dollar sign'
    }

    It 'fails a worksheet name longer than Excel''s 31-character limit' {
        # AB#5661 acceptance criterion: over-length worksheet names must FAIL THE BUILD rather than
        # warn at render time. Export-Excel hits this inside EPPlus, after a full collection run.
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "WorksheetName = 'Probe'", "WorksheetName = 'A Worksheet Name That Is Far Too Long For Excel'")
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match '31'
    }

    It 'fails a worksheet name containing a character Excel does not allow' {
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "WorksheetName = 'Probe'", "WorksheetName = 'Probe/Sheet'")
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'does not allow'
    }

    It 'fails two definitions that claim the same worksheet name' {
        # The other AB#5661 criterion, and the only check that cannot be decided from one file.
        # Case differs deliberately: Excel compares sheet names case-insensitively, so 'Probe' and
        # 'PROBE' collide and a naive ordinal comparison would miss it.
        $Root = Join-Path $script:Sandbox ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $Root 'Probe') -Force
        Set-Content -LiteralPath (Join-Path $Root 'Probe/One.psd1') -Value $script:ValidBody -Encoding utf8
        Set-Content -LiteralPath (Join-Path $Root 'Probe/Two.psd1') -Encoding utf8 `
            -Value ($script:ValidBody -replace "WorksheetName = 'Probe'", "WorksheetName = 'PROBE'")

        $Output = & pwsh -NoProfile -File $script:Validator -DefinitionRoot $Root `
            -SkipDriftCheck -SkipAllowListStaleCheck 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $Output | Should -Match 'same Excel worksheet name'
        $Output | Should -Match 'One'
        $Output | Should -Match 'Two'
    }

    It 'accepts retired SourceCollector provenance without making it a runtime dependency' {
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace 'Databases/SQLSERVER.ps1', 'Databases/NoSuchCollector.ps1')
        $Result.ExitCode | Should -Be 0
    }

    It 'fails a definition whose Preamble does not parse' {
        $Result = New-BrokenDefinitionTree -Body ($script:ValidBody -replace "RowLoopVariable = '1'", "RowLoopVariable = '1'`n    Preamble = 'if (`$true) { '")
        $Result.ExitCode | Should -Be 1
        $Result.Output   | Should -Match 'Preamble'
    }
}

Describe 'Collector definition validation (AB#5661) -- the real tree passes' {
    It 'every definition under manifests/collectors passes every v3 catalog check' {
        $Output = & pwsh -NoProfile -File $script:Validator 2>&1 | Out-String
        $Code = $LASTEXITCODE
        $Code | Should -Be 0 -Because "collector definitions must be valid and current:`n$Output"
    }
}
