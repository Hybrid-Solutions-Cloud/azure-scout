<#
.Synopsis
Operational Deep-Data for Azure Virtual Machines

.DESCRIPTION
This script provides deep operational data for Azure VMs including backup status,
advisor recommendations count, update compliance, and lifecycle tag extraction.
Supplement to VirtualMachine.ps1 — does not replace it.
Excel Sheet Name: VM Operational Data

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Compute/VMOperationalData.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
First Release Date: February 24, 2026
Authors: AzureScout Contributors

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{
    $vms = $Resources | Where-Object { $_.TYPE -eq 'microsoft.compute/virtualmachines' }

    if ($vms) {

        # Pre-load backup items from Resources (ARG type for protected items)
        $backupItems = $Resources | Where-Object {
            $_.TYPE -like 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
        }

        # Pre-load Advisor recommendations if present in Resources
        $advisorRecs = $Resources | Where-Object { $_.TYPE -eq 'microsoft.advisor/recommendations' }

        $tmp = foreach ($1 in $vms) {
            $ResUCount = 1
            # AB#5671: empty $sub1 (subscription out of scope) is not $null, so `.Name` throws;
            # and an untagged VM's Resource Graph row OMITS `tags`, so both `$1.tags` and
            # `$null.psobject.properties` throw. The '0' sentinel only ever existed to make the
            # tag loop run once for an untagged resource -- but `'0'.Name` throws too, so an empty
            # tag object replaces it, emitting the identical [string]-cast empty Tag Name/Value.
            $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
            $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { '' }
            $data = $1.PROPERTIES
            $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
            $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
            $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }

            # ---- Extensions summary ----
            # An extension id shorter than nine segments makes the fixed [8] index return $null
            # rather than throw once it is guarded on segment count.
            $vmExts = $Resources | Where-Object {
                $_.TYPE -eq 'microsoft.compute/virtualmachines/extensions' -and
                (Get-AZSCIdSegment -Id $_.id -Index 8) -eq $1.NAME
            }
            $extCount    = if ($vmExts)  { @($vmExts).Count }                                                       else { 0 }
            $extNames    = if ($vmExts)  { (@($vmExts) | ForEach-Object { Get-AZSCSafeProperty -InputObject $_ -Path 'PROPERTIES.type' }) -join ', ' } else { 'None' }
            # `$vmExts.PROPERTIES.publisher` is member enumeration through a collection whose
            # elements may omit `publisher` entirely -- an absent key on EVERY element makes the
            # enumeration yield nothing, which is what StrictMode reports as the missing property.
            $extPublishers = @(Get-AZSCSafeProperty -InputObject $vmExts -Path 'PROPERTIES.publisher' -Enumerate)
            $extTypes      = @(Get-AZSCSafeProperty -InputObject $vmExts -Path 'PROPERTIES.type' -Enumerate)
            $hasAMA      = if ($vmExts -and ($extPublishers -contains 'Microsoft.Azure.Monitor'))    { 'Yes' } else { 'No' }
            $hasDefender = if ($vmExts -and ($extTypes -like '*MDE*' -or $extPublishers -like '*MicrosoftDefender*')) { 'Yes' } else { 'No' }

            # ---- Boot diagnostics ----
            # `diagnosticsProfile` is ABSENT (not null) on any VM created without boot diagnostics,
            # which is the default -- so this was the very first line to throw here (AB#5671).
            $bootDiagEnabled = Get-AZSCSafeProperty -InputObject $data -Path 'diagnosticsProfile.bootDiagnostics.enabled'
            $bootDiagUri     = Get-AZSCSafeProperty -InputObject $data -Path 'diagnosticsProfile.bootDiagnostics.storageUri'
            $PowerState  = Get-AZSCSafeProperty -InputObject $data -Path 'extended.instanceView.powerState.displayStatus'
            $bootDiag    = if ($bootDiagEnabled -eq $true) { 'Enabled' } else { 'Disabled' }
            $bootDiagSA  = if ($bootDiagUri) { $bootDiagUri } else { 'Managed' }

            # ---- Backup status (cross-ref from pre-loaded backup items) ----
            $backupItem     = $backupItems | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'PROPERTIES.sourceResourceId') -eq $1.id }
            $backupEnabled  = if ($backupItem)  { 'Yes' }                                   else { 'No' }
            $lastBackupTime = if ($backupItem)  { Get-AZSCSafeProperty -InputObject $backupItem -Path 'PROPERTIES.lastBackupTime' -Enumerate }   else { 'N/A' }
            $backupVault    = if ($backupItem)  { Get-AZSCIdSegment -Id (Get-AZSCCollectedValue -InputObject $backupItem -Name 'id') -Index 8 } else { 'N/A' }
            $backupPolicy   = if ($backupItem)  { Get-AZSCSafeProperty -InputObject $backupItem -Path 'PROPERTIES.policyName' -Enumerate }       else { 'N/A' }

            # ---- Advisor recommendations (cross-ref) ----
            $vmAdvisor     = $advisorRecs | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'PROPERTIES.resourceMetadata.resourceId') -eq $1.id }
            $advisorCount  = if ($vmAdvisor)  { @($vmAdvisor).Count }                                          else { 0 }
            $costAdvisor   = if ($vmAdvisor)  { @($vmAdvisor | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'PROPERTIES.category') -eq 'Cost' }).Count }        else { 0 }
            $secAdvisor    = if ($vmAdvisor)  { @($vmAdvisor | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'PROPERTIES.category') -eq 'Security' }).Count }    else { 0 }

            # ---- Update compliance via REST (optional, try/catch) ----
            $pendingCritical  = 'N/A'
            $pendingImportant = 'N/A'
            $lastPatchTime    = 'N/A'
            try {
                $assessUri = "/subscriptions/$($1.subscriptionId)/resourceGroups/$($1.RESOURCEGROUP)/providers/Microsoft.Compute/virtualMachines/$($1.NAME)/assessPatches?api-version=2023-03-01"
                $assessResp = Invoke-AzRestMethod -Path $assessUri -Method POST -ErrorAction SilentlyContinue
                if ($assessResp.StatusCode -in 200, 202) {
                    $assessData    = $assessResp.Content | ConvertFrom-Json
                    $pendingCritical  = if ($assessData.criticalAndSecurityPatchCount)  { $assessData.criticalAndSecurityPatchCount }  else { 0 }
                    $pendingImportant = if ($assessData.otherPatchCount)                 { $assessData.otherPatchCount }                 else { 0 }
                    $lastPatchTime    = if ($assessData.startDateTime)                   { ([datetime]$assessData.startDateTime).ToString('yyyy-MM-dd') } else { 'N/A' }
                }
            } catch {}

            # ---- Lifecycle tags ----
            # Reading a specific tag off a resource that has no `tags` block at all, or has tags but
            # not this one, throws under StrictMode. Get-AZSCSafeProperty's lookup is already
            # case-insensitive, so the original Environment/environment pairs collapse to one read
            # each -- the same value, since the fall-back arm could only ever match what the first
            # arm already would have.
            $tagEnv        = Get-AZSCSafeProperty -InputObject $RowTags -Path 'Environment'
            $tagOwner      = Get-AZSCSafeProperty -InputObject $RowTags -Path 'Owner'
            $tagCostCenter = Get-AZSCSafeProperty -InputObject $RowTags -Path 'CostCenter'
            $tagExpiry     = Get-AZSCSafeProperty -InputObject $RowTags -Path 'ExpirationDate'
            if (-not $tagExpiry) { $tagExpiry = Get-AZSCSafeProperty -InputObject $RowTags -Path 'Expiration' }
            if (-not $tagEnv)        { $tagEnv        = 'N/A' }
            if (-not $tagOwner)      { $tagOwner      = 'N/A' }
            if (-not $tagCostCenter) { $tagCostCenter = 'N/A' }
            if (-not $tagExpiry)     { $tagExpiry     = 'N/A' }

            foreach ($Tag in $Tags) {
                $obj = @{
                    'ID'                        = $1.id;
                    'Subscription'              = $SubscriptionName;
                    'Resource Group'            = $1.RESOURCEGROUP;
                    'VM Name'                   = $1.NAME;
                    'Location'                  = $1.LOCATION;
                    # `extended` comes from the instance-view expansion and is absent on a plain
                    # Resource Graph row, so this whole chain throws without the expansion.
                    'Power State'               = if ($PowerState) { $PowerState } else { 'N/A' };
                    'Extensions Count'          = $extCount;
                    'Extensions Installed'      = $extNames;
                    'Azure Monitor Agent'       = $hasAMA;
                    'Defender Extension'        = $hasDefender;
                    'Boot Diagnostics'          = $bootDiag;
                    'Boot Diag Storage'         = $bootDiagSA;
                    'Backup Enabled'            = $backupEnabled;
                    'Last Backup Time'          = $lastBackupTime;
                    'Backup Vault'              = $backupVault;
                    'Backup Policy'             = $backupPolicy;
                    'Advisor Recs Total'        = $advisorCount;
                    'Advisor Cost Recs'         = $costAdvisor;
                    'Advisor Security Recs'     = $secAdvisor;
                    'Pending Critical Patches'  = $pendingCritical;
                    'Pending Other Patches'     = $pendingImportant;
                    'Last Patch Assessment'     = $lastPatchTime;
                    'Tag: Environment'          = $tagEnv;
                    'Tag: Owner'                = $tagOwner;
                    'Tag: Cost Center'          = $tagCostCenter;
                    'Tag: Expiration Date'      = $tagExpiry;
                    'Resource U'                = $ResUCount;
                    'Tag Name'                  = [string]$Tag.Name;
                    'Tag Value'                 = [string]$Tag.Value;
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
        $TableName = ('VMOperDataTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Left -AutoSize -NumberFormat '0'

        $Cond  = New-ConditionalText -ConditionalType ContainsText 'No'       -ConditionalTextColor ([System.Drawing.Color]::FromArgb(255,165,0))  -BackgroundColor ([System.Drawing.Color]::White)
        $Cond2 = New-ConditionalText -ConditionalType ContainsText 'Disabled' -ConditionalTextColor ([System.Drawing.Color]::FromArgb(255,0,0))    -BackgroundColor ([System.Drawing.Color]::White)
        $Cond3 = New-ConditionalText -ConditionalType ContainsText 'Yes'      -ConditionalTextColor ([System.Drawing.Color]::FromArgb(0,176,80))   -BackgroundColor ([System.Drawing.Color]::White)

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('VM Name')
        $Exc.Add('Location')
        $Exc.Add('Power State')
        $Exc.Add('Extensions Count')
        $Exc.Add('Extensions Installed')
        $Exc.Add('Azure Monitor Agent')
        $Exc.Add('Defender Extension')
        $Exc.Add('Boot Diagnostics')
        $Exc.Add('Boot Diag Storage')
        $Exc.Add('Backup Enabled')
        $Exc.Add('Last Backup Time')
        $Exc.Add('Backup Vault')
        $Exc.Add('Backup Policy')
        $Exc.Add('Advisor Recs Total')
        $Exc.Add('Advisor Cost Recs')
        $Exc.Add('Advisor Security Recs')
        $Exc.Add('Pending Critical Patches')
        $Exc.Add('Pending Other Patches')
        $Exc.Add('Last Patch Assessment')
        $Exc.Add('Tag: Environment')
        $Exc.Add('Tag: Owner')
        $Exc.Add('Tag: Cost Center')
        $Exc.Add('Tag: Expiration Date')
        $Exc.Add('Resource U')
        if ($InTag) { $Exc.Add('Tag Name'); $Exc.Add('Tag Value') }

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File `
            -WorksheetName 'VM Operational Data' `
            -AutoSize -MaxAutoSizeRows 100 `
            -ConditionalText $Cond, $Cond2, $Cond3 `
            -TableName $TableName -TableStyle $TableStyle -Style $Style
    }
}
