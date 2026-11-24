#
# Hand-authored collector (AB#9300): Network interfaces of Azure Local VMs were discovered but not read. Property paths from the Microsoft.AzureStackHCI reference.
#
@{
    ResourceTypes = @('microsoft.azurestackhci/networkinterfaces')

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
        @{ Name = 'Private IP'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''ipConfigurations.properties.privateIPAddress'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Logical Network'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''ipConfigurations.properties.subnet.id'' -Enumerate) | Where-Object { $_ } | ForEach-Object { ([string]$_ -split ''/'')[-1] } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'MAC Address'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''macAddress'')' }
        @{ Name = 'DNS Servers'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''dnsSettings.dnsServers'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Security Group'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''networkSecurityGroup.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Azure Local VM NICs'
        TableNamePrefix = 'AzLocalNics_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Private IP'
            'Logical Network'
            'MAC Address'
            'DNS Servers'
            'Security Group'
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

    SourceCollector = 'manifests/collectors/Hybrid/AzureLocalNetworkInterfaces.psd1'

    ManualConversionReason = 'Network interfaces of Azure Local VMs were discovered but not read. Property paths from the Microsoft.AzureStackHCI reference.'
}
