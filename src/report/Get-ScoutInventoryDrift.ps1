#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Compute cross-run RESOURCE/inventory drift (Added/Removed/Changed) between
    the current collect.json and the immediately previous run, and append the
    current run's inventory snapshot to a durable inventory-history log.

.DESCRIPTION
    Get-ScoutDrift (src/report/Get-ScoutDrift.ps1) tracks FINDINGS drift — the
    scored Pass/Fail/Manual state of each rule across runs. This function
    fills the adjacent gap: RESOURCE drift — what actually changed in the
    collected Azure estate itself between two runs, independent of how any
    rule scored it.

    Given the canonical collect.json shape Invoke-Collect produces (a nested
    object of arrays of resource rows — networking.virtualNetworks,
    compute.virtualMachines, domains.storage.storageAccounts, etc.), this
    function:

      1. Walks -Collect recursively, treating every array found anywhere in
         the tree as a collection of resource rows, and every object in that
         array as one resource. The dotted property path to that array (e.g.
         'domains.storage.storageAccounts') is recorded alongside each
         resource so callers can group/label drift by resource type.
      2. Builds a STABLE resource id for each resource from an ordered list
         of recognized identity-ish field names (id, name, vnet, subnet, nsg,
         rule, machineId, policyName, type, key) plus scope fields
         (resourceGroup, subscriptionId) — whichever of those are actually
         present on the resource, joined together and prefixed with its
         array path. This deliberately does NOT depend on Azure Resource
         Graph exposing a full ARM `id` (most collect.json queries project
         only name/resourceGroup/subscriptionId + scalar fields, no `id`).
         A resource with none of those recognized fields falls back to a
         SHA-256 hash of its full, name-sorted property set, so it still
         gets a deterministic id rather than being silently dropped — the
         tradeoff being that such a resource's id changes if ANY of its
         fields change (it will show as Removed+Added instead of Changed).
         Duplicate ids within the same run (two resources whose recognized
         identity fields collide) are disambiguated with a `#2`, `#3`, ...
         suffix in encounter order, so no resource is ever silently dropped.
      3. Compares the current run's resource-id set against the previous
         run's persisted snapshot:
           Added     - id present now, absent from the previous run
           Removed   - id present in the previous run, absent now
           Changed   - id present in both, but one or more field values
                       differ (every property name from either side is
                       compared; each differing field is reported as
                       {Field, PreviousValue, CurrentValue})
           Unchanged - id present in both with no field differences
         (rolled into Summary as a count only — not enumerated, since an
         unchanged resource carries no new information for a drift report).
      4. Appends/replaces the current run's snapshot in the history file (a
         rerun with the same -RunId overwrites its own prior record rather
         than duplicating it) — same replace-on-rerun contract Get-ScoutDrift
         uses for findings-history.json.

    On the first-ever run for a given -HistoryPath (no usable prior
    snapshot), returns an explicit baseline result — IsBaseline = $true,
    Added/Removed/Changed all empty, Summary counts all zero except
    TotalCurrent — rather than treating every resource as "Added". A brand
    new inventory has nothing to have drifted from; it establishes the
    baseline the NEXT run will be compared against.

.PARAMETER Collect
    The canonical collect object (Invoke-Collect's output, or the parsed
    contents of a run's collect.json) to compute inventory drift for.

.PARAMETER HistoryPath
    Folder the inventory-history.json log lives in. Created if missing.
    Defaults to a .scout-history folder under the current location if not
    supplied — callers should normally pass the SAME -HistoryPath they pass
    to Get-ScoutDrift (e.g. a .scout-history folder under the assessment's
    -OutputPath root) so findings-history.json and inventory-history.json
    live side by side for one run tree.

.PARAMETER RunId
    The caller-supplied run identifier stamped onto this run's inventory
    snapshot. Required — drift has no meaning without a stable, caller-
    controlled id to compare across.

.OUTPUTS
    [pscustomobject] with RunId/GeneratedOn/IsBaseline/PreviousRunId/Summary/
    Added/Removed/Changed — see tests/Report.InventoryDrift.Tests.ps1 for the
    exact shape exercised.

.NOTES
    Tracks ADO Story AB#326.
#>
function Get-ScoutInventoryDrift {
    param(
        $Collect,
        [string] $HistoryPath,
        [string] $RunId
    )

    if ($null -eq $Collect) {
        throw 'Get-ScoutInventoryDrift: -Collect is required.'
    }
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw 'Get-ScoutInventoryDrift: -RunId is required (pass the caller-controlled run id, e.g. the assessment run-folder name).'
    }
    if ([string]::IsNullOrWhiteSpace($HistoryPath)) {
        $HistoryPath = Join-Path -Path (Get-Location) -ChildPath 'output' -AdditionalChildPath '.scout-history'
    }

    if (-not (Test-Path $HistoryPath)) {
        New-Item -ItemType Directory -Path $HistoryPath -Force | Out-Null
    }
    $historyFile = Join-Path $HistoryPath 'inventory-history.json'

    function Get-InvProp {
        param($Obj, [string] $Name)
        if ($null -eq $Obj) { return $null }
        if ($Obj -isnot [System.Management.Automation.PSCustomObject]) { return $null }
        $p = $Obj.PSObject.Properties[$Name]
        if ($p) { return $p.Value } else { return $null }
    }

    # ---- recursively flatten -Collect into (Path, Resource) entries ------
    # Every array found anywhere in the tree is treated as a resource
    # collection; every PSCustomObject inside it is one resource. Plain
    # objects (not arrays) are descended into by property name to build the
    # dotted path. `_meta` is skipped — it's run metadata (generatedOn,
    # scope, categories), never inventory.
    function Get-InventoryResourceEntry {
        param($Node, [string] $Path)
        $result = [System.Collections.Generic.List[pscustomobject]]::new()
        if ($null -eq $Node) { return $result }

        if ($Node -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $Node.PSObject.Properties) {
                if ($prop.Name -eq '_meta') { continue }
                $childPath = if ($Path) { "$Path.$($prop.Name)" } else { $prop.Name }
                foreach ($sub in (Get-InventoryResourceEntry -Node $prop.Value -Path $childPath)) { $result.Add($sub) }
            }
            return $result
        }

        if ($Node -is [string]) { return $result }

        if ($Node -is [System.Collections.IEnumerable]) {
            foreach ($item in $Node) {
                if ($null -eq $item) { continue }
                if ($item -is [string]) { continue }
                if ($item -is [System.Management.Automation.PSCustomObject]) {
                    $result.Add([pscustomobject]@{ Path = $Path; Resource = $item })
                    continue
                }
                if ($item -is [System.Collections.IEnumerable]) {
                    # Defensive: a stray nested array-of-arrays — flatten under the same path.
                    foreach ($sub in (Get-InventoryResourceEntry -Node $item -Path $Path)) { $result.Add($sub) }
                    continue
                }
                # Scalar row with no object shape (e.g. a stray empty-string
                # placeholder row) — nothing to key or diff, skip it.
            }
            return $result
        }

        return $result
    }

    # ---- stable resource id: recognized identity fields, else content hash ----
    $script:idFieldOrder = @('id', 'name', 'vnet', 'subnet', 'nsg', 'rule', 'machineId', 'policyName', 'type', 'key')
    $script:scopeFieldOrder = @('resourceGroup', 'subscriptionId')

    function Get-InventoryResourceId {
        param([string] $Path, $Resource)
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $script:idFieldOrder) {
            $v = Get-InvProp $Resource $f
            if (-not [string]::IsNullOrEmpty([string]$v)) { $parts.Add("$f=$v") }
        }
        foreach ($f in $script:scopeFieldOrder) {
            $v = Get-InvProp $Resource $f
            if (-not [string]::IsNullOrEmpty([string]$v)) { $parts.Add("$f=$v") }
        }
        if ($parts.Count -eq 0) {
            # No recognized identity field at all — fall back to a deterministic
            # hash of the full, name-sorted property set so the resource still
            # gets a stable id instead of being silently dropped.
            $sortedJson = (
                $Resource.PSObject.Properties | Sort-Object Name | ForEach-Object {
                    "$($_.Name)=$($_.Value | ConvertTo-Json -Compress -Depth 100)"
                }
            ) -join '|'
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sortedJson))
            }
            finally {
                $sha256.Dispose()
            }
            $hash = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
            $parts.Add("hash=$hash")
        }
        return "$Path::$($parts -join '|')"
    }

    # ---- build the current run's id -> {Path, Fields} map ------------------
    $currentEntries = Get-InventoryResourceEntry -Node $Collect -Path ''
    $currentMap = [ordered]@{}
    $idSeenCount = @{}
    foreach ($entry in $currentEntries) {
        $baseId = Get-InventoryResourceId -Path $entry.Path -Resource $entry.Resource
        if ($idSeenCount.ContainsKey($baseId)) {
            $idSeenCount[$baseId]++
            $id = "$baseId#$($idSeenCount[$baseId])"
        }
        else {
            $idSeenCount[$baseId] = 1
            $id = $baseId
        }
        $currentMap[$id] = [pscustomobject]@{ Path = $entry.Path; Fields = $entry.Resource }
    }

    # ---- read prior history (tolerant: missing/corrupt => baseline, never throw) ----
    $history = @()
    if (Test-Path $historyFile) {
        try {
            $raw = Get-Content $historyFile -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                if ($null -ne $parsed) { $history = @($parsed) }
            }
        }
        catch {
            # Malformed/corrupt history file — treat as "no history" (baseline).
            $history = @()
        }
    }

    $priorCandidates = @($history | Where-Object { (Get-InvProp $_ 'RunId') -ne $RunId })
    $previous = if ($priorCandidates.Count -gt 0) { $priorCandidates[-1] } else { $null }
    $isBaseline = ($null -eq $previous)

    $previousMap = [ordered]@{}
    if (-not $isBaseline) {
        $previousResources = Get-InvProp $previous 'Resources'
        if ($null -ne $previousResources) {
            foreach ($prop in $previousResources.PSObject.Properties) {
                $previousMap[$prop.Name] = $prop.Value
            }
        }
    }

    # ---- field-level diff between a previous and current resource's Fields ----
    function Get-InventoryFieldChange {
        param($PreviousFields, $CurrentFields)
        $changes = [System.Collections.Generic.List[pscustomobject]]::new()
        $names = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $PreviousFields -and $PreviousFields -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $PreviousFields.PSObject.Properties) { if (-not $names.Contains($p.Name)) { $names.Add($p.Name) } }
        }
        if ($null -ne $CurrentFields -and $CurrentFields -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $CurrentFields.PSObject.Properties) { if (-not $names.Contains($p.Name)) { $names.Add($p.Name) } }
        }
        foreach ($name in ($names | Sort-Object)) {
            $prevVal = Get-InvProp $PreviousFields $name
            $currVal = Get-InvProp $CurrentFields $name
            $prevJson = $prevVal | ConvertTo-Json -Compress -Depth 100
            $currJson = $currVal | ConvertTo-Json -Compress -Depth 100
            if ($prevJson -ne $currJson) {
                $changes.Add([pscustomobject]@{
                    Field         = $name
                    PreviousValue = $prevVal
                    CurrentValue  = $currVal
                })
            }
        }
        return $changes
    }

    # ---- classify: Added / Removed / Changed / Unchanged -------------------
    $added = [System.Collections.Generic.List[object]]::new()
    $removed = [System.Collections.Generic.List[object]]::new()
    $changed = [System.Collections.Generic.List[object]]::new()
    $unchangedCount = 0

    if ($isBaseline) {
        # First-ever run for this history: nothing to have drifted from.
        # Persist the snapshot as the baseline the NEXT run compares against,
        # but report no Added/Removed/Changed — a baseline is not drift.
    }
    else {
        foreach ($id in $currentMap.Keys) {
            $curr = $currentMap[$id]
            if (-not $previousMap.Contains($id)) {
                $added.Add([pscustomobject]@{ Id = $id; Path = $curr.Path; Fields = $curr.Fields })
                continue
            }
            $prevEntry = $previousMap[$id]
            $prevFields = Get-InvProp $prevEntry 'Fields'
            # @() forces an array even when Get-InventoryFieldChange returns zero or
            # one item — PowerShell unrolls a function's List[T] "return" onto the
            # pipeline, so an unwrapped assignment would collapse an empty list to
            # $null (breaking .Count below) or a single-item list to a bare scalar.
            $fieldChanges = @(Get-InventoryFieldChange -PreviousFields $prevFields -CurrentFields $curr.Fields)
            if ($fieldChanges.Count -gt 0) {
                $changed.Add([pscustomobject]@{ Id = $id; Path = $curr.Path; Changes = @($fieldChanges) })
            }
            else {
                $unchangedCount++
            }
        }

        foreach ($id in $previousMap.Keys) {
            if (-not $currentMap.Contains($id)) {
                $prevEntry = $previousMap[$id]
                $removed.Add([pscustomobject]@{ Id = $id; Path = (Get-InvProp $prevEntry 'Path'); Fields = (Get-InvProp $prevEntry 'Fields') })
            }
        }
    }

    $result = [pscustomobject]@{
        RunId         = $RunId
        GeneratedOn   = (Get-Date).ToString('o')
        IsBaseline    = $isBaseline
        PreviousRunId = if ($isBaseline) { $null } else { Get-InvProp $previous 'RunId' }
        Summary       = [pscustomobject]@{
            Added         = $added.Count
            Removed       = $removed.Count
            Changed       = $changed.Count
            Unchanged     = $unchangedCount
            TotalCurrent  = $currentMap.Count
            TotalPrevious = if ($isBaseline) { 0 } else { $previousMap.Count }
        }
        Added         = @($added | Sort-Object Path, Id)
        Removed       = @($removed | Sort-Object Path, Id)
        Changed       = @($changed | Sort-Object Path, Id)
    }

    # ---- persist this run's snapshot (replace-on-rerun, else append) ------
    $resourcesForStorage = [ordered]@{}
    foreach ($id in $currentMap.Keys) {
        $resourcesForStorage[$id] = [pscustomobject]@{ Path = $currentMap[$id].Path; Fields = $currentMap[$id].Fields }
    }
    $newRecord = [pscustomobject]@{
        RunId     = $RunId
        Timestamp = (Get-Date).ToString('o')
        Resources = [pscustomobject]$resourcesForStorage
    }
    $updatedHistory = @($history | Where-Object { (Get-InvProp $_ 'RunId') -ne $RunId }) + $newRecord
    $updatedHistory | ConvertTo-Json -Depth 100 | Out-File $historyFile -Encoding utf8

    return $result
}
