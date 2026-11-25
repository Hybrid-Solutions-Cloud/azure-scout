#
# Hand-authored collector (AB#9300): Virtual WAN site-to-site, point-to-site and ExpressRoute gateways were read only inline by the Virtual WAN collector. Property paths from the Microsoft.Network reference.
#
@{
    ResourceTypes = @('microsoft.network/vpngateways', 'microsoft.network/p2svpngateways', 'microsoft.network/expressroutegateways')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$kind = ([string]$1.type -split '/')[-1]
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
        @{ Name = 'Kind'; Expression = '$kind' }
        @{ Name = 'Virtual Hub'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''virtualHub.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Scale Units'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''vpnGatewayScaleUnit''; if ($null -eq $v) { $min = Get-AZSCSafeProperty -InputObject $data -Path ''autoScaleConfiguration.bounds.min''; $max = Get-AZSCSafeProperty -InputObject $data -Path ''autoScaleConfiguration.bounds.max''; if ($null -ne $min -or $null -ne $max) { $v = ''{0}-{1}'' -f $min, $max } }; $v }' }
        @{ Name = 'Connections'; Expression = '@(@(Get-AZSCSafeProperty -InputObject $data -Path ''connections'') + @(Get-AZSCSafeProperty -InputObject $data -Path ''expressRouteConnections'') + @(Get-AZSCSafeProperty -InputObject $data -Path ''p2SConnectionConfigurations'') | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'BGP ASN'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''bgpSettings.asn'')' }
        @{ Name = 'VPN Server Configuration'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''vpnServerConfiguration.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Virtual WAN Gateways'
        TableNamePrefix = 'VwanGateways_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'Virtual Hub'
            'Scale Units'
            'Connections'
            'BGP ASN'
            'VPN Server Configuration'
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

    SourceCollector = 'manifests/collectors/Networking/VirtualWanGateways.psd1'

    ManualConversionReason = 'Virtual WAN site-to-site, point-to-site and ExpressRoute gateways were read only inline by the Virtual WAN collector. Property paths from the Microsoft.Network reference.'
}
