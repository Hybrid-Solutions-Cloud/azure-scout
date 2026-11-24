#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScoutResourceCategoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ScoutResourceCategoryMap = $null
$script:ScoutResourceCategoryCache = $null

<#
.SYNOPSIS
    Loads manifests/resource-categories.psd1: every Azure resource provider namespace and the
    AzureScout category its resources belong to, with type-level entries for namespaces that span
    categories.
#>
function Get-ScoutResourceCategoryMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string] $Path = (Join-Path $script:ScoutResourceCategoryRoot 'manifests/resource-categories.psd1'))

    if ($null -ne $script:ScoutResourceCategoryMap -and -not $PSBoundParameters.ContainsKey('Path')) { return $script:ScoutResourceCategoryMap }
    $raw = Import-PowerShellDataFile -LiteralPath $Path
    $namespaces = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $raw.Namespaces.Keys) { $namespaces[[string]$key] = [string]$raw.Namespaces[$key] }
    $types = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $raw.Types.Keys) { $types[([string]$key).TrimEnd('/')] = [string]$raw.Types[$key] }
    $map = @{ Categories = @($raw.Categories); Namespaces = $namespaces; Types = $types }
    if (-not $PSBoundParameters.ContainsKey('Path')) {
        $script:ScoutResourceCategoryMap = $map
        $script:ScoutResourceCategoryCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    return $map
}

<#
.SYNOPSIS
    The AzureScout category of a resource type, and where that answer came from.

.DESCRIPTION
    Resolution order:
      1. CollectorCategories: the categories of the collectors that read this type. The first in
         ordinal order wins, so the answer is stable when two categories read the same type.
      2. The longest entry in the map's Types that is the type itself or one of its parents.
      3. The type's namespace in the map's Namespaces.
      4. 'General', with Source 'Fallback' so the discovery record shows it was not mapped.

.OUTPUTS
    [pscustomobject] with Category and Source (Collector, Type, Namespace or Fallback).
#>
function Get-ScoutResourceCategory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyString()][string] $Type,
        [AllowNull()][string[]] $CollectorCategories,
        [AllowNull()][hashtable] $Map
    )

    $collectorCategory = @($CollectorCategories | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($collectorCategory.Count -gt 0) { return [pscustomobject]@{ Category = [string]$collectorCategory[0]; Source = 'Collector' } }

    $useCache = $null -eq $Map
    if ($useCache) { $Map = Get-ScoutResourceCategoryMap }
    $typeKey = ([string]$Type).Trim().TrimEnd('/').ToLowerInvariant()
    if ($useCache -and $null -ne $script:ScoutResourceCategoryCache) {
        $cached = $null
        if ($script:ScoutResourceCategoryCache.TryGetValue($typeKey, [ref]$cached)) { return $cached }
    }

    $result = $null
    $candidate = $typeKey
    while ($candidate.Contains('/')) {
        $value = $null
        if ($Map.Types.TryGetValue($candidate, [ref]$value)) { $result = [pscustomobject]@{ Category = $value; Source = 'Type' }; break }
        $candidate = $candidate.Substring(0, $candidate.LastIndexOf('/'))
    }
    if ($null -eq $result) {
        $namespace = ($typeKey -split '/', 2)[0]
        $value = $null
        $result = if ($namespace -and $Map.Namespaces.TryGetValue($namespace, [ref]$value)) { [pscustomobject]@{ Category = $value; Source = 'Namespace' } }
        else { [pscustomobject]@{ Category = 'General'; Source = 'Fallback' } }
    }
    if ($useCache -and $null -ne $script:ScoutResourceCategoryCache) { $script:ScoutResourceCategoryCache[$typeKey] = $result }
    return $result
}
