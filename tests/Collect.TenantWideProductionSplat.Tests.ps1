#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6755 / AB#6758 — the production splat must SET -IncludeTenantWideResources.

    `-IncludeTenantWideResources` arrived with AB#5933 as a temporary migration gate and was
    never removed once its consumers shipped. No production caller set it, so
    `Get-ScoutTenantWideResource` never ran and the ManagementGroups, CustomRoleDefinitions,
    PolicyDefinitions and PolicySetDefinitions collectors read an empty resource list on every
    run since — four worksheets silently blank, and four assessments (Landing Zone, AVS Landing
    Zone, Cloud Governance, CASA) scoring against nothing.

    Three separate safeguards missed it, and the shape of each miss dictates the shape of the
    tests here:

      1. `Get-ScoutRawInventory` returns the tenant-wide envelopes empty BY DESIGN when the
         switch is off, so nothing threw.
      2. `tests/Collect.RawInventory.Tests.ps1` passes `-IncludeTenantWideResources` explicitly,
         proving only that the function HONOURS the switch — which was never in doubt.
      3. A permission theory (Management Group Reader) absorbed the blame for the empty rows.

    So these tests assert the one thing none of those did: that the argument hashtable each
    PRODUCTION entry point builds carries the switch. They stub `Get-ScoutRawInventory` and
    capture what the caller actually splatted, which is the only place the defect lived.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent

    # Get-ScoutRawInventory's `Import-Module Az.ResourceGraph` must not pull the real module in.
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }
}

Describe 'AB#6755 — the inventory production splat (Start-AZSCGraphExtraction)' {

    BeforeEach {
        . "$script:Root/src/collect/Start-ScoutGraphExtraction.ps1"

        $script:Splat = $null
        # Only the two parameters under test are named; everything else the production splat
        # carries lands in -Rest. Naming them all would make this stub a second copy of the
        # real signature and it would rot the first time one is added.
        function Get-ScoutRawInventory {
            [CmdletBinding()]
            param(
                $IncludeTenantWideResources,
                $SkipPolicy,
                [Parameter(ValueFromRemainingArguments)] $Rest
            )
            $script:Splat = $PSBoundParameters
            [pscustomobject]@{
                Resources = @(); ResourceContainers = @(); Advisories = @()
                Security = @(); Retirements = @()
                ApiResources = @([pscustomobject]@{ Subscription = 'sub-1' })
            }
        }
        function Get-AZSCManagementGroups { param($ManagementGroup, $Subscriptions) $Subscriptions }
    }

    It 'sets -IncludeTenantWideResources on an ordinary run' {
        $null = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) -AzureEnvironment 'AzureCloud'

        $script:Splat.Keys | Should -Contain 'IncludeTenantWideResources'
        [bool]$script:Splat['IncludeTenantWideResources'] | Should -BeTrue
    }

    It 'clears -IncludeTenantWideResources when the operator asked to skip the ARM REST APIs' {
        # -SkipAPIs is the existing "Resource Graph only" flag. Tenant-wide collection is ARM
        # REST work, so it belongs on the far side of that switch and nowhere else.
        $null = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) -AzureEnvironment 'AzureCloud' -SkipAPIs $true

        [bool]$script:Splat['IncludeTenantWideResources'] | Should -BeFalse
    }

    It 'forwards -SkipPolicy so the sweep it drives matches what the operator asked for' {
        $null = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) -AzureEnvironment 'AzureCloud' -SkipPolicy $true

        [bool]$script:Splat['SkipPolicy'] | Should -BeTrue
    }

    It 'hands the ARM REST sweep back up so the orchestration does not repeat it' {
        $result = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) -AzureEnvironment 'AzureCloud'

        @($result.ApiResources).Count | Should -Be 1
        $result.ApiResources[0].Subscription | Should -Be 'sub-1'
    }
}

Describe 'AB#6755 — the assessment production splat (Invoke-Collect)' {

    It 'sets -IncludeTenantWideResources on the single-pass raw collection' {
        # Invoke-Collect is large and its raw-pass block is one branch deep inside it. Reading
        # the splat out of the source is the assertion that survives refactors of everything
        # around it, and it fails for exactly the reason the defect existed: the key is absent.
        $source = Get-Content -Raw "$script:Root/src/collect/Invoke-Collect.ps1"

        $source | Should -Match '\$rawArgs\s*=\s*@\{[^}]*IncludeTenantWideResources\s*=\s*\$true'
    }

    It 'does not set -SkipPolicy, because the policy definitions are what it collects for' {
        $source = Get-Content -Raw "$script:Root/src/collect/Invoke-Collect.ps1"
        $rawArgsLine = ([regex]'\$rawArgs\s*=\s*@\{[^}]*\}').Match($source).Value

        $rawArgsLine | Should -Not -Match 'SkipPolicy'
    }

    It 'narrows the sweep with -TenantWideDefinitionsOnly rather than paying for all seven calls' {
        $source = Get-Content -Raw "$script:Root/src/collect/Invoke-Collect.ps1"

        $source | Should -Match '\$rawArgs\s*=\s*@\{[^}]*TenantWideDefinitionsOnly\s*=\s*\$true'
    }
}

Describe 'AB#6755 / AB#6759 — the measured cost of the narrowed sweep' {

    BeforeEach {
        . "$script:Root/src/collect/Get-ScoutApiResources.ps1"

        $script:Uris = [System.Collections.Generic.List[string]]::new()
        function Get-AzAccessToken {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            [pscustomobject]@{ Token = (ConvertTo-SecureString 'stub' -AsPlainText -Force) }
        }
        function Invoke-RestMethod {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $script:Uris.Add(($Rest -join ' '))
            [pscustomobject]@{ value = @() }
        }
        function Start-Sleep { param([Parameter(ValueFromRemainingArguments)] $Rest) }
    }

    It 'issues seven calls per subscription for a full sweep and two for -DefinitionsOnly' {
        # The exact numbers are the point of AB#6759: this is the per-subscription REST cost the
        # assessment path now pays that it did not pay before. If either count moves, the number
        # recorded on the work item is stale and this test says so.
        $subs = @([pscustomobject]@{ id = 'sub-1'; name = 'Sub One' })

        $null = Get-ScoutApiResources -Subscriptions $subs
        $full = $script:Uris.Count

        $script:Uris.Clear()
        $null = Get-ScoutApiResources -Subscriptions $subs -DefinitionsOnly
        $definitionsOnly = $script:Uris.Count

        $full | Should -Be 7
        $definitionsOnly | Should -Be 2
        ($script:Uris -join ' ') | Should -Match 'policyDefinitions'
        ($script:Uris -join ' ') | Should -Match 'policySetDefinitions'
        ($script:Uris -join ' ') | Should -Not -Match 'ResourceHealth'
        ($script:Uris -join ' ') | Should -Not -Match 'policyStates'
    }

    It 'refuses the contradictory combination rather than silently collecting nothing' {
        { Get-ScoutApiResources -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) -DefinitionsOnly -SkipPolicy } |
            Should -Throw '*cannot be combined*'
    }
}

Describe 'AB#6755 — Get-ScoutRawInventory returns the sweep it ran' {

    BeforeEach {
        . "$script:Root/src/collect/Get-ScoutRawInventory.ps1"

        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) @() }
        function Get-AzContext { $null }
        function ConvertTo-ScoutManagementGroupHierarchy { param($Root) @() }
        function Get-ScoutTenantWideResource { param([object[]] $ApiResources) @() }
    }

    It 'is empty when tenant-wide collection is off — the only state that existed before' {
        function Get-ScoutApiResources { param([Parameter(ValueFromRemainingArguments)] $Rest) throw 'must not be called' }

        $result = Get-ScoutRawInventory

        @($result.ApiResources).Count | Should -Be 0
    }

    It 'carries the per-subscription results when tenant-wide collection is on' {
        function Get-ScoutApiResources {
            param([object[]] $Subscriptions, [string] $AzureEnvironment, [switch] $SkipPolicy)
            @([pscustomobject]@{ Subscription = 'sub-1'; SkipPolicyWas = [bool]$SkipPolicy })
        }

        $result = Get-ScoutRawInventory -SubscriptionIds @('sub-1') -IncludeTenantWideResources

        @($result.ApiResources).Count | Should -Be 1
        $result.ApiResources[0].Subscription | Should -Be 'sub-1'
        $result.ApiResources[0].SkipPolicyWas | Should -BeFalse
    }

    It 'forwards -SkipPolicy into the sweep' {
        function Get-ScoutApiResources {
            param([object[]] $Subscriptions, [string] $AzureEnvironment, [switch] $SkipPolicy)
            @([pscustomobject]@{ Subscription = 'sub-1'; SkipPolicyWas = [bool]$SkipPolicy })
        }

        $result = Get-ScoutRawInventory -SubscriptionIds @('sub-1') -IncludeTenantWideResources -SkipPolicy

        $result.ApiResources[0].SkipPolicyWas | Should -BeTrue
    }
}
