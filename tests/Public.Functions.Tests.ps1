#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for v3 pipeline utility scripts.

.DESCRIPTION
    Tests public function files: Diagram generation functions and Job wrapper functions.
    Validates file existence, syntax, and function definitions.
    No live Azure authentication is required.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
#>

BeforeAll {
    $script:ModuleRoot   = Split-Path -Parent $PSScriptRoot
    $script:PublicPath   = Join-Path -Path $script:ModuleRoot -ChildPath 'src'
    $script:DiagramPath  = Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'pipeline', 'diagram'
    $script:JobsPath     = Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'pipeline', 'jobs'
}

# =====================================================================
# FILE EXISTENCE
# =====================================================================
Describe 'Public/PublicFunctions Files Exist' {
    It 'Invoke-AzureScout.ps1 exists' {
        Join-Path -Path $script:PublicPath -ChildPath 'Invoke-AzureScout.ps1' | Should -Exist
    }

    It 'Test-AZTIPermissions.ps1 exists' {
        Join-Path -Path $script:PublicPath -ChildPath 'Test-AZTIPermissions.ps1' | Should -Exist
    }

    It 'Start-AZSCWizard.ps1 exists' {
        Join-Path -Path $script:PublicPath -ChildPath 'Start-AZSCWizard.ps1' | Should -Exist
    }
}

Describe 'v3 pipeline diagram files exist' {
    $diagramFiles = @(
        'Build-ScoutDiagramSubnet.ps1', 'Set-ScoutDiagramFile.ps1',
        'Start-ScoutDiagramJob.ps1', 'Start-ScoutDiagramNetwork.ps1',
        'Start-ScoutDiagramOrganization.ps1', 'Start-ScoutDiagramSubscription.ps1',
        'Start-ScoutDrawIoDiagram.ps1'
    )

    It '<_> exists' -ForEach $diagramFiles {
        Join-Path -Path $script:DiagramPath -ChildPath $_ | Should -Exist
    }
}

Describe 'v3 pipeline job files exist' {
    $jobFiles = @(
        'Start-ScoutAdvisoryJob.ps1', 'Start-ScoutPolicyJob.ps1',
        'Start-ScoutSecCenterJob.ps1', 'Start-ScoutSubscriptionJob.ps1'
    )

    It '<_> exists' -ForEach $jobFiles {
        Join-Path -Path $script:JobsPath -ChildPath $_ | Should -Exist
    }
}

# =====================================================================
# SYNTAX VALIDATION
# =====================================================================
Describe 'Public/PublicFunctions Syntax Validation' {

    It 'Invoke-AzureScout.ps1 parses without errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path -Path $script:PublicPath -ChildPath 'Invoke-AzureScout.ps1'), [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'Test-AZTIPermissions.ps1 parses without errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path -Path $script:PublicPath -ChildPath 'Test-AZTIPermissions.ps1'), [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'Start-AZSCWizard.ps1 parses without errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path -Path $script:PublicPath -ChildPath 'Start-AZSCWizard.ps1'), [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    $diagramFiles = @(
        'Build-ScoutDiagramSubnet.ps1', 'Set-ScoutDiagramFile.ps1',
        'Start-ScoutDiagramJob.ps1', 'Start-ScoutDiagramNetwork.ps1',
        'Start-ScoutDiagramOrganization.ps1', 'Start-ScoutDiagramSubscription.ps1',
        'Start-ScoutDrawIoDiagram.ps1'
    )

    It 'Diagram/<_> parses without errors' -ForEach $diagramFiles {
        $filePath = Join-Path -Path $script:DiagramPath -ChildPath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    $jobFiles = @(
        'Start-ScoutAdvisoryJob.ps1', 'Start-ScoutPolicyJob.ps1',
        'Start-ScoutSecCenterJob.ps1', 'Start-ScoutSubscriptionJob.ps1'
    )

    It 'Jobs/<_> parses without errors' -ForEach $jobFiles {
        $filePath = Join-Path -Path $script:JobsPath -ChildPath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}

# =====================================================================
# FUNCTION DEFINITIONS
# =====================================================================
Describe 'Public/Diagram Function Definitions' {

    It 'Build-ScoutDiagramSubnet.ps1 defines Build-AZSCDiagramSubnet' {
        $content = Get-Content (Join-Path -Path $script:DiagramPath -ChildPath 'Build-ScoutDiagramSubnet.ps1') -Raw
        $content | Should -Match 'function\s+Build-AZSCDiagramSubnet'
    }

    It 'Set-ScoutDiagramFile.ps1 defines Set-AZSCDiagramFile' {
        $content = Get-Content (Join-Path -Path $script:DiagramPath -ChildPath 'Set-ScoutDiagramFile.ps1') -Raw
        $content | Should -Match 'function\s+Set-AZSCDiagramFile'
    }

    It 'Start-ScoutDiagramJob.ps1 defines Start-AZSCDiagramJob' {
        $content = Get-Content (Join-Path -Path $script:DiagramPath -ChildPath 'Start-ScoutDiagramJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCDiagramJob'
    }

    It 'Start-ScoutDiagramNetwork.ps1 defines Start-AZSCDiagramNetwork' {
        $content = Get-Content (Join-Path -Path $script:DiagramPath -ChildPath 'Start-ScoutDiagramNetwork.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCDiagramNetwork'
    }

    It 'Start-ScoutDiagramOrganization.ps1 defines Start-AZSCDiagramOrganization' {
        $content = Get-Content (Join-Path -Path $script:DiagramPath -ChildPath 'Start-ScoutDiagramOrganization.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCDiagramOrganization'
    }

    It 'Start-ScoutDiagramSubscription.ps1 defines Start-AZSCDiagramSubscription' {
        $content = Get-Content (Join-Path -Path $script:DiagramPath -ChildPath 'Start-ScoutDiagramSubscription.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCDiagramSubscription'
    }

    It 'Start-ScoutDrawIoDiagram.ps1 defines Start-AZSCDrawIODiagram' {
        $content = Get-Content (Join-Path -Path $script:DiagramPath -ChildPath 'Start-ScoutDrawIoDiagram.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCDrawIODiagram'
    }
}

Describe 'Public/Jobs Function Definitions' {

    It 'Start-ScoutAdvisoryJob.ps1 defines Start-AZSCAdvisoryJob' {
        $content = Get-Content (Join-Path -Path $script:JobsPath -ChildPath 'Start-ScoutAdvisoryJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCAdvisoryJob'
    }

    It 'Start-ScoutPolicyJob.ps1 defines Start-AZSCPolicyJob' {
        $content = Get-Content (Join-Path -Path $script:JobsPath -ChildPath 'Start-ScoutPolicyJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCPolicyJob'
    }

    It 'Start-ScoutSecCenterJob.ps1 defines Start-AZSCSecCenterJob' {
        $content = Get-Content (Join-Path -Path $script:JobsPath -ChildPath 'Start-ScoutSecCenterJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCSecCenterJob'
    }

    It 'Start-ScoutSubscriptionJob.ps1 defines Start-AZSCSubscriptionJob' {
        $content = Get-Content (Join-Path -Path $script:JobsPath -ChildPath 'Start-ScoutSubscriptionJob.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCSubscriptionJob'
    }

    # Wait-AZTIJob.ps1 was DELETED by AB#5649 — the run orchestration starts no background jobs,
    # so nothing is left to wait on. The four Start-AZSC*Job functions above survive as ordinary
    # in-process functions; only the job plumbing around them went.
    It 'Wait-AZTIJob.ps1 stays deleted' {
        Join-Path -Path $script:JobsPath -ChildPath 'Wait-AZTIJob.ps1' | Should -Not -Exist
    }
}
