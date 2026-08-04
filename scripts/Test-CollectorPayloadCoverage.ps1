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
    # `type =~` KQL filter Invoke-Collect.ps1 could ever match. A manifest built that way is
    # NEITHER wired nor not-wired by this check -- it is simply unanswerable by this method, and
    # reporting it as NOT WIRED would be a false claim of a gap that may not exist.
    $nonSyntheticTypes = @($types | Where-Object { -not $_.StartsWith('azsc/') })
    $isSynthetic = ($types.Count -gt 0) -and ($nonSyntheticTypes.Count -eq 0)

    $status = if ($isSynthetic) { 'NEEDS MANUAL CHECK (synthetic type)' }
              elseif ($hitKeys.Count -gt 0) { 'WIRED' } else { 'NOT WIRED' }

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
        CollectKeys   = ($hitKeys -join ', ')
        LiveRows      = $liveRowCount
    }
}

$wired     = @($rows | Where-Object Status -eq 'WIRED')
$notWired  = @($rows | Where-Object Status -eq 'NOT WIRED')
$synthetic = @($rows | Where-Object Status -like 'NEEDS MANUAL CHECK*')

"`n=== WIRED -- resource type(s) queried in Invoke-Collect.ps1: $($wired.Count) of $($rows.Count) ==="
"=== NOT WIRED (confirmed gap, real ARM type absent from the assessment collect): $($notWired.Count) of $($rows.Count) ==="
"=== NEEDS MANUAL CHECK -- synthetic AZSC/* type, this method cannot answer: $($synthetic.Count) of $($rows.Count) ==="
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
    [void]$md.AppendLine("**$($rows.Count) manifests total -- $($wired.Count) WIRED, $($notWired.Count) NOT WIRED (confirmed), $($synthetic.Count) NEEDS MANUAL CHECK.**")
    [void]$md.AppendLine()
    [void]$md.AppendLine('This answers "is the plumbing there", not "does it return rows in a real tenant" -- see `scripts/Invoke-CorpusCoverage.ps1` for the second question, which only applies once a key is wired.')
    [void]$md.AppendLine()
    [void]$md.AppendLine('**NEEDS MANUAL CHECK** collectors declare a synthetic `AZSC/*` type (an ARM-child sweep via `Get-ScoutArmChildResource`, or a subscription-level sweep like the Defender security-policy walk) rather than a real ARM resource type. Neither is a `type =~` KQL filter, so this static method cannot determine whether they reach the payload through some other path -- do not read these as confirmed gaps.')
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
        [void]$md.AppendLine('| Collector | Resource types | Live rows |')
        [void]$md.AppendLine('|---|---|---|')
        foreach ($r in ($g.Group | Sort-Object Name)) {
            $liveCell = if ($null -ne $r.LiveRows) { $r.LiveRows } else { '' }
            [void]$md.AppendLine("| ``$($r.Name)`` | ``$($r.ResourceTypes)`` | $liveCell |")
        }
        [void]$md.AppendLine()
    }

    [void]$md.AppendLine('## Needs manual check (synthetic type), by category')
    [void]$md.AppendLine()
    $byCatSynthetic = $synthetic | Group-Object Category | Sort-Object Name
    foreach ($g in $byCatSynthetic) {
        [void]$md.AppendLine("### $($g.Name) ($($g.Count))")
        [void]$md.AppendLine()
        [void]$md.AppendLine('| Collector | Synthetic type |')
        [void]$md.AppendLine('|---|---|')
        foreach ($r in ($g.Group | Sort-Object Name)) {
            [void]$md.AppendLine("| ``$($r.Name)`` | ``$($r.ResourceTypes)`` |")
        }
        [void]$md.AppendLine()
    }
    Set-Content -LiteralPath (Join-Path $RepoRoot $OutputPath) -Value $md.ToString() -Encoding utf8
    "`nWritten: $OutputPath"
}

return $rows
