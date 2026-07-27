@{
    # Tasks for the stories under Feature AB#5937 (express every remaining collector as a
    # definition) and Feature AB#5942 (route report rendering through the definitions),
    # Epic AB#5917.
    #
    # The fourteen ARM child-collection collectors, the two Unsupported-contract files and the
    # per-file line references below were read from the working tree, not taken from the story
    # text.

    Tree = @(

        #-------------------------------------------------------------------------------------
        # AB#5938 -- Convert the fourteen ARM child collection collectors
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-conv-ml'; Type = 'Task'; ParentId = 5938; Priority = 2
            Title = 'Convert the six machine learning child collection collectors'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>With their child collections prefetched by AB#5929, AI/MLComputes, AI/MLDatasets, AI/MLDatastores, AI/MLEndpoints, AI/MLModels and AI/MLPipelines reduce to a single-type filter plus a join on the parent id. No schema change is needed; run scripts/ConvertTo-ScoutCollectorDefinition.ps1 against each and validate.</p>
<p>Two of them fan out further than the rest and will show it in the definition: MLDatasets and MLModels issue a second GET per child for the version, and MLEndpoints iterates two endpoint types. If the prefetch flattens those into one row type the conversion is ordinary; if it does not, that is a finding to take back to AB#5929 rather than something to work around in the definition.</p>
<p>Prove the join actually fires. Nine collectors currently pass equivalence while both paths take the not-found branch and every joined column is null on both sides -- that is the failure mode tests/DeclarativeCollectorCoverage.Tests.ps1 pins by name in JoinNotExercised, and it is why the acceptance criterion for this story says the join must be exercised rather than merely present.</p>
<p>Why now: it is the largest and most mechanical block of the conversion, and it is unblocked the moment the ML prefetch lands.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Six definitions under manifests/collectors/AI, each passing scripts/Test-ScoutCollectorDefinition.ps1.</li>
<li>Equivalence coverage with the parent join demonstrably exercised, not merely present.</li>
<li>Removal of the six .ps1 files once their golden sets from AB#5919 are recorded.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The prefetch itself, which is AB#5929.</li>
</ul>
'@
        }
        @{
            Key = 't-conv-obs'; Type = 'Task'; ParentId = 5938; Priority = 2
            Title = 'Convert the five App Insights and Log Analytics child collection collectors'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Monitor/AppInsightsContinuousExport, Monitor/AppInsightsProactiveDetection, Monitor/AppInsightsWorkItems, Monitor/LAWorkspaceLinkedServices and Monitor/LAWorkspaceSavedSearches each issue one ARM GET per parent against a child collection and shape the returned value array. With AB#5930's prefetch in place all five are a single-type filter plus a parent join.</p>
<p>Watch the parent type: three of these hang off microsoft.insights/components and two off microsoft.operationalinsights/workspaces, so they are two join shapes rather than one, and a fixture that only populates one parent type will leave the other five joins unexercised without failing.</p>
<p>Why now: it is independent of the ML block and of the OpenAI/Search/AVD block, so all three can proceed in parallel once their prefetches land.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Five definitions under manifests/collectors/Monitor, each passing the definition validator.</li>
<li>Equivalence coverage with both parent types populated and both joins exercised.</li>
<li>Removal of the five .ps1 files once their golden sets are recorded.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Monitor/SubscriptionDiagnosticSettings and Monitor/Outages, which are different clusters.</li>
</ul>
'@
        }
        @{
            Key = 't-conv-rest'; Type = 'Task'; ParentId = 5938; Priority = 2
            Title = 'Convert the OpenAI, Search and AVD application collectors'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>AI/OpenAIDeployments, AI/SearchIndexes and Compute/AVDApplications complete the fourteen. SearchIndexes is the one with an extra wrinkle: besides the child collection it also calls listQueryKeys, so its prefetch under AB#5931 emits two row sets and the definition joins both.</p>
<p>Once these three land, no collector in the fourteen contains an Invoke-AzRestMethod call, which is this story's checkable criterion.</p>
<p>Why now: it is the last block of the fourteen, and finishing it is what lets the collector count start dropping.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Three definitions, each passing the definition validator.</li>
<li>Both SearchIndexes row sets joined and exercised.</li>
<li>An assertion that none of the fourteen files contains Invoke-AzRestMethod.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The prefetch itself, which is AB#5931.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5939 -- Add row variants for optional child joins
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-rv-schema'; Type = 'Task'; ParentId = 5939; Priority = 2
            Title = 'Add an ordered row variant list to the collector definition schema'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Three collectors have two $obj sites at DIFFERENT loop depths, taken from the working tree:</p>
<ul>
<li>Networking/PublicIP.ps1 -- $obj at line 70 inside if ($null -ne $data.ipConfiguration.id) { foreach ($Tag in $Tags) }, and at line 96 in the else branch's own foreach ($Tag in $Tags). Same depth here, different guard.</li>
<li>Networking/VirtualWAN.ps1 -- $obj at line 71 nested foreach ($2 in $vhub) / foreach ($3 in $vpn) / foreach ($Tag in $Tags), and at line 108 nested only foreach ($2 in $vhub) / foreach ($Tag in $Tags). One loop level shallower.</li>
<li>Management/AutomationAccounts.ps1 -- $obj at line 76 inside foreach ($1 in $rbs) / foreach ($Tag in $Tags), and at line 103 inside foreach ($Tag in $Tags) alone.</li>
</ul>
<p>All three are the same construct: an optional-child left outer join where the row COUNT is conditional and the differing fields are a child-derived expression in one branch against literal $null in the other.</p>
<p>The naive fix -- one field list plus a flag that runs the loop body once with a null loop variable -- is not faithful, and PublicIP proves it: its branch computes 'Associated Resource' = $data.ipConfiguration.id.split('/')[8] and 'Associated Resource Type' = ...split('/')[7]. Calling .split() on $null throws. Making it work would mean rewriting the lifted expression, which breaks the verbatim-source guarantee the whole equivalence proof rests on.</p>
<p>Model it instead as an ordered list of variants, each carrying its own condition, its own loop nest and its own verbatim field list. Nothing is rewritten; the interpreter picks the first satisfied variant.</p>
<p>Why now: it is the last genuine schema gap, and three collectors cannot convert without it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The schema key, its loader validation, and interpreter support in src/pipeline/Invoke-ScoutDeclarativeCollector.ps1.</li>
<li>Fields staying verbatim -- no expression is rewritten to tolerate a null.</li>
<li>Converter support so the three definitions are generated rather than hand-written.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The conversions themselves, which follow.</li>
<li>The other unconverted collectors.</li>
</ul>
'@
        }
        @{
            Key = 't-rv-validate'; Type = 'Task'; ParentId = 5939; Priority = 2
            Title = 'Fail a definition with unsatisfiable row variants at load time'
            Tags  = 'azure-scout; thisismydemo; pipeline; testing'
            Description = @'
<p>A variant list whose conditions can never be satisfied emits no rows, and an empty worksheet is the specific failure this codebase keeps shipping -- the Security sheet was empty in every release until AB#5649 found it, and a definition that had drifted from its collector stayed green for a whole release. Silence must be a load-time failure, not a runtime outcome.</p>
<p>Add it as a check in scripts/Test-ScoutCollectorDefinition.ps1 alongside the existing seven, so it annotates the offending definition in the pull-request diff rather than surfacing as a missing worksheet on someone's run.</p>
<p>Follow the established proof style for that gate: the thirteen existing tests each write one deliberately broken definition and assert both a non-zero exit AND that the message names the fault, after first asserting a correct definition passes so the failure assertions are not vacuous. Do the same here.</p>
<p>Why now: adding a schema feature without its gate check is how the previous schema keys would have rotted; SetupPreamble and SetupVariables each got one at the time they were added.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A validator check for unsatisfiable, unreachable and overlapping-with-no-default variant lists.</li>
<li>A deliberately broken definition per failure mode, asserting exit code and message.</li>
<li>A positive control asserting a correct variant definition passes.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Relaxing any of the seven existing checks.</li>
</ul>
'@
        }
        @{
            Key = 't-rv-convert3'; Type = 'Task'; ParentId = 5939; Priority = 2
            Title = 'Convert PublicIP, VirtualWAN and AutomationAccounts onto row variants'
            Tags  = 'azure-scout; thisismydemo; powershell; testing'
            Description = @'
<p>Generate the three definitions with the extended converter and prove both branches of each. Equivalence passing on one branch is worth very little here: the whole reason these three need a schema addition is that the branches differ, so a fixture that only reaches the child-present branch tests nothing the existing schema could not already express.</p>
<p>Each needs a fixture estate carrying, for the same collector, at least one parent WITH the optional child and one WITHOUT. For PublicIP that is one address with $data.ipConfiguration.id set and one with it null; for VirtualWAN a hub with a vpn site and a hub without; for AutomationAccounts an account with runbooks and one with none.</p>
<p>Watch the $ResUCount 1 to 0 transition in every variant. It is the counter that makes the second and later tag rows report 0 rather than 1, it is copy-pasted into both branches of all three collectors, and getting it wrong changes a value in the report without changing the row count.</p>
<p>Why now: these three are the whole justification for the schema addition, so leaving them unconverted would mean shipping a schema feature with no user.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Three generated definitions passing the equivalence gate.</li>
<li>Fixture estates exercising both the child-present and child-absent branch for each.</li>
<li>An assertion pinning the $ResUCount transition in both branches.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what any of the three emits.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5940 -- Convert the three collectors with unique row sources
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-one-advisor'; Type = 'Task'; ParentId = 5940; Priority = 3
            Title = 'Convert AdvisorScore once the converter descends through its conditional'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Management/AdvisorScore.ps1 needs no schema change and no prefetch -- only the converter fix from AB#5924. Its row loop is nested inside a conditional: line 33 opens $tmp = foreach ($1 in $AdvisorScore), line 34 filters on if ($1.name -in ('Cost','OperationalExcellence','Performance','Security','HighAvailability','Advisor')), and the row-emitting foreach ($Serie in $Series.scoreHistory) with its $obj is at lines 46 and 52 inside that branch. Get-RowExpansion looks only for a foreach at each level, sees the if, and throws.</p>
<p>Once the descent lands, generate the definition and validate it like any other. This is the cheapest of the three one-offs and should go first, because it also confirms the descent fix works on the real collector rather than only on a synthetic AST.</p>
<p>Why now: it converts as soon as AB#5924 merges, with no other dependency.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A generated definition passing the equivalence gate, with the name filter preserved as a condition rather than lifted into the row set.</li>
<li>Fixture coverage for a score name inside the list and one outside it.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The converter change itself, which is AB#5924.</li>
</ul>
'@
        }
        @{
            Key = 't-one-avdlocal'; Type = 'Task'; ParentId = 5940; Priority = 3
            Title = 'Materialise the AVD Azure Local session host row set as a declarable type'
            Tags  = 'azure-scout; thisismydemo; powershell; infrastructure'
            Description = @'
<p>Compute/AVDAzureLocal.ps1 iterates a set it SYNTHESISES from three filtered sets -- microsoft.hybridcompute/machines, microsoft.azurestackhci/virtualmachineinstances and microsoft.desktopvirtualization/hostpools/sessionhosts -- adding members and hand-building objects as it goes. There is no resource type to declare, because the thing the row loop iterates does not exist in the estate.</p>
<p>Build that set in the collect phase instead and give it a type, e.g. AZSC/AVD/AzureLocalSessionHost, so the definition filters an actual type like every other collector. This is the same manoeuvre AB#5933 makes for the flattened management group tree, and the same one the AZSC/VM/SKU and AZSC/VM/Quotas rows already demonstrate.</p>
<p>Two things to preserve while moving it: the added members that the row expressions read, and the exact composition order of the three sets. Both are load-bearing and neither is stated anywhere but the code.</p>
<p>Why now: it is a synthesis problem rather than a prefetch problem, so it does not resolve as a side effect of any other story.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A collect-phase synthesis emitting the session host rows under a declarable type.</li>
<li>A definition consuming that type and passing the equivalence gate.</li>
<li>A test pinning the composition order and the added members.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Compute/AVD, which joins existing types and needs no synthesis.</li>
</ul>
'@
        }
        @{
            Key = 't-one-allsubs'; Type = 'Task'; ParentId = 5940; Priority = 3
            Title = 'Convert AllSubscriptions and move its ancestor chain query to the collect phase'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Management/AllSubscriptions.ps1 is unusual twice over. Its row loop iterates the SUBSCRIPTION list rather than the resource set, so there is no resource type behind the rows; and it runs a live Search-AzGraph query for each subscription's management-group ancestor chain, inside the collector.</p>
<p>The Search-AzGraph call is currently invisible to scripts/Invoke-CollectorAudit.ps1 -- the classifier matches command names by prefix and Search-Az matches none of them -- so this collector's real escape-hatch reason is not in the committed audit. AB#5923 makes it visible.</p>
<p>Two pieces of work: emit the subscription list as a declarable type so the row source is ordinary, and move the ancestor chain into the collect phase. If AB#5933 materialises the flattened management group hierarchy with depth and parent path, the ancestor chain may fall out of that data with no second query at all -- check before writing a new one.</p>
<p>Why now: it is the last of the three one-offs and the only one that still reaches Azure from inside a row loop.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The subscription list emitted as a declarable row type.</li>
<li>The ancestor chain sourced from the collect phase, reusing the management group prefetch if it suffices.</li>
<li>No Search-AzGraph call left in the collector.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing which subscription columns are emitted.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5941 -- Delete the two collectors written against a contract that never existed
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-dead-delete'; Type = 'Task'; ParentId = 5941; Priority = 3
            Title = 'Delete the two Identity collectors and their unsupported contract handling'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Identity/IdentityProviders.ps1 and Identity/SecurityDefaults.ps1 consist of a single call to Register-AZSCInventoryModule, an API that resolves as missing inside the module and exists only as a mock in tests/Identity.Module.Tests.ps1. Neither has ever produced a row in any release. A fresh audit run still records both as Contract = 'Unsupported', and scripts/Invoke-CollectorAudit.ps1 short-circuits on that contract with the reason recorded at its line 366.</p>
<p>Delete the files and the concept. src/pipeline/Get-ScoutCollector.ps1 derives Contract by regex from the file header (line 123: 'Standard' when the header matches param ($SCPath), otherwise unsupported); with these two gone there is only one contract, so the field itself becomes meaningless -- though removing it from the signature is AB#5952, not this Task.</p>
<p>Why now: converting them is impossible and keeping them means the collector total can never reach a number where every collector has a definition.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Deletion of both .ps1 files.</li>
<li>Removal of every reference to Register-AZSCInventoryModule under src/ and Modules/, including the mock in tests/Identity.Module.Tests.ps1.</li>
<li>The Unsupported branch removed from scripts/Invoke-CollectorAudit.ps1.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Reimplementing the capability, which nobody has asked for.</li>
<li>Removing Contract from Get-ScoutCollector's output, which is AB#5952.</li>
</ul>
'@
        }
        @{
            Key = 't-dead-specialcase'; Type = 'Task'; ParentId = 5941; Priority = 3
            Title = 'Remove the reporting special case that exists only for the two dead collectors'
            Tags  = 'azure-scout; thisismydemo; reporting'
            Description = @'
<p>The reporting path carries its own copy of the unsupported-contract logic so it does not crash on these two files. src/report/renderers/inventory/Start-AZSCExcelJob.ps1 re-derives it by regex at line 93: $Unsupported = $ModuleData -match '(?m)^\s*Register-AZSCInventoryModule', guarded at line 95 by $ModuleResourceCount -gt 0 -and -not $Unsupported, with a comment at line 84 naming the Identity files explicitly.</p>
<p>That is a second, independent implementation of a rule src/pipeline/Get-ScoutCollector.ps1 already applies -- and it has already drifted from its counterpart once and reached a live run. Delete it along with the collectors rather than leaving a regex matching a string that no longer appears anywhere.</p>
<p>Why now: it is the same change, and separating them leaves dead defensive code whose reason is gone and whose next reader will be afraid to remove it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The Register-AZSCInventoryModule regex and its guard removed from Start-AZSCExcelJob.ps1.</li>
<li>A test asserting no file under src/ or Modules/ contains the string Register-AZSCInventoryModule.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The duplicate DISCOVERY in the same file, which is AB#5944.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5943 -- Add a reporting branch to the shared collector entry point
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-rep-dispatch'; Type = 'Task'; ParentId = 5943; Priority = 2
            Title = 'Dispatch a reporting task through the shared collector entry point'
            Tags  = 'azure-scout; thisismydemo; reporting; pipeline'
            Description = @'
<p>src/pipeline/Invoke-ScoutCollector.ps1 is processing-only. Its declarative branch at line 151 routes on $HasDefinition and produces rows; there is no Reporting task. Meanwhile src/pipeline/Invoke-ScoutDeclarativeCollector.ps1 line 72 already forwards to Invoke-ScoutDeclarativeReporting (defined at line 293 of the same file) when the context task is Reporting -- and that call is reached only from tests. The Export section of all 138 manifests is therefore dead code on the live path.</p>
<p>Add the Reporting task to Invoke-ScoutCollector so a collector with a definition renders through its Export section, and one without falls to its .ps1 exactly as processing does today.</p>
<p>Mind the argument positions when the .ps1 branch is taken. The imperative path passes a positional argument list ($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, ...) and line 214 sets $Arguments[5] to the context Task. A comment at lines 195 to 204 records that this list was once shifted by one, $Task landed in $Retirements, the collectors' If ($Task -eq 'Processing') guard never fired, and every collector silently returned nothing. Reporting has the same hazard.</p>
<p>Why now: reporting being 0% cut over is the reason converting 138 collectors did not shrink Modules/ at all.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A Reporting task on Invoke-ScoutCollector routing on the same HasDefinition the processing branch uses.</li>
<li>Deterministic worksheet order, matching the processing order, pinned by a test.</li>
<li>An argument-position test for the imperative reporting fallback.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Retiring the old path in Start-AZSCExcelJob, which is AB#5944.</li>
</ul>
'@
        }
        @{
            Key = 't-rep-proof'; Type = 'Task'; ParentId = 5943; Priority = 2
            Title = 'Prove the definition export path is what actually renders'
            Tags  = 'azure-scout; thisismydemo; reporting; testing'
            Description = @'
<p>A cell comparison can never detect a routing regression, because both paths agree by construction -- that is precisely why v2.10.0's processing cutover was proved by impossibility instead. Reuse the technique here: pair a valid definition with a .ps1 whose entire Reporting branch is a throw, run the report, and assert the worksheet is present and correct. The throw makes it impossible for the old path to have produced the output.</p>
<p>tests/DeclarativeCollectorCutover.Tests.ps1 is the existing example and the file to model on; it also builds its fixture tree under a per-run GUID path (line 48), which is the pattern to copy rather than a fixed $env:TEMP directory.</p>
<p>Assert it end to end as well as at the entry point. The processing cutover proof asserted both through the collector entry point and through the ReportCache JSON, because a correct dispatch that nothing calls proves nothing about a real run.</p>
<p>Why now: without this the reporting cutover is unverifiable, which is exactly how the previous epic was closed while unfinished.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A fixture pairing a valid definition with a throwing .ps1 Reporting branch.</li>
<li>Assertions at the entry point and through the produced workbook.</li>
<li>The inverse case: with routing forced imperative, the same fixture fails with that exact message, so the test cannot pass on a sentinel string alone.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Removing the kill switch that makes the inverse case testable, which is AB#5953.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5944 -- Retire the duplicate discovery and script execution in the Excel job
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-excel-discovery'; Type = 'Task'; ParentId = 5944; Priority = 2
            Title = 'Remove the duplicate collector discovery and script block execution from the Excel job'
            Tags  = 'azure-scout; thisismydemo; reporting; pipeline'
            Description = @'
<p>src/report/renderers/inventory/Start-AZSCExcelJob.ps1 runs a second, independent collector discovery and executor. From the working tree:</p>
<ul>
<li>line 25 -- a comment recording that the walk-up depth to reach Modules/Public/InventoryModules changed from 2 to 4, which is what a hard-coded parent walk costs</li>
<li>line 27 -- $InventoryModulesPath built by Join-Path from the repo root</li>
<li>lines 28, 32, 49 and 51 -- four Get-ChildItem calls, none sorted, so folder and file order is filesystem order</li>
<li>line 100 -- $ScriptBlock = [Scriptblock]::Create($ModuleData), building executable code from file text</li>
<li>line 102 -- Invoke-Command with a ten-element positional argument list</li>
</ul>
<p>Replace all of it with src/pipeline/Get-ScoutCollector.ps1 for discovery -- the single discovery implementation AB#5649 established -- and the Reporting task from AB#5943 for execution. Discovery order must become deterministic in the process; Get-ScoutCollector already sorts (line 92).</p>
<p>Why now: this file is the reason the definitions' Export sections never run, and it is the largest single block of duplicated engine logic left outside the collectors.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>No Get-ChildItem and no [Scriptblock]::Create left in the file.</li>
<li>Discovery through Get-ScoutCollector, execution through the Reporting task.</li>
<li>A test pinning deterministic worksheet order.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The tag switch, which is the next Task.</li>
<li>The four exporters, which are AB#5945.</li>
</ul>
'@
        }
        @{
            Key = 't-excel-intag'; Type = 'Task'; ParentId = 5944; Priority = 2
            Title = 'Thread the tag switch into the Excel job as a declared parameter'
            Tags  = 'azure-scout; thisismydemo; reporting; resilience'
            Description = @'
<p>Start-AZSCExcelJob reads $InTag and passes it to each collector (line 102), but $InTag is not one of its parameters and is not passed by its caller. It resolves only by PowerShell dynamic scoping -- it happens to be set in an enclosing scope at the moment the function runs.</p>
<p>That is invisible coupling: it works, silently produces untagged workbooks if the enclosing variable is ever renamed or the call site moves, and it defeats strict mode as an early-warning mechanism because a variable found in a parent scope is not an undefined variable.</p>
<p>Declare it as a parameter and pass it explicitly from the reporting orchestrator. Confirm on a live run that tag columns actually reach the workbook, not just that the parameter binds -- the tag column set has already produced one silent ordering defect in this codebase, found by cell-by-cell comparison rather than by anything failing.</p>
<p>Why now: it must be threaded before the file is moved under AB#5951, because moving a dynamically-scoped read is how it stops resolving.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>$InTag as a declared parameter, passed explicitly by the caller.</li>
<li>A test asserting the function does not read any undeclared variable from a parent scope.</li>
<li>A live run confirming tag columns reach the workbook.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing tag column content or order.</li>
</ul>
'@
        }
        @{
            Key = 't-excel-count'; Type = 'Task'; ParentId = 5944; Priority = 3
            Title = 'Derive the supported resource type count from the definitions'
            Tags  = 'azure-scout; thisismydemo; reporting; docs'
            Description = @'
<p>Start-AZSCExcelJob line 32 computes $ModulesCount as [string]@(Get-ChildItem -Path $InventoryModulesPath -Recurse -Filter "*.ps1").count -- a count of FILES on disk, presented to the operator as the number of supported resource types. It is user-visible output, it was never the same thing as a resource type count, and it becomes zero the moment the collector tree is deleted.</p>
<p>Derive it from the definitions instead. Whether the honest number is the definition count or the distinct declared resource type count is a decision to make and record, not to infer -- several collectors declare more than one type and several declare synthetic AZSC/* types that are not resource types at all.</p>
<p>Why now: it is one of the specific things that breaks at deletion time under AB#5954, and it is cheaper to fix while the old number is still there to compare against.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The count sourced from the definitions, with the chosen definition of the number recorded.</li>
<li>Synthetic AZSC/* types excluded from any figure described to the operator as resource types.</li>
<li>A test pinning the count so it cannot silently drift.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The documentation pages that also state counts, which have their own drift guard.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5945 -- Re-point the four exporters off the collector tree
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-exp-index'; Type = 'Task'; ParentId = 5945; Priority = 3
            Title = 'Build the report section index from the definitions instead of the folder tree'
            Tags  = 'azure-scout; thisismydemo; reporting'
            Description = @'
<p>Four exporters build the same name index -- folder name to report section, file base name to cache key -- by walking the collector tree. Each does it independently, and each hard-codes the same fragile parent walk-up to find the tree:</p>
<ul>
<li>src/report/renderers/inventory/Export-AZSCJsonReport.ps1 lines 90-91 (with the section mapping comment at 94)</li>
<li>src/report/renderers/inventory/Export-AZSCPowerBIReport.ps1 lines 200-201</li>
<li>src/report/renderers/inventory/Export-AZSCMarkdownReport.ps1 lines 67-68</li>
<li>src/report/renderers/inventory/Export-AZSCAsciiDocReport.ps1 lines 77-78</li>
</ul>
<p>Write the index once, sourced from manifests/collectors, and have all four consume it. The category folder under manifests/collectors carries the same information the InventoryModules folder did, so the mapping survives the move unchanged.</p>
<p>Why now: these four do not execute collectors, so they look harmless -- and all four break the instant the tree is deleted under AB#5954.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>One shared index built from the definitions, replacing four independent walks.</li>
<li>Two of the four currently sort folders and two do not; the shared index sorts, and the two that change order must be checked against their baselines.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing any output format.</li>
</ul>
'@
        }
        @{
            Key = 't-exp-walkup'; Type = 'Task'; ParentId = 5945; Priority = 3
            Title = 'Remove the hard coded parent walk ups from the four exporters'
            Tags  = 'azure-scout; thisismydemo; reporting; testing'
            Description = @'
<p>Each of the four exporters finds the repo root by walking a fixed number of parent directories. That depth is a hidden dependency on file location, and it has already been wrong once -- Start-AZSCExcelJob line 25 carries a comment recording that its walk-up depth changed from 2 to 4 when files moved. AB#5951 moves 45 more files, so every one of these walks is about to be wrong again.</p>
<p>Replace them with whatever the rest of src/ uses to locate the module root, and add a test that fails on a re-introduced fixed-depth walk-up rather than trusting review to catch it.</p>
<p>Then prove the four exporters survive deletion: run each against a recorded report cache with the collector tree absent and assert every section is still emitted, and that the output is byte-identical to the v2.11.0 baseline for the same cache.</p>
<p>Why now: doing it before the relocation means one correction instead of two, and the byte comparison is only available while the baseline can still be reproduced.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Fixed-depth parent walks removed from all four exporters.</li>
<li>A test that fails on a re-introduced walk-up.</li>
<li>A test running all four with the collector tree absent, asserting every section is emitted and the output matches the baseline byte for byte.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The other renderers under src/report/renderers, which do not index the collector tree.</li>
</ul>
'@
        }
    )
}
