#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#5656 — THE CUTOVER.

    v2.9.0 shipped 124 of 176 collectors as `.psd1` definitions, each proven row-for-row
    equivalent to its `.ps1` by tests/DeclarativeCollectorEquivalence.Tests.ps1 — and NOTHING
    USED THEM. Every collector in a live run still executed its hand-written script. Converting
    is not the same as using: until the pipeline routes to the interpreter, the whole feature
    delivers a directory of files nobody runs.

    This file exists because the cutover is, uniquely, INVISIBLE to the equivalence proof. The
    two paths produce identical rows by construction — that is the point of the proof — so a
    routing regression that quietly sent every collector back to its `.ps1` would leave the
    entire suite green. Row comparison can never detect it.

    So these tests assert the thing rows cannot: WHICH IMPLEMENTATION RAN. The central technique
    is a booby-trapped fixture — a collector whose `.psd1` is valid and whose `.ps1` throws on
    sight, or emits a sentinel value no definition ever could. If the run succeeds and carries
    the declarative values, the script was not executed. That is not inference; there is no
    other way for the run to have completed.

    The same fixture, run with the kill switch on, must produce the OPPOSITE result. A kill
    switch that silently did nothing would also make every test here pass if they only ever
    asserted the declarative outcome.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Write-ScoutCacheFile.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutProcessing.ps1')

    # The kill switch is process-wide state. Capture whatever the caller had and restore it in
    # AfterAll — a suite that leaks it would silently disable the cutover for every test file
    # Pester runs after this one, and they would all still pass.
    $script:OriginalKillSwitch = $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS
    $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = $null

    # ── The booby-trapped fixture estate ──────────────────────────────────────────────────
    #
    # A private root per run: ~18 test files in this repo hardcode a shared $env:TEMP\AZSC_*
    # path and delete it in BeforeAll, so anything predictable here is racing them.
    $script:FixtureRoot    = Join-Path ([System.IO.Path]::GetTempPath()) ("scout-cutover-" + [guid]::NewGuid().ToString('N'))
    $script:InventoryRoot  = Join-Path $script:FixtureRoot 'InventoryModules'
    $script:DefinitionRoot = Join-Path $script:FixtureRoot 'definitions'

    function New-CutoverCollector {
        param([string]$Category, [string]$Name, [string]$Body, [string]$Root)
        if (-not $Root) { $Root = $script:InventoryRoot }
        $Dir = Join-Path $Root $Category
        if (-not (Test-Path -LiteralPath $Dir)) { $null = New-Item -Path $Dir -ItemType Directory -Force }
        # Concatenated, not formatted: the bodies contain $_ and $1, which -f and -replace eat.
        $Lines = @(
            'param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)'
            "If (`$Task -eq 'Processing') {"
            $Body
            '}'
        )
        Set-Content -LiteralPath (Join-Path $Dir "$Name.ps1") -Value ($Lines -join "`n") -Encoding UTF8
    }

    function New-CutoverDefinition {
        param([string]$Category, [string]$Name, [string]$Text, [string]$Root)
        if (-not $Root) { $Root = $script:DefinitionRoot }
        $Dir = Join-Path $Root $Category
        if (-not (Test-Path -LiteralPath $Dir)) { $null = New-Item -Path $Dir -ItemType Directory -Force }
        Set-Content -LiteralPath (Join-Path $Dir "$Name.psd1") -Value $Text -Encoding UTF8
    }

    # 1. Sentinel — both implementations run, and they disagree ON PURPOSE. Which value comes
    #    out of the pipeline names the path that executed it.
    New-CutoverCollector -Category 'Fixture' -Name 'Sentinel' -Body @'
    foreach ($1 in ($Resources | Where-Object { $_.TYPE -eq 'widget' })) {
        @{ ID = $1.id; Origin = 'FROM-IMPERATIVE'; 'Resource U' = 1 }
    }
'@
    New-CutoverDefinition -Category 'Fixture' -Name 'Sentinel' -Text @'
@{
    ResourceTypes   = @('widget')
    RowLoopVariable = '1'
    TagLoop         = $null
    Preamble        = '$ResUCount = 1'
    Fields = @(
        @{ Name = 'ID';          Expression = '$1.id' }
        @{ Name = 'Origin';      Expression = "'FROM-DECLARATIVE'" }
        @{ Name = 'Resource U';  Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Sentinel'
        Columns       = @('ID', 'Origin', 'Resource U')
        TagColumns    = @()
    }
}
'@

    # 2. Landmine — the `.ps1` cannot produce a row at all. It throws the instant it is invoked
    #    in Processing. A run that completes with this collector's rows present is proof by
    #    impossibility that the script was never executed; no assertion about row VALUES could
    #    establish that, because both paths are meant to agree on values.
    New-CutoverCollector -Category 'Fixture' -Name 'Landmine' -Body @'
    throw 'THE IMPERATIVE SCRIPT RAN'
'@
    New-CutoverDefinition -Category 'Fixture' -Name 'Landmine' -Text @'
@{
    ResourceTypes   = @('mine')
    RowLoopVariable = '1'
    TagLoop         = $null
    Preamble        = '$ResUCount = 1'
    Fields = @(
        @{ Name = 'ID';         Expression = '$1.id' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Landmine'
        Columns       = @('ID', 'Resource U')
        TagColumns    = @()
    }
}
'@

    # 3. Unconverted — no `.psd1`. The escape hatch (ADR §2.4): 52 of the 176 shipped collectors
    #    are in this state and must keep running exactly as they always have.
    New-CutoverCollector -Category 'Fixture' -Name 'Unconverted' -Body @'
    foreach ($1 in ($Resources | Where-Object { $_.TYPE -eq 'legacy' })) {
        @{ ID = $1.id; Origin = 'FROM-IMPERATIVE'; 'Resource U' = 1 }
    }
'@

    # 4. Malformed — a `.psd1` that loads as data but fails schema validation (no Fields). The
    #    collector must still produce its rows, via the script sitting next to it.
    New-CutoverCollector -Category 'Fixture' -Name 'Malformed' -Body @'
    foreach ($1 in ($Resources | Where-Object { $_.TYPE -eq 'broken' })) {
        @{ ID = $1.id; Origin = 'FROM-IMPERATIVE'; 'Resource U' = 1 }
    }
'@
    New-CutoverDefinition -Category 'Fixture' -Name 'Malformed' -Text @'
@{
    ResourceTypes   = @('broken')
    RowLoopVariable = '1'
    Export = @{ WorksheetName = 'Malformed'; Columns = @('ID') }
}
'@

    $script:Estate = @(
        [PSCustomObject]@{ id = '/w/1'; NAME = 'w1'; TYPE = 'widget' }
        [PSCustomObject]@{ id = '/w/2'; NAME = 'w2'; TYPE = 'widget' }
        [PSCustomObject]@{ id = '/m/1'; NAME = 'm1'; TYPE = 'mine' }
        [PSCustomObject]@{ id = '/l/1'; NAME = 'l1'; TYPE = 'legacy' }
        [PSCustomObject]@{ id = '/b/1'; NAME = 'b1'; TYPE = 'broken' }
    )

    function Get-CutoverDescriptor {
        param([string]$Name)
        @(Get-ScoutCollector -InventoryRoot $script:InventoryRoot -DefinitionRoot $script:DefinitionRoot |
            Where-Object { $_.Name -eq $Name })[0]
    }

    function New-CutoverContext {
        @{
            ScriptRoot = $script:InventoryRoot; Subscriptions = @(); InTag = $null
            Resources  = $script:Estate; Retirements = @(); Task = 'Processing'
            File       = $null; SmaResources = $null; TableStyle = $null; Unsupported = @()
        }
    }

    function Invoke-CutoverRun {
        param([switch]$ForceImperative)
        $RunPath = Join-Path $script:FixtureRoot ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path (Join-Path $RunPath 'ReportCache') -ItemType Directory -Force

        $Summary = Invoke-ScoutProcessing -Resources $script:Estate -DefaultPath $RunPath `
            -InventoryRoot $script:InventoryRoot -DefinitionRoot $script:DefinitionRoot `
            -ForceImperativeCollectors:$ForceImperative -WarningAction SilentlyContinue

        $CacheFile = Join-Path $RunPath 'ReportCache/Fixture.json'
        $Cache = if (Test-Path -LiteralPath $CacheFile) {
            Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
        } else { $null }

        [PSCustomObject]@{ Summary = $Summary; Cache = $Cache }
    }
}

AfterAll {
    $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = $script:OriginalKillSwitch
    if ($script:FixtureRoot -and (Test-Path -LiteralPath $script:FixtureRoot)) {
        Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Cutover — a collector with a definition is executed by the interpreter, not by its .ps1' {

    It 'runs the definition and never reads the script' {
        $Descriptor = Get-CutoverDescriptor -Name 'Sentinel'
        $Descriptor.HasDeclarativeDefinition | Should -BeTrue

        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext)

        $Result.Mode    | Should -Be 'Declarative'
        $Result.Success | Should -BeTrue
        @($Result.Rows).Count | Should -Be 2
        @($Result.Rows | ForEach-Object { $_['Origin'] } | Select-Object -Unique) | Should -Be 'FROM-DECLARATIVE'
    }

    It 'completes a collector whose .ps1 throws on sight — the script cannot have run' {
        # The unfakeable assertion. Landmine.ps1's entire Processing branch is `throw`. There is
        # no execution of it that yields a row, so a successful result with rows means the
        # interpreter produced them.
        $Descriptor = Get-CutoverDescriptor -Name 'Landmine'
        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext)

        $Result.Success | Should -BeTrue
        $Result.Mode    | Should -Be 'Declarative'
        @($Result.Rows).Count | Should -Be 1
        $Result.Rows[0]['ID'] | Should -Be '/m/1'
    }

    It 'keeps running the .ps1 for a collector with no definition' {
        $Descriptor = Get-CutoverDescriptor -Name 'Unconverted'
        $Descriptor.HasDeclarativeDefinition | Should -BeFalse

        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext)

        $Result.Mode | Should -Be 'Imperative'
        @($Result.Rows | ForEach-Object { $_['Origin'] }) | Should -Be 'FROM-IMPERATIVE'
    }

    It 'routes imperative for a hand-built descriptor that carries no HasDeclarativeDefinition property' {
        # Hand-built descriptors are real — the equivalence harness and Invoke-CollectorAudit both
        # make them. "I do not know whether a definition exists" must resolve to the path that has
        # shipped in every release, not to the new one.
        $Descriptor = [PSCustomObject]@{
            Name = 'Sentinel'; FolderCategory = 'Fixture'
            Path = (Join-Path $script:InventoryRoot 'Fixture/Sentinel.ps1')
        }
        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext)

        $Result.Mode | Should -Be 'Imperative'
        @($Result.Rows | ForEach-Object { $_['Origin'] } | Select-Object -Unique) | Should -Be 'FROM-IMPERATIVE'
    }
}

Describe 'Cutover — the whole processing pass routes on the definition' {

    BeforeAll { $script:Run = Invoke-CutoverRun }

    It 'writes declarative rows into the report cache' {
        # End to end, through Invoke-ScoutProcessing and Write-ScoutCacheFile — not just through
        # Invoke-ScoutCollector in isolation. The cache file is what the report is built from.
        @($script:Run.Cache.Sentinel | ForEach-Object { $_.Origin } | Select-Object -Unique) |
            Should -Be 'FROM-DECLARATIVE'
    }

    It 'has no failures, so the landmine .ps1 never executed anywhere in the pass' {
        $script:Run.Summary.FailureCount | Should -Be 0
        @($script:Run.Cache.Landmine).Count | Should -Be 1
    }

    It 'reports how many collectors ran each way' {
        # Counted from the RESULT of each collector, so this is a report of what happened rather
        # than of what the descriptor intended.
        $script:Run.Summary.DeclarativeCount | Should -Be 2   # Sentinel, Landmine
        $script:Run.Summary.ImperativeCount  | Should -Be 2   # Unconverted, Malformed (fallback)
        $script:Run.Summary.CollectorCount   | Should -Be 4
    }

    It 'still runs the unconverted collector as a script in the same pass' {
        @($script:Run.Cache.Unconverted | ForEach-Object { $_.Origin }) | Should -Be 'FROM-IMPERATIVE'
    }
}

Describe 'Cutover — a definition that fails schema validation falls back instead of losing the worksheet' {

    It 'runs the .ps1 and reports the fallback' {
        # A schema-invalid definition is a repo defect that CI catches, so this path should never
        # fire in a release. If it ever does, losing a whole worksheet when a working script is
        # sitting beside it would be the worse failure.
        $Descriptor = Get-CutoverDescriptor -Name 'Malformed'
        $Descriptor.HasDeclarativeDefinition | Should -BeTrue

        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext) -WarningAction SilentlyContinue

        $Result.Mode    | Should -Be 'ImperativeFallback'
        $Result.Success | Should -BeTrue
        @($Result.Rows | ForEach-Object { $_['Origin'] }) | Should -Be 'FROM-IMPERATIVE'
    }

    It 'warns rather than failing silently' {
        $Descriptor = Get-CutoverDescriptor -Name 'Malformed'
        $Warnings = @()
        $null = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext) -WarningVariable Warnings
        ($Warnings -join ' ') | Should -BeLike '*INVALID declarative definition*'
    }
}

Describe 'Cutover — the kill switch' {

    AfterEach { $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = $null }

    It 'AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS puts every collector back on its .ps1' {
        $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = '1'

        $Descriptor = Get-CutoverDescriptor -Name 'Sentinel'
        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext)

        $Result.Mode | Should -Be 'Imperative'
        @($Result.Rows | ForEach-Object { $_['Origin'] } | Select-Object -Unique) | Should -Be 'FROM-IMPERATIVE'
    }

    It 'and the landmine then blows up, proving the switch really changed the executing path' {
        # Without this, "kill switch works" would rest on a sentinel STRING that a broken switch
        # could coincidentally produce. A collector that can only fail when its script runs
        # cannot be faked: this failure IS the imperative path executing.
        $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = 'true'

        $Descriptor = Get-CutoverDescriptor -Name 'Landmine'
        $Result = Invoke-ScoutCollector -Collector $Descriptor -Context (New-CutoverContext) -WarningAction SilentlyContinue

        $Result.Success | Should -BeFalse
        $Result.Error.Exception.Message | Should -BeLike '*THE IMPERATIVE SCRIPT RAN*'
    }

    It 'turns the whole processing pass back to the pre-cutover behaviour' {
        $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = 'yes'
        $Run = Invoke-CutoverRun

        $Run.Summary.DeclarativeCount | Should -Be 0
        $Run.Summary.ImperativeCount  | Should -Be 4
        $Run.Summary.FailureCount     | Should -Be 1   # the landmine, exactly as v2.9.0 behaved
        @($Run.Cache.Sentinel | ForEach-Object { $_.Origin } | Select-Object -Unique) | Should -Be 'FROM-IMPERATIVE'
    }

    It 'the -ForceImperativeCollectors parameter does the same without touching the environment' {
        $Run = Invoke-CutoverRun -ForceImperative

        $Run.Summary.DeclarativeCount | Should -Be 0
        $Run.Summary.ImperativeCount  | Should -Be 4
        @($Run.Cache.Sentinel | ForEach-Object { $_.Origin } | Select-Object -Unique) | Should -Be 'FROM-IMPERATIVE'
    }

    It 'reads <_> as OFF, leaving the cutover enabled' -ForEach @('', ' ', '0', 'false', 'no', 'off', 'maybe') {
        # A truthiness test on the raw string would make `= '0'` mean "forced imperative", which
        # is the opposite of what anyone typing it intends. Only the affirmative spellings count.
        $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = $_
        Test-ScoutDeclarativeCutoverDisabled | Should -BeFalse
    }

    It 'reads <_> as ON' -ForEach @('1', 'true', 'TRUE', 'yes', 'on', ' true ') {
        $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS = $_
        Test-ScoutDeclarativeCutoverDisabled | Should -BeTrue
    }

    It 'is off when the variable is not set at all' {
        Remove-Item Env:\AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS -ErrorAction SilentlyContinue
        Test-ScoutDeclarativeCutoverDisabled | Should -BeFalse
    }
}

Describe 'Cutover — the shipped estate' {

    BeforeAll {
        $script:Shipped = @(Get-ScoutCollector -InventoryRoot (Join-Path $script:RepoRoot 'Modules/Public/InventoryModules'))
    }

    It 'routes every collector that has a definition, and only those' {
        $WithDefinition = @($script:Shipped | Where-Object { $_.HasDeclarativeDefinition })
        $OnDisk = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'manifests/collectors') -Filter '*.psd1' -Recurse -File)

        # Not a hardcoded 124: the sibling conversion work adds definitions, and a count pinned
        # here would fail for the right reason at the wrong time. What must hold is that
        # discovery sees exactly the definitions that exist.
        @($WithDefinition).Count | Should -Be @($OnDisk).Count
        @($WithDefinition).Count | Should -BeGreaterThan 100
    }

    It 'every routed collector loads through the schema validator, so none of them can fall back' {
        # ImperativeFallback in a release would mean a shipped worksheet silently reverted to the
        # old path. This is the gate that keeps the fallback branch dead code in practice.
        foreach ($Collector in @($script:Shipped | Where-Object { $_.HasDeclarativeDefinition })) {
            { Get-ScoutCollectorDefinition -Path $Collector.DefinitionPath } |
                Should -Not -Throw -Because "$($Collector.FolderCategory)/$($Collector.Name) would fall back to its .ps1 in a live run"
        }
    }

    It 'a real shipped collector reports Declarative through the real dispatch' {
        $SqlDb = @($script:Shipped | Where-Object { $_.FolderCategory -eq 'Databases' -and $_.Name -eq 'SQLDB' })[0]
        $SqlDb.HasDeclarativeDefinition | Should -BeTrue

        $Fixture = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests/fixtures/databases-collector-input.json') -Raw | ConvertFrom-Json
        $Result = Invoke-ScoutCollector -Collector $SqlDb -Context @{
            ScriptRoot = (Join-Path $script:RepoRoot 'Modules/Public/InventoryModules')
            Subscriptions = $Fixture.subscriptions; InTag = $false; Resources = $Fixture.resources
            Retirements = $Fixture.retirements; Task = 'Processing'; File = $null
            SmaResources = $null; TableStyle = $null; Unsupported = $Fixture.unsupported
        }

        $Result.Mode    | Should -Be 'Declarative'
        $Result.Success | Should -BeTrue
        @($Result.Rows).Count | Should -BeGreaterThan 0
    }
}

Describe 'Cutover — a field expression that throws, which the ADR says the two paths handle differently' {

    # ADR §4.1 records an asymmetry and nothing tested it, because the generated fixtures are
    # built specifically so no expression throws. It is the one difference that could bite at
    # cutover, when a real tenant hands a collector a shape no fixture had:
    #
    #   imperative: `$obj = @{ ... }` fails, $obj keeps the PREVIOUS iteration's value, and the
    #               following `$obj` statement emits that row a SECOND time.
    #   declarative: the row is one `@{ ... }` statement, so a throw emits nothing at all.
    #
    # MEASURED, and the ADR's conclusion does not transfer to the live pipeline. A .NET method
    # exception (`.Substring` past the end — the commonest real shape of this) is a
    # STATEMENT-terminating error, and a statement-terminating error is caught by an enclosing
    # try/catch. Invoke-ScoutCollector wraps both paths in one, so in a real run neither path
    # reaches its next iteration: the collector fails, is contained, and emits nothing, exactly
    # as it did in v2.9.0. The asymmetry is real only where nothing catches — pinned below,
    # because it is the reason the containment try/catch is load-bearing rather than defensive.
    #
    # So the cutover does NOT change behaviour here. That is a measurement, not a reassurance:
    # if a future change moved the try/catch inside the row loop to salvage partial output, the
    # two paths would immediately start disagreeing, and these tests would say so.

    BeforeAll {
        # Its OWN roots, not the shared estate above: adding a fifth collector to that tree would
        # change the DeclarativeCount/ImperativeCount this file asserts elsewhere, and a test
        # whose fixture depends on Describe execution order is a test that breaks when someone
        # reorders the file.
        $script:ThrowInventory  = Join-Path $script:FixtureRoot 'throw-inventory'
        $script:ThrowDefinition = Join-Path $script:FixtureRoot 'throw-definitions'

        New-CutoverCollector -Root $script:ThrowInventory -Category 'Throwing' -Name 'ShortName' -Body @'
    foreach ($1 in ($Resources | Where-Object { $_.TYPE -eq 'thrower' })) {
        $obj = @{ ID = $1.id; Sliced = $1.NAME.Substring(10); 'Resource U' = 1 }
        $obj
    }
'@
        New-CutoverDefinition -Root $script:ThrowDefinition -Category 'Throwing' -Name 'ShortName' -Text @'
@{
    ResourceTypes   = @('thrower')
    RowLoopVariable = '1'
    TagLoop         = $null
    Preamble        = '$ResUCount = 1'
    Fields = @(
        @{ Name = 'ID';         Expression = '$1.id' }
        @{ Name = 'Sliced';     Expression = '$1.NAME.Substring(10)' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{ WorksheetName = 'Throwing'; Columns = @('ID', 'Sliced', 'Resource U'); TagColumns = @() }
}
'@
        # First and third slice fine; the middle one is too short, so .Substring(10) throws on it
        # alone. Three resources, not two, so "the row after the bad one" is observable.
        $script:ThrowEstate = @(
            [PSCustomObject]@{ id = '/t/1'; NAME = 'a-long-enough-name'; TYPE = 'thrower' }
            [PSCustomObject]@{ id = '/t/2'; NAME = 'short';              TYPE = 'thrower' }
            [PSCustomObject]@{ id = '/t/3'; NAME = 'another-long-name';  TYPE = 'thrower' }
        )
        $script:ThrowContext = @{
            ScriptRoot = $script:ThrowInventory; Subscriptions = @(); InTag = $null
            Resources  = $script:ThrowEstate; Retirements = @(); Task = 'Processing'
            File = $null; SmaResources = $null; TableStyle = $null; Unsupported = @()
        }

        # A SECOND failure shape, because the two are not handled the same way underneath. A .NET
        # method exception escapes InvokeWithContext untouched; a PowerShell runtime error (here a
        # failed [datetime] cast) comes back wrapped in `Exception calling "InvokeWithContext"`.
        # Only the second needs unwrapping, and a test that exercised only the first would have
        # let an over-eager unwrap through — which is exactly what happened: unwrapping both
        # stripped a layer off the Substring case that the imperative path keeps.
        New-CutoverCollector -Root $script:ThrowInventory -Category 'Throwing' -Name 'CastFail' -Body @'
    foreach ($1 in ($Resources | Where-Object { $_.TYPE -eq 'caster' })) {
        $obj = @{ ID = $1.id; When = [datetime]$1.missing; 'Resource U' = 1 }
        $obj
    }
'@
        New-CutoverDefinition -Root $script:ThrowDefinition -Category 'Throwing' -Name 'CastFail' -Text @'
@{
    ResourceTypes   = @('caster')
    RowLoopVariable = '1'
    TagLoop         = $null
    Preamble        = '$ResUCount = 1'
    Fields = @(
        @{ Name = 'ID';         Expression = '$1.id' }
        @{ Name = 'When';       Expression = '[datetime]$1.missing' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{ WorksheetName = 'Casting'; Columns = @('ID', 'When', 'Resource U'); TagColumns = @() }
}
'@
        $script:CastEstate = @([PSCustomObject]@{ id = '/c/1'; NAME = 'c1'; TYPE = 'caster' })
        $script:CastContext = @{
            ScriptRoot = $script:ThrowInventory; Subscriptions = @(); InTag = $null
            Resources  = $script:CastEstate; Retirements = @(); Task = 'Processing'
            File = $null; SmaResources = $null; TableStyle = $null; Unsupported = @()
        }

        $script:Discovered = @(Get-ScoutCollector -InventoryRoot $script:ThrowInventory -DefinitionRoot $script:ThrowDefinition)
        $script:ThrowDescriptor = @($script:Discovered | Where-Object { $_.Name -eq 'ShortName' })[0]
        $script:CastDescriptor  = @($script:Discovered | Where-Object { $_.Name -eq 'CastFail' })[0]
    }

    It 'both paths fail the collector identically, so the cutover changes nothing here' {
        $Imperative  = Invoke-ScoutCollector -Collector $script:ThrowDescriptor -Context $script:ThrowContext -Imperative -WarningAction SilentlyContinue
        $Declarative = Invoke-ScoutCollector -Collector $script:ThrowDescriptor -Context $script:ThrowContext -WarningAction SilentlyContinue

        $Imperative.Mode  | Should -Be 'Imperative'
        $Declarative.Mode | Should -Be 'Declarative'

        $Declarative.Success | Should -Be $Imperative.Success
        $Declarative.Success | Should -BeFalse
        @($Declarative.Rows).Count | Should -Be @($Imperative.Rows).Count
        @($Declarative.Rows).Count | Should -Be 0
        $Declarative.Error.Exception.Message | Should -Be $Imperative.Error.Exception.Message
    }

    It 'reports the collector failure without the interpreter in the message' {
        # InvokeWithContext is a .NET method call, so an unhandled row-script error comes back as
        # `Exception calling "InvokeWithContext" with "2" argument(s): "<real message>"`. That
        # string reaches the customer's run log via Invoke-ScoutCollector's warning, so leaving it
        # would have changed the text of every contained failure on the release that switches
        # paths — a diff in the logs with no corresponding change in what failed.
        $Result = Invoke-ScoutCollector -Collector $script:ThrowDescriptor -Context $script:ThrowContext -WarningAction SilentlyContinue
        $Result.Error.Exception.Message | Should -Not -BeLike '*InvokeWithContext*'
        $Result.Error.Exception.Message | Should -BeLike '*startIndex cannot be larger than length of string*'
    }

    It 'reports a failed cast identically to the imperative path, wrapper stripped' {
        # The shape that DOES get an extra layer. Both halves asserted: the wrapper is gone, AND
        # what is left is character-for-character what the .ps1 reports — stripping too much would
        # satisfy the first assertion and fail the second.
        $Imperative  = Invoke-ScoutCollector -Collector $script:CastDescriptor -Context $script:CastContext -Imperative -WarningAction SilentlyContinue
        $Declarative = Invoke-ScoutCollector -Collector $script:CastDescriptor -Context $script:CastContext -WarningAction SilentlyContinue

        $Imperative.Success  | Should -BeFalse
        $Declarative.Success | Should -BeFalse
        $Declarative.Error.Exception.Message | Should -Not -BeLike '*InvokeWithContext*'
        $Declarative.Error.Exception.Message | Should -Be $Imperative.Error.Exception.Message
    }

    It 'the failure is contained, not propagated' {
        # One bad resource costs a worksheet, not the run — the property AB#5649 bought, and it
        # must hold on the new path too.
        { Invoke-ScoutCollector -Collector $script:ThrowDescriptor -Context $script:ThrowContext -WarningAction SilentlyContinue } |
            Should -Not -Throw
    }

    It 'and the ADR asymmetry is real underneath — the imperative row loop DOES duplicate' {
        # A statement-terminating error only lets the loop continue when NOTHING in the call
        # stack catches it, and Pester wraps every It in a try/catch, so the behaviour cannot be
        # observed by running the collector here — it would just fail this test.
        #
        # A bare runspace is that catch-free stack. Using one is not a relapse into the machinery
        # AB#5649 deleted; it is the point. The v1 pipeline ran every collector in exactly such a
        # runspace, so "throw, keep the previous $obj, emit it twice" WAS the shipped behaviour
        # until AB#5649 wrapped collectors in a try/catch. That is also why this asymmetry cannot
        # bite at cutover: the containment that changed it is a year older than the interpreter,
        # and it changed both paths at once.
        $Shell = [powershell]::Create()
        try {
            $null = $Shell.AddScript(@'
param($estate)
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
foreach ($1 in $estate) {
    $obj = @{ ID = $1.id; Sliced = $1.NAME.Substring(10) }
    $obj
}
'@)
            $null = $Shell.AddParameter('estate', $script:ThrowEstate)
            $Rows = $Shell.Invoke()

            # /t/2 threw, so its assignment never ran and $obj still held /t/1's row.
            @($Rows | ForEach-Object { $_['ID'] }) | Should -Be @('/t/1', '/t/1', '/t/3')
            $Shell.Streams.Error.Count | Should -Be 1
        }
        finally { $Shell.Dispose() }
    }
}
