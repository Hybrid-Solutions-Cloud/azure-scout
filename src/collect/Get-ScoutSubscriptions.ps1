#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Module responsible for retrieving Azure subscriptions.

.DESCRIPTION
This module retrieves Azure subscriptions for a given tenant or specific subscription IDs.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/src/collect/Get-ScoutSubscriptions.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>
function Get-AZSCSubscriptions {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Public function name is load-bearing across tests and the legacy extraction path; renaming is an API break out of scope for a lint-only pass.')]
    Param ($TenantID,$SubscriptionID,$PlatOS)
    if($PlatOS -eq 'Azure CloudShell')
        {
            $Subscriptions = Get-AzSubscription -WarningAction SilentlyContinue -Debug:$false

            if ($SubscriptionID)
                {
                    if(@($SubscriptionID).count -gt 1)
                        {
                            $Subscriptions = $Subscriptions | Where-Object { $_.ID -in $SubscriptionID }
                        }
                    else
                        {
                            $Subscriptions = $Subscriptions | Where-Object { $_.ID -eq $SubscriptionID }
                        }
                }
        }
    else
        {
            Write-Host "Extracting Subscriptions from Tenant $TenantID"
            try
                {
                    $Subscriptions = Get-AzSubscription -TenantId $TenantID -WarningAction SilentlyContinue -Debug:$false
                }
            catch
                {
                    Write-Host ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+ " Error: $_")
                    return
                }

            if ($SubscriptionID)
                {
                    if(@($SubscriptionID).count -gt 1)
                        {
                            $Subscriptions = $Subscriptions | Where-Object { $_.ID -in $SubscriptionID }
                        }
                    else
                        {
                            $Subscriptions = $Subscriptions | Where-Object { $_.ID -eq $SubscriptionID }
                        }
                }
        }

    # Disabled subscriptions can still be returned by Get-AzSubscription and Resource Graph, but
    # their resource providers cannot be queried. Treating them as runnable scope creates a false
    # Partial inventory (for example Defender Pricing appears unavailable) and wastes every
    # subscription-scoped call. Preserve test/legacy objects that do not expose State, while
    # excluding only an explicitly non-Enabled Azure subscription.
    $Subscriptions = @($Subscriptions | Where-Object {
            $stateProperty = $_.PSObject.Properties['State']
            $null -eq $stateProperty -or [string]$stateProperty.Value -ieq 'Enabled'
        })

    return $Subscriptions
}
