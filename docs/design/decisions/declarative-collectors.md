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
    AdditionalFilter   = '$_.name -ne ''master'''                # optional compound condition, ANDed in
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
    AdditionalRowLoops = @()          # rare: extra per-resource fan-out BEFORE the tag loop (see §2.3)
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

### 2.3 `AdditionalRowLoops` — the one further primitive the audit's shape needed

`Databases/SQLMIDB.ps1` and `Databases/SQLSERVER.ps1` each fan a resource out over its
private-endpoint connections (or a single `NONE` sentinel row when it has none) **before** the
per-tag loop — a self-contained, single-resource-type nested loop, not a cross-resource join.
Rather than special-case it, the schema generalises: `AdditionalRowLoops` is an ordered list of
`{ Variable, Source }` pairs run before the (always-last, implicit) tag loop, where `Source` is a
variable name the `Preamble` already computed (`$pvteps`, in both cases) — the collection-building
logic itself stays in the preamble, verbatim, like everything else; `AdditionalRowLoops` only
declares the extra loop structure the interpreter needs to run. The other 11 Databases collectors
declare it as `@()`. This
is the only genuinely new primitive the schema needed beyond what every collector already does —
everything else in the 128 PureShaping collectors reduces to filter + preamble + fields + export.

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
worksheet — for any estate that interleaves them. The interpreter matches per declared type, in
declared order, keeping the original relative order within each. For the 12 single-type Databases
collectors the two are identical, which is exactly why this went unnoticed until the fixture was
built to interleave them deliberately.

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

## 5. Alternatives rejected

| Alternative | Why not |
|---|---|
| JSON instead of `.psd1` | No restricted-language load-time guarantee; buys nothing over `.psd1` since field values are PowerShell expressions either way (§2.1). |
| A JSONPath-like value-mapping mini-language for `Fields` | Real fields need casts, arithmetic, string splitting and conditional nulls that such a language either can't express or converges back on PowerShell, worse (§2.2). |
| A generic `ScriptBlock`-per-collector escape hatch | That is `Invoke-ScoutCollector` again under a new name for the 46 collectors that need it — not a schema feature, a re-implementation of the thing already being kept (§2.4). |
| Convert every collector, including the 46 escape-hatch ones, by wrapping their whole body in one big `ScriptBlock` field | Would technically satisfy "every collector has a `.psd1`" but hides exactly the logic this epic exists to make visible and testable; a definition whose only field is "run this arbitrary code" documents nothing. |
| Cut the live pipeline over to the declarative interpreter in this same change | Two unverified things changing together (representation AND runtime path) is the flag-day pattern `deterministic-pipeline.md` explicitly rejected; the equivalence proof (AB#5659) is only trustworthy if the live path is held constant while it runs. |
