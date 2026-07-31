#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Evaluate a single rule against the collect object, returning a finding.

.NOTES
    Supports the seven assert types. Tracks ADO Story AB#5030.
#>
function Invoke-Rule {
    param(
        [Parameter(Mandatory)] $Rule,
        [Parameter(Mandatory)] $Collect,
        [string] $Area,
        [string] $Framework
    )

    $status = 'Unknown'; $evidenceCount = 0; $evidence = @()

    # A rule carries EITHER a `query` (one dataset, filtered) or a `join` (two datasets,
    # correlated) -- never both. `join` is read through the same shape-agnostic accessor the rest
    # of this function uses, because ConvertFrom-Yaml hands back a Hashtable while test fixtures
    # build a pscustomobject, and dotting a missing key throws under StrictMode (AB#6835).
    $hasJoin = if ($Rule -is [hashtable]) { $Rule.ContainsKey('join') -and $null -ne $Rule.join }
               elseif ($Rule -is [System.Collections.IDictionary]) { $Rule.Contains('join') -and $null -ne $Rule['join'] }
               else { $null -ne $Rule.PSObject.Properties['join'] -and $null -ne $Rule.join }

    if ($Rule.manual -or $Rule.assert.type -eq 'manual') {
        # pre-fill with any evidence the scan DID find, then hand to the human
        if ($Rule.query) {
            $evidence = Resolve-JsonPath -InputObject $Collect -Path $Rule.query
            $evidenceCount = $evidence.Count
        }
        $status = 'Manual'
    }
    else {
        try {
            # Assigned INSIDE each branch, not from the `if` as an expression. `$x = if (...) { @() }`
            # returns $null, not an empty array -- the if's output stream enumerates and an empty
            # array enumerates to nothing -- and the very next line reads `.Count`, which then
            # throws under StrictMode. A join that legitimately found no unmatched rows (the PASS
            # case, and the common one) hit that on every rule.
            $matches = $null
            if ($hasJoin) {
                $matches = @(Resolve-RuleJoin -Rule $Rule -Collect $Collect)
            } else {
                $matches = Resolve-JsonPath -InputObject $Collect -Path $Rule.query
            }
        }
        catch {
            # A query that threw (unsupported/invalid JSONPath, or a malformed join block) is an
            # Error, never a silent Pass on countEquals:0 (AB#5083). Surface it so it's visible.
            Write-Warning "Rule $($Rule.id): $(if ($hasJoin) { 'join' } else { "query '$($Rule.query)'" }) failed: $_"
            return [pscustomobject]@{
                Id = $Rule.id; Title = $Rule.title; Framework = $Framework; Area = $Area
                Severity = $Rule.severity; Status = 'Error'; EvidenceCount = 0; Evidence = @()
                Remediation = $Rule.remediation; Manual = [bool]$Rule.manual
            }
        }
        $evidenceCount = $matches.Count
        $evidence = $matches | Select-Object -First 25    # cap evidence payload
        # ConvertFrom-Yaml returns `assert:` as a Hashtable (test fixtures often use a
        # pscustomobject instead), and 'exists'/'notExists' rules legitimately omit a
        # `value:` key. Accessing a missing key/property via dot-notation throws
        # PropertyNotFoundException under Set-StrictMode -Version Latest, so only read
        # .value when it's actually present — the exists/notExists cases below never
        # reference $v. Handle both Hashtable and pscustomobject assert shapes.
        $v = $null
        if ($Rule.assert -is [hashtable]) {
            if ($Rule.assert.ContainsKey('value')) { $v = $Rule.assert.value }
        }
        elseif ($Rule.assert.PSObject.Properties['value']) {
            $v = $Rule.assert.value
        }

        switch ($Rule.assert.type) {
            'countGreaterThan'  { $status = ($evidenceCount -gt  $v) ? 'Pass' : 'Fail' }
            'countEquals'       { $status = ($evidenceCount -eq  $v) ? 'Pass' : 'Fail' }
            'countLessThan'     { $status = ($evidenceCount -lt  $v) ? 'Pass' : 'Fail' }
            'exists'            { $status = ($evidenceCount -gt   0) ? 'Pass' : 'Fail' }
            'notExists'         { $status = ($evidenceCount -eq   0) ? 'Pass' : 'Fail' }
            'percentageAtLeast' {
                $denom = (Resolve-JsonPath -InputObject $Collect -Path $Rule.assert.denominatorQuery).Count
                # No denominator = nothing collected for this dimension -> Unknown,
                # NOT a 0% Fail, which would be misleading (AB#5085).
                if ($denom -le 0) { $status = 'Unknown' }
                else {
                    $pct = $evidenceCount / $denom * 100
                    $status = ($pct -ge $v) ? 'Pass' : (($pct -gt 0) ? 'Partial' : 'Fail')
                }
            }
            default {
                Write-Warning "Rule $($Rule.id): unknown assert type '$($Rule.assert.type)'"
                $status = 'Error'
            }
        }
    }

    [pscustomobject]@{
        Id            = $Rule.id
        Title         = $Rule.title
        Framework     = $Framework
        Area          = $Area
        Severity      = $Rule.severity
        Status        = $status
        EvidenceCount = $evidenceCount
        Evidence      = $evidence
        Remediation   = $Rule.remediation
        Manual        = [bool]$Rule.manual
    }
}
