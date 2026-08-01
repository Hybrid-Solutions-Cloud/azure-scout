#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6817 — establish the framework currency and version-stamping rule.

    The audit's §8 "Framework currency warnings" records two facts that make this a permanent
    problem, not a one-time correction: Microsoft is actively rewriting CAF design-area pages
    (at least three already have no "Design recommendations" heading at all), and regulatory
    initiatives are versioned with old versions still shipping side by side (Azure offers six CIS
    Azure Foundations initiatives at once). A bare "CIS compliance: 72%" is meaningless without
    naming which of those it was measured against, and a coverage figure computed against a CAF
    page that has since been rewritten drifts silently.

    Four things are pinned here:
      1. Every docs/frameworks/*.md enumeration file carries a Source, a Framework version, an
         extraction date, and a verification method (docs/frameworks/README.md defines the two
         accepted header shapes).
      2. No enumeration file is old enough to be past its recheck grace period, unnoticed.
      3. src/assess/engine/Get-RuleSet.ps1 REFUSES to load a rule file that scores anything but
         names no framework version -- the actual gate criterion 4 of AB#6817 asks for. Proven
         against a real, disposable fixture, not just asserted.
      4. The version survives the trip through Invoke-Assessment and Get-Score, so a coverage
         figure Scout's engine actually emits carries its framework version end to end.

    Pure-file / pure-logic tests -- no Azure connection.
#>

# ---- header-block parser -------------------------------------------------------------------
# docs/frameworks/README.md documents two accepted header shapes:
#   Shape A: a blockquote block  "> **Source:** ..." / "> **Framework version:** ..." / ...
#   Shape B: a "**Enumerated YYYY-MM-DD.**" lede plus a "| Field | Value |" table carrying
#            "Framework version", "Extraction date"/"Extracted", and "Verification method" rows.
# This parser accepts either, because that is what the standard actually requires files to
# carry -- it is not stricter than the standard it is enforcing.
#
# Declared as a true top-level function (not inside BeforeDiscovery/BeforeAll): Pester's
# Discovery and Run phases each get their own execution of this container, and a function
# defined inside either of those blocks is not visible in the other -- only a plain top-level
# function declaration is reliably in scope for both the -ForEach case-list build (Discovery)
# and the It bodies that call it (Run).
function Get-FrameworkFileFacts {
    param([Parameter(Mandatory)] [string] $Path)

    $text = Get-Content -LiteralPath $Path -Raw

    # Extraction date: blockquote "> **Extracted:**", table "| Extraction date |", or the
    # "**Enumerated DATE.**" lede paragraph nearly every file in this directory opens with.
    $dateMatch = [regex]::Match($text, '>\s*\*\*Extracted:\*\*\s*(\d{4}-\d{2}-\d{2})')
    if (-not $dateMatch.Success) {
        $dateMatch = [regex]::Match($text, '\|\s*Extraction date\s*\|\s*(\d{4}-\d{2}-\d{2})')
    }
    if (-not $dateMatch.Success) {
        $dateMatch = [regex]::Match($text, '\*\*Enumerated\s+(\d{4}-\d{2}-\d{2})')
    }
    $extractedRaw = if ($dateMatch.Success) { $dateMatch.Groups[1].Value } else { $null }

    # Framework version: blockquote "> **Framework version:**", table row, or a bare
    # "**Framework version:**" line (the shape added to the three files that predate the
    # table/blockquote convention).
    $versionMatch = [regex]::Match($text, '>\s*\*\*Framework version:\*\*\s*(\S.*)')
    if (-not $versionMatch.Success) {
        $versionMatch = [regex]::Match($text, '\|\s*Framework version\s*\|\s*(.+?)\s*\|')
    }
    if (-not $versionMatch.Success) {
        $versionMatch = [regex]::Match($text, '(?m)^\*\*Framework version:\*\*\s*(\S.*)$')
    }
    $version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value.Trim() } else { $null }

    # Verification method: blockquote line, table row, or a "## Verification method" heading
    # (every file in this directory carries at least one of these).
    $hasMethod =
        ($text -match '>\s*\*\*Verification method:\*\*\s*\S') -or
        ($text -match '\|\s*Verification method\s*\|\s*\S') -or
        ($text -match '(?m)^#{1,3}\s*Verification method\b')

    # Source: blockquote "> **Source:**", table "| Source page |", or -- since every file in this
    # directory cites Microsoft Learn / Microsoft Assessments URLs regardless of header shape -- a
    # bare canonical URL anywhere in the document.
    $hasSource =
        ($text -match '>\s*\*\*Source:\*\*\s*\S') -or
        ($text -match '\|\s*Source( page)?\s*\|\s*\S') -or
        ($text -match 'https://(learn\.microsoft\.com|aka\.ms)/\S')

    [pscustomobject]@{
        Path         = $Path
        Name         = Split-Path $Path -Leaf
        HasSource    = [bool]$hasSource
        Version      = $version
        ExtractedRaw = $extractedRaw
        HasMethod    = [bool]$hasMethod
    }
}

# BeforeDiscovery, not BeforeAll: Pester builds the -ForEach test-case list for every `It` below
# during Discovery, before any BeforeAll has run, so the file list has to be established during
# Discovery, not deferred to Run.
BeforeDiscovery {
    $discoveryRoot = Split-Path $PSScriptRoot -Parent
    $script:EnumerationFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $discoveryRoot 'docs/frameworks') -Filter '*.md' -File |
            Where-Object { $_.Name -ne 'README.md' }
    )
}

BeforeAll {
    # Recomputed rather than trusted from Discovery-time state: Pester's Discovery and Run phases
    # each get their own execution of this container, and neither variables nor functions set
    # outside a BeforeAll/BeforeDiscovery block reliably cross from one phase to the other in this
    # Pester version -- confirmed by the top-level Get-FrameworkFileFacts function above being
    # unavailable here. Re-declared rather than factored into a shared file to keep this test
    # self-contained; the two copies are identical and reviewed together.
    $script:Root             = Split-Path $PSScriptRoot -Parent
    $script:FrameworkDocsDir = Join-Path $script:Root 'docs/frameworks'
    $script:RulesDir         = Join-Path $script:Root 'src/assess/rules'
    $script:EnumerationFiles = @(
        Get-ChildItem -LiteralPath $script:FrameworkDocsDir -Filter '*.md' -File |
            Where-Object { $_.Name -ne 'README.md' }
    )

    function Get-FrameworkFileFacts {
        param([Parameter(Mandatory)] [string] $Path)

        $text = Get-Content -LiteralPath $Path -Raw

        $dateMatch = [regex]::Match($text, '>\s*\*\*Extracted:\*\*\s*(\d{4}-\d{2}-\d{2})')
        if (-not $dateMatch.Success) {
            $dateMatch = [regex]::Match($text, '\|\s*Extraction date\s*\|\s*(\d{4}-\d{2}-\d{2})')
        }
        if (-not $dateMatch.Success) {
            $dateMatch = [regex]::Match($text, '\*\*Enumerated\s+(\d{4}-\d{2}-\d{2})')
        }
        $extractedRaw = if ($dateMatch.Success) { $dateMatch.Groups[1].Value } else { $null }

        $versionMatch = [regex]::Match($text, '>\s*\*\*Framework version:\*\*\s*(\S.*)')
        if (-not $versionMatch.Success) {
            $versionMatch = [regex]::Match($text, '\|\s*Framework version\s*\|\s*(.+?)\s*\|')
        }
        if (-not $versionMatch.Success) {
            $versionMatch = [regex]::Match($text, '(?m)^\*\*Framework version:\*\*\s*(\S.*)$')
        }
        $version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value.Trim() } else { $null }

        $hasMethod =
            ($text -match '>\s*\*\*Verification method:\*\*\s*\S') -or
            ($text -match '\|\s*Verification method\s*\|\s*\S') -or
            ($text -match '(?m)^#{1,3}\s*Verification method\b')

        $hasSource =
            ($text -match '>\s*\*\*Source:\*\*\s*\S') -or
            ($text -match '\|\s*Source( page)?\s*\|\s*\S') -or
            ($text -match 'https://(learn\.microsoft\.com|aka\.ms)/\S')

        [pscustomobject]@{
            Path         = $Path
            Name         = Split-Path $Path -Leaf
            HasSource    = [bool]$hasSource
            Version      = $version
            ExtractedRaw = $extractedRaw
            HasMethod    = [bool]$hasMethod
        }
    }

    . (Join-Path $script:Root 'src/assess/engine/Get-RuleSet.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Resolve-JsonPath.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Invoke-Rule.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Get-Score.ps1')
    . (Join-Path $script:Root 'src/assess/Invoke-Assessment.ps1')

    # This test's own scratch space. Roughly eighteen files in this repo's test suite share
    # $env:TEMP and delete each other's directories when run in parallel -- give this file a
    # uniquely-named directory of its own and remove it in AfterAll, never touching $env:TEMP
    # directly.
    $script:ScratchDir = Join-Path ([System.IO.Path]::GetTempPath()) "azsc-frameworkcurrency-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:ScratchDir -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:ScratchDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'AB#6817 — every enumeration file names its source, version, date and method' {

    It 'found at least one enumeration file to check' {
        # If this is ever zero, every other It in this Describe passes vacuously. Assert the
        # precondition explicitly so a directory-layout regression is loud, not silent.
        $script:EnumerationFiles.Count | Should -BeGreaterThan 0
    }

    It '<Name> carries a Source URL' -ForEach (@($script:EnumerationFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })) {
        (Get-FrameworkFileFacts -Path $Path).HasSource | Should -BeTrue -Because "$Name must name where it was read from"
    }

    It '<Name> carries a non-empty Framework version' -ForEach (@($script:EnumerationFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })) {
        $facts = Get-FrameworkFileFacts -Path $Path
        $facts.Version | Should -Not -BeNullOrEmpty -Because "$Name must name the framework version it enumerates, even when that version is `"not versioned, extraction date is the version`""
    }

    It '<Name> carries a real, parseable extraction date' -ForEach (@($script:EnumerationFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })) {
        $facts = Get-FrameworkFileFacts -Path $Path
        $facts.ExtractedRaw | Should -Not -BeNullOrEmpty -Because "$Name must state when it was read"

        $parsed = [datetime]::MinValue
        $ok = [datetime]::TryParseExact($facts.ExtractedRaw, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref] $parsed)
        $ok | Should -BeTrue -Because "'$($facts.ExtractedRaw)' in $Name must be a real yyyy-MM-dd date"
    }

    It '<Name> carries a verification method' -ForEach (@($script:EnumerationFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })) {
        (Get-FrameworkFileFacts -Path $Path).HasMethod | Should -BeTrue -Because "$Name must state what was read and how"
    }
}

Describe 'AB#6817 — enumeration files must not be silently overdue for a recheck' {
    # Cadence is 90 days (docs/frameworks/README.md). A HARD test failure at exactly 90 days
    # would break CI on ordinary documentation lag rather than genuine staleness -- a doc review
    # running a few weeks behind schedule is not the failure this test exists to catch. The grace
    # period below is roughly four missed cycles (365 days): comfortably past "someone forgot the
    # quarterly pass" and into "this file has not been looked at in a year," which is exactly the
    # silent-drift case AB#6817 exists to prevent. The 90-day cadence itself is enforced by
    # process (README.md's recheck procedure), not by this tighter CI trigger.
    BeforeAll {
        $script:StaleAfterDays = 365
    }

    It "flags no file more than 365 days past its extraction date" {
        $today = [datetime]::Today
        $stale = foreach ($file in $script:EnumerationFiles) {
            $facts = Get-FrameworkFileFacts -Path $file.FullName
            if (-not $facts.ExtractedRaw) { continue }
            $parsed = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($facts.ExtractedRaw, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref] $parsed)) { continue }
            $ageDays = ($today - $parsed).Days
            if ($ageDays -gt $script:StaleAfterDays) {
                [pscustomobject]@{ Name = $facts.Name; AgeDays = $ageDays }
            }
        }

        $stale = @($stale)
        ($stale | ForEach-Object { "$($_.Name) is $($_.AgeDays) days old" }) -join '; ' |
            Should -BeNullOrEmpty -Because 'a file this old was never re-verified against docs/frameworks/README.md''s 90-day cadence -- see its recheck procedure'
    }
}

Describe 'AB#6817 — Get-RuleSet refuses to load a scored framework with no version' {
    # This is criterion 4's teeth: prove the gate actually rejects, using a real, disposable rule
    # file dropped into src/assess/rules (Get-RuleSet's rule directory is fixed relative to its
    # own script location, not parameterized, so this is the only way to exercise it against a
    # genuinely broken file rather than inspecting the source for the word "throw"). Both
    # fixtures are removed in AfterAll even if an assertion below fails.
    BeforeAll {
        $script:NoVersionFixture  = Join-Path $script:RulesDir 'zzz-ab6817-fixture-noversion.yaml'
        $script:VersionedFixture = Join-Path $script:RulesDir 'zzz-ab6817-fixture-versioned.yaml'

        @'
area: "AB6817 fixture"
framework: FIXTURE6817
weight: 1.0
rules:
  - id: FIX-1
    title: "fixture rule"
    severity: low
    query: "$.x[*]"
    assert: { type: countGreaterThan, value: 0 }
    remediation: "fixture"
    manual: false
'@ | Set-Content -LiteralPath $script:NoVersionFixture -Encoding utf8

        @'
area: "AB6817 fixture"
framework: FIXTURE6817
frameworkversion: "Fixture v1, verified 2026-08-01"
weight: 1.0
rules:
  - id: FIX-1
    title: "fixture rule"
    severity: low
    query: "$.x[*]"
    assert: { type: countGreaterThan, value: 0 }
    remediation: "fixture"
    manual: false
'@ | Set-Content -LiteralPath $script:VersionedFixture -Encoding utf8
    }

    AfterAll {
        Remove-Item -LiteralPath $script:NoVersionFixture  -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:VersionedFixture -ErrorAction SilentlyContinue
    }

    It 'throws loading a rule file that declares rules but no frameworkversion' {
        { Get-RuleSet -Patterns @('zzz-ab6817-fixture-noversion') } | Should -Throw -ExpectedMessage '*frameworkversion*'
    }

    It 'loads fine, and carries the version, when frameworkversion is declared' {
        $sets = @(Get-RuleSet -Patterns @('zzz-ab6817-fixture-versioned'))
        $sets.Count | Should -Be 1
        $sets[0].FrameworkVersion | Should -Be 'Fixture v1, verified 2026-08-01'
    }

    It 'a rule file declaring no rules at all is exempt (nothing to score, nothing to version)' {
        $emptyFixture = Join-Path $script:RulesDir 'zzz-ab6817-fixture-norules.yaml'
        try {
            @'
area: "AB6817 fixture, no rules"
framework: FIXTURE6817
weight: 1.0
rules: []
'@ | Set-Content -LiteralPath $emptyFixture -Encoding utf8

            { Get-RuleSet -Patterns @('zzz-ab6817-fixture-norules') } | Should -Not -Throw
        }
        finally {
            Remove-Item -LiteralPath $emptyFixture -ErrorAction SilentlyContinue
        }
    }

    It 'every real rule file under src/assess/rules loads without throwing and carries a version' {
        # Proves the 25 real rule files (not a synthetic fixture) actually satisfy the gate --
        # this is what makes the assertion above non-vacuous rather than just proving the guard
        # clause exists in isolation. Patterns name the real prefixes explicitly rather than '*'
        # so this assertion is unaffected by this Describe's own zzz-ab6817-fixture-* files still
        # sitting in the same directory (removed in this Describe's AfterAll, which has not run
        # yet at this point in the block).
        # NB: the assignment happens outside any nested scriptblock -- `{ $sets = ... } | Should
        # -Not -Throw` would assign $sets inside the scriptblock's own scope and leave it unset
        # here. If Get-RuleSet throws, this It simply fails with that exception, which is exactly
        # what "loads without throwing" should look like on failure.
        $sets = @(Get-RuleSet -Patterns @('caf.*', 'waf.*', 'smart.*', 'xr.*'))
        $sets.Count | Should -BeGreaterThan 0

        foreach ($set in $sets) {
            $set.FrameworkVersion | Should -Not -BeNullOrEmpty -Because "rule set for framework '$($set.Framework)' / area '$($set.Area)' must carry a version"
        }
    }
}

Describe 'AB#6817 — the version survives Invoke-Assessment and Get-Score end to end' {

    It 'stamps every finding with the rule set''s FrameworkVersion' {
        $ruleSet = @(
            [pscustomobject]@{
                Area = 'A'; Framework = 'FIXTURE'; FrameworkVersion = 'Fixture v1'
                Weight = 1.0; Requires = @()
                Rules = @(
                    @{ id = 'F1'; title = 't'; severity = 'low'; query = '$.items[*]'; assert = @{ type = 'countGreaterThan'; value = 0 }; remediation = 'r'; manual = $false }
                )
            }
        )
        $collect  = [pscustomobject]@{ items = @(1, 2) }
        $findings = Invoke-Assessment -Collect $collect -RuleSet $ruleSet -Assessment 'FixtureTest'

        @($findings).Count | Should -Be 1
        $findings[0].FrameworkVersion | Should -Be 'Fixture v1'
    }

    It 'Get-Score carries Version onto both the Areas and Frameworks roll-ups' {
        $findings = @(
            [pscustomobject]@{
                Id = 'F1'; Title = 't'; Framework = 'FIXTURE'; Area = 'A'; Severity = 'medium'
                Status = 'Pass'; EvidenceCount = 1; Evidence = @(); Remediation = 'r'; Manual = $false
                AreaWeight = 1.0; FrameworkVersion = 'Fixture v1, verified 2026-08-01'
            }
        )
        $score = Get-Score -Findings $findings

        ($score.Areas      | Where-Object Area      -eq 'A').Version       | Should -Be 'Fixture v1, verified 2026-08-01'
        ($score.Frameworks | Where-Object Framework -eq 'FIXTURE').Version | Should -Be 'Fixture v1, verified 2026-08-01'
    }

    It 'does NOT fabricate a version when a finding carries none — Get-RuleSet is the gate, Get-Score is honest about what it was given' {
        $findings = @(
            [pscustomobject]@{
                Id = 'F1'; Title = 't'; Framework = 'FIXTURE'; Area = 'A'; Severity = 'medium'
                Status = 'Pass'; EvidenceCount = 1; Evidence = @(); Remediation = 'r'; Manual = $false
                AreaWeight = 1.0
            }
        )
        $score = Get-Score -Findings $findings

        ($score.Frameworks | Where-Object Framework -eq 'FIXTURE').Version | Should -BeNullOrEmpty
        # This is exactly the state Get-RuleSet's load-time guard exists to make unreachable in
        # production: a finding with a Score but no Version. See the "refuses to load" Describe
        # above for the actual rejection.
    }
}
