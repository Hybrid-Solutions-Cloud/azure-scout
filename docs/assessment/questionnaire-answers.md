---
description: How to answer the assessment questions no Azure API can answer, so CASA, DevOps Capability, FinOps, SMART, the AI workload review and the rest produce a complete score.
---

# Questionnaire Answers

Many assessments include questions that no Azure API can answer. "Is the shared-responsibility
model understood and documented?" and "Do you hold blameless post-incident reviews?" are about
how your organisation works, not about how a resource is configured. Scout calls these
**manual** rules.

Until you answer them, manual rules show as **Manual** and are left out of the score. They are
never counted as failures. Once answered, they are scored like any other check and marked
**Answered**, so a reader can always tell a person's answer from Azure evidence.

Some assessments are mostly questions: CASA has 24 of 31, the AI workload review 32 of 34 and
the FinOps Review 15 of 22. The [Assessment Catalogue](../reference/assessment-catalogue.md)
lists the manual count for every assessment.

## How it works

1. **Get the questions.** Every assessment run writes `assessment-questions.csv` into its report
   folder, with one row per question. To get the file without running a scan:

   ```powershell
   Export-ScoutAssessmentQuestion -Assessment 'Microsoft: CASA', 'Microsoft: FinOps Review' -Path .\answers.csv
   ```

2. **Answer them.** Open the CSV in Excel or any editor and fill in the `Answer` column. `Note`,
   `AnsweredBy` and `AnsweredAt` are optional. Leave a row blank to skip it.

   You can also answer in the React report. In each assessment's **Review and availability
   agenda**, choose an answer next to each question, then select **download answers**. The report
   saves `assessment-answers.json`, and the report file itself is never changed.

3. **Run again with the answers.** To re-score the collection you already have, without
   scanning Azure again:

   ```powershell
   Invoke-AzureScout -Assessment 'Microsoft: CASA' `
       -FromCollect C:\AzureScout\<run>\assessment-report\collect.json `
       -AssessmentAnswers .\answers.csv
   ```

   Or pass `-AssessmentAnswers` on a normal scan.

The wizard asks for the answer file after you choose assessments, but only when the chosen
assessments have questions, and it says how many there are.

## Answers

| Write | Scored as |
|---|---|
| `Yes`, `Y`, `Pass`, `Met`, `Implemented`, `Done` | **Met** (Pass) |
| `Partial`, `Partly`, `In progress`, `Some` | **Partially met** (Partial) |
| `No`, `N`, `Fail`, `Not met`, `Not implemented` | **Not met** (Fail) |
| `N/A`, `NA`, `Not applicable` | **Not assessed**, left out of the score, with your note kept |

Case doesn't matter. Scout reports any other word as a warning naming the question, and skips it
rather than guessing.

## Rules

- **Answers only apply to manual questions.** If Scout evaluates a rule from Azure data, an answer
  for that rule is ignored, because the data is the evidence.
- **A question can be answered even when its data is missing.** For example, SMART on an estate
  with no Azure Migrate project marks its data checks Unknown, but its organisational questions
  can still be answered and scored.
- **Each run records what it used.** `assessment-answers.json` in the report folder lists every
  answer applied. The new `assessment-questions.csv` comes back pre-filled with those answers, so
  each run's file is the starting point for the next.
- **Multi-tenant runs use one file for every tenant.** Question IDs are the same in every tenant.
  If the answers differ between tenants, run each tenant separately with its own file.
- **Answers are visible everywhere results are.** In `findings.json`, the Json report and the React
  report's CSV export, each finding carries `Source` (`Data`, `Answer` or `Unanswered`), plus
  `Answer`, `AnswerNote`, `AnsweredBy` and `AnsweredAt` when it was answered.

## File formats

**CSV.** These are the columns Scout writes. Only `RuleId` and `Answer` are required, and other
columns are ignored, so the exported file can be used unchanged.

```text
RuleId,Assessment,Framework,Area,Severity,Question,Guidance,Answer,Note,AnsweredBy,AnsweredAt
CASA-TR-01,Microsoft: CASA,CASA,...,low,"The role of the cloud service provider ...","...",Yes,Documented in the cloud policy,Security team,2026-11-24
```

**JSON.** This is what the report's download button and each run write:

```json
{
  "schema": "azurescout.assessment-answers/v1",
  "answers": [
    { "ruleId": "CASA-TR-01", "answer": "Yes", "note": "Documented in the cloud policy" }
  ]
}
```

A plain object keyed by rule ID also works: `{ "CASA-TR-01": "Yes", "CASA-TR-02": { "answer": "No", "note": "..." } }`.
