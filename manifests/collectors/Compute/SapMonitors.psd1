#
# Hand-authored collector (AB#9300): Azure Monitor for SAP solutions monitors had no collector. Property paths from the Microsoft.Workloads monitors 2023-04-01 reference.
#
@{
    ResourceTypes = @('microsoft.workloads/monitors')

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
        @{ Name = 'Routing Preference'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''routingPreference'')' }
        @{ Name = 'App Location'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''appLocation'')' }
        @{ Name = 'Subnet'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''monitorSubnet''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Log Analytics Workspace'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''logAnalyticsWorkspaceArmId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Zone Redundancy'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''zoneRedundancyPreference'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Azure Monitor for SAP'
        TableNamePrefix = 'SapMonitors_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Routing Preference'
            'App Location'
            'Subnet'
            'Log Analytics Workspace'
            'Zone Redundancy'
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

    SourceCollector = 'manifests/collectors/Compute/SapMonitors.psd1'

    ManualConversionReason = 'Azure Monitor for SAP solutions monitors had no collector. Property paths from the Microsoft.Workloads monitors 2023-04-01 reference.'
}
