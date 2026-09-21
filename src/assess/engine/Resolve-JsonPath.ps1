#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Resolve a JSONPath expression against an object using the Newtonsoft engine
    that ships with PowerShell 7.

.NOTES
    Tracks ADO Story AB#5029.
#>
function New-ScoutQueryContext {
    param([Parameter(Mandatory)] $InputObject)

    # Owned by one immutable assessment snapshot, never a module/global cache. Parse lazily
    # so manual-only assessments do not pay for a JSON conversion (AB#9303).
    [pscustomobject]@{ InputObject = $InputObject; Token = $null; ParseCount = 0 }
}

function Resolve-JsonPath {
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Path,
        [AllowNull()] $QueryContext
    )
    # A null/blank path is a legitimate "no query" (e.g. manual rules) -> empty set.
    # NOTE: `return @()` collapses to $null once it crosses the function-return
    # pipeline (a well-known PowerShell empty-array-unwrapping gotcha), which then
    # blows up every `.Count` caller under Set-StrictMode. Write-Output -NoEnumerate
    # preserves the (possibly empty) array identity across the return boundary.
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Output -InputObject @() -NoEnumerate
        return
    }

    if ($null -eq $QueryContext) { $QueryContext = New-ScoutQueryContext -InputObject $InputObject }
    if (-not [object]::ReferenceEquals($QueryContext.InputObject, $InputObject)) {
        throw 'The query context belongs to a different assessment input snapshot.'
    }
    if ($null -eq $QueryContext.Token) {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        if (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level DEBUG -Message 'Assessment query index build started.'
        }
        $json = $InputObject | ConvertTo-Json -Depth 100
        $QueryContext.Token = [Newtonsoft.Json.Linq.JToken]::Parse($json)
        $QueryContext.ParseCount++
        if (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level DEBUG -Message ('Assessment query index built: elapsed={0}; characters={1}' -f $timer.Elapsed, $json.Length)
        }
    }
    $token = $QueryContext.Token

    # A query that THROWS (unsupported/invalid JSONPath) must NOT collapse into an
    # empty result set — that would let a broken query score as a Pass on
    # countEquals:0 asserts (AB#5083). Rethrow so Invoke-Rule can mark it Error.
    $results = $token.SelectTokens($Path, $false)
    Write-Output -InputObject @($results) -NoEnumerate
}
