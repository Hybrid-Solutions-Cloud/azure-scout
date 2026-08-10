#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Export-PowerBi (.pbit generation) AB#5046' {
    BeforeAll {
        . "$PSScriptRoot/../src/report/renderers/Export-PowerBi.ps1"
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $script:Findings = [pscustomobject]@{
            Areas      = @(
                [pscustomobject]@{ Framework = 'CAF'; Area = 'Governance'; Score = 72 }
                [pscustomobject]@{ Framework = 'WAF'; Area = 'Security';   Score = 64 }
            )
            Frameworks = @([pscustomobject]@{ Framework = 'CAF'; Score = 70 })
            Gaps       = @([pscustomobject]@{ Framework = 'CAF'; Area = 'Governance'; Id = 'CAF-GOV-01'; Severity = 'High'; Title = 'x' })
            Findings   = @(
                [pscustomobject]@{ Framework = 'CAF'; Area = 'Governance'; Id = 'CAF-GOV-01'; Severity = 'High'; Status = 'Fail'; EvidenceCount = 2; Title = 'x'; Remediation = 'y'; Manual = $false }
            )
        }
        $script:Out = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("pbit-pester-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Export-PowerBi -Findings $script:Findings -Collect ([pscustomobject]@{}) -OutputPath $script:Out | Out-Null
        $script:PbiDir = Join-Path -Path $script:Out -ChildPath 'powerbi'
    }
    AfterAll {
        if ($script:Out -and (Test-Path $script:Out)) { Remove-Item $script:Out -Recurse -Force }
    }

    It 'emits the four star-schema CSVs' {
        foreach ($csv in 'fact_area_scores', 'fact_framework', 'dim_gaps', 'fact_findings') {
            Join-Path -Path $script:PbiDir -ChildPath "$csv.csv" | Should -Exist
        }
    }

    It 'generates report.pbit' {
        Join-Path -Path $script:PbiDir -ChildPath 'report.pbit' | Should -Exist
    }

    It 'produces a report.pbit containing all required OPC parts' {
        $pbit = Join-Path -Path $script:PbiDir -ChildPath 'report.pbit'
        $zip = [System.IO.Compression.ZipFile]::OpenRead($pbit)
        try { $names = @($zip.Entries.FullName) } finally { $zip.Dispose() }
        foreach ($part in '[Content_Types].xml', 'Version', 'DataModelSchema', 'Mashup', 'Report/Layout') {
            $names | Should -Contain $part
        }
    }

    It 'writes a README describing the star schema' {
        Join-Path -Path $script:PbiDir -ChildPath 'README.txt' | Should -Exist
        (Get-Content (Join-Path -Path $script:PbiDir -ChildPath 'README.txt') -Raw) | Should -Match 'star schema'
    }

    It 'neutralizes spreadsheet-formula prefixes in CSV fields' {
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("pbit-csv-pester-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $findings = [pscustomobject]@{
            GeneratedOn = (Get-Date).ToString('o'); Areas = @(); Frameworks = @(); Gaps = @()
            Findings = @([pscustomobject]@{
                Framework='CAF'; Area='Governance'; Id='CSV-1'; Severity='High'; Status='Fail'; EvidenceCount=1
                Title='=HYPERLINK("https://invalid")'; Remediation='@SUM(1+1)'; Manual=$false
            })
        }
        try {
            Export-PowerBi -Findings $findings -Collect ([pscustomobject]@{}) -OutputPath $dir | Out-Null
            $row = Import-Csv (Join-Path $dir 'powerbi/fact_findings.csv')
            $row.Title | Should -Be '''=HYPERLINK("https://invalid")'
            $row.Remediation | Should -Be '''@SUM(1+1)'
        }
        finally {
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Export-PowerBi -- $null -Findings crash class (StrictMode sweep)' {
    # $Findings.Areas/.Frameworks/.Gaps/.Findings previously dotted directly into
    # a possibly-$null $Findings, throwing PropertyNotFoundException under
    # Set-StrictMode -Version Latest instead of degrading to empty CSVs like
    # every other renderer in this folder.
    BeforeAll {
        . "$PSScriptRoot/../src/report/renderers/Export-PowerBi.ps1"
    }

    It 'does not throw and still emits empty star-schema CSVs when -Findings is $null' {
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("pbit-null-pester-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            Export-PowerBi -Findings $null -Collect ([pscustomobject]@{}) -OutputPath $dir
            $pbiDir = Join-Path -Path $dir -ChildPath 'powerbi'
            foreach ($csv in 'fact_area_scores', 'fact_framework', 'dim_gaps', 'fact_findings') {
                Join-Path -Path $pbiDir -ChildPath "$csv.csv" | Should -Exist
            }
        }
        finally {
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
