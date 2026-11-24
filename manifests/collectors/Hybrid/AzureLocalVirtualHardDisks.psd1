#
# Hand-authored collector (AB#9300): Virtual hard disks of Azure Local VMs were discovered but not read. Property paths from the Microsoft.AzureStackHCI reference.
#
@{
    ResourceTypes = @('microsoft.azurestackhci/virtualharddisks')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
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
        @{ Name = 'Size (GB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''diskSizeGB'')' }
        @{ Name = 'Dynamic'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''dynamic'')' }
        @{ Name = 'Format'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''diskFileFormat'')' }
        @{ Name = 'Storage Path'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''containerId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Hyper-V Generation'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''hyperVGeneration'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Azure Local VM Disks'
        TableNamePrefix = 'AzLocalVhds_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Size (GB)'
            'Dynamic'
            'Format'
            'Storage Path'
            'Hyper-V Generation'
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

    SourceCollector = 'manifests/collectors/Hybrid/AzureLocalVirtualHardDisks.psd1'

    ManualConversionReason = 'Virtual hard disks of Azure Local VMs were discovered but not read. Property paths from the Microsoft.AzureStackHCI reference.'
}
