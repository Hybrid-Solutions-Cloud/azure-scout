# Repo intent — azure-scout

**See everything. Own your cloud. — Azure and Entra ID discovery, inventory, and CAF/WAF assessment.**

## What this repo is

AzureScout (AZSC) is a PowerShell module that inventories an Azure tenant and
produces a self-contained React report plus machine-readable JSON evidence,
covering Azure resources and Entra ID, assessed against Cloud Adoption Framework
and Well-Architected Framework guidance.

## Shape

- `src/`, `AzureScout.psd1`/`.psm1` — the PowerShell module
- `manifests/`, `config/` — assessment configuration
- `action.yml` — usable as a GitHub Action
- `tests/`, `run_linter.ps1`, `PSScriptAnalyzerSettings.psd1` — full test/lint
  harness
- `pmo/`, `ado_items.json` — project management, tied to ADO work items

## How it relates to other repos

- **`stagecoach`** — a separate, complementary tool: scout finds and assesses the
  estate, stagecoach takes you to a machine in it (per `stagecoach`'s own
  repo-intent.md)
- A duplicate/legacy copy of this same repo also exists under the `thisismydemo`
  org — treat **this** `Hybrid-Solutions-Cloud/azure-scout` as canonical; verify
  before assuming the `thisismydemo` copy is current

## Status

Active, published open-source PowerShell module.
