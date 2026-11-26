#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#9300, 3.18.20 -- the update summary, security settings and Arc settings of Azure Local clusters, end to end.

    Resource Graph indexes a cluster (microsoft.azurestackhci/clusters) but not these children, so Get-ScoutArmChildResource reads
    three lists with ARM GETs under the cluster. The shared contract is asserted by tests/helpers/DepthChildHarness.ps1; this
    file adds what is particular to Azure Local:

      - the Arc application and object ids, the Arc resource group and the node names are never read (only counts of nodes);
      - drift control is "enforced" only when every baseline assignment the cluster names is ApplyAndAutoCorrect;
      - a cluster with an update available and one with a disconnected node say so as booleans.

    These api-versions and property names were checked on Microsoft Learn (2024-04-01 is GA; securitySettings carries
    securedCoreComplianceAssignment, wdacComplianceAssignment and smbEncryptionForIntraClusterTrafficComplianceAssignment, each
    ApplyAndAutoCorrect or Audit). The lab tenant's Azure Local cluster could not be read live when this was written: its
    subscription's cached sign-in had expired. No Azure connection, credential, tenant or subscription identifier is involved here.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthChildHarness.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthFamilyCases.ps1')
    $script:Family = @(Get-DepthFamilyCase | Where-Object { $_.Name -eq 'AzureLocal' })[0]
}

AfterAll { Remove-DepthStub }

Describe 'Get-ScoutArmChildResource -- Azure Local clusters: what is asked and what is kept' {

    It 'asks nothing without an Azure Local cluster' {
        Assert-DepthNothingAskedWithoutParent -Family $script:Family
    }

    It 'issues the documented request for every dataset: path, api-version, one list per cluster' {
        Assert-DepthDocumentedRequest -Family $script:Family
    }

    It 'carries no Arc application id, object id, resource group, node name or hardware model' {
        Assert-DepthNoSecret -Family $script:Family
    }

    It 'leaves every dataset empty and unmeasured when every GET is denied, so a rule reads NotAssessed' {
        Assert-DepthDeniedIsNotMeasured -Family $script:Family
    }

    It 'treats an empty list as an answer: measured, no rows' {
        Assert-DepthEmptyIsAnAnswer -Family $script:Family
    }

    It 'retries a throttled request and does not report it as a failure' {
        Assert-DepthRetriesAThrottledRequest -Family $script:Family
    }
}

Describe 'ConvertFrom-ScoutInventory -- Azure Local datasets' {

    BeforeAll {
        Install-DepthStub -Routes $script:Family.Routes
        $script:Sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets
        $script:Shaped = Get-DepthShaped -Sweep $script:Sweep -Resources $script:Family.Parents
    }

    It 'sets every Measured flag when the datasets were answered' {
        foreach ($key in $script:Family.Keys) { $script:Shaped["${key}Measured"] | Should -BeTrue -Because $key }
    }

    It 'shapes the update summary with the state, versions and the dates as ISO strings' {
        $summary = @($script:Shaped.azureLocalUpdateSummaries)
        $summary.Count | Should -Be 1
        $summary[0].clusterName | Should -Be 'hci1'
        $summary[0].state | Should -Be 'UpdateAvailable'
        $summary[0].updateAvailable | Should -BeTrue
        $summary[0].upToDate | Should -BeFalse
        $summary[0].currentVersion | Should -Be '10.2411.0.24'
        $summary[0].lastChecked | Should -Match '^2026-11-25T'
        $summary[0].packageVersionCount | Should -Be 2
    }

    It 'says drift control is not enforced when any baseline assignment is Audit, and enforced when all are ApplyAndAutoCorrect' {
        $settings = @($script:Shaped.azureLocalSecuritySettings)[0]
        $settings.wdacComplianceAssignment | Should -Be 'Audit'
        $settings.securedCoreComplianceAssignment | Should -Be 'ApplyAndAutoCorrect'
        $settings.driftControlEnforced | Should -BeFalse
        $settings.wdacCompliance | Should -Be 'NonCompliant'

        $enforced = @{}
        foreach ($path in $script:Family.Routes.Keys) { $enforced[$path] = $script:Family.Routes[$path] }
        $key = @($enforced.Keys | Where-Object { $_ -like '*/securitySettings' })[0]
        $enforced[$key] = @{ Status = 200; Body = (ConvertTo-DepthBody @{ value = @(@{ id = "$key/default"; name = 'default'; properties = @{ securedCoreComplianceAssignment = 'ApplyAndAutoCorrect'; wdacComplianceAssignment = 'ApplyAndAutoCorrect'; smbEncryptionForIntraClusterTrafficComplianceAssignment = 'ApplyAndAutoCorrect' } }) }) }
        Install-DepthStub -Routes $enforced
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset @('AzureLocalSecuritySettings')
        (@((Get-DepthShaped -Sweep $sweep -Resources $script:Family.Parents).azureLocalSecuritySettings)[0]).driftControlEnforced | Should -BeTrue
    }

    It 'reads a cluster that names no assignment as unknown, never as not enforced' {
        $none = @{}
        foreach ($path in $script:Family.Routes.Keys) { $none[$path] = $script:Family.Routes[$path] }
        $key = @($none.Keys | Where-Object { $_ -like '*/securitySettings' })[0]
        $none[$key] = @{ Status = 200; Body = (ConvertTo-DepthBody @{ value = @(@{ id = "$key/default"; name = 'default'; properties = @{ provisioningState = 'Succeeded' } }) }) }
        Install-DepthStub -Routes $none
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset @('AzureLocalSecuritySettings')
        (@((Get-DepthShaped -Sweep $sweep -Resources $script:Family.Parents).azureLocalSecuritySettings)[0]).driftControlEnforced | Should -BeNullOrEmpty
    }

    It 'counts Arc nodes and connected nodes without naming one' {
        $arc = @($script:Shaped.azureLocalArcSettings)[0]
        $arc.aggregateState | Should -Be 'PartiallyConnected'
        $arc.nodeCount | Should -Be 2
        $arc.connectedNodeCount | Should -Be 1
        $arc.allNodesConnected | Should -BeFalse
        $arc.connectivityEnabled | Should -BeTrue
        $arc.defaultExtensionCount | Should -Be 1
    }

    It 'mirrors every row under a real Azure Local type for the discovery index' {
        $twins = @(ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows))
        @($twins.type | Sort-Object -Unique) | Should -Be @(
            'microsoft.azurestackhci/clusters/arcsettings', 'microsoft.azurestackhci/clusters/securitysettings', 'microsoft.azurestackhci/clusters/updatesummaries')
    }
}
