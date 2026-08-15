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
        [string]$DefinitionRoot,

        [Parameter()]
        [AllowNull()]
        [object[]]$CollectionHealth = @()

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
            CollectorRows    = @()
            RowCountPath     = $null
            EmptyCount       = 0
            PartialCount     = 0
            UnavailableCount = 0
            CollectionHealthPath = $null
            DiscoveryPath    = $null
            DiscoveryStatus  = 'Unavailable'
            DiscoverySummary = $null
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

    # A 50k-row estate used to be scanned once for every one of the 285 collectors before a
    # collector processed even one matching row. Build a stable, case-insensitive type index once.
    # Lists preserve original order within a type; an ordinal map lets multi-type SinglePass
    # collectors restore the original interleaved order without another full-estate scan.
    $resourceTypeIndex = @{}
    $resourceOrdinals = [System.Collections.Generic.Dictionary[object, int]]::new(
        [System.Collections.Generic.ReferenceEqualityComparer]::Instance
    )
    $resourceOrdinal = 0
    foreach ($resource in @($Resources)) {
        if ($null -eq $resource) { continue }
        $resourceOrdinals[$resource] = $resourceOrdinal
        $resourceOrdinal++
        $typeProperty = [System.Management.Automation.PSObject]::AsPSObject($resource).PSObject.Properties['TYPE']
        if ($null -eq $typeProperty -or [string]::IsNullOrWhiteSpace([string]$typeProperty.Value)) { continue }
        $typeKey = ([string]$typeProperty.Value).ToLowerInvariant()
        if (-not $resourceTypeIndex.ContainsKey($typeKey)) {
            $resourceTypeIndex[$typeKey] = [System.Collections.Generic.List[object]]::new()
        }
        $resourceTypeIndex[$typeKey].Add($resource)
    }
    $Context['ResourceTypeIndex'] = $resourceTypeIndex
    $Context['ResourceOrdinals'] = $resourceOrdinals

    $CachePath  = Join-Path $DefaultPath 'ReportCache'
    # AB#6766 -- the per-collector row counts, retained. Before this, the only evidence of what
    # each collector produced was the ReportCache, and Invoke-AzureScout runs
    # Clear-AZSCCacheFolder unconditionally at the end of every run, so nothing survived to
    # compare one run against another. This list is written to the RUN folder, one level above
    # the cache, which that function does not touch.
    $RowCounts  = [System.Collections.Generic.List[object]]::new()
    $Failures   = [System.Collections.Generic.List[object]]::new()
    $Skipped    = [System.Collections.Generic.List[object]]::new()
    $CacheFiles = [System.Collections.Generic.List[object]]::new()
    $DiscoveryPath = $null
    $DiscoveryStatus = 'Unavailable'
    $DiscoverySummary = $null
    $Done       = 0

    # Every shipped collector is declarative in v3. The result mode is kept as a checked runtime
    # invariant so a future alternate executor cannot be counted as a successful release run.
    $Declarative = 0

    $healthByType = @{}
    $healthPatterns = [System.Collections.Generic.List[object]]::new()
    $healthByCollector = @{}
    foreach ($health in @($CollectionHealth)) {
        if ($null -eq $health) { continue }
        $collectorsProperty = $health.PSObject.Properties['Collectors']
        if ($collectorsProperty) {
            foreach ($collectorKey in @($collectorsProperty.Value)) {
                if ([string]::IsNullOrWhiteSpace([string]$collectorKey)) { continue }
                $key = ([string]$collectorKey).ToLowerInvariant()
                if (-not $healthByCollector.ContainsKey($key)) { $healthByCollector[$key] = [System.Collections.Generic.List[object]]::new() }
                $healthByCollector[$key].Add($health)
            }
            # A source-aware producer has already resolved the exact affected collectors.
            # ResourceTypes remain useful evidence in collection-health.json, but unioning them
            # back into matching here would re-poison collectors that share a type while reading
            # from an independent source. Type matching is retained only for legacy health rows
            # that do not carry the Collectors property at all.
            continue
        }
        $typesProperty = $health.PSObject.Properties['ResourceTypes']
        if (-not $typesProperty) { continue }
        foreach ($type in @($typesProperty.Value)) {
            if ([string]::IsNullOrWhiteSpace([string]$type)) { continue }
            $key = ([string]$type).ToLowerInvariant()
            if ($key.Contains('*') -or $key.Contains('?')) {
                $healthPatterns.Add([pscustomobject]@{ Pattern = $key; Health = $health })
                continue
            }
            if (-not $healthByType.ContainsKey($key)) { $healthByType[$key] = [System.Collections.Generic.List[object]]::new() }
            $healthByType[$key].Add($health)
        }
    }

    # Group by folder category: the cache file is named for the folder, so a category's file is
    # written once, after all of its collectors have run.
    $Groups = $Collectors | Group-Object -Property FolderCategory | Sort-Object Name

    if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
        Write-AZSCLog -Level 'VERBOSE' -Message (
            'Collector processing started: collectors={0}; categories={1}' -f $Total, @($Groups).Count
        )
    }

    foreach ($Group in $Groups) {
        $CategoryName = $Group.Name
        $Bucket       = @{}

        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level 'VERBOSE' -Message (
                'Collector category {0} started: collectors={1}' -f $CategoryName, @($Group.Group).Count
            )
        }

        foreach ($Collector in $Group.Group) {
            $Percent = [math]::Round((($Done / $Total) * 100))
            if (Get-Command -Name 'Write-ScoutProgress' -ErrorAction SilentlyContinue) {
                Write-ScoutProgress -Id 1 -Activity 'Processing inventory' -Status "$Percent% Complete." `
                    -PercentComplete $Percent -CurrentOperation "$CategoryName / $($Collector.Name)"
            }
            else {
                Write-Progress -Id 1 -Activity 'Processing inventory' -Status "$Percent% Complete." `
                    -PercentComplete $Percent -CurrentOperation "$CategoryName / $($Collector.Name)"
            }

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

            # AB#6766. Three verdicts, never two. "0 rows" on its own is the ambiguity the whole
            # audit is about: it can mean the collector broke, or that the tenant genuinely has
            # none of that resource type. A collector that threw is 'Failed' and its zero is
            # explained; one that returned cleanly with no rows is 'Empty', which is a real
            # finding rather than an absence of one.
            $rowCount = @($Result.Rows).Count
            $collectorKey = ('{0}/{1}' -f $Result.FolderCategory, $Result.Name).ToLowerInvariant()
            $collectorHealth = @(@(
                if ($healthByCollector.ContainsKey($collectorKey)) { $healthByCollector[$collectorKey] }
                foreach ($type in @($Result.ResourceTypes)) {
                    $key = ([string]$type).ToLowerInvariant()
                    if ($healthByType.ContainsKey($key)) { $healthByType[$key] }
                    foreach ($patternEntry in $healthPatterns) {
                        if ($key -like $patternEntry.Pattern) { $patternEntry.Health }
                    }
                }
            ) | Sort-Object Dataset, Status, Reason -Unique)
            $availability = if ($collectorHealth.Count -eq 0) { 'Complete' }
            elseif ($rowCount -gt 0) { 'Partial' }
            elseif (@($collectorHealth | Where-Object Status -eq 'NotAssessed').Count -gt 0) { 'NotAssessed' }
            else { 'Unavailable' }
            $verdict  = if (-not $Result.Success) { 'Failed' }
            elseif ($rowCount -gt 0) { 'Rows' }
            elseif ($availability -eq 'NotAssessed') { 'NotAssessed' }
            elseif ($availability -eq 'Unavailable') { 'Unavailable' }
            else { 'Empty' }
            $RowCounts.Add([PSCustomObject]@{
                Category  = $Result.FolderCategory
                Collector = $Result.Name
                Rows      = $rowCount
                Verdict   = $verdict
                Availability = $availability
                AvailabilityReason = if ($collectorHealth.Count -gt 0) { (@($collectorHealth | ForEach-Object Reason | Where-Object { $_ }) -join '; ') } else { $null }
                Error     = if (-not $Result.Success) { [string] $Result.Error.Exception.Message } else { $null }
            })

            $Bucket[$Result.Name] = $Result.Rows
            $Done++
        }

        if ($PSCmdlet.ShouldProcess($CategoryName, 'Write inventory cache')) {
            $CacheResult = Write-ScoutCacheFile -Category $CategoryName -Data $Bucket -CachePath $CachePath
            $CacheFiles.Add($CacheResult)
            if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
                Write-AZSCLog -Level 'VERBOSE' -Message (
                    'Collector category {0} finished: rows={1}; cacheWritten={2}' -f
                        $CategoryName, $CacheResult.RowCount, $CacheResult.Written
                )
            }
        }

        # Release the category's rows before the next one is collected. The old pipeline needed
        # this because it held every category's JSON in memory at once; keeping it costs
        # nothing and holds peak memory to a single category on a large estate.
        $Bucket = $null
        if (Get-Command -Name 'Clear-AZSCMemory' -ErrorAction SilentlyContinue) { Clear-AZSCMemory }
    }

    # AB#7366 -- the specialized collector cache can no longer be the completeness boundary.
    # Build one generic row for EVERY discovered resource, retain its control-plane properties,
    # correlate collection-health gaps, and extract ARM-id relationships. A new Azure type that
    # has no purpose-built collector therefore remains visible as GenericOnly instead of silently
    # disappearing from the report.
    try {
        if (-not (Get-Command Get-ScoutResourceCompleteness -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'Get-ScoutResourceCompleteness.ps1')
        }
        $Discovery = Get-ScoutResourceCompleteness -Resources @($Resources) `
            -CollectionHealth @($CollectionHealth) -Collectors @($Collectors) -DefinitionRoot $DefinitionRoot
        $DiscoveryPath = Join-Path $CachePath 'Discovery.json'
        if ($PSCmdlet.ShouldProcess($DiscoveryPath, 'Write universal discovery index')) {
            if (-not (Test-Path -LiteralPath $CachePath)) {
                $null = New-Item -Path $CachePath -ItemType Directory -Force
            }
            if (-not (Get-Command Write-ScoutJsonStream -ErrorAction SilentlyContinue)) {
                . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Write-ScoutJsonStream.ps1')
            }
            Write-ScoutJsonStream -InputObject $Discovery -Path $DiscoveryPath -Depth 100 | Out-Null
            $DiscoveryStatus = if (($Discovery.Summary.Partial + $Discovery.Summary.Unavailable) -gt 0) { 'Partial' } else { 'Complete' }
            $DiscoverySummary = $Discovery.Summary
            $CacheFiles.Add([pscustomobject]@{
                Category = 'Discovery'
                Path     = $DiscoveryPath
                RowCount = $Discovery.Summary.Resources
                Written  = $true
            })
        }
    }
    catch {
        $DiscoveryStatus = 'Unavailable'
        Write-Warning "[AzureScout] Could not build the universal discovery index: $($_.Exception.Message)"
    }

    if (Get-Command -Name 'Write-ScoutProgress' -ErrorAction SilentlyContinue) {
        Write-ScoutProgress -Id 1 -Activity 'Processing inventory' -Status '100% Complete.' -Completed
    }
    else {
        Write-Progress -Id 1 -Activity 'Processing inventory' -Status '100% Complete.' -Completed
    }

    # AB#6766 -- write the row-count artifact before anything can clear the cache. Sorted by
    # category then collector so two runs diff cleanly; a hash-ordered file would show every
    # line as changed. Failing to write it must not cost the caller their report, so it is
    # contained.
    $RowCountPath = Join-Path $DefaultPath 'collector-rowcounts.json'
    $CollectionHealthPath = Join-Path $DefaultPath 'collection-health.json'
    $OrderedCounts = @($RowCounts | Sort-Object Category, Collector)
    if ($PSCmdlet.ShouldProcess($RowCountPath, 'Write collector row counts')) {
        try {
            [PSCustomObject]@{
                Schema     = 'azure-scout/collector-rowcounts/v1'
                GeneratedAt = $Started.ToString('o')
                Totals     = [PSCustomObject]@{
                    Collectors = $Total
                    WithRows   = @($OrderedCounts | Where-Object Verdict -eq 'Rows').Count
                    Empty      = @($OrderedCounts | Where-Object Verdict -eq 'Empty').Count
                    Partial    = @($OrderedCounts | Where-Object Availability -eq 'Partial').Count
                    Unavailable = @($OrderedCounts | Where-Object Verdict -eq 'Unavailable').Count
                    NotAssessed = @($OrderedCounts | Where-Object Verdict -eq 'NotAssessed').Count
                    Failed     = @($OrderedCounts | Where-Object Verdict -eq 'Failed').Count
                    Rows       = (@($OrderedCounts | ForEach-Object { $_.Rows }) | Measure-Object -Sum).Sum
                }
                Collectors = $OrderedCounts
            } | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $RowCountPath -Encoding utf8
        }
        catch {
            Write-Warning "[AzureScout] Could not write the collector row-count artifact to '$RowCountPath': $($_.Exception.Message)"
            $RowCountPath = $null
        }
    }

    if ($PSCmdlet.ShouldProcess($CollectionHealthPath, 'Write collection health')) {
        try {
            [pscustomobject]@{
                Schema      = 'azure-scout/collection-health/v1'
                GeneratedAt = $Started.ToString('o')
                Overall     = if (@($CollectionHealth).Count -gt 0) { 'Partial' } else { 'Complete' }
                Datasets    = @($CollectionHealth)
            } | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $CollectionHealthPath -Encoding utf8
        }
        catch {
            Write-Warning "[AzureScout] Could not write collection health to '$CollectionHealthPath': $($_.Exception.Message)"
            $CollectionHealthPath = $null
        }
    }

    $Summary = [PSCustomObject]@{
        CollectorCount   = $Total
        DeclarativeCount = $Declarative
        FailureCount     = $Failures.Count
        Failures         = @($Failures)
        SkippedCount     = $Skipped.Count
        Skipped          = @($Skipped)
        Categories       = @($Groups | ForEach-Object { $_.Name })
        CacheFiles       = @($CacheFiles)
        # AB#6766
        CollectorRows    = $OrderedCounts
        RowCountPath     = $RowCountPath
        EmptyCount       = @($OrderedCounts | Where-Object Verdict -eq 'Empty').Count
        PartialCount     = @($OrderedCounts | Where-Object Availability -eq 'Partial').Count
        UnavailableCount = @($OrderedCounts | Where-Object { $_.Verdict -in @('Unavailable', 'NotAssessed') }).Count
        CollectionHealthPath = $CollectionHealthPath
        DiscoveryPath    = $DiscoveryPath
        DiscoveryStatus  = $DiscoveryStatus
        DiscoverySummary = $DiscoverySummary
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
                # AB#6766 -- an empty collector is a reportable outcome, not a silent one.
                'Collectors empty'  = $Summary.EmptyCount
                'Collectors partial' = $Summary.PartialCount
                'Collectors unavailable' = $Summary.UnavailableCount
                'Collection health' = $Summary.CollectionHealthPath
                'Discovery completeness' = $Summary.DiscoveryStatus
                'Discovery index'  = $Summary.DiscoveryPath
                'Row counts'        = $Summary.RowCountPath
                'Categories cached' = @($CacheFiles | Where-Object { $_.Written }).Count
                'Rows cached'       = (@($CacheFiles | ForEach-Object { $_.RowCount }) | Measure-Object -Sum).Sum
            }
    }

    $Summary
}
