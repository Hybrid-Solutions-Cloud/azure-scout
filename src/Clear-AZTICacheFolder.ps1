#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Clear cache folder for Azure Resource Inventory

.DESCRIPTION
Clears the per-run cache folder, or prunes whole run folders older than a given number
of days when -OlderThan is supplied.

.PARAMETER ReportCache
The run's ReportCache folder. Every file underneath it is removed.

.PARAMETER OlderThan
Prune mode. Removes entire run folders under -BasePath whose last write time is older
than this many days. Run folders are the timestamped (or -RunName) directories created
by Set-AZSCReportPath.

.PARAMETER BasePath
Base output directory to prune. Defaults to the same base Set-AZSCReportPath resolves.

.EXAMPLE
Clear-AZSCCacheFolder -ReportCache 'C:\AzureScout\2026-07-25_101500\ReportCache'

.EXAMPLE
Clear-AZSCCacheFolder -OlderThan 30

Removes every run folder that has not been written to in the last 30 days.

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Private/0.MainFunctions/Clear-AZSCCacheFolder.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>

function Clear-AZSCCacheFolder {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    Param(
        $ReportCache,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$OlderThan = 0,
        [string]$BasePath
    )

    if ($OlderThan -gt 0)
        {
            if (-not $BasePath)
                {
                    $BasePath = (Set-AZSCReportPath -Force).DefaultPath
                }

            if (-not (Test-Path -LiteralPath $BasePath -PathType Container))
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Base path does not exist, nothing to prune: '+$BasePath)
                    return
                }

            $ResolvedBase = Get-Item -LiteralPath $BasePath -Force
            if ($ResolvedBase.FullName -eq $ResolvedBase.Root.FullName)
                {
                    throw "Refusing to prune a filesystem root: $($ResolvedBase.FullName)"
                }

            $Cutoff = (Get-Date).AddDays(-$OlderThan)
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Pruning run folders older than '+$Cutoff.ToString('yyyy-MM-dd_HH_mm_ss')+' under '+$BasePath)

            $RunFolders = Get-ChildItem -LiteralPath $ResolvedBase.FullName -Directory -Force -ErrorAction SilentlyContinue
            Foreach ($RunFolder in $RunFolders)
                {
                    if (($RunFolder.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
                        {
                            Write-Warning "Skipping reparse-point directory while pruning Azure Scout runs: $($RunFolder.FullName)"
                            continue
                        }

                    # Run names are operator-selectable, so folder names cannot safely identify a
                    # run. Require the cache layout Set-AZSCReportPath creates before deleting an
                    # old child; unrelated directories under a shared report base are preserved.
                    $HasRunLayout =
                        (Test-Path -LiteralPath (Join-Path $RunFolder.FullName 'ReportCache') -PathType Container) -or
                        (Test-Path -LiteralPath (Join-Path $RunFolder.FullName 'DiagramCache') -PathType Container)

                    if (-not $HasRunLayout)
                        {
                            Write-Warning "Skipping directory that is not recognisable as an Azure Scout run: $($RunFolder.FullName)"
                            continue
                        }

                    if ($RunFolder.LastWriteTime -lt $Cutoff -and $PSCmdlet.ShouldProcess($RunFolder.FullName, 'Remove old Azure Scout run folder'))
                        {
                            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Removing run folder: '+$RunFolder.FullName)
                            Remove-Item -LiteralPath $RunFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                }
            return
        }

    if (-not $ReportCache) { return }

    if (-not (Test-Path -LiteralPath $ReportCache -PathType Container))
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Cache folder does not exist: '+$ReportCache)
            return
        }

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Clearing Cache Folder.')
    $CacheFiles = Get-ChildItem -LiteralPath $ReportCache -Recurse -File
    Foreach ($CacheFile in $CacheFiles)
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Removing Cache File: '+$CacheFile.FullName)
            if ($PSCmdlet.ShouldProcess($CacheFile.FullName, 'Remove Azure Scout cache file'))
                {
                    Remove-Item -LiteralPath $CacheFile.FullName -Force
                }
        }
}
