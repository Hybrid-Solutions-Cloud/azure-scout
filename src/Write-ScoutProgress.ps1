#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Live, resilient progress reporting for AzureScout (AB#405).

.DESCRIPTION
    Interactive extraction can run inside a real PwshSpectreConsole progress host. Spectre's
    auto-refresh thread keeps the spinner and elapsed-time column moving while the PowerShell
    thread is blocked in an Azure SDK or REST call. Phase updates change the live task instead of
    printing static styled lines.

    AzureScout requires PwshSpectreConsole 2.1.2, a release that declares PowerShell 7.0
    compatibility. PowerShell Gallery therefore installs the
    renderer with AzureScout instead of leaving the primary interactive experience to a manual
    prerequisite. Redirected hosts, CI, and explicitly suppressed progress still use native or
    log-friendly fallbacks. Progress rendering can never cause Azure work to execute twice.
#>

function Test-ScoutSpectreAvailable {
    [CmdletBinding()]
    param([switch] $Force)

    if ($ProgressPreference -eq 'SilentlyContinue') { return $false }

    if (-not $Force) {
        if ($env:CI -or $env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI) {
            return $false
        }
        if (-not [Environment]::UserInteractive) { return $false }
        try { if ([Console]::IsOutputRedirected) { return $false } } catch { return $false }
        if ($null -eq $Host -or $Host.Name -in @('Default Host', 'ServerRemoteHost')) { return $false }
    }

    try {
        return [bool](
            Get-Module -ListAvailable -Name PwshSpectreConsole -ErrorAction SilentlyContinue |
                Where-Object { $_.Version -ge [version]'2.1.2' } |
                Select-Object -First 1
        )
    }
    catch {
        return $false
    }
}

function Import-ScoutSpectreConsole {
    [CmdletBinding()]
    param()

    if (Get-Module -Name PwshSpectreConsole -ErrorAction SilentlyContinue) { return $true }
    try {
        Import-Module PwshSpectreConsole -MinimumVersion 2.1.2 -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        return $true
    }
    catch {
        Write-Verbose "PwshSpectreConsole is unavailable; using native progress: $($_.Exception.Message)"
        return $false
    }
}

function Get-ScoutProgressTaskKey {
    param([Parameter(Mandatory)] [string] $Activity, [Parameter(Mandatory)] [int] $Id)
    return '{0}|{1}' -f $Id, $Activity
}

function ConvertTo-ScoutSpectreText {
    param([AllowEmptyString()] [string] $Text)

    try { return [Spectre.Console.Markup]::Escape($Text) }
    catch { return ($Text -replace '\[', '[[' -replace '\]', ']]') }
}

function New-ScoutSpectreDescription {
    param(
        [Parameter(Mandatory)] [string] $Activity,
        [AllowEmptyString()] [string] $Status
    )

    $safeActivity = ConvertTo-ScoutSpectreText $Activity
    $safeStatus = ConvertTo-ScoutSpectreText $Status
    # No coloured background: the terminal's own foreground remains readable in light and dark
    # themes. Cyan and white reinforce state, while the labels themselves carry the meaning.
    return "[bold cyan1]$safeActivity[/] [white]$safeStatus[/]"
}

function Start-ScoutSpectreProgressHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Activity,
        [string] $Status = 'Starting...',
        [ValidateRange(0, 100)] [int] $PercentComplete = 0,
        [int] $Id = 1,
        [Parameter(Mandatory)] [scriptblock] $Operation,
        [object[]] $ArgumentList = @()
    )

    $state = [pscustomobject]@{
        Started   = $false
        Completed = $false
        Error     = $null
        Output    = @()
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()

    $hadContext = Test-Path Variable:script:ScoutSpectreProgressContext
    $hadTasks = Test-Path Variable:script:ScoutSpectreProgressTasks
    $previousContext = if ($hadContext) { $script:ScoutSpectreProgressContext } else { $null }
    $previousTasks = if ($hadTasks) { $script:ScoutSpectreProgressTasks } else { $null }

    try {
        $columns = [Spectre.Console.ProgressColumn[]]@(
            [Spectre.Console.SpinnerColumn]::new(),
            [Spectre.Console.TaskDescriptionColumn]::new(),
            [Spectre.Console.ProgressBarColumn]::new(),
            [Spectre.Console.PercentageColumn]::new(),
            [Spectre.Console.ElapsedTimeColumn]::new()
        )
        $progress = [Spectre.Console.AnsiConsole]::Progress()
        [void][Spectre.Console.ProgressExtensions]::Columns($progress, $columns)
        [void][Spectre.Console.ProgressExtensions]::AutoRefresh($progress, $true)
        [void][Spectre.Console.ProgressExtensions]::AutoClear($progress, $false)
        [void][Spectre.Console.ProgressExtensions]::HideCompleted($progress, $false)
        $progress.RefreshRate = [TimeSpan]::FromMilliseconds(100)

        $callback = [System.Action[Spectre.Console.ProgressContext]] {
            param($context)

            $tasks = [System.Collections.Generic.Dictionary[string, object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            $description = New-ScoutSpectreDescription -Activity $Activity -Status $Status
            $task = $context.AddTask($description)
            $task.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
            $tasks[(Get-ScoutProgressTaskKey -Activity $Activity -Id $Id)] = $task

            $script:ScoutSpectreProgressContext = $context
            $script:ScoutSpectreProgressTasks = $tasks
            $state.Started = $true

            try {
                $state.Output = @(& $Operation @ArgumentList)
                $state.Completed = $true
                $task.IsIndeterminate = $false
                $task.Value = 100
                $task.Description = New-ScoutSpectreDescription -Activity $Activity -Status 'Complete'
                $task.StopTask()
            }
            catch {
                $state.Error = $_
                $task.IsIndeterminate = $false
                $task.Description = New-ScoutSpectreDescription -Activity $Activity -Status 'Failed'
                $task.StopTask()
            }
        }

        try {
            $progress.Start($callback)
        }
        catch {
            # Once the operation starts it is unsafe to fall back by invoking it again. Mark the
            # exception so the outer wrapper propagates instead of duplicating Azure calls.
            if ($state.Started) { $_.Exception.Data['ScoutProgressOperationStarted'] = $true }
            throw
        }
    }
    finally {
        $timer.Stop()
        if ($hadContext) { $script:ScoutSpectreProgressContext = $previousContext }
        else { Remove-Variable -Name ScoutSpectreProgressContext -Scope Script -ErrorAction SilentlyContinue }
        if ($hadTasks) { $script:ScoutSpectreProgressTasks = $previousTasks }
        else { Remove-Variable -Name ScoutSpectreProgressTasks -Scope Script -ErrorAction SilentlyContinue }
    }

    if ($null -ne $state.Error) {
        $state.Error.Exception.Data['ScoutProgressOperationStarted'] = $true
        throw $state.Error
    }

    try {
        $safeActivity = ConvertTo-ScoutSpectreText $Activity
        Write-SpectreHost ('[green]✓[/] [bold]{0} complete[/] [white]elapsed {1}[/]' -f
            $safeActivity, $timer.Elapsed.ToString('hh\:mm\:ss'))
    }
    catch {
        Write-Verbose "AzureScout progress summary could not be rendered: $($_.Exception.Message)"
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

    if (-not (Test-ScoutSpectreAvailable)) { return (& $Operation @ArgumentList) }
    if (-not (Import-ScoutSpectreConsole)) { return (& $Operation @ArgumentList) }

    try {
        return Start-ScoutSpectreProgressHost -Activity $Activity -Status $Status `
            -PercentComplete $PercentComplete -Id $Id -Operation $Operation -ArgumentList $ArgumentList
    }
    catch {
        if ($_.Exception.Data.Contains('ScoutProgressOperationStarted')) { throw }
        Write-Verbose "AzureScout live progress could not start; using native progress: $($_.Exception.Message)"
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

    # A Spectre host is active around the long-running operation. Updating its task is fast;
    # Spectre's own refresh thread owns the spinner and elapsed clock between these calls.
    if (
        (Test-Path Variable:script:ScoutSpectreProgressContext) -and
        (Test-Path Variable:script:ScoutSpectreProgressTasks) -and
        $null -ne $script:ScoutSpectreProgressContext -and
        $null -ne $script:ScoutSpectreProgressTasks
    ) {
        try {
            $key = Get-ScoutProgressTaskKey -Activity $Activity -Id $Id
            if (-not $script:ScoutSpectreProgressTasks.ContainsKey($key)) {
                $newTask = $script:ScoutSpectreProgressContext.AddTask(
                    (New-ScoutSpectreDescription -Activity $Activity -Status $displayStatus)
                )
                $script:ScoutSpectreProgressTasks[$key] = $newTask
            }

            $task = $script:ScoutSpectreProgressTasks[$key]
            $task.Description = New-ScoutSpectreDescription -Activity $Activity -Status $displayStatus
            if ($Completed) {
                $task.IsIndeterminate = $false
                $task.Value = 100
                $task.StopTask()
            }
            elseif ($PercentComplete -ge 0) {
                $task.IsIndeterminate = $false
                $task.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
            }
            else {
                $task.IsIndeterminate = $true
            }
            return
        }
        catch {
            Write-Verbose "Write-ScoutProgress: live Spectre update failed, falling back to Write-Progress: $($_.Exception.Message)"
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
