#Requires -Version 7.0
#Requires -Modules Pester

<#
    Power BI star schema v2 — resource-grain fact plus its dimensions (Task AB#6860,
    User Story AB#6443, Feature AB#6449, Epic AB#6450).

    The v1 export carried four tables joined on AreaKey and never exported evidence, so the
    one question a consumer actually wants to ask of it — which subscriptions carry the most
    open findings, and what should each owner do first — could not be asked.

    The test that matters most is the last one: fact_evidence is at RESOURCE grain, so its row
    count is NOT the affected total whenever evidence was truncated. A consumer who counts
    rows and calls it a total gets a number that is quietly too small, which is the same
    partial-list-presented-as-complete failure AB#6864 fixed one layer down.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Get-GovernanceDomainScore.ps1"
    . "$root/src/report/Build-ScoutReportModel.ps1"
    . "$root/src/report/renderers/Export-PowerBi.ps1"

    function New-Finding {
        param(
            [string] $Id, [string] $Area, [string] $Status, [string] $Severity = 'high',
            [int] $EvidenceCount = 0, $Evidence = @(), [bool] $Truncated = $false,
            [string] $Title = 'A control', $TargetState = $null, $Owner = $null, $Phase = $null
        )
        [pscustomobject]@{
            Id = $Id; Title = $Title; Framework = 'Cloud Governance'; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = $EvidenceCount; Evidence = $Evidence
            EvidenceTruncated = $Truncated; EvidenceCap = 25
            Remediation = "Remediate $Id."; Manual = $false
            TargetState = $TargetState; Owner = $Owner; Effort = 'M'; Phase = $Phase
        }
    }

    $Script:Collect = [pscustomobject]@{
        subscriptions = @(
            [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled' }
            [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; name = 'sub-dev'; state = 'Enabled' }
        )
        _meta = [pscustomobject]@{ scope = 'All'; managementGroupId = 'mg-root'; tenantId = 'tenant-abc' }
    }

    $evidence = @(1..3 | ForEach-Object {
            [pscustomobject]@{
                id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/sa$_"
                name = "sa$_"; type = 'Microsoft.Storage/storageAccounts'; location = 'westus'
            }
        })

    $Script:Scored = [pscustomobject]@{
        GeneratedOn = '2026-08-01T10:00:00.0000000Z'
        Frameworks = @([pscustomobject]@{ Framework = 'Cloud Governance'; Score = 50; Version = 'CAF Govern' })
        Areas = @([pscustomobject]@{
                Framework = 'Cloud Governance'; Area = 'Security'; Score = 50; Weight = 1.0
                Pass = 1; Partial = 0; Fail = 1; Manual = 0; Unknown = 0; Error = 0
            })
        Gaps = @(); Manual = @(); Errors = @()
        Findings = @(
            New-Finding -Id 'SEC-01' -Area 'Security' -Status 'Fail' -Severity 'high' `
                -EvidenceCount 198 -Evidence $evidence -Truncated $true `
                -Title 'Storage accounts should disable public network access' `
                -TargetState 'PublicNetworkAccess=Disabled' -Owner 'Network Engineering' -Phase 1
            New-Finding -Id 'SEC-02' -Area 'Security' -Status 'Pass' -EvidenceCount 9 -Title 'Purge protection'
        )
    }

    $Script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-pbiv2-$([guid]::NewGuid().ToString('N'))"
    $Script:Model = Build-ScoutReportModel -Findings $Script:Scored -Collect $Script:Collect
    Export-PowerBi -Findings $Script:Scored -Collect $Script:Collect -OutputPath $Script:OutDir -Model $Script:Model | Out-Null
    $Script:PbiDir = Join-Path $Script:OutDir 'powerbi'
}

AfterAll {
    if ($Script:OutDir -and (Test-Path $Script:OutDir)) {
        Remove-Item $Script:OutDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Power BI v2 table inventory' {
    It 'still emits the four original tables' -ForEach @(
        @{ Table = 'fact_area_scores.csv' }
        @{ Table = 'fact_framework.csv' }
        @{ Table = 'dim_gaps.csv' }
        @{ Table = 'fact_findings.csv' }
    ) {
        Test-Path (Join-Path $Script:PbiDir $Table) | Should -BeTrue
    }

    It 'emits the new resource-grain fact and its dimensions' -ForEach @(
        @{ Table = 'fact_evidence.csv' }
        @{ Table = 'dim_gap_register.csv' }
        @{ Table = 'dim_subscription.csv' }
        @{ Table = 'dim_domain.csv' }
        @{ Table = 'dim_severity.csv' }
        @{ Table = 'dim_roadmap_phase.csv' }
    ) {
        Test-Path (Join-Path $Script:PbiDir $Table) | Should -BeTrue
    }
}

Describe 'fact_evidence grain and keys' {
    BeforeAll {
        $Script:Evidence = @(Import-Csv (Join-Path $Script:PbiDir 'fact_evidence.csv'))
    }

    It 'is one row per affected resource' {
        $Script:Evidence.Count | Should -Be 3
    }

    It 'carries the subscription key needed to join dim_subscription' {
        $Script:Evidence[0].SubscriptionId | Should -Be '11111111-1111-1111-1111-111111111111'
        $Script:Evidence[0].SubscriptionName | Should -Be 'sub-prod'
    }

    It 'carries the resource identity a consumer needs to act on the row' {
        $Script:Evidence[0].ResourceName | Should -Be 'sa1'
        $Script:Evidence[0].ResourceGroup | Should -Be 'rg-prod'
        $Script:Evidence[0].ResourceType | Should -Be 'Microsoft.Storage/storageAccounts'
    }

    It 'carries the severity, owner and phase so it can be sliced without a second join' {
        $Script:Evidence[0].Severity | Should -Be 'HIGH'
        $Script:Evidence[0].Owner | Should -Be 'Network Engineering'
        $Script:Evidence[0].Phase | Should -Be '1'
    }

    It 'travels with VerdictSource so a Verdict filter cannot silently become a claim' {
        $Script:Evidence[0].Verdict | Should -Not -BeNullOrEmpty
        $Script:Evidence[0].VerdictSource | Should -Be 'heuristic'
    }
}

Describe 'dim_gap_register carries the totals fact_evidence cannot' {
    BeforeAll {
        $Script:Register = @(Import-Csv (Join-Path $Script:PbiDir 'dim_gap_register.csv'))
        $Script:Evidence = @(Import-Csv (Join-Path $Script:PbiDir 'fact_evidence.csv'))
    }

    It 'holds the true affected total, which is NOT the fact_evidence row count when truncated' {
        $gap = $Script:Register | Where-Object RuleId -eq 'SEC-01'
        $gap.EvidenceCount | Should -Be '198'
        $gap.EvidenceTruncated | Should -Be 'True'
        # The whole point: counting rows of the fact table understates this gap by 195.
        [int]$gap.EvidenceCount | Should -Not -Be $Script:Evidence.Count
    }

    It 'holds the target state and closure action' {
        $gap = $Script:Register | Where-Object RuleId -eq 'SEC-01'
        $gap.TargetState | Should -Be 'PublicNetworkAccess=Disabled'
        $gap.ClosureAction | Should -Be 'Remediate SEC-01.'
    }
}

Describe 'Dimensions' {
    It 'orders severity by risk, not alphabetically, with UNKNOWN last' {
        $sev = @(Import-Csv (Join-Path $Script:PbiDir 'dim_severity.csv'))
        ($sev | Where-Object Severity -eq 'CRITICAL').SortOrder | Should -Be '1'
        ($sev | Where-Object Severity -eq 'LOW').SortOrder | Should -Be '4'
        ($sev | Where-Object Severity -eq 'UNKNOWN').SortOrder | Should -Be '99'
    }

    It 'lists every in-scope subscription, including those with no findings' {
        $subs = @(Import-Csv (Join-Path $Script:PbiDir 'dim_subscription.csv'))
        $subs.Count | Should -Be 2
        ($subs | Where-Object Name -eq 'sub-dev') | Should -Not -BeNullOrEmpty
    }

    It 'emits all three roadmap phases even when one is empty' {
        $phases = @(Import-Csv (Join-Path $Script:PbiDir 'dim_roadmap_phase.csv'))
        $phases.Count | Should -Be 3
    }
}

Describe 'Power BI v2 degrades rather than failing' {
    It 'emits the base star schema when no model can be built' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-pbiv2e-$([guid]::NewGuid().ToString('N'))"
        try {
            Export-PowerBi -Findings $null -Collect $null -OutputPath $dir | Out-Null
            Test-Path (Join-Path $dir 'powerbi/fact_findings.csv') | Should -BeTrue
        }
        finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
