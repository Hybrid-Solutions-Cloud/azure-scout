#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: the Mission Critical, Sustainability and Go-Live Well-Architected reviews.

    Each rule set is run against three collect objects built here -- a compliant estate, a
    non-compliant one and an empty one -- so every automated rule's Pass and Fail is pinned, every
    gated rule is proven NotAssessed when its data is absent, manual rules stay Manual, and no rule
    errors. All identifiers below are synthetic.
#>

BeforeDiscovery {
    $script:Reviews = @(
        @{ Name = 'Mission Critical'; Pattern = 'waf.missioncritical'; Assessment = 'WAF: Mission Critical'; Prefix = 'WAF-MC'; Framework = 'WAF-MC'; Doc = 'waf-mission-critical-checklist.md'; Total = 81; Auto = 42; Manual = 39 }
        @{ Name = 'Sustainability'; Pattern = 'waf.sustainability'; Assessment = 'WAF: Sustainability'; Prefix = 'WAF-SUS'; Framework = 'WAF-SUS'; Doc = 'waf-sustainability-checklist.md'; Total = 67; Auto = 21; Manual = 46 }
        @{ Name = 'Go-Live'; Pattern = 'waf.golive'; Assessment = 'WAF: Go-Live'; Prefix = 'WAF-GOLIVE'; Framework = 'WAF-GOLIVE'; Doc = 'waf-go-live-checklist.md'; Total = 57; Auto = 36; Manual = 21 }
    )
}

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml

    function Invoke-ScoutTestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    function ConvertTo-FindingMap {
        param($Findings)
        $map = @{}
        foreach ($f in $Findings) { $map[[string]$f.Id] = $f }
        $map
    }

    # One estate, compliant ($Good) or not. Every dataset an automated rule reads is present in both
    # so no gate closes; only the values differ. Datasets that two rules need in opposite shapes
    # (Application Insights for Go-Live PE-05, alert rules for MC HM-08) are adjusted by -Tweak.
    function Get-TestEstate {
        param([bool] $Good, [scriptblock] $Tweak)
        $p = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'
        $vm = "$p/Microsoft.Compute/virtualMachines/vm1"
        $disk = "$p/Microsoft.Compute/disks/disk1"
        $plan = "$p/Microsoft.Web/serverfarms/plan1"
        $planF = "$p/Microsoft.Web/serverfarms/plan2"
        $G = { param($a, $b) if ($Good) { $a } else { $b } }

        $estate = [ordered]@{
            subscriptions = @([ordered]@{ id = '00000000-0000-0000-0000-000000000001'; name = 'sub'; state = 'Enabled' })
            compute       = [ordered]@{
                virtualMachines = @([ordered]@{ id = $vm; name = 'vm1'; zoneEligible = $true; zoneRedundant = (& $G $true $false); patchMode = (& $G 'AutomaticByPlatform' 'Manual'); assessmentMode = 'AutomaticByPlatform' })
            }
            networking    = [ordered]@{
                frontDoors             = @(if ($Good) { [ordered]@{ id = "$p/Microsoft.Network/frontDoors/fd"; name = 'fd'; sku = 'Standard_AzureFrontDoor' } })
                cdnProfiles            = @(if ($Good) { [ordered]@{ id = "$p/Microsoft.Cdn/profiles/cdn"; name = 'cdn'; sku = 'Standard_Microsoft' } })
                trafficManagerProfiles = @()
                applicationGateways    = @([ordered]@{ id = "$p/Microsoft.Network/applicationGateways/agw"; name = 'agw'; wafEnabled = $Good })
                loadBalancers          = @([ordered]@{ id = "$p/Microsoft.Network/loadBalancers/lb"; name = 'lb'; sku = (& $G 'Standard' 'Basic'); backendPoolCount = (& $G 2 0) })
                natGateways            = @([ordered]@{ id = "$p/Microsoft.Network/natGateways/nat"; name = 'nat'; subnetCount = (& $G 1 0) })
                virtualNetworks        = @([ordered]@{ name = 'vnet'; peeringCount = 1; ddosEnabled = $Good })
                nsgPublicInbound       = @([ordered]@{ nsg = 'nsg'; rule = 'r'; port = (& $G '443' '3389') })
                bastionHosts           = @([ordered]@{ id = "$p/Microsoft.Network/bastionHosts/bas"; name = 'bas' })
                azureFirewalls         = @([ordered]@{ name = 'fw'; sku = 'Premium' })
            }
            security      = [ordered]@{
                wafPolicies   = @([ordered]@{ id = 'waf1'; mode = (& $G 'Prevention' 'Detection'); enabledState = 'Enabled' })
                defenderPlans = @([ordered]@{ name = 'VirtualMachines'; properties = [ordered]@{ pricingTier = (& $G 'Standard' 'Free') } })
                defenderSecureScores = @([ordered]@{ SubscriptionId = (& $G '00000000-0000-0000-0000-000000000001' '00000000-0000-0000-0000-000000000099'); Percentage = 0.5 })
            }
            management    = [ordered]@{
                logAnalyticsWorkspaces      = @(if ($Good) { [ordered]@{ name = 'law'; retentionInDays = 30 }; [ordered]@{ name = 'law-long'; retentionInDays = 180 } })
                backupProtectedItems        = @([ordered]@{ id = 'bi1'; sourceResourceId = (& $G $vm "$p/Microsoft.Compute/virtualMachines/other"); lastBackupStatus = (& $G 'Completed' 'Failed') })
                recoveryVaultBackupPolicies = @([ordered]@{ id = 'pol'; backupManagementType = 'AzureIaasVM'; scheduleFrequency = 'Daily' })
            }
            opsPosture    = [ordered]@{
                diagnosticCoverage         = @([ordered]@{ type = 'microsoft.keyvault/vaults'; total = 10; withDiag = (& $G 9 1); coveragePct = (& $G 90 10) })
                diagnosticCoverageMeasured = $true
            }
            monitor       = [ordered]@{
                appInsights                  = @([ordered]@{ id = 'ai1'; name = 'ai'; ingestionMode = (& $G 'LogAnalytics' 'ApplicationInsights') })
                appInsightsAvailabilityTests = @(if ($Good) { [ordered]@{ id = 'wt1'; enabled = $true } })
                metricAlertRules             = @([ordered]@{ id = 'ma1'; enabled = $true; actionGroupCount = (& $G 1 0) })
                scheduledQueryRules          = @()
                actionGroups                 = @(if ($Good) { [ordered]@{ id = 'ag1'; enabled = $true; emailReceiverCount = 1 } })
                activityLogAlertRules        = @([ordered]@{ id = 'al1'; enabled = $true; category = (& $G 'ServiceHealth' 'Administrative') })
                dataCollectionRules          = @(if ($Good) { [ordered]@{ id = 'dcr1'; hasLogAnalyticsDestination = $true; dataFlowCount = 1 } })
                autoscaleSettings            = @([ordered]@{ id = 'as1'; enabled = $Good; targetResourceUri = (& $G $plan "$p/Microsoft.Web/serverfarms/none") })
            }
            governance    = [ordered]@{
                policyAssignments          = @(if ($Good) {
                        [ordered]@{ name = 'a1'; properties = [ordered]@{ displayName = 'Sustainability baseline'; policyDefinitionId = 'x' } }
                        [ordered]@{ name = 'a2'; properties = [ordered]@{ displayName = 'Require a tag on resource groups'; policyDefinitionId = 'x' } }
                        [ordered]@{ name = 'a3'; properties = [ordered]@{ displayName = 'Allowed locations'; policyDefinitionId = 'x' } }
                    })
                policyAssignmentsAvailable = $true
                resourceLocks              = @(if ($Good) { [ordered]@{ name = 'lock1' } })
                resourceLocksAvailable     = $true
                budgets                    = @(if ($Good) { [ordered]@{ name = 'budget1' } })
                budgetsAvailable           = $true
                # Evidence for WAF-MC-SE-09: a permanent, standing privileged assignment held by a user.
                roleAssignmentSchedules    = @([ordered]@{ id = 'sched1'; principalId = 'p1'; principalType = 'User'; roleDefinitionName = 'Owner'; privilegedRole = $true; accessType = 'Standing'; permanent = $true })
                roleAssignmentSchedulesMeasured = $true
            }
            costCleanup   = [ordered]@{
                orphanedDisks = @(if (-not $Good) { [ordered]@{ name = 'old-disk'; location = 'eastus' } })
                orphanedPips  = @(if (-not $Good) { [ordered]@{ name = 'old-pip'; location = 'eastus' } })
            }
            advisor       = @(if (-not $Good) {
                    [ordered]@{ Category = 'Cost'; Impact = 'High'; ShortDescriptionProblem = 'Right-size or shutdown underutilized virtual machines' }
                    [ordered]@{ Category = 'HighAvailability'; Impact = 'High'; ShortDescriptionProblem = 'Enable backup' }
                    [ordered]@{ Category = 'Security'; Impact = 'High'; ShortDescriptionProblem = 'Enable MFA' }
                    [ordered]@{ Category = 'OperationalExcellence'; Impact = 'High'; ShortDescriptionProblem = 'Enable diagnostics' }
                    [ordered]@{ Category = 'Performance'; Impact = 'High'; ShortDescriptionProblem = 'Scale up' }
                })
            advisorAvailable = $true
            finops        = [ordered]@{ reservations = @([ordered]@{ id = 'res1'; sku = 'Standard_D2s_v5' }) }
            devops        = [ordered]@{
                loadTesting      = @(if ($Good) { [ordered]@{ name = 'lt' } })
                chaosExperiments = @(if ($Good) { [ordered]@{ name = 'chaos' } })
                managedPools     = @([ordered]@{ name = 'pool' })
            }
            domains       = [ordered]@{
                storage    = [ordered]@{
                    storageAccounts = @([ordered]@{ id = "$p/Microsoft.Storage/storageAccounts/st1"; name = 'st1'; sku = (& $G 'Standard_GZRS' 'Standard_LRS'); networkDefaultDeny = $Good; httpsOnly = $Good; minTls = (& $G 'TLS1_2' 'TLS1_0') })
                    managedDisks    = @(
                        [ordered]@{ id = $disk; name = 'disk1'; location = 'eastus' }
                        if ($Good) { [ordered]@{ id = "$p/Microsoft.Compute/disks/disk2"; name = 'disk2'; location = 'westus' } }
                    )
                    snapshots       = @([ordered]@{ id = 'snap1'; name = 'snap1'; sourceDiskId = (& $G $disk "$p/Microsoft.Compute/disks/deleted") })
                    lifecyclePoliciesMeasured = $true
                    lifecyclePolicies = @([ordered]@{ storageAccountId = 'st1'; premium = $false; policyPresent = $Good; enabledRuleCount = (& $G 2 0); tieringRuleCount = (& $G 1 0); deleteRuleCount = (& $G 1 0) })
                }
                databases  = [ordered]@{
                    sqlDatabases              = @(
                        [ordered]@{ name = 'srv/db1'; zoneRedundant = $Good; tier = 'GeneralPurpose' }
                        [ordered]@{ name = 'srv/master'; zoneRedundant = $false; tier = 'System' }
                    )
                    sqlServers                = @([ordered]@{ name = 'srv'; publicNetworkAccess = (& $G 'Disabled' 'Enabled') })
                    sqlDefenderPricing        = @([ordered]@{ subscriptionId = 's'; name = 'sqlservers'; pricingTier = (& $G 'Standard' 'Free') })
                    cosmosDbAccounts          = @([ordered]@{ id = 'cos1'; name = 'cos'; publicNetworkAccess = (& $G 'Disabled' 'Enabled'); disableLocalAuth = $Good })
                    postgreSqlFlexibleServers = @([ordered]@{ id = 'pg1'; name = 'pg' })
                    redisCaches               = @([ordered]@{ id = 'rc1'; name = 'rc'; type = (& $G 'microsoft.cache/redisenterprise' 'microsoft.cache/redis') })
                }
                web        = [ordered]@{
                    webApps               = @([ordered]@{ name = 'app'; httpsOnly = $true })
                    webAppDeploymentSlots = @([ordered]@{ id = 'slot1'; name = 'app/staging'; siteName = 'app' })
                    appServicePlans       = @(
                        if ($Good) { [ordered]@{ id = $plan; name = 'plan1'; sku = 'P1v3' } }
                        else { [ordered]@{ id = $plan; name = 'plan1'; sku = 'S1' }; [ordered]@{ id = $planF; name = 'plan2'; sku = 'F1' } }
                    )
                }
                containers = [ordered]@{
                    aksClusters         = @([ordered]@{ name = 'aks'; k8sVersion = '1.33'; allPoolsZoned = $Good; networkPolicyEnabled = $Good })
                    containerRegistries = @([ordered]@{ name = 'acr'; sku = (& $G 'Premium' 'Basic'); adminEnabled = (-not $Good); publicAccess = (& $G 'Disabled' 'Enabled') })
                    containerApps       = @([ordered]@{ id = 'ca1'; name = 'ca' })
                }
                security   = [ordered]@{
                    keyVaults = @([ordered]@{ id = 'kv1'; name = 'kv'; softDelete = $Good; purgeProtection = $Good })
                }
                # Evidence for WAF-GOLIVE-SE-05: an enabled Conditional Access policy that requires MFA.
                identity   = [ordered]@{
                    managedIdentities = @([ordered]@{ id = 'mi1'; name = 'mi' })
                    conditionalAccess = [ordered]@{ Collected = $true; policies = @([ordered]@{ id = 'ca1'; displayName = 'MFA'; enabled = $true; requiresMfa = $true; targetsAllUsers = $true }) }
                }
                integration = [ordered]@{
                    eventHubNamespaces   = @([ordered]@{ name = 'eh'; zoneRedundant = $Good })
                    serviceBusNamespaces = @([ordered]@{ name = 'sb'; publicAccess = 'Disabled' })
                    apiManagement        = @([ordered]@{ name = 'apim'; sku = 'Premium' })
                }
                ai         = [ordered]@{
                    cognitiveAccounts = @([ordered]@{ id = 'cog1'; name = 'cog' })
                    mlWorkspaces      = @([ordered]@{ id = 'ml1'; name = 'ml'; location = 'eastus' })
                    searchServices    = @([ordered]@{ id = 'srch1'; name = 'srch'; sku = (& $G 'standard' 'free') })
                }
            }
        }
        if ($Tweak) { & $Tweak $estate }
        $estate
    }

    function Get-TestEmptyEstate {
        [ordered]@{
            subscriptions    = @()
            compute          = [ordered]@{ virtualMachines = @() }
            networking       = [ordered]@{ frontDoors = @(); cdnProfiles = @(); trafficManagerProfiles = @(); applicationGateways = @(); loadBalancers = @(); natGateways = @(); virtualNetworks = @(); nsgPublicInbound = @(); bastionHosts = @(); azureFirewalls = @() }
            security         = [ordered]@{ wafPolicies = @(); defenderPlans = @(); defenderSecureScores = @() }
            management       = [ordered]@{ logAnalyticsWorkspaces = @(); backupProtectedItems = @(); recoveryVaultBackupPolicies = @() }
            opsPosture       = [ordered]@{ diagnosticCoverage = @(); diagnosticCoverageMeasured = $false }
            monitor          = [ordered]@{ appInsights = @(); appInsightsAvailabilityTests = @(); metricAlertRules = @(); scheduledQueryRules = @(); actionGroups = @(); activityLogAlertRules = @(); dataCollectionRules = @(); autoscaleSettings = @() }
            governance       = [ordered]@{ policyAssignments = @(); policyAssignmentsAvailable = $false; resourceLocks = @(); resourceLocksAvailable = $false; budgets = @(); budgetsAvailable = $false }
            costCleanup      = [ordered]@{ orphanedDisks = @(); orphanedPips = @() }
            advisor          = @()
            advisorAvailable = $false
            finops           = [ordered]@{ reservations = @() }
            devops           = [ordered]@{ loadTesting = @(); chaosExperiments = @(); managedPools = @() }
            domains          = [ordered]@{
                storage     = [ordered]@{ storageAccounts = @(); managedDisks = @(); snapshots = @(); lifecyclePolicies = @(); lifecyclePoliciesMeasured = $false }
                databases   = [ordered]@{ sqlDatabases = @(); sqlServers = @(); sqlDefenderPricing = @(); cosmosDbAccounts = @(); postgreSqlFlexibleServers = @(); redisCaches = @() }
                web         = [ordered]@{ webApps = @(); webAppDeploymentSlots = @(); appServicePlans = @() }
                containers  = [ordered]@{ aksClusters = @(); containerRegistries = @(); containerApps = @() }
                security    = [ordered]@{ keyVaults = @() }
                identity    = [ordered]@{ managedIdentities = @() }
                integration = [ordered]@{ eventHubNamespaces = @(); serviceBusNamespaces = @(); apiManagement = @() }
                ai          = [ordered]@{ cognitiveAccounts = @(); mlWorkspaces = @(); searchServices = @() }
            }
        }
    }

    # Go-Live PE-05 needs web apps WITHOUT Application Insights; the other rule sets need it present.
    $noAppInsights = { param($e) $e.monitor.appInsights = @() }

    $script:Results = @{}
    $reviews = @(
        @{ Pattern = 'waf.missioncritical'; Assessment = 'WAF: Mission Critical'; BadTweak = $null }
        @{ Pattern = 'waf.sustainability'; Assessment = 'WAF: Sustainability'; BadTweak = $null }
        @{ Pattern = 'waf.golive'; Assessment = 'WAF: Go-Live'; BadTweak = $noAppInsights }
    )
    foreach ($r in $reviews) {
        $script:Results[$r.Pattern] = @{
            Good  = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern $r.Pattern -Collect (Get-TestEstate -Good $true) -Assessment $r.Assessment)
            Bad   = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern $r.Pattern -Collect (Get-TestEstate -Good $false -Tweak $r.BadTweak) -Assessment $r.Assessment)
            Empty = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern $r.Pattern -Collect (Get-TestEmptyEstate) -Assessment $r.Assessment)
        }
        $script:Results[$r.Pattern].Set = & $script:Module { param($p) Get-RuleSet -Patterns $p } $r.Pattern
    }
}

Describe '<Name> review' -ForEach $script:Reviews {
    BeforeAll {
        $script:Set = $script:Results[$Pattern].Set
        $script:Rules = @($script:Set.Rules)
        $script:AutoRules = @($script:Rules | Where-Object { -not $_.manual })
        $script:ManualRules = @($script:Rules | Where-Object { $_.manual })
        $script:DocText = Get-Content "$script:root/docs/frameworks/$Doc" -Raw
    }

    It 'loads one rule set with the expected framework and rule counts' {
        @($script:Set).Count | Should -Be 1
        $script:Set.Framework | Should -Be $Framework
        $script:Set.FrameworkVersion | Should -Not -BeNullOrEmpty
        $script:Rules.Count | Should -Be $Total
        $script:AutoRules.Count | Should -Be $Auto
        $script:ManualRules.Count | Should -Be $Manual
    }

    It 'has unique ids, each carrying its framework prefix, and every title and remediation starts with the id' {
        @($script:Rules.id | Select-Object -Unique).Count | Should -Be $Total
        foreach ($r in $script:Rules) {
            $r.id | Should -Match "^$Prefix-[A-Z]+-\d{2}$"
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
        }
    }

    It 'enumerates exactly the rule ids in its checklist doc' {
        $docIds = @([regex]::Matches($script:DocText, "\|\s*($Prefix-[A-Z]+-\d{2})\s*\|") | ForEach-Object { $_.Groups[1].Value })
        @($docIds | Select-Object -Unique).Count | Should -Be $docIds.Count -Because 'an item must not be listed twice'
        @($docIds | Sort-Object) | Should -Be @($script:Rules.id | Sort-Object)
        $script:DocText | Should -Match ("\|\s*\*\*Total\*\*\s*\|\s*\*\*$Total\*\*\s*\|\s*\*\*$Auto\*\*\s*\|\s*\*\*$Manual\*\*")
    }

    It 'gates every automated rule, so an estate without the data is never passed or failed' {
        foreach ($r in $script:AutoRules) {
            $r.assert.ContainsKey('gate') | Should -BeTrue -Because "$($r.id) must be gated"
        }
    }

    It 'gives every Advisor-backed rule the Advisor availability gate and no other rule that gate' {
        foreach ($r in $script:AutoRules) {
            $isAdvisor = ($null -ne $r.query) -and ([string]$r.query).StartsWith('$.advisor')
            ([string]$r.assert.gate -eq '$.advisorAvailable') | Should -Be $isAdvisor -Because $r.id
        }
    }

    It 'reports every automated rule Pass on a compliant estate' {
        foreach ($r in $script:AutoRules) {
            $script:Results[$Pattern].Good[[string]$r.id].Status | Should -Be 'Pass' -Because "$($r.id) on a compliant estate"
        }
    }

    It 'reports every automated rule Fail on a non-compliant estate' {
        $expected = @{}
        # An alert rule that fires without an action group (MC HM-07) is still an enabled alert
        # rule, so HM-08 (alert rules exist) passes on the same estate; it is proven separately.
        if ($Pattern -eq 'waf.missioncritical') { $expected['WAF-MC-HM-08'] = 'Pass' }
        foreach ($r in $script:AutoRules) {
            $want = if ($expected.ContainsKey($r.id)) { $expected[$r.id] } else { 'Fail' }
            $script:Results[$Pattern].Bad[[string]$r.id].Status | Should -Be $want -Because "$($r.id) on a non-compliant estate"
        }
    }

    It 'reports every automated rule NotAssessed on an empty estate' {
        foreach ($r in $script:AutoRules) {
            $script:Results[$Pattern].Empty[[string]$r.id].Status | Should -Be 'NotAssessed' -Because "$($r.id) must not pass or fail an estate with nothing to check"
        }
    }

    It 'keeps every manual rule Manual in all three estates' {
        foreach ($r in $script:ManualRules) {
            foreach ($kind in 'Good', 'Bad', 'Empty') {
                $script:Results[$Pattern][$kind][[string]$r.id].Status | Should -Be 'Manual' -Because "$($r.id) in the $kind estate"
            }
        }
    }

    It 'attaches evidence to every manual rule that names a query, when the data exists' {
        foreach ($r in @($script:ManualRules | Where-Object { $_.query })) {
            $script:Results[$Pattern].Good[[string]$r.id].EvidenceCount | Should -BeGreaterThan 0 -Because "$($r.id) evidence query '$($r.query)'"
        }
    }

    It 'produces no Error findings in any estate' {
        foreach ($kind in 'Good', 'Bad', 'Empty') {
            @($script:Results[$Pattern][$kind].Values | Where-Object Status -eq 'Error').Count | Should -Be 0 -Because "the $kind estate"
        }
    }
}

Describe 'Rules whose behaviour is more than Pass or Fail' {
    It 'MC AD-02 counts distinct regions, not disks' {
        $good = $script:Results['waf.missioncritical'].Good['WAF-MC-AD-02']
        $bad = $script:Results['waf.missioncritical'].Bad['WAF-MC-AD-02']
        $good.EvidenceCount | Should -Be 2
        $bad.EvidenceCount | Should -Be 1
    }

    It 'MC DP-04 and Go-Live RE-06 exclude the SQL system database' {
        $script:Results['waf.missioncritical'].Bad['WAF-MC-DP-04'].EvidenceCount | Should -Be 1
        $script:Results['waf.golive'].Bad['WAF-GOLIVE-RE-06'].EvidenceCount | Should -Be 1
    }

    It 'MC HM-08 fails when no alert rule of either kind exists' {
        $estate = Get-TestEstate -Good $false -Tweak { param($e) $e.monitor.metricAlertRules = @(); $e.monitor.scheduledQueryRules = @() }
        $f = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.missioncritical' -Collect $estate -Assessment 'WAF: Mission Critical')
        $f['WAF-MC-HM-08'].Status | Should -Be 'Fail'
    }

    It 'MC NC-01 passes on any one of Front Door, CDN profile or Traffic Manager' {
        $estate = Get-TestEstate -Good $false -Tweak { param($e) $e.networking.cdnProfiles = @(); $e.networking.trafficManagerProfiles = @([ordered]@{ id = 'tm1'; name = 'tm' }) }
        $f = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.missioncritical' -Collect $estate -Assessment 'WAF: Mission Critical')
        $f['WAF-MC-NC-01'].Status | Should -Be 'Pass'
    }

    It 'MC NC-09 and Go-Live SE-06 flag RDP, SSH and all-port rules but not HTTPS' {
        foreach ($port in '22', '3389', '*') {
            $estate = Get-TestEstate -Good $true -Tweak { param($e) $e.networking.nsgPublicInbound = @([ordered]@{ nsg = 'n'; rule = 'r'; port = $port }) }
            $f = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.golive' -Collect $estate -Assessment 'WAF: Go-Live')
            $f['WAF-GOLIVE-SE-06'].Status | Should -Be 'Fail' -Because "port $port"
        }
        $script:Results['waf.golive'].Good['WAF-GOLIVE-SE-06'].Status | Should -Be 'Pass'
    }

    It 'App Service autoscale rules ignore Free, Shared and Basic plans' {
        $estate = Get-TestEstate -Good $false -Tweak { param($e) $e.domains.web.appServicePlans = @([ordered]@{ id = 'p1'; name = 'p'; sku = 'B1' }) }
        $f = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.golive' -Collect $estate -Assessment 'WAF: Go-Live')
        $f['WAF-GOLIVE-PE-06'].Status | Should -Be 'Pass'
    }

    It 'Go-Live CO-04 and SUS OE-06/OE-07 are name heuristics that read the policy display name' {
        $estate = Get-TestEstate -Good $true -Tweak { param($e) $e.governance.policyAssignments = @([ordered]@{ name = 'a'; properties = [ordered]@{ displayName = 'Something unrelated' } }) }
        $gl = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.golive' -Collect $estate -Assessment 'WAF: Go-Live')
        $su = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.sustainability' -Collect $estate -Assessment 'WAF: Sustainability')
        $gl['WAF-GOLIVE-CO-04'].Status | Should -Be 'Fail'
        $su['WAF-SUS-OE-06'].Status | Should -Be 'Fail'
        $su['WAF-SUS-OE-07'].Status | Should -Be 'Fail'
        $su['WAF-SUS-OE-05'].Status | Should -Be 'Pass'
    }

    It 'Advisor-backed rules match the right category and impact only' {
        $estate = Get-TestEstate -Good $true -Tweak { param($e) $e.advisor = @([ordered]@{ Category = 'Security'; Impact = 'Medium'; ShortDescriptionProblem = 'x' }) }
        $f = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.golive' -Collect $estate -Assessment 'WAF: Go-Live')
        $f['WAF-GOLIVE-SE-15'].Status | Should -Be 'Pass' -Because 'only High impact counts'
        $estate = Get-TestEstate -Good $true -Tweak { param($e) $e.advisor = @([ordered]@{ Category = 'Cost'; Impact = 'Low'; ShortDescriptionProblem = 'x' }) }
        $f = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.sustainability' -Collect $estate -Assessment 'WAF: Sustainability')
        $f['WAF-SUS-CO-02'].Status | Should -Be 'Pass'
    }

    It 'is not assessed when Advisor is unavailable, instead of reading an empty list as clean' {
        $estate = Get-TestEstate -Good $true -Tweak { param($e) $e.advisorAvailable = $false }
        $f = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.golive' -Collect $estate -Assessment 'WAF: Go-Live')
        foreach ($id in 'WAF-GOLIVE-RE-14', 'WAF-GOLIVE-SE-15', 'WAF-GOLIVE-CO-07', 'WAF-GOLIVE-OE-10', 'WAF-GOLIVE-PE-09') {
            $f[$id].Status | Should -Be 'NotAssessed'
        }
    }

    It 'is not assessed when diagnostics coverage was never measured' {
        $estate = Get-TestEstate -Good $false -Tweak { param($e) $e.opsPosture.diagnosticCoverageMeasured = $false }
        $mc = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.missioncritical' -Collect $estate -Assessment 'WAF: Mission Critical')
        $gl = ConvertTo-FindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.golive' -Collect $estate -Assessment 'WAF: Go-Live')
        $mc['WAF-MC-HM-04'].Status | Should -Be 'NotAssessed'
        $gl['WAF-GOLIVE-OE-06'].Status | Should -Be 'NotAssessed'
    }
}
