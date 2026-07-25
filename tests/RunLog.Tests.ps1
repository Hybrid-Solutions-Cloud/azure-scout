<#
    AB#5634 / AB#5635 — every run writes a detailed log into its own run folder.

    The contract these tests defend: logging is best-effort and must NEVER be the reason a
    run fails, and a failed run must still leave the full error record (message, script,
    line, script stack trace) behind on disk.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'Modules/Private/Main/Write-AZTIRunLog.ps1')
}

Describe 'Start-AZSCRunLog' {

    BeforeEach {
        $script:LogDir = Join-Path ([System.IO.Path]::GetTempPath()) ("azsc-log-" + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        $null = Stop-AZSCRunLog -Quiet -ErrorAction SilentlyContinue
        if (Test-Path $script:LogDir) { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates scout-run.log inside the run folder' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        Test-Path (Join-Path $script:LogDir 'scout-run.log') | Should -BeTrue
    }

    It 'creates the run folder when it does not already exist' {
        Test-Path $script:LogDir | Should -BeFalse
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        Test-Path $script:LogDir | Should -BeTrue
    }

    It 'writes the supplied metadata into the header' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript -Metadata @{
            Tenant = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            Scope  = 'All'
        }
        $Text = Get-Content -Raw (Join-Path $script:LogDir 'scout-run.log')
        $Text | Should -Match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $Text | Should -Match 'Scope'
    }

    It 'joins array metadata rather than printing a type name' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript -Metadata @{ Category = @('Compute', 'Storage') }
        $Text = Get-Content -Raw (Join-Path $script:LogDir 'scout-run.log')
        $Text | Should -Match 'Compute, Storage'
        $Text | Should -Not -Match 'System\.Object\[\]'
    }

    It 'does not throw when the path cannot be written' {
        # A run folder on a drive that does not exist must cost a warning, not the run.
        { Start-AZSCRunLog -DefaultPath 'Q:\definitely\not\here' -NoTranscript -WarningAction SilentlyContinue } |
            Should -Not -Throw
    }
}

Describe 'Write-AZSCLog' {

    BeforeEach {
        $script:LogDir = Join-Path ([System.IO.Path]::GetTempPath()) ("azsc-log-" + [guid]::NewGuid().ToString('N'))
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $script:LogFile = Join-Path $script:LogDir 'scout-run.log'
    }

    AfterEach {
        $null = Stop-AZSCRunLog -Quiet -ErrorAction SilentlyContinue
        if (Test-Path $script:LogDir) { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'appends a timestamped, levelled line' {
        Write-AZSCLog -Message 'hello there' -Level 'INFO'
        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\] \[INFO \] hello there'
    }

    It 'records phases with their elapsed time and detail rows' {
        Write-AZSCLogPhase -Name 'Extraction finished' -Elapsed '00:00:04:12:001' -Detail @{ Resources = 227 }
        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match 'Extraction finished \(elapsed 00:00:04:12:001\)'
        $Text | Should -Match 'Resources\s+: 227'
    }

    It 'renders a $null detail value as <none> rather than a blank' {
        Write-AZSCLogPhase -Name 'Phase' -Detail @{ Quotas = $null }
        (Get-Content -Raw $script:LogFile) | Should -Match '<none>'
    }

    It 'writes nothing and does not throw once the log is stopped' {
        $null = Stop-AZSCRunLog -Quiet
        { Write-AZSCLog -Message 'after the end' } | Should -Not -Throw
        (Get-Content -Raw $script:LogFile) | Should -Not -Match 'after the end'
    }
}

Describe 'Write-AZSCLogError' {

    BeforeEach {
        $script:LogDir = Join-Path ([System.IO.Path]::GetTempPath()) ("azsc-log-" + [guid]::NewGuid().ToString('N'))
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $script:LogFile = Join-Path $script:LogDir 'scout-run.log'

        # A real ErrorRecord with a real stack trace, produced the way the crash was.
        try {
            & {
                Set-StrictMode -Version Latest
                $Collection = @(@{ Key = @() }, @{ Key = @() })
                $null = $Collection.Key
            }
        }
        catch { $script:Caught = $_ }
    }

    AfterEach {
        $null = Stop-AZSCRunLog -Quiet -ErrorAction SilentlyContinue
        if (Test-Path $script:LogDir) { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'captured a real error record to test against' {
        $script:Caught | Should -Not -BeNullOrEmpty
    }

    It 'records the message, the exception type and the stack trace' {
        Write-AZSCLogError -ErrorRecord $script:Caught
        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match 'RUN FAILED'
        $Text | Should -Match 'cannot be found on this object'
        $Text | Should -Match 'ScriptStackTrace'
    }

    It 'records the failing script and line number' {
        Write-AZSCLogError -ErrorRecord $script:Caught
        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match 'Script\s+:'
        $Text | Should -Match 'Line\s+:'
    }

    It 'does not throw when no log has been started' {
        $null = Stop-AZSCRunLog -Quiet
        { Write-AZSCLogError -ErrorRecord $script:Caught } | Should -Not -Throw
    }
}

Describe 'Stop-AZSCRunLog' {

    BeforeEach {
        $script:LogDir = Join-Path ([System.IO.Path]::GetTempPath()) ("azsc-log-" + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        if (Test-Path $script:LogDir) { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns the log path so the caller can surface it' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $Path = Stop-AZSCRunLog -Quiet
        $Path | Should -Be (Join-Path $script:LogDir 'scout-run.log')
    }

    It 'records the terminal status in the log' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $null = Stop-AZSCRunLog -Status 'FAILED' -Quiet
        (Get-Content -Raw (Join-Path $script:LogDir 'scout-run.log')) | Should -Match 'Run FAILED after'
    }

    It 'is safe to call when no log was ever started' {
        { Stop-AZSCRunLog -Quiet } | Should -Not -Throw
    }
}

Describe 'Invoke-AzureScout wiring' {

    BeforeAll {
        $script:EntryPoint = Get-Content -Raw -Path (Join-Path $script:RepoRoot 'Modules/Public/PublicFunctions/Invoke-AzureScout.ps1')
    }

    It 'starts the run log once the run folder exists' {
        $script:EntryPoint | Should -Match 'Start-AZSCRunLog -DefaultPath \$DefaultPath'
    }

    It 'installs a trap so a failure anywhere in the run is logged with its stack trace' {
        $script:EntryPoint | Should -Match 'Write-AZSCLogError -ErrorRecord \$_'
        $script:EntryPoint | Should -Match "Stop-AZSCRunLog -Status 'FAILED'"
    }

    It 'rethrows with break, never a bare throw, so the original error survives' {
        # A bare `throw` inside a trap raises a NEW "ScriptHalted" error and discards the
        # original message, script, line and stack trace - the very detail the trap exists
        # to preserve. `break` propagates the original ErrorRecord untouched.
        $script:EntryPoint | Should -Match '(?s)trap \{.*?Write-AZSCLogError.*?break\s*\}'
    }

    It 'does not swallow the failure' {
        # Logging and continuing would turn a failed run into a silent one, which is worse
        # than the crash the log was added to explain.
        $script:EntryPoint | Should -Not -Match '(?s)trap \{.*?Write-AZSCLogError.*?continue\s*\}'
    }

    It 'logs each phase boundary' {
        foreach ($Phase in 'Extraction finished', 'Processing finished', 'Reporting finished', 'Run complete') {
            $script:EntryPoint | Should -Match ([regex]::Escape("-Name '$Phase'"))
        }
    }

    It 'closes the log on the success path too' {
        $script:EntryPoint | Should -Match "Stop-AZSCRunLog -Status 'COMPLETED'"
    }
}
