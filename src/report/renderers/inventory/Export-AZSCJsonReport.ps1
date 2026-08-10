#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Export inventory data as a structured JSON report

.DESCRIPTION
Reads all cache files produced by the processing phase and assembles them into
a single structured JSON document with a metadata envelope. The JSON file is
written alongside (or instead of) the Excel report depending on the
-OutputFormat parameter on Invoke-AzureScout.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/Reporting/Export-AZSCJsonReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Export-AZSCJsonReport {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'IncludeCosts', Justification = 'Called with -IncludeCosts from src/Invoke-AzureScout.ps1 (outside this task''s src/report+src/assess scope) for interface parity with sibling renderers; removing it would break that caller.')]
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
        [object]$Quotas,

        [Parameter()]
        [switch]$SecurityCenter,

        [Parameter()]
        [switch]$SkipAdvisory,

        [Parameter()]
        [switch]$SkipPolicy,

        [Parameter()]
        [switch]$IncludeCosts,

        [Parameter()]
        [string]$DefinitionRoot = (Join-Path (Join-Path ((Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName) 'manifests') 'collectors')
    )

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Starting JSON report export.')

    # ── Resolve output path ──────────────────────────────────────────────
    # Derive the .json path from the .xlsx path
    $JsonFile = [System.IO.Path]::ChangeExtension($File, '.json')

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - JSON output file: $JsonFile")

    # ── Build metadata envelope ──────────────────────────────────────────
    $SubscriptionList = @()
    if ($Subscriptions) {
        foreach ($sub in $Subscriptions) {
            $SubscriptionList += [ordered]@{
                id   = if ($sub.Id) { $sub.Id } elseif ($sub.SubscriptionId) { $sub.SubscriptionId } else { '' }
                name = if ($sub.Name) { $sub.Name } else { '' }
            }
        }
    }

    $Metadata = [ordered]@{
        tool          = 'AzureScout'
        version       = '1.0.0'
        tenantId      = $TenantID
        subscriptions = $SubscriptionList
        generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        scope         = $Scope
    }

    # ── Category mapping ─────────────────────────────────────────────────
    # Definitions are the report contract; cache keys are definition names.
    $SectionIndex = @(Get-ScoutReportSectionIndex -DefinitionRoot $DefinitionRoot)
    $EntraCategories = @('Identity')

    $ArmData   = [ordered]@{}
    $EntraData = [ordered]@{}

    $CacheFiles = @(Get-ChildItem -Path $ReportCache -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object FullName)
    $CacheByName = @{}
    foreach ($CacheFile in $CacheFiles) {
        if (-not $CacheByName.ContainsKey($CacheFile.Name)) { $CacheByName[$CacheFile.Name] = $CacheFile }
    }
    $ParsedCache = @{}

    foreach ($Section in $SectionIndex) {
        if ($Scope -eq 'ArmOnly' -and $Section.Category -in $EntraCategories) { continue }
        if ($Scope -eq 'EntraOnly' -and $Section.Category -notin $EntraCategories) { continue }
        if (-not $CacheByName.ContainsKey($Section.CacheFileName)) { continue }
        if (-not $ParsedCache.ContainsKey($Section.CacheFileName)) {
            $RawJson = [System.IO.File]::ReadAllText($CacheByName[$Section.CacheFileName].FullName)
            if ([string]::IsNullOrWhiteSpace($RawJson)) { continue }
            $ParsedCache[$Section.CacheFileName] = $RawJson | ConvertFrom-Json
        }

        $CacheData = $ParsedCache[$Section.CacheFileName]
        $CacheProperty = $CacheData.PSObject.Properties[$Section.CacheKey]
        $Resources = @(if ($CacheProperty) { $CacheProperty.Value })
        if ($Resources.Count -eq 0) { continue }

        $JsonKey = $Section.Name.Substring(0, 1).ToLowerInvariant() + $Section.Name.Substring(1)
        if ($Section.Category -in $EntraCategories) {
            $EntraData[$JsonKey] = $Resources
        }
        else {
            $FolderKey = $Section.Category.Substring(0, 1).ToLowerInvariant() + $Section.Category.Substring(1)
            if (-not $ArmData.Contains($FolderKey)) { $ArmData[$FolderKey] = [ordered]@{} }
            $ArmData[$FolderKey][$JsonKey] = $Resources
        }
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Added $($Resources.Count) resources from $($Section.Category)/$($Section.Name)")
    }

    # ── Build extra data sections ────────────────────────────────────────
    # Advisory, Policy, Security Center, Quotas — read from extra-report cache files if present
    $ExtraData = [ordered]@{}

    # Advisory
    if (-not $SkipAdvisory.IsPresent) {
        $AdvisoryCache = $CacheFiles | Where-Object { $_.Name -eq 'Advisory.json' }
        if ($AdvisoryCache) {
            try {
                $AdvReader = New-Object System.IO.StreamReader($AdvisoryCache.FullName)
                $AdvRaw    = $AdvReader.ReadToEnd()
                $AdvReader.Dispose()
                if (-not [string]::IsNullOrWhiteSpace($AdvRaw)) {
                    $ExtraData['advisory'] = ($AdvRaw | ConvertFrom-Json)
                }
            }
            catch {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Failed to read Advisory cache: $_")
            }
        }
    }

    # Policy
    if (-not $SkipPolicy.IsPresent) {
        $PolicyCache = $CacheFiles | Where-Object { $_.Name -eq 'Policy.json' }
        if ($PolicyCache) {
            try {
                $PolReader = New-Object System.IO.StreamReader($PolicyCache.FullName)
                $PolRaw    = $PolReader.ReadToEnd()
                $PolReader.Dispose()
                if (-not [string]::IsNullOrWhiteSpace($PolRaw)) {
                    $ExtraData['policy'] = ($PolRaw | ConvertFrom-Json)
                }
            }
            catch {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Failed to read Policy cache: $_")
            }
        }
    }

    # Security Center
    if ($SecurityCenter.IsPresent) {
        $SecCache = $CacheFiles | Where-Object { $_.Name -eq 'SecurityCenter.json' }
        if ($SecCache) {
            try {
                $SecReader = New-Object System.IO.StreamReader($SecCache.FullName)
                $SecRaw    = $SecReader.ReadToEnd()
                $SecReader.Dispose()
                if (-not [string]::IsNullOrWhiteSpace($SecRaw)) {
                    $ExtraData['security'] = ($SecRaw | ConvertFrom-Json)
                }
            }
            catch {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Failed to read SecurityCenter cache: $_")
            }
        }
    }

    # Quotas
    if ($Quotas) {
        $QuotaCache = $CacheFiles | Where-Object { $_.Name -eq 'Quotas.json' }
        if ($QuotaCache) {
            try {
                $QuotaReader = New-Object System.IO.StreamReader($QuotaCache.FullName)
                $QuotaRaw    = $QuotaReader.ReadToEnd()
                $QuotaReader.Dispose()
                if (-not [string]::IsNullOrWhiteSpace($QuotaRaw)) {
                    $ExtraData['quotas'] = ($QuotaRaw | ConvertFrom-Json)
                }
            }
            catch {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Failed to read Quotas cache: $_")
            }
        }
    }

    # ── Assemble final report object ─────────────────────────────────────
    $Report = [ordered]@{
        '_metadata' = $Metadata
    }

    if ($Scope -in ('All', 'ArmOnly') -and $ArmData.Count -gt 0) {
        $Report['arm'] = $ArmData
    }

    if ($Scope -in ('All', 'EntraOnly') -and $EntraData.Count -gt 0) {
        $Report['entra'] = $EntraData
    }

    # Merge extra data sections at the top level
    foreach ($key in $ExtraData.Keys) {
        $Report[$key] = $ExtraData[$key]
    }

    # ── Write JSON file ──────────────────────────────────────────────────
    try {
        $JsonOutput = $Report | ConvertTo-Json -Depth 40
        $JsonOutput | Out-File -FilePath $JsonFile -Encoding utf8 -Force

        Write-Host "JSON report saved to: " -ForegroundColor Green -NoNewline
        Write-Host $JsonFile -ForegroundColor Cyan
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - JSON report written successfully.")
    }
    catch {
        Write-Warning "Failed to write JSON report to '$JsonFile': $_"
    }

    return $JsonFile
}
