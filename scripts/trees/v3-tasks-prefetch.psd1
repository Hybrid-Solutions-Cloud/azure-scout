@{
    # Tasks for the stories under Feature AB#5927 (move live data access out of collector row
    # loops), Epic AB#5917. AB#5928 already carries its three Tasks and is not touched here.
    #
    # The collector-to-call mapping below was re-derived by re-running scripts/Invoke-CollectorAudit.ps1
    # over the working tree into a scratch file, then discarding the three AZSC-prefixed helper
    # names the classifier wrongly reports as external calls (AB#5923 fixes that). What remains is
    # the real set of live calls made inside collector row loops.

    Tree = @(

        #-------------------------------------------------------------------------------------
        # AB#5932 -- Prefetch the per-subscription security and policy sweeps
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-sub-defender'; Type = 'Task'; ParentId = 5932; Priority = 2
            Title = 'Prefetch the four Defender sweeps into synthetic rows'
            Tags  = 'azure-scout; thisismydemo; security; powershell'
            Description = @'
<p>Four collectors under Modules/Public/InventoryModules/Security share one skeleton: iterate subscriptions, call one Az cmdlet per subscription, shape the result. None filters $Resources at all, so there is nothing for a definition to declare until the data arrives as rows.</p>
<ul>
<li>DefenderAlerts -- Get-AzSecurityAlert</li>
<li>DefenderAssessments -- Get-AzSecurityAssessment</li>
<li>DefenderPricing -- Get-AzSecurityPricing</li>
<li>DefenderSecureScore -- Get-AzSecuritySecureScore and Get-AzSecuritySecureScoreControl (two cmdlets, so two synthetic types or one carrying a discriminator)</li>
</ul>
<p>Add a prefetch under src/collect that runs the sweep once and emits synthetic rows, following the pattern already established and proven in this repo: Get-ScoutVmSkuDetails and Get-ScoutVmQuotas inject rows typed AZSC/VM/SKU and AZSC/VM/Quotas, and Compute/VirtualMachine consumes them as ordinary resource types through its normal filter. Type these AZSC/Security/Alert, AZSC/Security/Assessment and so on, and carry the subscription id on every row so the collector can correlate.</p>
<p>Why now: these four are the largest block of collectors that cannot be expressed declaratively for a reason that has nothing to do with their shape, and one prefetch clears all four.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A prefetch function per Defender data source, emitting typed synthetic rows carrying the subscription id.</li>
<li>Tests driven from a recorded payload asserting row shape and subscription linkage.</li>
<li>A tenant lacking Defender producing zero rows rather than a failure.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Writing the definitions for the four collectors -- that follows once the rows exist.</li>
<li>Changing which columns any of the four emits.</li>
</ul>
'@
        }
        @{
            Key = 't-sub-diag'; Type = 'Task'; ParentId = 5932; Priority = 2
            Title = 'Prefetch the subscription diagnostic settings sweep'
            Tags  = 'azure-scout; thisismydemo; powershell; audit'
            Description = @'
<p>Monitor/SubscriptionDiagnosticSettings.ps1 calls Get-AzDiagnosticSetting once per subscription inside its processing branch. It is the same skeleton as the Defender four and belongs in the same sweep, but it is a separate data source with its own row shape, so it is a separate Task.</p>
<p>Emit it as AZSC/Monitor/SubscriptionDiagnosticSetting rows carrying the subscription id. If the sweep is implemented as one pass over subscriptions serving several data sources, this must not become a second independent enumeration of subscriptions -- the epic's standing instruction is not to grow a second copy of anything the pipeline already does once.</p>
<p>Why now: it shares the per-subscription pass with the Defender sweeps, so doing it separately later means enumerating subscriptions twice.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Diagnostic-setting rows emitted from the shared per-subscription pass.</li>
<li>A test driven from a recorded payload.</li>
<li>A subscription returning no settings producing no rows rather than a null row.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Per-resource diagnostic settings, which this collector does not gather.</li>
</ul>
'@
        }
        @{
            Key = 't-sub-policystate'; Type = 'Task'; ParentId = 5932; Priority = 2
            Title = 'Prefetch policy compliance states without mutating ambient subscription context'
            Tags  = 'azure-scout; thisismydemo; security; resilience'
            Description = @'
<p>Management/PolicyComplianceStates.ps1 is the one collector in this cluster that needs care. The audit records three live calls in it -- Get-AzContext, Set-AzContext and Get-AzPolicyState -- and the middle one is the problem: it MUTATES ambient subscription context in the middle of processing. Anything running after it in the same session inherits whichever subscription the loop happened to end on.</p>
<p>Modules/Private/Main/Invoke-AZTISubscriptionContext.ps1 already defines Invoke-AZSCInSubscriptionContext to scope a subscription switch safely. Use it rather than writing a fourth way to do this. (Note the stale file name -- the file is AZTI, the function is AZSC. AB#5951 corrects that; do not rename it here.)</p>
<p>Why now: this is a live correctness hazard on the current path, not only an obstacle to conversion, and moving the call into the collect phase is the moment to fix it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A policy-compliance prefetch emitting AZSC/Management/PolicyComplianceState rows carrying the subscription id.</li>
<li>Subscription scoping through Invoke-AZSCInSubscriptionContext, with no Set-AzContext left in any collector.</li>
<li>A test asserting the ambient context after the sweep is identical to the context before it, including after a mid-sweep failure.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Policy definitions and set definitions, which are tenant-scoped and belong to AB#5933.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5933 -- Wire the tenant-scoped policy and role prefetches that already exist
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-tenant-policy'; Type = 'Task'; ParentId = 5933; Priority = 3
            Title = 'Wire the policy definition collectors onto the existing collect phase output'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Management/PolicyDefinitions.ps1 calls Get-AzPolicyDefinition and Management/PolicySetDefinitions.ps1 calls Get-AzPolicySetDefinition, each once, tenant-wide. src/collect/Get-ScoutApiResources.ps1 already collects both. For these two the work is wiring, not new collection: surface what the collect phase already holds as typed rows the collectors can filter, and delete the calls.</p>
<p>Check before writing anything that the shapes match. The existing collect-phase copy serves the assessment path and the collector serves the inventory path, and the same divergence is the entire subject of AB#5950 for four other functions -- assume these two diverged too until the payloads are compared.</p>
<p>Why now: it is the cheapest item in the prefetch feature and it removes two live calls for the cost of a wiring change.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Emitting the already-collected policy and policy-set definitions as typed rows.</li>
<li>A recorded comparison of the collect-phase shape against what the collectors currently receive, before either call is deleted.</li>
<li>Neither collector containing a Get-AzPolicy call afterwards.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Policy compliance states, which are per-subscription and belong to AB#5932.</li>
<li>Merging the duplicated collect implementations, which is AB#5950.</li>
</ul>
'@
        }
        @{
            Key = 't-tenant-roles'; Type = 'Task'; ParentId = 5933; Priority = 3
            Title = 'Prefetch custom role definitions once for the whole tenant'
            Tags  = 'azure-scout; thisismydemo; identity; powershell'
            Description = @'
<p>Management/CustomRoleDefinitions.ps1 calls Get-AzRoleDefinition inside its processing branch. Unlike the policy pair there is no existing collect-phase equivalent, so this needs a prefetch written.</p>
<p>The call is tenant-scoped and made once, so it does not need the per-subscription sweep from AB#5932. Emit AZSC/Management/RoleDefinition rows and have the collector filter that type. A tenant where the caller cannot read role definitions must produce zero rows rather than failing the run -- Management/ManagementGroups is the cautionary case here: its earlier try/catch stopped the crash but left the fallback returning nothing on every run, so the worksheet was silently empty for a whole class of tenant.</p>
<p>Why now: it is one of the four tenant-scoped calls this story exists to clear, and it is independent of the other three.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A role-definition prefetch and its synthetic row type.</li>
<li>A test driven from a recorded payload.</li>
<li>Explicit, tested behaviour when the caller lacks the read right: zero rows, a warning, and the run continuing.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Role ASSIGNMENTS, which this collector does not gather.</li>
</ul>
'@
        }
        @{
            Key = 't-tenant-mgtree'; Type = 'Task'; ParentId = 5933; Priority = 3
            Title = 'Materialise the flattened management group hierarchy in the collect phase'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Management/ManagementGroups.ps1 is the hard one in this story. It calls Get-AzContext and Get-AzManagementGroup, and it defines a recursive local function that flattens the group tree, deriving depth and parent path per node. A definition can filter and shape rows; it cannot run a recursion. The tree therefore has to arrive already flattened, one row per group carrying its depth and parent path.</p>
<p>Preserve the behaviour v2.10.0 fixed and paid for: enumerate without switches, expand each group by id, and keep only roots so subtrees are not rendered twice. Six tests assert on the calls made rather than on the absence of an exception, precisely because not throwing was already true while the collector produced no rows. Keep that style of assertion when the logic moves.</p>
<p>Also preserve the documented permission behaviour: without Microsoft.Management/register/action at the root, the collector returns zero rows BY DESIGN rather than failing. That is an environment concern, not a defect, and the prefetch must reproduce it.</p>
<p>Why now: this is the only item in the story that is a design problem rather than a wiring problem, so it sets the schedule for the whole story.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A collect-phase prefetch emitting one flattened row per management group with depth and parent path.</li>
<li>The root-only expansion preserved, with tests asserting the call sequence.</li>
<li>Zero rows, not a failure, for a tenant without management group read access.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The management group permission gap itself, which is an environment concern.</li>
<li>Writing the ManagementGroups definition, which follows.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5934 -- Prefetch storage service properties and strip outage markup off COM
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-storage-svcprops'; Type = 'Task'; ParentId = 5934; Priority = 3
            Title = 'Prefetch blob and file service properties per storage account'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Storage/StorageAccounts.ps1 calls Get-AzStorageBlobServiceProperty and Get-AzStorageFileServiceProperty once per account, inside the row loop, to populate its soft-delete, versioning and retention columns. Neither has an Azure Resource Graph equivalent, so the data genuinely has to be fetched -- the question is only where.</p>
<p>Move both into a collect-phase prefetch emitting AZSC/Storage/BlobServiceProperty and AZSC/Storage/FileServiceProperty rows carrying the parent account id, and have the collector join them the way the other child-collection collectors will after AB#5928.</p>
<p>This is also a determinism improvement, not only a conversion enabler: per-resource calls issued during Processing are exactly what AB#5649 removed from the rest of the engine, and a fan-out of two calls per account is the largest remaining one outside the four heavy collectors.</p>
<p>Why now: it is one collector and one prefetch, and it unblocks a Storage definition independently of every other cluster.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A service-properties prefetch for both blob and file, keyed by account id.</li>
<li>A test driven from a recorded payload asserting the soft-delete, versioning and retention columns still populate.</li>
<li>An account whose service properties cannot be read producing the same column values the current not-found path produces.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Queue and table service properties, which this collector does not read.</li>
<li>Changing which columns the collector emits.</li>
</ul>
'@
        }
        @{
            Key = 't-outages-com'; Type = 'Task'; ParentId = 5934; Priority = 3
            Title = 'Strip outage description markup without constructing a COM object'
            Tags  = 'azure-scout; thisismydemo; powershell; resilience'
            Description = @'
<p>Monitor/Outages.ps1 builds a COM HTMLFile object per row for one purpose: stripping markup out of a Service Health description. It is a Windows-only text transform sitting in the middle of a collector, and it is the only COM construction in the product.</p>
<p>Note this is currently INVISIBLE to the audit: scripts/Invoke-CollectorAudit.ps1 matches command names by prefix, and New-Object -Com matches none of them, so Monitor/Outages classifies PureShaping today despite the call. AB#5923 makes it visible; this Task removes it. Do not assume the audit will flag a regression here until that lands.</p>
<p>Replace it with a plain text transform applied in the collect phase, so the description arrives already stripped. Pin the replacement against the current output for a recorded payload before switching -- the transform's exact behaviour on entity references, nested tags and malformed markup is whatever the COM parser did, and that is not obvious from reading the code.</p>
<p>Why now: it blocks the Outages definition, it is the last COM dependency, and it is a portability defect on any non-Windows host in its own right.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Markup stripping moved into the collect phase with no COM construction anywhere under src/ or Modules/.</li>
<li>A character-for-character comparison against the current output for a recorded set of descriptions, including entity references and malformed markup.</li>
<li>A test asserting no file constructs a COM object.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing which outage columns are emitted.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5935 -- Prefetch per-resource operational telemetry for the four heavy collectors
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-op-vm'; Type = 'Task'; ParentId = 5935; Priority = 3
            Title = 'Prefetch the six per virtual machine REST calls out of the row loop'
            Tags  = 'azure-scout; thisismydemo; powershell; perf'
            Description = @'
<p>Compute/VirtualMachine.ps1 is the heaviest collector in the product. It makes six distinct Invoke-AzRestMethod calls inside its row loop -- insights metrics with a time window, a Cost Management query with a POST body, patch assessment, policy state and more -- and it is simultaneously the collector with the widest join, already correlating six resource types including the synthetic AZSC/VM/SKU and AZSC/VM/Quotas.</p>
<p>Unlike the fourteen ARM child-collection collectors in AB#5928, these six calls do not share a shape, so each is its own design decision: what the natural batch is, whether the time window can be hoisted, and what the row type should be. Take them one at a time and record the decision for each.</p>
<p>Preserve the aggregation and time windows exactly. A metric window silently changing is a wrong VALUE reaching a report, which is the defect class this whole epic exists to eliminate, and it will not show up as a failure.</p>
<p>Why now: it is the single largest source of per-resource calls during Processing and therefore the largest remaining determinism risk after AB#5649.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A prefetch per telemetry source, each with a test driven from a recorded payload.</li>
<li>The existing aggregations and time windows preserved verbatim, with a test pinning each.</li>
<li>No Invoke-AzRestMethod left in Compute/VirtualMachine.ps1.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing any aggregation, time window or metric selection.</li>
<li>The other three heavy collectors, which are separate Tasks.</li>
</ul>
'@
        }
        @{
            Key = 't-op-vmopdata'; Type = 'Task'; ParentId = 5935; Priority = 3
            Title = 'Prefetch the virtual machine operational data telemetry'
            Tags  = 'azure-scout; thisismydemo; powershell; perf'
            Description = @'
<p>Compute/VMOperationalData.ps1 calls Invoke-AzRestMethod inside its row loop and additionally joins three resource types already in the estate: microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems, microsoft.advisor/recommendations and microsoft.compute/virtualmachines/extensions. Only the REST calls need to move; the three joins are ordinary shaping over data the pipeline already holds and become part of the definition.</p>
<p>Where a telemetry source overlaps with Compute/VirtualMachine, consume the same prefetch rather than adding a second one. That is the whole point of moving the calls to the collect phase; two prefetches issuing the same request is worse than one call in a row loop.</p>
<p>Why now: it overlaps with the VirtualMachine Task, so doing them adjacently is what makes the shared prefetch obvious rather than accidental.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Each REST call moved to a prefetch, reusing the VirtualMachine prefetches where the source is the same.</li>
<li>Tests driven from recorded payloads.</li>
<li>No Invoke-AzRestMethod left in the collector.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The three existing cross-resource joins, which stay as shaping.</li>
</ul>
'@
        }
        @{
            Key = 't-op-arc'; Type = 'Task'; ParentId = 5935; Priority = 3
            Title = 'Prefetch the Arc server telemetry for both hybrid collectors'
            Tags  = 'azure-scout; thisismydemo; powershell; infrastructure'
            Description = @'
<p>Hybrid/ARCServers.ps1 and Hybrid/ArcServerOperationalData.ps1 both call Invoke-AzRestMethod inside their row loops. ArcServerOperationalData additionally joins microsoft.hybridcompute/machines/extensions, microsoft.advisor/recommendations and microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems -- the same three-way pattern as the VM operational collector, so the two pairs mirror each other and the prefetch design should too.</p>
<p>Treat these two together in one Task because they read overlapping sources for the same machines, and splitting them invites two prefetches issuing the same request.</p>
<p>Why now: they are the last two collectors making per-resource REST calls, so this Task is what lets the epic assert that no collector reaches Azure during Processing.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A shared Arc telemetry prefetch serving both collectors.</li>
<li>Tests driven from recorded payloads for both.</li>
<li>No Invoke-AzRestMethod left in either file.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Compute/AVDAzureLocal, which also touches microsoft.hybridcompute/machines but is a synthesised-row-set problem handled in AB#5940.</li>
</ul>
'@
        }
        @{
            Key = 't-op-assert'; Type = 'Task'; ParentId = 5935; Priority = 3
            Title = 'Assert no collector reaches Azure during the processing phase'
            Tags  = 'azure-scout; thisismydemo; testing; perf'
            Description = @'
<p>Once the four heavy collectors are clear, add the standing check that keeps them clear: an AST test asserting no file under Modules/Public/InventoryModules contains a call matching the corrected classifier from AB#5923.</p>
<p>The repo already has the pattern to copy. v2.10.0 shipped AST tests asserting no file under Modules calls Invoke-RestMethod, Get-AzAccessToken, Get-AzVMUsage, Get-AzComputeResourceSku or Invoke-AzCostManagementQuery outside a named two-file allow-list, and that each cmdlet has exactly one call site under src/. Use the same shape: an allow-list that can only shorten, and a stale entry failing the build.</p>
<p>Drive it from the corrected classifier rather than a fresh regex, so there is one definition of "reaches Azure" in the repo instead of two that can drift apart.</p>
<p>Why now: the criterion this feature is judged on is an absence, and every absence in this codebase that was not tested has come back.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>An AST test over the collector tree driven by the corrected classifier.</li>
<li>An allow-list that fails on both an unlisted call and a stale entry.</li>
<li>A live tenant run confirming the same worksheet row counts as the v2.11.0 baseline for every affected collector.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The collect phase itself, which is where these calls are supposed to live.</li>
</ul>
'@
        }
    )
}
