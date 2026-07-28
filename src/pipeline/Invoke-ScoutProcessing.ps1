#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Run every inventory collector and write the report cache — deterministically (AB#5649).

.DESCRIPTION
    The single replacement for the v1 processing pipeline: `Start-AZSCProcessJob`,
    `Start-AZSCAutProcessJob`, `Wait-AZSCJob` and `Build-AZSCCacheFiles`. Those four
    coordinated background jobs, nested runspaces, batch waits and job harvesting, and every
    defect in the v2.5.x wave lived in that coordination rather than in the collectors:

      | Old mechanism                          | Failure it produced                          |
      |----------------------------------------|----------------------------------------------|
      | Start-Job, asynchronous                 | NotStarted jobs excluded from the wait, then |
      |                                         | harvested empty and deleted (AB#5629)        |
      | $Job.Runspace.IsCompleted               | no-op wait; EndInvoke raced its own work     |
      | Start-Job re-imports the module         | StrictMode leaked back in; 17 opt-out sites  |
      | Get-Job ordering                        | run-to-run variation in the same tenant      |
      | Receive-Job + Remove-Job                | a slow category was destroyed, not reported  |

    None of that machinery is present here. Collectors are pure functions of the resource set,
    so they run in-process, in a fixed order, one after another. Identical inputs produce an
    identical report cache — which is the property the old pipeline could not offer.

    Determinism does not come at the cost of resilience: each collector's failure is contained
    by Invoke-ScoutCollector, so one bad collector no longer empties its category or aborts
    the batch. The run reports what failed instead of silently shipping a thinner report.

    The automation path collapses into this one too. It existed only because Start-Job was
    unavailable in some hosts and Start-ThreadJob was substituted; with no jobs at all, regular
    and automation runs execute the same code, so they can no longer drift apart the way the
    two discovery implementations had.

.PARAMETER Resources
    The full resource set from the extraction phase. Passed to collectors as-is — notably NOT
    serialised to JSON and back, which the old pipeline did once per category job.

.PARAMETER DefaultPath
    Run folder. Cache files are written to its ReportCache subdirectory.

.PARAMETER DefinitionRoot
    Declarative definition tree (`manifests/collectors`). Defaults, via Get-ScoutCollector, to
    the one shipped with the module. Present so a fixture tree can supply its own definitions.

.OUTPUTS
    PSCustomObject summarising the run: collectors executed, how many ran declaratively,
    failures, categories cached.

.NOTES
    Tracks ADO AB#5649 and AB#5656 (Epic AB#5638).

    THE CUTOVER (AB#5656) happens one level down, in Invoke-ScoutCollector, and this function is
    unchanged in structure because of it: a collector is still discovered once, run once, and
    contained once. The definition is the implementation and its committed golden contract is
    the release evidence.
#>
function Invoke-ScoutProcessing {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter()]
        [AllowNull()]
        $Resources,

        [Parameter()]
        [AllowNull()]
        $Retirements,

        [Parameter()]
        [AllowNull()]
        $Subscriptions,

        [Parameter(Mandatory)]
        [string]$DefaultPath,

        [Parameter()]
        [AllowNull()]
        $InTag,

        [Parameter()]
        [AllowNull()]
        $Unsupported,

        [Parameter()]
        [AllowNull()]
        [string[]]$Category = @('All'),

        [Parameter()]
        [string]$InventoryRoot,

        [Parameter()]
        [AllowNull()]
        [string]$DefinitionRoot

    )

    $Started = Get-Date

    if (-not $DefinitionRoot) {
        $ModuleRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $DefinitionRoot = Join-Path $ModuleRoot 'manifests' 'collectors'
    }

    # The v3 runtime reads the complete declarative catalog.  InventoryRoot is retained only
    # for isolated legacy-fixture tests while the source tree is being removed; it is never
    # inferred from Modules/.
    if ($InventoryRoot) {
        $Collectors = @(Get-ScoutCollector -InventoryRoot $InventoryRoot -Category $Category -DefinitionRoot $DefinitionRoot)
    } else {
        $Collectors = @(Get-ScoutCollector -Category $Category -DefinitionRoot $DefinitionRoot)
    }
    $Total      = $Collectors.Count

    if ($Total -eq 0) {
        Write-Warning "[AzureScout] No inventory collectors matched the requested categories."
        # Same property set as the normal return below, deliberately. A caller reading
        # .SkippedCount on this path would otherwise throw under StrictMode -- a summary object
        # whose shape depends on which branch produced it is the same trap that produced the
        # v2.5.3 crash wave.
        return [PSCustomObject]@{
            CollectorCount   = 0
            DeclarativeCount = 0
            FailureCount     = 0
            Failures         = @()
            SkippedCount     = 0
            Skipped          = @()
            Categories       = @()
            CacheFiles       = @()
            Duration         = (Get-Date) - $Started
        }
    }

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + "Running $Total collectors in-process.")

    $Context = @{
        ScriptRoot    = $DefinitionRoot
        Subscriptions = $Subscriptions
        InTag         = $InTag
        Resources     = $Resources
        Retirements   = $Retirements
        Task          = 'Processing'
        File          = $null
        SmaResources  = $null
        TableStyle    = $null
        Unsupported   = $Unsupported
    }

    $CachePath  = Join-Path $DefaultPath 'ReportCache'
    $Failures   = [System.Collections.Generic.List[object]]::new()
    $Skipped    = [System.Collections.Generic.List[object]]::new()
    $CacheFiles = [System.Collections.Generic.List[object]]::new()
    $Done       = 0

    # Every shipped collector is declarative in v3. The result mode is kept as a checked runtime
    # invariant so a future alternate executor cannot be counted as a successful release run.
    $Declarative = 0

    # Group by folder category: the cache file is named for the folder, so a category's file is
    # written once, after all of its collectors have run.
    $Groups = $Collectors | Group-Object -Property FolderCategory | Sort-Object Name

    foreach ($Group in $Groups) {
        $CategoryName = $Group.Name
        $Bucket       = @{}

        foreach ($Collector in $Group.Group) {
            $Percent = [math]::Round((($Done / $Total) * 100))
            Write-Progress -Id 1 -Activity 'Processing inventory' -Status "$Percent% Complete." `
                -PercentComplete $Percent -CurrentOperation "$CategoryName / $($Collector.Name)"

            $Result = Invoke-ScoutCollector -Collector $Collector -Context $Context

            if ($Result.Mode -ne 'Declarative') { throw "Collector '$($Collector.FolderCategory)/$($Collector.Name)' returned unsupported execution mode '$($Result.Mode)'." }
            $Declarative++

            if (-not $Result.Success) {
                $Failures.Add([PSCustomObject]@{
                    Collector = $Result.Name
                    Category  = $Result.FolderCategory
                    Message   = $Result.Error.Exception.Message
                })
            }

            $Bucket[$Result.Name] = $Result.Rows
            $Done++
        }

        if ($PSCmdlet.ShouldProcess($CategoryName, 'Write inventory cache')) {
            $CacheFiles.Add((Write-ScoutCacheFile -Category $CategoryName -Data $Bucket -CachePath $CachePath))
        }

        # Release the category's rows before the next one is collected. The old pipeline needed
        # this because it held every category's JSON in memory at once; keeping it costs
        # nothing and holds peak memory to a single category on a large estate.
        $Bucket = $null
        if (Get-Command -Name 'Clear-AZSCMemory' -ErrorAction SilentlyContinue) { Clear-AZSCMemory }
    }

    Write-Progress -Id 1 -Activity 'Processing inventory' -Status '100% Complete.' -Completed

    $Summary = [PSCustomObject]@{
        CollectorCount   = $Total
        DeclarativeCount = $Declarative
        FailureCount     = $Failures.Count
        Failures         = @($Failures)
        SkippedCount     = $Skipped.Count
        Skipped          = @($Skipped)
        Categories       = @($Groups | ForEach-Object { $_.Name })
        CacheFiles       = @($CacheFiles)
        Duration         = (Get-Date) - $Started
    }

    if ($Summary.FailureCount -gt 0) {
        Write-Warning ("[AzureScout] {0} of {1} collectors failed and were skipped: {2}" -f
            $Summary.FailureCount, $Total, (($Summary.Failures | ForEach-Object { $_.Category + '/' + $_.Collector }) -join ', '))
    }

    if (Get-Command -Name 'Write-AZSCLogPhase' -ErrorAction SilentlyContinue) {
        Write-AZSCLogPhase -Name 'Processing (deterministic pipeline)' `
            -Elapsed $Summary.Duration.ToString('hh\:mm\:ss') `
            -Detail @{
                'Collectors run'    = $Total - $Summary.SkippedCount
                'Collectors declarative' = $Summary.DeclarativeCount
                'Collectors failed' = $Summary.FailureCount
                'Collectors skipped' = $Summary.SkippedCount
                'Categories cached' = @($CacheFiles | Where-Object { $_.Written }).Count
                'Rows cached'       = (@($CacheFiles | ForEach-Object { $_.RowCount }) | Measure-Object -Sum).Sum
            }
    }

    $Summary
}
