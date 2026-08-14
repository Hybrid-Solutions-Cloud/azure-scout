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

    It 'advertises and accepts only the live global output contract in the composite action' {
        $action = Get-Content -Raw (Join-Path $script:Root 'action.yml')

        $action | Should -Match "description: 'All \(React, Json, and JsonEvidence\), or a comma-separated selection of React, Json, and JsonEvidence\.'"
        $action | Should -Match ([regex]::Escape("`$requestedFormats = @(`$env:OUTPUT_FORMAT -split ','"))
        $action | Should -Match ([regex]::Escape("OutputFormat        = `$requestedFormats"))
        $action | Should -Match "(?s)if \(\`$requestedFormats\.Count -eq 0\).*?\`$requestedFormats = @\('All'\)"
        $action | Should -Not -Match "(?m)^\s+description: 'All, Excel, Json, Markdown, AsciiDoc, or PowerBI\.'"
    }

    It 'exposes the live global output contract in the inventory workflow' {
        $workflow = Get-Content -Raw (Join-Path $script:Root '.github/workflows/azure-inventory.yml')

        $workflow | Should -Match '(?ms)^\s{6}outputFormat:.*?^\s{10}- All\s*$.*?^\s{10}- React\s*$.*?^\s{10}- Json\s*$.*?^\s{10}- JsonEvidence\s*$'
        $workflow | Should -Match "output-format: \`$\{\{ github\.event\.inputs\.outputFormat \|\| 'All' \}\}"
        $workflow | Should -Not -Match '(?m)^\s+lite: ''true''\s*$'
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
        $ci = Get-Content -Raw (Join-Path $script:Root '.github/workflows/ci.yml')

        @($manifest.RequiredModules).Count | Should -BeGreaterThan 0
        @($manifest.RequiredModules) | Should -Contain 'Az.Accounts'
        @($manifest.RequiredModules) | Should -Contain 'powershell-yaml'
        $spectreDependency = @($manifest.RequiredModules | Where-Object {
            $_ -is [System.Collections.IDictionary] -and $_.ModuleName -eq 'PwshSpectreConsole'
        })
        $spectreDependency.Count | Should -Be 1
        [version]$spectreDependency[0].RequiredVersion | Should -Be ([version]'2.1.2')
        $ci | Should -Match '\$install\.RequiredVersion = \$requiredModule\.RequiredVersion'
        $module | Should -Not -Match '(?m)^\s*Install-Module\b'
    }
}
