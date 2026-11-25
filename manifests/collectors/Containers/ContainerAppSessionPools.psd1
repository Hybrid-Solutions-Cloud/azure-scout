#
# Hand-authored collector (AB#9300): Azure Container Apps dynamic session pools had no collector. Secrets are never projected. Property paths from the Microsoft.App sessionPools reference (2025-01-01 and later).
#
@{
    ResourceTypes = @('microsoft.app/sessionpools')

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
        @{ Name = 'Container Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''containerType'')' }
        @{ Name = 'Pool Management'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''poolManagementType'')' }
        @{ Name = 'Max Concurrent Sessions'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''scaleConfiguration.maxConcurrentSessions'')' }
        @{ Name = 'Ready Sessions'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''scaleConfiguration.readySessionInstances'')' }
        @{ Name = 'Lifecycle'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''dynamicPoolConfiguration.lifecycleConfiguration.lifecycleType'')' }
        @{ Name = 'Environment'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''environmentId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Container App Session Pools'
        TableNamePrefix = 'AcaSessionPools_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Container Type'
            'Pool Management'
            'Max Concurrent Sessions'
            'Ready Sessions'
            'Lifecycle'
            'Environment'
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

    SourceCollector = 'manifests/collectors/Containers/ContainerAppSessionPools.psd1'

    ManualConversionReason = 'Azure Container Apps dynamic session pools had no collector. Secrets are never projected. Property paths from the Microsoft.App sessionPools reference (2025-01-01 and later).'
}
