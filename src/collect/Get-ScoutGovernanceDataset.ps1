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

    That is the AB#6755 shape applied a second time. Two of the three Resource Graph queries and
    both ARM REST reads per subscription MOVED here from `Import-Governance`; they were not added.
    `tests/Collect.Governance.Tests.ps1` pins the count on both sides.

    THE THIRD QUERY IS DELIBERATE, AND IT IS A COST THIS FUNCTION DID NOT ORIGINALLY PAY.
    `Import-Governance` read only `microsoft.authorization/roleassignments`, which carries
    `properties.roleDefinitionId` -- a GUID. This function originally asked the SAME scoped query
    for `microsoft.authorization/roledefinitions` too, on the belief that `authorizationresources`
    returns built-in AND custom definitions. It does not: at subscription or management-group
    scope that table returns only the definitions CREATED in scope -- in practice the custom roles
    alone. Against a live tenant that produced 110 role assignments whose Role Name every one read
    `Unresolved (<guid>)`, which fails AB#6779's actual acceptance criterion -- "a run reports
    every role assignment, INCLUDING WHO HOLDS OWNER" -- while looking perfectly populated.

    The ~960 built-in definitions are visible only under `Search-AzGraph -UseTenantScope`, and
    that switch is its own PARAMETER SET: mutually exclusive with `-ManagementGroup`, and it
    returns a different set of role ASSIGNMENTS as well. So it cannot be folded into the scoped
    query, and a third round trip is the only way to name a built-in role. The budget moved from
    two to three on purpose: a role-assignment worksheet that cannot name the role is output that
    looks populated and answers nothing, which is the exact defect class this work exists to
    remove. The third query is used ONLY to resolve definition names -- never for the assignments
    themselves, which must keep coming from the scoped query.

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ManagementGroupId',
        Justification = 'False positive: read inside the nested Invoke-ScoutGovernanceArg closure (line 108), not in the outer function body.')]
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
    #
    # -TenantScope selects Search-AzGraph's TenantScopedQuery parameter set, which cannot carry
    # -ManagementGroup. That is why it is a switch here rather than something the caller's
    # -ManagementGroupId can imply: the two are mutually exclusive at the SDK, and only the
    # role-DEFINITION lookup may use it.
    function Invoke-ScoutGovernanceArg([string] $Query, [switch] $TenantScope) {
        $rows = @(); $skip = 0
        do {
            $params = @{ Query = $Query; First = 1000; ErrorAction = 'Stop' }
            if ($skip -gt 0) { $params.Skip = $skip }
            if ($TenantScope) { $params.UseTenantScope = $true }
            elseif ($ManagementGroupId) { $params.ManagementGroup = $ManagementGroupId }

            # Search-AzGraph writes ONE object -- a PSResourceGraphResponse wrapper carrying
            # SkipToken/Data/Count/IsReadOnly -- and does NOT enumerate its rows into the pipeline.
            # `@(Search-AzGraph ...)` therefore yields a one-element array holding the WRAPPER, not
            # the rows, and that cost this function two things (AB#6779):
            #
            #   * the wrapper has no `type` property, so the filter below that separates role
            #     assignments from role definitions matched nothing and the Role Assignments
            #     worksheet shipped EMPTY against a tenant with 110 assignments;
            #   * `$batch.Count` was permanently 1, so the paging predicate could never be true and
            #     every governance query was silently capped at its first page.
            #
            # `.Data` is the rows, and it behaves identically on an empty result -- which is the
            # whole reason to read it rather than to enumerate the wrapper. The array fallback is
            # for a caller (or a test double) that hands back plain rows instead of a wrapper.
            # Assigned in STATEMENTS, not as `$batch = if (...) { @($response.Data) }`. An if-block
            # yields its body through the output stream, and an EMPTY array contributes zero
            # objects to that stream -- so the expression form silently assigns $null on exactly
            # the empty result this code exists to handle, and the `$batch.Count` below then throws
            # under StrictMode and costs the whole dataset. Direct assignment keeps @() as @().
            $response = Search-AzGraph @params
            $batch = @()
            if ($null -ne $response -and $response.PSObject.Properties['Data']) {
                $batch = @($response.Data)
            }
            elseif ($null -ne $response) {
                $batch = @($response | Where-Object { $null -ne $_ })
            }

            $rows += $batch; $skip += 1000
        } while ($batch.Count -eq 1000)
        return , $rows
    }

    # ---- 1 of 3 Resource Graph round trips: authorization, at the caller's scope ---------------
    # Assignments AND in-scope (in practice: custom) definitions in one query. THE ASSIGNMENTS
    # COME FROM HERE AND ONLY HERE -- query 3 is tenant-scoped and returns a different, wrong set
    # of assignments, so it is never allowed to contribute one.
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

    # ---- 2 of 3 Resource Graph round trips: role definition NAMES, tenant-scoped --------------
    # The one call that makes "who has Owner" answerable. See the .DESCRIPTION for why it cannot
    # be folded into query 1.
    #
    # Only three fields cross the wire: a role definition's full `properties` carries its entire
    # permission model (Actions/NotActions/DataActions, hundreds of strings for a built-in), and
    # nothing here reads it. `pack()` rebuilds the exact nested shape
    # `ConvertTo-ScoutGovernanceResource` already reads -- properties.roleName / properties.type --
    # so the dataset contract is unchanged and the flattener needed no edit.
    #
    # A failure here is NOT fatal and must not be. Tenant-scope read is a permission a caller can
    # legitimately lack, and the run is still worth having: the scoped definitions from query 1
    # survive, every other role degrades to `Unresolved (<guid>)`, and the warning says which
    # permission would fix it. Failing the run instead would trade a partial answer for none.
    $tenantRoleDefinitions = @()
    try {
        $tenantRoleDefinitions = Invoke-ScoutGovernanceArg -TenantScope -Query @'
authorizationresources
| where type =~ "microsoft.authorization/roledefinitions"
| project id, type, properties = pack("roleName", tostring(properties.roleName), "type", tostring(properties.type))
'@
    }
    catch {
        Write-Warning ("Get-ScoutGovernanceDataset: tenant-scoped role-definition lookup failed; built-in role names " +
            "will read as 'Unresolved (<guid>)'. Reader at the tenant root management group resolves this: $($_.Exception.Message)")
    }

    # Merged, not replaced. The scoped definitions from query 1 are listed LAST so they win a GUID
    # collision: they were read at the caller's own scope and are the more specific answer.
    $roleDefinitions = @(@($tenantRoleDefinitions | Where-Object { $_ }) + @($roleDefinitions | Where-Object { $_ }))

    # ---- 3 of 3 Resource Graph round trips: policy assignments --------------------------------
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
    $budgets = @(); $locks = @(); $pimEligibility = @()
    $sourceOperations = [System.Collections.Generic.List[object]]::new()
    $subIds = @($Subscriptions | ForEach-Object {
            if ($_ -and $_.PSObject.Properties['id']) { $_.id }
        } | Where-Object { $_ })

    foreach ($sub in $subIds) {
        $pimStartedAt = Get-Date
        try {
            $pimRows = @(Get-AzRoleEligibilitySchedule -Scope "/subscriptions/$sub" -ErrorAction Stop)
            $pimEligibility += $pimRows
            $sourceOperations.Add([pscustomobject]@{
                    Source = 'Azure RBAC control plane'
                    Dataset = 'PIM role eligibility schedules'
                    SubscriptionId = $sub
                    Operation = 'Get-AzRoleEligibilitySchedule'
                    Scope = "/subscriptions/$sub"
                    Status = if ($pimRows.Count -gt 0) { 'Success' } else { 'Empty' }
                    Count = $pimRows.Count
                    Reason = $null
                    StartedAt = $pimStartedAt.ToString('o')
                    CompletedAt = (Get-Date).ToString('o')
                })
        }
        catch {
            Write-Warning ('Get-ScoutGovernanceDataset: PIM eligibility read failed for {0}: {1}' -f $sub, $_.Exception.Message)
            $sourceOperations.Add([pscustomobject]@{
                    Source = 'Azure RBAC control plane'
                    Dataset = 'PIM role eligibility schedules'
                    SubscriptionId = $sub
                    Operation = 'Get-AzRoleEligibilitySchedule'
                    Scope = "/subscriptions/$sub"
                    Status = 'Unavailable'
                    Count = 0
                    Reason = $_.Exception.Message
                    StartedAt = $pimStartedAt.ToString('o')
                    CompletedAt = (Get-Date).ToString('o')
                })
        }
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
        pimEligibility    = @($pimEligibility    | Where-Object { $_ })
        sourceOperations  = @($sourceOperations)
    }
}
