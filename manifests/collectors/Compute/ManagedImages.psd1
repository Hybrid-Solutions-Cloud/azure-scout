#
# Hand-authored collector (AB#9300): Managed VM images were discovered but not read. The OS disk blob URI is not projected. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.compute/images')

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
        @{ Name = 'OS Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''storageProfile.osDisk.osType'')' }
        @{ Name = 'OS State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''storageProfile.osDisk.osState'')' }
        @{ Name = 'Hyper-V Generation'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''hyperVGeneration'')' }
        @{ Name = 'OS Disk (GB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''storageProfile.osDisk.diskSizeGB'')' }
        @{ Name = 'OS Disk Storage'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''storageProfile.osDisk.storageAccountType'')' }
        @{ Name = 'Data Disks'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''storageProfile.dataDisks'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Source VM'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''sourceVirtualMachine.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Managed Images'
        TableNamePrefix = 'ManagedImages_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'OS Type'
            'OS State'
            'Hyper-V Generation'
            'OS Disk (GB)'
            'OS Disk Storage'
            'Data Disks'
            'Source VM'
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

    SourceCollector = 'manifests/collectors/Compute/ManagedImages.psd1'

    ManualConversionReason = 'Managed VM images were discovered but not read. The OS disk blob URI is not projected. Fields verified against live rows on 2026-11-24.'
}
