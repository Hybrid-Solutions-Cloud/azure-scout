#Requires -Version 7.0
#Requires -Modules Pester

<#
    Issues #102 and #103 -- the collection a run produces must not depend on HOW the run was started.

    Release 3.18.20 was the first tested in all three modes against one tenant, and the modes
    disagreed. An assessment-only run (`Invoke-AzureScout -Assessment ...`) and a combined run
    (`-InventoryAndAssessment`) collect through two different paths:

      assessment-only   Invoke-ScoutAssessmentCore -> Invoke-Collect -> its OWN Get-ScoutRawInventory pass
      combined          Start-AZSCExtractionOrchestration (the inventory pass: a wider Get-ScoutRawInventory
                        call plus the ARM REST sweep) -> Invoke-ScoutAssessmentCore -FromInventory <that>

    Both end in one collect.json that the same rules score. Every dataset one path reads and the other
    does not is therefore a rule that scores differently depending on the command line -- and where the
    missing dataset reads as an empty array it can score PASS. The live comparison found nine such false
    passes (Advisor) and this file exists so the next one is found by a test, not by a tenant.

    The two paths are driven end to end with the SAME mocked Azure responses (one fixture estate behind a
    table-routing Search-AzGraph stand-in and an ARM REST stand-in) and the two collect.json files are
    flattened and compared key by key. Anything that differs must be on the short list below, each entry
    with the reason the difference is legitimate; an entry that stops differing fails too, so the list
    cannot quietly outlive the reason for it.

    No Azure connection. Everything is written under $TestDrive.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent

    # ---- helpers both paths reach that would otherwise touch Azure ------------------------------
    # Parameter-ignoring stand-ins. Both paths call the same function the same way, so a stub that
    # ignores its arguments cannot manufacture or hide a difference BETWEEN the paths; the sources
    # that decide parity (Resource Graph tables, the ARM REST sweep) are mocked by content below.
    function Get-ScoutDefenderPlanSweep { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return @() }
    function Get-ScoutExternalIdentitiesPolicy { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return [pscustomobject]@{ Collected = $false } }
    function Get-ScoutConditionalAccessPosture { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return [pscustomobject]@{ Collected = $false; Reason = 'stub'; baselineAssessable = $false; namedLocationsCollected = $false; policies = @(); namedLocations = @(); securityDefaultsCoverage = @() } }
    function Get-ScoutArmChildResource { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return @() }
    function Get-ScoutTenantWideResource { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return @() }
    function Get-ScoutOperationalCollectorEnrichment { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return @() }
    function Get-ScoutSubscriptionSecurityPolicySweep { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return @() }
    function ConvertTo-ScoutAvdAzureLocalSessionHost { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return @() }
    function Get-ScoutOutageResource { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return @() }
    function Get-ScoutBillingEvidence { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return [pscustomobject]@{ Resources = @(); SourceOperations = @(); CollectionHealth = @() } }
    function Get-ScoutEntraDiagnosticSettingEvidence { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return [pscustomobject]@{ Resources = @(); SourceOperations = @(); CollectionHealth = @() } }
    function Get-ScoutArmResourceCrossCheck { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; return [pscustomobject]@{ Rows = @(); Operations = @(); Health = @(); Subscriptions = 1; Listed = 0 } }
    function Get-ScoutGovernanceDataset {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        [pscustomobject]@{
            roleAssignments = @(); roleDefinitions = @(); policyAssignments = @(); budgets = @(); resourceLocks = @()
            pimEligibility = @(); pimEligibilityAvailable = $true; pimEligibilityReason = $null
            roleAssignmentSchedules = @(); roleAssignmentSchedulesMeasured = $true; roleAssignmentSchedulesReason = $null
            privilegedAccessMeasured = $true
        }
    }
    function Get-AzSubscription { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; @([pscustomobject]@{ Id = 'aaa'; Name = 'demo-sub'; State = 'Enabled'; TenantId = 'tenant-x' }) }
    function Get-AzContext { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; $null }
    function Invoke-AzRestMethod { param([Parameter(ValueFromRemainingArguments)] $Rest) $null = $Rest; [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' } }
    function Get-AzAccessToken {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        # A throw-away placeholder, built char by char: the analyzer rightly rejects ConvertTo-SecureString
        # -AsPlainText, and nothing here is a credential.
        $placeholder = [System.Security.SecureString]::new()
        foreach ($character in 'placeholder'.ToCharArray()) { $placeholder.AppendChar($character) }
        [pscustomobject]@{ Token = $placeholder }
    }
    function Import-Module {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet so the code under test cannot import the real Az module (and refresh an ambient Az context) during a test.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow must accept whatever the code under test passes.')]
        param([Parameter(ValueFromRemainingArguments)] $Rest)
    }
    # The ARM REST sweep (Get-ScoutApiResources). Only the Advisor score has content; every other
    # list is an empty, successful answer.
    function Invoke-RestMethod {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet to stand in for the ARM REST endpoint.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow declares the real parameters the code under test passes.')]
        param($Uri, $Headers, $Method, $ErrorAction, $TimeoutSec)
        if ($Uri -match 'Microsoft\.Advisor/advisorScore') {
            return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = '/subscriptions/aaa/providers/Microsoft.Advisor/advisorScore/Cost'; name = 'Cost'; type = 'Microsoft.Advisor/advisorScore'; properties = [pscustomobject]@{ lastRefreshedScore = [pscustomobject]@{ score = 55.0 } } }
                    [pscustomobject]@{ id = '/subscriptions/aaa/providers/Microsoft.Advisor/advisorScore/Security'; name = 'Security'; type = 'Microsoft.Advisor/advisorScore'; properties = [pscustomobject]@{ lastRefreshedScore = [pscustomobject]@{ score = 91.0 } } }
                ) }
        }
        return [pscustomobject]@{ value = @() }
    }
    # Entra: the inventory pass reads it, an assessment-only collect has no Entra path.
    function Start-AZSCEntraExtraction {
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        $null = $Rest
        [pscustomobject]@{
            EntraResources = @([pscustomobject]@{ TYPE = 'entra/pimassignments'; properties = [pscustomobject]@{ principalId = 'p1'; roleDefinitionId = 'r1'; roleDefinition = [pscustomobject]@{ displayName = 'Global Administrator' }; directoryScopeId = '/' } })
            QueryOutcomes = @([pscustomobject]@{ Type = 'entra/pimassignments'; Name = 'pimassignments'; Status = 'Success'; Reason = $null })
        }
    }

    # ---- the code under test ---------------------------------------------------------------------
    . (Join-Path $script:Root 'src/Write-AZTIRunLog.ps1')
    . (Join-Path $script:Root 'src/Get-AZTICollectedValue.ps1')
    . (Join-Path $script:Root 'src/collect/ConvertFrom-ScoutInventory.ps1')
    . (Join-Path $script:Root 'src/collect/Get-ScoutResourceGraphDiscoveryTable.ps1')
    . (Join-Path $script:Root 'src/collect/Get-ScoutApiResources.ps1')
    . (Join-Path $script:Root 'src/collect/Get-ScoutRawInventory.ps1')
    . (Join-Path $script:Root 'src/collect/Invoke-Collect.ps1')
    . (Join-Path $script:Root 'src/collect/Start-ScoutGraphExtraction.ps1')
    . (Join-Path $script:Root 'src/Start-AZTIExtractionOrchestration.ps1')
    . (Join-Path $script:Root 'src/assess/Resolve-ScoutAssessmentName.ps1')
    . (Join-Path $script:Root 'src/ingest/Import-AdvisorScores.ps1')
    . (Join-Path $script:Root 'src/ingest/Import-Governance.ps1')
    . (Join-Path $script:Root 'src/ingest/Import-ScoutCostInventory.ps1')
    . (Join-Path $script:Root 'src/ingest/Import-ScoutDevOpsCapability.ps1')
    . (Join-Path $script:Root 'src/collect/Get-ScoutDirectoryRolePosture.ps1')
    . (Join-Path $script:Root 'src/collect/Get-ScoutRbacScheduleDataset.ps1')
    . (Join-Path $script:Root 'src/Invoke-ScoutAssessmentCore.ps1')

    function Get-AZSCManagementGroups {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow must accept whatever the code under test passes.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real function being shadowed.')]
        param($ManagementGroup, $Subscriptions)
        return $Subscriptions
    }

    # ---- one fixture estate, behind Resource Graph -----------------------------------------------
    function New-ParityRow {
        param([string] $Id, [string] $Type, $Properties = $null, [string] $Name = 'x', $Sku = $null)
        [pscustomobject]@{
            id = $Id; name = $Name; type = $Type; location = 'eastus'; resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
            kind = $null; sku = $Sku; plan = $null; identity = $null; zones = $null; extendedLocation = $null; managedBy = $null; tags = $null
            properties = $Properties
        }
    }
    function Get-ParityRowSet {
        param([string] $Table)
        switch ($Table) {
            'resourcecontainers' {
                @(
                    [pscustomobject]@{ id = '/subscriptions/aaa'; name = 'demo-sub'; type = 'microsoft.resources/subscriptions'; subscriptionId = 'aaa'; location = $null; resourceGroup = $null; kind = $null; sku = $null; plan = $null; identity = $null; zones = $null; extendedLocation = $null; managedBy = $null; tenantId = 'ten'; properties = [pscustomobject]@{ state = 'Enabled'; managementGroupAncestorsChain = @([pscustomobject]@{ name = 'mg-platform' }) }; tags = $null }
                    [pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app'; name = 'rg-app'; type = 'microsoft.resources/subscriptions/resourcegroups'; subscriptionId = 'aaa'; location = 'eastus'; resourceGroup = $null; kind = $null; sku = $null; plan = $null; identity = $null; zones = $null; extendedLocation = $null; managedBy = $null; tenantId = 'ten'; properties = [pscustomobject]@{ provisioningState = 'Succeeded' }; tags = $null }
                )
            }
            'resources' {
                @(
                    (New-ParityRow -Id '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.keyvault/vaults/kv1' -Type 'microsoft.keyvault/vaults' -Name 'kv1' -Properties ([pscustomobject]@{ enableSoftDelete = $true; enablePurgeProtection = $false }))
                    (New-ParityRow -Id '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.desktopvirtualization/hostpools/hp1' -Type 'microsoft.desktopvirtualization/hostpools' -Name 'hp1' -Properties ([pscustomobject]@{ hostPoolType = 'Pooled' }))
                )
            }
            # The AVD session host lives ONLY in this table. An inventory run reads it; an assessment-only
            # collect did not, so every AVD session-host rule read Not assessed on an estate that has hosts.
            'desktopvirtualizationresources' {
                @(New-ParityRow -Id '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.desktopvirtualization/hostpools/hp1/sessionhosts/sh1' -Type 'microsoft.desktopvirtualization/hostpools/sessionhosts' -Name 'hp1/sh1' -Properties ([pscustomobject]@{ status = 'Available'; agentVersion = '1.0.0'; updateState = 'Succeeded'; resourceId = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.compute/virtualmachines/vm1' }))
            }
            'managedservicesresources' {
                @(New-ParityRow -Id '/subscriptions/aaa/providers/microsoft.managedservices/registrationdefinitions/d1' -Type 'microsoft.managedservices/registrationdefinitions' -Name 'd1' -Properties ([pscustomobject]@{ provisioningState = 'Succeeded'; authorizations = @([pscustomobject]@{ principalId = 'p' }) }))
            }
            # Recommendations in four categories, Security and Performance included -- the two the
            # per-subscription cmdlet fallback did not return.
            'advisorresources' {
                foreach ($c in @(@('Cost', 'High'), @('HighAvailability', 'Medium'), @('Security', 'High'), @('Performance', 'Medium'))) {
                    New-ParityRow -Id "/subscriptions/aaa/providers/microsoft.advisor/recommendations/$($c[0])" -Type 'microsoft.advisor/recommendations' -Name $c[0] -Properties ([pscustomobject]@{
                            category = $c[0]; impact = $c[1]; impactedField = 'Microsoft.Compute/virtualMachines'; impactedValue = 'vm1'
                            shortDescription = [pscustomobject]@{ problem = "Problem $($c[0])"; solution = "Solution $($c[0])" }
                        })
                }
            }
            # A table only the inventory pass's all-tables discovery sweep reads. Gives the discovery
            # index a legitimate difference to be explained below.
            'policyresources' {
                @(New-ParityRow -Id '/subscriptions/aaa/providers/microsoft.authorization/policyassignments/pa1' -Type 'microsoft.authorization/policyassignments' -Name 'pa1' -Properties ([pscustomobject]@{ displayName = 'pa1' }))
            }
            default { @() }
        }
    }
    function Set-ParitySearchAzGraph {
        $script:ArgQueries = [System.Collections.Generic.List[string]]::new()
        function global:Search-AzGraph {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow declares the real parameters the code under test passes.')]
            param([string] $Query, [int] $First, [int] $Skip, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            $script:ArgQueries.Add($Query)
            $table = ($Query.TrimStart() -split '\s+')[0].ToLowerInvariant()
            # Typed (non-raw) queries answer nothing: this fixture proves what the RAW passes read.
            $isRaw = $Query -match 'project id,name,type,tenantId,kind' -or $table -in @('advisorresources', 'patchassessmentresources', 'patchinstallationresources')
            if (-not $isRaw) { return @() }
            if ($table -eq 'advisorresources' -and $Query -match 'advisorscore') { return @() }
            return @(Get-ParityRowSet -Table $table)
        }
    }

    # ---- the two paths, each producing the parsed collect.json ------------------------------------
    function Read-ParityCollect {
        param([string] $Path)
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    }
    function Invoke-ParityAssessmentOnly {
        param([string] $OutDir, [string[]] $Assessment = @('All'))
        Set-ParitySearchAzGraph
        $path = Invoke-ScoutAssessmentCore -Assessment $Assessment -Scope All -TenantID 'tenant-x' -CollectOnly -OutputPath $OutDir -WarningAction SilentlyContinue 6>$null 3>$null
        Read-ParityCollect -Path $path
    }
    function Invoke-ParityCombined {
        param([string] $OutDir, [string[]] $Assessment = @('All'))
        Set-ParitySearchAzGraph
        # What Invoke-AzureScout does for -InventoryAndAssessment: the inventory pass first (tags are forced
        # on because an assessment will consume the rows), then the assessment reuses it.
        $extraction = Start-AZSCExtractionOrchestration -Subscriptions @([pscustomobject]@{ id = 'aaa'; name = 'demo-sub' }) `
            -SkipPolicy $false -SecurityCenter $false -SkipAdvisory $false -IncludeTags $true -SkipAPIs $false `
            -SkipVMDetails $true -IncludeCosts $false -Automation $false -AzureEnvironment 'AzureCloud' `
            -Scope All -TenantID 'tenant-x' -Category @('All') -PreserveAssessmentDependencies 6>$null 3>$null
        # ...and the inventory processing phase leaves its processed collectors in the run's ReportCache,
        # which the assessment attaches to the collect as `_reportInventory` (and whose Discovery.json
        # replaces the collect's own discovery block).
        $cache = Join-Path $OutDir 'ReportCache'
        $null = New-Item -ItemType Directory -Path $cache -Force
        '{"VirtualMachine":[{"id":"/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.compute/virtualmachines/vm1"}]}' | Set-Content -LiteralPath (Join-Path $cache 'Compute.json')
        '{"Schema":"azure-scout/discovery-completeness/v1","GeneratedAt":"2026-01-01T00:00:00Z","Summary":{"Resources":9,"Relationships":0},"Resources":[],"Relationships":[],"CollectionHealth":[]}' | Set-Content -LiteralPath (Join-Path $cache 'Discovery.json')
        $path = Invoke-ScoutAssessmentCore -Assessment $Assessment -Scope All -TenantID 'tenant-x' -CollectOnly -OutputPath $OutDir -FromInventory $extraction -ReportCachePath $cache -WarningAction SilentlyContinue 6>$null 3>$null
        Read-ParityCollect -Path $path
    }

    # Flatten to path -> comparable scalar. Arrays are reduced to their row COUNT (rows are compared
    # field by field by the existing single-pass equivalence suite; this file asks "was the dataset
    # collected, and how many rows"), booleans and numbers keep their value, strings are compared
    # by value. `_reportInventory` is the processed inventory cache, which only a run with an inventory
    # pass has.
    function ConvertTo-ParityMap {
        param($InputObject, [string] $Prefix = '', [hashtable] $Map)
        if ($null -eq $InputObject) { $Map[$Prefix] = '<null>'; return }
        if ($InputObject -is [string]) { $Map[$Prefix] = "str:$InputObject"; return }
        if ($InputObject -is [bool] -or $InputObject -is [ValueType]) { $Map[$Prefix] = "$($InputObject.GetType().Name):$InputObject"; return }
        if ($InputObject -is [System.Collections.IList]) { $Map[$Prefix] = "rows:$(@($InputObject).Count)"; return }
        foreach ($property in $InputObject.PSObject.Properties) {
            ConvertTo-ParityMap -InputObject $property.Value -Prefix $(if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }) -Map $Map
        }
    }
    function Get-ParityDifference {
        param($Left, $Right)
        $a = @{}; $b = @{}
        ConvertTo-ParityMap -InputObject $Left -Map $a
        ConvertTo-ParityMap -InputObject $Right -Map $b
        foreach ($key in @($a.Keys + $b.Keys | Sort-Object -Unique)) {
            $x = if ($a.ContainsKey($key)) { $a[$key] } else { '<absent>' }
            $y = if ($b.ContainsKey($key)) { $b[$key] } else { '<absent>' }
            if ($x -ne $y) { [pscustomobject]@{ Path = $key; AssessmentOnly = $x; Combined = $y } }
        }
    }

    # ---- the allow-list: every difference between the modes that is legitimate, and why -----------
    # Keep this SHORT. A new entry needs a reason a reviewer can disagree with; "the other mode has it" is
    # not one -- that is the defect this file exists to catch.
    $script:AllowedDifference = @(
        @{ Pattern = '^_meta\.generatedOn$|^discovery\.GeneratedAt$'; Reason = 'Timestamps of two separate runs.' }
        @{ Pattern = '^_reportInventory(\.|$)'; Reason = 'The processed inventory report cache (one entry per inventory collector). Only a run that performed the inventory pass has one; an assessment-only run performs no inventory.' }
        @{ Pattern = '^entraResources$'; Reason = 'Entra ID objects come from the inventory pass (Start-AZSCEntraExtraction). The assessment collect layer has no Entra/Graph inventory path by design (Invoke-ScoutAssessmentCore, -Scope note); the identity datasets it needs it reads directly.' }
        @{ Pattern = '^domains\.identity\.directoryRoles\.'; Reason = 'Directory role assignments are shaped from the Entra rows above and make no Graph call of their own (Get-ScoutDirectoryRolePosture). Without the inventory pass it reports Collected = false with a Reason -- honest, and no rule reads it.' }
        @{ Pattern = '^discovery\.(Resources|Relationships|Summary\.|Status$|StatusReason$|CollectionHealth$)|^_meta\.collectionHealth$'; Reason = 'The universal discovery index is as wide as the pass that fed it. The inventory pass also reads every other Resource Graph table (Get-ScoutResourceGraphDiscoveryTable), the Resource Manager cross-check, support tickets and provider detail, so it lists more resources and carries more collection-health rows; the assessment-only collect says so with discovery.Status = Partial. A combined run replaces the block with the processed inventory cache (which has no Status), hence Status/StatusReason differ too.' }
    )
    function Test-ParityAllowed {
        param([string] $Path)
        foreach ($entry in $script:AllowedDifference) { if ($Path -match $entry.Pattern) { return $true } }
        return $false
    }

    $script:AssessmentOnly = $null
    $script:Combined = $null
}

AfterAll {
    Remove-Item function:Search-AzGraph -ErrorAction SilentlyContinue
}

Describe 'Collect parity -- assessment-only and combined produce the same collect.json' {

    BeforeAll {
        $script:AssessmentOnly = Invoke-ParityAssessmentOnly -OutDir (Join-Path $TestDrive 'assessment-only')
        $script:AssessmentOnlyQueries = @($script:ArgQueries)
        $script:Combined = Invoke-ParityCombined -OutDir (Join-Path $TestDrive 'combined')
        $script:Differences = @(Get-ParityDifference -Left $script:AssessmentOnly -Right $script:Combined)
    }

    It 'collects the fixture estate in both modes (the comparison is not between two empty collects)' {
        @($script:AssessmentOnly.subscriptions).Count | Should -Be 1
        @($script:Combined.subscriptions).Count | Should -Be 1
        @($script:AssessmentOnly.domains.storage.storageAccounts).Count | Should -Be @($script:Combined.domains.storage.storageAccounts).Count
        @($script:AssessmentOnly.domains.security.keyVaults).Count | Should -Be 1
    }

    It 'every dataset and Measured/Available flag is identical except the justified allow-list' {
        $unexplained = @($script:Differences | Where-Object { -not (Test-ParityAllowed -Path $_.Path) })
        ($unexplained | ForEach-Object { '{0}  assessment-only={1}  combined={2}' -f $_.Path, $_.AssessmentOnly, $_.Combined }) -join "`n" |
            Should -BeNullOrEmpty -Because 'a dataset the two modes collect differently scores differently depending on the command line'
    }

    It 'every allow-list entry is still needed (no stale justification)' {
        foreach ($entry in $script:AllowedDifference) {
            @($script:Differences | Where-Object { $_.Path -match $entry.Pattern }).Count |
                Should -BeGreaterThan 0 -Because "the allow-list entry '$($entry.Pattern)' no longer matches a difference; remove it"
        }
    }

    Context 'Advisor (issue #102)' {
        It 'reads the Resource Graph advisorresources table in assessment-only (same source as the combined run)' {
            @($script:AssessmentOnlyQueries | Where-Object { $_ -match '^advisorresources' -and $_ -notmatch 'advisorscore' }).Count | Should -Be 1
        }

        It 'returns every recommendation category, Security and Performance included, with the subscription ID' {
            $rows = @($script:AssessmentOnly.advisor)
            $rows.Count | Should -Be 4
            @($rows.Category | Sort-Object) | Should -Be @('Cost', 'HighAvailability', 'Performance', 'Security')
            @($rows.Subscription | Sort-Object -Unique) | Should -Be @('aaa')
        }

        It 'is complete in both modes' {
            $script:AssessmentOnly.advisorAvailable | Should -BeTrue
            $script:Combined.advisorAvailable | Should -BeTrue
            @($script:Combined.advisor).Count | Should -Be 4
        }

        It 'collects the Advisor score the combined run reads over ARM REST' {
            @($script:AssessmentOnly.management.advisorScores).Count | Should -Be 2
            @($script:Combined.management.advisorScores).Count | Should -Be 2
        }
    }

    Context 'datasets that live in a table the narrower pass used to skip' {
        It 'collects AVD session hosts (desktopvirtualizationresources) in assessment-only' {
            @($script:AssessmentOnly.compute.avdSessionHosts).Count | Should -Be 1
            @($script:Combined.compute.avdSessionHosts).Count | Should -Be 1
        }

        It 'collects Lighthouse delegations (managedservicesresources) in assessment-only' {
            @($script:AssessmentOnly.management.lighthouseDelegations).Count | Should -Be 1
            @($script:Combined.management.lighthouseDelegations).Count | Should -Be 1
        }
    }

    Context 'discovery honesty' {
        It 'an assessment-only discovery index never calls itself Complete' {
            $script:AssessmentOnly.discovery.Status | Should -Be 'Partial'
            $script:AssessmentOnly.discovery.StatusReason | Should -Match 'inventory'
        }
    }
}
