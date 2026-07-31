#Requires -Version 7.0
#Requires -Modules ImportExcel
<#
.SYNOPSIS
    Record the canonical golden output for declarative collectors (AB#6741).

.DESCRIPTION
    `tests/DeclarativeCollectorGolden.Tests.ps1` compares every collector's processed rows and
    rendered worksheet against a committed record under `tests/fixtures/collector-golden/`. Until
    now those records existed but nothing in the repo could produce one, so a new collector could
    not be added without hand-authoring a file whose format is defined only by the reader.

    This is the writer. It runs the SAME interpreter, on the SAME fixture, through the SAME
    comparison helpers the test uses (`scripts/CollectorGolden.Common.ps1`), so a record it writes
    and the test's live computation cannot disagree about formatting.

    WHEN TO RUN IT. Only two situations:

      1. A NEW collector definition has no record yet.
      2. The category FIXTURE changed -- the record stores the fixture's SHA-256 and the reader
         rejects a record captured against a different estate, so every collector in that category
         must be re-recorded together.

    It is NOT a way to make a failing test pass. A record regenerated to accommodate an unexplained
    row change silently blesses a behaviour change; that is the failure mode the golden suite
    exists to prevent. Use -WhatIfDiff to see what WOULD change before writing anything.

.PARAMETER Category
    Categories to record. Default is every category with a definition folder.

.PARAMETER Name
    Restrict to these collector names within the selected categories.

.PARAMETER WhatIfDiff
    Compute the records and report which existing ones would change, without writing.

.NOTES
    Tracks ADO AB#6741.
#>
[CmdletBinding()]
param(
    [string[]]$Category,
    [string[]]$Name,
    [switch]$WhatIfDiff
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot        = Split-Path -Parent $PSScriptRoot
$DefinitionRoot  = Join-Path $RepoRoot 'manifests' 'collectors'
$GoldenRoot      = Join-Path $RepoRoot 'tests' 'fixtures' 'collector-golden'

. (Join-Path $RepoRoot 'scripts' 'CollectorGolden.Common.ps1')
. (Join-Path $RepoRoot 'src' 'pipeline' 'Get-ScoutCollectorDefinition.ps1')
. (Join-Path $RepoRoot 'src' 'pipeline' 'Invoke-ScoutDeclarativeCollector.ps1')
. (Join-Path $RepoRoot 'src' 'Get-AZSCSafeProperty.ps1')
. (Join-Path $RepoRoot 'src' 'Get-AZTICollectedValue.ps1')
. (Join-Path $RepoRoot 'src' 'Get-AZSCIdSegment.ps1')

function Get-FixturePathFor {
    param([string]$CategoryName)
    # Databases predates the per-category convention and keeps its original fixture name; the
    # golden test resolves it the same way, so both sides agree.
    if ($CategoryName -eq 'Databases') { return Join-Path $RepoRoot 'tests/fixtures/databases-collector-input.json' }
    return Join-Path $RepoRoot "tests/fixtures/collector-equivalence/$CategoryName.json"
}

# The fixed instant every golden record is captured at. Changing it re-dates every time-relative
# column in every record, so it is a deliberate, reviewed edit -- not something to nudge.
$script:GoldenRunTime = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("scout-golden-record-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -Path $TempDir -ItemType Directory -Force

$FixtureCache = @{}
function Get-Fixture {
    param([string]$CategoryName)
    $Path = Get-FixturePathFor -CategoryName $CategoryName
    if (-not $FixtureCache.ContainsKey($Path)) {
        $FixtureCache[$Path] = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    return $FixtureCache[$Path]
}

function New-Context {
    param([string]$CategoryName, [string]$CollectorName, [string]$Task, $File, $SmaResources, [bool]$InTag)

    $Fixture = Get-Fixture -CategoryName $CategoryName
    $Resources = if ($CategoryName -eq 'Databases') {
        $Fixture.resources
    } else {
        $Entry = $Fixture.collectors.PSObject.Properties[$CollectorName]
        if ($null -eq $Entry) { throw "Fixture for category '$CategoryName' has no collector entry named '$CollectorName'. Regenerate it with scripts/New-ScoutCollectorFixture.ps1." }
        $Entry.Value.resources
    }

    @{
        ScriptRoot    = $RepoRoot
        Subscriptions = $Fixture.subscriptions
        InTag         = $InTag
        Resources     = $Resources
        Retirements   = $Fixture.retirements
        Task          = $Task
        File          = $File
        SmaResources  = $SmaResources
        TableStyle    = 'Light20'
        Unsupported   = $Fixture.unsupported
        # Pinned so a record captured today and the same record verified next month agree. Without
        # it Management/Backup's "Days Since Last Backup" moves by one every calendar day and the
        # golden suite fails on any day but the one it was recorded on. Must match the value
        # tests/DeclarativeCollectorGolden.Tests.ps1 uses.
        RunTime       = $script:GoldenRunTime
    }
}

$Folders = @(Get-ChildItem -LiteralPath $DefinitionRoot -Directory | Sort-Object Name)
if ($Category -and @($Category).Count -gt 0) {
    $Folders = @($Folders | Where-Object { $Category -contains $_.Name })
}

$Changed = [System.Collections.Generic.List[string]]::new()
$Created = [System.Collections.Generic.List[string]]::new()
$Same    = 0

foreach ($Folder in $Folders) {
    $Files = @(Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.psd1' -File | Sort-Object BaseName)
    if ($Name -and @($Name).Count -gt 0) {
        $Files = @($Files | Where-Object { $Name -contains $_.BaseName })
    }

    foreach ($File in $Files) {
        $CategoryName  = $Folder.Name
        $CollectorName = $File.BaseName
        $Definition    = Get-ScoutCollectorDefinition -Path $File.FullName

        $Rows = @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (
            New-Context -CategoryName $CategoryName -CollectorName $CollectorName -Task 'Processing' -File $null -SmaResources $null -InTag $false))

        $Workbook = @{}
        foreach ($TagState in @('WithoutTags', 'WithTags')) {
            $InTag = ($TagState -eq 'WithTags')
            $Xlsx  = Join-Path $TempDir "$CategoryName-$CollectorName-$TagState.xlsx"
            Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (
                New-Context -CategoryName $CategoryName -CollectorName $CollectorName -Task 'Reporting' -File $Xlsx -SmaResources $Rows -InTag $InTag)
            $Workbook[$TagState] = @(ConvertTo-ScoutWorksheetText -Path $Xlsx -Worksheet $Definition.Export.WorksheetName)
        }

        $FixturePath = Get-FixturePathFor -CategoryName $CategoryName
        $Record = [ordered]@{
            SchemaVersion = 1
            Category      = $CategoryName
            Name          = $CollectorName
            FixturePath   = ((Resolve-Path -LiteralPath $FixturePath).Path.Substring($RepoRoot.Length + 1) -replace '\\', '/')
            FixtureSha256 = Get-ScoutFixtureSha256 -Path $FixturePath
            Rows          = @(@($Rows) | ForEach-Object { ConvertTo-ScoutComparableRow -Row $_ })
            Workbook      = [ordered]@{
                WithoutTags = @($Workbook['WithoutTags'])
                WithTags    = @($Workbook['WithTags'])
            }
        }

        $Json   = ($Record | ConvertTo-Json -Depth 8)
        $Target = Join-Path $GoldenRoot $CategoryName "$CollectorName.json"
        $TargetDir = Split-Path -Parent $Target
        if (-not (Test-Path -LiteralPath $TargetDir)) { $null = New-Item -Path $TargetDir -ItemType Directory -Force }

        if (Test-Path -LiteralPath $Target) {
            $Existing = Get-Content -LiteralPath $Target -Raw
            # Compare the MEANINGFUL content, not the file bytes: the stored fixture hash changes
            # whenever the estate is regenerated, and reporting that as a behaviour change on every
            # collector in a category would bury the one collector that really did move.
            $ExistingObj = $Existing | ConvertFrom-Json
            $RowsSame     = (($ExistingObj.Rows -join "`n") -eq (@($Record.Rows) -join "`n"))
            $SheetsSame   = (((@($ExistingObj.Workbook.WithoutTags) + @($ExistingObj.Workbook.WithTags)) -join "`n") -eq
                             ((@($Record.Workbook.WithoutTags) + @($Record.Workbook.WithTags)) -join "`n"))
            if ($RowsSame -and $SheetsSame) { $Same++ } else { $Changed.Add("$CategoryName/$CollectorName") }
        } else {
            $Created.Add("$CategoryName/$CollectorName")
        }

        if (-not $WhatIfDiff) {
            Set-Content -LiteralPath $Target -Value $Json -Encoding utf8NoBOM
        }
    }
}

Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Golden records: $($Created.Count) new, $($Changed.Count) changed, $Same unchanged$(if ($WhatIfDiff) { ' (dry run -- nothing written)' })"
if ($Created.Count -gt 0) { Write-Host "  new:     $($Created -join ', ')" }
if ($Changed.Count -gt 0) {
    Write-Warning "Row or worksheet content CHANGED for: $($Changed -join ', ')"
    Write-Warning "Each of these is a behaviour change. Confirm it is intended before committing the regenerated record."
}
