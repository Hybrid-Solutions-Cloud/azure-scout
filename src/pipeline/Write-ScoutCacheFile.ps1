#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Write one category's collected rows to its ReportCache JSON file (AB#5649).

.DESCRIPTION
    Replaces `Build-AZSCCacheFiles`, which was inseparable from the job machinery: it took job
    NAMES, called `Receive-Job` and then `Remove-Job`. That coupling is what made an unfinished
    job destructive — the job was harvested empty and then deleted, so the category vanished
    from the report with no trace (AB#5629). It could not be tested without starting real jobs.

    This function takes data. There is no job to be in the wrong state, nothing to receive and
    nothing to destroy, so the whole failure mode is gone rather than guarded against.

.PARAMETER Category
    Category name; also the cache file's base name, preserving the layout the reporting phase
    reads (ReportCache/<Category>.json).

.PARAMETER Data
    Hashtable of collector name -> rows.

.PARAMETER CachePath
    The ReportCache directory.

.OUTPUTS
    PSCustomObject with Category, Path, RowCount and Written.

.NOTES
    Tracks ADO AB#5649 (Epic AB#5638).
#>
function Write-ScoutCacheFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Category,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Data,

        [Parameter(Mandatory, Position = 2)]
        [string]$CachePath
    )

    $RowCount = 0
    foreach ($Key in $Data.Keys) {
        $RowCount += @($Data[$Key]).Where({ $null -ne $_ }).Count
    }

    $FilePath = Join-Path $CachePath ($Category + '.json')

    # An all-empty category is not written, matching the old behaviour: the reporting phase
    # treats a missing cache file as "nothing of this kind in the estate". Writing a file full
    # of nulls instead produces empty worksheets.
    if ($RowCount -eq 0) {
        Write-Verbose "[AzureScout] Category '$Category' produced no rows; no cache file written."
        return [PSCustomObject]@{
            Category = $Category
            Path     = $FilePath
            RowCount = 0
            Written  = $false
        }
    }

    if (-not (Test-Path -LiteralPath $CachePath)) {
        $null = New-Item -Path $CachePath -ItemType Directory -Force
    }

    if ($PSCmdlet.ShouldProcess($FilePath, 'Write inventory cache file')) {
        $Data | ConvertTo-Json -Depth 40 | Out-File -LiteralPath $FilePath -Encoding utf8
    }

    [PSCustomObject]@{
        Category = $Category
        Path     = $FilePath
        RowCount = $RowCount
        Written  = $true
    }
}
