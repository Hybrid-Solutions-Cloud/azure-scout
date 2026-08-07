#Requires -Version 7.0
<#
.SYNOPSIS
    AB#7060 -- maps every collector manifest to whether its resource types are queried anywhere
    in the assessment collect (Invoke-Collect.ps1), the pipeline that feeds the React report, and
    optionally whether that resource type has live rows in a real tenant.

.DESCRIPTION
    242 collector manifests under manifests/collectors/ each declare the ARM resource type(s)
    they read (`ResourceTypes`). Invoke-Collect.ps1 -- the assessment collect that produces the
    payload the React report renders -- runs a fixed set of Resource Graph KQL queries, each
    keyed by name, each filtering on `type =~ "<resource type>"` (or `type in~ (...)`).

    This script extracts both sides statically (no live tenant needed for the WIRED/NOT WIRED
    verdict -- the banked corpus only contains collect.json, the ALREADY-SHAPED payload, which
    cannot answer "is this resource type queried at all") and reports, per manifest:

      WIRED       -- at least one of its ResourceTypes is queried by name in Invoke-Collect.ps1.
                     Its data CAN reach the payload; whether it actually renders is a shaping
                     question for AB#7059's per-category tasks, not this audit.
      NOT WIRED   -- none of its ResourceTypes appear anywhere in Invoke-Collect.ps1. This is the
                     definitive "never reaches the payload" list AB#7059/AB#7069 exist to close.
      NEEDS MANUAL CHECK -- declares a synthetic AZSC/* marker rather than a real ARM resource
                     type (an ARM-child sweep or a subscription-level sweep); this method cannot
                     resolve these either way.

    -LiveTypeCounts accepts a JSON file of {resourceType: rowCount} from a REAL Azure Resource
    Graph query (see the accompanying live-query recipe in the AB#7060 board comment) and adds,
    for every NOT WIRED collector, whether that resource type has actual rows in the tenant the
    counts were pulled from RIGHT NOW -- turning "this collector is unwired" into "and here is
    live evidence the estate has data it is missing" without needing a full live collect run.

.EXAMPLE
    ./scripts/Test-CollectorPayloadCoverage.ps1
    ./scripts/Test-CollectorPayloadCoverage.ps1 -OutputPath docs/reference/collector-payload-coverage.md -LiveTypeCounts hcs-live-type-counts.json -LiveTenantLabel hcs
#>
[CmdletBinding()]
param(
    [string] $RepoRoot        = (Split-Path -Parent $PSScriptRoot),
    [string] $OutputPath      = '',
    [string] $LiveTypeCounts  = '',
    [string] $LiveTenantLabel = 'live tenant'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$collectPath = Join-Path $RepoRoot 'src/collect/Invoke-Collect.ps1'
$collectText = Get-Content -LiteralPath $collectPath -Raw

# ---- 1. extract every $q key -> KQL body pair -----------------------------------------------
# Pattern: a bare identifier at the start of a hashtable entry, followed by = @'...'@ (here-string).
# Invoke-Collect.ps1's $q hashtable is the ONLY here-string-per-key block in the file at this
# indentation, so this pattern is deliberately narrow rather than a generic PSD1/hashtable parser.
$keyBodyRegex = [regex]'(?ms)^\s{8}(\w+)\s*=\s*@''(.*?)''@'
$queryMatches = $keyBodyRegex.Matches($collectText)
if ($queryMatches.Count -eq 0) {
    throw "No `$q = @{ key = @'...'@ } entries matched in $collectPath -- the extraction pattern no longer fits the file. Check Invoke-Collect.ps1's `$q hashtable shape before trusting this audit."
}

# ---- 2. build resourceType -> [collect keys that reference it] ---------------------------
$typeToKeys = @{}
$typePattern = [regex]'(?i)type\s*(?:=~|in~\s*\()\s*"?([a-z0-9.]+/[a-z0-9./]+)"?'
foreach ($m in $queryMatches) {
    $key = $m.Groups[1].Value
    $body = $m.Groups[2].Value
    foreach ($tm in $typePattern.Matches($body)) {
        $rt = $tm.Groups[1].Value.ToLowerInvariant().TrimEnd('/')
        if (-not $typeToKeys.ContainsKey($rt)) { $typeToKeys[$rt] = [System.Collections.Generic.HashSet[string]]::new() }
        [void]$typeToKeys[$rt].Add($key)
    }
}
"Assessment-collect keys found: $($queryMatches.Count)"
"Distinct resource types referenced: $($typeToKeys.Count)"

# ---- 1b. the 40 synthetic-AZSC/* collectors, resolved by hand against Invoke-Collect.ps1's own
# canonical payload-shape doc (lines 19-73 of that file), not left as "needs manual check".
# None of these are `type =~` KQL filters (they're ARM-child sweeps or a legacy subscription-wide
# security/policy sweep), so the static regex above can never see them -- this table is the
# result of actually reading the canonical shape comment and the governance/keyvault wiring code
# (the raw-governance pass at ~line 1065, the KeyVault ARM-child sweep at ~line 1309,
# Get-ScoutDefenderPlanSweep at ~line 1383) and matching each collector to a real verdict.
$syntheticVerdicts = @{
    'azsc/armchild/arcsites'                       = @{ Wired=$true;  Reason='canonical shape line 53: hybrid.arcSites[] -- always present as a key, populated when -IncludeAzureLocalArm is passed (AB#6803)' }
    'azsc/armchild/azurelocalvirtualmachineinstances' = @{ Wired=$true;  Reason='canonical shape line 53: hybrid.azureLocalVirtualMachineInstances[] -- same -IncludeAzureLocalArm gate as arcSites' }
    'azsc/governance/roleassignment'               = @{ Wired=$true;  Reason='canonical shape line 34: governance.roleAssignments[] -- filled by the raw-governance pass, Invoke-Collect.ps1 ~line 1065' }
    'azsc/management/subscriptionenrichment'       = @{ Wired=$true;  Reason='canonical shape line 20: top-level subscriptions[] IS the subscription-enrichment data this collector reads' }
    'azsc/armchild/backupinstances'                = @{ Wired=$true;  Reason='canonical shape line 31: management.recoveryVaults[{backupItems[]}] -- backupItems is this data under the vault' }
    'azsc/governance/budget'                       = @{ Wired=$true;  Reason='canonical shape line 34: governance.budgets[] -- filled by the raw-governance pass' }
    'azsc/management/managementgroup'              = @{ Wired=$true;  Reason='canonical shape line 34: governance.managementGroups[]' }
    'azsc/governance/policyassignment'             = @{ Wired=$true;  Reason='canonical shape line 34: governance.policyAssignments[] -- filled by the raw-governance pass' }
    'azsc/governance/resourcelock'                 = @{ Wired=$true;  Reason='canonical shape line 34: governance.resourceLocks[] -- filled by the raw-governance pass' }
    'azsc/armchild/keyvaultkeys'                   = @{ Wired=$true;  Reason='canonical shape line 48: security.keyVaultKeys[] -- ARM-child sweep, ConvertTo-ScoutKeyVaultChildRow, ~line 1338 (AB#6821)' }
    'azsc/armchild/keyvaultsecrets'                 = @{ Wired=$true;  Reason='canonical shape line 47: security.keyVaultSecrets[] -- ARM-child sweep, ConvertTo-ScoutKeyVaultChildRow, ~line 1338 (AB#6821)' }

    'azsc/armchild/mlcomputes'                     = @{ Wired=$false; Reason='canonical shape documents ai.mlWorkspaces[] only (workspace-level scalars); no mlComputes child key exists in the payload' }
    'azsc/armchild/mldatasets'                     = @{ Wired=$false; Reason='not in the canonical payload shape -- ai.mlWorkspaces[] carries no child datasets key' }
    'azsc/armchild/mldatastores'                   = @{ Wired=$false; Reason='not in the canonical payload shape -- ai.mlWorkspaces[] carries no child datastores key' }
    'azsc/armchild/mlendpoints'                    = @{ Wired=$false; Reason='not in the canonical payload shape -- ai.mlWorkspaces[] carries no child endpoints key' }
    'azsc/armchild/mlmodels'                       = @{ Wired=$false; Reason='not in the canonical payload shape -- ai.mlWorkspaces[] carries no child models key' }
    'azsc/armchild/mlpipelines'                    = @{ Wired=$false; Reason='not in the canonical payload shape -- ai.mlWorkspaces[] carries no child pipelines key' }
    'azsc/armchild/openaideployments'              = @{ Wired=$false; Reason='canonical shape documents ai.cognitiveAccounts[] at the account level only; no deployments child key' }
    'azsc/armchild/searchindexes'                  = @{ Wired=$false; Reason='canonical shape documents ai.searchServices[] at the service level only; no indexes child key' }
    'azsc/armchild/avdapplications'                = @{ Wired=$false; Reason='canonical shape documents compute.avdHostPools/avdSessionHosts/avdScalingPlans only; no avdApplications key' }
    'azsc/avd/azurelocalsessionhost'               = @{ Wired=$false; Reason='canonical shape has compute.avdSessionHosts[] as a generic key; the Azure-Local-hosted variant this collector targets is not separately wired' }
    'azsc/vm/quotas'                               = @{ Wired=$false; Reason='not in the canonical payload shape at all -- quotas are not part of the assessment collect contract' }
    'azsc/armchild/reservationutilization'         = @{ Wired=$false; Reason='canonical shape documents finops.reservations[]/reservationRecommendations[] only; no per-reservation utilization key' }
    'azsc/management/roledefinition'               = @{ Wired=$false; Reason='canonical shape documents governance.roleAssignments[] only; custom role DEFINITIONS (as opposed to assignments) are not wired' }
    'azsc/subscription/securitypolicysweep'        = @{ Wired=$false; Reason='canonical shape documents security.defenderPlans[] only (Get-ScoutDefenderPlanSweep); this legacy subscription-wide sweep type covers 6 manifests (Defender alerts/assessments/pricing/secure-score, policy compliance states, subscription diagnostic settings) and NONE of that additional detail reaches the payload -- only the bare plan list does' }
    'azsc/management/policydefinition'             = @{ Wired=$true; Reason='governance.policyDefinitions[] -- wired AB#7066, reads the AZSC/Management/PolicyDefinition envelope Get-ScoutTenantWideResource already appends, zero extra Azure calls' }
    'azsc/management/policysetdefinition'          = @{ Wired=$true; Reason='governance.policySetDefinitions[] -- wired AB#7066, same source/shape as PolicyDefinitions' }
    'azsc/armchild/appinsightsproactivedetection'  = @{ Wired=$false; Reason='not in the canonical payload shape -- no AppInsights child-detail keys are wired at all' }
    'azsc/armchild/laworkspacelinkedservices'      = @{ Wired=$false; Reason='canonical shape documents management.logAnalyticsWorkspaces[{retentionInDays}] only; no linked-services child key' }
    'azsc/armchild/laworkspacesavedsearches'       = @{ Wired=$false; Reason='canonical shape documents management.logAnalyticsWorkspaces[{retentionInDays}] only; no saved-searches child key' }
    'azsc/monitor/outage'                          = @{ Wired=$false; Reason='not in the canonical payload shape at all -- no outages key is wired' }
    'azsc/armchild/resourcediagnosticsettings'     = @{ Wired=$false; Reason='opsPosture.diagnosticCoverage[] is an aggregate coverage PERCENTAGE only, not per-resource diagnostic settings -- matches AB#7064 exactly' }
    'azsc/armchild/storageblobcontainers'          = @{ Wired=$false; Reason='canonical shape documents domains.storage.storageAccounts[{networkDefaultDeny}] at the account level only; no blob-container child key' }
    'azsc/armchild/storagefileshares'              = @{ Wired=$false; Reason='canonical shape documents storageAccounts[] at the account level only; no file-share child key' }
    'azsc/armchild/storagelifecyclepolicies'       = @{ Wired=$false; Reason='canonical shape documents storageAccounts[] at the account level only; no lifecycle-policy child key' }
}

# ---- 2b. optional: real per-type row counts from a live tenant ----------------------------
$liveCounts = $null
if ($LiveTypeCounts) {
    $liveCountsPath = if (Test-Path -LiteralPath $LiveTypeCounts) { $LiveTypeCounts } else { Join-Path $RepoRoot $LiveTypeCounts }
    $liveRaw = Get-Content -LiteralPath $liveCountsPath -Raw | ConvertFrom-Json
    $liveCounts = @{}
    foreach ($p in $liveRaw.PSObject.Properties) { $liveCounts[$p.Name.ToLowerInvariant()] = [int]$p.Value }
    "Live type counts loaded from '$LiveTypeCounts': $($liveCounts.Count) resource types with >=1 row in $LiveTenantLabel"
}

# ---- 3. walk every collector manifest, extract its ResourceTypes -------------------------
$manifests = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'manifests/collectors') -Recurse -Filter *.psd1 | Sort-Object FullName
"Collector manifests found: $($manifests.Count)"

$rows = foreach ($m in $manifests) {
    $category = Split-Path (Split-Path $m.FullName -Parent) -Leaf
    $raw = Import-PowerShellDataFile -LiteralPath $m.FullName
    $types = @(@($raw.ResourceTypes) | ForEach-Object { $_.ToString().ToLowerInvariant().TrimEnd('/') })

    $hitTypes = @($types | Where-Object { $typeToKeys.ContainsKey($_) })
    $keySet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($ht in $hitTypes) { foreach ($k in $typeToKeys[$ht]) { [void]$keySet.Add($k) } }
    $hitKeys = @(@($keySet) | Sort-Object)

    # AZSC/* is not an ARM resource type at all -- it's this codebase's own marker for a
    # collector that runs an ARM-child sweep (Get-ScoutArmChildResource) or a synthetic
    # subscription-level sweep (e.g. the Defender security-policy walk), neither of which is a
    # `type =~` KQL filter Invoke-Collect.ps1 could ever match. These are resolved from
    # $syntheticVerdicts (hand-checked against Invoke-Collect.ps1's own canonical payload-shape
    # doc), NOT left as an unresolved flag -- every one of the 242 gets a real verdict and reason.
    $nonSyntheticTypes = @($types | Where-Object { -not $_.StartsWith('azsc/') })
    $isSynthetic = ($types.Count -gt 0) -and ($nonSyntheticTypes.Count -eq 0)

    $reason = ''
    $status = if ($isSynthetic) {
        $verdict = $null
        foreach ($t in $types) { if ($syntheticVerdicts.ContainsKey($t)) { $verdict = $syntheticVerdicts[$t]; break } }
        if (-not $verdict) { throw "Synthetic type(s) '$($types -join ', ')' on $category/$($m.BaseName) has no entry in `$syntheticVerdicts -- resolve it by hand and add one; do not let a manifest fall through to an unverdicted state." }
        $reason = $verdict.Reason
        if ($verdict.Wired) { 'WIRED' } else { 'NOT WIRED' }
    }
    elseif ($hitKeys.Count -gt 0) { $reason = "queried via collect key(s): $($hitKeys -join ', ')"; 'WIRED' }
    else { $reason = 'resource type never appears in Invoke-Collect.ps1 -- no collect key, no ARM-child sweep, no synthetic wiring references it'; 'NOT WIRED' }

    $liveRowCount = $null
    if ($liveCounts -and $status -eq 'NOT WIRED') {
        $total = 0
        foreach ($t in $types) { if ($liveCounts.ContainsKey($t)) { $total += $liveCounts[$t] } }
        $liveRowCount = $total
    }

    [pscustomobject]@{
        Category      = $category
        Name          = $m.BaseName
        ResourceTypes = ($types -join '; ')
        Status        = $status
        Reason        = $reason
        CollectKeys   = ($hitKeys -join ', ')
        LiveRows      = $liveRowCount
    }
}

$wired    = @($rows | Where-Object Status -eq 'WIRED')
$notWired = @($rows | Where-Object Status -eq 'NOT WIRED')

"`n=== WIRED -- resource type(s) reach the assessment collect: $($wired.Count) of $($rows.Count) ==="
"=== NOT WIRED -- confirmed gap, with a reason for every one: $($notWired.Count) of $($rows.Count) ==="
if ($liveCounts) {
    $liveConfirmed = @($notWired | Where-Object { $_.LiveRows -gt 0 })
    "=== OF THE NOT-WIRED GAP, CONFIRMED LIVE IN $($LiveTenantLabel.ToUpper()) RIGHT NOW: $($liveConfirmed.Count) of $($notWired.Count) ==="
    $liveConfirmed | Sort-Object -Property @{Expression='LiveRows';Descending=$true} | ForEach-Object {
        "  {0,-14} {1,-40} {2,6} row(s) live in $LiveTenantLabel" -f $_.Category, $_.Name, $_.LiveRows
    }
}
$notWired | ForEach-Object { "  {0,-14} {1,-40} [{2}]" -f $_.Category, $_.Name, $_.ResourceTypes }

if ($OutputPath) {
    $byCat = $notWired | Group-Object Category | Sort-Object Name
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# Collector-to-payload wiring audit (AB#7060)')
    [void]$md.AppendLine()
    [void]$md.AppendLine("Generated by ``scripts/Test-CollectorPayloadCoverage.ps1``. Static cross-reference of every collector manifest's `ResourceTypes` against the resource types Invoke-Collect.ps1 (the assessment collect feeding the React report) actually queries.")
    [void]$md.AppendLine()
    [void]$md.AppendLine("**$($rows.Count) manifests total -- $($wired.Count) WIRED, $($notWired.Count) NOT WIRED. Every manifest carries a verdict and a reason** -- collectors declaring a synthetic `AZSC/*` type (an ARM-child sweep or a subscription-level sweep) are resolved by hand against Invoke-Collect.ps1's own canonical payload-shape documentation (its file header, lines 19-73) rather than left unresolved.")
    [void]$md.AppendLine()
    [void]$md.AppendLine('This answers "is the plumbing there", not "does it return rows in a real tenant" -- see `scripts/Invoke-CorpusCoverage.ps1` for the second question, which only applies once a key is wired.')
    [void]$md.AppendLine()
    if ($liveCounts) {
        $liveConfirmed = @($notWired | Where-Object { $_.LiveRows -gt 0 })
        [void]$md.AppendLine("## Live evidence -- $LiveTenantLabel, $(Get-Date -Format 'yyyy-MM-dd' -Date ([datetime]'2026-08-04'))")
        [void]$md.AppendLine()
        [void]$md.AppendLine("A live Azure Resource Graph query against **$LiveTenantLabel** (2 subscriptions, root-MG Reader) confirms **$($liveConfirmed.Count) of the $($notWired.Count) NOT-WIRED collectors have real, present-today rows** this tenant's estate carries but the React report cannot show, because the resource type is never queried by the assessment collect.")
        [void]$md.AppendLine()
        [void]$md.AppendLine('| Collector | Category | Live rows in ' + $LiveTenantLabel + ' |')
        [void]$md.AppendLine('|---|---|---|')
        foreach ($r in ($liveConfirmed | Sort-Object -Property @{Expression='LiveRows';Descending=$true})) {
            [void]$md.AppendLine("| ``$($r.Name)`` | $($r.Category) | $($r.LiveRows) |")
        }
        [void]$md.AppendLine()
    }
    [void]$md.AppendLine('## Not wired (confirmed gap), by category')
    [void]$md.AppendLine()
    foreach ($g in $byCat) {
        [void]$md.AppendLine("### $($g.Name) ($($g.Count))")
        [void]$md.AppendLine()
        [void]$md.AppendLine('| Collector | Resource types | Reason | Live rows |')
        [void]$md.AppendLine('|---|---|---|---|')
        foreach ($r in ($g.Group | Sort-Object Name)) {
            $liveCell = if ($null -ne $r.LiveRows) { $r.LiveRows } else { '' }
            [void]$md.AppendLine("| ``$($r.Name)`` | ``$($r.ResourceTypes)`` | $($r.Reason) | $liveCell |")
        }
        [void]$md.AppendLine()
    }

    [void]$md.AppendLine('## Wired via a synthetic type (ARM-child sweep or subscription-wide sweep), by category')
    [void]$md.AppendLine()
    $wiredSynthetic = @($wired | Where-Object { $_.ResourceTypes -match '^azsc/' })
    $byCatWiredSynthetic = $wiredSynthetic | Group-Object Category | Sort-Object Name
    foreach ($g in $byCatWiredSynthetic) {
        [void]$md.AppendLine("### $($g.Name) ($($g.Count))")
        [void]$md.AppendLine()
        [void]$md.AppendLine('| Collector | Synthetic type | Reason |')
        [void]$md.AppendLine('|---|---|---|')
        foreach ($r in ($g.Group | Sort-Object Name)) {
            [void]$md.AppendLine("| ``$($r.Name)`` | ``$($r.ResourceTypes)`` | $($r.Reason) |")
        }
        [void]$md.AppendLine()
    }
    Set-Content -LiteralPath (Join-Path $RepoRoot $OutputPath) -Value $md.ToString() -Encoding utf8
    "`nWritten: $OutputPath"
}

return $rows
