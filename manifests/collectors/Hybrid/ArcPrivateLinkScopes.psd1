#
# Hand-authored collector (AB#9300): Arc private link scopes had no collector. Property paths from the Microsoft.HybridCompute privateLinkScopes reference.
#
@{
    ResourceTypes = @('microsoft.hybridcompute/privatelinkscopes')

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
        @{ Name = 'Public Network Access'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''publicNetworkAccess'')' }
        @{ Name = 'Endpoint Connections'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''privateEndpointConnections'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Scope ID'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''privateLinkScopeId'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc Private Link Scopes'
        TableNamePrefix = 'ArcPls_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Public Network Access'
            'Endpoint Connections'
            'Scope ID'
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

    SourceCollector = 'manifests/collectors/Hybrid/ArcPrivateLinkScopes.psd1'

    ManualConversionReason = 'Arc private link scopes had no collector. Property paths from the Microsoft.HybridCompute privateLinkScopes reference.'
}
