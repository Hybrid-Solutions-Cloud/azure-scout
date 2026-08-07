#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7063 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Defender-for-Cloud detail plumbing.

    manifests/collectors/Security/*.psd1 has 17 collectors; before this pass only 4 (defenderPlans,
    keyVaults, keyVaultKeys, keyVaultSecrets) reached the assessment payload the React report
    renders. This closes the gap for the three collectors that ARE ordinary ARG-indexed types --
    WafPolicies, DdosProtectionPlans, ApplicationSecurityGroups -- the same class of defect and fix
    pattern AB#7064/AB#7065/AB#7066 already used.

    DefenderAlerts.psd1, DefenderAssessments.psd1, DefenderSecureScore.psd1 and DefenderPricing.psd1
    are deliberately NOT covered here -- they all declare the synthetic
    AZSC/Subscription/SecurityPolicySweep type, and the only code that populates that sweep today
    (Get-ScoutDefenderPlanSweep.ps1) calls exactly one REST endpoint
    (Microsoft.Security/pricings), never /alerts, /assessments or /secureScores. There is no
    existing data for those three to shape; DefenderPricing duplicates the plans/pricing data
    `security.defenderPlans` already carries. See Invoke-Collect.ps1's query-pack comment above
    `wafPolicies` for the full reasoning. This test file therefore also pins that `security`
    carries exactly the four keys this pass produces -- defenderPlans plus the three new ones --
    so a future change that silently adds/duplicates a Defender-detail key gets caught.

    Two collection paths must both reach every key:
      - Invoke-Collect -Source TypedQueries (the live KQL query pack)
      - Invoke-Collect -FromInventory / the default inverted path (ConvertFrom-ScoutInventory)

    Search-AzGraph is mocked throughout. No live Azure connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    $script:DefenderDetailKeys = @('wafPolicies', 'ddosProtectionPlans', 'applicationSecurityGroups')

    function New-MockSubscriptionRow {
        param([string] $Id = 'aaa')
        [pscustomobject]@{
            id = "/subscriptions/$Id"; name = "sub-$Id"; type = 'microsoft.resources/subscriptions'
            subscriptionId = $Id; location = $null; resourceGroup = $null
            kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
            extendedLocation = $null; managedBy = $null; tenantId = 'ten'
            properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null
        }
    }

    function Get-FixtureDefenderDetailRows {
        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.network/applicationgatewaywebapplicationfirewallpolicies/waf1'
                name = 'waf1'; type = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'
                location = 'eastus'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = [pscustomobject]@{ name = 'WAF_v2' }; plan = $null; identity = $null
                zones = $null; extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'
                    policySettings    = [pscustomobject]@{ state = 'Enabled'; mode = 'Prevention' }
                    managedRules      = [pscustomobject]@{ managedRuleSets = @([pscustomobject]@{ ruleSetType = 'OWASP'; ruleSetVersion = '3.2' }) }
                    customRules       = @([pscustomobject]@{ name = 'block-bad-ip' }, [pscustomobject]@{ name = 'rate-limit' })
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.network/frontdoorwebapplicationfirewallpolicies/waf2'
                name = 'waf2'; type = 'microsoft.network/frontdoorwebapplicationfirewallpolicies'
                location = 'Global'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = [pscustomobject]@{ name = 'Premium_AzureFrontDoor' }; plan = $null; identity = $null
                zones = $null; extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'
                    policySettings    = [pscustomobject]@{ enabledState = 'Enabled'; mode = 'Detection' }
                    managedRules      = [pscustomobject]@{ managedRuleSets = @() }
                    customRules       = [pscustomobject]@{ rules = @([pscustomobject]@{ name = 'geo-block' }) }
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.network/ddosprotectionplans/ddos1'
                name = 'ddos1'; type = 'microsoft.network/ddosprotectionplans'
                location = 'eastus'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'
                    virtualNetworks   = @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Network/virtualNetworks/vnet1' })
                    resourceGuid      = '11111111-2222-3333-4444-555555555555'
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/microsoft.network/applicationsecuritygroups/asg1'
                name = 'asg1'; type = 'microsoft.network/applicationsecuritygroups'
                location = 'eastus'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    provisioningState = 'Succeeded'
                    resourceGuid      = '66666666-7777-8888-9999-000000000000'
                }
            }
        )
    }
}

Describe 'ConvertFrom-ScoutInventory -- Defender-for-Cloud detail plumbing (AB#7063)' {

    It 'shapes every one of the three new keys, populated from the raw rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureDefenderDetailRows) -ResourceContainers @(New-MockSubscriptionRow)

        $shaped.ContainsKey('wafPolicies') | Should -BeTrue
        @($shaped['wafPolicies']).Count | Should -Be 2 -Because 'the fixture carries one appgw WAF policy and one Front Door WAF policy'

        $shaped.ContainsKey('ddosProtectionPlans') | Should -BeTrue
        @($shaped['ddosProtectionPlans']).Count | Should -Be 1

        $shaped.ContainsKey('applicationSecurityGroups') | Should -BeTrue
        @($shaped['applicationSecurityGroups']).Count | Should -Be 1
    }

    It 'shapes every key as an empty array (never throws, never missing) on an empty estate' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        foreach ($key in $script:DefenderDetailKeys) {
            $shaped.ContainsKey($key) | Should -BeTrue
            @($shaped[$key]).Count | Should -Be 0
        }
    }

    It 'projects wafPolicies scalar fields correctly, including cross-type enabledState/customRuleCount coalescing' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureDefenderDetailRows) -ResourceContainers @(New-MockSubscriptionRow)
        $rows = @($shaped['wafPolicies'])

        $appgw = $rows | Where-Object { $_.name -eq 'waf1' }
        $appgw.type | Should -Be 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'
        $appgw.sku | Should -Be 'WAF_v2'
        $appgw.provisioningState | Should -Be 'Succeeded'
        $appgw.enabledState | Should -Be 'Enabled' -Because 'appgw policies expose policySettings.state, not .enabledState'
        $appgw.mode | Should -Be 'Prevention'
        $appgw.managedRuleSetCount | Should -Be 1
        $appgw.customRuleCount | Should -Be 2 -Because 'appgw customRules is a bare array, no .rules wrapper'

        $frontdoor = $rows | Where-Object { $_.name -eq 'waf2' }
        $frontdoor.type | Should -Be 'microsoft.network/frontdoorwebapplicationfirewallpolicies'
        $frontdoor.enabledState | Should -Be 'Enabled' -Because 'front door policies expose policySettings.enabledState'
        $frontdoor.mode | Should -Be 'Detection'
        $frontdoor.managedRuleSetCount | Should -Be 0
        $frontdoor.customRuleCount | Should -Be 1 -Because 'front door customRules wraps the array under .rules'
    }

    It 'projects ddosProtectionPlans scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureDefenderDetailRows) -ResourceContainers @(New-MockSubscriptionRow)
        $ddos = $shaped['ddosProtectionPlans'][0]
        $ddos.name | Should -Be 'ddos1'
        $ddos.provisioningState | Should -Be 'Succeeded'
        $ddos.protectedVNetCount | Should -Be 1
        $ddos.resourceGuid | Should -Be '11111111-2222-3333-4444-555555555555'
    }

    It 'projects applicationSecurityGroups scalar fields correctly' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixtureDefenderDetailRows) -ResourceContainers @(New-MockSubscriptionRow)
        $asg = $shaped['applicationSecurityGroups'][0]
        $asg.name | Should -Be 'asg1'
        $asg.provisioningState | Should -Be 'Succeeded'
        $asg.resourceGuid | Should -Be '66666666-7777-8888-9999-000000000000'
    }
}

Describe 'Invoke-Collect -- Defender-detail keys reach the canonical contract on both paths (AB#7063)' {

    It 'the typed-query path (-Source TypedQueries) populates collect.security.wafPolicies/ddosProtectionPlans/applicationSecurityGroups' {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'webapplicationfirewallpolicies') {
                return @([pscustomobject]@{ id = 'waf1'; name = 'waf1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'; type = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'
                        sku = 'WAF_v2'; provisioningState = 'Succeeded'; enabledState = 'Enabled'; mode = 'Prevention'; managedRuleSetCount = 1; customRuleCount = 2 })
            }
            if ($Query -match 'ddosprotectionplans') {
                return @([pscustomobject]@{ id = 'ddos1'; name = 'ddos1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; protectedVNetCount = 1; resourceGuid = 'guid-ddos' })
            }
            if ($Query -match 'applicationsecuritygroups') {
                return @([pscustomobject]@{ id = 'asg1'; name = 'asg1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'; location = 'eastus'
                        provisioningState = 'Succeeded'; resourceGuid = 'guid-asg' })
            }
            return @()
        }

        try {
            $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

            $collect.security.PSObject.Properties.Name | Should -Contain 'wafPolicies'
            $collect.security.PSObject.Properties.Name | Should -Contain 'ddosProtectionPlans'
            $collect.security.PSObject.Properties.Name | Should -Contain 'applicationSecurityGroups'

            @($collect.security.wafPolicies).Count | Should -Be 1
            @($collect.security.ddosProtectionPlans).Count | Should -Be 1
            @($collect.security.applicationSecurityGroups).Count | Should -Be 1

            $collect.security.wafPolicies[0].name | Should -Be 'waf1'
            $collect.security.ddosProtectionPlans[0].resourceGuid | Should -Be 'guid-ddos'
            $collect.security.applicationSecurityGroups[0].resourceGuid | Should -Be 'guid-asg'
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'the default inverted path (-FromInventory) populates collect.security.* from raw rows' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixtureDefenderDetailRows
            ResourceContainers = @(New-MockSubscriptionRow)
        }

        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            # Only sqlDefenderPricing is a live query on the inverted path; every Defender-detail
            # key must come from the raw rows already handed in via -FromInventory.
            return @()
        }

        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue

            @($collect.security.wafPolicies).Count | Should -Be 2
            @($collect.security.ddosProtectionPlans).Count | Should -Be 1
            @($collect.security.applicationSecurityGroups).Count | Should -Be 1

            $collect.security.applicationSecurityGroups[0].name | Should -Be 'asg1'
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'every Defender-detail key is present, even as an empty array, on a completely empty estate' {
        $inventory = [pscustomobject]@{ Resources = @(); ResourceContainers = @() }
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            return @()
        }
        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue
            foreach ($key in $script:DefenderDetailKeys) {
                { @($collect.security.$key).Count } | Should -Not -Throw
                @($collect.security.$key).Count | Should -Be 0
            }
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'carries exactly defenderPlans plus the three AB#7063 keys under security -- no DefenderAlerts/Assessments/SecureScore/Pricing key was force-fitted' {
        $inventory = [pscustomobject]@{ Resources = @(); ResourceContainers = @() }
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            return @()
        }
        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue
            $collect.security.PSObject.Properties.Name | Should -Be @('defenderPlans', 'wafPolicies', 'ddosProtectionPlans', 'applicationSecurityGroups')
        }
        finally {
            Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }
}
