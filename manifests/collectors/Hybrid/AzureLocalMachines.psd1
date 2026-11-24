#
# Hand-authored collector (AB#9300): Azure Local machines (edgeMachines) were discovered but had no collector. Fields verified against live Resource Graph rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.azurestackhci/edgemachines')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$hw = Get-AZSCSafeProperty -InputObject $data -Path 'reportedProperties.hardwareProfile'
$os = Get-AZSCSafeProperty -InputObject $data -Path 'reportedProperties.osProfile'
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
        @{ Name = 'Connectivity Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''connectivityStatus'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Manufacturer'; Expression = '(Get-AZSCSafeProperty -InputObject $hw -Path ''manufacturer'')' }
        @{ Name = 'Model'; Expression = '(Get-AZSCSafeProperty -InputObject $hw -Path ''model'')' }
        @{ Name = 'Serial Number'; Expression = '(Get-AZSCSafeProperty -InputObject $hw -Path ''serialNumber'')' }
        @{ Name = 'Processor'; Expression = '(Get-AZSCSafeProperty -InputObject $hw -Path ''processorType'')' }
        @{ Name = 'CPU Sockets'; Expression = '(Get-AZSCSafeProperty -InputObject $hw -Path ''cpuSockets'')' }
        @{ Name = 'CPU Cores'; Expression = '(Get-AZSCSafeProperty -InputObject $hw -Path ''cpuCores'')' }
        @{ Name = 'Memory (GB)'; Expression = '(Get-AZSCSafeProperty -InputObject $hw -Path ''memoryCapacityInGb'')' }
        @{ Name = 'OS SKU'; Expression = '(Get-AZSCSafeProperty -InputObject $os -Path ''osSku'')' }
        @{ Name = 'OS Version'; Expression = '(Get-AZSCSafeProperty -InputObject $os -Path ''osVersion'')' }
        @{ Name = 'Boot Type'; Expression = '(Get-AZSCSafeProperty -InputObject $os -Path ''bootType'')' }
        @{ Name = 'Disks'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''reportedProperties.storageProfile.disks'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Network Adapters'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''reportedProperties.networkProfile.nicDetails'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Workloads'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''reportedProperties.workloadInventory'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Last Sync'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''lastSyncTimestamp'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Azure Local Machines'
        TableNamePrefix = 'AzLocalMachines_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Connectivity Status'
            'Provisioning State'
            'Manufacturer'
            'Model'
            'Serial Number'
            'Processor'
            'CPU Sockets'
            'CPU Cores'
            'Memory (GB)'
            'OS SKU'
            'OS Version'
            'Boot Type'
            'Disks'
            'Network Adapters'
            'Workloads'
            'Last Sync'
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

    SourceCollector = 'manifests/collectors/Hybrid/AzureLocalMachines.psd1'

    ManualConversionReason = 'Azure Local machines (edgeMachines) were discovered but had no collector. Fields verified against live Resource Graph rows on 2026-11-24.'
}
