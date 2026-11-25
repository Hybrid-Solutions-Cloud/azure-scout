#Requires -Version 7.0
#Requires -Modules Pester

<#
    The collector counts on the docs site and in the README were hand-maintained and drifted (the
    home page said 245 and the README 240 when the catalogue had 342). These tests hold every
    stated count to the manifests/collectors tree (AB#9300).
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Counts = @{}
    foreach ($dir in Get-ChildItem "$script:RepoRoot/manifests/collectors" -Directory) {
        $script:Counts[$dir.Name] = @(Get-ChildItem $dir.FullName -Filter '*.psd1' -File).Count
    }
    $script:Total = ($script:Counts.Values | Measure-Object -Sum).Sum
}

Describe 'Collector counts in the docs match the catalogue' {
    It 'README category table and total' {
        $text = Get-Content "$script:RepoRoot/README.md" -Raw
        foreach ($category in $script:Counts.Keys) {
            $text | Should -Match ('(?m)^\| `{0}` \|.*\| {1} \|\s*$' -f $category, $script:Counts[$category]) -Because "README row for $category"
        }
        $text | Should -Match ("18 categories, {0} collector definitions in total" -f $script:Total)
    }

    It 'Category Reference table and total' {
        $text = Get-Content "$script:RepoRoot/docs/reference/category-reference.md" -Raw
        foreach ($category in $script:Counts.Keys) {
            $text | Should -Match ('(?m)^\| .* \| `{0}` \| `manifests/collectors/{0}/` \| {1} \|\s*$' -f $category, $script:Counts[$category]) -Because "Category Reference row for $category"
        }
        $text | Should -Match ("\*\*{0} declarative collector definitions" -f $script:Total)
    }

    It 'home page and reference index' {
        (Get-Content "$script:RepoRoot/docs/index.md" -Raw) | Should -Match ("title: {0} collectors, 18 categories" -f $script:Total)
        (Get-Content "$script:RepoRoot/docs/reference/index.md" -Raw) | Should -Match ("All \*\*{0} collector definitions\*\*" -f $script:Total)
    }

    It 'testing guide' {
        $text = Get-Content "$script:RepoRoot/docs/project/testing.md" -Raw
        $text | Should -Match ("all {0} collectors" -f $script:Total)
        $text | Should -Match ("All {0} collectors are now tested" -f $script:Total)
    }
}
