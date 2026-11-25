#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300 phase 4, batch 2 follow-up -- the per-parent ARM GETs run in parallel.

    ResourceDiagnosticSettings and the eight batch-2 datasets are one independent GET per parent, and
    sequentially they cost about 0.6 s each. Get-ScoutArmChildResource now fetches them up to
    -ThrottleLimit (default 8) at a time in ForEach-Object -Parallel runspaces and APPLIES the results
    on the calling thread in input order. These tests hold the one property that matters: the parallel
    path and the in-process path are indistinguishable except for the clock.

    The in-process path is exercised through a stub of Invoke-AzRestMethod, exactly as
    Collect.ArmChildResources.Tests.ps1 does. A runspace cannot see that stub, so the parallel path is
    exercised against a real HTTP listener on the loopback interface that serves the SAME fixture:
    Invoke-WebRequest, the retry loop, the paging and the status handling all run for real. No Azure
    connection, credentials, tenant or subscription identifier is involved; the "token" is a sentinel.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')

    if (-not ('ArmFixtureServer' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Threading;

public sealed class ArmFixtureServer : IDisposable
{
    private sealed class Route { public int Status; public string Body; public int FailFirst; public int Hits; }

    private readonly HttpListener _listener = new HttpListener();
    private readonly ConcurrentDictionary<string, Route> _routes = new ConcurrentDictionary<string, Route>(StringComparer.OrdinalIgnoreCase);
    private int _inFlight;
    private int _maxInFlight;
    private int _requests;
    private int _unauthorized;
    public int DelayMilliseconds;
    public string ExpectedAuthorization = "";
    public string Prefix { get; private set; }

    public int MaxInFlight { get { return _maxInFlight; } }
    public int Requests { get { return _requests; } }
    public int Unauthorized { get { return _unauthorized; } }

    public ArmFixtureServer(string prefix)
    {
        Prefix = prefix;
        _listener.Prefixes.Add(prefix);
    }

    public void Add(string path, int status, string body, int failFirst)
    {
        _routes[path] = new Route { Status = status, Body = body, FailFirst = failFirst };
    }

    public void Reset()
    {
        foreach (var route in _routes.Values) { route.Hits = 0; }
        _inFlight = 0; _maxInFlight = 0; _requests = 0; _unauthorized = 0;
    }

    public void Start()
    {
        _listener.Start();
        var thread = new Thread(Loop) { IsBackground = true };
        thread.Start();
    }

    private void Loop()
    {
        while (_listener.IsListening)
        {
            HttpListenerContext context;
            try { context = _listener.GetContext(); } catch { break; }
            ThreadPool.QueueUserWorkItem(_ => Handle(context));
        }
    }

    private void Handle(HttpListenerContext context)
    {
        var now = Interlocked.Increment(ref _inFlight);
        int seen;
        while ((seen = _maxInFlight) < now && Interlocked.CompareExchange(ref _maxInFlight, now, seen) != seen) { }
        Interlocked.Increment(ref _requests);
        try
        {
            if (DelayMilliseconds > 0) { Thread.Sleep(DelayMilliseconds); }
            if (ExpectedAuthorization.Length > 0 && context.Request.Headers["Authorization"] != ExpectedAuthorization)
            {
                Interlocked.Increment(ref _unauthorized);
            }
            int status = 404;
            string body = "{\"error\":{\"code\":\"ResourceNotFound\",\"message\":\"no such route\"}}";
            Route route;
            if (_routes.TryGetValue(context.Request.Url.AbsolutePath, out route))
            {
                var hit = Interlocked.Increment(ref route.Hits);
                if (hit <= route.FailFirst) { status = 500; body = "{\"error\":{\"code\":\"InternalServerError\",\"message\":\"try again\"}}"; }
                else { status = route.Status; body = route.Body; }
            }
            var bytes = Encoding.UTF8.GetBytes(body);
            context.Response.StatusCode = status;
            context.Response.ContentType = "application/json";
            context.Response.ContentLength64 = bytes.Length;
            context.Response.OutputStream.Write(bytes, 0, bytes.Length);
            context.Response.Close();
        }
        catch { try { context.Response.Abort(); } catch { } }
        finally { Interlocked.Decrement(ref _inFlight); }
    }

    public void Dispose()
    {
        try { _listener.Stop(); _listener.Close(); } catch { }
    }
}
'@
    }

    $script:Token = 'SENTINEL-TOKEN-7f3a91c4'
    $script:Server = $null
    foreach ($candidate in 'http://127.0.0.1', 'http://localhost') {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start(); $port = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port; $probe.Stop()
        $server = [ArmFixtureServer]::new("${candidate}:$port/")
        try { $server.Start(); $script:Server = $server; $script:Base = "${candidate}:$port"; break }
        catch { $server.Dispose() }
    }

    function New-Parent {
        param([string]$Type, [string]$Name, [string]$Kind, $Sku)
        [pscustomobject]@{
            id = "/subscriptions/s1/resourceGroups/rg1/providers/$Type/$Name"
            type = $Type; name = $Name; kind = $Kind; sku = $Sku
            subscriptionId = 's1'; resourceGroup = 'rg1'; location = 'eastus'
            properties = [pscustomobject]@{}
        }
    }

    # A mixed estate: every outcome the apply step distinguishes, across the diagnostic sweep and
    # all eight batch-2 datasets.
    $script:Parents = @(
        New-Parent -Type 'microsoft.keyvault/vaults' -Name 'kv-has-setting'
        New-Parent -Type 'microsoft.keyvault/vaults' -Name 'kv-no-setting'
        New-Parent -Type 'microsoft.network/networksecuritygroups' -Name 'nsg-unregistered-a'
        New-Parent -Type 'microsoft.network/networksecuritygroups' -Name 'nsg-unregistered-b'
        New-Parent -Type 'microsoft.storage/storageaccounts' -Name 'st-ok' -Kind 'StorageV2'
        New-Parent -Type 'microsoft.storage/storageaccounts' -Name 'st-denied' -Kind 'StorageV2'
        New-Parent -Type 'microsoft.storage/storageaccounts' -Name 'st-paged' -Kind 'StorageV2'
        New-Parent -Type 'microsoft.storage/storageaccounts' -Name 'st-file-only' -Kind 'FileStorage'
        New-Parent -Type 'microsoft.web/sites' -Name 'web-ok' -Kind 'app'
        New-Parent -Type 'microsoft.web/sites' -Name 'web-flaky' -Kind 'app'
        New-Parent -Type 'microsoft.sql/servers' -Name 'sql-one'
        New-Parent -Type 'microsoft.eventhub/namespaces' -Name 'eh-standard' -Sku ([pscustomobject]@{ name = 'Standard' })
        New-Parent -Type 'microsoft.eventhub/namespaces' -Name 'eh-basic' -Sku ([pscustomobject]@{ name = 'Basic' })
        New-Parent -Type 'microsoft.cache/redisenterprise' -Name 'redis-one'
    )

    function Get-ParentId { param([string]$Name) @($script:Parents | Where-Object name -eq $Name)[0].id }

    function Get-RouteTable {
        # path (no query) -> @{ Status; Body; FailFirst }
        $routes = [ordered]@{}
        $list = { param($items) (@{ value = @($items) } | ConvertTo-Json -Depth 8 -Compress) }
        $none = & $list @()
        # Every diagnostic-sweep parent answers an empty list unless overridden below.
        foreach ($parent in $script:Parents) {
            $routes["$($parent.id)/providers/Microsoft.Insights/diagnosticSettings"] = @{ Status = 200; Body = $none; FailFirst = 0 }
        }
        $setting = { param($parentId, $n) @{ id = "$parentId/providers/microsoft.insights/diagnosticSettings/$n"; name = $n; properties = @{ workspaceId = 'law'; logs = @(@{ category = 'AuditEvent'; enabled = $true }) } } }
        $diag = { param($name) "$(Get-ParentId $name)/providers/Microsoft.Insights/diagnosticSettings" }

        $routes[(& $diag 'kv-has-setting')] = @{ Status = 200; FailFirst = 0; Body = (& $list @(& $setting (Get-ParentId 'kv-has-setting') 'toLaw')) }
        $notRegistered = '{"error":{"code":"SubscriptionNotRegistered","message":"The subscription ''s1'' is not registered to use microsoft.insights."}}'
        $routes[(& $diag 'nsg-unregistered-a')] = @{ Status = 400; Body = $notRegistered; FailFirst = 0 }
        $routes[(& $diag 'nsg-unregistered-b')] = @{ Status = 400; Body = $notRegistered; FailFirst = 0 }
        $routes[(& $diag 'st-ok')] = @{ Status = 200; FailFirst = 0; Body = (& $list @(& $setting (Get-ParentId 'st-ok') 'toLaw')) }
        $routes[(& $diag 'st-denied')] = @{ Status = 403; Body = '{"error":{"code":"AuthorizationFailed","message":"no access"}}'; FailFirst = 0 }
        $pagedId = Get-ParentId 'st-paged'
        $routes[(& $diag 'st-paged')] = @{ Status = 200; FailFirst = 0; Body = (@{ value = @(& $setting $pagedId 'first'); nextLink = "$script:Base/next-diag-page" } | ConvertTo-Json -Depth 8 -Compress) }
        $routes['/next-diag-page'] = @{ Status = 200; FailFirst = 0; Body = (& $list @(& $setting $pagedId 'second')) }

        # Storage services: ok -> a document; denied -> 403 on blob; one 404 on file.
        $blob = @{ id = "$(Get-ParentId 'st-ok')/blobServices/default"; name = 'default'; properties = @{ deleteRetentionPolicy = @{ enabled = $true; days = 14 }; isVersioningEnabled = $true; cors = @{ corsRules = @(@{ allowedOrigins = @('https://SENTINEL-ORIGIN') }) } } } | ConvertTo-Json -Depth 8 -Compress
        $routes["$(Get-ParentId 'st-ok')/blobServices/default"] = @{ Status = 200; Body = $blob; FailFirst = 0 }
        $routes["$(Get-ParentId 'st-denied')/blobServices/default"] = @{ Status = 403; Body = '{"error":{"code":"AuthorizationFailed","message":"no access"}}'; FailFirst = 0 }
        $routes["$(Get-ParentId 'st-paged')/blobServices/default"] = @{ Status = 200; Body = ('{"id":"x","name":"default","properties":{}}'); FailFirst = 0 }
        $file = @{ id = "$(Get-ParentId 'st-ok')/fileServices/default"; name = 'default'; properties = @{ shareDeleteRetentionPolicy = @{ enabled = $true; days = 7 }; protocolSettings = @{ smb = @{ versions = 'SMB3.1.1' } } } } | ConvertTo-Json -Depth 8 -Compress
        $routes["$(Get-ParentId 'st-ok')/fileServices/default"] = @{ Status = 200; Body = $file; FailFirst = 0 }
        $routes["$(Get-ParentId 'st-denied')/fileServices/default"] = @{ Status = 404; Body = '{"error":{"code":"ResourceNotFound"}}'; FailFirst = 0 }
        $routes["$(Get-ParentId 'st-paged')/fileServices/default"] = @{ Status = 200; Body = $file; FailFirst = 0 }
        $routes["$(Get-ParentId 'st-file-only')/fileServices/default"] = @{ Status = 200; Body = $file; FailFirst = 0 }

        # Web apps: one healthy, one whose config answers 500 once (retried) and whose scm policy is absent.
        foreach ($site in 'web-ok', 'web-flaky') {
            $siteId = Get-ParentId $site
            $config = @{ id = "$siteId/config/web"; name = 'web'; properties = @{ ftpsState = 'FtpsOnly'; alwaysOn = $true; healthCheckPath = '/SENTINEL-PATH'; appSettings = @(@{ name = 'K'; value = 'SENTINEL-SETTING' }) } } | ConvertTo-Json -Depth 8 -Compress
            $routes["$siteId/config/web"] = @{ Status = 200; Body = $config; FailFirst = $(if ($site -eq 'web-flaky') { 1 } else { 0 }) }
            $routes["$siteId/basicPublishingCredentialsPolicies/ftp"] = @{ Status = 200; FailFirst = 0; Body = (@{ id = "$siteId/basicPublishingCredentialsPolicies/ftp"; name = 'ftp'; properties = @{ allow = $false } } | ConvertTo-Json -Depth 6 -Compress) }
            $scmStatus = if ($site -eq 'web-flaky') { 404 } else { 200 }
            $routes["$siteId/basicPublishingCredentialsPolicies/scm"] = @{ Status = $scmStatus; FailFirst = 0; Body = $(if ($scmStatus -eq 200) { @{ id = "$siteId/basicPublishingCredentialsPolicies/scm"; name = 'scm'; properties = @{ allow = $true } } | ConvertTo-Json -Depth 6 -Compress } else { '{"error":{"code":"ResourceNotFound"}}' }) }
        }

        $sqlId = Get-ParentId 'sql-one'
        $routes["$sqlId/auditingSettings/default"] = @{ Status = 200; FailFirst = 0; Body = (@{ id = "$sqlId/auditingSettings/default"; name = 'default'; properties = @{ state = 'Enabled'; isAzureMonitorTargetEnabled = $true; storageAccountAccessKey = 'SENTINEL-KEY' } } | ConvertTo-Json -Depth 6 -Compress) }
        $routes["$sqlId/failoverGroups"] = @{ Status = 200; FailFirst = 0; Body = (& $list @(
                    @{ id = "$sqlId/failoverGroups/fg1"; name = 'fg1'; properties = @{ readWriteEndpoint = @{ failoverPolicy = 'Automatic' }; partnerServers = @(@{ id = '/x/SENTINEL-PARTNER' }) } }
                    @{ id = "$sqlId/failoverGroups/fg2"; name = 'fg2'; properties = @{ readWriteEndpoint = @{ failoverPolicy = 'Manual' } } })) }
        $ehId = Get-ParentId 'eh-standard'
        $routes["$ehId/disasterRecoveryConfigs"] = @{ Status = 200; FailFirst = 0; Body = (& $list @(@{ id = "$ehId/disasterRecoveryConfigs/alias"; name = 'alias'; properties = @{ role = 'Primary'; provisioningState = 'Succeeded'; partnerNamespace = '/x/SENTINEL-NAMESPACE' } })) }
        $redisId = Get-ParentId 'redis-one'
        $routes["$redisId/databases"] = @{ Status = 200; FailFirst = 0; Body = (& $list @(@{ id = "$redisId/databases/default"; name = 'default'; properties = @{ accessKeysAuthentication = 'Disabled'; clientProtocol = 'Encrypted' } })) }
        $routes
    }

    $script:Datasets = @(
        'ResourceDiagnosticSettings', 'StorageBlobServiceProperties', 'StorageFileServiceProperties', 'SqlServerAuditing',
        'SqlFailoverGroups', 'WebAppConfig', 'WebAppBasicAuth', 'EventHubGeoDr', 'RedisEnterpriseDatabases'
    )

    function Set-ServerRouteTable {
        param([System.Collections.IDictionary]$Routes)
        foreach ($path in $Routes.Keys) { $script:Server.Add($path, [int]$Routes[$path].Status, [string]$Routes[$path].Body, [int]$Routes[$path].FailFirst) }
    }

    function Install-StubTransport {
        param([System.Collections.IDictionary]$Routes)
        $script:StubRoutes = $Routes
        $script:StubHits = @{}
        $script:StubCalls = 0
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Uri, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Method, $Rest
            $script:StubCalls++
            $request = if ($Uri) { ([uri]$Uri).AbsolutePath } else { ($Path -split '\?')[0] }
            $route = $script:StubRoutes[$request]
            if ($null -eq $route) { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound","message":"no such route"}}' } }
            $script:StubHits[$request] = 1 + [int]$script:StubHits[$request]
            if ($script:StubHits[$request] -le [int]$route.FailFirst) {
                return [pscustomobject]@{ StatusCode = 500; Content = '{"error":{"code":"InternalServerError","message":"try again"}}' }
            }
            [pscustomobject]@{ StatusCode = [int]$route.Status; Content = [string]$route.Body }
        }
    }

    function Invoke-Sweep {
        param([hashtable]$Arguments)
        $health = [System.Collections.Generic.List[object]]::new()
        $operations = [System.Collections.Generic.List[object]]::new()
        $warnings = $null
        $rows = @(Get-ScoutArmChildResource -Resources $script:Parents -Dataset $script:Datasets `
                -CollectionHealth $health -SourceOperations $operations -WarningVariable warnings -WarningAction SilentlyContinue @Arguments)
        [pscustomobject]@{ Rows = $rows; Operations = @($operations); Health = @($health); Warnings = @($warnings | ForEach-Object { $_.Message }) }
    }

    function ConvertTo-Comparable {
        # Everything except the clock: timestamps differ run to run by construction.
        param($Sweep)
        [pscustomobject]@{
            Rows       = @($Sweep.Rows | ForEach-Object { $copy = $_ | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $copy.AZSC.CollectedAt = $null; $copy | ConvertTo-Json -Depth 12 -Compress })
            Operations = @($Sweep.Operations | ForEach-Object { $_ | Select-Object -Property * -ExcludeProperty StartedAt, CompletedAt | ConvertTo-Json -Depth 6 -Compress })
            Health     = @($Sweep.Health | ForEach-Object { $_ | ConvertTo-Json -Depth 6 -Compress })
            Warnings   = @($Sweep.Warnings)
        }
    }

    function Initialize-Server {
        # Every test starts from a clean listener with the full fixture; a host that cannot open a
        # loopback listener skips instead of failing.
        if ($null -eq $script:Server) { Set-ItResult -Skipped -Because 'a loopback HTTP listener could not be started on this host'; return $false }
        $script:Server.Reset()
        $script:Server.DelayMilliseconds = 0
        $script:Server.ExpectedAuthorization = "Bearer $script:Token"
        Set-ServerRouteTable -Routes (Get-RouteTable)
        return $true
    }

    function New-Token {
        $secure = [securestring]::new()
        foreach ($character in $script:Token.ToCharArray()) { $secure.AppendChar($character) }
        $secure
    }
}

AfterAll {
    if ($null -ne $script:Server) { $script:Server.Dispose() }
    Remove-Item -Path 'Function:\Invoke-AzRestMethod' -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Get-AzContext' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ScoutArmChildResource -- parallel per-parent GETs' {

    It 'produces the same rows, source operations, health and warnings as the in-process path, in the same order' {
        if (-not (Initialize-Server)) { return }
        Install-StubTransport -Routes (Get-RouteTable)
        $sequential = Invoke-Sweep -Arguments @{ Execution = 'InProcess' }
        $script:Server.Requests | Should -Be 0 -Because 'the in-process run must not touch the network'
        $script:StubCalls | Should -BeGreaterThan 20

        $parallel = Invoke-Sweep -Arguments @{ Execution = 'Parallel'; ManagementEndpoint = $script:Base; AccessToken = (New-Token); ThrottleLimit = 8 }
        # A transient 500 is retried, so the listener sees more requests than the sweep has parents.
        $script:Server.Requests | Should -BeGreaterThan 20

        # The fixture really covers every outcome, so equality below is not vacuous.
        $statuses = @($sequential.Operations.Status | Sort-Object -Unique)
        $statuses | Should -Be @('Empty', 'Failed', 'NotApplicable', 'Success')
        @($sequential.Rows).Count | Should -BeGreaterThan 15
        @($sequential.Health | Where-Object Status -eq 'Unavailable').Count | Should -Be 2 -Because 'health is one record per dataset: the diagnostic sweep (403) and the blob service (403)'
        @($sequential.Health | Where-Object Status -eq 'NotAssessed').Count | Should -Be 1 -Because 'not-registered is one record per subscription and provider'
        @($sequential.Warnings).Count | Should -BeGreaterThan 1
        @($sequential.Operations | Where-Object { $_.PSObject.Properties['ParentId'] }).Count | Should -Be @($sequential.Operations).Count

        $a = ConvertTo-Comparable $sequential
        $b = ConvertTo-Comparable $parallel
        $b.Rows | Should -Be $a.Rows
        $b.Operations | Should -Be $a.Operations
        $b.Health | Should -Be $a.Health
        $b.Warnings | Should -Be $a.Warnings
    }

    It 'runs requests concurrently but never more than the throttle' {
        if (-not (Initialize-Server)) { return }
        $script:Server.DelayMilliseconds = 120
        $storage = @(1..24 | ForEach-Object {
                $parent = New-Parent -Type 'microsoft.storage/storageaccounts' -Name ('st-bulk-{0:d2}' -f $_) -Kind 'StorageV2'
                $script:Server.Add("$($parent.id)/blobServices/default", 200, '{"id":"x","name":"default","properties":{}}', 0)
                $parent
            })
        $call = {
            param($limit)
            Get-ScoutArmChildResource -Resources $storage -Dataset StorageBlobServiceProperties -Execution Parallel `
                -ManagementEndpoint $script:Base -AccessToken (New-Token) -ThrottleLimit $limit
        }

        $script:Server.Reset()
        $started = Get-Date
        $rows = @(& $call 3)
        $elapsed = ((Get-Date) - $started).TotalSeconds
        $rows.Count | Should -Be 24
        $script:Server.Requests | Should -Be 24
        $script:Server.MaxInFlight | Should -BeLessOrEqual 3
        $script:Server.MaxInFlight | Should -BeGreaterThan 1 -Because 'requests must overlap'
        $elapsed | Should -BeLessThan (24 * 0.12) -Because 'overlap beats the 2.9 s a sequential run needs'

        $script:Server.Reset()
        $null = @(& $call 8)
        $script:Server.MaxInFlight | Should -BeLessOrEqual 8
        $script:Server.MaxInFlight | Should -BeGreaterThan 3
    }

    It 'sends the bearer token on every request and never lets it reach a row, operation, health record or warning' {
        if (-not (Initialize-Server)) { return }
        $sweep = Invoke-Sweep -Arguments @{ Execution = 'Parallel'; ManagementEndpoint = $script:Base; AccessToken = (New-Token) }
        $script:Server.Requests | Should -BeGreaterThan 20
        $script:Server.Unauthorized | Should -Be 0 -Because 'every request carries the same Authorization header'

        $everything = (@($sweep.Rows) + @($sweep.Operations) + @($sweep.Health) + @($sweep.Warnings) | ConvertTo-Json -Depth 12)
        $everything | Should -Not -Match ([regex]::Escape($script:Token))
        $everything | Should -Not -Match 'Bearer '
        # Positive control: the sweep did produce output for the absence above to mean something.
        $everything | Should -Match 'FtpsOnly'
    }

    It 'keeps the secret-bearing neighbours out of the parallel rows too' {
        if (-not (Initialize-Server)) { return }
        $sweep = Invoke-Sweep -Arguments @{ Execution = 'Parallel'; ManagementEndpoint = $script:Base; AccessToken = (New-Token) }
        $json = $sweep.Rows | ConvertTo-Json -Depth 12
        foreach ($sentinel in 'SENTINEL-ORIGIN', 'SENTINEL-PATH', 'SENTINEL-SETTING', 'SENTINEL-KEY', 'SENTINEL-PARTNER', 'SENTINEL-NAMESPACE') {
            $json | Should -Not -Match $sentinel
        }
    }

    It 'stays in-process under Auto when Invoke-AzRestMethod is a stub, so mocks keep working' {
        if (-not (Initialize-Server)) { return }
        Install-StubTransport -Routes (Get-RouteTable)
        $null = Invoke-Sweep -Arguments @{ ManagementEndpoint = $script:Base; AccessToken = (New-Token) }
        $script:Server.Requests | Should -Be 0
        $script:StubCalls | Should -BeGreaterThan 20
    }

    It 'stays in-process when the throttle is 1, even if parallel is forced' {
        if (-not (Initialize-Server)) { return }
        Install-StubTransport -Routes (Get-RouteTable)
        $null = Invoke-Sweep -Arguments @{ Execution = 'Parallel'; ThrottleLimit = 1; ManagementEndpoint = $script:Base; AccessToken = (New-Token) }
        $script:Server.Requests | Should -Be 0
        $script:StubCalls | Should -BeGreaterThan 20
    }

    It 'falls back to the in-process path when no token can be built' {
        if (-not (Initialize-Server)) { return }
        Install-StubTransport -Routes (Get-RouteTable)
        function global:Get-AzContext { $null }
        try {
            $sweep = Invoke-Sweep -Arguments @{ Execution = 'Parallel' }
        }
        finally { Remove-Item -Path 'Function:\Get-AzContext' -Force -ErrorAction SilentlyContinue }
        $script:Server.Requests | Should -Be 0
        $script:StubCalls | Should -BeGreaterThan 20
        @($sweep.Rows).Count | Should -BeGreaterThan 15
    }
}
