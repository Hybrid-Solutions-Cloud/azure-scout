#
# Hand-authored collector (AB#9300): Arc-enabled server licenses (Extended Security Updates) had no collector. Property paths from the Microsoft.HybridCompute licenses 2026-09-01 reference.
#
@{
    ResourceTypes = @('microsoft.hybridcompute/licenses')

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
        @{ Name = 'License Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseType'')' }
        @{ Name = 'State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseDetails.state'')' }
        @{ Name = 'Target'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseDetails.target'')' }
        @{ Name = 'Edition'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseDetails.edition'')' }
        @{ Name = 'Core Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseDetails.type'')' }
        @{ Name = 'Processors'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseDetails.processors'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc ESU Licenses'
        TableNamePrefix = 'ArcLicenses_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'License Type'
            'State'
            'Target'
            'Edition'
            'Core Type'
            'Processors'
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

    SourceCollector = 'manifests/collectors/Hybrid/ArcServerLicenses.psd1'

    ManualConversionReason = 'Arc-enabled server licenses (Extended Security Updates) had no collector. Property paths from the Microsoft.HybridCompute licenses 2026-09-01 reference.'
}
