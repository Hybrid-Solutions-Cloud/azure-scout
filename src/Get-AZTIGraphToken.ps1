#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
    Acquire a Microsoft Graph bearer token for the selected Azure context.

.DESCRIPTION
    Uses Get-AzAccessToken for service principals, managed identities, and requests that do not
    need explicit delegated scopes. Interactive user collection that requires granular delegated
    scopes uses Microsoft.Graph.Authentication's device-code flow. Azure CLI is never used.
    Successful authentication state is cached per Graph
    endpoint, tenant, selected Az account identity, and scope set, and are refreshed automatically
    when within 5 minutes of expiry.

.PARAMETER TenantID
    Optional tenant ID to scope the token to. Pass the same TenantID given to
    Invoke-AzureScout / Invoke-AZSCPermissionAudit so ARM and Graph remain pinned
    to the same resource tenant.

.OUTPUTS
    [hashtable] Authorization headers ready for Invoke-RestMethod:
    @{ 'Authorization' = 'Bearer <token>'; 'Content-Type' = 'application/json' }

.LINK
    https://github.com/Hybrid-Solutions-Cloud/azure-scout

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
    Version: 1.2.0
    Authors: thisismydemo
    Modified: 2026-02-24 - Changed from Get-AzAccessToken to Azure CLI for proper Graph scopes
    Modified: 2026-08-08 - AB#7100 -- Added -TenantID so the token targets the tenant being
              audited/collected instead of az CLI's ambient default; cache keyed per tenant so
              a run touching multiple tenants can't return one tenant's cached token for another.
    Modified: 2026-08-11 - Use only the selected Az context and isolate the cache by account;
              a different Azure CLI login cannot hijack Entra collection or require a second sign-in.
#>
function Get-AZSCGraphToken {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [string]$TenantID,
        [string[]]$Scopes = @(),
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$AzureEnvironment
    )

    $azContext = $null
    try {
        $azContext = Get-AzContext -ErrorAction SilentlyContinue
    }
    catch { }

    if (-not $AzureEnvironment) {
        try {
            if ($azContext -and $azContext.PSObject.Properties.Name -contains 'Environment' -and
                $azContext.Environment -and $azContext.Environment.PSObject.Properties.Name -contains 'Name') {
                $AzureEnvironment = [string]$azContext.Environment.Name
            }
        }
        catch { }
    }
    if ($AzureEnvironment -notin @('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')) {
        $AzureEnvironment = 'AzureCloud'
    }

    $graphResource = switch ($AzureEnvironment) {
        'AzureUSGovernment' { 'https://graph.microsoft.us' }
        'AzureChinaCloud'   { 'https://microsoftgraph.chinacloudapi.cn' }
        default             { 'https://graph.microsoft.com' }
    }

    # Include the selected Az account in the cache key. Tenant-only caching can otherwise
    # return a token for account A after the operator changes the Az context to account B.
    $azAccountIdentity = ''
    $accountId = ''
    if ($azContext -and $azContext.PSObject.Properties['Account'] -and $azContext.Account) {
        $accountId = if ($azContext.Account.PSObject.Properties['Id']) { [string]$azContext.Account.Id } else { '' }
        $accountType = if ($azContext.Account.PSObject.Properties['Type']) { [string]$azContext.Account.Type } else { '' }
        $azAccountIdentity = "$accountType|$accountId"
    }
    $requestedScopes = @($Scopes | Where-Object { $_ } | Sort-Object -Unique)
    $scopeKey = $requestedScopes -join ','
    $cacheKey = "$graphResource|$(if ($TenantID) { $TenantID } else { '' })|$azAccountIdentity|$scopeKey"

    if (-not (Get-Variable -Name '_AZSCGraphTokenCache' -Scope Script -ErrorAction SilentlyContinue)) {
        Set-Variable -Name '_AZSCGraphTokenCache' -Scope Script -Value @{}
    }

    $now = [DateTimeOffset]::UtcNow
    $cache = $Script:_AZSCGraphTokenCache[$cacheKey]

    # Reuse cached token if still valid (more than 5 min from expiry)
    if ($cache -and $cache.ExpiresOn -gt $now.AddMinutes(5)) {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Reusing cached Graph token for tenant ' + $(if ($TenantID) { $TenantID } else { '(ambient)' }) + ' (expires ' + $cache.ExpiresOn.ToString('HH:mm:ss') + ' UTC)')
        return $cache.Headers
    }

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Acquiring new Microsoft Graph token for tenant ' + $(if ($TenantID) { $TenantID } else { '(ambient)' }))

    $plainToken = $null
    $expiresOn = $null
    $provider = $null
    try {
        $accountType = if ($azContext -and $azContext.Account -and $azContext.Account.PSObject.Properties['Type']) { [string]$azContext.Account.Type } else { '' }
        $applicationIdentity = $accountType -match '(?i)ServicePrincipal|ManagedService|ManagedIdentity'
        if ($requestedScopes.Count -gt 0 -and -not $applicationIdentity) {
            # Get-AzAccessToken can select a resource audience but cannot request delegated OAuth
            # scopes. Directory roles such as Global Reader therefore do not unlock granular
            # Graph surfaces (sign-ins, reports, access reviews, and role schedules) by themselves.
            # The SDK owns its public-client registration and token cache, so AzureScout neither
            # embeds an application identifier nor handles refresh tokens. UseDeviceCode works on
            # headless hosts and still lets the operator sign in as the same selected Az account.
            $mgEnvironment = switch ($AzureEnvironment) {
                'AzureUSGovernment' { 'USGov' }
                'AzureChinaCloud'   { 'China' }
                default             { 'Global' }
            }
            $mgContext = Get-MgContext -ErrorAction SilentlyContinue
            $contextScopes = @(
                if ($mgContext -and $mgContext.PSObject.Properties['Scopes']) { $mgContext.Scopes }
            )
            $missingScopes = @($requestedScopes | Where-Object { $contextScopes -notcontains $_ })
            $contextTenant = if ($mgContext -and $mgContext.PSObject.Properties['TenantId']) { [string]$mgContext.TenantId } else { '' }
            $contextAccount = if ($mgContext -and $mgContext.PSObject.Properties['Account']) { [string]$mgContext.Account } else { '' }
            $contextEnvironment = if ($mgContext -and $mgContext.PSObject.Properties['Environment']) { [string]$mgContext.Environment } else { '' }
            $sameTenant = (-not $TenantID -or $contextTenant -eq $TenantID)
            $sameAccount = (-not $accountId -or -not $contextAccount -or $contextAccount -eq $accountId)
            $sameEnvironment = (-not $contextEnvironment -or $contextEnvironment -eq $mgEnvironment)

            if (-not $mgContext -or $missingScopes.Count -gt 0 -or -not $sameTenant -or -not $sameAccount -or -not $sameEnvironment) {
                $connectArgs = @{
                    Scopes       = $requestedScopes
                    ContextScope = 'Process'
                    Environment  = $mgEnvironment
                    UseDeviceCode = $true
                    NoWelcome    = $true
                    ErrorAction  = 'Stop'
                }
                if ($TenantID) { $connectArgs.TenantId = $TenantID }
                Connect-MgGraph @connectArgs | Out-Null
                $mgContext = Get-MgContext -ErrorAction Stop
                $contextScopes = @($mgContext.Scopes)
                $contextAccount = [string]$mgContext.Account
            }

            $missingScopes = @($requestedScopes | Where-Object { $contextScopes -notcontains $_ })
            if ($missingScopes.Count -gt 0) {
                throw "Microsoft Graph authentication did not grant required delegated scopes: $($missingScopes -join ', ')."
            }
            if ($accountId -and $contextAccount -and $contextAccount -ne $accountId) {
                throw "Microsoft Graph authenticated as '$contextAccount', not the selected Azure PowerShell account '$accountId'."
            }

            # Invoke-AZSCGraphRequest recognizes this metadata-only marker and delegates the HTTP
            # call to Invoke-MgGraphRequest. No bearer or refresh token leaves the SDK cache.
            $headers = @{
                'X-AzureScout-GraphProvider' = 'Microsoft.Graph.Authentication'
                'X-AzureScout-GraphScopes'   = ($contextScopes -join ' ')
                'X-AzureScout-GraphAccount'  = $contextAccount
            }
            $expiresOn = $now.AddMinutes(30)
            $provider = 'Microsoft.Graph.Authentication device code'
        }
        else {
            # Service principals and managed identities receive application roles in their
            # resource token; delegated scopes and device code do not apply to them.
            $tokenArgs = @{
                ResourceUrl = $graphResource
                ErrorAction = 'Stop'
            }
            if ($TenantID) { $tokenArgs.TenantId = $TenantID }

            $tokenData = Get-AzAccessToken @tokenArgs
            if (-not $tokenData -or -not $tokenData.PSObject.Properties['Token'] -or $null -eq $tokenData.Token) {
                throw 'Get-AzAccessToken returned no token.'
            }

            if ($tokenData.Token -is [System.Security.SecureString]) {
                $tokenPointer = [IntPtr]::Zero
                try {
                    $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenData.Token)
                    $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
                }
                finally {
                    if ($tokenPointer -ne [IntPtr]::Zero) {
                        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
                    }
                }
            }
            else {
                # Older Az.Accounts versions returned a plain string.
                $plainToken = [string]$tokenData.Token
            }

            $expiresOn = if ($tokenData.PSObject.Properties['ExpiresOn'] -and $tokenData.ExpiresOn) {
                [DateTimeOffset]$tokenData.ExpiresOn
            }
            else {
                $now.AddMinutes(30)
            }
            $provider = 'Az PowerShell'
        }

        if ($provider -ne 'Microsoft.Graph.Authentication device code' -and [string]::IsNullOrWhiteSpace($plainToken)) {
            throw 'The authentication provider returned an empty token.'
        }
    }
    catch {
        $pathDescription = if ($requestedScopes.Count -gt 0 -and -not $applicationIdentity) { 'delegated Microsoft Graph authentication' } else { 'the selected Azure PowerShell context' }
        throw "Failed to acquire Microsoft Graph token from $pathDescription for tenant '$(if ($TenantID) { $TenantID } else { '(ambient)' })'. Azure CLI is not used. Error: $($_.Exception.Message)"
    }

    if ($provider -ne 'Microsoft.Graph.Authentication device code') {
        $headers = @{
            'Authorization' = "Bearer $plainToken"
            'Content-Type'  = 'application/json'
        }
        $plainToken = $null
    }

    $Script:_AZSCGraphTokenCache[$cacheKey] = [PSCustomObject]@{
        Headers   = $headers
        ExpiresOn = $expiresOn
        Provider  = $provider
    }

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Graph token acquired via $provider, expires " + $expiresOn.ToString('HH:mm:ss') + ' UTC')
    return $headers
}
