#Requires -Version 7.0
#Requires -Modules Pester
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModuleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ModuleRoot 'AzureScout.psd1') -Force

InModuleScope AzureScout {
    Describe 'ConvertTo-ScoutEntraDerivedEvidence' {
        BeforeAll {
            function New-TestEntraRow {
                param([string]$Type, [string]$Id, [string]$Name, [hashtable]$Properties)
                [pscustomobject]@{
                    id = $Id
                    name = $Name
                    TYPE = $Type
                    tenantId = 'tenant'
                    properties = [pscustomobject]$Properties
                }
            }

            $script:Evidence = @(
                New-TestEntraRow -Type 'entra/users' -Id 'user-1' -Name 'breakglass@example.com' -Properties @{
                    id = 'user-1'; accountEnabled = $true; onPremisesSyncEnabled = $false
                }
                New-TestEntraRow -Type 'entra/authenticationmethodregistrations' -Id 'user-1' -Name 'breakglass@example.com' -Properties @{
                    id = 'user-1'; isMfaRegistered = $true; methodsRegistered = @('fido2SecurityKey')
                }
                New-TestEntraRow -Type 'entra/conditionalaccesspolicies' -Id 'policy-report' -Name 'Report policy' -Properties @{
                    id = 'policy-report'; state = 'enabledForReportingButNotEnforced'
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{ excludeUsers = @('user-1') } }
                }
                New-TestEntraRow -Type 'entra/conditionalaccesspolicies' -Id 'policy-on' -Name 'Enabled policy' -Properties @{
                    id = 'policy-on'; state = 'enabled'
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{ excludeUsers = @('user-1') } }
                }
                New-TestEntraRow -Type 'entra/signins' -Id 'signin-1' -Name 'breakglass@example.com' -Properties @{
                    id = 'signin-1'; userId = 'user-1'; userPrincipalName = 'breakglass@example.com'
                    createdDateTime = (Get-Date).ToUniversalTime().AddDays(-2).ToString('o')
                    clientAppUsed = 'IMAP'
                    status = [pscustomobject]@{ errorCode = 0 }
                    appliedConditionalAccessPolicies = @([pscustomobject]@{ id = 'policy-report'; result = 'reportOnlyFailure' })
                }
                New-TestEntraRow -Type 'entra/roleassignmentschedules' -Id 'assignment-1' -Name 'user-1' -Properties @{
                    id = 'assignment-1'; principalId = 'user-1'; roleDefinitionId = 'role-1'; memberType = 'Direct'
                    roleDefinition = [pscustomobject]@{ id = 'role-1'; displayName = 'Global Administrator' }
                    startDateTime = $null; endDateTime = $null
                }
                New-TestEntraRow -Type 'entra/pimassignments' -Id 'legacy-1' -Name 'user-1' -Properties @{
                    id = 'legacy-1'; principalId = 'user-1'
                    roleDefinition = [pscustomobject]@{ displayName = 'Global Administrator' }
                }
            )
            $script:Derived = @(ConvertTo-ScoutEntraDerivedEvidence -EntraResources $script:Evidence -TenantID tenant)
        }

        It 'calculates report-only Conditional Access impact from retained sign-ins' {
            $row = @($script:Derived | Where-Object TYPE -eq 'entra/conditionalaccessreportonlyimpact')[0]
            $row.properties.reportOnlyFailure | Should -Be 1
            $row.properties.observedSignIns | Should -Be 1
        }

        It 'summarizes successful legacy authentication without exposing the full UPN in the name' {
            $row = @($script:Derived | Where-Object TYPE -eq 'entra/legacyauthsummary')[0]
            $row.properties.successfulSignIns | Should -Be 1
            $row.name | Should -Not -Be 'breakglass@example.com'
            $row.properties.clientApps | Should -Contain 'IMAP'
        }

        It 'resolves permanent privileged assignments and stale access' {
            $row = @($script:Derived | Where-Object TYPE -eq 'entra/privilegedassignments')[0]
            $row.properties.roleName | Should -Be 'Global Administrator'
            $row.properties.assignmentType | Should -Be 'Permanent'
            $row.properties.principalName | Should -Be 'breakglass@example.com'
        }

        It 'identifies direct emergency-access exclusions and correlates MFA and roles' {
            $row = @($script:Derived | Where-Object TYPE -eq 'entra/breakglasscandidates')[0]
            $row.properties.isMfaRegistered | Should -BeTrue
            $row.properties.cloudOnly | Should -BeTrue
            $row.properties.assignedRoles | Should -Contain 'Global Administrator'
            $row.properties.maskedUserPrincipalName | Should -Not -Be 'breakglass@example.com'
        }

        It 'labels every correlation row with its retained inputs' {
            foreach ($row in $script:Derived) {
                $row.AZSC.Source | Should -Match 'Derived'
                @($row.AZSC.Inputs).Count | Should -BeGreaterThan 0
            }
        }
    }
}
