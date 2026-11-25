#
# Hand-authored collector (AB#9300): ExpressRoute Direct ports had no collector. Property paths from the Microsoft.Network reference.
#
@{
    ResourceTypes = @('microsoft.network/expressrouteports')

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
        @{ Name = 'Peering Location'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''peeringLocation'')' }
        @{ Name = 'Bandwidth (Gbps)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''bandwidthInGbps'')' }
        @{ Name = 'Provisioned (Gbps)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisionedBandwidthInGbps'')' }
        @{ Name = 'Encapsulation'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''encapsulation'')' }
        @{ Name = 'Links'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''links'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Circuits'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''circuits'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'ExpressRoute Direct Ports'
        TableNamePrefix = 'ErPorts_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Peering Location'
            'Bandwidth (Gbps)'
            'Provisioned (Gbps)'
            'Encapsulation'
            'Links'
            'Circuits'
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

    SourceCollector = 'manifests/collectors/Networking/ExpressRoutePorts.psd1'

    ManualConversionReason = 'ExpressRoute Direct ports had no collector. Property paths from the Microsoft.Network reference.'
}
