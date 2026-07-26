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
    Path to the InventoryModules directory holding one subdirectory per category.

.PARAMETER Category
    Categories to include. The default, 'All', disables filtering. Filtering is applied twice,
    matching the behaviour the regular path shipped with:

      1. at FOLDER level — a category folder whose name is not requested is skipped entirely;
      2. at FILE level — a collector declaring `.CATEGORY` in its header is kept only when at
         least one of its declared categories was requested.

    A collector with no `.CATEGORY` header inherits its folder's name as its category.

.PARAMETER DefinitionRoot
    Path to the declarative collector definition tree (`manifests/collectors`, one
    `<Category>/<Name>.psd1` per converted collector -- see
    `docs/design/decisions/declarative-collectors.md`). Defaults to the sibling `manifests/
    collectors` of the module root that contains InventoryRoot.

    This EXTENDS the existing discovery rather than adding a second one: a collector is still
    found by walking InventoryRoot, and `HasDeclarativeDefinition` is an additive report of
    whether a definition happens to exist beside it. `Contract` is unchanged and a collector
    with no definition is not a defect -- it is the expected state for every escape-hatch
    collector (ADR §2.4, §3).

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
        [Parameter(Mandatory, Position = 0)]
        [string]$InventoryRoot,

        [Parameter(Position = 1)]
        [AllowNull()]
        [string[]]$Category = @('All'),

        [Parameter(Position = 2)]
        [AllowNull()]
        [string]$DefinitionRoot
    )

    if (-not (Test-Path -LiteralPath $InventoryRoot)) {
        Write-Warning "[AzureScout] Inventory module root not found: $InventoryRoot"
        return
    }

    # InventoryRoot is <ModuleRoot>/Modules/Public/InventoryModules; the definitions live at
    # <ModuleRoot>/manifests/collectors. Derived rather than hard-coded off $PSScriptRoot so the
    # function stays a pure function of its arguments and remains testable against a fixture tree.
    if ([string]::IsNullOrWhiteSpace($DefinitionRoot)) {
        $ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $InventoryRoot))
        $DefinitionRoot = Join-Path $ModuleRoot 'manifests' 'collectors'
    }

    # $null and @() both mean "no filter", the same as 'All'. Callers derive this from a
    # parameter that is legitimately absent.
    $FilterActive = $false
    if ($Category -and @($Category).Count -gt 0 -and $Category -notcontains 'All') {
        $FilterActive = $true
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

            # Which calling contract does this file implement?
            #
            # 'Standard'    — the param($SCPath, $Sub, $Intag, $Resources, ...) shape that 174
            #                 of the 176 collectors use and that Invoke-ScoutCollector calls.
            # 'Unsupported' — Identity/IdentityProviders and Identity/SecurityDefaults are
            #                 written against a registration API (Register-AZSCInventoryModule,
            #                 Get-AZSCProcessedData, $Context.EntraData) that exists ONLY as a
            #                 mock inside tests/Identity.Module.Tests.ps1. It was never
            #                 implemented in the module, so those two files have never produced
            #                 a row in any release. The old pipeline hid that: the "term is not
            #                 recognized" error surfaced detached inside a runspace and their
            #                 category simply came back empty.
            #
            # They are reported rather than executed, so a genuine collector failure is not
            # buried under two guaranteed ones. Porting them to the standard contract needs the
            # Entra data plumbing and belongs to the declarative-collector work (AB#5656).
            $Contract = if ($HeaderText -match '(?m)^\s*param\s*\(\s*\$SCPath') { 'Standard' }
                        elseif ($HeaderText -match '(?m)^\s*Register-AZSCInventoryModule') { 'Unsupported' }
                        else { 'Standard' }

            # Both header forms are accepted:
            #
            #     .CATEGORY Compute          <- same line, what all 176 shipped collectors use
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
