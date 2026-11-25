#
# Hand-authored collector (AB#9300): Network virtual appliances in Virtual WAN hubs had no collector. SSH keys and cloud-init are never projected. Property paths from the Microsoft.Network reference.
#
@{
    ResourceTypes = @('microsoft.network/networkvirtualappliances')

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
        @{ Name = 'Vendor'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''nvaSku.vendor'')' }
        @{ Name = 'Version'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''nvaSku.marketPlaceVersion'')' }
        @{ Name = 'Scale Unit'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''nvaSku.bundledScaleUnit'')' }
        @{ Name = 'Virtual Hub'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''virtualHub.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'ASN'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''virtualApplianceAsn'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Network Virtual Appliances'
        TableNamePrefix = 'Nvas_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Vendor'
            'Version'
            'Scale Unit'
            'Virtual Hub'
            'ASN'
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

    SourceCollector = 'manifests/collectors/Networking/NetworkVirtualAppliances.psd1'

    ManualConversionReason = 'Network virtual appliances in Virtual WAN hubs had no collector. SSH keys and cloud-init are never projected. Property paths from the Microsoft.Network reference.'
}
