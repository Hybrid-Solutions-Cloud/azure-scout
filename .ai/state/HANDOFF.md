# Handoff

## Session 2026-07-31 — Epic AB#6731 "Harden Azure Scout against real-world collection and reporting failures"

Six commits on `main`, pushed (`de3bc83..d18c7ab`). Suite: **2234 passing, 4 failing** — the same
four cross-file flakes that fail on a clean tree and pass in isolation (VM quota context restore,
Excel retired-registration, two Test-AZSCPermissions scoping tests). Verified by stashing and
re-running.

### Shipped

| Commit | Items | Summary |
|---|---|---|
| `d17dc59` | 6755, 6756–6760 | `-IncludeTenantWideResources` was a dead migration gate no production caller set, so management groups, custom role definitions, policy definitions and policy set definitions were collected by nothing. Wired at both call sites. Zero added REST cost on the inventory path (the raw pass hands its ARM sweep up and the orchestration reuses it instead of repeating it); +2 calls/subscription on the assessment path via a new `-DefinitionsOnly`, measured and pinned by a test. |
| `4b1e65a` | 6761, 6778 | The four fact-check defects in §9 that an earlier pass missed, plus dropping Security/Monitoring/Cost Management Reader from the pre-flight, `docs/automation.md` and the grant list. |
| `430c04b` | 6754, 6762, 6763 | Wizard menu. 15 entries prefixed `Assess: ` with legacy names still resolving (and warning); `Estate` hidden; availability derived from whether rule files exist, not from a flag. |
| `37557e8` | 6773, 6774–6777 | The four collect-once defects: ArgQueryPack deleted, `-InventoryAndAssessment` added, tags loss in the handoff fixed, AdvisorScores fed from `$ExtractionData.Advisories` + Az context restored in a `finally`. |
| `636d65d` | 6764, 6765, 6766 | `raw-inventory.json` (everything collected, before any manifest filters), `collector-rowcounts.json` (three verdicts — Rows / Empty / Failed), and a per-collector impact table replacing the READY verdict. Graph failures now reach the warning stream from **both** the pre-flight and the extraction. |
| `d18c7ab` | 6842, 6772, 6767, 6768 | Resource-type existence gate against ground truth read from ARM. Six collectors retired, three corrected. 242 → 236. |

### The gate is the notable result

`manifests/azure-provider-types.json` (316 providers, 4661 type pairs, taken 2026-07-31) is
committed so CI runs offline. Its first run found **eight** real defects — five in collectors this
audit never identified: `Compute/CloudServices` (`microsoft.classiccompute` now lists zero types),
`Storage/DataLakeStoreGen1`, and three collectors carrying a renamed/retired type *alongside* a
live one, so each was half-collecting silently.

Two classes were the gate's own fault and are classified, not exempted: `devops/` synthetics, and
three-plus-segment child types checked against their parent because ARM under-reports nested types.

### Board

All shipped items Resolved/Closed. Epic AB#6731 is at **zero** conformance failures: tags brought
into vocabulary (`collect`/`report` are not in it — the check caught that), AB#6738/6739 re-parented
off a Feature onto Bugs, and six GitHub master records created and linked (GH#201–206).

Board-wide 28 failures remain, all pre-existing on other epics.

### Still open under this Epic

| Item | Why it was not done |
|---|---|
| AB#6779 (+6780–6783) — render role assignments, locks, policy assignments, budgets | The data is on `$Collect.governance`, the **assessment** path, but the audit specifies **inventory** collectors. Satisfying "no additional Azure API call" needs the AB#6755 pattern applied again: collect the two ARG tables + two REST calls in the raw pass and have `Import-Governance` consume them. Real design work, not a quick pass. |
| AB#6769 — re-source `ResourceDiagnosticSettings` via ARM REST | `microsoft.insights/diagnosticsettings` is not ARG-indexed. |
| AB#6770 — `Monitor/Outages` call ordering | `Get-ScoutOutageResource` runs before the API merge. |
| AB#6771 — `managedserviceresources` pass for LighthouseDelegations | Type is real; no pass reads that table. |
| `Hybrid/VirtualMachines` | Type IS real, so this is not the ArcSites failure and needs its own diagnosis. |
| AB#6737 — network diagram never rasterizes to JPEG | Untouched. |
| AB#6845 — 40 remaining child-loop collectors that can drop the parent | Only AKS was fixed previously. |
| AB#6843, AB#6786 — live run and Reader-only run | AB#6786 needs a Reader-only principal created in Azure; that is a write to the tenant and needs the owner's go-ahead. |

### Gotchas found this session

- `ConvertTo-Json -AsArray -InputObject $array` **double-wraps**; the ADO patch API rejects it with
  "At least one operation is required for Apply". Use the pipeline form.
- ADO **Tasks have no `Resolved` state** on this process — New / Active / Closed only.
- `Get-ScoutEntraQueryCatalog` must NOT use the `,@(...)` idiom: the catalog is never empty, and the
  unary comma makes every caller's `@()` count read 1.
- `Invoke-AZTIPermissionAudit.ps1` is dot-sourced **standalone** by tests. Any new sibling it calls
  must be loaded defensively or four tests break.
- Bash mangles `$n` inside a `pwsh -Command` string. Write a script file to the scratchpad instead.
