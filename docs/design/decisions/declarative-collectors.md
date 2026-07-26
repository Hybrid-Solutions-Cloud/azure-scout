---
description: Decision record — a declarative, schema-validated definition format for inventory collectors, with a documented escape hatch for the minority that need one. Delivers AB#5657 under Feature AB#5656, Epic AB#5638.
---

# Decision record — declarative inventory collector definitions

> **Status:** Accepted 2026-07-25. Part of the engine rebuild (Epic **AB#5638**), which the repo
> owner authorised in full.
>
> **Date:** 2026-07-25 · **Delivers:** AB#5657 · **Feature:** AB#5656 · **Epic:** AB#5638

## 1. Decision

**Represent a collector as a PowerShell data file (`.psd1`) describing WHAT to filter and WHAT
fields to produce, not HOW — with the field-level expression text lifted verbatim from the
existing collector, evaluated by one shared interpreter function instead of by 174 separate
copies of the same filter/loop/hashtable/export boilerplate.**

A definition has five sections:

```powershell
@{
    ResourceTypes      = @('microsoft.sql/servers/databases')   # $_.TYPE values to keep
    ResourceTypeMatching = 'Grouped'                             # 'Grouped' | 'SinglePass' (§2.5)
    AdditionalFilter   = '$_.name -ne ''master'''                # optional compound condition, ANDed in
    FilterPreamble     = ''                                      # statements the filter needs (§2.6)
    RowLoopVariable    = '1'                                     # the name the original file's row loop used ($1, $0, ...)
    Preamble           = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$DBServer = $1.id.split("/")[8]
$PoolId = if (![string]::IsNullOrEmpty($data.elasticPoolId)) { $data.elasticPoolId.split('/')[8] } else { $null }
... every per-resource setup statement, VERBATIM, in original order ...
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
'@
    AdditionalRowLoops = @()          # extra per-resource fan-out BEFORE the tag loop, each with its
                                      # own Preamble (see §2.3)
    TagLoop = @{ Variable = 'Tag'; Source = '$Tags'; Preamble = '' }   # $null = no tag expansion (§2.7)
    Fields = @(
        @{ Name = 'ID';               Expression = '$1.id' }
        @{ Name = 'Subscription';     Expression = '$sub1.Name' }
        @{ Name = 'Database Server';  Expression = '$DBServer' }
        # ... one entry per column, in the SAME source text as the original collector
    )
    Export = @{
        WorksheetName    = 'SQL DBs'
        TableNamePrefix  = 'SQLDBTable_'
        Columns          = @('Subscription', 'Resource Group', 'Name', '...')  # order = column order
        TagColumns       = @('Tag Name', 'Tag Value')                          # added only when $InTag
        TagColumnsBefore = 'Resource U'                                        # WHERE they are added (§2.5)
        NumberFormat     = '0'
        ConditionalText  = @(
            'New-ConditionalText -Range E2:E100 -ConditionalType ContainsText' # verbatim source, like Fields
        )
    }
}
```

`ConditionalText` entries are the **verbatim source text** of the original collector's
`New-ConditionalText` calls, evaluated the same way a `Fields` expression is — not a decomposed
`@{ Range = ...; ConditionalType = ... }` structure. Same reasoning as §2.2: the argument sets
vary (positional match text, `-Range`, `-ConditionalType`, `-BackgroundColor`), and re-modelling
them buys a second dialect of `New-ConditionalText` to keep in sync with ImportExcel's real one.

One shared function, `Invoke-ScoutDeclarativeCollector`, interprets this for both the Processing
and Reporting tasks. It contains **zero** collector-specific knowledge — not even of what a
"retirement lookup" or a "tag" is. Every bit of per-resource setup a collector needs (subscription
lookup, retirement folding, tag detection, whatever else it happens to compute) is the collector's
own business and lives in `Preamble`, verbatim, exactly as the original file wrote it. This was a
deliberate revision during conversion: an earlier draft of this schema tried to name specific
"standard primitives" (subscription lookup, retirement lookup, tag expansion) and have the
*engine* compute them, on the theory that they are near-universal. That drove the semantics of
"what a retirement is" into engine code that no `.psd1` file could see or override, and it still
didn't work: several fields reference a collector-local variable computed earlier in the row loop
that is neither a resource property nor one of those three primitives (`Databases/SQLDB.ps1`
computes `$DBServer`, `$PoolId`, and `$RestorePoint` this way). Capturing the **whole** per-resource
preamble as one block, instead of trying to decompose it into named primitives, needs no such
special-casing and is what actually produces byte-identical output — see §2.2.

## 2. Why this shape

### 2.1 Why `.psd1`, not JSON

- **House convention.** `manifests/assessments.psd1` already defines the assessment catalogue the
  same way — a data file loaded natively by PowerShell, not a second serialisation format the
  engine has to parse. Collectors are the same kind of thing: declarative configuration owned by
  this codebase, authored by people who already write PowerShell.
- **`Import-PowerShellDataFile` enforces "data-only" for free.** It parses the file in restricted
  language mode: no function calls, no variable references, no side effects at load time — only
  literal hashtables, arrays, strings, numbers, and booleans. A `.psd1` that tried to smuggle real
  control flow back in (the exact failure mode this epic exists to remove) **fails to load**,
  which is a stronger guarantee than "please don't do that" in a JSON schema comment.
- **JSON would need the same escape hatch anyway.** Field values still have to be a PowerShell
  expression (`$1.id.split("/")[8]`) or a whole script block (§2.4) either way; JSON buys nothing
  over a `.psd1` string here except a second file format for contributors to learn, and would
  still be represented as opaque strings that only make sense as PowerShell.

### 2.2 Why field expressions (and the preamble) are STRINGS in the collector's OWN local-variable names, not a value-mapping mini-language

The audit (AB#5658) considered inventing a small non-Turing-complete expression language (a
JSONPath-like `@('Property', 'ipConfiguration.id')` form) so that `Fields` could never contain
arbitrary code. It was rejected: real collector fields are not always a bare property path —
`(($data.maxSizeBytes / 1024) / 1024) / 1024`, `[string]::IsNullOrEmpty(...)`, `.split("/")[8]`,
and conditional nulls appear throughout even the 128 PureShaping collectors (see the audit). A
mini-language expressive enough to cover those cases converges on being PowerShell again, just
worse — and the places it fell short would need an escape hatch per FIELD as well as per
collector, doubling the surface area for no real safety gain (the interpreter already runs in the
same trust boundary a hand-written collector always did).

Instead, `Preamble` runs as a plain script (not evaluated field-by-field) and every `Field`
`Expression` is evaluated with `[scriptblock]::Create(...).InvokeWithContext(...)`, in the SAME
scope the preamble just populated, using whatever local variable names the original collector
happened to use — `$1` for the current resource (`RowLoopVariable` records what the original file
actually called it), `$data`, `$sub1`, `$RetiringFeature`, `$DBServer`, or anything else a
particular collector's preamble sets up. `$Tag` (the tag being expanded) and `$ResUCount` (`1` on
a resource's first emitted row, `0` after) are the two variables the interpreter itself binds,
because they come from the row-expansion loop the interpreter runs, not from the collector's own
preamble.

This is the reason the conversion tool (`scripts/ConvertTo-ScoutCollectorDefinition.ps1`, AB#5660)
can lift a field's expression **verbatim** from the AST of the original file — the byte-for-byte
same expression runs against a byte-for-byte equivalent scope, which is what makes the equivalence
proof in AB#5659 meaningful rather than coincidental.

### 2.3 `AdditionalRowLoops` — the row-expansion nest, one level at a time

`Databases/SQLMIDB.ps1` and `Databases/SQLSERVER.ps1` each fan a resource out over its
private-endpoint connections (or a single `NONE` sentinel row when it has none) **before** the
per-tag loop — a self-contained, single-resource-type nested loop, not a cross-resource join.
Rather than special-case it, the schema generalises: `AdditionalRowLoops` is an ordered list of
`{ Variable, Source }` pairs run before the (always-last, implicit) tag loop, where `Source` is a
variable name the `Preamble` already computed (`$pvteps`, in both cases) — the collection-building
logic itself stays in the preamble, verbatim, like everything else; `AdditionalRowLoops` only
declares the extra loop structure the interpreter needs to run. The other 11 Databases collectors
declare it as `@()`.

**Each loop level carries its OWN `Preamble`** — added during the category-by-category conversion
(AB#5659), and not an optional nicety. A collector's row loop is a chain, and *every* level of it has
setup statements:

```powershell
foreach ($1 in $VirtualNetwork) {          # row loop
    $data = $1.PROPERTIES ...             #   -> Preamble
    foreach ($2 in $data.subnets) {       #   -> AdditionalRowLoops[0]
        $ConsumedIPs = ...; $Prefix = ... #        -> AdditionalRowLoops[0].Preamble
        foreach ($Tag in $Tags) { $obj = @{ ... } }
    }
}
```

Capturing only the row level's preamble — the first implementation — silently produced `$null` for
every local a fan-out loop computed: `Security/Vault.ps1` lost all three of its permission columns,
`Networking/NATGateway.ps1` lost its public-IP columns, and `Networking/VirtualNetwork.ps1` lost the
whole subnet prefix/available-IP calculation. The row-level preamble cannot cover them, because they
read the loop variable, which does not exist yet when the row preamble runs.

The loop chain plus the tag loop (§2.7) is the only genuinely new structural primitive the schema
needed — everything else in the PureShaping collectors reduces to filter + per-level preamble +
fields + export.

### 2.4 The escape hatch: stay a hand-written `.ps1`, unconverted

The 46 collectors the audit found doing real work (cross-resource joins, live `Get-Az*`/
`Invoke-AzRestMethod` calls — see `docs/design/collector-audit.md` §2) are **not** given a new
"escape hatch" field type inside the schema. They simply **do not get a `.psd1` definition**.
`src/pipeline/Get-ScoutCollector.ps1` — the single discovery implementation established by
AB#5649 — is EXTENDED to report, per collector, whether a definition exists
(`HasDeclarativeDefinition` / `DefinitionPath`: purely additive properties; `Contract` is
unchanged). Extended rather than paired with a second discovery mechanism that walked
`manifests/collectors` independently: two walkers over the same estate is how the v1 engine's
two copies of collector discovery drifted apart in the first place. A collector with no
definition keeps running exactly as it does today, as a Standard-contract `.ps1` executed by the
existing `Invoke-ScoutCollector`.

This was chosen over inventing a generic "arbitrary script block per collector" escape hatch
because that would just be `Invoke-ScoutCollector` again under a different name — the escape hatch
this codebase needs already exists; declaring it a *feature* of the new schema, rather than
building a second one, is the honest description of what "escape hatch" means here. A collector
graduates from escape hatch to declarative the same way every PureShaping one did: by having its
join/live-call logic factored so a human can confirm the schema's primitives now cover it, which
is future work, not a gap in this decision.

### 2.5 `Export.TagColumnsBefore` and `ResourceTypes` ordering — two things the equivalence proof forced into the schema

Both were found by `tests/DeclarativeCollectorEquivalence.Tests.ps1` (§4), not by review, and
both are recorded here because each is a case where the *obvious* schema was quietly wrong.

**`TagColumnsBefore`.** The first draft of `Export` had `TagColumns` **appended** to `Columns`
when `$InTag` was set. That is not what the collectors do. They build the column list by calling
`$Exc.Add(...)` in source order, with the two Tag columns added inside an `if ($InTag) { }` block
that is **not** at the end — all 13 Databases collectors call `$Exc.Add('Resource U')` *after* it.
Appending therefore produced `..., Resource U, Tag Name, Tag Value` where every shipped release
produced `..., Tag Name, Tag Value, Resource U`: a silent reordering of the last three columns of
every tagged worksheet, invisible to any test that only checked the column *set*.
`TagColumnsBefore` names the column the tag block is inserted before (`$null` = genuinely append),
and `Get-ScoutCollectorDefinition` **rejects** a value that is not in `Columns` rather than falling
back to appending — the silent fallback is the defect.

**`ResourceTypes` order is a grouping, not a filter.** A multi-type collector builds its set by
appending one filtered pass per type:

```powershell
$RedisCache  = $Resources | Where-Object { $_.TYPE -eq 'microsoft.cache/redis' }
$RedisCache += $Resources | Where-Object { $_.TYPE -eq 'microsoft.cache/redisenterprise' }
```

so every `redis` row precedes every `redisenterprise` row no matter how the two interleave in
`$Resources`. Interpreting `ResourceTypes` as a single `-contains` membership test over
`$Resources` instead preserves *arrival* order, reordering the rows — and therefore the
worksheet — for any estate that interleaves them. For the 12 single-type Databases
collectors the two are identical, which is exactly why this went unnoticed until the fixture was
built to interleave them deliberately.

**…and BOTH shapes exist in the estate, so the mode is declared, not inferred.** The wider conversion
(AB#5659) found the opposite pattern in `Hybrid/ArcSites.ps1`:

```powershell
$arcSites = $Resources | Where-Object {
    $_.TYPE -in @('microsoft.azurestackhci/sites', 'microsoft.edgeconfig/sites', 'microsoft.hybridcompute/sites')
}
```

One pass, so rows come out in `$Resources` order with the three types interleaved. Applying the
grouped interpretation to it reordered its worksheet — the same bug as the original, in the other
direction. `ResourceTypeMatching` therefore records which shape the collector has (`'Grouped'` for
the `+=` form, `'SinglePass'` for this one; the converter derives it from whether the resource set was
built by one filtered assignment or several), and `Get-ScoutCollectorDefinition` **rejects** any other
value rather than falling back to a default. For a single-type collector the two modes are identical.

### 2.6 `FilterPreamble` — a compound filter's own local variables

`AdditionalFilter` is lifted verbatim, and verbatim text can reference a local the Processing branch
set up before the filter ran. `AI/AppliedAIServices.ps1`:

```powershell
$appliedAIKinds = @('FormRecognizer', 'ComputerVision', ...)
$appliedAI = $Resources | Where-Object {
    $_.TYPE -eq 'microsoft.cognitiveservices/accounts' -and $appliedAIKinds -contains $_.KIND
}
```

Without those statements the filter's `$appliedAIKinds` is `$null`, `-contains` is false for every
resource, and the collector matches **nothing** — a definition that loads, validates, runs, and
silently produces an empty worksheet. `FilterPreamble` carries the statements verbatim and the
interpreter prepends them inside the `Where-Object` block (assignments emit nothing, so the block's
only output is still the condition). A `FilterPreamble` with no `AdditionalFilter` is a load-time
error: it can only mean the filter was lost.

### 2.7 `TagLoop` — the tag expansion is declared, because it is neither universal nor consistently named

The audit called per-tag row expansion "effectively universal". Converting the other 14 categories
showed it is not:

- **25 collectors have no tag loop at all** — all 15 convertible `Identity` ones, most of `Management`,
  and `Monitor/Outages`. They emit exactly one row per resource and their `$obj` has no Tag columns.
- **`Networking/RouteTables.ps1` calls its tag variable `$TagKey`**, not `$Tag`.

An interpreter that always wraps the row in `foreach ($Tag in $Tags)` gets the second one silently
wrong (every Tag column resolves to `$null`, because `$TagKey` is what the fields read) and cannot
express the first at all. `TagLoop` is therefore an explicit `{ Variable; Source; Preamble }` — or
`$null` for "no tag expansion". Omitting the key entirely keeps the historic
`foreach ($Tag in $Tags)` default, so the pilot definitions' behaviour is unchanged by the key
existing.

The same discovery applies to the export side: **10 Monitor collectors process `Tag Name` and
`Tag Value` but never export them** — their Reporting branch has no `if ($InTag)` block whatsoever. The
converter's original "default to the two standard names when none are found" therefore added two
columns to those sheets under `-IncludeTags` that no shipped release has ever contained. `TagColumns`
is now emitted as `@()` when the original adds none.

### 2.8 A field expression is not always an expression

The first interpreter wrapped each field as `'Name' = (<Expression>)`. That is a **parse error** for
any collector whose field is a multi-line `if (...) { ... } else { ... }` — `Containers/ARO.ps1` and
`Containers/ContainerRegistries.ps1` among others — because `( ... )` accepts a pipeline, not a
statement: *"The term 'if' is not recognized as a name of a cmdlet"*, and every field of that
collector was unreachable. `$( ... )` is not a safe substitute either: a subexpression collects the
output *stream*, so `$(@(1))` is the scalar `1` and `$(@())` is `$null` where the original produced a
one-element and an empty array. The interpreter now emits the expression **unwrapped**, exactly as the
original `$obj = @{ ... }` hashtable literal wrote it — which a hashtable value accepts, statement or
not, and which is also the faithful choice.

## 3. Consequences

- **`manifests/collectors/<Category>/<Name>.psd1`** is the new definition location — one file per
  converted collector, mirroring the `InventoryModules/<Category>/<Name>.ps1` layout so the two
  can be found side by side during the (currently manual, per-category) conversion.
- **`Invoke-ScoutDeclarativeCollector` (`src/pipeline/`) is the one interpreter** for every
  converted collector's Processing and Reporting tasks. Converting a collector deletes ~120 lines
  of copy-pasted retirement/tag/export boilerplate and leaves behind a data file whose only
  collector-specific content is the field list and the export column order.
- **A collector with no `.psd1` is not a defect.** `HasDeclarativeDefinition = $false` is the
  expected, common state for every escape-hatch collector until a later phase of this epic
  addresses it.
- **The live pipeline does not change yet.** `Invoke-ScoutProcessing` still calls
  `Invoke-ScoutCollector` against the original `.ps1` for every collector, converted or not — this
  decision and its proof (AB#5659) are deliberately staged before the cutover that would make
  `Invoke-ScoutDeclarativeCollector` the thing that actually runs in a release, matching this
  epic's "no big bang" phasing (`docs/design/decisions/deterministic-pipeline.md` §7).
- **`Identity/IdentityProviders.ps1` and `Identity/SecurityDefaults.ps1` are recommended for
  deletion**, not conversion — see the audit §4. There is no existing behaviour for a definition
  to reproduce.
- **Faithful conversion preserves pre-existing defects.** Two of the 13 converted collectors
  export a column whose name does not match any processed field, so it has been blank in every
  shipped release: `Databases/RedisCache.ps1` exports `Resource Group` for a field it processes as
  `ResourceGroup`, and `Databases/SQLMI.ps1` exports `ActiveDirectoryOnlyAuthentication` for a
  field it processes as `AzureADOnlyAuthentication`. `Get-ScoutCollectorDefinition` reports each as
  a `SchemaWarnings` entry and **not** a validation error: `Select-Object $Exc` in the original
  engine does not require the property to exist either. Silently fixing them here would make the
  declarative path produce a *different* report from the imperative one, which is precisely what
  this change must not do. They are worth fixing — as their own change, with their own work item.

  The wider conversion (AB#5659) found three more of exactly the same class, bringing the total to
  five columns that have been blank in every shipped release. All five are reported as
  `SchemaWarnings` and reproduced faithfully:

  | Collector | Column exported | Field actually processed |
  |---|---|---|
  | `Databases/RedisCache` | `Resource Group` | `ResourceGroup` |
  | `Databases/SQLMI` | `ActiveDirectoryOnlyAuthentication` | `AzureADOnlyAuthentication` |
  | `Analytics/EvtHub` | `Geo-Rep` | *(no such field)* |
  | `Integration/ServiceBUS` | `Geo-Rep` | *(no such field)* |
  | `Networking/vNETPeering` | `Peering Allow Virtual NetworkAccess` | `Peering Allow Virtual Network Access` |

  Finding these is a side effect worth noting: the schema validator sees a mismatch that
  `Select-Object $Exc` never could, so simply *representing* a collector declaratively surfaces
  export bugs the imperative form hid.

## 4. The equivalence proof

`tests/DeclarativeCollectorEquivalence.Tests.ps1` (AB#5659) is the test this decision stands or
falls on. For each of the 13 Databases collectors it feeds ONE shared fixture,
`tests/fixtures/databases-collector-input.json`, to both implementations and compares:

- **Processing** — every emitted row, in order, key by key and value by value, via a canonical
  rendering that distinguishes `$null` from `''` from `@()` (a bare `-eq` would compare an
  array element-wise and return a truthy array).
- **Reporting** — both paths write a real `.xlsx` through `Export-Excel`; both workbooks are read
  back with `Import-Excel` and compared cell by cell, under `-InTag:$false` **and** `-InTag:$true`.

The fixture is a superset of the mock estate `tests/Databases.Module.Tests.ps1` already uses, plus
the cases equivalence actually turns on: an untagged resource (the `$Tags = '0'` fallback), a
two-tag resource (row expansion and the `$ResUCount` 1→0 transition), a `master` database
(`AdditionalFilter`), resources with no `privateEndpointConnections` (the `NONE` sentinel in the
`AdditionalRowLoops` collectors), a resource whose subscription is absent from `$Sub`, a resource
carrying two retirements (the many-branch of the retirement fold), and an interleaved second
`microsoft.cache/redis` placed after the `redisenterprise` entry (§2.5).

Both §2.5 defects were found this way, and reverting either fix reproduces the failures — so the
suite is not passing vacuously.

**What it does not prove.** The fixture is synthetic. It is derived from the shapes the existing
test estate already asserts, not from a recorded live tenant payload, so a real-world property no
mock carries (an unexpected null, a differently-cased type string, a tag collection of an
unforeseen shape) is out of its reach. Recorded live fixtures are AB#5667's job; when they land,
this test should be re-run against them before the live pipeline is cut over to the declarative
interpreter.

### 4.1 Scaling the proof to the other 14 categories (AB#5659)

The pilot fixture is hand-authored. Hand-authoring one for **111 further collectors** — ~19 fields each,
often three levels deep inside `properties` — is not realistic, and the per-category mock estates in
`tests/*.Module.Tests.ps1` populate only the handful of properties those tests assert on, which makes
them worse than useless here: a collector whose properties are absent emits a row of nulls on *both*
paths and compares equal. **A vacuous pass is the failure mode this proof has to avoid.**

So the estate for the remaining categories is **generated from the definitions themselves**
(`scripts/New-ScoutCollectorFixture.ps1`, output `tests/fixtures/collector-equivalence/<Category>.json`).
It walks the AST of the same per-resource script the interpreter builds — preamble, per-loop preambles,
filter and every field expression — resolves every property path reached from the collector's own row
variable (through assignment chains, `foreach` variables, array indexing, member enumeration, and `$_`
inside a piped script block), and synthesises a resource with exactly those paths populated. That
inverts the usual risk: a hand-written fixture tends to under-populate, whereas one derived from the
expressions cannot, because every path the collector reads is present by construction.

Leaf *values* are inferred from how each path is used (`.split('/')` → a 16-segment slash-delimited
string, `[int]`/arithmetic → a number, `[datetime]`/`get-date` → an ISO timestamp, `@(...)`/`.count`/
`foreach` → an array). That is not cosmetic tidiness: **if a field expression throws, the two paths do
not fail the same way.** The interpreter's row is a single `@{ ... }` statement, so a throw emits
nothing; the original assigns `$obj` and then writes it, so a throw leaves the *previous* iteration's
`$obj` in scope and the collector emits a duplicate row. A fixture that provokes a throw reports a real
difference that is a property of the legacy code rather than of the conversion — which is also why each
collector is fed only its **own** generated resources rather than one estate shared across a category.

Six variants per declared resource type exercise the cases equivalence turns on: one tag; two tags
(row expansion and the `$ResUCount` 1→0 transition); no tags (the `$Tags = '0'` fallback); a
subscription absent from `$Sub`; one retirement; two retirements (the many-branch of the retirement
fold every collector copy-pastes). Types are emitted round-robin, not grouped, so the fixture can
*disprove* rather than accommodate a wrong `ResourceTypeMatching` (§2.5).

**Result:** 124 of the 176 collectors have a definition and every one of them is pinned, both
`Processing` (row by row, key by key) and `Reporting` (cell by cell, under both `-IncludeTags` states).
Four PureShaping collectors are deliberately left imperative, listed with their reasons in
`tests/DeclarativeCollectorEquivalence.Tests.ps1` (held as test data, so shortening the converted set
is a visible edit rather than a silent omission):

| Collector | Why it stays imperative |
|---|---|
| `Management/AllSubscriptions` | Its row loop iterates `$Sub`, not a filtered `$Resources` set — there is no resource-type filter for the interpreter to drive. |
| `Management/AdvisorScore` | Its `$obj` is built inside a nested `if`/`else`, so there is no single row-emitting level to lift. |
| `Networking/PublicIP` | **Two** `$obj` literals in opposite branches of an `if`/`else`: the row *shape* is conditional, and a `Fields` list is one shape. |
| `Monitor/Outages` | **Audit misclassification.** It builds columns via `New-Object -Com HTMLFile` and reads `$Html.body.innerText` — not pure shaping at all. The audit only searched for `Get-Az*`/`Invoke-*`, so a COM dependency was invisible to it. |

The same limits as §4 apply, plus one specific to generation: the values are semantically meaningless
(`res-value` where a real estate has `Standard_LRS`), so this proves the two implementations agree on
the paths the collector reads — not that either is correct about a real tenant.

## 5. Alternatives rejected

| Alternative | Why not |
|---|---|
| JSON instead of `.psd1` | No restricted-language load-time guarantee; buys nothing over `.psd1` since field values are PowerShell expressions either way (§2.1). |
| A JSONPath-like value-mapping mini-language for `Fields` | Real fields need casts, arithmetic, string splitting and conditional nulls that such a language either can't express or converges back on PowerShell, worse (§2.2). |
| A generic `ScriptBlock`-per-collector escape hatch | That is `Invoke-ScoutCollector` again under a new name for the 46 collectors that need it — not a schema feature, a re-implementation of the thing already being kept (§2.4). |
| Convert every collector, including the 46 escape-hatch ones, by wrapping their whole body in one big `ScriptBlock` field | Would technically satisfy "every collector has a `.psd1`" but hides exactly the logic this epic exists to make visible and testable; a definition whose only field is "run this arbitrary code" documents nothing. |
| Cut the live pipeline over to the declarative interpreter in this same change | Two unverified things changing together (representation AND runtime path) is the flag-day pattern `deterministic-pipeline.md` explicitly rejected; the equivalence proof (AB#5659) is only trustworthy if the live path is held constant while it runs. |
