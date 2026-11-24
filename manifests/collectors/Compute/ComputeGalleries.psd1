#
# Hand-authored collector (AB#9300): Azure Compute Galleries had no collector. Property paths from the Microsoft.Compute galleries reference.
#
@{
    ResourceTypes = @('microsoft.compute/galleries')

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
        @{ Name = 'Description'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''description'')' }
        @{ Name = 'Sharing'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''sharingProfile.permissions'')' }
        @{ Name = 'Soft Delete'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''softDeletePolicy.isSoftDeleteEnabled'')' }
        @{ Name = 'Unique Name'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''identifier.uniqueName'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Compute Galleries'
        TableNamePrefix = 'ComputeGalleries_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Description'
            'Sharing'
            'Soft Delete'
            'Unique Name'
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

    SourceCollector = 'manifests/collectors/Compute/ComputeGalleries.psd1'

    ManualConversionReason = 'Azure Compute Galleries had no collector. Property paths from the Microsoft.Compute galleries reference.'
}
