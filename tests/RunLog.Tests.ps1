<#
    AB#5634 / AB#5635 — every run writes a detailed log into its own run folder.

    The contract these tests defend: logging is best-effort and must NEVER be the reason a
    run fails, and a failed run must still leave the full error record (message, script,
    line, script stack trace) behind on disk.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/Write-AZTIRunLog.ps1')
}

Describe 'Start-AZSCRunLog' {

    BeforeEach {
        $script:LogDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("azsc-log-" + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        $null = Stop-AZSCRunLog -Quiet -ErrorAction SilentlyContinue
        if (Test-Path $script:LogDir) { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates scout-run.log inside the run folder' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        Test-Path (Join-Path -Path $script:LogDir -ChildPath 'scout-run.log') | Should -BeTrue
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
        $Text = Get-Content -Raw (Join-Path -Path $script:LogDir -ChildPath 'scout-run.log')
        $Text | Should -Match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $Text | Should -Match 'Scope'
    }

    It 'joins array metadata rather than printing a type name' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript -Metadata @{ Category = @('Compute', 'Storage') }
        $Text = Get-Content -Raw (Join-Path -Path $script:LogDir -ChildPath 'scout-run.log')
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
        $script:LogDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("azsc-log-" + [guid]::NewGuid().ToString('N'))
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $script:LogFile = Join-Path -Path $script:LogDir -ChildPath 'scout-run.log'
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

    # AB#5649 — seven inventory collectors (Monitor/SubscriptionDiagnosticSettings and the four
    # Security/Defender* ones, plus two in Identity) already call this function with -Color and
    # with -Level Verbose. Neither was accepted, so every one of them threw
    # "A parameter cannot be found that matches parameter name 'Color'" the moment it ran. The
    # old pipeline executed collectors inside a runspace whose errors surfaced detached at
    # EndInvoke time, so those collectors were dead in shipped releases with nothing to say so.
    # These two tests keep the signature honest.
    It 'accepts -Level Verbose, which the collector call sites use' {
        { Write-AZSCLog -Message 'verbose line' -Level Verbose } | Should -Not -Throw
        (Get-Content -Raw $script:LogFile) | Should -Match '\[VERBO\w*\s*\] verbose line'
    }

    It 'keeps DEBUG and VERBOSE file-only by default' {
        $DebugRecords = @(Write-AZSCLog -Message 'default debug detail' -Level Debug -Debug:$false 5>&1)
        $VerboseRecords = @(Write-AZSCLog -Message 'default verbose detail' -Level Verbose -Verbose:$false 4>&1)

        $DebugRecords | Should -BeNullOrEmpty
        $VerboseRecords | Should -BeNullOrEmpty

        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match '\[DEBUG\s*\] default debug detail'
        $Text | Should -Match '\[VERBO\w*\s*\] default verbose detail'
    }

    It 'surfaces DEBUG and VERBOSE detail only through their requested streams' {
        $DebugRecords = @(Write-AZSCLog -Message 'requested debug detail' -Level Debug -Debug 5>&1)
        $VerboseRecords = @(Write-AZSCLog -Message 'requested verbose detail' -Level Verbose -Verbose 4>&1)

        ($DebugRecords | ForEach-Object Message) | Should -Contain 'requested debug detail'
        ($VerboseRecords | ForEach-Object Message) | Should -Contain 'requested verbose detail'
    }

    It 'does not mutate the caller debug or verbose preferences' {
        $BeforeDebug = $DebugPreference
        $BeforeVerbose = $VerbosePreference

        Write-AZSCLog -Message 'preference-safe debug' -Level Debug -Debug:$false
        Write-AZSCLog -Message 'preference-safe verbose' -Level Verbose -Verbose:$false

        $DebugPreference | Should -Be $BeforeDebug
        $VerbosePreference | Should -Be $BeforeVerbose
    }

    It 'still writes the file when a caller has a terminating detail-stream preference' {
        {
            & {
                $DebugPreference = 'Stop'
                Write-AZSCLog -Message 'debug preference stop' -Level Debug
            }
            & {
                $VerbosePreference = 'Stop'
                Write-AZSCLog -Message 'verbose preference stop' -Level Verbose
            }
        } | Should -Not -Throw

        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match 'debug preference stop'
        $Text | Should -Match 'verbose preference stop'
    }

    It 'accepts -Color, which the collector call sites use' {
        { Write-AZSCLog -Message 'coloured line' -Color 'Cyan' } | Should -Not -Throw
        (Get-Content -Raw $script:LogFile) | Should -Match 'coloured line'
    }

    It 'accepts report exceptions and records their type without throwing' {
        $CaughtException = $null
        try { throw [System.InvalidOperationException]::new('renderer fixture failed') }
        catch { $CaughtException = $_.Exception }

        { Write-AZSCLog -Message 'JSON report generation failed' -Level Error -Exception $CaughtException } |
            Should -Not -Throw

        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match 'JSON report generation failed'
        $Text | Should -Match 'Exception type: System\.InvalidOperationException'
    }

    It 'records phases with their elapsed time and detail rows' {
        Write-AZSCLogPhase -Name 'Extraction finished' -Elapsed '00:00:04:12:001' -Detail @{ Resources = 227 }
        $Text = Get-Content -Raw $script:LogFile
        $Text | Should -Match 'Extraction finished \(elapsed 00:00:04:12:001\)'
        $Text | Should -Match 'Resources\s+: 227'
    }

    It 'renders a $null detail value with the literal none marker rather than a blank' {
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
        $script:LogDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("azsc-log-" + [guid]::NewGuid().ToString('N'))
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $script:LogFile = Join-Path -Path $script:LogDir -ChildPath 'scout-run.log'

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
        $script:LogDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("azsc-log-" + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        if (Test-Path $script:LogDir) { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns the log path so the caller can surface it' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $Path = Stop-AZSCRunLog -Quiet
        $Path | Should -Be (Join-Path -Path $script:LogDir -ChildPath 'scout-run.log')
    }

    It 'records the terminal status in the log' {
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $null = Stop-AZSCRunLog -Status 'FAILED' -Quiet
        (Get-Content -Raw (Join-Path -Path $script:LogDir -ChildPath 'scout-run.log')) | Should -Match 'Scan/log execution FAILED after'
    }

    It 'is safe to call when no log was ever started' {
        { Stop-AZSCRunLog -Quiet } | Should -Not -Throw
    }
}

Describe 'Detailed assessment logging' {

    BeforeAll {
        . (Join-Path -Path $script:RepoRoot -ChildPath 'src/assess/engine/Resolve-JsonPath.ps1')
        . (Join-Path -Path $script:RepoRoot -ChildPath 'src/assess/engine/Resolve-RuleJoin.ps1')
        . (Join-Path -Path $script:RepoRoot -ChildPath 'src/assess/engine/Invoke-Rule.ps1')
        . (Join-Path -Path $script:RepoRoot -ChildPath 'src/assess/Invoke-Assessment.ps1')
    }

    BeforeEach {
        $script:LogDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("azsc-log-" + [guid]::NewGuid().ToString('N'))
        Start-AZSCRunLog -DefaultPath $script:LogDir -NoTranscript
        $script:LogFile = Join-Path -Path $script:LogDir -ChildPath 'scout-run.log'
    }

    AfterEach {
        $null = Stop-AZSCRunLog -Quiet -ErrorAction SilentlyContinue
        if (Test-Path $script:LogDir) { Remove-Item $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'durably records each assessment rule status, evidence count, and elapsed time' {
        $RuleSet = @([pscustomobject]@{
            Framework = 'CAF'
            Area = 'LoggingTest'
            Rules = @([pscustomobject]@{
                id = 'LOG-01'
                title = 'Logging contract fixture'
                severity = 'low'
                manual = $false
                query = '$.items[*]'
                assert = [pscustomobject]@{ type = 'countEquals'; value = 1 }
                remediation = 'None'
            })
        })

        $Findings = @(Invoke-Assessment -Collect ([pscustomobject]@{ items = @([pscustomobject]@{ name = 'one' }) }) `
            -RuleSet $RuleSet -Assessment 'Logging test')

        $Findings.Count | Should -Be 1
        $Findings[0].Status | Should -Be 'Pass'
        (Get-Content -Raw $script:LogFile) | Should -Match (
            '\[DEBUG\s*\] Assessment rule LOG-01: status=Pass; evidence=1; elapsed=\d{2}:\d{2}:\d{2}:\d{2}\.\d{3}'
        )
    }
}

Describe 'Invoke-AzureScout wiring' {

    BeforeAll {
        $script:EntryPoint = Get-Content -Raw -Path (Join-Path -Path $script:RepoRoot -ChildPath 'src/Invoke-AzureScout.ps1')
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

    It 'logs the long-running orchestration subphases without resource identifiers or payloads' {
        $RawInventory = Get-Content -Raw -Path (Join-Path -Path $script:RepoRoot -ChildPath 'src/collect/Get-ScoutRawInventory.ps1')
        $AssessmentCore = Get-Content -Raw -Path (Join-Path -Path $script:RepoRoot -ChildPath 'src/Invoke-ScoutAssessmentCore.ps1')

        foreach ($Subphase in @(
            'ARG query sweep',
            'ARM child resource sweep',
            'subscription security and policy sweep',
            'operational enrichment',
            'ARM REST API sweep',
            'tenant-wide resource sweep',
            'governance dataset sweep'
        )) {
            $RawInventory | Should -Match ([regex]::Escape("-Name '$Subphase'"))
            $RawInventory | Should -Match ([regex]::Escape("Write-ScoutRawInventoryStart -Name '$Subphase'"))
        }

        $script:EntryPoint | Should -Match 'Raw inventory dump finished: status='
        $script:EntryPoint | Should -Match 'Deferred assessment started from the in-memory inventory'
        $AssessmentCore | Should -Match 'Assessment collect finished: source='
        $AssessmentCore | Should -Match 'Assessment rules finished: assessment='
        $AssessmentCore | Should -Match 'Assessment renderer finished: renderer='
    }

    It 'does not change the global debug or verbose preferences to enable file detail' {
        $ProductionFiles = @(
            'src/Write-AZTIRunLog.ps1',
            'src/pipeline/Invoke-ScoutCollector.ps1',
            'src/pipeline/Invoke-ScoutProcessing.ps1',
            'src/collect/Get-ScoutRawInventory.ps1',
            'src/Invoke-AzureScout.ps1',
            'src/Invoke-ScoutAssessmentCore.ps1',
            'src/assess/Invoke-Assessment.ps1'
        )

        foreach ($RelativePath in $ProductionFiles) {
            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path -Path $script:RepoRoot -ChildPath $RelativePath),
                [ref]$Tokens,
                [ref]$Errors
            )
            $Errors | Should -BeNullOrEmpty -Because "$RelativePath must parse before its preference contract can be inspected"
            $Assignments = @($Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $Node.Left.Extent.Text -match '^\$(Debug|Verbose)Preference$'
            }, $true))
            $Assignments | Should -BeNullOrEmpty -Because "$RelativePath must not force console detail globally"
        }
    }

    It 'closes the log on the success path too' {
        $script:EntryPoint | Should -Match "Stop-AZSCRunLog -Status 'COMPLETED'"
    }

    It 'initializes durable logging and the failure trap before permission preflight' {
        $startIndex = $script:EntryPoint.IndexOf('Start-AZSCRunLog -DefaultPath $DefaultPath')
        $trapIndex = $script:EntryPoint.IndexOf('trap {', $startIndex)
        $preflightIndex = $script:EntryPoint.IndexOf('$permResult = Test-AZSCPermissions')
        $startIndex | Should -BeGreaterThan -1
        $trapIndex | Should -BeGreaterThan $startIndex
        $preflightIndex | Should -BeGreaterThan $trapIndex
    }

    It 'fails closed an active unfinished log from finally without double-closing normal paths' {
        $script:EntryPoint | Should -Match '(?s)finally\s*\{.*Get-AZSCRunLogPath.*Run ended without reaching the normal completion or failure handler.*Stop-AZSCRunLog -Status ''FAILED'' -Quiet'
        $script:EntryPoint | Should -Match 'if \(\$runLogStarted -and \(Get-AZSCRunLogPath\)\)'
    }

    It 'uses independent nested progress records and reserves Completed for actual terminal points' {
        $raw = Get-Content -Raw -Path (Join-Path $script:RepoRoot 'src/collect/Get-ScoutRawInventory.ps1')
        $operational = Get-Content -Raw -Path (Join-Path $script:RepoRoot 'src/collect/Get-ScoutOperationalCollectorEnrichment.ps1')
        $raw | Should -Match "Write-ScoutProgress -Id 2 -ParentId 1 -Activity 'Azure Inventory extraction'"
        $raw | Should -Match "Write-Progress -Id 2 -ParentId 1 -Activity 'Azure Inventory extraction'"
        $raw | Should -Match "Status 'Extraction subphases complete' -Completed"
        # The live helper and native fallback each declare the same terminal point, but the
        # guarded if/else executes exactly one renderer at runtime.
        ([regex]::Matches($raw, "Status 'Extraction subphases complete' -Completed")).Count | Should -Be 2
        ([regex]::Matches($raw, '-Completed')).Count | Should -Be 2

        $timingStart = $raw.IndexOf('function Write-ScoutRawInventoryTiming')
        $startStart = $raw.IndexOf('function Write-ScoutRawInventoryStart')
        $startEnd = $raw.IndexOf('$tagProjection', $startStart)
        $timingSection = $raw.Substring($timingStart, $startStart - $timingStart)
        $startSection = $raw.Substring($startStart, $startEnd - $startStart)
        $lastPercent = -1
        foreach ($phase in @(
                'ARG query sweep', 'ARM child resource sweep',
                'subscription security and policy sweep', 'operational enrichment',
                'ARM REST API sweep', 'tenant-wide resource sweep',
                'governance dataset sweep'
            )) {
            $escaped = [regex]::Escape($phase)
            $started = [int][regex]::Match($startSection, "'$escaped'\s*\{\s*(\d+)").Groups[1].Value
            $finished = [int][regex]::Match($timingSection, "'$escaped'\s*\{\s*(\d+)").Groups[1].Value
            $started | Should -BeGreaterThan $lastPercent
            $finished | Should -BeGreaterOrEqual $started
            $finished | Should -BeLessOrEqual 99
            $lastPercent = $finished
        }
        $operational | Should -Match "Write-ScoutProgress -Id 3 -ParentId 2 -Activity 'Operational enrichment'"
        $operational | Should -Match "Write-Progress -Id 3 -ParentId 2 -Activity 'Operational enrichment'"
        ([regex]::Matches($operational, '-Completed')).Count | Should -Be 2
    }
}
