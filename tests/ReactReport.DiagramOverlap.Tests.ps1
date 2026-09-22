#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Collision-free diagram regression test for report-react.html.template (AB#6933).

.DESCRIPTION
    Ports the diagram-library.html mockup's overlap checker into the repo as a
    real, running test. The template exposes its diagram layout kernel on
    `window.__SCOUT_DIAGRAM_KERNEL__` purely for this test to reach; the
    checker (tests/diagram-overlap-checker.mjs) runs the kernel in a minimal
    Node vm sandbox against a payload built from a real banked-corpus
    collect.json (tests/diagram-fixture-build.mjs), then regex-parses the
    generated SVG and asserts:
      - no two node rects overlap
      - no node rect collapses to zero/negative size (text would not fit)
      - no edge polyline segment crosses a node rect it does not terminate on

    Requires `node` on PATH (this repo already depends on it for the
    VitePress docs site) and the banked corpus at D:\azure-scout-corpus —
    skipped, not failed, when either is unavailable so this runs clean on a
    machine without the corpus while still gating the template on CI/dev
    boxes that have it. Everything the It blocks need lives inside BeforeAll:
    Pester 6 runs discovery and execution as separate passes, so top-level
    script-scope state set outside a Describe block is not guaranteed to
    survive into the execution pass.
#>

Describe 'React report diagram kernel — no collisions on a real banked corpus' {

    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:TemplatePath = Join-Path $script:RepoRoot 'src' 'report' 'templates' 'report-react.html.template'
        $script:CorpusRoot = 'D:\azure-scout-corpus'
        $script:NodeAvailable = [bool](Get-Command node -ErrorAction SilentlyContinue)

        function Find-ScoutCorpusCollect {
            param([string] $Alias)
            if (-not (Test-Path $script:CorpusRoot)) { return $null }
            $runDirs = Get-ChildItem -Path $script:CorpusRoot -Directory -Filter '*-run*' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending
            foreach ($run in $runDirs) {
                $aliasDir = Join-Path $run.FullName $Alias
                if (-not (Test-Path $aliasDir)) { continue }
                $collect = Get-ChildItem -Path $aliasDir -Recurse -Filter 'collect.json' -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($collect) { return $collect.FullName }
            }
            return $null
        }

        function Test-ScoutDiagramOverlap {
            param([string] $Alias)

            if (-not $script:NodeAvailable) {
                Set-ItResult -Skipped -Because 'node is not on PATH'
                return
            }
            $collectPath = Find-ScoutCorpusCollect -Alias $Alias
            if (-not $collectPath) {
                Set-ItResult -Skipped -Because "no banked-corpus collect.json found for '$Alias' under $script:CorpusRoot"
                return
            }

            $fixturePath = Join-Path ([System.IO.Path]::GetTempPath()) "scout-react-fixture-$Alias.json"
            $fixtureBuilder = Join-Path $script:RepoRoot 'tests' 'diagram-fixture-build.mjs'
            $checker = Join-Path $script:RepoRoot 'tests' 'diagram-overlap-checker.mjs'

            & node $fixtureBuilder $collectPath | Out-File -FilePath $fixturePath -Encoding utf8NoBOM
            $LASTEXITCODE | Should -Be 0 -Because 'the fixture builder must succeed against a real collect.json'

            $output = & node $checker $script:TemplatePath $fixturePath 2>&1
            $output | Out-String | Write-Host
            $LASTEXITCODE | Should -Be 0 -Because ('the diagram kernel must not overlap nodes/edges for ' + $Alias)

            Remove-Item $fixturePath -ErrorAction SilentlyContinue
        }
    }

    It 'template exists' {
        Test-Path $script:TemplatePath | Should -BeTrue
    }

    It 'produces zero overlap violations for hcs (small estate)' {
        Test-ScoutDiagramOverlap -Alias 'hcs'
    }

    It 'produces zero overlap violations for tppoc (richest estate — 9 subs, 18 MGs)' {
        Test-ScoutDiagramOverlap -Alias 'tppoc'
    }
}
