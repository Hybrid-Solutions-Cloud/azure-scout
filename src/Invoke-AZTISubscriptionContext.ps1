#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Runs a script block once per subscription and always restores the caller's context.

.DESCRIPTION
Collection loops that walk every subscription have to call Set-AzContext to switch the
active subscription. Without a restore, the caller is left sitting in whichever
subscription happened to be last in the loop — and if the loop throws part way through,
in whichever one it died on. This helper captures the context up front, switches per
subscription, and restores in a finally block so both the happy path and the error path
leave the session where they found it.

Context switching is best-effort: a subscription the identity cannot see is skipped with
a debug message rather than aborting the whole run.

.PARAMETER Subscription
Subscriptions to iterate. Accepts subscription objects (anything exposing .Id) or plain
subscription ID strings.

.PARAMETER Process
Script block invoked once per subscription. The current subscription is passed as the
first argument and is also available as $_.

.EXAMPLE
Invoke-AZSCInSubscriptionContext -Subscription $Subscriptions -Process {
    param($Sub)
    Get-AzResourceProvider -ProviderNamespace 'Microsoft.Security'
}

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Work item: AB#368
#>

function Invoke-AZSCInSubscriptionContext {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Subscription,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Process
    )

    $OriginalContext = $null
    try
        {
            $OriginalContext = Get-AzContext -ErrorAction SilentlyContinue
        }
    catch
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Could not capture the original Azure context: '+$_.Exception.Message)
        }

    try
        {
            Foreach ($Sub in $Subscription)
                {
                    $SubId = if ($Sub -is [string]) { $Sub } elseif ($Sub -and $Sub.PSObject.Properties.Name -contains 'Id') { $Sub.Id } else { $null }
                    # Set-AzContext without -Tenant makes Az.Accounts resolve the
                    # subscription against every cached tenant. That turns a
                    # tenant-scoped Scout run into unrelated authentication attempts.
                    # Prefer the subscription's tenant, then preserve the caller's
                    # current tenant for string-only subscription inputs.
                    $SubTenant = if ($Sub -isnot [string] -and $Sub -and $Sub.PSObject.Properties.Name -contains 'TenantId') {
                        $Sub.TenantId
                    }
                    elseif ($OriginalContext -and $OriginalContext.PSObject.Properties.Name -contains 'Tenant' -and $OriginalContext.Tenant -and $OriginalContext.Tenant.PSObject.Properties.Name -contains 'Id') {
                        $OriginalContext.Tenant.Id
                    }
                    else {
                        $null
                    }

                    if (-not $SubId)
                        {
                            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Skipping a subscription entry with no resolvable Id.')
                            continue
                        }

                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Switching context to subscription: '+$SubId)
                    $contextParams = @{ Subscription = $SubId; ErrorAction = 'Stop' }
                    if ($SubTenant) { $contextParams['Tenant'] = $SubTenant }

                    try {
                        $SelectedContext = Set-AzContext @contextParams
                        if (-not $SelectedContext) {
                            throw "Set-AzContext returned no context for subscription '$SubId'."
                        }
                        if ($SelectedContext.PSObject.Properties.Name -contains 'Subscription' -and
                            $SelectedContext.Subscription -and
                            $SelectedContext.Subscription.PSObject.Properties.Name -contains 'Id' -and
                            $SelectedContext.Subscription.Id -and
                            [string]$SelectedContext.Subscription.Id -ne [string]$SubId) {
                            throw "Set-AzContext selected subscription '$($SelectedContext.Subscription.Id)' instead of '$SubId'."
                        }
                    }
                    catch {
                        Write-Warning "Skipping subscription '$SubId' because its Azure context could not be selected: $($_.Exception.Message)"
                        continue
                    }

                    & $Process $Sub
                }
        }
    finally
        {
            Restore-AZSCContext -Context $OriginalContext
        }
}

<#
.Synopsis
Restores a previously captured Azure context.

.DESCRIPTION
Separated from Invoke-AZSCInSubscriptionContext so loops that cannot be expressed as a
single script block can still restore correctly from their own finally block.

.PARAMETER Context
The context object captured by Get-AzContext before the loop started. A null context is
a no-op, so callers do not have to guard the call.
#>
function Restore-AZSCContext {
    [CmdletBinding()]
    Param($Context)

    # Property presence is tested via PSObject.Properties rather than a bare
    # $Context.Subscription, which throws under Set-StrictMode when the property is absent.
    if (-not $Context) { return }
    if ($Context.PSObject.Properties.Name -notcontains 'Subscription') { return }
    if (-not $Context.Subscription) { return }
    if ($Context.Subscription.PSObject.Properties.Name -notcontains 'Id') { return }
    if (-not $Context.Subscription.Id) { return }

    try
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Restoring original subscription context: '+$Context.Subscription.Id)
            $restoreParams = @{ Subscription = $Context.Subscription.Id; ErrorAction = 'SilentlyContinue' }
            if ($Context.PSObject.Properties.Name -contains 'Tenant' -and $Context.Tenant -and $Context.Tenant.PSObject.Properties.Name -contains 'Id' -and $Context.Tenant.Id) {
                $restoreParams['Tenant'] = $Context.Tenant.Id
            }
            Set-AzContext @restoreParams | Out-Null
        }
    catch
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Could not restore the original Azure context: '+$_.Exception.Message)
        }
}
