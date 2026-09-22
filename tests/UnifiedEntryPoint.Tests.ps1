#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the single Invoke-AzureScout entry point and its wizard.

.DESCRIPTION
    Inventory and assessment are one command with different switches, not two
    products. These tests pin that contract:

      - Invoke-AzureScout exposes the assessment-mode parameters.
      - Inventory, assessment, and combined runs share one live output contract.
      - Legacy formats still bind, warn, and fall back without invoking held renderers.
      - The wizard never fires in a non-interactive host, so CI and scheduled
        runs of a bare `Invoke-AzureScout` cannot block on a prompt.
      - The wizard's checklist/selection primitives behave.

    No live Azure authentication is required.

.NOTES
    Tracks AB#5540 (single entry point, per AB#5024) and AB#5541 (guided wizard).
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path -Path $script:ModuleRoot -ChildPath 'AzureScout.psd1') -Force
    $script:Module = Get-Module AzureScout
    $script:Cmd    = Get-Command Invoke-AzureScout
}

Describe 'Single entry point — parameter surface' {
    It 'Invoke-AzureScout exposes -<Name>' -ForEach @(
        @{ Name = 'Assessment' }
        @{ Name = 'CollectOnly' }
        @{ Name = 'FromCollect' }
        @{ Name = 'NoWizard' }
        @{ Name = 'NoProgress' }
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
        Import-Module (Join-Path -Path $script:ModuleRoot -ChildPath 'AzureScout.psd1') -Force -ErrorAction Stop
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
        $modulePath = (Join-Path -Path $script:ModuleRoot -ChildPath 'AzureScout.psd1').Replace("'", "''")
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
    It 'keeps live and held legacy names in the public ValidateSet' {
        $vs = $script:Cmd.Parameters['OutputFormat'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        foreach ($format in @('All', 'React', 'Json', 'JsonEvidence', 'Excel', 'Markdown', 'Pptx', 'Word')) {
            $vs.ValidValues | Should -Contain $format
        }
    }

    It 'defines one live-format set and the held-only React fallback' {
        $source = Get-Content -Raw (Join-Path $script:ModuleRoot 'src/Invoke-AzureScout.ps1')
        $source | Should -Match "\`$liveFormats = @\('React', 'Json', 'JsonEvidence'\)"
        $source | Should -Match 'every requested report format is on hold; rendering the React report instead'
    }

    It 'lets Both carry React and JsonEvidence past the inventory format guard' {
        $result = & $script:Module {
            $script:CombinedLoginCalls = 0
            Mock -CommandName Test-AZSCPS -MockWith { 'Windows' }
            Mock -CommandName Connect-AZSCLoginSession -MockWith {
                $script:CombinedLoginCalls++
                return 'test-tenant'
            }
            Mock -CommandName Get-AzContext -MockWith {
                [pscustomobject]@{
                    Account      = [pscustomobject]@{ Id = 'test@example.invalid' }
                    Subscription = [pscustomobject]@{ Id = 'sub-1'; Name = 'Test' }
                    Tenant       = [pscustomobject]@{ Id = 'test-tenant' }
                }
            }
            # Stop at the first inventory-only operation after authentication.
            # This proves the combined live-format guard was passed without ever
            # allowing the regression harness to touch the developer's Az context.
            Mock -CommandName Get-AZSCSubscriptions -MockWith {
                throw 'REGRESSION-GATE: combined run reached the inventory phase'
            }

            $message = try {
                Invoke-AzureScout `
                    -Assessment 'CAF: Azure Landing Zone' `
                    -InventoryAndAssessment `
                    -OutputFormat React, JsonEvidence `
                    -NoWizard
                '<no error>'
            }
            catch { $_.Exception.Message }

            [pscustomobject]@{ Message = $message; LoginCalls = $script:CombinedLoginCalls }
        }

        $result.Message | Should -Be 'REGRESSION-GATE: combined run reached the inventory phase'
        $result.LoginCalls | Should -Be 1
    }

    It 'completes a JSON-only inventory and retains its raw and processed discovery data' {
        $work = $TestDrive

        {
            & $script:Module {
                param($Work)

                Mock Test-AZSCPS { 'Linux' }
                Mock Test-AZSCInteractiveHost { $false }
                Mock Connect-AZSCLoginSession { 'test-tenant' }
                Mock Get-AzContext {
                    [pscustomobject]@{
                        Account      = [pscustomobject]@{ Id = 'test@example.invalid' }
                        Subscription = [pscustomobject]@{ Id = 'sub-1'; Name = 'Test' }
                        Tenant       = [pscustomobject]@{ Id = 'test-tenant' }
                    }
                }
                Mock Test-AZSCManagementGroupAccess { [pscustomobject]@{ HasAccess = $true; Count = 1 } }
                Mock Get-AZSCSubscriptions { @([pscustomobject]@{ Id = 'sub-1'; Name = 'Test' }) }
                Mock Set-AZSCReportPath {
                    @{
                        DefaultPath  = $Work
                        DiagramCache = Join-Path $Work 'DiagramCache'
                        ReportCache  = Join-Path $Work 'ReportCache'
                    }
                }
                Mock Set-AZSCFolder {
                    New-Item -ItemType Directory -Path (Join-Path $Work 'DiagramCache') -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $Work 'ReportCache') -Force | Out-Null
                }
                Mock Start-AZSCRunLog
                Mock Write-AZSCLog
                Mock Write-AZSCLogPhase
                Mock Write-Warning
                Mock Clear-AZSCCacheFolder
                Mock Get-Module { [pscustomobject]@{ Version = [version]'3.10.0' } } -ParameterFilter { $Name -eq 'AzureScout' }
                Mock Start-AZSCExtractionOrchestration {
                    [pscustomobject]@{
                        Resources          = @()
                        EntraResources     = @()
                        Quotas             = @()
                        Costs              = @()
                        ResourceContainers = @()
                        Advisories         = @()
                        ResourcesCount     = 0
                        AdvisoryCount      = 0
                        SecCenterCount     = 0
                        Security           = @()
                        Retirements        = @()
                        PolicyCount        = 0
                        PolicyAssign       = @()
                        PolicyDef          = @()
                        PolicySetDef       = @()
                    }
                }
                Mock Export-ScoutRawInventoryDump {
                    $path = Join-Path $Work 'raw-inventory.json'
                    '{"schema":"azure-scout/raw-inventory/v1"}' | Set-Content -LiteralPath $path
                    $path
                }
                Mock Start-AZSCExtraJobs { @{} }
                Mock Start-AZSCProcessOrchestration {
                    $path = Join-Path $Work 'ReportCache/Compute.json'
                    '[]' | Set-Content -LiteralPath $path
                }
                Mock Export-AZSCJsonReport { Join-Path $Work 'AzureScout.json' }
                Mock Clear-AZSCMemory
                Mock Out-AZSCReportResults
                Mock Stop-AZSCRunLog { Join-Path $Work 'AzureScout.log' }

                Invoke-AzureScout -NoWizard -OutputFormat Json -SkipPermissionCheck -SkipDiagram

                Should -Invoke Export-AZSCJsonReport -Exactly 1
                Should -Invoke Out-AZSCReportResults -Exactly 1 -ParameterFilter { $TotalRes -eq 0 }
                Should -Invoke Clear-AZSCCacheFolder -Exactly 1
                Test-Path -LiteralPath (Join-Path $Work 'raw-inventory.json') | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $Work 'ReportCache/Compute.json') | Should -BeTrue
            } $work
        } | Should -Not -Throw
    }

    It 'renders inventory-only React and JsonEvidence offline without assessment rules' {
        $work = Join-Path $TestDrive 'inventory-live-formats'
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        {
            & $script:Module {
                param($Work)

                Mock Test-AZSCPS { 'Linux' }
                Mock Test-AZSCInteractiveHost { $false }
                Mock Connect-AZSCLoginSession { 'test-tenant' }
                Mock Get-AzContext { [pscustomobject]@{ Account=[pscustomobject]@{Id='test@example.invalid'}; Subscription=[pscustomobject]@{Id='sub-1';Name='Test'}; Tenant=[pscustomobject]@{Id='test-tenant'} } }
                Mock Test-AZSCManagementGroupAccess { [pscustomobject]@{ HasAccess=$true; Count=1 } }
                Mock Get-AZSCSubscriptions { @([pscustomobject]@{ Id='sub-1'; Name='Test' }) }
                Mock Set-AZSCReportPath { @{ DefaultPath=$Work; DiagramCache=(Join-Path $Work 'DiagramCache'); ReportCache=(Join-Path $Work 'ReportCache') } }
                Mock Set-AZSCFolder
                Mock Start-AZSCRunLog
                Mock Write-AZSCLog
                Mock Write-AZSCLogPhase
                Mock Clear-AZSCCacheFolder
                Mock Get-Module { [pscustomobject]@{ Version=[version]'3.10.0' } } -ParameterFilter { $Name -eq 'AzureScout' }
                Mock Start-AZSCExtractionOrchestration {
                    [pscustomobject]@{
                        Resources=@(); EntraResources=@([pscustomobject]@{ id='user-1'; TYPE='entra/users' }); Quotas=@(); Costs=@(); ResourceContainers=@(); Advisories=@()
                        ResourcesCount=0; AdvisoryCount=0; SecCenterCount=0; Security=@(); Retirements=@(); PolicyCount=0
                        PolicyAssign=@(); PolicyDef=@(); PolicySetDef=@()
                    }
                }
                Mock Export-ScoutRawInventoryDump { Join-Path $Work 'raw-inventory.json' }
                Mock Start-AZSCExtraJobs { @{} }
                Mock Start-AZSCProcessOrchestration
                Mock Invoke-ScoutAssessmentCore {
                    $renderPath = Join-Path $Work 'assessment-report'
                    New-Item -ItemType Directory -Path $renderPath -Force | Out-Null
                    '<html></html>' | Set-Content (Join-Path $renderPath 'report-react.html')
                    '{}' | Set-Content (Join-Path $renderPath 'evidence.json')
                    return $renderPath
                }
                Mock Export-AZSCJsonReport { Join-Path $Work 'AzureScout.json' }
                Mock Write-Warning
                Mock New-AzStorageContext { [pscustomobject]@{ AccountName = 'storage' } }
                function Set-AzStorageBlobContent {
                    param($File, $Container, $Context, [switch]$Force)
                }
                Mock Set-AzStorageBlobContent
                Mock Clear-AZSCMemory
                Mock Out-AZSCReportResults
                Mock Stop-AZSCRunLog { Join-Path $Work 'AzureScout.log' }

                Invoke-AzureScout -NoWizard -OutputFormat React,JsonEvidence -Scope All -SkipPermissionCheck -SkipDiagram

                Should -Invoke Invoke-ScoutAssessmentCore -Exactly 1 -ParameterFilter {
                    $InventoryOnly -and $OutputFormat -contains 'React' -and
                        $OutputFormat -contains 'JsonEvidence' -and $null -ne $FromInventory
                }
                Should -Invoke Export-AZSCJsonReport -Exactly 0

                Invoke-AzureScout -NoWizard -OutputFormat All -Scope All -SkipPermissionCheck -SkipDiagram
                Should -Invoke Invoke-ScoutAssessmentCore -Exactly 2 -ParameterFilter {
                    $InventoryOnly -and $OutputFormat -contains 'React' -and
                        $OutputFormat -contains 'JsonEvidence' -and $null -ne $FromInventory
                }
                Should -Invoke Export-AZSCJsonReport -Exactly 1

                Invoke-AzureScout -NoWizard -OutputFormat Pptx -Scope All -SkipPermissionCheck -SkipDiagram -Verbose
                Should -Invoke Invoke-ScoutAssessmentCore -Exactly 1 -ParameterFilter {
                    $InventoryOnly -and @($OutputFormat).Count -eq 1 -and $OutputFormat -contains 'React'
                }
                Should -Invoke Write-Warning -ParameterFilter { $Message -like '*on hold*Pptx*' }

                Invoke-AzureScout -NoWizard -OutputFormat Excel,Json -Scope All -SkipPermissionCheck -SkipDiagram -Verbose
                Should -Invoke Invoke-ScoutAssessmentCore -Exactly 3
                Should -Invoke Export-AZSCJsonReport -Exactly 2
                Should -Invoke Write-Warning -ParameterFilter { $Message -like '*on hold*Excel*' }

                Invoke-AzureScout -NoWizard -OutputFormat All -Scope All -SkipPermissionCheck -SkipDiagram `
                    -StorageAccount storage -StorageContainer reports
                Should -Invoke Set-AzStorageBlobContent -Exactly 3
                Should -Invoke Set-AzStorageBlobContent -Exactly 1 -ParameterFilter { (Split-Path -Leaf $File) -eq 'AzureScout.json' }
                Should -Invoke Set-AzStorageBlobContent -Exactly 1 -ParameterFilter { (Split-Path -Leaf $File) -eq 'report-react.html' }
                Should -Invoke Set-AzStorageBlobContent -Exactly 1 -ParameterFilter { (Split-Path -Leaf $File) -eq 'evidence.json' }
            } $work
        } | Should -Not -Throw
    }

    It 'completes Both with React and JsonEvidence through deferred assessment' {
        $work = Join-Path $TestDrive 'both-react'
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        {
            & $script:Module {
                param($Work)

                Mock Test-AZSCPS { 'Linux' }
                Mock Test-AZSCInteractiveHost { $false }
                Mock Connect-AZSCLoginSession { 'test-tenant' }
                Mock Get-AzContext { [pscustomobject]@{ Account=[pscustomobject]@{Id='test@example.invalid'}; Subscription=[pscustomobject]@{Id='sub-1';Name='Test'}; Tenant=[pscustomobject]@{Id='test-tenant'} } }
                Mock Test-AZSCManagementGroupAccess { [pscustomobject]@{ HasAccess=$true; Count=1 } }
                Mock Get-AZSCSubscriptions { @([pscustomobject]@{ Id='sub-1'; Name='Test' }) }
                Mock Set-AZSCReportPath { @{ DefaultPath=$Work; DiagramCache=(Join-Path $Work 'DiagramCache'); ReportCache=(Join-Path $Work 'ReportCache') } }
                Mock Set-AZSCFolder
                Mock Start-AZSCRunLog
                Mock Write-AZSCLog
                Mock Write-AZSCLogPhase
                Mock Write-Warning
                Mock Clear-AZSCCacheFolder
                Mock Get-Module { [pscustomobject]@{ Version=[version]'3.10.0' } } -ParameterFilter { $Name -eq 'AzureScout' }
                Mock Start-AZSCExtractionOrchestration {
                    [pscustomobject]@{
                        Resources=@(); EntraResources=@(); Quotas=@(); Costs=@(); ResourceContainers=@(); Advisories=@()
                        ResourcesCount=0; AdvisoryCount=0; SecCenterCount=0; Security=@(); Retirements=@(); PolicyCount=0
                        PolicyAssign=@(); PolicyDef=@(); PolicySetDef=@()
                    }
                }
                Mock Export-ScoutRawInventoryDump { Join-Path $Work 'raw-inventory.json' }
                Mock Start-AZSCExtraJobs { @{} }
                Mock Start-AZSCProcessOrchestration
                Mock Invoke-ScoutAssessmentCore {
                    $assessmentPath = Join-Path $Work 'assessment-report'
                    New-Item -ItemType Directory -Path $assessmentPath -Force | Out-Null
                    '<html></html>' | Set-Content (Join-Path $assessmentPath 'report-react.html')
                    return $assessmentPath
                }
                Mock Clear-AZSCMemory
                Mock Out-AZSCReportResults
                Mock Stop-AZSCRunLog { Join-Path $Work 'AzureScout.log' }

                Invoke-AzureScout -NoWizard -Assessment 'CAF: Azure Landing Zone' -InventoryAndAssessment `
                    -OutputFormat React,JsonEvidence -SkipPermissionCheck -SkipDiagram

                Should -Invoke Invoke-ScoutAssessmentCore -Exactly 1 -ParameterFilter {
                    $OutputFormat -contains 'React' -and $OutputFormat -contains 'JsonEvidence' -and $null -ne $FromInventory
                }
                Should -Invoke Connect-AZSCLoginSession -Exactly 1
                Should -Invoke Out-AZSCReportResults -Exactly 1 -ParameterFilter { $TotalRes -eq 0 }

                Mock Invoke-ScoutAssessmentCore {
                    $exception = [System.InvalidOperationException]::new('required source unavailable')
                    $exception.Data['AzureScoutFailureKind'] = 'AssessmentSourceUnavailable'
                    throw $exception
                }

                Invoke-AzureScout -NoWizard -Assessment 'CAF: Azure Landing Zone' -InventoryAndAssessment `
                    -OutputFormat React,JsonEvidence -SkipPermissionCheck -SkipDiagram

                Should -Invoke Invoke-ScoutAssessmentCore -Exactly 2
                Should -Invoke Start-AZSCProcessOrchestration -Exactly 2
                Should -Invoke Out-AZSCReportResults -Exactly 2
                Should -Invoke Write-Warning -ParameterFilter { $Message -like '*skipped*assessment*inventory run will continue*' }
            } $work
        } | Should -Not -Throw
    }

    It 'uploads all selected live artifacts for a standalone automated assessment' {
        $work = Join-Path $TestDrive 'standalone-assessment-storage'
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        {
            & $script:Module {
                param($Work)

                Mock Test-AZSCPS { 'Linux' }
                Mock Test-AZSCInteractiveHost { $false }
                Mock Invoke-ScoutAssessmentCore {
                    $runPath = Join-Path $Work 'assessment-report'
                    New-Item -ItemType Directory -Path $runPath -Force | Out-Null
                    '<html></html>' | Set-Content (Join-Path $runPath 'report-react.html')
                    '{}' | Set-Content (Join-Path $runPath 'findings.json')
                    '{}' | Set-Content (Join-Path $runPath 'evidence.json')
                    return $runPath
                }
                Mock New-AzStorageContext { [pscustomobject]@{ AccountName = 'storage' } }
                function Set-AzStorageBlobContent {
                    param($File, $Container, $Context, [switch]$Force)
                }
                Mock Set-AzStorageBlobContent

                $result = Invoke-AzureScout -NoWizard -Assessment 'CAF: Azure Landing Zone' `
                    -OutputFormat All -Automation -StorageAccount storage -StorageContainer reports

                $result | Should -Be (Join-Path $Work 'assessment-report')
                Should -Invoke Invoke-ScoutAssessmentCore -Exactly 1 -ParameterFilter {
                    $OutputFormat -contains 'React' -and $OutputFormat -contains 'Json' -and
                        $OutputFormat -contains 'JsonEvidence'
                }
                Should -Invoke Set-AzStorageBlobContent -Exactly 3 -ParameterFilter {
                    $Container -eq 'reports' -and $Force
                }
                foreach ($leaf in 'report-react.html', 'findings.json', 'evidence.json') {
                    Should -Invoke Set-AzStorageBlobContent -Exactly 1 -ParameterFilter {
                        (Split-Path -Leaf $File) -eq $leaf
                    }
                }
            } $work
        } | Should -Not -Throw
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
        $script:RegistryKeys = @((Import-PowerShellDataFile (Join-Path -Path $script:ModuleRoot -ChildPath 'manifests/assessments.psd1')).Keys)
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
        $source = Get-Content (Join-Path -Path $script:ModuleRoot -ChildPath 'src/Start-AZSCWizard.ps1') -Raw
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

Describe 'Wizard — combined run contract' {
    BeforeEach {
        & $script:Module {
            Mock -CommandName Write-Host -MockWith {}
            Mock -CommandName Get-AzContext -MockWith {
                [pscustomobject]@{
                    Account = [pscustomobject]@{ Id = 'test@example.invalid' }
                    Tenant  = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
                }
            }
            Mock -CommandName Get-AzTenant -MockWith {
                @([pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'Test' })
            }
            Mock -CommandName Test-AZSCPermissions -MockWith {
                [pscustomobject]@{ Details = @(); OverallReadiness = 'ARMOnly' }
            }
            Mock -CommandName Get-ScoutAvailableAssessment -MockWith { @('CAF: Azure Landing Zone') }
            Mock -CommandName Get-ScoutCategoryCoverage -MockWith { @() }
        }
    }

    It 'offers the same live output formats for every run type' {
        $source = Get-Content -Raw (Join-Path $script:ModuleRoot 'src/Start-AZSCWizard.ps1')
        $source | Should -Match "\`$liveFormats = @\('React', 'Json', 'JsonEvidence'\)"
        $source | Should -Match '\$formatPool = \$liveFormats'
        $source | Should -Not -Match '\$inventoryFormats\s*='
        $source | Should -Not -Match '\$assessmentFormats\s*='
    }

    It 'defers permission validation so a guided run executes one selected-scope audit' {
        $wizardSource = Get-Content -Raw (Join-Path $script:ModuleRoot 'src/Start-AZSCWizard.ps1')
        $entrySource = Get-Content -Raw (Join-Path $script:ModuleRoot 'src/Invoke-AzureScout.ps1')
        $wizardSource | Should -Not -Match 'Test-AZSCPermissions'
        ([regex]::Matches($entrySource, 'Test-AZSCPermissions -TenantID')).Count | Should -Be 1
        $entrySource | Should -Not -Match 'Test-AZSCManagementGroupAccess'
    }

    It 'returns Both with React and JsonEvidence selected' {
        $result = & $script:Module {
            $script:WizardResponses = [System.Collections.Generic.Queue[string]]::new()
            @('', '3', '', '', '', '', '3', '', '', '', '', '', '', '') |
                ForEach-Object { $script:WizardResponses.Enqueue($_) }
            Mock -CommandName Read-Host -MockWith { $script:WizardResponses.Dequeue() }

            Start-AZSCWizard -AzureEnvironment AzureCloud -PlatOS Windows
        }

        $result.RunBoth | Should -BeTrue
        $result.Answers.Assessment | Should -Be @('CAF: Azure Landing Zone')
        $result.Answers.OutputFormat | Should -Be @('React', 'JsonEvidence')
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
