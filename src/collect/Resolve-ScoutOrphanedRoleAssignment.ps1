#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Flag role assignments whose principal no longer exists in Entra ID -- "who has Owner" answers
    who is CURRENTLY assigned; this answers whether that assignment still points at anyone.

.DESCRIPTION
    Story AB#6456 (Feature AB#6455, Epic AB#6454). The Role Assignments worksheet
    (manifests/collectors/Identity/RoleAssignments.psd1, shipped by Epic AB#6731) already renders
    every assignment's Principal ID and Principal Type. What it cannot say is whether that
    principal still resolves -- a role assignment left behind after a user is deleted, a service
    principal is removed, or a group is disbanded is a standing grant nobody can revoke by
    deleting the object anymore, and it is exactly the kind of finding a governance review exists
    to surface.

    This is a PURE, LOCAL transform. It makes no Azure Resource Graph or Microsoft Graph call of
    its own -- it reads two things Scout has already collected in the same run:

      * the 'AZSC/Governance/RoleAssignment' envelope ConvertTo-ScoutGovernanceResource produced
        from the ARM role-assignment sweep (Get-ScoutGovernanceDataset), and
      * the 'entra/users' / 'entra/groups' / 'entra/serviceprincipals' / 'entra/managedidentities'
        rows Start-AZSCEntraExtraction produced from Microsoft Graph.

    Both already live in the same merged $Resources array by the time this runs (Start-
    AZSCExtractionOrchestration merges Entra resources into $Resources right before calling this).
    That is the "collect once" rule the audit set out (AB#6779 and its family): resolving a
    principal ID against data already in memory costs nothing, so a second Graph round trip to
    look each one up individually is never justified.

    THE PERMISSION TRAP THIS EXISTS TO AVOID (see the audit, section 9): Azure RBAC and
    Microsoft Graph are two separate permission systems. A caller can have full Reader access to
    every subscription and management group and have ZERO Graph permissions -- Scout's own
    pre-flight (Get-ScoutGraphPermissionImpact) exists because that combination is common. If
    Graph access was denied, Start-AZSCEntraExtraction still emits an empty 'entra/users' row set
    -- indistinguishable, by row count alone, from a tenant that genuinely has no users. Reporting
    every User-typed assignment as orphaned in that case would manufacture a false, and alarming,
    security finding. QueryOutcomes (Start-AZSCEntraExtraction's other output field, added
    alongside this story) is what breaks the tie: it names, per Graph query, whether the query
    actually SUCCEEDED, independent of how many rows it returned. A principal whose backing query
    never succeeded is reported 'NotAssessed', never 'Orphaned'.

.PARAMETER Resources
    The full, already-merged resource set for this run -- ARM rows, the governance envelope, and
    (when Entra extraction ran) the entra/* principal rows. Returned unchanged in shape; only the
    'AZSC/Governance/RoleAssignment' envelope's `.properties` rows gain two new columns.

.PARAMETER EntraQueryOutcomes
    Start-AZSCEntraExtraction's `QueryOutcomes` output (an array of @{ Type; Name; Success; Count
    }). Optional and defaults to empty, which means "no Entra query is known to have succeeded" --
    the same conservative outcome as an ArmOnly run, a run with no -TenantID, or an Entra
    extraction result from before this story existed. Every role assignment then reports
    'NotAssessed' rather than guessing.

.OUTPUTS
    The SAME $Resources array (returned for convenient chaining), with the 'AZSC/Governance/
    RoleAssignment' envelope's rows carrying two additional fields:

      'Principal Resolution'   -- 'Resolved' | 'Orphaned' | 'NotAssessed'
      'Principal Display Name' -- the resolved object's display/user-principal name, or $null

.NOTES
    Tracks ADO Story AB#6456 (Feature AB#6455, Epic AB#6454).

    Entra GROUP resolution is a first-class case here (Feature AB#6455's own acceptance
    criterion): a Group-typed assignment resolves against 'entra/groups' exactly like a User
    resolves against 'entra/users'. Whether the resolved group HAS members is deliberately left
    unanswered -- Scout does not collect group membership today (the Graph 'list groups' endpoint
    only supports `$expand=members` for small groups, is not paginable, and adding it would be a
    NEW Graph call this story's own "resolve locally, no new calls" constraint rules out). That is
    a real gap, not an oversight, and it is called out rather than faked with a $null-filled column
    of a name nobody asked for.

    ForeignGroup and Device are deliberately NOT resolved against anything: a ForeignGroup is a
    group that lives in a DIFFERENT tenant (cross-tenant/B2B collaboration) and by definition will
    never appear in this tenant's Groups query, so treating a lookup miss as "orphaned" would
    manufacture a false finding against a legitimate assignment. Both report 'NotAssessed'.
#>
function Resolve-ScoutOrphanedRoleAssignment {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Resources,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $EntraQueryOutcomes = @()
    )
    Set-StrictMode -Version Latest

    $Resources = @($Resources | Where-Object { $null -ne $_ })

    # StrictMode-safe, case-insensitive property read. Entra rows carry an uppercase 'TYPE'
    # (Start-AZSCEntraExtraction's Add-NormalizedResource), the governance envelope and ARM rows
    # carry a lowercase 'type' -- a plain `.type` read would silently miss half of $Resources.
    function Get-ScoutOrphanValue {
        param([object] $InputObject, [Parameter(Mandatory)][string] $Name)
        if ($null -eq $InputObject) { return $null }
        $property = $InputObject.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
        if ($null -eq $property) { return $null }
        return $property.Value
    }

    # ---- ARM principalType -> the synthetic Entra type(s) that can resolve it ------------------
    # ARM's own vocabulary (properties.principalType) is exactly: User, Group, ServicePrincipal,
    # ForeignGroup, Device, Unknown. Only the first three have a local dataset to check against;
    # the rest fall through to 'NotAssessed' below, never 'Orphaned'.
    $typeMap = @{
        'user'             = @('entra/users')
        'group'            = @('entra/groups')
        # A managed identity IS a service principal (servicePrincipalType eq 'ManagedIdentity'
        # under the same /servicePrincipals endpoint), so 'entra/managedidentities' is already a
        # subset of 'entra/serviceprincipals'. Both are checked so a caller whose only success was
        # the (rarer) filtered managed-identity query still resolves.
        'serviceprincipal' = @('entra/serviceprincipals', 'entra/managedidentities')
    }

    # ---- which Entra queries are known to have actually succeeded ------------------------------
    $succeededTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($outcome in @($EntraQueryOutcomes)) {
        if ($null -eq $outcome) { continue }
        $type = [string](Get-ScoutOrphanValue $outcome 'Type')
        $success = Get-ScoutOrphanValue $outcome 'Success'
        if (-not [string]::IsNullOrWhiteSpace($type) -and $success -eq $true) {
            [void]$succeededTypes.Add($type)
        }
    }

    function Test-ScoutEntraTypeCollected {
        param([string[]] $Types)
        foreach ($candidate in $Types) {
            if ($succeededTypes.Contains($candidate)) { return $true }
        }
        return $false
    }

    # ---- id -> display name, one lookup table per synthetic Entra type -------------------------
    $entraByType = @{}
    foreach ($resource in @($Resources)) {
        if ($null -eq $resource) { continue }
        $type = [string](Get-ScoutOrphanValue $resource 'TYPE')
        if ([string]::IsNullOrWhiteSpace($type)) { $type = [string](Get-ScoutOrphanValue $resource 'type') }
        if ([string]::IsNullOrWhiteSpace($type) -or $type -notlike 'entra/*') { continue }

        $id = [string](Get-ScoutOrphanValue $resource 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        $key = $type.ToLowerInvariant()
        if (-not $entraByType.ContainsKey($key)) { $entraByType[$key] = @{} }
        $entraByType[$key][$id.ToLowerInvariant()] = [string](Get-ScoutOrphanValue $resource 'name')
    }

    function Resolve-ScoutPrincipal {
        param([string] $PrincipalId, [string] $PrincipalType)

        if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
            return [pscustomobject]@{ Resolution = 'NotAssessed'; DisplayName = $null }
        }

        $normalizedType = if ($PrincipalType) { $PrincipalType.Trim().ToLowerInvariant() } else { '' }
        if (-not $typeMap.ContainsKey($normalizedType)) {
            # ForeignGroup / Device / Unknown / absent -- see .NOTES. This collector cannot answer
            # for these, and "cannot answer" must never render as "orphaned".
            return [pscustomobject]@{ Resolution = 'NotAssessed'; DisplayName = $null }
        }

        $entraTypes = @($typeMap[$normalizedType])
        if (-not (Test-ScoutEntraTypeCollected -Types $entraTypes)) {
            return [pscustomobject]@{ Resolution = 'NotAssessed'; DisplayName = $null }
        }

        $idKey = $PrincipalId.ToLowerInvariant()
        foreach ($entraType in $entraTypes) {
            if ($entraByType.ContainsKey($entraType) -and $entraByType[$entraType].ContainsKey($idKey)) {
                return [pscustomobject]@{ Resolution = 'Resolved'; DisplayName = $entraByType[$entraType][$idKey] }
            }
        }
        return [pscustomobject]@{ Resolution = 'Orphaned'; DisplayName = $null }
    }

    foreach ($envelope in @($Resources)) {
        if ($null -eq $envelope) { continue }
        $envelopeType = [string](Get-ScoutOrphanValue $envelope 'type')
        if ($envelopeType -ine 'AZSC/Governance/RoleAssignment') { continue }

        $rows = @(Get-ScoutOrphanValue $envelope 'properties')
        $enrichedRows = @(
            foreach ($row in $rows) {
                if ($null -eq $row) { continue }
                $principalId = [string](Get-ScoutOrphanValue $row 'Principal ID')
                $principalType = [string](Get-ScoutOrphanValue $row 'Principal Type')
                $result = Resolve-ScoutPrincipal -PrincipalId $principalId -PrincipalType $principalType

                # A fresh object rather than an in-place Add-Member on $row: $row is a row
                # ConvertTo-ScoutGovernanceResource built earlier in the SAME pass, and nothing
                # else holds a reference to it yet, but this keeps the function's own contract --
                # "reads $Resources, does not mutate objects found inside it" -- true even if a
                # future caller re-runs this over rows it is still holding elsewhere.
                $clone = [PSCustomObject]@{}
                foreach ($property in $row.PSObject.Properties) {
                    $clone | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
                }
                $clone | Add-Member -NotePropertyName 'Principal Resolution' -NotePropertyValue $result.Resolution
                $clone | Add-Member -NotePropertyName 'Principal Display Name' -NotePropertyValue $result.DisplayName
                $clone
            }
        )

        # The envelope itself IS mutated -- that is the point. It is the same object the
        # RoleAssignments collector reads out of $Resources by reference, so replacing its
        # `.properties` here is what makes the new columns reach the worksheet without a second
        # collection pass or a second copy of $Resources.
        $envelope.properties = $enrichedRows
    }

    return $Resources
}
