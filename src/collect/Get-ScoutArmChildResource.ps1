#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-ScoutDiagnosticOperation -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot '../Write-AZTIRunLog.ps1') }
if (-not (Get-Command Get-ScoutHttpFailure -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot '../Get-ScoutHttpFailure.ps1') }

<#
.SYNOPSIS
    Prefetch ARM child collections and service metadata consumed by inventory collectors.

.DESCRIPTION
    Moves supported per-parent ARM and metadata-only service calls out of collector row loops and
    into the collect phase.
    Application Insights Continuous Export and Work Item Config endpoints are deliberately not
    represented: Azure retired them, so querying either would produce a permanent failure rather
    than inventory data. The function is intentionally isolated in this change: Invoke-Collect
    does not call it yet, and no existing collector or definition is modified.

    Each returned row preserves the child payload's top-level properties and adds a stable
    synthetic resource contract:

      TYPE             AZSC/ARMChild/<collector name>
      PARENTID         resource id of the parent
      PARENTTYPE       Resource Graph type of the parent
      PARENTNAME       Resource Graph name of the parent
      PARENTLOCATION   Resource Graph location of the parent (AB#6802 -- a singleton child
                       carries no location of its own, and a consumer that needs one, like
                       Compute/AVDAzureLocal's Azure Local branch, has nowhere else to read it)
      subscriptionId   inherited from the parent
      RESOURCEGROUP    inherited from the parent
      AZSC             metadata object with Dataset, ParentId, ParentType, ParentName,
                       SourceType, EndpointType, LatestVersion and DeploymentCount

    Dataset identifies the future consuming definition one-to-one. LatestVersion is populated for
    MLDatasets and MLModels. EndpointType and DeploymentCount are populated for MLEndpoints.

    Eight datasets (AB#9300 phase 4, batch 2) read configuration that Resource Graph does not
    index, one ARM GET per parent: StorageBlobServiceProperties, StorageFileServiceProperties,
    SqlServerAuditing, SqlFailoverGroups, WebAppConfig, WebAppBasicAuth, EventHubGeoDr and
    RedisEnterpriseDatabases. Unlike every dataset above, their rows do NOT carry the raw
    response: each child is projected down to an explicit allow-list of scalar settings BEFORE it
    becomes a row (see $SafeChildPropertyPaths). The responses sit next to secrets -- a SQL
    auditing policy's storageAccountAccessKey, an App Service's app settings and connection
    strings, a failover group's partner server ids, an Event Hubs partner namespace -- and a row
    that never held them cannot leak them into a collect.json, a Discovery.json or a log.

    Calls are independently non-fatal. A failed parent/dataset call emits a warning and only that
    child collection is omitted; other parents and datasets continue. Input order, canonical
    dataset order, endpoint-type order, and service response order are preserved.

.PARAMETER Resources
    Resource Graph rows containing the parent workspaces/accounts/application groups.

.PARAMETER Dataset
    Optional subset of the supported dataset names. Defaults to All.

.PARAMETER CollectionHealth
    Optional caller-owned list that receives one health record per child dataset that could not
    be read. Health records are never written to the function's output pipeline, so partial
    successful inventory rows retain their established shape.

.PARAMETER SourceOperations
    Optional caller-owned list that receives one record per ARM request (dataset, parent, uri, status,
    count, reason, timing -- and the parent's resource id for the per-parent datasets).

.PARAMETER ThrottleLimit
    How many requests run at once for the datasets that are one independent GET per parent --
    ResourceDiagnosticSettings and the eight batch-2 datasets (default 8, 1-16). The requests are
    FETCHED concurrently and then APPLIED on the calling thread in input order, so rows, source
    operations, collection health and warnings are identical to a sequential run; only the clock
    differs. 1 runs everything sequentially in the caller's session.

.PARAMETER Execution
    Auto (default) runs those datasets in parallel when Invoke-AzRestMethod is the real Az cmdlet and
    a bearer token can be acquired from the current Az context (once per call, never logged);
    otherwise sequentially -- including whenever Invoke-AzRestMethod is a test stub, which a runspace
    cannot see. InProcess never parallelises. Parallel forces it (a test seam; see
    -ManagementEndpoint / -AccessToken).

.OUTPUTS
    PSCustomObject rows using the synthetic contract documented above.

.NOTES
    Proof-of-isolation implementation for Epic AB#5638. Integration into Invoke-Collect and
    conversion of the fourteen collectors are separate changes.
#>
function Get-ScoutArmChildResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources,

        [Parameter()]
        [ValidateSet(
            'All',
            'MLComputes',
            'MLDatasets',
            'MLDatastores',
            'MLEndpoints',
            'MLModels',
            'MLPipelines',
            'OpenAIDeployments',
            'SearchIndexes',
            'AVDApplications',
            'AppInsightsProactiveDetection',
            'LAWorkspaceLinkedServices',
            'LAWorkspaceSavedSearches',
            'LAWorkspaceTables',
            'SentinelDataConnectors',
            'SentinelIngestion',
            'StorageBlobContainers',
            'StorageFileShares',
            'StorageLifecyclePolicies',
            'StorageQueues',
            'StorageTables',
            'BackupInstances',
            'ResourceDiagnosticSettings',
            'ReservationUtilization',
            'AzureLocalVirtualMachineInstances',
            'StorageBlobServiceProperties',
            'StorageFileServiceProperties',
            'SqlServerAuditing',
            'SqlFailoverGroups',
            'WebAppConfig',
            'WebAppBasicAuth',
            'EventHubGeoDr',
            'RedisEnterpriseDatabases'
        )]
        [string[]]$Dataset = @('All'),

        [Parameter()]
        [AllowNull()]
        [System.Collections.IList]$CollectionHealth,

        [Parameter()]
        [AllowNull()]
        [System.Collections.IList]$SourceOperations,

        # How many per-parent GETs run at once for the datasets that are one independent GET per
        # parent (ResourceDiagnosticSettings and the eight AB#9300 phase 4 batch 2 datasets). 8 matches
        # Get-ScoutArmResourceCrossCheck. 1 runs everything sequentially in the caller's session.
        [Parameter()]
        [ValidateRange(1, 16)]
        [int]$ThrottleLimit = 8,

        # Auto (default): parallel when Invoke-AzRestMethod is the real Az cmdlet and a token can be
        # acquired, otherwise sequential -- a unit-test stub of Invoke-AzRestMethod is a function a
        # runspace cannot see, so a stubbed run stays sequential and its mocks keep working.
        # InProcess: never parallel. Parallel: parallel even when Invoke-AzRestMethod is a stub (the
        # requests go straight to the endpoint, so this needs -ManagementEndpoint and -AccessToken or
        # a signed-in Az context); a test seam, not an operator switch.
        [Parameter()]
        [ValidateSet('Auto', 'InProcess', 'Parallel')]
        [string]$Execution = 'Auto',

        # Test seam / pre-acquired credentials for the parallel transport. Both, or neither: when
        # neither is given the base URL and the bearer token come from the current Az context. The
        # token is held only for the sweep and is never written to any output, log or health record.
        [Parameter(DontShow)]
        [string]$ManagementEndpoint,

        [Parameter(DontShow)]
        [securestring]$AccessToken
    )

    $DatasetOrder = @(
        'MLComputes',
        'MLDatasets',
        'MLDatastores',
        'MLEndpoints',
        'MLModels',
        'MLPipelines',
        'OpenAIDeployments',
        'SearchIndexes',
        'AVDApplications',
        'AppInsightsProactiveDetection',
        'LAWorkspaceLinkedServices',
        'LAWorkspaceSavedSearches',
        'LAWorkspaceTables',
        'SentinelDataConnectors',
        'SentinelIngestion',
        'StorageBlobContainers',
        'StorageFileShares',
        'StorageLifecyclePolicies',
        'StorageQueues',
        'StorageTables',
        'BackupInstances',
        'ResourceDiagnosticSettings',
        'ReservationUtilization',
        'AzureLocalVirtualMachineInstances',
        'StorageBlobServiceProperties',
        'StorageFileServiceProperties',
        'SqlServerAuditing',
        'SqlFailoverGroups',
        'WebAppConfig',
        'WebAppBasicAuth',
        'EventHubGeoDr',
        'RedisEnterpriseDatabases'
    )

    # --- Diagnostic-settings parent scope (AB#6769) ---------------------------------------------
    #
    # Diagnostic settings can be attached to MOST Azure resource types, so the naive
    # implementation is one REST call per resource in the estate -- tens of thousands of calls on
    # a large tenant to fill one worksheet. That is not a trade worth making, so the sweep is
    # scoped to the types below: the ones whose platform logs are the evidence a security or
    # governance review actually asks for (who touched the vault, what the firewall allowed, what
    # the database did), and where the ABSENCE of a diagnostic setting is itself the finding.
    #
    # Deliberately NOT in this list, and this is where the saving comes from: virtual machines,
    # managed disks, network interfaces, snapshots and VM extensions. They are the highest-count
    # types in any real estate by an order of magnitude, and a VM's guest telemetry is configured
    # through the Azure Monitor agent and data collection rules -- which Scout already collects
    # as their own resource types -- not through a diagnostic setting on the VM. Including them
    # would multiply this sweep's call count by 10-50x and add no finding.
    #
    # Public IP addresses WERE in that exclusion and are now swept (AB#9300 phase 4, batch 2): the
    # Azure Well-Architected DDoS guidance asks for DDoS protection logs and metrics on every
    # public IP, so a public IP without a diagnostic setting is itself the finding. They are the
    # one high-count type here -- budget roughly one GET per public IP, which is usually tens to
    # a few hundred and not the tens of thousands that VMs and disks would be.
    #
    # Adding a type here costs one ARM GET per instance of it, per run. Weigh it that way.
    $DiagnosticSettingParentTypes = @(
        'microsoft.keyvault/vaults'
        'microsoft.storage/storageaccounts'
        'microsoft.sql/servers'
        'microsoft.sql/servers/databases'
        'microsoft.dbforpostgresql/flexibleservers'
        'microsoft.dbformysql/flexibleservers'
        'microsoft.documentdb/databaseaccounts'
        'microsoft.containerservice/managedclusters'
        'microsoft.web/sites'
        'microsoft.network/networksecuritygroups'
        'microsoft.network/applicationgateways'
        'microsoft.network/azurefirewalls'
        'microsoft.network/frontdoors'
        'microsoft.cdn/profiles'
        'microsoft.apimanagement/service'
        'microsoft.eventhub/namespaces'
        'microsoft.servicebus/namespaces'
        'microsoft.operationalinsights/workspaces'
        'microsoft.recoveryservices/vaults'
        'microsoft.automation/automationaccounts'
        # AB#9300 phase 4, batch 2 -- the types the Well-Architected service guides ask a
        # diagnostic setting on. Each is one GET per instance; none is a high-count type except
        # public IP addresses (see above).
        'microsoft.machinelearningservices/workspaces'
        'microsoft.search/searchservices'
        'microsoft.databricks/workspaces'
        'microsoft.sql/managedinstances'
        'microsoft.cache/redis'
        'microsoft.cache/redisenterprise'
        'microsoft.network/loadbalancers'
        'microsoft.network/publicipaddresses'
        'microsoft.network/virtualnetworkgateways'
        'microsoft.network/trafficmanagerprofiles'
        'microsoft.eventgrid/topics'
        'microsoft.insights/components'
        'microsoft.desktopvirtualization/hostpools'
        'microsoft.desktopvirtualization/workspaces'
    )

    # --- Allow-listed child settings (AB#9300 phase 4, batch 2) ----------------------------------
    #
    # For these eight datasets the row is built from THIS table, never from the raw response. Each
    # path is relative to the response's `properties` and names ONE scalar setting. Anything not
    # listed -- including every secret-bearing neighbour -- is dropped at the GET, before a row
    # exists, so nothing downstream (collect.json, Discovery.json, a transcript, a source-operation
    # log) can carry it. A listed path whose value turns out not to be a scalar is dropped too.
    #
    # What each response holds beside the allow-listed settings, and is therefore never read:
    #   SqlServerAuditing         storageAccountAccessKey, storageAccountSubscriptionId, storageEndpoint
    #   SqlFailoverGroups         partnerServers[].id (partner server resource ids), databases[] ids
    #   WebAppConfig              appSettings, connectionStrings, azureStorageAccounts,
    #                             publishingUsername, scmIpSecurityRestrictions, ipSecurityRestrictions
    #   EventHubGeoDr             partnerNamespace (the partner namespace's resource id), alternateName
    #   RedisEnterpriseDatabases  geoReplication.linkedDatabases[].id, modules[].args
    #   StorageBlobServiceProperties / StorageFileServiceProperties
    #                             cors origins, static-website document paths
    #
    # Three values are reduced to a count or a boolean rather than copied: a failover group's
    # partner servers and databases (counts), a Redis Enterprise database's linked databases (a
    # count), and a web app's health-check path (a boolean saying whether one is set).
    $SafeChildPropertyPaths = @{
        StorageBlobServiceProperties = @(
            'deleteRetentionPolicy.enabled', 'deleteRetentionPolicy.days',
            'containerDeleteRetentionPolicy.enabled', 'containerDeleteRetentionPolicy.days',
            'isVersioningEnabled', 'changeFeed.enabled', 'restorePolicy.enabled'
        )
        StorageFileServiceProperties = @(
            'shareDeleteRetentionPolicy.enabled', 'shareDeleteRetentionPolicy.days',
            'protocolSettings.smb.versions', 'protocolSettings.smb.channelEncryption',
            'protocolSettings.smb.authenticationMethods'
        )
        SqlServerAuditing = @('state', 'isAzureMonitorTargetEnabled')
        SqlFailoverGroups = @(
            'readWriteEndpoint.failoverPolicy', 'readWriteEndpoint.failoverWithDataLossGracePeriodMinutes',
            'readOnlyEndpoint.failoverPolicy', 'replicationRole', 'replicationState'
        )
        WebAppConfig = @(
            'ftpsState', 'alwaysOn', 'remoteDebuggingEnabled', 'http20Enabled',
            'minTlsVersion', 'scmMinTlsVersion'
        )
        WebAppBasicAuth = @('allow')
        EventHubGeoDr = @('provisioningState', 'role')
        RedisEnterpriseDatabases = @(
            'accessKeysAuthentication', 'clientProtocol',
            'persistence.aofEnabled', 'persistence.aofFrequency',
            'persistence.rdbEnabled', 'persistence.rdbFrequency'
        )
    }

    $Selected = if ($Dataset -contains 'All') {
        $DatasetOrder
    }
    else {
        @($DatasetOrder | Where-Object { $Dataset -contains $_ })
    }

    $FailedHealthDatasets = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    # One "not registered" note per dataset, subscription and provider, not one per resource.
    $NotRegisteredSeen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    function Get-ArmParentValue {
        param(
            [Parameter(Mandatory)]$InputObject,
            [Parameter(Mandatory)][string[]]$Name
        )

        foreach ($Candidate in $Name) {
            $Property = $InputObject.PSObject.Properties[$Candidate]
            if ($null -ne $Property) { return $Property.Value }
        }
        return $null
    }

    # --- One ARM GET = a FETCH and an APPLY (AB#9300 phase 4, batch 2 follow-up) -------------------
    #
    # Reading a child used to be one function that did everything inline: send the request, retry,
    # follow nextLink, record the source operation, add health, warn. That cannot run in a parallel
    # runspace, because the shared collections are not thread-safe and the module's helpers are not
    # visible there. So it is split in two and both halves are used by EVERY path:
    #
    #   FETCH ($FetchChildBlock)  Pure. Sends the request(s) for one path, retries, follows nextLink,
    #                             parses, and RETURNS everything it learned -- the content, one record
    #                             per page, and on failure the raw facts (status, message, response
    #                             body). It touches no shared state and calls only built-in commands
    #                             (plus Invoke-AzRestMethod in 'Az' mode), so the same text runs in the
    #                             caller's session or in a ForEach-Object -Parallel runspace.
    #   APPLY (Complete-ArmChildFetch)  Main thread only. Turns a fetch result into source operations,
    #                             collection health, warnings and the returned content, with the
    #                             one-per-dataset health de-duplication.
    #
    # Because the decisions (404 is empty, 400 not-registered is NotApplicable, everything else is a
    # failure) live in APPLY and are made in input order, a parallel sweep yields exactly the rows,
    # operations, health and warnings of a sequential one.
    #
    # Two transports. 'Az' sends with Invoke-AzRestMethod, as the sequential path always has. 'Direct'
    # sends with Invoke-WebRequest and a bearer token the caller acquired ONCE, because the Az SDK's
    # per-runspace module import costs more than a GET and a unit-test stub of Invoke-AzRestMethod is
    # invisible to a runspace. Invoke-WebRequest -SkipHttpErrorCheck returns the same StatusCode and
    # Content as the Az cmdlet does for an HTTP error, so both transports classify identically.
    $FetchChildBlock = {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$DatasetName,
            [ValidateSet('Az', 'Direct')][string]$Mode = 'Az',
            [string]$ManagementHost = '',
            [string]$Authorization = '',
            [int]$Index = 0
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Read by the helpers below (they are nested, so the analyzer cannot see the use).
        $fetchDataset = $DatasetName
        $fetchIndex = $Index

        function Get-FetchStatusCode {
            param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

            $ResponseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
            if ($ResponseProperty -and $null -ne $ResponseProperty.Value) {
                $StatusProperty = $ResponseProperty.Value.PSObject.Properties['StatusCode']
                if ($StatusProperty -and $null -ne $StatusProperty.Value) {
                    try { return [int]$StatusProperty.Value } catch { return $null }
                }
            }

            if ($ErrorRecord.Exception.Data -and $ErrorRecord.Exception.Data.Contains('StatusCode')) {
                try { return [int]$ErrorRecord.Exception.Data['StatusCode'] } catch { return $null }
            }

            $StatusMatch = [regex]::Match(
                [string]$ErrorRecord.Exception.Message,
                '(?i)(?:HTTP|status(?:\s+code)?)\D{0,20}(?<code>[1-5]\d{2})(?!\d)'
            )
            if ($StatusMatch.Success) { return [int]$StatusMatch.Groups['code'].Value }
            return $null
        }

        function Get-FetchApiVersion {
            param([string] $Uri)
            if ($Uri -match '(?i)[?&]api-version=([^&]+)') { return $Matches[1] }
            return $null
        }

        function ConvertTo-FetchText {
            param([AllowNull()]$Value)
            if ($Value -is [byte[]]) { return [System.Text.Encoding]::UTF8.GetString($Value) }
            return $Value
        }

        $startedAt = Get-Date
        $currentPath = $Path
        $pageOperations = [System.Collections.Generic.List[object]]::new()

        function Add-PageOperation {
            param([string] $Status, [int] $Count = 0)
            $pageOperations.Add([pscustomobject]@{
                    Uri         = $currentPath
                    Status      = $Status
                    Count       = $Count
                    CompletedAt = Get-Date
                })
        }

        function New-FetchResult {
            param([string] $Terminal, $Content = $null, $Failure = $null)
            [pscustomobject]@{
                Index          = $fetchIndex
                Terminal       = $Terminal
                Content        = $Content
                PageOperations = $pageOperations.ToArray()
                Failure        = $Failure
                StartedAt      = $startedAt
            }
        }

        function Set-FetchProvenance {
            param([AllowNull()]$Item, [string]$Uri, [datetime]$CollectedAt)
            if ($null -eq $Item) { return }
            $metadata = [pscustomobject][ordered]@{
                Source      = 'Azure Resource Manager'
                Dataset     = $fetchDataset
                Operation   = 'GET'
                Uri         = $Uri
                ApiVersion  = Get-FetchApiVersion -Uri $Uri
                CollectedAt = $CollectedAt.ToString('o')
            }
            $Item | Add-Member -NotePropertyName '__AZSCSource' -NotePropertyValue $metadata -Force
        }

        try {
            # ARM list endpoints may paginate even tiny-looking datasets. AB#7358's tenant
            # reconciliation exposed first-page-only handling while auditing child resources.
            # Follow nextLink here once for every ARM-child consumer instead of teaching each
            # dataset its own paging loop.
            $items = [System.Collections.Generic.List[object]]::new()
            $seenPaths = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            $isPaged = $false

            while ($currentPath) {
                if (-not $seenPaths.Add($currentPath)) {
                    throw "ARM returned a repeated nextLink '$currentPath'."
                }

                $isAbsolute = [uri]::IsWellFormedUriString($currentPath, [System.UriKind]::Absolute)
                # Invoke-AzRestMethod returns a PSHttpResponse whose StatusCode can be inspected.
                # Unlike PowerShell's Invoke-RestMethod, the Az.Accounts cmdlet does not expose
                # -SkipHttpErrorCheck (including supported Az.Accounts 5.5.2). Expected singleton
                # 404s are therefore classified from either the response or the caught exception.
                $restParameters = @{ Method = 'GET'; ErrorAction = 'Stop' }
                if ($isAbsolute) { $restParameters['Uri'] = $currentPath } else { $restParameters['Path'] = $currentPath }
                $requestUri = if ($isAbsolute) { $currentPath } else { $ManagementHost + $currentPath }

                # Retry a transient answer twice. There was no retry here at all: one dropped
                # connection ("An error occurred while sending the request", live 2026-11-23) lost
                # a storage account's containers and marked the run Partial.
                # Throttling (429) and server errors back off exponentially (1, 2, 4, 8 s) and honour
                # ARM's Retry-After header, capped at 60 s, over up to five attempts. With the sweep
                # running eight requests at once, the old 0.5/1 s retries could exhaust before a
                # per-subscription throttle window reopened (AB#9300).
                $maxTransportAttempts = 5
                $response = $null
                for ($transportAttempt = 1; $transportAttempt -le $maxTransportAttempts; $transportAttempt++) {
                    try {
                        $response = if ($Mode -eq 'Direct') {
                            Invoke-WebRequest -Uri $requestUri -Method GET -Headers @{ Authorization = $Authorization } `
                                -SkipHttpErrorCheck -TimeoutSec 120 -ErrorAction Stop
                        }
                        else {
                            Invoke-ScoutDiagnosticOperation -Operation { Invoke-AzRestMethod @restParameters }
                        }
                        $transientStatus = if ($null -ne $response -and $response.PSObject.Properties['StatusCode']) { [int]$response.StatusCode } else { 0 }
                        if ($transportAttempt -lt $maxTransportAttempts -and $transientStatus -in @(429, 500, 502, 503, 504)) {
                            $waitMs = 1000 * [Math]::Pow(2, $transportAttempt - 1)
                            $headers = if ($response.PSObject.Properties['Headers']) { $response.Headers } else { $null }
                            if ($null -ne $headers) {
                                $retryAfter = $null
                                try { $retryAfter = @($headers['Retry-After'])[0] } catch { $retryAfter = $null }
                                $retryAfterSeconds = 0
                                if ($retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$retryAfterSeconds) -and $retryAfterSeconds -gt 0) {
                                    $waitMs = [Math]::Max($waitMs, 1000 * $retryAfterSeconds)
                                }
                            }
                            Start-Sleep -Milliseconds ([int][Math]::Min(60000, $waitMs))
                            continue
                        }
                        break
                    }
                    catch {
                        if ($transportAttempt -lt $maxTransportAttempts -and [string]$_.Exception.Message -match '(?i)error occurred while sending the request|transport connection|forcibly closed|timed out|TaskCanceled|operation was canceled|connection (was )?(closed|reset|aborted)|No such host is known') {
                            Start-Sleep -Milliseconds ([int](1000 * [Math]::Pow(2, $transportAttempt - 1)))
                            continue
                        }
                        throw
                    }
                }
                if ($null -eq $response) { throw 'ARM returned no response.' }

                $status = $response.PSObject.Properties['StatusCode']
                if ($null -ne $status -and ([int]$status.Value -lt 200 -or [int]$status.Value -ge 300)) {
                    # Hand the raw facts back; the main thread builds the message (it owns the
                    # redaction helper) and decides what the status means.
                    $failedBody = if ($response.PSObject.Properties['Content']) { ConvertTo-FetchText -Value $response.Content } else { $null }
                    return New-FetchResult -Terminal 'Failed' -Failure ([pscustomobject]@{
                            Kind = 'Response'; StatusCode = [int]$status.Value; Message = $null; Content = $failedBody; Path = $currentPath
                        })
                }

                $contentProperty = $response.PSObject.Properties['Content']
                if ($null -eq $contentProperty -or $null -eq $contentProperty.Value) {
                    if ($isPaged) { throw 'ARM returned no content for a continuation page.' }
                    Add-PageOperation -Status 'Empty'
                    return New-FetchResult -Terminal 'Empty'
                }
                $content = ConvertTo-FetchText -Value $contentProperty.Value
                if ($content -is [string]) {
                    if ([string]::IsNullOrWhiteSpace($content)) {
                        if ($isPaged) { throw 'ARM returned empty content for a continuation page.' }
                        Add-PageOperation -Status 'Empty'
                        return New-FetchResult -Terminal 'Empty'
                    }
                    $content = $content | ConvertFrom-Json
                }

                # Bare arrays and singleton objects retain their exact historical shape. Only a
                # normal ARM list envelope (a `value` property) participates in pagination.
                $valueProperty = $content.PSObject.Properties['value']
                if ($null -eq $valueProperty) {
                    Set-FetchProvenance -Item $content -Uri $currentPath -CollectedAt (Get-Date)
                    Add-PageOperation -Status 'Success' -Count 1
                    return New-FetchResult -Terminal 'Content' -Content $content
                }
                $pageCount = 0
                $collectedAt = Get-Date
                foreach ($item in @($valueProperty.Value)) {
                    if ($null -ne $item) {
                        Set-FetchProvenance -Item $item -Uri $currentPath -CollectedAt $collectedAt
                        $items.Add($item)
                        $pageCount++
                    }
                }
                Add-PageOperation -Status $(if ($pageCount -eq 0) { 'Empty' } else { 'Success' }) -Count $pageCount

                $nextLinkProperty = $content.PSObject.Properties['nextLink']
                if ($nextLinkProperty -and -not [string]::IsNullOrWhiteSpace([string]$nextLinkProperty.Value)) {
                    $currentPath = [string]$nextLinkProperty.Value
                    $isPaged = $true
                    continue
                }

                if (-not $isPaged) { return New-FetchResult -Terminal 'Content' -Content $content }
                return New-FetchResult -Terminal 'Content' -Content ([pscustomobject]@{ value = @($items) })
            }
            # Unreachable for a non-empty path; keeps the contract total.
            return New-FetchResult -Terminal 'Empty'
        }
        catch {
            return New-FetchResult -Terminal 'Failed' -Failure ([pscustomobject]@{
                    Kind       = 'Exception'
                    StatusCode = Get-FetchStatusCode -ErrorRecord $_
                    Message    = [string]$_.Exception.Message
                    Content    = $null
                    Path       = $currentPath
                })
        }
    }

    function Get-ArmApiVersion {
        param([string] $Uri)
        if ($Uri -match '(?i)[?&]api-version=([^&]+)') { return $Matches[1] }
        return $null
    }

    function Write-ArmChildOperation {
        # Record one request in the caller's source-operation log and the run log.
        param(
            [Parameter(Mandatory)][string] $DatasetName,
            [Parameter(Mandatory)][string] $ParentName,
            [string] $ParentId = '',
            [string] $Uri,
            [string] $Status,
            [int] $Count = 0,
            [AllowNull()][string] $Reason,
            [datetime] $StartedAt = (Get-Date),
            [datetime] $CompletedAt = (Get-Date)
        )
        if (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level DEBUG -Message "ARM GET $Uri; dataset=$DatasetName; status=$Status; count=$Count; reason=$Reason"
        }
        if ($null -eq $SourceOperations) { return }
        $operation = [ordered]@{
            Source      = 'Azure Resource Manager'
            Dataset     = $DatasetName
            ParentName  = $ParentName
            Operation   = 'GET'
            Uri         = $Uri
            ApiVersion  = Get-ArmApiVersion -Uri $Uri
            Status      = $Status
            Count       = $Count
            Reason      = $Reason
            StartedAt   = $StartedAt.ToString('o')
            CompletedAt = $CompletedAt.ToString('o')
        }
        if (-not [string]::IsNullOrWhiteSpace($ParentId)) { $operation['ParentId'] = $ParentId }
        [void]$SourceOperations.Add([pscustomobject]$operation)
    }

    function Complete-ArmChildFetch {
        # The APPLY half. Main thread only: it owns $SourceOperations, $CollectionHealth and the
        # de-duplication sets, so none of them is ever touched from a runspace.
        param(
            [Parameter(Mandatory)]$Result,
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter(Mandatory)][string]$ParentName,
            [string]$ParentId = '',
            [switch]$NotFoundIsEmpty
        )

        $Operation = @{ DatasetName = $DatasetName; ParentName = $ParentName; ParentId = $ParentId; StartedAt = $Result.StartedAt }
        foreach ($Page in @($Result.PageOperations)) {
            Write-ArmChildOperation @Operation -Uri $Page.Uri -Status $Page.Status -Count $Page.Count -Reason $null -CompletedAt $Page.CompletedAt
        }
        if ($Result.Terminal -ne 'Failed') { return $Result.Content }

        $Failure = $Result.Failure
        $StatusCode = $Failure.StatusCode
        $CurrentPath = [string]$Failure.Path
        # A returned non-2xx response used to be thrown as an exception whose message is the
        # service's own summary; that message is rebuilt here so every branch below reads the same
        # text it always did.
        $Message = if ($Failure.Kind -eq 'Response') {
            (Get-ScoutHttpFailure -Response ([pscustomobject]@{ StatusCode = $Failure.StatusCode; Content = $Failure.Content })).Summary
        }
        else { [string]$Failure.Message }

        if ($DatasetName -eq 'SentinelDataConnectors' -and $StatusCode -eq 400 -and
            $Message -match 'is not onboarded to Microsoft Sentinel') {
            $reason = 'Not applicable: this workspace is not onboarded to Microsoft Sentinel.'
            Write-ArmChildOperation @Operation -Uri $CurrentPath -Status 'NotApplicable' -Reason $reason
            if ($null -ne $CollectionHealth) {
                [void]$CollectionHealth.Add([pscustomobject]@{
                    Dataset = $DatasetName; Status = 'NotAssessed'; Reason = $reason
                    ResourceTypes = @("AZSC/ARMChild/$DatasetName")
                    ResourceIds = @(($Path -split '/providers/Microsoft.SecurityInsights/', 2)[0])
                })
            }
            return $null
        }
        # A subscription that has not registered the provider (for example microsoft.insights
        # for diagnostic settings) cannot answer for ANY of its resources. That is a stated,
        # expected gap, not a failure: it used to log one warning per resource and mark the
        # whole dataset Unavailable, which made a run Partial for a provider nobody uses.
        if ($StatusCode -eq 400 -and $Message -match "(?i)SubscriptionNotRegistered|is not registered to use '?([A-Za-z0-9.]+)") {
            $provider = if ($Message -match "(?i)is not registered to use '?([A-Za-z0-9.]+)") { $Matches[1].TrimEnd('.') } else { 'the resource provider' }
            $subscriptionId = if ($Path -match '(?i)/subscriptions/([^/]+)') { $Matches[1] } else { '' }
            $reason = "Not assessed: subscription '$subscriptionId' is not registered for the $provider resource provider, so its $DatasetName cannot be read. Register the provider to collect it."
            Write-ArmChildOperation @Operation -Uri $CurrentPath -Status 'NotApplicable' -Reason $reason
            $HealthDatasetName = ([string]$DatasetName -split '\.', 2)[0]
            if ($NotRegisteredSeen.Add("$HealthDatasetName|$subscriptionId|$provider")) {
                if ($null -ne $CollectionHealth) {
                    [void]$CollectionHealth.Add([pscustomobject]@{
                            Dataset       = $HealthDatasetName
                            Operation     = $DatasetName
                            Status        = 'NotAssessed'
                            Reason        = $reason
                            ResourceTypes = @("AZSC/ARMChild/$HealthDatasetName")
                            ResourceIds   = @(if ($subscriptionId) { "/subscriptions/$subscriptionId" })
                        })
                }
                Write-Verbose "Get-ScoutArmChildResource: $reason"
            }
            return $null
        }
        if ($NotFoundIsEmpty -and $StatusCode -eq 404) {
            Write-ArmChildOperation @Operation -Uri $CurrentPath -Status 'Empty'
            return $null
        }
        Write-ArmChildOperation @Operation -Uri $CurrentPath -Status 'Failed' -Reason $Message

        # Version/deployment lookups are sub-operations of the owning dataset. Reporting a
        # synthetic type such as AZSC/ARMChild/MLModels.LatestVersion would match no collector
        # and could let an assessment score partial evidence. Collapse health ownership to
        # the public dataset while preserving the exact failed operation for diagnostics.
        $HealthDatasetName = ([string]$DatasetName -split '\.', 2)[0]
        if ($null -ne $CollectionHealth -and $FailedHealthDatasets.Add($HealthDatasetName)) {
            [void]$CollectionHealth.Add([pscustomobject]@{
                    Dataset       = $HealthDatasetName
                    Operation     = $DatasetName
                    Status        = 'Unavailable'
                    Reason        = "Parent '$ParentName' at '$Path': $Message"
                    ResourceTypes = @("AZSC/ARMChild/$HealthDatasetName")
                })
        }
        Write-Warning "Get-ScoutArmChildResource: '$DatasetName' failed for parent '$ParentName' at '$Path' -- skipping this child collection: $Message"
        return $null
    }

    function Get-ArmChildContent {
        # One GET, sequentially, in the caller's session: the original behaviour, and still what
        # every dataset that is not in $ParallelDatasets uses. A prefetched result (from the
        # parallel sweep) is applied exactly as a freshly fetched one would be.
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter(Mandatory)][string]$ParentName,
            # Resource id of the parent. Optional: when supplied it is written onto every source
            # operation, so a consumer (ConvertFrom-ScoutInventory) can tell which PARENT a
            # per-parent GET covered without parsing the request path.
            [string]$ParentId = '',
            [switch]$NotFoundIsEmpty,
            [AllowNull()]$Prefetched = $null
        )

        $Result = if ($null -ne $Prefetched) { $Prefetched } else { & $FetchChildBlock -Path $Path -DatasetName $DatasetName -Mode 'Az' }
        return Complete-ArmChildFetch -Result $Result -Path $Path -DatasetName $DatasetName -ParentName $ParentName `
            -ParentId $ParentId -NotFoundIsEmpty:$NotFoundIsEmpty
    }

    function Test-StorageServiceSupported {
        param(
            [Parameter(Mandatory)]$Parent,
            [Parameter(Mandatory)][ValidateSet('Blob', 'File', 'Queue', 'Table')][string]$Service
        )

        $Kind = [string](Get-ArmParentValue -InputObject $Parent -Name @('kind', 'KIND'))
        if ([string]::IsNullOrWhiteSpace($Kind)) { return $true }
        switch ($Service) {
            'Blob'  { return $Kind -in @('Storage', 'StorageV2', 'BlobStorage', 'BlockBlobStorage') }
            'File'  { return $Kind -in @('Storage', 'StorageV2', 'FileStorage') }
            'Queue' { return $Kind -in @('Storage', 'StorageV2') }
            'Table' { return $Kind -in @('Storage', 'StorageV2') }
        }
    }

    function Get-ArmChildItemSet {
        param([AllowNull()]$Content)

        if ($null -eq $Content) { return @() }
        $ValueProperty = $Content.PSObject.Properties['value']
        if ($null -ne $ValueProperty) { return @($ValueProperty.Value) }
        return @($Content)
    }

    function ConvertTo-ArmChildRow {
        param(
            [Parameter(Mandatory)]$Child,
            [Parameter(Mandatory)]$Parent,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter()][AllowNull()][string]$EndpointType,
            [Parameter()][AllowNull()]$LatestVersion,
            [Parameter()][AllowNull()][Nullable[int]]$DeploymentCount
        )

        $ParentId = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
        $ParentType = [string](Get-ArmParentValue -InputObject $Parent -Name @('type', 'TYPE'))
        $ParentName = [string](Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
        $ParentLocation = Get-ArmParentValue -InputObject $Parent -Name @('location', 'LOCATION')
        $SubscriptionId = Get-ArmParentValue -InputObject $Parent -Name @('subscriptionId', 'SubscriptionId')
        $ResourceGroup = Get-ArmParentValue -InputObject $Parent -Name @('resourceGroup', 'RESOURCEGROUP')

        $SourceType = $null
        $SourceTypeProperty = $Child.PSObject.Properties['type']
        if ($null -ne $SourceTypeProperty) { $SourceType = $SourceTypeProperty.Value }
        if ([string]::IsNullOrWhiteSpace([string]$SourceType)) {
            # Several legacy management endpoints return configuration objects without a type.
            # Preserve a useful provenance value by falling back to the resource type queried.
            $SourceType = $ParentType
        }

        $Reserved = @(
            'TYPE', 'PARENTID', 'PARENTTYPE', 'PARENTNAME',
            'subscriptionId', 'RESOURCEGROUP', 'AZSC', '__AZSCSource'
        )
        $Row = [ordered]@{}
        foreach ($Property in $Child.PSObject.Properties) {
            if ($Reserved -contains $Property.Name) { continue }
            $Row[$Property.Name] = $Property.Value
        }

        $Row['TYPE'] = "AZSC/ARMChild/$DatasetName"
        $Row['PARENTID'] = $ParentId
        $Row['PARENTTYPE'] = $ParentType
        $Row['PARENTNAME'] = $ParentName
        $Row['PARENTLOCATION'] = $ParentLocation
        $Row['subscriptionId'] = $SubscriptionId
        $Row['RESOURCEGROUP'] = $ResourceGroup
        $sourceMetadata = if ($Child.PSObject.Properties['__AZSCSource']) { $Child.__AZSCSource } else { $null }
        $Row['AZSC'] = [PSCustomObject][ordered]@{
            Source          = if ($sourceMetadata) { $sourceMetadata.Source } else { 'Azure Resource Manager' }
            Dataset         = $DatasetName
            Operation       = if ($sourceMetadata) { $sourceMetadata.Operation } else { 'GET' }
            Uri             = if ($sourceMetadata) { $sourceMetadata.Uri } else { $null }
            ApiVersion      = if ($sourceMetadata) { $sourceMetadata.ApiVersion } else { $null }
            CollectedAt     = if ($sourceMetadata) { $sourceMetadata.CollectedAt } else { $null }
            ParentId        = $ParentId
            ParentType      = $ParentType
            ParentName      = $ParentName
            SourceType      = $SourceType
            EndpointType    = $EndpointType
            LatestVersion   = $LatestVersion
            DeploymentCount = $DeploymentCount
        }

        return [PSCustomObject]$Row
    }

    function Get-ArmPathValue {
        # Walk a dotted path of property names. Found is $false when ANY segment is absent, which
        # is how "the service did not return this setting" is kept apart from "returned null".
        param([AllowNull()]$InputObject, [Parameter(Mandatory)][string]$Path)

        $Current = $InputObject
        foreach ($Segment in $Path.Split('.')) {
            if ($null -eq $Current) { return [pscustomobject]@{ Found = $false; Value = $null } }
            $Property = $Current.PSObject.Properties[$Segment]
            if ($null -eq $Property) { return [pscustomobject]@{ Found = $false; Value = $null } }
            $Current = $Property.Value
        }
        return [pscustomobject]@{ Found = $true; Value = $Current }
    }

    function ConvertTo-ArmPlainObject {
        param([AllowNull()]$Node)

        if ($Node -is [System.Collections.IDictionary]) {
            $Plain = [ordered]@{}
            foreach ($Key in $Node.Keys) { $Plain[$Key] = ConvertTo-ArmPlainObject -Node $Node[$Key] }
            return [pscustomobject]$Plain
        }
        return $Node
    }

    function ConvertTo-ArmSafeChild {
        # Reduce one child response to the allow-listed scalar settings for its dataset (see
        # $SafeChildPropertyPaths) plus id/name/type and the request's source metadata. The raw
        # `properties` bag is never copied, only read.
        param(
            [Parameter(Mandatory)]$Child,
            [Parameter(Mandatory)][string]$DatasetName,
            [hashtable]$Extra
        )

        $RawProperties = Get-ArmParentValue -InputObject $Child -Name @('properties')
        $Tree = [ordered]@{}
        foreach ($Path in $SafeChildPropertyPaths[$DatasetName]) {
            $Found = Get-ArmPathValue -InputObject $RawProperties -Path $Path
            if (-not $Found.Found) { continue }
            $Value = $Found.Value
            $IsScalar = $Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or
                $Value -is [double] -or $Value -is [decimal]
            if (-not $IsScalar) { continue }
            $Segments = $Path.Split('.')
            $Node = $Tree
            for ($Index = 0; $Index -lt $Segments.Count - 1; $Index++) {
                if (-not $Node.Contains($Segments[$Index])) { $Node[$Segments[$Index]] = [ordered]@{} }
                $Node = $Node[$Segments[$Index]]
            }
            $Node[$Segments[-1]] = $Value
        }

        # Reductions: a count or a boolean stands in for a value that must not be carried.
        switch ($DatasetName) {
            'SqlFailoverGroups' {
                foreach ($Pair in @(@('partnerServers', 'partnerServerCount'), @('databases', 'databaseCount'))) {
                    $Found = Get-ArmPathValue -InputObject $RawProperties -Path $Pair[0]
                    $Tree[$Pair[1]] = if ($Found.Found -and $null -ne $Found.Value) { @($Found.Value).Count } else { 0 }
                }
            }
            'WebAppConfig' {
                $Found = Get-ArmPathValue -InputObject $RawProperties -Path 'healthCheckPath'
                $Tree['healthCheckPathSet'] = $Found.Found -and -not [string]::IsNullOrWhiteSpace([string]$Found.Value)
            }
            'RedisEnterpriseDatabases' {
                $Found = Get-ArmPathValue -InputObject $RawProperties -Path 'geoReplication.linkedDatabases'
                if (-not $Tree.Contains('geoReplication')) { $Tree['geoReplication'] = [ordered]@{} }
                $Tree['geoReplication']['linkedDatabaseCount'] = if ($Found.Found -and $null -ne $Found.Value) { @($Found.Value).Count } else { 0 }
            }
        }
        if ($null -ne $Extra) { foreach ($Key in $Extra.Keys) { $Tree[$Key] = $Extra[$Key] } }

        $Safe = [ordered]@{}
        foreach ($Name in @('id', 'name', 'type')) {
            $Found = Get-ArmPathValue -InputObject $Child -Path $Name
            if ($Found.Found) { $Safe[$Name] = $Found.Value }
        }
        $Safe['properties'] = ConvertTo-ArmPlainObject -Node $Tree
        $SafeChild = [pscustomobject]$Safe
        $SourceMetadata = Get-ArmParentValue -InputObject $Child -Name @('__AZSCSource')
        if ($null -ne $SourceMetadata) {
            $SafeChild | Add-Member -NotePropertyName '__AZSCSource' -NotePropertyValue $SourceMetadata -Force
        }
        return $SafeChild
    }

    $MachineLearningParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.machinelearningservices/workspaces' -and
        (Get-ArmParentValue -InputObject $_ -Name @('kind', 'KIND')) -notin @('Hub', 'Project')
    })
    $OpenAiParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.cognitiveservices/accounts' -and
        (Get-ArmParentValue -InputObject $_ -Name @('kind', 'KIND')) -ieq 'OpenAI'
    })
    $SearchParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.search/searchservices'
    })
    $AvdParents = @($Resources | Where-Object {
        $ParentType = Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')
        $ParentProperties = Get-ArmParentValue -InputObject $_ -Name @('properties', 'PROPERTIES')
        $ApplicationGroupType = if ($null -ne $ParentProperties) {
            Get-ArmParentValue -InputObject $ParentProperties -Name @('applicationGroupType', 'APPLICATIONGROUPTYPE')
        }
        $ParentType -ieq 'microsoft.desktopvirtualization/applicationgroups' -and
            $ApplicationGroupType -ieq 'RemoteApp'
    })
    $AppInsightsParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.insights/components'
    })
    $LogAnalyticsParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.operationalinsights/workspaces'
    })
    $StorageAccountParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.storage/storageaccounts'
    })
    $BackupVaultParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.dataprotection/backupvaults'
    })
    $ReservationParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.capacity/reservationorders/reservations'
    })
    $DiagnosticSettingParents = @($Resources | Where-Object {
        $DiagnosticSettingParentTypes -contains [string](Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE'))
    })
    # AB#6802. Every Arc-enabled server that is actually an Azure Local guest carries this
    # extension resource; every other Arc server (a bare-metal or VMware/SCVMM Arc machine) does
    # not, and the per-machine GET below degrades that absence to a non-fatal 404 -- the same
    # singleton pattern StorageLifecyclePolicies already uses. No `kind`/`vmId` pre-filter is
    # applied because Microsoft.HybridCompute/machines does not reliably expose which platform
    # provisioned it; the ARM response itself is the only trustworthy signal.
    $HybridComputeMachineParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.hybridcompute/machines'
    })
    # AB#9300 phase 4, batch 2.
    $SqlServerParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.sql/servers'
    })
    $WebSiteParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.web/sites'
    })
    # Geo-disaster recovery is not offered on the Basic tier (Microsoft Learn, "Compare Azure Event
    # Hubs tiers"), so a Basic namespace is not asked. A namespace whose row carries no SKU is
    # asked: absence of evidence is not a reason to skip the question.
    $EventHubNamespaceParents = @($Resources | Where-Object {
        $IsNamespace = (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.eventhub/namespaces'
        if (-not $IsNamespace) { return $false }
        $Sku = Get-ArmParentValue -InputObject $_ -Name @('sku', 'SKU')
        $SkuName = if ($null -ne $Sku) { [string](Get-ArmParentValue -InputObject $Sku -Name @('name', 'NAME')) } else { '' }
        $SkuName -ine 'Basic'
    })
    $RedisEnterpriseParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.cache/redisenterprise'
    })

    # --- The per-parent datasets: build the work, then fetch it (in parallel when it pays) ---------
    #
    # Nine datasets are ONE independent GET per parent (two for WebAppBasicAuth), with no GET
    # depending on another's answer: ResourceDiagnosticSettings and the eight AB#9300 phase 4 batch 2
    # datasets. They are the long pole of a sweep -- one request per storage account, per web app, per
    # public IP -- and sequentially they cost about 0.6 s each, so a real estate paid minutes for them.
    # Their requests are therefore built up front as a flat work list, fetched up to $ThrottleLimit at
    # a time in ONE batch for the whole sweep, and then APPLIED below in dataset order, work-item
    # order. The fetch is the only thing that runs concurrently; every row, source operation, health
    # record and warning is produced by the single-threaded apply, in the order a sequential sweep
    # would have produced them, so the two modes are indistinguishable except for the clock.
    #
    # The other datasets (ML, Sentinel, AVD, Storage containers/queues/tables, Backup, Reservations,
    # Azure Local) stay sequential on purpose: several make a dependent second call per child (an ML
    # dataset's latest version, an endpoint's deployments), and none is large.
    $ParallelDatasets = @(
        'ResourceDiagnosticSettings',
        'StorageBlobServiceProperties',
        'StorageFileServiceProperties',
        'SqlServerAuditing',
        'SqlFailoverGroups',
        'WebAppConfig',
        'WebAppBasicAuth',
        'EventHubGeoDr',
        'RedisEnterpriseDatabases'
    )

    function Get-ArmWorkItem {
        # The requests one dataset makes, one item per GET, in the order a sequential sweep makes them.
        #
        # ResourceDiagnosticSettings (AB#6769) -- WHY THIS IS A REST CALL AND NOT A RESOURCE GRAPH ROW.
        # `microsoft.insights/diagnosticsettings` is an ARM EXTENSION resource: it has no existence of
        # its own, only an attachment to another resource's id, and Resource Graph indexes it in no
        # table. Monitor/ResourceDiagnosticSettings declared that type and read the `resources` table,
        # so it returned zero rows in every tenant at every permission level. The only read that exists
        # is per parent:
        #
        #   GET {resourceId}/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview
        #
        # 2021-05-01-preview is the current version and the one AVM pins; it is the first to carry
        # `marketplacePartnerId`, which the worksheet's "Destination: Partner" column reads. Control
        # plane, read-only -- `Microsoft.Insights/diagnosticSettings/read`, which Reader holds. Nothing
        # here reads a log, only where logs are sent. A parent with no diagnostic setting returns an
        # empty `value` array, which produces no row -- and that absence IS the finding the worksheet
        # exists to show. See $DiagnosticSettingParentTypes for exactly which parents are swept.
        #
        # The other eight (AB#9300 phase 4, batch 2) are one ARM GET per parent each (two for
        # WebAppBasicAuth), all control plane and read-only -- the `*/read` operation each names is held
        # by Reader. They exist because the Azure Well-Architected service guides check settings that
        # live on a child resource or in a property Resource Graph omits: whether blob soft delete is
        # on, whether SQL auditing is enabled, whether FTP basic auth is allowed, whether an Event Hubs
        # namespace is paired.
        #
        # Every one of those rows is built from the allow-list in $SafeChildPropertyPaths, not from the
        # raw response -- see that table for the secrets each response sits next to and why they never
        # reach a row. A singleton that returns 404 is ordinary empty data (-NotFoundIsEmpty); a list
        # that returns no items is ordinary empty data too, and for the two per-parent summaries
        # (failover groups, geo-DR) that EMPTY answer is the finding, so ConvertFrom-ScoutInventory
        # reads the source operation's Status rather than the absence of a row.
        #
        # API versions are the oldest GA version that carries every allow-listed property and is already
        # live in every cloud, not the newest -- the newest takes weeks to reach sovereign clouds, and
        # nothing read here changed between them. Storage reuses the 2023-05-01 the other storage
        # datasets pin; both it and 2026-09-01 were checked live against a public-cloud estate and
        # return the same allow-listed settings.
        #
        #   StorageBlobServiceProperties  Microsoft.Storage/storageAccounts/blobServices/default   2023-05-01
        #   StorageFileServiceProperties  Microsoft.Storage/storageAccounts/fileServices/default   2023-05-01
        #   SqlServerAuditing             Microsoft.Sql/servers/auditingSettings/default           2021-11-01
        #   SqlFailoverGroups             Microsoft.Sql/servers/failoverGroups                     2021-11-01
        #   WebAppConfig                  Microsoft.Web/sites/config/web                           2022-09-01
        #   WebAppBasicAuth               Microsoft.Web/sites/basicPublishingCredentialsPolicies   2022-09-01
        #   EventHubGeoDr                 Microsoft.EventHub/namespaces/disasterRecoveryConfigs    2021-11-01
        #   RedisEnterpriseDatabases      Microsoft.Cache/redisEnterprise/databases                2025-04-01
        #
        # Redis Enterprise is the exception to "oldest": accessKeysAuthentication first appears in the
        # GA 2025-04-01 version (it was preview before), and it is the setting that dataset exists to
        # read; an older version would return the database without it.
        #
        # A storage account is asked only about services its kind has. A FileStorage account has no
        # blob service and answers 400 FeatureNotSupportedForAccount (seen live), which would be a
        # warning and an Unavailable dataset for something that is not a failure.
        param([Parameter(Mandatory)][string]$DatasetName)

        $Specs = @(switch ($DatasetName) {
            'ResourceDiagnosticSettings' {
                foreach ($Parent in $DiagnosticSettingParents) {
                    @{ Parent = $Parent; Suffix = '/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview'; NotFoundIsEmpty = $false }
                }
            }
            'StorageBlobServiceProperties' {
                foreach ($Parent in $StorageAccountParents) {
                    if (-not (Test-StorageServiceSupported -Parent $Parent -Service Blob)) { continue }
                    @{ Parent = $Parent; Suffix = '/blobServices/default?api-version=2023-05-01'; NotFoundIsEmpty = $true }
                }
            }
            'StorageFileServiceProperties' {
                foreach ($Parent in $StorageAccountParents) {
                    if (-not (Test-StorageServiceSupported -Parent $Parent -Service File)) { continue }
                    @{ Parent = $Parent; Suffix = '/fileServices/default?api-version=2023-05-01'; NotFoundIsEmpty = $true }
                }
            }
            'SqlServerAuditing' {
                foreach ($Parent in $SqlServerParents) {
                    @{ Parent = $Parent; Suffix = '/auditingSettings/default?api-version=2021-11-01'; NotFoundIsEmpty = $true }
                }
            }
            'SqlFailoverGroups' {
                foreach ($Parent in $SqlServerParents) {
                    @{ Parent = $Parent; Suffix = '/failoverGroups?api-version=2021-11-01'; NotFoundIsEmpty = $true }
                }
            }
            'WebAppConfig' {
                foreach ($Parent in $WebSiteParents) {
                    @{ Parent = $Parent; Suffix = '/config/web?api-version=2022-09-01'; NotFoundIsEmpty = $true }
                }
            }
            'WebAppBasicAuth' {
                # Two singletons per site, `ftp` and `scm`. The policy name is stamped onto the row
                # (properties.policy) because a web app's response does not reliably put the short
                # name in `name`.
                foreach ($Parent in $WebSiteParents) {
                    foreach ($Policy in @('ftp', 'scm')) {
                        @{ Parent = $Parent; Suffix = "/basicPublishingCredentialsPolicies/$Policy`?api-version=2022-09-01"; NotFoundIsEmpty = $true; Extra = @{ policy = $Policy } }
                    }
                }
            }
            'EventHubGeoDr' {
                foreach ($Parent in $EventHubNamespaceParents) {
                    @{ Parent = $Parent; Suffix = '/disasterRecoveryConfigs?api-version=2021-11-01'; NotFoundIsEmpty = $true }
                }
            }
            'RedisEnterpriseDatabases' {
                foreach ($Parent in $RedisEnterpriseParents) {
                    @{ Parent = $Parent; Suffix = '/databases?api-version=2025-04-01'; NotFoundIsEmpty = $true }
                }
            }
        })

        foreach ($Spec in $Specs) {
            $Base = [string](Get-ArmParentValue -InputObject $Spec.Parent -Name @('id', 'ID'))
            [pscustomobject]@{
                Index           = -1
                Dataset         = $DatasetName
                Parent          = $Spec.Parent
                ParentId        = $Base
                ParentName      = [string](Get-ArmParentValue -InputObject $Spec.Parent -Name @('name', 'NAME'))
                Path            = "$Base$($Spec.Suffix)"
                NotFoundIsEmpty = [bool]$Spec.NotFoundIsEmpty
                Extra           = if ($Spec.ContainsKey('Extra')) { $Spec.Extra } else { $null }
            }
        }
    }

    # Build every selected per-parent dataset's work list and number it globally, in sweep order.
    $WorkItems = @{}
    $AllWorkItems = [System.Collections.Generic.List[object]]::new()
    foreach ($ParallelDatasetName in @($Selected | Where-Object { $ParallelDatasets -contains $_ })) {
        $DatasetItems = @(Get-ArmWorkItem -DatasetName $ParallelDatasetName)
        foreach ($WorkItem in $DatasetItems) {
            $WorkItem.Index = $AllWorkItems.Count
            $AllWorkItems.Add($WorkItem)
        }
        $WorkItems[$ParallelDatasetName] = $DatasetItems
    }

    # Index -> fetch result, for the work the parallel batch already fetched. Anything not in here is
    # fetched sequentially at apply time, so a runspace that failed to answer costs nothing but time.
    $Prefetched = @{}

    $SuppliedEndpoint = $ManagementEndpoint
    $SuppliedToken = $AccessToken

    function Resolve-ArmParallelAuthorization {
        # The base URL and bearer header for the parallel transport, or $null when there is no way
        # to build them (no Az context, no token) -- in which case the sweep simply runs sequentially.
        # The token is acquired HERE, once, on the main thread, and handed to the runspaces as a
        # string; it is never written to a log, a record or a message.
        if (-not [string]::IsNullOrWhiteSpace($SuppliedEndpoint) -and $null -ne $SuppliedToken) {
            return [pscustomobject]@{
                ManagementHost = $SuppliedEndpoint.TrimEnd('/')
                Authorization  = 'Bearer ' + ($SuppliedToken | ConvertFrom-SecureString -AsPlainText)
            }
        }
        try {
            $Context = Get-AzContext -ErrorAction Stop
            if ($null -eq $Context -or $null -eq $Context.Environment -or [string]::IsNullOrWhiteSpace([string]$Context.Environment.ResourceManagerUrl)) {
                Write-Verbose 'Get-ScoutArmChildResource: no Az context with a Resource Manager endpoint; fetching sequentially.'
                return $null
            }
            $ManagementHost = ([string]$Context.Environment.ResourceManagerUrl).TrimEnd('/')
            $Token = Get-AzAccessToken -ResourceUrl ($ManagementHost + '/') -AsSecureString -WarningAction SilentlyContinue -ErrorAction Stop
            return [pscustomobject]@{
                ManagementHost = $ManagementHost
                Authorization  = 'Bearer ' + ($Token.Token | ConvertFrom-SecureString -AsPlainText)
            }
        }
        catch {
            Write-Verbose "Get-ScoutArmChildResource: could not acquire a Resource Manager token ($($_.Exception.GetType().Name)); fetching sequentially."
            return $null
        }
    }

    function Invoke-ArmParallelFetch {
        # The only concurrent step: run the FETCH half for every request, $ThrottleLimit at a time.
        # Each runspace gets the fetch text, the base URL and the Authorization header as plain
        # strings and returns a result object; nothing else is shared. Errors are collected, not
        # thrown: ForEach-Object -Parallel does not accept -ErrorAction, so the local preference is
        # relaxed instead, and a request that returned nothing is simply fetched again in-process.
        param(
            [Parameter(Mandatory)][object[]]$Requests,
            [Parameter(Mandatory)][string]$ManagementHost,
            [Parameter(Mandatory)][string]$Authorization
        )
        $ErrorActionPreference = 'SilentlyContinue'
        $FetchChildText = $FetchChildBlock.ToString()
        $Fetched = @($Requests | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                & ([scriptblock]::Create($using:FetchChildText)) -Path $_.Path -DatasetName $_.Dataset -Mode 'Direct' `
                    -ManagementHost $using:ManagementHost -Authorization $using:Authorization -Index $_.Index
            } -ErrorVariable ParallelErrors)
        foreach ($ParallelError in @($ParallelErrors)) {
            Write-Verbose "Get-ScoutArmChildResource: a parallel request did not return a result and will be fetched sequentially: $($ParallelError.Exception.GetType().Name)"
        }
        return $Fetched
    }

    if ($Execution -ne 'InProcess' -and $ThrottleLimit -gt 1 -and $AllWorkItems.Count -ge 2) {
        $RestCommand = Get-Command Invoke-AzRestMethod -ErrorAction SilentlyContinue
        $IsRealAz = $null -ne $RestCommand -and $RestCommand.CommandType -eq 'Cmdlet'
        if ($Execution -eq 'Parallel' -or $IsRealAz) {
            $ParallelAuth = Resolve-ArmParallelAuthorization
            if ($null -ne $ParallelAuth) {
                # Only what a runspace needs crosses over -- not the parent rows.
                $Requests = @($AllWorkItems | ForEach-Object { [pscustomobject]@{ Index = $_.Index; Dataset = $_.Dataset; Path = $_.Path } })
                try {
                    foreach ($FetchResult in @(Invoke-ArmParallelFetch -Requests $Requests -ManagementHost $ParallelAuth.ManagementHost -Authorization $ParallelAuth.Authorization)) {
                        if ($null -ne $FetchResult -and $FetchResult.PSObject.Properties['Index']) { $Prefetched[[int]$FetchResult.Index] = $FetchResult }
                    }
                }
                catch {
                    # A batch that fails outright costs only time: whatever it did not return is
                    # fetched sequentially below.
                    Write-Verbose "Get-ScoutArmChildResource: the parallel batch failed ($($_.Exception.GetType().Name)); fetching sequentially."
                }
                Write-Verbose ("Get-ScoutArmChildResource: fetched {0} of {1} per-parent request(s) {2}-wide." -f $Prefetched.Count, $AllWorkItems.Count, $ThrottleLimit)
                $ParallelAuth = $null
            }
        }
    }

    foreach ($DatasetName in $Selected) {
        switch ($DatasetName) {
            'MLComputes' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/computes?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'MLDatasets' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/data?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        $VersionContent = Get-ArmChildContent `
                            -Path "$Base/data/$($Child.name)/versions?api-version=2023-04-01&`$orderby=createdTime desc&`$top=1" `
                            -DatasetName "$DatasetName.LatestVersion" `
                            -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                        $Latest = @(Get-ArmChildItemSet -Content $VersionContent | Select-Object -First 1)
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                            -LatestVersion $(if ($Latest.Count -gt 0) { $Latest[0] } else { $null })
                    }
                }
            }
            'MLDatastores' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/datastores?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'MLEndpoints' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    foreach ($EndpointType in @('onlineEndpoints', 'batchEndpoints')) {
                        $Content = Get-ArmChildContent -Path "$Base/$EndpointType`?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                            Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                        )
                        foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                            $DeploymentContent = Get-ArmChildContent `
                                -Path "$Base/$EndpointType/$($Child.name)/deployments?api-version=2023-04-01" `
                                -DatasetName "$DatasetName.Deployments" `
                                -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                            $Count = @(Get-ArmChildItemSet -Content $DeploymentContent).Count
                            ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                                -EndpointType $EndpointType -DeploymentCount $Count
                        }
                    }
                }
            }
            'MLModels' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/models?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        $VersionContent = Get-ArmChildContent `
                            -Path "$Base/models/$($Child.name)/versions?api-version=2023-04-01&`$orderby=createdTime desc&`$top=1" `
                            -DatasetName "$DatasetName.LatestVersion" `
                            -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                        $Latest = @(Get-ArmChildItemSet -Content $VersionContent | Select-Object -First 1)
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                            -LatestVersion $(if ($Latest.Count -gt 0) { $Latest[0] } else { $null })
                    }
                }
            }
            'MLPipelines' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent `
                        -Path "$Base/jobs?api-version=2023-04-01&`$filter=jobType eq 'Pipeline'" `
                        -DatasetName $DatasetName `
                        -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'OpenAIDeployments' {
                foreach ($Parent in $OpenAiParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/deployments?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'SearchIndexes' {
                # Search indexes are data-plane objects. Microsoft.Search does not expose an ARM
                # `/indexes` child collection, and subscription Reader cannot authenticate to the
                # Search data plane. The old request therefore generated a 404 per Search service
                # while never returning an index. Keep this gap explicit without making a request
                # that cannot succeed under Scout's read-only ARM permission contract.
                if ($SearchParents.Count -gt 0 -and $null -ne $CollectionHealth) {
                    [void]$CollectionHealth.Add([pscustomobject]@{
                            Dataset       = $DatasetName
                            Operation     = "$DatasetName.DataPlaneList"
                            Status        = 'NotAssessed'
                            Reason        = 'Azure AI Search indexes are data-plane objects and are not available through ARM Reader. Parent Search services remain inventoried.'
                            ResourceTypes = @("AZSC/ARMChild/$DatasetName")
                        })
                }
                Write-Verbose 'Get-ScoutArmChildResource: SearchIndexes not assessed because Azure AI Search exposes indexes only through its data plane.'
            }
            'AVDApplications' {
                foreach ($Parent in $AvdParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/applications?api-version=2022-09-09" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'AppInsightsProactiveDetection' {
                foreach ($Parent in $AppInsightsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/ProactiveDetectionConfigs?api-version=2018-05-01-preview" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'LAWorkspaceLinkedServices' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/linkedServices?api-version=2020-08-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'LAWorkspaceSavedSearches' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/savedSearches?api-version=2020-08-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'LAWorkspaceTables' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/tables?api-version=2022-10-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'SentinelDataConnectors' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2023-11-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'SentinelIngestion' {
                $logToken = $null
                $tokenStartedAt = Get-Date
                try {
                    $tokenData = Get-AzAccessToken -ResourceUrl 'https://api.loganalytics.io' -AsSecureString -ErrorAction Stop
                    if ($tokenData.Token -is [securestring]) {
                        $logToken = $tokenData.Token
                    }
                    else {
                        throw 'Get-AzAccessToken did not honor -AsSecureString for the Log Analytics resource.'
                    }
                    if ($null -ne $SourceOperations) {
                        [void]$SourceOperations.Add([pscustomobject]@{
                                Source = 'Azure PowerShell authentication'
                                Dataset = $DatasetName
                                Operation = 'Acquire Log Analytics query token'
                                Uri = 'https://api.loganalytics.io'
                                Status = 'Success'
                                Count = 1
                                Reason = $null
                                StartedAt = $tokenStartedAt.ToString('o')
                                CompletedAt = (Get-Date).ToString('o')
                            })
                    }
                }
                catch {
                    if ($null -ne $CollectionHealth) {
                        [void]$CollectionHealth.Add([pscustomobject]@{
                                Dataset = $DatasetName
                                Operation = 'Acquire Log Analytics query token'
                                Status = 'Unavailable'
                                Reason = $_.Exception.Message
                                ResourceTypes = @("AZSC/ARMChild/$DatasetName")
                            })
                    }
                    if ($null -ne $SourceOperations) {
                        [void]$SourceOperations.Add([pscustomobject]@{
                                Source = 'Azure PowerShell authentication'
                                Dataset = $DatasetName
                                Operation = 'Acquire Log Analytics query token'
                                Uri = 'https://api.loganalytics.io'
                                Status = 'Unavailable'
                                Count = 0
                                Reason = $_.Exception.Message
                                StartedAt = $tokenStartedAt.ToString('o')
                                CompletedAt = (Get-Date).ToString('o')
                            })
                    }
                }
                if ($logToken) {
                    foreach ($Parent in $LogAnalyticsParents) {
                        $ParentName = [string](Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                        $properties = Get-ArmParentValue -InputObject $Parent -Name @('properties', 'PROPERTIES')
                        $workspaceId = [string](Get-ArmParentValue -InputObject $properties -Name @('customerId', 'CUSTOMERID'))
                        if ([string]::IsNullOrWhiteSpace($workspaceId)) {
                            $reason = "Workspace '$ParentName' did not expose properties.customerId, so the Logs Query API could not be called."
                            if ($null -ne $CollectionHealth) {
                                [void]$CollectionHealth.Add([pscustomobject]@{
                                        Dataset = $DatasetName
                                        Operation = 'Query ingestion freshness'
                                        Status = 'Unavailable'
                                        Reason = $reason
                                        ResourceTypes = @("AZSC/ARMChild/$DatasetName")
                                    })
                            }
                            if ($null -ne $SourceOperations) {
                                [void]$SourceOperations.Add([pscustomobject]@{
                                        Source = 'Azure Monitor Logs Query API'
                                        Dataset = $DatasetName
                                        ParentName = $ParentName
                                        Operation = 'POST query'
                                        Uri = $null
                                        ApiVersion = 'v1'
                                        Status = 'Unavailable'
                                        Count = 0
                                        Reason = $reason
                                        StartedAt = (Get-Date).ToString('o')
                                        CompletedAt = (Get-Date).ToString('o')
                                    })
                            }
                            continue
                        }
                        $uri = "https://api.loganalytics.io/v1/workspaces/$workspaceId/query"
                        $startedAt = Get-Date
                        try {
                            $query = 'union withsource=__AzureScoutIngestionSourceTable * | summarize LastRecord=max(TimeGenerated), Count=count() by TableName=__AzureScoutIngestionSourceTable | order by Count desc | take 40'
                            $response = Invoke-ScoutDiagnosticOperation -Operation {
                                Invoke-RestMethod -Uri $uri -Method POST -Authentication Bearer -Token $logToken -ContentType 'application/json' -Body (@{ query = $query; timespan = 'P30D' } | ConvertTo-Json -Compress) -ErrorAction Stop
                            }
                            $table = @($response.tables | Select-Object -First 1)
                            $columns = if ($table.Count -gt 0) { @($table[0].columns.name) } else { @() }
                            $resultRows = [System.Collections.Generic.List[object]]::new()
                            if ($table.Count -gt 0) {
                                $rawRows = @($table[0].rows)
                                # PowerShell functions can unwrap a single nested JSON row into
                                # its scalar values even though Invoke-RestMethod normally keeps
                                # rows as object[]. Accept both shapes without splitting a single
                                # table summary into one bogus row per character/value.
                                if ($rawRows.Count -gt 0 -and
                                    ($rawRows[0] -isnot [System.Collections.IEnumerable] -or $rawRows[0] -is [string])) {
                                    [void]$resultRows.Add([object[]]$rawRows)
                                }
                                else {
                                    foreach ($rawRow in $rawRows) { [void]$resultRows.Add($rawRow) }
                                }
                            }
                            foreach ($values in $resultRows) {
                                $shape = [ordered]@{}
                                for ($columnIndex = 0; $columnIndex -lt $columns.Count; $columnIndex++) {
                                    $shape[$columns[$columnIndex]] = $values[$columnIndex]
                                }
                                $shape['id'] = "$workspaceId/$($shape.TableName)"
                                $shape['name'] = [string]$shape.TableName
                                $shape['__AZSCSource'] = [pscustomobject]@{
                                    Source = 'Azure Monitor Logs Query API'
                                    Dataset = $DatasetName
                                    Operation = 'POST query'
                                    Uri = $uri
                                    ApiVersion = 'v1'
                                    CollectedAt = (Get-Date).ToString('o')
                                }
                                ConvertTo-ArmChildRow -Child ([pscustomobject]$shape) -Parent $Parent -DatasetName $DatasetName
                            }
                            if ($null -ne $SourceOperations) {
                                [void]$SourceOperations.Add([pscustomobject]@{
                                        Source = 'Azure Monitor Logs Query API'
                                        Dataset = $DatasetName
                                        ParentName = $ParentName
                                        Operation = 'POST query'
                                        Uri = $uri
                                        ApiVersion = 'v1'
                                        Status = if ($resultRows.Count -gt 0) { 'Success' } else { 'Empty' }
                                        Count = $resultRows.Count
                                        Reason = $null
                                        StartedAt = $startedAt.ToString('o')
                                        CompletedAt = (Get-Date).ToString('o')
                                    })
                            }
                        }
                        catch {
                            $failure = Get-ScoutHttpFailure -ErrorRecord $_
                            Write-AZSCLog -Level ERROR -Message "Sentinel ingestion query for '$ParentName': $($failure.Summary)"
                            if ($null -ne $CollectionHealth) {
                                [void]$CollectionHealth.Add([pscustomobject]@{
                                        Dataset = $DatasetName
                                        Operation = 'Query ingestion freshness'
                                        Status = 'Unavailable'
                                        Reason = "Workspace '$ParentName': $($_.Exception.Message)"
                                        ResourceTypes = @("AZSC/ARMChild/$DatasetName")
                                    })
                            }
                            if ($null -ne $SourceOperations) {
                                [void]$SourceOperations.Add([pscustomobject]@{
                                        Source = 'Azure Monitor Logs Query API'
                                        Dataset = $DatasetName
                                        ParentName = $ParentName
                                        Operation = 'POST query'
                                        Uri = $uri
                                        ApiVersion = 'v1'
                                        Status = 'Failed'
                                        Count = 0
                                        Reason = $_.Exception.Message
                                        StartedAt = $startedAt.ToString('o')
                                        CompletedAt = (Get-Date).ToString('o')
                                    })
                            }
                        }
                    }
                }
            }

            # --- Storage children (AB#6834) --------------------------------------------------------
            #
            # Also control plane. `blobServices/default/containers` returns each container's
            # `publicAccess` level -- the property that answers "is anything in this account
            # anonymously reachable", which a storage-account list cannot. Listing containers is
            # `Microsoft.Storage/storageAccounts/blobServices/containers/read`, held by Reader.
            # Nothing here reads a blob, a file, or an account key.
            'StorageBlobContainers' {
                foreach ($Parent in $StorageAccountParents) {
                    if (-not (Test-StorageServiceSupported -Parent $Parent -Service Blob)) { continue }
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/blobServices/default/containers?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'StorageFileShares' {
                foreach ($Parent in $StorageAccountParents) {
                    if (-not (Test-StorageServiceSupported -Parent $Parent -Service File)) { continue }
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/fileServices/default/shares?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'StorageLifecyclePolicies' {
                foreach ($Parent in $StorageAccountParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    # Singleton, not a list: an account with no policy returns 404. That absence
                    # is ordinary empty data and must not become a warning/transcript error.
                    $Content = Get-ArmChildContent -Path "$Base/managementPolicies/default?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    ) -NotFoundIsEmpty
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Storage queues (AB#7087, Story AB#7059, Feature AB#7069, Epic AB#7099) -------------
            #
            # Same reasoning as StorageBlobContainers/StorageFileShares directly above: Queue
            # Storage has no Resource Graph table of its own -- `queueServices/default/queues` is
            # a control-plane list under the storage account, `Microsoft.Storage/storageAccounts/
            # queueServices/queues/read`, held by Reader. Returns metadata only (name + the
            # `metadata` key/value bag a caller attached); no queue message is ever read.
            'StorageQueues' {
                foreach ($Parent in $StorageAccountParents) {
                    if (-not (Test-StorageServiceSupported -Parent $Parent -Service Queue)) { continue }
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/queueServices/default/queues?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Table Storage (AB#7090, Story AB#7071/AB#7059, Feature AB#7069, Epic AB#7099) ------
            #
            # Same reasoning as StorageQueues directly above: Table Storage has no Resource Graph
            # table of its own -- `tableServices/default/tables` is a control-plane list under the
            # storage account, `Microsoft.Storage/storageAccounts/tableServices/tables/read`, held
            # by Reader. Returns table name and metadata only; no table entity/row is ever read.
            'StorageTables' {
                foreach ($Parent in $StorageAccountParents) {
                    if (-not (Test-StorageServiceSupported -Parent $Parent -Service Table)) { continue }
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/tableServices/default/tables?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Backup vault instances (AB#6833) --------------------------------------------------
            #
            # Recovery Services vault protected items already arrive through Resource Graph's
            # `recoveryservicesresources` table (see Get-ScoutRawInventory's -IncludeBackupResources).
            # Backup vaults -- the newer `Microsoft.DataProtection` service that protects disks, blobs,
            # PostgreSQL and AKS -- are NOT in that table, so "which VMs have no backup" was wrong for
            # any estate using them. This closes that half.
            'BackupInstances' {
                foreach ($Parent in $BackupVaultParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/backupInstances?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Reservation utilization (AB#6829) -------------------------------------------------
            #
            # `Reservations` already lists WHAT was bought (Microsoft.Capacity/reservationOrders and
            # .../reservations, both indexed by Resource Graph). It cannot say whether any of it is
            # being used -- utilisation is served by a DIFFERENT resource provider,
            # Microsoft.Consumption, scoped per reservation:
            #
            #   GET {reservationOrderId}/reservations/{reservationId}
            #       /providers/Microsoft.Consumption/reservationSummaries?grain=monthly&api-version=2023-05-01
            #
            # This is NOT the billing-account permission system documented in the audit's "Cost and
            # billing" section (§9). Reservations are their own, SIXTH scope: a tenant-level resource
            # independent of subscription RBAC (see "Permissions to view and manage Azure
            # reservations" -- learn.microsoft.com/azure/cost-management-billing/reservations/
            # view-reservations). Microsoft's own guidance is that a built-in Reader role AT THE
            # RESERVATION SCOPE is sufficient to view utilisation; since the parent reservation
            # already came back from Resource Graph (which required exactly that visibility), no
            # additional grant is asked for here -- only the existing billing/cost gate this
            # function's neighbours already document, and even that is arguably not needed, because
            # Reservations Reader (or reservation-scoped Reader) is a distinct system from EA/MCA
            # billing roles.
            #
            # `grain=monthly` returns one row per calendar month; the most recent row is what the
            # collector reports, so a very new reservation with no month closed yet has no
            # utilisation row -- an absence, not a zero, and rendered as such.
            'ReservationUtilization' {
                foreach ($Parent in $ReservationParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/providers/Microsoft.Consumption/reservationSummaries?grain=monthly&api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    $Latest = @(Get-ArmChildItemSet -Content $Content |
                        Sort-Object -Property { [string](Get-ArmParentValue -InputObject $_ -Name @('properties', 'PROPERTIES') |
                            ForEach-Object { Get-ArmParentValue -InputObject $_ -Name @('usageDate', 'UsageDate') }) } -Descending |
                        Select-Object -First 1)
                    foreach ($Child in $Latest) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Azure Local virtual machine instances (AB#6802 / Feature AB#6747) -----------------
            #
            # WHY THIS IS A REST CALL AND NOT A RESOURCE GRAPH ROW.
            # `Microsoft.AzureStackHCI/virtualMachineInstances` is listed on Microsoft's own
            # "resource types that extend capabilities of other resources" page
            # (https://learn.microsoft.com/azure/azure-resource-manager/management/extension-resource-types#microsoftazurestackhci)
            # -- it is an ARM EXTENSION resource, scoped under a `Microsoft.HybridCompute/machines`
            # parent, not a standalone resource. Resource Graph's own supported-type reference
            # (https://learn.microsoft.com/azure/governance/resource-graph/reference/supported-tables-resources)
            # lists eleven other `microsoft.azurestackhci/*` types it indexes -- including the
            # confusingly similar `microsoft.azurestackhci/virtualmachines` (no "instances") --
            # but `virtualmachineinstances` is not one of them. The old declarative collector
            # queried the `resources` table for that exact type and could not have returned a row
            # in ANY tenant, deployed or not: it is the same defect class AB#6769 fixed for
            # ResourceDiagnosticSettings, not the "tenant just has none" verdict AB#6846 recorded
            # (see docs/audits/AZURE-SCOUT-AUDIT.md's revision of that verdict for the full
            # reasoning and citations).
            #
            # The instance is a SINGLETON named `default` under each machine -- there is no list
            # endpoint, matching the Bicep/ARM template reference's `name: 'default' (required)`.
            # A machine that is not an Azure Local guest returns 404, which Get-ArmChildContent
            # already degrades to a warning and $null, exactly like StorageLifecyclePolicies.
            #
            # Control plane, read-only -- `Microsoft.AzureStackHCI/virtualMachineInstances/read`,
            # which Reader's `*/read` wildcard already covers. No new permission is required.
            'AzureLocalVirtualMachineInstances' {
                foreach ($Parent in $HybridComputeMachineParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/providers/Microsoft.AzureStackHCI/virtualMachineInstances/default?api-version=2024-01-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    ) -NotFoundIsEmpty
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # The nine one-GET-per-parent datasets (see Get-ArmWorkItem for what each reads). The GETs
            # may already have been made in parallel; this applies them in work-item order.
            { $ParallelDatasets -contains $_ } {
                foreach ($Item in $WorkItems[$DatasetName]) {
                    $Content = Get-ArmChildContent -Path $Item.Path -DatasetName $DatasetName -ParentId $Item.ParentId `
                        -ParentName $Item.ParentName -NotFoundIsEmpty:$Item.NotFoundIsEmpty `
                        -Prefetched $(if ($Prefetched.ContainsKey($Item.Index)) { $Prefetched[$Item.Index] } else { $null })
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        # ResourceDiagnosticSettings keeps the whole setting (the worksheet shows its
                        # destinations); the other eight keep only their allow-listed scalars.
                        $RowChild = if ($DatasetName -eq 'ResourceDiagnosticSettings') { $Child } else {
                            ConvertTo-ArmSafeChild -Child $Child -DatasetName $DatasetName -Extra $Item.Extra
                        }
                        ConvertTo-ArmChildRow -Child $RowChild -Parent $Item.Parent -DatasetName $DatasetName
                    }
                }
            }
        }
    }
}
