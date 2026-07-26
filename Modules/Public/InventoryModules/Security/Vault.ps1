<#
.Synopsis
Inventory for Azure Key Vault

.DESCRIPTION
This script consolidates information for all microsoft.keyvault/vaults and  resource provider in $Resources variable. 
Excel Sheet Name: Vault

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Security/Vault.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 19th November, 2020
Authors: Claudio Merola and Renato Gregio 

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task ,$File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{
    <######### Insert the resource extraction here ########>

        $VAULT = $Resources | Where-Object {$_.TYPE -eq 'microsoft.keyvault/vaults'}

    <######### Insert the resource Process here ########>

    if($VAULT)
        {
            $tmp = foreach ($1 in $VAULT) {
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
                # `enableSoftDelete` and `enableRbacAuthorization` are both absent (not null) on an
                # older vault that has never had either set. Both arms are read through the accessor,
                # not just the guard: the else arm only runs when the property exists, so it happens
                # not to throw today, but leaving one raw read behind means the next person has to
                # work out which of the two spellings was deliberate (AB#5671).
                $EnableSoftDelete = Get-AZSCSafeProperty -InputObject $data -Path 'enableSoftDelete'
                $EnableRbac       = Get-AZSCSafeProperty -InputObject $data -Path 'enableRbacAuthorization'
                if([string]::IsNullOrEmpty($EnableSoftDelete)){$Soft = $false}else{$Soft = $EnableSoftDelete}
                if([string]::IsNullOrEmpty($EnableRbac)){$RBAC = $false}else{$RBAC = $EnableRbac}
                # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                # than carrying an empty object, so the raw read throws under StrictMode -- and so
                # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }
                $AccessPol = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'accessPolicies' -Enumerate))){(Get-AZSCSafeProperty -InputObject $data -Path 'accessPolicies' -Enumerate)}else{'0'}
                Foreach($2 in $AccessPol)
                    {
                        $Secrets = if (@((Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.secrets' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.secrets' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.secrets' -Enumerate) }
                        $Secrets = [string]$Secrets
                        $Secrets = if ($Secrets -like '* ,*') { $Secrets -replace ".$" }else { $Secrets }

                        $Keys = if (@((Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.keys' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.keys' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.keys' -Enumerate) }
                        $Keys = [string]$Keys
                        $Keys = if ($Keys -like '* ,*') { $Keys -replace ".$" }else { $Keys }

                        $Certs = if (@((Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.certificates' -Enumerate)).count -gt 1) { (Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.certificates' -Enumerate) | ForEach-Object { $_ + ' ,' } }else { (Get-AZSCSafeProperty -InputObject $2 -Path 'permissions.certificates' -Enumerate) }
                        $Certs = [string]$Certs
                        $Certs = if ($Certs -like '* ,*') { $Certs -replace ".$" }else { $Certs }

                        foreach ($Tag in $Tags) {
                                $obj = @{
                                    'ID'                         = $1.id;
                                    'Subscription'               = $SubscriptionName;
                                    'Resource Group'             = $1.RESOURCEGROUP;
                                    'Name'                       = $1.NAME;
                                    'Location'                   = $1.LOCATION;
                                    'Retiring Feature'           = $RetiringFeature;
                                    'Retiring Date'              = $RetiringDate;
                                    'SKU Family'                 = (Get-AZSCSafeProperty -InputObject $data -Path 'sku.family' -Enumerate);
                                    'SKU'                        = (Get-AZSCSafeProperty -InputObject $data -Path 'sku.name' -Enumerate);
                                    'Vault Uri'                  = (Get-AZSCSafeProperty -InputObject $data -Path 'vaultUri' -Enumerate);
                                    'Public Network Access'      = (Get-AZSCSafeProperty -InputObject $data -Path 'publicnetworkaccess' -Enumerate);
                                    'Enable RBAC'                = $RBAC;
                                    'Enable Soft Delete'         = $Soft;
                                    'Enable for Disk Encryption' = (Get-AZSCSafeProperty -InputObject $data -Path 'enabledForDiskEncryption' -Enumerate);
                                    'Soft Delete Retention Days' = (Get-AZSCSafeProperty -InputObject $data -Path 'softDeleteRetentionInDays' -Enumerate);
                                    'Access Policy ObjectID'     = (Get-AZSCSafeProperty -InputObject $2 -Path 'objectid' -Enumerate);
                                    'Certificate Permissions'    = $Certs;
                                    'Key Permissions'            = $Keys;
                                    'Secret Permissions'         = $Secrets;
                                    'Resource U'                 = $ResUCount;
                                    'Tag Name'                   = [string]$Tag.Name;
                                    'Tag Value'                  = [string]$Tag.Value
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

Else
{
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if($SmaResources)
    {

        $TableName = ('VaultTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $condtxt = @()
        $condtxt += New-ConditionalText false -Range L:L
        $condtxt += New-ConditionalText enabled -Range J:J
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('SKU Family')
        $Exc.Add('SKU')
        $Exc.Add('Vault Uri')
        $Exc.Add('Public Network Access')
        $Exc.Add('Enable RBAC')
        $Exc.Add('Enable Soft Delete')
        $Exc.Add('Enable for Disk Encryption')
        $Exc.Add('Soft Delete Retention Days')
        $Exc.Add('Access Policy ObjectID')
        $Exc.Add('Certificate Permissions')
        $Exc.Add('Key Permissions')
        $Exc.Add('Secret Permissions')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'Key Vaults' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style

    }
}