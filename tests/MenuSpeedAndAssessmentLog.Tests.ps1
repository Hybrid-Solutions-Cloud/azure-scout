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
        # A fresh runspace imports the whole module first; under a loaded full-suite run that has
        # taken longer than 90 seconds, so allow five minutes before giving up.
        $deadline = (Get-Date).AddSeconds(300)
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

Describe 'One run, one log file' {
    It 'writes every tenant of a multi-tenant run into one scout-run.log at the run root' {
        $out = Join-Path $TestDrive 'one-log'
        & $script:Module {
            param($Out)
            Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'operator@example.test' }; Tenant = [pscustomobject]@{ Id = 'tenant-a' } } }
            Mock Set-AzContext { }
            Mock Connect-AZSCLoginSession { 'tenant-a' }
            Mock Get-AZSCAccessibleTenant { @([pscustomobject]@{ Id = 'tenant-a'; Name = 'Tenant A' }, [pscustomobject]@{ Id = 'tenant-b'; Name = 'Tenant B' }) }
            # Stands in for Invoke-AzureScout: starts and stops "its" run log in the tenant folder,
            # writes a line and a console line, and returns a typed result with a report.
            $runner = {
                param($Arguments)
                $tenant = [string]@($Arguments.TenantID)[0]
                Start-AZSCRunLog -DefaultPath $Arguments.ReportDir -Metadata @{ Tenant = $tenant }
                Write-AZSCLog -Message "collected data for $tenant"
                Write-Host "console line for $tenant"
                $react = Join-Path $Arguments.ReportDir 'assessment-report/report-react.html'
                $null = New-Item -ItemType Directory -Path (Split-Path $react) -Force
                '<html></html>' | Set-Content -LiteralPath $react
                $null = Stop-AZSCRunLog -Status COMPLETED -Quiet
                New-AZSCRunResult -TenantId $tenant -OutputPath $Arguments.ReportDir -ReactFile $react -SubscriptionCount 1 -ResourceCount 2 -Status 'Completed'
            }
            $null = Invoke-AZSCMultiTenantRun -InvocationParameters @{
                ReportDir = $Out; RunName = 'one-log-run'; Scope = 'All'; OutputFormat = @('React'); InventoryAndAssessment = $true; NoWizard = $true
            } -RequestedTenantId @('tenant-a', 'tenant-b') -TenantRunner $runner -WarningAction SilentlyContinue 6>$null
        } $out

        $logs = @(Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Name -match '\.log$' })
        $logs.Count | Should -Be 1
        $logs[0].Name | Should -Be 'scout-run.log'
        $logs[0].Directory.Name | Should -Be 'one-log-run'
        $text = Get-Content -Raw -LiteralPath $logs[0].FullName
        $text | Should -Match 'Mode\s+: Multi-tenant'
        $text | Should -Match 'Tenant 1/2 started: Tenant A'
        $text | Should -Match 'collected data for tenant-a'
        $text | Should -Match '\[CONSOLE\] console line for tenant-a'
        $text | Should -Match 'Tenant 2/2 finished: Tenant B -> Completed'
        $text | Should -Match 'collected data for tenant-b'
        ([regex]::Matches($text, 'Tenant section COMPLETED')).Count | Should -Be 2
        $text | Should -Match 'Multi-tenant run status: Completed'
        $text | Should -Match 'Scan/log execution COMPLETED'
    }

    It 'copies console output into the run log, joining -NoNewline pieces into one line' {
        $dir = Join-Path $TestDrive 'console'
        & $script:Module {
            param($Dir)
            Start-AZSCRunLog -DefaultPath $Dir
            Write-Host '  Run folder   : ' -NoNewline 6>$null
            Write-Host 'C:\somewhere' 6>$null
            $null = Stop-AZSCRunLog -Quiet
        } $dir
        $text = Get-Content -Raw -LiteralPath (Join-Path $dir 'scout-run.log')
        $text | Should -Match '\[CONSOLE\]\s+Run folder   : C:\\somewhere'
        Test-Path -LiteralPath (Join-Path $dir 'scout-console.log') | Should -BeFalse
    }

    It 'folds the diagram builder log into scout-run.log and removes the file' {
        $dir = Join-Path $TestDrive 'diagram'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $side = Join-Path $dir 'DiagramLogFile.log'
        "DrawIOCoreFile - starting`nDrawIOCoreFile - Diagram Complete" | Set-Content -LiteralPath $side
        & $script:Module {
            param($Dir, $Side)
            Start-AZSCRunLog -DefaultPath $Dir
            Add-ScoutFileToRunLog -Path $Side -Label 'DIAGRAM'
            $null = Stop-AZSCRunLog -Quiet
        } $dir $side
        Test-Path -LiteralPath $side | Should -BeFalse
        (Get-Content -Raw -LiteralPath (Join-Path $dir 'scout-run.log')) | Should -Match '\[DIAGRAM\] DrawIOCoreFile - Diagram Complete'
    }
}

Describe 'Assessment collect names the tenant''s subscriptions' {
    It 'passes the tenant''s enabled subscriptions to the raw inventory pass' {
        & $script:Module {
            Mock Get-AzSubscription {
                @([pscustomobject]@{ Id = 'sub-1'; State = 'Enabled' }, [pscustomobject]@{ Id = 'sub-2'; State = 'Disabled' }, [pscustomobject]@{ Id = 'sub-3'; State = 'Enabled' })
            }
            Mock Get-ScoutRawInventory { throw 'stop after capture' }
            function Search-AzGraph { }
            try { $null = Invoke-Collect -TenantID 'tenant-x' -WarningAction SilentlyContinue } catch { $null = $_ }
            Should -Invoke Get-AzSubscription -Times 1 -ParameterFilter { $TenantId -eq 'tenant-x' }
            Should -Invoke Get-ScoutRawInventory -Times 1 -ParameterFilter { (@($SubscriptionIds) -join ',') -eq 'sub-1,sub-3' }
        }
    }

    It 'does not name subscriptions when the collect is scoped to a management group' {
        & $script:Module {
            Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; State = 'Enabled' }) }
            Mock Get-ScoutRawInventory { throw 'stop after capture' }
            function Search-AzGraph { }
            try { $null = Invoke-Collect -TenantID 'tenant-x' -ManagementGroupId 'mg-1' -WarningAction SilentlyContinue } catch { $null = $_ }
            Should -Invoke Get-AzSubscription -Times 0
            Should -Invoke Get-ScoutRawInventory -Times 1 -ParameterFilter { -not $SubscriptionIds -and $ManagementGroupId -eq 'mg-1' }
        }
    }
}

Describe 'Policy-state prefetch recognises the real Az command' {
    It 'accepts Get-AzPolicyState as an Az.PolicyInsights function, not only as a compiled cmdlet' {
        # 3.18.2 accepted a cmdlet only. Az.PolicyInsights 2.x ships Get-AzPolicyState as a
        # generated function, so on a real install the prefetch skipped itself every run.
        $source = Get-Content -Raw (Join-Path $script:ModuleRoot 'src/collect/Get-ScoutSubscriptionSecurityPolicySweep.ps1')
        $source | Should -Match "CommandType -eq 'Function' -and \[string\]\`$policyCommand\.ModuleName -eq 'Az\.PolicyInsights'"
    }
}

Describe 'Combined runs collect once' {
    It 'reads the External Identities policy from the inventory copy without calling Graph' {
        & $script:Module {
            Mock Invoke-AZSCGraphRequest { throw 'Graph was called a second time.' }
            $policy = [pscustomobject]@{
                isServiceDefault = $true
                inboundTrust     = [pscustomobject]@{ isMfaAccepted = $false; isCompliantDeviceAccepted = $true; isHybridAzureADJoinedDeviceAccepted = $false }
                b2bCollaborationInbound = [pscustomobject]@{ applications = [pscustomobject]@{ accessType = 'allowed' } }
            }
            $result = Get-ScoutExternalIdentitiesPolicy -TenantID 'tenant-x' -FromInventoryPolicy $policy
            Should -Invoke Invoke-AZSCGraphRequest -Times 0
            $result.Collected | Should -BeTrue
            $result.IsServiceDefault | Should -BeTrue
            $result.InboundTrustCompliantDevice | Should -BeTrue
            $result.B2BCollaborationInboundAccessType | Should -Be 'allowed'
        }
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

    It 'reports the subscriptions and resources the assessment collected, not 0' {
        $work = Join-Path $TestDrive 'assess-counts'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $result = & $script:Module {
            param($Work)
            Mock Test-AZSCPS { 'Linux' }
            Mock Test-AZSCInteractiveHost { $false }
            Mock Connect-AZSCLoginSession { 'tenant-1' }
            Mock Invoke-ScoutAssessmentCore {
                $runPath = Join-Path $Work 'assessment-report'
                New-Item -ItemType Directory -Path $runPath -Force | Out-Null
                '<html></html>' | Set-Content (Join-Path $runPath 'report-react.html')
                @'
{ "subscriptions": [ { "id": "/subscriptions/s1" }, { "id": "/subscriptions/s2" } ],
  "compute": { "vms": [ { "id": "/subscriptions/s1/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1" },
                        { "id": "/subscriptions/s1/resourceGroups/RG/providers/Microsoft.Compute/virtualMachines/VM1" } ] },
  "networking": { "vnets": [ { "id": "/subscriptions/s2/resourceGroups/net/providers/Microsoft.Network/virtualNetworks/v1" } ] } }
'@ | Set-Content (Join-Path $runPath 'collect.json')
                return $runPath
            }
            Invoke-AzureScout -NoWizard -NoProgress -Assessment 'CAF: Azure Landing Zone' -ReportDir $Work -OutputFormat React -TenantID 'tenant-1' -NonInteractiveAuth -PassThru 6>$null
        } $work

        $result = @($result | Where-Object { $_ -and $_.PSObject.Properties['ResourceCount'] })[-1]
        $result.SubscriptionCount | Should -Be 2
        $result.ResourceCount | Should -Be 2
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
