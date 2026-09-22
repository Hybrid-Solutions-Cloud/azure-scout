<#
.SYNOPSIS
    Build the inventory Excel workbook from declarative collector definitions.

.DESCRIPTION
    Reads the processing cache and renders each definition-indexed collector through
    Invoke-ScoutDeclarativeReporting.  The report layer deliberately never discovers or
    executes legacy collector scripts: manifests are the sole contract between collection,
    cache, and Excel output.
#>
function Start-AZSCExcelJob {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$ReportCache,

        [Parameter(Mandatory)]
        [string]$File,

        [Parameter(Mandatory)]
        [string]$TableStyle,

        [Parameter()]
        [switch]$InTag,

        [Parameter()]
        [string]$DefinitionRoot = (Join-Path (Join-Path ((Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName) 'manifests') 'collectors')
    )

    if (-not (Test-Path -LiteralPath $ReportCache -PathType Container)) {
        throw "Report cache path not found: $ReportCache"
    }

    $SectionIndex = @(Get-ScoutReportSectionIndex -DefinitionRoot $DefinitionRoot)
    $SectionsCount = $SectionIndex.Count

    Write-Progress -Activity 'Azure Inventory' -Status '68% Complete.' -PercentComplete 68 -CurrentOperation 'Starting the Report Loop..'
    Write-Output 'Starting to Build Excel Report.'
    Write-Host 'Supported Resource Types: ' -NoNewline -ForegroundColor Green
    Write-Host $SectionsCount -ForegroundColor Cyan

    # Cache files are category documents.  Read each document at most once, even though every
    # category has multiple definitions, and retain the old tolerant behavior for a category
    # that was skipped during processing.
    $CacheByName = @{}
    foreach ($CacheFile in @(Get-ChildItem -LiteralPath $ReportCache -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        if (-not $CacheByName.ContainsKey($CacheFile.Name)) {
            $CacheByName[$CacheFile.Name] = $CacheFile
        }
    }
    $ParsedCache = @{}

    $ReportCounter = 0
    $PreviousCategory = $null
    foreach ($Section in $SectionIndex) {
        if ($PreviousCategory -and $PreviousCategory -ne $Section.Category) {
            if (Get-Command -Name Clear-AZSCMemory -ErrorAction SilentlyContinue) {
                Clear-AZSCMemory
            }
        }
        $PreviousCategory = $Section.Category

        $Progress = if ($SectionsCount -gt 0) {
            [math]::Round(($ReportCounter / $SectionsCount) * 100)
        }
        else { 100 }
        Write-Progress -Id 1 -Activity 'Building Report' -Status "$Progress% Complete." -PercentComplete $Progress

        if (-not $CacheByName.ContainsKey($Section.CacheFileName)) {
            $ReportCounter++
            continue
        }

        if (-not $ParsedCache.ContainsKey($Section.CacheFileName)) {
            $RawJson = [System.IO.File]::ReadAllText($CacheByName[$Section.CacheFileName].FullName)
            if ([string]::IsNullOrWhiteSpace($RawJson)) {
                $ParsedCache[$Section.CacheFileName] = $null
            }
            else {
                $ParsedCache[$Section.CacheFileName] = $RawJson | ConvertFrom-Json
            }
        }

        $CacheData = $ParsedCache[$Section.CacheFileName]
        $CacheProperty = if ($CacheData) { $CacheData.PSObject.Properties[$Section.CacheKey] } else { $null }
        $SmaResources = if ($CacheProperty) { @($CacheProperty.Value).Where({ $null -ne $_ }) } else { @() }

        if ($SmaResources.Count -gt 0) {
            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + " - Rendering definition: '$($Section.Name)'. Excel Rows: $($SmaResources.Count)")
            $Definition = Get-ScoutCollectorDefinition -Path $Section.DefinitionPath
            Invoke-ScoutDeclarativeReporting -Definition $Definition -Context @{
                InTag       = $InTag.IsPresent
                File        = $File
                SmaResources = $SmaResources
                TableStyle  = $TableStyle
            }
        }

        $ReportCounter++
    }

    if ($PreviousCategory -and (Get-Command -Name Clear-AZSCMemory -ErrorAction SilentlyContinue)) {
        Clear-AZSCMemory
    }
    Write-Progress -Id 1 -Activity 'Building Report' -Status '100% Complete.' -Completed
}
