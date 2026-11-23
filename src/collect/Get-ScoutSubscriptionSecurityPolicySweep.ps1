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
        [object[]] $Subscriptions,

        # Read Defender assessments for every subscription at the same time before the
        # per-subscription pass. The assessments list is the slowest call in the sweep.
        [switch] $PrefetchAssessments
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

                # Regulatory compliance exists only on subscriptions with a paid Defender for Cloud
                # plan. On the free tier Azure answers "Regulatory compliance is not supported for
                # subscription '<id>' as it has no standard pricing bundle". That is the state of
                # the subscription, not a failed read: one field tenant raised this warning for
                # eight of its nine subscriptions on every scan.
                $notOfferedOnThisTier = $message -match '(?i)Regulatory compliance is not supported for subscription.+no standard pricing bundle'

                if ($providerUnavailable -or $notOfferedOnThisTier) {
                    # The reason travels with the result so collection health can say why the
                    # dataset is empty, instead of a bare "not available".
                    return [pscustomobject]@{
                        Data   = @()
                        Status = 'Unavailable'
                        Error  = $null
                        Reason = if ($notOfferedOnThisTier) {
                            'Not applicable: regulatory compliance needs a paid Microsoft Defender for Cloud plan, and this subscription is on the free tier.'
                        }
                        else {
                            'Not applicable: the Microsoft.Security resource provider is not registered on this subscription.'
                        }
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
            return [pscustomobject]@{
                Data   = @()
                Status = 'Unavailable'
                Error  = $null
                Reason = 'Not applicable: the Microsoft.Security resource provider is not registered on this subscription.'
            }
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

    function Get-ScoutDefenderAssessmentPrefetch {
        param(
            [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SubscriptionIds,
            [string]$TenantId
        )

        # Returns subscriptionId -> raw REST assessment rows for every subscription whose list
        # call succeeded. A subscription that is missing here is read by the per-subscription
        # pass exactly as before, so a failed or unavailable prefetch costs nothing but time.
        $prefetched = @{}
        if ($SubscriptionIds.Count -lt 2) { return $prefetched }

        try {
            $armUrl = 'https://management.azure.com/'
            $context = Get-AzContext -ErrorAction SilentlyContinue
            if ($null -ne $context -and $null -ne $context.PSObject.Properties['Environment'] -and $null -ne $context.Environment -and
                $null -ne $context.Environment.PSObject.Properties['ResourceManagerUrl'] -and
                -not [string]::IsNullOrWhiteSpace([string]$context.Environment.ResourceManagerUrl)) {
                $armUrl = [string]$context.Environment.ResourceManagerUrl
            }
            $tokenParams = @{ ResourceUrl = $armUrl; AsSecureString = $true; ErrorAction = 'Stop'; WarningAction = 'SilentlyContinue' }
            if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $tokenParams['TenantId'] = $TenantId }
            $token = Get-AzAccessToken @tokenParams
            $authorization = 'Bearer ' + ($token.Token | ConvertFrom-SecureString -AsPlainText)
        }
        catch {
            Write-Verbose "Get-ScoutSubscriptionSecurityPolicySweep: assessment prefetch skipped, no ARM token: $($_.Exception.Message)"
            return $prefetched
        }

        $baseUrl = $armUrl.TrimEnd('/')
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $SubscriptionIds | ForEach-Object -ThrottleLimit 8 -Parallel {
                $subscriptionId = $_
                $rows = [System.Collections.Generic.List[object]]::new()
                $uri = "$using:baseUrl/subscriptions/$subscriptionId/providers/Microsoft.Security/assessments?api-version=2021-06-01"
                try {
                    do {
                        # A single 502 from Defender used to send the whole subscription to the
                        # slow per-subscription pass (about a minute on a live tenant). Retry a
                        # transient answer twice before giving up on the prefetch.
                        $attempt = 0
                        while ($true) {
                            try {
                                $response = Invoke-RestMethod -Uri $uri -Method GET -Headers @{ Authorization = $using:authorization } -TimeoutSec 120 -ErrorAction Stop
                                break
                            }
                            catch {
                                $attempt++
                                $statusCode = 0
                                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
                                $transient = $statusCode -in @(408, 429, 500, 502, 503, 504) -or
                                    $_.Exception -is [System.Threading.Tasks.TaskCanceledException] -or
                                    [string]$_.Exception.Message -match '(?i)timed out|Bad Gateway|Service Unavailable|Gateway Timeout'
                                if (-not $transient -or $attempt -ge 3) { throw }
                                Start-Sleep -Milliseconds (500 * $attempt)
                            }
                        }
                        $uri = $null
                        if ($null -ne $response) {
                            if ($response.PSObject.Properties.Name -contains 'value') {
                                foreach ($row in @($response.value)) { if ($null -ne $row) { $rows.Add($row) } }
                            }
                            if ($response.PSObject.Properties.Name -contains 'nextLink') { $uri = [string]$response.nextLink }
                        }
                    } while (-not [string]::IsNullOrWhiteSpace($uri))
                    [pscustomobject]@{ SubscriptionId = $subscriptionId; Rows = $rows.ToArray(); Error = '' }
                }
                catch {
                    [pscustomobject]@{ SubscriptionId = $subscriptionId; Rows = @(); Error = [string]$_.Exception.Message }
                }
            } | ForEach-Object {
                if ([string]::IsNullOrEmpty($_.Error)) { $prefetched[[string]$_.SubscriptionId] = @($_.Rows) }
                else { Write-Verbose "Get-ScoutSubscriptionSecurityPolicySweep: assessment prefetch failed for one subscription, it will be read in the per-subscription pass: $($_.Error)" }
            }
        }
        catch {
            Write-Verbose "Get-ScoutSubscriptionSecurityPolicySweep: assessment prefetch unavailable: $($_.Exception.Message)"
        }
        Write-Verbose ('Get-ScoutSubscriptionSecurityPolicySweep: assessment prefetch read {0} of {1} subscription(s) in {2} ms' -f $prefetched.Count, $SubscriptionIds.Count, $timer.ElapsedMilliseconds)
        return $prefetched
    }

    function Get-ScoutPolicyStatePrefetch {
        <#
            Get-AzPolicyState is the slowest call in this sweep (about 4.4 s per subscription on a
            live tenant, 3 minutes across 42 subscriptions, strictly one after another). Run the
            SAME cmdlet for up to 8 subscriptions at once. The objects are the cmdlet's own
            PolicyState objects, so nothing downstream sees a different shape: on nine live
            subscriptions the parallel and serial results serialised byte-for-byte identical.
            A subscription that fails here is simply absent and goes through the ordinary
            per-subscription call, which owns retries, classification and health.
        #>
        param([string[]]$SubscriptionIds)
        $prefetched = @{}
        if (@($SubscriptionIds).Count -lt 2) { return $prefetched }
        $policyCommand = Get-Command Get-AzPolicyState -ErrorAction SilentlyContinue
        # A stub or mock stands in for the cmdlet in tests: every call must go through it.
        if ($null -eq $policyCommand -or $policyCommand.CommandType -ne 'Cmdlet') { return $prefetched }
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $SubscriptionIds | ForEach-Object -ThrottleLimit 8 -Parallel {
                $subscriptionId = $_
                try {
                    [pscustomobject]@{ SubscriptionId = $subscriptionId; Rows = @(Get-AzPolicyState -SubscriptionId $subscriptionId -ErrorAction Stop -WarningAction SilentlyContinue); Error = '' }
                }
                catch { [pscustomobject]@{ SubscriptionId = $subscriptionId; Rows = @(); Error = [string]$_.Exception.Message } }
            } | ForEach-Object {
                if ([string]::IsNullOrEmpty($_.Error)) { $prefetched[[string]$_.SubscriptionId] = @($_.Rows) }
                else { Write-Verbose "Get-ScoutSubscriptionSecurityPolicySweep: policy-state prefetch failed for one subscription, it will be read in the per-subscription pass: $($_.Error)" }
            }
        }
        catch { Write-Verbose "Get-ScoutSubscriptionSecurityPolicySweep: policy-state prefetch unavailable: $($_.Exception.Message)" }
        Write-Verbose ('Get-ScoutSubscriptionSecurityPolicySweep: policy-state prefetch read {0} of {1} subscription(s) in {2} ms' -f $prefetched.Count, @($SubscriptionIds).Count, $timer.ElapsedMilliseconds)
        return $prefetched
    }

    $prefetchedPolicyStates = Get-ScoutPolicyStatePrefetch -SubscriptionIds @(foreach ($candidate in $Subscriptions) {
            $candidateId = if ($null -ne $candidate) { $candidate.PSObject.Properties['id'] } else { $null }
            if ($null -ne $candidateId -and -not [string]::IsNullOrWhiteSpace([string]$candidateId.Value)) { [string]$candidateId.Value }
        })

    $prefetchedAssessments = @{}
    if ($PrefetchAssessments) {
        $prefetchIds = @(foreach ($candidate in $Subscriptions) {
                $candidateId = if ($null -ne $candidate) { $candidate.PSObject.Properties['id'] } else { $null }
                if ($null -ne $candidateId -and -not [string]::IsNullOrWhiteSpace([string]$candidateId.Value)) { [string]$candidateId.Value }
            })
        $prefetchTenantId = if ($null -ne $originalContext -and $null -ne $originalContext.PSObject.Properties['Tenant'] -and $null -ne $originalContext.Tenant -and $null -ne $originalContext.Tenant.PSObject.Properties['Id']) {
            [string]$originalContext.Tenant.Id
        }
        else { '' }
        $prefetchedAssessments = Get-ScoutDefenderAssessmentPrefetch -SubscriptionIds $prefetchIds -TenantId $prefetchTenantId
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
                DefenderRegulatoryStandards     = @()
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
                        DefenderRegulatoryStandards    = @()
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
                -Operation {
                    if ($prefetchedAssessments.ContainsKey($subscriptionId)) {
                        @(foreach ($prefetchedRow in @($prefetchedAssessments[$subscriptionId])) {
                                if ($null -ne $prefetchedRow) { ConvertFrom-ScoutDefenderAssessmentRestRow -Assessment $prefetchedRow }
                            })
                    }
                    else { Get-ScoutDefenderAssessments -SubscriptionId $subscriptionId }
                }

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

            $queries.DefenderRegulatoryStandards = Invoke-ScoutSweepDataset -Dataset 'DefenderRegulatoryStandards' -SubscriptionName $subscriptionName -ProviderRegistrationIsUnavailable -Operation {
                Get-AzRegulatoryComplianceStandard -ErrorAction Stop
            }

            $resourceId = "/subscriptions/$subscriptionId"
            $queries.SubscriptionDiagnosticSettings = Invoke-ScoutSweepDataset `
                -Dataset 'SubscriptionDiagnosticSettings' `
                -SubscriptionName $subscriptionName `
                -Operation { Get-AzDiagnosticSetting -ResourceId $resourceId -ErrorAction Stop }

            $queries.PolicyComplianceStates = Invoke-ScoutSweepDataset `
                -Dataset 'PolicyComplianceStates' `
                -SubscriptionName $subscriptionName `
                -Operation {
                    if ($prefetchedPolicyStates.ContainsKey($subscriptionId)) { @($prefetchedPolicyStates[$subscriptionId]) }
                    else { Get-AzPolicyState -SubscriptionId $subscriptionId -ErrorAction Stop }
                }

            $reasons = [ordered]@{}
            foreach ($datasetName in @($emptyData.Keys)) {
                $query = $queries[$datasetName]
                $emptyData[$datasetName] = @($query.Data)
                $statuses[$datasetName] = $query.Status
                if ($null -ne $query.Error) {
                    $collectionErrors.Add($query.Error)
                }
                $reasonProperty = $query.PSObject.Properties['Reason']
                if ($reasonProperty -and -not [string]::IsNullOrWhiteSpace([string]$reasonProperty.Value)) {
                    $reasons[$datasetName] = [string]$reasonProperty.Value
                }
            }

            $operationNames = @{
                DefenderAlerts = 'Get-AzSecurityAlert / ARM alerts fallback'
                DefenderAssessments = 'Get-AzSecurityAssessment / ARM assessments fallback'
                DefenderPricing = 'Get-AzSecurityPricing'
                DefenderSecureScores = 'Get-AzSecuritySecureScore'
                DefenderSecureScoreControls = 'Get-AzSecuritySecureScoreControl'
                DefenderRegulatoryStandards = 'Get-AzRegulatoryComplianceStandard'
                SubscriptionDiagnosticSettings = 'Get-AzDiagnosticSetting'
                PolicyComplianceStates = 'Get-AzPolicyState'
            }
            $sourceOperations = @($queries.Keys | ForEach-Object {
                    $datasetName = [string]$_
                    $queryResult = $queries[$datasetName]
                    [pscustomobject][ordered]@{
                        Source = 'Azure PowerShell control plane'
                        Dataset = $datasetName
                        SubscriptionId = $subscriptionId
                        Operation = $operationNames[$datasetName]
                        Status = $queryResult.Status
                        Count = @($queryResult.Data).Count
                        Reason = if ($queryResult.Error) { $queryResult.Error.Message } else { $null }
                    }
                })

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
                    DefenderRegulatoryStandards    = @($emptyData.DefenderRegulatoryStandards)
                    SubscriptionDiagnosticSettings = @($emptyData.SubscriptionDiagnosticSettings)
                    PolicyComplianceStates         = @($emptyData.PolicyComplianceStates)
                    CollectionStatus               = [pscustomobject] $statuses
                    CollectionErrors               = @($collectionErrors)
                    CollectionReasons              = [pscustomobject] $reasons
                    SourceOperations               = $sourceOperations
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
