#Requires -Version 7.0
#Requires -Modules Pester
#Requires -Modules Az.ResourceGraph

<#
    AB#6779 (Tasks AB#6780-AB#6783) -- render the governance data Scout already holds in memory.

    Role assignments, policy assignments, resource locks and budgets were collected on every
    assessment run and written NOWHERE. Four collectors now render them, and the story's binding
    acceptance criterion is that they cost NO additional Azure call. Three things are proved here:

      1. THE CALL BUDGET. `Get-ScoutGovernanceDataset` issues exactly two Resource Graph queries
         plus two ARM REST reads per subscription -- the same four calls `Import-Governance` used
         to make -- and `Import-Governance` then makes ZERO of them when the collect pass has
         already handed the rows over. Counted on both sides, because "no new call" is a claim
         about a number and the only honest way to state it is to measure it.

      2. THE TRANSFORM IS PURE. `ConvertTo-ScoutGovernanceResource` runs with every Azure command
         it could possibly reach stubbed to throw. If it ever grows a call, this fails.

      3. EACH COLLECTOR RENDERS REAL VALUES. One test per collector (an AC of the story), running
         the shipped `.psd1` through the real declarative interpreter over an in-memory envelope,
         asserting the values a reader would actually look for -- "who has Owner" chief among them.

    Search-AzGraph and Invoke-AzRestMethod are mocked throughout. Nothing here touches Azure.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    Import-Module Az.ResourceGraph -ErrorAction Stop
    . (Join-Path $script:RepoRoot 'src/collect/Get-ScoutGovernanceDataset.ps1')
    . (Join-Path $script:RepoRoot 'src/collect/ConvertTo-ScoutGovernanceResource.ps1')
    . (Join-Path $script:RepoRoot 'src/ingest/Import-Governance.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZSCSafeProperty.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZTICollectedValue.ps1')
    . (Join-Path $script:RepoRoot 'src/Get-AZSCIdSegment.ps1')

    # Present so the Get-Command probe in both functions finds it and Pester can mock it, exactly
    # as tests/Assessment.Governance.Tests.ps1 already does.
    if (-not (Get-Command Invoke-AzRestMethod -ErrorAction SilentlyContinue)) {
        function Invoke-AzRestMethod { param([string] $Method, [string] $Path) }
    }

    $script:SubA = '00000000-0000-0000-0000-00000000000a'
    $script:SubB = '00000000-0000-0000-0000-00000000000b'
    $script:OwnerGuid = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    $script:CustomGuid = '11111111-2222-3333-4444-555555555555'

    $script:Subscriptions = @(
        [pscustomobject]@{ id = $script:SubA; name = 'sub-alpha' }
        [pscustomobject]@{ id = $script:SubB; name = 'sub-beta' }
    )

    # ---- the rows Resource Graph / ARM would return -------------------------------------------
    $script:MockAuthorization = @(
        [pscustomobject]@{
            name = 'ra-owner'; type = 'microsoft.authorization/roleassignments'
            id = "/subscriptions/$($script:SubA)/providers/Microsoft.Authorization/roleAssignments/ra-owner"
            properties = [pscustomobject]@{
                scope            = "/subscriptions/$($script:SubA)"
                roleDefinitionId = "/subscriptions/$($script:SubA)/providers/Microsoft.Authorization/roleDefinitions/$($script:OwnerGuid)"
                principalId      = 'aaaaaaaa-0000-0000-0000-000000000001'
                principalType    = 'User'
                createdOn        = '2026-01-04T09:00:00.0000000Z'
            }
        }
        [pscustomobject]@{
            name = 'ra-mg'; type = 'microsoft.authorization/roleassignments'
            id = '/providers/Microsoft.Management/managementGroups/contoso/providers/Microsoft.Authorization/roleAssignments/ra-mg'
            properties = [pscustomobject]@{
                scope            = '/providers/Microsoft.Management/managementGroups/contoso'
                roleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/$($script:CustomGuid)"
                principalId      = 'bbbbbbbb-0000-0000-0000-000000000002'
                principalType    = 'ServicePrincipal'
            }
        }
        [pscustomobject]@{
            # No `scope` at all, and no `condition`/`description`. This is the sparse payload class
            # that has taken worksheets down twice (AB#6839/AB#6844); the scope must still be
            # recovered from the assignment's own id.
            name = 'ra-sparse'; type = 'microsoft.authorization/roleassignments'
            id = "/subscriptions/$($script:SubB)/resourceGroups/rg-one/providers/Microsoft.Authorization/roleAssignments/ra-sparse"
            properties = [pscustomobject]@{
                roleDefinitionId = "/subscriptions/$($script:SubB)/providers/Microsoft.Authorization/roleDefinitions/99999999-9999-9999-9999-999999999999"
            }
        }
        [pscustomobject]@{
            name = $script:OwnerGuid; type = 'microsoft.authorization/roledefinitions'
            id = "/subscriptions/$($script:SubA)/providers/Microsoft.Authorization/roleDefinitions/$($script:OwnerGuid)"
            properties = [pscustomobject]@{ roleName = 'Owner'; type = 'BuiltInRole' }
        }
        [pscustomobject]@{
            name = $script:CustomGuid; type = 'microsoft.authorization/roledefinitions'
            id = "/providers/Microsoft.Authorization/roleDefinitions/$($script:CustomGuid)"
            properties = [pscustomobject]@{ roleName = 'Contoso Platform Operator'; type = 'CustomRole' }
        }
    )

    $script:MockPolicyAssignments = @(
        [pscustomobject]@{
            name = 'require-tags'; type = 'microsoft.authorization/policyassignments'
            id = "/subscriptions/$($script:SubA)/providers/Microsoft.Authorization/policyAssignments/require-tags"
            properties = [pscustomobject]@{
                scope              = "/subscriptions/$($script:SubA)"
                displayName        = 'Require cost-centre tag'
                policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/require-tag'
                enforcementMode    = 'Default'
                notScopes          = @("/subscriptions/$($script:SubA)/resourceGroups/rg-sandbox")
                parameters         = [pscustomobject]@{ tagName = [pscustomobject]@{ value = 'costCentre' } }
            }
        }
        [pscustomobject]@{
            # An INITIATIVE, and a payload with no notScopes/parameters/displayName at all.
            name = 'alz-baseline'; type = 'microsoft.authorization/policyassignments'
            id = '/providers/Microsoft.Management/managementGroups/contoso/providers/Microsoft.Authorization/policyAssignments/alz-baseline'
            properties = [pscustomobject]@{
                scope              = '/providers/Microsoft.Management/managementGroups/contoso'
                policyDefinitionId = '/providers/Microsoft.Authorization/policySetDefinitions/alz-baseline'
                enforcementMode    = 'DoNotEnforce'
            }
        }
    )

    $script:MockBudgets = @(
        @{
            name = 'monthly-cap'
            id = "/subscriptions/$($script:SubA)/providers/Microsoft.Consumption/budgets/monthly-cap"
            properties = @{
                category = 'Cost'; amount = 1000; timeGrain = 'Monthly'
                timePeriod = @{ startDate = '2026-01-01T00:00:00Z'; endDate = '2026-12-31T00:00:00Z' }
                currentSpend = @{ amount = 250; unit = 'USD' }
                forecastSpend = @{ amount = 900; unit = 'USD' }
                notifications = @{ 'Actual_GreaterThan_80_Percent' = @{ enabled = $true } }
            }
        }
        @{
            # amount 0 is legal ARM. A divide here would take the worksheet down.
            name = 'zero-cap'
            id = "/subscriptions/$($script:SubB)/providers/Microsoft.Consumption/budgets/zero-cap"
            properties = @{ category = 'Cost'; amount = 0; currentSpend = @{ amount = 5; unit = 'USD' } }
        }
    )

    $script:MockLocks = @(
        @{
            name = 'no-delete'
            id = "/subscriptions/$($script:SubA)/resourceGroups/rg-prod/providers/Microsoft.Authorization/locks/no-delete"
            properties = @{ level = 'CanNotDelete'; notes = 'Production resource group' }
        }
        @{
            # No `notes`. Absent, not empty.
            name = 'read-only'
            id = "/subscriptions/$($script:SubB)/providers/Microsoft.Authorization/locks/read-only"
            properties = @{ level = 'ReadOnly' }
        }
    )

    function Set-ScoutGovernanceMock {
        Mock Search-AzGraph {
            if ($Query -match 'authorizationresources') { return $script:MockAuthorization }
            if ($Query -match 'policyresources')        { return $script:MockPolicyAssignments }
            return @()
        }
        Mock Invoke-AzRestMethod {
            if ($Path -match 'Microsoft\.Consumption/budgets') {
                $mine = @($script:MockBudgets | Where-Object { $Path -match ([regex]::Escape($_.id.Split('/')[2])) })
                return [pscustomobject]@{ StatusCode = 200; Content = (@{ value = $mine } | ConvertTo-Json -Depth 8) }
            }
            if ($Path -match 'Microsoft\.Authorization/locks') {
                $mine = @($script:MockLocks | Where-Object { $Path -match ([regex]::Escape($_.id.Split('/')[2])) })
                return [pscustomobject]@{ StatusCode = 200; Content = (@{ value = $mine } | ConvertTo-Json -Depth 8) }
            }
            return [pscustomobject]@{ StatusCode = 404; Content = '{}' }
        }
    }

    function Get-ScoutGovernanceTestDataset {
        Set-ScoutGovernanceMock
        return Get-ScoutGovernanceDataset -Subscriptions $script:Subscriptions
    }

    function Get-ScoutGovernanceEnvelope {
        param([string] $Type)
        $dataset = Get-ScoutGovernanceTestDataset
        $envelopes = @(ConvertTo-ScoutGovernanceResource -Governance $dataset -Subscriptions $script:Subscriptions)
        return @($envelopes | Where-Object { $_.type -eq $Type })[0]
    }

    function Invoke-ScoutGovernanceCollector {
        <# Run a shipped definition over an in-memory envelope, through the real interpreter. #>
        param([string] $Category, [string] $Name, [string] $Type)

        $definition = Get-ScoutCollectorDefinition -Path (
            Join-Path $script:RepoRoot "manifests/collectors/$Category/$Name.psd1"
        )
        $context = @{
            ScriptRoot    = $script:RepoRoot
            Subscriptions = $script:Subscriptions
            InTag         = $false
            Resources     = @(Get-ScoutGovernanceEnvelope -Type $Type)
            Retirements   = @()
            Task          = 'Processing'
            File          = $null
            SmaResources  = $null
            TableStyle    = 'Light20'
            Unsupported   = @()
            RunTime       = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()
        }
        return @(Invoke-ScoutDeclarativeCollector -Definition $definition -Context $context)
    }
}

Describe 'AB#6779 -- the call budget' {
    BeforeEach { Set-ScoutGovernanceMock }

    It 'collects the four datasets in exactly two Resource Graph queries' {
        # Two, not three: role ASSIGNMENTS and role DEFINITIONS come back from one
        # authorizationresources query. Splitting them would be a round trip this story is not
        # allowed to spend, and without the definitions the worksheet is a list of GUIDs.
        Get-ScoutGovernanceDataset -Subscriptions $script:Subscriptions | Out-Null
        Should -Invoke Search-AzGraph -Times 2 -Exactly
    }

    It 'reads budgets and locks exactly once per subscription' {
        Get-ScoutGovernanceDataset -Subscriptions $script:Subscriptions | Out-Null
        Should -Invoke Invoke-AzRestMethod -ParameterFilter { $Path -match 'budgets' } -Times 2 -Exactly
        Should -Invoke Invoke-AzRestMethod -ParameterFilter { $Path -match 'locks' }   -Times 2 -Exactly
    }

    It 'scopes both Resource Graph queries to the management group when one is supplied' {
        Get-ScoutGovernanceDataset -Subscriptions $script:Subscriptions -ManagementGroupId 'contoso' | Out-Null
        Should -Invoke Search-AzGraph -ParameterFilter { $ManagementGroup -eq 'contoso' } -Times 2 -Exactly
    }

    It 'makes Import-Governance issue ZERO calls for the four datasets it is handed' {
        # THE acceptance criterion, stated as the number it is. Before AB#6779 Import-Governance
        # made three Resource Graph queries and two REST reads per subscription. Handed the four
        # datasets the collect pass now collects, it makes ONE query -- management groups, the one
        # dataset the raw pass does not supply in this shape -- and no REST call at all.
        #
        # The datasets are built from the mock payloads directly rather than by calling
        # Get-ScoutGovernanceDataset here: Pester counts invocations for the whole test, so
        # collecting them inside this block would attribute the collect pass's own two queries to
        # Import-Governance and make the assertion meaningless.
        $collect = [pscustomobject]@{
            subscriptions = $script:Subscriptions
            governance    = [pscustomobject]@{
                managementGroups  = @()
                policyAssignments = $script:MockPolicyAssignments
                roleAssignments   = @($script:MockAuthorization | Where-Object { $_.type -eq 'microsoft.authorization/roleassignments' })
                budgets           = $script:MockBudgets
                resourceLocks     = $script:MockLocks
            }
        }

        $result = Import-Governance -Collect $collect

        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'authorizationresources' } -Times 0 -Exactly
        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'policyresources' } -Times 0 -Exactly
        Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly

        # ... and the rows survived the handoff, so this is a saving and not a loss.
        @($result.governance.roleAssignments).Count   | Should -Be 3
        @($result.governance.policyAssignments).Count | Should -Be 2
        @($result.governance.budgets).Count           | Should -Be 2
        @($result.governance.resourceLocks).Count     | Should -Be 2
    }

    It 'still collects a dataset the collect pass did NOT supply' {
        # An empty array cannot be told apart from "the raw pass never ran" (-Source TypedQueries,
        # -FromCollect on an old file), so an empty set must never be treated as an answer.
        # Silently reporting zero role assignments is the worst failure a governance run can have.
        $collect = [pscustomobject]@{
            subscriptions = $script:Subscriptions
            governance    = [pscustomobject]@{
                managementGroups = @(); policyAssignments = @(); roleAssignments = @()
                budgets = @(); resourceLocks = @()
            }
        }

        $result = Import-Governance -Collect $collect

        Should -Invoke Search-AzGraph -ParameterFilter { $Query -match 'authorizationresources' } -Times 1 -Exactly
        @($result.governance.roleAssignments).Count | Should -BeGreaterThan 0
        @($result.governance.budgets).Count         | Should -BeGreaterThan 0
    }

    It 'does not double-count budgets when only the locks were handed over' {
        # Skipping the per-subscription loop as a unit would append a SECOND copy of the budgets to
        # a set the collect pass already supplied. The two reads are skipped independently.
        $collect = [pscustomobject]@{
            subscriptions = $script:Subscriptions
            governance    = [pscustomobject]@{
                managementGroups = @(); policyAssignments = @(); roleAssignments = @()
                budgets = $script:MockBudgets; resourceLocks = @()
            }
        }

        $result = Import-Governance -Collect $collect

        @($result.governance.budgets).Count | Should -Be 2
        Should -Invoke Invoke-AzRestMethod -ParameterFilter { $Path -match 'budgets' } -Times 0 -Exactly
        Should -Invoke Invoke-AzRestMethod -ParameterFilter { $Path -match 'locks' } -Times 2 -Exactly
    }
}

Describe 'AB#6779 -- ConvertTo-ScoutGovernanceResource is a pure transform' {
    It 'produces every envelope without touching Azure' {
        # The claim "no additional Azure API call is made to produce them" is about THIS function.
        # Every command it could reach is stubbed to throw, so a future call cannot pass silently.
        Mock Search-AzGraph { throw 'ConvertTo-ScoutGovernanceResource must not query Resource Graph' }
        Mock Invoke-AzRestMethod { throw 'ConvertTo-ScoutGovernanceResource must not call ARM' }

        $dataset = [pscustomobject]@{
            roleAssignments = $script:MockAuthorization
            roleDefinitions = @()
            policyAssignments = $script:MockPolicyAssignments
            budgets = @(); resourceLocks = @()
        }

        $envelopes = @(ConvertTo-ScoutGovernanceResource -Governance $dataset -Subscriptions $script:Subscriptions)
        @($envelopes).Count | Should -Be 4
        Should -Invoke Search-AzGraph -Times 0 -Exactly
        Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly
    }

    It 'returns all four envelopes even when every dataset is empty' {
        # Same contract as Get-ScoutTenantWideResource: an estate with no budgets renders an empty
        # Budgets worksheet, not a missing one.
        $envelopes = @(ConvertTo-ScoutGovernanceResource -Governance ([pscustomobject]@{}) -Subscriptions @())
        @($envelopes).Count | Should -Be 4
        @($envelopes.type) | Should -Be @(
            'AZSC/Governance/RoleAssignment'
            'AZSC/Governance/PolicyAssignment'
            'AZSC/Governance/ResourceLock'
            'AZSC/Governance/Budget'
        )
        foreach ($envelope in $envelopes) { @($envelope.properties).Count | Should -Be 0 }
    }

    It 'survives a null Governance argument' {
        { ConvertTo-ScoutGovernanceResource -Governance $null } | Should -Not -Throw
    }
}

Describe 'AB#6780 -- Identity/RoleAssignments answers "who has Owner"' {
    It 'names the built-in role rather than printing its GUID' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Identity' -Name 'RoleAssignments' -Type 'AZSC/Governance/RoleAssignment'
        $owner = @($rows | Where-Object { $_['Role Name'] -eq 'Owner' })

        $owner.Count | Should -Be 1
        $owner[0]['Principal ID']   | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        $owner[0]['Principal Type'] | Should -Be 'User'
        $owner[0]['Subscription']   | Should -Be 'sub-alpha'
        $owner[0]['Scope Type']     | Should -Be 'Subscription'
        $owner[0]['Role Type']      | Should -Be 'BuiltInRole'
    }

    It 'names a custom role and classifies its management-group scope' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Identity' -Name 'RoleAssignments' -Type 'AZSC/Governance/RoleAssignment'
        $custom = @($rows | Where-Object { $_['Role Name'] -eq 'Contoso Platform Operator' })

        $custom.Count | Should -Be 1
        $custom[0]['Role Type']  | Should -Be 'CustomRole'
        $custom[0]['Scope Type'] | Should -Be 'Management Group'
        # A management group belongs to no subscription. Blank, not a wrong one.
        $custom[0]['Subscription'] | Should -BeNullOrEmpty
    }

    It 'recovers the scope of an assignment whose payload omits it, and says so when a role cannot be named' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Identity' -Name 'RoleAssignments' -Type 'AZSC/Governance/RoleAssignment'
        $sparse = @($rows | Where-Object { $_['Assignment Name'] -eq 'ra-sparse' })

        $sparse.Count | Should -Be 1
        $sparse[0]['Scope Type']   | Should -Be 'Resource Group'
        $sparse[0]['Subscription'] | Should -Be 'sub-beta'
        # An unresolved role reads as the GUID it is. A blank cell would look like an assignment
        # to nothing, which is a different and much worse claim.
        $sparse[0]['Role Name'] | Should -Be 'Unresolved (99999999-9999-9999-9999-999999999999)'
    }

    It 'renders one row per assignment and no rows for the role definitions' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Identity' -Name 'RoleAssignments' -Type 'AZSC/Governance/RoleAssignment'
        $rows.Count | Should -Be 3
    }
}

Describe 'AB#6782 -- Management/PolicyAssignments says which policies apply, and where' {
    It 'renders the assignment with its display name, scope and exclusions' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Management' -Name 'PolicyAssignments' -Type 'AZSC/Governance/PolicyAssignment'
        $tagPolicy = @($rows | Where-Object { $_['Assignment Name'] -eq 'require-tags' })

        $tagPolicy.Count | Should -Be 1
        $tagPolicy[0]['Display Name']     | Should -Be 'Require cost-centre tag'
        $tagPolicy[0]['Subscription']     | Should -Be 'sub-alpha'
        $tagPolicy[0]['Scope Type']       | Should -Be 'Subscription'
        $tagPolicy[0]['Enforcement Mode'] | Should -Be 'Default'
        $tagPolicy[0]['Excluded Scopes']  | Should -Be 1
        $tagPolicy[0]['Parameters']       | Should -Be 1
        $tagPolicy[0]['Assigned']         | Should -Be 'Policy'
    }

    It 'tells an initiative apart from a single policy' {
        # The first question anyone asks of this sheet, and the only place the answer lives is the
        # provider segment of the definition id.
        $rows = Invoke-ScoutGovernanceCollector -Category 'Management' -Name 'PolicyAssignments' -Type 'AZSC/Governance/PolicyAssignment'
        $initiative = @($rows | Where-Object { $_['Assignment Name'] -eq 'alz-baseline' })

        $initiative.Count | Should -Be 1
        $initiative[0]['Assigned']         | Should -Be 'Initiative'
        $initiative[0]['Definition']       | Should -Be 'alz-baseline'
        $initiative[0]['Enforcement Mode'] | Should -Be 'DoNotEnforce'
        $initiative[0]['Scope Type']       | Should -Be 'Management Group'
        # Absent notScopes/parameters are zero, not a crash and not a blank.
        $initiative[0]['Excluded Scopes'] | Should -Be 0
        $initiative[0]['Parameters']      | Should -Be 0
    }
}

Describe 'AB#6781 -- Management/ResourceLocks says what is protected from deletion' {
    It 'reports the scope the lock protects, not the lock resource id' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Management' -Name 'ResourceLocks' -Type 'AZSC/Governance/ResourceLock'
        $rgLock = @($rows | Where-Object { $_['Lock Name'] -eq 'no-delete' })

        $rgLock.Count | Should -Be 1
        $rgLock[0]['Protects']     | Should -Be "/subscriptions/$($script:SubA)/resourceGroups/rg-prod"
        $rgLock[0]['Scope Type']   | Should -Be 'Resource Group'
        $rgLock[0]['Lock Level']   | Should -Be 'CanNotDelete'
        $rgLock[0]['Notes']        | Should -Be 'Production resource group'
        $rgLock[0]['Subscription'] | Should -Be 'sub-alpha'
    }

    It 'renders a lock whose payload carries no notes' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Management' -Name 'ResourceLocks' -Type 'AZSC/Governance/ResourceLock'
        $subLock = @($rows | Where-Object { $_['Lock Name'] -eq 'read-only' })

        $subLock.Count | Should -Be 1
        $subLock[0]['Lock Level'] | Should -Be 'ReadOnly'
        $subLock[0]['Scope Type'] | Should -Be 'Subscription'
        $subLock[0]['Notes']      | Should -BeNullOrEmpty
    }
}

Describe 'AB#6783 -- Management/Budgets shows the cost guardrails in place' {
    It 'renders the budget with its spend, forecast and percentage used' {
        $rows = Invoke-ScoutGovernanceCollector -Category 'Management' -Name 'Budgets' -Type 'AZSC/Governance/Budget'
        $cap = @($rows | Where-Object { $_['Name'] -eq 'monthly-cap' })

        $cap.Count | Should -Be 1
        $cap[0]['Subscription']      | Should -Be 'sub-alpha'
        $cap[0]['Amount']            | Should -Be 1000
        $cap[0]['Current Spend']     | Should -Be 250
        $cap[0]['Forecast Spend']    | Should -Be 900
        $cap[0]['Budget Used %']     | Should -Be 25
        $cap[0]['Currency']          | Should -Be 'USD'
        $cap[0]['Time Grain']        | Should -Be 'Monthly'
        $cap[0]['Alerts Configured'] | Should -Be 1
    }

    It 'renders a zero-amount budget without dividing by it' {
        # amount 0 is legal ARM. Dividing there would cost the whole worksheet, not one cell.
        $rows = Invoke-ScoutGovernanceCollector -Category 'Management' -Name 'Budgets' -Type 'AZSC/Governance/Budget'
        $zero = @($rows | Where-Object { $_['Name'] -eq 'zero-cap' })

        $zero.Count | Should -Be 1
        $zero[0]['Budget Used %']     | Should -BeNullOrEmpty
        $zero[0]['Subscription']      | Should -Be 'sub-beta'
        $zero[0]['Alerts Configured'] | Should -Be 0
    }
}
