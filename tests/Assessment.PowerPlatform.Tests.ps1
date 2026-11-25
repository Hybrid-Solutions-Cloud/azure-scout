#Requires -Version 7.0
#Requires -Modules Pester

<#
    Power Platform assessments (AB#9300, "run every known assessment", phase 5): Microsoft's Power
    Platform Well-Architected, Solution and Adoption assessments, scored as questionnaires.

    Scout does not read Power Platform data yet, so every rule in pp.wellarchitected.yaml,
    pp.solution.yaml and pp.adoption.yaml is manual with no query. These tests pin the properties that
    keep that honest: unique ids, an id at the start of every title and remediation, every id present in
    its docs/frameworks page, every question reaching the questionnaire export, answered questions
    scoring, and an empty collection producing no Errors (a manual question must never read as a
    failure just because nothing was collected).
#>

BeforeDiscovery {
    $discoveryRoot = Split-Path $PSScriptRoot -Parent
    $script:FileCases = @(
        @{ Name = 'pp.wellarchitected'; Prefix = 'PPWAF'; Framework = 'PP-WAF'; Doc = 'power-platform-well-architected-checklist.md'; Count = 49; Root = $discoveryRoot }
        @{ Name = 'pp.solution'; Prefix = 'PPSOL'; Framework = 'PP-SOLUTION'; Doc = 'power-platform-solution-question-set.md'; Count = 37; Root = $discoveryRoot }
        @{ Name = 'pp.adoption'; Prefix = 'PPADOPT'; Framework = 'PP-ADOPTION'; Doc = 'power-platform-adoption-question-set.md'; Count = 41; Root = $discoveryRoot }
    )
}

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:ruleDir = Join-Path $script:root 'src/assess/rules'
    Import-Module powershell-yaml -ErrorAction Stop
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1

    # Every rule file in the repo, parsed once: the uniqueness check has to look at all of them.
    $script:allRules = foreach ($f in Get-ChildItem -LiteralPath $script:ruleDir -Filter '*.yaml' -File) {
        $doc = ConvertFrom-Yaml (Get-Content -LiteralPath $f.FullName -Raw)
        if ($null -eq $doc -or -not $doc.ContainsKey('rules')) { continue }
        foreach ($r in @($doc.rules)) { if ($null -ne $r -and $r.ContainsKey('id')) { [pscustomobject]@{ File = $f.BaseName; Id = [string]$r.id } } }
    }

    # The manifest is built here, not read from manifests/assessments.psd1, so this test does not depend
    # on the catalogue entries having been added yet. The shape is what the real entries must match.
    $script:manifest = @{
        'Microsoft: Power Platform Well-Architected' = @{
            Description = 'Power Platform Well-Architected (questionnaire)'; Category = '*'; Collect = @('Management'); Ingest = @()
            Rules = @('pp.wellarchitected'); Frameworks = @('PP-WAF: 5 pillars'); Tags = @('power-platform', 'well-architected', 'questionnaire'); Reporters = @('Html', 'Excel')
        }
        'Microsoft: Power Platform Solution'        = @{
            Description = 'Power Platform Solution Assessment (questionnaire)'; Category = '*'; Collect = @('Management'); Ingest = @()
            Rules = @('pp.solution'); Frameworks = @('PP-SOLUTION'); Tags = @('power-platform', 'solution', 'questionnaire'); Reporters = @('Html', 'Excel')
        }
        'Microsoft: Power Platform Adoption'        = @{
            Description = 'Power Platform Adoption Assessment (questionnaire)'; Category = '*'; Collect = @('Management'); Ingest = @()
            Rules = @('pp.adoption'); Frameworks = @('PP-ADOPTION'); Tags = @('power-platform', 'adoption', 'questionnaire'); Reporters = @('Html', 'Excel')
        }
    }

    function Get-PpDoc {
        param([string] $Name)
        ConvertFrom-Yaml (Get-Content -LiteralPath (Join-Path $script:ruleDir "$Name.yaml") -Raw)
    }
}

Describe 'Power Platform rule file <Name>' -ForEach $script:FileCases {
    BeforeAll {
        $script:ruleDoc = Get-PpDoc -Name $Name
        $script:rules = @($script:ruleDoc.rules)
        $script:docText = Get-Content -LiteralPath (Join-Path $script:root "docs/frameworks/$Doc") -Raw
    }

    It 'declares the framework, area, a verified version, a weight and what it was verified against' {
        $script:ruleDoc.framework | Should -Be $Framework
        $script:ruleDoc.area | Should -Not -BeNullOrEmpty
        [string]$script:ruleDoc.frameworkversion | Should -Match 'verified 2026-11-25'
        [double]$script:ruleDoc.weight | Should -BeGreaterThan 0
        [string]$script:ruleDoc.verifiedAgainst | Should -Match 'verified 2026-11-25'
        [string]$script:ruleDoc.verifiedAgainst | Should -Match "docs/frameworks/$([regex]::Escape($Doc))"
    }

    It 'has the enumerated number of rules' {
        $script:rules.Count | Should -Be $Count
    }

    It 'uses only the <Prefix>- id prefix, and ids are unique inside the file' {
        $ids = @($script:rules | ForEach-Object { [string]$_.id })
        @($ids | Where-Object { $_ -notlike "$Prefix-*" }) | Should -BeNullOrEmpty
        @($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'has ids that appear exactly once across every rule file in the repo' {
        $mine = @($script:rules | ForEach-Object { [string]$_.id })
        $dupes = @($script:allRules | Where-Object { $_.Id -in $mine } | Group-Object Id | Where-Object Count -gt 1)
        ($dupes | ForEach-Object { "$($_.Name) in $(($_.Group.File | Sort-Object -Unique) -join ', ')" }) -join '; ' | Should -BeNullOrEmpty
    }

    It 'makes every rule a manual question with no query' {
        foreach ($r in $script:rules) {
            $r.manual | Should -BeTrue -Because "$($r.id) must be manual: Scout does not read Power Platform data"
            $r.query | Should -BeNullOrEmpty -Because "$($r.id) has no collect.json path to query"
            [string]$r.assert.type | Should -Be 'manual'
            [string]$r.severity | Should -BeIn 'low', 'medium', 'high', 'critical'
        }
    }

    It 'starts every title and remediation with the rule id' {
        foreach ($r in $script:rules) {
            ([string]$r.title).StartsWith([string]$r.id) | Should -BeTrue -Because "title of $($r.id)"
            ([string]$r.remediation).StartsWith([string]$r.id) | Should -BeTrue -Because "remediation of $($r.id)"
        }
    }

    It 'lists every rule id in docs/frameworks/<Doc>, one table row each' {
        foreach ($r in $script:rules) {
            $script:docText | Should -Match "(?m)^\| $([regex]::Escape([string]$r.id)) \|" -Because "$($r.id) must be enumerated in the docs page"
        }
        @([regex]::Matches($script:docText, "(?m)^\| $Prefix-")).Count | Should -Be $script:rules.Count
    }

    It 'says the questions are Scout-derived, that Scout does not read Power Platform data yet, and what automation would need' {
        $script:docText | Should -Match 'Scout-derived'
        $script:docText | Should -Match 'Scout does not read Power Platform data yet'
        $script:docText | Should -Match '## What an automated version would need'
        $script:docText | Should -Match 'api\.powerplatform\.com'
    }

    It 'carries the Shape B header: Enumerated lede and a Field/Value Source table' {
        $script:docText | Should -Match '\*\*Enumerated 2026-11-25\.'
        $script:docText | Should -Match '(?m)^\| Field \| Value \|'
        $script:docText | Should -Match '(?m)^\| Framework version \| \S'
        $script:docText | Should -Match '(?m)^\| Extraction date \| 2026-11-25 \|'
        $script:docText | Should -Match '(?m)^\| Verification method \| \S'
    }
}

Describe 'Power Platform Well-Architected cites Microsoft checklist codes' {
    BeforeAll {
        $script:waf = @((Get-PpDoc -Name 'pp.wellarchitected').rules)
        $script:wafDoc = Get-Content -LiteralPath (Join-Path $script:root 'docs/frameworks/power-platform-well-architected-checklist.md') -Raw
    }

    It 'covers <Pillar> items 01 to <Last> exactly' -ForEach @(
        @{ Pillar = 'RE'; Last = 8 }, @{ Pillar = 'SE'; Last = 10 }, @{ Pillar = 'OE'; Last = 11 }
        @{ Pillar = 'PE'; Last = 10 }, @{ Pillar = 'XO'; Last = 10 }
    ) {
        $got = @($script:waf | Where-Object { $_.id -like "PPWAF-$Pillar-*" } | ForEach-Object { [int]($_.id -replace '^.*-', '') } | Sort-Object)
        $got | Should -Be @(1..$Last)
    }

    It 'names the matching Microsoft checklist code in each remediation and links it in the docs' {
        foreach ($r in $script:waf) {
            $parts = ([string]$r.id).Split('-')
            $code = '{0}:{1}' -f $parts[1], $parts[2]
            ([string]$r.remediation) | Should -Match "\(Microsoft checklist item $code\)\." -Because $r.id
            $script:wafDoc | Should -Match "\[$code\]\(https://learn\.microsoft\.com/power-platform/well-architected/" -Because "$($r.id) must link its checklist code"
        }
    }
}

Describe 'Power Platform questions reach the questionnaire' {
    It 'exports every rule of <Assessment> once, as a manual question' -ForEach @(
        @{ Assessment = 'Microsoft: Power Platform Well-Architected'; File = 'pp.wellarchitected'; Prefix = 'PPWAF'; Framework = 'PP-WAF' }
        @{ Assessment = 'Microsoft: Power Platform Solution'; File = 'pp.solution'; Prefix = 'PPSOL'; Framework = 'PP-SOLUTION' }
        @{ Assessment = 'Microsoft: Power Platform Adoption'; File = 'pp.adoption'; Prefix = 'PPADOPT'; Framework = 'PP-ADOPTION' }
    ) {
        $expected = @((Get-PpDoc -Name $File).rules)
        $rows = @(& $script:Module { param($a, $m) Get-ScoutAssessmentQuestion -Assessment $a -Manifest $m } $Assessment $script:manifest)
        $rows.Count | Should -Be $expected.Count
        @($rows.RuleId | Select-Object -Unique).Count | Should -Be $rows.Count
        @($rows | Where-Object { $_.RuleId -notlike "$Prefix-*" }) | Should -BeNullOrEmpty
        @($rows | Where-Object { -not $_.Question }) | Should -BeNullOrEmpty
        @($rows | Where-Object { -not $_.Guidance.StartsWith($_.RuleId) }) | Should -BeNullOrEmpty
        @($rows | Where-Object { $_.Framework -ne $Framework }) | Should -BeNullOrEmpty
        @($rows | Where-Object { $_.Assessment -ne $Assessment }) | Should -BeNullOrEmpty
    }
}

Describe 'Power Platform assessments on an empty collection' {
    BeforeAll {
        # An empty collect object stands in for "Scout has no Power Platform data": the real situation.
        $script:empty = & $script:Module {
            $rs = @(Get-RuleSet -Patterns @('pp.wellarchitected', 'pp.solution', 'pp.adoption'))
            $f = @(Invoke-Assessment -Collect ([pscustomobject]@{}) -RuleSet $rs -Assessment 'PowerPlatformTest')
            , $f
        }
        $script:emptyFindings = @($script:empty)
    }

    It 'produces a finding for every rule and none of them is an Error, Unknown or NotAssessed' {
        $script:emptyFindings.Count | Should -Be (49 + 37 + 41)
        @($script:emptyFindings | Where-Object Status -in 'Error', 'Unknown', 'NotAssessed', 'Fail', 'Pass') | Should -BeNullOrEmpty
        @($script:emptyFindings | Where-Object { $_.Status -ne 'Manual' }) | Should -BeNullOrEmpty
        @($script:emptyFindings | Where-Object { -not $_.Manual }) | Should -BeNullOrEmpty
    }

    It 'scores with no Errors and leaves every unanswered question out of the score' {
        $score = & $script:Module { param($f) Get-Score -Findings $f } $script:emptyFindings
        @($score.Errors).Count | Should -Be 0
        @($score.Areas).Count | Should -Be 3
        (@($score.Areas) | Measure-Object -Property Manual -Sum).Sum | Should -Be $script:emptyFindings.Count
        foreach ($a in @($score.Areas)) { $a.Score | Should -BeNullOrEmpty -Because "$($a.Area) has no answered question" }
    }

    It 'scores answered questions through Set-ScoutFindingAnswer and marks them as answers' -ForEach @(
        @{ Framework = 'PP-WAF'; Area = 'Power Platform Well-Architected'; Prefix = 'PPWAF' }
        @{ Framework = 'PP-SOLUTION'; Area = 'Power Platform Solution'; Prefix = 'PPSOL' }
        @{ Framework = 'PP-ADOPTION'; Area = 'Power Platform Adoption'; Prefix = 'PPADOPT' }
    ) {
        $mine = @($script:emptyFindings | Where-Object { $_.Id -like "$Prefix-*" })
        # Two questions of the same severity, one met and one not met, so the area scores 50 percent.
        $sev = ($mine | Group-Object Severity | Sort-Object Count -Descending | Select-Object -First 1).Name
        $pair = @($mine | Where-Object Severity -eq $sev | Select-Object -First 2)
        $pair.Count | Should -Be 2
        $answers = @{}
        $answers[[string]$pair[0].Id] = @{ Answer = 'Yes'; Status = 'Pass'; Note = 'documented'; AnsweredBy = 'test'; AnsweredAt = '2026-11-25' }
        $answers[[string]$pair[1].Id] = @{ Answer = 'No'; Status = 'Fail'; Note = ''; AnsweredBy = ''; AnsweredAt = '' }

        $scored = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } $mine $answers)
        $scored.Count | Should -Be $mine.Count
        ($scored | Where-Object Id -eq $pair[0].Id).Status | Should -Be 'Pass'
        ($scored | Where-Object Id -eq $pair[0].Id).Source | Should -Be 'Answer'
        ($scored | Where-Object Id -eq $pair[1].Id).Status | Should -Be 'Fail'
        @($scored | Where-Object Source -eq 'Unanswered').Count | Should -Be ($mine.Count - 2)

        $score = & $script:Module { param($f) Get-Score -Findings $f } $scored
        $area = @($score.Areas | Where-Object Area -eq $Area)[0]
        $area.Score | Should -Be 50
        $area.Manual | Should -Be ($mine.Count - 2)
        @($score.Errors).Count | Should -Be 0
        $area.Version | Should -Match 'verified 2026-11-25'
    }

    It 'leaves a question answered N/A out of the score and keeps the rest scoring' {
        $mine = @($script:emptyFindings | Where-Object { $_.Id -like 'PPADOPT-*' })
        $answers = @{}
        $answers[[string]$mine[0].Id] = @{ Answer = 'N/A'; Status = 'NotApplicable'; Note = 'no CoE needed'; AnsweredBy = ''; AnsweredAt = '' }
        $answers[[string]$mine[1].Id] = @{ Answer = 'Yes'; Status = 'Pass'; Note = ''; AnsweredBy = ''; AnsweredAt = '' }
        $scored = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } $mine $answers)
        ($scored | Where-Object Id -eq $mine[0].Id).Status | Should -Be 'NotAssessed'
        ($scored | Where-Object Id -eq $mine[1].Id).Status | Should -Be 'Pass'
    }
}
