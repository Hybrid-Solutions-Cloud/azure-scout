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

function ConvertFrom-ScoutTokenValue {
    <#
    .SYNOPSIS
        Normalise a Newtonsoft JToken to the native PowerShell value it represents.

    .NOTES
        AB#6899. Resource Graph hands dynamic columns (`properties`, `sku`, `identity`, ...)
        back as Newtonsoft `JObject`/`JArray`/`JValue`, not as PSCustomObject. A `JValue`
        stringifies acceptably but is not a `[bool]`, so `ConvertTo-ScoutBool` on one used to
        fall through to its string parse; unwrapping to `.Value` here restores the CLR type the
        rest of this file assumes.

        A `JObject` is deliberately returned AS-IS: it is still walkable by
        `Get-ScoutChildValue` below, and converting the whole bag eagerly would cost a deep copy
        of every resource's full ARM properties on every read.
    #>
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }

    # EVERY return below carries the unary comma. A bare `return $Value` on an array-valued leaf
    # emits its ELEMENTS, so a one-element array reconstitutes at the call site as the element
    # itself and a zero-element array as $null -- both of which corrupt the very distinction the
    # array walkers below exist to preserve.
    $out = switch ($Value.GetType().FullName) {
        'Newtonsoft.Json.Linq.JValue' { $Value.Value; break }
        'Newtonsoft.Json.Linq.JArray' { , @(foreach ($item in $Value) { ConvertFrom-ScoutTokenValue $item }); break }
        default { , $Value }
    }
    return , $out
}

function Get-ScoutChildValue {
    <#
    .SYNOPSIS
        Read ONE named child off a value of any shape a Resource Graph row can carry.

    .NOTES
        AB#6899. `Get-ScoutProp` walked every segment with
        `$wrapped.PSObject.Properties[$segment]`, which resolves a PSCustomObject's members and
        NOTHING ELSE. It silently returned $null — no error, no warning — for two other shapes
        a caller can reach these walkers with:

          * `IDictionary` — PowerShell's dictionary adapter exposes `Keys`/`Values`/`Count` as
            members, never the keys themselves.
          * `Newtonsoft.Json.Linq.JObject` — `PSObject.Properties` on one is EMPTY. Not "missing
            the key": empty. There is no member to find, so every nested read looked exactly
            like an absent property.

        SCOPE, measured rather than assumed. The path Scout runs today is NOT affected:
        `Search-AzGraph` (Az.ResourceGraph 1.3.0, SearchAzureRmGraph) converts rows through
        `JTokenExtensions.ToPsObject`, which builds a PSCustomObject RECURSIVELY, so `properties`
        arrives as a PSCustomObject and the old walk handled it. Verified live — the pre-fix and
        post-fix code shape the same tenant into the same 5 VNets and 8 subnets. This is
        hardening plus a real fix for the dictionary shape, not a fix for an observed production
        failure, and it should not be described as one.

        Dictionaries are tested BEFORE the PSObject path, deliberately: a dictionary would
        otherwise match `AsPSObject` and resolve `Keys` as if it were the caller's segment name.
    #>
    param([AllowNull()] $InputObject, [Parameter(Mandatory)] [string] $Name)
    if ($null -eq $InputObject) { return $null }

    # Resolved in ONE place and returned once, with a unary comma. A plain `return $value` on an
    # array leaf pipeline-unrolls it, and on a genuinely-present-but-EMPTY array that means zero
    # output objects -- $null, indistinguishable from absent. `Get-ScoutPropArray` exists
    # precisely to tell those apart (AB#6820), so this helper must not destroy the difference
    # before it gets there.
    $raw = $null
    $found = $false

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            # KQL column names are case-sensitive but the ARM properties bag is not consistently
            # cased across providers, so match the way the rule engine's JSONPath does.
            if ([string] $key -ieq $Name) { $raw = $InputObject[$key]; $found = $true; break }
        }
    }
    # Duck-typed rather than `-is [Newtonsoft.Json.Linq.JObject]`: this file is dot-sourced in
    # contexts (tests, offline renders from a banked collect.json) where Newtonsoft is not
    # loaded, and naming the type in a type literal would fail to load the whole file there.
    elseif ($InputObject.GetType().FullName -eq 'Newtonsoft.Json.Linq.JObject') {
        $raw = $InputObject[$Name]
        if ($null -eq $raw) {
            foreach ($jprop in $InputObject.Properties()) {
                if ($jprop.Name -ieq $Name) { $raw = $jprop.Value; break }
            }
        }
        $found = $null -ne $raw
    }
    else {
        $property = [System.Management.Automation.PSObject]::AsPSObject($InputObject).PSObject.Properties[$Name]
        if ($property) { $raw = $property.Value; $found = $true }
    }

    if (-not $found) { return $null }
    $value = ConvertFrom-ScoutTokenValue $raw
    return , $value
}

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
        $current = Get-ScoutChildValue -InputObject $current -Name $segment
    }
    # An array leaf still unrolls -- that is this function's documented contract above, and every
    # existing caller wraps the result in `Measure-ScoutArray`, which relies on it. A non-array
    # IEnumerable leaf must NOT: a Newtonsoft JObject enumerates over its JProperties, so a bare
    # return would hand the caller the object's members in place of the object (AB#6899).
    if ($null -ne $current -and
        $current -isnot [System.Array] -and
        $current -isnot [string] -and
        $current -is [System.Collections.IEnumerable]) {
        return , $current
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
        $current = Get-ScoutChildValue -InputObject $current -Name $segment
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

function ConvertTo-ScoutFeatureFlag {
    <#
    .SYNOPSIS
        A feature switch read off a per-resource ARM GET: $true only when the service said so,
        $false when it said otherwise OR said nothing.

    .NOTES
        AB#9300 phase 4, batch 2. This is the deliberate opposite of ConvertTo-ScoutBool, which
        keeps a missing property as $null because a Resource Graph row can be sparse. A per-
        resource GET returns the service's complete document, and ARM omits a feature that was
        never turned on: a storage account that never enabled blob versioning has no
        `isVersioningEnabled` at all, and one that never enabled change feed has no `changeFeed`
        object (both seen live). Reading that absence as $null would let a rule filtering
        `versioningEnabled == false` silently skip exactly the accounts it exists to find.
    #>
    param([AllowNull()] $Value)
    return ((ConvertTo-ScoutBool $Value) -eq $true)
}

function ConvertTo-ScoutNullableString {
    <#
    .SYNOPSIS
        A string setting as the service returned it: $null stays $null instead of becoming ''.

    .NOTES
        AB#9300 phase 4, batch 2. For the SMB protocol settings an absent value MEANS something
        ("every version / channel encryption / authentication method is allowed"), and an empty
        string would read as "none".
    #>
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    return [string] $Value
}

function Get-ScoutOsPatchSetting {
    <#
    .SYNOPSIS
        Read a Compute/HybridCompute PatchSettings field (patchMode or assessmentMode),
        preferring whichever OS family's sub-object is present.

    .NOTES
        AB#7109. `properties.osProfile.windowsConfiguration` and `...linuxConfiguration` are
        mutually exclusive on any one machine (a VM/Arc server is Windows XOR Linux), so
        preferring whichever is non-null is a merge, not an ambiguity -- mirrors
        Invoke-Collect.ps1's `iff(isnotempty(winX), winX, linX)` KQL idiom field for field.
    #>
    param([Parameter(Mandatory)] [AllowNull()] $Resource, [Parameter(Mandatory)] [string] $Field)
    $winValue = Get-ScoutProp $Resource "properties.osProfile.windowsConfiguration.patchSettings.$Field"
    if ($null -ne $winValue) { return $winValue }
    return Get-ScoutProp $Resource "properties.osProfile.linuxConfiguration.patchSettings.$Field"
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

function ConvertTo-ScoutInt {
    <#
    .SYNOPSIS
        KQL toint() semantics: $null stays $null, and a value that is not a number reads $null
        rather than throwing or becoming 0. A fractional value truncates toward zero, as toint does.

    .NOTES
        AB#9300 phase 4. Replaces the inline `if ($null -eq $raw) { $null } else { [int] $raw }`
        the older shapers repeat, which throws on a non-numeric string; one Resource Graph row with
        an unexpected value must not abort the whole shaping pass.
    #>
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [int]) { return $Value }
    if ($Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) {
        return [int] [Math]::Truncate([double] $Value)
    }
    $text = [string] $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $parsed = 0.0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $parsed)) {
        return [int] [Math]::Truncate($parsed)
    }
    return $null
}

function ConvertTo-ScoutDouble {
    <#
    .SYNOPSIS
        KQL todouble() semantics: $null stays $null; a value that is not a number reads $null.
    #>
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double]) { return $Value }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [single]) { return [double] $Value }
    $text = [string] $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $parsed = 0.0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $parsed)) {
        return $parsed
    }
    return $null
}

function Get-ScoutMinValue {
    <#
    .SYNOPSIS
        KQL min() semantics over a set of values: nulls are ignored, and the result is $null when
        nothing non-null remains (never 0).
    #>
    param([AllowNull()] [object[]] $Values)
    $minimum = $null
    foreach ($candidate in @($Values)) {
        if ($null -eq $candidate) { continue }
        if ($null -eq $minimum -or $candidate -lt $minimum) { $minimum = $candidate }
    }
    return $minimum
}

function ConvertFrom-ScoutInventory {
    [CmdletBinding()]
    param(
        # The `Resources` array from Start-AZSCGraphExtraction (resources + networkresources +
        # the other typed tables it accumulates).
        [Parameter()] [AllowNull()] [object[]] $Resources,

        # The `ResourceContainers` array from Start-AZSCGraphExtraction (subscriptions + RGs).
        [Parameter()] [AllowNull()] [object[]] $ResourceContainers,

        # SourceOperations from Get-ScoutRawInventory. Only the per-resource GETs are read -- the
        # ResourceDiagnosticSettings sweep and the eight AB#9300 phase 4 batch 2 datasets (storage
        # blob/file service settings, SQL auditing and failover groups, web app configuration and
        # basic-auth policies, Event Hubs geo-DR, Redis Enterprise databases): they say which
        # resources were actually checked, which is what separates "setting is off" and "no
        # failover group exists" from "nobody asked".
        [Parameter()] [AllowNull()] [object[]] $SourceOperations
    )

    # `resources` and `networkresources` overlap for several network types; shaping both without
    # de-duplication would double-count every affected resource.
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in @($Resources)) {
        if ($null -eq $resource) { continue }
        # AB#9300, 3.18.19. A discovery twin mirrors an AZSC/ARMChild row under its real ARM type so
        # the discovery index lists it (ConvertTo-ScoutAvsDiscoveryResource). It shares that row's id,
        # which the de-duplication below would otherwise resolve by arrival order; the AZSC row is the
        # one that is shaped, so the twin never takes part. A direct member probe, not Get-ScoutProp: this
        # loop runs once per row of the whole estate (50k on the audited run) and the probe is ~16x cheaper.
        if ($null -ne $resource.PSObject.Properties['AZSCDiscoveryTwin']) { continue }
        $id = [string] (Get-ScoutProp $resource 'id')
        if ($id -and -not $seenIds.Add($id)) { continue }
        $rows.Add($resource)
    }

    # Shape hundreds of typed datasets from one inventory pass without re-scanning the complete
    # estate for every type. On the audited 50k-row run the old Select-ByType implementation
    # repeated a PowerShell property walk millions of times before it reached the failing row.
    $rowsByType = @{}
    foreach ($row in $rows) {
        $rowType = [string](Get-ScoutProp $row 'type')
        if ([string]::IsNullOrWhiteSpace($rowType)) { continue }
        $typeKey = $rowType.ToLowerInvariant()
        if (-not $rowsByType.ContainsKey($typeKey)) {
            $rowsByType[$typeKey] = [System.Collections.Generic.List[object]]::new()
        }
        $rowsByType[$typeKey].Add($row)
    }

    $containers = @(@($ResourceContainers) | Where-Object { $null -ne $_ })

    function Select-ByType {
        param([string] $Type)
        $key = $Type.ToLowerInvariant()
        if (-not $rowsByType.ContainsKey($key)) { return }
        return $rowsByType[$key]
    }

    function Select-ByAnyType {
        param([string[]] $Types)
        # Multi-type KQL projections preserve global ARG row order. Keep that contract for the
        # handful of multi-type datasets; the high-volume single-type paths use the O(1) index.
        $selectedTypes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($type in $Types) { [void]$selectedTypes.Add($type) }
        return $rows | Where-Object { $selectedTypes.Contains([string](Get-ScoutProp $_ 'type')) }
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
                    # AB#9300 (depth wiring) -- mirrors the KQL: the length of the management group chain
                    # (tenant root included). Null when the chain is absent, never 0.
                    managementGroupLevels = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.managementGroupAncestorsChain')
                }
            }
    )

    # ---- deployments (resource groups) ----
    # One row per resource group. When ARM deployment history was collected (Resource Graph's
    # deploymentresources table), a resource group that has at least one template deployment also
    # carries properties.templateHash (its most recent one) and properties.templateDeploymentCount,
    # which is what the infrastructure-as-code rules test (`deployments[?(@.properties.templateHash)]`).
    # Before AB#9300 no row ever carried it, so those rules could never pass.
    $templateDeploymentsByGroup = @{}
    foreach ($deployment in @(Select-ByType 'microsoft.resources/deployments')) {
        $hash = [string] (Get-ScoutProp $deployment 'properties.templateHash')
        $deploymentGroup = [string] (Get-ScoutProp $deployment 'resourceGroup')
        if ([string]::IsNullOrWhiteSpace($hash) -or [string]::IsNullOrWhiteSpace($deploymentGroup)) { continue }
        $groupKey = ('{0}|{1}' -f [string] (Get-ScoutProp $deployment 'subscriptionId'), $deploymentGroup).ToLowerInvariant()
        if (-not $templateDeploymentsByGroup.ContainsKey($groupKey)) { $templateDeploymentsByGroup[$groupKey] = [System.Collections.Generic.List[object]]::new() }
        $templateDeploymentsByGroup[$groupKey].Add($deployment)
    }
    $result['deployments'] = @(
        $containers |
            Where-Object { [string] (Get-ScoutProp $_ 'type') -ieq 'microsoft.resources/subscriptions/resourcegroups' } |
            ForEach-Object {
                $row = [ordered]@{
                    name           = [string] (Get-ScoutProp $_ 'name')
                    subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                }
                $groupKey = ('{0}|{1}' -f $row.subscriptionId, $row.name).ToLowerInvariant()
                if ($templateDeploymentsByGroup.ContainsKey($groupKey)) {
                    $templated = @($templateDeploymentsByGroup[$groupKey] | Sort-Object { [string] (Get-ScoutProp $_ 'properties.timestamp') } -Descending)
                    $row['properties'] = [pscustomobject]@{
                        templateHash            = [string] (Get-ScoutProp $templated[0] 'properties.templateHash')
                        templateDeploymentCount = $templated.Count
                    }
                }
                [pscustomobject]$row
            }
    )

    # ---- networking ----
    $virtualNetworks = Select-ByType 'microsoft.network/virtualnetworks'
    $result['virtualNetworks'] = @(
        $virtualNetworks | ForEach-Object {
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                location         = [string] (Get-ScoutProp $_ 'location')
                peeringCount     = Measure-ScoutArray (Get-ScoutProp $_ 'properties.virtualNetworkPeerings')
                ddosEnabled      = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableDdosProtection')
                # AB#9300 phase 4 -- mirrors Invoke-Collect.ps1's virtualNetworks KQL field for field.
                encryptionEnabled = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.encryption.enabled')
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
                name            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup   = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId  = [string] (Get-ScoutProp $_ 'subscriptionId')
                # properties.sku.name is only AZFW_VNet / AZFW_Hub; the tier a rule needs is
                # properties.sku.tier (AB#9300 phase 4, mirrors the KQL field for field).
                sku             = [string] (Get-ScoutProp $_ 'properties.sku.name')
                tier            = [string] (Get-ScoutProp $_ 'properties.sku.tier')
                zoneCount       = Measure-ScoutArray (Get-ScoutPropArray $_ 'zones')
                hasPolicy       = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.firewallPolicy.id'))
                threatIntelMode = [string] (Get-ScoutProp $_ 'properties.threatIntelMode')
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
            $connections = @(Get-ScoutProp $_ 'properties.privateLinkServiceConnections')
            $connection = if ($connections.Count -gt 0) { $connections[0] } else { $null }
            if ($null -eq $connection) {
                $manualConnections = @(Get-ScoutProp $_ 'properties.manualPrivateLinkServiceConnections')
                $connection = if ($manualConnections.Count -gt 0) { $manualConnections[0] } else { $null }
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

    # ---- AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Networking(13) coverage gap.
    # Every shaper below mirrors Invoke-Collect.ps1's KQL field for field, same standard as the
    # rest of this file.
    $result['applicationGateways'] = @(
        Select-ByType 'microsoft.network/applicationgateways' | ForEach-Object {
            # AB#6928 -- wafEnabled mirrors the KQL: a WAF-capable tier AND (classic WAF config
            # enabled OR a firewall policy attached).
            $tier         = [string] (Get-ScoutProp $_ 'properties.sku.tier')
            $wafCfg       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.webApplicationFirewallConfiguration.enabled')
            $fwPolicyId   = [string] (Get-ScoutProp $_ 'properties.firewallPolicy.id')
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'properties.sku.name')
                tier              = $tier
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                wafEnabled        = [bool] (($tier -like '*WAF*') -and (($wafCfg -eq $true) -or -not [string]::IsNullOrEmpty($fwPolicyId)))
                listenerCount     = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.httpListeners')
                backendPoolCount  = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.backendAddressPools')
                # AB#9300 phase 4 -- mirrors the KQL field for field. sslCertificates is NEVER read
                # (certificate data); only the TLS policy that governs the listeners is.
                zoneCount         = Measure-ScoutArray (Get-ScoutPropArray $_ 'zones')
                autoscaleMin      = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.autoscaleConfiguration.minCapacity')
                autoscaleMax      = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.autoscaleConfiguration.maxCapacity')
                probeCount        = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.probes')
                sslPolicyType     = [string] (Get-ScoutProp $_ 'properties.sslPolicy.policyType')
                sslPolicyName     = [string] (Get-ScoutProp $_ 'properties.sslPolicy.policyName')
                sslMinProtocol    = [string] (Get-ScoutProp $_ 'properties.sslPolicy.minProtocolVersion')
            }
        }
    )

    $result['bastionHosts'] = @(
        Select-ByType 'microsoft.network/bastionhosts' | ForEach-Object {
            # AB#6928 -- owning VNet parsed from the ipConfiguration subnet id, segment index 8
            # (/subscriptions/../virtualNetworks/<vnet>/subnets/<subnet>), same as the KQL split.
            # Assign BEFORE @(): Get-ScoutPropArray comma-wraps its result, so an inline
            # @(Get-ScoutPropArray ...) collects the inner array as ONE element.
            $ipConfigsRaw = Get-ScoutPropArray $_ 'properties.ipConfigurations'
            $ipConfigs = @($ipConfigsRaw)
            $subnetId  = if ($ipConfigs.Count -gt 0 -and $null -ne $ipConfigs[0]) {
                [string] (Get-ScoutProp $ipConfigs[0] 'properties.subnet.id')
            } else { '' }
            $subnetSegments = $subnetId.Split('/')
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                vnet              = if ($subnetSegments.Count -gt 8) { $subnetSegments[8] } else { '' }
            }
        }
    )

    $result['networkConnections'] = @(
        Select-ByType 'microsoft.network/connections' | ForEach-Object {
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                location         = [string] (Get-ScoutProp $_ 'location')
                connectionType   = [string] (Get-ScoutProp $_ 'properties.connectionType')
                connectionStatus = [string] (Get-ScoutProp $_ 'properties.connectionStatus')
            }
        }
    )

    $result['expressRouteCircuits'] = @(
        Select-ByType 'microsoft.network/expressroutecircuits' | ForEach-Object {
            [pscustomobject]@{
                id                                = [string] (Get-ScoutProp $_ 'id')
                name                               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup                      = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId                     = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                           = [string] (Get-ScoutProp $_ 'location')
                sku                                = [string] (Get-ScoutProp $_ 'sku.name')
                circuitProvisioningState           = [string] (Get-ScoutProp $_ 'properties.circuitProvisioningState')
                serviceProviderProvisioningState   = [string] (Get-ScoutProp $_ 'properties.serviceProviderProvisioningState')
                # AB#6928 -- provider relationship scalars, mirrors the extended KQL projection.
                serviceProviderName                = [string] (Get-ScoutProp $_ 'properties.serviceProviderProperties.serviceProviderName')
                peeringLocation                    = [string] (Get-ScoutProp $_ 'properties.serviceProviderProperties.peeringLocation')
                bandwidthInMbps                    = $(
                    $bwRaw = Get-ScoutProp $_ 'properties.serviceProviderProperties.bandwidthInMbps'
                    if ($null -eq $bwRaw) { $null } else { [int] $bwRaw }
                )
            }
        }
    )

    $result['frontDoors'] = @(
        Select-ByType 'microsoft.network/frontdoors' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                # AB#6928 -- classic Front Door carries no sku block; empty string keeps the
                # contract shape stable, mirroring the KQL tostring(sku.name).
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                enabledState      = [string] (Get-ScoutProp $_ 'properties.enabledState')
                endpointCount     = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.frontendEndpoints')
            }
        }
    )

    $result['loadBalancers'] = @(
        Select-ByType 'microsoft.network/loadbalancers' | ForEach-Object {
            # AB#6928 -- hasPublicFrontend: any frontend config carrying the publicIPAddress
            # relationship (the key only appears on ARM payloads when a public IP is bound),
            # mirroring the KQL serialized-contains probe.
            $hasPublicFrontend = $false
            # AB#9300 phase 4 -- minFrontendZoneCount is the WEAKEST frontend's zone count, 0 when
            # a frontend carries no zones or the load balancer has no frontend at all (the KQL
            # swaps an absent/empty array for a one-element placeholder, which also reads 0).
            $minFrontendZones = $null
            # Assign BEFORE @(): Get-ScoutPropArray comma-wraps its result, so an inline
            # @(Get-ScoutPropArray ...) collects the inner array as ONE element.
            $feConfigs = Get-ScoutPropArray $_ 'properties.frontendIPConfigurations'
            foreach ($fe in @($feConfigs)) {
                if ($null -eq $fe) { continue }
                if ($null -ne (Get-ScoutProp $fe 'properties.publicIPAddress')) { $hasPublicFrontend = $true }
                $feZones = Measure-ScoutArray (Get-ScoutPropArray $fe 'zones')
                $feZoneCount = if ($null -eq $feZones) { 0 } else { $feZones }
                if ($null -eq $minFrontendZones -or $feZoneCount -lt $minFrontendZones) { $minFrontendZones = $feZoneCount }
            }
            if ($null -eq $minFrontendZones) { $minFrontendZones = 0 }
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'sku.name')
                tier                = [string] (Get-ScoutProp $_ 'sku.tier')
                frontendIpCount     = Measure-ScoutArray (Get-ScoutProp $_ 'properties.frontendIPConfigurations')
                backendPoolCount    = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.backendAddressPools')
                hasPublicFrontend   = $hasPublicFrontend
                probeCount          = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.probes')
                ruleCount           = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.loadBalancingRules')
                outboundRuleCount   = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.outboundRules')
                minFrontendZoneCount = $minFrontendZones
            }
        }
    )

    $result['natGateways'] = @(
        Select-ByType 'microsoft.network/natgateways' | ForEach-Object {
            $idleRaw = Get-ScoutProp $_ 'properties.idleTimeoutInMinutes'
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId       = [string] (Get-ScoutProp $_ 'subscriptionId')
                location             = [string] (Get-ScoutProp $_ 'location')
                sku                  = [string] (Get-ScoutProp $_ 'sku.name')
                idleTimeoutInMinutes = if ($null -eq $idleRaw) { $null } else { [int] $idleRaw }
                # AB#6928 -- Get-ScoutPropArray so a present-but-empty array reads 0 like KQL
                # array_length(), not $null.
                publicIpCount        = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.publicIpAddresses')
                subnetCount          = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.subnets')
            }
        }
    )

    $result['networkInterfaces'] = @(
        Select-ByType 'microsoft.network/networkinterfaces' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                nsgAttached    = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.networkSecurityGroup.id'))
                privateIpCount = Measure-ScoutArray (Get-ScoutProp $_ 'properties.ipConfigurations')
            }
        }
    )

    $result['networkWatchers'] = @(
        Select-ByType 'microsoft.network/networkwatchers' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['publicDnsZones'] = @(
        Select-ByType 'microsoft.network/dnszones' | ForEach-Object {
            $recordRaw = Get-ScoutProp $_ 'properties.numberOfRecordSets'
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                zoneType       = [string] (Get-ScoutProp $_ 'properties.zoneType')
                recordSetCount = if ($null -eq $recordRaw) { $null } else { [int] $recordRaw }
            }
        }
    )

    $result['routeTables'] = @(
        Select-ByType 'microsoft.network/routetables' | ForEach-Object {
            # AB#6928 -- per-route summary string ("name:prefix->nextHopType; ...") plus any
            # 0.0.0.0/0 route's next hop as a scalar, mirroring the KQL leftouter-join shape.
            $routeItems = Get-ScoutPropArray $_ 'properties.routes'
            $routeStrs  = [System.Collections.Generic.List[string]]::new()
            $defaultHops = [System.Collections.Generic.List[string]]::new()
            foreach ($route in @($routeItems)) {
                if ($null -eq $route) { continue }
                $prefix  = [string] (Get-ScoutProp $route 'properties.addressPrefix')
                $nextHop = [string] (Get-ScoutProp $route 'properties.nextHopType')
                $routeStrs.Add(('{0}:{1}->{2}' -f [string] (Get-ScoutProp $route 'name'), $prefix, $nextHop))
                if ($prefix -eq '0.0.0.0/0' -and -not [string]::IsNullOrEmpty($nextHop)) { $defaultHops.Add($nextHop) }
            }
            [pscustomobject]@{
                id                          = [string] (Get-ScoutProp $_ 'id')
                name                        = [string] (Get-ScoutProp $_ 'name')
                resourceGroup               = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId              = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                    = [string] (Get-ScoutProp $_ 'location')
                # Get-ScoutPropArray (not Get-ScoutProp): a present-but-EMPTY routes array must
                # read 0 like KQL array_length(), not collapse to $null (AB#6928).
                routeCount                  = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.routes')
                subnetCount                 = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.subnets')
                disableBgpRoutePropagation  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableBgpRoutePropagation')
                routes                      = ($routeStrs -join '; ')
                # KQL side uses max() over the per-route hop strings; a list this short makes
                # "the maximum" and "the one hop" the same answer on any real table.
                defaultRouteNextHopType     = $(if ($defaultHops.Count -gt 0) { @($defaultHops | Sort-Object)[-1] } else { '' })
            }
        }
    )

    $result['trafficManagerProfiles'] = @(
        Select-ByType 'microsoft.network/trafficmanagerprofiles' | ForEach-Object {
            # AB#9300 (depth wiring) -- mirrors the KQL: how many endpoints have AlwaysServe on.
            $endpointList = Get-ScoutPropArray $_ 'properties.endpoints'
            $alwaysServeEndpoints = @(@($endpointList) | Where-Object {
                    $null -ne $_ -and ([string] (Get-ScoutProp $_ 'properties.alwaysServe')) -ieq 'Enabled'
                }).Count
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId       = [string] (Get-ScoutProp $_ 'subscriptionId')
                location             = [string] (Get-ScoutProp $_ 'location')
                profileStatus        = [string] (Get-ScoutProp $_ 'properties.profileStatus')
                trafficRoutingMethod = [string] (Get-ScoutProp $_ 'properties.trafficRoutingMethod')
                # AB#6928 -- profile-level probe verdict + endpoint count, mirrors the KQL.
                monitorStatus        = [string] (Get-ScoutProp $_ 'properties.monitorConfig.profileMonitorStatus')
                endpointCount        = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.endpoints')
                dnsTtl               = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.dnsConfig.ttl')
                alwaysServeEndpointCount = $alwaysServeEndpoints
            }
        }
    )

    $result['virtualWans'] = @(
        Select-ByType 'microsoft.network/virtualwans' | ForEach-Object {
            [pscustomobject]@{
                id                         = [string] (Get-ScoutProp $_ 'id')
                name                       = [string] (Get-ScoutProp $_ 'name')
                resourceGroup              = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId             = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                   = [string] (Get-ScoutProp $_ 'location')
                wanType                    = [string] (Get-ScoutProp $_ 'properties.type')
                allowBranchToBranchTraffic = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.allowBranchToBranchTraffic')
            }
        }
    )

    # ---- AB#6928 -- connectivity relationship detail ----
    # Mirrors the four AB#6928 typed KQL projections field for field. The last id segment IS
    # the resource name on every well-formed ARM id (same value the KQL split(...)[8] takes);
    # [-1] avoids the StrictMode out-of-bounds throw a fixed index would risk on a short id.
    function Get-ScoutNameFromId {
        param([AllowNull()] [string] $Id)
        if ([string]::IsNullOrEmpty($Id)) { return '' }
        return [string] (@($Id -split '/')[-1])
    }

    $result['vnetPeerings'] = @(
        foreach ($vnet in $virtualNetworks) {
            # Assign-then-wrap: `@(Get-ScoutPropArray ...)` used INLINE keeps the function's
            # `, @()` wrapper as a single element instead of enumerating the peerings.
            $peeringItems = Get-ScoutPropArray $vnet 'properties.virtualNetworkPeerings'
            foreach ($peering in @($peeringItems)) {
                if ($null -eq $peering) { continue }
                $remoteVnetId = [string] (Get-ScoutProp $peering 'properties.remoteVirtualNetwork.id')
                [pscustomobject]@{
                    vnet                = [string] (Get-ScoutProp $vnet 'name')
                    resourceGroup       = [string] (Get-ScoutProp $vnet 'resourceGroup')
                    subscriptionId      = [string] (Get-ScoutProp $vnet 'subscriptionId')
                    remoteVnetId        = $remoteVnetId
                    remoteVnetName      = Get-ScoutNameFromId $remoteVnetId
                    peeringState        = [string] (Get-ScoutProp $peering 'properties.peeringState')
                    allowGatewayTransit = ConvertTo-ScoutBool (Get-ScoutProp $peering 'properties.allowGatewayTransit')
                    useRemoteGateways   = ConvertTo-ScoutBool (Get-ScoutProp $peering 'properties.useRemoteGateways')
                }
            }
        }
    )

    $result['vpnConnections'] = @(
        Select-ByType 'microsoft.network/connections' | ForEach-Object {
            $prefixItems = Get-ScoutPropArray $_ 'properties.localNetworkGateway2.properties.localNetworkAddressSpace.addressPrefixes'
            [pscustomobject]@{
                name                    = [string] (Get-ScoutProp $_ 'name')
                resourceGroup           = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId          = [string] (Get-ScoutProp $_ 'subscriptionId')
                gatewayName             = Get-ScoutNameFromId ([string] (Get-ScoutProp $_ 'properties.virtualNetworkGateway1.id'))
                connectionType          = [string] (Get-ScoutProp $_ 'properties.connectionType')
                connectionStatus        = [string] (Get-ScoutProp $_ 'properties.connectionStatus')
                localNetworkGatewayName = Get-ScoutNameFromId ([string] (Get-ScoutProp $_ 'properties.localNetworkGateway2.id'))
                localAddressPrefixes    = (@(@($prefixItems) | Where-Object { $null -ne $_ } | ForEach-Object { [string] $_ }) -join ',')
                # BOOL ONLY -- the pre-shared key VALUE is never shaped into the payload.
                sharedKeyPresent        = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.sharedKey'))
            }
        }
    )

    $result['localNetworkGateways'] = @(
        Select-ByType 'microsoft.network/localnetworkgateways' | ForEach-Object {
            $prefixItems = Get-ScoutPropArray $_ 'properties.localNetworkAddressSpace.addressPrefixes'
            [pscustomobject]@{
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                gatewayIpAddress = [string] (Get-ScoutProp $_ 'properties.gatewayIpAddress')
                addressPrefixes  = (@(@($prefixItems) | Where-Object { $null -ne $_ } | ForEach-Object { [string] $_ }) -join ',')
            }
        }
    )

    $result['virtualHubs'] = @(
        Select-ByType 'microsoft.network/virtualhubs' | ForEach-Object {
            # AB#9300 (depth wiring) -- mirrors the KQL. The gateways' ids are never carried, only whether
            # each exists; an unset routing preference is ExpressRoute, the platform default.
            $hubHasErGateway = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.expressRouteGateway.id'))
            $hubHasVpnGateway = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.vpnGateway.id'))
            $hubRoutingPreference = [string] (Get-ScoutProp $_ 'properties.hubRoutingPreference')
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                addressPrefix  = [string] (Get-ScoutProp $_ 'properties.addressPrefix')
                virtualWanName = Get-ScoutNameFromId ([string] (Get-ScoutProp $_ 'properties.virtualWan.id'))
                hasExpressRouteGateway = $hubHasErGateway
                hasVpnGateway          = $hubHasVpnGateway
                routingPreference      = $hubRoutingPreference
                expressRouteBackedUp   = ($hubHasErGateway -and $hubHasVpnGateway -and ($hubRoutingPreference -in 'ExpressRoute', ''))
            }
        }
    )

    # AB#7091 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Networking coverage-gap
    # close-out. Route Server and Azure Enclave are deliberately not shaped here -- see the
    # cdnProfiles KQL comment in Invoke-Collect.ps1 and docs/reference/service-coverage-gap.md.
    $result['cdnProfiles'] = @(
        Select-ByType 'microsoft.cdn/profiles' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                frontDoorId       = [string] (Get-ScoutProp $_ 'properties.frontDoorId')
            }
        }
    )

    $result['networkManagers'] = @(
        Select-ByType 'microsoft.network/networkmanagers' | ForEach-Object {
            $accessItems = Get-ScoutPropArray $_ 'properties.networkManagerScopeAccesses'
            [pscustomobject]@{
                id                     = [string] (Get-ScoutProp $_ 'id')
                name                   = [string] (Get-ScoutProp $_ 'name')
                resourceGroup          = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId         = [string] (Get-ScoutProp $_ 'subscriptionId')
                location               = [string] (Get-ScoutProp $_ 'location')
                provisioningState      = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                scopeSubscriptionCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.networkManagerScopes.subscriptions')
                scopeAccesses          = (@(@($accessItems) | Where-Object { $null -ne $_ } | ForEach-Object { [string] $_ }) -join ',')
            }
        }
    )

    $result['firewallPolicies'] = @(
        Select-ByType 'microsoft.network/firewallpolicies' | ForEach-Object {
            # AB#9300 (depth wiring) -- mirrors the KQL: booleans only. The CA's name and Key Vault secret
            # id are never carried, just whether one is configured.
            $idpsOn = ([string] (Get-ScoutProp $_ 'properties.intrusionDetection.mode')) -in 'Alert', 'Deny'
            $tlsOn = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.transportSecurity.certificateAuthority.keyVaultSecretId'))
            $dnsProxyOn = (ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.dnsSettings.enableProxy')) -eq $true
            [pscustomobject]@{
                id                       = [string] (Get-ScoutProp $_ 'id')
                name                     = [string] (Get-ScoutProp $_ 'name')
                resourceGroup            = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId           = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                 = [string] (Get-ScoutProp $_ 'location')
                sku                      = [string] (Get-ScoutProp $_ 'properties.sku.tier')
                provisioningState        = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                threatIntelMode          = [string] (Get-ScoutProp $_ 'properties.threatIntelMode')
                ruleCollectionGroupCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.ruleCollectionGroups')
                idpsEnabled              = $idpsOn
                tlsInspectionEnabled     = $tlsOn
                dnsProxyEnabled          = $dnsProxyOn
                hasBasePolicy            = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.basePolicy.id'))
                idpsTlsDnsEnabled        = ($idpsOn -and $tlsOn -and $dnsProxyOn)
            }
        }
    )

    $result['networkFunctions'] = @(
        Select-ByType 'microsoft.hybridnetwork/networkfunctions' | ForEach-Object {
            [pscustomobject]@{
                id                      = [string] (Get-ScoutProp $_ 'id')
                name                    = [string] (Get-ScoutProp $_ 'name')
                resourceGroup           = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId          = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                = [string] (Get-ScoutProp $_ 'location')
                provisioningState       = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                vendorProvisioningState = [string] (Get-ScoutProp $_ 'properties.vendorProvisioningState')
                serviceKey              = [string] (Get-ScoutProp $_ 'properties.serviceKey')
            }
        }
    )

    # ---- AB#9300 phase 4 -- Networking types that had no dataset. Mirrors Invoke-Collect.ps1's
    # `publicIPAddresses` / `flowLogs` KQL field for field.
    # attached = the address is bound to an IP configuration (NIC, load balancer frontend,
    # firewall, gateway). A NAT-gateway-only address carries properties.natGateway instead and
    # reads attached = false, exactly as the KQL does.
    $result['publicIPAddresses'] = @(
        Select-ByType 'microsoft.network/publicipaddresses' | ForEach-Object {
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                location           = [string] (Get-ScoutProp $_ 'location')
                skuName            = [string] (Get-ScoutProp $_ 'sku.name')
                skuTier            = [string] (Get-ScoutProp $_ 'sku.tier')
                zoneCount          = Measure-ScoutArray (Get-ScoutPropArray $_ 'zones')
                ddosProtectionMode = [string] (Get-ScoutProp $_ 'properties.ddosSettings.protectionMode')
                allocationMethod   = [string] (Get-ScoutProp $_ 'properties.publicIPAllocationMethod')
                attached           = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.ipConfiguration.id'))
            }
        }
    )

    # Neither the storage account nor the Log Analytics workspace a flow log writes to is shaped
    # (their ids are never read) -- only whether the log is on, its retention and whether Traffic
    # Analytics is enabled. targetResourceId is lower-cased, like the KQL tolower().
    $result['flowLogs'] = @(
        Select-ByType 'microsoft.network/networkwatchers/flowlogs' | ForEach-Object {
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                enabled          = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enabled')
                targetResourceId = ([string] (Get-ScoutProp $_ 'properties.targetResourceId')).ToLowerInvariant()
                retentionEnabled = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.retentionPolicy.enabled')
                retentionDays    = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.retentionPolicy.days')
                trafficAnalytics = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.enabled')
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
                location       = [string] (Get-ScoutProp $_ 'location')
                zoneRedundant  = ($null -ne $zoneCount -and $zoneCount -gt 0)
                zoneEligible   = $zoneEligibleRegions -contains ([string] (Get-ScoutProp $_ 'location')).ToLowerInvariant()
                size           = [string] (Get-ScoutProp $_ 'properties.hardwareProfile.vmSize')
                # Must mirror Invoke-Collect.ps1's virtualMachines KQL projection field for
                # field -- a combined inventory + assessment run shapes VMs HERE instead, and a
                # rule that reads licenseType would silently see nothing on that path. Empty
                # string means AHB is not configured (Azure omits licenseType entirely unless
                # set), which is the finding itself, not absent data.
                licenseType    = [string] (Get-ScoutProp $_ 'properties.licenseType')
                osType         = [string] (Get-ScoutProp $_ 'properties.storageProfile.osDisk.osType')
                # AB#7109 -- mirrors Invoke-Collect.ps1's virtualMachines KQL field for field.
                patchMode      = [string] (Get-ScoutOsPatchSetting -Resource $_ -Field 'patchMode')
                assessmentMode = [string] (Get-ScoutOsPatchSetting -Resource $_ -Field 'assessmentMode')
                # AB#9300 phase 4 -- mirrors the KQL field for field. unmanagedOsDisk is a BOOL ONLY:
                # an unmanaged disk's vhd.uri names the backing storage account and is never shaped.
                inAvailabilitySet = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.availabilitySet.id'))
                unmanagedOsDisk   = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.storageProfile.osDisk.vhd.uri'))
                osDiskType        = [string] (Get-ScoutProp $_ 'properties.storageProfile.osDisk.managedDisk.storageAccountType')
                securityType      = [string] (Get-ScoutProp $_ 'properties.securityProfile.securityType')
                encryptionAtHost  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.securityProfile.encryptionAtHost')
                bootDiagnostics   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.diagnosticsProfile.bootDiagnostics.enabled')
                identityType      = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    # AB#9300 phase 4 -- Virtual Machine Scale Sets had no dataset. Mirrors Invoke-Collect.ps1's
    # `virtualMachineScaleSets` KQL field for field.
    $result['virtualMachineScaleSets'] = @(
        Select-ByType 'microsoft.compute/virtualmachinescalesets' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                location          = [string] (Get-ScoutProp $_ 'location')
                zoneCount         = Measure-ScoutArray (Get-ScoutPropArray $_ 'zones')
                orchestrationMode = [string] (Get-ScoutProp $_ 'properties.orchestrationMode')
                automaticRepairs  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.automaticRepairsPolicy.enabled')
                upgradeMode       = [string] (Get-ScoutProp $_ 'properties.upgradePolicy.mode')
                zoneBalance       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneBalance')
                capacity          = ConvertTo-ScoutInt (Get-ScoutProp $_ 'sku.capacity')
                encryptionAtHost  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.virtualMachineProfile.securityProfile.encryptionAtHost')
            }
        }
    )

    # AB#6820 -- mirrors Invoke-Collect.ps1's `privateClouds` KQL field for field so a combined
    # inventory + assessment run shapes AVS private clouds from the one raw pass instead of
    # issuing a second, live ARG round-trip for them.
    #
    # AB#9300, 3.18.19 -- the private cloud's own extended properties, mirrored the same way: the
    # second zone and circuit of a stretched cloud, provisioning state, DNS zone type, the COUNT of
    # extended network blocks, the NSX public IP quota, whether a virtual network id is set (a Gen 2
    # cloud), the managed identity type and the customer-managed key's health. Never a password, a
    # licence key, a thumbprint, an address block, an endpoint or a key name / version / vault URL.
    $result['privateClouds'] = @(
        Select-ByType 'microsoft.avs/privateclouds' | ForEach-Object {
            $identitySourceCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.identitySources')
            $externalCloudLinkCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.externalCloudLinks')
            $extendedNetworkBlockCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.extendedNetworkBlocks')
            $clusterSizeRaw = Get-ScoutProp $_ 'properties.managementCluster.clusterSize'
            [pscustomobject]@{
                id                      = [string] (Get-ScoutProp $_ 'id')
                name                    = [string] (Get-ScoutProp $_ 'name')
                resourceGroup           = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId          = [string] (Get-ScoutProp $_ 'subscriptionId')
                sku                     = [string] (Get-ScoutProp $_ 'sku.name')
                availabilityStrategy    = [string] (Get-ScoutProp $_ 'properties.availability.strategy')
                availabilityZone        = [string] (Get-ScoutProp $_ 'properties.availability.zone')
                availabilitySecondaryZone = [string] (Get-ScoutProp $_ 'properties.availability.secondaryZone')
                clusterSize             = if ($null -eq $clusterSizeRaw) { $null } else { [int] $clusterSizeRaw }
                expressRouteCircuitId   = [string] (Get-ScoutProp $_ 'properties.circuit.expressRouteID')
                secondaryCircuitPresent = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.secondaryCircuit.expressRouteID'))
                encryptionStatus        = [string] (Get-ScoutProp $_ 'properties.encryption.status')
                encryptionKeyState      = [string] (Get-ScoutProp $_ 'properties.encryption.keyVaultProperties.keyState')
                encryptionKeyVersionType = [string] (Get-ScoutProp $_ 'properties.encryption.keyVaultProperties.versionType')
                internet                = [string] (Get-ScoutProp $_ 'properties.internet')
                identitySourceCount     = $identitySourceCount
                externalCloudLinkCount  = $externalCloudLinkCount
                provisioningState       = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                dnsZoneType             = [string] (Get-ScoutProp $_ 'properties.dnsZoneType')
                extendedNetworkBlockCount = $extendedNetworkBlockCount
                nsxPublicIpQuotaRaised  = [string] (Get-ScoutProp $_ 'properties.nsxPublicIpQuotaRaised')
                virtualNetworkIdSet     = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.virtualNetworkId'))
                identityType            = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    # ---- Compute coverage-gap close-out (AB#7088, folds in AB#7071) — mirrors
    # Invoke-Collect.ps1's `computeFleets`/`batchAccounts`/`dedicatedHostGroups`/
    # `vmImageTemplates`/`quantumWorkspaces`/`nutanixNodes` KQL fields field for field so the
    # inverted (default) path costs no extra round-trip.
    $result['computeFleets'] = @(
        Select-ByType 'microsoft.azurefleet/fleets' | ForEach-Object {
            [pscustomobject]@{
                name                                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup                       = [string] (Get-ScoutProp $_ 'resourceGroup')
                identityType                        = [string] (Get-ScoutProp $_ 'identity.type')
                regularPriorityAllocationStrategy    = [string] (Get-ScoutProp $_ 'properties.regularPriorityProfile.allocationStrategy')
                spotPriorityAllocationStrategy       = [string] (Get-ScoutProp $_ 'properties.spotPriorityProfile.allocationStrategy')
            }
        }
    )

    $result['batchAccounts'] = @(
        Select-ByType 'microsoft.batch/batchaccounts' | ForEach-Object {
            [pscustomobject]@{
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                poolAllocationMode   = [string] (Get-ScoutProp $_ 'properties.poolAllocationMode')
                publicNetworkAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType         = [string] (Get-ScoutProp $_ 'identity.type')
                encryptionKeySource  = [string] (Get-ScoutProp $_ 'properties.encryption.keySource')
            }
        }
    )

    $result['dedicatedHostGroups'] = @(
        Select-ByType 'microsoft.compute/hostgroups' | ForEach-Object {
            $faultDomainRaw = Get-ScoutProp $_ 'properties.platformFaultDomainCount'
            $autoPlacementRaw = Get-ScoutProp $_ 'properties.supportAutomaticPlacement'
            $ultraSsdRaw = Get-ScoutProp $_ 'properties.additionalCapabilities.ultraSSDEnabled'
            [pscustomobject]@{
                name                      = [string] (Get-ScoutProp $_ 'name')
                resourceGroup             = [string] (Get-ScoutProp $_ 'resourceGroup')
                platformFaultDomainCount  = if ($null -eq $faultDomainRaw) { $null } else { [int] $faultDomainRaw }
                supportAutomaticPlacement = if ($null -eq $autoPlacementRaw) { $null } else { [bool] $autoPlacementRaw }
                ultraSsdEnabled           = if ($null -eq $ultraSsdRaw) { $null } else { [bool] $ultraSsdRaw }
            }
        }
    )

    $result['vmImageTemplates'] = @(
        Select-ByType 'microsoft.virtualmachineimages/imagetemplates' | ForEach-Object {
            $buildTimeoutRaw = Get-ScoutProp $_ 'properties.buildTimeoutInMinutes'
            [pscustomobject]@{
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                sourceType          = [string] (Get-ScoutProp $_ 'properties.source.type')
                buildTimeoutMinutes = if ($null -eq $buildTimeoutRaw) { $null } else { [int] $buildTimeoutRaw }
                identityType        = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    $result['quantumWorkspaces'] = @(
        Select-ByType 'microsoft.quantum/workspaces' | ForEach-Object {
            $apiKeyRaw = Get-ScoutProp $_ 'properties.apiKeyEnabled'
            $providerCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.providers')
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                apiKeyEnabled  = if ($null -eq $apiKeyRaw) { $null } else { [bool] $apiKeyRaw }
                identityType   = [string] (Get-ScoutProp $_ 'identity.type')
                providerCount  = $providerCount
            }
        }
    )

    $result['nutanixNodes'] = @(
        Select-ByType 'microsoft.nutanix/nodes' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                skuName       = [string] (Get-ScoutProp $_ 'sku.name')
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

    # ---- ops posture: diagnostic-settings coverage by resource type ----
    # Diagnostic settings are ARM extension resources: Resource Graph indexes them in no table, and
    # `properties.diagnosticSettings` exists on no resource. The old shaping counted that property,
    # so every type read 0% in every tenant and CAF-MGT-01/05 and WAF-OE-01 failed everywhere
    # (AB#9300). Coverage now comes from the ResourceDiagnosticSettings ARM sweep: a resource
    # counts as CHECKED when its GET succeeded (Success = has settings, Empty = has none), and as
    # COVERED when at least one setting row came back for it. Resources whose GET failed or that
    # the sweep does not visit are not counted at all -- unmeasured is not 0%. With no sweep in
    # the run, diagnosticCoverageMeasured is false and the rules that read coverage gate to
    # NotAssessed instead of failing.
    $diagnosticOperations = @(@($SourceOperations) | Where-Object {
            $null -ne $_ -and $_.PSObject.Properties['Dataset'] -and [string]$_.Dataset -eq 'ResourceDiagnosticSettings'
        })
    $result['diagnosticCoverageMeasured'] = $diagnosticOperations.Count -gt 0
    $typeById = @{}
    foreach ($row in $rows) {
        $rowId = [string](Get-ScoutProp $row 'id')
        if ($rowId) { $typeById[$rowId.ToLowerInvariant()] = ([string](Get-ScoutProp $row 'type')).ToLowerInvariant() }
    }
    $checkedParents = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($operation in $diagnosticOperations) {
        if ([string]$operation.Status -notin 'Success', 'Empty') { continue }
        $uri = [string]$operation.Uri
        $marker = $uri.IndexOf('/providers/Microsoft.Insights/diagnosticSettings', [StringComparison]::OrdinalIgnoreCase)
        if ($marker -le 0) { continue }
        $parentPath = $uri.Substring(0, $marker)
        $schemeEnd = $parentPath.IndexOf('/subscriptions/', [StringComparison]::OrdinalIgnoreCase)
        if ($schemeEnd -gt 0) { $parentPath = $parentPath.Substring($schemeEnd) }
        [void]$checkedParents.Add($parentPath)
    }
    $coveredParents = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @(Select-ByType 'AZSC/ARMChild/ResourceDiagnosticSettings')) {
        $parentId = [string](Get-ScoutProp $row 'PARENTID')
        if ($parentId) { [void]$coveredParents.Add($parentId) }
    }
    $result['diagnosticCoverage'] = @(
        @($checkedParents) | Group-Object {
            $known = $typeById[$_.ToLowerInvariant()]
            if ($known) { $known } else { 'unknown' }
        } | Where-Object { $_.Name -ne 'unknown' } | Sort-Object Name | ForEach-Object {
            $total = $_.Count
            $withDiag = @($_.Group | Where-Object { $coveredParents.Contains($_) }).Count
            [pscustomobject]@{
                type        = $_.Name
                total       = $total
                withDiag    = $withDiag
                coveragePct = if ($total -gt 0) { [Math]::Round(([double] $withDiag / $total) * 100, 1) } else { [double] 0 }
            }
        }
    )
    # ---- per-resource settings from one ARM GET each (AB#9300 phase 4, batch 2) ---------------------
    # Eight datasets Resource Graph cannot supply, collected by Get-ScoutArmChildResource (one GET
    # per parent) and shaped here. Every dataset is keyed by the PARENT's resource id, lower-cased,
    # in a field named for the parent (storageAccountId, sqlServerId, webAppId, eventHubNamespaceId,
    # redisEnterpriseId) so a rule's join can match it to the parent dataset's `id`.
    #
    # Each dataset has a `<name>Measured` flag that is $true only when at least one GET of that
    # dataset got an ANSWER (Success or Empty). It is not "the sweep was requested": a run where
    # every GET was denied or failed has rows for nobody, and a `countEquals: 0` rule reading that
    # would pass for no reason. Rules gate on the flag and report NotAssessed instead. It is also
    # not "every parent was reached" -- a parent whose GET failed has no row, exactly like
    # diagnosticCoverage, and the failure is in the run's collection health.
    #
    # Two datasets are per-parent SUMMARIES, not row-per-response (sqlFailoverGroups, eventHubGeoDr):
    # for them "the server has no failover group" and "the namespace is not paired" are the finding,
    # and an empty list produces no response row to show it. They emit one row per parent whose GET
    # answered, with a count of 0 where nothing came back, using the ParentId each source operation
    # carries.
    $sweepOperations = @(@($SourceOperations) | Where-Object {
            $null -ne $_ -and $_.PSObject.Properties['Dataset'] -and $_.PSObject.Properties['Status']
        })

    function Test-ScoutSweepMeasured {
        param([Parameter(Mandatory)] [string] $Dataset)
        return @($sweepOperations | Where-Object {
                [string] $_.Dataset -eq $Dataset -and [string] $_.Status -in 'Success', 'Empty'
            }).Count -gt 0
    }

    function Get-ScoutSweepCheckedParent {
        param([Parameter(Mandatory)] [string] $Dataset)
        $checked = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($operation in $sweepOperations) {
            if ([string] $operation.Dataset -ne $Dataset -or [string] $operation.Status -notin 'Success', 'Empty') { continue }
            $operationParent = if ($operation.PSObject.Properties['ParentId']) { [string] $operation.ParentId } else { '' }
            if ($operationParent) { [void] $checked.Add($operationParent.ToLowerInvariant()) }
        }
        return , $checked
    }

    # Name / resource group / subscription for a parent that only has an id to go on: read them off
    # the parent's own row when it is in the inventory, else off the id itself.
    $summaryParentById = @{}
    foreach ($summaryParent in @(Select-ByAnyType @('microsoft.sql/servers', 'microsoft.eventhub/namespaces', 'microsoft.storage/storageaccounts'))) {
        $summaryParentId = [string] (Get-ScoutProp $summaryParent 'id')
        if ($summaryParentId) { $summaryParentById[$summaryParentId.ToLowerInvariant()] = $summaryParent }
    }
    function Get-ScoutSummaryParentFact {
        param([Parameter(Mandatory)] [string] $ParentId)
        $parent = $summaryParentById[$ParentId.ToLowerInvariant()]
        if ($null -ne $parent) {
            return [pscustomobject]@{
                name           = [string] (Get-ScoutProp $parent 'name')
                resourceGroup  = [string] (Get-ScoutProp $parent 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $parent 'subscriptionId')
                location       = [string] (Get-ScoutProp $parent 'location')
            }
        }
        $parsed = [regex]::Match($ParentId, '(?i)^/subscriptions/(?<sub>[^/]+)/resourceGroups/(?<rg>[^/]+)/providers/.+/(?<name>[^/]+)$')
        return [pscustomobject]@{
            name           = if ($parsed.Success) { $parsed.Groups['name'].Value } else { '' }
            resourceGroup  = if ($parsed.Success) { $parsed.Groups['rg'].Value } else { '' }
            subscriptionId = if ($parsed.Success) { $parsed.Groups['sub'].Value } else { '' }
            location       = ''
        }
    }

    function Group-ScoutChildRowByParent {
        param([Parameter(Mandatory)] [string] $Type)
        $grouped = [ordered]@{}
        foreach ($childRow in @(Select-ByType $Type)) {
            $groupKey = ([string] (Get-ScoutProp $childRow 'PARENTID')).ToLowerInvariant()
            if (-not $groupKey) { continue }
            if (-not $grouped.Contains($groupKey)) { $grouped[$groupKey] = [System.Collections.Generic.List[object]]::new() }
            $grouped[$groupKey].Add($childRow)
        }
        return $grouped
    }

    # -- storage: blob service ---------------------------------------------------------------
    # A feature the account never enabled is simply absent from the response (verified live), so
    # each switch reads $true only when the service said true -- see ConvertTo-ScoutFeatureFlag.
    $result['blobServicePropertiesMeasured'] = Test-ScoutSweepMeasured 'StorageBlobServiceProperties'
    $result['blobServiceProperties'] = @(
        Select-ByType 'AZSC/ARMChild/StorageBlobServiceProperties' | ForEach-Object {
            [pscustomobject]@{
                storageAccountId                = ([string] (Get-ScoutProp $_ 'PARENTID')).ToLowerInvariant()
                name                            = [string] (Get-ScoutProp $_ 'PARENTNAME')
                resourceGroup                   = [string] (Get-ScoutProp $_ 'RESOURCEGROUP')
                subscriptionId                  = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                        = [string] (Get-ScoutProp $_ 'PARENTLOCATION')
                deleteRetentionEnabled          = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.deleteRetentionPolicy.enabled')
                deleteRetentionDays             = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.deleteRetentionPolicy.days')
                containerDeleteRetentionEnabled = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.containerDeleteRetentionPolicy.enabled')
                containerDeleteRetentionDays    = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.containerDeleteRetentionPolicy.days')
                versioningEnabled               = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.isVersioningEnabled')
                changeFeedEnabled               = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.changeFeed.enabled')
                pointInTimeRestoreEnabled       = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.restorePolicy.enabled')
            }
        }
    )

    # -- storage: file service ---------------------------------------------------------------
    # The SMB strings are kept exactly as returned. $null is a real answer -- "every version,
    # channel-encryption algorithm and authentication method is allowed" -- not a missing one.
    $result['fileServicePropertiesMeasured'] = Test-ScoutSweepMeasured 'StorageFileServiceProperties'
    $result['fileServiceProperties'] = @(
        Select-ByType 'AZSC/ARMChild/StorageFileServiceProperties' | ForEach-Object {
            [pscustomobject]@{
                storageAccountId           = ([string] (Get-ScoutProp $_ 'PARENTID')).ToLowerInvariant()
                name                       = [string] (Get-ScoutProp $_ 'PARENTNAME')
                resourceGroup              = [string] (Get-ScoutProp $_ 'RESOURCEGROUP')
                subscriptionId             = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                   = [string] (Get-ScoutProp $_ 'PARENTLOCATION')
                shareDeleteRetentionEnabled = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.shareDeleteRetentionPolicy.enabled')
                shareDeleteRetentionDays   = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.shareDeleteRetentionPolicy.days')
                smbVersions                = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.protocolSettings.smb.versions')
                smbChannelEncryption       = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.protocolSettings.smb.channelEncryption')
                smbAuthenticationMethods   = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.protocolSettings.smb.authenticationMethods')
            }
        }
    )

    # -- SQL server auditing -----------------------------------------------------------------
    # Only the state and the Azure Monitor flag. The response also carries
    # storageAccountAccessKey, storageAccountSubscriptionId and storageEndpoint; the collector
    # drops them before a row exists, and nothing here reads them.
    $result['sqlServerAuditingMeasured'] = Test-ScoutSweepMeasured 'SqlServerAuditing'
    $result['sqlServerAuditing'] = @(
        Select-ByType 'AZSC/ARMChild/SqlServerAuditing' | ForEach-Object {
            [pscustomobject]@{
                sqlServerId                 = ([string] (Get-ScoutProp $_ 'PARENTID')).ToLowerInvariant()
                name                        = [string] (Get-ScoutProp $_ 'PARENTNAME')
                resourceGroup               = [string] (Get-ScoutProp $_ 'RESOURCEGROUP')
                subscriptionId              = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                    = [string] (Get-ScoutProp $_ 'PARENTLOCATION')
                auditingState               = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.state')
                azureMonitorTargetEnabled   = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.isAzureMonitorTargetEnabled')
            }
        }
    )

    # -- SQL failover groups (one row per server whose list answered) -------------------------
    # Counts and booleans only. A group's partner servers are other servers' resource ids and are
    # never carried; the collector reduces them to partnerServerCount before the row exists.
    $result['sqlFailoverGroupsMeasured'] = Test-ScoutSweepMeasured 'SqlFailoverGroups'
    $failoverGroupsByServer = Group-ScoutChildRowByParent 'AZSC/ARMChild/SqlFailoverGroups'
    $failoverServers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($checkedServer in (Get-ScoutSweepCheckedParent 'SqlFailoverGroups')) { [void] $failoverServers.Add($checkedServer) }
    foreach ($groupedServer in $failoverGroupsByServer.Keys) { [void] $failoverServers.Add($groupedServer) }
    $result['sqlFailoverGroups'] = @(
        foreach ($serverId in @($failoverServers | Sort-Object)) {
            $groups = @(if ($failoverGroupsByServer.Contains($serverId)) { $failoverGroupsByServer[$serverId] })
            $policies = @($groups | ForEach-Object { Get-ScoutProp $_ 'properties.readWriteEndpoint.failoverPolicy' } |
                    Where-Object { $_ } | ForEach-Object { [string] $_ } | Sort-Object -Unique)
            $automatic = @($groups | Where-Object { ([string] (Get-ScoutProp $_ 'properties.readWriteEndpoint.failoverPolicy')) -ieq 'Automatic' }).Count
            $fact = Get-ScoutSummaryParentFact $serverId
            [pscustomobject]@{
                sqlServerId                 = $serverId
                name                        = $fact.name
                resourceGroup               = $fact.resourceGroup
                subscriptionId              = $fact.subscriptionId
                location                    = $fact.location
                failoverGroupCount          = $groups.Count
                automaticFailoverGroupCount = $automatic
                hasAutomaticFailover        = $automatic -gt 0
                failoverPolicies            = $policies
            }
        }
    )

    # -- web app configuration ---------------------------------------------------------------
    # Seven settings off config/web. App settings and connection strings are not in the allow-
    # list; the health-check PATH is reduced to "is one set".
    $result['webAppConfigMeasured'] = Test-ScoutSweepMeasured 'WebAppConfig'
    $result['webAppConfig'] = @(
        Select-ByType 'AZSC/ARMChild/WebAppConfig' | ForEach-Object {
            [pscustomobject]@{
                webAppId               = ([string] (Get-ScoutProp $_ 'PARENTID')).ToLowerInvariant()
                name                   = [string] (Get-ScoutProp $_ 'PARENTNAME')
                resourceGroup          = [string] (Get-ScoutProp $_ 'RESOURCEGROUP')
                subscriptionId         = [string] (Get-ScoutProp $_ 'subscriptionId')
                location               = [string] (Get-ScoutProp $_ 'PARENTLOCATION')
                ftpsState              = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.ftpsState')
                alwaysOn               = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.alwaysOn')
                healthCheckPathSet     = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.healthCheckPathSet')
                remoteDebuggingEnabled = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.remoteDebuggingEnabled')
                http20Enabled          = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.http20Enabled')
                minTlsVersion          = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.minTlsVersion')
                scmMinTlsVersion       = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.scmMinTlsVersion')
            }
        }
    )

    # -- web app basic-auth policies ---------------------------------------------------------
    # Two GETs per site (ftp, scm) folded into one row per site. A policy whose GET returned no
    # row (404, denied) stays $null -- "unknown" -- rather than becoming "not allowed".
    $result['webAppBasicAuthMeasured'] = Test-ScoutSweepMeasured 'WebAppBasicAuth'
    $basicAuthSites = [ordered]@{}
    foreach ($policyRow in @(Select-ByType 'AZSC/ARMChild/WebAppBasicAuth')) {
        $siteKey = ([string] (Get-ScoutProp $policyRow 'PARENTID')).ToLowerInvariant()
        if (-not $siteKey) { continue }
        if (-not $basicAuthSites.Contains($siteKey)) {
            $basicAuthSites[$siteKey] = [pscustomobject]@{ row = $policyRow; ftp = $null; scm = $null }
        }
        $policyName = [string] (Get-ScoutProp $policyRow 'properties.policy')
        if (-not $policyName) { $policyName = ([string] (Get-ScoutProp $policyRow 'id')).Split('/')[-1] }
        $allowed = ConvertTo-ScoutBool (Get-ScoutProp $policyRow 'properties.allow')
        if ($policyName -ieq 'ftp') { $basicAuthSites[$siteKey].ftp = $allowed }
        elseif ($policyName -ieq 'scm') { $basicAuthSites[$siteKey].scm = $allowed }
    }
    $result['webAppBasicAuth'] = @(
        foreach ($siteKey in $basicAuthSites.Keys) {
            $site = $basicAuthSites[$siteKey]
            [pscustomobject]@{
                webAppId             = $siteKey
                name                 = [string] (Get-ScoutProp $site.row 'PARENTNAME')
                resourceGroup        = [string] (Get-ScoutProp $site.row 'RESOURCEGROUP')
                subscriptionId       = [string] (Get-ScoutProp $site.row 'subscriptionId')
                location             = [string] (Get-ScoutProp $site.row 'PARENTLOCATION')
                ftpBasicAuthAllowed  = $site.ftp
                scmBasicAuthAllowed  = $site.scm
            }
        }
    )

    # -- Event Hubs geo-disaster recovery (one row per namespace whose list answered) ---------
    # A boolean only. The pairing's partner namespace is another namespace's resource id and is
    # never carried; the collector keeps just the pairing's role and provisioning state.
    $result['eventHubGeoDrMeasured'] = Test-ScoutSweepMeasured 'EventHubGeoDr'
    $geoDrByNamespace = Group-ScoutChildRowByParent 'AZSC/ARMChild/EventHubGeoDr'
    $geoDrNamespaces = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($checkedNamespace in (Get-ScoutSweepCheckedParent 'EventHubGeoDr')) { [void] $geoDrNamespaces.Add($checkedNamespace) }
    foreach ($groupedNamespace in $geoDrByNamespace.Keys) { [void] $geoDrNamespaces.Add($groupedNamespace) }
    $result['eventHubGeoDr'] = @(
        foreach ($namespaceId in @($geoDrNamespaces | Sort-Object)) {
            $fact = Get-ScoutSummaryParentFact $namespaceId
            [pscustomobject]@{
                eventHubNamespaceId = $namespaceId
                name                = $fact.name
                resourceGroup       = $fact.resourceGroup
                subscriptionId      = $fact.subscriptionId
                location            = $fact.location
                geoDrConfigured     = $geoDrByNamespace.Contains($namespaceId) -and @($geoDrByNamespace[$namespaceId]).Count -gt 0
            }
        }
    )

    # -- Redis Enterprise / Azure Managed Redis databases ------------------------------------
    # Access keys are never read (they come from a POST listKeys, not this GET). The linked
    # databases of a geo-replication group are counted, never listed.
    $result['redisEnterpriseDatabasesMeasured'] = Test-ScoutSweepMeasured 'RedisEnterpriseDatabases'
    $result['redisEnterpriseDatabases'] = @(
        Select-ByType 'AZSC/ARMChild/RedisEnterpriseDatabases' | ForEach-Object {
            [pscustomobject]@{
                redisEnterpriseId        = ([string] (Get-ScoutProp $_ 'PARENTID')).ToLowerInvariant()
                name                     = [string] (Get-ScoutProp $_ 'name')
                clusterName              = [string] (Get-ScoutProp $_ 'PARENTNAME')
                resourceGroup            = [string] (Get-ScoutProp $_ 'RESOURCEGROUP')
                subscriptionId           = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                 = [string] (Get-ScoutProp $_ 'PARENTLOCATION')
                accessKeysAuthentication = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.accessKeysAuthentication')
                clientProtocol           = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.clientProtocol')
                persistenceAofEnabled    = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.persistence.aofEnabled')
                persistenceAofFrequency  = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.persistence.aofFrequency')
                persistenceRdbEnabled    = ConvertTo-ScoutFeatureFlag (Get-ScoutProp $_ 'properties.persistence.rdbEnabled')
                persistenceRdbFrequency  = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.persistence.rdbFrequency')
                geoReplicationLinkCount  = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.geoReplication.linkedDatabaseCount')
            }
        }
    )

    # -- storage lifecycle management policies (AB#9300, depth wiring) --------------------------------
    # One row per blob-capable storage account whose policy GET ANSWERED. A 404 is an answer -- the
    # account has no policy -- and for the three lifecycle rules that absence is the finding, so it
    # produces a row with policyPresent false and every count 0, exactly as an empty failover-group list
    # does above. A GET that failed produces no row and leaves the account out of the count.
    # The rows carry counts only: never a rule name, a container prefix or a filter. A rule counts as
    # enabled unless its `enabled` is an explicit false (the same reading the Storage Lifecycle Policies
    # worksheet uses), tiers data when it moves blobs, versions or snapshots to Cool, Cold or Archive, and
    # expires data when it deletes them. `premium` marks a premium block blob account, which has no tiers.
    $result['lifecyclePoliciesMeasured'] = Test-ScoutSweepMeasured 'StorageLifecyclePolicies'
    $lifecycleByAccount = Group-ScoutChildRowByParent 'AZSC/ARMChild/StorageLifecyclePolicies'
    $lifecycleAccounts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # The account an operation answered for is its ParentId, or -- for an inventory banked before this dataset
    # recorded one -- the account id in the request path, so an old dump still yields a row for an account that
    # answered 404 (no policy) instead of silently leaving it out.
    foreach ($lifecycleOperation in $sweepOperations) {
        if ([string] $lifecycleOperation.Dataset -ne 'StorageLifecyclePolicies' -or [string] $lifecycleOperation.Status -notin 'Success', 'Empty') { continue }
        $operationParent = if ($lifecycleOperation.PSObject.Properties['ParentId']) { [string] $lifecycleOperation.ParentId } else { '' }
        if (-not $operationParent -and $lifecycleOperation.PSObject.Properties['Uri']) {
            $uriMatch = [regex]::Match([string] $lifecycleOperation.Uri, '(?i)(/subscriptions/.+?)/managementPolicies/default')
            if ($uriMatch.Success) { $operationParent = $uriMatch.Groups[1].Value }
        }
        if ($operationParent) { [void] $lifecycleAccounts.Add($operationParent.ToLowerInvariant()) }
    }
    foreach ($groupedAccount in $lifecycleByAccount.Keys) { [void] $lifecycleAccounts.Add($groupedAccount) }
    $result['lifecyclePolicies'] = @(
        foreach ($accountId in @($lifecycleAccounts | Sort-Object)) {
            $fact = Get-ScoutSummaryParentFact $accountId
            $accountRow = $summaryParentById[$accountId.ToLowerInvariant()]
            $policyRows = @(if ($lifecycleByAccount.Contains($accountId)) { $lifecycleByAccount[$accountId] })
            $rules = @(foreach ($policyRow in $policyRows) {
                    $ruleList = Get-ScoutPropArray $policyRow 'properties.policy.rules'
                    foreach ($ruleItem in @($ruleList)) { if ($null -ne $ruleItem) { $ruleItem } }
                })
            $enabledRules = @($rules | Where-Object { (ConvertTo-ScoutBool (Get-ScoutProp $_ 'enabled')) -ne $false })
            $hasAction = {
                param($Rule, [string[]] $Actions)
                foreach ($group in 'baseBlob', 'version', 'snapshot') {
                    foreach ($action in $Actions) {
                        if ($null -ne (Get-ScoutProp $Rule "definition.actions.$group.$action")) { return $true }
                    }
                }
                return $false
            }
            [pscustomobject]@{
                storageAccountId  = $accountId
                name              = $fact.name
                resourceGroup     = $fact.resourceGroup
                subscriptionId    = $fact.subscriptionId
                location          = $fact.location
                premium           = if ($null -ne $accountRow) { ([string] (Get-ScoutProp $accountRow 'sku.name')) -like 'Premium*' } else { $false }
                policyPresent     = $policyRows.Count -gt 0
                ruleCount         = $rules.Count
                enabledRuleCount  = $enabledRules.Count
                tieringRuleCount  = @($enabledRules | Where-Object { & $hasAction $_ @('tierToCool', 'tierToCold', 'tierToArchive') }).Count
                deleteRuleCount   = @($enabledRules | Where-Object { & $hasAction $_ @('delete') }).Count
            }
        }
    )

    # ---- Azure VMware Solution private-cloud children (AB#9300, 3.18.19) ----------------------------
    # Thirteen datasets Resource Graph cannot supply, read by Get-ScoutArmChildResource and shaped
    # here under the same contract as the batch-2 datasets above: keyed by the PARENT private cloud's
    # resource id (lower-cased, field `privateCloudId`), each with a `<name>Measured` flag that is
    # $true only when at least one GET of that dataset got an answer, so a rule gates on it and reports
    # NotAssessed rather than passing on an empty list. They come in two shapes:
    #
    #   ITEM ROWS     avsClusters, avsDatastores, avsPlacementPolicies, avsMaintenances -- one row per
    #                 child, because the question is about each one (is THIS cluster big enough, is
    #                 THIS datastore accessible).
    #   SUMMARY ROWS  every other dataset -- one row per private cloud whose list ANSWERED, with counts
    #                 and booleans, and a count of 0 where nothing came back. Here the absence is the
    #                 finding ("no SRM add-on", "no Global Reach connection"), and an empty list
    #                 produces no response row to show it. A private cloud whose list failed has NO
    #                 row, so it is never reported as lacking the thing.
    #
    # The two per-cluster datasets are measured per answered GET, like the rest; a private cloud whose
    # cluster list failed contributes no datastore GET and so leaves them unmeasured.
    $avsPrivateCloudById = @{}
    foreach ($avsPrivateCloud in @(Select-ByType 'microsoft.avs/privateclouds')) {
        $avsPrivateCloudId = [string] (Get-ScoutProp $avsPrivateCloud 'id')
        if ($avsPrivateCloudId) { $avsPrivateCloudById[$avsPrivateCloudId.ToLowerInvariant()] = $avsPrivateCloud }
    }
    # Name / resource group / subscription / location of a private cloud that only has an id to go on.
    function Get-ScoutAvsParentFact {
        param([Parameter(Mandatory)] [string] $ParentId)
        $privateCloud = $avsPrivateCloudById[$ParentId.ToLowerInvariant()]
        if ($null -ne $privateCloud) {
            return [pscustomobject]@{
                name           = [string] (Get-ScoutProp $privateCloud 'name')
                resourceGroup  = [string] (Get-ScoutProp $privateCloud 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $privateCloud 'subscriptionId')
                location       = [string] (Get-ScoutProp $privateCloud 'location')
            }
        }
        $parsed = [regex]::Match($ParentId, '(?i)^/subscriptions/(?<sub>[^/]+)/resourceGroups/(?<rg>[^/]+)/providers/.+/(?<name>[^/]+)$')
        return [pscustomobject]@{
            name           = if ($parsed.Success) { $parsed.Groups['name'].Value } else { '' }
            resourceGroup  = if ($parsed.Success) { $parsed.Groups['rg'].Value } else { '' }
            subscriptionId = if ($parsed.Success) { $parsed.Groups['sub'].Value } else { '' }
            location       = ''
        }
    }

    # One row per private cloud whose list answered. $Shape receives that private cloud's child rows
    # and returns the dataset's own fields as an ordered table; the identity fields come first.
    function New-ScoutAvsSummaryRow {
        param([Parameter(Mandatory)] [string] $Dataset, [Parameter(Mandatory)] [scriptblock] $Shape)
        $childrenByCloud = Group-ScoutChildRowByParent "AZSC/ARMChild/$Dataset"
        $clouds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($checkedCloud in (Get-ScoutSweepCheckedParent $Dataset)) { [void] $clouds.Add($checkedCloud) }
        foreach ($groupedCloud in $childrenByCloud.Keys) { [void] $clouds.Add($groupedCloud) }
        foreach ($cloudId in @($clouds | Sort-Object)) {
            $fact = Get-ScoutAvsParentFact $cloudId
            $children = @(if ($childrenByCloud.Contains($cloudId)) { $childrenByCloud[$cloudId] })
            $row = [ordered]@{
                privateCloudId = $cloudId
                name           = $fact.name
                resourceGroup  = $fact.resourceGroup
                subscriptionId = $fact.subscriptionId
                location       = $fact.location
            }
            $own = & $Shape $children
            foreach ($key in $own.Keys) { $row[$key] = $own[$key] }
            [pscustomobject] $row
        }
    }

    # The identity fields every item row starts with (the private cloud is the row's PARENT).
    function Get-ScoutAvsItemIdentity {
        param([Parameter(Mandatory)] $Row)
        return [ordered]@{
            privateCloudId   = ([string] (Get-ScoutProp $Row 'PARENTID')).ToLowerInvariant()
            privateCloudName = [string] (Get-ScoutProp $Row 'PARENTNAME')
            resourceGroup    = [string] (Get-ScoutProp $Row 'RESOURCEGROUP')
            subscriptionId   = [string] (Get-ScoutProp $Row 'subscriptionId')
            location         = [string] (Get-ScoutProp $Row 'PARENTLOCATION')
        }
    }

    function Get-ScoutAvsCount {
        param([AllowNull()] [object[]] $Rows, [Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Value)
        return @(@($Rows) | Where-Object { $null -ne $_ -and ([string] (Get-ScoutProp $_ $Path)) -ieq $Value }).Count
    }

    # -- clusters -----------------------------------------------------------------------------
    # The minimum is the AVS floor: 3 hosts, and 6 (3 in each zone) for a stretched, DualZone private
    # cloud. The private cloud's own row supplies the strategy; a cluster whose private cloud is not
    # in the inventory is held to the floor of 3.
    $result['avsClustersMeasured'] = Test-ScoutSweepMeasured 'AvsClusters'
    $result['avsClusters'] = @(
        Select-ByType 'AZSC/ARMChild/AvsClusters' | ForEach-Object {
            $identity = Get-ScoutAvsItemIdentity $_
            $cloud = $avsPrivateCloudById[([string] $identity.privateCloudId)]
            $strategy = if ($null -ne $cloud) { ConvertTo-ScoutNullableString (Get-ScoutProp $cloud 'properties.availability.strategy') } else { $null }
            $clusterSize = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.clusterSize')
            $hostCount = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.hostCount')
            $hosts = if ($null -ne $clusterSize) { $clusterSize } else { $hostCount }
            $minimumHosts = if ($strategy -ieq 'DualZone') { 6 } else { 3 }
            $own = [ordered]@{
                name                 = [string] (Get-ScoutProp $_ 'name')
                sku                  = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.skuName')
                clusterSize          = $clusterSize
                hostCount            = $hostCount
                provisioningState    = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.provisioningState')
                availabilityStrategy = $strategy
                minimumHosts         = $minimumHosts
                belowMinimumHosts    = if ($null -eq $hosts) { $null } else { $hosts -lt $minimumHosts }
            }
            foreach ($key in $own.Keys) { $identity[$key] = $own[$key] }
            [pscustomobject] $identity
        }
    )

    # -- datastores (external storage attached to a cluster) -----------------------------------
    # `kind` says which provider backs the datastore; the target resource id is never carried.
    $result['avsDatastoresMeasured'] = Test-ScoutSweepMeasured 'AvsDatastores'
    $result['avsDatastores'] = @(
        Select-ByType 'AZSC/ARMChild/AvsDatastores' | ForEach-Object {
            $identity = Get-ScoutAvsItemIdentity $_
            $status = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.status')
            $own = [ordered]@{
                clusterName       = [string] (Get-ScoutProp $_ 'properties.clusterName')
                name              = [string] (Get-ScoutProp $_ 'name')
                kind              = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.kind')
                status            = $status
                accessible        = if ($null -eq $status) { $null } else { $status -ieq 'Accessible' }
                provisioningState = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.provisioningState')
            }
            foreach ($key in $own.Keys) { $identity[$key] = $own[$key] }
            [pscustomobject] $identity
        }
    )

    # -- DRS placement policies -----------------------------------------------------------------
    # The policy's members (VM ids and host names) are reduced to counts before a row exists.
    $result['avsPlacementPoliciesMeasured'] = Test-ScoutSweepMeasured 'AvsPlacementPolicies'
    $result['avsPlacementPolicies'] = @(
        Select-ByType 'AZSC/ARMChild/AvsPlacementPolicies' | ForEach-Object {
            $identity = Get-ScoutAvsItemIdentity $_
            $state = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.state')
            $own = [ordered]@{
                clusterName            = [string] (Get-ScoutProp $_ 'properties.clusterName')
                name                   = [string] (Get-ScoutProp $_ 'name')
                policyType             = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.type')
                state                  = $state
                enabled                = if ($null -eq $state) { $null } else { $state -ieq 'Enabled' }
                affinityType           = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.affinityType')
                affinityStrength       = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.affinityStrength')
                azureHybridBenefitType = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.azureHybridBenefitType')
                vmMemberCount          = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.vmMemberCount')
                hostMemberCount        = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.hostMemberCount')
                provisioningState      = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.provisioningState')
            }
            foreach ($key in $own.Keys) { $identity[$key] = $own[$key] }
            [pscustomobject] $identity
        }
    )

    # -- maintenances (platform maintenance the private cloud has pending or just had) -----------
    $result['avsMaintenancesMeasured'] = Test-ScoutSweepMeasured 'AvsMaintenances'
    $result['avsMaintenances'] = @(
        Select-ByType 'AZSC/ARMChild/AvsMaintenances' | ForEach-Object {
            $identity = Get-ScoutAvsItemIdentity $_
            $own = [ordered]@{
                name                       = [string] (Get-ScoutProp $_ 'name')
                component                  = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.component')
                state                      = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.state.name')
                scheduledByMicrosoft       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.scheduledByMicrosoft')
                scheduledStartTime         = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.scheduledStartTime')
                readiness                  = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.maintenanceReadiness.status')
                estimatedDurationInMinutes = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.estimatedDurationInMinutes')
                provisioningState          = ConvertTo-ScoutNullableString (Get-ScoutProp $_ 'properties.provisioningState')
            }
            foreach ($key in $own.Keys) { $identity[$key] = $own[$key] }
            [pscustomobject] $identity
        }
    )

    # -- add-ons: Site Recovery Manager, vSphere Replication, HCX, Arc ------------------------------
    # `...Enabled` means an add-on of that type finished provisioning (Succeeded). The SRM licence key
    # the list response carries is dropped at the GET; only the type, state, HCX offer and the VRS
    # count survive.
    $result['avsAddonsMeasured'] = Test-ScoutSweepMeasured 'AvsAddons'
    $result['avsAddons'] = @(
        New-ScoutAvsSummaryRow 'AvsAddons' {
            param($children)
            $enabled = {
                param($type)
                @($children | Where-Object {
                        ([string] (Get-ScoutProp $_ 'properties.addonType')) -ieq $type -and
                        ([string] (Get-ScoutProp $_ 'properties.provisioningState')) -ieq 'Succeeded'
                    }).Count -gt 0
            }
            $hcx = @($children | Where-Object { ([string] (Get-ScoutProp $_ 'properties.addonType')) -ieq 'HCX' } | Select-Object -First 1)
            $vr = @($children | Where-Object { ([string] (Get-ScoutProp $_ 'properties.addonType')) -ieq 'VR' } | Select-Object -First 1)
            [ordered]@{
                addonCount       = $children.Count
                srmEnabled       = [bool] (& $enabled 'SRM')
                vrEnabled        = [bool] (& $enabled 'VR')
                hcxEnabled       = [bool] (& $enabled 'HCX')
                arcEnabled       = [bool] (& $enabled 'Arc')
                hcxOffer         = if ($hcx.Count -gt 0) { ConvertTo-ScoutNullableString (Get-ScoutProp $hcx[0] 'properties.offer') } else { $null }
                vrsCount         = if ($vr.Count -gt 0) { ConvertTo-ScoutInt (Get-ScoutProp $vr[0] 'properties.vrsCount') } else { $null }
                failedAddonCount = @($children | Where-Object { ([string] (Get-ScoutProp $_ 'properties.provisioningState')) -in 'Failed', 'Canceled', 'Cancelled' }).Count
            }
        }
    )

    # -- ExpressRoute Global Reach connections (on-premises connectivity) -------------------------------
    # Counts only. The peer circuit's id and authorization key never reach a row; `peerCircuitCount`
    # says how many connections name a peer circuit.
    $result['avsGlobalReachConnectionsMeasured'] = Test-ScoutSweepMeasured 'AvsGlobalReachConnections'
    $result['avsGlobalReachConnections'] = @(
        New-ScoutAvsSummaryRow 'AvsGlobalReachConnections' {
            param($children)
            [ordered]@{
                connectionCount = $children.Count
                connectedCount  = Get-ScoutAvsCount -Rows $children -Path 'properties.circuitConnectionStatus' -Value 'Connected'
                peerCircuitCount = @($children | Where-Object { (ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.peerCircuitPresent')) -eq $true }).Count
                failedCount     = Get-ScoutAvsCount -Rows $children -Path 'properties.provisioningState' -Value 'Failed'
            }
        }
    )

    # -- ExpressRoute authorizations (the keys that let a virtual network or hub connect) -----------
    # A COUNT. The authorization key and id are never read into a row.
    $result['avsAuthorizationsMeasured'] = Test-ScoutSweepMeasured 'AvsAuthorizations'
    $result['avsAuthorizations'] = @(
        New-ScoutAvsSummaryRow 'AvsAuthorizations' {
            param($children)
            [ordered]@{
                authorizationCount = $children.Count
                failedCount        = Get-ScoutAvsCount -Rows $children -Path 'properties.provisioningState' -Value 'Failed'
            }
        }
    )

    # -- cloud links (to other private clouds) -------------------------------------------------------------
    $result['avsCloudLinksMeasured'] = Test-ScoutSweepMeasured 'AvsCloudLinks'
    $result['avsCloudLinks'] = @(
        New-ScoutAvsSummaryRow 'AvsCloudLinks' {
            param($children)
            [ordered]@{
                linkCount   = $children.Count
                activeCount = Get-ScoutAvsCount -Rows $children -Path 'properties.status' -Value 'Active'
            }
        }
    )

    # -- NSX workload network: segments, DHCP, DNS, gateways ------------------------------------------------
    # Counts only -- no gateway address, DHCP range, server address, DNS IP or NSX path.
    $result['avsSegmentsMeasured'] = Test-ScoutSweepMeasured 'AvsSegments'
    $result['avsSegments'] = @(
        New-ScoutAvsSummaryRow 'AvsSegments' {
            param($children)
            [ordered]@{
                segmentCount          = $children.Count
                failedSegmentCount    = Get-ScoutAvsCount -Rows $children -Path 'properties.status' -Value 'FAILURE'
                connectedSegmentCount = @($children | Where-Object { (ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.connectedGatewaySet')) -eq $true }).Count
                dhcpSegmentCount      = @($children | Where-Object { (ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.dhcpRangeCount')) -gt 0 }).Count
            }
        }
    )
    $result['avsDhcpConfigurationsMeasured'] = Test-ScoutSweepMeasured 'AvsDhcpConfigurations'
    $result['avsDhcpConfigurations'] = @(
        New-ScoutAvsSummaryRow 'AvsDhcpConfigurations' {
            param($children)
            [ordered]@{
                configurationCount = $children.Count
                serverCount        = Get-ScoutAvsCount -Rows $children -Path 'properties.dhcpType' -Value 'SERVER'
                relayCount         = Get-ScoutAvsCount -Rows $children -Path 'properties.dhcpType' -Value 'RELAY'
            }
        }
    )
    $result['avsDnsServicesMeasured'] = Test-ScoutSweepMeasured 'AvsDnsServices'
    $result['avsDnsServices'] = @(
        New-ScoutAvsSummaryRow 'AvsDnsServices' {
            param($children)
            [ordered]@{
                serviceCount       = $children.Count
                failedServiceCount = Get-ScoutAvsCount -Rows $children -Path 'properties.status' -Value 'FAILURE'
            }
        }
    )
    $result['avsGatewaysMeasured'] = Test-ScoutSweepMeasured 'AvsGateways'
    $result['avsGateways'] = @(
        New-ScoutAvsSummaryRow 'AvsGateways' {
            param($children)
            [ordered]@{ gatewayCount = $children.Count }
        }
    )

    # -- iSCSI paths -------------------------------------------------------------------------------------------
    $result['avsIscsiPathsMeasured'] = Test-ScoutSweepMeasured 'AvsIscsiPaths'
    $result['avsIscsiPaths'] = @(
        New-ScoutAvsSummaryRow 'AvsIscsiPaths' {
            param($children)
            [ordered]@{ pathCount = $children.Count }
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
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                location           = [string] (Get-ScoutProp $_ 'location')
                kind               = [string] (Get-ScoutProp $_ 'kind')
                sharedKeyAccess    = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.allowSharedKeyAccess')
                keySource          = [string] (Get-ScoutProp $_ 'properties.encryption.keySource')
                infrastructureEncryption = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.encryption.requireInfrastructureEncryption')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                allowCrossTenantReplication = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.allowCrossTenantReplication')
                defaultToOAuth     = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.defaultToOAuthAuthentication')
            }
        }
    )

    $result['sqlDatabases'] = @(
        Select-ByType 'microsoft.sql/servers/databases' | ForEach-Object {
            [pscustomobject]@{
                id            = [string] (Get-ScoutProp $_ 'id')
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                location      = [string] (Get-ScoutProp $_ 'location')
                zoneRedundant = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                tier          = [string] (Get-ScoutProp $_ 'sku.tier')
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                backupRedundancy = [string] (Get-ScoutProp $_ 'properties.requestedBackupStorageRedundancy')
                secondaryType    = [string] (Get-ScoutProp $_ 'properties.secondaryType')
                haReplicaCount   = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.highAvailabilityReplicaCount')
            }
        }
    )

    $result['sqlServers'] = @(
        Select-ByType 'microsoft.sql/servers' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                location            = [string] (Get-ScoutProp $_ 'location')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                # AB#9300 phase 4 -- mirrors the KQL field for field. The administrator's sid /
                # tenantId / login are never read; entraOnlyAuth is the one boolean taken from
                # properties.administrators, and cmkEnabled is a bool only (never the key uri).
                minimalTlsVersion   = [string] (Get-ScoutProp $_ 'properties.minimalTlsVersion')
                entraOnlyAuth       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.administrators.azureADOnlyAuthentication')
                identityType        = [string] (Get-ScoutProp $_ 'identity.type')
                cmkEnabled          = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.keyId'))
            }
        }
    )

    $result['webApps'] = @(
        Select-ByType 'microsoft.web/sites' | ForEach-Object {
            $sslStates = Measure-ScoutArray (Get-ScoutProp $_ 'properties.hostNameSslStates')
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                location          = [string] (Get-ScoutProp $_ 'location')
                kind              = [string] (Get-ScoutProp $_ 'kind')
                httpsOnly         = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.httpsOnly')
                minTls            = [string] (Get-ScoutProp $_ 'properties.siteConfig.minTlsVersion')
                vnetIntegrated    = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.virtualNetworkSubnetId'))
                customDomainBound = ($null -ne $sslStates -and $sslStates -gt 1)
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType        = [string] (Get-ScoutProp $_ 'identity.type')
                clientCertEnabled   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.clientCertEnabled')
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
            # AB#9300 phase 4 -- mirrors the KQL summarize. A pool autoscales only when its flag is
            # an explicit true (a missing flag is a fixed-size pool). systemPoolMinNodes is the
            # smallest node count a SYSTEM pool may fall to: minCount when it autoscales, else its
            # fixed count; null when the cluster has no system pool (min() ignores nulls).
            $autoscalePools = 0
            $systemPoolNodeFloors = [System.Collections.Generic.List[object]]::new()
            foreach ($pool in $pools) {
                if ($null -eq $pool) { continue }
                $poolAutoscales = (ConvertTo-ScoutBool (Get-ScoutProp $pool 'enableAutoScaling')) -eq $true
                if ($poolAutoscales) { $autoscalePools++ }
                if (([string] (Get-ScoutProp $pool 'mode')) -ieq 'System') {
                    $poolFloorRaw = if ($poolAutoscales) { Get-ScoutProp $pool 'minCount' } else { Get-ScoutProp $pool 'count' }
                    $systemPoolNodeFloors.Add((ConvertTo-ScoutInt $poolFloorRaw))
                }
            }
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                location             = [string] (Get-ScoutProp $_ 'location')
                k8sVersion           = [string] (Get-ScoutProp $_ 'properties.kubernetesVersion')
                privateCluster       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.apiServerAccessProfile.enablePrivateCluster')
                rbacEnabled          = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableRBAC')
                networkPolicyEnabled = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.networkProfile.networkPolicy'))
                aadIntegrated        = ($null -ne (Get-ScoutProp $_ 'properties.aadProfile'))
                allPoolsZoned        = ($zonedPools -eq $totalPools)
                tier                 = [string] (Get-ScoutProp $_ 'sku.tier')
                systemPoolMinNodes   = Get-ScoutMinValue -Values ($systemPoolNodeFloors.ToArray())
                allPoolsAutoscale    = ($autoscalePools -eq $totalPools)
                disableLocalAccounts = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAccounts')
                upgradeChannel       = [string] (Get-ScoutProp $_ 'properties.autoUpgradeProfile.upgradeChannel')
                nodeOsUpgradeChannel = [string] (Get-ScoutProp $_ 'properties.autoUpgradeProfile.nodeOSUpgradeChannel')
                # A COUNT -- the authorised IP ranges themselves are never shaped.
                authorizedIpRangeCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.apiServerAccessProfile.authorizedIPRanges')
                defenderEnabled      = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.securityProfile.defender.securityMonitoring.enabled')
                workloadIdentity     = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.securityProfile.workloadIdentity.enabled')
                azureRbac            = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.aadProfile.enableAzureRBAC')
                # AB#9300 (depth wiring) -- mirrors the KQL: the Azure Policy add-on switch, a bool only.
                azurePolicyAddon     = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.addonProfiles.azurepolicy.enabled')
            }
        }
    )

    $result['containerRegistries'] = @(
        Select-ByType 'microsoft.containerregistry/registries' | ForEach-Object {
            [pscustomobject]@{
                # AB#9300 (depth wiring) -- id and subscriptionId so a rule can join a registry to its
                # subscription's Defender for Containers plan.
                id            = [string] (Get-ScoutProp $_ 'id')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                sku           = [string] (Get-ScoutProp $_ 'sku.name')
                adminEnabled  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.adminUserEnabled')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    # ---- AB#7110 -- Containers(4) coverage gap. Mirrors Invoke-Collect.ps1's KQL field for field.
    $result['openShiftClusters'] = @(
        Select-ByType 'microsoft.redhatopenshift/openshiftclusters' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['containerApps'] = @(
        Select-ByType 'microsoft.app/containerapps' | ForEach-Object {
            # AB#9300 (depth wiring) -- mirrors the KQL expand-and-summarise: how many containers there
            # are, and how many lack ANY of the liveness, readiness and startup probes. Only each
            # probe's `type` is read -- never its host, path or headers. A container list that is absent
            # or empty reads containerCount null / 0 and no container is counted as probe-less.
            $appContainers = Get-ScoutPropArray $_ 'properties.template.containers'
            $containersWithoutAllProbes = 0
            foreach ($appContainer in @($appContainers)) {
                if ($null -eq $appContainer) { continue }
                # Assigned first: Get-ScoutPropArray returns its array wrapped, so it must be captured before it is enumerated.
                $probeList = Get-ScoutPropArray $appContainer 'probes'
                $probeKinds = @(foreach ($probe in @($probeList)) { if ($null -ne $probe) { [string] (Get-ScoutProp $probe 'type') } })
                $hasAllProbes = ($probeKinds -contains 'Liveness') -and ($probeKinds -contains 'Readiness') -and ($probeKinds -contains 'Startup')
                if (-not $hasAllProbes) { $containersWithoutAllProbes++ }
            }
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                environmentId     = [string] (Get-ScoutProp $_ 'properties.environmentId')
                # AB#9300 phase 4 -- mirrors the KQL field for field. configuration.secrets is
                # NEVER read (it holds secret values); only the ingress switches and scale floor.
                minReplicas       = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.template.scale.minReplicas')
                externalIngress   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.configuration.ingress.external')
                allowInsecure     = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.configuration.ingress.allowInsecure')
                identityType      = [string] (Get-ScoutProp $_ 'identity.type')
                containerCount    = Measure-ScoutArray $appContainers
                containersWithoutAllProbes = $containersWithoutAllProbes
            }
        }
    )

    $result['containerAppEnvironments'] = @(
        Select-ByType 'microsoft.app/managedenvironments' | ForEach-Object {
            $logDestination = [string] (Get-ScoutProp $_ 'properties.appLogsConfiguration.destination')
            $otelLogDestinations = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.openTelemetryConfiguration.logsConfiguration.destinations')
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                # AB#9300 phase 4 -- mirrors the KQL field for field. The Log Analytics sharedKey in
                # appLogsConfiguration is NEVER read.
                zoneRedundant       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                internal            = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.vnetConfiguration.internal')
                vnetIntegrated      = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.vnetConfiguration.infrastructureSubnetId'))
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                # AB#9300 (depth wiring) -- mirrors the KQL: where the environment sends its logs, and
                # whether it sends them anywhere (Log Analytics, Azure Monitor, or an OpenTelemetry logs
                # destination). Only the destination NAME is read, never a workspace id or key.
                logDestination      = $logDestination
                logsExported        = ($logDestination -ieq 'log-analytics') -or ($logDestination -ieq 'azure-monitor') -or ($null -ne $otelLogDestinations -and $otelLogDestinations -gt 0)
            }
        }
    )

    $result['containerGroups'] = @(
        Select-ByType 'microsoft.containerinstance/containergroups' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                osType         = [string] (Get-ScoutProp $_ 'properties.osType')
                restartPolicy  = [string] (Get-ScoutProp $_ 'properties.restartPolicy')
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
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                zoneCount           = Measure-ScoutArray (Get-ScoutPropArray $_ 'zones')
                networkAccessPolicy = [string] (Get-ScoutProp $_ 'properties.networkAccessPolicy')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                encryptionType      = [string] (Get-ScoutProp $_ 'properties.encryption.type')
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
    # AB#6895. The VAULT itself lives in the ordinary `resources` table, not in
    # recoveryservicesresources -- only its child protected items and policies are in that second
    # table. So the vault list is shaped from rows the raw pass already has, and costs no extra
    # round-trip.
    #
    # Before this, Invoke-Collect hardcoded `recoveryVaults = @()`, so no run in the product's
    # history reported a vault while backupProtectedItems returned rows -- a child with no parent,
    # the same class as AB#6845. A renderer reading recoveryVaults saw "none found" and could not
    # tell that from "never collected".
    $result['recoveryVaults'] = @(
        Select-ByType 'microsoft.recoveryservices/vaults' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
                publicAccess   = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                immutability   = [string] (Get-ScoutProp $_ 'properties.securitySettings.immutabilitySettings.state')
                softDelete     = [string] (Get-ScoutProp $_ 'properties.securitySettings.softDeleteSettings.softDeleteState')
                crossRegion    = [string] (Get-ScoutProp $_ 'properties.redundancySettings.crossRegionRestore')
                storageType    = [string] (Get-ScoutProp $_ 'properties.redundancySettings.standardTierStorageRedundancy')
            }
        }
    )

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
                id            = [string] (Get-ScoutProp $_ 'id')
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                location      = [string] (Get-ScoutProp $_ 'location')
                accountKind   = [string] (Get-ScoutProp $_ 'kind')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType  = [string] (Get-ScoutProp $_ 'identity.type')
                cmkEnabled    = ([string] (Get-ScoutProp $_ 'properties.encryption.keySource')) -ieq 'Microsoft.KeyVault'
                disableLocalAuth = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAuth')
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
                # AB#7109 -- mirrors Invoke-Collect.ps1's arcServers KQL field for field.
                patchMode      = [string] (Get-ScoutOsPatchSetting -Resource $_ -Field 'patchMode')
                assessmentMode = [string] (Get-ScoutOsPatchSetting -Resource $_ -Field 'assessmentMode')
            }
        }
    )

    # ---- Azure Update Manager patch detail (AB#7107 AB#7108, Story AB#7059, Feature AB#7069,
    # Epic AB#7099) -- mirrors Invoke-Collect.ps1's patchAssessments/patchInstallations KQL field
    # for field, reading the `patchassessmentresources`/`patchinstallationresources` rows the raw
    # pass's -IncludeUpdateManagerResources sweep appends to $Resources (see
    # Get-ScoutRawInventory.ps1's AB#6731 comment). Only the per-machine SUMMARY row is shaped --
    # the `.../softwarepatches` per-update child rows are excluded, same filter the KQL applies.
    function Get-ScoutPatchMachineId {
        param([Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Separator)
        $sepIndex = $Id.ToLowerInvariant().IndexOf($Separator.ToLowerInvariant())
        if ($sepIndex -lt 0) { return $null }
        return $Id.Substring(0, $sepIndex)
    }
    function Get-ScoutPatchPlatform {
        param([Parameter(Mandatory)] [string] $Type)
        if ($Type -ilike 'microsoft.compute*') { return 'AzureVM' }
        if ($Type -ilike 'microsoft.hybridcompute*') { return 'ArcServer' }
        if ($Type -ilike 'microsoft.connectedvmwarevsphere*') { return 'AVS' }
        return 'Unknown'
    }
    $patchAssessmentTypes = @(
        'microsoft.compute/virtualmachines/patchassessmentresults'
        'microsoft.hybridcompute/machines/patchassessmentresults'
        'microsoft.connectedvmwarevsphere/virtualmachines/patchassessmentresults'
    )
    $result['patchAssessments'] = @(
        $patchAssessmentTypes | ForEach-Object { Select-ByType $_ } | ForEach-Object {
            $id = [string] (Get-ScoutProp $_ 'id')
            $type = [string] (Get-ScoutProp $_ 'type')
            [pscustomobject]@{
                machineId                           = Get-ScoutPatchMachineId -Id $id -Separator '/patchAssessmentResults/'
                platform                             = Get-ScoutPatchPlatform -Type $type
                subscriptionId                       = [string] (Get-ScoutProp $_ 'subscriptionId')
                resourceGroup                        = [string] (Get-ScoutProp $_ 'resourceGroup')
                osType                                = [string] (Get-ScoutProp $_ 'properties.osType')
                rebootPending                         = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.rebootPending')
                patchServiceUsed                      = [string] (Get-ScoutProp $_ 'properties.patchServiceUsed')
                startDateTime                         = [string] (Get-ScoutProp $_ 'properties.startDateTime')
                lastModifiedDateTime                  = [string] (Get-ScoutProp $_ 'properties.lastModifiedDateTime')
                availablePatchCountByClassification    = Get-ScoutProp $_ 'properties.availablePatchCountByClassification'
            }
        }
    )
    $patchInstallationTypes = @(
        'microsoft.compute/virtualmachines/patchinstallationresults'
        'microsoft.hybridcompute/machines/patchinstallationresults'
        'microsoft.connectedvmwarevsphere/virtualmachines/patchinstallationresults'
    )
    $result['patchInstallations'] = @(
        $patchInstallationTypes | ForEach-Object { Select-ByType $_ } | ForEach-Object {
            $id = [string] (Get-ScoutProp $_ 'id')
            $type = [string] (Get-ScoutProp $_ 'type')
            [pscustomobject]@{
                machineId                  = Get-ScoutPatchMachineId -Id $id -Separator '/patchInstallationResults/'
                platform                    = Get-ScoutPatchPlatform -Type $type
                subscriptionId              = [string] (Get-ScoutProp $_ 'subscriptionId')
                resourceGroup               = [string] (Get-ScoutProp $_ 'resourceGroup')
                osType                      = [string] (Get-ScoutProp $_ 'properties.osType')
                status                      = [string] (Get-ScoutProp $_ 'properties.status')
                installationActivityId      = [string] (Get-ScoutProp $_ 'properties.installationActivityId')
                installedPatchCount         = Get-ScoutProp $_ 'properties.installedPatchCount'
                failedPatchCount            = Get-ScoutProp $_ 'properties.failedPatchCount'
                pendingPatchCount           = Get-ScoutProp $_ 'properties.pendingPatchCount'
                notSelectedPatchCount       = Get-ScoutProp $_ 'properties.notSelectedPatchCount'
                excludedPatchCount          = Get-ScoutProp $_ 'properties.excludedPatchCount'
                rebootStatus                = [string] (Get-ScoutProp $_ 'properties.rebootStatus')
                maintenanceWindowExceeded   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.maintenanceWindowExceeded')
                startDateTime               = [string] (Get-ScoutProp $_ 'properties.startDateTime')
                lastModifiedDateTime        = [string] (Get-ScoutProp $_ 'properties.lastModifiedDateTime')
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

    # nodeCount/clusterVersion added for AB#6803 (WAF-AZLOCAL-RE-02/RE-03/OE-06): both are
    # ARG-indexed, top-level `properties.reportedProperties` fields on the SAME
    # microsoft.azurestackhci/clusters row already selected below -- no new round trip. Field
    # names verified against the collector this was converted from
    # (manifests/collectors/Hybrid/Clusters.psd1, itself generated from the pre-retirement
    # Modules/Public/InventoryModules/Hybrid/Clusters.ps1); the ARM template reference documents
    # `reportedProperties` only as an opaque agent-reported bag with no listed sub-fields, so this
    # is confirmed by the shipped collector's own field expressions, not by the template schema.
    $result['azureLocalClusters'] = @(
        Select-ByType 'microsoft.azurestackhci/clusters' | ForEach-Object {
            $nodeCountRaw = Get-ScoutProp $_ 'properties.reportedProperties.clusterNodes'
            [pscustomobject]@{
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId     = [string] (Get-ScoutProp $_ 'subscriptionId')
                connectivityStatus = [string] (Get-ScoutProp $_ 'properties.connectivityStatus')
                nodeCount          = Measure-ScoutArray $nodeCountRaw
                clusterVersion     = [string] (Get-ScoutProp $_ 'properties.reportedProperties.clusterVersion')
                # AB#7093 (WAF-AZLOCAL-CO-03/CO-04) -- same field the live ARG query now projects
                # (Invoke-Collect.ps1's azureLocalClusters query); kept in parity here so a
                # -FromInventory collect scores the same rules as a live collect.
                softwareAssuranceStatus = [string] (Get-ScoutProp $_ 'properties.softwareAssuranceProperties.softwareAssuranceStatus')
            }
        }
    )

    # AB#6803 (WAF-AZLOCAL-RE-03/OE-03): microsoft.azurestackhci/logicalnetworks is confirmed
    # ARG-indexed (learn.microsoft.com/azure/governance/resource-graph/reference/
    # supported-tables-resources, entry `microsoft.azurestackhci/logicalnetworks`), so this reads
    # the SAME `resources` rows as every other typed projection in this function -- no new round
    # trip, no REST sweep, no per-parent extension-resource trap. The subnet fields are the first
    # subnet only, matching the existing Hybrid/LogicalNetworks declarative collector's own
    # "primary subnet" convention (manifests/collectors/Hybrid/LogicalNetworks.psd1).
    $result['logicalNetworks'] = @(
        Select-ByType 'microsoft.azurestackhci/logicalnetworks' | ForEach-Object {
            $subnets = @(Get-ScoutProp $_ 'properties.subnets')
            $firstSubnet = if ($subnets.Count -gt 0) { $subnets[0] } else { $null }
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                vmSwitchName   = [string] (Get-ScoutProp $_ 'properties.vmSwitchName')
                subnetCount    = $subnets.Count
                addressPrefix  = [string] (Get-ScoutProp $firstSubnet 'properties.addressPrefix')
                vlan           = Get-ScoutProp $firstSubnet 'properties.vlan'
            }
        }
    )

    # ---- AB#6803 (Feature AB#6747, Epic AB#6454) — the two blocking Azure Local collectors ------
    # `arcSites` and `azureLocalVirtualMachineInstances` are NOT Resource Graph rows -- both types
    # are confirmed absent from ARG's supported-type reference (AB#6801/AB#6802) and are sourced
    # entirely by the ARM REST sweep this function's caller opts into (see Invoke-Collect.ps1's
    # `-IncludeAzureLocalArm` switch). They land in the SAME `$Resources` array as everything else
    # here, tagged with their synthetic `AZSC/ARMChild/*` type, so `Select-ByType` finds them
    # exactly like an ARG row once collected -- and returns an empty array, not an error, when the
    # opt-in switch was not set. That empty-vs-populated distinction IS the RequiresData gate
    # `manifests/assessments.psd1`'s 'WAF: Azure Local' entry reads.
    $result['arcSites'] = @(
        Select-ByType 'AZSC/ARMChild/ArcSites' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'RESOURCEGROUP')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                displayName    = [string] (Get-ScoutProp $_ 'properties.displayName')
            }
        }
    )

    $result['azureLocalVirtualMachineInstances'] = @(
        Select-ByType 'AZSC/ARMChild/AzureLocalVirtualMachineInstances' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                # The child envelope's own name is always the fixed string 'default' (AB#6802) --
                # PARENTNAME/PARENTLOCATION carry the actual Arc machine / Azure Local VM identity.
                parentName        = [string] (Get-ScoutProp $_ 'PARENTNAME')
                parentLocation    = [string] (Get-ScoutProp $_ 'PARENTLOCATION')
                resourceGroup     = [string] (Get-ScoutProp $_ 'RESOURCEGROUP')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                powerState        = [string] (Get-ScoutProp $_ 'properties.instanceView.powerState')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['eventHubNamespaces'] = @(
        Select-ByType 'microsoft.eventhub/namespaces' | ForEach-Object {
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                location           = [string] (Get-ScoutProp $_ 'location')
                zoneRedundant      = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                publicAccess       = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                autoInflateEnabled = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.isAutoInflateEnabled')
                # AB#9300 phase 4 -- mirrors the KQL field for field. encryption.keyVaultProperties
                # is NEVER read; only the key source and the double-encryption flag.
                skuName            = [string] (Get-ScoutProp $_ 'sku.name')
                capacity           = ConvertTo-ScoutInt (Get-ScoutProp $_ 'sku.capacity')
                maxThroughputUnits = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.maximumThroughputUnits')
                geoReplicaCount    = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.geoDataReplication.locations')
                disableLocalAuth   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAuth')
                minimumTlsVersion  = [string] (Get-ScoutProp $_ 'properties.minimumTlsVersion')
                cmkKeySource       = [string] (Get-ScoutProp $_ 'properties.encryption.keySource')
                doubleEncryption   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.encryption.requireInfrastructureEncryption')
            }
        }
    )

    $result['apiManagement'] = @(
        Select-ByType 'microsoft.apimanagement/service' | ForEach-Object {
            # The customProperties keys contain dots, so each is read by its exact name (Get-ScoutProp would
            # split it into path segments). 'True' / 'False' strings, case-insensitive; absent or blank is null.
            $apimCustomProperties = Get-ScoutProp $_ 'properties.customProperties'
            $apimKeyPrefix = 'Microsoft.WindowsAzure.ApiManagement.'
            $apimProtocolKeys = 'Gateway.Security.Protocols.Ssl30', 'Gateway.Security.Protocols.Tls10', 'Gateway.Security.Protocols.Tls11',
            'Gateway.Security.Backend.Protocols.Ssl30', 'Gateway.Security.Backend.Protocols.Tls10', 'Gateway.Security.Backend.Protocols.Tls11'
            $apimProtocolsPresent = 0
            $apimProtocolsOn = 0
            foreach ($apimProtocolKey in $apimProtocolKeys) {
                $apimProtocolValue = if ($null -ne $apimCustomProperties) {
                    ConvertTo-ScoutBool (Get-ScoutChildValue -InputObject $apimCustomProperties -Name ($apimKeyPrefix + $apimProtocolKey))
                }
                else { $null }
                if ($null -ne $apimProtocolValue) { $apimProtocolsPresent++ }
                if ($apimProtocolValue -eq $true) { $apimProtocolsOn++ }
            }
            $apimLegacyProtocol = if ($apimProtocolsPresent -eq 0) { $null } else { $apimProtocolsOn -gt 0 }
            $apimLegacyCipher = if ($null -ne $apimCustomProperties) {
                ConvertTo-ScoutBool (Get-ScoutChildValue -InputObject $apimCustomProperties -Name ($apimKeyPrefix + 'Gateway.Security.Ciphers.TripleDes168'))
            }
            else { $null }
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                location           = [string] (Get-ScoutProp $_ 'location')
                sku                = [string] (Get-ScoutProp $_ 'sku.name')
                virtualNetworkType = [string] (Get-ScoutProp $_ 'properties.virtualNetworkType')
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                zoneCount             = Measure-ScoutArray (Get-ScoutPropArray $_ 'zones')
                capacity              = ConvertTo-ScoutInt (Get-ScoutProp $_ 'sku.capacity')
                additionalRegionCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.additionalLocations')
                publicNetworkAccess   = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType          = [string] (Get-ScoutProp $_ 'identity.type')
                # AB#9300 (depth wiring) -- mirrors the KQL: the seven named customProperties keys, each
                # 'True' / 'False', and nothing else out of the bag. legacyProtocolEnabled is null when none
                # of the six protocol keys is present (the default then depends on the service's age).
                legacyProtocolEnabled = $apimLegacyProtocol
                legacyCipherEnabled   = $apimLegacyCipher
            }
        }
    )

    $result['serviceBusNamespaces'] = @(
        Select-ByType 'microsoft.servicebus/namespaces' | ForEach-Object {
            [pscustomobject]@{
                id            = [string] (Get-ScoutProp $_ 'id')
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                location      = [string] (Get-ScoutProp $_ 'location')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                # AB#9300 phase 4 -- mirrors the KQL field for field. encryption.keyVaultProperties
                # is NEVER read; only the key source.
                tier              = [string] (Get-ScoutProp $_ 'sku.tier')
                capacity          = ConvertTo-ScoutInt (Get-ScoutProp $_ 'sku.capacity')
                zoneRedundant     = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                geoReplicaCount   = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.geoDataReplication.locations')
                disableLocalAuth  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAuth')
                minimumTlsVersion = [string] (Get-ScoutProp $_ 'properties.minimumTlsVersion')
                cmkKeySource      = [string] (Get-ScoutProp $_ 'properties.encryption.keySource')
            }
        }
    )

    # AB#9300 phase 4 -- Event Grid topics, domains and namespaces had no dataset. Mirrors
    # Invoke-Collect.ps1's `eventGrid` KQL field for field. disableLocalAuth applies to
    # topics/domains and isZoneRedundant to namespaces, so each is null on the other types.
    # inboundIpRuleCount is a COUNT -- the IP masks are never read.
    $result['eventGrid'] = @(
        Select-ByAnyType @('microsoft.eventgrid/topics', 'microsoft.eventgrid/domains', 'microsoft.eventgrid/namespaces') | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                type                = [string] (Get-ScoutProp $_ 'type')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                inboundIpRuleCount  = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.inboundIpRules')
                minimumTlsVersion   = [string] (Get-ScoutProp $_ 'properties.minimumTlsVersionAllowed')
                disableLocalAuth    = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAuth')
                zoneRedundant       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.isZoneRedundant')
                identityType        = [string] (Get-ScoutProp $_ 'identity.type')
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

    # AB#7083 -- Azure IoT Operations (Arc-enabled Kubernetes IoT workload). Mirrors
    # Invoke-Collect.ps1's iotOperationsInstances KQL: description/schemaRegistryRef are
    # documented top-level InstanceProperties fields, identity/extendedLocation are top-level
    # resource columns.
    $result['iotOperationsInstances'] = @(
        Select-ByType 'microsoft.iotoperations/instances' | ForEach-Object {
            [pscustomobject]@{
                name                  = [string] (Get-ScoutProp $_ 'name')
                resourceGroup         = [string] (Get-ScoutProp $_ 'resourceGroup')
                description           = [string] (Get-ScoutProp $_ 'properties.description')
                schemaRegistryId      = [string] (Get-ScoutProp $_ 'properties.schemaRegistryRef.resourceId')
                identityType          = [string] (Get-ScoutProp $_ 'identity.type')
                extendedLocationName  = [string] (Get-ScoutProp $_ 'extendedLocation.name')
                extendedLocationType  = [string] (Get-ScoutProp $_ 'extendedLocation.type')
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

    # ---- AB#7110 -- Analytics(3) coverage gap. Mirrors Invoke-Collect.ps1's KQL field for field.
    $result['databricksWorkspaces'] = @(
        Select-ByType 'microsoft.databricks/workspaces' | ForEach-Object {
            [pscustomobject]@{
                id                     = [string] (Get-ScoutProp $_ 'id')
                name                   = [string] (Get-ScoutProp $_ 'name')
                resourceGroup          = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId         = [string] (Get-ScoutProp $_ 'subscriptionId')
                location               = [string] (Get-ScoutProp $_ 'location')
                sku                    = [string] (Get-ScoutProp $_ 'sku.name')
                managedResourceGroupId = [string] (Get-ScoutProp $_ 'properties.managedResourceGroupId')
                # AB#9300 phase 4 -- mirrors the KQL field for field. vnetInjected is a BOOL ONLY
                # (the customer VNet id itself is never shaped).
                vnetInjected           = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.parameters.customVirtualNetworkId.value'))
                noPublicIp             = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.parameters.enableNoPublicIp.value')
                publicNetworkAccess    = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                requiredNsgRules       = [string] (Get-ScoutProp $_ 'properties.requiredNsgRules')
            }
        }
    )

    $result['dataExplorerClusters'] = @(
        Select-ByType 'microsoft.kusto/clusters' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
                state          = [string] (Get-ScoutProp $_ 'properties.state')
            }
        }
    )

    $result['streamAnalyticsJobs'] = @(
        Select-ByType 'microsoft.streamanalytics/streamingjobs' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'properties.sku.name')
                jobState       = [string] (Get-ScoutProp $_ 'properties.jobState')
            }
        }
    )

    # ---- AB#7082 -- Analytics coverage-gap closeout. Mirrors Invoke-Collect.ps1's KQL field for
    # field (Story AB#7059, Feature AB#7069, Epic AB#7099).
    $result['analysisServicesServers'] = @(
        Select-ByType 'microsoft.analysisservices/servers' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                state             = [string] (Get-ScoutProp $_ 'properties.state')
            }
        }
    )

    $result['dataFactories'] = @(
        Select-ByType 'microsoft.datafactory/factories' | ForEach-Object {
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId       = [string] (Get-ScoutProp $_ 'subscriptionId')
                location             = [string] (Get-ScoutProp $_ 'location')
                provisioningState    = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                publicNetworkAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType         = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    $result['dataShareAccounts'] = @(
        Select-ByType 'microsoft.datashare/accounts' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                identityType      = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    $result['hdInsightClusters'] = @(
        Select-ByType 'microsoft.hdinsight/clusters' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                clusterVersion      = [string] (Get-ScoutProp $_ 'properties.clusterVersion')
                clusterKind         = [string] (Get-ScoutProp $_ 'properties.clusterDefinition.kind')
                clusterState        = [string] (Get-ScoutProp $_ 'properties.clusterState')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.networkProperties.publicNetworkAccess')
            }
        }
    )

    $result['powerBIEmbeddedCapacities'] = @(
        Select-ByType 'microsoft.powerbidedicated/capacities' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                mode              = [string] (Get-ScoutProp $_ 'properties.mode')
            }
        }
    )

    $result['fabricCapacities'] = @(
        Select-ByType 'microsoft.fabric/capacities' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
                state          = [string] (Get-ScoutProp $_ 'properties.state')
            }
        }
    )

    $result['logAnalyticsWorkspaces'] = @(
        Select-ByType 'microsoft.operationalinsights/workspaces' | ForEach-Object {
            $retention = Get-ScoutProp $_ 'properties.retentionInDays'
            [pscustomobject]@{
                id              = [string] (Get-ScoutProp $_ 'id')
                name            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup   = [string] (Get-ScoutProp $_ 'resourceGroup')
                location        = [string] (Get-ScoutProp $_ 'location')
                retentionInDays = if ($null -eq $retention) { $null } else { [int] $retention }
                # AB#9300 phase 4 -- mirrors the KQL field for field. The pricing tier lives in
                # properties.sku.name (the top-level sku column is not where it is carried).
                skuName         = [string] (Get-ScoutProp $_ 'properties.sku.name')
                dailyQuotaGb    = ConvertTo-ScoutDouble (Get-ScoutProp $_ 'properties.workspaceCapping.dailyQuotaGb')
                publicNetworkAccessForIngestion = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccessForIngestion')
                publicNetworkAccessForQuery     = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccessForQuery')
                disableLocalAuth      = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.features.disableLocalAuth')
                resourceContextAccess = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.features.enableLogAccessUsingOnlyResourcePermissions')
                replicationEnabled    = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.replication.enabled')
            }
        }
    )

    # ---- Azure Update Manager (AB#7065) — mirrors Invoke-Collect.ps1's `maintenanceConfigurations`
    # KQL field for field so the inverted (default) path costs no extra Resource Graph round-trip.
    $result['maintenanceConfigurations'] = @(
        Select-ByType 'microsoft.maintenance/maintenanceconfigurations' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                scope          = [string] (Get-ScoutProp $_ 'properties.maintenanceScope')
                recurEvery     = [string] (Get-ScoutProp $_ 'properties.maintenanceWindow.recurEvery')
                startDateTime  = [string] (Get-ScoutProp $_ 'properties.maintenanceWindow.startDateTime')
                duration       = [string] (Get-ScoutProp $_ 'properties.maintenanceWindow.duration')
                timeZone       = [string] (Get-ScoutProp $_ 'properties.maintenanceWindow.timeZone')
                rebootSetting  = [string] (Get-ScoutProp $_ 'properties.installPatches.rebootSetting')
            }
        }
    )

    # ---- AI workload domain additions (AB#6818) — mirrors Invoke-Collect.ps1's `mlWorkspaces`/
    # `searchServices` KQL field for field so the inverted (default) path costs no extra
    # Resource Graph round-trip for either.
    $result['mlWorkspaces'] = @(
        Select-ByType 'microsoft.machinelearningservices/workspaces' | ForEach-Object {
            [pscustomobject]@{
                id            = [string] (Get-ScoutProp $_ 'id')
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                location      = [string] (Get-ScoutProp $_ 'location')
                workspaceKind = [string] (Get-ScoutProp $_ 'kind')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType  = [string] (Get-ScoutProp $_ 'identity.type')
                isolationMode = [string] (Get-ScoutProp $_ 'properties.managedNetwork.isolationMode')
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                cmkStatus     = [string] (Get-ScoutProp $_ 'properties.encryption.status')
                hbiWorkspace  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.hbiWorkspace')
                v1LegacyMode  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.v1LegacyMode')
            }
        }
    )

    $result['searchServices'] = @(
        Select-ByType 'microsoft.search/searchservices' | ForEach-Object {
            $replicaRaw = Get-ScoutProp $_ 'properties.replicaCount'
            [pscustomobject]@{
                id            = [string] (Get-ScoutProp $_ 'id')
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                location      = [string] (Get-ScoutProp $_ 'location')
                sku           = [string] (Get-ScoutProp $_ 'sku.name')
                publicAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                disableLocalAuth = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAuth')
                replicaCount  = if ($null -eq $replicaRaw -or [string]::IsNullOrWhiteSpace([string]$replicaRaw)) { $null } else { [int] $replicaRaw }
                # AB#9300 phase 4 -- mirrors the KQL field for field. ipRuleCount is a COUNT; the IP
                # rules themselves are never shaped.
                identityType     = [string] (Get-ScoutProp $_ 'identity.type')
                cmkEnforcement   = [string] (Get-ScoutProp $_ 'properties.encryptionWithCmk.enforcement')
                ipRuleCount      = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.networkRuleSet.ipRules')
                semanticSearch   = [string] (Get-ScoutProp $_ 'properties.semanticSearch')
                partitionCount   = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.partitionCount')
            }
        }
    )

    # ---- AI + Machine Learning coverage-gap close-out (AB#7086, folds in AB#7071) — mirrors
    # Invoke-Collect.ps1's `videoIndexerAccounts`/`healthBots`/`planetaryComputerGeoCatalogs`
    # KQL fields field for field so the inverted (default) path costs no extra round-trip.
    $result['videoIndexerAccounts'] = @(
        Select-ByType 'microsoft.videoindexer/accounts' | ForEach-Object {
            [pscustomobject]@{
                name                          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup                 = [string] (Get-ScoutProp $_ 'resourceGroup')
                publicAccess                  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                identityType                  = [string] (Get-ScoutProp $_ 'identity.type')
                privateEndpointConnectionCount = Measure-ScoutArray (Get-ScoutProp $_ 'properties.privateEndpointConnections')
                openAiLinked                  = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.openAiServices.resourceId'))
            }
        }
    )

    $result['healthBots'] = @(
        Select-ByType 'microsoft.healthbot/healthbots' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                skuName       = [string] (Get-ScoutProp $_ 'sku.name')
                identityType  = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    $result['planetaryComputerGeoCatalogs'] = @(
        Select-ByType 'microsoft.orbital/geocatalogs' | ForEach-Object {
            [pscustomobject]@{
                name          = [string] (Get-ScoutProp $_ 'name')
                resourceGroup = [string] (Get-ScoutProp $_ 'resourceGroup')
                tier          = [string] (Get-ScoutProp $_ 'properties.tier')
                identityType  = [string] (Get-ScoutProp $_ 'identity.type')
            }
        }
    )

    # ---- AVD (on Azure Local) workload domain additions (AB#6819) — mirrors Invoke-Collect.ps1's
    # `avdHostPools`/`avdSessionHosts`/`avdScalingPlans` KQL field for field.
    $result['avdHostPools'] = @(
        Select-ByType 'microsoft.desktopvirtualization/hostpools' | ForEach-Object {
            $maxSessionRaw = Get-ScoutProp $_ 'properties.maxSessionLimit'
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                location         = [string] (Get-ScoutProp $_ 'location')
                hostPoolType     = [string] (Get-ScoutProp $_ 'properties.hostPoolType')
                loadBalancerType = [string] (Get-ScoutProp $_ 'properties.loadBalancerType')
                maxSessionLimit  = if ($null -eq $maxSessionRaw) { $null } else { [int] $maxSessionRaw }
                startVMOnConnect      = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.startVMOnConnect')
                validationEnvironment = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.validationEnvironment')
                publicNetworkAccess   = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                agentUpdateType       = [string] (Get-ScoutProp $_ 'properties.agentUpdate.type')
                preferredAppGroupType = [string] (Get-ScoutProp $_ 'properties.preferredAppGroupType')
            }
        }
    )

    # hostPoolName = split(id, "/sessionHosts/")[0] -- the KQL projection deliberately omits
    # resourceGroup for this type, matched here.
    $result['avdSessionHosts'] = @(
        Select-ByType 'microsoft.desktopvirtualization/hostpools/sessionhosts' | ForEach-Object {
            $id = [string] (Get-ScoutProp $_ 'id')
            [pscustomobject]@{
                name         = [string] (Get-ScoutProp $_ 'name')
                hostPoolName = ($id -split '/sessionHosts/')[0]
                status       = [string] (Get-ScoutProp $_ 'properties.status')
                agentVersion = [string] (Get-ScoutProp $_ 'properties.agentVersion')
                resourceId   = [string] (Get-ScoutProp $_ 'properties.resourceId')
                updateState  = [string] (Get-ScoutProp $_ 'properties.updateState')
            }
        }
    )

    $result['avdScalingPlans'] = @(
        Select-ByType 'microsoft.desktopvirtualization/scalingplans' | ForEach-Object {
            [pscustomobject]@{
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                hostPoolRefCount = Measure-ScoutArray (Get-ScoutProp $_ 'properties.hostPoolReferences')
                # Host pools this plan actually scales (scalingPlanEnabled), lower-cased like the KQL.
                enabledHostPools = @(@(Get-ScoutProp $_ 'properties.hostPoolReferences') | Where-Object {
                        $null -ne $_ -and (ConvertTo-ScoutBool (Get-ScoutProp $_ 'scalingPlanEnabled')) -eq $true
                    } | ForEach-Object { ([string] (Get-ScoutProp $_ 'hostPoolArmPath')).ToLowerInvariant() } |
                    Where-Object { $_ } | Select-Object -Unique | ForEach-Object { [pscustomobject]@{ id = $_ } })
            }
        }
    )

    $result['avdWorkspaces'] = @(
        Select-ByType 'microsoft.desktopvirtualization/workspaces' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                location            = [string] (Get-ScoutProp $_ 'location')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    # ---- FinOps / DevOps Capability enumerations (AB#6826/AB#6827, Feature AB#6749) -----------
    # Same shape/fields as the matching KQL query in Invoke-Collect.ps1's $q hashtable -- this
    # is the shaper those live queries are the reference implementation for (AB#5648's own
    # pattern), so the inverted (default) path costs no extra Resource Graph round-trip for any
    # of these six.
    $result['reservations'] = @(
        Select-ByType 'microsoft.capacity/reservationorders/reservations' | ForEach-Object {
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                name             = [string] (Get-ScoutProp $_ 'name')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                sku              = [string] (Get-ScoutProp $_ 'sku.name')
            }
        }
    )

    $result['managedDevOpsPools'] = @(
        Select-ByType 'microsoft.devopsinfrastructure/pools' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
            }
        }
    )

    $result['devCenters'] = @(
        $rows | Where-Object {
            $t = [string] (Get-ScoutProp $_ 'type')
            $t -ieq 'microsoft.devcenter/devcenters' -or $t -ieq 'microsoft.devcenter/projects'
        } | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                type           = [string] (Get-ScoutProp $_ 'type')
            }
        }
    )

    $result['loadTesting'] = @(
        Select-ByType 'microsoft.loadtestservice/loadtests' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
            }
        }
    )

    $result['chaosExperiments'] = @(
        Select-ByType 'microsoft.chaos/experiments' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
            }
        }
    )

    $result['playwrightTesting'] = @(
        Select-ByType 'microsoft.azureplaywrightservice/accounts' | ForEach-Object {
            [pscustomobject]@{
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
            }
        }
    )

    # ---- Defender-for-Cloud detail: WAF/DDoS/ASG (AB#7063, Story AB#7059, Feature AB#7069,
    # Epic AB#7099) -- mirrors Invoke-Collect.ps1's wafPolicies/ddosProtectionPlans/
    # applicationSecurityGroups KQL field for field -- the default `-FromInventory` path costs
    # no extra Resource Graph round trip for any of these three. DefenderAlerts/
    # DefenderAssessments/DefenderSecureScore/DefenderPricing are NOT shaped here -- see
    # Invoke-Collect.ps1's query-pack comment for why.
    $result['wafPolicies'] = @(
        $rows | Where-Object {
            $t = [string] (Get-ScoutProp $_ 'type')
            $t -ieq 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies' -or
            $t -ieq 'microsoft.network/frontdoorwebapplicationfirewallpolicies' -or
            $t -ieq 'microsoft.cdn/cdnwebapplicationfirewallpolicies'
        } | ForEach-Object {
            $enabledStateRaw = Get-ScoutProp $_ 'properties.policySettings.enabledState'
            $stateRaw = Get-ScoutProp $_ 'properties.policySettings.state'
            $enabledState = if (-not [string]::IsNullOrEmpty([string] $enabledStateRaw)) { [string] $enabledStateRaw } else { [string] $stateRaw }
            $customRuleRules = Get-ScoutPropArray $_ 'properties.customRules.rules'
            $customRuleCount = if ($null -ne $customRuleRules) { Measure-ScoutArray $customRuleRules } else { Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.customRules') }
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId       = [string] (Get-ScoutProp $_ 'subscriptionId')
                location             = [string] (Get-ScoutProp $_ 'location')
                type                 = [string] (Get-ScoutProp $_ 'type')
                sku                  = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState    = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                enabledState         = $enabledState
                mode                 = [string] (Get-ScoutProp $_ 'properties.policySettings.mode')
                managedRuleSetCount  = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.managedRules.managedRuleSets')
                customRuleCount      = $customRuleCount
            }
        }
    )

    $result['ddosProtectionPlans'] = @(
        Select-ByType 'microsoft.network/ddosprotectionplans' | ForEach-Object {
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId     = [string] (Get-ScoutProp $_ 'subscriptionId')
                location           = [string] (Get-ScoutProp $_ 'location')
                provisioningState  = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                protectedVNetCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.virtualNetworks')
                resourceGuid       = [string] (Get-ScoutProp $_ 'properties.resourceGuid')
            }
        }
    )

    $result['applicationSecurityGroups'] = @(
        Select-ByType 'microsoft.network/applicationsecuritygroups' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                resourceGuid      = [string] (Get-ScoutProp $_ 'properties.resourceGuid')
            }
        }
    )

    # ---- Azure Local child resources (AB#7061, Story AB#7059, Feature AB#7069, Epic AB#7099) ----
    # Mirrors Invoke-Collect.ps1's customLocations/arcDataControllers/arcGateways/arcKubernetes/
    # arcResourceBridge/arcSqlManagedInstances/arcSqlServers/galleryImages/
    # marketplaceGalleryImages/storageContainers KQL field for field -- the inverted (default)
    # `-FromInventory` path costs no extra Resource Graph round-trip for any of these ten.
    $result['customLocations'] = @(
        Select-ByType 'microsoft.extendedlocation/customlocations' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                hostResourceId    = [string] (Get-ScoutProp $_ 'properties.hostResourceId')
                hostType          = [string] (Get-ScoutProp $_ 'properties.hostType')
                namespace         = [string] (Get-ScoutProp $_ 'properties.namespace')
            }
        }
    )

    $result['arcDataControllers'] = @(
        Select-ByType 'microsoft.azurearcdata/datacontrollers' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                infrastructure    = [string] (Get-ScoutProp $_ 'properties.infrastructure')
                k8sNamespace      = [string] (Get-ScoutProp $_ 'properties.k8sRaw.metadata.namespace')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['arcGateways'] = @(
        Select-ByType 'microsoft.hybridcompute/gateways' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                gatewayType       = [string] (Get-ScoutProp $_ 'properties.gatewayType')
                gatewayEndpoint   = [string] (Get-ScoutProp $_ 'properties.gatewayEndpoint')
            }
        }
    )

    $result['arcKubernetes'] = @(
        Select-ByType 'microsoft.kubernetes/connectedclusters' | ForEach-Object {
            $totalNodeCountRaw = Get-ScoutProp $_ 'properties.totalNodeCount'
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId     = [string] (Get-ScoutProp $_ 'subscriptionId')
                location           = [string] (Get-ScoutProp $_ 'location')
                provisioningState  = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                connectivityStatus = [string] (Get-ScoutProp $_ 'properties.connectivityStatus')
                distribution       = [string] (Get-ScoutProp $_ 'properties.distribution')
                kubernetesVersion  = [string] (Get-ScoutProp $_ 'properties.kubernetesVersion')
                totalNodeCount     = if ($null -eq $totalNodeCountRaw) { $null } else { [int] $totalNodeCountRaw }
            }
        }
    )

    $result['arcResourceBridge'] = @(
        Select-ByType 'microsoft.resourceconnector/appliances' | ForEach-Object {
            [pscustomobject]@{
                id                      = [string] (Get-ScoutProp $_ 'id')
                name                    = [string] (Get-ScoutProp $_ 'name')
                resourceGroup           = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId          = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                = [string] (Get-ScoutProp $_ 'location')
                provisioningState       = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                status                  = [string] (Get-ScoutProp $_ 'properties.status')
                distro                  = [string] (Get-ScoutProp $_ 'properties.distro')
                version                 = [string] (Get-ScoutProp $_ 'properties.version')
                infrastructureProvider  = [string] (Get-ScoutProp $_ 'properties.infrastructureConfig.provider')
            }
        }
    )

    $result['arcSqlManagedInstances'] = @(
        Select-ByType 'microsoft.azurearcdata/sqlmanagedinstances' | ForEach-Object {
            $vCoresRequestRaw = Get-ScoutProp $_ 'properties.vCores.request'
            $vCoresLimitRaw = Get-ScoutProp $_ 'properties.vCores.limit'
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                dataControllerId  = [string] (Get-ScoutProp $_ 'properties.dataControllerId')
                tier              = [string] (Get-ScoutProp $_ 'properties.tier')
                vCoresRequest     = if ($null -eq $vCoresRequestRaw) { $null } else { [int] $vCoresRequestRaw }
                vCoresLimit       = if ($null -eq $vCoresLimitRaw) { $null } else { [int] $vCoresLimitRaw }
            }
        }
    )

    $result['arcSqlServers'] = @(
        Select-ByType 'microsoft.azurearcdata/sqlserverinstances' | ForEach-Object {
            $vCoreRaw = Get-ScoutProp $_ 'properties.vCore'
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                provisioningState   = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                version             = [string] (Get-ScoutProp $_ 'properties.version')
                edition             = [string] (Get-ScoutProp $_ 'properties.edition')
                licenseType         = [string] (Get-ScoutProp $_ 'properties.licenseType')
                vCore               = if ($null -eq $vCoreRaw) { $null } else { [int] $vCoreRaw }
                patchLevel          = [string] (Get-ScoutProp $_ 'properties.patchLevel')
                azureDefenderStatus = [string] (Get-ScoutProp $_ 'properties.azureDefenderStatus')
            }
        }
    )

    $result['galleryImages'] = @(
        Select-ByType 'microsoft.azurestackhci/galleryimages' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                osType            = [string] (Get-ScoutProp $_ 'properties.osType')
                hyperVGeneration  = [string] (Get-ScoutProp $_ 'properties.hyperVGeneration')
                publisher         = [string] (Get-ScoutProp $_ 'properties.identifier.publisher')
                offer             = [string] (Get-ScoutProp $_ 'properties.identifier.offer')
                sku               = [string] (Get-ScoutProp $_ 'properties.identifier.sku')
                imageVersion      = [string] (Get-ScoutProp $_ 'properties.version.name')
            }
        }
    )

    $result['marketplaceGalleryImages'] = @(
        Select-ByType 'microsoft.azurestackhci/marketplacegalleryimages' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                status            = [string] (Get-ScoutProp $_ 'properties.status.provisioningStatus.status')
                osType            = [string] (Get-ScoutProp $_ 'properties.osType')
                hyperVGeneration  = [string] (Get-ScoutProp $_ 'properties.hyperVGeneration')
                publisher         = [string] (Get-ScoutProp $_ 'properties.identifier.publisher')
                offer             = [string] (Get-ScoutProp $_ 'properties.identifier.offer')
                sku               = [string] (Get-ScoutProp $_ 'properties.identifier.sku')
                imageVersion      = [string] (Get-ScoutProp $_ 'properties.version.name')
            }
        }
    )

    $result['storageContainers'] = @(
        Select-ByType 'microsoft.azurestackhci/storagecontainers' | ForEach-Object {
            $availableBytesRaw = Get-ScoutProp $_ 'properties.status.availableSizeBytes'
            $containerBytesRaw = Get-ScoutProp $_ 'properties.status.containerSizeBytes'
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                status            = [string] (Get-ScoutProp $_ 'properties.status.provisioningStatus.status')
                path              = [string] (Get-ScoutProp $_ 'properties.path')
                availableSizeGB   = if ($null -eq $availableBytesRaw) { $null } else { [math]::Round([double] $availableBytesRaw / 1GB, 2) }
                containerSizeGB   = if ($null -eq $containerBytesRaw) { $null } else { [math]::Round([double] $containerBytesRaw / 1GB, 2) }
            }
        }
    )

    # ---- Azure Monitor plumbing (AB#7064, Story AB#7059, Feature AB#7069, Epic AB#7099) --------
    # Mirrors Invoke-Collect.ps1's dataCollectionRules/dataCollectionEndpoints/actionGroups/
    # autoscaleSettings/metricAlertRules/scheduledQueryRules/activityLogAlertRules/
    # smartDetectorAlertRules/appInsights/workbooks/privateLinkScopes/workspaceSolutions/
    # appInsightsAvailabilityTests KQL field for field -- the inverted (default) `-FromInventory`
    # path costs no extra Resource Graph round-trip for any of these thirteen.
    $result['dataCollectionRules'] = @(
        Select-ByType 'microsoft.insights/datacollectionrules' | ForEach-Object {
            $dataFlowCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.dataFlows')
            [pscustomobject]@{
                id                          = [string] (Get-ScoutProp $_ 'id')
                name                        = [string] (Get-ScoutProp $_ 'name')
                resourceGroup               = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId              = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                    = [string] (Get-ScoutProp $_ 'location')
                dataCollectionEndpointId    = [string] (Get-ScoutProp $_ 'properties.dataCollectionEndpointId')
                hasLogAnalyticsDestination  = ($null -ne (Get-ScoutProp $_ 'properties.destinations.logAnalytics'))
                dataFlowCount               = $dataFlowCount
                immutableId                 = [string] (Get-ScoutProp $_ 'properties.immutableId')
            }
        }
    )

    $result['dataCollectionEndpoints'] = @(
        Select-ByType 'microsoft.insights/datacollectionendpoints' | ForEach-Object {
            [pscustomobject]@{
                id                           = [string] (Get-ScoutProp $_ 'id')
                name                         = [string] (Get-ScoutProp $_ 'name')
                resourceGroup                = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId               = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                     = [string] (Get-ScoutProp $_ 'location')
                publicNetworkAccess          = [string] (Get-ScoutProp $_ 'properties.networkAcls.publicNetworkAccess')
                configurationAccessEndpoint  = [string] (Get-ScoutProp $_ 'properties.configurationAccess.endpoint')
                immutableId                  = [string] (Get-ScoutProp $_ 'properties.immutableId')
            }
        }
    )

    $result['actionGroups'] = @(
        Select-ByType 'microsoft.insights/actiongroups' | ForEach-Object {
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId       = [string] (Get-ScoutProp $_ 'subscriptionId')
                enabled              = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enabled')
                groupShortName       = [string] (Get-ScoutProp $_ 'properties.groupShortName')
                emailReceiverCount   = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.emailReceivers')
                smsReceiverCount     = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.smsReceivers')
                webhookReceiverCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.webhookReceivers')
            }
        }
    )

    $result['autoscaleSettings'] = @(
        Select-ByType 'microsoft.insights/autoscalesettings' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                enabled           = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enabled')
                targetResourceUri = [string] (Get-ScoutProp $_ 'properties.targetResourceUri')
                profileCount      = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.profiles')
            }
        }
    )

    $result['metricAlertRules'] = @(
        Select-ByType 'microsoft.insights/metricalerts' | ForEach-Object {
            $severityRaw = Get-ScoutProp $_ 'properties.severity'
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                enabled          = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enabled')
                severity         = if ($null -eq $severityRaw) { $null } else { [int] $severityRaw }
                autoMitigate     = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.autoMitigate')
                scopeCount       = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.scopes')
                actionGroupCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.actions')
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                targetResourceType = [string] (Get-ScoutProp $_ 'properties.targetResourceType')
            }
        }
    )

    $result['scheduledQueryRules'] = @(
        Select-ByType 'microsoft.insights/scheduledqueryrules' | ForEach-Object {
            $severityRaw = Get-ScoutProp $_ 'properties.severity'
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                enabled        = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enabled')
                severity       = if ($null -eq $severityRaw) { $null } else { [int] $severityRaw }
                autoMitigate   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.autoMitigate')
                kind           = [string] (Get-ScoutProp $_ 'properties.kind')
                scopeCount     = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.scopes')
            }
        }
    )

    # `category` is the `equals` of the properties.condition.allOf[] entry whose field is
    # "category" (Administrative / ServiceHealth / ResourceHealth / Security / ...): $null when
    # no entry names one, exactly as the KQL mv-apply reads it. An entry with no `equals` (a
    # `containsAny` condition) does not count, like the KQL's isnotempty() filter.
    $result['activityLogAlertRules'] = @(
        Select-ByType 'microsoft.insights/activitylogalerts' | ForEach-Object {
            $conditions = Get-ScoutPropArray $_ 'properties.condition.allOf'
            $alertCategory = $null
            foreach ($condition in @($conditions)) {
                if ($null -eq $condition) { continue }
                if (([string] (Get-ScoutProp $condition 'field')) -ine 'category') { continue }
                $equalsValue = [string] (Get-ScoutProp $condition 'equals')
                if ([string]::IsNullOrEmpty($equalsValue)) { continue }
                $alertCategory = $equalsValue
                break
            }
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                enabled          = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enabled')
                scopeCount       = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.scopes')
                actionGroupCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.actions.actionGroups')
                category         = $alertCategory
            }
        }
    )

    $result['smartDetectorAlertRules'] = @(
        Select-ByType 'microsoft.alertsmanagement/smartdetectoralertrules' | ForEach-Object {
            [pscustomobject]@{
                id               = [string] (Get-ScoutProp $_ 'id')
                name             = [string] (Get-ScoutProp $_ 'name')
                resourceGroup    = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId   = [string] (Get-ScoutProp $_ 'subscriptionId')
                state            = [string] (Get-ScoutProp $_ 'properties.state')
                severity         = [string] (Get-ScoutProp $_ 'properties.severity')
                frequency        = [string] (Get-ScoutProp $_ 'properties.frequency')
                actionGroupCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.actionGroups.groupIds')
            }
        }
    )

    $result['appInsights'] = @(
        Select-ByType 'microsoft.insights/components' | ForEach-Object {
            $retentionRaw = Get-ScoutProp $_ 'properties.RetentionInDays'
            [pscustomobject]@{
                id                              = [string] (Get-ScoutProp $_ 'id')
                name                            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup                   = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId                  = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                        = [string] (Get-ScoutProp $_ 'location')
                applicationType                 = [string] (Get-ScoutProp $_ 'properties.Application_Type')
                flowType                        = [string] (Get-ScoutProp $_ 'properties.Flow_Type')
                retentionInDays                 = if ($null -eq $retentionRaw) { $null } else { [int] $retentionRaw }
                samplingPercentage              = [string] (Get-ScoutProp $_ 'properties.SamplingPercentage')
                ingestionMode                   = [string] (Get-ScoutProp $_ 'properties.IngestionMode')
                publicNetworkAccessForIngestion = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccessForIngestion')
                publicNetworkAccessForQuery     = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccessForQuery')
                # AB#9300 phase 4 -- mirrors the KQL field for field. Both properties are
                # PascalCase in the ARM payload. workspaceBased is a BOOL ONLY (the workspace
                # resource id itself is never shaped).
                workspaceBased                  = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.WorkspaceResourceId'))
                disableLocalAuth                = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.DisableLocalAuth')
                # AB#9300 (depth wiring) -- mirrors the KQL: true means IP address masking is turned OFF
                # (full client addresses are stored); null when the property is not on the row.
                disableIpMasking                = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.DisableIpMasking')
            }
        }
    )

    $result['workbooks'] = @(
        Select-ByType 'microsoft.insights/workbooks' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                kind           = [string] (Get-ScoutProp $_ 'kind')
                category       = [string] (Get-ScoutProp $_ 'properties.category')
                sourceId       = [string] (Get-ScoutProp $_ 'properties.sourceId')
                version        = [string] (Get-ScoutProp $_ 'properties.version')
            }
        }
    )

    $result['privateLinkScopes'] = @(
        Select-ByType 'microsoft.insights/privatelinkscopes' | ForEach-Object {
            [pscustomobject]@{
                id                              = [string] (Get-ScoutProp $_ 'id')
                name                            = [string] (Get-ScoutProp $_ 'name')
                resourceGroup                   = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId                  = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                        = [string] (Get-ScoutProp $_ 'location')
                accessMode                      = [string] (Get-ScoutProp $_ 'properties.accessModeSettings.queryAccessMode')
                ingestionAccessMode             = [string] (Get-ScoutProp $_ 'properties.accessModeSettings.ingestionAccessMode')
                privateEndpointConnectionCount  = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.privateEndpointConnections')
                scopedResourceCount             = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.scopedResources')
            }
        }
    )

    $result['workspaceSolutions'] = @(
        Select-ByType 'microsoft.operationsmanagement/solutions' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                workspaceResourceId = [string] (Get-ScoutProp $_ 'properties.workspaceResourceId')
                planName            = [string] (Get-ScoutProp $_ 'plan.name')
                planPublisher       = [string] (Get-ScoutProp $_ 'plan.publisher')
                planProduct         = [string] (Get-ScoutProp $_ 'plan.product')
            }
        }
    )

    # `AppInsightsAvailabilityTests.psd1` and `AppInsightsWebTests.psd1` both match
    # `microsoft.insights/webtests` -- AvailabilityTests carries no `AdditionalFilter` (every
    # Kind), WebTests filters `$_.KIND -eq 'standard'` (a strict subset). One combined array over
    # every webtest row, carrying `kind` per row, reproduces both manifests' scope; a consumer
    # that needs the WebTests-only subset filters this array on `kind -eq 'standard'` the same way
    # the manifest's AdditionalFilter does.
    $result['appInsightsAvailabilityTests'] = @(
        Select-ByType 'microsoft.insights/webtests' | ForEach-Object {
            $frequencyRaw = Get-ScoutProp $_ 'properties.Frequency'
            $timeoutRaw = Get-ScoutProp $_ 'properties.Timeout'
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                kind                = [string] (Get-ScoutProp $_ 'kind')
                enabled             = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.Enabled')
                frequency           = if ($null -eq $frequencyRaw) { $null } else { [int] $frequencyRaw }
                timeoutSeconds      = if ($null -eq $timeoutRaw) { $null } else { [int] $timeoutRaw }
                syntheticMonitorId  = [string] (Get-ScoutProp $_ 'properties.SyntheticMonitorId')
                testLocationCount   = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.Locations')
            }
        }
    )


    $result['cosmosDbAccounts'] = @(
        Select-ByType 'microsoft.documentdb/databaseaccounts' | ForEach-Object {
            # AB#9300 phase 4 -- mirrors the KQL. zoneRedundantRegionCount counts the locations whose
            # isZoneRedundant flag is true (a location with no flag counts as not redundant); an
            # account with no locations array reads 0, like the KQL's one-element placeholder.
            $locations = Get-ScoutPropArray $_ 'properties.locations'
            $zoneRedundantRegions = 0
            foreach ($cosmosLocation in @($locations)) {
                if ($null -eq $cosmosLocation) { continue }
                if ((ConvertTo-ScoutBool (Get-ScoutProp $cosmosLocation 'isZoneRedundant')) -eq $true) { $zoneRedundantRegions++ }
            }
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                kind                = [string] (Get-ScoutProp $_ 'kind')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                disableLocalAuth    = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableLocalAuth')
                regionCount              = Measure-ScoutArray $locations
                zoneRedundantRegionCount = $zoneRedundantRegions
                automaticFailover   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableAutomaticFailover')
                backupType          = [string] (Get-ScoutProp $_ 'properties.backupPolicy.type')
                multiRegionWrites   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableMultipleWriteLocations')
                minimalTlsVersion   = [string] (Get-ScoutProp $_ 'properties.minimalTlsVersion')
                vnetFilterEnabled   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.isVirtualNetworkFilterEnabled')
                # A COUNT -- the IP ranges and the key vault key uri are never shaped.
                ipRuleCount         = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.ipRules')
                cmkEnabled          = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.keyVaultKeyUri'))
            }
        }
    )

    $result['mariaDbServers'] = @(
        Select-ByType 'microsoft.dbformariadb/servers' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'sku.name')
                sslEnforcement      = [string] (Get-ScoutProp $_ 'properties.sslEnforcement')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['mySqlServers'] = @(
        Select-ByType 'microsoft.dbformysql/servers' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'sku.name')
                sslEnforcement      = [string] (Get-ScoutProp $_ 'properties.sslEnforcement')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['mySqlFlexibleServers'] = @(
        Select-ByType 'microsoft.dbformysql/flexibleservers' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'sku.name')
                version             = [string] (Get-ScoutProp $_ 'properties.version')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.network.publicNetworkAccess')
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                haMode              = [string] (Get-ScoutProp $_ 'properties.highAvailability.mode')
                geoBackup           = [string] (Get-ScoutProp $_ 'properties.backup.geoRedundantBackup')
                backupRetentionDays = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.backup.backupRetentionDays')
                encryptionType      = [string] (Get-ScoutProp $_ 'properties.dataEncryption.type')
                storageAutoGrow     = [string] (Get-ScoutProp $_ 'properties.storage.autoGrow')
            }
        }
    )

    $result['postgreSqlFlexibleServers'] = @(
        Select-ByType 'microsoft.dbforpostgresql/flexibleservers' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'sku.name')
                version             = [string] (Get-ScoutProp $_ 'properties.version')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.network.publicNetworkAccess')
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                tier                = [string] (Get-ScoutProp $_ 'sku.tier')
                haMode              = [string] (Get-ScoutProp $_ 'properties.highAvailability.mode')
                geoBackup           = [string] (Get-ScoutProp $_ 'properties.backup.geoRedundantBackup')
                backupRetentionDays = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.backup.backupRetentionDays')
                encryptionType      = [string] (Get-ScoutProp $_ 'properties.dataEncryption.type')
                entraAuth           = [string] (Get-ScoutProp $_ 'properties.authConfig.activeDirectoryAuth')
                passwordAuth        = [string] (Get-ScoutProp $_ 'properties.authConfig.passwordAuth')
                # AB#9300 (depth wiring) -- mirrors the KQL: Enabled / Disabled, '' when the row does not say.
                customMaintenanceWindow = [string] (Get-ScoutProp $_ 'properties.maintenanceWindow.customWindow')
            }
        }
    )

    # AB#9300 phase 4 -- classic Cache for Redis (microsoft.cache/redis) keeps its SKU under
    # properties.sku (the top-level `sku` is absent); Redis Enterprise keeps it in the top-level
    # `sku`. skuFamily / skuCapacity exist only on the classic properties.sku. NEVER read
    # properties.redisConfiguration as a whole: it holds the rdb/aof storage CONNECTION STRINGS.
    # The single key aad-enabled is read by name and nothing else.
    $result['redisCaches'] = @(
        Select-ByAnyType @('microsoft.cache/redis', 'microsoft.cache/redisenterprise') | ForEach-Object {
            $redisIsClassic = ([string] (Get-ScoutProp $_ 'type')) -ieq 'microsoft.cache/redis'
            $redisReplicas = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.replicasPerMaster')
            if ($null -eq $redisReplicas) { $redisReplicas = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.replicasPerPrimary') }
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                type                = [string] (Get-ScoutProp $_ 'type')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = if ($redisIsClassic) { [string] (Get-ScoutProp $_ 'properties.sku.name') } else { [string] (Get-ScoutProp $_ 'sku.name') }
                skuFamily           = [string] (Get-ScoutProp $_ 'properties.sku.family')
                skuCapacity         = ConvertTo-ScoutInt (Get-ScoutProp $_ 'properties.sku.capacity')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
                zoneCount           = Measure-ScoutArray (Get-ScoutPropArray $_ 'zones')
                zonalAllocationPolicy = [string] (Get-ScoutProp $_ 'properties.zonalAllocationPolicy')
                replicasPerPrimary  = $redisReplicas
                minimumTlsVersion   = [string] (Get-ScoutProp $_ 'properties.minimumTlsVersion')
                nonSslPortEnabled   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.enableNonSslPort')
                # Classic: absent = Azure's default (keys allowed) = false. Enterprise: null (database-level).
                accessKeyAuthDisabled = $(
                    $keyFlag = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.disableAccessKeyAuthentication')
                    if ($redisIsClassic -and $null -eq $keyFlag) { $false } else { $keyFlag })
                aadEnabled          = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.redisConfiguration.aad-enabled')
                highAvailability    = [string] (Get-ScoutProp $_ 'properties.highAvailability')
            }
        }
    )

    $result['sqlManagedInstances'] = @(
        Select-ByType 'microsoft.sql/managedinstances' | ForEach-Object {
            $vCoresRaw = Get-ScoutProp $_ 'sku.capacity'
            [pscustomobject]@{
                id                          = [string] (Get-ScoutProp $_ 'id')
                name                        = [string] (Get-ScoutProp $_ 'name')
                resourceGroup               = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId              = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                    = [string] (Get-ScoutProp $_ 'location')
                sku                         = [string] (Get-ScoutProp $_ 'sku.name')
                publicDataEndpointEnabled   = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.publicDataEndpointEnabled')
                vCores                      = if ($null -eq $vCoresRaw) { $null } else { [int] $vCoresRaw }
                # AB#9300 phase 4 -- mirrors the KQL field for field. The administrator's sid /
                # tenantId / login are never read; entraOnlyAuth is the one boolean taken from
                # properties.administrators.
                zoneRedundant               = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                backupRedundancy            = [string] (Get-ScoutProp $_ 'properties.requestedBackupStorageRedundancy')
                entraOnlyAuth               = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.administrators.azureADOnlyAuthentication')
                minimalTlsVersion           = [string] (Get-ScoutProp $_ 'properties.minimalTlsVersion')
                cmkEnabled                  = -not [string]::IsNullOrEmpty([string] (Get-ScoutProp $_ 'properties.keyId'))
            }
        }
    )

    $result['sqlManagedInstanceDatabases'] = @(
        Select-ByType 'microsoft.sql/managedinstances/databases' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                status         = [string] (Get-ScoutProp $_ 'properties.status')
            }
        }
    )

    $result['sqlElasticPools'] = @(
        Select-ByType 'microsoft.sql/servers/elasticpools' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                skuName        = [string] (Get-ScoutProp $_ 'sku.name')
                skuTier        = [string] (Get-ScoutProp $_ 'sku.tier')
            }
        }
    )

    $result['sqlVirtualMachines'] = @(
        Select-ByType 'microsoft.sqlvirtualmachine/sqlvirtualmachines' | ForEach-Object {
            [pscustomobject]@{
                id                    = [string] (Get-ScoutProp $_ 'id')
                name                  = [string] (Get-ScoutProp $_ 'name')
                resourceGroup         = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId        = [string] (Get-ScoutProp $_ 'subscriptionId')
                location              = [string] (Get-ScoutProp $_ 'location')
                sqlImageSku           = [string] (Get-ScoutProp $_ 'properties.sqlImageSku')
                sqlServerLicenseType  = [string] (Get-ScoutProp $_ 'properties.sqlServerLicenseType')
            }
        }
    )

    # ---- AB#7090 (Story AB#7071/AB#7059, Feature AB#7069, Epic AB#7099) -- Databases
    # coverage-gap close-out. Mirrors Invoke-Collect.ps1's KQL field for field.
    $result['documentDbMongoClusters'] = @(
        Select-ByType 'microsoft.documentdb/mongoclusters' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'properties.compute.tier')
                provisioningState   = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['managedCassandraClusters'] = @(
        Select-ByType 'microsoft.documentdb/cassandraclusters' | ForEach-Object {
            [pscustomobject]@{
                id                     = [string] (Get-ScoutProp $_ 'id')
                name                   = [string] (Get-ScoutProp $_ 'name')
                resourceGroup          = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId         = [string] (Get-ScoutProp $_ 'subscriptionId')
                location               = [string] (Get-ScoutProp $_ 'location')
                provisioningState      = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                cassandraVersion       = [string] (Get-ScoutProp $_ 'properties.cassandraVersion')
                authenticationMethod   = [string] (Get-ScoutProp $_ 'properties.authenticationMethod')
            }
        }
    )

    # ---- Web plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) --------------------
    # Mirrors Invoke-Collect.ps1's appServiceCertificates/appServiceDomains/appServiceEnvironments/
    # appServicePlans/communicationServices/webAppDeploymentSlots/fluidRelayServers/
    # notificationHubNamespaces/signalRServices/springApps/staticWebApps/webPubSubServices.
    $result['appServiceCertificates'] = @(
        Select-ByAnyType @('microsoft.certificateregistration/certificateorders', 'microsoft.web/certificates') | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                type           = [string] (Get-ScoutProp $_ 'type')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                keyVaultId     = [string] (Get-ScoutProp $_ 'properties.keyVaultId')
            }
        }
    )

    $result['appServiceDomains'] = @(
        Select-ByType 'microsoft.domainregistration/domains' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['appServiceEnvironments'] = @(
        Select-ByType 'microsoft.web/hostingenvironments' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                status         = [string] (Get-ScoutProp $_ 'properties.status')
                kind           = [string] (Get-ScoutProp $_ 'kind')
            }
        }
    )

    $result['appServicePlans'] = @(
        Select-ByType 'microsoft.web/serverfarms' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
                reserved       = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.reserved')
                # AB#9300 phase 4 -- mirrors the KQL field for field.
                zoneRedundant  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
                instanceCount  = ConvertTo-ScoutInt (Get-ScoutProp $_ 'sku.capacity')
                tier           = [string] (Get-ScoutProp $_ 'sku.tier')
            }
        }
    )

    $result['communicationServices'] = @(
        Select-ByAnyType @('microsoft.communication/communicationservices', 'microsoft.communication/emailservices',
                         'microsoft.communication/emailservices/domains') | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                type              = [string] (Get-ScoutProp $_ 'type')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['webAppDeploymentSlots'] = @(
        Select-ByType 'microsoft.web/sites/slots' | ForEach-Object {
            $id = [string] (Get-ScoutProp $_ 'id')
            [pscustomobject]@{
                id             = $id
                name           = [string] (Get-ScoutProp $_ 'name')
                siteName       = $id.Split('/slots/')[0]
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                state          = [string] (Get-ScoutProp $_ 'properties.state')
            }
        }
    )

    $result['fluidRelayServers'] = @(
        Select-ByType 'microsoft.fluidrelay/fluidrelayservers' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['notificationHubNamespaces'] = @(
        Select-ByAnyType @('microsoft.notificationhubs/namespaces', 'microsoft.notificationhubs/namespaces/notificationhubs') | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                type              = [string] (Get-ScoutProp $_ 'type')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['signalRServices'] = @(
        Select-ByType 'microsoft.signalrservice/signalr' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'sku.name')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['springApps'] = @(
        Select-ByAnyType @('microsoft.appplatform/spring', 'microsoft.appplatform/spring/apps') | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                type           = [string] (Get-ScoutProp $_ 'type')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
                zoneRedundant  = ConvertTo-ScoutBool (Get-ScoutProp $_ 'properties.zoneRedundant')
            }
        }
    )

    $result['staticWebApps'] = @(
        Select-ByType 'microsoft.web/staticsites' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['webPubSubServices'] = @(
        Select-ByType 'microsoft.signalrservice/webpubsub' | ForEach-Object {
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                resourceGroup       = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                location            = [string] (Get-ScoutProp $_ 'location')
                sku                 = [string] (Get-ScoutProp $_ 'sku.name')
                publicNetworkAccess = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    # ---- Security plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) ---------------
    # Mirrors Invoke-Collect.ps1's appComplianceReports/applicationSecurityGroups/
    # artifactSigningAccounts/cloudHsmClusters/confidentialLedgers/ddosProtectionPlans/
    # entraDomainServices/managedHsms/sentinelWorkspaces/wafPolicies.
    #
    # AB#7089 (Story AB#7071, Feature AB#7069, Epic AB#7099) -- Security coverage-gap
    # close-out. Mirrors Invoke-Collect.ps1's attestationProviders.
    $result['attestationProviders'] = @(
        Select-ByType 'microsoft.attestation/attestationproviders' | ForEach-Object {
            [pscustomobject]@{
                id                   = [string] (Get-ScoutProp $_ 'id')
                name                 = [string] (Get-ScoutProp $_ 'name')
                resourceGroup        = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId       = [string] (Get-ScoutProp $_ 'subscriptionId')
                location             = [string] (Get-ScoutProp $_ 'location')
                status               = [string] (Get-ScoutProp $_ 'properties.status')
                trustModel           = [string] (Get-ScoutProp $_ 'properties.trustModel')
                publicNetworkAccess  = [string] (Get-ScoutProp $_ 'properties.publicNetworkAccess')
            }
        }
    )

    $result['appComplianceReports'] = @(
        Select-ByAnyType @('microsoft.appcomplianceautomation/reports', 'microsoft.appcomplianceautomation/reports/snapshots') | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                type           = [string] (Get-ScoutProp $_ 'type')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                triggerType    = [string] (Get-ScoutProp $_ 'properties.triggerTime')
            }
        }
    )

    $result['artifactSigningAccounts'] = @(
        Select-ByType 'microsoft.codesigning/codesigningaccounts' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
            }
        }
    )

    $result['cloudHsmClusters'] = @(
        Select-ByType 'microsoft.hardwaresecuritymodules/cloudhsmclusters' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['confidentialLedgers'] = @(
        Select-ByType 'microsoft.confidentialledger/ledgers' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                ledgerType        = [string] (Get-ScoutProp $_ 'properties.ledgerType')
            }
        }
    )

    $result['entraDomainServices'] = @(
        Select-ByType 'microsoft.aad/domainservices' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['managedHsms'] = @(
        Select-ByType 'microsoft.keyvault/managedhsms' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['sentinelWorkspaces'] = @(
        Select-ByType 'microsoft.securityinsights/onboardingstates' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['edgeHardwareCenterOrders'] = @(
        Select-ByAnyType @('microsoft.edgeorder/orders', 'microsoft.edgeorder/orderitems', 'microsoft.edgeorder/addresses') | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                type           = [string] (Get-ScoutProp $_ 'type')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                orderStatus    = [string] (Get-ScoutProp $_ 'properties.orderItemDetails.orderItemStatus.status')
            }
        }
    )

    $result['elasticSanVolumeGroups'] = @(
        Select-ByAnyType @('microsoft.elasticsan/elasticsans', 'microsoft.elasticsan/elasticsans/volumegroups') | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                type              = [string] (Get-ScoutProp $_ 'type')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['netAppVolumes'] = @(
        Select-ByType 'microsoft.netapp/netappaccounts/capacitypools/volumes' | ForEach-Object {
            $usageThresholdRaw = Get-ScoutProp $_ 'properties.usageThreshold'
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                usageThresholdGB  = if ($null -eq $usageThresholdRaw) { $null } else { [math]::Round([double] $usageThresholdRaw / 1GB, 2) }
            }
        }
    )

    $result['partnerStorageResources'] = @(
        Select-ByAnyType @('purestorage.block/storagepools', 'purestorage.block/reservations', 'qumulo.storage/filesystems') | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                type              = [string] (Get-ScoutProp $_ 'type')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['storageSyncServices'] = @(
        Select-ByAnyType @('microsoft.storagesync/storagesyncservices', 'microsoft.storagesync/storagesyncservices/syncgroups',
                         'microsoft.storagesync/storagesyncservices/registeredservers') | ForEach-Object {
            [pscustomobject]@{
                id                     = [string] (Get-ScoutProp $_ 'id')
                name                   = [string] (Get-ScoutProp $_ 'name')
                type                   = [string] (Get-ScoutProp $_ 'type')
                resourceGroup          = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId         = [string] (Get-ScoutProp $_ 'subscriptionId')
                location               = [string] (Get-ScoutProp $_ 'location')
                incomingTrafficPolicy  = [string] (Get-ScoutProp $_ 'properties.incomingTrafficPolicy')
            }
        }
    )

    # ---- Storage coverage-gap close-out (AB#7087, Story AB#7059, Feature AB#7069, Epic AB#7099) --
    # Mirrors Invoke-Collect.ps1's managedLustreFilesystems/storageTasks/storageDiscoveryWorkspaces/
    # storageMovers. Azure Data Share is cross-listed under Analytics and is already shaped above
    # as 'dataShareAccounts' -- no separate Storage entry.
    $result['managedLustreFilesystems'] = @(
        Select-ByType 'microsoft.storagecache/amlfilesystems' | ForEach-Object {
            $capacityRaw = Get-ScoutProp $_ 'properties.storageCapacityTiB'
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                storageCapacityTiB = if ($null -eq $capacityRaw) { $null } else { [double] $capacityRaw }
            }
        }
    )

    $result['storageTasks'] = @(
        Select-ByType 'microsoft.storageactions/storagetasks' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                enabled           = [bool] (Get-ScoutProp $_ 'properties.storageTaskProperties.enabled')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['storageDiscoveryWorkspaces'] = @(
        Select-ByType 'microsoft.storagediscovery/storagediscoveryworkspaces' | ForEach-Object {
            $rootsRaw = Get-ScoutProp $_ 'properties.workspaceRoots'
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId     = [string] (Get-ScoutProp $_ 'subscriptionId')
                location           = [string] (Get-ScoutProp $_ 'location')
                sku                = [string] (Get-ScoutProp $_ 'properties.sku')
                workspaceRootCount = @($rootsRaw).Count
            }
        }
    )

    $result['storageMovers'] = @(
        Select-ByAnyType @('microsoft.storagemover/storagemovers', 'microsoft.storagemover/storagemovers/agents',
                         'microsoft.storagemover/storagemovers/endpoints', 'microsoft.storagemover/storagemovers/projects') | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                type              = [string] (Get-ScoutProp $_ 'type')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                location          = [string] (Get-ScoutProp $_ 'location')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    # ---- Management plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) --------------
    # Mirrors Invoke-Collect.ps1's advisorScores/automationAccounts/recoveryVaultBackupPolicies/
    # lighthouseDelegations.
    $result['advisorScores'] = @(
        Select-ByType 'microsoft.advisor/advisorscore' | ForEach-Object {
            $scoreRaw = Get-ScoutProp $_ 'properties.lastRefreshedScore.score'
            [pscustomobject]@{
                id                  = [string] (Get-ScoutProp $_ 'id')
                name                = [string] (Get-ScoutProp $_ 'name')
                subscriptionId      = [string] (Get-ScoutProp $_ 'subscriptionId')
                lastRefreshedScore  = if ($null -eq $scoreRaw) { $null } else { [double] $scoreRaw }
            }
        }
    )

    $result['automationAccounts'] = @(
        Select-ByType 'microsoft.automation/automationaccounts' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'properties.sku.name')
            }
        }
    )

    $result['recoveryVaultBackupPolicies'] = @(
        Select-ByType 'microsoft.recoveryservices/vaults/backuppolicies' | ForEach-Object {
            [pscustomobject]@{
                id                    = [string] (Get-ScoutProp $_ 'id')
                name                  = [string] (Get-ScoutProp $_ 'name')
                resourceGroup         = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId        = [string] (Get-ScoutProp $_ 'subscriptionId')
                backupManagementType  = [string] (Get-ScoutProp $_ 'properties.backupManagementType')
                scheduleFrequency     = [string] (Get-ScoutProp $_ 'properties.schedulePolicy.scheduleRunFrequency')
            }
        }
    )

    $result['lighthouseDelegations'] = @(
        Select-ByType 'microsoft.managedservices/registrationdefinitions' | ForEach-Object {
            $authCount = Measure-ScoutArray (Get-ScoutPropArray $_ 'properties.authorizations')
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                subscriptionId     = [string] (Get-ScoutProp $_ 'subscriptionId')
                provisioningState  = [string] (Get-ScoutProp $_ 'properties.provisioningState')
                authorizationCount = $authCount
            }
        }
    )

    # ---- Management and governance coverage-gap plumbing (AB#7085, Story AB#7071, Feature
    # AB#7069, Epic AB#7099) -- mirrors Invoke-Collect.ps1's automanageConfigurationProfiles/
    # managedApplications/resourceMoverCollections/defenderEasmWorkspaces. managedGrafana is NOT
    # mirrored here -- AB#7084 already shapes it (see the `microsoft.dashboard/grafana`
    # Select-ByType block elsewhere in this file) under `devops.managedGrafana`.
    $result['automanageConfigurationProfiles'] = @(
        Select-ByType 'microsoft.automanage/configurationprofiles' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
            }
        }
    )

    $result['managedApplications'] = @(
        Select-ByType 'microsoft.solutions/applications' | ForEach-Object {
            [pscustomobject]@{
                id                      = [string] (Get-ScoutProp $_ 'id')
                name                    = [string] (Get-ScoutProp $_ 'name')
                resourceGroup           = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId          = [string] (Get-ScoutProp $_ 'subscriptionId')
                location                = [string] (Get-ScoutProp $_ 'location')
                kind                    = [string] (Get-ScoutProp $_ 'kind')
                managedBy               = [string] (Get-ScoutProp $_ 'managedBy')
                managedResourceGroupId  = [string] (Get-ScoutProp $_ 'properties.managedResourceGroupId')
                applicationDefinitionId = [string] (Get-ScoutProp $_ 'properties.applicationDefinitionId')
                provisioningState       = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    $result['resourceMoverCollections'] = @(
        Select-ByType 'microsoft.migrate/movecollections' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sourceRegion   = [string] (Get-ScoutProp $_ 'properties.sourceRegion')
                targetRegion   = [string] (Get-ScoutProp $_ 'properties.targetRegion')
                moveType       = [string] (Get-ScoutProp $_ 'properties.moveType')
            }
        }
    )

    $result['defenderEasmWorkspaces'] = @(
        Select-ByType 'microsoft.easm/workspaces' | ForEach-Object {
            [pscustomobject]@{
                id                 = [string] (Get-ScoutProp $_ 'id')
                name               = [string] (Get-ScoutProp $_ 'name')
                resourceGroup      = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId     = [string] (Get-ScoutProp $_ 'subscriptionId')
                location           = [string] (Get-ScoutProp $_ 'location')
                dataPlaneEndpoint  = [string] (Get-ScoutProp $_ 'properties.dataPlaneEndpoint')
                provisioningState  = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )

    # ---- Identity plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) -----------------
    # Mirrors Invoke-Collect.ps1's managedIdentities. Identity had no existing shaper section --
    # every other Identity collector declares an `entra/*` type (Microsoft Graph API), deliberately
    # out of scope, see Invoke-Collect.ps1's file header.
    $result['managedIdentities'] = @(
        Select-ByType 'microsoft.managedidentity/userassignedidentities' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
            }
        }
    )

    # ---- DevOps plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) -------------------
    # Mirrors Invoke-Collect.ps1's apiConnections/appConfigurationStores/deploymentEnvironmentTypes/
    # devBoxPools/devCenterNetworkConnections/devTestLabs/labServicesLabs.
    $result['apiConnections'] = @(
        Select-ByType 'microsoft.web/connections' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
            }
        }
    )

    $result['appConfigurationStores'] = @(
        Select-ByType 'microsoft.appconfiguration/configurationstores' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                sku            = [string] (Get-ScoutProp $_ 'sku.name')
            }
        }
    )

    $result['deploymentEnvironmentTypes'] = @(
        Select-ByAnyType @('microsoft.devcenter/devcenters/environmenttypes', 'microsoft.devcenter/projects/environmenttypes',
                         'microsoft.devcenter/devcenters/catalogs', 'microsoft.devcenter/projects/catalogs') | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                type           = [string] (Get-ScoutProp $_ 'type')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
            }
        }
    )

    $result['devBoxPools'] = @(
        Select-ByType 'microsoft.devcenter/projects/pools' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                licenseType    = [string] (Get-ScoutProp $_ 'properties.licenseType')
            }
        }
    )

    $result['devCenterNetworkConnections'] = @(
        Select-ByType 'microsoft.devcenter/networkconnections' | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
                domainJoinType = [string] (Get-ScoutProp $_ 'properties.domainJoinType')
            }
        }
    )

    $result['devTestLabs'] = @(
        Select-ByAnyType @('microsoft.devtestlab/labs', 'microsoft.devtestlab/schedules') | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                type           = [string] (Get-ScoutProp $_ 'type')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
            }
        }
    )

    $result['labServicesLabs'] = @(
        Select-ByAnyType @('microsoft.labservices/labs', 'microsoft.labservices/labplans') | ForEach-Object {
            [pscustomobject]@{
                id             = [string] (Get-ScoutProp $_ 'id')
                name           = [string] (Get-ScoutProp $_ 'name')
                type           = [string] (Get-ScoutProp $_ 'type')
                resourceGroup  = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId = [string] (Get-ScoutProp $_ 'subscriptionId')
                location       = [string] (Get-ScoutProp $_ 'location')
            }
        }
    )

    # AB#7084 -- Azure Managed Grafana coverage-gap collector. Mirrors Invoke-Collect.ps1's
    # managedGrafana query.
    $result['managedGrafana'] = @(
        Select-ByType 'microsoft.dashboard/grafana' | ForEach-Object {
            [pscustomobject]@{
                id                = [string] (Get-ScoutProp $_ 'id')
                name              = [string] (Get-ScoutProp $_ 'name')
                resourceGroup     = [string] (Get-ScoutProp $_ 'resourceGroup')
                subscriptionId    = [string] (Get-ScoutProp $_ 'subscriptionId')
                sku               = [string] (Get-ScoutProp $_ 'sku.name')
                provisioningState = [string] (Get-ScoutProp $_ 'properties.provisioningState')
            }
        }
    )
    return $result
}
