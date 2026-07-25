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
https://github.com/thisismydemo/azure-scout/Modules/Private/0.MainFunctions/Clear-AZSCCacheFolder.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>

function Clear-AZSCCacheFolder {
    Param(
        $ReportCache,
        [int]$OlderThan = 0,
        [string]$BasePath
    )

    if ($OlderThan -gt 0)
        {
            if (-not $BasePath)
                {
                    $BasePath = (Set-AZSCReportPath -Force).DefaultPath
                }

            if (-not (Test-Path -Path $BasePath -PathType Container))
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Base path does not exist, nothing to prune: '+$BasePath)
                    return
                }

            $Cutoff = (Get-Date).AddDays(-$OlderThan)
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Pruning run folders older than '+$Cutoff.ToString('yyyy-MM-dd_HH_mm_ss')+' under '+$BasePath)

            $RunFolders = Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue
            Foreach ($RunFolder in $RunFolders)
                {
                    if ($RunFolder.LastWriteTime -lt $Cutoff)
                        {
                            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Removing run folder: '+$RunFolder.FullName)
                            Remove-Item -Path $RunFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                }
            return
        }

    if (-not $ReportCache) { return }

    if (-not (Test-Path -Path $ReportCache -PathType Container))
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Cache folder does not exist: '+$ReportCache)
            return
        }

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Clearing Cache Folder.')
    $CacheFiles = Get-ChildItem -Path $ReportCache -Recurse -File
    Foreach ($CacheFile in $CacheFiles)
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Removing Cache File: '+$CacheFile.FullName)
            Remove-Item -Path $CacheFile.FullName -Force
        }
}
