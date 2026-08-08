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
    Invoke-ScoutAssessment -Assessment 'CAF: Azure Landing Zone'
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
        { Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -OutputFormat Markdown } |
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

Describe 'Wizard — common-parameter eligibility' {
    It 'opens for every PowerShell common parameter when the host is interactive' {
        $commonParameters = @(
            [System.Management.Automation.PSCmdlet]::CommonParameters
            [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        )

        foreach ($name in $commonParameters) {
            & $script:Module {
                param($ParameterName)
                Test-AZSCWizardEligible -BoundParameters @{ $ParameterName = $true } -NoWizard $false -Interactive $true
            } $name | Should -BeTrue
        }
    }

    It 'does not open when the operator supplied a product parameter' {
        & $script:Module {
            Test-AZSCWizardEligible -BoundParameters @{ SkipDiagram = $true } -NoWizard $false -Interactive $true
        } | Should -BeFalse
    }

    It 'honours -NoWizard and non-interactive hosts' -ForEach @(
        @{ NoWizard = $true; Interactive = $true }
        @{ NoWizard = $false; Interactive = $false }
    ) {
        & $script:Module {
            param($NoWizardValue, $InteractiveValue)
            Test-AZSCWizardEligible -BoundParameters @{} -NoWizard $NoWizardValue -Interactive $InteractiveValue
        } $NoWizard $Interactive | Should -BeFalse
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

Describe 'Wizard — grouped assessment checklist (AB#7188)' {
    BeforeAll {
        $script:RegistryKeys = @((Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'manifests/assessments.psd1')).Keys)
    }

    It 'puts every registry key under exactly one heading' {
        $keys = $script:RegistryKeys
        $groups = & $script:Module { param($n) Group-AZSCWizardAssessment -Names $n } $keys
        $flattened = @(foreach ($h in $groups.Keys) { $groups[$h] })
        $flattened.Count | Should -Be $keys.Count
        ($flattened | Sort-Object) | Should -Be ($keys | Sort-Object)
    }

    It 'orders the headings CAF, WAF, Specialized, deep-dives' {
        $groups = & $script:Module { Group-AZSCWizardAssessment -Names @('CAF: Azure Landing Zone') }
        @($groups.Keys) | Should -Be @(
            'Cloud Adoption Framework (CAF)',
            'Well-Architected Framework (WAF)',
            'Specialized reviews',
            'Service category deep-dives'
        )
    }

    It 'sorts each prefix family into its own group' {
        $groups = & $script:Module {
            Group-AZSCWizardAssessment -Names @('CAF: Security', 'WAF: Security', 'Assess: Security', 'Scout: Cost Optimization')
        }
        $groups['Cloud Adoption Framework (CAF)']   | Should -Be @('CAF: Security')
        $groups['Well-Architected Framework (WAF)'] | Should -Be @('WAF: Security')
        $groups['Service category deep-dives']      | Should -Be @('Assess: Security')
        $groups['Specialized reviews']              | Should -Be @('Scout: Cost Optimization')
    }

    It 'never hides an unknown/future key — it lands under Specialized reviews' {
        $groups = & $script:Module { Group-AZSCWizardAssessment -Names @('Scout: Cost Optimization', 'Some Future Review') }
        $groups['Specialized reviews'] | Should -Contain 'Some Future Review'
        $groups['Specialized reviews'] | Should -Contain 'Scout: Cost Optimization'
    }

    It 'a grouped checklist returns the same raw keys as the flat form' {
        $keys = $script:RegistryKeys
        $grouped = & $script:Module {
            param($n)
            Mock -CommandName Read-Host -MockWith { '' }
            Read-AZSCWizardChecklist -Title 'x' -Groups (Group-AZSCWizardAssessment -Names $n)
        } $keys
        $grouped.Count | Should -Be $keys.Count
        ($grouped | Sort-Object) | Should -Be ($keys | Sort-Object)
        # Raw registry keys, verbatim — no display decoration leaks into the return.
        $grouped | Where-Object { $_ -match '^\s|──' } | Should -BeNullOrEmpty
    }

    It 'grouped toggling still returns raw keys with continuous numbering' {
        $result = & $script:Module {
            $script:calls = 0
            Mock -CommandName Read-Host -MockWith {
                $script:calls++
                if ($script:calls -eq 1) { 'n' } elseif ($script:calls -eq 2) { '2,4' } else { '' }
            }
            Read-AZSCWizardChecklist -Title 'x' -Groups ([ordered]@{
                'Cloud Adoption Framework (CAF)'   = @('CAF: A', 'CAF: B')
                'Well-Architected Framework (WAF)' = @('WAF: A')
                'Specialized reviews'              = @('Scout: Cost Optimization')
                'Service category deep-dives'      = @()
            })
        }
        $result | Should -Be @('CAF: B', 'Scout: Cost Optimization')
    }

    It 'CAF: Azure Landing Zone is still the default selection at the wizard call site' {
        $source = Get-Content (Join-Path $script:ModuleRoot 'src/Start-AZSCWizard.ps1') -Raw
        $source | Should -Match "Read-AZSCWizardChecklist -Title 'Assessments to run' -Groups \`$assessmentGroups -DefaultSelected @\('CAF: Azure Landing Zone'\)"
    }

    It 'a grouped checklist honours -DefaultSelected on a bare Enter' {
        $result = & $script:Module {
            param($n)
            Mock -CommandName Read-Host -MockWith { '' }
            Read-AZSCWizardChecklist -Title 'x' -Groups (Group-AZSCWizardAssessment -Names $n) -DefaultSelected @('CAF: Azure Landing Zone')
        } $script:RegistryKeys
        $result | Should -Be @('CAF: Azure Landing Zone')
    }
}

Describe 'Wizard — equivalent command rendering' {
    It 'renders the answers as a runnable Invoke-AzureScout line' {
        $line = & $script:Module {
            Format-AZSCWizardCommand -Answers @{
                TenantID     = '00000000-0000-0000-0000-000000000000'
                Assessment   = @('CAF: Azure Landing Zone')
                OutputFormat = @('Html')
            }
        }
        $line | Should -BeLike 'Invoke-AzureScout *'
        $line | Should -BeLike "*-Assessment 'CAF: Azure Landing Zone'*"
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
