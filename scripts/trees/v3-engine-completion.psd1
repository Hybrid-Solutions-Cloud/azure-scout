@{
    # Work-item tree for completing the inventory engine rebuild and shipping v3.0.0.
    #
    # Consumed by scripts/New-BoardTree.ps1. Nodes reference each other by local Key, never by
    # AB# id -- ids are server-assigned and guessing them has produced wrong references before.
    #
    # Every acceptance criterion here is written as something a script can check: a file absent,
    # a count equal to a number, an AST assertion, a test passing. Epic AB#5638 was closed while
    # unfinished because its criteria were never checked against the repo; prose criteria are how
    # that happens.
    #
    # Scope evidence: all counts re-derived at v2.11.0 (a9f41b5) by AST analysis --
    # 221 .ps1 under Modules/, 176 collectors, 138 definitions, 38 unconverted, 45 non-collector
    # files, 20 StrictMode weakening sites (all live), 11 data-access clusters.

    Tree = @(

        #-------------------------------------------------------------------------------------
        # EPIC
        #-------------------------------------------------------------------------------------
        @{
            Key      = 'epic'
            Type     = 'Epic'
            Priority = 1
            Title    = 'Complete the inventory engine rebuild and delete the forked ARI code'
            Tags     = 'azure-scout; thisismydemo; powershell; module-enhancement'
            Description = '<div><p>The inventory engine is a fork of microsoft/ARI carried under Modules/. Epic AB#5638 set out to replace it and was closed after v2.11.0, but it never met its own acceptance criteria and has been reopened: Modules/ still holds 221 .ps1 files, the collector folder still holds 176, and 138 of 176 collectors are definitions.</p><p>Why now: the releases from v2.6.0 to v2.11.0 built the machinery -- a deterministic pipeline, a declarative interpreter, a CI gate, single-pass collection -- but the fork is still the thing that runs the report. Until it is gone the codebase carries two implementations of everything, and v3.0.0 cannot honestly be tagged.</p><p>In scope: the 38 collectors that cannot currently be expressed declaratively, routing reporting through the definitions, StrictMode across every module scope, relocating the 45 surviving non-collector files, removing the deprecated public entry point, and deleting Modules/. Out of scope: the web portal (Epic AB#5093) and Lighthouse multi-tenant (Epic AB#5410).</p></div>'
            AcceptanceCriteria = @(
                'Test-Path Modules returns False on main.'
                'No file under src/ or tests/ contains the literal string InventoryModules.'
                'pwsh -File scripts/Test-StrictModeGuard.ps1 reports 0 weakening sites and an empty allow-list.'
                'A live tenant run completes with zero collector failures and produces a workbook whose worksheet set and row counts match the v2.11.0 baseline.'
                'Import-Module AzureScout exposes the same public function set as v2.11.0 apart from the deliberate removal of Invoke-ScoutAssessment.'
                'scripts/Test-BoardConformance.ps1 passes with every child of this epic Closed.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 1 -- the sequencing blocker. Nothing may be deleted before this lands.
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-proof'; Type = 'Feature'; Parent = 'epic'; Priority = 1
            Title = 'Preserve a reference proof that outlives the imperative collectors'
            Tags  = 'azure-scout; thisismydemo; testing; powershell'
            Description = '<div><p>tests/DeclarativeCollectorEquivalence.Tests.ps1 builds a descriptor pointing at the collector .ps1 and calls Invoke-ScoutCollector -Imperative to produce the reference output it compares against. The entire safety argument for the declarative path is structurally dependent on the .ps1 files existing.</p><p>Why now: this is the sequencing blocker for the whole epic. Delete the fork first and there is no reference implementation left to compare against, so the deletion becomes unverifiable -- the same failure mode that let AB#5638 be closed while unfinished.</p><p>In scope: recording golden output while the imperative path still exists, re-pointing the equivalence suite at it, and redefining definition drift so it does not depend on a SourceCollector file. Out of scope: converting any collector.</p></div>'
            AcceptanceCriteria = @(
                'A committed golden row-set exists for every collector that has a definition, captured from the imperative path.'
                'tests/DeclarativeCollectorEquivalence.Tests.ps1 passes with the collector .ps1 tree renamed away.'
                'scripts/Test-ScoutCollectorDefinition.ps1 exits 0 with the collector .ps1 tree renamed away.'
            )
        }
        @{
            Key = 's-golden'; Type = 'User Story'; Parent = 'f-proof'; Priority = 1
            Title = 'Record golden row-sets from the imperative collectors'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = '<div><p>Capture, per collector and per fixture estate, the exact rows the imperative path emits, and commit them. This is the artefact that replaces the .ps1 as the reference implementation.</p><p>In scope: capture tooling, the recorded data, and a determinism check. Out of scope: changing collector behaviour -- anything that changes an output here invalidates the record.</p></div>'
            AcceptanceCriteria = @(
                'A capture script exists under scripts/ and regenerates the golden set byte-identically on a second run.'
                'A golden row-set is committed for each of the 138 collectors that currently has a definition, plus each of the 38 as they convert.'
                'The capture records both the processed rows and the written worksheet cells, matching what the current equivalence test compares.'
            )
        }
        @{
            Key = 's-repoint'; Type = 'User Story'; Parent = 'f-proof'; Priority = 1
            Title = 'Re-point the equivalence suite at the recorded output'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = '<div><p>Replace the live -Imperative reference call in the equivalence test with the committed golden data, so the suite proves the same property without needing the .ps1 files.</p><p>In scope: the equivalence and coverage tests. Out of scope: relaxing what is compared -- the key-by-key row comparison and cell-by-cell workbook comparison must both survive.</p></div>'
            AcceptanceCriteria = @(
                'No test under tests/ calls Invoke-ScoutCollector with -Imperative.'
                'The equivalence suite still compares rows key-by-key and workbook cells cell-by-cell under both IncludeTags states.'
                'Mutating one field expression in a definition makes the equivalence suite fail.'
            )
        }
        @{
            Key = 's-drift'; Type = 'User Story'; Parent = 'f-proof'; Priority = 2
            Title = 'Redefine definition drift without a source collector file'
            Tags  = 'azure-scout; thisismydemo; testing; pipeline'
            Description = '<div><p>Every one of the 138 manifests carries SourceCollector pointing at its .ps1, and checks 6 and 7 in scripts/Test-ScoutCollectorDefinition.ps1 require that file to exist and regenerate byte-identically. Deleting the collectors turns 138 definitions into 138 CI violations.</p><p>In scope: replacing the regeneration check with something that survives deletion -- a content hash recorded at conversion time, or retiring the check once the definition is the source of truth. Out of scope: weakening the other five checks.</p></div>'
            AcceptanceCriteria = @(
                'scripts/Test-ScoutCollectorDefinition.ps1 exits 0 over all definitions with no collector .ps1 present.'
                'tests/CollectorDefinitionSchema.Tests.ps1 still fails the build on a hand-edited definition.'
                'No manifest key requires a path under Modules/ to exist.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 2 -- the tooling is wrong; fix it before planning against its output.
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-tooling'; Type = 'Feature'; Parent = 'epic'; Priority = 2
            Title = 'Correct the collector classification and conversion tooling'
            Tags  = 'azure-scout; thisismydemo; powershell; audit'
            Description = '<div><p>scripts/Invoke-CollectorAudit.ps1 classifies collectors with a regex that produces errors in both directions. It matches our own pure helpers Get-AZSCSafeProperty, Get-AZSCIdSegment and Get-AZSCCollectedValue as live Azure calls, and it misses Search-AzGraph entirely while never looking for New-Object -Com. Its 115 pure-shaping / 61 escape-hatch split is therefore not a safe planning basis.</p><p>Why now: the rest of the epic is planned against this classification. The converter has related gaps -- it will not descend through a conditional to find the row-emitting level, and it lifts live calls verbatim into a definition preamble rather than refusing.</p><p>In scope: the classifier, the converter descent, and the fixture generator gaps. Out of scope: converting collectors.</p></div>'
            AcceptanceCriteria = @(
                'A test asserts the classifier detects Search-AzGraph and New-Object -Com as live access.'
                'A test asserts the classifier does not report Get-AZSCSafeProperty, Get-AZSCIdSegment or Get-AZSCCollectedValue as live access.'
                'The converter refuses to emit a definition containing a live call rather than lifting it into a preamble.'
            )
        }
        @{
            Key = 's-classifier'; Type = 'User Story'; Parent = 'f-tooling'; Priority = 2
            Title = 'Correct the audit classifier in both directions'
            Tags  = 'azure-scout; thisismydemo; audit'
            Description = '<div><p>Replace the name-prefix regex with an AST check that distinguishes real external access from in-process helpers, and regenerate the audit.</p><p>In scope: the classifier, its committed output, and tests pinning both failure directions. Out of scope: acting on the corrected classification.</p></div>'
            AcceptanceCriteria = @(
                'The classifier decides on CommandAst command names, with an explicit allow-list for the three in-process Get-AZSC helpers.'
                'docs/design/collector-audit.md and tests/fixtures/collector-audit.json are regenerated and their totals reconcile to 176.'
                'Management/AllSubscriptions is reported as live access on the evidence of Search-AzGraph, and Monitor/Outages on the evidence of New-Object -Com.'
            )
        }
        @{
            Key = 's-descent'; Type = 'User Story'; Parent = 'f-tooling'; Priority = 2
            Title = 'Teach the converter to descend through a conditional row loop'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Management/AdvisorScore has one row site, no conditional shape and no live call. It fails conversion only because its row loop opens with an if and then fans out over a nested foreach, and the converter does not look through the if for the row-emitting level. Both constructs are already expressible as AdditionalFilter and AdditionalRowLoops.</p><p>In scope: converter descent, and refusing rather than lifting live calls. Out of scope: schema changes.</p></div>'
            AcceptanceCriteria = @(
                'The converter produces a definition for Management/AdvisorScore that passes the equivalence gate.'
                'Running the converter over the 38 unconverted collectors produces no definition containing a live call.'
                'A test asserts the converter exits non-zero when asked to convert a collector whose row loop makes a live call.'
            )
        }
        @{
            Key = 's-fixgen'; Type = 'User Story'; Parent = 'f-tooling'; Priority = 3
            Title = 'Close the four fixture generator gaps that leave joins unexercised'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = '<div><p>Nine converted join collectors are proven equivalent only in their not-found state, because the generated estate never satisfies the join predicate. The nine are four generator gaps, not nine problems: reverse-direction joins, predicates expressed as accessor calls, correlation values that are not properties of the primary, and array-valued or secondary-filtered partners.</p><p>In scope: scripts/New-ScoutCollectorFixture.ps1. Out of scope: changing any collector or definition.</p></div>'
            AcceptanceCriteria = @(
                'The JoinNotExercised list in tests/DeclarativeCollectorCoverage.Tests.ps1 is empty.'
                'The staleness assertion on that list still passes, so the list can only shorten.'
                'Removing the join partners from the estate changes the emitted output for all nine.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 3 -- move live access out of the row loop. This is the bulk of the work.
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-prefetch'; Type = 'Feature'; Parent = 'epic'; Priority = 2
            Title = 'Move live data access out of collector row loops into the collect phase'
            Tags  = 'azure-scout; thisismydemo; powershell; perf'
            Description = '<div><p>Thirty-two of the 38 unconverted collectors call Azure inside their row loop. A definition can only shape data the pipeline already holds, so these cannot be expressed until the calls move. The pattern already exists in the repo: Get-ScoutVmSkuDetails and Get-ScoutVmQuotas inject synthetic rows typed AZSC/VM/SKU and AZSC/VM/Quotas, and Compute/VirtualMachine consumes them as ordinary resource types.</p><p>Why now: this is the precondition for emptying the collector folder, and it is also a determinism win -- per-resource REST calls during Processing are exactly what AB#5649 removed from the rest of the engine.</p><p>In scope: prefetch functions in src/collect for each data-access cluster. Out of scope: writing the definitions themselves.</p></div>'
            AcceptanceCriteria = @(
                'No collector under Modules/Public/InventoryModules makes a call matching the corrected classifier.'
                'Each prefetch emits synthetic rows discoverable by resource type, with a test asserting shape and parent linkage.'
                'A live tenant run produces the same worksheet row counts as the v2.11.0 baseline for every affected collector.'
            )
        }
        @{
            Key = 's-armchild'; Type = 'User Story'; Parent = 'f-prefetch'; Priority = 2
            Title = 'Prefetch ARM child collections for the fourteen fan-out collectors'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Fourteen collectors share one structure: filter the parent type, then issue one ARM GET per parent against a child collection and shape the returned value array. They are the largest single cluster and the most mechanical. MLDatasets and MLModels issue a second GET per child; MLEndpoints iterates two endpoint types; SearchIndexes also calls listQueryKeys.</p><p>In scope: prefetch functions grouped by resource provider, emitting AZSC child rows carrying the parent id. Out of scope: schema changes -- this cluster needs none.</p></div>'
            AcceptanceCriteria = @(
                'A prefetch exists per resource provider covering all fourteen collectors.'
                'Each emits rows carrying the parent resource id, verified by a test against a recorded payload.'
                'None of the fourteen collectors contains an Invoke-AzRestMethod call.'
            )
        }
        @{
            Key = 't-arm-ml'; Type = 'Task'; Parent = 's-armchild'; Priority = 2
            Title = 'Prefetch the machine learning child collections'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Covers MLComputes, MLDatasets, MLDatastores, MLEndpoints, MLModels and MLPipelines, including the second per-child version GET that Datasets and Models issue and the two endpoint types Endpoints iterates.</p></div>'
        }
        @{
            Key = 't-arm-obs'; Type = 'Task'; Parent = 's-armchild'; Priority = 2
            Title = 'Prefetch the App Insights and Log Analytics child collections'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Covers AppInsightsContinuousExport, AppInsightsProactiveDetection, AppInsightsWorkItems, LAWorkspaceLinkedServices and LAWorkspaceSavedSearches.</p></div>'
        }
        @{
            Key = 't-arm-rest'; Type = 'Task'; Parent = 's-armchild'; Priority = 2
            Title = 'Prefetch the OpenAI, Search and AVD child collections'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Covers OpenAIDeployments, SearchIndexes including its listQueryKeys call, and AVDApplications.</p></div>'
        }
        @{
            Key = 's-subsweep'; Type = 'User Story'; Parent = 'f-prefetch'; Priority = 2
            Title = 'Prefetch the per-subscription security and policy sweeps'
            Tags  = 'azure-scout; thisismydemo; security'
            Description = '<div><p>Six collectors share the identical skeleton of a foreach over subscriptions calling an Az cmdlet, and none filters the resource set at all. One prefetch covers all six. Management/PolicyComplianceStates needs particular care: it mutates ambient subscription context mid-processing with Set-AzContext, and Invoke-AZSCInSubscriptionContext already exists to do that safely.</p><p>In scope: a single per-subscription sweep emitting security, diagnostic-setting and policy-state rows. Out of scope: changing what the cmdlets return.</p></div>'
            AcceptanceCriteria = @(
                'One prefetch covers DefenderAlerts, DefenderAssessments, DefenderPricing, DefenderSecureScore, SubscriptionDiagnosticSettings and PolicyComplianceStates.'
                'No collector calls Set-AzContext; subscription scoping goes through Invoke-AZSCInSubscriptionContext.'
                'A live run confirms the ambient subscription context is unchanged after the sweep.'
            )
        }
        @{
            Key = 's-tenantwide'; Type = 'User Story'; Parent = 'f-prefetch'; Priority = 3
            Title = 'Wire the tenant-scoped policy and role prefetches that already exist'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>PolicyDefinitions, PolicySetDefinitions and CustomRoleDefinitions each make one tenant-wide call, and src/collect/Get-ScoutApiResources.ps1 already collects the first two. For three of these four only the wiring is missing. ManagementGroups is the hard one: it defines a recursive local function that flattens the group tree with depth and parent path, which a definition would have to consume pre-flattened.</p><p>In scope: wiring the existing prefetches and materialising the flattened management-group tree. Out of scope: the management-group permission gap, which is an environment concern.</p></div>'
            AcceptanceCriteria = @(
                'PolicyDefinitions, PolicySetDefinitions and CustomRoleDefinitions consume prefetched rows and make no live call.'
                'The management group hierarchy is materialised as flattened rows carrying depth and parent path.'
                'A tenant without management group read access produces zero rows rather than a failure.'
            )
        }
        @{
            Key = 's-smallclusters'; Type = 'User Story'; Parent = 'f-prefetch'; Priority = 3
            Title = 'Prefetch storage service properties and strip outage markup off COM'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Two single-collector clusters. Storage/StorageAccounts calls Get-AzStorageBlobServiceProperty and Get-AzStorageFileServiceProperty once per account for soft-delete, versioning and retention columns, with no ARG equivalent. Monitor/Outages builds a COM HTMLFile object per row purely to strip markup from a Service Health description -- a Windows-only text transform, not a data-access problem.</p><p>In scope: a service-properties prefetch, and moving markup stripping into the collect phase without COM. Out of scope: changing which columns either collector emits.</p></div>'
            AcceptanceCriteria = @(
                'Storage/StorageAccounts contains no Get-AzStorage call and its soft-delete, versioning and retention columns still populate.'
                'No file under src/ or Modules/ constructs a COM object.'
                'Outage descriptions arrive pre-stripped and match the previous output for a recorded payload.'
            )
        }
        @{
            Key = 's-opdata'; Type = 'User Story'; Parent = 'f-prefetch'; Priority = 3
            Title = 'Prefetch per-resource operational telemetry for the four heavy collectors'
            Tags  = 'azure-scout; thisismydemo; powershell; perf'
            Description = '<div><p>VirtualMachine, VMOperationalData, ARCServers and ArcServerOperationalData each make heterogeneous per-resource calls -- insights metrics with a time window, a Cost Management query with a POST body, patch assessment, policy state queries and recovery vault walks. VirtualMachine alone makes six distinct REST calls inside its row loop. Unlike the ARM child cluster these do not share a shape, so each is its own design decision.</p><p>In scope: prefetching each telemetry source. Out of scope: changing the aggregation or time windows currently used.</p></div>'
            AcceptanceCriteria = @(
                'None of the four collectors contains an Invoke-AzRestMethod call.'
                'Each telemetry source has a prefetch with a test driven from a recorded payload.'
                'A live run reproduces the same metric, cost and patch columns as the v2.11.0 baseline.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 4 -- express the remainder as definitions.
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-convert'; Type = 'Feature'; Parent = 'epic'; Priority = 2
            Title = 'Express every remaining collector as a declarative definition'
            Tags  = 'azure-scout; thisismydemo; powershell; module-enhancement'
            Description = '<div><p>Once live access has moved to the collect phase, the remaining collectors become shaping problems. Three need a genuine schema addition for optional-child joins; three are one-off structures; two are dead and should be deleted rather than converted.</p><p>Why now: this is the step that empties Modules/Public/InventoryModules and makes deleting the fork possible.</p><p>In scope: conversion, the schema addition, and the two deletions. Out of scope: reporting, which is a separate feature.</p></div>'
            AcceptanceCriteria = @(
                'Get-ChildItem manifests/collectors -Recurse -Filter *.psd1 returns 174 files.'
                'Get-ChildItem Modules/Public/InventoryModules -Recurse -Filter *.ps1 returns 0 files.'
                'The UnconvertedPure and UnconvertedJoins lists in tests/DeclarativeCollectorCoverage.Tests.ps1 are both empty.'
            )
        }
        @{
            Key = 's-conv14'; Type = 'User Story'; Parent = 'f-convert'; Priority = 2
            Title = 'Convert the fourteen ARM child collection collectors'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>With their child collections prefetched, all fourteen reduce to a single-type filter with a parent join. No schema change is required.</p><p>In scope: fourteen definitions and their equivalence coverage. Out of scope: the prefetch itself.</p></div>'
            AcceptanceCriteria = @(
                'All fourteen have a definition passing the equivalence gate with the join exercised, not merely the not-found branch.'
                'None of the fourteen .ps1 files remains.'
                'A live run produces the same row counts for all fourteen worksheets as the v2.11.0 baseline.'
            )
        }
        @{
            Key = 's-rowvariants'; Type = 'User Story'; Parent = 'f-convert'; Priority = 2
            Title = 'Add row variants for optional child joins'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>PublicIP, VirtualWAN and AutomationAccounts each have two row sites at different loop depths. All three are the same construct: an optional-child left outer join where the differing fields are a child-derived expression in one branch and literal null in the other, and the row count itself is conditional.</p><p>A flag that runs the loop body once with a null loop variable is not faithful -- PublicIP calls .split() on the child value, which throws on null -- and making it work would mean rewriting the lifted expression, breaking the verbatim-source guarantee the whole equivalence proof rests on. An ordered list of variants, each carrying its own verbatim fields and loop nest, preserves that guarantee.</p><p>In scope: the schema addition, interpreter support, CI validation and the three conversions. Out of scope: the other 35 collectors.</p></div>'
            AcceptanceCriteria = @(
                'The schema supports an ordered list of row variants, each with its own condition, loop nest and verbatim field list.'
                'A definition whose variants are unsatisfiable fails at load time rather than silently emitting no rows.'
                'PublicIP, VirtualWAN and AutomationAccounts pass the equivalence gate with both branches exercised.'
            )
        }
        @{
            Key = 's-oneoffs'; Type = 'User Story'; Parent = 'f-convert'; Priority = 3
            Title = 'Convert the three collectors with unique row sources'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>AdvisorScore needs only the converter descent fix. AVDAzureLocal iterates a set synthesised from three filtered sets with added members and hand-built objects, so no resource type exists to declare. AllSubscriptions iterates the subscription list rather than the resource set and additionally runs a live Resource Graph query for the management-group ancestor chain.</p><p>In scope: materialising the synthesised row sets in the collect phase so each has a declarable type. Out of scope: changing emitted columns.</p></div>'
            AcceptanceCriteria = @(
                'All three have definitions passing the equivalence gate.'
                'Management/AllSubscriptions contains no Search-AzGraph call.'
                'The AVD session host row set is materialised in the collect phase with a declarable resource type.'
            )
        }
        @{
            Key = 's-deletedead'; Type = 'User Story'; Parent = 'f-convert'; Priority = 3
            Title = 'Delete the two collectors written against a contract that never existed'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Identity/IdentityProviders and Identity/SecurityDefaults consist of a single call to Register-AZSCInventoryModule, which resolves as missing inside the module and exists only as a mock in tests/Identity.Module.Tests.ps1. Neither has ever produced a row. Both the processing path and the reporting path carry special cases naming them to avoid crashing.</p><p>In scope: deleting both files and both special cases. Out of scope: reimplementing the capability, which nobody has asked for.</p></div>'
            AcceptanceCriteria = @(
                'Neither file exists and no file under src/ or Modules/ contains the string Register-AZSCInventoryModule.'
                'Get-ScoutCollector no longer emits an Unsupported contract and Start-AZSCExcelJob carries no special case for them.'
                'The collector total is 174 and every one has a definition.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 5 -- reporting is 0% cut over, not "a duplicate discovery".
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-reporting'; Type = 'Feature'; Parent = 'epic'; Priority = 2
            Title = 'Route report rendering through the collector definitions'
            Tags  = 'azure-scout; thisismydemo; reporting; powershell'
            Description = '<div><p>Invoke-ScoutCollector has no Reporting branch at all -- it is processing-only. Invoke-ScoutDeclarativeReporting is therefore reachable only from tests, and the Export section of all 138 manifests is dead code on the live path. Meanwhile Start-AZSCExcelJob discovers the collector tree itself with unsorted Get-ChildItem calls, re-derives the unsupported contract by regex, ignores the category filter entirely, and executes each collector by building a script block from file text.</p><p>Why now: reporting is the reason converting 138 collectors did not shrink Modules/. Four further exporters index the same tree by name and break the instant it is deleted.</p><p>In scope: a reporting branch on the shared collector entry point, retiring the duplicate discovery and script execution, and re-pointing the four exporters. Out of scope: changing workbook appearance.</p></div>'
            AcceptanceCriteria = @(
                'No file under src/ contains the literal string InventoryModules.'
                'A workbook built through the definition Export path is worksheet-for-worksheet and cell-for-cell identical to one built through the current path.'
                'Passing a category filter narrows the reported worksheets as well as the processed ones.'
            )
        }
        @{
            Key = 's-repbranch'; Type = 'User Story'; Parent = 'f-reporting'; Priority = 2
            Title = 'Add a reporting branch to the shared collector entry point'
            Tags  = 'azure-scout; thisismydemo; reporting'
            Description = '<div><p>Give Invoke-ScoutCollector a Reporting task alongside Processing, dispatching to the declarative reporting path for collectors with a definition, so the Export blocks become live code.</p><p>In scope: the dispatch and its tests. Out of scope: retiring the old path, which follows.</p></div>'
            AcceptanceCriteria = @(
                'Invoke-ScoutCollector accepts and dispatches a Reporting task.'
                'A test proves the definition Export path is what runs, by pairing a definition with a collector that throws on sight.'
                'Worksheet order is deterministic and matches the processing order.'
            )
        }
        @{
            Key = 's-repretire'; Type = 'User Story'; Parent = 'f-reporting'; Priority = 2
            Title = 'Retire the duplicate discovery and script execution in the Excel job'
            Tags  = 'azure-scout; thisismydemo; reporting'
            Description = '<div><p>Start-AZSCExcelJob walks the collector tree with two unsorted Get-ChildItem calls, re-derives the unsupported contract with a regex that has already drifted from its counterpart once and reached a live run, and executes collectors via a script block built from file text. It also reads a tag switch that is not one of its parameters and is not passed by its caller, resolving only by dynamic scoping.</p><p>In scope: removing the discovery and execution, and threading the tag switch as a declared parameter. Out of scope: the four name-index exporters.</p></div>'
            AcceptanceCriteria = @(
                'Start-AZSCExcelJob contains no Get-ChildItem and no script block construction.'
                'The tag switch is a declared parameter threaded from the reporting orchestrator, and a live run confirms tag columns reach the workbook.'
                'The printed supported-resource-type count is derived from the definitions rather than a file count.'
            )
        }
        @{
            Key = 's-exporters'; Type = 'User Story'; Parent = 'f-reporting'; Priority = 3
            Title = 'Re-point the four exporters off the collector tree'
            Tags  = 'azure-scout; thisismydemo; reporting'
            Description = '<div><p>The AsciiDoc, JSON, Markdown and Power BI exporters each walk the collector folders to build a name index mapping folder to section and file base name to cache key. They do not execute collectors, but all four break the moment the tree is deleted, and all four hard-code the same fragile four-level parent walk-up.</p><p>In scope: sourcing the index from the definitions and removing the walk-ups. Out of scope: changing the output formats.</p></div>'
            AcceptanceCriteria = @(
                'None of the four exporters references the collector tree or performs a parent walk-up to find it.'
                'Each exporter produces byte-identical output to the v2.11.0 baseline for the same report cache.'
                'A test asserts all four still emit every section after the collector tree is removed.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 6 -- StrictMode. All 20 sites are live.
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-strict'; Type = 'Feature'; Parent = 'epic'; Priority = 3
            Title = 'Run every module scope under strict mode'
            Tags  = 'azure-scout; thisismydemo; powershell; resilience'
            Description = '<div><p>The guard reports 20 weakening sites across 19 files and classifies 15 of them as dead. They are not: every one is reachable from Invoke-AzureScout. The three orchestrators and the extra-jobs entry are called directly, the four job wrappers are called from extra jobs, and the entire seven-file diagram subtree runs by default because the skip switch is an opt-out.</p><p>Why now: the epic criterion is strict mode in every module scope, and the allow-list currently misrepresents which sites are live, so nobody can plan against it.</p><p>In scope: correcting the allow-list, making its state field verifiable, and removing the sites. Out of scope: rewriting the diagram builder beyond what strict mode requires.</p></div>'
            AcceptanceCriteria = @(
                'pwsh -File scripts/Test-StrictModeGuard.ps1 reports 0 weakening sites and an empty allow-list.'
                'A full live inventory run with diagrams enabled completes with strict mode active throughout.'
                'tests/StrictModeGuard.Tests.ps1 derives each site state from call-graph reachability rather than a hand-maintained string.'
            )
        }
        @{
            Key = 's-allowlist'; Type = 'User Story'; Parent = 'f-strict'; Priority = 3
            Title = 'Correct the strict mode allow-list to reflect real reachability'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = '<div><p>The allow-list justifies fifteen entries as belonging to a deleted background-job engine. The job wrappers were deleted; the functions themselves were rewired to run in-process and are on the hot path. Marking them dead hides fifteen live sites.</p><p>In scope: correcting every state field and deriving it mechanically. Out of scope: removing the sites, which follows.</p></div>'
            AcceptanceCriteria = @(
                'Every allow-list entry records a state derived from call-graph reachability, not a hand-written string.'
                'A test fails if an entry claims dead while a path from Invoke-AzureScout reaches it.'
                'The guard output states 20 live sites.'
            )
        }
        @{
            Key = 's-strictfix'; Type = 'User Story'; Parent = 'f-strict'; Priority = 3
            Title = 'Remove the strict mode weakening sites'
            Tags  = 'azure-scout; thisismydemo; resilience'
            Description = '<div><p>Each site needs the code beneath it to survive strict mode before the opt-out can go. The collector dispatch site is already flagged as ready to lift on the evidence of the collector strict-mode harness.</p><p>In scope: the orchestrators, the extra-jobs path, the four job wrappers, the seven diagram files and the interpreter sites. Out of scope: behaviour changes beyond what strict mode forces.</p></div>'
            AcceptanceCriteria = @(
                'No file under src/ or Modules/ weakens strict mode.'
                'A live run with diagrams enabled produces a diagram file of the same size class as the v2.11.0 baseline.'
                'The full test suite passes with no strict mode opt-out present.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 7 -- relocate what survives, then delete the fork.
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-relocate'; Type = 'Feature'; Parent = 'epic'; Priority = 2
            Title = 'Relocate the surviving module code and delete the fork'
            Tags  = 'azure-scout; thisismydemo; powershell; breaking'
            Description = '<div><p>Beyond the collectors, Modules/ holds 45 .ps1 files defining 61 functions. None is dead and none is a shim. Four of them are already duplicated in src/collect with both copies live -- the src versions serve the assessment path and the Modules versions the inventory path -- so those are a merge of diverged implementations rather than a move. Every one of the 45 also carries a stale file name that does not match the function it defines, and five test files assert on those names.</p><p>Why now: this is the step the epic is named for.</p><p>In scope: merging the duplicates, relocating the rest, inverting collector discovery onto the definitions, retiring the imperative fallback, and deleting the folder. Out of scope: refactoring beyond what relocation requires.</p></div>'
            AcceptanceCriteria = @(
                'Test-Path Modules returns False.'
                'After import, the exported function set matches the v2.11.0 list apart from deliberate removals.'
                'No file under src/ carries the legacy file name prefix.'
            )
        }
        @{
            Key = 's-mergedup'; Type = 'User Story'; Parent = 'f-relocate'; Priority = 2
            Title = 'Merge the four duplicated extraction implementations'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>API resources, cost inventory, VM quotas and VM SKU details each exist twice and both copies run -- one serving inventory, one serving assessment. One header records that its version was ported rather than wrapped, so the two have diverged.</p><p>In scope: reconciling each pair into a single implementation serving both paths, with the differences identified before either is deleted. Out of scope: changing what either path emits.</p></div>'
            AcceptanceCriteria = @(
                'Each of the four capabilities has exactly one implementation under src/.'
                'The differences between each pair are recorded before deletion, and a test pins the reconciled behaviour for both callers.'
                'A live run produces the same API, cost, quota and SKU rows as the v2.11.0 baseline for both inventory and assessment.'
            )
        }
        @{
            Key = 's-relocate'; Type = 'User Story'; Parent = 'f-relocate'; Priority = 3
            Title = 'Relocate the remaining non-collector files into src'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = '<div><p>Session, context, path and logging primitives, the three orchestrators, the extra-jobs path, the diagram subtree, the job wrappers and the public entry points. The module loader dot-sources two directories that will disappear, and five test files assert on file names that all need correcting during the move.</p><p>In scope: the move, the renames, the loader, CI paths and the guard scan roots. Out of scope: behaviour changes.</p></div>'
            AcceptanceCriteria = @(
                'The module manifest and loader reference no path under Modules.'
                'Continuous integration analyses the new paths and the strict mode guard scans them.'
                'The full test suite passes with every relocated file at its new name.'
            )
        }
        @{
            Key = 's-invertdisc'; Type = 'User Story'; Parent = 'f-relocate'; Priority = 3
            Title = 'Invert collector discovery onto the definition tree'
            Tags  = 'azure-scout; thisismydemo; pipeline'
            Description = '<div><p>Get-ScoutCollector discovers by walking the collector folders, reads a header comment for the category, derives a contract by regex and reports the presence of a definition as an additive fact. Once the definitions are the only collectors, that inverts: category comes from the manifest folder, the contract concept disappears because only one remains, and the inventory root ceases to exist as a parameter.</p><p>In scope: the signature change and every caller and fixture that constructs a collector tree. Out of scope: changing discovery order, which must stay deterministic.</p></div>'
            AcceptanceCriteria = @(
                'Get-ScoutCollector takes no inventory root parameter and reports no contract.'
                'Discovery order is deterministic and a test pins it.'
                'Every test that built a fixture collector tree now builds a fixture definition tree.'
            )
        }
        @{
            Key = 's-killswitch'; Type = 'User Story'; Parent = 'f-relocate'; Priority = 3
            Title = 'Retire the imperative kill switch and fallback'
            Tags  = 'azure-scout; thisismydemo; pipeline'
            Description = '<div><p>The environment kill switch forces every collector back onto its .ps1, and a definition failing schema validation falls back to the collector beside it rather than losing a worksheet. Both become undefined once the collectors are gone, and the cutover test that proves routing by pairing a definition with a collector that throws stops working.</p><p>In scope: removing both, deciding what a schema validation failure does instead, and replacing the routing proof. Out of scope: weakening the CI schema gate, which is what makes removing the fallback safe.</p></div>'
            AcceptanceCriteria = @(
                'No code path references the kill switch and no fallback mode remains.'
                'A definition failing schema validation produces a documented, tested outcome rather than a silent substitution.'
                'The cutover test proves routing without relying on a collector file.'
            )
        }
        @{
            Key = 's-deletefork'; Type = 'User Story'; Parent = 'f-relocate'; Priority = 2
            Title = 'Delete the module tree and update everything that pointed at it'
            Tags  = 'azure-scout; thisismydemo; breaking'
            Description = '<div><p>Twenty-eight test files reference the collector tree, including the strict-mode harness that runs all 174 collectors and is itself the proof of strict-mode safety. Four repository scripts default to that tree, one of which feeds the collect type list and must be re-pointed rather than deleted. The user-visible supported-resource-type count is computed from a file count, and the category parameter help describes folder names under the tree.</p><p>In scope: the deletion and every dependent. Out of scope: anything already covered by the reporting or relocation stories.</p></div>'
            AcceptanceCriteria = @(
                'Test-Path Modules returns False and the full test suite passes.'
                'The resource-type map script reads the definitions, and an explicit decision is recorded for the converter and audit scripts.'
                'The printed supported-resource-type count and the category parameter help both describe the definitions.'
            )
        }

        #-------------------------------------------------------------------------------------
        # FEATURE 8 -- the breaking change and the release.
        #-------------------------------------------------------------------------------------
        @{
            Key = 'f-release'; Type = 'Feature'; Parent = 'epic'; Priority = 2
            Title = 'Remove the deprecated assessment entry point and release version three'
            Tags  = 'azure-scout; thisismydemo; breaking; delivery'
            Description = '<div><p>Invoke-ScoutAssessment was deprecated in v2.4.0 for removal in v3.0.0 and is still exported. This is the removal of a public name rather than of an implementation -- the unified entry point routes straight into it, so the work is dropping the export, renaming the internal function, updating five internal call sites and fixing a published pipeline example that would otherwise break for users.</p><p>Why now: it is the documented breaking change that justifies the major version, and it must land in the same release as the fork deletion.</p><p>In scope: the removal, the test temp isolation, and the release itself. Out of scope: any further deprecation.</p></div>'
            AcceptanceCriteria = @(
                'The exported function list does not contain the deprecated name and a test asserts calling it throws a command-not-found error.'
                'The published pipeline example and all current documentation use the unified entry point.'
                'Version three is tagged, published to the gallery, installed from the gallery, and its release notes state what changed.'
            )
        }
        @{
            Key = 's-removedep'; Type = 'User Story'; Parent = 'f-release'; Priority = 2
            Title = 'Remove the deprecated assessment entry point'
            Tags  = 'azure-scout; thisismydemo; breaking'
            Description = '<div><p>Twenty-eight files reference the name: eight code files including two live internal calls in the unified entry point and three in the pipeline, six test files, ten documentation pages, and a published pipeline example that is user-facing breakage if missed. Four historical files record it and must not be rewritten.</p><p>In scope: the removal and the twenty-four files that must change. Out of scope: the changelog, releases ledger and handoff, which are historical record.</p></div>'
            AcceptanceCriteria = @(
                'The name appears in no source, test, pipeline or current documentation file.'
                'The four historical files still record it unchanged.'
                'A test asserts the removed name throws a command-not-found error.'
            )
        }
        @{
            Key = 's-tempiso'; Type = 'User Story'; Parent = 'f-release'; Priority = 4
            Title = 'Isolate test temporary directories per run'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = '<div><p>Seventeen test files use a fixed temporary directory. The names are distinct from each other, so they do not collide across files, but two concurrent runs of the same file collide, and state survives between runs because a fixed path is not removed on failure. Two test files already solve this with a per-run identifier and document the pattern.</p><p>In scope: the seventeen files. Out of scope: changing what any test asserts.</p></div>'
            AcceptanceCriteria = @(
                'No test file joins a constant literal to the temporary directory path.'
                'An assertion enforces that every temporary path in the test tree includes a per-run identifier.'
                'Two concurrent full suite runs on one machine both pass.'
            )
        }
        @{
            Key = 's-ship3'; Type = 'User Story'; Parent = 'f-release'; Priority = 2
            Title = 'Release version three'
            Tags  = 'azure-scout; thisismydemo; delivery; docs'
            Description = '<div><p>Cut the release once the fork is gone: version bump, the four version-pinned documents, tag, gallery publish, install verification and a live tenant run. The gallery listing for v2.11.0 still carries release notes claiming the previous epic completed, so the notes for this release must be accurate about what shipped and what did not.</p><p>In scope: the release and its documentation. Out of scope: reopening any earlier release entry.</p></div>'
            AcceptanceCriteria = @(
                'The version sync test passes and the manifest, changelog, roadmap and releases ledger all name version three.'
                'The module installs from the gallery and imports at version three in a clean session.'
                'A live tenant run completes with zero collector failures and the run log reports every collector as declarative.'
            )
        }
    )
}
