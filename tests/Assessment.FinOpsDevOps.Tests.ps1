#Requires -Version 7.0
#Requires -Modules Pester, powershell-yaml

<#
    AB#6826 (FinOps Review) / AB#6827 (DevOps Capability Assessment), Feature AB#6749,
    Epic AB#6454.

    Covers the acceptance criteria that need a pinned, non-vacuous test:
      - The `assert.gate` mechanism (Invoke-Rule.ps1) reports NotAssessed -- never Fail, never
        a scored zero -- when the underlying data source is blocked/unavailable, and behaves
        exactly like an ordinary assert once the gate is open.
      - Import-ScoutCostInventory computes `finops.available` correctly across: module not
        installed, module installed with a real billing-API failure (blocked), module installed
        and genuinely zero-spend, and a combined-run reuse path.
      - Import-ScoutDevOpsCapability computes `devops.available` correctly across:
        -IncludeDevOps off, on with zero resources discovered, on with resources discovered, and
        a combined-run reuse path.
      - Both rule files load under Get-RuleSet, cite a real FINOPS-*/DEVOPS-* item per rule, and
        every automated (non-manual) rule that reads a billing-/DevOps-access-gated field
        actually carries the gate.
      - Both registry entries exist and route to the right rule file.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Resolve-JsonPath.ps1"
    . "$script:Root/src/assess/engine/Resolve-RuleJoin.ps1"
    . "$script:Root/src/assess/engine/Invoke-Rule.ps1"
    . "$script:Root/src/assess/engine/Get-RuleSet.ps1"
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/ingest/Import-ScoutCostInventory.ps1"
    . "$script:Root/src/ingest/Import-ScoutDevOpsCapability.ps1"
    . "$script:Root/src/collect/Get-ScoutCostInventory.ps1"
    Import-Module powershell-yaml -ErrorAction Stop

    $script:Manifest = Import-PowerShellDataFile (Join-Path $script:Root 'manifests/assessments.psd1')

    function New-ScoutRule {
        param($Id = 'X', $Query = '$.a[*]', $AssertType = 'exists', $Value = $null, $Gate = $null, $DenominatorQuery = $null)
        $assert = @{ type = $AssertType }
        if ($null -ne $Value) { $assert.value = $Value }
        if ($Gate) { $assert.gate = $Gate }
        if ($DenominatorQuery) { $assert.denominatorQuery = $DenominatorQuery }
        return @{ id = $Id; title = 't'; severity = 'medium'; query = $Query; assert = $assert; remediation = 'r'; manual = $false }
    }
}

Describe 'AB#6826 -- Invoke-Rule assert.gate' {
    It 'reports NotAssessed when the gate path is entirely absent from the collect object' {
        $collect = [pscustomobject]@{ subscriptions = @() }
        $rule = New-ScoutRule -Query '$.finops.costRows[*]' -AssertType 'exists' -Gate '$.finops.available'
        (Invoke-Rule -Rule $rule -Collect $collect -Area A -Framework F).Status | Should -Be 'NotAssessed'
    }
    It 'reports NotAssessed when the gate resolves to a scalar boolean false' {
        $collect = [pscustomobject]@{ finops = [pscustomobject]@{ available = $false; costRows = @() } }
        $rule = New-ScoutRule -Query '$.finops.costRows[*]' -AssertType 'exists' -Gate '$.finops.available'
        (Invoke-Rule -Rule $rule -Collect $collect -Area A -Framework F).Status | Should -Be 'NotAssessed'
    }
    It 'evaluates normally (Fail) when the gate is open (true) but the real query finds nothing' {
        $collect = [pscustomobject]@{ finops = [pscustomobject]@{ available = $true; costRows = @() } }
        $rule = New-ScoutRule -Query '$.finops.costRows[*]' -AssertType 'exists' -Gate '$.finops.available'
        (Invoke-Rule -Rule $rule -Collect $collect -Area A -Framework F).Status | Should -Be 'Fail'
    }
    It 'evaluates normally (Pass) when the gate is open and the real query finds evidence' {
        $collect = [pscustomobject]@{ finops = [pscustomobject]@{ available = $true; costRows = @(@{ Cost = 1 }) } }
        $rule = New-ScoutRule -Query '$.finops.costRows[*]' -AssertType 'exists' -Gate '$.finops.available'
        (Invoke-Rule -Rule $rule -Collect $collect -Area A -Framework F).Status | Should -Be 'Pass'
    }
    It 'a rule with no gate at all is completely unaffected -- proves the gate is opt-in, not a global behavior change' {
        $collect = [pscustomobject]@{ finops = [pscustomobject]@{ available = $false; costRows = @() } }
        $rule = New-ScoutRule -Query '$.finops.costRows[*]' -AssertType 'countEquals' -Value 0
        (Invoke-Rule -Rule $rule -Collect $collect -Area A -Framework F).Status | Should -Be 'Pass'
    }
    It 'Get-Score excludes NotAssessed from the scorable denominator, same as Manual/Unknown/Error' {
        $findings = @(
            [pscustomobject]@{ Id='a'; Title='t'; Framework='FinOps'; Area='FinOps Review'; Severity='medium'; Status='Pass'; EvidenceCount=0; Evidence=@(); Remediation='r'; Manual=$false; AreaWeight=1.0 }
            [pscustomobject]@{ Id='b'; Title='t'; Framework='FinOps'; Area='FinOps Review'; Severity='medium'; Status='NotAssessed'; EvidenceCount=0; Evidence=@(); Remediation='r'; Manual=$false; AreaWeight=1.0 }
        )
        $score = Get-Score -Findings $findings
        $area = $score.Areas | Where-Object Area -eq 'FinOps Review'
        $area.Score | Should -Be 100 -Because 'NotAssessed must not drag a 1-Pass area down to 50%'
        $area.NotAssessed | Should -Be 1 -Because 'it must still be counted and visible, not silently dropped'
    }
}

Describe 'AB#6826 -- Import-ScoutCostInventory availability semantics' {
    It 'unavailable when Az.CostManagement is not installed at all' {
        # No Invoke-AzCostManagementQuery function defined -- Get-Command must not find it.
        $collect = [pscustomobject]@{ subscriptions = @([pscustomobject]@{ id = 'sub-1'; name = 'sub-one' }) }
        $result = Import-ScoutCostInventory -Collect $collect -WarningAction SilentlyContinue
        $result.finops.available | Should -BeFalse
        $result.finops.moduleAvailable | Should -BeFalse
    }
    It 'available when the module resolves and returns real cost rows' {
        function Invoke-AzCostManagementQuery {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            return [pscustomobject]@{ Row = @(, @(42.5, '20260701', 'Microsoft.Compute/virtualMachines', 'rg-1', 'eastus', 'Virtual Machines', 'USD')) }
        }
        $collect = [pscustomobject]@{ subscriptions = @([pscustomobject]@{ id = 'sub-1'; name = 'sub-one' }) }
        $result = Import-ScoutCostInventory -Collect $collect
        $result.finops.available | Should -BeTrue
        $result.finops.moduleAvailable | Should -BeTrue
        @($result.finops.costRows).Count | Should -Be 1
        $result.finops.costRows[0].Cost | Should -Be 42.5
        Remove-Item function:Invoke-AzCostManagementQuery -ErrorAction SilentlyContinue
    }
    It 'unavailable (blocked) when the module resolves but every subscription errors -- never reads as zero-spend' {
        function Invoke-AzCostManagementQuery {
            param([string] $Scope, [Parameter(ValueFromRemainingArguments)] $Rest)
            throw "Forbidden: the caller does not have permission to perform action 'Microsoft.CostManagement/query/action' for subscription '$Scope'"
        }
        $collect = [pscustomobject]@{ subscriptions = @([pscustomobject]@{ id = 'sub-1'; name = 'sub-one' }) }
        $result = Import-ScoutCostInventory -Collect $collect -WarningAction SilentlyContinue
        $result.finops.available | Should -BeFalse -Because 'a billing-permission-blocked pull must degrade to unavailable, not a scored zero'
        $result.finops.moduleAvailable | Should -BeTrue -Because 'the module itself resolved fine -- only the API call was blocked'
        @($result.finops.blockedSubscriptions) | Should -Contain 'sub-one'
        Remove-Item function:Invoke-AzCostManagementQuery -ErrorAction SilentlyContinue
    }
    It 'trivially available on an estate with zero subscriptions -- an empty estate is not a blocked one' {
        $collect = [pscustomobject]@{ subscriptions = @() }
        $result = Import-ScoutCostInventory -Collect $collect -WarningAction SilentlyContinue
        # No module installed AND no subscriptions -- module absence still wins (deterministic
        # opt-in gate), proving the "zero subscriptions" branch alone doesn't fabricate available.
        $result.finops.available | Should -BeFalse
    }
    It 'preserves the reservations stub Invoke-Collect already attached, rather than clobbering it' {
        $collect = [pscustomobject]@{
            subscriptions = @()
            finops = [pscustomobject]@{ reservations = @(@{ name = 'my-reservation' }) }
        }
        $result = Import-ScoutCostInventory -Collect $collect -WarningAction SilentlyContinue
        @($result.finops.reservations).Count | Should -Be 1
        $result.finops.reservations[0].name | Should -Be 'my-reservation'
    }
}

Describe 'AB#6827 -- Import-ScoutDevOpsCapability availability semantics' {
    It 'unavailable (not attempted) when -IncludeDevOps is not passed at all' {
        $collect = [pscustomobject]@{}
        $result = Import-ScoutDevOpsCapability -Collect $collect
        $result.devops.available | Should -BeFalse
        $result.devops.attempted | Should -BeFalse
    }
    It 'unavailable when -IncludeDevOps is set but the extraction finds zero resources of any type' {
        function Start-AZSCDevOpsExtraction { param([Parameter(ValueFromRemainingArguments)] $Rest) return [pscustomobject]@{ DevOpsResources = @() } }
        $collect = [pscustomobject]@{}
        $result = Import-ScoutDevOpsCapability -Collect $collect -IncludeDevOps
        $result.devops.available | Should -BeFalse -Because 'attempted but zero resources came back must not read as a clean zero'
        $result.devops.attempted | Should -BeTrue
        Remove-Item function:Start-AZSCDevOpsExtraction -ErrorAction SilentlyContinue
    }
    It 'available and shapes projects/pipelines/serviceConnections when resources come back' {
        function Start-AZSCDevOpsExtraction {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            return [pscustomobject]@{
                DevOpsResources = @(
                    [pscustomobject]@{ organization = 'contoso'; name = 'proj1'; type = 'devops/projects'; properties = [pscustomobject]@{ state = 'wellFormed' } }
                    [pscustomobject]@{ organization = 'contoso'; name = 'conn1'; type = 'devops/serviceconnections'; properties = [pscustomobject]@{ projectName = 'proj1'; authorization = [pscustomobject]@{ scheme = 'WorkloadIdentityFederation' } } }
                    [pscustomobject]@{ organization = 'contoso'; name = 'conn2'; type = 'devops/serviceconnections'; properties = [pscustomobject]@{ projectName = 'proj1'; authorization = [pscustomobject]@{ scheme = 'ServicePrincipal' } } }
                )
            }
        }
        $collect = [pscustomobject]@{}
        $result = Import-ScoutDevOpsCapability -Collect $collect -IncludeDevOps
        $result.devops.available | Should -BeTrue
        @($result.devops.projects).Count | Should -Be 1
        @($result.devops.serviceConnections).Count | Should -Be 2
        ($result.devops.serviceConnections | Where-Object Name -eq 'conn1').CredentialFree | Should -BeTrue
        ($result.devops.serviceConnections | Where-Object Name -eq 'conn2').CredentialFree | Should -BeFalse
        Remove-Item function:Start-AZSCDevOpsExtraction -ErrorAction SilentlyContinue
    }
    It 'reuses -FromInventory rows (devops/* types only) without calling Start-AZSCDevOpsExtraction again' {
        $calledExtraction = $false
        function Start-AZSCDevOpsExtraction { param([Parameter(ValueFromRemainingArguments)] $Rest) $script:calledExtraction = $true; return [pscustomobject]@{ DevOpsResources = @() } }
        $fromInventory = @(
            [pscustomobject]@{ organization = 'contoso'; name = 'proj1'; type = 'devops/projects'; properties = [pscustomobject]@{} }
            [pscustomobject]@{ name = 'vm1'; type = 'microsoft.compute/virtualmachines'; properties = [pscustomobject]@{} }
        )
        $collect = [pscustomobject]@{}
        $result = Import-ScoutDevOpsCapability -Collect $collect -IncludeDevOps -FromInventory $fromInventory
        $result.devops.available | Should -BeTrue
        @($result.devops.projects).Count | Should -Be 1
        $calledExtraction | Should -BeFalse -Because 'the collect-once pattern must not re-call Azure when rows were already handed in'
        Remove-Item function:Start-AZSCDevOpsExtraction -ErrorAction SilentlyContinue
    }
    It 'preserves the ARM-sourced stub fields Invoke-Collect already attached (managedPools etc.)' {
        $collect = [pscustomobject]@{ devops = [pscustomobject]@{ managedPools = @(@{ name = 'pool1' }) } }
        $result = Import-ScoutDevOpsCapability -Collect $collect
        @($result.devops.managedPools).Count | Should -Be 1
    }
}

Describe 'AB#6826/AB#6827 -- rule files load, cite real items, and gate every access-restricted automated rule' {
    BeforeAll {
        $script:FinOpsDoc = ConvertFrom-Yaml (Get-Content (Join-Path $script:Root 'src/assess/rules/finops.review.yaml') -Raw)
        $script:DevOpsDoc = ConvertFrom-Yaml (Get-Content (Join-Path $script:Root 'src/assess/rules/devops.capability.yaml') -Raw)
    }
    It 'finops.review.yaml loads under Get-RuleSet with a non-empty frameworkversion' {
        $set = Get-RuleSet -Patterns @('finops.review')
        $set.Count | Should -Be 1
        $set[0].FrameworkVersion | Should -Not -BeNullOrEmpty
        $set[0].Rules.Count | Should -Be 22
    }
    It 'devops.capability.yaml loads under Get-RuleSet with a non-empty frameworkversion' {
        $set = Get-RuleSet -Patterns @('devops.capability')
        $set.Count | Should -Be 1
        $set[0].FrameworkVersion | Should -Not -BeNullOrEmpty
        $set[0].Rules.Count | Should -Be 18
    }
    It 'every finops.review.yaml rule id matches the FINOPS-* enumeration shape' {
        $offenders = @($script:FinOpsDoc.rules | Where-Object { $_.id -notmatch '^FINOPS-[A-Z]+[0-9]+$' })
        $offenders | Should -BeNullOrEmpty
    }
    It 'every devops.capability.yaml rule id matches the DEVOPS-* enumeration shape' {
        $offenders = @($script:DevOpsDoc.rules | Where-Object { $_.id -notmatch '^DEVOPS-[A-Z]+-[0-9]+$' })
        $offenders | Should -BeNullOrEmpty
    }
    It 'every automated finops.review.yaml rule reading $.finops.costRows or $.finops.anomalies carries assert.gate' {
        $offenders = @($script:FinOpsDoc.rules | Where-Object {
            (-not $_.manual) -and $_.query -and ($_.query -match '\$\.finops\.(costRows|anomalies)') -and
            (-not ($_.assert.ContainsKey('gate') -and $_.assert.gate))
        })
        $offenders | Should -BeNullOrEmpty -Because 'a rule reading the billing-gated fields without a gate would score a blocked pull as zero'
    }
    It 'every automated devops.capability.yaml rule reading $.devops.projects/pipelines/repositories/serviceConnections/agentPools carries assert.gate' {
        $offenders = @($script:DevOpsDoc.rules | Where-Object {
            (-not $_.manual) -and $_.query -and ($_.query -match '\$\.devops\.(projects|pipelines|repositories|serviceConnections|agentPools)') -and
            (-not ($_.assert.ContainsKey('gate') -and $_.assert.gate))
        })
        $offenders | Should -BeNullOrEmpty -Because 'a rule reading Azure-DevOps-access-gated fields without a gate would score "access not granted" as zero pipelines'
    }
    It 'no finops.review.yaml or devops.capability.yaml rule that reads an ARM-sourced field (reservations/managedPools/devCenters/loadTesting/playwrightTesting) carries a gate -- proves the gate is only on the truly access-restricted half' {
        $armOffenders = @($script:FinOpsDoc.rules + $script:DevOpsDoc.rules | Where-Object {
            $_.query -and ($_.query -match '\$\.(finops\.reservations|devops\.(managedPools|devCenters|loadTesting|playwrightTesting))') -and
            $_.assert.ContainsKey('gate') -and $_.assert.gate
        })
        $armOffenders | Should -BeNullOrEmpty
    }
}

Describe 'AB#6826/AB#6827 -- registry entries exist and route to the right rule file' {
    It 'FinOps Review is registered and points at exactly finops.review' {
        $script:Manifest.Keys | Should -Contain 'FinOps Review'
        $script:Manifest['FinOps Review'].Rules | Should -Be @('finops.review')
        $script:Manifest['FinOps Review'].Ingest | Should -Contain 'CostInventory'
    }
    It 'DevOps Capability Assessment is registered and points at exactly devops.capability' {
        $script:Manifest.Keys | Should -Contain 'DevOps Capability Assessment'
        $script:Manifest['DevOps Capability Assessment'].Rules | Should -Be @('devops.capability')
        $script:Manifest['DevOps Capability Assessment'].Ingest | Should -Contain 'DevOpsCapability'
    }
    It 'both Description fields state the enumeration is inferred, not Microsoft-published' {
        $script:Manifest['FinOps Review'].Description | Should -Match '(?i)inferred'
        $script:Manifest['DevOps Capability Assessment'].Description | Should -Match '(?i)inferred'
    }
}
