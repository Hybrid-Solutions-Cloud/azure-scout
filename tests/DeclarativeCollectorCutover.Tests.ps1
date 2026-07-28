#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutCollector.ps1')
}

Describe 'v3 declarative collector cutover' {
    It 'discovers the shipped manifest catalog without an InventoryModules tree' {
        $Definitions = Join-Path $script:RepoRoot 'manifests/collectors'
        $Collectors = @(Get-ScoutCollector -DefinitionRoot $Definitions)

        $Collectors.Count | Should -Be 174
        @($Collectors | Where-Object { -not $_.HasDeclarativeDefinition }).Count | Should -Be 0
        @($Collectors | Where-Object { $_.Path }).Count | Should -Be 0
    }

    It 'exposes no imperative execution switch on the runtime entry point' {
        $Command = Get-Command Invoke-ScoutCollector
        $Command.Parameters.ContainsKey('Imperative') | Should -BeFalse
        $Command.Parameters.ContainsKey('ForceImperativeCollectors') | Should -BeFalse

        $Runtime = Get-Content (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutCollector.ps1') -Raw
        $Runtime | Should -Not -Match 'Set-StrictMode\s+-Off'
        $Runtime | Should -Not -Match 'ImperativeCapture|ImperativeFallback'
    }

    It 'contains an invalid definition as a declarative failure rather than executing another path' {
        $Root = Join-Path ([System.IO.Path]::GetTempPath()) ("scout-v3-cutover-" + [guid]::NewGuid().ToString('N'))
        try {
            $Dir = Join-Path $Root 'Fixture'; $null = New-Item -ItemType Directory -Path $Dir -Force
            "@{ ResourceTypes = @('widget'); RowLoopVariable = '1'; Export = @{ WorksheetName = 'Bad'; Columns = @('ID') } }" |
                Set-Content -LiteralPath (Join-Path $Dir 'Malformed.psd1') -Encoding utf8
            $Collector = @(Get-ScoutCollector -DefinitionRoot $Root)[0]
            $Result = Invoke-ScoutCollector -Collector $Collector -Context @{ Resources = @(); Task = 'Processing' } -WarningAction SilentlyContinue

            $Result.Success | Should -BeFalse
            $Result.Mode | Should -Be 'Declarative'
            @($Result.Rows).Count | Should -Be 0
        } finally { Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
