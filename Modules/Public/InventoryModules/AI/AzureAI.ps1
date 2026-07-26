<#
.Synopsis
Inventory for Azure AI

.DESCRIPTION
This script consolidates information for all microsoft.cognitiveservices/accounts and  resource provider in $Resources variable. 
Excel Sheet Name: Azure AI

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/AI/AzureAI.ps1

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC).

.CATEGORY AI

.NOTES
Version: 3.6.0
First Release Date: 19th November, 2020
Authors: Claudio Merola

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{

    <######### Insert the resource extraction here ########>

    $AzureAI = $Resources | Where-Object {$_.TYPE -eq 'microsoft.cognitiveservices/accounts' -and $_.Kind -eq 'AIServices'}

    <######### Insert the resource Process here ########>

    if($AzureAI)
        {
            $tmp = foreach ($1 in $AzureAI) {
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
                # The datecreated field is absent (not present-and-null) on older API versions and some
                # resource kinds, so the raw read throws under StrictMode -- and [datetime] of a null
                # produced a bogus 0001-01-01 before that (AB#5671).
                $timecreated = Get-AZSCSafeProperty -InputObject $data -Path 'datecreated'
                $timecreated = if ($timecreated) { ([datetime]$timecreated).ToString("yyyy-MM-dd HH:mm") } else { '' }
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
                $pvt = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'privateendpointconnections' -Enumerate))){(Get-AZSCSafeProperty -InputObject $data -Path 'privateendpointconnections' -Enumerate)}else{'0'}
                # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                # than carrying an empty object, so the raw read throws under StrictMode -- and so
                # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }
                    foreach ($pv in $pvt)
                        {
                            # $pvt falls back to the string '0' when the account has no private
                            # endpoints (the common case), and '0' splits to a ONE-element array --
                            # so the fixed [8] index was out of range. Silently $null before, a
                            # thrown "Index was outside the bounds of the array" now (AB#5671).
                            $priv = Get-AZSCIdSegment -Id $pv -Index 8
                            foreach ($Tag in $Tags) {
                                $obj = @{
                                    'ID'                                        = $1.id;
                                    'Subscription'                              = $SubscriptionName;
                                    'Resource Group'                            = $1.RESOURCEGROUP;
                                    'Name'                                      = $1.NAME;
                                    'SKU'                                       = (Get-AZSCSafeProperty -InputObject $1 -Path 'sku.name' -Enumerate);
                                    'Retiring Feature'                          = $RetiringFeature;
                                    'Retiring Date'                             = $RetiringDate;
                                    'Public Network Access'                     = (Get-AZSCSafeProperty -InputObject $data -Path 'publicnetworkaccess' -Enumerate);
                                    'Creation Time'                             = $timecreated;
                                    'Is Migrated'                               = (Get-AZSCSafeProperty -InputObject $data -Path 'ismigrated' -Enumerate);
                                    'Custom Domain Name'                        = (Get-AZSCSafeProperty -InputObject $data -Path 'customsubdomainname' -Enumerate);
                                    'Endpoint'                                  = (Get-AZSCSafeProperty -InputObject $data -Path 'endpoint' -Enumerate);
                                    'Network Default Action'                    = (Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.defaultaction' -Enumerate);
                                    'IP Rules'                                  = @((Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.iprules' -Enumerate)).count;
                                    'Virtual Network Rules'                     = @((Get-AZSCSafeProperty -InputObject $data -Path 'networkacls.virtualnetworkrules' -Enumerate)).count;
                                    'Private Endpoint'                          = $priv;
                                    'Resource U'                                = $ResUCount;
                                    'Tag Name'                                  = [string]$Tag.Name;
                                    'Tag Value'                                 = [string]$Tag.Value
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

        $TableName = ('AzureAITable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $condtxt = @()
        $condtxt += New-ConditionalText F0 -Range D:D
        $condtxt += New-ConditionalText enabled -Range G:G
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('SKU')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Public Network Access')
        $Exc.Add('Creation Time')
        $Exc.Add('Is Migrated')
        $Exc.Add('Custom Domain Name')
        $Exc.Add('Endpoint')
        $Exc.Add('Network Default Action')
        $Exc.Add('IP Rules')
        $Exc.Add('Virtual Network Rules')
        $Exc.Add('Private Endpoint')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

            [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'Azure AI' -AutoSize -MaxAutoSizeRows 100 -ConditionalText $condtxt -TableName $TableName -TableStyle $tableStyle -Style $Style

    }
}