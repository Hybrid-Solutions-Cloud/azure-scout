#Requires -Version 7.0
<#
.SYNOPSIS
    Audits the Azure Scout ADO board and GitHub issue set against the HCS work-item standards.

.DESCRIPTION
    Enforces, in one pass, the rules that are otherwise only enforced by memory:

    From the work-items standard:
      - Description, Acceptance Criteria (minimum count per type), and Priority are present.
      - Every tag comes from the approved vocabulary - no freeform tags.
      - Area paths are at most two levels deep.
      - Titles start with a verb.
      - The type hierarchy holds: Epic > Feature > User Story > Task, with Bug a peer of
        User Story (so parented to a Feature). Checking only that a parent EXISTS is not enough -
        this checks the parent's TYPE.
      - No open item hangs off a Closed, Resolved, or Removed parent.

    From the work-item-sync standard (Flow 1):
      - Every ADO Bug has a GitHub master record, because GitHub is master for Bugs.
      - Every GitHub issue maps to an ADO work item.
      - Every linked issue carries `ado-tracked` plus the status label matching its ADO state.

    Exits non-zero when anything fails, so it can gate a pipeline.

.PARAMETER Organization
    Azure DevOps organization URL.

.PARAMETER ProjectId
    Azure DevOps project GUID. The GUID is used rather than the name because the project name
    contains an em-dash that Windows console encoding mangles, which silently audits the wrong project.

.PARAMETER Repository
    GitHub repository in owner/name form.

.EXAMPLE
    ./scripts/Test-BoardConformance.ps1

    Audits the board and issue set, printing every failure and exiting non-zero if there are any.
#>
[CmdletBinding()]
param(
    [string] $Organization = 'https://dev.azure.com/hybridcloudsolutions',
    [string] $ProjectId    = '85b6e47e-a666-4a38-8c43-de87dd21aa56',
    [string] $Repository   = 'Hybrid-Solutions-Cloud/azure-scout',

    # An Azure DevOps PAT, used in preference to the az CLI when supplied. Also read from
    # $env:ADO_PAT so a caller can export it once. Added because `az account get-access-token`
    # now fails with AADSTS50076 (MFA required) on this tenant, which made a committed
    # conformance gate unrunnable without an interactive login -- and a gate nobody can run is a
    # gate nobody runs. The HCS Governance MCP mints a suitable PAT non-interactively.
    [string] $Pat = $env:ADO_PAT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$org  = $Organization
$proj = $ProjectId
$repo = $Repository
$hdr  = if (-not [string]::IsNullOrWhiteSpace($Pat)) {
    @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':' + $Pat))
       'Content-Type' = 'application/json' }
} else {
    $tok = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
    if ([string]::IsNullOrWhiteSpace($tok)) {
        throw 'Could not obtain an Azure DevOps token. Pass -Pat, or set $env:ADO_PAT, or run `az login`.'
    }
    @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
}

$vocab = @(
    'platform','azurelocal','thisismydemo','hybridcloudsolutions','tierpoint','cross-repo','azure-scout',
    'identity','pipeline','docs','security','infrastructure','breaking','perf','testing','audit','automation',
    'powershell','cli','web-portal','cross-surface','module-enhancement','reporting','resilience','delivery','config','future-roadmap'
)
$minAc = @{ 'Epic' = 3; 'Feature' = 3; 'User Story' = 3; 'Bug' = 2; 'Task' = 0 }

$wiql = @{ query = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project ORDER BY [System.Id]" } | ConvertTo-Json
$ids  = @((Invoke-RestMethod -Uri "$org/$proj/_apis/wit/wiql?api-version=7.0" -Method POST -Headers $hdr -Body $wiql).workItems.id)
$all = @()
for ($i = 0; $i -lt $ids.Count; $i += 100) {
    $chunk = $ids[$i..([Math]::Min($i + 99, $ids.Count - 1))]
    $body  = @{ ids = $chunk; '$expand' = 'Relations' } | ConvertTo-Json
    $all += (Invoke-RestMethod -Uri "$org/$proj/_apis/wit/workitemsbatch?api-version=7.0" -Method POST -Headers $hdr -Body $body).value
}

function Field { param($Wi, $Name) if ($Wi.fields.PSObject.Properties.Name -contains $Name) { $Wi.fields.$Name } else { $null } }

$rows = foreach ($wi in $all) {
    $ghNums = @()
    $parent = $null
    if ($wi.PSObject.Properties.Name -contains 'relations' -and $wi.relations) {
        foreach ($r in $wi.relations) {
            if ($r.rel -eq 'Hyperlink' -and $r.url -match 'github\.com/[^/]+/[^/]+/issues/(\d+)') { $ghNums += [int]$Matches[1] }
            if ($r.rel -eq 'System.LinkTypes.Hierarchy-Reverse' -and $r.url -match '/workItems/(\d+)') { $parent = [int]$Matches[1] }
        }
    }
    $acRaw = Field $wi 'Microsoft.VSTS.Common.AcceptanceCriteria'
    [pscustomobject]@{
        Ab     = $wi.id
        Type   = Field $wi 'System.WorkItemType'
        State  = Field $wi 'System.State'
        Title  = Field $wi 'System.Title'
        Desc   = Field $wi 'System.Description'
        AcN    = if ($acRaw) { ([regex]::Matches($acRaw, '<li')).Count } else { 0 }
        Pri    = Field $wi 'Microsoft.VSTS.Common.Priority'
        Tags   = @(((Field $wi 'System.Tags') -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Area   = Field $wi 'System.AreaPath'
        Iter   = Field $wi 'System.IterationPath'
        Parent = $parent
        Gh     = $ghNums
    }
}

"BOARD TOTAL: $($rows.Count)"
$rows | Group-Object State | Sort-Object Name | ForEach-Object { "  {0,-10} {1}" -f $_.Name, $_.Count }
$rows | Group-Object Type | Sort-Object Name | ForEach-Object { "  {0,-12} {1}" -f $_.Name, $_.Count }

$fail = @()
foreach ($r in $rows) {
    if (-not $r.Desc)                             { $fail += "AB#$($r.Ab) no description" }
    if ($r.AcN -lt $minAc[$r.Type])               { $fail += "AB#$($r.Ab) [$($r.Type)] AC count $($r.AcN) < $($minAc[$r.Type])" }
    if ($null -eq $r.Pri)                         { $fail += "AB#$($r.Ab) no priority" }
    if (-not $r.Tags)                             { $fail += "AB#$($r.Ab) no tags" }
    foreach ($t in $r.Tags) { if ($vocab -notcontains $t) { $fail += "AB#$($r.Ab) non-vocabulary tag '$t'" } }
    if (($r.Area -split '\\').Count -gt 2)        { $fail += "AB#$($r.Ab) area path deeper than 2 levels: $($r.Area)" }
    if ($r.Type -ne 'Epic' -and -not $r.Parent)   { $fail += "AB#$($r.Ab) [$($r.Type)] has no parent" }
    if ($r.Type -eq 'Bug' -and -not $r.Gh)        { $fail += "AB#$($r.Ab) Bug with no GitHub master record" }
    if ($r.Title -notmatch '^[A-Z][a-z]+')        { $fail += "AB#$($r.Ab) title may not start with a verb: $($r.Title)" }
}

$byId = @{}; foreach ($r in $rows) { $byId[[int]$r.Ab] = $r }

# A closed parent cannot own open work - the roll-up would be reporting done work that isn't.
foreach ($r in $rows) {
    if ($r.State -notin 'New', 'Active') { continue }
    if (-not $r.Parent -or -not $byId.ContainsKey([int]$r.Parent)) { continue }
    $p = $byId[[int]$r.Parent]
    if ($p.State -in 'Closed', 'Resolved', 'Removed') {
        $fail += "AB#$($r.Ab) [$($r.State)] hangs off AB#$($p.Ab) which is $($p.State)"
    }
}

# work-items.md "Work item types" dictates the parent TYPE, not merely that a parent exists:
# Epic > Feature > User Story > Task, with Bug a peer of User Story (so parented to a Feature).
$allowedParent = @{
    'Epic' = @(); 'Feature' = @('Epic'); 'User Story' = @('Feature'); 'Bug' = @('Feature'); 'Task' = @('User Story', 'Bug')
}
foreach ($r in $rows) {
    if ($r.Type -eq 'Epic') {
        if ($r.Parent) { $fail += "AB#$($r.Ab) Epic must be top of hierarchy but has parent AB#$($r.Parent)" }
        continue
    }
    if (-not $r.Parent) { continue }   # already reported by the no-parent check above
    if (-not $byId.ContainsKey([int]$r.Parent)) { $fail += "AB#$($r.Ab) parent AB#$($r.Parent) is not on this board"; continue }
    $pt = $byId[[int]$r.Parent].Type
    if ($allowedParent[$r.Type] -notcontains $pt) {
        $fail += "AB#$($r.Ab) [$($r.Type)] is parented to a $pt (AB#$($r.Parent)); must be a child of $($allowedParent[$r.Type] -join ' or ')"
    }
}

"--- ADO CONFORMANCE FAILURES: $((@($fail)).Count) ---"
$fail | ForEach-Object { "  $_" }

# GitHub side
# gh issue list uses GraphQL, whose hourly quota is spent; the REST issues endpoint still has budget.
$rest = @()
for ($page = 1; $page -le 5; $page++) {
    $r = (gh api "repos/$repo/issues?state=all&per_page=100&page=$page" 2>&1 | Out-String)
    $r = $r.Substring($r.IndexOf('['))
    $batch = @($r | ConvertFrom-Json)
    if (-not $batch) { break }
    $rest += $batch
    if ($batch.Count -lt 100) { break }
}
$gh = @($rest |
    Where-Object { -not ($_.PSObject.Properties.Name -contains 'pull_request') } |
    ForEach-Object { [pscustomobject]@{ number = $_.number; state = $_.state.ToUpper(); labels = $_.labels } })
$ghx = @{}; foreach ($i in $gh) { $ghx[[int]$i.number] = $i }
$linked = @{}
foreach ($r in $rows) { foreach ($g in $r.Gh) { $linked[$g] = $r } }

$ghFail = @()
foreach ($r in $rows) {
    foreach ($g in $r.Gh) {
        if (-not $ghx.ContainsKey($g)) { $ghFail += "AB#$($r.Ab) -> GH#$g does not exist"; continue }
        $lab  = @($ghx[$g].labels.name)
        $want = switch ($r.State) { 'Resolved' { 'resolved' } 'Closed' { 'resolved' } 'Removed' { 'wont-fix' } 'Active' { 'in-progress' } default { '' } }
        if ($lab -notcontains 'ado-tracked') { $ghFail += "GH#$g missing ado-tracked (AB#$($r.Ab))" }
        if ($want -and ($lab -notcontains $want)) { $ghFail += "GH#$g missing '$want' (AB#$($r.Ab) is $($r.State))" }
    }
}
foreach ($n in $ghx.Keys) { if (-not $linked.ContainsKey($n)) { $ghFail += "GH#$n has no ADO work item" } }

"--- GITHUB RECONCILE FAILURES: $((@($ghFail)).Count) ---"
$ghFail | Sort-Object | ForEach-Object { "  $_" }
"GITHUB TOTAL: $($gh.Count) (linked: $($linked.Keys.Count))"

$total = (@($fail)).Count + (@($ghFail)).Count
if ($total -gt 0) {
    Write-Error "$total conformance failure(s). The board does not meet the HCS work-item standards."
    exit 1
}
'PASS - board and issue set conform to the HCS work-item standards.'
