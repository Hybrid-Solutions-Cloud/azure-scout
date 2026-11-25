#
# Hand-authored collector (AB#9300): MongoDB Atlas organizations bought through Azure had no collector. User details are never projected. Property paths from the MongoDB.Atlas 2025-06-01 reference.
#
@{
    ResourceTypes = @('mongodb.atlas/organizations')

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
        @{ Name = 'Organization'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''partnerProperties.organizationName'')' }
        @{ Name = 'Organization ID'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''partnerProperties.organizationId'')' }
        @{ Name = 'Offer'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''marketplace.offerDetails.offerId'')' }
        @{ Name = 'Plan'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''marketplace.offerDetails.planId'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'MongoDB Atlas'
        TableNamePrefix = 'MongoAtlas_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Organization'
            'Organization ID'
            'Offer'
            'Plan'
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

    SourceCollector = 'manifests/collectors/Databases/MongoDBAtlas.psd1'

    ManualConversionReason = 'MongoDB Atlas organizations bought through Azure had no collector. User details are never projected. Property paths from the MongoDB.Atlas 2025-06-01 reference.'
}
