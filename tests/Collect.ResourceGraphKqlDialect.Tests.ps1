#Requires -Version 7.0
#Requires -Modules Pester

<#
    Resource Graph runs a subset of Kusto. Two things in the typed-query pack passed every offline
    test (the tests emulate query answers rather than running them) and were rejected by Azure as
    parse errors when run live (AB#9300, 2026-11-25):
      - `mv-apply` is not supported -- use mv-expand + summarize;
      - `count` is a reserved word, so `x.count` does not parse -- use x['count'].
    This test reads every KQL here-string in Invoke-Collect.ps1 and fails on either.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $text = Get-Content (Join-Path $script:Root 'src/collect/Invoke-Collect.ps1') -Raw
    $script:Queries = @([regex]::Matches($text, "(?s)\r?\n\s+([A-Za-z][A-Za-z0-9]*) = @'\r?\n(.*?)\r?\n'@") | ForEach-Object {
            [pscustomobject]@{
                Key   = $_.Groups[1].Value
                Query = (($_.Groups[2].Value -split "\r?\n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
            }
        } | Where-Object { $_.Query -match '(?m)^\s*(resources|resourcecontainers|networkresources|securityresources|advisorresources|desktopvirtualizationresources|recoveryservicesresources|patch\w+resources|\w+resources)\b' })
}

Describe 'Typed Resource Graph queries use only the Resource Graph dialect' {
    It 'finds the query pack' {
        $script:Queries.Count | Should -BeGreaterThan 50
    }
    It 'no query uses mv-apply' {
        $bad = @($script:Queries | Where-Object { $_.Query -match '\bmv-apply\b' } | ForEach-Object Key)
        $bad -join ', ' | Should -BeNullOrEmpty -Because 'Resource Graph rejects mv-apply; use mv-expand and summarize'
    }
    It 'no query reads a property named count with dot syntax' {
        $bad = @($script:Queries | Where-Object { $_.Query -match '[A-Za-z_\]]\.count\b' } | ForEach-Object Key)
        $bad -join ', ' | Should -BeNullOrEmpty -Because "count is a reserved word in Kusto; use ['count']"
    }
}
