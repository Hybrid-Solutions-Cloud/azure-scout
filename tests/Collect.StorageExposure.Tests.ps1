#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/collect/ConvertTo-ScoutStorageExposureEvidence.ps1')

    function New-StorageEvidenceAccount {
        param(
            [string] $Name,
            [string] $ResourceGroup = 'rg-workload',
            [hashtable] $Properties = @{}
        )
        [pscustomobject]@{
            id = "/subscriptions/sub-1/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$Name"
            name = $Name
            type = 'microsoft.storage/storageaccounts'
            subscriptionId = 'sub-1'
            resourceGroup = $ResourceGroup
            location = 'eastus'
            properties = [pscustomobject]$Properties
        }
    }

    function New-StorageEvidenceResourceGroup {
        param([string] $Name, [string] $ManagedBy)
        [pscustomobject]@{
            id = "/subscriptions/sub-1/resourceGroups/$Name"
            name = $Name
            type = 'microsoft.resources/subscriptions/resourcegroups'
            subscriptionId = 'sub-1'
            managedBy = $ManagedBy
            properties = [pscustomobject]@{}
        }
    }
}

Describe 'ConvertTo-ScoutStorageExposureEvidence' {
    It 'emits one retained evidence row per discovered storage account without any Azure call' {
        function global:Invoke-AzRestMethod { throw 'pure transform must not call Azure' }
        function global:Search-AzGraph { throw 'pure transform must not call Resource Graph' }
        try {
            $rows = @(ConvertTo-ScoutStorageExposureEvidence -Resources @(
                    New-StorageEvidenceAccount -Name 'storageone'
                    New-StorageEvidenceAccount -Name 'storagetwo'
                ))
            $rows.Count | Should -Be 2
            @($rows.type | Select-Object -Unique) | Should -Be @('AZSC/Derived/StorageExposure')
            @($rows.AZSC.SourceDatasets).Count | Should -BeGreaterThan 0
        }
        finally {
            Remove-Item Function:global:Invoke-AzRestMethod -Force -ErrorAction SilentlyContinue
            Remove-Item Function:global:Search-AzGraph -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies documented effective defaults without erasing the absent configured values' {
        $row = @(ConvertTo-ScoutStorageExposureEvidence -Resources @(
                New-StorageEvidenceAccount -Name 'defaultstorage'
            ))[0]

        $row.properties.PublicNetworkAccessConfigured | Should -BeNullOrEmpty
        $row.properties.PublicNetworkAccessEffective | Should -Be 'Enabled'
        $row.properties.NetworkDefaultActionConfigured | Should -BeNullOrEmpty
        $row.properties.NetworkDefaultActionEffective | Should -Be 'Allow'
        $row.properties.AllowBlobPublicAccessConfigured | Should -BeNullOrEmpty
        $row.properties.AllowBlobPublicAccessEffective | Should -BeTrue
        $row.properties.AllowSharedKeyAccessConfigured | Should -BeNullOrEmpty
        $row.properties.AllowSharedKeyAccessEffective | Should -BeTrue
        $row.properties.Exposure | Should -Be 'Public'
        $row.properties.Verdict | Should -Be 'REAL exposure - remediate'
    }

    It 'joins resource-group managedBy and gives managed resources verdict precedence' {
        $row = @(ConvertTo-ScoutStorageExposureEvidence -Resources @(
                New-StorageEvidenceAccount -Name 'dbstorageabc' -ResourceGroup 'databricks-rg'
            ) -ResourceContainers @(
                New-StorageEvidenceResourceGroup -Name 'databricks-rg' -ManagedBy '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Databricks/workspaces/dbw'
            ))[0]

        $row.properties.ManagedBy | Should -Match 'Microsoft.Databricks'
        $row.properties.Verdict | Should -Be 'Managed RG - by design, confirm'
    }

    It 'labels temporary deployment groups before generic public exposure' {
        $row = @(ConvertTo-ScoutStorageExposureEvidence -Resources @(
                New-StorageEvidenceAccount -Name 'artifactstore' -ResourceGroup 'migration-tmp-2026'
            ))[0]
        $row.properties.Verdict | Should -Be 'Deployment/temp - candidate to delete'
    }

    It 'joins private endpoints from both the account and private-endpoint resource directions' {
        $storage = New-StorageEvidenceAccount -Name 'privatestorage' -Properties @{
            publicNetworkAccess = 'Disabled'
            networkAcls = @{ defaultAction = 'Deny' }
            privateEndpointConnections = @(
                @{ properties = @{ privateEndpoint = @{ id = '/subscriptions/sub-1/resourceGroups/rg-network/providers/Microsoft.Network/privateEndpoints/pe-one' } } }
            )
        }
        $privateEndpoint = [pscustomobject]@{
            id = '/subscriptions/sub-1/resourceGroups/rg-network/providers/Microsoft.Network/privateEndpoints/pe-two'
            type = 'microsoft.network/privateendpoints'
            properties = [pscustomobject]@{
                privateLinkServiceConnections = @(
                    @{ properties = @{ privateLinkServiceId = $storage.id } }
                )
            }
        }

        $row = @(ConvertTo-ScoutStorageExposureEvidence -Resources @($storage, $privateEndpoint))[0]
        $row.properties.PrivateEndpointCount | Should -Be 2
        $row.properties.PrivateEndpointIds | Should -Contain $privateEndpoint.id
        $row.properties.Exposure | Should -Be 'Private'
        $row.properties.Verdict | Should -Be 'Needs owner review'
    }

    It 'ships a declarative report manifest for every normalized field' {
        $definition = Import-PowerShellDataFile (Join-Path $script:RepoRoot 'manifests/collectors/Storage/StorageExposure.psd1')
        $definition.ResourceTypes | Should -Be @('AZSC/Derived/StorageExposure')
        @($definition.Fields.Name) | Should -Contain 'Verdict'
        @($definition.Fields.Name) | Should -Contain 'Private Endpoint IDs'
        @($definition.Export.Columns) | Should -Contain 'Allow Shared Key Access (Effective)'
    }
}
