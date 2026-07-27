@{
    # Tasks for the stories under Feature AB#5955 (remove the deprecated entry point and release
    # v3), plus the wizard Bug AB#6060 under Feature AB#6059. Epic AB#5917.
    #
    # A Task is a valid child of a Bug on this board, so AB#6060 carries Tasks directly.
    #
    # File counts below were recounted in the working tree: 30 files reference
    # Invoke-ScoutAssessment, of which 2 are these board tree data files, leaving 28 -- 7 code,
    # 6 test, 10 documentation, 1 published pipeline example and 4 historical records.

    Tree = @(

        #-------------------------------------------------------------------------------------
        # AB#5956 -- Remove the deprecated assessment entry point
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-dep-code'; Type = 'Task'; ParentId = 5956; Priority = 2
            Title = 'Drop the deprecated export and rename the internal assessment function'
            Tags  = 'azure-scout; thisismydemo; breaking; powershell'
            Description = @'
<p>Invoke-ScoutAssessment was deprecated in v2.4.0 for removal in v3.0.0 and is still exported. This is the removal of a public NAME, not of an implementation -- the unified entry point routes straight into it, so the implementation stays and only the exported name and the internal identifier change.</p>
<p>Seven code files reference it in the working tree: AzureScout.psd1 (the export list), Modules/Public/PublicFunctions/Invoke-AzureScout.ps1 (live internal calls), src/Invoke-ScoutAssessment.ps1 (the definition, whose file name also changes), src/Invoke-ScoutPipeline.ps1 (three call sites), src/report/Get-ScoutDrift.ps1, src/report/renderers/Export-React.ps1 and src/report/renderers/Export-Word.ps1.</p>
<p>Sequence this against AB#5951, which relocates Invoke-AzureScout.ps1. Doing both to the same file in one change makes the diff unreadable and the breakage unattributable; do the rename first, on the file at its current path.</p>
<p>Why now: it is the documented breaking change that justifies the major version, and it has to land in the same release as the fork deletion.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The name removed from the manifest export list.</li>
<li>src/Invoke-ScoutAssessment.ps1 renamed along with the function it defines.</li>
<li>All five internal call sites updated.</li>
<li>A test asserting the removed name throws a command-not-found error after a clean import.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what the assessment does.</li>
<li>Any further deprecation.</li>
</ul>
'@
        }
        @{
            Key = 't-dep-tests'; Type = 'Task'; ParentId = 5956; Priority = 2
            Title = 'Update the six test files that call the deprecated entry point'
            Tags  = 'azure-scout; thisismydemo; testing; breaking'
            Description = @'
<p>Six test files reference the name: tests/Assessment.ReportReturn.Tests.ps1, tests/Pipeline.Tests.ps1, tests/Pipeline.NonTerminatingErrors.Tests.ps1, tests/Report.React.Tests.ps1, tests/StrictModeMemberEnumeration.Tests.ps1 and tests/UnifiedEntryPoint.Tests.ps1.</p>
<p>Two of them are the ones to check carefully. tests/UnifiedEntryPoint.Tests.ps1 exists to prove the unified entry point is the single way in, so it must gain the assertion that the old name is GONE rather than simply stop mentioning it -- that is the regression test for this story. tests/Pipeline.Tests.ps1 and tests/Pipeline.NonTerminatingErrors.Tests.ps1 dot-source Invoke-ScoutPipeline.ps1 directly rather than importing the module, so a renamed dependency will fail to resolve at dot-source time with an error that does not name the rename.</p>
<p>Why now: these fail the instant the rename lands, so they belong in the same piece of work.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Six test files updated to the current name.</li>
<li>tests/UnifiedEntryPoint.Tests.ps1 asserting the removed name throws command-not-found.</li>
<li>The two direct dot-source suites verified to resolve after the rename.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what any of the six asserts about behaviour.</li>
</ul>
'@
        }
        @{
            Key = 't-dep-pipeline'; Type = 'Task'; ParentId = 5956; Priority = 2
            Title = 'Fix the published pipeline example that would break for users'
            Tags  = 'azure-scout; thisismydemo; delivery; breaking'
            Description = @'
<p>.ado/azure-pipelines.yml calls Invoke-ScoutAssessment. It is a published example -- users copy it into their own pipelines -- so leaving it is not a cosmetic miss, it is shipping a breaking change with a broken example alongside it. Anyone who copied it gets a command-not-found on their first v3.0.0 run.</p>
<p>Update it to the unified entry point and check whether the parameters carry across unchanged, rather than assuming the call is a straight substitution.</p>
<p>Call it out explicitly in the v3.0.0 release notes as well as fixing it. A user who copied the file already has the old call in their own repo, and the fixed example does not reach them.</p>
<p>Why now: it is the only user-facing breakage in this story that a user cannot discover by reading the changelog, because it lives in their repo rather than ours.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>.ado/azure-pipelines.yml updated to the unified entry point with parameters verified.</li>
<li>An explicit migration line in the release notes for anyone who copied it.</li>
<li>A check for any other example under .ado or docs that invokes the module.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Restructuring the pipeline example beyond the call change.</li>
</ul>
'@
        }
        @{
            Key = 't-dep-docs'; Type = 'Task'; ParentId = 5956; Priority = 3
            Title = 'Update the ten documentation pages and leave the four historical records alone'
            Tags  = 'azure-scout; thisismydemo; docs; breaking'
            Description = @'
<p>Ten current documentation files name the deprecated entry point: docs/assessment.md, docs/authentication.md, docs/overview.md, docs/parameters.md, docs/folder-structure.md, docs/roadmap.md, docs/design/arg-round-trips.md, docs/design/assessment-registry.md, docs/design/master-plan.md and src/README.md. All ten describe how to use the product today and must be updated.</p>
<p>Four files must NOT be rewritten, because they are the historical record of what shipped and when: CHANGELOG.md, RELEASES.md, docs/changelog.md and .ai/state/HANDOFF.md. Rewriting them would make the v2.4.0 deprecation notice disappear, which is the only place a user upgrading from an older version finds out the change was announced a year of releases in advance.</p>
<p>Add a test asserting the name appears in no source, test, pipeline or current documentation file, with those four explicitly excluded. Without the exclusion list encoded, the next sweep deletes the history.</p>
<p>Why now: the docs are how the breaking change is communicated, and a page still describing the removed name is worse than no page.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Ten documentation files updated to the unified entry point.</li>
<li>A test asserting the absence with the four historical files excluded by name.</li>
<li>The four historical files verified unchanged.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Reopening or editing any earlier release entry.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5957 -- Isolate test temporary directories per run
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-tmp-modules'; Type = 'Task'; ParentId = 5957; Priority = 4
            Title = 'Give the seventeen module test files a per run temporary directory'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Seventeen test files build a temporary directory as Join-Path $env:TEMP with a fixed literal. The names are distinct from each other so they do not collide ACROSS files, but two concurrent runs of the same file collide, and state survives between runs because a fixed path is not removed on failure. Verified in the working tree, with the line each is built on:</p>
<ul>
<li>AI.Module.Tests.ps1 L74, Analytics.Module.Tests.ps1 L49, Compute.Module.Tests.ps1 L49, Containers.Module.Tests.ps1 L40, Databases.Module.Tests.ps1 L46, Hybrid.Module.Tests.ps1 L62, Identity.Module.Tests.ps1 L76, Integration.Module.Tests.ps1 L32, IoT.Module.Tests.ps1 L31, Management.Module.Tests.ps1 L58, Monitor.Module.Tests.ps1 L62, Networking.Module.Tests.ps1 L67, Security.Module.Tests.ps1 L54, Storage.Module.Tests.ps1 L32</li>
<li>OutputFormat.Tests.ps1 L46, Private.Main.Tests.ps1 L21, RunIsolation.Tests.ps1 L21</li>
</ul>
<p>Two files already solve this and are the pattern to copy, not to reinvent: tests/DeclarativeCollectorCutover.Tests.ps1 line 48 and tests/CollectorDefinitionSchema.Tests.ps1 line 32 both build Join-Path ([System.IO.Path]::GetTempPath()) ("&lt;prefix&gt;-" + [guid]::NewGuid().ToString('N')), and both carry a comment explaining exactly this problem. Eight files in the suite already do it.</p>
<p>Why now: the epic adds concurrent work across several stories, and a shared fixed path is the kind of flake that gets blamed on the change under test.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>Seventeen files switched to the per-run GUID pattern.</li>
<li>Cleanup in an AfterAll that runs on failure as well as success.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what any test asserts.</li>
<li>The eight files that already use a per-run path.</li>
</ul>
'@
        }
        @{
            Key = 't-tmp-guard'; Type = 'Task'; ParentId = 5957; Priority = 4
            Title = 'Fix the remaining shared temporary paths and assert the pattern across the suite'
            Tags  = 'azure-scout; thisismydemo; testing'
            Description = @'
<p>Three more fixed temporary paths exist outside the seventeen module tests and are easy to miss because they are single files rather than a shared literal:</p>
<ul>
<li>tests/CollectorStrictMode.Tests.ps1 L240 -- Join-Path ([System.IO.Path]::GetTempPath()) 'AZSC_StrictModeCollectorRows.json', a results file, so two concurrent runs overwrite each other's results rather than each other's fixtures.</li>
<li>tests/ModuleUpdate.Tests.ps1 L28 -- 'azurescout-update-check.txt', which is the PRODUCT'S OWN throttle file. Check whether the test is meant to share it with a real installation before changing it; isolating it may be the fix or may break the thing it tests.</li>
<li>tests/Report.InventoryDrift.Tests.ps1 -- three sites in one file.</li>
</ul>
<p>Then encode the rule: a test asserting no file under tests/ joins a constant literal to the temp path without a per-run component. State it as an allow-list if any file genuinely needs a shared path, so an exception is visible and justified rather than silent.</p>
<p>Why now: the guard is what makes the previous Task stay done. Without it the pattern comes back in the next test written.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The three remaining fixed paths resolved, with an explicit decision recorded for the update throttle file.</li>
<li>An AST assertion over tests/ that every temporary path carries a per-run identifier.</li>
<li>Two concurrent full suite runs on one machine both passing.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing the product's own throttle file location.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#5958 -- Release version three
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-rel-version'; Type = 'Task'; ParentId = 5958; Priority = 2
            Title = 'Bump the version and update the four version pinned documents'
            Tags  = 'azure-scout; thisismydemo; delivery; docs'
            Description = @'
<p>tests/DocsVersionSync.Tests.ps1 is the gate, and it names exactly what has to move together. ModuleVersion in AzureScout.psd1 (line 15) is the source of truth, and four documents are compared against it: CHANGELOG.md's newest version heading, docs/roadmap.md's Current Release, docs/changelog.md's summary table lead row, and a RELEASES.md ledger row for the shipping version. The suite also watches AzureScout.psd1, CHANGELOG.md, RELEASES.md and docs/** for changes, so a doc edit alone will not slip through.</p>
<p>The manifest ReleaseNotes have two hard constraints, both tested: they must LEAD with the shipping version, and they must stay at or under 10,600 characters -- the PowerShell Gallery limit. The current notes are close to that ceiling, so writing the v3.0.0 entry means trimming older entries out of the field, not appending to it. The full history stays in CHANGELOG.md, which the notes already link to.</p>
<p>Write the notes honestly. The v2.11.0 gallery listing still carries notes that were corrected in place after claiming the previous epic completed when it had not. State plainly what shipped and what did not.</p>
<p>Why now: it is the first step of the release and it gates every step after it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>ModuleVersion set to 3.0.0 and all four version-pinned documents updated.</li>
<li>ReleaseNotes leading with the version and under 10,600 characters, with older entries trimmed rather than appended to.</li>
<li>The breaking changes named explicitly: the removed entry point, the removed kill switch, and the deleted module tree.</li>
<li>tests/DocsVersionSync.Tests.ps1 passing.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Reopening any earlier release entry.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-publish'; Type = 'Task'; ParentId = 5958; Priority = 2
            Title = 'Tag the release and publish it to the PowerShell Gallery'
            Tags  = 'azure-scout; thisismydemo; delivery'
            Description = @'
<p>Tag v3.0.0 on main and publish to the gallery. The publishing key is in the vault; do not assume otherwise, and do not report the publish as blocked without attempting it -- that has happened on this project before and the block was invented rather than observed.</p>
<p>Publish only after the full suite is green with the module tree absent, because a gallery version cannot be withdrawn and replaced at the same number. If the tag already exists remotely from an earlier attempt, resolve that before tagging rather than force-moving it.</p>
<p>Why now: it is the point at which the epic's work reaches a user, and nothing after it is reversible.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>An annotated v3.0.0 tag on main, pushed.</li>
<li>The module published to the gallery at 3.0.0.</li>
<li>The gallery listing checked for the release notes rendering correctly and not being truncated.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Any post-release fix, which is a new version.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-install'; Type = 'Task'; ParentId = 5958; Priority = 2
            Title = 'Install from the gallery into a clean session and verify the public surface'
            Tags  = 'azure-scout; thisismydemo; delivery; testing'
            Description = @'
<p>Install the published module from the gallery in a clean PowerShell session -- not the working tree, not a local build -- and verify it imports at 3.0.0 and exposes the expected functions.</p>
<p>The verification worth doing is the one the epic's criteria state: the exported function set matches v2.11.0 apart from the deliberate removal of the deprecated entry point, and calling the removed name gives a command-not-found error. Import succeeding is not the same thing as the surface being right.</p>
<p>Do this on a machine that has an existing Az module set, and do NOT auto-install or auto-update any Az.* module as part of it. Az.Accounts 5.5.1 alongside another version produces a stack overflow at import on this project's machines; an install verification that quietly upgrades a dependency proves nothing about what a real user gets and can brick the session it runs in.</p>
<p>Why now: the gallery package is the artefact users receive, and nothing before this step tests that artefact.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A clean-session install from the gallery, importing at 3.0.0.</li>
<li>The exported function set compared against the v2.11.0 list.</li>
<li>The removed entry point asserted to throw command-not-found.</li>
<li>No Az.* module installed or upgraded during the verification.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>The live tenant run, which is the next Task.</li>
</ul>
'@
        }
        @{
            Key = 't-rel-liverun'; Type = 'Task'; ParentId = 5958; Priority = 2
            Title = 'Run the installed release against a live tenant and compare to the baseline'
            Tags  = 'azure-scout; thisismydemo; delivery; testing'
            Description = @'
<p>Run the gallery-installed v3.0.0 end to end against a live tenant. This is the step that has found what the test suite could not on every previous release of this project -- one live run surfaced seven defects that 1,692 tests missed.</p>
<p>The comparison is against the v2.11.0 baseline, and it must be a comparison rather than a smoke test: worksheet set, per-worksheet row counts, the diagram file's size class, and the run log. That baseline is the only evidence that deleting the fork changed nothing a user sees, and it is the epic's headline claim.</p>
<p>Assert on the run log too. It reports how many collectors ran declarative versus imperative; at v2.11.0 that was 138 and 36, and at v3.0.0 the imperative count must be zero. Zero collector failures is also part of the criterion -- v2.10.0 was the first release to reach it and it should not silently regress.</p>
<p>Run it against the tenant that has been used for every previous baseline. Substituting a different, more reachable tenant makes the comparison meaningless.</p>
<p>Why now: it is the last verification, and the release is not finished without it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A full live run from the gallery-installed module, with diagrams enabled.</li>
<li>Worksheet set and row counts compared against the v2.11.0 baseline.</li>
<li>The run log asserted: zero imperative collectors, zero collector failures, zero leftover background jobs.</li>
<li>The results recorded in the release notes.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Fixing anything the run finds, which is a new work item against v3.0.1.</li>
</ul>
'@
        }

        #-------------------------------------------------------------------------------------
        # AB#6060 -- Bug: the guided wizard is skipped when a common parameter is supplied
        #-------------------------------------------------------------------------------------
        @{
            Key = 't-wiz-fix'; Type = 'Task'; ParentId = 6060; Priority = 3
            Title = 'Count only explicitly supplied non common parameters when opening the wizard'
            Tags  = 'azure-scout; thisismydemo; powershell; cli'
            Description = @'
<p>Modules/Public/PublicFunctions/Invoke-AzureScout.ps1 line 491 reads:</p>
<p>if ($PSBoundParameters.Count -eq 0 -and -not $NoWizard.IsPresent -and (Test-AZSCInteractiveHost))</p>
<p>Every PowerShell common parameter lands in $PSBoundParameters, so the count is one rather than zero and the wizard is skipped. It is not only -Debug: Verbose, ErrorAction, WarningAction, InformationAction, ErrorVariable, WarningVariable, InformationVariable, OutVariable, OutBuffer, PipelineVariable and ProgressAction all suppress it identically.</p>
<p>Change the test to count only explicitly supplied NON-common parameters. Derive the common set from [System.Management.Automation.PSCmdlet]::CommonParameters and ::OptionalCommonParameters rather than hard-coding a list, so a future PowerShell version adding one does not reintroduce the bug.</p>
<p>Do not change $PSBoundParameters itself. The comment immediately below (lines 495-499) records that the wizard's answers are written back into it deliberately, because later branches read it to distinguish explicitly asked for from left at the default. Filtering for the wizard trigger must be local to the trigger.</p>
<p>-NoWizard must keep working as the deliberate opt-out, and Test-AZSCInteractiveHost must keep gating it so automation and CI still fall straight through without prompting.</p>
<p>Why now: it defeats the ordinary act of adding -Debug to investigate a problem, and it affects the first interaction a new user has with the product. GitHub issue 189 is the master record.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>The trigger at line 491 counting only non-common bound parameters.</li>
<li>The common set derived from the runtime rather than hard-coded.</li>
<li>$PSBoundParameters left otherwise untouched.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Changing what the wizard asks or the order it asks it.</li>
<li>Changing -NoWizard or the non-interactive fall-through.</li>
</ul>
'@
        }
        @{
            Key = 't-wiz-tests'; Type = 'Task'; ParentId = 6060; Priority = 3
            Title = 'Add a regression test per common parameter and pin the opt out paths'
            Tags  = 'azure-scout; thisismydemo; testing; cli'
            Description = @'
<p>The fix is one line; what stops it regressing is the test matrix. Add a case per common parameter asserting the wizard still opens on an interactive host -- twelve of them, and derived from the same runtime list the fix uses, so a new common parameter is covered automatically rather than needing a remembered edit.</p>
<p>Pin the three paths that must NOT change alongside it, because a fix that opens the wizard more eagerly is its own defect:</p>
<ul>
<li>-NoWizard bypasses the wizard on an interactive host.</li>
<li>A non-interactive host falls straight through with no prompt, whatever is passed -- this is what stops a scheduled pipeline run blocking forever.</li>
<li>A real, non-common parameter such as -SkipDiagram still bypasses the wizard, since supplying one means the operator has already made their choices.</li>
</ul>
<p>Assert the repro first. Confirm on v2.11.0 that a bare Invoke-AzureScout opens the wizard and Invoke-AzureScout -Debug does not, so the new tests are known to fail before the fix and are not vacuous.</p>
<p>Why now: it goes with the fix, and tests/Invoke-AzureScout.Tests.ps1 already exists to hold it.</p>
<p><strong>In scope:</strong></p>
<ul>
<li>A test per common parameter, driven from the runtime common-parameter list.</li>
<li>Assertions for -NoWizard, the non-interactive host, and a genuine non-common parameter.</li>
<li>The repro confirmed failing before the fix.</li>
</ul>
<p><strong>Out of scope:</strong></p>
<ul>
<li>Testing the wizard's content or question order.</li>
</ul>
'@
        }
    )
}
