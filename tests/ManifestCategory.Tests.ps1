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

Describe 'assessment manifests collect every category their automated rules consume' {
    BeforeAll {
        $script:Assessments = Import-PowerShellDataFile (Join-Path $script:RepoRoot 'manifests/assessments.psd1')
    }

    It 'includes <Required> for <Assessment> because <Dataset> is scored' -ForEach @(
        @{ Assessment = 'Assess: Compute';            Required = 'Storage';    Dataset = 'storageAccounts' }
        @{ Assessment = 'Microsoft: FinOps Review';   Required = 'Compute';    Dataset = 'virtualMachines' }
        @{ Assessment = 'Assess: Cloud Governance';   Required = 'Analytics';  Dataset = 'purviewAccounts' }
        @{ Assessment = 'Assess: Management';         Required = 'Compute';    Dataset = 'virtualMachines backup denominator' }
        @{ Assessment = 'Assess: Monitor';            Required = 'Compute';    Dataset = 'virtualMachines backup denominator' }
        @{ Assessment = 'Scout: Update Manager';      Required = 'Compute';    Dataset = 'virtualMachines backup denominator' }
        @{ Assessment = 'Assess: AVD Workload';       Required = 'Hybrid';     Dataset = 'azureLocalClusters/logicalNetworks/arcExtensions' }
        @{ Assessment = 'Assess: AVD Workload';       Required = 'Management'; Dataset = 'logAnalyticsWorkspaces' }
    ) {
        $script:Assessments[$Assessment].Collect | Should -Contain $Required
    }
}
