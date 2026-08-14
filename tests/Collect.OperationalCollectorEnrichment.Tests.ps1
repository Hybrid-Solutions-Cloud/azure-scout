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
    It 'collects effective NSGs and routes for every NIC and retains both payloads' {
        $nic = [pscustomobject]@{
            id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/nic-1'
            type = 'microsoft.network/networkinterfaces'; name = 'nic-1'; subscriptionId = 'sub-1'; resourceGroup = 'rg'
        }
        function global:Invoke-AzRestMethod {
            param($Path,$Uri,$Method,$Payload,$ErrorAction)
            $null=$Uri,$Payload,$ErrorAction
            $script:Calls.Add("$Method $Path")
            if ($Path -match 'effectiveNetworkSecurityGroups') {
                return [pscustomobject]@{ StatusCode=200; Content='{"value":[{"networkSecurityGroup":{"id":"/nsg/one"},"effectiveSecurityRules":[{"name":"AllowVnetInBound"}]}]}' }
            }
            if ($Path -match 'effectiveRouteTable') {
                return [pscustomobject]@{ StatusCode=200; Content='{"value":[{"source":"Default","addressPrefix":["0.0.0.0/0"],"nextHopType":"Internet"}]}' }
            }
            [pscustomobject]@{ StatusCode=200; Content='{"value":[]}' }
        }

        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources @($nic) -Subscriptions @())
        $envelope = $rows | Where-Object type -eq 'AZSC/Operational/NetworkInterface'

        $envelope | Should -Not -BeNullOrEmpty
        $envelope.properties.EffectiveNetworkSecurityGroups.value[0].effectiveSecurityRules[0].name | Should -Be 'AllowVnetInBound'
        $envelope.properties.EffectiveRouteTable.value[0].nextHopType | Should -Be 'Internet'
        ($script:Calls -join "`n") | Should -Match 'POST .*/networkInterfaces/nic-1/effectiveNetworkSecurityGroups'
        ($script:Calls -join "`n") | Should -Match 'POST .*/networkInterfaces/nic-1/effectiveRouteTable'
    }

    It 'polls a 202 effective-network response and records a per-NIC health failure without dropping the NIC' {
        $nic = [pscustomobject]@{
            id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/nic-1'
            type = 'microsoft.network/networkinterfaces'; name = 'nic-1'; subscriptionId = 'sub-1'; resourceGroup = 'rg'
        }
        $health = [System.Collections.Generic.List[object]]::new()
        $script:PollCount = 0
        function global:Invoke-AzRestMethod {
            param($Path,$Uri,$Method,$Payload,$ErrorAction)
            $null=$Payload,$ErrorAction
            if ($Path -match 'effectiveNetworkSecurityGroups') {
                return [pscustomobject]@{ StatusCode=202; Content=''; Headers=@{ Location='/operations/nsg-1' } }
            }
            if ($Uri -or $Path -eq '/operations/nsg-1') {
                $script:PollCount++
                return [pscustomobject]@{ StatusCode=200; Content='{"value":[]}' }
            }
            if ($Path -match 'effectiveRouteTable') { return [pscustomobject]@{ StatusCode=403; Content='{}' } }
            [pscustomobject]@{ StatusCode=200; Content='{"value":[]}' }
        }

        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources @($nic) -Subscriptions @() -CollectionHealth $health -WarningAction SilentlyContinue)
        $envelope = $rows | Where-Object type -eq 'AZSC/Operational/NetworkInterface'

        $script:PollCount | Should -Be 1
        $envelope.properties.EffectiveNetworkSecurityGroups.PSObject.Properties['__AZSCError'] | Should -BeNullOrEmpty
        $envelope.properties.EffectiveRouteTable.__AZSCError | Should -Match 'status 403'
        @($health | Where-Object SourceDataset -eq 'NetworkInterface.EffectiveRouteTable').Count | Should -Be 1
        @($health | Where-Object SourceDataset -eq 'NetworkInterface.EffectiveRouteTable')[0].ResourceIds | Should -Contain $nic.id
    }

    It 'resolves a stable provider API version once and retains the provider GET payload' {
        $widget = [pscustomobject]@{
            id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Contoso/widgets/widget-1'
            type = 'microsoft.contoso/widgets'; name = 'widget-1'; subscriptionId = 'sub-1'; resourceGroup = 'rg'
            properties = [pscustomobject]@{ argOnly = 'summary' }
        }
        function global:Invoke-AzRestMethod {
            param($Path,$Uri,$Method,$Payload,$ErrorAction)
            $null=$Uri,$Method,$Payload,$ErrorAction
            $script:Calls.Add($Path)
            if ($Path -match '/providers/Microsoft\.Contoso\?api-version=2021-04-01$') {
                return [pscustomobject]@{ StatusCode=200; Content='{"resourceTypes":[{"resourceType":"widgets","apiVersions":["2026-01-01-preview","2025-06-01","2024-01-01"]}]}' }
            }
            if ($Path -match '/widgets/widget-1\?api-version=2025-06-01$') {
                return [pscustomobject]@{ StatusCode=200; Content='{"id":"widget-1","properties":{"fullSetting":"retained"}}' }
            }
            [pscustomobject]@{ StatusCode=200; Content='{"value":[]}' }
        }

        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources @($widget) -Subscriptions @() -IncludeProviderResourceDetails)
        $detail = $rows | Where-Object type -eq 'AZSC/ProviderDetail'

        $detail | Should -Not -BeNullOrEmpty
        $detail.properties.ApiVersion | Should -Be '2025-06-01'
        $detail.properties.Payload.properties.fullSetting | Should -Be 'retained'
        @($script:Calls | Where-Object { $_ -match '/providers/Microsoft\.Contoso\?' }).Count | Should -Be 1
    }

    It 'records provider-detail denial against only the affected resource and still emits its envelope' {
        $widget = [pscustomobject]@{
            id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Contoso/widgets/widget-1'
            type = 'microsoft.contoso/widgets'; name = 'widget-1'; subscriptionId = 'sub-1'; resourceGroup = 'rg'
        }
        $health = [System.Collections.Generic.List[object]]::new()
        function global:Invoke-AzRestMethod {
            param($Path,$Uri,$Method,$Payload,$ErrorAction)
            $null=$Uri,$Method,$Payload,$ErrorAction
            if ($Path -match '/providers/Microsoft\.Contoso\?') {
                return [pscustomobject]@{ StatusCode=200; Content='{"resourceTypes":[{"resourceType":"widgets","apiVersions":["2025-06-01"]}]}' }
            }
            if ($Path -match '/widgets/widget-1\?') { return [pscustomobject]@{ StatusCode=403; Content='{}' } }
            [pscustomobject]@{ StatusCode=200; Content='{"value":[]}' }
        }

        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources @($widget) -Subscriptions @() -IncludeProviderResourceDetails -CollectionHealth $health -WarningAction SilentlyContinue)
        $detail = $rows | Where-Object type -eq 'AZSC/ProviderDetail'
        $detail.properties.Payload.__AZSCError | Should -Match 'status 403'
        $providerHealth = @($health | Where-Object SourceDataset -eq 'ProviderDetails.Resource')
        $providerHealth.Count | Should -Be 1
        $providerHealth[0].ResourceIds | Should -Contain $widget.id
        $providerHealth[0].ResourceTypes | Should -Contain $widget.type
    }
    It 'contains a failed parent request while producing other envelopes' {
        function global:Invoke-AzRestMethod { param($Path,$Method,$Payload,$ErrorAction) $null=$Method,$Payload,$ErrorAction; if($Path -match 'vm-1/providers/microsoft.insights/metrics'){throw 'metrics denied'}; [pscustomobject]@{StatusCode=200;Content='{}'} }
        $Rows=@(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @() -WarningVariable Warnings)
        ($Rows | Where-Object type -eq 'AZSC/Operational/VirtualMachine').properties.CpuMetrics.__AZSCError | Should -Be 'metrics denied'
        ($Rows | Where-Object type -eq 'AZSC/Operational/ARCServers') | Should -Not -BeNullOrEmpty
        ($Warnings -join "`n") | Should -Match 'VirtualMachine.CpuMetrics'
    }

    It 'records exact collector health for every operational wrapper family that fails' {
        $health = [System.Collections.Generic.List[object]]::new()
        function global:Invoke-AzRestMethod {
            param($Path,$Method,$Payload,$ErrorAction)
            $null=$Method,$Payload,$ErrorAction
            if($Path -match 'Microsoft.CostManagement/query'){ throw 'HTTP 429 TooManyRequests' }
            [pscustomobject]@{StatusCode=200;Content='{"value":[]}' }
        }
        function global:Get-AzStorageBlobServiceProperty { param($ResourceGroupName,$Name,$ErrorAction) $null=$ResourceGroupName,$Name,$ErrorAction; throw 'blob read denied' }
        function global:Search-AzGraph { param($Query,$First,$ErrorAction) $null=$Query,$First,$ErrorAction; throw 'management group query denied' }

        $rows = @(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @(
                [pscustomobject]@{Id='sub-1';Name='Subscription One';TenantId='tenant-a'}
            ) -CollectionHealth $health -WarningAction SilentlyContinue)

        $rows.Count | Should -Be 6
        @($health | ForEach-Object Collectors) | Should -Contain 'Compute/VirtualMachine'
        @($health | ForEach-Object Collectors) | Should -Contain 'Hybrid/ARCServers'
        @($health | ForEach-Object Collectors) | Should -Contain 'Storage/StorageAccounts'
        @($health | ForEach-Object Collectors) | Should -Contain 'Management/AllSubscriptions'
        @($health | Where-Object SourceDataset -eq 'VirtualMachine.EstimatedCost').Count | Should -Be 1
        @($health | Where-Object SourceDataset -eq 'ARCServers.EstimatedCost').Count | Should -Be 1
        @($health | Where-Object SourceDataset -eq 'StorageAccounts.BlobService').Count | Should -Be 1
        @($health | Where-Object SourceDataset -eq 'AllSubscriptions.ManagementGroupPath').Count | Should -Be 1
        @($health | Where-Object Collectors -contains 'Storage/StorageAccounts')[0].ResourceTypes | Should -Be @('AZSC/Operational/StorageAccount')
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

    It 'logs a complete monotonic request ledger and emits terminal progress only after all work is complete' {
        $script:OperationalLogs = [System.Collections.Generic.List[string]]::new()
        $script:OperationalProgress = [System.Collections.Generic.List[object]]::new()
        function global:Write-AZSCLog {
            param($Level, $Message)
            $script:OperationalLogs.Add("$Level|$Message")
        }
        function global:Write-Progress {
            param($Id, $ParentId, $Activity, $Status, $PercentComplete, [switch]$Completed)
            $script:OperationalProgress.Add([pscustomobject]@{
                    Id = $Id; ParentId = $ParentId; Activity = $Activity; Status = $Status
                    PercentComplete = $PercentComplete; Completed = $Completed.IsPresent
                })
        }
        try {
            $null = @(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @(
                    [pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; TenantId = 'tenant-a' }
                ))

            @($script:OperationalLogs | Where-Object { $_ -match 'Operational enrichment plan:' }).Count | Should -Be 1
            $finished = @($script:OperationalLogs | Where-Object { $_ -match 'Operational request finished:' })
            $finished.Count | Should -BeGreaterThan 0
            $completed = @($finished | ForEach-Object {
                    [int][regex]::Match($_, 'completed=(\d+)').Groups[1].Value
                })
            $completed | Should -Be @(1..$finished.Count)
            foreach ($line in $finished) {
                $done = [int][regex]::Match($line, 'completed=(\d+)').Groups[1].Value
                $planned = [int][regex]::Match($line, 'planned=(\d+)').Groups[1].Value
                $done | Should -BeLessOrEqual $planned
            }

            $summary = @($script:OperationalLogs | Where-Object { $_ -match 'Operational enrichment complete:' })
            $summary.Count | Should -Be 1
            $summary[0] | Should -Match "completed=$($finished.Count); planned=$($finished.Count)"
            ($script:OperationalLogs -join "`n") | Should -Not -Match '(?i)/subscriptions/|resourceGroups/|\{\s*"'

            $terminal = @($script:OperationalProgress | Where-Object Completed)
            $terminal.Count | Should -Be 1
            $script:OperationalProgress[-1].Completed | Should -BeTrue
            @($script:OperationalProgress | Select-Object -SkipLast 1 | Where-Object Completed) | Should -BeNullOrEmpty
            foreach ($progress in @($script:OperationalProgress | Where-Object { -not $_.Completed })) {
                $progress.PercentComplete | Should -BeGreaterOrEqual 0
                $progress.PercentComplete | Should -BeLessOrEqual 99
            }
            $percentages = @($script:OperationalProgress |
                    Where-Object { -not $_.Completed } |
                    ForEach-Object { [int]$_.PercentComplete })
            for ($index = 1; $index -lt $percentages.Count; $index++) {
                $percentages[$index] | Should -BeGreaterOrEqual $percentages[$index - 1]
            }
        }
        finally {
            Remove-Item Function:\Write-AZSCLog -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Write-Progress -Force -ErrorAction SilentlyContinue
        }
    }

    It 'records every remote wrapper family including dynamic protected-item discovery without identifiers' {
        $script:OperationalLogs = [System.Collections.Generic.List[string]]::new()
        function global:Write-AZSCLog { param($Level, $Message) $script:OperationalLogs.Add("$Level|$Message") }
        function global:Write-Progress { param($Id, $ParentId, $Activity, $Status, $PercentComplete, [switch]$Completed) }
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $Payload, $ErrorAction)
            $null = $Method, $Payload, $ErrorAction
            if ($Path -match '/Microsoft.RecoveryServices/vaults\?') {
                return [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.RecoveryServices/vaults/vault-1","name":"vault-1"}]}' }
            }
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' }
        }
        try {
            $null = @(Get-ScoutOperationalCollectorEnrichment -Resources $script:Resources -Subscriptions @(
                    [pscustomobject]@{ Id = 'sub-1'; Name = 'Subscription One'; TenantId = 'tenant-a' }
                ))
            $text = $script:OperationalLogs -join "`n"
            foreach ($dataset in @(
                    'VirtualMachine.ReplicationEligibility', 'VirtualMachine.ReplicationVaults',
                    'VirtualMachine.ReplicationProtectedItems', 'VirtualMachine.CpuMetrics',
                    'VirtualMachine.MemoryMetrics', 'VirtualMachine.EstimatedCost',
                    'ARCServers.PolicyCompliance', 'ARCServers.EstimatedCost',
                    'StorageAccounts.EnterSubscriptionContext', 'StorageAccounts.BlobService',
                    'StorageAccounts.FileService', 'StorageAccounts.RestoreSubscriptionContext',
                    'AllSubscriptions.ManagementGroupPath'
                )) {
                $text | Should -Match ([regex]::Escape("dataset=$dataset"))
            }
            $text | Should -Not -Match '(?i)/subscriptions/|resourceGroups/'
        }
        finally {
            Remove-Item Function:\Write-AZSCLog -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Write-Progress -Force -ErrorAction SilentlyContinue
        }
    }

    It 'logs retry attempts and one final completion with the accurate attempt count' {
        $script:OperationalLogs = [System.Collections.Generic.List[string]]::new()
        $script:RetryLedgerAttempts = 0
        function global:Write-AZSCLog { param($Level, $Message) $script:OperationalLogs.Add("$Level|$Message") }
        function global:Write-Progress { param($Id, $ParentId, $Activity, $Status, $PercentComplete, [switch]$Completed) }
        function global:Invoke-AzRestMethod {
            param($Path, $Method, $Payload, $ErrorAction)
            $null = $Method, $Payload, $ErrorAction
            if ($Path -match 'Microsoft.CostManagement/query') {
                $script:RetryLedgerAttempts++
                if ($script:RetryLedgerAttempts -eq 1) { return [pscustomobject]@{ StatusCode = 429; Content = '{}' } }
            }
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' }
        }
        try {
            $null = @(Get-ScoutOperationalCollectorEnrichment -Resources @($script:Resources[0]) -Subscriptions @())
            @($script:OperationalLogs | Where-Object { $_ -match 'Operational request retry: dataset=VirtualMachine.EstimatedCost; attempt=1; maximum=3' }).Count | Should -Be 1
            @($script:OperationalLogs | Where-Object { $_ -match 'Operational request finished: dataset=VirtualMachine.EstimatedCost; status=Success; attempts=2;' }).Count | Should -Be 1
        }
        finally {
            Remove-Item Function:\Write-AZSCLog -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Write-Progress -Force -ErrorAction SilentlyContinue
        }
    }
}
