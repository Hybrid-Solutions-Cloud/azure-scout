#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent

    $script:PolicySweepLedger = [System.Collections.Generic.List[string]]::new()
    $script:DefenderPlanLedger = [System.Collections.Generic.List[string]]::new()
    $script:ArgLedger = [System.Collections.Generic.List[string]]::new()
    $script:PolicySweepResponder = $null
    $script:DefenderPlanResponder = $null

    function global:Search-AzGraph {
        param(
            [string] $Query,
            [int] $First,
            [int] $Skip,
            [string] $SkipToken,
            [string] $ManagementGroup,
            [string[]] $Subscription,
            [string] $ErrorAction
        )
        $null = $First, $Skip, $SkipToken, $ManagementGroup, $Subscription, $ErrorAction
        $script:ArgLedger.Add([string]$Query)
        return @()
    }

    function global:Get-ScoutSubscriptionSecurityPolicySweep {
        param([object[]] $Subscriptions)
        foreach ($subscription in @($Subscriptions)) { $script:PolicySweepLedger.Add([string]$subscription.id) }
        if ($script:PolicySweepResponder) { return @(& $script:PolicySweepResponder $Subscriptions) }
        return @()
    }

    function global:Get-ScoutDefenderPlanSweep {
        param([object[]] $Subscriptions)
        foreach ($subscription in @($Subscriptions)) { $script:DefenderPlanLedger.Add([string]$subscription.id) }
        if ($script:DefenderPlanResponder) { return @(& $script:DefenderPlanResponder $Subscriptions) }
        return @()
    }

    function global:Get-ScoutExternalIdentitiesPolicy {
        param([string] $TenantID)
        $null = $TenantID
        return [pscustomobject]@{ Collected = $false }
    }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    function New-ReuseSubscriptionContainer {
        param([Parameter(Mandatory)] [string] $Id)
        [pscustomobject]@{
            id = "/subscriptions/$Id"; name = "name-$Id"; type = 'microsoft.resources/subscriptions'
            subscriptionId = $Id; tenantId = 'tenant-test'; resourceGroup = $null; location = $null
            kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
            extendedLocation = $null; managedBy = $null; tags = $null
            properties = [pscustomobject]@{ state = 'Enabled' }
        }
    }

    function New-ReuseSweep {
        param(
            [Parameter(Mandatory)] [string] $SubscriptionId,
            [ValidateSet('Populated', 'SuccessEmpty', 'Unavailable')]
            [string] $Mode = 'Populated'
        )
        $status = if ($Mode -eq 'Unavailable') { 'Unavailable' } else { 'Success' }
        $suffix = $SubscriptionId.Replace('sub-', '')
        $data = if ($Mode -eq 'Populated') {
            [ordered]@{
                DefenderPricing = @([pscustomobject]@{
                        Id = "/subscriptions/$SubscriptionId/providers/Microsoft.Security/pricings/VirtualMachines"
                        Name = 'VirtualMachines'; PricingTier = 'Standard'; SubPlan = 'P2'
                    })
                DefenderAlerts = @([pscustomobject]@{ Id = "alert-$suffix"; AlertDisplayName = "alert-$suffix" })
                DefenderAssessments = @([pscustomobject]@{ Id = "assessment-$suffix"; DisplayName = "assessment-$suffix" })
                DefenderSecureScores = @([pscustomobject]@{ Id = "score-$suffix"; DisplayName = "score-$suffix" })
                PolicyComplianceStates = @([pscustomobject]@{ Id = "policy-$suffix"; ComplianceState = 'Compliant' })
            }
        }
        else {
            [ordered]@{
                DefenderPricing = @(); DefenderAlerts = @(); DefenderAssessments = @()
                DefenderSecureScores = @(); PolicyComplianceStates = @()
            }
        }
        $data.CollectionStatus = [pscustomobject]@{
            DefenderPricing = $status; DefenderAlerts = $status; DefenderAssessments = $status
            DefenderSecureScores = $status; PolicyComplianceStates = $status
        }
        $data.CollectionErrors = if ($Mode -eq 'Unavailable') {
            @([pscustomobject]@{ Dataset = 'DefenderPricing'; Message = 'provider unavailable' })
        }
        else { @() }

        [pscustomobject]@{
            id = "/subscriptions/$SubscriptionId/providers/AzureScout/securityPolicySweep/default"
            name = 'default'; type = 'AZSC/Subscription/SecurityPolicySweep'
            subscriptionId = $SubscriptionId; subscriptionName = "name-$SubscriptionId"
            properties = [pscustomobject]$data
        }
    }

    function New-ReuseInventory {
        param([string[]] $SubscriptionIds, [object[]] $Sweeps = @())
        [pscustomobject]@{
            Resources = @($Sweeps)
            ResourceContainers = @($SubscriptionIds | ForEach-Object { New-ReuseSubscriptionContainer -Id $_ })
        }
    }
}

AfterAll {
    Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
    Remove-Item function:Get-ScoutSubscriptionSecurityPolicySweep -ErrorAction SilentlyContinue
    Remove-Item function:Get-ScoutDefenderPlanSweep -ErrorAction SilentlyContinue
    Remove-Item function:Get-ScoutExternalIdentitiesPolicy -ErrorAction SilentlyContinue
}

Describe 'Invoke-Collect security/policy invocation-local reuse' {
    BeforeEach {
        $script:PolicySweepLedger.Clear()
        $script:DefenderPlanLedger.Clear()
        $script:ArgLedger.Clear()
        $script:PolicySweepResponder = $null
        $script:DefenderPlanResponder = $null
    }

    It 'reuses populated inventory sweeps without repeating Defender or policy calls and orders rows deterministically' {
        $inventory = New-ReuseInventory -SubscriptionIds @('sub-b', 'sub-a') -Sweeps @(
            (New-ReuseSweep -SubscriptionId 'sub-b'),
            (New-ReuseSweep -SubscriptionId 'sub-a')
        )

        $collect = Invoke-Collect -FromInventory $inventory -IncludePolicyCompliance -WarningAction SilentlyContinue

        @($script:PolicySweepLedger).Count | Should -Be 0
        @($script:DefenderPlanLedger).Count | Should -Be 0
        @($collect.security.defenderPlans).subscriptionId | Should -Be @('sub-a', 'sub-b')
        @($collect.security.defenderAlerts).SubscriptionId | Should -Be @('sub-a', 'sub-b')
        @($collect.domains.management.policyComplianceStates).SubscriptionId | Should -Be @('sub-a', 'sub-b')
        $collect.security.defenderPlans[0].properties.pricingTier | Should -Be 'Standard'
    }

    It 'does not reinterpret successful-empty or explicitly unavailable datasets as missing' {
        $inventory = New-ReuseInventory -SubscriptionIds @('sub-success', 'sub-unavailable') -Sweeps @(
            (New-ReuseSweep -SubscriptionId 'sub-success' -Mode SuccessEmpty),
            (New-ReuseSweep -SubscriptionId 'sub-unavailable' -Mode Unavailable)
        )

        $collect = Invoke-Collect -FromInventory $inventory -IncludePolicyCompliance -WarningAction SilentlyContinue

        @($script:PolicySweepLedger).Count | Should -Be 0
        @($script:DefenderPlanLedger).Count | Should -Be 0
        @($collect.security.defenderPlans).Count | Should -Be 0
        @($collect.security.defenderAlerts).Count | Should -Be 0
        @($collect.domains.management.policyComplianceStates).Count | Should -Be 0
    }

    It 'falls back only for the subscription genuinely absent from the completed inventory sweep' {
        $inventory = New-ReuseInventory -SubscriptionIds @('sub-a', 'sub-b') -Sweeps @(
            (New-ReuseSweep -SubscriptionId 'sub-a')
        )
        $script:PolicySweepResponder = {
            param($Subscriptions)
            foreach ($subscription in $Subscriptions) { New-ReuseSweep -SubscriptionId ([string]$subscription.id) }
        }

        $collect = Invoke-Collect -FromInventory $inventory -IncludePolicyCompliance -WarningAction SilentlyContinue

        @($script:PolicySweepLedger) | Should -Be @('sub-b')
        # The missing policy sweep also supplies DefenderPricing, so the Defender-only ARM helper
        # must not query that same subscription a second time in this invocation.
        @($script:DefenderPlanLedger).Count | Should -Be 0
        @($collect.security.defenderPlans).subscriptionId | Should -Be @('sub-a', 'sub-b')
        @($collect.security.defenderAlerts).SubscriptionId | Should -Be @('sub-a', 'sub-b')
    }

    It 'uses the Defender-only fallback for only missing subscriptions when policy detail is not requested' {
        $inventory = New-ReuseInventory -SubscriptionIds @('sub-a', 'sub-b') -Sweeps @(
            (New-ReuseSweep -SubscriptionId 'sub-a')
        )
        $script:DefenderPlanResponder = {
            param($Subscriptions)
            foreach ($subscription in $Subscriptions) {
                [pscustomobject]@{
                    id = "/subscriptions/$($subscription.id)/providers/Microsoft.Security/pricings/VirtualMachines"
                    name = 'VirtualMachines'; subscriptionId = [string]$subscription.id
                    subscriptionName = "name-$($subscription.id)"
                    properties = [pscustomobject]@{ pricingTier = 'Free'; subPlan = $null }
                }
            }
        }

        $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue

        @($script:PolicySweepLedger).Count | Should -Be 0
        @($script:DefenderPlanLedger) | Should -Be @('sub-b')
        @($collect.security.defenderPlans).subscriptionId | Should -Be @('sub-a', 'sub-b')
    }

    It 'keeps OfflineFromInventory network-free while still reusing supplied local datasets' {
        $inventory = New-ReuseInventory -SubscriptionIds @('sub-a', 'sub-missing') -Sweeps @(
            (New-ReuseSweep -SubscriptionId 'sub-a')
        )

        $collect = Invoke-Collect -FromInventory $inventory -OfflineFromInventory `
            -IncludePolicyCompliance -WarningAction SilentlyContinue

        @($script:ArgLedger).Count | Should -Be 0
        @($script:PolicySweepLedger).Count | Should -Be 0
        @($script:DefenderPlanLedger).Count | Should -Be 0
        @($collect.security.defenderPlans).subscriptionId | Should -Be @('sub-a')
        @($collect.security.defenderAlerts).SubscriptionId | Should -Be @('sub-a')
    }
}
