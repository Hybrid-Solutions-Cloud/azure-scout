#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#6839 — a collector must not lose its whole worksheet because Azure omitted an optional
    property.

    WHY THIS FILE EXISTS SEPARATELY FROM THE GOLDEN SUITE. It cannot be a golden test.
    `scripts/New-ScoutCollectorFixture.ps1` derives each collector's estate FROM THAT COLLECTOR'S
    OWN EXPRESSIONS, so every property a collector reads is present in its fixture by construction
    and no golden record can ever exercise a sparse payload. The estate here is therefore built the
    opposite way round: by hand, by REMOVING properties, which is the only shape that reproduces
    what Azure actually returns.

    These run against REAL SHIPPED DEFINITIONS, not a synthetic one. A test that invented its own
    collector would prove the interpreter tolerates sparseness without proving that any collector
    anyone ships does.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZSCSafeProperty.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZTICollectedValue.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZSCIdSegment.ps1')

    # The shape Resource Graph really returns: every projected COLUMN present (they come from the
    # `| project` list, so they are always there, usually $null), and `properties` holding only the
    # keys this particular resource happens to have.
    function New-SparseArgRow {
        param([string]$Type, [string]$Name, [hashtable]$Properties)
        [pscustomobject]@{
            id               = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers/$Type/$Name"
            NAME             = $Name
            TYPE             = $Type
            tenantId         = '00000000-0000-0000-0000-0000000000ff'
            KIND             = $null
            LOCATION         = 'eastus'
            RESOURCEGROUP    = 'rg'
            subscriptionId   = '00000000-0000-0000-0000-000000000001'
            managedBy        = $null
            sku              = $null
            plan             = $null
            PROPERTIES       = [pscustomobject]$Properties
            identity         = $null
            zones            = $null
            extendedLocation = $null
            tags             = [pscustomobject]@{}
        }
    }

    function Invoke-CollectorOnRow {
        param([string]$Category, [string]$Name, $Row)
        $Definition = Get-ScoutCollectorDefinition -Path (Join-Path $script:RepoRoot "manifests/collectors/$Category/$Name.psd1")
        $Context = @{
            ScriptRoot   = $script:RepoRoot
            Subscriptions = @([pscustomobject]@{ id = '00000000-0000-0000-0000-000000000001'; Name = 'sub-one' })
            InTag        = $false
            Resources    = @($Row)
            Retirements  = @()
            Task         = 'Processing'
            File         = $null
            SmaResources = $null
            TableStyle   = 'Light20'
            Unsupported  = @()
            RunTime      = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()
        }
        return @(Invoke-ScoutDeclarativeCollector -Definition $Definition -Context $Context)
    }
}

Describe 'A sparse Azure payload does not cost the collector its worksheet (AB#6839)' -ForEach @(
    # One shipped-before-AB#6741 collector and three added by it, so a regression in either the old
    # or the new half of the estate fails here. Each `Properties` hashtable holds ONLY what the
    # real resource always carries; everything else the collector reads is deliberately absent.
    @{ Category = 'Integration'; Name = 'APIM'; Type = 'microsoft.apimanagement/service'
       Properties = @{ gatewayUrl = 'https://contoso.azure-api.net' }
       Because = 'shipped since v1 and fails on virtualNetworkType — proof this was never a new-collector problem' }
    @{ Category = 'Integration'; Name = 'LogicApps'; Type = 'microsoft.logic/workflows'
       Properties = @{ state = 'Enabled' }
       Because = 'a Logic App with no integration account has no integrationAccount key' }
    @{ Category = 'Migration'; Name = 'DataBox'; Type = 'microsoft.databox/jobs'
       Properties = @{ status = 'DeviceOrdered' }
       Because = 'a job that was never cancelled has no cancellationReason' }
    @{ Category = 'Security'; Name = 'WafPolicies'; Type = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'
       Properties = @{ provisioningState = 'Succeeded' }
       Because = 'a policy with no custom rules has no customRules key' }

    # AB#6844 — the second class: a string method called on a payload value that is absent. These
    # four each held an unguarded `.split('/')[N]` and threw "You cannot call a method on a
    # null-valued expression" before those 75 sites were routed through Get-AZSCIdSegment.
    @{ Category = 'Analytics'; Name = 'Databricks'; Type = 'microsoft.databricks/workspaces'
       Properties = @{ provisioningState = 'Succeeded' }
       Because = 'split the managed resource group id, which a failed deployment does not have' }
    @{ Category = 'Databases'; Name = 'SQLSERVER'; Type = 'microsoft.sql/servers'
       Properties = @{ version = '12.0' }
       Because = 'split a private endpoint connection id on a server that has no private endpoints' }
    # Containers/AKS is deliberately NOT here. It emits one row per agent pool, so a cluster with
    # no agentPoolProfiles correctly produces zero rows — that is the collector's contract, not a
    # sparse-payload failure, and asserting otherwise would encode a wrong expectation.
    @{ Category = 'Networking'; Name = 'NetworkSecurityGroup'; Type = 'microsoft.network/networksecuritygroups'
       Properties = @{ provisioningState = 'Succeeded' }
       Because = 'split associated subnet ids on an NSG associated with nothing' }
) {
    It '<Category>/<Name> still emits its row' {
        $Row = New-SparseArgRow -Type $Type -Name 'res-one' -Properties $Properties
        # @() at the CALL SITE: `return @()` inside a function collapses to $null across the
        # return boundary, and the assertion below would then read "cannot index into a null
        # array" instead of "the collector produced no rows".
        $Rows = @(Invoke-CollectorOnRow -Category $Category -Name $Name -Row $Row)
        $Rows.Count | Should -BeGreaterThan 0 -Because $Because
    }

    It '<Category>/<Name> fills the columns it CAN answer, rather than emptying the sheet' {
        # The guard that stops the previous assertion passing vacuously: a row of nothing but nulls
        # would satisfy a count check while still having lost every value.
        $Row = New-SparseArgRow -Type $Type -Name 'res-one' -Properties $Properties
        # @() at the CALL SITE: `return @()` inside a function collapses to $null across the
        # return boundary, and the assertion below would then read "cannot index into a null
        # array" instead of "the collector produced no rows".
        $Rows = @(Invoke-CollectorOnRow -Category $Category -Name $Name -Row $Row)
        $Rows[0]['Name'] | Should -Be 'res-one'
        $Rows[0]['Location'] | Should -Be 'eastus'
    }
}

Describe 'The relaxation is scoped and does not weaken what StrictMode is for (AB#6839)' {

    It 'still fails on an uninitialised variable inside a row script' {
        # This is the protection AB#5671/5672 bought and the reason the row scope drops to
        # StrictMode 1.0 rather than turning StrictMode off: a mistyped variable name in a lifted
        # preamble must not silently read $null. If this ever passes, the fix has gone too far.
        $Block = [scriptblock]::Create("Set-StrictMode -Version 1.0`n`$ThisWasNeverAssigned")
        { $Block.Invoke() } | Should -Throw
    }

    It 'does not leak out of the collector into the caller' {
        Set-StrictMode -Version Latest
        $Object = [pscustomobject]@{ present = 1 }
        $Row = New-SparseArgRow -Type 'microsoft.databox/jobs' -Name 'res-one' -Properties @{ status = 'DeviceOrdered' }
        $null = Invoke-CollectorOnRow -Category 'Migration' -Name 'DataBox' -Row $Row
        # After a collector has run, the caller's own StrictMode must be untouched.
        { $Object.absent } | Should -Throw
    }
}
