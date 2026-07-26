#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#5659 — the COVERAGE gate for the declarative collector conversion, kept separate from the
    equivalence proof in tests/DeclarativeCollectorEquivalence.Tests.ps1.

    The equivalence tests discover whatever definitions exist and prove each one matches the `.ps1` it
    was lifted from. That is necessary but not sufficient: it is trivially satisfiable by converting
    nothing. This file asserts the other half — that the converted set is exactly the set the audit
    (docs/design/collector-audit.md) classified as pure data-shaping, minus a short list of collectors
    that each carry a written reason.

    Two files rather than one because the two questions fail for different reasons and want different
    answers: an equivalence failure means a conversion is WRONG, a coverage failure means a conversion
    is MISSING.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    # Only the fixture loader is needed here, not the whole equivalence harness.
    $script:GeneratedFixtures = @{}
    function Get-GeneratedFixture {
        param([string]$Category)
        if (-not $script:GeneratedFixtures.ContainsKey($Category)) {
            $Path = Join-Path $script:RepoRoot "tests/fixtures/collector-equivalence/$Category.json"
            if (-not (Test-Path -LiteralPath $Path)) { throw "No generated equivalence fixture for category '$Category' at $Path" }
            $script:GeneratedFixtures[$Category] = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        return $script:GeneratedFixtures[$Category]
    }
}

Describe 'Declarative collector coverage — the converted set is exactly the audited pure set, minus a listed few' {
    BeforeAll {
        $script:Audit = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests/fixtures/collector-audit.json') -Raw | ConvertFrom-Json

        # The four PureShaping collectors NOT converted, each with the reason. Held as data in the test
        # rather than as prose in a design doc so that "convert everything the audit called pure" cannot
        # quietly become "convert everything that happened to be easy": editing this list is visible.
        #
        # Declared in BeforeAll, not at file scope: a file-scope variable is visible during DISCOVERY
        # (where -ForEach data is built) but not inside an It at run time.
        $script:UnconvertedPure = @(
            @{ Category = 'Management'; Name = 'AllSubscriptions'
               Reason = 'Its row loop iterates $Sub, not a filtered $Resources set, so there is no resource-type filter for the interpreter to drive; it also folds in a management-group chain built from a separate graph query.' }
            @{ Category = 'Management'; Name = 'AdvisorScore'
               Reason = 'Its $obj is built inside a nested if/else rather than as a statement of a row loop, so there is no single row-emitting level to lift.' }
            @{ Category = 'Networking'; Name = 'PublicIP'
               Reason = 'It has TWO $obj hashtable literals in opposite branches of an if/else -- the row SHAPE is conditional, which the schema deliberately cannot express (a Fields list is one shape).' }
            @{ Category = 'Monitor';    Name = 'Outages'
               Reason = 'AUDIT MISCLASSIFICATION: it builds its columns with New-Object -Com HTMLFile and reads $Html.body.innerText, so it is not pure shaping at all -- it depends on a COM component the audit never looked for (it only searched for Get-Az*/Invoke-*).' }
        )

        $script:AllDefinitions = @(
            foreach ($Folder in (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'manifests/collectors') -Directory | Sort-Object Name)) {
                foreach ($File in (Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.psd1' -File | Sort-Object Name)) {
                    @{ Category = $Folder.Name; Name = $File.BaseName }
                }
            }
        )
    }

    It 'every PureShaping collector either has a definition or is on the unconverted list' {
        $Missing = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in @($script:Audit | Where-Object { $_.Classification -eq 'PureShaping' })) {
            $Path = Join-Path $script:RepoRoot "manifests/collectors/$($Entry.Category)/$($Entry.Name).psd1"
            if (Test-Path -LiteralPath $Path) { continue }
            $Listed = @($script:UnconvertedPure | Where-Object { $_.Category -eq $Entry.Category -and $_.Name -eq $Entry.Name })
            if (@($Listed).Count -eq 0) { $Missing.Add("$($Entry.Category)/$($Entry.Name)") }
        }
        $Missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'nothing on the unconverted list has a definition after all' {
        # Keeps the list honest in the other direction: a stale entry here would understate coverage
        # and hide the fact that the obstacle was solved.
        foreach ($Entry in $script:UnconvertedPure) {
            (Join-Path $script:RepoRoot "manifests/collectors/$($Entry.Category)/$($Entry.Name).psd1") |
                Should -Not -Exist -Because "$($Entry.Category)/$($Entry.Name) is listed as unconverted: $($Entry.Reason)"
        }
    }

    It 'every definition has a generated fixture entry with at least one resource' {
        # A definition with no fixture entry would make its equivalence Describe throw rather than
        # silently pass, but a definition whose fixture entry is EMPTY would pass vacuously.
        foreach ($Entry in $script:AllDefinitions) {
            $Fixture = Get-GeneratedFixture -Category $Entry.Category
            $Fixture.collectors.PSObject.Properties.Name | Should -Contain $Entry.Name
            @($Fixture.collectors.($Entry.Name).resources).Count | Should -BeGreaterThan 0
        }
    }

    It 'no generated fixture carries anything that looks like a real tenant identifier' {
        # The generated estates are entirely synthetic, but they live in tests/fixtures next to the
        # recorded ones and the repo's hard rule about subscription/tenant ids applies to every
        # committed file. The only GUIDs these may contain are the two placeholders.
        $Allowed = @('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000ff')
        $Pattern = [regex]'(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
        foreach ($File in (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'tests/fixtures/collector-equivalence') -Filter '*.json' -File)) {
            $Text = Get-Content -LiteralPath $File.FullName -Raw
            $Bad  = @($Pattern.Matches($Text) | ForEach-Object { $_.Value } | Where-Object { $Allowed -notcontains $_.ToLowerInvariant() } | Select-Object -Unique)
            $Bad -join ', ' | Should -BeNullOrEmpty -Because "$($File.Name) must contain no identifier that could be real"
        }
    }
}
