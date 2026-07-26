#Requires -Version 7.0

<#
.SYNOPSIS
    Fails the build if any declarative collector definition is malformed or has drifted from the
    collector it was lifted from (AB#5661).

.DESCRIPTION
    A `.psd1` collector definition is DATA that is executed. Nothing about it is checked by the
    compiler, and almost nothing about it is checked by the report: a definition that names a
    column no field produces, or whose lifted preamble no longer matches the collector it came
    from, does not crash -- it writes a worksheet with a blank column, or with no rows at all.
    Every defect of that shape in this epic reached a shipped release, and every one was found by
    a human opening the workbook.

    The equivalence suite (tests/DeclarativeCollectorEquivalence.Tests.ps1) proves a definition
    agrees with its collector, but it is expensive: it executes both paths for all of them and
    writes real .xlsx files. This is the cheap structural gate that runs first and names the file.

    SEVEN CHECKS, each of which corresponds to a defect that actually shipped:

      1. PARSES        -- `Import-PowerShellDataFile` accepts it and it satisfies the schema in
                          `Get-ScoutCollectorDefinition` (non-empty ResourceTypes, unique non-empty
                          Field names and Expressions, an Export block, a recognised
                          ResourceTypeMatching, a TagColumnsBefore that names a real column, a
                          FilterPreamble that has a filter to feed, a SetupPreamble and
                          SetupVariables that imply each other).
      2. ROW SCRIPT    -- the per-resource script the interpreter BUILDS from the definition parses.
                          This is the one that matters most and is not implied by (1): a field whose
                          source text is an `if (...) {...} else {...}` STATEMENT is legal inside a
                          hashtable literal but not inside `( ... )`, and when the interpreter
                          wrapped expressions the entire generated script failed to parse -- every
                          field of ten collectors silently unreachable, with no error anywhere.
      3. PREAMBLES     -- SetupPreamble, FilterPreamble and every loop Preamble parse on their own.
      4. COLUMNS       -- every Export.Columns and Export.TagColumns entry is a declared Field name.
                          A mismatch is a permanently blank column, because `Select-Object` does not
                          require the property to exist. FIVE such columns are pre-existing shipped
                          bugs and are allow-listed below by name; a SIXTH fails the build, and an
                          allow-list entry that has been FIXED also fails the build so the list can
                          only get shorter.
      5. SETUP VARS    -- every declared SetupVariable is assigned somewhere in the SetupPreamble.
                          Checked statically here rather than only at run time, where a name that
                          the preamble stopped assigning throws inside a collector.
      6. SOURCE        -- SourceCollector names a file that exists.
      7. DRIFT         -- regenerating the definition from that collector with
                          ConvertTo-ScoutCollectorDefinition.ps1 reproduces the file byte for byte.
                          The definitions are GENERATED artefacts and say so in their own header;
                          when the collector changes and the definition does not, the two paths
                          diverge silently. `Compute/AvailabilitySets.psd1` had been in exactly that
                          state since the StrictMode hardening -- its equivalence test passed,
                          because with StrictMode off the stale expression and the new one happen to
                          agree on the fixture, so nothing else in the repo could have caught it.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent of this script's directory.

.PARAMETER DefinitionRoot
    Directory to scan. Defaults to <RepoRoot>/manifests/collectors. Pointed at a throwaway tree by
    tests/CollectorDefinitionSchema.Tests.ps1 to prove the checks actually fire.

.PARAMETER SkipDriftCheck
    Skip check 7. Only for a throwaway tree, whose definitions have no SourceCollector in this repo.

.PARAMETER SkipAllowListStaleCheck
    Skip the "an allow-listed blank column is no longer blank" half of check 4, for the same reason.

.OUTPUTS
    A GitHub Actions ::error:: annotation per violation, and exit 1; or exit 0 when clean.

.NOTES
    Tracks ADO AB#5661 (Feature AB#5656, Epic AB#5638). tests/CollectorDefinitionSchema.Tests.ps1
    calls this same script so the gate fires locally as well as in CI.

.EXAMPLE
    pwsh -File scripts/Test-ScoutCollectorDefinition.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [string]$DefinitionRoot,

    [Parameter()]
    [switch]$SkipDriftCheck,

    [Parameter()]
    [switch]$SkipAllowListStaleCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
. (Join-Path $RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')

if (-not $DefinitionRoot) { $DefinitionRoot = Join-Path $RepoRoot 'manifests/collectors' }

# --- The blank-column allow-list ---------------------------------------------------------------
#
# An Export column whose name matches no Field is exported by `Select-Object` as a property that
# does not exist, which is blank rather than an error. These five have been blank in every shipped
# release. They are NOT fixed here: the equivalence proof compares the declarative path against the
# imperative one, so "fixing" the definition would make the two disagree and the test would report
# the fix as a conversion defect. They are surfaced as warnings by the loader and pinned here.
$script:KnownBlankColumns = @(
    @{ Category = 'Analytics';   Name = 'EvtHub';       Column = 'Geo-Rep'
       Reason   = "the Reporting branch exports 'Geo-Rep' but Processing produces no such field." }
    @{ Category = 'Databases';   Name = 'RedisCache';   Column = 'Resource Group'
       Reason   = "Processing emits the field as 'ResourceGroup' (no space); Reporting exports 'Resource Group'." }
    @{ Category = 'Databases';   Name = 'SQLMI';        Column = 'ActiveDirectoryOnlyAuthentication'
       Reason   = "Processing emits the field as 'AzureADOnlyAuthentication'; Reporting exports the newer name." }
    @{ Category = 'Integration'; Name = 'ServiceBUS';   Column = 'Geo-Rep'
       Reason   = "the Reporting branch exports 'Geo-Rep' but Processing produces no such field." }
    @{ Category = 'Networking';  Name = 'vNETPeering';  Column = 'Peering Allow Virtual NetworkAccess'
       Reason   = "Processing emits 'Peering Allow Virtual Network Access' (spaced); Reporting exports it unspaced." }
)

function Test-AllowedBlankColumn {
    param([string]$Category, [string]$Name, [string]$Column)
    foreach ($Entry in $script:KnownBlankColumns) {
        if ($Entry.Category -eq $Category -and $Entry.Name -eq $Name -and $Entry.Column -eq $Column) { return $true }
    }
    return $false
}

function Test-DefinitionParses {
    <# Parse a fragment of lifted source and return its first error message, or $null. #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $Errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$Errors)
    if (@($Errors).Count -gt 0) { return $Errors[0].Message }
    return $null
}

$Violations = [System.Collections.Generic.List[object]]::new()
function Add-Violation {
    param([string]$Path, [string]$Message)
    $Violations.Add([PSCustomObject]@{ Path = $Path; Message = $Message })
}

if (-not (Test-Path -LiteralPath $DefinitionRoot)) {
    Write-Host "::error::Collector definition root '$DefinitionRoot' does not exist."
    exit 1
}

$Files = @(Get-ChildItem -LiteralPath $DefinitionRoot -Filter '*.psd1' -Recurse -File | Sort-Object FullName)
$SeenBlank = [System.Collections.Generic.HashSet[string]]::new()
$Checked   = 0

foreach ($File in $Files) {
    $Checked++
    $Category = Split-Path -Leaf (Split-Path -Parent $File.FullName)
    $Name     = $File.BaseName
    # Repo-relative and forward-slashed so the ::error:: annotation lands on the file in the PR diff.
    # Guarded on the prefix actually matching: with -DefinitionRoot pointed at a sandbox the two
    # paths are unrelated, and blindly trimming RepoRoot's LENGTH chopped the sandbox path
    # mid-GUID and produced an annotation naming a file that does not exist.
    $Relative = if ($File.FullName.StartsWith($RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        ($File.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')) -replace '\\', '/'
    } else {
        $File.FullName -replace '\\', '/'
    }

    # --- 1. PARSES ---------------------------------------------------------------------------
    $Definition = $null
    try {
        $Definition = Get-ScoutCollectorDefinition -Path $File.FullName
    } catch {
        Add-Violation -Path $Relative -Message "does not satisfy the collector definition schema: $($_.Exception.Message -replace "`r?`n", ' ')"
        continue
    }

    # --- 2. ROW SCRIPT -----------------------------------------------------------------------
    try {
        $RowScript = Build-ScoutDeclarativeRowScript -Definition $Definition
        $RowError  = Test-DefinitionParses -Text $RowScript
        if ($RowError) {
            Add-Violation -Path $Relative -Message "the per-resource script the interpreter builds from this definition does not parse, so every field of this collector would be unreachable at run time: $RowError"
        }
    } catch {
        Add-Violation -Path $Relative -Message "the per-resource script could not be built from this definition: $($_.Exception.Message -replace "`r?`n", ' ')"
    }

    # --- 3. PREAMBLES ------------------------------------------------------------------------
    foreach ($Fragment in @(
            @{ Label = 'SetupPreamble';  Text = $Definition.SetupPreamble }
            @{ Label = 'FilterPreamble'; Text = $Definition.FilterPreamble }
            @{ Label = 'Preamble';       Text = $Definition.Preamble })) {
        $FragmentError = Test-DefinitionParses -Text $Fragment.Text
        if ($FragmentError) { Add-Violation -Path $Relative -Message "$($Fragment.Label) does not parse: $FragmentError" }
    }
    foreach ($Loop in @($Definition.AdditionalRowLoops)) {
        $LoopError = Test-DefinitionParses -Text $Loop.Preamble
        if ($LoopError) { Add-Violation -Path $Relative -Message "the Preamble of AdditionalRowLoops entry '$($Loop.Variable)' does not parse: $LoopError" }
    }

    # --- 4. COLUMNS --------------------------------------------------------------------------
    $FieldNames = @(@($Definition.Fields) | ForEach-Object { $_.Name })
    foreach ($Column in @(@($Definition.Export.Columns) + @($Definition.Export.TagColumns))) {
        if ($FieldNames -contains $Column) { continue }
        if (Test-AllowedBlankColumn -Category $Category -Name $Name -Column $Column) {
            [void]$SeenBlank.Add("$Category/$Name/$Column")
            continue
        }
        Add-Violation -Path $Relative -Message "Export references the column '$Column', which no Field produces. Select-Object does not require the property to exist, so this would ship as a permanently BLANK column rather than as an error. Rename the Field or the column; if it is a pre-existing bug being carried deliberately, add it to the allow-list in scripts/Test-ScoutCollectorDefinition.ps1 WITH a reason."
    }

    # --- 5. SETUP VARS -----------------------------------------------------------------------
    if (@($Definition.SetupVariables).Count -gt 0) {
        $SetupAst = [System.Management.Automation.Language.Parser]::ParseInput($Definition.SetupPreamble, [ref]$null, [ref]$null)
        $Assigned = @($SetupAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                      $n.Left -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true) | ForEach-Object { $_.Left.VariablePath.UserPath })

        foreach ($Variable in @($Definition.SetupVariables)) {
            if ($Assigned -notcontains $Variable) {
                Add-Violation -Path $Relative -Message "SetupVariables declares '$Variable' but the SetupPreamble never assigns it. At run time the interpreter throws; the point of checking it here is that the failure names the file instead of a collector."
            }
        }
    }

    # --- 6. SOURCE ---------------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($Definition.SourceCollector)) {
        Add-Violation -Path $Relative -Message 'SourceCollector is empty, so nothing records which collector this definition was lifted from and the drift check below cannot run.'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Definition.SourceCollector))) {
        Add-Violation -Path $Relative -Message "SourceCollector names '$($Definition.SourceCollector)', which does not exist."
    } elseif (-not $SkipDriftCheck) {
        # --- 7. DRIFT ------------------------------------------------------------------------
        $Regenerated = Join-Path ([System.IO.Path]::GetTempPath()) ("azsc-defdrift-" + [guid]::NewGuid().ToString('N') + '.psd1')
        try {
            $null = & (Join-Path $RepoRoot 'scripts/ConvertTo-ScoutCollectorDefinition.ps1') `
                -CollectorPath (Join-Path $RepoRoot $Definition.SourceCollector) -OutputPath $Regenerated 6>$null

            # Line endings normalised: git may check the tree out with either, and a CRLF/LF
            # difference is not drift.
            $OnDisk = (Get-Content -LiteralPath $File.FullName  -Raw) -replace "`r`n", "`n"
            $Fresh  = (Get-Content -LiteralPath $Regenerated     -Raw) -replace "`r`n", "`n"
            if ($OnDisk -ne $Fresh) {
                Add-Violation -Path $Relative -Message "has DRIFTED from $($Definition.SourceCollector): regenerating it with scripts/ConvertTo-ScoutCollectorDefinition.ps1 produces a different file. The collector was edited and the definition was not, so the declarative and imperative paths no longer run the same source. Regenerate the definition -- do not hand-patch it."
            }
        } catch {
            Add-Violation -Path $Relative -Message "could not be regenerated from $($Definition.SourceCollector) for the drift check: $($_.Exception.Message -replace "`r?`n", ' ')"
        } finally {
            if (Test-Path -LiteralPath $Regenerated) { Remove-Item -LiteralPath $Regenerated -Force -ErrorAction SilentlyContinue }
        }
    }
}

# The other half of check 4: an allow-listed blank column that is no longer blank. Without this the
# list rots into a description of bugs that were fixed two releases ago, and the next person reads
# it as five live defects.
$Stale = @()
if (-not $SkipAllowListStaleCheck) {
    $Stale = @($script:KnownBlankColumns | Where-Object { -not $SeenBlank.Contains("$($_.Category)/$($_.Name)/$($_.Column)") })
}

Write-Host "[AzureScout] Collector definition validation (AB#5661): checked $Checked definition(s) under $DefinitionRoot; $($script:KnownBlankColumns.Count) allow-listed blank column(s), $($SeenBlank.Count) still present."

foreach ($Violation in $Violations) {
    Write-Host "::error file=$($Violation.Path)::$($Violation.Message)"
}
foreach ($Entry in $Stale) {
    Write-Host "::error::scripts/Test-ScoutCollectorDefinition.ps1 allow-lists a blank '$($Entry.Column)' column on $($Entry.Category)/$($Entry.Name), but that column now resolves to a Field. Delete the entry -- the list is only allowed to get shorter (AB#5661)."
}

if (@($Violations).Count -gt 0 -or @($Stale).Count -gt 0) {
    Write-Host "::error::Collector definition validation failed: $(@($Violations).Count) violation(s), $(@($Stale).Count) stale allow-list entr(ies)."
    exit 1
}

Write-Host '[AzureScout] Collector definition validation: OK.'
exit 0
