<#
.Synopsis
Inventory for Azure Private Endpoint

.DESCRIPTION
This script consolidates information for all microsoft.network/privateendpoints and resource provider in $Resources variable. 
Excel Sheet Name: Private Endpoints

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Network_2/PrivateEndpoint.ps1

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

    $PrivateEdp = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/privateendpoints' }
    $NICs = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/networkinterfaces' }

    if($PrivateEdp)
        {
            $tmp = foreach ($1 in $PrivateEdp) {
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
                $Retired = $Retirements | Where-Object { $_.id -eq $1.id }
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

                $VNET = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'subnet.id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'subnet.id' -Enumerate) -Index 8)}else{''}
                $Subnet = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'subnet.id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'subnet.id' -Enumerate) -Index 10)}else{''}

                if([string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'customDnsConfigs.ipAddresses' -Enumerate)))
                    {
                        $NIC = $NICs | Where-Object {$_.id -eq (Get-AZSCSafeProperty -InputObject $data -Path 'networkInterfaces.id' -Enumerate)}
                        $IPAddress = if (@($NIC.properties.ipconfigurations.properties.privateipaddress).count -gt 1) { $NIC.properties.ipconfigurations.properties.privateipaddress | ForEach-Object { $_ + ' ,' } }else { $NIC.properties.ipconfigurations.properties.privateipaddress }
                        $IPAddress = [string]$IPAddress
                        $IPAddress = if ($IPAddress -like '* ,*') { $IPAddress -replace ".$" }else { $IPAddress }

                        $FQDN = if (@($NIC.properties.ipconfigurations.properties.privatelinkconnectionproperties.fqdns).count -gt 1) { $NIC.properties.ipconfigurations.properties.privatelinkconnectionproperties.fqdns | ForEach-Object { $_ + ' ,' } }else { $NIC.properties.ipconfigurations.properties.privatelinkconnectionproperties.fqdns }
                        $FQDN = [string]$FQDN
                        $FQDN = if ($FQDN -like '* ,*') { $FQDN -replace ".$" }else { $FQDN }
                    }
                else
                    {
                        $IPAddress = if (@((Get-AZSCSafeProperty -InputObject $data -Path 'customDnsConfigs.ipAddresses' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $data -Path 'customDnsConfigs.ipAddresses' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $data -Path 'customDnsConfigs.ipAddresses' -Enumerate) }
                        $IPAddress = [string]$IPAddress
                        $IPAddress = if ($IPAddress -like '* ,*') { $IPAddress -replace ".$" }else { $IPAddress }

                        $FQDN = if (@((Get-AZSCSafeProperty -InputObject $data -Path 'customDnsConfigs.fqdn' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $data -Path 'customDnsConfigs.fqdn' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $data -Path 'customDnsConfigs.fqdn' -Enumerate) }
                        $FQDN = [string]$FQDN
                        $FQDN = if ($FQDN -like '* ,*') { $FQDN -replace ".$" }else { $FQDN }
                    }
                
                foreach ($Tag in $Tags) {     
                    $obj = @{
                        'ID'                              = $1.id;
                        'Subscription'                    = $SubscriptionName;
                        'Resource Group'                  = $1.RESOURCEGROUP;
                        'Name'                            = $1.NAME;
                        'Location'                        = $1.LOCATION;
                        'Retiring Feature'                = $RetiringFeature;
                        'Retiring Date'                   = $RetiringDate;
                        'VNET'                            = $VNET;
                        'Subnet'                          = $Subnet;
                        'Private Link Name'               = (Get-AZSCSafeProperty -InputObject $data -Path 'privateLinkServiceConnections.name' -Enumerate);
                        'Private Link Status'             = (Get-AZSCSafeProperty -InputObject $data -Path 'privatelinkserviceconnections.properties.privateLinkServiceConnectionState.status' -Enumerate);
                        'Private Link Resource Type'      = [string](Get-AZSCSafeProperty -InputObject $data -Path 'privatelinkserviceconnections.properties.groupids' -Enumerate);
                        'Private Link Target Resource'    = [string](Get-AZSCSafeProperty -InputObject $data -Path 'privatelinkserviceconnections.properties.privatelinkserviceid' -Enumerate);
                        'IP Address'                      = $IPAddress;
                        'FQDN'                            = $FQDN;
                        'Resource U'                        = $ResUCount;
                        'Tag Name'                        = [string]$Tag.Name;
                        'Tag Value'                       = [string]$Tag.Value;
                    }
                    $obj
                    if ($ResUCount -eq 1) { $ResUCount = 0 } 
                }            
            }
            $tmp
        }
}
Else {
    if ($SmaResources) {

        $TableName = ('PvtEndpointTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = @()
        $Style += New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat 0

        $condtxt = @()
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('VNET')
        $Exc.Add('Subnet')
        $Exc.Add('Private Link Name')
        $Exc.Add('IP Address')
        $Exc.Add('FQDN')
        $Exc.Add('Private Link Status')
        $Exc.Add('Private Link Resource Type')
        $Exc.Add('Private Link Target Resource')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')


        [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'Private Endpoint' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -ConditionalText $condtxt -TableStyle $tableStyle -Style $Style

    }   
}