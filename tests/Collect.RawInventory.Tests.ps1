#Requires -Version 7.0
#Requires -Modules Pester

<#
    Pester tests for src/collect/Get-ScoutRawInventory.ps1 (AB#5639/5642, Epic AB#5638).

    Search-AzGraph is mocked throughout -- no live Azure connection is made.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }
    . "$root/src/collect/Get-ScoutRawInventory.ps1"
    . "$root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$root/src/collect/Invoke-Collect.ps1"

    function New-MockSubscriptionRow {
        param([string] $Id)
        [pscustomobject]@{ id = "/subscriptions/$Id"; name = "sub-$Id"; type = 'microsoft.resources/subscriptions'; subscriptionId = $Id; properties = [pscustomobject]@{ state = 'Enabled' } }
    }
}

Describe 'Get-ScoutRawInventory -- table coverage' {
    It 'always queries resources, networkresources and resourcecontainers' {
        $script:queries = @()
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            $script:queries += $Query
            return @()
        }
        Get-ScoutRawInventory | Out-Null
        ($script:queries -join "`n") | Should -Match '(?m)^resources\b'
        ($script:queries -join "`n") | Should -Match '(?m)^networkresources\b'
        ($script:queries -join "`n") | Should -Match '(?m)^resourcecontainers\b'
    }

    It 'does not query SupportResources/recoveryservicesresources/desktopvirtualizationresources/advisorresources/securityresources unless asked' {
        $script:queries = @()
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            $script:queries += $Query
            return @()
        }
        Get-ScoutRawInventory | Out-Null
        ($script:queries -join "`n") | Should -Not -Match '(?m)^SupportResources\b'
        ($script:queries -join "`n") | Should -Not -Match '(?m)^recoveryservicesresources\b'
        ($script:queries -join "`n") | Should -Not -Match '(?m)^desktopvirtualizationresources\b'
        ($script:queries -join "`n") | Should -Not -Match '(?m)^advisorresources\b'
        ($script:queries -join "`n") | Should -Not -Match '(?m)^securityresources\b'
    }

    It 'queries every extra table when every -Include switch is supplied' {
        $script:queries = @()
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            $script:queries += $Query
            return @()
        }
        Get-ScoutRawInventory -IncludeSupportResources -IncludeBackupResources -IncludeDesktopVirtualization -IncludeAdvisories -IncludeSecurityCenter | Out-Null
        ($script:queries -join "`n") | Should -Match '(?m)^SupportResources\b'
        ($script:queries -join "`n") | Should -Match '(?m)^recoveryservicesresources\b'
        ($script:queries -join "`n") | Should -Match '(?m)^desktopvirtualizationresources\b'
        ($script:queries -join "`n") | Should -Match '(?m)^advisorresources\b'
        ($script:queries -join "`n") | Should -Match '(?m)^securityresources\b'
    }

    It 'returns the Start-AZTIGraphExtraction-compatible shape' {
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) return @() }
        $result = Get-ScoutRawInventory
        $result.PSObject.Properties.Name | Should -Contain 'Resources'
        $result.PSObject.Properties.Name | Should -Contain 'ResourceContainers'
        $result.PSObject.Properties.Name | Should -Contain 'Advisories'
        $result.PSObject.Properties.Name | Should -Contain 'Security'
    }

    It 'does not invoke optional non-ARG helpers unless their switches are supplied' {
        $script:armChildCalls = 0
        $script:subscriptionSweepCalls = 0
        $script:operationalEnrichmentCalls = 0
        function Get-ScoutArmChildResource { $script:armChildCalls++ }
        function Get-ScoutSubscriptionSecurityPolicySweep { $script:subscriptionSweepCalls++ }
        function Get-ScoutOperationalCollectorEnrichment { $script:operationalEnrichmentCalls++ }
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) return @() }

        Get-ScoutRawInventory | Out-Null

        $script:armChildCalls | Should -Be 0
        $script:subscriptionSweepCalls | Should -Be 0
        $script:operationalEnrichmentCalls | Should -Be 0
    }

    It 'DOES invoke the tenant-wide helper, because it is not optional' {
        # Deliberately split out of the test above rather than left in it with a flipped number.
        # Tenant-wide collection used to sit behind a switch and now does not (AB#6755): the four
        # datasets it produces are what a governance assessment scores, and an assessment reading
        # an empty array reports a false pass. There is no switch to supply.
        $script:tenantWideCalls = 0
        function Get-ScoutTenantWideResource { param([object[]] $ApiResources) $script:tenantWideCalls++ }
        function Get-ScoutApiResources { param([Parameter(ValueFromRemainingArguments)] $Rest) @() }
        function ConvertTo-ScoutManagementGroupHierarchy { param($Root) @() }
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) return @() }

        Get-ScoutRawInventory | Out-Null

        $script:tenantWideCalls | Should -Be 1
    }
}

Describe 'Get-ScoutRawInventory -- optional synthetic resource envelopes' {
    BeforeEach {
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resourcecontainers\b') { return @((New-MockSubscriptionRow -Id 'sub-1')) }
            if ($Query -match '^resources\b') {
                return @([pscustomobject]@{
                        id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.MachineLearningServices/workspaces/ml-one'
                        name = 'ml-one'; type = 'microsoft.machinelearningservices/workspaces'; subscriptionId = 'sub-1'
                        resourceGroup = 'rg'; kind = $null; properties = [pscustomobject]@{}
                    })
            }
            return @()
        }
    }

    It 'appends ARM child rows exactly once when requested' {
        $script:armChildInputs = @()
        function Get-ScoutArmChildResource {
            param([object[]] $Resources)
            $script:armChildInputs += , @($Resources)
            [pscustomobject]@{ id = 'synthetic-child'; type = 'AZSC/ARMChild/MLComputes'; properties = @() }
        }

        $result = Get-ScoutRawInventory -IncludeArmChildResources

        $script:armChildInputs.Count | Should -Be 1
        @($result.Resources | Where-Object id -eq 'synthetic-child').Count | Should -Be 1
    }

    It 'appends one subscription security/policy envelope per resolved subscription when requested' {
        $script:sweepSubscriptions = @()
        function Get-ScoutSubscriptionSecurityPolicySweep {
            param([object[]] $Subscriptions)
            $script:sweepSubscriptions += , @($Subscriptions)
            foreach ($subscription in $Subscriptions) {
                [pscustomobject]@{
                    id = "sweep-$($subscription.id)"; type = 'AZSC/Subscription/SecurityPolicySweep'
                    subscriptionId = $subscription.id; properties = @{}
                }
            }
        }

        $result = Get-ScoutRawInventory -IncludeSubscriptionSecurityPolicy

        $script:sweepSubscriptions.Count | Should -Be 1
        $script:sweepSubscriptions[0][0].id | Should -Be 'sub-1'
        @($result.Resources | Where-Object type -eq 'AZSC/Subscription/SecurityPolicySweep').Count | Should -Be 1
    }

    It 'feeds API results into tenant-wide envelopes without changing assessment-shaped rows' {
        $script:apiSubscriptions = @()
        function Get-ScoutApiResources {
            param([object[]] $Subscriptions, [string] $AzureEnvironment)
            $script:apiSubscriptions += , @($Subscriptions)
            [pscustomobject]@{ PolicyDefinitions = @([pscustomobject]@{ id = 'policy-1' }); PolicySetDefinitions = @() }
        }
        function ConvertTo-ScoutManagementGroupHierarchy { param($Root) @() }
        function Get-ScoutTenantWideResource {
            param([object[]] $ApiResources)
            @(
                [pscustomobject]@{ type = 'AZSC/Management/RoleDefinition'; properties = @() }
                [pscustomobject]@{ type = 'AZSC/Management/PolicyDefinition'; properties = @($ApiResources[0].PolicyDefinitions) }
            )
        }

        # No switch: tenant-wide collection is unconditional (AB#6755). This test used to pass
        # `-IncludeTenantWideResources` explicitly, which is precisely why nothing noticed that
        # no production caller did -- proving the function HONOURS a switch says nothing about
        # whether anything sets it.
        $result = Get-ScoutRawInventory
        $shaped = ConvertFrom-ScoutInventory -Resources $result.Resources -ResourceContainers $result.ResourceContainers

        $script:apiSubscriptions.Count | Should -Be 1
        $script:apiSubscriptions[0][0].id | Should -Be 'sub-1'
        @($result.Resources | Where-Object type -eq 'AZSC/Management/RoleDefinition').Count | Should -Be 1
        @($result.Resources | Where-Object type -eq 'AZSC/Management/PolicyDefinition').Count | Should -Be 1
        @($shaped.virtualNetworks).Count | Should -Be 0
    }

    It 'appends operational enrichment only when explicitly requested' {
        $script:operationalInputs = @()
        function Get-ScoutOperationalCollectorEnrichment {
            param([object[]] $Resources, [object[]] $Subscriptions)
            $script:operationalInputs += , [pscustomobject]@{ Resources = @($Resources); Subscriptions = @($Subscriptions) }
            [pscustomobject]@{ id = 'operational-vm'; type = 'AZSC/Operational/VirtualMachine'; properties = @{} }
        }

        $result = Get-ScoutRawInventory -IncludeOperationalCollectorEnrichment

        $script:operationalInputs.Count | Should -Be 1
        $script:operationalInputs[0].Resources.Count | Should -BeGreaterThan 0
        $script:operationalInputs[0].Subscriptions[0].id | Should -Be 'sub-1'
        @($result.Resources | Where-Object type -eq 'AZSC/Operational/VirtualMachine').Count | Should -Be 1
    }
}

Describe 'Get-ScoutRawInventory -- SkipToken paging' {
    It 'follows SkipToken across pages and stops when it is absent' {
        # Search-AzGraph really returns a collection that both enumerates as the row objects
        # AND carries a `.SkipToken` note property on the collection itself (see the
        # documented `$response = Search-AzGraph ...; ... -SkipToken $response.SkipToken`
        # pattern) -- Add-Member on an array instance reproduces that shape for the mock.
        $script:callNumber = 0
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -notmatch '^resources\b') { return @() }
            $script:callNumber++
            if ($script:callNumber -eq 1) {
                $page = @([pscustomobject]@{ id = 'r1' })
                Add-Member -InputObject $page -NotePropertyName SkipToken -NotePropertyValue 'page2' -Force
                return , $page
            }
            $page = @([pscustomobject]@{ id = 'r2' })
            Add-Member -InputObject $page -NotePropertyName SkipToken -NotePropertyValue $null -Force
            return , $page
        }
        $result = Get-ScoutRawInventory
        $script:callNumber | Should -Be 2
        @($result.Resources | Where-Object { $_.id -in @('r1', 'r2') }).Count | Should -Be 2
    }
}

Describe 'Get-ScoutRawInventory -- subscription batching' {
    It 'batches an explicit subscription list into groups of 1000' {
        $ids = 1..2500 | ForEach-Object { "sub-$_" }
        $script:batchSizes = @()
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resources\b') { $script:batchSizes += @($Subscription).Count }
            return @()
        }
        Get-ScoutRawInventory -SubscriptionIds $ids | Out-Null
        $script:batchSizes.Count | Should -Be 3
        $script:batchSizes | Should -Be @(1000, 1000, 500)
    }

    It 'derives the subscription list from resourcecontainers when none is supplied' {
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resourcecontainers\b') {
                return @((New-MockSubscriptionRow -Id 'aaa'), (New-MockSubscriptionRow -Id 'bbb'))
            }
            return @()
        }
        $result = Get-ScoutRawInventory
        $result.ResourceContainers.Count | Should -Be 2
    }

    It 'actually scopes the later tables to the derived subscription list' {
        # Regression guard: `@($SubscriptionIds)` on an unbound [string[]] parameter is
        # `@($null)`, whose .Count is 1 -- so the "no explicit list supplied" branch never
        # fired on the DEFAULT path and every table after resourcecontainers silently ran as
        # one un-batched tenant-wide call. The assertion above (container count only) passed
        # either way, which is exactly why this one checks the -Subscription argument.
        $script:resourceCallSubscriptions = @()
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resourcecontainers\b') {
                return @((New-MockSubscriptionRow -Id 'aaa'), (New-MockSubscriptionRow -Id 'bbb'))
            }
            if ($Query -match '^resources\b') { $script:resourceCallSubscriptions += , @($Subscription) }
            return @()
        }
        Get-ScoutRawInventory -WarningAction SilentlyContinue | Out-Null
        $script:resourceCallSubscriptions.Count | Should -Be 1
        @($script:resourceCallSubscriptions[0] | Sort-Object) | Should -Be @('aaa', 'bbb')
    }
}

Describe 'Get-ScoutRawInventory -- throttling and error resilience' {
    It 'retries a throttled (429) response with backoff before succeeding' {
        $script:attempts = 0
        Mock Start-Sleep { }
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resources\b') {
                $script:attempts++
                if ($script:attempts -lt 2) { throw 'Status: 429 (Too Many Requests)' }
                return @([pscustomobject]@{ id = 'r1' })
            }
            return @()
        }
        $result = Get-ScoutRawInventory
        $script:attempts | Should -Be 2
        @($result.Resources) | Where-Object { $_.id -eq 'r1' } | Should -Not -BeNullOrEmpty
    }

    It 'warns and skips (without throwing) a non-throttling failure' {
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resources\b') { throw 'AuthorizationFailed: access denied' }
            return @()
        }
        Get-ScoutRawInventory -WarningVariable w -WarningAction SilentlyContinue | Out-Null
        ($w -join "`n") | Should -Match 'AuthorizationFailed'
    }

    It 'warns with a diagnostic hint when literally nothing came back' {
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) return @() }
        Get-ScoutRawInventory -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        ($warnings -join "`n") | Should -Match 'zero resources'
    }
}

Describe 'Get-ScoutRawInventory -- Invoke-Collect -FromInventory interoperability' {
    # The whole point of AB#5639 is that src/collect owns ONE pass whose rows feed
    # everything. `Get-ScoutRawInventory`'s comment-based help claims its output is a
    # drop-in `-FromInventory` argument; nothing asserted that, so this pins the
    # contract end to end (both functions mocked off Azure, no live call).

    It 'produces a row set Invoke-Collect can shape without going back to Resource Graph' {
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resourcecontainers\b') {
                return @([pscustomobject]@{
                        id = '/subscriptions/aaa'; name = 'demo-sub'; type = 'microsoft.resources/subscriptions'
                        subscriptionId = 'aaa'; location = $null; resourceGroup = $null
                        properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null
                    })
            }
            if ($Query -match '^resources\b') {
                return @([pscustomobject]@{
                        id = '/subscriptions/aaa/rg/x/vnet1'; name = 'vnet1'; type = 'microsoft.network/virtualnetworks'
                        subscriptionId = 'aaa'; resourceGroup = 'rg-net'; location = 'eastus'
                        kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                        extendedLocation = $null; managedBy = $null
                        properties = [pscustomobject]@{
                            enableDdosProtection   = $false
                            virtualNetworkPeerings = @([pscustomobject]@{ name = 'peer1' })
                            subnets                = @()
                        }
                    })
            }
            return @()
        }

        $raw = Get-ScoutRawInventory -WarningAction SilentlyContinue
        $collect = Invoke-Collect -FromInventory $raw -Categories 'Networking' -WarningAction SilentlyContinue

        @($collect.subscriptions).Count | Should -Be 1
        $collect.subscriptions[0].id | Should -Be 'aaa'
        $collect.subscriptions[0].name | Should -Be 'demo-sub'

        # The scalar the rules actually filter on has to survive the round trip, not just
        # the row count -- peeringCount is computed in KQL on the live path and in
        # PowerShell on this one, so it is the honest end-to-end check.
        @($collect.networking.virtualNetworks).Count | Should -Be 1
        $collect.networking.virtualNetworks[0].name | Should -Be 'vnet1'
        $collect.networking.virtualNetworks[0].peeringCount | Should -Be 1
        $collect.networking.virtualNetworks[0].ddosEnabled | Should -BeFalse
    }
}

Describe 'Get-ScoutRawInventory -- management group scoping' {
    It 'passes -ManagementGroup on the tenant-wide call when no subscription list is known yet' {
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            if ($Query -match '^resourcecontainers\b') { $script:sawMg = $ManagementGroup }
            return @()
        }
        Get-ScoutRawInventory -ManagementGroupId 'contoso-root-mg' | Out-Null
        $script:sawMg | Should -Be 'contoso-root-mg'
    }
}
