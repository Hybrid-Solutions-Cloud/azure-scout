#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Shape already-collected inventory rows into the query result-set Invoke-Collect produces,
    so a combined run collects from Azure once instead of twice (AB#5543).

.DESCRIPTION
    Inventory and assessment historically each ran their own Azure Resource Graph pass over the
    same resource types. `Start-AZSCGraphExtraction` already projects the FULL `properties` bag
    from `resources`, `networkresources` and `resourcecontainers`, which is a superset of what
    the assessment's typed queries re-fetch. This function derives every assessment scalar from
    those in-memory rows instead of asking Azure again.

    It returns the same `$r`-shaped hashtable of query-name -> row-array that Invoke-Collect's
    KQL pack produces, so the downstream canonical-contract shaping is untouched.

    ONE query cannot be served from inventory and is deliberately NOT produced here:
    `sqlDefenderPricing` reads the `SecurityResources` table (Microsoft.Security/pricings).
    Inventory only touches `securityresources` when -SecurityCenter is supplied, and then filters
    to `microsoft.security/assessments` with an Unhealthy status, so the pricings rows are never
    present. Invoke-Collect still issues that one live query. Callers must not assume this
    function returns a key for it.

.NOTES
    Tracks ADO AB#5543 (Epic AB#5545).

    Every projection below mirrors the KQL in src/collect/Invoke-Collect.ps1 field for field.
    The KQL remains the reference implementation and is still exercised whenever a run is
    assessment-only; this path is used when an inventory pass has already fetched the data.
    tests/CollectorCollapse.Tests.ps1 asserts the two paths agree.

    Semantics deliberately preserved from the KQL:
      - `array_length(null)` in KQL yields null, NOT 0. A VNet with no peerings array therefore
        reports peeringCount $null, matching the ARG path, so a rule filtering `peeringCount > 0`
        behaves identically.
      - `tobool()` of a missing property yields $null, not $false. Returning $false here would
        silently flip rules that test for an explicit false.
      - Subnet capacity is `2^(32-prefix) - 5` (Azure reserves five addresses per subnet).
      - `resources` and `networkresources` overlap for some network types, so rows are
        de-duplicated by `id` before shaping — without this, a VNet present in both tables would
        be counted twice and inflate every existence-count rule.
#>

function Get-ScoutProp {
    <#
    .SYNOPSIS
        StrictMode-safe nested property read. Returns $null for any missing segment.

    .NOTES
        Callers reading an ARRAY-typed leaf: `return $current` (no leading comma) pipeline-UNROLLS
        a genuinely present but EMPTY array to zero output objects, so `$v = Get-ScoutProp ...`
        captures $null, indistinguishable from the property being absent entirely. Every existing
        caller wraps the result in `Measure-ScoutArray` immediately, whose own null-in/null-out
        contract happens to make that collapse look intentional, so this function's general
        contract is left as-is here rather than changed for every caller at once. Use
        `Get-ScoutPropArray` below instead of this function for a leaf you need to distinguish
        "empty array" (0) from "absent" (null) on, as `array_length()` does in the KQL this file
        mirrors (AB#6820).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] $InputObject,
        [Parameter(Mandatory)] [string] $Path
    )
    $current = $InputObject
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) { return $null }
        if ($current -isnot [System.Management.Automation.PSObject] -and $current -isnot [pscustomobject]) {
            $wrapped = [System.Management.Automation.PSObject]::AsPSObject($current)
        }
        else { $wrapped = $current }
        $property = $wrapped.PSObject.Properties[$segment]
        if (-not $property) { return $null }
        $current = $property.Value
    }
    return $current
}

function Get-ScoutPropArray {
    <#
    .SYNOPSIS
        Same nested-property walk as Get-ScoutProp, for an array-typed leaf, preserving the
        difference between "the property is absent" ($null) and "the property is present and
        empty" (a real, zero-length array) -- see Get-ScoutProp's .NOTES for why that function
        cannot safely do this for every caller at once. AB#6820.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] $InputObject,
        [Parameter(Mandatory)] [string] $Path
    )
    $current = $InputObject
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) { return $null }
        if ($current -isnot [System.Management.Automation.PSObject] -and $current -isnot [pscustomobject]) {
            $wrapped = [System.Management.Automation.PSObject]::AsPSObject($current)
        }
        else { $wrapped = $current }
        $property = $wrapped.PSObject.Properties[$segment]
        if (-not $property) { return $null }
        $current = $property.Value
    }
    if ($null -eq $current) { return $null }
    return , @($current)
}

function ConvertTo-ScoutBool {
    <#
    .SYNOPSIS
        KQL tobool() semantics: $null stays $null so a missing property never reads as an
        explicit false.
    #>
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return $Value }
    $text = [string] $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return [bool]::TryParse($text, [ref] $null) ? [bool]::Parse($text) : $null
}

function Measure-ScoutArray {
    <#
    .SYNOPSIS
        KQL array_length() semantics: null in, null out (NOT zero).
    #>
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    return @($Value).Count
}

function ConvertFrom-ScoutInventory {
    [CmdletBinding()]
    param(
        # The `Resources` array from Start-AZSCGraphExtraction (resources + networkresources +
        # the other typed tables it accumulates).
        [Parameter()] [AllowNull()] [object[]] $Resources,

        # The `ResourceContainers` array from Start-AZSCGraphExtraction (subscriptions + RGs).
        [Parameter()] [AllowNull()] [object[]] $ResourceContainers
    )

    # `resources` and `networkresources` overlap for several network types; shaping both without
    # de-duplication would double-count every affected resource.
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in @($Resources)) {
        if ($null -eq $resource) { continue }
        $id = [string] (Get-ScoutProp $resource 'id')
        if ($id -and -not $seenIds.Add($id)) { continue }
        $rows.Add($resource)
    }

    $containers = @(@($ResourceContainers) | Where-Object { $null -ne $_ })

    function Select-ByType {
        param([string] $Type)
        return @($rows | Where-Object { [string] (Get-ScoutProp $_ 'type') -ieq $Type })
    }

    $result = @{}

    # ---- subscriptions (resourcecontainers) ----
    $result['subscriptions'] = @(
        $containers |
            Where-Object { [string] (Get-ScoutProp $_ 'type') -ieq 'microsoft.resources/subscriptions' } |
            ForEach-Object {
                [pscustomobject]@{
                    id    = [string] (Get-ScoutProp $_ 'subscriptionId')
                    name  = [string] (Get-ScoutProp $_ 'name')
                    state = [string] (Get-ScoutProp $_ 'properties.state')
                    tags  = Get-ScoutProp $_ 'tags'
                }
            }
    )

    # ---- deployments (resource groups) ----
    $result['deployments'] = @(
        $containers |
            Where-Object { [string] (Get-ScoutProp $_ 'type') -ieq 'microsoft.resources/subscriptions/resourcegroups' } |
            ForEach-Object {
                [pscustomobject]@{
                    name           = [string] (Get-ScoutProp $_ 'name')
                    subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                }
            }
    )

    # ---- networking ----
    $virtualNetworks = Select-ByType 'microsoft.network/virtualnetworks'
    $result['virtualNetworks'] = @(
        $virtualNetworks | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                peeringCount   = Measure-ScoutArray (Get-ScoutProp $_ 'properties.virtualNetworkPeerings')
                ddosEnabled    = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableDdosProtection')
            }
        }
    )

    # mv-expand over properties.subnets. Azure reserves 5 addresses per subnet.
    $result['subnets'] = @(
        foreach ($vnet in $virtualNetworks) {
            foreach ($subnet in @(Get-ScoutProp $vnet 'properties.subnets')) {
                if ($null -eq $subnet) { continue }
                $prefix = [string] (Get-ScoutProp $subnet 'properties.addressPrefix')
                $total = 0
                $parts = $prefix -split '/'
                if ($parts.Count -eq 2) {
                    $maskBits = 0
                    if ([int]::TryParse($parts[1], [ref] $maskBits) -and $maskBits -ge 0 -and $maskBits -le 32) {
                        $total = [int] ([Math]::Pow(2, 32 - $maskBits)) - 5
                    }
                }
                $used = Measure-ScoutArray (Get-ScoutProp $subnet 'properties.ipConfigurations')
                $usedCount = if ($null -eq $used) { 0 } else { $used }
                [pscustomobject]@{
                    vnet             = [string] (Get-ScoutProp $vnet 'name')
                    subnet           = [string] (Get-ScoutProp $subnet 'name')
                    prefix           = $prefix
                    total            = $total
                    used             = $used
                    ipUtilizationPct = if ($total -gt 0) { [Math]::Round(([double] $usedCount / $total) * 100, 1) } else { [double] 0 }
                }
            }
        }
    )

    $result['azureFirewalls'] = @(
        Select-ByType 'microsoft.network/azurefirewalls' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                sku            = [string] (Get-ScoutProp $_ 'properties.sku.name')
            }
        }
    )

    # policyName = split(id, "/")[8] in KQL — the parent firewall-policy segment.
    $result['firewallPolicyRuleGroups'] = @(
        Select-ByType 'microsoft.network/firewallpolicies/rulecollectiongroups' | ForEach-Object {
            $idSegments = ([string] (Get-ScoutProp $_ 'id')) -split '/'
            $priorityRaw = Get-ScoutProp $_ 'properties.priority'
            [pscustomobject]@{
                name            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup   = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId  = [string] (Get-ScoutProp $_ 'subscriptionId')
                policyName      = if ($idSegments.Count -gt 8) { $idSegments[8] } else { $null }
                priority        = if ($null -eq $priorityRaw) { $null } else { [int] $priorityRaw }
                ruleCollections = Get-ScoutProp $_ 'properties.ruleCollections'
            }
        }
    )

    $result['vpnGateways'] = @(
        Select-ByType 'microsoft.network/virtualnetworkgateways' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                gatewayType   = [string] (Get-ScoutProp $_ 'properties.gatewayType')
                sku           = [string] (Get-ScoutProp $_ 'properties.sku.name')
                activeActive  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.activeActive')
                bgp           = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableBgp')
            }
        }
    )

    # coalesce(privateLinkServiceConnections[0], manualPrivateLinkServiceConnections[0]) then
    # split the target resource id: [6] = provider, [7] = type.
    $result['privateEndpoints'] = @(
        Select-ByType 'microsoft.network/privateendpoints' | ForEach-Object {
            $connection = @(Get-ScoutProp $_ 'properties.privateLinkServiceConnections')[0]
            if ($null -eq $connection) {
                $connection = @(Get-ScoutProp $_ 'properties.manualPrivateLinkServiceConnections')[0]
            }
            $targetResourceId = [string] (Get-ScoutProp $connection 'properties.privateLinkServiceId')
            $targetSegments = $targetResourceId -split '/'
            [pscustomobject]@{
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                targetResourceId = $targetResourceId
                targetProvider   = if ($targetSegments.Count -gt 6) { $targetSegments[6].ToLowerInvariant() } else { '' }
                targetType       = if ($targetSegments.Count -gt 7) { $targetSegments[7].ToLowerInvariant() } else { '' }
            }
        }
    )

    $result['privateDnsZones'] = @(
        Select-ByType 'microsoft.network/privatednszones' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
            }
        }
    )

    # mv-expand securityRules, keep Allow + Inbound from an internet-equivalent source.
    $openSources = @('*', '0.0.0.0/0', 'Internet')
    $result['nsgPublicInbound'] = @(
        foreach ($nsg in (Select-ByType 'microsoft.network/networksecuritygroups')) {
            foreach ($rule in @(Get-ScoutProp $nsg 'properties.securityRules')) {
                if ($null -eq $rule) { continue }
                $access = [string] (Get-ScoutProp $rule 'properties.access')
                $direction = [string] (Get-ScoutProp $rule 'properties.direction')
                $source = [string] (Get-ScoutProp $rule 'properties.sourceAddressPrefix')
                if ($access -ine 'Allow' -or $direction -ine 'Inbound') { continue }
                if ($openSources -notcontains $source) { continue }
                [pscustomobject]@{
                    nsg           = [string] (Get-ScoutProp $nsg 'name')
                    resourceGroup = [string] (Get-ScoutProp $nsg 'resourceGroup')
                    rule          = [string] (Get-ScoutProp $rule 'name')
                    port          = [string] (Get-ScoutProp $rule 'properties.destinationPortRange')
                }
            }
        }
    )

    # ---- compute ----
    # Region list copied verbatim from the KQL zoneEligible projection.
    $zoneEligibleRegions = @(
        'eastus', 'eastus2', 'westus2', 'westus3', 'centralus', 'southcentralus',
        'northeurope', 'westeurope', 'uksouth', 'francecentral', 'germanywestcentral',
        'switzerlandnorth', 'norwayeast', 'swedencentral', 'southeastasia', 'eastasia',
        'australiaeast', 'japaneast', 'koreacentral', 'centralindia', 'canadacentral',
        'brazilsouth', 'uaenorth', 'southafricanorth'
    )
    $result['virtualMachines'] = @(
        Select-ByType 'microsoft.compute/virtualmachines' | ForEach-Object {
            $zoneCount = Measure-ScoutArray (Get-ScoutProp $_ 'zones')
            [pscustomobject]@{
                # `id` is the join key for the cross-resource rules (AB#6835) and must be shaped
                # here, not fetched: a separate query for it would undo AB#5648's collect-once.
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                zoneRedundant  = ($null -ne $zoneCount -and $zoneCount -gt 0)
                zoneEligible   = $zoneEligibleRegions -contains ([string] (Get-ScoutProp $_ 'location')).ToLowerInvariant()
                size           = [string] (Get-ScoutProp $_ 'properties.hardwareProfile.vmSize')
            }
        }
    )

    # AB#6820 -- mirrors Invoke-Collect.ps1's `privateClouds` KQL field for field so a combined
    # inventory + assessment run shapes AVS private clouds from the one raw pass instead of
    # issuing a second, live ARG round-trip for them.
    $result['privateClouds'] = @(
        Select-ByType 'microsoft.avs/privateclouds' | ForEach-Object {
            $identitySourceCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.identitySources')
            $externalCloudLinkCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.externalCloudLinks')
            $clusterSizeRaw = Get-ScoutProp $_ 'properties.managementCluster.clusterSize'
            [pscustomobject]@{
                id                      = [string] (Get-ScoutProp $_ 'id')
                name                    = [string] (Get-ScoutProp $_ 'name')
                resourceGroup           = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId          = [string] (Get-ScoutProp $_ 'subscriptionId')
                sku                     = [string] (Get-ScoutProp $_ 'sku.name')
                availabilityStrategy    = [string] (Get-ScoutProp $_ 'properties.availability.strategy')
                availabilityZone        = [string] (Get-ScoutProp $_ 'properties.availability.zone')
                clusterSize             = if ($null -eq $clusterSizeRaw) { $null } else { [int] $clusterSizeRaw }
                expressRouteCircuitId   = [string] (Get-ScoutProp $_ 'properties.circuit.expressRouteID')
                encryptionStatus        = [string] (Get-ScoutProp $_ 'properties.encryption.status')
                internet                = [string] (Get-ScoutProp $_ 'properties.internet')
                identitySourceCount     = $identitySourceCount
                externalCloudLinkCount  = $externalCloudLinkCount
            }
        }
    )

    $result['orphanedDisks'] = @(
        Select-ByType 'microsoft.compute/disks' |
            Where-Object { ([string] (Get-ScoutProp $_ 'properties.diskState')) -ieq 'Unattached' } |
            ForEach-Object {
                $sizeRaw = Get-ScoutProp $_ 'properties.diskSizeGB'
                [pscustomobject]@{
                    name          = [string] (Get-ScoutProp $_ 'name')
                    resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                    location      = [string] (Get-ScoutProp $_ 'location')
                    sku           = [string] (Get-ScoutProp $_ 'sku.name')
                    sizeGb        = if ($null -eq $sizeRaw) { $null } else { [int] $sizeRaw }
                }
            }
    )

    $result['orphanedPips'] = @(
        Select-ByType 'microsoft.network/publicipaddresses' |
            Where-Object { $null -eq (Get-ScoutProp $_ 'properties.ipConfiguration') } |
            ForEach-Object {
                [pscustomobject]@{
                    name          = [string] (Get-ScoutProp $_ 'name')
                    resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                    location      = [string] (Get-ScoutProp $_ 'location')
                    sku           = [string] (Get-ScoutProp $_ 'sku.name')
                }
            }
    )

    # ---- ops posture: summarize total/withDiag by type ----
    $result['diagnosticCoverage'] = @(
        $rows | Group-Object { [string] (Get-ScoutProp $_ 'type') } | ForEach-Object {
            $total = $_.Count
            $withDiag = @($_.Group | Where-Object { $null -ne (Get-ScoutProp $_ 'properties.diagnosticSettings') }).Count
            [pscustomobject]@{
                type        = $_.Name
                total       = $total
                withDiag    = $withDiag
                coveragePct = if ($total -gt 0) { [Math]::Round(([double] $withDiag / $total) * 100, 1) } else { [double] 0 }
            }
        }
    )

    # ---- per-domain scalars ----
    $result['storageAccounts'] = @(
        Select-ByType 'microsoft.storage/storageaccounts' | ForEach-Object {
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                sku                = [string] (Get-ScoutProp $_ 'sku.name')
                publicAccess       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.allowBlobPublicAccess')
                httpsOnly          = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.supportsHttpsTrafficOnly')
                minTls             = [string] (Get-ScoutProp $_ 'properties.minimumTlsVersion')
                networkDefaultDeny = ([string] (Get-ScoutProp $_ 'properties.networkAcls.defaultAction')) -ieq 'Deny'
            }
        }
    )

    $result['sqlDatabases'] = @(
        Select-ByType 'microsoft.sql/servers/databases' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                zoneRedundant = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                tier          = [string] (Get-ScoutProp $_ 'sku.tier')
            }
        }
    )

    $result['sqlServers'] = @(
        Select-ByType 'microsoft.sql/servers' | ForEach-Object {
            [pscustomobject]@{
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['webApps'] = @(
        Select-ByType 'microsoft.web/sites' | ForEach-Object {
            $sslStates = Measure-ScoutArray (Get-ScoutProp $_ 'properties.hostNameSslStates')
            [pscustomobject]@{
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                httpsOnly         = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.httpsOnly')
                minTls            = [string] (Get-ScoutProp $_ 'properties.siteConfig.minTlsVersion')
                vnetIntegrated    = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.virtualNetworkSubnetId'))
                customDomainBound = ($null -ne $sslStates -and $sslStates -gt 1)
            }
        }
    )

    # agentPoolProfiles: mv-expand + summarize back to one row per cluster.
    $result['aksClusters'] = @(
        Select-ByType 'microsoft.containerservice/managedclusters' | ForEach-Object {
            $pools = @(Get-ScoutProp $_ 'properties.agentPoolProfiles')
            $totalPools = $pools.Count
            $zonedPools = @($pools | Where-Object {
                    $zones = Measure-ScoutArray (Get-ScoutProp $_ 'availabilityZones')
                    $null -ne $zones -and $zones -gt 0
                }).Count
            [pscustomobject]@{
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                k8sVersion           = [string] (Get-ScoutProp $_ 'properties.kubernetesVersion')
                privateCluster       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.apiServerAccessProfile.enablePrivateCluster')
                rbacEnabled          = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableRBAC')
                networkPolicyEnabled = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.networkProfile.networkPolicy'))
                aadIntegrated        = ($null -ne (Get-ScoutProp $_ 'properties.aadProfile'))
                allPoolsZoned        = ($zonedPools -eq $totalPools)
            }
        }
    )

    $result['containerRegistries'] = @(
        Select-ByType 'microsoft.containerregistry/registries' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                sku           = [string] (Get-ScoutProp $_ 'sku.name')
                adminEnabled  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.adminUserEnabled')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['keyVaults'] = @(
        Select-ByType 'microsoft.keyvault/vaults' | ForEach-Object {
            [pscustomobject]@{
                id              = [string] (Get-ScoutProp $_ 'id')
                name            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup   = [string] (Get-ScoutProp $_ 'resourceGroup')
                softDelete      = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableSoftDelete')
                purgeProtection = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enablePurgeProtection')
            }
        }
    )

    # ---- cross-resource join sources and the Migration domain (AB#6835 / AB#6832) ----------------
    # Every one of these is shaped from rows the SAME raw pass already returned. Adding them as
    # live `$q` queries instead would have taken the default assessment collect from four Resource
    # Graph round-trips to eleven, silently undoing AB#5648.
    $result['snapshots'] = @(
        Select-ByType 'microsoft.compute/snapshots' | ForEach-Object {
            $sizeRaw = Get-ScoutProp $_ 'properties.diskSizeGB'
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                sourceDiskId   = [string] (Get-ScoutProp $_ 'properties.creationData.sourceResourceId')
                sizeGb         = if ($null -eq $sizeRaw) { $null } else { [int] $sizeRaw }
                created        = [string] (Get-ScoutProp $_ 'properties.timeCreated')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
            }
        }
    )

    # ALL managed disks, not just the unattached ones `orphanedDisks` keeps: XR-SNP-01 asks whether
    # a snapshot's source disk still exists, and an attached disk answers "yes".
    $result['managedDisks'] = @(
        Select-ByType 'microsoft.compute/disks' | ForEach-Object {
            $sizeRaw = Get-ScoutProp $_ 'properties.diskSizeGB'
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
                diskState      = [string] (Get-ScoutProp $_ 'properties.diskState')
                sizeGb         = if ($null -eq $sizeRaw) { $null } else { [int] $sizeRaw }
            }
        }
    )

    $result['diskEncryptionSets'] = @(
        Select-ByType 'microsoft.compute/diskencryptionsets' | ForEach-Object {
            [pscustomobject]@{
                id              = [string] (Get-ScoutProp $_ 'id')
                name            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup   = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId  = [string] (Get-ScoutProp $_ 'subscriptionId')
                keyVaultId      = [string] (Get-ScoutProp $_ 'properties.activeKey.sourceVault.id')
                encryptionType  = [string] (Get-ScoutProp $_ 'properties.encryptionType')
                autoKeyRotation = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.rotationToLatestKeyVersionEnabled')
            }
        }
    )

    $migrationTypes = @(
        'microsoft.migrate/migrateprojects', 'microsoft.migrate/projects', 'microsoft.migrate/assessmentprojects'
    )
    $result['migrateProjects'] = @(
        $rows | Where-Object { $migrationTypes -contains ([string] (Get-ScoutProp $_ 'type')).ToLowerInvariant() } | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                type                = ([string] (Get-ScoutProp $_ 'type')).ToLowerInvariant()
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                projectStatus       = [string] (Get-ScoutProp $_ 'properties.projectStatus')
            }
        }
    )

    $migrationServiceTypes = @(
        'microsoft.datamigration/services', 'microsoft.datamigration/sqlmigrationservices',
        'microsoft.databox/jobs', 'microsoft.databoxedge/databoxedgedevices'
    )
    $result['migrationServices'] = @(
        $rows | Where-Object { $migrationServiceTypes -contains ([string] (Get-ScoutProp $_ 'type')).ToLowerInvariant() } | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                type              = ([string] (Get-ScoutProp $_ 'type')).ToLowerInvariant()
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['discoverySites'] = @(
        $rows | Where-Object { ([string] (Get-ScoutProp $_ 'type')).ToLowerInvariant().StartsWith('microsoft.offazure/') } | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                type              = ([string] (Get-ScoutProp $_ 'type')).ToLowerInvariant()
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    # `recoveryservicesresources` is a DIFFERENT Resource Graph table, so unlike everything above
    # this one cannot be shaped from the `resources` rows -- the raw pass now asks for it, which is
    # a fifth round-trip on the default assessment collect and the only one AB#6741 added. It buys
    # XR-BKP-01, "which VMs have no backup", which was the single most-requested finding in the
    # audit's §7. Recorded in tests/Collect.SinglePassInversion.Tests.ps1 rather than absorbed.
    $result['backupProtectedItems'] = @(
        Select-ByType 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' | ForEach-Object {
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId       = [string] (Get-ScoutProp $_ 'subscriptionId')
                sourceResourceId     = [string] (Get-ScoutProp $_ 'properties.sourceResourceId')
                protectionState      = [string] (Get-ScoutProp $_ 'properties.protectionState')
                lastBackupStatus     = [string] (Get-ScoutProp $_ 'properties.lastBackupStatus')
                backupManagementType = [string] (Get-ScoutProp $_ 'properties.backupManagementType')
            }
        }
    )

    $result['cognitiveAccounts'] = @(
        Select-ByType 'microsoft.cognitiveservices/accounts' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                accountKind   = [string] (Get-ScoutProp $_ 'kind')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType  = [string] (Get-ScoutProp $_ 'identity.type')
                cmkEnabled    = ([string] (Get-ScoutProp $_ 'properties.encryption.keySource')) -ieq 'Microsoft.KeyVault'
            }
        }
    )

    $result['arcServers'] = @(
        Select-ByType 'microsoft.hybridcompute/machines' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                status        = [string] (Get-ScoutProp $_ 'properties.status')
                agentVersion  = [string] (Get-ScoutProp $_ 'properties.agentVersion')
            }
        }
    )

    # machineId = split(id, "/extensions/")[0]
    $result['arcExtensions'] = @(
        Select-ByType 'microsoft.hybridcompute/machines/extensions' | ForEach-Object {
            $id = [string] (Get-ScoutProp $_ 'id')
            [pscustomobject]@{
                machineId     = ($id -split '/extensions/')[0]
                name          = [string] (Get-ScoutProp $_ 'name')
                extensionType = [string] (Get-ScoutProp $_ 'properties.type')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
            }
        }
    )

    $result['azureLocalClusters'] = @(
        Select-ByType 'microsoft.azurestackhci/clusters' | ForEach-Object {
            [pscustomobject]@{
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                connectivityStatus = [string] (Get-ScoutProp $_ 'properties.connectivityStatus')
            }
        }
    )

    $result['eventHubNamespaces'] = @(
        Select-ByType 'microsoft.eventhub/namespaces' | ForEach-Object {
            [pscustomobject]@{
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                zoneRedundant      = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                publicAccess       = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                autoInflateEnabled = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.isAutoInflateEnabled')
            }
        }
    )

    $result['apiManagement'] = @(
        Select-ByType 'microsoft.apimanagement/service' | ForEach-Object {
            [pscustomobject]@{
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                sku                = [string] (Get-ScoutProp $_ 'sku.name')
                virtualNetworkType = [string] (Get-ScoutProp $_ 'properties.virtualNetworkType')
            }
        }
    )

    $result['serviceBusNamespaces'] = @(
        Select-ByType 'microsoft.servicebus/namespaces' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['iotHubs'] = @(
        Select-ByType 'microsoft.devices/iothubs' | ForEach-Object {
            [pscustomobject]@{
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                sku              = [string] (Get-ScoutProp $_ 'sku.name')
                publicAccess     = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                disableLocalAuth = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAuth')
            }
        }
    )

    # linkedHubCount is a COUNT only — the array's connectionString entries are secrets and are
    # never read or projected here, matching the KQL.
    $result['dpsInstances'] = @(
        Select-ByType 'microsoft.devices/provisioningservices' | ForEach-Object {
            [pscustomobject]@{
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                sku              = [string] (Get-ScoutProp $_ 'sku.name')
                publicAccess     = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                allocationPolicy = [string] (Get-ScoutProp $_ 'properties.allocationPolicy')
                linkedHubCount   = Measure-ScoutArray (Get-ScoutProp $_ 'properties.iotHubs')
            }
        }
    )

    $result['digitalTwinsInstances'] = @(
        Select-ByType 'microsoft.digitaltwins/digitaltwinsinstances' | ForEach-Object {
            [pscustomobject]@{
                name                          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup                 = [string] (Get-ScoutProp $_ 'resourceGroup')
                publicAccess                  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                privateEndpointConnectionCount = Measure-ScoutArray (Get-ScoutProp $_ 'properties.privateEndpointConnections')
                identityType                  = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    $result['synapseWorkspaces'] = @(
        Select-ByType 'microsoft.synapse/workspaces' | ForEach-Object {
            [pscustomobject]@{
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                publicAccess      = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                managedVnetEnabled = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.managedVirtualNetwork'))
            }
        }
    )

    $result['purviewAccounts'] = @(
        Select-ByType 'microsoft.purview/accounts' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
            }
        }
    )

    $result['logAnalyticsWorkspaces'] = @(
        Select-ByType 'microsoft.operationalinsights/workspaces' | ForEach-Object {
            $retention = Get-ScoutProp $_ 'properties.retentionInDays'
            [pscustomobject]@{
                name            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup   = [string] (Get-ScoutProp $_ 'resourceGroup')
                retentionInDays = if ($null -eq $retention) { $null } else { [int] $retention }
            }
        }
    )

    return $result
}
