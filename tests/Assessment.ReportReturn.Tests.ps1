#Requires -Version 7.0
#Requires -Modules Pester

<#
    Regression test for the renderer return-value leak (found in live E2E, AB#5053
    wiring): Export-React RETURNS the path it writes, and the reporter loop in
    The internal assessment core must swallow that (| Out-Null) so its only
    output is the single run-folder path. Without the guard, a run whose
    -OutputFormat includes 'React' returns @(reportPath, runPath), which breaks
    every caller that expects one path (notably Invoke-ScoutPipeline).

    Runs the REAL orchestrator via -FromCollect against the canonical fixture, so
    no Azure connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object {
        $_.ModuleBase -eq $script:root
    } | Select-Object -First 1
    $script:fixture = "$script:root/tests/datadump/sample-collect.json"
    $script:outRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AZSC_ReportReturn_" + [System.IO.Path]::GetRandomFileName())
}

AfterAll {
    if ($script:outRoot -and (Test-Path $script:outRoot)) {
        Remove-Item $script:outRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Assessment core return value with the React renderer' {
    It 'returns a single run-folder path (string), not an array, when React is included' {
        $result = & $script:Module {
            param($fixture, $outRoot)
            Invoke-ScoutAssessmentCore -Assessment 'CAF: Azure Landing Zone' -FromCollect $fixture -OutputFormat React, Json -OutputPath $outRoot
        } $script:fixture $script:outRoot

        @($result).Count | Should -Be 1
        $result          | Should -BeOfType [string]
        Test-Path $result | Should -BeTrue
        Test-Path (Join-Path $result 'report-react.html') | Should -BeTrue
    }

    It 'produces a self-contained React report with no external CDN references' {
        $run  = & $script:Module {
            param($fixture, $outRoot)
            Invoke-ScoutAssessmentCore -Assessment 'CAF: Azure Landing Zone' -FromCollect $fixture -OutputFormat React -OutputPath $outRoot
        } $script:fixture $script:outRoot
        $html = Join-Path $run 'report-react.html'

        Test-Path $html | Should -BeTrue
        (Select-String -Path $html -Pattern '(src|href)="https?://' -Quiet) | Should -Not -BeTrue
        (Select-String -Path $html -Pattern '__SCOUT_DATA__' -Quiet)        | Should -BeTrue
    }

    It 'accumulates cross-run drift history across runs under the output root' {
        # Two runs into the same output root -> the shared history log gains a
        # second record, proving the drift wiring runs inside the orchestrator.
        & $script:Module {
            param($fixture, $outRoot)
            Invoke-ScoutAssessmentCore -Assessment 'CAF: Azure Landing Zone' -FromCollect $fixture -OutputFormat React -OutputPath $outRoot
        } $script:fixture $script:outRoot | Out-Null
        $histFile = Join-Path $script:outRoot '.scout-history/findings-history.json'
        Test-Path $histFile | Should -BeTrue
        $records = Get-Content $histFile -Raw | ConvertFrom-Json
        @($records).Count | Should -BeGreaterThan 1
    }
}
