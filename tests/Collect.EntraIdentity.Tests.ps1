#Requires -Version 7.0
#Requires -Modules Pester

<#
    Entra Conditional Access, directory roles and Azure RBAC PIM reach collect.json.

    Identity controls decide who can reach Azure and with what privilege, and two of them were read
    and then thrown away:

      * Azure RBAC PIM eligibility was fetched per subscription by Get-ScoutGovernanceDataset, then
        Invoke-Collect wrote `pimEligibility = @()` and Import-Governance wrote
        `pimEligibilityAvailable = $false`, so every PIM rule read NotAssessed on every run.
      * Entra Conditional Access, named locations and directory roles were collected into
        `entraResources` during the inventory pass and no assessment rule could read them.

    Pinned here:

      1. Get-ScoutRbacScheduleDataset: allow-listed rows (no display name or e-mail), the standing /
         activated / eligible split, de-duplication, and availability that is true ONLY when every
         subscription answered (an empty answer counts), with a reason that carries no id.
      2. Get-ScoutGovernanceDataset and Import-Governance both carry the schedules, and
         Import-Governance does not ask a second time when the collect pass already did.
      3. Get-ScoutConditionalAccessPosture: the computed booleans a JSONPath rule tests, for
         representative policies (MFA for all users on all apps, block legacy authentication,
         administrator MFA, report-only, Azure management, authentication strength, the OR trap,
         AVD excluded), Security Defaults, named locations that keep counts and never ranges, and
         Collected = $false -- never a throw -- when Graph is unreachable or refused.
      4. Get-ScoutDirectoryRolePosture: assignments from inventory rows only, eligibility reported as
         not collected, principal types looked up, no names kept.
      5. Invoke-Collect: the typed-query path and the inventory path carry the SAME keys, ArmOnly and
         offline renders make no Graph call, and a failure the inventory pass already reported is not
         retried.

    Search-AzGraph, Invoke-AZSCGraphRequest and the Azure RBAC schedule cmdlets are mocked throughout.
    No live Azure or Graph connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent

    . "$script:root/tests/helpers/Search-AzGraph.TestDouble.ps1"
    function Import-Module {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub module loading for the test -- this is the point of the shadow.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must accept every argument the code under test passes.')]
        param([Parameter(ValueFromRemainingArguments)] $Rest)
    }

    # Stand-ins so Pester can mock them and nothing reaches Azure. The shadows are unconditional:
    # a retained shadow from another test file may lack a parameter these tests filter on.
    function Get-AzRoleEligibilitySchedule {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the real signature.')]
        [CmdletBinding()] param([string] $Scope)
    }
    function Get-AzRoleAssignmentSchedule {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the real signature.')]
        [CmdletBinding()] param([string] $Scope)
    }
    function Invoke-AzRestMethod {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the real signature.')]
        param([string] $Method, [string] $Path)
    }
    function Invoke-AZSCGraphRequest {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the real signature.')]
        [CmdletBinding()]
        param([string] $Uri, [string] $TenantID, [string[]] $RequiredScopes, [switch] $SinglePage, [switch] $SuppressFailureWarning, [switch] $OptionalRead)
    }
    function Get-ScoutExternalIdentitiesPolicy {
        param([string] $TenantID)
        $null = $TenantID
        [pscustomobject]@{ Collected = $false }
    }
    function Get-ScoutDefenderPlanSweep {
        param([object[]] $Subscriptions)
        $null = $Subscriptions
        return @()
    }

    . "$script:root/src/collect/Get-ScoutRbacScheduleDataset.ps1"
    . "$script:root/src/collect/Get-ScoutGovernanceDataset.ps1"
    . "$script:root/src/collect/ConvertTo-ScoutGovernanceResource.ps1"
    . "$script:root/src/collect/Get-ScoutConditionalAccessPosture.ps1"
    . "$script:root/src/collect/Get-ScoutDirectoryRolePosture.ps1"
    . "$script:root/src/ingest/Import-Governance.ps1"
    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    $script:SubA = '00000000-0000-0000-0000-00000000000a'
    $script:SubB = '00000000-0000-0000-0000-00000000000b'
    $script:SubC = '00000000-0000-0000-0000-00000000000c'
    $script:OwnerGuid = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    $script:ContributorGuid = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
    $script:ReaderGuid = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    $script:AzureManagementApp = '797f4846-ba00-4fd7-ba43-dac1f8f63013'
    $script:AvdApp = '9cdead84-a844-4324-93f2-b2e6bb768d07'

    # What the Az cmdlets return: the principal's display name and e-mail ride along and must NOT
    # reach collect.json.
    function New-ScheduleObject {
        param(
            [string] $Scope, [string] $Id, [string] $RoleGuid = $script:OwnerGuid, [string] $RoleName = 'Owner',
            [string] $PrincipalType = 'User', [string] $PrincipalId = '11111111-aaaa-bbbb-cccc-000000000001',
            [AllowNull()] $End = $null, [string] $AssignmentType
        )
        $row = [ordered]@{
            Id = $Id; PrincipalId = $PrincipalId; PrincipalType = $PrincipalType
            PrincipalDisplayName = 'Alice Example'; PrincipalEmail = 'alice.example@contoso.invalid'
            RoleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/$RoleGuid"
            RoleDefinitionDisplayName = $RoleName; RoleDefinitionType = 'BuiltInRole'
            Scope = $Scope; ScopeType = 'subscription'; MemberType = 'Direct'; Status = 'Provisioned'
            StartDateTime = [datetime]::SpecifyKind([datetime]'2026-01-01T00:00:00', [System.DateTimeKind]::Utc)
            EndDateTime = $End
        }
        if ($AssignmentType) { $row['AssignmentType'] = $AssignmentType }
        [pscustomobject]$row
    }

    function Set-RbacMock {
        param([switch] $EligibilityFailsForSubB, [switch] $SchedulesFailForSubB, [switch] $Empty)
        $script:EligibilityFailsForSubB = [bool]$EligibilityFailsForSubB
        $script:SchedulesFailForSubB = [bool]$SchedulesFailForSubB
        $script:EmptyRbac = [bool]$Empty
        Mock Get-AzRoleEligibilitySchedule {
            if ($script:EligibilityFailsForSubB -and $Scope -match '00000000b$') {
                throw "AuthorizationFailed: no permission over $Scope (client 22222222-3333-4444-5555-666666666666)"
            }
            if ($script:EmptyRbac) { return @() }
            New-ScheduleObject -Scope $Scope -Id "$Scope/providers/Microsoft.Authorization/roleEligibilitySchedules/e1"
        }
        Mock Get-AzRoleAssignmentSchedule {
            if ($script:SchedulesFailForSubB -and $Scope -match '00000000b$') { throw 'ServiceUnavailable' }
            if ($script:EmptyRbac) { return @() }
            New-ScheduleObject -Scope $Scope -Id "$Scope/providers/Microsoft.Authorization/roleAssignmentSchedules/s1" -RoleGuid $script:ContributorGuid -RoleName 'Contributor' -AssignmentType 'Assigned' -PrincipalId '11111111-aaaa-bbbb-cccc-000000000002'
            New-ScheduleObject -Scope $Scope -Id "$Scope/providers/Microsoft.Authorization/roleAssignmentSchedules/s2" -RoleGuid $script:OwnerGuid -RoleName 'Owner' -AssignmentType 'Activated' -End ([datetime]'2026-12-01T08:00:00Z')
        }
    }

    # ---- Conditional Access fixtures: shaped as Microsoft Graph returns them ----------------------
    function ConvertFrom-PolicyJson { param([string] $Json) $Json | ConvertFrom-Json -Depth 20 }
    $script:PolicyMfaAllUsersAllApps = ConvertFrom-PolicyJson '{"id":"ca-1","displayName":"Require MFA for all users","state":"enabled","conditions":{"applications":{"includeApplications":["All"],"excludeApplications":[]},"users":{"includeUsers":["All"],"excludeUsers":["11111111-aaaa-bbbb-cccc-0000000000ee"],"excludeGroups":[],"includeRoles":[]},"clientAppTypes":["all"]},"grantControls":{"operator":"OR","builtInControls":["mfa"]},"sessionControls":null}'
    $script:PolicyBlockLegacy = ConvertFrom-PolicyJson '{"id":"ca-2","displayName":"Block legacy authentication","state":"enabled","conditions":{"applications":{"includeApplications":["All"]},"users":{"includeUsers":["All"]},"clientAppTypes":["exchangeActiveSync","other"]},"grantControls":{"operator":"OR","builtInControls":["block"]}}'
    $script:PolicyAdminMfa = ConvertFrom-PolicyJson '{"id":"ca-3","displayName":"Administrators need MFA and a compliant device","state":"enabled","conditions":{"applications":{"includeApplications":["797f4846-ba00-4fd7-ba43-dac1f8f63013"]},"users":{"includeUsers":[],"includeRoles":["62e90394-69f5-4237-9190-012177145e10"]}},"grantControls":{"operator":"AND","builtInControls":["mfa","compliantDevice"]}}'
    $script:PolicyReportOnly = ConvertFrom-PolicyJson '{"id":"ca-4","displayName":"Report-only MFA","state":"enabledForReportingButNotEnforced","conditions":{"applications":{"includeApplications":["All"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
    $script:PolicyMfaOrCompliant = ConvertFrom-PolicyJson '{"id":"ca-5","displayName":"MFA or compliant device","state":"enabled","conditions":{"applications":{"includeApplications":["9cdead84-a844-4324-93f2-b2e6bb768d07"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa","compliantDevice"]}}'
    $script:PolicyStrengthAvdExcluded = ConvertFrom-PolicyJson '{"id":"ca-6","displayName":"Strength, AVD excluded","state":"enabled","conditions":{"applications":{"includeApplications":["All"],"excludeApplications":["9cdead84-a844-4324-93f2-b2e6bb768d07"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"AND","builtInControls":[],"authenticationStrength":{"id":"00000000-0000-0000-0000-000000000002"}}}'
    $script:PolicyAdminPortals = ConvertFrom-PolicyJson '{"id":"ca-7","displayName":"MFA for admin portals","state":"enabled","conditions":{"applications":{"includeApplications":["MicrosoftAdminPortals"]},"users":{"includeUsers":["All"],"excludeGroups":["11111111-aaaa-bbbb-cccc-0000000000ff"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
    $script:PolicyRiskLocations = ConvertFrom-PolicyJson '{"id":"ca-8","displayName":"Risky sign-ins","state":"enabled","conditions":{"applications":{"includeApplications":["All"]},"users":{"includeUsers":["GuestsOrExternalUsers"]},"signInRiskLevels":["high","medium"],"userRiskLevels":["high"],"locations":{"includeLocations":["All"],"excludeLocations":["AllTrusted"]}},"grantControls":{"operator":"OR","builtInControls":["domainJoinedDevice"]}}'
    $script:PolicySparse = ConvertFrom-PolicyJson '{"id":"ca-9","displayName":"Nothing configured","state":"disabled"}'

    function New-EntraRow {
        param([string] $Type, $Properties)
        [pscustomobject]@{ id = [string]$Properties.id; name = 'row'; TYPE = $Type; tenantId = 'tenant'; properties = $Properties; AZSC = [pscustomobject]@{ Source = 'Microsoft Graph' } }
    }
    function New-Outcome {
        param([string] $Type, [string] $Status, [string] $Reason)
        [pscustomobject]@{ Source = 'Microsoft Graph'; Type = $Type; Status = $Status; Success = ($Status -in 'Success', 'Empty'); Reason = $Reason }
    }
    $script:AllPolicies = @($script:PolicyMfaAllUsersAllApps, $script:PolicyBlockLegacy, $script:PolicyAdminMfa, $script:PolicyReportOnly,
        $script:PolicyMfaOrCompliant, $script:PolicyStrengthAvdExcluded, $script:PolicyAdminPortals, $script:PolicyRiskLocations, $script:PolicySparse)

    function Get-Policy {
        param($Posture, [string] $Id)
        @($Posture.policies | Where-Object { $_.id -eq $Id })[0]
    }

    function Get-PropertyNameTree {
        # The shape of an object: every property name, recursively, with arrays represented by their
        # first element. Used to prove two collect paths carry the same keys.
        param($Value, [string] $Prefix = '')
        if ($null -eq $Value) { return }
        if ($Value -is [string] -or $Value -is [ValueType]) { return }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
            $first = @($Value | Where-Object { $null -ne $_ } | Select-Object -First 1)
            if ($first.Count -gt 0) { Get-PropertyNameTree -Value $first[0] -Prefix $Prefix }
            return
        }
        foreach ($property in $Value.PSObject.Properties) {
            $path = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }
            $path
            Get-PropertyNameTree -Value $property.Value -Prefix $path
        }
    }
}

Describe 'Get-ScoutRbacScheduleDataset' {
    It 'reads eligibility and assignment schedules for every subscription and marks both answered' {
        Set-RbacMock
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA, $script:SubB, $script:SubC) -WarningAction SilentlyContinue

        @($result.pimEligibility).Count | Should -Be 3
        @($result.roleAssignmentSchedules).Count | Should -Be 6
        $result.pimEligibilityAvailable | Should -BeTrue
        $result.pimEligibilityReason | Should -BeNullOrEmpty
        $result.roleAssignmentSchedulesMeasured | Should -BeTrue
        $result.privilegedAccessMeasured | Should -BeTrue
        Should -Invoke Get-AzRoleEligibilitySchedule -Times 3 -Exactly
        Should -Invoke Get-AzRoleAssignmentSchedule -Times 3 -Exactly
        @($result.sourceOperations).Count | Should -Be 6
    }

    It 'treats an empty answer from every subscription as an answer, not as unavailable' {
        Set-RbacMock -Empty
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA, $script:SubB)

        @($result.pimEligibility).Count | Should -Be 0
        $result.pimEligibilityAvailable | Should -BeTrue
        $result.privilegedAccessMeasured | Should -BeTrue
        @($result.sourceOperations | Where-Object Status -eq 'Empty').Count | Should -Be 4
    }

    It 'is NOT available when one subscription refuses, says why, and never names the subscription' {
        Set-RbacMock -EligibilityFailsForSubB
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA, $script:SubB, $script:SubC) -WarningAction SilentlyContinue

        $result.pimEligibilityAvailable | Should -BeFalse
        $result.pimEligibilityReason | Should -Match 'failed for 1 of 3 subscription'
        $result.pimEligibilityReason | Should -Not -Match '[0-9a-f]{8}-[0-9a-f]{4}-'
        $result.privilegedAccessMeasured | Should -BeFalse
        # The two subscriptions that answered keep their rows.
        @($result.pimEligibility).Count | Should -Be 2
        $result.roleAssignmentSchedulesMeasured | Should -BeTrue
        @($result.sourceOperations | Where-Object { $_.Status -eq 'Unavailable' -and $_.Operation -eq 'Get-AzRoleEligibilitySchedule' }).Count | Should -Be 1
    }

    It 'a refused assignment-schedule read leaves eligibility available but the privileged-access measure closed' {
        Set-RbacMock -SchedulesFailForSubB
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA, $script:SubB) -WarningAction SilentlyContinue

        $result.pimEligibilityAvailable | Should -BeTrue
        $result.roleAssignmentSchedulesMeasured | Should -BeFalse
        $result.roleAssignmentSchedulesReason | Should -Match 'role assignment schedule read failed for 1 of 2'
        $result.privilegedAccessMeasured | Should -BeFalse
    }

    It 'with no subscription there is nothing to read and nothing is claimed available' {
        Set-RbacMock
        $result = Get-ScoutRbacScheduleDataset
        $result.pimEligibilityAvailable | Should -BeFalse
        $result.pimEligibilityReason | Should -Match 'No subscription'
        @($result.pimEligibility).Count | Should -Be 0
        Should -Invoke Get-AzRoleEligibilitySchedule -Times 0 -Exactly
    }

    It 'keeps an allow-list: no display name or e-mail address reaches the output' {
        Set-RbacMock
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA)
        $json = $result | ConvertTo-Json -Depth 8

        $json | Should -Not -Match 'Alice'
        $json | Should -Not -Match 'contoso\.invalid'
        $names = @($result.pimEligibility[0].PSObject.Properties.Name)
        $names | Should -Not -Contain 'principalDisplayName'
        $names | Should -Not -Contain 'principalEmail'
        $names | Should -Contain 'principalId'
        $names | Should -Contain 'roleDefinitionName'
    }

    It 'flags privileged roles, tells standing from activated access, and dates in UTC' {
        Set-RbacMock
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA)
        $eligible = $result.pimEligibility[0]
        $standing = @($result.roleAssignmentSchedules | Where-Object accessType -eq 'Standing')[0]
        $activated = @($result.roleAssignmentSchedules | Where-Object accessType -eq 'Activated')[0]

        $eligible.accessType | Should -Be 'Eligible'
        $eligible.privilegedRole | Should -BeTrue
        $eligible.scopeType | Should -Be 'subscription'
        $standing.roleDefinitionName | Should -Be 'Contributor'
        $standing.privilegedRole | Should -BeTrue
        $standing.permanent | Should -BeTrue
        $standing.assignmentType | Should -Be 'Assigned'
        $activated.permanent | Should -BeFalse
        $activated.endDateTime | Should -Match '^2026-12-01T08:00:00'
        $eligible.startDateTime | Should -Match '^2026-01-01T00:00:00.*Z$'
    }

    It 'does not call a Reader assignment privileged' {
        Mock Get-AzRoleEligibilitySchedule { @() }
        Mock Get-AzRoleAssignmentSchedule {
            New-ScheduleObject -Scope $Scope -Id 'r1' -RoleGuid $script:ReaderGuid -RoleName 'Reader' -AssignmentType 'Assigned'
        }
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA)
        $result.roleAssignmentSchedules[0].privilegedRole | Should -BeFalse
    }

    It 'returns a schedule inherited from a management group once, however many subscriptions list it' {
        Mock Get-AzRoleEligibilitySchedule {
            New-ScheduleObject -Scope '/providers/Microsoft.Management/managementGroups/mg-root' -Id '/providers/Microsoft.Management/managementGroups/mg-root/providers/Microsoft.Authorization/roleEligibilitySchedules/shared'
        }
        Mock Get-AzRoleAssignmentSchedule { @() }
        $result = Get-ScoutRbacScheduleDataset -SubscriptionId @($script:SubA, $script:SubB, $script:SubC)

        @($result.pimEligibility).Count | Should -Be 1
        $result.pimEligibility[0].scopeType | Should -Be 'managementGroup'
        $result.pimEligibilityAvailable | Should -BeTrue
    }
}

Describe 'Get-ScoutGovernanceDataset carries the Azure RBAC schedules' {
    BeforeEach {
        Mock Search-AzGraph { return @() }
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 404; Content = '{}' } }
    }

    It 'returns normalised eligibility rows and the flags instead of discarding them' {
        Set-RbacMock
        $subscriptions = @([pscustomobject]@{ id = $script:SubA }, [pscustomobject]@{ id = $script:SubB })
        $dataset = Get-ScoutGovernanceDataset -Subscriptions $subscriptions -WarningAction SilentlyContinue

        @($dataset.pimEligibility).Count | Should -Be 2
        $dataset.pimEligibility[0].roleDefinitionName | Should -Be 'Owner'
        $dataset.pimEligibilityAvailable | Should -BeTrue
        @($dataset.roleAssignmentSchedules).Count | Should -Be 4
        $dataset.privilegedAccessMeasured | Should -BeTrue
        @($dataset.sourceOperations | Where-Object Dataset -eq 'PIM role eligibility schedules').Count | Should -Be 2
    }

    It 'reports not available when a subscription could not be read, without failing the dataset' {
        Set-RbacMock -EligibilityFailsForSubB
        $subscriptions = @([pscustomobject]@{ id = $script:SubA }, [pscustomobject]@{ id = $script:SubB })
        $dataset = Get-ScoutGovernanceDataset -Subscriptions $subscriptions -WarningAction SilentlyContinue

        $dataset.pimEligibilityAvailable | Should -BeFalse
        $dataset.pimEligibilityReason | Should -Not -BeNullOrEmpty
        @($dataset.pimEligibility).Count | Should -Be 1
    }

    It 'still feeds the PIM worksheet envelope, case-insensitively, with no name in it' {
        Set-RbacMock
        $subscriptions = @([pscustomobject]@{ id = $script:SubA; name = 'sub-alpha' })
        $dataset = Get-ScoutGovernanceDataset -Subscriptions $subscriptions
        $envelope = @(ConvertTo-ScoutGovernanceResource -Governance $dataset -Subscriptions $subscriptions | Where-Object type -eq 'AZSC/Governance/PimEligibility')[0]

        @($envelope.properties).Count | Should -Be 1
        $envelope.properties[0].'Principal ID' | Should -Be '11111111-aaaa-bbbb-cccc-000000000001'
        $envelope.properties[0].'Principal Type' | Should -Be 'User'
        $envelope.properties[0].'Role Definition ID' | Should -Match $script:OwnerGuid
        $envelope.properties[0].Subscription | Should -Be 'sub-alpha'
        ($envelope | ConvertTo-Json -Depth 6) | Should -Not -Match 'Alice'
    }
}

Describe 'Import-Governance carries the Azure RBAC schedules' {
    BeforeEach {
        Mock Search-AzGraph { return @() }
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 404; Content = '{}' } }
        $script:Collect = [pscustomobject]@{ subscriptions = @([pscustomobject]@{ id = $script:SubA }, [pscustomobject]@{ id = $script:SubB }) }
    }

    It 'reads the schedules itself when the collect pass did not (the -Source TypedQueries path)' {
        Set-RbacMock
        $result = Import-Governance -Collect $script:Collect -WarningAction SilentlyContinue

        @($result.governance.pimEligibility).Count | Should -Be 2
        $result.governance.pimEligibilityAvailable | Should -BeTrue
        @($result.governance.roleAssignmentSchedules).Count | Should -Be 4
        $result.governance.roleAssignmentSchedulesMeasured | Should -BeTrue
        $result.governance.privilegedAccessMeasured | Should -BeTrue
        Should -Invoke Get-AzRoleEligibilitySchedule -Times 2 -Exactly
    }

    It 'reports not available, with the reason, when a subscription refuses' {
        Set-RbacMock -EligibilityFailsForSubB
        $result = Import-Governance -Collect $script:Collect -WarningAction SilentlyContinue

        $result.governance.pimEligibilityAvailable | Should -BeFalse
        $result.governance.pimEligibilityReason | Should -Match 'failed for 1 of 2'
    }

    It 'reuses what the collect pass already read and does not ask Azure again' {
        Set-RbacMock
        $row = [pscustomobject]@{ id = 'e1'; principalId = 'p'; privilegedRole = $true; accessType = 'Eligible' }
        $script:Collect | Add-Member -NotePropertyName governance -NotePropertyValue ([pscustomobject]@{
                rbacSchedulesRead = $true
                pimEligibility = @($row); pimEligibilityAvailable = $true; pimEligibilityReason = $null
                roleAssignmentSchedules = @(); roleAssignmentSchedulesMeasured = $true; roleAssignmentSchedulesReason = $null
                privilegedAccessMeasured = $true
            })
        $result = Import-Governance -Collect $script:Collect -WarningAction SilentlyContinue

        @($result.governance.pimEligibility).Count | Should -Be 1
        $result.governance.pimEligibilityAvailable | Should -BeTrue
        $result.governance.privilegedAccessMeasured | Should -BeTrue
        Should -Invoke Get-AzRoleEligibilitySchedule -Times 0 -Exactly
        Should -Invoke Get-AzRoleAssignmentSchedule -Times 0 -Exactly
    }

    It 'keeps a reused read that was NOT available as not available' {
        Set-RbacMock
        $script:Collect | Add-Member -NotePropertyName governance -NotePropertyValue ([pscustomobject]@{
                rbacSchedulesRead = $true
                pimEligibility = @(); pimEligibilityAvailable = $false; pimEligibilityReason = 'refused'
                roleAssignmentSchedules = @(); roleAssignmentSchedulesMeasured = $false; roleAssignmentSchedulesReason = 'refused'
                privilegedAccessMeasured = $false
            })
        $result = Import-Governance -Collect $script:Collect -WarningAction SilentlyContinue

        $result.governance.pimEligibilityAvailable | Should -BeFalse
        $result.governance.pimEligibilityReason | Should -Be 'refused'
        Should -Invoke Get-AzRoleEligibilitySchedule -Times 0 -Exactly
    }
}

Describe 'Get-ScoutConditionalAccessPosture -- computed booleans' {
    BeforeAll {
        $rows = @($script:AllPolicies | ForEach-Object { New-EntraRow -Type 'entra/conditionalaccesspolicies' -Properties $_ })
        $script:Posture = Get-ScoutConditionalAccessPosture -TenantID 't' -EntraResources $rows `
            -EntraQueryOutcomes @(New-Outcome -Type 'entra/conditionalaccesspolicies' -Status 'Success') -SkipGraph
    }

    It 'collects every policy from the inventory rows with no Graph call' {
        $script:Posture.Collected | Should -BeTrue
        $script:Posture.Reason | Should -BeNullOrEmpty
        @($script:Posture.policies).Count | Should -Be 9
    }

    It 'MFA for all users on all apps: enabled, requires MFA, all users, all apps, Azure management, AVD, exclusions' {
        $p = Get-Policy $script:Posture 'ca-1'
        $p.enabled | Should -BeTrue
        $p.reportOnly | Should -BeFalse
        $p.requiresMfa | Should -BeTrue
        $p.targetsAllUsers | Should -BeTrue
        $p.targetsAllApps | Should -BeTrue
        $p.hasAppExclusions | Should -BeFalse
        $p.targetsAzureManagement | Should -BeTrue
        $p.targetsAvd | Should -BeTrue
        $p.hasExclusions | Should -BeTrue -Because 'a user is excluded (the break-glass pattern)'
        $p.blocks | Should -BeFalse
    }

    It 'block legacy authentication: blocks, and only blocksLegacyAuth when the clients are legacy ones' {
        $legacy = Get-Policy $script:Posture 'ca-2'
        $legacy.blocks | Should -BeTrue
        $legacy.blocksLegacyAuth | Should -BeTrue
        $legacy.requiresMfa | Should -BeFalse
        (Get-Policy $script:Posture 'ca-1').blocksLegacyAuth | Should -BeFalse
    }

    It 'administrator MFA: targets directory roles and Azure management, requires MFA and a compliant device' {
        $p = Get-Policy $script:Posture 'ca-3'
        $p.targetsDirectoryRoles | Should -BeTrue
        $p.targetsAllUsers | Should -BeFalse
        $p.targetsAzureManagement | Should -BeTrue
        $p.targetsAdminPortals | Should -BeFalse
        $p.requiresMfa | Should -BeTrue
        $p.requiresCompliantOrHybridDevice | Should -BeTrue
    }

    It 'report-only is not enabled, so it never satisfies an "enabled policy requires MFA" check' {
        $p = Get-Policy $script:Posture 'ca-4'
        $p.enabled | Should -BeFalse
        $p.reportOnly | Should -BeTrue
        $p.requiresMfa | Should -BeTrue -Because 'the grant control is MFA; the rules gate on enabled separately'
    }

    It 'MFA OR compliant device does not require MFA (the user may choose the other control) and does not require a device either' {
        $p = Get-Policy $script:Posture 'ca-5'
        $p.requiresMfa | Should -BeFalse
        $p.requiresCompliantOrHybridDevice | Should -BeFalse
        $p.targetsAvd | Should -BeTrue
    }

    It 'an authentication strength counts as MFA, and excluding the AVD app clears targetsAvd while all apps stays true' {
        $p = Get-Policy $script:Posture 'ca-6'
        $p.requiresMfa | Should -BeTrue
        $p.targetsAllApps | Should -BeTrue
        $p.hasAppExclusions | Should -BeTrue
        $p.targetsAvd | Should -BeFalse
        $p.targetsAzureManagement | Should -BeTrue
    }

    It 'the Microsoft Admin Portals grouping is the portal only: targetsAdminPortals, not targetsAzureManagement' {
        $p = Get-Policy $script:Posture 'ca-7'
        $p.targetsAdminPortals | Should -BeTrue
        $p.targetsAzureManagement | Should -BeFalse
        $p.targetsAvd | Should -BeFalse
        $p.hasExclusions | Should -BeTrue -Because 'a group is excluded'
    }

    It 'reads risk levels, locations, guests and a hybrid-joined-device requirement' {
        $p = Get-Policy $script:Posture 'ca-8'
        $p.usesSignInRisk | Should -BeTrue
        $p.usesUserRisk | Should -BeTrue
        $p.usesLocations | Should -BeTrue
        $p.targetsGuests | Should -BeTrue
        $p.targetsAllUsers | Should -BeFalse
        $p.requiresCompliantOrHybridDevice | Should -BeTrue
    }

    It 'a disabled policy with no conditions or grant controls reads all false and never throws' {
        $p = Get-Policy $script:Posture 'ca-9'
        $p.enabled | Should -BeFalse
        foreach ($name in 'requiresMfa', 'blocks', 'targetsAllUsers', 'targetsAllApps', 'targetsAzureManagement', 'targetsAvd', 'usesSignInRisk', 'hasExclusions') {
            $p.$name | Should -BeFalse -Because $name
        }
    }

    It 'keeps the raw conditions, grant controls and session controls next to the booleans' {
        $p = Get-Policy $script:Posture 'ca-1'
        $p.conditions.applications.includeApplications | Should -Contain 'All'
        $p.grantControls.builtInControls | Should -Contain 'mfa'
        $p.PSObject.Properties.Name | Should -Contain 'sessionControls'
        $p.displayName | Should -Be 'Require MFA for all users'
    }

    It 'answers a JSONPath rule filter the way the rules use it' {
        $json = [pscustomobject]@{ domains = [pscustomobject]@{ identity = [pscustomobject]@{ conditionalAccess = $script:Posture } } } | ConvertTo-Json -Depth 30
        $token = [Newtonsoft.Json.Linq.JToken]::Parse($json)
        $mfaAllAllApps = @($token.SelectTokens('$.domains.identity.conditionalAccess.policies[?(@.enabled == true && @.requiresMfa == true && @.targetsAllUsers == true && @.targetsAllApps == true && @.hasAppExclusions == false)]', $false))
        $avd = @($token.SelectTokens('$.domains.identity.conditionalAccess.policies[?(@.enabled == true && @.requiresMfa == true && @.targetsAvd == true)]', $false))

        $mfaAllAllApps.Count | Should -Be 1
        $mfaAllAllApps[0].SelectToken('id').ToString() | Should -Be 'ca-1'
        # ca-1 (all apps) and nothing else: ca-5 allows an alternative to MFA, ca-6 excludes AVD, ca-4 is report-only.
        @($avd | ForEach-Object { $_.SelectToken('id').ToString() }) | Should -Be @('ca-1')
    }
}

Describe 'Get-ScoutConditionalAccessPosture -- Security Defaults, named locations, sources' {
    It 'Security Defaults on: one policy-shaped coverage row, real policies untouched' {
        Mock Invoke-AZSCGraphRequest {
            switch -Wildcard ($Uri) {
                '*identitySecurityDefaultsEnforcementPolicy' { [pscustomobject]@{ isEnabled = $true } }
                '*conditionalAccess/policies' { @() }
                '*conditionalAccess/namedLocations' { @() }
            }
        }
        $posture = Get-ScoutConditionalAccessPosture -TenantID 't'

        $posture.Collected | Should -BeTrue
        $posture.securityDefaultsEnabled | Should -BeTrue
        $posture.baselineAssessable | Should -BeTrue
        @($posture.policies).Count | Should -Be 0
        @($posture.securityDefaultsCoverage).Count | Should -Be 1
        $row = $posture.securityDefaultsCoverage[0]
        $row.source | Should -Be 'SecurityDefaults'
        $row.requiresMfa | Should -BeTrue
        $row.targetsAzureManagement | Should -BeTrue
        $row.targetsAllUsers | Should -BeTrue
        $row.blocksLegacyAuth | Should -BeTrue
        $row.targetsAllApps | Should -BeFalse -Because 'Security defaults require MFA when necessary, not on every app'
        $row.targetsAvd | Should -BeFalse
    }

    It 'Security Defaults off: no coverage row, and the flag is false rather than null' {
        Mock Invoke-AZSCGraphRequest {
            switch -Wildcard ($Uri) {
                '*identitySecurityDefaultsEnforcementPolicy' { [pscustomobject]@{ isEnabled = $false } }
                default { @() }
            }
        }
        $posture = Get-ScoutConditionalAccessPosture -TenantID 't'
        $posture.securityDefaultsEnabled | Should -BeFalse
        $posture.baselineAssessable | Should -BeTrue -Because 'Security defaults are known to be off, so "no policy" is a real answer'
        @($posture.securityDefaultsCoverage).Count | Should -Be 0
    }

    It 'Security Defaults unreadable: the flag is null and no coverage is claimed, but Conditional Access still collected' {
        Mock Invoke-AZSCGraphRequest {
            switch -Wildcard ($Uri) {
                '*identitySecurityDefaultsEnforcementPolicy' { throw 'Forbidden' }
                default { @() }
            }
        }
        $posture = Get-ScoutConditionalAccessPosture -TenantID 't'
        $posture.Collected | Should -BeTrue
        $posture.securityDefaultsEnabled | Should -BeNullOrEmpty
        $posture.baselineAssessable | Should -BeFalse -Because 'no enabled policy and Security defaults unknown: "protected by policy or by Security defaults" has no answer'
        @($posture.securityDefaultsCoverage).Count | Should -Be 0
    }

    It 'an enabled policy makes the baseline assessable even when Security Defaults cannot be read (the two cannot coexist)' {
        Mock Invoke-AZSCGraphRequest {
            switch -Wildcard ($Uri) {
                '*identitySecurityDefaultsEnforcementPolicy' { throw 'Forbidden' }
                '*conditionalAccess/policies' { $script:PolicyMfaAllUsersAllApps }
                default { @() }
            }
        }
        $posture = Get-ScoutConditionalAccessPosture -TenantID 't'
        $posture.securityDefaultsEnabled | Should -BeNullOrEmpty
        $posture.baselineAssessable | Should -BeTrue
    }

    It 'named locations keep counts and never the address ranges' {
        $ip = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; id = 'nl-1'; displayName = 'HQ'; isTrusted = $true
            ipRanges = @([pscustomobject]@{ cidrAddress = '203.0.113.0/24' }, [pscustomobject]@{ cidrAddress = '198.51.100.7/32' }) }
        $country = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.countryNamedLocation'; id = 'nl-2'; displayName = 'Allowed countries'
            countriesAndRegions = @('US', 'CA', 'GB'); includeUnknownCountriesAndRegions = $false }
        $rows = @(
            New-EntraRow -Type 'entra/conditionalaccesspolicies' -Properties $script:PolicyMfaAllUsersAllApps
            New-EntraRow -Type 'entra/namedlocations' -Properties $ip
            New-EntraRow -Type 'entra/namedlocations' -Properties $country
        )
        $posture = Get-ScoutConditionalAccessPosture -EntraResources $rows -SkipGraph -EntraQueryOutcomes @(
            New-Outcome -Type 'entra/conditionalaccesspolicies' -Status 'Success'
            New-Outcome -Type 'entra/namedlocations' -Status 'Success')

        $posture.namedLocationsCollected | Should -BeTrue
        @($posture.namedLocations).Count | Should -Be 2
        $hq = @($posture.namedLocations | Where-Object id -eq 'nl-1')[0]
        $hq.locationType | Should -Be 'ip'
        $hq.isTrusted | Should -BeTrue
        $hq.ipRangeCount | Should -Be 2
        @($posture.namedLocations | Where-Object id -eq 'nl-2')[0].countryCount | Should -Be 3
        ($posture | ConvertTo-Json -Depth 20) | Should -Not -Match '203\.0\.113|198\.51\.100'
    }

    It 'an empty answer from the inventory pass is a real answer: Collected, zero policies' {
        $posture = Get-ScoutConditionalAccessPosture -EntraResources @() -SkipGraph `
            -EntraQueryOutcomes @(New-Outcome -Type 'entra/conditionalaccesspolicies' -Status 'Empty')
        $posture.Collected | Should -BeTrue
        @($posture.policies).Count | Should -Be 0
    }

    It 'a query the inventory pass reported as failed is NOT retried and is reported as not collected' {
        Mock Invoke-AZSCGraphRequest { throw 'must not be called: the inventory pass already reported this failure' }
        $posture = Get-ScoutConditionalAccessPosture -TenantID 't' -EntraResources @() -EntraQueryOutcomes @(
            New-Outcome -Type 'entra/organization' -Status 'Success'
            New-Outcome -Type 'entra/conditionalaccesspolicies' -Status 'Failed' -Reason 'Forbidden')

        $posture.Collected | Should -BeFalse
        $posture.Reason | Should -Match 'Failed'
        $posture.Reason | Should -Match 'Forbidden'
        Should -Invoke Invoke-AZSCGraphRequest -Times 0 -Exactly
    }

    It 'reads Graph directly when the inventory pass never ran Entra' {
        Mock Invoke-AZSCGraphRequest {
            switch -Wildcard ($Uri) {
                '*conditionalAccess/policies' { $script:PolicyMfaAllUsersAllApps }
                '*identitySecurityDefaultsEnforcementPolicy' { [pscustomobject]@{ isEnabled = $false } }
                default { @() }
            }
        }
        $posture = Get-ScoutConditionalAccessPosture -TenantID 'target-tenant'

        $posture.Collected | Should -BeTrue
        @($posture.policies).Count | Should -Be 1
        Should -Invoke Invoke-AZSCGraphRequest -Times 3 -Exactly
        Should -Invoke Invoke-AZSCGraphRequest -ParameterFilter { $TenantID -eq 'target-tenant' } -Times 3 -Exactly
    }

    It 'Collected is $false with a reason -- never a throw -- when Graph throws, and the reason carries no id' {
        Mock Invoke-AZSCGraphRequest { throw 'Forbidden: caller 33333333-4444-5555-6666-777777777777 lacks Policy.Read.All' }
        { Get-ScoutConditionalAccessPosture -TenantID 't' } | Should -Not -Throw
        $posture = Get-ScoutConditionalAccessPosture -TenantID 't'

        $posture.Collected | Should -BeFalse
        $posture.Reason | Should -Match 'Policy.Read.All'
        $posture.Reason | Should -Not -Match '33333333-4444'
        @($posture.policies).Count | Should -Be 0
        @($posture.namedLocations).Count | Should -Be 0
        @($posture.securityDefaultsCoverage).Count | Should -Be 0
        $posture.securityDefaultsEnabled | Should -BeNullOrEmpty
    }

    It 'makes no Graph call and says why when told to skip it' {
        Mock Invoke-AZSCGraphRequest { throw 'must not be called' }
        $posture = Get-ScoutConditionalAccessPosture -SkipGraph -SkipReason 'ArmOnly scope'
        $posture.Collected | Should -BeFalse
        $posture.baselineAssessable | Should -BeFalse
        $posture.Reason | Should -Be 'ArmOnly scope'
        Should -Invoke Invoke-AZSCGraphRequest -Times 0 -Exactly
    }
}

Describe 'Get-ScoutDirectoryRolePosture' {
    BeforeAll {
        $script:UserId = '44444444-aaaa-bbbb-cccc-000000000001'
        $script:GroupId = '44444444-aaaa-bbbb-cccc-000000000002'
        $script:SpId = '44444444-aaaa-bbbb-cccc-000000000003'
        $script:EntraRows = @(
            New-EntraRow -Type 'entra/pimassignments' -Properties ([pscustomobject]@{ id = 'ra1'; principalId = $script:UserId; directoryScopeId = '/'; roleDefinitionId = 'gl-admin'; roleDefinition = [pscustomobject]@{ id = 'gl-admin'; displayName = 'Global Administrator' } })
            New-EntraRow -Type 'entra/pimassignments' -Properties ([pscustomobject]@{ id = 'ra2'; principalId = $script:SpId; directoryScopeId = '/'; roleDefinitionId = 'sec-admin'; roleDefinition = [pscustomobject]@{ id = 'sec-admin'; displayName = 'Security Administrator' } })
            New-EntraRow -Type 'entra/pimassignments' -Properties ([pscustomobject]@{ id = 'ra3'; principalId = 'not-in-any-set'; directoryScopeId = '/'; roleDefinitionId = 'x'; roleDefinition = $null })
            New-EntraRow -Type 'entra/users' -Properties ([pscustomobject]@{ id = $script:UserId; displayName = 'Carol Example'; userPrincipalName = 'carol@contoso.invalid' })
            New-EntraRow -Type 'entra/groups' -Properties ([pscustomobject]@{ id = $script:GroupId; displayName = 'Platform Admins' })
            New-EntraRow -Type 'entra/serviceprincipals' -Properties ([pscustomobject]@{ id = $script:SpId; displayName = 'deploy-pipeline' })
        )
    }

    It 'shapes assignments, looks the principal type up and keeps no name' {
        $result = Get-ScoutDirectoryRolePosture -EntraResources $script:EntraRows -EntraQueryOutcomes @(
            New-Outcome -Type 'entra/pimassignments' -Status 'Success'
            New-Outcome -Type 'entra/roleeligibilityschedules' -Status 'NotAssessed' -Reason 'The selected user token does not contain the delegated scope')

        $result.Collected | Should -BeTrue
        @($result.assignments).Count | Should -Be 3
        $global = @($result.assignments | Where-Object roleName -eq 'Global Administrator')[0]
        $global.principalType | Should -Be 'User'
        $global.directoryScopeId | Should -Be '/'
        @($result.assignments | Where-Object roleName -eq 'Security Administrator')[0].principalType | Should -Be 'ServicePrincipal'
        @($result.assignments | Where-Object principalId -eq 'not-in-any-set')[0].principalType | Should -BeNullOrEmpty
        $json = $result | ConvertTo-Json -Depth 8
        $json | Should -Not -Match 'Carol'
        $json | Should -Not -Match 'contoso\.invalid'
        $json | Should -Not -Match 'deploy-pipeline'
    }

    It 'reports eligibility as NOT collected (with the reason) when the delegated scope was missing' {
        $result = Get-ScoutDirectoryRolePosture -EntraResources $script:EntraRows -EntraQueryOutcomes @(
            New-Outcome -Type 'entra/pimassignments' -Status 'Success'
            New-Outcome -Type 'entra/roleeligibilityschedules' -Status 'NotAssessed' -Reason 'The selected user token does not contain the delegated scope')

        $result.eligibilityCollected | Should -BeFalse
        $result.eligibilityReason | Should -Match 'NotAssessed'
        @($result.eligibility).Count | Should -Be 0
    }

    It 'shapes eligibility when it was read' {
        $rows = @($script:EntraRows) + @(New-EntraRow -Type 'entra/roleeligibilityschedules' -Properties ([pscustomobject]@{
                    id = 'el1'; principalId = $script:UserId; directoryScopeId = '/'; roleDefinitionId = 'gl-admin'; status = 'Provisioned'; memberType = 'Direct'
                    roleDefinition = [pscustomobject]@{ displayName = 'Global Administrator' }
                    scheduleInfo = [pscustomobject]@{ expiration = [pscustomobject]@{ type = 'afterDateTime'; endDateTime = '2027-01-01T00:00:00Z' } } }))
        $result = Get-ScoutDirectoryRolePosture -EntraResources $rows -EntraQueryOutcomes @(
            New-Outcome -Type 'entra/pimassignments' -Status 'Success'
            New-Outcome -Type 'entra/roleeligibilityschedules' -Status 'Success')

        $result.eligibilityCollected | Should -BeTrue
        @($result.eligibility).Count | Should -Be 1
        $result.eligibility[0].roleName | Should -Be 'Global Administrator'
        $result.eligibility[0].endDateTime | Should -Be '2027-01-01T00:00:00Z'
        $result.eligibility[0].principalType | Should -Be 'User'
    }

    It 'is not collected, with a reason, when the inventory pass did not run Entra or the query failed' {
        $none = Get-ScoutDirectoryRolePosture -EntraResources @() -EntraQueryOutcomes @()
        $none.Collected | Should -BeFalse
        $none.Reason | Should -Match 'did not run'

        $failed = Get-ScoutDirectoryRolePosture -EntraResources @() -EntraQueryOutcomes @(New-Outcome -Type 'entra/pimassignments' -Status 'Failed' -Reason 'Forbidden')
        $failed.Collected | Should -BeFalse
        $failed.Reason | Should -Match 'Failed'
        @($failed.assignments).Count | Should -Be 0
    }
}

Describe 'Invoke-Collect -- domains.identity and governance carry the same keys on both paths' {
    BeforeAll {
        function global:Search-AzGraph {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow must accept the production signature.')]
            param([string] $Query, [int] $First, [int] $Skip, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            return @()
        }
        $script:GovernanceDataset = [pscustomobject]@{
            roleAssignments = @(); roleDefinitions = @(); policyAssignments = @(); budgets = @(); resourceLocks = @()
            pimEligibility = @([pscustomobject]@{ id = 'e1'; principalId = 'p'; principalType = 'User'; roleDefinitionName = 'Owner'; privilegedRole = $true; accessType = 'Eligible' })
            pimEligibilityAvailable = $true; pimEligibilityReason = $null
            roleAssignmentSchedules = @([pscustomobject]@{ id = 's1'; principalId = 'p'; principalType = 'User'; roleDefinitionName = 'Contributor'; privilegedRole = $true; accessType = 'Standing'; permanent = $true })
            roleAssignmentSchedulesMeasured = $true; roleAssignmentSchedulesReason = $null; privilegedAccessMeasured = $true
            sourceOperations = @()
        }
        function Get-Inventory {
            param([switch] $WithEntra, [switch] $CaFailed)
            $inventory = [pscustomobject]@{
                Resources = @(); ResourceContainers = @()
                Governance = $script:GovernanceDataset
            }
            if ($WithEntra) {
                $rows = @(
                    New-EntraRow -Type 'entra/conditionalaccesspolicies' -Properties $script:PolicyMfaAllUsersAllApps
                    New-EntraRow -Type 'entra/pimassignments' -Properties ([pscustomobject]@{ id = 'ra1'; principalId = 'u1'; directoryScopeId = '/'; roleDefinitionId = 'gl'; roleDefinition = [pscustomobject]@{ displayName = 'Global Administrator' } })
                )
                $outcomes = @(
                    New-Outcome -Type 'entra/conditionalaccesspolicies' -Status $(if ($CaFailed) { 'Failed' } else { 'Success' }) -Reason $(if ($CaFailed) { 'Forbidden' })
                    New-Outcome -Type 'entra/namedlocations' -Status 'Empty'
                    New-Outcome -Type 'entra/pimassignments' -Status 'Success'
                )
                if ($CaFailed) { $rows = @($rows | Where-Object { $_.TYPE -ne 'entra/conditionalaccesspolicies' }) }
                $inventory | Add-Member -NotePropertyName EntraResources -NotePropertyValue $rows
                $inventory | Add-Member -NotePropertyName EntraQueryOutcomes -NotePropertyValue $outcomes
            }
            return $inventory
        }
    }
    AfterAll { Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue }

    BeforeEach {
        Mock Invoke-AZSCGraphRequest {
            switch -Wildcard ($Uri) {
                '*conditionalAccess/policies' { $script:PolicyMfaAllUsersAllApps }
                '*identitySecurityDefaultsEnforcementPolicy' { [pscustomobject]@{ isEnabled = $false } }
                default { @() }
            }
        }
    }

    It 'the typed-query path and the inventory path produce the same conditionalAccess, directoryRoles and governance keys' {
        $typed = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue
        $inventory = Invoke-Collect -FromInventory (Get-Inventory -WithEntra) -WarningAction SilentlyContinue

        foreach ($path in 'conditionalAccess', 'directoryRoles') {
            $typedKeys = @(Get-PropertyNameTree -Value $typed.domains.identity.$path | Sort-Object -Unique)
            $inventoryKeys = @(Get-PropertyNameTree -Value $inventory.domains.identity.$path | Sort-Object -Unique)
            # The inventory path carries rows for the arrays the typed path leaves empty, so compare the
            # top-level keys exactly and the row keys the typed path can show.
            @($typed.domains.identity.$path.PSObject.Properties.Name) | Should -Be @($inventory.domains.identity.$path.PSObject.Properties.Name)
            @($typedKeys | Where-Object { $_ -notin $inventoryKeys }) | Should -BeNullOrEmpty -Because "every key the typed path shows for $path must exist on the inventory path"
        }
        $governanceKeys = 'pimEligibility', 'pimEligibilityAvailable', 'pimEligibilityReason', 'roleAssignmentSchedules',
        'roleAssignmentSchedulesMeasured', 'roleAssignmentSchedulesReason', 'privilegedAccessMeasured', 'rbacSchedulesRead', 'classicAdministrators'
        foreach ($key in $governanceKeys) {
            $typed.governance.PSObject.Properties.Name | Should -Contain $key
            $inventory.governance.PSObject.Properties.Name | Should -Contain $key
        }
        @($typed.governance.PSObject.Properties.Name) | Should -Be @($inventory.governance.PSObject.Properties.Name)
    }

    It 'the inventory path uses the inventory rows without a second Graph read, and reuses the governance schedules' {
        $collect = Invoke-Collect -FromInventory (Get-Inventory -WithEntra) -WarningAction SilentlyContinue

        $collect.domains.identity.conditionalAccess.Collected | Should -BeTrue
        @($collect.domains.identity.conditionalAccess.policies).Count | Should -Be 1
        @($collect.domains.identity.directoryRoles.assignments).Count | Should -Be 1
        $collect.domains.identity.directoryRoles.eligibilityCollected | Should -BeFalse
        # No Conditional Access, named-location or directory-role call: only Security Defaults is read directly.
        Should -Invoke Invoke-AZSCGraphRequest -Times 1 -Exactly
        Should -Invoke Invoke-AZSCGraphRequest -ParameterFilter { $Uri -like '*identitySecurityDefaultsEnforcementPolicy' } -Times 1 -Exactly
        $collect.governance.pimEligibilityAvailable | Should -BeTrue
        @($collect.governance.pimEligibility).Count | Should -Be 1
        $collect.governance.rbacSchedulesRead | Should -BeTrue
        $collect.governance.privilegedAccessMeasured | Should -BeTrue
    }

    It 'the typed-query path reads Conditional Access from Graph and says the schedules were not read in this pass' {
        $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

        $collect.domains.identity.conditionalAccess.Collected | Should -BeTrue
        @($collect.domains.identity.conditionalAccess.policies).Count | Should -Be 1
        $collect.domains.identity.directoryRoles.Collected | Should -BeFalse
        $collect.governance.rbacSchedulesRead | Should -BeFalse
        $collect.governance.pimEligibilityAvailable | Should -BeFalse
        $collect.governance.pimEligibilityReason | Should -Match 'inventory pass or the Governance ingest'
    }

    It 'a Conditional Access failure the inventory pass already reported is not retried' {
        $collect = Invoke-Collect -FromInventory (Get-Inventory -WithEntra -CaFailed) -WarningAction SilentlyContinue

        $collect.domains.identity.conditionalAccess.Collected | Should -BeFalse
        $collect.domains.identity.conditionalAccess.Reason | Should -Match 'Forbidden'
        Should -Invoke Invoke-AZSCGraphRequest -Times 0 -Exactly
    }

    It '-Scope ArmOnly makes no Graph call and reports Conditional Access as not collected, with the reason' {
        $collect = Invoke-Collect -Source TypedQueries -Scope ArmOnly -WarningAction SilentlyContinue

        $collect.domains.identity.conditionalAccess.Collected | Should -BeFalse
        $collect.domains.identity.conditionalAccess.Reason | Should -Match 'ArmOnly'
        @($collect.domains.identity.conditionalAccess.policies).Count | Should -Be 0
        Should -Invoke Invoke-AZSCGraphRequest -Times 0 -Exactly
    }

    It 'an offline render uses the inventory rows and still makes no Graph call' {
        $collect = Invoke-Collect -OfflineFromInventory -FromInventory (Get-Inventory -WithEntra) -WarningAction SilentlyContinue

        $collect.domains.identity.conditionalAccess.Collected | Should -BeTrue
        @($collect.domains.identity.conditionalAccess.policies).Count | Should -Be 1
        $collect.domains.identity.conditionalAccess.securityDefaultsEnabled | Should -BeNullOrEmpty
        Should -Invoke Invoke-AZSCGraphRequest -Times 0 -Exactly
    }

    It 'an offline render with no Entra rows reports not collected rather than Graph' {
        $collect = Invoke-Collect -OfflineFromInventory -FromInventory (Get-Inventory) -WarningAction SilentlyContinue

        $collect.domains.identity.conditionalAccess.Collected | Should -BeFalse
        $collect.domains.identity.conditionalAccess.Reason | Should -Match 'offline'
        Should -Invoke Invoke-AZSCGraphRequest -Times 0 -Exactly
    }

    It 'never fails the collect when Graph throws, and never omits the keys' {
        Mock Invoke-AZSCGraphRequest { throw 'simulated Graph outage' }
        $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

        $collect.domains.identity.PSObject.Properties.Name | Should -Contain 'conditionalAccess'
        $collect.domains.identity.PSObject.Properties.Name | Should -Contain 'directoryRoles'
        $collect.domains.identity.conditionalAccess.Collected | Should -BeFalse
        $collect.domains.identity.conditionalAccess.Reason | Should -Match 'Graph'
    }

    It 'writes no display name of a person into collect.json' {
        $inventory = Get-Inventory -WithEntra
        $inventory.EntraResources += @(New-EntraRow -Type 'entra/users' -Properties ([pscustomobject]@{ id = 'u1'; displayName = 'Dana Example'; userPrincipalName = 'dana@contoso.invalid' }))
        $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue
        $json = $collect.domains.identity | ConvertTo-Json -Depth 30

        $json | Should -Not -Match 'Dana'
        $json | Should -Not -Match 'contoso\.invalid'
        ($collect.governance | ConvertTo-Json -Depth 10) | Should -Not -Match 'Alice'
    }
}
