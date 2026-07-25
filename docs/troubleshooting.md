---
description: Common errors and solutions when running AzureScout.
---

# Troubleshooting

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Insufficient privileges to complete the operation` | Missing Microsoft Graph permission | Grant the required permission and perform admin consent. See [Permissions](permissions.md). |
| `Authorization_RequestDenied` | Delegated permission not consented | Sign in with a Global Admin and consent to the required permissions. |
| `Resource provider not registered` / `[FAIL] Provider: ... NotRegistered` | Provider not enabled in subscription | **This is expected.** Not all providers need to be registered in every subscription — Azure only registers providers for services you actually use. The corresponding inventory modules are simply skipped. Only register a provider if you actually use that service and want it included in the report: `Register-AzResourceProvider -ProviderNamespace <namespace>`. See [Prerequisites](prerequisites.md) for details. |
| `No match was found for the specified search criteria and module name` | Module not available in PSGallery or network restrictions | Install the module manually. See [Prerequisites](prerequisites.md) for install commands. |
| `Get-AzSubscription returned 0 subscriptions` | Identity has no Reader role on any subscription | Assign `Reader` at the subscription or management group level. |
| `Connect-AzAccount: interactive login failed` | Running in a non-interactive session (CI/CD, SSH) | Use `-DeviceLogin`, SPN with secret, or SPN with certificate. See [Authentication](authentication.md). |
| `Token acquisition failed for MSGraph` | Az.Accounts version too old or tenant configuration issue | Update `Az.Accounts` to latest: `Update-Module Az.Accounts -Force` |
| `Export-Excel: file is locked` | Excel report file is open in another application | Close the file and re-run. |
| Management Groups worksheet is empty, no error | Identity has no tenant-root role | Assign `Management Group Reader` at the tenant root. Since v2.3.0 the login summary reports the visible count and prints this tip, so you find out at sign-in rather than after the run. |
| Reports are not where a previous version left them | Run isolation (v2.3.0) | Each run now writes to its own folder under the base path. Use `-Force` for the old overwrite-in-place behaviour, or `-RunName` to control the folder name. See [Output Files & Formats](output.md#run-isolation). |
| Output folders accumulating on disk | One folder per run, by design | `Clear-AZSCCacheFolder -OlderThan 30` prunes runs not written to in the last 30 days. |
| `No Azure DevOps organizations could be discovered` | Service principals have no profile to enumerate | Pass `-DevOpsOrganization 'contoso','fabrikam'`. See [Azure DevOps](azure-devops.md). |
| `Could not acquire an Azure DevOps token` | Not signed in, or the sign-in cannot reach Azure DevOps | Run `Connect-AzAccount`, or pass `-DevOpsPat`. |
| ADO Service Connections worksheet missing | Identity holds project read but not service connection read | Expected and handled — that slice is skipped and the rest still collects. Grant the scope to include it. |
| Runbook uploads fail with `blob already exists` | Module older than v2.3.0 | Upgrade. Uploads now pass `-Force`, so a second scheduled run overwrites rather than failing. See [Azure Automation Account](automation.md). |
| Chart step fails on a GitHub-hosted runner | Chart customization drives Excel over COM; no hosted runner has Excel | Keep `lite: true` in the action. See [GitHub Actions](github-actions.md). |
| `The term 'Invoke-AzCostManagementQuery' is not recognized` | `Az.CostManagement` missing, and before v2.5.3 `-IncludeCosts` treated that as fatal | Upgrade. Since v2.5.3 the run continues without cost data and warns instead. To collect costs, `Install-Module Az.CostManagement -Scope CurrentUser`. |
| `The property '<name>' cannot be found on this object` during extraction | Module older than v2.5.3 | Upgrade. This was a StrictMode member-enumeration fault that fired whenever an Azure API returned an empty result for **every** subscription — see [Changelog](changelog.md). |

## Run logs

**Every run writes a detailed log into its own run folder — you do not have to ask for it.**
When something goes wrong, read the log before re-running anything.

| File | Contents |
|------|----------|
| `scout-run.log` | Structured log: run metadata header, every phase boundary with elapsed time, per-phase counts, warnings, and — when a run fails — the full error record including the failing script, line number and script stack trace |
| `scout-console.log` | Transcript of everything printed to the console, warnings included. Skipped on hosts that do not support transcription (including Azure Automation) |

Both land next to the report:

```
C:\Users\you\Documents\AzureScout\2026-07-25_152431_d6fc73cf\
├── scout-run.log
├── scout-console.log
└── AzureScout_Report_2026-07-25_15_24.xlsx
```

A failed run prints the log path before it exits:

```
  The run failed. Full detail written to: C:\...\2026-07-25_152431_d6fc73cf\scout-run.log
```

The failure block in `scout-run.log` looks like this — the script and line are the fastest
route to a diagnosis, and are exactly what a bare console error does not give you:

```
[2026-07-25 15:58:09.445] [ERROR] ---------------- RUN FAILED ----------------
[2026-07-25 15:58:09.476] [ERROR] Message    : The term 'Invoke-AzCostManagementQuery' is not recognized...
[2026-07-25 15:58:09.587] [ERROR] Script     : ...\Modules\Private\Extraction\Get-AZTICostInventory.ps1
[2026-07-25 15:58:09.620] [ERROR] Line       : 49
[2026-07-25 15:58:09.682] [ERROR] ScriptStackTrace :
[2026-07-25 15:58:09.711] [ERROR]     at Get-AZSCCostInventory, ...
```

Logging is best-effort by design: if the log cannot be written the run still proceeds, warning
once. A lost log is a lost diagnostic, never a lost report.

## Debugging

For step-by-step tracing beyond the run log, enable debug output:

```powershell
Invoke-AzureScout -TenantID '00000000-...' -Debug
```

This produces timestamped log entries for each extraction step, module execution, and API call.

## Pre-flight Permission Check

Run the permission checker standalone to validate access before a full inventory:

```powershell
$result = Test-AZSCPermissions -TenantID '00000000-...' -Scope All
$result | Format-List
```

The `Details` array contains per-check results with remediation guidance for any failures.
