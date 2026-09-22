#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Run every rule in every rule set against the collect object.

.NOTES
    Appends benchmark findings when a benchmark is supplied. Tracks ADO Story AB#5035.
#>
function Invoke-Assessment {
    param($Collect, $RuleSet, $Benchmark, [string] $Assessment)

    function Write-ScoutRuleTiming {
        param(
            [Parameter(Mandatory)] [string] $RuleId,
            [Parameter(Mandatory)] [string] $Status,
            [Parameter(Mandatory)] [int] $EvidenceCount,
            [Parameter(Mandatory)] [System.Diagnostics.Stopwatch] $Timer
        )
        if ($Timer.IsRunning) { $Timer.Stop() }
        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level 'DEBUG' -Message (
                'Assessment rule {0}: status={1}; evidence={2}; elapsed={3}' -f
                    $RuleId, $Status, $EvidenceCount, $Timer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
            )
        }
    }

    $findings = foreach ($set in $RuleSet) {
        # A rule file may declare a data prerequisite (`requires:`). When it does and NOT ONE of
        # the declared paths returned a row, the whole set is reported Unknown with the missing
        # datasets named -- never scored (AB#6832). Scoring it would turn "nothing was collected"
        # into "everything passed", which for a migration-readiness assessment on an estate with no
        # Azure Migrate project is the most misleading answer available.
        #
        # One satisfied path is enough: a tenant part-way through a migration legitimately has
        # projects but no Data Box, and that partial state is a finding, not a blocker.
        $Required = @(if ($set.PSObject.Properties['Requires']) { @($set.Requires) } else { @() })

        # Both of these are OPTIONAL rule-set metadata: a rule file need not declare `weight:` or
        # `frameworkVersion:`, and several do not. Reading an absent property throws under
        # Set-StrictMode -Version Latest, and because these are read on the Add-Member chain that
        # decorates EVERY finding, one rule set missing one key took down the entire assessment
        # rather than degrading that one field to $null. Resolve them once, defensively, here.
        $SetWeight = if ($set.PSObject.Properties['Weight']) { $set.Weight } else { $null }
        $SetFrameworkVersion = if ($set.PSObject.Properties['FrameworkVersion']) { $set.FrameworkVersion } else { $null }
        $Missing = @()
        if ($Required.Count -gt 0) {
            $Satisfied = $false
            foreach ($Requirement in $Required) {
                $Path = if ($Requirement -is [System.Collections.IDictionary]) { [string]$Requirement['path'] } else { [string]$Requirement.path }
                $Description = if ($Requirement -is [System.Collections.IDictionary]) { [string]$Requirement['description'] } else { [string]$Requirement.description }
                # NOT wrapped in @(): Resolve-JsonPath returns its array through
                # `Write-Output -NoEnumerate`, so @() would produce a one-element array holding the
                # (possibly empty) result and every prerequisite would read as satisfied.
                $Rows = $null
                try { $Rows = Resolve-JsonPath -InputObject $Collect -Path $Path } catch { $Rows = $null }
                $RowCount = if ($null -eq $Rows) { 0 } else { $Rows.Count }
                if ($RowCount -gt 0) { $Satisfied = $true } else { $Missing += $(if ($Description) { $Description } else { $Path }) }
            }
            if (-not $Satisfied) {
                foreach ($rule in $set.Rules) {
                    $ruleTimer = [System.Diagnostics.Stopwatch]::StartNew()
                    $f = [pscustomobject]@{
                        Id            = $rule.id
                        Title         = $rule.title
                        Framework     = $set.Framework
                        Area          = $set.Area
                        Severity      = $rule.severity
                        Status        = 'Unknown'
                        EvidenceCount = 0
                        Evidence      = @()
                        Remediation   = "Not assessed: none of this rule set's required datasets returned any rows ($($Missing -join '; ')). Collect them before reading a score from this area."
                        Manual        = [bool]$rule.manual
                    } | Add-Member -NotePropertyName Assessment -NotePropertyValue $Assessment -PassThru |
                        Add-Member -NotePropertyName AreaWeight -NotePropertyValue $SetWeight -PassThru |
                        Add-Member -NotePropertyName FrameworkVersion -NotePropertyValue $SetFrameworkVersion -PassThru
                    Write-ScoutRuleTiming -RuleId ([string]$rule.id) -Status 'Unknown' -EvidenceCount 0 -Timer $ruleTimer
                    $f
                }
                continue
            }
        }

        foreach ($rule in $set.Rules) {
            $ruleTimer = [System.Diagnostics.Stopwatch]::StartNew()
            $f = Invoke-Rule -Rule $rule -Collect $Collect -Area $set.Area -Framework $set.Framework
            $f = $f | Add-Member -NotePropertyName Assessment -NotePropertyValue $Assessment -PassThru |
                 Add-Member -NotePropertyName AreaWeight -NotePropertyValue $SetWeight -PassThru |
                 Add-Member -NotePropertyName FrameworkVersion -NotePropertyValue $SetFrameworkVersion -PassThru
            $evidenceCount = if ($f.PSObject.Properties['EvidenceCount']) { [int]$f.EvidenceCount } else { 0 }
            Write-ScoutRuleTiming -RuleId ([string]$rule.id) -Status ([string]$f.Status) -EvidenceCount $evidenceCount -Timer $ruleTimer
            $f
        }
    }
    # AB#6929 follow-up -- Compare-Benchmark builds its findings as bare pscustomobjects (no
    # Assessment/AreaWeight/FrameworkVersion), unlike every rule-set finding above, which each get
    # the Add-Member chain inside the ruleset loop. Appending them unstamped left every benchmark
    # finding (LandingZone's ALZ management-group/policy checks) with NO Assessment property at
    # all -- Export-React's per-assessment grouping fell back to a literal "(unassigned)" bucket,
    # which rendered as a nameless 0%-scoring assessment card next to the real ones. These findings
    # unambiguously belong to the assessment whose Benchmark declared them (only LandingZone's
    # manifest entry names one today), so stamp the SAME $Assessment this whole function was
    # called for -- not a fabricated bucket. AreaWeight/FrameworkVersion are deliberately left
    # unset (not even added as $null): Get-Score's `$null -ne $_.PSObject.Properties['AreaWeight']`
    # check treats an ABSENT property as "use the 1.0 default", which is correct here, whereas
    # adding the property with a $null value would cast to 0.0 and zero out the area's weight.
    if ($Benchmark) {
        $benchmarkFindings = Compare-Benchmark -Collect $Collect -Benchmark $Benchmark
        $findings += $benchmarkFindings | ForEach-Object {
            $_ | Add-Member -NotePropertyName Assessment -NotePropertyValue $Assessment -PassThru
        }
    }
    return $findings
}
