#
# Hand-authored collector (AB#9300): Proximity placement groups had no collector. Property paths from the Microsoft.Compute SDK models.
#
@{
    ResourceTypes = @('microsoft.compute/proximityplacementgroups')

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
        @{ Name = 'Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''proximityPlacementGroupType'')' }
        @{ Name = 'VMs'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''virtualMachines'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Availability Sets'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''availabilitySets'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Scale Sets'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''virtualMachineScaleSets'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Colocation'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''colocationStatus.code'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Proximity Placement Groups'
        TableNamePrefix = 'Ppgs_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Type'
            'VMs'
            'Availability Sets'
            'Scale Sets'
            'Colocation'
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

    SourceCollector = 'manifests/collectors/Compute/ProximityPlacementGroups.psd1'

    ManualConversionReason = 'Proximity placement groups had no collector. Property paths from the Microsoft.Compute SDK models.'
}
