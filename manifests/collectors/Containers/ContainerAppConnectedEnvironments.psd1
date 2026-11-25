#
# Hand-authored collector (AB#9300): Container Apps connected (Arc) environments had no collector. Connection strings and certificate material are never projected. Property paths from the Microsoft.App connectedEnvironments reference.
#
@{
    ResourceTypes = @('microsoft.app/connectedenvironments')

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
        @{ Name = 'Default Domain'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''defaultDomain'')' }
        @{ Name = 'Static IP'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''staticIp'')' }
        @{ Name = 'DNS Suffix'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''customDomainConfiguration.dnsSuffix'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Container App Arc Environments'
        TableNamePrefix = 'AcaConnectedEnv_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Default Domain'
            'Static IP'
            'DNS Suffix'
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

    SourceCollector = 'manifests/collectors/Containers/ContainerAppConnectedEnvironments.psd1'

    ManualConversionReason = 'Container Apps connected (Arc) environments had no collector. Connection strings and certificate material are never projected. Property paths from the Microsoft.App connectedEnvironments reference.'
}
