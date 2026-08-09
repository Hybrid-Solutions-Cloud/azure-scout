#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    For each Microsoft Graph permission, the collectors that go empty without it.

.DESCRIPTION
    AB#6765. The pre-flight used to end on one word. `$isCritical` was a hardcoded list of four
    check names, so a denied permission outside those four downgraded the run to a `Warn` and
    still printed **"READY — Full ARM + Entra ID scan supported"** — over a scan that would
    render the affected worksheet empty. One word cannot stand in for 236 outcomes, and a list
    of what you will actually get cannot lie the way a verdict word can.

    This function derives that list instead of restating it. It joins two things that already
    exist and are already maintained for their own reasons:

      - `Get-ScoutEntraQueryCatalog` — every Graph query Scout issues, with its permission and
        the synthetic TYPE it stamps on the rows.
      - the collector manifests — each declares the `ResourceTypes` it reads.

    So criticality is a derived property: a permission is critical when a collector consumes the
    data it unlocks, and adding a collector changes the answer without anyone editing a list.
    Two of Scout's Graph queries turn out to have no consumer at all, which the table reports
    rather than hides — a permission asked for and not needed belongs in the output.

.PARAMETER CollectorRoot
    The collector manifest tree. Defaults to `manifests/collectors` beside the module.

.OUTPUTS
    One row per permission: Permission, Queries, Collectors, CollectorCount, IsConsumed.

.NOTES
    Tracks ADO AB#6765 (Feature AB#6743, Epic AB#6731).
#>
function Get-ScoutGraphPermissionImpact {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string] $CollectorRoot
    )

    if ([string]::IsNullOrWhiteSpace($CollectorRoot)) {
        $moduleRoot   = Split-Path -Parent $PSScriptRoot
        $CollectorRoot = Join-Path -Path $moduleRoot -ChildPath 'manifests' -AdditionalChildPath 'collectors'
    }

    # Same standalone-dot-source contract as the pre-flight that calls this.
    if (-not (Get-Command Get-ScoutEntraQueryCatalog -ErrorAction SilentlyContinue)) {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'collect/Get-ScoutEntraQueryCatalog.ps1')
    }

    $catalog = @(Get-ScoutEntraQueryCatalog)

    # type -> collectors that read it. Built once from the manifests rather than asked per
    # permission, because the tree is ~240 files and this runs inside an interactive pre-flight.
    $byType = @{}
    if (Test-Path -LiteralPath $CollectorRoot) {
        foreach ($file in Get-ChildItem -LiteralPath $CollectorRoot -Filter '*.psd1' -Recurse -File) {
            $definition = $null
            try { $definition = Import-PowerShellDataFile -LiteralPath $file.FullName }
            catch {
                # A manifest that will not parse is a real problem, but it is not this
                # function's problem to fail on -- the collector runtime reports it.
                Write-Verbose "Get-ScoutGraphPermissionImpact: could not read '$($file.FullName)': $($_.Exception.Message)"
                continue
            }
            if ($null -eq $definition -or -not $definition.ContainsKey('ResourceTypes')) { continue }

            $collectorName = '{0}/{1}' -f $file.Directory.Name, $file.BaseName
            foreach ($type in @($definition.ResourceTypes)) {
                if ([string]::IsNullOrWhiteSpace($type)) { continue }
                $key = ([string] $type).ToLowerInvariant()
                if (-not $byType.ContainsKey($key)) { $byType[$key] = [System.Collections.Generic.List[string]]::new() }
                if (-not $byType[$key].Contains($collectorName)) { $byType[$key].Add($collectorName) }
            }
        }
    }
    else {
        Write-Verbose "Get-ScoutGraphPermissionImpact: no collector tree at '$CollectorRoot' — every permission will report zero consumers."
    }

    $catalog |
        Group-Object -Property { $_.Permission } |
        Sort-Object Name |
        ForEach-Object {
            $queries    = @($_.Group | ForEach-Object { $_.Name } | Sort-Object)
            $collectors = @(
                $_.Group | ForEach-Object {
                    $key = ([string] $_.Type).ToLowerInvariant()
                    if ($byType.ContainsKey($key)) { $byType[$key] }
                }
            ) | Sort-Object -Unique

            [PSCustomObject]@{
                Permission     = $_.Name
                Queries        = $queries
                Collectors     = @($collectors)
                CollectorCount = @($collectors).Count
                # The derived criticality. Nothing hardcoded, nothing to keep in sync.
                IsConsumed     = (@($collectors).Count -gt 0)
            }
        }
}
