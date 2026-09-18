#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/report/Import-ScoutReportInventory.ps1"
    . "$script:Root/src/report/renderers/Export-React.ps1"
}

Describe 'Complete processed inventory reaches the standard report' {
    It 'retains heterogeneous child rows, empty datasets and distinct identities without changing assessment inputs' {
        $cachePath = Join-Path $TestDrive 'ReportCache'
        $null = New-Item -ItemType Directory -Path $cachePath
        $rows = @(1..401 | ForEach-Object { [pscustomobject]@{ ID = 'resource-a'; Child = $_ } })
        $rows += [pscustomobject]@{ ID = 'resource-b'; LastRowOnly = 'retained' }
        @{ VirtualMachine = $rows; EmptyDataset = @(); CounterOnly = @(@{'Resource U'=1},@{'Resource U'=1}) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $cachePath 'Compute.json')
        @{ Users = @([pscustomobject]@{ id = 'user-fixture'; displayName = 'Fixture user' }) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $cachePath 'Identity.json')
        $collect = [pscustomobject]@{ compute = [pscustomobject]@{ virtualMachines = @([pscustomobject]@{ id = 'canonical'; name = 'Canonical VM' }) } }
        $collect = Import-ScoutReportInventory -Collect $collect -ReportCachePath $cachePath
        $collect.compute.virtualMachines.Count | Should -Be 1
        $collect._reportInventory['collected.compute.VirtualMachine'].count | Should -Be 402
        $collect._reportInventory['collected.compute.VirtualMachine'].resourceCount | Should -Be 2
        $collect._reportInventory['collected.compute.EmptyDataset'].count | Should -Be 0
        $collect._reportInventory['collected.compute.CounterOnly'].resourceCount | Should -BeNullOrEmpty
        $file = Export-React -Collect $collect -Findings ([pscustomobject]@{ Findings = @() }) -OutputPath (Join-Path $TestDrive 'report')
        $html = Get-Content -LiteralPath $file -Raw
        $match = [regex]::Match($html, '(?s)window\.__SCOUT_DATA__\s*=\s*(\{.*?\});\s*</script>')
        $data = $match.Groups[1].Value | ConvertFrom-Json -Depth 100
        $data.inventory.'collected.compute.VirtualMachine'.rows.Count | Should -Be 402
        $data.inventory.'collected.compute.VirtualMachine'.rows[-1].LastRowOnly | Should -Be 'retained'
        $data.inventory.'collected.compute.VirtualMachine'.truncated | Should -BeNullOrEmpty
        $data.ran.entra | Should -BeTrue
        # Persist/reload must preserve the same contract used by offline report regeneration.
        $roundTrip = $collect | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $second = Export-React -Collect $roundTrip -Findings ([pscustomobject]@{ Findings = @() }) -OutputPath (Join-Path $TestDrive 'reloaded')
        (Get-Content -LiteralPath $second -Raw) | Should -Match 'LastRowOnly'
    }

    It 'preserves more than 300 normalized inventory rows without a processed cache' {
        $collect = [pscustomobject]@{ monitor = [pscustomobject]@{ logs = @(1..405 | ForEach-Object { [pscustomobject]@{ name = "log-$_" } }) } }
        $file = Export-React -Collect $collect -Findings ([pscustomobject]@{ Findings = @() }) -OutputPath (Join-Path $TestDrive 'many')
        $html = Get-Content -LiteralPath $file -Raw
        $match = [regex]::Match($html, '(?s)window\.__SCOUT_DATA__\s*=\s*(\{.*?\});\s*</script>')
        $data = $match.Groups[1].Value | ConvertFrom-Json -Depth 100
        $data.inventory.'monitor.logs'.rows.Count | Should -Be 405
        $data.ran.inventory | Should -BeTrue
    }

    It 'fails visibly on corrupt processed evidence instead of silently dropping it' {
        $path = Join-Path $TestDrive 'bad-cache'
        $null = New-Item -ItemType Directory -Path $path
        '{broken' | Set-Content (Join-Path $path 'Compute.json')
        { Import-ScoutReportInventory -Collect ([pscustomobject]@{}) -ReportCachePath $path } | Should -Throw
    }

    It 'renders the reference experience from synthetic sparse and multi-region evidence' {
        $output = & node (Join-Path $PSScriptRoot 'report-parity-checker.mjs') (Join-Path $script:Root 'src/report/templates/report-react.html.template') 2>&1
        $output | Out-String | Write-Host
        $LASTEXITCODE | Should -Be 0
    }
}
