#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Export inventory data as a Power BI-ready CSV bundle

.DESCRIPTION
Reads all cache files produced by the processing phase and exports them as a
folder of flat CSV files optimized for Power BI / Microsoft Fabric import.

Each inventory module becomes its own CSV file with consistent naming. A
_metadata.csv provides tenant/scan context, a Subscriptions.csv dimension
table enables slicing, and a _relationships.json manifest describes the
star-schema relationships for automatic Power BI data model configuration.

Output structure:
    PowerBI/
        _metadata.csv               — Scan metadata (tenant, date, scope, version)
        _relationships.json         — Table relationship definitions for Power BI
        Subscriptions.csv           — Subscription dimension table
        Resources_{Module}.csv      — One file per ARM inventory module
        Entra_{Module}.csv          — One file per Entra/Identity module

.PARAMETER ReportCache
Path to the ReportCache folder containing processed category JSON files.

.PARAMETER File
Path to the base report file (e.g. the .xlsx path). The Power BI folder is
created as a sibling directory named "PowerBI".

.PARAMETER TenantID
The Azure AD / Entra ID tenant identifier.

.PARAMETER Subscriptions
Array of subscription objects with Id and Name properties.

.PARAMETER Scope
Scan scope: All, ArmOnly, or EntraOnly.

.OUTPUTS
[string] Path to the PowerBI output folder.

.LINK
https://github.com/thisismydemo/azure-scout/Modules/Private/Reporting/Export-AZSCPowerBIReport.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
First Release Date: February 25, 2026
Authors: AzureScout Contributors
#>

function Export-AZSCPowerBIReport {
    [CmdletBinding()]
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

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Starting Power BI CSV export.')

    # ── Resolve output folder ────────────────────────────────────────────
    $BaseDir   = Split-Path $File -Parent
    $PowerBIDir = Join-Path $BaseDir 'PowerBI'

    if (Test-Path $PowerBIDir) {
        Remove-Item $PowerBIDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $PowerBIDir -Force | Out-Null

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Power BI output folder: $PowerBIDir")

    # ── Helpers ──────────────────────────────────────────────────────────

    function ConvertTo-SafeCsvRow {
        param([Parameter(ValueFromPipeline)]$InputObject)
        process {
            $safe = [ordered]@{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $value = $property.Value
                if ($value -is [string] -and $value -match '^[\t\r\n ]*[=+\-@]') { $value = "'$value" }
                $safe[$property.Name] = $value
            }
            [pscustomobject]$safe
        }
    }

    # Export an array of ordered hashtables / PSObjects to CSV
    function Export-FlatCsv {
        param(
            [string]$FilePath,
            [object[]]$Data,
            [string]$Category,
            [string]$Module
        )

        if (-not $Data -or $Data.Count -eq 0) { return 0 }

        # Normalize all items to PSCustomObject and add _Category / _Module columns
        $rows = foreach ($item in $Data) {
            $props = [ordered]@{
                '_Category' = $Category
                '_Module'   = $Module
            }

            if ($item -is [System.Collections.IDictionary]) {
                foreach ($key in $item.Keys) {
                    $value = $item[$key]
                    # Flatten arrays/objects to strings for CSV compatibility
                    if ($null -eq $value) {
                        $props[$key] = ''
                    }
                    elseif ($value -is [array]) {
                        $props[$key] = ($value -join '; ')
                    }
                    elseif ($value -is [PSCustomObject] -or $value -is [System.Collections.IDictionary]) {
                        $props[$key] = ($value | ConvertTo-Json -Depth 5 -Compress)
                    }
                    elseif ($value -is [bool]) {
                        $props[$key] = $value.ToString()
                    }
                    else {
                        $props[$key] = $value
                    }
                }
            }
            else {
                foreach ($prop in $item.PSObject.Properties) {
                    $value = $prop.Value
                    if ($null -eq $value) {
                        $props[$prop.Name] = ''
                    }
                    elseif ($value -is [array]) {
                        $props[$prop.Name] = ($value -join '; ')
                    }
                    elseif ($value -is [PSCustomObject] -or $value -is [System.Collections.IDictionary]) {
                        $props[$prop.Name] = ($value | ConvertTo-Json -Depth 5 -Compress)
                    }
                    elseif ($value -is [bool]) {
                        $props[$prop.Name] = $value.ToString()
                    }
                    else {
                        $props[$prop.Name] = $value
                    }
                }
            }

            [PSCustomObject]$props
        }

        $rows | ConvertTo-SafeCsvRow | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8 -Force
        return $rows.Count
    }

    # ── Track generated files for summary ────────────────────────────────
    $generatedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalRows = 0

    # ── 1. Metadata CSV ──────────────────────────────────────────────────
    $metadataFile = Join-Path $PowerBIDir '_metadata.csv'
    $subCount = if ($Subscriptions) { @($Subscriptions).Count } else { 0 }

    $metadataRows = @(
        [ordered]@{ Property = 'Tool';           Value = 'AzureScout' }
        [ordered]@{ Property = 'Version';        Value = '1.0.0' }
        [ordered]@{ Property = 'TenantId';       Value = $TenantID }
        [ordered]@{ Property = 'Subscriptions';  Value = $subCount }
        [ordered]@{ Property = 'GeneratedAt';    Value = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') }
        [ordered]@{ Property = 'Scope';          Value = $Scope }
    )
    $metadataRows | ForEach-Object { [PSCustomObject]$_ } | ConvertTo-SafeCsvRow | Export-Csv -Path $metadataFile -NoTypeInformation -Encoding UTF8 -Force
    $generatedFiles.Add([PSCustomObject]@{ File = '_metadata.csv'; Category = 'Metadata'; Rows = $metadataRows.Count })

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Metadata CSV written.')

    # ── 2. Subscriptions dimension table ─────────────────────────────────
    $subsFile = Join-Path $PowerBIDir 'Subscriptions.csv'
    if ($Subscriptions -and @($Subscriptions).Count -gt 0) {
        $subRows = foreach ($sub in $Subscriptions) {
            [PSCustomObject][ordered]@{
                SubscriptionId   = if ($sub.Id) { $sub.Id } elseif ($sub.SubscriptionId) { $sub.SubscriptionId } else { '' }
                SubscriptionName = if ($sub.Name) { $sub.Name } else { '' }
            }
        }
        $subRows | ConvertTo-SafeCsvRow | Export-Csv -Path $subsFile -NoTypeInformation -Encoding UTF8 -Force
        $generatedFiles.Add([PSCustomObject]@{ File = 'Subscriptions.csv'; Category = 'Dimension'; Rows = @($subRows).Count })
    }
    else {
        # Write empty dimension table with headers
        [PSCustomObject]@{ SubscriptionId = ''; SubscriptionName = '' } | ConvertTo-SafeCsvRow | Export-Csv -Path $subsFile -NoTypeInformation -Encoding UTF8 -Force
        $generatedFiles.Add([PSCustomObject]@{ File = 'Subscriptions.csv'; Category = 'Dimension'; Rows = 0 })
    }

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Subscriptions CSV written.')

    # ── 3. Read definition-indexed cache files and export CSVs ───────────
    # Definitions are the report contract; cache keys are definition names.
    $SectionIndex = @(Get-ScoutReportSectionIndex -DefinitionRoot $DefinitionRoot)
    $CacheFiles = @(Get-ChildItem -Path $ReportCache -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object FullName)
    $CacheByName = @{}
    foreach ($CacheFile in $CacheFiles) {
        if (-not $CacheByName.ContainsKey($CacheFile.Name)) { $CacheByName[$CacheFile.Name] = $CacheFile }
    }
    $ParsedCache = @{}

    # Track all relationship sources for manifest
    $relationshipTables = [System.Collections.Generic.List[string]]::new()

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

        $isEntra = $Section.Category -eq 'Identity'
        $prefix = if ($isEntra) { 'Entra' } else { 'Resources' }
        $csvName = "${prefix}_$($Section.Name).csv"
        $csvPath = Join-Path $PowerBIDir $csvName
        $categoryDisplay = if ($isEntra) { 'Identity' } else { $Section.Category }
        $rowCount = Export-FlatCsv -FilePath $csvPath -Data @($ModResources) -Category $categoryDisplay -Module $Section.Name

        if ($rowCount -gt 0) {
            $generatedFiles.Add([PSCustomObject]@{ File = $csvName; Category = $categoryDisplay; Rows = $rowCount })
            $totalRows += $rowCount
            $relationshipTables.Add($csvName)

            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Exported $rowCount rows → $csvName")
        }
    }

    # ── 5. Relationships manifest ────────────────────────────────────────
    $relationshipsFile = Join-Path $PowerBIDir '_relationships.json'

    # Build star-schema relationships: each resource table links to Subscriptions via Subscription
    $relationships = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($table in $relationshipTables) {
        # Resource tables that have a Subscription column can join to Subscriptions dimension
        $relationships.Add([PSCustomObject][ordered]@{
            fromTable  = [System.IO.Path]::GetFileNameWithoutExtension($table)
            fromColumn = 'Subscription'
            toTable    = 'Subscriptions'
            toColumn   = 'SubscriptionName'
            type       = 'many-to-one'
        })
    }

    $manifest = [ordered]@{
        description   = 'Power BI data model relationships for Azure Scout inventory data'
        generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        instructions  = 'In Power BI Desktop: Get Data > Folder > select the PowerBI directory. Use these relationships to configure the data model.'
        tables        = @(@('_metadata.csv', 'Subscriptions.csv') + @($relationshipTables))
        relationships = @($relationships)
    }

    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $relationshipsFile -Encoding UTF8 -Force

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Relationships manifest written.')

    # ── 6. Summary ───────────────────────────────────────────────────────
    $fileCount = $generatedFiles.Count

    Write-Host "Power BI CSV bundle saved to: " -ForegroundColor Green -NoNewline
    Write-Host $PowerBIDir -ForegroundColor Cyan
    Write-Host "  Files: $fileCount  |  Total rows: $totalRows" -ForegroundColor Gray

    Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Power BI export complete: $fileCount files, $totalRows rows.")

    return $PowerBIDir
}
