#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#7107 AB#7108 AB#7109 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Azure Update
    Manager patch detail.

    `Get-ScoutRawInventory.ps1` has read Update Manager's own `patchassessmentresources` /
    `patchinstallationresources` Resource Graph tables since AB#6731 (behind
    `-IncludeUpdateManagerResources`), and `Get-ScoutOperationalCollectorEnrichment.ps1` already
    folds those same rows into the legacy Excel VMOperationalData/ArcServerOperationalData
    collectors -- but nothing before this change turned that switch on for the default assessment
    collect, and nothing shaped the rows into the JSON assessment payload (`collect.json`).
    AB#7109's per-machine patch ORCHESTRATION config (patchMode/assessmentMode) was likewise
    already sitting in the ordinary `resources` row for every VM/Arc machine Scout already
    collects -- it was never projected. This is the same class of defect AB#7065/AB#7066/AB#7064
    fixed elsewhere: pure plumbing, not new collection logic.

    Two collection paths must both reach every key:
      - Invoke-Collect -Source TypedQueries (the live KQL query pack)
      - Invoke-Collect -FromInventory / the default inverted path (ConvertFrom-ScoutInventory)

    Search-AzGraph is mocked throughout. No live Azure connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    function New-MockSubscriptionRow {
        param([string] $Id = 'aaa')
        [pscustomobject]@{
            id = "/subscriptions/$Id"; name = "sub-$Id"; type = 'microsoft.resources/subscriptions'
            subscriptionId = $Id; location = $null; resourceGroup = $null
            kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
            extendedLocation = $null; managedBy = $null; tenantId = 'ten'
            properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null
        }
    }

    function Get-FixturePatchRows {
        @(
            # ---- Azure VM (Windows), with a patch orchestration setting on the resource itself
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1'
                name = 'vm1'; type = 'microsoft.compute/virtualmachines'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2s_v3' }
                    storageProfile  = [pscustomobject]@{ osDisk = [pscustomobject]@{ osType = 'Windows' } }
                    osProfile       = [pscustomobject]@{
                        windowsConfiguration = [pscustomobject]@{
                            patchSettings = [pscustomobject]@{ patchMode = 'AutomaticByPlatform'; assessmentMode = 'AutomaticByPlatform' }
                        }
                    }
                }
            }
            # ---- Arc-enabled server (Linux) -- exercises the linuxConfiguration fallback
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/arc1'
                name = 'arc1'; type = 'microsoft.hybridcompute/machines'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    status = 'Connected'; agentVersion = '1.40.0'
                    osProfile = [pscustomobject]@{
                        linuxConfiguration = [pscustomobject]@{
                            patchSettings = [pscustomobject]@{ patchMode = 'ImageDefault'; assessmentMode = 'AutomaticByPlatform' }
                        }
                    }
                }
            }
            # ---- Update Manager assessment summary row for vm1
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1/patchAssessmentResults/latest'
                name = 'latest'; type = 'microsoft.compute/virtualmachines/patchassessmentresults'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    osType = 'Windows'; rebootPending = $true; patchServiceUsed = 'WU-WSUS'
                    startDateTime = '2026-08-01T00:00:00Z'; lastModifiedDateTime = '2026-08-01T01:00:00Z'
                    availablePatchCountByClassification = [pscustomobject]@{ Critical = 2; Security = 3; Updates = 1 }
                }
            }
            # ---- softwarepatches CHILD row -- must be excluded (per-update detail, not the
            # per-machine summary this feature shapes)
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1/patchAssessmentResults/latest/softwarePatches/kb1'
                name = 'kb1'; type = 'microsoft.compute/virtualmachines/patchassessmentresults/softwarepatches'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{ patchName = 'kb1' }
            }
            # ---- Update Manager assessment summary row for arc1 (Arc server platform)
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/arc1/patchAssessmentResults/latest'
                name = 'latest'; type = 'microsoft.hybridcompute/machines/patchassessmentresults'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    osType = 'Linux'; rebootPending = $false; patchServiceUsed = 'APT'
                    startDateTime = '2026-08-01T00:00:00Z'; lastModifiedDateTime = '2026-08-01T01:00:00Z'
                    availablePatchCountByClassification = [pscustomobject]@{ Security = 4 }
                }
            }
            # ---- Update Manager installation summary row for vm1
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1/patchInstallationResults/11111111-1111-1111-1111-111111111111'
                name = '11111111-1111-1111-1111-111111111111'; type = 'microsoft.compute/virtualmachines/patchinstallationresults'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    osType = 'Windows'; status = 'Succeeded'
                    installationActivityId = '11111111-1111-1111-1111-111111111111'
                    installedPatchCount = 5; failedPatchCount = 0; pendingPatchCount = 0
                    notSelectedPatchCount = 1; excludedPatchCount = 0
                    rebootStatus = 'NotNeeded'; maintenanceWindowExceeded = $false
                    startDateTime = '2026-07-25T00:00:00Z'; lastModifiedDateTime = '2026-07-25T02:00:00Z'
                }
            }
            # ---- softwarepatches CHILD row for the installation -- must be excluded
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1/patchInstallationResults/11111111-1111-1111-1111-111111111111/softwarePatches/kb1'
                name = 'kb1'; type = 'microsoft.compute/virtualmachines/patchinstallationresults/softwarepatches'; location = 'eastus'
                resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{ patchName = 'kb1' }
            }
        )
    }
}

Describe 'ConvertFrom-ScoutInventory -- Update Manager patch detail (AB#7107 AB#7108)' {

    It 'shapes patchAssessments and patchInstallations, populated from the raw rows, excluding softwarepatches children' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePatchRows) -ResourceContainers @(New-MockSubscriptionRow)

        $shaped.ContainsKey('patchAssessments') | Should -BeTrue
        $shaped.ContainsKey('patchInstallations') | Should -BeTrue
        @($shaped['patchAssessments']).Count | Should -Be 2 -Because 'vm1 and arc1 each have one assessment summary row; the softwarepatches child must be excluded'
        @($shaped['patchInstallations']).Count | Should -Be 1 -Because 'only vm1 has an installation summary row; its softwarepatches child must be excluded'
    }

    It 'shapes both keys as an empty array (never throws, never missing) on an empty estate' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @()
        $shaped.ContainsKey('patchAssessments') | Should -BeTrue
        $shaped.ContainsKey('patchInstallations') | Should -BeTrue
        @($shaped['patchAssessments']).Count | Should -Be 0
        @($shaped['patchInstallations']).Count | Should -Be 0
    }

    It 'derives machineId and platform correctly for an Azure VM assessment row' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePatchRows) -ResourceContainers @(New-MockSubscriptionRow)
        $vmRow = @($shaped['patchAssessments'] | Where-Object { $_.platform -eq 'AzureVM' })[0]
        $vmRow.machineId | Should -Be '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1'
        $vmRow.osType | Should -Be 'Windows'
        $vmRow.rebootPending | Should -BeTrue
        $vmRow.patchServiceUsed | Should -Be 'WU-WSUS'
        $vmRow.availablePatchCountByClassification.Critical | Should -Be 2
        $vmRow.availablePatchCountByClassification.Security | Should -Be 3
    }

    It 'derives machineId and platform correctly for an Arc server assessment row' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePatchRows) -ResourceContainers @(New-MockSubscriptionRow)
        $arcRow = @($shaped['patchAssessments'] | Where-Object { $_.platform -eq 'ArcServer' })[0]
        $arcRow.machineId | Should -Be '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/arc1'
        $arcRow.osType | Should -Be 'Linux'
    }

    It 'projects patchInstallations scalar fields correctly, including the machineId join key' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePatchRows) -ResourceContainers @(New-MockSubscriptionRow)
        $installRow = $shaped['patchInstallations'][0]
        $installRow.machineId | Should -Be '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1'
        $installRow.platform | Should -Be 'AzureVM'
        $installRow.status | Should -Be 'Succeeded'
        $installRow.installedPatchCount | Should -Be 5
        $installRow.failedPatchCount | Should -Be 0
        $installRow.pendingPatchCount | Should -Be 0
        $installRow.rebootStatus | Should -Be 'NotNeeded'
        $installRow.maintenanceWindowExceeded | Should -BeFalse
    }
}

Describe 'ConvertFrom-ScoutInventory -- per-machine patch orchestration config (AB#7109)' {

    It 'projects patchMode/assessmentMode on a Windows VM from windowsConfiguration' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePatchRows) -ResourceContainers @(New-MockSubscriptionRow)
        $vm = $shaped['virtualMachines'][0]
        $vm.patchMode | Should -Be 'AutomaticByPlatform'
        $vm.assessmentMode | Should -Be 'AutomaticByPlatform'
    }

    It 'projects patchMode/assessmentMode on a Linux Arc server from linuxConfiguration (the fallback)' {
        $shaped = ConvertFrom-ScoutInventory -Resources (Get-FixturePatchRows) -ResourceContainers @(New-MockSubscriptionRow)
        $arc = $shaped['arcServers'][0]
        $arc.patchMode | Should -Be 'ImageDefault'
        $arc.assessmentMode | Should -Be 'AutomaticByPlatform'
    }

    It 'reads patchMode/assessmentMode as empty string, not throwing, when neither OS config is present' {
        $bareVm = [pscustomobject]@{
            id = '/subscriptions/aaa/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm2'
            name = 'vm2'; type = 'microsoft.compute/virtualmachines'; location = 'eastus'
            resourceGroup = 'rg1'; subscriptionId = 'aaa'; tenantId = 'ten'
            kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
            extendedLocation = $null; managedBy = $null; tags = $null
            properties = [pscustomobject]@{
                hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2s_v3' }
                storageProfile  = [pscustomobject]@{ osDisk = [pscustomobject]@{ osType = 'Windows' } }
            }
        }
        { ConvertFrom-ScoutInventory -Resources @($bareVm) -ResourceContainers @(New-MockSubscriptionRow) } | Should -Not -Throw
        $shaped = ConvertFrom-ScoutInventory -Resources @($bareVm) -ResourceContainers @(New-MockSubscriptionRow)
        $shaped['virtualMachines'][0].patchMode | Should -Be ''
        $shaped['virtualMachines'][0].assessmentMode | Should -Be ''
    }
}

Describe 'Invoke-Collect -- Update Manager keys reach the canonical contract on both paths (AB#7107 AB#7108 AB#7109)' {

    It 'the typed-query path (-Source TypedQueries) populates collect.updateManager.* and compute/hybrid patchMode' {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'microsoft\.compute/virtualmachines"' -and $Query -notmatch 'patchassessmentresources|patchinstallationresources') {
                return @([pscustomobject]@{
                        id = 'vm1'; name = 'vm1'; resourceGroup = 'rg1'; subscriptionId = 'aaa'
                        zoneRedundant = $false; zoneEligible = $true; size = 'Standard_D2s_v3'
                        licenseType = ''; osType = 'Windows'
                        patchMode = 'AutomaticByPlatform'; assessmentMode = 'AutomaticByPlatform'
                    })
            }
            if ($Query -match 'microsoft\.hybridcompute/machines"') {
                return @([pscustomobject]@{
                        name = 'arc1'; resourceGroup = 'rg1'; status = 'Connected'; agentVersion = '1.40.0'
                        patchMode = 'ImageDefault'; assessmentMode = 'AutomaticByPlatform'
                    })
            }
            if ($Query -match '^patchassessmentresources') {
                return @([pscustomobject]@{
                        machineId = 'vm1'; platform = 'AzureVM'; subscriptionId = 'aaa'; resourceGroup = 'rg1'
                        osType = 'Windows'; rebootPending = $true; patchServiceUsed = 'WU-WSUS'
                        startDateTime = '2026-08-01T00:00:00Z'; lastModifiedDateTime = '2026-08-01T01:00:00Z'
                        availablePatchCountByClassification = [pscustomobject]@{ Critical = 2; Security = 3 }
                    })
            }
            if ($Query -match '^patchinstallationresources') {
                return @([pscustomobject]@{
                        machineId = 'vm1'; platform = 'AzureVM'; subscriptionId = 'aaa'; resourceGroup = 'rg1'
                        osType = 'Windows'; status = 'Succeeded'; installationActivityId = 'guid1'
                        installedPatchCount = 5; failedPatchCount = 0; pendingPatchCount = 0
                        notSelectedPatchCount = 1; excludedPatchCount = 0; rebootStatus = 'NotNeeded'
                        maintenanceWindowExceeded = $false
                        startDateTime = '2026-07-25T00:00:00Z'; lastModifiedDateTime = '2026-07-25T02:00:00Z'
                    })
            }
            return @()
        }

        try {
            $collect = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

            $collect.PSObject.Properties.Name | Should -Contain 'updateManager'
            @($collect.updateManager.patchAssessments).Count | Should -Be 1
            @($collect.updateManager.patchInstallations).Count | Should -Be 1
            $collect.updateManager.patchAssessments[0].machineId | Should -Be 'vm1'
            $collect.updateManager.patchInstallations[0].installedPatchCount | Should -Be 5
            $collect.compute.virtualMachines[0].patchMode | Should -Be 'AutomaticByPlatform'
            $collect.domains.hybrid.arcServers[0].patchMode | Should -Be 'ImageDefault'
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'the default inverted path (-FromInventory) populates collect.updateManager.* from raw rows, with no live patch query' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixturePatchRows
            ResourceContainers = @(New-MockSubscriptionRow)
        }

        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            # Only sqlDefenderPricing is a live query on the inverted path; updateManager must
            # come from the raw rows already handed in via -FromInventory.
            if ($Query -match 'patchassessmentresources|patchinstallationresources') {
                throw 'the inverted path must not re-query patch data live'
            }
            return @()
        }

        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue

            @($collect.updateManager.patchAssessments).Count | Should -Be 2
            @($collect.updateManager.patchInstallations).Count | Should -Be 1
            $collect.compute.virtualMachines[0].patchMode | Should -Be 'AutomaticByPlatform'
            $collect.domains.hybrid.arcServers[0].patchMode | Should -Be 'ImageDefault'
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }

    It 'updateManager.* is present, even as an empty array, on a completely empty estate' {
        $inventory = [pscustomobject]@{ Resources = @(); ResourceContainers = @() }
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            return @()
        }
        try {
            $collect = Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue
            $collect.updateManager.PSObject.Properties.Name | Should -Be @('patchAssessments', 'patchInstallations')
            foreach ($key in @('patchAssessments', 'patchInstallations')) {
                { @($collect.updateManager.$key).Count } | Should -Not -Throw
                @($collect.updateManager.$key).Count | Should -Be 0
            }
        }
        finally {
            Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
        }
    }
}
