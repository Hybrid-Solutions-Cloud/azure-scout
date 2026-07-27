#Requires -Version 7.0
<#
.SYNOPSIS
    Rewrites work-item descriptions and adds Predecessor/Successor links on the Azure Scout ADO board.

.DESCRIPTION
    scripts/New-BoardTree.ps1 creates a conformant tree, but it only ever writes an item once. The
    two things it cannot do are the two things the HCS work-items standard asks for after creation:

      1. Bring an existing description into the standard's template -- problem, "Why now:", an
         "In scope:" list and an "Out of scope:" list, both as real <ul><li> lists rather than
         prose. A description written as a paragraph renders as a paragraph forever; nothing on
         the board rewrites it.
      2. LINK dependencies rather than describe them. "X has to land before Y" written in prose is
         invisible to a query, to the Dependency Tracker, and to whoever picks the work up cold.

    This script does both from a declarative data file, for the same reason New-BoardTree.ps1 takes
    one: board writes made from throwaway scratch scripts are not reviewable, not re-runnable and
    not subject to the repo's standards. Run scripts/Test-BoardConformance.ps1 afterwards -- the
    one time that was skipped it left 15 violations on the board.

    Both operations are idempotent. A description is skipped when the board already holds exactly
    the string in the data file, and a link is skipped when a relation of the same type already
    points at the same target. Re-running after a partial failure is therefore safe.

    Nothing is written until every item in the file has been fetched and checked, because a
    half-applied set of dependency links is a worse artefact than none: it reads as a complete
    ordering while omitting edges.

    Traps this script encodes so callers do not rediscover them:

    - The dependency link direction is easy to invert and silently wrong when you do.
      System.LinkTypes.Dependency-FORWARD names the SUCCESSOR: added to A with a url pointing at
      B it means "B comes after A", i.e. A must finish first. -Reverse names the PREDECESSOR. This
      script therefore takes 'Precedes' and emits Forward, and -Verify reads the mirror back off
      the target to prove the direction rather than assuming it.
    - The server creates the mirror relation itself. Writing both ends is a 400 (the second write
      is a duplicate link), so only one end is ever sent.
    - The relation URL segment must be camel-cased 'workItems'. A lower-case 'workitems' is
      accepted on write but scripts/Test-BoardConformance.ps1's regex is case-sensitive and will
      not see it.
    - ConvertTo-Json defaults to -Depth 2, which flattens a relation's nested attributes into the
      string "System.Collections.Hashtable". Every serialisation here passes -Depth 6.
    - ConvertTo-Json on a single-element array emits an object; the patch endpoint requires an
      array. Every body is wrapped with @( ).
    - System.Description with op=add APPENDS nothing but is semantically a create; use op=replace
      so an existing description is actually overwritten.
    - $pid is a read-only automatic variable (the process id), and PowerShell names are
      case-insensitive, so $pId IS $PID. Never name a work-item id that.
    - Run this as a FILE, never as an inline `pwsh -Command`. A backtick in an ADO URL breaks bash
      quoting and the request silently goes somewhere else.

.PARAMETER Path
    Path to a PowerShell data file (.psd1) holding a single hashtable with an Items key. Each entry
    supports:

      Id           (required) the work-item id to update
      Description  HTML replacing System.Description. Omit to leave the description alone
      Precedes     ids of work items that must not start until this one completes. Emitted as
                   System.LinkTypes.Dependency-Forward (Successor) relations on THIS item

    A data file is used rather than a script so loading the detail cannot execute code.

.PARAMETER Organization
    Azure DevOps organization URL.

.PARAMETER ProjectId
    Azure DevOps project GUID. The GUID is used rather than the name because the project name
    contains an em-dash that Windows console encoding mangles, which silently writes to the wrong
    project.

.PARAMETER Verify
    After writing, re-read every touched item and print its rendered description and every
    dependency relation on it, resolving each relation to the human link name ("Successor" /
    "Predecessor") from the link-types API. Use this to confirm the result rather than assume it.

.EXAMPLE
    ./scripts/Update-BoardItemDetail.ps1 -Path ./scripts/trees/v3-engine-completion-detail.psd1 -WhatIf

    Fetches every item, reports which descriptions and links would change, and writes nothing.

.EXAMPLE
    ./scripts/Update-BoardItemDetail.ps1 -Path ./scripts/trees/v3-engine-completion-detail.psd1 -Verify

    Applies the file, then reads every touched item back and prints what the board now holds.

.NOTES
    Requires an authenticated Azure CLI session (az login). Reads no secrets from the repo and
    writes none to it. Run scripts/Test-BoardConformance.ps1 immediately afterwards.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [string] $Organization = 'https://dev.azure.com/hybridcloudsolutions',

    # Scout project GUID. Using the GUID avoids the U+2014 em-dash in the project name, which
    # console encoding mangles into a write against the wrong project.
    [string] $ProjectId = '85b6e47e-a666-4a38-8c43-de87dd21aa56',

    [switch] $Verify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The dependency pair. Forward is the SUCCESSOR end: on item A pointing at B it asserts B follows
# A. 'Precedes' in the data file therefore maps to Forward, and the mirror the server writes on B
# is the Reverse (Predecessor) end.
$DependencyForward = 'System.LinkTypes.Dependency-Forward'
$DependencyReverse = 'System.LinkTypes.Dependency-Reverse'

function Get-EntryValue {
    # Hashtable member access under StrictMode is inconsistent enough to be worth avoiding.
    param($Entry, [string] $Name)
    if ($Entry.Contains($Name)) { return $Entry[$Name] }
    return $null
}

function Get-PrecedesId {
    # NOT `@(Get-EntryValue $Entry 'Precedes')`. On a missing key that yields @($null) -- a
    # ONE-element array holding $null -- and [int]$null is 0, which reaches the batch endpoint as
    # work item 0 and fails the whole run with "The value 0 is outside of the allowed range".
    param($Entry)
    return @(Get-EntryValue $Entry 'Precedes' | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
}

# --------------------------------------------------------------------------------------------
# Load and pre-flight the data file. Nothing is fetched until the file itself is coherent.
# --------------------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Path)) { throw "Detail file not found: $Path" }
$data = Import-PowerShellDataFile -LiteralPath $Path
if (-not $data.Contains('Items')) { throw "$Path must contain a hashtable with an Items key." }
$entries = @($data['Items'])
if (-not $entries) { throw 'The Items collection is empty.' }

$errs  = [System.Collections.Generic.List[string]]::new()
$seen  = @{}
foreach ($e in $entries) {
    if ($e -isnot [System.Collections.IDictionary]) { $errs.Add('Every entry must be a hashtable.'); continue }
    $id = Get-EntryValue $e 'Id'
    if (-not $id)               { $errs.Add('An entry has no Id.'); continue }
    if ($seen.ContainsKey($id)) { $errs.Add("Duplicate Id $id in the data file."); continue }
    $seen[[int]$id] = $true

    $desc = Get-EntryValue $e 'Description'
    $prec = Get-PrecedesId -Entry $e
    if (-not $desc -and -not $prec) { $errs.Add("AB#$id : neither Description nor Precedes is set; the entry does nothing.") }

    foreach ($p in $prec) {
        if ([int]$p -eq [int]$id) { $errs.Add("AB#$id : cannot precede itself.") }
    }
}
if ($errs.Count -gt 0) {
    $errs | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($errs.Count) pre-flight failure(s) in the data file. Nothing was fetched or written."
}

# --------------------------------------------------------------------------------------------
# Token and headers
# --------------------------------------------------------------------------------------------
# 499b84ac-1321-427f-aa17-267ca6975798 is the well-known Azure DevOps resource id.
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
if (-not $token) { throw 'Could not get an Azure DevOps access token. Run: az login' }

$patchHeaders = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json-patch+json' }
$jsonHeaders  = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

$org  = $Organization
$proj = $ProjectId

# --------------------------------------------------------------------------------------------
# Fetch current state for every item mentioned, as an id OR as a link target. A Precedes target
# that is not on the board would create a dangling relation, so it is checked before any write.
# --------------------------------------------------------------------------------------------
function Get-ItemState {
    param([int[]] $Ids)
    $result = @{}
    $unique = @($Ids | Sort-Object -Unique)
    for ($i = 0; $i -lt $unique.Count; $i += 100) {
        $chunk = $unique[$i..([Math]::Min($i + 99, $unique.Count - 1))]
        $body  = @{ ids = $chunk; '$expand' = 'Relations' } | ConvertTo-Json -Depth 6
        $batch = (Invoke-RestMethod -Uri "$org/$proj/_apis/wit/workitemsbatch?api-version=7.0" -Method POST -Headers $jsonHeaders -Body $body).value
        foreach ($w in $batch) { $result[[int]$w.id] = $w }
    }
    return $result
}

$allIds = [System.Collections.Generic.List[int]]::new()
foreach ($e in $entries) {
    $allIds.Add([int](Get-EntryValue $e 'Id'))
    foreach ($p in (Get-PrecedesId -Entry $e)) { $allIds.Add($p) }
}
$state = Get-ItemState -Ids $allIds.ToArray()

foreach ($wanted in @($allIds | Sort-Object -Unique)) {
    if (-not $state.ContainsKey($wanted)) { $errs.Add("AB#$wanted is referenced by the data file but is not on this board.") }
}
if ($errs.Count -gt 0) {
    $errs | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($errs.Count) pre-flight failure(s) against the live board. Nothing was written."
}

function Get-Relation {
    # $expand=Relations omits the property entirely on an item with no relations, which under
    # StrictMode is a terminating error rather than $null.
    param($Item)
    if ($Item.PSObject.Properties.Name -contains 'relations' -and $Item.relations) { return @($Item.relations) }
    return @()
}

function Get-RelationTargetId {
    param($Relation)
    if ($Relation.url -match '/workItems/(\d+)$') { return [int]$Matches[1] }
    return $null
}

Write-Host ("Loaded        : {0} entr(ies) from {1}" -f $entries.Count, (Split-Path -Leaf $Path))
Write-Host ("Board         : {0} item(s) fetched with relations" -f $state.Count)
Write-Host ''

# --------------------------------------------------------------------------------------------
# Apply
# --------------------------------------------------------------------------------------------
$descChanged = 0
$descSame    = 0
$linkAdded   = 0
$linkSame    = 0
$touched     = [System.Collections.Generic.List[int]]::new()

foreach ($e in $entries) {
    $id   = [int](Get-EntryValue $e 'Id')
    $item = $state[$id]
    $ops  = [System.Collections.Generic.List[object]]::new()
    $what = [System.Collections.Generic.List[string]]::new()

    $desc = Get-EntryValue $e 'Description'
    if ($desc) {
        $current = $null
        if ($item.fields.PSObject.Properties.Name -contains 'System.Description') { $current = $item.fields.'System.Description' }
        if ($current -ceq $desc) {
            $descSame++
        }
        else {
            # op=replace, not add: op=add on a field that already has a value is accepted but is
            # semantically a create, and the intent here is explicitly to overwrite.
            $ops.Add(@{ op = 'replace'; path = '/fields/System.Description'; value = $desc })
            $what.Add('description')
        }
    }

    $existing = @()
    foreach ($r in (Get-Relation -Item $item)) {
        if ($r.rel -ne $DependencyForward -and $r.rel -ne $DependencyReverse) { continue }
        $target = Get-RelationTargetId -Relation $r
        if ($null -ne $target) { $existing += ('{0}:{1}' -f $r.rel, $target) }
    }

    foreach ($p in (Get-PrecedesId -Entry $e)) {
        $target = [int]$p
        if ($existing -contains ('{0}:{1}' -f $DependencyForward, $target)) { $linkSame++; continue }
        # Only ONE end is ever written. The server creates the mirror Dependency-Reverse relation
        # on the target itself; sending both ends is a 400 on the second write.
        # The -f argument list is parenthesised: inside a hashtable literal its commas would
        # otherwise be read as entry separators and the script would not parse.
        $ops.Add(@{ op = 'add'; path = '/relations/-'; value = @{
            rel        = $DependencyForward
            url        = ('{0}/{1}/_apis/wit/workItems/{2}' -f $org, $proj, $target)
            attributes = @{ comment = 'Predecessor of this item; it must complete first.' }
        } })
        $what.Add("precedes AB#$target")
        $linkAdded++
    }

    if ($ops.Count -eq 0) {
        '{0,-8} SKIP   nothing to change' -f "AB#$id"
        continue
    }

    $target = "AB#$id ($($what -join ', '))"
    if (-not $PSCmdlet.ShouldProcess($target, 'patch work item')) {
        '{0,-8} WHATIF {1}' -f "AB#$id", ($what -join ', ')
        continue
    }

    $uri  = '{0}/{1}/_apis/wit/workitems/{2}?api-version=7.0' -f $org, $proj, $id
    $body = ConvertTo-Json @($ops.ToArray()) -Depth 6   # -Depth 6 or the relation attributes flatten
    $null = Invoke-RestMethod -Uri $uri -Method PATCH -Headers $patchHeaders -Body $body

    if ($what -contains 'description') { $descChanged++ }
    $touched.Add($id)
    '{0,-8} OK     {1}' -f "AB#$id", ($what -join ', ')
}

Write-Host ''
Write-Host ("Descriptions  : {0} rewritten, {1} already identical" -f $descChanged, $descSame)
Write-Host ("Dependencies  : {0} added, {1} already present" -f $linkAdded, $linkSame)

# --------------------------------------------------------------------------------------------
# Verify. Reads the board back rather than trusting the write, and resolves each relation to its
# human link name so an inverted dependency is visible instead of inferred.
# --------------------------------------------------------------------------------------------
if ($Verify -and $touched.Count -gt 0) {
    Write-Host ''
    Write-Host '--- VERIFY (re-read from the API) ---'

    $linkNames = @{}
    foreach ($t in (Invoke-RestMethod -Uri "$org/_apis/wit/workitemrelationtypes?api-version=7.0" -Method Get -Headers $jsonHeaders).value) {
        $linkNames[$t.referenceName] = $t.name
    }

    $after = Get-ItemState -Ids $touched.ToArray()
    foreach ($id in $touched) {
        $w = $after[$id]
        Write-Host ''
        Write-Host ("===== AB#{0} [{1}] {2}" -f $id, $w.fields.'System.WorkItemType', $w.fields.'System.Title')
        if ($w.fields.PSObject.Properties.Name -contains 'System.Description') { $w.fields.'System.Description' }
        foreach ($r in (Get-Relation -Item $w)) {
            if ($r.rel -ne $DependencyForward -and $r.rel -ne $DependencyReverse) { continue }
            $name = if ($linkNames.ContainsKey($r.rel)) { $linkNames[$r.rel] } else { $r.rel }
            Write-Host ("  LINK  {0,-12} -> AB#{1}" -f $name, (Get-RelationTargetId -Relation $r))
        }
    }
}

Write-Host ''
Write-Host 'Now run: ./scripts/Test-BoardConformance.ps1' -ForegroundColor Yellow
