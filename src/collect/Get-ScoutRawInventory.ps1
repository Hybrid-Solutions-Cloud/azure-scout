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

.PARAMETER IncludeUpdateManagerResources
    Also collect `patchassessmentresources` (pending/available updates, 7-day retention) and
    `patchinstallationresources` (update installation history, 30-day retention) -- the Resource
    Graph tables Azure Update Manager writes its own results into, for both Azure VMs and
    Arc-enabled servers. Read-only: this reads what Update Manager already recorded and never
    asks a machine to run a scan.

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

.PARAMETER IncludeArmChildResources
    Also collect the ARM child datasets required by the declarative inventory collectors. The
    synthetic rows are appended to `Resources`. Off by default because this is ARM REST work,
    not part of the Resource Graph pass.

.PARAMETER ArmChildDataset
    Which ARM child dataset(s) to collect when -IncludeArmChildResources is set -- passed straight
    through to Get-ScoutArmChildResource's own -Dataset parameter. Defaults to 'All' (every
    dataset that function supports), matching the pre-AB#6821 behaviour for callers that already
    set -IncludeArmChildResources without naming a subset. A caller that only needs, say, the two
    Key Vault child datasets (the assessment collect path, AB#6821) names them explicitly so the
    ARM REST sweep is not paying for ML/Search/Storage/Backup/diagnostics children nothing reads.

.PARAMETER IncludeSubscriptionSecurityPolicy
    Also collect one synthetic Defender/diagnostics/policy-compliance envelope per discovered
    subscription and append it to `Resources`. Off by default.

.PARAMETER SkipApiResourceSweep
    Suppress the ARM REST API sweep (`Get-ScoutApiResources`). Mirrors the operator's
    `-SkipAPIs` flag, whose meaning is "Resource Graph only".

    It does NOT suppress tenant-wide collection. The custom-role, management-group,
    policy-definition and policy-set envelopes are collected on every run and there is no
    parameter that turns them off -- they are what a governance assessment reads, and an
    assessment scoring against an empty array reports a false pass. Only the policy halves,
    which genuinely come from this sweep, come back empty (AB#6755).

    The sweep's per-subscription results are returned on the `ApiResources` field so a caller
    that needs them for its own reasons -- the v1 inventory orchestration does -- reuses this
    pass rather than issuing a second identical one.

.PARAMETER SkipPolicy
    Suppress the three policy REST calls inside the ARM API sweep. Mirrors
    `Get-ScoutApiResources -SkipPolicy`; with it set the policy-definition and policy-set
    envelopes come back empty by construction.

.PARAMETER TenantWideDefinitionsOnly
    Narrow the ARM API sweep to the two calls the tenant-wide envelopes actually consume.
    Set by callers that never read `ApiResources` themselves -- the assessment collect pass.
    Cuts the sweep from seven paced calls per subscription to two.

.PARAMETER IncludeOperationalCollectorEnrichment
    Also collect the parent-scoped ARM/Az-cmdlet envelopes consumed by the remaining live-access
    inventory collectors (VM, Arc, storage, and subscription enrichment), appending them to
    `Resources`. Off by default so the ordinary Resource Graph output is unchanged.

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
    `Invoke-Collect -FromInventory` already accepts. When one of the optional non-ARG switches
    is supplied, its synthetic collector envelopes are appended to `Resources`; no top-level
    property is added, so callers that have not opted in observe the identical contract.

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
        [switch]   $IncludeUpdateManagerResources,
        [switch]   $IncludeAdvisories,
        [switch]   $IncludeSecurityCenter,
        [switch]   $IncludeTags,
        [switch]   $IncludeRetirements,
        [switch]   $IncludeArmChildResources,
        [string[]] $ArmChildDataset = @('All'),
        [switch]   $IncludeSubscriptionSecurityPolicy,
        [switch]   $SkipApiResourceSweep,
        [switch]   $SkipPolicy,
        [switch]   $TenantWideDefinitionsOnly,
        [bool]     $CollectResourceTable = $true,
        [bool]     $CollectNetworkTable = $true,
        [bool]     $CollectTenantWideResources = $true,
        [bool]     $CollectGovernance = $true,
        [string[]] $ResourceTypes,

        [switch]   $IncludeOperationalCollectorEnrichment,
        [string]   $RetirementQueryPath,
        [string[]] $ResourceGroups,
        [string]   $TagKey,
        [string]   $TagValue,
        [string]   $ManagementGroupName,
        [string]   $AzureEnvironment = 'AzureCloud'
    )

    # The module manifest normally supplies Az.ResourceGraph. Direct dot-source callers still get
    # a clear import path, while tests and hosts that already provide Search-AzGraph avoid an
    # unnecessary module import (which can refresh an ambient Az context and contact ARM).
    if (-not (Get-Command Search-AzGraph -ErrorAction SilentlyContinue)) {
        Import-Module Az.ResourceGraph -ErrorAction Stop
    }

    $collectionHealth = [System.Collections.Generic.List[object]]::new()
    $collectionHealthKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $affectedCollectorCache = @{}
    # Synthetic ARM-child rows whose existence depends on a parent from the core `resources`
    # table. A failed parent query means these collectors were not genuinely observed; excluding
    # every AZSC/* type would incorrectly report them as clean empty datasets. AVDApplications is
    # deliberately absent because its parent comes from desktopvirtualizationresources, and
    # ArcSites is absent because its parent comes from the independent ARM REST sweep.
    $resourceDerivedArmChildParents = @{
        'azsc/armchild/mlcomputes' = @('microsoft.machinelearningservices/workspaces')
        'azsc/armchild/mldatasets' = @('microsoft.machinelearningservices/workspaces')
        'azsc/armchild/mldatastores' = @('microsoft.machinelearningservices/workspaces')
        'azsc/armchild/mlendpoints' = @('microsoft.machinelearningservices/workspaces')
        'azsc/armchild/mlmodels' = @('microsoft.machinelearningservices/workspaces')
        'azsc/armchild/mlpipelines' = @('microsoft.machinelearningservices/workspaces')
        'azsc/armchild/openaideployments' = @('microsoft.cognitiveservices/accounts')
        'azsc/armchild/searchindexes' = @('microsoft.search/searchservices')
        'azsc/armchild/appinsightsproactivedetection' = @('microsoft.insights/components')
        'azsc/armchild/laworkspacelinkedservices' = @('microsoft.operationalinsights/workspaces')
        'azsc/armchild/laworkspacesavedsearches' = @('microsoft.operationalinsights/workspaces')
        'azsc/armchild/keyvaultsecrets' = @('microsoft.keyvault/vaults')
        'azsc/armchild/keyvaultkeys' = @('microsoft.keyvault/vaults')
        'azsc/armchild/storageblobcontainers' = @('microsoft.storage/storageaccounts')
        'azsc/armchild/storagefileshares' = @('microsoft.storage/storageaccounts')
        'azsc/armchild/storagelifecyclepolicies' = @('microsoft.storage/storageaccounts')
        'azsc/armchild/storagequeues' = @('microsoft.storage/storageaccounts')
        'azsc/armchild/storagetables' = @('microsoft.storage/storageaccounts')
        'azsc/armchild/backupinstances' = @('microsoft.dataprotection/backupvaults')
        'azsc/armchild/resourcediagnosticsettings' = @(
            'microsoft.keyvault/vaults', 'microsoft.storage/storageaccounts',
            'microsoft.sql/servers', 'microsoft.sql/servers/databases',
            'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers',
            'microsoft.documentdb/databaseaccounts', 'microsoft.containerservice/managedclusters',
            'microsoft.web/sites', 'microsoft.cdn/profiles', 'microsoft.apimanagement/service',
            'microsoft.eventhub/namespaces', 'microsoft.servicebus/namespaces',
            'microsoft.operationalinsights/workspaces', 'microsoft.recoveryservices/vaults',
            'microsoft.automation/automationaccounts'
        )
        'azsc/armchild/reservationutilization' = @('microsoft.capacity/reservationorders/reservations')
        'azsc/armchild/azurelocalvirtualmachineinstances' = @('microsoft.hybridcompute/machines')
    }
    $networkDiagnosticParentTypes = @(
        'microsoft.network/networksecuritygroups', 'microsoft.network/applicationgateways',
        'microsoft.network/azurefirewalls', 'microsoft.network/frontdoors'
    )

    function Get-ScoutRawAffectedCollector {
        param(
            [string] $Source,
            [string[]] $RequestedResourceTypes = @()
        )

        if ([string]::IsNullOrWhiteSpace($Source)) { return @() }
        $cacheKey = '{0}|{1}' -f $Source, (@($RequestedResourceTypes | Sort-Object -Unique) -join ',')
        if ($affectedCollectorCache.ContainsKey($cacheKey)) { return @($affectedCollectorCache[$cacheKey]) }

        $manifestRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'manifests/collectors'
        $affected = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $manifestRoot -PathType Container) {
            foreach ($manifestPath in @(Get-ChildItem -LiteralPath $manifestRoot -Recurse -Filter '*.psd1' -File)) {
                try {
                    $definition = Import-PowerShellDataFile -LiteralPath $manifestPath.FullName
                    $types = @($definition.ResourceTypes | ForEach-Object { ([string]$_).ToLowerInvariant() })
                    $text = Get-Content -LiteralPath $manifestPath.FullName -Raw
                    $collectorKey = '{0}/{1}' -f $manifestPath.Directory.Name, $manifestPath.BaseName

                    $isAffected = switch ($Source) {
                        'Resources' {
                            # These types are materialized by the independent ARM REST sweep, not
                            # by the Resource Graph `resources` table. A core ARG failure must not
                            # make their collectors look unavailable when their own source worked.
                            $nonResourceTableTypes = @(
                                'microsoft.advisor/advisorscore'
                                'microsoft.consumption/reservationrecommendations'
                                'microsoft.resourcehealth/events'
                                'microsoft.edge/sites'
                            )
                            $resourceTableTypes = @($types | Where-Object {
                                    $_ -notmatch '^(azsc|entra|devops)/' -and
                                        $_ -notmatch '^microsoft\.network/' -and
                                        $_ -notmatch '^microsoft\.support/supporttickets$' -and
                                        $_ -notmatch '^microsoft\.recoveryservices/vaults/(backuppolicies|backupfabrics/.+/protecteditems)$' -and
                                        $_ -notmatch '^microsoft\.desktopvirtualization/' -and
                                        $_ -notmatch '/patch(assessment|installation)results' -and
                                        $_ -notmatch '^microsoft\.(advisor/recommendations|security/assessments)$' -and
                                        $_ -notmatch '^microsoft\.resources/subscriptions' -and
                                        $_ -notin $nonResourceTableTypes
                                })
                            $derivedArmChildAffected = [bool]@(
                                $types | Where-Object { $resourceDerivedArmChildParents.ContainsKey($_) } | Where-Object {
                                    @($RequestedResourceTypes).Count -eq 0 -or
                                    [bool]@($resourceDerivedArmChildParents[$_] | Where-Object { $_ -in $RequestedResourceTypes }).Count
                                }
                            ).Count
                            if (@($RequestedResourceTypes).Count -gt 0) {
                                $derivedArmChildAffected -or [bool]@($resourceTableTypes | Where-Object { $_ -in $RequestedResourceTypes }).Count
                            }
                            else { $derivedArmChildAffected -or $resourceTableTypes.Count -gt 0 }
                        }
                        'Network Resources' {
                            $networkTableTypes = @($types | Where-Object { $_ -match '^microsoft\.network/' })
                            $networkDiagnosticAffected = $types -contains 'azsc/armchild/resourcediagnosticsettings' -and (
                                @($RequestedResourceTypes).Count -eq 0 -or
                                [bool]@($networkDiagnosticParentTypes | Where-Object { $_ -in $RequestedResourceTypes }).Count
                            )
                            if (@($RequestedResourceTypes).Count -gt 0) {
                                $networkDiagnosticAffected -or [bool]@($networkTableTypes | Where-Object { $_ -in $RequestedResourceTypes }).Count
                            }
                            else { $networkDiagnosticAffected -or $networkTableTypes.Count -gt 0 }
                        }
                        'SupportTickets' { $types -contains 'microsoft.support/supporttickets' }
                        'Backup Items' { $text -match '(?i)microsoft\.recoveryservices/vaults/(?:backuppolicies|backupfabrics/.+/protecteditems)' }
                        'Virtual Desktop' { [bool]@($types | Where-Object { $_ -match '^(microsoft\.desktopvirtualization/|azsc/armchild/avdapplications$|azsc/avd/azurelocalsessionhost$)' }).Count }
                        'Update Manager: Assessments' { $text -match '(?i)PatchAssessment' }
                        'Update Manager: Installations' { $text -match '(?i)PatchInstallation' }
                        'Advisories' { $text -match '(?i)microsoft\.advisor/recommendations' }
                        'Retirements' { $text -match '(?i)\$Retirements\b' }
                        'Subscriptions and Resource Groups' { $collectorKey -eq 'Management/AllSubscriptions' }
                        'Security Center' { $types -contains 'microsoft.security/assessments' }
                        'ARM Child' { [bool]@($types | Where-Object { $_ -in $RequestedResourceTypes }).Count }
                        default { $false }
                    }
                    if ($isAffected) { $affected.Add($collectorKey) }
                }
                catch {
                    Write-Verbose "Get-ScoutRawInventory: could not evaluate collector dependency metadata from '$($manifestPath.FullName)': $($_.Exception.Message)"
                }
            }
        }
        $affectedCollectorCache[$cacheKey] = @($affected | Sort-Object -Unique)
        return @($affectedCollectorCache[$cacheKey])
    }

    function Write-ScoutRawInventoryTiming {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [System.Diagnostics.Stopwatch] $Timer,
            [Parameter(Mandatory)] [string] $Status,
            [Parameter(Mandatory)] [int] $Rows,
            [string] $Detail
        )

        if ($Timer.IsRunning) { $Timer.Stop() }
        $message = 'Extraction subphase {0}: status={1}; rows={2}; elapsed={3}' -f
            $Name, $Status, $Rows, $Timer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
        if ($Detail) { $message += "; $Detail" }
        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level 'VERBOSE' -Message $message
        }
        $phasePercent = switch ($Name) {
            'ARG query sweep'                          { 15 }
            'ARM child resource sweep'                 { 30 }
            'subscription security and policy sweep'   { 45 }
            'operational enrichment'                   { 60 }
            'ARM REST API sweep'                       { 72 }
            'tenant-wide resource sweep'               { 84 }
            'governance dataset sweep'                 { 96 }
            default                                    { 1 }
        }
        Write-Progress -Id 1 -Activity 'Azure Inventory extraction' -Status (
            '{0} {1}; {2} row(s); elapsed {3}' -f $Name, $Status.ToLowerInvariant(), $Rows, $Timer.Elapsed.ToString('hh\:mm\:ss')
        ) -PercentComplete $phasePercent
    }

    function Write-ScoutRawInventoryStart {
        param([Parameter(Mandatory)] [string] $Name)
        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level 'DEBUG' -Message "Extraction subphase $Name started."
        }
        $phasePercent = switch ($Name) {
            'ARG query sweep'                          { 2 }
            'ARM child resource sweep'                 { 16 }
            'subscription security and policy sweep'   { 31 }
            'operational enrichment'                   { 46 }
            'ARM REST API sweep'                       { 61 }
            'tenant-wide resource sweep'               { 73 }
            'governance dataset sweep'                 { 85 }
            default                                    { 1 }
        }
        Write-Progress -Id 1 -Activity 'Azure Inventory extraction' -Status "$Name started" -PercentComplete $phasePercent
    }

    $tagProjection = if ($IncludeTags) { ',tags' } else { '' }
    $columns = "id,name,type,tenantId,kind,location,resourceGroup,subscriptionId,managedBy,sku,plan,properties,identity,zones,extendedLocation$tagProjection"
    $resolvedResourceTypes = @($ResourceTypes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $resourceTypeClause = if ($resolvedResourceTypes.Count -gt 0) {
        $escapedTypes = @($resolvedResourceTypes | ForEach-Object { ([string]$_).Replace("'", "''") })
        "| where type in~ ('$([string]::Join("','", $escapedTypes))')"
    }
    else { '' }

    # Inherited from Start-AZTIGraphExtraction's $ExcludedTypes. What remains -- portal dashboards
    # and template-spec versions -- really are UI/authoring artifacts rather than inventory.
    #
    # `microsoft.logic/workflows` WAS on this list and has been removed (AB#6836). Its comment
    # called it a "Logic Apps designer workflow def"; it is not. It is the Logic App itself, and
    # excluding it made Integration -- Scout's thinnest category -- miss one of the most common
    # resources in any Azure estate, with no way for a user to opt back in. Nothing downstream
    # depended on the absence: no collector, rule or renderer referenced the type, which is why
    # the gap survived every release. Integration/LogicApps.psd1 now consumes these rows.
    $excludedTypesClause = "| where type !in ('microsoft.portal/dashboards','microsoft.resources/templatespecs/versions','microsoft.resources/templatespecs')"

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
            [string]   $LoopName,
            [string[]] $AffectedResourceTypes = @(),
            [string]   $AffectedCollectorSource,
            [ValidateRange(25, 1000)]
            [int]      $PageSize = 1000
        )
        $throttleRetries = 0
        $effectivePageSize = $PageSize
        # A while($true)+continue loop (NOT a do/while on the retry count) is deliberate: a
        # do/while's `continue` re-evaluates the OUTER loop's own condition, not "try the
        # request again" -- with $skipToken still unset on a first-page throttle, that would
        # exit immediately instead of retrying. This inner loop's only exit paths are an
        # explicit `return`.
        while ($true) {
            $params = @{ Query = $Query; First = $effectivePageSize; ErrorAction = 'Stop' }
            if ($SkipToken) { $params.SkipToken = $SkipToken }
            if ($Batch)     { $params.Subscription = $Batch }
            if ($ManagementGroupId -and -not $Batch) { $params.ManagementGroup = $ManagementGroupId }

            try {
                return Search-AzGraph @params
            }
            catch {
                $errText = $_.Exception.Message
                if ($errText -match '(?i)ResponsePayloadTooLarge|response payload size exceeded' -and $effectivePageSize -gt 25) {
                    $effectivePageSize = [Math]::Max(25, [Math]::Floor($effectivePageSize / 2))
                    Write-Verbose "Get-ScoutRawInventory: '$LoopName' exceeded the ARG response payload limit -- retrying with page size $effectivePageSize."
                    continue
                }
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
                $healthTypes = @(
                    $AffectedResourceTypes |
                        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                        Sort-Object -Unique
                )
                $healthCollectors = @(Get-ScoutRawAffectedCollector -Source $AffectedCollectorSource -RequestedResourceTypes $healthTypes)
                $healthKey = '{0}|{1}|{2}' -f $LoopName, ($healthTypes -join ','), ($healthCollectors -join ',')
                if ($collectionHealthKeys.Add($healthKey)) {
                    $collectionHealth.Add([pscustomobject]@{
                            Dataset       = $LoopName
                            Status        = 'Unavailable'
                            Reason        = $errText
                            ResourceTypes = $healthTypes
                            Collectors     = $healthCollectors
                        })
                }
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
            [string]   $LoopName,
            [string[]] $AffectedResourceTypes = @(),
            [string]   $AffectedCollectorSource,
            [ValidateRange(25, 1000)]
            [int]      $PageSize = 1000
        )
        $rows = [System.Collections.Generic.List[object]]::new()
        $skipToken = $null
        do {
            $page = Get-ScoutRawArgPage -Query $Query -Batch $Batch -SkipToken $skipToken -LoopName $LoopName -AffectedResourceTypes $AffectedResourceTypes -AffectedCollectorSource $AffectedCollectorSource -PageSize $PageSize
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
        param(
            [string] $Query,
            [string] $LoopName,
            [string[]] $Subscriptions,
            [string[]] $AffectedResourceTypes = @(),
            [string] $AffectedCollectorSource,
            [ValidateRange(25, 1000)]
            [int] $PageSize = 1000
        )
        if (-not $Subscriptions -or @($Subscriptions).Count -eq 0) {
            return Invoke-ScoutRawArgQuery -Query $Query -LoopName $LoopName -AffectedResourceTypes $AffectedResourceTypes -AffectedCollectorSource $AffectedCollectorSource -PageSize $PageSize
        }
        $rows = [System.Collections.Generic.List[object]]::new()
        # 1000 is the documented Resource Graph maximum subscriptions per call.
        for ($i = 0; $i -lt $Subscriptions.Count; $i += 1000) {
            $upper = [Math]::Min($i + 999, $Subscriptions.Count - 1)
            $batch = @($Subscriptions[$i..$upper])
            foreach ($row in (Invoke-ScoutRawArgQuery -Query $Query -Batch $batch -LoopName $LoopName -AffectedResourceTypes $AffectedResourceTypes -AffectedCollectorSource $AffectedCollectorSource -PageSize $PageSize)) { $rows.Add($row) }
        }
        return , @($rows)
    }

    # A standalone caller may dot-source only this file. Track helpers loaded on demand so they
    # remain available for this raw pass, then remove them before returning. Module imports load
    # every helper up front, so production module commands are never added to this list or removed.
    $dynamicallyLoadedHelpers = [System.Collections.Generic.List[string]]::new()

    function Import-ScoutRawInventoryHelper {
        param(
            [Parameter(Mandatory)] [string] $CommandName,
            [Parameter(Mandatory)] [string] $FileName
        )

        # Optional helpers are loaded only for an explicit opt-in. This keeps normal raw
        # collection independent from staged rebuild files that may not yet be available.
        if (Get-Command $CommandName -ErrorAction SilentlyContinue) { return $true }

        $helperPath = Join-Path $PSScriptRoot $FileName
        if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
            Write-Warning "Get-ScoutRawInventory: optional helper '$CommandName' is unavailable; skipping its opted-in dataset."
            return $false
        }

        try {
            $functionNamesBeforeLoad = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            foreach ($existingFunction in @(Get-ChildItem Function:)) {
                $null = $functionNamesBeforeLoad.Add([string]$existingFunction.Name)
            }

            . $helperPath

            # Dot-sourcing from inside this loader creates the helper in the loader's local
            # function scope. Without promotion, that command disappears as soon as this
            # function returns: the caller then enters the opted-in phase, cannot find the
            # command it just "loaded", and records a systemic source failure. Normal module
            # imports masked the defect because all helpers were already present. Promote the
            # newly loaded function into the owning script/module scope so direct dot-source,
            # isolated tests, and partial-source consumers obey the same contract.
            # Promote every function introduced by the helper file, not merely its public entry
            # command. Several helpers carry private companions in the same file (for example,
            # ConvertTo-ScoutGovernanceResource depends on Get-ScoutGovernanceValue). Promoting
            # only the named command made that companion disappear with this loader's scope.
            foreach ($loadedFunction in @(Get-ChildItem Function:)) {
                $loadedName = [string]$loadedFunction.Name
                if ($functionNamesBeforeLoad.Contains($loadedName)) { continue }
                Set-Item -Path ("Function:script:$loadedName") -Value $loadedFunction.ScriptBlock -Force
                if (-not $dynamicallyLoadedHelpers.Contains($loadedName)) {
                    $dynamicallyLoadedHelpers.Add($loadedName)
                }
            }
        }
        catch {
            Write-Warning "Get-ScoutRawInventory: optional helper '$CommandName' could not be loaded; skipping its opted-in dataset: $($_.Exception.Message)"
            return $false
        }

        if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
            Write-Warning "Get-ScoutRawInventory: optional helper '$CommandName' did not load; skipping its opted-in dataset."
            return $false
        }
        return $true
    }

    # ---- resourcecontainers first: gives every other table a subscription list to batch by,
    # exactly like Invoke-Collect's own AB#397 ordering guarantee. ----
    # `@($SubscriptionIds)` alone is NOT safe here: an unbound [string[]] parameter is $null,
    # and `@($null).Count` is 1, not 0 -- which made the `.Count -eq 0` test below false on the
    # DEFAULT (no -SubscriptionIds) path, so the subscription list was never derived from
    # resourcecontainers and every later table silently ran as a single tenant-wide call with
    # no per-batch isolation at all. Filtering out the null element restores the documented
    # behavior for both paths.
    $argTimer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-ScoutRawInventoryStart -Name 'ARG query sweep'
    $resolvedSubscriptionIds = @($SubscriptionIds | Where-Object { $_ })
    # No $excludedTypesClause here: the legacy extractor applied its type exclusion to the
    # `resources` table ONLY, and none of the four excluded types is a container type anyway.
    # Applying it to resourcecontainers was a (harmless) divergence introduced in v2.7.0; it is
    # removed so the query text matches the shipped one exactly (AB#5648).
    $containerQuery = "resourcecontainers $rgClause $tagClause $mgContainerClause | project $columns | order by id asc"
    $resourceContainers = Invoke-ScoutRawTable -Query $containerQuery -LoopName 'Subscriptions and Resource Groups' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.resources/subscriptions', 'microsoft.resources/subscriptions/resourcegroups') -AffectedCollectorSource 'Subscriptions and Resource Groups'
    if ($resolvedSubscriptionIds.Count -eq 0) {
        $resolvedSubscriptionIds = @(
            $resourceContainers |
                Where-Object {
                    [string] $_.type -ieq 'microsoft.resources/subscriptions' -and
                    ($null -eq $_.PSObject.Properties['properties'] -or
                        $null -eq $_.properties -or
                        $null -eq $_.properties.PSObject.Properties['state'] -or
                        [string]$_.properties.state -ieq 'Enabled')
                } |
                ForEach-Object { $_.subscriptionId } |
                Where-Object { $_ }
        )
    }

    $resources = [System.Collections.Generic.List[object]]::new()
    if ($CollectResourceTable) {
        $resourceHealthTypes = if ($resolvedResourceTypes.Count -gt 0) { $resolvedResourceTypes } else { @() }
        foreach ($row in (Invoke-ScoutRawTable -Query "resources $rgClause $tagClause $mgJoinClause $resourceTypeClause $excludedTypesClause | project $columns | order by id asc" -LoopName 'Resources' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes $resourceHealthTypes -AffectedCollectorSource 'Resources')) { $resources.Add($row) }
    }
    if ($CollectNetworkTable) {
        $networkHealthTypes = if ($resolvedResourceTypes.Count -gt 0) { @($resolvedResourceTypes | Where-Object { $_ -like 'microsoft.network/*' }) } else { @() }
        foreach ($row in (Invoke-ScoutRawTable -Query "networkresources $rgClause $tagClause $mgJoinClause $resourceTypeClause | project $columns | order by id asc" -LoopName 'Network Resources' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes $networkHealthTypes -AffectedCollectorSource 'Network Resources')) { $resources.Add($row) }
    }

    if ($IncludeSupportResources -and $AzureEnvironment -ne 'AzureUSGovernment') {
        foreach ($row in (Invoke-ScoutRawTable -Query "SupportResources $rgClause $tagClause $mgJoinClause | project $columns | order by id asc" -LoopName 'SupportTickets' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.support/supporttickets') -AffectedCollectorSource 'SupportTickets')) { $resources.Add($row) }
    }

    if ($IncludeBackupResources) {
        # The management-group join goes AFTER the type filter here, exactly as the legacy
        # extractor rendered it -- the tag clause goes before. Not symmetric, but faithful.
        $backupQuery = "recoveryservicesresources $rgClause $tagClause | where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' or type =~ 'microsoft.recoveryservices/vaults/backuppolicies' $mgJoinClause | project $columns | order by id asc"
        foreach ($row in (Invoke-ScoutRawTable -Query $backupQuery -LoopName 'Backup Items' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.recoveryservices/vaults/backuppolicies', 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems') -AffectedCollectorSource 'Backup Items')) { $resources.Add($row) }
    }

    if ($IncludeDesktopVirtualization) {
        # No tag clause: the legacy extractor never applied one to this table.
        foreach ($row in (Invoke-ScoutRawTable -Query "desktopvirtualizationresources $rgClause $mgJoinClause | project $columns | order by id asc" -LoopName 'Virtual Desktop' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.desktopvirtualization/hostpools', 'microsoft.desktopvirtualization/hostpools/sessionhosts', 'microsoft.desktopvirtualization/applicationgroups', 'microsoft.desktopvirtualization/scalingplans', 'microsoft.desktopvirtualization/workspaces', 'AZSC/ARMChild/AVDApplications', 'AZSC/AVD/AzureLocalSessionHost') -AffectedCollectorSource 'Virtual Desktop')) { $resources.Add($row) }
    }

    # ---- Azure Update Manager patch data (AB#6731) ----
    # READ ONLY. Azure Update Manager already pushes every assessment and installation result into
    # these two Resource Graph tables on its own schedule, so the data is simply there to be read:
    #
    #   patchassessmentresources   pending/available updates      retained  7 days
    #   patchinstallationresources update installation history     retained 30 days
    #
    # Both cover microsoft.compute/virtualmachines AND microsoft.hybridcompute/machines, so Azure
    # VMs and Arc-enabled servers come back from the same query.
    #
    # This REPLACES the previous per-machine `POST .../assessPatches` calls. That endpoint is an
    # ARM *action*, not a read: it commanded every VM and Arc machine in the tenant to run a fresh
    # guest-OS patch scan on every Scout run -- work that can take hours, that Reader does not
    # grant, and that made a tool documented as read-only mutate customer machines. The summary
    # rows below carry the same counts that call returned, and the /softwarepatches child rows
    # carry per-update detail (KB id, classification, reboot requirement) it never returned at all.
    #
    # Retention is the one behavioural difference worth knowing: a machine Update Manager has not
    # assessed within 7 days has no row here. That is a true statement about the estate -- the old
    # code manufactured a fresh answer by forcing a scan, which is exactly the behaviour being
    # removed.
    if ($IncludeUpdateManagerResources) {
        $patchAssessQuery = "patchassessmentresources $rgClause $mgJoinClause | order by id asc"
        foreach ($row in (Invoke-ScoutRawTable -Query $patchAssessQuery -LoopName 'Update Manager: Assessments' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.compute/virtualmachines/patchassessmentresults', 'microsoft.hybridcompute/machines/patchassessmentresults', 'microsoft.connectedvmwarevsphere/virtualmachines/patchassessmentresults') -AffectedCollectorSource 'Update Manager: Assessments')) { $resources.Add($row) }

        $patchInstallQuery = "patchinstallationresources $rgClause $mgJoinClause | order by id asc"
        foreach ($row in (Invoke-ScoutRawTable -Query $patchInstallQuery -LoopName 'Update Manager: Installations' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.compute/virtualmachines/patchinstallationresults', 'microsoft.hybridcompute/machines/patchinstallationresults', 'microsoft.connectedvmwarevsphere/virtualmachines/patchinstallationresults') -AffectedCollectorSource 'Update Manager: Installations')) { $resources.Add($row) }
    }

    $advisories = @()
    if ($IncludeAdvisories) {
        $advisorQuery = "advisorresources $rgClause $mgJoinClause | where properties.impact in~ ('Medium','High') | order by id asc"
        $advisories = Invoke-ScoutRawTable -Query $advisorQuery -LoopName 'Advisories' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.advisor/recommendations') -AffectedCollectorSource 'Advisories'
    }

    $security = @()
    if ($IncludeSecurityCenter) {
        # Full Defender assessment payloads regularly exceed Resource Graph's 16 MiB response
        # ceiling even with row paging. The legacy report consumes only this narrow shape, so
        # project it server-side and use a conservative page size. The paging helper also halves
        # the page on ResponsePayloadTooLarge as a final safety net.
        $securityProperties = "bag_pack('resourceDetails',bag_pack('id',tostring(properties.resourceDetails.id)),'metadata',bag_pack('categories',properties.metadata.categories,'severity',tostring(properties.metadata.severity),'remediationDescription',tostring(properties.metadata.remediationDescription),'implementationEffort',tostring(properties.metadata.implementationEffort),'userImpact',tostring(properties.metadata.userImpact),'threats',properties.metadata.threats),'displayName',tostring(properties.displayName),'status',bag_pack('code',tostring(properties.status.code)))"
        $securityQuery = "securityresources $rgClause | where type =~ 'microsoft.security/assessments' and properties['status']['code'] == 'Unhealthy' $mgJoinClause | project id,name,type,tenantId,resourceGroup,subscriptionId,properties=$securityProperties | order by id asc"
        $security = Invoke-ScoutRawTable -Query $securityQuery -LoopName 'Security Center' -Subscriptions $resolvedSubscriptionIds -AffectedResourceTypes @('microsoft.security/assessments') -AffectedCollectorSource 'Security Center' -PageSize 200
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
            $retirements = Invoke-ScoutRawTable -Query $retirementQuery -LoopName 'Retirements' -Subscriptions $resolvedSubscriptionIds -AffectedCollectorSource 'Retirements'
        }
        catch {
            Write-Warning "Get-ScoutRawInventory: the retirement query at '$resolvedRetirementPath' could not be read -- Retirements will be empty and the rest of the inventory is unaffected: $($_.Exception.Message)"
            $healthCollectors = @(Get-ScoutRawAffectedCollector -Source 'Retirements')
            $healthKey = 'Retirements||{0}' -f ($healthCollectors -join ',')
            if ($collectionHealthKeys.Add($healthKey)) {
                $collectionHealth.Add([pscustomobject]@{
                        Dataset       = 'Retirements'
                        Status        = 'Unavailable'
                        Reason        = $_.Exception.Message
                        ResourceTypes = @()
                        Collectors    = $healthCollectors
                    })
            }
            $retirements = @()
        }
    }

    Write-ScoutRawInventoryTiming -Name 'ARG query sweep' -Timer $argTimer -Status 'Completed' `
        -Rows @($resources).Count -Detail ('containers={0}; advisories={1}; security={2}; retirements={3}' -f
            @($resourceContainers).Count, @($advisories).Count, @($security).Count, @($retirements).Count)

    # Optional non-ARG collector inputs use the existing Resources envelope rather than adding
    # a new top-level contract. The assessment shaper ignores unknown AZSC/* types, so opting
    # into these inventory-only rows cannot alter assessment-shaped output.
    #
    # NOTE: outage normalisation used to sit HERE and has moved below the ARM REST sweep --
    # see the AB#6770 block near the end of this function for why.

    if ($IncludeArmChildResources -and (Import-ScoutRawInventoryHelper -CommandName 'Get-ScoutArmChildResource' -FileName 'Get-ScoutArmChildResource.ps1')) {
        $childTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutRawInventoryStart -Name 'ARM child resource sweep'
        $childStartCount = $resources.Count
        $childStatus = 'Completed'
        $armChildHealth = [System.Collections.Generic.List[object]]::new()
        try {
            foreach ($row in @(Get-ScoutArmChildResource -Resources @($resources) -Dataset $ArmChildDataset -CollectionHealth $armChildHealth)) {
                if ($null -ne $row) { $resources.Add($row) }
            }

            foreach ($health in @($armChildHealth)) {
                if ($null -eq $health -or -not $health.PSObject.Properties['Dataset']) { continue }
                $sourceDataset = [string]$health.Dataset
                $resourceTypes = @(
                    if ($health.PSObject.Properties['ResourceTypes']) { $health.ResourceTypes }
                    else { "AZSC/ARMChild/$sourceDataset" }
                )
                $healthCollectors = @(Get-ScoutRawAffectedCollector -Source 'ARM Child' -RequestedResourceTypes $resourceTypes)
                $healthKey = 'Resources|ARM Child:{0}|{1}' -f $sourceDataset, ($healthCollectors -join ',')
                if ($collectionHealthKeys.Add($healthKey)) {
                    $collectionHealth.Add([pscustomobject]@{
                            Dataset       = 'Resources'
                            Source        = 'ARM Child'
                            SourceDataset = $sourceDataset
                            Operation     = if ($health.PSObject.Properties['Operation']) { [string]$health.Operation } else { $sourceDataset }
                            Status        = if ($health.PSObject.Properties['Status']) { [string]$health.Status } else { 'Unavailable' }
                            Reason        = if ($health.PSObject.Properties['Reason']) { [string]$health.Reason } else { "ARM child dataset '$sourceDataset' could not be read." }
                            ResourceTypes = $resourceTypes
                            Collectors    = $healthCollectors
                        })
                }
            }
            if ($armChildHealth.Count -gt 0) { $childStatus = 'Partial' }
        }
        catch {
            $childStatus = 'Failed'
            $failureReason = "ARM child collection failed before per-dataset health could be returned: $($_.Exception.Message)"
            Write-Warning "Get-ScoutRawInventory: $failureReason; continuing without its synthetic rows."

            # A helper-level exception is distinct from the remote failures that the helper
            # reports per dataset. Keep it visible as source health so assessment callers do not
            # interpret an unexpectedly empty synthetic row set as successful evidence.
            $requestedChildDatasets = @($ArmChildDataset | Where-Object { $_ -and $_ -ne 'All' })
            $failedResourceTypes = @($requestedChildDatasets | ForEach-Object { "AZSC/ARMChild/$_" })
            $failedCollectors = if ($failedResourceTypes.Count -gt 0) {
                @(Get-ScoutRawAffectedCollector -Source 'ARM Child' -RequestedResourceTypes $failedResourceTypes)
            }
            else { @() }
            $healthKey = 'Resources|ARM Child:Systemic|{0}' -f ($failedCollectors -join ',')
            if ($collectionHealthKeys.Add($healthKey)) {
                $collectionHealth.Add([pscustomobject]@{
                        Dataset       = 'Resources'
                        Source        = 'ARM Child'
                        SourceDataset = if ($requestedChildDatasets.Count -gt 0) { $requestedChildDatasets -join ',' } else { 'All' }
                        Operation     = 'Sweep'
                        Status        = 'Failed'
                        Reason        = $failureReason
                        ResourceTypes = $failedResourceTypes
                        Collectors    = $failedCollectors
                    })
            }
        }
        finally {
            Write-ScoutRawInventoryTiming -Name 'ARM child resource sweep' -Timer $childTimer -Status $childStatus `
                -Rows ($resources.Count - $childStartCount)
        }
    }

    # This is a pure transform of rows already collected above, not an optional ARM enrichment.
    # Appending its typed envelope lets the AVDAzureLocal declarative collector retain the legacy
    # Arc -> Azure Local -> session-host fallback ordering without mutating raw ARG rows.
    if (Import-ScoutRawInventoryHelper -CommandName 'ConvertTo-ScoutAvdAzureLocalSessionHost' -FileName 'ConvertTo-ScoutAvdAzureLocalSessionHost.ps1') {
        try {
            foreach ($row in @(ConvertTo-ScoutAvdAzureLocalSessionHost -Resources @($resources))) {
                if ($null -ne $row) { $resources.Add($row) }
            }
        }
        catch {
            Write-Warning "Get-ScoutRawInventory: AVD Azure Local row transform failed; continuing without its synthetic rows: $($_.Exception.Message)"
        }
    }

    # Normalise the subscription rows once. Explicit subscription ids remain usable when the
    # resourcecontainers call is unavailable, but container names take precedence when present.
    $subscriptionEnvelopes = @(
        $resourceContainers |
            Where-Object {
                [string] $_.type -ieq 'microsoft.resources/subscriptions' -and $_.subscriptionId -and
                ($null -eq $_.PSObject.Properties['properties'] -or
                    $null -eq $_.properties -or
                    $null -eq $_.properties.PSObject.Properties['state'] -or
                    [string]$_.properties.state -ieq 'Enabled')
            } |
            ForEach-Object {
                [pscustomobject]@{
                    id   = [string] $_.subscriptionId
                    name = if ($_.PSObject.Properties['name'] -and $_.name) { [string] $_.name } else { [string] $_.subscriptionId }
                }
            }
    )
    if ($subscriptionEnvelopes.Count -eq 0 -and $resolvedSubscriptionIds.Count -gt 0) {
        $subscriptionEnvelopes = @($resolvedSubscriptionIds | ForEach-Object {
                [pscustomobject]@{ id = [string] $_; name = [string] $_ }
            })
    }

    if ($IncludeSubscriptionSecurityPolicy -and (Import-ScoutRawInventoryHelper -CommandName 'Get-ScoutSubscriptionSecurityPolicySweep' -FileName 'Get-ScoutSubscriptionSecurityPolicySweep.ps1')) {
        $securityPolicyCollectorMap = @{
            DefenderAlerts                 = @('Security/DefenderAlerts')
            DefenderAssessments            = @('Security/DefenderAssessments')
            DefenderPricing                = @('Security/DefenderPricing')
            DefenderSecureScores           = @('Security/DefenderSecureScore')
            DefenderSecureScoreControls    = @('Security/DefenderSecureScore')
            SubscriptionDiagnosticSettings = @('Monitor/SubscriptionDiagnosticSettings')
            PolicyComplianceStates         = @('Management/PolicyComplianceStates')
        }
        $securityPolicyTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutRawInventoryStart -Name 'subscription security and policy sweep'
        $securityPolicyStartCount = $resources.Count
        $securityPolicyStatus = 'Completed'
        try {
            foreach ($row in @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions $subscriptionEnvelopes)) {
                if ($null -eq $row) { continue }
                $resources.Add($row)
                $statusProperty = $row.properties.PSObject.Properties['CollectionStatus']
                if ($statusProperty -and $statusProperty.Value) {
                    $collectionErrors = if ($row.properties.PSObject.Properties['CollectionErrors']) {
                        @($row.properties.CollectionErrors)
                    }
                    else { @() }
                    $contextError = @($collectionErrors | Where-Object Dataset -eq 'Context' | Select-Object -First 1)
                    foreach ($status in $statusProperty.Value.PSObject.Properties) {
                        $statusValue = [string]$status.Value
                        $isUnavailable = $statusValue -in @('Unavailable', 'Failed') -or
                            ($statusValue -eq 'Skipped' -and $contextError.Count -gt 0)
                        if ($isUnavailable) {
                            $datasetError = @($collectionErrors | Where-Object Dataset -eq $status.Name | Select-Object -First 1)
                            $reason = if ($datasetError.Count -gt 0) { [string]$datasetError[0].Message }
                            elseif ($contextError.Count -gt 0) { [string]$contextError[0].Message }
                            else { 'The subscription-scoped dataset was not available.' }
                            $collectionHealth.Add([pscustomobject]@{
                                    Dataset       = "SecurityPolicy/$($status.Name) [$($row.subscriptionName)]"
                                    Status        = if ($statusValue -eq 'Skipped') { 'Unavailable' } else { $statusValue }
                                    Reason        = $reason
                                    ResourceTypes = @('AZSC/Subscription/SecurityPolicySweep')
                                    Collectors     = @($securityPolicyCollectorMap[$status.Name])
                                })
                        }
                    }
                }
            }
        }
        catch {
            $securityPolicyStatus = 'Failed'
            Write-Warning "Get-ScoutRawInventory: subscription security/policy collection failed; continuing without its synthetic rows: $($_.Exception.Message)"
        }
        finally {
            Write-ScoutRawInventoryTiming -Name 'subscription security and policy sweep' -Timer $securityPolicyTimer `
                -Status $securityPolicyStatus -Rows ($resources.Count - $securityPolicyStartCount)
        }
    }

    if ($IncludeOperationalCollectorEnrichment -and (Import-ScoutRawInventoryHelper -CommandName 'Get-ScoutOperationalCollectorEnrichment' -FileName 'Get-ScoutOperationalCollectorEnrichment.ps1')) {
        $operationalTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutRawInventoryStart -Name 'operational enrichment'
        $operationalStartCount = $resources.Count
        $operationalStatus = 'Completed'
        $operationalHealth = [System.Collections.Generic.List[object]]::new()
        try {
            $operationalArguments = @{
                Resources     = @($resources)
                Subscriptions = $subscriptionEnvelopes
            }
            $operationalCommand = Get-Command Get-ScoutOperationalCollectorEnrichment -ErrorAction Stop
            if ($operationalCommand.Parameters.ContainsKey('CollectionHealth')) {
                $operationalArguments['CollectionHealth'] = $operationalHealth
            }
            foreach ($row in @(Get-ScoutOperationalCollectorEnrichment @operationalArguments)) {
                if ($null -ne $row) { $resources.Add($row) }
            }
            foreach ($health in $operationalHealth) { $collectionHealth.Add($health) }
            if ($operationalHealth.Count -gt 0) { $operationalStatus = 'Partial' }
        }
        catch {
            $operationalStatus = 'Failed'
            Write-Warning "Get-ScoutRawInventory: operational collector enrichment failed; continuing without its synthetic rows: $($_.Exception.Message)"
        }
        finally {
            Write-ScoutRawInventoryTiming -Name 'operational enrichment' -Timer $operationalTimer `
                -Status $operationalStatus -Rows ($resources.Count - $operationalStartCount)
        }
    }

    # ── Tenant-wide collection ────────────────────────────────────────────────────────────────
    #
    # Management groups, custom role definitions, policy definitions and policy set definitions
    # are what a landing-zone or governance assessment IS. They are not an opt-in extra, and
    # there is no longer any parameter that turns them off.
    #
    # AB#6755 removed the dead `-IncludeTenantWideResources` gate that no production caller ever
    # set. The first fix replaced it with `-not $SkipAPIs`, which was wrong twice over and the
    # owner rightly rejected it:
    #
    #   1. "A switch that is usually set" is the same trap as "a switch nobody sets". An
    #      assessment that scores governance against an empty array and reports a pass is worse
    #      than one that fails loudly, so the inputs to that claim must not be optional.
    #   2. Only the POLICY definitions come from the ARM REST sweep. Management groups and custom
    #      role definitions come from Get-AzManagementGroup / Get-AzRoleDefinition -Custom, which
    #      -SkipAPIs has nothing to do with — so gating the whole block on it silently dropped two
    #      datasets that flag has no business touching.
    #
    # -SkipAPIs now degrades only the half that is genuinely ARM REST work.
    # Get-ScoutTenantWideResource accepts an empty -ApiResources by design and still returns all
    # four envelopes, so the management-group and custom-role halves are unaffected.
    #
    # $collectedApiResources is returned on the envelope so the v1 inventory orchestration can
    # consume this sweep rather than issuing its own identical one after the raw pass returns.
    $collectedApiResources = @()

    # Full/default and assessment-backed paths leave both collection booleans true. A selective
    # inventory category can turn off either independent phase through the internal plan; these
    # are booleans (not public opt-in switches) so an omitted argument preserves the established
    # full-collection contract.
    if (-not $SkipApiResourceSweep -and
        (Import-ScoutRawInventoryHelper -CommandName 'Get-ScoutApiResources' -FileName 'Get-ScoutApiResources.ps1')) {
        $apiSweepTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutRawInventoryStart -Name 'ARM REST API sweep'
        $apiSweepStatus = 'Completed'
        try {
            $apiArgs = @{
                Subscriptions    = $subscriptionEnvelopes
                AzureEnvironment = $AzureEnvironment
                SkipPolicy       = $SkipPolicy
                DefinitionsOnly  = $TenantWideDefinitionsOnly
            }
            # Older isolated test shadows predate this optimization. Production owns the
            # parameter and uses ARG as the single source for managed identities.
            if ((Get-Command Get-ScoutApiResources).Parameters.ContainsKey('SkipManagedIdentities')) {
                $apiArgs.SkipManagedIdentities = $true
            }
            $collectedApiResources = @(Get-ScoutApiResources @apiArgs)
        }
        catch {
            $apiSweepStatus = 'Failed'
            Write-Warning "Get-ScoutRawInventory: the ARM REST sweep failed; policy definitions will be empty, management groups and custom roles are unaffected: $($_.Exception.Message)"
        }
        finally {
            Write-ScoutRawInventoryTiming -Name 'ARM REST API sweep' -Timer $apiSweepTimer -Status $apiSweepStatus `
                -Rows @($collectedApiResources).Count
        }
    }

    $tenantHelpersAvailable = $CollectTenantWideResources -and
        (Import-ScoutRawInventoryHelper -CommandName 'ConvertTo-ScoutManagementGroupHierarchy' -FileName 'ConvertTo-ScoutManagementGroupHierarchy.ps1') -and
        (Import-ScoutRawInventoryHelper -CommandName 'Get-ScoutTenantWideResource' -FileName 'Get-ScoutTenantWideResource.ps1')
    if ($tenantHelpersAvailable) {
        $tenantWideTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutRawInventoryStart -Name 'tenant-wide resource sweep'
        $tenantWideStartCount = $resources.Count
        $tenantWideStatus = 'Completed'
        try {
            foreach ($row in @(Get-ScoutTenantWideResource -ApiResources $collectedApiResources)) {
                if ($null -ne $row) { $resources.Add($row) }
            }
        }
        catch {
            $tenantWideStatus = 'Failed'
            Write-Warning "Get-ScoutRawInventory: tenant-wide collection failed; continuing without its synthetic rows: $($_.Exception.Message)"
        }
        finally {
            Write-ScoutRawInventoryTiming -Name 'tenant-wide resource sweep' -Timer $tenantWideTimer `
                -Status $tenantWideStatus -Rows ($resources.Count - $tenantWideStartCount)
        }

    }

    # AB#6801: Microsoft.Edge/sites rides the ARM REST sweep on its ArcSites field. This
    # conversion remains independent of tenant-wide management/policy envelopes because Hybrid
    # category extraction needs Arc sites without paying for unrelated tenant-wide cmdlets.
    if (-not $SkipApiResourceSweep -and
        (Import-ScoutRawInventoryHelper -CommandName 'ConvertTo-ScoutArcSiteResource' -FileName 'ConvertTo-ScoutArcSiteResource.ps1')) {
        try {
            foreach ($row in @(ConvertTo-ScoutArcSiteResource -ApiResources $collectedApiResources)) {
                if ($null -ne $row) { $resources.Add($row) }
            }
        }
        catch {
            Write-Warning "Get-ScoutRawInventory: Arc site conversion failed; continuing without its synthetic rows: $($_.Exception.Message)"
        }
    }

    # ── Outage narrative normalisation — AB#6770 ──────────────────────────────────────────────
    #
    # This block MUST run after the ARM REST sweep above, and it used to run ~120 lines before
    # it. That ordering is the whole defect: `Microsoft.ResourceHealth/events` is not in the
    # `resources` or `networkresources` tables this function queries -- Resource Graph exposes
    # service-health events only through `servicehealthresources`, which Scout does not query,
    # and the events Scout DOES collect arrive from Get-ScoutApiResources' `ResourceHealth`
    # field. So the transform ran against a row set that could never contain a single event,
    # emitted nothing, and Monitor/Outages was empty in every tenant on every run at every
    # permission level. Nothing threw, because "no matching rows" is a legal outcome here.
    #
    # It is still a pure transform -- no Azure request is made in this block -- and it is still
    # unconditional; only its INPUT changed. The raw events are deliberately NOT appended to
    # $resources: Start-AZTIExtractionOrchestration already appends them from the same sweep
    # (via the ApiResources field returned below), and adding them here would duplicate every
    # event row on the inventory path.
    $resourceHealthEvents = [System.Collections.Generic.List[object]]::new()
    foreach ($sweepResult in @($collectedApiResources)) {
        if ($null -eq $sweepResult) { continue }
        # Element-wise, never `$collectedApiResources.ResourceHealth`: member enumeration over a
        # collection whose every element yields an EMPTY value throws under StrictMode, which is
        # the AB#5633 crash class. A subscription with no events is the normal case here.
        $healthProperty = $sweepResult.PSObject.Properties['ResourceHealth']
        if ($null -eq $healthProperty -or $null -eq $healthProperty.Value) { continue }
        foreach ($healthEvent in @($healthProperty.Value)) {
            if ($null -ne $healthEvent) { $resourceHealthEvents.Add($healthEvent) }
        }
    }

    if (Import-ScoutRawInventoryHelper -CommandName 'Get-ScoutOutageResource' -FileName 'Get-ScoutOutageResource.ps1') {
        try {
            $outageInput = @(@($resources) + @($resourceHealthEvents))
            foreach ($row in @(Get-ScoutOutageResource -Resources $outageInput)) {
                if ($null -ne $row) { $resources.Add($row) }
            }
        }
        catch {
            Write-Warning "Get-ScoutRawInventory: outage normalisation failed; continuing with the raw Resource Health events: $($_.Exception.Message)"
        }
    }

    # ── Governance collection — UNCONDITIONAL, and collected exactly ONCE ─────────────────────
    #
    # Role assignments, policy assignments, resource locks and budgets used to be collected by
    # src/ingest/Import-Governance.ps1 on every assessment run and rendered nowhere: no collector
    # consumed them, so a run could not answer "who has Owner" while holding the answer in memory
    # (AB#6779).
    #
    # Collecting them HERE rather than there is what makes the four new worksheets free. The two
    # Resource Graph queries and the two ARM REST reads per subscription MOVED out of
    # Import-Governance into this pass; Invoke-Collect hands the result straight to
    # $collect.governance, and Import-Governance now skips whatever is already populated. An
    # assessment run therefore issues exactly the same number of calls it did before, and the
    # inventory run gains four worksheets from data it is already paying for.
    #
    # Unconditional for the same reason the tenant-wide block above is: an assessment that scores
    # governance against an empty array and reports a pass is worse than one that fails loudly, so
    # its inputs must not sit behind a switch.
    $governance = $null
    if ($CollectGovernance -and
        (Import-ScoutRawInventoryHelper -CommandName 'Get-ScoutGovernanceDataset' -FileName 'Get-ScoutGovernanceDataset.ps1') -and
        (Import-ScoutRawInventoryHelper -CommandName 'ConvertTo-ScoutGovernanceResource' -FileName 'ConvertTo-ScoutGovernanceResource.ps1')) {
        $governanceTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutRawInventoryStart -Name 'governance dataset sweep'
        $governanceStartCount = $resources.Count
        $governanceStatus = 'Completed'
        try {
            $governanceArgs = @{ Subscriptions = $subscriptionEnvelopes }
            if ($ManagementGroupId) { $governanceArgs.ManagementGroupId = $ManagementGroupId }
            $governance = Get-ScoutGovernanceDataset @governanceArgs

            foreach ($row in @(ConvertTo-ScoutGovernanceResource -Governance $governance -Subscriptions $subscriptionEnvelopes)) {
                if ($null -ne $row) { $resources.Add($row) }
            }
        }
        catch {
            $governanceStatus = 'Failed'
            Write-Warning "Get-ScoutRawInventory: governance collection failed; continuing without its synthetic rows: $($_.Exception.Message)"
        }
        finally {
            Write-ScoutRawInventoryTiming -Name 'governance dataset sweep' -Timer $governanceTimer `
                -Status $governanceStatus -Rows ($resources.Count - $governanceStartCount)
        }
    }

    if (@($resources).Count -eq 0 -and @($resourceContainers).Count -eq 0) {
        Write-Warning ('Get-ScoutRawInventory: extraction returned zero resources. Verify the identity has Reader ' +
            'at the target scope (root management group for full coverage) and that -ManagementGroupId/-SubscriptionIds is correct.')
    }

    Write-Progress -Id 1 -Activity 'Azure Inventory extraction' -Status 'Extraction subphases complete' -Completed

    $result = [pscustomobject]@{
        Resources          = @($resources)
        ResourceContainers = @($resourceContainers)
        Advisories         = @($advisories)
        Security           = @($security)
        Retirements        = @($retirements)
        ApiResources       = @($collectedApiResources)
        # AB#6779 -- the governance datasets this pass just collected, handed up so Invoke-Collect
        # fills $collect.governance from them instead of Import-Governance querying Azure again.
        Governance         = $governance
        CollectionHealth   = @($collectionHealth)
    }

    # Do not leak dynamically loaded collectors into a standalone caller's session. Persistent
    # global functions make later isolated tests (or scripts) silently call live Azure cmdlets.
    foreach ($helperName in $dynamicallyLoadedHelpers) {
        Remove-Item -Path ("Function:$helperName") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path ("Function:script:$helperName") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path ("Function:global:$helperName") -Force -ErrorAction SilentlyContinue
    }

    return $result
}
