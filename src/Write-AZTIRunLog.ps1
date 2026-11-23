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

One file is written into the run folder:

  scout-run.log      metadata header, phase boundaries with elapsed time, per-phase counts,
                     warnings, everything Scout printed to the console ([CONSOLE] lines), the
                     diagram builder's messages, and the full error record (message, script,
                     line, script stack trace) when a run fails.

A multi-tenant run is one scan, so it writes one scout-run.log at the run root. Each tenant
gets a labelled section in that file; the tenant folders hold that tenant's data, not a log.

There used to be a second file, scout-console.log, a PowerShell transcript of the console, and
a third, DiagramLogFile.log. Operators had to read three files to follow one run. The console
lines now go into scout-run.log through the Write-Host proxy below, and the diagram messages are
folded in when the diagram build finishes.

Logging must never be the reason a run fails, so every function here swallows its own
errors. A broken log is a lost diagnostic, not a lost report.

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).
#>

# The run log is held open for the life of the run. Opening, appending and closing the file for
# every record (the previous Add-Content design) cost 25-240 ms per line on real hosts; a run
# that captured ~50 SDK debug records per Azure call spent about 12 seconds per call writing
# them, which turned a scan that needed minutes of Azure time into hours.
$existingRunLogWriter = Get-Variable -Scope Script -Name AZSCRunLogWriter -ValueOnly -ErrorAction Ignore
if ($existingRunLogWriter) { try { $existingRunLogWriter.Dispose() } catch { $null = $_ } }
$script:AZSCRunLogWriter = $null
$script:AZSCRunLogWriterPath = $null
$script:AZSCRunLogPath = $null
$script:AZSCTranscriptPath = $null
$script:AZSCRunLogStart = $null
$script:AZSCPendingLog = [System.Collections.Generic.List[object]]::new()
$script:AZSCPendingLogDropped = 0
# Multi-tenant runs: the root log every tenant section is written into, and whether a tenant
# section is currently open inside it.
$script:AZSCSharedRunLogPath = $null
$script:AZSCSharedRunLogStart = $null
$script:AZSCRunLogSectionActive = $false
# Write-Host -NoNewline fragments are joined into one [CONSOLE] line.
$script:AZSCConsoleLine = [System.Text.StringBuilder]::new()

function Protect-ScoutLogText {
    param([AllowEmptyString()][string]$Text)
    $Text = [regex]::Replace($Text, '(?is)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', '[REDACTED PRIVATE KEY]')
    $Text = [regex]::Replace($Text, '(?im)(Authorization["'']?\s*[=:]\s*["'']?)(?:Bearer|Basic)\s+[^\s"'']+', '$1[REDACTED]')
    $Text = [regex]::Replace($Text, '(?i)(["'']?(?:access_?token|refresh_?token|id_?token|client_?secret|password|accountkey|sharedaccesskey|connectionstring)["'']?\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s;&,}]+)', '$1[REDACTED]')
    $Text = [regex]::Replace($Text, '(?i)([?&]sig=)[^&\s"'']+', '$1[REDACTED]')
    return $Text
}

function Close-ScoutRunLogWriter {
    if ($script:AZSCRunLogWriter) {
        try { $script:AZSCRunLogWriter.Dispose() } catch { $null = $_ }
    }
    $script:AZSCRunLogWriter = $null
    $script:AZSCRunLogWriterPath = $null
}

function Add-ScoutRunLogText {
    # Appends already-redacted text to the active run log through one long-lived writer.
    # AutoFlush hands every record to the operating system immediately, so a run that dies
    # still leaves everything it logged on disk; what is avoided is the per-record open/close.
    # The file is shared for read, write and delete so an operator can tail it during a run.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if (-not $script:AZSCRunLogPath) { return }
    if ($script:AZSCRunLogWriter -and $script:AZSCRunLogWriterPath -ne $script:AZSCRunLogPath) {
        Close-ScoutRunLogWriter
    }
    if (-not $script:AZSCRunLogWriter) {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $stream = [System.IO.FileStream]::new(
            $script:AZSCRunLogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, $share)
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
        $writer.AutoFlush = $true
        $script:AZSCRunLogWriter = $writer
        $script:AZSCRunLogWriterPath = $script:AZSCRunLogPath
    }
    try {
        $script:AZSCRunLogWriter.Write($Text + [Environment]::NewLine)
    }
    catch {
        # Drop the broken handle so the next record reopens the file instead of failing forever.
        Close-ScoutRunLogWriter
        throw
    }
}

function Test-ScoutSdkTraceEnabled {
    # Full SDK wire-level capture (MSAL token steps, HTTP request and response bodies) for
    # every successful call is opt-in: run with -Debug, or set AZURESCOUT_SDK_TRACE=1.
    param([string]$ConsoleDebugPreference)
    if ($ConsoleDebugPreference -in @('Continue', 'Inquire')) { return $true }
    return ([string]$env:AZURESCOUT_SDK_TRACE) -in @('1', 'true', 'True', 'TRUE')
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

function Write-Host {
    # Everything Scout prints to the console also lands in scout-run.log as a [CONSOLE] line, so
    # the run log alone shows what the operator saw. This replaces the separate transcript file.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Private module proxy; copies console output into the one run log.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Proxy for Write-Host itself.')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromRemainingArguments)]
        [object]$Object,
        [switch]$NoNewline,
        [object]$Separator,
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor
    )
    process {
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
        if (-not $script:AZSCRunLogPath) { return }
        try {
            $joiner = if ($PSBoundParameters.ContainsKey('Separator')) { [string]$Separator } else { ' ' }
            $text = if ($null -eq $Object) { '' }
                elseif ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) { (@($Object) | ForEach-Object { [string]$_ }) -join $joiner }
                else { [string]$Object }
            [void]$script:AZSCConsoleLine.Append($text)
            if (-not $NoNewline) {
                $line = $script:AZSCConsoleLine.ToString()
                [void]$script:AZSCConsoleLine.Clear()
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-AZSCLog -Level CONSOLE -Message $line.TrimEnd() -FileOnly }
            }
        }
        catch { Microsoft.PowerShell.Utility\Write-Debug ('Write-Host proxy: could not copy console output to the run log: ' + $_.Exception.Message) }
    }
}

function Format-ScoutRunLogHeaderLine {
    param([hashtable]$Metadata)
    if (-not $Metadata) { return @() }
    foreach ($Key in ($Metadata.Keys | Sort-Object)) {
        $Value = $Metadata[$Key]
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $Value = (@($Value) -join ', ')
        }
        ' {0,-12} : {1}' -f $Key, $Value
    }
}

function Add-ScoutFileToRunLog {
    # Folds a side file (the diagram builder's log) into scout-run.log and removes it, so a run
    # leaves one log. Lines are kept verbatim under a label; nothing is dropped.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    if (-not $script:AZSCRunLogPath -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -gt 0) {
            $block = foreach ($line in $lines) { '[{0}] [{1,-5}] {2}' -f $stamp, $Label, $line }
            Add-ScoutRunLogText -Text (Protect-ScoutLogText -Text ($block -join [Environment]::NewLine))
        }
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch { Microsoft.PowerShell.Utility\Write-Debug ("Add-ScoutFileToRunLog: could not fold '$Path' into the run log: " + $_.Exception.Message) }
}

function Invoke-ScoutDiagnosticOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Operation)
    # SDK modules have their own scope, so capture their streams at the request boundary.
    # Only success objects leave this function; diagnostic records never become inventory.
    #
    # The SDK emits roughly fifty debug records per Azure call (MSAL token steps plus the full
    # HTTP request and response body). They are held in memory for the duration of the call and
    # written to the run log only when they are needed to explain something: the call threw, it
    # returned an HTTP status of 400 or above, or the operator asked for a full trace
    # (-Debug, or AZURESCOUT_SDK_TRACE=1). A successful call writes nothing here; its caller
    # already records the dataset, status, attempts and elapsed time. Warnings are always kept.
    $consoleDebug = $DebugPreference
    $consoleVerbose = $VerbosePreference
    $consoleWarning = $WarningPreference
    $traceEverything = Test-ScoutSdkTraceEnabled -ConsoleDebugPreference $consoleDebug
    $DebugPreference = 'Continue'
    $VerbosePreference = 'Continue'
    $WarningPreference = 'Continue'
    $held = [System.Collections.Generic.List[string]]::new()
    $callState = @{ HttpFailure = $false }
    $writeHeld = {
        if ($held.Count -eq 0) { return }
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $block = foreach ($entry in $held) { '[{0}] {1}' -f $stamp, (Protect-ScoutLogText -Text $entry) }
        try { Add-ScoutRunLogText -Text ($block -join [Environment]::NewLine) }
        catch { Microsoft.PowerShell.Utility\Write-Debug ('Invoke-ScoutDiagnosticOperation: failed to write SDK diagnostics: ' + $_.Exception.Message) }
        $held.Clear()
    }
    try {
        & $Operation 3>&1 4>&1 5>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.DebugRecord]) {
                $held.Add('[DEBUG] ' + $_.Message)
                if ($consoleDebug -in @('Continue', 'Inquire')) { Microsoft.PowerShell.Utility\Write-Debug (Protect-ScoutLogText $_.Message) }
            }
            elseif ($_ -is [System.Management.Automation.VerboseRecord]) {
                $held.Add('[VERBOSE] ' + $_.Message)
                if ($consoleVerbose -in @('Continue', 'Inquire')) { Microsoft.PowerShell.Utility\Write-Verbose (Protect-ScoutLogText $_.Message) }
            }
            elseif ($_ -is [System.Management.Automation.WarningRecord]) {
                Write-AZSCLog -Level WARN -Message $_.Message -FileOnly
                if ($consoleWarning -ne 'SilentlyContinue') { Microsoft.PowerShell.Utility\Write-Warning (Protect-ScoutLogText $_.Message) }
            }
            else {
                # Invoke-AzRestMethod reports HTTP failures as a returned object, not an exception.
                if ($null -ne $_ -and $_ -isnot [string] -and $_.PSObject.Properties['StatusCode']) {
                    $statusCode = 0
                    if ([int]::TryParse([string]$_.StatusCode, [ref]$statusCode) -and $statusCode -ge 400) { $callState.HttpFailure = $true }
                }
                $PSCmdlet.WriteObject($_, $false)
            }
        }
        if ($traceEverything -or $callState.HttpFailure) { & $writeHeld }
    }
    catch {
        & $writeHeld
        Write-AZSCLog -Level ERROR -Message $_.Exception.Message -FileOnly
        if ($_.ErrorDetails) { Write-AZSCLog -Level ERROR -Message $_.ErrorDetails.Message -FileOnly }
        throw
    }
}

function Start-AZSCRunLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NoTranscript', Justification = 'Compatibility; the transcript file was retired.')]
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$DefaultPath,

        [hashtable]$Metadata,

        # Kept so existing callers still bind. There is no transcript any more: console output
        # is copied into scout-run.log by the Write-Host proxy, so this switch changes nothing.
        [switch]$NoTranscript,

        # Add to an existing scout-run.log instead of replacing it (a resumed multi-tenant run).
        [switch]$Append
    )

    # Inside a multi-tenant run every tenant writes a section into the one root log instead of
    # starting its own file in the tenant folder.
    if ($script:AZSCSharedRunLogPath) {
        $script:AZSCRunLogPath = $script:AZSCSharedRunLogPath
        $script:AZSCRunLogStart = Get-Date
        $script:AZSCRunLogSectionActive = $true
        $Section = @('', '----------------------------------------------------------------')
        $Section += ' Tenant section'
        $Section += '----------------------------------------------------------------'
        $Section += (' Started      : ' + $script:AZSCRunLogStart.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))
        $Section += @(Format-ScoutRunLogHeaderLine -Metadata $Metadata)
        $Section += '----------------------------------------------------------------'
        try { Add-ScoutRunLogText -Text (Protect-ScoutLogText -Text ($Section -join [Environment]::NewLine)) }
        catch { Microsoft.PowerShell.Utility\Write-Debug ('Start-AZSCRunLog: could not open the tenant section: ' + $_.Exception.Message) }
    }
    else {
        try {
            if (-not (Test-Path -Path $DefaultPath)) {
                # -ErrorAction Stop: a bad path raises a NON-terminating error by default, which
                # would sail straight past this try/catch and out to the console as red text.
                $null = New-Item -Path $DefaultPath -ItemType Directory -Force -ErrorAction Stop
            }

            Close-ScoutRunLogWriter
            $script:AZSCRunLogPath = Join-Path $DefaultPath 'scout-run.log'
            $script:AZSCRunLogStart = Get-Date
            $script:AZSCRunLogSectionActive = $false
            [void]$script:AZSCConsoleLine.Clear()

            $Header = @()
            if ($Append.IsPresent -and (Test-Path -LiteralPath $script:AZSCRunLogPath -PathType Leaf)) { $Header += '' }
            $Header += '================================================================'
            $Header += ' Azure Scout run log'
            $Header += '================================================================'
            $Header += (' Started      : ' + $script:AZSCRunLogStart.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))
            $Header += @(Format-ScoutRunLogHeaderLine -Metadata $Metadata)
            $Header += '================================================================'
            $Header += ''

            if ($Append.IsPresent -and (Test-Path -LiteralPath $script:AZSCRunLogPath -PathType Leaf)) {
                Add-ScoutRunLogText -Text (Protect-ScoutLogText -Text ($Header -join "`n"))
            }
            else {
                Set-Content -Path $script:AZSCRunLogPath -Value (Protect-ScoutLogText -Text ($Header -join "`n")) -Encoding UTF8 -ErrorAction Stop
            }
        }
        catch {
            # A run folder we cannot write to is worth one warning, not a failed run.
            Microsoft.PowerShell.Utility\Write-Warning "[AzureScout] Could not start the run log: $($_.Exception.Message)"
            $script:AZSCRunLogPath = $null
            return
        }
    }

    foreach ($entry in $script:AZSCPendingLog) {
        Write-AZSCLog -Level $entry.Level -Message ("[before log initialization at $($entry.Timestamp)] " + $entry.Message) -FileOnly
    }
    $script:AZSCPendingLog.Clear()
    if ($script:AZSCPendingLogDropped -gt 0) {
        Write-AZSCLog -Level WARN -Message "$script:AZSCPendingLogDropped pre-run diagnostics exceeded the 10000-entry buffer. Run-time diagnostics are not capped."
        $script:AZSCPendingLogDropped = 0
    }
}

function Start-AZSCSharedRunLog {
    # Opens the one scout-run.log at a multi-tenant run root. Every tenant's Start-AZSCRunLog then
    # writes a section into it instead of creating a file in its tenant folder.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DefaultPath, [hashtable]$Metadata)
    $script:AZSCSharedRunLogPath = $null
    $script:AZSCRunLogSectionActive = $false
    Start-AZSCRunLog -DefaultPath $DefaultPath -Metadata $Metadata -Append
    if ($script:AZSCRunLogPath) {
        $script:AZSCSharedRunLogPath = $script:AZSCRunLogPath
        $script:AZSCSharedRunLogStart = $script:AZSCRunLogStart
    }
    return $script:AZSCSharedRunLogPath
}

function Stop-AZSCSharedRunLog {
    [CmdletBinding()]
    param(
        [ValidateSet('COMPLETED', 'FAILED', 'INTERRUPTED')]
        [string]$Status = 'COMPLETED',
        [switch]$Quiet
    )
    if (-not $script:AZSCSharedRunLogPath) { return $null }
    $script:AZSCRunLogSectionActive = $false
    $script:AZSCRunLogPath = $script:AZSCSharedRunLogPath
    $script:AZSCRunLogStart = $script:AZSCSharedRunLogStart
    $script:AZSCSharedRunLogPath = $null
    $script:AZSCSharedRunLogStart = $null
    return (Stop-AZSCRunLog -Status $Status -Quiet:$Quiet)
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

        [ValidateSet('INFO', 'PHASE', 'WARN', 'ERROR', 'DEBUG', 'VERBOSE', 'CONSOLE')]
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
        # The real cmdlet, not the module's Write-Host proxy: this message is logged below already.
        try { Microsoft.PowerShell.Utility\Write-Host $Message -ForegroundColor $Color }
        catch { Microsoft.PowerShell.Utility\Write-Host $Message }
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
        Add-ScoutRunLogText -Text (Protect-ScoutLogText -Text ($Lines -join "`n"))
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
        [ValidateSet('COMPLETED', 'FAILED', 'INTERRUPTED')]
        [string]$Status = 'COMPLETED',

        [switch]$Quiet
    )

    $Path = $script:AZSCRunLogPath

    # Closing a tenant section of a multi-tenant run: mark the section's end, keep the root log
    # open for the next tenant and for the run summary.
    if ($script:AZSCRunLogSectionActive -and $script:AZSCSharedRunLogPath) {
        try {
            $Elapsed = if ($script:AZSCRunLogStart) { ((Get-Date) - $script:AZSCRunLogStart).ToString('dd\:hh\:mm\:ss\:fff') } else { 'unknown' }
            Write-AZSCLog -Message ("Tenant section $Status after $Elapsed") -Level 'PHASE'
        }
        catch { Microsoft.PowerShell.Utility\Write-Debug ('Stop-AZSCRunLog: failed to close the tenant section: ' + $_.Exception.Message) }
        $script:AZSCRunLogSectionActive = $false
        $script:AZSCRunLogPath = $script:AZSCSharedRunLogPath
        $script:AZSCRunLogStart = $script:AZSCSharedRunLogStart
        return $script:AZSCSharedRunLogPath
    }

    if ($script:AZSCConsoleLine.Length -gt 0 -and $Path) {
        try { Write-AZSCLog -Level CONSOLE -Message $script:AZSCConsoleLine.ToString().TrimEnd() -FileOnly } catch { $null = $_ }
        [void]$script:AZSCConsoleLine.Clear()
    }

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

    Close-ScoutRunLogWriter
    $script:AZSCRunLogPath = $null
    $script:AZSCRunLogStart = $null
    $script:AZSCPendingLog.Clear()
    $script:AZSCPendingLogDropped = 0

    return $Path
}

function Get-AZSCRunLogPath {
    # The log the CURRENT run or tenant section is writing to. Between tenant sections of a
    # multi-tenant run nothing is open at tenant level, so this is $null; Invoke-AzureScout's
    # finally reads it to decide whether its own log was left unclosed.
    [CmdletBinding()]
    Param()
    if ($script:AZSCSharedRunLogPath -and -not $script:AZSCRunLogSectionActive) { return $null }
    return $script:AZSCRunLogPath
}
