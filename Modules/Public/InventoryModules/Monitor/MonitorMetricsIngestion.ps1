<#
.Synopsis
Inventory for Azure Monitor Metrics Ingestion Endpoints

.DESCRIPTION
This script inventories Data Collection Endpoints and Log Analytics Workspace
capacity/retention settings that govern metrics and log ingestion.
Excel Sheet Name: Monitor Metrics Ingestion

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Monitoring/MonitorMetricsIngestion.ps1

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
    $workspaces = $Resources | Where-Object { $_.TYPE -eq 'microsoft.operationalinsights/workspaces' }

    if ($workspaces) {
        $tmp = foreach ($1 in $workspaces) {
            $ResUCount = 1
            # An EMPTY $sub1 is not $null -- the match is empty for any resource whose subscription
            # is outside the requested scope -- and reading .Name off an empty collection throws
            # under StrictMode (AB#5671). Resolved once here, as VirtualMachine.ps1 already does.
            $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
            $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { '' }
            $data = $1.PROPERTIES
            # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
            # than carrying an empty object, so the raw read throws under StrictMode -- and so
            # does psobject.properties on a $null. The historic '0' sentinel existed only to make
            # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
            # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
            $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
            $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
            $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }

            # SKU details
            $skuName        = if ((Get-AZSCSafeProperty -InputObject $data -Path 'sku.name' -Enumerate))                           { (Get-AZSCSafeProperty -InputObject $data -Path 'sku.name' -Enumerate) }                           else { 'N/A' }
            $capResLevel    = if ((Get-AZSCSafeProperty -InputObject $data -Path 'sku.capacityReservationLevel' -Enumerate))       { (Get-AZSCSafeProperty -InputObject $data -Path 'sku.capacityReservationLevel' -Enumerate) }       else { 'N/A' }

            # Retention
            $retentionDays  = if ((Get-AZSCSafeProperty -InputObject $data -Path 'retentionInDays' -Enumerate))                    { (Get-AZSCSafeProperty -InputObject $data -Path 'retentionInDays' -Enumerate) }                    else { 'N/A' }

            # Daily cap
            $dailyQuotaGb   = if ((Get-AZSCSafeProperty -InputObject $data -Path 'workspaceCapping.dailyQuotaGb' -Enumerate) -and (Get-AZSCSafeProperty -InputObject $data -Path 'workspaceCapping.dailyQuotaGb' -Enumerate) -ne -1) {
                                  (Get-AZSCSafeProperty -InputObject $data -Path 'workspaceCapping.dailyQuotaGb' -Enumerate)
                               } else { 'Unlimited' }
            $dataIngestionStatus = if ((Get-AZSCSafeProperty -InputObject $data -Path 'workspaceCapping.dataIngestionStatus' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'workspaceCapping.dataIngestionStatus' -Enumerate) } else { 'N/A' }

            # Customer-managed key
            $cmkEnabled     = if ((Get-AZSCSafeProperty -InputObject $data -Path 'features.enableDataExport' -Enumerate) -eq $true) { 'Yes' } else { 'No' }

            # Public network access
            $publicIngestion = if ((Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccessForIngestion' -Enumerate))   { (Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccessForIngestion' -Enumerate) }   else { 'N/A' }
            $publicQuery     = if ((Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccessForQuery' -Enumerate))       { (Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccessForQuery' -Enumerate) }       else { 'N/A' }

            foreach ($Tag in $Tags) {
                $obj = @{
                    'ID'                          = $1.id;
                    'Subscription'                = $SubscriptionName;
                    'Resource Group'              = $1.RESOURCEGROUP;
                    'Workspace Name'              = $1.NAME;
                    'Location'                    = $1.LOCATION;
                    'SKU'                         = $skuName;
                    'Capacity Reservation (GB/d)' = $capResLevel;
                    'Retention (days)'            = $retentionDays;
                    'Daily Cap (GB)'              = $dailyQuotaGb;
                    'Daily Cap Status'            = $dataIngestionStatus;
                    'Public Ingestion'            = $publicIngestion;
                    'Public Query'                = $publicQuery;
                    'Provisioning State'          = if ((Get-AZSCSafeProperty -InputObject $data -Path 'provisioningState' -Enumerate)) { (Get-AZSCSafeProperty -InputObject $data -Path 'provisioningState' -Enumerate) } else { 'N/A' };
                    'Resource U'                  = $ResUCount;
                    'Tag Name'                    = [string]$Tag.Name;
                    'Tag Value'                   = [string]$Tag.Value;
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
        $TableName = ('MonitorMetricsIngTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Left -AutoSize -NumberFormat '0'

        $Cond = New-ConditionalText -ConditionalType ContainsText  'Unlimited' -ConditionalTextColor ([System.Drawing.Color]::FromArgb(0,176,240)) -BackgroundColor ([System.Drawing.Color]::White)
        $Cond2 = New-ConditionalText -ConditionalType ContainsText 'CapReached' -ConditionalTextColor ([System.Drawing.Color]::White) -BackgroundColor ([System.Drawing.Color]::FromArgb(255,0,0))
        $Cond3 = New-ConditionalText -ConditionalType ContainsText 'PerNodeNotAllowed' -ConditionalTextColor ([System.Drawing.Color]::White) -BackgroundColor ([System.Drawing.Color]::FromArgb(255,165,0))

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Workspace Name')
        $Exc.Add('Location')
        $Exc.Add('SKU')
        $Exc.Add('Capacity Reservation (GB/d)')
        $Exc.Add('Retention (days)')
        $Exc.Add('Daily Cap (GB)')
        $Exc.Add('Daily Cap Status')
        $Exc.Add('Public Ingestion')
        $Exc.Add('Public Query')
        $Exc.Add('Provisioning State')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File `
            -WorksheetName 'Monitor Metrics Ingestion' `
            -AutoSize -MaxAutoSizeRows 100 `
            -ConditionalText $Cond, $Cond2, $Cond3 `
            -TableName $TableName -TableStyle $TableStyle -Style $Style
    }
}
