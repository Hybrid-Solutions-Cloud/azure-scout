#Requires -Version 7.0
#Requires -Modules Pester

<#
    The narrative engine (Task AB#6854, User Story AB#6443, Feature AB#6449, Epic AB#6450).

    A per-rule template produces "1 of 3 scorable controls are satisfied" — true, mechanical,
    unread. The reference report writes "The four-point gap is driven by operational governance
    and security hygiene, not by architecture." The difference is not vocabulary: every
    interesting sentence there is COMPARATIVE or AGGREGATE, and no such fact exists on any
    single rule.

    So these tests are in two halves:

      * the facts are derived correctly (rankings, spread, concentration, what is driving the
        score down versus what is clean);
      * a sentence whose supporting fact is absent is NOT emitted — not hedged, not
        placeholdered, not emitted.

    Plus grammar, which is not cosmetic here: "1 domain(s) are excluded" tells the reader a
    machine wrote it, and they discount the analysis accordingly.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Get-GovernanceDomainScore.ps1"
    . "$root/src/report/Build-ScoutNarrative.ps1"
    . "$root/src/report/Build-ScoutReportModel.ps1"

    function New-Finding {
        param(
            [string] $Id, [string] $Area, [string] $Status, [string] $Severity = 'high',
            [int] $EvidenceCount = 0, $Evidence = @(), [string] $Title = 'A control'
        )
        [pscustomobject]@{
            Id = $Id; Title = $Title; Framework = 'Cloud Governance'; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = $EvidenceCount; Evidence = $Evidence
            EvidenceTruncated = $false; EvidenceCap = 25
            Remediation = "Remediate $Id."; Manual = $false
            TargetState = 'Closed'; Owner = 'Platform'; Effort = 'M'; Phase = 1
        }
    }

    function New-Area {
        param([string] $Area, $Score, [int] $Pass = 2, [int] $Partial = 0, [int] $Fail = 1,
            [int] $Manual = 0, [int] $Unknown = 0, [int] $ErrorCount = 0)
        [pscustomobject]@{
            Framework = 'Cloud Governance'; Area = $Area; Score = $Score; Weight = 1.0
            Pass = $Pass; Partial = $Partial; Fail = $Fail; Manual = $Manual
            Unknown = $Unknown; Error = $ErrorCount
        }
    }

    function New-TestModel {
        param($Areas, $Findings, [int] $SubCount = 4)
        $collect = [pscustomobject]@{
            subscriptions = @(1..$SubCount | ForEach-Object {
                    [pscustomobject]@{ id = "sub-$_"; name = "sub-$_"; state = 'Enabled' }
                })
            _meta = [pscustomobject]@{ scope = 'All'; managementGroupId = 'mg-root'; tenantId = 't' }
        }
        $scored = [pscustomobject]@{
            GeneratedOn = '2026-08-01T10:00:00.0000000Z'
            Frameworks = @(); Areas = @($Areas); Gaps = @(); Manual = @(); Errors = @()
            Findings = @($Findings)
        }
        Build-ScoutReportModel -Findings $scored -Collect $collect
    }

    function New-Evidence {
        param([string] $Sub, [string] $Name)
        [pscustomobject]@{
            id = "/subscriptions/$Sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/$Name"
            name = $Name
        }
    }
}

Describe 'Fact derivation' {
    BeforeAll {
        $Script:Model = New-TestModel -Areas @(
            (New-Area -Area 'Security' -Score 40)
            (New-Area -Area 'Operations' -Score 90)
            (New-Area -Area 'Data' -Score $null)
        ) -Findings @(
            New-Finding -Id 'S1' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 60 -Evidence @((New-Evidence 'sub-1' 'a'))
            New-Finding -Id 'S2' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 30 -Evidence @((New-Evidence 'sub-2' 'b'))
            New-Finding -Id 'O1' -Area 'Operations' -Status 'Fail' -Severity 'low' -EvidenceCount 2 -Evidence @((New-Evidence 'sub-1' 'c'))
        )
        $Script:Facts = Get-ScoutNarrativeFact -Model $Script:Model
    }

    It 'ranks the strongest and weakest assessed domains' {
        $Script:Facts.StrongestDomain.Domain | Should -Be 'Operations'
        $Script:Facts.WeakestDomain.Domain | Should -Be 'Security'
        $Script:Facts.ScoreSpread | Should -Be 5
    }

    It 'excludes not-assessed domains from the ranking' {
        $Script:Facts.AssessedDomainCount | Should -Be 2
        $Script:Facts.NotAssessedDomainCount | Should -Be 1
    }

    It 'identifies which domains are driving the severe findings' {
        $Script:Facts.DrivingDomains | Should -Contain 'Security'
        $Script:Facts.DrivingDomains | Should -Not -Contain 'Operations'
    }

    It 'identifies the domains carrying no severe findings — the other half of the contrast' {
        $Script:Facts.CleanDomains | Should -Contain 'Operations'
    }

    It 'computes concentration across the largest findings' {
        # 92 affected in total; the three largest are all of them.
        $Script:Facts.TotalAffectedResources | Should -Be 92
        $Script:Facts.ConcentrationPercent | Should -Be 100
    }

    It 'counts the distinct subscriptions the affected resources actually touch' {
        $Script:Facts.AffectedSubscriptions | Should -Be 2
        $Script:Facts.InScopeSubscriptions | Should -Be 4
    }

    It 'names the single largest blast radius' {
        $Script:Facts.LargestGap.EvidenceCount | Should -Be 60
    }
}

Describe 'Executive narrative composition' {
    BeforeAll {
        $Script:Model = New-TestModel -Areas @(
            (New-Area -Area 'Security' -Score 40)
            (New-Area -Area 'Operations' -Score 90)
            (New-Area -Area 'Data' -Score $null)
        ) -Findings @(
            New-Finding -Id 'S1' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 60 `
                -Evidence @((New-Evidence 'sub-1' 'a')) -Title 'Storage public network access'
            New-Finding -Id 'O1' -Area 'Operations' -Status 'Fail' -Severity 'low' -EvidenceCount 2 -Evidence @((New-Evidence 'sub-2' 'c'))
        )
        $Script:Paras = New-ScoutExecutiveNarrative -Model $Script:Model
        $Script:Text = ($Script:Paras | ForEach-Object { "$($_.Lead). $($_.Text)" }) -join "`n"
    }

    It 'emits three named paragraphs' {
        @($Script:Paras).Count | Should -Be 3
        @($Script:Paras | ForEach-Object { $_.Lead }) | Should -Contain 'Reading the score'
    }

    It 'ranks the strongest domain against its peers rather than stating it in isolation' {
        $Script:Text | Should -BeLike '*Operations is the strongest of the 2 domains*'
    }

    It 'contrasts what is driving the score down against what is not' {
        $Script:Text | Should -BeLike '*driven by Security, not by Operations*'
    }

    It 'names the largest blast radius with its count' {
        $Script:Text | Should -BeLike "*'Storage public network access', affecting 60 resources*"
    }

    It 'publishes the rubric alongside the composite so the number can be read' {
        $Script:Text | Should -BeLike '*1-2 Initial, 3-4 Emerging, 5-6 Defined, 7-8 Managed, 9-10 Optimised*'
    }

    It 'states the composite exclusion in the same breath the composite is quoted' {
        # Never in a footnote. A composite computed over a subset that does not say so is read
        # as covering everything.
        $reading = $Script:Paras | Where-Object Lead -eq 'Reading the score'
        $reading.Text | Should -BeLike '*excluded from this figure entirely*'
        $reading.Text | Should -BeLike '*not scored as zero*'
    }
}

Describe 'A sentence with no supporting fact is not emitted' {
    It 'emits one honest paragraph when nothing was assessed at all' {
        $model = New-TestModel -Areas @((New-Area -Area 'Security' -Score $null)) -Findings @()
        $paras = New-ScoutExecutiveNarrative -Model $model
        @($paras).Count | Should -Be 1
        $paras[0].Lead | Should -Be 'No assessable result'
        $paras[0].Text | Should -BeLike '*No maturity position, ranking or remediation priority can be stated*'
    }

    It 'omits the driving-factors paragraph entirely when there are no gaps' {
        $model = New-TestModel -Areas @(
            (New-Area -Area 'Security' -Score 100 -Pass 3 -Fail 0)
            (New-Area -Area 'Operations' -Score 100 -Pass 3 -Fail 0)
        ) -Findings @(New-Finding -Id 'S1' -Area 'Security' -Status 'Pass' -EvidenceCount 5)
        $paras = New-ScoutExecutiveNarrative -Model $model
        @($paras | ForEach-Object { $_.Lead }) | Should -Not -Contain 'What is driving the score down'
    }

    It 'never emits a placeholder or a hedge in place of a missing fact' {
        $model = New-TestModel -Areas @((New-Area -Area 'Security' -Score 50)) -Findings @(
            New-Finding -Id 'S1' -Area 'Security' -Status 'Fail' -EvidenceCount 3
        )
        $text = ((New-ScoutExecutiveNarrative -Model $model) | ForEach-Object { $_.Text }) -join ' '
        $text | Should -Not -Match '\{\d\}'
        $text | Should -Not -Match '(?i)\b(TBD|N/A|unknown number|some number)\b'
    }
}

Describe 'Domain narrative' {
    BeforeAll {
        $Script:Model = New-TestModel -Areas @(
            (New-Area -Area 'Security' -Score 40 -Pass 1 -Fail 2)
            (New-Area -Area 'Operations' -Score 90 -Pass 3 -Fail 0)
            (New-Area -Area 'Data' -Score $null)
        ) -Findings @(
            New-Finding -Id 'S1' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 60 `
                -Evidence @((New-Evidence 'sub-1' 'a')) -Title 'Storage public network access'
            New-Finding -Id 'S2' -Area 'Security' -Status 'Fail' -Severity 'medium' -EvidenceCount 4 `
                -Evidence @((New-Evidence 'sub-1' 'b')) -Title 'TLS 1.2 minimum'
        )
        $Script:Domains = @(Get-ScoutModelProp (Get-ScoutModelProp $Script:Model 'Maturity') 'Domains')
    }

    It 'places the domain against its peers, not in isolation' {
        $sec = $Script:Domains | Where-Object Domain -eq 'Security'
        $sec.CurrentState | Should -BeLike '*the lowest of the 2 assessed domains*'
    }

    It 'translates rule counts into affected resources' {
        $sec = $Script:Domains | Where-Object Domain -eq 'Security'
        $sec.CurrentState | Should -BeLike '*touch 64 resources in scope*'
    }

    It 'says so plainly when a domain has no open gaps at all' {
        $ops = $Script:Domains | Where-Object Domain -eq 'Operations'
        $ops.CurrentState | Should -BeLike '*There are no open gaps in this domain*'
    }

    It 'characterises a domain whose gaps are all low severity as refinement, not remediation' {
        $model = New-TestModel -Areas @(
            (New-Area -Area 'Security' -Score 40 -Pass 1 -Fail 2)
            (New-Area -Area 'Operations' -Score 80 -Pass 3 -Fail 1)
        ) -Findings @(
            New-Finding -Id 'S1' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 60 -Evidence @((New-Evidence 'sub-1' 'a'))
            New-Finding -Id 'O1' -Area 'Operations' -Status 'Fail' -Severity 'low' -EvidenceCount 2 -Evidence @((New-Evidence 'sub-2' 'c'))
        )
        $ops = @(Get-ScoutModelProp (Get-ScoutModelProp $model 'Maturity') 'Domains') | Where-Object Domain -eq 'Operations'
        $ops.CurrentState | Should -BeLike '*refinement rather than a remediation priority*'
    }

    It 'refuses to describe a current state for a domain with no evidence' {
        $data = $Script:Domains | Where-Object Domain -eq 'Data'
        $data.CurrentState | Should -BeLike '*no current state can be described and no score can be claimed*'
        $data.CurrentState | Should -BeLike '*not a pass and not a failure*'
    }

    It 'states controls excluded from the score rather than dropping them silently' {
        $model = New-TestModel -Areas @((New-Area -Area 'Security' -Score 50 -Pass 1 -Fail 1 -Manual 2 -Unknown 1)) -Findings @()
        $d = @(Get-ScoutModelProp (Get-ScoutModelProp $model 'Maturity') 'Domains')[0]
        $d.CurrentState | Should -BeLike '*could not be scored automatically*'
        $d.CurrentState | Should -BeLike '*2 need manual confirmation*'
        $d.CurrentState | Should -BeLike '*1 returned no usable data*'
    }
}

Describe 'Grammar' {
    It 'never emits a parenthesised plural anywhere in the narrative' {
        # "1 domain(s) are excluded" tells the reader a machine wrote it, and they discount
        # the analysis with it. Cheap to avoid, so it is not avoided by exception.
        $model = New-TestModel -Areas @(
            (New-Area -Area 'Security' -Score 40 -Pass 1 -Fail 1 -Manual 1)
            (New-Area -Area 'Operations' -Score 90)
            (New-Area -Area 'Data' -Score $null)
        ) -Findings @(
            New-Finding -Id 'S1' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 1 -Evidence @((New-Evidence 'sub-1' 'a'))
        )
        $all = (((New-ScoutExecutiveNarrative -Model $model) | ForEach-Object { $_.Text }) -join ' ') +
        ((@(Get-ScoutModelProp (Get-ScoutModelProp $model 'Maturity') 'Domains') | ForEach-Object { $_.CurrentState }) -join ' ')
        $all | Should -Not -Match '\(s\)'
    }

    It 'agrees subject and verb on a single-item count' {
        $model = New-TestModel -Areas @(
            (New-Area -Area 'Security' -Score 40 -Pass 1 -Fail 1)
            (New-Area -Area 'Operations' -Score 90)
        ) -Findings @(
            New-Finding -Id 'S1' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 1 -Evidence @((New-Evidence 'sub-1' 'a'))
        )
        $sec = @(Get-ScoutModelProp (Get-ScoutModelProp $model 'Maturity') 'Domains') | Where-Object Domain -eq 'Security'
        $sec.CurrentState | Should -BeLike '*That finding touches 1 resource in scope*'
        $sec.CurrentState | Should -Not -BeLike '*1 are*'
    }

    It 'formats an English list without a trailing comma' {
        Join-ScoutList @('a') | Should -Be 'a'
        Join-ScoutList @('a', 'b') | Should -Be 'a and b'
        Join-ScoutList @('a', 'b', 'c') | Should -Be 'a, b and c'
        Join-ScoutList @() | Should -Be ''
    }

    It 'pluralises a count without parentheses' {
        Format-ScoutCount 1 'resource' | Should -Be '1 resource'
        Format-ScoutCount 60 'resource' | Should -Be '60 resources'
        Format-ScoutCount 2 'gap carries' 'gaps carry' | Should -Be '2 gaps carry'
    }
}

Describe 'Narrative never sinks the run' {
    It 'attaches nothing and warns rather than throwing when composition fails' {
        $broken = [pscustomobject]@{ Maturity = 'not-an-object' }
        { Add-ScoutNarrativeToModel -Model $broken 3>$null } | Should -Not -Throw
    }
}
