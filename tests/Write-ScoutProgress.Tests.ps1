#Requires -Version 7.0
#Requires -Modules Pester

<#
    Pester tests for src/Write-ScoutProgress.ps1 (AB#405) -- AzureScout's built-in live
    progress host shared by the collect/assess/report pipeline. No live Azure connection
    or third-party renderer module is needed.
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

Describe 'Invoke-ScoutProgressOperation -- execute-once safety' {
    BeforeEach { $script:operationCount = 0 }
    AfterEach { Remove-Variable operationCount -Scope Script -ErrorAction SilentlyContinue }

    It 'runs directly exactly once when a live console is unavailable' {
        Mock Test-ScoutNativeLiveHost { return $false }

        $result = Invoke-ScoutProgressOperation -Activity 'Test' -Operation {
            $script:operationCount++
            return 'done'
        }

        $result | Should -Be 'done'
        $script:operationCount | Should -Be 1
    }

    It 'falls back exactly once when the live host fails before work starts' {
        Mock Test-ScoutNativeLiveHost { return $true }
        Mock Initialize-ScoutNativeProgressRenderer { return $true }
        Mock Start-ScoutNativeProgressHost { throw 'host startup failed' }

        $result = Invoke-ScoutProgressOperation -Activity 'Test' -Operation {
            $script:operationCount++
            return 'fallback'
        }

        $result | Should -Be 'fallback'
        $script:operationCount | Should -Be 1
    }

    It 'never reruns Azure work after the live host has started it' {
        Mock Test-ScoutNativeLiveHost { return $true }
        Mock Initialize-ScoutNativeProgressRenderer { return $true }
        Mock Start-ScoutNativeProgressHost {
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

Describe 'Start-ScoutNativeProgressHost -- self-contained live rendering contract' {
    BeforeAll { $script:source = Get-Content "$root/src/Write-ScoutProgress.ps1" -Raw }

    It 'uses a background timer and stopwatch so elapsed time moves during blocked calls' {
        $script:source | Should -Match 'new Timer\(RenderTick'
        $script:source | Should -Match 'Stopwatch\.StartNew\(\)'
        $script:source | Should -Match 'TimeSpan\.FromMilliseconds\(125\)'
    }

    It 'has no PwshSpectreConsole or Spectre.Console dependency' {
        $script:source | Should -Not -Match 'PwshSpectreConsole'
        $script:source | Should -Not -Match 'Spectre\.Console'
    }

    It 'uses bright foreground colours without ANSI background colours' {
        $script:source | Should -Match 'BrightCyan = "\\u001b\[96;1m"'
        $script:source | Should -Match 'BrightGreen = "\\u001b\[92;1m"'
        $script:source | Should -Match 'BrightYellow = "\\u001b\[93;1m"'
        $script:source | Should -Not -Match '\\u001b\[4[0-9]'
    }

    It 'renders an unmistakable bordered multi-phase ledger instead of a bare progress line' {
        $script:source | Should -Match 'Azure Scout — live progress'
        $script:source | Should -Match 'PanelLine'
        $script:source | Should -Match 'FinishLiveRow'
        $script:source | Should -Match 'phase changed'
    }

    It 'compiles and runs the native renderer without an installed third-party module' {
        Initialize-ScoutNativeProgressRenderer | Should -BeTrue
        ('AzureScout.NativeProgressRenderer' -as [type]) | Should -Not -BeNullOrEmpty

        $result = Start-ScoutNativeProgressHost -Activity 'Test' -Status 'Working' `
            -PercentComplete 5 -Operation {
                Write-ScoutProgress -Activity 'Child phase' -Status 'Blocked operation' `
                    -PercentComplete 35 -Id 2 -ParentId 1
                Start-Sleep -Milliseconds 450
                Write-ScoutProgress -Activity 'Child phase' -Status 'Complete' `
                    -PercentComplete 100 -Id 2 -ParentId 1 -Completed
                return 'done'
            }
        $result | Should -Be 'done'
        [AzureScout.NativeProgressRenderer]::RenderCount | Should -BeGreaterThan 1
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

Describe 'Write-ScoutProgress -- isolated fallback' {
    It 'never throws when the helper is tested without the manifest dependency loaded' {
        { Write-ScoutProgress -Activity 'Test' -Status 'step' -PercentComplete 5 } | Should -Not -Throw
    }
}

Describe 'Invoke-AzureScout -- production live-host boundaries' {
    BeforeAll {
        $script:invokeSource = Get-Content "$root/src/Invoke-AzureScout.ps1" -Raw
    }

    It 'starts the live host for preflight instead of waiting until extraction' {
        $script:invokeSource | Should -Match "Invoke-ScoutProgressOperation -Activity 'Azure Scout'"
        $script:invokeSource | Should -Match "-Status 'Validating tenant permissions'"
    }

    It 'keeps every long top-level phase behind a live host' {
        foreach ($status in @(
            'Starting extraction',
            'Building diagrams and supplemental datasets',
            'Running collectors',
            'Scoring and rendering selected assessments'
        )) {
            $script:invokeSource | Should -Match ([regex]::Escape("-Status '$status'"))
        }
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
