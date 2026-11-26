#Requires -Version 7.0
#Requires -Modules Pester, powershell-yaml

<#
    Identity items in the Azure assessments that are scored from Entra Conditional Access and Azure
    RBAC PIM data instead of being left Manual.

    The data side is in tests/Collect.EntraIdentity.Tests.ps1. This file pins the RULE side, using the
    real rule files and the real collectors' output as fixtures (so a rule query that the collector's
    shape would never satisfy fails here, not on a live tenant):

      CAF-IDN-04   a Conditional Access baseline is enforced (enabled policy, MFA, all users)
      CAF-BIL-02   MFA is required for all users on Azure management (policy OR Security defaults)
      WAF-AVD-SE-01 / WAF-AVDAZ-SE-06   MFA is required for Azure Virtual Desktop
      APPMOD-SEC-02   MFA for all users on all cloud apps with no app excluded
      CAF-IDN-02 / CGOV-SC-05   PIM eligibility exists
      CAF-IDN-05   the privileged-user share that is eligible rather than standing

    For every one: Pass on a compliant fixture, Fail on a non-compliant one, and NotAssessed -- never
    Fail -- when the data was not collected. The evidence-only manual items stay Manual, never Fail.

    No Azure or Graph connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module powershell-yaml -ErrorAction Stop

    function Import-Module {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub module loading for the test -- this is the point of the shadow.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must accept every argument the code under test passes.')]
        param([Parameter(ValueFromRemainingArguments)] $Rest)
    }

    . "$script:root/src/assess/engine/Get-RuleSet.ps1"
    . "$script:root/src/assess/engine/Resolve-JsonPath.ps1"
    . "$script:root/src/assess/engine/Resolve-RuleJoin.ps1"
    . "$script:root/src/assess/engine/Invoke-Rule.ps1"
    . "$script:root/src/collect/Get-ScoutRbacScheduleDataset.ps1"
    . "$script:root/src/collect/Get-ScoutConditionalAccessPosture.ps1"

    # ---- stand-ins for the data sources: plain functions that read script variables ----------------
    function Invoke-AZSCGraphRequest {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must declare the real signature.')]
        [CmdletBinding()]
        param([string] $Uri, [string] $TenantID, [string[]] $RequiredScopes, [switch] $SinglePage, [switch] $SuppressFailureWarning, [switch] $OptionalRead)
        switch -Wildcard ($Uri) {
            '*conditionalAccess/policies' { $script:FixturePolicies }
            '*namedLocations' { @() }
            '*identitySecurityDefaultsEnforcementPolicy' {
                # $null models a reader whose role cannot read Security defaults (403), seen live.
                if ($null -eq $script:FixtureSecurityDefaults) { throw 'Forbidden' }
                [pscustomobject]@{ isEnabled = $script:FixtureSecurityDefaults }
            }
        }
    }
    function Get-AzRoleEligibilitySchedule {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must declare the real signature.')]
        [CmdletBinding()] param([string] $Scope)
        if ($script:FixtureFailEligibility) { throw 'AuthorizationFailed' }
        for ($i = 0; $i -lt $script:FixtureEligible.Count; $i++) { New-ScheduleObject -Scope $Scope -Spec $script:FixtureEligible[$i] -Index $i -Prefix 'e' }
    }
    function Get-AzRoleAssignmentSchedule {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must declare the real signature.')]
        [CmdletBinding()] param([string] $Scope)
        for ($i = 0; $i -lt $script:FixtureSchedules.Count; $i++) { New-ScheduleObject -Scope $Scope -Spec $script:FixtureSchedules[$i] -Index $i -Prefix 's' }
    }
    function New-ScheduleObject {
        param([string] $Scope, $Spec, [int] $Index, [string] $Prefix)
        $guids = @{ Owner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; Reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' }
        # Indexer reads: a missing key on a hashtable is a StrictMode error through dot syntax.
        $role = if ($Spec['Role']) { $Spec['Role'] } else { 'Owner' }
        $row = [ordered]@{
            Id = "$Scope/$Prefix$Index"; PrincipalId = "principal-$Prefix$Index"
            PrincipalType = $(if ($Spec['Type']) { $Spec['Type'] } else { 'User' })
            RoleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/$($guids[$role])"; RoleDefinitionDisplayName = $role
            Scope = $Scope; ScopeType = 'subscription'; MemberType = 'Direct'; Status = 'Provisioned'
            StartDateTime = [datetime]'2026-01-01T00:00:00Z'; EndDateTime = $Spec['End']
        }
        if ($Spec['Assignment']) { $row['AssignmentType'] = $Spec['Assignment'] }
        [pscustomobject]$row
    }

    # ---- policies, as Graph returns them -------------------------------------------------------------
    function ConvertFrom-PolicyJson { param([string] $Json) $Json | ConvertFrom-Json -Depth 20 }
    $script:Policies = @{
        MfaAllUsersAllApps = ConvertFrom-PolicyJson '{"id":"p-all","displayName":"MFA all users all apps","state":"enabled","conditions":{"applications":{"includeApplications":["All"]},"users":{"includeUsers":["All"],"excludeUsers":["11111111-aaaa-bbbb-cccc-0000000000ee"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
        MfaAzureMgmtAllUsers = ConvertFrom-PolicyJson '{"id":"p-mgmt","displayName":"MFA Azure management","state":"enabled","conditions":{"applications":{"includeApplications":["797f4846-ba00-4fd7-ba43-dac1f8f63013"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
        MfaAvdGroup = ConvertFrom-PolicyJson '{"id":"p-avd","displayName":"MFA AVD users","state":"enabled","conditions":{"applications":{"includeApplications":["9cdead84-a844-4324-93f2-b2e6bb768d07"]},"users":{"includeUsers":[],"includeGroups":["11111111-aaaa-bbbb-cccc-0000000000aa"]}},"grantControls":{"operator":"AND","builtInControls":["mfa"]}}'
        MfaAdminRolesMgmt = ConvertFrom-PolicyJson '{"id":"p-admin","displayName":"MFA administrators","state":"enabled","conditions":{"applications":{"includeApplications":["797f4846-ba00-4fd7-ba43-dac1f8f63013"]},"users":{"includeUsers":[],"includeRoles":["62e90394-69f5-4237-9190-012177145e10"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
        ReportOnlyAll = ConvertFrom-PolicyJson '{"id":"p-report","displayName":"Report-only MFA","state":"enabledForReportingButNotEnforced","conditions":{"applications":{"includeApplications":["All"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
        MfaOrCompliantAll = ConvertFrom-PolicyJson '{"id":"p-or","displayName":"MFA or compliant device","state":"enabled","conditions":{"applications":{"includeApplications":["All"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa","compliantDevice"]}}'
        AdminPortalsAllUsers = ConvertFrom-PolicyJson '{"id":"p-portal","displayName":"MFA admin portals","state":"enabled","conditions":{"applications":{"includeApplications":["MicrosoftAdminPortals"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
        MfaAllAppsExceptOne = ConvertFrom-PolicyJson '{"id":"p-except","displayName":"MFA all apps except one","state":"enabled","conditions":{"applications":{"includeApplications":["All"],"excludeApplications":["00000003-0000-0ff1-ce00-000000000000"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
        MfaAllAppsExceptAvd = ConvertFrom-PolicyJson '{"id":"p-noavd","displayName":"MFA all apps except AVD","state":"enabled","conditions":{"applications":{"includeApplications":["All"],"excludeApplications":["9cdead84-a844-4324-93f2-b2e6bb768d07"]},"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["mfa"]}}'
    }

    # What the collector does with them, end to end through the Graph path.
    function New-IdentityCollect {
        param([string[]] $Policy = @(), [switch] $SecurityDefaults, [switch] $SecurityDefaultsUnreadable, [switch] $NotCollected, [switch] $WithAvd)
        $script:FixturePolicies = @($Policy | ForEach-Object { $script:Policies[$_] })
        $script:FixtureSecurityDefaults = if ($SecurityDefaultsUnreadable) { $null } else { [bool]$SecurityDefaults }
        $posture = if ($NotCollected) { Get-ScoutConditionalAccessPosture -SkipGraph -SkipReason 'Graph was not read' }
                   else { Get-ScoutConditionalAccessPosture -TenantID 'tenant' }
        $collect = [ordered]@{
            domains = [ordered]@{ identity = [ordered]@{ conditionalAccess = $posture } }
            compute = [ordered]@{ avdHostPools = @(if ($WithAvd) { [ordered]@{ id = 'hp1'; hostPoolType = 'Pooled' } }) }
        }
        $collect
    }

    function New-PimCollect {
        param([object[]] $Eligible = @(), [object[]] $Schedules = @(), [switch] $FailEligibility)
        $script:FixtureEligible = @($Eligible)
        $script:FixtureSchedules = @($Schedules)
        $script:FixtureFailEligibility = [bool]$FailEligibility
        $dataset = Get-ScoutRbacScheduleDataset -SubscriptionId @('00000000-0000-0000-0000-000000000001') -WarningAction SilentlyContinue
        [ordered]@{
            governance = [ordered]@{
                pimEligibility = $dataset.pimEligibility; pimEligibilityAvailable = $dataset.pimEligibilityAvailable
                roleAssignmentSchedules = $dataset.roleAssignmentSchedules; roleAssignmentSchedulesMeasured = $dataset.roleAssignmentSchedulesMeasured
                privilegedAccessMeasured = $dataset.privilegedAccessMeasured
            }
        }
    }

    $script:RuleSets = @{}
    function Get-TestRuleSet {
        param([string] $Pattern)
        if (-not $script:RuleSets.ContainsKey($Pattern)) { $script:RuleSets[$Pattern] = @(Get-RuleSet -Patterns $Pattern)[0] }
        $script:RuleSets[$Pattern]
    }
    function Invoke-TestRule {
        param([string] $Pattern, [string] $Id, $Collect)
        $set = Get-TestRuleSet -Pattern $Pattern
        $rule = @($set.Rules | Where-Object { $_.id -eq $Id })[0]
        if ($null -eq $rule) { throw "rule $Id is not in $Pattern" }
        Invoke-Rule -Rule $rule -Collect ([pscustomobject]$Collect) -Area $set.Area -Framework $set.Framework
    }
}

Describe 'Conditional Access rules score from domains.identity.conditionalAccess' {
    Context 'CAF-IDN-04: a Conditional Access baseline is enforced' {
        It 'passes with an enabled MFA policy for all users (<Policy>)' -ForEach @(
            @{ Policy = 'MfaAllUsersAllApps' }
            @{ Policy = 'MfaAzureMgmtAllUsers' }
        ) {
            $f = Invoke-TestRule 'caf.identity' 'CAF-IDN-04' (New-IdentityCollect -Policy $Policy)
            $f.Status | Should -Be 'Pass'
            $f.Manual | Should -BeFalse
            $f.EvidenceCount | Should -Be 1
        }

        It 'fails when no enabled policy requires MFA for all users (<Name>)' -ForEach @(
            @{ Name = 'no policy at all'; Policy = @() }
            @{ Name = 'report-only'; Policy = @('ReportOnlyAll') }
            @{ Name = 'MFA or a compliant device'; Policy = @('MfaOrCompliantAll') }
            @{ Name = 'administrators only'; Policy = @('MfaAdminRolesMgmt') }
            @{ Name = 'one group only'; Policy = @('MfaAvdGroup') }
        ) {
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-04' (New-IdentityCollect -Policy $Policy)).Status | Should -Be 'Fail'
        }

        It 'a tenant protected only by Security defaults fails: the item is about Conditional Access' {
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-04' (New-IdentityCollect -SecurityDefaults)).Status | Should -Be 'Fail'
        }

        It 'reads NotAssessed, never Fail, when Conditional Access was not collected' {
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-04' (New-IdentityCollect -NotCollected)).Status | Should -Be 'NotAssessed'
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-04' ([ordered]@{})).Status | Should -Be 'NotAssessed'
        }
    }

    Context 'CAF-BIL-02: MFA is required for all users on Azure management' {
        It 'passes with an enabled policy for all users on Azure management or all apps (<Policy>)' -ForEach @(
            @{ Policy = 'MfaAllUsersAllApps' }
            @{ Policy = 'MfaAzureMgmtAllUsers' }
        ) {
            (Invoke-TestRule 'caf.billing' 'CAF-BIL-02' (New-IdentityCollect -Policy $Policy)).Status | Should -Be 'Pass'
        }

        It 'passes on Security defaults alone, which require MFA for Azure management' {
            $f = Invoke-TestRule 'caf.billing' 'CAF-BIL-02' (New-IdentityCollect -SecurityDefaults)
            $f.Status | Should -Be 'Pass'
            $f.Evidence[0].source.ToString() | Should -Be 'SecurityDefaults'
        }

        It 'fails when the policy is administrators only, the admin-portals grouping, report-only, or MFA-or-device (<Name>)' -ForEach @(
            @{ Name = 'no policy'; Policy = @() }
            @{ Name = 'administrators only'; Policy = @('MfaAdminRolesMgmt') }
            @{ Name = 'admin portals only'; Policy = @('AdminPortalsAllUsers') }
            @{ Name = 'report-only'; Policy = @('ReportOnlyAll') }
            @{ Name = 'MFA or a compliant device'; Policy = @('MfaOrCompliantAll') }
            @{ Name = 'AVD only'; Policy = @('MfaAvdGroup') }
        ) {
            (Invoke-TestRule 'caf.billing' 'CAF-BIL-02' (New-IdentityCollect -Policy $Policy)).Status | Should -Be 'Fail'
        }

        It 'reads NotAssessed, never Fail, when Conditional Access was not collected' {
            (Invoke-TestRule 'caf.billing' 'CAF-BIL-02' (New-IdentityCollect -NotCollected)).Status | Should -Be 'NotAssessed'
        }

        It 'reads NotAssessed, never Fail, with no policy when Security defaults cannot be read: the tenant may be protected by them' {
            $collect = New-IdentityCollect -SecurityDefaultsUnreadable
            $collect.domains.identity.conditionalAccess.Collected | Should -BeTrue
            $collect.domains.identity.conditionalAccess.baselineAssessable | Should -BeFalse
            (Invoke-TestRule 'caf.billing' 'CAF-BIL-02' $collect).Status | Should -Be 'NotAssessed'
        }

        It 'still scores when Security defaults cannot be read but a policy decides the answer (<Policy>)' -ForEach @(
            @{ Policy = 'MfaAllUsersAllApps'; Expected = 'Pass' }
            @{ Policy = 'MfaAdminRolesMgmt'; Expected = 'Fail' }
        ) {
            # Security defaults and enabled policies cannot coexist, so an enabled policy settles the question.
            (Invoke-TestRule 'caf.billing' 'CAF-BIL-02' (New-IdentityCollect -Policy @($Policy) -SecurityDefaultsUnreadable)).Status | Should -Be $Expected
        }
    }

    Context 'AVD: <Pattern> <Id>' -ForEach @(
        @{ Pattern = 'waf.avd'; Id = 'WAF-AVD-SE-01' }
        @{ Pattern = 'waf.avd.azure'; Id = 'WAF-AVDAZ-SE-06' }
    ) {
        It 'passes when an enabled policy requires MFA for the AVD app (<Policy>)' -ForEach @(
            @{ Policy = 'MfaAvdGroup' }
            @{ Policy = 'MfaAllUsersAllApps' }
            @{ Policy = 'MfaAllAppsExceptOne' }
        ) {
            $f = Invoke-TestRule $Pattern $Id (New-IdentityCollect -Policy $Policy -WithAvd)
            $f.Status | Should -Be 'Pass'
            $f.Manual | Should -BeFalse
        }

        It 'fails when nothing enforced requires MFA for the AVD app (<Name>)' -ForEach @(
            @{ Name = 'no policy'; Policy = @() }
            @{ Name = 'report-only'; Policy = @('ReportOnlyAll') }
            @{ Name = 'MFA or a compliant device'; Policy = @('MfaOrCompliantAll') }
            @{ Name = 'administrators on Azure management only'; Policy = @('MfaAdminRolesMgmt') }
            @{ Name = 'all apps but the AVD app excluded'; Policy = @('MfaAllAppsExceptAvd') }
        ) {
            (Invoke-TestRule $Pattern $Id (New-IdentityCollect -Policy $Policy -WithAvd)).Status | Should -Be 'Fail'
        }

        It 'does not accept Security defaults for the AVD app' {
            (Invoke-TestRule $Pattern $Id (New-IdentityCollect -SecurityDefaults -WithAvd)).Status | Should -Be 'Fail'
        }

        It 'reads NotAssessed when Conditional Access was not collected, even with AVD present' {
            (Invoke-TestRule $Pattern $Id (New-IdentityCollect -NotCollected -WithAvd)).Status | Should -Be 'NotAssessed'
        }

        It 'reads NotAssessed on an estate with no AVD host pools, even with Conditional Access collected' {
            (Invoke-TestRule $Pattern $Id (New-IdentityCollect -Policy @('MfaAllUsersAllApps'))).Status | Should -Be 'NotAssessed'
            (Invoke-TestRule $Pattern $Id (New-IdentityCollect)).Status | Should -Be 'NotAssessed'
        }
    }

    Context 'APPMOD-SEC-02: MFA for all users on all cloud apps, no app excluded' {
        It 'passes with an enabled all-users all-apps MFA policy' {
            (Invoke-TestRule 'appmod.readiness' 'APPMOD-SEC-02' (New-IdentityCollect -Policy @('MfaAllUsersAllApps'))).Status | Should -Be 'Pass'
        }

        It 'fails when the policy excludes an app, covers one app, is report-only, or does not exist (<Name>)' -ForEach @(
            @{ Name = 'an app is excluded'; Policy = @('MfaAllAppsExceptOne') }
            @{ Name = 'Azure management only'; Policy = @('MfaAzureMgmtAllUsers') }
            @{ Name = 'report-only'; Policy = @('ReportOnlyAll') }
            @{ Name = 'no policy'; Policy = @() }
        ) {
            (Invoke-TestRule 'appmod.readiness' 'APPMOD-SEC-02' (New-IdentityCollect -Policy $Policy)).Status | Should -Be 'Fail'
        }

        It 'reads NotAssessed when Conditional Access was not collected' {
            (Invoke-TestRule 'appmod.readiness' 'APPMOD-SEC-02' (New-IdentityCollect -NotCollected)).Status | Should -Be 'NotAssessed'
        }
    }
}

Describe 'PIM rules score from the Azure RBAC schedules' {
    Context 'PIM eligibility exists: <Pattern> <Id>' -ForEach @(
        @{ Pattern = 'caf.identity'; Id = 'CAF-IDN-02' }
        @{ Pattern = 'caf.govern.sc'; Id = 'CGOV-SC-05' }
    ) {
        It 'passes when an eligible assignment exists' {
            $f = Invoke-TestRule $Pattern $Id (New-PimCollect -Eligible @(@{ Role = 'Owner' }))
            $f.Status | Should -Be 'Pass'
            $f.EvidenceCount | Should -Be 1
        }

        It 'fails when every subscription answered and none is eligible' {
            (Invoke-TestRule $Pattern $Id (New-PimCollect)).Status | Should -Be 'Fail'
        }

        It 'reads NotAssessed, never Fail, when a subscription could not be read' {
            (Invoke-TestRule $Pattern $Id (New-PimCollect -FailEligibility)).Status | Should -Be 'NotAssessed'
        }

        It 'reads NotAssessed on a collect with no governance data at all' {
            (Invoke-TestRule $Pattern $Id ([ordered]@{})).Status | Should -Be 'NotAssessed'
        }
    }

    Context 'CAF-IDN-05: the privileged-user share that is eligible rather than standing' {
        It 'passes when eligible privileged users are the majority (2 eligible, 1 standing)' {
            $f = Invoke-TestRule 'caf.identity' 'CAF-IDN-05' (New-PimCollect `
                    -Eligible @(@{ Role = 'Owner' }, @{ Role = 'Contributor' }) `
                    -Schedules @(@{ Role = 'Owner'; Assignment = 'Assigned' }))
            $f.Status | Should -Be 'Pass'
            $f.EvidenceCount | Should -Be 2
            $f.Denominator | Should -Be 3
        }

        It 'is Partial when some, not most, privileged user access is eligible (1 eligible, 3 standing)' {
            $f = Invoke-TestRule 'caf.identity' 'CAF-IDN-05' (New-PimCollect `
                    -Eligible @(@{ Role = 'Owner' }) `
                    -Schedules @(@{ Role = 'Owner'; Assignment = 'Assigned' }, @{ Role = 'Owner'; Assignment = 'Assigned' }, @{ Role = 'Contributor'; Assignment = 'Assigned' }))
            $f.Status | Should -Be 'Partial'
            $f.Denominator | Should -Be 4
        }

        It 'fails when privileged user access is all standing' {
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-05' (New-PimCollect -Schedules @(@{ Role = 'Owner'; Assignment = 'Assigned' }))).Status | Should -Be 'Fail'
        }

        It 'does not count an activated assignment twice: it is an eligible assignment someone elevated into' {
            $f = Invoke-TestRule 'caf.identity' 'CAF-IDN-05' (New-PimCollect `
                    -Eligible @(@{ Role = 'Owner' }) `
                    -Schedules @(@{ Role = 'Owner'; Assignment = 'Activated'; End = [datetime]'2026-12-01T00:00:00Z' }, @{ Role = 'Owner'; Assignment = 'Activated'; End = [datetime]'2026-12-01T00:00:00Z' }))
            $f.Status | Should -Be 'Pass'
            $f.Denominator | Should -Be 1
        }

        It 'ignores roles that are not privileged and principals that are not users' {
            $f = Invoke-TestRule 'caf.identity' 'CAF-IDN-05' (New-PimCollect `
                    -Eligible @(@{ Role = 'Owner' }, @{ Role = 'Reader' }) `
                    -Schedules @(@{ Role = 'Reader'; Assignment = 'Assigned' }, @{ Role = 'Owner'; Type = 'Group'; Assignment = 'Assigned' }, @{ Role = 'Owner'; Type = 'ServicePrincipal'; Assignment = 'Assigned' }))
            $f.Status | Should -Be 'Pass'
            $f.EvidenceCount | Should -Be 1
            $f.Denominator | Should -Be 1
        }

        It 'reads NotAssessed, not Fail, when there is no privileged user access at all' {
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-05' (New-PimCollect)).Status | Should -Be 'NotAssessed'
        }

        It 'reads NotAssessed when either schedule read was refused' {
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-05' (New-PimCollect -FailEligibility)).Status | Should -Be 'NotAssessed'
            $collect = New-PimCollect -Eligible @(@{ Role = 'Owner' })
            $collect.governance.privilegedAccessMeasured = $false
            (Invoke-TestRule 'caf.identity' 'CAF-IDN-05' $collect).Status | Should -Be 'NotAssessed'
        }
    }
}

Describe 'Evidence-only identity items stay Manual and never Fail' {
    BeforeAll {
        $script:StandingOwner = @{ Role = 'Owner'; Assignment = 'Assigned' }
    }

    It '<Id> attaches Conditional Access evidence and stays Manual' -ForEach @(
        @{ Pattern = 'caf.billing'; Id = 'CAF-BIL-01'; Policy = 'MfaAllUsersAllApps'; Because = 'an enabled all-users policy that excludes a user is the break-glass pattern' }
        @{ Pattern = 'caf.govern.sc'; Id = 'CGOV-SC-03'; Policy = 'MfaAllUsersAllApps'; Because = 'it requires MFA for all users' }
        @{ Pattern = 'casa.security'; Id = 'CASA-PM-01'; Policy = 'MfaAzureMgmtAllUsers'; Because = 'an enabled policy requires MFA' }
        @{ Pattern = 'waf.golive'; Id = 'WAF-GOLIVE-SE-05'; Policy = 'MfaAvdGroup'; Because = 'an enabled policy requires MFA' }
    ) {
        $with = Invoke-TestRule $Pattern $Id (New-IdentityCollect -Policy @($Policy))
        $with.Status | Should -Be 'Manual'
        $with.Manual | Should -BeTrue
        $with.EvidenceCount | Should -BeGreaterThan 0 -Because $Because

        $without = Invoke-TestRule $Pattern $Id (New-IdentityCollect -NotCollected)
        $without.Status | Should -Be 'Manual'
        $without.EvidenceCount | Should -Be 0
        (Invoke-TestRule $Pattern $Id ([ordered]@{})).Status | Should -Be 'Manual'
    }

    It 'CAF-BIL-01 does not offer a report-only or exclusion-free policy as break-glass evidence' {
        $f = Invoke-TestRule 'caf.billing' 'CAF-BIL-01' (New-IdentityCollect -Policy @('ReportOnlyAll', 'MfaAzureMgmtAllUsers'))
        $f.EvidenceCount | Should -Be 0
    }

    It '<Id> attaches permanent, standing privileged assignments and stays Manual' -ForEach @(
        @{ Pattern = 'waf.missioncritical'; Id = 'WAF-MC-SE-09' }
        @{ Pattern = 'ai.readiness'; Id = 'AIRDY-GS-10' }
    ) {
        $collect = New-PimCollect -Schedules @($script:StandingOwner, @{ Role = 'Owner'; Assignment = 'Activated'; End = [datetime]'2026-12-01T00:00:00Z' }, @{ Role = 'Owner'; Type = 'ServicePrincipal'; Assignment = 'Assigned' }, @{ Role = 'Reader'; Assignment = 'Assigned' })
        $f = Invoke-TestRule $Pattern $Id $collect
        $f.Status | Should -Be 'Manual'
        $f.EvidenceCount | Should -Be 1 -Because 'only the permanent standing privileged assignment held by a user qualifies'
        (Invoke-TestRule $Pattern $Id ([ordered]@{})).Status | Should -Be 'Manual'
    }

    It 'WAF-AVS-SEC-01 attaches only permanent, standing Contributor assignments' {
        $collect = New-PimCollect -Schedules @(@{ Role = 'Contributor'; Assignment = 'Assigned' }, @{ Role = 'Owner'; Assignment = 'Assigned' }, @{ Role = 'Contributor'; Assignment = 'Assigned'; End = [datetime]'2026-12-01T00:00:00Z' })
        $f = Invoke-TestRule 'avs.workload' 'WAF-AVS-SEC-01' $collect
        $f.Status | Should -Be 'Manual'
        $f.EvidenceCount | Should -Be 1
    }
}

Describe 'Invoke-Rule accepts a list of gates, every one of which must be open' {
    BeforeAll {
        function Test-Gate {
            param($Collect, [string[]] $Gate)
            $rule = @{ id = 'T-01'; title = 'T-01. t'; severity = 'low'; query = '$.rows[*]'; assert = @{ type = 'exists'; gate = $Gate }; remediation = 'T-01. r'; manual = $false }
            (Invoke-Rule -Rule $rule -Collect ([pscustomobject]$Collect) -Area 'a' -Framework 'f').Status
        }
    }

    It 'evaluates the rule when every gate is open' {
        Test-Gate ([ordered]@{ a = [ordered]@{ ok = $true }; b = @(1); rows = @(1) }) @('$.a.ok', '$.b[*]') | Should -Be 'Pass'
        Test-Gate ([ordered]@{ a = [ordered]@{ ok = $true }; b = @(1); rows = @() }) @('$.a.ok', '$.b[*]') | Should -Be 'Fail'
    }

    It 'reads NotAssessed when ANY gate is closed (<Name>)' -ForEach @(
        @{ Name = 'first is false'; Collect = [ordered]@{ a = [ordered]@{ ok = $false }; b = @(1); rows = @(1) } }
        @{ Name = 'second has no rows'; Collect = [ordered]@{ a = [ordered]@{ ok = $true }; b = @(); rows = @(1) } }
        @{ Name = 'both closed'; Collect = [ordered]@{ a = [ordered]@{ ok = $false }; b = @(); rows = @(1) } }
    ) {
        Test-Gate $Collect @('$.a.ok', '$.b[*]') | Should -Be 'NotAssessed'
    }

    It 'keeps a single string gate working exactly as before' {
        $rule = @{ id = 'T-02'; title = 'T-02. t'; severity = 'low'; query = '$.rows[*]'; assert = @{ type = 'exists'; gate = '$.a.ok' }; remediation = 'T-02. r'; manual = $false }
        (Invoke-Rule -Rule $rule -Collect ([pscustomobject]@{ a = [pscustomobject]@{ ok = $false }; rows = @(1) }) -Area 'a' -Framework 'f').Status | Should -Be 'NotAssessed'
        (Invoke-Rule -Rule $rule -Collect ([pscustomobject]@{ a = [pscustomobject]@{ ok = $true }; rows = @(1) }) -Area 'a' -Framework 'f').Status | Should -Be 'Pass'
    }

    It 'a YAML gate list reaches the engine as a list' {
        $rule = @((Get-TestRuleSet 'waf.avd.azure').Rules | Where-Object { $_.id -eq 'WAF-AVDAZ-SE-06' })[0]
        @($rule.assert.gate).Count | Should -Be 2
        @($rule.assert.gate) | Should -Contain '$.domains.identity.conditionalAccess.Collected'
    }
}

Describe 'The converted rule files keep their conventions and no longer claim the data is missing' {
    BeforeAll {
        $script:RuleDir = Join-Path $script:root 'src/assess/rules'
        $script:RuleText = (Get-ChildItem $script:RuleDir -Filter '*.yaml' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
    }

    It '<File> titles and remediations start with the rule id' -ForEach @(
        @{ File = 'waf.avd.yaml' }
        @{ File = 'waf.avd.azure.yaml' }
        @{ File = 'appmod.readiness.yaml' }
        @{ File = 'waf.missioncritical.yaml' }
        @{ File = 'waf.golive.yaml' }
        @{ File = 'ai.readiness.yaml' }
        @{ File = 'casa.security.yaml' }
    ) {
        $doc = ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir $File) -Raw)
        foreach ($r in @($doc.rules | Where-Object { $_.id -match '^(WAF-AVD-SE-01|WAF-AVDAZ-SE-06|APPMOD-SEC-02|WAF-MC-SE-09|WAF-GOLIVE-SE-05|WAF-AVS-SEC-01|AIRDY-GS-10)$' })) {
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
        }
    }

    It 'WAF-AVS-SEC-01 cites its own id in the remediation' {
        $doc = ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir 'avs.workload.yaml') -Raw)
        $r = @($doc.rules | Where-Object { $_.id -eq 'WAF-AVS-SEC-01' })[0]
        $r.remediation | Should -BeLike 'WAF-AVS-SEC-01. *'
    }

    It 'every converted automated rule is gated, and a gate names Collected or an availability flag' {
        $converted = @{
            'caf.identity' = 'CAF-IDN-02', 'CAF-IDN-04', 'CAF-IDN-05'
            'caf.billing' = 'CAF-BIL-02'
            'caf.govern.sc' = 'CGOV-SC-05'
            'waf.avd' = 'WAF-AVD-SE-01'
            'waf.avd.azure' = 'WAF-AVDAZ-SE-06'
            'appmod.readiness' = 'APPMOD-SEC-02'
        }
        foreach ($pattern in $converted.Keys) {
            foreach ($id in $converted[$pattern]) {
                $rule = @((Get-TestRuleSet $pattern).Rules | Where-Object { $_.id -eq $id })[0]
                $rule.manual | Should -BeFalse -Because "$id is scored"
                $rule.assert.ContainsKey('gate') | Should -BeTrue -Because "$id must read NotAssessed when its data was not collected"
                (@($rule.assert.gate) -join ' ') | Should -Match 'conditionalAccess\.(Collected|baselineAssessable)|pimEligibilityAvailable|privilegedAccessMeasured'
            }
        }
    }

    It 'no rule still says PIM or Conditional Access is not collected' -ForEach @(
        @{ Phrase = 'Scout does not read Entra Conditional Access' }
        @{ Phrase = 'not reliably collected' }
        @{ Phrase = 'requires an Entra ID P2 license and a Graph' }
        @{ Phrase = 'needs an Entra ID P2 licence and a Graph' }
        @{ Phrase = 'Conditional Access is read from Microsoft Graph, not this' }
        @{ Phrase = 'Conditional Access policy data is not modeled' }
        @{ Phrase = 'No Conditional Access or emergency-access-account collector exists yet' }
        @{ Phrase = 'Scout could not read PIM eligibility in this run' }
        @{ Phrase = 'Identity/RBAC data (Conditional Access, per-resource role assignments) is not modeled' }
    ) {
        $script:RuleText | Should -Not -Match ([regex]::Escape($Phrase))
    }
}
