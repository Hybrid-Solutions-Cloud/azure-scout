#Requires -Version 7.0
<#
.SYNOPSIS
    Refresh the committed catalogue of real Azure resource provider/type pairs.

.DESCRIPTION
    AB#6842. Ground truth for the resource-type existence gate, and the whole point is where it
    comes from: **Azure**, not the manifests.

    Scout's test fixtures are generated from each collector's own definition
    (`scripts/New-ScoutCollectorFixture.ps1`), so a collector declaring a resource type Azure
    does not have gets a fixture that agrees with it, and passes forever. `Hybrid/ArcSites`
    declared three such strings and passed every release. No amount of test-writing against the
    manifests can catch that class of defect, because the manifests are the thing under test.

    So this script reads the provider metadata from ARM and commits it. The gate
    (`tests/ResourceTypeExistence.Tests.ps1`) then runs offline on every pull request against
    the committed file — CI needs no Azure credentials, and the ground truth is still Azure's.

    The catalogue is tenant-independent: `Get-AzResourceProvider -ListAvailable` returns every
    provider ARM knows about, whether or not this subscription has registered it or owns a single
    resource of that type. That is exactly the property the gate needs, and it is why this check
    works on a tiny tenant when nothing else in the verification story does.

.PARAMETER Path
    Where to write. Defaults to `manifests/azure-provider-types.json`.

.EXAMPLE
    Connect-AzAccount
    ./scripts/Update-ScoutProviderCatalog.ps1

.NOTES
    Tracks ADO AB#6842 / AB#6772 (Epic AB#6731).

    REFRESH PROCEDURE: run this against any subscription in any tenant, commit the result, and
    say in the commit message when and against which API version. Refresh when a collector is
    added for a provider newer than the file's `GeneratedAt`, or when the gate reports a type
    you have independently confirmed is real.
#>
[CmdletBinding()]
param(
    [string] $Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Path)) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $Path = Join-Path $repoRoot 'manifests' 'azure-provider-types.json'
}

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) { throw 'Update-ScoutProviderCatalog: no Az context. Run Connect-AzAccount first.' }

Write-Host 'Reading resource providers from ARM...' -ForegroundColor Cyan
$providers = @(Get-AzResourceProvider -ListAvailable -ErrorAction Stop)
Write-Host "  $($providers.Count) providers" -ForegroundColor Cyan

$types = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($provider in $providers) {
    $ns = [string] $provider.ProviderNamespace
    if ([string]::IsNullOrWhiteSpace($ns)) { continue }
    foreach ($rt in @($provider.ResourceTypes)) {
        if ($null -eq $rt) { continue }
        $name = if ($rt.PSObject.Properties['ResourceTypeName']) { [string] $rt.ResourceTypeName } else { $null }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        # Stored lower-case because ARM resource types are case-insensitive and Scout's manifests
        # are inconsistent about casing -- comparing case-sensitively would report false unknowns.
        $null = $types.Add(("$ns/$name").ToLowerInvariant())
    }
}

Write-Host "  $($types.Count) provider/type pairs" -ForegroundColor Cyan

[PSCustomObject]@{
    Schema      = 'azure-scout/azure-provider-types/v1'
    GeneratedAt = (Get-Date).ToString('o')
    Source      = 'Get-AzResourceProvider -ListAvailable'
    Environment = [string] $context.Environment.Name
    ProviderCount = $providers.Count
    TypeCount   = $types.Count
    Types       = @($types)
} | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $Path -Encoding utf8

Write-Host "Wrote $Path" -ForegroundColor Green
