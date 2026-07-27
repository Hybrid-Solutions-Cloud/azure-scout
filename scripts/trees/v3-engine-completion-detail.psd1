# Description bodies and dependency links for the v3.0.0 engine-completion tree (Epic AB#5917).
#
# Applied with scripts/Update-BoardItemDetail.ps1. Separate from scripts/trees/v3-engine-completion.psd1
# because that file CREATES the tree and this one enriches it: creation happens once, description
# and dependency correction happen whenever the evidence moves.
#
# Every count, path and construct named below was re-derived from the repo, not copied from a plan.
# Where a number appears it is the number a grep produces today; if the code changes, the number in
# the work item is wrong and should be re-derived rather than trusted.
#
# 'Precedes' means "this item must complete before the listed items start". The script maps it to
# System.LinkTypes.Dependency-Forward, which is the SUCCESSOR end -- see the script's notes.

@{
    Items = @(

        # ============================================================================ EPIC =====
        @{
            Id = 5917
            Description = @'
<div><p>The inventory engine is a fork of microsoft/ARI carried under <code>Modules/</code>. Epic AB#5638 set out to replace it and was closed after v2.11.0, but it never met its own acceptance criteria and has been reopened: <code>Modules/</code> still holds 221 .ps1 files, <code>Modules/Public/InventoryModules</code> still holds 176 collectors, and only 138 of those 176 have a definition under <code>manifests/collectors</code>.</p>
<p>Why now: the releases from v2.6.0 to v2.11.0 built the machinery -- a deterministic pipeline, a declarative interpreter, a CI gate, single-pass collection -- but the fork is still the thing that runs the report. Until it is gone the codebase carries two implementations of everything, and v3.0.0 cannot honestly be tagged.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The 38 collectors that cannot currently be expressed declaratively (176 collectors minus 138 definitions).</li>
<li>Routing report rendering through the definitions, so the Export blocks in all 138 manifests become live code.</li>
<li><code>Set-StrictMode -Version Latest</code> in every module scope: 20 weakening sites across 19 files, enumerated in <code>scripts/Test-StrictModeGuard.ps1</code>.</li>
<li>Relocating the 45 surviving non-collector .ps1 files under <code>Modules/</code> into <code>src/</code>, and deleting the folder.</li>
<li>Removing the deprecated public entry point <code>Invoke-ScoutAssessment</code> and cutting v3.0.0.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The web portal -- Epic AB#5093.</li>
<li>Lighthouse multi-tenant delegation -- Epic AB#5410.</li>
<li>Any behaviour change to what the report emits. Every step here is provably output-preserving or it is not done.</li>
</ul></div>
'@
        }

        # ==================================================================== f-proof 5918 =====
        @{
            Id = 5918
            Precedes = @(5949, 5954)
            Description = @'
<div><p><code>tests/DeclarativeCollectorEquivalence.Tests.ps1</code> builds a descriptor pointing at the collector .ps1 and calls <code>Invoke-ScoutCollector -Imperative</code> (lines 142, 238, 264 and 294) to produce the reference output it compares against; it explicitly throws if the reference came back with <code>Mode -ne 'Imperative'</code>, on the grounds that the comparison would otherwise be vacuous. The entire safety argument for the declarative path is structurally dependent on the .ps1 files existing.</p>
<p>Why now: this is the sequencing blocker for the whole epic. Delete the fork first and there is no reference implementation left to compare against, so the deletion becomes unverifiable -- the same failure mode that let AB#5638 be closed while unfinished.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Recording golden output from the imperative path while it still exists.</li>
<li>Re-pointing the equivalence suite at the recording.</li>
<li>Redefining definition drift so it no longer depends on a <code>SourceCollector</code> file existing on disk.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Converting any collector -- that is Feature AB#5937.</li>
<li>Deleting anything. This feature only adds the artefact that makes deletion checkable.</li>
</ul></div>
'@
        }
        @{
            Id = 5919
            Precedes = @(5920)
            Description = @'
<div><p>Capture, per collector and per fixture estate, the exact rows the imperative path emits, and commit them. This is the artefact that replaces the .ps1 as the reference implementation for all 176 collectors under <code>Modules/Public/InventoryModules</code>.</p>
<p>Why now: it can only be recorded while the imperative collectors still exist, and every later story in this epic edits or deletes them. This is the first thing in the epic that must happen.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Capture tooling, alongside the existing <code>scripts/Export-ScoutFixture.ps1</code> and <code>scripts/New-ScoutCollectorFixture.ps1</code>.</li>
<li>The recorded row-sets themselves, committed, covering both fixture estates the equivalence suite drives: the recorded <code>tests/fixtures/collector-equivalence/*.json</code> estates and the generated per-collector estates.</li>
<li>A determinism check: recording twice from the same fixture must produce byte-identical output, or the record cannot serve as a reference.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing collector behaviour. Anything that changes an output here invalidates the record and has to be re-captured.</li>
<li>Recording against a live tenant -- the record must be reproducible from committed fixtures.</li>
</ul></div>
'@
        }
        @{
            Id = 5920
            Description = @'
<div><p>Replace the live <code>Invoke-ScoutCollector -Imperative</code> reference call in <code>tests/DeclarativeCollectorEquivalence.Tests.ps1</code> with the committed golden data, so the suite proves the same property without needing the .ps1 files. There are four such call sites (lines 142, 238, 264 and 294), each followed by a guard that rejects a reference produced by any other mode.</p>
<p>Why now: this is what actually severs the test suite from the fork. Until it lands, deleting a collector reddens the proof rather than the code under test.</p>
<p><strong>In scope:</strong></p>
<ul>
<li><code>tests/DeclarativeCollectorEquivalence.Tests.ps1</code> -- all four reference call sites and the mode guards that protect them.</li>
<li><code>tests/DeclarativeCollectorCoverage.Tests.ps1</code>, which drives the interpreter against the same estates.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Relaxing what is compared. The key-by-key row comparison and the cell-by-cell workbook comparison must both survive intact -- a weaker comparison would make the deletion look safe without proving it.</li>
</ul></div>
'@
        }
        @{
            Id = 5921
            Precedes = @(5954)
            Description = @'
<div><p>Every one of the 138 manifests under <code>manifests/collectors</code> carries a <code>SourceCollector</code> value of the form <code>Modules/Public/InventoryModules/&lt;Category&gt;/&lt;Name&gt;.ps1</code>, written by <code>scripts/ConvertTo-ScoutCollectorDefinition.ps1</code> (line 560). Check 6 (SOURCE) in <code>scripts/Test-ScoutCollectorDefinition.ps1</code> requires that file to exist, and check 7 (DRIFT) regenerates the definition from it and requires the result to be byte-identical. Deleting the collectors turns 138 definitions into 138 CI violations.</p>
<p>Why now: it is a hard gate on the deletion. The CI validator fails the build the moment the collector tree goes, whatever else is correct.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Replacing the regeneration check with something that survives deletion -- either a content hash of the source recorded at conversion time, or retiring check 7 outright once the definition is the source of truth rather than a derivative.</li>
<li>Deciding what <code>SourceCollector</code> means after the file it names is gone: provenance record, or removed from the schema.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Weakening the other five checks in the validator. Only checks 6 and 7 depend on the .ps1 existing.</li>
</ul></div>
'@
        }

        # ================================================================== f-tooling 5922 =====
        @{
            Id = 5922
            Description = @'
<div><p><code>scripts/Invoke-CollectorAudit.ps1</code> classifies collectors with a regex that produces errors in both directions. It matches this repo's own pure in-process helpers -- <code>Get-AZSCSafeProperty</code>, <code>Get-AZSCIdSegment</code>, <code>Get-AZTICollectedValue</code> -- as live Azure calls, and it misses <code>Search-AzGraph</code> entirely while never looking for <code>New-Object -Com</code>. Its 115 pure-shaping / 61 escape-hatch split is therefore not a safe planning basis.</p>
<p>Why now: Features AB#5927 and AB#5937 are both planned against this classification and against the converter's current capabilities. Building the prefetch clusters on a classification that is wrong in both directions means re-doing the clustering.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The classifier in <code>scripts/Invoke-CollectorAudit.ps1</code> and its committed output <code>tests/fixtures/collector-audit.json</code>.</li>
<li>Converter descent through a conditional in <code>scripts/ConvertTo-ScoutCollectorDefinition.ps1</code>.</li>
<li>The four fixture generator gaps in <code>scripts/New-ScoutCollectorFixture.ps1</code> that leave nine converted joins unexercised.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Converting collectors. This feature only makes the tools honest about which collectors can be converted and proves the joins that already were.</li>
</ul></div>
'@
        }
        @{
            Id = 5923
            Precedes = @(5927)
            Description = @'
<div><p>Replace the name-prefix regex in <code>scripts/Invoke-CollectorAudit.ps1</code> with an AST check that distinguishes real external access from in-process helpers, and regenerate <code>tests/fixtures/collector-audit.json</code>.</p>
<p>Why now: the audit's own output is the input to the prefetch clustering in Feature AB#5927 and the conversion plan in AB#5937. Both false positives (pure helpers read as live calls) and false negatives (<code>Search-AzGraph</code>, <code>New-Object -Com</code>) move collectors between clusters.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Classifying by AST command name rather than by name prefix, so <code>Get-AZSCSafeProperty</code>, <code>Get-AZSCIdSegment</code> and <code>Get-AZTICollectedValue</code> stop reading as external access.</li>
<li>Adding the two constructs the regex never looks for: <code>Search-AzGraph</code> (used by <code>Management/AllSubscriptions</code>) and <code>New-Object -Com</code> (used by <code>Monitor/Outages</code>).</li>
<li>Regenerating the committed audit and re-deriving the pure-shaping / escape-hatch split from it.</li>
<li>Tests that pin BOTH failure directions, so a future regex cannot silently reintroduce either.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Acting on the corrected classification -- the prefetch and conversion work is Features AB#5927 and AB#5937.</li>
</ul></div>
'@
        }
        @{
            Id = 5924
            Precedes = @(5940)
            Description = @'
<div><p><code>Modules/Public/InventoryModules/Management/AdvisorScore.ps1</code> has one row site, no conditional row shape and no live call. It fails conversion only because its row loop opens with an <code>if</code> and then fans out over a nested <code>foreach ($Serie in $Series.scoreHistory)</code> (lines 33-52), and <code>scripts/ConvertTo-ScoutCollectorDefinition.ps1</code> does not look through the <code>if</code> for the row-emitting level. Both constructs are already expressible in the schema as <code>AdditionalFilter</code> and <code>AdditionalRowLoops</code>.</p>
<p>Why now: it is the single change that unblocks one of the three one-off conversions in AB#5940, and it is small -- the schema already has the vocabulary.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Converter descent through a conditional to find the row-emitting level, emitting the condition as <code>AdditionalFilter</code> and the nested loop as <code>AdditionalRowLoops</code>.</li>
<li>Making the converter REFUSE a collector containing a live call, rather than lifting the call verbatim into a definition preamble where it would run at interpretation time.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Schema changes. Row variants for optional child joins are a separate schema addition -- AB#5939.</li>
</ul></div>
'@
        }
        @{
            Id = 5926
            Description = @'
<div><p>Nine converted join collectors are proven equivalent only in their not-found state, because the estate <code>scripts/New-ScoutCollectorFixture.ps1</code> generates never satisfies the join predicate. They are listed with per-collector reasons in <code>$script:JoinNotExercised</code> in <code>tests/DeclarativeCollectorCoverage.Tests.ps1</code>: Analytics/Streamanalytics, Containers/AKS, Containers/ContainerAppEnv, Networking/ApplicationGateways, Networking/AzureFirewall, Networking/NetworkInterface, Networking/NetworkSecurityGroup, Networking/PrivateEndpoint, Web/APPServicePlan.</p>
<p>Why now: the nine are four generator gaps, not nine problems, and every further conversion that carries a join inherits them. The coverage test already fails loudly on a tenth, so the list only grows until the generator is fixed.</p>
<p><strong>In scope:</strong></p>
<ul>
<li><strong>Reverse-direction joins.</strong> The predicate reads <code>$_.id -eq $data.&lt;child&gt;.id</code>, so the PARTNER id must equal a value inside the PRIMARY payload; the generator correlates the other way, writing the primary id into a partner property. Affects Streamanalytics (<code>$data.cluster.id</code>) and AzureFirewall (<code>$data.firewallpolicy.id</code>).</li>
<li><strong>Predicates expressed as an accessor call.</strong> The correlated property is named in a string argument to <code>Get-AZSCSafeProperty</code> rather than as a member of <code>$_</code>, so the generator's <code>$_.&lt;path&gt;</code> scan does not see it. Affects ContainerAppEnv (<code>properties.environmentId</code>), NetworkInterface (<code>properties.publicipaddress.id</code>, reverse as well) and PrivateEndpoint (<code>networkInterfaces.id</code>, reverse as well).</li>
<li><strong>Correlation value is not a property of the primary.</strong> AKS correlates through member enumeration onto the PROPERTIES object rather than the resource, one level below where the generator writes it, and against the synthetic <code>AZSC/VM/SKU</code> and <code>AZSC/VM/Quotas</code> types no real ARG query returns. NetworkSecurityGroup correlates on an id derived inside a nested loop over the NSG's own <code>networkInterfaces</code>.</li>
<li><strong>Array-valued or secondary-filtered partner.</strong> ApplicationGateways correlates with <code>-in</code> against a member-enumerated array of ids while the generator writes scalars. APPServicePlan's correlation IS written, but the secondary set's own filter also demands <code>$_.Properties.enabled -eq 'true'</code>, which the generator does not satisfy the way <code>Resolve-FixtureFilter</code> satisfies the primary's, so the partner is dropped before the join runs.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing any collector or any definition. The definitions are correct; only the generated test estate is inadequate.</li>
<li>The three entries on <code>$script:UnconvertedJoins</code> -- those carry live calls as well as a join and belong to Feature AB#5927.</li>
</ul></div>
'@
        }

        # ================================================================= f-prefetch 5927 =====
        @{
            Id = 5927
            Precedes = @(5937)
            Description = @'
<div><p>Thirty-two of the 38 unconverted collectors call Azure inside their row loop. A definition can only shape data the pipeline already holds, so none of them can be expressed until the calls move to the collect phase. The pattern already exists in this repo: <code>src/collect/Get-ScoutVmSkuDetails.ps1</code> and <code>src/collect/Get-ScoutVmQuotas.ps1</code> inject synthetic rows typed <code>AZSC/VM/SKU</code> and <code>AZSC/VM/Quotas</code>, and <code>Modules/Public/InventoryModules/Compute/VirtualMachine.ps1</code> consumes them as ordinary resource types. No schema change was needed to do it.</p>
<p>Why now: this is the precondition for emptying <code>Modules/Public/InventoryModules</code>, and it is also a determinism win -- per-resource REST calls during Processing are exactly what AB#5649 removed from the rest of the engine.</p>
<p><strong>In scope:</strong> one prefetch per data-access cluster --</p>
<ul>
<li>ARM child collections, 14 collectors -- AB#5928.</li>
<li>Per-subscription security and policy sweeps, 6 collectors -- AB#5932.</li>
<li>Tenant-scoped policy and role lists, 4 collectors -- AB#5933.</li>
<li>Storage service properties and outage markup, 2 collectors -- AB#5934.</li>
<li>Per-resource operational telemetry, 4 heavy collectors -- AB#5935.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Writing the definitions themselves -- Feature AB#5937.</li>
<li>Changing which columns any collector emits. A prefetch that alters a value breaks the equivalence proof.</li>
</ul></div>
'@
        }
        @{
            Id = 5928
            Precedes = @(5938)
            Description = @'
<div><p>Fourteen collectors share one structure: filter the parent resource type out of <code>$Resources</code>, then issue one <code>Invoke-AzRestMethod -Method GET</code> per parent against a child collection, and shape the returned <code>value</code> array into rows. They are the largest single cluster and the most mechanical.</p>
<p>Why now: the largest block of the 32 live-call collectors, and the one whose prefetch shape is already proven by <code>Get-ScoutVmSkuDetails</code>.</p>
<p><strong>In scope:</strong> the fourteen, with parent filter and child path --</p>
<ul>
<li><code>AI/MLComputes.ps1</code>, <code>MLDatasets</code>, <code>MLDatastores</code>, <code>MLEndpoints</code>, <code>MLModels</code>, <code>MLPipelines</code> -- all filter <code>microsoft.machinelearningservices/workspaces</code> with <code>KIND -notin ('Hub','Project')</code>, api-version 2023-04-01, against <code>computes</code> / <code>data</code> / <code>datastores</code> / <code>onlineEndpoints</code>+<code>batchEndpoints</code> / <code>models</code> / <code>jobs</code>.</li>
<li><code>AI/OpenAIDeployments.ps1</code> -- filters <code>microsoft.cognitiveservices/accounts</code> with <code>KIND -eq 'OpenAI'</code>.</li>
<li><code>AI/SearchIndexes.ps1</code> -- filters <code>microsoft.search/searchservices</code>, api-version 2023-11-01, against <code>indexes</code>.</li>
<li><code>Compute/AVDApplications.ps1</code> -- filters <code>microsoft.desktopvirtualization/applicationgroups</code> with <code>PROPERTIES.applicationGroupType -eq 'RemoteApp'</code>, api-version 2022-09-09.</li>
<li><code>Monitor/AppInsightsContinuousExport.ps1</code>, <code>AppInsightsProactiveDetection</code>, <code>AppInsightsWorkItems</code> -- all filter <code>microsoft.insights/components</code>.</li>
<li><code>Monitor/LAWorkspaceLinkedServices.ps1</code>, <code>LAWorkspaceSavedSearches</code> -- both filter <code>microsoft.operationalinsights/workspaces</code>; SavedSearches additionally filters the returned <code>value</code> array before shaping.</li>
</ul>
<p><strong>Variants the prefetch must carry (re-derived from source; three of these differ from the original plan):</strong></p>
<ul>
<li><code>MLDatasets</code>, <code>MLModels</code> and <code>MLEndpoints</code> each issue a SECOND GET per child -- the latest version for Datasets and Models, the deployment count for Endpoints. Three collectors, not two.</li>
<li><code>MLEndpoints</code> ALSO iterates two endpoint types per parent, so it is both variants at once, not just the two-type loop.</li>
<li><code>MLPipelines</code> passes an OData filter in the query string (<code>$filter=jobType eq 'Pipeline'</code>), which the prefetch must reproduce or replace with client-side filtering.</li>
<li><code>SearchIndexes</code> does NOT call <code>listQueryKeys</code>. Line 39 builds a <code>listQueryKeys</code> URI into <code>$uri</code> and nothing ever invokes it -- only <code>$indexUri</code> is fetched. It is dead code and must not be reimplemented in the prefetch.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Schema changes -- this cluster needs none. The precedent injects synthetic typed rows consumed as ordinary resource types.</li>
<li>Writing the fourteen definitions -- AB#5938.</li>
</ul></div>
'@
        }
        @{
            Id = 5929
            Description = @'
<div><p>Prefetch the six Machine Learning child collections, all hanging off <code>microsoft.machinelearningservices/workspaces</code> filtered to <code>KIND -notin ('Hub','Project')</code> at api-version 2023-04-01. Today each is a per-parent <code>Invoke-AzRestMethod</code> inside the collector's row loop, which a definition cannot express.</p>
<p>Why now: the six share one parent filter and one api-version, so they are a single prefetch rather than six. They are the largest sub-group of AB#5928 and the one carrying every variant the cluster has.</p>
<p><strong>In scope:</strong></p>
<ul>
<li><code>MLComputes</code> -- child path <code>computes</code>.</li>
<li><code>MLDatastores</code> -- child path <code>datastores</code>.</li>
<li><code>MLDatasets</code> -- child path <code>data</code>, plus a second GET per child for the latest version.</li>
<li><code>MLModels</code> -- child path <code>models</code>, plus a second GET per child for the latest version.</li>
<li><code>MLEndpoints</code> -- two child paths per workspace (<code>onlineEndpoints</code> and <code>batchEndpoints</code>), plus a second GET per endpoint for the deployment count. This is the only collector in the cluster carrying both variants.</li>
<li><code>MLPipelines</code> -- child path <code>jobs</code> with the OData filter <code>jobType eq 'Pipeline'</code>.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Writing the six definitions -- that is AB#5938.</li>
<li>The Hub and Project workspace kinds, which every one of the six excludes and which have their own collectors (<code>AI/AIFoundryHubs.ps1</code>, <code>AI/AIFoundryProjects.ps1</code>).</li>
</ul></div>
'@
        }
        @{
            Id = 5930
            Description = @'
<div><p>Prefetch the five Azure Monitor child collections: three off <code>microsoft.insights/components</code> and two off <code>microsoft.operationalinsights/workspaces</code>. Each is currently a per-parent <code>Invoke-AzRestMethod</code> inside the collector's row loop.</p>
<p>Why now: two parent types cover all five, so this is two prefetches rather than five, and it is the second-largest sub-group of AB#5928.</p>
<p><strong>In scope:</strong></p>
<ul>
<li><code>Monitor/AppInsightsContinuousExport.ps1</code></li>
<li><code>Monitor/AppInsightsProactiveDetection.ps1</code></li>
<li><code>Monitor/AppInsightsWorkItems.ps1</code></li>
<li><code>Monitor/LAWorkspaceLinkedServices.ps1</code></li>
<li><code>Monitor/LAWorkspaceSavedSearches.ps1</code> -- note it filters the returned <code>value</code> array before shaping, so the prefetch must either carry that filter or preserve the unfiltered set for the definition to filter.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Writing the five definitions -- that is AB#5938.</li>
<li>The other Monitor collectors that already have definitions; only these five fan out per parent.</li>
</ul></div>
'@
        }
        @{
            Id = 5931
            Description = @'
<div><p>Prefetch the three remaining ARM child collections, one per provider. Each is currently a per-parent <code>Invoke-AzRestMethod</code> inside the collector's row loop.</p>
<p>Why now: these three share no parent type with each other or with the ML and Monitor sub-groups, so they are the residue of AB#5928 -- three separate small prefetches that would otherwise be forgotten behind the two large ones.</p>
<p><strong>In scope:</strong></p>
<ul>
<li><code>AI/OpenAIDeployments.ps1</code> -- parents are <code>microsoft.cognitiveservices/accounts</code> with <code>KIND -eq 'OpenAI'</code>; the response handler falls back to the whole body when <code>value</code> is absent, which the prefetch must preserve.</li>
<li><code>AI/SearchIndexes.ps1</code> -- parents are <code>microsoft.search/searchservices</code>, child path <code>indexes</code> at api-version 2023-11-01. It does NOT call <code>listQueryKeys</code>: line 39 builds that URI and nothing invokes it. Do not carry the dead call into the prefetch.</li>
<li><code>Compute/AVDApplications.ps1</code> -- parents are <code>microsoft.desktopvirtualization/applicationgroups</code> filtered to <code>PROPERTIES.applicationGroupType -eq 'RemoteApp'</code>, since only RemoteApp groups have applications.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Writing the three definitions -- that is AB#5938.</li>
<li>Desktop application groups, which have no applications child collection and are already covered by <code>Compute/AVDApplicationGroups.ps1</code>.</li>
</ul></div>
'@
        }
        @{
            Id = 5932
            Description = @'
<div><p>Six collectors share an identical skeleton: <code>foreach ($subscription in $Sub)</code> wrapping a single Az cmdlet call, and none of the six filters <code>$Resources</code> at all -- they receive the resource set and ignore it. One prefetch covers all six.</p>
<p>Why now: it is the cheapest of the five prefetch clusters per collector converted, and it removes a per-subscription round trip from the Processing phase.</p>
<p><strong>In scope:</strong> the six --</p>
<ul>
<li><code>Security/DefenderAlerts.ps1</code> -- <code>Get-AzSecurityAlert</code>.</li>
<li><code>Security/DefenderAssessments.ps1</code> -- <code>Get-AzSecurityAssessment</code>, then filtered client-side to the current subscription id.</li>
<li><code>Security/DefenderPricing.ps1</code> -- <code>Get-AzSecurityPricing</code>.</li>
<li><code>Security/DefenderSecureScore.ps1</code> -- <code>Get-AzSecuritySecureScore</code> AND a second call to <code>Get-AzSecuritySecureScoreControl</code> inside the same loop. It is the only one of the six that is not a single cmdlet.</li>
<li><code>Monitor/SubscriptionDiagnosticSettings.ps1</code> -- <code>Get-AzDiagnosticSetting -ResourceId "/subscriptions/&lt;id&gt;"</code>.</li>
<li><code>Management/PolicyComplianceStates.ps1</code> -- <code>Get-AzPolicyState</code>.</li>
</ul>
<p><strong>Particular care -- ambient context mutation:</strong></p>
<ul>
<li><code>PolicyComplianceStates</code> calls <code>Set-AzContext</code> inside the loop (line 43) and restores the original context afterwards (line 95), mutating ambient state mid-processing. <code>Invoke-AZSCInSubscriptionContext</code>, defined in <code>Modules/Private/Main/Invoke-AZTISubscriptionContext.ps1</code>, already exists to do exactly this safely and should be used rather than hand-rolled again.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what the cmdlets return, including the client-side subscription filter DefenderAssessments applies.</li>
</ul></div>
'@
        }
        @{
            Id = 5933
            Description = @'
<div><p>Four collectors each make one tenant-wide call rather than a per-resource one, and for three of them the prefetch already exists -- only the wiring is missing.</p>
<p>Why now: three of the four are wiring, not new code, which makes this the highest ratio of collectors converted to code written in the whole feature.</p>
<p><strong>In scope:</strong> the four --</p>
<ul>
<li><code>Management/PolicyDefinitions.ps1</code> -- <code>Get-AzPolicyDefinition -Custom</code>. Already collected: <code>src/collect/Get-ScoutApiResources.ps1</code> line 156 fetches it into the <code>PolicyDefinitions</code> field.</li>
<li><code>Management/PolicySetDefinitions.ps1</code> -- <code>Get-AzPolicySetDefinition -Custom</code>. Already collected: same file, line 153, field <code>PolicySetDefinitions</code>.</li>
<li><code>Management/CustomRoleDefinitions.ps1</code> -- <code>Get-AzRoleDefinition -Custom</code>. Not yet collected; one call to add.</li>
<li><code>Management/ManagementGroups.ps1</code> -- the hard one. It calls <code>Get-AzManagementGroup -Expand -Recurse</code>, then defines a recursive local function <code>Expand-MgHierarchy</code> (line 84) that flattens the returned tree into rows carrying depth and parent path. A definition cannot recurse, so the prefetch must emit the ALREADY-FLATTENED tree.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The management-group permission gap -- an environment concern, not a code one. The collector already degrades to a per-group fallback loop (lines 58-63) when the tenant-root expansion is refused.</li>
</ul></div>
'@
        }
        @{
            Id = 5934
            Description = @'
<div><p>Two single-collector clusters that share nothing except being too small to justify their own story.</p>
<p>Why now: both block a definition, and the Outages one additionally removes the engine's last COM dependency, which is a portability win beyond this epic.</p>
<p><strong>In scope:</strong></p>
<ul>
<li><code>Storage/StorageAccounts.ps1</code> lines 158-159 call <code>Get-AzStorageBlobServiceProperty</code> and <code>Get-AzStorageFileServiceProperty</code> once per account, for the soft-delete, versioning and retention columns. There is no Resource Graph equivalent, so the values must be prefetched per account.</li>
<li><code>Monitor/Outages.ps1</code> line 59 builds <code>New-Object -Com 'HTMLFile'</code> per row purely to strip markup out of a Service Health description. This is a Windows-only text transform, not a data-access problem: move it into the collect phase and do it without COM.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing which columns either collector emits, or how the stripped text reads. The markup stripping must produce the same string COM produced, or the equivalence proof fails.</li>
</ul></div>
'@
        }
        @{
            Id = 5935
            Description = @'
<div><p>Four collectors make heterogeneous per-resource calls inside their row loops. Unlike the ARM child cluster these share no shape, so each is its own design decision.</p>
<p>Why now: these are the collectors that dominate run time on a large tenant, so moving them into the collect phase is the largest determinism and performance win in the feature -- and the largest risk, which is why they are last.</p>
<p><strong>In scope:</strong> the four, with what each actually calls --</p>
<ul>
<li><code>Compute/VirtualMachine.ps1</code> -- six distinct REST calls inside the row loop: insights CPU metrics (line 409), insights memory metrics (418), ASR replication status (436), a recovery-vault walk (448) and per-vault recovery points (453), and a Cost Management POST with a request body (483). This one collector is most of the story.</li>
<li><code>Compute/VMOperationalData.ps1</code> -- an <code>assessPatches</code> POST (line 105).</li>
<li><code>Hybrid/ARCServers.ps1</code> -- three calls: a <code>policyStates</code> POST (line 123), insights CPU metrics (140) and a Cost Management POST (162).</li>
<li><code>Hybrid/ArcServerOperationalData.ps1</code> -- a patch-assessment POST (line 83).</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing the aggregation or the metric time windows currently used. The prefetch must return what the row loop returns today, including its failure behaviour -- every one of these calls is <code>-ErrorAction SilentlyContinue</code> and a failure currently yields an empty column rather than an error.</li>
</ul></div>
'@
        }

        # =================================================================== f-convert 5937 ====
        @{
            Id = 5937
            Precedes = @(5954)
            Description = @'
<div><p>Once live access has moved to the collect phase (Feature AB#5927), the remaining collectors become pure shaping problems. Twenty-two of them are addressed here: fourteen mechanical conversions, three needing a genuine schema addition, three one-off structures, and two that are dead and should be deleted rather than converted.</p>
<p>Why now: this is the step that empties <code>Modules/Public/InventoryModules</code> and makes deleting the fork possible at all.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The fourteen ARM child collection conversions -- AB#5938.</li>
<li>Row variants for optional child joins: a schema addition plus three conversions -- AB#5939.</li>
<li>The three collectors with unique row sources -- AB#5940.</li>
<li>Deleting the two collectors written against a contract that never existed -- AB#5941.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Report rendering -- Feature AB#5942. Converting collectors did not shrink <code>Modules/</code> last time precisely because reporting still walked the tree.</li>
<li>Deleting the collector files, which cannot happen until the golden proof (AB#5918) and reporting (AB#5942) both land.</li>
</ul></div>
'@
        }
        @{
            Id = 5938
            Description = @'
<div><p>With their child collections prefetched by AB#5928, all fourteen reduce to a single-type filter over the synthetic child rows with a join back to the parent. No schema change is required -- the same shape <code>Compute/VirtualMachine</code> already uses to consume <code>AZSC/VM/SKU</code>.</p>
<p>Why now: fourteen of the 38 unconverted collectors in one mechanical pass, immediately after their prefetch lands.</p>
<p><strong>In scope:</strong> fourteen definitions under <code>manifests/collectors</code> --</p>
<ul>
<li><code>AI/</code>: MLComputes, MLDatasets, MLDatastores, MLEndpoints, MLModels, MLPipelines, OpenAIDeployments, SearchIndexes.</li>
<li><code>Compute/</code>: AVDApplications.</li>
<li><code>Monitor/</code>: AppInsightsContinuousExport, AppInsightsProactiveDetection, AppInsightsWorkItems, LAWorkspaceLinkedServices, LAWorkspaceSavedSearches.</li>
<li>Equivalence coverage for each, driven from the golden record rather than a live <code>-Imperative</code> call.</li>
<li>The parent-derived columns each definition must reproduce -- every one of the fourteen emits parent name, subscription and resource group alongside the child's own fields, so the synthetic child row has to carry the parent id.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The prefetch itself -- AB#5928.</li>
<li>Reimplementing <code>SearchIndexes</code>' unused <code>listQueryKeys</code> URI, which is dead code in the source and must not survive the conversion.</li>
</ul></div>
'@
        }
        @{
            Id = 5939
            Description = @'
<div><p>Three collectors each have two <code>$obj = @{ ... }</code> row sites at different loop depths, guarded by a conditional. All three are the same construct: an optional-child left outer join where the differing fields are a child-derived expression in one branch and literal <code>$null</code> in the other, and where the row COUNT itself is conditional because the branches sit at different loop depths.</p>
<p>Why now: it is the only genuine schema addition left in the epic, and two of the three collectors cannot be converted at all without it.</p>
<p><strong>In scope:</strong> the three, with the exact shape of each --</p>
<ul>
<li><code>Networking/PublicIP.ps1</code> -- branches on <code>$null -ne $data.ipConfiguration.id</code> (line 68). The bound branch sets 'Associated Resource' and 'Associated Resource Type' from <code>$data.ipConfiguration.id.split('/')[8]</code> and <code>[7]</code>; the unbound branch omits them. Same loop depth, so the row count is equal here.</li>
<li><code>Networking/VirtualWAN.ps1</code> -- branches on <code>if ($vpn)</code> (line 66). The bound branch nests <code>foreach ($3 in $vpn)</code> INSIDE <code>foreach ($2 in $vhub)</code> and fills six Virtual Site columns from <code>$3</code>; the unbound branch loops <code>$vhub</code> only and sets those same six columns to literal <code>$null</code>. The row count differs by a factor of the vpn-site count.</li>
<li><code>Management/AutomationAccounts.ps1</code> -- branches on <code>$null -ne $rbs</code> (line 72). The bound branch nests <code>foreach ($1 in $rbs)</code> over the account's runbooks; the unbound branch emits one row per tag with the runbook columns absent.</li>
</ul>
<p><strong>Why the naive fix is rejected -- record this so it is not re-proposed:</strong></p>
<ul>
<li>A flag that simply runs the loop body once with a <code>$null</code> loop variable is not faithful. <code>PublicIP</code> calls <code>.split('/')</code> on the child value, which throws on <code>$null</code>, so the flag approach requires rewriting the lifted expression -- and rewriting a lifted expression breaks the verbatim-source guarantee that the entire equivalence proof rests on.</li>
<li>The design that preserves the guarantee is an ORDERED LIST OF VARIANTS, each carrying its own verbatim field expressions and its own loop nest, selected by the same condition the source branches on.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The other 35 collectors. This variant construct appears in exactly these three.</li>
</ul></div>
'@
        }
        @{
            Id = 5940
            Description = @'
<div><p>Three collectors whose row source is not the resource set, each for a different reason, and each therefore its own piece of work.</p>
<p>Why now: AdvisorScore needs nothing but the converter fix from AB#5924; the other two are the last structural blockers before the collector folder can be emptied.</p>
<p><strong>In scope:</strong> the three --</p>
<ul>
<li><code>Management/AdvisorScore.ps1</code> -- needs ONLY the converter descent from AB#5924. One row site, no conditional shape, no live call; it fails today because the row loop opens with an <code>if</code> and fans out over <code>foreach ($Serie in $Series.scoreHistory)</code>. Both constructs already exist in the schema as <code>AdditionalFilter</code> and <code>AdditionalRowLoops</code>.</li>
<li><code>Compute/AVDAzureLocal.ps1</code> -- the row loop iterates <code>$combined</code>, a set synthesised from three filtered sets and tagged with <code>Add-Member -NotePropertyName '_Platform'</code> (lines 56-57), then further decorated from <code>$avdSessionHosts</code>. No resource type exists to declare, so the synthesised set must be materialised in the collect phase as a typed row set.</li>
<li><code>Management/AllSubscriptions.ps1</code> -- iterates <code>$Sub</code> (line 81) rather than the resource set, AND runs a live <code>Search-AzGraph</code> (line 61) for the management-group ancestor chain. Both the subscription list and the graph result must arrive as prefetched rows.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing the columns any of the three emits.</li>
<li>The converter descent fix itself, which is AB#5924 and blocks this story.</li>
</ul></div>
'@
        }
        @{
            Id = 5941
            Description = @'
<div><p><code>Identity/IdentityProviders.ps1</code> and <code>Identity/SecurityDefaults.ps1</code> each consist of two calls to <code>Register-AZSCInventoryModule</code> -- one Processing block, one Reporting block. That function does not exist anywhere in <code>src/</code> or <code>Modules/</code>. It exists only as a locally-defined mock in <code>tests/Identity.Module.Tests.ps1</code> (lines 670 and 791) and as stubs in <code>tests/Test-ExcelFromDataDump.ps1</code> and <code>tests/Test-PowerBIFromDataDump.ps1</code>. Neither collector has ever produced a row in a real run.</p>
<p>Why now: they are two of the 38 "unconverted" collectors, and counting dead code as remaining work overstates the epic. Both the processing and the reporting path also carry special cases naming them, purely to avoid crashing on them.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Deleting <code>Modules/Public/InventoryModules/Identity/IdentityProviders.ps1</code> and <code>.../SecurityDefaults.ps1</code>.</li>
<li>Removing the 'Unsupported' contract special case in <code>src/pipeline/Get-ScoutCollector.ps1</code> (lines 112 and 124), which regex-matches a leading <code>Register-AZSCInventoryModule</code> to classify these two files.</li>
<li>Removing the matching regex in <code>src/report/renderers/inventory/Start-AZSCExcelJob.ps1</code> (lines 84 and 93) -- note this file now lives under <code>src/</code>, not <code>Modules/</code>.</li>
<li>Removing the skip reason in <code>src/pipeline/Invoke-ScoutProcessing.ps1</code> (line 188) and the escape-hatch reason in <code>scripts/Invoke-CollectorAudit.ps1</code> (line 365).</li>
<li>Retiring the mocks and the assertions in <code>tests/Identity.Module.Tests.ps1</code> and <code>tests/DeterministicPipeline.Tests.ps1</code> (lines 431-456) that exist only to pin this behaviour.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Reimplementing the capability. Nobody has asked for it, and the Entra extraction path already fetches both data sets (<code>Modules/Private/Extraction/Start-AZTIEntraExtraction.ps1</code> lines 175-182) under the types <code>entra/identityproviders</code> and <code>entra/securitydefaults</code>.</li>
</ul></div>
'@
        }

        # ================================================================= f-reporting 5942 ====
        @{
            Id = 5942
            Precedes = @(5954)
            Description = @'
<div><p><code>src/pipeline/Invoke-ScoutCollector.ps1</code> has no Reporting branch at all -- it is processing-only. <code>Invoke-ScoutDeclarativeReporting</code> (defined at <code>src/pipeline/Invoke-ScoutDeclarativeCollector.ps1</code> line 293) is therefore reached only through <code>Invoke-ScoutDeclarativeCollector -Task 'Reporting'</code> at line 72, which no product code path calls. The Export section of all 138 manifests is dead code on the live path. Meanwhile <code>src/report/renderers/inventory/Start-AZSCExcelJob.ps1</code> discovers the collector tree itself with unsorted <code>Get-ChildItem</code> calls (lines 27-32), re-derives the unsupported contract by regex (line 93), and executes each collector by building a script block from file text.</p>
<p>Why now: reporting is the reason converting 138 collectors did not shrink <code>Modules/</code> last time. Four further exporters index the same tree by name and break the instant it is deleted.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A Reporting branch on the shared collector entry point -- AB#5943.</li>
<li>Retiring the Excel job's duplicate discovery and script-block execution -- AB#5944.</li>
<li>Re-pointing the four name-index exporters off the tree -- AB#5945.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing workbook appearance, sheet order or column formatting. The cell-by-cell workbook comparison in the equivalence suite has to keep passing.</li>
</ul></div>
'@
        }
        @{
            Id = 5943
            Precedes = @(5944)
            Description = @'
<div><p>Give <code>src/pipeline/Invoke-ScoutCollector.ps1</code> a Reporting task alongside Processing, dispatching to <code>Invoke-ScoutDeclarativeReporting</code> for collectors that have a definition, so the Export blocks in the 138 manifests become live code instead of validated-but-unreached data.</p>
<p>Why now: it is the precondition for retiring the Excel job's own discovery and execution -- the new path has to exist before the old one can go.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The Reporting dispatch in <code>Invoke-ScoutCollector</code>, mirroring the Processing branch including the <code>AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS</code> kill-switch behaviour it already honours.</li>
<li>Tests proving a definition's Export block is what actually rendered, not the collector's.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Retiring the old path in <code>Start-AZSCExcelJob</code>, which follows as AB#5944.</li>
</ul></div>
'@
        }
        @{
            Id = 5944
            Description = @'
<div><p><code>src/report/renderers/inventory/Start-AZSCExcelJob.ps1</code> walks the collector tree with two unsorted <code>Get-ChildItem</code> calls (lines 28 and 32), re-derives the unsupported contract with a regex (line 93) that has already drifted from its counterpart in <code>Get-ScoutCollector</code> once and reached a live run, and executes collectors via a script block built from file text. It also reads a tag switch that is not one of its declared parameters and is not passed by its caller, resolving only by dynamic scoping.</p>
<p>Why now: it is the single largest remaining consumer of the collector tree, and it cannot be removed until the Reporting branch (AB#5943) exists to replace it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Removing both <code>Get-ChildItem</code> discovery calls in favour of the definition set, which is already sorted deterministically.</li>
<li>Removing the script-block-from-file-text execution in favour of the shared entry point.</li>
<li>Removing the duplicated unsupported-contract regex, which disappears entirely once AB#5941 deletes the two files it exists for.</li>
<li>Threading the tag switch as a declared parameter rather than relying on dynamic scoping.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The four name-index exporters -- AB#5945.</li>
<li>The user-visible resource-type count this file prints (line 32), which is derived from a file count and is handled with the deletion in AB#5954.</li>
</ul></div>
'@
        }
        @{
            Id = 5945
            Description = @'
<div><p>Four exporters each walk the collector folders to build a name index mapping folder name to report section and file base name to cache key. They do not execute collectors, but all four break the moment the tree is deleted, and all four hard-code the same fragile four-level parent walk-up to locate the repo root.</p>
<p>Why now: they are silent dependents. Nothing in the deletion story would surface them, and they fail at render time rather than at build time.</p>
<p><strong>In scope:</strong> the four, all under <code>src/report/renderers/inventory/</code> --</p>
<ul>
<li><code>Export-AZSCAsciiDocReport.ps1</code> (lines 77-78).</li>
<li><code>Export-AZSCJsonReport.ps1</code>.</li>
<li><code>Export-AZSCMarkdownReport.ps1</code>.</li>
<li><code>Export-AZSCPowerBIReport.ps1</code> (lines 200-201).</li>
<li>Sourcing the index from <code>manifests/collectors</code> instead, and removing the four duplicated walk-ups.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing any output format.</li>
<li><code>Build-AZSCCostManagementReport.ps1</code>, which mentions the tree only in a source comment (line 36) and needs no change.</li>
</ul></div>
'@
        }

        # ==================================================================== f-strict 5946 ====
        @{
            Id = 5946
            Precedes = @(5958)
            Description = @'
<div><p><code>scripts/Test-StrictModeGuard.ps1</code> reports 20 <code>Set-StrictMode</code> weakening sites across 19 files and classifies 15 of those files as DEAD -- "referenced only by tests". They are not. Every one is reachable from <code>Modules/Public/PublicFunctions/Invoke-AzureScout.ps1</code>.</p>
<p>Why now: the epic criterion is strict mode in every module scope, and the allow-list currently misrepresents which sites are live, so nobody can plan against it. A "dead" label is also an invitation to delete the file rather than fix it.</p>
<p><strong>The evidence the DEAD labels are wrong:</strong></p>
<ul>
<li><code>Start-AZSCExtractionOrchestration</code> is called at <code>Invoke-AzureScout.ps1</code> line 781.</li>
<li><code>Start-AZSCProcessOrchestration</code> at line 856.</li>
<li><code>Start-AZSCReporOrchestration</code> at line 886.</li>
<li><code>Start-AZSCExtraJobs</code> at line 854 -- and it in turn calls <code>Invoke-AZSCDrawIOJob</code> (line 106 of <code>Start-AZTIExtraJobs.ps1</code>) whenever <code>-SkipDiagram</code> is absent. <code>-SkipDiagram</code> is an OPT-OUT switch, so the whole seven-file diagram subtree runs by DEFAULT.</li>
<li>The four job wrappers under <code>Modules/Public/PublicFunctions/Jobs/</code> are reached from that same extra-jobs entry.</li>
</ul>
<p><strong>In scope:</strong></p>
<ul>
<li>Correcting every <code>State</code> field on the allow-list -- AB#5947.</li>
<li>Removing the 20 sites -- AB#5948.</li>
<li>Making the <code>State</code> field verifiable rather than asserted, so it cannot rot again.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Rewriting the diagram builder beyond what strict mode requires.</li>
<li>The four sites the guard already labels LIVE and correctly so.</li>
</ul></div>
'@
        }
        @{
            Id = 5947
            Precedes = @(5948)
            Description = @'
<div><p>The <code>$AllowList</code> in <code>scripts/Test-StrictModeGuard.ps1</code> (lines 73-105) justifies fifteen of its nineteen entries as belonging to a background-job engine deleted in v2.6.0. The job WRAPPERS were deleted; the functions themselves were rewired to run in-process and are on the hot path. Marking them DEAD hides fifteen live sites.</p>
<p>Why now: AB#5948 has to work through these sites, and a list that says fifteen of them do not matter will get fifteen of them skipped.</p>
<p><strong>In scope:</strong> the fifteen entries currently labelled DEAD --</p>
<ul>
<li><code>Modules/Private/Main/Start-AZTIExtractionOrchestration.ps1</code>, <code>Start-AZTIProcessOrchestration.ps1</code>, <code>Start-AZTIReporOrchestration.ps1</code>.</li>
<li><code>Modules/Private/Processing/Start-AZTIExtraJobs.ps1</code>.</li>
<li><code>Modules/Public/PublicFunctions/Jobs/</code>: <code>Start-AZTIAdvisoryJob.ps1</code>, <code>Start-AZTIPolicyJob.ps1</code>, <code>Start-AZTISecCenterJob.ps1</code>, <code>Start-AZTISubscriptionJob.ps1</code>.</li>
<li><code>Modules/Public/PublicFunctions/Diagram/</code>: <code>Build-AZTIDiagramSubnet.ps1</code>, <code>Set-AZTIDiagramFile.ps1</code>, <code>Start-AZTIDiagramJob.ps1</code>, <code>Start-AZTIDiagramNetwork.ps1</code>, <code>Start-AZTIDiagramOrganization.ps1</code>, <code>Start-AZTIDiagramSubscription.ps1</code>, <code>Start-AZTIDrawIODiagram.ps1</code>.</li>
<li>Deriving <code>State</code> mechanically -- a reachability walk from <code>Invoke-AzureScout</code> -- rather than asserting it in a comment, so the same drift cannot recur.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Removing the sites, which follows as AB#5948.</li>
<li>The four entries already labelled LIVE: <code>src/pipeline/Invoke-ScoutCollector.ps1</code>, <code>src/pipeline/Invoke-ScoutDeclarativeCollector.ps1</code> (two sites), <code>src/ingest/Import-AzGovViz.ps1</code>, <code>src/report/renderers/inventory/style/Start-AZSCExcelCustomization.ps1</code>.</li>
</ul></div>
'@
        }
        @{
            Id = 5948
            Description = @'
<div><p>Remove all 20 weakening sites so every module scope runs <code>Set-StrictMode -Version Latest</code>. Each site needs the code beneath it to survive strict mode first, so this is 19 small conversions rather than one edit.</p>
<p>Why now: it is an explicit acceptance criterion of Epic AB#5917, and the guard already blocks any NEW weakening -- so the list can only shrink, but only if someone shrinks it.</p>
<p><strong>In scope:</strong> by group --</p>
<ul>
<li>The three orchestrators under <code>Modules/Private/Main/</code> and the extra-jobs entry under <code>Modules/Private/Processing/</code>.</li>
<li>The four job wrappers under <code>Modules/Public/PublicFunctions/Jobs/</code>.</li>
<li>The seven files under <code>Modules/Public/PublicFunctions/Diagram/</code>.</li>
<li>The two interpreter sites in <code>src/pipeline/Invoke-ScoutDeclarativeCollector.ps1</code>.</li>
<li><code>src/pipeline/Invoke-ScoutCollector.ps1</code> -- the guard's own note records this one as ready to lift on the evidence of <code>tests/CollectorStrictMode.Tests.ps1</code>, which runs all 174 Standard collectors under <code>-Version Latest</code> with zero failures. It is held only because <code>src/pipeline</code> was owned by concurrent work.</li>
<li><code>src/ingest/Import-AzGovViz.ps1</code> and <code>src/report/renderers/inventory/style/Start-AZSCExcelCustomization.ps1</code>, both of which need recorded fixtures first.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Behaviour changes beyond what strict mode forces. The known traps are that <code>@()</code> collapses and that an empty collection throws on member access where <code>$null</code> does not -- both are output-preserving to fix correctly.</li>
</ul></div>
'@
        }

        # ================================================================== f-relocate 5949 ====
        @{
            Id = 5949
            Description = @'
<div><p>Beyond the 176 collectors, <code>Modules/</code> holds 45 .ps1 files: <code>Private/Extraction</code> 9 (including 2 under <code>ResourceDetails</code>), <code>Private/Main</code> 20, <code>Private/Processing</code> 2, <code>Public/PublicFunctions</code> root 3, <code>Public/PublicFunctions/Diagram</code> 7, <code>Public/PublicFunctions/Jobs</code> 4. None is dead and none is a shim. Four are already duplicated in <code>src/collect</code> with BOTH copies live -- the src versions serve the assessment path and the Modules versions the inventory path -- so those are a merge of diverged implementations rather than a move.</p>
<p>Why now: this is the step the epic is named for, and it is the last thing between the current tree and deleting <code>Modules/</code>.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Merging the four duplicated extraction implementations -- AB#5950.</li>
<li>Relocating the remaining 41 files into <code>src/</code> -- AB#5951.</li>
<li>Inverting collector discovery onto the definition tree -- AB#5952.</li>
<li>Retiring the imperative kill switch and fallback -- AB#5953.</li>
<li>Deleting <code>Modules/</code> and updating every dependent -- AB#5954.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Refactoring beyond what relocation requires. A move that also rewrites logic cannot be reviewed as a move.</li>
</ul></div>
'@
        }
        @{
            Id = 5950
            Precedes = @(5954)
            Description = @'
<div><p>Four extraction implementations exist twice and both copies run -- one serving the inventory path, one the assessment path. This is not a wrapper relationship: <code>src/collect/Get-ScoutApiResources.ps1</code> line 58 records that it was "Ported (not just wrapped) rather than calling the legacy <code>Get-AZSCAPIResources</code>", so the two have diverged and the differences are not documented anywhere.</p>
<p>Why now: deleting <code>Modules/</code> deletes one copy of each pair. Doing that without first establishing what differs is how a silent behaviour change ships.</p>
<p><strong>In scope:</strong> the four pairs --</p>
<ul>
<li><code>Modules/Private/Extraction/Get-AZTIAPIResources.ps1</code> and <code>src/collect/Get-ScoutApiResources.ps1</code>.</li>
<li><code>Modules/Private/Extraction/Get-AZTICostInventory.ps1</code> and <code>src/collect/Get-ScoutCostInventory.ps1</code>.</li>
<li><code>Modules/Private/Extraction/ResourceDetails/Get-AZTIVMQuotas.ps1</code> and <code>src/collect/Get-ScoutVmQuotas.ps1</code>.</li>
<li><code>Modules/Private/Extraction/ResourceDetails/Get-AZTIVMSkuDetails.ps1</code> and <code>src/collect/Get-ScoutVmSkuDetails.ps1</code>.</li>
<li>Reconciling each pair into a single implementation serving both paths, with a written diff of the divergence produced BEFORE either copy is deleted.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what either path emits. Both src copies carry comments recording deliberate non-<code>@()</code>-wrapping to preserve a scalar-vs-array shape the callers depend on; the merged version has to preserve both callers' expectations.</li>
</ul></div>
'@
        }
        @{
            Id = 5951
            Precedes = @(5954)
            Description = @'
<div><p>Relocate the 41 non-duplicated files from <code>Modules/</code> into <code>src/</code>: session, context, path and logging primitives, the three orchestrators, the extra-jobs path, the diagram subtree, the four job wrappers and the public entry points.</p>
<p>Why now: nothing can delete <code>Modules/</code> while live code lives in it, and the module loader dot-sources two directories that will disappear.</p>
<p><strong>In scope:</strong> 45 files by group (4 of which AB#5950 merges rather than moves) --</p>
<ul>
<li><code>Modules/Private/Extraction</code> -- 9 files, including <code>ResourceDetails/</code> 2.</li>
<li><code>Modules/Private/Main</code> -- 20 files.</li>
<li><code>Modules/Private/Processing</code> -- 2 files.</li>
<li><code>Modules/Public/PublicFunctions</code> root -- 3 files (<code>Invoke-AzureScout.ps1</code>, <code>Start-AZSCWizard.ps1</code>, <code>Test-AZTIPermissions.ps1</code>).</li>
<li><code>Modules/Public/PublicFunctions/Diagram</code> -- 7 files.</li>
<li><code>Modules/Public/PublicFunctions/Jobs</code> -- 4 files.</li>
<li>The module loader in <code>AzureScout.psm1</code>, the CI paths, and the <code>$ScanRoots</code> list in <code>scripts/Test-StrictModeGuard.ps1</code>, which currently reads <code>@('Modules', 'src', 'scripts')</code>.</li>
</ul>
<p><strong>The stale filenames -- corrected against the original plan:</strong></p>
<ul>
<li>40 of the 45 carry an <code>AZTI</code> filename that does not match the <code>AZSC</code> function it defines -- NOT all 45. The five already correct are <code>Get-AZSCIdSegment.ps1</code>, <code>Get-AZSCSafeProperty.ps1</code>, <code>Test-AZSCModuleUpdate.ps1</code>, <code>Invoke-AzureScout.ps1</code> and <code>Start-AZSCWizard.ps1</code>.</li>
<li>35 test files reference those <code>AZTI*.ps1</code> filenames, NOT five. The original estimate was out by a factor of seven, and this is the bulk of the work in this story: every module test suite dot-sources collectors and helpers by path.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Behaviour changes. A rename plus a move is already a large diff to review.</li>
</ul></div>
'@
        }
        @{
            Id = 5952
            Precedes = @(5954)
            Description = @'
<div><p><code>src/pipeline/Get-ScoutCollector.ps1</code> discovers by walking the collector folders, reads a header comment for the category, derives a contract by regex (lines 112-124) and reports the presence of a definition as an additive fact about a .ps1. Once the definitions are the only collectors, that relationship inverts.</p>
<p>Why now: the function walks the tree that AB#5954 deletes. It has to stop walking it first.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Category comes from the <code>manifests/collectors/&lt;Category&gt;</code> folder rather than a header comment.</li>
<li>The contract concept disappears -- <code>Standard</code> and <code>Unsupported</code> only exist because two files were written against a contract that never existed, and AB#5941 deletes both.</li>
<li>The inventory root ceases to exist as a parameter.</li>
<li>Every caller and every test fixture that constructs a collector tree on disk -- <code>tests/DeclarativeCollectorCutover.Tests.ps1</code> and <code>tests/CollectorDefinitionSchema.Tests.ps1</code> both build one under a sandbox root.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing discovery ORDER, which must stay deterministic -- non-deterministic ordering was the root cause fixed in AB#5649.</li>
</ul></div>
'@
        }
        @{
            Id = 5953
            Precedes = @(5954)
            Description = @'
<div><p>The environment kill switch <code>AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS</code> (read at <code>src/pipeline/Invoke-ScoutCollector.ps1</code> line 38) forces every collector back onto its .ps1, and a definition that fails schema validation falls back to the collector beside it rather than losing a worksheet. Both become undefined once the collectors are gone, and the cutover test that proves routing by pairing a definition with a collector that throws stops working.</p>
<p>Why now: both are explicit references to files AB#5954 deletes, and the fallback in particular would fail closed in a way that silently drops a worksheet.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Removing the kill switch and its documentation in <code>Invoke-ScoutCollector.ps1</code>, <code>Invoke-ScoutDeclarativeCollector.ps1</code> (line 57) and <code>Invoke-ScoutProcessing.ps1</code> (line 54).</li>
<li>Deciding what a schema validation failure does instead of falling back -- fail the run, or emit an empty sheet with a recorded reason.</li>
<li>Replacing the routing proof in <code>tests/DeclarativeCollectorCutover.Tests.ps1</code>, which currently proves routing by pairing a definition with a deliberately-throwing collector.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Weakening the CI schema gate. The gate is precisely what makes removing the fallback safe -- a malformed definition never reaches a run.</li>
</ul></div>
'@
        }
        @{
            Id = 5954
            Precedes = @(5958)
            Description = @'
<div><p>Delete <code>Modules/</code> and update everything that pointed at it. This is the acceptance criterion of Epic AB#5917 and it is blocked by every other feature in the epic.</p>
<p>Why now: it is the point of the epic. AB#5638 was closed without it, which is why this tree exists.</p>
<p><strong>In scope:</strong> the dependents, re-derived --</p>
<ul>
<li><strong>28 test files</strong> reference <code>Modules/Public/InventoryModules</code>, including <code>tests/CollectorStrictMode.Tests.ps1</code>, which runs all 174 Standard collectors and is itself the evidence that lifting the strict-mode opt-out in AB#5948 is safe. Deleting the tree deletes that proof, so the strict-mode work must be complete before, not after.</li>
<li><strong>Two scripts default a parameter to the tree</strong>: <code>scripts/Get-CollectorResourceTypeMap.ps1</code> (<code>-InventoryRoot</code>, line 51) and <code>scripts/Invoke-CollectorAudit.ps1</code> (<code>-InventoryRoot</code>, line 52). The first feeds the authoritative ARM resource-type list the collect phase queries, so it must be RE-POINTED at <code>manifests/collectors</code>, not deleted.</li>
<li><strong>One script writes the path into data</strong>: <code>scripts/ConvertTo-ScoutCollectorDefinition.ps1</code> line 560 hard-codes <code>Modules/Public/InventoryModules/&lt;Category&gt;/&lt;Name&gt;.ps1</code> into every <code>SourceCollector</code> it emits -- 138 of them, checked by AB#5921.</li>
<li><strong>The user-visible supported-resource-type count</strong> printed by <code>src/report/renderers/inventory/Start-AZSCExcelJob.ps1</code> line 32 is computed as a recursive <code>*.ps1</code> file count under the tree, and becomes zero.</li>
<li>The <code>-Category</code> parameter help, which describes folder names under the tree.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Anything already covered by the reporting feature (AB#5942) or the relocation stories (AB#5950-5953). This story is the deletion and the leftovers only.</li>
<li><code>scripts/Export-ScoutFixture.ps1</code> and <code>scripts/Test-StrictModeGuard.ps1</code>, which mention the tree only in documentation and allow-list prose.</li>
</ul></div>
'@
        }

        # =================================================================== f-release 5955 ====
        @{
            Id = 5955
            Description = @'
<div><p><code>Invoke-ScoutAssessment</code> was deprecated in v2.4.0 for removal in v3.0.0 and is still exported from <code>AzureScout.psd1</code> (line 101). This is the removal of a public NAME rather than of an implementation -- the unified entry point routes straight into it -- so the work is dropping the export, renaming the internal function, updating the internal call sites and fixing a published pipeline example that would otherwise break for users.</p>
<p>Why now: it is the documented breaking change that justifies the major version, and it must land in the same release as the fork deletion.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Removing the deprecated entry point -- AB#5956.</li>
<li>Isolating test temporary directories per run -- AB#5957.</li>
<li>Cutting and publishing v3.0.0 -- AB#5958.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Any further deprecation. One breaking change per major version is enough to explain in release notes.</li>
</ul></div>
'@
        }
        @{
            Id = 5956
            Precedes = @(5958)
            Description = @'
<div><p>Twenty-eight files reference the name <code>Invoke-ScoutAssessment</code>. Removing it is mostly mechanical, but one of the references is a published pipeline example that is user-facing breakage if missed.</p>
<p>Why now: v2.4.0 documented removal in v3.0.0. Shipping v3.0.0 with it still exported makes the deprecation notice untrue.</p>
<p><strong>In scope:</strong> the 24 files that must change, in three groups --</p>
<ul>
<li><strong>8 code files.</strong> <code>AzureScout.psd1</code> line 101, the <code>FunctionsToExport</code> entry. <code>Modules/Public/PublicFunctions/Invoke-AzureScout.ps1</code>, two LIVE internal calls at lines 541 and 789. <code>src/Invoke-ScoutPipeline.ps1</code>, three live calls at lines 168, 218 and 226. <code>src/Invoke-ScoutAssessment.ps1</code>, the definition itself, to be renamed. <code>src/report/Get-ScoutDrift.ps1</code>, <code>src/report/renderers/Export-React.ps1</code> and <code>src/report/renderers/Export-Word.ps1</code>, documentation references in help blocks. <code>.ado/azure-pipelines.yml</code> line 15, a published example users copy -- this one is user-facing breakage if missed.</li>
<li><strong>6 test files.</strong> <code>tests/Assessment.ReportReturn.Tests.ps1</code>, <code>tests/Pipeline.NonTerminatingErrors.Tests.ps1</code>, <code>tests/Pipeline.Tests.ps1</code>, <code>tests/Report.React.Tests.ps1</code>, <code>tests/StrictModeMemberEnumeration.Tests.ps1</code>, <code>tests/UnifiedEntryPoint.Tests.ps1</code>.</li>
<li><strong>10 documentation pages.</strong> <code>src/README.md</code>, <code>docs/assessment.md</code>, <code>docs/authentication.md</code>, <code>docs/folder-structure.md</code>, <code>docs/overview.md</code>, <code>docs/parameters.md</code>, <code>docs/roadmap.md</code>, <code>docs/design/arg-round-trips.md</code>, <code>docs/design/assessment-registry.md</code>, <code>docs/design/master-plan.md</code>.</li>
</ul>
<p><strong>Out of scope:</strong> four historical files that must NOT be rewritten --</p>
<ul>
<li><code>CHANGELOG.md</code>, <code>RELEASES.md</code>, <code>docs/changelog.md</code> and <code>.ai/state/HANDOFF.md</code>. They record what was true at the time; editing them falsifies the record.</li>
</ul></div>
'@
        }
        @{
            Id = 5957
            Precedes = @(5958)
            Description = @'
<div><p>Seventeen test files build a temporary directory as a FIXED path under <code>$env:TEMP</code> and <code>Remove-Item</code> it in their own <code>BeforeAll</code>. The names are distinct from each other so they do not collide across files, but two concurrent runs of the same file collide, and state survives between runs because a fixed path is not removed on failure.</p>
<p>Why now: it is the last source of cross-run test flake, and a release should not be cut on a suite that can fail for a reason unrelated to the code.</p>
<p><strong>In scope:</strong> the seventeen fixed paths --</p>
<ul>
<li><code>AZSC_AITests</code>, <code>AZSC_AnalyticsTests</code>, <code>AZSC_ComputeTests</code>, <code>AZSC_ContainersTests</code>, <code>AZSC_DatabasesTests</code>, <code>AZSC_HybridTests</code>, <code>AZSC_IdentityTests</code>, <code>AZSC_IntegrationTests</code>, <code>AZSC_IoTTests</code>, <code>AZSC_ManagementTests</code>, <code>AZSC_MonitorTests</code>, <code>AZSC_NetworkingTests</code>, <code>AZSC_OutputFormatTests</code>, <code>AZSC_PrivateMainTests</code>, <code>AZSC_RunIsolationTests</code>, <code>AZSC_SecurityTests</code>, <code>AZSC_StorageTests</code>.</li>
</ul>
<p><strong>The pattern to copy -- two files already solve it:</strong></p>
<ul>
<li><code>tests/DeclarativeCollectorCutover.Tests.ps1</code> line 48: <code>Join-Path ([System.IO.Path]::GetTempPath()) ("scout-cutover-" + [guid]::NewGuid().ToString('N'))</code>.</li>
<li><code>tests/CollectorDefinitionSchema.Tests.ps1</code> line 32, the same shape with an <code>azsc-defschema-</code> prefix.</li>
<li>Both carry a comment explaining exactly why they avoid <code>$env:TEMP\AZSC_*</code> -- that other test files delete a shared path out from under them.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what any test asserts. This is a path change and a cleanup change only.</li>
</ul></div>
'@
        }
        @{
            Id = 5958
            Description = @'
<div><p>Cut v3.0.0 once the fork is gone.</p>
<p>Why now: it is the last item in the epic, and it is what makes the breaking change (AB#5956) legitimate. It cannot start until the fork is deleted (AB#5954), strict mode is clean (AB#5946) and the deprecated entry point is removed (AB#5956).</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Version bump and the four version-pinned documents the deploy watches.</li>
<li>Tag, PowerShell Gallery publish, and install verification on a clean machine.</li>
<li>A live tenant run against the published module -- the last four releases each surfaced defects that the test suite did not.</li>
<li>Release notes that are accurate about what shipped and what did not. The gallery listing for v2.11.0 still carries notes claiming the previous epic completed, which it did not; these notes must not repeat that.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Reopening or rewriting any earlier release entry. The v2.11.0 notes are wrong but they are the historical record.</li>
</ul></div>
'@
        }
    )
}
