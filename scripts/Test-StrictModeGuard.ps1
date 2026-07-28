#Requires -Version 7.0

<#
.SYNOPSIS
    Fails if any Set-StrictMode call in the shipped module WEAKENS strict mode, unless that exact
    site is on the annotated allow-list below (AB#5672).

.DESCRIPTION
    The HCS scripting standard requires `Set-StrictMode -Version Latest`. Anything else -- `-Off`,
    `-Version 1.0`, `-Version 2.0`, `-Version 3.0` -- is a WEAKENING, and every weakening is a place
    the defect class AB#5633 / AB#5667 / AB#5671 exist to eliminate can quietly come back:

      * a property read on an ABSENT member returns $null instead of throwing,
      * member enumeration over an empty collection returns nothing instead of throwing,
      * an out-of-range array index returns $null instead of throwing.

    Those are not conveniences. Each one is a wrong VALUE silently reaching a report, and each one
    shipped at least once (six crashes traced to the first, two to `@($null).Count -eq 0` never
    firing, a whole empty Security worksheet to the third).

    The guard is an ALLOW-LIST, not a ban, because twenty such sites already exist and removing them
    is a bigger job than adding this check. What it buys is that the number can only go DOWN:

      * a weakening at a site NOT on the list fails the build -- nobody adds a twenty-first,
      * a site on the list that has DISAPPEARED also fails the build, with a message saying to
        delete its entry -- so the list cannot rot into a fiction the way the collector StrictMode
        baseline once did (it shipped empty while 24 collectors were failing).

.PARAMETER RepoRoot
    Repository root. Defaults to the parent of this script's directory.

.PARAMETER IgnoreStaleAllowList
    Skip the "an allow-listed file no longer weakens StrictMode" check.

    Only for pointing the scanner at a throwaway tree, which by definition contains none of the
    allow-listed files and would therefore report all of them stale -- see the sandbox cases in
    tests/StrictModeGuard.Tests.ps1. Never pass this in CI: the stale check is half the value, because
    it is what stops the allow-list decaying into a list of files that have not weakened anything for
    two releases.

.OUTPUTS
    Writes a GitHub Actions ::error:: annotation per violation and exits 1, or exits 0 when clean.
    tests/StrictModeGuard.Tests.ps1 calls the same scanner so the check runs locally too.

.EXAMPLE
    pwsh -File scripts/Test-StrictModeGuard.ps1
#>

[CmdletBinding()]
param(
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch] $IgnoreStaleAllowList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===================================================================================================
# THE ALLOW-LIST
# ===================================================================================================
# Every pre-existing weakening, with why it is still there. Paths are repo-relative, '/'-separated.
#
# Two groups, and the distinction matters to whoever picks this up next:
#
#  LIVE      -- on a real code path today. Lifting one needs the code underneath it to survive strict
#               mode first.
#  DEAD      -- the enclosing function is not called from ANY product code; it is referenced only by
#               its own unit tests. v2.6.0 deleted the background-job engine these belong to and left
#               the functions behind. Their opt-outs are therefore not load-bearing in any real run,
#               but deleting them means deleting the functions, which reddens six test files and is a
#               separate piece of work, not a StrictMode fix.
$AllowList = @(
    # ---- LIVE ---------------------------------------------------------------------------------
    @{ Path = 'src/pipeline/Invoke-ScoutCollector.ps1'
       State = 'LIVE'
       Reason = 'Wraps the 176 InventoryModules collectors. AB#5671 converted every collector that the recorded fixtures exercise, and tests/CollectorStrictMode.Tests.ps1 now runs all 174 Standard collectors under -Version Latest with zero failures -- so on the evidence available this opt-out is ready to be lifted. It is NOT lifted here only because src/pipeline is owned by the concurrent declarative-collector work; lifting it is the obvious next move once that lands.' }
    @{ Path = 'src/ingest/Import-AzGovViz.ps1'
       State = 'LIVE'
       Reason = 'Parses third-party AzGovViz output, whose shape this repo does not control and has no fixtures for. Needs recorded fixtures before it can be tightened.' }
    @{ Path = 'src/report/renderers/inventory/style/Start-AZSCExcelCustomization.ps1'
       State = 'LIVE'
       Reason = 'Walks EPPlus worksheet objects whose members vary by sheet content. Needs its own conversion pass.' }
    @{ Path = 'src/Start-AZTIExtractionOrchestration.ps1'; State = 'DEAD'; Reason = 'Migrated job-era orchestration compatibility surface.' }
    @{ Path = 'src/Start-AZTIProcessOrchestration.ps1'; State = 'DEAD'; Reason = 'Migrated job-era orchestration compatibility surface.' }
    @{ Path = 'src/Start-AZTIReporOrchestration.ps1'; State = 'DEAD'; Reason = 'Migrated job-era orchestration compatibility surface.' }
    @{ Path = 'src/pipeline/Start-ScoutExtraJobs.ps1'; State = 'DEAD'; Reason = 'Migrated job-era extra-data fan-out.' }
    @{ Path = 'src/pipeline/jobs/Start-ScoutAdvisoryJob.ps1'; State = 'DEAD'; Reason = 'Migrated job-era compatibility function.' }
    @{ Path = 'src/pipeline/jobs/Start-ScoutPolicyJob.ps1'; State = 'DEAD'; Reason = 'Migrated job-era compatibility function.' }
    @{ Path = 'src/pipeline/jobs/Start-ScoutSecCenterJob.ps1'; State = 'DEAD'; Reason = 'Migrated job-era compatibility function.' }
    @{ Path = 'src/pipeline/jobs/Start-ScoutSubscriptionJob.ps1'; State = 'DEAD'; Reason = 'Migrated job-era compatibility function.' }
    @{ Path = 'src/pipeline/diagram/Build-ScoutDiagramSubnet.ps1'; State = 'DEAD'; Reason = 'Migrated job-era diagram compatibility function.' }
    @{ Path = 'src/pipeline/diagram/Set-ScoutDiagramFile.ps1'; State = 'DEAD'; Reason = 'Migrated job-era diagram compatibility function.' }
    @{ Path = 'src/pipeline/diagram/Start-ScoutDiagramJob.ps1'; State = 'DEAD'; Reason = 'Migrated job-era diagram compatibility function.' }
    @{ Path = 'src/pipeline/diagram/Start-ScoutDiagramNetwork.ps1'; State = 'DEAD'; Reason = 'Migrated job-era diagram compatibility function.' }
    @{ Path = 'src/pipeline/diagram/Start-ScoutDiagramOrganization.ps1'; State = 'DEAD'; Reason = 'Migrated job-era diagram compatibility function.' }
    @{ Path = 'src/pipeline/diagram/Start-ScoutDiagramSubscription.ps1'; State = 'DEAD'; Reason = 'Migrated job-era diagram compatibility function.' }
    @{ Path = 'src/pipeline/diagram/Start-ScoutDrawIoDiagram.ps1'; State = 'DEAD'; Reason = 'Migrated job-era diagram compatibility function.' }

    # ---- DEAD (job-era leftovers; verified unreferenced outside tests/) ------------------------
    @{ Path = 'Modules/Private/Main/Start-AZTIExtractionOrchestration.ps1'; State = 'DEAD'; Reason = 'Job-era orchestration; referenced only by tests.' }
    @{ Path = 'Modules/Private/Main/Start-AZTIProcessOrchestration.ps1';    State = 'DEAD'; Reason = 'Job-era orchestration; referenced only by tests.' }
    @{ Path = 'Modules/Private/Main/Start-AZTIReporOrchestration.ps1';      State = 'DEAD'; Reason = 'Job-era orchestration; referenced only by tests.' }
    @{ Path = 'Modules/Private/Processing/Start-AZTIExtraJobs.ps1';         State = 'DEAD'; Reason = 'Job-era extra-data fan-out; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Jobs/Start-AZTIAdvisoryJob.ps1';     State = 'DEAD'; Reason = 'Job-era; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Jobs/Start-AZTIPolicyJob.ps1';       State = 'DEAD'; Reason = 'Job-era; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Jobs/Start-AZTISecCenterJob.ps1';    State = 'DEAD'; Reason = 'Job-era; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Jobs/Start-AZTISubscriptionJob.ps1'; State = 'DEAD'; Reason = 'Job-era; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Diagram/Build-AZTIDiagramSubnet.ps1';       State = 'DEAD'; Reason = 'Diagram fan-out predating the AB#5649 single-pass diagram; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Diagram/Set-AZTIDiagramFile.ps1';           State = 'DEAD'; Reason = 'Diagram fan-out predating the AB#5649 single-pass diagram; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Diagram/Start-AZTIDiagramJob.ps1';          State = 'DEAD'; Reason = 'Diagram fan-out predating the AB#5649 single-pass diagram; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Diagram/Start-AZTIDiagramNetwork.ps1';      State = 'DEAD'; Reason = 'Diagram fan-out predating the AB#5649 single-pass diagram; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Diagram/Start-AZTIDiagramOrganization.ps1'; State = 'DEAD'; Reason = 'Diagram fan-out predating the AB#5649 single-pass diagram; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Diagram/Start-AZTIDiagramSubscription.ps1'; State = 'DEAD'; Reason = 'Diagram fan-out predating the AB#5649 single-pass diagram; referenced only by tests.' }
    @{ Path = 'Modules/Public/PublicFunctions/Diagram/Start-AZTIDrawIODiagram.ps1';       State = 'DEAD'; Reason = 'Diagram fan-out predating the AB#5649 single-pass diagram; referenced only by tests.' }
)

# v3 removes Modules/ entirely.  Keep the historical entries above as migration context, but do
# not let deleted paths participate in the executable guard baseline.
$AllowList = @($AllowList | Where-Object { $_.Path -notlike 'Modules/*' -and $_.Path -ne 'src/pipeline/Invoke-ScoutCollector.ps1' })

# Directories that ship. tests/ is deliberately excluded: a test may need to demonstrate the unsafe
# behaviour it is asserting against, and tests/CollectorStrictMode.Tests.ps1 does exactly that.
$ScanRoots = @('Modules', 'src', 'scripts')

function Get-AZSCStrictModeWeakening {
    <#
    .SYNOPSIS
        Every Set-StrictMode call under $ScanRoots (plus AzureScout.psm1) that is not -Version Latest.

    .DESCRIPTION
        Parsed with the PowerShell AST, not grepped: a regex over source text cannot tell a real call
        from the words "Set-StrictMode -Off" inside a comment or a here-string, and this repo's
        collectors are full of comments discussing exactly that.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)

    $Files = @(
        foreach ($ScanRoot in $ScanRoots) {
            $FullRoot = Join-Path $Root $ScanRoot
            if (Test-Path -LiteralPath $FullRoot) {
                Get-ChildItem -LiteralPath $FullRoot -Recurse -File -Include '*.ps1', '*.psm1'
            }
        }
        Get-ChildItem -LiteralPath $Root -File -Filter '*.psm1'
    )

    foreach ($File in $Files) {
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref] $Tokens, [ref] $Errors)
        if ($Errors -and $Errors.Count -gt 0) {
            Write-Warning "skipping unparsable file: $($File.FullName)"
            continue
        }

        $Calls = $Ast.FindAll({
            param($Node)
            $Node -is [System.Management.Automation.Language.CommandAst] -and
            $Node.GetCommandName() -eq 'Set-StrictMode'
        }, $true)

        foreach ($Call in $Calls) {
            $Text = $Call.Extent.Text
            # Anything other than an explicit -Version Latest is a weakening. `-Off` obviously is;
            # so is -Version 1.0/2.0/3.0, each of which drops one or more of the three checks.
            if ($Text -match '(?i)-Version\s+Latest') { continue }

            [PSCustomObject]@{
                Path   = ($File.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
                Line   = $Call.Extent.StartLineNumber
                Call   = $Text.Trim()
            }
        }
    }
}

$Found       = @(Get-AZSCStrictModeWeakening -Root $RepoRoot)
$AllowedPath = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($Entry in $AllowList) { [void] $AllowedPath.Add($Entry.Path) }

$New = @($Found | Where-Object { -not $AllowedPath.Contains($_.Path) })

$FoundPath = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($Item in $Found) { [void] $FoundPath.Add($Item.Path) }
# NOT `$Stale = if (...) { @() } else { ... }`. An `if` used as an expression returns its branch
# through the pipeline, and an EMPTY array enumerates to nothing, so $Stale would land as $null and
# `$Stale.Count` below would throw -- under this very guard, which runs with StrictMode Latest. That
# is the same `@()`-collapse this branch fixed in VirtualMachineScaleSet.ps1; it is an easy mistake
# to make twice, which is rather the point of the guard existing.
$Stale = @()
if (-not $IgnoreStaleAllowList) {
    $Stale = @($AllowList | Where-Object { -not $FoundPath.Contains($_.Path) })
}

$Live = @($AllowList | Where-Object { $_.State -eq 'LIVE' }).Count
$Dead = @($AllowList | Where-Object { $_.State -eq 'DEAD' }).Count

Write-Host "[AzureScout] StrictMode guard (AB#5672): $($Found.Count) weakening site(s) found across $($FoundPath.Count) file(s); allow-list holds $($AllowList.Count) file(s) -- $Live live, $Dead dead."

foreach ($Violation in $New) {
    Write-Host "::error file=$($Violation.Path),line=$($Violation.Line)::StrictMode weakening '$($Violation.Call)' is not on the allow-list in scripts/Test-StrictModeGuard.ps1. Shipped module code must use Set-StrictMode -Version Latest (AB#5672). If this site is genuinely unavoidable, add it to the allow-list WITH a reason; do not delete the guard."
}

foreach ($Entry in $Stale) {
    Write-Host "::error::scripts/Test-StrictModeGuard.ps1 allow-lists '$($Entry.Path)' but that file no longer weakens StrictMode. Delete the entry -- the point of the list is that it only ever gets shorter (AB#5672)."
}

if ($New.Count -gt 0 -or $Stale.Count -gt 0) {
    Write-Host "::error::StrictMode guard failed: $($New.Count) new weakening(s), $($Stale.Count) stale allow-list entr(ies)."
    exit 1
}

Write-Host '[AzureScout] StrictMode guard: OK -- no new weakening, no stale allow-list entry.'
exit 0
