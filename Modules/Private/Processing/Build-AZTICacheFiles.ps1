<#
.Synopsis
Module responsible for creating the local cache files for the report.

.DESCRIPTION
This module receives the job names for the Azure Resources that were processed previously and creates the local cache files that will be used to build the Excel report.

.Link
https://github.com/thisismydemo/azure-scout/Modules/Private/2.ProcessingFunctions/Build-AZSCCacheFiles.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola
#>

function Build-AZSCCacheFiles {
    Param($DefaultPath, $JobNames)

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Checking Cache Folder.')

    $Lops = @($JobNames).count
    $Counter = 0

    Foreach ($Job in $JobNames)
        {
            $c = (($Counter / $Lops) * 100)
            $c = [math]::Round($c)
            Write-Progress -Id 1 -activity "Building Cache Files" -Status "$c% Complete." -PercentComplete $c

            $NewJobName = ($Job -replace 'ResourceJob_','')

            # A job harvested before it finished yields nothing and is then destroyed by the
            # Remove-Job below, so its whole category silently vanishes from the report. That used
            # to happen without a trace. Surface it instead of writing a cache file that quietly
            # says the estate is empty. (AB#5629)
            $JobState = (Get-Job -Name $Job -ErrorAction SilentlyContinue).State
            if ($JobState -and $JobState -ne 'Completed')
                {
                    Write-Warning ("[AzureScout] Category '$NewJobName' is being collected while its job is in state " +
                        "'$JobState' rather than 'Completed'. Its data may be incomplete or empty in the report.")
                }

            $TempJob = Receive-Job -Name $Job
            if (-not $TempJob -or [string]::IsNullOrEmpty($TempJob.values))
                {
                    Write-Warning ("[AzureScout] Category '$NewJobName' returned no data; no cache file was written. " +
                        "If this category should contain resources, re-run and check the job state above.")
                }
            if ($TempJob -and ![string]::IsNullOrEmpty($TempJob.values))
                {
                    $JobJSONName = ($NewJobName+'.json')
                    $JobFileName = Join-Path $DefaultPath 'ReportCache' $JobJSONName
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Creating Cache File: '+ $JobFileName)
                    $TempJob | ConvertTo-Json -Depth 40 | Out-File $JobFileName
                }
            Remove-Job -Name $Job
            Remove-Variable -Name TempJob

            $Counter++

        }
    Clear-AZSCMemory
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Cache Files Created.')
}