#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300 phase 5: four questionnaire assessments for Microsoft products Scout cannot read -- Data Security
    for Copilot for Microsoft 365, the Microsoft Sustainability Manager (now Dynamics 365 Sustainability)
    Well-Architected assessment, the Microsoft Cloud for Financial Services (now Microsoft for Financial
    Services) Well-Architected for Industry assessment, and the Windows 11 Pro Migration Readiness Assessment.

    Microsoft does not publish these assessments' question text, and Scout holds no Microsoft 365, Dataverse
    or client device data, so every rule is Scout-derived and `manual: true` with `query: null`, answered
    through -AssessmentAnswers. Pinned here:
      - rule ids are unique inside each file and across every rule file, each is enumerated in its
        docs/frameworks page (and the page lists nothing else), and title and remediation start with the id;
      - every rule is a manual question: no query, assert type manual, no evidence that could be mistaken for
        data (in particular nothing for Windows 11 is read from Arc-enabled servers or Azure VMs);
      - every manual rule is exported as a question by Get-ScoutAssessmentQuestion, and answering the
        questions scores them (Set-ScoutFindingAnswer then Get-Score);
      - an empty collect produces no Error findings and leaves every rule Manual.

    The collect object below is built here from the collect.json contract in src/collect/Invoke-Collect.ps1.
    It is not captured from a live estate.
#>

BeforeDiscovery {
    $script:SetCases = @(
        @{ Name = 'Microsoft: M365 Copilot Data Security'; Pattern = 'm365.copilot.datasecurity'; Framework = 'M365-COPILOT-DATASEC'; Area = 'Microsoft 365 Copilot data security'; Doc = 'm365-copilot-data-security-question-set.md'; Prefix = 'M365CP'
            Total = 40; AreaCounts = @{ RO = 11; SL = 6; GR = 9; AU = 5; RG = 5; AG = 4 } }
        @{ Name = 'Microsoft: Sustainability Manager Well-Architected'; Pattern = 'msm.wellarchitected'; Framework = 'MSM-WAF'; Area = 'Sustainability Manager well-architected'; Doc = 'sustainability-manager-well-architected-question-set.md'; Prefix = 'MSM'
            Total = 47; AreaCounts = @{ CF = 8; DI = 8; EX = 4; SE = 8; OB = 5; PC = 4; RP = 4; PI = 4; IT = 2 } }
        @{ Name = 'Microsoft: Cloud for Financial Services Well-Architected'; Pattern = 'mcfs.wellarchitected'; Framework = 'MCFS-WAF'; Area = 'Cloud for Financial Services well-architected'; Doc = 'cloud-for-financial-services-question-set.md'; Prefix = 'MCFS'
            Total = 40; AreaCounts = @{ RE = 7; SE = 9; CO = 4; OE = 5; PE = 4; CE = 5; GV = 6 } }
        @{ Name = 'Microsoft: Windows 11 Migration Readiness'; Pattern = 'win11.readiness'; Framework = 'WIN11-READINESS'; Area = 'Windows 11 migration readiness'; Doc = 'windows-11-readiness-question-set.md'; Prefix = 'WIN11'
            Total = 34; AreaCounts = @{ PL = 6; HW = 8; AP = 5; MG = 7; SC = 4; OP = 4 } }
    )
}

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml

    # The real manifests/assessments.psd1 entries are added by the caller; the questionnaire export is
    # exercised here against an equivalent manifest built in the test.
    $script:Manifest = @{
        'Microsoft: M365 Copilot Data Security'                    = @{ Rules = @('m365.copilot.datasecurity'); Category = '*'; Collect = @('Management'); Ingest = @() }
        'Microsoft: Sustainability Manager Well-Architected'       = @{ Rules = @('msm.wellarchitected'); Category = '*'; Collect = @('Management'); Ingest = @() }
        'Microsoft: Cloud for Financial Services Well-Architected' = @{ Rules = @('mcfs.wellarchitected'); Category = '*'; Collect = @('Management'); Ingest = @() }
        'Microsoft: Windows 11 Migration Readiness'                = @{ Rules = @('win11.readiness'); Category = '*'; Collect = @('Management'); Ingest = @() }
    }

    function Invoke-ScoutTestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    # A collect with every top-level key a rule could query, all empty: the shape of an estate with nothing in
    # it, and of a scan that read no Microsoft 365, Dataverse or device data.
    $script:Empty = [ordered]@{
        subscriptions = @(); tags = @()
        governance    = [ordered]@{ policyAssignments = @(); policyAssignmentsAvailable = $false; resourceLocks = @(); resourceLocksAvailable = $false; budgets = @(); budgetsAvailable = $false; roleAssignments = @(); roleAssignmentsAvailable = $false; managementGroups = @() }
        security      = [ordered]@{ defenderPlans = @() }
        compute       = [ordered]@{ virtualMachines = @() }
        networking    = [ordered]@{ virtualNetworks = @() }
        management    = [ordered]@{ deployments = @(); logAnalyticsWorkspaces = @() }
        domains       = [ordered]@{
            identity = [ordered]@{ managedIdentities = @() }
            hybrid   = [ordered]@{ arcServers = @() }
        }
    }

    # Per set: the loaded rule set, the findings on the empty collect and the doc text.
    $script:Run = @{}
    foreach ($case in @(
            @{ Name = 'Microsoft: M365 Copilot Data Security'; Pattern = 'm365.copilot.datasecurity' }
            @{ Name = 'Microsoft: Sustainability Manager Well-Architected'; Pattern = 'msm.wellarchitected' }
            @{ Name = 'Microsoft: Cloud for Financial Services Well-Architected'; Pattern = 'mcfs.wellarchitected' }
            @{ Name = 'Microsoft: Windows 11 Migration Readiness'; Pattern = 'win11.readiness' })) {
        $script:Run[$case.Pattern] = @{
            Set      = @(& $script:Module { param($p) Get-RuleSet -Patterns $p } $case.Pattern)
            Findings = @(Invoke-ScoutTestRuleSet -Pattern $case.Pattern -Collect $script:Empty -Assessment $case.Name)
        }
    }
}

Describe 'Microsoft product assessments - rule file shape' {
    It '<Name> loads one rule set for framework <Framework> with <Total> rules' -ForEach $script:SetCases {
        $set = $script:Run[$Pattern].Set
        $set.Count | Should -Be 1
        $set[0].Framework | Should -Be $Framework
        $set[0].Area | Should -Be $Area
        $set[0].FrameworkVersion | Should -BeLike '*verified 2026-11-25*'
        $set[0].FrameworkVersion | Should -BeLike "*docs/frameworks/$Doc*"
        @($set[0].Rules).Count | Should -Be $Total
        @($set[0].Rules.id | Select-Object -Unique).Count | Should -Be $Total
    }

    It '<Name> declares the questionnaire-only header keys the other questionnaire files carry' -ForEach $script:SetCases {
        $doc = ConvertFrom-Yaml (Get-Content "$script:root/src/assess/rules/$Pattern.yaml" -Raw)
        foreach ($key in 'area', 'framework', 'frameworkversion', 'weight', 'verifiedAgainst', 'rules') { $doc.ContainsKey($key) | Should -BeTrue -Because $key }
        [double]$doc.weight | Should -Be 1.0
        $doc.verifiedAgainst | Should -BeLike '*Scout-derived*'
        $doc.verifiedAgainst | Should -BeLike '*verified 2026-11-25*'
    }

    It '<Name> has only manual rules: no query, assert type manual, manual flag set' -ForEach $script:SetCases {
        foreach ($r in $script:Run[$Pattern].Set[0].Rules) {
            $r.manual | Should -BeTrue -Because $r.id
            $r.assert.type | Should -Be 'manual' -Because $r.id
            $r.query | Should -BeNullOrEmpty -Because "$($r.id) must not read data that Scout does not collect"
        }
    }

    It '<Name> title and remediation start with the rule id, and every severity is valid' -ForEach $script:SetCases {
        foreach ($r in $script:Run[$Pattern].Set[0].Rules) {
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
            $r.severity | Should -BeIn 'high', 'medium', 'low'
        }
    }

    It '<Name> covers each group with the expected number of items' -ForEach $script:SetCases {
        $rules = @($script:Run[$Pattern].Set[0].Rules)
        foreach ($k in $AreaCounts.Keys) {
            @($rules | Where-Object { ([string]$_.id -split '-')[-2] -eq $k }).Count | Should -Be $AreaCounts[$k] -Because "group $k"
        }
        ($AreaCounts.Values | Measure-Object -Sum).Sum | Should -Be $Total
    }

    It '<Name> has every rule id enumerated in docs/frameworks/<Doc>, and the doc enumerates nothing else' -ForEach $script:SetCases {
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        $ids = @($script:Run[$Pattern].Set[0].Rules | ForEach-Object { [string]$_.id })
        foreach ($id in $ids) { $doc | Should -Match ([regex]::Escape($id)) }
        $docIds = @([regex]::Matches($doc, "\b$Prefix-[A-Z]{2}-\d{2}\b") | ForEach-Object Value | Select-Object -Unique)
        $docIds.Count | Should -Be $Total
        @($docIds | Where-Object { $_ -notin $ids }).Count | Should -Be 0
    }

    It '<Name> doc carries the Shape B header, says the questions are Scout-derived and names what an automated version needs' -ForEach $script:SetCases {
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        $doc | Should -Match '\*\*Enumerated 2026-11-25\. Verification method and limits are stated below .{1,3} read them before quoting'
        $doc | Should -Match '(?m)^any coverage number from this page\.\*\*$'
        $doc | Should -Match '\| Field \| Value \|'
        $doc | Should -Match '\| Framework version \|'
        $doc | Should -Match '\| Extraction date \| 2026-11-25 \|'
        $doc | Should -Match '\| Verification method \|'
        $doc | Should -Match 'Scout-derived'
        $doc | Should -Match 'Scout does not read this product'
        $doc | Should -Match '(?m)^## What an automated version would need$'
        $doc | Should -Match '(?m)^## Product status$'
        $doc | Should -Match 'https://learn\.microsoft\.com/en-us/assessments/[0-9a-f-]{36}/'
    }

    It '<Name> doc names a Microsoft Graph or product API an automated version would call' -ForEach $script:SetCases {
        $doc = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
        $section = ($doc -split '(?m)^## What an automated version would need$')[1]
        $section | Should -Not -BeNullOrEmpty
        $section | Should -Match 'GET /|POST /|Web API|PowerShell'
    }

    It 'names no tenant, subscription or client identifier in the rule files or docs' -ForEach $script:SetCases {
        $text = (Get-Content "$script:root/src/assess/rules/$Pattern.yaml" -Raw) + (Get-Content "$script:root/docs/frameworks/$Doc" -Raw)
        # The only GUIDs allowed are the public Microsoft Learn assessment ids inside learn.microsoft.com URLs.
        $stripped = [regex]::Replace($text, 'learn\.microsoft\.com/(?:en-us/)?assessments/[0-9a-f-]{36}', 'ASSESSMENT')
        $stripped | Should -Not -Match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    }
}

Describe 'Microsoft product assessments - ids are unique across every rule file' {
    It 'no rule id is used twice anywhere under src/assess/rules' {
        $seen = @{}
        $dupes = [System.Collections.Generic.List[string]]::new()
        foreach ($file in Get-ChildItem "$script:root/src/assess/rules" -Filter '*.yaml' -File) {
            $doc = ConvertFrom-Yaml (Get-Content $file.FullName -Raw)
            if ($null -eq $doc -or -not $doc.ContainsKey('rules')) { continue }
            foreach ($rule in @($doc.rules)) {
                $id = [string]$rule.id
                if ($seen.ContainsKey($id)) { $dupes.Add("$id ($($seen[$id]) and $($file.Name))") } else { $seen[$id] = $file.Name }
            }
        }
        $dupes | Should -BeNullOrEmpty
    }

    It '<Name> uses only ids that start with <Prefix>-' -ForEach $script:SetCases {
        $ids = @($script:Run[$Pattern].Set[0].Rules | ForEach-Object { [string]$_.id })
        $ids.Count | Should -Be $Total
        foreach ($id in $ids) { $id.StartsWith("$Prefix-", [System.StringComparison]::Ordinal) | Should -BeTrue -Because $id }
    }

    It 'no other rule file uses the M365CP-, MSM-, MCFS- or WIN11- prefixes' {
        $own = @('m365.copilot.datasecurity', 'msm.wellarchitected', 'mcfs.wellarchitected', 'win11.readiness')
        $stray = [System.Collections.Generic.List[string]]::new()
        foreach ($file in Get-ChildItem "$script:root/src/assess/rules" -Filter '*.yaml' -File | Where-Object { $_.BaseName -notin $own }) {
            $doc = ConvertFrom-Yaml (Get-Content $file.FullName -Raw)
            if ($null -eq $doc -or -not $doc.ContainsKey('rules')) { continue }
            foreach ($rule in @($doc.rules)) { if ([string]$rule.id -match '^(M365CP|MSM|MCFS|WIN11)-') { $stray.Add("$($rule.id) in $($file.Name)") } }
        }
        $stray | Should -BeNullOrEmpty
    }
}

Describe 'Microsoft product assessments - manual questions export and score' {
    It '<Name> exports every rule exactly once through Get-ScoutAssessmentQuestion' -ForEach $script:SetCases {
        $rows = @(& $script:Module { param($n, $m) Get-ScoutAssessmentQuestion -Assessment $n -Manifest $m } $Name $script:Manifest)
        $rows.Count | Should -Be $Total
        @($rows.RuleId | Select-Object -Unique).Count | Should -Be $Total
        $manualIds = @($script:Run[$Pattern].Set[0].Rules | Where-Object { $_.manual } | ForEach-Object { [string]$_.id })
        foreach ($row in $rows) {
            $row.RuleId | Should -BeIn $manualIds
            $row.Question | Should -BeLike "$($row.RuleId). *"
            $row.Guidance | Should -BeLike "$($row.RuleId). *"
            $row.Framework | Should -Be $Framework
            $row.Area | Should -Be $Area
            $row.Assessment | Should -Be $Name
        }
    }

    It '<Name> leaves every rule Manual and out of the score until it is answered' -ForEach $script:SetCases {
        $findings = @($script:Run[$Pattern].Findings)
        $findings.Count | Should -Be $Total
        @($findings | Where-Object Status -eq 'Manual').Count | Should -Be $Total
        $score = & $script:Module { param($f) Get-Score -Findings $f } $findings
        $area = @($score.Areas | Where-Object Area -eq $Area)[0]
        $area.Manual | Should -Be $Total
    }

    It '<Name> scores answered questions: all Yes is 100, all No is 0, a mix is between, N/A is left out' -ForEach $script:SetCases {
        $manualIds = @($script:Run[$Pattern].Set[0].Rules | Where-Object { $_.manual } | ForEach-Object { [string]$_.id })
        $makeAnswers = {
            param([scriptblock] $Pick)
            $a = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
            $n = 0
            foreach ($id in $manualIds) {
                $word, $status = & $Pick $n
                $a[$id] = @{ Answer = $word; Status = $status; Note = ''; AnsweredBy = ''; AnsweredAt = '' }
                $n++
            }
            $a
        }
        $score = {
            param($Answers)
            $fresh = @(Invoke-ScoutTestRuleSet -Pattern $Pattern -Collect $script:Empty -Assessment $Name)
            $answered = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } $fresh $Answers)
            $result = & $script:Module { param($f) Get-Score -Findings $f } $answered
            [pscustomobject]@{ Findings = $answered; Area = @($result.Areas | Where-Object Area -eq $Area)[0] }
        }

        $yes = & $score (& $makeAnswers { 'Yes', 'Pass' })
        $yes.Area.Score | Should -Be 100
        $yes.Area.Manual | Should -Be 0
        @($yes.Findings | Where-Object { $_.Manual -and $_.Source -eq 'Answer' }).Count | Should -Be $Total

        $no = & $score (& $makeAnswers { 'No', 'Fail' })
        $no.Area.Score | Should -Be 0

        $mix = & $score (& $makeAnswers { param($n) if ($n % 2) { 'Yes', 'Pass' } else { 'No', 'Fail' } })
        $mix.Area.Score | Should -BeGreaterThan 0
        $mix.Area.Score | Should -BeLessThan 100

        $na = & $score (& $makeAnswers { param($n) if ($n -eq 0) { 'N/A', 'NotApplicable' } else { 'Yes', 'Pass' } })
        @($na.Findings | Where-Object { $_.Id -eq $manualIds[0] })[0].Status | Should -Be 'NotAssessed'
        $na.Area.Score | Should -Be 100
    }

    It '<Name> is reported under its own framework, with the verified version, once a question is answered' -ForEach $script:SetCases {
        $firstId = [string]$script:Run[$Pattern].Set[0].Rules[0].id
        $answers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $answers[$firstId] = @{ Answer = 'Yes'; Status = 'Pass'; Note = ''; AnsweredBy = ''; AnsweredAt = '' }
        $answered = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } @($script:Run[$Pattern].Findings) $answers)
        $score = & $script:Module { param($f) Get-Score -Findings $f } $answered
        @($score.Frameworks | Where-Object Framework -eq $Framework).Count | Should -Be 1
        (@($score.Frameworks | Where-Object Framework -eq $Framework)[0]).Version | Should -BeLike '*verified 2026-11-25*'
    }
}

Describe 'Microsoft product assessments - no evidence from data Scout does not hold' {
    It '<Name> produces no Error findings on an empty collect' -ForEach $script:SetCases {
        @($script:Run[$Pattern].Findings | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It '<Name> attaches no evidence to any finding' -ForEach $script:SetCases {
        foreach ($f in $script:Run[$Pattern].Findings) { $f.EvidenceCount | Should -Be 0 -Because $f.Id }
    }

    It 'Windows 11 readiness does not use Arc-enabled servers or Azure VMs as evidence for client devices' {
        $rules = @($script:Run['win11.readiness'].Set[0].Rules)
        foreach ($r in $rules) {
            [string]$r.query | Should -BeNullOrEmpty -Because $r.id
            ([string]$r.title + [string]$r.remediation) | Should -Not -Match 'arcServers|virtualMachines'
        }
        $withArc = [ordered]@{}
        foreach ($k in $script:Empty.Keys) { $withArc[$k] = $script:Empty[$k] }
        $withArc.domains = [ordered]@{ identity = [ordered]@{ managedIdentities = @() }; hybrid = [ordered]@{ arcServers = @([ordered]@{ id = 'arc1'; name = 'arc1' }) } }
        $withArc.compute = [ordered]@{ virtualMachines = @([ordered]@{ id = 'vm1'; name = 'vm1' }) }
        $f = @(Invoke-ScoutTestRuleSet -Pattern 'win11.readiness' -Collect $withArc -Assessment 'Microsoft: Windows 11 Migration Readiness')
        @($f | Where-Object { $_.Status -ne 'Manual' }).Count | Should -Be 0
        @($f | Where-Object { $_.EvidenceCount -gt 0 }).Count | Should -Be 0
    }
}
