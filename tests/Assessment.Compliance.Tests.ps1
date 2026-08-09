#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6792 / AB#6793 / AB#6794 (Feature AB#6744, Epic AB#6454) — score the compliance state
    Azure Scout already collects.

    No Azure connection. Everything here is a rendering test over fixture collect objects.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-ScoutComplianceScore.ps1"
    . "$script:Root/src/assess/engine/Resolve-ScoutAssignedInitiative.ps1"
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/assess/Invoke-ScoutComplianceAssessment.ps1"

    # One MCSB-shaped fixture: an assigned, versioned, BuiltIn initiative with a mix of
    # Compliant / NonCompliant / never-evaluated controls, plus a second initiative
    # (CIS-shaped) so two-initiatives-in-one-run and two-versions-of-one-framework are both
    # exercised, plus a definition for an initiative that produced ZERO compliance rows —
    # the "deliberately unassigned initiative" AB#6793 requires a test for.
    function New-ScoutComplianceFixture {
        $mcsbId  = '/providers/Microsoft.Authorization/policySetDefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8'
        $cisV1Id = '/providers/Microsoft.Authorization/policySetDefinitions/cis-v1-0000'
        $cisV2Id = '/providers/Microsoft.Authorization/policySetDefinitions/cis-v2-0000'
        $unassignedId = '/providers/Microsoft.Authorization/policySetDefinitions/unassigned-0000'

        $states = @(
            # MCSB control A — every row Compliant -> Pass
            [pscustomobject]@{ PolicySetDefinitionId = $mcsbId; PolicyDefinitionId = 'policy-a'; PolicyDefinitionName = 'Storage accounts should restrict network access'; ComplianceState = 'Compliant'; ResourceId = '/sub/1/rg/a/res/1' }
            [pscustomobject]@{ PolicySetDefinitionId = $mcsbId; PolicyDefinitionId = 'policy-a'; PolicyDefinitionName = 'Storage accounts should restrict network access'; ComplianceState = 'Compliant'; ResourceId = '/sub/1/rg/a/res/2' }
            # MCSB control B — a mixed result; NonCompliant must win -> Fail
            [pscustomobject]@{ PolicySetDefinitionId = $mcsbId; PolicyDefinitionId = 'policy-b'; PolicyDefinitionName = 'Key vaults should have soft delete enabled'; ComplianceState = 'Compliant'; ResourceId = '/sub/1/rg/a/res/3' }
            [pscustomobject]@{ PolicySetDefinitionId = $mcsbId; PolicyDefinitionId = 'policy-b'; PolicyDefinitionName = 'Key vaults should have soft delete enabled'; ComplianceState = 'NonCompliant'; ResourceId = '/sub/1/rg/a/res/4' }
            # MCSB control C — every row Exempt, never Compliant or NonCompliant -> NotAssessed
            [pscustomobject]@{ PolicySetDefinitionId = $mcsbId; PolicyDefinitionId = 'policy-c'; PolicyDefinitionName = 'VMs should use managed disks'; ComplianceState = 'Exempt'; ResourceId = '/sub/1/rg/a/res/5' }

            # CIS v3.0.0 — one control, Compliant
            [pscustomobject]@{ PolicySetDefinitionId = $cisV1Id; PolicyDefinitionId = 'cis-policy-1'; PolicyDefinitionName = 'CIS control one'; ComplianceState = 'Compliant'; ResourceId = '/sub/1/rg/b/res/1' }
            # CIS v2.0.0 (a DIFFERENT, older initiative id) — one control, NonCompliant
            [pscustomobject]@{ PolicySetDefinitionId = $cisV2Id; PolicyDefinitionId = 'cis-policy-1'; PolicyDefinitionName = 'CIS control one'; ComplianceState = 'NonCompliant'; ResourceId = '/sub/1/rg/b/res/2' }
        )

        $initiatives = @(
            [pscustomobject]@{ Id = $mcsbId; DisplayName = 'Microsoft cloud security benchmark'; PolicyType = 'BuiltIn'; Version = '1.0.0'; PolicyCount = 223 }
            [pscustomobject]@{ Id = $cisV1Id; DisplayName = 'CIS Azure Foundations'; PolicyType = 'BuiltIn'; Version = 'v3.0.0'; PolicyCount = 53 }
            [pscustomobject]@{ Id = $cisV2Id; DisplayName = 'CIS Microsoft Azure Foundations Benchmark'; PolicyType = 'BuiltIn'; Version = 'v2.0.0'; PolicyCount = 108 }
            # Defined (Scout can see it exists) but ZERO compliance rows reference it anywhere
            # above -- the deliberately-unassigned initiative.
            [pscustomobject]@{ Id = $unassignedId; DisplayName = 'ISO/IEC 27001 2022'; PolicyType = 'BuiltIn'; Version = '2022'; PolicyCount = 58 }
            # A custom initiative sharing a compliance row's id space is never offered even if
            # somehow it had rows -- proven separately below.
        )

        [pscustomobject]@{
            domains = [pscustomobject]@{
                management = [pscustomobject]@{
                    policyComplianceStates = $states
                    policyInitiatives      = $initiatives
                }
            }
        }
    }
}

Describe 'AB#6793 — three states, so unassessed never reads as passed' {

    BeforeAll {
        $script:Collect = New-ScoutComplianceFixture
        $script:Mcsb = @($script:Collect.domains.management.policyInitiatives | Where-Object DisplayName -eq 'Microsoft cloud security benchmark')[0]
        $script:Scored = Get-ScoutComplianceScore -Collect $script:Collect -Initiative $script:Mcsb
    }

    It 'scores an all-Compliant control as Pass' {
        (@($script:Scored.Findings | Where-Object Id -eq 'policy-a'))[0].Status | Should -Be 'Pass'
    }

    It 'scores a mixed Compliant/NonCompliant control as Fail, never Pass' {
        (@($script:Scored.Findings | Where-Object Id -eq 'policy-b'))[0].Status | Should -Be 'Fail'
    }

    It 'scores a control with no Compliant/NonCompliant row as NotAssessed, never Pass or Fail' {
        $finding = @($script:Scored.Findings | Where-Object Id -eq 'policy-c')[0]
        $finding.Status | Should -Be 'NotAssessed'
        $finding.Status | Should -Not -Be 'Pass'
        $finding.Status | Should -Not -Be 'Fail'
    }

    It 'excludes NotAssessed from the compliance percentage denominator' {
        # 1 Pass (policy-a) + 1 Fail (policy-b) scorable; policy-c (NotAssessed) must not enter
        # the denominator, so the percentage is exactly 50, not 33 (which is what counting all
        # three controls would produce).
        $script:Scored.CompliancePercent | Should -Be 50
        $script:Scored.Pass | Should -Be 1
        $script:Scored.Fail | Should -Be 1
        $script:Scored.NotAssessed | Should -Be 1
    }

    It 'a deliberately unassigned initiative (definition known, zero compliance rows) is never offered as scored' {
        $unassigned = @($script:Collect.domains.management.policyInitiatives | Where-Object DisplayName -eq 'ISO/IEC 27001 2022')[0]
        $assigned = @(Resolve-ScoutAssignedInitiative -Collect $script:Collect)

        $assigned.DisplayName | Should -Not -Contain $unassigned.DisplayName
    }

    It 'end to end: Get-Score never counts NotAssessed toward a Pass/Fail-based area score' {
        $findings = @(Invoke-ScoutComplianceAssessment -Collect $script:Collect)
        $result   = Get-Score -Findings $findings

        $area = @($result.Areas | Where-Object Framework -eq 'Microsoft cloud security benchmark 1.0.0')[0]
        $area.Score | Should -Be 50          # (1 pass) / (1 pass + 1 fail) * 100, policy-c excluded
        $area.NotAssessed | Should -Be 1
        @($result.NotAssessed).Count | Should -BeGreaterThan 0
    }

    It 'renders the three states as three distinguishable CSS classes in the HTML template' {
        $tpl = Get-Content -Raw "$script:Root/src/report/templates/report.html.template"
        $tpl | Should -Match '\.pass\{'
        $tpl | Should -Match '\.fail\{'
        $tpl | Should -Match '\.notassessed\{'
        # And the "all findings" tab classes findings by their (lower-cased) Status, which is how
        # 'NotAssessed' reaches the .notassessed CSS rule above without a separate template branch.
        $tpl | Should -Match 'f\.Status\.toLowerCase\(\)'
    }

    It 'gives Pass/Fail/NotAssessed three different Excel ConditionalText colours' {
        $src = Get-Content -Raw "$script:Root/src/report/renderers/Export-Excel.ps1"
        $src | Should -Match "New-ConditionalText -Text 'Pass'.*BackgroundColor LightGreen"
        $src | Should -Match "New-ConditionalText -Text 'Fail'.*BackgroundColor LightPink"
        $src | Should -Match "New-ConditionalText -Text 'NotAssessed'.*BackgroundColor LightBlue"
    }
}

Describe 'AB#6792 — score MCSB (and any other initiative) from collected policy state' {

    BeforeAll {
        $script:Collect = New-ScoutComplianceFixture
    }

    It 'names the exact initiative version scored, not a bare framework name' {
        $mcsb = @($script:Collect.domains.management.policyInitiatives | Where-Object DisplayName -eq 'Microsoft cloud security benchmark')[0]
        $scored = Get-ScoutComplianceScore -Collect $script:Collect -Initiative $mcsb

        $scored.Framework | Should -Be 'Microsoft cloud security benchmark 1.0.0'
        $scored.Version   | Should -Be '1.0.0'
    }

    It 'identifies the policy that produced each per-control result' {
        $mcsb = @($script:Collect.domains.management.policyInitiatives | Where-Object DisplayName -eq 'Microsoft cloud security benchmark')[0]
        $scored = Get-ScoutComplianceScore -Collect $script:Collect -Initiative $mcsb
        $failFinding = @($scored.Findings | Where-Object Status -eq 'Fail')[0]

        $failFinding.PolicyDefinitionId | Should -Be 'policy-b'
        $failFinding.Title | Should -Be 'Key vaults should have soft delete enabled'
    }

    It 'issues zero Azure calls itself — it only reads $Collect' {
        $mcsb = @($script:Collect.domains.management.policyInitiatives | Where-Object DisplayName -eq 'Microsoft cloud security benchmark')[0]
        function Search-AzGraph { throw 'Get-ScoutComplianceScore must never call Azure directly' }
        function Get-AzPolicyState { throw 'Get-ScoutComplianceScore must never call Azure directly' }

        { Get-ScoutComplianceScore -Collect $script:Collect -Initiative $mcsb } | Should -Not -Throw
    }
}

Describe 'AB#6794 — every assigned regulatory initiative is its own assessment' {

    BeforeAll {
        $script:Collect = New-ScoutComplianceFixture
        $script:Assigned = @(Resolve-ScoutAssignedInitiative -Collect $script:Collect)
    }

    It 'offers every BuiltIn initiative that actually produced compliance rows' {
        $script:Assigned.DisplayName | Should -Contain 'Microsoft cloud security benchmark'
        $script:Assigned.DisplayName | Should -Contain 'CIS Azure Foundations'
        $script:Assigned.DisplayName | Should -Contain 'CIS Microsoft Azure Foundations Benchmark'
    }

    It 'does not offer an initiative with zero compliance rows' {
        $script:Assigned.DisplayName | Should -Not -Contain 'ISO/IEC 27001 2022'
    }

    It 'two versions of the same framework produce two distinct assessments, never merged' {
        $cisEntries = @($script:Assigned | Where-Object { $_.DisplayName -match 'CIS' })

        $cisEntries.Count | Should -Be 2
        ($cisEntries | Select-Object -ExpandProperty Id -Unique).Count | Should -Be 2
        ($cisEntries | Select-Object -ExpandProperty Version -Unique).Count | Should -Be 2
    }

    It 'end to end: each assigned initiative becomes its own Framework score card' {
        $findings = @(Invoke-ScoutComplianceAssessment -Collect $script:Collect)
        $result   = Get-Score -Findings $findings

        $frameworkNames = @($result.Frameworks | Select-Object -ExpandProperty Framework)
        $frameworkNames | Should -Contain 'Microsoft cloud security benchmark 1.0.0'
        $frameworkNames | Should -Contain 'CIS Azure Foundations v3.0.0'
        $frameworkNames | Should -Contain 'CIS Microsoft Azure Foundations Benchmark v2.0.0'
    }

    It 'excludes a custom (non-BuiltIn) policy set even if it has compliance rows' {
        $collect = New-ScoutComplianceFixture
        $customId = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/my-custom-initiative'
        $collect.domains.management.policyComplianceStates += [pscustomobject]@{
            PolicySetDefinitionId = $customId; PolicyDefinitionId = 'custom-1'; PolicyDefinitionName = 'Custom control'; ComplianceState = 'Compliant'
        }
        $collect.domains.management.policyInitiatives += [pscustomobject]@{
            Id = $customId; DisplayName = 'My Custom Initiative'; PolicyType = 'Custom'; Version = 'N/A'; PolicyCount = 1
        }

        $assigned = @(Resolve-ScoutAssignedInitiative -Collect $collect)

        $assigned.DisplayName | Should -Not -Contain 'My Custom Initiative'
    }

    It 'a real MCSB run reports no findings, not a crash, when nothing is assigned at all' {
        $empty = [pscustomobject]@{ domains = [pscustomobject]@{ management = [pscustomobject]@{ policyComplianceStates = @(); policyInitiatives = @() } } }

        { $null = @(Invoke-ScoutComplianceAssessment -Collect $empty -WarningAction SilentlyContinue) } | Should -Not -Throw
        @(Invoke-ScoutComplianceAssessment -Collect $empty -WarningAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe 'AB#6795 — the assessment registry is clean' {

    BeforeAll {
        $script:Manifest = Import-PowerShellDataFile (Join-Path -Path $script:Root -ChildPath 'manifests/assessments.psd1')
    }

    It 'has no Estate entry — a full-estate inventory pull is not an assessment' {
        $script:Manifest.Keys | Should -Not -Contain 'Estate'
    }

    It 'has no Policy entry — it was byte-identical to Governance' {
        $script:Manifest.Keys | Should -Not -Contain 'Policy'
    }

    It 'still has the Governance baseline, the entry Policy duplicated' {
        $script:Manifest.Keys | Should -Contain 'Scout: Governance Baseline'
    }

    It 'names Update Manager and Monitoring as subsets in their own description' {
        $script:Manifest['Scout: Update Manager'].Description | Should -Match '(?i)subset'
        $script:Manifest['Scout: Monitoring Baseline'].Description | Should -Match '(?i)subset'
    }

    It 'offers Assess: Compliance, routed through the compliance engine, not the YAML rule engine' {
        $script:Manifest.Keys | Should -Contain 'Assess: Compliance'
        $script:Manifest['Assess: Compliance'].Compliance | Should -BeTrue
    }

    It 'Assess: Compliance passes the AB#6763 menu-honesty gate (a rule file backs its glob)' {
        . "$script:Root/src/assess/Get-ScoutAvailableAssessment.ps1"
        $available = @(Get-ScoutAvailableAssessment -Manifest $script:Manifest -RuleDirectory "$script:Root/src/assess/rules")

        $available | Should -Contain 'Assess: Compliance'
    }
}

Describe 'AB#6795 — the wizard asks for inventory and assessment separately' {

    It 'offers Inventory, Assessment, and Both as distinct run-type choices, not a combined checkbox' {
        $source = Get-Content -Raw "$script:Root/src/Start-AZSCWizard.ps1"

        $source | Should -Match "Value = 'Inventory'"
        $source | Should -Match "Value = 'Assessment'"
        $source | Should -Match "Value = 'Both'"
    }
}

Describe 'AB#6792 — an initiative Scout cannot confirm is Not assessed, never silence' {
    # Found by a live run against tenant tppoc: policy compliance state and policy set definitions
    # are two SEPARATE Azure calls, so the definitions sweep can return nothing while the
    # compliance sweep returns hundreds of rows. The assessment used to emit ZERO findings in that
    # case -- an empty report reading as "nothing to report" against 469 real compliance rows.

    BeforeAll {
        . "$script:Root/src/assess/engine/Get-ScoutComplianceScore.ps1"
        . "$script:Root/src/assess/engine/Resolve-ScoutAssignedInitiative.ps1"
        . "$script:Root/src/assess/Invoke-ScoutComplianceAssessment.ps1"

        $script:McsbId = '/providers/Microsoft.Authorization/policySetDefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8'
        function New-ComplianceCollect([object[]] $Definitions) {
            [pscustomobject]@{
                domains = [pscustomobject]@{
                    management = [pscustomobject]@{
                        policyComplianceStates = @(
                            [pscustomobject]@{ PolicySetDefinitionId = $script:McsbId; PolicyDefinitionId = 'p1'; ComplianceState = 'Compliant'; ResourceId = 'r1' }
                            [pscustomobject]@{ PolicySetDefinitionId = $script:McsbId; PolicyDefinitionId = 'p2'; ComplianceState = 'NonCompliant'; ResourceId = 'r2' }
                        )
                        policyInitiatives    = @($Definitions)
                        policySetDefinitions = @($Definitions)
                    }
                }
            }
        }
    }

    It 'emits a NotAssessed finding naming the initiative when no definition confirms it built-in' {
        $findings = @(Invoke-ScoutComplianceAssessment -Collect (New-ComplianceCollect @()) -WarningAction SilentlyContinue)

        $findings.Count | Should -BeGreaterThan 0 -Because 'silence against real compliance rows is the false-negative this fix removes'
        $notAssessed = @($findings | Where-Object Status -eq 'NotAssessed')
        $notAssessed.Count | Should -Be 1
        $notAssessed[0].Title | Should -BeLike "*$($script:McsbId)*" -Because 'the operator has to know WHICH initiative went unevaluated'
    }

    It 'never scores an unconfirmable initiative as a pass or a fail' {
        $findings = @(Invoke-ScoutComplianceAssessment -Collect (New-ComplianceCollect @()) -WarningAction SilentlyContinue)

        @($findings | Where-Object Status -in 'Pass', 'Fail').Count | Should -Be 0 -Because 'a custom initiative rendered under a framework name would be actively misleading'
    }

    It 'scores normally, naming the exact version, once a built-in definition is present' {
        $def = [pscustomobject]@{
            Id = $script:McsbId; Name = 'mcsb'; DisplayName = 'Microsoft cloud security benchmark'
            Version = '57.58.0'; PolicyType = 'BuiltIn'; PolicyCount = 226
        }
        $findings = @(Invoke-ScoutComplianceAssessment -Collect (New-ComplianceCollect @($def)))

        @($findings | Where-Object Status -eq 'NotAssessed').Count | Should -Be 0
        @($findings | Where-Object Status -in 'Pass', 'Fail').Count | Should -BeGreaterThan 0
        $findings[0].Framework | Should -Be 'Microsoft cloud security benchmark 57.58.0'
    }
}
