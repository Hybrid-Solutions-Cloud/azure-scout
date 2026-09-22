#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
    Azure Login Session Module for Azure Scout

.DESCRIPTION
    Authenticates to Azure using one of five methods (in priority order):
      1. Managed Identity  — triggered by -Automation flag (handled in Invoke-AzureScout)
      2. SPN + Certificate — -AppId, -CertificatePath, -CertificatePassword
      3. SPN + Secret      — -AppId, -Secret
      4. Device Code        — -DeviceLogin switch
      5. Current User       — default; reuses existing Az context or prompts interactive login

    Single-tenant per run. TenantID is required for SPN auth and strongly recommended
    for all other methods.

.PARAMETER AzureEnvironment
    Azure cloud environment. Default: AzureCloud.

.PARAMETER TenantID
    Target Azure AD tenant ID. Required for SPN methods; optional for interactive.

.PARAMETER DeviceLogin
    Use device-code authentication flow.

.PARAMETER ForceLogin
    Ignore an existing current-user context and authenticate again. The guided
    wizard uses this when the operator declines the displayed account/tenant.

.PARAMETER AppId
    Application (client) ID for service principal authentication.

.PARAMETER Secret
    Client secret for SPN + Secret auth. Requires -AppId and -TenantID.

.PARAMETER CertificatePath
    Path to PKCS#12 certificate file for SPN + Certificate auth.

.PARAMETER CertificatePassword
    Password protecting the certificate file. Passed as SecureString internally.

.LINK
    https://github.com/Hybrid-Solutions-Cloud/azure-scout

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
    Version: 1.0.0
    Authors: Claudio Merola, thisismydemo
#>
function Connect-AZSCLoginSession {
    # The -Secret / -CertificatePassword parameters arrive as plain strings from
    # CI env vars / headless callers, so ConvertTo-SecureString -AsPlainText is the
    # only way to build the SecureString that Connect-AzAccount requires. There is
    # no SecureString input path for these non-interactive service-principal flows.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Headless SPN/cert auth: secret arrives as a plain string arg; no SecureString input path exists.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CertificatePassword',
        Justification = 'Headless SPN/cert auth: arrives as a plain string from CI env vars / callers with no SecureString input path; changing the parameter type is a breaking change for every existing caller.')]
    [CmdletBinding()]
    param(
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string]$AzureEnvironment = 'AzureCloud',

        [string]$TenantID,

        [switch]$DeviceLogin,

        [switch]$ForceLogin,

        [string]$AppId,

        [string]$Secret,

        [string]$CertificatePath,

        [string]$CertificatePassword
    )

    $ErrorActionPreference = 'Stop'

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Starting Connect-AZSCLoginSession')

    # -----------------------------------------------------------
    # Priority 2: SPN + Certificate
    # -----------------------------------------------------------
    if ($AppId -and $CertificatePath) {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Auth method: SPN + Certificate')
        if (-not $TenantID) {
            throw 'TenantID is required for service principal authentication with certificate.'
        }

        $connectParams = @{
            ServicePrincipal = $true
            TenantId         = $TenantID
            ApplicationId    = $AppId
            CertificatePath  = $CertificatePath
            Environment      = $AzureEnvironment
        }
        if ($CertificatePassword) {
            $connectParams['CertificatePassword'] = ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force
        }

        Connect-AzAccount @connectParams | Out-Null
        Write-Host 'Authenticated via SPN + Certificate' -ForegroundColor Green
        return $TenantID
    }

    # -----------------------------------------------------------
    # Priority 3: SPN + Secret
    # -----------------------------------------------------------
    if ($AppId -and $Secret) {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Auth method: SPN + Secret')
        if (-not $TenantID) {
            throw 'TenantID is required for service principal authentication with secret.'
        }

        $secureSecret = ConvertTo-SecureString -String $Secret -AsPlainText -Force
        $credential   = [System.Management.Automation.PSCredential]::new($AppId, $secureSecret)

        Connect-AzAccount -ServicePrincipal -TenantId $TenantID -Credential $credential -Environment $AzureEnvironment | Out-Null
        Write-Host 'Authenticated via SPN + Secret' -ForegroundColor Green
        return $TenantID
    }

    # -----------------------------------------------------------
    # Priority 4: Device Code
    # -----------------------------------------------------------
    if ($DeviceLogin.IsPresent) {
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Auth method: Device Code')

        $deviceParams = @{
            UseDeviceAuthentication = $true
            Environment             = $AzureEnvironment
        }
        if ($TenantID) { $deviceParams['Tenant'] = $TenantID }

        Connect-AzAccount @deviceParams | Out-Null
        Write-Host 'Authenticated via Device Code' -ForegroundColor Green

        if (-not $TenantID) {
            $TenantID = (Get-AzContext).Tenant.Id
        }
        return $TenantID
    }

    # -----------------------------------------------------------
    # Priority 5: Current User (default)
    # -----------------------------------------------------------
    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Auth method: Current User (default)')

    $context = Get-AzContext -ErrorAction SilentlyContinue

    # If we have a valid context matching the target tenant, reuse it
    if (-not $ForceLogin.IsPresent -and $context -and $context.Account -and (-not $TenantID -or $context.Tenant.Id -eq $TenantID)) {
        $TenantID = $context.Tenant.Id
        Write-Host "Using existing Az context for tenant $TenantID" -ForegroundColor Green
        return $TenantID
    }

    # AB#7105 -- a user who already authenticated to several directly accessible tenants may
    # have an Az context cached for each one. Switch to that context before considering another
    # interactive login. This keeps the outer enterprise-tenant loop to one initial sign-in in
    # the common case while preserving the existing login path when no cached context exists.
    if (-not $ForceLogin.IsPresent -and $TenantID -and $context -and $context.Account) {
        try {
            $matchingContext = @(
                Get-AzContext -ListAvailable -ErrorAction Stop |
                    Where-Object {
                        $_.Tenant -and [string]$_.Tenant.Id -eq $TenantID -and
                        $_.Account -and [string]$_.Account.Id -eq [string]$context.Account.Id
                    }
            ) | Select-Object -First 1
            if ($matchingContext) {
                $null = Set-AzContext -Context $matchingContext -ErrorAction Stop
                Write-Host "Using cached Az context for tenant $TenantID" -ForegroundColor Green
                return $TenantID
            }
        }
        catch {
            Write-Verbose "Could not reuse a cached Az context for tenant '$TenantID': $($_.Exception.Message)"
        }
    }

    # Need to authenticate interactively
    Write-Host 'No valid Az context found — launching interactive login...' -ForegroundColor Yellow

    $interactiveParams = @{ Environment = $AzureEnvironment }
    if ($TenantID) { $interactiveParams['Tenant'] = $TenantID }

    # Temporarily disable LoginExperienceV2 if enabled (avoids subscription picker). The
    # authentication call runs exactly once, and a failed login must not leave global Az
    # configuration changed for the rest of the user's session.
    $restoreLoginExperienceV2 = $false
    try {
        try {
            $loginConfig = Get-AzConfig -LoginExperienceV2 -WarningAction SilentlyContinue -InformationAction SilentlyContinue
            if ($loginConfig.Value -eq 'On') {
                Update-AzConfig -LoginExperienceV2 Off -Scope Process -ErrorAction Stop | Out-Null
                $restoreLoginExperienceV2 = $true
            }
        }
        catch {
            Write-Verbose "Could not inspect or temporarily change LoginExperienceV2: $($_.Exception.Message)"
        }

        Connect-AzAccount @interactiveParams -ErrorAction Stop | Out-Null
    }
    finally {
        if ($restoreLoginExperienceV2) {
            try { Update-AzConfig -LoginExperienceV2 On -Scope Process -ErrorAction Stop | Out-Null }
            catch { Write-Warning "Interactive login completed, but LoginExperienceV2 could not be restored to On: $($_.Exception.Message)" }
        }
    }

    if (-not $TenantID) {
        $TenantID = (Get-AzContext).Tenant.Id
    }

    Write-Host "Authenticated interactively for tenant $TenantID" -ForegroundColor Green
    return $TenantID
}
