#Requires -Version 7.0
#Requires -Modules Pester

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:ContractFiles = @(
        'README.md'
        'docs/index.md'
        'docs/guide/usage.md'
        'docs/guide/parameters.md'
        'docs/guide/overview.md'
        'docs/guide/output.md'
        'docs/assessment/configuration.md'
        'docs/assessment/assessment.md'
        'docs/automation-guide/github-actions.md'
        'docs/automation-guide/automation.md'
    )
    $script:ContractText = @{}
    foreach ($relativePath in $script:ContractFiles) {
        $path = Join-Path $script:Root $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Documentation contract file is missing: $relativePath"
        }
        $script:ContractText[$relativePath] = Get-Content -LiteralPath $path -Raw
    }
    $script:CombinedContractText = ($script:ContractText.Values -join "`n")
    $script:HeldFormats = @(
        'Excel', 'Markdown', 'AsciiDoc', 'PowerBI', 'Html', 'Pptx', 'Pdf', 'Word',
        'EChartsDashboard', 'GovernanceReport'
    )
}

Describe 'Documentation — global output-format contract' {
    It 'names React, Json, and JsonEvidence as the live formats' {
        foreach ($format in @('React', 'Json', 'JsonEvidence')) {
            $script:CombinedContractText | Should -Match "(?i)\b$format\b"
        }
    }

    It 'documents All as selecting exactly the three live formats' {
        $parameters = $script:ContractText['docs/guide/parameters.md']
        $parameters | Should -Match '(?i)`React`, `Json`, `JsonEvidence`, or `All`'
        $parameters | Should -Match '(?i)`All`[^\r\n]*(selects all three|selects the three live formats)'
    }

    It 'documents every legacy renderer as held, including former inventory renderers' {
        $usage = $script:ContractText['docs/guide/usage.md']
        $usage | Should -Match '(?is)Legacy values.{0,600}on hold'
        foreach ($format in $script:HeldFormats) {
            $usage | Should -Match "(?i)\b$format\b"
        }
    }

    It 'contains no runnable example that selects a held renderer' {
        $heldAlternation = ($script:HeldFormats | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $pattern = "(?im)^\s*(?:Invoke-AzureScout|Invoke-ScoutPipeline)\b[^\r\n]*-OutputFormat\s+(?:$heldAlternation)\b"

        foreach ($relativePath in $script:ContractFiles) {
            $script:ContractText[$relativePath] | Should -Not -Match $pattern -Because "$relativePath must not advertise a held renderer as runnable"
        }
    }

    It 'does not restore an inventory-only exception to the renderer hold' {
        $forbiddenClaims = @(
            'Inventory runs still write',
            'inventory-mode formats.+different pipeline.+unaffected',
            'inventory run writes.+unaffected by the reporting hold',
            'generates both Excel and JSON reports'
        )
        foreach ($claim in $forbiddenClaims) {
            $script:CombinedContractText | Should -Not -Match "(?is)$claim"
        }
    }

    It 'does not describe Excel as a current README output' {
        $readme = $script:ContractText['README.md']
        $readme | Should -Not -Match '(?i)ArtifactType:\s*Excel'
        $readme | Should -Not -Match '(?im)^\s*-\s*Excel and JSON output\s*$'
    }
}
