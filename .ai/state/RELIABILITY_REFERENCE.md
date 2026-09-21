# Azure Scout reliability reference

Updated 2026-09-19. This is the standing record for the customer-report corrections, multi-tenant experience, and completed September scan investigation. Customer artifacts are read-only and are not committed to the public repository.

## Evidence and limits

The customer reference is `D:/tmp/Gentherm Assessment Report/assessment_report.html`, with `collect.json`, `evidence.json`, and `findings.json` in the same directory. The original August run logs, external Graph export scripts and complete customer-side export history are not present in that directory. The folder also contains per-assessment companions and 51 backup JSON files: 137 files in total, with no log or script files. Historical claims from the operator are useful incident reports, but are not all independently reproducible from these report snapshots.

The directly inspected September run is `C:/AzureScout/2026-09-18_162019_581_d6fc73cf`: main log, transcript, health ledger, raw inventory, discovery cache and assessment artifacts. It completed in 4h54m24.899s. Investigation established repeated discovery, repeated query parsing, evidence retaining parent JSON trees, repeated companion serialization, six collection/logging defects, and misleading transcript pipeline-stop entries.

## Work and acceptance evidence

| Concern | Classification and solution | Tracking / verification |
| --- | --- | --- |
| Silent fallback after inventory normalization failure | Product defect: stop scored assessments on failed normalization; retain partial inventory and explicit health, rather than substituting narrower ARG evidence. | Released 3.17.0, AB#9290; normalization/partial-run tests. Original August exception stack remains unavailable. |
| Identity evidence missing from reports | Preserve processed identity datasets and inventory categories; distinguish collection failure from unavailable scopes/licensing. | Released 3.17.0 complete processed inventory and catalog-derived identity requirements. |
| Inflated resource totals | Denormalized child rows are evidence rows, not distinct resources. Preserve both measures and show their units. | 3.17.0 report/inventory contract tests. Never hardcode customer counts. |
| Customer report inventory/formatting/diagrams | Standard report retains all processed datasets, detail dialogs, readable properties, all-row CSV/JSON exports, inventory category views and evidence-driven regional/network/availability/backup/storage diagrams. | Released 3.17.0, AB#9290. Reference HTML remains a fixture; diagrams must use current evidence and identify unknown/conceptual relationships. |
| Incorrect historical verdicts, stale companions and drift | Regenerate from the same supported collection snapshot; detach finding evidence, maintain assessment-qualified drift identities, and write consistent root/per-assessment companions. | 3.17.0 drift fixes; 3.17.1 AB#9304/9306. September replay preserves all 550 finding verdicts and evidence counts. Historical customer-side manual rescoring cannot be independently validated without the exact export inputs. |
| External CSV header loss / localized timestamps | Reported defects in external export scripts. Their source is not in the supplied folder. Require a union of row keys and invariant ISO timestamps when those scripts are recovered; do not infer inactivity from localized or missing dates. | Unverified external-script issue, not represented as a released Scout patch. |
| Guest identity / PIM / access reviews / risky users | Authorization, token scopes, consent, licensing and host topology are separate requirements. Use the selected Azure identity, or a matching preconnected Graph SDK context. Do not silently initiate another Graph login or bypass consent. | 3.17.0 recovery guide and scope tests; September health ledger retains real permission/license boundaries. |
| Repeated interactive tenant login / confusing scope menu | Reuse the initial account/context, acquire child contexts silently, select one/selected/all scope before asking for a single tenant. | Released 3.17.0, AB#9290. Tenant-auth and wizard tests. |
| Continue/retry failed tenant | Versioned locked checkpoint; retry failed/partial/interrupted attempts or selected tenant into a new attempt folder, preserving successes. | Released 3.17.0. `-ResumeRun`, `-RetryFailed`, `-RetryTenant`; see `docs/how-to/multi-tenant-recovery.md`. |
| Menu says tags in Excel | Correct report-facing wording and help. | Included in PR17 / 3.17.1. |
| Sign-in HTTP400 | Unsupported beta property was selected from v1.0. Remove it from the v1.0 catalog. | AB#9294, PR17. Graph catalog/regression tests. |
| Schema errors called permission denials | Classify actual HTTP status; prescribe directory roles only for 403, and retain request/service details otherwise. | AB#9295, PR17. Tests cover 400 versus 403. |
| Sentinel connectors HTTP400 | Read-only service probe confirmed workspace not onboarded. Mark that exact condition not applicable; retain other errors as unavailable. | AB#9296, PR17. Both response cases tested. |
| Sentinel ingestion query collision | Use an internal source column and preserve exported TableName. | AB#9297, PR17. Query/response contract tests. |
| Main log misses debug / SDK errors | Private Scout diagnostic capture plus request-boundary SDK capture; console preferences remain local, diagnostic records do not enter inventory, credentials are redacted, service error bodies retained. | AB#9298, PR17. Quiet-console, redaction, output-shape, exception, preference and transcript tests. |
| NIC effective-state HTTP400 | Skip known private-endpoint/detached NIC requests, preserve their envelopes with not-applicable detail; supported/unknown NICs still queried and failures retained. | AB#9299, PR17. NIC envelope/applicability and async-error tests. |
| Discovery/assessment takes hours | One run-owned discovery build and shared query context; scalar traversal guard; detached evidence and one evidence serialization for companions. | AB#9300/9302/9303/9304/9306, PR17. Full prior performance CI passed 3,909 tests; final-head CI pending. |
| Stale extraction progress | Close legacy extraction progress before processing and emit phase/request timing. | AB#9301, PR17. Progress lifecycle tests. |
| Transcript says pipeline stopped during success | First-item pipeline short circuit reproduced during discovery; replace with bounded loop. | AB#9298, PR17. Transcript regression passed; corrected actual-data discovery replay has zero occurrences. |

## Delivery state

AzureScout 3.17.1 is released and installed. [PR17](https://github.com/Hybrid-Solutions-Cloud/azure-scout/pull/17) merged at `11be3687b7b94d55e66d6acba515ad9698ba6c26`, whose tree exactly matches tested source head `85a9910a446242485fdd7ff7fac60b0e39535c2d`.

- [GitHub release](https://github.com/Hybrid-Solutions-Cloud/azure-scout/releases/tag/v3.17.1).
- [PowerShell Gallery package](https://www.powershellgallery.com/packages/AzureScout/3.17.1).
- [Final CI](https://github.com/Hybrid-Solutions-Cloud/azure-scout/actions/runs/35419964151): all 3,922 tests passed, zero failures/errors/skips/not-run; static analysis and StrictMode guard passed. Documentation built and deployed successfully.
- Independent Gallery download and installed copy both matched all 527 staged source files and imported successfully. Installed at `C:/Users/KristopherTurner/Documents/PowerShell/Modules/AzureScout/3.17.1`.
- All twelve scan bugs are Resolved in ADO: 9294–9304 and 9306. Each has the release, PR, verification evidence and remaining scope limits in its history.

The logged assessment replay retained all 550 finding verdicts/evidence counts across 41 groups with one parse (81.640 seconds). Logged discovery retained 1,535 resources and 1,602 relationships with one build (125.684 seconds; reused view 5.426 seconds), with zero pipeline-stop transcript messages. A real read-only SDK request returned HTTP 200 and wrote 80 debug records with console debug disabled; authorization was redacted and no JWT-shaped values remained. All six affected NICs were confirmed to be private-endpoint NICs without VM attachments.

These are equivalence and diagnostic checks, not an end-to-end cloud scan-duration guarantee. No new complete Azure scan was run. Genuine permissions/licensing limits remain explicit. External customer scripts and original historical verdict reconstruction still require their missing original inputs. Existing PowerShell sessions retain their loaded version; start a new session for 3.17.1.
