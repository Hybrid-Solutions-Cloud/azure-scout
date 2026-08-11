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
    $ResourceTypes = @()

    try {
        if (-not [bool]$Collector.HasDeclarativeDefinition -or
            [string]::IsNullOrWhiteSpace([string]$Collector.DefinitionPath)) {
            throw "Collector '$($Collector.FolderCategory)/$($Collector.Name)' has no declarative definition."
        }

        $Definition = Get-ScoutCollectorDefinition -Path $Collector.DefinitionPath
        $ResourceTypes = @($Definition.ResourceTypes)
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

    $Duration = (Get-Date) - $Started
    $RowCount = @($Rows).Count
    $Status = if ($null -ne $Failure) { 'Failed' } elseif ($RowCount -gt 0) { 'Rows' } else { 'Empty' }

    if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
        Write-AZSCLog -Level 'DEBUG' -Message (
            'Collector {0}/{1}: status={2}; rows={3}; elapsed={4}' -f
                $Collector.FolderCategory,
                $Collector.Name,
                $Status,
                $RowCount,
                $Duration.ToString('dd\:hh\:mm\:ss\.fff')
        )
    }

    [PSCustomObject]@{
        Name           = $Collector.Name
        FolderCategory = $Collector.FolderCategory
        Success        = ($null -eq $Failure)
        Rows           = $Rows
        Mode           = 'Declarative'
        Error          = $Failure
        Duration       = $Duration
        ResourceTypes  = $ResourceTypes
    }
}
