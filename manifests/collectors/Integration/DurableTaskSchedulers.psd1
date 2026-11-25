#
# Hand-authored collector (AB#9300): Durable Task Schedulers had no collector. Property paths from the Microsoft.DurableTask schedulers 2026-02-01 reference.
#
@{
    ResourceTypes = @('microsoft.durabletask/schedulers')

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
        @{ Name = 'Endpoint'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''endpoint'')' }
        @{ Name = 'SKU'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''sku.name'')' }
        @{ Name = 'Capacity'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''sku.capacity'')' }
        @{ Name = 'Allowed IPs'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''ipAllowlist'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Public Network Access'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''publicNetworkAccess'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Durable Task Schedulers'
        TableNamePrefix = 'DurableTask_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Endpoint'
            'SKU'
            'Capacity'
            'Allowed IPs'
            'Public Network Access'
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

    SourceCollector = 'manifests/collectors/Integration/DurableTaskSchedulers.psd1'

    ManualConversionReason = 'Durable Task Schedulers had no collector. Property paths from the Microsoft.DurableTask schedulers 2026-02-01 reference.'
}
