<#
.Synopsis
Inventory for Azure Virtual Machine

.DESCRIPTION
This script consolidates information for all microsoft.compute/virtualmachines resource provider in $Resources variable. 
Excel Sheet Name: Virtual Machines

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Compute/VirtualMachine.ps1

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC).

.CATEGORY Compute

.NOTES
Version: 3.6.0
First Release Date: 19th November, 2020
Authors: Claudio Merola and Renato Gregio 

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{

        $vm =  $Resources | Where-Object {$_.TYPE -eq 'microsoft.compute/virtualmachines'}
        $nic = $Resources | Where-Object {$_.TYPE -eq 'microsoft.network/networkinterfaces'}
        $vmexp = $Resources | Where-Object {$_.TYPE -eq 'microsoft.compute/virtualmachines/extensions'}
        $disk = $Resources | Where-Object {$_.TYPE -eq 'microsoft.compute/disks'}
        $VirtualNetwork = $Resources | Where-Object { $_.TYPE -eq 'microsoft.network/virtualnetworks' }
        $VMExtraDetails = $Resources | Where-Object { $_.TYPE -eq 'AZSC/VM/SKU' }
        $VMQuotas = $Resources | Where-Object { $_.TYPE -eq 'AZSC/VM/Quotas' }

    if($vm)
        {    

            $tmp = foreach ($1 in $vm) 
                {
                    $ResUCount = 1
                    # $SUB does not always contain the resource's subscription -- a management-group
                    # scoped run, a subscription the caller lost access to mid-run, or simply a
                    # resource row from a subscription outside the requested scope all leave this
                    # Where-Object matching nothing. An EMPTY result is not $null, and reading
                    # .Name off it throws under StrictMode (AB#5667), so the name is resolved once,
                    # defensively, instead of at the point of use ~400 lines below.
                    $sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
                    # The else arm is $null, NOT '': with StrictMode off $sub1.Name on an unmatched ($null)
                    # $sub1 evaluated to $null, and the ~110 collectors that still read $sub1.Name directly
                    # emit $null here. '' was a silent behaviour change -- the declarative equivalence proof
                    # caught it on 11 collectors, and it would have been invisible on the rest (AB#5659).
                    $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { $null }
                    $data = $1.PROPERTIES
                    # $data.timeCreated: absent entirely on some API versions/resource kinds, not
                    # just $null -- a plain member read throws under StrictMode when the
                    # NoteProperty genuinely does not exist (AB#5667). PSObject.Properties[...]
                    # is a safe existence check either way.
                    $timecreated = if ($data.PSObject.Properties['timeCreated']) { $data.timeCreated } else { $null }
                    $timecreated = if ($timecreated) { ([datetime]$timecreated).ToString("yyyy-MM-dd HH:mm") } else { '' }
                    $dataSize = ''
                    $StorAcc = ''
                    # `extended` is populated by the instance-view expansion and is ABSENT (not
                    # null) on a plain Resource Graph row, and `storageProfile.imageReference` is
                    # absent on a VM created from a specialised/attached disk rather than a
                    # gallery image -- both chains throw under StrictMode (AB#5667). The
                    # fall-back logic is unchanged; only the reads are made safe.
                    $ExtendedOsName    = Get-AZSCSafeProperty -InputObject $data -Path 'extended.instanceView.osname'
                    $ExtendedOsVersion = Get-AZSCSafeProperty -InputObject $data -Path 'extended.instanceView.osversion'
                    $ImageOffer        = Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.imageReference.offer'
                    $ImageSku          = Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.imageReference.sku'

                    $OSName = if(![string]::IsNullOrEmpty($ExtendedOsName)){$ExtendedOsName}else{$ImageOffer}
                    $OSVersion = if(![string]::IsNullOrEmpty($ExtendedOsVersion)){$ExtendedOsVersion}else{$ImageSku}

                    # Extra VM Details
                    #
                    # $VMExtraDetails ($Resources filtered to the synthetic 'AZSC/VM/SKU' type) is
                    # empty on most tenants/fixtures -- member access on an empty collection
                    # throws under StrictMode (AB#5667), so every step of this chain, and every
                    # capability variable it feeds, is reset to a known value up front rather than
                    # left holding a previous VM's value when this VM has no match.
                    $vCPUs = $null; $vCPUsPerCore = $null; $RAM = $null; $MaxDataDiskCount = $null
                    $UncachedDiskIOPS = $null; $UncachedDiskBytesPerSecond = $null; $MaxNetworkInterfaces = $null

                    $VMExtraDetail = if ($VMExtraDetails) { $VMExtraDetails.properties | Where-Object {$_.Location -eq $1.location} } else { $null }
                    # hardwareProfile is absent on some VM shapes (and on any malformed row);
                    # resolved once here so the Where-Object below does not read it per SKU.
                    $VMSize = Get-AZSCSafeProperty -InputObject $data -Path 'hardwareProfile.vmSize'
                    $VMExtraDetail = if ($VMExtraDetail) { $VMExtraDetail.SKUs | Where-Object {$_.Name -eq $VMSize} } else { $null }

                    if ($VMExtraDetail) {
                        foreach ($Capability in $VMExtraDetail.Capabilities) {
                            if ($Capability.Name -eq 'vCPUs') {$vCPUs = $Capability.Value}
                            if ($Capability.Name -eq 'vCPUsPerCore') {$vCPUsPerCore = $Capability.Value}
                            if ($Capability.Name -eq 'MemoryGB') {$RAM = $Capability.Value}
                            if ($Capability.Name -eq 'MaxDataDiskCount') {$MaxDataDiskCount = $Capability.Value}
                            if ($Capability.Name -eq 'UncachedDiskIOPS') {$UncachedDiskIOPS = $Capability.Value}
                            if ($Capability.Name -eq 'UncachedDiskBytesPerSecond') {$UncachedDiskBytesPerSecond = ([math]::Round($Capability.Value / 1024) / 1024)}
                            if ($Capability.Name -eq 'MaxNetworkInterfaces') {$MaxNetworkInterfaces = $Capability.Value}
                        }
                    }

                    # Quotas -- $VMExtraDetail/$VMQuotas/$Quota are all empty on most
                    # tenants/fixtures (the synthetic 'AZSC/VM/SKU' and 'AZSC/VM/Quotas' types are
                    # rarely present), and member access on an empty collection throws under
                    # StrictMode (AB#5667), so every step is guarded rather than chained.
                    $Size = if ($VMExtraDetail) { $VMExtraDetail.Family } else { $null }
                    $Quota = if ($VMQuotas) { $VMQuotas.properties | Where-Object {$_.SubId -eq $1.subscriptionId} } else { $null }
                    $Quota = if ($Quota) { $Quota | Where-Object {$_.Location -eq $1.location} } else { $null }
                    $RemainingQuota = if ($Quota) {
                        (($Quota.Data | Where-Object {$_.Name.Value -eq $Size}).Limit - ($Quota.Data | Where-Object {$_.Name.Value -eq $Size}).CurrentValue)
                    } else { $null }

                    # Same "$VMExtraDetail may be empty" guard as above, for the two remaining
                    # chains off it that are only read once per VM (further down, in $obj).
                    $VMZonesAvailable = if ($VMExtraDetail) { [string]$VMExtraDetail.LocationInfo.ZoneDetails.Name } else { '' }
                    $VMCapabilities   = if ($VMExtraDetail) { [string]$VMExtraDetail.LocationInfo.ZoneDetails.Capabilities.Name } else { '' }

                    $Retired = Foreach ($Retirement in $Retirements)
                        {
                            if ($Retirement.id -eq $1.id) { $Retirement }
                        }
                    if ($Retired) 
                        {
                            $RetiredFeature = foreach ($Retire in $Retired)
                                {
                                    $RetiredServiceID = $Unsupported | Where-Object {$_.Id -eq $Retired.ServiceID}
                                    $tmp0 = [PSCustomObject]@{
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

                    #Extensions 
                    $ext = @()
                    $AzDiag = ''
                    $Azinsights = ''
                    # licenseType is only present at all when Hybrid Benefit is configured -- most
                    # VMs never set it, so a plain $data.licenseType read throws under StrictMode
                    # on the common case, not the exception (AB#5667).
                    $LicenseType = if ($data.PSObject.Properties['licenseType']) { $data.licenseType } else { $null }
                    $Lic = switch ($LicenseType) {
                        'Windows_Server' { 'Azure Hybrid Benefit for Windows' }
                        'Windows_Client' { 'Windows client with multi-tenant hosting' }
                        'RHEL_BYOS' { 'Azure Hybrid Benefit for Redhat' }
                        'SLES_BYOS' { 'Azure Hybrid Benefit for SUSE' }
                        default { $LicenseType }
                    }
                    $Lic = if($Lic){$Lic}else{'None'}
                    $ext = foreach ($vmextension in $vmexp)
                        {
                            if (($vmextension.id -split "/")[8] -eq $1.name) { $vmextension.properties.Publisher }
                        }
                    if ($null -ne $ext) 
                        {
                            $ext = foreach ($ex in $ext) 
                                {
                                    if ($ex | Where-Object { $_ -eq 'Microsoft.Azure.Performance.Diagnostics' }) { $AzDiag = $true }
                                    if ($ex | Where-Object { $_ -eq 'Microsoft.EnterpriseCloud.Monitoring' }) { $Azinsights = $true }
                                    $ex + ', '
                                }
                            $ext = [string]$ext
                            $ext = $ext.Substring(0, $ext.Length - 2)
                        }

                    # Every $data.<chain> below is optional-block territory: a VM that does not
                    # use it does not merely carry a $null value, the whole block is ABSENT from
                    # the API response, and a raw chain throws under StrictMode the moment it
                    # hits the missing segment (AB#5667). Get-AZSCSafeProperty returns $null
                    # instead, exactly like the (unreachable-in-practice) $null a pre-StrictMode
                    # reader of this same chain would have seen.
                    # Neither branch below runs when a VM carries neither a windowsConfiguration
                    # nor a linuxConfiguration block, and reading an unassigned variable is its
                    # own StrictMode failure -- distinct from the missing-property class, and
                    # worse, because without StrictMode it silently reuses the PREVIOUS VM's
                    # value for every VM after the first (this loop reuses one scope).
                    $Autoupdate = $null
                    $WindowsAutoUpdate = Get-AZSCSafeProperty -InputObject $data -Path 'osProfile.windowsConfiguration.enableAutomaticUpdates'
                    $LinuxPatchMode    = Get-AZSCSafeProperty -InputObject $data -Path 'osProfile.linuxConfiguration.patchSettings.patchMode'

                    if(![string]::IsNullOrEmpty($WindowsAutoUpdate))
                        {
                            if($WindowsAutoUpdate -eq 'True')
                                {
                                    $Autoupdate = $true
                                }
                            else
                                {
                                    $Autoupdate = $false
                                }
                        }
                    elseif(![string]::IsNullOrEmpty($LinuxPatchMode))
                        {
                            if($LinuxPatchMode -eq 'automaticbyos')
                                {
                                    $Autoupdate = $true
                                }
                            else
                                {
                                    $Autoupdate = $false
                                }
                        }

                    $AvailabilitySetValue = Get-AZSCSafeProperty -InputObject $data -Path 'availabilitySet'
                    if (![string]::IsNullOrEmpty($AvailabilitySetValue)) { $AVSET = $true }else { $AVSET = $false }
                    $BootDiagEnabled = Get-AZSCSafeProperty -InputObject $data -Path 'diagnosticsProfile.bootDiagnostics.enabled'
                    if ($BootDiagEnabled -eq $true) { $bootdg = $true }else { $bootdg = $false }

                    #Storage
                    $OsDiskVhdUri         = Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.osDisk.vhd.uri'
                    $OsDiskManagedDiskId  = Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.osDisk.managedDisk.id'
                    $DataDisksManagedIds  = Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.dataDisks.managedDisk.id'

                    # Both are left unassigned when the VM uses a managed OS disk that is not in
                    # $disk (a disk outside the queried scope, or simply no matching row) --
                    # the same reuse-the-previous-VM's-value hazard as $Autoupdate above.
                    $OSDisk     = $null
                    $OSDiskSize = $null

                    if($OsDiskVhdUri)
                        {
                            $OSDisk = 'Custom VHD'
                            $OSDiskSize = Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.osDisk.diskSizeGB'
                        }
                    else
                        {
                            foreach ($VMDisk in $disk)
                                {
                                    if ($VMDisk.id -eq $OsDiskManagedDiskId)
                                        {
                                            $OSDisk = $VMDisk.sku.name
                                        }
                                    if ($VMDisk.id -eq $DataDisksManagedIds)
                                        {
                                            $OSDiskSize = $VMDisk.properties.diskSizeGB
                                        }
                                }
                        }

                    if ($DataDisksManagedIds)
                        {
                            if (@($DataDisksManagedIds).count -ge 2)
                            {
                                $StorAcc = (@($DataDisksManagedIds).count.ToString() + ' Disks found.')
                                foreach ($VMDisk in $disk)
                                    {
                                        if ($VMDisk.id -in $DataDisksManagedIds)
                                            {
                                                $dataSize = ($VMDisk.properties.diskSizeGB | Measure-Object -Sum).Sum
                                            }
                                    }
                            }
                            else
                            {
                                foreach ($VMDisk in $disk)
                                    {
                                        if ($VMDisk.id -eq $DataDisksManagedIds)
                                            {
                                                $StorAcc = $VMDisk.sku.name
                                                $dataSize = $VMDisk.properties.diskSizeGB
                                            }
                                    }
                            }
                        }
                    else
                        {
                            $StorAcc = 'None'
                            $dataSize = '0'
                        }

                    # The untagged case still has to emit ONE row per VM, which is why this is a
                    # sentinel rather than an empty collection. It used to be the string '0':
                    # harmless without StrictMode ([string]$Tag.Name on a string quietly yields
                    # ''), but a hard throw with it, since [string] has no Name member. An object
                    # carrying empty Name/Value produces byte-identical output and cannot throw.
                    # `$1.tags` itself is absent (not empty) on rows the Graph never tagged.
                    $TagProperties = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                    $Tags = if($null -ne $TagProperties -and ![string]::IsNullOrEmpty($TagProperties.psobject.properties)){$TagProperties.psobject.properties}else{[pscustomobject]@{ Name = ''; Value = '' }}
                    # networkInterfaces is an ARRAY of {id} references -- when it is empty (a
                    # VM row that genuinely has none), enumerating .id off it throws under
                    # StrictMode the same way an empty $Resources match does (AB#5633's rule);
                    # fetch the array itself safely first, then only enumerate when non-empty.
                    $NetworkInterfaceRefs = Get-AZSCSafeProperty -InputObject $data -Path 'networkProfile.networkInterfaces'
                    $VMNICS = if ($NetworkInterfaceRefs) { $NetworkInterfaceRefs.id } else { '0' }
                    foreach ($2 in $VMNICS) {

                        $vmnic = foreach ($netinterface in $nic)
                            {
                                if ($netinterface.id -eq $2) { $netinterface }
                            }
                        $vmnic = $vmnic | Select-Object -Unique

                        # No matching NIC row (common for every VM this harness's fixtures do not
                        # also carry a NIC for) -- $vmnic is $null, and every chain below reads a
                        # property OFF it, which throws under StrictMode on a null base (AB#5667).
                        # Match the values each branch's own "not found" case already produced.
                        if ($vmnic) {
                            # ipConfigurations is an ARRAY -- .properties.publicIPAddress.id relies
                            # on PowerShell's member-enumeration-across-elements magic, which
                            # throws under StrictMode the moment any hop is absent on every element
                            # (e.g. a NIC with no public IP simply omits 'publicIPAddress' rather
                            # than setting it null -- AB#5667/AB#5633's rule). Get-AZSCCollectedValue
                            # walks the same chain one safe hop at a time instead.
                            $IpConfigs      = Get-AZSCSafeProperty -InputObject $vmnic -Path 'properties.ipConfigurations'
                            $IpConfigProps  = Get-AZSCCollectedValue -InputObject $IpConfigs -Name 'properties'
                            $PublicIpId     = Get-AZSCCollectedValue -InputObject (Get-AZSCCollectedValue -InputObject $IpConfigProps -Name 'publicIPAddress') -Name 'id' | Select-Object -First 1
                            $SubnetId       = Get-AZSCCollectedValue -InputObject (Get-AZSCCollectedValue -InputObject $IpConfigProps -Name 'subnet') -Name 'id' | Select-Object -First 1

                            $PIP = if(![string]::IsNullOrEmpty($PublicIpId)){$PublicIpId.split('/')[8]}else{''}
                            $VNET = if(![string]::IsNullOrEmpty($SubnetId)){$SubnetId.split('/')[8]}else{''}
                            $Subnet = if(![string]::IsNullOrEmpty($SubnetId)){$SubnetId.split('/')[10]} else {''}
                            $vmnet = foreach ($VMVnet in $VirtualNetwork)
                                {
                                    if ((Get-AZSCCollectedValue -InputObject (Get-AZSCSafeProperty -InputObject $VMVnet -Path 'subnets') -Name 'id') -eq $SubnetId) { $VMVnet }
                                }
                            # A subnet entry without an `id` is rare but real (an inline subnet
                            # definition on some API versions), and a bare $_.id in the filter
                            # throws under StrictMode for the whole VM rather than skipping that
                            # one entry.
                            # A subnet entry without an `id` -- or a $null entry -- is rare but
                            # real, and a bare $_.id in the filter throws under StrictMode for the
                            # whole VM rather than skipping that one entry. Get-AZSCSafeProperty
                            # rather than $_.PSObject.Properties['id'] because .PSObject itself is
                            # not safe to dereference on a $null element.
                            $vmnetsubnet = (Get-AZSCSafeProperty -InputObject $vmnet -Path 'properties.subnets') |
                                Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'id') -eq $SubnetId }

                            $NicDnsServers = Get-AZSCSafeProperty -InputObject $vmnic -Path 'properties.dnsSettings.dnsServers'
                            if(![string]::IsNullOrEmpty($NicDnsServers))
                                {
                                    $DNSServer = $NicDnsServers
                                }
                            else
                                {
                                    $DNSServer = Get-AZSCSafeProperty -InputObject $vmnet -Path 'properties.dhcpoptions.dnsservers'
                                }

                            if(![string]::IsNullOrEmpty($DNSServer))
                                {
                                    $FinalDNS = if (@($DNSServer).count -gt 1) { $DNSServer | ForEach-Object { $_ + ' ,' } }else { $DNSServer }
                                    $FinalDNS = [string]$FinalDNS
                                    $FinalDNS = if ($FinalDNS -like '* ,*') { $FinalDNS -replace ".$" }else { $FinalDNS }
                                    $FinalDNS = ('VNET: ( ' + $FinalDNS + ')')
                                }
                            else
                                {
                                    $FinalDNS = 'Default (Azure-provided)'
                                }

                            $NicNsgId = Get-AZSCSafeProperty -InputObject $vmnic -Path 'properties.networkSecurityGroup.id'
                            $SubnetNsgId = Get-AZSCSafeProperty -InputObject $vmnetsubnet -Path 'properties.networksecuritygroup.id'
                            if(![string]::IsNullOrEmpty($NicNsgId))
                                {
                                    $vmnsg = $NicNsgId.split('/')[8]
                                }
                            elseif(![string]::IsNullOrEmpty($SubnetNsgId))
                                {
                                    $vmnsg = ('Subnet: ('+$SubnetNsgId.split('/')[8]+')')
                                }
                            else
                                {
                                    $vmnsg = 'None'
                                }
                            $NicAcceleratedNetworking = Get-AZSCSafeProperty -InputObject $vmnic -Path 'properties.enableAcceleratedNetworking'
                            if(![string]::IsNullOrEmpty($NicAcceleratedNetworking))
                                {
                                    $AcceleratedNetwork = $true
                                }
                            else
                                {
                                    $AcceleratedNetwork = $false
                                }
                        } else {
                            $PIP = ''; $VNET = ''; $Subnet = ''; $vmnet = $null; $vmnetsubnet = $null
                            $DNSServer = $null; $FinalDNS = 'Default (Azure-provided)'
                            $vmnsg = 'None'; $AcceleratedNetwork = $false
                            # $IpConfigProps is read again further down (Private IP Address/
                            # Allocation) -- initialised here too so that read is never the FIRST
                            # assignment to it under StrictMode for a VM whose only NIC match
                            # failed (an unset variable throws exactly like a missing property).
                            $IpConfigProps = $null
                        }

                        # ── Phase 17: Performance Metrics (Azure Monitor) ──────────────────
                        $avgCpu    = 'N/A'
                        $avgMem    = 'N/A'
                        try {
                            $monEnd   = (Get-Date).ToUniversalTime().ToString('o')
                            $monStart = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
                            $cpuUri   = "/subscriptions/$($1.subscriptionId)/resourceGroups/$($1.RESOURCEGROUP)/providers/Microsoft.Compute/virtualMachines/$($1.NAME)/providers/microsoft.insights/metrics?api-version=2019-07-01&metricnames=Percentage+CPU&timespan=$monStart/$monEnd&interval=P1D&aggregation=Average"
                            $cpuResp  = Invoke-AzRestMethod -Path $cpuUri -Method GET -ErrorAction SilentlyContinue
                            if ($cpuResp.StatusCode -eq 200) {
                                $cpuData = $cpuResp.Content | ConvertFrom-Json
                                $vals    = $cpuData.value[0].timeseries[0].data.average | Where-Object { $_ -ne $null }
                                if ($vals) { $avgCpu = [math]::Round(($vals | Measure-Object -Average).Average, 1) }
                            }
                        } catch {}
                        try {
                            $memUri  = "/subscriptions/$($1.subscriptionId)/resourceGroups/$($1.RESOURCEGROUP)/providers/Microsoft.Compute/virtualMachines/$($1.NAME)/providers/microsoft.insights/metrics?api-version=2019-07-01&metricnames=Available+Memory+Bytes&timespan=$monStart/$monEnd&interval=P1D&aggregation=Average"
                            $memResp = Invoke-AzRestMethod -Path $memUri -Method GET -ErrorAction SilentlyContinue
                            if ($memResp.StatusCode -eq 200) {
                                $memData  = $memResp.Content | ConvertFrom-Json
                                $memVals  = $memData.value[0].timeseries[0].data.average | Where-Object { $_ -ne $null }
                                $ramBytes = [double]$RAM * 1073741824
                                if ($memVals -and $ramBytes -gt 0) {
                                    $avgAvailBytes = ($memVals | Measure-Object -Average).Average
                                    $avgMem = [math]::Round((($ramBytes - $avgAvailBytes) / $ramBytes) * 100, 1)
                                }
                            }
                        } catch {}

                        # ── Phase 17: DR Status (Azure Site Recovery) ─────────────────────
                        $drReplicated  = 'N/A'
                        $drTargetRegion = 'N/A'
                        $drHealth      = 'N/A'
                        try {
                            $asrUri  = "/subscriptions/$($1.subscriptionId)/providers/Microsoft.RecoveryServices/replicationEligibilityResults/$($1.NAME)?api-version=2022-10-01"
                            $asrResp = Invoke-AzRestMethod -Path $asrUri -Method GET -ErrorAction SilentlyContinue
                            if ($asrResp.StatusCode -eq 200) {
                                $asrData = $asrResp.Content | ConvertFrom-Json
                                if ($asrData.properties.eligible -eq $false -and $asrData.properties.errorDetails) {
                                    # Not eligible may mean already replicated; check replication
                                    $drReplicated = 'Check ASR'
                                } elseif ($asrData.properties.eligible -eq $true) {
                                    $drReplicated = $false
                                }
                            }
                            # Try to find replication protected items across vaults
                            $vaultUri  = "/subscriptions/$($1.subscriptionId)/providers/Microsoft.RecoveryServices/vaults?api-version=2023-04-01"
                            $vaultResp = Invoke-AzRestMethod -Path $vaultUri -Method GET -ErrorAction SilentlyContinue
                            if ($vaultResp.StatusCode -eq 200) {
                                $vaults = ($vaultResp.Content | ConvertFrom-Json).value
                                foreach ($vault in $vaults) {
                                    $rpUri  = "/subscriptions/$($1.subscriptionId)/resourceGroups/$($vault.id.split('/')[4])/providers/Microsoft.RecoveryServices/vaults/$($vault.name)/replicationProtectedItems?api-version=2022-10-01"
                                    $rpResp = Invoke-AzRestMethod -Path $rpUri -Method GET -ErrorAction SilentlyContinue
                                    if ($rpResp.StatusCode -eq 200) {
                                        $rpItems = ($rpResp.Content | ConvertFrom-Json).value
                                        $vmItem  = $rpItems | Where-Object { $_.properties.friendlyName -eq $1.NAME }
                                        if ($vmItem) {
                                            $drReplicated   = $true
                                            $drTargetRegion = $vmItem.properties.recoveryAzureResourceGroupId -split '/'  | Select-Object -Index 4
                                            $drHealth       = $vmItem.properties.replicationHealth
                                            break
                                        }
                                    }
                                }
                            }
                        } catch {}

                        # ── Phase 17: Cost Estimate (Cost Management) ─────────────────────
                        $estMonthlyCost = 'N/A'
                        try {
                            $costUri  = "/subscriptions/$($1.subscriptionId)/providers/Microsoft.CostManagement/query?api-version=2023-03-01"
                            $costBody = @{
                                type       = 'Usage'
                                timeframe  = 'MonthToDate'
                                dataset    = @{
                                    granularity = 'None'
                                    filter      = @{
                                        dimensions = @{ name = 'ResourceId'; operator = 'In'; values = @($1.id) }
                                    }
                                    aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } }
                                }
                            } | ConvertTo-Json -Depth 10
                            $costResp = Invoke-AzRestMethod -Path $costUri -Method POST -Payload $costBody -ErrorAction SilentlyContinue
                            if ($costResp.StatusCode -eq 200) {
                                $costData = $costResp.Content | ConvertFrom-Json
                                $rawCost  = $costData.properties.rows[0][0]
                                if ($rawCost -ne $null) { $estMonthlyCost = [math]::Round([double]$rawCost, 2) }
                            }
                        } catch {}

                        foreach ($Tag in $Tags) 
                            {
                                $obj = @{
                                'ID'                                    = $1.id;
                                'Subscription'                          = $SubscriptionName;
                                'Resource Group'                        = $1.RESOURCEGROUP;
                                'VM Name'                               = $1.NAME;
                                'Location'                              = $1.LOCATION;
                                'Retiring Feature'                      = $RetiringFeature;
                                'Retiring Date'                         = $RetiringDate;
                                'Availability Zone'                     = [string]$1.ZONES;
                                'Zones Available in the Region'         = $VMZonesAvailable;
                                'Availability Set'                      = $AVSET;
                                'VM Size'                               = $VMSize;
                                'Remaining Quota (vCPUs)'               = [string]$RemainingQuota;
                                'vCPUs'                                 = $vCPUs;
                                'vCPUs Per Core'                        = $vCPUsPerCore;
                                'RAM (GiB)'                             = $RAM;
                                'Max Remote Storage Disks'              = $MaxDataDiskCount;
                                'Uncached Disk IOPS Limit'              = $UncachedDiskIOPS;
                                'Uncached Disk Throughput Limit (MB/s)' = $UncachedDiskBytesPerSecond;
                                'Max Network Interfaces'                = $MaxNetworkInterfaces;
                                # Same absent-imageReference case as $ImageOffer/$ImageSku above.
                                'Image Reference'                       = (Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.imageReference.publisher');
                                'Image Version'                         = (Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.imageReference.exactVersion');
                                'Capabilities'                          = $VMCapabilities;
                                'Hybrid Benefit'                        = $Lic;
                                # osProfile is absent on a VM created from a specialised disk (no
                                # provisioning agent ran), osDisk on some attached-disk shapes.
                                'Admin Username'                        = (Get-AZSCSafeProperty -InputObject $data -Path 'osProfile.adminUsername');
                                'OS Type'                               = (Get-AZSCSafeProperty -InputObject $data -Path 'storageProfile.osDisk.osType');
                                'OS Name'                               = $OSName;
                                'OS Version'                            = $OSVersion;
                                'Automatic Update'                      = $Autoupdate;
                                'Boot Diagnostics'                      = $bootdg;
                                'Performance Agent'                     = if ($azDiag -ne '') { $true }else { $false };
                                'Azure Monitor'                         = if ($Azinsights -ne '') { $true }else { $false };
                                'OS Disk Storage Type'                  = $OSDisk;
                                'OS Disk Size (GB)'                     = $OSDiskSize;
                                'Data Disk Storage Type'                = $StorAcc;
                                'Data Disk Size (GB)'                   = $dataSize;
                                'VM generation'                         = (Get-AZSCSafeProperty -InputObject $data -Path 'extended.instanceview.hypervgeneration');
                                'Power State'                           = (Get-AZSCSafeProperty -InputObject $data -Path 'extended.instanceView.powerState.displayStatus');
                                'NIC Name'                              = [string](Get-AZSCSafeProperty -InputObject $vmnic -Path 'name');
                                'NIC Type'                              = [string](Get-AZSCSafeProperty -InputObject $vmnic -Path 'properties.nicType');
                                'DNS Servers'                           = $FinalDNS;
                                'Public IP'                             = $PIP;
                                'Virtual Network'                       = $VNET;
                                'Subnet'                                = $Subnet;
                                'NSG'                                   = $vmnsg;
                                'Accelerated Networking'                = $AcceleratedNetwork;
                                'IP Forwarding'                         = [string](Get-AZSCSafeProperty -InputObject $vmnic -Path 'properties.enableIPForwarding');
                                'Private IP Address'                    = [string](Get-AZSCCollectedValue -InputObject $IpConfigProps -Name 'privateIPAddress' | Select-Object -First 1);
                                'Private IP Allocation'                 = [string](Get-AZSCCollectedValue -InputObject $IpConfigProps -Name 'privateIPAllocationMethod' | Select-Object -First 1);
                                'Creation Time'                         = $timecreated;
                                'VM Extensions'                         = $ext;
                                'Avg CPU % (7d)'                        = $avgCpu;
                                'Avg Memory % (7d)'                     = $avgMem;
                                'DR Replicated'                         = $drReplicated;
                                'DR Target Region'                      = $drTargetRegion;
                                'DR Replication Health'                 = $drHealth;
                                'Est. Monthly Cost (USD)'               = $estMonthlyCost;
                                'Resource U'                            = $ResUCount;
                                'Tag Name'                              = [string]$Tag.Name;
                                'Tag Value'                             = [string]$Tag.Value
                                }
                                if ($ResUCount -eq 1) { $ResUCount = 0 }
                                $obj
                            }
                        }
                    }
                $tmp
        }
}
else
{
    If($SmaResources)
        {

            $TableName = ('VMTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
            $Style = @()
            $Style += New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0' -VerticalAlignment Center
            $Style += New-ExcelStyle -HorizontalAlignment Left -Range AW:AW -Width 60 -WrapText

            $SheetName = 'Virtual Machines'

            $condtxt = @()
            #Automatic Updates
            $condtxt += New-ConditionalText false -Range V:V
            #Hybrid Benefit
            $condtxt += New-ConditionalText None -Range Y:Y
            #Boot Diagnostics
            $condtxt += New-ConditionalText false -Range AA:AA
            #Performance Agent
            $condtxt += New-ConditionalText false -Range AB:AB
            #Azure Monitor
            $condtxt += New-ConditionalText false -Range AC:AC
            #NSG
            $condtxt += New-ConditionalText None -Range AN:AN
            #Acelerated Network
            $condtxt += New-ConditionalText false -Range AQ:AQ
            #Retirement
            $condtxt += New-ConditionalText -Range M2:M100 -ConditionalType ContainsText

            $Exc = New-Object System.Collections.Generic.List[System.Object]
            $Exc.Add('Subscription')
            $Exc.Add('Resource Group')
            $Exc.Add('VM Name')
            $Exc.Add('VM Size')
            $Exc.Add('Remaining Quota (vCPUs)')
            $Exc.Add('vCPUs')
            $Exc.Add('vCPUs Per Core')
            $Exc.Add('RAM (GiB)')
            $Exc.Add('Max Remote Storage Disks')
            $Exc.Add('Uncached Disk IOPS Limit')
            $Exc.Add('Uncached Disk Throughput Limit (MB/s)')
            $Exc.Add('Max Network Interfaces')
            $Exc.Add('Retiring Feature')
            $Exc.Add('Retiring Date')
            $Exc.Add('Availability Zone')
            $Exc.Add('Zones Available in the Region')
            $Exc.Add('Capabilities')
            $Exc.Add('Location')
            $Exc.Add('OS Type')
            $Exc.Add('OS Name')
            $Exc.Add('OS Version')
            $Exc.Add('Automatic Update')
            $Exc.Add('Image Reference')
            $Exc.Add('Image Version')
            $Exc.Add('Hybrid Benefit')
            $Exc.Add('Admin Username')
            $Exc.Add('Boot Diagnostics')
            $Exc.Add('Performance Agent')
            $Exc.Add('Azure Monitor')
            $Exc.Add('OS Disk Storage Type')
            $Exc.Add('OS Disk Size (GB)')
            $Exc.Add('Data Disk Storage Type')
            $Exc.Add('Data Disk Size (GB)')
            $Exc.Add('VM generation')
            $Exc.Add('Power State')
            $Exc.Add('Availability Set')
            $Exc.Add('Virtual Network')
            $Exc.Add('Subnet')
            $Exc.Add('DNS Servers')
            $Exc.Add('NSG')
            $Exc.Add('NIC Name')
            $Exc.Add('NIC Type')
            $Exc.Add('Accelerated Networking')
            $Exc.Add('IP Forwarding')
            $Exc.Add('Private IP Address')
            $Exc.Add('Private IP Allocation')
            $Exc.Add('Public IP')
            $Exc.Add('Creation Time')                
            $Exc.Add('VM Extensions')
            $Exc.Add('Avg CPU % (7d)')
            $Exc.Add('Avg Memory % (7d)')
            $Exc.Add('DR Replicated')
            $Exc.Add('DR Target Region')
            $Exc.Add('DR Replication Health')
            $Exc.Add('Est. Monthly Cost (USD)')
            $Exc.Add('Resource U')
            if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }

            $noNumberConversion = @()
            $noNumberConversion += 'OS Version'
            $noNumberConversion += 'Image Version'
            $noNumberConversion += 'Private IP Address'
            $noNumberConversion += 'DNS Servers'

            [PSCustomObject]$SmaResources | 
            ForEach-Object { $_ } | Select-Object $Exc | 
            Export-Excel -Path $File -WorksheetName $SheetName -TableName $TableName -TableStyle $tableStyle -MaxAutoSizeRows 100 -ConditionalText $condtxt -Style $Style -NoNumberConversion $noNumberConversion

        }
}