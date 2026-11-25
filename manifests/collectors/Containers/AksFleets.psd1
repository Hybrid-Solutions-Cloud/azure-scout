#
# Hand-authored collector (AB#9300): Azure Kubernetes Fleet Manager fleets had no collector. Property paths from the Microsoft.ContainerService fleets 2026-06-01 reference.
#
@{
    ResourceTypes = @('microsoft.containerservice/fleets')

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
        @{ Name = 'DNS Prefix'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''hubProfile.dnsPrefix'')' }
        @{ Name = 'Hub VM Size'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''hubProfile.agentProfile.vmSize'')' }
        @{ Name = 'Private Hub'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''hubProfile.apiServerAccessProfile.enablePrivateCluster'')' }
        @{ Name = 'Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''status'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'AKS Fleets'
        TableNamePrefix = 'AksFleets_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'DNS Prefix'
            'Hub VM Size'
            'Private Hub'
            'Status'
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

    SourceCollector = 'manifests/collectors/Containers/AksFleets.psd1'

    ManualConversionReason = 'Azure Kubernetes Fleet Manager fleets had no collector. Property paths from the Microsoft.ContainerService fleets 2026-06-01 reference.'
}
