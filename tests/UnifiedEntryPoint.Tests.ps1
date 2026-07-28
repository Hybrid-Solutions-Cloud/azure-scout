#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the single Invoke-AzureScout entry point and its wizard.

.DESCRIPTION
    Inventory and assessment are one command with different switches, not two
    products. These tests pin that contract:

      - Invoke-AzureScout exposes the assessment-mode parameters.
      - Mixing an inventory-only format with -Assessment (and vice versa) fails
        with an actionable message instead of silently producing nothing.
      - The wizard never fires in a non-interactive host, so CI and scheduled
        runs of a bare `Invoke-AzureScout` cannot block on a prompt.
      - The wizard's checklist/selection primitives behave.

    No live Azure authentication is required.

.NOTES
    Tracks AB#5540 (single entry point, per AB#5024) and AB#5541 (guided wizard).
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'AzureScout.psd1') -Force
    $script:Module = Get-Module AzureScout
    $script:Cmd    = Get-Command Invoke-AzureScout
}

Describe 'Single entry point — parameter surface' {
    It 'Invoke-AzureScout exposes -<Name>' -ForEach @(
        @{ Name = 'Assessment' }
        @{ Name = 'CollectOnly' }
        @{ Name = 'FromCollect' }
        @{ Name = 'NoWizard' }
    ) {
        $script:Cmd.Parameters.ContainsKey($Name) | Should -BeTrue
    }

    It '-Assessment accepts multiple assessments' {
        $script:Cmd.Parameters['Assessment'].ParameterType | Should -Be ([string[]])
    }

    It '-Assessment has the short -Assess alias' {
        $alias = $script:Cmd.Parameters['Assessment'].Aliases
        $alias | Should -Contain 'Assess'
    }

    It 'does not export the removed Invoke-ScoutAssessment name' {
        # Re-import from this repository after removing any gallery version a
        # developer may already have loaded. This makes the command-not-found
        # assertion a release-contract test rather than a machine-state test.
        Remove-Module AzureScout -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:ModuleRoot 'AzureScout.psd1') -Force -ErrorAction Stop
        $script:Module = Get-Module AzureScout | Where-Object {
            $_.ModuleBase -eq $script:ModuleRoot
        } | Select-Object -First 1

        # Do not use Get-Command without -ListImported: on a developer machine
        # with an older gallery version installed it would auto-load that *other*
        # module solely to answer this lookup. The imported module's export table
        # is the release contract.
        $script:Module.ExportedCommands.ContainsKey('Invoke-ScoutAssessment') | Should -BeFalse

        # Run the invocation assertion in a clean process: Pester shares one
        # PowerShell session with other suites, which may have loaded a prior
        # gallery version for compatibility tests.
        $modulePath = (Join-Path $script:ModuleRoot 'AzureScout.psd1').Replace("'", "''")
        $probe = @"
`$env:AZURESCOUT_SKIP_UPDATE_CHECK = '1'
`$ErrorActionPreference = 'Stop'
Import-Module '$modulePath' -Force -ErrorAction Stop
`$PSModuleAutoloadingPreference = 'None'
try {
    Invoke-ScoutAssessment -Assessment LandingZone
    exit 1
}
catch [System.Management.Automation.CommandNotFoundException] {
    exit 0
}
catch {
    exit 2
}
"@
        & pwsh -NoProfile -Command $probe
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Single entry point — output format guards' {
    It 'rejects an inventory-only format in assessment mode' {
        { Invoke-AzureScout -Assessment LandingZone -OutputFormat Markdown } |
            Should -Throw -ExpectedMessage '*inventory-only*'
    }

    It 'rejects an assessment-only format in inventory mode' {
        { Invoke-AzureScout -OutputFormat Html -NoWizard } |
            Should -Throw -ExpectedMessage '*assessment format*'
    }

    It 'names the valid alternatives in the rejection message' {
        # The point of the guard is to redirect, not just to fail.
        { Invoke-AzureScout -OutputFormat Pptx -NoWizard } |
            Should -Throw -ExpectedMessage '*-Assessment*'
    }

    It 'accepts a format valid in both modes' {
        $vs = $script:Cmd.Parameters['OutputFormat'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        foreach ($shared in @('All', 'Excel', 'Json', 'PowerBI')) {
            $vs.ValidValues | Should -Contain $shared
        }
    }
}

Describe 'Wizard — interactive-host gate' {
    It 'does not prompt when stdin is redirected or the host is non-interactive' {
        # This Pester run is itself non-interactive, which is exactly the
        # condition a CI runner hits.
        & $script:Module { Test-AZSCInteractiveHost } | Should -BeFalse
    }

    It 'returns false when a CI environment variable is set' {
        $original = $env:GITHUB_ACTIONS
        try {
            $env:GITHUB_ACTIONS = 'true'
            & $script:Module { Test-AZSCInteractiveHost } | Should -BeFalse
        }
        finally { $env:GITHUB_ACTIONS = $original }
    }

    It 'exports Start-AZSCWizard so operators can re-run it on demand' {
        Get-Command Start-AZSCWizard -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'keeps the console primitives internal to the module' {
        Get-Command Read-AZSCWizardChecklist -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Wizard — checklist primitive' {
    It 'pre-selects every item and accepts on a bare Enter' {
        $result = & $script:Module {
            Mock -CommandName Read-Host -MockWith { '' }
            Read-AZSCWizardChecklist -Title 'x' -Items @('A', 'B', 'C')
        }
        $result | Should -Be @('A', 'B', 'C')
    }

    It 'unchecks the items the operator names, then accepts' {
        $result = & $script:Module {
            $script:calls = 0
            Mock -CommandName Read-Host -MockWith {
                $script:calls++
                if ($script:calls -eq 1) { '2' } else { '' }
            }
            Read-AZSCWizardChecklist -Title 'x' -Items @('A', 'B', 'C')
        }
        $result | Should -Be @('A', 'C')
    }

    It 'returns null when the operator quits' {
        $result = & $script:Module {
            Mock -CommandName Read-Host -MockWith { 'q' }
            Read-AZSCWizardChecklist -Title 'x' -Items @('A', 'B')
        }
        $result | Should -BeNullOrEmpty
    }

    It 'preserves the original item order regardless of toggle order' {
        $result = & $script:Module {
            $script:calls = 0
            Mock -CommandName Read-Host -MockWith {
                $script:calls++
                if ($script:calls -eq 1) { 'n' } elseif ($script:calls -eq 2) { '3,1' } else { '' }
            }
            Read-AZSCWizardChecklist -Title 'x' -Items @('A', 'B', 'C')
        }
        $result | Should -Be @('A', 'C')
    }
}

Describe 'Wizard — equivalent command rendering' {
    It 'renders the answers as a runnable Invoke-AzureScout line' {
        $line = & $script:Module {
            Format-AZSCWizardCommand -Answers @{
                TenantID     = '00000000-0000-0000-0000-000000000000'
                Assessment   = @('LandingZone')
                OutputFormat = @('Html')
            }
        }
        $line | Should -BeLike 'Invoke-AzureScout *'
        $line | Should -BeLike '*-Assessment LandingZone*'
        $line | Should -BeLike '*-OutputFormat Html*'
        $line | Should -BeLike '*-TenantID 00000000-0000-0000-0000-000000000000*'
    }

    It 'quotes values containing spaces' {
        $line = & $script:Module {
            Format-AZSCWizardCommand -Answers @{ ReportDir = 'C:\My Reports\Scout' }
        }
        $line | Should -BeLike "*-ReportDir 'C:\My Reports\Scout'*"
    }

    It 'renders switches as bare flags' {
        $line = & $script:Module {
            Format-AZSCWizardCommand -Answers @{ IncludeTags = [switch]$true }
        }
        $line | Should -Be 'Invoke-AzureScout -IncludeTags'
    }
}
