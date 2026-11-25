#
# Hand-authored collector (AB#9300): Virtual network TAPs (traffic mirroring) had no collector. Property paths from the Microsoft.Network reference.
#
@{
    ResourceTypes = @('microsoft.network/virtualnetworktaps')

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
        @{ Name = 'Destination NIC IP Config'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''destinationNetworkInterfaceIPConfiguration.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Destination LB Frontend'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''destinationLoadBalancerFrontEndIPConfiguration.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Destination Port'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''destinationPort'')' }
        @{ Name = 'Mirrored NICs'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''networkInterfaceTapConfigurations'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Virtual Network TAPs'
        TableNamePrefix = 'VnetTaps_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Destination NIC IP Config'
            'Destination LB Frontend'
            'Destination Port'
            'Mirrored NICs'
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

    SourceCollector = 'manifests/collectors/Networking/VirtualNetworkTaps.psd1'

    ManualConversionReason = 'Virtual network TAPs (traffic mirroring) had no collector. Property paths from the Microsoft.Network reference.'
}
