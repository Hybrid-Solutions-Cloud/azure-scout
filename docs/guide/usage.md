---
description: How to use AzureScout — scopes, output formats, category filtering, and examples.
---

# Usage Guide

## Basic Usage

```powershell
Import-Module ./AzureScout.psd1
Invoke-AzureScout
```

With no parameters, AZSC runs a full **ARM-only** inventory (`-Scope ArmOnly` is the default — Entra ID is skipped unless you pass `-Scope All` or `-Scope EntraOnly`) using your current Azure context. It produces the React report and machine-readable JSON outputs selected by the global output contract.

## Scope

The `-Scope` parameter controls which data domains are inventoried:

| Value | Behavior |
|-------|----------|
| `ArmOnly` (default) | Inventories ARM resources only — Entra ID is **not** scanned unless requested |
| `EntraOnly` | Skips all ARM extraction — Entra ID objects only |
| `All` | Inventories both ARM resources and Entra ID objects |

```powershell
# Default — ARM only, Entra ID is skipped
Invoke-AzureScout

# ARM + Entra ID
Invoke-AzureScout -Scope All

# Entra ID only — skip ARM resources
Invoke-AzureScout -Scope EntraOnly
```

::: tip
This is the `-Scope` default for **inventory mode** only. In **assessment mode**
(`-Assessment`) the same `-Scope` parameter defaults to `All` and has different
semantics — see [Assessment mode: `-Scope`](../assessment/assessment.md#-scope).
:::

## Output Format

The `-OutputFormat` parameter has the same live values for inventory, assessment, and combined
runs:

| Value | Produces |
|-------|----------|
| `All` (default) | `React`, `Json`, and `JsonEvidence` |
| `React` | Self-contained `report-react.html` with an Inventory & audit page; assessment sections appear when assessments run |
| `Json` | Machine-readable run results |
| `JsonEvidence` | Resources-only evidence export |

```powershell
# Machine-readable results only
Invoke-AzureScout -OutputFormat Json

# Self-contained inventory report
Invoke-AzureScout -OutputFormat React
```

Legacy values such as `Excel`, `Markdown`, `AsciiDoc`, `PowerBI`, `Html`, `Pptx`, `Pdf`, `Word`,
`EChartsDashboard`, and `GovernanceReport` are on hold. They are not live inventory alternatives.
Use the export menu inside the React report for Markdown, JSON, CSV, PDF/Print, and standalone HTML.

## Report Location

Every run writes to its own folder, so a rerun never overwrites the previous one:

- **Windows**: `C:\AzureScout\<timestamp>_<tenant>\`
- **Linux/macOS**: `$HOME/AzureScout/<timestamp>_<tenant>/`

Override the base path with `-ReportDir`, name the run folder with `-RunName`, or skip the run
folder entirely with `-Force`:

```powershell
# Different base path
Invoke-AzureScout -ReportDir 'D:\Reports'

# Friendly run folder name instead of the timestamp
Invoke-AzureScout -RunName 'Production-TenantA'

# Write straight into the base path, overwriting in place
Invoke-AzureScout -ReportDir 'D:\Reports' -Force
```

Full detail, including pruning old runs with `Clear-AZSCCacheFolder -OlderThan`, is in
[Output Files & Formats](./output.md#run-isolation).

Every run retains its complete evidence set: `raw-inventory.json` (everything the Resource Graph
pass collected, before any manifest filtered it down), `ReportCache/Discovery.json` (one
completeness record per resource plus generic ARM relationships), `collector-rowcounts.json`,
`collection-health.json`, and the complete `ReportCache`/`DiagramCache` trees. See
[Output Files & Formats — evidence artifacts](./output.md#evidence-artifacts).
Discovery/report payloads preserve sensitive field presence but replace credential values with
`[REDACTED]`.

## Content Toggles

Switch parameters to include/exclude specific content:

| Parameter | Effect |
|-----------|--------|
| `-SecurityCenter` | Include Microsoft Defender for Cloud findings |
| `-IncludeTags` | Include resource tags in Excel worksheets |
| `-IncludeDevOps` | Include Azure DevOps projects, pipelines, service connections, repositories, and agent pools |
| `-IncludeOkta` | Include the separate Okta control plane; also requires an HTTPS `-OktaOrganizationUrl` and SecureString `-OktaApiToken` |
| `-IncludeOnPremisesIdentity` | Include local Entra Connect and AD topology from a host with the required read-only modules |
| `-SkipAdvisory` | Skip Azure Advisor recommendations |
| `-SkipPolicy` | Skip Azure Policy compliance data |
| `-SkipPermissionCheck` | Skip the pre-flight permission validation |

Okta is explicitly opt-in. Supply its token without placing plaintext in shell history:

```powershell
$oktaToken = Read-Host 'Okta read-only API token' -AsSecureString
Invoke-AzureScout -Scope All -IncludeOkta `
  -OktaOrganizationUrl 'https://example.okta.com' -OktaApiToken $oktaToken
```

For Entra Connect/AD topology, run on a host that can read those local services and modules:

```powershell
Invoke-AzureScout -Scope All -IncludeOnPremisesIdentity
```

Unavailable local modules and denied Okta endpoints are recorded as coverage gaps; they are not
reported as proof that the corresponding configuration is absent.

## Azure DevOps

`-IncludeDevOps` adds five worksheets covering your Azure DevOps estate. It reuses the current
Azure sign-in, so no personal access token is needed in the common case:

```powershell
# Organizations discovered from the signed-in profile
Invoke-AzureScout -TenantID '00000000-...' -IncludeDevOps

# Name them explicitly (required for service principals)
Invoke-AzureScout -TenantID '00000000-...' -IncludeDevOps -DevOpsOrganization 'contoso','fabrikam'
```

See [Azure DevOps](../automation-guide/azure-devops.md) for the service-connection-to-subscription cross-reference
and the full permission model.

## Subscription & Management Group Filters

```powershell
# Specific subscriptions only
Invoke-AzureScout -SubscriptionID 'sub-001','sub-002'

# Management group scoped
Invoke-AzureScout -ManagementGroup 'mg-prod'
```

## Naming the Report

```powershell
Invoke-AzureScout -ReportName 'Q4-2025-Audit'
```

## JSON Output Structure

The JSON report uses a normalized, flat resource schema:

```json
{
  "metadata": {
    "tenantId": "...",
    "generatedAt": "2026-01-15T10:30:00Z",
    "scope": "All",
    "moduleVersion": "1.5.0"
  },
  "resources": [
    {
      "id": "/subscriptions/.../resourceGroups/.../providers/...",
      "name": "my-vm",
      "TYPE": "microsoft.compute/virtualmachines",
      "resourceGroup": "rg-prod",
      "subscriptionId": "...",
      "location": "eastus",
      "properties": { }
    }
  ]
}
```
