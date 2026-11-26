#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#9300, 3.18.20 -- the sub-resources of Azure Front Door Standard / Premium profiles, end to end.

    Resource Graph indexes a profile (microsoft.cdn/profiles) but not its origin groups, origins, endpoints, routes, custom
    domains or security policies, so Get-ScoutArmChildResource reads six datasets with ARM GETs (origins once per origin group
    and routes once per endpoint -- the second level), ConvertFrom-ScoutInventory shapes them under `domains.afd` and
    ConvertTo-ScoutChildDiscoveryResource lists them in the discovery index. The shared contract (nothing asked without a parent,
    the documented requests, no secret on any surface, denied is not measured, empty is an answer, a throttle is retried) is
    asserted by tests/helpers/DepthChildHarness.ps1; this file adds what is particular to Front Door:

      - a classic Azure CDN profile (Standard_Microsoft) is never asked, only Front Door Standard / Premium;
      - the second level: an origin group whose origin list failed has NO origin count (null), never zero;
      - the shaped booleans the rules read: redundant origins, probe gap, TLS 1.2 floor, HTTP not redirected;
      - the parallel path, including the second wave, is indistinguishable from the in-process one except for the clock.

    No Azure connection, credential, tenant or subscription identifier is involved.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthChildHarness.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthFamilyCases.ps1')
    $script:Family = @(Get-DepthFamilyCase | Where-Object { $_.Name -eq 'Afd' })[0]

    if (-not ('DepthFixtureServer' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Threading;

public sealed class DepthFixtureServer : IDisposable
{
    private sealed class Route { public int Status; public string Body; }
    private readonly HttpListener _listener = new HttpListener();
    private readonly ConcurrentDictionary<string, Route> _routes = new ConcurrentDictionary<string, Route>(StringComparer.OrdinalIgnoreCase);
    private int _requests;
    public int Requests { get { return _requests; } }
    public DepthFixtureServer(string prefix) { _listener.Prefixes.Add(prefix); }
    public void Add(string path, int status, string body) { _routes[path] = new Route { Status = status, Body = body }; }
    public void Start() { _listener.Start(); var t = new Thread(Loop) { IsBackground = true }; t.Start(); }
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
        Interlocked.Increment(ref _requests);
        try
        {
            int status = 404; string body = "{\"error\":{\"code\":\"ResourceNotFound\",\"message\":\"no such route\"}}";
            Route route;
            if (_routes.TryGetValue(context.Request.Url.AbsolutePath, out route)) { status = route.Status; body = route.Body; }
            var bytes = Encoding.UTF8.GetBytes(body);
            context.Response.StatusCode = status; context.Response.ContentType = "application/json";
            context.Response.ContentLength64 = bytes.Length; context.Response.OutputStream.Write(bytes, 0, bytes.Length); context.Response.Close();
        }
        catch { try { context.Response.Abort(); } catch { } }
    }
    public void Dispose() { try { _listener.Stop(); _listener.Close(); } catch { } }
}
'@
    }
    $script:Server = $null
    foreach ($candidate in 'http://127.0.0.1', 'http://localhost') {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start(); $port = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port; $probe.Stop()
        $server = [DepthFixtureServer]::new("${candidate}:$port/")
        try { $server.Start(); $script:Server = $server; $script:Base = "${candidate}:$port"; break } catch { $server.Dispose() }
    }
}

AfterAll {
    if ($null -ne $script:Server) { $script:Server.Dispose() }
    Remove-DepthStub
}

Describe 'Get-ScoutArmChildResource -- Front Door Standard / Premium: what is asked and what is kept' {

    It 'asks nothing without a Front Door profile, and nothing about a classic CDN profile' {
        Assert-DepthNothingAskedWithoutParent -Family $script:Family
    }

    It 'issues the documented request for every dataset: path, api-version, origins per origin group, routes per endpoint' {
        Assert-DepthDocumentedRequest -Family $script:Family
    }

    It 'carries no host name, probe path, private link target, route pattern, validation token or WAF association id' {
        Assert-DepthNoSecret -Family $script:Family
    }

    It 'leaves every dataset empty and unmeasured when every GET is denied, so a rule reads NotAssessed' {
        Assert-DepthDeniedIsNotMeasured -Family $script:Family
    }

    It 'treats an empty list as an answer: measured, no rows' {
        Assert-DepthEmptyIsAnAnswer -Family $script:Family
    }

    It 'retries a throttled request and does not report it as a failure' {
        Assert-DepthRetriesAThrottledRequest -Family $script:Family
    }

    It 'reads the origin list of a group as a sub-operation when only the second-level dataset is selected' {
        Install-DepthStub -Routes $script:Family.Routes
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset @('AfdOrigins')
        @($sweep.Rows).Count | Should -Be 3
        @($sweep.Operations | Where-Object { $_.Dataset -eq 'AfdOrigins.OriginGroups' }).Count | Should -Be 1 -Because 'the group list was asked once, under the dataset that needed it'
        @($sweep.Operations | Where-Object { $_.Dataset -eq 'AfdOrigins' }).Count | Should -Be 2 -Because 'one origin list per group'
    }

    It 'does not ask a profile''s origins when its origin-group list failed, and says so once' {
        Install-DepthStub -Routes $script:Family.Routes -Override { param($path) if ($path -like '*/originGroups') { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed"}}' } } }
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset @('AfdOriginGroups', 'AfdOrigins')
        @($sweep.Rows).Count | Should -Be 0
        @($script:StubCalls | Where-Object { $_ -match '/origins' }).Count | Should -Be 0
        @($sweep.Health | Where-Object { $_.Dataset -eq 'AfdOrigins' -and $_.Status -eq 'NotAssessed' }).Count | Should -Be 1
        (Get-DepthShaped -Sweep $sweep -Resources $script:Family.Parents).afdOriginsMeasured | Should -BeFalse
    }
}

Describe 'ConvertFrom-ScoutInventory -- Front Door datasets' {

    BeforeAll {
        Install-DepthStub -Routes $script:Family.Routes
        $script:Sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets
        $script:Shaped = Get-DepthShaped -Sweep $script:Sweep -Resources $script:Family.Parents
    }

    It 'sets every Measured flag when the datasets were answered' {
        foreach ($key in $script:Family.Keys) { $script:Shaped["${key}Measured"] | Should -BeTrue -Because $key }
    }

    It 'shapes origin groups with redundancy and probe facts joined from their origins' {
        $groups = @($script:Shaped.afdOriginGroups)
        $groups.Count | Should -Be 2
        $og1 = $groups | Where-Object name -eq 'og1'
        $og1.originCount | Should -Be 2
        $og1.enabledOriginCount | Should -Be 2
        $og1.privateLinkOriginCount | Should -Be 1
        $og1.hasRedundantOrigins | Should -BeTrue
        $og1.probeGap | Should -BeFalse
        $og1.healthProbeConfigured | Should -BeTrue
        $og1.probeRequestType | Should -Be 'HEAD'
        $og1.profileId | Should -Be $script:Family.Parents[0].id.ToLowerInvariant()
        $og2 = $groups | Where-Object name -eq 'og2'
        $og2.originCount | Should -Be 1
        $og2.hasRedundantOrigins | Should -BeFalse -Because 'one origin has nothing to fail over to'
        $og2.probeGap | Should -BeFalse -Because 'a probe only matters with two or more origins'
        $og2.healthProbeConfigured | Should -BeFalse
        $og2.sessionAffinityEnabled | Should -BeTrue
    }

    It 'reports a group whose origin list was not answered as not measured, never as having no origin' {
        Install-DepthStub -Routes $script:Family.Routes -Override { param($path) if ($path -like '*/originGroups/og1/origins') { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed"}}' } } }
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets
        $shaped = Get-DepthShaped -Sweep $sweep -Resources $script:Family.Parents
        $og1 = @($shaped.afdOriginGroups | Where-Object name -eq 'og1')[0]
        $og1.originCount | Should -BeNullOrEmpty
        $og1.hasRedundantOrigins | Should -BeNullOrEmpty -Because 'unknown is not false, so a rule reading == false skips it'
        $og1.probeGap | Should -BeNullOrEmpty
        (@($shaped.afdOriginGroups | Where-Object name -eq 'og2')[0]).originCount | Should -Be 1 -Because 'the other group was read'
        $shaped.afdOriginsMeasured | Should -BeTrue -Because 'one origin list was answered'
    }

    It 'shapes routes, custom domains and security policies into the booleans the rules read' {
        $r1 = @($script:Shaped.afdRoutes | Where-Object name -eq 'r1')[0]
        $r1.endpointName | Should -Be 'ep1'
        $r1.httpsRedirect | Should -BeTrue
        $r1.httpNotRedirected | Should -BeFalse
        $r1.forwardsOverHttpOnly | Should -BeFalse
        $r1.cacheConfigured | Should -BeTrue
        $r1.compressionEnabled | Should -BeTrue
        $r1.patternCount | Should -Be 1
        $r2 = @($script:Shaped.afdRoutes | Where-Object name -eq 'r2')[0]
        $r2.httpNotRedirected | Should -BeTrue
        $r2.forwardsOverHttpOnly | Should -BeTrue
        $r2.cacheConfigured | Should -BeFalse

        $cd1 = @($script:Shaped.afdCustomDomains | Where-Object name -eq 'cd1')[0]
        $cd1.tls12OrHigher | Should -BeTrue
        $cd1.managedCertificate | Should -BeTrue
        $cd1.validated | Should -BeTrue
        $cd2 = @($script:Shaped.afdCustomDomains | Where-Object name -eq 'cd2')[0]
        $cd2.tls12OrHigher | Should -BeFalse
        $cd2.managedCertificate | Should -BeFalse
        $cd2.azureDnsZoneSet | Should -BeTrue

        $policy = @($script:Shaped.afdSecurityPolicies)[0]
        $policy.policyType | Should -Be 'WebApplicationFirewall'
        $policy.wafPolicySet | Should -BeTrue
        $policy.associatedDomainCount | Should -Be 2
    }

    It 'mirrors every row under a real Front Door type for the discovery index' {
        $twins = @(ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows))
        $twins.Count | Should -Be @($script:Sweep.Rows).Count
        @($twins.type | Sort-Object -Unique) | Should -Be @(
            'microsoft.cdn/profiles/afdendpoints', 'microsoft.cdn/profiles/afdendpoints/routes', 'microsoft.cdn/profiles/customdomains',
            'microsoft.cdn/profiles/origingroups', 'microsoft.cdn/profiles/origingroups/origins', 'microsoft.cdn/profiles/securitypolicies')
        foreach ($twin in $twins) { $twin.AZSCDiscoveryTwin | Should -BeTrue; $twin.location | Should -Be 'eastus' }
    }
}

Describe 'Get-ScoutArmChildResource -- Front Door in parallel (including the second wave)' {

    BeforeAll {
        # The parallel transport sends with Invoke-WebRequest, so it needs a real listener; the routes are the same fixtures.
        $script:Token = 'SENTINEL-TOKEN-afd-71c2'
        $script:ParallelFamily = $script:Family
    }

    It 'produces the same rows, operations, health and warnings as the in-process sweep, and never leaks the token or a secret' {
        if ($null -eq $script:Server) { Set-ItResult -Skipped -Because 'no loopback HTTP listener could be started'; return }
        function New-Token { $s = [securestring]::new(); foreach ($c in $script:Token.ToCharArray()) { $s.AppendChar($c) }; $s }
        function ConvertTo-Comparable {
            param($Sweep)
            [pscustomobject]@{
                Rows       = @($Sweep.Rows | ForEach-Object { $copy = $_ | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $copy.AZSC.CollectedAt = $null; $copy | ConvertTo-Json -Depth 12 -Compress })
                Operations = @($Sweep.Operations | ForEach-Object { $_ | Select-Object -Property * -ExcludeProperty StartedAt, CompletedAt | ConvertTo-Json -Depth 6 -Compress })
                Health     = @($Sweep.Health | ForEach-Object { $_ | ConvertTo-Json -Depth 6 -Compress })
            }
        }
        foreach ($path in $script:Family.Routes.Keys) { $script:Server.Add($path, 200, $script:Family.Routes[$path].Body) }
        Install-DepthStub -Routes $script:Family.Routes

        $serial = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets -Arguments @{ Execution = 'InProcess' }
        $before = $script:Server.Requests
        $parallel = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets -Arguments @{ Execution = 'Parallel'; ManagementEndpoint = $script:Base; AccessToken = (New-Token) }
        ($script:Server.Requests - $before) | Should -Be 7 -Because 'the four first-level lists, then three second-level lists in the second wave'

        $a = ConvertTo-Comparable -Sweep $serial
        $b = ConvertTo-Comparable -Sweep $parallel
        # Source operations are applied in input order in both modes; rows are in the same order too.
        ($b.Rows -join "`n") | Should -Be ($a.Rows -join "`n")
        ($b.Operations -join "`n") | Should -Be ($a.Operations -join "`n")
        ($b.Health -join "`n") | Should -Be ($a.Health -join "`n")
        $everything = ($parallel | ConvertTo-Json -Depth 12)
        $everything | Should -Not -Match 'SENTINEL-TOKEN'
        foreach ($sentinel in $script:Family.Sentinels) { $everything | Should -Not -Match ([regex]::Escape($sentinel)) }
    }
}
