@{
    # Seven defects found in a v2.11.0 live run with -Debug on 2026-07-26.
    #
    # GitHub is master for Bugs (work-items standard), so issues 190-196 were opened first
    # and each Bug below carries the Hyperlink relation back to its issue. The conformance
    # audit requires Bug -> Feature, so these hang off a Feature under the v3 epic: they are
    # defects in the shipped product and must be fixed before v3.0.0.
    #
    # These are product defects only. Azure-side noise from the same log (breaking-change
    # warnings from Az.Monitor, rate-limit headers, empty result sets) is deliberately excluded.

    Tree = @(
        @{
            Key      = 'f-runtime'
            Type     = 'Feature'
            ParentId = 5917
            Priority = 2
            Title    = 'Fix the runtime defects a verbose live run exposes'
            Tags     = 'azure-scout; thisismydemo; powershell; resilience'
            Description = @'
<p>A v2.11.0 run with -Debug against a real tenant surfaced seven distinct product defects that a normal run hides: calls made against the wrong subscription, requests to endpoints Azure has retired, an unretried transient 500 that cost a minute of wall clock, a normal condition reported as an exception, a worksheet name silently truncated past the Excel limit, and authentication attempted against every tenant the account can see rather than the one requested.</p>
<p>Why now: none of these appear in the summary output, so the product looks clean while wasting round-trips, emitting alarming Conditional Access failures for unrelated tenants, and leaving columns blank. They are all in the shipped v2.11.0 and must be fixed before v3.0.0.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The seven defects tracked as child Bugs, each mastered by a GitHub issue.</li>
<li>Regression coverage for each, driven from a recorded payload rather than a live call.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Azure-side breaking-change warnings from the Az modules, which are informational and not ours to fix.</li>
<li>The engine rewrite itself, tracked by the sibling features on this epic.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'A verbose live run emits no raw PowerShell error records; every per-resource failure is a contained warning.'
                'No collector issues a request to an endpoint Azure has retired.'
                'A tenant-scoped run attempts authentication only against the requested tenant.'
            )
        }

        @{
            Key = 'bug-storage-context'; Type = 'Bug'; Parent = 'f-runtime'; Priority = 2; GitHubIssue = 190
            Title = 'Fix storage service-property lookups running against the wrong subscription'
            Tags  = 'azure-scout; thisismydemo; powershell; resilience'
            Description = @'
<p>Storage/StorageAccounts calls Get-AzStorageBlobServiceProperty and Get-AzStorageFileServiceProperty per account, and both fail with ResourceGroupNotFound for any account outside the currently selected subscription. The requests are issued against subscription 2aa5ed66 while the resource groups belong elsewhere, because the collector iterates accounts drawn from every subscription while the ambient Az context is pinned to whichever subscription was set last.</p>
<p>The failures are also uncontained: they print as raw PowerShell error records with source-line context, unlike every other per-resource failure in the codebase, which warns and continues.</p>
<p>Why now: soft-delete, versioning and retention columns are silently blank for those accounts, and the console output looks like a crash.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Scoping each lookup to the account own subscription, using the existing Invoke-AZSCInSubscriptionContext.</li>
<li>Containing the failure as a warning.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing which columns the collector emits.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: on v2.11.0 a tenant with storage accounts in more than one subscription produces ResourceGroupNotFound errors printed as raw error records.'
                'Fix verified: the same tenant produces populated soft-delete, versioning and retention columns for every account, with no raw error record in the output.'
                'A failure that is genuinely unreadable warns once naming the account and does not abort the collector.'
            )
        }

        @{
            Key = 'bug-appinsights-export'; Type = 'Bug'; Parent = 'f-runtime'; Priority = 3; GitHubIssue = 191
            Title = 'Stop calling the retired App Insights exportconfiguration endpoint'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Monitor/AppInsightsContinuousExport requests the exportconfiguration endpoint and Azure returns 400 DisallowedResourceOperation: the read operation on components/exportconfiguration is disallowed. Continuous Export was retired by Azure, so the call can never succeed for any tenant. This is not a permissions problem.</p>
<p>Why now: one wasted ARM round-trip per Application Insights component on every run, and a 400 in the log that reads as a defect in the caller.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Removing the collector, or recording the capability as retired and emitting no rows without issuing the request.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The other App Insights collectors, except where they share the same retired-endpoint pattern.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: on v2.11.0 the run issues the exportconfiguration request and receives 400 DisallowedResourceOperation.'
                'Fix verified: a run issues no request to that endpoint.'
                'If the collector is retained, it emits no rows and records why, rather than failing.'
            )
        }

        @{
            Key = 'bug-appinsights-workitems'; Type = 'Bug'; Parent = 'f-runtime'; Priority = 3; GitHubIssue = 192
            Title = 'Handle the App Insights WorkItemConfigs 404 that returns HTML instead of JSON'
            Tags  = 'azure-scout; thisismydemo; powershell; resilience'
            Description = @'
<p>Monitor/AppInsightsWorkItems requests the WorkItemConfigs endpoint and receives an IIS HTML error page with status 404 rather than JSON. Any code piping that body into ConvertFrom-Json either throws or silently yields nothing, so the collector must treat a non-JSON body as no data rather than as a payload.</p>
<p>Why now: one failing ARM round-trip per Application Insights component on every run, with a parse hazard behind it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Detecting the 404 and emitting no rows without attempting to parse the body.</li>
<li>Retiring the collector if the endpoint is gone for the same reason as Continuous Export.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Adding work-item integration data from another source.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: on v2.11.0 the request returns 404 with an HTML body.'
                'Fix verified: a recorded HTML 404 payload produces zero rows and no parse error.'
                'The run issues no request to a known-retired endpoint.'
            )
        }

        @{
            Key = 'bug-defender-500'; Type = 'Bug'; Parent = 'f-runtime'; Priority = 2; GitHubIssue = 193
            Title = 'Retry transient server errors from the Defender assessment collector'
            Tags  = 'azure-scout; thisismydemo; resilience; perf'
            Description = @'
<p>Get-AzSecurityAssessment returned HTTP 500 and the run absorbed sixty-six seconds of a seven-minute total on that single failed call, with no retry. A 500 from ARM is the canonical retryable status, and the same call succeeded for the other subscription seconds earlier, which is what a transient fault looks like. The collect layer has throttling and retry for Resource Graph; the Defender collectors have none.</p>
<p>Why now: one flaky response costs a minute of wall clock and silently drops the assessment rows for that subscription.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Bounded retry with backoff on 5xx for the Defender collectors.</li>
<li>A single warning naming the subscription when the retries are exhausted.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Retrying 4xx responses, which are not transient.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: a stubbed 500 response causes the collector to fail immediately with no retry and no rows.'
                'Fix verified: a stubbed 500 followed by a success yields the rows from the successful attempt.'
                'Exhausted retries warn once naming the subscription and the run continues.'
            )
        }

        @{
            Key = 'bug-defender-unregistered'; Type = 'Bug'; Parent = 'f-runtime'; Priority = 3; GitHubIssue = 194
            Title = 'Treat an unregistered Defender provider as a normal result rather than an exception'
            Tags  = 'azure-scout; thisismydemo; resilience'
            Description = @'
<p>Get-AzSecurityPricing returns 404 Subscription Not Registered for any subscription that has never registered the Microsoft.Security provider, and the collector surfaces it as an exception. This is not a fault: it is the correct answer for a subscription that does not use Defender for Cloud, which will be most subscriptions in most tenants. Both subscriptions in the verification tenant hit it on every run.</p>
<p>Why now: reporting a normal condition as an error trains operators to ignore errors.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Detecting the unregistered-provider response and recording the subscription as having no Defender plan.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Registering the provider on the operator behalf, which changes their Azure state.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: on v2.11.0 an unregistered subscription produces an exception in the run output.'
                'Fix verified: the same subscription produces no exception and is recorded as having no Defender plan.'
                'A genuine failure from the same cmdlet still warns.'
            )
        }

        @{
            Key = 'bug-sheetname'; Type = 'Bug'; Parent = 'f-runtime'; Priority = 2; GitHubIssue = 195
            Title = 'Fix the worksheet name that exceeds the Excel character limit and gate it in CI'
            Tags  = 'azure-scout; thisismydemo; reporting; testing'
            Description = @'
<p>The run warns that the worksheet name App Insights Proactive Detection was changed to App Insights Proactive Detectio because Excel caps worksheet names at thirty-one characters. Every consumer that looks a worksheet up by name is then looking for a name the workbook does not contain, which affects the JSON, Markdown, AsciiDoc and Power BI exporters as well as anything an operator writes downstream.</p>
<p>Why now: this is a live instance of exactly what the AB#5661 CI gate was written to catch. That gate checks definitions for duplicate and over-length names, and this collector still emits one, so the check either does not cover this path or is not applied to it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A deliberately chosen worksheet name of thirty-one characters or fewer.</li>
<li>Extending the CI gate so any collector producing a longer name fails the build.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Renaming worksheets that are already within the limit.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: on v2.11.0 the run emits the truncation warning for App Insights Proactive Detection.'
                'Fix verified: no run emits a worksheet truncation warning, and a test asserts the workbook contains no truncated names.'
                'The CI gate fails the build on a deliberately over-length worksheet name.'
            )
        }

        @{
            Key = 'bug-tenant-scope'; Type = 'Bug'; Parent = 'f-runtime'; Priority = 1; GitHubIssue = 196
            Title = 'Restrict a tenant-scoped run to the requested tenant instead of enumerating all of them'
            Tags  = 'azure-scout; thisismydemo; identity; security'
            Description = @'
<p>A single-tenant run enumerates every tenant the signed-in account can see and attempts to authenticate to each. The verification run listed six tenants and produced Conditional Access failures, multi-factor authentication prompts, and InvalidAuthenticationTokenTenant 401s where a token issued by one tenant was presented against a subscription belonging to another.</p>
<p>Why now: the failures name unrelated tenants and read as a security problem in the tool; each failed acquisition costs a round trip and MSAL throttles after them; and passing a tenant id is an explicit instruction to scan one tenant. The warning text also reads Unable to acquire token for tenant with an empty tenant id, so whatever emits it has lost the tenant it was working on.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Enumerating only the requested tenant subscriptions and requesting only that tenant tokens.</li>
<li>Skipping a subscription whose tenant does not match, without an authentication attempt.</li>
<li>Naming the tenant in any token-acquisition failure message.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Cross-tenant scanning, which is Lighthouse work tracked separately and explicitly excluded from this roadmap.</li>
</ul>
'@
            AcceptanceCriteria = @(
                'Repro confirmed: on v2.11.0 a tenant-scoped run from an account with access to other tenants produces Conditional Access, multi-factor and wrong-issuer failures naming those tenants.'
                'Fix verified: the same run attempts authentication only against the requested tenant and produces none of those failures.'
                'Any token-acquisition failure names the tenant it was for rather than an empty string.'
            )
        }
    )
}
