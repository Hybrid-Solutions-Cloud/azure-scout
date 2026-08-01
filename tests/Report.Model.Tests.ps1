#Requires -Version 7.0
#Requires -Modules Pester

<#
    Build-ScoutReportModel — the single report model every renderer consumes.
    Tasks AB#6852 (the model) and AB#6855 (evidence projection + triage verdict),
    beneath User Story AB#6443, Feature AB#6449, Epic AB#6450.

    The tests that matter here are the honesty ones. A reporting layer's failure mode is not
    a crash, it is a confident sentence about something nobody measured — so most of what
    follows asserts that absent data stays absent instead of arriving as a zero.

    Pure-logic tests — no Azure connection.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Get-GovernanceDomainScore.ps1"
    . "$root/src/report/Build-ScoutReportModel.ps1"

    function New-TestFinding {
        param(
            [string] $Id = 'R1', [string] $Area = 'Security', [string] $Framework = 'Cloud Governance',
            [string] $Status = 'Fail', [string] $Severity = 'high', [int] $EvidenceCount = 0,
            $Evidence = @(), [bool] $Truncated = $false,
            $TargetState = $null, $Owner = $null, $Effort = $null, $Phase = $null,
            [string] $Title = 'A control', [string] $Remediation = 'Do the thing.'
        )
        [pscustomobject]@{
            Id = $Id; Title = $Title; Framework = $Framework; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = $EvidenceCount; Evidence = $Evidence
            EvidenceTruncated = $Truncated; EvidenceCap = 25
            Remediation = $Remediation; Manual = $false
            TargetState = $TargetState; Owner = $Owner; Effort = $Effort; Phase = $Phase
        }
    }

    function New-TestArea {
        param([string] $Area, $Score, [string] $Framework = 'Cloud Governance',
            [int] $Pass = 1, [int] $Partial = 0, [int] $Fail = 1, [int] $Manual = 0, [int] $Unknown = 0, [int] $ErrorCount = 0)
        [pscustomobject]@{
            Framework = $Framework; Area = $Area; Score = $Score; Weight = 1.0
            Pass = $Pass; Partial = $Partial; Fail = $Fail; Manual = $Manual; Unknown = $Unknown; Error = $ErrorCount
        }
    }

    function New-TestScored {
        param($Areas, $Findings)
        [pscustomobject]@{
            GeneratedOn = '2026-08-01T10:00:00.0000000Z'
            Frameworks = @([pscustomobject]@{ Framework = 'Cloud Governance'; Score = 55; Version = 'CAF Govern' })
            Areas = @($Areas); Gaps = @(); Manual = @(); Errors = @(); Findings = @($Findings)
        }
    }

    $Script:SampleCollect = [pscustomobject]@{
        subscriptions = @(
            [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled' }
            [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; name = 'sub-sandbox'; state = 'Enabled' }
        )
        networking = [pscustomobject]@{ virtualNetworks = @(1, 2, 3); subnets = @(1, 2) }
        governance = [pscustomobject]@{ managementGroups = @(1, 2) }
        _meta = [pscustomobject]@{ scope = 'All'; managementGroupId = 'mg-root'; tenantId = 'd6fc73cf-0000-0000-0000-000000000000' }
    }
}

Describe 'Inventory tiles' {
    It 'counts a collected path' {
        $tiles = Get-ScoutInventoryTile -Collect $Script:SampleCollect
        $vnet = $tiles | Where-Object Label -eq 'Virtual networks'
        $vnet.Value | Should -Be 3
        $vnet.Collected | Should -BeTrue
    }

    It 'reports an uncollected path as $null and Collected=$false, NEVER as 0' {
        # This is the whole point of the tile shape. "Scout did not collect storage accounts"
        # and "this tenant has no storage accounts" render identically the moment either
        # becomes a 0, and the reader has no way to tell an empty estate from a blind spot.
        $tiles = Get-ScoutInventoryTile -Collect $Script:SampleCollect
        $storage = $tiles | Where-Object Label -eq 'Storage accounts'
        $storage.Collected | Should -BeFalse
        $storage.Value | Should -BeNullOrEmpty
        $storage.Value | Should -Not -Be 0
    }

    It 'reports a COLLECTED-but-empty collection as 0, not as a blind spot' {
        # The mirror image of the test above, and the one that actually bit. A property holding
        # an empty array returned through PowerShell's ordinary output stream enumerates to
        # nothing, so the accessor handed back $null and a collected-and-genuinely-empty
        # resourceLocks array was reported as "not collected". Both halves of the distinction
        # have to hold or neither is worth stating.
        $collect = [pscustomobject]@{ governance = [pscustomobject]@{ resourceLocks = @() } }
        # Assigned, not piped: these builders return through the unary comma so an EMPTY result
        # survives the return boundary, which means piping the call directly hands the whole
        # array to the next command as one item. Same convention Resolve-JsonPath uses.
        $tiles = Get-ScoutInventoryTile -Collect $collect
        $tile = $tiles | Where-Object Label -eq 'Resource locks'
        $tile.Collected | Should -BeTrue
        $tile.Value | Should -Be 0
    }

    It 'does not throw on a completely empty collect object' {
        { Get-ScoutInventoryTile -Collect ([pscustomobject]@{}) } | Should -Not -Throw
    }
}

Describe 'Maturity rubric and bands' {
    It 'covers 1-10 with no gap and no overlap' {
        $rubric = Get-ScoutMaturityRubric
        $covered = @($rubric | ForEach-Object { $_.Min..$_.Max }) | Sort-Object
        ($covered -join ',') | Should -Be ((1..10) -join ',')
    }

    It 'bands a score into its published level' {
        Get-ScoutMaturityBand -Score 8 | Should -Be 'Managed'
        Get-ScoutMaturityBand -Score 5 | Should -Be 'Defined'
        Get-ScoutMaturityBand -Score 10 | Should -Be 'Optimised'
    }

    It 'bands a null score as Not assessed, never as the bottom band' {
        Get-ScoutMaturityBand -Score $null | Should -Be 'Not assessed'
    }
}

Describe 'Composite score' {
    It 'is the unweighted mean of the ASSESSED domains only' {
        $domains = New-ScoutMaturityDomain -Areas @((New-TestArea -Area 'A' -Score 80), (New-TestArea -Area 'B' -Score 60))
        $c = New-ScoutCompositeScore -Domains $domains
        $c.Current | Should -Be 7      # (8 + 6) / 2
        $c.AssessedDomainCount | Should -Be 2
        $c.ExcludedDomainCount | Should -Be 0
    }

    It 'excludes a NotAssessed domain from the mean rather than averaging in a fabricated 0' {
        # A NotAssessed domain scored as 0 would drag the headline down to describe controls
        # nobody evaluated — the exact false read the audit's three-state decision prevents.
        $domains = New-ScoutMaturityDomain -Areas @(
            (New-TestArea -Area 'A' -Score 80)
            (New-TestArea -Area 'B' -Score 60)
            (New-TestArea -Area 'C' -Score $null)
        )
        $c = New-ScoutCompositeScore -Domains $domains
        $c.Current | Should -Be 7
        $c.AssessedDomainCount | Should -Be 2
        $c.ExcludedDomainCount | Should -Be 1
    }

    It 'returns a null composite, not 0, when nothing at all was assessed' {
        $domains = New-ScoutMaturityDomain -Areas @((New-TestArea -Area 'A' -Score $null))
        $c = New-ScoutCompositeScore -Domains $domains
        $c.Current | Should -BeNullOrEmpty
        $c.Band | Should -Be 'Not assessed'
    }
}

Describe 'Gap register' {
    It 'builds one row per Fail or Partial finding, worst severity first' {
        $findings = @(
            New-TestFinding -Id 'R-LOW' -Status 'Fail' -Severity 'low'
            New-TestFinding -Id 'R-HIGH' -Status 'Fail' -Severity 'high'
            New-TestFinding -Id 'R-MED' -Status 'Partial' -Severity 'medium'
        )
        $reg = New-ScoutGapRegister -Findings $findings
        @($reg).Count | Should -Be 3
        $reg[0].RuleId | Should -Be 'R-HIGH'
        $reg[0].GapId | Should -Be 'G01'
    }

    It 'excludes Manual and NotAssessed findings — a control nobody could evaluate is not a failure' {
        $findings = @(
            New-TestFinding -Id 'R-FAIL' -Status 'Fail'
            New-TestFinding -Id 'R-MAN' -Status 'Manual'
            New-TestFinding -Id 'R-NA' -Status 'NotAssessed'
            New-TestFinding -Id 'R-PASS' -Status 'Pass'
        )
        $reg = New-ScoutGapRegister -Findings $findings
        @($reg).Count | Should -Be 1
        $reg[0].RuleId | Should -Be 'R-FAIL'
    }

    It 'carries targetState, owner, effort and phase through from the rule' {
        $findings = @(New-TestFinding -Status 'Fail' -TargetState 'PublicNetworkAccess=Disabled' `
                -Owner 'Network Engineering' -Effort 'M' -Phase 2)
        $reg = New-ScoutGapRegister -Findings $findings
        $reg[0].TargetState | Should -Be 'PublicNetworkAccess=Disabled'
        $reg[0].Owner | Should -Be 'Network Engineering'
        $reg[0].Effort | Should -Be 'M'
        $reg[0].Phase | Should -Be 2
    }

    It 'carries the evidence truncation flag so a renderer can say "25 of 198"' {
        $findings = @(New-TestFinding -Status 'Fail' -EvidenceCount 198 -Truncated $true `
                -Evidence @(1..25 | ForEach-Object { [pscustomobject]@{ name = "sa$_" } }))
        $reg = New-ScoutGapRegister -Findings $findings
        $reg[0].EvidenceCount | Should -Be 198
        $reg[0].EvidenceShown | Should -Be 25
        $reg[0].EvidenceTruncated | Should -BeTrue
    }
}

Describe 'Evidence projection (AB#6855)' {
    It 'pulls subscription and resource group out of an ARM id when the row does not name them' {
        $ev = @([pscustomobject]@{
                id = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/sa1'
                name = 'sa1'; type = 'Microsoft.Storage/storageAccounts'
            })
        $rows = ConvertTo-ScoutEvidenceRow -Finding (New-TestFinding -Evidence $ev) -GapId 'G01' `
            -SubscriptionLookup @{ '11111111-1111-1111-1111-111111111111' = 'sub-prod' }
        $rows[0].SubscriptionId | Should -Be '11111111-1111-1111-1111-111111111111'
        $rows[0].SubscriptionName | Should -Be 'sub-prod'
        $rows[0].ResourceGroup | Should -Be 'rg-prod'
        $rows[0].ResourceName | Should -Be 'sa1'
        $rows[0].ResourceType | Should -Be 'Microsoft.Storage/storageAccounts'
    }

    It 'leaves an absent field as $null rather than a fabricated empty string' {
        $rows = ConvertTo-ScoutEvidenceRow -Finding (New-TestFinding -Evidence @([pscustomobject]@{ name = 'orphan' })) -GapId 'G01'
        $rows[0].ResourceId | Should -BeNullOrEmpty
        $rows[0].ResourceGroup | Should -BeNullOrEmpty
        $rows[0].ResourceName | Should -Be 'orphan'
    }

    It 'survives a sparse payload with no recognised properties at all' {
        # The AB#6844 class: a row carrying none of the expected fields must project to a row
        # of nulls, not throw and take the whole report down.
        { ConvertTo-ScoutEvidenceRow -Finding (New-TestFinding -Evidence @([pscustomobject]@{ somethingElse = 1 })) -GapId 'G01' } |
            Should -Not -Throw
    }

    It 'handles a scalar match that carries no resource identity' {
        $rows = ConvertTo-ScoutEvidenceRow -Finding (New-TestFinding -Evidence @('westus')) -GapId 'G01'
        $rows[0].ResourceName | Should -Be 'westus'
        $rows[0].ResourceId | Should -BeNullOrEmpty
    }

    It 'returns an empty array for a finding with no evidence' {
        $rows = ConvertTo-ScoutEvidenceRow -Finding (New-TestFinding -Evidence @()) -GapId 'G01'
        @($rows).Count | Should -Be 0
    }
}

Describe 'Triage verdict (AB#6855)' {
    It 'flags a sandbox placement as out of scope by design' {
        Get-ScoutTriageVerdict -SubscriptionName 'sub-alz-infrastructure-sandbox-dev' |
            Should -Be 'Sandbox - out of scope by design'
    }

    It 'flags an Azure-managed resource group as a deliberate platform pattern' {
        Get-ScoutTriageVerdict -ResourceGroup 'databricks-rg-edp-prd-eus-001' |
            Should -Be 'Platform-required - deliberate pattern'
    }

    It 'flags a landing-zone vending service principal as a deliberate platform pattern' {
        Get-ScoutTriageVerdict -ResourceName 'SPN-PR-ALZ-Subscription-Vending' |
            Should -Be 'Platform-required - deliberate pattern'
    }

    It 'defaults an ordinary production resource to Real - investigate' {
        Get-ScoutTriageVerdict -ResourceName 'stprodpayments001' -SubscriptionName 'sub-prod' |
            Should -Be 'Real - investigate'
    }

    It 'defaults to Real - investigate when it knows nothing at all — never quietly dismisses a row' {
        Get-ScoutTriageVerdict | Should -Be 'Real - investigate'
    }

    It 'stamps every projected row as heuristic so no renderer can present it as confirmed triage' {
        $ev = @([pscustomobject]@{ name = 'sa-sandbox-01' })
        $rows = ConvertTo-ScoutEvidenceRow -Finding (New-TestFinding -Evidence $ev) -GapId 'G01'
        $rows[0].VerdictSource | Should -Be 'heuristic'
    }
}

Describe 'Key risk indicators' {
    It 'states every risk with its supporting count' {
        $findings = @(New-TestFinding -Status 'Fail' -Severity 'high' -EvidenceCount 60 -Title 'Storage public network access')
        $kris = New-ScoutKeyRiskIndicator -Findings $findings
        $kri = $kris | Where-Object RuleId -eq 'R1'
        $kri.SupportingCount | Should -Be 60
        $kri.CurrentState | Should -Match '60'
    }

    It 'includes GOOD rows for controls that passed with evidence behind them' {
        $findings = @(
            New-TestFinding -Id 'R-FAIL' -Status 'Fail' -EvidenceCount 5
            New-TestFinding -Id 'R-PASS' -Status 'Pass' -EvidenceCount 40 -Title 'Tag taxonomy applied'
        )
        $kris = New-ScoutKeyRiskIndicator -Findings $findings
        ($kris | Where-Object Severity -eq 'GOOD').RuleId | Should -Be 'R-PASS'
    }

    It 'surfaces controls that could not be evaluated as their own coverage row' {
        $findings = @(
            New-TestFinding -Id 'R-FAIL' -Status 'Fail' -EvidenceCount 1
            New-TestFinding -Id 'R-NA1' -Status 'NotAssessed'
            New-TestFinding -Id 'R-NA2' -Status 'NotAssessed'
        )
        $kris = New-ScoutKeyRiskIndicator -Findings $findings
        $coverage = $kris | Where-Object Domain -eq 'Coverage'
        $coverage | Should -Not -BeNullOrEmpty
        $coverage.SupportingCount | Should -Be 2
        $coverage.Severity | Should -Be 'UNKNOWN'
    }

    It 'emits no coverage row when every control was evaluated' {
        $kris = New-ScoutKeyRiskIndicator -Findings @(New-TestFinding -Status 'Fail' -EvidenceCount 1)
        ($kris | Where-Object Domain -eq 'Coverage') | Should -BeNullOrEmpty
    }
}

Describe 'Roadmap' {
    It 'honours a rule-declared phase' {
        $reg = New-ScoutGapRegister -Findings @(New-TestFinding -Status 'Fail' -Severity 'low' -Phase 1)
        $phases = New-ScoutRoadmap -GapRegister $reg
        $p1 = $phases | Where-Object Phase -eq 1
        @($p1.Items).Count | Should -Be 1
        $p1.Items[0].PhaseSource | Should -Be 'rule'
    }

    It 'derives a phase from severity when the rule declares none, and says that it did' {
        $reg = New-ScoutGapRegister -Findings @(New-TestFinding -Status 'Fail' -Severity 'high')
        $phases = New-ScoutRoadmap -GapRegister $reg
        $p1 = $phases | Where-Object Phase -eq 1
        @($p1.Items).Count | Should -Be 1
        $p1.Items[0].PhaseSource | Should -Be 'derived-from-severity'
    }

    It 'always emits three phases, even when one of them is empty' {
        $phases = New-ScoutRoadmap -GapRegister @()
        @($phases).Count | Should -Be 3
        @($phases[2].Items).Count | Should -Be 0
    }
}

Describe 'Focus areas' {
    It 'ranks the weakest assessed domain first' {
        $domains = New-ScoutMaturityDomain -Areas @(
            (New-TestArea -Area 'Strong' -Score 90)
            (New-TestArea -Area 'Weak' -Score 30)
        )
        $focus = New-ScoutFocusArea -Domains $domains -GapRegister @()
        $focus[0].Domain | Should -Be 'Weak'
        $focus[0].Rank | Should -Be 1
        $focus[0].Priority | Should -Be 'IMMEDIATE'
    }

    It 'omits NotAssessed domains from the ranking rather than ranking them worst' {
        $domains = New-ScoutMaturityDomain -Areas @(
            (New-TestArea -Area 'Scored' -Score 70)
            (New-TestArea -Area 'Blind' -Score $null)
        )
        $focus = New-ScoutFocusArea -Domains $domains -GapRegister @()
        @($focus).Count | Should -Be 1
        $focus[0].Domain | Should -Be 'Scored'
    }
}

Describe 'Build-ScoutReportModel end to end' {
    BeforeAll {
        $Script:Findings = @(
            New-TestFinding -Id 'SEC-01' -Area 'Security' -Status 'Fail' -Severity 'high' -EvidenceCount 3 `
                -Evidence @(1..3 | ForEach-Object {
                    [pscustomobject]@{
                        id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-a/providers/Microsoft.Storage/storageAccounts/sa$_"
                        name = "sa$_"
                    } })
            New-TestFinding -Id 'SEC-02' -Area 'Security' -Status 'Pass' -EvidenceCount 12
            New-TestFinding -Id 'OPS-01' -Area 'Operations' -Status 'NotAssessed' -Severity 'medium'
        )
        $Script:Scored = New-TestScored -Areas @(
            (New-TestArea -Area 'Security' -Score 50)
            (New-TestArea -Area 'Operations' -Score $null)
        ) -Findings $Script:Findings
        $Script:Model = Build-ScoutReportModel -Findings $Script:Scored -Collect $Script:SampleCollect -RunId 'run-1'
    }

    It 'stamps the schema version' {
        $Script:Model.SchemaVersion | Should -Be '2.0'
    }

    It 'carries every top-level section a renderer needs' {
        foreach ($section in 'Meta', 'Engagement', 'Scope', 'Inventory', 'Maturity', 'KeyRiskIndicators',
            'FocusAreas', 'GapRegister', 'Roadmap', 'Coverage', 'Appendices') {
            $Script:Model.PSObject.Properties[$section] | Should -Not -BeNullOrEmpty -Because "renderers read $section"
        }
    }

    It 'resolves the subscription name onto evidence rows from the ARM id alone' {
        $gap = $Script:Model.GapRegister | Where-Object RuleId -eq 'SEC-01'
        $gap.Evidence[0].SubscriptionName | Should -Be 'sub-prod'
    }

    It 'keeps the NotAssessed domain visible instead of dropping it' {
        $ops = $Script:Model.Maturity.Domains | Where-Object Domain -eq 'Operations'
        $ops | Should -Not -BeNullOrEmpty
        $ops.NotAssessed | Should -BeTrue
        $ops.Score | Should -BeNullOrEmpty
        $Script:Model.Coverage.NotAssessedDomains | Should -Be 1
    }

    It 'does not throw when Findings and Collect are both empty' {
        { Build-ScoutReportModel -Findings ([pscustomobject]@{}) -Collect ([pscustomobject]@{}) } | Should -Not -Throw
    }

    It 'writes report-model.json when an output path is given, and it round-trips through JSON' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "scout-model-$([guid]::NewGuid().ToString('N'))"
        try {
            Build-ScoutReportModel -Findings $Script:Scored -Collect $Script:SampleCollect -OutputPath $dir | Out-Null
            $path = Join-Path $dir 'report-model.json'
            Test-Path $path | Should -BeTrue
            $reloaded = Get-Content $path -Raw | ConvertFrom-Json -Depth 100
            $reloaded.SchemaVersion | Should -Be '2.0'
            $reloaded.Maturity.Composite.Current | Should -Be $Script:Model.Maturity.Composite.Current
        }
        finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
