#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Build the deterministic collector index used by inventory report renderers.

.DESCRIPTION
    Reads validated collector definitions from manifests/collectors and returns one ordered
    descriptor per definition. The index contains the category/cache-file mapping, cache key,
    worksheet name, and declared resource types that reporting needs without consulting the
    retired source-script tree.

    This function does not change live report routing. Until every collector has a definition,
    callers must not replace the legacy reporting walk with this index or unconverted collectors
    would be omitted.

.PARAMETER DefinitionRoot
    Root of the collector definition tree. Each direct child directory is a report category and
    each .psd1 beneath it is one collector definition.

.PARAMETER Category
    Optional category filter. Null, an empty array, or All returns every category.

.OUTPUTS
    PSCustomObject entries ordered by Category then Name.

.NOTES
    Prerequisite for AB#5945 (Feature AB#5942, Epic AB#5917).
#>
function Get-ScoutReportSectionIndex {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [string]$DefinitionRoot,

        [Parameter(Position = 1)]
        [AllowNull()]
        [string[]]$Category = @('All')
    )

    if (-not (Test-Path -LiteralPath $DefinitionRoot -PathType Container)) {
        throw "Collector definition root not found: $DefinitionRoot"
    }

    if (-not (Get-Command -Name 'Get-ScoutCollectorDefinition' -ErrorAction SilentlyContinue)) {
        throw 'Get-ScoutCollectorDefinition must be loaded before building the report section index.'
    }

    $FilterActive = $Category -and @($Category).Count -gt 0 -and $Category -notcontains 'All'
    $CategoryDirectories = @(
        Get-ChildItem -LiteralPath $DefinitionRoot -Directory |
            Sort-Object Name
    )

    if ($FilterActive) {
        $CategoryDirectories = @(
            $CategoryDirectories |
                Where-Object { $Category -contains $_.Name }
        )
    }

    $Order = 0
    foreach ($CategoryDirectory in $CategoryDirectories) {
        $DefinitionFiles = @(
            Get-ChildItem -LiteralPath $CategoryDirectory.FullName -Filter '*.psd1' -File |
                Sort-Object BaseName
        )

        foreach ($DefinitionFile in $DefinitionFiles) {
            $Definition = Get-ScoutCollectorDefinition -Path $DefinitionFile.FullName
            $AzureResourceTypes = @(
                $Definition.ResourceTypes |
                    Where-Object { $_ -notmatch '(?i)^AZSC/' }
            )

            [PSCustomObject]@{
                Order              = $Order
                Category           = $CategoryDirectory.Name
                SectionName        = $CategoryDirectory.Name
                CacheFileName      = "$($CategoryDirectory.Name).json"
                Name               = $DefinitionFile.BaseName
                CacheKey           = $DefinitionFile.BaseName
                WorksheetName      = $Definition.Export.WorksheetName
                DefinitionPath     = $DefinitionFile.FullName
                ResourceTypes      = @($Definition.ResourceTypes)
                AzureResourceTypes = $AzureResourceTypes
            }

            $Order++
        }
    }
}
