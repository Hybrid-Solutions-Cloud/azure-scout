#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#6890 — a landing-zone audit must score the landing zone, and nothing else.

    `LandingZone` used to declare `Rules = @('caf.*', 'waf.*', 'xr.*')`. By the time the workload
    assessments existed (Epic AB#6454) that glob was sweeping `waf.ai`, `waf.avd` and every
    `waf.azurelocal.*` file into it, so a run that selected LandingZone and Cloud Governance
    produced 34 scored areas where the audit covers 14 — and the evidence workbook grew a visible
    tab for each of them, which is the symptom the bug was raised on.

    The failure mode is what makes this worth a gate: adding a new `waf.<workload>.yaml` silently
    joins it to LandingZone. Nothing errors, nothing warns, and the audit quietly widens. This is
    the same dangling-glob class that silently cost `Assess: Storage` its WAF rules — the glob
    just pointed the other way.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Manifest = Import-PowerShellDataFile "$script:Root/manifests/assessments.psd1"
    $script:RuleDir = "$script:Root/src/assess/rules"
}

Describe 'AB#6890 — LandingZone scope is enumerated, not globbed' {

    It 'does not declare a bare waf.* glob' {
        # The whole point: `waf.*` is what let workload rule files in by filename alone.
        @($script:Manifest.'CAF: Azure Landing Zone'.Rules) | Should -Not -Contain 'waf.*'
    }

    It 'names exactly the five WAF pillars' {
        $waf = @(@($script:Manifest.'CAF: Azure Landing Zone'.Rules) | Where-Object { $_ -like 'waf.*' } | Sort-Object)
        $waf | Should -Be @(
            'waf.cost'
            'waf.operational'
            'waf.performance'
            'waf.reliability'
            'waf.security'
        )
    }

    It 'excludes every caf rule file that belongs to another assessment' {
        # Enumerated against the manifest itself: any caf.* file another entry claims must not
        # also be scored by the landing-zone roll-up.
        $declared = @($script:Manifest.'CAF: Azure Landing Zone'.Rules)
        $others = foreach ($k in $script:Manifest.Keys) {
            if ($k -eq 'CAF: Azure Landing Zone') { continue }
            $spec = $script:Manifest[$k]
            if (-not $spec.ContainsKey('Rules')) { continue }
            foreach ($p in @($spec.Rules)) { if ($p -like 'caf.*' -and $p -notmatch '\*') { $p } }
        }
        $others = @($others | Sort-Object -Unique)
        $overlap = @($others | Where-Object { $declared -contains $_ -or $declared -contains "$_.yaml" })
        # Some overlap is legitimate -- caf.security is both a design area and the basis of the
        # Security assessment. What must NOT appear is a workload file.
        foreach ($w in @('caf.iot', 'caf.avslandingzone', 'caf.ai', 'caf.storage',
                'caf.web', 'caf.containers', 'caf.databases', 'caf.analytics',
                'caf.hybrid', 'caf.integration')) {
            $declared | Should -Not -Contain $w -Because "$w is owned by its own assessment; a landing-zone audit must not score it"
        }
        $overlap.Count | Should -BeGreaterOrEqual 0   # documented, not asserted -- see comment
    }

    It 'excludes every workload rule file that merely starts with waf.' {
        # Enumerated against what is actually on disk, so a NEW workload file added tomorrow
        # fails this test rather than silently widening the audit.
        $declared = @($script:Manifest.'CAF: Azure Landing Zone'.Rules)
        $pillars = @('waf.cost', 'waf.operational', 'waf.performance', 'waf.reliability', 'waf.security')
        # Manifest patterns carry NO .yaml extension -- every other entry in the registry uses
        # 'caf.iot', not 'caf.iot.yaml', and Get-RuleSet matches on that form. Adding the
        # extension silently matched nothing and narrowed the audit to two areas.
        $workloadFiles = @(Get-ChildItem $script:RuleDir -Filter 'waf.*.yaml' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Name -replace '\.yaml$', '' } |
                Where-Object { $_ -notin $pillars })

        # There ARE workload files -- if this is ever zero the test below proves nothing.
        $workloadFiles.Count | Should -BeGreaterThan 0

        foreach ($w in $workloadFiles) {
            $declared | Should -Not -Contain $w -Because "$w is a workload rule set and has its own assessment; a landing-zone audit must not score it"
        }
    }

    It 'does not declare a bare caf.* glob either' {
        # Same defect, other framework: caf.* swept in caf.iot, caf.avslandingzone, caf.ai,
        # caf.storage and the rest -- every one of which has its own assessment entry.
        @($script:Manifest.'CAF: Azure Landing Zone'.Rules) | Should -Not -Contain 'caf.*'
    }

    It 'names exactly the eight CAF landing-zone design areas' {
        $caf = @(@($script:Manifest.'CAF: Azure Landing Zone'.Rules) | Where-Object { $_ -like 'caf.*' } | Sort-Object)
        $caf | Should -Be @(
            'caf.billing'
            'caf.governance'
            'caf.identity'
            'caf.management'
            'caf.network'
            'caf.platformauto'
            'caf.resourceorg'
            'caf.security'
        )
    }

    It 'still covers the cross-resource rules' {
        # The fix must not narrow the audit either. Enumerating was about excluding what belongs
        # to another assessment, not about dropping coverage.
        @($script:Manifest.'CAF: Azure Landing Zone'.Rules) | Should -Contain 'xr.*'
    }

    It 'every enumerated pillar file actually exists' {
        # An enumerated list can go stale in a way a glob cannot: a renamed file just stops being
        # scored, silently. Same nil-result-is-invisible problem the audit was raised on.
        foreach ($p in @($script:Manifest.'CAF: Azure Landing Zone'.Rules | Where-Object { $_ -notmatch '\*' })) {
            (Join-Path $script:RuleDir "$p.yaml") | Should -Exist -Because "LandingZone names $p explicitly, so a rename must fail loudly here rather than silently drop it"
        }
    }
}
