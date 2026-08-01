#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Run the 'Assess: Compliance' registry entry — score every regulatory-compliance
    initiative assigned in the scanned scope from already-collected policy state.

.DESCRIPTION
    The compliance counterpart to Invoke-Assessment (which drives the YAML rule
    engine). This function does not read a rule file: it discovers every BuiltIn
    initiative actually assigned (Resolve-ScoutAssignedInitiative, AB#6794), scores
    each one from collected compliance state (Get-ScoutComplianceScore, AB#6792), and
    returns Findings shaped so the existing Get-Score aggregator — and therefore every
    existing reporter (Html, Excel, ...) — needs no changes to render them: one
    Framework card per initiative+version, three states, never a fabricated pass
    (AB#6793).

.PARAMETER Collect
    The assessment collect object.

.PARAMETER Assessment
    The manifest key this run was invoked under (for Add-Member tagging, matching
    Invoke-Assessment's contract).

.OUTPUTS
    [pscustomobject[]] findings, in the same shape Invoke-Rule/Invoke-Assessment
    produce (Id, Title, Framework, Area, Severity, Status, EvidenceCount, Evidence,
    Remediation, Manual, Assessment, AreaWeight) so Get-Score can aggregate them
    identically to a YAML-rule-scored assessment.

.NOTES
    Tracks AB#6792/#6793/#6794 (Feature AB#6744, Epic AB#6454).
#>
function Invoke-ScoutComplianceAssessment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Collect,
        [string] $Assessment = 'Assess: Compliance'
    )

    $initiatives = @(Resolve-ScoutAssignedInitiative -Collect $Collect)

    if ($initiatives.Count -eq 0) {
        # Nothing observably assigned: honest empty result, not a fabricated pass or a crash.
        # Invoke-ScoutAssessmentCore's RequiresData gate (same mechanism as SMART, AB#6832)
        # should normally keep this from being reached with zero rows at all, but a tenant that
        # HAS compliance rows for zero BuiltIn initiatives (e.g. only custom policy) reaches here
        # legitimately, and must produce zero findings, not throw.
        Write-Warning "Invoke-ScoutComplianceAssessment: no BuiltIn regulatory-compliance initiative is observably assigned in the scanned scope (policyComplianceStates has rows, but none match a known BuiltIn policySetDefinition) — nothing to score."
        return @()
    }

    $findings = foreach ($initiative in $initiatives) {
        $scored = Get-ScoutComplianceScore -Collect $Collect -Initiative $initiative
        foreach ($f in $scored.Findings) {
            [pscustomobject]@{
                Id            = $f.Id
                Title         = $f.Title
                Framework     = $scored.Framework
                Area          = 'Regulatory compliance'
                Severity      = $null
                Status        = $f.Status
                EvidenceCount = $f.EvidenceCount
                Evidence      = $f.Evidence
                Remediation   = $f.Remediation
                Manual        = $false
            } | Add-Member -NotePropertyName Assessment -NotePropertyValue $Assessment -PassThru |
                Add-Member -NotePropertyName AreaWeight -NotePropertyValue 1.0 -PassThru |
                Add-Member -NotePropertyName InitiativeId -NotePropertyValue $scored.InitiativeId -PassThru |
                Add-Member -NotePropertyName InitiativeVersion -NotePropertyValue $scored.Version -PassThru
        }
    }

    return @($findings)
}
