#Requires -Version 7.0
#Requires -Modules Pester

<#
    The v3.8.0 assessment-key namespace rename -- the backward-compat contract.

    Twelve registry keys gained a namespace prefix (CAF: / Microsoft: / Scout: /
    Workload:). Renaming a value people put in scripts must not break those
    scripts, so Resolve-ScoutAssessmentName carries a 12-entry alias map: every
    old key resolves to its new key, with a deprecation warning naming the
    replacement. This file pins that contract:

      - each of the 12 old names resolves to exactly its decided new key
      - the deprecation warning fires exactly once per resolution
      - new keys pass through untouched, with no warning
      - unknown names still pass through unchanged (the caller rejects them)
      - the AB#6762 `Assess: ` retry still works alongside the alias map
      - end to end, `-Assessment LandingZone` still runs the renamed entry

    No Azure connection -- the end-to-end leg replays the canonical fixture.
#>

BeforeAll {
    $script:Root     = Split-Path $PSScriptRoot -Parent
    $script:Manifest = Import-PowerShellDataFile (Join-Path -Path $script:Root -ChildPath 'manifests/assessments.psd1')

    . (Join-Path -Path $script:Root -ChildPath 'src/assess/Resolve-ScoutAssessmentName.ps1')

    # The decided rename map, verbatim. Changing either column is a product
    # decision, not a refactor -- this literal table is the point of the test.
    $script:RenameMap = @(
        @{ Old = 'LandingZone';                  New = 'CAF: Azure Landing Zone' }
        @{ Old = 'CASA';                         New = 'Microsoft: CASA' }
        @{ Old = 'DevOps Capability Assessment'; New = 'Microsoft: DevOps Capability' }
        @{ Old = 'SMART';                        New = 'Microsoft: SMART Migration' }
        @{ Old = 'FinOps Review';                New = 'Microsoft: FinOps Review' }
        @{ Old = 'Cost';                         New = 'Scout: Cost Optimization' }
        @{ Old = 'CrossResource';                New = 'Scout: Cross-Resource' }
        @{ Old = 'Monitoring';                   New = 'Scout: Monitoring Baseline' }
        @{ Old = 'UpdateManager';                New = 'Scout: Update Manager' }
        @{ Old = 'Governance';                   New = 'Scout: Governance Baseline' }
        @{ Old = 'AVS Workload';                 New = 'Workload: AVS' }
        @{ Old = 'AVS Landing Zone';             New = 'Workload: AVS Landing Zone' }
    )
}

Describe 'v3.8.0 rename -- every old key resolves to its new key' {

    It 'resolves ''<Old>'' to ''<New>''' -ForEach @(
        @{ Old = 'LandingZone';                  New = 'CAF: Azure Landing Zone' }
        @{ Old = 'CASA';                         New = 'Microsoft: CASA' }
        @{ Old = 'DevOps Capability Assessment'; New = 'Microsoft: DevOps Capability' }
        @{ Old = 'SMART';                        New = 'Microsoft: SMART Migration' }
        @{ Old = 'FinOps Review';                New = 'Microsoft: FinOps Review' }
        @{ Old = 'Cost';                         New = 'Scout: Cost Optimization' }
        @{ Old = 'CrossResource';                New = 'Scout: Cross-Resource' }
        @{ Old = 'Monitoring';                   New = 'Scout: Monitoring Baseline' }
        @{ Old = 'UpdateManager';                New = 'Scout: Update Manager' }
        @{ Old = 'Governance';                   New = 'Scout: Governance Baseline' }
        @{ Old = 'AVS Workload';                 New = 'Workload: AVS' }
        @{ Old = 'AVS Landing Zone';             New = 'Workload: AVS Landing Zone' }
    ) {
        $resolved = Resolve-ScoutAssessmentName -Name @($Old) -Manifest $script:Manifest -WarningAction SilentlyContinue

        $resolved | Should -Be $New
    }

    It 'every new key in the map actually exists in the registry' {
        foreach ($row in $script:RenameMap) {
            $script:Manifest.Keys | Should -Contain $row.New
        }
    }

    It 'no old key remains as a registry key -- the alias map is the only route' {
        foreach ($row in $script:RenameMap) {
            $script:Manifest.Keys | Should -Not -Contain $row.Old
        }
    }
}

Describe 'v3.8.0 rename -- the deprecation warning' {

    It 'fires exactly once per resolved alias, and names both the old and new value' {
        foreach ($row in $script:RenameMap) {
            $warnings = @()
            $null = Resolve-ScoutAssessmentName -Name @($row.Old) -Manifest $script:Manifest -WarningVariable warnings -WarningAction SilentlyContinue

            @($warnings).Count | Should -Be 1 -Because "'$($row.Old)' is one aliased name, so one warning"
            $warnings[0] | Should -Match ([regex]::Escape($row.Old))
            $warnings[0] | Should -Match ([regex]::Escape($row.New))
        }
    }

    It 'stays silent for a name that is already a current registry key' {
        foreach ($row in $script:RenameMap) {
            $warnings = @()
            $resolved = Resolve-ScoutAssessmentName -Name @($row.New) -Manifest $script:Manifest -WarningVariable warnings -WarningAction SilentlyContinue

            $resolved | Should -Be $row.New
            $warnings | Should -BeNullOrEmpty
        }
    }
}

Describe 'v3.8.0 rename -- the surrounding contract is unchanged' {

    It 'hands back an unknown name unchanged, for the caller to reject' {
        $resolved = Resolve-ScoutAssessmentName -Name @('NoSuchAssessment') -Manifest $script:Manifest -WarningAction SilentlyContinue

        $resolved | Should -Be 'NoSuchAssessment'
    }

    It 'still applies the AB#6762 Assess: retry for legacy category names' {
        $resolved = Resolve-ScoutAssessmentName -Name @('Compute') -Manifest $script:Manifest -WarningAction SilentlyContinue

        $resolved | Should -Be 'Assess: Compute'
    }

    It 'preserves order across a mix of aliased, current, legacy-category and unknown names' {
        $resolved = @(Resolve-ScoutAssessmentName -Name @('UpdateManager', 'CAF: Azure Landing Zone', 'IoT', 'Mystery') -Manifest $script:Manifest -WarningAction SilentlyContinue)

        $resolved | Should -Be @('Scout: Update Manager', 'CAF: Azure Landing Zone', 'Assess: IoT', 'Mystery')
    }
}

Describe 'v3.8.0 rename -- -Assessment LandingZone still runs, end to end' {

    BeforeAll {
        Import-Module "$script:Root/AzureScout.psd1" -Force -ErrorAction Stop
        $script:Module  = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:Root } | Select-Object -First 1
        $script:Fixture = "$script:Root/tests/datadump/sample-collect.json"
        $script:OutRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("AZSC_NameAlias_" + [System.IO.Path]::GetRandomFileName())
    }

    AfterAll {
        if ($script:OutRoot -and (Test-Path $script:OutRoot)) {
            Remove-Item $script:OutRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'a run selecting the OLD name produces findings stamped with the NEW name' {
        $run = & $script:Module {
            param($fixture, $outRoot)
            Invoke-ScoutAssessmentCore -Assessment LandingZone -FromCollect $fixture -OutputFormat Json -OutputPath $outRoot
        } $script:Fixture $script:OutRoot 3>$null

        @($run).Count | Should -Be 1
        $findingsPath = Join-Path -Path $run -ChildPath 'findings.json'
        Test-Path $findingsPath | Should -BeTrue

        $findings = (Get-Content $findingsPath -Raw | ConvertFrom-Json -Depth 100).Findings
        @($findings).Count | Should -BeGreaterThan 0

        $stamped = @($findings | Where-Object { $_.PSObject.Properties['Assessment'] } | ForEach-Object Assessment | Select-Object -Unique)
        $stamped | Should -Contain 'CAF: Azure Landing Zone' -Because 'the alias layer resolves before the manifest lookup, so the run executes the renamed entry'
        $stamped | Should -Not -Contain 'LandingZone'
    }
}
