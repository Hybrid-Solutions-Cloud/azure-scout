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

    function Get-KeyVaultResponseStub {
        function global:Get-AzContext {
            [pscustomobject]@{ Environment = [pscustomobject]@{ Name = 'AzureCloud' } }
        }
        function global:Get-AzEnvironment {
            param([string]$Name)
            $null = $Name
            [pscustomobject]@{
                AzureKeyVaultDnsSuffix = 'vault.azure.net'
                AzureKeyVaultServiceEndpointResourceId = 'https://vault.azure.net'
            }
        }
        function global:Get-AzAccessToken {
            param(
                [string]$ResourceUrl,
                [switch]$AsSecureString,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $ResourceUrl, $AsSecureString, $Rest
            [pscustomobject]@{ Token = [securestring]::new() }
        }
        function global:Invoke-WebRequest {
            [CmdletBinding()]
            param(
                [string]$Uri,
                [string]$Method,
                [string]$Authentication,
                [securestring]$Token,
                [switch]$SkipHttpErrorCheck,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Method, $Authentication, $Token, $SkipHttpErrorCheck, $Rest
            Invoke-AzRestMethod -Path $Uri -Method GET
        }
    }

    Get-ArmChildResponseStub
    Get-KeyVaultResponseStub
}

AfterAll {
    foreach ($Name in 'Invoke-AzRestMethod', 'Get-AzContext', 'Get-AzEnvironment', 'Get-AzAccessToken', 'Invoke-WebRequest') {
        Remove-Item -Path "Function:\$Name" -Force -ErrorAction SilentlyContinue
    }
}

BeforeEach {
    Get-ArmChildResponseStub
    Get-KeyVaultResponseStub
}

Describe 'Get-ScoutArmChildResource - supported-dataset contract' {
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
            # AB#6769. The Log Analytics workspace in $script:Parents is one of the twenty parent
            # types the diagnostic-settings sweep is scoped to, so it emits here too. This entry
            # is the canary for that scope: if a type is ever added to
            # $DiagnosticSettingParentTypes that also appears above, this list grows and the run
            # got more expensive.
            'AZSC/ARMChild/ResourceDiagnosticSettings'
            'AZSC/ARMChild/AzureLocalVirtualMachineInstances'
        )
        $Rows.Count | Should -Be 14 -Because 'MLEndpoints emits one online and one batch endpoint, the LA workspace also yields a diagnostic setting, the Arc machine yields one Azure Local VM instance, and Search indexes are data-plane-only'
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
        }
    }

    It 'excludes ML Hub/Project workspaces and non-RemoteApp AVD groups before calling ARM' {
        $null = Get-ScoutArmChildResource -Resources $script:Parents
        ($script:ArmCalls -join "`n") | Should -Not -Match 'ml-hub'
        ($script:ArmCalls -join "`n") | Should -Not -Match 'ml-project'
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

    It 'lists every Key Vault secret metadata page without requesting a secret value (AB#7358)' {
        $vault = Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv-paged' `
            -Properties @{ vaultUri = 'https://kv-paged.vault.azure.net/' }
        $script:keyVaultCalls = [System.Collections.Generic.List[string]]::new()
        $script:keyVaultTokenResource = $null
        function global:Get-AzAccessToken {
            param(
                [string]$ResourceUrl,
                [switch]$AsSecureString,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $AsSecureString, $Rest
            $script:keyVaultTokenResource = $ResourceUrl
            [pscustomobject]@{ Token = [securestring]::new() }
        }
        function global:Invoke-WebRequest {
            [CmdletBinding()]
            param(
                [string]$Uri,
                [string]$Method,
                [string]$Authentication,
                [securestring]$Token,
                [switch]$SkipHttpErrorCheck,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Method, $Authentication, $Token, $SkipHttpErrorCheck, $Rest
            $script:keyVaultCalls.Add($Uri)
            $payload = if ($Uri -eq 'https://kv-paged.vault.azure.net/secrets/next-page') {
                @{ value = @(@{ id = 'https://kv-paged.vault.azure.net/secrets/secret-two'; attributes = @{ enabled = $true } }) }
            }
            else {
                @{
                    value = @(@{ id = 'https://kv-paged.vault.azure.net/secrets/secret-one'; attributes = @{ enabled = $true } })
                    nextLink = 'https://kv-paged.vault.azure.net/secrets/next-page'
                }
            }
            [pscustomobject]@{ StatusCode = 200; Content = ($payload | ConvertTo-Json -Depth 8 -Compress) }
        }

        $rows = @(Get-ScoutArmChildResource -Resources @($vault) -Dataset KeyVaultSecrets)

        $rows.Count | Should -Be 2
        @($rows.name | Sort-Object) | Should -Be @('secret-one', 'secret-two')
        @($rows.id | Sort-Object) | Should -Be @(
            "$($vault.id)/secrets/secret-one"
            "$($vault.id)/secrets/secret-two"
        )
        $rows[0].properties.PSObject.Properties['value'] | Should -BeNullOrEmpty
        $script:keyVaultTokenResource | Should -Be 'https://vault.azure.net'
        $script:keyVaultCalls | Should -Be @(
            'https://kv-paged.vault.azure.net/secrets?api-version=7.4&maxresults=25'
            'https://kv-paged.vault.azure.net/secrets/next-page'
        )
        ($script:keyVaultCalls -join "`n") | Should -Not -Match '/secrets/[^?]+\?api-version='
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
            @{ Dataset = 'KeyVaultSecrets'; Parent = Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv'; NotFoundIsEmpty = $false }
            @{ Dataset = 'KeyVaultKeys'; Parent = Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageBlobContainers'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageFileShares'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageLifecyclePolicies'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $true }
            @{ Dataset = 'StorageQueues'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'StorageTables'; Parent = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage'; NotFoundIsEmpty = $false }
            @{ Dataset = 'BackupInstances'; Parent = Get-TestParent -Type 'microsoft.dataprotection/backupvaults' -Name 'backup'; NotFoundIsEmpty = $false }
            @{ Dataset = 'ResourceDiagnosticSettings'; Parent = Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv'; NotFoundIsEmpty = $false }
            @{ Dataset = 'ReservationUtilization'; Parent = Get-TestParent -Type 'microsoft.capacity/reservationorders/reservations' -Name 'reservation'; NotFoundIsEmpty = $false }
            @{ Dataset = 'AzureLocalVirtualMachineInstances'; Parent = Get-TestParent -Type 'microsoft.hybridcompute/machines' -Name 'arc'; NotFoundIsEmpty = $true }
        )
        $declaredDatasets = @(
            (Get-Command Get-ScoutArmChildResource).Parameters['Dataset'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object ValidValues |
                Where-Object { $_ -ne 'All' }
        )
        @($datasetCases.Dataset) | Should -Be $declaredDatasets -Because 'the matrix must track every shipped dataset'

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
                function global:Invoke-WebRequest {
                    [CmdletBinding()]
                    param(
                        [string]$Uri,
                        [string]$Method,
                        [string]$Authentication,
                        [securestring]$Token,
                        [switch]$SkipHttpErrorCheck
                    )
                    $null = $Method, $Authentication, $Token, $SkipHttpErrorCheck
                    $response = Invoke-AzRestMethod -Path $Uri -Method GET
                    if ($script:ArmMatrixOutcome -eq 'Success200') {
                        $kind = if ($Uri -match '/keys(?:\?|/)') { 'keys' } else { 'secrets' }
                        $identifierName = if ($kind -eq 'keys') { 'kid' } else { 'id' }
                        $item = @{ attributes = @{ enabled = $true } }
                        $item[$identifierName] = "https://kv.vault.azure.net/$kind/item-one"
                        return [pscustomobject]@{
                            StatusCode = 200
                            Content = (@{ value = @($item) } | ConvertTo-Json -Depth 8 -Compress)
                        }
                    }
                    return $response
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

    It 'aggregates Key Vault metadata denials into one warning and one health record per dataset' {
        $vaults = @(
            Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv-one' -Properties @{ vaultUri = 'https://kv-one.vault.azure.net/' }
            Get-TestParent -Type 'microsoft.keyvault/vaults' -Name 'kv-two' -Properties @{ vaultUri = 'https://kv-two.vault.azure.net/' }
        )
        function global:Invoke-WebRequest {
            throw [System.InvalidOperationException]::new('HTTP status code 403 Forbidden')
        }
        $health = [System.Collections.Generic.List[object]]::new()
        $warnings = @()

        $rows = @(Get-ScoutArmChildResource -Resources $vaults -Dataset KeyVaultSecrets `
                -CollectionHealth $health -WarningVariable warnings)

        $rows | Should -BeNullOrEmpty
        @($warnings).Count | Should -Be 1
        $warnings[0].Message | Should -Match '2 vault\(s\) unavailable'
        @($health).Count | Should -Be 1
        $health[0].FailedParents | Should -Be @('kv-one', 'kv-two')
        $health[0].Reason | Should -Match 'Key Vault Reader'
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
}
