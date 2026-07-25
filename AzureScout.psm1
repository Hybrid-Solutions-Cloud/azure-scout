<#
.SYNOPSIS
    AzureScout — Single-tenant Azure ARM + Entra ID inventory tool.

.DESCRIPTION
    This module orchestrates dot-sourcing of all private and public functions
    that are triggered by the Invoke-AzureScout cmdlet.

.AUTHOR
    thisismydemo

.COPYRIGHT
    (c) 2026 thisismydemo. All rights reserved.

.VERSION
    1.0.0

#>

#region — Dependency bootstrap
$_requiredModules = @(
    'ImportExcel',
    'Az.Accounts',
    'Az.ResourceGraph',
    'Az.Storage',
    'Az.Compute',
    'Az.Resources',
    'Az.Advisor',        # CAF/WAF assessment ingest — Import-AdvisorScores
    'powershell-yaml'    # CAF/WAF assessment rule-file parsing — Get-RuleSet
)
# NOT auto-installed, deliberately: Az.CostManagement is needed only by -IncludeCosts, and
# adding it here made every import of this module attempt an install that drags in a newer
# Az.Accounts as a dependency. On a machine that already has Az.Accounts, that leaves two
# versions side by side and every subsequent Import-Module dies with a stack overflow inside
# Az.Accounts' own assembly-load-context resolver. An opt-in feature must not force a
# dependency upgrade on everyone. Get-AZSCCostInventory warns with the exact install command
# when the module is absent, and the run continues without cost data. (AB#5636)
foreach ($_mod in $_requiredModules) {
    if (-not (Get-Module -Name $_mod -ListAvailable)) {
        Write-Host "[AzureScout] Installing required module: $_mod" -ForegroundColor Cyan
        try {
            Install-Module -Name $_mod -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        } catch {
            Write-Warning "[AzureScout] Could not install $_mod`: $_. Some functionality may be unavailable."
            continue
        }
    }
    if (-not (Get-Module -Name $_mod)) {
        Import-Module -Name $_mod -ErrorAction SilentlyContinue
    }
}
#endregion

foreach ($directory in @('modules\Private', '.\modules\Public\PublicFunctions')) {
    Get-ChildItem -Path "$PSScriptRoot\$directory\*.ps1" -Recurse | ForEach-Object { . $_.FullName }
}

#region — Update check (AB#369)
# Auto-UPDATE counterpart to the auto-INSTALL dependency bootstrap above: on import,
# surface (never silently apply) a newer AzureScout release from PSGallery. The guts of
# the check (throttle, CI detection, Find-Module lookup, notify-vs-update opt-in) live in
# Test-AZSCModuleUpdate (Modules\Private\Main) so they can be unit-tested with Pester
# mocks -- see that function's comment-based help for the full design rationale. This
# outer try/catch is a second, redundant safety net so a missing/broken function can
# never fail module import either.
try {
    Test-AZSCModuleUpdate
} catch {
    Write-Verbose "[AzureScout] Update check failed to run: $_"
}
#endregion

# Assessment platform (Epics AB#5023 / AB#5056) — collect, engine, ingest,
# benchmark, report, orchestrator. Loaded after the inventory modules so the
# assessment layer can call into collection when needed (AB#5024).
$_assessmentRoot = Join-Path $PSScriptRoot 'src'
if (Test-Path $_assessmentRoot) {
    Get-ChildItem -Path $_assessmentRoot -Filter '*.ps1' -Recurse |
        Sort-Object FullName | ForEach-Object {
            try { . $_.FullName }
            catch { Write-Warning "[AzureScout] Failed to load assessment file $($_.FullName): $_" }
        }
}


<#
$PrivateFiles = @( Get-ChildItem -Path (Join-Path $PSScriptRoot "Modules" "Private" "*.ps1") -Recurse -ErrorAction SilentlyContinue )
$PublicFiles = @( Get-ChildItem -Path (Join-Path $PSScriptRoot "Modules" "Public" "PublicFunctions" "*.ps1") -Recurse -ErrorAction SilentlyContinue )

Foreach($import in @($PrivateFiles + $PublicFiles))
{
    Try
    {
        . $import.fullname
    }
    Catch
    {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

Export-ModuleMember -Function $PublicFiles.Basename

#>
