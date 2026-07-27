@{
    # Tasks for the stories under Feature AB#5918 (reference proof) and Feature AB#5922
    # (classification and conversion tooling), Epic AB#5917.
    #
    # Consumed by scripts/New-BoardTree.ps1. Every Task attaches to its story by ParentId because
    # the stories already exist on the board; New-BoardTree validates each id live for type and
    # state before writing anything.
    #
    # Facts were re-derived from the working tree at the time of writing, not copied from the
    # story text: the audit was re-run into a scratch file (176 collectors, 115 PureShaping,
    # 61 EscapeHatch), the strict-mode allow-list was checked by AST call-graph, and every file
    # and line number below was read.

    Tree = @(

        #-------------------------------------------------------------------------------------
        # AB#5919 -- Record golden row-sets from the imperative collectors
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-golden-script'; Type = 'Task'; ParentId = 5919; Priority = 1
            Title = 'Write the golden capture script that records imperative rows and workbook cells'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Add scripts/Export-ScoutGoldenRowSet.ps1, which for a given collector and fixture estate runs the imperative path exactly as tests/DeclarativeCollectorEquivalence.Tests.ps1 does today and writes the result to disk. It must capture BOTH halves that suite compares: the processed row sequence, and the cells of the workbook produced by the Reporting task, under -InTag:$false and -InTag:$true.</p>
<p>The reference invocation to copy is Get-LegacyRows in tests/DeclarativeCollectorEquivalence.Tests.ps1: it hand-builds a PSCustomObject descriptor with Name, FolderCategory and Path (Path pointing at Modules/Public/InventoryModules/&lt;Category&gt;/&lt;Name&gt;.ps1), calls Invoke-ScoutCollector -Collector $Descriptor -Context (New-EquivalenceContext) -Imperative, and throws if $Result.Mode is not exactly 'Imperative'. Keep that Mode assertion -- it is what stops the capture silently recording interpreter output and making the whole golden set vacuous.</p>
<p>Serialise rows through the same canonicalisation the suite uses, not through a plain ConvertTo-Json: ConvertTo-ComparableValue distinguishes $null from '' from @() and renders arrays as JSON, and ConvertTo-ComparableRow tolerates a $null row (Networking/VirtualNetwork emits $null into its row stream from a switch Default branch, in every shipped release) and a non-hashtable row. A capture that loses those distinctions cannot detect the differences the suite exists to detect.</p>
<p>Why now: nothing else in the repo can produce this artefact once Modules/Public/InventoryModules is deleted, and the deletion is the point of the epic. The script has to exist before any collector is removed.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>scripts/Export-ScoutGoldenRowSet.ps1 with -Category, -Name and -OutputRoot parameters, following the repo header convention (#Requires -Version 7.0, Set-StrictMode -Version Latest, $ErrorActionPreference = 'Stop').</li>
<li>Reuse of the row canonicalisation from tests/DeclarativeCollectorEquivalence.Tests.ps1, lifted into a shared file both the script and the suite dot-source, rather than copied.</li>
<li>Capture of the Reporting workbook under both InTag states, read back with ImportExcel the way the suite reads it.</li>
<li>The Mode -ne 'Imperative' guard, preserved verbatim in intent.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Recording the data -- that is the next Task.</li>
<li>Changing any collector, which would invalidate the record before it is taken.</li>
<li>Changing what the equivalence suite compares.</li>
</ul>
'@
        }
        @{
            Key = 't-golden-record'; Type = 'Task'; ParentId = 5919; Priority = 1
            Title = 'Record and commit the golden set for every collector that has a definition'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Run the capture over every collector with a manifest under manifests/collectors and commit the output. Two fixture sources feed it, matching what the equivalence suite already uses: tests/fixtures/databases-collector-input.json for the 13 Databases collectors (hand-authored for the pilot conversion), and the per-category generated estates under tests/fixtures/collector-equivalence/&lt;Category&gt;.json for everything else, loaded by Get-GeneratedFixture in tests/DeclarativeCollectorEquivalence.Tests.ps1.</p>
<p>Store one file per collector under tests/fixtures/collector-golden/&lt;Category&gt;/&lt;Name&gt;.json so a failure names the collector and a diff shows only the collector that changed. Record the fixture file's own hash alongside the rows: a golden set captured against a regenerated estate is not comparable with one captured against the previous estate, and without the hash that mismatch surfaces as an unexplained equivalence failure.</p>
<p>Why now: the record can only be taken while Modules/Public/InventoryModules still exists. Every subsequent story in this epic deletes part of it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A golden file per collector that currently has a definition, plus a documented step to capture one as each remaining collector converts.</li>
<li>The source fixture hash recorded in each golden file.</li>
<li>A driver that captures a whole category in one invocation, since 138 individual runs is not a workable manual step.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Re-pointing the equivalence suite, which is AB#5920.</li>
<li>Capturing anything for the two Identity collectors on the Unsupported contract -- they have never produced a row and are deleted under AB#5941.</li>
</ul>
'@
        }
        @{
            Key = 't-golden-determinism'; Type = 'Task'; ParentId = 5919; Priority = 1
            Title = 'Prove the golden capture regenerates byte-identically on a second run'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Add a test that captures a category twice into two scratch directories and asserts the files are byte-identical, then asserts a fresh capture matches the committed golden set. Without it the golden data is not a reference, because a spurious difference cannot be told from a real regression.</p>
<p>This repo has already been bitten by exactly this: scripts/New-ScoutCollectorFixture.ps1 was not reproducible between processes because unordered hashtable enumeration made every regeneration produce a spurious difference (recorded in the v2.11.0 release notes). Row keys come from hashtable literals and their enumeration order is not meaningful, so the capture must sort keys -- ConvertTo-ComparableRow already does, and the serialiser must too.</p>
<p>Why now: it is cheaper to build determinism in with the capture than to debug a non-deterministic golden set later, and the fixture generator proved the failure mode is real here.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A Pester test asserting two consecutive captures of one category are byte-identical.</li>
<li>An assertion that a fresh capture matches the committed golden set, so drift between collector and record fails the build.</li>
<li>Per-run temporary directories using the [guid]::NewGuid().ToString('N') pattern from tests/DeclarativeCollectorCutover.Tests.ps1, not a fixed $env:TEMP path.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Making the generated equivalence estates themselves deterministic -- that was already done under AB#5659.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5920 -- Re-point the equivalence suite at the recorded output
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-repoint-rows'; Type = 'Task'; ParentId = 5920; Priority = 1
            Title = 'Replace the imperative row reference with the recorded golden rows'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>In tests/DeclarativeCollectorEquivalence.Tests.ps1, replace the body of Get-LegacyRows -- which builds a descriptor pointing at $script:CollectorDir and calls Invoke-ScoutCollector ... -Imperative -- with a read of the committed golden row-set for that collector. The declarative side (Get-DeclarativeRows, which loads the .psd1 and calls Invoke-ScoutDeclarativeCollector) is unchanged, and the key-by-key comparison through ConvertTo-ComparableRow is unchanged.</p>
<p>Keep the vacuity guard the -Imperative switch currently provides. Today the suite throws if $Result.Mode is not 'Imperative', so it cannot degrade into comparing the interpreter with itself. The equivalent after this change is asserting that the golden file exists and that its recorded fixture hash matches the estate being fed to the declarative side; a missing or mismatched golden file must fail loudly rather than skip.</p>
<p>Why now: this is the change that removes the suite's structural dependency on the collector .ps1 files, which is the sequencing blocker for the entire epic.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Get-LegacyRows reading tests/fixtures/collector-golden/&lt;Category&gt;/&lt;Name&gt;.json.</li>
<li>A hard failure on a missing golden file or a fixture-hash mismatch.</li>
<li>Removal of $script:CollectorDir if nothing else in the file uses it.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The workbook half of the comparison, which is the next Task.</li>
<li>Relaxing what is compared -- the comparison stays key-by-key over the canonical rendering.</li>
</ul>
'@
        }
        @{
            Key = 't-repoint-workbook'; Type = 'Task'; ParentId = 5920; Priority = 1
            Title = 'Replace the imperative workbook reference and keep both tag states compared'
            Tags  = 'azure-scout; thisismydemo; testing; reporting'
            Description = @'
<p>The suite's reporting half writes a real .xlsx through both paths and compares the two workbooks cell by cell, under -InTag:$false AND -InTag:$true. Re-point the reference workbook at the recorded cells from AB#5919 and keep both tag cases.</p>
<p>The tag case is not redundant and must not be dropped as a simplification. The original collectors add their two Tag columns inside an if ($InTag) block that is NOT at the end of the column list, so a definition format that merely appends TagColumns silently reorders the last columns of every tagged sheet. That defect was found by this exact test and fixed via Export.TagColumnsBefore; a re-point that quietly tests one tag state re-opens it.</p>
<p>Why now: reporting is 0% cut over (Invoke-ScoutCollector has no Reporting branch), so this comparison is currently the only thing checking the Export section of all 138 manifests against anything.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The reference side of the workbook comparison reading recorded cells rather than executing the .ps1 Reporting branch.</li>
<li>Both InTag states retained, with the column-order assertion intact.</li>
<li>A test that mutating one field expression in a definition makes the suite fail, so the re-point is proven non-vacuous rather than assumed to be.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Adding the Reporting branch to Invoke-ScoutCollector, which is AB#5943.</li>
<li>Changing workbook appearance or column sets.</li>
</ul>
'@
        }
        @{
            Key = 't-repoint-sweep'; Type = 'Task'; ParentId = 5920; Priority = 2
            Title = 'Remove every remaining imperative reference from the test tree'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Sweep tests/ for anything else that reaches the collector .ps1 tree as a reference implementation, and either re-point it at the golden set or record why it must stay until a later story. tests/DeclarativeCollectorCoverage.Tests.ps1 dot-sources Modules/Private/Main/Get-AZSCSafeProperty.ps1, Get-AZTICollectedValue.ps1 and Get-AZSCIdSegment.ps1; those are helper functions the interpreter needs and move under AB#5951, not references to collectors. tests/DeclarativeCollectorCutover.Tests.ps1 deliberately pairs a valid definition with a .ps1 that throws to prove routing, and that proof is replaced under AB#5953.</p>
<p>Add a test asserting no file under tests/ calls Invoke-ScoutCollector with -Imperative, so the dependency cannot come back.</p>
<p>Why now: the acceptance criterion for this story is stated as an absence, and an absence needs a check or it decays.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>An AST-based assertion that no test invokes Invoke-ScoutCollector with -Imperative.</li>
<li>A recorded, per-file decision for each remaining reference, naming the story that removes it.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The cutover routing proof, which AB#5953 replaces.</li>
<li>Moving the helper functions, which is AB#5951.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5921 -- Redefine definition drift without a source collector file
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-drift-hash'; Type = 'Task'; ParentId = 5921; Priority = 2
            Title = 'Replace the regeneration drift check with a hash recorded at conversion time'
            Tags  = 'azure-scout; thisismydemo; testing; pipeline'
            Description = @'
<p>scripts/Test-ScoutCollectorDefinition.ps1 runs seven checks per definition. Checks 6 and 7 both need the collector .ps1: check 6 fails when SourceCollector is empty or names a file that does not exist (line 268 onward), and check 7 regenerates the definition by invoking scripts/ConvertTo-ScoutCollectorDefinition.ps1 against that file and fails if the result is not byte-identical. Every one of the 138 manifests carries a SourceCollector path, so deleting the collectors turns 138 definitions into 276 CI violations.</p>
<p>Replace the regeneration with a hash recorded into the definition at conversion time: the converter writes the SHA-256 of the collector source it lifted from, and the validator checks the definition against its own recorded hash rather than against a file. That keeps the property the check was bought for -- a definition and its source cannot diverge unnoticed, which happened once already and stayed green through a whole release because with StrictMode off the stale and current property accessors agreed on the fixture -- while surviving the deletion.</p>
<p>Why now: without this, the fork cannot be deleted without the CI gate turning red for every definition, and turning the gate off to permit the deletion is exactly how the previous epic was closed while unfinished.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A SourceCollectorHash key written by scripts/ConvertTo-ScoutCollectorDefinition.ps1 and validated by scripts/Test-ScoutCollectorDefinition.ps1.</li>
<li>Rewriting checks 6 and 7 so neither requires the file to exist.</li>
<li>Backfilling the hash into all existing manifests in one regeneration pass, while the collectors are still present.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Weakening the other five checks -- schema, generated-row-script parse, preamble parse, column resolution and setup-variable assignment all stay exactly as they are.</li>
<li>Deleting the collectors, which is AB#5954.</li>
</ul>
'@
        }
        @{
            Key = 't-drift-switches'; Type = 'Task'; ParentId = 5921; Priority = 2
            Title = 'Retire the drift skip switch and prove the validator passes with no collector present'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>scripts/Test-ScoutCollectorDefinition.ps1 carries -SkipDriftCheck, documented as being only for a throwaway tree whose definitions have no SourceCollector in this repo. Once the check no longer reads a file, that switch has no meaning and should go rather than linger as a way to turn the gate off.</p>
<p>Prove the outcome directly: run the validator against a sandbox containing the definitions and no Modules directory at all, and assert exit code 0. That is the acceptance criterion for this story stated as a test, and it is the only form of it that cannot pass by accident. Use a per-run sandbox path built with [guid]::NewGuid().ToString('N'), as tests/CollectorDefinitionSchema.Tests.ps1 already does at line 32.</p>
<p>Why now: the thirteen existing gate tests each write one deliberately broken definition and assert the message names the fault; this adds the one case that matters for the epic and is currently untestable.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Removal of -SkipDriftCheck and its callers, including any CI step that passes it.</li>
<li>A test that runs the validator over a collector-free sandbox and asserts exit 0.</li>
<li>Keeping -SkipAllowListStaleCheck, which serves a different purpose (the blank-column allow-list).</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The blank-column allow-list, which is unaffected.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5923 -- Correct the audit classifier in both directions
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-audit-falsepos'; Type = 'Task'; ParentId = 5923; Priority = 2
            Title = 'Stop the audit classifier matching the repository own helper functions'
            Tags  = 'azure-scout; thisismydemo; audit'
            Description = @'
<p>Get-ExternalCalls in scripts/Invoke-CollectorAudit.ps1 (line 279) matches command names against:</p>
<p>^(Get-Az(?!ureADServicePrincipal$)|Invoke-Az|New-Az|Set-Az|Connect-Az|Invoke-RestMethod$|Invoke-WebRequest$|Get-Msol|Get-Mg|Invoke-Mg)</p>
<p>PowerShell -match is case-insensitive, so Get-Az matches Get-AZSCSafeProperty, Get-AZSCIdSegment and Get-AZSCCollectedValue -- this repository's own pure, offline property accessors, which take no network call and are precisely the declarative vocabulary. The single negative lookahead only excludes Get-AzureADServicePrincipal.</p>
<p>Re-running the audit today over the working tree gives 61 EscapeHatch and 115 PureShaping, against 48/128 in the committed tests/fixtures/collector-audit.json. The difference is these helpers: they contribute 34 call sites (Get-AZSCSafeProperty 23, Get-AZSCIdSegment 8, Get-AZSCCollectedValue 3), and 13 collectors are classified EscapeHatch for no other reason -- AI/AzureAI, Compute/AvailabilitySets, Compute/VMDisk, Containers/ContainerApp, Containers/ContainerRegistries, Databases/POSTGREFlexible, Integration/ServiceBUS, Management/AllSubscriptions, Monitor/AppInsights, Monitor/MonitorMetricsIngestion, Monitor/SmartDetectorAlertRules, Networking/VirtualNetwork and Security/Vault. Every one is convertible.</p>
<p>Why now: the audit is the input to the conversion plan, and it currently says thirteen convertible collectors cannot be converted. AB#5671 introduced these helpers into collectors after the committed audit was taken, so the error grows with every hardening pass.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>An explicit exclusion for the repository's own AZSC-prefixed helpers, expressed as a named allow-list rather than another lookahead, so adding a helper is a one-line edit.</li>
<li>A test that feeds a synthetic collector calling each of the three helpers and asserts it classifies PureShaping.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The false negatives, which are the next Task.</li>
<li>Converting any of the thirteen collectors.</li>
</ul>
'@
        }
        @{
            Key = 't-audit-falseneg'; Type = 'Task'; ParentId = 5923; Priority = 2
            Title = 'Teach the audit classifier about Search-AzGraph and COM object construction'
            Tags  = 'azure-scout; thisismydemo; audit'
            Description = @'
<p>The same regex misses two real escape hatches because neither command name starts with one of its prefixes.</p>
<p>Management/AllSubscriptions.ps1 calls Search-AzGraph -- a live Resource Graph query for the management-group ancestor chain, issued inside the collector. Monitor/Outages.ps1 calls New-Object -Com to build an HTMLFile object per row, purely to strip markup out of a Service Health description. Neither is data shaping; both must be visible to the audit.</p>
<p>Verified against the current tree: a fresh audit run classifies Monitor/Outages as PureShaping despite the COM call, and classifies Management/AllSubscriptions as EscapeHatch only by accident -- it trips the Get-AZSCSafeProperty false positive, and once that is fixed its real Search-AzGraph call becomes invisible too. Fix this Task and the previous one together or the second fix will appear to regress the first.</p>
<p>Why now: AB#5940 has to convert AllSubscriptions and AB#5934 has to strip the COM call out of Outages, and neither can be planned from an audit that does not see them.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Search-AzGraph, and Search-Az* generally, added to the pattern.</li>
<li>Detection of New-Object with a -Com or -ComObject parameter, which needs a parameter check on the CommandAst rather than a name match.</li>
<li>A test asserting Management/AllSubscriptions and Monitor/Outages both classify EscapeHatch with the correct reason recorded.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Removing either call, which is AB#5940 and AB#5934.</li>
</ul>
'@
        }
        @{
            Key = 't-audit-regen'; Type = 'Task'; ParentId = 5923; Priority = 2
            Title = 'Regenerate the committed audit and reconcile the coverage lists against it'
            Tags  = 'azure-scout; thisismydemo; audit; testing'
            Description = @'
<p>tests/fixtures/collector-audit.json is committed and read directly by tests/DeclarativeCollectorCoverage.Tests.ps1, which cross-checks it against the hand-maintained UnconvertedPure, UnconvertedJoins and JoinNotExercised lists. It was last written before the helper functions spread into the collectors, so it is stale in the same direction the classifier is wrong.</p>
<p>Regenerate it after both classifier fixes land and reconcile every list entry. Any collector whose classification changes must either gain a definition or gain a list entry with a reason; the coverage test already fails on both an unlisted collector and a stale entry, which is what makes the reconciliation checkable rather than a judgement call.</p>
<p>Why now: leaving the fixture stale means the coverage test is asserting against a snapshot that disagrees with the tool that produced it, and neither number can then be trusted for planning.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Regenerating tests/fixtures/collector-audit.json and committing the new counts.</li>
<li>Reconciling UnconvertedPure, UnconvertedJoins and JoinNotExercised in tests/DeclarativeCollectorCoverage.Tests.ps1.</li>
<li>A CI check that the committed audit matches a fresh run, so it cannot go stale again.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Converting any collector as a result of a changed classification.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5924 -- Teach the converter to descend through a conditional row loop
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-conv-descend'; Type = 'Task'; ParentId = 5924; Priority = 2
            Title = 'Descend through an if statement in the converter row expansion'
            Tags  = 'azure-scout; thisismydemo; powershell'
            Description = @'
<p>Get-RowExpansion in scripts/ConvertTo-ScoutCollectorDefinition.ps1 (line 358) walks down to the level that emits rows. At each level it looks in $Body.Statements for a $obj assignment, and failing that for a ForEachStatementAst that contains one. If it finds neither it throws "no row-emitting foreach or $obj assignment at this level; this collector's shape is not recognised."</p>
<p>It never looks inside an IfStatementAst. Management/AdvisorScore.ps1 is the case that defeats it: line 33 opens $tmp = foreach ($1 in $AdvisorScore) {, line 34 is if ($1.name -in ('Cost','OperationalExcellence','Performance','Security','HighAvailability','Advisor')), and only inside that branch does line 46 open foreach ($Serie in $Series.scoreHistory) with the $obj assignment at line 52. At the loop-body level the converter sees an if and no foreach, so it throws.</p>
<p>Teach it to treat a conditional as a transparent level when exactly one of its branches contains the $obj assignment, carrying the condition text into the emitted definition so the row remains conditional. Preserve the two structural decisions already documented in that function's comment: the descent terminates where $obj is a statement of the current body (not at a loop variable named Tag, because Networking/RouteTables.ps1 calls its tag variable $TagKey), and candidate loops must contain the $obj assignment, which is what structurally excludes the retirement fold's foreach ($Retire in $Retired).</p>
<p>Why now: it is the only blocker on AdvisorScore, and the row-variant work in AB#5939 builds on the same descent, so a descent that cannot see through a conditional will fight that story too.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>IfStatementAst descent in Get-RowExpansion, with the condition preserved into the definition.</li>
<li>A clear failure, naming the collector, when more than one branch emits rows -- that is the row-variant case AB#5939 handles, not this one.</li>
<li>Unit coverage over synthetic ASTs for the conditional, the plain nested loop, and the multi-branch rejection.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Row variants for two differing $obj sites, which is AB#5939.</li>
<li>Converting AdvisorScore, which is AB#5940.</li>
</ul>
'@
        }
        @{
            Key = 't-conv-regen'; Type = 'Task'; ParentId = 5924; Priority = 2
            Title = 'Regenerate every definition and confirm the descent change moves no existing output'
            Tags  = 'azure-scout; thisismydemo; powershell; testing'
            Description = @'
<p>The converter is not a one-shot tool: scripts/Test-ScoutCollectorDefinition.ps1 check 7 regenerates every definition from its source and fails on any byte difference, so a change to the descent has to reproduce all existing manifests exactly or it has silently rewritten them.</p>
<p>Regenerate the full set after the descent change and confirm a zero diff. If any definition does move, treat it as a finding and explain it before accepting: a definition had already drifted from its collector for an entire release while its equivalence test stayed green, because with StrictMode off the stale and current property accessors agreed on the fixture. A diff here is the same class of evidence.</p>
<p>Why now: doing this in the same change as the descent is what makes the descent safe; doing it later means untangling two causes at once.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A full regeneration pass with the diff reported.</li>
<li>An explanation recorded for any definition that changes, before the change is accepted.</li>
<li>Confirmation that scripts/Test-ScoutCollectorDefinition.ps1 still exits 0 over the whole tree.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The SourceCollectorHash change from AB#5921 -- sequence this before it or rebase onto it, but do not do both in one step.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5926 -- Close the four fixture generator gaps that leave joins unexercised
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-fix-reverse'; Type = 'Task'; ParentId = 5926; Priority = 2
            Title = 'Satisfy join predicates written in the reverse direction'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>scripts/New-ScoutCollectorFixture.ps1 correlates one way: it writes the PRIMARY resource's id into a property of the synthesised partner. Four collectors in the JoinNotExercised list in tests/DeclarativeCollectorCoverage.Tests.ps1 (line 89) join the other way -- the partner's own id must equal a value found inside the primary's payload:</p>
<ul>
<li>Analytics/Streamanalytics -- $_.id -eq $data.cluster.id</li>
<li>Networking/AzureFirewall -- $_.id -eq $data.firewallpolicy.id</li>
<li>Networking/NetworkInterface -- $_.id -eq (Get-AZSCSafeProperty -InputObject $2 -Path 'properties.publicipaddress.id' -Enumerate), where $2 is an ipConfigurations element, so the value lives inside an array item of the primary</li>
<li>Networking/PrivateEndpoint -- $_.id -eq (Get-AZSCSafeProperty -InputObject $data -Path 'networkInterfaces.id' -Enumerate)</li>
</ul>
<p>Because the partner is never found, both paths take the not-found branch, every joined column is null on both sides, and equivalence passes while proving nothing about the join. Teach Get-JoinCorrelationPaths (line 558) to recognise a predicate comparing $_.id against a path rooted in the primary, and have the generator write the partner's id into that primary path instead of the reverse.</p>
<p>Why now: nine collectors currently pass equivalence without their join ever firing, and the release notes call this the weakest part of v2.11.0. These four are one gap and close together.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Reverse-direction correlation in Get-JoinCorrelationPaths and the partner synthesis.</li>
<li>Removing those four entries from JoinNotExercised -- the coverage test already fails on a stale entry, so the list can only shorten.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The accessor, membership and secondary-filter gaps, which are the three following Tasks.</li>
</ul>
'@
        }
        @{
            Key = 't-fix-accessor'; Type = 'Task'; ParentId = 5926; Priority = 2
            Title = 'Satisfy join predicates expressed as an accessor call rather than a member path'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>The generator scans predicates for $_.&lt;path&gt; member access. Containers/ContainerAppEnv writes its correlation as an accessor call instead: (Get-AZSCSafeProperty -InputObject $_ -Path 'properties.environmentId') -eq $1.id. The correlated property name lives inside a string argument, so the $_.&lt;path&gt; scan does not see it and the partner is synthesised without that property.</p>
<p>Networking/NetworkInterface and Networking/PrivateEndpoint combine this with the reverse direction, so they need both this Task and the previous one before their entries can be removed.</p>
<p>The generator already understands this helper's parameter set elsewhere -- there is a note at line 164 that only -InputObject/-Path/-Id/-Index/-Name carry a value there while -Enumerate does not -- so the shape-resolution side knows the call; it is the correlation scan that does not.</p>
<p>Why now: this is the gap that will keep recurring, because AB#5671 is actively converting collectors to read properties through these accessors. Every conversion moves another predicate out of reach of the scan.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Recognising Get-AZSCSafeProperty, Get-AZSCIdSegment and Get-AZSCCollectedValue calls in a join predicate and resolving the -Path/-Id argument to the property path being correlated.</li>
<li>Removing Containers/ContainerAppEnv from JoinNotExercised, and the two Networking entries once the reverse-direction Task also lands.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing any collector to stop using the accessors.</li>
</ul>
'@
        }
        @{
            Key = 't-fix-membership'; Type = 'Task'; ParentId = 5926; Priority = 3
            Title = 'Satisfy join predicates that test membership of a member enumerated array'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Two collectors correlate against a collection reached by member enumeration, where the generator writes a scalar:</p>
<ul>
<li>Networking/ApplicationGateways -- $1.id -in $APPGTWPOL.properties.applicationGateways.id. The partner property is an ARRAY of ids produced by enumerating applicationGateways; a scalar id never satisfies -in.</li>
<li>Containers/AKS -- $VMExtraDetails.properties | Where-Object { $_.Location -eq $1.location }, where $_ is the PROPERTIES object reached by member enumeration, so the correlated path sits one level below where the generator writes it. Its join types are additionally the synthetic AZSC/VM/SKU and AZSC/VM/Quotas rows injected by Get-ScoutVmSkuDetails and Get-ScoutVmQuotas, which no real ARG query returns.</li>
</ul>
<p>Teach the generator that a correlation path crossing a member-enumerated collection needs the value written into an ELEMENT of that collection, and that an -in / -contains predicate needs an array-valued property. AKS additionally needs the generator to synthesise the two AZSC/* synthetic types, since they exist only as prefetch output.</p>
<p>Why now: AKS is the pattern every prefetch under Feature AB#5927 will produce -- synthetic AZSC/* rows joined back to a real resource -- so a generator that cannot fixture a synthetic type will block equivalence for the whole prefetch feature, not just these two.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Array-valued partner properties for -in and -contains predicates.</li>
<li>Correlation into an element of a member-enumerated collection.</li>
<li>Fixture support for synthetic AZSC/* resource types.</li>
<li>Removing both entries from JoinNotExercised.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Networking/NetworkSecurityGroup, whose NIC id is derived inside a nested loop over the NSG's own networkInterfaces and is not a property of the primary at all -- record it as a remaining known gap if it cannot be closed here.</li>
</ul>
'@
        }
        @{
            Key = 't-fix-secondaryfilter'; Type = 'Task'; ParentId = 5926; Priority = 3
            Title = 'Satisfy a secondary resource set own filter before the join runs'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Web/APPServicePlan is the one entry in JoinNotExercised where the correlation IS written correctly. Its partner is dropped earlier: the secondary set's own filter demands $_.Properties.enabled -eq 'true', and the generator satisfies the PRIMARY set's filter through Resolve-FixtureFilter but does not do the same for a secondary set. The partner is filtered out before the join is ever evaluated.</p>
<p>The generator already knows where both filters live -- there is a comment at line 522 about handling BOTH places a join can live, and at line 538 about a filter written in double quotes that a single-quote-only pattern silently gave no join partner, which is the same class of silent miss. Apply the existing primary-filter satisfaction to the secondary set.</p>
<p>Note the honest limit already recorded in that script's header: values are synthetic and semantically meaningless, and the fixture proves the two implementations agree on the same input over the paths the collector reads -- it does not prove either is right about a real tenant. Satisfying a secondary filter must not drift into inventing plausible domain values.</p>
<p>Why now: it is the last of the four gaps and the cheapest, because the machinery exists and is applied to the wrong set.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Resolve-FixtureFilter applied to secondary resource sets.</li>
<li>Removing Web/APPServicePlan from JoinNotExercised.</li>
<li>A regeneration of every category fixture, confirmed byte-identical on a second run.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Replacing synthetic values with realistic ones.</li>
</ul>
'@
        }
    )
}
