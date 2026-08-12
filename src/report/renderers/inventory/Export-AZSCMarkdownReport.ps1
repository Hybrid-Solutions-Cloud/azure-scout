#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Export inventory data as a structured Markdown report

.DESCRIPTION
Reads all cache files produced by the processing phase and assembles them into
a single Markdown document. Each category becomes a top-level section and each
module's data is rendered as a GitHub-Flavored Markdown pipe table. Suitable
for GitHub/GitLab wikis, Obsidian, and Confluence.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Private/Reporting/Export-AZSCMarkdownReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
First Release Date: February 24, 2026
Authors: AzureScout Contributors
#>

function Export-AZSCMarkdownReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ReportCache,

        [Parameter(Mandatory)]
        [string]$File,

        [Parameter()]
        [string]$TenantID,

        [Parameter()]
        [object]$Subscriptions,

        [Parameter()]
        [ValidateSet('All', 'ArmOnly', 'EntraOnly')]
        [string]$Scope = 'All',

        [Parameter()]
        [string]$DefinitionRoot = (Join-Path (Join-Path ((Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName) 'manifests') 'collectors')
    )

    $MdFile = [System.IO.Path]::ChangeExtension($File, '.md')
    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Markdown output file: $MdFile")

    $subCount = if ($Subscriptions) { @($Subscriptions).Count } else { 0 }
    $genDate  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $lines = [System.Collections.Generic.List[string]]::new()

    # ── Header ───────────────────────────────────────────────────────────
    $lines.Add('# Azure Scout Report')
    $lines.Add('')
    $lines.Add("| Field | Value |")
    $lines.Add("|-------|-------|")
    $lines.Add("| Generated | $genDate |")
    $lines.Add("| Tenant ID | $TenantID |")
    $lines.Add("| Subscriptions | $subCount |")
    $lines.Add("| Scope | $Scope |")
    $lines.Add("| Tool | AzureScout |")
    $lines.Add('')

    # Definitions are the report contract; cache keys are definition names.
    $SectionIndex = @(Get-ScoutReportSectionIndex -DefinitionRoot $DefinitionRoot)
    $CacheFiles = @(Get-ChildItem -Path $ReportCache -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object FullName)
    $CacheByName = @{}
    foreach ($CacheFile in $CacheFiles) {
        if (-not $CacheByName.ContainsKey($CacheFile.Name)) { $CacheByName[$CacheFile.Name] = $CacheFile }
    }
    $ParsedCache = @{}

    # ── Table of Contents ─────────────────────────────────────────────────
    $tocLines       = [System.Collections.Generic.List[string]]::new()
    $sectionLines   = [System.Collections.Generic.List[string]]::new()
    $totalResources = 0

    $tocLines.Add('## Table of Contents')
    $tocLines.Add('')

    $CurrentCategory = $null
    foreach ($Section in $SectionIndex) {
        if ($Scope -eq 'ArmOnly' -and $Section.Category -eq 'Identity') { continue }
        if ($Scope -eq 'EntraOnly' -and $Section.Category -ne 'Identity') { continue }
        if (-not $CacheByName.ContainsKey($Section.CacheFileName)) { continue }
        if (-not $ParsedCache.ContainsKey($Section.CacheFileName)) {
            $RawJson = [System.IO.File]::ReadAllText($CacheByName[$Section.CacheFileName].FullName)
            if ([string]::IsNullOrWhiteSpace($RawJson)) { continue }
            $ParsedCache[$Section.CacheFileName] = $RawJson | ConvertFrom-Json
        }

        $CacheData = $ParsedCache[$Section.CacheFileName]
        $CacheProperty = $CacheData.PSObject.Properties[$Section.CacheKey]
        $ModResources = if ($CacheProperty) { $CacheProperty.Value } else { $null }
        if (-not $ModResources -or @($ModResources).Count -eq 0) { continue }

        $rows = @($ModResources)
        $totalResources += $rows.Count
        if ($CurrentCategory -ne $Section.Category) {
            $CurrentCategory = $Section.Category
            $anchor = $CurrentCategory.ToLowerInvariant() -replace '[^a-z0-9]', '-'
            $tocLines.Add("- [$CurrentCategory](#$anchor)")
            $sectionLines.Add("## $CurrentCategory")
            $sectionLines.Add('')
        }

        $modAnchor = $Section.Name.ToLowerInvariant() -replace '[^a-z0-9]', '-'
        $tocLines.Add("  - [$($Section.Name)](#$modAnchor)")
        $sectionLines.Add("### $($Section.Name)")
        $sectionLines.Add('')
        $sectionLines.Add("_$($rows.Count) resource(s)_")
        $sectionLines.Add('')

        $props = $rows[0].PSObject.Properties.Name | Where-Object { $_ -notmatch 'Tag (Name|Value)|Resource U' }
        if (@($props).Count -gt 0) {
            $header = '| ' + ($props -join ' | ') + ' |'
            $sep    = '| ' + (($props | ForEach-Object { '---' }) -join ' | ') + ' |'
            $sectionLines.Add($header)
            $sectionLines.Add($sep)
            foreach ($row in $rows) {
                $cells = $props | ForEach-Object {
                    $v = $row.$_
                    if ($null -eq $v) { '' }
                    else { [string]$v -replace '\|', '&#124;' -replace '\r?\n', ' ' }
                }
                $sectionLines.Add('| ' + ($cells -join ' | ') + ' |')
            }
        }
        $sectionLines.Add('')
    }

    $tocLines.Add('')
    # ${...} is required here: the trailing underscore closes the markdown italic run, but an
    # underscore is a legal identifier character, so "$totalResources_" parses as a variable
    # named $totalResources_ -- which does not exist, and the Markdown export died on it.
    # (AB#5567)
    $lines.Add("_Total resources: ${totalResources}_")
    $lines.Add('')
    foreach ($l in $tocLines)    { $lines.Add($l) }
    foreach ($l in $sectionLines) { $lines.Add($l) }

    # ── Footer ────────────────────────────────────────────────────────────
    $lines.Add('---')
    $lines.Add('')
    $lines.Add("*Report generated by [AzureScout](https://github.com/Hybrid-Solutions-Cloud/azure-scout) at $genDate*")

    try {
        $lines | Out-File -FilePath $MdFile -Encoding UTF8 -Force
        Write-Host "Markdown report saved to: " -ForegroundColor Green -NoNewline
        Write-Host $MdFile -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to write Markdown report to '$MdFile': $_"
    }

    return $MdFile
}
