#Requires -Version 7.0
#Requires -Modules Pester

<#
    Issues #102 and #103 -- regression tests for the two defects found when release 3.18.20 was first
    run in all three modes (inventory only, assessment only, both) on one tenant.

    #102  An assessment-only run read Advisor through a per-subscription cmdlet fallback that returned a
          narrower set than the Resource Graph query a combined run uses (147 rows vs 647, no Security,
          no Performance, a subscription NAME where the other path had the ID) and called the result
          complete. Nine Advisor-dependent rules passed that the combined run failed.
    #103  An assessment-only run ignored -RunName and the standard report root and wrote to ./output
          relative to the current directory.

    The wider "does every dataset match between the modes" check is tests/Collect.ModeParity.Tests.ps1.
    No Azure connection; everything is written under $TestDrive.
#>

BeforeAll {
    $env:AZURESCOUT_SKIP_UPDATE_CHECK = '1'
    $script:Root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:Root 'AzureScout.psd1') -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:Root } | Select-Object -First 1
    Import-Module powershell-yaml
}

Describe 'Issue #102 -- Advisor in an assessment-only run' {

    BeforeAll {
        # Drives Invoke-Collect's own raw pass with a stand-in Get-ScoutRawInventory, so what is asserted
        # is what Invoke-Collect ASKS the pass for and what it does with the answer.
        $script:InvokeCollectWith = {
            param([object[]] $Advisories, [object[]] $Health, [bool] $IncludeAdvisories)
            $script:RawArgs = $null
            $script:StandInAdvisories = @($Advisories)
            $script:StandInHealth = @($Health)
            Mock Get-ScoutRawInventory {
                $script:RawArgs = @{ IncludeAdvisories = [bool]$IncludeAdvisories }
                [pscustomobject]@{
                    Resources = @(); ResourceContainers = @(); Advisories = @($script:StandInAdvisories); Security = @(); Retirements = @()
                    ApiResources = @(); Governance = $null; CollectionHealth = @($script:StandInHealth); SourceOperations = @()
                }
            }
            Mock Get-AzSubscription { @() }
            Mock Get-ScoutDefenderPlanSweep { @() }
            Mock Get-ScoutExternalIdentitiesPolicy { [pscustomobject]@{ Collected = $false } }
            Mock Get-ScoutConditionalAccessPosture { $null }
            function global:Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; @() }
            try {
                $collect = if ($IncludeAdvisories) { Invoke-Collect -TenantID 'tenant-x' -IncludeAdvisories -WarningAction SilentlyContinue }
                else { Invoke-Collect -TenantID 'tenant-x' -WarningAction SilentlyContinue }
            }
            finally { Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue }
            [pscustomobject]@{ Collect = $collect; RawArgs = $script:RawArgs }
        }
        $script:AdvisorRow = {
            param($Category, $Impact)
            [pscustomobject]@{
                subscriptionId = 'sub-1'
                properties = [pscustomobject]@{ category = $Category; impact = $Impact; impactedField = 'Microsoft.Compute/virtualMachines'; impactedValue = 'vm-1'; shortDescription = [pscustomobject]@{ problem = 'p'; solution = 's' } }
            }
        }
    }

    It 'asks the collect pass for the Advisor table when an assessment ingests Advisor' {
        $result = & $script:Module $script:InvokeCollectWith @() @() $true
        $result.RawArgs.IncludeAdvisories | Should -BeTrue
    }

    It 'does not pay for the Advisor query when no assessment ingests Advisor' {
        $result = & $script:Module $script:InvokeCollectWith @() @() $false
        $result.RawArgs.IncludeAdvisories | Should -BeFalse
        $result.Collect.PSObject.Properties['advisorAvailable'] | Should -BeNullOrEmpty
    }

    It 'attaches every category the query returned, Security and Performance included, with the subscription ID' {
        $rows = @(
            (& $script:AdvisorRow 'Cost' 'High'), (& $script:AdvisorRow 'HighAvailability' 'Medium'),
            (& $script:AdvisorRow 'Security' 'High'), (& $script:AdvisorRow 'Performance' 'Medium')
        )
        $result = & $script:Module $script:InvokeCollectWith $rows @() $true
        @($result.Collect.advisor).Count | Should -Be 4
        @($result.Collect.advisor.Category | Sort-Object) | Should -Be @('Cost', 'HighAvailability', 'Performance', 'Security')
        @($result.Collect.advisor.Subscription | Sort-Object -Unique) | Should -Be @('sub-1')
        $result.Collect.advisorAvailable | Should -BeTrue
    }

    It 'treats a complete empty answer as complete: zero open recommendations is a finding' {
        $result = & $script:Module $script:InvokeCollectWith @() @() $true
        $result.Collect.advisorAvailable | Should -BeTrue
        @($result.Collect.advisor).Count | Should -Be 0
    }

    It 'attaches nothing when the Advisor query reported a failed batch (the data would be partial)' {
        $health = @([pscustomobject]@{ Dataset = 'Advisories'; Status = 'Unavailable'; Reason = 'boom'; ResourceTypes = @(); Collectors = @() })
        $result = & $script:Module $script:InvokeCollectWith @((& $script:AdvisorRow 'Cost' 'High')) $health $true
        $result.Collect.PSObject.Properties['advisorAvailable'] | Should -BeNullOrEmpty -Because 'the ingest must see no Advisor decision and take its explicitly-incomplete fallback'
    }

    It 'never reports the per-subscription fallback as complete, and every dependent rule reads NotAssessed' {
        $findings = & $script:Module {
            Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'Sub One'; State = 'Enabled'; TenantId = 'tenant-x' }) }
            Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'tenant-x' }; Subscription = $null } }
            Mock Set-AzContext { }
            # The fallback cmdlet returned NO Security and NO Performance rows in the field -- here it returns
            # one Cost row, which is exactly the shape that made nine rules pass on missing data.
            function Get-AzAdvisorRecommendation { [pscustomobject]@{ Category = 'Cost'; Impact = 'High'; ImpactedField = 'f'; ImpactedValue = 'v'; ShortDescriptionProblem = 'p'; ShortDescriptionSolution = 's' } }
            $collect = Import-AdvisorScores -Collect ([pscustomobject]@{}) -WarningAction SilentlyContinue
            $json = $collect | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
            [pscustomobject]@{
                Available = $collect.advisorAvailable
                Subscription = @($collect.advisor)[0].Subscription
                Findings = @(Invoke-Assessment -Collect $json -RuleSet (Get-RuleSet -Patterns 'advisor.recommendations') -Assessment 'x')
            }
        }
        $findings.Available | Should -BeFalse
        $findings.Subscription | Should -Be 'sub-1' -Because 'the fallback now fills Subscription with the ID, as the Resource Graph rows do'
        $advisorRules = @($findings.Findings | Where-Object { $_.Id -match '^ADVISOR-(RE|SE|PE|CO|OE|SC)-\d+$' })
        $advisorRules.Count | Should -BeGreaterThan 10
        foreach ($rule in $advisorRules) { $rule.Status | Should -Be 'NotAssessed' -Because "$($rule.Id) must not pass, or fail, on a source that cannot prove it is complete" }
    }

    It 'the assessment core asks for Advisor on the live path and leaves the rows it was handed alone' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-ScoutAssessmentCore.ps1')
        $source | Should -Match "\`$requiredIngestors -contains 'AdvisorScores' -and -not \`$FromInventory\) \{ \`$collectArgs\.IncludeAdvisories = \`$true \}"
        $source | Should -Match "\`$advisorFromCollectPass = \[bool\]\`$collect\.PSObject\.Properties\['advisorAvailable'\]"
    }
}

Describe 'Issue #102 -- the other ingest flags that reported complete over missing data' {

    It 'passes cost rows to the ingestor only when the inventory pass read some; a null Costs is "not read"' {
        $bound = & $script:Module {
            param($Costs, $Out)
            $script:CostBound = $null
            Mock Invoke-Collect { [pscustomobject]@{ subscriptions = @(); finops = [pscustomobject]@{ reservations = @() } } }
            Mock Import-Governance { $Collect }
            Mock Import-AdvisorScores { $Collect }
            Mock Import-ScoutCostInventory { $script:CostBound = [pscustomobject]@{ Passed = ($null -ne $FromInventory); Rows = @($FromInventory).Count }; $Collect }
            $inventory = [pscustomobject]@{ Costs = $Costs; Advisories = @(); CollectionHealth = @() }
            $null = Invoke-ScoutAssessmentCore -Assessment 'Microsoft: FinOps Review' -FromInventory $inventory -CollectOnly -OutputPath $Out
            $script:CostBound
        } $null (Join-Path $TestDrive 'costs-null')
        $bound.Passed | Should -BeFalse -Because '@($null) is a one-element array; it used to read as "one subscription pulled, zero rows" and report finops.available = true'

        $bound = & $script:Module {
            param($Costs, $Out)
            $script:CostBound = $null
            Mock Invoke-Collect { [pscustomobject]@{ subscriptions = @(); finops = [pscustomobject]@{ reservations = @() } } }
            Mock Import-Governance { $Collect }
            Mock Import-AdvisorScores { $Collect }
            Mock Import-ScoutCostInventory { $script:CostBound = [pscustomobject]@{ Passed = ($null -ne $FromInventory); Rows = @($FromInventory).Count }; $Collect }
            $inventory = [pscustomobject]@{ Costs = $Costs; Advisories = @(); CollectionHealth = @() }
            $null = Invoke-ScoutAssessmentCore -Assessment 'Microsoft: FinOps Review' -FromInventory $inventory -CollectOnly -OutputPath $Out
            $script:CostBound
        } @([pscustomobject]@{ SubscriptionId = 'a'; CostData = $null }) (Join-Path $TestDrive 'costs-rows')
        $bound.Passed | Should -BeTrue
        $bound.Rows | Should -Be 1
    }

    It 'reports devops.attempted only when Azure DevOps was requested, not merely because the inventory had rows' {
        $result = & $script:Module {
            $rows = @([pscustomobject]@{ type = 'microsoft.compute/virtualmachines' })
            [pscustomobject]@{
                Without = (Import-ScoutDevOpsCapability -Collect ([pscustomobject]@{}) -FromInventory $rows).devops
                With    = (Import-ScoutDevOpsCapability -Collect ([pscustomobject]@{}) -FromInventory $rows -IncludeDevOps).devops
            }
        }
        $result.Without.attempted | Should -BeFalse
        $result.Without.available | Should -BeFalse
        $result.With.attempted | Should -BeTrue
        $result.With.available | Should -BeFalse -Because 'attempted but nothing came back is still "unavailable", never a clean zero'
    }

    It 'reports diagnostic-settings coverage as measured only when a GET answered, not when every attempt failed' {
        $flags = & $script:Module {
            $uri = 'https://management.azure.com/subscriptions/aaa/resourceGroups/rg/providers/microsoft.keyvault/vaults/kv1/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview'
            $failed = @([pscustomobject]@{ Dataset = 'ResourceDiagnosticSettings'; Status = 'Failed'; Count = 0; Uri = $uri; ParentId = '' })
            $answered = $failed + @([pscustomobject]@{ Dataset = 'ResourceDiagnosticSettings'; Status = 'Empty'; Count = 0; Uri = $uri; ParentId = '' })
            [pscustomobject]@{
                AllFailed = (ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @() -SourceOperations $failed)['diagnosticCoverageMeasured']
                Answered  = (ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @() -SourceOperations $answered)['diagnosticCoverageMeasured']
            }
        }
        $flags.AllFailed | Should -BeFalse -Because 'an empty coverage list from a sweep that was denied everywhere must read NotAssessed, not 0 findings'
        $flags.Answered | Should -BeTrue
    }

    It 'writes a single Entra object as an array, like every other count' {
        $path = & $script:Module {
            param($Out)
            Mock Invoke-Collect { [pscustomobject]@{ subscriptions = @() } }
            $inventory = [pscustomobject]@{ EntraResources = @([pscustomobject]@{ TYPE = 'entra/users' }) }
            Invoke-ScoutAssessmentCore -InventoryOnly -FromInventory $inventory -CollectOnly -OutputPath $Out
        } (Join-Path $TestDrive 'one-entra')
        $json = Get-Content -LiteralPath $path -Raw
        $json | Should -Match '"entraResources":\s*\['
    }
}

Describe 'Issue #103 -- the run folder and report root are the same in every mode' {

    BeforeAll {
        # Runs Invoke-AzureScout -Assessment (assessment-only) with the Azure-facing commands stubbed and
        # returns what the assessment core was called with.
        $script:RunAssessmentOnly = {
            param([hashtable] $Parameters)
            $script:Captured = $null
            Mock Test-AZSCPS { 'Windows' }
            Mock Test-AZSCInteractiveHost { $false }
            Mock Connect-AZSCLoginSession { 'tenant-0000-aaaa' }
            Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'a@example.invalid' }; Tenant = [pscustomobject]@{ Id = 'tenant-0000-aaaa' } } }
            Mock Start-AZSCRunLog { }
            Mock Stop-AZSCRunLog { }
            Mock Write-AZSCLogPhase { }
            Mock Write-AZSCLog { }
            Mock Invoke-ScoutAssessmentCore {
                $script:Captured = @{ OutputPath = $OutputPath; HistoryPath = $HistoryPath }
                $null = New-Item -ItemType Directory -Path (Join-Path $OutputPath 'assessment-report') -Force
                Join-Path $OutputPath 'assessment-report'
            }
            $null = Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -NoWizard -SkipPermissionCheck @Parameters
            $script:Captured
        }
        # Runs the inventory-only or combined path up to the run-folder allocator and returns its arguments.
        $script:RunToAllocator = {
            param([hashtable] $Parameters)
            $script:Allocator = $null
            Mock Test-AZSCPS { 'Windows' }
            Mock Test-AZSCInteractiveHost { $false }
            Mock Connect-AZSCLoginSession { 'tenant-0000-aaaa' }
            Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'a@example.invalid' }; Subscription = [pscustomobject]@{ Id = 's'; Name = 'n' }; Tenant = [pscustomobject]@{ Id = 'tenant-0000-aaaa' } } }
            Mock Test-AZSCManagementGroupAccess { [pscustomobject]@{ HasAccess = $true; Count = 1 } }
            Mock Get-AZSCSubscriptions { @([pscustomobject]@{ Id = 'sub-1'; Name = 'Test' }) }
            Mock Write-AZSCLog { }
            Mock Set-AZSCReportPath { $script:Allocator = @{ ReportDir = $ReportDir; RunName = $RunName; Force = [bool]$Force }; throw 'STOP-AT-ALLOCATOR' }
            try { Invoke-AzureScout -NoWizard -SkipPermissionCheck @Parameters } catch { if ($_.Exception.Message -ne 'STOP-AT-ALLOCATOR') { throw } }
            $script:Allocator
        }
    }

    It 'honours -ReportDir and -RunName for an assessment-only run' {
        $base = Join-Path $TestDrive 'base-named'
        $captured = & $script:Module $script:RunAssessmentOnly @{ ReportDir = $base; RunName = 'my-run' }
        $captured.OutputPath | Should -Be (Join-Path $base 'my-run')
        Test-Path -LiteralPath (Join-Path $base 'my-run/assessment-report') | Should -BeTrue
    }

    It 'allocates a timestamped run folder under -ReportDir when no -RunName is given, tagged with the tenant' {
        $base = Join-Path $TestDrive 'base-stamped'
        $captured = & $script:Module $script:RunAssessmentOnly @{ ReportDir = $base }
        (Split-Path $captured.OutputPath -Parent) | Should -Be $base
        (Split-Path $captured.OutputPath -Leaf) | Should -Match '^\d{4}-\d{2}-\d{2}_\d{6}_\d{3}_tenant-0$'
    }

    It 'with no -ReportDir the allocator is asked for the standard root, never the current directory' {
        # The allocator is replaced so nothing is created outside $TestDrive; what is asserted is the
        # question the assessment-only path puts to it, and what the real allocator answers to that
        # question (resolved with -Force, which creates nothing).
        # Resolved FIRST: the stand-in allocator below would otherwise answer this question too.
        $standardBase = if (Resolve-Path -Path 'C:\' -ErrorAction SilentlyContinue) { 'C:\AzureScout' } else { Join-Path $HOME 'AzureScout' }
        $resolved = & $script:Module { (Set-AZSCReportPath -ReportDir $null -Force).BasePath }
        $resolved | Should -Be $standardBase
        $resolved | Should -Not -Match '[\/]output([\/]|$)'
        $drive = $TestDrive
        $asked = & $script:Module {
            param($Drive)
            $script:Asked = $null
            $script:DriveRoot = $Drive
            Mock Test-AZSCPS { 'Windows' }
            Mock Test-AZSCInteractiveHost { $false }
            Mock Connect-AZSCLoginSession { 'tenant-0000-aaaa' }
            Mock Get-AzContext { $null }
            Mock Start-AZSCRunLog { }
            Mock Stop-AZSCRunLog { }
            Mock Write-AZSCLogPhase { }
            Mock Write-AZSCLog { }
            Mock Set-AZSCReportPath {
                $script:Asked = @{ ReportDir = $ReportDir; RunName = $RunName }
                @{ DefaultPath = (Join-Path $script:DriveRoot 'stub-run'); BasePath = $script:DriveRoot; RunFolder = 'stub-run' }
            }
            Mock Invoke-ScoutAssessmentCore { $script:Asked.OutputPath = $OutputPath; Join-Path $OutputPath 'assessment-report' }
            $null = Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -NoWizard -SkipPermissionCheck -RunName 'issue-103-default-root'
            $script:Asked
        } $drive
        $asked.ReportDir | Should -BeNullOrEmpty
        $asked.RunName | Should -Be 'issue-103-default-root'

    }
    It 'writes straight into -ReportDir with -Force, which is how a multi-tenant child is invoked' {
        $tenantFolder = Join-Path $TestDrive 'tenant-attempt'
        $captured = & $script:Module $script:RunAssessmentOnly @{ ReportDir = $tenantFolder; Force = $true; PassThru = $true; RunName = 'ignored-by-force' }
        $captured.OutputPath | Should -Be $tenantFolder
        Test-Path -LiteralPath (Join-Path $tenantFolder 'assessment-report') | Should -BeTrue
    }

    It 'keeps the drift history in the shared base folder, with a run id that is unique per run folder' {
        $base = Join-Path $TestDrive 'base-history'
        $captured = & $script:Module $script:RunAssessmentOnly @{ ReportDir = $base; RunName = 'run-a' }
        $captured.HistoryPath | Should -Be (Join-Path $base '.scout-history')
    }

    It 'drift compares across run folders instead of seeing every run as the first' {
        $fixture = Join-Path $script:Root 'tests/datadump/sample-collect.json'
        $history = Join-Path $TestDrive 'shared-history'
        foreach ($name in 'first', 'second') {
            $out = Join-Path $TestDrive "runs/$name"
            $null = & $script:Module {
                param($Fixture, $Out, $History)
                Invoke-ScoutAssessmentCore -Assessment 'CAF: Azure Landing Zone' -FromCollect $Fixture -OutputFormat Json -OutputPath $Out -HistoryPath $History
            } $fixture $out $history
        }
        $records = @(Get-Content -LiteralPath (Join-Path $history 'findings-history.json') -Raw | ConvertFrom-Json)
        $records.Count | Should -Be 2 -Because 'two run folders must be two history records, not one overwritten record'
        @($records.RunId | Sort-Object -Unique).Count | Should -Be 2
    }

    It 'a permission-only assessment invocation allocates no run folder' {
        $base = Join-Path $TestDrive 'base-permission'
        $null = & $script:Module {
            param($Base)
            Mock Test-AZSCPS { 'Windows' }
            Mock Test-AZSCInteractiveHost { $false }
            Mock Connect-AZSCLoginSession { 'tenant-0000-aaaa' }
            Mock Get-AzContext { $null }
            Mock Start-AZSCRunLog { }
            Mock Stop-AZSCRunLog { }
            Mock Write-AZSCLogPhase { }
            Mock Write-AZSCLog { }
            Mock Invoke-ScoutAssessmentCore { 'permissions' }
            Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -PermissionAudit -NoWizard -ReportDir $Base
        } $base
        @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'the combined and inventory-only paths allocate through the same call with the same -ReportDir and -RunName' {
        $base = Join-Path $TestDrive 'base-allocator'
        $combined = & $script:Module $script:RunToAllocator @{ Assessment = 'CAF: Azure Landing Zone'; InventoryAndAssessment = $true; ReportDir = $base; RunName = 'both-run'; OutputFormat = 'React' }
        $inventory = & $script:Module $script:RunToAllocator @{ ReportDir = $base; RunName = 'inv-run'; OutputFormat = 'Json' }
        $combined.RunName | Should -Be 'both-run'
        $combined.ReportDir | Should -Be $base
        $inventory.RunName | Should -Be 'inv-run'
        $inventory.ReportDir | Should -Be $base
    }

    It 'the wizard path keeps working: a report directory chosen in the wizard becomes the run root' {
        $base = Join-Path $TestDrive 'base-wizard'
        $captured = & $script:Module {
            param($Base)
            $script:Captured = $null
            $script:WizardBase = $Base
            Mock Test-AZSCPS { 'Windows' }
            Mock Test-AZSCInteractiveHost { $true }
            Mock Test-AZSCWizardEligible { $true }
            Mock Start-AZSCWizard { [pscustomobject]@{ Answers = @{ Assessment = @('CAF: Azure Landing Zone'); ReportDir = $script:WizardBase }; RunBoth = $false } }
            Mock Connect-AZSCLoginSession { 'tenant-0000-aaaa' }
            Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'a@example.invalid' }; Tenant = [pscustomobject]@{ Id = 'tenant-0000-aaaa' } } }
            Mock Start-AZSCRunLog { }
            Mock Stop-AZSCRunLog { }
            Mock Write-AZSCLogPhase { }
            Mock Write-AZSCLog { }
            Mock Invoke-ScoutAssessmentCore { $script:Captured = @{ OutputPath = $OutputPath }; Join-Path $OutputPath 'assessment-report' }
            $null = Invoke-AzureScout -RunName 'wizard-run'
            $script:Captured
        } $base
        $captured.OutputPath | Should -Be (Join-Path $base 'wizard-run')
    }

    It 'no longer routes assessment-only output to ./output' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-AzureScout.ps1')
        $source | Should -Not -Match "else \{ '\./output' \}"
        $source | Should -Match '\$standaloneReportPath = Set-AZSCReportPath -ReportDir \$ReportDir -RunName \$RunName -ScopeId \$TenantID -Force:\$Force'
    }
}
