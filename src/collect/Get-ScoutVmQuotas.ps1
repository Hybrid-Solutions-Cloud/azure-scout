#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Per-subscription, per-location VM/VMSS quota usage -- ported into src/collect from
    Modules/Private/Extraction/ResourceDetails/Get-AZTIVMQuotas.ps1 (AB#5639/5646).

.DESCRIPTION
    Quota usage (`Get-AzVMUsage`) is an ARM data-plane call scoped to a subscription context
    and a region -- it has no Resource Graph table, so it cannot be folded into
    `Get-ScoutRawInventory`'s ARG queries no matter how the raw row set is shaped. The type
    map this task derived from the 174 legacy collectors (`scripts/
    Get-CollectorResourceTypeMap.ps1`) surfaces exactly this: three collectors
    (AKS, VirtualMachine, VirtualMachineScaleSet) filter `$Resources` for a synthetic
    `'AZSC/VM/Quotas'`-typed row that only this call can produce -- confirming the legacy
    engine already depends on this exact REST-API-backed dataset, not an ARG one.

    Only queries the (subscription, location) pairs that actually HAVE a VM or VMSS in
    `$Resources` -- the same targeted-location strategy the legacy function uses, avoiding a
    quota lookup for every Azure region regardless of where the tenant actually deploys.

.PARAMETER Subscriptions
    Subscription objects with `.id` (and ideally `.name`).

.PARAMETER Resources
    The mixed resource row set (Resource Graph rows, optionally alongside REST-API rows from
    `Get-ScoutApiResources` that do not carry `subscriptionId`/`Type`) to derive
    (subscription, location) pairs from. Every row is guarded with a `PSObject.Properties`
    check before either property is read, so a mixed array never aborts the whole
    call (AB#5633's exact defect class, carried forward as a fix rather than reintroduced).

.OUTPUTS
    `[pscustomobject]` with `type = 'AZSC/VM/Quotas'` and `properties` holding one entry per
    (subscription, location) pair queried: `Location`, `SubId`, `Subscription`, `Data` (the
    `Get-AzVMUsage` result, filtered to `CurrentValue -ge 1`). The literal `type` string is
    preserved EXACTLY as the legacy function emits it -- the three collectors above match on
    it case-insensitively but it must still be present for that match to succeed at all.

.NOTES
    Tracks ADO AB#5639 (Task AB#5646, Epic AB#5638).

    Restores the caller's original Az context in a `finally` block, exactly like the legacy
    function -- `Set-AzContext` is called once per subscription to run the quota lookup in
    that subscription's scope, and a caller left parked in the last-iterated subscription
    (or wherever an error surfaced from) is a real defect the legacy function already fixed
    once (AB#368); this keeps that fix.
#>
function Get-ScoutVmQuotas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Subscriptions,
        [Parameter(Mandatory)] [AllowNull()] [object[]] $Resources
    )

    $originalContext = Get-AzContext -ErrorAction SilentlyContinue
    $vmTypes = @('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets')

    $quotas = try {
        foreach ($sub in $Subscriptions) {
            $locations = @(
                @($Resources) | Where-Object {
                    $null -ne $_ -and
                    $_.PSObject.Properties.Name -contains 'subscriptionId' -and
                    $_.PSObject.Properties.Name -contains 'type' -and
                    $_.subscriptionId -eq $sub.id -and
                    ([string] $_.type).ToLowerInvariant() -in $vmTypes
                } | Group-Object -Property location | ForEach-Object { $_.Name } | Where-Object { $_ }
            )
            if ($locations.Count -eq 0) { continue }

            $contextParams = @{ Subscription = $sub.id; ErrorAction = 'SilentlyContinue'; WarningAction = 'SilentlyContinue' }
            if ($sub.PSObject.Properties.Name -contains 'TenantId' -and $sub.TenantId) {
                $contextParams['Tenant'] = $sub.TenantId
            }
            elseif ($originalContext -and $originalContext.PSObject.Properties.Name -contains 'Tenant' -and $originalContext.Tenant -and $originalContext.Tenant.PSObject.Properties.Name -contains 'Id' -and $originalContext.Tenant.Id) {
                $contextParams['Tenant'] = $originalContext.Tenant.Id
            }
            Set-AzContext @contextParams | Out-Null
            foreach ($loc in $locations) {
                try {
                    # NOT wrapped in @(): the legacy function assigned the filtered pipeline
                    # unwrapped, so a single matching quota row arrives as a scalar and a
                    # region with none arrives as $null. Every consumer reads it as
                    # `$Quota.Data | Where-Object ...`, which is shape-agnostic, but the
                    # emitted object is kept byte-identical to v1's rather than "improved"
                    # into a shape no consumer asked for. (AB#5648)
                    $usage = Get-AzVMUsage -Location $loc -ErrorAction Stop | Where-Object { $_.CurrentValue -ge 1 }
                }
                catch {
                    Write-Warning "Get-ScoutVmQuotas: quota lookup failed for subscription '$($sub.id)' / location '$loc' -- skipping: $($_.Exception.Message)"
                    continue
                }
                [pscustomobject]@{
                    Location     = $loc
                    SubId        = $sub.id
                    Subscription = if ($sub.PSObject.Properties['name']) { $sub.name } else { $sub.id }
                    Data         = $usage
                }
            }
        }
    }
    finally {
        $restoreId = $null
        if ($originalContext -and $originalContext.PSObject.Properties.Name -contains 'Subscription' -and $originalContext.Subscription) {
            if ($originalContext.Subscription.PSObject.Properties.Name -contains 'Id') { $restoreId = $originalContext.Subscription.Id }
        }
        if ($restoreId) {
            $restoreParams = @{ Subscription = $restoreId; ErrorAction = 'SilentlyContinue' }
            if ($originalContext.PSObject.Properties.Name -contains 'Tenant' -and $originalContext.Tenant -and $originalContext.Tenant.PSObject.Properties.Name -contains 'Id' -and $originalContext.Tenant.Id) {
                $restoreParams['Tenant'] = $originalContext.Tenant.Id
            }
            Set-AzContext @restoreParams | Out-Null
        }
    }

    return [pscustomobject]@{
        type       = 'AZSC/VM/Quotas'
        properties = @($quotas)
    }
}
