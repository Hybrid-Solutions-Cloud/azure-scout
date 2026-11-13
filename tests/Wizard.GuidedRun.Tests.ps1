#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Walks the guided menu end to end with every prompt answered, and asserts the parameter set
    it hands to Invoke-AzureScout. No Azure connection: sign-in, tenant discovery and category
    coverage are replaced with inert doubles.

    What this defends:
      - accepting every default produces a run that includes network diagrams (the menu used to
        add -SkipDiagram unless the operator ticked a box that was off by default);
      - the menu offers no item that does nothing (the 'Quota usage' box changed nothing);
      - an inventory-only run can set the report cover identity, because it renders the React
        report too;
      - data-gated assessments look for prior runs where runs are actually written.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:Root 'src/Start-AZSCWizard.ps1')

    function Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'tenant-1' }; Account = [pscustomobject]@{ Id = 'operator@example.test' } } }
    function Resolve-AZSCContextIdentity { param($Context) [pscustomobject]@{ AccountDisplayName = 'operator@example.test'; TenantDisplayName = 'Example tenant' } }
    function Get-AZSCAccessibleTenant { @([pscustomobject]@{ Id = 'tenant-1'; Name = 'Example tenant' }) }
    function Get-ScoutCategoryCoverage { param($Category) @() }
    function Connect-AZSCLoginSession { 'tenant-1' }

    $script:WizardSource = Get-Content -Raw (Join-Path $script:Root 'src/Start-AZSCWizard.ps1')
}

Describe 'Guided menu — inventory run accepting every default' {
    BeforeAll {
        Mock Read-Host { '' }
        Mock Write-Host { }
        $script:Result = Start-AZSCWizard
    }

    It 'returns an answer set rather than cancelling' {
        $script:Result | Should -Not -BeNullOrEmpty
        $script:Result.RunBoth | Should -BeFalse
    }

    It 'scans the confirmed tenant' {
        $script:Result.Answers.TenantID | Should -Be 'tenant-1'
    }

    It 'collects every category' {
        @($script:Result.Answers.Category) | Should -Be @('All')
    }

    It 'includes network diagrams by default' {
        $script:Result.Answers.ContainsKey('SkipDiagram') | Should -BeFalse
    }

    It 'includes resource tags by default' {
        $script:Result.Answers.IncludeTags | Should -BeTrue
    }

    It 'renders the React report by default' {
        @($script:Result.Answers.OutputFormat) | Should -Be @('React')
    }

    It 'does not emit a switch for a menu item that does nothing' {
        $script:Result.Answers.ContainsKey('QuotaUsage') | Should -BeFalse
    }

    It 'prints an equivalent command that names only real parameters' {
        $command = Format-AZSCWizardCommand -Answers $script:Result.Answers
        $command | Should -Match '^Invoke-AzureScout '
        $command | Should -Match '-OutputFormat React'
        $command | Should -Not -Match 'SkipDiagram|QuotaUsage'
    }
}

Describe 'Guided menu — choices change the run' {
    BeforeEach { Mock Write-Host { } }

    It 'adds -SkipDiagram only when the operator unticks network diagrams' {
        # Extras checklist is the second checklist of an inventory run; item 4 is diagrams.
        $script:ChecklistCalls = 0
        Mock Read-Host {
            if ($Prompt -eq '  >') {
                $script:ChecklistCalls++
                if ($script:ChecklistCalls -eq 2) { return '4' }
            }
            ''
        }
        $result = Start-AZSCWizard
        $result.Answers.SkipDiagram | Should -BeTrue
    }

    It 'lets an inventory-only run set the report cover identity' {
        Mock Read-Host {
            if ($Prompt -like '*Client / organization name*') { return 'Contoso' }
            ''
        }
        $result = Start-AZSCWizard
        $result.Answers.ReportIdentity.clientName | Should -Be 'Contoso'
    }

    It 'routes Both to a combined run with the default assessment' {
        Mock Read-Host {
            if ($Prompt -like '*Selection (number*') { return '3' }
            ''
        }
        $result = Start-AZSCWizard
        $result.RunBoth | Should -BeTrue
        @($result.Answers.Assessment) | Should -Contain 'CAF: Azure Landing Zone'
        @($result.Answers.Category) | Should -Be @('All')
    }

    It 'adds Entra scope only when the operator opts in' {
        Mock Read-Host {
            if ($Prompt -like '*Also collect Entra ID data*') { return 'y' }
            ''
        }
        (Start-AZSCWizard).Answers.Scope | Should -Be 'All'
        Mock Read-Host { '' }
        (Start-AZSCWizard).Answers.ContainsKey('Scope') | Should -BeFalse
    }

    It 'returns nothing when the operator declines to start the run' {
        Mock Read-Host {
            if ($Prompt -like '*Start the run?*') { return 'n' }
            ''
        }
        Start-AZSCWizard | Should -BeNullOrEmpty
    }
}

Describe 'Guided menu — source contracts' {
    It 'does not offer the Quota usage checkbox' {
        $script:WizardSource | Should -Match "'Include resource tags in reports', 'Security Center findings', 'Cost data', 'Network diagrams'"
        $script:WizardSource | Should -Not -Match "'Cost data', 'Quota usage'"
    }

    It 'looks for prior runs in the default report directory' {
        $script:WizardSource | Should -Match "C:\\AzureScout"
        $script:WizardSource | Should -Match 'collectRoots'
    }

    It 'asks for report identity whenever the React report is produced' {
        $script:WizardSource | Should -Match "if \(\`$formats -contains 'React'\)"
    }
}
