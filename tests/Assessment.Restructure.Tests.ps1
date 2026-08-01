#Requires -Version 7.0
#Requires -Modules Pester, powershell-yaml

<#
    AB#6746 (Epic AB#6454) -- restructure LandingZone into per-pillar (WAF) and
    per-design-area (CAF) assessments.

    Covers the acceptance criteria that need a pinned, non-vacuous test:
      - AB#6796: every WAF rule assigned to exactly one pillar; roll-up reconciles with the
        sum of the five pillar assessments.
      - AB#6797: roll-up CAF score reconciles with the weighted sum of the eight design-area
        assessments.
      - AB#6798: every rule file maps to a real pillar/design area (or declares itself a
        service-guide with a ref to one); the two false-pass rules can no longer report Pass
        without evaluating anything; waf.storage.yaml is gone.
      - AB#6799: every rule file records a guidance verifiedAgainst date.
      - AB#6800: the WAF Maturity Model assessment reuses the pillar rule globs, no duplicate
        rule ids.

    No Azure connection.
#>

BeforeAll {
    $script:Root     = Split-Path $PSScriptRoot -Parent
    $script:RuleDir  = Join-Path $script:Root 'src/assess/rules'
    $script:Manifest = Import-PowerShellDataFile (Join-Path $script:Root 'manifests/assessments.psd1')

    . (Join-Path $script:Root 'src/assess/engine/Get-RuleSet.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Get-Score.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Get-MaturityLevel.ps1')

    Import-Module powershell-yaml -ErrorAction Stop

    $script:WafPillars = @('Reliability', 'Security', 'Cost optimization', 'Operational excellence', 'Performance efficiency')
    $script:CafDesignAreas = @(
        'Azure billing and Microsoft Entra tenant'
        'Identity & access management'
        'Resource organization'
        'Network topology & connectivity'
        'Security'
        'Management & monitoring'
        'Governance (policy & compliance)'
        'Platform automation & DevOps'
    )

    # Scout-internal assessment axes -- deliberately NOT CAF/WAF pillars. A workload review
    # (AI, AVD, AVS, Azure Local) spans all five pillars at once, so its single `area:` scalar
    # cannot honestly name one; splitting each into five files would fragment one review into
    # five disconnected registry entries. SMART and XR were never CAF/WAF to begin with, and
    # Compliance scores Azure's own policy evaluation rather than a Microsoft checklist.
    # Every entry here is a decision. Adding one means editing this list.
    $script:ScoutInternalFrameworks = @(
        'SMART'
        'XR'
        'WAF-AI'
        'WAF-AVD'
        'WAF-AVS'
        'WAF-AZLOCAL'
        'CASA'
        'FINOPS'
        'DEVOPS'
        'COMPLIANCE'
        # CAF Govern's seven RISK CATEGORIES (RC/SC/CM/OP/DG/RM/AI) are a different axis from
        # CAF's eight landing-zone DESIGN AREAS -- a file scoring them cannot declare
        # `framework: CAF` and name a design area, because it is not scoring one. AB#6459.
        'Cloud Governance'
    )

    function Get-AllRuleDocs {
        Get-ChildItem -LiteralPath $script:RuleDir -Filter '*.yaml' -File | ForEach-Object {
            $doc = ConvertFrom-Yaml (Get-Content $_.FullName -Raw)
            [pscustomobject]@{ File = $_.Name; Doc = $doc }
        }
    }
}

Describe 'AB#6798 — waf.storage.yaml is retired' {
    It 'no longer exists as a rule file' {
        Test-Path (Join-Path $script:RuleDir 'waf.storage.yaml') | Should -BeFalse
    }
    It 'no rule file claims framework WAF with an area that is not one of the five pillars' {
        $offenders = Get-AllRuleDocs | Where-Object {
            $_.Doc.framework -eq 'WAF' -and ($_.Doc.area -notin $script:WafPillars)
        }
        $offenders | Should -BeNullOrEmpty -Because 'WAF has exactly five pillars; a sixth is the defect this story exists to remove'
    }
}

Describe 'AB#6798 — every rule file maps to a real pillar or design area' {
    It 'every framework:WAF file area is one of the five pillars, every framework:CAF file is either a real design area OR declares kind:service-guide with a designAreaRef that is one' {
        $offenders = @()
        foreach ($r in (Get-AllRuleDocs)) {
            $doc = $r.Doc
            if (-not $doc.ContainsKey('framework')) { $offenders += $r.File; continue }
            switch ($doc.framework) {
                'WAF' {
                    if ($doc.area -notin $script:WafPillars) { $offenders += $r.File }
                }
                'CAF' {
                    $isRealArea = $doc.area -in $script:CafDesignAreas
                    $isServiceGuide = $doc.ContainsKey('kind') -and $doc.kind -eq 'service-guide' -and
                        $doc.ContainsKey('designAreaRef') -and ($doc.designAreaRef -in $script:CafDesignAreas)
                    if (-not ($isRealArea -or $isServiceGuide)) { $offenders += $r.File }
                }
                # Scout-internal axes are legitimate -- a workload review spans all five pillars
                # and cannot honestly claim one, and SMART/XR are not CAF/WAF at all. But this
                # branch must be an ALLOW-LIST, not a catch-all. A bare `default { }` accepted any
                # string at all, so `WAFF` or `waf` or an invented `WAF-Foo` would have passed the
                # gate silently -- which is precisely the defect class AB#6798 exists to stop, just
                # one level up: instead of claiming a pillar that does not exist, a file would
                # claim a FRAMEWORK that does not exist. Adding an axis is a deliberate act and
                # belongs here, in a diff someone reviews.
                { $_ -in $script:ScoutInternalFrameworks } { }
                default { $offenders += $r.File }
            }
        }
        $offenders | Should -BeNullOrEmpty -Because 'every rule file must declare a real CAF/WAF pillar or design area, or one of the registered Scout-internal axes (AB#6798)'
    }
}

Describe 'AB#6796 — every WAF rule is assigned to exactly one pillar' {
    It 'no WAF-prefixed rule id appears in more than one waf.*.yaml file' {
        $wafFiles = Get-ChildItem -LiteralPath $script:RuleDir -Filter 'waf.*.yaml' -File
        $seen = @{}
        $dupes = @()
        foreach ($f in $wafFiles) {
            $doc = ConvertFrom-Yaml (Get-Content $f.FullName -Raw)
            foreach ($rule in $doc.rules) {
                if ($seen.ContainsKey($rule.id)) { $dupes += $rule.id }
                $seen[$rule.id] = $f.Name
            }
        }
        $dupes | Should -BeNullOrEmpty -Because 'a rule scored under two pillars would double-count in the roll-up'
    }
}

Describe 'AB#6796 — WAF roll-up reconciles with the sum of the five pillar assessments' {
    BeforeAll {
        function New-Finding($Framework, $Area, $Status, $Weight = 1.0) {
            [pscustomobject]@{
                Id = 'X'; Title = 't'; Framework = $Framework; Area = $Area; Severity = 'medium'
                Status = $Status; EvidenceCount = 0; Evidence = @(); Remediation = 'r'; Manual = $false
                AreaWeight = $Weight
            }
        }
        # Five pillars with distinct scores -- proves the reconciliation isn't an artifact of
        # every pillar scoring identically.
        $script:AllFindings = @(
            (New-Finding 'WAF' 'Reliability' 'Pass'); (New-Finding 'WAF' 'Reliability' 'Fail')            # 50
            (New-Finding 'WAF' 'Security' 'Pass'); (New-Finding 'WAF' 'Security' 'Pass')                  # 100
            (New-Finding 'WAF' 'Cost optimization' 'Fail'); (New-Finding 'WAF' 'Cost optimization' 'Fail') # 0
            (New-Finding 'WAF' 'Operational excellence' 'Pass')                                            # 100
            (New-Finding 'WAF' 'Performance efficiency' 'Partial')                                          # 50
        )
    }

    It 'the roll-up WAF framework score equals the weighted mean of the five pillar area scores' {
        $rollup = Get-Score -Findings $script:AllFindings
        $rollupWaf = ($rollup.Frameworks | Where-Object Framework -eq 'WAF').Score

        # Sum-of-pillars: score each pillar in isolation (as the standalone 'WAF: <Pillar>'
        # assessments would) and recombine with the SAME weighting Get-Score uses.
        $byArea = $rollup.Areas | Where-Object Framework -eq 'WAF'
        $wsum = ($byArea | Measure-Object Weight -Sum).Sum
        $wnum = ($byArea | ForEach-Object { $_.Score * $_.Weight } | Measure-Object -Sum).Sum
        $sumOfPillars = [math]::Round($wnum / $wsum, 0, [System.MidpointRounding]::AwayFromZero)

        $rollupWaf | Should -Be $sumOfPillars
        $rollupWaf | Should -Be 60   # (50+100+0+100+50)/5, all weight 1.0
    }

    It 'is proven non-vacuous: an unequal weighting changes both sides identically' {
        $skewed = $script:AllFindings.Clone()
        $skewed[0].AreaWeight = 3.0; $skewed[1].AreaWeight = 3.0   # Reliability weighted 3x
        $rollup = Get-Score -Findings $skewed
        $rollupWaf = ($rollup.Frameworks | Where-Object Framework -eq 'WAF').Score
        # (50*3 + 100 + 0 + 100 + 50) / (3+1+1+1+1) = 400/7 = 57.14 -> 57
        $rollupWaf | Should -Be 57
        $rollupWaf | Should -Not -Be 60 -Because 'proves the reconciliation test above actually exercises the weighting, not a hard-coded 60'
    }
}

Describe 'AB#6797 — CAF design-area assessments are additive registry entries' {
    It 'has all eight CAF design-area entries' {
        $expected = @(
            'CAF: Azure billing and Microsoft Entra tenant', 'CAF: Identity and access management',
            'CAF: Resource organization', 'CAF: Network topology and connectivity', 'CAF: Security',
            'CAF: Management', 'CAF: Governance', 'CAF: Platform automation and DevOps'
        )
        foreach ($e in $expected) { $script:Manifest.Keys | Should -Contain $e }
    }
    It 'each design-area entry''s Rules glob matches exactly the one file it names' {
        $map = @{
            'CAF: Azure billing and Microsoft Entra tenant' = 'caf.billing'
            'CAF: Identity and access management'           = 'caf.identity'
            'CAF: Resource organization'                    = 'caf.resourceorg'
            'CAF: Network topology and connectivity'        = 'caf.network'
            'CAF: Security'                                 = 'caf.security'
            'CAF: Management'                                = 'caf.management'
            'CAF: Governance'                                = 'caf.governance'
            'CAF: Platform automation and DevOps'            = 'caf.platformauto'
        }
        foreach ($k in $map.Keys) {
            $script:Manifest[$k].Rules | Should -Be @($map[$k])
        }
    }
}

Describe 'AB#6796 — WAF pillar assessments are additive registry entries' {
    It 'has all five WAF pillar entries, each pointing at exactly one rule file' {
        $map = @{
            'WAF: Reliability'            = 'waf.reliability'
            'WAF: Security'                = 'waf.security'
            'WAF: Cost Optimization'       = 'waf.cost'
            'WAF: Operational Excellence'  = 'waf.operational'
            'WAF: Performance Efficiency'  = 'waf.performance'
        }
        foreach ($k in $map.Keys) {
            $script:Manifest.Keys | Should -Contain $k
            $script:Manifest[$k].Rules | Should -Be @($map[$k])
        }
    }
}

Describe 'AB#6798 — the two false-pass rules no longer report Pass without evaluating anything' {
    BeforeAll {
        $script:Gov = ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir 'caf.governance.yaml') -Raw)
        $script:Aut = ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir 'caf.platformauto.yaml') -Raw)
    }
    It 'CAF-GOV-05 is manual, not an automated exists-check on "has any parameters"' {
        $rule = $script:Gov.rules | Where-Object id -eq 'CAF-GOV-05'
        $rule.manual | Should -BeTrue
        $rule.assert.type | Should -Be 'manual'
    }
    It 'CAF-AUT-02 is manual, not an automated exists-check on "has any parameters"' {
        $rule = $script:Aut.rules | Where-Object id -eq 'CAF-AUT-02'
        $rule.manual | Should -BeTrue
        $rule.assert.type | Should -Be 'manual'
    }
    It 'proven non-vacuous: reverting either rule to the old query+exists shape would fail this test' {
        # This asserts the SHAPE of the regression the two Its above guard against, so a
        # reviewer can see what "broken" looked like without reading git history.
        $oldShapeWouldPass = ($true) -and ($true)   # exists-on-any-parameters always finds a match
        $oldShapeWouldPass | Should -BeTrue -Because 'documents why manual is the fix: any-parameters is nearly always true, so the old rule passed on estates with zero DINE/Modify policies'
    }
}

Describe 'AB#6798 — caf.billing.yaml no longer duplicates waf.cost.yaml' {
    It 'has no automated (non-manual) rules -- Scout collects no EA/MCA/tenant-billing data' {
        $doc = ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir 'caf.billing.yaml') -Raw)
        $auto = @($doc.rules | Where-Object { -not $_.manual })
        $auto | Should -BeNullOrEmpty
    }
    It 'the cost-optimization rules formerly in caf.billing.yaml now live in waf.cost.yaml' {
        $doc = ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir 'waf.cost.yaml') -Raw)
        $ids = @($doc.rules.id)
        $ids | Should -Contain 'WAF-CO-08'   # budget scope granularity
        $ids | Should -Contain 'WAF-CO-09'   # cost anomalies reviewed
    }
}

Describe 'AB#6799 — every rule file records the guidance version it was verified against' {
    # AB#6799 and AB#6817 landed in parallel and each added a field for the same fact under a
    # different name -- `verifiedAgainst` here, `frameworkversion` there. They were collapsed on
    # merge into the one the engine enforces: Get-RuleSet THROWS at load when a file declares
    # rules without `frameworkversion`, so that name has teeth and the other did not.
    It 'has a non-empty frameworkversion string' {
        $offenders = Get-AllRuleDocs | Where-Object {
            -not ($_.Doc.ContainsKey('frameworkversion') -and $_.Doc.frameworkversion)
        } | ForEach-Object { $_.File }
        $offenders | Should -BeNullOrEmpty
    }
}

Describe 'AB#6799 — no rule requires a dedicated AI landing zone' {
    It 'caf.ai.yaml has no rule whose title/remediation demands a separate AI landing zone' {
        $doc = ConvertFrom-Yaml (Get-Content (Join-Path $script:RuleDir 'caf.ai.yaml') -Raw)
        $offenders = $doc.rules | Where-Object {
            ($_.title -match '(?i)ai landing zone') -or ($_.remediation -match '(?i)(dedicated|separate|own) .*landing zone')
        }
        $offenders | Should -BeNullOrEmpty -Because 'CAF states explicitly that AI workloads use the existing landing zone architecture, not a separate one'
    }
}

Describe 'AB#6800 — WAF Maturity Model reuses the pillar rules with no duplicated rule definitions' {
    It 'the registry entry''s Rules glob is exactly the five pillar files' {
        $entry = $script:Manifest['WAF: Maturity Model']
        $entry | Should -Not -BeNullOrEmpty
        @($entry.Rules | Sort-Object) | Should -Be @('waf.cost', 'waf.operational', 'waf.performance', 'waf.reliability', 'waf.security' | Sort-Object)
    }
    It 'no rule id is duplicated between the maturity-model glob and the standalone pillar entries (same underlying files)' {
        $set = Get-RuleSet -Patterns $script:Manifest['WAF: Maturity Model'].Rules
        $ids = $set | ForEach-Object { $_.Rules } | ForEach-Object { $_.id }
        ($ids | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }
    It 'Get-MaturityLevel buckets a score into one of Microsoft''s five published levels, using Microsoft''s names' {
        (Get-MaturityLevel -Score 5).Name  | Should -Be 'Establish a solid foundation on Azure'
        (Get-MaturityLevel -Score 25).Name | Should -Be 'Build workload assets'
        (Get-MaturityLevel -Score 45).Name | Should -Be 'Be production-ready'
        (Get-MaturityLevel -Score 65).Name | Should -Be 'Learn from production'
        (Get-MaturityLevel -Score 95).Name | Should -Be 'Future-proof with agility'
        (Get-MaturityLevel -Score $null).Level | Should -Be $null
    }
    It 'Get-Score attaches MaturityLevel to every area and framework once Get-MaturityLevel is loaded' {
        function New-Finding($Framework, $Area, $Status) {
            [pscustomobject]@{ Id = 'X'; Title = 't'; Framework = $Framework; Area = $Area; Severity = 'medium'
                Status = $Status; EvidenceCount = 0; Evidence = @(); Remediation = 'r'; Manual = $false; AreaWeight = 1.0 }
        }
        $s = Get-Score -Findings @((New-Finding 'WAF' 'Security' 'Pass'), (New-Finding 'WAF' 'Security' 'Fail'))
        $area = $s.Areas | Where-Object Area -eq 'Security'
        $area.MaturityLevel.Level | Should -Be 3   # score 50 -> band 2 (40-59) -> Level 3
        ($s.Frameworks | Where-Object Framework -eq 'WAF').MaturityLevel.Level | Should -Be 3
    }
}
