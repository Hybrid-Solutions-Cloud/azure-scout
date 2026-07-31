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
                    [pscustomobject]@{
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
                        Add-Member -NotePropertyName AreaWeight -NotePropertyValue $set.Weight -PassThru
                }
                continue
            }
        }

        foreach ($rule in $set.Rules) {
            $f = Invoke-Rule -Rule $rule -Collect $Collect -Area $set.Area -Framework $set.Framework
            $f | Add-Member -NotePropertyName Assessment -NotePropertyValue $Assessment -PassThru |
                 Add-Member -NotePropertyName AreaWeight -NotePropertyValue $set.Weight -PassThru
        }
    }
    if ($Benchmark) { $findings += Compare-Benchmark -Collect $Collect -Benchmark $Benchmark }
    return $findings
}
