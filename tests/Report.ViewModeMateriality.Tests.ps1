#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Regression test for AB#6936 -- proves the three view modes (Executive/Consultant/Data)
    render MATERIALLY different content for every one of the six nav sections, not just that
    switching modes runs without throwing.

.DESCRIPTION
    report-react.html.template builds its ENTIRE multi-page document once at boot (assemble()),
    with every Executive/Consultant/Data variant embedded inline as depth-exec/depth-cons/
    depth-data-tagged markup; the View toggle only flips a body[data-view] attribute and lets CSS
    show/hide those classes (see the template's own <style> block). A no-throw test of mode
    switching therefore proves nothing about content -- the CSS could regress to always showing
    the same block and every existing test would stay green.

    This test instead: builds a real Findings + Collect fixture deliberately sized to exceed
    EVERY depth-cons/depth-data reveal cap the template defines (evidenceTable's 12-evidence cap,
    categoryBlocksFor's 50-row cap, the Top-categories-grid's 12-card cap, pageData's 60-row cap,
    and the remediation/assessmentNext ">3 actions" reveal) -- a fixture that stayed under any one
    of those caps would make Consultant byte-identical to Data for that specific widget, silently
    not exercising AB#6936's fix at all. Runs that fixture through the REAL Get-Score/Export-React
    pipeline (same as tests/Report.React.Tests.ps1) so the embedded __SCOUT_DATA__ payload matches
    the real contract exactly, then hands the real template + that payload to
    tests/view-mode-materiality-checker.mjs (ported boot-in-a-Node-vm-sandbox approach from
    tests/ReactReport.DiagramOverlap.Tests.ps1's diagram-overlap-checker.mjs, extended with a
    getElementById('app') override that actually captures assemble()'s output instead of
    discarding it). The checker parses that captured HTML into a lightweight tree, mirrors the
    template's own depth-exec/depth-cons/depth-data CSS visibility rule to compute what's actually
    visible per (nav section, view mode) pair, and asserts every section's three modes are
    pairwise non-identical and differ by more than a trivial character-count floor.

    No Azure connection; requires `node` on PATH (already a repo dependency for the docs site) --
    skipped, not failed, when unavailable.
#>

Describe 'React report view modes — Executive/Consultant/Data differ materially per nav section (AB#6936)' {
    BeforeAll {
        $script:Root = Split-Path $PSScriptRoot -Parent
        . "$script:Root/src/assess/engine/Get-Score.ps1"
        . "$script:Root/src/report/renderers/Export-React.ps1"

        $script:TemplatePath = Join-Path -Path $script:Root -ChildPath 'src' -AdditionalChildPath 'report', 'templates', 'report-react.html.template'
        $script:Checker = Join-Path -Path $script:Root -ChildPath 'tests' -AdditionalChildPath 'view-mode-materiality-checker.mjs'
        $script:NodeAvailable = [bool](Get-Command node -ErrorAction SilentlyContinue)

        function New-MaterialityFinding {
            param($Id, $Area, $Status, $Severity, $Evidence, $AssessmentName)
            [pscustomobject]@{
                Id            = $Id
                Title         = "$Area check $Id — a fairly descriptive configuration gap"
                Framework     = 'CAF'
                Area          = $Area
                Severity      = $Severity
                Status        = $Status
                EvidenceCount = @($Evidence).Count
                Evidence      = $Evidence
                Remediation   = "Adjust the $Area configuration to meet the baseline. Then re-run the assessment to confirm the fix."
                Manual        = ($Status -eq 'Manual')
                AreaWeight    = 1.0
            } | Add-Member -NotePropertyName Assessment -NotePropertyValue $AssessmentName -PassThru
        }

        # 10 areas x 8 findings = 80 findings, 60 of them Fail -- deliberately > pageData's
        # 60-row cap, and 6 Fail per area (> the remediation/assessmentNext ">3 actions" reveal
        # threshold), across 10 design areas (> the roadmap's top-5 executive-summary cap). Split
        # across 3 assessments (not 1) so pageOverview's exec band-list vs cons gauge-tiles and
        # the "as" section's per-assessment register pages each carry real multiplicity -- a
        # single assessment made the exec/cons Overview delta and the evidenceTable cap reveal
        # too close to the materiality floor to be a meaningful regression guard.
        $areaAssessment = @{
            Identity = 'Assess: Materiality Alpha'; Networking = 'Assess: Materiality Alpha'; Security = 'Assess: Materiality Alpha'; 'Cost Management' = 'Assess: Materiality Alpha'
            DevOps = 'Assess: Materiality Beta'; Storage = 'Assess: Materiality Beta'; Databases = 'Assess: Materiality Beta'
            Web = 'Assess: Materiality Gamma'; Compute = 'Assess: Materiality Gamma'; Governance = 'Assess: Materiality Gamma'
        }
        $areas = 'Identity', 'Networking', 'Security', 'Cost Management', 'DevOps', 'Storage', 'Databases', 'Web', 'Compute', 'Governance'
        $statusCycle = 'Fail', 'Fail', 'Fail', 'Fail', 'Pass', 'Fail', 'Manual', 'Fail'
        $sevCycle = 'high', 'medium', 'low', 'high', 'medium', 'low', 'high', 'medium'
        $script:BigFindings = @()
        $counter = 0
        foreach ($area in $areas) {
            $slugArea = $area -replace '\s', ''
            for ($i = 0; $i -lt 8; $i++) {
                $counter++
                if ($area -eq 'Networking' -and $i -eq 0) {
                    # 40 evidence rows -- well past evidenceTable's 12-row cap (AB#6936); the
                    # 28-row cons/data delta this produces is deliberately large, not borderline.
                    $evidence = 1..40 | ForEach-Object { [pscustomobject]@{ name = "res-net-$_"; resourceGroup = 'rg-materiality'; subscriptionId = 'sub-0001' } }
                } else {
                    $evidence = 1..2 | ForEach-Object { [pscustomobject]@{ name = "res-$slugArea-$counter-$_"; resourceGroup = 'rg-materiality'; subscriptionId = 'sub-0001' } }
                }
                $script:BigFindings += New-MaterialityFinding -Id "mat-$counter" -Area $area -Status $statusCycle[$i] -Severity $sevCycle[$i] -Evidence $evidence -AssessmentName $areaAssessment[$area]
            }
        }
        $script:BigScored = Get-Score -Findings $script:BigFindings

        # >12 inventory categories (exceeds the Top-categories-grid's 12-card cap), with
        # compute.virtualMachines at 60 rows (exceeds categoryBlocksFor's 50-row cap).
        function New-MaterialityRows {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
param([string] $Prefix, [int] $Count)
            1..$Count | ForEach-Object { [pscustomobject]@{ name = "$Prefix-$_"; resourceGroup = 'rg-materiality'; subscriptionId = 'sub-0001' } }
        }
        $script:BigCollect = [pscustomobject]@{
            _meta         = [pscustomobject]@{ scope = 'All'; managementGroupId = 'mg-materiality'; generatedOn = (Get-Date).ToString('o') }
            subscriptions = @([pscustomobject]@{ subscriptionId = 'sub-0001'; name = 'sub-materiality'; state = 'Enabled' })
            networking    = [ordered]@{ virtualNetworks = (New-MaterialityRows 'vnet' 8); subnets = (New-MaterialityRows 'snet' 8); nsgRules = (New-MaterialityRows 'nsgrule' 8) }
            compute       = [ordered]@{ virtualMachines = (New-MaterialityRows 'vm' 60); disks = (New-MaterialityRows 'disk' 8) }
            storage       = [ordered]@{ storageAccounts = (New-MaterialityRows 'sa' 8); managedDisks = (New-MaterialityRows 'mdisk' 8) }
            security      = [ordered]@{ keyVaults = (New-MaterialityRows 'kv' 8) }
            databases     = [ordered]@{ sqlServers = (New-MaterialityRows 'sql' 8) }
            web           = [ordered]@{ sites = (New-MaterialityRows 'site' 8) }
            containers    = [ordered]@{ aks = (New-MaterialityRows 'aks' 8) }
            management    = [ordered]@{ logAnalyticsWorkspaces = (New-MaterialityRows 'law' 8) }
            governance    = [ordered]@{
                managementGroups = @(
                    [pscustomobject]@{ name = 'mg-root'; displayName = 'Root'; parent = $null }
                    [pscustomobject]@{ name = 'mg-child'; displayName = 'Child'; parent = 'mg-root' }
                )
                roleAssignments  = (New-MaterialityRows 'ra' 8)
            }
            identity      = [ordered]@{ users = (New-MaterialityRows 'user' 8) }
            devops        = [ordered]@{ pipelines = (New-MaterialityRows 'pipe' 8) }
            hybrid        = [ordered]@{ arcServers = (New-MaterialityRows 'arc' 8) }
            integration   = [ordered]@{ logicApps = (New-MaterialityRows 'la' 8) }
            iot           = [ordered]@{ hubs = (New-MaterialityRows 'iothub' 8) }
            migration     = [ordered]@{ projects = (New-MaterialityRows 'migproj' 8) }
            analytics     = [ordered]@{ workspaces = (New-MaterialityRows 'analyticsws' 8) }
            ai            = [ordered]@{ services = (New-MaterialityRows 'aisvc' 8) }
        }

        $script:OutDir = Join-Path -Path $script:Root -ChildPath 'tests' -AdditionalChildPath 'test-output', 'view-mode-materiality'
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
        New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

        $script:ReportPath = Export-React -Findings $script:BigScored -Collect $script:BigCollect -OutputPath $script:OutDir
        $script:Html = Get-Content $script:ReportPath -Raw

        # Extract the embedded __SCOUT_DATA__ payload VERBATIM (no ConvertFrom-Json/ConvertTo-Json
        # round trip -- that risks subtly reshaping ordering/types) and hand that exact JSON text
        # straight to the Node checker, which boots the raw template against it.
        $s = $script:Html.IndexOf('window.__SCOUT_DATA__ = ') + 'window.__SCOUT_DATA__ = '.Length
        $e = $script:Html.IndexOf(';</script>', $s)
        $script:FixturePath = Join-Path -Path $script:OutDir -ChildPath 'materiality-payload.json'
        Set-Content -Path $script:FixturePath -Value $script:Html.Substring($s, $e - $s) -Encoding utf8NoBOM -NoNewline
    }

    AfterAll {
        if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'template and checker script both exist' {
        Test-Path $script:TemplatePath | Should -BeTrue
        Test-Path $script:Checker | Should -BeTrue
    }

    It 'the fixture actually exceeds every depth-cons/depth-data cap the template defines (else this test would not exercise AB#6936 at all)' {
        @($script:BigFindings).Count | Should -BeGreaterThan 60
        @($script:BigFindings | Where-Object Status -eq 'Fail').Count | Should -BeGreaterOrEqual 60
        $netFinding = $script:BigFindings | Where-Object { $_.Area -eq 'Networking' -and $_.Status -eq 'Fail' } | Select-Object -First 1
        @($netFinding.Evidence).Count | Should -BeGreaterThan 12
        @($script:BigCollect.PSObject.Properties | Where-Object Name -ne '_meta').Count | Should -BeGreaterThan 10
        @($script:BigCollect.compute.virtualMachines).Count | Should -BeGreaterThan 50
    }

    It 'produces a materially different render for Executive vs Consultant vs Data in every one of the 6 nav sections (ov/inv/as/dgm/data/road)' {
        if (-not $script:NodeAvailable) {
            Set-ItResult -Skipped -Because 'node is not on PATH'
            return
        }
        $output = & node $script:Checker $script:TemplatePath $script:FixturePath 2>&1
        $output | Out-String | Write-Host
        $LASTEXITCODE | Should -Be 0 -Because 'every nav section should render materially different visible content across Executive/Consultant/Data -- see the printed per-section char/node counts above for exactly which section and mode pair failed'
    }
}
