#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Collect the four governance datasets ONCE, in the raw pass, so both the assessment rules
    and the inventory worksheets read the same rows.

.DESCRIPTION
    Role assignments, policy assignments, resource locks and budgets were collected by
    `src/ingest/Import-Governance.ps1` on every assessment run and written NOWHERE. No collector
    rendered them, so a run could not answer "who has Owner" even though the answer was sitting
    in memory (AB#6779).

    The four inventory collectors that now render them (Identity/RoleAssignments,
    Management/PolicyAssignments, Management/ResourceLocks, Management/Budgets) run over the raw
    pass's `$Resources`, not over the assessment's `collect.json`. Rather than collect the same
    data a second time for them, this function is the single producer and BOTH consumers read it:

        Get-ScoutRawInventory  ->  Get-ScoutGovernanceDataset  ->  ConvertTo-ScoutGovernanceResource
                                            |                        (AZSC/Governance/* envelopes
                                            |                         appended to $Resources, which
                                            |                         is what the collectors render)
                                            +-> returned on the raw envelope as `Governance`
                                                 -> Invoke-Collect fills $collect.governance
                                                 -> Import-Governance SKIPS the datasets that are
                                                    already populated

    That is the AB#6755 shape applied a second time, and it is why rendering these four datasets
    costs zero additional Azure calls on an assessment run: the two Resource Graph queries and the
    two ARM REST reads per subscription MOVED here from `Import-Governance`; they were not added.
    `tests/Collect.Governance.Tests.ps1` pins the count on both sides.

    One deliberate difference from the query it replaces. `Import-Governance` read only
    `microsoft.authorization/roleassignments`, which carries `properties.roleDefinitionId` -- a
    GUID. A worksheet of GUIDs cannot answer "who has Owner", so the SAME single query also
    returns `microsoft.authorization/roledefinitions` (the `authorizationresources` table holds
    built-in AND custom definitions, each with `properties.roleName`). One round trip, two result
    types, real role names.

.PARAMETER Subscriptions
    Subscription objects carrying `.id` (and optionally `.name`). Budgets and resource locks are
    not Resource Graph-indexed and must be read per subscription over ARM REST.

.PARAMETER ManagementGroupId
    Scopes both Resource Graph queries via `Search-AzGraph -ManagementGroup`, matching
    `Import-Governance`'s behaviour exactly.

.OUTPUTS
    [pscustomobject] with `roleAssignments`, `roleDefinitions`, `policyAssignments`, `budgets`,
    `resourceLocks` -- every one an array, never $null. A dataset whose read failed is empty and
    a warning names it; a governance read must never take an inventory run down.

.NOTES
    Tracks ADO Task AB#6780/AB#6781/AB#6782/AB#6783 (Story AB#6779).

    Read-only throughout: Reader at the management-group root is sufficient. Budgets and locks
    are plain ARM GETs against the caller's ambient Az context, the same authentication path
    `Import-Governance` and `Get-ScoutApiResources` already use.
#>
function Get-ScoutGovernanceDataset {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Subscriptions = @(),

        [string]   $ManagementGroupId
    )

    # Imported only if the command is not already reachable. An unconditional Import-Module here
    # would be a hard dependency the raw pass around this function does not have -- it calls
    # Search-AzGraph without importing anything -- and it re-binds the command in a way that costs
    # the whole dataset silently when the module is unavailable or shadowed.
    if (-not (Get-Command Search-AzGraph -ErrorAction SilentlyContinue)) {
        Import-Module Az.ResourceGraph -ErrorAction Stop
    }
    if (-not (Get-Command Invoke-AzRestMethod -ErrorAction SilentlyContinue)) {
        Import-Module Az.Accounts -ErrorAction Stop
    }

    # Paged exactly as Import-Governance paged: Search-AzGraph rejects -Skip 0 (its ValidateRange
    # minimum is 1), so the first page omits it entirely.
    function Invoke-ScoutGovernanceArg([string] $Query) {
        $rows = @(); $skip = 0
        do {
            $params = @{ Query = $Query; First = 1000; ErrorAction = 'Stop' }
            if ($skip -gt 0) { $params.Skip = $skip }
            if ($ManagementGroupId) { $params.ManagementGroup = $ManagementGroupId }
            $batch = @(Search-AzGraph @params)
            $rows += $batch; $skip += 1000
        } while ($batch.Count -eq 1000)
        return , $rows
    }

    # ---- 1 of 2 Resource Graph round trips: authorization -------------------------------------
    # Assignments AND definitions in one query. Splitting them would be a second round trip for
    # data the same table already holds, which is the exact cost this story is not allowed to add.
    $authorization = @()
    try {
        $authorization = Invoke-ScoutGovernanceArg @'
authorizationresources
| where type in~ ("microsoft.authorization/roleassignments", "microsoft.authorization/roledefinitions")
| project name, id, type, properties
'@
    }
    catch { Write-Warning "Get-ScoutGovernanceDataset: authorization query failed; role assignments and role names will be empty: $($_.Exception.Message)" }

    $authorization = @($authorization | Where-Object { $_ })
    $roleAssignments = @($authorization | Where-Object {
            $_.PSObject.Properties['type'] -and [string]$_.type -ieq 'microsoft.authorization/roleassignments'
        })
    $roleDefinitions = @($authorization | Where-Object {
            $_.PSObject.Properties['type'] -and [string]$_.type -ieq 'microsoft.authorization/roledefinitions'
        })

    # ---- 2 of 2 Resource Graph round trips: policy assignments --------------------------------
    # The nested `properties` object is kept whole so the assessment rules' JSONPaths
    # (@.properties.enforcementMode / .parameters / .displayName) resolve exactly as before.
    $policyAssignments = @()
    try {
        $policyAssignments = Invoke-ScoutGovernanceArg @'
policyresources
| where type =~ "microsoft.authorization/policyassignments"
| project name, id, type, properties
'@
    }
    catch { Write-Warning "Get-ScoutGovernanceDataset: policy-assignment query failed: $($_.Exception.Message)" }

    # ---- budgets + resource locks: neither is Resource Graph-indexed --------------------------
    # Read-only ARM GETs on the ambient Az context (works headless under an SPN login). One
    # failing subscription costs that subscription's rows, never the dataset.
    $budgets = @(); $locks = @()
    $subIds = @($Subscriptions | ForEach-Object {
            if ($_ -and $_.PSObject.Properties['id']) { $_.id }
        } | Where-Object { $_ })

    foreach ($sub in $subIds) {
        try {
            $resp = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$sub/providers/Microsoft.Consumption/budgets?api-version=2023-11-01"
            if ($resp -and $resp.StatusCode -eq 200) {
                $val = ($resp.Content | ConvertFrom-Json -Depth 100).value
                if ($val) { $budgets += $val }
            }
        }
        catch { Write-Warning "Get-ScoutGovernanceDataset: budgets read failed for $sub`: $($_.Exception.Message)" }

        try {
            $resp = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$sub/providers/Microsoft.Authorization/locks?api-version=2020-05-01"
            if ($resp -and $resp.StatusCode -eq 200) {
                $val = ($resp.Content | ConvertFrom-Json -Depth 100).value
                if ($val) { $locks += $val }
            }
        }
        catch { Write-Warning "Get-ScoutGovernanceDataset: resource-lock read failed for $sub`: $($_.Exception.Message)" }
    }

    # Every dataset is normalised to a genuine array of real objects. The paged helper's
    # `return , $rows` idiom preserves a populated array intact, but a query that yields ZERO rows
    # leaks a single-element wrapper whose element is an empty array -- which reports Count=1 and
    # would make a downstream "did we get governance data" guard answer yes when it should answer
    # no. Filtering to truthy elements collapses that wrapper back to a true empty set.
    return [pscustomobject]@{
        roleAssignments   = @($roleAssignments   | Where-Object { $_ })
        roleDefinitions   = @($roleDefinitions   | Where-Object { $_ })
        policyAssignments = @($policyAssignments | Where-Object { $_ })
        budgets           = @($budgets           | Where-Object { $_ })
        resourceLocks     = @($locks             | Where-Object { $_ })
    }
}
