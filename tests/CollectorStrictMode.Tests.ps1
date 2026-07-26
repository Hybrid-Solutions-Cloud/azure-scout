#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5667 — do the 176 InventoryModules collectors survive Set-StrictMode -Version Latest?

    Invoke-ScoutCollector currently calls `Set-StrictMode -Off` before running every collector
    (see its own header note) precisely because nobody had answered this question against real
    payload shapes. This file is that answer, replayed offline from captured + hand-authored
    fixtures so it needs no Azure connection to run.

    THREE DISTINCT DEFECT CLASSES showed up, not one:

      1. Member ENUMERATION over an empty collection throws when the enumeration yields
         nothing at all (see StrictModeMemberEnumeration.Tests.ps1 for the extraction-phase
         version of this same rule) -- e.g. `$Resources.Where(...).properties` when the
         Where-Object match is empty, or `$data.storageProfile.dataDisks.managedDisk.id` when
         a VM genuinely has zero data disks (the common case, not the exception).
      2. A plain property read on a single object that genuinely lacks that property throws --
         a bare `$null` VALUE is fine (the key exists), an ABSENT key is not. `$data.timeCreated`
         throws when the API response omits the field, which older API versions and some
         resource kinds do.
      3. An out-of-range ARRAY INDEX throws instead of silently returning $null. Roughly thirty
         collectors do `<idField>.split('/')[8]` (or `[7]`) assuming the standard nine-segment
         `/subscriptions/{s}/resourceGroups/{rg}/providers/{Namespace}/{type}/{name}` shape; a
         subscription-scoped id (a Defender/Security assessment with no resource target, or a
         short `managedBy`) has fewer segments and the fixed index is out of range.

    Fixtures live in tests/fixtures/:
      * captured-*.json          -- Export-ScoutFixture.ps1's anonymised capture of whatever the
                                     signed-in tenant actually contains (real shapes, whatever
                                     breadth of resource TYPES that tenant happens to have).
      * edge-case-*.json         -- hand-authored shapes a live capture may not contain: the
                                     three defect classes above, deliberately reproduced.

    edge-case-mixed-resources-missing-fields.json is loaded but NOT merged into the shared
    $Resources every collector runs against -- see its own "_comment" field and the dedicated
    Describe block near the end of this file for why (a single element missing the TYPE
    property fails the very first line of every one of the 176 collectors, which would swamp
    every other finding rather than add one of its own).

    THE SUITE STAYS GREEN. tests/fixtures/CollectorStrictMode.baseline.json is the list of
    collectors known to still fail under StrictMode as of this commit. A collector already in
    the baseline failing is expected and does not fail this suite; a collector NOT in the
    baseline failing is a NEW regression and does. Removing an entry from the baseline (because
    someone fixed that collector) tightens the gate for everyone after them.

    THE BASELINE IS A MEASUREMENT, NOT A WISH. It currently holds 23 of the 174 'Standard'
    collectors, each with the exact exception that collector throws. It must only ever be
    written from an actual run -- an earlier revision of this file shipped an EMPTY baseline
    while 24 collectors were in fact failing, which made the gate assert nothing at all and
    hid the finding it exists to surface. To refresh it after fixing a collector, run this file
    and take the reported failures; never hand-edit an entry in to make a red run go green.

    WHAT A PASS HERE DOES AND DOES NOT MEAN. It means "this collector did not throw against
    these fixtures". The captured fixtures cover 29 distinct resource types, so a collector
    whose type is not among them filters to zero rows and passes without executing any of its
    body. A green result for such a collector is real but weak; only the collectors whose types
    the fixtures do contain are meaningfully exercised. Widening the capture widens the gate.

    That distinction is not theoretical. The first version of these fixtures was written
    double-wrapped (`[[ {...} ]]` instead of `[ {...} ]`), so `@($raw | ConvertFrom-Json)`
    produced a single element holding the row array, every collector's opening
    `Where-Object { $_.TYPE -eq ... }` matched nothing, and 150 of 174 collectors "passed"
    without touching a single captured row. Fixing the nesting changed the failure set
    substantially and moved the failures DEEPER into each collector. If a change to the
    fixtures makes this suite dramatically greener, suspect the fixtures before believing it.

    A NOTE ON SCOPING: Pester v5 runs a file's DISCOVERY phase (collecting the Describe/It tree,
    evaluating every -ForEach argument) and its RUN phase (actually executing BeforeAll/It
    bodies) as two separate passes, the second in a fresh script scope. A `$script:` variable
    assigned at the true top of the file (outside every Describe/BeforeAll) is visible during
    discovery but NOT inside a BeforeAll/It body at run time -- so every value a BeforeAll or It
    body needs is (re)computed INSIDE that BeforeAll, never inherited from top-level code. Only
    the two collector lists below are computed at the top level, because -ForEach is the one
    thing that genuinely needs its data at discovery time.
#>

# ===================================================================
# DISCOVERY-TIME ONLY: collector inventory, needed for -ForEach below.
# ===================================================================
$DiscoveryRepoRoot      = Split-Path -Parent $PSScriptRoot
$DiscoveryInventoryRoot = Join-Path $DiscoveryRepoRoot 'Modules' 'Public' 'InventoryModules'

. (Join-Path $DiscoveryRepoRoot 'src' 'pipeline' 'Get-ScoutCollector.ps1')

# Only the 'Standard' contract is ever invoked by the real pipeline (Invoke-ScoutProcessing
# skips 'Unsupported' collectors and counts them separately) -- mirror that here rather than
# reporting a StrictMode result for two files that never run at all.
$AllCollectors = @(
    Get-ScoutCollector -InventoryRoot $DiscoveryInventoryRoot -Category 'All' |
        Where-Object { $_.Contract -eq 'Standard' } |
        Sort-Object FolderCategory, Name |
        ForEach-Object { @{ Name = $_.Name; Category = $_.FolderCategory; Path = $_.Path } }
)

# A small representative sample used by the "missing TYPE" Describe block further down.
$SampleCollectors = @($AllCollectors | Where-Object { $_.Category -in @('Compute', 'Storage') } | Select-Object -First 5)

Describe 'Inventory collectors run under StrictMode (AB#5667)' {

    BeforeAll {
        $script:RepoRoot      = Split-Path -Parent $PSScriptRoot
        $script:InventoryRoot = Join-Path $script:RepoRoot 'Modules' 'Public' 'InventoryModules'
        $script:FixtureRoot   = Join-Path $script:RepoRoot 'tests' 'fixtures'

        # Recomputed here, not read from the discovery-time $AllCollectors above: a Pester v5
        # BeforeAll runs in a fresh script scope, so a bare top-level variable from discovery
        # would resolve to nothing here (only -ForEach's own argument survives from discovery,
        # because Pester captures that VALUE directly into each generated test's parameters).
        . (Join-Path $script:RepoRoot 'src' 'pipeline' 'Get-ScoutCollector.ps1')
        $script:AllCollectors = @(
            Get-ScoutCollector -InventoryRoot $script:InventoryRoot -Category 'All' |
                Where-Object { $_.Contract -eq 'Standard' } |
                Sort-Object FolderCategory, Name |
                ForEach-Object { @{ Name = $_.Name; Category = $_.FolderCategory; Path = $_.Path } }
        )

        $script:BaselinePath = Join-Path $script:FixtureRoot 'CollectorStrictMode.baseline.json'
        $script:BaselineSet  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if (Test-Path -LiteralPath $script:BaselinePath) {
            foreach ($entry in @(Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json)) {
                [void] $script:BaselineSet.Add("$($entry.Category)/$($entry.Name)")
            }
        }

        function Read-ScoutFixtureFile {
            param([string] $Path)
            if (-not (Test-Path -LiteralPath $Path)) { return @() }
            $raw = Get-Content -LiteralPath $Path -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
            @($raw | ConvertFrom-Json)
        }

        # A few collectors call the module's own logging helper (Write-AZSCLog,
        # Modules/Private/Main/Write-AZTIRunLog.ps1), which requires Start-AZSCRunLog to have
        # initialised a run folder first -- machinery this harness has no need for. Stubbed
        # here (function scope, visible down the call stack the same way Invoke-ScoutCollector's
        # own `Get-Command ... -ErrorAction SilentlyContinue` guards treat it as optional) so a
        # missing dependency does not masquerade as a StrictMode finding.
        function Write-AZSCLog { param([string] $Message, [string] $Level, [string] $Color) }

        # The real, shared helper (Modules/Private/Main/Get-AZSCSafeProperty.ps1) -- collectors
        # increasingly use it for a safe dotted-path read instead of a raw chain that throws
        # under StrictMode when an intermediate segment is genuinely absent (AB#5667). Dot
        # sourced for real here, unlike Write-AZSCLog above, because its behaviour (not just its
        # presence) matters to whether a collector's StrictMode result is trustworthy.
        . (Join-Path $script:RepoRoot 'Modules' 'Private' 'Main' 'Get-AZSCSafeProperty.ps1')
        # Also real, for the same reason -- some collectors compose it with Get-AZSCSafeProperty
        # to walk a chain that passes THROUGH an array (member enumeration), which
        # Get-AZSCSafeProperty alone does not attempt to reproduce.
        . (Join-Path $script:RepoRoot 'Modules' 'Private' 'Main' 'Get-AZTICollectedValue.ps1')

        # The shared, "hostile-but-plausible" resource set every collector below runs against:
        # real captured shapes plus every hand-authored edge case EXCEPT the missing-TYPE row
        # (see the file header and the dedicated Describe block for why that one is separate).
        $script:Resources = @(
            Read-ScoutFixtureFile (Join-Path $script:FixtureRoot 'captured-resources.json')
            Read-ScoutFixtureFile (Join-Path $script:FixtureRoot 'captured-networkresources.json')
            Read-ScoutFixtureFile (Join-Path $script:FixtureRoot 'edge-case-empty-collections.json')
            Read-ScoutFixtureFile (Join-Path $script:FixtureRoot 'edge-case-defender-assessment-subscription-scope.json')
            Read-ScoutFixtureFile (Join-Path $script:FixtureRoot 'edge-case-no-timestamps.json')
        )
        $script:ResourceContainers = Read-ScoutFixtureFile (Join-Path $script:FixtureRoot 'captured-resourcecontainers.json')
        $script:Subscriptions      = Read-ScoutFixtureFile (Join-Path $script:FixtureRoot 'captured-subscriptions.json')
        $script:Retirements        = @()
        $script:Unsupported        = @()

        function Invoke-ScoutCollectorUnderStrictMode {
            <#
            .SYNOPSIS
                Run one collector file exactly the way Invoke-ScoutCollector does -- same 10
                positional arguments, built by INDEX into a fixed-size array so an empty
                $Resources or $Retirements cannot silently shift every later argument down a
                slot -- except with Set-StrictMode -Version Latest instead of -Off.

            .DESCRIPTION
                StrictMode is dynamically scoped: setting it here, immediately before
                `& $Block`, governs the collector's whole call tree without leaking back out
                once this function returns (Invoke-ScoutCollector.ps1's own header note
                documents the same property).
            #>
            param([Parameter(Mandatory)] [hashtable] $Collector)

            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Continue'

            $Failure = $null
            $Rows    = @()
            try {
                $Source = [System.IO.File]::ReadAllText($Collector.Path)
                $Block  = [ScriptBlock]::Create($Source)

                $Arguments = [object[]]::new(10)
                $Arguments[0] = $script:InventoryRoot
                $Arguments[1] = $script:Subscriptions
                $Arguments[2] = $false
                $Arguments[3] = $script:Resources
                $Arguments[4] = $script:Retirements
                $Arguments[5] = 'Processing'
                $Arguments[6] = $null
                $Arguments[7] = $null
                $Arguments[8] = $null
                $Arguments[9] = $script:Unsupported

                $Rows = @(& $Block @Arguments)
            }
            catch {
                $Failure = $_
            }

            [PSCustomObject]@{ Success = ($null -eq $Failure); Error = $Failure; Rows = $Rows }
        }

        # Run every collector exactly ONCE, up front, and let the per-collector Its below read
        # from this cache -- 176 collectors is expensive enough without doubling it for a
        # summary test.
        $script:CollectorResults = @{}
        foreach ($c in $script:AllCollectors) {
            $script:CollectorResults["$($c.Category)/$($c.Name)"] = Invoke-ScoutCollectorUnderStrictMode -Collector $c
        }

        # Running 174 collectors against deliberately hostile fixtures generates hundreds of
        # non-terminating errors, and $Error is GLOBAL and capped at $MaximumErrorCount (256 by
        # default). Left saturated, it silently breaks any later test in the same session that
        # measures an $Error.Count DELTA -- once the cap is reached, adding an error no longer
        # increases the count, so the delta reads 0. tests/Pipeline.NonTerminatingErrors.Tests.ps1
        # does exactly that (it is testing Invoke-ScoutPipeline's own AB#402 delta check), and it
        # fails in a full-suite run purely because this file ran first.
        #
        # Clearing here keeps this file from leaking state into its neighbours. Note that the
        # underlying fragility is in the PRODUCT, not the test: Invoke-ScoutPipeline's
        # count-delta detection has the same blind spot in a real run whose $Error is already
        # saturated. That is out of scope for AB#5667 and is left as a separate finding.
        $Error.Clear()
    }

    It '<Category>/<Name> does not throw a NEW StrictMode failure' -ForEach $AllCollectors {
        $key    = "$Category/$Name"
        $result = $script:CollectorResults[$key]

        if (-not $result.Success -and -not $script:BaselineSet.Contains($key)) {
            $location = if ($result.Error.InvocationInfo) {
                " at $($result.Error.InvocationInfo.ScriptName):$($result.Error.InvocationInfo.ScriptLineNumber)"
            } else { '' }
            throw "NEW StrictMode failure, not covered by CollectorStrictMode.baseline.json: $($result.Error.Exception.Message)$location"
        }

        # A baseline failure is a known, tracked limitation (see the baseline file's own
        # comment) -- it does not fail this test. A collector that passes is, naturally, fine.
        $true | Should -BeTrue
    }

    It 'reports the pass / fail / baseline counts' {
        $total    = $script:AllCollectors.Count
        $failing  = @($script:CollectorResults.Values | Where-Object { -not $_.Success }).Count
        $passing  = $total - $failing

        Write-Host ("[AzureScout] StrictMode collector harness: {0}/{1} pass, {2} fail (baseline covers {3})." -f
            $passing, $total, $failing, $script:BaselineSet.Count)

        # The gate: nothing may fail that the baseline does not already account for. Collectors
        # fixed since the baseline was captured only ever move this number down.
        $failing | Should -BeLessOrEqual $script:BaselineSet.Count
    }
}

Describe 'A single resource missing the TYPE property fails every collector at once (AB#5667)' {

    # This is deliberately its own, small-scale Describe rather than folded into the shared
    # $Resources set above -- see edge-case-mixed-resources-missing-fields.json's own comment.
    # `$Resources | Where-Object { $_.TYPE -eq '<x>' }` -- the very first line of essentially
    # every collector -- reads $_.TYPE by plain member access, not member enumeration. A single
    # element genuinely missing that property throws the moment Where-Object evaluates it,
    # independent of what type is being searched for, so it takes down EVERY collector's first
    # line at once rather than exercising one. That makes it the single highest-leverage
    # StrictMode fix once the -Off opt-out in Invoke-ScoutCollector.ps1 is lifted: one guard
    # (coalesce a missing TYPE to '' before filtering, or filter the malformed row out before
    # handing $Resources to any collector) protects all 176 files in one place, rather than 176
    # individual `$_.PSObject.Properties['TYPE']` guards.

    BeforeAll {
        $script:FixtureRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests' 'fixtures'
        $script:MixedResources = @(
            Get-Content -LiteralPath (Join-Path $script:FixtureRoot 'edge-case-mixed-resources-missing-fields.json') -Raw |
                ConvertFrom-Json
        )
    }

    It 'a row missing TYPE entirely throws out of the basic Where-Object filter under StrictMode' {
        Set-StrictMode -Version Latest
        { $script:MixedResources | Where-Object { $_.TYPE -eq 'microsoft.compute/virtualmachines' } } |
            Should -Throw -ExpectedMessage '*TYPE*cannot be found*'
    }

    It 'a row missing subscriptionId throws only when that specific element is read, not before' {
        Set-StrictMode -Version Latest
        # The filter has to be the GUARDED form. The naive `$_.TYPE -eq ...` is what the previous
        # test proves throws on this fixture, so using it here would make this test fail for that
        # reason and never reach the thing it is actually about.
        $vmRows = $script:MixedResources |
            Where-Object { $_.PSObject.Properties['TYPE'] -and $_.TYPE -eq 'microsoft.compute/virtualmachines' }
        # The filter itself succeeds -- every element here DOES carry TYPE. Reading the ABSENT
        # subscriptionId off the specific element that lacks it is what throws.
        $badRow = $vmRows | Where-Object { $_.name -eq 'vm-no-subscriptionid' }
        { $null = $badRow.subscriptionId } | Should -Throw -ExpectedMessage '*subscriptionId*cannot be found*'
    }

    It '<Category>/<Name> is representative of the class -- confirms the finding is not one file''s quirk' -ForEach $SampleCollectors {
        Set-StrictMode -Version Latest
        $Arguments = [object[]]::new(10)
        $Arguments[3] = $script:MixedResources
        $Arguments[5] = 'Processing'

        # Every collector in the sample is expected to throw on the missing-TYPE row -- this
        # documents the systemic finding, it is not a per-collector regression gate (that is
        # what the Describe block above is for, deliberately excluding this fixture).
        $threw = $false
        try {
            $Source = [System.IO.File]::ReadAllText($Path)
            $Block  = [ScriptBlock]::Create($Source)
            $null = & $Block @Arguments
        } catch { $threw = $true }

        $threw | Should -BeTrue -Because 'a TYPE-less row should fail this collector''s first filter line the same way it fails every other one'
    }
}
