# Azure Resource Graph round-trips per run

Tracks ADO AB#5648 (Epic AB#5638).

This is the map of **every** Azure Resource Graph and ARM REST call the product issues, where it
is issued from, and what changed when `src/collect` became the single source of the raw data.
It was derived by reading each call site, not from an earlier estimate.

A "round-trip" here means one `Search-AzGraph` invocation for one query and one subscription
batch — not one page. Paging multiplies each entry by however many 1000-row pages the estate
needs.

## Where Resource Graph is reached from

Every `Search-AzGraph` call site in the shipped module:

| Call site | Purpose | Queries issued |
|---|---|---|
| `src/collect/Get-ScoutRawInventory.ps1` | the single raw pass | 3 tables always; up to 6 more behind `-Include*` switches |
| `src/collect/Invoke-Collect.ps1` | typed assessment pack | 1 (`sqlDefenderPricing`) by default; 35 under `-Source TypedQueries` |
| `Modules/Private/Extraction/Get-AZTIManagementGroups.ps1` | expand a management group into its subscriptions | 1, only when `-ManagementGroup` is supplied |
| `Modules/Public/InventoryModules/Management/AllSubscriptions.ps1` | one inventory collector's own lookup | 1, during processing |
| `src/ingest/Import-Governance.ps1` | governance ingestor | per its own query pack, only for assessments whose manifest lists `Ingest = 'Governance'` |
| `src/ingest/Invoke-ArgQueryPack.ps1` | opt-in ARG query pack ingestor | per its own pack, only when the manifest lists it |
| `scripts/Export-ScoutFixture.ps1` | developer fixture capture | not part of a product run |

`Modules/Private/Extraction/Start-AZTIGraphExtraction.ps1` and
`Modules/Private/Extraction/Invoke-AZTIInventoryLoop.ps1` **used to** be call sites. The first is
now a parameter-translation shim with no query text and no ARG call; the second is deleted.

## Before and after

Measured with a counting stub in place of `Search-AzGraph`, and pinned by
`tests/Collect.SinglePassInversion.Tests.ps1`.

| Entry point | v2.7.0 | after AB#5648 |
|---|---|---|
| Assessment-only collect (`Invoke-ScoutAssessment`, default) | **35** | **4** |
| Assessment collect, `-Source TypedQueries` (opt-in) | 35 | 35 |
| Assessment collect, `-FromInventory` (combined run) | 1 | 1 |
| Inventory extraction (`Invoke-AzureScout`, default switches) | 8 | 8 |
| Combined inventory + assessment, end to end | 9 | 9 |

Excluded from those numbers because they are conditional on flags or manifest entries, and
unchanged by this work: the management-group expansion (1, only with `-ManagementGroup`), the
`AllSubscriptions` collector (1, during processing), and the two ingestors.

## Why the inventory number is 8 and not 1

The inventory extraction reads eight **distinct** Resource Graph tables. They are not different
filters over one table, so they cannot be merged into one query without dropping datasets:

`resourcecontainers`, `resources`, `networkresources`, `SupportResources`,
`recoveryservicesresources`, `desktopvirtualizationresources`, `advisorresources`, plus the
file-backed retirement query. `securityresources` makes a ninth when `-SecurityCenter` is
supplied.

What changed is not the count but the ownership: all eight are now issued by one function, with
one paging implementation (`SkipToken`), one batching rule (1000 subscriptions per call), one
throttle-retry policy and one per-batch error-isolation policy. Before, there were two
independent implementations of that machinery and 43 round-trips across a combined run's two
passes over the same resource types.

## The two documented exceptions to "one pass"

Both are real, both are asserted in the test file rather than hidden:

1. **`sqlDefenderPricing`** reads the `SecurityResources` table (`microsoft.security/pricings`).
   No inventory pass collects it: the inventory `securityresources` query filters to
   `microsoft.security/assessments` with an `Unhealthy` status, which cannot contain a pricings
   row. It stays a live typed query, so a default assessment collect is 3 + 1, not 3.
2. **`Retirements`** is a file-backed KQL query
   (`src/report/renderers/inventory/style/Retirement.kql`) with its own joins over service-health
   data. It is not derivable from the raw row set either. It moved into
   `Get-ScoutRawInventory -IncludeRetirements` so it is issued from the same place as everything
   else, but it is still its own round-trip.

## The trade-off, stated plainly

The round-trip **count** dropped from 35 to 4 for an assessment collect. The raw pass transfers
the full `properties` bag for every resource in scope, where the typed queries transferred narrow
projections — so on a large estate the number of 1000-row **pages** can go up even as the number
of queries goes down. `-Categories` no longer reduces what is *fetched* (it still filters what is
shaped and returned).

This is the same trade the combined-run `-FromInventory` path has made since v2.5.0.
`-Source TypedQueries` remains available for a narrow single-category collect where projection
size matters more than call count.

**Unverified:** the page-count effect has not been measured against a large live estate. The
numbers in this document are query counts from a mocked run, not page counts or wall-clock time.

## Non-ARG data sources

Not Resource Graph, listed for completeness because they are part of the same "how many times do
we call Azure" question and are the remaining duplication:

| Source | v1 implementation (live) | `src/collect` port (v2.7.0, not yet wired) |
|---|---|---|
| ARM REST (resource health, managed identities, advisor score, reservation recommendations, policy) | `Modules/Private/Extraction/Get-AZTIAPIResources.ps1` | `src/collect/Get-ScoutApiResources.ps1` |
| VM quotas | `Modules/Private/Extraction/ResourceDetails/Get-AZTIVMQuotas.ps1` | `src/collect/Get-ScoutVmQuotas.ps1` |
| VM SKU details | `Modules/Private/Extraction/ResourceDetails/Get-AZTIVMSkuDetails.ps1` | `src/collect/Get-ScoutVmSkuDetails.ps1` |
| Cost Management | `Modules/Private/Extraction/Get-AZTICostInventory.ps1` | `src/collect/Get-ScoutCostInventory.ps1` |

AB#5648 inverted the Resource Graph half. The four non-ARG sources above still run the v1
implementation on a live run; their `src/collect` ports remain uncalled. Retiring those four is
not covered by the round-trip numbers in this document and is not done.
