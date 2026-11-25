#
# Hand-authored collector (AB#9300): Private Link services (exposing a service to other tenants) had no collector. Property paths from the Microsoft.Network reference.
#
@{
    ResourceTypes = @('microsoft.network/privatelinkservices')

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
        @{ Name = 'Alias'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''alias'')' }
        @{ Name = 'Visibility Subscriptions'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''visibility.subscriptions'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Auto-approved Subscriptions'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''autoApproval.subscriptions'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Proxy Protocol'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''enableProxyProtocol'')' }
        @{ Name = 'Endpoint Connections'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''privateEndpointConnections'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Private Link Services'
        TableNamePrefix = 'PrivateLinkSvcs_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Alias'
            'Visibility Subscriptions'
            'Auto-approved Subscriptions'
            'Proxy Protocol'
            'Endpoint Connections'
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

    SourceCollector = 'manifests/collectors/Networking/PrivateLinkServices.psd1'

    ManualConversionReason = 'Private Link services (exposing a service to other tenants) had no collector. Property paths from the Microsoft.Network reference.'
}
