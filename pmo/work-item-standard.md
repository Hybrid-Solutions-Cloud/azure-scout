# Work-item standard

How issues, features, epics and roadmap items are written in this repo. It applies to everyone
who creates one: maintainers, contributors and AI agents.

Status: draft, introduced by
[`plans/github-tracking-migration.md`](plans/github-tracking-migration.md). It takes effect when
that plan's step 3 is complete.

## Rule 1: this repo is public

Anyone can read every issue, comment, label, milestone and project field. Never include:

- customer, tenant or subscription names or IDs;
- resource names, resource IDs, host names or IP addresses from a real environment;
- names, e-mail addresses or user principal names of people;
- secrets of any kind: keys, tokens, connection strings, passwords;
- unredacted scan output, logs or screenshots.

Describe an environment by its shape instead: "a tenant with 42 subscriptions", "a storage
account with versioning off". Use `contoso`-style placeholders in examples.

**Security weaknesses in Azure Scout are not filed as issues.** Report them through GitHub
private vulnerability reporting (the Security tab). They become public after a fix ships.

If something sensitive is posted by mistake, edit it out and tell a maintainer; an edit alone
leaves it in the issue's history, which a maintainer must delete.

## Types

Every issue has exactly one type.

| Type | Use it for | Parent |
|---|---|---|
| Epic | A goal spanning several releases | none |
| Feature | A capability a user can see | an Epic |
| Task | One unit of work, normally one pull request | a Feature or Epic |
| Bug | Released behaviour that is wrong | optional |

## Labels

| Group | Rule | Values |
|---|---|---|
| `area:` | At least one | `collect`, `discovery`, `assess-rules`, `assess-engine`, `report`, `menu-ui`, `performance`, `identity`, `docs-site`, `release-ci`, `permissions` |
| `priority:` | Exactly one, set by a maintainer | `p0-now`, `p1-next`, `p2-later` |
| `status:` | When it applies | `blocked`, `needs-live-test`, `needs-decision` |
| `kind:` | When it applies | `tech-debt`, `breaking-change`, `research` |
| `source:` | When it applies | `ado-migrated`, `depth-audit`, `user-feedback` |
| `roadmap` | Epics and Features shown on the public roadmap | |

New labels are added by changing this file in a pull request first.

## Titles

- Start with a verb or the affected thing; no type prefix (the type field carries that).
- Say the outcome, not the activity: "Read Front Door origins and routes", not "Front Door work".
- Bugs state the wrong behaviour: "Handled 403 is logged as ERROR".
- 80 characters or fewer. No version numbers; the milestone carries the release.

## Required content

### Epic

```markdown
## Goal
One or two sentences: what is true for a user when this is done.

## Why
The problem, with numbers where they exist.

## Scope
- In: ...
- Out (non-goals): ...

## Done when
- [ ] Measurable outcome
```

### Feature

```markdown
## What the user gets
One or two sentences.

## Why

## Acceptance criteria
- [ ] Observable behaviour, testable

## Permissions and Azure calls
New permissions needed, and extra Azure calls per run. "None" is a valid answer.

## Not included
```

### Task

```markdown
## What
The change, in one or two sentences.

## Done when
- [ ] Tests added or updated
- [ ] Docs updated, or "no doc change" with the reason
```

### Bug

```markdown
## What happens
## What should happen
## Steps to reproduce
Version (`Get-Module AzureScout`), PowerShell version, and the command, with environment
details replaced by placeholders.
## Impact
Who is affected and how badly.
```

## Roadmap items

- A roadmap item is an Epic or Feature with the `roadmap` label.
- Its **milestone** is its target release. No milestone means "not scheduled".
- It appears in the "Azure Scout Roadmap" project; the project's Status field is kept current.
- It is closed only when released, with a closing comment naming the release.

## Linking work

- Commits and pull requests reference the issue: `feat(collect): read Front Door origins #123`.
- A pull request that completes an issue says `Closes #123` in its description.
- Items moved from Azure DevOps carry the line `Migrated from AB#<id>`.

## Live-test honesty

Work that shipped without running against a real resource carries `status:needs-live-test`
and says so in the issue. The label is removed only with a comment describing the live run.
