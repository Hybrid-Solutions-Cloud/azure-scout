#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6773 — the four collect-once defects (audit section 10).

    "Collect once" was already the design and mostly already built. Four defects stood between
    the code and it, and each one wasted or corrupted work that had already been done correctly:

      1. AB#6774 — ArgQueryPack re-queried six datasets Invoke-Collect had just collected, and
         overwrote the good copies with worse ones. Two of its queries computed a percentage
         with no divide-by-zero guard where the collector's has one; a third projected untyped
         where the collector casts; a fourth was fetched and never merged at all. A comment in
         the file recorded that an earlier -Force replace had already caused a live incident.
      2. AB#6775 — the combined run was reachable only by answering a wizard prompt, so CI and
         scripted callers could not reach the collect-once path at all.
      3. AB#6776 — the collect-once handoff silently lost tags. The assessment-only path got
         them; the cheaper path did not.
      4. AB#6777 — AdvisorScores re-fetched, through a slower per-subscription API, rows the
         inventory pass already had in memory, and left the caller's Az context pointing at
         whichever subscription happened to be last.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path -Path $script:Root -ChildPath 'src/ingest/Import-AdvisorScores.ps1')
}

Describe 'AB#6774 — ArgQueryPack is retired' {

    It 'no longer exists as a file' {
        Test-Path (Join-Path -Path $script:Root -ChildPath 'src/ingest/Invoke-ArgQueryPack.ps1') | Should -BeFalse
    }

    It 'is named by no registry entry' {
        $manifest = Import-PowerShellDataFile (Join-Path -Path $script:Root -ChildPath 'manifests/assessments.psd1')

        foreach ($name in $manifest.Keys) {
            @($manifest[$name].Ingest) | Should -Not -Contain 'ArgQueryPack' -Because "'$name' would pay for six duplicate Resource Graph queries"
        }
    }

    It 'is ignored rather than fatal if a copied manifest still names it' {
        # The value lives in a data file a customer may have copied out of the repo, so the
        # retirement must not turn their manifest into a hard error.
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-ScoutAssessmentCore.ps1')
        $branch = ([regex]"'ArgQueryPack'\s*\{[^}]*\}").Match($source).Value

        $branch | Should -Not -BeNullOrEmpty
        $branch | Should -Not -Match 'Invoke-ArgQueryPack'
        $branch | Should -Match 'Write-Verbose'
    }

    It 'leaves every dataset it used to supply produced by Invoke-Collect' {
        # The whole safety argument for deleting it. If any of these six stops being produced by
        # the collector, retiring the pack silently empties a rule input.
        $collect = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/collect/Invoke-Collect.ps1')

        foreach ($key in 'subnets', 'nsgPublicInbound', 'orphanedDisks', 'orphanedPips', 'diagnosticCoverage') {
            $collect | Should -Match "(?m)^\s+$key\s*=\s*@'" -Because "ArgQueryPack used to supply '$key' and no longer does"
        }
    }
}

Describe 'AB#6775 — the combined run is reachable from the command line' {

    It 'exposes a parameter, not only the wizard answer' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AzureScout.ps1')

        $source | Should -Match '\[switch\]\$InventoryAndAssessment'
        $source | Should -Match '\$wizardRunBoth -or \$InventoryAndAssessment\.IsPresent'
    }

    It 'keeps -Both as the short form' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AzureScout.ps1')

        $source | Should -Match "\[Alias\('Both'\)\]\s*\r?\n\s*\[switch\]\`$InventoryAndAssessment"
    }
}

Describe 'AB#6776 — the collect-once handoff keeps its tags' {

    It 'forces -IncludeTags on the inventory pass when an assessment will consume its rows' {
        # Invoke-Collect already forces IncludeTags on its own raw pass and documents why: the
        # canonical `tags` key is aggregated from the raw container row, which omits the column
        # unless asked. The inventory pass had no such rule, so the combined run produced an
        # empty tags aggregation while the slower path produced the real one.
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AzureScout.ps1')

        $source | Should -Match '\$extractionIncludeTags = \$IncludeTags'
        $source | Should -Match 'if \(\$deferredAssessArgs -and -not \$IncludeTags\)'
        $source | Should -Match '-IncludeTags \$extractionIncludeTags'
    }

    It 'does not force it on an inventory-only run' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AzureScout.ps1')

        # The override is gated on $deferredAssessArgs, so a plain inventory run is untouched
        # and keeps paying nothing for a column its report was not asked to show.
        $source | Should -Not -Match '\$extractionIncludeTags = \[switch\]\$true\s*\r?\n\s*\$ExtractionData'
    }
}

Describe 'AB#6777 — AdvisorScores reuses the inventory rows' {

    BeforeEach {
        $script:CmdletCalled = $false
        function Get-AzSubscription {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) $script:CmdletCalled = $true; @() }
        function Get-AzAdvisorRecommendation {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) $script:CmdletCalled = $true; @() }
        function Get-AzContext { $null }
        function Set-AzContext {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) }

        $script:Rows = @(
            [pscustomobject]@{
                subscriptionId = 'sub-1'
                properties     = [pscustomobject]@{
                    category         = 'Cost'
                    impact           = 'High'
                    impactedField    = 'Microsoft.Compute/virtualMachines'
                    impactedValue    = 'vm-1'
                    shortDescription = [pscustomobject]@{ problem = 'Right-size'; solution = 'Resize it' }
                }
            }
        )
    }

    It 'makes no Azure call when the inventory rows are handed over' {
        $collect = [pscustomobject]@{}

        $result = Import-AdvisorScores -Collect $collect -FromInventory $script:Rows

        $script:CmdletCalled | Should -BeFalse
        @($result.advisor).Count | Should -Be 1
    }

    It 'shapes the rows into the field names the rule files query by' {
        # `$.advisor[?(@.Category == 'Cost' && @.Impact == 'High')]` is a real rule query. A
        # shape difference between the two sources would make findings depend on how the run
        # was started, which is the worst possible way for an assessment to vary.
        $result = Import-AdvisorScores -Collect ([pscustomobject]@{}) -FromInventory $script:Rows
        $row = @($result.advisor)[0]

        $row.Category                 | Should -Be 'Cost'
        $row.Impact                   | Should -Be 'High'
        $row.ImpactedField            | Should -Be 'Microsoft.Compute/virtualMachines'
        $row.ImpactedValue            | Should -Be 'vm-1'
        $row.Subscription             | Should -Be 'sub-1'
        $row.ShortDescriptionProblem  | Should -Be 'Right-size'
        $row.ShortDescriptionSolution | Should -Be 'Resize it'
    }

    It 'survives a row whose properties bag is missing the optional keys' {
        # Raw Resource Graph rows are whatever ARM indexed. Under StrictMode a chained dot into
        # an absent key throws rather than returning $null, which is how sparse payloads have
        # cost this codebase whole worksheets before.
        $sparse = @([pscustomobject]@{ subscriptionId = 'sub-2'; properties = [pscustomobject]@{ category = 'Security' } })

        $result = Import-AdvisorScores -Collect ([pscustomobject]@{}) -FromInventory $sparse
        $row = @($result.advisor)[0]

        $row.Category                | Should -Be 'Security'
        $row.Impact                  | Should -BeNullOrEmpty
        $row.ShortDescriptionProblem | Should -BeNullOrEmpty
    }

    It 'falls back to the cmdlet sweep when no inventory rows are supplied' {
        $null = Import-AdvisorScores -Collect ([pscustomobject]@{})

        $script:CmdletCalled | Should -BeTrue
    }

    It 'restores the caller original subscription context after the sweep' {
        # The loop calls Set-AzContext per subscription and used to leave the caller wherever it
        # finished, so anything running after an assessment in the same session inherited a
        # different subscription.
        $script:Restored = @()
        function Get-AzContext {
            [pscustomobject]@{
                Tenant       = [pscustomobject]@{ Id = 'tenant-1' }
                Subscription = [pscustomobject]@{ Id = 'original-sub' }
            }
        }
        function Get-AzSubscription {
                        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest)
            @([pscustomobject]@{ Id = 'other-sub'; Name = 'Other'; State = 'Enabled'; TenantId = 'tenant-1' })
        }
        function Get-AzAdvisorRecommendation {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) @() }
        function Set-AzContext {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param($Subscription, $Tenant, $ErrorAction) $script:Restored += [string]$Subscription }

        $null = Import-AdvisorScores -Collect ([pscustomobject]@{})

        $script:Restored[-1] | Should -Be 'original-sub'
    }

    It 'restores the context even when the sweep throws' {
        $script:Restored = @()
        function Get-AzContext {
            [pscustomobject]@{
                Tenant       = [pscustomobject]@{ Id = 'tenant-1' }
                Subscription = [pscustomobject]@{ Id = 'original-sub' }
            }
        }
        function Get-AzSubscription {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param([Parameter(ValueFromRemainingArguments)] $Rest) throw 'boom' }
        function Set-AzContext {             [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Mock/shadow function must declare the full real-cmdlet signature so PowerShell parameter binding accepts every argument the code under test passes; not every parameter is exercised by this test.')]
param($Subscription, $Tenant, $ErrorAction) $script:Restored += [string]$Subscription }

        { Import-AdvisorScores -Collect ([pscustomobject]@{}) } | Should -Throw

        $script:Restored[-1] | Should -Be 'original-sub'
    }
}

Describe 'AB#6777 — the assessment core hands the inventory advisories over' {

    It 'passes $FromInventory.Advisories into the ingest' {
        $source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-ScoutAssessmentCore.ps1')

        $source | Should -Match "\`$advisorArgs\.FromInventory = @\(\`$FromInventory\.Advisories\)"
    }
}

Describe 'AB#6737 — the deferred assessment (and its PDF) renders after the diagram is built' {
    # A live end-to-end run needs a real Azure connection, so -- matching this file's existing
    # style for Invoke-AzureScout-level checks (AB#6775/6776 above) -- this pins the ORDERING
    # the source code commits to, by asserting the relative position of the markers that bound
    # each phase. A regression that moves the deferred-assessment call back above the diagram
    # build (or frees $ExtractionData before the call can use it) fails this test even though
    # nothing here executes the run.
    BeforeAll {
        $script:Source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AzureScout.ps1')

        function Get-ScoutSourceIndex {
            param([string]$Pattern)
            $m = [regex]::Match($script:Source, $Pattern)
            $m.Success | Should -BeTrue -Because "expected to find '$Pattern' in Invoke-AzureScout.ps1"
            return $m.Index
        }
    }

    It 'still builds the diagram inside Start-AZSCExtraJobs before anything unpacks $ExtractionData for it' {
        # Sanity check on the fixture itself: $DDFile is created, then handed to
        # Start-AZSCExtraJobs (which builds the diagram synchronously, AB#5649), before the
        # deferred-assessment call this Describe block is really testing.
        $ddFileIdx      = Get-ScoutSourceIndex '\$DDFile = Join-Path \$DefaultPath \$DDName'
        $extraJobsIdx   = Get-ScoutSourceIndex '\$ExtraData = Start-AZSCExtraJobs\b'
        $ddFileIdx | Should -BeLessThan $extraJobsIdx
    }

    It 'calls Start-AZSCExtraJobs (which builds the diagram) before the deferred assessment call' {
        # AB#6737 -- this used to be reversed: the deferred assessment (and its PDF, AB#379)
        # rendered before $DDFile existed at all, so a combined run could never have a diagram
        # ready in time to embed it.
        $extraJobsIdx    = Get-ScoutSourceIndex '\$ExtraData = Start-AZSCExtraJobs\b'
        $deferredCallIdx = Get-ScoutSourceIndex 'Invoke-ScoutAssessmentCore @deferredAssessArgs -FromInventory \$ExtractionData'
        $extraJobsIdx | Should -BeLessThan $deferredCallIdx
    }

    It 'keeps $ExtractionData alive (does not Remove-Variable it) until after the deferred assessment call' {
        $deferredCallIdx = Get-ScoutSourceIndex 'Invoke-ScoutAssessmentCore @deferredAssessArgs -FromInventory \$ExtractionData'
        $removeVarIdx    = Get-ScoutSourceIndex 'Remove-Variable -Name ExtractionData -ErrorAction SilentlyContinue'
        $deferredCallIdx | Should -BeLessThan $removeVarIdx
    }

    It 'unpacks $Resources/$Advisories/etc. from $ExtractionData before the diagram/assessment ordering point, so neither reads stale data' {
        # The unpack must happen before Start-AZSCExtraJobs (which consumes $Resources/
        # $Advisories/etc. by value) and, since nothing between the unpack and the deferred call
        # reassigns those variables, the same values reach both the diagram build and the
        # (now-later) assessment call unchanged.
        $unpackIdx    = Get-ScoutSourceIndex '\$Resources = \$ExtractionData\.Resources'
        $extraJobsIdx = Get-ScoutSourceIndex '\$ExtraData = Start-AZSCExtraJobs\b'
        $unpackIdx | Should -BeLessThan $extraJobsIdx
    }

    It 'runs the deferred assessment before Start-AZSCProcessOrchestration (kept close to the diagram build, not deferred further than needed)' {
        $deferredCallIdx = Get-ScoutSourceIndex 'Invoke-ScoutAssessmentCore @deferredAssessArgs -FromInventory \$ExtractionData'
        $processIdx      = Get-ScoutSourceIndex 'Start-AZSCProcessOrchestration -Subscriptions \$Subscriptions'
        $deferredCallIdx | Should -BeLessThan $processIdx
    }
}

Describe 'AB#7185 — the deferred assessment writes into the SAME run folder as the inventory pass' {
    # A live end-to-end run needs a real Azure connection, so -- matching this file's existing
    # style for Invoke-AzureScout-level checks above -- this pins the fix by source position
    # rather than executing the run. Before this fix, $deferredAssessArgs.OutputPath was set once
    # at the "-Assessment" argument-building block to the bare $ReportDir, and never touched again
    # -- so Invoke-ScoutAssessmentCore (which always nests its own dated subfolder under whatever
    # OutputPath it receives) wrote outside the inventory run folder instead of inside it. A
    # regression that removes the retarget line, or that moves it before $DefaultPath exists or
    # after the deferred call already ran, fails this test even though nothing here executes the
    # run.
    BeforeAll {
        $script:Source = Get-Content -Raw (Join-Path -Path $script:Root -ChildPath 'src/Invoke-AzureScout.ps1')

        function Get-ScoutSourceIndex {
            param([string]$Pattern)
            $m = [regex]::Match($script:Source, $Pattern)
            $m.Success | Should -BeTrue -Because "expected to find '$Pattern' in Invoke-AzureScout.ps1"
            return $m.Index
        }
    }

    It 'retargets $deferredAssessArgs.OutputPath to $DefaultPath, guarded on $deferredAssessArgs being set' {
        Get-ScoutSourceIndex 'if\s*\(\$deferredAssessArgs\)\s*\{\s*\$deferredAssessArgs\.OutputPath\s*=\s*\$DefaultPath\s*\}' | Out-Null
    }

    It 'retargets OutputPath after $DefaultPath is assigned from $ReportingPath, not before' {
        $defaultPathIdx = Get-ScoutSourceIndex '\$DefaultPath\s*=\s*\$ReportingPath\.DefaultPath'
        $retargetIdx    = Get-ScoutSourceIndex 'if\s*\(\$deferredAssessArgs\)\s*\{\s*\$deferredAssessArgs\.OutputPath\s*=\s*\$DefaultPath\s*\}'
        $defaultPathIdx | Should -BeLessThan $retargetIdx
    }

    It 'retargets OutputPath before the deferred Invoke-ScoutAssessmentCore call consumes it' {
        $retargetIdx     = Get-ScoutSourceIndex 'if\s*\(\$deferredAssessArgs\)\s*\{\s*\$deferredAssessArgs\.OutputPath\s*=\s*\$DefaultPath\s*\}'
        $deferredCallIdx = Get-ScoutSourceIndex 'Invoke-ScoutAssessmentCore @deferredAssessArgs -FromInventory \$ExtractionData'
        $retargetIdx | Should -BeLessThan $deferredCallIdx
    }

    It 'no longer leaves the stale bare-$ReportDir assignment as the last word on $deferredAssessArgs.OutputPath' {
        # The original assignment at the -Assessment argument-building block is fine to keep (it
        # seeds a sane default before $DefaultPath exists yet) -- what must never regress is it
        # being the ONLY assignment. This is a belt-and-suspenders duplicate of the two ordering
        # tests above, expressed as a straight count so a future refactor that deletes the
        # retarget line without deleting the seed assignment still fails obviously.
        $assignments = [regex]::Matches($script:Source, '\$deferredAssessArgs\.OutputPath\s*=')
        $assignments.Count | Should -BeGreaterThan 0
        $retargetAssignments   = [regex]::Matches($script:Source, '\$deferredAssessArgs\.OutputPath\s*=\s*\$DefaultPath')
        $retargetAssignments.Count | Should -BeGreaterThan 0
    }
}
