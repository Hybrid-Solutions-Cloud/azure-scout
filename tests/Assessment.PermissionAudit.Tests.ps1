#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/assess/Test-ScoutPermission.ps1 -- the read-only
    permission pre-flight (ADO Story AB#5051).

    Focus: the $Manifest[$_] null-crash class found in a StrictMode sweep.
    `$Manifest[$_].Ingest -contains 'AzGovViz'` dots directly into whatever
    `$Manifest[$_]` returns -- a bracket lookup on a Hashtable/[ordered] map
    returns $null (not a throw) for a key that isn't present, but the
    IMMEDIATELY FOLLOWING `.Ingest` dot-access on that $null throws
    PropertyNotFoundException under Set-StrictMode -Version Latest. This is
    reachable whenever -Assessment names something that isn't actually a key
    in manifests/assessments.psd1 (a caller-supplied name never validated
    against the manifest, since Test-ScoutPermission has no ValidateSet on
    -Assessment and is a standalone, directly-callable function).

    No live Azure authentication is required -- Get-AzContext/Get-AzRoleAssignment
    are stubbed with local functions of the same name, which PowerShell resolves
    ahead of any same-named command from an Az module that may or may not be
    loaded in the test session.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent

    # Stubs -- Test-ScoutPermission.ps1 never imports Az.Accounts/Az.Resources
    # itself (the caller is expected to already have an authenticated context),
    # so these local functions satisfy its two Az calls without any live
    # Azure connection or Az module dependency in this test.
    function Get-AzContext {
        [pscustomobject]@{
            Tenant  = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
            Account = [pscustomobject]@{ Id = 'test-user@contoso.com' }
        }
    }
    function Get-AzRoleAssignment {         [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([string]$Scope, [string]$SignInName, [string]$ErrorAction) @() }

    . "$script:Root/src/assess/Test-ScoutPermission.ps1"
}

Describe 'Test-ScoutPermission -- unknown/missing manifest key crash class (StrictMode sweep)' {
    It 'does not throw when -Assessment names a value that is not a key in -Manifest at all' {
        $manifest = @{ 'CAF: Azure Landing Zone' = @{ Ingest = @('AzGovViz') } }
        $results = Test-ScoutPermission -Assessment @('NotARealAssessmentName') -Manifest $manifest 6>$null
        @($results).Count | Should -BeGreaterThan 0
    }

    It 'does not throw when -Manifest itself is $null' {
        $results = Test-ScoutPermission -Assessment @('CAF: Azure Landing Zone') -Manifest $null 6>$null
        @($results).Count | Should -BeGreaterThan 0
    }

    It 'still detects the AzGovViz ingest requirement for an assessment that IS a valid manifest key' {
        $manifest = @{ 'CAF: Azure Landing Zone' = @{ Ingest = @('AzGovViz') } }
        $results = Test-ScoutPermission -Assessment @('CAF: Azure Landing Zone') -Manifest $manifest 6>$null
        # @() wrap is load-bearing here too: a Where-Object match of zero items
        # collapses the bare expression to $null, and $null.Count is exactly the
        # crash class this whole test file exists to guard against.
        @($results | Where-Object Check -like 'Graph:*').Count | Should -BeGreaterThan 0
    }

    It 'reports no Graph checks when every named assessment is missing/unknown (no AzGovViz ingest found)' {
        $manifest = @{ 'CAF: Azure Landing Zone' = @{ Ingest = @('AzGovViz') } }
        $results = Test-ScoutPermission -Assessment @('DoesNotExist1', 'DoesNotExist2') -Manifest $manifest 6>$null
        @($results | Where-Object Check -like 'Graph:*').Count | Should -Be 0
        # The ARM Reader @ MG root check always runs regardless.
        @($results | Where-Object Check -eq 'ARM Reader @ MG root').Count | Should -Be 1
    }
}
