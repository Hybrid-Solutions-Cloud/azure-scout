#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the v3 collection modules that replaced Private/Extraction.

.DESCRIPTION
    Tests extraction pipeline functions: API resource retrieval, cost inventory,
    management groups, subscriptions, inventory loop, Entra extraction,
    Graph extraction, VM quotas, and VM SKU details.
    No live Azure authentication is required.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
#>

BeforeAll {
    $script:ModuleRoot     = Split-Path -Parent $PSScriptRoot
    $script:CollectionPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'collect'
}

# =====================================================================
# FILE EXISTENCE
# =====================================================================
Describe 'v3 collection module files exist' {
    $collectionFiles = @(
        'Get-ScoutApiResources.ps1',
        'Get-ScoutCostInventory.ps1',
        'Get-ScoutManagementGroups.ps1',
        'Get-ScoutSubscriptions.ps1',
        'Get-ScoutVmQuotas.ps1',
        'Get-ScoutVmSkuDetails.ps1',
        'Start-ScoutDevOpsExtraction.ps1',
        'Start-ScoutEntraExtraction.ps1',
        'Start-ScoutGraphExtraction.ps1'
    )

    It '<_> exists' -ForEach $collectionFiles {
        Join-Path -Path $script:CollectionPath -ChildPath $_ | Should -Exist
    }
}

# =====================================================================
# SYNTAX VALIDATION
# =====================================================================
Describe 'v3 collection script syntax validation' {
    $allFiles = @(
        'Get-ScoutApiResources.ps1', 'Get-ScoutCostInventory.ps1',
        'Get-ScoutManagementGroups.ps1', 'Get-ScoutSubscriptions.ps1',
        'Get-ScoutVmQuotas.ps1', 'Get-ScoutVmSkuDetails.ps1',
        'Start-ScoutDevOpsExtraction.ps1', 'Start-ScoutEntraExtraction.ps1',
        'Start-ScoutGraphExtraction.ps1'
    )

    It '<_> parses without errors' -ForEach $allFiles {
        $filePath = Join-Path -Path $script:CollectionPath -ChildPath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

}

# =====================================================================
# FUNCTION DEFINITIONS
# =====================================================================
Describe 'v3 collection function definitions' {

    It 'Get-ScoutApiResources.ps1 defines Get-ScoutApiResources' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Get-ScoutApiResources.ps1') -Raw
        $content | Should -Match 'function\s+Get-ScoutApiResources'
    }

    It 'Get-ScoutCostInventory.ps1 defines Get-ScoutCostInventory' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Get-ScoutCostInventory.ps1') -Raw
        $content | Should -Match 'function\s+Get-ScoutCostInventory'
    }

    It 'Get-ScoutManagementGroups.ps1 defines Get-AZSCManagementGroups' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Get-ScoutManagementGroups.ps1') -Raw
        $content | Should -Match 'function\s+Get-AZSCManagementGroups'
    }

    It 'Get-ScoutSubscriptions.ps1 defines Get-AZSCSubscriptions' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Get-ScoutSubscriptions.ps1') -Raw
        $content | Should -Match 'function\s+Get-AZSCSubscriptions'
    }

    It 'Invoke-AZTIInventoryLoop.ps1 is deleted and nothing references Invoke-AZSCInventoryLoop (AB#5648)' {
        Join-Path -Path $script:CollectionPath -ChildPath 'Invoke-AZTIInventoryLoop.ps1' | Should -Not -Exist
        $root = Split-Path $PSScriptRoot -Parent
        # AST command names, not raw text: the replacement shim's comments name the retired
        # function to explain what superseded it, and that is not a call site.
        $callers = @(
            Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'Modules'), (Join-Path -Path $root -ChildPath 'src') -Recurse -Filter *.ps1 |
                Where-Object {
                    $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
                    @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                            ForEach-Object { $_.GetCommandName() }) -contains 'Invoke-AZSCInventoryLoop'
                } |
                ForEach-Object { $_.Name }
        )
        $callers | Should -BeNullOrEmpty
    }

    It 'Start-ScoutEntraExtraction.ps1 defines Start-AZSCEntraExtraction' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Start-ScoutEntraExtraction.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCEntraExtraction'
    }

    It 'Start-ScoutGraphExtraction.ps1 defines Start-AZSCGraphExtraction' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Start-ScoutGraphExtraction.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCGraphExtraction'
    }

    It 'Get-ScoutVmQuotas.ps1 defines Get-ScoutVmQuotas' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Get-ScoutVmQuotas.ps1') -Raw
        $content | Should -Match 'function\s+Get-ScoutVmQuotas'
    }

    It 'Get-ScoutVmSkuDetails.ps1 defines Get-ScoutVmSkuDetails' {
        $content = Get-Content (Join-Path -Path $script:CollectionPath -ChildPath 'Get-ScoutVmSkuDetails.ps1') -Raw
        $content | Should -Match 'function\s+Get-ScoutVmSkuDetails'
    }
}

# =====================================================================
# STRICTMODE CRASH-HARDENING REGRESSION TESTS (AB#5041 sweep)
# =====================================================================
# Invoke-AZSCInventoryLoop used to `return $LocalResults` directly. When
# $LocalResults stayed an empty @() (e.g. every Search-AzGraph page came back
# empty), PowerShell's empty-array-on-return unrolls to $null — and the very
# next `.Count` access on that $null by a caller throws under
# `Set-StrictMode -Version Latest`. The fix was `return ,$LocalResults`.
#
# AB#5648 deleted that function; Get-ScoutRawInventory is the single paging engine now, so the
# same three contracts are enforced against IT instead — the hazard (an empty result set
# unrolling to $null on return, then a caller doing .Count under StrictMode) is identical.
Describe 'Get-ScoutRawInventory empty-result StrictMode hardening (was Invoke-AZSCInventoryLoop)' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        function Import-Module {             [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }
        . "$root/src/collect/Get-ScoutRawInventory.ps1"
        function Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            return @()
        }
    }

    BeforeEach {
        $script:emptyRawArgs = @{
            SubscriptionIds           = @('11111111-1111-1111-1111-111111111111')
            SkipApiResourceSweep      = $true
            CollectTenantWideResources = $false
            CollectGovernance         = $false
            WarningAction             = 'SilentlyContinue'
        }
    }

    It 'never returns $null for an empty result set (would collapse via bare "return $var")' {
        Set-StrictMode -Version Latest
        $result = Get-ScoutRawInventory @script:emptyRawArgs
        # Intentionally NOT using -BeNullOrEmpty: an empty array is a valid, non-null result
        # here and that distinction is exactly what this regression test protects.
        ($null -eq $result.Resources) | Should -BeFalse -Because 'a real (possibly-empty) array must come back, never $null'
        ($null -eq $result.ResourceContainers) | Should -BeFalse
        ($null -eq $result.Advisories) | Should -BeFalse
        ($null -eq $result.Security) | Should -BeFalse
        ($null -eq $result.Retirements) | Should -BeFalse
    }

    It 'lets the caller call .Count on the result without throwing under StrictMode' {
        Set-StrictMode -Version Latest
        $result = Get-ScoutRawInventory @script:emptyRawArgs
        { $result.Resources.Count } | Should -Not -Throw
        $result.Resources.Count | Should -Be 0
    }

    It 'accepts a single scalar subscription id without throwing on the internal .count checks' {
        Set-StrictMode -Version Latest
        $script:emptyRawArgs.SubscriptionIds = '11111111-1111-1111-1111-111111111111'
        { Get-ScoutRawInventory @script:emptyRawArgs } | Should -Not -Throw
    }
}
