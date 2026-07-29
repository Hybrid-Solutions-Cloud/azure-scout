#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Pull Azure Advisor recommendations per enabled subscription into collect.advisor.

.NOTES
    Read-only. Tracks ADO Story AB#5040.
#>
function Import-AdvisorScores {
    param($Collect)
    $context = Get-AzContext -ErrorAction SilentlyContinue
    $tenantId = if ($context -and $context.Tenant -and $context.Tenant.Id) { $context.Tenant.Id } else { $null }
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
    return $Collect
}
