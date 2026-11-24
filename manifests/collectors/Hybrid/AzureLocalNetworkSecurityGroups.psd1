#
# Hand-authored collector (AB#9300): Network security groups of Azure Local VMs were discovered but not read; their rules are a separate child type. Property paths from the Microsoft.AzureStackHCI reference.
#
@{
    ResourceTypes = @('microsoft.azurestackhci/networksecuritygroups')

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
        @{ Name = 'Network Interfaces'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''networkInterfaces'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Logical Networks'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''subnets'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Azure Local NSGs'
        TableNamePrefix = 'AzLocalNsgs_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Network Interfaces'
            'Logical Networks'
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

    SourceCollector = 'manifests/collectors/Hybrid/AzureLocalNetworkSecurityGroups.psd1'

    ManualConversionReason = 'Network security groups of Azure Local VMs were discovered but not read; their rules are a separate child type. Property paths from the Microsoft.AzureStackHCI reference.'
}
