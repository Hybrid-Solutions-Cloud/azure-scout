#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutResourceCompleteness.ps1')

    function New-TestResource {
        param(
            [string]$Name,
            [string]$Type,
            $Properties,
            $Tags = $null
        )
        [pscustomobject]@{
            id             = "/subscriptions/sub-1/resourceGroups/rg-1/providers/$Type/$Name"
            name           = $Name
            type           = $Type
            tenantId       = 'tenant-1'
            subscriptionId = 'sub-1'
            resourceGroup  = 'rg-1'
            location       = 'eastus'
            properties     = $Properties
            tags           = $Tags
        }
    }
}

Describe 'Universal discovery completeness index (AB#7366)' {
    It 'retains an unsupported resource with its full Resource Graph payload and tags' {
        $properties = [pscustomobject]@{ customSetting = 'kept'; nested = [pscustomobject]@{ enabled = $true } }
        $resource = New-TestResource -Name 'future-1' -Type 'contoso.future/widgets' -Properties $properties -Tags ([pscustomobject]@{ Environment = 'Test' })

        $result = Get-ScoutResourceCompleteness -Resources @($resource) -Collectors @()

        $result.Summary.Resources | Should -Be 1
        $result.Resources[0].DetailStatus | Should -Be 'GenericOnly'
        $result.Resources[0].Properties.customSetting | Should -Be 'kept'
        $result.Resources[0].Properties.nested.enabled | Should -BeTrue
        $result.Resources[0].Tags.Environment | Should -Be 'Test'
    }

    It 'marks a resource detailed when a specialized collector declares its type' {
        $resource = New-TestResource -Name 'vnet-1' -Type 'microsoft.network/virtualnetworks' -Properties ([pscustomobject]@{})
        $collector = [pscustomobject]@{ FolderCategory = 'Networking'; Name = 'VirtualNetworks'; ResourceTypes = @('microsoft.network/virtualnetworks') }

        $result = Get-ScoutResourceCompleteness -Resources @($resource) -Collectors @($collector)

        $result.Resources[0].DetailStatus | Should -Be 'Detailed'
        $result.Resources[0].SpecializedCollectors | Should -Contain 'Networking/VirtualNetworks'
    }

    It 'keeps the parent visible and marks detail partial when collection health reports a failure' {
        $resource = New-TestResource -Name 'store-1' -Type 'microsoft.storage/storageaccounts' -Properties ([pscustomobject]@{ publicNetworkAccess = 'Enabled' })
        $collector = [pscustomobject]@{ FolderCategory = 'Storage'; Name = 'StorageAccounts'; ResourceTypes = @('microsoft.storage/storageaccounts') }
        $health = [pscustomobject]@{
            Collectors   = @('Storage/StorageAccounts')
            ResourceTypes = @('microsoft.storage/storageaccounts')
            Reason       = 'Provider detail request returned 403.'
        }

        $result = Get-ScoutResourceCompleteness -Resources @($resource) -Collectors @($collector) -CollectionHealth @($health)

        $result.Resources.Count | Should -Be 1
        $result.Resources[0].DetailStatus | Should -Be 'Partial'
        $result.Resources[0].DetailReasons | Should -Contain 'Provider detail request returned 403.'
    }

    It 'normalizes mixed public and private exposure from direct control-plane evidence' {
        $privateEndpointId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/privateEndpoints/pe-1'
        $resource = New-TestResource -Name 'store-1' -Type 'microsoft.storage/storageaccounts' -Properties ([pscustomobject]@{
                publicNetworkAccess = 'Enabled'
                privateEndpointConnections = @([pscustomobject]@{ properties = [pscustomobject]@{ privateEndpoint = [pscustomobject]@{ id = $privateEndpointId } } })
            })

        $result = Get-ScoutResourceCompleteness -Resources @($resource) -Collectors @()

        $result.Resources[0].Exposure | Should -Be 'Mixed'
        $result.Resources[0].ExposureEvidence | Should -Contain 'publicNetworkAccess=Enabled'
        $result.Resources[0].ExposureEvidence | Should -Contain 'privateEndpoints=1'
    }

    It 'extracts generic ARM references and classifies known network relationships' {
        $vnetId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/virtualNetworks/vnet-2'
        $nsgId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/networkSecurityGroups/nsg-1'
        $resource = New-TestResource -Name 'vnet-1' -Type 'microsoft.network/virtualnetworks' -Properties ([pscustomobject]@{
                virtualNetworkPeerings = @([pscustomobject]@{ properties = [pscustomobject]@{ remoteVirtualNetwork = [pscustomobject]@{ id = $vnetId } } })
                networkSecurityGroup = [pscustomobject]@{ id = $nsgId }
            })

        $result = Get-ScoutResourceCompleteness -Resources @($resource) -Collectors @()

        $result.Relationships.RelationshipType | Should -Contain 'VNetPeering'
        $result.Relationships.RelationshipType | Should -Contain 'NetworkSecurityGroup'
    }

    It 'deduplicates repeated Resource Graph rows by ARM id' {
        $resource = New-TestResource -Name 'same' -Type 'contoso.future/widgets' -Properties ([pscustomobject]@{ value = 1 })
        $duplicate = $resource | Select-Object *

        $result = Get-ScoutResourceCompleteness -Resources @($resource, $duplicate) -Collectors @()

        $result.Summary.Resources | Should -Be 1
    }

    It 'attaches synthetic provider enrichment to the real resource instead of double-counting it' {
        $resource = New-TestResource -Name 'nic-1' -Type 'microsoft.network/networkinterfaces' -Properties ([pscustomobject]@{ enableIPForwarding = $false })
        $enrichment = [pscustomobject]@{
            id = $resource.id
            type = 'AZSC/Operational/NetworkInterface'
            properties = [pscustomobject]@{ EffectiveRouteTable = [pscustomobject]@{ value = @([pscustomobject]@{ nextHopType = 'Internet' }) } }
        }

        $result = Get-ScoutResourceCompleteness -Resources @($resource, $enrichment) -Collectors @()

        $result.Summary.Resources | Should -Be 1
        $result.Resources[0].Enrichment.Type | Should -Contain 'AZSC/Operational/NetworkInterface'
        $result.Resources[0].Enrichment[0].Properties.EffectiveRouteTable.value[0].nextHopType | Should -Be 'Internet'
    }

    It 'loads the shipped collector catalog when invoked standalone' {
        Remove-Item Function:\Get-ScoutCollector -ErrorAction SilentlyContinue
        $resource = New-TestResource -Name 'store-1' -Type 'microsoft.storage/storageaccounts' `
            -Properties ([pscustomobject]@{ publicNetworkAccess = 'Enabled' })

        $result = Get-ScoutResourceCompleteness -Resources @($resource) `
            -DefinitionRoot (Join-Path $script:RepoRoot 'manifests/collectors')

        $result.Resources[0].DetailStatus | Should -Be 'Detailed'
        @($result.Resources[0].SpecializedCollectors).Count | Should -BeGreaterThan 0
    }

    It 'redacts secret values while retaining non-secret configuration and secret presence' {
        $resource = New-TestResource -Name 'connection-1' -Type 'microsoft.network/connections' `
            -Properties ([pscustomobject]@{
                connectionType = 'IPsec'
                sharedKey = 'do-not-ship-this-psk'
                nested = [pscustomobject]@{ clientSecret = 'do-not-ship-this-client-secret' }
                setting = [pscustomobject]@{ name = 'ApiToken'; value = 'do-not-ship-this-token' }
                parameter = [pscustomobject]@{ type = 'SecureString'; defaultValue = 'do-not-ship-this-password' }
            })

        $result = Get-ScoutResourceCompleteness -Resources @($resource) -Collectors @()
        $json = $result | ConvertTo-Json -Depth 30

        $result.Resources[0].Properties.connectionType | Should -Be 'IPsec'
        $result.Resources[0].Properties.sharedKey | Should -Be '[REDACTED]'
        $result.Resources[0].Properties.nested.clientSecret | Should -Be '[REDACTED]'
        $result.Resources[0].Properties.setting.value | Should -Be '[REDACTED]'
        $result.Resources[0].Properties.parameter.defaultValue | Should -Be '[REDACTED]'
        $json | Should -Not -Match 'do-not-ship-this'
    }
}
