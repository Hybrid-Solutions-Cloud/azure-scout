#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#6779 — `@(Search-AzGraph ...)` yields the response WRAPPER, not the rows, and that killed
    pagination at four call sites.

    `Search-AzGraph` writes a single un-enumerated `PSResourceGraphResponse` to the pipeline.
    Wrapping the INVOCATION collects that wrapper as one element; wrapping a VARIABLE holding it
    enumerates to the rows. Proven live against a real tenant in one session — same query, same
    process:

        @(Search-AzGraph @p)                -> 1     (the wrapper)
        $r = Search-AzGraph @p; @($r)       -> 111   (the rows)
        $r.Data                             -> 111   (the rows, empty-safe)

    It does not throw. It returns something plausible. Two ways it bites:

      1. A downstream filter on `type` matches nothing, because the wrapper has no `type`
         property, so the dataset is silently empty. That is how Identity/RoleAssignments
         returned 0 rows in a tenant holding 110 of them.
      2. `do { $batch = @(Search-AzGraph @params) } while ($batch.Count -eq 1000)` — the count is
         permanently 1, so the loop can NEVER advance past the first page. Every paged query was
         capped at 1000 rows, including the assessment platform's main query loop.

    Why no existing test caught it: every ARG mock in the suite returns a BARE ARRAY, which
    restates the bug's own assumption. A fixture derived from those mocks cannot fail this way.
    The fake below is wrapper-shaped, which is the whole point of the file.

    No Azure connection.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent

    # A stand-in for PSResourceGraphResponse: carries rows on .Data and does NOT enumerate them
    # when the invocation is wrapped in @(). That second property is the one that matters.
    function New-ArgResponse {
        param([object[]] $Rows)
        [pscustomobject]@{ Data = @($Rows); Count = @($Rows).Count; SkipToken = $null }
    }
}

Describe 'AB#6779 — the four production call sites read .Data, not @(invocation)' {

    # Anchored to source text deliberately. The defect is a SHAPE, and the shape is what must not
    # come back: a future edit that reverts to `@(Search-AzGraph ...)` reintroduces a silent
    # truncation that no behavioural test in this suite would notice.
    It '<File> does not wrap a Search-AzGraph invocation in @()' -ForEach @(
        @{ File = 'src/collect/Invoke-Collect.ps1' }
        @{ File = 'src/ingest/Import-Governance.ps1' }
        @{ File = 'src/collect/Get-ScoutGovernanceDataset.ps1' }
        @{ File = 'src/collect/Get-ScoutOperationalCollectorEnrichment.ps1' }
    ) {
        $source = Get-Content -Raw (Join-Path $script:Root $File)

        # Comments naming the bug are expected and fine; executable code is not.
        $code = ($source -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

        $code | Should -Not -Match '@\(\s*Search-AzGraph' -Because 'wrapping the invocation collects the response wrapper, not the rows'
    }

    It '<File> reads the Data property off the response' -ForEach @(
        @{ File = 'src/collect/Invoke-Collect.ps1' }
        @{ File = 'src/ingest/Import-Governance.ps1' }
        @{ File = 'src/collect/Get-ScoutGovernanceDataset.ps1' }
        @{ File = 'src/collect/Get-ScoutOperationalCollectorEnrichment.ps1' }
    ) {
        $source = Get-Content -Raw (Join-Path $script:Root $File)

        $source | Should -Match "PSObject\.Properties\['Data'\]" -Because 'reading .Data is the only shape that behaves the same when the result is empty'
    }
}

Describe 'AB#6779 — the shape itself, so the reason is testable and not just asserted' {

    It 'wrapping the INVOCATION yields one element — the wrapper' {
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) New-ArgResponse -Rows @(1..111) }

        $wrapped = @(Search-AzGraph -Query 'x')

        $wrapped.Count | Should -Be 1 -Because 'this is the defect: 111 rows collapse to one wrapper'
    }

    It 'reading .Data yields the rows' {
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) New-ArgResponse -Rows @(1..111) }

        $response = Search-AzGraph -Query 'x'
        @($response.Data).Count | Should -Be 111
    }

    It 'reading .Data on an EMPTY result yields zero, not one' {
        # The other half. `@($response)` on an empty result yields the wrapper, so a zero-row
        # answer reads as Count 1 — which is how "no rows" masquerades as "one row".
        function Search-AzGraph { param([Parameter(ValueFromRemainingArguments)] $Rest) New-ArgResponse -Rows @() }

        $response = Search-AzGraph -Query 'x'
        @($response.Data).Count | Should -Be 0
        @($response).Count      | Should -Be 1 -Because 'this is why .Data is required rather than optional'
    }
}

Describe 'AB#6779 — pagination actually advances past the first page' {

    # The assertion that existed at NONE of the four sites. Two full pages then a short one: a
    # loop that reads the wrapper stops after page 1 and returns 1 row; a correct loop returns
    # 1000 + 1000 + 7.
    It 'a paging loop reading .Data walks every page' {
        $script:calls = 0
        function Search-AzGraph {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $script:calls++
            $n = switch ($script:calls) { 1 { 1000 } 2 { 1000 } default { 7 } }
            New-ArgResponse -Rows @(1..$n)
        }

        $rows = @(); $skip = 0
        do {
            $params = @{ Query = 'x'; First = 1000 }
            if ($skip -gt 0) { $params.Skip = $skip }
            $response = Search-AzGraph @params
            $batch = if ($null -ne $response -and $response.PSObject.Properties['Data']) { @($response.Data) } else { @($response) }
            $rows += $batch; $skip += 1000
        } while ($batch.Count -eq 1000)

        $script:calls   | Should -Be 3    -Because 'two full pages must be followed by a third call'
        @($rows).Count  | Should -Be 2007
    }

    It 'the OLD shape stops after one page — the regression this file exists to prevent' {
        $script:calls = 0
        function Search-AzGraph {
            param([Parameter(ValueFromRemainingArguments)] $Rest)
            $script:calls++
            $n = switch ($script:calls) { 1 { 1000 } 2 { 1000 } default { 7 } }
            New-ArgResponse -Rows @(1..$n)
        }

        $rows = @(); $skip = 0
        do {
            $batch = @(Search-AzGraph -Query 'x' -First 1000)   # the defect, reproduced deliberately
            $rows += $batch; $skip += 1000
        } while ($batch.Count -eq 1000)

        $script:calls  | Should -Be 1 -Because 'the wrapper makes Count 1, so the loop never continues'
        @($rows).Count | Should -Be 1 -Because '2007 rows of real data collapse to a single wrapper object'
    }
}
