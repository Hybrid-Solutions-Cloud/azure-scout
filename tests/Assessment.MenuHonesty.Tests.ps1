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

    # The fifteen inventory categories the assessment entries used to collide with.
    $script:InventoryCategories = @(
        'Management', 'Monitor', 'Networking', 'Identity', 'Security', 'Compute', 'Storage',
        'Databases', 'Containers', 'Web', 'Analytics', 'AI', 'Integration', 'Hybrid', 'IoT'
    )
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
