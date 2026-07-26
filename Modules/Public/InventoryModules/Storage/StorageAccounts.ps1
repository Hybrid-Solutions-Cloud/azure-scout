<#
.Synopsis
Inventory for Azure Storage Account

.DESCRIPTION
This script consolidates information for all microsoft.storage/storageaccounts and  resource provider in $Resources variable.
Excel Sheet Name: StorageAcc

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Storage/StorageAccounts.ps1

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
    <######### Insert the resource extraction here ########>

    $storageacc = $Resources | Where-Object { $_.TYPE -eq 'microsoft.storage/storageaccounts' }

    <######### Insert the resource Process here ########>

    if($storageacc)
        {
            $tmp = foreach ($1 in $storageacc) {
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
                # The creationTime field is absent (not present-and-null) on older API versions and some
                # resource kinds, so the raw read throws under StrictMode -- and [datetime] of a null
                # produced a bogus 0001-01-01 before that (AB#5671).
                $timecreated = Get-AZSCSafeProperty -InputObject $data -Path 'creationTime'
                $timecreated = if ($timecreated) { ([datetime]$timecreated).ToString("yyyy-MM-dd HH:mm") } else { '' }
                $TLSv = if ((Get-AZSCSafeProperty -InputObject $data -Path 'minimumTlsVersion' -Enumerate) -eq 'TLS1_2') { "TLS 1.2" }elseif ((Get-AZSCSafeProperty -InputObject $data -Path 'minimumTlsVersion' -Enumerate) -eq 'TLS1_1') { "TLS 1.1" }else { "TLS 1.0" }
                # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                # than carrying an empty object, so the raw read throws under StrictMode -- and so
                # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }
                $VNETRules = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.virtualnetworkrules' -Enumerate))){(Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.virtualnetworkrules' -Enumerate)}else{' '}
                $BlobAccess = if ((Get-AZSCSafeProperty -InputObject $data -Path 'allowBlobPublicAccess' -Enumerate) -eq $false){$false}else{$true}
                $KeyAccess = if((Get-AZSCSafeProperty -InputObject $data -Path 'allowsharedkeyaccess' -Enumerate) -eq $true){$true}else{$false}
                $SFTPEnabled = if((Get-AZSCSafeProperty -InputObject $data -Path 'isSftpEnabled' -Enumerate) -eq $true){$true}else{$false}
                $HNSEnabled = if((Get-AZSCSafeProperty -InputObject $data -Path 'ishnsenabled' -Enumerate) -eq $true){$true}else{$false}
                $NFSv3 = if((Get-AZSCSafeProperty -InputObject $data -Path 'isnfsv3enabled' -Enumerate) -eq $true){$true}else{$false}
                $LargeFileShare = if((Get-AZSCSafeProperty -InputObject $data -Path 'largeFileSharesState' -Enumerate) -eq $true){$true}else{$false}
                $CrossTNT = if((Get-AZSCSafeProperty -InputObject $data -Path 'allowCrossTenantReplication' -Enumerate) -eq $true){$true}else{$false}
                $InfrastructureEncryption = if((Get-AZSCSafeProperty -InputObject $data -Path 'encryption.requireInfrastructureEncryption' -Enumerate) -eq "True"){$true}else{$false}

                

                if ((Get-AZSCSafeProperty -InputObject $data -Path 'azureFilesIdentityBasedAuthentication.directoryServiceOptions' -Enumerate) -eq 'None')
                    {
                        $EntraID = $false
                    }
                elseif ([string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'azureFilesIdentityBasedAuthentication.directoryServiceOptions' -Enumerate)))
                    {
                        $EntraID = $false
                    }
                else
                    {
                        $EntraID = $true
                    }

                # This if/elseif chain has NO else, so an account that matches none of the three cases
                # (no networkAcls block and no publicNetworkAccess field -- both are optional) left
                # $PubNetAccess unset. Under StrictMode the later read is then an error; without
                # StrictMode it was worse but silent, because the variable survives from one loop
                # iteration to the next, so such an account reported the PREVIOUS account's value.
                # Resetting per account is the same fix VirtualMachine.ps1 already applies to its
                # capability variables (AB#5671).
                $PubNetAccess = $null
                if ((Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.defaultaction' -Enumerate) -eq 'allow')
                    {
                        $PubNetAccess = 'Enabled from all networks'
                    }
                elseif ((Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.defaultaction' -Enumerate) -eq 'Deny' -and (Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccess' -Enumerate) -eq 'Enabled')
                    {
                        $PubNetAccess = 'Enabled from selected virtual networks and IP addresses'
                    }
                elseif ((Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccess' -Enumerate) -eq 'Disabled')
                    {
                        $PubNetAccess = 'Disabled'
                    }

                $PVTEndpoints = @()
                foreach ($pvt in (Get-AZSCSafeProperty -InputObject $data -Path 'privateEndpointConnections.properties.privateendpoint' -Enumerate))
                    {
                        $PVTEndpoints += if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $pvt -Path 'id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $pvt -Path 'id' -Enumerate) -Index 8)}else{$null}
                    }
                $DirectResources = @()
                foreach ($DiRes in (Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.resourceaccessrules' -Enumerate))
                    {
                        $DirectResources += if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $DiRes -Path 'resourceid' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $DiRes -Path 'resourceid' -Enumerate) -Index 8)}else{$null}
                    }

                $FinalDirectResources = if ($DirectResources.count -gt 1) { $DirectResources | ForEach-Object { $_ + ' ,' } }else { $DirectResources }
                $FinalDirectResources = [string]$FinalDirectResources
                $FinalDirectResources = if ($FinalDirectResources -like '* ,*') { $FinalDirectResources -replace ".$" }else { $FinalDirectResources }

                $FinalPVTEndpoint = if ($PVTEndpoints.count -gt 1) { $PVTEndpoints | ForEach-Object { $_ + ' ,' } }else { $PVTEndpoints }
                $FinalPVTEndpoint = [string]$FinalPVTEndpoint
                $FinalPVTEndpoint = if ($FinalPVTEndpoint -like '* ,*') { $FinalPVTEndpoint -replace ".$" }else { $FinalPVTEndpoint }

                $FinalACLIPs = if (@((Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.iprules.value' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.iprules.value' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.iprules.value' -Enumerate) }
                $FinalACLIPs = [string]$FinalACLIPs
                $FinalACLIPs = if ($FinalACLIPs -like '* ,*') { $FinalACLIPs -replace ".$" }else { $FinalACLIPs }

                $blobProperties = Get-AzStorageBlobServiceProperty -ResourceGroupName $1.RESOURCEGROUP -Name $1.NAME
                $fileProperties = Get-AzStorageFileServiceProperty -ResourceGroupName $1.RESOURCEGROUP -Name $1.NAME

                foreach ($2 in $VNETRules)
                    {
                        $VNET = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $2 -Path 'id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $2 -Path 'id' -Enumerate) -Index 8)}else{''}
                        $Subnet = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $2 -Path 'id' -Enumerate))){(Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $2 -Path 'id' -Enumerate) -Index 10)}else{''}
                        foreach ($Tag in $Tags) {
                            $obj = @{
                                'ID'                                    = $1.id;
                                'Subscription'                          = $SubscriptionName;
                                'Resource Group'                        = $1.RESOURCEGROUP;
                                'Name'                                  = $1.NAME;
                                'Location'                              = $1.LOCATION;
                                'Retiring Feature'                      = $RetiringFeature;
                                'Retiring Date'                         = $RetiringDate;
                                'Zone'                                  = $1.ZONES;
                                'SKU'                                   = (Get-AZSCSafeProperty -InputObject $1 -Path 'sku.name' -Enumerate);
                                'Tier'                                  = (Get-AZSCSafeProperty -InputObject $1 -Path 'sku.tier' -Enumerate);
                                'Storage Account Kind'                  = $1.kind;
                                'Secure Transfer Required'              = (Get-AZSCSafeProperty -InputObject $data -Path 'supportsHttpsTrafficOnly' -Enumerate);
                                'Allow Blob Anonymous Access'           = $BlobAccess;
                                'Minimum TLS Version'                   = $TLSv;
                                'Microsoft Entra Authorization'         = $EntraID;
                                'Allow Storage Account Key Access'      = $KeyAccess;
                                'SFTP Enabled'                          = $SFTPEnabled;
                                # Get-AzStorageBlobServiceProperty / ...FileServiceProperty are called
                                # WITHOUT -ErrorAction above, so on any account the caller cannot read
                                # (RBAC, a deleted account, a data-plane firewall) they emit a
                                # non-terminating error and leave these variables $null -- and a
                                # property read on $null throws under StrictMode just as an absent
                                # member does (AB#5671). The 'N/A' fall-back already covers that case;
                                # it just never got the chance to run.
                                'Blob Soft Delete Days'                 = if (Get-AZSCSafeProperty -InputObject $blobProperties -Path 'DeleteRetentionPolicy.Enabled') { Get-AZSCSafeProperty -InputObject $blobProperties -Path 'DeleteRetentionPolicy.Days' } else { 'N/A' };
                                'Container Soft Delete Days'            = if (Get-AZSCSafeProperty -InputObject $blobProperties -Path 'containerDeleteRetentionPolicy.Enabled') { Get-AZSCSafeProperty -InputObject $blobProperties -Path 'containerDeleteRetentionPolicy.Days' } else { 'N/A' };
                                'File Share Soft Delete Days'           = if (Get-AZSCSafeProperty -InputObject $fileProperties -Path 'ShareDeleteRetentionPolicy.Enabled') { Get-AZSCSafeProperty -InputObject $fileProperties -Path 'ShareDeleteRetentionPolicy.Days' } else { 'N/A' };
                                'Hierarchical Namespace'                = $HNSEnabled;
                                'NFSv3 Enabled'                         = $NFSv3;
                                'Large File Shares'                     = $LargeFileShare;
                                'Access Tier'                           = (Get-AZSCSafeProperty -InputObject $data -Path 'accessTier' -Enumerate);
                                'Allow Cross Tenant Replication'        = $CrossTNT;
                                'Infrastructure Encryption Enabled'     = $InfrastructureEncryption;
                                'Public Network Access'                 = $PubNetAccess;
                                'Private Endpoints'                     = $FinalPVTEndpoint;
                                'Direct Access Resources'               = $FinalDirectResources;
                                'Virtual Networks'                      = $VNET;
                                'Subnet'                                = $Subnet;
                                'Direct Access IPs'                     = $FinalACLIPs;
                                'Firewall Exceptions'                   = [string](Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.bypass' -Enumerate);
                                'Primary Location'                      = (Get-AZSCSafeProperty -InputObject $data -Path 'primaryLocation' -Enumerate);
                                'Status Of Primary Location'            = (Get-AZSCSafeProperty -InputObject $data -Path 'statusOfPrimary' -Enumerate);
                                'Secondary Location'                    = (Get-AZSCSafeProperty -InputObject $data -Path 'secondaryLocation' -Enumerate);
                                'Status Of Secondary Location'          = (Get-AZSCSafeProperty -InputObject $data -Path 'statusofsecondary' -Enumerate);
                                'Created Time'                          = $timecreated;
                                'Resource U'                            = $ResUCount;
                                'Tag Name'                              = [string]$Tag.Name;
                                'Tag Value'                             = [string]$Tag.Value
                            }
                            $obj
                            if ($ResUCount -eq 1) { $ResUCount = 0 }
                        }
                    }
            }
            $tmp
        }
}

<######## Resource Excel Reporting Begins Here ########>

Else {
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if ($SmaResources) {

        $SheetName = 'Storage Accounts'

        $TableName = ('StorAccTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = @(
        New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'
        New-ExcelStyle -HorizontalAlignment Center -Width 80 -WrapText -NumberFormat '0' -Range "X:X"
        New-ExcelStyle -HorizontalAlignment Center -Width 140 -WrapText -NumberFormat '0' -Range "AA:AA"
        )

        $condtxt = @()
        $condtxt += New-ConditionalText false -Range K:K                                #Secure Transfer Required
        $condtxt += New-ConditionalText true -Range L:L                                 #Allow Blob Anonymous Access
        $condtxt += New-ConditionalText 1.0 -Range M:M                                  #Minimum TLS Version
        $condtxt += New-ConditionalText 1.1 -Range M:M                                  #Minimum TLS Version
        $condtxt += New-ConditionalText true -Range O:O                                 #Allow Storage Account Key Access
        $condtxt += New-ConditionalText all -Range Z:Z                                  #Public Network Access  
        $condtxt += New-ConditionalText . -Range AF:AF -ConditionalType ContainsText    #Firewall Exceptions
        $condtxt += New-ConditionalText unavailable -Range AH:AH                        #Status Of Primary Location
        $condtxt += New-ConditionalText unavailable -Range AI:AI                        #Status Of Secondary Location
        $condtxt += New-ConditionalText -Range I2:I100 -ConditionalType ContainsText    #Retiring Feature

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Zone')
        $Exc.Add('SKU')
        $Exc.Add('Tier')
        $Exc.Add('Storage Account Kind')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Secure Transfer Required')
        $Exc.Add('Allow Blob Anonymous Access')
        $Exc.Add('Minimum TLS Version')
        $Exc.Add('Microsoft Entra Authorization')
        $Exc.Add('Allow Storage Account Key Access')
        $Exc.Add('SFTP Enabled')
        $Exc.Add('Blob Soft Delete Days')
        $Exc.Add('Container Soft Delete Days')
        $Exc.Add('File Share Soft Delete Days')
        $Exc.Add('Hierarchical Namespace')
        $Exc.Add('NFSv3 Enabled')
        $Exc.Add('Large File Shares')
        $Exc.Add('Access Tier')
        $Exc.Add('Allow Cross Tenant Replication')
        $Exc.Add('Infrastructure Encryption Enabled')
        $Exc.Add('Public Network Access')
        $Exc.Add('Private Endpoints')
        $Exc.Add('Direct Access Resources')
        $Exc.Add('Virtual Networks')
        $Exc.Add('Subnet')
        $Exc.Add('Direct Access IPs')
        $Exc.Add('Firewall Exceptions')
        $Exc.Add('Primary Location')
        $Exc.Add('Status Of Primary Location')
        $Exc.Add('Secondary Location')
        $Exc.Add('Status Of Secondary Location')
        $Exc.Add('Created Time')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value')
            }
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName $SheetName -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style

    }
}
