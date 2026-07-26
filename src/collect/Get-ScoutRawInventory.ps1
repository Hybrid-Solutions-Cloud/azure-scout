#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    The single Resource Graph pass src/collect owns -- the raw superset both the typed
    assessment queries and the legacy inventory extraction can be shaped from (AB#5639).

.DESCRIPTION
    `Modules/Private/Extraction/Start-AZTIGraphExtraction.ps1` (the v1-forked inventory
    engine's own query builder) and `src/collect/Invoke-Collect.ps1` (the assessment
    platform's typed query pack) each independently query Azure Resource Graph today.
    `ConvertFrom-ScoutInventory.ps1` already proved (AB#5543) that every assessment scalar
    can be derived, field for field, from the raw rows a broad `resources`/`networkresources`/
    `resourcecontainers` pass returns -- but only when the INVENTORY side happened to run
    first and hand its rows to the assessment side via `Invoke-Collect -FromInventory`.

    This function inverts that dependency: it is `src/collect`'s own implementation of the
    raw pass, independent of the legacy inventory engine, so `src/collect` can be the single
    place that knows how to ask Azure for this data. It mirrors
    `Start-AZTIGraphExtraction`'s table set and column projection field for field (same eight
    ARG tables, same excluded types, same advisor-impact / security-assessment filters) so
    its output is a drop-in `-FromInventory` argument to `Invoke-Collect`, and so a future
    pass (AB#5648) can point the legacy inventory engine at this function instead of its own
    query-building code, once the pieces this task ships are proven live.

    AB#5648 update: both deferrals below are now done. `Start-AZTIGraphExtraction` is a
    parameter-translation shim over THIS function -- it builds no queries and issues no
    Resource Graph call of its own -- and `Invoke-AZTIInventoryLoop.ps1` (the legacy
    paging/batching engine) is deleted. `Retirements` moved here too (see
    `-IncludeRetirements`), so every ARG round-trip the inventory path makes is issued from
    this one function.

.PARAMETER ManagementGroupId
    Scopes every query to a management group via `Search-AzGraph -ManagementGroup`, exactly
    as `Invoke-Collect` does. Omitted entirely when not supplied (tenant-wide, subject to the
    caller's own RBAC).

.PARAMETER SubscriptionIds
    An explicit subscription-id allow-list. When supplied, every query is scoped with
    `-Subscription` (batched into groups of 1000 -- the documented Resource Graph maximum
    subscriptions per call) instead of running tenant/management-group-wide. When omitted,
    the function collects `resourcecontainers` first (exactly like `Invoke-Collect`) and uses
    the resulting subscription-id list as the AB#397-style per-subscription retry fallback
    for every other query.

.PARAMETER IncludeSupportResources
    Also collect `SupportResources` (support tickets) -- skipped by default because
    Start-AZTIGraphExtraction itself skips this table entirely on `AzureUSGovernment`, and it
    is a light, rarely-consumed dataset (one collector: `Management/SupportTickets.ps1`).

.PARAMETER IncludeBackupResources
    Also collect `recoveryservicesresources` (backup protected items + backup policies).

.PARAMETER IncludeDesktopVirtualization
    Also collect `desktopvirtualizationresources` (AVD host pools, session hosts, workspaces,
    application groups, scaling plans).

.PARAMETER IncludeAdvisories
    Also collect `advisorresources` filtered to Medium/High impact, matching the legacy
    `-SkipAdvisory:$false` default.

.PARAMETER IncludeSecurityCenter
    Also collect `securityresources` filtered to Unhealthy `microsoft.security/assessments`,
    matching the legacy `-SecurityCenter` switch. Note this is a DIFFERENT filter than
    `Invoke-Collect`'s own live `sqlDefenderPricing` query (which reads the same
    `securityresources` table but for `microsoft.security/pricings` rows) -- the two do not
    overlap and this switch does not make `sqlDefenderPricing` derivable from the result.

.PARAMETER IncludeTags
    Project the `tags` column on every row (omitted by default, matching the legacy default).

.PARAMETER IncludeRetirements
    Also run the service-retirement KQL (`src/report/renderers/inventory/style/Retirement.kql`)
    and return its rows as `Retirements`. AB#5648: this used to be issued directly by
    `Start-AZTIGraphExtraction`; it lives here now so every inventory ARG round-trip goes
    through one function. It is NOT derivable from the raw row set -- it queries
    `resources`/`servicehealthresources` with its own joins -- so it is one of the two
    documented exceptions to "one pass" (the other is `Invoke-Collect`'s `sqlDefenderPricing`).

.PARAMETER RetirementQueryPath
    Overrides where the retirement KQL is read from. Defaults to
    `src/report/renderers/inventory/style/Retirement.kql` resolved from this file's location.

.PARAMETER ResourceGroups
    Restrict every resource-bearing table to these resource-group names, rendering the same
    `| where resourceGroup in~ (...)` clause `Start-AZTIGraphExtraction` built. Mutually
    exclusive with -TagKey/-TagValue and -ManagementGroupName, matching the legacy if/elseif
    precedence exactly (resource group wins, then tags, then management group).

.PARAMETER TagKey
.PARAMETER TagValue
    Restrict to resources carrying a tag key and/or value, rendering the same
    `mvexpand tags | extend tagKey ... | where tagKey =~ ...` clause the legacy extractor built.

.PARAMETER ManagementGroupName
    Renders the legacy `join kind=inner (resourcecontainers | ... managementGroupAncestorsChain
    ...)` filter (and its narrower `mv-expand`-only variant for the `resourcecontainers` table)
    so a management-group-scoped inventory run produces byte-identical query text to the one
    the legacy extractor produced. This is DIFFERENT from `-ManagementGroupId`, which scopes the
    `Search-AzGraph` CALL rather than filtering rows -- the inventory path has always used the
    row filter, the assessment path has always used the call scope, and both remain available.

.PARAMETER AzureEnvironment
    Passed through only to decide whether `SupportResources` is queryable at all (that table
    is unavailable in Azure US Government, exactly as in `Start-AZTIGraphExtraction`).

.OUTPUTS
    [pscustomobject] with `Resources`, `ResourceContainers`, `Advisories`, `Security` and
    `Retirements` -- the same shape `Start-AZTIGraphExtraction` returns, and the same shape
    `Invoke-Collect -FromInventory` already accepts.

.NOTES
    Tracks ADO AB#5639 (Task AB#5642, Epic AB#5638).

    ---- Row contract (Task AB#5643) ----

    Every row from the `resources`, `networkresources`, `SupportResources`,
    `recoveryservicesresources`, `desktopvirtualizationresources` and `advisorresources`
    tables carries exactly this projection, whether or not the underlying resource type
    populates every field:

        id, name, type, tenantId, kind, location, resourceGroup, subscriptionId, managedBy,
        sku, plan, properties, identity, zones, extendedLocation[, tags when -IncludeTags]

    GUARANTEES:
      - `id`, `name`, `type`, `resourceGroup`, `subscriptionId` are always non-null strings
        for a real resource row (ARG never returns a row without them).
      - `properties` is the FULL, untyped ARM properties bag as Resource Graph indexed it --
        a `PSCustomObject` (or `$null` for a resource type ARG indexes with no properties).
        It is NOT the scalar-shaped object `ConvertFrom-ScoutInventory`/`Invoke-Collect`
        produce; consumers read sub-properties directly (`$row.properties.someField`) and
        MUST treat every segment as possibly absent (see `Get-ScoutProp` in
        `ConvertFrom-ScoutInventory.ps1` for the StrictMode-safe pattern this codebase uses).
      - `sku`, `plan`, `identity`, `zones`, `extendedLocation`, `kind`, `managedBy` are
        present as columns but are `$null`/empty for any resource type that does not define
        them -- never absent as a PROPERTY (StrictMode-safe to read directly, unlike
        `properties`' nested fields).
      - `tags` is present ONLY when `-IncludeTags` was supplied; a caller that always needs
        to check for it first (`$row.PSObject.Properties['tags']`) rather than assume its
        presence.
      - `resources` and `networkresources` OVERLAP for several network resource types (the
        same VNet/NSG/etc. row can appear in both tables) -- callers MUST de-duplicate by
        `id` before counting or summarizing, exactly as `ConvertFrom-ScoutInventory` already
        does. This function does NOT de-duplicate `.Resources` itself (nor did
        `Start-AZTIGraphExtraction` -- callers have always been responsible for this); it is
        called out here because it is the single most common defect class a naive consumer
        of this row set hits.

    `ResourceContainers` rows carry a NARROWER, DIFFERENT projection -- `type`, `name`,
    `subscriptionId`, `properties`, `tags` -- and do NOT carry `location`/`resourceGroup`
    (a subscription or resource-group container has neither). Two `type` values appear:
    `microsoft.resources/subscriptions` (subscription rows, `properties.state` is the only
    read field downstream) and `microsoft.resources/subscriptions/resourcegroups` (resource
    group rows).

    `Advisories` rows are `advisorresources` rows filtered to `properties.impact` in
    (Medium, High) -- the full advisor recommendation shape, not the narrower
    `microsoft.advisor/advisorscore` percentage (that is REST-API-only data; see
    `Get-ScoutApiResources.ps1`).

    `Security` rows are `securityresources` rows filtered to
    `type =~ 'microsoft.security/assessments'` and `properties.status.code == 'Unhealthy'`
    ONLY -- this table also holds `microsoft.security/pricings` rows (what
    `Invoke-Collect`'s `sqlDefenderPricing` query reads), which this filter deliberately
    excludes, so `.Security` can never be used to derive `sqlDefenderPricing`.

    ---- Paging / throttling / retry (Task AB#5642) ----

    Uses Resource Graph's own `SkipToken` (not a manually incremented `-Skip` count) to page
    within a single query/subscription-batch -- `SkipToken` is the mechanism Resource Graph
    itself hands back and is immune to the `-Skip 0` "value must be greater than 0" trap that
    `Invoke-Collect.ps1`'s own paging loop had to work around (AB#5642's originally-reported
    defect, fixed there by omitting `-Skip` on the first page; `SkipToken` sidesteps the
    class of bug entirely by never taking a manual offset).

    Subscriptions are batched into groups of 1000 (the documented Resource Graph maximum
    subscriptions accepted per call) rather than the legacy loop's more conservative 200 --
    both are correct; 1000 halves the call count for large tenants without violating the
    documented ceiling.

    A 429/throttled response is detected by message text (`429`, `TooManyRequests`,
    `Throttled`) and retried up to three times with a short, fixed backoff BEFORE falling
    through to the existing per-batch-skip resilience -- Resource Graph's throttling window
    resets in single-digit seconds (see the ARG throttling-headers guidance), so a short
    fixed wait clears the vast majority of throttling without the run stalling on an
    unbounded retry loop. Any other error (a genuine auth failure, a malformed query) is not
    retried at this layer and falls straight through to the per-batch warn-and-skip path,
    matching `Start-AZTIGraphExtraction`'s existing "isolate the batch, keep going" design.
#>
function Get-ScoutRawInventory {
    [CmdletBinding()]
    param(
        [string]   $ManagementGroupId,
        [string[]] $SubscriptionIds,
        [switch]   $IncludeSupportResources,
        [switch]   $IncludeBackupResources,
        [switch]   $IncludeDesktopVirtualization,
        [switch]   $IncludeAdvisories,
        [switch]   $IncludeSecurityCenter,
        [switch]   $IncludeTags,
        [switch]   $IncludeRetirements,
        [string]   $RetirementQueryPath,
        [string[]] $ResourceGroups,
        [string]   $TagKey,
        [string]   $TagValue,
        [string]   $ManagementGroupName,
        [string]   $AzureEnvironment = 'AzureCloud'
    )

    Import-Module Az.ResourceGraph -ErrorAction Stop

    $tagProjection = if ($IncludeTags) { ',tags' } else { '' }
    $columns = "id,name,type,tenantId,kind,location,resourceGroup,subscriptionId,managedBy,sku,plan,properties,identity,zones,extendedLocation$tagProjection"

    # Same exclusion list as Start-AZTIGraphExtraction's $ExcludedTypes -- these three types
    # are UI/authoring artifacts (Logic Apps designer workflow defs, portal dashboards,
    # template-spec versions), not inventory-worthy resources.
    $excludedTypesClause = "| where type !in ('microsoft.logic/workflows','microsoft.portal/dashboards','microsoft.resources/templatespecs/versions','microsoft.resources/templatespecs')"

    # ---- legacy row-filter clauses (AB#5648) ----
    # Rendered here, byte for byte, from Start-AZTIGraphExtraction's $RGQueryExtension /
    # $TagQueryExtension / $MGQueryExtension / $MGContainerExtension. The precedence is the
    # legacy if/elseif chain, NOT independent flags: resource group wins outright, then tags,
    # then management group. Reproducing the chain rather than allowing arbitrary combinations
    # keeps the query text identical to what shipped -- a combination the legacy never emitted
    # would be untested KQL.
    # `@($ResourceGroups).Count` alone is NOT a safe emptiness test: an unbound [string[]]
    # parameter is $null and @($null).Count is 1, not 0 (the defect class that emptied the
    # v2.6.0 Excel loop and broke v2.7.0 subscription batching). Filter the nulls out first.
    $resolvedResourceGroups = @($ResourceGroups | Where-Object { $_ })
    $rgClause = ''
    $tagClause = ''
    $mgJoinClause = ''
    $mgContainerClause = ''
    if ($resolvedResourceGroups.Count -gt 0) {
        $rgClause = "| where resourceGroup in~ ('$([String]::Join("','", $resolvedResourceGroups))')"
    }
    elseif (-not [string]::IsNullOrEmpty($TagKey) -or -not [string]::IsNullOrEmpty($TagValue)) {
        $tagClause = '| where isnotempty(tags) | mvexpand tags | extend tagKey = tostring(bag_keys(tags)[0]) | extend tagValue = tostring(tags[tagKey]) '
        if (-not [string]::IsNullOrEmpty($TagKey))   { $tagClause += "| where tagKey =~ '$TagKey'" }
        if (-not [string]::IsNullOrEmpty($TagValue)) { $tagClause += " and tagValue =~ '$TagValue'" }
    }
    elseif (-not [string]::IsNullOrEmpty($ManagementGroupName)) {
        $mgJoinClause = "| join kind=inner (resourcecontainers | where type == 'microsoft.resources/subscriptions' | mv-expand managementGroupParent = properties.managementGroupAncestorsChain | where managementGroupParent.name =~ '$ManagementGroupName' | project subscriptionId, managanagementGroup = managementGroupParent.name) on subscriptionId"
        $mgContainerClause = "| mv-expand managementGroupParent = properties.managementGroupAncestorsChain | where managementGroupParent.name =~ '$ManagementGroupName'"
    }

    function Test-ScoutArgThrottled {
        param([string] $Message)
        return [bool]($Message -match '(?i)\b429\b' -or $Message -match '(?i)TooManyRequests' -or $Message -match '(?i)Throttled')
    }

    function Get-ScoutRawArgPage {
        <#
        .SYNOPSIS
            Fetch exactly one page, with a bounded, backoff retry for throttling. Returns
            $null (not a thrown error) when the page could not be fetched at all, so the
            caller can warn-and-skip without losing pages already collected (AB#5642).
        #>
        param(
            [Parameter(Mandatory)] [string]   $Query,
            [string[]] $Batch,
            [string]   $SkipToken,
            [string]   $LoopName
        )
        $throttleRetries = 0
        # A while($true)+continue loop (NOT a do/while on the retry count) is deliberate: a
        # do/while's `continue` re-evaluates the OUTER loop's own condition, not "try the
        # request again" -- with $skipToken still unset on a first-page throttle, that would
        # exit immediately instead of retrying. This inner loop's only exit paths are an
        # explicit `return`.
        while ($true) {
            $params = @{ Query = $Query; First = 1000; ErrorAction = 'Stop' }
            if ($SkipToken) { $params.SkipToken = $SkipToken }
            if ($Batch)     { $params.Subscription = $Batch }
            if ($ManagementGroupId -and -not $Batch) { $params.ManagementGroup = $ManagementGroupId }

            try {
                return Search-AzGraph @params
            }
            catch {
                $errText = $_.Exception.Message
                if ((Test-ScoutArgThrottled $errText) -and $throttleRetries -lt 3) {
                    $throttleRetries++
                    # Resource Graph's quota window resets in single-digit seconds (per the
                    # ARG throttling-headers guidance) -- a short fixed backoff, not an
                    # unbounded/exponential one, is enough headroom without stalling the run.
                    Write-Verbose "Get-ScoutRawInventory: '$LoopName' was throttled -- retrying in 5s (attempt $throttleRetries/3): $errText"
                    Start-Sleep -Seconds 5
                    continue
                }
                Write-Warning "Get-ScoutRawInventory: '$LoopName' failed$(if ($Batch) { " for a batch of $($Batch.Count) subscription(s)" }) and was skipped: $errText"
                return $null
            }
        }
    }

    function Invoke-ScoutRawArgQuery {
        <#
        .SYNOPSIS
            Page one query, for one subscription batch (or tenant/MG-wide when $Batch is
            $null), using SkipToken.
        #>
        param(
            [Parameter(Mandatory)] [string]   $Query,
            [string[]] $Batch,
            [string]   $LoopName
        )
        $rows = [System.Collections.Generic.List[object]]::new()
        $skipToken = $null
        do {
            $page = Get-ScoutRawArgPage -Query $Query -Batch $Batch -SkipToken $skipToken -LoopName $LoopName
            if ($null -eq $page) { break }
            foreach ($row in @($page)) { $rows.Add($row) }
            $skipToken = if ($page -and $page.PSObject.Properties['SkipToken']) { $page.SkipToken } else { $null }
        } while ($skipToken)
        # Comma-prefix: an empty [List[object]] must still come back as an array, not unroll
        # to $null, so every caller's `.Count` stays StrictMode-safe (same idiom as
        # Invoke-AZTIInventoryLoop's `return ,$LocalResults`).
        return , @($rows)
    }

    function Invoke-ScoutRawTable {
        <#
        .SYNOPSIS
            Run one table query across every subscription batch (or tenant/MG-wide when no
            explicit subscription list is available yet).
        #>
        param([string] $Query, [string] $LoopName, [string[]] $Subscriptions)
        if (-not $Subscriptions -or @($Subscriptions).Count -eq 0) {
            return Invoke-ScoutRawArgQuery -Query $Query -LoopName $LoopName
        }
        $rows = [System.Collections.Generic.List[object]]::new()
        # 1000 is the documented Resource Graph maximum subscriptions per call.
        for ($i = 0; $i -lt $Subscriptions.Count; $i += 1000) {
            $upper = [Math]::Min($i + 999, $Subscriptions.Count - 1)
            $batch = @($Subscriptions[$i..$upper])
            foreach ($row in (Invoke-ScoutRawArgQuery -Query $Query -Batch $batch -LoopName $LoopName)) { $rows.Add($row) }
        }
        return , @($rows)
    }

    # ---- resourcecontainers first: gives every other table a subscription list to batch by,
    # exactly like Invoke-Collect's own AB#397 ordering guarantee. ----
    # `@($SubscriptionIds)` alone is NOT safe here: an unbound [string[]] parameter is $null,
    # and `@($null).Count` is 1, not 0 -- which made the `.Count -eq 0` test below false on the
    # DEFAULT (no -SubscriptionIds) path, so the subscription list was never derived from
    # resourcecontainers and every later table silently ran as a single tenant-wide call with
    # no per-batch isolation at all. Filtering out the null element restores the documented
    # behavior for both paths.
    $resolvedSubscriptionIds = @($SubscriptionIds | Where-Object { $_ })
    # No $excludedTypesClause here: the legacy extractor applied its type exclusion to the
    # `resources` table ONLY, and none of the four excluded types is a container type anyway.
    # Applying it to resourcecontainers was a (harmless) divergence introduced in v2.7.0; it is
    # removed so the query text matches the shipped one exactly (AB#5648).
    $containerQuery = "resourcecontainers $rgClause $tagClause $mgContainerClause | project $columns | order by id asc"
    $resourceContainers = Invoke-ScoutRawTable -Query $containerQuery -LoopName 'Subscriptions and Resource Groups' -Subscriptions $resolvedSubscriptionIds
    if ($resolvedSubscriptionIds.Count -eq 0) {
        $resolvedSubscriptionIds = @(
            $resourceContainers |
                Where-Object { [string] $_.type -ieq 'microsoft.resources/subscriptions' } |
                ForEach-Object { $_.subscriptionId } |
                Where-Object { $_ }
        )
    }

    $resources = [System.Collections.Generic.List[object]]::new()
    foreach ($row in (Invoke-ScoutRawTable -Query "resources $rgClause $tagClause $mgJoinClause $excludedTypesClause | project $columns | order by id asc" -LoopName 'Resources' -Subscriptions $resolvedSubscriptionIds)) { $resources.Add($row) }
    foreach ($row in (Invoke-ScoutRawTable -Query "networkresources $rgClause $tagClause $mgJoinClause | project $columns | order by id asc" -LoopName 'Network Resources' -Subscriptions $resolvedSubscriptionIds)) { $resources.Add($row) }

    if ($IncludeSupportResources -and $AzureEnvironment -ne 'AzureUSGovernment') {
        foreach ($row in (Invoke-ScoutRawTable -Query "SupportResources $rgClause $tagClause $mgJoinClause | project $columns | order by id asc" -LoopName 'SupportTickets' -Subscriptions $resolvedSubscriptionIds)) { $resources.Add($row) }
    }

    if ($IncludeBackupResources) {
        # The management-group join goes AFTER the type filter here, exactly as the legacy
        # extractor rendered it -- the tag clause goes before. Not symmetric, but faithful.
        $backupQuery = "recoveryservicesresources $rgClause $tagClause | where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' or type =~ 'microsoft.recoveryservices/vaults/backuppolicies' $mgJoinClause | project $columns | order by id asc"
        foreach ($row in (Invoke-ScoutRawTable -Query $backupQuery -LoopName 'Backup Items' -Subscriptions $resolvedSubscriptionIds)) { $resources.Add($row) }
    }

    if ($IncludeDesktopVirtualization) {
        # No tag clause: the legacy extractor never applied one to this table.
        foreach ($row in (Invoke-ScoutRawTable -Query "desktopvirtualizationresources $rgClause $mgJoinClause | project $columns | order by id asc" -LoopName 'Virtual Desktop' -Subscriptions $resolvedSubscriptionIds)) { $resources.Add($row) }
    }

    $advisories = @()
    if ($IncludeAdvisories) {
        $advisorQuery = "advisorresources $rgClause $mgJoinClause | where properties.impact in~ ('Medium','High') | order by id asc"
        $advisories = Invoke-ScoutRawTable -Query $advisorQuery -LoopName 'Advisories' -Subscriptions $resolvedSubscriptionIds
    }

    $security = @()
    if ($IncludeSecurityCenter) {
        $securityQuery = "securityresources $rgClause | where type =~ 'microsoft.security/assessments' and properties['status']['code'] == 'Unhealthy' $mgJoinClause | order by id asc"
        $security = Invoke-ScoutRawTable -Query $securityQuery -LoopName 'Security Center' -Subscriptions $resolvedSubscriptionIds
    }

    # ---- retirements (AB#5648) ----
    # A file-backed KQL query with its own joins; not derivable from the raw row set, so it is
    # a documented, deliberate extra round-trip rather than a gap. Reading the file is guarded:
    # a missing/unreadable .kql must degrade this one dataset, not sink the whole inventory run.
    $retirements = @()
    if ($IncludeRetirements) {
        $resolvedRetirementPath = if ($RetirementQueryPath) { $RetirementQueryPath }
        else { Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src' 'report' 'renderers' 'inventory' 'style' 'Retirement.kql' }
        try {
            $retirementQuery = (Get-Content -Path $resolvedRetirementPath -ErrorAction Stop | Out-String)
            $retirements = Invoke-ScoutRawTable -Query $retirementQuery -LoopName 'Retirements' -Subscriptions $resolvedSubscriptionIds
        }
        catch {
            Write-Warning "Get-ScoutRawInventory: the retirement query at '$resolvedRetirementPath' could not be read -- Retirements will be empty and the rest of the inventory is unaffected: $($_.Exception.Message)"
            $retirements = @()
        }
    }

    if (@($resources).Count -eq 0 -and @($resourceContainers).Count -eq 0) {
        Write-Warning ('Get-ScoutRawInventory: extraction returned zero resources. Verify the identity has Reader ' +
            'at the target scope (root management group for full coverage) and that -ManagementGroupId/-SubscriptionIds is correct.')
    }

    return [pscustomobject]@{
        Resources          = @($resources)
        ResourceContainers = @($resourceContainers)
        Advisories         = @($advisories)
        Security           = @($security)
        Retirements        = @($retirements)
    }
}
