#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300 (3.18.10): collectors for resources that discovery found but nothing read.

    Rows are shaped like the live Resource Graph rows seen on 2026-11-24 (Azure Local machines,
    Arc SQL databases, guest configuration, Update Manager, alert processing rules, Defender
    automations, Kubernetes extensions, run commands, partner monitors) or, for types absent from
    the test tenants, like Microsoft's documented schema. No Azure calls.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . "$script:RepoRoot/src/pipeline/Get-ScoutCollectorDefinition.ps1"
    . "$script:RepoRoot/src/pipeline/Invoke-ScoutDeclarativeCollector.ps1"
    . "$script:RepoRoot/src/Get-AZSCSafeProperty.ps1"
    . "$script:RepoRoot/src/Get-AZTICollectedValue.ps1"
    . "$script:RepoRoot/src/Get-AZSCIdSegment.ps1"

    function Invoke-NewCollector {
        param([string] $Category, [string] $Name, [object[]] $Resources)
        $definition = Get-ScoutCollectorDefinition -Path "$script:RepoRoot/manifests/collectors/$Category/$Name.psd1"
        $context = @{
            ScriptRoot = $script:RepoRoot; Subscriptions = @([pscustomobject]@{ id = 'sub-1'; Name = 'Subscription One' })
            InTag = $false; Resources = @($Resources); Retirements = @(); Task = 'Processing'; File = $null
            SmaResources = $null; TableStyle = 'Light20'; Unsupported = @(); RunTime = [datetime]'2026-11-24T00:00:00Z'
        }
        @(Invoke-ScoutDeclarativeCollector -Definition $definition -Context $context -WarningAction Stop)
    }

    function New-Row {
        param([string] $Type, [string] $Id, [object] $Properties, [object] $Tags = $null)
        [pscustomobject]@{
            id = $Id; name = ($Id -split '/')[-1]; type = $Type; subscriptionId = 'sub-1'; resourceGroup = 'rg-1'
            location = 'eastus'; properties = $Properties; tags = $Tags
        }
    }
}

Describe 'Collectors for discovered types (AB#9300)' {
    It 'reads an Azure Local machine''s hardware, OS and connectivity' {
        $row = New-Row -Type 'microsoft.azurestackhci/edgemachines' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.AzureStackHCI/edgeMachines/node-01' -Properties ([pscustomobject]@{
                provisioningState = 'Succeeded'; connectivityStatus = 'Connected'; lastSyncTimestamp = '2026-11-24T03:30:56Z'
                reportedProperties = [pscustomobject]@{
                    hardwareProfile = [pscustomobject]@{ manufacturer = 'Contoso'; model = 'AX-1'; serialNumber = 'SN1'; processorType = 'Xeon'; cpuSockets = 2; cpuCores = 64; memoryCapacityInGb = 1024 }
                    osProfile = [pscustomobject]@{ osSku = 'Azure Stack HCI'; osVersion = '10.0.26100.1'; bootType = 'UEFI' }
                    storageProfile = [pscustomobject]@{ disks = @([pscustomobject]@{}, [pscustomobject]@{}, [pscustomobject]@{}) }
                    networkProfile = [pscustomobject]@{ nicDetails = @([pscustomobject]@{}, [pscustomobject]@{}) }
                    workloadInventory = @([pscustomobject]@{ workloadType = 'VirtualMachine' })
                }
            })
        $r = @(Invoke-NewCollector -Category Hybrid -Name AzureLocalMachines -Resources $row)
        $r.Count | Should -Be 1
        $r[0].'Connectivity Status' | Should -Be 'Connected'
        $r[0].'Model' | Should -Be 'AX-1'
        $r[0].'CPU Cores' | Should -Be 64
        $r[0].'Memory (GB)' | Should -Be 1024
        $r[0].'OS Version' | Should -Be '10.0.26100.1'
        $r[0].'Disks' | Should -Be 3
        $r[0].'Network Adapters' | Should -Be 2
        $r[0].'Workloads' | Should -Be 1
        $r[0].'Subscription' | Should -Be 'Subscription One'
    }

    It 'reads an Arc SQL database with its instance taken from the resource ID' {
        $row = New-Row -Type 'microsoft.azurearcdata/sqlserverinstances/databases' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.AzureArcData/sqlServerInstances/sql-01/databases/Sales' -Properties ([pscustomobject]@{
                state = 'Online'; recoveryMode = 'Full'; compatibilityLevel = 170; sizeMB = 15800; isReadOnly = $false
                databaseOptions = [pscustomobject]@{ isEncrypted = $false; isTrustworthyOn = $false; isAutoShrinkOn = $false }
            })
        $r = @(Invoke-NewCollector -Category Hybrid -Name ArcSQLDatabases -Resources $row)
        $r[0].'SQL Instance' | Should -Be 'sql-01'
        $r[0].'Name' | Should -Be 'Sales'
        $r[0].'Recovery Model' | Should -Be 'Full'
        $r[0].'Encrypted' | Should -BeFalse
    }

    It 'reads guest configuration compliance and the machine it targets' {
        $row = New-Row -Type 'microsoft.guestconfiguration/guestconfigurationassignments' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/AzureWindowsBaseline' -Properties ([pscustomobject]@{
                complianceStatus = 'NonCompliant'; lastComplianceStatusChecked = '2026-11-24T05:01:17Z'
                targetResourceId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1'
                policyAssignmentId = '/providers/Microsoft.Management/managementGroups/mg/providers/Microsoft.Authorization/policyAssignments/baseline'
                guestConfiguration = [pscustomobject]@{ name = 'AzureWindowsBaseline'; assignmentType = 'Audit'; assignmentSource = 'Azure Policy'; contentType = 'Builtin' }
            })
        $r = @(Invoke-NewCollector -Category Management -Name GuestConfigurationAssignments -Resources $row)
        $r[0].'Machine' | Should -Be 'vm-1'
        $r[0].'Machine Type' | Should -Be 'virtualMachines'
        $r[0].'Compliance Status' | Should -Be 'NonCompliant'
        $r[0].'Policy Assignment' | Should -Be 'baseline'
    }

    It 'tells a dynamic Update Manager scope from a single-machine assignment' {
        $dynamic = New-Row -Type 'microsoft.maintenance/configurationassignments' -Id '/subscriptions/sub-1/providers/Microsoft.Maintenance/configurationAssignments/dyn' -Properties ([pscustomobject]@{
                maintenanceConfigurationId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Maintenance/maintenanceConfigurations/patch-w1'
                filter = [pscustomobject]@{ osTypes = @('Windows', 'Linux'); resourceTypes = @('microsoft.compute/virtualmachines'); locations = @('eastus') }
            })
        $single = New-Row -Type 'microsoft.maintenance/configurationassignments' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1/providers/Microsoft.Maintenance/configurationAssignments/one' -Properties ([pscustomobject]@{
                maintenanceConfigurationId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Maintenance/maintenanceConfigurations/patch-w2'
                resourceId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1'
            })
        $r = @(Invoke-NewCollector -Category Management -Name UpdateManagerAssignments -Resources @($dynamic, $single))
        $d = $r | Where-Object { $_.Name -eq 'dyn' }; $s = $r | Where-Object { $_.Name -eq 'one' }
        $d.'Scope' | Should -Be 'Dynamic'
        $d.'Filter OS Types' | Should -Be 'Linux, Windows'
        $d.'Maintenance Configuration' | Should -Be 'patch-w1'
        $s.'Scope' | Should -Be 'Resource'
        $s.'Target' | Should -Be 'vm-1'
    }

    It 'shows an alert processing rule''s action and conditions' {
        $row = New-Row -Type 'microsoft.alertsmanagement/actionrules' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.AlertsManagement/actionRules/suppress-dev' -Properties ([pscustomobject]@{
                enabled = $true; description = 'Quiet hours'; scopes = @('/subscriptions/sub-1')
                actions = @([pscustomobject]@{ actionType = 'RemoveAllActionGroups' })
                conditions = @([pscustomobject]@{ field = 'Severity'; operator = 'Equals'; values = @('Sev3', 'Sev4') })
            })
        $r = @(Invoke-NewCollector -Category Monitor -Name AlertProcessingRules -Resources $row)
        $r[0].'Action' | Should -Be 'RemoveAllActionGroups'
        $r[0].'Conditions' | Should -Be 'Severity Equals Sev3|Sev4'
        $r[0].'Action Groups' | Should -Be 0
    }

    It 'never projects a run command''s script, parameters or output' {
        $row = New-Row -Type 'microsoft.hybridcompute/machines/runcommands' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.HybridCompute/machines/arc-01/runCommands/audit' -Properties ([pscustomobject]@{
                provisioningState = 'Succeeded'; timeoutInSeconds = 300; asyncExecution = $false
                source = [pscustomobject]@{ script = 'net user admin P@ssw0rd-SECRET /add' }
                parameters = @([pscustomobject]@{ name = 'pwd'; value = 'SECRET-PARAM' })
                instanceView = [pscustomobject]@{ executionState = 'Succeeded'; exitCode = 0; output = 'SECRET-OUTPUT'; startTime = '2026-08-07T01:03:58Z' }
            })
        $r = @(Invoke-NewCollector -Category Hybrid -Name ArcMachineRunCommands -Resources $row)
        $r[0].'Machine' | Should -Be 'arc-01'
        $r[0].'Execution State' | Should -Be 'Succeeded'
        ($r[0] | ConvertTo-Json -Depth 5 -Compress) | Should -Not -Match 'SECRET'
    }

    It 'never projects Kubernetes extension configuration or protected settings' {
        $row = New-Row -Type 'microsoft.kubernetesconfiguration/extensions' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Kubernetes/connectedClusters/aks-01/providers/Microsoft.KubernetesConfiguration/extensions/flux' -Properties ([pscustomobject]@{
                ExtensionType = 'microsoft.flux'; Version = '1.9.0'; InstallState = 'Installed'; ProvisioningState = 'Succeeded'; ReleaseTrain = 'stable'; AutoUpgradeMinorVersion = $true
                ConfigurationSettings = [pscustomobject]@{ token = 'SECRET-SETTING' }
                ConfigurationProtectedSettings = [pscustomobject]@{ key = 'SECRET-PROTECTED' }
            })
        $r = @(Invoke-NewCollector -Category Hybrid -Name KubernetesExtensions -Resources $row)
        $r[0].'Cluster' | Should -Be 'aks-01'
        $r[0].'Cluster Type' | Should -Be 'Microsoft.Kubernetes/connectedClusters'
        $r[0].'Extension Type' | Should -Be 'microsoft.flux'
        ($r[0] | ConvertTo-Json -Depth 5 -Compress) | Should -Not -Match 'SECRET'
    }

    It 'reads Datadog and Elastic monitors without their user contact details' {
        $datadog = New-Row -Type 'microsoft.datadog/monitors' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Datadog/monitors/dd' -Properties ([pscustomobject]@{
                monitoringStatus = 'Enabled'; marketplaceSubscriptionStatus = 'Active'; provisioningState = 'Succeeded'
                userInfo = [pscustomobject]@{ emailAddress = 'person@example.invalid'; name = 'A Person' }
            })
        $elastic = New-Row -Type 'microsoft.elastic/monitors' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Elastic/monitors/es' -Properties ([pscustomobject]@{
                monitoringStatus = 'Disabled'; saaSAzureSubscriptionStatus = 'Subscribed'; provisioningState = 'Succeeded'
            })
        $r = @(Invoke-NewCollector -Category Monitor -Name PartnerMonitors -Resources @($datadog, $elastic))
        ($r | Where-Object { $_.Name -eq 'dd' }).'Marketplace Status' | Should -Be 'Active'
        ($r | Where-Object { $_.Name -eq 'es' }).'Marketplace Status' | Should -Be 'Subscribed'
        ($r | Where-Object { $_.Name -eq 'es' }).'Provider' | Should -Be 'microsoft.elastic'
        ($r | ConvertTo-Json -Depth 5 -Compress) | Should -Not -Match 'example\.invalid|A Person'
    }

    It 'reads a backup vault''s immutability, soft delete and resource guard protection' {
        $row = New-Row -Type 'microsoft.dataprotection/backupvaults' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.DataProtection/backupVaults/bv-1' -Properties ([pscustomobject]@{
                provisioningState = 'Succeeded'; isVaultProtectedByResourceGuard = $true
                storageSettings = @([pscustomobject]@{ datastoreType = 'VaultStore'; type = 'GeoRedundant' })
                securitySettings = [pscustomobject]@{ immutabilitySettings = [pscustomobject]@{ state = 'Locked' }; softDeleteSettings = [pscustomobject]@{ state = 'AlwaysOn'; retentionDurationInDays = 14 } }
                featureSettings = [pscustomobject]@{ crossRegionRestoreSettings = [pscustomobject]@{ state = 'Enabled' }; crossSubscriptionRestoreSettings = [pscustomobject]@{ state = 'Disabled' } }
                monitoringSettings = [pscustomobject]@{ azureMonitorAlertSettings = [pscustomobject]@{ alertsForAllJobFailures = 'Enabled' } }
            })
        $r = @(Invoke-NewCollector -Category Management -Name BackupVaults -Resources $row)
        $r[0].'Storage Redundancy' | Should -Be 'GeoRedundant'
        $r[0].'Immutability' | Should -Be 'Locked'
        $r[0].'Soft Delete' | Should -Be 'AlwaysOn'
        $r[0].'Soft Delete Retention (days)' | Should -Be 14
        $r[0].'Protected by Resource Guard' | Should -BeTrue
    }

    It 'reads Arc VMware inventory of mixed kinds in one collector' {
        $ds = New-Row -Type 'microsoft.connectedvmwarevsphere/datastores' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.ConnectedVMwarevSphere/datastores/ds1' -Properties ([pscustomobject]@{
                vCenterId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.ConnectedVMwarevSphere/vcenters/vc-01'; moName = 'datastore1'; moRefId = 'datastore-11'; capacityGB = 2048; freeSpaceGB = 512; provisioningState = 'Succeeded'
            })
        $host1 = New-Row -Type 'microsoft.connectedvmwarevsphere/hosts' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.ConnectedVMwarevSphere/hosts/h1' -Properties ([pscustomobject]@{
                vCenterId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.ConnectedVMwarevSphere/vcenters/vc-01'; moName = 'esx01'; memorySizeGB = 768
            })
        $r = @(Invoke-NewCollector -Category Hybrid -Name ArcVMwareInventory -Resources @($ds, $host1))
        ($r | Where-Object { $_.Name -eq 'ds1' }).'Kind' | Should -Be 'datastores'
        ($r | Where-Object { $_.Name -eq 'ds1' }).'vCenter' | Should -Be 'vc-01'
        @($r | Where-Object { $_.Name -eq 'ds1' })[0]['Free (GB)'] | Should -Be 512
        @($r | Where-Object { $_.Name -eq 'h1' })[0]['Memory (GB)'] | Should -Be 768
    }

    It 'reads an SCVMM cloud and template by their own name fields' {
        $cloud = New-Row -Type 'microsoft.scvmm/clouds' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.ScVmm/clouds/c1' -Properties ([pscustomobject]@{ vmmServerId = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.ScVmm/vmmServers/vmm-01'; cloudName = 'Production' })
        $template = New-Row -Type 'microsoft.scvmm/virtualmachinetemplates' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.ScVmm/virtualMachineTemplates/t1' -Properties ([pscustomobject]@{ vmmServerId = '/x/vmm-01'; osName = 'Windows Server 2025'; osType = 'Windows'; cpuCount = 4; memoryMB = 8192 })
        $r = @(Invoke-NewCollector -Category Hybrid -Name ArcSCVMMInventory -Resources @($cloud, $template))
        ($r | Where-Object { $_.Name -eq 'c1' }).'Inventory Name' | Should -Be 'Production'
        ($r | Where-Object { $_.Name -eq 'c1' }).'VMM Server' | Should -Be 'vmm-01'
        ($r | Where-Object { $_.Name -eq 't1' }).'Inventory Name' | Should -Be 'Windows Server 2025'
        @($r | Where-Object { $_.Name -eq 't1' })[0]['Memory (MB)'] | Should -Be 8192
    }

    It 'reads Azure Local VM NICs, disks and connectors from their documented paths' {
        $nic = New-Row -Type 'microsoft.azurestackhci/networkinterfaces' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.AzureStackHCI/networkInterfaces/nic1' -Properties ([pscustomobject]@{
                macAddress = '00:15:5D:01:02:03'; provisioningState = 'Succeeded'
                ipConfigurations = @([pscustomobject]@{ name = 'ip1'; properties = [pscustomobject]@{ privateIPAddress = '10.0.0.5'; subnet = [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.AzureStackHCI/logicalNetworks/lnet-prod' } } })
                dnsSettings = [pscustomobject]@{ dnsServers = @('10.0.0.10', '10.0.0.11') }
            })
        $r = @(Invoke-NewCollector -Category Hybrid -Name AzureLocalNetworkInterfaces -Resources $nic)
        $r[0].'Private IP' | Should -Be '10.0.0.5'
        $r[0].'Logical Network' | Should -Be 'lnet-prod'
        $r[0].'DNS Servers' | Should -Be '10.0.0.10, 10.0.0.11'

        $connector = New-Row -Type 'microsoft.security/securityconnectors' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Security/securityConnectors/aws' -Properties ([pscustomobject]@{
                environmentName = 'AWS'; hierarchyIdentifier = '123456789012'; environmentData = [pscustomobject]@{ environmentType = 'AwsAccount' }
                offerings = @([pscustomobject]@{ offeringType = 'CspmMonitorAws' }, [pscustomobject]@{ offeringType = 'DefenderForServersAws' })
            })
        $c = @(Invoke-NewCollector -Category Security -Name DefenderSecurityConnectors -Resources $connector)
        $c[0].'Environment' | Should -Be 'AWS'
        $c[0].'Offerings' | Should -Be 'CspmMonitorAws, DefenderForServersAws'
    }

    It 'reads all three Virtual WAN gateway kinds with their own connection lists' {
        $s2s = New-Row -Type 'microsoft.network/vpngateways' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/vpnGateways/s2s' -Properties ([pscustomobject]@{
                virtualHub = [pscustomobject]@{ id = '/x/virtualHubs/hub-east' }; vpnGatewayScaleUnit = 2; connections = @([pscustomobject]@{}, [pscustomobject]@{}); bgpSettings = [pscustomobject]@{ asn = 65515 } })
        $er = New-Row -Type 'microsoft.network/expressroutegateways' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/expressRouteGateways/er' -Properties ([pscustomobject]@{
                virtualHub = [pscustomobject]@{ id = '/x/virtualHubs/hub-east' }; autoScaleConfiguration = [pscustomobject]@{ bounds = [pscustomobject]@{ min = 1; max = 4 } }; expressRouteConnections = @([pscustomobject]@{}) })
        $p2s = New-Row -Type 'microsoft.network/p2svpngateways' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/p2sVpnGateways/p2s' -Properties ([pscustomobject]@{
                vpnServerConfiguration = [pscustomobject]@{ id = '/x/vpnServerConfigurations/aad-cfg' }; p2SConnectionConfigurations = @([pscustomobject]@{}) })
        $r = @(Invoke-NewCollector -Category Networking -Name VirtualWanGateways -Resources @($s2s, $er, $p2s))
        $a = @($r | Where-Object { $_.Name -eq 's2s' })[0]; $b = @($r | Where-Object { $_.Name -eq 'er' })[0]; $c = @($r | Where-Object { $_.Name -eq 'p2s' })[0]
        $a['Kind'] | Should -Be 'vpngateways'; $a['Connections'] | Should -Be 2; $a['BGP ASN'] | Should -Be 65515; $a['Virtual Hub'] | Should -Be 'hub-east'
        $b['Scale Units'] | Should -Be '1-4'; $b['Connections'] | Should -Be 1
        $c['VPN Server Configuration'] | Should -Be 'aad-cfg'; $c['Connections'] | Should -Be 1
    }

    It 'never projects secrets from appliances, databases, session pools, scripts or SSH keys' {
        $rows = @(
            @{ Category = 'Networking'; Name = 'NetworkVirtualAppliances'; Row = (New-Row -Type 'microsoft.network/networkvirtualappliances' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/networkVirtualAppliances/nva' -Properties ([pscustomobject]@{ nvaSku = [pscustomobject]@{ vendor = 'contoso'; marketPlaceVersion = '1.2' }; sshPublicKey = 'ssh-rsa SECRET-KEY'; cloudInitConfiguration = 'SECRET-CLOUDINIT' })) }
            @{ Category = 'Networking'; Name = 'VpnServerConfigurations'; Row = (New-Row -Type 'microsoft.network/vpnserverconfigurations' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Network/vpnServerConfigurations/cfg' -Properties ([pscustomobject]@{ vpnProtocols = @('OpenVPN'); radiusServerSecret = 'SECRET-RADIUS' })) }
            @{ Category = 'Databases'; Name = 'OracleDatabaseAtAzure'; Row = (New-Row -Type 'oracle.database/autonomousdatabases' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Oracle.Database/autonomousDatabases/adb' -Properties ([pscustomobject]@{ dbVersion = '23ai'; computeCount = 4; adminPassword = 'SECRET-PASSWORD' })) }
            @{ Category = 'Containers'; Name = 'ContainerAppSessionPools'; Row = (New-Row -Type 'microsoft.app/sessionpools' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.App/sessionPools/pool' -Properties ([pscustomobject]@{ containerType = 'PythonLTS'; secrets = @([pscustomobject]@{ name = 'k'; value = 'SECRET-VALUE' }) })) }
            @{ Category = 'Management'; Name = 'DeploymentScripts'; Row = (New-Row -Type 'microsoft.resources/deploymentscripts' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Resources/deploymentScripts/ds' -Properties ([pscustomobject]@{ azPowerShellVersion = '12.0'; scriptContent = 'Write-Output SECRET-SCRIPT'; environmentVariables = @([pscustomobject]@{ name = 'pw'; secureValue = 'SECRET-ENV' }) })) }
            @{ Category = 'Compute'; Name = 'SshPublicKeys'; Row = (New-Row -Type 'microsoft.compute/sshpublickeys' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Compute/sshPublicKeys/key' -Properties ([pscustomobject]@{ publicKey = 'ssh-ed25519 SECRET-PUBKEY' })) }
        )
        foreach ($case in $rows) {
            $r = @(Invoke-NewCollector -Category $case.Category -Name $case.Name -Resources $case.Row)
            $r.Count | Should -Be 1 -Because $case.Name
            ($r[0] | ConvertTo-Json -Depth 5 -Compress) | Should -Not -Match 'SECRET' -Because $case.Name
        }
        @(Invoke-NewCollector -Category Compute -Name SshPublicKeys -Resources $rows[5].Row)[0]['Key Present'] | Should -BeTrue
    }

    It 'reads AKS Arc clusters, Oracle Exadata, deployment stacks and Log Analytics clusters' {
        $aks = New-Row -Type 'microsoft.hybridcontainerservice/provisionedclusterinstances' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Kubernetes/connectedClusters/aks-local-01/providers/Microsoft.HybridContainerService/provisionedClusterInstances/default' -Properties ([pscustomobject]@{
                kubernetesVersion = '1.31.2'; controlPlane = [pscustomobject]@{ count = 3 }; agentPoolProfiles = @([pscustomobject]@{ count = 2 }, [pscustomobject]@{ count = 3 }); licenseProfile = [pscustomobject]@{ azureHybridBenefit = 'True' } })
        $a = @(Invoke-NewCollector -Category Hybrid -Name AksArcClusters -Resources $aks)[0]
        $a['Connected Cluster'] | Should -Be 'aks-local-01'; $a['Agent Nodes'] | Should -Be 5; $a['Control Plane Nodes'] | Should -Be 3

        $exa = New-Row -Type 'oracle.database/cloudexadatainfrastructures' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Oracle.Database/cloudExadataInfrastructures/exa' -Properties ([pscustomobject]@{ shape = 'Exadata.X11M'; computeCount = 2; storageCount = 3; lifecycleState = 'Available' })
        $e = @(Invoke-NewCollector -Category Databases -Name OracleDatabaseAtAzure -Resources $exa)[0]
        $e['Kind'] | Should -Be 'cloudexadatainfrastructures'; $e['Shape'] | Should -Be 'Exadata.X11M'; $e['Lifecycle State'] | Should -Be 'Available'

        $stack = New-Row -Type 'microsoft.resources/deploymentstacks' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Resources/deploymentStacks/lz' -Properties ([pscustomobject]@{ denySettings = [pscustomobject]@{ mode = 'denyWriteAndDelete'; applyToChildScopes = $true; excludedPrincipals = @('p1') }; actionOnUnmanage = [pscustomobject]@{ resources = 'detach' }; resources = @([pscustomobject]@{}, [pscustomobject]@{}) })
        $s = @(Invoke-NewCollector -Category Management -Name DeploymentStacks -Resources $stack)[0]
        $s['Deny Mode'] | Should -Be 'denyWriteAndDelete'; $s['Managed Resources'] | Should -Be 2; $s['Excluded Principals'] | Should -Be 1

        $cluster = New-Row -Type 'microsoft.operationalinsights/clusters' -Id '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.OperationalInsights/clusters/la-ded' -Properties ([pscustomobject]@{ billingType = 'Cluster'; isDoubleEncryptionEnabled = $true; keyVaultProperties = [pscustomobject]@{ keyName = 'la-cmk' }; associatedWorkspaces = @([pscustomobject]@{}) })
        $cluster | Add-Member -NotePropertyName sku -NotePropertyValue ([pscustomobject]@{ name = 'CapacityReservation'; capacity = 500 })
        $l = @(Invoke-NewCollector -Category Monitor -Name LogAnalyticsClusters -Resources $cluster)[0]
        $l['Capacity (GB/day)'] | Should -Be 500; $l['Customer Key'] | Should -Be 'la-cmk'; $l['Workspaces'] | Should -Be 1
    }

    It 'produces a row with blanks, not an error, for a sparse row of every new type' {
        foreach ($manifest in Get-ChildItem "$script:RepoRoot/manifests/collectors" -Recurse -Filter '*.psd1' | Where-Object { (Get-Content $_.FullName -Raw) -match 'Hand-authored collector \(AB#9300\)' }) {
            $definition = Get-ScoutCollectorDefinition -Path $manifest.FullName
            foreach ($type in $definition.ResourceTypes) {
                $row = New-Row -Type $type -Id "/subscriptions/sub-1/resourceGroups/rg-1/providers/$type/sparse" -Properties ([pscustomobject]@{})
                $rows = @(Invoke-NewCollector -Category $manifest.Directory.Name -Name $manifest.BaseName -Resources $row)
                $rows.Count | Should -Be 1 -Because "$($manifest.BaseName) / $type"
            }
        }
    }
}
