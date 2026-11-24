#
# Hand-authored collector (AB#9300): Clusters, hosts, datastores, resource pools, networks and templates of Arc-enabled VMware vSphere had no collector. Property paths from the Microsoft.ConnectedVMwarevSphere 2023-12-01 reference and SDK models.
#
@{
    ResourceTypes = @('microsoft.connectedvmwarevsphere/clusters', 'microsoft.connectedvmwarevsphere/hosts', 'microsoft.connectedvmwarevsphere/datastores', 'microsoft.connectedvmwarevsphere/resourcepools', 'microsoft.connectedvmwarevsphere/virtualnetworks', 'microsoft.connectedvmwarevsphere/virtualmachinetemplates')

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
        @{ Name = 'vCenter'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''vCenterId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Inventory Name'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''moName'')' }
        @{ Name = 'MoRef ID'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''moRefId'')' }
        @{ Name = 'Capacity (GB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''capacityGB'')' }
        @{ Name = 'Free (GB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''freeSpaceGB'')' }
        @{ Name = 'Memory (GB)'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''totalMemoryGB''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''memorySizeGB'' }; $v }' }
        @{ Name = 'OS Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''osType'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc VMware Inventory'
        TableNamePrefix = 'ArcVMwareInventory_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'vCenter'
            'Inventory Name'
            'MoRef ID'
            'Capacity (GB)'
            'Free (GB)'
            'Memory (GB)'
            'OS Type'
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

    SourceCollector = 'manifests/collectors/Hybrid/ArcVMwareInventory.psd1'

    ManualConversionReason = 'Clusters, hosts, datastores, resource pools, networks and templates of Arc-enabled VMware vSphere had no collector. Property paths from the Microsoft.ConnectedVMwarevSphere 2023-12-01 reference and SDK models.'
}
