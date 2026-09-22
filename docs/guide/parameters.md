---
description: Complete reference of all Invoke-AzureScout and Test-AZSCPermissions parameters.
---

# Parameters Reference

## Invoke-AzureScout Parameters

### Core

| Parameter | Description |
|-----------|-------------|
| `-TenantID` | One or more target Entra tenant IDs. One value preserves the single-tenant run; multiple values create an umbrella run with one isolated folder per tenant. Alias: `-TenantList` |
| `-AllAccessibleTenants` | Scan every tenant the signed-in user can directly access. This is explicit opt-in and does not use Azure Lighthouse. Aliases: `-AllTenants`, `-AllReachableTenants` |
| `-SubscriptionID` | Limit to one or more specific subscription IDs (comma-separated or array) |
| `-ResourceGroup` | Limit to one or more specific resource groups |
| `-ManagementGroup` | Inventory all subscriptions under a management group |
| `-Scope` | `ArmOnly` (default), `All`, or `EntraOnly` — controls which data domains are inventoried |
| `-OutputFormat` | Global output contract for every run mode: `React`, `Json`, `JsonEvidence`, or `All` (default, selects all three). Accepts an array. Legacy names still bind for compatibility but are on hold and are not emitted. See [Report tiers](../assessment/configuration.md#report-tiers). |
| `-Assessment` | Switches the run to **assessment mode** — see [Assessment-mode Parameters](#assessment-mode-parameters). Omit for an inventory run |
| `-NoWizard` | Skip the guided wizard that a bare, interactive `Invoke-AzureScout` opens, and run the default inventory instead. Alias: `-NonInteractive`. Never needed in CI — the wizard already suppresses itself in non-interactive hosts |
| `-NoProgress` | Suppress interactive progress rendering. Scout already chooses log-friendly output automatically in CI, redirected, and non-interactive hosts |
| `-Category` | Filter by resource category: `AI`, `Analytics`, `Compute`, `Containers`, `Databases`, `Hybrid`, `Identity`, `Integration`, `IoT`, `Management`, `Monitor`, `Networking`, `Security`, `Storage`, `Web` — see [Category Filtering](./category-filtering.md) |

### Authentication

| Parameter | Description |
|-----------|-------------|
| `-AppId` | Service principal application (client) ID |
| `-Secret` | Service principal client secret or certificate password |
| `-CertificatePath` | Path to `.pfx` certificate file for SPN authentication |
| `-DeviceLogin` | Use device code authentication flow (for headless/remote sessions) |

See [Authentication](./authentication.md) for detailed examples of each method.

### Content Options

| Parameter | Description |
|-----------|-------------|
| `-SecurityCenter` | Include Microsoft Defender for Cloud data (assessments, alerts, secure score) |
| `-IncludeTags` | Include resource tags in Excel worksheets |
| `-SkipPolicy` | Skip Azure Policy compliance collection |
| `-SkipAdvisory` | Skip Azure Advisor recommendation collection |
| `-SkipVMDetails` | Skip extra VM detail collection (extensions, boot diagnostics status) |
| `-SkipDiagram` | Skip network diagram generation |
| `-SkipPermissionCheck` | Skip the pre-flight permission validation |
| `-PermissionAudit` | Standalone permission audit — connects, checks ARM/RBAC (and Graph, with `-IncludeEntraPermissions`) then exits without collecting. Aliases: `-AuditPermissions`, `-CheckPermissions`. Prints an overall readiness verdict plus a per-collector impact table naming every collector a missing permission will leave empty and which permission fixes it — the verdict word alone used to be the only answer, which could read READY over worksheets that were about to come back empty |
| `-IncludeEntraPermissions` | With `-PermissionAudit`, also audit Microsoft Graph / Entra ID access. Alias: `-EntraAudit` |

### Output

| Parameter | Description |
|-----------|-------------|
| `-ReportName` | Custom report filename (default: `AzureScout_Report_<timestamp>`) |
| `-ReportDir` | Base output directory (default: `C:\AzureScout\` on Windows, `$HOME/AzureScout/` on Linux/Mac) |
| `-RunName` | Friendly name for this run's output folder instead of the generated timestamp, e.g. `-RunName 'Production-TenantA'`. Invalid path characters become `-` |
| `-Force` | Write a single-tenant run directly into `-ReportDir`, overwriting in place. It is rejected for multi-tenant runs because the umbrella folder is a required isolation boundary; use `-RunName` instead |
| `-Lite` | Legacy compatibility switch for the held Excel renderer; it does not change a live React/JSON output |

### Azure DevOps

| Parameter | Description |
|-----------|-------------|
| `-IncludeDevOps` | Also inventory Azure DevOps: projects, pipelines, service connections, repositories, agent pools. Adds five worksheets. Aliases: `-IncludeADO`, `-DevOps`. See [Azure DevOps](../automation-guide/azure-devops.md) |
| `-DevOpsOrganization` | Organization name(s) to inventory. Omit to discover them from the signed-in profile — service principals must name them explicitly. Alias: `-ADOOrganization` |
| `-DevOpsPat` | Personal access token, used instead of the current Azure sign-in. Needs read scope on Project and Team, Build, Release, Code, Service Connections, Agent Pools. Alias: `-ADOPat` |

### Unattended execution

| Parameter | Description |
|-----------|-------------|
| `-Automation` | Run non-interactively for an Azure Automation Account runbook: no interactive login, ThreadJob instead of background Job, progress to the job output stream. See [Azure Automation Account](../automation-guide/automation.md) |
| `-StorageAccount` | Storage account to upload the generated reports to. Authenticates to the data plane with the connected identity, so the identity needs **Storage Blob Data Contributor** |
| `-StorageContainer` | Blob container within `-StorageAccount` that reports are written to |

### Diagram

| Parameter | Description |
|-----------|-------------|
| `-DiagramFullEnvironment` | Include all network components in the draw.io topology diagram |

### Other

| Parameter | Description |
|-----------|-------------|
| `-AzureEnvironment` | Target Azure cloud: `AzureCloud` (default), `AzureUSGovernment`, `AzureChinaCloud`, `AzureGermanCloud` |
| `-Debug` | Verbose debug output during extraction and processing |

## Test-AZSCPermissions Parameters

| Parameter | Description |
|-----------|-------------|
| `-TenantID` | Target tenant ID to validate permissions against |
| `-Scope` | `All` (default), `ArmOnly`, or `EntraOnly` — controls which permission checks run |

Returns a structured object:

```powershell
$result = Test-AZSCPermissions -TenantID '00000000-...' -Scope All
$result.ArmAccess    # $true / $false
$result.GraphAccess  # $true / $false
$result.Details      # Array of check results with remediation guidance
```

See [Permissions](./permissions.md) for the full list of required roles and API permissions.

## Assessment-mode Parameters

Adding `-Assessment` switches `Invoke-AzureScout` from inventory to the **CAF/WAF
assessment**. All the sign-in and scoping parameters above still apply. Full
run-mode examples: [Assessment guide](../assessment/assessment.md#run-modes).

| Parameter | Description |
|-----------|-------------|
| `-Assessment` | One, several, or `All` assessment names from `manifests/assessments.psd1`. Supplying it is what selects assessment mode; omit it for an inventory run. Alias `-Assess`. Fifteen of the twenty-four entries score a single inventory category and are named `'Assess: <Category>'` — e.g. `'Assess: Compute'`, not `Compute` — because that name previously collided with the inventory `-Category` value of the same name. The colon and space mean the value must be quoted. Legacy unprefixed names (`Compute`, `Storage`, ...) still resolve, with a warning naming the new value. Those fifteen are a stopgap — they are category-scoped filters over the same CAF/WAF rule set `CAF: Azure Landing Zone` runs in full, and they are due to be retired once per-pillar assessments exist. See the [Assessment Registry](../design/assessment-registry.md). |
| `-InventoryAndAssessment` | Switch, alias `-Both`. Runs the inventory pass and the `-Assessment` pass from **one** collection instead of two — the assessment is handed the inventory's already-collected rows rather than re-querying Azure. Without it, `-Assessment` alone returns the assessment only; getting both previously meant invoking the command twice (and collecting from Azure twice) or answering the wizard's "run both?" prompt, which no script or CI pipeline could reach. See [Overview: running both](./overview.md#running-both). |
| `-Scope` | `ArmOnly` or `All` — both run the ARM/Resource Graph collect. `EntraOnly` throws, because the assessment Collect layer has no Entra/Graph path; use an inventory run with `-Scope EntraOnly` for Entra ID. |
| `-Category` | Filters which Resource Graph queries the Collect layer runs, narrowing the collect below the assessment's manifest default. |
| `-OutputFormat` | Same global contract as inventory and combined runs: `React`, `Json`, `JsonEvidence`, or `All` (selects all three). `React` renders a self-contained multi-page `report-react.html` — inventory blades, a full conformance register per assessment, diagrams, drift, and a remediation plan — with an Executive/Consultant/Data view-depth toggle, a light/dark theme, and Markdown/JSON/CSV/Print/standalone-HTML exports. `JsonEvidence` is a resources-only JSON export with no assessment metadata. Every legacy renderer name is on hold. See [Report tiers](../assessment/configuration.md#report-tiers) and [the section contract](../reference/react-report-section-contract.md). |
| `-ReportDir` | Base output directory; each run writes to a dated subfolder. |
| `-PermissionAudit` | Switch — runs `Test-ScoutPermission` for the requested `-Assessment` set and returns before any collection happens. |
| `-CollectOnly` | Switch — stop after Collect; returns the path to `collect.json`. |
| `-FromCollect` | Path to an existing `collect.json` — skips Collect/Ingest and assesses/reports from it directly. Runs fully offline, so it does **not** trigger a sign-in. |
| `-ManagementGroup` | Scopes the Resource Graph `Collect` layer (and the opt-in `AzGovViz` ingest, if selected instead of the native `Governance` default) for assessments that need it (`CAF: Azure Landing Zone`, `Management`, `Identity`, `Scout: Governance Baseline`, `Policy`). |

::: warning Former assessment command removed
The standalone assessment command was removed in **v3.0.0**. Use
`Invoke-AzureScout -Assessment` with `-ReportDir` and `-ManagementGroup` instead.
:::

## Invoke-ScoutPipeline Parameters

Unattended, one-command wrapper (`src/Invoke-ScoutPipeline.ps1`, exported)
that runs collect → assess → report headless into a single dated run folder.
See [Assessment guide — unattended, one-command run](../assessment/assessment.md#unattended-one-command-run-invoke-scoutpipeline).

| Parameter | Description |
|-----------|-------------|
| `-Assessment` | Same as `Invoke-AzureScout -Assessment` — one, several, or `All`. |
| `-OutputFormat` | Same global contract as `Invoke-AzureScout`: `React`, `Json`, `JsonEvidence`, or `All` (default, selects all three). Every legacy renderer is on hold. |
| `-OutputPath` | Base output directory; each run writes to a dated subfolder. |
| `-ManagementGroupId` | Same scoping behaviour as assessment mode’s `-ManagementGroup`. |
| `-Category` | Same as assessment mode’s `-Category`. |
| `-SkipPermissionAudit` | Switch — skips the read-only permission pre-flight that otherwise runs first. |

Returns the run-folder path. Throws and sets `$LASTEXITCODE = 1` only when
`pipeline-summary.json`'s `outcome` is `Failed`; an exporter failure degrades
the run to `PartialSuccess` instead of losing the output that did succeed.

## Test-ScoutPermission Parameters

Read-only permission pre-flight for the assessment platform — distinct from
`Test-AZSCPermissions` above. Normally invoked via
`Invoke-AzureScout -Assessment ... -PermissionAudit` rather than called directly.

| Parameter | Description |
|-----------|-------------|
| `-Assessment` | The assessment name(s) to check permissions for. |
| `-Manifest` | The imported `manifests/assessments.psd1` hashtable (passed automatically by assessment mode). |

Returns an array of `[pscustomobject]` results (`Check`, `Ok`, `Fix`) — the
ARM check's `Ok` is a live-validated `$true`/`$false`; the Graph checks'
`Ok` is always `$null` (informational, not live-verified). Full explanation:
[what `-PermissionAudit` actually verifies](../assessment/assessment-permissions.md#what-permissionaudit-actually-verifies).
