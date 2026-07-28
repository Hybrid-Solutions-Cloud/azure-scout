<#
.Synopsis
Per-run diagnostic log for Azure Scout.

.DESCRIPTION
Every run writes a detailed, timestamped log into its own run folder, with no extra
parameter required from the operator (AB#5634 / AB#5635).

Before this existed, a failed run left nothing behind but a single red line on the
console. Working out what a run actually did - which subscriptions it reached, which
phase it was in, how long each phase took, where it died - meant running the whole tool
again with -Debug and watching the screen. That is not a diagnostic story, and it is why
a data-dependent crash (AB#5633) took a full reproduction cycle to locate.

Two files are written into the run folder:

  scout-run.log      structured phase log - metadata header, phase boundaries with
                     elapsed time, per-phase counts, warnings, and the full error record
                     (message, script, line, script stack trace) when a run fails.
  scout-console.log  best-effort PowerShell transcript of everything printed to the
                     console, including warnings. Skipped silently on hosts that do not
                     support transcription.

Logging must never be the reason a run fails, so every function here swallows its own
errors. A broken log is a lost diagnostic, not a lost report.

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).
#>

$script:AZSCRunLogPath = $null
$script:AZSCTranscriptPath = $null
$script:AZSCRunLogStart = $null

function Start-AZSCRunLog {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$DefaultPath,

        [hashtable]$Metadata,

        [switch]$NoTranscript
    )

    try {
        if (-not (Test-Path -Path $DefaultPath)) {
            # -ErrorAction Stop: a bad path raises a NON-terminating error by default, which
            # would sail straight past this try/catch and out to the console as red text.
            $null = New-Item -Path $DefaultPath -ItemType Directory -Force -ErrorAction Stop
        }

        $script:AZSCRunLogPath = Join-Path $DefaultPath 'scout-run.log'
        $script:AZSCRunLogStart = Get-Date

        $Header = @()
        $Header += '================================================================'
        $Header += ' Azure Scout run log'
        $Header += '================================================================'
        $Header += (' Started      : ' + $script:AZSCRunLogStart.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))

        if ($Metadata) {
            foreach ($Key in ($Metadata.Keys | Sort-Object)) {
                $Value = $Metadata[$Key]
                if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                    $Value = (@($Value) -join ', ')
                }
                $Header += (' {0,-12} : {1}' -f $Key, $Value)
            }
        }

        $Header += '================================================================'
        $Header += ''

        Set-Content -Path $script:AZSCRunLogPath -Value $Header -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # A run folder we cannot write to is worth one warning, not a failed run.
        Write-Warning "[AzureScout] Could not start the run log: $($_.Exception.Message)"
        $script:AZSCRunLogPath = $null
        return
    }

    if ($NoTranscript.IsPresent) { return }

    try {
        $script:AZSCTranscriptPath = Join-Path $DefaultPath 'scout-console.log'
        Start-Transcript -Path $script:AZSCTranscriptPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # Transcription is unavailable in some hosts (and in Azure Automation). The
        # structured log above is the part that matters; carry on without it.
        $script:AZSCTranscriptPath = $null
    }
}

function Write-AZSCLog {
    <#
        AB#5649 — VERBOSE and -Color exist because seven inventory collectors already call
        this function that way:

            Write-AZSCLog -Message "  >> Processing Defender Alerts for: $x" -Color 'Cyan'
            Write-AZSCLog -Message "No identity providers data available"     -Level Verbose

        Those call sites are in Monitor/SubscriptionDiagnosticSettings and the four
        Security/Defender* collectors. Neither 'Verbose' nor -Color was accepted, so every one
        of them threw "A parameter cannot be found that matches parameter name 'Color'" the
        moment it was reached — and the old pipeline ran collectors inside a runspace whose
        errors surfaced detached at EndInvoke time, so those five collectors have been dead in
        shipped releases with nothing in the report or the console to say so. Running them
        in-process is what made it visible.

        Widening the signature here fixes all five at once and keeps one meaning for the name,
        which is why it is preferred over editing five collectors to drop the arguments.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'PHASE', 'WARN', 'ERROR', 'DEBUG', 'VERBOSE')]
        [string]$Level = 'INFO',

        # Console colour hint. When supplied the message is also written to the host, which is
        # what the collector call sites are asking for. Omitted, this stays a file-only log.
        [ValidateNotNullOrEmpty()]
        [string]$Color
    )

    if ($PSBoundParameters.ContainsKey('Color')) {
        try { Write-Host $Message -ForegroundColor $Color }
        catch { Write-Host $Message }
    }

    if (-not $script:AZSCRunLogPath) { return }

    try {
        $Stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $Line = '[{0}] [{1,-5}] {2}' -f $Stamp, $Level.ToUpperInvariant(), $Message
        Add-Content -Path $script:AZSCRunLogPath -Value $Line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Deliberately silent: a failed log write must not derail the run.
    }
}

function Write-AZSCLogPhase {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [string]$Elapsed,

        [hashtable]$Detail
    )

    if (-not $script:AZSCRunLogPath) { return }

    $Text = $Name
    if ($Elapsed) { $Text = "$Text (elapsed $Elapsed)" }
    Write-AZSCLog -Message $Text -Level 'PHASE'

    if ($Detail) {
        foreach ($Key in ($Detail.Keys | Sort-Object)) {
            $Value = $Detail[$Key]
            if ($null -eq $Value) { $Value = '<none>' }
            elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                $Value = (@($Value) -join ', ')
            }
            Write-AZSCLog -Message ('    {0,-22} : {1}' -f $Key, $Value) -Level 'INFO'
        }
    }
}

function Write-AZSCLogError {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if (-not $script:AZSCRunLogPath) { return }

    try {
        Write-AZSCLog -Message '---------------- RUN FAILED ----------------' -Level 'ERROR'
        Write-AZSCLog -Message ('Message    : ' + $ErrorRecord.Exception.Message) -Level 'ERROR'
        Write-AZSCLog -Message ('Type       : ' + $ErrorRecord.Exception.GetType().FullName) -Level 'ERROR'
        Write-AZSCLog -Message ('Category   : ' + $ErrorRecord.CategoryInfo.ToString()) -Level 'ERROR'
        Write-AZSCLog -Message ('FullyQualifiedErrorId : ' + $ErrorRecord.FullyQualifiedErrorId) -Level 'ERROR'

        if ($ErrorRecord.InvocationInfo) {
            Write-AZSCLog -Message ('Script     : ' + $ErrorRecord.InvocationInfo.ScriptName) -Level 'ERROR'
            Write-AZSCLog -Message ('Line       : ' + $ErrorRecord.InvocationInfo.ScriptLineNumber) -Level 'ERROR'
            if ($ErrorRecord.InvocationInfo.Line) {
                Write-AZSCLog -Message ('Statement  : ' + $ErrorRecord.InvocationInfo.Line.Trim()) -Level 'ERROR'
            }
        }

        Write-AZSCLog -Message 'ScriptStackTrace :' -Level 'ERROR'
        foreach ($Frame in (($ErrorRecord.ScriptStackTrace -split "`r?`n") | Where-Object { $_ })) {
            Write-AZSCLog -Message ('    ' + $Frame) -Level 'ERROR'
        }

        $Inner = $ErrorRecord.Exception.InnerException
        $Depth = 0
        while ($Inner -and $Depth -lt 5) {
            Write-AZSCLog -Message ("InnerException[$Depth] : " + $Inner.Message) -Level 'ERROR'
            $Inner = $Inner.InnerException
            $Depth++
        }
    }
    catch {
        # Never let error logging raise a second error on top of the first.
    }
}

function Stop-AZSCRunLog {
    [CmdletBinding()]
    Param(
        [ValidateSet('COMPLETED', 'FAILED')]
        [string]$Status = 'COMPLETED',

        [switch]$Quiet
    )

    $Path = $script:AZSCRunLogPath

    if ($Path) {
        try {
            $Elapsed = if ($script:AZSCRunLogStart) {
                ((Get-Date) - $script:AZSCRunLogStart).ToString('dd\:hh\:mm\:ss\:fff')
            }
            else { 'unknown' }

            Write-AZSCLog -Message '' -Level 'INFO'
            Write-AZSCLog -Message ("Run $Status after $Elapsed") -Level 'PHASE'
        }
        catch {
            # nothing useful left to do here
        }
    }

    if ($script:AZSCTranscriptPath) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { }
        $script:AZSCTranscriptPath = $null
    }

    if ($Path -and -not $Quiet.IsPresent) {
        Write-Host '  Run log      : ' -NoNewline -ForegroundColor DarkGray
        Write-Host $Path -ForegroundColor Cyan
    }

    $script:AZSCRunLogPath = $null
    $script:AZSCRunLogStart = $null

    return $Path
}

function Get-AZSCRunLogPath {
    [CmdletBinding()]
    Param()
    return $script:AZSCRunLogPath
}
