#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot=Split-Path -Parent $PSScriptRoot
    . "$script:RepoRoot/src/pipeline/Get-ScoutCollectorDefinition.ps1"
    . "$script:RepoRoot/src/pipeline/Invoke-ScoutDeclarativeCollector.ps1"
    . "$script:RepoRoot/src/Get-AZSCSafeProperty.ps1"
    . "$script:RepoRoot/src/Get-AZTICollectedValue.ps1"
    . "$script:RepoRoot/src/Get-AZSCIdSegment.ps1"

    function Invoke-EvidenceSparseCollector {
        param([string]$Category,[string]$Name,[string]$Type,[object]$Properties)
        $definition=Get-ScoutCollectorDefinition -Path "$script:RepoRoot/manifests/collectors/$Category/$Name.psd1"
        $resource=[pscustomobject]@{id='test-id';name='test';type=$Type;properties=$Properties;subscriptionId='sub-test'}
        $context=@{
            ScriptRoot=$script:RepoRoot;Subscriptions=@([pscustomobject]@{id='sub-test';Name='Test'})
            InTag=$false;Resources=@($resource);Retirements=@();Task='Processing';File=$null
            SmaResources=$null;TableStyle='Light20';Unsupported=@();RunTime=[datetime]'2026-08-16T00:00:00Z'
        }
        return @(Invoke-ScoutDeclarativeCollector -Definition $definition -Context $context)
    }
}

Describe 'AB#7441 evidence manifests retain sparse source rows' -ForEach @(
    @{Category='Identity';Name='AccessReviews';Type='entra/accessreviewdefinitions';Properties=[pscustomobject]@{}},
    @{Category='Identity';Name='HybridIdentityTopology';Type='entra/domains';Properties=[pscustomobject]@{}},
    @{Category='Identity';Name='EntraDiagnosticSettings';Type='AZSC/Entra/DiagnosticSettings';Properties=[pscustomobject]@{Raw=[pscustomobject]@{properties=[pscustomobject]@{}}}},
    @{Category='Identity';Name='HybridIdentityLocal';Type='AZSC/HybridIdentity/EntraConnectScheduler';Properties=[pscustomobject]@{Raw=[pscustomobject]@{}}},
    @{Category='Identity';Name='OktaFederation';Type='AZSC/Okta/Applications';Properties=[pscustomobject]@{Raw=[pscustomobject]@{}}},
    @{Category='Identity';Name='OktaAuthenticationPolicies';Type='AZSC/Okta/Policies';Properties=[pscustomobject]@{Raw=[pscustomobject]@{}}},
    @{Category='Identity';Name='OktaApplicationUsage';Type='AZSC/Okta/ApplicationUsageSummary';Properties=[pscustomobject]@{}},
    @{Category='Identity';Name='OktaFactorEnrollment';Type='AZSC/Okta/FactorEnrollmentSummary';Properties=[pscustomobject]@{}},
    @{Category='Identity';Name='OktaAdministrators';Type='AZSC/Okta/AdminRoleSummary';Properties=[pscustomobject]@{}},
    @{Category='Management';Name='BillingAccounts';Type='AZSC/Billing/BillingAccounts';Properties=[pscustomobject]@{Raw=[pscustomobject]@{properties=[pscustomobject]@{}}}},
    @{Category='Management';Name='BillingBenefits';Type='AZSC/Billing/ReservationOrders';Properties=[pscustomobject]@{Raw=[pscustomobject]@{properties=[pscustomobject]@{}}}},
    @{Category='Management';Name='BillingHierarchy';Type='AZSC/Billing/BillingProfiles';Properties=[pscustomobject]@{Raw=[pscustomobject]@{properties=[pscustomobject]@{}}}},
    @{Category='Management';Name='BillingRoles';Type='AZSC/Billing/BillingRoleAssignments';Properties=[pscustomobject]@{Raw=[pscustomobject]@{properties=[pscustomobject]@{}}}},
    @{Category='Monitor';Name='WorkspaceTableRetention';Type='AZSC/ARMChild/LAWorkspaceTables';Properties=[pscustomobject]@{}},
    @{Category='Security';Name='SentinelDataConnectors';Type='AZSC/ARMChild/SentinelDataConnectors';Properties=[pscustomobject]@{}},
    @{Category='Security';Name='SentinelIngestion';Type='AZSC/ARMChild/SentinelIngestion';Properties=[pscustomobject]@{}},
    @{Category='Security';Name='DefenderAttackPaths';Type='microsoft.security/attackpaths';Properties=[pscustomobject]@{}}
) {
    It '<Category>/<Name> produces a row rather than throwing on omitted optional fields' {
        $rows=@(Invoke-EvidenceSparseCollector -Category $Category -Name $Name -Type $Type -Properties $Properties)
        $rows.Count | Should -Be 1
    }
}
