#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/analyze/Get-ScoutIacGap.ps1 — Bicep/IaC gap detection
    (ADO Story AB#325). Builds synthetic collect-shaped resources and throwaway
    template files under $env:TEMP — no Azure connection, no network calls.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/analyze/Get-ScoutIacGap.ps1"
}

Describe 'Get-ScoutIacGap -- graceful degradation with no -TemplatePath' {
    BeforeAll {
        $script:Resources = @(
            [pscustomobject]@{ Type = 'Microsoft.Network/virtualNetworks'; Name = 'vnet-hub'; ResourceGroup = 'rg-connectivity' }
        )
    }

    It 'returns HasTemplates = $false when -TemplatePath is omitted' {
        $result = Get-ScoutIacGap -CollectData $script:Resources
        $result.HasTemplates | Should -BeFalse
        $result.Message | Should -Not -BeNullOrEmpty
        $result.Unmanaged | Should -BeNullOrEmpty
    }

    It 'returns HasTemplates = $false when -TemplatePath does not exist' {
        $result = Get-ScoutIacGap -CollectData $script:Resources -TemplatePath (Join-Path $env:TEMP "ScoutIacGapMissing_$([guid]::NewGuid().ToString('N'))")
        $result.HasTemplates | Should -BeFalse
    }

    It 'returns HasTemplates = $false when -TemplatePath has no .bicep/.json files' {
        $emptyFolder = Join-Path $env:TEMP "ScoutIacGapEmpty_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $emptyFolder -Force | Out-Null
        try {
            'not a template' | Out-File (Join-Path $emptyFolder 'notes.txt')
            $result = Get-ScoutIacGap -CollectData $script:Resources -TemplatePath $emptyFolder
            $result.HasTemplates | Should -BeFalse
        }
        finally {
            Remove-Item $emptyFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not throw' {
        { Get-ScoutIacGap -CollectData $script:Resources } | Should -Not -Throw
    }
}

Describe 'Get-ScoutIacGap -- unmanaged vs matched detection' {
    BeforeAll {
        $script:TemplateFolder = Join-Path $env:TEMP "ScoutIacGapTemplates_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $script:TemplateFolder -Force | Out-Null

        # Bicep template declaring vnet-hub (a literal, resolvable name)
        @"
resource vnetHub 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-hub'
  location: 'eastus'
  properties: {}
}
"@ | Out-File (Join-Path $script:TemplateFolder 'network.bicep') -Encoding utf8

        # ARM JSON template declaring stgprod01 (a literal, resolvable name)
        @'
{
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2023-01-01",
      "name": "stgprod01",
      "properties": {}
    },
    {
      "type": "Microsoft.KeyVault/vaults",
      "apiVersion": "2023-07-01",
      "name": "[parameters('kvName')]",
      "properties": {}
    }
  ]
}
'@ | Out-File (Join-Path $script:TemplateFolder 'storage.json') -Encoding utf8

        # discovered resources: vnet-hub (templated), stgprod01 (templated),
        # kv-prod01 (type present in templates but name is parameter-driven/unresolved),
        # vm-app03 (type not present in templates at all -- fully unmanaged)
        $script:Resources = @(
            [pscustomobject]@{ Type = 'Microsoft.Network/virtualNetworks'; Name = 'vnet-hub'; ResourceGroup = 'rg-connectivity' }
            [pscustomobject]@{ Type = 'Microsoft.Storage/storageAccounts'; Name = 'stgprod01'; ResourceGroup = 'rg-workload1' }
            [pscustomobject]@{ Type = 'Microsoft.KeyVault/vaults'; Name = 'kv-prod01'; ResourceGroup = 'rg-workload1' }
            [pscustomobject]@{ Type = 'Microsoft.Compute/virtualMachines'; Name = 'vm-app03'; ResourceGroup = 'rg-sandbox' }
        )

        $script:Result = Get-ScoutIacGap -CollectData $script:Resources -TemplatePath $script:TemplateFolder
    }

    AfterAll {
        Remove-Item $script:TemplateFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'has templates and processed both template files' {
        $script:Result.HasTemplates | Should -BeTrue
        $script:Result.TemplateFileCount | Should -Be 2
    }

    It 'matches the templated, literally-named resources and does not flag them' {
        @($script:Result.Matched | Where-Object Name -eq 'vnet-hub').Count | Should -Be 1
        @($script:Result.Matched | Where-Object Name -eq 'stgprod01').Count | Should -Be 1
        @($script:Result.Unmanaged | Where-Object Name -eq 'vnet-hub').Count | Should -Be 0
        @($script:Result.Unmanaged | Where-Object Name -eq 'stgprod01').Count | Should -Be 0
    }

    It 'flags the fully-unmanaged resource (type absent from every template) as High severity' {
        $vm = $script:Result.Unmanaged | Where-Object Name -eq 'vm-app03'
        $vm | Should -Not -BeNullOrEmpty
        $vm.TypePresentInTemplates | Should -BeFalse
        $vm.Severity | Should -Be 'High'
    }

    It 'flags the parameter-driven-name resource as Medium severity (type present, name unresolved)' {
        $kv = $script:Result.Unmanaged | Where-Object Name -eq 'kv-prod01'
        $kv | Should -Not -BeNullOrEmpty
        $kv.TypePresentInTemplates | Should -BeTrue
        $kv.Severity | Should -Be 'Medium'
    }

    It 'does not report templated-but-missing entries unless requested' {
        $script:Result.TemplatedButMissing | Should -BeNullOrEmpty
    }
}

Describe 'Get-ScoutIacGap -- -IncludeTemplatedButMissing' {
    BeforeAll {
        $script:TemplateFolder = Join-Path $env:TEMP "ScoutIacGapMissing2_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $script:TemplateFolder -Force | Out-Null

        @"
resource vnetHub 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-never-deployed'
  properties: {}
}
"@ | Out-File (Join-Path $script:TemplateFolder 'network.bicep') -Encoding utf8

        $script:Resources = @(
            [pscustomobject]@{ Type = 'Microsoft.Network/virtualNetworks'; Name = 'vnet-hub'; ResourceGroup = 'rg-connectivity' }
        )
    }

    AfterAll {
        Remove-Item $script:TemplateFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports the templated-but-undeployed resource only when the switch is passed' {
        $withoutSwitch = Get-ScoutIacGap -CollectData $script:Resources -TemplatePath $script:TemplateFolder
        $withoutSwitch.TemplatedButMissing | Should -BeNullOrEmpty

        $withSwitch = Get-ScoutIacGap -CollectData $script:Resources -TemplatePath $script:TemplateFolder -IncludeTemplatedButMissing
        $withSwitch.TemplatedButMissing.Count | Should -Be 1
        $withSwitch.TemplatedButMissing[0].Name | Should -Be 'vnet-never-deployed'
    }
}

Describe 'Get-ScoutIacGap -- consumes the nested collect.json shape directly' {
    BeforeAll {
        $script:TemplateFolder = Join-Path $env:TEMP "ScoutIacGapNested_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $script:TemplateFolder -Force | Out-Null
        @"
resource vnetHub 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-hub'
  properties: {}
}
"@ | Out-File (Join-Path $script:TemplateFolder 'network.bicep') -Encoding utf8

        $script:SampleCollectPath = Join-Path $script:Root 'tests/datadump/sample-collect.json'
        $script:Collect = Get-Content $script:SampleCollectPath -Raw | ConvertFrom-Json
    }

    AfterAll {
        Remove-Item $script:TemplateFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'flattens networking.virtualNetworks from the real sample-collect.json fixture' {
        $result = Get-ScoutIacGap -CollectData $script:Collect -TemplatePath $script:TemplateFolder
        $result.DiscoveredCount | Should -BeGreaterThan 0
        @($result.Matched | Where-Object Name -eq 'vnet-hub').Count | Should -Be 1
        @($result.Unmanaged | Where-Object Name -eq 'vnet-spoke1').Count | Should -Be 1
    }
}
