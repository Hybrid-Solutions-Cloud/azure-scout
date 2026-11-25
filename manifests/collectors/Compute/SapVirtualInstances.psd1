#
# Hand-authored collector (AB#9300): Azure Center for SAP solutions virtual instances had no collector. Property paths from the Microsoft.Workloads sapVirtualInstances 2024-09-01 reference.
#
@{
    ResourceTypes = @('microsoft.workloads/sapvirtualinstances')

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
        @{ Name = 'Environment'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''environment'')' }
        @{ Name = 'SAP Product'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''sapProduct'')' }
        @{ Name = 'State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''state'')' }
        @{ Name = 'Health'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''health'')' }
        @{ Name = 'Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''status'')' }
        @{ Name = 'Managed Network Access'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''managedResourcesNetworkAccessType'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'SAP Virtual Instances'
        TableNamePrefix = 'SapVis_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Environment'
            'SAP Product'
            'State'
            'Health'
            'Status'
            'Managed Network Access'
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

    SourceCollector = 'manifests/collectors/Compute/SapVirtualInstances.psd1'

    ManualConversionReason = 'Azure Center for SAP solutions virtual instances had no collector. Property paths from the Microsoft.Workloads sapVirtualInstances 2024-09-01 reference.'
}
