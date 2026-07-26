<#
.Synopsis
Inventory for Azure Disk

.DESCRIPTION
This script consolidates information for all microsoft.compute/disks resource provider in $Resources variable. 
Excel Sheet Name: VMDISK

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Compute/VMDisk.ps1

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

        $disk = $Resources | Where-Object {$_.TYPE -eq 'microsoft.compute/disks'}

    <######### Insert the resource Process here ########>

    if($disk)
        {
            $tmp = foreach ($1 in $disk) {
                $ResUCount = 1
                # AB#5671: an EMPTY $sub1 (subscription outside the requested scope) is not $null,
                # so `.Name` on it throws; and `timeCreated` is absent on older disk API versions,
                # where [datetime]$null then produced a bogus 0001-01-01 anyway.
                $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
                # The else arm is $null, NOT '': with StrictMode off $sub1.Name on an unmatched ($null)
                # $sub1 evaluated to $null, and the ~110 collectors that still read $sub1.Name directly
                # emit $null here. '' was a silent behaviour change -- the declarative equivalence proof
                # caught it on 11 collectors, and it would have been invisible on the rest (AB#5659).
                $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { $null }
                $data = $1.PROPERTIES
                $timecreated = Get-AZSCSafeProperty -InputObject $data -Path 'timeCreated'
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
                $SKU = Get-AZSCSafeProperty -InputObject $1 -Path 'SKU'
                # Every `properties` field below is OPTIONAL in the disk API response: an unattached
                # standard disk omits maxShares, tier, dataAccessAuthMode, networkAccessPolicy and
                # osType outright, and `MANAGEDBY` is absent on any disk not currently attached --
                # where the historic `.split('/')[8]` also indexed past the end of a short id.
                $Hibernation = $data | Get-AZSCSafeProperty -Path 'supportsHibernation'
                $Hibernation = if (![string]::IsNullOrEmpty($Hibernation)) { $Hibernation }else { $false }
                $ManagedBySegments = @()
                $ManagedBy = Get-AZSCSafeProperty -InputObject $1 -Path 'MANAGEDBY'
                if (![string]::IsNullOrEmpty($ManagedBy)) { $ManagedBySegments = @(([string]$ManagedBy).split('/')) }
                $AssociatedResource = if ($ManagedBySegments.Count -gt 8) { $ManagedBySegments[8] } else { $null }
                $RowTags = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                # '0' was a sentinel to run the loop once for an untagged resource; `'0'.Name`
                # throws under StrictMode, and an empty tag object emits the identical row.
                $Tags = if(![string]::IsNullOrEmpty($TagProps)){$TagProps}else{[pscustomobject]@{ Name = $null; Value = $null }}
                    foreach ($Tag in $Tags) {
                        $obj = @{
                            'ID'                     = $1.id;
                            'Subscription'           = $SubscriptionName;
                            'Resource Group'         = $1.RESOURCEGROUP;
                            'Disk Name'              = $1.NAME;
                            'Retiring Feature'       = $RetiringFeature;
                            'Retiring Date'          = $RetiringDate;
                            'Disk State'             = (Get-AZSCSafeProperty -InputObject $data -Path 'diskState');
                            'Associated Resource'    = $AssociatedResource;
                            'Location'               = $1.LOCATION;
                            'Zone'                   = [string](Get-AZSCSafeProperty -InputObject $1 -Path 'ZONES');
                            'SKU'                    = (Get-AZSCSafeProperty -InputObject $SKU -Path 'Name');
                            'Disk Size'              = (Get-AZSCSafeProperty -InputObject $data -Path 'diskSizeGB');
                            'Performance Tier'       = (Get-AZSCSafeProperty -InputObject $data -Path 'tier');
                            'Disk IOPS Read / Write' = (Get-AZSCSafeProperty -InputObject $data -Path 'diskIOPSReadWrite');
                            'Disk MBps Read / Write' = (Get-AZSCSafeProperty -InputObject $data -Path 'diskMBpsReadWrite');
                            'Public Network Access'  = (Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccess');
                            'Connection Type'        = (Get-AZSCSafeProperty -InputObject $data -Path 'networkAccessPolicy');
                            'Hibernation Supported'  = $Hibernation;
                            'Encryption'             = (Get-AZSCSafeProperty -InputObject $data -Path 'encryption.type');
                            'OS Type'                = (Get-AZSCSafeProperty -InputObject $data -Path 'osType');
                            'Max Shares'             = (Get-AZSCSafeProperty -InputObject $data -Path 'maxShares');
                            'Data Access Auth Mode'  = (Get-AZSCSafeProperty -InputObject $data -Path 'dataAccessAuthMode');
                            'HyperV Generation'      = (Get-AZSCSafeProperty -InputObject $data -Path 'hyperVGeneration');
                            'Created Time'           = $timecreated;   
                            'Resource U'             = $ResUCount;
                            'Tag Name'               = [string]$Tag.Name;
                            'Tag Value'              = [string]$Tag.Value
                        }
                        $obj
                        if ($ResUCount -eq 1) { $ResUCount = 0}
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

        $SheetName = 'Disks'

        $TableName = ('VMDiskT_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))

        $condtxt = @()
        $condtxt += New-ConditionalText Unattached -Range F:F
        #Retirement
        $condtxt += New-ConditionalText -Range D2:D100 -ConditionalType ContainsText

        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Disk Name')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Disk State')
        $Exc.Add('Associated Resource')
        $Exc.Add('Location')  
        $Exc.Add('Zone')
        $Exc.Add('SKU')
        $Exc.Add('Disk Size')
        $Exc.Add('Performance Tier')
        $Exc.Add('Disk IOPS Read / Write')
        $Exc.Add('Disk MBps Read / Write')
        $Exc.Add('Public Network Access')
        $Exc.Add('Connection Type')
        $Exc.Add('Hibernation Supported')
        $Exc.Add('Encryption')
        $Exc.Add('OS Type')
        $Exc.Add('Max Shares')
        $Exc.Add('Data Access Auth Mode')
        $Exc.Add('HyperV Generation')
        $Exc.Add('Created Time')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName $SheetName -TableName $TableName -MaxAutoSizeRows 100 -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style

    }
}