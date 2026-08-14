#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Prefetch live operational data used by legacy inventory collectors.

.DESCRIPTION
    Produces stable synthetic envelopes for collectors that currently make ARM or Az cmdlet calls
    inside a row loop.  This is intentionally an isolated collect-phase capability: it does not
    yet alter raw-inventory integration, collector scripts, or definitions.

    A failed request is recorded on only its owning parent envelope.  Other parents and datasets
    continue.  Payloads are retained as returned (rather than prematurely shaping report fields),
    so the subsequent definition migration has one auditable source contract.

.OUTPUTS
    Typed envelopes: AZSC/Operational/VirtualMachine, AZSC/Operational/VMOperationalData,
    AZSC/Operational/ArcServerOperationalData, AZSC/Operational/ARCServers,
    AZSC/Operational/StorageAccount, AZSC/Operational/NetworkInterface, and
    AZSC/Management/SubscriptionEnrichment.
#>
function Get-ScoutOperationalCollectorEnrichment {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Subscriptions = @(),

        [Parameter()]
        [AllowNull()]
        [System.Collections.IList]$CollectionHealth,

        [switch]$IncludeProviderResourceDetails
    )

    function Get-ScoutValue {
        param([AllowNull()]$InputObject, [Parameter(Mandatory)][string[]]$Name)
        if ($null -eq $InputObject) { return $null }
        foreach ($Candidate in $Name) {
            $Property = $InputObject.PSObject.Properties[$Candidate]
            if ($null -ne $Property) { return $Property.Value }
        }
        return $null
    }

    function Get-ScoutUniqueResource {
        param([AllowEmptyCollection()][object[]]$InputRows)
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($inputRow in @($InputRows)) {
            if ($null -eq $inputRow) { continue }
            $resourceId = [string](Get-ScoutValue $inputRow @('id', 'ID'))
            if ([string]::IsNullOrWhiteSpace($resourceId) -or -not $seen.Add($resourceId)) { continue }
            $inputRow
        }
    }

    $VirtualMachines = @(Get-ScoutUniqueResource -InputRows @($Resources | Where-Object { (Get-ScoutValue $_ @('type', 'TYPE')) -ieq 'microsoft.compute/virtualmachines' }))
    $ArcMachines = @(Get-ScoutUniqueResource -InputRows @($Resources | Where-Object { (Get-ScoutValue $_ @('type', 'TYPE')) -ieq 'microsoft.hybridcompute/machines' }))
    $StorageAccounts = @(Get-ScoutUniqueResource -InputRows @($Resources | Where-Object { (Get-ScoutValue $_ @('type', 'TYPE')) -ieq 'microsoft.storage/storageaccounts' }))
    $NetworkInterfaces = @(Get-ScoutUniqueResource -InputRows @($Resources | Where-Object { (Get-ScoutValue $_ @('type', 'TYPE')) -ieq 'microsoft.network/networkinterfaces' }))
    $VmSubscriptionCount = @($VirtualMachines | ForEach-Object { [string](Get-ScoutValue $_ @('subscriptionId')) } | Where-Object { $_ } | Sort-Object -Unique).Count
    $ProgressState = @{
        Planned  = (($VirtualMachines.Count * 4) + $VmSubscriptionCount + ($ArcMachines.Count * 2) + ($NetworkInterfaces.Count * 2))
        Completed = 0
        Failed    = 0
        Started   = [System.Diagnostics.Stopwatch]::StartNew()
    }
    $OperationalHealthDatasets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Add-ScoutOperationalHealth {
        param(
            [Parameter(Mandatory)][string]$Dataset,
            [Parameter(Mandatory)][string]$Reason,
            [AllowNull()][string]$ParentId,
            [AllowNull()][string]$ResourceType,
            [AllowNull()][string]$Collector
        )
        $healthKey = "$Dataset|$ParentId"
        if ($null -eq $CollectionHealth -or -not $OperationalHealthDatasets.Add($healthKey)) { return }

        $ownership = if ($Dataset -like 'VirtualMachine.*') {
            [pscustomobject]@{ ResourceType = 'AZSC/Operational/VirtualMachine'; Collector = 'Compute/VirtualMachine' }
        }
        elseif ($Dataset -like 'ARCServers.*') {
            [pscustomobject]@{ ResourceType = 'AZSC/Operational/ARCServers'; Collector = 'Hybrid/ARCServers' }
        }
        elseif ($Dataset -like 'StorageAccounts.*' -and $Dataset -ne 'StorageAccounts.RestoreSubscriptionContext') {
            [pscustomobject]@{ ResourceType = 'AZSC/Operational/StorageAccount'; Collector = 'Storage/StorageAccounts' }
        }
        elseif ($Dataset -like 'NetworkInterface.*') {
            [pscustomobject]@{ ResourceType = 'microsoft.network/networkinterfaces'; Collector = 'Networking/NetworkInterface' }
        }
        elseif ($Dataset -like 'AllSubscriptions.*') {
            [pscustomobject]@{ ResourceType = 'AZSC/Management/SubscriptionEnrichment'; Collector = 'Management/AllSubscriptions' }
        }
        elseif ($ResourceType -and $Collector) {
            [pscustomobject]@{ ResourceType = $ResourceType; Collector = $Collector }
        }
        else { $null }
        if ($null -eq $ownership) { return }

        [void]$CollectionHealth.Add([pscustomobject]@{
                Dataset       = "Operational/$Dataset"
                Source        = 'Operational enrichment'
                SourceDataset = $Dataset
                Status        = 'Unavailable'
                Reason        = $Reason
                ResourceTypes = @($ownership.ResourceType)
                Collectors     = @($ownership.Collector)
                ResourceIds    = @($ParentId | Where-Object { $_ })
            })
    }

    function Write-ScoutOperationalDetail {
        param(
            [Parameter(Mandatory)][ValidateSet('DEBUG', 'VERBOSE')][string]$Level,
            [Parameter(Mandatory)][string]$Message
        )
        if (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level $Level -Message $Message
        }
    }

    function Start-ScoutOperationalRequest {
        param([Parameter(Mandatory)][string]$Dataset, [switch]$Dynamic)
        if ($Dynamic.IsPresent) { $ProgressState.Planned++ }
        Write-ScoutOperationalDetail -Level DEBUG -Message (
            'Operational request started: dataset={0}; ordinal={1}; planned={2}' -f
                $Dataset, ($ProgressState.Completed + 1), $ProgressState.Planned
        )
        return [System.Diagnostics.Stopwatch]::StartNew()
    }

    function Complete-ScoutOperationalRequest {
        param(
            [Parameter(Mandatory)][string]$Dataset,
            [Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Timer,
            [Parameter(Mandatory)][ValidateSet('Success', 'Failed', 'NotConfigured', 'OperationInProgress')][string]$Status,
            [int]$Attempts = 1
        )
        $Timer.Stop()
        $ProgressState.Completed++
        if ($Status -in @('Failed', 'OperationInProgress')) { $ProgressState.Failed++ }
        $denominator = [Math]::Max(1, [int]$ProgressState.Planned)
        $percent = [Math]::Min(99, [int](100 * $ProgressState.Completed / $denominator))
        $progressStatus = 'Operational enrichment: {0}/{1} requests; {2} unavailable' -f
            $ProgressState.Completed, $ProgressState.Planned, $ProgressState.Failed
        if (Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue) {
            Write-ScoutProgress -Id 3 -ParentId 2 -Activity 'Operational enrichment' `
                -Status $progressStatus -PercentComplete $percent
        }
        else {
            Write-Progress -Id 3 -ParentId 2 -Activity 'Operational enrichment' `
                -Status $progressStatus -PercentComplete $percent
        }
        Write-ScoutOperationalDetail -Level VERBOSE -Message (
            'Operational request finished: dataset={0}; status={1}; attempts={2}; elapsed={3}; completed={4}; planned={5}; unavailable={6}' -f
                $Dataset, $Status, $Attempts, $Timer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff'),
                $ProgressState.Completed, $ProgressState.Planned, $ProgressState.Failed
        )
    }

    function Invoke-ScoutOperationalTrackedCommand {
        param(
            [Parameter(Mandatory)][string]$Dataset,
            [Parameter(Mandatory)][scriptblock]$Operation
        )
        $timer = Start-ScoutOperationalRequest -Dataset $Dataset -Dynamic
        try {
            $result = & $Operation
            Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $timer -Status Success
            return $result
        }
        catch {
            Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $timer -Status Failed
            Add-ScoutOperationalHealth -Dataset $Dataset -Reason $_.Exception.Message
            throw
        }
    }

    Write-ScoutOperationalDetail -Level DEBUG -Message (
        'Operational enrichment plan: virtualMachines={0}; arcMachines={1}; storageAccounts={2}; networkInterfaces={3}; subscriptions={4}; minimumRequests={5}' -f
            $VirtualMachines.Count, $ArcMachines.Count, $StorageAccounts.Count, $NetworkInterfaces.Count, @($Subscriptions).Count, $ProgressState.Planned
    )
    $progressStatus = 'Operational enrichment planned: {0} VM; {1} Arc; {2} storage; {3} NIC' -f
        $VirtualMachines.Count, $ArcMachines.Count, $StorageAccounts.Count, $NetworkInterfaces.Count
    if (Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue) {
        Write-ScoutProgress -Id 3 -ParentId 2 -Activity 'Operational enrichment' `
            -Status $progressStatus -PercentComplete 0
    }
    else {
        Write-Progress -Id 3 -ParentId 2 -Activity 'Operational enrichment' `
            -Status $progressStatus -PercentComplete 0
    }

    function Invoke-ScoutOperationalArm {
        param(
            [Parameter(Mandatory)][string]$Dataset,
            [Parameter(Mandatory)][string]$ParentId,
            [Parameter(Mandatory)][string]$Path,
            [ValidateSet('GET', 'POST')][string]$Method = 'GET',
            [AllowNull()]$Payload,
            [ValidateRange(1, 5)][int]$MaxAttempts = 3,
            [switch]$PollAsync,
            # 404 on this dataset is an expected "not configured" state, not a failure -- do not warn.
            [switch]$QuietNotFound,
            [switch]$DynamicRequest
        )

        $requestTimer = Start-ScoutOperationalRequest -Dataset $Dataset -Dynamic:$DynamicRequest
        for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
            try {
                $Arguments = @{ Path = $Path; Method = $Method; ErrorAction = 'Stop' }
                if ($null -ne $Payload) { $Arguments['Payload'] = $Payload }
                $Response = Invoke-AzRestMethod @Arguments
                if ($null -eq $Response) { throw 'ARM returned no response.' }
                $Status = Get-ScoutValue -InputObject $Response -Name @('StatusCode')
                if ([int]$Status -eq 202 -and $PollAsync) {
                    $headers = Get-ScoutValue -InputObject $Response -Name @('Headers')
                    $location = $null
                    if ($headers -is [System.Collections.IDictionary]) {
                        foreach ($headerKey in $headers.Keys) {
                            if ([string]$headerKey -notin @('Location', 'Azure-AsyncOperation')) { continue }
                            $location = [string]$headers[$headerKey]
                            if ($location) { break }
                        }
                    }
                    elseif ($null -ne $headers) {
                        $location = [string](Get-ScoutValue -InputObject $headers -Name @('Location', 'Azure-AsyncOperation'))
                    }
                    if ([string]::IsNullOrWhiteSpace($location)) {
                        throw 'ARM returned status 202 without a Location or Azure-AsyncOperation header.'
                    }
                    $pollComplete = $false
                    for ($pollAttempt = 1; $pollAttempt -le 30; $pollAttempt++) {
                        if ($pollAttempt -gt 1) { Start-Sleep -Milliseconds 1000 }
                        $pollArguments = @{ Method = 'GET'; ErrorAction = 'Stop' }
                        if ($location -match '^https?://') { $pollArguments['Uri'] = $location }
                        else { $pollArguments['Path'] = $location }
                        $Response = Invoke-AzRestMethod @pollArguments
                        if ($null -eq $Response) { throw 'ARM async status request returned no response.' }
                        $Status = Get-ScoutValue -InputObject $Response -Name @('StatusCode')
                        if ([int]$Status -eq 202) { continue }
                        $pollComplete = $true
                        break
                    }
                    if (-not $pollComplete) { throw 'ARM asynchronous request did not complete within 30 seconds.' }
                }
                if ($null -ne $Status -and ([int]$Status -lt 200 -or [int]$Status -ge 300)) {
                    throw "ARM returned status $Status."
                }
                $Content = Get-ScoutValue -InputObject $Response -Name @('Content')
                if ($Content -is [string]) {
                    if ([string]::IsNullOrWhiteSpace($Content)) {
                        Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $requestTimer -Status Success -Attempts $Attempt
                        return $null
                    }
                    $result = $Content | ConvertFrom-Json
                    Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $requestTimer -Status Success -Attempts $Attempt
                    return $result
                }
                Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $requestTimer -Status Success -Attempts $Attempt
                return $Content
            }
            catch {
                $Message = $_.Exception.Message
                $StatusMatch = [regex]::Match($Message, 'ARM returned status (\d+)')
                $StatusCode = if ($StatusMatch.Success) { [int]$StatusMatch.Groups[1].Value } else { $null }

                if ($StatusCode -eq 404 -and $QuietNotFound) {
                    Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $requestTimer -Status NotConfigured -Attempts $Attempt
                    return [PSCustomObject]@{ __AZSCStatus = 'NotConfigured' }
                }

                # 429 (rate limit), 409 (operation already in-flight/too-recent), and transient 5xx
                # all warrant a retry with backoff rather than an immediate hard failure.
                $Retryable = ($StatusCode -in 429, 409, 500, 502, 503, 504) -or
                    ($Message -match '(?i)InternalServerError|BadGateway|ServiceUnavailable|GatewayTimeout|TooManyRequests')
                if ($Retryable -and $Attempt -lt $MaxAttempts) {
                    Write-ScoutOperationalDetail -Level DEBUG -Message (
                        'Operational request retry: dataset={0}; attempt={1}; maximum={2}' -f $Dataset, $Attempt, $MaxAttempts
                    )
                    Start-Sleep -Milliseconds (500 * $Attempt)
                    continue
                }

                if ($StatusCode -eq 409) {
                    Write-Warning "Get-ScoutOperationalCollectorEnrichment: $Dataset for '$ParentId' still in progress (409) after $Attempt attempt(s)."
                    Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $requestTimer -Status OperationInProgress -Attempts $Attempt
                    Add-ScoutOperationalHealth -Dataset $Dataset -Reason "The Azure operation remained in progress (HTTP 409) after $Attempt attempt(s)." -ParentId $ParentId
                    return [PSCustomObject]@{ __AZSCStatus = 'OperationInProgress' }
                }

                Write-Warning "Get-ScoutOperationalCollectorEnrichment: $Dataset failed for '$ParentId': $Message"
                Complete-ScoutOperationalRequest -Dataset $Dataset -Timer $requestTimer -Status Failed -Attempts $Attempt
                Add-ScoutOperationalHealth -Dataset $Dataset -Reason $Message -ParentId $ParentId
                return [PSCustomObject]@{ __AZSCError = $Message }
            }
        }
    }

    function ConvertTo-ScoutPatchAssessmentSummary {
        <#
            Shapes the Azure Update Manager `patchassessmentresources` row for one machine into the
            same property bag the previous `POST .../assessPatches` response produced, so the
            VMOperationalData / ArcServerOperationalData collectors need no change.

            Update Manager writes a `<machineId>/patchAssessmentResults/latest` row per assessed
            machine, whose properties carry `availablePatchCountByClassification` (a bag keyed by
            OS-vendor classification) rather than the flat `criticalAndSecurityPatchCount` /
            `otherPatchCount` the action response returned. Windows and Linux name those
            classifications differently, so both vocabularies are folded here:

              critical/security  Windows 'Critical' + 'Security'   Linux 'Security'
              other              everything else reported

            A machine Update Manager has not assessed inside its 7-day retention window has no row.
            That returns a NotAssessed status rather than a zero count -- "no data" and "no pending
            patches" are different findings and must not render identically.
        #>
        param(
            [Parameter(Mandatory)][string]$MachineId,
            [AllowEmptyCollection()][object[]]$Resources
        )

        $Prefix = "$MachineId/patchAssessmentResults/"
        $Row = @($Resources | Where-Object {
            $RowId = [string](Get-ScoutValue $_ @('id', 'ID'))
            $RowType = [string](Get-ScoutValue $_ @('type', 'TYPE'))
            $RowId -like "$Prefix*" -and $RowType -notlike '*/softwarepatches'
        } | Select-Object -First 1)

        if ($Row.Count -eq 0) {
            return [PSCustomObject]@{ __AZSCStatus = 'NotAssessed' }
        }

        $Props = Get-ScoutValue $Row[0] @('properties', 'PROPERTIES')
        $ByClass = Get-ScoutValue $Props @('availablePatchCountByClassification')

        $Critical = 0
        $Other = 0
        if ($null -ne $ByClass) {
            foreach ($Entry in $ByClass.PSObject.Properties) {
                $Count = 0
                if (-not [int]::TryParse([string]$Entry.Value, [ref]$Count)) { continue }
                # Windows reports 'Critical'/'Security', Linux reports 'Security' -- match without
                # regard to case, since the vendor supplies these strings verbatim.
                if (@('critical', 'security') -contains $Entry.Name.ToLowerInvariant()) { $Critical += $Count }
                else { $Other += $Count }
            }
        }

        [PSCustomObject]@{
            criticalAndSecurityPatchCount = $Critical
            otherPatchCount               = $Other
            startDateTime                 = Get-ScoutValue $Props @('startDateTime')
            lastModifiedDateTime          = Get-ScoutValue $Props @('lastModifiedDateTime')
            rebootPending                 = Get-ScoutValue $Props @('rebootPending')
            patchServiceUsed              = Get-ScoutValue $Props @('patchServiceUsed')
            osType                        = Get-ScoutValue $Props @('osType')
        }
    }

    function ConvertTo-ScoutOperationalEnvelope {
        param(
            [Parameter(Mandatory)][string]$Type,
            [Parameter(Mandatory)]$Parent,
            [Parameter(Mandatory)][hashtable]$Properties
        )
        $Id = [string](Get-ScoutValue $Parent @('id', 'ID'))
        [PSCustomObject][ordered]@{
            type           = $Type
            id             = $Id
            subscriptionId = Get-ScoutValue $Parent @('subscriptionId', 'SubscriptionId')
            RESOURCEGROUP  = Get-ScoutValue $Parent @('resourceGroup', 'RESOURCEGROUP')
            name           = Get-ScoutValue $Parent @('name', 'NAME')
            properties     = [PSCustomObject]$Properties
        }
    }

    # Vault discovery is subscription-scoped and protected-item discovery is vault-scoped. The
    # legacy row-loop repeated both requests for every VM in the same subscription, multiplying a
    # fixed result by the VM count. Cache the raw response at its real owning scope; every VM still
    # receives the same ReplicationProtectedItems payload it did before.
    $VaultsBySubscription = @{}
    $ProtectedItemsByVault = @{}
    # Use one common metrics window for the run. Each VM still has its own CPU and memory request;
    # combining those calls would couple their independent failure envelopes and change the schema.
    $MetricNow = (Get-Date).ToUniversalTime().ToString('o')
    $MetricStart = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
    foreach ($Vm in $VirtualMachines) {
        $Id = [string](Get-ScoutValue $Vm @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $BaseMetric = "$Id/providers/microsoft.insights/metrics?api-version=2019-07-01&timespan=$MetricStart/$MetricNow&interval=P1D&aggregation=Average"
        # Keep the operational payloads at the collect boundary.  The two Compute report
        # collectors consume these envelopes later; they must never issue a per-row ARM call.
        # The Cost Management body deliberately retains the legacy ResourceId filter -- an
        # unfiltered `{}` query is not equivalent and can report a subscription total.
        $SubscriptionId = [string](Get-ScoutValue $Vm @('subscriptionId'))
        $VmName = [string](Get-ScoutValue $Vm @('name', 'NAME'))
        # 404 here means ASR has never evaluated this VM -- expected for most VMs, not a defect.
        $Eligibility = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.ReplicationEligibility' -ParentId $Id -QuietNotFound -Path "/subscriptions/$SubscriptionId/providers/Microsoft.RecoveryServices/replicationEligibilityResults/${VmName}?api-version=2022-10-01"
        if (-not $VaultsBySubscription.ContainsKey($SubscriptionId)) {
            $VaultsBySubscription[$SubscriptionId] = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.ReplicationVaults' -ParentId $Id -Path "/subscriptions/$SubscriptionId/providers/Microsoft.RecoveryServices/vaults?api-version=2023-04-01"
        }
        $Vaults = $VaultsBySubscription[$SubscriptionId]
        $ProtectedItems = @()
        if ($null -eq (Get-ScoutValue $Vaults @('__AZSCError'))) {
            foreach ($Vault in @(Get-ScoutValue $Vaults @('value'))) {
                $VaultId = [string](Get-ScoutValue $Vault @('id'))
                $VaultName = [string](Get-ScoutValue $Vault @('name'))
                $VaultSegments = @($VaultId -split '/')
                $VaultResourceGroup = if ($VaultSegments.Count -gt 4) { $VaultSegments[4] } else { $null }
                if ([string]::IsNullOrWhiteSpace($VaultResourceGroup) -or [string]::IsNullOrWhiteSpace($VaultName)) { continue }
                $VaultCacheKey = if (-not [string]::IsNullOrWhiteSpace($VaultId)) {
                    $VaultId.ToLowerInvariant()
                }
                else {
                    ("$SubscriptionId/$VaultResourceGroup/$VaultName").ToLowerInvariant()
                }
                if (-not $ProtectedItemsByVault.ContainsKey($VaultCacheKey)) {
                    $ProtectedItemsByVault[$VaultCacheKey] = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.ReplicationProtectedItems' -ParentId $VaultId -Path "/subscriptions/$SubscriptionId/resourceGroups/$VaultResourceGroup/providers/Microsoft.RecoveryServices/vaults/$VaultName/replicationProtectedItems?api-version=2022-10-01" -DynamicRequest
                }
                $ProtectedItems += $ProtectedItemsByVault[$VaultCacheKey]
            }
        }
        $CostPayload = @{
            type      = 'Usage'
            timeframe = 'MonthToDate'
            dataset   = @{
                granularity = 'None'
                filter      = @{ dimensions = @{ name = 'ResourceId'; operator = 'In'; values = @($Id) } }
                aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } }
            }
        } | ConvertTo-Json -Depth 10
        $Properties = @{
            CpuMetrics = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.CpuMetrics' -ParentId $Id -Path "$BaseMetric&metricnames=Percentage+CPU"
            MemoryMetrics = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.MemoryMetrics' -ParentId $Id -Path "$BaseMetric&metricnames=Available+Memory+Bytes"
            ReplicationEligibility = $Eligibility
            ReplicationProtectedItems = $ProtectedItems
            EstimatedCost = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.EstimatedCost' -ParentId $Id -Method POST -Path "/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-03-01" -Payload $CostPayload
        }
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/VirtualMachine' -Parent $Vm -Properties $Properties
    }

    # Patch data is READ from the Azure Update Manager Resource Graph tables
    # (`patchassessmentresources` / `patchinstallationresources`) in Get-ScoutRawInventory, not
    # obtained by commanding each machine to scan itself. The previous implementation POSTed
    # `{vmId}/assessPatches` here -- an ARM *action*, not a read -- which triggered a fresh
    # guest-OS scan on every VM in the tenant on every run. See AB#6731.
    foreach ($Vm in $VirtualMachines) {
        $Id = [string](Get-ScoutValue $Vm @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $Patch = ConvertTo-ScoutPatchAssessmentSummary -MachineId $Id -Resources $Resources
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/VMOperationalData' -Parent $Vm -Properties @{ PatchAssessment = $Patch }
    }

    foreach ($Arc in $ArcMachines) {
        $Id = [string](Get-ScoutValue $Arc @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $Patch = ConvertTo-ScoutPatchAssessmentSummary -MachineId $Id -Resources $Resources
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/ArcServerOperationalData' -Parent $Arc -Properties @{ PatchAssessment = $Patch }

        $SubId = [string](Get-ScoutValue $Arc @('subscriptionId'))
        $Policy = Invoke-ScoutOperationalArm -Dataset 'ARCServers.PolicyCompliance' -ParentId $Id -Method POST -Path "/subscriptions/$SubId/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=2019-10-01&`$filter=resourceId eq '$Id'&`$top=100" -Payload '{}'
        # Arc-enabled servers (Microsoft.HybridCompute/machines) do not publish guest-OS metrics
        # through the ARM Insights metrics API at all -- that endpoint only ever exposes host-level
        # platform metrics, and Arc has no Azure-managed host layer. Guest CPU/memory for Arc is only
        # available via Azure Monitor Agent -> Log Analytics (VM Insights Perf table), a different
        # data source. Calling microsoft.insights/metrics here 400s for every machine, always -- do
        # not call it. See ADO Bug 6733.
        $Cpu = [PSCustomObject]@{ __AZSCStatus = 'NotSupportedForArc' }
        $ArcCostPayload = @{ type = 'Usage'; timeframe = 'MonthToDate'; dataset = @{ granularity = 'None'; filter = @{ dimensions = @{ name = 'ResourceId'; operator = 'In'; values = @($Id) } }; aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } } } } | ConvertTo-Json -Depth 10
        $Cost = Invoke-ScoutOperationalArm -Dataset 'ARCServers.EstimatedCost' -ParentId $Id -Method POST -Path "/subscriptions/$SubId/providers/Microsoft.CostManagement/query?api-version=2023-03-01" -Payload $ArcCostPayload
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/ARCServers' -Parent $Arc -Properties @{ PolicyCompliance = $Policy; CpuMetrics = $Cpu; EstimatedCost = $Cost }
    }

    # AB#7367: configured route tables and NSG rules do not describe the state Azure actually
    # applies to a NIC after subnet associations, platform routes, BGP, peering, and multiple NSG
    # scopes are combined. These read-only POST actions return that effective control-plane state.
    # Every NIC receives an envelope even when either request is denied or unsupported, so the
    # discovery index can distinguish an unavailable detail from an absent NIC.
    foreach ($Nic in $NetworkInterfaces) {
        $Id = [string](Get-ScoutValue $Nic @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $effectiveNsgs = Invoke-ScoutOperationalArm `
            -Dataset 'NetworkInterface.EffectiveNetworkSecurityGroups' `
            -ParentId $Id `
            -Method POST `
            -PollAsync `
            -Path "$Id/effectiveNetworkSecurityGroups?api-version=2025-05-01"
        $effectiveRoutes = Invoke-ScoutOperationalArm `
            -Dataset 'NetworkInterface.EffectiveRouteTable' `
            -ParentId $Id `
            -Method POST `
            -PollAsync `
            -Path "$Id/effectiveRouteTable?api-version=2025-05-01"
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/NetworkInterface' -Parent $Nic -Properties @{
            EffectiveNetworkSecurityGroups = $effectiveNsgs
            EffectiveRouteTable            = $effectiveRoutes
        }
    }

    $SubscriptionsById = @{}
    foreach ($Subscription in @($Subscriptions)) {
        $SubscriptionKey = [string](Get-ScoutValue $Subscription @('id', 'Id'))
        if (-not [string]::IsNullOrWhiteSpace($SubscriptionKey) -and -not $SubscriptionsById.ContainsKey($SubscriptionKey)) {
            $SubscriptionsById[$SubscriptionKey] = $Subscription
        }
    }
    $StorageContext = Get-AzContext -ErrorAction SilentlyContinue
    $StorageIndexesBySubscription = @{}
    $StorageSubscriptionOrder = [System.Collections.Generic.List[string]]::new()
    for ($StorageIndex = 0; $StorageIndex -lt $StorageAccounts.Count; $StorageIndex++) {
        $StorageSubscriptionId = [string](Get-ScoutValue $StorageAccounts[$StorageIndex] @('subscriptionId', 'SubscriptionId'))
        if (-not $StorageIndexesBySubscription.ContainsKey($StorageSubscriptionId)) {
            $StorageIndexesBySubscription[$StorageSubscriptionId] = [System.Collections.Generic.List[int]]::new()
            $StorageSubscriptionOrder.Add($StorageSubscriptionId)
        }
        $StorageIndexesBySubscription[$StorageSubscriptionId].Add($StorageIndex)
    }
    $StorageResults = [object[]]::new($StorageAccounts.Count)
    try {
        # Enter each subscription once, collect every account in that scope, then move on. Results
        # are stored by original index and emitted afterward so grouping remote work does not change
        # the public envelope order.
        foreach ($SubscriptionId in $StorageSubscriptionOrder) {
            $StorageContextError = $null
            try {
                if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { throw 'Storage account has no subscriptionId.' }
                $contextParams = @{ Subscription = $SubscriptionId; ErrorAction = 'Stop' }
                $tenantId = if ($SubscriptionsById.ContainsKey($SubscriptionId)) {
                    Get-ScoutValue $SubscriptionsById[$SubscriptionId] @('tenantId', 'TenantId')
                }
                else { $null }
                if (-not $tenantId -and $StorageContext -and $StorageContext.Tenant) { $tenantId = $StorageContext.Tenant.Id }
                if ($tenantId) { $contextParams['Tenant'] = $tenantId }
                Invoke-ScoutOperationalTrackedCommand -Dataset 'StorageAccounts.EnterSubscriptionContext' -Operation {
                    Set-AzContext @contextParams | Out-Null
                } | Out-Null
            }
            catch {
                $StorageContextError = $_.Exception.Message
            }

            foreach ($AccountIndex in $StorageIndexesBySubscription[$SubscriptionId]) {
                $Account = $StorageAccounts[$AccountIndex]
                $Id = [string](Get-ScoutValue $Account @('id', 'ID'))
                if ($StorageContextError) {
                    Write-Warning "Get-ScoutOperationalCollectorEnrichment: StorageAccounts.BlobService failed for '$Id': $StorageContextError"
                    $Blob = [PSCustomObject]@{ __AZSCError = $StorageContextError }
                    $FileError = "Subscription context was not entered: $StorageContextError"
                    Write-Warning "Get-ScoutOperationalCollectorEnrichment: StorageAccounts.FileService failed for '$Id': $FileError"
                    $File = [PSCustomObject]@{ __AZSCError = $FileError }
                }
                else {
                    try {
                        $Blob = Invoke-ScoutOperationalTrackedCommand -Dataset 'StorageAccounts.BlobService' -Operation {
                            Get-AzStorageBlobServiceProperty -ResourceGroupName (Get-ScoutValue $Account @('resourceGroup', 'RESOURCEGROUP')) -Name (Get-ScoutValue $Account @('name', 'NAME')) -ErrorAction Stop
                        }
                    }
                    catch {
                        Write-Warning "Get-ScoutOperationalCollectorEnrichment: StorageAccounts.BlobService failed for '$Id': $($_.Exception.Message)"
                        $Blob = [PSCustomObject]@{ __AZSCError = $_.Exception.Message }
                    }
                    try {
                        $File = Invoke-ScoutOperationalTrackedCommand -Dataset 'StorageAccounts.FileService' -Operation {
                            Get-AzStorageFileServiceProperty -ResourceGroupName (Get-ScoutValue $Account @('resourceGroup', 'RESOURCEGROUP')) -Name (Get-ScoutValue $Account @('name', 'NAME')) -ErrorAction Stop
                        }
                    }
                    catch {
                        Write-Warning "Get-ScoutOperationalCollectorEnrichment: StorageAccounts.FileService failed for '$Id': $($_.Exception.Message)"
                        $File = [PSCustomObject]@{ __AZSCError = $_.Exception.Message }
                    }
                }
                $StorageResults[$AccountIndex] = [PSCustomObject]@{ BlobService = $Blob; FileService = $File }
            }
        }
    }
    finally {
        if ($StorageContext -and $StorageContext.Subscription -and $StorageContext.Subscription.Id) {
            $restoreParams = @{ Subscription = $StorageContext.Subscription.Id; ErrorAction = 'SilentlyContinue' }
            if ($StorageContext.Tenant -and $StorageContext.Tenant.Id) { $restoreParams['Tenant'] = $StorageContext.Tenant.Id }
            try {
                Invoke-ScoutOperationalTrackedCommand -Dataset 'StorageAccounts.RestoreSubscriptionContext' -Operation {
                    Set-AzContext @restoreParams | Out-Null
                } | Out-Null
            }
            catch {
                Write-Warning "Get-ScoutOperationalCollectorEnrichment: restoring the original subscription context failed: $($_.Exception.Message)"
            }
        }
    }
    for ($StorageIndex = 0; $StorageIndex -lt $StorageAccounts.Count; $StorageIndex++) {
        $Account = $StorageAccounts[$StorageIndex]
        $Result = $StorageResults[$StorageIndex]
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/StorageAccount' -Parent $Account -Properties @{
            BlobService = $Result.BlobService
            FileService = $Result.FileService
        }
    }

    if ($IncludeProviderResourceDetails) {
        # AB#7366: ARG is the universal discovery pass, but its `properties` bag is not guaranteed
        # to equal the resource provider's GET response. Resolve API versions once per provider
        # namespace and then GET every concrete ARM resource. Failures become resource-scoped
        # health records; the ARG parent remains in the inventory and is marked Partial.
        $armResources = @(Get-ScoutUniqueResource -InputRows @($Resources | Where-Object {
                $candidateType = [string](Get-ScoutValue $_ @('type', 'TYPE'))
                $candidateId = [string](Get-ScoutValue $_ @('id', 'ID'))
                $candidateType -match '(?i)^microsoft\.[^/]+/.+' -and $candidateId -match '(?i)/providers/'
            }))
        $providerMetadataByKey = @{}
        foreach ($resource in $armResources) {
            $id = [string](Get-ScoutValue $resource @('id', 'ID'))
            $resourceType = [string](Get-ScoutValue $resource @('type', 'TYPE'))
            $subscriptionId = [string](Get-ScoutValue $resource @('subscriptionId', 'SubscriptionId'))
            if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($subscriptionId)) { continue }
            $typeParts = @($resourceType -split '/', 2)
            if ($typeParts.Count -ne 2) { continue }
            $namespace = $typeParts[0]
            $providerType = $typeParts[1]
            $providerKey = "$subscriptionId|$namespace".ToLowerInvariant()
            if (-not $providerMetadataByKey.ContainsKey($providerKey)) {
                $providerMetadataByKey[$providerKey] = Invoke-ScoutOperationalArm `
                    -Dataset "ProviderDetails.Metadata.$namespace" `
                    -ParentId "/subscriptions/$subscriptionId/providers/$namespace" `
                    -Path "/subscriptions/$subscriptionId/providers/${namespace}?api-version=2021-04-01" `
                    -DynamicRequest
            }
            $providerMetadata = $providerMetadataByKey[$providerKey]
            $metadataError = [string](Get-ScoutValue $providerMetadata @('__AZSCError'))
            if (-not [string]::IsNullOrWhiteSpace($metadataError)) {
                Add-ScoutOperationalHealth -Dataset 'ProviderDetails.Resource' -Reason "Provider API-version discovery failed: $metadataError" `
                    -ParentId $id -ResourceType $resourceType -Collector 'Discovery/ProviderDetails'
                continue
            }
            $typeMetadata = @(Get-ScoutValue $providerMetadata @('resourceTypes', 'ResourceTypes') | Where-Object {
                    [string](Get-ScoutValue $_ @('resourceType', 'ResourceTypeName')) -ieq $providerType
                } | Select-Object -First 1)
            $apiVersions = if ($typeMetadata.Count -gt 0) { @((Get-ScoutValue $typeMetadata[0] @('apiVersions', 'ApiVersions')) | Where-Object { $_ }) } else { @() }
            $stableVersions = @($apiVersions | Where-Object { [string]$_ -notmatch '(?i)preview|beta|alpha|private' })
            $candidateVersions = $apiVersions
            if ($stableVersions.Count -gt 0) {
                $candidateVersions = $stableVersions
            }
            $apiVersion = @($candidateVersions | Sort-Object -Descending | Select-Object -First 1)
            if ($apiVersion.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$apiVersion[0])) {
                Add-ScoutOperationalHealth -Dataset 'ProviderDetails.Resource' -Reason "No API version was advertised for provider type '$providerType'." `
                    -ParentId $id -ResourceType $resourceType -Collector 'Discovery/ProviderDetails'
                continue
            }
            $detail = Invoke-ScoutOperationalArm `
                -Dataset "ProviderDetails.Resource.$namespace.$providerType" `
                -ParentId $id `
                -Path "${id}?api-version=$($apiVersion[0])" `
                -DynamicRequest
            $detailError = [string](Get-ScoutValue $detail @('__AZSCError'))
            if (-not [string]::IsNullOrWhiteSpace($detailError)) {
                Add-ScoutOperationalHealth -Dataset 'ProviderDetails.Resource' -Reason $detailError `
                    -ParentId $id -ResourceType $resourceType -Collector 'Discovery/ProviderDetails'
            }
            ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/ProviderDetail' -Parent $resource -Properties @{
                ApiVersion = [string]$apiVersion[0]
                Payload    = $detail
            }
        }
    }

    $ResourceCounts = @{}
    $ResourceGroupCounts = @{}
    foreach ($Resource in @($Resources)) {
        $SubId = [string](Get-ScoutValue $Resource @('subscriptionId'))
        if ([string]::IsNullOrWhiteSpace($SubId)) { continue }
        $ResourceCounts[$SubId] = 1 + [int]($ResourceCounts[$SubId])
        if ((Get-ScoutValue $Resource @('type', 'TYPE')) -ieq 'microsoft.resources/subscriptions/resourcegroups') {
            $ResourceGroupCounts[$SubId] = 1 + [int]($ResourceGroupCounts[$SubId])
        }
    }
    $ManagementGroups = @{}
    try {
        # AB#6779 -- `@(Search-AzGraph ...)` yields the PSResourceGraphResponse WRAPPER, not the rows.
        # Reading `.Data` is the shape that behaves the same whether the result is empty or not.
        $GraphResponse = Invoke-ScoutOperationalTrackedCommand -Dataset 'AllSubscriptions.ManagementGroupPath' -Operation {
            Search-AzGraph -Query "resourcecontainers | where type == 'microsoft.resources/subscriptions' | extend mgChain = properties.managementGroupAncestorsChain | project subscriptionId, mgChain" -First 1000 -ErrorAction Stop
        }
        # Assigned in statements: `$x = if (...) { @() }` yields $null, because an empty array
        # contributes nothing to the output stream an if-block returns through. Harmless for the
        # `foreach` just below, which tolerates $null -- but the same idiom DOES throw where the
        # result's `.Count` is read, so all four Search-AzGraph sites are written the one way.
        $GraphRows = @()
        if ($null -ne $GraphResponse -and $GraphResponse.PSObject.Properties['Data']) {
            $GraphRows = @($GraphResponse.Data)
        }
        elseif ($null -ne $GraphResponse) {
            $GraphRows = @($GraphResponse)
        }
        foreach ($GraphRow in $GraphRows) {
            $Chain = @(Get-ScoutValue $GraphRow @('mgChain'))
            [array]::Reverse($Chain)
            $ManagementGroups[[string](Get-ScoutValue $GraphRow @('subscriptionId'))] = if ($Chain.Count -gt 0) { ($Chain | ForEach-Object { Get-ScoutValue $_ @('displayName') }) -join ' / ' } else { 'Tenant Root' }
        }
    }
    catch {
        Write-Warning "Get-ScoutOperationalCollectorEnrichment: AllSubscriptions.ManagementGroupPath failed: $($_.Exception.Message)"
    }
    foreach ($Subscription in @($Subscriptions)) {
        $SubId = [string](Get-ScoutValue $Subscription @('id', 'Id'))
        if ([string]::IsNullOrWhiteSpace($SubId)) { continue }
        [PSCustomObject][ordered]@{
            type = 'AZSC/Management/SubscriptionEnrichment'; id = $SubId; subscriptionId = $SubId
            name = Get-ScoutValue $Subscription @('name', 'Name')
            properties = [PSCustomObject]@{
                ResourceCount = [int]$ResourceCounts[$SubId]
                ResourceGroupCount = [int]$ResourceGroupCounts[$SubId]
                ManagementGroupPath = if ($ManagementGroups.ContainsKey($SubId)) { $ManagementGroups[$SubId] } else { 'Unknown' }
                Subscription = $Subscription
            }
        }
    }

    $ProgressState.Started.Stop()
    $progressStatus = 'Operational enrichment complete: {0} requests; {1} unavailable' -f
        $ProgressState.Completed, $ProgressState.Failed
    if (Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue) {
        Write-ScoutProgress -Id 3 -ParentId 2 -Activity 'Operational enrichment' `
            -Status $progressStatus -Completed
    }
    else {
        Write-Progress -Id 3 -ParentId 2 -Activity 'Operational enrichment' `
            -Status $progressStatus -Completed
    }
    $completionStatus = if ($ProgressState.Failed -gt 0) { 'Partial' } else { 'Completed' }
    Write-ScoutOperationalDetail -Level VERBOSE -Message (
        'Operational enrichment complete: status={0}; completed={1}; planned={2}; unavailable={3}; elapsed={4}' -f
            $completionStatus,
            $ProgressState.Completed, $ProgressState.Planned, $ProgressState.Failed,
            $ProgressState.Started.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
    )
}
