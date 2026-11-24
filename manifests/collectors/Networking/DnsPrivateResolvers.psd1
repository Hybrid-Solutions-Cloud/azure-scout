#
# Hand-authored collector (AB#9300): Azure DNS Private Resolvers had no collector. Property paths from the Microsoft.Network dnsResolvers 2025-05-01 reference.
#
@{
    ResourceTypes = @('microsoft.network/dnsresolvers')

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
        @{ Name = 'Virtual Network'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''virtualNetwork.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''dnsResolverState'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'DNS Private Resolvers'
        TableNamePrefix = 'DnsResolvers_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Virtual Network'
            'State'
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

    SourceCollector = 'manifests/collectors/Networking/DnsPrivateResolvers.psd1'

    ManualConversionReason = 'Azure DNS Private Resolvers had no collector. Property paths from the Microsoft.Network dnsResolvers 2025-05-01 reference.'
}
