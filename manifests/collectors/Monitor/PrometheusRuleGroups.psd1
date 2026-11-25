#
# Hand-authored collector (AB#9300): Azure Monitor managed Prometheus rule groups had no collector. Property paths from the Microsoft.AlertsManagement prometheusRuleGroups 2023-03-01 reference.
#
@{
    ResourceTypes = @('microsoft.alertsmanagement/prometheusrulegroups')

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
        @{ Name = 'Enabled'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''enabled'')' }
        @{ Name = 'Cluster'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''clusterName'')' }
        @{ Name = 'Interval'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''interval'')' }
        @{ Name = 'Rules'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''rules'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Scopes'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''scopes'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Description'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''description'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Prometheus Rule Groups'
        TableNamePrefix = 'PromRuleGroups_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Enabled'
            'Cluster'
            'Interval'
            'Rules'
            'Scopes'
            'Description'
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

    SourceCollector = 'manifests/collectors/Monitor/PrometheusRuleGroups.psd1'

    ManualConversionReason = 'Azure Monitor managed Prometheus rule groups had no collector. Property paths from the Microsoft.AlertsManagement prometheusRuleGroups 2023-03-01 reference.'
}
