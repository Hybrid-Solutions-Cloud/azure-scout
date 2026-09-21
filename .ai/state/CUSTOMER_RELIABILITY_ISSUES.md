# Azure Scout customer reliability issue reference

Date: 2026-09-18. Baseline: local main 048e995238714479fe3e2a4e49d832b2193386fb, version 3.16.2. Customer corrected HTML declares version 3.12.8.

Confirmed fixes are released in AzureScout3.17.0 (AB#9290, merged PR #16). GitHub and PowerShell Gallery publication and fresh-download verification are complete. Original incident attribution and external helper/import questions remain open as stated below. Detailed evidence, fingerprints and acceptance cases: [CUSTOMER_RELIABILITY_PLAN.md](CUSTOMER_RELIABILITY_PLAN.md).

The investigation tables below record the original findings and proposed acceptance gates. The final **Implementation delivery update** section supersedes their implementation/status statements (including the former browser limitation and proposed command names).

## Implement first

| ID | Priority / evidence | Root cause and proposed change | Acceptance gate |
| --- | --- | --- | --- |
| REL-01 | P0, reproduced offline | Graph helper caches an SDK provider marker and returns it before validating active SDK context. A-B-A returns A metadata with B active. Validate tenant/account/cloud/scopes before every SDK-backed request and restore or fail closed. | A-B-A, retry-A, account/cloud changes, pagination and permission probes never execute under the wrong identity/context. |
| REL-02 | P0, source-confirmed prompt paths; customer cause awaits logs | Azure device-code branch precedes context reuse. Default Azure path prompts when no matching context exists. Graph granular-scope path independently requests device code on context mismatch. Separate identity authentication from context acquisition; reuse usable sessions; acquire only selected dataset scopes; make interaction-required coverage explicit. | Five-tenant run avoids unnecessary prompts under reusable sessions. Guest, device-code, expired token and tenant-policy challenges are exercised. No private token-cache extraction or false promise of universal single sign-on. |
| REL-03 | P0, source-confirmed | Wizard selects one tenant before asking single/selected/all and conflates changing account with changing tenant. Change flow to account reuse/sign-in, tenant discovery, scope choice, target selection, run settings, one confirmation. | No arbitrary single-tenant selection on the all-tenant path; no forced login merely to change tenants; cancellation cannot broaden scope. |
| REL-04 | P0, source-confirmed | Per-tenant exceptions continue today, but no persisted resume/failed-only retry entry point exists. Extend versioned run-summary into a checkpoint with attempt history, sanitized settings and selected retry targets. | Four successful tenants remain byte-identical while only the fifth is retried. Interrupted process recovery, writer locking, corrupt/incompatible checkpoints and settings mismatches are covered. |
| REL-05 | P0, source-confirmed | Orchestrator marks Completed after a nonthrowing child even without a typed result/report; it does not propagate the child's Status. Validate result identity/status/artifacts and expose partial/failed/interrupted states. | Missing result/report, wrong tenant result or partial child cannot become a clean Completed tenant. Summary-write errors preserve evidence and have an actionable recovery path. |
| REL-06 | P1, executed against customer payload | keyCat omits monitor/general and domain identity mapping. Add complete category contract and an explicit uncategorized destination. | All 27 affected datasets/1,038 stored rows are reachable; 21 identity datasets appear under Identity. No collected dataset silently disappears. |

## Evidence integrity and customer report work

| ID | Classification | Proposed work and verification |
| --- | --- | --- |
| REL-07 | Historical bounds bug has a later source fix; broad fallback remains | Reconcile the original crash with 3.14.0 sparse-array guards. Preserve raw and identity evidence when ARM shaping fails. Inject shaping failure and require explicit coverage loss, no false absence-based verdicts, and a dataset-level collected/normalized/assessed/rendered ledger. |
| REL-08 | Row/resource distinction confirmed; historical totals partly unverified | Define stable identity and count units per dataset. Preserve child rows. Customer payload has 193 VM-disk rows and 159 managed-disk inventory rows, so these must not share an unlabeled disk total. Verify denominators and backup arithmetic against matched populations. |
| REL-09 | Corrected statuses synchronized; original verdict derivations unverified | Recompute all dependent findings/scores/charts/exports from one canonical snapshot with provenance. Current 550 HTML/root/companion statuses agree across 41 assessment files; this is not proof of original engine correctness or every field's consistency. Recheck named CAF/CASA/backup/compliance findings using original and imported evidence. |
| REL-10 | Drift identity loss confirmed; contradictory current duplicate statuses not observed | Current drift uses bare rule ID, collapsing 550 assessment findings to 313 rules. Choose explicit per-rule aggregation with assessment membership and conflict detection, or per-assessment identities with history migration. Test conflicting duplicates and corrected baselines. Baseline New can be valid while CurrentStatus must reflect current evidence. |
| REL-11 | External Graph probe bugs reported; source missing | Obtain ConvertTo-FlatObject and export scripts before assigning ownership. Test sparse first rows, union headers, invariant ISO timestamps, multiple locales and dormant-user calculations. Productize only the supported import/export contract; keep customer recovery tooling distinguishable. |
| REL-12 | Customer-only row popup/formatting confirmed in source; visual verification unavailable | Generalize readable labels, structured long/nested values, detail popup, portal/guidance links and action-list behavior. Test escaping, keyboard/focus behavior, offline use, long rows, print layouts and complete exports. Compare diagrams as feature requests; remove customer-specific geography/naming/topology assumptions. |

## Permissions and customer-side recovery

REL-13: Produce a generated selected-dataset permission matrix from catalog metadata and independently verify endpoint requirements. Separate subscription/management-group ARM scope, vault metadata access, Graph scopes, directory roles, consent, licensing and guest-account behavior. Minimum viable inventory must not be described as complete coverage. Current code distinguishes granular delegated Graph scopes from directory roles; the reported original 403s still need response evidence for exact attribution.

REL-14: Add a supported customer evidence import path with tenant/schema/time/provenance validation and deterministic rescoring. Preserve source files and record superseded evidence. Current local Entra Connect topology collection uses ADSync/CIM/service commands on the collection host; Graph consent is not a substitute for those local reads. Inspect the September customer export schema before promising import compatibility.

Management-group registration denial is not proof of absent management groups when another source contains them. Merge source coverage deliberately and retain the reason one acquisition path failed.

## Suggested delivery slices

1. Tenant isolation and authentication reuse, then wizard ordering. Treat Graph and Azure paths as one acceptance boundary.
2. Checkpoint/retry and truthful root/child completion status, including failure during summary export.
3. Renderer categories and row-detail usability, with normalized count-unit contracts.
4. Dataset coverage preservation, canonical assessment artifacts, drift identity and supported customer import.

Each slice requires focused regressions and package-level verification. Final release acceptance needs required repository gates and an explicitly scoped real multi-tenant smoke test. No customer tenant scan was performed in this investigation.

Proposed recovery switches are design names, not existing commands: ResumeRun <root>, RetryFailed, RetryTenant <selection>. Resume must use new attempt directories and preserve successful artifacts; persist no credentials. The existing single-TenantID invocation can start a separate scan, but does not merge that scan into the original umbrella or provide checkpoint recovery.

## Verification and completion audit

| Requirement | Evidence / status |
| --- | --- |
| Inspect supplied folder | Complete: 85 JSON, 51 backups, one HTML; no execution logs. Customer files unchanged. |
| Compare customer report to current source | Payload, category behavior, named-function and CSS comparisons complete. Visual comparison blocked: CUA reports no browser available; native UI is disabled. |
| Trace reported engine/fallback failure | Current source and historical release notes reconciled; original failure/raw dataset losses remain unverified without original logs/ReportCache. |
| Explain repeated tenant prompts | Both Azure and Graph prompting branches located. Exact branch in customer's five-tenant run awaits logs/auth mode. |
| Specify continuation/retry and menu fix | Implementation boundaries and regression gates defined in REL-03/04/05 and detailed plan. |
| Reconcile scoring and drift | Current status equality verified. Historical verdict correctness, maturity/chart values and full source-to-report completeness remain unverified. |
| Distinguish bug versus permission ceiling | Current contracts reviewed; original 403 attribution and export compatibility await source evidence. |
| Durable reference and actionable plan | This reference plus detailed plan, current task and handoff maintained locally. No ADO items, commits or releases claimed. |
| Existing regression baseline | Four focused suites: 48 passed, zero failures/skips/not-run. They do not cover newly found A-B-A mismatch or resume. |

## Missing inputs that prevent full incident reconciliation

- Original August 14 run log, console/transcript and raw ReportCache/Identity evidence. The prior handoff's desktop log path now holds a different August 18 run.
- Latest five-tenant root run-summary.json, failed-child logs, invocation/auth mode and installed module versions.
- Gap/Graph probe scripts, customer export scripts/schema and intended formatting/feature changes not evident from the patched HTML.

The original folder and known historical log location were rechecked. Locations were requested in the conversation. The investigation is blocked on this evidence for final root-cause attribution; the confirmed fixes above can be implemented independently. Do not label the overall incident fully reconciled until these inputs are checked.
## Implementation delivery update - AB#9290

Commit 10a05f90 implements the code changes; 64557bb5 makes public-repository CI runnable on isolated hosted runners because the shared HCS group excludes public repositories. PR: https://github.com/Hybrid-Solutions-Cloud/azure-scout/pull/16. No organization runner access was changed.

- REL-01/02: SDK markers are revalidated against current tenant/account/cloud/scopes. Matching Az contexts are checked before device-code login; tenant tokens/contexts can be acquired silently. Children cannot start interactive authentication. Default Graph collection uses Az tokens; preconnected matching SDK contexts remain supported. Five-tenant and A-B-A regressions pass.
- REL-03: account choice, tenant discovery, one/selected/all scope, then individual selection. Empty selection cancels.
- REL-04/05: v2 checkpoint resume, failed/selected retry, per-attempt directories/history, same-account/version/settings checks, writer lock, interrupted-state recovery, typed result identity and artifact checks, Partial preserved. Older v1 runs require a separate single-tenant invocation because original settings cannot be reconstructed safely.
- REL-06/08/12: complete processed inventory retained and categorized; evidence-row/distinct-ID units; detail dialogs and CSV/JSON export; evidence-derived diagrams; responsive and print fixes. Resource U is a collector counter, not a resource identity, and is excluded from distinct-ID counting.
- REL-07: normalization failure no longer substitutes a narrower ARG assessment. Scoring fails closed; combined/offline inventory retains raw/identity evidence and failure health. Original August crash attribution remains dependent on original logs.
- REL-10: assessment plus rule identity prevents drift overwrites. Legacy bare-rule histories start new per-assessment baselines rather than claiming comparable prior evidence.
- REL-13: catalog-derived requirements appear in reports with Identity cache; docs separate token scopes, directory roles, consent, guest limits and licensing. No permissions were granted or bypassed.
- REL-09/11/14: all 550 corrected saved verdicts match the renderer replay. Product inventory CSV preserves union headers and JSON timestamps. Historical rescoring, external helper fixes and compatibility with the September export cannot be verified without the original evidence and helper/export schemas. No external importer or historical recomputation is falsely claimed.

Validation in progress: focused49 + inventory-count4 + release-contract17 tests pass, lint0 errors, StrictMode guard clean, source secret scan clean, docs build and fresh 526-file package import pass. Full local batch0 passed911; batch2 passed858 with one mock isolation issue subsequently fixed and covered by focused rerun; batch1 remains running. Headless Edge verified desktop/mobile, keyboard row details/escape, complete CSV download, diagrams and light print palette. No live customer tenant scan. Original customer report unchanged.

Final release gate:3.17.0 published on GitHub and Gallery from merged ee8c62fb. Final CI3898/3898 passed; fresh Gallery download526/526 files matches and import passed. Remaining open items are historical incident evidence and external helper/export schemas (REL-09/11/14), not an unpublished code change. Recovery applies to new v2 checkpoints; old v1 runs can rescan only the failed tenant via the documented single-tenant invocation.
