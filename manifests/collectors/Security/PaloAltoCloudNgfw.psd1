#
# Hand-authored collector (AB#9300): Palo Alto Networks Cloud NGFW firewalls and local rulestacks had no collector. Property paths from the PaloAltoNetworks.Cloudngfw 2026-06-01 reference.
#
@{
    ResourceTypes = @('paloaltonetworks.cloudngfw/firewalls', 'paloaltonetworks.cloudngfw/localrulestacks')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$kind = ([string]$1.type -split '/')[-1]
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
        @{ Name = 'Kind'; Expression = '$kind' }
        @{ Name = 'Panorama Managed'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''isPanoramaManaged'')' }
        @{ Name = 'Strata Cloud Managed'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''isStrataCloudManaged'')' }
        @{ Name = 'Rulestack'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''associatedRulestack.resourceId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Marketplace Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''marketplaceDetails.marketplaceSubscriptionStatus'')' }
        @{ Name = 'Plan'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''planData.planId'')' }
        @{ Name = 'Scope'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''scope'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Palo Alto Cloud NGFW'
        TableNamePrefix = 'PaloAltoNgfw_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'Panorama Managed'
            'Strata Cloud Managed'
            'Rulestack'
            'Marketplace Status'
            'Plan'
            'Scope'
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

    SourceCollector = 'manifests/collectors/Security/PaloAltoCloudNgfw.psd1'

    ManualConversionReason = 'Palo Alto Networks Cloud NGFW firewalls and local rulestacks had no collector. Property paths from the PaloAltoNetworks.Cloudngfw 2026-06-01 reference.'
}
