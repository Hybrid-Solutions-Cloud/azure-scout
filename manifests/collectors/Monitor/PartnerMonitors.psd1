#
# Hand-authored collector (AB#9300): Datadog, Elastic, Dynatrace and New Relic monitors (telemetry sent to a third party) had no collector. User contact details are not projected. Datadog fields verified against live rows on 2026-11-24; the others from their SDK models.
#
@{
    ResourceTypes = @('microsoft.datadog/monitors', 'microsoft.elastic/monitors', 'dynatrace.observability/monitors', 'newrelic.observability/monitors')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$provider = ([string]$1.type -split '/')[0]
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
        @{ Name = 'Provider'; Expression = '$provider' }
        @{ Name = 'Monitoring Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''monitoringStatus'')' }
        @{ Name = 'Marketplace Status'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''marketplaceSubscriptionStatus''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''saaSAzureSubscriptionStatus'' }; $v }' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Partner Monitors'
        TableNamePrefix = 'PartnerMonitors_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Provider'
            'Monitoring Status'
            'Marketplace Status'
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

    SourceCollector = 'manifests/collectors/Monitor/PartnerMonitors.psd1'

    ManualConversionReason = 'Datadog, Elastic, Dynatrace and New Relic monitors (telemetry sent to a third party) had no collector. User contact details are not projected. Datadog fields verified against live rows on 2026-11-24; the others from their SDK models.'
}
