<#
.Synopsis
Inventory for Azure Database for Postgre SQL Flexible Server

.DESCRIPTION
This script consolidates information for all Microsoft.DBforPostgreSQL/flexibleServers resource provider in $Resources variable. 
Excel Sheet Name: POSTGRE Flexible

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Database/POSTGREFlexible.ps1

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

    $POSTGRE = $Resources | Where-Object { $_.TYPE -eq 'Microsoft.DBforPostgreSQL/flexibleServers' }

    if($POSTGRE)
        {
            $tmp = foreach ($1 in $POSTGRE) {
                $ResUCount = 1
                # An EMPTY $sub1 is not $null -- the match is empty for any resource whose subscription
                # is outside the requested scope -- and reading .Name off an empty collection throws
                # under StrictMode (AB#5671). Resolved once here, as VirtualMachine.ps1 already does.
                $sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
                # The else arm is $null, NOT '': with StrictMode off $sub1.Name on an unmatched ($null)
                # $sub1 evaluated to $null, and the ~110 collectors that still read $sub1.Name directly
                # emit $null here. '' was a silent behaviour change -- the declarative equivalence proof
                # caught it on 11 collectors, and it would have been invisible on the rest (AB#5659).
                $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { $null }
                $data = $1.PROPERTIES
                $sku = $1.SKU
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
                $DelegatedVNET = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'network.delegatedsubnetresourceid' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'network.delegatedsubnetresourceid' -Enumerate) -Index 8)}else{$null}
                $DelegatedSubnet = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'network.delegatedsubnetresourceid' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'network.delegatedsubnetresourceid' -Enumerate) -Index 10)}else{$null}
                $PrivateDNSZone = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'network.privatednszonearmresourceid' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'network.privatednszonearmresourceid' -Enumerate) -Index 8)}else{$null}
                # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                # than carrying an empty object, so the raw read throws under StrictMode -- and so
                # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }
                    foreach ($Tag in $Tags) {
                        $obj = @{
                            'ID'                        = $1.id;
                            'Subscription'              = $SubscriptionName;
                            'Resource Group'            = $1.RESOURCEGROUP;
                            'Name'                      = $1.NAME;
                            'Location'                  = $1.LOCATION;
                            'Retiring Feature'          = $RetiringFeature;
                            'Retiring Date'             = $RetiringDate;
                            'FQDN'                      = (Get-AZSCSafeProperty -InputObject $data -Path 'fullyqualifieddomainname' -Enumerate);
                            'ADMIN Login'               = (Get-AZSCSafeProperty -InputObject $data -Path 'administratorLogin' -Enumerate);
                            'Version'                   = [string]((Get-AZSCSafeProperty -InputObject $data -Path 'version' -Enumerate)+'.'+(Get-AZSCSafeProperty -InputObject $data -Path 'minorversion' -Enumerate));
                            'AD Authentication'         = (Get-AZSCSafeProperty -InputObject $data -Path 'authconfig.activedirectoryauth' -Enumerate);
                            'Password Authentication'   = (Get-AZSCSafeProperty -InputObject $data -Path 'authconfig.passwordauth' -Enumerate);
                            'Computer Tier'             = (Get-AZSCSafeProperty -InputObject $sku -Path 'tier' -Enumerate);
                            'Computer Size'             = (Get-AZSCSafeProperty -InputObject $sku -Path 'name' -Enumerate);
                            'Storage Size (GB)'         = (Get-AZSCSafeProperty -InputObject $data -Path 'storage.storagesizegb' -Enumerate);
                            'Availability Zone'         = (Get-AZSCSafeProperty -InputObject $data -Path 'availabilityzone' -Enumerate);
                            'High Availability'         = (Get-AZSCSafeProperty -InputObject $data -Path 'highavailability.state' -Enumerate);
                            'Data Encryption'           = (Get-AZSCSafeProperty -InputObject $data -Path 'dataencryption.type' -Enumerate);
                            'Backup Retention (Days)'   = (Get-AZSCSafeProperty -InputObject $data -Path 'backup.backupretentiondays' -Enumerate);
                            'Geo-Redundant Backup'      = (Get-AZSCSafeProperty -InputObject $data -Path 'backup.geoRedundantBackup' -Enumerate);
                            'Replication Role'          = (Get-AZSCSafeProperty -InputObject $data -Path 'replicationRole' -Enumerate);
                            'Replication Capacity'      = (Get-AZSCSafeProperty -InputObject $data -Path 'replicaCapacity' -Enumerate);
                            'Public Network Access'     = (Get-AZSCSafeProperty -InputObject $data -Path 'network.publicnetworkaccess' -Enumerate);
                            'Delegated VNET'            = $DelegatedVNET;
                            'Delegated Subnet'          = $DelegatedSubnet;
                            'Private DNS Zone'          = $PrivateDNSZone;
                            'Resource U'                = $ResUCount;
                            'Tag Name'                  = [string]$Tag.Name;
                            'Tag Value'                 = [string]$Tag.Value
                        }
                        $obj
                        if ($ResUCount -eq 1) { $ResUCount = 0 } 
                    }                
            }
            $tmp
        }
}
<######## Resource Excel Reporting Begins Here ########>

Else {
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if ($SmaResources) {

        $TableName = ('POSTGFlex_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat 0

        $condtxt = @()
        $condtxt += New-ConditionalText enabled -Range V:V
        $condtxt += New-ConditionalText notenabled -Range P:P
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription') #A
        $Exc.Add('Resource Group') #B
        $Exc.Add('Name') #C
        $Exc.Add('Location') #D
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('FQDN') #G
        $Exc.Add('ADMIN Login') #H
        $Exc.Add('Version') #I
        $Exc.Add('AD Authentication') #J
        $Exc.Add('Password Authentication') #K
        $Exc.Add('Computer Tier') #L
        $Exc.Add('Computer Size') #M
        $Exc.Add('Storage Size (GB)') #N
        $Exc.Add('Availability Zone') #O
        $Exc.Add('High Availability') #P
        $Exc.Add('Data Encryption') #Q 
        $Exc.Add('Backup Retention (Days)') #R
        $Exc.Add('Geo-Redundant Backup') #S
        $Exc.Add('Replication Role') #T
        $Exc.Add('Replication Capacity') #U
        $Exc.Add('Public Network Access') #V
        $Exc.Add('Delegated VNET') #W
        $Exc.Add('Delegated Subnet') #X
        $Exc.Add('Private DNS Zone') #Y
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'PostgreSQL Flexible' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style

    }
}
