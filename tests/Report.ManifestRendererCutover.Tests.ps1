#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/Get-ScoutReportSectionIndex.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCJsonReport.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCMarkdownReport.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCAsciiDocReport.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCPowerBIReport.ps1')

    $script:TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (
        'AZSC_ManifestRenderer_' + [guid]::NewGuid().ToString('N')
    )
    $script:DefinitionRoot = Join-Path -Path $script:TempRoot -ChildPath 'definitions'
    $script:CacheRoot = Join-Path -Path $script:TempRoot -ChildPath 'cache'
    New-Item -ItemType Directory -Path $script:DefinitionRoot, $script:CacheRoot -Force | Out-Null

    function Write-RendererDefinition {
        param([string]$Category, [string]$Name)

        $Directory = Join-Path -Path $script:DefinitionRoot -ChildPath $Category
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        @"
@{
    ResourceTypes = @('microsoft.example/$($Name.ToLowerInvariant())')
    RowLoopVariable = '1'
    Fields = @(@{ Name = 'Name'; Expression = '`$1.Name' })
    Export = @{ WorksheetName = '$Name'; Columns = @('Name') }
}
"@ | Set-Content -LiteralPath (Join-Path -Path $Directory -ChildPath "$Name.psd1") -Encoding utf8
    }

    Write-RendererDefinition -Category 'Compute' -Name 'Widget'
    Write-RendererDefinition -Category 'Identity' -Name 'Users'

    @{ Widget = @([ordered]@{ Name = 'widget-01'; Location = 'eastus' }); Unlisted = @([ordered]@{ Name = 'must-not-render' }) } |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path -Path $script:CacheRoot -ChildPath 'Compute.json') -Encoding utf8
    @{ Users = @([ordered]@{ Name = 'user-01'; 'User Principal Name' = 'user@example.test' }) } |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path -Path $script:CacheRoot -ChildPath 'Identity.json') -Encoding utf8
    [pscustomobject]@{
        Schema = 'azure-scout/discovery-completeness/v1'; GeneratedAt = '2026-08-14T00:00:00Z'
        Summary = [pscustomobject]@{ Resources = 1 }
        Resources = @([pscustomobject]@{
                Id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Example/widgets/widget-01'
                Name = 'widget-01'; Type = 'microsoft.example/widgets'; SourceKind = 'ARM'
                DetailStatus = 'GenericOnly'; Exposure = 'Unknown'
            })
        Relationships = @()
        CollectionHealth = @()
    } | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath (Join-Path -Path $script:CacheRoot -ChildPath 'Discovery.json') -Encoding utf8
}

AfterAll {
    if (Test-Path -LiteralPath $script:TempRoot) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
    }
}

Describe 'Manifest-backed inventory JSON and Markdown renderers' {
    It 'JSON renders only definition-indexed cache keys and preserves ARM/Entra grouping' {
        $OutputBase = Join-Path -Path $script:TempRoot -ChildPath 'inventory.xlsx'
        $JsonPath = Export-AZSCJsonReport -ReportCache $script:CacheRoot -File $OutputBase `
            -DefinitionRoot $script:DefinitionRoot -TenantID 'tenant-test'
        $Report = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json

        (Split-Path -Leaf $JsonPath) | Should -Be 'inventory.json'
        (Split-Path -Leaf $JsonPath) | Should -Not -Be 'findings.json'
        $Report.arm.compute.widget[0].Name | Should -Be 'widget-01'
        $Report.entra.users[0].Name | Should -Be 'user-01'
        $Report.arm.compute.PSObject.Properties.Name | Should -Not -Contain 'unlisted'
        $Report.discovery.schema | Should -Be 'azure-scout/discovery-completeness/v1'
        $Report.discovery.summary.resources | Should -Be 1
        $Report.discovery.resources[0].Name | Should -Be 'widget-01'
    }

    It 'Markdown honors scope using definition categories, without a collector-script walk' {
        $OutputBase = Join-Path -Path $script:TempRoot -ChildPath 'inventory-markdown.xlsx'
        $MarkdownPath = Export-AZSCMarkdownReport -ReportCache $script:CacheRoot -File $OutputBase `
            -DefinitionRoot $script:DefinitionRoot -Scope ArmOnly
        $Markdown = Get-Content -LiteralPath $MarkdownPath -Raw

        $Markdown | Should -Match '## Compute'
        $Markdown | Should -Match '### Widget'
        $Markdown | Should -Not -Match '## Identity'
        $Markdown | Should -Not -Match '### Users'
    }

    It 'AsciiDoc renders only definition-indexed cache keys and honors scope' {
        $OutputBase = Join-Path -Path $script:TempRoot -ChildPath 'inventory-asciidoc.xlsx'
        $AsciiDocPath = Export-AZSCAsciiDocReport -ReportCache $script:CacheRoot -File $OutputBase `
            -DefinitionRoot $script:DefinitionRoot -Scope ArmOnly
        $AsciiDoc = Get-Content -LiteralPath $AsciiDocPath -Raw

        $AsciiDoc | Should -Match '== Compute'
        $AsciiDoc | Should -Match '=== Widget'
        $AsciiDoc | Should -Not -Match '== Identity'
        $AsciiDoc | Should -Not -Match 'Users'
        $AsciiDoc | Should -Not -Match 'must-not-render'
    }

    It 'Power BI exports only definition-indexed cache keys and honors scope' {
        $OutputBase = Join-Path -Path $script:TempRoot -ChildPath 'inventory-powerbi.xlsx'
        $PowerBIDirectory = Export-AZSCPowerBIReport -ReportCache $script:CacheRoot -File $OutputBase `
            -DefinitionRoot $script:DefinitionRoot -Scope EntraOnly

        Test-Path -LiteralPath (Join-Path -Path $PowerBIDirectory -ChildPath 'Entra_Users.csv') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $PowerBIDirectory -ChildPath 'Resources_Widget.csv') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $PowerBIDirectory -ChildPath 'Resources_Unlisted.csv') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path -Path $PowerBIDirectory -ChildPath 'Entra_Users.csv') -Raw) | Should -Match 'user@example.test'
    }

    It 'renderers have no legacy collector-tree path literal and call the section index' {
        foreach ($Path in @(
            (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCJsonReport.ps1'),
            (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCMarkdownReport.ps1'),
            (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCAsciiDocReport.ps1'),
            (Join-Path -Path $script:RepoRoot -ChildPath 'src/report/renderers/inventory/Export-AZSCPowerBIReport.ps1')
        )) {
            $Source = Get-Content -LiteralPath $Path -Raw
            $Source | Should -Match 'Get-ScoutReportSectionIndex'
            $retiredCollectorToken = 'Inventory' + 'Modules'
            $Source | Should -Not -Match "$retiredCollectorToken|Modules[/\\]Public"
        }
    }
}
