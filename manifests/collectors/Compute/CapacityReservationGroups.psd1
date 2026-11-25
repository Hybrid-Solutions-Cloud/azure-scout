#
# Hand-authored collector (AB#9300): On-demand capacity reservation groups had no collector. Property paths from the Microsoft.Compute SDK models.
#
@{
    ResourceTypes = @('microsoft.compute/capacityreservationgroups')

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
        @{ Name = 'Zones'; Expression = '(@($1.zones) -join '', '')' }
        @{ Name = 'Reservations'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''capacityReservations'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Associated VMs'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''virtualMachinesAssociated'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Shared With'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''sharingProfile.subscriptionIds'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Capacity Reservation Groups'
        TableNamePrefix = 'CapReservations_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Zones'
            'Reservations'
            'Associated VMs'
            'Shared With'
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

    SourceCollector = 'manifests/collectors/Compute/CapacityReservationGroups.psd1'

    ManualConversionReason = 'On-demand capacity reservation groups had no collector. Property paths from the Microsoft.Compute SDK models.'
}
