#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6820 (AVS workload + AVS Landing Zone) / AB#6821 (CASA) -- Feature AB#6748, Epic AB#6454.

    Covers:
      - the two new rule files load (avs.workload.yaml, caf.avslandingzone.yaml) and the
        `requires:` gate reports Unknown, not a manufactured Pass, on an estate with no AVS
        private cloud
      - casa.security.yaml loads and scores real collected data (no requires gate -- CASA is
        tenant-wide)
      - the registry entries are wired and selectable
      - the collect-pipeline wiring this story added: privateClouds shaping (both the typed KQL
        path and the ConvertFrom-ScoutInventory single-pass path agree) and the Key Vault child
        (secrets/keys) extraction in Invoke-Collect

    No Azure connection. Az.ResourceGraph/Az.Accounts imports and Search-AzGraph are stubbed.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Get-RuleSet.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Resolve-JsonPath.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Resolve-RuleJoin.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Invoke-Rule.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/Invoke-Assessment.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    $script:Manifest = Import-PowerShellDataFile (Join-Path -Path $script:Root -ChildPath 'manifests/assessments.psd1')

    function New-EmptyCollect {
        [pscustomobject]@{
            subscriptions = @(); tags = @()
            networking    = [pscustomobject]@{ virtualNetworks = @(); subnets = @(); azureFirewalls = @(); firewallPolicyRuleGroups = @(); vpnGateways = @(); privateEndpoints = @(); privateDnsZones = @(); nsgPublicInbound = @() }
            compute       = [pscustomobject]@{ virtualMachines = @(); privateClouds = @() }
            management    = [pscustomobject]@{ recoveryVaults = @(); deployments = @(); logAnalyticsWorkspaces = @(); backupProtectedItems = @() }
            security      = [pscustomobject]@{ defenderPlans = @() }
            governance    = [pscustomobject]@{ managementGroups = @(); policyAssignments = @(); roleAssignments = @(); budgets = @(); resourceLocks = @(); pimEligibility = @(); classicAdministrators = @() }
            costCleanup   = [pscustomobject]@{ orphanedDisks = @(); orphanedPips = @() }
            opsPosture    = [pscustomobject]@{ diagnosticCoverage = @() }
            domains       = [pscustomobject]@{
                storage = [pscustomobject]@{ storageAccounts = @(); snapshots = @(); managedDisks = @(); diskEncryptionSets = @() }
                databases = [pscustomobject]@{ sqlDatabases = @(); sqlServers = @(); sqlDefenderPricing = @() }
                web = [pscustomobject]@{ webApps = @() }
                containers = [pscustomobject]@{ aksClusters = @(); containerRegistries = @() }
                security = [pscustomobject]@{ keyVaults = @(); keyVaultSecrets = @(); keyVaultKeys = @() }
                ai = [pscustomobject]@{ cognitiveAccounts = @() }
                hybrid = [pscustomobject]@{ arcServers = @(); arcExtensions = @(); azureLocalClusters = @() }
                integration = [pscustomobject]@{ eventHubNamespaces = @(); apiManagement = @(); serviceBusNamespaces = @() }
                iot = [pscustomobject]@{ iotHubs = @(); dpsInstances = @(); digitalTwinsInstances = @() }
                migration = [pscustomobject]@{ migrateProjects = @(); migrationServices = @(); discoverySites = @() }
                analytics = [pscustomobject]@{ synapseWorkspaces = @(); purviewAccounts = @() }
                management = [pscustomobject]@{ policyComplianceStates = @(); policyInitiatives = @() }
            }
            advisor = @()
        }
    }
}

Describe 'AB#6820 -- avs.workload.yaml and caf.avslandingzone.yaml load and gate correctly' {

    It 'both load through Get-RuleSet with the frameworkversion the gate requires' {
        $set = Get-RuleSet -Patterns @('avs.workload', 'caf.avslandingzone')
        $set.Count | Should -Be 2
        ($set | Where-Object Framework -eq 'AVS').Rules.Count | Should -Be 27
        ($set | Where-Object Framework -eq 'CAF').Rules.Count | Should -Be 25
        $set | ForEach-Object { $_.FrameworkVersion | Should -Not -BeNullOrEmpty }
    }

    It 'reports the whole set Unknown, not a manufactured Pass, on an estate with zero AVS private clouds' {
        $set = Get-RuleSet -Patterns @('avs.workload', 'caf.avslandingzone')
        $collect = New-EmptyCollect
        $findings = Invoke-Assessment -Collect $collect -RuleSet $set -Assessment 'Workload: AVS'

        $findings.Count | Should -Be (27 + 25)
        ($findings | Where-Object Status -ne 'Unknown') | Should -BeNullOrEmpty -Because 'requires: gates the whole set when compute.privateClouds[*] returns zero rows'
        ($findings | Select-Object -First 1).Remediation | Should -Match 'Not assessed'
    }

    It 'is proven non-vacuous: the SAME rule set scores real findings once a private cloud is in scope' {
        $set = Get-RuleSet -Patterns @('avs.workload', 'caf.avslandingzone')
        $collect = New-EmptyCollect
        $collect.compute.privateClouds = @(
            [pscustomobject]@{
                id = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.AVS/privateClouds/pc1'
                name = 'pc1'; resourceGroup = 'rg1'; subscriptionId = 's1'; sku = 'av36'
                availabilityStrategy = 'None'; availabilityZone = $null; clusterSize = 3
                expressRouteCircuitId = $null; encryptionStatus = 'Disabled'; internet = 'Disabled'
                identitySourceCount = 0; externalCloudLinkCount = 0
            }
        )
        $findings = Invoke-Assessment -Collect $collect -RuleSet $set -Assessment 'Workload: AVS'

        ($findings | Where-Object Status -eq 'Unknown') | Should -BeNullOrEmpty -Because 'the gate is satisfied once compute.privateClouds has a row'
        $reFail = $findings | Where-Object Id -eq 'WAF-AVS-RE-04'
        $reFail.Status | Should -Be 'Fail' -Because 'the fixture private cloud has availabilityStrategy None, which WAF-AVS-RE-04 flags'
        $lzFail = $findings | Where-Object Id -eq 'AVS-C5'
        $lzFail.Status | Should -Be 'Fail' -Because 'the fixture private cloud has no ExpressRoute circuit id, which AVS-C5 flags'
    }

    It 'is registered in manifests/assessments.psd1 with a matching RequiresData gate' {
        $script:Manifest.Keys | Should -Contain 'Workload: AVS'
        $script:Manifest.Keys | Should -Contain 'Workload: AVS Landing Zone'
        $script:Manifest['Workload: AVS'].Rules | Should -Be @('avs.workload')
        $script:Manifest['Workload: AVS Landing Zone'].Rules | Should -Be @('caf.avslandingzone')
        $script:Manifest['Workload: AVS'].RequiresData | Should -Be @('$.compute.privateClouds[*]')
        $script:Manifest['Workload: AVS Landing Zone'].RequiresData | Should -Be @('$.compute.privateClouds[*]')
    }
}

Describe 'AB#6821 -- casa.security.yaml loads and scores real collected data' {

    It 'loads through Get-RuleSet with 32 rules and a frameworkversion' {
        $set = Get-RuleSet -Patterns @('casa.*')
        $set.Count | Should -Be 1
        $set[0].Framework | Should -Be 'CASA'
        $set[0].Rules.Count | Should -Be 32
        $set[0].FrameworkVersion | Should -Not -BeNullOrEmpty
    }

    It 'carries no requires: gate -- CASA is tenant-wide and scores even a sparsely-collected estate' {
        $set = Get-RuleSet -Patterns @('casa.*')
        @($set[0].Requires).Count | Should -Be 0
    }

    It 'is proven non-vacuous: CASA-CO-01 flips from Fail to Pass when a Key Vault key is collected' {
        $set = Get-RuleSet -Patterns @('casa.*')
        $collect = New-EmptyCollect
        $before = Invoke-Assessment -Collect $collect -RuleSet $set -Assessment 'Microsoft: CASA'
        ($before | Where-Object Id -eq 'CASA-CO-01').Status | Should -Be 'Fail'

        $collect.domains.security.keyVaultKeys = @(
            [pscustomobject]@{ id = '.../keys/k1'; keyVaultName = 'kv1'; keyVaultId = '.../vaults/kv1'; subscriptionId = 's1'; resourceGroup = 'rg1'; contentType = $null; enabled = $true; expires = $null }
        )
        $after = Invoke-Assessment -Collect $collect -RuleSet $set -Assessment 'Microsoft: CASA'
        ($after | Where-Object Id -eq 'CASA-CO-01').Status | Should -Be 'Pass'
    }

    It 'is proven non-vacuous: CASA-CO-04 flips from Fail to Pass when a Purview account is collected' {
        $set = Get-RuleSet -Patterns @('casa.*')
        $collect = New-EmptyCollect
        ((Invoke-Assessment -Collect $collect -RuleSet $set -Assessment 'Microsoft: CASA') | Where-Object Id -eq 'CASA-CO-04').Status | Should -Be 'Fail'

        $collect.domains.analytics.purviewAccounts = @([pscustomobject]@{ name = 'pv1'; resourceGroup = 'rg1'; subscriptionId = 's1' })
        ((Invoke-Assessment -Collect $collect -RuleSet $set -Assessment 'Microsoft: CASA') | Where-Object Id -eq 'CASA-CO-04').Status | Should -Be 'Pass'
    }

    It 'every rule id starts with CASA- and cites an item number from the CASA question set' {
        $set = Get-RuleSet -Patterns @('casa.*')
        $offenders = @($set[0].Rules | Where-Object { $_.id -notmatch '^CASA-(TR|PM|IR|CO|IN|AV|SS)-\d\d$' })
        $offenders | Should -BeNullOrEmpty
        foreach ($rule in $set[0].Rules) {
            $rule.remediation | Should -Match ([regex]::Escape($rule.id)) -Because "$($rule.id)'s remediation text must cite its own id, so a reviewer can trace it back to docs/frameworks/casa-question-set.md"
        }
    }

    It 'is registered in manifests/assessments.psd1' {
        $script:Manifest.Keys | Should -Contain 'Microsoft: CASA'
        $script:Manifest['Microsoft: CASA'].Rules | Should -Be @('casa.*')
    }
}

Describe 'AB#6820 -- compute.privateClouds: the typed-query and inventory-shaping paths agree' {

    It 'ConvertFrom-ScoutInventory shapes Microsoft.AVS/privateClouds identically to the KQL fields' {
        $resources = @(
            [pscustomobject]@{
                id = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.AVS/privateClouds/pc1'
                name = 'pc1'; type = 'microsoft.avs/privateclouds'; resourceGroup = 'rg1'; subscriptionId = 's1'
                sku = [pscustomobject]@{ name = 'av36' }
                properties = [pscustomobject]@{
                    availability = [pscustomobject]@{ strategy = 'DualZone'; zone = 2 }
                    managementCluster = [pscustomobject]@{ clusterSize = 6 }
                    circuit = [pscustomobject]@{ expressRouteID = '/subscriptions/s1/.../expressRouteCircuits/er1' }
                    encryption = [pscustomobject]@{ status = 'Enabled' }
                    internet = 'Disabled'
                    identitySources = @(@{ name = 'ad1' })
                    externalCloudLinks = @()
                }
            }
        )
        $result = ConvertFrom-ScoutInventory -Resources $resources -ResourceContainers @()

        $result.ContainsKey('privateClouds') | Should -BeTrue
        $result.privateClouds.Count | Should -Be 1
        $pc = $result.privateClouds[0]
        $pc.availabilityStrategy | Should -Be 'DualZone'
        $pc.clusterSize | Should -Be 6
        $pc.expressRouteCircuitId | Should -Be '/subscriptions/s1/.../expressRouteCircuits/er1'
        $pc.encryptionStatus | Should -Be 'Enabled'
        $pc.identitySourceCount | Should -Be 1
        $pc.externalCloudLinkCount | Should -Be 0
    }

    It 'reports clusterSize as null, not zero, when the property is absent (matches the KQL toint(null) semantics elsewhere in this file)' {
        $resources = @(
            [pscustomobject]@{
                id = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.AVS/privateClouds/pc2'
                name = 'pc2'; type = 'microsoft.avs/privateclouds'; resourceGroup = 'rg1'; subscriptionId = 's1'
                sku = $null; properties = [pscustomobject]@{}
            }
        )
        $result = ConvertFrom-ScoutInventory -Resources $resources -ResourceContainers @()
        $result.privateClouds[0].clusterSize | Should -Be $null
    }
}

Describe 'AB#6821 -- Invoke-Collect extracts Key Vault secrets/keys from the ARM-child sweep' {

    BeforeAll {
        function Import-Module {             [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stub Azure/PowerShell calls for the test -- this is the point of the mock.')]
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }
        . (Join-Path -Path $script:Root -ChildPath 'src/collect/Invoke-Collect.ps1')
    }

    It 'shapes AZSC/ARMChild/KeyVaultSecrets and KeyVaultKeys rows into domains.security, and requests the scoped ArmChildDataset' {
        $script:capturedIncludeArmChild = $null
        $script:capturedArmChildDataset = $null
        function Get-ScoutRawInventory {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param(
                [switch] $IncludeArmChildResources,
                [string[]] $ArmChildDataset,
                [Parameter(ValueFromRemainingArguments)] $Rest
            )
            $script:capturedIncludeArmChild = [bool]$IncludeArmChildResources
            $script:capturedArmChildDataset = $ArmChildDataset

            [pscustomobject]@{
                Resources = @(
                    [pscustomobject]@{
                        id = '.../vaults/kv1/secrets/s1'; type = 'AZSC/ARMChild/KeyVaultSecrets'
                        contentType = 'text/plain'; attributes = [pscustomobject]@{ enabled = $true; exp = $null }
                        PARENTID = '.../vaults/kv1'; PARENTNAME = 'kv1'; subscriptionId = 'sub1'; RESOURCEGROUP = 'rg1'
                    }
                    [pscustomobject]@{
                        id = '.../vaults/kv1/secrets/cert1'; type = 'AZSC/ARMChild/KeyVaultSecrets'
                        contentType = 'application/x-pkcs12'; attributes = [pscustomobject]@{ enabled = $true; exp = 1234567890 }
                        PARENTID = '.../vaults/kv1'; PARENTNAME = 'kv1'; subscriptionId = 'sub1'; RESOURCEGROUP = 'rg1'
                    }
                    [pscustomobject]@{
                        id = '.../vaults/kv1/keys/k1'; type = 'AZSC/ARMChild/KeyVaultKeys'
                        attributes = [pscustomobject]@{ enabled = $true }
                        PARENTID = '.../vaults/kv1'; PARENTNAME = 'kv1'; subscriptionId = 'sub1'; RESOURCEGROUP = 'rg1'
                    }
                )
                ResourceContainers = @()
            }
        }
        function Search-AzGraph {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest); return @() }

        $collect = Invoke-Collect -Categories @('*')

        $script:capturedIncludeArmChild | Should -Be $true
        @($script:capturedArmChildDataset) | Should -Be @('KeyVaultSecrets', 'KeyVaultKeys')

        $collect.domains.security.keyVaultSecrets.Count | Should -Be 2
        $collect.domains.security.keyVaultKeys.Count | Should -Be 1
        ($collect.domains.security.keyVaultSecrets | Where-Object id -match 'cert1').contentType | Should -Be 'application/x-pkcs12'
        $collect.domains.security.keyVaultKeys[0].keyVaultName | Should -Be 'kv1'
    }
}
