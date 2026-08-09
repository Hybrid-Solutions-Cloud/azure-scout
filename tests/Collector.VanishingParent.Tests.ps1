#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#6845 — a parent resource must not disappear from its worksheet because its child collection
    is absent from the payload.

    THE DEFECT. 43 collectors fan a row out over a child collection: an AKS cluster's agent pools,
    a VNet's subnets, an app service's hostname SSL states. When Azure returns the parent WITHOUT
    that array — a normal sparse response, not an error — the inner `foreach` iterates zero times
    and the collector emits NO ROW AT ALL. The resource exists in Azure and is simply missing from
    the report: no error, no warning, just a plausible smaller estate. It is the one sparse-payload
    class that does not throw, which is why it outlived the AB#6839 and AB#6844 fixes.

    WHY IT NEEDS ITS OWN FILE, AND WHY IT IS NOT SHAPED LIKE THE OTHER SPARSE TESTS.
    `Collector.SparsePayload.Tests.ps1` hand-builds one minimal ARG row per collector. That works
    for a collector whose whole estate is one Resource Graph row, but half the collectors here read
    a SEPARATE collected type — AVD's session hosts, VirtualWAN's hubs, Outages' source event — so
    a hand-built row exercises the collector's resource-type filter rather than its child loop.

    So this suite works the other way round: it takes the collector's REAL fixture, the same estate
    the golden records are captured from, and empties ONE child loop's source expression. Every
    other input stays exactly as shipped, which isolates the change to the single question this bug
    asks — does the parent survive its children going missing?

    That also makes it a guard against REGRESSION BY ADDITION: a new collector with an unguarded
    child loop fails here on the day it is written, without anyone remembering this bug existed.

    NOT EVERY LOOP SHOULD BE GUARDED. Where the ROW IS THE CHILD, a parent-only row is noise rather
    than inventory — see the allow-list below, which carries a written reason per entry and asserts
    the exempt behaviour rather than merely skipping it.

    THE THIRD CATEGORY, AND WHY IT IS CHECKED DIFFERENTLY. 27 of the 50 child loops never vanish
    their parent because their source variable is assigned through a conditional with a non-empty
    fallback — `$Auths = if(...){$data.authorizations}else{'0'}` — so the loop always runs at least
    once and `EmitNullWhenEmpty` would be redundant. Emptying the SOURCE for those simulates a
    state the collector cannot reach, and asserting on it would report a defect that does not
    exist. They are proved the honest way instead: with a hand-built sparse payload in
    `Collector.SparsePayload.Tests.ps1`, where the property really is absent and the sentinel
    really does fire. What this file adds for them is the STRUCTURAL half — that the fallback is
    still there — so deleting a sentinel fails here rather than silently reopening the bug.
#>

BeforeDiscovery {
    $DiscoveryRoot = Split-Path -Parent $PSScriptRoot

    # Loops that MUST NOT emit a parent row, each with the reason it differs in kind from the 20
    # that were fixed. Keyed "Category/Name:LoopVariable". Adding an entry is a design decision
    # about what a worksheet is an inventory OF; it is not a way to quiet a failure.
    $Unguarded = @{
        'General/Quotas:Loc'       = 'the parent is a synthetic AZSC/VM/Quotas envelope rather than an Azure resource, and every column except Resource U is read off $Loc/$Usage, so a parent-only row would be entirely blank'
        'General/Quotas:Usage'     = 'the row IS the usage line; a quota envelope with no usage data has nothing to state'
        'Networking/vNETPeering:4' = 'this worksheet is an inventory of PEERINGS, and a VNet with none belongs on the Virtual Networks worksheet where it already appears, not here with every peering column blank'
    }

    # The reason travels IN the case data. A -ForEach case is built during discovery and read back
    # during run, and a variable set in BeforeDiscovery is not in scope inside an It body.
    $script:LoopCases = @(
        Get-ChildItem -LiteralPath (Join-Path -Path $DiscoveryRoot -ChildPath 'manifests/collectors') -Recurse -Filter *.psd1 |
            Sort-Object FullName |
            ForEach-Object {
                $Raw = Import-PowerShellDataFile $_.FullName
                if (-not $Raw.Contains('AdditionalRowLoops') -or -not $Raw.AdditionalRowLoops) { return }
                $Category = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                $Name = $_.BaseName
                # Every statement the collector runs before the loop body, in one string: the
                # sentinel that saves a parent can be assigned in the setup preamble, the row
                # preamble or an OUTER loop's preamble, and AzureFirewall uses all three.
                $Statements = @(
                    $Raw.SetupPreamble
                    $Raw.Preamble
                    @($Raw.AdditionalRowLoops) | ForEach-Object { $_.Preamble }
                ) -join "`n"

                # Comments are the one thing Import-PowerShellDataFile throws away, and the
                # recorded decision for an unflagged loop lives ONLY in a comment. Read the raw
                # text alongside the parsed data so both halves are visible to the assertions.
                $RawText = Get-Content -LiteralPath $_.FullName -Raw

                $Index = 0
                foreach ($Loop in @($Raw.AdditionalRowLoops)) {
                    $Key = "$Category/$Name`:$($Loop.Variable)"
                    $Emits = $Loop.Contains('EmitNullWhenEmpty') -and [bool]$Loop.EmitNullWhenEmpty

                    # The marker an unflagged loop must carry. `EmitNullWhenEmpty` is itself a
                    # recorded decision — it is data, it survives parsing, and the interpreter
                    # acts on it — so only the loops WITHOUT it need one of these.
                    $Marker = "AB#6845 decision (`$$($Loop.Variable))"
                    $HasDecisionComment = $RawText.Contains($Marker)

                    # A source of the form `$Thing` whose assignment is a conditional. The `if`
                    # must be on the assignment itself, not merely somewhere in the file, which is
                    # why the variable name is anchored into the pattern.
                    $Sentinel = $false
                    if (-not $Emits -and $Loop.Source -match '^\$(\w+)$') {
                        $SourceVar = [regex]::Escape($Matches[1])
                        $Sentinel = $Statements -match ('\$' + $SourceVar + '\s*=\s*if\s*\(')
                    }

                    @{
                        Category   = $Category
                        Name       = $Name
                        Path       = $_.FullName
                        LoopIndex  = $Index
                        LoopVar    = $Loop.Variable
                        Source     = $Loop.Source
                        Emits      = $Emits
                        Sentinel   = $Sentinel
                        IsExempt   = $Unguarded.ContainsKey($Key)
                        Reason     = if ($Unguarded.ContainsKey($Key)) { $Unguarded[$Key] } else { '' }
                        Marker             = $Marker
                        HasDecisionComment = $HasDecisionComment
                    }
                    $Index++
                }
            }
    )
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/Get-AZSCSafeProperty.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/Get-AZTICollectedValue.ps1')
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/Get-AZSCIdSegment.ps1')

    # Must match scripts/New-ScoutCollectorGolden.ps1 and the golden suite, so a collector with a
    # time-relative column behaves here exactly as it does when its record is captured.
    $script:RunTime = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()

    $script:FixtureCache = @{}
    function Get-CategoryFixture {
        param([string]$CategoryName)
        # Databases predates the per-category convention and keeps its original fixture name.
        $Path = if ($CategoryName -eq 'Databases') {
            Join-Path -Path $script:RepoRoot -ChildPath 'tests/fixtures/databases-collector-input.json'
        } else {
            Join-Path -Path $script:RepoRoot -ChildPath "tests/fixtures/collector-equivalence/$CategoryName.json"
        }
        if (-not $script:FixtureCache.ContainsKey($Path)) {
            $script:FixtureCache[$Path] = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        return $script:FixtureCache[$Path]
    }

    function New-FixtureContext {
        param([string]$CategoryName, [string]$CollectorName)
        $Fixture = Get-CategoryFixture -CategoryName $CategoryName
        $Resources = if ($CategoryName -eq 'Databases') {
            $Fixture.resources
        } else {
            $Fixture.collectors.PSObject.Properties[$CollectorName].Value.resources
        }
        @{
            ScriptRoot    = $script:RepoRoot
            Subscriptions = $Fixture.subscriptions
            InTag         = $false
            Resources     = $Resources
            Retirements   = $Fixture.retirements
            Task          = 'Processing'
            File          = $null
            SmaResources  = $null
            TableStyle    = 'Light20'
            Unsupported   = $Fixture.unsupported
            RunTime       = $script:RunTime
        }
    }

    # Run the collector with ONE child loop's source replaced by an empty collection. Everything
    # else — the estate, the subscriptions, the retirement data, the row preamble — is the shipped
    # article, so a difference in the result can only come from the emptied loop.
    #
    # NOTE the @() at every CALL SITE below rather than here: `return @(...)` collapses an empty
    # array to $null across a function boundary, and `$Rows.Count` would then fail with "the
    # property 'Count' cannot be found" instead of reporting that the collector produced no rows.
    function Invoke-WithEmptyChildLoop {
        param([string]$Path, [int]$LoopIndex, $Context)
        $Definition = Get-ScoutCollectorDefinition -Path $Path
        @($Definition.AdditionalRowLoops)[$LoopIndex].Source = '@()'
        return @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $Context)
    }

    function Invoke-AsShipped {
        param([string]$Path, $Context)
        $Definition = Get-ScoutCollectorDefinition -Path $Path
        return @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $Context)
    }
}

Describe 'A parent resource survives its child collection being absent (AB#6845)' -ForEach $script:LoopCases {

    It '<Category>/<Name> loop $<LoopVar> cannot silently drop its parent' {
        # THE COMPLETENESS ASSERTION, and the one that catches a collector written next year. Every
        # child row loop must fall into exactly one of three reviewed states. A loop that is none
        # of them is the defect this bug is about, and it fails here the day it is added.
        $Accounted = $Emits -or $Sentinel -or $IsExempt
        $Accounted | Should -BeTrue -Because "loop `$$LoopVar over '$Source' fans the row out over a child collection: when that collection is empty it must either set EmitNullWhenEmpty, assign its source through a conditional with a non-empty fallback, or be listed as a deliberate exception in this file. It does none of the three, so $Category/$Name disappears from its worksheet whenever Azure omits that collection"
    }

    It '<Category>/<Name> loop $<LoopVar> carries an explicit, recorded decision' {
        # THE AUDIT ASSERTION. Being accounted for is not the same as being REVIEWED. The three
        # states above are inferred from structure, and a loop can fall into the "sentinel" state
        # by accident — someone wrote the fallback for an unrelated reason years ago and nobody
        # has since asked whether this parent should survive. A silent omission is indistinguishable
        # from an oversight, which is the whole reason this bug's acceptance criterion is worded
        # the way it is.
        #
        # So every loop must SAY which decision was taken. `EmitNullWhenEmpty` says it as data.
        # A loop without it must say it in a comment carrying this exact marker, next to the loop
        # it describes, so the reasoning cannot drift away from the code into a commit message
        # nobody will read again.
        $Recorded = $Emits -or $HasDecisionComment
        $Recorded | Should -BeTrue -Because "loop `$$LoopVar over '$Source' fans a row out over a child collection, so someone has to have decided whether the parent survives that collection being empty. It neither sets EmitNullWhenEmpty nor carries a '$Marker' comment, so no decision is recorded and there is no way to tell a considered choice from an oversight. Add the flag, or add the comment saying why the row here IS the child"
    }

    It '<Category>/<Name> loop $<LoopVar> still emits the parent row when the child collection is empty' -Skip:(-not $Emits) {
        $Context = New-FixtureContext -CategoryName $Category -CollectorName $Name

        # The control. If the collector produces nothing from its own fixture then the emptied-loop
        # result is trivially equal to it, and the assertion below would pass while proving nothing.
        $Baseline = @(Invoke-AsShipped -Path $Path -Context $Context)
        $Baseline.Count | Should -BeGreaterThan 0 -Because "$Category/$Name must produce rows from its own fixture, or this test is vacuous"

        $Rows = @(Invoke-WithEmptyChildLoop -Path $Path -LoopIndex $LoopIndex -Context $Context)
        $Rows.Count | Should -BeGreaterThan 0 -Because "a resource must not disappear from the $Category/$Name worksheet because Azure omitted the collection behind loop `$$LoopVar"
    }

    It '<Category>/<Name> loop $<LoopVar> is a deliberate, documented exception' -Skip:(-not $IsExempt) {
        # The allow-list half. These loops legitimately emit nothing, but the behaviour must be the
        # one the written reason describes — an exception that quietly STARTED emitting parent rows
        # is as much an unreviewed change as one that quietly stopped.
        $Reason | Should -Not -BeNullOrEmpty
        $Context = New-FixtureContext -CategoryName $Category -CollectorName $Name
        $Rows = @(Invoke-WithEmptyChildLoop -Path $Path -LoopIndex $LoopIndex -Context $Context)
        $Rows.Count | Should -Be 0 -Because "the row here IS the child: $Reason"
    }
}

Describe 'The guard is expressed in the definition, not in the interpreter (AB#6845)' {

    BeforeAll {
        $script:SyntheticDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("scout-ab6845-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $script:SyntheticDir -ItemType Directory -Force

        # Written to disk and loaded through Get-ScoutCollectorDefinition rather than hand-built as
        # a hashtable, so the definition under test goes through the same normalisation (and the
        # same schema validation) every shipped collector does.
        function New-SyntheticDefinitionFile {
            param([string]$FileName, [bool]$Emit)
            $EmitLine = if ($Emit) { "            EmitNullWhenEmpty = `$true`n" } else { '' }
            $Path = Join-Path -Path $script:SyntheticDir -ChildPath $FileName
            Set-Content -LiteralPath $Path -Encoding utf8 -Value @"
@{
    ResourceTypes = @('microsoft.test/things')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = `$null
    FilterPreamble = ''
    RowLoopVariable = '1'
    SetupPreamble = ''
    SetupVariables = @()
    # `$ResUCount is read by the interpreter's own tag-dedup line, so every real definition sets
    # it in its row preamble and a synthetic one must too.
    Preamble = '`$ResUCount = 1'
    AdditionalRowLoops = @(
        @{
            Variable = '2'
            Source = '@()'
$EmitLine            Preamble = ''
        }
    )
    TagLoop = `$null
    Fields = @(
        @{ Name = 'Name'; Expression = '`$1.NAME' }
        @{ Name = 'Child'; Expression = '`$2' }
    )
    Export = @{
        WorksheetName = 'Things'
        TableNamePrefix = 'ThingsTable_'
        Columns = @('Name', 'Child')
        TagColumns = @()
        TagColumnsBefore = `$null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
"@
            return $Path
        }

        $script:SyntheticContext = @{
            ScriptRoot = $script:RepoRoot
            Subscriptions = @([pscustomobject]@{ id = '00000000-0000-0000-0000-000000000001'; Name = 'sub-one' })
            InTag = $false
            Resources = @([pscustomobject]@{
                id = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers/microsoft.test/things/thing-one'
                NAME = 'thing-one'; TYPE = 'microsoft.test/things'; LOCATION = 'eastus'
                RESOURCEGROUP = 'rg'; subscriptionId = '00000000-0000-0000-0000-000000000001'
                PROPERTIES = [pscustomobject]@{}; tags = [pscustomobject]@{}
            })
            Retirements = @(); Task = 'Processing'; File = $null; SmaResources = $null
            TableStyle = 'Light20'; Unsupported = @(); RunTime = $script:RunTime
        }
    }

    AfterAll {
        if ($script:SyntheticDir -and (Test-Path -LiteralPath $script:SyntheticDir)) {
            Remove-Item -LiteralPath $script:SyntheticDir -Recurse -Force
        }
    }

    It 'reproduces the defect on a definition without the key' {
        # A directed proof of the mechanism itself, independent of any shipped collector, so an
        # interpreter regression is attributable here rather than diffusely across 40 manifests.
        $Path = New-SyntheticDefinitionFile -FileName 'Unguarded.psd1' -Emit $false
        $Definition = Get-ScoutCollectorDefinition -Path $Path
        $Rows = @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $script:SyntheticContext)
        $Rows.Count | Should -Be 0 -Because 'this IS the defect: no children, no row, and the parent is gone from the report'
    }

    It 'EmitNullWhenEmpty emits the parent exactly once, with the child column blank' {
        $Path = New-SyntheticDefinitionFile -FileName 'Guarded.psd1' -Emit $true
        $Definition = Get-ScoutCollectorDefinition -Path $Path
        $Rows = @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $script:SyntheticContext)
        $Rows.Count | Should -Be 1 -Because 'the parent must appear exactly once — not zero times, and not duplicated'
        $Rows[0]['Name'] | Should -Be 'thing-one' -Because 'the parent row must still identify the resource'
        $Rows[0]['Child'] | Should -BeNullOrEmpty -Because 'the child-specific column is left blank, not invented'
    }
}
