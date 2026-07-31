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
    . (Join-Path $script:Root 'src/ingest/Import-AdvisorScores.ps1')
}

Describe 'AB#6774 — ArgQueryPack is retired' {

    It 'no longer exists as a file' {
        Test-Path (Join-Path $script:Root 'src/ingest/Invoke-ArgQueryPack.ps1') | Should -BeFalse
    }

    It 'is named by no registry entry' {
        $manifest = Import-PowerShellDataFile (Join-Path $script:Root 'manifests/assessments.psd1')

        foreach ($name in $manifest.Keys) {
            @($manifest[$name].Ingest) | Should -Not -Contain 'ArgQueryPack' -Because "'$name' would pay for six duplicate Resource Graph queries"
        }
    }

    It 'is ignored rather than fatal if a copied manifest still names it' {
        # The value lives in a data file a customer may have copied out of the repo, so the
        # retirement must not turn their manifest into a hard error.
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-ScoutAssessmentCore.ps1')
        $branch = ([regex]"'ArgQueryPack'\s*\{[^}]*\}").Match($source).Value

        $branch | Should -Not -BeNullOrEmpty
        $branch | Should -Not -Match 'Invoke-ArgQueryPack'
        $branch | Should -Match 'Write-Verbose'
    }

    It 'leaves every dataset it used to supply produced by Invoke-Collect' {
        # The whole safety argument for deleting it. If any of these six stops being produced by
        # the collector, retiring the pack silently empties a rule input.
        $collect = Get-Content -Raw (Join-Path $script:Root 'src/collect/Invoke-Collect.ps1')

        foreach ($key in 'subnets', 'nsgPublicInbound', 'orphanedDisks', 'orphanedPips', 'diagnosticCoverage') {
            $collect | Should -Match "(?m)^\s+$key\s*=\s*@'" -Because "ArgQueryPack used to supply '$key' and no longer does"
        }
    }
}

Describe 'AB#6775 — the combined run is reachable from the command line' {

    It 'exposes a parameter, not only the wizard answer' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-AzureScout.ps1')

        $source | Should -Match '\[switch\]\$InventoryAndAssessment'
        $source | Should -Match '\$wizardRunBoth -or \$InventoryAndAssessment\.IsPresent'
    }

    It 'keeps -Both as the short form' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-AzureScout.ps1')

        $source | Should -Match "\[Alias\('Both'\)\]\s*\r?\n\s*\[switch\]\`$InventoryAndAssessment"
    }
}

Describe 'AB#6776 — the collect-once handoff keeps its tags' {

    It 'forces -IncludeTags on the inventory pass when an assessment will consume its rows' {
        # Invoke-Collect already forces IncludeTags on its own raw pass and documents why: the
        # canonical `tags` key is aggregated from the raw container row, which omits the column
        # unless asked. The inventory pass had no such rule, so the combined run produced an
        # empty tags aggregation while the slower path produced the real one.
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-AzureScout.ps1')

        $source | Should -Match '\$extractionIncludeTags = \$IncludeTags'
        $source | Should -Match 'if \(\$deferredAssessArgs -and -not \$IncludeTags\)'
        $source | Should -Match '-IncludeTags \$extractionIncludeTags'
    }

    It 'does not force it on an inventory-only run' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-AzureScout.ps1')

        # The override is gated on $deferredAssessArgs, so a plain inventory run is untouched
        # and keeps paying nothing for a column its report was not asked to show.
        $source | Should -Not -Match '\$extractionIncludeTags = \[switch\]\$true\s*\r?\n\s*\$ExtractionData'
    }
}

Describe 'AB#6777 — AdvisorScores reuses the inventory rows' {

    BeforeEach {
        $script:CmdletCalled = $false
        function Get-AzSubscription { param([Parameter(ValueFromRemainingArguments)] $Rest) $script:CmdletCalled = $true; @() }
        function Get-AzAdvisorRecommendation { param([Parameter(ValueFromRemainingArguments)] $Rest) $script:CmdletCalled = $true; @() }
        function Get-AzContext { $null }
        function Set-AzContext { param([Parameter(ValueFromRemainingArguments)] $Rest) }

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
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            @([pscustomobject]@{ Id = 'other-sub'; Name = 'Other'; State = 'Enabled'; TenantId = 'tenant-1' })
        }
        function Get-AzAdvisorRecommendation { param([Parameter(ValueFromRemainingArguments)] $Rest) @() }
        function Set-AzContext { param($Subscription, $Tenant, $ErrorAction) $script:Restored += [string]$Subscription }

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
        function Get-AzSubscription { param([Parameter(ValueFromRemainingArguments)] $Rest) throw 'boom' }
        function Set-AzContext { param($Subscription, $Tenant, $ErrorAction) $script:Restored += [string]$Subscription }

        { Import-AdvisorScores -Collect ([pscustomobject]@{}) } | Should -Throw

        $script:Restored[-1] | Should -Be 'original-sub'
    }
}

Describe 'AB#6777 — the assessment core hands the inventory advisories over' {

    It 'passes $FromInventory.Advisories into the ingest' {
        $source = Get-Content -Raw (Join-Path $script:Root 'src/Invoke-ScoutAssessmentCore.ps1')

        $source | Should -Match "\`$advisorArgs\.FromInventory = @\(\`$FromInventory\.Advisories\)"
    }
}
