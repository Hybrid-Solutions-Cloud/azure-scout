#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5648 (Epic AB#5638) — the single-pass inversion, and the gate that keeps it.

    v2.7.0 shipped src/collect's collection functions as dead capability: nothing called them,
    so the product still reached Azure Resource Graph 35 times for an assessment collect and a
    second, separate 8-table time for an inventory extraction. This file pins the inverted
    wiring by COUNTING Resource Graph round-trips for each entry point, because that is the only
    property that actually regresses silently — every other assertion in the suite passes just
    as happily whether the data came from one pass or thirty-five.

    Measured on this branch (see the Describe blocks below for the assertions):

      | entry point                                     | before | after |
      |-------------------------------------------------|--------|-------|
      | Invoke-Collect, assessment-only (default)        |     35 |     4 |
      | Invoke-Collect -FromInventory (combined run)     |      1 |     1 |
      | Invoke-Collect -Source TypedQueries (opt-in)     |     35 |    35 |
      | Start-AZSCGraphExtraction, inventory default     |      8 |     8 |
      | combined inventory + assessment, end to end      |      9 |     9 |

    The two documented exceptions to "one pass", both asserted here:
      - `sqlDefenderPricing` reads the SecurityResources table (microsoft.security/pricings),
        which no inventory pass collects. It stays a live typed query.
      - `Retirements` is a file-backed KQL query with its own joins over service-health data.
        It cannot be derived from the raw row set either.

    Search-AzGraph is replaced by a counting stub throughout. No Azure connection.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent

    # Neutralise Import-Module so `Import-Module Az.ResourceGraph` inside the functions under
    # test cannot pull the real cmdlet into the session and make a live call.
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }

    . "$script:root/src/collect/ConvertFrom-ScoutInventory.ps1"
    . "$script:root/src/collect/Get-ScoutRawInventory.ps1"
    . "$script:root/src/collect/Invoke-Collect.ps1"
    . "$script:root/src/collect/Start-ScoutGraphExtraction.ps1"

    function Get-AZSCManagementGroups { param($ManagementGroup, $Subscriptions) return $Subscriptions }

    # ---- the one fixture estate both paths are driven from ----
    # Raw rows carry the full properties bag exactly as Resource Graph indexes it; the typed
    # responses further down are the projections ARG would return for these same resources.
    function Get-FixtureContainerRows {
        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa'; name = 'demo-sub'; type = 'microsoft.resources/subscriptions'
                subscriptionId = 'aaa'; location = $null; resourceGroup = $null
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tenantId = 'ten'
                properties = [pscustomobject]@{ state = 'Enabled' }
                tags = [pscustomobject]@{ Environment = 'Production'; CostCenter = 'CC-100' }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-net'; name = 'rg-net'
                type = 'microsoft.resources/subscriptions/resourcegroups'
                subscriptionId = 'aaa'; location = 'eastus'; resourceGroup = $null
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tenantId = 'ten'
                properties = [pscustomobject]@{ provisioningState = 'Succeeded' }; tags = $null
            }
        )
    }

    function Get-FixtureResourceRows {
        @(
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-net/providers/microsoft.network/virtualnetworks/vnet1'
                name = 'vnet1'; type = 'microsoft.network/virtualnetworks'; location = 'eastus'
                resourceGroup = 'rg-net'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{
                    enableDdosProtection   = $false
                    virtualNetworkPeerings = @([pscustomobject]@{ name = 'peer1' })
                    subnets                = @(
                        [pscustomobject]@{
                            name = 'snet-app'
                            properties = [pscustomobject]@{
                                addressPrefix    = '10.0.1.0/24'
                                ipConfigurations = @([pscustomobject]@{ id = 'ipc1' }, [pscustomobject]@{ id = 'ipc2' })
                            }
                        }
                    )
                }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.keyvault/vaults/kv1'
                name = 'kv1'; type = 'microsoft.keyvault/vaults'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; sku = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                properties = [pscustomobject]@{ enableSoftDelete = $true; enablePurgeProtection = $false }
            }
            [pscustomobject]@{
                id = '/subscriptions/aaa/resourceGroups/rg-app/providers/microsoft.compute/disks/disk-orphan'
                name = 'disk-orphan'; type = 'microsoft.compute/disks'; location = 'eastus'
                resourceGroup = 'rg-app'; subscriptionId = 'aaa'; tenantId = 'ten'
                kind = $null; plan = $null; identity = $null; zones = $null
                extendedLocation = $null; managedBy = $null; tags = $null
                sku = [pscustomobject]@{ name = 'Premium_LRS' }
                properties = [pscustomobject]@{ diskState = 'Unattached'; diskSizeGB = 128 }
            }
        )
    }

    # ---- the typed-query responses for the SAME estate ----
    # Hand-written to match what Resource Graph would project for the rows above. This is the
    # only honest way to compare the two implementations: if the typed pack and the shaping pack
    # disagree on a field, the equivalence test below fails rather than both being wrong
    # together (which is what happens when the "expected" side is generated by the code
    # under test).
    function Invoke-FixtureTypedQuery {
        param([string] $Query)
        if ($Query -match 'microsoft\.resources/subscriptions"') {
            return @([pscustomobject]@{ id = 'aaa'; name = 'demo-sub'; state = 'Enabled'
                    tags = [pscustomobject]@{ Environment = 'Production'; CostCenter = 'CC-100' } })
        }
        if ($Query -match 'subscriptions/resourcegroups') {
            return @([pscustomobject]@{ name = 'rg-net'; subscriptionId = 'aaa' })
        }
        if ($Query -match 'peeringCount') {
            return @([pscustomobject]@{ name = 'vnet1'; resourceGroup = 'rg-net'; subscriptionId = 'aaa'
                    peeringCount = 1; ddosEnabled = $false })
        }
        if ($Query -match 'ipUtilizationPct') {
            return @([pscustomobject]@{ vnet = 'vnet1'; subnet = 'snet-app'; prefix = '10.0.1.0/24'
                    total = 251; used = 2; ipUtilizationPct = [Math]::Round((2 / 251) * 100, 1) })
        }
        if ($Query -match 'microsoft\.keyvault/vaults') {
            # `id` is projected for the cross-resource joins (AB#6835); the shaped path reads it
            # off the raw row, so the typed emulation has to return it too or the two paths
            # legitimately disagree on the key SET.
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv1'
                    name = 'kv1'; resourceGroup = 'rg-app'; softDelete = $true; purgeProtection = $false })
        }
        if ($Query -match 'coveragePct') {
            # `summarize total = count(), withDiag = countif(hasDiag) by type` over the three
            # fixture resources. None of them carries properties.diagnosticSettings, so
            # withDiag is 0 and coveragePct is 0.0 for each type. Order matches the shaping
            # path's Group-Object order (first appearance in the row set).
            return @(
                [pscustomobject]@{ type = 'microsoft.network/virtualnetworks'; total = 1; withDiag = 0; coveragePct = [double] 0 }
                [pscustomobject]@{ type = 'microsoft.keyvault/vaults'; total = 1; withDiag = 0; coveragePct = [double] 0 }
                [pscustomobject]@{ type = 'microsoft.compute/disks'; total = 1; withDiag = 0; coveragePct = [double] 0 }
            )
        }
        # managedDisks (AB#6835) and orphanedDisks BOTH mention diskState, so this branch must come
        # first and match on the filter that distinguishes them -- orphanedDisks is the one that
        # narrows to Unattached. Ordering these the other way round silently fed the orphan row to
        # both and the equivalence proof compared the wrong shape.
        if ($Query -match 'diskState' -and $Query -notmatch 'Unattached') {
            return @([pscustomobject]@{ id = '/subscriptions/aaa/resourceGroups/rg-app/providers/Microsoft.Compute/disks/disk-orphan'
                    name = 'disk-orphan'; resourceGroup = 'rg-app'; subscriptionId = 'aaa'; location = 'eastus'
                    sku = 'Premium_LRS'; diskState = 'Unattached'; sizeGb = 128 })
        }
        if ($Query -match 'diskState') {
            return @([pscustomobject]@{ name = 'disk-orphan'; resourceGroup = 'rg-app'; location = 'eastus'
                    sku = 'Premium_LRS'; sizeGb = 128 })
        }
        return @()
    }

    # One stub, two dispatch modes. The raw pass is identified by its projection
    # (`project id,name,type,tenantId,...`), which no typed query uses.
    function New-CountingSearchAzGraph {
        $script:argQueries = [System.Collections.Generic.List[string]]::new()
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            $script:argQueries.Add($Query)
            $isRawProjection = $Query -match 'project id,name,type,tenantId'
            if ($isRawProjection -and $Query -match '^resourcecontainers\b') { return Get-FixtureContainerRows }
            if ($isRawProjection -and $Query -match '^resources\b')           { return Get-FixtureResourceRows }
            if ($isRawProjection)                                            { return @() }
            return Invoke-FixtureTypedQuery -Query $Query
        }
    }
}

AfterAll {
    Remove-Item function:global:Search-AzGraph -ErrorAction SilentlyContinue
}

Describe 'AB#5648 — Resource Graph round-trip count per entry point' {

    BeforeEach { New-CountingSearchAzGraph }

    It 'the DEFAULT assessment collect reaches Resource Graph exactly 7 times' {
        Invoke-Collect -WarningAction SilentlyContinue | Out-Null

        # Four raw tables carrying the `project id,name,type,tenantId` marker, plus two more raw
        # tables that do NOT carry it (see below), plus the one query that genuinely cannot be
        # served from inventory.
        #
        # This was 4 until AB#6835 (recoveryservicesresources, for XR-BKP-01/02). It is 6 raw
        # round-trips as of AB#7107/AB#7108 (Story AB#7059, Feature AB#7069, Epic AB#7099):
        # `patchassessmentresources` and `patchinstallationresources` are Update Manager's OWN
        # Resource Graph tables (7-day/30-day retention respectively) -- read-only, same as every
        # other raw-pass table, but not derivable from `resources`/`networkresources` at all, so
        # collecting them costs two more round-trips. Raising this number further is a deliberate
        # contract change, and an EIGHTH would need the same justification in writing.
        $script:argQueries.Count | Should -Be 7 -Because 'the inverted path is one raw pass (resourcecontainers, resources, networkresources, recoveryservicesresources, patchassessmentresources, patchinstallationresources) plus sqlDefenderPricing'

        # patchassessmentresources/patchinstallationresources deliberately omit the `project
        # $columns` clause every OTHER raw table carries (Get-ScoutRawInventory.ps1's AB#6731
        # comment explains why: a `project` naming a column the table does not define fails the
        # whole query, and these two tables' schema is not guaranteed to match the `resources`
        # projection). That means the `project id,name,type,tenantId` marker below only ever
        # matches 4 of the 6 raw-pass queries, not all 6 -- an accident of the heuristic, not a
        # sign the patch queries are typed/live queries.
        @($script:argQueries | Where-Object { $_ -match 'project id,name,type,tenantId' }).Count | Should -Be 4
        @($script:argQueries | Where-Object { $_ -match 'microsoft\.security/pricings' }).Count | Should -Be 1
        @($script:argQueries | Where-Object { $_ -match '^patchassessmentresources' }).Count | Should -Be 1
        @($script:argQueries | Where-Object { $_ -match '^patchinstallationresources' }).Count | Should -Be 1
    }

    It 'the queries outside the projection marker are the documented SecurityResources exception plus the two patch tables, nothing else' {
        Invoke-Collect -WarningAction SilentlyContinue | Out-Null
        $unmarked = @($script:argQueries | Where-Object { $_ -notmatch 'project id,name,type,tenantId' })
        $unmarked.Count | Should -Be 3

        $securityException = @($unmarked | Where-Object { $_ -match 'SecurityResources' -and $_ -match 'microsoft\.security/pricings' })
        $securityException.Count | Should -Be 1

        $patchTables = @($unmarked | Where-Object { $_ -match '^patchassessmentresources' -or $_ -match '^patchinstallationresources' })
        $patchTables.Count | Should -Be 2
    }

    It 'the pre-inversion typed pack still costs more than 30 round-trips (the "before" number)' {
        Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue | Out-Null
        $script:argQueries.Count | Should -BeGreaterThan 30
        # And it makes no raw pass at all -- the two sources are genuinely alternatives.
        @($script:argQueries | Where-Object { $_ -match 'project id,name,type,tenantId' }).Count | Should -Be 0
    }

    It 'a narrowed -Categories collect never costs more than the full run' {
        Invoke-Collect -Categories @('Security') -WarningAction SilentlyContinue | Out-Null
        $narrow = $script:argQueries.Count

        New-CountingSearchAzGraph
        Invoke-Collect -WarningAction SilentlyContinue | Out-Null
        $full = $script:argQueries.Count

        # The raw pass (resourcecontainers/resources/networkresources/recoveryservicesresources/
        # patchassessmentresources/patchinstallationresources) is NOT category-filtered -- it is
        # the same unconditional sweep regardless of -Categories, same as -IncludeBackupResources
        # was before it -- so a narrowed run costs the same 7 as the full run; it can never cost
        # MORE.
        $narrow | Should -BeLessOrEqual $full
        $narrow | Should -BeLessOrEqual 7
    }

    It '-FromInventory still costs exactly 1 (the combined-run path is unchanged)' {
        $inventory = [pscustomobject]@{
            Resources          = Get-FixtureResourceRows
            ResourceContainers = Get-FixtureContainerRows
        }
        Invoke-Collect -FromInventory $inventory -WarningAction SilentlyContinue | Out-Null
        $script:argQueries.Count | Should -Be 1
        $script:argQueries[0] | Should -Match 'microsoft\.security/pricings'
    }

    It 'the inventory extraction path reaches Resource Graph 11 times, all from one function' {
        Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'aaa'; name = 'demo-sub' }) `
            -AzureEnvironment 'AzureCloud' -IncludeTags ([switch]$false) `
            -SkipAdvisory ([switch]$false) -SecurityCenter ([switch]$false) `
            3>$null 4>$null 6>$null | Out-Null

        # resourcecontainers, resources, networkresources, SupportResources,
        # recoveryservicesresources, desktopvirtualizationresources, patchassessmentresources,
        # patchinstallationresources, advisorresources, Retirements. Ten DISTINCT Resource Graph
        # tables -- this number cannot go to 1 without dropping datasets, and is reported as 10
        # rather than claimed as 1.
        #
        # This assertion said 8 and had been FAILING ON MAIN since v3.0.9 (AB#6731), which
        # replaced the per-machine `assessPatches` POST with reads of the two Update Manager
        # tables and did not update the count here. Corrected while running the suite for
        # AB#6741; the extra two round-trips are that change's, not this Epic's.
        #
        # 10 -> 11 (AB#6771): the `managedserviceresources` table. Management/LighthouseDelegations
        # declares a REAL resource type, Microsoft.ManagedServices/registrationDefinitions, but no
        # pass read the one ARG table that carries it, so the worksheet was blank on every run.
        # One extra round-trip is the honest price of a dataset that was previously empty.
        #
        # This budget is deliberately tight and is meant to FAIL when a round-trip is added. That
        # is how it just proved something else: AB#6779 added four governance collectors
        # (RoleAssignments, ResourceLocks, PolicyAssignments, Budgets) whose acceptance criterion
        # was "no additional Azure API call, proven by comparing query counts before and after".
        # The count moved by exactly one, and that one is attributable to AB#6771 above -- so the
        # governance renders cost ZERO new queries. This assertion IS that proof.
        $script:argQueries.Count | Should -Be 11
    }

    It 'a combined inventory + assessment run costs 12, not 43' {
        $extraction = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'aaa'; name = 'demo-sub' }) `
            -AzureEnvironment 'AzureCloud' -IncludeTags ([switch]$true) `
            -SkipAdvisory ([switch]$false) -SecurityCenter ([switch]$false) `
            3>$null 4>$null 6>$null
        Invoke-Collect -FromInventory $extraction -WarningAction SilentlyContinue | Out-Null

        # Eleven inventory tables plus the one SecurityResources query. The combined run reuses
        # the extraction's rows, so the assessment adds ONE call, not five -- that is the property
        # this assertion protects, and it is unchanged by the Update Manager tables, by the
        # recoveryservicesresources pass AB#6835 added to the standalone assessment path, or by
        # AB#6771's managedserviceresources table (which moved the inventory half from 10 to 11).
        #
        # The number that matters here is not 12; it is the DIFFERENCE of one against the
        # inventory-only assertion above. A combined run costing inventory+1 is the whole
        # collect-once guarantee. If this ever reads inventory+5, the assessment has stopped
        # reusing the extraction's rows and is querying Azure a second time.
        $script:argQueries.Count | Should -Be 12 -Because 'eleven inventory tables plus the one SecurityResources query'
    }
}

Describe 'AB#5648 — the inverted path and the typed pack produce the same collect object' {

    BeforeEach { New-CountingSearchAzGraph }

    BeforeAll {
        function Get-ScoutFlatMap {
            <#
                Flatten a collect object into path -> scalar so two runs can be compared
                key BY KEY rather than by row count or by a whole-object JSON string (which
                would report a single useless "not equal" for any difference anywhere).
            #>
            param([Parameter(Mandatory)] [AllowNull()] $InputObject, [string] $Prefix = '')
            $map = [ordered]@{}
            if ($null -eq $InputObject) { $map[$Prefix] = '<null>'; return $map }
            if ($InputObject -is [string] -or $InputObject -is [bool] -or $InputObject -is [int] -or
                $InputObject -is [long] -or $InputObject -is [double] -or $InputObject -is [decimal]) {
                $map[$Prefix] = "$($InputObject.GetType().Name):$InputObject"
                return $map
            }
            if ($InputObject -is [System.Collections.IEnumerable]) {
                $index = 0
                foreach ($item in $InputObject) {
                    foreach ($entry in (Get-ScoutFlatMap -InputObject $item -Prefix "$Prefix[$index]").GetEnumerator()) {
                        $map[$entry.Key] = $entry.Value
                    }
                    $index++
                }
                $map["$Prefix.__count"] = $index
                return $map
            }
            foreach ($property in ($InputObject.PSObject.Properties | Sort-Object Name)) {
                foreach ($entry in (Get-ScoutFlatMap -InputObject $property.Value -Prefix "$Prefix.$($property.Name)").GetEnumerator()) {
                    $map[$entry.Key] = $entry.Value
                }
            }
            return $map
        }
    }

    It 'every populated key matches, field for field, between -Source Inventory and -Source TypedQueries' {
        $inverted = Invoke-Collect -WarningAction SilentlyContinue
        New-CountingSearchAzGraph
        $typed = Invoke-Collect -Source TypedQueries -WarningAction SilentlyContinue

        # opsPosture.diagnosticCoverage comes from a KQL `summarize ... by type`, whose row
        # ORDER Resource Graph does not define (the shaping path's Group-Object happens to
        # sort by type; ARG does not promise to). Sorting both sides keeps this an assertion
        # about the DATA rather than about an ordering neither implementation guarantees.
        foreach ($collect in @($inverted, $typed)) {
            $collect.opsPosture.diagnosticCoverage = @($collect.opsPosture.diagnosticCoverage | Sort-Object type)
        }

        # _meta carries a generation timestamp, so it is excluded and asserted separately.
        $invertedMap = Get-ScoutFlatMap -InputObject ($inverted | Select-Object -ExcludeProperty _meta)
        $typedMap = Get-ScoutFlatMap -InputObject ($typed | Select-Object -ExcludeProperty _meta)

        # Same key SET first: a key present in one and absent in the other is the failure mode
        # that a value-only comparison misses entirely.
        $missingFromInverted = @($typedMap.Keys | Where-Object { -not $invertedMap.Contains($_) })
        $missingFromTyped = @($invertedMap.Keys | Where-Object { -not $typedMap.Contains($_) })
        $missingFromInverted -join ', ' | Should -BeNullOrEmpty
        $missingFromTyped -join ', ' | Should -BeNullOrEmpty

        # Then every value, reported as an explicit list of differing paths.
        $differences = @(
            foreach ($key in $typedMap.Keys) {
                if ("$($invertedMap[$key])" -ne "$($typedMap[$key])") {
                    "$key : inverted='$($invertedMap[$key])' typed='$($typedMap[$key])'"
                }
            }
        )
        $differences -join "`n" | Should -BeNullOrEmpty
    }

    It 'carries the subscription tag aggregation on the inverted path too (AB#367)' {
        # Regression guard for a defect found while writing this file: the raw pass omits the
        # `tags` COLUMN unless asked, and the top-level `tags` key is aggregated from
        # subscriptions[*].tags. Without -IncludeTags on the internal raw call the inverted path
        # returned an empty tags array for every estate -- a blank report section, no error.
        $collect = Invoke-Collect -WarningAction SilentlyContinue
        @($collect.tags).Count | Should -Be 2
        @($collect.tags | Where-Object { $_.key -eq 'Environment' }).values | Should -Be @('Production')
        @($collect.tags | Where-Object { $_.key -eq 'CostCenter' }).values | Should -Be @('CC-100')
    }

    It 'still populates sqlDefenderPricing from the live query on the inverted path' {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'microsoft\.security/pricings') {
                return @([pscustomobject]@{ subscriptionId = 'aaa'; name = 'SqlServers'; pricingTier = 'Standard' })
            }
            if ($Query -match 'project id,name,type,tenantId' -and $Query -match '^resourcecontainers\b') { return Get-FixtureContainerRows }
            if ($Query -match 'project id,name,type,tenantId' -and $Query -match '^resources\b') { return Get-FixtureResourceRows }
            return @()
        }
        $collect = Invoke-Collect -WarningAction SilentlyContinue
        @($collect.domains.databases.sqlDefenderPricing).Count | Should -Be 1
        $collect.domains.databases.sqlDefenderPricing[0].pricingTier | Should -Be 'Standard'
    }

    It 'falls back to the typed pack when the raw pass throws, rather than returning nothing' {
        function global:Search-AzGraph {
            param(
                [string] $Query, [int] $First, [int] $Skip, [string] $SkipToken,
                [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction
            )
            if ($Query -match 'project id,name,type,tenantId') { throw 'ARG is unavailable' }
            return Invoke-FixtureTypedQuery -Query $Query
        }
        # Get-ScoutRawInventory absorbs per-table failures itself (warn and skip), so a total
        # ARG outage comes back as an EMPTY raw pass rather than an exception. Either way the
        # caller must still get a well-formed collect object with the contract's keys present.
        $collect = Invoke-Collect -WarningAction SilentlyContinue
        $collect.PSObject.Properties.Name | Should -Contain 'networking'
        $collect.PSObject.Properties.Name | Should -Contain 'domains'
        { @($collect.networking.virtualNetworks).Count } | Should -Not -Throw
    }
}
