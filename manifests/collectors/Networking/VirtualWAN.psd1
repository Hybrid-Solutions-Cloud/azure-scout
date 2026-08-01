# Declarative equivalent of Networking/VirtualWAN.ps1.  The VPN-site branch is represented by a
# conditional loop source: a missing site emits one null iteration, preserving the legacy branch's
# one row per virtual hub without adding a collector-specific interpreter branch.
@{
    ResourceTypes = @('microsoft.network/virtualwans')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    ManualConversionReason = 'The imperative branches have different loop depth. A conditional loop source preserves their row cardinality; tests/ConditionalTopologyCollector.Tests.ps1 proves both branches against the imperative collector.'

    SetupPreamble = @'
$VirtualHub = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/virtualhubs' }
$VPNSite = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/vpnsites' }
'@
    SetupVariables = @('VirtualHub','VPNSite')

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$vhub = $VirtualHub | Where-Object { $_.ID -in $data.virtualHubs.id }
$vpn = $VPNSite | Where-Object { $_.ID -in $data.vpnSites.id }
$Retired = $Retirements | Where-Object { $_.id -eq $1.id }
if ($Retired) {
    $RetiredFeature = foreach ($Retire in $Retired) {
        $RetiredServiceID = $Unsupported | Where-Object {$_.Id -eq $Retired.ServiceID}
        [pscustomobject]@{
            'RetiredFeature' = $RetiredServiceID.RetiringFeature
            'RetiredDate' = $RetiredServiceID.RetirementDate
        }
    }
    $RetiringFeature = if (@($RetiredFeature.RetiredFeature).count -gt 1) { $RetiredFeature.RetiredFeature | ForEach-Object { $_ + ' ,' } } else { $RetiredFeature.RetiredFeature }
    $RetiringFeature = [string]$RetiringFeature
    $RetiringFeature = if ($RetiringFeature -like '* ,*') { $RetiringFeature -replace ".$" } else { $RetiringFeature }
    $RetiringDate = if (@($RetiredFeature.RetiredDate).count -gt 1) { $RetiredFeature.RetiredDate | ForEach-Object { $_ + ' ,' } } else { $RetiredFeature.RetiredDate }
    $RetiringDate = [string]$RetiringDate
    $RetiringDate = if ($RetiringDate -like '* ,*') { $RetiringDate -replace ".$" } else { $RetiringDate }
} else {
    $RetiringFeature = $null
    $RetiringDate = $null
}
$Tags = if(![string]::IsNullOrEmpty($1.tags.psobject.properties)){$1.tags.psobject.properties}else{'0'}
'@

    AdditionalRowLoops = @(
        # AB#6845: loop 3 was already guarded; loop 2 was not, so a virtual WAN whose hubs are
        # absent from the collected set -- a WAN created before its first hub, or one whose hubs
        # sit outside the requested scope -- disappeared from the worksheet even though loop 3
        # was carefully written to keep it when its VPN sites were missing.
        @{ Variable = '2'; Source = '$vhub'; EmitNullWhenEmpty = $true; Preamble = '' }
        @{ Variable = '3'; Source = '$vpn'; EmitNullWhenEmpty = $true; Preamble = '' }
    )
    TagLoop = @{ Variable = 'Tag'; Source = '$Tags'; Preamble = '' }

    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Subscription'; Expression = '$sub1.Name' }
        @{ Name = 'Resource Group'; Expression = '$1.RESOURCEGROUP' }
        @{ Name = 'Name'; Expression = '$1.NAME' }
        @{ Name = 'Location'; Expression = '$1.LOCATION' }
        @{ Name = 'Retiring Feature'; Expression = '$RetiringFeature' }
        @{ Name = 'Retiring Date'; Expression = '$RetiringDate' }
        @{ Name = 'Allow BranchToBranch Traffic'; Expression = '$data.allowBranchToBranchTraffic' }
        @{ Name = 'Allow VnetToVnet Traffic'; Expression = '$data.allowVnetToVnetTraffic' }
        @{ Name = 'Disable Vpn Encryption'; Expression = '$data.disableVpnEncryption' }
        @{ Name = 'HUB Name'; Expression = '[string]$2.name' }
        @{ Name = 'HUB Location'; Expression = '[string]$2.location' }
        @{ Name = 'HUB Address Prefix'; Expression = '[string]$2.properties.addressPrefix' }
        @{ Name = 'HUB Gateway Preference'; Expression = '[string]$2.properties.preferredRoutingGateway' }
        @{ Name = 'HUB Router ASN'; Expression = '[string]$2.properties.virtualRouterAsn' }
        @{ Name = 'HUB Router IPs'; Expression = '[string]($2.properties.virtualRouterIps | Select-Object -Unique)' }
        @{ Name = 'Virtual Site Name'; Expression = 'if ($null -ne $3) { [string]$3.name } else { $null }' }
        @{ Name = 'Device Vendor'; Expression = 'if ($null -ne $3) { [string]$3.properties.deviceProperties.deviceVendor } else { $null }' }
        @{ Name = 'Device Vendor IpAddress'; Expression = 'if ($null -ne $3) { [string]$3.properties.vpnSiteLinks.properties.ipAddress } else { $null }' }
        @{ Name = 'Link Provider name'; Expression = 'if ($null -ne $3) { [string]$3.properties.vpnSiteLinks.properties.linkProperties.linkProviderName } else { $null }' }
        @{ Name = 'Link Speed in Mbps'; Expression = 'if ($null -ne $3) { [string]$3.properties.vpnSiteLinks.properties.linkProperties.linkSpeedInMbps } else { $null }' }
        @{ Name = 'Virtual Site Private Address Space'; Expression = 'if ($null -ne $3) { [string]$3.properties.addressSpace.addressPrefixes } else { $null }' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = 'if ($Tag -is [string]) { [string]$null } else { [string]$Tag.Name }' }
        @{ Name = 'Tag Value'; Expression = 'if ($Tag -is [string]) { [string]$null } else { [string]$Tag.Value }' }
    )
    Export = @{
        WorksheetName = 'Virtual WAN'
        TableNamePrefix = 'VWANTable_'
        Columns = @('Subscription','Resource Group','Name','Location','Retiring Feature','Retiring Date','Allow BranchToBranch Traffic','Allow VnetToVnet Traffic','Disable Vpn Encryption','HUB Name','HUB Location','HUB Address Prefix','HUB Gateway Preference','HUB Router ASN','HUB Router IPs','Virtual Site Name','Device Vendor','Device Vendor IpAddress','Link Provider name','Link Speed in Mbps','Virtual Site Private Address Space','Resource U')
        TagColumns = @('Tag Name','Tag Value')
        TagColumnsBefore = 'Resource U'
        NumberFormat = '0'
        ConditionalText = @('New-ConditionalText -Range E2:E100 -ConditionalType ContainsText')
    }
    SourceCollector = 'Modules/Public/InventoryModules/Networking/VirtualWAN.ps1'
}
