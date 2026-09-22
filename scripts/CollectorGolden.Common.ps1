#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Shared canonicalisation helpers for collector golden-output capture and verification.

.DESCRIPTION
    Committed golden records are the behavioral reference for the v3 engine,
    but that tree is scheduled for deletion. These helpers preserve the exact comparison contract
    used by tests/DeclarativeCollectorEquivalence.Tests.ps1 without preserving executable code:

    - row order is significant;
    - row keys are sorted because hashtable enumeration order is not significant;
    - null, empty string, empty array, scalar and array values remain distinguishable;
    - worksheet column order and every rendered cell remain significant.

    Keep this file dependency-free. The capture script and Pester suite both dot-source it.

.NOTES
    Tracks the proof-preservation prerequisite for Epic AB#5638.
#>

function ConvertTo-ScoutComparableValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return '<null>' }
    if ($Value -is [string]) { return "s:$Value" }

    try {
        return 'j:' + (ConvertTo-Json -InputObject $Value -Depth 12 -Compress)
    }
    catch {
        return 'x:' + [string]$Value
    }
}

function ConvertTo-ScoutComparableRow {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        $Row
    )

    if ($null -eq $Row) { return '<null-row>' }
    if ($Row -isnot [System.Collections.IDictionary]) {
        return "<non-row:$($Row.GetType().Name)>$(ConvertTo-ScoutComparableValue -Value $Row)"
    }

    $Keys = @($Row.Keys | Sort-Object)
    return (($Keys | ForEach-Object {
        "$_=$(ConvertTo-ScoutComparableValue -Value $Row[$_])"
    }) -join '|')
}

function ConvertTo-ScoutWorksheetText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Worksheet
    )

    $Sheet = @(Import-Excel -Path $Path -WorksheetName $Worksheet)
    if ($Sheet.Count -eq 0) { return '<empty>' }

    $Columns = @($Sheet[0].PSObject.Properties.Name)
    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add(($Columns -join "`t"))

    foreach ($Row in $Sheet) {
        $Lines.Add((($Columns | ForEach-Object { [string]$Row.$_ }) -join "`t"))
    }

    return ($Lines -join "`n")
}

function Get-ScoutFixtureSha256 {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Collector fixture not found: $Path"
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Import-ScoutGoldenOutput {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [AllowNull()]
        [string]$FixturePath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Golden collector output not found: $Path. Add a reviewed canonical record before changing this collector definition."
    }

    $Golden = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($Golden.SchemaVersion -ne 1) {
        throw "Golden collector output '$Path' uses unsupported schema version '$($Golden.SchemaVersion)'."
    }

    foreach ($Property in @('Category', 'Name', 'FixturePath', 'FixtureSha256', 'Rows', 'Workbook')) {
        if (@($Golden.PSObject.Properties.Name) -notcontains $Property) {
            throw "Golden collector output '$Path' is missing '$Property'."
        }
    }

    foreach ($TagState in @('WithoutTags', 'WithTags')) {
        if (@($Golden.Workbook.PSObject.Properties.Name) -notcontains $TagState) {
            throw "Golden collector output '$Path' is missing Workbook.$TagState."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($FixturePath)) {
        $ActualHash = Get-ScoutFixtureSha256 -Path $FixturePath
        if ($Golden.FixtureSha256 -ne $ActualHash) {
            throw "Golden collector output '$Path' was captured from fixture hash '$($Golden.FixtureSha256)', but '$FixturePath' is '$ActualHash'. Regenerate the golden output from the current fixture."
        }
    }

    return $Golden
}
