@{
    ResourceTypes = @('AZSC/Derived/StorageExposure')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$data = $1.properties'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$data.StorageAccountId' }
        @{ Name = 'Subscription ID'; Expression = '$1.subscriptionId' }
        @{ Name = 'Resource Group'; Expression = '$1.resourceGroup' }
        @{ Name = 'Storage Account'; Expression = '$1.name' }
        @{ Name = 'Managed By'; Expression = '$data.ManagedBy' }
        @{ Name = 'Public Network Access (Configured)'; Expression = '$data.PublicNetworkAccessConfigured' }
        @{ Name = 'Public Network Access (Effective)'; Expression = '$data.PublicNetworkAccessEffective' }
        @{ Name = 'Network Default Action (Configured)'; Expression = '$data.NetworkDefaultActionConfigured' }
        @{ Name = 'Network Default Action (Effective)'; Expression = '$data.NetworkDefaultActionEffective' }
        @{ Name = 'Allow Blob Public Access (Configured)'; Expression = '$data.AllowBlobPublicAccessConfigured' }
        @{ Name = 'Allow Blob Public Access (Effective)'; Expression = '$data.AllowBlobPublicAccessEffective' }
        @{ Name = 'Allow Shared Key Access (Configured)'; Expression = '$data.AllowSharedKeyAccessConfigured' }
        @{ Name = 'Allow Shared Key Access (Effective)'; Expression = '$data.AllowSharedKeyAccessEffective' }
        @{ Name = 'Minimum TLS Version'; Expression = '$data.MinimumTlsVersion' }
        @{ Name = 'Private Endpoint Count'; Expression = '$data.PrivateEndpointCount' }
        @{ Name = 'Private Endpoint IDs'; Expression = '[string]::Join('', '', @($data.PrivateEndpointIds))' }
        @{ Name = 'Exposure'; Expression = '$data.Exposure' }
        @{ Name = 'Verdict'; Expression = '$data.Verdict' }
    )
    Export = @{
        WorksheetName = 'Storage Exposure'
        TableNamePrefix = 'StorageExposure_'
        Columns = @(
            'Subscription ID', 'Resource Group', 'Storage Account', 'Managed By',
            'Public Network Access (Configured)', 'Public Network Access (Effective)',
            'Network Default Action (Configured)', 'Network Default Action (Effective)',
            'Allow Blob Public Access (Configured)', 'Allow Blob Public Access (Effective)',
            'Allow Shared Key Access (Configured)', 'Allow Shared Key Access (Effective)',
            'Minimum TLS Version', 'Private Endpoint Count', 'Private Endpoint IDs', 'Exposure', 'Verdict'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
    SourceCollector = 'src/collect/ConvertTo-ScoutStorageExposureEvidence.ps1'
    ManualConversionReason = 'Hand-authored for AB#7441 against a pure storage-evidence transform; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}
