#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#6769 / AB#6770 / AB#6771 -- three collectors that returned zero rows in every tenant, on
    every run, at every permission level, because of where their data was read from rather than
    what it was.

    The audit (docs/audits/AZURE-SCOUT-AUDIT.md, section 9 note 3) grouped these as "no meaningful
    permission answer": granting more access could not have changed the output, so they would
    always PRESENT as a permission failure while not being one. Each fix moves the source, and
    each test below asserts the source -- not that the collector honours an input it was never
    given, which is the shape of assertion that let all three survive the suite for releases.

    No Azure connection: Search-AzGraph, Invoke-AzRestMethod and the ARM REST sweep are all
    replaced with local functions.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent

    # Get-ScoutRawInventory's `Import-Module Az.ResourceGraph` must not pull the real module in.
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:Root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:Root/src/collect/Get-ScoutArmChildResource.ps1"
    # Dot-sourced HERE on purpose. Get-ScoutRawInventory's own Import-ScoutRawInventoryHelper
    # falls back to dot-sourcing the file from inside a nested function, which defines the command
    # in that function's scope and not the caller's -- fine in production, where AzureScout.psm1
    # has already loaded every src/ file, but not something a test should depend on.
    . "$script:Root/src/collect/Get-ScoutOutageResource.ps1"
    . "$script:Root/src/collect/ConvertTo-ScoutArcSiteResource.ps1"
}

Describe 'AB#6770 -- Monitor/Outages sees the Resource Health events' {

    BeforeEach {
        $script:Queries = @()
        function Search-AzGraph {
            param([string] $Query, [Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            $script:Queries += $Query
            return @()
        }

        # The narrative headings are what Get-ScoutOutageResource keys on; an event whose
        # description lacks the last one is not an outage post-mortem and is skipped.
        $script:OutageDescription = @(
            '<p>What happened?</p><p>A regional storage incident.</p>'
            '<p>What went wrong and why?</p><p>A deployment regressed a cache.</p>'
            '<p>How did we respond?</p><p>The deployment was rolled back.</p>'
            '<p>How are we making incidents like this less likely or less impactful?</p><p>More canaries.</p>'
            '<p>How can customers make incidents like this less impactful?</p><p>Use zone redundancy.</p>'
        ) -join ''

        function New-MockHealthEvent {
            [pscustomobject]@{
                id         = '/subscriptions/sub-1/providers/Microsoft.ResourceHealth/events/event-one'
                name       = 'event-one'
                type       = 'Microsoft.ResourceHealth/events'
                properties = [pscustomobject]@{
                    eventType   = 'ServiceIssue'
                    status      = 'Resolved'
                    title       = 'Storage - East US'
                    description = $script:OutageDescription
                }
            }
        }

        function ConvertTo-ScoutManagementGroupHierarchy { param($Root) $null = $Root; @() }
        function Get-ScoutTenantWideResource { param([object[]] $ApiResources) $null = $ApiResources; @() }
    }

    It 'turns an event carried on the ARM REST sweep into an AZSC/Monitor/Outage envelope' {
        function Get-ScoutApiResources {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            [pscustomobject]@{ Subscription = 'sub-1'; ResourceHealth = @(New-MockHealthEvent) }
        }

        $result = Get-ScoutRawInventory

        $outages = @($result.Resources | Where-Object { $_.type -eq 'AZSC/Monitor/Outage' })
        $outages.Count | Should -Be 1
        $outages[0].properties.SourceResource.name | Should -Be 'event-one'
        $outages[0].properties.DescriptionSections.'What happened' | Should -Be 'A regional storage incident.'
        $outages[0].properties.DescriptionSections.'How can customers make incidents like this less impactful' |
            Should -Be 'Use zone redundancy.'
    }

    It 'does not append the raw event rows, which the orchestration adds from the same sweep' {
        # Appending them here as well would duplicate every Resource Health event on the
        # inventory path, where Start-AZTIExtractionOrchestration already adds them from the
        # ApiResources field this function returns.
        function Get-ScoutApiResources {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            [pscustomobject]@{ Subscription = 'sub-1'; ResourceHealth = @(New-MockHealthEvent) }
        }

        $result = Get-ScoutRawInventory

        @($result.Resources | Where-Object { $_.type -eq 'Microsoft.ResourceHealth/events' }) | Should -BeNullOrEmpty
        @($result.ApiResources).Count | Should -Be 1
    }

    It 'survives a subscription whose sweep returned no events at all' {
        # An EMPTY value on every element is what makes member enumeration throw under
        # StrictMode (AB#5633); a subscription with no incidents is the normal case.
        function Get-ScoutApiResources {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            @(
                [pscustomobject]@{ Subscription = 'sub-1'; ResourceHealth = @() }
                [pscustomobject]@{ Subscription = 'sub-2' }
                [pscustomobject]@{ Subscription = 'sub-3'; ResourceHealth = $null }
            )
        }

        { Get-ScoutRawInventory } | Should -Not -Throw
        @((Get-ScoutRawInventory).Resources | Where-Object { $_.type -eq 'AZSC/Monitor/Outage' }) |
            Should -BeNullOrEmpty
    }

    It 'runs the transform after the sweep, not before it' {
        # The defect in one assertion. With the ordering reversed the sweep result is still $null
        # when the transform runs, so the envelope count is zero no matter what the sweep returns.
        $script:SweepRan = $false
        function Get-ScoutApiResources {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            $script:SweepRan = $true
            [pscustomobject]@{ Subscription = 'sub-1'; ResourceHealth = @(New-MockHealthEvent) }
        }

        $result = Get-ScoutRawInventory

        $script:SweepRan | Should -BeTrue
        @($result.Resources | Where-Object { $_.type -eq 'AZSC/Monitor/Outage' }).Count | Should -Be 1
    }
}

Describe 'AB#6771 -- Management/LighthouseDelegations has a table to read' {

    BeforeEach {
        $script:Queries = @()
        function Search-AzGraph {
            param([string] $Query, [Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            $script:Queries += $Query
            if ($Query -match '^managedserviceresources') {
                return @([pscustomobject]@{
                        id             = '/subscriptions/sub-1/providers/Microsoft.ManagedServices/registrationDefinitions/def-one'
                        name           = 'def-one'
                        type           = 'microsoft.managedservices/registrationdefinitions'
                        subscriptionId = 'sub-1'
                        tags           = [pscustomobject]@{}
                        properties     = [pscustomobject]@{ managedByTenantId = 'tenant-managing' }
                    })
            }
            return @()
        }
        function Get-ScoutApiResources { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; @() }
        function ConvertTo-ScoutManagementGroupHierarchy { param($Root) $null = $Root; @() }
        function Get-ScoutTenantWideResource { param([object[]] $ApiResources) $null = $ApiResources; @() }
    }

    It 'queries managedserviceresources, filtered to registration definitions' {
        $null = Get-ScoutRawInventory -IncludeLighthouseDelegations

        $joined = $script:Queries -join "`n"
        $joined | Should -Match '(?m)^managedserviceresources\b'
        $joined | Should -Match "microsoft\.managedservices/registrationdefinitions"
    }

    It 'returns the delegation rows on Resources, where the collector reads them' {
        $result = Get-ScoutRawInventory -IncludeLighthouseDelegations

        $rows = @($result.Resources | Where-Object { $_.type -eq 'microsoft.managedservices/registrationdefinitions' })
        $rows.Count | Should -Be 1
        $rows[0].properties.managedByTenantId | Should -Be 'tenant-managing'
    }

    It 'does not project columns, because the table need not define the resources-table schema' {
        # A `project` naming a column the table does not have fails the WHOLE query, and this
        # table is not guaranteed to carry zones/extendedLocation/plan. The patch* tables skip
        # the projection for the same reason.
        $null = Get-ScoutRawInventory -IncludeLighthouseDelegations

        $lighthouse = @($script:Queries | Where-Object { $_ -match '^managedserviceresources' })
        $lighthouse.Count | Should -Be 1
        $lighthouse[0] | Should -Not -Match '\|\s*project\b'
    }

    It 'does not query the table when the switch is absent' {
        $null = Get-ScoutRawInventory

        ($script:Queries -join "`n") | Should -Not -Match '(?m)^managedserviceresources\b'
    }
}

Describe 'AB#6771 -- the production splat turns the pass on' {

    BeforeEach {
        . "$script:Root/src/collect/Start-ScoutGraphExtraction.ps1"

        $script:Splat = $null
        function Get-ScoutRawInventory {
            [CmdletBinding()]
            # Only the parameter under test is named; everything else the production splat carries
            # lands in -Rest, so this stub does not become a second copy of the real signature.
            param(
                $IncludeLighthouseDelegations,
                [Parameter(ValueFromRemainingArguments)] $Rest
            )
            $null = $Rest, $IncludeLighthouseDelegations
            $script:Splat = $PSBoundParameters
            [pscustomobject]@{
                Resources = @(); ResourceContainers = @(); Advisories = @()
                Security = @(); Retirements = @(); ApiResources = @()
            }
        }
        function Get-AZSCManagementGroups { param($ManagementGroup, $Subscriptions) $null = $ManagementGroup; $Subscriptions }
    }

    It 'sets -IncludeLighthouseDelegations' {
        # The assertion the suite was missing for its sibling defect (AB#6755): proving the
        # function HONOURS a switch says nothing about whether any production caller sets it.
        $null = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) -AzureEnvironment 'AzureCloud'

        [bool]$script:Splat['IncludeLighthouseDelegations'] | Should -BeTrue
    }
}

Describe 'AB#6769 -- Monitor/ResourceDiagnosticSettings is re-sourced via ARM REST' {

    BeforeEach {
        $script:ArmCalls = [System.Collections.Generic.List[string]]::new()
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Method, $Rest
            $script:ArmCalls.Add($Path)
            [PSCustomObject]@{
                StatusCode = 200
                Content    = (@{ value = @(@{
                                id         = "$Path/setting-one"
                                name       = 'setting-one'
                                type       = 'Microsoft.Insights/diagnosticSettings'
                                properties = @{
                                    workspaceId = '/subscriptions/sub-test/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-one'
                                    logs        = @(@{ category = 'AuditEvent'; enabled = $true })
                                    metrics     = @(@{ category = 'AllMetrics'; enabled = $true })
                                }
                            }) } | ConvertTo-Json -Depth 8 -Compress)
            }
        }

        function New-DiagParent {
            param([string]$Type, [string]$Name)
            [PSCustomObject]@{
                id             = "/subscriptions/sub-test/resourceGroups/rg-test/providers/$Type/$Name"
                type           = $Type
                name           = $Name
                subscriptionId = 'sub-test'
                resourceGroup  = 'rg-test'
                properties     = [PSCustomObject]@{}
            }
        }
    }

    AfterEach {
        Remove-Item -Path 'function:global:Invoke-AzRestMethod' -ErrorAction SilentlyContinue
    }

    It 'reads the extension endpoint per parent and emits the envelope the definition consumes' {
        $rows = @(Get-ScoutArmChildResource `
                -Resources @(New-DiagParent -Type 'microsoft.keyvault/vaults' -Name 'kv-one') `
                -Dataset @('ResourceDiagnosticSettings'))

        $rows.Count | Should -Be 1
        $rows[0].TYPE | Should -Be 'AZSC/ARMChild/ResourceDiagnosticSettings'
        $rows[0].PARENTNAME | Should -Be 'kv-one'
        $rows[0].PARENTTYPE | Should -Be 'microsoft.keyvault/vaults'
        $rows[0].subscriptionId | Should -Be 'sub-test'
        $rows[0].properties.workspaceId | Should -Match 'law-one'

        $script:ArmCalls.Count | Should -Be 1
        $script:ArmCalls[0] | Should -Match '/providers/Microsoft\.Insights/diagnosticSettings\?api-version=2021-05-01-preview$'
    }

    It 'is the type the definition declares' {
        # The two ends of the fix must agree, and nothing else in the repo checks that they do.
        $definition = Import-PowerShellDataFile "$script:Root/manifests/collectors/Monitor/ResourceDiagnosticSettings.psd1"

        @($definition.ResourceTypes) | Should -Be @('AZSC/ARMChild/ResourceDiagnosticSettings')
    }

    It 'does not sweep the high-count types the scope deliberately excludes' {
        # This is the cost control, and it is the reason this is a scoped sweep rather than one
        # REST call per resource in the estate. If a VM ever appears here, the run just got
        # 10-50x more expensive on any real tenant.
        $rows = @(Get-ScoutArmChildResource -Resources @(
                New-DiagParent -Type 'microsoft.compute/virtualmachines' -Name 'vm-one'
                New-DiagParent -Type 'microsoft.compute/disks' -Name 'disk-one'
                New-DiagParent -Type 'microsoft.network/networkinterfaces' -Name 'nic-one'
                New-DiagParent -Type 'microsoft.network/publicipaddresses' -Name 'pip-one'
            ) -Dataset @('ResourceDiagnosticSettings'))

        $rows | Should -BeNullOrEmpty
        $script:ArmCalls.Count | Should -Be 0
    }

    It 'produces no row for a parent that has no diagnostic setting, which is the finding' {
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Method, $Rest
            $script:ArmCalls.Add($Path)
            [PSCustomObject]@{ StatusCode = 200; Content = (@{ value = @() } | ConvertTo-Json -Compress) }
        }

        $rows = @(Get-ScoutArmChildResource `
                -Resources @(New-DiagParent -Type 'microsoft.storage/storageaccounts' -Name 'st-one') `
                -Dataset @('ResourceDiagnosticSettings'))

        $rows | Should -BeNullOrEmpty
        $script:ArmCalls.Count | Should -Be 1
    }

    It 'degrades one parent, not the dataset, when ARM refuses the call' {
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Method, $Rest
            $script:ArmCalls.Add($Path)
            if ($Path -match '/vaults/kv-bad/') { throw 'simulated ARM failure' }
            [PSCustomObject]@{
                StatusCode = 200
                Content    = (@{ value = @(@{ id = "$Path/setting-one"; name = 'setting-one'; properties = @{} }) } | ConvertTo-Json -Depth 8 -Compress)
            }
        }

        $warnings = @()
        $rows = @(Get-ScoutArmChildResource -Resources @(
                New-DiagParent -Type 'microsoft.keyvault/vaults' -Name 'kv-bad'
                New-DiagParent -Type 'microsoft.keyvault/vaults' -Name 'kv-good'
            ) -Dataset @('ResourceDiagnosticSettings') -WarningVariable warnings)

        $rows.Count | Should -Be 1
        $rows[0].PARENTNAME | Should -Be 'kv-good'
        $warnings.Count | Should -Be 1
        $warnings[0].Message | Should -Match 'ResourceDiagnosticSettings'
    }
}

Describe 'AB#6802 -- Hybrid/VirtualMachines is re-sourced via ARM REST' {

    BeforeEach {
        $script:ArmCalls = [System.Collections.Generic.List[string]]::new()
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Method, $Rest
            $script:ArmCalls.Add($Path)
            [PSCustomObject]@{
                StatusCode = 200
                Content    = (@{
                        id         = "$Path"
                        name       = 'default'
                        type       = 'Microsoft.AzureStackHCI/virtualMachineInstances'
                        properties = @{
                            hardwareProfile = @{ vmSize = 'Standard_D4s_v3'; processors = 4; memoryMB = 8192 }
                            osProfile       = @{ osType = 'Windows'; computerName = 'vm-one' }
                            provisioningState = 'Succeeded'
                        }
                    } | ConvertTo-Json -Depth 8 -Compress)
            }
        }

        function New-MachineParent {
            param([string]$Name = 'arc-machine-one')
            [PSCustomObject]@{
                id             = "/subscriptions/sub-test/resourceGroups/rg-test/providers/microsoft.hybridcompute/machines/$Name"
                type           = 'microsoft.hybridcompute/machines'
                name           = $Name
                location       = 'eastus'
                subscriptionId = 'sub-test'
                resourceGroup  = 'rg-test'
                properties     = [PSCustomObject]@{}
            }
        }
    }

    AfterEach {
        Remove-Item -Path 'function:global:Invoke-AzRestMethod' -ErrorAction SilentlyContinue
    }

    It 'reads the virtualMachineInstances singleton per Arc machine, not the Resource Graph resources table' {
        $rows = @(Get-ScoutArmChildResource -Resources @(New-MachineParent) -Dataset @('AzureLocalVirtualMachineInstances'))

        $rows.Count | Should -Be 1
        $rows[0].TYPE | Should -Be 'AZSC/ARMChild/AzureLocalVirtualMachineInstances'
        $rows[0].PARENTNAME | Should -Be 'arc-machine-one'
        $rows[0].PARENTTYPE | Should -Be 'microsoft.hybridcompute/machines'
        $rows[0].PARENTLOCATION | Should -Be 'eastus'
        $rows[0].properties.hardwareProfile.vmSize | Should -Be 'Standard_D4s_v3'

        $script:ArmCalls.Count | Should -Be 1
        $script:ArmCalls[0] | Should -Match '/providers/Microsoft\.AzureStackHCI/virtualMachineInstances/default\?api-version=2024-01-01$'
    }

    It 'is the type the definition declares' {
        $definition = Import-PowerShellDataFile "$script:Root/manifests/collectors/Hybrid/VirtualMachines.psd1"

        @($definition.ResourceTypes) | Should -Be @('AZSC/ARMChild/AzureLocalVirtualMachineInstances')
    }

    It 'produces no row for an Arc machine that is not an Azure Local guest, which is the finding' {
        function global:Invoke-AzRestMethod {
            param([string]$Path, [string]$Method, [Parameter(ValueFromRemainingArguments)]$Rest)
            $null = $Method, $Rest
            $script:ArmCalls.Add($Path)
            throw 'ResourceNotFound'
        }

        $rows = @(Get-ScoutArmChildResource -Resources @(New-MachineParent) -Dataset @('AzureLocalVirtualMachineInstances') -WarningAction SilentlyContinue)

        $rows | Should -BeNullOrEmpty
        $script:ArmCalls.Count | Should -Be 1
    }

    It 'feeds Compute/AVDAzureLocal by way of the PARENTNAME/PARENTLOCATION-preferring session-host transform' {
        . "$script:Root/src/collect/ConvertTo-ScoutAvdAzureLocalSessionHost.ps1"

        $armChildRows = @(Get-ScoutArmChildResource -Resources @(New-MachineParent) -Dataset @('AzureLocalVirtualMachineInstances'))
        $armChildRows[0] | Add-Member -NotePropertyName tags -NotePropertyValue ([pscustomobject]@{ AvdSessionHost = 'true' }) -Force

        $sessionHosts = @(ConvertTo-ScoutAvdAzureLocalSessionHost -Resources $armChildRows)

        $sessionHosts.Count | Should -Be 1
        $sessionHosts[0].TYPE | Should -Be 'AZSC/AVD/AzureLocalSessionHost'
        $sessionHosts[0]._Platform | Should -Be 'AzureLocal'
        # The child envelope's own NAME is the fixed string 'default' and it carries no LOCATION
        # at all -- PARENTNAME/PARENTLOCATION must win, or every Azure Local row in the AVD
        # worksheet reads 'default' where a VM name belongs.
        $sessionHosts[0].NAME | Should -Be 'arc-machine-one'
        $sessionHosts[0].LOCATION | Should -Be 'eastus'
    }
}

Describe 'AB#6801 -- Hybrid/ArcSites is re-sourced via ARM REST' {

    BeforeEach {
        function ConvertTo-ScoutManagementGroupHierarchy { param($Root) $null = $Root; @() }
        function Get-ScoutTenantWideResource { param([object[]] $ApiResources) $null = $ApiResources; @() }
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; @() }
    }

    It 'is the type the definition declares' {
        $definition = Import-PowerShellDataFile "$script:Root/manifests/collectors/Hybrid/ArcSites.psd1"

        @($definition.ResourceTypes) | Should -Be @('AZSC/ARMChild/ArcSites')
    }

    It 'turns the per-subscription Microsoft.Edge/sites sweep into AZSC/ARMChild/ArcSites rows, not a Resource Graph query' {
        function Get-ScoutApiResources {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            [pscustomobject]@{
                Subscription = 'sub-1'
                ArcSites     = @(
                    [pscustomobject]@{
                        id         = '/subscriptions/sub-1/resourceGroups/rg-arc/providers/Microsoft.Edge/sites/site-one'
                        name       = 'site-one'
                        type       = 'Microsoft.Edge/sites'
                        properties = [pscustomobject]@{ displayName = 'Store 42'; description = 'Retail site' }
                    }
                )
            }
        }

        $result = Get-ScoutRawInventory

        $rows = @($result.Resources | Where-Object { $_.TYPE -eq 'AZSC/ARMChild/ArcSites' })
        $rows.Count | Should -Be 1
        $rows[0].name | Should -Be 'site-one'
        $rows[0].subscriptionId | Should -Be 'sub-1'
        $rows[0].RESOURCEGROUP | Should -Be 'rg-arc'
        $rows[0].properties.displayName | Should -Be 'Store 42'

        # No AzureStackHCI/EdgeConfig/HybridCompute 'sites' Resource Graph query was ever issued
        # -- those three type strings do not exist, which is why the collector was retired rather
        # than corrected in AB#6842.
        @($result.Resources | Where-Object { $_.TYPE -match '(?i)sites$' -and $_.TYPE -ne 'AZSC/ARMChild/ArcSites' }) |
            Should -BeNullOrEmpty
    }

    It 'survives a subscription whose sweep returned no sites at all' {
        function Get-ScoutApiResources {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Rest
            @(
                [pscustomobject]@{ Subscription = 'sub-1'; ArcSites = @() }
                [pscustomobject]@{ Subscription = 'sub-2' }
                [pscustomobject]@{ Subscription = 'sub-3'; ArcSites = $null }
            )
        }

        { Get-ScoutRawInventory } | Should -Not -Throw
        @((Get-ScoutRawInventory).Resources | Where-Object { $_.TYPE -eq 'AZSC/ARMChild/ArcSites' }) |
            Should -BeNullOrEmpty
    }
}
