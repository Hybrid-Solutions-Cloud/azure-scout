#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Load rule files matching the supplied glob patterns.

.PARAMETER Overrides
    Optional hashtable of ruleId -> override, sourced from a Scout config file
    (Import-ScoutConfig's RuleOverrides, AB#373/#375). Each entry either:
      - is a bare scalar, applied as the rule's new `assert.value` (the common
        "threshold override" case, e.g. loosen/tighten a countLessThan bound), or
      - is a hashtable/pscustomobject with a `value` and/or `type` key, applied
        onto the rule's existing `assert.value` / `assert.type` respectively.
    Rule ids absent from Overrides, or rules with no `assert` block (manual
    rules), are left untouched. A $null/empty map is a no-op.

.NOTES
    Requires the powershell-yaml module. Tracks ADO Story AB#5028.
#>
function Get-RuleSet {
    param([string[]] $Patterns, [hashtable] $Overrides)

    Import-Module powershell-yaml -ErrorAction Stop
    $ruleDir = "$PSScriptRoot/../rules"
    $files = Get-ChildItem $ruleDir -Filter *.yaml | Where-Object {
        $f = $_.BaseName
        $Patterns | Where-Object { $f -like $_ }
    }
    $sets = foreach ($file in $files) {
        # ConvertFrom-Yaml returns a plain Hashtable (not a PSCustomObject) -- dotting into
        # a key that isn't present (e.g. a hand-edited/custom rule file missing `rules`/
        # `area`/`framework`/`weight`, or an empty file, which parses to $null outright)
        # throws PropertyNotFoundException under Set-StrictMode -Version Latest rather
        # than returning $null, so every top-level key is read via ContainsKey below.
        $doc = ConvertFrom-Yaml (Get-Content $file.FullName -Raw)
        if ($null -eq $doc) {
            Write-Warning "Get-RuleSet: '$($file.Name)' parsed to an empty/null YAML document -- skipping this rule file."
            continue
        }
        $rules = if ($doc.ContainsKey('rules')) { $doc.rules } else { @() }

        # AB#6817 -- a scored framework with no named version is exactly how "CIS compliance:
        # 72%" ends up meaningless across a 31-policy initiative and a 168-policy one, or how a
        # CAF page rewrite silently invalidates a coverage figure nobody re-dated. Refuse to load
        # a rule file that scores anything without a `frameworkversion` naming the version/date
        # it was measured against (see docs/frameworks/README.md). This is a load-time,
        # fail-fast check -- distinct from AB#6832's Unknown-at-score-time handling for data that
        # is simply absent at run time.
        if (@($rules).Count -gt 0) {
            $hasVersion = $doc.ContainsKey('frameworkversion') -and -not [string]::IsNullOrWhiteSpace([string]$doc.frameworkversion)
            if (-not $hasVersion) {
                throw "Get-RuleSet: '$($file.Name)' declares $(@($rules).Count) rule(s) but no 'frameworkversion' -- every scored framework must name the version/date it was measured against. Add a 'frameworkversion' key (see docs/frameworks/README.md)."
            }
        }
        if ($Overrides -and $Overrides.Count -gt 0) {
            foreach ($rule in $rules) {
                if (-not $rule.ContainsKey('id')) { continue }
                if (-not $Overrides.ContainsKey($rule.id)) { continue }
                if ($rule.ContainsKey('manual') -and $rule.manual) { continue }   # manual rules have no numeric threshold to override
                if (-not $rule.ContainsKey('assert') -or $null -eq $rule.assert) { continue }
                $ov = $Overrides[$rule.id]
                $ovMap = $null
                if ($ov -is [hashtable]) {
                    $ovMap = $ov
                }
                elseif ($ov -is [System.Management.Automation.PSCustomObject]) {
                    $ovMap = @{}
                    foreach ($p in $ov.PSObject.Properties) { $ovMap[$p.Name] = $p.Value }
                }
                if ($ovMap) {
                    if ($ovMap.ContainsKey('value')) { $rule.assert.value = $ovMap.value }
                    if ($ovMap.ContainsKey('type'))  { $rule.assert.type  = $ovMap.type }
                }
                else {
                    $rule.assert.value = $ov
                }
            }
        }
        [pscustomobject]@{
            Area             = if ($doc.ContainsKey('area'))      { $doc.area }      else { $null }
            Framework        = if ($doc.ContainsKey('framework')) { $doc.framework } else { $null }
            FrameworkVersion = if ($doc.ContainsKey('frameworkversion')) { $doc.frameworkversion } else { $null }
            Weight           = [double]($(if ($doc.ContainsKey('weight')) { $doc.weight } else { $null }) ?? 1.0)
            # Optional per-file data prerequisite (AB#6832). When declared and none of the paths
            # resolve to rows, Invoke-Assessment reports the whole set Unknown instead of scoring
            # it. Without this a rule set whose inputs were never collected reads as a clean Pass:
            # "0 migrate projects with public access" and "no migrate project exists" are the same
            # count and opposite findings.
            Requires         = @(if ($doc.ContainsKey('requires') -and $doc.requires) { $doc.requires } else { @() })
            Rules            = $rules
        }
    }
    return $sets
}
