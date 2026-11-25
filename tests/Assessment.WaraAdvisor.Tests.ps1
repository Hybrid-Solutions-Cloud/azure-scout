#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: the Well-Architected Reliability Assessment (WARA, backed by the Azure Proactive
    Resiliency Library) and the Azure Advisor recommendations assessment. Each rule set is run
    against small collect objects built here, so every automated rule's Pass/Fail is pinned, gated
    rules are proven NotAssessed on an estate without the resource, and no rule errors.

    Three WARA estates are built: a "bad" one where every automated rule has something to find, a
    "healthy" one where every automated rule passes, and an empty one where every rule is gated.
    Advisor gets the same three shapes, plus the "Advisor was skipped" shape the advisorAvailable
    gate exists for.
#>

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

    function ConvertTo-ScoutFindingMap {
        param($Findings)
        $map = @{}
        foreach ($f in $Findings) { $map[[string]$f.Id] = $f }
        $map
    }

    $sub = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'
    $script:VmGood = "$sub/Microsoft.Compute/virtualMachines/vm-good"

    # ---- WARA: an estate where every automated rule has at least one finding --------------------
    $script:WaraBad = [ordered]@{
        compute    = [ordered]@{
            virtualMachines = @(
                [ordered]@{ id = $script:VmGood; name = 'vm-good'; zoneEligible = $true; zoneRedundant = $true; size = 'Standard_D2s_v5' }
                [ordered]@{ id = "$sub/Microsoft.Compute/virtualMachines/vm-bad"; name = 'vm-bad'; zoneEligible = $true; zoneRedundant = $false; size = 'Standard_B2s' }
                [ordered]@{ id = "$sub/Microsoft.Compute/virtualMachines/vm-nozones"; name = 'vm-nozones'; zoneEligible = $false; zoneRedundant = $false; size = 'Standard_D2s_v5' }
            )
        }
        management = [ordered]@{
            backupProtectedItems = @([ordered]@{ name = 'item1'; sourceResourceId = $script:VmGood })
            recoveryVaults       = @(
                [ordered]@{ name = 'rsv-bad'; softDelete = 'Disabled'; storageType = 'GeoRedundant'; crossRegion = 'False' }
                [ordered]@{ name = 'rsv-ok'; softDelete = 'Enabled'; storageType = 'LocallyRedundant'; crossRegion = 'False' }
            )
        }
        networking = [ordered]@{
            loadBalancers        = @(
                [ordered]@{ name = 'lb-std'; sku = 'Standard' }
                [ordered]@{ name = 'lb-basic'; sku = 'Basic' }
            )
            applicationGateways  = @(
                [ordered]@{ name = 'agw-v2'; sku = 'Standard_v2'; tier = 'Standard_v2' }
                [ordered]@{ name = 'agw-v1'; sku = 'Standard_Medium'; tier = 'Standard' }
                [ordered]@{ name = 'agw-waf1'; sku = 'WAF_Medium'; tier = 'WAF' }
            )
            vpnGateways          = @(
                [ordered]@{ name = 'vpn-az'; gatewayType = 'Vpn'; sku = 'VpnGw1AZ'; activeActive = $true }
                [ordered]@{ name = 'vpn-old'; gatewayType = 'Vpn'; sku = 'VpnGw2'; activeActive = $false }
                [ordered]@{ name = 'vpn-aa-az'; gatewayType = 'Vpn'; sku = 'VpnGw2AZ'; activeActive = $false }
                [ordered]@{ name = 'vpn-basic'; gatewayType = 'Vpn'; sku = 'Basic'; activeActive = $false }
                [ordered]@{ name = 'er-az'; gatewayType = 'ExpressRoute'; sku = 'ErGw1AZ'; activeActive = $false }
                [ordered]@{ name = 'er-old'; gatewayType = 'ExpressRoute'; sku = 'Standard'; activeActive = $false }
            )
            expressRouteCircuits = @([ordered]@{ name = 'circuit1'; peeringLocation = 'LocationA'; serviceProviderName = 'ProviderA' })
            azureFirewalls       = @([ordered]@{ name = 'fw1'; sku = 'Premium' })
        }
        domains    = [ordered]@{
            storage     = [ordered]@{
                managedDisks    = @(
                    [ordered]@{ name = 'd-prem'; sku = 'Premium_LRS'; diskState = 'Attached' }
                    [ordered]@{ name = 'd-hdd'; sku = 'Standard_LRS'; diskState = 'Attached' }
                    [ordered]@{ name = 'd-spare'; sku = 'Standard_LRS'; diskState = 'Unattached' }
                )
                storageAccounts = @(
                    [ordered]@{ name = 's-zrs'; sku = 'Standard_ZRS' }
                    [ordered]@{ name = 's-lrs'; sku = 'Standard_LRS' }
                    [ordered]@{ name = 's-prem'; sku = 'Premium_LRS' }
                )
            }
            security    = [ordered]@{
                keyVaults = @(
                    [ordered]@{ name = 'kv-ok'; softDelete = $null; purgeProtection = $true }
                    [ordered]@{ name = 'kv-bad'; softDelete = $false; purgeProtection = $false }
                    [ordered]@{ name = 'kv-null'; softDelete = $null; purgeProtection = $null }
                )
            }
            containers  = [ordered]@{
                aksClusters         = @(
                    [ordered]@{ name = 'aks-ok'; allPoolsZoned = $true; aadIntegrated = $true }
                    [ordered]@{ name = 'aks-bad'; allPoolsZoned = $false; aadIntegrated = $false }
                )
                containerRegistries = @(
                    [ordered]@{ name = 'acr-prem'; sku = 'Premium' }
                    [ordered]@{ name = 'acr-basic'; sku = 'Basic' }
                )
            }
            web         = [ordered]@{
                appServicePlans = @(
                    [ordered]@{ name = 'plan-p1'; sku = 'P1v3'; reserved = $false }
                    [ordered]@{ name = 'plan-b1'; sku = 'B1'; reserved = $false }
                    [ordered]@{ name = 'plan-y1'; sku = 'Y1'; reserved = $false }
                )
            }
            databases   = [ordered]@{
                sqlDatabases              = @(
                    [ordered]@{ name = 'master'; zoneRedundant = $false; tier = 'System' }
                    [ordered]@{ name = 'db-ok'; zoneRedundant = $true; tier = 'Premium' }
                    [ordered]@{ name = 'db-bad'; zoneRedundant = $false; tier = 'GeneralPurpose' }
                    [ordered]@{ name = 'db-null'; zoneRedundant = $null; tier = 'Basic' }
                )
                sqlServers                = @([ordered]@{ name = 'sql1' })
                cosmosDbAccounts          = @([ordered]@{ name = 'cosmos1' })
                redisCaches               = @([ordered]@{ name = 'redis1'; sku = 'Standard' })
                postgreSqlFlexibleServers = @([ordered]@{ name = 'pg1' })
                mySqlFlexibleServers      = @([ordered]@{ name = 'my1' })
            }
            integration = [ordered]@{
                apiManagement      = @(
                    [ordered]@{ name = 'apim-prem'; sku = 'Premium' }
                    [ordered]@{ name = 'apim-dev'; sku = 'Developer' }
                )
                eventHubNamespaces = @(
                    [ordered]@{ name = 'eh-ok'; zoneRedundant = $true }
                    [ordered]@{ name = 'eh-bad'; zoneRedundant = $false }
                )
            }
        }
    }

    # ---- WARA: an estate where every automated rule passes --------------------------------------
    $script:WaraHealthy = [ordered]@{
        compute    = [ordered]@{
            virtualMachines = @([ordered]@{ id = $script:VmGood; name = 'vm-good'; zoneEligible = $true; zoneRedundant = $true; size = 'Standard_D2s_v5' })
        }
        management = [ordered]@{
            backupProtectedItems = @([ordered]@{ name = 'item1'; sourceResourceId = $script:VmGood })
            recoveryVaults       = @([ordered]@{ name = 'rsv-ok'; softDelete = 'Enabled'; storageType = 'GeoRedundant'; crossRegion = 'True' })
        }
        networking = [ordered]@{
            loadBalancers       = @([ordered]@{ name = 'lb-std'; sku = 'Standard' })
            applicationGateways = @([ordered]@{ name = 'agw-v2'; sku = 'WAF_v2'; tier = 'WAF_v2' })
            vpnGateways         = @(
                [ordered]@{ name = 'vpn-az'; gatewayType = 'Vpn'; sku = 'VpnGw1AZ'; activeActive = $true }
                [ordered]@{ name = 'er-az'; gatewayType = 'ExpressRoute'; sku = 'ErGw2AZ'; activeActive = $false }
            )
        }
        domains    = [ordered]@{
            storage     = [ordered]@{
                managedDisks    = @([ordered]@{ name = 'd-prem'; sku = 'Premium_ZRS'; diskState = 'Attached' })
                storageAccounts = @([ordered]@{ name = 's-gzrs'; sku = 'Standard_GZRS' })
            }
            security    = [ordered]@{ keyVaults = @([ordered]@{ name = 'kv-ok'; softDelete = $true; purgeProtection = $true }) }
            containers  = [ordered]@{
                aksClusters         = @([ordered]@{ name = 'aks-ok'; allPoolsZoned = $true; aadIntegrated = $true })
                containerRegistries = @([ordered]@{ name = 'acr-prem'; sku = 'Premium' })
            }
            web         = [ordered]@{ appServicePlans = @([ordered]@{ name = 'plan-p1'; sku = 'P1v3'; reserved = $false }) }
            databases   = [ordered]@{
                sqlDatabases = @(
                    [ordered]@{ name = 'master'; zoneRedundant = $false; tier = 'System' }
                    [ordered]@{ name = 'db-ok'; zoneRedundant = $true; tier = 'Premium' }
                )
            }
            integration = [ordered]@{
                apiManagement      = @([ordered]@{ name = 'apim-prem'; sku = 'Premium' })
                eventHubNamespaces = @([ordered]@{ name = 'eh-ok'; zoneRedundant = $true })
            }
        }
    }

    # ---- WARA: an estate with none of the services ----------------------------------------------
    $script:WaraEmpty = [ordered]@{
        compute    = [ordered]@{ virtualMachines = @() }
        management = [ordered]@{ backupProtectedItems = @(); recoveryVaults = @() }
        networking = [ordered]@{ loadBalancers = @(); applicationGateways = @(); vpnGateways = @(); expressRouteCircuits = @(); azureFirewalls = @() }
        domains    = [ordered]@{
            storage     = [ordered]@{ managedDisks = @(); storageAccounts = @() }
            security    = [ordered]@{ keyVaults = @() }
            containers  = [ordered]@{ aksClusters = @(); containerRegistries = @() }
            web         = [ordered]@{ appServicePlans = @() }
            databases   = [ordered]@{ sqlDatabases = @(); sqlServers = @(); cosmosDbAccounts = @(); redisCaches = @(); postgreSqlFlexibleServers = @(); mySqlFlexibleServers = @() }
            integration = [ordered]@{ apiManagement = @(); eventHubNamespaces = @() }
        }
    }

    $script:WaraBadFindings = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraBad -Assessment 'Microsoft: Well-Architected Reliability Assessment')
    $script:WaraBadById = ConvertTo-ScoutFindingMap $script:WaraBadFindings

    # ---- Advisor: a recommendation row, shaped as Import-AdvisorScores shapes it ----------------
    function New-AdvisorRow {
        param([string] $Category, [string] $Impact, [string] $Problem = 'Example problem')
        [ordered]@{
            Category = $Category; Impact = $Impact; ImpactedField = 'microsoft.compute/virtualmachines'
            ImpactedValue = 'res1'; Subscription = '00000000-0000-0000-0000-000000000001'
            ShortDescriptionProblem = $Problem; ShortDescriptionSolution = 'Example solution'
        }
    }
    $script:AdvisorBad = [ordered]@{
        advisorAvailable = $true
        advisor          = @(
            New-AdvisorRow -Category 'HighAvailability' -Impact 'High' -Problem 'Azure CDN Standard from Microsoft (classic) is retiring'
            New-AdvisorRow -Category 'HighAvailability' -Impact 'Medium'
            New-AdvisorRow -Category 'Security' -Impact 'High'
            New-AdvisorRow -Category 'Security' -Impact 'Medium'
            New-AdvisorRow -Category 'Security' -Impact 'Medium'
            New-AdvisorRow -Category 'Performance' -Impact 'Medium'
            New-AdvisorRow -Category 'Cost' -Impact 'High'
            New-AdvisorRow -Category 'Cost' -Impact 'Medium'
            New-AdvisorRow -Category 'OperationalExcellence' -Impact 'High' -Problem 'Create an Azure Service Health alert'
        )
        management       = [ordered]@{
            advisorScores = @(
                [ordered]@{ id = 'a'; name = 'Advisor'; subscriptionId = 's1'; lastRefreshedScore = 64.5 }
                [ordered]@{ id = 'b'; name = 'Advisor'; subscriptionId = 's2'; lastRefreshedScore = 88.0 }
            )
        }
        monitor          = [ordered]@{ activityLogAlertRules = @() }
    }
    $script:AdvisorClean = [ordered]@{
        advisorAvailable = $true
        advisor          = @()
        management       = [ordered]@{ advisorScores = @([ordered]@{ id = 'a'; name = 'Advisor'; subscriptionId = 's1'; lastRefreshedScore = 91.0 }) }
        monitor          = [ordered]@{ activityLogAlertRules = @() }
    }
    $script:AdvisorSkipped = [ordered]@{
        advisorAvailable = $false
        advisor          = @()
        management       = [ordered]@{ advisorScores = @() }
        monitor          = [ordered]@{ activityLogAlertRules = @() }
    }
    $script:AdvisorBadFindings = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $script:AdvisorBad -Assessment 'Microsoft: Azure Advisor')
    $script:AdvisorBadById = ConvertTo-ScoutFindingMap $script:AdvisorBadFindings
}

Describe 'WARA: Well-Architected Reliability Assessment (APRL-backed)' {
    BeforeAll {
        $script:WaraSet = & $script:Module { Get-RuleSet -Patterns 'wara.reliability' }
    }

    It 'loads one rule file named WARA with 31 rules, 21 automated and 10 manual' {
        @($script:WaraSet).Count | Should -Be 1
        $script:WaraSet.Framework | Should -Be 'WARA'
        $script:WaraSet.FrameworkVersion | Should -Not -BeNullOrEmpty
        @($script:WaraSet.Rules).Count | Should -Be 31
        @($script:WaraSet.Rules | Where-Object { -not $_.manual }).Count | Should -Be 21
        @($script:WaraSet.Rules | Where-Object { $_.manual }).Count | Should -Be 10
    }

    It 'has unique ids, and each title and remediation starts with its own id' {
        @($script:WaraSet.Rules.id | Select-Object -Unique).Count | Should -Be 31
        foreach ($r in $script:WaraSet.Rules) {
            $r.id | Should -Match '^WARA-[A-Z]+-[0-9]{2}$'
            $r.title | Should -BeLike "$($r.id).*"
            $r.remediation | Should -BeLike "$($r.id).*"
        }
    }

    It 'cites an APRL recommendation guid and a source URL on every rule, and gates every rule on its resource type' {
        foreach ($r in $script:WaraSet.Rules) {
            $r.aprl | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -Because "$($r.id) must name the APRL recommendation it paraphrases"
            $r.source | Should -BeLike 'https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2/tree/main/azure-resources/*' -Because "$($r.id) must cite its APRL folder"
            [string]$r.assert.gate | Should -Not -BeNullOrEmpty -Because "$($r.id) must report Not assessed on an estate without the service"
        }
    }

    It 'every rule id, and every guid it cites, is enumerated in the checklist doc' {
        $doc = Get-Content "$script:root/docs/frameworks/wara-aprl-checklist.md" -Raw
        foreach ($r in $script:WaraSet.Rules) {
            $doc | Should -Match ([regex]::Escape([string]$r.id))
            $doc | Should -Match ([regex]::Escape([string]$r.aprl))
        }
    }

    It 'carries no subscription resource id in the rule file or the doc' {
        $text = (Get-Content "$script:root/src/assess/rules/wara.reliability.yaml" -Raw) + (Get-Content "$script:root/docs/frameworks/wara-aprl-checklist.md" -Raw)
        # Only APRL recommendation guids are allowed; an ARM subscription path is not.
        $text | Should -Not -Match '/subscriptions/[0-9a-f]{8}-'
    }

    It 'produces no Error findings on the bad, healthy or empty estate' {
        @($script:WaraBadFindings | Where-Object Status -eq 'Error').Count | Should -Be 0
        $healthy = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraHealthy -Assessment 'x')
        @($healthy | Where-Object Status -eq 'Error').Count | Should -Be 0
        $empty = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraEmpty -Assessment 'x')
        @($empty | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'fails <Id> with <Count> offending resource(s)' -ForEach @(
        @{ Id = 'WARA-VM-01'; Count = 1 }     # vm-bad has no zone in a zone-capable region; vm-nozones is not eligible
        @{ Id = 'WARA-VM-02'; Count = 2 }     # vm-bad and vm-nozones have no protected item
        @{ Id = 'WARA-VM-03'; Count = 1 }     # Standard_B2s
        @{ Id = 'WARA-DSK-01'; Count = 1 }    # attached HDD; the unattached HDD and the Premium disk are not findings
        @{ Id = 'WARA-AKS-01'; Count = 1 }
        @{ Id = 'WARA-AKS-02'; Count = 1 }
        @{ Id = 'WARA-ACR-01'; Count = 1 }
        @{ Id = 'WARA-ASP-01'; Count = 1 }    # B1 only; P1v3 and the consumption Y1 plan are not findings
        @{ Id = 'WARA-SQL-01'; Count = 2 }    # db-bad and db-null; master and db-ok are not findings
        @{ Id = 'WARA-STG-01'; Count = 2 }    # Standard_LRS and Premium_LRS
        @{ Id = 'WARA-KV-01'; Count = 1 }     # only the explicit false; null reads as on
        @{ Id = 'WARA-KV-02'; Count = 2 }     # false and null both lack purge protection
        @{ Id = 'WARA-RSV-01'; Count = 1 }
        @{ Id = 'WARA-RSV-02'; Count = 1 }    # geo-redundant without cross-region restore; the LRS vault is not a finding
        @{ Id = 'WARA-LB-01'; Count = 1 }
        @{ Id = 'WARA-AGW-01'; Count = 2 }    # Standard and WAF are v1
        @{ Id = 'WARA-VPN-01'; Count = 2 }    # VpnGw2 and Basic
        @{ Id = 'WARA-VPN-02'; Count = 2 }    # VpnGw2 and VpnGw2AZ; Basic is excluded, the active-active gateway passes
        @{ Id = 'WARA-ER-01'; Count = 1 }     # the Standard ExpressRoute gateway
        @{ Id = 'WARA-APIM-01'; Count = 1 }
        @{ Id = 'WARA-EH-01'; Count = 1 }
    ) {
        $script:WaraBadById[$Id].Status | Should -Be 'Fail'
        $script:WaraBadById[$Id].EvidenceCount | Should -Be $Count
    }

    It 'reports <Id> as Manual with its evidence attached' -ForEach @(
        @{ Id = 'WARA-AKS-03' }, @{ Id = 'WARA-ASP-02' }, @{ Id = 'WARA-SQL-02' }, @{ Id = 'WARA-COSMOS-01' },
        @{ Id = 'WARA-REDIS-01' }, @{ Id = 'WARA-PGSQL-01' }, @{ Id = 'WARA-MYSQL-01' }, @{ Id = 'WARA-AGW-02' },
        @{ Id = 'WARA-ER-02' }, @{ Id = 'WARA-FW-01' }
    ) {
        $script:WaraBadById[$Id].Status | Should -Be 'Manual'
        $script:WaraBadById[$Id].EvidenceCount | Should -BeGreaterThan 0
    }

    It 'passes every automated rule on the healthy estate' {
        $healthy = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraHealthy -Assessment 'x')
        $automated = @($script:WaraSet.Rules | Where-Object { -not $_.manual } | ForEach-Object { $_.id })
        $automated.Count | Should -Be 21
        foreach ($id in $automated) {
            ($healthy | Where-Object Id -eq $id).Status | Should -Be 'Pass' -Because "$id must pass an estate that meets its condition"
        }
    }

    It 'reports every rule NotAssessed on an estate with none of the services' {
        $empty = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $script:WaraEmpty -Assessment 'x')
        @($empty | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Manual', 'Error' }).Count | Should -Be 0
        @($empty | Where-Object Status -eq 'NotAssessed').Count | Should -Be 31
    }

    It 'does not fail a SQL estate that holds only the master system database' {
        $onlyMaster = [ordered]@{ domains = [ordered]@{ databases = [ordered]@{ sqlDatabases = @([ordered]@{ name = 'master'; zoneRedundant = $false; tier = 'System' }) } } }
        $f = @(Invoke-ScoutTestRuleSet -Pattern 'wara.reliability' -Collect $onlyMaster -Assessment 'x') | Where-Object Id -eq 'WARA-SQL-01'
        $f.Status | Should -Be 'NotAssessed'
    }
}

Describe 'ADVISOR: Azure Advisor recommendations assessment' {
    BeforeAll {
        $script:AdvisorSet = & $script:Module { Get-RuleSet -Patterns 'advisor.recommendations' }
        $script:AdvisorAutomated = @('ADVISOR-RE-01', 'ADVISOR-RE-02', 'ADVISOR-RE-03', 'ADVISOR-SE-01', 'ADVISOR-SE-02', 'ADVISOR-PE-01', 'ADVISOR-PE-02', 'ADVISOR-CO-01', 'ADVISOR-CO-02', 'ADVISOR-OE-01', 'ADVISOR-OE-02')
    }

    It 'loads one rule file named ADVISOR with 15 rules, 12 automated and 3 manual' {
        @($script:AdvisorSet).Count | Should -Be 1
        $script:AdvisorSet.Framework | Should -Be 'ADVISOR'
        $script:AdvisorSet.FrameworkVersion | Should -Not -BeNullOrEmpty
        @($script:AdvisorSet.Rules).Count | Should -Be 15
        @($script:AdvisorSet.Rules | Where-Object { -not $_.manual }).Count | Should -Be 12
        @($script:AdvisorSet.Rules | Where-Object { $_.manual }).Count | Should -Be 3
    }

    It 'has unique ids, and each title and remediation starts with its own id' {
        @($script:AdvisorSet.Rules.id | Select-Object -Unique).Count | Should -Be 15
        foreach ($r in $script:AdvisorSet.Rules) {
            $r.title | Should -BeLike "$($r.id).*"
            $r.remediation | Should -BeLike "$($r.id).*"
        }
    }

    It 'every rule id is enumerated in the Advisor doc' {
        $doc = Get-Content "$script:root/docs/frameworks/advisor-recommendations.md" -Raw
        foreach ($r in $script:AdvisorSet.Rules) { $doc | Should -Match ([regex]::Escape([string]$r.id)) }
    }

    It 'gates every rule that reads $.advisor on advisorAvailable and no other rule' {
        foreach ($r in $script:AdvisorSet.Rules) {
            $query = [string]$r.query
            $gate = if ($r.assert.ContainsKey('gate')) { [string]$r.assert.gate } else { '' }
            if ($query.StartsWith('$.advisor[')) { $gate | Should -Be '$.advisorAvailable' -Because "$($r.id) reads Advisor rows" }
            else { $gate | Should -Not -Be '$.advisorAvailable' -Because "$($r.id) does not read Advisor rows" }
        }
    }

    It 'produces no Error findings on the bad, clean or skipped estate' {
        @($script:AdvisorBadFindings | Where-Object Status -eq 'Error').Count | Should -Be 0
        foreach ($c in $script:AdvisorClean, $script:AdvisorSkipped) {
            @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $c -Assessment 'x' | Where-Object Status -eq 'Error').Count | Should -Be 0
        }
    }

    It 'scores <Id> as <Status> with <Count> row(s)' -ForEach @(
        @{ Id = 'ADVISOR-RE-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-RE-02'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-RE-03'; Status = 'Fail'; Count = 1 }   # the retiring-service row
        @{ Id = 'ADVISOR-SE-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-SE-02'; Status = 'Fail'; Count = 2 }
        @{ Id = 'ADVISOR-PE-01'; Status = 'Pass'; Count = 0 }   # no High performance row
        @{ Id = 'ADVISOR-PE-02'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-CO-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-CO-02'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-OE-01'; Status = 'Fail'; Count = 1 }
        @{ Id = 'ADVISOR-OE-02'; Status = 'Pass'; Count = 0 }   # no Medium operational row
        @{ Id = 'ADVISOR-SC-01'; Status = 'Fail'; Count = 1 }   # one score of 64.5
    ) {
        $script:AdvisorBadById[$Id].Status | Should -Be $Status
        $script:AdvisorBadById[$Id].EvidenceCount | Should -Be $Count
    }

    It 'reports the three governance items Manual' {
        foreach ($id in 'ADVISOR-GOV-01', 'ADVISOR-GOV-02', 'ADVISOR-GOV-03') {
            $script:AdvisorBadById[$id].Status | Should -Be 'Manual'
        }
    }

    It 'passes every automated rule when Advisor was read and reported nothing' {
        $findings = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $script:AdvisorClean -Assessment 'x')
        foreach ($id in ($script:AdvisorAutomated + 'ADVISOR-SC-01')) {
            ($findings | Where-Object Id -eq $id).Status | Should -Be 'Pass' -Because "$id has nothing to report"
        }
    }

    It 'reports every Advisor-backed rule NotAssessed, not Pass, when Advisor was skipped' {
        $findings = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $script:AdvisorSkipped -Assessment 'x')
        foreach ($id in ($script:AdvisorAutomated + 'ADVISOR-SC-01')) {
            ($findings | Where-Object Id -eq $id).Status | Should -Be 'NotAssessed' -Because "$id must not pass an estate whose Advisor data was never read"
        }
    }

    It 'matches the retirement rule only on retirement wording' {
        $c = [ordered]@{
            advisorAvailable = $true
            advisor          = @(
                New-AdvisorRow -Category 'OperationalExcellence' -Impact 'Medium' -Problem 'Create an Azure Service Health alert'
                New-AdvisorRow -Category 'Cost' -Impact 'Medium' -Problem 'Right-size or shutdown underutilized virtual machines'
            )
        }
        $f = @(Invoke-ScoutTestRuleSet -Pattern 'advisor.recommendations' -Collect $c -Assessment 'x') | Where-Object Id -eq 'ADVISOR-RE-03'
        $f.Status | Should -Be 'Pass'
    }
}
