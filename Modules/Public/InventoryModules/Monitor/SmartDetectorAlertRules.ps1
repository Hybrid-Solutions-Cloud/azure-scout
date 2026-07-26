<#
.Synopsis
Inventory for Azure Monitor Smart Detector Alert Rules

.DESCRIPTION
This script consolidates information for all Smart Detector Alert Rules
(microsoft.alertsmanagement/smartdetectoralertrules).
Excel Sheet Name: Smart Detector Alerts

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Monitoring/SmartDetectorAlertRules.ps1

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC).

.CATEGORY Monitor

.NOTES
Version: 1.0.0
First Release Date: February 24, 2026
Authors: AzureScout Contributors

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{
    $smartAlerts = $Resources | Where-Object { $_.TYPE -eq 'microsoft.alertsmanagement/smartdetectoralertrules' }

    if ($smartAlerts) {
        $tmp = foreach ($1 in $smartAlerts) {
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

            # Detector info
            $detectorId   = if ((Get-AZSCSafeProperty -InputObject $data -Path 'detector' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'detector.id' -Enumerate) } else { 'N/A' }
            $detectorName = if ((Get-AZSCSafeProperty -InputObject $data -Path 'detector' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'detector.name' -Enumerate) } else { 'N/A' }

            # Scope (target Application Insights / resource)
            $scopeResourceId = if ((Get-AZSCSafeProperty -InputObject $data -Path 'scope' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'scope' -Enumerate) -join '; ' } else { 'N/A' }

            # Action groups
            $actionGroupStr = 'None'
            if ((Get-AZSCSafeProperty -InputObject $data -Path 'actionGroups' -Enumerate) -and (Get-AZSCSafeProperty -InputObject $data -Path 'actionGroups.groupIds' -Enumerate)) {
                $actionGroupStr = ((Get-AZSCSafeProperty -InputObject $data -Path 'actionGroups.groupIds' -Enumerate) | ForEach-Object { ($_ -split '/')[-1] }) -join '; '
            }

            foreach ($Tag in $Tags) {
                $obj = @{
                    'ID'                  = $1.id;
                    'Subscription'        = $SubscriptionName;
                    'Resource Group'      = $1.RESOURCEGROUP;
                    'Alert Rule Name'     = $1.NAME;
                    'Location'            = $1.LOCATION;
                    'State'               = if ((Get-AZSCSafeProperty -InputObject $data -Path 'state' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'state' -Enumerate) } else { 'N/A' };
                    'Severity'            = if ((Get-AZSCSafeProperty -InputObject $data -Path 'severity' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'severity' -Enumerate) } else { 'N/A' };
                    'Frequency'           = if ((Get-AZSCSafeProperty -InputObject $data -Path 'frequency' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'frequency' -Enumerate) } else { 'N/A' };
                    'Detector ID'         = $detectorId;
                    'Detector Name'       = $detectorName;
                    'Target Scope'        = $scopeResourceId;
                    'Action Groups'       = $actionGroupStr;
                    'Throttling Duration' = if ((Get-AZSCSafeProperty -InputObject $data -Path 'throttlingDuration' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'throttlingDuration' -Enumerate) } else { 'PT0M' };
                    'Resource U'          = $ResUCount;
                    'Tag Name'            = [string]$Tag.Name;
                    'Tag Value'           = [string]$Tag.Value;
                }
                $obj
                if ($ResUCount -eq 1) { $ResUCount = 0 }
            }
        }
        $tmp
    }
}

Else
{
    if ($SmaResources) {
        $TableName = ('SmartAlertTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Left -AutoSize -NumberFormat '0'

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Alert Rule Name')
        $Exc.Add('Location')
        $Exc.Add('State')
        $Exc.Add('Severity')
        $Exc.Add('Frequency')
        $Exc.Add('Detector ID')
        $Exc.Add('Detector Name')
        $Exc.Add('Target Scope')
        $Exc.Add('Action Groups')
        $Exc.Add('Throttling Duration')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File `
            -WorksheetName 'Smart Detector Alerts' `
            -AutoSize -MaxAutoSizeRows 100 `
            -TableName $TableName -TableStyle $TableStyle -Style $Style
    }
}
