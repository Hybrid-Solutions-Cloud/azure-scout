<#
.Synopsis
    Acquire a Microsoft Graph bearer token via Azure CLI.

.DESCRIPTION
    Uses Azure CLI (az account get-access-token) to obtain a bearer token
    for Microsoft Graph API calls. Caches the token in a script-scope variable
    and refreshes automatically when within 5 minutes of expiry.

    Requires Azure CLI to be logged in ('az login'). Azure CLI automatically
    requests proper Graph API scopes during authentication, unlike Az PowerShell.

.PARAMETER TenantID
    Optional tenant ID to scope the token to. Without this, 'az account get-access-token'
    returns a token for whatever tenant Azure CLI's ambient context currently has active,
    which is not necessarily the tenant the caller is auditing or collecting against --
    on a multi-tenant/delegated identity (Lighthouse, GDAP, or simply an operator who is
    signed into several customer tenants) that can silently be the wrong tenant. Pass the
    same TenantID given to Invoke-AzureScout / Invoke-AZSCPermissionAudit to pin it.

.OUTPUTS
    [hashtable] Authorization headers ready for Invoke-RestMethod:
    @{ 'Authorization' = 'Bearer <token>'; 'Content-Type' = 'application/json' }

.LINK
    https://github.com/thisismydemo/azure-scout

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
    Version: 1.1.0
    Authors: thisismydemo
    Modified: 2026-02-24 - Changed from Get-AzAccessToken to Azure CLI for proper Graph scopes
    Modified: 2026-08-08 - AB#7100 -- Added -TenantID so the token targets the tenant being
              audited/collected instead of az CLI's ambient default; cache keyed per tenant so
              a run touching multiple tenants can't return one tenant's cached token for another.
#>
function Get-AZSCGraphToken {
    [CmdletBinding()]
    param(
        [string]$TenantID
    )

    # Cache key: empty string means "az CLI's ambient/default tenant", same as the old
    # single-slot cache. A distinct key per TenantID prevents a token minted for tenant A
    # from being handed back for a subsequent call scoped to tenant B.
    $cacheKey = if ($TenantID) { $TenantID } else { '' }

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

    try {
        # Use Azure CLI to get Graph token with proper scopes
        # Azure CLI device code authentication includes Graph API scopes by default
        $tenantArgs = @()
        if ($TenantID) { $tenantArgs = @('--tenant', $TenantID) }
        $azTokenJson = az account get-access-token --resource https://graph.microsoft.com @tenantArgs 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI failed to get Graph token. Ensure you are logged in with 'az login'. Error: $azTokenJson"
        }

        $tokenData = $azTokenJson | ConvertFrom-Json
        $plainToken = $tokenData.accessToken
        $expiresOn = [DateTimeOffset]::Parse($tokenData.expiresOn)

        $headers = @{
            'Authorization' = "Bearer $plainToken"
            'Content-Type'  = 'application/json'
        }

        # Cache for reuse, keyed per tenant
        $Script:_AZSCGraphTokenCache[$cacheKey] = [PSCustomObject]@{
            Headers   = $headers
            ExpiresOn = $expiresOn
        }

        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Graph token acquired via Azure CLI, expires ' + $expiresOn.ToString('HH:mm:ss') + ' UTC')

        return $headers
    }
    catch {
        $errorMessage = "Failed to acquire Microsoft Graph token. Ensure Azure CLI is logged in with 'az login' and has Graph API permissions. Error: $($_.Exception.Message)"
        Write-Warning $errorMessage
        throw $errorMessage
    }
}
