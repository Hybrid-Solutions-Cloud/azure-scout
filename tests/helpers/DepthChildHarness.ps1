# Shared harness for the depth child-resource tests (AB#9300, 3.18.20): tests/Collect.AfdChildResources.Tests.ps1,
# Collect.SqlChildResources.Tests.ps1, Collect.AzureLocalChildResources.Tests.ps1, Collect.MessagingChildResources.Tests.ps1,
# Collect.WebApimChildResources.Tests.ps1 and Collect.DepthDiscovery.Tests.ps1. No Azure connection, credential, tenant or
# subscription identifier is involved: Invoke-AzRestMethod is a stub that answers from a route table.
#
# A "family" (tests/helpers/DepthFamilyCases.ps1) is one service's parents, datasets, ARM responses -- every secret-bearing
# property carrying a SENTINEL -- and the request paths the sweep must make. The Assert-Depth* functions hold the contract
# every family shares; each family's test file adds what is particular to it.
Set-StrictMode -Version Latest

function New-DepthParent {
    # A Resource Graph row for a parent resource. $Path is what follows /subscriptions/sub1/resourceGroups/rg1/providers/.
    param([Parameter(Mandatory)][string]$Type, [Parameter(Mandatory)][string]$Path, [string]$Sku, [string]$Tier)
    $row = [pscustomobject]@{
        id             = "/subscriptions/sub1/resourceGroups/rg1/providers/$Path"
        name           = $Path.Split('/')[-1]
        type           = $Type
        location       = 'eastus'
        resourceGroup  = 'rg1'
        subscriptionId = 'sub1'
        properties     = [pscustomobject]@{}
    }
    if ($Sku) { $row | Add-Member -NotePropertyName sku -NotePropertyValue ([pscustomobject]@{ name = $Sku; tier = $(if ($Tier) { $Tier } else { $Sku }) }) }
    $row
}
function ConvertTo-DepthBody { param($Value) $Value | ConvertTo-Json -Depth 12 -Compress }

function Install-DepthStub {
    # Replace Invoke-AzRestMethod, Get-AzContext and Get-AzAccessToken with stubs. $Routes maps a request path WITHOUT its
    # query string to @{ Status; Body }; anything else answers 404. $Override sees (path, hitCount) and may answer first.
    param([hashtable]$Routes = @{}, [scriptblock]$Override)
    $script:StubRoutes = $Routes
    $script:StubOverride = $Override
    $script:StubCalls = [System.Collections.Generic.List[string]]::new()
    $script:StubHits = @{}
    function global:Invoke-AzRestMethod {
        [CmdletBinding()]
        param([string]$Path, [string]$Method, [string]$Uri)
        $null = $Method
        $request = if ($Path) { $Path } else { $Uri }
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
    function global:Get-AzContext { $null }
    function global:Get-AzAccessToken { throw 'no token in this test' }
}

function Remove-DepthStub {
    foreach ($name in 'Invoke-AzRestMethod', 'Get-AzContext', 'Get-AzAccessToken') { Remove-Item -Path "Function:\$name" -Force -ErrorAction SilentlyContinue }
}

function Invoke-DepthSweep {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resources, [Parameter(Mandatory)][string[]]$Dataset, [hashtable]$Arguments = @{})
    $health = [System.Collections.Generic.List[object]]::new()
    $operations = [System.Collections.Generic.List[object]]::new()
    $warnings = $null
    $rows = @(Get-ScoutArmChildResource -Resources $Resources -Dataset $Dataset -CollectionHealth $health `
            -SourceOperations $operations -WarningVariable warnings -WarningAction SilentlyContinue @Arguments)
    [pscustomobject]@{ Rows = $rows; Operations = @($operations); Health = @($health); Warnings = @($warnings | ForEach-Object { $_.Message }) }
}

function Get-DepthShaped {
    param([Parameter(Mandatory)]$Sweep, [Parameter(Mandatory)][object[]]$Resources)
    ConvertFrom-ScoutInventory -Resources (@($Resources) + @($Sweep.Rows)) -ResourceContainers @() -SourceOperations @($Sweep.Operations)
}

function Get-DepthRequestPath {
    # The distinct request paths the stub saw, relative to the subscription, without the query string.
    param()
    @($script:StubCalls | ForEach-Object { ($_ -split '\?')[0] } | Sort-Object -Unique)
}

# ---- the contract every family shares ------------------------------------------------------------------------------

function Assert-DepthNothingAskedWithoutParent {
    param([Parameter(Mandatory)]$Family)
    Install-DepthStub -Routes $Family.Routes
    foreach ($resources in @(@(), @($Family.Unrelated), @($Family.NotAsked))) {
        $script:StubCalls.Clear()
        $sweep = Invoke-DepthSweep -Resources @($resources | Where-Object { $null -ne $_ }) -Dataset $Family.Datasets
        $script:StubCalls.Count | Should -Be 0 -Because 'no parent the dataset can answer for, no request'
        @($sweep.Rows).Count | Should -Be 0
        @($sweep.Operations).Count | Should -Be 0
        @($sweep.Health).Count | Should -Be 0
    }
}

function Assert-DepthDocumentedRequest {
    param([Parameter(Mandatory)]$Family)
    Install-DepthStub -Routes $Family.Routes
    $sweep = Invoke-DepthSweep -Resources $Family.Parents -Dataset $Family.Datasets
    $paths = @(Get-DepthRequestPath | ForEach-Object { $_ -replace '^/subscriptions/sub1/resourceGroups/rg1/providers/', '' })
    $paths | Should -Be @($Family.ExpectedPaths | Sort-Object) -Because 'exactly the documented requests, one per parent (and per middle resource)'
    foreach ($call in $script:StubCalls) { $call | Should -Match "api-version=$([regex]::Escape($Family.ApiVersion))(&|$)" }
    # Every GET: the stub only answers GETs, and the sweep never POSTs (listKeys and the other credential actions).
    @($script:StubCalls | Where-Object { $_ -match '(?i)listkeys|listcredentials|/list\b|listsecrets|/regenerate' }).Count | Should -Be 0
    foreach ($dataset in $Family.Datasets) {
        @($sweep.Operations | Where-Object { $_.Dataset -eq $dataset -and $_.Status -in 'Success', 'Empty' }).Count | Should -BeGreaterThan 0 -Because "$dataset was answered"
    }
}

function Assert-DepthNoSecret {
    param([Parameter(Mandatory)]$Family)
    Install-DepthStub -Routes $Family.Routes
    $sweep = Invoke-DepthSweep -Resources $Family.Parents -Dataset $Family.Datasets
    $shaped = Get-DepthShaped -Sweep $sweep -Resources $Family.Parents
    $twins = @(ConvertTo-ScoutChildDiscoveryResource -Resources @($sweep.Rows))
    $surfaces = [ordered]@{
        rows       = ($sweep.Rows | ConvertTo-Json -Depth 12)
        operations = ($sweep.Operations | ConvertTo-Json -Depth 6)
        shaped     = ($shaped | ConvertTo-Json -Depth 10)
        twins      = ($twins | ConvertTo-Json -Depth 12)
    }
    @($sweep.Rows).Count | Should -BeGreaterThan 0
    foreach ($surface in $surfaces.Keys) {
        $surfaces[$surface] | Should -Match $Family.PositiveControl -Because "$surface must carry the positive control"
        foreach ($sentinel in $Family.Sentinels) {
            $surfaces[$surface] | Should -Not -Match ([regex]::Escape($sentinel)) -Because "$sentinel sits in a property the allow-list excludes (in $surface)"
        }
    }
}

function Assert-DepthDeniedIsNotMeasured {
    param([Parameter(Mandatory)]$Family)
    Install-DepthStub -Routes $Family.Routes -Override { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' } }
    $sweep = Invoke-DepthSweep -Resources $Family.Parents -Dataset $Family.Datasets
    @($sweep.Rows).Count | Should -Be 0
    @($sweep.Warnings).Count | Should -BeGreaterThan 0
    $shaped = Get-DepthShaped -Sweep $sweep -Resources $Family.Parents
    foreach ($key in $Family.Keys) {
        @($shaped[$key]).Count | Should -Be 0 -Because "$key has no row when every GET was denied"
        $shaped["${key}Measured"] | Should -BeFalse -Because "$key must read NotAssessed, never Pass, when nothing answered"
    }
}

function Assert-DepthEmptyIsAnAnswer {
    param([Parameter(Mandatory)]$Family)
    # Every route answers an empty list (or a 404): the questions were answered, the answer was "nothing there".
    $empty = @{}
    foreach ($path in $Family.Routes.Keys) { $empty[$path] = @{ Status = 200; Body = '{"value":[]}' } }
    Install-DepthStub -Routes $empty
    $sweep = Invoke-DepthSweep -Resources $Family.Parents -Dataset $Family.Datasets
    @($sweep.Rows).Count | Should -Be 0
    @($sweep.Warnings).Count | Should -Be 0
    $shaped = Get-DepthShaped -Sweep $sweep -Resources $Family.Parents
    foreach ($key in $Family.FirstLevelKeys) { $shaped["${key}Measured"] | Should -BeTrue -Because "an empty list for $key is an answer" }
}

function Assert-DepthRetriesAThrottledRequest {
    param([Parameter(Mandatory)]$Family)
    $first = (@($Family.Routes.Keys) | Sort-Object | Select-Object -First 1)
    Install-DepthStub -Routes $Family.Routes -Override ([scriptblock]::Create("param(`$path, `$hit) if (`$path -eq '$first' -and `$hit -eq 1) { [pscustomobject]@{ StatusCode = 429; Content = '{}' } }"))
    $sweep = Invoke-DepthSweep -Resources $Family.Parents -Dataset $Family.Datasets
    @($sweep.Warnings).Count | Should -Be 0 -Because 'a throttled request is retried, not reported as a failure'
    $script:StubHits[$first] | Should -BeGreaterThan 1
}
