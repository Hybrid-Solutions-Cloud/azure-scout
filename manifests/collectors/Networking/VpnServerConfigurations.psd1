#
# Hand-authored collector (AB#9300): Point-to-site VPN server configurations had no collector. The RADIUS secret is never projected. Property paths from the Microsoft.Network reference.
#
@{
    ResourceTypes = @('microsoft.network/vpnserverconfigurations')

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
        @{ Name = 'Protocols'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''vpnProtocols'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Authentication'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''vpnAuthenticationTypes'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'RADIUS Server'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''radiusServerAddress'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'VPN Server Configurations'
        TableNamePrefix = 'VpnServerConfigs_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Protocols'
            'Authentication'
            'RADIUS Server'
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

    SourceCollector = 'manifests/collectors/Networking/VpnServerConfigurations.psd1'

    ManualConversionReason = 'Point-to-site VPN server configurations had no collector. The RADIUS secret is never projected. Property paths from the Microsoft.Network reference.'
}
