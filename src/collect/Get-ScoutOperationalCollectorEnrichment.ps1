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
    AZSC/Operational/StorageAccount, and AZSC/Management/SubscriptionEnrichment.
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
        [object[]]$Subscriptions = @()
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

    function Invoke-ScoutOperationalArm {
        param(
            [Parameter(Mandatory)][string]$Dataset,
            [Parameter(Mandatory)][string]$ParentId,
            [Parameter(Mandatory)][string]$Path,
            [ValidateSet('GET', 'POST')][string]$Method = 'GET',
            [AllowNull()]$Payload
        )

        try {
            $Arguments = @{ Path = $Path; Method = $Method; ErrorAction = 'Stop' }
            if ($null -ne $Payload) { $Arguments['Payload'] = $Payload }
            $Response = Invoke-AzRestMethod @Arguments
            if ($null -eq $Response) { throw 'ARM returned no response.' }
            $Status = Get-ScoutValue -InputObject $Response -Name @('StatusCode')
            if ($null -ne $Status -and ([int]$Status -lt 200 -or [int]$Status -ge 300)) {
                throw "ARM returned status $Status."
            }
            $Content = Get-ScoutValue -InputObject $Response -Name @('Content')
            if ($Content -is [string]) {
                if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
                return ($Content | ConvertFrom-Json)
            }
            return $Content
        }
        catch {
            Write-Warning "Get-ScoutOperationalCollectorEnrichment: $Dataset failed for '$ParentId': $($_.Exception.Message)"
            return [PSCustomObject]@{ __AZSCError = $_.Exception.Message }
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

    $VirtualMachines = @($Resources | Where-Object { (Get-ScoutValue $_ @('type', 'TYPE')) -ieq 'microsoft.compute/virtualmachines' })
    foreach ($Vm in $VirtualMachines) {
        $Id = [string](Get-ScoutValue $Vm @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $Now = (Get-Date).ToUniversalTime().ToString('o')
        $Start = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
        $BaseMetric = "$Id/providers/microsoft.insights/metrics?api-version=2019-07-01&timespan=$Start/$Now&interval=P1D&aggregation=Average"
        # Keep the operational payloads at the collect boundary.  The two Compute report
        # collectors consume these envelopes later; they must never issue a per-row ARM call.
        # The Cost Management body deliberately retains the legacy ResourceId filter -- an
        # unfiltered `{}` query is not equivalent and can report a subscription total.
        $SubscriptionId = [string](Get-ScoutValue $Vm @('subscriptionId'))
        $VmName = [string](Get-ScoutValue $Vm @('name', 'NAME'))
        $Eligibility = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.ReplicationEligibility' -ParentId $Id -Path "/subscriptions/$SubscriptionId/providers/Microsoft.RecoveryServices/replicationEligibilityResults/${VmName}?api-version=2022-10-01"
        $Vaults = Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.ReplicationVaults' -ParentId $Id -Path "/subscriptions/$SubscriptionId/providers/Microsoft.RecoveryServices/vaults?api-version=2023-04-01"
        $ProtectedItems = @()
        if ($null -eq (Get-ScoutValue $Vaults @('__AZSCError'))) {
            foreach ($Vault in @(Get-ScoutValue $Vaults @('value'))) {
                $VaultId = [string](Get-ScoutValue $Vault @('id'))
                $VaultName = [string](Get-ScoutValue $Vault @('name'))
                $VaultSegments = @($VaultId -split '/')
                $VaultResourceGroup = if ($VaultSegments.Count -gt 4) { $VaultSegments[4] } else { $null }
                if ([string]::IsNullOrWhiteSpace($VaultResourceGroup) -or [string]::IsNullOrWhiteSpace($VaultName)) { continue }
                $ProtectedItems += Invoke-ScoutOperationalArm -Dataset 'VirtualMachine.ReplicationProtectedItems' -ParentId $Id -Path "/subscriptions/$SubscriptionId/resourceGroups/$VaultResourceGroup/providers/Microsoft.RecoveryServices/vaults/$VaultName/replicationProtectedItems?api-version=2022-10-01"
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

    foreach ($Vm in $VirtualMachines) {
        $Id = [string](Get-ScoutValue $Vm @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $Patch = Invoke-ScoutOperationalArm -Dataset 'VMOperationalData.PatchAssessment' -ParentId $Id -Method POST -Path "$Id/assessPatches?api-version=2023-03-01"
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/VMOperationalData' -Parent $Vm -Properties @{ PatchAssessment = $Patch }
    }

    $ArcMachines = @($Resources | Where-Object { (Get-ScoutValue $_ @('type', 'TYPE')) -ieq 'microsoft.hybridcompute/machines' })
    foreach ($Arc in $ArcMachines) {
        $Id = [string](Get-ScoutValue $Arc @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $Patch = Invoke-ScoutOperationalArm -Dataset 'ArcServerOperationalData.PatchAssessment' -ParentId $Id -Method POST -Path "$Id/assessPatches?api-version=2023-06-20-preview"
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/ArcServerOperationalData' -Parent $Arc -Properties @{ PatchAssessment = $Patch }

        $Now = (Get-Date).ToUniversalTime().ToString('o')
        $Start = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
        $SubId = [string](Get-ScoutValue $Arc @('subscriptionId'))
        $Policy = Invoke-ScoutOperationalArm -Dataset 'ARCServers.PolicyCompliance' -ParentId $Id -Method POST -Path "/subscriptions/$SubId/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=2019-10-01&`$filter=resourceId eq '$Id'&`$top=100" -Payload '{}'
        $Cpu = Invoke-ScoutOperationalArm -Dataset 'ARCServers.CpuMetrics' -ParentId $Id -Path "$Id/providers/microsoft.insights/metrics?api-version=2019-07-01&metricnames=cpu_usage_active&timespan=$Start/$Now&interval=P1D&aggregation=Average"
        $ArcCostPayload = @{ type = 'Usage'; timeframe = 'MonthToDate'; dataset = @{ granularity = 'None'; filter = @{ dimensions = @{ name = 'ResourceId'; operator = 'In'; values = @($Id) } }; aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } } } } | ConvertTo-Json -Depth 10
        $Cost = Invoke-ScoutOperationalArm -Dataset 'ARCServers.EstimatedCost' -ParentId $Id -Method POST -Path "/subscriptions/$SubId/providers/Microsoft.CostManagement/query?api-version=2023-03-01" -Payload $ArcCostPayload
        ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/ARCServers' -Parent $Arc -Properties @{ PolicyCompliance = $Policy; CpuMetrics = $Cpu; EstimatedCost = $Cost }
    }

    $StorageAccounts = @($Resources | Where-Object { (Get-ScoutValue $_ @('type', 'TYPE')) -ieq 'microsoft.storage/storageaccounts' })
    $StorageContext = Get-AzContext -ErrorAction SilentlyContinue
    try {
        foreach ($Account in $StorageAccounts) {
            $Id = [string](Get-ScoutValue $Account @('id', 'ID'))
            $SubscriptionId = [string](Get-ScoutValue $Account @('subscriptionId', 'SubscriptionId'))
            $Subscription = @($Subscriptions | Where-Object { [string](Get-ScoutValue $_ @('id', 'Id')) -eq $SubscriptionId } | Select-Object -First 1)
            $StorageContextEntered = $false
            $StorageContextError = $null
            try {
                if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { throw 'Storage account has no subscriptionId.' }
                $contextParams = @{ Subscription = $SubscriptionId; ErrorAction = 'Stop' }
                $tenantId = if ($Subscription.Count -gt 0) { Get-ScoutValue $Subscription[0] @('tenantId', 'TenantId') } else { $null }
                if (-not $tenantId -and $StorageContext -and $StorageContext.Tenant) { $tenantId = $StorageContext.Tenant.Id }
                if ($tenantId) { $contextParams['Tenant'] = $tenantId }
                Set-AzContext @contextParams | Out-Null
                $StorageContextEntered = $true
                $Blob = Get-AzStorageBlobServiceProperty -ResourceGroupName (Get-ScoutValue $Account @('resourceGroup', 'RESOURCEGROUP')) -Name (Get-ScoutValue $Account @('name', 'NAME')) -ErrorAction Stop
            }
            catch {
                $StorageContextError = $_.Exception.Message
                Write-Warning "Get-ScoutOperationalCollectorEnrichment: StorageAccounts.BlobService failed for '$Id': $($_.Exception.Message)"
                $Blob = [PSCustomObject]@{ __AZSCError = $_.Exception.Message }
            }
            try {
                if (-not $StorageContextEntered) { throw "Subscription context was not entered: $StorageContextError" }
                $File = Get-AzStorageFileServiceProperty -ResourceGroupName (Get-ScoutValue $Account @('resourceGroup', 'RESOURCEGROUP')) -Name (Get-ScoutValue $Account @('name', 'NAME')) -ErrorAction Stop
            }
            catch {
                Write-Warning "Get-ScoutOperationalCollectorEnrichment: StorageAccounts.FileService failed for '$Id': $($_.Exception.Message)"
                $File = [PSCustomObject]@{ __AZSCError = $_.Exception.Message }
            }
            ConvertTo-ScoutOperationalEnvelope -Type 'AZSC/Operational/StorageAccount' -Parent $Account -Properties @{ BlobService = $Blob; FileService = $File }
        }
    }
    finally {
        if ($StorageContext -and $StorageContext.Subscription -and $StorageContext.Subscription.Id) {
            $restoreParams = @{ Subscription = $StorageContext.Subscription.Id; ErrorAction = 'SilentlyContinue' }
            if ($StorageContext.Tenant -and $StorageContext.Tenant.Id) { $restoreParams['Tenant'] = $StorageContext.Tenant.Id }
            Set-AzContext @restoreParams | Out-Null
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
        $GraphRows = @(Search-AzGraph -Query "resourcecontainers | where type == 'microsoft.resources/subscriptions' | extend mgChain = properties.managementGroupAncestorsChain | project subscriptionId, mgChain" -First 1000 -ErrorAction Stop)
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
}
