#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Run one inventory collector in-process, with its failure contained (AB#5649).

.DESCRIPTION
    Replaces the per-collector `[PowerShell]::Create().AddScript(...).BeginInvoke()` runspace
    from `Start-AZSCProcessJob`. That design cost far more than it bought:

      * `BeginInvoke()` returns a `PowerShellAsyncResult`, which has NO `.Runspace` property.
        The wait loop read `$Job.Runspace.IsCompleted`, so it evaluated to an empty collection
        and never waited — `EndInvoke` then raced its own work (AB#5629, and again in a second
        un-fixed copy in AB#5633).
      * Each runspace RE-IMPORTED the module, which is why module-scope StrictMode leaked back
        in and the opt-out had to be applied at 17 separate entry points instead of 5.
      * The whole estate was serialised to JSON and rehydrated once per category job.
      * An exception inside a runspace surfaced at `EndInvoke` time, detached from the
        collector that caused it, so a single bad collector took out its entire category.

    Running a collector in-process removes all four. A collector is a pure function of the
    resource set — it filters `$Resources` by type and shapes rows — so there was never any
    concurrency requirement to honour.

    ERROR CONTAINMENT IS THE POINT. A collector that throws is reported and skipped; every
    other collector still runs and the report is still produced. Under the old pipeline the
    same throw silently emptied a category, or aborted the batch.

.PARAMETER Collector
    A descriptor from Get-ScoutCollector.

.PARAMETER Context
    Hashtable supplying the collector's ten positional parameters. Recognised keys:
    ScriptRoot, Subscriptions, InTag, Resources, Retirements, Task, File, SmaResources,
    TableStyle, Unsupported. Any key omitted is passed as $null.

.OUTPUTS
    PSCustomObject with Name, FolderCategory, Success, Rows, Error and Duration.

.NOTES
    Tracks ADO AB#5649 (Epic AB#5638).

    Collectors are invoked with StrictMode OFF. The 176 files under InventoryModules were
    written for a runspace where StrictMode never applied, and turning it on for them is a
    separate, tested piece of work with recorded live payload fixtures (AB#5667). Doing both
    at once would be a flag day. StrictMode is dynamically scoped, so the opt-out here covers
    the collector's call tree and nothing else.
#>
function Invoke-ScoutCollector {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [PSCustomObject]$Collector,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Context
    )

    Set-StrictMode -Off

    # Match the runspace default the collectors were written against. Under the module's
    # 'Stop' preference a merely non-terminating error would discard rows the collector had
    # already produced.
    $ErrorActionPreference = 'Continue'

    $Started = Get-Date
    $Rows    = @()
    $Failure = $null

    try {
        $Source = [System.IO.File]::ReadAllText($Collector.Path)
        $Block  = [ScriptBlock]::Create($Source)

        # The collector parameter block, in order:
        #   $SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources,
        #   $TableStyle, $Unsupported
        #
        # Built by INDEX into a fixed-size array, deliberately. An array subexpression --
        # @( $a; $b; $c ) -- takes its elements from the output stream, and an empty collection
        # contributes NOTHING to that stream rather than contributing itself. Several of these
        # values are legitimately @() (a tenant with no retirements, no unsupported-version
        # list), so the array silently came back short and every argument after the first empty
        # one shifted down a position -- $Task landed in $Retirements and the collectors'
        # `If ($Task -eq 'Processing')` guard never fired, so every collector returned nothing.
        #
        # Same root cause as AB#5633: an empty collection is not a value, it is an absence.
        # Indexed assignment cannot flatten, so the arity is guaranteed.
        $Arguments = [object[]]::new(10)
        $Arguments[0] = $Context['ScriptRoot']
        $Arguments[1] = $Context['Subscriptions']
        $Arguments[2] = $Context['InTag']
        $Arguments[3] = $Context['Resources']
        $Arguments[4] = $Context['Retirements']
        $Arguments[5] = $Context['Task']
        $Arguments[6] = $Context['File']
        $Arguments[7] = $Context['SmaResources']
        $Arguments[8] = $Context['TableStyle']
        $Arguments[9] = $Context['Unsupported']

        $Rows = @(& $Block @Arguments)
    }
    catch {
        $Failure = $_
        $Rows    = @()

        Write-Warning ("[AzureScout] Collector '{0}' ({1}) failed and was skipped: {2}" -f
            $Collector.Name, $Collector.FolderCategory, $_.Exception.Message)

        # Deliberately WARN, not Write-AZSCLogError: that helper is the run-failed reporter and
        # opens with a "RUN FAILED" banner. A contained collector skip is not a failed run.
        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level 'WARN' -Message ("Collector {0}/{1} failed and was skipped: {2}" -f
                $Collector.FolderCategory, $Collector.Name, $_.Exception.Message)
            Write-AZSCLog -Level 'WARN' -Message ('    at {0}:{1}' -f
                $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber)
        }
    }

    [PSCustomObject]@{
        Name           = $Collector.Name
        FolderCategory = $Collector.FolderCategory
        Success        = ($null -eq $Failure)
        Rows           = $Rows
        Error          = $Failure
        Duration       = (Get-Date) - $Started
    }
}
