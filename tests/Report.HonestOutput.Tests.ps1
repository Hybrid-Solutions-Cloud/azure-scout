#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6764 / AB#6765 / AB#6766 — Scout stops reporting things that are not true.

    Three defects, one theme: a run that produced less than it claimed and said nothing.

      AB#6764 — the Resource Graph pass is unfiltered, the manifests decide what reaches a
      worksheet, and roughly 40% of what was collected was discarded without being written
      anywhere. A resource type no manifest claims left no trace it had ever been seen.

      AB#6765 — the pre-flight ended on one word, and `$isCritical` was a hardcoded list of four
      check names. A permission denied outside those four printed "READY — Full ARM + Entra ID
      scan supported" over a scan whose worksheet would render empty. The Graph failure itself
      was swallowed into a coloured Write-Host that reaches no capturable stream.

      AB#6766 — the only per-collector evidence a run produced was the ReportCache, and
      Invoke-AzureScout clears it unconditionally at the end of every run. Nothing survived to
      compare one run against another.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path -Path $script:Root -ChildPath 'src/Export-ScoutRawInventoryDump.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutEntraQueryCatalog.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/Get-ScoutGraphPermissionImpact.ps1')

    $script:Work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("scout-honest-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
}

AfterAll {
    if ($script:Work -and (Test-Path $script:Work)) { Remove-Item $script:Work -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'AB#6764 — every collected row reaches the raw artifact' {

    BeforeAll {
        $script:Extraction = [pscustomobject]@{
            Resources = @(
                [pscustomobject]@{ id = '/r/1'; name = 'vm-1';    type = 'microsoft.compute/virtualmachines'; properties = [pscustomobject]@{ nested = [pscustomobject]@{ deep = 'value' } } }
                # A type no collector manifest claims. Before this artifact it was collected and
                # thrown away, which is the whole point of the story.
                [pscustomobject]@{ id = '/r/2'; name = 'weird-1'; type = 'microsoft.madeup/thingies';         properties = $null }
                [pscustomobject]@{ id = '/r/3'; name = 'vm-2';    type = 'microsoft.compute/virtualmachines'; properties = $null }
            )
            ResourceContainers = @([pscustomobject]@{ id = '/s/1'; type = 'microsoft.resources/subscriptions' })
            Advisories         = @()
            Security           = @()
            Retirements        = @()
            EntraResources     = @([pscustomobject]@{ id = 'u1'; TYPE = 'entra/users' })
            EntraQueryOutcomes = @([pscustomobject]@{ Source = 'Microsoft Graph'; Name = 'Users'; Status = 'Success'; Count = 1; Uri = 'https://graph.microsoft.com/v1.0/users' })
            CollectionHealth   = @([pscustomobject]@{ Source = 'ARM'; Dataset = 'Example'; Status = 'NotAssessed'; Reason = 'fixture' })
            SourceOperations   = @([pscustomobject]@{ Source = 'Azure Resource Graph'; Dataset = 'Resources'; Status = 'Success'; Count = 3 })
        }

        $script:DumpPath = Export-ScoutRawInventoryDump -ExtractionData $script:Extraction -DefaultPath $script:Work
        $script:Dump     = Get-Content -Raw -LiteralPath $script:DumpPath | ConvertFrom-Json -Depth 100
    }

    It 'writes the artifact to the run folder, not the cache folder' {
        # Clear-AZSCCacheFolder deletes everything under ReportCache and nothing above it, so
        # the artifact must live one level up or it is gone by the time the run ends.
        Split-Path $script:DumpPath -Parent | Should -Be $script:Work
        $script:DumpPath | Should -Not -Match 'ReportCache'
    }

    It 'contains every resource row' {
        @($script:Dump.Resources).Count | Should -Be 3
    }

    It 'contains a resource type no manifest claims' {
        @($script:Dump.Resources | Where-Object type -eq 'microsoft.madeup/thingies').Count | Should -Be 1
    }

    It 'censuses the types, which is the shortest answer to "what did we not show?"' {
        $census = @($script:Dump.ResourceTypes)

        ($census | Where-Object Type -eq 'microsoft.compute/virtualmachines').Rows | Should -Be 2
        ($census | Where-Object Type -eq 'microsoft.madeup/thingies').Rows          | Should -Be 1
    }

    It 'preserves the nested properties bag rather than truncating it to a type name' {
        # A shallower ConvertTo-Json depth would render `properties` as a class name string,
        # which is the same silent loss the artifact exists to end.
        $script:Dump.Resources[0].properties.nested.deep | Should -Be 'value'
    }

    It 'carries the other extraction sets too' {
        @($script:Dump.ResourceContainers).Count | Should -Be 1
        @($script:Dump.EntraResources).Count     | Should -Be 1
        @($script:Dump.EntraQueryOutcomes).Count | Should -Be 1
        @($script:Dump.CollectionHealth).Count   | Should -Be 1
        @($script:Dump.SourceOperations).Count   | Should -Be 1
        $script:Dump.Counts.Resources            | Should -Be 3
    }

    It 'declares a schema so a later run can be diffed against it' {
        $script:Dump.Schema | Should -Be 'azure-scout/raw-inventory/v2'
    }

    It 'survives an extraction shape that omits half its properties' {
        # $ExtractionData's shape varies with -Scope and the -Skip* switches; an EntraOnly run
        # has no Resources at all, and under StrictMode dotting an absent property throws.
        $sparse = [pscustomobject]@{ EntraResources = @([pscustomobject]@{ id = 'u1' }) }

        $p = Export-ScoutRawInventoryDump -ExtractionData $sparse -DefaultPath $script:Work -FileName 'sparse.json'
        $d = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json

        $d.Counts.Resources      | Should -Be 0
        @($d.EntraResources).Count | Should -Be 1
    }

    It 'returns $null rather than throwing when there is nothing to dump' {
        Export-ScoutRawInventoryDump -ExtractionData $null -DefaultPath $script:Work | Should -BeNullOrEmpty
    }

    It 'streams a large resource set into valid JSON without a whole-document serializer call' {
        $large = [pscustomobject]@{
            Resources = @(1..10000 | ForEach-Object {
                [pscustomobject]@{
                    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Example/widgets/$_"
                    type = 'Microsoft.Example/widgets'
                    properties = [pscustomobject]@{ ordinal = $_; nested = [pscustomobject]@{ retained = $true } }
                }
            })
        }

        $largePath = Export-ScoutRawInventoryDump -ExtractionData $large -DefaultPath $script:Work -FileName 'large.json'
        $largeDump = Get-Content -Raw -LiteralPath $largePath | ConvertFrom-Json -Depth 100

        @($largeDump.Resources).Count | Should -Be 10000
        $largeDump.Resources[9999].properties.nested.retained | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:Work -Filter 'large.json.*.tmp').Count | Should -Be 0

        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Export-ScoutRawInventoryDump.ps1')
        $source | Should -Not -Match '\$payload\s*\|\s*ConvertTo-Json'
    }

    It 'is called before the processing phase filters anything' {
        # "Before any manifest filtering" has to be a property of the call site, not a claim.
        $source   = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AzureScout.ps1')
        $dumpAt   = $source.IndexOf('Export-ScoutRawInventoryDump -ExtractionData')
        $processAt = $source.IndexOf('Start-AZSCProcessOrchestration -Subscriptions')

        $dumpAt    | Should -BeGreaterThan 0
        $processAt | Should -BeGreaterThan $dumpAt
    }
}

Describe 'AB#6766 — the row-count artifact survives the run' {

    BeforeAll {
        . (Join-Path -Path $script:Root -ChildPath 'src/pipeline/Invoke-ScoutProcessing.ps1')
        . (Join-Path -Path $script:Root -ChildPath 'src/pipeline/Get-ScoutCollector.ps1')
        . (Join-Path -Path $script:Root -ChildPath 'src/Clear-AZTICacheFolder.ps1')
    }

    It 'writes counts outside the folder Clear-AZSCCacheFolder deletes' {
        $runFolder = Join-Path -Path $script:Work -ChildPath 'run1'
        $cache     = Join-Path -Path $runFolder -ChildPath 'ReportCache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        'x' | Out-File (Join-Path -Path $cache -ChildPath 'Compute.json')
        '{"Schema":"azure-scout/collector-rowcounts/v1"}' | Out-File (Join-Path -Path $runFolder -ChildPath 'collector-rowcounts.json')

        Clear-AZSCCacheFolder -ReportCache $cache

        Test-Path (Join-Path -Path $cache -ChildPath 'Compute.json')             | Should -BeFalse
        Test-Path (Join-Path -Path $runFolder -ChildPath 'collector-rowcounts.json') | Should -BeTrue
    }

    It 'gives every collector an explicit row and availability verdict' {
        # "0 rows" alone is ambiguous: it can mean genuinely empty, intentionally not
        # assessed, unavailable source data, or a failed collector. Pin every honest verdict.
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/pipeline/Invoke-ScoutProcessing.ps1')

        foreach ($verdict in @('Failed', 'Rows', 'NotAssessed', 'Unavailable', 'Empty')) {
            $source | Should -Match "'${verdict}'"
        }
    }

    It 'writes the artifact to the run folder' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/pipeline/Invoke-ScoutProcessing.ps1')

        $source | Should -Match "\`$RowCountPath = Join-Path \`$DefaultPath 'collector-rowcounts\.json'"
        $source | Should -Not -Match "Join-Path \`$CachePath 'collector-rowcounts"
    }

    It 'sorts the rows so two runs diff cleanly' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/pipeline/Invoke-ScoutProcessing.ps1')

        $source | Should -Match 'Sort-Object Category, Collector'
    }

    It 'returns the same summary shape from the no-collectors branch' {
        # A summary whose properties depend on which branch produced it is the trap that caused
        # the v2.5.3 crash wave: the caller reads .EmptyCount and StrictMode throws.
        $summary = Invoke-ScoutProcessing -Resources @() -Retirements @() -Subscriptions @() `
            -DefaultPath $script:Work -Category @('NoSuchCategory') -WarningAction SilentlyContinue

        $summary.PSObject.Properties.Name | Should -Contain 'CollectorRows'
        $summary.PSObject.Properties.Name | Should -Contain 'RowCountPath'
        $summary.PSObject.Properties.Name | Should -Contain 'EmptyCount'
    }
}

Describe 'AB#6765 — criticality is derived, not listed' {

    BeforeAll {
        $script:Impact = @(Get-ScoutGraphPermissionImpact -CollectorRoot (Join-Path -Path $script:Root -ChildPath 'manifests/collectors'))
    }

    It 'finds the collectors behind every consumed permission' {
        $userImpact = @($script:Impact | Where-Object Permission -eq 'User.Read.All')[0]

        $userImpact.IsConsumed | Should -BeTrue
        $userImpact.Collectors | Should -Contain 'Identity/Users'
    }

    It 'attributes a permission shared by several queries to all of their collectors' {
        # Application.Read.All unlocks three queries: applications, service principals, and the
        # managed-identity filter over service principals.
        $appImpact = @($script:Impact | Where-Object Permission -eq 'Application.Read.All')[0]

        $appImpact.Collectors | Should -Contain 'Identity/AppRegistrations'
        $appImpact.Collectors | Should -Contain 'Identity/ServicePrincipals'
        $appImpact.Collectors | Should -Contain 'Identity/ManagedIdentities'
    }

    It 'excludes disabled, unconsumed catalog entries from the permission request entirely' {
        @($script:Impact.Permission) | Should -Not -Contain 'IdentityProvider.Read.All'
        @($script:Impact.Queries) | Should -Not -Contain 'Security Defaults'
    }

    It 'requests AuditLog.Read.All now that retained sign-in evidence is consumed' {
        $auditImpact = @($script:Impact | Where-Object Permission -eq 'AuditLog.Read.All')[0]
        $auditImpact.IsConsumed | Should -BeTrue
        $auditImpact.Queries | Should -Contain 'Sign-ins (Last 30 Days)'
    }

    It 'has no hardcoded critical list left in the pre-flight' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AZTIPermissionAudit.ps1')

        $source | Should -Not -Match "\`$isCritical = \`$checkName -in"
        $source | Should -Match 'Get-ScoutGraphPermissionImpact'
    }

    It 'changes its answer when a collector is added, with no list to edit' {
        # The property that makes this derived rather than restated. A tree containing one
        # collector for one entra type must yield consumers for exactly that type's permission.
        $fakeRoot = Join-Path -Path $script:Work -ChildPath 'fake-collectors/Identity'
        New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
        "@{ ResourceTypes = @('entra/domains') }" | Out-File (Join-Path -Path $fakeRoot -ChildPath 'OnlyDomains.psd1')

        $impact = @(Get-ScoutGraphPermissionImpact -CollectorRoot (Join-Path -Path $script:Work -ChildPath 'fake-collectors'))

        @($impact | Where-Object Permission -eq 'Domain.Read.All')[0].Collectors | Should -Be @('Identity/OnlyDomains')
        @($impact | Where-Object Permission -eq 'User.Read.All')[0].IsConsumed   | Should -BeFalse
    }

    It 'routes a denied Graph permission to the warning stream' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AZTIPermissionAudit.ps1')

        $source | Should -Match "Write-Warning .*Graph permission.*is DENIED"
    }

    It 'warns from the extraction too, not only from the pre-flight' {
        # The pre-flight is optional. The extraction's own SKIP branch was a coloured
        # Write-Host and nothing else, so a run that skipped the pre-flight had no capturable
        # record at all.
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/collect/Start-ScoutEntraExtraction.ps1')

        $source | Should -Match 'Write-Warning .*failed unexpectedly.*dependent collectors are unavailable'
    }

    It 'exposes the impact on the result object, not only on the console' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AZTIPermissionAudit.ps1')

        $source | Should -Match 'EmptyCollectors  = @\(\$emptyCollectors'
    }
}

Describe 'AB#6765 — the query catalog is the single source both sides read' {

    It 'is used by the extraction loop rather than a second literal' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/collect/Start-ScoutEntraExtraction.ps1')

        $source | Should -Match '\$entraQueries = @\(Get-ScoutEntraQueryCatalog\)'
        $source | Should -Not -Match "Name         = 'Conditional Access Policies'"
    }

    It 'gives every query a permission, so no query can be silently uncosted' {
        foreach ($q in @(Get-ScoutEntraQueryCatalog)) {
            $q.Permission | Should -Not -BeNullOrEmpty -Because "query '$($q.Name)' must declare what it costs"
            $q.Type       | Should -Match '^entra/'
        }
    }

    It 'covers the original queries plus evidence-complete identity datasets' {
        @(Get-ScoutEntraQueryCatalog).Count | Should -Be 26
    }
}
