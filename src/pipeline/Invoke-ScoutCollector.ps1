#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Runs one manifest-defined inventory collector with contained failure handling.

.DESCRIPTION
    v3 executes the committed declarative catalog exclusively.  The prior imperative-script
    fallback has been removed: a malformed descriptor is a contained collector failure, never a
    reason to re-enter the retired Modules tree.  Behavioural equivalence is retained by the
    committed golden records in tests/DeclarativeCollectorGolden.Tests.ps1.
#>
function Invoke-ScoutCollector {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSCustomObject]$Collector,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Context

    )

    $Started = Get-Date
    $Rows = @()
    $Failure = $null

    try {
        if (-not [bool]$Collector.HasDeclarativeDefinition -or
            [string]::IsNullOrWhiteSpace([string]$Collector.DefinitionPath)) {
            throw "Collector '$($Collector.FolderCategory)/$($Collector.Name)' has no declarative definition."
        }

        $Definition = Get-ScoutCollectorDefinition -Path $Collector.DefinitionPath
        $Rows = @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $Context)
    }
    catch {
        $Failure = $_
        $Rows = @()
        Write-Warning ("[AzureScout] Collector '{0}' ({1}, Declarative) failed and was skipped: {2}" -f
            $Collector.Name, $Collector.FolderCategory, $_.Exception.Message)
        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level 'WARN' -Message ("Collector {0}/{1} (Declarative) failed and was skipped: {2}" -f
                $Collector.FolderCategory, $Collector.Name, $_.Exception.Message)
        }
    }

    [PSCustomObject]@{
        Name           = $Collector.Name
        FolderCategory = $Collector.FolderCategory
        Success        = ($null -eq $Failure)
        Rows           = $Rows
        Mode           = 'Declarative'
        Error          = $Failure
        Duration       = (Get-Date) - $Started
    }
}
