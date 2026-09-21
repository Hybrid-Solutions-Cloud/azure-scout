# Customer-run reliability investigation

Date: 2026-09-18
Status: Original incident reconciliation is blocked on missing execution evidence. Report parity is now implemented locally on feat/customer-report-parity; see CURRENT_TASK.md and HANDOFF.md for scope and verification. Multi-tenant changes remain outstanding.
Baseline: local main, module 3.16.2. Existing CURRENT_TASK.md and HANDOFF.md edits preserved.

## Objective

Resolve collection and report trust problems demonstrated by the customer assessment, and design implementable fixes for multi-tenant authentication, failed-tenant recovery, and the guided menu. Deliver root causes, evidence, acceptance criteria, and a verified implementation sequence. Initial priority is multi-tenant usability and reliability. This document records investigation, not a claim that fixes have shipped.

## Evidence boundaries

The supplied folder D:/tmp/Gentherm Assessment Report contains 85 JSON files, 51 backup files, and one HTML report. No execution-log files were found in that folder. These are manually corrected deliverables and cannot establish the original collector behavior by themselves. Customer files remain untouched and must not be copied into source control.

The supplied timeline reports the August 14 run, August 31 repair work, September 1 customer export, and September 4 rescoring. Treat its numerical claims as operator-reported until compared against original evidence. Existing handoff records describe subsequent 3.14.0 collection fixes (AB#7366), 3.15.0 evidence completeness work (AB#7441), and 3.16.2 orchestration fixes (AB#7105). Do not assume every August defect remains unfixed, or that historical passing tests validate this customer's current experience.

## Confirmed source findings and proposed work

| Priority | Finding | Implementable change | Acceptance evidence |
| --- | --- | --- | --- |
| P0 | Connect-AZTILoginSession.ps1 handles DeviceLogin before context reuse; default login reuses current/cached contexts but otherwise invokes interactive Connect-AzAccount. The orchestrator copies authentication parameters to each child. | Separate initial identity authentication from tenant context acquisition; validate account, cloud, tenant, and token usability; reuse valid sessions before device-code fallback; explicitly classify interaction-required failures and allow remaining tenants to proceed. Verify supported Az behavior before selecting an API implementation. | Five-tenant scenario with reusable authentication generates no unnecessary prompts; expired token, missing context, guest access, device code, different cloud/account, and interaction-required cases covered. Never reuse a token for the wrong tenant. Real tenant-policy challenges remain explicit. |
| P0 | Start-AZSCWizard.ps1 asks Select the tenant to scan before How many tenants do you want to scan. Declining Use this account and tenant forces login even when the intent is only to change tenant. | Separate account selection from scan scope. Authenticate only if needed, discover tenants, choose one/selected/all, then choose target tenants if required, configure scope, and confirm once. | Fresh and existing sessions reach all-tenant scan without first selecting an arbitrary tenant; changing tenant does not imply changing account; cancel/empty selection never silently broadens scope. |
| P0 | Invoke-AZSCMultiTenantRun.ps1 catches tenant failures and continues, but exposes no persisted-run resume or failed-only retry entry point. | Add versioned checkpoint loading, failed/interrupted/pending selection and explicit single-tenant retry within the original umbrella. Preserve successful tenant artifacts and attempt history; validate paths and compatible settings; never persist credentials. | A five-tenant run with one failure completes four; retry executes only the failed tenant. Restart after interruption resumes pending/interrupted tenants; completed artifact hashes stay unchanged; corrupt/incompatible checkpoints fail clearly. |
| P0 | Orchestrator marks a tenant Completed even when no typed run result or report is found. | Require explicit child completion evidence and distinguish failed, partial, skipped, interrupted, and complete states. Protect checkpoint/export failure handling so it cannot silently invalidate continuation. | Missing result/report cannot become Completed; partial coverage is visible in root and child reports; injected summary-write failures are actionable. |
| P1 | report-react.html.template keyCat omits monitor.* and general.* and lacks identity in the domains map; domains.identity.* becomes General. | Establish a complete category contract and an explicit uncategorized bucket; audit every emitted inventory key against render visibility. | monitor/general/identity fixtures appear in intended categories; no evidence dataset is silently discarded; derived-only datasets have documented destinations. |

## Collection and report integrity workstreams

1. Reproduce the reported Invoke-Collect bounds exception and trace the ARG fallback using original raw inventory/logs and the actual installed package version. Compare against AB#7366 fixes before reopening the same defect. Inject a shaping failure into current code and require preserved raw evidence, explicit partial status, and no false absence-based conclusions.
2. Reconcile the reported 134 datasets, 26 shortened containers, 23,244 missing rows, and 84 omitted datasets/103,126 rows. Build a per-stage ledger: collected, normalized, assessed, rendered, excluded with reason. Counts here are operator-reported, not independently verified.
3. Separate distinct resource identities from child/evidence rows. Reported corrected counts: VMs 94, storage 105, disks 193, NSGs 42, route tables 17, private endpoints 199, private DNS zones 32. Preserve child rows but label units and use distinct stable IDs for resource KPIs and finding denominators.
4. Trace fallback identity loss and ran.entra semantics. Distinguish not requested, denied, failed, collected, empty, and rendered. Available Identity.json evidence must not disappear because ARM shaping failed.
5. Recompute findings from one canonical evidence snapshot. Include backup, compliance, AVD, CAF-MGT-04, CAF-IDN-02/05/07, and CASA-PM-01. Missing/denied evidence must not imply a definitive negative verdict. Verify reported 27/94 protected implies 67 unprotected only when those populations are exhaustive and aligned.
6. Generate HTML, assessment findings.json, root findings.json, rollup, maturity chart, and drift from one versioned assessment result. Test cross-artifact equality and intentional baseline/current drift semantics. The supplied backup JSONs provide before/after comparison material but not an unmodified run baseline.
7. Locate the Graph probe/Gap scripts before assigning ownership. Reproduce first-row CSV header loss and locale-sensitive timestamp conversion with sparse heterogeneous rows, ISO timestamps and multiple locales. Fix in product only if product owns the path; otherwise integrate a supported import/export contract with provenance and schema validation.
8. Diff the patched customer HTML against the matching shipped template to enumerate formatting fixes and missing features. Keep corrections separate from feature requests; verify generated output through browser inspection and representative fixtures. Exact requested features are not yet independently inventoried.

## Permissions and customer export

Audit the advertised minimum-permission contract per selected dataset, separating ARM roles, Graph permissions, directory roles, delegated guest access, tenant consent and licensing. The reported PIM/access-review/risky-user/sync-topology 403s need endpoint/error evidence before assigning a precise cause. Do not promise that code changes bypass customer consent or tenant authentication policies. Preserve Azure PowerShell guest-token support; do not assume Connect-MgGraph with a native customer account.

Design an optional customer export/import path that validates tenant, schema, collection time and dataset provenance, then deterministically rescores every dependent artifact. Surface actionable coverage gaps before and after scanning. A management-group registration denial alone does not establish missing management-group inventory when ARG evidence exists.

## Verification and delivery sequence

1. Acquire original customer run logs/raw inventory, the five-tenant run-summary.json and child logs, actual package versions, Az.Accounts version, invocation/authentication mode, and patched helper scripts. These are missing evidence, not permission to initiate a new customer scan.
2. Implement authentication/menu/retry as a cohesive reliability change with focused Pester tests using real PSBoundParametersDictionary and realistic child results. Validate cached-session and device-code branches, interruption, continuation and artifact preservation.
3. Repair renderer category coverage and add dataset-ledger/count-unit contracts.
4. Reconcile remaining collection defects against prior releases; implement canonical scoring/export and customer import as supported by evidence.
5. Run focused regressions, then required repository validation and an authorized controlled multi-tenant smoke test. No live tenant scans or cloud writes occurred during this investigation. No product tests have been run for this documentation-only initial pass.

## Remaining questions

- Where are the original August run logs/raw inventory and the latest five-tenant summary/child logs?
- Which installed Scout version and authentication mode produced each symptom?
- Which customer report formatting changes/features are absent from the current template?
- Are the Graph probe scripts product code or customer-specific recovery tooling?

Goal remains active until log reconciliation and the implementation-ready solution review are complete. Product fixes and release verification are not complete.

## Verified follow-up evidence — 2026-09-18

Source baseline: main at 048e995238714479fe3e2a4e49d832b2193386fb, module 3.16.2. The customer HTML identifies productVersion 3.12.8. This difference is material: customer history cannot be treated as proof of a current 3.16.2 regression without version-specific evidence.

### Customer artifact reconciliation

Read-only JSON parsing of the embedded window.__SCOUT_DATA__ payload found 310 rendered inventory datasets, 14,392 stored rows, 21 domains.identity datasets and ran.inventory/entra/assessments all true. These are properties of the corrected report, not of the original failed run. Counts of raw ReportCache collections (reported 134) and normalized report datasets (310) use different schemas and are not interchangeable.

Compared all 550 HTML findings with root findings.json using assessment name plus rule ID (HTML IDs prefix rule IDs with an assessment slug): zero missing matches and zero status mismatches. Compared all 550 findings across 41 assessment findings.json files with root findings using the same composite identity: zero missing matches and zero status mismatches. This verifies current status synchronization only, not evidence/remediation/score equivalence or historical scoring correctness.

Drift comparison found 220 unambiguous rule-ID matches with zero status mismatches. Another 93 drift records could not be uniquely resolved by rule ID; do not claim full drift consistency. Proposed correction: carry assessment identity into drift and join by assessment + rule ID, retaining an explicit ambiguity state for legacy records.

The customer artifact includes compute.vmDisk with 193 rows and domains.storage.managedDisks with 159 rows. Preserve both and label the population; do not globally substitute 193 as the managed-disk resource count. Other corrected report counts include 94 compute.virtualMachines, 105 domains.storage.storageAccounts, 199 private endpoints, 32 private DNS zones and 17 route tables. Some schemas omit canonical id/resourceId fields; the normalization contract needs per-dataset identity definitions rather than an assumed universal field.

Executing the current template's keyCat against the corrected payload confirms 27 monitor/general datasets (1,038 stored rows) receive no category; all 21 domains.identity datasets are miscategorized. The customer HTML has explicit monitor/general prefix handling and identity in the domain map. This is a reproducible current renderer gap, independent of the original engine failure.

Artifact fingerprints (SHA-256; customer files unchanged):

| Artifact | SHA-256 |
| --- | --- |
| assessment_report.html | 23017429305700A85E1C39F8D98A5974E6A0F7D124DBFB3F63F38F69C3DF9CDB |
| findings.json | 1480FFFA882759CBFA936DCD17CB9D338027921DA5363B3FD27D33F4915F18D7 |
| collect.json | DC790327DFDC30F1280FE75AB0E1D162455008C8885C401B1875CE1C2D5A8750 |

### Additional P0: Graph authentication and tenant isolation

Get-AZTIGraphToken.ps1: explicit delegated scopes select Microsoft.Graph.Authentication. A missing/mismatched SDK context invokes Connect-MgGraph with UseDeviceCode=true and ContextScope=Process. Fixing only Connect-AZTILoginSession.ps1 cannot remove this separate prompt source. Existing Get-AZSCGraphToken tests explicitly expect device-code login on this path.

A live-free mock reproduction dot-sourced the current helper, provided one synthetic Az user account, and called Get-AZSCGraphToken for synthetic tenants A, B, A with AuditLog.Read.All. The result was two Graph connects, an SDK provider marker returned for A, but the active SDK context still B. The helper returns cached metadata before revalidating Get-MgContext; Invoke-AZTIGraphRequest.ps1 then invokes Invoke-MgGraphRequest without a per-request tenant parameter. This proves a cache/context mismatch in the local control flow; it does not prove customer data was mixed.

Required implementation: SDK provider metadata must never substitute for verified active tenant/account/cloud/scope state. Revalidate and restore the correct context before each SDK request (including cache hits, pagination, retries and permission probes); fail closed on mismatch. Do not persist/replay SDK markers as credentials. Regression acceptance: A-B-A and A-B-retry-A use the requested tenant, account changes cannot reuse old context, different clouds remain isolated, and no request executes under an incompatible context.

Authentication design should prefer usable Az-context Graph tokens for datasets they can read, and request separately consented delegated scopes only for selected datasets that require them. Do not silently sacrifice PIM/access-review coverage just to remove prompts. Offer explicit coverage mode and interaction policy: reuse sessions, disclose missing consent, skip/defer interaction-required datasets or perform the requested consent flow. Never claim universal zero-prompt cross-tenant delegation where customer policy requires interaction. Any new provider/API choice needs a supported-library prototype, not private refresh-token extraction.

Microsoft references: [Azure context persistence](https://learn.microsoft.com/en-us/powershell/azure/context-persistence) describes context/token-cache reuse; [Graph authentication commands](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands) documents process-scoped sessions and delegated/app authentication. These support session reuse design but do not establish that one delegated login will satisfy every tenant's consent and access policies.

### Existing collection fixes versus remaining fallback behavior

CHANGELOG.md 3.14.0 records the sparse private-endpoint array fix; current ConvertFrom-ScoutInventory.ps1 guards connections before indexing. Current Invoke-Collect.ps1 still catches general shaping failures, emits a warning and resets inventoryShaped for live ARG fallback; OfflineFromInventory instead throws. The general fallback exposure remains, even though the specific historical array defect has a source fix. Preserve Graph/raw evidence independently of ARM shaping and make fallback coverage explicit. Exact historical trigger and remaining dataset loss require original raw evidence.

The old handoff's C:/Users/KristopherTurner/Desktop/scout-run.log now contains August 18 evidence, not the August 14 customer log. It includes a Graph permission failure, Key Vault metadata denials and operational enrichment failures for a different run. Do not cite it as the original customer incident or copy its infrastructure identifiers into the issue reference.

### Customer report functionality absent from current named-function surface

The patched HTML adds row-detail popups, human-readable property labels, structured long-value display, portal/guidance links, action-list helpers, region/traffic-flow/SD-WAN availability/backup diagrams, and customer-specific regional storage/path diagrams. Source inspection confirms the popup implements those display improvements. Function-name comparison establishes implementation differences, not necessarily absence of every equivalent feature.

Proposed product backlog: generalize the row detail and readable-value experience; compare action-list behavior with current assessment pages; add reusable topology/backup visualizations only from supported evidence contracts. Keep customer-specific geography, naming and topology assumptions out of the product. Acceptance includes keyboard-accessible dialogs/focus return, escaped untrusted values, readable long/nested values, offline rendering, complete evidence exports, and diagrams that show unknown coverage rather than inferring a healthy topology. A browser/visual comparison remains necessary to inventory exact formatting defects and any equivalent current features.

### Permissions scope and documentation corrections

Current Get-ScoutEntraQueryCatalog.ps1 requires explicit delegated scopes for directory assignment/eligibility schedules, access reviews and risky users; it records supported directory roles separately, and a licensing gate for risky users. This is evidence of the product's current contract, not independent validation of all endpoint requirements. Original 403 response bodies are needed to distinguish missing scope, directory role, tenant consent, licensing and guest restrictions.

The guide mixes blanket Reader claims, management-group scope caveats and an older assessment/Graph model with newer scope-aware collection. Generate a selected-dataset permission matrix from collector definitions and cross-check it against Microsoft endpoint documentation. Separate minimum viable inventory from complete selected-scope coverage. Pin endpoint/version, role/scope/license, auth provider and coverage consequence for every optional dataset. Customer export/import must preserve collection time and source identity, and regenerate all dependent findings, scores and drift using one canonical snapshot.

### Concrete implementation sequence and gates

1. Authentication/tenant isolation: Get-AZTIGraphToken.ps1, Invoke-AZTIGraphRequest.ps1, Connect-AZTILoginSession.ps1 and their tests. Gate on A-B-A isolation, cached device-code session reuse, account/cloud changes and explicit interaction-required handling.
2. Wizard scope ordering: Start-AZSCWizard.ps1 and entry-point tests. Gate on existing-account single/selected/all paths, fresh sign-in, cancellation and no redundant tenant selection.
3. Recovery: Invoke-AzureScout.ps1, Invoke-AZSCMultiTenantRun.ps1, multi-tenant overview and tests. Proposed public switches (not implemented): ResumeRun <root>, RetryFailed, RetryTenant <selected IDs>. Validate one existing root and manifest schema/settings; retain attempt history and use new attempt directories; atomically update root links only after validated completion; never overwrite successful evidence. Mark stale Running as Interrupted on explicit resume; lock against two writers. Runtime manifests need tenant identifiers but must remain local evidence and never enter source control. Persist only non-secret settings and reacquire authentication. Gate on four-success/one-failure replay, crash/restart, corrupt manifest, settings mismatch and summary-write failures.
4. Renderer category/row-unit contracts, then canonical scoring/export/drift identity and optional customer import. Use anonymized synthetic fixtures, not customer raw data.
5. Reconcile any additional original-log defects before release. Focused checks demonstrate only their own contracts; require packaged-module smoke tests, required full validation and controlled real multi-tenant acceptance before claiming release readiness.

### Follow-up validation and residual boundaries

Focused existing Pester suites passed 48/48, zero failed/skipped/not-run in 140.36 seconds: Connect-AZSCLoginSession (15), Get-AZSCGraphToken (7), Invoke-AZSCGraphRequest (17), MultiTenantRun (9). These test existing behavior and do not cover the newly reproduced A-B-A SDK-context mismatch, persisted resume, or the complete customer flow. Passing them is not evidence that the reported experience is fixed. Earlier initial-pass statements that no tests had run are superseded by this result. git diff --check passes (existing line-ending warnings only).

Get-ScoutDrift.ps1 explicitly keys its current findings map by bare Id. The customer root has 550 findings but 313 distinct rule IDs; 93 rule IDs recur across assessments and a bare-ID map collapses 237 entries. All repeated IDs currently have consistent statuses. This establishes lost assessment identity, not an observed contradictory current status. Decide and document whether drift is per unique rule or per assessment rule; if per-rule by design, retain all assessment memberships and reject conflicting duplicates instead of last-write-wins. If per-assessment, migrate history to composite identities. Both paths must avoid silent overwrites.

The current hybrid local-evidence collector uses Get-ADSyncScheduler, Get-ADSyncConnector, Get-ADSyncGlobalSettings, CIM and services on the collection host. Cloud Graph consent alone cannot populate that local topology contract. Reconcile the customer's export schema before promising that every Entra Connect topology gap is fixed through Graph consent.

No ConvertTo-FlatObject implementation was found in src/tests/scripts. The specific Graph probe corruption remains operator-reported external-tooling behavior until its scripts are supplied; do not report it as a reproduced current Scout defect.

Still missing for full incident reconciliation: original August 14 execution log/raw ReportCache; latest five-tenant run-summary and child logs/invocation details; Graph probe/customer export scripts. A text question requesting their locations was sent. Browser-level formatting verification and exact customer-specific feature acceptance remain open; source comparison has identified concrete reusable enhancements without copying customer assumptions.

### Final independent review — 2026-09-18

Consolidated issue reference and requirement-by-requirement completion audit: [CUSTOMER_RELIABILITY_ISSUES.md](CUSTOMER_RELIABILITY_ISSUES.md). Customer/current CSS comparison found 30 customer-only selectors, including the row-detail popup family. Current template's existing dialog marker belongs to About, not a row-detail popup; no showRowPopup/ROWREG/rowclick implementation was found there. Visual inspection attempted with CUA getBrowser on the local customer file returned No browser is available. No substitute UI automation or customer-data upload was used.

Confirmed root completion logic also ignores a typed child's Status before assigning Completed. Acceptance must validate child tenant identity, terminal status and required artifacts, not just absence of an exception.

Original evidence remains missing after three goal turns. All available independent investigation needed to define the proposed solutions is recorded; full incident reconciliation and visual verification cannot be claimed. No product fix has been implemented. Status is blocked pending original customer/five-tenant evidence and recovery/export scripts; confirmed implementation slices remain ready to execute separately.
