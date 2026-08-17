#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6842 / AB#6772 — every declared resource type must exist in Azure.

    This is the one check in the verification story that the test suite could never make on its
    own, because of how the suite is built: `scripts/New-ScoutCollectorFixture.ps1` derives each
    collector's fixture estate from that collector's OWN expressions. The declared resource type
    is fabricated into existence and every property it reads is present by construction. A
    collector for a type Azure does not have passes forever — `Hybrid/ArcSites` declared three
    such strings and shipped green through every release.

    The fix is ground truth that does not come from the manifests. `manifests/azure-provider-types.json`
    is read from ARM by `scripts/Update-ScoutProviderCatalog.ps1` and committed, so this gate
    runs offline on every pull request with no Azure credentials while still checking against
    Azure's own answer.

    It is also the only verification check that works on a SMALL tenant: it needs the resource
    provider to be real, not for the customer to own one of the resources.

    Deliberately NOT checked here: whether a type that exists returns any rows in this tenant.
    That is a live-run question (AB#6843), and conflating the two is how "0 rows" became
    ambiguous in the first place.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent

    $catalogPath = Join-Path -Path $script:Root -ChildPath 'manifests/azure-provider-types.json'
    $script:Catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
    $script:Known = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @($script:Catalog.Types), [System.StringComparer]::OrdinalIgnoreCase)

    # Scout stamps its own synthetic TYPE strings on rows that have no ARM counterpart:
    # `AZSC/...` envelopes from the enrichment helpers, `entra/...` from the Microsoft Graph
    # pass, and `devops/...` from the Azure DevOps REST collectors. None is a resource provider
    # type and none can appear in an ARM catalogue, so excluding them is correct rather than
    # convenient. Anything else that cannot be found is a defect.
    $script:SyntheticPrefixes = @('azsc/', 'entra/', 'devops/')

    # Resource Graph's securityresources table exposes attack paths as typed rows, but ARM
    # provider metadata does not advertise that query-only entity. Keep this exception explicit
    # and exact; it is neither a synthetic Scout type nor an ARM-addressable resource type.
    $script:ResourceGraphOnlyTypes = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @('microsoft.security/attackpaths'),
        [System.StringComparer]::OrdinalIgnoreCase)

    function Test-ScoutSynthetic {
        param([string] $Type)
        $t = $Type.ToLowerInvariant()
        foreach ($p in $script:SyntheticPrefixes) { if ($t.StartsWith($p)) { return $true } }
        return $false
    }

    # ARM's provider metadata under-reports NESTED types. `Microsoft.RecoveryServices/vaults`
    # is listed but most of its `vaults/backup*` children are not, and `Microsoft.Maps/accounts`
    # is listed while `accounts/creators` is not -- both of those child types are real and
    # callable. Failing on them would train people to exempt things, which is how a gate stops
    # working.
    #
    # So a type with three or more segments is checked against its PARENT instead. That keeps
    # the gate strict where it matters: a child of a provider/type pair that does not exist is
    # still rejected, and every string this gate was built to catch is a two-segment type.
    function Test-ScoutTypeExists {
                [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Name matches the real collector/API/fixture noun (often already plural in the product surface, e.g. ManagementGroups); renaming would break the shadow/mocked signature or the fixture-name convention used across this suite.')]
param([string] $Type)
        $t = $Type.ToLowerInvariant()
        if ($script:Known.Contains($t)) { return $true }
        if ($script:ResourceGraphOnlyTypes.Contains($t)) { return $true }

        $segments = $t.Split('/')
        if ($segments.Count -ge 3) {
            return $script:Known.Contains(($segments[0] + '/' + $segments[1]))
        }
        return $false
    }

    $script:Declared = foreach ($file in Get-ChildItem (Join-Path -Path $script:Root -ChildPath 'manifests/collectors') -Filter '*.psd1' -Recurse -File) {
        $definition = Import-PowerShellDataFile -LiteralPath $file.FullName
        if (-not $definition.ContainsKey('ResourceTypes')) { continue }
        foreach ($type in @($definition.ResourceTypes)) {
            if ([string]::IsNullOrWhiteSpace($type)) { continue }
            [PSCustomObject]@{
                Collector = '{0}/{1}' -f $file.Directory.Name, $file.BaseName
                Type      = [string] $type
                Synthetic = Test-ScoutSynthetic ([string] $type)
            }
        }
    }
    $script:Declared = @($script:Declared)
}

Describe 'AB#6842 — the ground truth comes from Azure, not from the manifests' {

    It 'reads a committed catalogue produced by ARM' {
        $script:Catalog.Schema | Should -Be 'azure-scout/azure-provider-types/v1'
        $script:Catalog.Source | Should -Be 'Get-AzResourceProvider -ListAvailable'
    }

    It 'contains enough of Azure to be a real catalogue rather than a stub' {
        # A truncated or hand-written catalogue would make this gate vacuous in the quietest
        # possible way: everything unknown, or everything known.
        $script:Catalog.TypeCount | Should -BeGreaterThan 3000
        @($script:Catalog.Types).Count | Should -Be $script:Catalog.TypeCount
    }

    It 'knows the types Scout obviously depends on' {
        foreach ($t in 'microsoft.compute/virtualmachines',
                       'microsoft.storage/storageaccounts',
                       'microsoft.network/virtualnetworks',
                       'microsoft.keyvault/vaults') {
            $script:Known.Contains($t) | Should -BeTrue -Because "'$t' is unquestionably real"
        }
    }

    It 'does NOT contain the strings this gate exists to reject' {
        # Proven non-vacuous from the other side too: if the catalogue happened to contain these,
        # the gate below would pass for the wrong reason.
        $script:Known.Contains('microsoft.edgeconfig/sites') | Should -BeFalse
        $script:Known.Contains('microsoft.azurestackhci/sites') | Should -BeFalse
    }
}

Describe 'AB#6842 — synthetic envelope types are excluded deliberately' {

    It 'excludes AZSC/ and entra/ prefixes and nothing else' {
        $synthetic = @($script:Declared | Where-Object Synthetic)

        $synthetic.Count | Should -BeGreaterThan 0
        foreach ($row in $synthetic) {
            $row.Type | Should -Match '^(?i)(AZSC/|entra/|devops/)' -Because 'the exclusion must not quietly widen'
        }
    }

    It 'still checks the majority of declared types' {
        # If the exclusion ever swallowed most of the tree, the gate would look green while
        # checking almost nothing.
        $checked = @($script:Declared | Where-Object { -not $_.Synthetic })

        $checked.Count | Should -BeGreaterThan (@($script:Declared).Count / 2)
    }
}

Describe 'AB#6772 — a manifest declaring a non-existent resource type fails the build' {

    It 'finds no unknown ARM resource type in any collector manifest' {
        $unknown = @(
            $script:Declared |
                Where-Object { -not $_.Synthetic } |
                Where-Object { -not (Test-ScoutTypeExists $_.Type) }
        )

        if ($unknown.Count -gt 0) {
            $detail = ($unknown | Sort-Object Collector, Type | ForEach-Object { "  $($_.Collector) declares '$($_.Type)'" }) -join "`n"
            throw "These collectors declare resource types Azure does not have. Each one emits an empty worksheet that reads as 'none found':`n$detail`n`nIf you believe a type is real and the catalogue is stale, refresh it with scripts/Update-ScoutProviderCatalog.ps1 and commit the result."
        }

        $unknown.Count | Should -Be 0
    }

    It 'would have caught the known-bad strings — proven, not asserted' {
        # AB#6842's acceptance criterion: the check must FAIL against Hybrid/ArcSites as it
        # shipped. That collector is corrected now, so the proof is re-run here against its
        # original declaration rather than lost with the fix.
        $shippedArcSites = @(
            'microsoft.azurestackhci/sites'
            'microsoft.edgeconfig/sites'
            'microsoft.hybridcompute/sites'
        )

        foreach ($t in $shippedArcSites) {
            $script:Known.Contains($t) | Should -BeFalse -Because "the gate must reject '$t', which Hybrid/ArcSites declared for several releases"
        }

        # And the other two-segment strings this gate found on its first run, each of which was
        # a real collector defect: a type name that had been renamed, or a provider Azure has
        # emptied entirely.
        foreach ($t in 'microsoft.classiccompute/domainnames',
                       'microsoft.datalakestore/accounts',
                       'microsoft.migrate/projects',
                       'microsoft.hardwaresecuritymodules/dedicatedhsms',
                       'microsoft.confidentialledger/managedccfs') {
            $script:Known.Contains($t) | Should -BeFalse -Because "'$t' was declared by a shipped collector and does not exist"
        }

        # The replacements the corrected collectors now declare, so a future rename shows up
        # here rather than as a silently empty worksheet.
        foreach ($t in 'microsoft.migrate/migrateprojects',
                       'microsoft.hardwaresecuritymodules/cloudhsmclusters',
                       'microsoft.confidentialledger/ledgers') {
            $script:Known.Contains($t) | Should -BeTrue
        }
    }

    It 'accepts a real child type ARM metadata does not enumerate' {
        # Microsoft.RecoveryServices lists `vaults` but not its `vaults/backupPolicies` child,
        # and Microsoft.Maps lists `accounts` but not `accounts/creators`. Both children are
        # real and callable, so the parent rule must let them through.
        Test-ScoutTypeExists 'microsoft.recoveryservices/vaults/backuppolicies' | Should -BeTrue
        Test-ScoutTypeExists 'microsoft.maps/accounts/creators'                 | Should -BeTrue
    }

    It 'still rejects a child whose parent does not exist' {
        # The parent rule must not become a way to smuggle anything through by adding a segment.
        Test-ScoutTypeExists 'microsoft.edgeconfig/sites/anything' | Should -BeFalse
    }

    It 'allows only the named Resource Graph entity, not its whole provider namespace' {
        Test-ScoutTypeExists 'microsoft.security/attackpaths'       | Should -BeTrue
        Test-ScoutTypeExists 'microsoft.security/not-a-real-entity' | Should -BeFalse
        $script:ResourceGraphOnlyTypes.Count | Should -Be 1
    }
}
