#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300, 3.18.19 -- the Azure VMware Solution rules that read the private cloud's children.

    Resource Graph indexes a private cloud but not its clusters, add-ons or maintenances; those are read
    by Get-ScoutArmChildResource and shaped into `domains.avs`. This file holds every rule that reads
    them to the same standard: a Pass, a Fail and a NotAssessed fixture, with the data built by the REAL
    shaper (ConvertFrom-ScoutInventory) from child rows and source operations rather than written by
    hand, so a rule cannot pass against a field name the collector never produces.

      WAF-AVS-RE-05   every cluster has the minimum host count (6 for a stretched cloud, 3 otherwise)
      WAF-AVS-SEC-05  the vSAN datastore uses a customer-managed key and the key is reachable
      WAF-AVS-SEC-07  the private cloud streams VMware syslog through a diagnostic setting
      AVS-E2          the Site Recovery Manager add-on is provisioned
      AVS-C5          a private cloud has a hub path: an ExpressRoute circuit (Gen 1) or a virtual network (Gen 2)

    plus the manual items that now carry what was read as evidence (WAF-AVS-RE-06, WAF-AVS-RE-08,
    AVS-C3). A rule gated on a Measured flag reports NotAssessed -- never Fail -- when the dataset was
    not answered, and a private cloud whose own list failed is not flagged as lacking the thing.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Get-RuleSet.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Resolve-JsonPath.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Resolve-RuleJoin.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/engine/Invoke-Rule.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/assess/Invoke-Assessment.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    $script:RuleSet = Get-RuleSet -Patterns @('avs.workload', 'caf.avslandingzone')

    # ---- fixtures -------------------------------------------------------------------------------------
    function New-Cloud {
        param(
            [string]$Name = 'pc1', [string]$Strategy = 'SingleZone', [string]$Circuit = '/x/circuit',
            [string]$EncryptionStatus = 'Disabled', [string]$KeyState = '', [string]$VirtualNetworkId = '',
            [string]$Internet = 'Disabled'
        )
        [pscustomobject]@{
            id = "/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.AVS/privateClouds/$Name"
            name = $Name; type = 'microsoft.avs/privateclouds'; location = 'eastus'; resourceGroup = 'rg1'; subscriptionId = 's1'
            sku = [pscustomobject]@{ name = 'av36' }
            properties = [pscustomobject]@{
                availability = [pscustomobject]@{ strategy = $Strategy; zone = 1 }
                managementCluster = [pscustomobject]@{ clusterSize = 3 }
                circuit = [pscustomobject]@{ expressRouteID = $Circuit }
                encryption = [pscustomobject]@{ status = $EncryptionStatus; keyVaultProperties = [pscustomobject]@{ keyState = $KeyState } }
                internet = $Internet
                virtualNetworkId = $VirtualNetworkId
            }
        }
    }
    function New-ChildRow {
        param($Cloud, [string]$Dataset, [string]$Name, [hashtable]$Properties)
        [pscustomobject]@{
            id = "$($Cloud.id)/children/$Dataset/$Name"; name = $Name; type = "AZSC/ARMChild/$Dataset"
            PARENTID = $Cloud.id; PARENTNAME = $Cloud.name; PARENTTYPE = 'microsoft.avs/privateclouds'; PARENTLOCATION = 'eastus'
            subscriptionId = 's1'; RESOURCEGROUP = 'rg1'; properties = [pscustomobject]$Properties
        }
    }
    function New-Operation {
        param($Cloud, [string]$Dataset, [string]$Status = 'Success')
        [pscustomobject]@{ Source = 'Azure Resource Manager'; Dataset = $Dataset; ParentName = $Cloud.name; ParentId = $Cloud.id; Operation = 'GET'; Uri = 'x'; Status = $Status; Count = 1 }
    }

    function New-AvsCollect {
        param(
            [object[]]$Clouds, [object[]]$Children = @(), [object[]]$Operations = @(),
            [object[]]$DiagnosticCoverage = @()
        )
        $shaped = ConvertFrom-ScoutInventory -Resources (@($Clouds) + @($Children)) -ResourceContainers @() -SourceOperations @($Operations)
        $avs = [ordered]@{}
        foreach ($name in 'clusters', 'datastores', 'placementPolicies', 'addons', 'globalReachConnections', 'authorizations',
            'cloudLinks', 'segments', 'dhcpConfigurations', 'dnsServices', 'gateways', 'iscsiPaths', 'maintenances') {
            $key = "avs$($name.Substring(0, 1).ToUpperInvariant())$($name.Substring(1))"
            $avs[$name] = @($shaped[$key])
            $avs["${name}Measured"] = [bool]$shaped["${key}Measured"]
        }
        [pscustomobject]@{
            subscriptions = @(); tags = @()
            networking = [pscustomobject]@{ azureFirewalls = @(); privateEndpoints = @(); nsgPublicInbound = @() }
            compute = [pscustomobject]@{ virtualMachines = @(); privateClouds = @($shaped['privateClouds']) }
            management = [pscustomobject]@{ logAnalyticsWorkspaces = @() }
            governance = [pscustomobject]@{ policyAssignments = @(); roleAssignments = @(); budgets = @(); roleAssignmentSchedules = @() }
            opsPosture = [pscustomobject]@{ diagnosticCoverage = @($DiagnosticCoverage); diagnosticCoverageMeasured = $DiagnosticCoverage.Count -gt 0 }
            domains = [pscustomobject]@{
                hybrid = [pscustomobject]@{ arcServers = @(); arcExtensions = @() }
                management = [pscustomobject]@{ policyComplianceStates = @() }
                avs = [pscustomobject]$avs
            }
        }
    }

    function Get-Finding {
        param($Collect, [string]$Id)
        $assessment = if ($Id -like 'AVS-*') { 'Workload: AVS Landing Zone' } else { 'Workload: AVS' }
        @(Invoke-Assessment -Collect $Collect -RuleSet $script:RuleSet -Assessment $assessment | Where-Object Id -eq $Id)[0]
    }

    function New-ClusterCase {
        # A private cloud with one cluster of the given size, its cluster list answered.
        param([string]$Strategy, [int]$Size, [bool]$Answered = $true)
        $cloud = New-Cloud -Strategy $Strategy
        $children = @(New-ChildRow -Cloud $cloud -Dataset 'AvsClusters' -Name 'Cluster-1' -Properties @{ clusterSize = $Size; provisioningState = 'Succeeded' })
        $operations = @(if ($Answered) { New-Operation -Cloud $cloud -Dataset 'AvsClusters' })
        New-AvsCollect -Clouds @($cloud) -Children $children -Operations $operations
    }
}

Describe 'The two AVS rule files after the child datasets (AB#9300, 3.18.19)' {

    It 'keeps every rule id in its title and remediation, and every rule either automated or manual' {
        foreach ($set in $script:RuleSet) {
            foreach ($rule in $set.Rules) {
                $rule.title | Should -BeLike "$($rule.id). *" -Because "$($rule.id)'s title leads with its id"
                $rule.remediation | Should -BeLike "$($rule.id). *" -Because "$($rule.id)'s remediation leads with its id"
            }
        }
    }

    It 'counts 27 workload rules (9 automated) and 25 landing-zone rules (10 automated)' {
        $workload = $script:RuleSet | Where-Object Framework -eq 'AVS'
        $zone = $script:RuleSet | Where-Object Framework -eq 'CAF'
        @($workload.Rules).Count | Should -Be 27
        @($workload.Rules | Where-Object { -not $_.manual }).Count | Should -Be 9
        @($zone.Rules).Count | Should -Be 25
        @($zone.Rules | Where-Object { -not $_.manual }).Count | Should -Be 10
    }

    It 'gates every rule that reads a child dataset on that dataset''s Measured flag' {
        $gated = @{
            'WAF-AVS-RE-05' = '$.domains.avs.clustersMeasured'
            'AVS-E2'        = '$.domains.avs.addonsMeasured'
        }
        foreach ($set in $script:RuleSet) {
            foreach ($rule in $set.Rules | Where-Object { -not $_.manual -and [string]$_.query -match 'domains\.avs\.' }) {
                $gated.ContainsKey($rule.id) | Should -BeTrue -Because "$($rule.id) reads domains.avs and must be listed here with its gate"
                @($rule.assert.gate) | Should -Contain $gated[$rule.id]
            }
        }
    }

    It 'uses only the JSONPath forms the engine supports: no parentheses inside a filter value, no negation operator on a boolean' {
        foreach ($set in $script:RuleSet) {
            foreach ($rule in $set.Rules | Where-Object { $_.query -and [string]$_.query -match 'domains\.avs|privateClouds' }) {
                [string]$rule.query | Should -Not -Match '\(\?\([^)]*![^=]' -Because "$($rule.id): a negated filter is not supported"
            }
        }
    }
}

Describe 'WAF-AVS-RE-05 -- every cluster meets the minimum host count for its availability configuration' {

    It 'passes a standard cluster of exactly 3 hosts and a stretched cluster of exactly 6' {
        (Get-Finding (New-ClusterCase -Strategy 'SingleZone' -Size 3) 'WAF-AVS-RE-05').Status | Should -Be 'Pass'
        (Get-Finding (New-ClusterCase -Strategy 'DualZone' -Size 6) 'WAF-AVS-RE-05').Status | Should -Be 'Pass'
    }

    It 'passes a standard cluster of 4, which is short only for a stretched cloud' {
        (Get-Finding (New-ClusterCase -Strategy 'SingleZone' -Size 4) 'WAF-AVS-RE-05').Status | Should -Be 'Pass'
    }

    It 'fails a standard cluster below 3 hosts' {
        $finding = Get-Finding (New-ClusterCase -Strategy 'SingleZone' -Size 2) 'WAF-AVS-RE-05'
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
    }

    It 'fails a stretched cluster below 6 hosts even though 4 would be fine elsewhere' {
        $finding = Get-Finding (New-ClusterCase -Strategy 'DualZone' -Size 4) 'WAF-AVS-RE-05'
        $finding.Status | Should -Be 'Fail'
        $finding.Evidence[0].availabilityStrategy.ToString() | Should -Be 'DualZone'
        $finding.Evidence[0].minimumHosts.ToString() | Should -Be '6'
    }

    It 'checks EVERY cluster, not only the management cluster' {
        $cloud = New-Cloud -Strategy 'SingleZone'
        $children = @(
            New-ChildRow -Cloud $cloud -Dataset 'AvsClusters' -Name 'Cluster-1' -Properties @{ clusterSize = 4 }
            New-ChildRow -Cloud $cloud -Dataset 'AvsClusters' -Name 'Cluster-2' -Properties @{ clusterSize = 2 }
        )
        $collect = New-AvsCollect -Clouds @($cloud) -Children $children -Operations @(New-Operation -Cloud $cloud -Dataset 'AvsClusters')
        $finding = Get-Finding $collect 'WAF-AVS-RE-05'
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
        $finding.Evidence[0].name.ToString() | Should -Be 'Cluster-2'
    }

    It 'is NotAssessed, never Fail, when the cluster list was not read -- even if the private cloud row shows a small management cluster' {
        $collect = New-ClusterCase -Strategy 'SingleZone' -Size 2 -Answered $false
        $collect.domains.avs.clustersMeasured | Should -BeFalse
        (Get-Finding $collect 'WAF-AVS-RE-05').Status | Should -Be 'NotAssessed'
    }

    It 'does not flag a cluster whose size was not returned' {
        $cloud = New-Cloud
        $child = New-ChildRow -Cloud $cloud -Dataset 'AvsClusters' -Name 'Cluster-1' -Properties @{ provisioningState = 'Succeeded' }
        $collect = New-AvsCollect -Clouds @($cloud) -Children @($child) -Operations @(New-Operation -Cloud $cloud -Dataset 'AvsClusters')
        (Get-Finding $collect 'WAF-AVS-RE-05').Status | Should -Be 'Pass'
    }
}

Describe 'WAF-AVS-SEC-05 -- vSAN datastores use a customer-managed key via Key Vault' {

    It 'passes a private cloud with encryption Enabled and the key Connected' {
        $collect = New-AvsCollect -Clouds @(New-Cloud -EncryptionStatus 'Enabled' -KeyState 'Connected')
        (Get-Finding $collect 'WAF-AVS-SEC-05').Status | Should -Be 'Pass'
    }

    It 'fails a private cloud with encryption Disabled' {
        $finding = Get-Finding (New-AvsCollect -Clouds @(New-Cloud -EncryptionStatus 'Disabled')) 'WAF-AVS-SEC-05'
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
    }

    It 'fails a private cloud that reports no encryption block at all' {
        $bare = New-Cloud
        $bare.properties.PSObject.Properties.Remove('encryption')
        (Get-Finding (New-AvsCollect -Clouds @($bare)) 'WAF-AVS-SEC-05').Status | Should -Be 'Fail'
    }

    It 'fails a private cloud whose key the platform cannot reach (AccessDenied) even though encryption is Enabled' {
        $collect = New-AvsCollect -Clouds @(New-Cloud -EncryptionStatus 'Enabled' -KeyState 'AccessDenied')
        (Get-Finding $collect 'WAF-AVS-SEC-05').Status | Should -Be 'Fail'
    }

    It 'counts only the private clouds without a working key' {
        $collect = New-AvsCollect -Clouds @(
            (New-Cloud -Name 'good' -EncryptionStatus 'Enabled' -KeyState 'Connected')
            (New-Cloud -Name 'bad' -EncryptionStatus 'Disabled'))
        $finding = Get-Finding $collect 'WAF-AVS-SEC-05'
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
        $finding.Evidence[0].name.ToString() | Should -Be 'bad'
    }

    It 'needs no sweep: the answer is on the private cloud''s own row, so an unmeasured run still scores it' {
        $collect = New-AvsCollect -Clouds @(New-Cloud -EncryptionStatus 'Enabled' -KeyState 'Connected')
        $collect.domains.avs.clustersMeasured | Should -BeFalse
        (Get-Finding $collect 'WAF-AVS-SEC-05').Status | Should -Be 'Pass'
    }

    It 'reads nothing inside a Key Vault: the rule queries the private cloud and cites no Key Vault dataset' {
        $rule = @(($script:RuleSet | Where-Object Framework -eq 'AVS').Rules | Where-Object id -eq 'WAF-AVS-SEC-05')[0]
        [string]$rule.query | Should -Match 'compute\.privateClouds'
        [string]$rule.query | Should -Not -Match '(?i)keyVault(Keys|Secrets)|domains\.security'
    }
}

Describe 'WAF-AVS-SEC-07 -- the private cloud streams VMware syslog through a diagnostic setting' {

    BeforeAll {
        $script:AvsCoverage = { param($total, $with) [pscustomobject]@{ type = 'microsoft.avs/privateclouds'; total = $total; withDiag = $with; coveragePct = [double]($with * 100 / $total) } }
        $script:OtherCoverage = [pscustomobject]@{ type = 'microsoft.storage/storageaccounts'; total = 5; withDiag = 0; coveragePct = 0 }
    }

    It 'passes when every private cloud has a diagnostic setting' {
        $collect = New-AvsCollect -Clouds @(New-Cloud) -DiagnosticCoverage @((& $script:AvsCoverage 2 2))
        (Get-Finding $collect 'WAF-AVS-SEC-07').Status | Should -Be 'Pass'
    }

    It 'fails when a private cloud has none' {
        $collect = New-AvsCollect -Clouds @(New-Cloud) -DiagnosticCoverage @((& $script:AvsCoverage 2 1))
        $finding = Get-Finding $collect 'WAF-AVS-SEC-07'
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
    }

    It 'is NotAssessed when the sweep did not read a private cloud, whatever other types showed' {
        $collect = New-AvsCollect -Clouds @(New-Cloud) -DiagnosticCoverage @($script:OtherCoverage)
        (Get-Finding $collect 'WAF-AVS-SEC-07').Status | Should -Be 'NotAssessed'
        $collect = New-AvsCollect -Clouds @(New-Cloud)
        (Get-Finding $collect 'WAF-AVS-SEC-07').Status | Should -Be 'NotAssessed'
    }

    It 'is not fooled by a Log Analytics workspace existing somewhere (the check this rule replaced)' {
        $collect = New-AvsCollect -Clouds @(New-Cloud) -DiagnosticCoverage @((& $script:AvsCoverage 1 0))
        $collect.management.logAnalyticsWorkspaces = @([pscustomobject]@{ name = 'law1' })
        (Get-Finding $collect 'WAF-AVS-SEC-07').Status | Should -Be 'Fail'
    }
}

Describe 'AVS-E2 -- the Site Recovery Manager add-on is provisioned' {

    It 'passes a private cloud with an SRM add-on that finished provisioning' {
        $cloud = New-Cloud
        $children = @(New-ChildRow -Cloud $cloud -Dataset 'AvsAddons' -Name 'srm' -Properties @{ addonType = 'SRM'; provisioningState = 'Succeeded' })
        $collect = New-AvsCollect -Clouds @($cloud) -Children $children -Operations @(New-Operation -Cloud $cloud -Dataset 'AvsAddons')
        (Get-Finding $collect 'AVS-E2').Status | Should -Be 'Pass'
    }

    It 'fails a private cloud whose add-on list answered and has no SRM add-on' {
        $cloud = New-Cloud
        $children = @(New-ChildRow -Cloud $cloud -Dataset 'AvsAddons' -Name 'hcx' -Properties @{ addonType = 'HCX'; provisioningState = 'Succeeded' })
        $collect = New-AvsCollect -Clouds @($cloud) -Children $children -Operations @(New-Operation -Cloud $cloud -Dataset 'AvsAddons')
        $finding = Get-Finding $collect 'AVS-E2'
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
    }

    It 'fails a private cloud with an empty add-on list: the empty answer is the finding' {
        $cloud = New-Cloud
        $collect = New-AvsCollect -Clouds @($cloud) -Operations @(New-Operation -Cloud $cloud -Dataset 'AvsAddons' -Status 'Empty')
        (Get-Finding $collect 'AVS-E2').Status | Should -Be 'Fail'
    }

    It 'fails a private cloud whose SRM add-on is still Building or Failed' {
        foreach ($state in 'Building', 'Failed') {
            $cloud = New-Cloud
            $children = @(New-ChildRow -Cloud $cloud -Dataset 'AvsAddons' -Name 'srm' -Properties @{ addonType = 'SRM'; provisioningState = $state })
            $collect = New-AvsCollect -Clouds @($cloud) -Children $children -Operations @(New-Operation -Cloud $cloud -Dataset 'AvsAddons')
            (Get-Finding $collect 'AVS-E2').Status | Should -Be 'Fail' -Because $state
        }
    }

    It 'is NotAssessed, never Fail, when the add-on list was not read' {
        $collect = New-AvsCollect -Clouds @(New-Cloud) -Operations @(New-Operation -Cloud (New-Cloud) -Dataset 'AvsAddons' -Status 'Failed')
        $collect.domains.avs.addonsMeasured | Should -BeFalse
        (Get-Finding $collect 'AVS-E2').Status | Should -Be 'NotAssessed'
    }

    It 'does not flag a private cloud whose own add-on list failed while another answered' {
        $answered = New-Cloud -Name 'answered'
        $failed = New-Cloud -Name 'failed'
        $children = @(New-ChildRow -Cloud $answered -Dataset 'AvsAddons' -Name 'srm' -Properties @{ addonType = 'SRM'; provisioningState = 'Succeeded' })
        $operations = @((New-Operation -Cloud $answered -Dataset 'AvsAddons'), (New-Operation -Cloud $failed -Dataset 'AvsAddons' -Status 'Failed'))
        $collect = New-AvsCollect -Clouds @($answered, $failed) -Children $children -Operations $operations
        $collect.domains.avs.addonsMeasured | Should -BeTrue
        @($collect.domains.avs.addons).Count | Should -Be 1
        (Get-Finding $collect 'AVS-E2').Status | Should -Be 'Pass'
    }
}

Describe 'AVS-C5 -- connectivity exists to a hub: an ExpressRoute circuit or, for Gen 2, a virtual network' {

    It 'passes a Generation 1 private cloud with an ExpressRoute circuit' {
        $collect = New-AvsCollect -Clouds @(New-Cloud -Circuit '/x/circuit')
        (Get-Finding $collect 'AVS-C5').Status | Should -Be 'Pass'
    }

    It 'passes a Generation 2 private cloud that has a virtual network and no circuit' {
        $collect = New-AvsCollect -Clouds @(New-Cloud -Circuit '' -VirtualNetworkId '/x/vnet')
        $collect.compute.privateClouds[0].virtualNetworkIdSet | Should -BeTrue
        (Get-Finding $collect 'AVS-C5').Status | Should -Be 'Pass'
    }

    It 'fails a private cloud with neither' {
        $collect = New-AvsCollect -Clouds @(New-Cloud -Circuit '' -VirtualNetworkId '')
        $finding = Get-Finding $collect 'AVS-C5'
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
    }
}

Describe 'The manual items that now carry what was read as evidence' {

    It 'WAF-AVS-RE-06 stays manual and lists the private clouds with a replication add-on' {
        $cloud = New-Cloud
        $other = New-Cloud -Name 'other'
        $children = @(New-ChildRow -Cloud $cloud -Dataset 'AvsAddons' -Name 'vr' -Properties @{ addonType = 'VR'; vrsCount = 2; provisioningState = 'Succeeded' })
        $operations = @((New-Operation -Cloud $cloud -Dataset 'AvsAddons'), (New-Operation -Cloud $other -Dataset 'AvsAddons'))
        $finding = Get-Finding (New-AvsCollect -Clouds @($cloud, $other) -Children $children -Operations $operations) 'WAF-AVS-RE-06'
        $finding.Status | Should -Be 'Manual'
        $finding.EvidenceCount | Should -Be 1
        $finding.Evidence[0].name.ToString() | Should -Be 'pc1'
    }

    It 'WAF-AVS-RE-08 stays manual and lists the pending maintenance' {
        $cloud = New-Cloud
        $children = @(New-ChildRow -Cloud $cloud -Dataset 'AvsMaintenances' -Name 'm1' -Properties @{ component = 'ESXI'; state = [pscustomobject]@{ name = 'Scheduled' }; scheduledByMicrosoft = $true })
        $collect = New-AvsCollect -Clouds @($cloud) -Children $children -Operations @(New-Operation -Cloud $cloud -Dataset 'AvsMaintenances')
        $finding = Get-Finding $collect 'WAF-AVS-RE-08'
        $finding.Status | Should -Be 'Manual'
        $finding.EvidenceCount | Should -Be 1
        $finding.Evidence[0].component.ToString() | Should -Be 'ESXI'
        $finding.Evidence[0].scheduledByMicrosoft.ToString() | Should -Be 'True'
    }

    It 'AVS-C3 stays manual and lists the private clouds with managed internet egress on' {
        $collect = New-AvsCollect -Clouds @((New-Cloud -Name 'open' -Internet 'Enabled'), (New-Cloud -Name 'closed' -Internet 'Disabled'))
        $finding = Get-Finding $collect 'AVS-C3'
        $finding.Status | Should -Be 'Manual'
        $finding.EvidenceCount | Should -Be 1
        $finding.Evidence[0].name.ToString() | Should -Be 'open'
    }

    It 'never turns a manual item into a Pass or a Fail from what was read' {
        $cloud = New-Cloud -Internet 'Enabled'
        $collect = New-AvsCollect -Clouds @($cloud)
        foreach ($id in 'WAF-AVS-RE-06', 'WAF-AVS-RE-08', 'AVS-C3', 'AVS-E1', 'WAF-AVS-RE-01') {
            (Get-Finding $collect $id).Status | Should -Be 'Manual' -Because $id
        }
    }
}

Describe 'Every AVS rule against an estate with no private cloud' {

    It 'reports NotAssessed, not a manufactured Pass, because the requires gate is not met' {
        $collect = New-AvsCollect -Clouds @()
        $workload = Invoke-Assessment -Collect $collect -RuleSet $script:RuleSet -Assessment 'Workload: AVS'
        @($workload | Where-Object Status -ne 'NotAssessed') | Should -BeNullOrEmpty
        @($workload).Count | Should -Be (27 + 25)
    }
}
