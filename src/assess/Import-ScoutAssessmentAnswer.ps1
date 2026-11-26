#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    Questionnaire answers for manual assessment items.

    Many Microsoft assessments (CASA, DevOps Capability, FinOps Review, SMART, the AI workload
    review, ...) contain questions no Azure API can answer: "is the shared-responsibility model
    documented?", "do you hold blameless post-incident reviews?". Scout's rule files mark those
    `manual: true`; until now they always came back Status = Manual and were left out of every
    score, so those assessments could never be completed.

    The flow:
      1. Every assessment run writes assessment-questions.csv next to its findings: one row per
         manual question, with its id, assessment, area, question text and any answer already given.
         Export-ScoutAssessmentQuestion writes the same file without running a scan.
      2. The operator fills in the Answer column (Yes / Partial / No / N/A) and optional notes.
      3. The next run passes the file with -AssessmentAnswers (with -FromCollect to re-score an
         existing collection offline). Answered items are scored like any other finding and marked
         Source = Answer, so a reader can always tell which results came from Azure data and which
         from a person.

    Answers only ever apply to manual questions. A rule Scout evaluates from Azure data is never
    overridden by an answer file: the data is the evidence.
#>

$script:ScoutAnswerStatusMap = [ordered]@{
    'yes' = 'Pass'; 'y' = 'Pass'; 'pass' = 'Pass'; 'true' = 'Pass'; 'met' = 'Pass'; 'implemented' = 'Pass'; 'done' = 'Pass'
    'partial' = 'Partial'; 'partly' = 'Partial'; 'partially' = 'Partial'; 'in progress' = 'Partial'; 'inprogress' = 'Partial'; 'some' = 'Partial'
    'no' = 'Fail'; 'n' = 'Fail'; 'fail' = 'Fail'; 'false' = 'Fail'; 'not met' = 'Fail'; 'notmet' = 'Fail'; 'not implemented' = 'Fail'
    'n/a' = 'NotApplicable'; 'na' = 'NotApplicable'; 'not applicable' = 'NotApplicable'; 'notapplicable' = 'NotApplicable'
}

function ConvertTo-ScoutAnswerStatus {
    <# Maps an answer word to a finding status, or $null for blank/unrecognised input. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string] $Answer)

    if ([string]::IsNullOrWhiteSpace($Answer)) { return $null }
    $key = $Answer.Trim().ToLowerInvariant()
    if ($script:ScoutAnswerStatusMap.Contains($key)) { return [string]$script:ScoutAnswerStatusMap[$key] }
    return $null
}

function Import-ScoutAssessmentAnswer {
    <#
    .SYNOPSIS
        Reads a questionnaire answer file (CSV or JSON) into a rule-id keyed table.

    .DESCRIPTION
        CSV: the assessment-questions.csv Scout writes, filled in. Required columns: RuleId, Answer.
        Optional: Note, AnsweredBy, AnsweredAt. Any other column (Assessment, Area, Question, ...)
        is ignored, so the exported file round-trips unchanged.

        JSON: either the answers file a run writes (assessment-answers.json, whose `answers` array
        holds objects with ruleId/answer/note/answeredBy/answeredAt) or a plain object keyed by
        rule id whose values are an answer word or such an object. The React report's "download
        answers" button writes the first shape.

        Blank answers are skipped. Unrecognised answer words are reported as a warning naming the
        rule id and skipped, never guessed.

    .OUTPUTS
        Hashtable: rule id (case-insensitive) -> @{ RuleId; Answer; Status; Note; AnsweredBy; AnsweredAt }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Assessment answer file '$Path' was not found."
    }
    $answers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $entries = [System.Collections.Generic.List[object]]::new()
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    if ($extension -eq '.csv') {
        $rows = @(Import-Csv -LiteralPath $Path)
        if ($rows.Count -gt 0) {
            $columns = @($rows[0].PSObject.Properties.Name)
            foreach ($required in 'RuleId', 'Answer') {
                if ($columns -notcontains $required) { throw "Assessment answer file '$Path' has no '$required' column (columns: $($columns -join ', '))." }
            }
        }
        foreach ($row in $rows) {
            $entries.Add([pscustomobject]@{
                    RuleId     = [string]$row.RuleId
                    Answer     = [string]$row.Answer
                    Note       = if ($row.PSObject.Properties['Note']) { [string]$row.Note } else { '' }
                    AnsweredBy = if ($row.PSObject.Properties['AnsweredBy']) { [string]$row.AnsweredBy } else { '' }
                    AnsweredAt = if ($row.PSObject.Properties['AnsweredAt']) { [string]$row.AnsweredAt } else { '' }
                })
        }
    }
    elseif ($extension -eq '.json') {
        $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20
        $readField = {
            param($Object, [string] $Name)
            if ($null -eq $Object) { return '' }
            $property = $Object.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
            if ($property) { return [string]$property.Value }
            return ''
        }
        $list = $null
        if ($doc -is [array]) { $list = $doc }
        elseif ($doc.PSObject.Properties['answers'] -and $doc.answers -is [array]) { $list = $doc.answers }
        if ($null -ne $list) {
            foreach ($item in $list) {
                $entries.Add([pscustomobject]@{
                        RuleId     = & $readField $item 'ruleId'
                        Answer     = & $readField $item 'answer'
                        Note       = & $readField $item 'note'
                        AnsweredBy = & $readField $item 'answeredBy'
                        AnsweredAt = & $readField $item 'answeredAt'
                    })
            }
        }
        else {
            $map = if ($doc.PSObject.Properties['answers']) { $doc.answers } else { $doc }
            foreach ($property in $map.PSObject.Properties) {
                if ($property.Name -in 'schema', 'generatedAt', 'assessments') { continue }
                $value = $property.Value
                if ($value -is [string]) {
                    $entries.Add([pscustomobject]@{ RuleId = $property.Name; Answer = $value; Note = ''; AnsweredBy = ''; AnsweredAt = '' })
                }
                else {
                    $entries.Add([pscustomobject]@{
                            RuleId     = $property.Name
                            Answer     = & $readField $value 'answer'
                            Note       = & $readField $value 'note'
                            AnsweredBy = & $readField $value 'answeredBy'
                            AnsweredAt = & $readField $value 'answeredAt'
                        })
                }
            }
        }
    }
    else {
        throw "Assessment answer file '$Path' must be .csv or .json."
    }

    $unrecognised = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $entries) {
        $ruleId = $entry.RuleId.Trim()
        if (-not $ruleId) { continue }
        if ([string]::IsNullOrWhiteSpace($entry.Answer)) { continue }
        $status = ConvertTo-ScoutAnswerStatus -Answer $entry.Answer
        if (-not $status) { $unrecognised.Add("$ruleId='$($entry.Answer.Trim())'"); continue }
        $answers[$ruleId] = @{
            RuleId     = $ruleId
            Answer     = $entry.Answer.Trim()
            Status     = $status
            Note       = $entry.Note.Trim()
            AnsweredBy = $entry.AnsweredBy.Trim()
            AnsweredAt = $entry.AnsweredAt.Trim()
        }
    }
    if ($unrecognised.Count -gt 0) {
        Write-Warning ("Assessment answers: {0} answer(s) not recognised and skipped (use Yes, Partial, No or N/A): {1}" -f
            $unrecognised.Count, ($unrecognised -join ', '))
    }
    return $answers
}

function Set-ScoutFindingAnswer {
    <#
    .SYNOPSIS
        Applies questionnaire answers to manual findings and stamps every finding's Source.

    .DESCRIPTION
        Source is 'Data' for a finding Scout evaluated from Azure data, 'Answer' for a manual
        question answered from the answer file, and 'Unanswered' for a manual question with no
        answer yet. An answer of N/A becomes Status NotAssessed (excluded from the score, the same
        as any other not-applicable item) with the note kept.

        A manual question whose rule set could not run because its data prerequisite was absent
        (Status NotAssessed, flagged NotApplicable) is still answerable: the question is about the organisation, not the data.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]] $Findings,
        [AllowNull()][hashtable] $Answers
    )

    foreach ($finding in @($Findings)) {
        if ($null -eq $finding) { continue }
        $isManual = $finding.PSObject.Properties['Manual'] -and [bool]$finding.Manual
        $source = if ($isManual) { 'Unanswered' } else { 'Data' }
        $answer = $null
        if ($isManual -and $Answers -and $finding.PSObject.Properties['Id'] -and $Answers.ContainsKey([string]$finding.Id) -and
            ([string]$finding.Status -in 'Manual', 'Unknown' -or ($finding.PSObject.Properties['NotApplicable'] -and $finding.NotApplicable))) {
            $answer = $Answers[[string]$finding.Id]
        }
        if ($answer) {
            $source = 'Answer'
            $finding.Status = if ($answer.Status -eq 'NotApplicable') { 'NotAssessed' } else { $answer.Status }
        }
        foreach ($pair in @(
                @('Source', $source),
                @('Answer', $(if ($answer) { $answer.Answer } else { $null })),
                @('AnswerNote', $(if ($answer) { $answer.Note } else { $null })),
                @('AnsweredBy', $(if ($answer) { $answer.AnsweredBy } else { $null })),
                @('AnsweredAt', $(if ($answer) { $answer.AnsweredAt } else { $null })))) {
            if ($finding.PSObject.Properties[$pair[0]]) { $finding.($pair[0]) = $pair[1] }
            else { $finding | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] }
        }
        $finding
    }
}

function Get-ScoutAssessmentQuestion {
    <#
    .SYNOPSIS
        Lists the manual questions of the named assessments, as rows for assessment-questions.csv.

    .DESCRIPTION
        Reads the rule files each assessment names (the same Get-RuleSet call a run makes) and
        returns one row per manual rule. A question shared by several assessments is listed once,
        under the first one. -Answers pre-fills rows that already have an answer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Assessment,
        [Parameter(Mandatory)][hashtable] $Manifest,
        [AllowNull()][hashtable] $Answers
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $Assessment) {
        if (-not $Manifest.ContainsKey($name)) { continue }
        $spec = $Manifest[$name]
        if (-not $spec.ContainsKey('Rules') -or @($spec.Rules).Count -eq 0) { continue }
        foreach ($set in @(Get-RuleSet -Patterns $spec.Rules)) {
            foreach ($rule in @($set.Rules)) {
                if ($null -eq $rule) { continue }
                $manual = ($rule.ContainsKey('manual') -and [bool]$rule.manual) -or
                ($rule.ContainsKey('assert') -and $rule.assert -is [System.Collections.IDictionary] -and [string]$rule.assert['type'] -eq 'manual')
                if (-not $manual -or -not $rule.ContainsKey('id')) { continue }
                if (-not $seen.Add([string]$rule.id)) { continue }
                $existing = if ($Answers -and $Answers.ContainsKey([string]$rule.id)) { $Answers[[string]$rule.id] } else { $null }
                [pscustomobject][ordered]@{
                    RuleId     = [string]$rule.id
                    Assessment = $name
                    Framework  = [string]$set.Framework
                    Area       = [string]$set.Area
                    Severity   = if ($rule.ContainsKey('severity')) { [string]$rule.severity } else { '' }
                    Question   = if ($rule.ContainsKey('title')) { [string]$rule.title } else { '' }
                    Guidance   = if ($rule.ContainsKey('remediation')) { [string]$rule.remediation } else { '' }
                    Answer     = if ($existing) { $existing.Answer } else { '' }
                    Note       = if ($existing) { $existing.Note } else { '' }
                    AnsweredBy = if ($existing) { $existing.AnsweredBy } else { '' }
                    AnsweredAt = if ($existing) { $existing.AnsweredAt } else { '' }
                }
            }
        }
    }
}

function Export-ScoutAssessmentQuestion {
    <#
    .SYNOPSIS
        Writes the questionnaire for one or more assessments to a CSV you can fill in.

    .DESCRIPTION
        No scan and no Azure sign-in: the questions come from the assessment rule files. Fill in
        the Answer column (Yes, Partial, No or N/A), optionally Note / AnsweredBy / AnsweredAt,
        then pass the file to Invoke-AzureScout -AssessmentAnswers. Every assessment run also
        writes this file (assessment-questions.csv) into its report folder, pre-filled with the
        answers that run used.

    .PARAMETER Assessment
        Assessment names as shown by the wizard or -Assessment, or 'All'.

    .PARAMETER Path
        CSV to write. Defaults to ./assessment-questions.csv.

    .PARAMETER AssessmentAnswers
        An existing answer file whose answers pre-fill the new questionnaire (for example to add a
        newly selected assessment's questions to answers you already gave).

    .EXAMPLE
        Export-ScoutAssessmentQuestion -Assessment 'Microsoft: CASA', 'Microsoft: FinOps Review' -Path .\answers.csv
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)][string[]] $Assessment,
        [string] $Path = './assessment-questions.csv',
        [string] $AssessmentAnswers
    )

    $manifest = Import-PowerShellDataFile ([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'manifests', 'assessments.psd1'))
    # Wrapped in @(): an `if` used as an expression unrolls a one-item array to a bare string.
    $names = @(if ($Assessment -contains 'All') { $manifest.Keys | Sort-Object }
        else { Resolve-ScoutAssessmentName -Name $Assessment -Manifest $manifest })
    $unknown = @($names | Where-Object { -not $manifest.ContainsKey($_) })
    if ($unknown.Count -gt 0) { throw "Unknown assessment(s): $($unknown -join ', ')" }
    $answers = if ($AssessmentAnswers) { Import-ScoutAssessmentAnswer -Path $AssessmentAnswers } else { $null }
    $rows = @(Get-ScoutAssessmentQuestion -Assessment $names -Manifest $manifest -Answers $answers)
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    $rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
    Write-Verbose "Export-ScoutAssessmentQuestion: wrote $($rows.Count) question(s) for $($names.Count) assessment(s) to $Path"
    Get-Item -LiteralPath $Path
}
