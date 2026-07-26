<#
.Synopsis
Inventory for Azure Virtual Machine Scale Set

.DESCRIPTION
This script consolidates information for all microsoft.compute/virtualmachinescalesets resource provider in $Resources variable. 
Excel Sheet Name: VMSS

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Compute/VirtualMachineScaleSet.ps1

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

        $vmss = $Resources | Where-Object {$_.TYPE -eq 'microsoft.compute/virtualmachinescalesets'}
        $AutoScale = $Resources | Where-Object {$_.TYPE -eq "microsoft.insights/autoscalesettings" -and $_.Properties.enabled -eq 'true'} 
        $AKS = $Resources | Where-Object {$_.TYPE -eq 'microsoft.containerservice/managedclusters'}
        $SFC = $Resources | Where-Object {$_.TYPE -eq 'microsoft.servicefabric/clusters'}
        $VMExtraDetails = $Resources | Where-Object { $_.TYPE -eq 'AZSC/VM/SKU' }
        $VMQuotas = $Resources | Where-Object { $_.TYPE -eq 'AZSC/VM/Quotas' }

    <######### Insert the resource Process here ########>

    if($vmss)
        {
            $tmp = foreach ($1 in $vmss) {
                $ResUCount = 1
                # An EMPTY $sub1 is not $null, and `.Name` on it throws under StrictMode -- the
                # match is empty for any resource whose subscription is outside the requested
                # scope. Resolved once here, defensively, as VirtualMachine.ps1 already does.
                $sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
                $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { '' }
                $data = $1.PROPERTIES
                # AB#5671: every chain below hangs off `virtualMachineProfile`, which is ABSENT
                # (not $null) on a Flexible-orchestration scale set -- Flexible keeps the profile
                # on the member VMs, so the raw chains threw on the first such scale set. Reads
                # crossing `networkInterfaceConfigurations` / `ipConfigurations` (arrays) use
                # -Enumerate so the member enumeration the original relied on is reproduced
                # exactly, not silently collapsed to $null.
                $VMProfile = Get-AZSCSafeProperty -InputObject $data -Path 'virtualMachineProfile'
                $OS = Get-AZSCSafeProperty -InputObject $VMProfile -Path 'storageProfile.osDisk.osType'
                $RelatedAKS = Get-AZSCCollectedValue -InputObject @($AKS | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'properties.nodeResourceGroup') -eq $1.resourceGroup }) -Name 'Name'
                if([string]::IsNullOrEmpty($RelatedAKS)){
                    $VMSSClusterEndpoints = @(Get-AZSCSafeProperty -InputObject $VMProfile -Path 'extensionProfile.extensions.properties.settings.clusterEndpoint' -Enumerate)
                    $Related = Get-AZSCCollectedValue -InputObject @($SFC | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'Properties.clusterEndpoint') -in $VMSSClusterEndpoints }) -Name 'Name'
                }else{$Related = $RelatedAKS}
                $Scaling = ($AutoScale | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'Properties.targetResourceUri') -eq $1.id })
                if([string]::IsNullOrEmpty($Scaling)){$AutoSc = $false}else{$AutoSc = $true}
                $Diag = if(Get-AZSCSafeProperty -InputObject $VMProfile -Path 'diagnosticsProfile'){'Enabled'}else{'Disabled'}
                if($OS -eq 'Linux'){$PWD = Get-AZSCSafeProperty -InputObject $VMProfile -Path 'osProfile.linuxConfiguration.disablePasswordAuthentication'}Else{$PWD = 'N/A'}
                $AcceleratedNet = if(![string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $VMProfile -Path 'networkProfile.networkInterfaceConfigurations.properties.enableAcceleratedNetworking' -Enumerate))){$true}else{$false}

                # Extra Hardware Details
                #
                # $VMExtraDetails (the synthetic 'AZSC/VM/SKU' rows) is EMPTY whenever the SKU
                # enrichment query returned nothing, and reading `.properties` off an empty
                # collection throws under StrictMode (AB#5671). Every capability variable is also
                # reset per scale set: they are assigned only inside the loop below, so without
                # this they would leak the PREVIOUS scale set's values -- or, on the first
                # iteration, be genuinely unset, which StrictMode reports as an error too.
                $vCPUs = $null; $vCPUsPerCore = $null; $RAM = $null; $MaxDataDiskCount = $null
                $UncachedDiskIOPS = $null; $UncachedDiskBytesPerSecond = $null; $MaxNetworkInterfaces = $null

                $SKUName = Get-AZSCSafeProperty -InputObject $1 -Path 'sku.name'
                $VMExtraDetail = @(Get-AZSCCollectedValue -InputObject $VMExtraDetails -Name 'properties') |
                    Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'Location') -eq $1.location }
                $VMExtraDetail = @(Get-AZSCCollectedValue -InputObject $VMExtraDetail -Name 'SKUs') |
                    Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'Name') -eq $SKUName }

                foreach ($Capability in @(Get-AZSCCollectedValue -InputObject $VMExtraDetail -Name 'Capabilities')) {
                    if ($Capability.Name -eq 'vCPUs') {$vCPUs = $Capability.Value}
                    if ($Capability.Name -eq 'vCPUsPerCore') {$vCPUsPerCore = $Capability.Value}
                    if ($Capability.Name -eq 'MemoryGB') {$RAM = $Capability.Value}
                    if ($Capability.Name -eq 'MaxDataDiskCount') {$MaxDataDiskCount = $Capability.Value}
                    if ($Capability.Name -eq 'UncachedDiskIOPS') {$UncachedDiskIOPS = $Capability.Value}
                    if ($Capability.Name -eq 'UncachedDiskBytesPerSecond') {$UncachedDiskBytesPerSecond = ([math]::Round($Capability.Value / 1024) / 1024)}
                    if ($Capability.Name -eq 'MaxNetworkInterfaces') {$MaxNetworkInterfaces = $Capability.Value}
                }

                # Quotas -- same empty-collection hazard as the SKU block above, plus the
                # subtraction itself: with no matching quota row both operands were reads off an
                # empty collection. They now resolve to $null, and $null - $null is 0, which is
                # what the unguarded expression produced under -Off.
                $Size = Get-AZSCCollectedValue -InputObject $VMExtraDetail -Name 'Family'
                $Quota = @(Get-AZSCCollectedValue -InputObject $VMQuotas -Name 'properties') |
                    Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'SubId') -eq $1.subscriptionId }
                $Quota = $Quota | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'Location') -eq $1.location }
                $QuotaData = @(Get-AZSCCollectedValue -InputObject $Quota -Name 'Data') |
                    Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'Name.Value') -eq $Size }
                $RemainingQuota = ((Get-AZSCCollectedValue -InputObject $QuotaData -Name 'Limit') -
                                   (Get-AZSCCollectedValue -InputObject $QuotaData -Name 'CurrentValue'))


                # `timeCreated` is absent on older API versions, and [datetime]$null throws, so the
                # unguarded three-line conversion fails twice over under StrictMode (AB#5671).
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
                # Two array hops (networkInterfaceConfigurations, then ipConfigurations) -- exactly
                # what -Enumerate is for. `.split('/')[8]` / `[10]` are also guarded on segment
                # count now: a subnet id shorter than the standard shape used to raise
                # "Index was outside the bounds of the array" rather than yield $null (AB#5671).
                $Subnet = Get-AZSCSafeProperty -InputObject $VMProfile -Path 'networkProfile.networkInterfaceConfigurations.properties.ipConfigurations.properties.subnet.id' -Enumerate |
                    Select-Object -Unique
                # NOT `$x = if (...) { @(...) } else { @() }` -- an `if` used as an expression
                # returns its branch through the pipeline, and an EMPTY array enumerates to
                # nothing, so $x lands as $null and the very next `.Count` throws. Assign the
                # empty default first, then overwrite.
                $SubnetSegments = @()
                if(![string]::IsNullOrEmpty($Subnet)){ $SubnetSegments = @(([string]$Subnet).split('/')) }
                $VNET   = if($SubnetSegments.Count -gt 8) {$SubnetSegments[8]}else{$null}
                $Subnet = if($SubnetSegments.Count -gt 10){$SubnetSegments[10]}else{$null}
                $ext = @()
                # Not @()-wrapped: @($null) has one element, which would append a stray ', ' for a
                # scale set with no extensions where the original appended nothing.
                $ext = foreach ($ex in (Get-AZSCSafeProperty -InputObject $VMProfile -Path 'extensionProfile.extensions.name' -Enumerate))
                                {
                                    $ex + ', '
                                }
                $VMSSNsgId = Get-AZSCSafeProperty -InputObject $VMProfile -Path 'networkProfile.networkInterfaceConfigurations.properties.networkSecurityGroup.id' -Enumerate
                $VMSSNsgSegments = @()
                if(![string]::IsNullOrEmpty($VMSSNsgId)){ $VMSSNsgSegments = @(([string]$VMSSNsgId).split('/')) }
                $NSG = if($VMSSNsgSegments.Count -gt 8){$VMSSNsgSegments[8]}else{'Not Configured'}
                # A Resource Graph row for an untagged resource OMITS `tags` (it is not present-
                # and-empty), so both `$1.tags` and `$null.psobject.properties` throw under
                # StrictMode. The historic fall-back was the string '0', a sentinel whose only job
                # was to make the loop below run exactly once for an untagged resource -- but
                # `'0'.Name` throws under StrictMode too. An empty tag object does the same job
                # and emits the identical row: [string]$null and [string]('0'.Name) are both ''.
                $RowTags = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if(![string]::IsNullOrEmpty($TagProps)){$TagProps}else{[pscustomobject]@{ Name = $null; Value = $null }}
                foreach ($Tag in $Tags) {
                    $obj = @{
                        'ID'                            = $1.id;
                        'Subscription'                  = $SubscriptionName;
                        'Resource Group'                = $1.RESOURCEGROUP;
                        'AKS / SFC'                     = $Related;
                        'Name'                          = $1.NAME;
                        'Location'                      = $1.LOCATION;
                        'SKU Tier'                      = (Get-AZSCSafeProperty -InputObject $1 -Path 'sku.tier');
                        'Retiring Feature'              = $RetiringFeature;
                        'Retiring Date'                 = $RetiringDate;
                        'Fault Domain'                  = (Get-AZSCSafeProperty -InputObject $data -Path 'platformFaultDomainCount');
                        'Upgrade Policy'                = (Get-AZSCSafeProperty -InputObject $data -Path 'upgradePolicy.mode');
                        'Diagnostics'                   = $Diag;
                        'VM Size'                       = $SKUName;
                        'Instances'                     = (Get-AZSCSafeProperty -InputObject $1 -Path 'sku.capacity');
                        'vCPUs (per Instance)'          = $vCPUs;
                        'vCPUs per Core (per Instance)' = $vCPUsPerCore;
                        'Memory (GB) (per Instance)'    = $RAM;
                        'Remaining Quota'               = $RemainingQuota;
                        'Autoscale Enabled'             = $AutoSc;
                        'VM OS'                         = $OS;
                        'OS Image'                      = (Get-AZSCSafeProperty -InputObject $VMProfile -Path 'storageProfile.imageReference.offer');
                        'Image Version'                 = (Get-AZSCSafeProperty -InputObject $VMProfile -Path 'storageProfile.imageReference.sku');
                        'VM OS Disk Size (GB)'          = (Get-AZSCSafeProperty -InputObject $VMProfile -Path 'storageProfile.osDisk.diskSizeGB');
                        'Disk Storage Account Type'     = (Get-AZSCSafeProperty -InputObject $VMProfile -Path 'storageProfile.osDisk.managedDisk.storageAccountType');
                        'Disable Password Authentication'= $PWD;
                        'Custom DNS Servers'            = [string](Get-AZSCSafeProperty -InputObject $VMProfile -Path 'networkProfile.networkInterfaceConfigurations.properties.dnsSettings.dnsServers' -Enumerate);
                        'Virtual Network'               = $VNET;
                        'Subnet'                        = $Subnet;
                        'Accelerated Networking Enabled'= $AcceleratedNet; 
                        'Network Security Group'        = $NSG;
                        'Extensions'                    = [string]$ext;
                        'Admin Username'                = (Get-AZSCSafeProperty -InputObject $VMProfile -Path 'osProfile.adminUsername');
                        'VM Name Prefix'                = (Get-AZSCSafeProperty -InputObject $VMProfile -Path 'osProfile.computerNamePrefix');
                        'Created Time'                  = $timecreated;
                        'Resource U'                    = $ResUCount;
                        'Tag Name'                      = [string]$Tag.Name;
                        'Tag Value'                     = [string]$Tag.Value
                    }
                    $obj
                    if ($ResUCount -eq 1) { $ResUCount = 0 } 
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
        $SheetName = 'Virtual Machine Scale Sets'

        $TableName = ('VMSSTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = @()        
        $Style += New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0' -Range A:W
        $Style += New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0.0' -Range Y:AA
        $Style += New-ExcelStyle -HorizontalAlignment Left -Range W:W -Width 60 -WrapText

        $condtxt = @()
        $condtxt += New-ConditionalText FALSE -Range R:R
        $condtxt += New-ConditionalText Disabled -Range K:K
        $condtxt += New-ConditionalText FALSE -Range AB:AB
        # Quota = 0
        $condtxt += New-ConditionalText 0 -Range Q:Q
        #Retirement
        $condtxt += New-ConditionalText -Range G2:G100 -ConditionalType ContainsText


        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('AKS / SFC')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('SKU Tier')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Fault Domain')
        $Exc.Add('Upgrade Policy')                                   
        $Exc.Add('Diagnostics')
        $Exc.Add('VM Size')
        $Exc.Add('Instances')
        $Exc.Add('vCPUs (per Instance)')
        $Exc.Add('vCPUs per Core (per Instance)')
        $Exc.Add('Memory (GB) (per Instance)')
        $Exc.Add('Remaining Quota')
        $Exc.Add('Autoscale Enabled')
        $Exc.Add('VM OS')
        $Exc.Add('OS Image')
        $Exc.Add('Image Version')                        
        $Exc.Add('VM OS Disk Size (GB)')
        $Exc.Add('Disk Storage Account Type')
        $Exc.Add('Disable Password Authentication')
        $Exc.Add('Custom DNS Servers')
        $Exc.Add('Virtual Network')
        $Exc.Add('Subnet')
        $Exc.Add('Accelerated Networking Enabled')
        $Exc.Add('Network Security Group')
        $Exc.Add('Extensions')
        $Exc.Add('Admin Username')
        $Exc.Add('VM Name Prefix')
        $Exc.Add('Created Time')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        $SmaResources | 
        ForEach-Object { [PSCustomObject]$_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName $SheetName -AutoSize -MaxAutoSizeRows 50 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style


        $excel = Open-ExcelPackage -Path $File

        $sheet = $excel.Workbook.Worksheets[$SheetName]

        #Remaining Quota
        Add-ConditionalFormatting -WorkSheet $sheet -RuleType Between -ConditionValue 50 -ConditionValue2 100 -Address Q:Q -BackgroundColor "Yellow"
        Add-ConditionalFormatting -WorkSheet $sheet -RuleType Between -ConditionValue 1 -ConditionValue2 50 -Address Q:Q -BackgroundColor 'LightPink' -ForegroundColor 'DarkRed'

        Close-ExcelPackage $excel

    }
}