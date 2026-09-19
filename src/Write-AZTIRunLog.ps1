#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
$script:AZSCPendingLog = [System.Collections.Generic.List[object]]::new()
$script:AZSCPendingLogDropped = 0

function Protect-ScoutLogText {
    param([AllowEmptyString()][string]$Text)
    $Text = [regex]::Replace($Text, '(?is)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', '[REDACTED PRIVATE KEY]')
    $Text = [regex]::Replace($Text, '(?im)(Authorization["'']?\s*[=:]\s*["'']?)(?:Bearer|Basic)\s+[^\s"'']+', '$1[REDACTED]')
    $Text = [regex]::Replace($Text, '(?i)(["'']?(?:access_?token|refresh_?token|id_?token|client_?secret|password|accountkey|sharedaccesskey|connectionstring)["'']?\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s;&,}]+)', '$1[REDACTED]')
    $Text = [regex]::Replace($Text, '(?i)([?&]sig=)[^&\s"'']+', '$1[REDACTED]')
    return $Text
}

# Private module commands capture Scout diagnostics even when their console streams are
# disabled. The manifest does not export these proxies into the caller's session.
function Write-Debug {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Private module diagnostic proxy; always persists debug messages (AB#9298).')]
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0, ValueFromPipeline)][AllowEmptyString()][string]$Message)
    process { Write-AZSCLog -Level DEBUG -Message $Message }
}

function Write-Verbose {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Private module diagnostic proxy; always persists verbose messages (AB#9298).')]
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0, ValueFromPipeline)][AllowEmptyString()][string]$Message)
    process { Write-AZSCLog -Level VERBOSE -Message $Message }
}

function Write-Warning {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Private module diagnostic proxy; persists warnings regardless of console preference (AB#9298).')]
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0, ValueFromPipeline)][AllowEmptyString()][string]$Message)
    process {
        Write-AZSCLog -Level WARN -Message $Message -FileOnly
        Microsoft.PowerShell.Utility\Write-Warning (Protect-ScoutLogText -Text $Message)
    }
}

function Invoke-ScoutDiagnosticOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Operation)
    # SDK modules have their own scope, so capture their streams at the request boundary.
    # Only success objects leave this function; diagnostic records never become inventory.
    $consoleDebug = $DebugPreference
    $consoleVerbose = $VerbosePreference
    $consoleWarning = $WarningPreference
    $DebugPreference = 'Continue'
    $VerbosePreference = 'Continue'
    $WarningPreference = 'Continue'
    try {
        & $Operation 3>&1 4>&1 5>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.DebugRecord]) {
                Write-AZSCLog -Level DEBUG -Message $_.Message -FileOnly
                if ($consoleDebug -in @('Continue', 'Inquire')) { Microsoft.PowerShell.Utility\Write-Debug (Protect-ScoutLogText $_.Message) }
            }
            elseif ($_ -is [System.Management.Automation.VerboseRecord]) {
                Write-AZSCLog -Level VERBOSE -Message $_.Message -FileOnly
                if ($consoleVerbose -in @('Continue', 'Inquire')) { Microsoft.PowerShell.Utility\Write-Verbose (Protect-ScoutLogText $_.Message) }
            }
            elseif ($_ -is [System.Management.Automation.WarningRecord]) {
                Write-AZSCLog -Level WARN -Message $_.Message -FileOnly
                if ($consoleWarning -ne 'SilentlyContinue') { Microsoft.PowerShell.Utility\Write-Warning (Protect-ScoutLogText $_.Message) }
            }
            else { $PSCmdlet.WriteObject($_, $false) }
        }
    }
    catch {
        Write-AZSCLog -Level ERROR -Message $_.Exception.Message -FileOnly
        if ($_.ErrorDetails) { Write-AZSCLog -Level ERROR -Message $_.ErrorDetails.Message -FileOnly }
        throw
    }
}

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

        Set-Content -Path $script:AZSCRunLogPath -Value (Protect-ScoutLogText -Text ($Header -join "`n")) -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # A run folder we cannot write to is worth one warning, not a failed run.
        Microsoft.PowerShell.Utility\Write-Warning "[AzureScout] Could not start the run log: $($_.Exception.Message)"
        $script:AZSCRunLogPath = $null
        return
    }

    foreach ($entry in $script:AZSCPendingLog) {
        Write-AZSCLog -Level $entry.Level -Message ("[before log initialization at $($entry.Timestamp)] " + $entry.Message) -FileOnly
    }
    $script:AZSCPendingLog.Clear()
    if ($script:AZSCPendingLogDropped -gt 0) {
        Write-AZSCLog -Level WARN -Message "$script:AZSCPendingLogDropped pre-run diagnostics exceeded the 10000-entry buffer. Run-time diagnostics are not capped."
        $script:AZSCPendingLogDropped = 0
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

        # Report/export catch blocks already pass their caught exception here. Keep the
        # ordinary message concise, then add type and stack detail to the durable file only.
        [System.Exception]$Exception,

        # Console colour hint. When supplied the message is also written to the host, which is
        # what the collector call sites are asking for. Omitted, this stays a file-only log.
        [ValidateNotNullOrEmpty()]
        [string]$Color,

        [switch]$FileOnly
    )

    # DEBUG and VERBOSE are always durable file detail, but they should obey the
    # caller's ordinary PowerShell stream preferences on the console.  Do not set
    # either preference here: Write-Debug/Write-Verbose stay silent by default and
    # become visible only when the caller requested -Debug/-Verbose.
    $Message = Protect-ScoutLogText -Text $Message
    if ($DebugPreference -eq 'Inquire') { $DebugPreference = 'Continue' }
    if ($VerbosePreference -eq 'Inquire') { $VerbosePreference = 'Continue' }
    try {
        switch ($Level.ToUpperInvariant()) {
            'DEBUG'   { if (-not $FileOnly) { Microsoft.PowerShell.Utility\Write-Debug $Message } }
            'VERBOSE' { if (-not $FileOnly) { Microsoft.PowerShell.Utility\Write-Verbose $Message } }
        }
    }
    catch {
        # Stream preferences such as Stop must not turn optional logging into a run failure.
        $null = $_.Exception
    }

    if ($PSBoundParameters.ContainsKey('Color')) {
        try { Write-Host $Message -ForegroundColor $Color }
        catch { Write-Host $Message }
    }

    if (-not $script:AZSCRunLogPath) {
        if ($script:AZSCPendingLog.Count -lt 10000) {
            $script:AZSCPendingLog.Add([pscustomobject]@{ Timestamp = (Get-Date).ToString('o'); Level = $Level; Message = $Message })
        }
        else { $script:AZSCPendingLogDropped++ }
        return
    }

    try {
        $Stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $Lines = @('[{0}] [{1,-5}] {2}' -f $Stamp, $Level.ToUpperInvariant(), $Message)
        if ($Exception) {
            $Lines += '[{0}] [{1,-5}] Exception type: {2}' -f $Stamp, $Level.ToUpperInvariant(), $Exception.GetType().FullName
            if ($Exception.StackTrace) {
                foreach ($Frame in ($Exception.StackTrace -split "`r?`n" | Where-Object { $_ })) {
                    $Lines += '[{0}] [{1,-5}]     {2}' -f $Stamp, $Level.ToUpperInvariant(), $Frame.Trim()
                }
            }
        }
        Add-Content -Path $script:AZSCRunLogPath -Value (Protect-ScoutLogText -Text ($Lines -join "`n")) -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Deliberately silent: a failed log write must not derail the run.
        Microsoft.PowerShell.Utility\Write-Debug ('Write-AZSCLog: failed to write to the run log: ' + $_.Exception.Message)
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
        Microsoft.PowerShell.Utility\Write-Debug ('Write-AZSCLogError: failed while logging the original error: ' + $_.Exception.Message)
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
            Write-AZSCLog -Message ("Scan/log execution $Status after $Elapsed") -Level 'PHASE'
        }
        catch {
            # nothing useful left to do here
            Microsoft.PowerShell.Utility\Write-Debug ('Stop-AZSCRunLog: failed to write the closing log entry: ' + $_.Exception.Message)
        }
    }

    if ($script:AZSCTranscriptPath) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { Microsoft.PowerShell.Utility\Write-Debug ('Stop-AZSCRunLog: Stop-Transcript failed (no transcript running?): ' + $_.Exception.Message) }
        $script:AZSCTranscriptPath = $null
    }

    if ($Path -and -not $Quiet.IsPresent) {
        Write-Host '  Run log      : ' -NoNewline -ForegroundColor DarkGray
        Write-Host $Path -ForegroundColor Cyan
    }

    $script:AZSCRunLogPath = $null
    $script:AZSCRunLogStart = $null
    $script:AZSCPendingLog.Clear()
    $script:AZSCPendingLogDropped = 0

    return $Path
}

function Get-AZSCRunLogPath {
    [CmdletBinding()]
    Param()
    return $script:AZSCRunLogPath
}
