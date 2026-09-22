#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Emit star-schema CSVs and copy the .pbit template bound to them.

.NOTES
    Tracks ADO Story AB#5046.
#>
function Export-PowerBi {
    param($Findings, $Collect, [string] $OutputPath)
    $pbiDir = Join-Path $OutputPath 'powerbi'
    New-Item -ItemType Directory -Path $pbiDir -Force | Out-Null

    # Emit a normalized AreaKey (lowercased, trimmed "framework|area") into both
    # the area and findings tables so the Power BI relationship binds on a stable
    # key instead of fragile raw-text (Framework, Area) equality (AB#5092).
    function New-AreaKey($fw, $ar) { ("{0}|{1}" -f $fw, $ar).ToLower().Trim() }

    # $Findings.Areas/.Frameworks/.Gaps/.Findings dot directly into a possibly-
    # $null $Findings (e.g. a standalone re-render from a hand-edited/partial
    # findings.json) -- $null.Areas throws PropertyNotFoundException under
    # Set-StrictMode -Version Latest rather than returning $null, unlike every
    # other renderer in this folder (which all read through a Get-Scout*Prop
    # helper for exactly this reason). @() degrades to empty CSVs, not a crash.
    function Get-ScoutPowerBiProp {
        param($Obj, [Parameter(Mandatory)][string] $Name)
        if ($null -eq $Obj) { return @() }
        $prop = $Obj.PSObject.Properties[$Name]
        if ($prop) { return @($prop.Value) } else { return @() }
    }

    (Get-ScoutPowerBiProp $Findings 'Areas') | Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, * |
        Export-Csv "$pbiDir/fact_area_scores.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Frameworks') | Export-Csv "$pbiDir/fact_framework.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Gaps') | Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, * |
        Export-Csv "$pbiDir/dim_gaps.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Findings') |
        Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, Id, Framework, Area, Severity, Status, EvidenceCount, Title, Remediation, Manual |
        Export-Csv "$pbiDir/fact_findings.csv" -NoTypeInformation

    # Generate the Power BI Template (.pbit) bound to the star-schema CSVs above.
    # Uses the schema-agnostic generator (New-AZSCPowerBITemplate), which builds the
    # DataModelSchema and Power Query (M) directly from the CSV headers — so there is
    # no static template to maintain or check in (AB#5046). Failure is non-fatal: the
    # CSVs + README still let a user import the star schema by hand.
    $pbitPath = Join-Path $pbiDir 'report.pbit'
    $pbitMade = $false
    try {
        if (-not (Get-Command -Name New-AZSCPowerBITemplate -ErrorAction SilentlyContinue)) {
            # AB#5662: New-AZSCPowerBITemplate.ps1 moved from Modules/Private/Reporting to
            # src/report/renderers/inventory as part of the reporting-layer consolidation.
            . "$PSScriptRoot/inventory/New-AZSCPowerBITemplate.ps1"
        }
        New-AZSCPowerBITemplate -PowerBIDir $pbiDir -OutputFile $pbitPath | Out-Null
        $pbitMade = Test-Path $pbitPath
    }
    catch {
        Write-Warning ("Power BI .pbit generation skipped: {0}. The star-schema CSVs and README below are still available for manual import." -f $_.Exception.Message)
    }

    $pbitLine = if ($pbitMade) {
        "Open report.pbit in Power BI Desktop and click Refresh when prompted (the model was built from a snapshot)."
    } else {
        "No report.pbit was generated; import the CSVs below manually in Power BI Desktop."
    }
    @"
$pbitLine
If the CSV folder has moved, re-point the FolderPath parameter to:
  $pbiDir
The model is a star schema: fact_findings + dim_gaps + fact_area_scores + fact_framework, joined on AreaKey.
"@ | Out-File "$pbiDir/README.txt"
}
