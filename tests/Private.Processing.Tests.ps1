#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for v3 pipeline modules that replaced Private/Processing.

.DESCRIPTION
    Tests processing pipeline functions: the draw.io job wrapper and the extra-processing
    step, plus the AB#5649 pins that keep the deleted background-job machinery deleted.
    No live Azure authentication is required.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
#>

BeforeAll {
    $script:ModuleRoot      = Split-Path -Parent $PSScriptRoot
    $script:ProcessingPath  = Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'pipeline'

    # Return a file's executable code with ALL comments removed, using the PowerShell
    # tokenizer. A line regex is not good enough here: these files document the machinery they
    # replaced inside <# … #> blocks, whose inner lines do not begin with '#', so a regex
    # strip leaves the old command names behind and the assertions below match the prose
    # instead of the code.
    function Get-StrippedCode {
        Param([string]$Path)

        $Tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$Tokens, [ref]$null)

        ($Tokens | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join ' '
    }
}

# =====================================================================
# FILE EXISTENCE
# =====================================================================
Describe 'v3 pipeline module files exist' {
    # Build-AZTICacheFiles, Start-AZTIProcessJob and Start-AZTIAutProcessJob were DELETED by
    # AB#5649 — see the regression Describe at the end of this file.
    # Only the draw.io wrapper survives — the Advisory, Policy, SecurityCenter and Sub wrappers
    # were deleted by AB#5649 along with the jobs they existed to wrap.
    $processingFiles = @(
        'Invoke-ScoutDrawIoJob.ps1',
        'Start-ScoutExtraJobs.ps1'
    )

    It '<_> exists' -ForEach $processingFiles {
        Join-Path -Path $script:ProcessingPath -ChildPath $_ | Should -Exist
    }
}

# =====================================================================
# SYNTAX VALIDATION
# =====================================================================
Describe 'v3 pipeline script syntax validation' {
    # Build-AZTICacheFiles, Start-AZTIProcessJob and Start-AZTIAutProcessJob were DELETED by
    # AB#5649 — see the regression Describe at the end of this file.
    # Only the draw.io wrapper survives — the Advisory, Policy, SecurityCenter and Sub wrappers
    # were deleted by AB#5649 along with the jobs they existed to wrap.
    $processingFiles = @(
        'Invoke-ScoutDrawIoJob.ps1',
        'Start-ScoutExtraJobs.ps1'
    )

    It '<_> parses without errors' -ForEach $processingFiles {
        $filePath = Join-Path -Path $script:ProcessingPath -ChildPath $_
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}

# =====================================================================
# FUNCTION DEFINITIONS
# =====================================================================
Describe 'v3 pipeline function definitions' {

    It 'Invoke-ScoutDrawIoJob.ps1 defines Invoke-AZSCDrawIOJob' {
        $content = Get-Content (Join-Path -Path $script:ProcessingPath -ChildPath 'Invoke-ScoutDrawIoJob.ps1') -Raw
        $content | Should -Match 'function\s+Invoke-AZSCDrawIOJob'
    }

    It 'Start-ScoutExtraJobs.ps1 defines Start-AZSCExtraJobs' {
        $content = Get-Content (Join-Path -Path $script:ProcessingPath -ChildPath 'Start-ScoutExtraJobs.ps1') -Raw
        $content | Should -Match 'function\s+Start-AZSCExtraJobs'
    }
}

# =====================================================================
# THE RESOURCE-PROCESSING JOB MACHINERY IS GONE (AB#5649)
# =====================================================================
# Start-AZSCProcessJob, Start-AZSCAutProcessJob and Build-AZSCCacheFiles were deleted when the
# processing phase moved to the deterministic in-process pipeline. Every crash-hardening test
# that used to live here existed to make that machinery survive its own edge cases -- a
# category filter matching nothing, a job list that was null, a job harvested before it
# finished. None of those states exist any more, so the tests are not ported: the equivalent
# behaviour is covered directly in tests/DeterministicPipeline.Tests.ps1.
#
# This block pins the deletion so the machinery cannot quietly return.
Describe 'Resource-processing background jobs stay deleted' {

    It '<_> no longer exists' -ForEach @(
        'Build-AZTICacheFiles.ps1',
        'Start-AZTIAutProcessJob.ps1',
        'Start-AZTIProcessJob.ps1',
        # Wrappers whose whole body was "Start-Job { import-module; Start-AZSC<X>Job }".
        'Invoke-AZTIAdvisoryJob.ps1',
        'Invoke-AZTIPolicyJob.ps1',
        'Invoke-AZTISecurityCenterJob.ps1',
        'Invoke-AZTISubJob.ps1'
    ) {
        Join-Path -Path $script:ProcessingPath -ChildPath $_ | Should -Not -Exist
    }

    It 'no v3 pipeline file starts a ResourceJob_* background job' {
        $Offenders = Get-ChildItem -Path $script:ProcessingPath -Filter '*.ps1' -File |
            Where-Object { (Get-Content $_.FullName -Raw) -match "ResourceJob_" }

        @($Offenders).Count | Should -Be 0
    }

    It 'Start-AZSCExtraJobs runs the four processing steps in-process, not as jobs' {
        # Comments describing the old design are allowed; executable calls are not. Stripped
        # with the tokenizer rather than a line regex: the design note in that file is a
        # <# … #> block, whose inner lines do not start with '#'.
        $Code = Get-StrippedCode (Join-Path -Path $script:ProcessingPath -ChildPath 'Start-ScoutExtraJobs.ps1')

        $Code | Should -Not -Match 'Start-Job'
        $Code | Should -Not -Match 'Start-ThreadJob'

        # …and it calls the real work directly instead.
        $Code | Should -Match 'Start-AZSCSecCenterJob'
        $Code | Should -Match 'Start-AZSCPolicyJob'
        $Code | Should -Match 'Start-AZSCAdvisoryJob'
        $Code | Should -Match 'Start-AZSCSubscriptionJob'
    }

    It 'Start-AZSCSecCenterJob receives the security ROWS, not the on/off switch' {
        # It was called as `-SecurityCenter $SecurityCenter` against a parameter block that
        # declared no such parameter. PowerShell silently routes an unknown named argument to
        # $args for a simple function, so $null crossed the job boundary as -Security and
        # `foreach ($1 in $Security)` iterated nothing — the Security Center sheet was empty in
        # every release that had one. (AB#5649)
        $Source = Get-Content (Join-Path -Path $script:ProcessingPath -ChildPath 'Start-ScoutExtraJobs.ps1') -Raw
        $Source | Should -Match 'Start-AZSCSecCenterJob\s+-Subscriptions\s+\$Subscriptions\s+-Security\s+\$Security'
    }

    It 'Start-AZSCExtraReports no longer harvests background jobs' {
        # AB#5662: moved from Modules/Private/Reporting to src/report/renderers/inventory.
        $ReportingPath = Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'report', 'renderers', 'inventory'
        $Code = Get-StrippedCode (Join-Path -Path $ReportingPath -ChildPath 'Start-AZSCExtraReports.ps1')

        $Code | Should -Not -Match 'Receive-Job'
        $Code | Should -Not -Match 'Remove-Job'
    }
}
