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
    Remove-Item -Path Function:\Invoke-AzRestMethod -Force -ErrorAction SilentlyContinue
}

BeforeEach {
    Get-ArmChildResponseStub
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
            'AZSC/ARMChild/SearchIndexes'
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
        $Rows.Count | Should -Be 15 -Because 'MLEndpoints emits one online and one batch endpoint, the LA workspace also yields a diagnostic setting, and the Arc machine yields one Azure Local VM instance'
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
        $Calls | Should -Match '/indexes\?api-version=2023-11-01'
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

        $Rows.TYPE | Should -Be @(
            'AZSC/ARMChild/MLComputes'
            'AZSC/ARMChild/SearchIndexes'
        )
        $script:ArmCalls.Count | Should -Be 2
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

    It 'treats an absent storage lifecycle policy as empty without warning or terminating error' {
        $storage = Get-TestParent -Type 'microsoft.storage/storageaccounts' -Name 'storage-one'
        function global:Invoke-AzRestMethod {
            param(
                [string]$Path,
                [string]$Method,
                [switch]$SkipHttpErrorCheck,
                [Parameter(ValueFromRemainingArguments)]$Rest
            )
            $null = $Path, $Method, $Rest
            $SkipHttpErrorCheck | Should -BeTrue
            [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound"}}' }
        }

        $warnings = @()
        $rows = @(Get-ScoutArmChildResource -Resources @($storage) -Dataset StorageLifecyclePolicies -WarningVariable warnings)

        $rows | Should -BeNullOrEmpty
        @($warnings).Count | Should -Be 0
    }
}
}
