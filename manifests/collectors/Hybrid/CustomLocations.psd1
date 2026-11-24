#
# Hand-authored collector (AB#9300): Arc custom locations, which Azure Local VMs and Arc data services depend on, had no inventory collector. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.extendedlocation/customlocations')

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
        @{ Name = 'Display Name'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''displayName'')' }
        @{ Name = 'Namespace'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''namespace'')' }
        @{ Name = 'Host Resource'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''hostResourceId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Cluster Extensions'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''clusterExtensionIds'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Custom Locations'
        TableNamePrefix = 'CustomLocations_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Display Name'
            'Namespace'
            'Host Resource'
            'Cluster Extensions'
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

    SourceCollector = 'manifests/collectors/Hybrid/CustomLocations.psd1'

    ManualConversionReason = 'Arc custom locations, which Azure Local VMs and Arc data services depend on, had no inventory collector. Fields verified against live rows on 2026-11-24.'
}
