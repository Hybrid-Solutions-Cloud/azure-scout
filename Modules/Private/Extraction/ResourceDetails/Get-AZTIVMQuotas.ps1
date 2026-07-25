<#
.Synopsis
Module responsible for retrieving Azure VM quotas.

.DESCRIPTION
This module retrieves Azure VM quotas for specific subscriptions and locations.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/1.ExtractionFunctions/ResourceDetails/Get-AZSCVMQuotas.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>
function Get-AZSCVMQuotas {
    Param ($Subscriptions, $Resources)

    # AB#368 - quota lookups are per-location and force a context switch per subscription.
    # Capture up front and restore in the finally below so the caller is not left parked
    # in the last subscription of the loop, or in whichever one an error surfaced from.
    $OriginalContext = Get-AzContext -ErrorAction SilentlyContinue

    try {
    $Quotas = Foreach($Sub in $Subscriptions)
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Getting VM Quota Details: '+$Sub.name)
            # $Resources is a MIXED array: Resource Graph rows carry subscriptionId/Type, but the
            # REST API rows appended alongside them (resource health events, managed identities,
            # advisor scores, reservation recommendations) do not. Under Set-StrictMode -Version
            # Latest a bare $_.subscriptionId on one of those rows aborts the whole run with
            # "The property 'subscriptionId' cannot be found on this object" -- and it aborts the
            # pipeline, so no quota is collected for any subscription. Test for the property
            # before reading it. (AB#5633)
            $VMTypes = @('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets')
            $Locs = @($Resources |
                Where-Object {
                    $null -ne $_ -and
                    $_.PSObject.Properties.Name -contains 'subscriptionId' -and
                    $_.PSObject.Properties.Name -contains 'Type' -and
                    $_.subscriptionId -eq $Sub.id -and
                    $_.Type -in $VMTypes
                } |
                Group-Object -Property Location |
                ForEach-Object { $_.Name })
            if (![string]::IsNullOrEmpty($Locs))
                {
                    Foreach($Loc in $Locs)
                        {
                            # $Loc is a plain string here (one location name); bare strings have
                            # no native .Count and throw under StrictMode — wrap in @().
                            if(@($Loc).count -eq 1)
                                {
                                    Set-AzContext -Subscription $Sub.Id -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -Debug:$false
                                    $Quota = get-azvmusage -location $Loc -Debug:$false
                                    $Quota = $Quota | Where-Object {$_.CurrentValue -ge 1}
                                    $tmp = [PSCustomObject]@{
                                        Location = $Loc
                                        SubId = $Sub.id
                                        Subscription = $Sub.name
                                        Data = $Quota
                                    }
                                    $tmp
                                }
                            else {
                                    Set-AzContext -Subscription $Sub.Id -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -InformationAction SilentlyContinue -Debug:$false
                                    foreach($Loc1 in $Loc)
                                        {
                                            $Quota = get-azvmusage -location $Loc1 -Debug:$false
                                            $Quota = $Quota | Where-Object {$_.CurrentValue -ge 1}
                                            $tmp = [PSCustomObject]@{
                                                Location = $Loc1
                                                SubId = $Sub.id
                                                Subscription = $Sub.name
                                                Data = $Quota
                                            }
                                            $tmp
                                        }
                            }
                        }
                }
        }
    }
    finally {
        # Inline rather than via the shared helper — extraction functions are invoked from
        # thread-job script blocks where sibling private functions are not dot-sourced.
        # PSObject.Properties guards keep this safe under Set-StrictMode.
        $RestoreId = $null
        if ($OriginalContext -and $OriginalContext.PSObject.Properties.Name -contains 'Subscription' -and $OriginalContext.Subscription) {
            if ($OriginalContext.Subscription.PSObject.Properties.Name -contains 'Id') {
                $RestoreId = $OriginalContext.Subscription.Id
            }
        }
        if ($RestoreId) {
            Set-AzContext -SubscriptionId $RestoreId -ErrorAction SilentlyContinue | Out-Null
        }
    }

    $VMQuotas = [PSCustomObject]@{
        'type'          = 'AZSC/VM/Quotas'
        'properties'    = $Quotas
    }

    return $VMQuotas
}