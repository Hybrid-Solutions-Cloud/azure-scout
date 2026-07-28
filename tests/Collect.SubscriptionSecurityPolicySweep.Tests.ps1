#Requires -Version 7.0
#Requires -Modules Pester

<#
    Focused, offline tests for the AB#5638 subscription security/policy collect phase.
    Every Azure command is stubbed; these tests never require credentials or network access.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    . "$script:root/src/collect/Get-ScoutSubscriptionSecurityPolicySweep.ps1"

    $script:subscriptions = @(
        [pscustomobject]@{ id = 'sub-1'; name = 'First subscription' }
        [pscustomobject]@{ id = 'sub-2'; name = 'Second subscription' }
    )

    function Initialize-ScoutSweepStub {
        $script:currentSubscription = 'original-sub'
        $script:contextCalls = [System.Collections.Generic.List[string]]::new()
        $script:assessmentAttempts = @{}
        $script:sleepCalls = [System.Collections.Generic.List[int]]::new()
        $script:failPolicySubscription = $null
        $script:retryAssessmentSubscription = $null
        $script:unregisteredPricingSubscription = $null
        $script:failContextSubscription = $null

        function global:Get-AzContext {
            param($ErrorAction)
            $null = $ErrorAction
            [pscustomobject]@{
                Subscription = [pscustomobject]@{ Id = 'original-sub' }
            }
        }

        function global:Set-AzContext {
            param($SubscriptionId, $ErrorAction)
            $null = $ErrorAction
            if ($SubscriptionId -eq $script:failContextSubscription) {
                throw "Cannot enter $SubscriptionId"
            }
            $script:currentSubscription = $SubscriptionId
            $script:contextCalls.Add($SubscriptionId)
        }

        function global:Get-AzSecurityAlert {
            param($ErrorAction)
            $null = $ErrorAction
            [pscustomobject]@{ Name = "alert-$script:currentSubscription" }
        }

        function global:Get-AzSecurityAssessment {
            param($ErrorAction)
            $null = $ErrorAction
            $subId = $script:currentSubscription
            if (-not $script:assessmentAttempts.ContainsKey($subId)) {
                $script:assessmentAttempts[$subId] = 0
            }
            $script:assessmentAttempts[$subId]++
            if (
                $subId -eq $script:retryAssessmentSubscription -and
                $script:assessmentAttempts[$subId] -lt 3
            ) {
                throw 'HTTP 500 InternalServerError'
            }
            [pscustomobject]@{ Name = "assessment-$subId" }
        }

        function global:Get-AzSecurityPricing {
            param($ErrorAction)
            $null = $ErrorAction
            if ($script:currentSubscription -eq $script:unregisteredPricingSubscription) {
                throw "Subscription is not registered to use namespace 'Microsoft.Security'"
            }
            [pscustomobject]@{ Name = "pricing-$script:currentSubscription" }
        }

        function global:Get-AzSecuritySecureScore {
            param($ErrorAction)
            $null = $ErrorAction
            [pscustomobject]@{ Name = "score-$script:currentSubscription" }
        }

        function global:Get-AzSecuritySecureScoreControl {
            param($ErrorAction)
            $null = $ErrorAction
            [pscustomobject]@{ Name = "control-$script:currentSubscription" }
        }

        function global:Get-AzDiagnosticSetting {
            param($ResourceId, $ErrorAction)
            $null = $ErrorAction
            [pscustomobject]@{ Name = "diagnostic-$script:currentSubscription"; ResourceId = $ResourceId }
        }

        function global:Get-AzPolicyState {
            param($SubscriptionId, $ErrorAction)
            $null = $ErrorAction
            if ($SubscriptionId -eq $script:failPolicySubscription) {
                throw 'Policy Insights access denied'
            }
            [pscustomobject]@{ PolicyAssignmentName = "policy-$SubscriptionId" }
        }

        function global:Start-Sleep {
            param([int] $Milliseconds)
            $script:sleepCalls.Add($Milliseconds)
        }
    }

    function Clear-ScoutSweepStub {
        foreach ($name in @(
                'Get-AzContext',
                'Set-AzContext',
                'Get-AzSecurityAlert',
                'Get-AzSecurityAssessment',
                'Get-AzSecurityPricing',
                'Get-AzSecuritySecureScore',
                'Get-AzSecuritySecureScoreControl',
                'Get-AzDiagnosticSetting',
                'Get-AzPolicyState',
                'Start-Sleep'
            )) {
            if (Test-Path "Function:\$name") {
                Remove-Item "Function:\$name" -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Get-ScoutSubscriptionSecurityPolicySweep integration contract' {
    BeforeEach {
        Initialize-ScoutSweepStub
    }

    AfterEach {
        Clear-ScoutSweepStub
    }

    It 'returns one complete, typed envelope per subscription' {
        $results = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions $script:subscriptions)

        $results.Count | Should -Be 2
        $results[0].type | Should -Be 'AZSC/Subscription/SecurityPolicySweep'
        $results[0].subscriptionId | Should -Be 'sub-1'
        $results[0].subscriptionName | Should -Be 'First subscription'
        $results[0].properties.DefenderAlerts[0].Name | Should -Be 'alert-sub-1'
        $results[0].properties.DefenderAssessments[0].Name | Should -Be 'assessment-sub-1'
        $results[0].properties.DefenderPricing[0].Name | Should -Be 'pricing-sub-1'
        $results[0].properties.DefenderSecureScores[0].Name | Should -Be 'score-sub-1'
        $results[0].properties.DefenderSecureScoreControls[0].Name | Should -Be 'control-sub-1'
        $results[0].properties.SubscriptionDiagnosticSettings[0].ResourceId | Should -Be '/subscriptions/sub-1'
        $results[0].properties.PolicyComplianceStates[0].PolicyAssignmentName | Should -Be 'policy-sub-1'
        @($results[0].properties.CollectionErrors).Count | Should -Be 0

        @($results[0].properties.PSObject.Properties.Name) | Should -Be @(
            'DefenderAlerts',
            'DefenderAssessments',
            'DefenderPricing',
            'DefenderSecureScores',
            'DefenderSecureScoreControls',
            'SubscriptionDiagnosticSettings',
            'PolicyComplianceStates',
            'CollectionStatus',
            'CollectionErrors'
        )
    }

    It 'enters each subscription once and restores the original context' {
        Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions $script:subscriptions | Out-Null

        @($script:contextCalls) | Should -Be @('sub-1', 'sub-2', 'original-sub')
    }

    It 'isolates a failed dataset to the affected subscription' {
        $script:failPolicySubscription = 'sub-2'

        $results = @(
            Get-ScoutSubscriptionSecurityPolicySweep `
                -Subscriptions $script:subscriptions `
                -WarningAction SilentlyContinue
        )

        @($results[0].properties.PolicyComplianceStates).Count | Should -Be 1
        @($results[1].properties.PolicyComplianceStates).Count | Should -Be 0
        @($results[1].properties.DefenderAlerts).Count | Should -Be 1
        $results[1].properties.CollectionStatus.PolicyComplianceStates | Should -Be 'Unavailable'
        @($results[1].properties.CollectionErrors).Count | Should -Be 1
        $results[1].properties.CollectionErrors[0].Dataset | Should -Be 'PolicyComplianceStates'
    }

    It 'retries a transient Defender assessment failure with bounded backoff' {
        $script:retryAssessmentSubscription = 'sub-1'

        $results = @(
            Get-ScoutSubscriptionSecurityPolicySweep `
                -Subscriptions @($script:subscriptions[0])
        )

        $script:assessmentAttempts['sub-1'] | Should -Be 3
        @($script:sleepCalls) | Should -Be @(200, 400)
        $results[0].properties.DefenderAssessments[0].Name | Should -Be 'assessment-sub-1'
        $results[0].properties.CollectionStatus.DefenderAssessments | Should -Be 'Success'
    }

    It 'treats an unregistered Microsoft.Security pricing provider as unavailable, not an error' {
        $script:unregisteredPricingSubscription = 'sub-2'

        $results = @(
            Get-ScoutSubscriptionSecurityPolicySweep `
                -Subscriptions $script:subscriptions `
                -WarningVariable warnings `
                -WarningAction SilentlyContinue
        )

        @($results[1].properties.DefenderPricing).Count | Should -Be 0
        $results[1].properties.CollectionStatus.DefenderPricing | Should -Be 'Unavailable'
        @($results[1].properties.CollectionErrors).Count | Should -Be 0
        ($warnings -join "`n") | Should -Not -Match 'DefenderPricing'
    }

    It 'returns a skipped envelope without issuing data calls when context entry fails' {
        $script:failContextSubscription = 'sub-2'

        $results = @(
            Get-ScoutSubscriptionSecurityPolicySweep `
                -Subscriptions $script:subscriptions `
                -WarningAction SilentlyContinue
        )

        @($results[1].properties.DefenderAlerts).Count | Should -Be 0
        $results[1].properties.CollectionStatus.DefenderAlerts | Should -Be 'Skipped'
        $results[1].properties.CollectionErrors[0].Dataset | Should -Be 'Context'
        $script:assessmentAttempts.ContainsKey('sub-2') | Should -BeFalse
        $script:contextCalls[-1] | Should -Be 'original-sub'
    }

    It 'returns no rows and performs no context operations for an empty subscription list' {
        $results = @(
            Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @()
        )

        $results.Count | Should -Be 0
        $script:contextCalls.Count | Should -Be 0
    }
}
