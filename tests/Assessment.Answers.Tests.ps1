#Requires -Version 7.0
#Requires -Modules Pester

<#
    Questionnaire answers for manual assessment questions (AB#9300, "run every known assessment",
    phase 0). Manual questions used to be permanently Status = Manual and excluded from the score;
    an answer file now scores them, marks them Source = Answer, and never overrides a rule Scout
    evaluated from Azure data.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    $script:fixture = "$script:root/tests/datadump/sample-collect.json"
    $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("AZSC_Answers_" + [System.IO.Path]::GetRandomFileName())
    $null = New-Item -ItemType Directory -Path $script:tmp -Force
    $script:manifest = Import-PowerShellDataFile "$script:root/manifests/assessments.psd1"

    function New-ManualFinding {
        param([string] $Id, [string] $Status = 'Manual', [bool] $Manual = $true)
        [pscustomobject]@{ Id = $Id; Title = "q $Id"; Framework = 'F'; Area = 'A'; Severity = 'high'; Status = $Status; Manual = $Manual; EvidenceCount = 0; Evidence = @(); Remediation = 'r' }
    }
}

AfterAll {
    if ($script:tmp -and (Test-Path $script:tmp)) { Remove-Item $script:tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Answer words' {
    It 'maps <Word> to <Status>' -ForEach @(
        @{ Word = 'Yes'; Status = 'Pass' }, @{ Word = ' y '; Status = 'Pass' }, @{ Word = 'implemented'; Status = 'Pass' },
        @{ Word = 'Partial'; Status = 'Partial' }, @{ Word = 'in progress'; Status = 'Partial' },
        @{ Word = 'No'; Status = 'Fail' }, @{ Word = 'NOT MET'; Status = 'Fail' },
        @{ Word = 'N/A'; Status = 'NotApplicable' }, @{ Word = 'not applicable'; Status = 'NotApplicable' }
    ) {
        (& $script:Module { param($w) ConvertTo-ScoutAnswerStatus -Answer $w } $Word) | Should -Be $Status
    }
    It 'returns nothing for blank or unknown words' {
        (& $script:Module { ConvertTo-ScoutAnswerStatus -Answer '' }) | Should -BeNullOrEmpty
        (& $script:Module { ConvertTo-ScoutAnswerStatus -Answer 'maybe' }) | Should -BeNullOrEmpty
    }
}

Describe 'Import-ScoutAssessmentAnswer' {
    It 'reads the exported CSV shape, ignoring extra columns and blank answers' {
        $csv = Join-Path $script:tmp 'a.csv'
        @(
            [pscustomobject]@{ RuleId = 'X-01'; Assessment = 'A'; Question = 'q'; Answer = 'Yes'; Note = 'documented'; AnsweredBy = 'ops'; AnsweredAt = '2026-11-24' }
            [pscustomobject]@{ RuleId = 'X-02'; Assessment = 'A'; Question = 'q'; Answer = ''; Note = ''; AnsweredBy = ''; AnsweredAt = '' }
            [pscustomobject]@{ RuleId = 'X-03'; Assessment = 'A'; Question = 'q'; Answer = 'n/a'; Note = 'no AI'; AnsweredBy = ''; AnsweredAt = '' }
        ) | Export-Csv -LiteralPath $csv -NoTypeInformation
        $a = & $script:Module { param($p) Import-ScoutAssessmentAnswer -Path $p } $csv
        $a.Count | Should -Be 2
        $a['x-01'].Status | Should -Be 'Pass'
        $a['X-01'].Note | Should -Be 'documented'
        $a['X-03'].Status | Should -Be 'NotApplicable'
    }
    It 'reads the JSON list the report and runs write' {
        $json = Join-Path $script:tmp 'a.json'
        @{ schema = 'azurescout.assessment-answers/v1'; answers = @(@{ ruleId = 'J-01'; answer = 'Partial'; note = 'half' }) } | ConvertTo-Json -Depth 5 | Set-Content $json
        $a = & $script:Module { param($p) Import-ScoutAssessmentAnswer -Path $p } $json
        $a['J-01'].Status | Should -Be 'Partial'
        $a['J-01'].Note | Should -Be 'half'
    }
    It 'reads a plain JSON map of rule id to answer' {
        $json = Join-Path $script:tmp 'map.json'
        '{ "M-01": "No", "M-02": { "answer": "Yes", "note": "ok" } }' | Set-Content $json
        $a = & $script:Module { param($p) Import-ScoutAssessmentAnswer -Path $p } $json
        $a['M-01'].Status | Should -Be 'Fail'
        $a['M-02'].Note | Should -Be 'ok'
    }
    It 'warns about and skips unrecognised answers' {
        $csv = Join-Path $script:tmp 'bad.csv'
        [pscustomobject]@{ RuleId = 'B-01'; Answer = 'maybe' } | Export-Csv -LiteralPath $csv -NoTypeInformation
        $a = & $script:Module { param($p) Import-ScoutAssessmentAnswer -Path $p -WarningVariable w -WarningAction SilentlyContinue; $script:w = $w } $csv
        $a.Count | Should -Be 0
    }
    It 'rejects a CSV without an Answer column, a missing file and an unknown extension' {
        $csv = Join-Path $script:tmp 'nocol.csv'
        [pscustomobject]@{ RuleId = 'B-01'; Response = 'Yes' } | Export-Csv -LiteralPath $csv -NoTypeInformation
        { & $script:Module { param($p) Import-ScoutAssessmentAnswer -Path $p } $csv } | Should -Throw '*Answer*'
        { & $script:Module { Import-ScoutAssessmentAnswer -Path 'Z:\nope\none.csv' } } | Should -Throw '*not found*'
        $txt = Join-Path $script:tmp 'a.txt'; 'x' | Set-Content $txt
        { & $script:Module { param($p) Import-ScoutAssessmentAnswer -Path $p } $txt } | Should -Throw '*.csv or .json*'
    }
}

Describe 'Set-ScoutFindingAnswer' {
    It 'scores answered manual questions and stamps the source of every finding' {
        $findings = @(
            (New-ManualFinding -Id 'Q-1')
            (New-ManualFinding -Id 'Q-2')
            (New-ManualFinding -Id 'Q-3')
            (New-ManualFinding -Id 'Q-4' -Status 'Unknown')
            (New-ManualFinding -Id 'D-1' -Status 'Fail' -Manual $false)
        )
        $answers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        $answers['Q-1'] = @{ Answer = 'Yes'; Status = 'Pass'; Note = 'n'; AnsweredBy = 'me'; AnsweredAt = 't' }
        $answers['Q-2'] = @{ Answer = 'N/A'; Status = 'NotApplicable'; Note = ''; AnsweredBy = ''; AnsweredAt = '' }
        $answers['Q-4'] = @{ Answer = 'No'; Status = 'Fail'; Note = ''; AnsweredBy = ''; AnsweredAt = '' }
        $answers['D-1'] = @{ Answer = 'Yes'; Status = 'Pass'; Note = 'trust me'; AnsweredBy = ''; AnsweredAt = '' }
        $out = @(& $script:Module { param($f, $a) Set-ScoutFindingAnswer -Findings $f -Answers $a } $findings $answers)

        $out.Count | Should -Be 5
        ($out | Where-Object Id -eq 'Q-1').Status | Should -Be 'Pass'
        ($out | Where-Object Id -eq 'Q-1').Source | Should -Be 'Answer'
        ($out | Where-Object Id -eq 'Q-1').AnsweredBy | Should -Be 'me'
        ($out | Where-Object Id -eq 'Q-2').Status | Should -Be 'NotAssessed'
        ($out | Where-Object Id -eq 'Q-3').Status | Should -Be 'Manual'
        ($out | Where-Object Id -eq 'Q-3').Source | Should -Be 'Unanswered'
        ($out | Where-Object Id -eq 'Q-4').Status | Should -Be 'Fail' -Because 'an organisational question is answerable even when its data prerequisite was missing'
        ($out | Where-Object Id -eq 'D-1').Status | Should -Be 'Fail' -Because 'an answer file never overrides a rule evaluated from Azure data'
        ($out | Where-Object Id -eq 'D-1').Source | Should -Be 'Data'
    }
    It 'answered findings count in the score' {
        $f = @((New-ManualFinding -Id 'S-1'), (New-ManualFinding -Id 'S-2'))
        $answers = @{ 'S-1' = @{ Answer = 'Yes'; Status = 'Pass'; Note = ''; AnsweredBy = ''; AnsweredAt = '' }; 'S-2' = @{ Answer = 'No'; Status = 'Fail'; Note = ''; AnsweredBy = ''; AnsweredAt = '' } }
        $score = & $script:Module { param($f, $a) Get-Score -Findings @(Set-ScoutFindingAnswer -Findings $f -Answers $a) } $f $answers
        $area = @($score.Areas)[0]
        $area.Score | Should -Be 50
        $area.Manual | Should -Be 0
    }
}

Describe 'Questionnaire export' {
    It 'lists every manual question of an assessment once' {
        $expected = @((Get-Content "$script:root/src/assess/rules/casa.security.yaml" -Raw | ConvertFrom-Yaml).rules | Where-Object { $_.manual }).Count
        $rows = @(& $script:Module { param($m) Get-ScoutAssessmentQuestion -Assessment 'Microsoft: CASA' -Manifest $m } $script:manifest)
        $rows.Count | Should -Be $expected
        @($rows.RuleId | Select-Object -Unique).Count | Should -Be $rows.Count
        $rows[0].Question | Should -Not -BeNullOrEmpty
    }
    It 'Export-ScoutAssessmentQuestion writes a CSV that round-trips through the importer' {
        $csv = Join-Path $script:tmp 'casa.csv'
        $file = Export-ScoutAssessmentQuestion -Assessment 'Microsoft: CASA' -Path $csv
        $file.FullName | Should -Exist
        $rows = @(Import-Csv $csv)
        ($rows[0].PSObject.Properties.Name -join ',') | Should -Be 'RuleId,Assessment,Framework,Area,Severity,Question,Guidance,Answer,Note,AnsweredBy,AnsweredAt'
        $rows[0].Answer = 'Yes'; $rows[1].Answer = 'Partial'
        $rows | Export-Csv $csv -NoTypeInformation
        $a = & $script:Module { param($p) Import-ScoutAssessmentAnswer -Path $p } $csv
        $a.Count | Should -Be 2
        $again = Join-Path $script:tmp 'casa2.csv'
        $null = Export-ScoutAssessmentQuestion -Assessment 'Microsoft: CASA' -Path $again -AssessmentAnswers $csv
        @(Import-Csv $again | Where-Object Answer).Count | Should -Be 2
    }
    It 'rejects an unknown assessment name' {
        { Export-ScoutAssessmentQuestion -Assessment 'No Such Assessment' -Path (Join-Path $script:tmp 'x.csv') } | Should -Throw '*Unknown assessment*'
    }
}

Describe 'End to end: -AssessmentAnswers re-scores an existing collection offline' {
    It 'writes the questionnaire, applies answers, and the report carries them' {
        $out1 = Join-Path $script:tmp 'run1'
        $run1 = & $script:Module { param($fx, $o) Invoke-ScoutAssessmentCore -Assessment 'CAF: Azure Landing Zone' -FromCollect $fx -OutputFormat React, Json -OutputPath $o } $script:fixture $out1
        $questions = Join-Path $run1 'assessment-questions.csv'
        $questions | Should -Exist
        $rows = @(Import-Csv $questions)
        $rows.Count | Should -BeGreaterThan 2
        $rows[0].Answer = 'Yes'; $rows[1].Answer = 'No'; $rows[2].Answer = 'N/A'
        $rows | Export-Csv $questions -NoTypeInformation

        $out2 = Join-Path $script:tmp 'run2'
        $run2 = & $script:Module { param($fx, $o, $a) Invoke-ScoutAssessmentCore -Assessment 'CAF: Azure Landing Zone' -FromCollect $fx -OutputFormat React, Json -OutputPath $o -AssessmentAnswers $a } $script:fixture $out2 $questions
        $applied = Get-Content (Join-Path $run2 'assessment-answers.json') -Raw | ConvertFrom-Json
        @($applied.answers).Count | Should -Be 3
        $findings = Get-Content (Join-Path $run2 'findings.json') -Raw | ConvertFrom-Json
        $byId = @{}; foreach ($f in @($findings.Findings)) { $byId[$f.Id] = $f }
        $byId[$rows[0].RuleId].Status | Should -Be 'Pass'
        $byId[$rows[0].RuleId].Source | Should -Be 'Answer'
        $byId[$rows[1].RuleId].Status | Should -Be 'Fail'
        $byId[$rows[2].RuleId].Status | Should -Be 'NotAssessed'
        $html = Get-Content (Join-Path $run2 'report-react.html') -Raw
        $html | Should -Match '"source":\s*"Answer"'
        $html | Should -Match 'ans-download'
        @(Import-Csv (Join-Path $run2 'assessment-questions.csv') | Where-Object Answer).Count | Should -Be 3
    }
}
