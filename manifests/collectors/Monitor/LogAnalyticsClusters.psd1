#
# Hand-authored collector (AB#9300): Log Analytics dedicated clusters (commitment tiers, customer-managed keys) had no collector. Only the key name is projected, never key material. Property paths from the Microsoft.OperationalInsights clusters 2026-03-01 reference.
#
@{
    ResourceTypes = @('microsoft.operationalinsights/clusters')

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
        @{ Name = 'SKU'; Expression = '(Get-AZSCSafeProperty -InputObject $1 -Path ''sku.name'')' }
        @{ Name = 'Capacity (GB/day)'; Expression = '(Get-AZSCSafeProperty -InputObject $1 -Path ''sku.capacity'')' }
        @{ Name = 'Billing'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''billingType'')' }
        @{ Name = 'Double Encryption'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''isDoubleEncryptionEnabled'')' }
        @{ Name = 'Availability Zones'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''isAvailabilityZonesEnabled'')' }
        @{ Name = 'Customer Key'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''keyVaultProperties.keyName'')' }
        @{ Name = 'Workspaces'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''associatedWorkspaces'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Replication'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''replication.enabled'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Log Analytics Clusters'
        TableNamePrefix = 'LaClusters_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'SKU'
            'Capacity (GB/day)'
            'Billing'
            'Double Encryption'
            'Availability Zones'
            'Customer Key'
            'Workspaces'
            'Replication'
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

    SourceCollector = 'manifests/collectors/Monitor/LogAnalyticsClusters.psd1'

    ManualConversionReason = 'Log Analytics dedicated clusters (commitment tiers, customer-managed keys) had no collector. Only the key name is projected, never key material. Property paths from the Microsoft.OperationalInsights clusters 2026-03-01 reference.'
}
