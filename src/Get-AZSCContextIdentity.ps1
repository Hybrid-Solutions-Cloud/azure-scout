#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AZSCAzureCliAccount {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $AzCommand = Get-Command az -ErrorAction SilentlyContinue
    if (-not $AzCommand) { return $null }

    try {
        $Json = & $AzCommand.Source account show --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $Json) { return $null }
        $Account = $Json | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            TenantId         = [string]$Account.tenantId
            TenantDisplayName = [string]$Account.tenantDisplayName
            UserName          = [string]$Account.user.name
        }
    }
    catch {
        return $null
    }
}

function Get-AZSCAzureCliTenant {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $AzCommand = Get-Command az -ErrorAction SilentlyContinue
    if (-not $AzCommand) { return @() }

    try {
        $Json = & $AzCommand.Source account list --all --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $Json) { return @() }
        $Subscriptions = @($Json | ConvertFrom-Json -ErrorAction Stop)
        return @(
            $Subscriptions |
                Where-Object { $_.tenantId } |
                Group-Object { [string]$_.tenantId } |
                ForEach-Object {
                    $First = @($_.Group)[0]
                    [pscustomobject]@{
                        Id   = [string]$First.tenantId
                        Name = [string]$First.tenantDisplayName
                    }
                } |
                Sort-Object Name, Id
        )
    }
    catch {
        return @()
    }
}

function Get-AZSCAccessibleTenant {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $Tenants = @()
    try {
        $Tenants = @(
            Get-AzTenant -ErrorAction Stop |
                ForEach-Object {
                    [pscustomobject]@{
                        Id   = [string]$_.Id
                        Name = [string]$_.Name
                    }
                }
        )
    }
    catch {
        $Tenants = @()
    }

    # Access-token contexts do not always carry a token Get-AzTenant can use.
    # Azure CLI retains tenant display names in its subscription cache, so use
    # that only as a fallback and still present tenants rather than subscriptions.
    if ($Tenants.Count -eq 0) {
        $Tenants = @(Get-AZSCAzureCliTenant)
    }

    return @(
        $Tenants |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Id) } |
            Group-Object { [string]$_.Id } |
            ForEach-Object { @($_.Group)[0] } |
            Sort-Object Name, Id
    )
}

function Resolve-AZSCContextIdentity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        $Context
    )

    $AccountId = if ($Context.PSObject.Properties['Account'] -and $Context.Account) {
        [string]$Context.Account.Id
    }
    else { '' }
    $TenantId = if ($Context.PSObject.Properties['Tenant'] -and $Context.Tenant) {
        [string]$Context.Tenant.Id
    }
    else { '' }

    $AccountDisplayName = $AccountId
    $TenantDisplayName = $TenantId
    $MatchingTenant = @(
        Get-AZSCAccessibleTenant | Where-Object { [string]$_.Id -eq $TenantId }
    ) | Select-Object -First 1
    if ($MatchingTenant -and -not [string]::IsNullOrWhiteSpace([string]$MatchingTenant.Name)) {
        $TenantDisplayName = [string]$MatchingTenant.Name
    }

    $ParsedAccountId = [guid]::Empty
    $AccountNeedsName = [string]::IsNullOrWhiteSpace($AccountDisplayName) -or
        [guid]::TryParse($AccountDisplayName, [ref]$ParsedAccountId)
    $TenantNeedsName = [string]::IsNullOrWhiteSpace($TenantDisplayName) -or $TenantDisplayName -eq $TenantId

    if ($AccountNeedsName -or $TenantNeedsName) {
        $CliAccount = Get-AZSCAzureCliAccount
        if ($CliAccount -and [string]$CliAccount.TenantId -eq $TenantId) {
            if ($AccountNeedsName -and -not [string]::IsNullOrWhiteSpace([string]$CliAccount.UserName)) {
                $AccountDisplayName = [string]$CliAccount.UserName
            }
            if ($TenantNeedsName -and -not [string]::IsNullOrWhiteSpace([string]$CliAccount.TenantDisplayName)) {
                $TenantDisplayName = [string]$CliAccount.TenantDisplayName
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($AccountDisplayName)) { $AccountDisplayName = 'unknown account' }
    if ([string]::IsNullOrWhiteSpace($TenantDisplayName)) { $TenantDisplayName = 'unknown tenant' }

    return [pscustomobject]@{
        AccountDisplayName = $AccountDisplayName
        TenantDisplayName  = $TenantDisplayName
        TenantId           = $TenantId
    }
}
