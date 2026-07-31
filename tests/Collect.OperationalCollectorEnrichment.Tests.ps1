#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . "$script:Root/src/collect/Get-ScoutOperationalCollectorEnrichment.ps1"
    $script:Calls = [System.Collections.Generic.List[string]]::new()
    $script:Resources = @(
        [pscustomobject]@{ id='/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm-1'; type='microsoft.compute/virtualmachines'; name='vm-1'; subscriptionId='sub-1'; resourceGroup='rg' },
        [pscustomobject]@{ id='/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.HybridCompute/machines/arc-1'; type='microsoft.hybridcompute/machines'; name='arc-1'; subscriptionId='sub-1'; resourceGroup='rg' },
        [pscustomobject]@{ id='/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/store-1'; type='microsoft.storage/storageaccounts'; name='store-1'; subscriptionId='sub-1'; resourceGroup='rg' },
        [pscustomobject]@{ id='/subscriptions/sub-1/resourceGroups/rg-rg'; type='microsoft.resources/subscriptions/resourcegroups'; name='rg-rg'; subscriptionId='sub-1'; resourceGroup='rg-rg' }
    )
    function Initialize-OperationalStubs {
        $script:Calls.Clear()
        $script:ContextCalls = [System.Collections.Generic.List[object]]::new()
        $script:FailStorageContext = $false
        $script:BlobCalls = 0
        $script:FileCalls = 0
        function global:Invoke-AzRestMethod { param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction; $script:Calls.Add($Path); [pscustomobject]@{StatusCode=200;Content='{"value":[]}' } }
        function global:Get-AzContext { param($ErrorAction) $null = $ErrorAction; [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'original-sub' }; Tenant = [pscustomobject]@{ Id = 'tenant-a' } } }
        function global:Set-AzContext { param($Subscription,$Tenant,$ErrorAction) $script:ContextCalls.Add([pscustomobject]@{ Subscription=$Subscription; Tenant=$Tenant; ErrorAction=$ErrorAction }); if($script:FailStorageContext -and $Subscription -eq 'sub-1'){throw 'context unavailable'} }
        function global:Get-AzStorageBlobServiceProperty { param($ResourceGroupName,$Name,$ErrorAction) $null=$ResourceGroupName,$ErrorAction; $script:BlobCalls++; [pscustomobject]@{ Name=$Name; DeleteRetentionPolicy=[pscustomobject]@{Enabled=$true} } }
        function global:Get-AzStorageFileServiceProperty { param($ResourceGroupName,$Name,$ErrorAction) $null=$ResourceGroupName,$ErrorAction; $script:FileCalls++; [pscustomobject]@{ Name=$Name; ShareDeleteRetentionPolicy=[pscustomobject]@{Enabled=$true} } }
        function global:Search-AzGraph { param($Query,$First,$ErrorAction) $null=$Query,$First,$ErrorAction; [pscustomobject]@{subscriptionId='sub-1';mgChain=@([pscustomobject]@{displayName='Platform'},[pscustomobject]@{displayName='Root'})} }
    }
    function Clear-OperationalStubs { foreach($Name in 'Invoke-AzRestMethod','Get-AzContext','Set-AzContext','Get-AzStorageBlobServiceProperty','Get-AzStorageFileServiceProperty','Search-AzGraph'){ Remove-Item "Function:\$Name" -Force -ErrorAction SilentlyContinue } }
}
Describe 'Get-ScoutOperationalCollectorEnrichment' {
    BeforeEach { Initialize-OperationalStubs }
    AfterEach { Clear-OperationalStubs }
    It 'returns stable envelopes for all six live-access collector contracts' {
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}))
        $Rows.type | Should -Be @('AZSC/Operational/VirtualMachine','AZSC/Operational/VMOperationalData','AZSC/Operational/ArcServerOperationalData','AZSC/Operational/ARCServers','AZSC/Operational/StorageAccount','AZSC/Management/SubscriptionEnrichment')
        ($Rows | Where-Object type -eq 'AZSC/Management/SubscriptionEnrichment').properties.ManagementGroupPath | Should -Be 'Root / Platform'
        ($Rows | Where-Object type -eq 'AZSC/Management/SubscriptionEnrichment').properties.ResourceCount | Should -Be 4
    }
    It 'uses parent-scoped REST/cmdlet calls and preserves their raw payloads' {
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}))
        ($script:Calls -join "`n") | Should -Match '/virtualMachines/vm-1/providers/microsoft.insights/metrics'
        ($script:Calls -join "`n") | Should -Match '/virtualMachines/vm-1/assessPatches'
        ($script:Calls -join "`n") | Should -Match '/machines/arc-1/assessPatches'
        ($Rows | Where-Object type -eq 'AZSC/Operational/StorageAccount').properties.BlobService.Name | Should -Be 'store-1'
        ($Rows | Where-Object type -eq 'AZSC/Operational/StorageAccount').properties.FileService.Name | Should -Be 'store-1'
        ($script:ContextCalls | Where-Object Subscription -eq 'sub-1').Tenant | Should -Be 'tenant-a'
        ($script:ContextCalls | Where-Object Subscription -eq 'original-sub').Tenant | Should -Be 'tenant-a'
    }
    It 'contains a failed parent request while producing other envelopes' {
        function global:Invoke-AzRestMethod { param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction; if($Path -match 'vm-1/assessPatches'){throw 'patch denied'}; [pscustomobject]@{StatusCode=200;Content='{}'} }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @() -WarningVariable Warnings)
        ($Rows | Where-Object type -eq 'AZSC/Operational/VMOperationalData').properties.PatchAssessment.__AZSCError | Should -Be 'patch denied'
        ($Rows | Where-Object type -eq 'AZSC/Operational/ARCServers') | Should -Not -BeNullOrEmpty
        ($Warnings -join "`n") | Should -Match 'VMOperationalData.PatchAssessment'
    }
    It 'does not issue storage service calls in the wrong context when the subscription switch fails' {
        $script:FailStorageContext = $true
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}) -WarningAction SilentlyContinue)
        $Storage = $Rows | Where-Object type -eq 'AZSC/Operational/StorageAccount'
        $script:BlobCalls | Should -Be 0
        $script:FileCalls | Should -Be 0
        $Storage.properties.BlobService.__AZSCError | Should -Match 'context unavailable'
        $Storage.properties.FileService.__AZSCError | Should -Match 'context unavailable'
    }
    It 'returns no envelopes and does not call Azure for empty inputs' {
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources @() -Subscriptions @())
        $Rows | Should -BeNullOrEmpty
        $script:Calls.Count | Should -Be 0
    }
    It 'never calls the ARM metrics API for Arc-enabled servers CPU (unsupported for this resource type)' {
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}))
        ($script:Calls -join "`n") | Should -Not -Match 'arc-1/providers/microsoft.insights/metrics'
        ($Rows | Where-Object type -eq 'AZSC/Operational/ARCServers').properties.CpuMetrics.__AZSCStatus | Should -Be 'NotSupportedForArc'
    }
    It 'retries a 429 with backoff and eventually succeeds instead of failing immediately' {
        $script:AttemptCount = 0
        function global:Invoke-AzRestMethod {
            param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction
            if ($Path -match 'Microsoft.CostManagement/query') {
                $script:AttemptCount++
                if ($script:AttemptCount -lt 2) { return [pscustomobject]@{StatusCode=429;Content='{}'} }
            }
            [pscustomobject]@{StatusCode=200;Content='{"value":[]}' }
        }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}))
        $script:AttemptCount | Should -BeGreaterOrEqual 2
        $EstimatedCost = ($Rows | Where-Object type -eq 'AZSC/Operational/VirtualMachine').properties.EstimatedCost
        $EstimatedCost.PSObject.Properties['__AZSCError'] | Should -BeNullOrEmpty
    }
    It 'treats a persistent 409 on PatchAssessment as a distinct in-progress status, not a generic error' {
        function global:Invoke-AzRestMethod {
            param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction
            if ($Path -match 'assessPatches') { return [pscustomobject]@{StatusCode=409;Content='{}'} }
            [pscustomobject]@{StatusCode=200;Content='{"value":[]}' }
        }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}) -WarningAction SilentlyContinue)
        ($Rows | Where-Object type -eq 'AZSC/Operational/VMOperationalData').properties.PatchAssessment.__AZSCStatus | Should -Be 'OperationInProgress'
        ($Rows | Where-Object type -eq 'AZSC/Operational/ArcServerOperationalData').properties.PatchAssessment.__AZSCStatus | Should -Be 'OperationInProgress'
    }
    It 'does not warn when ReplicationEligibility 404s -- an expected "ASR never evaluated this VM" state' {
        function global:Invoke-AzRestMethod {
            param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction
            if ($Path -match 'replicationEligibilityResults') { return [pscustomobject]@{StatusCode=404;Content='{}'} }
            [pscustomobject]@{StatusCode=200;Content='{"value":[]}' }
        }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}) -WarningVariable Warnings)
        ($Rows | Where-Object type -eq 'AZSC/Operational/VirtualMachine').properties.ReplicationEligibility.__AZSCStatus | Should -Be 'NotConfigured'
        ($Warnings -join "`n") | Should -Not -Match 'ReplicationEligibility'
    }
}
