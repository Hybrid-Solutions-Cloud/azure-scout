#
# Hand-authored collector (AB#9300): Cluster extensions (how AKS on Azure Local, Container Storage, Defender and Flux appear) were discovered but not read. Configuration settings and protected settings are never projected. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.kubernetesconfiguration/extensions')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$clusterParts = @((([string]$1.id -split '/providers/microsoft.kubernetesconfiguration', 2)[0]) -split '/')
$clusterName = $clusterParts[-1]
$clusterType = if ($clusterParts.Count -ge 3) { $clusterParts[-3] + '/' + $clusterParts[-2] } else { $null }
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
        @{ Name = 'Cluster'; Expression = '$clusterName' }
        @{ Name = 'Cluster Type'; Expression = '$clusterType' }
        @{ Name = 'Extension Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''extensionType'')' }
        @{ Name = 'Version'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''version'')' }
        @{ Name = 'Install State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''installState'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Release Train'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''releaseTrain'')' }
        @{ Name = 'Auto Upgrade Minor'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''autoUpgradeMinorVersion'')' }
        @{ Name = 'Release Namespace'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''scope.cluster.releaseNamespace'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Kubernetes Extensions'
        TableNamePrefix = 'K8sExtensions_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Cluster'
            'Cluster Type'
            'Extension Type'
            'Version'
            'Install State'
            'Provisioning State'
            'Release Train'
            'Auto Upgrade Minor'
            'Release Namespace'
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

    SourceCollector = 'manifests/collectors/Hybrid/KubernetesExtensions.psd1'

    ManualConversionReason = 'Cluster extensions (how AKS on Azure Local, Container Storage, Defender and Flux appear) were discovered but not read. Configuration settings and protected settings are never projected. Fields verified against live rows on 2026-11-24.'
}
