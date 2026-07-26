#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#5659 — the COVERAGE gate for the declarative collector conversion, kept separate from the
    equivalence proof in tests/DeclarativeCollectorEquivalence.Tests.ps1.

    The equivalence tests discover whatever definitions exist and prove each one matches the `.ps1` it
    was lifted from. That is necessary but not sufficient: it is trivially satisfiable by converting
    nothing. This file asserts the other half — that the converted set is exactly the set the audit
    (docs/design/collector-audit.md) classified as pure data-shaping, minus a short list of collectors
    that each carry a written reason.

    Two files rather than one because the two questions fail for different reasons and want different
    answers: an equivalence failure means a conversion is WRONG, a coverage failure means a conversion
    is MISSING.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $script:RepoRoot 'src/pipeline/Get-ScoutCollectorDefinition.ps1')
    . (Join-Path $script:RepoRoot 'src/pipeline/Invoke-ScoutDeclarativeCollector.ps1')
    . (Join-Path $script:RepoRoot 'Modules/Private/Main/Get-AZSCSafeProperty.ps1')
    . (Join-Path $script:RepoRoot 'Modules/Private/Main/Get-AZTICollectedValue.ps1')
    . (Join-Path $script:RepoRoot 'Modules/Private/Main/Get-AZSCIdSegment.ps1')

    # Only the fixture loader is needed here, not the whole equivalence harness.
    $script:GeneratedFixtures = @{}
    function Get-GeneratedFixture {
        param([string]$Category)
        if (-not $script:GeneratedFixtures.ContainsKey($Category)) {
            $Path = Join-Path $script:RepoRoot "tests/fixtures/collector-equivalence/$Category.json"
            if (-not (Test-Path -LiteralPath $Path)) { throw "No generated equivalence fixture for category '$Category' at $Path" }
            $script:GeneratedFixtures[$Category] = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        return $script:GeneratedFixtures[$Category]
    }
}

Describe 'Declarative collector coverage — the converted set is exactly the audited pure set, minus a listed few' {
    BeforeAll {
        $script:Audit = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests/fixtures/collector-audit.json') -Raw | ConvertFrom-Json

        # The four PureShaping collectors NOT converted, each with the reason. Held as data in the test
        # rather than as prose in a design doc so that "convert everything the audit called pure" cannot
        # quietly become "convert everything that happened to be easy": editing this list is visible.
        #
        # Declared in BeforeAll, not at file scope: a file-scope variable is visible during DISCOVERY
        # (where -ForEach data is built) but not inside an It at run time.
        $script:UnconvertedPure = @(
            @{ Category = 'Management'; Name = 'AllSubscriptions'
               Reason = 'Its row loop iterates $Sub, not a filtered $Resources set, so there is no resource-type filter for the interpreter to drive; it also folds in a management-group chain built from a separate graph query.' }
            @{ Category = 'Management'; Name = 'AdvisorScore'
               Reason = 'Its $obj is built inside a nested if/else rather than as a statement of a row loop, so there is no single row-emitting level to lift.' }
            @{ Category = 'Networking'; Name = 'PublicIP'
               Reason = 'It has TWO $obj hashtable literals in opposite branches of an if/else -- the row SHAPE is conditional, which the schema deliberately cannot express (a Fields list is one shape).' }
            @{ Category = 'Monitor';    Name = 'Outages'
               Reason = 'AUDIT MISCLASSIFICATION: it builds its columns with New-Object -Com HTMLFile and reads $Html.body.innerText, so it is not pure shaping at all -- it depends on a COM component the audit never looked for (it only searched for Get-Az*/Invoke-*).' }
        )

        # The six collectors whose ONLY audit obstacle is a CrossResourceJoin and which are STILL not
        # converted (AB#5659). The other 14 are. Held here for the same reason as the list above:
        # "convert the joins" must not quietly become "convert the easy joins".
        $script:UnconvertedJoins = @(
            @{ Category = 'Compute'; Name = 'AVDAzureLocal'
               Reason = 'Its row loop iterates $combined -- a set SYNTHESISED from three filtered sets with Add-Member, not a resource-type filter over $Resources. The interpreter drives its row loop from ResourceTypes, so there is no resource type to declare. (The converter refuses it by name rather than emitting something wrong.)' }
            @{ Category = 'Management'; Name = 'AutomationAccounts'
               Reason = 'TWO $obj literals in opposite branches of `if ($null -ne $rbs)`, and the branches differ in LOOP DEPTH: the match branch adds `foreach ($1 in $rbs)`, the else branch does not. Row COUNT is conditional, which a single Fields list plus a fixed loop nest cannot express -- the same obstacle as Networking/PublicIP.' }
            @{ Category = 'Networking'; Name = 'VirtualWAN'
               Reason = 'Same shape: `if($vpn)` nests THREE loops (vhub, vpn, tag) and the else nests TWO. Conditional loop depth, so conditional row count.' }
            @{ Category = 'Compute'; Name = 'VirtualMachine'
               Reason = 'Carries a LiveCmdletCall as well as the join -- six Invoke-AzRestMethod calls for CPU/memory/ASR/vault/cost inside the row loop.' }
            @{ Category = 'Compute'; Name = 'VMOperationalData'
               Reason = 'Carries a LiveCmdletCall as well as the join -- Invoke-AzRestMethod for the patch-assessment POST.' }
            @{ Category = 'Hybrid'; Name = 'ArcServerOperationalData'
               Reason = 'Carries a LiveCmdletCall as well as the join -- Invoke-AzRestMethod for the patch-assessment POST.' }
        )

        # Converted join collectors whose join the GENERATED estate does not yet exercise: the
        # partner resources are present and the row values agree with the imperative path, but the
        # collector's own predicate does not match any of them, so both paths take the not-found
        # branch and the joined columns are proven only in their empty state.
        #
        # This is a FIXTURE limitation, not a conversion defect -- and it is pinned rather than
        # left implicit precisely because "the equivalence test passes" reads as stronger evidence
        # than it is for these nine. Removing an entry (by teaching
        # scripts/New-ScoutCollectorFixture.ps1 to satisfy the predicate) is the improvement; the
        # test below fails if an entry becomes stale, so the list can only get shorter.
        $script:JoinNotExercised = @(
            @{ Category = 'Analytics';  Name = 'Streamanalytics'
               Reason = 'Joins the REVERSE way -- `$_.id -eq $data.cluster.id` -- so the PARTNER id must equal a value inside the PRIMARY payload. The generator correlates the other direction (it writes the primary id into a partner property).' }
            @{ Category = 'Containers'; Name = 'AKS'
               Reason = 'Correlates on `$VMExtraDetails.properties | Where-Object { $_.Location -eq $1.location }` -- $_ is the PROPERTIES object reached by member enumeration, not the resource, so the correlated path sits one level below where the generator writes it. The types are also the synthetic AZSC/VM/SKU and AZSC/VM/Quotas, which no real ARG query returns.' }
            @{ Category = 'Containers'; Name = 'ContainerAppEnv'
               Reason = 'The predicate is an ACCESSOR CALL -- `(Get-AZSCSafeProperty -InputObject $_ -Path ''properties.environmentId'') -eq $1.id` -- so the correlated property is named in a string rather than as a member of $_, and the generator''s `$_.<path>` scan does not see it.' }
            @{ Category = 'Networking'; Name = 'ApplicationGateways'
               Reason = 'Correlates with `-in` against a member-enumerated collection: `$1.id -in $APPGTWPOL.properties.applicationGateways.id`. The partner property is an ARRAY of ids, and the generator writes scalars.' }
            @{ Category = 'Networking'; Name = 'AzureFirewall'
               Reason = 'Reverse direction, as Streamanalytics -- `$_.id -eq $data.firewallpolicy.id`.' }
            @{ Category = 'Networking'; Name = 'NetworkInterface'
               Reason = 'Reverse direction AND through an accessor -- `$_.id -eq (Get-AZSCSafeProperty -InputObject $2 -Path ''properties.publicipaddress.id'' -Enumerate)` -- where $2 is an ipConfigurations element, so the value lives inside an array item of the primary.' }
            @{ Category = 'Networking'; Name = 'NetworkSecurityGroup'
               Reason = 'Its NIC join reads `$_.id -eq $NICID`, where $NICID is derived inside a nested loop over the NSG''s own networkInterfaces, so the id to correlate on is not a property of the primary resource at all.' }
            @{ Category = 'Networking'; Name = 'PrivateEndpoint'
               Reason = 'Reverse direction through an accessor -- `$_.id -eq (Get-AZSCSafeProperty -InputObject $data -Path ''networkInterfaces.id'' -Enumerate)`.' }
            @{ Category = 'Web';        Name = 'APPServicePlan'
               Reason = 'The correlation IS written (Properties.targetResourceUri), but the secondary set''s OWN filter also demands `$_.Properties.enabled -eq ''true''`, and the generator does not satisfy a secondary set''s filter the way Resolve-FixtureFilter satisfies the primary''s -- so the partner is dropped before the join runs.' }
        )

        $script:AllDefinitions = @(
            foreach ($Folder in (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'manifests/collectors') -Directory | Sort-Object Name)) {
                foreach ($File in (Get-ChildItem -LiteralPath $Folder.FullName -Filter '*.psd1' -File | Sort-Object Name)) {
                    @{ Category = $Folder.Name; Name = $File.BaseName }
                }
            }
        )
    }

    It 'every PureShaping collector either has a definition or is on the unconverted list' {
        $Missing = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in @($script:Audit | Where-Object { $_.Classification -eq 'PureShaping' })) {
            $Path = Join-Path $script:RepoRoot "manifests/collectors/$($Entry.Category)/$($Entry.Name).psd1"
            if (Test-Path -LiteralPath $Path) { continue }
            $Listed = @($script:UnconvertedPure | Where-Object { $_.Category -eq $Entry.Category -and $_.Name -eq $Entry.Name })
            if (@($Listed).Count -eq 0) { $Missing.Add("$($Entry.Category)/$($Entry.Name)") }
        }
        $Missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'nothing on the unconverted list has a definition after all' {
        # Keeps the list honest in the other direction: a stale entry here would understate coverage
        # and hide the fact that the obstacle was solved.
        foreach ($Entry in $script:UnconvertedPure) {
            (Join-Path $script:RepoRoot "manifests/collectors/$($Entry.Category)/$($Entry.Name).psd1") |
                Should -Not -Exist -Because "$($Entry.Category)/$($Entry.Name) is listed as unconverted: $($Entry.Reason)"
        }
    }

    It 'every definition has a generated fixture entry with at least one resource' {
        # A definition with no fixture entry would make its equivalence Describe throw rather than
        # silently pass, but a definition whose fixture entry is EMPTY would pass vacuously.
        foreach ($Entry in $script:AllDefinitions) {
            $Fixture = Get-GeneratedFixture -Category $Entry.Category
            $Fixture.collectors.PSObject.Properties.Name | Should -Contain $Entry.Name
            @($Fixture.collectors.($Entry.Name).resources).Count | Should -BeGreaterThan 0
        }
    }

    It 'every join-only collector either has a definition or is on the unconverted-joins list' {
        # The AB#5659 half of the coverage claim. A CrossResourceJoin over a set derived from
        # $Resources is expressible (SetupPreamble/SetupVariables), so a collector whose ONLY
        # audit obstacle is such a join must be converted -- or be listed with a reason.
        $Missing = [System.Collections.Generic.List[string]]::new()
        $JoinOnly = @($script:Audit | Where-Object {
            $_.Classification -ne 'PureShaping' -and
            @($_.EscapeHatchReasons).Count -gt 0 -and
            @($_.EscapeHatchReasons | Where-Object { $_ -notlike 'CrossResourceJoin*' }).Count -eq 0
        })
        @($JoinOnly).Count | Should -BeGreaterThan 0

        foreach ($Entry in $JoinOnly) {
            if (Test-Path -LiteralPath (Join-Path $script:RepoRoot "manifests/collectors/$($Entry.Category)/$($Entry.Name).psd1")) { continue }
            $Listed = @($script:UnconvertedJoins | Where-Object { $_.Category -eq $Entry.Category -and $_.Name -eq $Entry.Name })
            if (@($Listed).Count -eq 0) { $Missing.Add("$($Entry.Category)/$($Entry.Name)") }
        }
        $Missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'nothing on the unconverted-joins list has a definition after all' {
        foreach ($Entry in $script:UnconvertedJoins) {
            (Join-Path $script:RepoRoot "manifests/collectors/$($Entry.Category)/$($Entry.Name).psd1") |
                Should -Not -Exist -Because "$($Entry.Category)/$($Entry.Name) is listed as unconverted: $($Entry.Reason)"
        }
    }

    It 'a converted join collector''s join either changes the rows the fixture produces, or is listed as unexercised' {
        # The equivalence proof compares two paths on ONE estate, so it is satisfied when both paths
        # take the join's not-found branch -- which proves nothing about the join. This asks the
        # sharper question directly: remove the join partners from the estate and see whether the
        # output changes. If it does not, the fixture is not testing the join and that has to be
        # said out loud rather than inferred from a green tick.
        $Unexercised = [System.Collections.Generic.List[string]]::new()
        $Exercised   = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($Entry in $script:AllDefinitions) {
            $Definition = Get-ScoutCollectorDefinition -Path (Join-Path $script:RepoRoot "manifests/collectors/$($Entry.Category)/$($Entry.Name).psd1")
            $Fixture    = Get-GeneratedFixture -Category $Entry.Category
            $All        = @($Fixture.collectors.($Entry.Name).resources)
            $Declared   = @($Definition.ResourceTypes)

            $Primary = @($All | Where-Object { $Type = $_.TYPE; @($Declared | Where-Object { $_ -ieq $Type }).Count -gt 0 })
            if (@($Primary).Count -eq @($All).Count) { continue }   # no join partners: not a join collector

            function New-JoinContext { param($Resources)
                @{ ScriptRoot = $script:RepoRoot; Subscriptions = $Fixture.subscriptions; InTag = $false
                   Resources = $Resources; Retirements = $Fixture.retirements; Task = 'Processing'
                   File = $null; SmaResources = $null; TableStyle = 'Light20'; Unsupported = $Fixture.unsupported }
            }
            function ConvertTo-JoinText { param($Rows)
                (@($Rows) | ForEach-Object {
                    $Row = $_
                    if ($Row -isnot [System.Collections.IDictionary]) { return '<non-row>' }
                    (@($Row.Keys | Sort-Object) | ForEach-Object { "$_=$($Row[$_])" }) -join '|'
                }) -join "`n"
            }

            $WithPartners    = ConvertTo-JoinText (Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (New-JoinContext -Resources $All))
            $WithoutPartners = ConvertTo-JoinText (Invoke-ScoutDeclarativeCollector -Definition $Definition -Context (New-JoinContext -Resources $Primary))

            $Key = "$($Entry.Category)/$($Entry.Name)"
            if ($WithPartners -ne $WithoutPartners) { [void]$Exercised.Add($Key); continue }

            $Listed = @($script:JoinNotExercised | Where-Object { $_.Category -eq $Entry.Category -and $_.Name -eq $Entry.Name })
            if (@($Listed).Count -eq 0) { $Unexercised.Add($Key) }
        }

        $Unexercised -join ', ' | Should -BeNullOrEmpty -Because 'a join collector whose partners make no difference to its output is not actually having its join tested; add it to $script:JoinNotExercised with a reason, or fix the fixture generator'

        # Stale entries fail too, so the list can only get shorter.
        $Stale = @($script:JoinNotExercised | Where-Object { $Exercised.Contains("$($_.Category)/$($_.Name)") })
        (@($Stale) | ForEach-Object { "$($_.Category)/$($_.Name)" }) -join ', ' |
            Should -BeNullOrEmpty -Because 'these joins ARE now exercised by the generated estate -- delete their entries from $script:JoinNotExercised'
    }

    It 'no generated fixture carries anything that looks like a real tenant identifier' {
        # The generated estates are entirely synthetic, but they live in tests/fixtures next to the
        # recorded ones and the repo's hard rule about subscription/tenant ids applies to every
        # committed file. The only GUIDs these may contain are the two placeholders.
        $Allowed = @('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000ff')
        $Pattern = [regex]'(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
        foreach ($File in (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'tests/fixtures/collector-equivalence') -Filter '*.json' -File)) {
            $Text = Get-Content -LiteralPath $File.FullName -Raw
            $Bad  = @($Pattern.Matches($Text) | ForEach-Object { $_.Value } | Where-Object { $Allowed -notcontains $_.ToLowerInvariant() } | Select-Object -Unique)
            $Bad -join ', ' | Should -BeNullOrEmpty -Because "$($File.Name) must contain no identifier that could be real"
        }
    }
}
