#Requires -Version 7.0
#Requires -Modules Pester

<#
    The contract the reporting engine v2 depends on (Epic AB#6450, Feature AB#6449).

    Three defects found while auditing the renderers against the reference deliverables
    attached to AB#6443, each of which lets a report state something untrue:

      AB#6864 — the Evidence payload is capped at 25 rows and nothing said so, so a
                renderer listing affected resources showed 25 of 198 and looked identical
                to a complete list of 26.
      AB#6853 — rules had no targetState/owner/effort/phase, so a gap register or a phased
                roadmap could only be invented by a renderer.
      AB#6863 — 'GovernanceReport' was missing from the -OutputFormat All list and from
                every ValidateSet, so a shipped, tested renderer was unreachable.

    Pure-logic tests — no Azure connection.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Resolve-JsonPath.ps1"
    . "$root/src/assess/engine/Invoke-Rule.ps1"
    . "$root/src/report/Export-Report.ps1"

    function New-Collect {
        param([int] $StorageAccountCount)
        [pscustomobject]@{
            domains = [pscustomobject]@{
                storage = [pscustomobject]@{
                    accounts = @(1..$StorageAccountCount | ForEach-Object {
                            [pscustomobject]@{ name = "sa$_"; publicNetworkAccess = 'Enabled' }
                        })
                }
            }
        }
    }

    # The minimum viable rule — none of the four AB#6853 keys present, which is the shape
    # every rule file in src/assess/rules carried before this change.
    function New-BareRule {
        @{
            id = 'R-BARE'; title = 'Storage accounts should not permit public network access'
            severity = 'high'
            query = '$.domains.storage.accounts[?(@.publicNetworkAccess == ''Enabled'')]'
            assert = @{ type = 'countEquals'; value = 0 }
            remediation = 'Set PublicNetworkAccess=Disabled.'
        }
    }
}

Describe 'AB#6864 — evidence truncation is explicit, never silent' {
    It 'flags truncation when the match count exceeds the cap' {
        $f = Invoke-Rule -Rule (New-BareRule) -Collect (New-Collect -StorageAccountCount 198) -Area 'Storage' -Framework 'CAF'
        $f.EvidenceCount | Should -Be 198
        @($f.Evidence).Count | Should -Be $f.EvidenceCap
        $f.EvidenceTruncated | Should -BeTrue
    }

    It 'does not flag truncation when every match fits inside the cap' {
        $f = Invoke-Rule -Rule (New-BareRule) -Collect (New-Collect -StorageAccountCount 3) -Area 'Storage' -Framework 'CAF'
        $f.EvidenceCount | Should -Be 3
        @($f.Evidence).Count | Should -Be 3
        $f.EvidenceTruncated | Should -BeFalse
    }

    It 'does not flag truncation at exactly the cap — the off-by-one that would cry wolf on every full page' {
        $f = Invoke-Rule -Rule (New-BareRule) -Collect (New-Collect -StorageAccountCount 25) -Area 'Storage' -Framework 'CAF'
        $f.EvidenceCount | Should -Be 25
        $f.EvidenceTruncated | Should -BeFalse
    }

    It 'reports the cap it applied, so a renderer can say "25 of 198" without hardcoding 25' {
        $f = Invoke-Rule -Rule (New-BareRule) -Collect (New-Collect -StorageAccountCount 198) -Area 'Storage' -Framework 'CAF'
        $f.EvidenceCap | Should -BeGreaterThan 0
        $f.EvidenceCap | Should -Be @($f.Evidence).Count
    }
}

Describe 'AB#6853 — the four optional gap-register / roadmap keys' {
    It 'a rule declaring none of them still scores, and surfaces all four as $null' {
        $f = Invoke-Rule -Rule (New-BareRule) -Collect (New-Collect -StorageAccountCount 2) -Area 'Storage' -Framework 'CAF'
        $f.Status | Should -Be 'Fail'
        $f.TargetState | Should -BeNullOrEmpty
        $f.Owner | Should -BeNullOrEmpty
        $f.Effort | Should -BeNullOrEmpty
        $f.Phase | Should -BeNullOrEmpty
    }

    It 'carries all four through onto the finding when the rule declares them' {
        $rule = New-BareRule
        $rule.targetState = 'PublicNetworkAccess=Disabled; data-plane reach via Private Endpoint'
        $rule.owner = 'Data Platform / Network Engineering'
        $rule.effort = 'M'
        $rule.phase = 1
        $f = Invoke-Rule -Rule $rule -Collect (New-Collect -StorageAccountCount 2) -Area 'Storage' -Framework 'CAF'
        $f.TargetState | Should -Be 'PublicNetworkAccess=Disabled; data-plane reach via Private Endpoint'
        $f.Owner | Should -Be 'Data Platform / Network Engineering'
        $f.Effort | Should -Be 'M'
        $f.Phase | Should -Be 1
    }

    It 'reads the keys off a pscustomobject rule as well as a Hashtable one' {
        # ConvertFrom-Yaml hands back a Hashtable; test fixtures across tests/ build
        # pscustomobjects. Both shapes must work or half the suite breaks (AB#6835).
        $rule = [pscustomobject](New-BareRule)
        $rule | Add-Member -NotePropertyName owner -NotePropertyValue 'Security Engineering'
        $f = Invoke-Rule -Rule $rule -Collect (New-Collect -StorageAccountCount 1) -Area 'Storage' -Framework 'CAF'
        $f.Owner | Should -Be 'Security Engineering'
        $f.TargetState | Should -BeNullOrEmpty
    }

    It 'surfaces the four keys on the NotAssessed gate path too, so a gated rule still lands in the roadmap' {
        $rule = New-BareRule
        $rule.owner = 'CCoE Platform'
        $rule.assert = @{ type = 'countEquals'; value = 0; gate = '$.finops.available' }
        $f = Invoke-Rule -Rule $rule -Collect ([pscustomobject]@{ finops = [pscustomobject]@{ available = $false } }) -Area 'Storage' -Framework 'CAF'
        $f.Status | Should -Be 'NotAssessed'
        $f.Owner | Should -Be 'CCoE Platform'
        $f.EvidenceTruncated | Should -BeFalse
    }
}

Describe 'AB#6863 — every renderer Export-Report dispatches is reachable' {
    It 'includes GovernanceReport — the renderer that was shipped, tested and unreachable' {
        Get-ScoutRendererName | Should -Contain 'GovernanceReport'
    }

    It 'lists exactly the renderer names Export-Report.ps1 switches on' {
        # Parse the switch labels out of the dispatcher itself rather than restating them,
        # so adding a renderer without adding it to the canonical list fails HERE instead of
        # silently making it unreachable via -OutputFormat All the way GovernanceReport was.
        $root = Split-Path $PSScriptRoot -Parent
        $src = Get-Content "$root/src/report/Export-Report.ps1" -Raw
        $switchBody = [regex]::Match($src, "switch \(\`$Renderer\) \{(.+?)\n    \}", 'Singleline').Groups[1].Value
        $switchBody | Should -Not -BeNullOrEmpty
        $dispatched = [regex]::Matches($switchBody, "(?m)^\s*'([A-Za-z]+)'\s*\{") |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -ne 'default' } |
            Sort-Object -Unique
        $canonical = @(Get-ScoutRendererName) | Sort-Object -Unique
        $dispatched | Should -Not -BeNullOrEmpty
        ($canonical -join ',') | Should -Be ($dispatched -join ',')
    }

    It 'is accepted by both -OutputFormat ValidateSets' {
        $root = Split-Path $PSScriptRoot -Parent
        foreach ($file in @('src/Invoke-AzureScout.ps1', 'src/Invoke-ScoutAssessmentCore.ps1')) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $root $file), [ref]$null, [ref]$null)
            $param = $ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.ParameterAst] -and
                    $n.Name.VariablePath.UserPath -eq 'OutputFormat'
                }, $true) | Select-Object -First 1
            $param | Should -Not -BeNullOrEmpty -Because "$file must declare -OutputFormat"
            $values = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] -and $_.TypeName.Name -eq 'ValidateSet' } |
                ForEach-Object { $_.PositionalArguments.Value }
            $values | Should -Contain 'GovernanceReport' -Because "$file rejected an explicit -OutputFormat GovernanceReport"
        }
    }
}
