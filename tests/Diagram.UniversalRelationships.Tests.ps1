#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutResourceCompleteness.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/diagram/New-ScoutUniversalRelationshipDiagram.ps1')
    $script:OutputPath = Join-Path $script:RepoRoot 'tests/test-output/universal-resource-graph.xml'
    New-Item -ItemType Directory -Path (Split-Path $script:OutputPath -Parent) -Force | Out-Null
}

AfterAll { Remove-Item -LiteralPath $script:OutputPath -Force -ErrorAction SilentlyContinue }

Describe 'Universal draw.io relationship page (AB#7367)' {
    It 'renders unknown resource types and their ARM references without a finite type map' {
        $targetId = '/subscriptions/sub-1/resourceGroups/rg/providers/Contoso.Future/targets/target-1'
        $source = [pscustomobject]@{
            id = '/subscriptions/sub-1/resourceGroups/rg/providers/Contoso.Future/widgets/widget-1'
            name = 'widget-1'; type = 'contoso.future/widgets'; subscriptionId = 'sub-1'; resourceGroup = 'rg'
            properties = [pscustomobject]@{ relatedResource = [pscustomobject]@{ id = $targetId } }
        }

        $result = New-ScoutUniversalRelationshipDiagram -Resources @($source) -Path $script:OutputPath
        [xml]$xml = Get-Content -LiteralPath $script:OutputPath -Raw

        $result.Resources | Should -Be 2
        $result.Relationships | Should -Be 1
        $xml.mxfile.diagram.name | Should -Be 'Universal Resource Graph'
        @($xml.SelectNodes('//mxCell[@vertex="1"]')).Count | Should -Be 2
        @($xml.SelectNodes('//mxCell[@edge="1"]')).Count | Should -Be 1
        $xml.OuterXml | Should -Match 'contoso\.future/widgets'
        $xml.OuterXml | Should -Match 'ArmReference'
    }
}
