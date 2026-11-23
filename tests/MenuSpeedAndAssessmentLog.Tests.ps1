#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Regression tests for two problems found while a user drove a real multi-tenant run.

.DESCRIPTION
    1. After the "Optional report and enrichment features" checklist the guided menu paused for
       about a minute. It checked each data-gated assessment by calling Resolve-JsonPath on the
       newest collect.json, and every call converted the whole document back to JSON text and
       re-parsed it: about 5 seconds per gate on a 28 MB file, eight gates in the registry.
       The file is now parsed once and every gate queries that one token.

    2. An assessment-only run (-Assessment without -InventoryAndAssessment) never started
       scout-run.log. Every multi-tenant child of an assessment-only run left its attempt folder
       empty for the whole collection, so an operator watching a slow tenant had nothing to read.

    No live Azure authentication is required.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'AzureScout.psd1') -Force
    $script:Module = Get-Module AzureScout
}

Describe 'Guided menu — data-gated assessments' {
    BeforeAll {
        $script:Manifest = @{
            'CAF: Azure Landing Zone' = @{ Rules = @('caf-*') }
            'Workload: AVS'           = @{ Rules = @('avs-*'); RequiresData = @('$.compute.privateClouds[*]') }
            'Microsoft: SMART Migration' = @{ Rules = @('smart-*'); RequiresData = @('$.domains.migration.migrateProjects[*]', '$.domains.migration.discoverySites[*]') }
        }
        $script:Names = @('CAF: Azure Landing Zone', 'Workload: AVS', 'Microsoft: SMART Migration')
    }

    It 'offers a gated assessment only when its data has rows' {
        $file = Join-Path $TestDrive 'collect-avs.json'
        '{ "compute": { "privateClouds": [ { "id": "pc1" } ] }, "domains": { "migration": { "migrateProjects": [], "discoverySites": [] } } }' |
            Set-Content -LiteralPath $file
        $kept = & $script:Module { param($n, $m, $f) @(Select-AZSCWizardDataGatedAssessment -Names $n -Manifest $m -CollectPath $f) } $script:Names $script:Manifest $file
        $kept | Should -Be @('CAF: Azure Landing Zone', 'Workload: AVS')
    }

    It 'accepts any one of several gates' {
        $file = Join-Path $TestDrive 'collect-smart.json'
        '{ "domains": { "migration": { "migrateProjects": [], "discoverySites": [ { "id": "s1" } ] } } }' | Set-Content -LiteralPath $file
        $kept = & $script:Module { param($n, $m, $f) @(Select-AZSCWizardDataGatedAssessment -Names $n -Manifest $m -CollectPath $f) } $script:Names $script:Manifest $file
        $kept | Should -Be @('CAF: Azure Landing Zone', 'Microsoft: SMART Migration')
    }

    It 'hides every gated assessment when there is no collect.json, and keeps the ungated ones' {
        $kept = & $script:Module { param($n, $m) @(Select-AZSCWizardDataGatedAssessment -Names $n -Manifest $m -CollectPath $null) } $script:Names $script:Manifest
        $kept | Should -Be @('CAF: Azure Landing Zone')
    }

    It 'hides gated assessments when the collect.json cannot be parsed' {
        $file = Join-Path $TestDrive 'broken.json'
        '{ not json' | Set-Content -LiteralPath $file
        $kept = & $script:Module { param($n, $m, $f) @(Select-AZSCWizardDataGatedAssessment -Names $n -Manifest $m -CollectPath $f) } $script:Names $script:Manifest $file
        $kept | Should -Be @('CAF: Azure Landing Zone')
    }

    It 'parses the file once instead of calling Resolve-JsonPath per gate' {
        $source = Get-Content -Raw (Join-Path $script:ModuleRoot 'src/Start-AZSCWizard.ps1')
        $source | Should -Match 'Select-AZSCWizardDataGatedAssessment -Names \$assessmentNames'
        $source | Should -Not -Match 'Resolve-JsonPath -InputObject \$collectObject'
    }

    It 'checks every gate in a large collect.json in well under the old per-gate cost' {
        $file = Join-Path $TestDrive 'collect-large.json'
        $rows = 1..40000 | ForEach-Object { @{ id = "r$_"; name = "resource-$_"; properties = @{ a = $_; b = 'x' * 40 } } }
        @{ compute = @{ privateClouds = @(); virtualMachines = $rows }; domains = @{ migration = @{ migrateProjects = @(); discoverySites = @() } } } |
            ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $file
        $elapsed = Measure-Command {
            $null = & $script:Module { param($n, $m, $f) Select-AZSCWizardDataGatedAssessment -Names $n -Manifest $m -CollectPath $f } $script:Names $script:Manifest $file
        }
        # One parse of a ~5 MB file. The old path re-serialised the document for each of the
        # three gates here and took several seconds; the bound is generous for slow CI agents.
        $elapsed.TotalSeconds | Should -BeLessThan 5
    }
}

Describe 'Multi-tenant run stopped mid-tenant' {
    It 'records the tenant and the run as Interrupted instead of leaving them Running' {
        # A live run stopped with Ctrl+C left run-summary.json saying "Running" for good.
        # PowerShell.Stop() is what Ctrl+C does to a pipeline: no catch block runs, only finally.
        $out = Join-Path $TestDrive 'interrupted'
        $modulePath = Join-Path $script:ModuleRoot 'AzureScout.psd1'
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($ModulePath, $Out)
            $env:CI = 'true'
            Import-Module $ModulePath -Force
            & (Get-Module AzureScout) {
                param($Out)
                function script:Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'operator@example.test' }; Tenant = [pscustomobject]@{ Id = 'tenant-a' } } }
                function script:Set-AzContext { }
                function script:Connect-AZSCLoginSession { 'tenant-a' }
                function script:Get-AZSCAccessibleTenant {
                    @([pscustomobject]@{ Id = 'tenant-a'; Name = 'Tenant A' }, [pscustomobject]@{ Id = 'tenant-b'; Name = 'Tenant B' })
                }
                $runner = { Start-Sleep -Seconds 120 }
                Invoke-AZSCMultiTenantRun -InvocationParameters @{
                    ReportDir = $Out; RunName = 'stopped-run'; Scope = 'All'; OutputFormat = @('React')
                    InventoryAndAssessment = $true; NoWizard = $true
                } -RequestedTenantId @('tenant-a', 'tenant-b') -TenantRunner $runner -WarningAction SilentlyContinue
            } $Out
        }).AddArgument($modulePath).AddArgument($out)
        $null = $ps.BeginInvoke()

        $summaryFile = $null
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline) {
            $summaryFile = Get-ChildItem -LiteralPath $out -Recurse -Filter 'run-summary.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($summaryFile) {
                try {
                    $peek = Get-Content -Raw -LiteralPath $summaryFile.FullName | ConvertFrom-Json
                    if (@($peek.Tenants)[0].Status -eq 'Running') { break }
                }
                catch { Write-Verbose "summary mid-write: $_" }
            }
            Start-Sleep -Milliseconds 200
        }
        $ps.Stop()
        $ps.Dispose()

        $summaryFile | Should -Not -BeNullOrEmpty
        $summary = Get-Content -Raw -LiteralPath $summaryFile.FullName | ConvertFrom-Json
        $summary.Status | Should -Be 'Interrupted'
        $summary.CompletedAt | Should -Not -BeNullOrEmpty
        $first = @($summary.Tenants)[0]
        $first.Status | Should -Be 'Interrupted'
        $first.Error | Should -Match 'ResumeRun'
        @($first.Attempts)[-1].Status | Should -Be 'Interrupted'
        @($summary.Tenants)[1].Status | Should -Be 'Pending'
        $summary.Counts.Interrupted | Should -Be 1
        $summary.Counts.Running | Should -Be 0
    }
}

Describe 'Assessment-only runs write scout-run.log' {
    It 'writes the log into -ReportDir and closes it as COMPLETED' {
        $work = Join-Path $TestDrive 'assess-ok'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        & $script:Module {
            param($Work)
            Mock Test-AZSCPS { 'Linux' }
            Mock Test-AZSCInteractiveHost { $false }
            Mock Connect-AZSCLoginSession { 'tenant-1' }
            Mock Invoke-ScoutAssessmentCore {
                Write-AZSCLog -Message 'collector ran inside the assessment core'
                $runPath = Join-Path $Work 'assessment-report'
                New-Item -ItemType Directory -Path $runPath -Force | Out-Null
                '<html></html>' | Set-Content (Join-Path $runPath 'report-react.html')
                return $runPath
            }
            $null = Invoke-AzureScout -NoWizard -NoProgress -Assessment 'CAF: Azure Landing Zone' -ReportDir $Work -OutputFormat React -TenantID 'tenant-1' -NonInteractiveAuth 6>$null
        } $work

        $log = Join-Path $work 'scout-run.log'
        Test-Path -LiteralPath $log | Should -BeTrue
        $text = Get-Content -Raw -LiteralPath $log
        $text | Should -Match 'Mode\s+: Assessment only'
        $text | Should -Match 'collector ran inside the assessment core'
        $text | Should -Match 'Scan/log execution COMPLETED'
    }

    It 'records the error and closes the log as FAILED when the assessment throws' {
        $work = Join-Path $TestDrive 'assess-fail'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        {
            & $script:Module {
                param($Work)
                Mock Test-AZSCPS { 'Linux' }
                Mock Test-AZSCInteractiveHost { $false }
                Mock Connect-AZSCLoginSession { 'tenant-1' }
                Mock Invoke-ScoutAssessmentCore { throw 'simulated collection failure' }
                $null = Invoke-AzureScout -NoWizard -NoProgress -Assessment 'CAF: Azure Landing Zone' -ReportDir $Work -OutputFormat React -TenantID 'tenant-1' -NonInteractiveAuth 6>$null
            } $work
        } | Should -Throw '*simulated collection failure*'

        $text = Get-Content -Raw -LiteralPath (Join-Path $work 'scout-run.log')
        $text | Should -Match 'RUN FAILED'
        $text | Should -Match 'simulated collection failure'
        $text | Should -Match 'Scan/log execution FAILED'
    }
}
