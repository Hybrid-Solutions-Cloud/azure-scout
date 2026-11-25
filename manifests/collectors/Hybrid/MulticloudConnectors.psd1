#
# Hand-authored collector (AB#9300): Azure Arc multicloud connectors (AWS and GCP onboarding) had no collector. Property paths from the Microsoft.HybridConnectivity publicCloudConnectors reference.
#
@{
    ResourceTypes = @('microsoft.hybridconnectivity/publiccloudconnectors')

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
        @{ Name = 'Host Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''hostType'')' }
        @{ Name = 'AWS Account'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''awsCloudProfile.accountId'')' }
        @{ Name = 'AWS Organization'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''awsCloudProfile.isOrganizationalAccount'')' }
        @{ Name = 'Excluded Accounts'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''awsCloudProfile.excludedAccounts'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Primary Identifier'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''connectorPrimaryIdentifier'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc Multicloud Connectors'
        TableNamePrefix = 'ArcMulticloud_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Host Type'
            'AWS Account'
            'AWS Organization'
            'Excluded Accounts'
            'Primary Identifier'
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

    SourceCollector = 'manifests/collectors/Hybrid/MulticloudConnectors.psd1'

    ManualConversionReason = 'Azure Arc multicloud connectors (AWS and GCP onboarding) had no collector. Property paths from the Microsoft.HybridConnectivity publicCloudConnectors reference.'
}
