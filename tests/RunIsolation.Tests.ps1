#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for run isolation, subscription context restore, and the management
    group access probe.

.DESCRIPTION
    Covers AB#331 (non-destructive cache), AB#368 (cross-subscription context switching
    with restore) and AB#351 (post-login management group access probe).
    No live Azure authentication is required — all Az cmdlets are mocked.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:MainPath   = Join-Path -Path $script:ModuleRoot -ChildPath 'src'
    $script:TempDir    = Join-Path -Path $env:TEMP -ChildPath 'AZSC_RunIsolationTests'

    if (Test-Path $script:TempDir) { Remove-Item $script:TempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    . (Join-Path -Path $script:MainPath -ChildPath 'Set-AZTIReportPath.ps1')
    . (Join-Path -Path $script:MainPath -ChildPath 'Clear-AZTICacheFolder.ps1')
    . (Join-Path -Path $script:MainPath -ChildPath 'Invoke-AZTISubscriptionContext.ps1')
    . (Join-Path -Path $script:MainPath -ChildPath 'Test-AZTIManagementGroupAccess.ps1')
}

AfterAll {
    if (Test-Path $script:TempDir) { Remove-Item $script:TempDir -Recurse -Force }
}

Describe 'Set-AZSCReportPath — run isolation (AB#331)' {

    It 'Places each run in its own folder under the base path by default' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir
        $result.BasePath    | Should -Be $script:TempDir
        $result.DefaultPath | Should -Not -Be $script:TempDir
        $result.DefaultPath | Should -BeLike "$script:TempDir*"
        $result.RunFolder   | Should -Not -BeNullOrEmpty
    }

    It 'Names the generated run folder with a sortable timestamp' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir
        $result.RunFolder | Should -Match '^\d{4}-\d{2}-\d{2}_\d{6}'
    }

    It 'Nests DiagramCache and ReportCache inside the run folder, not the base path' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir
        $result.DiagramCache | Should -Be (Join-Path -Path $result.DefaultPath -ChildPath 'DiagramCache')
        $result.ReportCache  | Should -Be (Join-Path -Path $result.DefaultPath -ChildPath 'ReportCache')
    }

    It 'Does not reuse a previous run folder — two runs never collide' {
        # A same-second second call would produce an identical timestamp, so drive the
        # two runs through -RunName to assert the isolation contract deterministically.
        $first  = Set-AZSCReportPath -ReportDir $script:TempDir -RunName 'tenantA'
        $second = Set-AZSCReportPath -ReportDir $script:TempDir -RunName 'tenantB'
        $first.DefaultPath | Should -Not -Be $second.DefaultPath
    }

    It 'Uses the supplied RunName as the folder name' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir -RunName 'Production-TenantA'
        $result.RunFolder   | Should -Be 'Production-TenantA'
        $result.DefaultPath | Should -Be (Join-Path -Path $script:TempDir -ChildPath 'Production-TenantA')
    }

    It 'Replaces invalid path characters in a RunName' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir -RunName 'bad:name*here?'
        $result.RunFolder | Should -Not -Match '[:*?]'
        $result.RunFolder | Should -Be 'bad-name-here-'
    }

    It 'Sanitizes rather than discards a RunName made only of invalid characters' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir -RunName '???'
        $result.RunFolder | Should -Be '---'
    }

    It 'Falls back to a timestamp when RunName is whitespace only' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir -RunName '   '
        $result.RunFolder | Should -Match '^\d{4}-\d{2}-\d{2}_\d{6}$'
    }

    It 'Appends a truncated scope identifier to the generated folder name' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir -ScopeId '12345678-aaaa-bbbb-cccc-dddddddddddd'
        $result.RunFolder | Should -Match '^\d{4}-\d{2}-\d{2}_\d{6}_12345678$'
    }

    It 'Writes into the base path directly when -Force is supplied' {
        $result = Set-AZSCReportPath -ReportDir $script:TempDir -Force
        $result.DefaultPath  | Should -Be $script:TempDir
        $result.RunFolder    | Should -BeNullOrEmpty
        $result.ReportCache  | Should -Be (Join-Path -Path $script:TempDir -ChildPath 'ReportCache')
    }

    It 'Still resolves a default base path when no ReportDir is given' {
        $result = Set-AZSCReportPath -ReportDir $null -Force
        $result.DefaultPath | Should -Not -BeNullOrEmpty
        $result.DefaultPath | Should -BeLike '*AzureScout*'
    }
}

Describe 'Clear-AZSCCacheFolder — prune mode (AB#331)' {

    BeforeEach {
        $script:PruneBase = Join-Path -Path $script:TempDir -ChildPath 'prune'
        if (Test-Path $script:PruneBase) { Remove-Item $script:PruneBase -Recurse -Force }
        New-Item -ItemType Directory -Path $script:PruneBase -Force | Out-Null

        $script:OldRun = Join-Path -Path $script:PruneBase -ChildPath '2020-01-01_000000'
        $script:NewRun = Join-Path -Path $script:PruneBase -ChildPath '2026-07-25_120000'
        New-Item -ItemType Directory -Path $script:OldRun -Force | Out-Null
        New-Item -ItemType Directory -Path $script:NewRun -Force | Out-Null
        (Get-Item $script:OldRun).LastWriteTime = (Get-Date).AddDays(-90)
    }

    It 'Removes run folders older than the cutoff' {
        Clear-AZSCCacheFolder -OlderThan 30 -BasePath $script:PruneBase
        $script:OldRun | Should -Not -Exist
    }

    It 'Keeps run folders newer than the cutoff' {
        Clear-AZSCCacheFolder -OlderThan 30 -BasePath $script:PruneBase
        $script:NewRun | Should -Exist
    }

    It 'Does not throw when the base path does not exist' {
        { Clear-AZSCCacheFolder -OlderThan 30 -BasePath (Join-Path -Path $script:TempDir -ChildPath 'nope') } | Should -Not -Throw
    }

    It 'Still clears a single cache folder in the original mode' {
        $cache = Join-Path -Path $script:TempDir -ChildPath 'legacy_cache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        'x' | Out-File (Join-Path -Path $cache -ChildPath 'a.json')
        'y' | Out-File (Join-Path -Path $cache -ChildPath 'b.json')

        Clear-AZSCCacheFolder -ReportCache $cache

        @(Get-ChildItem -Path $cache -File -Recurse).Count | Should -Be 0
    }

    It 'Does not throw when the cache folder does not exist' {
        { Clear-AZSCCacheFolder -ReportCache (Join-Path -Path $script:TempDir -ChildPath 'missing_cache') } | Should -Not -Throw
    }
}

Describe 'Invoke-AZSCInSubscriptionContext — context restore (AB#368)' {

    BeforeAll {
        $script:Subs = @(
            [PSCustomObject]@{ Id = 'sub-1'; Name = 'One'; TenantId = 'tenant-a' }
            [PSCustomObject]@{ Id = 'sub-2'; Name = 'Two'; TenantId = 'tenant-a' }
            [PSCustomObject]@{ Id = 'sub-3'; Name = 'Three'; TenantId = 'tenant-a' }
        )
    }

    It 'Switches context once per subscription and restores once at the end' {
        Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'original-sub' }; Tenant = [PSCustomObject]@{ Id = 'tenant-a' } } }
        Mock Set-AzContext { }

        Invoke-AZSCInSubscriptionContext -Subscription $script:Subs -Process { param($s) $null = $s }

        Should -Invoke Set-AzContext -Times 3 -Exactly -ParameterFilter { $Subscription -in 'sub-1','sub-2','sub-3' -and $Tenant -eq 'tenant-a' }
        Should -Invoke Set-AzContext -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'original-sub' -and $Tenant -eq 'tenant-a' }
    }

    It 'Runs the process block once per subscription' {
        Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'original-sub' }; Tenant = [PSCustomObject]@{ Id = 'tenant-a' } } }
        Mock Set-AzContext { }

        $seen = [System.Collections.Generic.List[string]]::new()
        Invoke-AZSCInSubscriptionContext -Subscription $script:Subs -Process { param($s) $seen.Add($s.Id) }

        $seen.Count | Should -Be 3
        $seen -join ',' | Should -Be 'sub-1,sub-2,sub-3'
    }

    It 'Restores the original context when the loop throws part way through' {
        Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'original-sub' }; Tenant = [PSCustomObject]@{ Id = 'tenant-a' } } }
        Mock Set-AzContext { }

        {
            Invoke-AZSCInSubscriptionContext -Subscription $script:Subs -Process {
                param($s)
                if ($s.Id -eq 'sub-2') { throw 'boom' }
            }
        } | Should -Throw

        Should -Invoke Set-AzContext -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'original-sub' -and $Tenant -eq 'tenant-a' }
    }

    It 'Accepts plain subscription ID strings' {
        Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'original-sub' }; Tenant = [PSCustomObject]@{ Id = 'tenant-a' } } }
        Mock Set-AzContext { }

        Invoke-AZSCInSubscriptionContext -Subscription @('sub-a', 'sub-b') -Process { param($s) $null = $s }

        Should -Invoke Set-AzContext -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'sub-a' -and $Tenant -eq 'tenant-a' }
        Should -Invoke Set-AzContext -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'sub-b' -and $Tenant -eq 'tenant-a' }
    }

    It 'Does not attempt a restore when there was no original context' {
        Mock Get-AzContext { $null }
        Mock Set-AzContext { }

        Invoke-AZSCInSubscriptionContext -Subscription @('sub-a') -Process { param($s) $null = $s }

        Should -Invoke Set-AzContext -Times 1 -Exactly
    }

    It 'Skips entries with no resolvable subscription Id' {
        Mock Get-AzContext { $null }
        Mock Set-AzContext { }

        Invoke-AZSCInSubscriptionContext -Subscription @([PSCustomObject]@{ Name = 'no-id' }) -Process { param($s) $null = $s }

        Should -Invoke Set-AzContext -Times 0 -Exactly
    }
}

Describe 'Restore-AZSCContext (AB#368)' {

    It 'Is a no-op for a null context' {
        Mock Set-AzContext { }
        { Restore-AZSCContext -Context $null } | Should -Not -Throw
        Should -Invoke Set-AzContext -Times 0 -Exactly
    }

    It 'Is a no-op for a context with no subscription' {
        Mock Set-AzContext { }
        Restore-AZSCContext -Context ([PSCustomObject]@{ Subscription = $null })
        Should -Invoke Set-AzContext -Times 0 -Exactly
    }

    It 'Restores a valid context' {
        Mock Set-AzContext { }
        Restore-AZSCContext -Context ([PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'restore-me' }; Tenant = [PSCustomObject]@{ Id = 'tenant-a' } })
        Should -Invoke Set-AzContext -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'restore-me' -and $Tenant -eq 'tenant-a' }
    }
}

Describe 'Test-AZSCManagementGroupAccess — post-login probe (AB#351)' {

    It 'Reports the management group count when access succeeds' {
        Mock Get-AzManagementGroup {
            @(
                [PSCustomObject]@{ Name = 'mg-root' }
                [PSCustomObject]@{ Name = 'mg-prod' }
            )
        }

        $result = Test-AZSCManagementGroupAccess

        $result.HasAccess | Should -BeTrue
        $result.Count     | Should -Be 2
        $result.Message   | Should -Match '2'
    }

    It 'Emits a cyan Management Group Reader tip on AuthorizationFailed' {
        Mock Get-AzManagementGroup { throw "AuthorizationFailed: the client does not have authorization" }
        Mock Write-Host { }

        $null = Test-AZSCManagementGroupAccess

        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $ForegroundColor -eq 'Cyan' -and $Object -match "Management Group Reader"
        }
    }

    It 'Does not throw when the probe fails' {
        Mock Get-AzManagementGroup { throw "AuthorizationFailed" }
        Mock Write-Host { }

        { Test-AZSCManagementGroupAccess } | Should -Not -Throw
    }

    It 'Returns a zero count and no access when the probe fails' {
        Mock Get-AzManagementGroup { throw "AuthorizationFailed" }
        Mock Write-Host { }

        $result = Test-AZSCManagementGroupAccess

        $result.HasAccess | Should -BeFalse
        $result.Count     | Should -Be 0
    }

    It 'Stays quiet for a non-authorization failure — no role tip to give' {
        Mock Get-AzManagementGroup { throw "The request was throttled" }
        Mock Write-Host { }

        $result = Test-AZSCManagementGroupAccess

        $result.HasAccess | Should -BeFalse
        Should -Invoke Write-Host -Times 0 -Exactly
    }
}
