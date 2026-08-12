# Change Request: Move AzureScout to Hybrid-Solutions-Cloud

**Requester:** Kristopher Turner  
**Date:** 2026-08-12  
**Priority:** High  
**Status:** In progress  
**Work item:** AB#7279

## Description

Move the public `azure-scout` repository from the `thisismydemo` GitHub organization to
`Hybrid-Solutions-Cloud`. Make the new GitHub Pages site the canonical project website, preserve
the existing `https://thisismydemo.cloud/azure-scout/` entry point as a temporary redirect, update
PowerShell Gallery metadata and repository references, and then complete the interrupted collector
test gate.

## Why this change is needed

AzureScout is an HCS product and should be owned, secured, documented, and released from the HCS
GitHub organization. The move gives users one canonical HCS location without breaking existing
bookmarks, package links, clones, issues, releases, or action references.

## Target state

| Area | Target |
|---|---|
| GitHub repository | `https://github.com/Hybrid-Solutions-Cloud/azure-scout` |
| Canonical documentation | `https://hybrid-solutions-cloud.github.io/azure-scout/` |
| Legacy documentation | `https://thisismydemo.cloud/azure-scout/` redirects to the canonical site |
| PowerShell Gallery `ProjectUri` | Canonical documentation URL |
| PowerShell Gallery source/license/icon | `Hybrid-Solutions-Cloud/azure-scout` URLs |
| Git remote | `origin` points directly to the new repository URL |
| Release gate | Complete collector and automated test suite passes on one exact commit |

## Impact analysis

| Area | Impact | Details |
|---|---|---|
| Users | Medium | Existing GitHub links and clones should redirect; documentation bookmarks need a Pages redirect because GitHub Pages URLs do not transfer as redirects. |
| Maintainers | Medium | Repository location, app installation, branch protection, Actions permissions, Pages, and release procedures must be revalidated. |
| Automation | Medium | Reusable action references, badges, source links, generated board links, and docs edit links change organization. |
| PowerShell Gallery | Low | Existing package pages keep their published metadata until edited; the next package version must publish the new manifest URLs. |
| Cost | None expected | GitHub Pages and current release infrastructure remain in use. |

## Risk assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Transfer loses or hides refs, issues, releases, or settings | Low | High | Record counts and IDs before transfer; create and verify a complete Git bundle; validate the stable repository ID and all critical refs afterward. |
| New Pages site is unavailable | Medium | High | Retain the transferred `gh-pages` branch, verify Pages source/settings, trigger a documentation deployment, and test root plus deep links. |
| Old documentation URL breaks | Medium | High | Host a move page and deep-link redirect in the `thisismydemo.github.io` site before transfer; verify it after the old repo Pages route is released. |
| Actions or Pages cannot deploy in the new org | Medium | High | Verify GitHub App installation, Actions permissions, workflow token permissions, environments, secrets, and a real workflow run. |
| Existing external action consumers are disrupted | Low | Medium | GitHub repository URLs redirect after transfer; update all first-party `uses:` examples and retain existing tags. |
| PowerShell Gallery shows stale links | High | Low | Edit the current package page where supported and ensure the 3.12.3 manifest publishes matching URLs. The legacy project URL redirects during the transition. |
| Product changes are released without a clean test gate | Medium | High | Keep the 3.12.3 branch separate from `main`; fix recovered failures and require one complete zero-failure, zero-skip suite before merge or release. |

## Implementation plan

| # | Task | Owner | Dependency | Acceptance evidence |
|---:|---|---|---|---|
| 1 | Inventory repository ID, branches, tags, releases, issues, Actions, Pages, custom domain, package metadata, and inbound URLs. | Codex | None | Inventory recorded in the session handoff. |
| 2 | Create and verify a complete pre-transfer Git bundle. | Codex | Inventory | `git bundle verify` reports complete history and includes the active branch. |
| 3 | Publish the legacy root and deep-link redirect at the `thisismydemo.github.io` organization site. | Codex | Canonical URL selected | Organization-site deployment succeeds. |
| 4 | Update repository, documentation, action, workflow, generated-link, and PowerShell manifest URLs on the active branch. | Codex | Target names selected | No live old URLs remain; manifest, parser, and docs build pass. |
| 5 | Transfer the repository using an owner credential brokered by HCS Governance. | Codex | Target name free; source admin and target membership verified | GitHub returns an accepted transfer and stable repository ID is unchanged. |
| 6 | Verify refs, tags, issues, releases, redirects, collaborators, branch rules, Actions settings, secrets, environments, and app access. | Codex | Transfer complete | Post-transfer inventory matches pre-transfer inventory or differences are documented. |
| 7 | Change `origin`, push the active branch with the target-org HCS GitHub App token, and open/update the PR. | Codex | Target app access verified | Branch exists in the target repo and PR checks start. |
| 8 | Configure/verify Pages and deploy the documentation from `main`/`gh-pages`. | Codex | Transfer complete | Canonical root and representative deep links return the expected site. |
| 9 | Verify the legacy documentation redirect after GitHub releases the old repo Pages route. | Codex | Transfer and Pages cutover | Root and deep links route to the equivalent canonical path. |
| 10 | Update the current PowerShell Gallery package page where the Gallery permits, and verify the 3.12.3 manifest metadata. | Codex/operator | Gallery publisher access; validated release | Gallery project, license, and icon links resolve to the new locations. |
| 11 | Reproduce and fix the three recovered `Collect.RawInventory.Tests.ps1` failures. | Codex | Repository moved | Focused suite passes with no failed containers. |
| 12 | Run the complete collector/live acceptance and all 134 Pester files against one exact commit. | Codex | Focused failures fixed | Zero failures, skips, not-run tests, and failed containers; results retained. |
| 13 | Merge/release only after CI, documentation, package metadata, and full product tests are green. | Operator/Codex | All gates pass | PR merged, release evidence recorded, handoff updated. |

## Execution gates

### Gate 1 — safe to transfer

- Target repository name does not exist.
- Source credential has repository administration permission.
- Credential owner is an active member/owner of the target organization.
- Verified bundle includes all refs and the current local branch.
- Legacy redirect is deployed.

### Gate 2 — safe to publish migration branch

- Repository ID and critical counts match the source inventory.
- New URL resolves and the old GitHub URL redirects.
- HCS target-org GitHub App can read and push the repository.
- Local `origin` is the new direct URL.

### Gate 3 — safe to merge or release

- Documentation and link contract tests pass.
- GitHub Pages and legacy redirects pass root/deep-link checks.
- The three recovered collector failures are fixed.
- Complete automated and collector acceptance gates pass against one exact commit.
- PowerShell Gallery metadata is correct for the release being published.

## Rollback plan

### Rollback triggers

- Stable repository ID changes or critical refs/history are missing.
- Required issues, releases, tags, app access, or security controls cannot be recovered promptly.
- The new organization cannot run required Actions or publish Pages.
- The old and new documentation entry points cannot be made usable during cutover.

### Steps

1. Stop merge, release, Pages, and package-publishing activity.
2. Preserve post-transfer evidence and any new refs in a second verified bundle.
3. Transfer the unchanged repository back to the source organization when GitHub permits it, or
   restore a replacement repository from the verified bundle if ownership transfer cannot be
   reversed immediately.
4. Restore the previous `origin` URL for maintainers.
5. Re-enable the prior Pages source/custom-domain configuration.
6. Keep the legacy notice active and update it with the temporary canonical location.
7. Re-run repository/ref, Pages, and release verification before reopening work.

### Recovery artifacts

- Latest verified bundle: `D:/tmp/azure-scout-pretransfer-final-20260812-1015.bundle`
- Source repository stable ID: `1164382922`
- Legacy redirect deployment: `thisismydemo/thisismydemo.github.io` workflow run `31604230132`

## Communications

| Audience | Message | Channel | Timing |
|---|---|---|---|
| Maintainers | New repository URL, remote update command, branch/PR status, and test gate. | GitHub/ADO | Immediately after transfer verification. |
| Module users | Repository and docs moved; existing links redirect; no command/module-name change. | Docs and release notes | At merge/release. |
| Gallery users | Project links now use the HCS documentation and source locations. | PowerShell Gallery package metadata | Current-page edit and next release. |

## Approvals

The operator explicitly requested the repository move and revised the execution order on
2026-08-12. Merge and release approval remain separate from authorization to transfer the
repository.
