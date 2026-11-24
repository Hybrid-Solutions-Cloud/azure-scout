#
# Hand-authored collector (AB#9300): VM restore point collections were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.compute/restorepointcollections')

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
        @{ Name = 'Source VM'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''source.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Source Location'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''source.location'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Restore Point Collections'
        TableNamePrefix = 'RestorePoints_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Source VM'
            'Source Location'
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

    SourceCollector = 'manifests/collectors/Compute/RestorePointCollections.psd1'

    ManualConversionReason = 'VM restore point collections were discovered but not read. Fields verified against live rows on 2026-11-24.'
}
