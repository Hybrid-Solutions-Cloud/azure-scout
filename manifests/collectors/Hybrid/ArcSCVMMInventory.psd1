#
# Hand-authored collector (AB#9300): Clouds, networks, templates and availability sets of Arc-enabled SCVMM had no collector. Property paths from the Microsoft.ScVmm 2025-03-13 reference and SDK models.
#
@{
    ResourceTypes = @('microsoft.scvmm/clouds', 'microsoft.scvmm/virtualnetworks', 'microsoft.scvmm/virtualmachinetemplates', 'microsoft.scvmm/availabilitysets')

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
$inventoryName = @('cloudName', 'networkName', 'availabilitySetName', 'osName' | ForEach-Object { Get-AZSCSafeProperty -InputObject $data -Path $_ } | Where-Object { $_ })[0]
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
        @{ Name = 'VMM Server'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''vmmServerId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Inventory Name'; Expression = '$inventoryName' }
        @{ Name = 'OS Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''osType'')' }
        @{ Name = 'CPU Count'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''cpuCount'')' }
        @{ Name = 'Memory (MB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''memoryMB'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc SCVMM Inventory'
        TableNamePrefix = 'ArcSCVMMInventory_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'VMM Server'
            'Inventory Name'
            'OS Type'
            'CPU Count'
            'Memory (MB)'
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

    SourceCollector = 'manifests/collectors/Hybrid/ArcSCVMMInventory.psd1'

    ManualConversionReason = 'Clouds, networks, templates and availability sets of Arc-enabled SCVMM had no collector. Property paths from the Microsoft.ScVmm 2025-03-13 reference and SDK models.'
}
