#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Collects the subscription-scoped security, diagnostic, and policy datasets used by the
    legacy inventory collectors.

.DESCRIPTION
    Performs one context-scoped sweep per subscription and returns one synthetic resource
    envelope for that subscription. Each Azure call is isolated so a denied or unavailable
    dataset becomes an empty collection without discarding its neighbours.

    Defender assessment queries retry transient HTTP 5xx failures up to three times. A
    Microsoft.Security provider-registration failure for Defender pricing is represented as
    an empty, Unavailable dataset rather than as a collection error.

.PARAMETER Subscriptions
    Subscription objects with an `id` property and an optional `name` property.

.OUTPUTS
    One `[pscustomobject]` per valid subscription with this integration contract:

        type = 'AZSC/Subscription/SecurityPolicySweep'
        subscriptionId
        subscriptionName
        properties.DefenderAlerts
        properties.DefenderAssessments
        properties.DefenderPricing
        properties.DefenderSecureScores
        properties.DefenderSecureScoreControls
        properties.SubscriptionDiagnosticSettings
        properties.PolicyComplianceStates
        properties.CollectionStatus
        properties.CollectionErrors

    Every dataset property is always an array, including on failure. CollectionStatus
    records Success, Unavailable, or Skipped for every dataset. CollectionErrors contains
    only actual failures and is also always an array.

.NOTES
    Collect-phase implementation for Epic AB#5638. The legacy collectors and the collect
    orchestrator intentionally remain unchanged until their declarative definitions are
    integrated.
#>
function Get-ScoutSubscriptionSecurityPolicySweep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Subscriptions
    )

    if ($Subscriptions.Count -eq 0) {
        return @()
    }

    function Invoke-ScoutSweepDataset {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string] $Dataset,

            [Parameter(Mandatory)]
            [string] $SubscriptionName,

            [Parameter(Mandatory)]
            [scriptblock] $Operation,

            [ValidateRange(1, 5)]
            [int] $MaxAttempts = 1,

            [switch] $ProviderRegistrationIsUnavailable
        )

        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                return [pscustomobject]@{
                    Data   = @(& $Operation)
                    Status = 'Success'
                    Error  = $null
                }
            }
            catch {
                $message = $_.Exception.Message
                # 'Please register to Microsoft.Security in order to view your security status' is
                # the phrasing Azure actually uses for an unregistered provider on this endpoint
                # (observed live, AB#6900) -- it says "register to", never "not registered", so the
                # original patterns missed it and the quiet Unavailable path fell through to a
                # raw Write-Warning on every collect against a subscription without Defender.
                $providerUnavailable =
                    $ProviderRegistrationIsUnavailable -and
                    $message -match '(?i)MissingSubscriptionRegistration|SubscriptionNotRegistered|not registered.+Microsoft\.Security|Microsoft\.Security.+not registered|register to Microsoft\.Security'

                if ($providerUnavailable) {
                    return [pscustomobject]@{
                        Data   = @()
                        Status = 'Unavailable'
                        Error  = $null
                    }
                }

                $transientFailure = $message -match '(?i)\bHTTP\s*(429|500|502|503|504)\b|InternalServerError|BadGateway|ServiceUnavailable|GatewayTimeout|TooManyRequests|HttpClient\.Timeout|timed out|TaskCanceled|operation (?:was|has been) canceled'
                if ($transientFailure -and $attempt -lt $MaxAttempts) {
                    Start-Sleep -Milliseconds (200 * $attempt)
                    continue
                }

                Write-Warning "Get-ScoutSubscriptionSecurityPolicySweep: '$Dataset' failed for subscription '$SubscriptionName' after $attempt attempt(s): $message"
                return [pscustomobject]@{
                    Data   = @()
                    Status = 'Unavailable'
                    Error  = [pscustomobject]@{
                        Dataset = $Dataset
                        Message = $message
                    }
                }
            }
        }
    }

    function Invoke-ScoutDefenderPricingDataset {
        param([Parameter(Mandatory)][string] $SubscriptionName)

        # Az.Security emits an error when Microsoft.Security is unregistered. Run this known
        # optional read with a quiet error variable so the expected provider state does not leak
        # into scout-console.log as a TerminatingError before Scout can classify it.
        $pricingErrors = @()
        $pricingData = @()
        try {
            $pricingData = @(Get-AzSecurityPricing -ErrorAction SilentlyContinue -ErrorVariable +pricingErrors)
        }
        catch {
            $pricingErrors += $_
        }

        if (@($pricingErrors).Count -eq 0) {
            return [pscustomobject]@{ Data = $pricingData; Status = 'Success'; Error = $null }
        }

        $message = (@($pricingErrors | ForEach-Object { $_.Exception.Message }) -join '; ')
        if ($message -match '(?i)MissingSubscriptionRegistration|SubscriptionNotRegistered|not registered.+Microsoft\.Security|Microsoft\.Security.+not registered|register to Microsoft\.Security') {
            return [pscustomobject]@{ Data = @(); Status = 'Unavailable'; Error = $null }
        }

        Write-Warning "Get-ScoutSubscriptionSecurityPolicySweep: 'DefenderPricing' failed for subscription '$SubscriptionName': $message"
        return [pscustomobject]@{
            Data   = @()
            Status = 'Unavailable'
            Error  = [pscustomobject]@{ Dataset = 'DefenderPricing'; Message = $message }
        }
    }

    function ConvertFrom-ScoutDefenderAlertRestRow {
        param([Parameter(Mandatory)]$Alert)

        function Get-AlertValue {
            param($Object, [Parameter(Mandatory)][string]$Name)
            if ($null -eq $Object) { return $null }
            $property = $Object.PSObject.Properties[$Name]
            if ($null -eq $property) { return $null }
            return $property.Value
        }

        $properties = Get-AlertValue -Object $Alert -Name 'properties'
        if ($null -eq $properties) { $properties = $Alert }
        $timeGeneratedValue = Get-AlertValue -Object $properties -Name 'timeGeneratedUtc'
        $timeGenerated = if ($timeGeneratedValue) { [datetime]$timeGeneratedValue } else { $null }

        # Preserve the established Get-AzSecurityAlert projection consumed by the declarative
        # DefenderAlerts collector. The REST API nests these values under `properties`.
        [pscustomobject]@{
            Id                  = Get-AlertValue -Object $Alert -Name 'id'
            Name                = Get-AlertValue -Object $Alert -Name 'name'
            AlertDisplayName    = Get-AlertValue -Object $properties -Name 'alertDisplayName'
            AlertType           = Get-AlertValue -Object $properties -Name 'alertType'
            Severity            = Get-AlertValue -Object $properties -Name 'severity'
            Status              = Get-AlertValue -Object $properties -Name 'status'
            TimeGeneratedUtc    = $timeGenerated
            Description         = Get-AlertValue -Object $properties -Name 'description'
            RemediationSteps    = @(Get-AlertValue -Object $properties -Name 'remediationSteps')
            Intent              = Get-AlertValue -Object $properties -Name 'intent'
            Entities            = @(Get-AlertValue -Object $properties -Name 'entities')
            ResourceIdentifiers = @(Get-AlertValue -Object $properties -Name 'resourceIdentifiers')
            ExtendedProperties  = Get-AlertValue -Object $properties -Name 'extendedProperties'
            ConfidenceLevel     = Get-AlertValue -Object $properties -Name 'confidenceLevel'
        }
    }

    function Invoke-ScoutDefenderAlertRestFallback {
        param([Parameter(Mandatory)][string]$SubscriptionId)

        $alerts = [System.Collections.Generic.List[object]]::new()
        $path = "/subscriptions/$SubscriptionId/providers/Microsoft.Security/alerts?api-version=2022-01-01"
        do {
            # Do not pass -SkipHttpErrorCheck: older supported Az.Accounts releases do not expose
            # it on Invoke-AzRestMethod. Non-success responses throw and are classified from their
            # actual service error by the surrounding dataset boundary.
            $response = Invoke-AzRestMethod -Path $path -Method GET -ErrorAction Stop
            if ($null -eq $response) { throw 'Defender alerts REST fallback returned no response.' }

            $statusProperty = $response.PSObject.Properties['StatusCode']
            if ($null -ne $statusProperty) {
                $statusCode = [int]$statusProperty.Value
                if ($statusCode -lt 200 -or $statusCode -ge 300) {
                    $responseContent = $response.PSObject.Properties['Content']
                    $responseText = if ($null -ne $responseContent) { [string]$responseContent.Value } else { '' }
                    throw "Defender alerts REST fallback returned HTTP $statusCode. $responseText"
                }
            }

            $contentProperty = $response.PSObject.Properties['Content']
            $content = if ($null -ne $contentProperty) { $contentProperty.Value } else { $response }
            if ($content -is [string]) {
                if ([string]::IsNullOrWhiteSpace($content)) { $content = [pscustomobject]@{ value = @() } }
                else { $content = $content | ConvertFrom-Json }
            }
            if ($null -eq $content) { $content = [pscustomobject]@{ value = @() } }

            $valueProperty = $content.PSObject.Properties['value']
            $pageRows = if ($null -ne $valueProperty) { @($valueProperty.Value) } else { @() }
            foreach ($alert in $pageRows) {
                if ($null -ne $alert) { $alerts.Add((ConvertFrom-ScoutDefenderAlertRestRow -Alert $alert)) }
            }
            $nextLinkProperty = $content.PSObject.Properties['nextLink']
            $path = if ($null -ne $nextLinkProperty) { [string]$nextLinkProperty.Value } else { $null }
        } while (-not [string]::IsNullOrWhiteSpace($path))

        return $alerts.ToArray()
    }

    function Get-ScoutDefenderAlerts {
        param([Parameter(Mandatory)][string]$SubscriptionId)

        try {
            return @(Get-AzSecurityAlert -ErrorAction Stop)
        }
        catch {
            if ($_.Exception -isnot [System.NullReferenceException] -and
                $_.Exception.Message -notmatch '(?i)Object reference not set to an instance of an object') {
                throw
            }
            Write-Verbose 'Get-AzSecurityAlert failed inside Az.Security; using the documented Defender for Cloud alerts REST endpoint.'
            return @(Invoke-ScoutDefenderAlertRestFallback -SubscriptionId $SubscriptionId)
        }
    }

    function ConvertFrom-ScoutDefenderAssessmentRestRow {
        param([Parameter(Mandatory)]$Assessment)

        function Get-AssessmentValue {
            param($Object, [Parameter(Mandatory)][string]$Name)
            if ($null -eq $Object) { return $null }
            $property = $Object.PSObject.Properties[$Name]
            if ($null -eq $property) { return $null }
            return $property.Value
        }

        $properties = Get-AssessmentValue -Object $Assessment -Name 'properties'
        if ($null -eq $properties) { $properties = $Assessment }

        # Preserve the Get-AzSecurityAssessment projection consumed by the shipped collector.
        # The documented REST response nests these values beneath `properties`.
        [pscustomobject]@{
            Id              = Get-AssessmentValue -Object $Assessment -Name 'id'
            Name            = Get-AssessmentValue -Object $Assessment -Name 'name'
            DisplayName     = Get-AssessmentValue -Object $properties -Name 'displayName'
            ResourceDetails = Get-AssessmentValue -Object $properties -Name 'resourceDetails'
            Status          = Get-AssessmentValue -Object $properties -Name 'status'
            Metadata        = Get-AssessmentValue -Object $properties -Name 'metadata'
            AdditionalData  = Get-AssessmentValue -Object $properties -Name 'additionalData'
            Links           = Get-AssessmentValue -Object $properties -Name 'links'
            PartnersData    = Get-AssessmentValue -Object $properties -Name 'partnersData'
        }
    }

    function Invoke-ScoutDefenderAssessmentRestFallback {
        param([Parameter(Mandatory)][string]$SubscriptionId)

        $assessments = [System.Collections.Generic.List[object]]::new()
        $path = "/subscriptions/$SubscriptionId/providers/Microsoft.Security/assessments?api-version=2021-06-01"
        do {
            $response = Invoke-AzRestMethod -Path $path -Method GET -ErrorAction Stop
            if ($null -eq $response) { throw 'Defender assessments REST fallback returned no response.' }

            $statusProperty = $response.PSObject.Properties['StatusCode']
            if ($null -ne $statusProperty) {
                $statusCode = [int]$statusProperty.Value
                if ($statusCode -lt 200 -or $statusCode -ge 300) {
                    $responseContent = $response.PSObject.Properties['Content']
                    $responseText = if ($null -ne $responseContent) { [string]$responseContent.Value } else { '' }
                    throw "Defender assessments REST fallback returned HTTP $statusCode. $responseText"
                }
            }

            $contentProperty = $response.PSObject.Properties['Content']
            $content = if ($null -ne $contentProperty) { $contentProperty.Value } else { $response }
            if ($content -is [string]) {
                if ([string]::IsNullOrWhiteSpace($content)) { $content = [pscustomobject]@{ value = @() } }
                else { $content = $content | ConvertFrom-Json }
            }
            if ($null -eq $content) { $content = [pscustomobject]@{ value = @() } }

            $valueProperty = $content.PSObject.Properties['value']
            foreach ($assessment in @(if ($null -ne $valueProperty) { $valueProperty.Value } else { @() })) {
                if ($null -ne $assessment) {
                    $assessments.Add((ConvertFrom-ScoutDefenderAssessmentRestRow -Assessment $assessment))
                }
            }
            $nextLinkProperty = $content.PSObject.Properties['nextLink']
            $path = if ($null -ne $nextLinkProperty) { [string]$nextLinkProperty.Value } else { $null }
        } while (-not [string]::IsNullOrWhiteSpace($path))

        return $assessments.ToArray()
    }

    function Get-ScoutDefenderAssessments {
        param(
            [Parameter(Mandatory)][string]$SubscriptionId
        )

        # Az.Security can surface an HttpClient.Timeout after 100 seconds even though the
        # documented list endpoint remains healthy. Suppress the raw cmdlet error record, retain
        # its message for classification, and fall back only for client-side timeout/null failures.
        $assessmentErrors = @()
        $assessmentData = @()
        try {
            $assessmentData = @(Get-AzSecurityAssessment -ErrorAction SilentlyContinue -ErrorVariable +assessmentErrors)
        }
        catch {
            $assessmentErrors += $_
        }
        if (@($assessmentErrors).Count -eq 0) { return $assessmentData }

        $message = (@($assessmentErrors | ForEach-Object { $_.Exception.Message }) -join '; ')
        $fallbackRequired = $message -match '(?i)HttpClient\.Timeout|timed out|TaskCanceled|operation (?:was|has been) canceled|Object reference not set'
        if (-not $fallbackRequired) { throw $message }

        Write-Verbose 'Get-AzSecurityAssessment failed inside Az.Security; using the documented Defender for Cloud assessments REST endpoint.'
        return @(Invoke-ScoutDefenderAssessmentRestFallback -SubscriptionId $SubscriptionId)
    }

    $originalContext = try {
        Get-AzContext -ErrorAction SilentlyContinue
    }
    catch {
        $null
    }

    $results = try {
        foreach ($subscription in $Subscriptions) {
            $idProperty = $subscription.PSObject.Properties['id']
            if ($null -eq $idProperty -or [string]::IsNullOrWhiteSpace([string] $idProperty.Value)) {
                Write-Warning 'Get-ScoutSubscriptionSecurityPolicySweep: skipping a subscription object without an id.'
                continue
            }

            $subscriptionId = [string] $idProperty.Value
            $tenantIdProperty = $subscription.PSObject.Properties['tenantId']
            $subscriptionTenantId = if ($null -ne $tenantIdProperty -and -not [string]::IsNullOrWhiteSpace([string] $tenantIdProperty.Value)) {
                [string] $tenantIdProperty.Value
            }
            elseif ($null -ne $originalContext -and $null -ne $originalContext.PSObject.Properties['Tenant'] -and $null -ne $originalContext.Tenant -and $null -ne $originalContext.Tenant.PSObject.Properties['Id']) {
                [string] $originalContext.Tenant.Id
            }
            else {
                $null
            }
            $nameProperty = $subscription.PSObject.Properties['name']
            $subscriptionName = if (
                $null -ne $nameProperty -and
                -not [string]::IsNullOrWhiteSpace([string] $nameProperty.Value)
            ) {
                [string] $nameProperty.Value
            }
            else {
                $subscriptionId
            }

            $emptyData = [ordered]@{
                DefenderAlerts                  = @()
                DefenderAssessments             = @()
                DefenderPricing                 = @()
                DefenderSecureScores            = @()
                DefenderSecureScoreControls     = @()
                SubscriptionDiagnosticSettings  = @()
                PolicyComplianceStates          = @()
            }
            $statuses = [ordered]@{}
            $collectionErrors = [System.Collections.Generic.List[object]]::new()

            try {
                $contextParams = @{ Subscription = $subscriptionId; ErrorAction = 'Stop' }
                if ($subscriptionTenantId) { $contextParams['Tenant'] = $subscriptionTenantId }
                Set-AzContext @contextParams | Out-Null
            }
            catch {
                $message = $_.Exception.Message
                Write-Warning "Get-ScoutSubscriptionSecurityPolicySweep: could not enter subscription context '$subscriptionName': $message"
                foreach ($datasetName in $emptyData.Keys) {
                    $statuses[$datasetName] = 'Skipped'
                }
                $collectionErrors.Add([pscustomobject]@{
                        Dataset = 'Context'
                        Message = $message
                    })

                [pscustomobject]@{
                    id               = "/subscriptions/$subscriptionId/providers/AzureScout/securityPolicySweep/default"
                    name             = 'default'
                    type             = 'AZSC/Subscription/SecurityPolicySweep'
                    subscriptionId   = $subscriptionId
                    subscriptionName = $subscriptionName
                    properties       = [pscustomobject]@{
                        DefenderAlerts                 = @()
                        DefenderAssessments            = @()
                        DefenderPricing                = @()
                        DefenderSecureScores           = @()
                        DefenderSecureScoreControls    = @()
                        SubscriptionDiagnosticSettings = @()
                        PolicyComplianceStates         = @()
                        CollectionStatus               = [pscustomobject] $statuses
                        CollectionErrors               = @($collectionErrors)
                    }
                }
                continue
            }

            $queries = [ordered]@{}
            $queries.DefenderAlerts = Invoke-ScoutSweepDataset `
                -Dataset 'DefenderAlerts' `
                -SubscriptionName $subscriptionName `
                -MaxAttempts 3 `
                -ProviderRegistrationIsUnavailable `
                -Operation { Get-ScoutDefenderAlerts -SubscriptionId $subscriptionId }

            $queries.DefenderAssessments = Invoke-ScoutSweepDataset `
                -Dataset 'DefenderAssessments' `
                -SubscriptionName $subscriptionName `
                -MaxAttempts 3 `
                -ProviderRegistrationIsUnavailable `
                -Operation { Get-ScoutDefenderAssessments -SubscriptionId $subscriptionId }

            $queries.DefenderPricing = Invoke-ScoutDefenderPricingDataset -SubscriptionName $subscriptionName

            $queries.DefenderSecureScores = Invoke-ScoutSweepDataset `
                -Dataset 'DefenderSecureScores' `
                -SubscriptionName $subscriptionName `
                -Operation { Get-AzSecuritySecureScore -ErrorAction Stop }

            if (@($queries.DefenderSecureScores.Data).Count -gt 0) {
                $queries.DefenderSecureScoreControls = Invoke-ScoutSweepDataset `
                    -Dataset 'DefenderSecureScoreControls' `
                    -SubscriptionName $subscriptionName `
                    -Operation { Get-AzSecuritySecureScoreControl -ErrorAction Stop }
            }
            else {
                $queries.DefenderSecureScoreControls = [pscustomobject]@{
                    Data   = @()
                    Status = 'Skipped'
                    Error  = $null
                }
            }

            $resourceId = "/subscriptions/$subscriptionId"
            $queries.SubscriptionDiagnosticSettings = Invoke-ScoutSweepDataset `
                -Dataset 'SubscriptionDiagnosticSettings' `
                -SubscriptionName $subscriptionName `
                -Operation { Get-AzDiagnosticSetting -ResourceId $resourceId -ErrorAction Stop }

            $queries.PolicyComplianceStates = Invoke-ScoutSweepDataset `
                -Dataset 'PolicyComplianceStates' `
                -SubscriptionName $subscriptionName `
                -Operation { Get-AzPolicyState -SubscriptionId $subscriptionId -ErrorAction Stop }

            foreach ($datasetName in @($emptyData.Keys)) {
                $query = $queries[$datasetName]
                $emptyData[$datasetName] = @($query.Data)
                $statuses[$datasetName] = $query.Status
                if ($null -ne $query.Error) {
                    $collectionErrors.Add($query.Error)
                }
            }

            [pscustomobject]@{
                id               = "/subscriptions/$subscriptionId/providers/AzureScout/securityPolicySweep/default"
                name             = 'default'
                type             = 'AZSC/Subscription/SecurityPolicySweep'
                subscriptionId   = $subscriptionId
                subscriptionName = $subscriptionName
                properties       = [pscustomobject]@{
                    DefenderAlerts                 = @($emptyData.DefenderAlerts)
                    DefenderAssessments            = @($emptyData.DefenderAssessments)
                    DefenderPricing                = @($emptyData.DefenderPricing)
                    DefenderSecureScores           = @($emptyData.DefenderSecureScores)
                    DefenderSecureScoreControls    = @($emptyData.DefenderSecureScoreControls)
                    SubscriptionDiagnosticSettings = @($emptyData.SubscriptionDiagnosticSettings)
                    PolicyComplianceStates         = @($emptyData.PolicyComplianceStates)
                    CollectionStatus               = [pscustomobject] $statuses
                    CollectionErrors               = @($collectionErrors)
                }
            }
        }
    }
    finally {
        $restoreId = $null
        if (
            $null -ne $originalContext -and
            $null -ne $originalContext.PSObject.Properties['Subscription'] -and
            $null -ne $originalContext.Subscription -and
            $null -ne $originalContext.Subscription.PSObject.Properties['Id']
        ) {
            $restoreId = [string] $originalContext.Subscription.Id
        }
        if (-not [string]::IsNullOrWhiteSpace($restoreId)) {
            try {
                $restoreParams = @{ Subscription = $restoreId; ErrorAction = 'Stop' }
                if ($null -ne $originalContext.PSObject.Properties['Tenant'] -and $null -ne $originalContext.Tenant -and $null -ne $originalContext.Tenant.PSObject.Properties['Id'] -and $originalContext.Tenant.Id) {
                    $restoreParams['Tenant'] = $originalContext.Tenant.Id
                }
                Set-AzContext @restoreParams | Out-Null
            }
            catch {
                Write-Warning "Get-ScoutSubscriptionSecurityPolicySweep: could not restore subscription context '$restoreId': $($_.Exception.Message)"
            }
        }
    }

    return @($results)
}
