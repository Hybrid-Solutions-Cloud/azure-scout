#
# Hand-authored collector (AB#9300): DNS forwarding rulesets had no collector. Property paths from the Microsoft.Network dnsForwardingRulesets 2025-05-01 reference.
#
@{
    ResourceTypes = @('microsoft.network/dnsforwardingrulesets')

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
        @{ Name = 'Outbound Endpoints'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''dnsResolverOutboundEndpoints'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'DNS Forwarding Rulesets'
        TableNamePrefix = 'DnsRulesets_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Outbound Endpoints'
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

    SourceCollector = 'manifests/collectors/Networking/DnsForwardingRulesets.psd1'

    ManualConversionReason = 'DNS forwarding rulesets had no collector. Property paths from the Microsoft.Network dnsForwardingRulesets 2025-05-01 reference.'
}
