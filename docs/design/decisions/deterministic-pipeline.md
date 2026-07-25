---
description: Decision record — replace the inventory processing phase's background-job and runspace orchestration with a single deterministic in-process pipeline. Delivers AB#5651 under Feature AB#5649.
---

# Decision record — a deterministic inventory processing pipeline

> **Status:** Accepted 2026-07-25. Approved as part of the engine rebuild
> (Epic **AB#5638**), which the repo owner authorised in full.
>
> **Date:** 2026-07-25 · **Delivers:** AB#5651 · **Feature:** AB#5649 · **Epic:** AB#5638

## 1. Decision

**Run every inventory collector in-process, sequentially, in a fixed order. Use no background
jobs and no nested runspaces in the processing phase.**

Concretely: `Start-AZSCProcessJob`, `Start-AZSCAutProcessJob`, `Wait-AZSCJob` (for resources)
and `Build-AZSCCacheFiles` are replaced by four functions under `src/pipeline/`:

| Function | Responsibility |
|---|---|
| `Get-ScoutCollector` | Discover collectors — a pure function of the filesystem plus the category filter |
| `Invoke-ScoutCollector` | Run **one** collector, contain its failure, time it |
| `Invoke-ScoutProcessing` | Run them all in order, group by category, write the cache |
| `Write-ScoutCacheFile` | Write one category's rows — takes **data**, not job names |

## 2. Why — the old design's failures were structural, not incidental

The forked engine created one `Start-Job` per category, and each of those jobs created one
`[PowerShell]::Create()` runspace per collector. Every defect of the v2.5.x wave lived in that
coordination layer rather than in the collectors:

- **`Start-Job` is asynchronous.** A job created moments earlier sits in `NotStarted`. The wait
  condition tested `State -eq 'Running'`, so such a job was never waited on — then `Receive-Job`
  harvested it empty and `Remove-Job` destroyed it. A whole category vanished from the report
  with no error anywhere. This is AB#5629, and it is why `ReportCache/Compute.json` came back
  5,158 bytes on one run and 470 on the next against the same tenant.
- **The inner wait was a no-op.** `BeginInvoke()` returns a `PowerShellAsyncResult`, which has no
  `.Runspace` property. `While ($Job.Runspace.IsCompleted -contains $false)` therefore evaluated
  an empty collection, `-contains $false` was always false, and `EndInvoke` raced its own work.
  v2.5.2 fixed one of the two copies of this line; the other survived to v2.5.3.
- **Each job re-imported the module.** That re-applied module-scope StrictMode *inside* the job
  even when the calling orchestrator had opted out — which is why the v2.5.3 opt-out had to be
  applied at **17** entry points instead of 5, one per job body.
- **Ordering came from `Get-Job`.** Two runs over an unchanged estate could process categories in
  different orders and produce different output.
- **Errors surfaced detached.** An exception inside a runspace appeared at `EndInvoke` time,
  separated from the collector that raised it, so one bad collector silently emptied its whole
  category. Two collectors have been dead in every shipped release for exactly this reason (see
  §5).
- **The estate was serialised per category.** `ConvertTo-Json -Depth 40` over the full resource
  set, once for each of the 16 category jobs, then `ConvertFrom-Json` inside each.

Each of these was individually patchable, and several *were* patched. The pattern is that fixing
one exposed the next: v2.5.3 alone fixed six stacked crashes, each reachable only once the
previous cleared, at roughly seven minutes per live run to discover each one. The coordination
layer was the defect source, so removing it removes the class.

## 3. Why sequential is not a performance regression

The obvious objection is that this trades parallelism for determinism. It does not, because the
parallelism was largely illusory:

- Collectors are **pure CPU-bound filters over an in-memory array** — `$Resources | Where-Object
  { $_.TYPE -eq '…' }` and row shaping. They make no network calls; all Azure I/O happens in the
  extraction phase, before this one.
- `Start-Job` is **out-of-process**. Every argument crosses a serialisation boundary. The old
  design paid a full JSON round-trip of the entire estate per category to buy concurrency for
  work that is a few hundred milliseconds of array filtering.

A smoke run over the real 176 collectors completes in well under two minutes on a synthetic
estate, with the serialisation cost gone entirely. If a genuinely large estate ever makes this
phase the bottleneck, `ForEach-Object -Parallel` (in-process, PowerShell 7) is available without
reintroducing job harvesting — but it must not be adopted speculatively, because determinism is
the property this work exists to deliver.

## 4. Resilience is better, not worse

Determinism was not bought with fragility. `Invoke-ScoutCollector` contains each collector's
failure individually: a collector that throws is reported and skipped, every other collector
still runs, and the report is still produced. `Invoke-ScoutProcessing` returns the failure list
so the run log and the console can state plainly what did not run.

Under the old pipeline the same throw either emptied the category silently or took down the
batch. "The run completed" now means something it did not mean before.

## 5. Consequences

- **The `-Automation` processing branch is deleted.** It existed only to substitute
  `Start-ThreadJob` where `Start-Job` was unavailable. With no jobs, automation and interactive
  runs execute identical code and can no longer drift — as the two collector-discovery
  implementations already had (only one applied per-file category filtering).
- **`-Heavy` no longer affects this phase.** It only sized the parallel job batch. Peak memory is
  now one category at a time regardless. It still applies to extraction.
- **Ordering is part of the contract**, pinned by a test that hashes the cache files across two
  runs of the same input.
- **Three real defects surfaced immediately** once collectors ran in-process, all of them
  pre-existing and all previously masked by the job boundary:
  1. `Start-AZSCSecCenterJob` was receiving `$null` instead of the security rows, because
     `Invoke-AZSCSecurityCenterJob` was called with a parameter its own param block did not
     declare — and PowerShell routes an unknown named argument on a simple function into `$args`
     rather than rejecting it. **The Security Center sheet was empty in every release that had
     one.**
  2. Five collectors called `Write-AZSCLog -Color`/`-Level Verbose`, neither of which the
     function accepted, so each threw on its first log line and produced nothing.
  3. `Identity/IdentityProviders` and `Identity/SecurityDefaults` are written against a
     registration API that exists only as a **mock inside the test suite** and was never
     implemented. They have never produced a row. They are now detected at discovery and
     reported as skipped rather than executed, so a genuine failure is not buried under two
     guaranteed ones. Porting them is tracked under AB#5656.

## 6. What this deliberately does not do

- **The draw.io diagram subsystem still uses background jobs**, and `Wait-AZSCJob` survives to
  serve it. That subsystem starts nested jobs of its own and is a separate piece of work; folding
  it in here would have made this change untestable in one step.
- **StrictMode is still off for collectors.** They were written for a runspace where it never
  applied, and turning it on needs the recorded live-payload fixtures that AB#5667 covers. Doing
  both at once would be a flag day — exactly what the rebuild plan rules out.

## 7. Alternatives rejected

| Alternative | Why not |
|---|---|
| Keep the jobs, fix the waits again | Six stacked crashes in v2.5.3 alone, each found by a seven-minute live run. Patching the coordination layer had already been tried repeatedly; the next tenant-specific variant was always waiting. |
| `ForEach-Object -Parallel` | In-process, so it avoids the serialisation cost, but reintroduces non-deterministic ordering and interleaved failure reporting for work that does not need concurrency. Available later if profiling ever justifies it. |
| Thread jobs everywhere | Same harvesting and ordering problems as `Start-Job`, minus only the process boundary. |
| Rewrite the collectors at the same time | The 176 collectors are effectively data and are not the crash source. Changing the engine and its inputs together would leave no way to attribute a regression. That work is AB#5656. |
