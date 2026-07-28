#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/report/renderers/inventory/Start-AZSCExcelJob.ps1')

    # The renderer's collaborators are loaded by AzureScout.psm1 in production.  Define small
    # seams here so Pester can replace them without loading the full module and ImportExcel.
    function Get-ScoutReportSectionIndex { param($DefinitionRoot) }
    function Get-ScoutCollectorDefinition { param($Path) }
    function Invoke-ScoutDeclarativeReporting { param($Definition, $Context) }

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'AZSC_ExcelManifestRenderer_' + [guid]::NewGuid().ToString('N')
    )
    $script:CacheRoot = Join-Path $script:TempRoot 'cache'
    New-Item -ItemType Directory -Path $script:CacheRoot -Force | Out-Null
}

AfterAll {
    if (Test-Path -LiteralPath $script:TempRoot) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
    }
}

Describe 'Start-AZSCExcelJob manifest cutover' {
    It 'uses the definition index and never contains a legacy script-execution path' {
        $Source = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'src/report/renderers/inventory/Start-AZSCExcelJob.ps1') -Raw

        $Source | Should -Match 'Get-ScoutReportSectionIndex'
        $Source | Should -Match 'Invoke-ScoutDeclarativeReporting'
        $Source | Should -Not -Match 'InventoryModules|Modules[/\\]Public|Scriptblock\]::Create|Invoke-Command'
    }

    It 'renders only definition-indexed cache rows through declarative reporting' {
        @{
            Widget = @([ordered]@{ Name = 'widget-01'; 'Resource U' = 1 })
            Unlisted = @([ordered]@{ Name = 'must-not-render'; 'Resource U' = 1 })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:CacheRoot 'Compute.json') -Encoding utf8

        $script:RenderedContexts = @()
        Mock Get-ScoutReportSectionIndex {
            @(
                [pscustomobject]@{ Category = 'Compute'; CacheFileName = 'Compute.json'; CacheKey = 'Widget'; Name = 'Widget'; DefinitionPath = 'widget-definition.psd1' }
                [pscustomobject]@{ Category = 'Compute'; CacheFileName = 'Compute.json'; CacheKey = 'Missing'; Name = 'Missing'; DefinitionPath = 'missing-definition.psd1' }
                [pscustomobject]@{ Category = 'Identity'; CacheFileName = 'Identity.json'; CacheKey = 'Users'; Name = 'Users'; DefinitionPath = 'users-definition.psd1' }
            )
        }
        Mock Get-ScoutCollectorDefinition { [pscustomobject]@{ Name = 'Widget definition' } }
        Mock Invoke-ScoutDeclarativeReporting {
            param($Definition, $Context)
            $script:RenderedContexts += $Context
        }
        Mock Write-Progress {}
        Mock Write-Host {}

        Start-AZSCExcelJob -ReportCache $script:CacheRoot -File (Join-Path $script:TempRoot 'inventory.xlsx') `
            -TableStyle 'Medium2' -DefinitionRoot 'definitions-root'

        Should -Invoke Invoke-ScoutDeclarativeReporting -Times 1 -Exactly
        Should -Invoke Get-ScoutCollectorDefinition -ParameterFilter { $Path -eq 'widget-definition.psd1' } -Times 1 -Exactly
        $script:RenderedContexts.Count | Should -Be 1
        $script:RenderedContexts[0].SmaResources.Count | Should -Be 1
        $script:RenderedContexts[0].SmaResources[0].Name | Should -Be 'widget-01'
        $script:RenderedContexts[0].File | Should -Be (Join-Path $script:TempRoot 'inventory.xlsx')
        $script:RenderedContexts[0].TableStyle | Should -Be 'Medium2'
    }
}
