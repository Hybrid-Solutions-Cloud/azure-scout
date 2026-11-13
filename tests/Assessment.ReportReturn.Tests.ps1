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
    $script:outRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("AZSC_ReportReturn_" + [System.IO.Path]::GetRandomFileName())
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
        Test-Path (Join-Path -Path $result -ChildPath 'report-react.html') | Should -BeTrue
    }

    It 'produces a self-contained React report with no external CDN references' {
        $run  = & $script:Module {
            param($fixture, $outRoot)
            Invoke-ScoutAssessmentCore -Assessment 'CAF: Azure Landing Zone' -FromCollect $fixture -OutputFormat React -OutputPath $outRoot
        } $script:fixture $script:outRoot
        $html = Join-Path -Path $run -ChildPath 'report-react.html'

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
        $histFile = Join-Path -Path $script:outRoot -ChildPath '.scout-history/findings-history.json'
        Test-Path $histFile | Should -BeTrue
        $records = Get-Content $histFile -Raw | ConvertFrom-Json
        @($records).Count | Should -BeGreaterThan 1
    }
}

Describe 'Inventory-only live renderers' {
    It 'renders React and JsonEvidence from memory without rules or remote fallback' {
        $inventoryRoot = Join-Path $script:outRoot 'inventory-only'
        $result = & $script:Module {
            param($outRoot)

            Mock Search-AzGraph { throw 'Inventory-only rendering attempted Resource Graph.' }
            Mock Get-ScoutDefenderPlanSweep { throw 'Inventory-only rendering attempted Defender ARM.' }
            Mock Get-ScoutExternalIdentitiesPolicy { throw 'Inventory-only rendering attempted Graph.' }
            Mock Invoke-Assessment { throw 'Inventory-only rendering attempted assessment rules.' }

            $raw = [pscustomobject]@{
                Resources = @([pscustomobject]@{
                    id = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1'
                    name = 'vm1'; type = 'microsoft.compute/virtualmachines'; subscriptionId = '11111111-1111-1111-1111-111111111111'
                    resourceGroup = 'rg'; location = 'eastus'; properties = [pscustomobject]@{}
                })
                ResourceContainers = @([pscustomobject]@{
                    id = '11111111-1111-1111-1111-111111111111'; name = 'Subscription One'
                    type = 'microsoft.resources/subscriptions'; subscriptionId = '11111111-1111-1111-1111-111111111111'
                    properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null
                })
                EntraResources = @([pscustomobject]@{ id = 'user-1'; name = 'Example User'; TYPE = 'entra/users' })
            }

            $run = Invoke-ScoutAssessmentCore -InventoryOnly -FromInventory $raw -Scope All `
                -OutputFormat React,JsonEvidence -OutputPath $outRoot

            Should -Invoke Search-AzGraph -Exactly 0
            Should -Invoke Get-ScoutDefenderPlanSweep -Exactly 0
            Should -Invoke Get-ScoutExternalIdentitiesPolicy -Exactly 0
            Should -Invoke Invoke-Assessment -Exactly 0
            return $run
        } $inventoryRoot

        @($result).Count | Should -Be 1
        Test-Path (Join-Path $result 'report-react.html') | Should -BeTrue
        Test-Path (Join-Path $result 'evidence.json') | Should -BeTrue

        $evidence = Get-Content (Join-Path $result 'evidence.json') -Raw | ConvertFrom-Json -Depth 100
        @($evidence.entraResources).Count | Should -Be 1
        $evidence.PSObject.Properties.Name | Should -Not -Contain 'Findings'

        $html = Get-Content (Join-Path $result 'report-react.html') -Raw
        $html | Should -Match '"entra"\s*:\s*true'
        $html | Should -Match '"assessments"\s*:\s*false'
    }

    It 'carries Advisor recommendations and service retirements the inventory pass already collected' {
        # Field scan 2026-10-05: 211 Advisor recommendations and 2 retirement notices were
        # collected and the inventory-only React report contained none of them, because that
        # path ran no ingestors. Both are in memory already, so no Azure call is needed.
        $inventoryRoot = Join-Path $script:outRoot 'inventory-only-advisor'
        $result = & $script:Module {
            param($outRoot)

            Mock Search-AzGraph { throw 'Inventory-only rendering attempted Resource Graph.' }
            Mock Get-AzAdvisorRecommendation { throw 'Inventory-only rendering attempted the Advisor API.' }
            Mock Get-ScoutDefenderPlanSweep { throw 'Inventory-only rendering attempted Defender ARM.' }
            Mock Get-ScoutExternalIdentitiesPolicy { throw 'Inventory-only rendering attempted Graph.' }
            Mock Invoke-Assessment { throw 'Inventory-only rendering attempted assessment rules.' }

            $subscription = '11111111-1111-1111-1111-111111111111'
            $raw = [pscustomobject]@{
                Resources = @([pscustomobject]@{
                    id = "/subscriptions/$subscription/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1"
                    name = 'vm1'; type = 'microsoft.compute/virtualmachines'; subscriptionId = $subscription
                    resourceGroup = 'rg'; location = 'eastus'; properties = [pscustomobject]@{}
                })
                ResourceContainers = @([pscustomobject]@{
                    id = $subscription; name = 'Subscription One'
                    type = 'microsoft.resources/subscriptions'; subscriptionId = $subscription
                    properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null
                })
                EntraResources = @()
                Advisories = @(
                    [pscustomobject]@{ subscriptionId = $subscription; properties = [pscustomobject]@{
                        category = 'Cost'; impact = 'High'; impactedField = 'Microsoft.Compute/virtualMachines'; impactedValue = 'vm1'
                        shortDescription = [pscustomobject]@{ problem = 'Right-size or shut down underutilized virtual machines'; solution = 'Resize vm1' } } }
                    [pscustomobject]@{ subscriptionId = $subscription; properties = [pscustomobject]@{
                        category = 'Security'; impact = 'Medium'; impactedField = 'Microsoft.Compute/virtualMachines'; impactedValue = 'vm1'
                        shortDescription = [pscustomobject]@{ problem = 'Enable disk encryption'; solution = 'Encrypt' } } }
                )
                Retirements = @([pscustomobject]@{ ServiceName = 'Example retiring service'; RetirementDate = '2027-03-31'; subscriptionId = $subscription })
            }

            Invoke-ScoutAssessmentCore -InventoryOnly -FromInventory $raw -Scope All -OutputFormat React,JsonEvidence -OutputPath $outRoot
        } $inventoryRoot

        $evidence = Get-Content (Join-Path $result 'evidence.json') -Raw | ConvertFrom-Json -Depth 100
        @($evidence.advisor).Count | Should -Be 2
        @($evidence.advisor | Where-Object Category -eq 'Cost')[0].ShortDescriptionProblem | Should -Match 'Right-size'
        @($evidence.serviceRetirements).Count | Should -Be 1

        $html = Get-Content (Join-Path $result 'report-react.html') -Raw
        $html | Should -Match 'Right-size or shut down underutilized virtual machines'
        $html | Should -Match 'Example retiring service'
    }
}
