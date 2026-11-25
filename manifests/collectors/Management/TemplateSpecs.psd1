#
# Hand-authored collector (AB#9300): ARM template specs had no collector. Property paths from the Microsoft.Resources templateSpecs reference.
#
@{
    ResourceTypes = @('microsoft.resources/templatespecs')

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
        @{ Name = 'Display Name'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''displayName'')' }
        @{ Name = 'Description'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''description'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Template Specs'
        TableNamePrefix = 'TemplateSpecs_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Display Name'
            'Description'
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

    SourceCollector = 'manifests/collectors/Management/TemplateSpecs.psd1'

    ManualConversionReason = 'ARM template specs had no collector. Property paths from the Microsoft.Resources templateSpecs reference.'
}
