<#
.Synopsis
Inventory for Azure Network Watchers

.DESCRIPTION
This script consolidates information for all Azure Network Watcher instances.
Captures flow logs, connection monitors, packet captures, and diagnostic capabilities.
Excel Sheet Name: Network Watchers

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Network/NetworkWatchers.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
First Release Date: February 24, 2026
Authors: AzureScout Contributors

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task ,$File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{
    <######### Insert the resource extraction here ########>

        $networkWatchers = $Resources | Where-Object {$_.TYPE -eq 'microsoft.network/networkwatchers'}

    <######### Insert the resource Process here ########>

    if($networkWatchers)
        {
            $tmp = foreach ($1 in $networkWatchers) {
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
                # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                # than carrying an empty object, so the raw read throws under StrictMode -- and so
                # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }

                # Get provisioning state
                $provisioningState = if ((Get-AZSCSafeProperty -InputObject $data -Path 'provisioningState' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'provisioningState' -Enumerate) } else { 'Unknown' }

                # Get associated flow logs
                $flowLogs = $Resources | Where-Object {
                    $_.TYPE -eq 'Microsoft.Network/networkWatchers/flowLogs' -and
                    $_.id -like "$($1.id)/*"
                }
                $flowLogCount = @($flowLogs).Count
                $flowLogNames = @()
                if ($flowLogs) {
                    foreach ($fl in $flowLogs) {
                        $flowLogNames += $fl.NAME
                    }
                }
                $flowLogStr = if ($flowLogNames.Count -gt 0) { $flowLogNames -join ', ' } else { 'None' }

                # Get connection monitors
                $connMonitors = $Resources | Where-Object {
                    $_.TYPE -eq 'Microsoft.Network/networkWatchers/connectionMonitors' -and
                    $_.id -like "$($1.id)/*"
                }
                $connMonitorCount = @($connMonitors).Count
                $connMonitorNames = @()
                if ($connMonitors) {
                    foreach ($cm in $connMonitors) {
                        $connMonitorNames += $cm.NAME
                    }
                }
                $connMonitorStr = if ($connMonitorNames.Count -gt 0) { $connMonitorNames -join ', ' } else { 'None' }

                # Check for packet captures (typically short-lived, might be 0)
                $packetCaptures = $Resources | Where-Object {
                    $_.TYPE -eq 'Microsoft.Network/networkWatchers/packetCaptures' -and
                    $_.id -like "$($1.id)/*"
                }
                $packetCaptureCount = @($packetCaptures).Count

                foreach ($Tag in $Tags) {
                    $obj = @{
                        'ID'                        = $1.id;
                        'Subscription'              = $SubscriptionName;
                        'Resource Group'            = $1.RESOURCEGROUP;
                        'Network Watcher Name'      = $1.NAME;
                        'Location'                  = $1.LOCATION;
                        'Provisioning State'        = $provisioningState;
                        'Flow Logs Count'           = $flowLogCount;
                        'Flow Logs'                 = $flowLogStr;
                        'Connection Monitors Count' = $connMonitorCount;
                        'Connection Monitors'       = $connMonitorStr;
                        'Packet Captures Count'     = $packetCaptureCount;
                        'Capabilities'              = 'IP Flow Verify, Next Hop, VPN Troubleshoot, NSG Diagnostics, Topology, Connection Troubleshoot';
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

Else
{
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if($SmaResources)
    {

        $TableName = ('NetworkWatchersTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'
        $StyleExt = New-ExcelStyle -HorizontalAlignment Left -Range H:H,J:J,L:L -Width 40 -WrapText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Network Watcher Name')
        $Exc.Add('Location')
        $Exc.Add('Provisioning State')
        $Exc.Add('Flow Logs Count')
        $Exc.Add('Flow Logs')
        $Exc.Add('Connection Monitors Count')
        $Exc.Add('Connection Monitors')
        $Exc.Add('Packet Captures Count')
        $Exc.Add('Capabilities')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value')
            }
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'Network Watchers' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style, $StyleExt

    }
}
