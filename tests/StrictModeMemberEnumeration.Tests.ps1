<#
    AB#5633 — a full inventory run aborted with

        The property 'ReservationRecomen' cannot be found on this object.

    Every src/*.ps1 calls Set-StrictMode -Version Latest at file scope and AzureScout.psm1
    dot-sources them, so the whole module — including the v1 inventory path — runs strict.
    Under StrictMode, member enumeration over a collection throws when the enumeration
    yields NOTHING AT ALL, which is what an empty collection on every element produces.

    That distinction is the entire bug and is not obvious, so it is pinned here: a $null
    value is safe, an empty collection is not. Anyone "simplifying" Get-AZSCCollectedValue
    back to $APIResults.<Name> reintroduces a crash that only fires against real tenants.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src/Get-AZTICollectedValue.ps1')
    # Get-AZSCIdSegment (AB#5671) guards the FIXED .split('/')[8] index ~30 collectors use to pull
    # a name out of a related resource id -- an out-of-range index THROWS under StrictMode, where
    # without it the same expression quietly returned $null.
    . (Join-Path -Path $script:RepoRoot -ChildPath 'src' -AdditionalChildPath 'Get-AZSCIdSegment.ps1')
}

Describe 'StrictMode member enumeration — the behaviour that caused AB#5633' {

    It 'does NOT throw when every element carries a $null value' {
        # Two elements, key present, value $null on both: enumeration still yields two
        # nulls, so PowerShell finds the property. This case always worked.
        $Collection = @(@{ Key = $null }, @{ Key = $null })
        { Set-StrictMode -Version Latest; $null = $Collection.Key } | Should -Not -Throw
    }

    It 'DOES throw when every element carries an empty collection' {
        # The real shape: the Consumption reservationRecommendations API returns
        # { "value": [] } for a subscription with no recommendations. Empty collections
        # flatten away, the enumeration yields nothing, and StrictMode calls the property
        # missing even though every element carries the key.
        $Collection = @(@{ Key = @() }, @{ Key = @() })
        { Set-StrictMode -Version Latest; $null = $Collection.Key } |
            Should -Throw -ExpectedMessage "*cannot be found on this object*"
    }

    It 'DOES throw on an empty collection even with a single element' {
        $Collection = @(@{ Key = @() })
        { Set-StrictMode -Version Latest; $null = $Collection.Key } |
            Should -Throw -ExpectedMessage "*cannot be found on this object*"
    }

    It 'does NOT throw when at least one element carries a value' {
        $Collection = @(@{ Key = @() }, @{ Key = 'something' })
        { Set-StrictMode -Version Latest; $null = $Collection.Key } | Should -Not -Throw
    }
}

Describe 'Get-AZSCCollectedValue' {

    It 'returns nothing instead of throwing when every element is an empty collection' {
        Set-StrictMode -Version Latest
        $Collection = @(@{ ReservationRecomen = @() }, @{ ReservationRecomen = @() })
        $Result = Get-AZSCCollectedValue -InputObject $Collection -Name 'ReservationRecomen'
        @($Result).Count | Should -Be 0
    }

    It 'accumulates onto an existing array without adding anything' {
        Set-StrictMode -Version Latest
        $Resources = @('existing')
        $Collection = @(@{ Key = @() }, @{ Key = @() })
        $Resources += Get-AZSCCollectedValue -InputObject $Collection -Name 'Key'
        @($Resources).Count | Should -Be 1
    }

    It 'returns every value when the elements do carry data' {
        Set-StrictMode -Version Latest
        $Collection = @(@{ Key = 'a' }, @{ Key = 'b' })
        $Result = @(Get-AZSCCollectedValue -InputObject $Collection -Name 'Key')
        $Result | Should -Be @('a', 'b')
    }

    It 'flattens collection values the same way member enumeration did' {
        Set-StrictMode -Version Latest
        $Collection = @(@{ Key = @(1, 2) }, @{ Key = @(3) })
        $Result = @(Get-AZSCCollectedValue -InputObject $Collection -Name 'Key')
        $Result | Should -Be @(1, 2, 3)
    }

    It 'preserves $null values so per-element alignment is unchanged' {
        Set-StrictMode -Version Latest
        $Collection = @(@{ Key = $null }, @{ Key = 'b' })
        $Result = @(Get-AZSCCollectedValue -InputObject $Collection -Name 'Key')
        $Result.Count | Should -Be 2
    }

    It 'tolerates a $null input object' {
        Set-StrictMode -Version Latest
        { Get-AZSCCollectedValue -InputObject $null -Name 'Key' } | Should -Not -Throw
        @(Get-AZSCCollectedValue -InputObject $null -Name 'Key').Count | Should -Be 0
    }

    It 'tolerates an empty input collection' {
        Set-StrictMode -Version Latest
        @(Get-AZSCCollectedValue -InputObject @() -Name 'Key').Count | Should -Be 0
    }

    It 'tolerates $null elements inside the collection' {
        Set-StrictMode -Version Latest
        $Collection = @($null, @{ Key = 'a' }, $null)
        $Result = @(Get-AZSCCollectedValue -InputObject $Collection -Name 'Key')
        $Result | Should -Be @('a')
    }

    It 'skips elements that do not carry the key at all' {
        Set-StrictMode -Version Latest
        $Collection = @(@{ Other = 1 }, @{ Key = 'a' })
        $Result = @(Get-AZSCCollectedValue -InputObject $Collection -Name 'Key')
        $Result | Should -Be @('a')
    }

    It 'reads PSCustomObject elements as well as dictionaries' {
        Set-StrictMode -Version Latest
        $Collection = @([pscustomobject]@{ Key = 'a' }, [pscustomobject]@{ Other = 2 })
        $Result = @(Get-AZSCCollectedValue -InputObject $Collection -Name 'Key')
        $Result | Should -Be @('a')
    }

    It 'accepts a single dictionary that was unwrapped from a one-element array' {
        Set-StrictMode -Version Latest
        $Result = @(Get-AZSCCollectedValue -InputObject @{ Key = 'a' } -Name 'Key')
        $Result | Should -Be @('a')
    }
}

Describe 'Start-AZSCExtractionOrchestration reads API results safely' {

    BeforeAll {
        # Comment lines stripped: the fix carries an explanation that necessarily quotes the
        # broken expression, and matching that would defeat the check.
        $Raw = Get-Content -Path (Join-Path -Path $script:RepoRoot -ChildPath 'src/Start-AZTIExtractionOrchestration.ps1')
        $script:Orchestration = (($Raw | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
    }

    It 'no longer member-enumerates $APIResults for any consumed API field' {
        foreach ($Field in 'ResourceHealth', 'AdvisorScore', 'ReservationRecommendations',
                           'PolicyAssignments', 'PolicyDefinitions', 'PolicySetDefinitions') {
            $script:Orchestration | Should -Not -Match ([regex]::Escape('$APIResults.' + $Field))
        }
    }

    It 'routes all six consumed API fields through Get-AZSCCollectedValue' {
        foreach ($Field in 'ResourceHealth', 'AdvisorScore', 'ReservationRecommendations',
                           'PolicyAssignments', 'PolicyDefinitions', 'PolicySetDefinitions') {
            $script:Orchestration | Should -Match ([regex]::Escape("-Name '$Field'"))
        }
    }

    It 'does not append REST managed identities because Resource Graph owns that dataset' {
        $script:Orchestration | Should -Not -Match ([regex]::Escape("-Name 'ManagedIdentities'"))
        $script:Orchestration | Should -Match ([regex]::Escape('$apiFallbackArgs.SkipManagedIdentities = $true'))
    }
}

Describe 'The v1 inventory engine runs outside StrictMode' {

    # The forked ARI engine was written without StrictMode and carries ~800 property reads
    # that are only valid without it. The v2 assessment platform under src/ sets
    # `Set-StrictMode -Version Latest` at FILE scope, and the .psm1 dot-sources those files,
    # so StrictMode leaked into the whole module and made the engine abort on normal Azure
    # responses — in a different place on every tenant, because the faults are data-dependent.
    # StrictMode is dynamically scoped, so each engine entry point opts out for its own call
    # tree. Removing these turns a working run back into a tenant-specific crash. (AB#5633)

    $EntryPoints = @(
        'src/Start-AZTIExtractionOrchestration.ps1'
        'src/Start-AZTIProcessOrchestration.ps1'
        'src/Start-AZTIReporOrchestration.ps1'
        'src/pipeline/Start-ScoutExtraJobs.ps1'
        'src/report/renderers/inventory/style/Start-AZSCExcelCustomization.ps1'
    )

    It '<_> opts out of StrictMode' -ForEach $EntryPoints {
        $Text = Get-Content -Raw -Path (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath $_)
        $Text | Should -Match 'Set-StrictMode -Off'
    }

    It 'the assessment platform still runs UNDER StrictMode' {
        # The opt-out must stay scoped to the v1 engine. src/ was written for StrictMode and
        # its tests depend on it.
        $Root = Split-Path -Parent $PSScriptRoot
        $Assessment = Get-Content -Raw -Path (Join-Path -Path $Root -ChildPath 'src/Invoke-ScoutAssessmentCore.ps1')
        $Assessment | Should -Match 'Set-StrictMode -Version Latest'
        $Assessment | Should -Not -Match 'Set-StrictMode -Off'
    }

    It 'does not disable StrictMode module-wide' {
        # A blanket opt-out in the .psm1 would silently strip StrictMode from the assessment
        # platform too.
        $Root = Split-Path -Parent $PSScriptRoot
        $Psm1 = Get-Content -Path (Join-Path -Path $Root -ChildPath 'AzureScout.psm1') | Where-Object { $_ -notmatch '^\s*#' }
        ($Psm1 -join "`n") | Should -Not -Match 'Set-StrictMode -Off'
    }
}

# The 'An empty job set is a valid state' tests that stood here exercised Wait-AZSCJob, which
# AB#5649 DELETED — the run orchestration starts no background jobs at all now, so there is no
# job list to be empty. tests/DeterministicPipeline.Tests.ps1 carries the forward-looking guard
# (the pipeline and the diagram lookup must start no jobs). Only the caller-side check survives,
# because building a name list off a Where-Object that matches nothing is a general trap.
Describe 'Callers never member-enumerate an empty Get-Job result' {

    It 'callers build the job list without member-enumerating an empty result' {
        foreach ($File in 'src/Start-AZTIProcessOrchestration.ps1',
                          'src/Invoke-AzureScout.ps1') {
            $Raw = Get-Content -Path (Join-Path -Path $script:RepoRoot -ChildPath $File)
            $Active = ($Raw | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
            $Active | Should -Not -Match '\(Get-Job \| Where-Object.*\)\.Name'
        }
    }
}

Describe 'Job waits never member-enumerate a possibly-empty handle collection' {

    # The Start-AZTIProcessJob assertion that stood here is gone with the file: AB#5649 deleted
    # the resource-processing runspace machinery outright, so there is no handle collection left
    # to member-enumerate. tests/Private.Processing.Tests.ps1 pins the deletion, and
    # tests/DeterministicPipeline.Tests.ps1 pins that the replacement starts no jobs at all.
    # The diagram subsystem still uses jobs, so its assertion stays.

    It 'Start-AZTIDiagramJob no longer reads the non-existent .Runspace property' {
        # PowerShellAsyncResult has no .Runspace, so the old condition was always false and the
        # wait was a no-op. AB#5649 removed the whole runspace fan-out this guarded, so the file
        # now only MENTIONS the expression in the note explaining what went. Strip comments with
        # the tokenizer, not a line regex — that note is a <# … #> block whose inner lines do
        # not start with '#', so a regex strip matches the prose instead of the code.
        $Text = Get-Content -Raw -Path (Join-Path -Path $script:RepoRoot -ChildPath 'src/pipeline/diagram/Start-ScoutDiagramJob.ps1')
        $Tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$null)
        $Code = ($Tokens | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join ' '

        $Code | Should -Not -Match ([regex]::Escape('$Job.Runspace.IsCompleted'))
        $Code | Should -Not -Match 'BeginInvoke'
    }
}
