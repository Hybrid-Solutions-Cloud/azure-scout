#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5629 — the job-wait race that silently dropped a whole category from the report.

    Wait-AZSCJob used to loop only while a job was in state 'Running'. Start-Job is asynchronous, so
    a job created moments earlier is briefly 'NotStarted'; that state satisfied neither the loop
    condition nor the caller's job-selection filter, so the job was never waited on. The caller then
    ran Receive-Job (nothing to receive) followed by Remove-Job (destroying it), and that category's
    cache file was written empty — or not at all. Observed live as Compute.json coming back 5,158
    bytes on one run and 470 on the next against the same tenant and scope.

    These tests pin the contract: Wait-AZSCJob returns only once every named job has reached a
    TERMINAL state, never while one is still pending.

    No Azure connection.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/Modules/Public/PublicFunctions/Jobs/Wait-AZTIJob.ps1"

    $script:PendingStates  = @('NotStarted', 'Running', 'Stopping', 'Suspending', 'Suspended')
    $script:TerminalStates = @('Completed', 'Failed', 'Stopped', 'Blocked')
}

Describe 'Wait-AZSCJob (AB#5629)' {

    AfterEach {
        Get-Job -Name 'WaitTest_*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    }

    It 'does not return until every named job has reached a terminal state' {
        $names = 1..3 | ForEach-Object {
            $n = "WaitTest_$_"
            Start-Job -Name $n -ScriptBlock { Start-Sleep -Milliseconds 900; 'done' } | Out-Null
            $n
        }

        # Called immediately after Start-Job, so at least one job is very likely still NotStarted —
        # precisely the state the old condition ignored.
        Wait-AZSCJob -JobNames $names -JobType 'Test' -LoopTime 1 3>$null 4>$null 6>$null

        $states = @(Get-Job -Name $names | Select-Object -ExpandProperty State | ForEach-Object { [string]$_ })
        $states.Count | Should -Be 3
        foreach ($s in $states) { $script:TerminalStates | Should -Contain $s }
    }

    It 'actually returns the job output afterwards, which is what the empty cache file was missing' {
        Start-Job -Name 'WaitTest_Payload' -ScriptBlock { Start-Sleep -Milliseconds 600; 'payload' } | Out-Null
        Wait-AZSCJob -JobNames @('WaitTest_Payload') -JobType 'Test' -LoopTime 1 3>$null 4>$null 6>$null
        (Receive-Job -Name 'WaitTest_Payload') | Should -Be 'payload'
    }

    It 'returns promptly when the jobs are already finished' {
        Start-Job -Name 'WaitTest_Fast' -ScriptBlock { 'quick' } | Out-Null
        Wait-Job -Name 'WaitTest_Fast' | Out-Null
        Wait-AZSCJob -JobNames @('WaitTest_Fast') -JobType 'Test' -LoopTime 1 3>$null 4>$null 6>$null
        [string](Get-Job -Name 'WaitTest_Fast').State | Should -Be 'Completed'
    }

    It 'treats a failed job as terminal rather than waiting on it forever' {
        Start-Job -Name 'WaitTest_Boom' -ScriptBlock { throw 'boom' } | Out-Null
        Wait-AZSCJob -JobNames @('WaitTest_Boom') -JobType 'Test' -LoopTime 1 3>$null 4>$null 6>$null
        $script:TerminalStates | Should -Contain ([string](Get-Job -Name 'WaitTest_Boom').State)
    }
}

Describe 'BeginInvoke handle completion (AB#5629)' {

    It 'exposes IsCompleted on the handle itself, not under a Runspace property' {
        # The old wait loop read $job.Runspace.IsCompleted. PowerShellAsyncResult has no Runspace
        # property, so that expression was empty and "-contains $false" never held — the loop
        # never waited. This pins the property the fix relies on.
        $ps = [PowerShell]::Create().AddScript({ Start-Sleep -Milliseconds 200; 'x' })
        try {
            $handle = $ps.BeginInvoke()
            $handles = @($handle)

            $handle.PSObject.Properties['Runspace'] | Should -BeNullOrEmpty
            $handles.Runspace | Should -BeNullOrEmpty
            # The old loop condition: always false, so the loop body never ran and nothing waited.
            ($handles.Runspace.IsCompleted -contains $false) | Should -BeFalse

            $handles.IsCompleted | Should -Not -BeNullOrEmpty                    # the fix
            while ($handles.IsCompleted -contains $false) { Start-Sleep -Milliseconds 50 }
            $ps.EndInvoke($handle) | Should -Be 'x'
        }
        finally { $ps.Dispose() }
    }
}
