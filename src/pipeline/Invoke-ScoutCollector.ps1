#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Is the declarative cutover switched off for this process? (AB#5656)

.DESCRIPTION
    THE KILL SWITCH. Setting the environment variable
    `AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS` to 1/true/yes/on forces EVERY collector down the
    hand-written `.ps1` path, whether or not it has a `.psd1` definition — restoring, exactly,
    the execution path of every release up to and including v2.9.0.

    An environment variable rather than only a parameter, because the failure it exists for is
    a customer mid-run discovering that one bad definition has emptied a worksheet. An env var
    needs no new argument threaded through Invoke-AzureScout -> Start-AZSCProcessOrchestration
    -> Invoke-ScoutProcessing, so it works on the version the customer already has installed:

        $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = '1'
        Invoke-AzureScout ...

    Only the four affirmative spellings switch it on. An unset variable, an empty one, '0' and
    'false' all leave the cutover ENABLED — a truthiness test on the raw string would have made
    `= '0'` mean "on", which is the opposite of what anyone typing it intends.

.OUTPUTS
    [bool] — $true when the cutover is forced off.

.NOTES
    Tracks ADO AB#5656 (Epic AB#5638).
#>
function Test-ScoutDeclarativeCutoverDisabled {
    [CmdletBinding()]
    [OutputType([bool])]
    Param()

    $Value = $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return (@('1', 'true', 'yes', 'on') -contains $Value.Trim().ToLowerInvariant())
}

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

.PARAMETER Imperative
    Force the hand-written `.ps1` even when the descriptor carries a declarative definition.

    This is the per-call form of the kill switch (see `Test-ScoutDeclarativeCutoverDisabled`),
    and it is also what the equivalence proof passes to obtain its REFERENCE rows: without an
    explicit opt-out, `tests/DeclarativeCollectorEquivalence.Tests.ps1` would — after the
    cutover — run the interpreter on both sides of its own comparison and pass vacuously.

.OUTPUTS
    PSCustomObject with Name, FolderCategory, Success, Rows, Mode, Error and Duration.

    `Mode` is 'Declarative', 'Imperative' or 'ImperativeFallback' — the observable that makes
    the cutover testable. Without it, a routing regression that silently sent every collector
    back to its `.ps1` would produce identical rows (that is the entire point of the equivalence
    proof) and therefore no failing test.

.NOTES
    Tracks ADO AB#5649 and AB#5656 (Epic AB#5638).

    THE CUTOVER (AB#5656). A collector that has a `.psd1` definition is executed by
    `Invoke-ScoutDeclarativeCollector`; one that does not keeps running as a hand-written
    `.ps1`, exactly as before. The routing key is `HasDeclarativeDefinition` on the descriptor
    `Get-ScoutCollector` already produces — no second walk of `manifests/collectors`, because
    two walkers over the same estate is how the v1 engine's two copies of collector discovery
    drifted apart in the first place (ADR §2.4).

    A descriptor with no `HasDeclarativeDefinition` property at all routes imperative. That is
    deliberate rather than incidental: hand-built descriptors exist (the equivalence harness,
    Invoke-CollectorAudit) and the safe reading of "I do not know whether a definition exists"
    is the path that has shipped in every release.

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
        [hashtable]$Context,

        [Parameter()]
        [switch]$Imperative
    )

    Set-StrictMode -Off

    # Match the runspace default the collectors were written against. Under the module's
    # 'Stop' preference a merely non-terminating error would discard rows the collector had
    # already produced.
    $ErrorActionPreference = 'Continue'

    $Started = Get-Date
    $Rows    = @()
    $Failure = $null

    # --- Routing (AB#5656) -------------------------------------------------------------------
    #
    # `$Collector.HasDeclarativeDefinition` on a descriptor that lacks the property would be
    # $null here (StrictMode is off), which reads as false — but relying on that would make the
    # imperative default an accident of a suppressed error. Test for the property.
    $HasDefinition = (@($Collector.PSObject.Properties.Name) -contains 'HasDeclarativeDefinition') -and
                     [bool]$Collector.HasDeclarativeDefinition -and
                     -not [string]::IsNullOrWhiteSpace([string]$Collector.DefinitionPath)

    $Mode       = 'Imperative'
    $Definition = $null

    if ($HasDefinition -and -not $Imperative -and -not (Test-ScoutDeclarativeCutoverDisabled)) {
        try {
            $Definition = Get-ScoutCollectorDefinition -Path $Collector.DefinitionPath
            $Mode       = 'Declarative'
        }
        catch {
            # A definition that fails SCHEMA VALIDATION is a repo defect, not a tenant-data
            # problem: tests/CollectorDefinitionSchema.Tests.ps1 and the equivalence suite both
            # load every definition in CI, so this cannot reach a release without the suite
            # going red. If one somehow does, running the perfectly good `.ps1` sitting beside
            # it is strictly better than losing the worksheet — so this ONE case falls back, and
            # says so loudly.
            #
            # An EXECUTION failure below deliberately does NOT fall back. The two paths are
            # proven equivalent, so data the interpreter chokes on is data the `.ps1` would very
            # likely choke on too; retrying it would turn one reported failure into two, and a
            # silent retry is how a real defect stays invisible.
            $Mode = 'ImperativeFallback'
            Write-Warning ("[AzureScout] Collector '{0}' ({1}) has an INVALID declarative definition and fell back to the imperative script: {2}" -f
                $Collector.Name, $Collector.FolderCategory, $_.Exception.Message)
            if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
                Write-AZSCLog -Level 'WARN' -Message ("Collector {0}/{1} declarative definition failed to load; using the imperative script: {2}" -f
                    $Collector.FolderCategory, $Collector.Name, $_.Exception.Message)
            }
        }
    }

    try {
        if ($Mode -eq 'Declarative') {
            # The `.ps1` is not read and not executed on this path. That is the cutover, and
            # tests/DeclarativeCollectorCutover.Tests.ps1 proves it by pairing a definition with
            # a `.ps1` that throws on sight.
            #
            # Inside the SAME try as the imperative branch, deliberately: a collector's failure
            # must stay contained however it was executed. An interpreter that throws on one
            # tenant's data must not be able to abort a run that a hand-written collector's throw
            # would only have cost a worksheet.
            $Rows = @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $Context)
        }
        else {
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
    }
    catch {
        $Failure = $_
        $Rows    = @()

        Write-Warning ("[AzureScout] Collector '{0}' ({1}, {2}) failed and was skipped: {3}" -f
            $Collector.Name, $Collector.FolderCategory, $Mode, $_.Exception.Message)

        # Deliberately WARN, not Write-AZSCLogError: that helper is the run-failed reporter and
        # opens with a "RUN FAILED" banner. A contained collector skip is not a failed run.
        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level 'WARN' -Message ("Collector {0}/{1} ({2}) failed and was skipped: {3}" -f
                $Collector.FolderCategory, $Collector.Name, $Mode, $_.Exception.Message)
            Write-AZSCLog -Level 'WARN' -Message ('    at {0}:{1}' -f
                $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber)
        }
    }

    [PSCustomObject]@{
        Name           = $Collector.Name
        FolderCategory = $Collector.FolderCategory
        Success        = ($null -eq $Failure)
        Rows           = $Rows
        Mode           = $Mode
        Error          = $Failure
        Duration       = (Get-Date) - $Started
    }
}
