#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Private/Processing modules.

.DESCRIPTION
    Tests processing pipeline functions: cache file building, advisory jobs,
    draw.io jobs, policy jobs, security center jobs, subscription jobs,
    automation processing, extra jobs, and main process job.
    No live Azure authentication is required.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
#>

BeforeAll {
    $script:ModuleRoot      = Split-Path -Parent $PSScriptRoot
    $script:ProcessingPath  = Join-Path $script:ModuleRoot 'Modules' 'Private' 'Processing'
}

# =====================================================================
# FILE EXISTENCE
# =====================================================================
Describe 'Private/Processing Module Files Exist' {
    $processingFiles = @(
        'Build-AZTICacheFiles.ps1',
        'Invoke-AZTIAdvisoryJob.ps1',
        'Invoke-AZTIDrawIOJob.ps1',
        'Invoke-AZTIPolicyJob.ps1',
        'Invoke-AZTISecurityCenterJob.ps1',
        'Invoke-AZTISubJob.ps1',
        'Start-AZTIAutProcessJob.ps1',
        'Start-AZTIExtraJobs.ps1',
        'Start-AZTIProcessJob.ps1'
    )

    It '<_> exists' -ForEach $processingFiles {
        Join-Path $script:ProcessingPath $_ | Should -Exist
    }
}

# =====================================================================
# SYNTAX VALIDATION
# =====================================================================
Describe 'Private/Processing Script Syntax Validation' {
    $processingFiles = @(
        'Build-AZTICacheFiles.ps1',
        'Invoke-AZTIAdvisoryJob.ps1',
        'Invoke-AZTIDrawIOJob.ps1',
        'Invoke-AZTIPolicyJob.ps1',
        'Invoke-AZTISecurityCenterJob.ps1',
        'Invoke-AZTISubJob.ps1',
        'Start-AZTIAutProcessJob.ps1',
        'Start-AZTIExtraJobs.ps1',
        'Start-AZTIProcessJob.ps1'
    )

    It '<_> parses without errors' -ForEach $processingFiles {
        $filePath = Join-Path $script:ProcessingPath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}

# =====================================================================
# FUNCTION DEFINITIONS
# =====================================================================
Describe 'Private/Processing Function Definitions' {

    It 'Build-AZTICacheFiles.ps1 defines Build-AZSCCacheFiles' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Build-AZTICacheFiles.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCCacheFiles'
    }

    It 'Invoke-AZTIAdvisoryJob.ps1 defines Invoke-AZSCAdvisoryJob' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Invoke-AZTIAdvisoryJob.ps1') -Raw
        $content | Should -Match 'function\s+Invoke-AZSCAdvisoryJob'
    }

    It 'Invoke-AZTIDrawIOJob.ps1 defines Invoke-AZSCDrawIOJob' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Invoke-AZTIDrawIOJob.ps1') -Raw
        $content | Should -Match 'function\s+Invoke-AZSCDrawIOJob'
    }

    It 'Invoke-AZTIPolicyJob.ps1 defines Invoke-AZSCPolicyJob' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Invoke-AZTIPolicyJob.ps1') -Raw
        $content | Should -Match 'function\s+Invoke-AZSCPolicyJob'
    }

    It 'Invoke-AZTISecurityCenterJob.ps1 defines Invoke-AZSCSecurityCenterJob' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Invoke-AZTISecurityCenterJob.ps1') -Raw
        $content | Should -Match 'function\s+Invoke-AZSCSecurityCenterJob'
    }

    It 'Invoke-AZTISubJob.ps1 defines Invoke-AZSCSubJob' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Invoke-AZTISubJob.ps1') -Raw
        $content | Should -Match 'function\s+Invoke-AZSCSubJob'
    }

    It 'Start-AZTIAutProcessJob.ps1 defines Start-AZSCAutProcessJob' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Start-AZTIAutProcessJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCAutProcessJob'
    }

    It 'Start-AZTIExtraJobs.ps1 defines Start-AZSCExtraJobs' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Start-AZTIExtraJobs.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCExtraJobs'
    }

    It 'Start-AZTIProcessJob.ps1 defines Start-AZSCProcessJob' {
        $content = Get-Content (Join-Path $script:ProcessingPath 'Start-AZTIProcessJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCProcessJob'
    }
}

# =====================================================================
# STRICTMODE CRASH-HARDENING REGRESSION TESTS (AB#5041 sweep)
# =====================================================================
# Start-AZSCProcessJob / Build-AZSCCacheFiles filter folders/files/categories
# with Where-Object and then read .Count / .Name off the result. When a
# -Category filter (or a job that returned no output) matches nothing,
# Where-Object's result collapses to $null, and a bare `.Count`/`.Name` on
# that throws under `Set-StrictMode -Version Latest`. These tests reproduce
# the exact filter-to-zero-matches shape without needing to spin up real
# background jobs.
Describe 'Category-filter-to-zero-matches StrictMode hardening' {
    BeforeAll {
        Set-StrictMode -Version Latest

        # Mirrors Start-AZTIProcessJob.ps1's folder-level category filter (post-fix).
        function Get-FilteredFolderNameList {
            param($ModuleFolders, $Category)
            if ($Category -and $Category -notcontains 'All') {
                $ModuleFolders = $ModuleFolders | Where-Object { $Category -contains $_.Name }
                $nameList = if ($ModuleFolders) { $ModuleFolders.Name -join ', ' } else { '(none)' }
                return $nameList
            }
            return $null
        }

        # Mirrors Start-AZTIProcessJob.ps1's per-file .Categories intersection check (post-fix).
        function Test-HasMatchingCategory {
            param($FileCategories, $Category)
            return @($FileCategories | Where-Object { $Category -contains $_ }).Count -gt 0
        }
    }

    It 'a folder-name filter that matches nothing does not throw (was: $ModuleFolders.Name on $null)' {
        $folders = @([pscustomobject]@{ Name = 'Compute' }, [pscustomobject]@{ Name = 'Storage' })
        { Get-FilteredFolderNameList -ModuleFolders $folders -Category @('NoSuchCategory') } | Should -Not -Throw
        Get-FilteredFolderNameList -ModuleFolders $folders -Category @('NoSuchCategory') | Should -Be '(none)'
    }

    It 'a per-file category intersection with zero overlap does not throw (was: (...).Count on $null)' {
        { Test-HasMatchingCategory -FileCategories @('Storage') -Category @('Compute') } | Should -Not -Throw
        Test-HasMatchingCategory -FileCategories @('Storage') -Category @('Compute') | Should -BeFalse
    }

    It 'a per-file category intersection with overlap still returns true' {
        Test-HasMatchingCategory -FileCategories @('Compute', 'Storage') -Category @('Compute') | Should -BeTrue
    }

    It 'Build-AZTICacheFiles.ps1 guards $JobNames.count for a null/empty job list' {
        . (Join-Path $script:ProcessingPath 'Build-AZTICacheFiles.ps1')
        . (Join-Path $script:ModuleRoot 'Modules' 'Private' 'Main' 'Clear-AZTIMemory.ps1')
        Mock Receive-Job { }
        Mock Remove-Job { }
        { Build-AZSCCacheFiles -DefaultPath $TestDrive -JobNames $null } | Should -Not -Throw
    }
}
