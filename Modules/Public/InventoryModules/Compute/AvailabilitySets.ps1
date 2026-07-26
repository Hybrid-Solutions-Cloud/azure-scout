<#
.Synopsis
Inventory for Azure Availability Set

.DESCRIPTION
This script consolidates information for all microsoft.compute/availabilitysets and  resource provider in $Resources variable. 
Excel Sheet Name: AvSet

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Compute/AvailabilitySets.ps1

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC).

.CATEGORY Compute

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

        $AvSet = $Resources | Where-Object {$_.TYPE -eq 'microsoft.compute/availabilitysets'}

    <######### Insert the resource Process here ########>

    if($AvSet)
        {
            $tmp = foreach ($1 in $AvSet) {
                $ResUCount = 1
                $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
                $data = $1.PROPERTIES
                # `virtualMachines` is an ARRAY, and it is absent (not empty) on an availability
                # set that has never had a VM placed in it -- both shapes make the raw
                # `$data.virtualMachines.id` chain throw under StrictMode (AB#5671). -Enumerate
                # reproduces the member enumeration the original relied on, so a set WITH members
                # still yields exactly the same id (or array of ids) as before.
                $AvSetVMIds = Get-AZSCSafeProperty -InputObject $data -Path 'virtualMachines.id' -Enumerate
                $Orphaned = if([string]::IsNullOrEmpty($AvSetVMIds)){$true}else{$false}
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
                # A Resource Graph row for an untagged resource OMITS `tags` rather than carrying
                # an empty object, so the raw `$1.tags` read throws under StrictMode (AB#5671).
                # `$null.psobject.properties` throws too, so the psobject read is guarded on the
                # value as well as on the key. The '0' fall-back is retained exactly: an untagged
                # resource still emits ONE row with empty Tag Name/Value, rather than none.
                $RowTags = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                # The historic '0' sentinel existed only to make the tag loop run once for an
                # untagged resource; `'0'.Name` throws under StrictMode, and an empty tag object
                # runs the loop once AND emits the identical [string]-cast empty Tag Name/Value.
                $Tags = if(![string]::IsNullOrEmpty($TagProps)){$TagProps}else{[pscustomobject]@{ Name = $null; Value = $null }}
                Foreach ($vmid in $AvSetVMIds) {
                    $vmIds = $vmid.split('/')[8]
                        foreach ($Tag in $Tags) {
                            $obj = @{
                                'ID'               = $1.id;
                                'Subscription'     = $sub1.Name;
                                'Resource Group'   = $1.RESOURCEGROUP;
                                'Name'             = $1.NAME;
                                'Location'         = $1.LOCATION;
                                'Retiring Feature' = $RetiringFeature;
                                'Retiring Date'    = $RetiringDate;
                                'Orphaned'         = $Orphaned;
                                'Fault Domains'    = [string]$data.platformFaultDomainCount;
                                'Update Domains'   = [string]$data.platformUpdateDomainCount;
                                'Virtual Machines' = [string]$vmIds;
                                'Resource U'       = $ResUCount;
                                'Tag Name'         = [string]$Tag.Name;
                                'Tag Value'        = [string]$Tag.Value
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

        $TableName = ('AvSetTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $condtxt = @()
        $condtxt += New-ConditionalText TRUE -Range G:G
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText
            
        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Orphaned')
        $Exc.Add('Fault Domains')
        $Exc.Add('Update Domains')
        $Exc.Add('Virtual Machines')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        $SmaResources | 
        ForEach-Object { [PSCustomObject]$_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'Availability Sets' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style

    }
}