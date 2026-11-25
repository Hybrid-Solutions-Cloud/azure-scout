#
# Hand-authored collector (AB#9300): Application Gateway for Containers had no collector. Property paths from the Microsoft.ServiceNetworking SDK models.
#
@{
    ResourceTypes = @('microsoft.servicenetworking/trafficcontrollers')

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
        @{ Name = 'Configuration Endpoints'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''configurationEndpoints'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Frontends'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''frontends'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Associations'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''associations'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'App Gateway for Containers'
        TableNamePrefix = 'AGC_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Configuration Endpoints'
            'Frontends'
            'Associations'
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

    SourceCollector = 'manifests/collectors/Containers/AppGatewayForContainers.psd1'

    ManualConversionReason = 'Application Gateway for Containers had no collector. Property paths from the Microsoft.ServiceNetworking SDK models.'
}
