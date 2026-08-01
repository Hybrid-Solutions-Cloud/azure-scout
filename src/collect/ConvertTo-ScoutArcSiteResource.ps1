#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Materialize AZSC/ARMChild/ArcSites resource rows from Get-ScoutApiResources' ArcSites field.

.DESCRIPTION
    `Microsoft.Edge/sites` (Azure Arc site manager) is a normal, non-extension ARM resource, but
    Resource Graph's supported-type reference does not list `microsoft.edge/sites` among the
    `microsoft.edge/*` types it indexes -- so a declarative collector reading the `resources`
    table for that type returns zero rows in every tenant, the same defect class AB#6769 fixed
    for Monitor/ResourceDiagnosticSettings. Because `Microsoft.Edge/sites` has no natural parent
    resource the way an extension resource does, `Get-ScoutApiResources.ps1` lists it once per
    subscription (`ArcSites` field) rather than through Get-ScoutArmChildResource.ps1's per-parent
    sweep. This is the pure transform that turns that per-subscription REST result into the
    `AZSC/ARMChild/ArcSites` resource rows the Hybrid/ArcSites declarative collector reads --
    performs no Azure call and never mutates an input row, matching the shape of
    ConvertTo-ScoutAvdAzureLocalSessionHost.ps1 and Get-ScoutOutageResource.ps1.

.PARAMETER ApiResources
    Per-subscription output from Get-ScoutApiResources. The `ArcSites` field is read; every
    other field is ignored.

.OUTPUTS
    `[pscustomobject]` rows, one per site, each tagged `TYPE = 'AZSC/ARMChild/ArcSites'` with
    `subscriptionId` inherited from the owning subscription. A subscription whose sweep failed or
    whose ArcSites field is `$null` contributes zero rows and does not throw.

.NOTES
    Tracks ADO AB#6801 (Feature AB#6747, Epic AB#6454).
#>
function ConvertTo-ScoutArcSiteResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ApiResources
    )

    function Get-ArcSitePropertyValue {
        param(
            [Parameter(Mandatory)]$InputObject,
            [Parameter(Mandatory)][string[]]$Name
        )

        foreach ($Candidate in $Name) {
            $Property = $InputObject.PSObject.Properties[$Candidate]
            if ($null -ne $Property) { return $Property.Value }
        }
        return $null
    }

    foreach ($ApiResult in @($ApiResources)) {
        if ($null -eq $ApiResult) { continue }

        $SubscriptionId = [string](Get-ArcSitePropertyValue -InputObject $ApiResult -Name @('Subscription', 'subscriptionId'))
        $SitesProperty = $ApiResult.PSObject.Properties['ArcSites']
        if ($null -eq $SitesProperty -or $null -eq $SitesProperty.Value) { continue }

        foreach ($Site in @($SitesProperty.Value)) {
            if ($null -eq $Site) { continue }

            $SiteId = [string](Get-ArcSitePropertyValue -InputObject $Site -Name @('id', 'ID'))
            # ARM ids are always .../subscriptions/{sub}/resourceGroups/{rg}/providers/...; a site
            # created at subscription scope (no resource group segment) legitimately has none.
            $ResourceGroup = $null
            if (-not [string]::IsNullOrEmpty($SiteId)) {
                $Segments = $SiteId -split '/'
                $RgIndex = [array]::IndexOf($Segments, 'resourceGroups')
                if ($RgIndex -ge 0 -and $Segments.Count -gt ($RgIndex + 1)) {
                    $ResourceGroup = $Segments[$RgIndex + 1]
                }
            }

            $Row = [ordered]@{}
            foreach ($Property in $Site.PSObject.Properties) {
                $Row[$Property.Name] = $Property.Value
            }
            $Row['TYPE'] = 'AZSC/ARMChild/ArcSites'
            $Row['subscriptionId'] = $SubscriptionId
            $Row['RESOURCEGROUP'] = $ResourceGroup

            [PSCustomObject]$Row
        }
    }
}
