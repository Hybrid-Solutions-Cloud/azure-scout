#
# Hand-authored collector (AB#9300): Confluent Cloud organizations had no collector. User details and link tokens are never projected. Property paths from the Microsoft.Confluent organizations reference.
#
@{
    ResourceTypes = @('microsoft.confluent/organizations')

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
        @{ Name = 'Plan'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''offerDetail.planName'')' }
        @{ Name = 'Plan ID'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''offerDetail.planId'')' }
        @{ Name = 'Publisher'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''offerDetail.publisherId'')' }
        @{ Name = 'Offer Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''offerDetail.status'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Confluent Cloud'
        TableNamePrefix = 'Confluent_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Plan'
            'Plan ID'
            'Publisher'
            'Offer Status'
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

    SourceCollector = 'manifests/collectors/Analytics/ConfluentOrganizations.psd1'

    ManualConversionReason = 'Confluent Cloud organizations had no collector. User details and link tokens are never projected. Property paths from the Microsoft.Confluent organizations reference.'
}
