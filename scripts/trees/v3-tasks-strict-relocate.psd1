@{
    # Tasks for the stories under Feature AB#5946 (strict mode) and Feature AB#5949 (relocate the
    # surviving module code and delete the fork), Epic AB#5917.
    #
    # The reachability claim in AB#5947 was independently verified before these Tasks were
    # written, by parsing every .ps1 under Modules/ and src/ and asking which files contain a
    # CommandAst naming each function defined in an allow-listed file. All fifteen entries the
    # allow-list marks DEAD have a live production caller. The per-function results are quoted in
    # the first Task.

    Tree = @(

        #-------------------------------------------------------------------------------------
        # AB#5947 -- Correct the strict mode allow-list to reflect real reachability
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-al-correct'; Type = 'Task'; ParentId = 5947; Priority = 3
            Title = 'Correct the fifteen allow-list entries that claim to be dead code'
            Tags  = 'azure-scout; thisismydemo; testing; resilience'
            Description = @'
<p>The allow-list in scripts/Test-StrictModeGuard.ps1 holds 19 files carrying 20 weakening sites, and splits them into LIVE (4 files, 5 sites) and DEAD (15 files, 15 sites). Every DEAD entry is wrong, and the reason is a naming mismatch: each file has a stale AZTI file name but defines an AZSC function, so a reachability check run against the FILE name finds nothing while the FUNCTION is called from production code.</p>
<p>Verified by AST call-graph over Modules/ and src/. Each of the fifteen is Set-StrictMode -Off, one site per file:</p>
<ul>
<li>Private/Main/Start-AZTIExtractionOrchestration.ps1 L50 defines Start-AZSCExtractionOrchestration, called from Invoke-AzureScout.ps1</li>
<li>Private/Main/Start-AZTIProcessOrchestration.ps1 L48 defines Start-AZSCProcessOrchestration, called from Invoke-AzureScout.ps1</li>
<li>Private/Main/Start-AZTIReporOrchestration.ps1 L54 defines Start-AZSCReporOrchestration, called from Invoke-AzureScout.ps1</li>
<li>Private/Processing/Start-AZTIExtraJobs.ps1 L47 defines Start-AZSCExtraJobs, called from Invoke-AzureScout.ps1 line 854</li>
<li>The four Jobs files L33 each -- Start-AZSCAdvisoryJob, Start-AZSCPolicyJob, Start-AZSCSecCenterJob, Start-AZSCSubscriptionJob -- all called from Start-AZTIExtraJobs.ps1</li>
<li>The seven Diagram files L28-L37 -- Start-AZSCDrawIODiagram is called from Private/Processing/Invoke-AZTIDrawIOJob.ps1, and it in turn calls Start-AZSCDiagramNetwork, Start-AZSCDiagramOrganization, Start-AZSCDiagramSubscription, Start-AZSCDiagramJob and Set-AZSCDiagramFile; Build-AZTIDiagramSubnet is reached from Start-AZTIDiagramNetwork.ps1</li>
</ul>
<p>The diagram subtree additionally runs BY DEFAULT: -SkipDiagram is a [switch] on Invoke-AzureScout (line 294), threaded to Start-AZSCExtraJobs at line 854, and tested there as if (![bool]$SkipDiagram) at line 104 of Start-AZTIExtraJobs.ps1. Unset means the diagram runs.</p>
<p>Why now: the epic's criterion is strict mode in every module scope, and the allow-list currently tells anyone planning that work that three quarters of it is already dead. It is not.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>All fifteen State fields corrected to LIVE, each Reason replaced with the actual caller.</li>
<li>The guard's summary line, which prints the live and dead split, reporting 20 live sites.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Removing any site, which is AB#5948.</li>
<li>Renaming any file, which is AB#5951.</li>
</ul>
'@
        }
        @{
            Key = 't-al-derive'; Type = 'Task'; ParentId = 5947; Priority = 3
            Title = 'Derive the allow-list state from call graph reachability instead of a written string'
            Tags  = 'azure-scout; thisismydemo; testing; automation'
            Description = @'
<p>Correcting the fifteen strings fixes today's answer and does nothing about tomorrow's. The State field is hand-written prose next to a Reason that is also hand-written, and the whole reason this list was wrong is that nobody re-checked either after the code moved.</p>
<p>Compute reachability instead: from Invoke-AzureScout, walk the CommandAst graph across Modules/ and src/ and mark a file live if any function it defines is reachable. That is the same technique the guard already uses to find the weakenings themselves -- it parses with the AST rather than grepping, precisely because a regex over source text cannot tell a real call from the words in a comment, and this codebase's comments discuss Set-StrictMode -Off at length.</p>
<p>Add the assertion that would have caught the current error: a test failing when an entry claims DEAD while a path from Invoke-AzureScout reaches it. The guard already fails on a stale entry whose file no longer weakens strict mode, on the stated principle that the list can only ever get shorter; this extends the same principle to the list's contents being true.</p>
<p>Why now: the list is about to be edited by AB#5948 and rewritten again by the relocation in AB#5951, and a hand-maintained field will not survive either.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A reachability computation over the CommandAst graph rooted at Invoke-AzureScout.</li>
<li>tests/StrictModeGuard.Tests.ps1 asserting each entry's state against it.</li>
<li>Correct handling of the AZTI-file/AZSC-function mismatch, which is what defeated the original check.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Call sites reached only through a variable or Invoke-Expression -- record any as an explicit unknown rather than silently reporting them dead.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5948 -- Remove the strict mode weakening sites
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-sm-orchestrators'; Type = 'Task'; ParentId = 5948; Priority = 3
            Title = 'Lift the strict mode opt-out from the three orchestrators and the extra jobs entry'
            Tags  = 'azure-scout; thisismydemo; resilience'
            Description = @'
<p>Four Set-StrictMode -Off sites, each on the hot path of every run: Start-AZTIExtractionOrchestration.ps1 L50, Start-AZTIProcessOrchestration.ps1 L48, Start-AZTIReporOrchestration.ps1 L54 and Start-AZTIExtraJobs.ps1 L47.</p>
<p>Expect the failures to be the empty-collection class rather than the missing-property class. The root cause recorded for the v2.5.3 crash series is that under strict mode an EMPTY collection throws on member access while $null does not, so code that reads a property off a filtered result works until the filter matches nothing. Every one of these four coordinates over collections that are legitimately empty in a small tenant.</p>
<p>Lift one file at a time and run the suite between each. Lifting all four at once produces a pile of failures with no way to attribute them, and this codebase has ~800 candidate sites of that class.</p>
<p>Why now: these four are the outermost scopes, so every site below them is currently protected by a parent opt-out; lifting the leaves first would prove nothing.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Four opt-outs removed, one file per commit, suite green between each.</li>
<li>Empty-collection cases covered by tests, not only the populated ones.</li>
<li>Each allow-list entry deleted as its site goes -- the guard fails on a stale entry, so this is enforced.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Behaviour changes beyond what strict mode forces.</li>
</ul>
'@
        }
        @{
            Key = 't-sm-jobs'; Type = 'Task'; ParentId = 5948; Priority = 3
            Title = 'Lift the strict mode opt-out from the four job wrapper functions'
            Tags  = 'azure-scout; thisismydemo; resilience'
            Description = @'
<p>Start-AZTIAdvisoryJob.ps1, Start-AZTIPolicyJob.ps1, Start-AZTISecCenterJob.ps1 and Start-AZTISubscriptionJob.ps1 each carry one Set-StrictMode -Off at line 33, and all four are called from Start-AZTIExtraJobs.ps1.</p>
<p>The allow-list calls these job-era leftovers. The background-job ENGINE was deleted in v2.6.0; these functions were rewired to run in-process and still execute on every run. The name is the only thing about them that is job-era.</p>
<p>The security path is the one to be careful with. An empty Security worksheet shipped in every release until AB#5649 found it, and the cause was exactly this class of silence -- so for Start-AZSCSecCenterJob, assert on rows produced rather than on the absence of an exception. Not throwing was already true while it produced nothing.</p>
<p>Why now: they sit directly beneath Start-AZSCExtraJobs, so they are the natural next layer after the orchestrators.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Four opt-outs removed with the code beneath each made strict-safe.</li>
<li>Row-count assertions on the security path, not exception-absence assertions.</li>
<li>Their allow-list entries deleted.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Renaming the four files, which is AB#5951.</li>
</ul>
'@
        }
        @{
            Key = 't-sm-diagram'; Type = 'Task'; ParentId = 5948; Priority = 3
            Title = 'Lift the strict mode opt-out from the seven diagram files'
            Tags  = 'azure-scout; thisismydemo; resilience'
            Description = @'
<p>Seven files, one Set-StrictMode -Off each: Build-AZTIDiagramSubnet.ps1 L30, Set-AZTIDiagramFile.ps1 L37, Start-AZTIDiagramJob.ps1 L28, Start-AZTIDiagramNetwork.ps1 L29, Start-AZTIDiagramOrganization.ps1 L29, Start-AZTIDiagramSubscription.ps1 L29 and Start-AZTIDrawIODiagram.ps1 L29. This is the largest block and by some distance the hardest.</p>
<p>It is also live on every default run: -SkipDiagram is an opt-OUT switch, so an operator who passes nothing gets the diagram. The allow-list's claim that these predate the AB#5649 single-pass diagram is true of the fan-out; it is not true of the code, which still executes.</p>
<p>Two structural facts to plan around. Start-AZTIDiagramNetwork.ps1 alone defines nineteen functions, most called only from within that file, so the blast radius is contained but wide. Three of the seven each define their own Get-AZSCDiagramSafeLabel and Add-Icon, so the same function name exists in more than one file -- resolve which definition actually wins before changing any of them, because strict mode will not tell you and the answer depends on dot-source order.</p>
<p>Why now: it is 7 of the 20 sites, and the epic criterion of an empty allow-list is unreachable without it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Seven opt-outs removed with the code beneath each made strict-safe.</li>
<li>The duplicate function definitions across the seven resolved and recorded.</li>
<li>A live run with diagrams enabled producing a diagram file of the same size class as the v2.11.0 baseline.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Rewriting the diagram builder beyond what strict mode requires.</li>
</ul>
'@
        }
        @{
            Key = 't-sm-pipeline'; Type = 'Task'; ParentId = 5948; Priority = 3
            Title = 'Lift the three strict mode opt-outs in the collector pipeline'
            Tags  = 'azure-scout; thisismydemo; resilience; pipeline'
            Description = @'
<p>Three of the four LIVE sites are in src/pipeline: Invoke-ScoutCollector.ps1 line 128, and Invoke-ScoutDeclarativeCollector.ps1 lines 147 and 300. Note both files already set Set-StrictMode -Version Latest at file scope on line 2; the opt-outs are inside specific functions.</p>
<p>The collector dispatch site is the one the allow-list itself says is ready. Its recorded reason states that AB#5671 converted every collector the recorded fixtures exercise, and tests/CollectorStrictMode.Tests.ps1 now runs all 174 Standard collectors under -Version Latest with zero failures -- so on the evidence available the opt-out can go. It was left only because src/pipeline was owned by concurrent work.</p>
<p>The two interpreter sites are different: that runtime was being actively written when the allow-list was authored, and line 300 is inside Invoke-ScoutDeclarativeReporting, which is currently reached only from tests. AB#5943 puts it on the live path, so lift it after that lands or the change is unexercised.</p>
<p>Why now: the collector site is the cheapest win in the whole feature, and the reporting site should be lifted with the branch that first makes it run.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The Invoke-ScoutCollector opt-out removed, on the evidence of the existing 174-collector harness.</li>
<li>Both interpreter opt-outs removed, sequenced after AB#5943 for the reporting one.</li>
<li>Their allow-list entries deleted.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The two remaining LIVE sites outside src/pipeline, which are the next Task.</li>
</ul>
'@
        }
        @{
            Key = 't-sm-ingest'; Type = 'Task'; ParentId = 5948; Priority = 4
            Title = 'Lift the strict mode opt-outs in the AzGovViz import and the Excel styling pass'
            Tags  = 'azure-scout; thisismydemo; resilience'
            Description = @'
<p>The two remaining LIVE sites are the two with a genuine external-shape reason, so they go last and each needs recorded input before it can be tightened.</p>
<p>src/ingest/Import-AzGovViz.ps1 line 49 parses third-party AzGovViz output. The shape is not controlled by this repo and there are no fixtures for it; the comment at line 42 records that strict mode propagating into it crashes its ALZ policy handling. It needs recorded fixtures first, and that is the real work here.</p>
<p>src/report/renderers/inventory/style/Start-AZSCExcelCustomization.ps1 line 43 walks EPPlus worksheet objects whose members vary by sheet content. The comment at line 28 records that the v2 platform sets strict mode at FILE scope and it propagates in. This one needs a conversion pass over the member access, not fixtures.</p>
<p>Why now: they are the last two entries, and an empty allow-list is what the guard's stale check turns into a permanent property -- once the list is empty, any new weakening fails the build with nowhere to hide.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Recorded AzGovViz fixtures, including the ALZ policy case that crashes today.</li>
<li>Safe member access through the EPPlus walk.</li>
<li>Both opt-outs and both allow-list entries removed, leaving the list empty.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Supporting AzGovViz output shapes beyond those already handled.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5950 -- Merge the four duplicated extraction implementations
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-dup-api'; Type = 'Task'; ParentId = 5950; Priority = 2
            Title = 'Reconcile the two API resource extraction implementations'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Private/Extraction/Get-AZTIAPIResources.ps1 (defining Get-AZTIAPIResources) and src/collect/Get-ScoutApiResources.ps1 both exist and both run -- the src version serves the assessment path, the Modules version the inventory path. This is a merge of two diverged implementations, not a file move.</p>
<p>Record the differences BEFORE deleting either. One of the four pairs carries a header noting its version was ported rather than wrapped, which is direct evidence the pair diverged; assume this one did too until the outputs are compared. The comparison technique already exists in this repo: v2.10.0 checked equivalence per dataset against the v1 bodies driven over identical stubbed responses, comparing key sets, values AND the REST call sequence in order.</p>
<p>The call sequence matters as much as the values. That same release found two shape regressions introduced by an @() that looked like hardening -- CostData wrapped in an array meant a downstream reader that walks PSObject.Properties would have produced zero records with no error at all, and returning a collection member unrolled single-element arrays so every endpoint answering with exactly one row changed shape.</p>
<p>Why now: it feeds AB#5933, which wires the policy definition collectors onto this function's output.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A recorded diff of the two implementations' outputs and call sequences over identical stubbed responses.</li>
<li>One implementation under src/ serving both callers.</li>
<li>A test pinning the reconciled behaviour for the inventory and assessment callers separately.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what either path emits -- if the merge forces a change, that is a finding to record, not a decision to take silently.</li>
</ul>
'@
        }
        @{
            Key = 't-dup-cost'; Type = 'Task'; ParentId = 5950; Priority = 2
            Title = 'Reconcile the two cost inventory extraction implementations'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Private/Extraction/Get-AZTICostInventory.ps1 and src/collect/Get-ScoutCostInventory.ps1 are the second live duplicate pair. Same method as the API pair: diff the outputs and the call sequence over identical stubbed responses before either is deleted.</p>
<p>Cost is the pair with the known trap. The v2.10.0 comparison caught CostData being wrapped in an array, which would have made Get-ScoutCostAnomaly -- which reads the raw shape through PSObject.Properties -- return zero records with no error at all. Nothing in the product would have failed. Any reconciliation here has to check the anomaly consumer explicitly, not just the cost rows.</p>
<p>Why now: it is the same technique as the API pair and the two share stub infrastructure, so doing them adjacently is cheaper than doing them apart.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A recorded diff of both implementations' outputs and REST call sequences.</li>
<li>One implementation under src/ serving both callers.</li>
<li>An explicit assertion that Get-ScoutCostAnomaly still produces records from the reconciled shape.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing the cost query window or grain.</li>
</ul>
'@
        }
        @{
            Key = 't-dup-quota'; Type = 'Task'; ParentId = 5950; Priority = 2
            Title = 'Reconcile the two virtual machine quota extraction implementations'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Private/Extraction/ResourceDetails/Get-AZTIVMQuotas.ps1 and src/collect/Get-ScoutVmQuotas.ps1 are the third pair. The src version is the one that injects synthetic rows typed AZSC/VM/Quotas, which Compute/VirtualMachine, Compute/VirtualMachineScaleSet and Containers/AKS all consume as ordinary resource types -- confirmed in their audit records.</p>
<p>That makes this pair higher risk than the first two: three collectors join against the synthetic rows, so a shape change during the merge does not fail, it changes columns in three worksheets. Pin the joined columns for all three collectors before merging, not just the quota rows themselves.</p>
<p>Watch the single-element unrolling specifically. A subscription with exactly one quota family returning an unwrapped object instead of a one-element array is the exact regression v2.10.0 caught in this family of functions.</p>
<p>Why now: the synthetic-row pattern is the model every prefetch under Feature AB#5927 is copying, so its one existing duplicate should be resolved before it is imitated fourteen more times.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A recorded diff of both implementations over identical stubbed responses.</li>
<li>One implementation under src/ serving both paths.</li>
<li>Joined-column assertions for VirtualMachine, VirtualMachineScaleSet and AKS.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing the AZSC/VM/Quotas row type or its consumers.</li>
</ul>
'@
        }
        @{
            Key = 't-dup-sku'; Type = 'Task'; ParentId = 5950; Priority = 2
            Title = 'Reconcile the two virtual machine SKU detail extraction implementations'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Private/Extraction/ResourceDetails/Get-AZTIVMSkuDetails.ps1 and src/collect/Get-ScoutVmSkuDetails.ps1 complete the four. The src version emits the AZSC/VM/SKU synthetic rows, consumed by the same three collectors as the quota rows.</p>
<p>Containers/AKS is the one to check hardest. Its join against these rows is already listed in JoinNotExercised in tests/DeclarativeCollectorCoverage.Tests.ps1 -- it correlates through $VMExtraDetails.properties | Where-Object { $_.Location -eq $1.location }, where $_ is the properties object reached by member enumeration. That join is not currently exercised by any fixture, so equivalence will NOT catch a shape change here. Do not rely on it.</p>
<p>Once all four pairs are merged, add the standing check: an AST test asserting each of the four capabilities has exactly one implementation under src/ and none under Modules/. The pattern to copy is the v2.10.0 test asserting each of Get-AzVMUsage, Get-AzComputeResourceSku and the rest has exactly one call site under src/.</p>
<p>Why now: it is the last pair, and the standing check belongs with it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A recorded diff over identical stubbed responses.</li>
<li>One implementation under src/ serving both paths.</li>
<li>An AST test asserting exactly one implementation of each of the four capabilities.</li>
<li>Explicit verification of the AKS join, which no fixture currently exercises.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Closing the AKS fixture gap, which is AB#5926.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5951 -- Relocate the remaining non-collector files into src
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-rel-extraction'; Type = 'Task'; ParentId = 5951; Priority = 3
            Title = 'Relocate the nine extraction files and correct their names'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Private/Extraction holds nine .ps1: Get-AZTIAPIResources.ps1, Get-AZTICostInventory.ps1, Get-AZTIManagementGroups.ps1, Get-AZTISubscriptions.ps1, Start-AZTIDevOpsExtraction.ps1, Start-AZTIEntraExtraction.ps1, Start-AZTIGraphExtraction.ps1, and under ResourceDetails/ Get-AZTIVMQuotas.ps1 and Get-AZTIVMSkuDetails.ps1.</p>
<p>Four of the nine are the duplicates AB#5950 merges, so sequence this after that story or those four moves will be reverted. The other five move to src/collect and are renamed to match the AZSC function each actually defines -- every file in Modules/ carries a stale AZTI file name over an AZSC function, which is the same mismatch that made the strict-mode allow-list wrong.</p>
<p>Why now: these are the files closest to src/collect in purpose, so they establish the destination convention the other five groups follow.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Five files moved to src/collect and renamed to their defined function.</li>
<li>The module loader updated so the new location is dot-sourced and the old one is not.</li>
<li>Any test asserting on the old file name corrected in the same change.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The four duplicate pairs, which AB#5950 resolves first.</li>
<li>Behaviour changes.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-main'; Type = 'Task'; ParentId = 5951; Priority = 3
            Title = 'Relocate the twenty private main files and correct their names'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Private/Main holds twenty .ps1 and is the most heterogeneous group: session and login (Connect-AZTILoginSession.ps1, Get-AZTIGraphToken.ps1, Invoke-AZTIGraphRequest.ps1), context (Invoke-AZTISubscriptionContext.ps1), paths and folders (Set-AZTIFolder.ps1, Set-AZTIReportPath.ps1, Clear-AZTICacheFolder.ps1), logging (Write-AZTIRunLog.ps1), the three orchestrators, the property accessors (Get-AZSCSafeProperty.ps1, Get-AZSCIdSegment.ps1, Get-AZTICollectedValue.ps1), and checks (Test-AZTIPS.ps1, Test-AZSCModuleUpdate.ps1, Test-AZTIManagementGroupAccess.ps1, Invoke-AZTIPermissionAudit.ps1, Get-AZTIUnsupportedData.ps1, Clear-AZTIMemory.ps1).</p>
<p>They do not share a destination. Split them across src/ by purpose rather than moving the folder wholesale, or src/ inherits a Main dumping ground.</p>
<p>The three property accessors need care: tests/DeclarativeCollectorCoverage.Tests.ps1 dot-sources all three by their current paths (lines 23-25), and tests/DeclarativeCollectorEquivalence.Tests.ps1 needs them too. They are also called from 23 collectors and are exactly the names the audit classifier wrongly flags as external calls, so AB#5923's allow-list references them by name and must be updated with the move.</p>
<p>Why now: it is the largest group, and several other stories dot-source from it, so leaving it until last means every other story's paths change twice.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Twenty files placed by purpose under src/ and renamed to their defined function.</li>
<li>Every dot-source updated, including the three in tests/DeclarativeCollectorCoverage.Tests.ps1.</li>
<li>The AZSC helper allow-list in the audit classifier re-pointed.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Merging any two of these files.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-processing'; Type = 'Task'; ParentId = 5951; Priority = 3
            Title = 'Relocate the two processing files and the four job wrappers'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Private/Processing holds Invoke-AZTIDrawIOJob.ps1 and Start-AZTIExtraJobs.ps1. Modules/Public/PublicFunctions/Jobs holds Start-AZTIAdvisoryJob.ps1, Start-AZTIPolicyJob.ps1, Start-AZTISecCenterJob.ps1 and Start-AZTISubscriptionJob.ps1. Six files, one call chain: Invoke-AzureScout calls Start-AZSCExtraJobs, which calls all four job wrappers and reaches the diagram through Invoke-AZTIDrawIOJob.</p>
<p>The Jobs folder name is now actively misleading. The background-job engine was deleted in v2.6.0 and these run in-process; the folder is why the strict-mode allow-list called them dead. Do not carry the name across -- rename the group to what it does.</p>
<p>Start-AZTIExtraJobs.ps1 also holds the -SkipDiagram gate at line 104, which is what makes the seven diagram files live on a default run. Note it in the move so it is not mistaken for dead branch.</p>
<p>Why now: it moves as one call chain, and splitting it across changes leaves half the chain resolving by dot-source order that no longer holds.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Six files relocated and renamed to their AZSC functions, under a folder named for what they do.</li>
<li>The call chain from Invoke-AzureScout verified intact after the move.</li>
<li>tests/DeterministicPipeline.Tests.ps1, which calls Start-AZSCExtraJobs directly at five sites, updated.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The strict mode opt-outs in these files, which are AB#5948.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-diagram'; Type = 'Task'; ParentId = 5951; Priority = 3
            Title = 'Relocate the seven diagram files and resolve their duplicate function definitions'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Modules/Public/PublicFunctions/Diagram holds seven .ps1 defining well over forty functions between them, most private to the subtree. Start-AZTIDiagramNetwork.ps1 alone defines nineteen.</p>
<p>There is a real hazard here that a plain move will not survive: the same function name is defined in more than one file. Get-AZSCDiagramSafeLabel is defined in Build-AZTIDiagramSubnet.ps1, Start-AZTIDiagramNetwork.ps1 AND Start-AZTIDiagramOrganization.ps1. Add-Icon is defined in both Start-AZTIDiagramOrganization.ps1 and Start-AZTIDiagramSubscription.ps1, and each calls the other's. Which definition wins today depends on dot-source order, and changing the load order is exactly what relocating files does.</p>
<p>Determine the current winner for each duplicated name before moving anything, and collapse each set to one definition as part of the move -- carrying three copies of a function into src/ merely relocates the ambiguity.</p>
<p>Why now: this subtree runs by default, so a load-order regression here changes the diagram on every run rather than in an opt-in path.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Seven files relocated and renamed.</li>
<li>Every duplicated function name collapsed to one definition, with the pre-move winner recorded.</li>
<li>A test asserting no function name is defined twice under src/.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Rewriting the diagram builder.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-public'; Type = 'Task'; ParentId = 5951; Priority = 3
            Title = 'Relocate the three public entry point files and update the module loader'
            Tags  = 'azure-scout; thisismydemo; powershell; breaking'
            Description = @'
<p>Three files sit at the root of Modules/Public/PublicFunctions: Invoke-AzureScout.ps1, Start-AZSCWizard.ps1 and Test-AZTIPermissions.ps1. These are the exported surface, so this is the move that decides whether the module still imports.</p>
<p>Invoke-AzureScout.ps1 is over a thousand lines and is the root of the whole call graph -- the orchestrators, the extra-jobs path and the wizard are all reached from it. Move it last, after every callee has landed at its new path.</p>
<p>Do the loader and the manifest in the same change. AzureScout.psd1 and the .psm1 dot-source Modules/ directories that will not exist; scripts/Test-StrictModeGuard.ps1 declares $ScanRoots = @('Modules', 'src', 'scripts') and will silently stop scanning relocated code if Modules disappears from under it; and CI paths need the same update.</p>
<p>Why now: it is the last group, and it is the one that turns the relocation from a set of moves into a module that still imports.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Three files relocated, with Test-AZTIPermissions renamed to its AZSC function.</li>
<li>The manifest and loader referencing no path under Modules.</li>
<li>The strict mode guard's scan roots and the CI analysis paths updated.</li>
<li>A clean-session import exporting the same public function set as v2.11.0.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Removing Invoke-ScoutAssessment from the export list, which is AB#5956.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-testnames'; Type = 'Task'; ParentId = 5951; Priority = 3
            Title = 'Correct the test files that assert on the stale module file names'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Five test files assert on the AZTI file names rather than on the AZSC functions those files define, so they break on rename rather than on behaviour. They are the reason a rename looks riskier than it is.</p>
<p>Correct them to assert on the function, not the path. A test that pins a file name pins a fact about the filesystem; a test that pins an exported function name pins the thing a caller depends on. Where a test genuinely needs a path -- to dot-source a private function, as tests/DeclarativeCollectorCoverage.Tests.ps1 does for the three property accessors -- centralise the path in one place so the next move is one edit.</p>
<p>Why now: doing this first makes every other Task in this story mechanical, and doing it last means five test files break in each of them.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The five file-name assertions replaced with function assertions.</li>
<li>Private dot-source paths centralised so a future move is a single edit.</li>
<li>The full suite passing with every relocated file at its new name.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what any test asserts about behaviour.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5952 -- Invert collector discovery onto the definition tree
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-disc-signature'; Type = 'Task'; ParentId = 5952; Priority = 3
            Title = 'Discover collectors from the manifest tree and drop the contract concept'
            Tags  = 'azure-scout; thisismydemo; pipeline'
            Description = @'
<p>src/pipeline/Get-ScoutCollector.ps1 discovers by walking the collector folders. It takes $InventoryRoot (line 61), warns and returns when the path is missing (line 72), derives the manifest location by walking three parents up from it (line 81), enumerates category folders with Get-ChildItem -Directory | Sort-Object Name (line 92), reads a header comment for the category, derives Contract by regex from the file header (line 123: 'Standard' when the header matches param ($SCPath), otherwise unsupported), and reports HasDeclarativeDefinition as an ADDITIVE fact about whether a definition happens to exist beside the .ps1 (documented at lines 44-45).</p>
<p>Every one of those inverts. Category comes from the manifest folder name; there is no header comment to read; the contract concept disappears entirely because AB#5941 deletes the only two non-Standard collectors; HasDeclarativeDefinition becomes universally true and therefore meaningless; and InventoryRoot ceases to exist as a parameter.</p>
<p>Why now: it must land before the collector tree is deleted under AB#5954, because discovery currently returns nothing without it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Discovery rooted at manifests/collectors, with no InventoryRoot parameter and no Contract in the output.</li>
<li>Discovery order deterministic and pinned by a test -- it is sorted today and must stay sorted.</li>
<li>A missing manifest root failing loudly rather than warning and returning empty, which is how an empty report gets produced silently.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Deleting the collector tree, which is AB#5954.</li>
</ul>
'@
        }
        @{
            Key = 't-disc-callers'; Type = 'Task'; ParentId = 5952; Priority = 3
            Title = 'Re-point every caller and fixture that builds a collector tree'
            Tags  = 'azure-scout; thisismydemo; pipeline; testing'
            Description = @'
<p>Changing the signature is the small half. Everything that constructs a collector tree -- in product code and in fixtures -- has to build a definition tree instead.</p>
<p>Production callers reference the tree from src/pipeline/Invoke-ScoutProcessing.ps1, src/pipeline/Invoke-ScoutCollector.ps1, src/collect/Invoke-Collect.ps1 and Modules/Public/PublicFunctions/Invoke-AzureScout.ps1. Twenty-eight test files reference it, including tests/DeclarativeCollectorCutover.Tests.ps1, which builds a whole fixture collector tree under a per-run path, and tests/CollectorStrictMode.Tests.ps1, which runs all 174 collectors and is itself the evidence base for lifting the strict-mode opt-out in AB#5948.</p>
<p>Handle those two deliberately rather than mechanically. The cutover test's entire technique is pairing a definition with a .ps1 that throws, so it does not survive as-is -- AB#5953 replaces the proof. The strict-mode harness loses its subject when the collectors go, so decide and record what replaces it as evidence before it is changed.</p>
<p>Why now: the signature change breaks all of them at once, so the re-point belongs in the same story.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Four production callers re-pointed.</li>
<li>Every test fixture building a definition tree instead of a collector tree.</li>
<li>A recorded decision on what replaces the 174-collector strict-mode harness as evidence.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The routing proof, which is AB#5953.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5953 -- Retire the imperative kill switch and fallback
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-kill-remove'; Type = 'Task'; ParentId = 5953; Priority = 3
            Title = 'Remove the imperative kill switch and the schema validation fallback'
            Tags  = 'azure-scout; thisismydemo; pipeline; breaking'
            Description = @'
<p>Two escape hatches in src/pipeline/Invoke-ScoutCollector.ps1 both become undefined once no .ps1 exists to fall back to:</p>
<ul>
<li>The kill switch. $env:AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS set to 1/true/yes/on forces every collector down the .ps1 path. It is read at line 38 through Test-ScoutDeclarativeCutoverDisabled, and tested in the routing condition at line 151. Invoke-ScoutProcessing -ForceImperativeCollectors is the programmatic form. It is documented public behaviour in the v2.10.0 release notes, so removing it is a breaking change and belongs in the v3.0.0 notes.</li>
<li>The fallback. A definition failing schema validation falls back to its collector with a warning, reported as Mode = 'ImperativeFallback' (line 168).</li>
</ul>
<p>Removing the fallback is safe only because the CI schema gate makes a malformed definition impossible to merge. That is the trade, and it is why the gate must not be weakened to accommodate anything else in this epic.</p>
<p>Why now: leaving either in place after the collectors are gone means an environment variable that silently produces an empty report, which is worse than no switch at all.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The environment variable, the -ForceImperativeCollectors parameter and the fallback branch all removed.</li>
<li>Mode reduced to the values that remain meaningful.</li>
<li>The removal recorded as a breaking change in the release notes.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Weakening the CI schema gate, which is what makes this safe.</li>
</ul>
'@
        }
        @{
            Key = 't-kill-failmode'; Type = 'Task'; ParentId = 5953; Priority = 3
            Title = 'Define and test what a schema validation failure does with no fallback'
            Tags  = 'azure-scout; thisismydemo; pipeline; resilience'
            Description = @'
<p>With the fallback gone, a definition that fails to load at runtime needs a defined outcome. Decide it explicitly and test it; the one outcome that must not be chosen is silent omission, because a missing worksheet is the specific failure this codebase has shipped more than once -- an empty Security sheet in every release until AB#5649, and a drifted definition that stayed green for a whole release.</p>
<p>Replacing the routing proof is the second half of this Task. tests/DeclarativeCollectorCutover.Tests.ps1 proves routing by impossibility: it pairs a valid definition with a .ps1 whose processing branch is a throw, and asserts the run completes with the row present; with the kill switch on, the same fixture fails with that exact message, so the switch cannot pass on a sentinel string alone. Both halves of that technique need a .ps1 and a kill switch, and this Task removes both.</p>
<p>Design the replacement before deleting the original. What survives the removal is a proof that the interpreter is what produced a given row -- for example a definition whose emitted value is derivable only by interpretation.</p>
<p>Why now: deleting a proof without replacing it is precisely how the previous epic was closed while unfinished.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A documented, tested outcome for a runtime schema validation failure -- failing loudly, never omitting silently.</li>
<li>A replacement routing proof that needs neither a .ps1 nor the kill switch.</li>
<li>The old cutover test retired only after the replacement passes.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing the CI schema gate's seven checks.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5954 -- Delete the module tree and update everything that pointed at it
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-del-tests'; Type = 'Task'; ParentId = 5954; Priority = 2
            Title = 'Re-point the twenty eight test files that reference the collector tree'
            Tags  = 'azure-scout; thisismydemo; testing; breaking'
            Description = @'
<p>Twenty-eight files under tests/ reference Modules/Public/InventoryModules -- confirmed by counting them in the working tree. They are the largest single dependency on the folder and the reason the deletion has to be its own story rather than a line in another one.</p>
<p>Two need a decision rather than an edit. tests/CollectorStrictMode.Tests.ps1 runs all 174 Standard collectors under -Version Latest and is cited in the strict-mode allow-list as the evidence that the collector dispatch opt-out can be lifted; when the collectors go, that evidence has no subject. tests/DeclarativeCollectorCutover.Tests.ps1 is handled by AB#5953.</p>
<p>The rest are per-category module tests that load a collector and feed it a fixture. Those become definition tests, which is a mechanical change but a large one -- do it category by category so a failure names the category.</p>
<p>Why now: this is the bulk of the deletion work, and every test still pointing at the folder is a build failure the moment it goes.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Twenty-eight test files re-pointed at manifests/collectors, category by category.</li>
<li>A recorded decision on what replaces the 174-collector strict-mode harness.</li>
<li>The full suite passing with the folder absent.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The cutover routing test, which is AB#5953.</li>
</ul>
'@
        }
        @{
            Key = 't-del-scripts'; Type = 'Task'; ParentId = 5954; Priority = 2
            Title = 'Decide the fate of the four repository scripts that default to the collector tree'
            Tags  = 'azure-scout; thisismydemo; automation'
            Description = @'
<p>Four scripts take the collector tree as their default input, and they do not all have the same answer:</p>
<ul>
<li>scripts/Get-CollectorResourceTypeMap.ps1 -- feeds the collect phase's resource type list. This one is load-bearing and must be RE-POINTED at manifests/collectors, not deleted.</li>
<li>scripts/Invoke-CollectorAudit.ps1 -- classifies collectors by AST. With no imperative collectors there is nothing to classify; it becomes historical.</li>
<li>scripts/ConvertTo-ScoutCollectorDefinition.ps1 -- converts a .ps1 into a definition. With no .ps1 left it has no input, but it is also the tool that produced every definition, so deleting it removes the ability to explain how they were derived.</li>
<li>scripts/Export-ScoutFixture.ps1 -- check what it actually reads before deciding.</li>
</ul>
<p>Record an explicit decision for each, keep or delete, with the reason. The epic's acceptance criterion asks for exactly that, because a script silently left pointing at a deleted folder is how a repo accumulates tools nobody can run.</p>
<p>Note scripts/Test-StrictModeGuard.ps1 also names the tree, but only inside allow-list paths, which AB#5951 handles.</p>
<p>Why now: it is a small, well-bounded piece that unblocks the deletion, and the resource type map has to be re-pointed before the folder goes or the collect phase loses its type list.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Get-CollectorResourceTypeMap re-pointed at the definitions, with its output compared against the current one before and after.</li>
<li>A recorded keep-or-delete decision for the other three.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The strict mode guard's allow-list paths, which move with AB#5951.</li>
</ul>
'@
        }
        @{
            Key = 't-del-userfacing'; Type = 'Task'; ParentId = 5954; Priority = 2
            Title = 'Delete the module tree and correct the user facing text that described it'
            Tags  = 'azure-scout; thisismydemo; breaking; docs'
            Description = @'
<p>The final deletion, plus the two places the folder was visible to an operator.</p>
<p>The category parameter help on Invoke-AzureScout describes folder names under Modules/Public/InventoryModules. Those folder names are preserved by manifests/collectors, so the help text needs re-wording rather than re-listing, but it must not go on describing a folder that does not exist.</p>
<p>The supported-resource-type count printed during a run is computed from a file count in Start-AZSCExcelJob (line 32) and becomes zero on deletion. AB#5944 re-points it; verify here that it did, because this is the change that would expose it.</p>
<p>Then delete the folder and confirm the epic's headline criterion directly: Test-Path Modules returns False, and the full suite passes.</p>
<p>Why now: it is the last step, and it is the one the epic is named for.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Modules/ deleted, with Test-Path Modules returning False.</li>
<li>The category parameter help re-worded to describe the definitions.</li>
<li>The printed resource-type count verified non-zero and correct after deletion.</li>
<li>The full test suite passing.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Anything already covered by the reporting, relocation or discovery stories.</li>
</ul>
'@
        }
    )
}
