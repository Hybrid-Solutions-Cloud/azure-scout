#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Pull Azure Advisor recommendations per enabled subscription into collect.advisor.

.DESCRIPTION
    Two sources, in preference order.

    When the caller hands over rows the inventory pass already collected (`-FromInventory`),
    they are shaped into the contract below and no Azure call is made. This is the collect-once
    path: inventory reads Advisor from the `advisorresources` Resource Graph table on every run,
    so in a combined run the per-subscription `Get-AzAdvisorRecommendation` sweep re-fetched data
    already sitting in memory, through a slower API (AB#6777, audit section 10 defect 4).

    Otherwise it falls back to the per-subscription cmdlet, which is still the only source for
    an assessment-only run.

.PARAMETER Collect
    The collect object to attach `advisor` to.

.PARAMETER FromInventory
    `advisorresources` rows from an inventory pass -- `$ExtractionData.Advisories`. Rows carry
    the full ARM `properties` bag; this function projects the same seven fields the cmdlet path
    produces, because the rule files query them by name (`$.advisor[?(@.Category == 'Cost')]`)
    and a shape difference between the two paths would make findings depend on how the run was
    started.

.NOTES
    Read-only. Tracks ADO Story AB#5040; collect-once rework AB#6777 (Story AB#6773).
#>
function Import-AdvisorScores {
    param(
        $Collect,
        [object[]] $FromInventory
    )

    # ---- collect-once path ----
    if ($null -ne $FromInventory -and @($FromInventory).Count -gt 0) {
        $shaped = @(
            foreach ($row in @($FromInventory)) {
                if ($null -eq $row) { continue }

                # Every read below is guarded. These are raw Resource Graph rows: `properties`
                # is whatever ARM indexed, `shortDescription` is absent on some recommendation
                # types, and a chained dot into a missing key throws under StrictMode rather
                # than returning $null.
                $props = if ($row.PSObject.Properties['properties']) { $row.properties } else { $null }
                if ($null -eq $props) { continue }

                $short = if ($props.PSObject.Properties['shortDescription']) { $props.shortDescription } else { $null }

                [pscustomobject]@{
                    Category                = if ($props.PSObject.Properties['category'])      { [string] $props.category }      else { $null }
                    Impact                  = if ($props.PSObject.Properties['impact'])        { [string] $props.impact }        else { $null }
                    ImpactedField           = if ($props.PSObject.Properties['impactedField']) { [string] $props.impactedField } else { $null }
                    ImpactedValue           = if ($props.PSObject.Properties['impactedValue']) { [string] $props.impactedValue } else { $null }
                    Subscription            = if ($row.PSObject.Properties['subscriptionId'])  { [string] $row.subscriptionId }  else { $null }
                    ShortDescriptionProblem = if ($short -and $short.PSObject.Properties['problem'])  { [string] $short.problem }  else { $null }
                    ShortDescriptionSolution = if ($short -and $short.PSObject.Properties['solution']) { [string] $short.solution } else { $null }
                }
            }
        )

        Write-Verbose "Import-AdvisorScores: shaped $($shaped.Count) advisor rows from the inventory pass -- no Azure call made (AB#6777)."
        $Collect | Add-Member -NotePropertyName advisor -NotePropertyValue $shaped -Force
        return $Collect
    }

    # ---- fallback: per-subscription cmdlet sweep ----
    $context = Get-AzContext -ErrorAction SilentlyContinue
    $tenantId = if ($context -and $context.Tenant -and $context.Tenant.Id) { $context.Tenant.Id } else { $null }

    # AB#6777. The loop below calls Set-AzContext per subscription and used to leave the caller
    # on whichever one happened to be last -- so anything running after an assessment in the
    # same session silently inherited a different subscription. try/finally, and the restore is
    # written inline rather than through a helper because this file is dot-sourced standalone.
    $originalSubscriptionId = $null
    if ($context -and $context.PSObject.Properties.Name -contains 'Subscription' -and $context.Subscription) {
        if ($context.Subscription.PSObject.Properties.Name -contains 'Id') {
            $originalSubscriptionId = $context.Subscription.Id
        }
    }

    try {
        $subs = (Get-AzSubscription -TenantId $tenantId | Where-Object State -eq 'Enabled')
        $recs = foreach ($s in $subs) {
            $switchParams = @{ Subscription = $s.Id }
            $subscriptionTenantId = if ($s.PSObject.Properties.Name -contains 'TenantId') { $s.TenantId } else { $tenantId }
            if ($subscriptionTenantId) { $switchParams['Tenant'] = $subscriptionTenantId }
            Set-AzContext @switchParams | Out-Null
            Get-AzAdvisorRecommendation | Select-Object Category, Impact, ImpactedField, ImpactedValue,
                @{ n = 'Subscription'; e = { $s.Name } }, ShortDescriptionProblem, ShortDescriptionSolution
        }
        $Collect | Add-Member -NotePropertyName advisor -NotePropertyValue (@($recs)) -Force
    }
    finally {
        if ($originalSubscriptionId) {
            $restoreParams = @{ Subscription = $originalSubscriptionId; ErrorAction = 'SilentlyContinue' }
            if ($tenantId) { $restoreParams['Tenant'] = $tenantId }
            Set-AzContext @restoreParams | Out-Null
        }
    }

    return $Collect
}
