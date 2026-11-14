#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# An inventory-only run evaluates no CAF/WAF checks. The Overview page used to lead with
# "0 CAF/WAF checks were evaluated" and a row of zero tiles, hiding what the run collected.
Describe 'React report Overview for an inventory-only run' {
    BeforeAll {
        $templatePath = Join-Path $PSScriptRoot '..' 'src' 'report' 'templates' 'report-react.html.template'
        $script:Template = Get-Content -LiteralPath $templatePath -Raw
        $match = [regex]::Match($script:Template, 'function pageOverview\(\)\{[\s\S]*?\r?\n\}\r?\n')
        $script:Overview = $match.Value
    }

    It 'has an Overview page function to inspect' {
        $script:Overview | Should -Not -BeNullOrEmpty
    }

    It 'branches on a run with no assessments before the assessment lede is built' {
        $branchIndex = $script:Overview.IndexOf('if(assessments.length===0){')
        $ledeIndex = $script:Overview.IndexOf('CAF/WAF checks were evaluated against this tenant')
        $branchIndex | Should -BeGreaterThan -1
        $ledeIndex | Should -BeGreaterThan $branchIndex
    }

    It 'leads the inventory overview with what was collected and says no assessment ran' {
        $script:Overview | Should -Match 'This run inventoried '
        $script:Overview | Should -Match 'No CAF/WAF assessment was selected for this run'
    }

    It 'shows management groups, Advisor, policy assignments and Entra objects as tiles' {
        foreach ($label in 'Management groups', 'Advisor recommendations', 'Policy assignments', 'Entra objects') {
            $script:Overview | Should -Match ([regex]::Escape("kpiLink('$label'"))
        }
    }

    It 'does not claim zero checks in the Markdown export of an inventory-only run' {
        $script:Template | Should -Match ([regex]::Escape("if(assessments.length===0) md.push('\n**Inventory run**"))
    }
}
