#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/pipeline/Get-ScoutCollector.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
}

Describe 'v3 manifest category modules — <Category>' -ForEach @(
    Get-ChildItem (Join-Path -Path $script:RepoRoot -ChildPath 'manifests/collectors') -Directory | Sort-Object Name |
        ForEach-Object { @{ Category = $_.Name; Path = $_.FullName } }
) {
    It 'has at least one valid collector definition' {
        $Collectors = @(Get-ScoutCollector -DefinitionRoot (Join-Path -Path $script:RepoRoot -ChildPath 'manifests/collectors') -Category $Category)
        $Collectors.Count | Should -BeGreaterThan 0
        foreach ($Collector in $Collectors) {
            { Get-ScoutCollectorDefinition -Path $Collector.DefinitionPath } | Should -Not -Throw
        }
    }
}
