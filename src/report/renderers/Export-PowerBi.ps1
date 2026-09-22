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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Collect', Justification = 'Kept for the uniform renderer signature dispatched by src/report/Export-Report.ps1 (all renderers take Findings/Collect/OutputPath).')]
    param($Findings, $Collect, [string] $OutputPath)
    $pbiDir = Join-Path $OutputPath 'powerbi'
    New-Item -ItemType Directory -Path $pbiDir -Force | Out-Null

    # Emit a normalized AreaKey (lowercased, trimmed "framework|area") into both
    # the area and findings tables so the Power BI relationship binds on a stable
    # key instead of fragile raw-text (Framework, Area) equality (AB#5092).
    function New-AreaKey($fw, $ar) { ("{0}|{1}" -f $fw, $ar).ToLower().Trim() }
    function ConvertTo-SafeCsvRow {
        param([Parameter(ValueFromPipeline)]$InputObject)
        process {
            $safe = [ordered]@{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $value = $property.Value
                if ($value -is [string] -and $value -match '^[\t\r\n ]*[=+\-@]') { $value = "'$value" }
                $safe[$property.Name] = $value
            }
            [pscustomobject]$safe
        }
    }

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
        ConvertTo-SafeCsvRow |
        Export-Csv "$pbiDir/fact_area_scores.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Frameworks') | ConvertTo-SafeCsvRow | Export-Csv "$pbiDir/fact_framework.csv" -NoTypeInformation
    (Get-ScoutPowerBiProp $Findings 'Gaps') | Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, * |
        ConvertTo-SafeCsvRow |
        Export-Csv "$pbiDir/dim_gaps.csv" -NoTypeInformation
    # AB#6882, clause B-04. ScanDate is carried onto every fact row so the semantic model has a
    # real date column to relate its date dimension to. Without it the date table is decoration:
    # it exists, nothing joins to it, and no time intelligence works.
    $scanDate = $null
    if ($null -ne $Findings) {
        $genProp = $Findings.PSObject.Properties['GeneratedOn']
        if ($genProp -and $genProp.Value) {
            try { $scanDate = ([datetime]$genProp.Value).ToString('yyyy-MM-dd') } catch { $scanDate = $null }
        }
    }
    if (-not $scanDate) { $scanDate = (Get-Date).ToString('yyyy-MM-dd') }

    (Get-ScoutPowerBiProp $Findings 'Findings') |
        Select-Object @{n = 'AreaKey'; e = { New-AreaKey $_.Framework $_.Area } }, Id, Framework, Area, Severity, Status, EvidenceCount, Title, Remediation, Manual, @{n = 'ScanDate'; e = { $scanDate } } |
        ConvertTo-SafeCsvRow |
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

    # AB#6882, clauses B-01..B-05. The PBIP project is the deliverable; the .pbit above is kept
    # only as a fallback for a reader on a Power BI Desktop old enough to lack PBIP support.
    # Failure here is non-fatal for the same reason the .pbit's is -- a run must not lose its
    # other five formats because one of them could not be written.
    $pbipPath = $null
    try {
        if (-not (Get-Command -Name Export-ScoutPowerBiProject -ErrorAction SilentlyContinue)) {
            . "$PSScriptRoot/Export-PowerBiProject.ps1"
        }
        $pbipPath = Export-ScoutPowerBiProject -PowerBiDir $pbiDir
    }
    catch {
        Write-Warning ("Power BI project (PBIP) generation failed: {0}. The star-schema CSVs are still available." -f $_.Exception.Message)
    }

    $pbipLine = if ($pbipPath) {
        "PRIMARY OUTPUT: open AzureScout.pbip in Power BI Desktop. It carries the semantic model (TMDL) and three authored report pages -- executive summary, findings by area, prioritised gaps."
    }
    else {
        'The PBIP project could not be generated for this run; see the warning in the run log.'
    }

    $pbitLine = if ($pbitMade) {
        "Open report.pbit in Power BI Desktop and click Refresh when prompted (the model was built from a snapshot)."
    } else {
        "No report.pbit was generated; import the CSVs below manually in Power BI Desktop."
    }
    @"
$pbipLine

FALLBACK: $pbitLine

If the CSV folder has moved, re-point the DataFolder parameter (PBIP) or FolderPath (.pbit) to:
  $pbiDir
The model is a star schema: fact_findings + dim_gaps joined to fact_area_scores on AreaKey and to
fact_framework on Framework, with a calculated Date dimension joined on ScanDate.
"@ | Out-File "$pbiDir/README.txt"
}
