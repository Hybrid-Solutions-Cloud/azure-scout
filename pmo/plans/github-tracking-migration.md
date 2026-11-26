# Plan: move roadmap and work tracking from Azure DevOps to GitHub

| Field | Value |
|---|---|
| Status | Draft for review. Nothing in this plan has been created on GitHub yet. |
| Written | 2026-11-26 |
| Owner | Repo maintainer |
| Standard it introduces | [`pmo/work-item-standard.md`](../work-item-standard.md) |

## Goal

Azure Scout's roadmap, features, tasks and bugs are tracked in GitHub Issues in this repo.
Azure DevOps (ADO) is frozen as an archive. The roadmap is a view over GitHub issues, not a
separate document that can drift.

## This repo is public

Everything created under this plan is visible to anyone: issues, comments, labels, milestones,
project boards, and every file in `pmo/`. The plan is built around that.

- No customer, tenant or subscription names or IDs, resource names, user names, e-mail
  addresses, or internal host names in any issue, comment, label, milestone, project field or
  file. The work-item standard states the full rule.
- ADO items are **rewritten**, not copied, when they move. Old descriptions were written for a
  private audience and are not assumed safe.
- Security weaknesses in Scout are **not** filed as public issues. They go through GitHub
  private vulnerability reporting (to be enabled, see step 3) and become public only after a
  fix ships.
- Scan output, logs and screenshots are attached only after redaction.
- The GitHub Project is public, like the repo. Nothing sensitive goes in its fields.

## Non-goals

- Migrating closed ADO items. They stay in ADO as the archive.
- Rewriting history: existing `AB#` references in the changelog, release notes and commits stay.
- Carrying ADO conventions forward. This plan defines new ones for GitHub.

## Starting point (checked 2026-11-26)

- GitHub: 0 issues, no milestones, 9 default labels, three markdown issue templates. The
  organisation has three issue types: Task, Bug, Feature.
- ADO: the repo's docs reference 392 distinct `AB#` work items. The open count is not known
  until the export in step 1.
- Roadmap content lives in `docs/project/roadmap.md` and `pmo/`.

## Structure

Types say **what** an item is. Labels say **where** it lives and **how urgent** it is.
The full definitions and the required format of each item are in the
[work-item standard](../work-item-standard.md).

### Issue types (one per issue)

| Type | Used for | ADO equivalent |
|---|---|---|
| Epic (to add at organisation level) | A goal spanning several releases | Epic |
| Feature | A capability a user can see; parent of tasks | Feature, User Story |
| Task | One unit of work, normally one pull request | Task |
| Bug | Released behaviour that is wrong | Bug |

Hierarchy uses GitHub sub-issues: Epic → Feature → Task.

### Labels (several per issue)

| Group | Labels |
|---|---|
| `area:` | `collect`, `discovery`, `assess-rules`, `assess-engine`, `report`, `menu-ui`, `performance`, `identity`, `docs-site`, `release-ci`, `permissions` |
| `priority:` | `p0-now`, `p1-next`, `p2-later` |
| `status:` | `blocked`, `needs-live-test`, `needs-decision` |
| `kind:` | `tech-debt`, `breaking-change`, `research` |
| `source:` | `ado-migrated`, `depth-audit`, `user-feedback` |
| `roadmap` | Marks an item that appears on the public roadmap |
| Kept defaults | `good first issue`, `duplicate`, `wontfix`, `question` |

### Roadmap in GitHub issues

- Every roadmap item is an **Epic or Feature issue** carrying the `roadmap` label.
- **Milestones are releases** (for example `3.19.0`). An item's milestone is its target release.
- One **GitHub Project, "Azure Scout Roadmap"**, shows them. Fields: Status (Backlog, Ready,
  In progress, In review, Released), Priority, Area, Target release. Views: roadmap by release,
  board by status, table per epic.
- `docs/project/roadmap.md` keeps a short narrative (current, previous, next) and links to the
  project. It no longer lists individual future items; the issues are the source of truth.
- Closing a roadmap issue requires the release it shipped in.

## Steps

1. **Export ADO.** Open Epics, Features, Stories, Tasks and Bugs with title, description,
   state, parent, area and tags. The export file stays out of the repo.
2. **Triage.** Each open item is marked keep, merge or drop. Only keeps move.
3. **Create the structure on GitHub.** Epic issue type; labels; milestones; the project; issue
   forms (YAML) replacing the three markdown templates, each enforcing the standard's fields;
   enable private vulnerability reporting and add `SECURITY.md`.
4. **Create the new epics** listed below. They are new work and need no migration.
5. **Import the keeps.** Each is rewritten to the standard, checked against the public-repo
   rule, given its type and labels plus `source:ado-migrated`, and a line
   `Migrated from AB#<id>`. Parent links become sub-issues.
6. **Switch conventions.** Commits and pull requests reference `#<issue>`. Update `AGENTS.md`,
   `CONTRIBUTING.md` (link to the standard), the commit-format rule, and the test that requires
   `AB#` in version notes.
7. **Point the roadmap page at the project** (see above).
8. **Freeze ADO.** A note on the ADO project points to GitHub; the area path becomes read-only.

## Decisions (made 2026-11-26)

1. Only open ADO items are candidates, and each is reviewed first: many are already done.
2. ADO conventions do not carry over. The standards and naming for GitHub are new and are
   defined in the work-item standard. `AB#<id>` references stop; commits reference `#<issue>`.
3. The project is public, like the repo.

## ADO open items (read 2026-11-26)

782 work items in the project; 178 are open (New or Active): 3 epics, 18 features, 20 user
stories, 10 bugs, 127 tasks. A further 140 are Resolved but never closed. The first-pass
review sorts the open items into: already shipped (close in ADO, do not migrate), out of scope
(close), fold into a new epic, and keep. The item-level list is reviewed with the maintainer
before anything is created on GitHub; it is not stored in this repo.

## First epics

### Epic 1: Faster scans (`area:performance`, `priority:p0-now`, `roadmap`)

A full run of the multi-tenant test takes about 78 minutes for five tenants; the largest takes
about 33 minutes.

| # | Type | Item |
|---|---|---|
| 1 | Task | Measure first: publish a per-phase timing breakdown from the timings Scout already logs. |
| 2 | Feature | Scan profiles: Quick, Standard, Deep. |
| 3 | Feature | Collect only what the selected categories and assessments need. |
| 4 | Task | Parallelise the remaining serial reads (the 8-wide pattern cut one sweep from 33 s to 3.7 s). |
| 5 | Feature | Run tenants in parallel in multi-tenant runs. |
| 6 | Feature | Reuse a recent collection: re-run assessments or reports without calling Azure. |
| 7 | Task | Stop collecting datasets no check or report reads. |

### Epic 2: Better menu and user experience (`area:menu-ui`, `roadmap`)

| # | Type | Item |
|---|---|---|
| 1 | Feature | Redesign the PowerShell menu around three choices: what to discover (by category, with presets), how deep (scan profile), what output. Show estimated time and required permissions before starting. |
| 2 | Feature | Saved run profiles: save a selection to a file and re-run it with one command. |
| 3 | Feature | Live progress per phase and per tenant, with time remaining. |
| 4 | Feature | HTML launcher (later): a local page with the same choices that produces the run command or profile file. Start as a static page; a local web server that runs the scan is a later decision. |
| 5 | Task | One manifest defines categories and options for both menus. |

### Epic 3: Collection depth (`area:collect`, `source:depth-audit`, `roadmap`)

Remaining sub-resource reads from the depth audit; projecting more of each resource's settings
into worksheets and assessment data; live-testing datasets shipped without a live resource
(`status:needs-live-test`); publishing the audit summary to the docs site.

### Epic 4: Identity depth (`area:identity`, `roadmap`)

Directory-role eligibility and MFA registration (need extra Microsoft Graph permissions);
access reviews.

## Ideas from comparable tools

Checked 2026-11-26. Items marked "not verified" come from prior knowledge, not a source read
that day.

| Tool | Idea | Fits |
|---|---|---|
| Azure Quick Review | Scan stages switched on or off individually; a YAML filters file to include or exclude checks and scopes; scope down to one resource group; plugins | Epic 1 items 2-3, Epic 2 item 2 |
| Azure Quick Review | Interactive dashboard opened from a results file | Epic 2 item 4 |
| Azure Governance Visualizer | Warn when a tenant approaches Azure limits | New Feature under Epic 3 |
| Steampipe / Powerpipe | Query collected data ad hoc | Epic 1 item 6 |
| Prowler (not verified) | Pass/fail thresholds and exit codes for pipeline use | New Feature |
| PSRule for Azure (not verified) | Dated baselines; suppression with a recorded reason | New Feature: baselines and waivers with expiry |

Sources: <https://github.com/Azure/azqr>, <https://azure.github.io/azqr/docs/usage>,
<https://github.com/azure/azure-governance-visualizer>.
