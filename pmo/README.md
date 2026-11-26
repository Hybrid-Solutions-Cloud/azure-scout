# PMO — Azure Scout

Project management artefacts for Azure Scout. Not product documentation — that lives in
`docs/`.

| Folder | Contents |
|---|---|
| `plans/` | Programme and epic plans. One file per programme, named for the epic it delivers. |
| `research/` | Research spikes and tool evaluations that feed a plan. |

## Conventions

- Markdown only, per the HCS documentation standard.
- Every plan names the GitHub epic issue it delivers. Work items are GitHub Issues, written to [`work-item-standard.md`](work-item-standard.md). Plans written before 2026-11-26 cite Azure DevOps work items (`AB#<id>`).
- A plan states its **non-goals** explicitly. Most failed work here was scope that nobody
  wrote down as out of scope.
- Research spikes record what was rejected and **why**, not only what was chosen — see
  `docs/design/decisions/` for the same discipline applied to architecture decisions.
