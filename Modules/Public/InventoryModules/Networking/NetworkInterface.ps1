<#
.Synopsis
Inventory for Azure Network Interfaces

.DESCRIPTION
This script consolidates information for all microsoft.network/natgateways and  resource provider in $Resources variable. 
Excel Sheet Name: Network Interface

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Network_2/NetworkInterface.ps1

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

    $nic = $Resources | Where-Object {$_.TYPE -eq 'microsoft.network/networkinterfaces'}
    $PublicIP = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/publicipaddresses' }

    if($nic)
        {
            $tmp = foreach ($1 in $nic) 
                {
                    $ResUCount = 1
                    # An EMPTY $sub1 is not $null -- the match is empty for any resource whose subscription
                    # is outside the requested scope -- and reading .Name off an empty collection throws
                    # under StrictMode (AB#5671). Resolved once here, as VirtualMachine.ps1 already does.
                    $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
                    $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { '' }
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

                    if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'virtualmachine.id' -Enumerate)))
                        {
                            $ResourceType = 'Virtual Machine'
                            $Resource = (Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'virtualmachine.id' -Enumerate) -Index 8)
                        }
                    elseif(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'privateendpoint.id' -Enumerate)))
                        {
                            $ResourceType = 'Private Endpoint'
                            $Resource = (Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'privateendpoint.id' -Enumerate) -Index 8)
                        }
                    else
                        {
                            $ResourceType = 'Underutilized'
                            $Resource = 'None'
                        }
                    
                    $NSG = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'networksecuritygroup.id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'networksecuritygroup.id' -Enumerate) -Index 8)}else{$null}

                    $DNS = if (@((Get-AZSCSafeProperty -InputObject $data -Path 'dnssettings.dnsservers' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $data -Path 'dnssettings.dnsservers' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $data -Path 'dnssettings.dnsservers' -Enumerate) }
                    $DNS = [string]$DNS
                    $DNS = if ($DNS -like '* ,*') { $DNS -replace ".$" }else { $DNS }

                    $AcceleratedNetworking = if((Get-AZSCSafeProperty -InputObject $data -Path 'enableacceleratednetworking' -Enumerate) -eq $true){'On'}else{'Off'}

                    # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                    # than carrying an empty object, so the raw read throws under StrictMode -- and so
                    # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                    # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                    # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                    $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                    $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                    $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }
                    foreach ($2 in (Get-AZSCSafeProperty -InputObject $data -Path 'ipconfigurations' -Enumerate))
                        {
                            $VNET = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.subnet.id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.subnet.id' -Enumerate) -Index 8)}else{$null}
                            $Subnet = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $2 -Path 'properties.subnet.id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.subnet.id' -Enumerate) -Index 10)}else{$null}
                            $PIP = $PublicIP | Where-Object {$_.id -eq (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.publicipaddress.id' -Enumerate)}
                            $PIPName = (Get-AZSCSafeProperty -InputObject $PIP -Path 'Name' -Enumerate)
                            $PIPAddress = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $PIP -Path 'properties.ipaddress' -Enumerate))){(Get-AZSCSafeProperty -InputObject $PIP -Path 'properties.ipaddress' -Enumerate)}else{'Unassigned'}
                            foreach ($Tag in $Tags) 
                                {
                                    $obj = @{
                                        'ID'                    = $1.id;
                                        'Subscription'          = $SubscriptionName;
                                        'Resource Group'        = $1.RESOURCEGROUP;
                                        'Name'                  = $1.NAME;
                                        'Location'              = $1.LOCATION;
                                        'Retiring Feature'      = $RetiringFeature;
                                        'Retiring Date'         = $RetiringDate;
                                        'Attached Resource Type'= $ResourceType;
                                        'Attached Resource'     = $Resource;
                                        'Network Security Group'= $NSG;
                                        'DNS Servers'           = $DNS;
                                        'Internal Domain Suffix'= (Get-AZSCSafeProperty -InputObject $data -Path 'dnssettings.internaldomainnamesuffix' -Enumerate);
                                        'Accelerated Networking'= $AcceleratedNetworking;
                                        'IP Forwarding'         = (Get-AZSCSafeProperty -InputObject $data -Path 'enableipforwarding' -Enumerate);
                                        'MAC Address'           = (Get-AZSCSafeProperty -InputObject $data -Path 'macaddress' -Enumerate);
                                        'IP Configurations'     = (Get-AZSCSafeProperty -InputObject $2 -Path 'name' -Enumerate);
                                        'Virtual Network'       = $VNET;
                                        'Subnet'                = $Subnet;
                                        'Primary'               = (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.primary' -Enumerate);
                                        'Private IP Version'    = (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.privateipaddressversion' -Enumerate);
                                        'Private IP'            = (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.privateipaddress' -Enumerate);
                                        'Private IP Method'     = (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.privateipallocationmethod' -Enumerate);
                                        'Public IP Name'        = $PIPName;
                                        'Public IP'             = $PIPAddress;
                                        'Resource U'            = $ResUCount;
                                        'Tag Name'              = [string]$Tag.Name;
                                        'Tag Value'             = [string]$Tag.Value
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

        $TableName = ('NICTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = @()
        $Style += New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat 0

        $condtxt = @()
        $condtxt += New-ConditionalText Off -Range L:L
        $condtxt += New-ConditionalText Underutilized -Range G:G
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Attached Resource Type')
        $Exc.Add('Attached Resource')
        $Exc.Add('Network Security Group')
        $Exc.Add('DNS Servers')
        $Exc.Add('Internal Domain Suffix')
        $Exc.Add('Accelerated Networking')
        $Exc.Add('IP Forwarding')
        $Exc.Add('MAC Address')
        $Exc.Add('IP Configurations')
        $Exc.Add('Virtual Network')
        $Exc.Add('Subnet')
        $Exc.Add('Primary')
        $Exc.Add('Private IP Version')
        $Exc.Add('Private IP')
        $Exc.Add('Private IP Method')
        $Exc.Add('Public IP Name')
        $Exc.Add('Public IP')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        $noNumberConversion = @()
        $noNumberConversion += 'DNS Servers'
        $noNumberConversion += 'Private IP'
        $noNumberConversion += 'Public IP'

        [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'Network Interface' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style -NoNumberConversion $noNumberConversion

    }
}