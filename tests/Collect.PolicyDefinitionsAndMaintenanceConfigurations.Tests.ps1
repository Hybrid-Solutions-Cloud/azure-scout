#Requires -Version 7.0
#Requires -Modules Pester
#Requires -Modules Az.ResourceGraph

<#
    AB#7065/AB#7066/AB#7067 (Story AB#7059, Feature AB#7069, Epic AB#7099).

    The collector manifests for Azure Update Manager (Management/MaintenanceConfigurations.psd1)
    and Azure Policy definitions/initiatives (Management/PolicyDefinitions.psd1,
    Management/PolicySetDefinitions.psd1) already existed and already rendered Excel worksheets,
    but none of the three ever reached `collect.json` -- the payload the assessment rules and the
    React report actually read. This is pure plumbing: the ARM resource types were already being
    read (or, for the two policy datasets, were already sitting in `$rawInventory.Resources` from
    the unconditional TenantWideDefinitionsOnly sweep); nothing here adds a new collection call.

      - management.maintenanceConfigurations   -- a normal ARG-indexed type
        (microsoft.maintenance/maintenanceconfigurations), wired the same way every other typed
        `$q` query in Invoke-Collect.ps1 is (AB#7065).
      - governance.policyDefinitions / governance.policySetDefinitions -- extracted from the
        AZSC/Management/PolicyDefinition / AZSC/Management/PolicySetDefinition envelopes
        `Get-ScoutTenantWideResource` already appends to `$rawInventory.Resources`, following the
        same placement/shape convention `governance.policyAssignments` already uses (properties
        kept whole, not flattened) (AB#7066).

    This file (AB#7067) is the regression guard: assert all three keys are present, correctly
    shaped, and reachable through BOTH collection paths (`-Source TypedQueries` and the default
    `-Source Inventory` / `-FromInventory` raw-pass path) so this can never silently regress the
    way the other 163 categories AB#7060 found did.

    Search-AzGraph is mocked throughout. No live Azure connection is made.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module Az.ResourceGraph -ErrorAction Stop
    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"

    # ---- a raw maintenance-configuration row, the shape Resource Graph's `resources` table
    # returns for microsoft.maintenance/maintenanceconfigurations ----
    function New-FixtureMaintenanceConfigRow {
        [pscustomobject]@{
            id             = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg1/providers/Microsoft.Maintenance/maintenanceConfigurations/patch-tuesday'
            name           = 'patch-tuesday'; type = 'microsoft.maintenance/maintenanceconfigurations'
            resourceGroup  = 'rg1'; subscriptionId = '00000000-0000-0000-0000-000000000001'; location = 'eastus'
            kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
            extendedLocation = $null; managedBy = $null; tags = $null; tenantId = 'ten'
            properties = [pscustomobject]@{
                maintenanceScope = 'InGuestPatch'
                maintenanceWindow = [pscustomobject]@{
                    recurEvery    = '1Month Second Tuesday'
                    startDateTime = '2026-08-11 03:00'
                    duration      = '03:00'
                    timeZone      = 'Pacific Standard Time'
                }
                installPatches = [pscustomobject]@{ rebootSetting = 'IfRequired' }
            }
        }
    }

    # ---- raw ARM REST list-response rows for the two policy envelopes, exactly the shape
    # Get-ScoutApiResources' PolicyDefinitions/PolicySetDefinitions fields carry ----
    function New-FixturePolicyDefinitionRow {
        [pscustomobject]@{
            id   = '/providers/Microsoft.Authorization/policyDefinitions/require-tag'
            name = 'require-tag'; type = 'Microsoft.Authorization/policyDefinitions'
            properties = [pscustomobject]@{
                displayName = 'Require a cost-centre tag'; policyType = 'Custom'; mode = 'Indexed'
                metadata    = [pscustomobject]@{ category = 'Tags'; version = '1.0.0' }
                policyRule  = [pscustomobject]@{ then = [pscustomobject]@{ effect = 'deny' } }
            }
        }
    }

    function New-FixturePolicySetDefinitionRow {
        [pscustomobject]@{
            id   = '/providers/Microsoft.Authorization/policySetDefinitions/alz-baseline'
            name = 'alz-baseline'; type = 'Microsoft.Authorization/policySetDefinitions'
            properties = [pscustomobject]@{
                displayName      = 'ALZ baseline initiative'; policyType = 'Custom'
                metadata         = [pscustomobject]@{ category = 'Landing Zone'; version = '2.1.0' }
                policyDefinitions = @(
                    [pscustomobject]@{ policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/require-tag' }
                    [pscustomobject]@{ policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/deny-public-ip' }
                )
            }
        }
    }

    function New-FixtureRawInventory {
        <# The -FromInventory / Get-ScoutRawInventory envelope shape: .Resources, .ResourceContainers,
           .Governance. Carries one of each fixture row above, plus the two synthetic policy
           envelopes exactly as Get-ScoutTenantWideResource produces them. #>
        [pscustomobject]@{
            Resources          = @(
                (New-FixtureMaintenanceConfigRow)
                [pscustomobject]@{ type = 'AZSC/Management/PolicyDefinition'; properties = @(New-FixturePolicyDefinitionRow) }
                [pscustomobject]@{ type = 'AZSC/Management/PolicySetDefinition'; properties = @(New-FixturePolicySetDefinitionRow) }
            )
            ResourceContainers = @(
                [pscustomobject]@{
                    id = '/subscriptions/00000000-0000-0000-0000-000000000001'; name = 'sub-one'; type = 'microsoft.resources/subscriptions'
                    subscriptionId = '00000000-0000-0000-0000-000000000001'; properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null
                }
            )
            Governance         = [pscustomobject]@{
                roleAssignments = @(); policyAssignments = @(); budgets = @(); resourceLocks = @()
            }
        }
    }
}

Describe 'AB#7065 -- management.maintenanceConfigurations reaches the payload' {
    BeforeEach { Mock Search-AzGraph { return @() } }

    It 'is a distinct typed query, keyed by name, in Invoke-Collect''s $q pack' {
        Invoke-Collect -Source TypedQueries -Categories @('*') | Out-Null
        Should -Invoke Search-AzGraph -ParameterFilter {
            $Query -match 'microsoft\.maintenance/maintenanceconfigurations'
        } -Times 1 -Exactly
    }

    It 'runs when -Categories asks for Management' {
        Invoke-Collect -Source TypedQueries -Categories @('Management') | Out-Null
        Should -Invoke Search-AzGraph -ParameterFilter {
            $Query -match 'microsoft\.maintenance/maintenanceconfigurations'
        } -Times 1 -Exactly
    }

    It 'is skipped for an unrelated category' {
        Invoke-Collect -Source TypedQueries -Categories @('Web') | Out-Null
        Should -Invoke Search-AzGraph -ParameterFilter {
            $Query -match 'microsoft\.maintenance/maintenanceconfigurations'
        } -Times 0 -Exactly
    }

    It 'shapes the scalar schedule fields the rules would filter on -- no `.length` needed (AB#5083)' {
        Mock Search-AzGraph {
            if ($Query -match 'microsoft\.maintenance/maintenanceconfigurations') {
                # The projection ARG would return for the KQL in Invoke-Collect.ps1's `$q`
                # pack -- scalar fields only, matching AB#5083's "no `.length` in a rule" rule.
                return @(
                    [pscustomobject]@{
                        name = 'patch-tuesday'; resourceGroup = 'rg1'; subscriptionId = '00000000-0000-0000-0000-000000000001'
                        scope = 'InGuestPatch'; recurEvery = '1Month Second Tuesday'
                        startDateTime = '2026-08-11 03:00'; duration = '03:00'
                        timeZone = 'Pacific Standard Time'; rebootSetting = 'IfRequired'
                    }
                )
            }
            return @()
        }

        $result = Invoke-Collect -Source TypedQueries -Categories @('*')

        $result.management.PSObject.Properties.Name | Should -Contain 'maintenanceConfigurations'
        @($result.management.maintenanceConfigurations).Count | Should -Be 1
        $row = @($result.management.maintenanceConfigurations)[0]
        $row.name          | Should -Be 'patch-tuesday'
        $row.scope         | Should -Be 'InGuestPatch'
        $row.recurEvery    | Should -Be '1Month Second Tuesday'
        $row.rebootSetting | Should -Be 'IfRequired'
    }

    It 'is still present as an empty array when nothing is collected -- never a missing key' {
        $result = Invoke-Collect -Source TypedQueries -Categories @('*')
        $result.management.PSObject.Properties.Name | Should -Contain 'maintenanceConfigurations'
        @($result.management.maintenanceConfigurations) | Should -BeNullOrEmpty
    }

    It 'reaches the payload through the default raw-inventory path too (ConvertFrom-ScoutInventory)' {
        $result = Invoke-Collect -FromInventory (New-FixtureRawInventory) -Categories @('*')

        @($result.management.maintenanceConfigurations).Count | Should -Be 1
        $row = @($result.management.maintenanceConfigurations)[0]
        $row.name  | Should -Be 'patch-tuesday'
        $row.scope | Should -Be 'InGuestPatch'
    }
}

Describe 'AB#7066 -- governance.policyDefinitions / governance.policySetDefinitions reach the payload' {
    It 'extracts policy definitions from the AZSC/Management/PolicyDefinition envelope with zero extra Azure calls' {
        Mock Search-AzGraph { throw 'must not query Resource Graph for a dataset already sitting in $rawInventory.Resources' }

        $result = Invoke-Collect -FromInventory (New-FixtureRawInventory) -Categories @('*')

        $result.governance.PSObject.Properties.Name | Should -Contain 'policyDefinitions'
        @($result.governance.policyDefinitions).Count | Should -Be 1
        $def = @($result.governance.policyDefinitions)[0]
        $def.id   | Should -Be '/providers/Microsoft.Authorization/policyDefinitions/require-tag'
        $def.name | Should -Be 'require-tag'
        # `properties` kept whole -- exactly like governance.policyAssignments -- so a rule's
        # JSONPath resolves without a re-shape here.
        $def.properties.policyType             | Should -Be 'Custom'
        $def.properties.metadata.category      | Should -Be 'Tags'
        $def.properties.policyRule.then.effect | Should -Be 'deny'
    }

    It 'extracts policy SET (initiative) definitions the same way' {
        Mock Search-AzGraph { throw 'must not query Resource Graph' }

        $result = Invoke-Collect -FromInventory (New-FixtureRawInventory) -Categories @('*')

        $result.governance.PSObject.Properties.Name | Should -Contain 'policySetDefinitions'
        @($result.governance.policySetDefinitions).Count | Should -Be 1
        $set = @($result.governance.policySetDefinitions)[0]
        $set.id                             | Should -Be '/providers/Microsoft.Authorization/policySetDefinitions/alz-baseline'
        $set.properties.displayName         | Should -Be 'ALZ baseline initiative'
        @($set.properties.policyDefinitions).Count | Should -Be 2
    }

    It 'collapses a definition visible from more than one subscription''s ARM REST sweep to one row' {
        Mock Search-AzGraph { throw 'must not query Resource Graph' }

        $raw = New-FixtureRawInventory
        # The same policy definition, repeated (as it would be if two subscriptions in the
        # sweep both saw the same tenant-global built-in/custom definition).
        $raw.Resources = @(
            $raw.Resources[0]
            [pscustomobject]@{ type = 'AZSC/Management/PolicyDefinition'; properties = @((New-FixturePolicyDefinitionRow), (New-FixturePolicyDefinitionRow)) }
            $raw.Resources[2]
        )

        $result = Invoke-Collect -FromInventory $raw -Categories @('*')
        @($result.governance.policyDefinitions).Count | Should -Be 1
    }

    It 'is present as an empty array, never a missing key, when the raw pass carries no such envelope' {
        Mock Search-AzGraph { return @() }
        $result = Invoke-Collect -Source TypedQueries -Categories @('*')

        $result.governance.PSObject.Properties.Name | Should -Contain 'policyDefinitions'
        $result.governance.PSObject.Properties.Name | Should -Contain 'policySetDefinitions'
        @($result.governance.policyDefinitions) | Should -BeNullOrEmpty
        @($result.governance.policySetDefinitions) | Should -BeNullOrEmpty
    }
}

Describe 'AB#7067 -- the three keys are pinned in the canonical collect.json payload shape' {
    It 'never regresses silently: all three keys exist on a real Invoke-Collect result' {
        Mock Search-AzGraph { return @() }
        $result = Invoke-Collect -FromInventory (New-FixtureRawInventory) -Categories @('*')

        $result.management.PSObject.Properties.Name  | Should -Contain 'maintenanceConfigurations'
        $result.governance.PSObject.Properties.Name   | Should -Contain 'policyDefinitions'
        $result.governance.PSObject.Properties.Name   | Should -Contain 'policySetDefinitions'
    }
}
