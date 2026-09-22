#Requires -Version 7.0
<#!
.SYNOPSIS
    Reports the resource-type coverage declared by the v3 collector catalog.

.DESCRIPTION
    v3 collectors are data files, so ResourceTypes is the authoritative source of the
    inventory surface.  This script reads the shipped manifests rather than reconstructing
    a type map from the retired collector scripts.
#>
[CmdletBinding()]
param(
    [string]$DefinitionRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'manifests', 'collectors'),
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DefinitionRoot = (Resolve-Path -LiteralPath $DefinitionRoot -ErrorAction Stop).Path
. (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'src', 'pipeline', 'Get-ScoutCollectorDefinition.ps1')

$files = @(Get-ChildItem -LiteralPath $DefinitionRoot -Recurse -Filter '*.psd1' -File | Sort-Object FullName)
$typeHits = @{}
foreach ($file in $files) {
    $definition = Get-ScoutCollectorDefinition -Path $file.FullName
    $collector = "$($file.Directory.Name)/$($file.BaseName)"
    foreach ($resourceType in @($definition.ResourceTypes)) {
        $key = ([string]$resourceType).ToLowerInvariant()
        if (-not $typeHits.ContainsKey($key)) {
            $typeHits[$key] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        }
        [void]$typeHits[$key].Add($collector)
    }
}

$typeReport = @(
    foreach ($key in ($typeHits.Keys | Sort-Object)) {
        [pscustomobject]@{ Type = $key; CollectorCount = $typeHits[$key].Count; Collectors = @($typeHits[$key] | Sort-Object) }
    }
)

$report = [pscustomobject]@{
    GeneratedOn = (Get-Date).ToString('o')
    DefinitionRoot = $DefinitionRoot
    FileCount = $files.Count
    TypeCount = $typeReport.Count
    Types = $typeReport
    PatternHits = @()
}

if ($AsJson) { $report | ConvertTo-Json -Depth 6; return }
Write-Host "Scanned $($files.Count) declarative collector definitions under $DefinitionRoot"
Write-Host "Distinct declared resource types: $($typeReport.Count)"
$typeReport | Format-Table -AutoSize Type, CollectorCount
