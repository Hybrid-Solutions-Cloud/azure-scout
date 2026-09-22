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
    VitePress docs site) and the banked corpus at D:\azure-scout-corpus.
    Corpus cases are registered during discovery only when their inputs are
    present, so clean GitHub runners do not report unavailable local corpus
    data as skipped product coverage. Deterministic report and diagram tests
    remain mandatory on every runner.
#>

$CorpusRoot = 'D:\azure-scout-corpus'
$DiagramCorpusCases = @()
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $CorpusRoot)) {
    $RunDirectories = @(
        Get-ChildItem -LiteralPath $CorpusRoot -Directory -Filter '*-run*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
    )

    foreach ($CorpusCase in @(
            @{ Alias = 'hcs'; Name = 'hcs (small estate)' }
            @{ Alias = 'tppoc'; Name = 'tppoc (richest estate - 9 subs, 18 MGs)' }
        )) {
        $CollectPath = $null
        foreach ($RunDirectory in $RunDirectories) {
            $AliasDirectory = Join-Path -Path $RunDirectory.FullName -ChildPath $CorpusCase.Alias
            if (-not (Test-Path -LiteralPath $AliasDirectory)) { continue }
            $CollectPath = Get-ChildItem -LiteralPath $AliasDirectory -Recurse -Filter 'collect.json' -File -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
            if ($CollectPath) { break }
        }

        if ($CollectPath) {
            $DiagramCorpusCases += @{
                Alias       = $CorpusCase.Alias
                Name        = $CorpusCase.Name
                CollectPath = $CollectPath
            }
        }
    }
}

Describe 'React report diagram kernel — no collisions on a real banked corpus' {

    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:TemplatePath = Join-Path -Path $script:RepoRoot -ChildPath 'src' -AdditionalChildPath 'report', 'templates', 'report-react.html.template'
        function Test-ScoutDiagramOverlap {
            param([string] $Alias, [string] $CollectPath)

            $fixturePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "scout-react-fixture-$Alias.json"
            $fixtureBuilder = Join-Path -Path $script:RepoRoot -ChildPath 'tests' -AdditionalChildPath 'diagram-fixture-build.mjs'
            $checker = Join-Path -Path $script:RepoRoot -ChildPath 'tests' -AdditionalChildPath 'diagram-overlap-checker.mjs'

            & node $fixtureBuilder $CollectPath | Out-File -FilePath $fixturePath -Encoding utf8NoBOM
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

    It 'produces zero overlap violations for <Name>' -ForEach $DiagramCorpusCases {
        Test-ScoutDiagramOverlap -Alias $Alias -CollectPath $CollectPath
    }
}
