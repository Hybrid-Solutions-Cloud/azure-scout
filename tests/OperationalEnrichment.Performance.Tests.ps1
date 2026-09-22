#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . "$script:Root/src/collect/Get-ScoutOperationalCollectorEnrichment.ps1"

    function New-OperationalPerformanceResource {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test-fixture factory only returns an in-memory object and changes no state.')]
        param(
            [Parameter(Mandatory)][string]$Type,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$SubscriptionId
        )
        [pscustomobject]@{
            id = "/subscriptions/$SubscriptionId/resourceGroups/rg-$SubscriptionId/providers/$Type/$Name"
            type = $Type
            name = $Name
            subscriptionId = $SubscriptionId
            resourceGroup = "rg-$SubscriptionId"
        }
    }

    function Initialize-OperationalPerformanceStubs {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Test helper installs the complete set of command stubs as one fixture operation.')]
        param()
        $script:RestCalls = [System.Collections.Generic.List[object]]::new()
        $script:ContextCalls = [System.Collections.Generic.List[object]]::new()
        $script:BlobCalls = [System.Collections.Generic.List[string]]::new()
        $script:FileCalls = [System.Collections.Generic.List[string]]::new()
        $script:FailContextSubscription = $null
        $script:FailVaultSubscription = $null

        function global:Invoke-AzRestMethod {
            param($Path, $Method, $Payload, $ErrorAction)
            $script:RestCalls.Add([pscustomobject]@{ Path=$Path; Method=$Method; Payload=$Payload; ErrorAction=$ErrorAction })
            $subscriptionId = if ($Path -match '/subscriptions/([^/]+)') { $Matches[1] } else { 'unknown' }
            if ($Path -match '/Microsoft\.RecoveryServices/vaults\?') {
                if ($script:FailVaultSubscription -eq $subscriptionId) { throw 'vault enumeration denied' }
                $vault = [pscustomobject]@{
                    id = "/subscriptions/$subscriptionId/resourceGroups/rg-vault-$subscriptionId/providers/Microsoft.RecoveryServices/vaults/vault-$subscriptionId"
                    name = "vault-$subscriptionId"
                }
                return [pscustomobject]@{ StatusCode=200; Content=(@{ value=@($vault) } | ConvertTo-Json -Depth 8 -Compress) }
            }
            if ($Path -match '/replicationProtectedItems\?') {
                return [pscustomobject]@{ StatusCode=200; Content=(@{ value=@([pscustomobject]@{ name="protected-$subscriptionId" }) } | ConvertTo-Json -Depth 8 -Compress) }
            }
            if ($Path -match 'metricnames=Percentage\+CPU') {
                return [pscustomobject]@{ StatusCode=200; Content=(@{ kind='cpu'; subscriptionId=$subscriptionId } | ConvertTo-Json -Compress) }
            }
            if ($Path -match 'metricnames=Available\+Memory\+Bytes') {
                return [pscustomobject]@{ StatusCode=200; Content=(@{ kind='memory'; subscriptionId=$subscriptionId } | ConvertTo-Json -Compress) }
            }
            if ($Path -match 'Microsoft\.CostManagement/query') {
                $resourceId = (([string]$Payload | ConvertFrom-Json).dataset.filter.dimensions.values | Select-Object -First 1)
                return [pscustomobject]@{ StatusCode=200; Content=(@{ kind='cost'; resourceId=$resourceId } | ConvertTo-Json -Compress) }
            }
            if ($Path -match 'replicationEligibilityResults') {
                return [pscustomobject]@{ StatusCode=200; Content=(@{ kind='eligibility'; subscriptionId=$subscriptionId } | ConvertTo-Json -Compress) }
            }
            return [pscustomobject]@{ StatusCode=200; Content='{}' }
        }
        function global:Get-AzContext {
            param($ErrorAction)
            $null = $ErrorAction
            [pscustomobject]@{
                Subscription = [pscustomobject]@{ Id='original-sub' }
                Tenant = [pscustomobject]@{ Id='tenant-a' }
            }
        }
        function global:Set-AzContext {
            param($Subscription, $Tenant, $ErrorAction)
            $script:ContextCalls.Add([pscustomobject]@{ Subscription=$Subscription; Tenant=$Tenant; ErrorAction=$ErrorAction })
            if ($script:FailContextSubscription -eq $Subscription) { throw "context unavailable for $Subscription" }
        }
        function global:Get-AzStorageBlobServiceProperty {
            param($ResourceGroupName, $Name, $ErrorAction)
            $null = $ResourceGroupName, $ErrorAction
            $script:BlobCalls.Add($Name)
            [pscustomobject]@{ Name=$Name; Kind='blob' }
        }
        function global:Get-AzStorageFileServiceProperty {
            param($ResourceGroupName, $Name, $ErrorAction)
            $null = $ResourceGroupName, $ErrorAction
            $script:FileCalls.Add($Name)
            [pscustomobject]@{ Name=$Name; Kind='file' }
        }
        function global:Search-AzGraph {
            param($Query, $First, $ErrorAction)
            $null = $Query, $First, $ErrorAction
            [pscustomobject]@{ Data=@() }
        }
    }

    function Clear-OperationalPerformanceStubs {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Test helper removes the complete set of command stubs as one fixture operation.')]
        param()
        foreach ($Name in 'Invoke-AzRestMethod', 'Get-AzContext', 'Set-AzContext',
            'Get-AzStorageBlobServiceProperty', 'Get-AzStorageFileServiceProperty', 'Search-AzGraph') {
            Remove-Item "Function:\$Name" -Force -ErrorAction SilentlyContinue
        }
    }

    $script:Subscriptions = @(
        [pscustomobject]@{ Id='sub-1'; Name='Subscription 1'; TenantId='tenant-a' }
        [pscustomobject]@{ Id='sub-2'; Name='Subscription 2'; TenantId='tenant-a' }
    )
    $script:Resources = @(
        New-OperationalPerformanceResource -Type 'Microsoft.Compute/virtualMachines' -Name 'vm-1a' -SubscriptionId 'sub-1'
        New-OperationalPerformanceResource -Type 'Microsoft.Compute/virtualMachines' -Name 'vm-1b' -SubscriptionId 'sub-1'
        New-OperationalPerformanceResource -Type 'Microsoft.Compute/virtualMachines' -Name 'vm-2a' -SubscriptionId 'sub-2'
        New-OperationalPerformanceResource -Type 'Microsoft.Storage/storageAccounts' -Name 'store-1a' -SubscriptionId 'sub-1'
        New-OperationalPerformanceResource -Type 'Microsoft.Storage/storageAccounts' -Name 'store-2a' -SubscriptionId 'sub-2'
        # Deliberately interleaved by subscription. The optimized implementation groups remote
        # context work but must still emit storage envelopes in this original order.
        New-OperationalPerformanceResource -Type 'Microsoft.Storage/storageAccounts' -Name 'store-1b' -SubscriptionId 'sub-1'
    )
}

Describe 'Get-ScoutOperationalCollectorEnrichment remote-call caching' {
    BeforeEach { Initialize-OperationalPerformanceStubs }
    AfterEach { Clear-OperationalPerformanceStubs }

    It 'enumerates vaults once per subscription and protected items once per vault without changing VM payloads' {
        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions $script:Subscriptions)

        @($script:RestCalls | Where-Object Path -Match '/Microsoft\.RecoveryServices/vaults\?').Count | Should -Be 2
        @($script:RestCalls | Where-Object Path -Match '/replicationProtectedItems\?').Count | Should -Be 2
        @($script:RestCalls | Where-Object Path -Match 'replicationEligibilityResults').Count | Should -Be 3
        @($script:RestCalls | Where-Object Path -Match 'microsoft\.insights/metrics').Count | Should -Be 6
        @($script:RestCalls | Where-Object Path -Match 'Microsoft\.CostManagement/query').Count | Should -Be 3

        $vmRows = @($rows | Where-Object type -eq 'AZSC/Operational/VirtualMachine')
        $vmRows.Count | Should -Be 3
        foreach ($vm in $vmRows) {
            $expectedSubscription = $vm.subscriptionId
            $vm.properties.CpuMetrics.kind | Should -Be 'cpu'
            $vm.properties.MemoryMetrics.kind | Should -Be 'memory'
            $vm.properties.ReplicationEligibility.kind | Should -Be 'eligibility'
            @($vm.properties.ReplicationProtectedItems).Count | Should -Be 1
            $vm.properties.ReplicationProtectedItems[0].value[0].name | Should -Be "protected-$expectedSubscription"
            $vm.properties.EstimatedCost.kind | Should -Be 'cost'
            $vm.properties.EstimatedCost.resourceId | Should -Be $vm.id
        }
    }

    It 'enters each storage subscription once while preserving envelope order and raw service payloads' {
        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions $script:Subscriptions)

        @($script:ContextCalls | Where-Object Subscription -eq 'sub-1').Count | Should -Be 1
        @($script:ContextCalls | Where-Object Subscription -eq 'sub-2').Count | Should -Be 1
        @($script:ContextCalls | Where-Object Subscription -eq 'original-sub').Count | Should -Be 1
        $script:BlobCalls.Count | Should -Be 3
        $script:FileCalls.Count | Should -Be 3

        $storageRows = @($rows | Where-Object type -eq 'AZSC/Operational/StorageAccount')
        @($storageRows.name) | Should -Be @('store-1a', 'store-2a', 'store-1b')
        foreach ($storage in $storageRows) {
            $storage.properties.BlobService.Name | Should -Be $storage.name
            $storage.properties.BlobService.Kind | Should -Be 'blob'
            $storage.properties.FileService.Name | Should -Be $storage.name
            $storage.properties.FileService.Kind | Should -Be 'file'
        }
    }

    It 'caches subscription-scoped failures while retaining an error envelope for every owning parent' {
        $script:FailVaultSubscription = 'sub-1'
        $script:FailContextSubscription = 'sub-1'
        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions $script:Subscriptions -WarningAction SilentlyContinue)

        @($script:RestCalls | Where-Object Path -Match '/subscriptions/sub-1/providers/Microsoft\.RecoveryServices/vaults\?').Count | Should -Be 1
        @($script:ContextCalls | Where-Object Subscription -eq 'sub-1').Count | Should -Be 1
        $failedVms = @($rows | Where-Object { $_.type -eq 'AZSC/Operational/VirtualMachine' -and $_.subscriptionId -eq 'sub-1' })
        $failedVms.Count | Should -Be 2
        foreach ($vm in $failedVms) { @($vm.properties.ReplicationProtectedItems).Count | Should -Be 0 }

        $failedStorage = @($rows | Where-Object { $_.type -eq 'AZSC/Operational/StorageAccount' -and $_.subscriptionId -eq 'sub-1' })
        $failedStorage.Count | Should -Be 2
        foreach ($storage in $failedStorage) {
            $storage.properties.BlobService.__AZSCError | Should -Be 'context unavailable for sub-1'
            $storage.properties.FileService.__AZSCError | Should -Be 'Subscription context was not entered: context unavailable for sub-1'
        }
        # Failure in one subscription remains contained; the other subscription still has data.
        $successfulStorage = $rows | Where-Object { $_.type -eq 'AZSC/Operational/StorageAccount' -and $_.subscriptionId -eq 'sub-2' }
        $successfulStorage.properties.BlobService.Kind | Should -Be 'blob'
        $successfulStorage.properties.FileService.Kind | Should -Be 'file'
    }
}
