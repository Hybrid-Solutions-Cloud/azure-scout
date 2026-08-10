#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
}

Describe 'release automation executes the code and contracts it advertises' {
    It 'uses valid public parameters and live assessment formats in Azure Pipelines' {
        $pipeline = Get-Content -Raw (Join-Path $script:Root '.ado/azure-pipelines.yml')

        $pipeline | Should -Match '(?m)^\s+-ManagementGroup\s'
        $pipeline | Should -Match '(?m)^\s+-ReportDir\s'
        $pipeline | Should -Match '(?m)^\s+-OutputFormat React,Json,JsonEvidence\s'
        $pipeline | Should -Not -Match '(?m)^\s+-(ManagementGroupId|OutputPath)\s'
        $pipeline | Should -Not -Match '(?m)^\s+-OutputFormat.*\b(PowerBi|Html|Pptx|Excel|Pdf|Word|EChartsDashboard)\b'
    }

    It 'runs the module bundled with the pinned composite action by default' {
        $action = Get-Content -Raw (Join-Path $script:Root 'action.yml')

        $action | Should -Match "GITHUB_ACTION_PATH 'AzureScout\.psd1'"
        $action | Should -Match 'AZURESCOUT_MODULE_PATH=\$modulePath'
        $action | Should -Match 'Import-Module \$env:AZURESCOUT_MODULE_PATH'
        $action | Should -Not -Match 'Installing AzureScout \(latest\)'
    }

    It 'fails the composite action when no report artifact exists' {
        $action = Get-Content -Raw (Join-Path $script:Root 'action.yml')

        $action | Should -Match "Azure Scout completed but produced no report files\.'\s*\r?\n\s+exit 1"
        $action | Should -Match 'if-no-files-found: error'
    }

    It 'fails CI for Pester discovery/container failures and zero discovered tests' {
        $ci = Get-Content -Raw (Join-Path $script:Root '.github/workflows/ci.yml')

        $ci | Should -Match '\$result\.Result -ne ''Passed'''
        $ci | Should -Match '\$result\.FailedContainersCount -gt 0'
        $ci | Should -Match '\$result\.TotalCount -eq 0'
    }

    It 'keeps pull-request documentation builds read-only' {
        $workflow = Get-Content -Raw (Join-Path $script:Root '.github/workflows/documentation.yml')

        $workflow | Should -Match '(?ms)^permissions:\s+contents: read'
        $workflow | Should -Match 'persist-credentials: false'
        $workflow | Should -Match '(?ms)^  deploy:.*?^    permissions:\s+contents: write'
    }

    It 'fails module import when a required engine file cannot load' {
        $module = Get-Content -Raw (Join-Path $script:Root 'AzureScout.psm1')

        $module | Should -Match 'catch \{ throw "\[AzureScout\] Failed to load required engine file'
        $module | Should -Not -Match 'Failed to load v3 engine file.*Write-Warning'
    }

    It 'declares core dependencies without installing software during module import' {
        $manifestPath = Join-Path $script:Root 'AzureScout.psd1'
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $module = Get-Content -Raw (Join-Path $script:Root 'AzureScout.psm1')

        @($manifest.RequiredModules).Count | Should -BeGreaterThan 0
        @($manifest.RequiredModules) | Should -Contain 'Az.Accounts'
        @($manifest.RequiredModules) | Should -Contain 'powershell-yaml'
        $module | Should -Not -Match '(?m)^\s*Install-Module\b'
    }
}
