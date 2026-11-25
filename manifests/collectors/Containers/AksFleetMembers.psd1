#
# Hand-authored collector (AB#9300): Members of AKS fleets had no collector. Property paths from the Microsoft.ContainerService fleets/members reference.
#
@{
    ResourceTypes = @('microsoft.containerservice/fleets/members')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$fleetName = ([string]$1.id -split '/')[-3]
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
        @{ Name = 'Fleet'; Expression = '$fleetName' }
        @{ Name = 'Cluster'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''clusterResourceId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Update Group'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''group'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'AKS Fleet Members'
        TableNamePrefix = 'AksFleetMembers_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Fleet'
            'Cluster'
            'Update Group'
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

    SourceCollector = 'manifests/collectors/Containers/AksFleetMembers.psd1'

    ManualConversionReason = 'Members of AKS fleets had no collector. Property paths from the Microsoft.ContainerService fleets/members reference.'
}
