#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Score one Azure Policy regulatory-compliance initiative from already-collected
    policy compliance state — a rendering job, not rule authoring (AB#6792/AB#6793).

.DESCRIPTION
    Azure Policy evaluates every control in an assigned initiative continuously. This
    function does not assert anything itself; it reads the compliance state Scout has
    already collected (domains.management.policyComplianceStates) and rolls it up to
    one result per policy ("control") in the named initiative.

    Three states, deliberately (AB#6793) — never two:

      Pass        — every compliance-state row seen for this control is 'Compliant'.
      Fail        — at least one compliance-state row for this control is
                    'NonCompliant'. NonCompliant wins over Compliant, because "some
                    resources fail this control" is the honest read of a mixed result,
                    not a pass.
      NotAssessed — Azure returned NO compliance-state row for this control at all
                    (e.g. it is a member of the initiative but nothing has been
                    evaluated against it yet, or every row for it was Exempt). This is
                    the state AB#6793 exists to protect: it is never counted as a pass
                    or a fail, by ANY caller, because it carries neither status string.

    A control is identified by (PolicySetDefinitionId, PolicyDefinitionId) so the same
    policy definition reused by two initiatives is scored independently in each.

.PARAMETER Collect
    The assessment collect object. Reads
    $Collect.domains.management.policyComplianceStates (rows) and, when supplied,
    $Initiative.PolicyCount to report coverage.

.PARAMETER Initiative
    One descriptor from Resolve-ScoutAssignedInitiative -- must carry Id (the
    PolicySetDefinitionId), DisplayName, and Version.

.OUTPUTS
    [pscustomobject] with:
      InitiativeId, DisplayName, Version, Framework (the exact "name + version" string
      every finding below is tagged with, so two versions of the same initiative never
      merge into one score card — AB#6794)
      Findings   — one row per control: Id, Title, Status ('Pass'|'Fail'|'NotAssessed'),
                   EvidenceCount, Evidence (the compliance-state rows themselves, capped),
                   PolicyDefinitionId (AB#6792 — "identify the policy that produced it")
      CompliancePercent — Compliant / (Compliant + Fail) * 100, rounded, matching how
                   Defender for Cloud's compliance blade reads a policy-level pass/fail
                   split. $null when there is nothing scorable or Scout observed fewer
                   distinct controls than Initiative.PolicyCount.
      NotAssessedCount

.NOTES
    Tracks AB#6792 / AB#6793 (Feature AB#6744, Epic AB#6454).
#>
function Get-ScoutComplianceScore {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Collect,
        [Parameter(Mandatory)] $Initiative
    )

    $initiativeId = [string]$Initiative.Id
    $displayName  = [string]$Initiative.DisplayName
    $version      = [string]$Initiative.Version
    $frameworkName = if ([string]::IsNullOrWhiteSpace($version) -or $version -eq 'N/A') {
        "$displayName (version unknown)"
    } else {
        "$displayName $version"
    }

    # StrictMode-safe descent: $Collect.domains.management.policyComplianceStates throws
    # PropertyNotFoundException the moment any hop is absent (a fixture built without the full
    # shape, or a real collect.json from before this feature existed), rather than returning
    # $null. Walk it defensively.
    $allStates = @()
    if ($null -ne $Collect -and $Collect.PSObject.Properties['domains'] -and $null -ne $Collect.domains -and
        $Collect.domains.PSObject.Properties['management'] -and $null -ne $Collect.domains.management -and
        $Collect.domains.management.PSObject.Properties['policyComplianceStates'] -and $null -ne $Collect.domains.management.policyComplianceStates) {
        $allStates = @($Collect.domains.management.policyComplianceStates)
    }

    # Rows belonging to THIS initiative only. A policy-definition id is not unique across
    # initiatives (the same built-in policy is a member of several), so PolicySetDefinitionId is
    # the join key, not PolicyDefinitionId alone.
    $initiativeStates = @($allStates | Where-Object {
        $_ -and $_.PSObject.Properties['PolicySetDefinitionId'] -and
        [string]$_.PolicySetDefinitionId -eq $initiativeId
    })

    $byControl = $initiativeStates | Group-Object PolicyDefinitionId

    $findings = @(
        foreach ($group in $byControl) {
            $rows = @($group.Group)
            $title = ($rows | Where-Object { $_.PSObject.Properties['PolicyDefinitionName'] -and $_.PolicyDefinitionName } |
                Select-Object -First 1 -ExpandProperty PolicyDefinitionName)
            if (-not $title) { $title = $group.Name }

            $states = @($rows | ForEach-Object {
                if ($_.PSObject.Properties['ComplianceState']) { [string]$_.ComplianceState } else { $null }
            })
            # NonCompliant wins over Compliant on a mixed result (AB#6792) -- "some resources
            # fail this control" is not a pass. Rows that are only Exempt/blank/unknown never
            # produce Pass or Fail; that is what routes them to NotAssessed below, which is the
            # exact AB#6793 guard: a control this function never SAW a Compliant/NonCompliant row
            # for must not silently read as passed.
            $status =
                if ($states -contains 'NonCompliant') { 'Fail' }
                elseif ($states -contains 'Compliant') { 'Pass' }
                else { 'NotAssessed' }

            [pscustomobject]@{
                Id                = $group.Name
                PolicyDefinitionId = $group.Name
                Title             = $title
                Status            = $status
                EvidenceCount     = $rows.Count
                Evidence          = @($rows | Select-Object -First 25)
                Remediation       = if ($status -eq 'Fail') { "Remediate the non-compliant resource(s) flagged by policy '$title' (Azure Policy assignment already in place; no new policy needed)." }
                                     elseif ($status -eq 'NotAssessed') { "No compliance evaluation has been recorded yet for policy '$title' in this initiative -- trigger an on-demand policy scan or wait for the next evaluation cycle." }
                                     else { $null }
            }
        }
    )

    # A control this initiative's definition names but that never produced a single compliance
    # row (assigned but not yet evaluated at all, distinct from "evaluated and Exempt") is still
    # NotAssessed, never silently dropped -- but Scout only knows a control's NAME once Azure has
    # returned at least one row for it (policyComplianceStates carries no membership list on its
    # own), so an initiative with zero rows entirely produces zero findings here. That case is
    # handled one layer up, in Resolve-ScoutAssignedInitiative / Invoke-ScoutComplianceAssessment,
    # by not offering the initiative as assigned at all (AB#6793's "not assigned -> no card, not a
    # fabricated pass" rule).

    $passCount = @($findings | Where-Object Status -eq 'Pass').Count
    $failCount = @($findings | Where-Object Status -eq 'Fail').Count
    $observedControlCount = @($findings).Count
    $expectedControlCount = $null
    if ($Initiative.PSObject.Properties['PolicyCount'] -and $null -ne $Initiative.PolicyCount) {
        $parsedPolicyCount = 0
        if ([int]::TryParse([string]$Initiative.PolicyCount, [ref]$parsedPolicyCount) -and $parsedPolicyCount -gt 0) {
            $expectedControlCount = $parsedPolicyCount
        }
    }
    $unobservedControlCount = if ($null -ne $expectedControlCount -and $expectedControlCount -gt $observedControlCount) {
        $expectedControlCount - $observedControlCount
    } else { 0 }
    $coverageComplete = ($null -eq $expectedControlCount -or $observedControlCount -ge $expectedControlCount)
    $notAssessedCount = @($findings | Where-Object Status -eq 'NotAssessed').Count + $unobservedControlCount
    $scorableCount = $passCount + $failCount

    [pscustomobject]@{
        InitiativeId      = $initiativeId
        DisplayName       = $displayName
        Version           = $version
        Framework         = $frameworkName
        Findings          = $findings
        Pass              = $passCount
        Fail              = $failCount
        NotAssessed       = $notAssessedCount
        ObservedControlCount   = $observedControlCount
        ExpectedControlCount   = $expectedControlCount
        UnobservedControlCount = $unobservedControlCount
        CoverageComplete       = $coverageComplete
        CoveragePercent        = if ($null -ne $expectedControlCount) {
            [math]::Round([math]::Min($observedControlCount, $expectedControlCount) / $expectedControlCount * 100, 1)
        } else { $null }
        CompliancePercent = if ($coverageComplete -and $scorableCount -gt 0) { [math]::Round($passCount / $scorableCount * 100, 0, [System.MidpointRounding]::AwayFromZero) } else { $null }
    }
}
