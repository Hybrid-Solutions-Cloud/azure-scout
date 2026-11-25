#
# Hand-authored collector (AB#9300): Azure Operator Nexus clusters and network fabrics had no collector. Property paths from the Microsoft.NetworkCloud and Microsoft.ManagedNetworkFabric SDK models.
#
@{
    ResourceTypes = @('microsoft.networkcloud/clusters', 'microsoft.managednetworkfabric/networkfabrics')

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
        @{ Name = 'Cluster Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''clusterType'')' }
        @{ Name = 'Version'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''clusterVersion''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''fabricVersion'' }; $v }' }
        @{ Name = 'Detailed Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''detailedStatus'')' }
        @{ Name = 'Configuration State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''configurationState'')' }
        @{ Name = 'Administrative State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''administrativeState'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Operator Nexus'
        TableNamePrefix = 'OperatorNexus_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'Cluster Type'
            'Version'
            'Detailed Status'
            'Configuration State'
            'Administrative State'
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

    SourceCollector = 'manifests/collectors/Networking/OperatorNexus.psd1'

    ManualConversionReason = 'Azure Operator Nexus clusters and network fabrics had no collector. Property paths from the Microsoft.NetworkCloud and Microsoft.ManagedNetworkFabric SDK models.'
}
