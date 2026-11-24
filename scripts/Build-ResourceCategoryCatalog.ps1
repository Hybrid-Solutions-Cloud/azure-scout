#Requires -Version 7.0
<#
.SYNOPSIS
    Regenerate docs/reference/resource-categories.md from manifests/resource-categories.psd1
    (AB#9300).

.DESCRIPTION
    The page lists every Azure resource provider namespace and the AzureScout category its
    resources are filed under, plus the type-level entries for namespaces that span categories.
    tests/Discovery.ResourceCategories.Tests.ps1 fails when the committed page differs from what
    this script would write, so the page cannot drift from the map.

.PARAMETER OutputPath
    Defaults to docs/reference/resource-categories.md.

.PARAMETER PassThru
    Return the page text instead of writing it.
#>
[CmdletBinding()]
param(
    [string] $OutputPath,
    [switch] $PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'docs/reference/resource-categories.md' }
$map = Import-PowerShellDataFile -LiteralPath (Join-Path $repoRoot 'manifests/resource-categories.psd1')
$labels = @{ AI = 'AI + Machine Learning'; Hybrid = 'Hybrid + multicloud'; IoT = 'Internet of Things'; Management = 'Management and governance'; Web = 'Web & Mobile' }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('---')
$lines.Add('description: Every Azure resource provider namespace and the AzureScout category its discovered resources are filed under.')
$lines.Add('---')
$lines.Add('')
$lines.Add('# Resource Categories')
$lines.Add('')
$lines.Add('Every resource AzureScout discovers belongs to one of the 18 categories in')
$lines.Add('[Category Structure](category-structure.md), whether or not a collector reads it. Discovery records the')
$lines.Add('category on each resource (`Category`, and `CategorySource` for where it came from) in')
$lines.Add('`ReportCache/Discovery.json`, and the React report lists resources without a collector under their')
$lines.Add('category as **Other discovered resources**.')
$lines.Add('')
$lines.Add('::: tip This page is generated')
$lines.Add('Regenerate it with `scripts/Build-ResourceCategoryCatalog.ps1` from `manifests/resource-categories.psd1`.')
$lines.Add('A test fails if this page and the map differ, or if a namespace in Azure''s provider catalogue')
$lines.Add('(`manifests/azure-provider-types.json`) has no category.')
$lines.Add(':::')
$lines.Add('')
$lines.Add('## How a resource''s category is decided')
$lines.Add('')
$lines.Add('1. **Collector** — if a collector reads the resource type, the category is that collector''s folder under')
$lines.Add('   `manifests/collectors/`.')
$lines.Add('2. **Type** — otherwise the longest entry in the type table below that is the type itself or one of its')
$lines.Add('   parents (for example `microsoft.compute/virtualmachines/patchassessmentresults` covers its')
$lines.Add('   `softwarepatches` children).')
$lines.Add('3. **Namespace** — otherwise the category of the type''s resource provider namespace.')
$lines.Add('4. **Fallback** — a namespace Azure adds after this map was updated is filed under General and marked')
$lines.Add('   `CategorySource = Fallback`, and the discovery page counts it as uncategorized, so it is visible')
$lines.Add('   rather than silently misfiled.')
$lines.Add('')
$lines.Add('## Summary')
$lines.Add('')
$lines.Add('| Category | Namespaces | Type entries |')
$lines.Add('|---|---:|---:|')
foreach ($category in $map.Categories) {
    $nsCount = @($map.Namespaces.GetEnumerator() | Where-Object Value -eq $category).Count
    $typeCount = @($map.Types.GetEnumerator() | Where-Object Value -eq $category).Count
    $label = if ($labels.ContainsKey($category)) { "$category ($($labels[$category]))" } else { $category }
    $lines.Add("| $label | $nsCount | $typeCount |")
}
$lines.Add("| **Total** | **$($map.Namespaces.Count)** | **$($map.Types.Count)** |")
$lines.Add('')
$lines.Add('## Type entries')
$lines.Add('')
$lines.Add('For namespaces whose resources span categories. Each entry also covers its child types.')
$lines.Add('')
$lines.Add('| Resource type | Category |')
$lines.Add('|---|---|')
foreach ($entry in $map.Types.GetEnumerator() | Sort-Object Name) { $lines.Add("| ``$($entry.Name)`` | $($entry.Value) |") }
$lines.Add('')
$lines.Add('## Namespaces by category')
foreach ($category in $map.Categories) {
    $names = @($map.Namespaces.GetEnumerator() | Where-Object Value -eq $category | ForEach-Object Name | Sort-Object)
    $label = if ($labels.ContainsKey($category)) { "$category — $($labels[$category])" } else { $category }
    $lines.Add('')
    $lines.Add("### $label")
    $lines.Add('')
    $lines.Add((($names | ForEach-Object { "``$_``" }) -join ', '))
}
$text = ($lines -join "`n") + "`n"
if ($PassThru) { return $text }
Set-Content -LiteralPath $OutputPath -Value $text -NoNewline -Encoding utf8NoBOM
Write-Host "[Build-ResourceCategoryCatalog] Wrote $OutputPath ($($map.Namespaces.Count) namespaces, $($map.Types.Count) type entries)"
