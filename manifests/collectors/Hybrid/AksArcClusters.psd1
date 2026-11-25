#
# Hand-authored collector (AB#9300): AKS enabled by Azure Arc (AKS on Azure Local) cluster instances had no collector. Property paths from the Microsoft.HybridContainerService provisionedClusterInstances 2024-01-01 reference.
#
@{
    ResourceTypes = @('microsoft.hybridcontainerservice/provisionedclusterinstances', 'microsoft.hybridcontainerservice/provisionedclusters')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$clusterParts = @((([string]$1.id -split '/providers/microsoft.hybridcontainerservice', 2)[0]) -split '/')
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
        @{ Name = 'Connected Cluster'; Expression = '$clusterParts[-1]' }
        @{ Name = 'Kubernetes Version'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''kubernetesVersion'')' }
        @{ Name = 'Control Plane Nodes'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''controlPlane.count'')' }
        @{ Name = 'Agent Pools'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''agentPoolProfiles'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Agent Nodes'; Expression = '(@(Get-AZSCSafeProperty -InputObject $data -Path ''agentPoolProfiles'') | Where-Object { $null -ne $_ } | ForEach-Object { [int](Get-AZSCSafeProperty -InputObject $_ -Path ''count'') } | Measure-Object -Sum).Sum' }
        @{ Name = 'Azure Hybrid Benefit'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseProfile.azureHybridBenefit'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'AKS Arc Clusters'
        TableNamePrefix = 'AksArc_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Connected Cluster'
            'Kubernetes Version'
            'Control Plane Nodes'
            'Agent Pools'
            'Agent Nodes'
            'Azure Hybrid Benefit'
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

    SourceCollector = 'manifests/collectors/Hybrid/AksArcClusters.psd1'

    ManualConversionReason = 'AKS enabled by Azure Arc (AKS on Azure Local) cluster instances had no collector. Property paths from the Microsoft.HybridContainerService provisionedClusterInstances 2024-01-01 reference.'
}
