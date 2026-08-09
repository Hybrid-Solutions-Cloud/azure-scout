#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6762 / AB#6763 — the wizard assessment menu tells the truth.

    Two defects, one menu:

    AB#6762 — fifteen registry entries carried the same names as Scout's fifteen INVENTORY
    categories (Compute, Storage, Networking, …). One filters what is collected, the other what
    is scored. The collision was invisible while the wizard showed a hard-coded list of one
    entry; fixing the manifest path (AB#6754) was about to put both meanings in the same list.

    AB#6763 — with the path fixed, the wizard exposes the whole registry, including `Estate`,
    which declares `Rules = @()` and scores nothing. A menu entry that runs and returns nothing
    is read as *"no findings"* — the same false negative that makes the provably-broken
    collectors worth retiring. A short honest menu beats a long dishonest one.

    No Azure connection.
#>

BeforeAll {
    $script:Root     = Split-Path $PSScriptRoot -Parent
    $script:Manifest = Import-PowerShellDataFile (Join-Path $script:Root 'manifests/assessments.psd1')
    $script:RuleDir  = Join-Path $script:Root 'src/assess/rules'

    . (Join-Path $script:Root 'src/assess/Get-ScoutAvailableAssessment.ps1')
    . (Join-Path $script:Root 'src/assess/Resolve-ScoutAssessmentName.ps1')
    . (Join-Path $script:Root 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:Root 'src/pipeline/Get-ScoutCategoryCoverage.ps1')

    # The fifteen inventory categories the assessment entries used to collide with.
    $script:InventoryCategories = @(
        'Management', 'Monitor', 'Networking', 'Identity', 'Security', 'Compute', 'Storage',
        'Databases', 'Containers', 'Web', 'Analytics', 'AI', 'Integration', 'Hybrid', 'IoT'
    )

    # The wizard's eighteen -- see $inventoryCategories in Start-AZSCWizard.ps1.
    $script:WizardCategories = @(
        'AI', 'Analytics', 'Compute', 'Containers', 'Databases', 'DevOps', 'General', 'Hybrid',
        'Identity', 'Integration', 'IoT', 'Management', 'Migration', 'Monitor', 'Networking',
        'Security', 'Storage', 'Web'
    )

    $script:CollectorRoot = Join-Path $script:Root 'manifests/collectors'
}

Describe 'AB#6762 — no menu entry shares a name with an inventory category' {

    It 'has no registry key equal to an inventory category name' {
        $collisions = @($script:Manifest.Keys | Where-Object { $_ -in $script:InventoryCategories })

        $collisions | Should -BeNullOrEmpty -Because 'the same word must not mean "what to collect" and "what to score" in one menu'
    }

    It 'still carries all fifteen, under the prefixed names' {
        foreach ($c in $script:InventoryCategories) {
            $script:Manifest.Keys | Should -Contain "Assess: $c"
        }
    }
}

Describe 'AB#6762 — a scripted call using a legacy name still works' {

    It 'maps a legacy category name onto its prefixed entry' {
        $resolved = Resolve-ScoutAssessmentName -Name @('Compute') -Manifest $script:Manifest -WarningAction SilentlyContinue

        $resolved | Should -Be 'Assess: Compute'
    }

    It 'warns, naming the new value, so the caller knows what to change' {
        $warnings = @()
        $null = Resolve-ScoutAssessmentName -Name @('Security') -Manifest $script:Manifest -WarningVariable warnings -WarningAction SilentlyContinue

        ($warnings -join ' ') | Should -Match 'Assess: Security'
    }

    It 'leaves a name that is already a registry key untouched, and warns about nothing' {
        $warnings = @()
        $resolved = Resolve-ScoutAssessmentName -Name @('CAF: Azure Landing Zone') -Manifest $script:Manifest -WarningVariable warnings -WarningAction SilentlyContinue

        $resolved | Should -Be 'CAF: Azure Landing Zone'
        $warnings | Should -BeNullOrEmpty
    }

    It 'hands back an unknown name unchanged, for the caller to reject' {
        # Renaming is this function's whole job. Inventing a plausible target for a typo would
        # make the eventual error message point at a name the operator never typed.
        $resolved = Resolve-ScoutAssessmentName -Name @('NoSuchThing') -Manifest $script:Manifest -WarningAction SilentlyContinue

        $resolved | Should -Be 'NoSuchThing'
    }

    It 'preserves order and handles several names at once' {
        $resolved = @(Resolve-ScoutAssessmentName -Name @('CAF: Azure Landing Zone', 'IoT', 'Cost') -Manifest $script:Manifest -WarningAction SilentlyContinue)

        $resolved | Should -Be @('CAF: Azure Landing Zone', 'Assess: IoT', 'Scout: Cost Optimization')
    }
}

Describe 'AB#6763 — the menu lists only assessments Scout can actually run' {

    BeforeAll {
        $script:Available = @(Get-ScoutAvailableAssessment -Manifest $script:Manifest -RuleDirectory $script:RuleDir)
    }

    It 'offers at least one assessment' {
        $script:Available.Count | Should -BeGreaterThan 0
    }

    It 'keeps CAF: Azure Landing Zone, which is the pre-checked default' {
        $script:Available | Should -Contain 'CAF: Azure Landing Zone'
    }

    It 'drops Estate, which declares no rules and therefore scores nothing' {
        $script:Available | Should -Not -Contain 'Estate'
    }

    It 'has a rule file behind every entry it offers' {
        # This is the assertion AB#6763 exists for. An entry whose rules do not exist runs,
        # returns nothing, and is read as "no findings".
        $ruleNames = @(Get-ChildItem -LiteralPath $script:RuleDir -Filter '*.yaml' -File | ForEach-Object { $_.BaseName })

        foreach ($name in $script:Available) {
            $patterns = @($script:Manifest[$name].Rules)
            $matched  = @($ruleNames | Where-Object { $rn = $_; @($patterns | Where-Object { $rn -like $_ }).Count -gt 0 })

            $matched.Count | Should -BeGreaterThan 0 -Because "'$name' is offered in the menu, so something must score when it is selected"
        }
    }

    It 'hides an entry whose rule glob matches no file on disk' {
        # The regression this guards: someone adds a registry entry ahead of its rule file, and
        # it silently becomes a menu option that scores nothing. Proven against a manifest that
        # contains exactly that, not by inspection.
        $fake = @{
            Real    = @{ Rules = @('caf.*') }
            Phantom = @{ Rules = @('caf.thisdoesnotexist') }
        }

        $result = @(Get-ScoutAvailableAssessment -Manifest $fake -RuleDirectory $script:RuleDir)

        $result | Should -Contain 'Real'
        $result | Should -Not -Contain 'Phantom'
    }

    It 'hides an entry with no Rules key at all, rather than throwing under StrictMode' {
        $fake = @{ NoRulesKey = @{ Description = 'nothing to score' } }

        $result = @(Get-ScoutAvailableAssessment -Manifest $fake -RuleDirectory $script:RuleDir)

        $result | Should -BeNullOrEmpty
    }
}

Describe 'AB#6754 / AB#6763 — the wizard consumes the availability list, not the raw registry' {

    It 'filters the menu through Get-ScoutAvailableAssessment' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Start-AZSCWizard.ps1')

        $source | Should -Match 'Get-ScoutAvailableAssessment'
        $source | Should -Not -Match '\$assessmentManifest\.Keys \| Sort-Object'
    }

    It 'resolves the manifest one directory up, not three' {
        # The original defect: three Split-Path calls landed outside the repository, Test-Path
        # returned false on every run, and the wizard fell back to a hard-coded single entry
        # without saying so.
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Start-AZSCWizard.ps1')

        $source | Should -Match '\$moduleRoot\s*=\s*Split-Path \$PSScriptRoot -Parent\s*\r?\n\s*\$manifestPath'
    }

    It 'warns instead of falling back silently when the manifest cannot be resolved' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Start-AZSCWizard.ps1')
        $block  = ([regex]'(?s)if \(Test-Path \$manifestPath\).*?\n        \}\r?\n        else \{.*?\n        \}').Match($source).Value

        $block | Should -Match 'Write-Warning'
    }

    It 'resolves the manifest from the real repository layout' {
        # Proves the path arithmetic against the actual tree rather than against a comment.
        $moduleRoot   = Join-Path $script:Root 'src'
        $manifestPath = Join-Path (Split-Path $moduleRoot -Parent) 'manifests/assessments.psd1'

        Test-Path $manifestPath | Should -BeTrue
    }
}

Describe 'AB#6762 — the assessment core resolves legacy names before indexing the manifest' {

    It 'calls Resolve-ScoutAssessmentName before the first manifest lookup' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-ScoutAssessmentCore.ps1')

        $resolveAt = $source.IndexOf('Resolve-ScoutAssessmentName -Name $Assessment')
        $lookupAt  = $source.IndexOf('$manifest[$_].Collect')

        $resolveAt | Should -BeGreaterThan 0
        $lookupAt  | Should -BeGreaterThan $resolveAt -Because 'an unresolved legacy name would index the hashtable and come back $null'
    }
}

Describe 'AB#6922 — the format menu lists only renderers a run will actually produce' {

    # The AB#6763 principle, applied to output formats. Read as SOURCE rather than by invoking
    # the wizard, because the defect is in the two lists and the branch that chooses between
    # them -- driving an interactive checklist would test the prompt, not the offer.
    BeforeAll {
        $script:WizardSrc = Get-Content (Join-Path $script:Root 'src/Start-AZSCWizard.ps1') -Raw
        $script:CoreSrc   = Get-Content (Join-Path $script:Root 'src/Invoke-ScoutAssessmentCore.ps1') -Raw

        $m = [regex]::Match($script:CoreSrc, '\$script:ScoutHeldRenderers\s*=\s*@\(([^)]*)\)')
        $script:Held = @($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") } | Where-Object { $_ })

        $a = [regex]::Match($script:WizardSrc, '\$assessmentFormats\s*=\s*@\(([^)]*)\)')
        $script:Offered = @($a.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") } | Where-Object { $_ })
    }

    It 'found both lists to compare' {
        $script:Held.Count | Should -BeGreaterThan 0
        $script:Offered.Count | Should -BeGreaterThan 0
    }

    It 'offers no renderer that is on hold — the wizard cannot promise what the core will skip' {
        foreach ($f in $script:Offered) {
            $script:Held | Should -Not -Contain $f -Because "the wizard offers '$f' but Invoke-ScoutAssessmentCore holds it, so the run warns and skips it"
        }
    }

    It 'offers React, which is the deliverable' {
        $script:Offered | Should -Contain 'React'
    }

    It 'defaults an assessment run to React rather than a held renderer' {
        $m = [regex]::Match($script:WizardSrc, '\$defaultFormats\s*=\s*if\s*\(\$wantsAssessment[^)]*\)\s*\{\s*@\(([^)]*)\)')
        $m.Success | Should -BeTrue
        $defaults = @($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") } | Where-Object { $_ })
        $defaults | Should -Contain 'React'
        foreach ($d in $defaults) { $script:Held | Should -Not -Contain $d }
    }

    It 'chooses the assessment list whenever an assessment runs, inventory or not' {
        # The original `$wantsAssessment -and -not $wantsInventory` sent the commonest path --
        # Inventory AND Assessment -- to the inventory-only list, which contains no React.
        $script:WizardSrc | Should -Match '\$formatPool\s*=\s*if\s*\(\$wantsAssessment\)'
        $script:WizardSrc | Should -Not -Match '\$formatPool\s*=\s*if\s*\(\$wantsAssessment\s+-and\s+-not\s+\$wantsInventory\)'
    }
}

Describe 'AB#7101/AB#7102/AB#7103 — the category checklist tells the truth about coverage' {

    BeforeAll {
        if (-not $script:WizardSrc) {
            $script:WizardSrc = Get-Content (Join-Path $script:Root 'src/Start-AZSCWizard.ps1') -Raw
        }
        $script:LiveCoverage = @(Get-ScoutCategoryCoverage -CollectorRoot $script:CollectorRoot)
        $script:LiveByName   = @{}
        foreach ($c in $script:LiveCoverage) { $script:LiveByName[$c.Category] = $c }
    }

    It 'the wizard calls Get-ScoutCategoryCoverage rather than hand-typing a figure' {
        $script:WizardSrc | Should -Match 'Get-ScoutCategoryCoverage'
        # No hand-typed "N/N"-shaped coverage literal anywhere near the category checklist.
        $script:WizardSrc | Should -Not -Match "'\w+\s*\(\d+/\d+\)'"
    }

    It 'offers a way to see per-category detail without leaving the checklist' {
        $script:WizardSrc | Should -Match 'ItemDetail'
        $script:WizardSrc | Should -Match 'i<n> = detail'
    }

    It 'every category the wizard offers exists in the live manifest tree' {
        foreach ($cat in $script:WizardCategories) {
            $script:LiveByName.ContainsKey($cat) | Should -BeTrue -Because "the wizard offers '$cat' but manifests/collectors/$cat has no folder"
        }
    }

    It 'never offers a category with zero collectors as though it collects something' {
        # The regression this guards: a category folder emptied out (collectors retired) while
        # the wizard's hard-coded name list still lists it as a live, selectable source of data.
        foreach ($cat in $script:WizardCategories) {
            $coverage = $script:LiveByName[$cat]
            $coverage.Published | Should -BeGreaterThan 0 -Because "'$cat' is offered in the checklist, so it must collect at least one thing"
        }
    }

    It 'a category folder with zero manifests is reported as zero, not hidden or defaulted' {
        # Proven against a synthetic tree, not by inspection of the real one.
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "scout-coverage-$([guid]::NewGuid())"
        $emptyCat = Join-Path $tempRoot 'Empty'
        New-Item -ItemType Directory -Path $emptyCat -Force | Out-Null
        try {
            $result = @(Get-ScoutCategoryCoverage -CollectorRoot $tempRoot)
            $result.Count | Should -Be 1
            $result[0].Category  | Should -Be 'Empty'
            $result[0].Published | Should -Be 0
            $result[0].Collected | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'the coverage figure agrees with a live, independently-counted manifest total' {
        # Guards against the function itself drifting into a cached/hand-typed number: recompute
        # Published from disk with a completely separate code path and compare.
        foreach ($cat in $script:WizardCategories) {
            $independentCount = @(Get-ChildItem -LiteralPath (Join-Path $script:CollectorRoot $cat) -Filter '*.psd1' -File).Count
            $script:LiveByName[$cat].Published | Should -Be $independentCount -Because "the displayed figure for '$cat' must match manifests/collectors/$cat on disk"
        }
    }

    It 'Collected never exceeds Published for any category' {
        foreach ($c in $script:LiveCoverage) {
            $c.Collected | Should -BeLessOrEqual $c.Published
        }
    }
}

Describe 'AB#7104 — the "Optional inventory data" checklist does not offer dead controls' {

    BeforeAll {
        if (-not $script:WizardSrc) {
            $script:WizardSrc = Get-Content (Join-Path $script:Root 'src/Start-AZSCWizard.ps1') -Raw
        }
        $script:CoreSrc = Get-Content (Join-Path $script:Root 'src/Invoke-AzureScout.ps1') -Raw
    }

    It 'detects the absence of Az.CostManagement before letting Cost data be picked' {
        $script:WizardSrc | Should -Match "'Cost data'\s*\)\s*\{"
        $script:WizardSrc | Should -Match 'Get-Module -ListAvailable -Name Az\.CostManagement'
    }

    It 'does not emit -QuotaUsage, which Invoke-AzureScout never reads' {
        # Invoke-AzureScout declares -QuotaUsage but no code path in the pipeline consumes it --
        # VM quota usage is gathered unconditionally as part of VM details. Emitting the flag
        # from the wizard would print a command that looks like it controls something it does
        # not; the honest fix is to say so and never set the answer.
        ($script:CoreSrc -match '\$QuotaUsage\b[^\r\n]*(\r?\n(?!.*\$QuotaUsage).*){0,400}') | Out-Null
        $quotaUsageReads = @([regex]::Matches($script:CoreSrc, '\$QuotaUsage\b')).Count
        # Exactly one read: the parameter declaration itself. Any second occurrence would mean
        # the pipeline now consumes it and this test (and the wizard's note) are stale.
        $quotaUsageReads | Should -Be 1 -Because 'if this fails, -QuotaUsage is wired now -- update the wizard to actually gate on the answer instead of only warning'

        $script:WizardSrc | Should -Not -Match '\$answers\.QuotaUsage'
        $script:WizardSrc | Should -Match 'AB#7104'
    }
}
