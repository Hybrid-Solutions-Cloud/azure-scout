#Requires -Version 7.0
#Requires -Modules Pester

<#
    Pester tests for src/Write-ScoutProgress.ps1 (AB#405) -- the optional,
    soft-dependency live progress host shared by the collect/assess/report
    pipeline. No live Azure connection is needed.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/Write-ScoutProgress.ps1"
}

Describe 'Write-ScoutProgress -- interactive (Write-Progress) path' {
    It 'does not throw with a percent-complete status call' {
        { Write-ScoutProgress -Activity 'Test' -Status 'step 1' -PercentComplete 10 } | Should -Not -Throw
    }

    It 'does not throw on a -Completed call' {
        { Write-ScoutProgress -Activity 'Test' -Id 1 -Completed } | Should -Not -Throw
    }

    It 'does not throw with an indeterminate (-1, the default) percent' {
        { Write-ScoutProgress -Activity 'Test' -Status 'working' } | Should -Not -Throw
    }

    It 'does not throw with -ParentId set (nested progress)' {
        { Write-ScoutProgress -Activity 'Child' -Status 'nested step' -PercentComplete 50 -Id 2 -ParentId 1 } | Should -Not -Throw
    }
}

Describe 'Write-ScoutProgress -- live Spectre task updates' {
    BeforeEach {
        $script:createdTasks = [System.Collections.Generic.List[object]]::new()
        $script:fakeContext = [pscustomobject]@{}
        $script:fakeContext | Add-Member -MemberType ScriptMethod -Name AddTask -Value {
            param([string] $Description)
            $task = [pscustomobject]@{
                Description     = $Description
                Value           = 0.0
                IsIndeterminate = $false
                Stopped         = $false
            }
            $task | Add-Member -MemberType ScriptMethod -Name StopTask -Value { $this.Stopped = $true }
            $script:createdTasks.Add($task)
            return $task
        }
        $script:ScoutSpectreProgressContext = $script:fakeContext
        $script:ScoutSpectreProgressTasks = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    AfterEach {
        Remove-Variable ScoutSpectreProgressContext -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable ScoutSpectreProgressTasks -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable fakeContext -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable createdTasks -Scope Script -ErrorAction SilentlyContinue
    }

    It 'creates and updates one live task instead of printing a static Spectre line' {
        Write-ScoutProgress -Activity 'Azure Inventory extraction' -Status 'ARM child-resource sweep' `
            -PercentComplete 30 -Id 2
        Write-ScoutProgress -Activity 'Azure Inventory extraction' -Status 'Still collecting' `
            -PercentComplete 31 -Id 2

        $script:createdTasks.Count | Should -Be 1
        $script:createdTasks[0].Value | Should -Be 31
        $script:createdTasks[0].Description | Should -Match '\[bold cyan1\]Azure Inventory extraction\[/\]'
        $script:createdTasks[0].Description | Should -Match '\[white\]Still collecting\[/\]'
    }

    It 'marks the live task complete without losing its readable label' {
        Write-ScoutProgress -Activity 'Azure Inventory extraction' -Status 'Working' -Id 2
        Write-ScoutProgress -Activity 'Azure Inventory extraction' -Status 'Complete' -Id 2 -Completed

        $script:createdTasks[0].Stopped | Should -BeTrue
        $script:createdTasks[0].Value | Should -Be 100
        $script:createdTasks[0].Description | Should -Match '\[white\]Complete\[/\]'
    }
}

Describe 'Invoke-ScoutProgressOperation -- execute-once safety' {
    BeforeEach { $script:operationCount = 0 }
    AfterEach { Remove-Variable operationCount -Scope Script -ErrorAction SilentlyContinue }

    It 'runs directly exactly once when Spectre is unavailable' {
        Mock Test-ScoutSpectreAvailable { return $false }

        $result = Invoke-ScoutProgressOperation -Activity 'Test' -Operation {
            $script:operationCount++
            return 'done'
        }

        $result | Should -Be 'done'
        $script:operationCount | Should -Be 1
    }

    It 'falls back exactly once when the live host fails before work starts' {
        Mock Test-ScoutSpectreAvailable { return $true }
        Mock Import-ScoutSpectreConsole { return $true }
        Mock Start-ScoutSpectreProgressHost { throw 'host startup failed' }

        $result = Invoke-ScoutProgressOperation -Activity 'Test' -Operation {
            $script:operationCount++
            return 'fallback'
        }

        $result | Should -Be 'fallback'
        $script:operationCount | Should -Be 1
    }

    It 'never reruns Azure work after the live host has started it' {
        Mock Test-ScoutSpectreAvailable { return $true }
        Mock Import-ScoutSpectreConsole { return $true }
        Mock Start-ScoutSpectreProgressHost {
            $script:operationCount++
            $exception = [InvalidOperationException]::new('operation failed')
            $exception.Data['ScoutProgressOperationStarted'] = $true
            throw $exception
        }

        { Invoke-ScoutProgressOperation -Activity 'Test' -Operation { $script:operationCount++ } } |
            Should -Throw '*operation failed*'
        $script:operationCount | Should -Be 1
    }
}

Describe 'Start-ScoutSpectreProgressHost -- live rendering contract' {
    BeforeAll { $script:source = Get-Content "$root/src/Write-ScoutProgress.ps1" -Raw }

    It 'uses Spectre auto-refresh with spinner and elapsed-time columns' {
        $script:source | Should -Match '\[Spectre\.Console\.SpinnerColumn\]::new\(\)'
        $script:source | Should -Match '\[Spectre\.Console\.ElapsedTimeColumn\]::new\(\)'
        $script:source | Should -Match 'AutoRefresh\(\$progress, \$true\)'
    }

    It 'uses high-contrast phase text without a colored background' {
        $description = New-ScoutSpectreDescription -Activity 'Azure Inventory' -Status 'ARM child-resource sweep'
        $description | Should -Match '\[bold cyan1\]Azure Inventory\[/\]'
        $description | Should -Match '\[white\]ARM child-resource sweep\[/\]'
        $description | Should -Not -Match ' on '
    }
}

Describe 'Write-ScoutProgress -- CI / headless (log-line) fallback' {
    BeforeEach { $ProgressPreference = 'SilentlyContinue' }
    AfterEach  { $ProgressPreference = 'Continue' }

    It 'does not throw when $ProgressPreference is SilentlyContinue' {
        { Write-ScoutProgress -Activity 'Test' -Status 'step 1' -PercentComplete 25 } | Should -Not -Throw
    }

    It 'emits a single-line, log-friendly status via the Information stream' {
        $info = Write-ScoutProgress -Activity 'ScoutTest' -Status 'doing the thing' -PercentComplete 42 6>&1 |
            Where-Object { $_ -is [System.Management.Automation.InformationRecord] }
        $lines = ($info | ForEach-Object { $_.MessageData }) -join "`n"
        $lines | Should -Match 'ScoutTest'
        $lines | Should -Match '42%'
    }

    It 'does not emit a log line on a -Completed call (avoids a spurious final line)' {
        $info = Write-ScoutProgress -Activity 'ScoutTest' -Id 1 -Completed 6>&1 |
            Where-Object { $_ -is [System.Management.Automation.InformationRecord] }
        @($info).Count | Should -Be 0
    }
}

Describe 'Write-ScoutProgress -- soft dependency' {
    It 'never throws when PwshSpectreConsole is unavailable' {
        { Write-ScoutProgress -Activity 'Test' -Status 'step' -PercentComplete 5 } | Should -Not -Throw
    }
}

Describe 'Write-ScoutProgress -- guarded optional integration with Invoke-Collect (AB#405)' {
    BeforeAll {
        $collectRoot = Split-Path $PSScriptRoot -Parent
        . "$collectRoot/tests/helpers/Search-AzGraph.TestDouble.ps1"
        . "$collectRoot/src/collect/Invoke-Collect.ps1"
    }

    It 'Invoke-Collect calls through to Write-ScoutProgress without error when it is loaded in the session' {
        Mock Search-AzGraph { return @() }
        # -Source TypedQueries: the per-query progress calls this test exercises live in the
        # typed-query loop. The default (single-pass) source shapes those keys locally and so
        # only reports progress for the one query that still goes to ARG (AB#5648).
        { Invoke-Collect -Source TypedQueries -Categories @('Security') -WarningAction SilentlyContinue } | Should -Not -Throw
    }
}
