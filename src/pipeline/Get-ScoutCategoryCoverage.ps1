#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Per-category collector coverage counts, derived from manifests/collectors/ (AB#7102).

.DESCRIPTION
    The wizard's category checklist (AB#7101) used to show eighteen bare category names with
    no indication of how much any of them actually collects. Any figure typed next to a
    category name -- "Analytics (6/19)" -- rots the moment a collector is added, retired, or
    breaks its schema, exactly the way the old hand-maintained `docs/reference/arm-modules.md`
    rotted before `scripts/Build-ArmModuleCatalog.ps1` started generating it (AB#6741).

    This function is that same read, exposed as a callable instead of an inline build-script
    block, so the wizard (a running module) and the docs generator (a standalone script) can
    both derive their counts from one manifest walk. It reuses
    `Get-ScoutCollectorDefinition` -- the same schema-validating reader
    `scripts/Build-ArmModuleCatalog.ps1` already uses -- rather than re-parsing `.psd1` files
    with a second, independent implementation.

    Per category:
      Published — every `.psd1` file under the category's manifest directory. A definition
                  that exists is published; whether it also *works* is Collected.
      Collected — the subset of Published whose definition loads and passes
                  `Get-ScoutCollectorDefinition`'s schema validation without throwing. A
                  manifest that fails validation is shipped but does not actually collect
                  anything, so it must not count toward the coverage figure.

.PARAMETER CollectorRoot
    The collector manifest tree. Defaults to `manifests/collectors` beside the module.

.PARAMETER Category
    Restrict the result to these category (folder) names. Defaults to every category found.

.OUTPUTS
    One [PSCustomObject] per category: Category, Published, Collected, Services (one entry per
    `.psd1` file: Name, Collected, Error).

.NOTES
    Tracks ADO AB#7102 (feature AB#7101, AB#7103, AB#7104).
#>
function Get-ScoutCategoryCoverage {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$CollectorRoot,
        [string[]]$Category
    )

    # Same standalone-dot-source contract as Get-ScoutGraphPermissionImpact: callable either as
    # part of the loaded module or dot-sourced on its own (tests, scripts).
    if (-not (Get-Command Get-ScoutCollectorDefinition -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Get-ScoutCollectorDefinition.ps1')
    }

    if ([string]::IsNullOrWhiteSpace($CollectorRoot)) {
        # $PSScriptRoot is <module>/src/pipeline, so the manifest tree is two levels up.
        $ModuleRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $CollectorRoot = Join-Path $ModuleRoot 'manifests' 'collectors'
    }

    if (-not (Test-Path -LiteralPath $CollectorRoot)) {
        Write-Warning "Get-ScoutCategoryCoverage: collector root not found at '$CollectorRoot'."
        return @()
    }

    $Folders = @(Get-ChildItem -LiteralPath $CollectorRoot -Directory | Sort-Object Name)
    if ($Category -and $Category -notcontains 'All') {
        $Folders = @($Folders | Where-Object { $_.Name -in $Category })
    }

    foreach ($Folder in $Folders) {
        $Files = @(Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.psd1' -File | Sort-Object BaseName)

        $Services = foreach ($File in $Files) {
            $IsCollected = $true
            $ErrorText   = $null
            try { $null = Get-ScoutCollectorDefinition -Path $File.FullName }
            catch {
                $IsCollected = $false
                $ErrorText   = $_.Exception.Message
            }
            [PSCustomObject]@{
                Name      = $File.BaseName
                Collected = $IsCollected
                Error     = $ErrorText
            }
        }

        [PSCustomObject]@{
            Category  = $Folder.Name
            Published = $Files.Count
            Collected = @($Services | Where-Object { $_.Collected }).Count
            Services  = @($Services)
        }
    }
}
