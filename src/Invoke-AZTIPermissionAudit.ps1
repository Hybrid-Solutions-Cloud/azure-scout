<#
.Synopsis
    Dedicated permission audit for Azure Scout.

.DESCRIPTION
    Runs a standalone permission audit without performing any inventory collection.
    Checks ARM/RBAC access across all visible subscriptions, validates critical Azure
    resource provider registration, and optionally audits Microsoft Graph / Entra ID
    permissions when -IncludeEntraPermissions is specified.

    Outputs colour-coded results to the console (green = OK, yellow = partial/warn,
    red = missing/fail).  Returns a structured object so callers can inspect results
    programmatically or serialize them to JSON.

.PARAMETER IncludeEntraPermissions
    Also audits Microsoft Graph permissions required for Entra ID scanning
    (-Scope All or -Scope EntraOnly).  Requires a Graph-capable token.

.PARAMETER TenantID
    Optional tenant ID override.  Used when connecting to a specific tenant.

.PARAMETER SubscriptionID
    One or more subscription IDs (or names) to scope the audit to.  When provided,
    only these subscriptions are checked for RBAC roles and resource-provider
    registration instead of all accessible subscriptions in the tenant.

.PARAMETER OutputFormat
    If 'Json' or 'Markdown', saves the audit result as a file alongside where the
    Excel report would normally land (the user's AZSC report directory).

.PARAMETER ReportDir
    Directory where the audit file is written when -OutputFormat is Json or Markdown.
    Defaults to the same path that Invoke-AzureScout would use.

.OUTPUTS
    [PSCustomObject] with:
        ArmAccess               [bool]
        GraphAccess             [bool]
        CallerAccount           [string]
        CallerType              [string]
        TenantId                [string]
        ArmDetails              [array]   — per-subscription ARM check objects
        ProviderResults         [array]   — per-subscription provider objects
        GraphDetails            [array]   — Graph permission check objects
        Recommendations         [array]   — actionable remediation strings
        OverallReadiness        [string]  — 'FullARM', 'FullARMAndEntra', 'Partial', 'Insufficient'

.LINK
    https://github.com/thisismydemo/azure-scout

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC)

.CATEGORY Management

.NOTES
    Version: 1.0.0
    First Release Date: February 24, 2026
    Authors: AzureScout Contributors
#>
# AB#6893 — Graph permissions whose data is gated by a LICENCE, not by consent.
#
# These are the ones where "grant the permission" is the wrong advice: the endpoint fails on an
# unlicensed tenant however much consent it has. Reporting that as DENIED sends the customer to
# chase a checkbox that cannot fix it, and since most tenants do not carry Entra ID P2, that was
# the COMMON case being reported as an error.
#
# Keyed by permission so the audit can look it up without a special case in the flow.
$Script:ScoutGraphLicensedFeature = @{
    'IdentityRiskyUser.Read.All' = @{
        Product    = 'Microsoft Entra ID P2'
        # subscribedSkus servicePlan names carry the feature, not the SKU marketing name --
        # AAD_PREMIUM_P2 appears in EMS E5 / Microsoft 365 E5 as well as standalone Entra ID P2,
        # so matching the service plan catches every route to the licence.
        SkuPattern = 'AAD_PREMIUM_P2'
    }
}

function Test-ScoutTenantLicence {
    <#
    .SYNOPSIS
        Is a service plan present on any subscribed SKU in this tenant?

    .DESCRIPTION
        AB#6893. Returns $true (present), $false (definitively absent) or $null (could not tell).

        The three-state return is the point. A caller must be able to distinguish "this tenant has
        no P2" from "I could not read the SKUs", because downgrading a genuine permission denial to
        a licensing note on the strength of a failed lookup would hide a real problem. Only an
        explicit $false softens the verdict.

        AB#7100: TenantID must be passed and threaded to the Graph token -- without it the
        subscribedSkus read comes from az CLI's ambient default tenant, not necessarily the
        tenant this audit was invoked against, and can report a licensed tenant as unlicensed.
    #>
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$SkuPattern,
        [string]$TenantID
    )

    try {
        $skus = @(Invoke-AZSCGraphRequest -Uri '/v1.0/subscribedSkus' -SinglePage -TenantID $TenantID)
        if ($skus.Count -eq 0) { return $null }
        foreach ($s in $skus) {
            $plans = $s.PSObject.Properties['servicePlans']
            if (-not $plans -or -not $plans.Value) { continue }
            foreach ($p in @($plans.Value)) {
                $name = $p.PSObject.Properties['servicePlanName']
                if ($name -and "$($name.Value)" -like "*$SkuPattern*") { return $true }
            }
        }
        return $false
    }
    catch {
        # Cannot read subscribedSkus (needs Organization.Read.All, which may itself be denied).
        # Unknown, not absent.
        Write-Verbose "Test-ScoutTenantLicence: could not read subscribedSkus ($($_.Exception.Message)); licence state unknown."
        return $null
    }
}

function Invoke-AZSCPermissionAudit {
    [CmdletBinding()]
    param(
        [switch]$IncludeEntraPermissions,
        [string]$TenantID,
        [string[]]$SubscriptionID,
        [ValidateSet('Console', 'Json', 'Markdown', 'AsciiDoc', 'All')]
        [string]$OutputFormat = 'Console',
        [string]$ReportDir
    )

    # ── Helpers ──────────────────────────────────────────────────────────────
    function Write-AuditLine {
        param($Status, $Text)
        switch ($Status) {
            'Pass'  { Write-Host "  [" -NoNewline; Write-Host " OK  " -ForegroundColor Green  -NoNewline; Write-Host "] $Text" }
            'Warn'  { Write-Host "  [" -NoNewline; Write-Host " WARN" -ForegroundColor Yellow -NoNewline; Write-Host "] $Text" }
            'Fail'  { Write-Host "  [" -NoNewline; Write-Host " FAIL" -ForegroundColor Red    -NoNewline; Write-Host "] $Text" }
            'Info'  { Write-Host "  [" -NoNewline; Write-Host " INFO" -ForegroundColor Cyan   -NoNewline; Write-Host "] $Text" }
            'Skip'  { Write-Host "  [" -NoNewline; Write-Host " SKIP" -ForegroundColor Gray   -NoNewline; Write-Host "] $Text" }
        }
    }

    function New-CheckResult {
        param($Check, $Status, $Message, $Remediation = $null)
        [PSCustomObject]@{
            Check       = $Check
            Status      = $Status
            Message     = $Message
            Remediation = $Remediation
        }
    }

    # ── Banner ────────────────────────────────────────────────────────────────
    Write-Host ''
    Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '║        Azure Scout — Permission Audit                      ║' -ForegroundColor Cyan
    Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if ($IncludeEntraPermissions.IsPresent) {
        Write-Host '  Scope: ARM/RBAC + Microsoft Graph (Entra ID)' -ForegroundColor Cyan
    } else {
        Write-Host '  Scope: ARM/RBAC only  (add -IncludeEntraPermissions to also audit Entra ID)' -ForegroundColor Gray
    }
    Write-Host ''

    # ── Caller context ────────────────────────────────────────────────────────
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Write-Host '  ERROR: No Azure authentication context found. Run Connect-AzAccount first.' -ForegroundColor Red
        return $null
    }

    $callerAccount = $ctx.Account.Id
    $callerType    = $ctx.Account.Type   # User / ServicePrincipal / ManagedServiceIdentity
    $tenantId      = if ($TenantID) { $TenantID } else { $ctx.Tenant.Id }

    Write-Host "  Account : $callerAccount"
    Write-Host "  Type    : $callerType"
    Write-Host "  Tenant  : $tenantId"
    Write-Host ''

    $armDetails      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $providerResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    $graphDetails    = [System.Collections.Generic.List[PSCustomObject]]::new()
    $recommendations = [System.Collections.Generic.List[string]]::new()
    # AB#6765 -- declared here, not inside the Graph branch, because the summary reads it
    # unconditionally and StrictMode makes an unset variable a terminating error.
    $emptyCollectors = [System.Collections.Generic.List[PSCustomObject]]::new()
    $armAccess       = $true
    $graphAccess     = $false   # stays false unless -IncludeEntraPermissions and tests pass

    # ═══════════════════════════════════════════════════════════════════════════
    # SECTION 1 — ARM / RBAC
    # ═══════════════════════════════════════════════════════════════════════════
    Write-Host '── ARM / RBAC Checks ────────────────────────────────────────────' -ForegroundColor White
    Write-Host ''

    # 1a — Subscription enumeration
    $subs = $null
    try {
        $subParams = @{ ErrorAction = 'Stop' }
        if ($TenantID) { $subParams['TenantId'] = $TenantID }
        $allSubs = @(Get-AzSubscription @subParams)

        # When -SubscriptionID is specified, scope the audit to only those subscriptions
        if ($SubscriptionID -and $SubscriptionID.Count -gt 0) {
            $subs = @($allSubs | Where-Object { $_.Id -in $SubscriptionID -or $_.Name -in $SubscriptionID })
            if ($subs.Count -eq 0) {
                $r = New-CheckResult 'ARM: Subscription Enumeration' 'Fail' `
                    "None of the specified subscription(s) ($($SubscriptionID -join ', ')) were found in the $($allSubs.Count) accessible subscription(s)" `
                    'Verify the -SubscriptionID value matches an accessible subscription ID or name.'
                Write-AuditLine -Status Fail -Text $r.Message
                $armAccess = $false
                $recommendations.Add('Verify -SubscriptionID matches an accessible subscription ID or name.')
            }
            else {
                $r = New-CheckResult 'ARM: Subscription Enumeration' 'Pass' `
                    "Scoped to $($subs.Count) of $($allSubs.Count) accessible subscription(s)"
                Write-AuditLine -Status Pass -Text $r.Message
            }
        }
        else {
            $subs = $allSubs
            $r = New-CheckResult 'ARM: Subscription Enumeration' 'Pass' "Found $($subs.Count) subscription(s) accessible to this identity"
            Write-AuditLine -Status Pass -Text $r.Message
        }
    }
    catch {
        $armAccess = $false
        $r = New-CheckResult 'ARM: Subscription Enumeration' 'Fail' $_.Exception.Message `
            'Grant the identity at least Reader role on one or more subscriptions.'
        Write-AuditLine -Status Fail -Text $r.Message
        $recommendations.Add("Grant Reader role: New-AzRoleAssignment -ObjectId <principalId> -RoleDefinitionName 'Reader' -Scope '/subscriptions/<subId>'")
    }
    $armDetails.Add($r)

    # 1b — Root Management Group access
    try {
        $mgScope = "/providers/Microsoft.Management/managementGroups/$tenantId"
        $mgAssign = @(Get-AzRoleAssignment -Scope $mgScope -ErrorAction Stop) | Select-Object -First 1
        $r = New-CheckResult 'ARM: Root Management Group Access' 'Pass' 'Can read root management group role assignments (broadest scope)'
        Write-AuditLine -Status Pass -Text $r.Message
    }
    catch {
        $r = New-CheckResult 'ARM: Root Management Group Access' 'Warn' `
            "Cannot read root MG role assignments — inventory will run per-subscription instead" `
            "Grant Reader at root MG: New-AzRoleAssignment -ObjectId {principalId} -RoleDefinitionName 'Reader' -Scope '/providers/Microsoft.Management/managementGroups/$tenantId'"
        Write-AuditLine -Status Warn -Text $r.Message
    }
    $armDetails.Add($r)

    # 1c — Per-subscription role check
    if ($subs -and $subs.Count -gt 0) {
        Write-Host ''
        Write-Host "  Subscription role summary ($($subs.Count) subscription(s)):" -ForegroundColor White
        Write-Host ''

        # AB#6778. This used to list Security Reader, Monitoring Reader and Cost Management
        # Reader as optional roles, warn on every subscription that lacked them, and emit a
        # New-AzRoleAssignment line telling the operator to grant Security Reader. All three
        # are redundant: Azure `Reader` is `Actions: ["*/read"]` with an empty `NotActions`,
        # and every action Scout calls through those roles is inside that single wildcard.
        #
        # Two of them are worse than merely useless as an ask. Monitoring Reader and Cost
        # Management Reader both carry `Microsoft.Support/*`, which includes support-ticket
        # CREATION -- a write, in a tool sold as read-only. Security Reader carries five IoT
        # Defender `/action` permissions, one of which downloads a password-reset file.
        #
        # Cost data in particular was never gated on Cost Management Reader: it is gated on
        # the EA "AO view charges" / MCA "Azure charges" billing setting, which no RBAC role
        # can grant. Recommending the role was advice that could not work.
        $requiredRoles = @{
            'Reader' = 'Core inventory (required)'
        }

        # AB#368 — try/finally, not a scriptblock, so the loop body keeps writing to the
        # enclosing scope's $armAccess/$armDetails/$recommendations while the caller's
        # subscription context is still restored on both the normal and the error path.
        $armLoopContext = Get-AzContext -ErrorAction SilentlyContinue
        try {
            foreach ($sub in $subs) {
                try {
                    Set-AzContext -Subscription $sub.Id -Tenant $tenantId -ErrorAction SilentlyContinue | Out-Null
                    $assignments = @(Get-AzRoleAssignment -Scope "/subscriptions/$($sub.Id)" -ErrorAction Stop)

                    $foundRoles = $assignments | Select-Object -ExpandProperty RoleDefinitionName -Unique
                    $missingCritical = $requiredRoles.Keys | Where-Object { $_ -eq 'Reader' -and $_ -notin $foundRoles }

                    # There is no longer an "optional roles are missing" Warn state: Reader is
                    # the whole ARM ask (AB#6778), so a subscription either has it or does not.
                    $status = if ($missingCritical) { 'Fail' } else { 'Pass' }

                    $rolesDisplay = ($requiredRoles.Keys | ForEach-Object {
                        $emoji = if ($_ -in $foundRoles) { '✅' } else { if ($_ -eq 'Reader') { '❌' } else { '⚠️' } }
                        "$emoji $_"
                    }) -join '  '

                    $subMsg = "[$($sub.Name)] $rolesDisplay"
                    Write-AuditLine -Status $status -Text $subMsg

                    $subResult = [PSCustomObject]@{
                        SubscriptionId   = $sub.Id
                        SubscriptionName = $sub.Name
                        State            = $sub.State
                        AssignedRoles    = $foundRoles
                        HasReader        = 'Reader' -in $foundRoles
                        Status           = $status
                    }
                    $armDetails.Add([PSCustomObject]@{
                        Check       = "ARM: Subscription [$($sub.Name)]"
                        Status      = $status
                        Message     = $subMsg
                        Remediation = if ($missingCritical) { "Add Reader role on subscription $($sub.Id)" } else { $null }
                    })

                    if ($missingCritical) {
                        $armAccess = $false
                        $recommendations.Add("Add Reader role on '$($sub.Name)': New-AzRoleAssignment -ObjectId {principalId} -RoleDefinitionName 'Reader' -Scope '/subscriptions/$($sub.Id)'")
                    }
                }
                catch {
                    Write-AuditLine -Status Warn -Text "[$($sub.Name)] Cannot read role assignments: $($_.Exception.Message)"
                }
            }
        }
        finally {
            # Written inline rather than calling the shared Restore-AZSCContext helper:
            # the audit is dot-sourced standalone (by tests, and by callers that do not
            # import the whole module) and must not depend on a sibling file being loaded.
            # Property presence is tested via PSObject.Properties because a bare
            # $ctx.Subscription THROWS under Set-StrictMode when the property is absent,
            # and callers with strict mode in their profile do reach this path.
            $restoreId = $null
            if ($armLoopContext -and $armLoopContext.PSObject.Properties.Name -contains 'Subscription' -and $armLoopContext.Subscription) {
                if ($armLoopContext.Subscription.PSObject.Properties.Name -contains 'Id') {
                    $restoreId = $armLoopContext.Subscription.Id
                }
            }
            if ($restoreId) {
                $restoreParams = @{ Subscription = $restoreId; ErrorAction = 'SilentlyContinue' }
                if ($armLoopContext.PSObject.Properties.Name -contains 'Tenant' -and $armLoopContext.Tenant -and $armLoopContext.Tenant.PSObject.Properties.Name -contains 'Id' -and $armLoopContext.Tenant.Id) {
                    $restoreParams['Tenant'] = $armLoopContext.Tenant.Id
                }
                Set-AzContext @restoreParams | Out-Null
            }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # SECTION 2 — Resource Provider Registration
    # ═══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Resource Provider Registration ───────────────────────────────' -ForegroundColor White
    Write-Host ''

    $criticalProviders = [ordered]@{
        'Microsoft.Security'                = 'Microsoft Defender for Cloud'
        'Microsoft.Insights'                = 'Azure Monitor, Application Insights'
        'Microsoft.Maintenance'             = 'Azure Update Manager'
        'Microsoft.DesktopVirtualization'   = 'Azure Virtual Desktop'
        'Microsoft.HybridCompute'           = 'Azure Arc-enabled Servers'
        'Microsoft.AzureStackHCI'           = 'Azure Local (Azure Stack HCI)'
        'Microsoft.MachineLearningServices' = 'Azure Machine Learning / AI Foundry'
        'Microsoft.CognitiveServices'       = 'Azure OpenAI, Cognitive Services, Bot Services'
        'Microsoft.Search'                  = 'Azure AI Search'
        'Microsoft.BotService'              = 'Azure Bot Services'
        'Microsoft.AlertsManagement'        = 'Azure Monitor Smart Alerts'
        'Microsoft.OperationalInsights'     = 'Log Analytics Workspaces'
        'Microsoft.AzureArcData'            = 'Arc-enabled SQL Server / Data Services'
        'Microsoft.Kubernetes'              = 'Arc-enabled Kubernetes'
    }

    # NOTE: wrap in @() — Where-Object/Select-Object collapse a single match to a bare
    # scalar object (not an array). Accessing .Count on that scalar is silently coerced
    # to 1 by PowerShell 7's intrinsic Count/Length member, but THROWS under strict mode
    # on Windows PowerShell 5.1 ("The property 'Count' cannot be found on this object"),
    # since Desktop edition has no such intrinsic. @() guarantees a real array here.
    $targetSubs = @(if ($subs) { $subs | Where-Object { $_.State -eq 'Enabled' } | Select-Object -First 3 } else { @() })

    if ($targetSubs.Count -gt 0) {
        $checkSub = $targetSubs[0]

        # AB#368 — the provider probe borrows a subscription context; the audit must not
        # leave the caller parked in it once the section is done.
        $providerLoopContext = Get-AzContext -ErrorAction SilentlyContinue
        try {
            Set-AzContext -Subscription $checkSub.Id -Tenant $tenantId -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  Checking against subscription: $($checkSub.Name)" -ForegroundColor Gray
            Write-Host "  NOTE: Not all providers need to be registered. Unregistered providers are" -ForegroundColor DarkGray
            Write-Host "        expected — they simply mean that service is not deployed here." -ForegroundColor DarkGray
            Write-Host "        The scan will complete successfully; those modules will be skipped." -ForegroundColor DarkGray
            Write-Host ''

            foreach ($kvp in $criticalProviders.GetEnumerator()) {
                $provider = $kvp.Key
                $purpose  = $kvp.Value
                try {
                    $reg = Get-AzResourceProvider -ProviderNamespace $provider -ErrorAction Stop
                    $state = ($reg | Select-Object -ExpandProperty RegistrationState -First 1)
                    $status = if ($state -eq 'Registered') { 'Pass' } elseif ($state -in 'Registering','Unregistering') { 'Warn' } else { 'Info' }
                    $skipText = if ($status -eq 'Info') { " (modules for this service will be skipped)" } else { '' }
                    Write-AuditLine -Status $status -Text "$provider  [$state]  — $purpose$skipText"

                    if ($status -ne 'Pass') {
                        $recommendations.Add("Register provider: Register-AzResourceProvider -ProviderNamespace '$provider'")
                    }
                }
                catch {
                    $state = 'Unknown'
                    $status = 'Warn'
                    Write-AuditLine -Status Warn -Text "$provider  [Unknown — cannot read]  — $purpose"
                }

                $providerResults.Add([PSCustomObject]@{
                    SubscriptionId   = $checkSub.Id
                    SubscriptionName = $checkSub.Name
                    Provider         = $provider
                    Purpose          = $purpose
                    RegistrationState = $state
                    Status           = $status
                })
            }
        }
        finally {
            $restoreId = $null
            if ($providerLoopContext -and $providerLoopContext.PSObject.Properties.Name -contains 'Subscription' -and $providerLoopContext.Subscription) {
                if ($providerLoopContext.Subscription.PSObject.Properties.Name -contains 'Id') {
                    $restoreId = $providerLoopContext.Subscription.Id
                }
            }
            if ($restoreId) {
                $restoreParams = @{ Subscription = $restoreId; ErrorAction = 'SilentlyContinue' }
                if ($providerLoopContext.PSObject.Properties.Name -contains 'Tenant' -and $providerLoopContext.Tenant -and $providerLoopContext.Tenant.PSObject.Properties.Name -contains 'Id' -and $providerLoopContext.Tenant.Id) {
                    $restoreParams['Tenant'] = $providerLoopContext.Tenant.Id
                }
                Set-AzContext @restoreParams | Out-Null
            }
        }
    }
    else {
        Write-AuditLine -Status Skip -Text 'No enabled subscriptions available — skipping provider check'
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # SECTION 3 — Microsoft Graph / Entra ID (optional)
    # ═══════════════════════════════════════════════════════════════════════════
    if ($IncludeEntraPermissions.IsPresent) {
        Write-Host ''
        Write-Host '── Microsoft Graph / Entra ID Checks ───────────────────────────' -ForegroundColor White
        Write-Host ''

        $graphToken = $null
        try {
            $graphToken = Get-AZSCGraphToken -TenantID $tenantId
            Write-AuditLine -Status Pass -Text 'Microsoft Graph token acquired successfully'
        }
        catch {
            Write-AuditLine -Status Fail -Text "Cannot acquire Microsoft Graph token: $($_.Exception.Message)"
            $graphDetails.Add(( New-CheckResult 'Graph: Token Acquisition' 'Fail' $_.Exception.Message `
                "Ensure the identity has Graph API permissions. For SPNs: grant app permissions in Entra ID app registration. For users: ensure Directory Readers or Global Reader directory role." ))
            $recommendations.Add('Grant Graph permissions — in Entra ID portal: App Registrations > API Permissions > Microsoft Graph > Directory.Read.All (application permission, requires admin consent)')
        }

        if ($graphToken) {
            # AB#6765 -- the checks are DERIVED from the query catalog Scout actually runs and
            # from the collector manifests that consume it, not from a second hand-maintained
            # list. The old list had nine entries and a hardcoded four of them were "critical";
            # a denial outside those four left the run reporting READY with an empty worksheet
            # behind it, and 'Graph: Audit Logs Read' was checked at all despite no collector
            # reading sign-in logs.
            #
            # Loaded defensively, for the same reason the context restore below is written
            # inline rather than through the shared helper: this file is dot-sourced standalone
            # by tests and by callers that do not import the whole module, so it must not
            # assume a sibling has already been loaded.
            if (-not (Get-Command Get-ScoutEntraQueryCatalog -ErrorAction SilentlyContinue)) {
                . (Join-Path $PSScriptRoot 'collect/Get-ScoutEntraQueryCatalog.ps1')
            }
            if (-not (Get-Command Get-ScoutGraphPermissionImpact -ErrorAction SilentlyContinue)) {
                . (Join-Path $PSScriptRoot 'Get-ScoutGraphPermissionImpact.ps1')
            }

            $graphImpact = @(Get-ScoutGraphPermissionImpact)

            $graphAccess = $true

            foreach ($impact in $graphImpact) {
                $checkName  = "Graph: $($impact.Permission)"
                $probe      = @(Get-ScoutEntraQueryCatalog | Where-Object { $_.Permission -eq $impact.Permission })[0]
                $purpose    = ($impact.Queries -join ', ')

                if (-not $impact.IsConsumed) {
                    # A permission no collector consumes is not worth failing, warning, or even
                    # asking for. Say so rather than quietly probing it every run.
                    $r = New-CheckResult $checkName 'Warn' `
                        "$($impact.Permission) — queried ($purpose) but NO collector reads the result. Do not grant it." `
                        "Remove '$($impact.Permission)' from the access request — nothing consumes it."
                    Write-AuditLine -Status Warn -Text "$checkName — queried but unused by every collector"
                    $graphDetails.Add($r)
                    continue
                }

                try {
                    $null = Invoke-AZSCGraphRequest -Uri $probe.Uri -SinglePage -TenantID $tenantId
                    $r = New-CheckResult $checkName 'Pass' "$($impact.Permission) — $purpose ($($impact.CollectorCount) collectors)"
                    Write-AuditLine -Status Pass -Text "$checkName  [$($impact.CollectorCount) collectors]"
                }
                catch {
                    # AB#6893. A LICENSED-FEATURE permission is not a misconfiguration. Identity
                    # Protection is Entra ID P2; on a tenant without P2 the risky-users endpoint
                    # fails no matter how much consent is granted, and reporting that as
                    # "DENIED - grant this permission" sends the customer to chase a checkbox
                    # that will not fix it. Most tenants do not have P2, so this was the common
                    # case being reported as an error.
                    #
                    # Scout already collects subscribedSkus, so the licence state is knowable
                    # rather than guessable -- and when it is not knowable this stays a Fail,
                    # because silently downgrading a real denial would be the worse error.
                    if ($Script:ScoutGraphLicensedFeature.ContainsKey($impact.Permission)) {
                        $req = $Script:ScoutGraphLicensedFeature[$impact.Permission]
                        $licensed = Test-ScoutTenantLicence -SkuPattern $req.SkuPattern -TenantID $tenantId
                        if ($licensed -eq $false) {
                            foreach ($c in $impact.Collectors) {
                                $emptyCollectors.Add([PSCustomObject]@{
                                        Collector  = $c
                                        Reason     = "Not licensed — requires $($req.Product)"
                                        Permission = $impact.Permission
                                    })
                            }
                            $r = New-CheckResult $checkName 'Warn' `
                                "NOT LICENSED — $($impact.Permission) ($purpose) requires $($req.Product), which this tenant does not have. $($impact.CollectorCount) collector(s) will be empty and are reported as Not assessed: $($impact.Collectors -join ', ')" `
                                "No action needed unless you intend to license $($req.Product). Granting the permission alone will not populate these collectors."
                            Write-AuditLine -Status Warn -Text "$checkName — not licensed ($($req.Product)); reported as Not assessed"
                            $graphDetails.Add($r)
                            continue
                        }
                    }

                    # Criticality is derived: this permission has consumers, so denying it
                    # empties worksheets, so the run is not READY. There is no list to edit.
                    $graphAccess = $false
                    foreach ($c in $impact.Collectors) {
                        $emptyCollectors.Add([PSCustomObject]@{
                            Collector  = $c
                            Reason     = 'Graph permission denied'
                            Permission = $impact.Permission
                        })
                    }
                    $r = New-CheckResult $checkName 'Fail' `
                        "DENIED — $($impact.Permission) ($purpose). $($impact.CollectorCount) collectors will be empty: $($impact.Collectors -join ', ')" `
                        "Grant '$($impact.Permission)' in Entra ID > Enterprise Applications > API Permissions"
                    Write-AuditLine -Status Fail -Text "$checkName — DENIED; $($impact.CollectorCount) collectors will be empty"
                    # AB#6765 -- this used to be a coloured Write-Host and nothing else, so a
                    # denied permission never reached the warning stream and never reached the
                    # run's error count. An automated caller could not tell.
                    Write-Warning "[AzureScout] Graph permission '$($impact.Permission)' is DENIED. These collectors will produce no data: $($impact.Collectors -join ', ')."
                    $recommendations.Add("Grant Graph permission '$($impact.Permission)' — without it these collectors are empty: $($impact.Collectors -join ', ')")
                }
                $graphDetails.Add($r)
            }
        }
    }
    else {
        $graphAccess = $null   # not checked
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # SECTION 4 — Summary & Recommendations
    # ═══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Summary ──────────────────────────────────────────────────────' -ForegroundColor White
    Write-Host ''

    $overallReadiness = switch ($true) {
        { -not $armAccess }                             { 'Insufficient' }
        { $armAccess -and $graphAccess -eq $true }      { 'FullARMAndEntra' }
        { $armAccess -and $graphAccess -eq $false }     { 'Partial' }
        { $armAccess -and $null -eq $graphAccess }      { 'FullARM' }
        default                                         { 'Unknown' }
    }

    $readinessColor = switch ($overallReadiness) {
        'FullARMAndEntra'  { 'Green'  }
        'FullARM'          { 'Green'  }
        'Partial'          { 'Yellow' }
        'Insufficient'     { 'Red'    }
        default            { 'Gray'   }
    }

    $readinessText = switch ($overallReadiness) {
        'FullARMAndEntra'  { 'READY — Full ARM + Entra ID scan supported' }
        'FullARM'          { 'READY — ARM-only scan supported  (use -Scope ArmOnly)' }
        'Partial'          { 'PARTIAL — ARM accessible, but some Graph permissions are missing (use -Scope ArmOnly for full coverage)' }
        'Insufficient'     { 'INSUFFICIENT — ARM access is missing on one or more subscriptions' }
        default            { 'UNKNOWN' }
    }

    Write-Host "  Overall Readiness: " -NoNewline
    Write-Host $readinessText -ForegroundColor $readinessColor
    Write-Host ''

    # ── AB#6765: the impact table ─────────────────────────────────────────────
    # The verdict word above is kept because scripts read $result.OverallReadiness, but it is no
    # longer the answer. This table is: it names every collector that will produce no data and
    # the permission each one needs. A word can be wrong in a way a list cannot -- "READY"
    # printed over four empty worksheets is exactly the failure this replaces.
    if ($emptyCollectors -and $emptyCollectors.Count -gt 0) {
        Write-Host "  Collectors that will produce NO data ($($emptyCollectors.Count)):" -ForegroundColor Yellow
        Write-Host ''
        foreach ($row in ($emptyCollectors | Sort-Object Collector)) {
            Write-Host ('    {0,-40} {1} — needs {2}' -f $row.Collector, $row.Reason, $row.Permission) -ForegroundColor Yellow
        }
        Write-Host ''
    }
    elseif ($null -ne $graphAccess) {
        Write-Host '  Every Entra collector has the permission it needs.' -ForegroundColor Green
        Write-Host ''
    }

    # @() guard: when $recommendations is empty, piping it through Sort-Object -Unique
    # emits nothing at all, so the expression evaluates to $null — and $null.Count
    # throws under strict mode on every PowerShell edition/version, not just 5.1.
    $recCount = @($recommendations | Sort-Object -Unique).Count
    if ($recCount -gt 0) {
        Write-Host "  Recommendations ($recCount):" -ForegroundColor Yellow
        Write-Host ''
        $recommendations | Sort-Object -Unique | ForEach-Object {
            Write-Host "    • $_" -ForegroundColor Yellow
        }
        Write-Host ''
    }
    else {
        Write-Host '  No remediation actions required.' -ForegroundColor Green
        Write-Host ''
    }

    # Suggested command
    Write-Host '  Suggested Invoke-AzureScout command:' -ForegroundColor Cyan
    $scopeSuggestion = if ($overallReadiness -eq 'FullARMAndEntra') { '-Scope All' } else { '-Scope ArmOnly' }
    Write-Host "    Invoke-AzureScout -TenantID $tenantId $scopeSuggestion" -ForegroundColor Cyan
    Write-Host ''

    # ── Build result object ────────────────────────────────────────────────────
    $result = [PSCustomObject]@{
        ArmAccess        = $armAccess
        GraphAccess      = $graphAccess
        CallerAccount    = $callerAccount
        CallerType       = $callerType
        TenantId         = $tenantId
        ArmDetails       = $armDetails.ToArray()
        ProviderResults  = $providerResults.ToArray()
        GraphDetails     = $graphDetails.ToArray()
        Recommendations  = ($recommendations | Sort-Object -Unique)
        # AB#6765 -- the per-collector impact, so an automated caller gets the same answer the
        # console table shows instead of having to interpret OverallReadiness.
        EmptyCollectors  = @($emptyCollectors | Sort-Object Collector)
        OverallReadiness = $overallReadiness
        AuditTimestamp   = (Get-Date -Format 'o')
    }

    # ── Optional file output ───────────────────────────────────────────────────
    if ($OutputFormat -in 'Json', 'All') {
        $reportPath = if ($ReportDir) { $ReportDir } else {
            $rp = Set-AZSCReportPath -ReportDir $null
            $rp.DefaultPath
        }
        if (-not (Test-Path $reportPath)) { New-Item -ItemType Directory -Path $reportPath -Force | Out-Null }
        $jsonFile = Join-Path $reportPath ("PermissionAudit_" + (Get-Date -Format 'yyyy-MM-dd_HH_mm') + ".json")
        $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -Encoding UTF8
        Write-Host "  Audit saved → $jsonFile" -ForegroundColor Cyan
    }

    if ($OutputFormat -in 'Markdown', 'All') {
        $reportPath = if ($ReportDir) { $ReportDir } else {
            $rp = Set-AZSCReportPath -ReportDir $null
            $rp.DefaultPath
        }
        if (-not (Test-Path $reportPath)) { New-Item -ItemType Directory -Path $reportPath -Force | Out-Null }
        $mdFile = Join-Path $reportPath ("PermissionAudit_" + (Get-Date -Format 'yyyy-MM-dd_HH_mm') + ".md")

        $mdLines = [System.Collections.Generic.List[string]]::new()
        $mdLines.Add('# Azure Scout - Permission Audit Report')
        $mdLines.Add("")
        $mdLines.Add("| Field | Value |")
        $mdLines.Add("|-------|-------|")
        $mdLines.Add("| Generated | " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " |")
        $mdLines.Add("| Account | $callerAccount |")
        $mdLines.Add("| Account Type | $callerType |")
        $mdLines.Add("| Tenant ID | $tenantId |")
        $mdLines.Add("| Overall Readiness | **$overallReadiness** |")
        $mdLines.Add("")
        $mdLines.Add("## ARM / RBAC Checks")
        $mdLines.Add("")
        $mdLines.Add("| Check | Status | Message | Remediation |")
        $mdLines.Add("|-------|--------|---------|-------------|")
        foreach ($d in $armDetails) {
            $icon = switch ($d.Status) { 'Pass' { '✅' } 'Warn' { '⚠️' } 'Fail' { '❌' } default { 'ℹ️' } }
            $mdLines.Add("| $($d.Check) | $icon $($d.Status) | $($d.Message -replace '\|','&#124;') | $($d.Remediation -replace '\|','&#124;') |")
        }
        $mdLines.Add("")
        $mdLines.Add("## Resource Provider Registration")
        $mdLines.Add("")
        $mdLines.Add("| Provider | Purpose | State | Status |")
        $mdLines.Add("|----------|---------|-------|--------|")
        foreach ($p in $providerResults) {
            $icon = switch ($p.Status) { 'Pass' { '✅' } 'Warn' { '⚠️' } 'Fail' { '❌' } default { 'ℹ️' } }
            $mdLines.Add("| $($p.Provider) | $($p.Purpose) | $($p.RegistrationState) | $icon |")
        }
        if ($graphDetails.Count -gt 0) {
            $mdLines.Add("")
            $mdLines.Add("## Microsoft Graph / Entra ID Permissions")
            $mdLines.Add("")
            $mdLines.Add("| Check | Status | Details |")
            $mdLines.Add("|-------|--------|---------|")
            foreach ($g in $graphDetails) {
                $icon = switch ($g.Status) { 'Pass' { '✅' } 'Warn' { '⚠️' } 'Fail' { '❌' } default { 'ℹ️' } }
                $mdLines.Add("| $($g.Check) | $icon $($g.Status) | $($g.Message -replace '\|','&#124;') |")
            }
        }
        if ($recommendations.Count -gt 0) {
            $mdLines.Add("")
            $mdLines.Add("## Recommendations")
            $mdLines.Add("")
            $recommendations | Sort-Object -Unique | ForEach-Object { $mdLines.Add("- ``$_``") }
        }
        $mdLines | Out-File -FilePath $mdFile -Encoding UTF8
        Write-Host "  Audit saved → $mdFile" -ForegroundColor Cyan
    }

    if ($OutputFormat -in 'AsciiDoc', 'All') {
        $reportPath = if ($ReportDir) { $ReportDir } else {
            $rp = Set-AZSCReportPath -ReportDir $null
            $rp.DefaultPath
        }
        if (-not (Test-Path $reportPath)) { New-Item -ItemType Directory -Path $reportPath -Force | Out-Null }
        $adocFile = Join-Path $reportPath ("PermissionAudit_" + (Get-Date -Format 'yyyy-MM-dd_HH_mm') + ".adoc")

        $adocLines = [System.Collections.Generic.List[string]]::new()
        $adocLines.Add('= Azure Scout — Permission Audit Report')
        $adocLines.Add(':toc: left')
        $adocLines.Add(':toclevels: 2')
        $adocLines.Add(':icons: font')
        $adocLines.Add(':source-highlighter: highlight.js')
        $adocLines.Add('')
        $adocLines.Add('[%autowidth.stretch]')
        $adocLines.Add('|===')
        $adocLines.Add('| Field | Value')
        $adocLines.Add('')
        $adocLines.Add("| Generated | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $adocLines.Add("| Account | $callerAccount")
        $adocLines.Add("| Account Type | $callerType")
        $adocLines.Add("| Tenant ID | $tenantId")
        $adocLines.Add("| Overall Readiness | *$overallReadiness*")
        $adocLines.Add('|===')
        $adocLines.Add('')
        $adocLines.Add('== ARM / RBAC Checks')
        $adocLines.Add('')
        $adocLines.Add('[%autowidth.stretch,cols="2,1,3,3"]')
        $adocLines.Add('|===')
        $adocLines.Add('| Check | Status | Message | Remediation')
        $adocLines.Add('')
        foreach ($d in $armDetails) {
            $icon = switch ($d.Status) { 'Pass' { 'icon:check-circle[role=green]' } 'Warn' { 'icon:exclamation-triangle[role=yellow]' } 'Fail' { 'icon:times-circle[role=red]' } default { 'icon:info-circle[]' } }
            $adocLines.Add("| $($d.Check) | $icon $($d.Status) | $($d.Message) | $($d.Remediation)")
            $adocLines.Add('')
        }
        $adocLines.Add('|===')
        $adocLines.Add('')
        $adocLines.Add('== Resource Provider Registration')
        $adocLines.Add('')
        $adocLines.Add('[%autowidth.stretch,cols="2,2,1,1"]')
        $adocLines.Add('|===')
        $adocLines.Add('| Provider | Purpose | State | Status')
        $adocLines.Add('')
        foreach ($p in $providerResults) {
            $stateIcon = switch ($p.Status) { 'Pass' { 'icon:check-circle[role=green]' } 'Warn' { 'icon:exclamation-triangle[role=yellow]' } 'Fail' { 'icon:times-circle[role=red]' } default { 'icon:info-circle[]' } }
            $adocLines.Add("| $($p.Provider) | $($p.Purpose) | $($p.RegistrationState) | $stateIcon")
            $adocLines.Add('')
        }
        $adocLines.Add('|===')
        if ($graphDetails.Count -gt 0) {
            $adocLines.Add('')
            $adocLines.Add('== Microsoft Graph / Entra ID Permissions')
            $adocLines.Add('')
            $adocLines.Add('[%autowidth.stretch,cols="2,1,3"]')
            $adocLines.Add('|===')
            $adocLines.Add('| Check | Status | Details')
            $adocLines.Add('')
            foreach ($g in $graphDetails) {
                $gIcon = switch ($g.Status) { 'Pass' { 'icon:check-circle[role=green]' } 'Warn' { 'icon:exclamation-triangle[role=yellow]' } 'Fail' { 'icon:times-circle[role=red]' } default { 'icon:info-circle[]' } }
                $adocLines.Add("| $($g.Check) | $gIcon $($g.Status) | $($g.Message)")
                $adocLines.Add('')
            }
            $adocLines.Add('|===')
        }
        if ($recommendations.Count -gt 0) {
            $adocLines.Add('')
            $adocLines.Add('== Recommendations')
            $adocLines.Add('')
            $recommendations | Sort-Object -Unique | ForEach-Object { $adocLines.Add("[source,powershell]`n----`n$_`n----`n") }
        }
        $adocLines | Out-File -FilePath $adocFile -Encoding UTF8
        Write-Host "  Audit saved → $adocFile" -ForegroundColor Cyan
    }

    return $result
}
