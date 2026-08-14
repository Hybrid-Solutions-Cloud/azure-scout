#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Live, resilient progress reporting for AzureScout (AB#405).

.DESCRIPTION
    Interactive runs use AzureScout's built-in renderer. A small in-process .NET timer owns the
    spinner and elapsed clock, so both continue moving while the PowerShell thread is blocked in
    an Azure SDK or REST call. Phase updates change the active line instead of printing static
    styled output.

    The renderer has no external module dependency and never changes PowerShell repository trust.
    It uses bright foreground colours only (never a coloured background) and falls back to native
    Write-Progress or log-friendly information records in redirected, CI, or suppressed hosts.
    Rendering failures can never cause Azure work to execute twice.
#>

function Test-ScoutNativeLiveHost {
    [CmdletBinding()]
    param([switch] $Force)

    if ($ProgressPreference -eq 'SilentlyContinue') { return $false }
    if ($Force) { return $true }

    if ($env:CI -or $env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI) {
        return $false
    }
    if (-not [Environment]::UserInteractive) { return $false }
    try { if ([Console]::IsOutputRedirected) { return $false } } catch { return $false }
    if ($null -eq $Host -or $Host.Name -in @('Default Host', 'ServerRemoteHost')) { return $false }
    return $true
}

function Initialize-ScoutNativeProgressRenderer {
    [CmdletBinding()]
    param()

    if ('AzureScout.NativeProgressRenderer' -as [type]) { return $true }

    $source = @'
using System;
using System.Diagnostics;
using System.Text;
using System.Threading;

namespace AzureScout
{
    public static class NativeProgressRenderer
    {
        private static readonly object Gate = new object();
        private static readonly string[] Frames = new[] { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        private const string BrightCyan = "\u001b[96;1m";
        private const string BrightGreen = "\u001b[92;1m";
        private const string BrightRed = "\u001b[91;1m";
        private const string Dim = "\u001b[90m";
        private const string Reset = "\u001b[0m";

        private static Timer _timer;
        private static Stopwatch _stopwatch;
        private static string _activity = "Azure Scout";
        private static string _status = "Starting...";
        private static int _percent = -1;
        private static int _frame;
        private static int _renderCount;
        private static int _lastPlainLength;
        private static bool _ansi;
        private static bool _active;

        public static bool IsActive
        {
            get { lock (Gate) { return _active; } }
        }

        public static int RenderCount
        {
            get { lock (Gate) { return _renderCount; } }
        }

        public static void Start(string activity, string status, int percent, bool ansi)
        {
            lock (Gate)
            {
                DisposeTimer();
                _activity = Clean(activity, "Azure Scout");
                _status = Clean(status, "Starting...");
                _percent = ClampPercent(percent);
                _ansi = ansi;
                _frame = 0;
                _renderCount = 0;
                _lastPlainLength = 0;
                _stopwatch = Stopwatch.StartNew();
                _active = true;
                _timer = new Timer(RenderTick, null, TimeSpan.Zero, TimeSpan.FromMilliseconds(125));
            }
        }

        public static void Update(string activity, string status, int percent, bool completed)
        {
            lock (Gate)
            {
                if (!_active) return;
                _activity = Clean(activity, _activity);
                _status = Clean(status, _status);
                _percent = completed ? 100 : ClampPercent(percent);
            }
        }

        public static void Stop(bool succeeded, string status)
        {
            lock (Gate)
            {
                if (!_active) return;
                _active = false;
                DisposeTimer();
                if (_stopwatch != null) _stopwatch.Stop();

                try
                {
                    string elapsed = _stopwatch == null ? "00:00:00" : _stopwatch.Elapsed.ToString(@"hh\:mm\:ss");
                    string symbol = succeeded ? "✓" : "✗";
                    string finalStatus = Clean(status, succeeded ? "Complete" : "Failed");
                    string plain = String.Format("{0} {1} — {2} (elapsed {3})", symbol, _activity, finalStatus, elapsed);
                    int width = GetWidth();
                    plain = Truncate(plain, Math.Max(20, width - 1));
                    string colour = succeeded ? BrightGreen : BrightRed;
                    string rendered = _ansi ? colour + plain + Reset : plain;
                    Console.Write("\r" + rendered + Spaces(Math.Max(0, _lastPlainLength - plain.Length)) + Environment.NewLine);
                    _lastPlainLength = 0;
                }
                catch
                {
                    // Progress must never affect the operation result.
                }
            }
        }

        private static void RenderTick(object state)
        {
            lock (Gate)
            {
                if (!_active) return;
                try
                {
                    int width = GetWidth();
                    _renderCount++;
                    string frame = Frames[_frame++ % Frames.Length];
                    string activity = Truncate(_activity, 30);
                    string bar = BuildBar(_percent, 20, _frame);
                    string percent = _percent < 0 ? " --%" : String.Format("{0,3}%", _percent);
                    string elapsed = _stopwatch == null ? "00:00:00" : _stopwatch.Elapsed.ToString(@"hh\:mm\:ss");
                    string fixedPlain = String.Format("{0} {1} [{2}] {3} elapsed {4}  ", frame, activity, bar, percent, elapsed);
                    int statusWidth = Math.Max(0, width - 1 - fixedPlain.Length);
                    string status = Truncate(_status, statusWidth);
                    string plain = fixedPlain + status;
                    string padding = Spaces(Math.Max(0, _lastPlainLength - plain.Length));

                    if (_ansi)
                    {
                        Console.Write("\r" + BrightCyan + frame + " " + activity + Reset +
                            " [" + bar + "] " + percent + " " + Dim + "elapsed " + elapsed + Reset +
                            "  " + status + padding);
                    }
                    else
                    {
                        Console.Write("\r" + plain + padding);
                    }
                    _lastPlainLength = plain.Length;
                }
                catch
                {
                    _active = false;
                    DisposeTimer();
                }
            }
        }

        private static string BuildBar(int percent, int width, int frame)
        {
            if (percent < 0)
            {
                int position = frame % width;
                return new string('─', position) + "●" + new string('─', Math.Max(0, width - position - 1));
            }
            int filled = (int)Math.Round(width * (Math.Min(100, Math.Max(0, percent)) / 100.0));
            return new string('█', filled) + new string('─', width - filled);
        }

        private static int ClampPercent(int percent)
        {
            return percent < 0 ? -1 : Math.Min(100, Math.Max(0, percent));
        }

        private static string Clean(string value, string fallback)
        {
            if (String.IsNullOrWhiteSpace(value)) return fallback ?? String.Empty;
            var builder = new StringBuilder(value.Length);
            foreach (char character in value)
            {
                if (character == '\r' || character == '\n' || character == '\u001b') builder.Append(' ');
                else if (!Char.IsControl(character)) builder.Append(character);
            }
            return builder.ToString().Trim();
        }

        private static string Truncate(string value, int width)
        {
            if (width <= 0) return String.Empty;
            if (String.IsNullOrEmpty(value) || value.Length <= width) return value ?? String.Empty;
            if (width == 1) return "…";
            return value.Substring(0, width - 1) + "…";
        }

        private static int GetWidth()
        {
            try { return Math.Max(60, Console.WindowWidth); }
            catch { return 120; }
        }

        private static string Spaces(int count)
        {
            return count <= 0 ? String.Empty : new string(' ', count);
        }

        private static void DisposeTimer()
        {
            if (_timer == null) return;
            try { _timer.Change(Timeout.Infinite, Timeout.Infinite); } catch { }
            try { _timer.Dispose(); } catch { }
            _timer = null;
        }
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "AzureScout native progress renderer could not initialize: $($_.Exception.Message)"
        return $false
    }
}

function Start-ScoutNativeProgressHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Activity,
        [string] $Status = 'Starting...',
        [ValidateRange(0, 100)] [int] $PercentComplete = 0,
        [int] $Id = 1,
        [Parameter(Mandatory)] [scriptblock] $Operation,
        [object[]] $ArgumentList = @()
    )

    $state = [pscustomobject]@{ Started = $false; Error = $null; Output = @() }
    $hadActive = Test-Path Variable:script:ScoutNativeProgressActive
    $previousActive = if ($hadActive) { $script:ScoutNativeProgressActive } else { $false }
    $supportsAnsi = $false
    try { $supportsAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch { $supportsAnsi = $false }

    try {
        [AzureScout.NativeProgressRenderer]::Start($Activity, $Status, $PercentComplete, $supportsAnsi)
        $script:ScoutNativeProgressActive = $true
        $state.Started = $true
        try {
            $state.Output = @(& $Operation @ArgumentList)
        }
        catch {
            $state.Error = $_
        }
    }
    finally {
        try {
            [AzureScout.NativeProgressRenderer]::Stop(
                ($null -eq $state.Error),
                $(if ($null -eq $state.Error) { 'Complete' } else { 'Failed' })
            )
        }
        catch {
            Write-Verbose "AzureScout progress summary could not be rendered: $($_.Exception.Message)"
        }
        if ($hadActive) { $script:ScoutNativeProgressActive = $previousActive }
        else { Remove-Variable -Name ScoutNativeProgressActive -Scope Script -ErrorAction SilentlyContinue }
    }

    if ($null -ne $state.Error) {
        $state.Error.Exception.Data['ScoutProgressOperationStarted'] = $true
        throw $state.Error
    }
    return $state.Output
}

function Invoke-ScoutProgressOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Activity,
        [string] $Status = 'Starting...',
        [ValidateRange(0, 100)] [int] $PercentComplete = 0,
        [int] $Id = 1,
        [Parameter(Mandatory)] [scriptblock] $Operation,
        [object[]] $ArgumentList = @()
    )

    if (-not (Test-ScoutNativeLiveHost)) { return (& $Operation @ArgumentList) }
    if (-not (Initialize-ScoutNativeProgressRenderer)) { return (& $Operation @ArgumentList) }

    try {
        return Start-ScoutNativeProgressHost -Activity $Activity -Status $Status `
            -PercentComplete $PercentComplete -Id $Id -Operation $Operation -ArgumentList $ArgumentList
    }
    catch {
        if ($_.Exception.Data.Contains('ScoutProgressOperationStarted')) { throw }
        Write-Verbose "AzureScout live progress could not start; using native Write-Progress: $($_.Exception.Message)"
        return (& $Operation @ArgumentList)
    }
}

function Write-ScoutProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Activity,
        [string] $Status = 'Working...',
        [string] $CurrentOperation,
        [int] $PercentComplete = -1,
        [int] $Id = 1,
        [int] $ParentId = -1,
        [switch] $Completed
    )

    $displayStatus = if ([string]::IsNullOrWhiteSpace($CurrentOperation)) {
        $Status
    }
    elseif ([string]::IsNullOrWhiteSpace($Status)) {
        $CurrentOperation
    }
    else {
        '{0} — {1}' -f $Status, $CurrentOperation
    }

    if ((Test-Path Variable:script:ScoutNativeProgressActive) -and $script:ScoutNativeProgressActive) {
        try {
            [AzureScout.NativeProgressRenderer]::Update(
                $Activity,
                $displayStatus,
                $PercentComplete,
                $Completed.IsPresent
            )
            return
        }
        catch {
            Write-Verbose "Write-ScoutProgress: live update failed, falling back to Write-Progress: $($_.Exception.Message)"
        }
    }

    try {
        $progressParams = @{ Activity = $Activity; Status = $displayStatus; Id = $Id }
        if ($ParentId -ge 0) { $progressParams.ParentId = $ParentId }
        if ($Completed) { $progressParams.Completed = $true }
        elseif ($PercentComplete -ge 0) { $progressParams.PercentComplete = [Math]::Min(100, $PercentComplete) }
        Write-Progress @progressParams
    }
    catch {
        Write-Verbose "Write-ScoutProgress: Write-Progress failed, continuing without a progress bar: $($_.Exception.Message)"
    }

    if (-not $Completed -and $ProgressPreference -eq 'SilentlyContinue') {
        try {
            $pctText = if ($PercentComplete -ge 0) { "$PercentComplete%" } else { '...' }
            Write-Information "[$Activity] $pctText $displayStatus" -InformationAction Continue
        }
        catch {
            Write-Verbose "Write-ScoutProgress: log-line fallback failed: $($_.Exception.Message)"
        }
    }
}
