#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Lists every top-level resource in each subscription from Azure Resource Manager itself and
    returns the ones Resource Graph did not return.

.DESCRIPTION
    Discovery reads Azure Resource Graph, which indexes most but not every resource type, and can
    lag a new deployment by a short time. Resource Manager's own list
    (`GET /subscriptions/{id}/resources`) is the source of truth for top-level resources. Reading
    it once per subscription and comparing resource IDs means a resource of a type Resource Graph
    does not index is still discovered, with its name, type, location, SKU, kind, identity, tags
    and managed-by.

    The list does not return `properties`; a resource added here carries `properties = $null`
    and `AZSCSource = 'ArmResourceList'` so the report can say where it came from.

    Reads run 8 subscriptions at a time. A subscription whose list fails after retries is
    reported in `Health` as Unavailable, because the cross-check for it did not happen.

.PARAMETER SubscriptionIds
    Subscriptions to list.

.PARAMETER KnownIds
    Resource IDs already discovered (case-insensitive).

.PARAMETER ResourceGroups
    Optional resource-group filter, applied to the listed resources.

.PARAMETER TagKey
    Optional tag filter, applied to the listed resources (with -TagValue when given).

.OUTPUTS
    [pscustomobject] with Rows, Health, Operations, Listed and Subscriptions.
#>
function Get-ScoutArmResourceCrossCheck {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $SubscriptionIds,
        # Not Mandatory: PowerShell refuses an empty set for a mandatory parameter, and an empty
        # tenant has nothing discovered yet.
        [System.Collections.Generic.HashSet[string]] $KnownIds,
        [string[]] $ResourceGroups,
        [string] $TagKey,
        [string] $TagValue,
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
        [string] $AzureEnvironment = 'AzureCloud',
        [ValidateRange(1, 16)][int] $ThrottleLimit = 8
    )

    if ($null -eq $KnownIds) { $KnownIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
    $rows = [System.Collections.Generic.List[object]]::new()
    $health = [System.Collections.Generic.List[object]]::new()
    $operations = [System.Collections.Generic.List[object]]::new()
    $result = [pscustomobject]@{ Rows = $rows; Health = $health; Operations = $operations; Listed = 0; Subscriptions = 0 }

    $subscriptions = @($SubscriptionIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($subscriptions.Count -eq 0) { return $result }

    $managementHost = switch ($AzureEnvironment) {
        'AzureCloud' { 'https://management.azure.com' }
        'AzureUSGovernment' { 'https://management.usgovcloudapi.net' }
        'AzureChinaCloud' { 'https://management.chinacloudapi.cn' }
    }
    try {
        $token = Get-AzAccessToken -ResourceUrl ($managementHost + '/') -AsSecureString -WarningAction SilentlyContinue -ErrorAction Stop
        $authorization = 'Bearer ' + ($token.Token | ConvertFrom-SecureString -AsPlainText)
    }
    catch {
        $health.Add([pscustomobject]@{
                Dataset = 'Discovery: Azure Resource Manager resource list'
                Status = 'Unavailable'
                Reason = "Could not get an access token for Azure Resource Manager: $($_.Exception.Message)"
                ResourceTypes = @()
                Collectors = @()
            })
        return $result
    }

    # One subscription's full list, following nextLink, with retries for throttling, server
    # errors and dropped connections. Kept as text so the same code runs in parallel runspaces
    # and, when Invoke-RestMethod is a test stub that runspaces cannot see, in-process.
    $listOneSubscription = {
        param([string] $SubscriptionId, [string] $ManagementHost, [string] $Authorization)
            $subscriptionId = $SubscriptionId
            $uri = "$ManagementHost/subscriptions/$subscriptionId/resources?api-version=2021-04-01&`$top=1000"
            $items = [System.Collections.Generic.List[object]]::new()
            $failure = $null
            $started = Get-Date
            while ($uri) {
                $attempt = 0
                $page = $null
                while ($true) {
                    try {
                        $page = Invoke-RestMethod -Uri $uri -Method GET -Headers @{ Authorization = $Authorization } -TimeoutSec 120 -ErrorAction Stop
                        break
                    }
                    catch {
                        $attempt++
                        $status = 0
                        try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = 0 }
                        $transient = $status -in @(408, 429, 500, 502, 503, 504) -or
                            ($status -eq 0 -and [string]$_.Exception.Message -match '(?i)transport connection|forcibly closed|error occurred while sending|timed out|Timeout|canceled')
                        if ($transient -and $attempt -lt 4) {
                            Start-Sleep -Seconds ([Math]::Min(30, 5 * $attempt))
                            continue
                        }
                        $failure = if ($status) { "HTTP $status. $($_.Exception.Message)" } else { $_.Exception.Message }
                        break
                    }
                }
                if ($null -ne $failure) { break }
                foreach ($item in @($page.value)) { if ($null -ne $item) { $items.Add($item) } }
                $next = if ($page.PSObject.Properties['nextLink']) { [string]$page.nextLink } else { '' }
                $uri = if ([string]::IsNullOrWhiteSpace($next)) { $null } else { $next }
            }
            [pscustomobject]@{ SubscriptionId = $subscriptionId; Items = $items.ToArray(); Failure = $failure; Started = $started; Completed = Get-Date }
    }

    $restCommand = Get-Command Invoke-RestMethod -ErrorAction SilentlyContinue
    $listed = if ($restCommand -and $restCommand.CommandType -eq 'Cmdlet' -and $subscriptions.Count -gt 1) {
        $listText = $listOneSubscription.ToString()
        @($subscriptions | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                & ([scriptblock]::Create($using:listText)) $_ $using:managementHost $using:authorization
            })
    }
    else {
        @(foreach ($subscriptionId in $subscriptions) { & $listOneSubscription $subscriptionId $managementHost $authorization })
    }

    $rgFilter = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($group in @($ResourceGroups | Where-Object { $_ })) { $null = $rgFilter.Add([string]$group) }

    foreach ($entry in $listed) {
        $result.Subscriptions++
        $operations.Add([pscustomobject][ordered]@{
                Source = 'Azure Resource Manager'
                Dataset = 'Discovery: Azure Resource Manager resource list'
                Operation = 'GET /subscriptions/{id}/resources'
                Scope = 'Subscription'
                ScopeIds = @($entry.SubscriptionId)
                Status = if ($entry.Failure) { 'Failed' } elseif (@($entry.Items).Count -eq 0) { 'Empty' } else { 'Success' }
                Count = @($entry.Items).Count
                StartedAt = $entry.Started.ToString('o')
                CompletedAt = $entry.Completed.ToString('o')
            })
        if ($entry.Failure) {
            $health.Add([pscustomobject]@{
                    Dataset = "Discovery: Azure Resource Manager resource list [$($entry.SubscriptionId)]"
                    Status = 'Unavailable'
                    Reason = "Resources that Resource Graph does not index could not be checked for this subscription: $($entry.Failure)"
                    ResourceTypes = @()
                    Collectors = @()
                })
            continue
        }
        foreach ($item in @($entry.Items)) {
            $result.Listed++
            $id = [string]$item.id
            if ([string]::IsNullOrWhiteSpace($id) -or $KnownIds.Contains($id)) { continue }
            $resourceGroup = if ($id -match '(?i)/resourceGroups/([^/]+)') { $Matches[1] } else { $null }
            if ($rgFilter.Count -gt 0 -and -not ($resourceGroup -and $rgFilter.Contains($resourceGroup))) { continue }
            $tags = if ($item.PSObject.Properties['tags']) { $item.tags } else { $null }
            if ($TagKey) {
                $tagProperty = @(if ($tags) { $tags.PSObject.Properties | Where-Object Name -ieq $TagKey })
                if ($tagProperty.Count -eq 0) { continue }
                if ($TagValue -and [string]$tagProperty[0].Value -ine $TagValue) { continue }
            }
            $null = $KnownIds.Add($id)
            $value = { param($Name) if ($item.PSObject.Properties[$Name]) { $item.$Name } else { $null } }
            $rows.Add([pscustomobject][ordered]@{
                    id = $id
                    name = [string]$item.name
                    type = ([string]$item.type).ToLowerInvariant()
                    tenantId = $null
                    kind = & $value 'kind'
                    location = & $value 'location'
                    resourceGroup = if ($resourceGroup) { $resourceGroup.ToLowerInvariant() } else { $null }
                    subscriptionId = $entry.SubscriptionId
                    managedBy = & $value 'managedBy'
                    sku = & $value 'sku'
                    plan = & $value 'plan'
                    properties = $null
                    identity = & $value 'identity'
                    zones = & $value 'zones'
                    extendedLocation = & $value 'extendedLocation'
                    tags = $tags
                    AZSCSource = 'ArmResourceList'
                })
        }
    }
    return $result
}
