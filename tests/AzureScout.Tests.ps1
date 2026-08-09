#Requires -Modules Pester
[Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'ManifestPath/ModulePath are assigned in BeforeAll and consumed by sibling It blocks via Pester''s shared scope -- PSScriptAnalyzer''s static analysis cannot see across those scriptblocks.')]
param()

<#
.SYNOPSIS
    Pester tests for the AzureScout module.

.DESCRIPTION
    Basic module validation tests for AzureScout (AZSC).
    These tests verify the module can be imported, that expected functions
    are exported, and that the manifest is well-formed.

.NOTES
    Author:  Kristopher Turner
    Version: 2.0.1
    Created: 2026-01-20
#>

BeforeAll {
    $ModuleRoot = Split-Path -Parent $PSScriptRoot
    $ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'AzureScout.psd1'
    $ModulePath   = Join-Path -Path $ModuleRoot -ChildPath 'AzureScout.psm1'
}

Describe 'Module Manifest Tests' {
    It 'Has a valid module manifest' {
        $ManifestPath | Should -Exist
        $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        $Manifest | Should -Not -BeNullOrEmpty
    }

    It 'Has the correct module name' {
        $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        $Manifest.Name | Should -Be 'AzureScout'
    }

    It 'Has a valid GUID' {
        $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        $Manifest.Guid | Should -Be 'a0785538-fd96-4960-bf93-c733f88519e0'
    }

    It 'Has a version matching the newest CHANGELOG entry' {
        # Asserted against CHANGELOG.md rather than a hardcoded literal: a pinned version
        # string has to be hand-edited on every release and fails CI when someone forgets,
        # which tests the release checklist rather than the module. The invariant worth
        # holding is that the manifest and the changelog agree.
        $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop

        $changelogPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'CHANGELOG.md'
        $changelogPath | Should -Exist

        $newest = Select-String -Path $changelogPath -Pattern '^## \[(\d+\.\d+\.\d+)\]' |
                  Select-Object -First 1

        $newest | Should -Not -BeNullOrEmpty -Because 'CHANGELOG.md must carry at least one released version heading'
        $Manifest.Version.ToString() | Should -Be $newest.Matches[0].Groups[1].Value
    }

    It 'Has the correct author' {
        $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        $Manifest.Author | Should -Be 'Kristopher Turner'
    }

    It 'Has a root module' {
        $ModulePath | Should -Exist
    }

    It 'Requires PowerShell 7.0+ (rejects Windows PowerShell 5.1 Desktop cleanly at Import-Module time)' {
        $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        $Manifest.PowerShellVersion | Should -Be ([version]'7.0')
    }

    It 'Declares only the Core PSEdition as compatible' {
        $ManifestData = Import-PowerShellDataFile -Path $ManifestPath
        $ManifestData.CompatiblePSEditions | Should -Be @('Core')
    }
}

Describe 'Module Import Tests' {
    It 'Imports without errors' {
        { Import-Module $ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Exports Invoke-AzureScout' {
        Import-Module $ManifestPath -Force -ErrorAction Stop
        $Commands = Get-Command -Module AzureScout
        $Commands.Name | Should -Contain 'Invoke-AzureScout'
    }
}
