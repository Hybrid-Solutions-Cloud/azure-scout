#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: the SAP on Azure and Oracle on Azure IaaS workload reviews. Each rule set is run against
    small collect objects built here, so every automated rule's Pass and Fail is pinned, gated rules
    are proven NotAssessed on an estate without the workload, resources outside the workload are
    proven not to be scored, and no rule errors.

    The SAP rules read Virtual Instance for SAP solutions rows from the universal discovery index
    ($.discovery.Resources). The Oracle rules read VMs built from an Oracle-published Marketplace
    image from the same index. The fixtures below mirror the Resource Graph row shape that index
    keeps (Id, Name, Type, Zones, Properties); they are NOT captured from a live estate.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml

    $script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'

    function Invoke-ScoutTestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    function ConvertTo-ScoutFindingMap {
        param($Findings)
        $map = @{}
        foreach ($f in $Findings) { $map[[string]$f.Id] = $f }
        $map
    }

    function Get-TestVmId { param([string] $Name) "$script:Sub/Microsoft.Compute/virtualMachines/$Name" }

    # A Resource Graph virtual-machine row as the discovery index keeps it.
    function Get-VmRowFixture {
        param(
            [string] $Id, [string] $Name = 'vm', [string] $Publisher = 'Canonical',
            [string] $OsSku = 'Premium_LRS', [string] $DataSku = 'Premium_LRS', [string] $Caching = 'ReadOnly'
        )
        [ordered]@{
            Id = $Id; Name = $Name; Type = 'microsoft.compute/virtualmachines'; Zones = @('1')
            Properties = [ordered]@{
                storageProfile = [ordered]@{
                    imageReference = [ordered]@{ publisher = $Publisher }
                    osDisk         = [ordered]@{ managedDisk = [ordered]@{ storageAccountType = $OsSku } }
                    dataDisks      = @([ordered]@{ lun = 0; caching = $Caching; managedDisk = [ordered]@{ storageAccountType = $DataSku } })
                }
            }
        }
    }

    function Get-NicRowFixture {
        param([string] $Id, [string] $VmId, [bool] $Accelerated = $true, [bool] $PublicIp = $false)
        $ipProps = [ordered]@{}
        if ($PublicIp) { $ipProps['publicIPAddress'] = [ordered]@{ id = "$script:Sub/Microsoft.Network/publicIPAddresses/pip" } }
        [ordered]@{
            Id = $Id; Name = 'nic'; Type = 'microsoft.network/networkinterfaces'
            Properties = [ordered]@{
                enableAcceleratedNetworking = $Accelerated
                virtualMachine              = [ordered]@{ id = $VmId }
                ipConfigurations            = @([ordered]@{ properties = $ipProps })
            }
        }
    }

    # The slim row Invoke-Collect projects into compute.virtualMachines.
    function Get-SlimVmFixture {
        param([string] $Id, [string] $Name, [bool] $Zoned = $true, [string] $Assessment = 'AutomaticByPlatform')
        [ordered]@{ id = $Id; name = $Name; zoneEligible = $true; zoneRedundant = $Zoned; assessmentMode = $Assessment }
    }

    # ---- SAP fixture -------------------------------------------------------------------------
    # -Bad breaks every automated SAP rule once; without it every automated rule passes. The
    # `not-sap` VM and `nic-other` sit outside every SAP system and are broken in BOTH variants:
    # a rule that scored them would fail the clean collect.
    function Get-SapCollectFixture {
        param([switch] $Bad)
        $csVm = Get-TestVmId 'sap-cs-1'; $csVm2 = Get-TestVmId 'sap-cs-2'
        $dbVm = Get-TestVmId 'sap-db-1'; $appVm = Get-TestVmId 'sap-app-1'; $otherVm = Get-TestVmId 'not-sap'
        $lbCs = "$script:Sub/Microsoft.Network/loadBalancers/lb-cs"; $lbDb = "$script:Sub/Microsoft.Network/loadBalancers/lb-db"
        $saNfs = "$script:Sub/Microsoft.Storage/storageAccounts/sapnfs"
        $vis = "$script:Sub/Microsoft.Workloads/sapVirtualInstances/X00"
        $resources = @(
            [ordered]@{ Id = $vis; Name = 'X00'; Type = 'microsoft.workloads/sapvirtualinstances'
                Properties = [ordered]@{ environment = 'Prod'; health = ($Bad ? 'Degraded' : 'Healthy'); state = ($Bad ? 'DiscoveryFailed' : 'RegistrationComplete') } }
            [ordered]@{ Id = "$vis/centralInstances/cs"; Name = 'cs'; Type = 'microsoft.workloads/sapvirtualinstances/centralinstances'
                Properties = [ordered]@{
                    health              = ($Bad ? 'Unhealthy' : 'Healthy')
                    vmDetails           = @([ordered]@{ virtualMachineId = $csVm; type = 'ASCS'; storageDetails = @([ordered]@{ id = $saNfs }) }, [ordered]@{ virtualMachineId = $csVm2; type = 'ERS' })
                    loadBalancerDetails = [ordered]@{ id = $lbCs }
                } }
            [ordered]@{ Id = "$vis/databaseInstances/db"; Name = 'db'; Type = 'microsoft.workloads/sapvirtualinstances/databaseinstances'
                Properties = [ordered]@{ vmDetails = @([ordered]@{ virtualMachineId = $dbVm }); loadBalancerDetails = [ordered]@{ id = $lbDb } } }
            [ordered]@{ Id = "$vis/applicationInstances/app"; Name = 'app'; Type = 'microsoft.workloads/sapvirtualinstances/applicationinstances'
                Properties = [ordered]@{ health = 'Healthy'; vmDetails = @([ordered]@{ virtualMachineId = $appVm; type = 'Active' }); loadBalancerDetails = [ordered]@{ id = $lbDb } } }
            [ordered]@{ Id = "$script:Sub/Microsoft.Workloads/monitors/ams"; Name = 'ams'; Type = 'microsoft.workloads/monitors'
                Properties = [ordered]@{ provisioningState = ($Bad ? 'Failed' : 'Succeeded') } }
            (Get-VmRowFixture -Id $csVm -Name 'sap-cs-1')
            (Get-VmRowFixture -Id $csVm2 -Name 'sap-cs-2')
            (Get-VmRowFixture -Id $dbVm -Name 'sap-db-1' -OsSku ($Bad ? 'Standard_LRS' : 'Premium_LRS') -DataSku ($Bad ? 'Standard_LRS' : 'Premium_LRS'))
            (Get-VmRowFixture -Id $appVm -Name 'sap-app-1')
            (Get-VmRowFixture -Id $otherVm -Name 'not-sap' -OsSku 'Standard_LRS' -DataSku 'Standard_LRS')
            (Get-NicRowFixture -Id 'nic-app' -VmId $appVm -Accelerated (-not $Bad))
            (Get-NicRowFixture -Id 'nic-other' -VmId $otherVm -Accelerated $false)
        )
        $slimVms = @(
            (Get-SlimVmFixture -Id $csVm -Name 'sap-cs-1' -Zoned (-not $Bad) -Assessment ($Bad ? 'ImageDefault' : 'AutomaticByPlatform'))
            (Get-SlimVmFixture -Id $csVm2 -Name 'sap-cs-2')
            (Get-SlimVmFixture -Id $dbVm -Name 'sap-db-1')
            (Get-SlimVmFixture -Id $appVm -Name 'sap-app-1')
            (Get-SlimVmFixture -Id $otherVm -Name 'not-sap' -Zoned $false -Assessment 'ImageDefault')
        )
        $protected = if ($Bad) { @($csVm2, $appVm) } else { @($csVm, $csVm2, $dbVm, $appVm) }
        [ordered]@{
            discovery     = [ordered]@{ Resources = $resources }
            compute       = [ordered]@{ virtualMachines = $slimVms }
            networking    = [ordered]@{
                loadBalancers    = @([ordered]@{ id = $lbCs; sku = ($Bad ? 'Basic' : 'Standard') }, [ordered]@{ id = $lbDb; sku = 'Standard' })
                privateEndpoints = @(if (-not $Bad) { [ordered]@{ targetResourceId = $saNfs } })
                nsgPublicInbound = @()
            }
            management    = [ordered]@{ backupProtectedItems = @($protected | ForEach-Object { [ordered]@{ sourceResourceId = $_ } }); maintenanceConfigurations = @(); recoveryVaults = @() }
            security      = [ordered]@{ defenderPlans = @([ordered]@{ name = 'VirtualMachines'; properties = [ordered]@{ pricingTier = ($Bad ? 'Free' : 'Standard') } }) }
            updateManager = [ordered]@{ patchInstallations = @([ordered]@{ machineId = $dbVm; status = ($Bad ? 'Failed' : 'Succeeded') }) }
            monitor       = [ordered]@{ activityLogAlertRules = @() }
            domains       = [ordered]@{ storage = [ordered]@{ diskEncryptionSets = @() } }
            finops        = [ordered]@{ reservations = @() }
        }
    }

    # ---- Oracle fixture ----------------------------------------------------------------------
    # `web1` is built from a non-Oracle image and is broken in BOTH variants, so a rule that scored
    # VMs outside the Oracle-image set would fail the clean collect.
    function Get-OracleCollectFixture {
        param([switch] $Bad)
        $oraVm = Get-TestVmId 'oradb-01'; $oraVm2 = Get-TestVmId 'oracle-02'; $webVm = Get-TestVmId 'web1'
        $resources = @(
            (Get-VmRowFixture -Id $oraVm -Name 'oradb-01' -Publisher 'Oracle' -OsSku ($Bad ? 'Standard_LRS' : 'Premium_LRS') -DataSku ($Bad ? 'StandardSSD_LRS' : 'Premium_LRS') -Caching ($Bad ? 'ReadWrite' : 'ReadOnly'))
            (Get-VmRowFixture -Id $oraVm2 -Name 'oracle-02' -Publisher 'Oracle')
            (Get-VmRowFixture -Id $webVm -Name 'web1' -Publisher 'MicrosoftWindowsServer' -OsSku 'Standard_LRS' -DataSku 'Standard_LRS' -Caching 'ReadWrite')
            (Get-NicRowFixture -Id 'nic-ora' -VmId $oraVm -Accelerated (-not $Bad) -PublicIp $Bad.IsPresent)
            (Get-NicRowFixture -Id 'nic-ora2' -VmId $oraVm2)
            (Get-NicRowFixture -Id 'nic-web' -VmId $webVm -Accelerated $false -PublicIp $true)
        )
        $slimVms = @(
            (Get-SlimVmFixture -Id $oraVm -Name 'oradb-01' -Zoned (-not $Bad) -Assessment ($Bad ? 'ImageDefault' : 'AutomaticByPlatform'))
            (Get-SlimVmFixture -Id $oraVm2 -Name 'oracle-02')
            (Get-SlimVmFixture -Id $webVm -Name 'web1' -Zoned $false -Assessment 'ImageDefault')
        )
        [ordered]@{
            discovery     = [ordered]@{ Resources = $resources }
            compute       = [ordered]@{ virtualMachines = $slimVms }
            security      = [ordered]@{ defenderPlans = @([ordered]@{ name = 'VirtualMachines'; properties = [ordered]@{ pricingTier = ($Bad ? 'Free' : 'Standard') } }) }
            updateManager = [ordered]@{ patchInstallations = @([ordered]@{ machineId = $oraVm; status = ($Bad ? 'Failed' : 'Succeeded') }) }
            management    = [ordered]@{ backupProtectedItems = @(); recoveryVaults = @() }
            networking    = [ordered]@{ nsgPublicInbound = @() }
            monitor       = [ordered]@{ dataCollectionRules = @(); metricAlertRules = @() }
            domains       = [ordered]@{ storage = [ordered]@{ diskEncryptionSets = @() } }
            finops        = [ordered]@{ reservations = @() }
        }
    }

    $script:EmptyEstate = [ordered]@{
        discovery     = [ordered]@{ Resources = @() }
        compute       = [ordered]@{ virtualMachines = @() }
        networking    = [ordered]@{ loadBalancers = @(); privateEndpoints = @(); nsgPublicInbound = @() }
        management    = [ordered]@{ backupProtectedItems = @(); maintenanceConfigurations = @(); recoveryVaults = @() }
        security      = [ordered]@{ defenderPlans = @() }
        updateManager = [ordered]@{ patchInstallations = @() }
        monitor       = [ordered]@{ activityLogAlertRules = @(); dataCollectionRules = @(); metricAlertRules = @() }
        domains       = [ordered]@{ storage = [ordered]@{ diskEncryptionSets = @() } }
        finops        = [ordered]@{ reservations = @() }
    }

    $script:SapSet = @(& $script:Module { Get-RuleSet -Patterns 'waf.sap' })
    $script:OraSet = @(& $script:Module { Get-RuleSet -Patterns 'waf.oracle' })
    $script:SapClean = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.sap' -Collect (Get-SapCollectFixture) -Assessment 'Workload: SAP')
    $script:SapBad = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.sap' -Collect (Get-SapCollectFixture -Bad) -Assessment 'Workload: SAP')
    $script:SapEmpty = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.sap' -Collect $script:EmptyEstate -Assessment 'Workload: SAP')
    $script:OraClean = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.oracle' -Collect (Get-OracleCollectFixture) -Assessment 'Workload: Oracle')
    $script:OraBad = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.oracle' -Collect (Get-OracleCollectFixture -Bad) -Assessment 'Workload: Oracle')
    $script:OraEmpty = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.oracle' -Collect $script:EmptyEstate -Assessment 'Workload: Oracle')
}

Describe 'Workload: SAP on Azure - rule set shape' {
    It 'loads one rule set for framework WAF-SAP with 38 unique rules' {
        $script:SapSet.Count | Should -Be 1
        $script:SapSet[0].Framework | Should -Be 'WAF-SAP'
        $script:SapSet[0].Area | Should -Be 'SAP on Azure workload'
        $script:SapSet[0].FrameworkVersion | Should -BeLike '*verified 2026-11-25*'
        @($script:SapSet[0].Rules).Count | Should -Be 38
        @($script:SapSet[0].Rules.id | Select-Object -Unique).Count | Should -Be 38
    }

    It 'every title and remediation starts with its own id' {
        foreach ($r in $script:SapSet[0].Rules) {
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
        }
    }

    It 'covers the five pillars with 8, 9, 4, 10 and 7 items' {
        $counts = @{ RE = 8; SE = 9; CO = 4; OE = 10; PE = 7 }
        foreach ($k in $counts.Keys) {
            @($script:SapSet[0].Rules | Where-Object { $_.id -like "WAF-SAP-$k-*" }).Count | Should -Be $counts[$k] -Because "pillar $k"
        }
    }

    It 'has 14 automated and 24 manual rules, every automated one gated and every manual one flagged' {
        $auto = @($script:SapSet[0].Rules | Where-Object { -not $_.manual })
        $manual = @($script:SapSet[0].Rules | Where-Object { $_.manual })
        $auto.Count | Should -Be 14
        $manual.Count | Should -Be 24
        foreach ($r in $auto) {
            $r.assert.ContainsKey('gate') | Should -BeTrue -Because "$($r.id) must report NotAssessed on an estate without SAP"
            [string]::IsNullOrWhiteSpace([string]$r.assert.gate) | Should -BeFalse
        }
        foreach ($r in $manual) { $r.assert.type | Should -Be 'manual' }
    }

    It 'every rule id is enumerated in the checklist doc, and the doc enumerates nothing else' {
        $doc = Get-Content "$script:root/docs/frameworks/waf-sap-workload-checklist.md" -Raw
        foreach ($r in $script:SapSet[0].Rules) { $doc | Should -Match ([regex]::Escape([string]$r.id)) }
        $docIds = @([regex]::Matches($doc, 'WAF-SAP-(RE|SE|CO|OE|PE)-\d{2}') | ForEach-Object Value | Select-Object -Unique)
        $docIds.Count | Should -Be 38
    }
}

Describe 'Workload: SAP on Azure - automated rules' {
    It 'produces no Error findings on a clean, a broken or an empty estate' {
        @($script:SapClean.Values + $script:SapBad.Values + $script:SapEmpty.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'passes every automated rule on the clean SAP estate (14 rules)' {
        $auto = @($script:SapSet[0].Rules | Where-Object { -not $_.manual })
        foreach ($r in $auto) { $script:SapClean[[string]$r.id].Status | Should -Be 'Pass' -Because "$($r.id) on the clean collect" }
        $auto.Count | Should -Be 14
    }

    It 'scores <Id> as Fail on the broken estate with <Evidence> evidence rows' -ForEach @(
        @{ Id = 'WAF-SAP-RE-01'; Evidence = 1 }   # sap-cs-1 has no zone; not-sap (also unzoned) is not an SAP VM
        @{ Id = 'WAF-SAP-RE-03'; Evidence = 2 }   # virtual instance Degraded + central instance Unhealthy
        @{ Id = 'WAF-SAP-RE-04'; Evidence = 1 }   # DiscoveryFailed
        @{ Id = 'WAF-SAP-RE-05'; Evidence = 1 }   # lb-cs is Basic
        @{ Id = 'WAF-SAP-RE-06'; Evidence = 2 }   # sap-cs-1 and sap-db-1 have no backup item
        @{ Id = 'WAF-SAP-SE-07'; Evidence = 1 }   # Defender for Servers on Free
        @{ Id = 'WAF-SAP-SE-08'; Evidence = 1 }   # sap-cs-1 on ImageDefault
        @{ Id = 'WAF-SAP-SE-09'; Evidence = 1 }   # NFS storage account has no private endpoint
        @{ Id = 'WAF-SAP-OE-02'; Evidence = 1 }   # monitor failed provisioning
        @{ Id = 'WAF-SAP-OE-09'; Evidence = 1 }   # sap-db-1 failed patch installation
        @{ Id = 'WAF-SAP-PE-01'; Evidence = 1 }   # sap-db-1 Standard HDD data disk; not-sap has one too
        @{ Id = 'WAF-SAP-PE-02'; Evidence = 1 }   # sap-db-1 Standard HDD OS disk
        @{ Id = 'WAF-SAP-PE-05'; Evidence = 1 }   # sap-app-1 NIC without accelerated networking; nic-other is not SAP
    ) {
        $f = $script:SapBad[$Id]
        $f.Status | Should -Be 'Fail'
        $f.EvidenceCount | Should -Be $Evidence
    }

    It 'passes WAF-SAP-OE-01 when a monitor exists, even a failed one, and fails it when none does' {
        $script:SapBad['WAF-SAP-OE-01'].Status | Should -Be 'Pass'
        $visOnly = Get-SapCollectFixture
        $visOnly.discovery.Resources = @($visOnly.discovery.Resources | Where-Object { $_.Type -ne 'microsoft.workloads/monitors' })
        $f = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.sap' -Collect $visOnly -Assessment 'Workload: SAP')
        $f['WAF-SAP-OE-01'].Status | Should -Be 'Fail'
        $f['WAF-SAP-OE-02'].Status | Should -Be 'NotAssessed' -Because 'there is no monitor to be in a failed state'
    }

    It 'reports every automated rule NotAssessed on an estate with no SAP (14 rules)' {
        $auto = @($script:SapSet[0].Rules | Where-Object { -not $_.manual })
        foreach ($r in $auto) { $script:SapEmpty[[string]$r.id].Status | Should -Be 'NotAssessed' -Because "$($r.id) must not pass or fail an estate with no SAP" }
        @($script:SapEmpty.Values | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Error' }).Count | Should -Be 0
        @($script:SapEmpty.Values | Where-Object Status -eq 'Manual').Count | Should -Be 24
    }

    It 'leaves VM-level rules NotAssessed when SAP systems are registered but list no instance VMs' {
        $visOnly = Get-SapCollectFixture
        $visOnly.discovery.Resources = @($visOnly.discovery.Resources | Where-Object { $_.Type -eq 'microsoft.workloads/sapvirtualinstances' })
        $f = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.sap' -Collect $visOnly -Assessment 'Workload: SAP')
        foreach ($id in 'WAF-SAP-RE-01', 'WAF-SAP-RE-05', 'WAF-SAP-RE-06', 'WAF-SAP-SE-07', 'WAF-SAP-SE-08', 'WAF-SAP-SE-09', 'WAF-SAP-OE-09', 'WAF-SAP-PE-01', 'WAF-SAP-PE-02', 'WAF-SAP-PE-05') {
            $f[$id].Status | Should -Be 'NotAssessed' -Because $id
        }
        $f['WAF-SAP-RE-03'].Status | Should -Be 'Pass'
    }

    It 'attaches the production and non-production virtual instances as manual evidence' {
        $script:SapClean['WAF-SAP-RE-02'].Status | Should -Be 'Manual'
        $script:SapClean['WAF-SAP-RE-02'].EvidenceCount | Should -Be 1
        $script:SapClean['WAF-SAP-CO-01'].Status | Should -Be 'Manual'
        $script:SapClean['WAF-SAP-CO-01'].EvidenceCount | Should -Be 0
    }
}

Describe 'Workload: Oracle on Azure IaaS - rule set shape' {
    It 'loads one rule set for framework WAF-ORACLE with 34 unique rules' {
        $script:OraSet.Count | Should -Be 1
        $script:OraSet[0].Framework | Should -Be 'WAF-ORACLE'
        $script:OraSet[0].Area | Should -Be 'Oracle on Azure IaaS workload'
        $script:OraSet[0].FrameworkVersion | Should -BeLike '*verified 2026-11-25*'
        @($script:OraSet[0].Rules).Count | Should -Be 34
        @($script:OraSet[0].Rules.id | Select-Object -Unique).Count | Should -Be 34
    }

    It 'every title and remediation starts with its own id' {
        foreach ($r in $script:OraSet[0].Rules) {
            $r.title | Should -BeLike "$($r.id). *"
            $r.remediation | Should -BeLike "$($r.id). *"
        }
    }

    It 'covers the five pillars with 6, 7, 5, 8 and 8 items' {
        $counts = @{ RE = 6; SE = 7; CO = 5; OE = 8; PE = 8 }
        foreach ($k in $counts.Keys) {
            @($script:OraSet[0].Rules | Where-Object { $_.id -like "WAF-ORA-$k-*" }).Count | Should -Be $counts[$k] -Because "pillar $k"
        }
    }

    It 'has 9 automated and 25 manual rules, every automated one gated and every manual one flagged' {
        $auto = @($script:OraSet[0].Rules | Where-Object { -not $_.manual })
        $manual = @($script:OraSet[0].Rules | Where-Object { $_.manual })
        $auto.Count | Should -Be 9
        $manual.Count | Should -Be 25
        foreach ($r in $auto) {
            $r.assert.ContainsKey('gate') | Should -BeTrue -Because "$($r.id) must report NotAssessed on an estate without Oracle-image VMs"
            [string]::IsNullOrWhiteSpace([string]$r.assert.gate) | Should -BeFalse
        }
        foreach ($r in $manual) { $r.assert.type | Should -Be 'manual' }
    }

    It 'every rule id is enumerated in the checklist doc, and the doc enumerates nothing else' {
        $doc = Get-Content "$script:root/docs/frameworks/waf-oracle-iaas-workload-checklist.md" -Raw
        foreach ($r in $script:OraSet[0].Rules) { $doc | Should -Match ([regex]::Escape([string]$r.id)) }
        $docIds = @([regex]::Matches($doc, 'WAF-ORA-(RE|SE|CO|OE|PE)-\d{2}') | ForEach-Object Value | Select-Object -Unique)
        $docIds.Count | Should -Be 34
    }
}

Describe 'Workload: Oracle on Azure IaaS - automated rules' {
    It 'produces no Error findings on a clean, a broken or an empty estate' {
        @($script:OraClean.Values + $script:OraBad.Values + $script:OraEmpty.Values | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'passes every automated rule on the clean Oracle estate (9 rules)' {
        $auto = @($script:OraSet[0].Rules | Where-Object { -not $_.manual })
        foreach ($r in $auto) { $script:OraClean[[string]$r.id].Status | Should -Be 'Pass' -Because "$($r.id) on the clean collect" }
        $auto.Count | Should -Be 9
    }

    It 'scores <Id> as Fail on the broken estate with <Evidence> evidence row' -ForEach @(
        @{ Id = 'WAF-ORA-RE-01'; Evidence = 1 }   # oradb-01 has no zone; web1 (also unzoned, not Oracle) is not scored
        @{ Id = 'WAF-ORA-SE-01'; Evidence = 1 }   # oradb-01 NIC has a public IP; nic-web has one too and is not Oracle
        @{ Id = 'WAF-ORA-SE-02'; Evidence = 1 }   # Defender for Servers on Free
        @{ Id = 'WAF-ORA-SE-03'; Evidence = 1 }   # oradb-01 on ImageDefault
        @{ Id = 'WAF-ORA-OE-05'; Evidence = 1 }   # oradb-01 failed patch installation
        @{ Id = 'WAF-ORA-PE-01'; Evidence = 1 }   # StandardSSD data disk; web1 has a Standard HDD one and is not Oracle
        @{ Id = 'WAF-ORA-PE-02'; Evidence = 1 }   # Standard HDD OS disk
        @{ Id = 'WAF-ORA-PE-03'; Evidence = 1 }   # ReadWrite caching on a data disk
        @{ Id = 'WAF-ORA-PE-04'; Evidence = 1 }   # accelerated networking off on the Oracle NIC
    ) {
        $f = $script:OraBad[$Id]
        $f.Status | Should -Be 'Fail'
        $f.EvidenceCount | Should -Be $Evidence
    }

    It 'reports every automated rule NotAssessed on an estate with no Oracle-image VM (9 rules)' {
        $auto = @($script:OraSet[0].Rules | Where-Object { -not $_.manual })
        foreach ($r in $auto) { $script:OraEmpty[[string]$r.id].Status | Should -Be 'NotAssessed' -Because "$($r.id) must not pass or fail an estate with no Oracle VM" }
        @($script:OraEmpty.Values | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Error' }).Count | Should -Be 0
        @($script:OraEmpty.Values | Where-Object Status -eq 'Manual').Count | Should -Be 25
    }

    It 'leaves the automated rules NotAssessed when the only VMs run a non-Oracle image' {
        $web = Get-OracleCollectFixture -Bad
        $web.discovery.Resources = @($web.discovery.Resources | Where-Object { $_.Name -in 'web1', 'nic-web' })
        $f = ConvertTo-ScoutFindingMap (Invoke-ScoutTestRuleSet -Pattern 'waf.oracle' -Collect $web -Assessment 'Workload: Oracle')
        foreach ($r in @($script:OraSet[0].Rules | Where-Object { -not $_.manual })) { $f[[string]$r.id].Status | Should -Be 'NotAssessed' -Because "$($r.id) keys on the Oracle image" }
    }

    It 'pre-fills the identification rule with VMs whose names suggest Oracle, and not others' {
        $f = $script:OraClean['WAF-ORA-OE-01']
        $f.Status | Should -Be 'Manual'
        $f.EvidenceCount | Should -Be 2   # oradb-01 and oracle-02, not web1
    }
}
