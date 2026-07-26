<#
.Synopsis
Module for Excel Job Processing

.DESCRIPTION
This script processes inventory modules and builds the Excel report.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/3.ReportingFunctions/Start-AZSCExcelJob.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Start-AZSCExcelJob {
    Param($ReportCache, $File, $TableStyle)

    # AB#5662: this file moved from Modules/Private/Reporting to src/report/renderers/inventory,
    # four levels below the repo root (inventory -> renderers -> report -> src -> root), so the
    # walk-up depth to reach Modules/Public/InventoryModules changed from 2 to 4.
    $RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent
    $InventoryModulesPath = Join-Path $RepoRoot 'Modules' 'Public' 'InventoryModules'
    $ModuleFolders = Get-ChildItem -Path $InventoryModulesPath -Directory

    Write-Progress -activity 'Azure Inventory' -Status "68% Complete." -PercentComplete 68 -CurrentOperation "Starting the Report Loop.."

    $ModulesCount = [string]@(Get-ChildItem -Path $InventoryModulesPath -Recurse -Filter "*.ps1").count

    Write-Output 'Starting to Build Excel Report.'
    Write-Host 'Supported Resource Types: ' -NoNewline -ForegroundColor Green
    Write-Host $ModulesCount -ForegroundColor Cyan

    $Lops = $ModulesCount
    $ReportCounter = 0

    # Dedicated tabs (Cost Management, Security Overview, Azure Update Manager,
    # Azure Monitor) are created by Build-AZSC*Report functions called from
    # Start-AZSCExtraReports later in the pipeline. No placeholder creation needed here.

    Foreach ($ModuleFolder in $ModuleFolders)
        {
            $CacheData = $null
            $ModulePath = Join-Path $ModuleFolder.FullName '*.ps1'
            $ModuleFiles = Get-ChildItem -Path $ModulePath

            $CacheFiles = Get-ChildItem -Path $ReportCache -Recurse
            $JSONFileName = ($ModuleFolder.Name + '.json')
            $CacheFile = $CacheFiles | Where-Object { $_.Name -like "*$JSONFileName" }

            if ($CacheFile)
                {
                    $CacheFileContent = New-Object System.IO.StreamReader($CacheFile.FullName)
                    $CacheData = $CacheFileContent.ReadToEnd()
                    $CacheFileContent.Dispose()
                    $CacheData = $CacheData | ConvertFrom-Json
                }

            Foreach ($Module in $ModuleFiles)
                {
                    $c = (($ReportCounter / $Lops) * 100)
                    $c = [math]::Round($c)
                    Write-Progress -Id 1 -activity "Building Report" -Status "$c% Complete." -PercentComplete $c

                    $ModuleFileContent = New-Object System.IO.StreamReader($Module.FullName)
                    $ModuleData = $ModuleFileContent.ReadToEnd()
                    $ModuleFileContent.Dispose()
                    $ModName = $Module.Name.replace(".ps1","")

                    # Guarded: $CacheData can be $null (no cache file for this folder), and
                    # dynamic property access ($CacheData.$ModName) on $null — or on a key that
                    # doesn't exist in the parsed JSON — throws under StrictMode.
                    $SmaResources = if ($CacheData -and $CacheData.PSObject.Properties.Name -contains $ModName) { $CacheData.$ModName } else { $null }

                    # @($null).Count is 1, NOT 0. The guard below was `@($SmaResources).count`,
                    # so a module with no cache data scored 1 and was invoked anyway — every one
                    # of the 176 collectors ran in Reporting mode on every run, not just the
                    # ~30 that had rows. Mostly that was only wasted work, because a collector
                    # opens with `if ($SmaResources)`. It stopped being harmless for the two
                    # Identity files whose top-level statement is Register-AZSCInventoryModule:
                    # invoking them at all throws, and that killed the Excel build outright.
                    # Filtering out the nulls makes the count mean what it reads as. (AB#5649)
                    $ModuleResourceCount = @($SmaResources).Where({ $null -ne $_ }).Count

                    # The same two files must never be invoked here either, data or not. The
                    # processing pipeline already refuses them by contract; this is the second
                    # place that iterates the collector set, and it had drifted apart from the
                    # first — which is exactly how this reached a live run.
                    $Unsupported = $ModuleData -match '(?m)^\s*Register-AZSCInventoryModule'

                    if ($ModuleResourceCount -gt 0 -and -not $Unsupported)
                    {
                        Start-Sleep -Milliseconds 25
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Running Module: '$ModName'. Excel Rows: $ModuleResourceCount")

                        $ScriptBlock = [Scriptblock]::Create($ModuleData)

                        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $PSScriptRoot, $null, $InTag, $null, $null, 'Reporting', $file, $SmaResources, $TableStyle, $null

                    }

                    $ReportCounter ++

                }
                Remove-Variable -Name CacheData
                Remove-Variable -Name SmaResources
                Clear-AZSCMemory
        }
        Write-Progress -Id 1 -activity "Building Report" -Status "100% Complete." -Completed
    }