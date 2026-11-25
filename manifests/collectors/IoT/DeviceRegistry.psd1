#
# Hand-authored collector (AB#9300): Azure Device Registry namespaces, assets and devices (Azure IoT Operations) had no collector. Property paths from the Microsoft.DeviceRegistry 2026-11-01 reference.
#
@{
    ResourceTypes = @('microsoft.deviceregistry/namespaces', 'microsoft.deviceregistry/namespaces/assets', 'microsoft.deviceregistry/namespaces/devices')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$kind = ([string]$1.type -split '/')[-1]
'@

    AdditionalRowLoops = @()

    TagLoop = @{
        Variable = 'Tag'
        Source = '$Tags'
        Preamble = ''
    }

    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Subscription'; Expression = '(Get-AZSCSafeProperty -InputObject $sub1 -Path ''name'')' }
        @{ Name = 'Resource Group'; Expression = '$1.RESOURCEGROUP' }
        @{ Name = 'Name'; Expression = '$1.NAME' }
        @{ Name = 'Location'; Expression = '$1.LOCATION' }
        @{ Name = 'Kind'; Expression = '$kind' }
        @{ Name = 'Enabled'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''enabled'')' }
        @{ Name = 'External ID'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''externalAssetId''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''externalDeviceId'' }; $v }' }
        @{ Name = 'Manufacturer'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''manufacturer'')' }
        @{ Name = 'Model'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''model'')' }
        @{ Name = 'Discovered Refs'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''discoveredAssetRefs'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Azure Device Registry'
        TableNamePrefix = 'DeviceRegistry_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'Enabled'
            'External ID'
            'Manufacturer'
            'Model'
            'Discovered Refs'
            'Provisioning State'
            'Resource U'
        )
        TagColumns = @(
            'Tag Name'
            'Tag Value'
        )
        TagColumnsBefore = 'Resource U'
        NumberFormat = '0'
        ConditionalText = @()
    }

    SourceCollector = 'manifests/collectors/IoT/DeviceRegistry.psd1'

    ManualConversionReason = 'Azure Device Registry namespaces, assets and devices (Azure IoT Operations) had no collector. Property paths from the Microsoft.DeviceRegistry 2026-11-01 reference.'
}
