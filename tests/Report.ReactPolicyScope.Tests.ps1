#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    The React report describes the customer's tenant. Microsoft's built-in policy catalog is
    the same in every tenant; a 2026-10-05 field run embedded it ten times over (33,291
    definition rows, 3,699 distinct, none of them custom) and produced a 100 MB report.

    These tests defend the scoping rule: the report keeps every custom definition/initiative,
    everything an assignment or compliance record refers to, and the members of assigned or
    custom initiatives. Unused built-ins are left out with a note saying how many and where
    the full catalog is. The shared Collect object is never modified.

    No Azure connection required.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/report/renderers/Export-React.ps1"

    function New-PolicyDefinitionRow {
        param([string] $Name, [string] $Type, [string] $Scope = '')
        [pscustomobject]@{
            id = "$Scope/providers/Microsoft.Authorization/policyDefinitions/$Name"; name = $Name
            type = 'Microsoft.Authorization/policyDefinitions'
            properties = [pscustomobject]@{ displayName = "Definition $Name"; policyType = $Type }
        }
    }
    function New-ProcessedDefinitionRow {
        param([string] $Name, [string] $Type)
        [pscustomobject]@{ Name = $Name; 'Display Name' = "Definition $Name"; 'Policy Type' = $Type; ID = $null; Subscription = $null }
    }

    $definitions = @(
        New-PolicyDefinitionRow -Name 'assigned-directly' -Type 'BuiltIn'
        New-PolicyDefinitionRow -Name 'member-of-assigned-set' -Type 'BuiltIn'
        New-PolicyDefinitionRow -Name 'seen-in-compliance' -Type 'Static'
        New-PolicyDefinitionRow -Name 'customer-authored' -Type 'Custom' -Scope '/subscriptions/sub-1'
        New-PolicyDefinitionRow -Name 'unused-builtin-1' -Type 'BuiltIn'
        New-PolicyDefinitionRow -Name 'unused-builtin-2' -Type 'Static'
    )
    $sets = @(
        [pscustomobject]@{
            id = '/providers/Microsoft.Authorization/policySetDefinitions/assigned-set'; name = 'assigned-set'
            properties = [pscustomobject]@{ displayName = 'Assigned set'; policyType = 'BuiltIn'; policyDefinitions = @(
                [pscustomobject]@{ policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/member-of-assigned-set' }) }
        }
        [pscustomobject]@{
            id = '/providers/Microsoft.Authorization/policySetDefinitions/unused-set'; name = 'unused-set'
            properties = [pscustomobject]@{ displayName = 'Unused set'; policyType = 'BuiltIn'; policyDefinitions = @(
                [pscustomobject]@{ policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/unused-builtin-1' }) }
        }
    )
    $assignments = @(
        [pscustomobject]@{ name = 'a1'; properties = [pscustomobject]@{ policyDefinitionId = '/providers/Microsoft.Authorization/policySetDefinitions/assigned-set' } }
        [pscustomobject]@{ name = 'a2'; properties = [pscustomobject]@{ policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/Assigned-Directly' } }
    )

    # Processed collector tables as an older run wrote them: one identical copy of every
    # built-in per subscription (three subscriptions here).
    $processedDefinitions = @(1..3 | ForEach-Object {
        New-ProcessedDefinitionRow -Name 'assigned-directly' -Type 'BuiltIn'
        New-ProcessedDefinitionRow -Name 'member-of-assigned-set' -Type 'BuiltIn'
        New-ProcessedDefinitionRow -Name 'seen-in-compliance' -Type 'Static'
        New-ProcessedDefinitionRow -Name 'unused-builtin-1' -Type 'BuiltIn'
        New-ProcessedDefinitionRow -Name 'unused-builtin-2' -Type 'Static'
    }) + @(New-ProcessedDefinitionRow -Name 'customer-authored' -Type 'Custom')

    $script:Collect = [pscustomobject]@{
        _meta = [pscustomobject]@{ scope = 'All' }
        subscriptions = @([pscustomobject]@{ id = 'sub-1'; name = 'Sub one'; state = 'Enabled' })
        governance = [pscustomobject]@{
            policyAssignments = $assignments
            policyDefinitions = $definitions
            policySetDefinitions = $sets
        }
        _reportInventory = [ordered]@{
            'collected.management.PolicyDefinitions' = [ordered]@{
                label = 'Management → Policy Definitions (collected details)'; count = $processedDefinitions.Count
                countUnit = 'evidence rows'; resourceCount = $null; rows = $processedDefinitions; truncated = $null; source = 'Management.json/PolicyDefinitions'
            }
            'collected.management.PolicyComplianceStates' = [ordered]@{
                label = 'Management → Policy Compliance States (collected details)'; count = 1; countUnit = 'evidence rows'; resourceCount = $null
                rows = @([pscustomobject]@{ 'Policy Definition ID' = '/providers/Microsoft.Authorization/policyDefinitions/seen-in-compliance'; 'Policy Set Definition ID' = $null })
                truncated = $null; source = 'Management.json/PolicyComplianceStates'
            }
        }
    }

    $script:OutputPath = Join-Path $TestDrive 'policy-scope'
    $null = Export-React -Findings (Get-Score -Findings @()) -Collect $script:Collect -OutputPath $script:OutputPath
    $html = Get-Content -Raw (Join-Path $script:OutputPath 'report-react.html')
    $start = $html.IndexOf('window.__SCOUT_DATA__ = ') + 'window.__SCOUT_DATA__ = '.Length
    $end = $html.IndexOf('</script>', $start)
    $script:Payload = $html.Substring($start, $end - $start).Trim().TrimEnd(';') | ConvertFrom-Json -Depth 100 -AsHashtable
    $script:Inventory = $script:Payload.inventory
}

Describe 'React report — policy catalog is scoped to what the tenant uses' {
    It 'keeps assigned, initiative-member, compliance-referenced and custom definitions' {
        $names = @($script:Inventory['governance.policyDefinitions'].rows | ForEach-Object { $_.name }) | Sort-Object
        $names | Should -Be @('assigned-directly', 'customer-authored', 'member-of-assigned-set', 'seen-in-compliance')
    }

    It 'leaves unused built-in definitions out and says how many' {
        $entry = $script:Inventory['governance.policyDefinitions']
        $entry.count | Should -Be 4
        $entry.note | Should -Match '2 unused Microsoft built-in policy definitions'
        $entry.note | Should -Match 'raw-inventory\.json'
    }

    It 'keeps only the assigned initiative' {
        $entry = $script:Inventory['governance.policySetDefinitions']
        @($entry.rows | ForEach-Object { $_.name }) | Should -Be @('assigned-set')
        $entry.note | Should -Match '1 unused Microsoft built-in policy initiatives'
    }

    It 'does not treat the members of an unused initiative as in use' {
        @($script:Inventory['governance.policyDefinitions'].rows | ForEach-Object { $_.name }) | Should -Not -Contain 'unused-builtin-1'
    }

    It 'shows each built-in once in the processed table even when the run stored a copy per subscription' {
        $entry = $script:Inventory['collected.management.PolicyDefinitions']
        $names = @($entry.rows | ForEach-Object { $_.Name }) | Sort-Object
        $names | Should -Be @('assigned-directly', 'customer-authored', 'member-of-assigned-set', 'seen-in-compliance')
        $entry.count | Should -Be 4
        $entry.note | Should -Match '12 unused Microsoft built-in policy definitions'
    }

    It 'never drops a custom definition' {
        @($script:Inventory['collected.management.PolicyDefinitions'].rows | Where-Object { $_.'Policy Type' -eq 'Custom' }).Count | Should -Be 1
    }

    It 'leaves the shared Collect object complete for the evidence companions' {
        @($script:Collect.governance.policyDefinitions).Count | Should -Be 6
        @($script:Collect._reportInventory['collected.management.PolicyDefinitions'].rows).Count | Should -Be 16
        $script:Collect._reportInventory['collected.management.PolicyDefinitions'].count | Should -Be 16
    }

    It 'adds no note to a table that was not trimmed' {
        $script:Inventory['governance.policyAssignments'].ContainsKey('note') | Should -BeFalse
    }
}

Describe 'React report — template shows the scoping note' {
    It 'renders an inventory entry note when one is present' {
        $template = Get-Content -Raw (Join-Path $script:Root 'src/report/templates/report-react.html.template')
        $template | Should -Match "if\(v\.note\) unitNote \+= '<div class=""note"">'\+esc\(v\.note\)\+'</div>';"
    }
}
