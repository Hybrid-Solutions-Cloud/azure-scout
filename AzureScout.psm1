#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

# Core dependencies are declared in AzureScout.psd1. PowerShell Gallery installs
# resolve them during Install-Module; source-tree imports fail cleanly when one is
# missing and never install software merely because the module was imported.
# Az.CostManagement remains optional and is checked only when -IncludeCosts is used.

# v3 engine — the module loads implementation code exclusively from src/;
# collector behavior is supplied by manifests/collectors rather than scripts.
$_assessmentRoot = Join-Path $PSScriptRoot 'src'
if (Test-Path $_assessmentRoot) {
    Get-ChildItem -Path $_assessmentRoot -Filter '*.ps1' -Recurse |
        Sort-Object FullName | ForEach-Object {
            try { . $_.FullName }
            catch { throw "[AzureScout] Failed to load required engine file '$($_.FullName)': $($_.Exception.Message)" }
        }
}

#region — Update check (AB#369)
# On import, optionally surface (never silently apply) a newer AzureScout release:
# surface (never silently apply) a newer AzureScout release from PSGallery. The guts of
# the check (throttle, CI detection, Find-Module lookup, notify-vs-update opt-in) live in
# Test-AZSCModuleUpdate (src) so it can be unit-tested with Pester
# mocks -- see that function's comment-based help for the full design rationale. This
# outer try/catch is a second, redundant safety net so a missing/broken function can
# never fail module import either.
try {
    Test-AZSCModuleUpdate
} catch {
    Write-Verbose "[AzureScout] Update check failed to run: $_"
}
#endregion

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
