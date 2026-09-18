# Multi-tenant sign-in and recovery

Azure Scout authenticates the account at the start of a multi-tenant run, then acquires tenant contexts from that session. Selecting device-code login does not force another sign-in for each child. Children do not initiate interactive authentication. If a tenant requires a policy challenge or a new sign-in, its failure is recorded and the remaining tenants continue.

The guided menu asks whether to reuse the signed-in account, discovers accessible tenants, and offers one, selected, or all tenants. It asks for an individual tenant only after selecting the single-tenant option. Cancelling or selecting no tenants does not start a scan.

## Recover a run

Use the umbrella directory containing `run-summary.json`:

```powershell
# Retry failures, partial results and interrupted attempts only.
Invoke-AzureScout -ResumeRun 'D:\Reports\customer-run' -RetryFailed

# Retry one specific tenant from that run.
Invoke-AzureScout -ResumeRun 'D:\Reports\customer-run' -RetryTenant '<tenant-id>'

# Continue pending, failed, partial and interrupted tenants.
Invoke-AzureScout -ResumeRun 'D:\Reports\customer-run'
```

Resume uses the original account, module version and saved scan settings. Each retry writes a new attempt directory; successful tenant artifacts and previous attempts are preserved. A file lock prevents concurrent writers. The versioned checkpoint rejects unsupported schemas and changed scan settings.

Credentials are never saved in the checkpoint. Re-supply `-Secret`, `-CertificatePassword`, `-DevOpsPat` or `-OktaApiToken` when needed. Other scan options come from the checkpoint. For a tenant requiring authentication, sign in to that tenant with the original account, then retry it. Tenant consent and Conditional Access may require genuine interaction; Scout cannot bypass those requirements.

Older v1 run summaries cannot be resumed. Use a separate `Invoke-AzureScout -TenantID '<tenant-id>' -NoWizard` run with the original scan options for those runs.

## Understand completion

A child is complete only when it returns a typed result for the requested tenant and its report or evidence artifacts exist inside that attempt directory. A nonthrowing child with no result is a failure. Partial collection remains Partial; it is not promoted to Completed. Root summaries include pending, running, completed, partial, interrupted, skipped and failed counts.

If a checkpoint write fails, execution stops rather than scanning additional tenants without recording progress. The previous atomic JSON checkpoint and attempt directories remain available. Restore filesystem access before resuming; an interrupted attempt is retried in a new directory.

## Graph and guest accounts

Default Graph collection uses the selected Azure PowerShell identity. Scout also accepts an already-connected Microsoft Graph SDK context when its account, tenant, cloud and required scopes match. SDK context is checked on every token-provider lookup, including pagination and retries; a cached provider marker cannot select another tenant's active SDK context.

Scout does not automatically start a separate Graph device-code flow. For endpoints requiring additional delegated scopes, an administrator can explicitly consent and connect the Graph SDK before a targeted run. Azure role assignments, directory roles, OAuth scopes, consent, guest restrictions and licensing are independent requirements. Minimum ARM inventory permissions do not promise complete PIM, access-review or risky-user coverage. Entra Connect host topology can require local host access; Graph consent alone does not supply it.

The report includes catalog-derived identity permission requirements when an Identity cache exists. These describe requirements, not granted access. Collection outcomes record unavailable and not-assessed datasets. Supported authentication behavior is documented in [Set-AzContext](https://learn.microsoft.com/en-us/powershell/module/az.accounts/set-azcontext) and [Microsoft Graph authentication](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands).

## Evidence integrity

An inventory normalization failure no longer silently substitutes a narrower Resource Graph assessment. Scoring stops, while combined runs retain collected inventory and produce a partial inventory report. Processed datasets preserve child rows and label them separately from distinct resource identities. Raw identity evidence remains available even when ARM normalization fails.

Drift uses assessment membership plus rule ID. The same rule in different assessments can retain different verdicts. Existing bare-rule history cannot safely establish those assessment-specific baselines, so the first comparison after this change marks those entries New.

Customer-specific corrections are not hardcoded into future assessments. Historical verdict verification and compatibility with external customer export scripts require their original evidence/schema. Use the supported `-FromCollect` path to regenerate a report and its findings from a Scout collection snapshot; do not hand-edit HTML and leave companion JSONs stale.
