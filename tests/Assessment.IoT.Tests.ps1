#Requires -Version 7.0
#Requires -Modules Pester

<#
    Pester tests for the IoT deep-coverage collector/rule pass (AB#330):
      - src/collect/Invoke-Collect.ps1's new `dpsInstances` (Microsoft.Devices/
        provisioningServices) and `digitalTwinsInstances` (Microsoft.DigitalTwins/
        digitalTwinsInstances) queries, projected into domains.iot.
      - src/assess/rules/caf.iot.yaml's new automated rules (CAF-IOT-07..11) and
        the two rules that stay manual with a documented reason (CAF-IOT-12/13).

    Search-AzGraph is mocked throughout for the collector tests -- no live Azure
    connection is made. The rule-engine tests use Resolve-JsonPath/Invoke-Rule
    directly against synthetic collect objects -- no YAML mutation.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/tests/helpers/Search-AzGraph.TestDouble.ps1"
    Import-Module powershell-yaml -ErrorAction Stop
    . "$root/src/collect/Invoke-Collect.ps1"
    . "$root/src/assess/engine/Resolve-JsonPath.ps1"
    . "$root/src/assess/engine/Invoke-Rule.ps1"
    . "$root/src/assess/engine/Get-RuleSet.ps1"

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
}

Describe 'Invoke-Collect IoT deep coverage (AB#330)' {
    BeforeEach {
        Mock Search-AzGraph {
            if ($Query -match 'microsoft\.devices/provisioningservices') {
                return @(
                    [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/provisioningServices/dps-prod'; name = 'dps-prod'; resourceGroup = 'rg-iot'; sku = 'S1'; publicAccess = 'Enabled'; allocationPolicy = 'Hashed'; linkedHubCount = 2 }
                    [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/provisioningServices/dps-sec'; name = 'dps-sec'; resourceGroup = 'rg-iot'; sku = 'S1'; publicAccess = 'Disabled'; allocationPolicy = 'Static'; linkedHubCount = 1 }
                )
            }
            if ($Query -match 'microsoft\.digitaltwins/digitaltwinsinstances') {
                return @(
                    [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt-prod'; name = 'dt-prod'; resourceGroup = 'rg-iot'; publicAccess = 'Enabled'; privateEndpointConnectionCount = 0; identityType = '' }
                    [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt-sec'; name = 'dt-sec'; resourceGroup = 'rg-iot'; publicAccess = 'Disabled'; privateEndpointConnectionCount = 1; identityType = 'SystemAssigned' }
                )
            }
            return @()
        }
    }

    It 'queries Microsoft.Devices/provisioningServices and shapes it into domains.iot.dpsInstances' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('IoT')
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.devices/provisioningservices' -and $Query -match '(?m)^\| project id,' } -Times 1
        $result.domains.iot.dpsInstances.Count | Should -Be 2
        ($result.domains.iot.dpsInstances | Where-Object name -eq 'dps-prod').publicAccess | Should -Be 'Enabled'
        ($result.domains.iot.dpsInstances | Where-Object name -eq 'dps-prod').linkedHubCount | Should -Be 2
    }

    It 'queries Microsoft.DigitalTwins/digitalTwinsInstances and shapes it into domains.iot.digitalTwinsInstances' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('IoT')
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.digitaltwins/digitaltwinsinstances' -and $Query -match '(?m)^\| project id,' } -Times 1
        $result.domains.iot.digitalTwinsInstances.Count | Should -Be 2
        ($result.domains.iot.digitalTwinsInstances | Where-Object name -eq 'dt-prod').identityType | Should -Be ''
        ($result.domains.iot.digitalTwinsInstances | Where-Object name -eq 'dt-sec').identityType | Should -Be 'SystemAssigned'
    }

    It 'collects IoT Hubs with the resource id needed for private-endpoint correlation' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('IoT')
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.devices/iothubs"' -and $Query -match '(?m)^\| project id,' } -Times 1
        $result.domains.iot.PSObject.Properties.Name | Should -Contain 'iotHubs'
    }

    It 'the new IoT queries are skipped when -Categories excludes IoT' {
        Invoke-Collect -Source TypedQueries -Categories @('Security') | Out-Null
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.devices/provisioningservices' } -Times 0 -Exactly
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'microsoft\.digitaltwins/digitaltwinsinstances' } -Times 0 -Exactly
    }
}

Describe 'caf.iot.yaml rule set (AB#330)' {
    BeforeAll {
        $script:ruleSet = Get-RuleSet -Patterns @('caf.iot')

        $script:collect = [pscustomobject]@{
            domains = [pscustomobject]@{
                iot = [pscustomobject]@{
                    iotHubs = @(
                        [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/IotHubs/hub1'; name = 'hub1'; sku = 'S1'; publicAccess = 'Enabled'; disableLocalAuth = $false }
                        [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/IotHubs/hub2'; name = 'hub2'; sku = 'S1'; publicAccess = 'Disabled'; disableLocalAuth = $true }
                    )
                    dpsInstances = @(
                        [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/provisioningServices/dps1'; name = 'dps1'; sku = 'S1'; publicAccess = 'Enabled'; allocationPolicy = 'Hashed'; linkedHubCount = 2 }
                        [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/provisioningServices/dps2'; name = 'dps2'; sku = 'S1'; publicAccess = 'Disabled'; allocationPolicy = 'Static'; linkedHubCount = 1 }
                    )
                    digitalTwinsInstances = @(
                        [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt1'; name = 'dt1'; publicAccess = 'Enabled'; privateEndpointConnectionCount = 0; identityType = '' }
                        [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt2'; name = 'dt2'; publicAccess = 'Disabled'; privateEndpointConnectionCount = 1; identityType = 'SystemAssigned' }
                        [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt3'; name = 'dt3'; publicAccess = 'Disabled'; privateEndpointConnectionCount = 0; identityType = 'None' }
                    )
                }
            }
            networking = [pscustomobject]@{
                privateEndpoints = @(
                    [pscustomobject]@{ name = 'pe-dps'; targetResourceId = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/provisioningServices/dps1'; targetProvider = 'microsoft.devices'; targetType = 'provisioningservices' }
                    [pscustomobject]@{ name = 'pe-hub'; targetResourceId = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/IotHubs/hub1'; targetProvider = 'microsoft.devices'; targetType = 'iothubs' }
                    [pscustomobject]@{ name = 'pe-dt'; targetResourceId = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt2'; targetProvider = 'microsoft.digitaltwins'; targetType = 'digitaltwinsinstances' }
                )
            }
        }
    }

    It 'loads 13 rules with no duplicate ids' {
        $script:ruleSet.Rules.Count | Should -Be 13
        ($script:ruleSet.Rules.id | Sort-Object -Unique).Count | Should -Be 13
    }

    It 'CAF-IOT-07 fails when a DPS instance allows public network access' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'CAF-IOT-07'
        $finding = Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
    }

    It 'CAF-IOT-08 reports Partial private-endpoint adoption for DPS instances (1 of 2)' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'CAF-IOT-08'
        $finding = Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Partial'
    }

    It 'CAF-IOT-09 fails when a Digital Twins instance allows public network access' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'CAF-IOT-09'
        $finding = Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
    }

    It 'CAF-IOT-10 reports Partial private-endpoint adoption for Digital Twins instances (1 of 3)' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'CAF-IOT-10'
        $finding = Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Partial'
    }

    It 'CAF-IOT-11 fails and counts both the empty-string and ''None'' identityType instances' {
        $rule = $script:ruleSet.Rules | Where-Object id -eq 'CAF-IOT-11'
        $finding = Invoke-Rule -Rule $rule -Collect $script:collect -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 2
    }

    It 'CAF-IOT-12 (IoT Edge) and CAF-IOT-13 (Digital Twins routing endpoints) stay manual with a null query' {
        $edge = $script:ruleSet.Rules | Where-Object id -eq 'CAF-IOT-12'
        $edge.manual | Should -BeTrue
        $edge.assert.type | Should -Be 'manual'
        $edge.query | Should -BeNullOrEmpty

        $routing = $script:ruleSet.Rules | Where-Object id -eq 'CAF-IOT-13'
        $routing.manual | Should -BeTrue
        $routing.assert.type | Should -Be 'manual'
        $routing.query | Should -BeNullOrEmpty
    }

    It 'a fully-compliant estate passes every automated IoT rule' {
        $compliant = [pscustomobject]@{
            domains = [pscustomobject]@{
                iot = [pscustomobject]@{
                    iotHubs = @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/IotHubs/hub1'; name = 'hub1'; sku = 'S1'; publicAccess = 'Disabled'; disableLocalAuth = $true })
                    dpsInstances = @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/provisioningServices/dps1'; name = 'dps1'; sku = 'S1'; publicAccess = 'Disabled'; allocationPolicy = 'Hashed'; linkedHubCount = 1 })
                    digitalTwinsInstances = @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt1'; name = 'dt1'; publicAccess = 'Disabled'; privateEndpointConnectionCount = 1; identityType = 'SystemAssigned' })
                }
            }
            networking = [pscustomobject]@{
                privateEndpoints = @(
                    [pscustomobject]@{ name = 'pe-hub'; targetResourceId = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/IotHubs/hub1'; targetProvider = 'microsoft.devices'; targetType = 'iothubs' }
                    [pscustomobject]@{ name = 'pe-dps'; targetResourceId = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.Devices/provisioningServices/dps1'; targetProvider = 'microsoft.devices'; targetType = 'provisioningservices' }
                    [pscustomobject]@{ name = 'pe-dt'; targetResourceId = '/subscriptions/sub-1/resourceGroups/rg-iot/providers/Microsoft.DigitalTwins/digitalTwinsInstances/dt1'; targetProvider = 'microsoft.digitaltwins'; targetType = 'digitaltwinsinstances' }
                )
            }
        }
        foreach ($id in @('CAF-IOT-01', 'CAF-IOT-05', 'CAF-IOT-06', 'CAF-IOT-07', 'CAF-IOT-08', 'CAF-IOT-09', 'CAF-IOT-10', 'CAF-IOT-11')) {
            $rule = $script:ruleSet.Rules | Where-Object id -eq $id
            $finding = Invoke-Rule -Rule $rule -Collect $compliant -Area $script:ruleSet.Area -Framework $script:ruleSet.Framework
            $finding.Status | Should -Be 'Pass' -Because "$id should pass against a fully-compliant estate"
        }
    }
}
