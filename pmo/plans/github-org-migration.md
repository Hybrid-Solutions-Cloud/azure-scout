# Change Request: Establish AzureScout in Hybrid-Solutions-Cloud

| Field | Value |
|---|---|
| Requester | Kristopher Turner |
| Date | 2026-08-12 |
| Priority | High |
| Status | In progress |
| Work item | AB#7279 |

## Description

Establish `Hybrid-Solutions-Cloud/azure-scout` as AzureScout's canonical repository without using
GitHub's ownership-transfer operation. Preserve `thisismydemo/azure-scout` as the historical home
and publish a friendly move notice on its documentation landing page. Mirror Git history, branches,
tags, releases, documentation, and active local work into the new repository; then update project
links, PowerShell Gallery metadata, AI workspace identity, and the local canonical clone.

## Target state

| Area | Target |
|---|---|
| Canonical GitHub repository | `https://github.com/Hybrid-Solutions-Cloud/azure-scout` |
| Canonical local clone | `D:/git/hybrid-solutions-cloud/azure-scout` |
| Canonical documentation | `https://hybrid-solutions-cloud.github.io/azure-scout/` |
| Legacy repository | Retained at `thisismydemo/azure-scout` as the issue/PR/history record |
| Legacy documentation | Landing page links to both canonical locations |
| PowerShell Gallery `ProjectUri` | Canonical documentation URL |
| PowerShell Gallery source/license/icon | `Hybrid-Solutions-Cloud/azure-scout` URLs |
| Release gate | Complete collector and automated suite passes on one exact commit |

## Important boundary

Git branches, tags, and commit history live in Git and can be mirrored exactly. GitHub issues,
pull requests, reviews, workflow runs, approvals, and repository settings do not live in `.git`.
The old repository remains available for that historical record. Release records and protection
settings are recreated in the new repository where practical; old PR and issue numbers are not
rewritten or represented as if they were native objects in the new repository.

## Impact analysis

| Area | Impact | Details |
|---|---|---|
| Users | Medium | New code and documentation links become canonical; the old landing page remains a signpost. |
| Maintainers | Medium | Local path, remote, app installation, branch protection, Pages, release, and test procedures change. |
| Automation | Medium | Reusable action examples, badges, generated links, and docs edit links change organization. |
| PowerShell Gallery | Low | Existing package metadata stays unchanged until edited; the next version publishes new manifest URLs. |
| Historical GitHub objects | Medium | Existing issues, PRs, reviews, and workflow runs remain in the source repository. |

## Risk assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A branch or tag is omitted | Low | High | Compare exact branch/tag names and object IDs after the mirror; retain a verified full-history bundle. |
| Active unpushed work is omitted | Low | High | Push the recovered local 3.12.3 branch separately and verify its exact commit ID. |
| Legacy notice accidentally becomes canonical main | Low | Medium | Build canonical main from the last product main commit and replace target main with an exact force-with-lease. |
| New Pages site is unavailable | Medium | High | Retain `gh-pages`, configure its source, trigger the docs workflow, and test root plus deep links. |
| Actions cannot deploy in the new org | Medium | High | Verify the target-org HCS GitHub App, Actions permissions, environments, and a real workflow run. |
| Release links point to missing releases | Medium | Medium | Recreate release metadata/assets against the mirrored tags and verify recent release URLs. |
| PowerShell Gallery shows stale links | High | Low | Keep the legacy project URL usable and publish matching URLs from the next tested manifest. |
| Product work is released without a clean gate | Medium | High | Keep 3.12.3 isolated; require complete zero-failure testing before merge or release. |

## Implementation plan

| # | Task | Acceptance evidence |
|---:|---|---|
| 1 | Inventory source identity, refs, releases, protections, Actions, Pages, secrets, environments, and package metadata. | Counts and settings recorded in the handoff. |
| 2 | Create and verify a complete pre-cutover Git bundle. | `git bundle verify` reports complete history and contains the active branch. |
| 3 | Publish the source-repository landing page move notice. | Legacy docs workflow succeeds and both canonical links render. |
| 4 | Create the public target repository using the target-org HCS GitHub App. | New repository ID and URL resolve. |
| 5 | Mirror source branches and tags; separately push unpushed local work. | Branch/tag object IDs match and active branch head is exact. |
| 6 | Clone the independent target repository at the canonical local path. | `origin` points directly to `Hybrid-Solutions-Cloud/azure-scout`. |
| 7 | Apply migration-only URL, manifest, docs, workflow, generated-link, and AI workspace updates to target main. | No unintended live source URLs remain; manifest, parser, docs, and focused tests pass. |
| 8 | Recreate release records, protections, Actions settings, environments, and Pages configuration. | Recent releases resolve, protections match, workflows run, and Pages serves the site. |
| 9 | Update the HCS Governance registry and related platform references. | MCP source identifies `azure-scout`, target org, canonical path, and VitePress. |
| 10 | Fix the recovered raw-inventory test failures and run the full collector/Pester gates. | Zero failures, skips, not-run tests, and failed containers on one exact commit. |
| 11 | Merge/release only after code, CI, documentation, package metadata, and full tests are green. | Release evidence and final handoff recorded. |

## Execution gates

### Gate 1 — safe to create and mirror

- Target repository name is free.
- HCS target-org GitHub App can create and administer the repository.
- Verified bundle includes the current local branch and complete history.
- Source landing-page notice builds successfully.

### Gate 2 — safe to make the target canonical

- Branch/tag names and object IDs match the source.
- Recovered product branch resolves to its exact local commit.
- Canonical main contains migration-only changes, not untested product fixes.
- Local canonical clone has the target `origin` and a clean working tree.

### Gate 3 — safe to merge or release product work

- Documentation, manifest, link, parser, and CI gates pass.
- GitHub Pages and legacy landing links pass root/deep-link checks.
- The recovered collector failures are fixed.
- Complete automated and collector acceptance gates pass on one exact commit.
- PowerShell Gallery metadata is correct for the package being published.

## Rollback plan

### Triggers

- Critical refs or tags do not match.
- The target cannot run required Actions or publish Pages.
- Canonical URLs remain unavailable or misleading.
- Security controls cannot be reproduced promptly.

### Steps

1. Stop target merge, release, Pages, and package-publishing activity.
2. Keep `thisismydemo/azure-scout` active as the authoritative code/history location.
3. Change its landing page back from the move notice if the target will remain unavailable.
4. Preserve any target-only commits in a new verified bundle and branch before changing visibility.
5. Restore canonical links and PowerShell metadata to the source locations on a reviewed branch.
6. Re-run ref, Pages, CI, and release checks before attempting cutover again.

### Recovery artifacts

- Verified bundle: `D:/tmp/azure-scout-pretransfer-final-20260812-1023.bundle`
- Source repository ID: `1164382922`
- Target repository ID: `1332126664`
- Legacy landing commit: `406cbabf1f81bfaa961532194f1773ec999e958a`

## Communication

| Audience | Message | Timing |
|---|---|---|
| Maintainers | New repo/local path, remote update, historical-object boundary, and test status. | After cutover verification. |
| Module users | Same module and commands; new docs and code home. | Legacy landing page and next release. |
| Gallery users | Project links now use the HCS documentation/source locations. | Current-page edit where possible and next release. |

## Authorization

The operator explicitly replaced the ownership-transfer approach with this copy-and-cutover method
on 2026-08-12. The source repository must remain intact. Merge and release authorization remain
separate from authorization to create and populate the target repository.
