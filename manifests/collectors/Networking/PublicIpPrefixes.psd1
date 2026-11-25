#
# Hand-authored collector (AB#9300): Public IP prefixes and custom (BYOIP) prefixes had no collector. Property paths from the Microsoft.Network reference.
#
@{
    ResourceTypes = @('microsoft.network/publicipprefixes', 'microsoft.network/customipprefixes')

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
        @{ Name = 'Prefix'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''ipPrefix''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''cidr'' }; $v }' }
        @{ Name = 'Prefix Length'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''prefixLength'')' }
        @{ Name = 'IP Version'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''publicIPAddressVersion'')' }
        @{ Name = 'Commissioned State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''commissionedState'')' }
        @{ Name = 'Custom Prefix'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''customIPPrefix.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Public IP Prefixes'
        TableNamePrefix = 'PipPrefixes_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'Prefix'
            'Prefix Length'
            'IP Version'
            'Commissioned State'
            'Custom Prefix'
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

    SourceCollector = 'manifests/collectors/Networking/PublicIpPrefixes.psd1'

    ManualConversionReason = 'Public IP prefixes and custom (BYOIP) prefixes had no collector. Property paths from the Microsoft.Network reference.'
}
