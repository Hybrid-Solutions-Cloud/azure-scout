#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Mirror the swept Azure VMware Solution child rows under their real ARM resource types, so the
    discovery index lists them.

.DESCRIPTION
    Resource Graph indexes an Azure VMware Solution private cloud but none of its children, so
    Get-ScoutArmChildResource reads them with ARM GETs and returns synthetic `AZSC/ARMChild/Avs*`
    rows. The discovery index (New-ScoutResourceDiscovery) treats every `AZSC/*` row as ENRICHMENT of
    the base resource with the same id and never lists it on its own -- which is right for a
    diagnostic setting or a blob container, and wrong for a cluster or a datastore, which are
    deployable ARM resources with no Resource Graph row to enrich. Without a base row they were never
    discovered at all.

    This pure transform gives each of those child rows a base-resource twin: same id and name, the
    real ARM type (`microsoft.avs/privateclouds/clusters`, `.../datastores`, ...), the private cloud's
    location, resource group and subscription, and the SAME allow-listed `properties` the AZSC row
    carries. The discovery index then lists it (category Compute, through the `microsoft.avs`
    namespace), the AZSC row attaches to it as enrichment, and the React report shows it under
    Compute, discovered resources. It makes no Azure call, never mutates an input row, and reads no
    property the sweep did not already allow-list.

    The twin shares its id with the AZSC row it mirrors, which ConvertFrom-ScoutInventory would
    de-duplicate; `AZSCDiscoveryTwin = $true` tells that shaper to skip it, so the AZSC row is what
    is shaped whatever order the two arrive in. No collector declares these types, so a twin feeds no
    worksheet.

.PARAMETER Resources
    The raw inventory's rows, including the AZSC/ARMChild rows the ARM-child sweep produced.

.OUTPUTS
    PSCustomObject rows, one per `AZSC/ARMChild/Avs*` row that has an id.
#>
function ConvertTo-ScoutAvsDiscoveryResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources
    )

    # Dataset -> the real ARM resource type, as listed in manifests/azure-provider-types.json.
    $RealType = @{
        'azsc/armchild/avsclusters'               = 'microsoft.avs/privateclouds/clusters'
        'azsc/armchild/avsdatastores'             = 'microsoft.avs/privateclouds/clusters/datastores'
        'azsc/armchild/avsplacementpolicies'      = 'microsoft.avs/privateclouds/clusters/placementpolicies'
        'azsc/armchild/avsaddons'                 = 'microsoft.avs/privateclouds/addons'
        'azsc/armchild/avsglobalreachconnections' = 'microsoft.avs/privateclouds/globalreachconnections'
        'azsc/armchild/avsauthorizations'         = 'microsoft.avs/privateclouds/authorizations'
        'azsc/armchild/avscloudlinks'             = 'microsoft.avs/privateclouds/cloudlinks'
        'azsc/armchild/avssegments'               = 'microsoft.avs/privateclouds/workloadnetworks/segments'
        'azsc/armchild/avsdhcpconfigurations'     = 'microsoft.avs/privateclouds/workloadnetworks/dhcpconfigurations'
        'azsc/armchild/avsdnsservices'            = 'microsoft.avs/privateclouds/workloadnetworks/dnsservices'
        'azsc/armchild/avsgateways'               = 'microsoft.avs/privateclouds/workloadnetworks/gateways'
        'azsc/armchild/avsiscsipaths'             = 'microsoft.avs/privateclouds/iscsipaths'
        'azsc/armchild/avsmaintenances'           = 'microsoft.avs/privateclouds/maintenances'
    }

    function Get-AvsRowValue {
        param([Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][string[]]$Name)
        foreach ($Candidate in $Name) {
            $Property = $InputObject.PSObject.Properties[$Candidate]
            if ($null -ne $Property) { return $Property.Value }
        }
        return $null
    }

    foreach ($Row in $Resources) {
        if ($null -eq $Row) { continue }
        $Type = ([string](Get-AvsRowValue -InputObject $Row -Name @('TYPE', 'type'))).ToLowerInvariant()
        if (-not $RealType.ContainsKey($Type)) { continue }
        $Id = [string](Get-AvsRowValue -InputObject $Row -Name @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }

        [pscustomobject][ordered]@{
            id                = $Id
            name              = [string](Get-AvsRowValue -InputObject $Row -Name @('name', 'NAME'))
            type              = $RealType[$Type]
            location          = [string](Get-AvsRowValue -InputObject $Row -Name @('PARENTLOCATION', 'location'))
            resourceGroup     = [string](Get-AvsRowValue -InputObject $Row -Name @('RESOURCEGROUP', 'resourceGroup'))
            subscriptionId    = [string](Get-AvsRowValue -InputObject $Row -Name @('subscriptionId', 'SubscriptionId'))
            properties        = Get-AvsRowValue -InputObject $Row -Name @('properties', 'PROPERTIES')
            AZSCDiscoveryTwin = $true
        }
    }
}
