#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Resolves the report, diagram cache, and report cache paths for an Azure Scout run.

.DESCRIPTION
Builds the folder layout for a single run. By default every invocation gets its own
run folder underneath the base path, so a second scan never overwrites the cache or
report of a previous one. Pass -Force to write directly into the base path, which is
the pre-2.3.0 behaviour.

.PARAMETER ReportDir
Base directory for output. Defaults to C:\AzureScout on Windows, $HOME/AzureScout elsewhere.

.PARAMETER RunName
Friendly name for this run's folder instead of the generated timestamp. Invalid path
characters are replaced with '-'.

.PARAMETER ScopeId
Optional scope identifier (normally a tenant ID) appended to the generated timestamp so
runs against different tenants are distinguishable at a glance.

.PARAMETER Force
Write into the base path directly, overwriting any previous run in place.

.Link
https://github.com/thisismydemo/azure-scout/src/Set-AZTIReportPath.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>

function Set-AZSCReportPath {
    Param(
        $ReportDir,
        [string]$RunName,
        [string]$ScopeId,
        [switch]$Force
    )

    if ($ReportDir)
        {
            $BasePath = $ReportDir
        }
    elseif (Resolve-Path -Path 'C:\' -ErrorAction SilentlyContinue)
        {
            $BasePath = Join-Path 'C:\' 'AzureScout'
        }
    else
        {
            $BasePath = Join-Path "$HOME" 'AzureScout'
        }

    # -Force keeps the historical behaviour: everything lands in the base path and a
    # rerun overwrites whatever was there. Without it, each run is isolated.
    if ($Force.IsPresent)
        {
            $RunFolder   = $null
            $DefaultPath = $BasePath
        }
    else
        {
            if ($RunName)
                {
                    $RunFolder = ConvertTo-AZSCSafeRunName -Name $RunName
                }
            else
                {
                    $RunFolder = Get-Date -Format 'yyyy-MM-dd_HHmmss_fff'
                    if ($ScopeId)
                        {
                            $ScopeToken = ConvertTo-AZSCSafeRunName -Name ([string]$ScopeId)
                            if ($ScopeToken.Length -gt 8) { $ScopeToken = $ScopeToken.Substring(0, 8) }
                            $RunFolder = $RunFolder + '_' + $ScopeToken
                        }
                }

            # Reserve the run directory here, atomically, instead of merely returning a
            # same-second candidate that Set-AZSCFolder creates later. Concurrent invocations
            # must never share cache, report, transcript, or cleanup ownership.
            if (-not (Test-Path -LiteralPath $BasePath -PathType Container)) {
                New-Item -ItemType Directory -Path $BasePath -Force -ErrorAction Stop | Out-Null
            }

            $PreferredRunFolder = $RunFolder
            $DefaultPath = $null
            for ($attempt = 0; $attempt -lt 100; $attempt++) {
                $CandidateName = if ($attempt -eq 0) { $PreferredRunFolder } else { "$PreferredRunFolder-$attempt" }
                $CandidatePath = Join-Path $BasePath $CandidateName
                try {
                    New-Item -ItemType Directory -Path $CandidatePath -ErrorAction Stop | Out-Null
                    $RunFolder = $CandidateName
                    $DefaultPath = $CandidatePath
                    break
                }
                catch {
                    if (Test-Path -LiteralPath $CandidatePath -PathType Container) { continue }
                    throw
                }
            }
            if (-not $DefaultPath) {
                throw "Could not allocate a unique Azure Scout run folder under '$BasePath' after 100 attempts."
            }
        }

    $DiagramCache = Join-Path $DefaultPath 'DiagramCache'
    $ReportCache  = Join-Path $DefaultPath 'ReportCache'

    $ReportPath = @{
        'DefaultPath'  = $DefaultPath;
        'DiagramCache' = $DiagramCache;
        'ReportCache'  = $ReportCache;
        'BasePath'     = $BasePath;
        'RunFolder'    = $RunFolder
    }

    return $ReportPath
}

function ConvertTo-AZSCSafeRunName {
    Param([string]$Name)

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $builder = [System.Text.StringBuilder]::new()
    foreach ($char in $Name.ToCharArray())
        {
            if ($invalid -contains $char) { [void]$builder.Append('-') } else { [void]$builder.Append($char) }
        }
    $safe = $builder.ToString().Trim().Trim('.')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = Get-Date -Format 'yyyy-MM-dd_HHmmss_fff' }
    return $safe
}
