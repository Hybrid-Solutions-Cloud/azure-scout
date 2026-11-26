#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#9300, 3.18.19 -- the children of Azure VMware Solution private clouds, end to end.

    Resource Graph indexes a private cloud (microsoft.avs/privateclouds) but none of its children, so
    Get-ScoutArmChildResource reads thirteen datasets with ARM GETs, ConvertFrom-ScoutInventory shapes
    them under `domains.avs` and Invoke-Collect places them in collect.json. This file holds the
    properties that matter, stage by stage and together:

      1. NOTHING IS ASKED WHEN THERE IS NO PRIVATE CLOUD. Zero requests, zero rows, no health record.
      2. THE REQUESTS ARE THE DOCUMENTED ONES: path, api-version, and the per-cluster second step.
      3. NOTHING SECRET SURVIVES. Every response here carries a sentinel in each property the
         allow-list excludes (the SRM licence key, ExpressRoute authorization keys, the Global Reach
         peer circuit and key, a linked cloud id, storage target ids, host names, VM ids, IP ranges, NSX
         paths, DNS zone names); the serialised rows, the shaped datasets and the whole collect.json
         must contain none of them.
      4. THE MEASURED FLAGS TELL THE TRUTH. True only when a GET was answered; a private cloud whose
         list failed has no summary row, so it is never reported as lacking the thing.
      5. THE PARALLEL PATH (including the second, per-cluster wave) IS INDISTINGUISHABLE FROM THE
         IN-PROCESS ONE except for the clock.
      6. THE TYPED QUERY AND THE INVENTORY SHAPER AGREE on the private cloud's extended fields, and
         both paths expose one `domains.avs` contract.

    No Azure connection, credentials, tenant or subscription identifier is involved. Invoke-AzRestMethod,
    Search-AzGraph, Get-ScoutRawInventory and the two non-ARG sweeps are stubbed; the parallel path is
    exercised against a real HTTP listener on the loopback interface.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')

    if (-not ('AvsFixtureServer' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Threading;

public sealed class AvsFixtureServer : IDisposable
{
    private sealed class Route { public int Status; public string Body; }

    private readonly HttpListener _listener = new HttpListener();
    private readonly ConcurrentDictionary<string, Route> _routes = new ConcurrentDictionary<string, Route>(StringComparer.OrdinalIgnoreCase);
    private int _requests;
    private int _unauthorized;
    public string ExpectedAuthorization = "";

    public int Requests { get { return _requests; } }
    public int Unauthorized { get { return _unauthorized; } }

    public AvsFixtureServer(string prefix) { _listener.Prefixes.Add(prefix); }
    public void Add(string path, int status, string body) { _routes[path] = new Route { Status = status, Body = body }; }
    public void Reset() { _requests = 0; _unauthorized = 0; _routes.Clear(); }
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
        Interlocked.Increment(ref _requests);
        try
        {
            if (ExpectedAuthorization.Length > 0 && context.Request.Headers["Authorization"] != ExpectedAuthorization)
            {
                Interlocked.Increment(ref _unauthorized);
            }
            int status = 404;
            string body = "{\"error\":{\"code\":\"ResourceNotFound\",\"message\":\"no such route\"}}";
            Route route;
            if (_routes.TryGetValue(context.Request.Url.AbsolutePath, out route)) { status = route.Status; body = route.Body; }
            var bytes = Encoding.UTF8.GetBytes(body);
            context.Response.StatusCode = status;
            context.Response.ContentType = "application/json";
            context.Response.ContentLength64 = bytes.Length;
            context.Response.OutputStream.Write(bytes, 0, bytes.Length);
            context.Response.Close();
        }
        catch { try { context.Response.Abort(); } catch { } }
    }

    public void Dispose() { try { _listener.Stop(); _listener.Close(); } catch { } }
}
'@
    }

    $script:Token = 'SENTINEL-TOKEN-avs-5b21'
    $script:Server = $null
    foreach ($candidate in 'http://127.0.0.1', 'http://localhost') {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start(); $port = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port; $probe.Stop()
        $server = [AvsFixtureServer]::new("${candidate}:$port/")
        try { $server.Start(); $script:Server = $server; $script:Base = "${candidate}:$port"; break }
        catch { $server.Dispose() }
    }

    # A sentinel is planted in every property the allow-list excludes. None may reach a row.
    $script:Sentinels = @(
        'SENTINEL-LICENSE-001', 'SENTINEL-GRKEY-002', 'SENTINEL-PEER-003', 'SENTINEL-ERKEY-004',
        'SENTINEL-ERAUTH-005', 'SENTINEL-LINKED-006', 'SENTINEL-HOST-007', 'SENTINEL-NETAPP-008',
        'SENTINEL-DISKPOOL-009', 'SENTINEL-VM-010', 'SENTINEL-RANGE-011', 'SENTINEL-GATEWAY-012',
        'SENTINEL-DHCPSERVER-013', 'SENTINEL-DNSIP-014', 'SENTINEL-ZONE-015', 'SENTINEL-NSXPATH-016',
        'SENTINEL-ISCSI-017', 'SENTINEL-INFO-018', 'SENTINEL-HCXNET-019', 'SENTINEL-VCENTER-020',
        'SENTINEL-ERID-021', 'SENTINEL-SEGPORT-022', 'SENTINEL-CMKNAME-023'
    )

    function New-AvsCloud {
        param([string]$Name, [string]$Strategy, [int]$ClusterSize)
        [pscustomobject]@{
            id             = "/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.AVS/privateClouds/$Name"
            name           = $Name
            type           = 'microsoft.avs/privateclouds'
            location       = 'eastus'
            resourceGroup  = 'rg1'
            subscriptionId = 'sub1'
            sku            = [pscustomobject]@{ name = 'av36' }
            identity       = [pscustomobject]@{ type = 'SystemAssigned' }
            properties     = [pscustomobject]@{
                availability      = [pscustomobject]@{ strategy = $Strategy; zone = 1; secondaryZone = $(if ($Strategy -eq 'DualZone') { 2 } else { $null }) }
                managementCluster = [pscustomobject]@{ clusterSize = $ClusterSize }
                circuit           = [pscustomobject]@{ expressRouteID = '/subscriptions/sub1/resourceGroups/x/providers/Microsoft.Network/expressroutecircuits/c1' }
                provisioningState = 'Succeeded'
            }
        }
    }
    # pc-stretched: DualZone, so every cluster needs 6 hosts. pc-single: SingleZone, so 3.
    $script:Stretched = New-AvsCloud -Name 'pc-stretched' -Strategy 'DualZone' -ClusterSize 6
    $script:Single = New-AvsCloud -Name 'pc-single' -Strategy 'SingleZone' -ClusterSize 3
    $script:Clouds = @($script:Stretched, $script:Single)
    $script:Storage = [pscustomobject]@{
        id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/st1'
        name = 'st1'; type = 'microsoft.storage/storageaccounts'; kind = 'StorageV2'; location = 'eastus'
        resourceGroup = 'rg1'; subscriptionId = 'sub1'; properties = [pscustomobject]@{}
    }
    # AB#9300, 3.18.20 -- the depth datasets the assessment collect also asks for, after the AVS ones.
    $script:DepthDatasets = @(
        'AfdOriginGroups', 'AfdOrigins', 'AfdEndpoints', 'AfdRoutes', 'AfdCustomDomains', 'AfdSecurityPolicies',
        'SqlDatabaseBackupShortTerm', 'SqlDatabaseBackupLongTerm', 'SqlDatabaseTde',
        'SqlServerFirewallRules', 'SqlServerEncryptionProtector', 'SqlServerSecurityAlertPolicies',
        'AzureLocalUpdateSummaries', 'AzureLocalSecuritySettings', 'AzureLocalArcSettings',
        'EventHubNetworkRuleSets', 'EventHubAuthorizationRules', 'EventHubEntities',
        'ServiceBusNetworkRuleSets', 'ServiceBusAuthorizationRules', 'ServiceBusQueues', 'ServiceBusTopics',
        'WebAppAuth', 'ApimGlobalPolicy', 'ApimApis', 'ApimNamedValues'
    )
    $script:AvsDatasets = @(
        'AvsClusters', 'AvsDatastores', 'AvsPlacementPolicies', 'AvsAddons', 'AvsGlobalReachConnections',
        'AvsAuthorizations', 'AvsCloudLinks', 'AvsSegments', 'AvsDhcpConfigurations', 'AvsDnsServices',
        'AvsGateways', 'AvsIscsiPaths', 'AvsMaintenances'
    )

    # path (no query) -> @{ Status; Body }. Every dataset, both clouds, every secret-bearing neighbour.
    function Get-AvsRouteTable {
        $routes = [ordered]@{}
        $list = { param($items) (@{ value = @($items) } | ConvertTo-Json -Depth 12 -Compress) }

        $stretched = $script:Stretched.id
        $single = $script:Single.id

        # ---- pc-stretched: four hosts short of the stretched minimum on Cluster-2 ----
        $routes["$stretched/clusters"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/clusters/Cluster-1"; name = 'Cluster-1'; type = 'Microsoft.AVS/privateClouds/clusters'; sku = @{ name = 'AV36' }
                        properties = @{ clusterSize = 6; hosts = @('SENTINEL-HOST-007-a', 'SENTINEL-HOST-007-b'); provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/clusters/Cluster-2"; name = 'Cluster-2'; type = 'Microsoft.AVS/privateClouds/clusters'; sku = @{ name = 'AV36' }
                        properties = @{ clusterSize = 4; hosts = @('SENTINEL-HOST-007-c'); provisioningState = 'Succeeded' } })) }
        $routes["$stretched/clusters/Cluster-1/datastores"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/clusters/Cluster-1/datastores/ds-anf"; name = 'ds-anf'; type = 'Microsoft.AVS/privateClouds/clusters/datastores'
                        properties = @{ netAppVolume = @{ id = '/x/SENTINEL-NETAPP-008' }; status = 'Accessible'; provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/clusters/Cluster-1/datastores/ds-pool"; name = 'ds-pool'; type = 'Microsoft.AVS/privateClouds/clusters/datastores'
                        properties = @{ diskPoolVolume = @{ targetId = '/x/SENTINEL-DISKPOOL-009'; lunName = 'lun0'; path = '/x/SENTINEL-DISKPOOL-009' }; status = 'Inaccessible'; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/clusters/Cluster-2/datastores"] = @{ Status = 200; Body = (& $list @()) }
        $routes["$stretched/clusters/Cluster-1/placementPolicies"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/clusters/Cluster-1/placementPolicies/p1"; name = 'p1'; type = 'Microsoft.AVS/privateClouds/clusters/placementPolicies'
                        properties = @{ type = 'VmHost'; state = 'Enabled'; displayName = 'SENTINEL-VM-010-name'; affinityType = 'AntiAffinity'; affinityStrength = 'Must'
                            azureHybridBenefitType = 'SqlHost'; vmMembers = @('/x/SENTINEL-VM-010-a', '/x/SENTINEL-VM-010-b'); hostMembers = @('SENTINEL-HOST-007-d'); provisioningState = 'Succeeded' } })) }
        $routes["$stretched/clusters/Cluster-2/placementPolicies"] = @{ Status = 200; Body = (& $list @()) }
        $routes["$stretched/addons"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/addons/srm"; name = 'srm'; type = 'Microsoft.AVS/privateClouds/addons'; properties = @{ addonType = 'SRM'; licenseKey = 'SENTINEL-LICENSE-001'; provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/addons/vr"; name = 'vr'; type = 'Microsoft.AVS/privateClouds/addons'; properties = @{ addonType = 'VR'; vrsCount = 2; provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/addons/hcx"; name = 'hcx'; type = 'Microsoft.AVS/privateClouds/addons'
                        properties = @{ addonType = 'HCX'; offer = 'VMware MaaS Cloud Provider (Enterprise)'; managementNetwork = '10.0.0.0/24'; uplinkNetwork = 'SENTINEL-HCXNET-019'; provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/addons/arc"; name = 'arc'; type = 'Microsoft.AVS/privateClouds/addons'; properties = @{ addonType = 'Arc'; vCenter = '/x/SENTINEL-VCENTER-020'; provisioningState = 'Building' } })) }
        $routes["$stretched/globalReachConnections"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/globalReachConnections/gr1"; name = 'gr1'; type = 'Microsoft.AVS/privateClouds/globalReachConnections'
                        properties = @{ addressPrefix = '10.2.3.16/29'; authorizationKey = 'SENTINEL-GRKEY-002'; circuitConnectionStatus = 'Connected'
                            expressRouteId = '/x/SENTINEL-ERID-021'; peerExpressRouteCircuit = '/x/SENTINEL-PEER-003'; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/authorizations"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/authorizations/a1"; name = 'a1'; type = 'Microsoft.AVS/privateClouds/authorizations'
                        properties = @{ expressRouteAuthorizationKey = 'SENTINEL-ERKEY-004'; expressRouteAuthorizationId = '/x/SENTINEL-ERAUTH-005'; expressRouteId = '/x/SENTINEL-ERID-021'; provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/authorizations/a2"; name = 'a2'; type = 'Microsoft.AVS/privateClouds/authorizations'
                        properties = @{ expressRouteAuthorizationKey = 'SENTINEL-ERKEY-004'; provisioningState = 'Failed' } })) }
        $routes["$stretched/cloudLinks"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/cloudLinks/l1"; name = 'l1'; type = 'Microsoft.AVS/privateClouds/cloudLinks'; properties = @{ status = 'Active'; linkedCloud = '/x/SENTINEL-LINKED-006'; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/workloadNetworks/default/segments"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/workloadNetworks/default/segments/s1"; name = 's1'; type = 'Microsoft.AVS/privateClouds/workloadNetworks/segments'
                        properties = @{ displayName = 's1'; connectedGateway = '/infra/tier-1s/SENTINEL-NSXPATH-016'; status = 'SUCCESS'
                            subnet = @{ dhcpRanges = @('SENTINEL-RANGE-011-a', 'SENTINEL-RANGE-011-b'); gatewayAddress = 'SENTINEL-GATEWAY-012' }
                            portVif = @(@{ portName = 'SENTINEL-SEGPORT-022' }); provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/workloadNetworks/default/segments/s2"; name = 's2'; type = 'Microsoft.AVS/privateClouds/workloadNetworks/segments'
                        properties = @{ displayName = 's2'; status = 'FAILURE'; subnet = @{ gatewayAddress = 'SENTINEL-GATEWAY-012' }; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/workloadNetworks/default/dhcpConfigurations"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/workloadNetworks/default/dhcpConfigurations/d1"; name = 'd1'; type = 'Microsoft.AVS/privateClouds/workloadNetworks/dhcpConfigurations'
                        properties = @{ dhcpType = 'SERVER'; serverAddress = 'SENTINEL-DHCPSERVER-013'; segments = @('s1', 's2'); provisioningState = 'Succeeded' } }
                    @{ id = "$stretched/workloadNetworks/default/dhcpConfigurations/d2"; name = 'd2'; type = 'Microsoft.AVS/privateClouds/workloadNetworks/dhcpConfigurations'
                        properties = @{ dhcpType = 'RELAY'; serverAddresses = @('SENTINEL-DHCPSERVER-013'); segments = @('s1'); provisioningState = 'Succeeded' } })) }
        $routes["$stretched/workloadNetworks/default/dnsServices"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/workloadNetworks/default/dnsServices/dns1"; name = 'dns1'; type = 'Microsoft.AVS/privateClouds/workloadNetworks/dnsServices'
                        properties = @{ dnsServiceIp = 'SENTINEL-DNSIP-014'; defaultDnsZone = 'SENTINEL-ZONE-015'; fqdnZones = @('SENTINEL-ZONE-015'); logLevel = 'INFO'; status = 'SUCCESS'; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/workloadNetworks/default/gateways"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/workloadNetworks/default/gateways/gw1"; name = 'gw1'; type = 'Microsoft.AVS/privateClouds/workloadNetworks/gateways'
                        properties = @{ displayName = 'gw1'; path = '/infra/tier-1s/SENTINEL-NSXPATH-016'; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/iscsiPaths"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/iscsiPaths/default"; name = 'default'; type = 'Microsoft.AVS/privateClouds/iscsiPaths'; properties = @{ networkBlock = 'SENTINEL-ISCSI-017'; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/maintenances"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/maintenances/m1"; name = 'm1'; type = 'Microsoft.AVS/privateClouds/maintenances'
                        properties = @{ component = 'ESXI'; displayName = 'ESXi 8.0 update'; infoLink = 'SENTINEL-INFO-018'; scheduledByMicrosoft = $true; scheduledStartTime = '2026-12-01T02:00:00Z'
                            estimatedDurationInMinutes = 240; state = @{ name = 'Scheduled' }; maintenanceReadiness = @{ status = 'Ready' }; provisioningState = 'Succeeded' } })) }
        $routes["$stretched/providers/Microsoft.Insights/diagnosticSettings"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$stretched/providers/Microsoft.Insights/diagnosticSettings/toLaw"; name = 'toLaw'; properties = @{ workspaceId = 'law'; logs = @(@{ category = 'vmwaresyslog'; enabled = $true }) } })) }

        # ---- pc-single: nothing configured, workload network not built yet ----
        $routes["$single/clusters"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$single/clusters/Cluster-1"; name = 'Cluster-1'; type = 'Microsoft.AVS/privateClouds/clusters'; sku = @{ name = 'AV36' }
                        properties = @{ clusterSize = 3; hosts = @('SENTINEL-HOST-007-e'); provisioningState = 'Succeeded' } })) }
        $routes["$single/clusters/Cluster-1/datastores"] = @{ Status = 200; Body = (& $list @(
                    @{ id = "$single/clusters/Cluster-1/datastores/ds-san"; name = 'ds-san'; type = 'Microsoft.AVS/privateClouds/clusters/datastores'
                        properties = @{ elasticSanVolume = @{ targetId = '/x/SENTINEL-NETAPP-008' }; status = 'Accessible'; provisioningState = 'Succeeded' } })) }
        $routes["$single/clusters/Cluster-1/placementPolicies"] = @{ Status = 200; Body = (& $list @()) }
        foreach ($segment in 'addons', 'globalReachConnections', 'authorizations', 'cloudLinks', 'iscsiPaths', 'maintenances', 'providers/Microsoft.Insights/diagnosticSettings') {
            $routes["$single/$segment"] = @{ Status = 200; Body = (& $list @()) }
        }
        foreach ($segment in 'segments', 'dhcpConfigurations', 'dnsServices', 'gateways') {
            $routes["$single/workloadNetworks/default/$segment"] = @{ Status = 404; Body = '{"error":{"code":"ResourceNotFound","message":"workload network not found"}}' }
        }
        $routes
    }

    function Install-AvsStub {
        param([System.Collections.IDictionary]$Routes, [scriptblock]$Override)
        $script:StubRoutes = $Routes
        $script:StubOverride = $Override
        $script:StubCalls = [System.Collections.Generic.List[string]]::new()
        $script:StubHits = @{}
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Uri, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Method, $Rest
            $request = if ($Uri) { $Uri } else { $Path }
            $script:StubCalls.Add($request)
            $clean = ($request -split '\?')[0]
            $script:StubHits[$clean] = 1 + [int]$script:StubHits[$clean]
            if ($null -ne $script:StubOverride) {
                $answer = & $script:StubOverride $clean $script:StubHits[$clean]
                if ($null -ne $answer) { return $answer }
            }
            $route = $script:StubRoutes[$clean]
            if ($null -eq $route) { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound","message":"no such route"}}' } }
            [pscustomobject]@{ StatusCode = [int]$route.Status; Content = [string]$route.Body }
        }
    }

    function Invoke-AvsSweep {
        param([object[]]$Resources = $script:Clouds, [string[]]$Dataset = $script:AvsDatasets, [hashtable]$Arguments = @{})
        $health = [System.Collections.Generic.List[object]]::new()
        $operations = [System.Collections.Generic.List[object]]::new()
        $warnings = $null
        $rows = @(Get-ScoutArmChildResource -Resources $Resources -Dataset $Dataset -CollectionHealth $health `
                -SourceOperations $operations -WarningVariable warnings -WarningAction SilentlyContinue @Arguments)
        [pscustomobject]@{ Rows = $rows; Operations = @($operations); Health = @($health); Warnings = @($warnings | ForEach-Object { $_.Message }) }
    }

    function Get-AvsShaped {
        param($Sweep, [object[]]$Resources = $script:Clouds)
        ConvertFrom-ScoutInventory -Resources (@($Resources) + @($Sweep.Rows)) -ResourceContainers @() -SourceOperations @($Sweep.Operations)
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

    function New-Token {
        $secure = [securestring]::new()
        foreach ($character in $script:Token.ToCharArray()) { $secure.AppendChar($character) }
        $secure
    }
}

AfterAll {
    if ($null -ne $script:Server) { $script:Server.Dispose() }
    foreach ($name in 'Invoke-AzRestMethod', 'Get-AzContext', 'Get-AzAccessToken') {
        Remove-Item -Path "Function:\$name" -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-ScoutArmChildResource -- Azure VMware Solution: what is asked' {

    It 'asks nothing at all when there is no private cloud, for any of the thirteen datasets or for All' {
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $named = Invoke-AvsSweep -Resources @($script:Storage)
        $script:StubCalls.Count | Should -Be 0
        @($named.Rows).Count | Should -Be 0
        @($named.Operations).Count | Should -Be 0
        @($named.Health).Count | Should -Be 0

        # Under All the other datasets do ask (a storage account is in scope), but never for AVS.
        $script:StubCalls.Clear()
        $null = Invoke-AvsSweep -Resources @($script:Storage) -Dataset @('All')
        $script:StubCalls.Count | Should -BeGreaterThan 0 -Because 'the positive control: other datasets do read the storage account'
        @($script:StubCalls | Where-Object { $_ -match '(?i)Microsoft\.AVS' }).Count | Should -Be 0

        $script:StubCalls.Clear()
        $null = Invoke-AvsSweep -Resources @() -Dataset @('All')
        $script:StubCalls.Count | Should -Be 0
    }

    It 'asks nothing about a private cloud for a dataset that was not selected' {
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $null = Invoke-AvsSweep -Dataset @('AvsAddons')
        $script:StubCalls | Should -Be @(
            "$($script:Stretched.id)/addons?api-version=2025-09-01"
            "$($script:Single.id)/addons?api-version=2025-09-01"
        )
    }

    It 'issues the documented request for every dataset: path, api-version, one list per private cloud and per cluster' {
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $null = Invoke-AvsSweep
        $v = 'api-version=2025-09-01'
        $s = $script:Stretched.id
        $g = $script:Single.id

        $script:StubCalls | Should -Be @(
            # AvsClusters, then AvsDatastores and AvsPlacementPolicies per cluster (the cluster list is reused)
            "$s/clusters?$v", "$g/clusters?$v"
            "$s/clusters/Cluster-1/datastores?$v", "$s/clusters/Cluster-2/datastores?$v", "$g/clusters/Cluster-1/datastores?$v"
            "$s/clusters/Cluster-1/placementPolicies?$v", "$s/clusters/Cluster-2/placementPolicies?$v", "$g/clusters/Cluster-1/placementPolicies?$v"
            "$s/addons?$v", "$g/addons?$v"
            "$s/globalReachConnections?$v", "$g/globalReachConnections?$v"
            "$s/authorizations?$v", "$g/authorizations?$v"
            "$s/cloudLinks?$v", "$g/cloudLinks?$v"
            "$s/workloadNetworks/default/segments?$v", "$g/workloadNetworks/default/segments?$v"
            "$s/workloadNetworks/default/dhcpConfigurations?$v", "$g/workloadNetworks/default/dhcpConfigurations?$v"
            "$s/workloadNetworks/default/dnsServices?$v", "$g/workloadNetworks/default/dnsServices?$v"
            "$s/workloadNetworks/default/gateways?$v", "$g/workloadNetworks/default/gateways?$v"
            "$s/iscsiPaths?$v", "$g/iscsiPaths?$v"
            "$s/maintenances?$v", "$g/maintenances?$v"
        )
    }

    It 'asks the cluster list itself, as a sub-operation of the dataset, when the cluster dataset was not selected' {
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $sweep = Invoke-AvsSweep -Dataset @('AvsDatastores', 'AvsPlacementPolicies')
        # One cluster list per private cloud, shared by both per-cluster datasets.
        @($script:StubCalls | Where-Object { $_ -match '/clusters\?' }).Count | Should -Be 2
        @($script:StubCalls).Count | Should -Be (2 + 3 + 3)
        @($sweep.Operations | Where-Object { $_.Dataset -eq 'AvsDatastores.Clusters' }).Count | Should -Be 2
        @($sweep.Operations | Where-Object { $_.Dataset -eq 'AvsPlacementPolicies.Clusters' }).Count | Should -Be 0 -Because 'the second dataset reuses the first one''s answer'
        @($sweep.Rows | Where-Object TYPE -eq 'AZSC/ARMChild/AvsDatastores').Count | Should -Be 3
    }

    It 'adds the private cloud to the diagnostic-settings sweep, one GET each' {
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $sweep = Invoke-AvsSweep -Dataset @('ResourceDiagnosticSettings')
        $script:StubCalls | Should -Be @(
            "$($script:Stretched.id)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
            "$($script:Single.id)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
        )
        @($sweep.Rows).Count | Should -Be 1 -Because 'only the private cloud with a setting yields a row; the other answered an empty list'
        $sweep.Rows[0].PARENTTYPE | Should -Be 'microsoft.avs/privateclouds'
    }

    It 'never POSTs, never lists credentials, and never reads a Key Vault' {
        $code = ((Get-Content (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')) |
                Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $code | Should -Not -Match '(?i)listAdminCredentials|listCredentials|rotateVcenterPassword|rotateNsxtPassword|/hcxEnterpriseSites|/scriptExecutions|/listKeys'
    }
}

Describe 'Get-ScoutArmChildResource -- Azure VMware Solution: what is kept' {

    BeforeAll {
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $script:Sweep = Invoke-AvsSweep
        $script:Json = $script:Sweep.Rows | ConvertTo-Json -Depth 12
        $script:ByType = { param($type) @($script:Sweep.Rows | Where-Object TYPE -eq "AZSC/ARMChild/$type") }
    }

    It 'carries no secret, key, circuit id, address, host, member id or path in any row' {
        foreach ($sentinel in $script:Sentinels) {
            $script:Json | Should -Not -Match ([regex]::Escape($sentinel)) -Because "$sentinel sits in a property the allow-list excludes"
        }
        # Positive control: the planted payloads were read, so the absence above is the projection's doing.
        $script:Json | Should -Match 'Connected'
        $script:Json | Should -Match 'ESXI'
        @($script:Sweep.Rows).Count | Should -BeGreaterThan 20
    }

    It 'stamps the private cloud on every row, and reads nothing but the allow-listed fields' {
        foreach ($row in $script:Sweep.Rows) {
            $row.PARENTTYPE | Should -Be 'microsoft.avs/privateclouds'
            $row.PARENTID | Should -Match '/privateClouds/pc-(stretched|single)$'
            $row.PARENTLOCATION | Should -Be 'eastus'
            $row.AZSC.ApiVersion | Should -Be '2025-09-01'
            $row.AZSC.Source | Should -Be 'Azure Resource Manager'
        }
        $allowed = @{
            AvsClusters = 'clusterSize', 'provisioningState', 'hostCount', 'skuName'
            AvsDatastores = 'status', 'provisioningState', 'kind', 'clusterName'
            AvsPlacementPolicies = 'type', 'state', 'affinityType', 'affinityStrength', 'azureHybridBenefitType', 'provisioningState', 'vmMemberCount', 'hostMemberCount', 'clusterName'
            AvsAddons = 'addonType', 'provisioningState', 'offer', 'vrsCount'
            AvsGlobalReachConnections = 'circuitConnectionStatus', 'provisioningState', 'peerCircuitPresent'
            AvsAuthorizations = 'provisioningState'
            AvsCloudLinks = 'status', 'provisioningState', 'linkedCloudPresent'
            AvsSegments = 'status', 'provisioningState', 'connectedGatewaySet', 'dhcpRangeCount', 'portCount'
            AvsDhcpConfigurations = 'dhcpType', 'provisioningState', 'segmentCount'
            AvsDnsServices = 'logLevel', 'status', 'provisioningState', 'fqdnZoneCount', 'defaultZoneSet'
            AvsGateways = 'provisioningState'
            AvsIscsiPaths = 'provisioningState', 'networkBlockSet'
            AvsMaintenances = 'component', 'state', 'scheduledByMicrosoft', 'provisioningState', 'maintenanceReadiness', 'estimatedDurationInMinutes', 'scheduledStartTime'
        }
        foreach ($dataset in $allowed.Keys) {
            $rows = & $script:ByType $dataset
            $rows.Count | Should -BeGreaterThan 0 -Because "$dataset must yield rows for the check to mean something"
            foreach ($row in $rows) {
                @($row.properties.PSObject.Properties.Name | Where-Object { $_ -notin $allowed[$dataset] }) | Should -BeNullOrEmpty -Because "$dataset keeps only its allow-list"
            }
        }
    }

    It 'reduces members, hosts, peers and ranges to counts and booleans' {
        $cluster = (& $script:ByType 'AvsClusters') | Where-Object name -eq 'Cluster-1' | Select-Object -First 1
        $cluster.properties.hostCount | Should -Be 2
        $cluster.properties.skuName | Should -Be 'AV36'

        $datastores = & $script:ByType 'AvsDatastores'
        @($datastores | Where-Object name -eq 'ds-anf')[0].properties.kind | Should -Be 'NetApp'
        @($datastores | Where-Object name -eq 'ds-pool')[0].properties.kind | Should -Be 'DiskPool'
        @($datastores | Where-Object name -eq 'ds-san')[0].properties.kind | Should -Be 'ElasticSan'

        $policy = (& $script:ByType 'AvsPlacementPolicies')[0]
        $policy.properties.vmMemberCount | Should -Be 2
        $policy.properties.hostMemberCount | Should -Be 1
        $policy.properties.type | Should -Be 'VmHost'

        (& $script:ByType 'AvsGlobalReachConnections')[0].properties.peerCircuitPresent | Should -BeTrue
        (& $script:ByType 'AvsCloudLinks')[0].properties.linkedCloudPresent | Should -BeTrue

        $segments = & $script:ByType 'AvsSegments'
        $s1 = @($segments | Where-Object name -eq 's1')[0]
        $s1.properties.dhcpRangeCount | Should -Be 2
        $s1.properties.portCount | Should -Be 1
        $s1.properties.connectedGatewaySet | Should -BeTrue
        @($segments | Where-Object name -eq 's2')[0].properties.dhcpRangeCount | Should -Be 0

        @(& $script:ByType 'AvsDhcpConfigurations' | Where-Object name -eq 'd1')[0].properties.segmentCount | Should -Be 2
        $dns = (& $script:ByType 'AvsDnsServices')[0]
        $dns.properties.fqdnZoneCount | Should -Be 1
        $dns.properties.defaultZoneSet | Should -BeTrue
        (& $script:ByType 'AvsIscsiPaths')[0].properties.networkBlockSet | Should -BeTrue

        $maintenance = (& $script:ByType 'AvsMaintenances')[0]
        $maintenance.properties.state.name | Should -Be 'Scheduled'
        $maintenance.properties.scheduledStartTime | Should -Be '2026-12-01T02:00:00.0000000Z'
        $maintenance.properties.scheduledByMicrosoft | Should -BeTrue
    }

    It 'treats a missing workload network as an empty answer, not a failure' {
        $script:Sweep.Warnings.Count | Should -Be 0
        @($script:Sweep.Health).Count | Should -Be 0
        @($script:Sweep.Operations | Where-Object { $_.Status -eq 'Empty' -and $_.Uri -match 'pc-single/workloadNetworks' }).Count | Should -Be 4
    }
}

Describe 'ConvertFrom-ScoutInventory -- Azure VMware Solution datasets' {

    BeforeAll {
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $script:Sweep = Invoke-AvsSweep
        $script:Shaped = Get-AvsShaped -Sweep $script:Sweep
    }

    It 'sets every Measured flag when the datasets were answered' {
        foreach ($dataset in $script:AvsDatasets) {
            $script:Shaped["$($dataset.Substring(0, 1).ToLowerInvariant())$($dataset.Substring(1))Measured"] | Should -BeTrue -Because $dataset
        }
    }

    It 'holds every cluster to the minimum for its availability strategy: 6 for a stretched cloud, 3 otherwise' {
        $clusters = @($script:Shaped.avsClusters)
        $clusters.Count | Should -Be 3
        $byName = { param($cloud, $name) @($clusters | Where-Object { $_.privateCloudName -eq $cloud -and $_.name -eq $name })[0] }

        $stretchedOk = & $byName 'pc-stretched' 'Cluster-1'
        $stretchedOk.clusterSize | Should -Be 6
        $stretchedOk.minimumHosts | Should -Be 6
        $stretchedOk.belowMinimumHosts | Should -BeFalse

        $stretchedShort = & $byName 'pc-stretched' 'Cluster-2'
        $stretchedShort.clusterSize | Should -Be 4
        $stretchedShort.availabilityStrategy | Should -Be 'DualZone'
        $stretchedShort.belowMinimumHosts | Should -BeTrue -Because '4 hosts is fine for a standard cloud and short for a stretched one'

        $single = & $byName 'pc-single' 'Cluster-1'
        $single.minimumHosts | Should -Be 3
        $single.belowMinimumHosts | Should -BeFalse
        $single.privateCloudId | Should -Be $script:Single.id.ToLowerInvariant()
    }

    It 'reads a cluster with no size at all as unknown, not as below the minimum' {
        $row = [pscustomobject]@{
            id = "$($script:Single.id)/clusters/C9"; name = 'C9'; type = 'AZSC/ARMChild/AvsClusters'
            PARENTID = $script:Single.id; PARENTNAME = 'pc-single'; PARENTTYPE = 'microsoft.avs/privateclouds'
            subscriptionId = 'sub1'; RESOURCEGROUP = 'rg1'; properties = [pscustomobject]@{ provisioningState = 'Succeeded' }
        }
        $shaped = ConvertFrom-ScoutInventory -Resources @($script:Single, $row) -ResourceContainers @() -SourceOperations @()
        $shaped.avsClusters[0].belowMinimumHosts | Should -BeNullOrEmpty
        $shaped.avsClustersMeasured | Should -BeFalse -Because 'no source operation says the cluster list was answered'
    }

    It 'keeps datastores, placement policies and maintenances as one row per child' {
        @($script:Shaped.avsDatastores).Count | Should -Be 3
        $inaccessible = @($script:Shaped.avsDatastores | Where-Object { $_.accessible -eq $false })
        $inaccessible.Count | Should -Be 1
        $inaccessible[0].kind | Should -Be 'DiskPool'
        $inaccessible[0].clusterName | Should -Be 'Cluster-1'
        @($script:Shaped.avsDatastores | Where-Object kind -eq 'ElasticSan').Count | Should -Be 1

        @($script:Shaped.avsPlacementPolicies).Count | Should -Be 1
        $script:Shaped.avsPlacementPolicies[0].enabled | Should -BeTrue
        $script:Shaped.avsPlacementPolicies[0].policyType | Should -Be 'VmHost'
        $script:Shaped.avsPlacementPolicies[0].vmMemberCount | Should -Be 2

        @($script:Shaped.avsMaintenances).Count | Should -Be 1
        $script:Shaped.avsMaintenances[0].component | Should -Be 'ESXI'
        $script:Shaped.avsMaintenances[0].state | Should -Be 'Scheduled'
        $script:Shaped.avsMaintenances[0].scheduledByMicrosoft | Should -BeTrue
    }

    It 'summarises the add-ons per private cloud, and reports a cloud with none as having none' {
        $stretched = @($script:Shaped.avsAddons | Where-Object name -eq 'pc-stretched')[0]
        $stretched.addonCount | Should -Be 4
        $stretched.srmEnabled | Should -BeTrue
        $stretched.vrEnabled | Should -BeTrue
        $stretched.vrsCount | Should -Be 2
        $stretched.hcxEnabled | Should -BeTrue
        $stretched.hcxOffer | Should -Be 'VMware MaaS Cloud Provider (Enterprise)'
        $stretched.arcEnabled | Should -BeFalse -Because 'the Arc add-on is still Building, not provisioned'

        $single = @($script:Shaped.avsAddons | Where-Object name -eq 'pc-single')[0]
        $single.addonCount | Should -Be 0
        $single.srmEnabled | Should -BeFalse
        $single.hcxEnabled | Should -BeFalse
    }

    It 'counts Global Reach connections, authorizations, cloud links and the workload network' {
        $gr = @($script:Shaped.avsGlobalReachConnections | Where-Object name -eq 'pc-stretched')[0]
        $gr.connectionCount | Should -Be 1
        $gr.connectedCount | Should -Be 1
        $gr.peerCircuitCount | Should -Be 1
        @($script:Shaped.avsGlobalReachConnections | Where-Object name -eq 'pc-single')[0].connectedCount | Should -Be 0

        $auth = @($script:Shaped.avsAuthorizations | Where-Object name -eq 'pc-stretched')[0]
        $auth.authorizationCount | Should -Be 2
        $auth.failedCount | Should -Be 1
        @($script:Shaped.avsAuthorizations | Where-Object name -eq 'pc-single')[0].authorizationCount | Should -Be 0

        $links = @($script:Shaped.avsCloudLinks | Where-Object name -eq 'pc-stretched')[0]
        $links.linkCount | Should -Be 1
        $links.activeCount | Should -Be 1

        $segments = @($script:Shaped.avsSegments | Where-Object name -eq 'pc-stretched')[0]
        $segments.segmentCount | Should -Be 2
        $segments.failedSegmentCount | Should -Be 1
        $segments.dhcpSegmentCount | Should -Be 1
        $segments.connectedSegmentCount | Should -Be 1

        $dhcp = @($script:Shaped.avsDhcpConfigurations | Where-Object name -eq 'pc-stretched')[0]
        $dhcp.configurationCount | Should -Be 2
        $dhcp.serverCount | Should -Be 1
        $dhcp.relayCount | Should -Be 1

        @($script:Shaped.avsDnsServices | Where-Object name -eq 'pc-stretched')[0].serviceCount | Should -Be 1
        @($script:Shaped.avsGateways | Where-Object name -eq 'pc-stretched')[0].gatewayCount | Should -Be 1
        @($script:Shaped.avsIscsiPaths | Where-Object name -eq 'pc-stretched')[0].pathCount | Should -Be 1
    }

    It 'gives the private cloud whose workload network is missing a row of zeros, because the 404 was an answer' {
        $single = @($script:Shaped.avsSegments | Where-Object name -eq 'pc-single')[0]
        $single.segmentCount | Should -Be 0
        @($script:Shaped.avsDnsServices | Where-Object name -eq 'pc-single')[0].serviceCount | Should -Be 0
    }

    It 'carries no secret into any shaped dataset' {
        $json = ($script:Shaped.Keys | Where-Object { $_ -like 'avs*' } | ForEach-Object { $script:Shaped[$_] } | ConvertTo-Json -Depth 12)
        $json | Should -Match 'pc-stretched' -Because 'the positive control: there is output to scan'
        foreach ($sentinel in $script:Sentinels) { $json | Should -Not -Match ([regex]::Escape($sentinel)) }
    }

    It 'shapes nothing and measures nothing for an estate with no private cloud' {
        $empty = ConvertFrom-ScoutInventory -Resources @($script:Storage) -ResourceContainers @() -SourceOperations @()
        foreach ($dataset in $script:AvsDatasets) {
            $key = "$($dataset.Substring(0, 1).ToLowerInvariant())$($dataset.Substring(1))"
            @($empty[$key]).Count | Should -Be 0 -Because $key
            $empty["${key}Measured"] | Should -BeFalse -Because $key
        }
    }
}

Describe 'Azure VMware Solution -- when a GET does not answer' {

    It 'leaves every dataset empty, unmeasured and warned about when every GET is denied' {
        $denied = { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' } }
        Install-AvsStub -Routes (Get-AvsRouteTable) -Override $denied
        $sweep = Invoke-AvsSweep
        @($sweep.Rows).Count | Should -Be 0
        $shaped = Get-AvsShaped -Sweep $sweep
        foreach ($dataset in $script:AvsDatasets) {
            $key = "$($dataset.Substring(0, 1).ToLowerInvariant())$($dataset.Substring(1))"
            @($shaped[$key]).Count | Should -Be 0 -Because $key
            $shaped["${key}Measured"] | Should -BeFalse -Because "$key had no answered GET"
        }
        # One health record per dataset that has no answer. The eleven per-private-cloud lists failed
        # (Unavailable); the two per-cluster datasets were never asked, because the cluster list they
        # depend on was not answered (NotAssessed).
        @($sweep.Health | Where-Object Status -eq 'Unavailable').Count | Should -Be 11
        @(@($sweep.Health | Where-Object Status -eq 'NotAssessed').Dataset | Sort-Object) | Should -Be @('AvsDatastores', 'AvsPlacementPolicies')
        @($sweep.Health.Dataset | Sort-Object) | Should -Be @($script:AvsDatasets | Sort-Object)
        $sweep.Warnings.Count | Should -BeGreaterThan 12
    }

    It 'does not ask for datastores of a private cloud whose cluster list failed, and leaves them unmeasured' {
        $clustersDenied = {
            param($path)
            if ($path -match '/clusters$') { return [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' } }
        }
        Install-AvsStub -Routes (Get-AvsRouteTable) -Override $clustersDenied
        $sweep = Invoke-AvsSweep -Dataset @('AvsClusters', 'AvsDatastores', 'AvsPlacementPolicies')
        @($script:StubCalls | Where-Object { $_ -match '/clusters/' }).Count | Should -Be 0
        @($sweep.Rows).Count | Should -Be 0
        $shaped = Get-AvsShaped -Sweep $sweep
        $shaped.avsClustersMeasured | Should -BeFalse
        $shaped.avsDatastoresMeasured | Should -BeFalse
        $shaped.avsPlacementPoliciesMeasured | Should -BeFalse
        @($sweep.Health | Where-Object Status -eq 'Unavailable').Dataset | Should -Be @('AvsClusters')
        @(@($sweep.Health | Where-Object Status -eq 'NotAssessed').Dataset | Sort-Object) | Should -Be @('AvsDatastores', 'AvsPlacementPolicies')
    }

    It 'gives a private cloud whose list failed no summary row, so it is never reported as lacking the thing' {
        $pcSingleAddonsDenied = {
            param($path)
            if ($path -match 'pc-single/addons$') { return [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' } }
        }
        Install-AvsStub -Routes (Get-AvsRouteTable) -Override $pcSingleAddonsDenied
        $sweep = Invoke-AvsSweep -Dataset @('AvsAddons')
        $shaped = Get-AvsShaped -Sweep $sweep
        $shaped.avsAddonsMeasured | Should -BeTrue -Because 'one private cloud answered'
        @($shaped.avsAddons).Count | Should -Be 1
        $shaped.avsAddons[0].name | Should -Be 'pc-stretched'
        @($shaped.avsAddons | Where-Object name -eq 'pc-single') | Should -BeNullOrEmpty
        @($sweep.Health).Count | Should -Be 1
        $sweep.Health[0].Status | Should -Be 'Unavailable'
        $sweep.Health[0].ResourceTypes | Should -Be @('AZSC/ARMChild/AvsAddons')
    }

    It 'treats an empty list as an answer: measured, with a count of zero' {
        $empty = { [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' } }
        Install-AvsStub -Routes (Get-AvsRouteTable) -Override $empty
        $sweep = Invoke-AvsSweep
        @($sweep.Rows).Count | Should -Be 0
        $sweep.Warnings.Count | Should -Be 0
        $shaped = Get-AvsShaped -Sweep $sweep
        foreach ($dataset in $script:AvsDatasets | Where-Object { $_ -notin 'AvsDatastores', 'AvsPlacementPolicies' }) {
            $shaped["$($dataset.Substring(0, 1).ToLowerInvariant())$($dataset.Substring(1))Measured"] | Should -BeTrue -Because $dataset
        }
        # No cluster exists to hold a datastore or a placement policy, so no GET of either was made.
        $shaped.avsDatastoresMeasured | Should -BeFalse
        $shaped.avsPlacementPoliciesMeasured | Should -BeFalse
        @($shaped.avsClusters).Count | Should -Be 0
        @($shaped.avsAddons | Where-Object name -eq 'pc-stretched')[0].srmEnabled | Should -BeFalse
        @($shaped.avsAddons | Where-Object name -eq 'pc-stretched')[0].addonCount | Should -Be 0
    }

    It 'retries a throttled request and honours the answer that follows' {
        $throttleOnce = {
            param($path, $hit)
            if ($path -match 'pc-stretched/addons$' -and $hit -eq 1) {
                return [pscustomobject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = '1' } }
            }
        }
        Install-AvsStub -Routes (Get-AvsRouteTable) -Override $throttleOnce
        $sweep = Invoke-AvsSweep -Dataset @('AvsAddons')
        $script:StubHits["$($script:Stretched.id)/addons"] | Should -Be 2
        $sweep.Warnings.Count | Should -Be 0
        @($sweep.Health).Count | Should -Be 0
        @($sweep.Rows | Where-Object PARENTNAME -eq 'pc-stretched').Count | Should -Be 4
    }

    It 'follows nextLink so a paged cluster list is not cut off after page one' {
        # The second page is a different URL with the same path, so it is told apart by the hit count.
        $paged = {
            param($path, $hit)
            if ($path -notmatch 'pc-single/clusters$') { return $null }
            $page = if ($hit -eq 1) {
                @{ value = @(@{ id = "$($script:Single.id)/clusters/Cluster-1"; name = 'Cluster-1'; properties = @{ clusterSize = 3 } })
                    nextLink = "$($script:Single.id)/clusters?api-version=2025-09-01&`$skiptoken=p2" }
            }
            else {
                @{ value = @(@{ id = "$($script:Single.id)/clusters/Cluster-2"; name = 'Cluster-2'; properties = @{ clusterSize = 3 } }) }
            }
            [pscustomobject]@{ StatusCode = 200; Content = ($page | ConvertTo-Json -Depth 8 -Compress) }
        }
        Install-AvsStub -Routes (Get-AvsRouteTable) -Override $paged
        $sweep = Invoke-AvsSweep -Resources @($script:Single) -Dataset @('AvsClusters')
        @($sweep.Rows.name | Sort-Object) | Should -Be @('Cluster-1', 'Cluster-2')
    }
}

Describe 'Get-ScoutArmChildResource -- Azure VMware Solution in parallel' {

    BeforeAll {
        function Set-ServerRouteTable {
            $script:Server.Reset()
            $script:Server.ExpectedAuthorization = "Bearer $script:Token"
            $routes = Get-AvsRouteTable
            foreach ($path in $routes.Keys) { $script:Server.Add($path, [int]$routes[$path].Status, [string]$routes[$path].Body) }
        }
    }

    It 'produces the same rows, source operations, health and warnings as the in-process path, including the per-cluster wave' {
        if ($null -eq $script:Server) { Set-ItResult -Skipped -Because 'a loopback HTTP listener could not be started on this host'; return }
        Set-ServerRouteTable
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $sequential = Invoke-AvsSweep -Arguments @{ Execution = 'InProcess' }
        $script:Server.Requests | Should -Be 0 -Because 'the in-process run must not touch the network'
        $expectedRequests = $script:StubCalls.Count
        $script:StubCalls.Clear()

        $parallel = Invoke-AvsSweep -Arguments @{ Execution = 'Parallel'; ManagementEndpoint = $script:Base; AccessToken = (New-Token); ThrottleLimit = 8 }
        # Exactly the requests the in-process run made: the second wave's answers were used, not re-fetched,
        # and nothing fell back to the in-process transport.
        $script:Server.Requests | Should -Be $expectedRequests
        $script:StubCalls.Count | Should -Be 0
        $script:Server.Unauthorized | Should -Be 0

        @($sequential.Rows).Count | Should -BeGreaterThan 20
        @($sequential.Operations.Status | Sort-Object -Unique) | Should -Contain 'Empty'
        $a = ConvertTo-Comparable $sequential
        $b = ConvertTo-Comparable $parallel
        $b.Rows | Should -Be $a.Rows
        $b.Operations | Should -Be $a.Operations
        $b.Health | Should -Be $a.Health
        $b.Warnings | Should -Be $a.Warnings
    }

    It 'never lets the token or a planted secret reach a row, operation, health record or warning' {
        if ($null -eq $script:Server) { Set-ItResult -Skipped -Because 'a loopback HTTP listener could not be started on this host'; return }
        Set-ServerRouteTable
        $sweep = Invoke-AvsSweep -Arguments @{ Execution = 'Parallel'; ManagementEndpoint = $script:Base; AccessToken = (New-Token) }
        $everything = (@($sweep.Rows) + @($sweep.Operations) + @($sweep.Health) + @($sweep.Warnings) | ConvertTo-Json -Depth 12)
        $everything | Should -Match 'pc-stretched'
        $everything | Should -Not -Match ([regex]::Escape($script:Token))
        $everything | Should -Not -Match 'Bearer '
        foreach ($sentinel in $script:Sentinels) { $everything | Should -Not -Match ([regex]::Escape($sentinel)) }
    }

    It 'makes no request, and acquires no token, for an estate with no private cloud' {
        if ($null -eq $script:Server) { Set-ItResult -Skipped -Because 'a loopback HTTP listener could not be started on this host'; return }
        Set-ServerRouteTable
        $rows = @(Get-ScoutArmChildResource -Resources @($script:Storage) -Dataset $script:AvsDatasets -Execution Parallel `
                -ManagementEndpoint $script:Base -AccessToken (New-Token))
        $rows.Count | Should -Be 0
        $script:Server.Requests | Should -Be 0
    }
}

Describe 'Azure VMware Solution children are discoverable (collection health and the discovery index)' {

    BeforeAll {
        . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1')
        . (Join-Path -Path $script:Root -ChildPath 'src/pipeline/Get-ScoutResourceCompleteness.ps1')
        Install-AvsStub -Routes (Get-AvsRouteTable)
        $script:Sweep = Invoke-AvsSweep
        $script:Twins = @(ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows))
        $script:Catalogue = @((Get-Content (Join-Path -Path $script:Root -ChildPath 'manifests/azure-provider-types.json') -Raw | ConvertFrom-Json).Types)
    }

    It 'mirrors every swept child under a real ARM type that Azure''s provider catalogue lists' {
        $script:Twins.Count | Should -Be @($script:Sweep.Rows).Count
        $types = @($script:Twins.type | Sort-Object -Unique)
        $types.Count | Should -Be 13 -Because 'one real type per dataset'
        foreach ($type in $types) { $script:Catalogue | Should -Contain $type -Because "$type is a Microsoft.AVS resource type" }
        foreach ($twin in $script:Twins) {
            $twin.AZSCDiscoveryTwin | Should -BeTrue
            $twin.id | Should -Match '/privateClouds/pc-(stretched|single)/'
            $twin.location | Should -Be 'eastus'
            $twin.subscriptionId | Should -Be 'sub1'
        }
    }

    It 'adds nothing for an estate with no private cloud, and ignores every other synthetic row' {
        @(ConvertTo-ScoutChildDiscoveryResource -Resources @()).Count | Should -Be 0
        $other = [pscustomobject]@{ id = '/x/y'; name = 'y'; type = 'AZSC/ARMChild/StorageBlobContainers'; properties = [pscustomobject]@{} }
        @(ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Storage, $other)).Count | Should -Be 0
    }

    It 'lists every child in the discovery index, filed under Compute, which no AZSC row would be on its own' {
        $withoutTwins = New-ScoutResourceDiscovery -Resources (@($script:Clouds) + @($script:Sweep.Rows))
        $withoutTwins.Resources.Count | Should -Be 2 -Because 'an AZSC row is enrichment of a base resource with its id, so alone it is never indexed'

        $discovery = New-ScoutResourceDiscovery -Resources (@($script:Clouds) + @($script:Sweep.Rows) + @($script:Twins))
        $discovery.Resources.Count | Should -Be (2 + $script:Twins.Count)
        $children = @($discovery.Resources | Where-Object Type -like 'microsoft.avs/privateclouds/*')
        $children.Count | Should -Be $script:Twins.Count
        @($children.Category | Sort-Object -Unique) | Should -Be @('Compute')
        @($children.CategorySource | Sort-Object -Unique) | Should -Be @('Namespace')
        @($children | Where-Object { @($_.Enrichment).Count -ne 1 }).Count | Should -Be 0 -Because 'the AZSC row attaches to its twin as enrichment'
        $discovery.Summary.Uncategorized | Should -Be 0
    }

    It 'carries no secret into the discovery index' {
        $discovery = New-ScoutResourceDiscovery -Resources (@($script:Clouds) + @($script:Sweep.Rows) + @($script:Twins))
        $json = $discovery | ConvertTo-Json -Depth 12
        $json | Should -Match 'Cluster-1' -Because 'the positive control'
        foreach ($sentinel in $script:Sentinels) { $json | Should -Not -Match ([regex]::Escape($sentinel)) }
    }

    It 'leaves the shaped datasets the same whichever order the twin and its AZSC row arrive in' {
        $forward = ConvertFrom-ScoutInventory -Resources (@($script:Clouds) + @($script:Sweep.Rows) + @($script:Twins)) -ResourceContainers @() -SourceOperations @($script:Sweep.Operations)
        $reverse = ConvertFrom-ScoutInventory -Resources (@($script:Twins) + @($script:Clouds) + @($script:Sweep.Rows)) -ResourceContainers @() -SourceOperations @($script:Sweep.Operations)
        $baseline = Get-AvsShaped -Sweep $script:Sweep
        foreach ($key in $baseline.Keys | Where-Object { $_ -like 'avs*' }) {
            ($forward[$key] | ConvertTo-Json -Depth 8) | Should -Be ($baseline[$key] | ConvertTo-Json -Depth 8) -Because $key
            ($reverse[$key] | ConvertTo-Json -Depth 8) | Should -Be ($baseline[$key] | ConvertTo-Json -Depth 8) -Because $key
        }
    }

    It 'is wired into the raw inventory, the collection-health parent map and the category plan' {
        $raw = Get-Content (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutRawInventory.ps1') -Raw
        $raw | Should -Match "Import-ScoutRawInventoryHelper -CommandName 'ConvertTo-ScoutChildDiscoveryResource' -FileName 'ConvertTo-ScoutChildDiscoveryResource.ps1'"
        $raw.IndexOf('ConvertTo-ScoutChildDiscoveryResource -Resources') | Should -BeGreaterThan $raw.IndexOf('Get-ScoutArmChildResource -Resources') -Because 'the twins are appended after the AZSC rows'
        $plan = Get-Content (Join-Path -Path $script:Root -ChildPath 'src/Start-AZTIExtractionOrchestration.ps1') -Raw
        foreach ($dataset in $script:AvsDatasets) {
            $raw | Should -Match ("'azsc/armchild/{0}' = @\('microsoft\.avs/privateclouds'\)" -f $dataset.ToLowerInvariant()) -Because "$dataset's health must map to its parent"
            $plan | Should -Match "'$dataset'" -Because "$dataset is a supported ARM-child dataset"
        }
        $raw | Should -Match "(?s)'azsc/armchild/resourcediagnosticsettings' = @\(.*?'microsoft\.avs/privateclouds'\s*\)"
    }
}

Describe 'The private cloud extended fields: typed query and inventory shaper agree' {

    BeforeAll {
        $script:CollectCode = Get-Content (Join-Path -Path $script:Root -ChildPath 'src/collect/Invoke-Collect.ps1') -Raw
        $query = [regex]::Match($script:CollectCode, "(?s)privateClouds = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
        $projectBlock = [regex]::Match($query, '(?s)\| project (.*)$').Groups[1].Value
        $script:KqlColumns = @(
            $projectBlock -split ',' | ForEach-Object { ($_ -split '=')[0].Trim() } | Where-Object { $_ }
        ) | Sort-Object
        $script:KqlQuery = $query

        $cloud = [pscustomobject]@{
            id = $script:Stretched.id; name = 'pc-stretched'; type = 'microsoft.avs/privateclouds'; resourceGroup = 'rg1'; subscriptionId = 'sub1'
            sku = [pscustomobject]@{ name = 'av36' }; identity = [pscustomobject]@{ type = 'SystemAssigned'; principalId = 'SENTINEL-CMKNAME-023' }
            properties = [pscustomobject]@{
                availability = [pscustomobject]@{ strategy = 'DualZone'; zone = 1; secondaryZone = 2 }
                managementCluster = [pscustomobject]@{ clusterSize = 6 }
                circuit = [pscustomobject]@{ expressRouteID = '/x/c1' }
                secondaryCircuit = [pscustomobject]@{ expressRouteID = '/x/c2' }
                encryption = [pscustomobject]@{
                    status = 'Enabled'
                    keyVaultProperties = [pscustomobject]@{ keyName = 'SENTINEL-CMKNAME-023'; keyVaultUrl = 'https://SENTINEL-CMKNAME-023.vault.azure.net/'; keyVersion = 'v1'; keyState = 'Connected'; versionType = 'Fixed' }
                }
                internet = 'Disabled'; identitySources = @(@{ name = 'ad'; password = 'SENTINEL-CMKNAME-023' }); externalCloudLinks = @()
                provisioningState = 'Succeeded'; dnsZoneType = 'Private'; extendedNetworkBlocks = @('SENTINEL-CMKNAME-023/22', '10.1.0.0/22')
                nsxPublicIpQuotaRaised = 'Enabled'; virtualNetworkId = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/virtualNetworks/SENTINEL-CMKNAME-023'
                vcenterPassword = 'SENTINEL-CMKNAME-023'; nsxtPassword = 'SENTINEL-CMKNAME-023'
            }
        }
        $script:ShapedCloud = (ConvertFrom-ScoutInventory -Resources @($cloud) -ResourceContainers @()).privateClouds[0]
    }

    It 'projects exactly the columns the shaper produces' {
        @($script:KqlColumns).Count | Should -BeGreaterThan 20
        @($script:ShapedCloud.PSObject.Properties.Name | Sort-Object) | Should -Be @($script:KqlColumns)
    }

    It 'shapes the extended fields as scalars, counts and booleans' {
        $script:ShapedCloud.availabilitySecondaryZone | Should -Be '2'
        $script:ShapedCloud.secondaryCircuitPresent | Should -BeTrue
        $script:ShapedCloud.encryptionStatus | Should -Be 'Enabled'
        $script:ShapedCloud.encryptionKeyState | Should -Be 'Connected'
        $script:ShapedCloud.encryptionKeyVersionType | Should -Be 'Fixed'
        $script:ShapedCloud.provisioningState | Should -Be 'Succeeded'
        $script:ShapedCloud.dnsZoneType | Should -Be 'Private'
        $script:ShapedCloud.extendedNetworkBlockCount | Should -Be 2
        $script:ShapedCloud.nsxPublicIpQuotaRaised | Should -Be 'Enabled'
        $script:ShapedCloud.virtualNetworkIdSet | Should -BeTrue
        $script:ShapedCloud.identityType | Should -Be 'SystemAssigned'
    }

    It 'reports an absent optional block as empty or false, never as a value it did not read' {
        $bare = [pscustomobject]@{
            id = $script:Single.id; name = 'pc-single'; type = 'microsoft.avs/privateclouds'; resourceGroup = 'rg1'; subscriptionId = 'sub1'
            sku = $null; properties = [pscustomobject]@{}
        }
        $shaped = (ConvertFrom-ScoutInventory -Resources @($bare) -ResourceContainers @()).privateClouds[0]
        $shaped.secondaryCircuitPresent | Should -BeFalse
        $shaped.virtualNetworkIdSet | Should -BeFalse
        $shaped.encryptionStatus | Should -BeExactly ''
        $shaped.encryptionKeyState | Should -BeExactly ''
        $shaped.extendedNetworkBlockCount | Should -BeNullOrEmpty
        $shaped.identityType | Should -BeExactly ''
    }

    It 'projects no secret-bearing, addressing or key-identifying column' {
        $script:KqlColumns | Should -Not -Contain 'vcenterPassword'
        $script:KqlColumns | Should -Not -Contain 'nsxtPassword'
        $script:KqlQuery | Should -Not -Match '(?i)password|licenseKey|vcfLicense|thumbprint|endpoints|\.networkBlock\b|\.keyVaultUrl\b|\.keyName\b|\.keyVersion\b|managementNetwork|provisioningNetwork|vmotionNetwork'
        $json = $script:ShapedCloud | ConvertTo-Json -Depth 6
        $json | Should -Not -Match 'SENTINEL-CMKNAME-023'
    }
}

Describe 'Invoke-Collect -- Azure VMware Solution in collect.json' {

    BeforeAll {
        function Import-Module {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet so Invoke-Collect does not import Az modules during the test.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must accept whatever arguments the code under test passes.')]
            param([Parameter(ValueFromRemainingArguments)] $Rest)
        }
        function Get-ScoutDefenderPlanSweep {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
            param([object[]] $Subscriptions)
            return @()
        }
        function Get-ScoutExternalIdentitiesPolicy {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
            param([string] $TenantID)
            return [pscustomobject]@{ Collected = $false }
        }
        function Search-AzGraph {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            return @()
        }
        . (Join-Path -Path $script:Root -ChildPath 'src/collect/Invoke-Collect.ps1')

        # The raw pass is stubbed, but the ARM-child collector inside it is the real one, so what comes
        # back is exactly what a live run would hand to Invoke-Collect.
        function global:Get-ScoutRawInventory {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature; only the ARM-child parameters are used.')]
            param([switch] $IncludeArmChildResources, [string[]] $ArmChildDataset, [Parameter(ValueFromRemainingArguments)] $Rest)
            $script:CapturedArmChildDataset = $ArmChildDataset
            $health = [System.Collections.Generic.List[object]]::new()
            $operations = [System.Collections.Generic.List[object]]::new()
            $children = @(Get-ScoutArmChildResource -Resources $script:RawParents -Dataset $ArmChildDataset `
                    -CollectionHealth $health -SourceOperations $operations -WarningAction SilentlyContinue)
            [pscustomobject]@{
                Resources          = @($script:RawParents) + $children
                ResourceContainers = @()
                SourceOperations   = @($operations)
                CollectionHealth   = @($health)
            }
        }
    }

    AfterAll {
        Remove-Item -Path 'Function:\Get-ScoutRawInventory' -Force -ErrorAction SilentlyContinue
    }

    Context 'two private clouds, every GET answered' {
        BeforeAll {
            $script:RawParents = @($script:Stretched, $script:Single, $script:Storage)
            Install-AvsStub -Routes (Get-AvsRouteTable)
            $script:Collect = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
            $script:CollectJson = $script:Collect | ConvertTo-Json -Depth 20
        }

        It 'asks the assessment collect for all thirteen datasets, after the existing ten, then the depth datasets' {
            @($script:CapturedArmChildDataset) | Should -Be (@(
                    'ResourceDiagnosticSettings'
                    'StorageBlobServiceProperties', 'StorageFileServiceProperties', 'StorageLifecyclePolicies'
                    'SqlServerAuditing', 'SqlFailoverGroups'
                    'WebAppConfig', 'WebAppBasicAuth'
                    'EventHubGeoDr', 'RedisEnterpriseDatabases'
                ) + $script:AvsDatasets + $script:DepthDatasets)
        }

        It 'places every dataset and its Measured flag under domains.avs' {
            $avs = $script:Collect.domains.avs
            foreach ($dataset in $script:AvsDatasets) {
                $key = "$($dataset.Substring(3, 1).ToLowerInvariant())$($dataset.Substring(4))"
                $avs.PSObject.Properties.Name | Should -Contain $key
                $avs.PSObject.Properties.Name | Should -Contain "${key}Measured"
                $avs."${key}Measured" | Should -BeTrue -Because $key
            }
            @($avs.clusters).Count | Should -Be 3
            @($avs.clusters | Where-Object belowMinimumHosts -eq $true).Count | Should -Be 1
            @($avs.addons | Where-Object srmEnabled -eq $true).Count | Should -Be 1
            @($avs.globalReachConnections | Where-Object connectedCount -gt 0).Count | Should -Be 1
        }

        It 'carries the private cloud extended fields on compute.privateClouds' {
            $cloud = @($script:Collect.compute.privateClouds | Where-Object name -eq 'pc-stretched')[0]
            $cloud.availabilitySecondaryZone | Should -Be '2'
            $cloud.identityType | Should -Be 'SystemAssigned'
            $cloud.virtualNetworkIdSet | Should -BeFalse
        }

        It 'puts the private cloud in the diagnostic coverage' {
            $script:Collect.opsPosture.diagnosticCoverageMeasured | Should -BeTrue
            $row = @($script:Collect.opsPosture.diagnosticCoverage | Where-Object type -eq 'microsoft.avs/privateclouds')[0]
            $row.total | Should -Be 2
            $row.withDiag | Should -Be 1
            $row.coveragePct | Should -Be 50
        }

        It 'carries no secret, key, address or identifier anywhere in the serialised collect' {
            foreach ($sentinel in $script:Sentinels) {
                $script:CollectJson | Should -Not -Match ([regex]::Escape($sentinel)) -Because "$sentinel sits in a property the allow-list excludes"
            }
            $script:CollectJson | Should -Match 'pc-stretched' -Because 'the positive control'
        }
    }

    Context 'every GET denied' {
        BeforeAll {
            $script:RawParents = @($script:Stretched, $script:Single)
            Install-AvsStub -Routes (Get-AvsRouteTable) -Override { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' } }
            $script:Denied = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'leaves every dataset empty and every Measured flag false, so a rule reports NotAssessed' {
            $avs = $script:Denied.domains.avs
            foreach ($property in $avs.PSObject.Properties) {
                if ($property.Name -like '*Measured') { $property.Value | Should -BeFalse -Because $property.Name }
                else { @($property.Value).Count | Should -Be 0 -Because $property.Name }
            }
            @($script:Denied.compute.privateClouds).Count | Should -Be 2 -Because 'the private clouds themselves come from Resource Graph, not the sweep'
        }
    }

    Context 'no private cloud in the estate' {
        BeforeAll {
            $script:RawParents = @($script:Storage)
            Install-AvsStub -Routes (Get-AvsRouteTable)
            $script:NoAvs = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'asks nothing about AVS and declares the section empty and unmeasured' {
            @($script:StubCalls | Where-Object { $_ -match '(?i)Microsoft\.AVS' }).Count | Should -Be 0
            foreach ($property in $script:NoAvs.domains.avs.PSObject.Properties) {
                if ($property.Name -like '*Measured') { $property.Value | Should -BeFalse -Because $property.Name }
                else { @($property.Value).Count | Should -Be 0 -Because $property.Name }
            }
        }
    }

    Context 'the typed-query path (no ARM-child sweep)' {
        BeforeAll {
            Remove-Item -Path 'Function:\Get-ScoutRawInventory' -Force -ErrorAction SilentlyContinue
            $script:Typed = Invoke-Collect -Source TypedQueries -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'declares the same domains.avs keys as the inventory path, empty and unmeasured' {
            $script:Typed.domains.avs.PSObject.Properties.Name | Should -Be $script:Collect.domains.avs.PSObject.Properties.Name
            foreach ($property in $script:Typed.domains.avs.PSObject.Properties) {
                if ($property.Name -like '*Measured') { $property.Value | Should -BeFalse -Because $property.Name }
                else { @($property.Value).Count | Should -Be 0 -Because $property.Name }
            }
        }
    }
}

Describe 'The Azure VMware Solution allow-list stays an allow-list' {

    BeforeAll {
        # Comment lines are stripped: the file explains what it must never read, and a scan over the
        # raw text would flag that explanation as the offence.
        $script:CollectorCode = (
            Get-Content (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1') |
                Where-Object { $_ -notmatch '^\s*#' }
        ) -join "`n"
        $script:AllowList = [regex]::Match($script:CollectorCode, '(?s)\$SafeChildPropertyPaths = @\{.*?\r?\n    \}').Value
    }

    It 'lists no key, licence, circuit, target, address, member or path' {
        $script:AllowList | Should -Match 'AvsAddons'
        foreach ($forbidden in 'licenseKey', 'authorizationKey', 'expressRouteAuthorizationKey', 'expressRouteAuthorizationId',
            'peerExpressRouteCircuit', 'expressRouteId', 'addressPrefix', 'linkedCloud', 'hosts', 'vmMembers', 'hostMembers',
            'netAppVolume', 'diskPoolVolume', 'elasticSanVolume', 'pureStorageVolume', 'subnet', 'gatewayAddress', 'dhcpRanges',
            'portVif', 'serverAddress', 'dnsServiceIp', 'defaultDnsZone', 'fqdnZones', 'path', 'networkBlock', 'displayName',
            'infoLink', 'managementNetwork', 'uplinkNetwork', 'vCenter', 'connectedGateway', 'peerCircuit') {
            $script:AllowList | Should -Not -Match "'$forbidden" -Because "$forbidden must never be an allow-listed path"
        }
    }
}
