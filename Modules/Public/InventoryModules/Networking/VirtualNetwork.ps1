<#
.Synopsis
Inventory for Azure Virtual Network

.DESCRIPTION
This script consolidates information for all microsoft.network/virtualnetworks and  resource provider in $Resources variable. 
Excel Sheet Name: VirtualNetwork

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Network_1/VirtualNetwork.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 19th November, 2020
Authors: Claudio Merola and Renato Gregio 

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task ,$File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing') {

    $VirtualNetwork = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/virtualnetworks' }

    if($VirtualNetwork)
        {
            $tmp = foreach ($1 in $VirtualNetwork) {
                $ResUCount = 1
                # An EMPTY $sub1 is not $null -- the match is empty for any resource whose subscription
                # is outside the requested scope -- and reading .Name off an empty collection throws
                # under StrictMode (AB#5671). Resolved once here, as VirtualMachine.ps1 already does.
                $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
                # The else arm is $null, NOT '': with StrictMode off $sub1.Name on an unmatched ($null)
                # $sub1 evaluated to $null, and the ~110 collectors that still read $sub1.Name directly
                # emit $null here. '' was a silent behaviour change -- the declarative equivalence proof
                # caught it on 11 collectors, and it would have been invisible on the rest (AB#5659).
                $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { $null }
                $data = $1.PROPERTIES
                $Retired = Foreach ($Retirement in $Retirements)
                    {
                        if ($Retirement.id -eq $1.id) { $Retirement }
                    }
                if ($Retired) 
                    {
                        $RetiredFeature = foreach ($Retire in $Retired)
                            {
                                $RetiredServiceID = $Unsupported | Where-Object {$_.Id -eq $Retired.ServiceID}
                                $tmp0 = [pscustomobject]@{
                                        'RetiredFeature'            = $RetiredServiceID.RetiringFeature
                                        'RetiredDate'               = $RetiredServiceID.RetirementDate 
                                    }
                                $tmp0
                            }
                        $RetiringFeature = if (@($RetiredFeature.RetiredFeature).count -gt 1) { $RetiredFeature.RetiredFeature | ForEach-Object { $_ + ' ,' } }else { $RetiredFeature.RetiredFeature}
                        $RetiringFeature = [string]$RetiringFeature
                        $RetiringFeature = if ($RetiringFeature -like '* ,*') { $RetiringFeature -replace ".$" }else { $RetiringFeature }

                        $RetiringDate = if (@($RetiredFeature.RetiredDate).count -gt 1) { $RetiredFeature.RetiredDate | ForEach-Object { $_ + ' ,' } }else { $RetiredFeature.RetiredDate}
                        $RetiringDate = [string]$RetiringDate
                        $RetiringDate = if ($RetiringDate -like '* ,*') { $RetiringDate -replace ".$" }else { $RetiringDate }
                    }
                else 
                    {
                        $RetiringFeature = $null
                        $RetiringDate = $null
                    }
                # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                # than carrying an empty object, so the raw read throws under StrictMode -- and so
                # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }

                $AddrPool = if (@((Get-AZSCSafeProperty -InputObject $data -Path 'addressSpace.addressPrefixes' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $data -Path 'addressSpace.addressPrefixes' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $data -Path 'addressSpace.addressPrefixes' -Enumerate) }
                $AddrPool = [string]$AddrPool
                $AddrPool = if ($AddrPool -like '* ,*') { $AddrPool -replace ".$" }else { $AddrPool }

                $DNSServers = if (@((Get-AZSCSafeProperty -InputObject $data -Path 'dhcpOptions.dnsServers' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $data -Path 'dhcpOptions.dnsServers' -Enumerate)| ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $data -Path 'dhcpOptions.dnsServers' -Enumerate) }
                $DNSServers = [string]$DNSServers
                $DNSServers = if ($DNSServers -like '* ,*') { $DNSServers -replace ".$" }else { $DNSServers }

                foreach ($2 in (Get-AZSCSafeProperty -InputObject $data -Path 'subnets' -Enumerate))
                    {
                        $ConsumedIPs = [int]@((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.ipConfigurations.id' -Enumerate)).count
                        $Prefixes = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.addressPrefix' -Enumerate))){(Get-AZSCSafeProperty -InputObject $2 -Path 'properties.addressPrefix' -Enumerate)}else{(Get-AZSCSafeProperty -InputObject $2 -Path 'properties.addressPrefixes' -Enumerate)}
                        # This is a CIDR mask, not a resource id: '10.0.0.0/24'.split('/')[1] is '24'.
                        # A subnet with neither addressPrefix nor addressPrefixes leaves $Prefixes
                        # empty, and index [1] of a one-element split then throws under StrictMode
                        # instead of returning $null (AB#5671). Get-AZSCIdSegment is index-guarded
                        # '/'-splitting, which is exactly what is wanted here too.
                        $Prefix = Get-AZSCIdSegment -Id $Prefixes -Index 1
                        $AvailableIPs = $null

                        $Delegations = if (@((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.delegations.properties.servicename' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.delegations.properties.servicename' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.delegations.properties.servicename' -Enumerate)}
                        $Delegations = [string]$Delegations
                        $Delegations = if ($Delegations -like '* ,*') { $Delegations -replace ".$" }else { $Delegations }

                        $SubnetNSG = if ((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.networkSecurityGroup.id' -Enumerate)) { (Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.networkSecurityGroup.id' -Enumerate) -Index 8) } else {'None'}

                        switch ([int]$Prefix)
                            {
                                8 {$AvailableIPs = 16777211 - $ConsumedIPs}
                                9 {$AvailableIPs = 8388603 - $ConsumedIPs}
                                10 {$AvailableIPs = 4194299 - $ConsumedIPs}
                                11 {$AvailableIPs = 2097147 - $ConsumedIPs}
                                12 {$AvailableIPs = 1048571 - $ConsumedIPs}
                                13 {$AvailableIPs = 524283 - $ConsumedIPs}
                                14 {$AvailableIPs = 262139 - $ConsumedIPs}
                                15 {$AvailableIPs = 131067 - $ConsumedIPs}
                                16 {$AvailableIPs = 65531 - $ConsumedIPs}
                                17 {$AvailableIPs = 32763 - $ConsumedIPs}
                                18 {$AvailableIPs = 16379 - $ConsumedIPs}
                                19 {$AvailableIPs = 8187 - $ConsumedIPs}
                                20 {$AvailableIPs = 4091 - $ConsumedIPs}
                                21 {$AvailableIPs = 2043 - $ConsumedIPs}
                                22 {$AvailableIPs = 1019 - $ConsumedIPs}
                                23 {$AvailableIPs = 507 - $ConsumedIPs}
                                24 {$AvailableIPs = 251 - $ConsumedIPs}
                                25 {$AvailableIPs = 123 - $ConsumedIPs}
                                26 {$AvailableIPs = 59 - $ConsumedIPs}
                                27 {$AvailableIPs = 27 - $ConsumedIPs}
                                28 {$AvailableIPs = 11 - $ConsumedIPs}
                                29 {$AvailableIPs = 4 - $ConsumedIPs}
                                30 {$AvailableIPs = 2 - $ConsumedIPs}
                                31 {$AvailableIPs = 2 - $ConsumedIPs}
                                32 {$AvailableIPs = 1 - $ConsumedIPs}
                                Default 
                                    {
                                        $null
                                    }
                            }
                        foreach ($Tag in $Tags) 
                            {
                                $obj = @{
                                    'ID'                                           = $1.id;
                                    'Subscription'                                 = $SubscriptionName;
                                    'Resource Group'                               = $1.RESOURCEGROUP;
                                    'Name'                                         = $1.NAME;
                                    'Location'                                     = $1.LOCATION;
                                    'Retiring Feature'                             = $RetiringFeature;
                                    'Retiring Date'                                = $RetiringDate;
                                    'Address Space'                                = $AddrPool;
                                    'Enable DDOS Protection'                       = (Get-AZSCSafeProperty -InputObject $data -Path 'enableDdosProtection' -Enumerate);
                                    'DNS Servers'                                  = $DNSServers;
                                    'Consumed IPs'                                 = [string]$ConsumedIPs;
                                    'Available IPs'                                = [string]$AvailableIPs;
                                    'Subnet Name'                                  = (Get-AZSCSafeProperty -InputObject $2 -Path 'name' -Enumerate);
                                    'Private Subnet'                               = if((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.defaultOutboundAccess' -Enumerate) -eq 'false'){$true}else{$false};
                                    'Subnet Prefix'                                = [string]$Prefixes;
                                    'Subnet Private Link Service Network Policies' = (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.privateLinkServiceNetworkPolicies' -Enumerate);
                                    'Subnet Private Endpoint Network Policies'     = (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.privateEndpointNetworkPolicies' -Enumerate);
                                    'Subnet Delegations'                           = $Delegations;
                                    'Subnet Route Table'                           = if ((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.routeTable.id' -Enumerate)) { (Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.routeTable.id' -Enumerate) -Index 8) };
                                    'Subnet Network Security Group'                = $SubnetNSG;
                                    'Resource U'                                   = $ResUCount;
                                    'Tag Name'                                     = [string]$Tag.Name;
                                    'Tag Value'                                    = [string]$Tag.Value
                                }
                                $obj
                                if ($ResUCount -eq 1) { $ResUCount = 0 } 
                            }
                    }
            }
            $tmp
        }
}

Else {
    if ($SmaResources) {

        $TableName = ('VNETTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))

        $SheetName = 'Virtual Networks'

        $condtxt = @()
        #Enable DDOS Protection
        $condtxt += New-ConditionalText FALSE -Range F:F
        #Retirement
        $condtxt += New-ConditionalText -Range G2:G100 -ConditionalType ContainsText
        #NSG
        $condtxt += New-ConditionalText None -Range S:S

        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Address Space')
        $Exc.Add('Enable DDOS Protection')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('DNS Servers')
        $Exc.Add('Subnet Name')
        $Exc.Add('Private Subnet')
        $Exc.Add('Subnet Prefix')
        $Exc.Add('Consumed IPs')
        $Exc.Add('Available IPs')
        $Exc.Add('Subnet Private Link Service Network Policies')
        $Exc.Add('Subnet Private Endpoint Network Policies')
        $Exc.Add('Subnet Delegations')
        $Exc.Add('Subnet Route Table')
        $Exc.Add('Subnet Network Security Group')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        $noNumberConversion = @()
        $noNumberConversion += 'DNS Servers'
        $noNumberConversion += 'Address Space'
        $noNumberConversion += 'Subnet Prefix'

        [PSCustomObject]$SmaResources | 
            ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName $SheetName -AutoSize -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style -NoNumberConversion $noNumberConversion

    }
}