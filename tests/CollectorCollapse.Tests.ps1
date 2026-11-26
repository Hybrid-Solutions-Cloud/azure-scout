#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5543 — collapsing the duplicate inventory/assessment collection passes.

    Inventory and assessment used to each run their own Azure Resource Graph pass over the same
    resource types. `Invoke-Collect -FromInventory` now shapes the assessment's scalars from the
    rows an inventory pass already fetched.

    These tests pin the two things that make that safe:
      1. every projection reproduces the KQL semantics exactly (including the null-vs-zero and
         null-vs-false cases that a naive PowerShell rewrite silently gets wrong), and
      2. supplying -FromInventory does not re-query Azure, except for the one query that
         genuinely cannot be served from inventory rows.

    Pure-logic tests — no Azure connection.
#>

BeforeAll {
    # Invoke-Collect always performs these two non-ARG sweeps. Keep fake
    # subscriptions and tenants inside the test process.
    function Get-ScoutDefenderPlanSweep {
        param([object[]] $Subscriptions)
        $null = $Subscriptions
        return @()
    }

    function Get-ScoutExternalIdentitiesPolicy {
        param([string] $TenantID)
        $null = $TenantID
        return [pscustomobject]@{ Collected = $false }
    }
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/collect/ConvertFrom-ScoutInventory.ps1"

    function New-Resource {
        param([string] $Type, [string] $Name = 'r1', [hashtable] $Properties = @{}, [hashtable] $Extra = @{})
        $obj = [ordered]@{
            id             = "/subscriptions/sub1/resourceGroups/rg1/providers/$Type/$Name"
            name           = $Name
            type           = $Type
            location       = 'eastus'
            resourceGroup  = 'rg1'
            subscriptionId = 'sub1'
            properties     = [pscustomobject] $Properties
        }
        foreach ($k in $Extra.Keys) { $obj[$k] = $Extra[$k] }
        return [pscustomobject] $obj
    }
}

Describe 'ConvertFrom-ScoutInventory — KQL semantics are preserved' {

    It 'reports peeringCount as null when the peerings array is absent (KQL array_length(null) is null, not 0)' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{}
        ) -ResourceContainers @()
        $shaped['virtualNetworks'][0].peeringCount | Should -BeNullOrEmpty
    }

    It 'counts peerings when present' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{
                virtualNetworkPeerings = @(1, 2, 3)
            }
        ) -ResourceContainers @()
        $shaped['virtualNetworks'][0].peeringCount | Should -Be 3
    }

    It 'leaves a missing bool as null rather than false (KQL tobool(null) is null)' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.keyvault/vaults' -Properties @{}
        ) -ResourceContainers @()
        $shaped['keyVaults'][0].softDelete | Should -BeNullOrEmpty
        $shaped['keyVaults'][0].purgeProtection | Should -BeNullOrEmpty
    }

    It 'preserves an explicit false' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.keyvault/vaults' -Properties @{ enableSoftDelete = $false }
        ) -ResourceContainers @()
        $shaped['keyVaults'][0].softDelete | Should -BeExactly $false
    }

    It 'computes subnet utilisation as used / (2^(32-prefix) - 5)' {
        # /24 => 256 - 5 = 251 usable; 2 IP configs => 0.8%
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{
                subnets = @(
                    [pscustomobject]@{
                        name       = 'snet1'
                        properties = [pscustomobject]@{
                            addressPrefix    = '10.0.0.0/24'
                            ipConfigurations = @(1, 2)
                        }
                    }
                )
            }
        ) -ResourceContainers @()
        $shaped['subnets'][0].total | Should -Be 251
        $shaped['subnets'][0].used | Should -Be 2
        $shaped['subnets'][0].ipUtilizationPct | Should -Be 0.8
    }

    It 'keeps only Allow + Inbound NSG rules from an internet-equivalent source' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/networksecuritygroups' -Properties @{
                securityRules = @(
                    [pscustomobject]@{ name = 'open'; properties = [pscustomobject]@{ access = 'Allow'; direction = 'Inbound'; sourceAddressPrefix = '*'; destinationPortRange = '22' } }
                    [pscustomobject]@{ name = 'deny'; properties = [pscustomobject]@{ access = 'Deny'; direction = 'Inbound'; sourceAddressPrefix = '*'; destinationPortRange = '80' } }
                    [pscustomobject]@{ name = 'out'; properties = [pscustomobject]@{ access = 'Allow'; direction = 'Outbound'; sourceAddressPrefix = '*'; destinationPortRange = '443' } }
                    [pscustomobject]@{ name = 'scoped'; properties = [pscustomobject]@{ access = 'Allow'; direction = 'Inbound'; sourceAddressPrefix = '10.0.0.0/8'; destinationPortRange = '3389' } }
                )
            }
        ) -ResourceContainers @()
        $shaped['nsgPublicInbound'].Count | Should -Be 1
        $shaped['nsgPublicInbound'][0].rule | Should -Be 'open'
        $shaped['nsgPublicInbound'][0].port | Should -Be '22'
    }

    It 'splits a private endpoint target id into provider and type, falling back to the manual connection' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.network/privateendpoints' -Properties @{
                manualPrivateLinkServiceConnections = @(
                    [pscustomobject]@{ properties = [pscustomobject]@{ privateLinkServiceId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sa1' } }
                )
            }
        ) -ResourceContainers @()
        $shaped['privateEndpoints'][0].targetProvider | Should -Be 'microsoft.storage'
        $shaped['privateEndpoints'][0].targetType | Should -Be 'storageaccounts'
    }

    It 'marks allPoolsZoned only when every AKS pool has zones' {
        $mixed = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.containerservice/managedclusters' -Properties @{
                agentPoolProfiles = @(
                    [pscustomobject]@{ availabilityZones = @('1', '2') }
                    [pscustomobject]@{ availabilityZones = $null }
                )
            }
        ) -ResourceContainers @()
        $mixed['aksClusters'][0].allPoolsZoned | Should -BeExactly $false

        $allZoned = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.containerservice/managedclusters' -Properties @{
                agentPoolProfiles = @([pscustomobject]@{ availabilityZones = @('1') })
            }
        ) -ResourceContainers @()
        $allZoned['aksClusters'][0].allPoolsZoned | Should -BeExactly $true
    }

    It 'derives zoneRedundant from the zones column and zoneEligible from the region list' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.compute/virtualmachines' -Name 'vm1' -Properties @{ hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2s_v5' } } -Extra @{ zones = @('1') }
            New-Resource -Type 'microsoft.compute/virtualmachines' -Name 'vm2' -Properties @{} -Extra @{ zones = $null; location = 'nowhereland' }
        ) -ResourceContainers @()
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm1').zoneRedundant | Should -BeExactly $true
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm1').zoneEligible | Should -BeExactly $true
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm2').zoneRedundant | Should -BeExactly $false
        ($shaped['virtualMachines'] | Where-Object name -EQ 'vm2').zoneEligible | Should -BeExactly $false
    }

    It 'takes the parent policy name from the rule-collection-group resource id' {
        $group = New-Resource -Type 'microsoft.network/firewallpolicies/rulecollectiongroups' -Properties @{ priority = 100; ruleCollections = @() }
        $group.id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/firewallPolicies/pol1/ruleCollectionGroups/grp1'
        $shaped = ConvertFrom-ScoutInventory -Resources @($group) -ResourceContainers @()
        $shaped['firewallPolicyRuleGroups'][0].policyName | Should -Be 'pol1'
        $shaped['firewallPolicyRuleGroups'][0].priority | Should -Be 100
    }

    It 'strips the extension suffix to recover the Arc machine id' {
        $ext = New-Resource -Type 'microsoft.hybridcompute/machines/extensions' -Properties @{ type = 'MDE.Windows' }
        $ext.id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/m1/extensions/MDE'
        $shaped = ConvertFrom-ScoutInventory -Resources @($ext) -ResourceContainers @()
        $shaped['arcExtensions'][0].machineId | Should -Be '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/m1'
    }

    It 'de-duplicates rows that appear in both the resources and networkresources tables' {
        $vnet = New-Resource -Type 'microsoft.network/virtualnetworks' -Properties @{ virtualNetworkPeerings = @(1) }
        $shaped = ConvertFrom-ScoutInventory -Resources @($vnet, $vnet) -ResourceContainers @()
        $shaped['virtualNetworks'].Count | Should -Be 1
    }

    It 'projects subscriptions and resource groups out of the container rows' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @(
            [pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'Sub One'; subscriptionId = 'sub1'; properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null }
            [pscustomobject]@{ type = 'microsoft.resources/subscriptions/resourcegroups'; name = 'rg1'; subscriptionId = 'sub1' }
        )
        $shaped['subscriptions'].Count | Should -Be 1
        $shaped['subscriptions'][0].id | Should -Be 'sub1'
        $shaped['subscriptions'][0].state | Should -Be 'Enabled'
        $shaped['deployments'].Count | Should -Be 1
        $shaped['deployments'][0].name | Should -Be 'rg1'
    }

    It 'summarises diagnostic coverage per resource type from the diagnostic-settings sweep (AB#9300)' {
        # Diagnostic settings are an ARM extension resource that no Resource Graph row carries.
        # Coverage = resources whose diagnostic-settings GET succeeded (checked), and of those the
        # ones that returned at least one setting row (covered). A failed GET is not counted.
        $base = '/subscriptions/sub1/resourceGroups/rg1/providers/microsoft.storage/storageaccounts'
        $operations = @(
            [pscustomobject]@{ Dataset = 'ResourceDiagnosticSettings'; Status = 'Success'; Uri = "https://management.azure.com$base/a/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" }
            [pscustomobject]@{ Dataset = 'ResourceDiagnosticSettings'; Status = 'Empty'; Uri = "https://management.azure.com$base/b/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" }
            [pscustomobject]@{ Dataset = 'ResourceDiagnosticSettings'; Status = 'Failed'; Uri = "https://management.azure.com$base/c/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" }
        )
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.storage/storageaccounts' -Name 'a'
            New-Resource -Type 'microsoft.storage/storageaccounts' -Name 'b'
            New-Resource -Type 'microsoft.storage/storageaccounts' -Name 'c'
            [pscustomobject]@{ id = "$base/a/providers/microsoft.insights/diagnosticSettings/toLaw"; type = 'AZSC/ARMChild/ResourceDiagnosticSettings'; PARENTID = "$base/a"; PARENTTYPE = 'microsoft.storage/storageaccounts' }
        ) -ResourceContainers @() -SourceOperations $operations
        $shaped['diagnosticCoverageMeasured'] | Should -BeTrue
        $row = $shaped['diagnosticCoverage'] | Where-Object type -EQ 'microsoft.storage/storageaccounts'
        $row.total | Should -Be 2 -Because 'the account whose GET failed was not measured'
        $row.withDiag | Should -Be 1
        $row.coveragePct | Should -Be 50
    }

    It 'marks resource groups deployed from a template with the deployment''s templateHash (AB#9300)' {
        $containers = @(
            [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg-iac'; type = 'microsoft.resources/subscriptions/resourcegroups'; name = 'rg-iac'; subscriptionId = 'sub1' }
            [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg-portal'; type = 'microsoft.resources/subscriptions/resourcegroups'; name = 'rg-portal'; subscriptionId = 'sub1' }
        )
        $deployments = @(
            [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg-iac/providers/Microsoft.Resources/deployments/d1'; type = 'microsoft.resources/deployments'; name = 'd1'; resourceGroup = 'RG-IAC'; subscriptionId = 'sub1'
                properties = [pscustomobject]@{ templateHash = 'old'; timestamp = '2026-01-01T00:00:00Z' } }
            [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg-iac/providers/Microsoft.Resources/deployments/d2'; type = 'microsoft.resources/deployments'; name = 'd2'; resourceGroup = 'rg-iac'; subscriptionId = 'sub1'
                properties = [pscustomobject]@{ templateHash = 'new'; timestamp = '2026-06-01T00:00:00Z' } }
        )
        $shaped = ConvertFrom-ScoutInventory -Resources $deployments -ResourceContainers $containers
        $iac = $shaped['deployments'] | Where-Object name -EQ 'rg-iac'
        $portal = $shaped['deployments'] | Where-Object name -EQ 'rg-portal'
        $iac.properties.templateHash | Should -Be 'new'
        $iac.properties.templateDeploymentCount | Should -Be 2
        $portal.PSObject.Properties['properties'] | Should -BeNullOrEmpty -Because 'a resource group with no template deployment carries no templateHash'
    }

    It 'reports diagnostic coverage as not measured when no sweep ran, instead of 0%' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-Resource -Type 'microsoft.storage/storageaccounts' -Name 'a' -Properties @{ diagnosticSettings = [pscustomobject]@{ x = 1 } }
        ) -ResourceContainers @()
        $shaped['diagnosticCoverageMeasured'] | Should -BeFalse
        @($shaped['diagnosticCoverage']).Count | Should -Be 0 -Because 'properties.diagnosticSettings is not a real ARM property and must not be counted'
    }

    Context 'per-resource ARM GET datasets (AB#9300 phase 4, batch 2)' {
        BeforeAll {
            $script:Sub = '/subscriptions/sub1/resourceGroups/rg1/providers'
            function New-ChildRow {
                # A row as Get-ScoutArmChildResource emits it: the child's id/name/type/properties
                # plus the synthetic parent linkage.
                param([string] $Dataset, [string] $ParentId, [string] $ParentName, [string] $ChildJson, [string] $Name = 'default')
                $child = $ChildJson | ConvertFrom-Json
                [pscustomobject]@{
                    id             = "$ParentId/child/$Name"
                    name           = $Name
                    properties     = $child
                    # The child's own `type` is dropped by ConvertTo-ArmChildRow (it collides with
                    # TYPE, case-insensitively), so a real row carries only the synthetic one.
                    TYPE           = "AZSC/ARMChild/$Dataset"
                    PARENTID       = $ParentId
                    PARENTTYPE     = 'test/parent'
                    PARENTNAME     = $ParentName
                    PARENTLOCATION = 'eastus'
                    subscriptionId = 'sub1'
                    RESOURCEGROUP  = 'rg1'
                }
            }
            function New-SweepOp {
                param([string] $Dataset, [string] $Status, [string] $ParentId)
                [pscustomobject]@{ Dataset = $Dataset; Status = $Status; ParentId = $ParentId; Uri = "$ParentId/x?api-version=1" }
            }
            $script:AllDatasets = @(
                @{ Key = 'blobServiceProperties'; Dataset = 'StorageBlobServiceProperties' }
                @{ Key = 'fileServiceProperties'; Dataset = 'StorageFileServiceProperties' }
                @{ Key = 'sqlServerAuditing'; Dataset = 'SqlServerAuditing' }
                @{ Key = 'sqlFailoverGroups'; Dataset = 'SqlFailoverGroups' }
                @{ Key = 'webAppConfig'; Dataset = 'WebAppConfig' }
                @{ Key = 'webAppBasicAuth'; Dataset = 'WebAppBasicAuth' }
                @{ Key = 'eventHubGeoDr'; Dataset = 'EventHubGeoDr' }
                @{ Key = 'redisEnterpriseDatabases'; Dataset = 'RedisEnterpriseDatabases' }
            )
        }

        It 'always declares every dataset and its Measured flag, empty and false when no sweep ran' {
            $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
            foreach ($case in $script:AllDatasets) {
                $shaped.ContainsKey($case.Key) | Should -BeTrue -Because $case.Key
                @($shaped[$case.Key]).Count | Should -Be 0
                $shaped.ContainsKey("$($case.Key)Measured") | Should -BeTrue -Because "$($case.Key)Measured"
                $shaped["$($case.Key)Measured"] | Should -BeFalse
            }
        }

        It 'shapes blob service settings keyed by the lower-cased parent id, reading an absent feature as off' {
            $parent = "$script:Sub/Microsoft.Storage/storageAccounts/StOne"
            $on = New-ChildRow -Dataset StorageBlobServiceProperties -ParentId $parent -ParentName 'StOne' -ChildJson '{"deleteRetentionPolicy":{"enabled":true,"days":14},"containerDeleteRetentionPolicy":{"enabled":true,"days":7},"isVersioningEnabled":true,"changeFeed":{"enabled":true},"restorePolicy":{"enabled":true}}'
            # What ARM returns for an account that never enabled anything beyond a soft-delete stub
            # (verified live): no isVersioningEnabled, no changeFeed, no restorePolicy.
            $offParent = "$script:Sub/Microsoft.Storage/storageAccounts/stoff"
            $off = New-ChildRow -Dataset StorageBlobServiceProperties -ParentId $offParent -ParentName 'stoff' -ChildJson '{"deleteRetentionPolicy":{"enabled":false}}'
            $shaped = ConvertFrom-ScoutInventory -Resources @($on, $off) -ResourceContainers @() -SourceOperations @(
                New-SweepOp -Dataset StorageBlobServiceProperties -Status Success -ParentId $parent
                New-SweepOp -Dataset StorageBlobServiceProperties -Status Success -ParentId $offParent
            )
            $shaped['blobServicePropertiesMeasured'] | Should -BeTrue
            $a = $shaped['blobServiceProperties'] | Where-Object name -EQ 'StOne'
            $a.storageAccountId | Should -BeExactly $parent.ToLowerInvariant()
            $a.deleteRetentionEnabled | Should -BeExactly $true
            $a.deleteRetentionDays | Should -Be 14
            $a.containerDeleteRetentionEnabled | Should -BeExactly $true
            $a.containerDeleteRetentionDays | Should -Be 7
            $a.versioningEnabled | Should -BeExactly $true
            $a.changeFeedEnabled | Should -BeExactly $true
            $a.pointInTimeRestoreEnabled | Should -BeExactly $true
            $b = $shaped['blobServiceProperties'] | Where-Object name -EQ 'stoff'
            $b.deleteRetentionEnabled | Should -BeExactly $false
            $b.deleteRetentionDays | Should -BeNullOrEmpty
            $b.containerDeleteRetentionEnabled | Should -BeExactly $false
            $b.versioningEnabled | Should -BeExactly $false -Because 'an absent feature in a complete GET response means it was never enabled, not "unknown"'
            $b.changeFeedEnabled | Should -BeExactly $false
            $b.pointInTimeRestoreEnabled | Should -BeExactly $false
        }

        It 'keeps SMB strings exactly as returned, with null meaning every option is allowed' {
            $parent = "$script:Sub/Microsoft.Storage/storageAccounts/stfile"
            $restricted = New-ChildRow -Dataset StorageFileServiceProperties -ParentId $parent -ParentName 'stfile' -ChildJson '{"shareDeleteRetentionPolicy":{"enabled":true,"days":9},"protocolSettings":{"smb":{"versions":"SMB3.0;SMB3.1.1","channelEncryption":"AES-256-GCM","authenticationMethods":"Kerberos"}}}'
            $openParent = "$script:Sub/Microsoft.Storage/storageAccounts/stopen"
            $open = New-ChildRow -Dataset StorageFileServiceProperties -ParentId $openParent -ParentName 'stopen' -ChildJson '{"shareDeleteRetentionPolicy":{"enabled":true,"days":7},"protocolSettings":{"smb":{}}}'
            $shaped = ConvertFrom-ScoutInventory -Resources @($restricted, $open) -ResourceContainers @() -SourceOperations @(
                New-SweepOp -Dataset StorageFileServiceProperties -Status Success -ParentId $parent
            )
            $r = $shaped['fileServiceProperties'] | Where-Object name -EQ 'stfile'
            $r.shareDeleteRetentionEnabled | Should -BeExactly $true
            $r.shareDeleteRetentionDays | Should -Be 9
            $r.smbVersions | Should -BeExactly 'SMB3.0;SMB3.1.1'
            $r.smbChannelEncryption | Should -BeExactly 'AES-256-GCM'
            $r.smbAuthenticationMethods | Should -BeExactly 'Kerberos'
            $o = $shaped['fileServiceProperties'] | Where-Object name -EQ 'stopen'
            $o.smbVersions | Should -BeNullOrEmpty
            $null -eq $o.smbVersions | Should -BeTrue -Because 'null means all allowed; an empty string would read as none'
            $null -eq $o.smbChannelEncryption | Should -BeTrue
            $null -eq $o.smbAuthenticationMethods | Should -BeTrue
        }

        It 'shapes SQL auditing to its state and Azure Monitor flag only' {
            $parent = "$script:Sub/Microsoft.Sql/servers/sql1"
            $row = New-ChildRow -Dataset SqlServerAuditing -ParentId $parent -ParentName 'sql1' -ChildJson '{"state":"Enabled","isAzureMonitorTargetEnabled":true}'
            $shaped = ConvertFrom-ScoutInventory -Resources @($row) -ResourceContainers @() -SourceOperations @(New-SweepOp -Dataset SqlServerAuditing -Status Success -ParentId $parent)
            $a = $shaped['sqlServerAuditing'][0]
            $a.sqlServerId | Should -BeExactly $parent.ToLowerInvariant()
            $a.auditingState | Should -BeExactly 'Enabled'
            $a.azureMonitorTargetEnabled | Should -BeExactly $true
            @($a.PSObject.Properties.Name) | Should -Not -Contain 'storageAccountAccessKey'
            @($a.PSObject.Properties.Name) | Should -Not -Contain 'storageEndpoint'
        }

        It 'emits one failover-group row per server whose list answered, with a zero count where it returned nothing' {
            $withGroups = "$script:Sub/Microsoft.Sql/servers/sqlfg"
            $without = "$script:Sub/Microsoft.Sql/servers/sqlnone"
            $unreached = "$script:Sub/Microsoft.Sql/servers/sqlfailed"
            $auto = New-ChildRow -Dataset SqlFailoverGroups -ParentId $withGroups -ParentName 'sqlfg' -ChildJson '{"readWriteEndpoint":{"failoverPolicy":"Automatic"},"partnerServerCount":1,"databaseCount":2}' -Name 'fg1'
            $manual = New-ChildRow -Dataset SqlFailoverGroups -ParentId $withGroups -ParentName 'sqlfg' -ChildJson '{"readWriteEndpoint":{"failoverPolicy":"Manual"},"partnerServerCount":1,"databaseCount":0}' -Name 'fg2'
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.sql/servers' -Name 'sqlnone'
                $auto, $manual
            ) -ResourceContainers @() -SourceOperations @(
                New-SweepOp -Dataset SqlFailoverGroups -Status Success -ParentId $withGroups
                New-SweepOp -Dataset SqlFailoverGroups -Status Empty -ParentId $without
                New-SweepOp -Dataset SqlFailoverGroups -Status Failed -ParentId $unreached
            )
            $shaped['sqlFailoverGroupsMeasured'] | Should -BeTrue
            @($shaped['sqlFailoverGroups']).Count | Should -Be 2 -Because 'the server whose GET failed was not measured and gets no row'
            $g = $shaped['sqlFailoverGroups'] | Where-Object sqlServerId -EQ $withGroups.ToLowerInvariant()
            $g.failoverGroupCount | Should -Be 2
            $g.automaticFailoverGroupCount | Should -Be 1
            $g.hasAutomaticFailover | Should -BeExactly $true
            @($g.failoverPolicies) | Should -Be @('Automatic', 'Manual')
            $g.name | Should -Be 'sqlfg'
            $n = $shaped['sqlFailoverGroups'] | Where-Object sqlServerId -EQ $without.ToLowerInvariant()
            $n.failoverGroupCount | Should -Be 0
            $n.hasAutomaticFailover | Should -BeExactly $false
            @($n.failoverPolicies).Count | Should -Be 0
            $n.name | Should -Be 'sqlnone' -Because 'the parent row supplies the name when it is in the inventory'
        }

        It 'shapes web app configuration to scalar settings and a health-check boolean' {
            $parent = "$script:Sub/Microsoft.Web/sites/app1"
            $row = New-ChildRow -Dataset WebAppConfig -ParentId $parent -ParentName 'app1' -ChildJson '{"ftpsState":"FtpsOnly","alwaysOn":true,"remoteDebuggingEnabled":false,"http20Enabled":true,"minTlsVersion":"1.2","scmMinTlsVersion":"1.2","healthCheckPathSet":true}' -Name 'web'
            $bare = New-ChildRow -Dataset WebAppConfig -ParentId "$script:Sub/Microsoft.Web/sites/app2" -ParentName 'app2' -ChildJson '{"healthCheckPathSet":false}' -Name 'web'
            $shaped = ConvertFrom-ScoutInventory -Resources @($row, $bare) -ResourceContainers @() -SourceOperations @(New-SweepOp -Dataset WebAppConfig -Status Success -ParentId $parent)
            $c = $shaped['webAppConfig'] | Where-Object name -EQ 'app1'
            $c.webAppId | Should -BeExactly $parent.ToLowerInvariant()
            $c.ftpsState | Should -BeExactly 'FtpsOnly'
            $c.alwaysOn | Should -BeExactly $true
            $c.healthCheckPathSet | Should -BeExactly $true
            $c.remoteDebuggingEnabled | Should -BeExactly $false
            $c.http20Enabled | Should -BeExactly $true
            $c.minTlsVersion | Should -BeExactly '1.2'
            $c.scmMinTlsVersion | Should -BeExactly '1.2'
            @($c.PSObject.Properties.Name) | Should -Not -Contain 'healthCheckPath'
            $d = $shaped['webAppConfig'] | Where-Object name -EQ 'app2'
            $null -eq $d.ftpsState | Should -BeTrue
            $d.alwaysOn | Should -BeExactly $false
            $d.healthCheckPathSet | Should -BeExactly $false
        }

        It 'folds the ftp and scm policy rows into one row per site, leaving a policy it never got as null' {
            $both = "$script:Sub/Microsoft.Web/sites/both"
            $ftpOnly = "$script:Sub/Microsoft.Web/sites/ftponly"
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-ChildRow -Dataset WebAppBasicAuth -ParentId $both -ParentName 'both' -ChildJson '{"allow":false,"policy":"ftp"}' -Name 'ftp'
                New-ChildRow -Dataset WebAppBasicAuth -ParentId $both -ParentName 'both' -ChildJson '{"allow":true,"policy":"scm"}' -Name 'scm'
                New-ChildRow -Dataset WebAppBasicAuth -ParentId $ftpOnly -ParentName 'ftponly' -ChildJson '{"allow":true,"policy":"ftp"}' -Name 'ftp'
            ) -ResourceContainers @() -SourceOperations @(New-SweepOp -Dataset WebAppBasicAuth -Status Success -ParentId $both)
            @($shaped['webAppBasicAuth']).Count | Should -Be 2
            $b = $shaped['webAppBasicAuth'] | Where-Object name -EQ 'both'
            $b.ftpBasicAuthAllowed | Should -BeExactly $false
            $b.scmBasicAuthAllowed | Should -BeExactly $true
            $f = $shaped['webAppBasicAuth'] | Where-Object name -EQ 'ftponly'
            $f.ftpBasicAuthAllowed | Should -BeExactly $true
            $null -eq $f.scmBasicAuthAllowed | Should -BeTrue -Because 'no scm row came back, so it is unknown rather than disallowed'
        }

        It 'reports geo-DR as a boolean per namespace whose list answered' {
            $paired = "$script:Sub/Microsoft.EventHub/namespaces/ehpaired"
            $alone = "$script:Sub/Microsoft.EventHub/namespaces/ehalone"
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-ChildRow -Dataset EventHubGeoDr -ParentId $paired -ParentName 'ehpaired' -ChildJson '{"provisioningState":"Succeeded","role":"Primary"}' -Name 'alias'
            ) -ResourceContainers @() -SourceOperations @(
                New-SweepOp -Dataset EventHubGeoDr -Status Success -ParentId $paired
                New-SweepOp -Dataset EventHubGeoDr -Status Empty -ParentId $alone
            )
            $shaped['eventHubGeoDrMeasured'] | Should -BeTrue
            @($shaped['eventHubGeoDr']).Count | Should -Be 2
            ($shaped['eventHubGeoDr'] | Where-Object eventHubNamespaceId -EQ $paired.ToLowerInvariant()).geoDrConfigured | Should -BeExactly $true
            $notPaired = $shaped['eventHubGeoDr'] | Where-Object eventHubNamespaceId -EQ $alone.ToLowerInvariant()
            $notPaired.geoDrConfigured | Should -BeExactly $false
            $notPaired.name | Should -Be 'ehalone' -Because 'the name is recovered from the id when the parent row is not in the inventory'
            @($notPaired.PSObject.Properties.Name) | Should -Be @('eventHubNamespaceId', 'name', 'resourceGroup', 'subscriptionId', 'location', 'geoDrConfigured')
        }

        It 'shapes Redis Enterprise databases with the access-key setting, protocol, persistence and link count' {
            $parent = "$script:Sub/Microsoft.Cache/redisEnterprise/redis1"
            $row = New-ChildRow -Dataset RedisEnterpriseDatabases -ParentId $parent -ParentName 'redis1' -ChildJson '{"accessKeysAuthentication":"Disabled","clientProtocol":"Encrypted","persistence":{"aofEnabled":true,"aofFrequency":"1s"},"geoReplication":{"linkedDatabaseCount":2}}'
            $shaped = ConvertFrom-ScoutInventory -Resources @($row) -ResourceContainers @() -SourceOperations @(New-SweepOp -Dataset RedisEnterpriseDatabases -Status Success -ParentId $parent)
            $d = $shaped['redisEnterpriseDatabases'][0]
            $d.redisEnterpriseId | Should -BeExactly $parent.ToLowerInvariant()
            $d.name | Should -Be 'default'
            $d.clusterName | Should -Be 'redis1'
            $d.accessKeysAuthentication | Should -BeExactly 'Disabled'
            $d.clientProtocol | Should -BeExactly 'Encrypted'
            $d.persistenceAofEnabled | Should -BeExactly $true
            $d.persistenceAofFrequency | Should -BeExactly '1s'
            $d.persistenceRdbEnabled | Should -BeExactly $false
            $null -eq $d.persistenceRdbFrequency | Should -BeTrue
            $d.geoReplicationLinkCount | Should -Be 2
        }

        It 'sets a Measured flag only when a GET of that dataset got an answer' {
            $parent = "$script:Sub/Microsoft.Storage/storageAccounts/stm"
            $cases = @(
                @{ Statuses = @('Success'); Expected = $true }
                @{ Statuses = @('Empty'); Expected = $true }
                @{ Statuses = @('Failed', 'Success'); Expected = $true }
                @{ Statuses = @('Failed', 'Failed'); Expected = $false }
                @{ Statuses = @('NotApplicable'); Expected = $false }
                @{ Statuses = @(); Expected = $false }
            )
            foreach ($case in $cases) {
                $ops = @($case.Statuses | ForEach-Object { New-SweepOp -Dataset StorageBlobServiceProperties -Status $_ -ParentId $parent })
                $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @() -SourceOperations $ops
                $shaped['blobServicePropertiesMeasured'] | Should -Be $case.Expected -Because ($case.Statuses -join ',')
            }
            # A different dataset's operations must not measure this one.
            $other = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @() -SourceOperations @(New-SweepOp -Dataset StorageFileServiceProperties -Status Success -ParentId $parent)
            $other['blobServicePropertiesMeasured'] | Should -BeFalse
            $other['fileServicePropertiesMeasured'] | Should -BeTrue
        }

        It 'leaves rows out when no operation was recorded, rather than guessing a sweep ran' {
            $parent = "$script:Sub/Microsoft.Storage/storageAccounts/stg"
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-ChildRow -Dataset StorageBlobServiceProperties -ParentId $parent -ParentName 'stg' -ChildJson '{"deleteRetentionPolicy":{"enabled":true}}'
            ) -ResourceContainers @()
            @($shaped['blobServiceProperties']).Count | Should -Be 1
            $shaped['blobServicePropertiesMeasured'] | Should -BeFalse -Because 'there is no source operation to prove the GET was answered'
        }
    }

    It 'never produces sqlDefenderPricing — that query reads SecurityResources, which inventory does not collect' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        $shaped.ContainsKey('sqlDefenderPricing') | Should -BeFalse
    }
}

# Discovery-time data for the sparse-payload table below: Pester evaluates -ForEach before any
# BeforeAll has run, so this lives at file scope. Each case is one resource with an EMPTY properties
# bag; Expected is what that absence must read as. $null is "unknown" (KQL tobool()/toint()/
# array_length() of a missing property is null, never false/0); $false / 0 / '' appear only where
# the KQL itself yields them (isnotempty() is a real false, a countif over no rows is a real 0).
$script:Phase4SparseCases = @(
    @{ Type = 'microsoft.sql/managedinstances'; Dataset = 'sqlManagedInstances'; Field = 'zoneRedundant'; Expected = $null }
    @{ Type = 'microsoft.sql/managedinstances'; Dataset = 'sqlManagedInstances'; Field = 'entraOnlyAuth'; Expected = $null }
    @{ Type = 'microsoft.sql/managedinstances'; Dataset = 'sqlManagedInstances'; Field = 'cmkEnabled'; Expected = $false }
    @{ Type = 'microsoft.sql/servers'; Dataset = 'sqlServers'; Field = 'entraOnlyAuth'; Expected = $null }
    @{ Type = 'microsoft.sql/servers'; Dataset = 'sqlServers'; Field = 'cmkEnabled'; Expected = $false }
    @{ Type = 'microsoft.sql/servers/databases'; Dataset = 'sqlDatabases'; Field = 'haReplicaCount'; Expected = $null }
    @{ Type = 'microsoft.documentdb/databaseaccounts'; Dataset = 'cosmosDbAccounts'; Field = 'automaticFailover'; Expected = $null }
    @{ Type = 'microsoft.documentdb/databaseaccounts'; Dataset = 'cosmosDbAccounts'; Field = 'regionCount'; Expected = $null }
    @{ Type = 'microsoft.documentdb/databaseaccounts'; Dataset = 'cosmosDbAccounts'; Field = 'zoneRedundantRegionCount'; Expected = 0 }
    @{ Type = 'microsoft.documentdb/databaseaccounts'; Dataset = 'cosmosDbAccounts'; Field = 'ipRuleCount'; Expected = $null }
    @{ Type = 'microsoft.documentdb/databaseaccounts'; Dataset = 'cosmosDbAccounts'; Field = 'cmkEnabled'; Expected = $false }
    @{ Type = 'microsoft.containerservice/managedclusters'; Dataset = 'aksClusters'; Field = 'systemPoolMinNodes'; Expected = $null }
    @{ Type = 'microsoft.containerservice/managedclusters'; Dataset = 'aksClusters'; Field = 'disableLocalAccounts'; Expected = $null }
    @{ Type = 'microsoft.containerservice/managedclusters'; Dataset = 'aksClusters'; Field = 'authorizedIpRangeCount'; Expected = $null }
    @{ Type = 'microsoft.network/azurefirewalls'; Dataset = 'azureFirewalls'; Field = 'zoneCount'; Expected = $null }
    @{ Type = 'microsoft.network/azurefirewalls'; Dataset = 'azureFirewalls'; Field = 'hasPolicy'; Expected = $false }
    @{ Type = 'microsoft.network/publicipaddresses'; Dataset = 'publicIPAddresses'; Field = 'zoneCount'; Expected = $null }
    @{ Type = 'microsoft.network/publicipaddresses'; Dataset = 'publicIPAddresses'; Field = 'attached'; Expected = $false }
    @{ Type = 'microsoft.network/networkwatchers/flowlogs'; Dataset = 'flowLogs'; Field = 'enabled'; Expected = $null }
    @{ Type = 'microsoft.network/networkwatchers/flowlogs'; Dataset = 'flowLogs'; Field = 'retentionDays'; Expected = $null }
    @{ Type = 'microsoft.network/networkwatchers/flowlogs'; Dataset = 'flowLogs'; Field = 'trafficAnalytics'; Expected = $null }
    @{ Type = 'microsoft.network/loadbalancers'; Dataset = 'loadBalancers'; Field = 'probeCount'; Expected = $null }
    @{ Type = 'microsoft.network/loadbalancers'; Dataset = 'loadBalancers'; Field = 'minFrontendZoneCount'; Expected = 0 }
    @{ Type = 'microsoft.network/virtualnetworks'; Dataset = 'virtualNetworks'; Field = 'encryptionEnabled'; Expected = $null }
    @{ Type = 'microsoft.compute/virtualmachines'; Dataset = 'virtualMachines'; Field = 'encryptionAtHost'; Expected = $null }
    @{ Type = 'microsoft.compute/virtualmachines'; Dataset = 'virtualMachines'; Field = 'bootDiagnostics'; Expected = $null }
    @{ Type = 'microsoft.compute/virtualmachines'; Dataset = 'virtualMachines'; Field = 'inAvailabilitySet'; Expected = $false }
    @{ Type = 'microsoft.compute/virtualmachines'; Dataset = 'virtualMachines'; Field = 'unmanagedOsDisk'; Expected = $false }
    @{ Type = 'microsoft.compute/virtualmachinescalesets'; Dataset = 'virtualMachineScaleSets'; Field = 'zoneBalance'; Expected = $null }
    @{ Type = 'microsoft.compute/virtualmachinescalesets'; Dataset = 'virtualMachineScaleSets'; Field = 'capacity'; Expected = $null }
    @{ Type = 'microsoft.compute/disks'; Dataset = 'managedDisks'; Field = 'zoneCount'; Expected = $null }
    @{ Type = 'microsoft.cache/redis'; Dataset = 'redisCaches'; Field = 'nonSslPortEnabled'; Expected = $null }
    @{ Type = 'microsoft.cache/redis'; Dataset = 'redisCaches'; Field = 'replicasPerPrimary'; Expected = $null }
    @{ Type = 'microsoft.cache/redis'; Dataset = 'redisCaches'; Field = 'aadEnabled'; Expected = $null }
    @{ Type = 'microsoft.web/serverfarms'; Dataset = 'appServicePlans'; Field = 'zoneRedundant'; Expected = $null }
    @{ Type = 'microsoft.web/serverfarms'; Dataset = 'appServicePlans'; Field = 'instanceCount'; Expected = $null }
    @{ Type = 'microsoft.operationalinsights/workspaces'; Dataset = 'logAnalyticsWorkspaces'; Field = 'dailyQuotaGb'; Expected = $null }
    @{ Type = 'microsoft.operationalinsights/workspaces'; Dataset = 'logAnalyticsWorkspaces'; Field = 'disableLocalAuth'; Expected = $null }
    @{ Type = 'microsoft.insights/components'; Dataset = 'appInsights'; Field = 'workspaceBased'; Expected = $false }
    @{ Type = 'microsoft.insights/components'; Dataset = 'appInsights'; Field = 'disableLocalAuth'; Expected = $null }
    @{ Type = 'microsoft.insights/activitylogalerts'; Dataset = 'activityLogAlertRules'; Field = 'category'; Expected = $null }
    @{ Type = 'microsoft.databricks/workspaces'; Dataset = 'databricksWorkspaces'; Field = 'vnetInjected'; Expected = $false }
    @{ Type = 'microsoft.databricks/workspaces'; Dataset = 'databricksWorkspaces'; Field = 'noPublicIp'; Expected = $null }
    @{ Type = 'microsoft.eventgrid/topics'; Dataset = 'eventGrid'; Field = 'disableLocalAuth'; Expected = $null }
    @{ Type = 'microsoft.eventgrid/topics'; Dataset = 'eventGrid'; Field = 'zoneRedundant'; Expected = $null }
    @{ Type = 'microsoft.eventhub/namespaces'; Dataset = 'eventHubNamespaces'; Field = 'geoReplicaCount'; Expected = $null }
    @{ Type = 'microsoft.servicebus/namespaces'; Dataset = 'serviceBusNamespaces'; Field = 'geoReplicaCount'; Expected = $null }
    @{ Type = 'microsoft.search/searchservices'; Dataset = 'searchServices'; Field = 'ipRuleCount'; Expected = $null }
    @{ Type = 'microsoft.app/containerapps'; Dataset = 'containerApps'; Field = 'minReplicas'; Expected = $null }
    @{ Type = 'microsoft.app/managedenvironments'; Dataset = 'containerAppEnvironments'; Field = 'vnetIntegrated'; Expected = $false }
    @{ Type = 'microsoft.storage/storageaccounts'; Dataset = 'storageAccounts'; Field = 'sharedKeyAccess'; Expected = $null }
    @{ Type = 'microsoft.machinelearningservices/workspaces'; Dataset = 'mlWorkspaces'; Field = 'hbiWorkspace'; Expected = $null }
)

Describe 'ConvertFrom-ScoutInventory — AB#9300 phase 4 collection properties' {

    Context 'the two bug fixes' {
        It 'reads an absent classic Redis access-key flag as false (Azure default: keys allowed) but leaves Enterprise null' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.cache/redis' -Name 'nokeyflag' -Properties @{ sku = [pscustomobject]@{ name = 'Standard' } }
                New-Resource -Type 'microsoft.cache/redis' -Name 'keysoff' -Properties @{ sku = [pscustomobject]@{ name = 'Standard' }; disableAccessKeyAuthentication = $true }
                New-Resource -Type 'microsoft.cache/redisenterprise' -Name 'ent' -Properties @{ highAvailability = 'Enabled' }
            ) -ResourceContainers @()
            ($shaped['redisCaches'] | Where-Object name -EQ 'nokeyflag').accessKeyAuthDisabled | Should -BeExactly $false
            ($shaped['redisCaches'] | Where-Object name -EQ 'keysoff').accessKeyAuthDisabled | Should -BeExactly $true
            ($null -eq ($shaped['redisCaches'] | Where-Object name -EQ 'ent').accessKeyAuthDisabled) | Should -BeTrue
        }

        It 'reads the classic Redis SKU from properties.sku and the Enterprise SKU from the top-level sku' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.cache/redis' -Name 'classic' -Properties @{
                    sku = [pscustomobject]@{ name = 'Premium'; family = 'P'; capacity = 2 }
                }
                New-Resource -Type 'microsoft.cache/redisenterprise' -Name 'ent' -Properties @{
                    highAvailability = 'Enabled'; minimumTlsVersion = '1.2'
                } -Extra @{ sku = [pscustomobject]@{ name = 'Enterprise_E10'; capacity = 2 }; zones = @('1', '2') }
            ) -ResourceContainers @()

            $classic = $shaped['redisCaches'] | Where-Object name -EQ 'classic'
            $enterprise = $shaped['redisCaches'] | Where-Object name -EQ 'ent'
            $classic.sku | Should -Be 'Premium' -Because 'classic Redis has no top-level sku column; the tier is properties.sku.name'
            $classic.skuFamily | Should -Be 'P'
            $classic.skuCapacity | Should -BeExactly 2
            $enterprise.sku | Should -Be 'Enterprise_E10' -Because 'Redis Enterprise keeps its SKU in the top-level sku column'
            $enterprise.skuFamily | Should -BeNullOrEmpty
            ($null -eq $enterprise.skuCapacity) | Should -BeTrue -Because 'Enterprise has no properties.sku, so there is no classic capacity to report'
            $enterprise.highAvailability | Should -Be 'Enabled'
            $enterprise.zoneCount | Should -BeExactly 2
        }

        It 'never reads the classic Redis SKU from a top-level sku column' {
            # If a classic cache ever did carry one, properties.sku still wins -- the type decides.
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.cache/redis' -Name 'classic' -Properties @{
                    sku = [pscustomobject]@{ name = 'Standard'; family = 'C'; capacity = 1 }
                } -Extra @{ sku = [pscustomobject]@{ name = 'WrongColumn' } }
            ) -ResourceContainers @()
            $shaped['redisCaches'][0].sku | Should -Be 'Standard'
        }

        It 'reports the Azure Firewall tier from properties.sku.tier, not the AZFW_VNet / AZFW_Hub sku name' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.network/azurefirewalls' -Name 'fw1' -Properties @{
                    sku             = [pscustomobject]@{ name = 'AZFW_VNet'; tier = 'Premium' }
                    firewallPolicy  = [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/firewallPolicies/pol1' }
                    threatIntelMode = 'Deny'
                } -Extra @{ zones = @('1', '2', '3') }
                New-Resource -Type 'microsoft.network/azurefirewalls' -Name 'fw2' -Properties @{
                    sku = [pscustomobject]@{ name = 'AZFW_Hub'; tier = 'Standard' }
                }
            ) -ResourceContainers @()
            $fw1 = $shaped['azureFirewalls'] | Where-Object name -EQ 'fw1'
            $fw2 = $shaped['azureFirewalls'] | Where-Object name -EQ 'fw2'
            $fw1.sku | Should -Be 'AZFW_VNet'
            $fw1.tier | Should -Be 'Premium'
            $fw1.zoneCount | Should -BeExactly 3
            $fw1.hasPolicy | Should -BeExactly $true
            $fw1.threatIntelMode | Should -Be 'Deny'
            $fw2.tier | Should -Be 'Standard'
            $fw2.hasPolicy | Should -BeExactly $false -Because 'no firewallPolicy.id means no policy attached'
            ($null -eq $fw2.zoneCount) | Should -BeTrue -Because 'no zones array is unknown, not zero zones'
        }
    }

    Context 'per-element counts' {
        It 'counts only the Cosmos locations flagged zone redundant (a missing flag is not redundant)' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.documentdb/databaseaccounts' -Name 'c1' -Properties @{
                    locations = @(
                        [pscustomobject]@{ locationName = 'East US'; isZoneRedundant = $true }
                        [pscustomobject]@{ locationName = 'West US'; isZoneRedundant = $false }
                        [pscustomobject]@{ locationName = 'North Europe' }
                        [pscustomobject]@{ locationName = 'UK South'; isZoneRedundant = $true }
                    )
                }
                New-Resource -Type 'microsoft.documentdb/databaseaccounts' -Name 'c2' -Properties @{
                    locations = @([pscustomobject]@{ locationName = 'East US' })
                }
                New-Resource -Type 'microsoft.documentdb/databaseaccounts' -Name 'c3' -Properties @{ locations = @() }
            ) -ResourceContainers @()
            $c1 = $shaped['cosmosDbAccounts'] | Where-Object name -EQ 'c1'
            $c2 = $shaped['cosmosDbAccounts'] | Where-Object name -EQ 'c2'
            $c3 = $shaped['cosmosDbAccounts'] | Where-Object name -EQ 'c3'
            $c1.regionCount | Should -BeExactly 4
            $c1.zoneRedundantRegionCount | Should -BeExactly 2
            $c2.regionCount | Should -BeExactly 1
            $c2.zoneRedundantRegionCount | Should -BeExactly 0
            $c3.regionCount | Should -BeExactly 0 -Because 'a present-but-empty locations array is zero regions, like array_length([])'
            $c3.zoneRedundantRegionCount | Should -BeExactly 0
        }

        It 'takes the AKS system pool floor from minCount when it autoscales and from count when it does not' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                # An autoscaling system pool (floor 2, current 6) and a fixed system pool (1): min = 1.
                New-Resource -Type 'microsoft.containerservice/managedclusters' -Name 'mixed' -Properties @{
                    agentPoolProfiles = @(
                        [pscustomobject]@{ name = 'sys'; mode = 'System'; enableAutoScaling = $true; minCount = 2; maxCount = 8; count = 6 }
                        [pscustomobject]@{ name = 'sys2'; mode = 'System'; count = 1 }
                        [pscustomobject]@{ name = 'user'; mode = 'User'; enableAutoScaling = $true; minCount = 0; count = 9 }
                    )
                }
                # The autoscale floor, not the current count, is the capacity the pool may fall to.
                New-Resource -Type 'microsoft.containerservice/managedclusters' -Name 'auto' -Properties @{
                    agentPoolProfiles = @([pscustomobject]@{ name = 'sys'; mode = 'System'; enableAutoScaling = $true; minCount = 3; maxCount = 9; count = 7 })
                }
                # User pools never count towards the system floor.
                New-Resource -Type 'microsoft.containerservice/managedclusters' -Name 'useronly' -Properties @{
                    agentPoolProfiles = @([pscustomobject]@{ name = 'u'; mode = 'User'; count = 5 })
                }
            ) -ResourceContainers @()
            ($shaped['aksClusters'] | Where-Object name -EQ 'mixed').systemPoolMinNodes | Should -BeExactly 1
            ($shaped['aksClusters'] | Where-Object name -EQ 'auto').systemPoolMinNodes | Should -BeExactly 3
            $null -eq ($shaped['aksClusters'] | Where-Object name -EQ 'useronly').systemPoolMinNodes | Should -BeTrue
        }

        It 'marks allPoolsAutoscale only when every pool carries an explicit autoscale flag' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.containerservice/managedclusters' -Name 'all' -Properties @{
                    agentPoolProfiles = @(
                        [pscustomobject]@{ mode = 'System'; enableAutoScaling = $true; minCount = 1 }
                        [pscustomobject]@{ mode = 'User'; enableAutoScaling = $true; minCount = 0 }
                    )
                }
                New-Resource -Type 'microsoft.containerservice/managedclusters' -Name 'some' -Properties @{
                    agentPoolProfiles = @(
                        [pscustomobject]@{ mode = 'System'; enableAutoScaling = $true; minCount = 1 }
                        [pscustomobject]@{ mode = 'User'; count = 3 }
                    )
                }
            ) -ResourceContainers @()
            ($shaped['aksClusters'] | Where-Object name -EQ 'all').allPoolsAutoscale | Should -BeExactly $true
            ($shaped['aksClusters'] | Where-Object name -EQ 'some').allPoolsAutoscale | Should -BeExactly $false
        }

        It 'reports a load balancer''s WEAKEST frontend zone count, 0 when a frontend has none or there is no frontend' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.network/loadbalancers' -Name 'allzoned' -Properties @{
                    frontendIPConfigurations = @(
                        [pscustomobject]@{ name = 'a'; zones = @('1', '2', '3') }
                        [pscustomobject]@{ name = 'b'; zones = @('1', '2', '3') }
                    )
                }
                New-Resource -Type 'microsoft.network/loadbalancers' -Name 'oneweak' -Properties @{
                    frontendIPConfigurations = @(
                        [pscustomobject]@{ name = 'a'; zones = @('1', '2', '3') }
                        [pscustomobject]@{ name = 'b'; zones = @('1') }
                    )
                }
                New-Resource -Type 'microsoft.network/loadbalancers' -Name 'nozones' -Properties @{
                    frontendIPConfigurations = @([pscustomobject]@{ name = 'a' })
                }
                New-Resource -Type 'microsoft.network/loadbalancers' -Name 'nofrontend' -Properties @{}
            ) -ResourceContainers @()
            ($shaped['loadBalancers'] | Where-Object name -EQ 'allzoned').minFrontendZoneCount | Should -BeExactly 3
            ($shaped['loadBalancers'] | Where-Object name -EQ 'oneweak').minFrontendZoneCount | Should -BeExactly 1
            ($shaped['loadBalancers'] | Where-Object name -EQ 'nozones').minFrontendZoneCount | Should -BeExactly 0
            ($shaped['loadBalancers'] | Where-Object name -EQ 'nofrontend').minFrontendZoneCount | Should -BeExactly 0
        }

        It 'extracts the activity-log alert category from the allOf entry whose field is category, null when none' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.insights/activitylogalerts' -Name 'admin' -Properties @{
                    condition = [pscustomobject]@{ allOf = @(
                            [pscustomobject]@{ field = 'operationName'; equals = 'Microsoft.Compute/virtualMachines/delete' }
                            [pscustomobject]@{ field = 'category'; equals = 'Administrative' }
                        ) }
                }
                # ARM field names are not consistently cased.
                New-Resource -Type 'microsoft.insights/activitylogalerts' -Name 'health' -Properties @{
                    condition = [pscustomobject]@{ allOf = @([pscustomobject]@{ field = 'Category'; equals = 'ServiceHealth' }) }
                }
                New-Resource -Type 'microsoft.insights/activitylogalerts' -Name 'nocategory' -Properties @{
                    condition = [pscustomobject]@{ allOf = @([pscustomobject]@{ field = 'resourceType'; equals = 'Microsoft.Sql/servers' }) }
                }
                # A category entry with no `equals` (a containsAny condition) names no category.
                New-Resource -Type 'microsoft.insights/activitylogalerts' -Name 'noequals' -Properties @{
                    condition = [pscustomobject]@{ allOf = @([pscustomobject]@{ field = 'category'; containsAny = @('Security') }) }
                }
                New-Resource -Type 'microsoft.insights/activitylogalerts' -Name 'nocondition' -Properties @{}
            ) -ResourceContainers @()
            ($shaped['activityLogAlertRules'] | Where-Object name -EQ 'admin').category | Should -Be 'Administrative'
            ($shaped['activityLogAlertRules'] | Where-Object name -EQ 'health').category | Should -Be 'ServiceHealth'
            foreach ($name in 'nocategory', 'noequals', 'nocondition') {
                $row = $shaped['activityLogAlertRules'] | Where-Object name -EQ $name
                ($null -eq $row.category) | Should -BeTrue -Because "'$name' names no category, so null (not an empty string)"
            }
            @($shaped['activityLogAlertRules']).Count | Should -Be 5 -Because 'no alert is dropped for lacking a category'
        }
    }

    Context 'bool-only fields and attachment flags' {
        It 'reports VM unmanagedOsDisk as a real bool and never carries the VHD uri' {
            $vhdUri = 'https://unmanagedstorageacct.blob.core.windows.net/vhds/osdisk.vhd'
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.compute/virtualmachines' -Name 'legacy' -Properties @{
                    storageProfile = [pscustomobject]@{ osDisk = [pscustomobject]@{ osType = 'Linux'; vhd = [pscustomobject]@{ uri = $vhdUri } } }
                    availabilitySet = [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Compute/availabilitySets/as1' }
                }
                New-Resource -Type 'microsoft.compute/virtualmachines' -Name 'managed' -Properties @{
                    storageProfile = [pscustomobject]@{ osDisk = [pscustomobject]@{ osType = 'Windows'; managedDisk = [pscustomobject]@{ storageAccountType = 'Premium_LRS' } } }
                }
            ) -ResourceContainers @()
            $legacy = $shaped['virtualMachines'] | Where-Object name -EQ 'legacy'
            $managed = $shaped['virtualMachines'] | Where-Object name -EQ 'managed'
            $legacy.unmanagedOsDisk | Should -BeOfType [bool]
            $legacy.unmanagedOsDisk | Should -BeExactly $true
            $legacy.inAvailabilitySet | Should -BeExactly $true
            $managed.unmanagedOsDisk | Should -BeOfType [bool]
            $managed.unmanagedOsDisk | Should -BeExactly $false
            $managed.osDiskType | Should -Be 'Premium_LRS'
            ($shaped['virtualMachines'] | ConvertTo-Json -Depth 5) | Should -Not -Match 'unmanagedstorageacct' -Because 'only the bool is shaped, never the uri'
        }

        It 'flags a public IP as attached only when it is bound to an IP configuration' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.network/publicipaddresses' -Name 'bound' -Properties @{
                    publicIPAllocationMethod = 'Static'
                    ddosSettings             = [pscustomobject]@{ protectionMode = 'Enabled' }
                    ipConfiguration          = [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/networkInterfaces/nic1/ipConfigurations/ipc1' }
                } -Extra @{ sku = [pscustomobject]@{ name = 'Standard'; tier = 'Regional' }; zones = @('1', '2', '3') }
                New-Resource -Type 'microsoft.network/publicipaddresses' -Name 'floating' -Properties @{
                    publicIPAllocationMethod = 'Dynamic'
                } -Extra @{ sku = [pscustomobject]@{ name = 'Basic'; tier = 'Regional' } }
                # An address bound only to a NAT gateway carries properties.natGateway, not an
                # ipConfiguration -- the documented limit of this flag.
                New-Resource -Type 'microsoft.network/publicipaddresses' -Name 'natonly' -Properties @{
                    natGateway = [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/natGateways/ng1' }
                }
            ) -ResourceContainers @()
            $bound = $shaped['publicIPAddresses'] | Where-Object name -EQ 'bound'
            $floating = $shaped['publicIPAddresses'] | Where-Object name -EQ 'floating'
            $natOnly = $shaped['publicIPAddresses'] | Where-Object name -EQ 'natonly'
            $bound.attached | Should -BeOfType [bool]
            $bound.attached | Should -BeExactly $true
            $floating.attached | Should -BeExactly $false
            $natOnly.attached | Should -BeExactly $false
            $bound.skuName | Should -Be 'Standard'
            $bound.skuTier | Should -Be 'Regional'
            $bound.zoneCount | Should -BeExactly 3
            $bound.ddosProtectionMode | Should -Be 'Enabled'
            $bound.allocationMethod | Should -Be 'Static'
            $floating.allocationMethod | Should -Be 'Dynamic'
            # orphanedPips still lists the unbound ones and only those, independently of this dataset.
            @($shaped['orphanedPips'] | ForEach-Object name) | Should -Contain 'floating'
            @($shaped['orphanedPips'] | ForEach-Object name) | Should -Not -Contain 'bound'
        }

        It 'lower-cases a flow log''s target id and never shapes the workspace or storage ids' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.network/networkwatchers/flowlogs' -Name 'fl1' -Properties @{
                    enabled                     = $true
                    targetResourceId            = '/subscriptions/SUB1/resourceGroups/RG1/providers/Microsoft.Network/networkSecurityGroups/NSG1'
                    storageId                   = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/flowlogstorageacct'
                    retentionPolicy             = [pscustomobject]@{ enabled = $true; days = 30 }
                    flowAnalyticsConfiguration  = [pscustomobject]@{
                        networkWatcherFlowAnalyticsConfiguration = [pscustomobject]@{
                            enabled = $true; workspaceResourceId = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.OperationalInsights/workspaces/flowlogworkspace'
                        }
                    }
                }
            ) -ResourceContainers @()
            $row = $shaped['flowLogs'][0]
            $row.enabled | Should -BeExactly $true
            $row.targetResourceId | Should -BeExactly '/subscriptions/sub1/resourcegroups/rg1/providers/microsoft.network/networksecuritygroups/nsg1'
            $row.retentionEnabled | Should -BeExactly $true
            $row.retentionDays | Should -BeExactly 30
            $row.trafficAnalytics | Should -BeExactly $true
            ($row | ConvertTo-Json -Depth 4) | Should -Not -Match 'flowlogstorageacct|flowlogworkspace'
        }
    }

    Context 'nothing secret-bearing or identifying is shaped' {
        It 'keeps every sentinel value planted in a never-project property out of every shaped dataset' {
            $s = 'SENTINEL-MUST-NOT-APPEAR'
            $resources = @(
                New-Resource -Type 'microsoft.cache/redis' -Name 'r1' -Properties @{
                    sku = [pscustomobject]@{ name = 'Premium'; family = 'P'; capacity = 1 }
                    redisConfiguration = [pscustomobject]@{
                        'aad-enabled'                   = 'true'
                        'rdb-storage-connection-string' = $s
                        'aof-storage-connection-string-0' = $s
                        'maxmemory-policy'              = 'volatile-lru'
                    }
                }
                New-Resource -Type 'microsoft.network/applicationgateways' -Name 'agw1' -Properties @{
                    sslCertificates = @([pscustomobject]@{ name = 'c1'; properties = [pscustomobject]@{ data = $s; password = $s; keyVaultSecretId = $s } })
                    sslPolicy       = [pscustomobject]@{ policyType = 'Predefined'; policyName = 'AppGwSslPolicy20220101'; minProtocolVersion = 'TLSv1_2' }
                }
                New-Resource -Type 'microsoft.app/containerapps' -Name 'ca1' -Properties @{
                    configuration = [pscustomobject]@{
                        secrets = @([pscustomobject]@{ name = 'db'; value = $s })
                        ingress = [pscustomobject]@{ external = $true; allowInsecure = $false }
                    }
                    template = [pscustomobject]@{ scale = [pscustomobject]@{ minReplicas = 1 } }
                }
                New-Resource -Type 'microsoft.app/managedenvironments' -Name 'cae1' -Properties @{
                    appLogsConfiguration = [pscustomobject]@{ logAnalyticsConfiguration = [pscustomobject]@{ customerId = $s; sharedKey = $s } }
                    vnetConfiguration    = [pscustomobject]@{ internal = $true; infrastructureSubnetId = $s }
                }
                New-Resource -Type 'microsoft.eventhub/namespaces' -Name 'eh1' -Properties @{
                    encryption = [pscustomobject]@{
                        keySource = 'Microsoft.KeyVault'; requireInfrastructureEncryption = $true
                        keyVaultProperties = @([pscustomobject]@{ keyName = $s; keyVaultUri = $s; keyVersion = $s })
                    }
                }
                New-Resource -Type 'microsoft.servicebus/namespaces' -Name 'sb1' -Properties @{
                    encryption = [pscustomobject]@{ keySource = 'Microsoft.KeyVault'; keyVaultProperties = @([pscustomobject]@{ keyName = $s; keyVaultUri = $s }) }
                }
                New-Resource -Type 'microsoft.sql/servers' -Name 'sql1' -Properties @{
                    keyId = $s
                    administrators = [pscustomobject]@{ login = $s; sid = $s; tenantId = $s; azureADOnlyAuthentication = $true }
                }
                New-Resource -Type 'microsoft.sql/managedinstances' -Name 'mi1' -Properties @{
                    keyId = $s
                    administrators = [pscustomobject]@{ login = $s; sid = $s; tenantId = $s; azureADOnlyAuthentication = $true }
                }
                New-Resource -Type 'microsoft.compute/virtualmachines' -Name 'vm1' -Properties @{
                    storageProfile  = [pscustomobject]@{ osDisk = [pscustomobject]@{ vhd = [pscustomobject]@{ uri = $s } } }
                    availabilitySet = [pscustomobject]@{ id = $s }
                }
                New-Resource -Type 'microsoft.network/networkwatchers/flowlogs' -Name 'fl1' -Properties @{
                    enabled = $true; targetResourceId = '/subscriptions/sub1/x'
                    storageId = $s
                    flowAnalyticsConfiguration = [pscustomobject]@{ networkWatcherFlowAnalyticsConfiguration = [pscustomobject]@{ enabled = $true; workspaceId = $s; workspaceResourceId = $s } }
                }
                New-Resource -Type 'microsoft.documentdb/databaseaccounts' -Name 'cosmos1' -Properties @{
                    ipRules = @([pscustomobject]@{ ipAddressOrRange = $s })
                    keyVaultKeyUri = $s
                }
                New-Resource -Type 'microsoft.search/searchservices' -Name 'srch1' -Properties @{
                    networkRuleSet = [pscustomobject]@{ ipRules = @([pscustomobject]@{ value = $s }) }
                }
                New-Resource -Type 'microsoft.containerservice/managedclusters' -Name 'aks1' -Properties @{
                    apiServerAccessProfile = [pscustomobject]@{ authorizedIPRanges = @($s) }
                }
                New-Resource -Type 'microsoft.databricks/workspaces' -Name 'dbw1' -Properties @{
                    parameters = [pscustomobject]@{ customVirtualNetworkId = [pscustomobject]@{ value = $s }; enableNoPublicIp = [pscustomobject]@{ value = $true } }
                }
                New-Resource -Type 'microsoft.insights/components' -Name 'ai1' -Properties @{ WorkspaceResourceId = $s; DisableLocalAuth = $true }
                New-Resource -Type 'microsoft.eventgrid/topics' -Name 'eg1' -Properties @{
                    inboundIpRules = @([pscustomobject]@{ ipMask = $s; action = 'Allow' })
                }
            )
            $shaped = ConvertFrom-ScoutInventory -Resources $resources -ResourceContainers @()

            ($shaped | ConvertTo-Json -Depth 8) | Should -Not -Match 'SENTINEL-MUST-NOT-APPEAR'

            # ...while the one legitimate key read out of the secret-bearing bag IS read.
            $shaped['redisCaches'][0].aadEnabled | Should -BeExactly $true
            # ...and the bool stand-ins still say what they stand in for.
            $shaped['sqlServers'][0].cmkEnabled | Should -BeExactly $true
            $shaped['sqlServers'][0].entraOnlyAuth | Should -BeExactly $true
            $shaped['databricksWorkspaces'][0].vnetInjected | Should -BeExactly $true
            $shaped['appInsights'][0].workspaceBased | Should -BeExactly $true
            $shaped['cosmosDbAccounts'][0].ipRuleCount | Should -BeExactly 1
            $shaped['eventGrid'][0].inboundIpRuleCount | Should -BeExactly 1
        }

        It 'gives the shaped Redis row no property named like a connection string or a configuration bag' {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.cache/redis' -Name 'r1' -Properties @{
                    sku = [pscustomobject]@{ name = 'Premium'; family = 'P'; capacity = 1 }
                    redisConfiguration = [pscustomobject]@{ 'rdb-storage-connection-string' = 'x'; 'aad-enabled' = 'false' }
                }
                New-Resource -Type 'microsoft.cache/redisenterprise' -Name 'r2' -Properties @{ highAvailability = 'Enabled' }
            ) -ResourceContainers @()
            foreach ($row in $shaped['redisCaches']) {
                @($row.PSObject.Properties.Name | Where-Object { $_ -match 'connection|configuration|secret|password|credential|sharedkey' }) |
                    Should -BeNullOrEmpty -Because "row '$($row.name)' must carry no secret-bearing property name"
            }
            $shaped['redisCaches'][0].aadEnabled | Should -BeExactly $false
        }

        It 'never asks the typed KQL pack for a secret-bearing property' {
            # The typed pack is the other half of every dataset above and is not executed here, so the
            # same rule is held against its text. Comment lines (the KQL `//` ones that explain what is
            # NEVER projected) are stripped first -- they name the very properties being banned.
            $collectDir = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'src', 'collect'
            $source = Get-Content -Raw (Join-Path -Path $collectDir -ChildPath 'Invoke-Collect.ps1')
            $pack = [regex]::Match($source, '(?s)\$q = @\{.*?\r?\n    \}').Value
            $pack | Should -Not -BeNullOrEmpty
            $kql = (($pack -split "`r?`n") | Where-Object { $_ -notmatch '^\s*(//|#)' }) -join "`n"

            $kql | Should -Not -Match 'sslCertificates'
            $kql | Should -Not -Match 'configuration\.secrets'
            $kql | Should -Not -Match 'logAnalyticsConfiguration'
            # keyVaultProperties holds a key's NAME, VERSION and VAULT URL, which identify a vault. The one
            # place the pack reads it is an Azure VMware Solution private cloud's customer-managed key,
            # for its two STATE enums only (AB#9300, 3.18.19: keyState Connected / AccessDenied and
            # versionType Fixed / AutoDetected). Every other read, or any read of the name, version or
            # URL, still fails here.
            $keyVaultReads = @([regex]::Matches($kql, 'keyVaultProperties\.?\w*') | ForEach-Object { $_.Value } | Sort-Object -Unique)
            @($keyVaultReads | Where-Object { $_ -notin @('keyVaultProperties.keyState', 'keyVaultProperties.versionType') }) |
                Should -BeNullOrEmpty -Because 'keyVaultProperties may be read only for keyState and versionType'
            $kql | Should -Not -Match 'administrators\.(sid|login|tenantId)'
            # redisConfiguration is read for exactly one key, by name -- never as a whole.
            $redisReads = @([regex]::Matches($kql, 'redisConfiguration[^\r\n]*') | ForEach-Object { $_.Value })
            $redisReads.Count | Should -BeGreaterThan 0 -Because 'the scan must have found the one aad-enabled read, or it asserts nothing'
            foreach ($read in $redisReads) { $read | Should -Match "redisConfiguration\['aad-enabled'\]" }
            # the unmanaged OS disk and the workspace/VNet ids only ever appear inside isnotempty().
            foreach ($path in 'osDisk\.vhd\.uri', 'customVirtualNetworkId\.value', 'WorkspaceResourceId', 'availabilitySet\.id') {
                $pathHits = @([regex]::Matches($kql, "[^\r\n]*$path[^\r\n]*"))
                $pathHits.Count | Should -BeGreaterThan 0 -Because "the scan must have found '$path', or it asserts nothing"
                foreach ($hit in $pathHits) {
                    $hit.Value | Should -Match "isnotempty\(tostring\(properties\.[A-Za-z.]*$path\)\)" -Because "'$path' must only be projected as a bool"
                }
            }
        }

        It 'carries the two bug fixes in the typed KQL as well as the shaper' {
            $collectDir = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'src', 'collect'
            $source = Get-Content -Raw (Join-Path -Path $collectDir -ChildPath 'Invoke-Collect.ps1')
            $pack = [regex]::Match($source, '(?s)\$q = @\{.*?\r?\n    \}').Value
            $redis = [regex]::Match($pack, "(?s)redisCaches = @'.*?\r?\n'@").Value
            $redis | Should -Match 'iff\(type =~ "microsoft\.cache/redis", tostring\(properties\.sku\.name\), tostring\(sku\.name\)\)'
            $redis | Should -Match 'skuFamily = tostring\(properties\.sku\.family\)'
            $firewall = [regex]::Match($pack, "(?s)azureFirewalls = @'.*?\r?\n'@").Value
            $firewall | Should -Match 'tier = tostring\(properties\.sku\.tier\)'
            $firewall | Should -Match 'zoneCount = array_length\(zones\)'
        }
    }

    Context 'null stays null; absence is never a false or a zero' {
        It 'reads <Dataset>.<Field> from an empty properties bag (expected: <Expected>; blank is null)' -ForEach $script:Phase4SparseCases {
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type $Type -Name 'sparse' -Properties @{}
            ) -ResourceContainers @()
            $row = @($shaped[$Dataset])[0]
            $row | Should -Not -BeNullOrEmpty -Because "the $Type row must still produce a $Dataset row"
            $row.PSObject.Properties[$Field] | Should -Not -BeNullOrEmpty -Because "$Dataset must always carry '$Field', even when it is null"
            $value = $row.PSObject.Properties[$Field].Value
            if ($null -eq $Expected) {
                ($null -eq $value) | Should -BeTrue -Because "a missing property is unknown (KQL null), not '$value'"
            }
            else {
                $value | Should -BeExactly $Expected
            }
        }

        It 'does not throw on a non-numeric count or capacity, it reads null (KQL toint of a non-number)' {
            { ConvertFrom-ScoutInventory -Resources @(
                    New-Resource -Type 'microsoft.web/serverfarms' -Name 'p1' -Extra @{ sku = [pscustomobject]@{ name = 'P1v3'; capacity = 'not-a-number' } }
                    New-Resource -Type 'microsoft.search/searchservices' -Name 's1' -Properties @{ partitionCount = 'abc' }
                ) -ResourceContainers @() } | Should -Not -Throw
            $shaped = ConvertFrom-ScoutInventory -Resources @(
                New-Resource -Type 'microsoft.web/serverfarms' -Name 'p1' -Extra @{ sku = [pscustomobject]@{ name = 'P1v3'; capacity = 'not-a-number' } }
            ) -ResourceContainers @()
            ($null -eq $shaped['appServicePlans'][0].instanceCount) | Should -BeTrue
        }
    }

    Context 'ids and locations on the datasets that lacked them' {
        It 'carries id and location on <Dataset>' -ForEach @(
            @{ Type = 'microsoft.eventhub/namespaces'; Dataset = 'eventHubNamespaces' }
            @{ Type = 'microsoft.operationalinsights/workspaces'; Dataset = 'logAnalyticsWorkspaces' }
            @{ Type = 'microsoft.containerservice/managedclusters'; Dataset = 'aksClusters' }
            @{ Type = 'microsoft.web/sites'; Dataset = 'webApps' }
            @{ Type = 'microsoft.sql/servers/databases'; Dataset = 'sqlDatabases' }
            @{ Type = 'microsoft.sql/servers'; Dataset = 'sqlServers' }
            @{ Type = 'microsoft.network/virtualnetworks'; Dataset = 'virtualNetworks' }
            @{ Type = 'microsoft.apimanagement/service'; Dataset = 'apiManagement' }
            @{ Type = 'microsoft.servicebus/namespaces'; Dataset = 'serviceBusNamespaces' }
        ) {
            $resource = New-Resource -Type $Type -Name 'thing'
            $shaped = ConvertFrom-ScoutInventory -Resources @($resource) -ResourceContainers @()
            $row = @($shaped[$Dataset])[0]
            $row.id | Should -Be $resource.id
            $row.location | Should -Be 'eastus'
        }
    }
}

Describe 'Invoke-Collect -FromInventory — collects once, not twice' {

    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        # Stub the Az.ResourceGraph surface so the collector runs with no Azure connection and we
        # can count exactly which queries still reach Resource Graph.
        function Import-Module {             [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }
        . "$root/src/collect/Invoke-Collect.ps1"
    }

    It 'sends only the query that cannot be served from inventory to Resource Graph' {
        $script:argQueries = @()
        function Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip,
                [string] $ManagementGroup, [string[]] $Subscription,
                [string] $ErrorAction
            )
            $script:argQueries += $Query
            return @()
        }

        $inventory = [pscustomobject]@{
            Resources          = @(
                [pscustomobject]@{
                    id = '/subscriptions/sub1/resourceGroups/rg1/providers/microsoft.keyvault/vaults/kv1'
                    name = 'kv1'; type = 'microsoft.keyvault/vaults'; location = 'eastus'
                    resourceGroup = 'rg1'; subscriptionId = 'sub1'
                    properties = [pscustomobject]@{ enableSoftDelete = $true; enablePurgeProtection = $true }
                }
            )
            ResourceContainers = @(
                [pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'Sub One'; subscriptionId = 'sub1'; properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null }
            )
        }

        $collect = Invoke-Collect -FromInventory $inventory

        # Exactly one query type still goes to Azure: the SecurityResources pricings lookup.
        $script:argQueries.Count | Should -Be 1
        $script:argQueries[0] | Should -Match 'SecurityResources'
        $script:argQueries[0] | Should -Match 'microsoft.security/pricings'

        # And the assessment data really was populated from the inventory rows.
        $collect.domains.security.keyVaults.Count | Should -Be 1
        $collect.domains.security.keyVaults[0].softDelete | Should -BeExactly $true
        $collect.subscriptions.Count | Should -Be 1
        $collect.subscriptions[0].id | Should -Be 'sub1'
    }

    It 'still queries Resource Graph for every query under -Source TypedQueries' {
        $script:argQueries = @()
        function Search-AzGraph {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [string] $Query, [int] $First, [int] $Skip,
                [string] $ManagementGroup, [string[]] $Subscription,
                [string] $ErrorAction
            )
            $script:argQueries += $Query
            return @()
        }

        # This was the DEFAULT behaviour up to and including v2.7.0, and is the "before"
        # number the AB#5648 inversion is measured against. It is still reachable on demand
        # (the typed pack is the reference implementation ConvertFrom-ScoutInventory is
        # verified field-for-field against), so it stays pinned here.
        Invoke-Collect -Source TypedQueries | Out-Null
        $script:argQueries.Count | Should -BeGreaterThan 30
    }
}
