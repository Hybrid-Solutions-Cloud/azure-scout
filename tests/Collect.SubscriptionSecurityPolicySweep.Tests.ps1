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
        $script:pricingErrorActions = [System.Collections.Generic.List[string]]::new()
        $script:failContextSubscription = $null
        $script:deniedDataset = $null

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
            if ($script:deniedDataset -eq 'DefenderAlerts') { throw 'HTTP 403 AuthorizationFailed: alerts/read denied' }
            [pscustomobject]@{ Name = "alert-$script:currentSubscription" }
        }

        function global:Get-AzSecurityAssessment {
            param($ErrorAction, $ErrorVariable)
            $null = $ErrorAction, $ErrorVariable
            if ($script:deniedDataset -eq 'DefenderAssessments') { throw 'HTTP 403 AuthorizationFailed: assessments/read denied' }
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
            param($ErrorAction, $ErrorVariable)
            $null = $ErrorVariable
            $script:pricingErrorActions.Add([string]$ErrorAction)
            if ($script:deniedDataset -eq 'DefenderPricing') { throw 'HTTP 403 AuthorizationFailed: pricings/read denied' }
            if ($script:currentSubscription -eq $script:unregisteredPricingSubscription) {
                throw "Subscription is not registered to use namespace 'Microsoft.Security'"
            }
            [pscustomobject]@{ Name = "pricing-$script:currentSubscription" }
        }

        function global:Get-AzSecuritySecureScore {
            param($ErrorAction)
            $null = $ErrorAction
            if ($script:deniedDataset -eq 'DefenderSecureScores') { throw 'HTTP 403 AuthorizationFailed: secureScores/read denied' }
            [pscustomobject]@{ Name = "score-$script:currentSubscription" }
        }

        function global:Get-AzSecuritySecureScoreControl {
            param($ErrorAction)
            $null = $ErrorAction
            if ($script:deniedDataset -eq 'DefenderSecureScoreControls') { throw 'HTTP 403 AuthorizationFailed: secureScoreControls/read denied' }
            [pscustomobject]@{ Name = "control-$script:currentSubscription" }
        }

        function global:Get-AzRegulatoryComplianceStandard {
            param($ErrorAction)
            $null = $ErrorAction
            if ($script:deniedDataset -eq 'DefenderRegulatoryStandards') { throw 'HTTP 403 AuthorizationFailed: regulatoryComplianceStandards/read denied' }
            [pscustomobject]@{ Name = "standard-$script:currentSubscription" }
        }

        function global:Get-AzDiagnosticSetting {
            param($ResourceId, $ErrorAction)
            $null = $ErrorAction
            if ($script:deniedDataset -eq 'SubscriptionDiagnosticSettings') { throw 'HTTP 403 AuthorizationFailed: diagnosticSettings/read denied' }
            [pscustomobject]@{ Name = "diagnostic-$script:currentSubscription"; ResourceId = $ResourceId }
        }

        function global:Get-AzPolicyState {
            param($SubscriptionId, $ErrorAction)
            $null = $ErrorAction
            if ($script:deniedDataset -eq 'PolicyComplianceStates') { throw 'HTTP 403 AuthorizationFailed: policyStates/read denied' }
            if ($SubscriptionId -eq $script:failPolicySubscription) {
                throw 'Policy Insights access denied'
            }
            [pscustomobject]@{ PolicyAssignmentName = "policy-$SubscriptionId" }
        }

        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction)
            $null = $Path, $Method, $ErrorAction
            throw 'Invoke-AzRestMethod must only be called by an explicitly configured fallback test.'
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
                'Get-AzRegulatoryComplianceStandard',
                'Get-AzDiagnosticSetting',
                'Get-AzPolicyState',
                'Invoke-AzRestMethod',
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
        $results[0].properties.DefenderRegulatoryStandards[0].Name | Should -Be 'standard-sub-1'
        $results[0].properties.SubscriptionDiagnosticSettings[0].ResourceId | Should -Be '/subscriptions/sub-1'
        $results[0].properties.PolicyComplianceStates[0].PolicyAssignmentName | Should -Be 'policy-sub-1'
        @($results[0].properties.CollectionErrors).Count | Should -Be 0

        @($results[0].properties.PSObject.Properties.Name) | Should -Be @(
            'DefenderAlerts',
            'DefenderAssessments',
            'DefenderPricing',
            'DefenderSecureScores',
            'DefenderSecureScoreControls',
            'DefenderRegulatoryStandards',
            'SubscriptionDiagnosticSettings',
            'PolicyComplianceStates',
            'CollectionStatus',
            'CollectionErrors'
            'CollectionReasons'
            'SourceOperations'
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

    It 'falls back to the paged REST endpoint when Az.Security times out without losing assessment fields' {
        function global:Get-AzSecurityAssessment {
            param($ErrorAction, $ErrorVariable)
            $null = $ErrorAction, $ErrorVariable
            throw 'The request was canceled due to the configured HttpClient.Timeout of 100 seconds elapsing.'
        }
        $script:assessmentRestPaths = [System.Collections.Generic.List[string]]::new()
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction)
            $null = $Method, $ErrorAction
            $script:assessmentRestPaths.Add($Path)
            if ($script:assessmentRestPaths.Count -eq 1) {
                return [pscustomobject]@{
                    StatusCode = 200
                    Content = @{
                        value = @(@{
                            id = '/subscriptions/sub-1/providers/Microsoft.Security/assessments/a'
                            name = 'a'
                            properties = @{
                                displayName = 'Assessment A'
                                resourceDetails = @{ id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm-1' }
                                status = @{ code = 'Unhealthy'; severity = 'High'; description = 'remediate' }
                                metadata = @{ category = @('Compute'); implementationEffort = 'Low' }
                                additionalData = @{ assessedResourceType = 'VirtualMachine' }
                            }
                        })
                        nextLink = 'https://management.azure.com/next-assessment-page'
                    } | ConvertTo-Json -Depth 10
                }
            }
            [pscustomobject]@{
                StatusCode = 200
                Content = '{"value":[{"id":"/subscriptions/sub-1/providers/Microsoft.Security/assessments/b","name":"b","properties":{"displayName":"Assessment B","status":{"code":"Healthy"}}}]}'
            }
        }

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]) -WarningVariable warnings -WarningAction SilentlyContinue)[0]

        @($result.properties.DefenderAssessments).Count | Should -Be 2
        $result.properties.DefenderAssessments[0].DisplayName | Should -Be 'Assessment A'
        $result.properties.DefenderAssessments[0].Status.Code | Should -Be 'Unhealthy'
        $result.properties.DefenderAssessments[0].ResourceDetails.Id | Should -Match '/vm-1$'
        $result.properties.DefenderAssessments[1].Name | Should -Be 'b'
        @($script:assessmentRestPaths) | Should -Be @(
            '/subscriptions/sub-1/providers/Microsoft.Security/assessments?api-version=2021-06-01'
            'https://management.azure.com/next-assessment-page'
        )
        $result.properties.CollectionStatus.DefenderAssessments | Should -Be 'Success'
        ($warnings -join "`n") | Should -Not -Match 'DefenderAssessments|Timeout'
    }

    It 'falls back to REST and preserves the established alert projection after an Az.Security null reference' {
        function global:Get-AzSecurityAlert {
            param($ErrorAction) $null = $ErrorAction
            throw [System.NullReferenceException]::new('Object reference not set to an instance of an object.')
        }
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction)
            $null = $Method, $ErrorAction
            $Path | Should -Match '/subscriptions/sub-1/providers/Microsoft.Security/alerts\?api-version=2022-01-01'
            [pscustomobject]@{
                StatusCode = 200
                Content = @{
                    value = @(@{
                        id = '/alerts/alert-1'; name = 'alert-1'
                        properties = @{
                            alertDisplayName = 'REST alert'; alertType = 'Test'; severity = 'High'; status = 'Active'
                            timeGeneratedUtc = '2026-08-11T12:00:00Z'; description = 'description'
                            remediationSteps = @('step'); intent = 'Execution'; entities = @(); resourceIdentifiers = @()
                        }
                    })
                } | ConvertTo-Json -Depth 10
            }
        }

        $results = @(
            Get-ScoutSubscriptionSecurityPolicySweep `
                -Subscriptions @($script:subscriptions[0]) `
                -WarningVariable warnings `
                -WarningAction SilentlyContinue
        )

        @($results[0].properties.DefenderAlerts).Count | Should -Be 1
        $results[0].properties.DefenderAlerts[0].AlertDisplayName | Should -Be 'REST alert'
        $results[0].properties.DefenderAlerts[0].Severity | Should -Be 'High'
        $results[0].properties.DefenderAlerts[0].TimeGeneratedUtc | Should -BeOfType ([datetime])
        $results[0].properties.CollectionStatus.DefenderAlerts | Should -Be 'Success'
        ($warnings -join "`n") | Should -Not -Match 'provisioned|onboarded|DefenderAlerts'
    }

    It 'maps an authorization failure to the correct dataset without discarding its neighbours' -TestCases @(
        @{ Dataset = 'DefenderAlerts' }
        @{ Dataset = 'DefenderAssessments' }
        @{ Dataset = 'DefenderPricing' }
        @{ Dataset = 'DefenderSecureScores' }
        @{ Dataset = 'DefenderSecureScoreControls' }
        @{ Dataset = 'SubscriptionDiagnosticSettings' }
        @{ Dataset = 'PolicyComplianceStates' }
    ) {
        param($Dataset)
        $script:deniedDataset = $Dataset

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]) -WarningAction SilentlyContinue)[0]

        $result.properties.CollectionStatus.$Dataset | Should -Be 'Unavailable'
        @($result.properties.$Dataset).Count | Should -Be 0
        $error = @($result.properties.CollectionErrors | Where-Object Dataset -eq $Dataset)
        $error.Count | Should -Be 1
        $error[0].Message | Should -Match '403|AuthorizationFailed'
        foreach ($other in @('DefenderAlerts', 'DefenderAssessments', 'DefenderPricing', 'DefenderSecureScores', 'DefenderSecureScoreControls', 'SubscriptionDiagnosticSettings', 'PolicyComplianceStates') | Where-Object { $_ -ne $Dataset }) {
            $result.properties.CollectionStatus.$other | Should -Not -Be 'Unavailable'
        }
    }

    It 'preserves successful empty-versus-skipped status for every sweep dataset' {
        function global:Get-AzSecurityAlert { param($ErrorAction) $null = $ErrorAction }
        function global:Get-AzSecurityAssessment { param($ErrorAction, $ErrorVariable) $null = $ErrorAction, $ErrorVariable }
        function global:Get-AzSecurityPricing { param($ErrorAction, $ErrorVariable) $null = $ErrorAction, $ErrorVariable }
        function global:Get-AzSecuritySecureScore { param($ErrorAction) $null = $ErrorAction }
        function global:Get-AzSecuritySecureScoreControl { param($ErrorAction) $null = $ErrorAction }
        function global:Get-AzDiagnosticSetting { param($ResourceId, $ErrorAction) $null = $ResourceId, $ErrorAction }
        function global:Get-AzPolicyState { param($SubscriptionId, $ErrorAction) $null = $SubscriptionId, $ErrorAction }

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]))[0]
        foreach ($dataset in @('DefenderAlerts', 'DefenderAssessments', 'DefenderPricing', 'DefenderSecureScores', 'SubscriptionDiagnosticSettings', 'PolicyComplianceStates')) {
            $result.properties.CollectionStatus.$dataset | Should -Be 'Success'
            @($result.properties.$dataset).Count | Should -Be 0
        }
        $result.properties.CollectionStatus.DefenderSecureScoreControls | Should -Be 'Skipped'
        @($result.properties.DefenderSecureScoreControls).Count | Should -Be 0
        @($result.properties.CollectionErrors).Count | Should -Be 0
    }

    It 'treats an empty 200 REST fallback as a successful empty alert dataset' {
        function global:Get-AzSecurityAlert { param($ErrorAction) $null = $ErrorAction; throw [NullReferenceException]::new() }
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction) $null = $Path, $Method, $ErrorAction
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' }
        }

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]))[0]
        @($result.properties.DefenderAlerts).Count | Should -Be 0
        $result.properties.CollectionStatus.DefenderAlerts | Should -Be 'Success'
        @($result.properties.CollectionErrors | Where-Object Dataset -eq 'DefenderAlerts').Count | Should -Be 0
    }

    It 'follows Defender alert REST nextLink pages exactly once each' {
        function global:Get-AzSecurityAlert { param($ErrorAction) $null = $ErrorAction; throw [NullReferenceException]::new() }
        $script:alertRestPaths = [System.Collections.Generic.List[string]]::new()
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction) $null = $Method, $ErrorAction
            $script:alertRestPaths.Add($Path)
            if ($script:alertRestPaths.Count -eq 1) {
                return [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"name":"a","properties":{}}],"nextLink":"https://management.azure.com/next-alert-page"}' }
            }
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"name":"b","properties":{}}]}' }
        }

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]))[0]
        @($result.properties.DefenderAlerts.Name) | Should -Be @('a', 'b')
        @($script:alertRestPaths) | Should -Be @(
            '/subscriptions/sub-1/providers/Microsoft.Security/alerts?api-version=2022-01-01'
            'https://management.azure.com/next-alert-page'
        )
    }

    It 'reports an actual REST 403 without claiming Defender onboarding is the cause' {
        function global:Get-AzSecurityAlert { param($ErrorAction) $null = $ErrorAction; throw [NullReferenceException]::new() }
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction) $null = $Path, $Method, $ErrorAction
            throw 'HTTP 403 AuthorizationFailed: Microsoft.Security/alerts/read denied'
        }

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]) -WarningAction SilentlyContinue)[0]
        $result.properties.CollectionStatus.DefenderAlerts | Should -Be 'Unavailable'
        $error = @($result.properties.CollectionErrors | Where-Object Dataset -eq 'DefenderAlerts')[0]
        $error.Message | Should -Match '403|AuthorizationFailed'
        $error.Message | Should -Not -Match 'provisioned|onboarded'
    }

    It 'classifies an unregistered Microsoft.Security REST fallback as expected unavailable without a collection error' {
        function global:Get-AzSecurityAlert { param($ErrorAction) $null = $ErrorAction; throw [NullReferenceException]::new() }
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction) $null = $Path, $Method, $ErrorAction
            throw "MissingSubscriptionRegistration: register to Microsoft.Security"
        }

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]))[0]
        $result.properties.CollectionStatus.DefenderAlerts | Should -Be 'Unavailable'
        @($result.properties.CollectionErrors | Where-Object Dataset -eq 'DefenderAlerts').Count | Should -Be 0
    }

    It 'treats regulatory compliance on a free-tier subscription as expected unavailable, with no warning or collection error' {
        # Field run 2026-10-05: eight of nine subscriptions raised this as a WARN on every scan.
        function global:Get-AzRegulatoryComplianceStandard {
            param($ErrorAction) $null = $ErrorAction
            throw "Regulatory compliance is not supported for subscription '00000000-0000-0000-0000-000000000001' as it has no standard pricing bundle"
        }

        $warnings = @()
        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]) -WarningVariable warnings -WarningAction SilentlyContinue)[0]
        $result.properties.CollectionStatus.DefenderRegulatoryStandards | Should -Be 'Unavailable'
        @($result.properties.CollectionErrors | Where-Object Dataset -eq 'DefenderRegulatoryStandards').Count | Should -Be 0
        @($warnings | Where-Object { [string]$_ -match 'DefenderRegulatoryStandards' }).Count | Should -Be 0
        # The reason travels with the row so collection health can explain the empty dataset.
        $result.properties.CollectionReasons.DefenderRegulatoryStandards | Should -Match 'paid Microsoft Defender for Cloud plan'
    }

    It 'retries transient Defender alert REST failures with the shared bounded policy' {
        function global:Get-AzSecurityAlert { param($ErrorAction) $null = $ErrorAction; throw [NullReferenceException]::new() }
        $script:alertRestAttempts = 0
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $ErrorAction) $null = $Path, $Method, $ErrorAction
            $script:alertRestAttempts++
            if ($script:alertRestAttempts -lt 3) { throw 'HTTP 503 ServiceUnavailable' }
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' }
        }

        $result = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions @($script:subscriptions[0]))[0]
        $script:alertRestAttempts | Should -Be 3
        $result.properties.CollectionStatus.DefenderAlerts | Should -Be 'Success'
        @($script:sleepCalls) | Should -Be @(200, 400)
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
        @($script:pricingErrorActions | Select-Object -Unique) | Should -Be @('SilentlyContinue')
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

Describe 'Get-ScoutSubscriptionSecurityPolicySweep assessment prefetch' {
    BeforeAll {
        # A loopback HTTP listener stands in for Azure Resource Manager: the prefetch runs on
        # worker threads, which cannot see the stubbed Az commands.
        $script:armPort = 0
        $script:armListener = $null
        foreach ($candidate in (Get-Random -Minimum 20000 -Maximum 40000 -Count 10)) {
            try {
                $listener = [System.Net.HttpListener]::new()
                $listener.Prefixes.Add("http://localhost:$candidate/")
                $listener.Start()
                $script:armListener = $listener
                $script:armPort = $candidate
                break
            }
            catch { continue }
        }
        # Request counts per subscription, shared with the listener thread.
        $script:armHits = [hashtable]::Synchronized(@{})
        $script:armServer = [powershell]::Create()
        $null = $script:armServer.AddScript({
                param($Listener, $Port, $Hits)
                while ($Listener.IsListening) {
                    try { $context = $Listener.GetContext() } catch { break }
                    $target = $context.Request.Url.PathAndQuery
                    $status = 200
                    $hitKey = if ($target -like '/subscriptions/sub-1/*page=2*') { 'sub-1-page-2' } elseif ($target -like '/subscriptions/sub-1/*') { 'sub-1' } else { 'other' }
                    $Hits[$hitKey] = 1 + [int]$Hits[$hitKey]
                    $body = if ($target -like '/subscriptions/sub-1/*page=2*') {
                        '{"value":[{"id":"/a/sub-1/2","name":"a2","properties":{"displayName":"Second","status":{"code":"Healthy"}}}]}'
                    }
                    elseif ($target -like '/subscriptions/sub-1/*' -and $Hits['sub-1'] -eq 1) {
                        # The first answer for sub-1 is a transient gateway error; the retry succeeds.
                        $status = 502
                        '{"error":{"code":"BadGateway"}}'
                    }
                    elseif ($target -like '/subscriptions/sub-1/*') {
                        '{"value":[{"id":"/a/sub-1/1","name":"a1","properties":{"displayName":"First","status":{"code":"Unhealthy"}}}],"nextLink":"http://localhost:' + $Port + '/subscriptions/sub-1/providers/Microsoft.Security/assessments?page=2"}'
                    }
                    else {
                        $status = 500
                        '{"error":{"code":"InternalServerError"}}'
                    }
                    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
                    $context.Response.StatusCode = $status
                    $context.Response.ContentType = 'application/json'
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $context.Response.Close()
                }
            }).AddArgument($script:armListener).AddArgument($script:armPort).AddArgument($script:armHits)
        $null = $script:armServer.BeginInvoke()
    }

    AfterAll {
        if ($script:armListener) { $script:armListener.Stop(); $script:armListener.Close() }
        if ($script:armServer) { $script:armServer.Dispose() }
    }

    BeforeEach {
        Initialize-ScoutSweepStub
        $script:tokenCalls = 0
        function global:Get-AzContext {
            param($ErrorAction)
            $null = $ErrorAction
            [pscustomobject]@{
                Subscription = [pscustomobject]@{ Id = 'original-sub' }
                Environment  = [pscustomobject]@{ ResourceManagerUrl = "http://localhost:$script:armPort/" }
            }
        }
        function global:Get-AzAccessToken {
            param($ResourceUrl, [switch]$AsSecureString, $TenantId, $ErrorAction, $WarningAction)
            $null = $ResourceUrl, $AsSecureString, $TenantId, $ErrorAction, $WarningAction
            $script:tokenCalls++
            $secureToken = [securestring]::new()
            foreach ($character in 'stub-token'.ToCharArray()) { $secureToken.AppendChar($character) }
            [pscustomobject]@{ Token = $secureToken }
        }
    }

    AfterEach {
        Clear-ScoutSweepStub
        Remove-Item 'Function:\Get-AzAccessToken' -Force -ErrorAction SilentlyContinue
    }

    It 'uses prefetched assessments, follows nextLink and leaves a failed subscription to the cmdlet' {
        $script:armListener | Should -Not -BeNullOrEmpty

        $results = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions $script:subscriptions -PrefetchAssessments)

        $script:tokenCalls | Should -Be 1
        $first = @($results[0].properties.DefenderAssessments)
        $first.Count | Should -Be 2
        $first[0].Id | Should -Be '/a/sub-1/1'
        $first[0].DisplayName | Should -Be 'First'
        $first[0].Status.code | Should -Be 'Unhealthy'
        $first[1].Name | Should -Be 'a2'
        $results[0].properties.CollectionStatus.DefenderAssessments | Should -Be 'Success'
        # sub-1 came from the prefetch, so the cmdlet ran only for sub-2, whose prefetch failed.
        $script:assessmentAttempts.ContainsKey('sub-1') | Should -BeFalse
        $script:assessmentAttempts['sub-2'] | Should -Be 1
        $results[1].properties.DefenderAssessments[0].Name | Should -Be 'assessment-sub-2'
    }

    It 'retries a transient prefetch answer and gives up after three attempts on a persistent failure' {
        $script:armHits.Clear()

        $results = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions $script:subscriptions -PrefetchAssessments)

        # sub-1: a 502, then success on the retry, so it never reaches the slow per-subscription pass.
        $script:armHits['sub-1'] | Should -Be 2
        $script:assessmentAttempts.ContainsKey('sub-1') | Should -BeFalse
        @($results[0].properties.DefenderAssessments).Count | Should -Be 2
        # sub-2 answers 500 every time: three attempts, then the per-subscription pass reads it.
        $script:armHits['other'] | Should -Be 3
        $script:assessmentAttempts['sub-2'] | Should -Be 1
    }

    It 'does not prefetch unless asked' {
        $results = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions $script:subscriptions)

        $script:tokenCalls | Should -Be 0
        $results[0].properties.DefenderAssessments[0].Name | Should -Be 'assessment-sub-1'
    }
}
