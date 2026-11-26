#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Unit and contract tests for Get-ScoutArmChildResource.

    Invoke-AzRestMethod is replaced with a deterministic local function throughout. No Azure
    context, credentials, tenant identifiers, or network access are used.
#>

Describe 'Get-ScoutArmChildResource' {
BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')

    function Get-TestParent {
        param(
            [string]$Type,
            [string]$Name,
            [string]$Kind,
            [hashtable]$Properties = @{}
        )

        [PSCustomObject]@{
            id             = "/subscriptions/sub-test/resourceGroups/rg-test/providers/$Type/$Name"
            type           = $Type
            name           = $Name
            kind           = $Kind
            subscriptionId = 'sub-test'
            resourceGroup  = 'rg-test'
            location       = 'eastus'
            properties     = [PSCustomObject]$Properties
        }
    }

    $script:Parents = @(
        Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml-standard' -Kind 'Default'
        Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml-hub' -Kind 'Hub'
        Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml-project' -Kind 'Project'
        Get-TestParent -Type 'microsoft.cognitiveservices/accounts' -Name 'openai-one' -Kind 'OpenAI'
        Get-TestParent -Type 'microsoft.search/searchservices' -Name 'search-one'
        Get-TestParent -Type 'microsoft.desktopvirtualization/applicationgroups' -Name 'remoteapps-one' `
            -Properties @{ applicationGroupType = 'RemoteApp' }
        Get-TestParent -Type 'microsoft.desktopvirtualization/applicationgroups' -Name 'desktop-one' `
            -Properties @{ applicationGroupType = 'Desktop' }
        Get-TestParent -Type 'microsoft.insights/components' -Name 'appi-one'
        Get-TestParent -Type 'microsoft.operationalinsights/workspaces' -Name 'law-one'
        Get-TestParent -Type 'microsoft.hybridcompute/machines' -Name 'arc-machine-one'
    )

    function Get-ArmChildResponseStub {
        $script:ArmCalls = [System.Collections.Generic.List[string]]::new()

        function global:Invoke-AzRestMethod {
            param(
                [string]$Path,
                [string]$Method,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Method, $Rest

            $script:ArmCalls.Add($Path)

            $Payload = switch -Regex ($Path) {
                '/data/[^/]+/versions' {
                    @{ value = @(@{ id = "$Path/version-one"; name = 'version-one'; properties = @{ dataType = 'uri_file' } }) }
                    break
                }
                '/models/[^/]+/versions' {
                    @{ value = @(@{ id = "$Path/version-one"; name = 'version-one'; properties = @{ flavors = @{ python = @{} } } }) }
                    break
                }
                '/onlineEndpoints/[^/]+/deployments' {
                    @{ value = @(@{ name = 'blue' }, @{ name = 'green' }) }
                    break
                }
                '/batchEndpoints/[^/]+/deployments' {
                    @{ value = @(@{ name = 'batch-deployment' }) }
                    break
                }
                '/onlineEndpoints\?' {
                    @{ value = @(@{ id = "$Path/endpoint-online"; name = 'endpoint-online'; type = 'Microsoft.MachineLearningServices/onlineEndpoints'; properties = @{ authMode = 'aadToken' } }) }
                    break
                }
                '/batchEndpoints\?' {
                    @{ value = @(@{ id = "$Path/endpoint-batch"; name = 'endpoint-batch'; type = 'Microsoft.MachineLearningServices/batchEndpoints'; properties = @{ authMode = 'aadToken' } }) }
                    break
                }
                '/ProactiveDetectionConfigs\?' {
                    @(@{ id = "$Path/rule-one"; name = 'rule-one'; Enabled = $true })
                    break
                }
                default {
                    $Leaf = (($Path -split '\?')[0] -split '/')[-1]
                    @{ value = @(@{
                        id         = "$(($Path -split '\?')[0])/$Leaf-one"
                        name       = "$Leaf-one"
                        type       = "Test.Provider/$Leaf"
                        properties = @{ state = 'Ready' }
                    }) }
                }
            }

            [PSCustomObject]@{
                StatusCode = 200
                Content    = ($Payload | ConvertTo-Json -Depth 12 -Compress)
            }
        }
    }

    Get-ArmChildResponseStub
}

AfterAll {
    foreach ($Name in 'Invoke-AzRestMethod', 'Get-AzAccessToken', 'Invoke-WebRequest') {
        Remove-Item -Path "Function:\$Name" -Force -ErrorAction SilentlyContinue
    }
}

BeforeEach {
    Get-ArmChildResponseStub
}

Describe 'Get-ScoutArmChildResource - supported-dataset contract' {
    It 'classifies only the Sentinel onboarding service error as not applicable' {
        $parent = Get-TestParent -Type 'microsoft.operationalinsights/workspaces' -Name 'law'
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 400; Content = '{"error":{"code":"BadRequest","message":"Workspace is not onboarded to Microsoft Sentinel."}}' } }
        $health = [System.Collections.Generic.List[object]]::new()
        $operations = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources @($parent) -Dataset SentinelDataConnectors -CollectionHealth $health -SourceOperations $operations)
        $rows.Count | Should -Be 0
        $health[0].Status | Should -Be 'NotAssessed'
        $health[0].Reason | Should -Match 'Not applicable'
        $operations[0].Status | Should -Be 'NotApplicable'
    }

    It 'retries a dropped connection instead of losing the dataset' {
        $parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'st1' -Kind 'StorageV2'
        $script:DropCount = 0
        Mock Start-Sleep { }
        Mock Invoke-AzRestMethod {
            if ($Path -match '/blobServices/default/containers' -and $script:DropCount -lt 1) {
                $script:DropCount++
                throw 'An error occurred while sending the request.'
            }
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"c1","name":"c1"}]}' }
        }
        $health = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources @($parent) -Dataset StorageBlobContainers -CollectionHealth $health -WarningAction SilentlyContinue)
        $script:DropCount | Should -Be 1
        $rows.Count | Should -BeGreaterThan 0
        @($health | Where-Object Status -eq 'Unavailable').Count | Should -Be 0
    }

    It 'records an unregistered resource provider once per subscription as not assessed, without warnings' {
        # Live run: one warning per NSG and the whole dataset Unavailable because a subscription
        # had not registered microsoft.insights. That is a stated gap, not a failure.
        $parents = @(
            Get-TestParent -Type 'microsoft.network/networksecuritygroups' -Name 'nsg-a'
            Get-TestParent -Type 'microsoft.network/networksecuritygroups' -Name 'nsg-b'
        )
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 400; Content = '{"error":{"code":"SubscriptionNotRegistered","message":"The subscription ''00000000-0000-0000-0000-000000000001'' is not registered to use microsoft.insights."}}' } }
        $health = [System.Collections.Generic.List[object]]::new()
        $operations = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources $parents -Dataset ResourceDiagnosticSettings -CollectionHealth $health -SourceOperations $operations -WarningVariable warned -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 0
        @($warned).Count | Should -Be 0
        $health.Count | Should -Be 1
        $health[0].Status | Should -Be 'NotAssessed'
        $health[0].Reason | Should -Match 'not registered for the microsoft\.insights resource provider'
        @($operations | Where-Object Status -eq 'NotApplicable').Count | Should -Be 2
    }

    It 'keeps other Sentinel HTTP 400 errors unavailable with their service detail' {
        $parent = Get-TestParent -Type 'microsoft.operationalinsights/workspaces' -Name 'law'
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 400; Content = '{"error":{"code":"BadRequest","message":"Invalid parameter example"}}' } }
        $health = [System.Collections.Generic.List[object]]::new()
        $null = Get-ScoutArmChildResource -Resources @($parent) -Dataset SentinelDataConnectors -CollectionHealth $health -WarningAction SilentlyContinue
        $health[0].Status | Should -Be 'Unavailable'
        $health[0].Reason | Should -Match 'Invalid parameter example'
    }

    It 'emits all supported synthetic types in canonical order without retired endpoints' {
        $Rows = @(Get-ScoutArmChildResource -Resources $script:Parents)
        $Types = @($Rows.TYPE | Select-Object -Unique)

        $Types | Should -Be @(
            'AZSC/ARMChild/MLComputes'
            'AZSC/ARMChild/MLDatasets'
            'AZSC/ARMChild/MLDatastores'
            'AZSC/ARMChild/MLEndpoints'
            'AZSC/ARMChild/MLModels'
            'AZSC/ARMChild/MLPipelines'
            'AZSC/ARMChild/OpenAIDeployments'
            'AZSC/ARMChild/AVDApplications'
            'AZSC/ARMChild/AppInsightsProactiveDetection'
            'AZSC/ARMChild/LAWorkspaceLinkedServices'
            'AZSC/ARMChild/LAWorkspaceSavedSearches'
            'AZSC/ARMChild/LAWorkspaceTables'
            'AZSC/ARMChild/SentinelDataConnectors'
            # AB#6769. The Log Analytics workspace in $script:Parents is one of the parent types
            # the diagnostic-settings sweep is scoped to, so it emits here too. This entry
            # is the canary for that scope: if a type is ever added to
            # $DiagnosticSettingParentTypes that also appears above, this list grows and the run
            # got more expensive.
            'AZSC/ARMChild/ResourceDiagnosticSettings'
            'AZSC/ARMChild/AzureLocalVirtualMachineInstances'
        )
        # 16 before AB#9300 phase 4 batch 2. That batch added the machine learning workspaces
        # (all three: standard, hub and project), the search service and the Application Insights
        # component in $script:Parents to the diagnostic sweep, so each now yields one more
        # diagnostic-settings row: 16 + 5 = 21. None of the eight new datasets emits here because
        # $script:Parents holds no storage account, SQL server, web app, Event Hubs namespace or
        # Redis Enterprise cluster.
        $Rows.Count | Should -Be 21 -Because 'MLEndpoints emits one online and one batch endpoint, the LA workspace yields tables, Sentinel connectors, and a diagnostic setting, the Arc machine yields one Azure Local VM instance, Search indexes are data-plane-only, and five more parents (three ML workspaces, the search service and the App Insights component) each yield one diagnostic setting'
    }

    It 'preserves raw child properties and stamps parent linkage on every row' {
        $Rows = @(Get-ScoutArmChildResource -Resources $script:Parents)

        foreach ($Row in $Rows) {
            $Row.id | Should -Not -BeNullOrEmpty
            $Row.name | Should -Not -BeNullOrEmpty
            $Row.PARENTID | Should -Match '^/subscriptions/sub-test/'
            $Row.PARENTTYPE | Should -Not -BeNullOrEmpty
            $Row.PARENTNAME | Should -Not -BeNullOrEmpty
            $Row.subscriptionId | Should -Be 'sub-test'
            $Row.RESOURCEGROUP | Should -Be 'rg-test'
            $Row.AZSC.Dataset | Should -Be ($Row.TYPE -replace '^AZSC/ARMChild/', '')
            $Row.AZSC.ParentId | Should -Be $Row.PARENTID
            $Row.AZSC.SourceType | Should -Not -BeNullOrEmpty
            $Row.AZSC.Source | Should -Be 'Azure Resource Manager'
            $Row.AZSC.Operation | Should -Be 'GET'
            $Row.AZSC.Uri | Should -Match 'api-version='
            $Row.AZSC.ApiVersion | Should -Not -BeNullOrEmpty
            $Row.AZSC.CollectedAt | Should -Not -BeNullOrEmpty
        }
    }

    It 'records each successful ARM request independently from collection health' {
        $health = [System.Collections.Generic.List[object]]::new()
        $operations = [System.Collections.Generic.List[object]]::new()

        $rows = @(Get-ScoutArmChildResource -Resources $script:Parents -Dataset MLComputes `
                -CollectionHealth $health -SourceOperations $operations)

        @($rows).Count | Should -Be 1
        @($health).Count | Should -Be 0
        @($operations).Count | Should -Be 1
        $operations[0].Source | Should -Be 'Azure Resource Manager'
        $operations[0].Status | Should -Be 'Success'
        $operations[0].Count | Should -Be 1
        $operations[0].Uri | Should -Match '/computes\?api-version=2023-04-01'
    }

    It 'excludes ML Hub/Project workspaces and non-RemoteApp AVD groups before calling ARM' {
        $null = Get-ScoutArmChildResource -Resources $script:Parents
        # The ML child datasets (computes, data, models, ...) skip Hub and Project workspaces. A
        # Hub or Project is still a workspace that can carry a diagnostic setting, and since
        # AB#9300 phase 4 batch 2 the diagnostic sweep asks it, so only the non-diagnostic calls
        # are held to the exclusion.
        $childCalls = @($script:ArmCalls | Where-Object { $_ -notmatch 'Microsoft\.Insights/diagnosticSettings' })
        ($childCalls -join "`n") | Should -Not -Match 'ml-hub'
        ($childCalls -join "`n") | Should -Not -Match 'ml-project'
        ($script:ArmCalls -join "`n") | Should -Not -Match 'desktop-one'
        ($script:ArmCalls -join "`n") | Should -Match 'ml-standard'
        ($script:ArmCalls -join "`n") | Should -Match 'remoteapps-one'
    }

    It 'captures latest ML versions and endpoint deployment counts as metadata' {
        $Rows = @(Get-ScoutArmChildResource -Resources $script:Parents)

        ($Rows | Where-Object TYPE -eq 'AZSC/ARMChild/MLDatasets').AZSC.LatestVersion.name |
            Should -Be 'version-one'
        ($Rows | Where-Object TYPE -eq 'AZSC/ARMChild/MLModels').AZSC.LatestVersion.name |
            Should -Be 'version-one'

        $Online = $Rows | Where-Object { $_.TYPE -eq 'AZSC/ARMChild/MLEndpoints' -and $_.AZSC.EndpointType -eq 'onlineEndpoints' }
        $Batch = $Rows | Where-Object { $_.TYPE -eq 'AZSC/ARMChild/MLEndpoints' -and $_.AZSC.EndpointType -eq 'batchEndpoints' }
        $Online.AZSC.DeploymentCount | Should -Be 2
        $Batch.AZSC.DeploymentCount | Should -Be 1
    }

    It 'uses the API versions and special query clauses from the current collectors' {
        $null = Get-ScoutArmChildResource -Resources $script:Parents
        $Calls = $script:ArmCalls -join "`n"

        $Calls | Should -Match '/computes\?api-version=2023-04-01'
        $Calls | Should -Match '/data\?api-version=2023-04-01'
        $Calls | Should -Match '/versions\?api-version=2023-04-01&\$orderby=createdTime desc&\$top=1'
        $Calls | Should -Match '/jobs\?api-version=2023-04-01&\$filter=jobType eq ''Pipeline'''
        $Calls | Should -Match '/deployments\?api-version=2023-05-01'
        $Calls | Should -Not -Match '/indexes\?api-version=2023-11-01' -Because 'Search indexes are data-plane objects and ARM Reader cannot list them'
        $Calls | Should -Match '/applications\?api-version=2022-09-09'
        $Calls | Should -Match '/ProactiveDetectionConfigs\?api-version=2018-05-01-preview'
        $Calls | Should -Match '/linkedServices\?api-version=2020-08-01'
        $Calls | Should -Match '/savedSearches\?api-version=2020-08-01'
        $Calls | Should -Not -Match 'listQueryKeys' -Because 'the current SearchIndexes collector constructs that URI but never calls it'
        $Calls | Should -Not -Match '(?i)exportconfiguration|WorkItemConfigs' -Because 'both Application Insights endpoints are retired'
    }

    It 'reads the Azure Local VM instance singleton per Arc machine and stamps parent location (AB#6802)' {
        $Rows = @(Get-ScoutArmChildResource -Resources $script:Parents -Dataset 'AzureLocalVirtualMachineInstances')
        $Calls = $script:ArmCalls -join "`n"

        $Calls | Should -Match '/providers/Microsoft\.AzureStackHCI/virtualMachineInstances/default\?api-version=2024-01-01'
        $Rows.Count | Should -Be 1
        $Rows[0].TYPE | Should -Be 'AZSC/ARMChild/AzureLocalVirtualMachineInstances'
        $Rows[0].PARENTNAME | Should -Be 'arc-machine-one'
        $Rows[0].PARENTLOCATION | Should -Be 'eastus'
    }
}

Describe 'Get-ScoutArmChildResource - selection, ordering and resilience' {
    It 'calls only requested datasets and still uses canonical dataset order' {
        $Rows = @(Get-ScoutArmChildResource -Resources $script:Parents -Dataset @('SearchIndexes', 'MLComputes'))

        $Rows.TYPE | Should -Be @('AZSC/ARMChild/MLComputes')
        $script:ArmCalls.Count | Should -Be 1
    }

    It 'marks Search indexes not assessed without calling an invalid ARM endpoint' {
        $health = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources $script:Parents -Dataset SearchIndexes `
                -CollectionHealth $health)

        $rows | Should -BeNullOrEmpty
        $script:ArmCalls.Count | Should -Be 0
        @($health).Count | Should -Be 1
        $health[0].Dataset | Should -Be 'SearchIndexes'
        $health[0].Status | Should -Be 'NotAssessed'
        $health[0].Reason | Should -Match 'data-plane'
    }

    It 'makes no ARM calls when no matching parents exist' {
        # This used to use a storage account, which became a MATCHING parent when AB#6834 added
        # the blob-container, file-share and lifecycle-policy datasets. A virtual network is a
        # type no dataset claims, so the assertion still tests what it says it does.
        $Rows = @(Get-ScoutArmChildResource -Resources @(
            Get-TestParent -Type 'microsoft.network/virtualnetworks' -Name 'vnet-one'
        ))

        $Rows | Should -BeNullOrEmpty
        $script:ArmCalls.Count | Should -Be 0
    }

    It 'contains one failed child collection and continues with the next dataset' {
        function global:Invoke-AzRestMethod {
            param(
                [string]$Path,
                [string]$Method,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Method, $Rest
            if ($Path -match '/computes\?') { throw 'simulated ARM failure' }
            [PSCustomObject]@{
                StatusCode = 200
                Content = (@{ value = @(@{
                    id = "$Path/child-one"; name = 'child-one'; type = 'Test.Provider/child'; properties = @{}
                }) } | ConvertTo-Json -Depth 8 -Compress)
            }
        }

        $Warnings = @()
        $Rows = @(Get-ScoutArmChildResource -Resources $script:Parents `
            -Dataset @('MLComputes', 'MLDatastores') -WarningVariable Warnings)

        @($Rows | Where-Object TYPE -eq 'AZSC/ARMChild/MLComputes') | Should -BeNullOrEmpty
        @($Rows | Where-Object TYPE -eq 'AZSC/ARMChild/MLDatastores').Count | Should -Be 1
        $Warnings.Count | Should -Be 1
        $Warnings[0].Message | Should -Match 'MLComputes'
        $Warnings[0].Message | Should -Match 'simulated ARM failure'
    }

    It 'accepts both ARM value envelopes and bare arrays without changing child shape' {
        $Rows = @(Get-ScoutArmChildResource -Resources $script:Parents)

        @($Rows | Where-Object TYPE -match 'AppInsights(ContinuousExport|WorkItems)').Count | Should -Be 0
        ($script:ArmCalls -join "`n") | Should -Not -Match '(?i)exportconfiguration|WorkItemConfigs'
    }

    It 'follows ARM nextLink pages without dropping child resources (AB#7358)' {
        $storage = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage-paged'
        $script:pagedCalls = [System.Collections.Generic.List[string]]::new()
        function global:Invoke-AzRestMethod {
            [CmdletBinding()]
            param([string]$Path, [string]$Uri, [string]$Method)
            $null = $Method
            $RequestUri = if ($Uri) { $Uri } else { $Path }
            $script:pagedCalls.Add($RequestUri)

            $payload = if ($RequestUri -eq 'https://management.azure.com/next-queues-page') {
                @{ value = @(@{ id = "$($storage.id)/queueServices/default/queues/queue-two"; name = 'queue-two'; properties = @{} }) }
            }
            else {
                @{
                    value = @(@{ id = "$($storage.id)/queueServices/default/queues/queue-one"; name = 'queue-one'; properties = @{} })
                    nextLink = 'https://management.azure.com/next-queues-page'
                }
            }
            [pscustomobject]@{ StatusCode = 200; Content = ($payload | ConvertTo-Json -Depth 8 -Compress) }
        }

        $rows = @(Get-ScoutArmChildResource -Resources @($storage) -Dataset StorageQueues)

        $rows.Count | Should -Be 2
        @($rows.name | Sort-Object) | Should -Be @('queue-one', 'queue-two')
        $script:pagedCalls | Should -Be @(
            "$($storage.id)/queueServices/default/queues?api-version=2023-05-01"
            'https://management.azure.com/next-queues-page'
        )
    }

    It 'treats an absent storage lifecycle policy as empty without warning or terminating error' {
        $storage = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage-one'
        function global:Invoke-AzRestMethod {
            param(
                [string]$Path,
                [string]$Method,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Path, $Method, $Rest
            [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound"}}' }
        }

        $warnings = @()
        $health = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources @($storage) -Dataset StorageLifecyclePolicies `
                -CollectionHealth $health -WarningVariable warnings)

        $rows | Should -BeNullOrEmpty
        @($warnings).Count | Should -Be 0
        @($health).Count | Should -Be 0
    }

    It 'binds against the Az.Accounts 5.5.2 command surface without an unsupported switch' {
        $storage = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage-one'
        $script:boundCalls = 0
        function global:Invoke-AzRestMethod {
            [CmdletBinding()]
            param([string]$Path, [string]$Method)
            $null = $Path, $Method
            $script:boundCalls++
            [pscustomobject]@{ StatusCode = 200; Content = '{"properties":{"policy":{"rules":[]}}}' }
        }

        $rows = @(Get-ScoutArmChildResource -Resources @($storage) -Dataset StorageLifecyclePolicies)

        $script:boundCalls | Should -Be 1
        @($rows).Count | Should -Be 1
    }

    It 'classifies a thrown expected 404 as empty without warning or failed health' {
        $storage = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage-one'
        function global:Invoke-AzRestMethod {
            [CmdletBinding()]
            param([string]$Path, [string]$Method)
            $null = $Path, $Method
            $exception = [System.InvalidOperationException]::new('ARM status code 404')
            $exception.Data['StatusCode'] = 404
            throw $exception
        }

        $warnings = @()
        $health = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources @($storage) -Dataset StorageLifecyclePolicies `
                -CollectionHealth $health -WarningVariable warnings)

        $rows | Should -BeNullOrEmpty
        @($warnings).Count | Should -Be 0
        @($health).Count | Should -Be 0
    }

    It 'preserves successful rows while recording one health item for a failed dataset' {
        $parents = @(
            Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml-failed' -Kind 'Default'
            Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml-ok' -Kind 'Default'
        )
        function global:Invoke-AzRestMethod {
            [CmdletBinding()]
            param([string]$Path, [string]$Method)
            $null = $Method
            if ($Path -match 'ml-failed') { throw 'ARM status 403' }
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"child-ok","name":"child-ok","properties":{}}]}' }
        }

        $warnings = @()
        $health = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources $parents -Dataset MLComputes `
                -CollectionHealth $health -WarningVariable warnings)

        @($rows).Count | Should -Be 1
        $rows[0].PARENTNAME | Should -Be 'ml-ok'
        @($warnings).Count | Should -Be 1
        @($health).Count | Should -Be 1
        $health[0].Dataset | Should -Be 'MLComputes'
        $health[0].Status | Should -Be 'Unavailable'
        $health[0].ResourceTypes | Should -Be @('AZSC/ARMChild/MLComputes')
    }

    It 'covers every ARM-child dataset across the supported remote outcome matrix' {
        $datasetCases = @(
            @{ Dataset = 'MLComputes'; Parent = Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml' -Kind 'Default'; NotFoundIsEmpty = $false }
            @{ Dataset = 'MLDatasets'; Parent = Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml' -Kind 'Default'; NotFoundIsEmpty = $false }
            @{ Dataset = 'MLDatastores'; Parent = Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml' -Kind 'Default'; NotFoundIsEmpty = $false }
            @{ Dataset = 'MLEndpoints'; Parent = Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml' -Kind 'Default'; NotFoundIsEmpty = $false }
            @{ Dataset = 'MLModels'; Parent = Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml' -Kind 'Default'; NotFoundIsEmpty = $false }
            @{ Dataset = 'MLPipelines'; Parent = Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml' -Kind 'Default'; NotFoundIsEmpty = $false }
            @{ Dataset = 'OpenAIDeployments'; Parent = Get-TestParent -Type 'microsoft.cognitiveservices/accounts' -Name 'openai' -Kind 'OpenAI'; NotFoundIsEmpty = $false }
            @{ Dataset = 'SearchIndexes'; Parent = Get-TestParent -Type 'microsoft.search/searchservices' -Name 'search'; NotFoundIsEmpty = $false }
            @{ Dataset = 'AVDApplications'; Parent = Get-TestParent -Type 'microsoft.desktopvirtualization/applicationgroups' -Name 'apps' -Properties @{ applicationGroupType = 'RemoteApp' }; NotFoundIsEmpty = $false }
            @{ Dataset = 'AppInsightsProactiveDetection'; Parent = Get-TestParent -Type 'microsoft.insights/components' -Name 'appi'; NotFoundIsEmpty = $false }
            @{ Dataset = 'LAWorkspaceLinkedServices'; Parent = Get-TestParent -Type 'microsoft.operationalinsights/workspaces' -Name 'law'; NotFoundIsEmpty = $false }
            @{ Dataset = 'LAWorkspaceSavedSearches'; Parent = Get-TestParent -Type 'microsoft.operationalinsights/workspaces' -Name 'law'; NotFoundIsEmpty = $false }
            @{ Dataset = 'LAWorkspaceTables'; Parent = Get-TestParent -Type 'microsoft.operationalinsights/workspaces' -Name 'law'; NotFoundIsEmpty = $false }
            @{ Dataset = 'SentinelDataConnectors'; Parent = Get-TestParent -Type 'microsoft.operationalinsights/workspaces' -Name 'law'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageBlobContainers'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageFileShares'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageLifecyclePolicies'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $true }
            @{ Dataset = 'StorageQueues'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageTables'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'BackupInstances'; Parent = Get-TestParent -Type 'microsoft.dataprotection/backupvaults' -Name 'backup'; NotFoundIsEmpty = $false }
            @{ Dataset = 'ResourceDiagnosticSettings'; Parent = Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv'; NotFoundIsEmpty = $false }
            @{ Dataset = 'ReservationUtilization'; Parent = Get-TestParent -Type 'microsoft.capacity/reservationorders/reservations' -Name 'reservation'; NotFoundIsEmpty = $false }
            @{ Dataset = 'AzureLocalVirtualMachineInstances'; Parent = Get-TestParent -Type 'microsoft.hybridcompute/machines' -Name 'arc'; NotFoundIsEmpty = $true }
            # AB#9300 phase 4, batch 2. Every one is read with -NotFoundIsEmpty: a missing
            # singleton or an absent list is ordinary empty data, not a failure.
            @{ Dataset = 'StorageBlobServiceProperties'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $true }
            @{ Dataset = 'StorageFileServiceProperties'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $true }
            @{ Dataset = 'SqlServerAuditing'; Parent = Get-TestParent -Type 'microsoft.sql/servers' -Name 'sql'; NotFoundIsEmpty = $true }
            @{ Dataset = 'SqlFailoverGroups'; Parent = Get-TestParent -Type 'microsoft.sql/servers' -Name 'sql'; NotFoundIsEmpty = $true }
            @{ Dataset = 'WebAppConfig'; Parent = Get-TestParent -Type 'microsoft.web/sites' -Name 'web'; NotFoundIsEmpty = $true }
            @{ Dataset = 'WebAppBasicAuth'; Parent = Get-TestParent -Type 'microsoft.web/sites' -Name 'web'; NotFoundIsEmpty = $true }
            @{ Dataset = 'EventHubGeoDr'; Parent = Get-TestParent -Type 'microsoft.eventhub/namespaces' -Name 'hub'; NotFoundIsEmpty = $true }
            @{ Dataset = 'RedisEnterpriseDatabases'; Parent = Get-TestParent -Type 'microsoft.cache/redisenterprise' -Name 'redis'; NotFoundIsEmpty = $true }
            # AB#9300, 3.18.19 -- Azure VMware Solution private-cloud children. All thirteen accept a 404
            # as empty data (a private cloud still building has no workload network yet). The two
            # per-cluster datasets are driven by the cluster list the matrix stub answers with one cluster.
            @{ Dataset = 'AvsClusters'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsDatastores'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsPlacementPolicies'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsAddons'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsGlobalReachConnections'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsAuthorizations'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsCloudLinks'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsSegments'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsDhcpConfigurations'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsDnsServices'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsGateways'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsIscsiPaths'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
            @{ Dataset = 'AvsMaintenances'; Parent = Get-TestParent -Type 'microsoft.avs/privateclouds' -Name 'pc'; NotFoundIsEmpty = $true }
        )
        $declaredDatasets = @(
            (Get-Command Get-ScoutArmChildResource).Parameters['Dataset'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object ValidValues |
                Where-Object { $_ -ne 'All' }
        )
        @($datasetCases.Dataset) | Should -Be @($declaredDatasets | Where-Object { $_ -ne 'SentinelIngestion' }) -Because 'the ARM/Key Vault matrix must track every shipped request dataset; Sentinel ingestion has its own Logs Query API contract tests'

        # Cross every shipped dataset with each materially different response class: usable
        # success, valid empty, returned/thrown not-found, authorization, throttling, server
        # failure, absent response and malformed payload. This remains entirely offline.
        $outcomes = @(
            'Success200',
            'Empty200',
            'Returned404',
            'Thrown404Data',
            'Thrown404Response',
            'Thrown403',
            'Thrown429',
            'Returned500',
            'NullResponse',
            'MalformedJson'
        )

        foreach ($case in $datasetCases) {
            foreach ($outcome in $outcomes) {
                $script:ArmMatrixOutcome = $outcome
                function global:Invoke-AzRestMethod {
                    [CmdletBinding()]
                    param([string]$Path, [string]$Method)
                    $null = $Path, $Method
                    switch ($script:ArmMatrixOutcome) {
                        'Success200' {
                            return [pscustomobject]@{
                                StatusCode = 200
                                Content = '{"value":[{"id":"child-one","name":"child-one","properties":{"usageDate":"2026-08-01"}}]}'
                            }
                        }
                        'Empty200' { return [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' } }
                        'Returned404' { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"NotFound"}}' } }
                        'Returned500' { return [pscustomobject]@{ StatusCode = 500; Content = '{"error":{"code":"ServerError"}}' } }
                        'Thrown404Data' {
                            $exception = [System.InvalidOperationException]::new('request failed')
                            $exception.Data['StatusCode'] = 404
                            throw $exception
                        }
                        'Thrown404Response' {
                            $exception = [System.InvalidOperationException]::new('request failed')
                            $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 404 })
                            throw $exception
                        }
                        'Thrown403' { throw [System.InvalidOperationException]::new('HTTP status code 403 Forbidden') }
                        'Thrown429' { throw [System.InvalidOperationException]::new('ARM HTTP 429 Too Many Requests') }
                        'NullResponse' { return $null }
                        'MalformedJson' { return [pscustomobject]@{ StatusCode = 200; Content = '{not-json' } }
                    }
                }

                $warnings = @()
                $health = [System.Collections.Generic.List[object]]::new()
                $rows = @(Get-ScoutArmChildResource -Resources @($case.Parent) -Dataset $case.Dataset `
                        -CollectionHealth $health -WarningVariable warnings)
                $label = "$($case.Dataset)/$outcome"

                if ($case.Dataset -eq 'SearchIndexes') {
                    @($rows).Count | Should -Be 0 -Because "$label has no ARM endpoint"
                    @($warnings).Count | Should -Be 0 -Because "$label is an explicit coverage boundary"
                    @($health).Count | Should -Be 1 -Because "$label must stay visibly not assessed"
                    $health[0].Status | Should -Be 'NotAssessed'
                }
                elseif ($outcome -eq 'Success200') {
                    @($rows).Count | Should -BeGreaterThan 0 -Because "$label must retain successful rows"
                    @($warnings).Count | Should -Be 0 -Because "$label is successful"
                    @($health).Count | Should -Be 0 -Because "$label is successful"
                }
                elseif ($outcome -eq 'Empty200') {
                    @($rows).Count | Should -Be 0 -Because "$label is a valid empty collection"
                    @($warnings).Count | Should -Be 0 -Because "$label is a valid empty collection"
                    @($health).Count | Should -Be 0 -Because "$label is a valid empty collection"
                }
                elseif ($case.NotFoundIsEmpty -and $outcome -in @('Returned404', 'Thrown404Data', 'Thrown404Response')) {
                    @($rows).Count | Should -Be 0 -Because "$label is an expected absent singleton"
                    @($warnings).Count | Should -Be 0 -Because "$label is an expected absent singleton"
                    @($health).Count | Should -Be 0 -Because "$label is an expected absent singleton"
                }
                else {
                    @($rows).Count | Should -Be 0 -Because "$label did not return usable evidence"
                    @($warnings).Count | Should -BeGreaterThan 0 -Because "$label must remain visible"
                    @($health).Count | Should -Be 1 -Because "$label must mark exactly one owning dataset unavailable"
                    $health[0].Dataset | Should -Be $case.Dataset -Because $label
                    $health[0].ResourceTypes | Should -Be @("AZSC/ARMChild/$($case.Dataset)") -Because $label
                }
            }
        }
    }

    It 'never reads inside a Key Vault: no data-plane token, no vault.azure.net request, no Key Vault content datasets (AB#9300)' {
        # The dataset names are gone from the public contract, so asking for them is a parameter
        # validation error rather than a silent no-op.
        $declaredDatasets = @(
            (Get-Command Get-ScoutArmChildResource).Parameters['Dataset'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object ValidValues
        )
        $declaredDatasets | Should -Not -Contain 'KeyVaultSecrets'
        $declaredDatasets | Should -Not -Contain 'KeyVaultKeys'
        { Get-ScoutArmChildResource -Resources @() -Dataset KeyVaultSecrets } | Should -Throw
        { Get-ScoutArmChildResource -Resources @() -Dataset KeyVaultKeys } | Should -Throw

        # Record every token request and every direct web request while sweeping ALL datasets
        # with a Key Vault in the parent set.
        $script:kvGuardTokenResources = [System.Collections.Generic.List[string]]::new()
        $script:kvGuardWebRequests = [System.Collections.Generic.List[string]]::new()
        function global:Get-AzAccessToken {
            param(
                [string]$ResourceUrl,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Rest
            $script:kvGuardTokenResources.Add([string]$ResourceUrl)
            [pscustomobject]@{ Token = [securestring]::new() }
        }
        function global:Invoke-WebRequest {
            [CmdletBinding()]
            param(
                [string]$Uri,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Rest
            $script:kvGuardWebRequests.Add($Uri)
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' }
        }

        $vault = Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv-guard' `
            -Properties @{ vaultUri = 'https://kv-guard.vault.azure.net/' }
        $rows = @(Get-ScoutArmChildResource -Resources (@($vault) + $script:Parents) -WarningAction SilentlyContinue)

        @($script:kvGuardTokenResources | Where-Object { $_ -match 'vault' }).Count | Should -Be 0 -Because 'no Key Vault resource token may be requested (the Log Analytics token for Sentinel ingestion is unrelated)'
        @($script:kvGuardWebRequests | Where-Object { $_ -match 'vault' }).Count | Should -Be 0 -Because 'no Key Vault data-plane web request may be made'
        ($script:ArmCalls -join "`n") | Should -Not -Match 'vault\.azure\.net'
        @($rows | Where-Object { $_.TYPE -match 'KeyVault(Secrets|Keys)' }).Count | Should -Be 0

        # The vault itself is still inventoried through the ARM control plane (diagnostic settings).
        @($script:ArmCalls | Where-Object { $_ -like "$($vault.id)/providers/Microsoft.Insights/diagnosticSettings*" }).Count |
            Should -BeGreaterThan 0

        # Nothing under src/ may name the Key Vault data-plane endpoint or its token resource.
        $sourceText = (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'src') -Recurse -Filter '*.ps1' -File |
                ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        $sourceText | Should -Not -Match 'vault\.azure\.net'
        $sourceText | Should -Not -Match 'AzureKeyVaultServiceEndpointResourceId'
    }

    It 'skips unsupported storage services without warning or failed health' {
        $parents = @(
            Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'blob-only' -Kind 'BlobStorage'
            Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'file-only' -Kind 'FileStorage'
        )
        $health = [System.Collections.Generic.List[object]]::new()
        $warnings = @()

        $null = Get-ScoutArmChildResource -Resources $parents `
            -Dataset @('StorageFileShares', 'StorageQueues', 'StorageTables') `
            -CollectionHealth $health -WarningVariable warnings

        $script:ArmCalls.Count | Should -Be 1 -Because 'only FileStorage supports the requested file service'
        $script:ArmCalls[0] | Should -Match 'file-only/fileServices/default/shares'
        @($warnings).Count | Should -Be 0
        @($health).Count | Should -Be 0
    }

    It 'attributes every nested remote-operation failure to its public owning dataset' {
        $ml = Get-TestParent -Type 'microsoft.machinelearningservices/workspaces' -Name 'ml' -Kind 'Default'
        $nestedCases = @(
            @{ Dataset = 'MLDatasets'; NestedPath = '/versions\?'; Operation = 'MLDatasets.LatestVersion'; ExpectedRows = 1 }
            @{ Dataset = 'MLModels'; NestedPath = '/versions\?'; Operation = 'MLModels.LatestVersion'; ExpectedRows = 1 }
            @{ Dataset = 'MLEndpoints'; NestedPath = '/deployments\?'; Operation = 'MLEndpoints.Deployments'; ExpectedRows = 2 }
        )

        foreach ($case in $nestedCases) {
            $script:ArmNestedFailurePath = $case.NestedPath
            function global:Invoke-AzRestMethod {
                [CmdletBinding()]
                param([string]$Path, [string]$Method)
                $null = $Method
                if ($Path -match $script:ArmNestedFailurePath) { throw 'HTTP status 403' }
                [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"child-one","name":"child-one","properties":{}}]}' }
            }

            $health = [System.Collections.Generic.List[object]]::new()
            $rows = @(Get-ScoutArmChildResource -Resources @($ml) -Dataset $case.Dataset `
                    -CollectionHealth $health -WarningAction SilentlyContinue)

            @($rows).Count | Should -Be $case.ExpectedRows -Because "$($case.Dataset) base rows remain usable"
            @($health).Count | Should -Be 1 -Because "$($case.Dataset) health is deduplicated to its owner"
            $health[0].Dataset | Should -Be $case.Dataset
            $health[0].Operation | Should -Be $case.Operation
            $health[0].ResourceTypes | Should -Be @("AZSC/ARMChild/$($case.Dataset)")
        }
    }
}

Describe 'Get-ScoutArmChildResource - per-resource settings (AB#9300 phase 4, batch 2)' {
    BeforeAll {
        # Each marker is planted in a property the allow-list must NOT carry. If one reaches a row,
        # a source operation or a health record, the projection leaked.
        $script:Sentinels = @(
            'SENTINEL-KEY-001', 'SENTINEL-SUBID-002', 'SENTINEL-STORAGE-003', 'SENTINEL-PARTNER-004',
            'SENTINEL-APPSETTING-005', 'SENTINEL-CONN-006', 'SENTINEL-PATH-007', 'SENTINEL-NAMESPACE-008',
            'SENTINEL-ALIAS-009', 'SENTINEL-NICK-010', 'SENTINEL-LINKED-011', 'SENTINEL-ARGS-012',
            'SENTINEL-ORIGIN-013', 'SENTINEL-DOC-014', 'SENTINEL-DB-015', 'SENTINEL-IPRULE-016'
        )

        function Get-Batch2Payload {
            param([string]$Path)
            $trimmed = ($Path -split '\?')[0]
            switch -Regex ($trimmed) {
                '/blobServices/default$' {
                    return @{
                        id = $trimmed; name = 'default'; type = 'Microsoft.Storage/storageAccounts/blobServices'
                        sku = @{ name = 'Standard_LRS' }
                        properties = @{
                            deleteRetentionPolicy = @{ enabled = $true; days = 14; allowPermanentDelete = $false }
                            containerDeleteRetentionPolicy = @{ enabled = $true; days = 7 }
                            isVersioningEnabled = $true
                            changeFeed = @{ enabled = $false; retentionInDays = 3 }
                            restorePolicy = @{ enabled = $true; days = 6 }
                            cors = @{ corsRules = @(@{ allowedOrigins = @('https://SENTINEL-ORIGIN-013') }) }
                            staticWebsite = @{ enabled = $true; indexDocument = 'SENTINEL-DOC-014' }
                        }
                    }
                }
                '/fileServices/default$' {
                    return @{
                        id = $trimmed; name = 'default'; type = 'Microsoft.Storage/storageAccounts/fileServices'
                        properties = @{
                            shareDeleteRetentionPolicy = @{ enabled = $true; days = 9 }
                            protocolSettings = @{ smb = @{ versions = 'SMB3.0;SMB3.1.1'; channelEncryption = 'AES-256-GCM'; authenticationMethods = 'Kerberos' } }
                            cors = @{ corsRules = @(@{ allowedOrigins = @('https://SENTINEL-ORIGIN-013') }) }
                        }
                    }
                }
                '/auditingSettings/default$' {
                    return @{
                        id = $trimmed; name = 'default'; type = 'Microsoft.Sql/servers/auditingSettings'
                        properties = @{
                            state = 'Enabled'; isAzureMonitorTargetEnabled = $true; retentionDays = 90
                            storageAccountAccessKey = 'SENTINEL-KEY-001'
                            storageAccountSubscriptionId = 'SENTINEL-SUBID-002'
                            storageEndpoint = 'https://SENTINEL-STORAGE-003.blob.core.windows.net'
                        }
                    }
                }
                '/failoverGroups$' {
                    return @{ value = @(
                            @{
                                id = "$trimmed/fg-one"; name = 'fg-one'; type = 'Microsoft.Sql/servers/failoverGroups'
                                properties = @{
                                    readWriteEndpoint = @{ failoverPolicy = 'Automatic'; failoverWithDataLossGracePeriodMinutes = 60 }
                                    readOnlyEndpoint = @{ failoverPolicy = 'Disabled' }
                                    replicationRole = 'Primary'; replicationState = 'CATCH_UP'
                                    partnerServers = @(@{ id = '/subscriptions/x/resourceGroups/y/providers/Microsoft.Sql/servers/SENTINEL-PARTNER-004'; location = 'westus'; replicationRole = 'Secondary' })
                                    databases = @('/subscriptions/x/resourceGroups/y/providers/Microsoft.Sql/servers/s/databases/SENTINEL-DB-015', '/subscriptions/x/resourceGroups/y/providers/Microsoft.Sql/servers/s/databases/other')
                                }
                            }
                            @{
                                id = "$trimmed/fg-two"; name = 'fg-two'; type = 'Microsoft.Sql/servers/failoverGroups'
                                properties = @{ readWriteEndpoint = @{ failoverPolicy = 'Manual' }; replicationRole = 'Secondary' }
                            }
                        ) }
                }
                '/config/web$' {
                    return @{
                        id = $trimmed; name = 'web'; type = 'Microsoft.Web/sites/config'
                        properties = @{
                            ftpsState = 'FtpsOnly'; alwaysOn = $true; remoteDebuggingEnabled = $false
                            http20Enabled = $true; minTlsVersion = '1.2'; scmMinTlsVersion = '1.2'
                            healthCheckPath = '/SENTINEL-PATH-007'
                            appSettings = @(@{ name = 'SECRET_NAME'; value = 'SENTINEL-APPSETTING-005' })
                            connectionStrings = @(@{ name = 'db'; connectionString = 'SENTINEL-CONN-006'; type = 'SQLAzure' })
                            ipSecurityRestrictions = @(@{ ip_address = 'SENTINEL-IPRULE-016/32'; action = 'Allow' })
                        }
                    }
                }
                '/basicPublishingCredentialsPolicies/(ftp|scm)$' {
                    return @{ id = $trimmed; name = 'webapp/' + $Matches[1]; type = 'Microsoft.Web/sites/basicPublishingCredentialsPolicies'; properties = @{ allow = ($Matches[1] -eq 'scm') } }
                }
                '/disasterRecoveryConfigs$' {
                    return @{ value = @(@{
                                id = "$trimmed/alias-one"; name = 'alias-one'; type = 'Microsoft.EventHub/namespaces/disasterrecoveryconfigs'
                                properties = @{
                                    provisioningState = 'Succeeded'; role = 'Primary'
                                    partnerNamespace = '/subscriptions/x/resourceGroups/y/providers/Microsoft.EventHub/namespaces/SENTINEL-NAMESPACE-008'
                                    alternateName = 'SENTINEL-ALIAS-009'
                                }
                            }) }
                }
                '/databases$' {
                    return @{ value = @(@{
                                id = "$trimmed/default"; name = 'default'; type = 'Microsoft.Cache/redisEnterprise/databases'
                                properties = @{
                                    accessKeysAuthentication = 'Disabled'; clientProtocol = 'Encrypted'; port = 10000
                                    persistence = @{ aofEnabled = $true; aofFrequency = '1s'; rdbEnabled = $false }
                                    geoReplication = @{
                                        groupNickname = 'SENTINEL-NICK-010'
                                        linkedDatabases = @(@{ id = '/subscriptions/x/resourceGroups/y/providers/Microsoft.Cache/redisEnterprise/r/databases/SENTINEL-LINKED-011' }, @{ id = '/x/SENTINEL-LINKED-011-b' })
                                    }
                                    modules = @(@{ name = 'RedisJSON'; args = 'SENTINEL-ARGS-012' })
                                }
                            }) }
                }
                '/diagnosticSettings$' {
                    return @{ value = @(@{ id = "$trimmed/toWorkspace"; name = 'toWorkspace'; type = 'Microsoft.Insights/diagnosticSettings'; properties = @{ logs = @() } }) }
                }
                default { return @{ value = @() } }
            }
        }

        function Set-Batch2Stub {
            $script:ArmCalls = [System.Collections.Generic.List[string]]::new()
            function global:Invoke-AzRestMethod {
                param([string]$Path, [string]$Uri, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
                $null = $Method, $Rest
                $request = if ($Uri) { $Uri } else { $Path }
                $script:ArmCalls.Add($request)
                [pscustomobject]@{ StatusCode = 200; Content = (Get-Batch2Payload -Path $request | ConvertTo-Json -Depth 12 -Compress) }
            }
        }

        $script:Batch2Datasets = @(
            'StorageBlobServiceProperties', 'StorageFileServiceProperties', 'SqlServerAuditing', 'SqlFailoverGroups',
            'WebAppConfig', 'WebAppBasicAuth', 'EventHubGeoDr', 'RedisEnterpriseDatabases'
        )
        $script:Batch2Parents = @(
            Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'st-v2' -Kind 'StorageV2'
            Get-TestParent -Type 'microsoft.sql/servers' -Name 'sql-one'
            Get-TestParent -Type 'microsoft.web/sites' -Name 'web-one'
            Get-TestParent -Type 'microsoft.eventhub/namespaces' -Name 'eh-one'
            Get-TestParent -Type 'microsoft.cache/redisenterprise' -Name 'redis-one'
        )
    }

    BeforeEach { Set-Batch2Stub }

    It 'declares the eight datasets, after the existing ones, and sweeps them under All' {
        $declared = @(
            (Get-Command Get-ScoutArmChildResource).Parameters['Dataset'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object ValidValues | Where-Object { $_ -ne 'All' }
        )
        @($script:Batch2Datasets | Where-Object { $declared -notcontains $_ }) | Should -BeNullOrEmpty
        # The eight sit after the existing datasets and before the thirteen Azure VMware Solution
        # datasets AB#9300 added in 3.18.19.
        @($declared | Select-Object -SkipLast 13 | Select-Object -Last 8) | Should -Be $script:Batch2Datasets
        @($declared | Select-Object -Last 13 | Select-Object -First 1) | Should -Be @('AvsClusters')

        $rows = @(Get-ScoutArmChildResource -Resources $script:Batch2Parents)
        $types = @($rows.TYPE | Select-Object -Unique)
        foreach ($dataset in $script:Batch2Datasets) { $types | Should -Contain "AZSC/ARMChild/$dataset" }
    }

    It 'issues exactly one GET per parent (two per web app for basic auth) at the documented path and API version' {
        $null = Get-ScoutArmChildResource -Resources $script:Batch2Parents -Dataset $script:Batch2Datasets
        $id = { param($name) @($script:Batch2Parents | Where-Object name -eq $name)[0].id }
        $script:ArmCalls | Should -Be @(
            "$(& $id 'st-v2')/blobServices/default?api-version=2023-05-01"
            "$(& $id 'st-v2')/fileServices/default?api-version=2023-05-01"
            "$(& $id 'sql-one')/auditingSettings/default?api-version=2021-11-01"
            "$(& $id 'sql-one')/failoverGroups?api-version=2021-11-01"
            "$(& $id 'web-one')/config/web?api-version=2022-09-01"
            "$(& $id 'web-one')/basicPublishingCredentialsPolicies/ftp?api-version=2022-09-01"
            "$(& $id 'web-one')/basicPublishingCredentialsPolicies/scm?api-version=2022-09-01"
            "$(& $id 'eh-one')/disasterRecoveryConfigs?api-version=2021-11-01"
            "$(& $id 'redis-one')/databases?api-version=2025-04-01"
        )
    }

    It 'never lets a secret-bearing neighbour of an allow-listed setting into a row, an operation or a health record' {
        $health = [System.Collections.Generic.List[object]]::new()
        $operations = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources $script:Batch2Parents -Dataset $script:Batch2Datasets `
                -CollectionHealth $health -SourceOperations $operations)
        $rows.Count | Should -BeGreaterThan 8

        $everything = (@($rows) + @($operations) + @($health) | ConvertTo-Json -Depth 12)
        foreach ($sentinel in $script:Sentinels) {
            $everything | Should -Not -Match ([regex]::Escape($sentinel)) -Because "$sentinel sits in a property the allow-list excludes"
        }
        # Positive control: the planted payload really was read, so the absence above is the
        # projection's doing and not an empty fixture.
        $everything | Should -Match 'FtpsOnly'
        $everything | Should -Match 'RedisJSON|persistence'
    }

    It 'keeps only the allow-listed settings on each row' {
        $rows = @(Get-ScoutArmChildResource -Resources $script:Batch2Parents -Dataset $script:Batch2Datasets)
        $byType = { param($dataset) @($rows | Where-Object TYPE -eq "AZSC/ARMChild/$dataset") }

        $blob = (& $byType 'StorageBlobServiceProperties')[0]
        $blob.properties.deleteRetentionPolicy.enabled | Should -BeTrue
        $blob.properties.deleteRetentionPolicy.days | Should -Be 14
        $blob.properties.containerDeleteRetentionPolicy.days | Should -Be 7
        $blob.properties.isVersioningEnabled | Should -BeTrue
        $blob.properties.restorePolicy.enabled | Should -BeTrue
        @($blob.properties.PSObject.Properties.Name | Sort-Object) | Should -Be @('changeFeed', 'containerDeleteRetentionPolicy', 'deleteRetentionPolicy', 'isVersioningEnabled', 'restorePolicy')

        $file = (& $byType 'StorageFileServiceProperties')[0]
        $file.properties.protocolSettings.smb.versions | Should -Be 'SMB3.0;SMB3.1.1'
        @($file.properties.PSObject.Properties.Name | Sort-Object) | Should -Be @('protocolSettings', 'shareDeleteRetentionPolicy')

        $audit = (& $byType 'SqlServerAuditing')[0]
        @($audit.properties.PSObject.Properties.Name | Sort-Object) | Should -Be @('isAzureMonitorTargetEnabled', 'state')

        $groups = & $byType 'SqlFailoverGroups'
        $groups.Count | Should -Be 2
        $groups[0].properties.partnerServerCount | Should -Be 1
        $groups[0].properties.databaseCount | Should -Be 2
        $groups[1].properties.partnerServerCount | Should -Be 0 -Because 'a count of an absent array is 0, not null'
        $groups[0].properties.PSObject.Properties['partnerServers'] | Should -BeNullOrEmpty

        $config = (& $byType 'WebAppConfig')[0]
        $config.properties.healthCheckPathSet | Should -BeTrue
        $config.properties.PSObject.Properties['healthCheckPath'] | Should -BeNullOrEmpty
        foreach ($forbidden in 'appSettings', 'connectionStrings', 'ipSecurityRestrictions') {
            $config.properties.PSObject.Properties[$forbidden] | Should -BeNullOrEmpty
        }

        $geoDr = (& $byType 'EventHubGeoDr')[0]
        @($geoDr.properties.PSObject.Properties.Name | Sort-Object) | Should -Be @('provisioningState', 'role')

        $redis = (& $byType 'RedisEnterpriseDatabases')[0]
        $redis.properties.accessKeysAuthentication | Should -Be 'Disabled'
        $redis.properties.persistence.aofEnabled | Should -BeTrue
        $redis.properties.geoReplication.linkedDatabaseCount | Should -Be 2
        $redis.properties.geoReplication.PSObject.Properties['linkedDatabases'] | Should -BeNullOrEmpty
        $redis.properties.geoReplication.PSObject.Properties['groupNickname'] | Should -BeNullOrEmpty
    }

    It 'stamps the policy name on each basic-auth row, one GET per policy' {
        $rows = @(Get-ScoutArmChildResource -Resources $script:Batch2Parents -Dataset WebAppBasicAuth)
        $rows.Count | Should -Be 2
        @($rows.properties.policy) | Should -Be @('ftp', 'scm')
        @($rows.properties.allow) | Should -Be @($false, $true)
    }

    It 'records the parent id on every source operation of the new datasets' {
        $operations = [System.Collections.Generic.List[object]]::new()
        $null = Get-ScoutArmChildResource -Resources $script:Batch2Parents -Dataset $script:Batch2Datasets -SourceOperations $operations
        $operations.Count | Should -Be 9
        foreach ($operation in $operations) {
            $operation.PSObject.Properties['ParentId'] | Should -Not -BeNullOrEmpty -Because "$($operation.Dataset) must say which parent it covered"
            $operation.Uri | Should -BeLike "$($operation.ParentId)/*"
            $operation.Status | Should -Be 'Success'
        }
    }

    It 'does not ask a FileStorage account about blobs or a BlobStorage account about files (FeatureNotSupportedForAccount, seen live)' {
        $parents = @(
            Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'file-only' -Kind 'FileStorage'
            Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'blob-only' -Kind 'BlockBlobStorage'
        )
        $null = Get-ScoutArmChildResource -Resources $parents -Dataset StorageBlobServiceProperties, StorageFileServiceProperties
        $script:ArmCalls.Count | Should -Be 2
        $script:ArmCalls | Should -Contain "$($parents[0].id)/fileServices/default?api-version=2023-05-01"
        $script:ArmCalls | Should -Contain "$($parents[1].id)/blobServices/default?api-version=2023-05-01"
    }

    It 'skips Basic-tier Event Hubs namespaces (no geo-DR there) but asks Standard and SKU-less ones' {
        $parents = @(
            [pscustomobject]@{ id = '/subscriptions/s/resourceGroups/r/providers/Microsoft.EventHub/namespaces/basic'; type = 'microsoft.eventhub/namespaces'; name = 'basic'; sku = [pscustomobject]@{ name = 'Basic'; tier = 'Basic' } }
            [pscustomobject]@{ id = '/subscriptions/s/resourceGroups/r/providers/Microsoft.EventHub/namespaces/standard'; type = 'microsoft.eventhub/namespaces'; name = 'standard'; sku = [pscustomobject]@{ name = 'Standard' } }
            [pscustomobject]@{ id = '/subscriptions/s/resourceGroups/r/providers/Microsoft.EventHub/namespaces/nosku'; type = 'microsoft.eventhub/namespaces'; name = 'nosku' }
        )
        $null = Get-ScoutArmChildResource -Resources $parents -Dataset EventHubGeoDr
        $script:ArmCalls.Count | Should -Be 2
        ($script:ArmCalls -join "`n") | Should -Not -Match '/namespaces/basic/'
        ($script:ArmCalls -join "`n") | Should -Match '/namespaces/standard/'
        ($script:ArmCalls -join "`n") | Should -Match '/namespaces/nosku/'
    }

    It 'records an answered-but-absent singleton as Empty with its parent id, without a row or a warning' {
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Path, $Method, $Rest
            [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound"}}' }
        }
        $operations = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources @($script:Batch2Parents[0]) -Dataset StorageBlobServiceProperties `
                -SourceOperations $operations -WarningVariable warned -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 0
        @($warned).Count | Should -Be 0
        $operations[0].Status | Should -Be 'Empty'
        $operations[0].ParentId | Should -Be $script:Batch2Parents[0].id
    }

    It 'sweeps diagnostic settings on the fourteen added parent types and still not on virtual machines or disks' {
        $added = @(
            'microsoft.machinelearningservices/workspaces', 'microsoft.search/searchservices',
            'microsoft.databricks/workspaces', 'microsoft.sql/managedinstances', 'microsoft.cache/redis',
            'microsoft.cache/redisenterprise', 'microsoft.network/loadbalancers',
            'microsoft.network/publicipaddresses', 'microsoft.network/virtualnetworkgateways',
            'microsoft.network/trafficmanagerprofiles', 'microsoft.eventgrid/topics',
            'microsoft.insights/components', 'microsoft.desktopvirtualization/hostpools',
            'microsoft.desktopvirtualization/workspaces'
        )
        $parents = @($added | ForEach-Object { Get-TestParent -Type $_ -Name 'res' })
        $parents += Get-TestParent -Type 'microsoft.compute/virtualmachines' -Name 'vm'
        $parents += Get-TestParent -Type 'microsoft.compute/disks' -Name 'disk'
        $parents += Get-TestParent -Type 'microsoft.network/networkinterfaces' -Name 'nic'

        $rows = @(Get-ScoutArmChildResource -Resources $parents -Dataset ResourceDiagnosticSettings)

        $rows.Count | Should -Be 14
        @($rows.PARENTTYPE | Sort-Object) | Should -Be @($added | Sort-Object)
        ($script:ArmCalls -join "`n") | Should -Not -Match 'virtualmachines|/disks/|networkinterfaces'
        @($script:ArmCalls | Where-Object { $_ -match 'api-version=2021-05-01-preview$' }).Count | Should -Be 14
    }
}
}
