#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Discover the inventory collectors to run, as an ordered, deterministic list (AB#5649).

.DESCRIPTION
    The v1 engine forked from microsoft/ARI rediscovered collectors inline inside
    `Start-AZSCProcessJob` and `Start-AZSCAutProcessJob`, twice, with the two copies already
    drifted apart: the regular path applied per-file `.CATEGORY` filtering and the automation
    path did not. Discovery was therefore neither shared, testable, nor consistent.

    This function is the single discovery implementation. It is a pure function of the
    filesystem plus the category filter — it starts nothing, waits on nothing, and touches no
    Azure state, so it can be unit-tested against a fixture directory.

    ORDER IS PART OF THE CONTRACT. Results are sorted by category then collector name, so two
    runs over an unchanged tree return the same collectors in the same sequence. The old
    pipeline's ordering came from whatever order `Get-Job` happened to return, which is one of
    the reasons the same tenant produced different reports on consecutive runs (AB#5629).

.PARAMETER InventoryRoot
    Optional legacy fixture root. Production discovery uses DefinitionRoot only; this parameter
    remains solely for isolated test fixtures that carry a sibling definitions directory.

.PARAMETER Category
    Categories to include. The default, 'All', disables filtering. Filtering is applied twice,
    matching the behaviour the regular path shipped with:

      1. at FOLDER level — a category folder whose name is not requested is skipped entirely;
      2. at FILE level — a collector declaring `.CATEGORY` in its header is kept only when at
         least one of its declared categories was requested.

    A collector with no `.CATEGORY` header inherits its folder's name as its category.

.PARAMETER DefinitionRoot
    Path to the declarative collector definition tree (`manifests/collectors`, one
    `<Category>/<Name>.psd1` per collector -- see `docs/v3.0.0.md`). It is the production
    catalog and defaults to the module's shipped manifests/collectors tree.

.OUTPUTS
    PSCustomObject with Name, FolderCategory, Categories, Path, Contract,
    HasDeclarativeDefinition and DefinitionPath.

.NOTES
    Tracks ADO AB#5649 (Epic AB#5638); definition reporting tracks AB#5657 (Feature AB#5656).
#>
function Get-ScoutCollector {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(Position = 0)]
        [string]$InventoryRoot,

        [Parameter(Position = 1)]
        [AllowNull()]
        [string[]]$Category = @('All'),

        [Parameter(Position = 2)]
        [AllowNull()]
        [string]$DefinitionRoot
    )

    # v3's production catalog is the manifest tree.  InventoryRoot remains an explicit
    # compatibility input for focused imperative-fixture tests only; production callers do not
    # discover or execute a collector script.
    if ([string]::IsNullOrWhiteSpace($DefinitionRoot)) {
        if ([string]::IsNullOrWhiteSpace($InventoryRoot)) {
            $ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        } else {
            # Isolated test estates keep their declarative catalog under the fixture root.
            # Production has no InventoryRoot and therefore never relies on this convention.
            $FixtureDefinitionRoot = Join-Path $InventoryRoot 'definitions'
            if (Test-Path -LiteralPath $FixtureDefinitionRoot -PathType Container) {
                $DefinitionRoot = $FixtureDefinitionRoot
            } else {
                # The shipped definition catalog is anchored to this function, not to an
                # arbitrary legacy fixture path. Walking parents from /tmp on Linux can reach
                # the filesystem root and then collapse to an empty string.
                $ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            }
        }
        if ([string]::IsNullOrWhiteSpace($DefinitionRoot)) {
            $DefinitionRoot = Join-Path $ModuleRoot 'manifests' 'collectors'
        }
    }

    # $null and @() both mean "no filter", the same as 'All'. Callers derive this from a
    # parameter that is legitimately absent.
    $FilterActive = $false
    if ($Category -and @($Category).Count -gt 0 -and $Category -notcontains 'All') {
        $FilterActive = $true
    }

    # A definition root without an inventory root is the v3 path.  The directory names and
    # file basenames are the catalog's category and collector identity, so no source-script
    # metadata is needed to construct the deterministic descriptor.
    if ([string]::IsNullOrWhiteSpace($InventoryRoot)) {
        if (-not (Test-Path -LiteralPath $DefinitionRoot -PathType Container)) {
            Write-Warning "[AzureScout] Collector definition root not found: $DefinitionRoot"
            return
        }

        $Folders = @(Get-ChildItem -LiteralPath $DefinitionRoot -Directory | Sort-Object Name)
        if ($FilterActive) {
            $Folders = @($Folders | Where-Object { $Category -contains $_.Name })
        }

        foreach ($Folder in $Folders) {
            foreach ($File in @(Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.psd1' -File | Sort-Object BaseName)) {
                [PSCustomObject]@{
                    Name                     = $File.BaseName
                    FolderCategory           = $Folder.Name
                    Categories               = @($Folder.Name)
                    Path                     = $null
                    Contract                 = 'Declarative'
                    HasDeclarativeDefinition = $true
                    DefinitionPath           = $File.FullName
                }
            }
        }
        return
    }

    if (-not (Test-Path -LiteralPath $InventoryRoot)) {
        Write-Warning "[AzureScout] Inventory module root not found: $InventoryRoot"
        return
    }

    $Folders = @(Get-ChildItem -LiteralPath $InventoryRoot -Directory | Sort-Object Name)

    if ($FilterActive) {
        $Folders = @($Folders | Where-Object { $Category -contains $_.Name })
    }

    foreach ($Folder in $Folders) {
        $Files = @(Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.ps1' -File | Sort-Object Name)

        foreach ($File in $Files) {
            # The header carries an optional `.CATEGORY` line so a collector can belong to a
            # category other than the folder it is filed under. Read a bounded prefix rather
            # than the whole file — these are read for every collector on every run.
            $HeaderText = (@(Get-Content -LiteralPath $File.FullName -TotalCount 80 -ErrorAction SilentlyContinue) -join "`n")

            # All remaining collectors implement the standard invocation shape. Keep the field
            # while callers still consume it; its value is now deterministic.
            $Contract = 'Standard'

            # Both header forms are accepted:
            #
            #     .CATEGORY Compute          <- same line, what all 174 shipped collectors use
            #     .CATEGORY
            #     Compute                    <- value on the following line
            #
            # The engine's original expression was '\.CATEGORY\s*[\r\n]+\s*(...)', which REQUIRES
            # a line break between the keyword and the value. No collector is written that way,
            # so it never matched a single file and per-file category filtering was dead code --
            # every collector silently fell back to its folder name. Nothing currently declares a
            # category different from its folder, so accepting the real form changes no present
            # behaviour; it makes the documented feature work for cross-filed collectors.
            $FileCategory = $Folder.Name
            if ($HeaderText -match '\.CATEGORY[ \t]*(?:\r?\n\s*)?([^\r\n#<]+)') {
                $FileCategory = $Matches[1].Trim()
            }

            $Categories = @($FileCategory -split '\s*,\s*' | Where-Object { $_ })

            if ($FilterActive) {
                $Wanted = @($Categories | Where-Object { $Category -contains $_ })
                if ($Wanted.Count -eq 0) { continue }
            }

            $DefinitionPath = Join-Path $DefinitionRoot $Folder.Name "$($File.BaseName).psd1"
            $HasDefinition  = Test-Path -LiteralPath $DefinitionPath -PathType Leaf

            [PSCustomObject]@{
                Name                     = $File.BaseName
                FolderCategory           = $Folder.Name
                Categories               = $Categories
                Path                     = $File.FullName
                Contract                 = $Contract
                HasDeclarativeDefinition = $HasDefinition
                DefinitionPath           = if ($HasDefinition) { $DefinitionPath } else { $null }
            }
        }
    }
}
