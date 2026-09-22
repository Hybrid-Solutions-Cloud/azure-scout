#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a conformant Epic > Feature > User Story > Task tree on the Azure Scout ADO board.

.DESCRIPTION
    Board writes used to be made from throwaway scripts in a scratch directory, which meant the
    writes actually applied were not reviewable, not re-runnable, and not subject to the repo's
    standards. This script exists so item creation is committed code, alongside
    scripts/Set-BoardState.ps1 and scripts/Test-BoardConformance.ps1.

    ALWAYS run scripts/Test-BoardConformance.ps1 afterwards. Skipping it once left 15 violations
    on the board.

    The tree is declarative and is supplied by the caller, either inline via -Tree or from a
    PowerShell data file via -Path. Nodes refer to each other by a local 'Key' handle, never by
    work-item id: ids are assigned by the server and are unpredictable, and guessing them has
    produced wrong references on this board more than once.

    Before a single write, every node is checked against the same eleven rules
    scripts/Test-BoardConformance.ps1 enforces. Any failure aborts the whole run, because a
    half-created tree is harder to clean up than no tree at all. Re-running is safe: a node whose
    exact title already exists on the board is skipped, and its existing id is used to parent its
    children.

    Traps this script encodes so callers do not rediscover them:

    - The project name contains U+2014 EM DASH. Typing it into a script and letting it pass
      through console or pipe encoding yields TF401347 Invalid tree name. Area and iteration
      paths are therefore built in-process from the classification-nodes API response, and if the
      round-tripped root name looks mangled the classification fields are omitted entirely
      (they then default to the project root, which is one segment and still conformant).
    - The parent link is a relation, not the read-only System.Parent field, and the relation URL
      segment must be camel-cased 'workItems'. The conformance audit's regex is case-sensitive,
      so 'workitems' makes the parent invisible and reports "has no parent".
    - Acceptance Criteria are counted by matching the literal lowercase '<li'. Plain text, <div>
      or <p> score zero even though the web UI renders them. This script emits <ul><li>.
    - ConvertTo-Json defaults to -Depth 2, which flattens a relation's nested attributes into
      "System.Collections.Hashtable". Every serialisation here passes -Depth 6.
    - ConvertTo-Json on a single-element array emits an object; the patch endpoint requires an
      array. Every body is wrapped with @( ).
    - Task has no Microsoft.VSTS.Common.ValueArea field. Sending it is a 400.
    - A work item cannot be CREATED in Resolved or Closed. Everything here is created in New.
      Use scripts/Set-BoardState.ps1 afterwards to move states; it handles the types that refuse
      a direct New -> Closed jump.
    - System.Tags with op=add APPENDS on an existing item. On a create there is no prior value so
      op=add is correct; if you later change tags, use op=replace with the complete
      semicolon-joined string.
    - $pid is a read-only automatic variable (the process id). Never use it for a project id.
    - An ordered dictionary with integer keys indexes by POSITION, not key. Iterate with
      .GetEnumerator(); this script keys every lookup by string.

.PARAMETER Tree
    An array of node hashtables. Each node supports:

      Key                 (required) local handle, unique within the tree
      Type                (required) Epic | Feature | User Story | Task | Bug
      Title               (required) must start with a capitalised verb, <= 120 chars
      Description         (required) HTML; what the problem is, why now, in and out of scope
      Priority            (required) 1-4
      Tags                (required) semicolon-joined string or string array, approved vocabulary
      AcceptanceCriteria  string array, one testable statement per element.
                          Minimum 3 for Epic, Feature and User Story; 2 for Bug; optional on Task
      Parent              the Key of another node in this tree. Omit on an Epic
      ParentId            escape hatch: an existing work-item id to parent to. Validated live for
                          type and state. Prefer Parent
      GitHubIssue         (required on Bug) the GitHub issue number that masters the defect
      AreaLeaf            per-node override of -AreaLeaf
      IterationLeaf       per-node override of -IterationLeaf

.PARAMETER Path
    Path to a PowerShell data file (.psd1) whose single hashtable has a Tree key holding the node
    array. A data file is used rather than a script so loading the tree cannot execute code.

.PARAMETER AreaLeaf
    Sub-area under the project root. One of Collect, Assess, Ingest, Benchmark, Report, Platform.
    The value is validated against the live classification nodes before anything is written.

.PARAMETER IterationLeaf
    Iteration node under the project root, e.g. 2026-Q3-S6. Pass an empty string to leave items
    at the root iteration.

.PARAMETER OmitClassification
    Do not send System.AreaPath or System.IterationPath at all. Both then default to the project
    root, which is a single segment and passes the depth check. Use this if the em-dash in the
    project name is being mangled by the environment.

.EXAMPLE
    ./scripts/New-BoardTree.ps1 -Path ./scratch/v3-tree.psd1 -WhatIf

    Validates the whole tree and prints exactly what would be created, without writing anything.

.EXAMPLE
    $tree = @(
        @{ Key = 'epic'; Type = 'Epic'; Priority = 1
           Title       = 'Delete the forked ARI engine and ship Scout on its own collector'
           Description = '<div><p>The inventory engine is a fork of microsoft/ARI.</p></div>'
           Tags        = 'azure-scout; thisismydemo; powershell; module-enhancement'
           AcceptanceCriteria = @(
               'Get-ChildItem Modules -Recurse -Filter *.ps1 returns 0 files on main.'
               'No file under src/ references the Modules path.'
               'A full inventory run completes with Set-StrictMode -Version Latest in every module scope.'
           ) }
        @{ Key = 'feature'; Type = 'Feature'; Parent = 'epic'; Priority = 2
           Title       = 'Rewrite the collectors that cannot be expressed declaratively'
           Description = '<div><p>38 collectors make live calls or vary their row shape.</p></div>'
           Tags        = 'azure-scout; thisismydemo; powershell'
           AcceptanceCriteria = @(
               'Get-ScoutCollectorDefinition returns 176 definitions.'
               'The CI schema gate fails the build on a malformed definition.'
               'Each rewritten collector matches its predecessor output for the same fixture.'
           ) }
        @{ Key = 'story'; Type = 'User Story'; Parent = 'feature'; Priority = 2
           Title       = 'Convert the collectors that make live Azure calls'
           Description = '<div><p>32 collectors call Azure directly rather than filtering rows.</p></div>'
           Tags        = 'azure-scout; thisismydemo; powershell'
           AcceptanceCriteria = @(
               'All 32 declare their live calls in the definition.'
               'Each is covered by a test driven from a recorded Azure payload.'
               'The imperative fallback path is removed for these 32.'
           ) }
        @{ Key = 'task'; Type = 'Task'; Parent = 'story'; Priority = 2
           Title       = 'Catalogue the live-call shapes the schema must express'
           Description = '<div><p>Find every construct the declarative schema does not yet cover.</p></div>'
           Tags        = 'azure-scout; thisismydemo; powershell' }
    )
    ./scripts/New-BoardTree.ps1 -Tree $tree

    Creates a four-item tree under the Platform area in the current sprint.

.NOTES
    Requires an authenticated Azure CLI session (az login). Reads no secrets from the repo and
    writes none to it. Run scripts/Test-BoardConformance.ps1 immediately afterwards.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Inline')]
    [object[]] $Tree,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [string] $Path,

    [string] $Organization = 'https://dev.azure.com/hybridcloudsolutions',

    # Scout project GUID. Using the GUID avoids the U+2014 em-dash in the project name, which
    # console encoding mangles into TF401347 Invalid tree name.
    [string] $ProjectId = '85b6e47e-a666-4a38-8c43-de87dd21aa56',

    [string] $AreaLeaf = 'Platform',

    [string] $IterationLeaf = '2026-Q3-S6',

    # Used only to build the Hyperlink target for a Bug's GitHub master record.
    [string] $Repository = 'Hybrid-Solutions-Cloud/azure-scout',

    [switch] $OmitClassification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------------------------
# The rules below are a local mirror of scripts/Test-BoardConformance.ps1. If that script
# changes, change these to match - it is the gate, this is only an early warning.
# --------------------------------------------------------------------------------------------
$vocab = @(
    'platform', 'azurelocal', 'thisismydemo', 'hybridcloudsolutions', 'tierpoint', 'cross-repo', 'azure-scout',
    'identity', 'pipeline', 'docs', 'security', 'infrastructure', 'breaking', 'perf', 'testing', 'audit', 'automation',
    'powershell', 'cli', 'web-portal', 'cross-surface', 'module-enhancement', 'reporting', 'resilience', 'delivery', 'config', 'future-roadmap'
)
$minAc         = @{ 'Epic' = 3; 'Feature' = 3; 'User Story' = 3; 'Bug' = 2; 'Task' = 0 }
$allowedParent = @{ 'Epic' = @(); 'Feature' = @('Epic'); 'User Story' = @('Feature'); 'Bug' = @('Feature'); 'Task' = @('User Story', 'Bug') }
$validTypes    = @($minAc.Keys)

# Types that carry Microsoft.VSTS.Common.ValueArea. Task does not - sending it is a 400.
$valueAreaTypes = @('Epic', 'Feature', 'User Story', 'Bug')

function Get-NodeValue {
    # Hashtable member access under StrictMode is inconsistent enough to be worth avoiding.
    param($Node, [string] $Name)
    if ($Node.Contains($Name)) { return $Node[$Name] }
    return $null
}

function ConvertTo-AcceptanceCriteriaHtml {
    # The audit counts the literal lowercase '<li'. Nothing else scores, however it renders.
    param([string[]] $Criteria)
    "<ul>`n" + (($Criteria | ForEach-Object { "<li>$_</li>" }) -join "`n") + "`n</ul>"
}

# --------------------------------------------------------------------------------------------
# Load the tree
# --------------------------------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'File') {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Tree file not found: $Path" }
    $data = Import-PowerShellDataFile -LiteralPath $Path
    if (-not $data.Contains('Tree')) { throw "$Path must contain a hashtable with a Tree key." }
    $Tree = @($data['Tree'])
}
$nodes = @($Tree)
if (-not $nodes) { throw 'The tree is empty.' }

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
# Classification paths, read back verbatim so the em-dash is never re-encoded.
# The URL is assembled by concatenation rather than interpolation: a backtick-escaped $depth
# inside a double-quoted string does not survive being passed through a non-PowerShell shell.
# --------------------------------------------------------------------------------------------
$areaUri = "$org/$proj/_apis/wit/classificationnodes/areas?" + '$depth=2' + '&api-version=7.0'
$iterUri = "$org/$proj/_apis/wit/classificationnodes/iterations?" + '$depth=2' + '&api-version=7.0'

$areaNode = Invoke-RestMethod -Uri $areaUri -Method Get -Headers $jsonHeaders
$iterNode = Invoke-RestMethod -Uri $iterUri -Method Get -Headers $jsonHeaders

$areaRoot = $areaNode.name
$iterRoot = $iterNode.name

$areaLeaves = @()
if ($areaNode.PSObject.Properties.Name -contains 'children' -and $areaNode.children) {
    $areaLeaves = @($areaNode.children | ForEach-Object { $_.name })
}
$iterLeaves = @()
if ($iterNode.PSObject.Properties.Name -contains 'children' -and $iterNode.children) {
    $iterLeaves = @($iterNode.children | ForEach-Object { $_.name })
}

# Omit-on-doubt. U+FFFD is the replacement character a broken decode leaves behind, and a
# literal '?' means the em-dash was transliterated. The suspect characters are built from code
# points rather than typed, so this check cannot itself be broken by how this file is decoded.
# Either symptom means the string would be rejected as an invalid tree name, so send nothing and
# let both paths default to the project root - one segment, still conformant.
$suspect = '[' + [char]0xFFFD + '?]'
$omit = [bool] $OmitClassification
if (-not $omit -and ($areaRoot -match $suspect -or $iterRoot -match $suspect)) {
    Write-Warning "The project root name did not round-trip cleanly ('$areaRoot'). Omitting System.AreaPath and System.IterationPath; both will default to the project root, which is still conformant."
    $omit = $true
}

# Print the code point of every non-ASCII character in the root name, so a mangled em-dash is
# visible in the transcript instead of looking like an ordinary hyphen.
$exotic = @(
    0..($areaRoot.Length - 1) |
        Where-Object { [int]$areaRoot[$_] -gt 127 } |
        ForEach-Object { 'U+{0:X4}@{1}' -f [int]$areaRoot[$_], $_ }
)
Write-Host ("Area root     : {0}  [{1}]" -f $areaRoot, $(if ($exotic) { $exotic -join ' ' } else { 'all ASCII' }))
Write-Host ("Area leaves   : {0}" -f ($areaLeaves -join ', '))
Write-Host ("Iteration root: {0}" -f $iterRoot)

# --------------------------------------------------------------------------------------------
# Pre-flight. Nothing is written until every node passes.
# --------------------------------------------------------------------------------------------
$errs  = [System.Collections.Generic.List[string]]::new()
$byKey = @{}

foreach ($n in $nodes) {
    if ($n -isnot [System.Collections.IDictionary]) { $errs.Add('Every node must be a hashtable.'); continue }
    $key = Get-NodeValue $n 'Key'
    if (-not $key)                { $errs.Add('A node has no Key.'); continue }
    if ($byKey.ContainsKey($key)) { $errs.Add("Duplicate Key '$key'."); continue }
    $byKey[$key] = $n
}
if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Error $_ -ErrorAction Continue }; throw "$($errs.Count) pre-flight failure(s). Nothing was written." }

# Any ParentId escape hatches are validated against the live board for existence, type and state.
$externalParents = @{}
$parentIds = @($nodes | ForEach-Object { Get-NodeValue $_ 'ParentId' } | Where-Object { $_ } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
if ($parentIds.Count -gt 0) {
    $body = @{ ids = $parentIds; fields = @('System.WorkItemType', 'System.State', 'System.Title') } | ConvertTo-Json -Depth 6
    $fetched = (Invoke-RestMethod -Uri "$org/$proj/_apis/wit/workitemsbatch?api-version=7.0" -Method POST -Headers $jsonHeaders -Body $body).value
    foreach ($w in $fetched) { $externalParents[[int]$w.id] = $w.fields }
}

foreach ($n in $nodes) {
    $key   = Get-NodeValue $n 'Key'
    $type  = Get-NodeValue $n 'Type'
    $title = Get-NodeValue $n 'Title'

    if (-not $type)                    { $errs.Add("$key : no Type."); continue }
    if ($validTypes -notcontains $type) { $errs.Add("$key : unknown Type '$type'. Valid: $($validTypes -join ', ')."); continue }

    # Rule 9 - the audit's regex is ^[A-Z][a-z]+ , so the title must open with a capitalised
    # word. 'AB#5638 ...', 'v3 engine ...' and 'CI gate ...' all fail it.
    if (-not $title)                          { $errs.Add("$key : no Title.") }
    elseif ($title -notmatch '^[A-Z][a-z]+')  { $errs.Add("$key : Title must start with a capitalised verb: '$title'") }
    elseif ($title.Length -gt 120)            { $errs.Add("$key : Title is $($title.Length) characters; the standard caps it at 120.") }

    # Rule 1
    if (-not (Get-NodeValue $n 'Description')) { $errs.Add("$key : no Description.") }

    # Rule 3 - the audit tests for $null, so 0 would pass, but the standard defines 1-4.
    $pri = Get-NodeValue $n 'Priority'
    if ($null -eq $pri)          { $errs.Add("$key : no Priority.") }
    elseif ($pri -notin 1, 2, 3, 4) { $errs.Add("$key : Priority must be 1-4, got '$pri'.") }

    # Rule 2
    $ac = @(Get-NodeValue $n 'AcceptanceCriteria')
    $ac = @($ac | Where-Object { $_ })
    if ($ac.Count -lt $minAc[$type]) { $errs.Add("$key : $($ac.Count) acceptance criteria; $type requires $($minAc[$type]).") }

    # Rules 4 and 5
    $rawTags = Get-NodeValue $n 'Tags'
    $tags    = @((@($rawTags) -join ';') -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $tags) { $errs.Add("$key : no Tags.") }
    foreach ($t in $tags) { if ($vocab -notcontains $t) { $errs.Add("$key : non-vocabulary tag '$t'.") } }

    # Rule 6 - a two-segment path is the deepest the audit allows.
    if (-not $omit) {
        $leaf = Get-NodeValue $n 'AreaLeaf'; if (-not $leaf) { $leaf = $AreaLeaf }
        if ($leaf) {
            if ($areaLeaves -notcontains $leaf) { $errs.Add("$key : area '$leaf' is not a child of the project root. Valid: $($areaLeaves -join ', ').") }
            if ((('{0}\{1}' -f $areaRoot, $leaf) -split '\\').Count -gt 2) { $errs.Add("$key : area path would be deeper than 2 levels.") }
        }
        $iLeaf = Get-NodeValue $n 'IterationLeaf'; if (-not $iLeaf) { $iLeaf = $IterationLeaf }
        if ($iLeaf -and $iterLeaves -notcontains $iLeaf) { $errs.Add("$key : iteration '$iLeaf' is not a child of the project root. Valid: $($iterLeaves -join ', ').") }
    }

    # Rule 8 - GitHub masters Bugs, so a Bug without an issue fails the audit immediately.
    if ($type -eq 'Bug' -and -not (Get-NodeValue $n 'GitHubIssue')) {
        $errs.Add("$key : a Bug needs GitHubIssue set to a real issue number. Create the issue with the ado-tracked label first.")
    }
    if ($type -ne 'Bug' -and (Get-NodeValue $n 'GitHubIssue')) {
        $errs.Add("$key : GitHubIssue is only meaningful on a Bug. Every linked issue must map to a work item, so do not link one speculatively.")
    }

    # Rules 7, 10, 11 and 12 - the audit checks the parent's TYPE, not merely that a parent exists.
    $pKey = Get-NodeValue $n 'Parent'
    # Named $pRef, not $pId: PowerShell variable names are case-insensitive, so $pId IS the
    # read-only automatic variable $PID (the process id) and assigning it throws.
    $pRef = Get-NodeValue $n 'ParentId'
    if ($pKey -and $pRef) { $errs.Add("$key : set Parent or ParentId, not both.") }

    if ($type -eq 'Epic') {
        if ($pKey -or $pRef) { $errs.Add("$key : an Epic must be the top of the hierarchy and cannot have a parent.") }
    }
    elseif (-not $pKey -and -not $pRef) {
        $errs.Add("$key : $type must have a parent ($($allowedParent[$type] -join ' or ')).")
    }
    elseif ($pKey) {
        if (-not $byKey.ContainsKey($pKey)) { $errs.Add("$key : Parent '$pKey' is not a Key in this tree.") }
        else {
            $pType = Get-NodeValue $byKey[$pKey] 'Type'
            if ($allowedParent[$type] -notcontains $pType) {
                $errs.Add("$key : $type is parented to $pType; it must be a child of $($allowedParent[$type] -join ' or ').")
            }
        }
    }
    else {
        $pInt = [int]$pRef
        if (-not $externalParents.ContainsKey($pInt)) { $errs.Add("$key : ParentId AB#$pInt is not on this board.") }
        else {
            $pf    = $externalParents[$pInt]
            $pType = $pf.'System.WorkItemType'
            $pState = $pf.'System.State'
            if ($allowedParent[$type] -notcontains $pType) {
                $errs.Add("$key : $type is parented to AB#$pInt which is $pType; it must be a child of $($allowedParent[$type] -join ' or ').")
            }
            # Rule 10 - new items are created in New, so a closed parent would immediately fail.
            if ($pState -in 'Closed', 'Resolved', 'Removed') {
                $errs.Add("$key : ParentId AB#$pInt is $pState. A New item cannot hang off a closed parent.")
            }
        }
    }
}

if ($errs.Count -gt 0) {
    $errs | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($errs.Count) pre-flight failure(s). Nothing was written."
}
Write-Host ("Pre-flight    : {0} node(s) OK" -f $nodes.Count) -ForegroundColor Green

# --------------------------------------------------------------------------------------------
# Order parents before children. Declaration order is not trusted.
# --------------------------------------------------------------------------------------------
$ordered   = [System.Collections.Generic.List[object]]::new()
$placed    = @{}
$remaining = [System.Collections.Generic.List[object]]::new($nodes)
while ($remaining.Count -gt 0) {
    $progress = $false
    foreach ($n in @($remaining)) {
        $pKey = Get-NodeValue $n 'Parent'
        if (-not $pKey -or $placed.ContainsKey($pKey)) {
            $ordered.Add($n)
            $placed[(Get-NodeValue $n 'Key')] = $true
            [void]$remaining.Remove($n)
            $progress = $true
        }
    }
    if (-not $progress) {
        $stuck = @($remaining | ForEach-Object { Get-NodeValue $_ 'Key' }) -join ', '
        throw "The tree has a parent cycle. Unresolvable nodes: $stuck"
    }
}

# --------------------------------------------------------------------------------------------
# Idempotence. A node whose exact title is already on the board is skipped, and its id is reused
# so its children still parent correctly on a re-run.
# --------------------------------------------------------------------------------------------
$wiql = @{ query = 'SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project' } | ConvertTo-Json
$ids  = @((Invoke-RestMethod -Uri "$org/$proj/_apis/wit/wiql?api-version=7.0" -Method POST -Headers $jsonHeaders -Body $wiql).workItems.id)
$existing = @{}
for ($i = 0; $i -lt $ids.Count; $i += 100) {
    $chunk = $ids[$i..([Math]::Min($i + 99, $ids.Count - 1))]
    $body  = @{ ids = $chunk; fields = @('System.Title') } | ConvertTo-Json -Depth 6
    foreach ($w in (Invoke-RestMethod -Uri "$org/$proj/_apis/wit/workitemsbatch?api-version=7.0" -Method POST -Headers $jsonHeaders -Body $body).value) {
        $t = $w.fields.'System.Title'
        if (-not $existing.ContainsKey($t)) { $existing[$t] = [int]$w.id }
    }
}
Write-Host ("Board         : {0} existing item(s) scanned for duplicate titles" -f $ids.Count)
Write-Host ''

# --------------------------------------------------------------------------------------------
# Create
# --------------------------------------------------------------------------------------------
$created  = @{}
$newCount = 0
$skipped  = 0

foreach ($n in $ordered) {
    $key   = Get-NodeValue $n 'Key'
    $type  = Get-NodeValue $n 'Type'
    $title = Get-NodeValue $n 'Title'

    if ($existing.ContainsKey($title)) {
        $created[$key] = $existing[$title]
        $skipped++
        '{0,-14} SKIP   already on the board as AB#{1}' -f $key, $existing[$title]
        continue
    }

    $parentId = $null
    $pKey = Get-NodeValue $n 'Parent'
    $pRef = Get-NodeValue $n 'ParentId'   # not $pId - that name is the automatic variable $PID
    if ($pRef)      { $parentId = [int]$pRef }
    elseif ($pKey)  { $parentId = $created[$pKey] }   # topological order guarantees the key exists

    $rawTags = Get-NodeValue $n 'Tags'
    $tagList = @((@($rawTags) -join ';') -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $ops = [System.Collections.Generic.List[object]]::new()
    $ops.Add(@{ op = 'add'; path = '/fields/System.Title';                   value = $title })
    $ops.Add(@{ op = 'add'; path = '/fields/System.Description';             value = (Get-NodeValue $n 'Description') })
    $ops.Add(@{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.Priority'; value = [int](Get-NodeValue $n 'Priority') })
    # op=add is correct on a create because there is no prior value. On an EXISTING item
    # System.Tags with op=add appends - use op=replace with the complete joined string there.
    $ops.Add(@{ op = 'add'; path = '/fields/System.Tags';                    value = ($tagList -join '; ') })

    $ac = @(Get-NodeValue $n 'AcceptanceCriteria')
    $ac = @($ac | Where-Object { $_ })
    if ($ac.Count -gt 0) {
        $ops.Add(@{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.AcceptanceCriteria'; value = (ConvertTo-AcceptanceCriteriaHtml $ac) })
    }

    if (-not $omit) {
        $leaf = Get-NodeValue $n 'AreaLeaf'; if (-not $leaf) { $leaf = $AreaLeaf }
        if ($leaf) { $ops.Add(@{ op = 'add'; path = '/fields/System.AreaPath'; value = ('{0}\{1}' -f $areaRoot, $leaf) }) }
        $iLeaf = Get-NodeValue $n 'IterationLeaf'; if (-not $iLeaf) { $iLeaf = $IterationLeaf }
        if ($iLeaf) { $ops.Add(@{ op = 'add'; path = '/fields/System.IterationPath'; value = ('{0}\{1}' -f $iterRoot, $iLeaf) }) }
    }

    # Task has no ValueArea field. Sending it is a 400.
    if ($valueAreaTypes -contains $type) {
        $ops.Add(@{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.ValueArea'; value = 'Business' })
    }

    if ($parentId) {
        # 'workItems' must stay camel-cased: the conformance audit's regex is case-sensitive and
        # a lower-case 'workitems' makes this relation invisible, reporting "has no parent".
        # The -f argument list is parenthesised: inside a hashtable literal its commas would
        # otherwise be read as entry separators and the script would not parse.
        $ops.Add(@{ op = 'add'; path = '/relations/-'; value = @{
            rel        = 'System.LinkTypes.Hierarchy-Reverse'
            url        = ('{0}/{1}/_apis/wit/workItems/{2}' -f $org, $proj, $parentId)
            attributes = @{ comment = 'Parent' }
        } })
    }

    $gh = Get-NodeValue $n 'GitHubIssue'
    if ($gh) {
        $ops.Add(@{ op = 'add'; path = '/relations/-'; value = @{
            rel        = 'Hyperlink'
            url        = "https://github.com/$Repository/issues/$gh"
            attributes = @{ comment = "GitHub intake master (Flow 1) - $Repository#$gh" }
        } })
    }

    $target = if ($parentId) { "$type '$title' under AB#$parentId" } else { "$type '$title'" }
    if (-not $PSCmdlet.ShouldProcess($target, 'create work item')) {
        # Under -WhatIf there is no server-assigned id, so children of this node will be planned
        # without a parent link. That is a rehearsal artefact, not a conformance problem.
        $created[$key] = $null
        '{0,-14} WHATIF {1}' -f $key, $target
        continue
    }

    # A work item cannot be created in Resolved or Closed. Everything is created in New; use
    # scripts/Set-BoardState.ps1 afterwards to move states.
    $uri  = '{0}/{1}/_apis/wit/workitems/${2}?api-version=7.0' -f $org, $proj, [uri]::EscapeDataString($type)
    $body = ConvertTo-Json @($ops.ToArray()) -Depth 6   # -Depth 6 or the relation attributes flatten
    $wi   = Invoke-RestMethod -Uri $uri -Method POST -Headers $patchHeaders -Body $body

    $created[$key] = [int]$wi.id
    $newCount++
    '{0,-14} AB#{1,-6} [{2}]  {3}' -f $key, $wi.id, $type, $title
}

Write-Host ''
Write-Host ("Created {0}, skipped {1} (already present)." -f $newCount, $skipped)
Write-Host 'Now run: ./scripts/Test-BoardConformance.ps1' -ForegroundColor Yellow
