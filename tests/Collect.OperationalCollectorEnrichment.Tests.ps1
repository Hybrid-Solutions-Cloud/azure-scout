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
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
        param()

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
    function Clear-OperationalStubs {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
        param()
 foreach($Name in 'Invoke-AzRestMethod','Get-AzContext','Set-AzContext','Get-AzStorageBlobServiceProperty','Get-AzStorageFileServiceProperty','Search-AzGraph'){ Remove-Item "Function:\$Name" -Force -ErrorAction SilentlyContinue } }
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
        ($Rows | Where-Object type -eq 'AZSC/Operational/StorageAccount').properties.BlobService.Name | Should -Be 'store-1'
        ($Rows | Where-Object type -eq 'AZSC/Operational/StorageAccount').properties.FileService.Name | Should -Be 'store-1'
        ($script:ContextCalls | Where-Object Subscription -eq 'sub-1').Tenant | Should -Be 'tenant-a'
        ($script:ContextCalls | Where-Object Subscription -eq 'original-sub').Tenant | Should -Be 'tenant-a'
    }
    It 'contains a failed parent request while producing other envelopes' {
        function global:Invoke-AzRestMethod { param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction; if($Path -match 'vm-1/providers/microsoft.insights/metrics'){throw 'metrics denied'}; [pscustomobject]@{StatusCode=200;Content='{}'} }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @() -WarningVariable Warnings)
        ($Rows | Where-Object type -eq 'AZSC/Operational/VirtualMachine').properties.CpuMetrics.__AZSCError | Should -Be 'metrics denied'
        ($Rows | Where-Object type -eq 'AZSC/Operational/ARCServers') | Should -Not -BeNullOrEmpty
        ($Warnings -join "`n") | Should -Match 'VirtualMachine.CpuMetrics'
    }

    # AB#6731 -- Scout must never command a machine to run a patch scan. `assessPatches` is an ARM
    # *action*, not a read: the previous implementation POSTed it once per VM and once per Arc
    # machine on every run, triggering guest-OS scans that can take hours, that Reader does not
    # grant, and that made a tool documented as read-only mutate customer machines. Patch data now
    # comes from the Azure Update Manager Resource Graph tables, which Update Manager populates on
    # its own schedule. This test is the regression lock.
    It 'never calls assessPatches -- patch data is READ from Update Manager, never triggered' {
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}))
        ($script:Calls -join "`n") | Should -Not -Match 'assessPatches'
        $null = $Rows
    }

    It 'reads pending-patch counts from the Update Manager assessment row, folding Windows and Linux classifications' {
        $PatchRow = [pscustomobject]@{
            id   = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm-1/patchAssessmentResults/latest'
            type = 'microsoft.compute/virtualmachines/patchassessmentresults'
            name = 'latest'
            properties = [pscustomobject]@{
                availablePatchCountByClassification = [pscustomobject]@{ Critical = 3; Security = 2; Updates = 7 }
                startDateTime    = '2026-07-30T01:00:00Z'
                rebootPending    = $true
                patchServiceUsed = 'WU-WSUS'
                osType           = 'Windows'
            }
        }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources ($script:Resources + $PatchRow) -Subscriptions @())
        $Patch = ($Rows | Where-Object type -eq 'AZSC/Operational/VMOperationalData').properties.PatchAssessment
        $Patch.criticalAndSecurityPatchCount | Should -Be 5   # Critical 3 + Security 2
        $Patch.otherPatchCount               | Should -Be 7   # Updates
        $Patch.rebootPending                 | Should -BeTrue
        $Patch.patchServiceUsed              | Should -Be 'WU-WSUS'
    }

    It 'reports NotAssessed rather than zero when Update Manager has no row for the machine' {
        # "Update Manager has not assessed this machine in 7 days" and "this machine has no pending
        # patches" are different findings and must not render identically.
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @())
        $Patch = ($Rows | Where-Object type -eq 'AZSC/Operational/VMOperationalData').properties.PatchAssessment
        $Patch.__AZSCStatus | Should -Be 'NotAssessed'
        $Patch.PSObject.Properties['criticalAndSecurityPatchCount'] | Should -BeNullOrEmpty
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
    It 'treats a persistent 409 as a distinct in-progress status, not a generic error' {
        # The 409 branch of Invoke-ScoutOperationalArm still matters for the remaining query-style
        # POSTs (Cost Management, Policy Insights) even though assessPatches no longer runs.
        function global:Invoke-AzRestMethod {
            param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction
            if ($Path -match 'Microsoft.CostManagement/query') { return [pscustomobject]@{StatusCode=409;Content='{}'} }
            [pscustomobject]@{StatusCode=200;Content='{"value":[]}' }
        }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @([pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}) -WarningAction SilentlyContinue)
        ($Rows | Where-Object type -eq 'AZSC/Operational/VirtualMachine').properties.EstimatedCost.__AZSCStatus | Should -Be 'OperationInProgress'
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
