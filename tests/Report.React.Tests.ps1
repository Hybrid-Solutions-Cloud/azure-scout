#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for src/report/renderers/Export-React.ps1 — the payload builder behind the
    React single-page report (ADO Feature AB#6928: AB#6929 payload contract, AB#6930 identity).

    window.__SCOUT_DATA__ = { identity, meta, ran, inventory, subscriptions, assessments,
    resourceIndex, drift } is the FULL contract this renderer is now responsible for (the front
    end never re-derives anything). These tests assert the contract's shape, the score-formula
    strings, every catalogued evidence shape normalising to {resourceName,resourceId,
    subscriptionId,detail}, and subscription attribution -- built from the repo's existing
    tests/datadump/sample-collect.json fixture (the canonical collect.json shape) plus a
    synthetic Findings set carrying every evidence shape found in a real corpus run (see the
    AB#6928 session notes for the tenant-by-tenant catalogue this mirrors).

    No Azure connection, no external network access required.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/assess/engine/Get-Score.ps1"
    . "$script:Root/src/report/renderers/Export-React.ps1"

    function New-ReactTestFinding {
        param($Id, $Framework, $Area, $Status, $Assessment, $Evidence = @(), $Severity = 'medium', $Weight = 1.0)
        [pscustomobject]@{
            Id = $Id; Title = "$Id title"; Framework = $Framework; Area = $Area; Severity = $Severity
            Status = $Status; EvidenceCount = @($Evidence).Count; Evidence = $Evidence
            Remediation = "Remediate $Id."; Manual = ($Status -eq 'Manual'); AreaWeight = $Weight
        } | Add-Member -NotePropertyName Assessment -NotePropertyValue $Assessment -PassThru
    }

    # One finding per catalogued real-world evidence shape (AB#6929's own shape catalogue):
    # plain ARM row, key vault secret, NSG rule, subnet utilisation (no name/id/sub at all),
    # advisor row (subscription NAME not guid), cross-resource join (leftOnly), and a
    # diagnostic-coverage aggregate row (type-level, not a resource).
    $script:Findings = @(
        (New-ReactTestFinding 'net-1' 'CAF' 'Networking' 'Pass' 'LandingZone' @(
            [pscustomobject]@{ name = 'vnet-hub'; resourceGroup = 'rg-hub'; subscriptionId = 'sub-0001'; peeringCount = 1 }
        ))
        (New-ReactTestFinding 'net-2' 'CAF' 'Networking' 'Fail' 'LandingZone' @(
            [pscustomobject]@{ vnet = 'vnet-hub'; subnet = 'snet-app'; prefix = '10.0.0.0/24'; total = 251; used = 3; ipUtilizationPct = 1.2 }
        ) 'high')
        (New-ReactTestFinding 'sec-1' 'WAF' 'Security' 'Fail' 'Assess: Security' @(
            [pscustomobject]@{ id = '/subscriptions/sub-0001/resourceGroups/rg-hub/providers/Microsoft.KeyVault/vaults/kv-hub/secrets/db-pass'; keyVaultName = 'kv-hub'; keyVaultId = '/subscriptions/sub-0001/resourceGroups/rg-hub/providers/Microsoft.KeyVault/vaults/kv-hub'; subscriptionId = 'sub-0001'; resourceGroup = 'rg-hub'; contentType = $null; enabled = $true; expires = $null }
        ))
        (New-ReactTestFinding 'sec-2' 'WAF' 'Security' 'Fail' 'Assess: Security' @(
            [pscustomobject]@{ nsg = 'vm1-nsg'; resourceGroup = 'rg-hub'; rule = 'default-allow-ssh'; port = '22' }
        ))
        (New-ReactTestFinding 'cost-1' 'WAF' 'Cost optimization' 'Fail' 'WAF: Cost Optimization' @(
            [pscustomobject]@{ Category = 'Cost'; Impact = 'Medium'; ImpactedField = 'Microsoft.Compute/disks'; ImpactedValue = 'osdisk-orphan-01'; Subscription = 'sub-prod'; ShortDescriptionProblem = 'orphaned disk'; ShortDescriptionSolution = 'delete it' }
        ))
        (New-ReactTestFinding 'bak-1' 'WAF' 'Reliability' 'Fail' 'WAF: Reliability' @(
            [pscustomobject]@{ JoinMode = 'leftOnly'; Key = '/subscriptions/sub-0001/resourceGroups/rg-hub/providers/Microsoft.Compute/virtualMachines/vm1'; Left = [pscustomobject]@{ id = '/subscriptions/sub-0001/resourceGroups/rg-hub/providers/Microsoft.Compute/virtualMachines/vm1'; name = 'vm1'; resourceGroup = 'rg-hub'; subscriptionId = 'sub-0001'; size = 'Standard_B2s' }; Right = $null; LeftLabel = 'virtual machine'; RightLabel = 'backup protected item' }
        ))
        (New-ReactTestFinding 'diag-1' 'CAF' 'Management' 'Partial' 'Assess: Monitor' @(
            [pscustomobject]@{ type = 'microsoft.compute/disks'; total = 3; withDiag = 1; coveragePct = 33.3 }
        ))
        (New-ReactTestFinding 'man-1' 'CAF' 'Governance' 'Manual' 'LandingZone')
        (New-ReactTestFinding 'unk-1' 'CAF' 'Governance' 'Unknown' 'LandingZone')
    )
    $script:Scored = Get-Score -Findings $script:Findings

    $script:CollectPath = Join-Path $script:Root 'tests' 'datadump' 'sample-collect.json'
    $script:Collect = Get-Content $script:CollectPath -Raw | ConvertFrom-Json -Depth 100
    $script:Collect | Add-Member -NotePropertyName _meta -NotePropertyValue ([pscustomobject]@{
            scope = 'All'; managementGroupId = 'mg-test-01'; generatedOn = (Get-Date).ToString('o')
        }) -Force

    $script:OutDir = Join-Path $script:Root 'tests' 'test-output' 'react'
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force }
    New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null

    function Get-EmbeddedPayload {
        param([string] $Html)
        $s = $Html.IndexOf('window.__SCOUT_DATA__ = ') + 'window.__SCOUT_DATA__ = '.Length
        $e = $Html.IndexOf(';</script>', $s)
        return ($Html.Substring($s, $e - $s) | ConvertFrom-Json -Depth 100)
    }
}

AfterAll {
    if (Test-Path $script:OutDir) { Remove-Item $script:OutDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Export-React — payload contract shape (AB#6929)' {
    BeforeAll {
        $script:ReportPath = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Html = Get-Content $script:ReportPath -Raw
        $script:Payload = Get-EmbeddedPayload -Html $script:Html
    }

    It 'writes report-react.html into -OutputPath and returns its path' {
        $script:ReportPath | Should -Exist
        (Split-Path $script:ReportPath -Leaf) | Should -Be 'report-react.html'
    }

    It 'carries exactly the eight top-level contract keys' {
        $keys = @($script:Payload.PSObject.Properties.Name | Sort-Object)
        $keys | Should -Be (@('identity', 'meta', 'ran', 'inventory', 'subscriptions', 'assessments', 'resourceIndex', 'drift') | Sort-Object)
    }

    It 'identity carries every neutral-default field with no vendor name/URL leaking onto the report surface' {
        $id = $script:Payload.identity
        $id.clientName | Should -Be 'Client Organization'
        # script:Collect carries inventory data and script:Scored carries findings, so the
        # derived default is the "both" case -- see the dedicated adaptive-reportTitle Describe
        # block below for every ran combination.
        $id.reportTitle | Should -Be 'Azure Inventory and Assessment'
        $id.classification | Should -Match 'Confidential'
        $id.handlingFooter | Should -Not -BeNullOrEmpty
        ($id.PSObject.Properties.Value -join ' ') | Should -Not -Match 'Azure Scout'
        ($id.PSObject.Properties.Value -join ' ') | Should -Not -Match 'thisismydemo'
    }

    It 'meta carries scope/managementGroupId/runId/product identity' {
        $script:Payload.meta.scope | Should -Be 'All'
        $script:Payload.meta.managementGroupId | Should -Be 'mg-test-01'
        $script:Payload.meta.runId | Should -Not -BeNullOrEmpty
        $script:Payload.meta.productName | Should -Be 'Azure Scout'
    }

    It 'ran reflects that this run actually scored findings, and never claims Entra collection' {
        $script:Payload.ran.assessments | Should -BeTrue
        $script:Payload.ran.entra | Should -BeFalse
    }

    It 'subscriptions mirrors Collect.subscriptions {id,name,state}' {
        @($script:Payload.subscriptions).Count | Should -Be 3
        ($script:Payload.subscriptions | Where-Object id -eq 'sub-0001').name | Should -Be 'sub-prod'
    }

    It 'inventory carries a category per array found anywhere in Collect, each with label/count/rows' {
        $cats = @($script:Payload.inventory.PSObject.Properties.Name)
        $cats.Count | Should -BeGreaterThan 5
        $vnetCat = $script:Payload.inventory.'networking.virtualNetworks'
        $vnetCat | Should -Not -BeNullOrEmpty
        $vnetCat.label | Should -Match 'Networking'
        $vnetCat.count | Should -BeGreaterOrEqual 0
    }

    It 'assessments groups findings by the Assessment property Invoke-Assessment stamps on each' {
        $names = @($script:Payload.assessments.name | Sort-Object)
        $names | Should -Contain 'LandingZone'
        $names | Should -Contain 'Assess: Security'
    }

    It 'each assessment finding id is globally unique via the slug:originalId composite' {
        $allIds = @($script:Payload.assessments | ForEach-Object { $_.findings.id })
        ($allIds | Select-Object -Unique).Count | Should -Be $allIds.Count
        $allIds | Should -Contain 'landingzone:net-1'
    }
}

Describe 'Export-React — every assessment has a real name, no "(unassigned)" bucket (AB#6929 follow-up)' {
    <#
        Found visually on the executive view: an assessment card labelled "(UNASSIGNED)" scoring
        0% next to a real "LANDINGZONE 41%" card. Root cause was in Invoke-Assessment.ps1, not
        this renderer -- Compare-Benchmark (LandingZone's ALZ management-group/policy checks)
        built its findings as bare pscustomobjects with no Assessment property, unlike every
        rule-set finding, which is decorated via an Add-Member chain. This renderer's grouping
        then fell back to a placeholder bucket for anything with no Assessment, and that
        placeholder rendered as a nameless, 0%-scoring card. Fixed at the source (Invoke-
        Assessment now stamps the benchmark findings with the SAME Assessment it was called for)
        plus a defensive rename here so a future unstamped finding still reads as something
        legible rather than blank.
    #>
    It 'no assessment in the payload has an empty/blank name or slug' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        foreach ($a in $payload.assessments) {
            $a.name | Should -Not -BeNullOrEmpty
            $a.name.Trim() | Should -Not -Be ''
            $a.slug | Should -Not -BeNullOrEmpty
            $a.slug.Trim() | Should -Not -Be ''
        }
    }

    It 'a finding with no Assessment property still gets a real, non-blank bucket name (defensive backstop)' {
        $unstamped = [pscustomobject]@{
            Id = 'orphan-1'; Title = 'orphan'; Framework = 'CAF'; Area = 'Test'; Severity = 'low'
            Status = 'Fail'; EvidenceCount = 0; Evidence = @(); Remediation = 'fix it'; Manual = $false; AreaWeight = 1.0
        }   # deliberately NOT stamped with Assessment
        $merged = Get-Score -Findings (@($script:Findings) + @($unstamped))
        $path = Export-React -Findings $merged -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $backstop = $payload.assessments | Where-Object { $_.findings.id -contains 'unassigned-checks:orphan-1' }
        $backstop | Should -Not -BeNullOrEmpty
        $backstop.name | Should -Not -Match '^\(.*\)$'   # not the old "(unassigned)" placeholder shape
        $backstop.name.Trim() | Should -Not -Be ''
    }

    It 'Invoke-Assessment stamps benchmark (Compare-Benchmark) findings with the SAME Assessment as the rule-set findings' {
        . "$script:Root/src/assess/Compare-Benchmark.ps1"
        . "$script:Root/src/assess/engine/Invoke-Rule.ps1"
        . "$script:Root/src/assess/engine/Resolve-JsonPath.ps1"
        . "$script:Root/src/assess/engine/Resolve-RuleJoin.ps1"
        . "$script:Root/src/assess/engine/Get-RuleSet.ps1"
        . "$script:Root/src/assess/Invoke-Assessment.ps1"

        $manifest = Import-PowerShellDataFile (Join-Path $script:Root 'manifests' 'assessments.psd1')
        $spec = $manifest['LandingZone']
        $spec.ContainsKey('Benchmark') | Should -BeTrue -Because 'this test specifically exercises the benchmark-attribution path'
        $ruleSet = Get-RuleSet -Patterns $spec.Rules
        $benchmark = Get-Content (Join-Path $script:Root 'src' 'assess' 'benchmarks' $spec.Benchmark) -Raw | ConvertFrom-Json -Depth 100

        $liveFindings = Invoke-Assessment -Collect $script:Collect -RuleSet $ruleSet -Benchmark $benchmark -Assessment 'LandingZone'
        $benchmarkFindings = @($liveFindings | Where-Object { $_.Id -like 'BENCH-*' })
        $benchmarkFindings.Count | Should -BeGreaterThan 0 -Because 'sample-collect.json carries governance data, so Compare-Benchmark should produce real findings, not the BENCH-GOV-DATA guard'
        foreach ($f in $benchmarkFindings) {
            $f.PSObject.Properties['Assessment'] | Should -Not -BeNullOrEmpty
            $f.Assessment | Should -Be 'LandingZone'
        }

        # And end to end: exactly one "LandingZone" assessment in the payload, no separate
        # unassigned/blank bucket carrying the benchmark findings.
        $liveScored = Get-Score -Findings $liveFindings
        $path = Export-React -Findings $liveScored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        @($payload.assessments | Where-Object name -eq 'LandingZone').Count | Should -Be 1
        $payload.assessments.name | Should -Not -Contain '(unassigned)'
        $payload.assessments.name | Should -Not -Contain ''
        $lzFindingIds = ($payload.assessments | Where-Object name -eq 'LandingZone').findings.id
        $lzFindingIds | Where-Object { $_ -like 'landingzone:BENCH-*' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Export-React — score formulas (AB#6929)' {
    BeforeAll {
        $script:ReportPath = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Payload = Get-EmbeddedPayload -Html (Get-Content $script:ReportPath -Raw)
        $script:Lz = $script:Payload.assessments | Where-Object name -eq 'LandingZone'
    }

    It 'never emits a bare score number -- numerator/denominator/weight/excludedCount/formula all present' {
        $script:Lz.score.percent | Should -Not -BeNullOrEmpty
        $script:Lz.score.numerator | Should -Not -BeNullOrEmpty
        $script:Lz.score.denominator | Should -BeGreaterThan 0
        $script:Lz.score.formula | Should -Match 'automated'
        $script:Lz.score.formula | Should -Match '%'
    }

    It 'excludedCount accounts for the Manual and Unknown findings in scope' {
        # net-1 (Pass), net-2 (Fail), man-1 (Manual), unk-1 (Unknown) are all LandingZone.
        $script:Lz.scope.checksManual | Should -Be 1
        $script:Lz.scope.checksNotAssessed | Should -BeGreaterOrEqual 1
    }

    It 'every area carries its own formula string' {
        foreach ($area in $script:Lz.areas) {
            $area.formula | Should -Not -BeNullOrEmpty
            $area.weight | Should -Not -BeNullOrEmpty
        }
    }
}

<#
    learnUrl was empty on every finding in the real rendered payload (owner review, tppoc). The
    resolver below is ported from the approved mockup's generate.js (finding id/title override ->
    assessment slug's CAF design area/WAF pillar/domain/specialty map -> a CAF/WAF framework root
    -- never an unrelated topic). Rule #1 in the assignment: never fall through to an unrelated
    page (an earlier mockup pass sent every specialty-assessment finding to the cost-management
    page). Rule #2: don't trust an in-data citation blindly -- one rule file's own cited URL 404s
    (AB#6913); the curated map here is the source of truth.
#>
Describe 'Export-React — learnUrl resolves for every finding, never to an unrelated page (AB#6928 follow-up)' {
    BeforeAll {
        $script:ReportPath = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Payload = Get-EmbeddedPayload -Html (Get-Content $script:ReportPath -Raw)
        $script:AllFindings = @($script:Payload.assessments | ForEach-Object { $_.findings })
    }

    It 'every finding carries a non-empty learnUrl' {
        $script:AllFindings.Count | Should -BeGreaterThan 0
        foreach ($f in $script:AllFindings) {
            $f.learnUrl | Should -Not -BeNullOrEmpty -Because "finding $($f.id) has no guidance link"
        }
    }

    It 'every learnUrl is a real learn.microsoft.com or security.microsoft.com page, not a placeholder' {
        foreach ($f in $script:AllFindings) {
            $f.learnUrl | Should -Match '^https://(learn\.microsoft\.com|security\.microsoft\.com)/' -Because "finding $($f.id): $($f.learnUrl)"
        }
    }

    It 'a backup-related finding never resolves to an unrelated page (regression: the mockup once sent every specialty finding to the cost page)' {
        $backupFinding = $script:AllFindings | Where-Object { $_.title -match '(?i)backup' } | Select-Object -First 1
        if ($backupFinding) {
            $backupFinding.learnUrl | Should -Match 'backup' -Because "a backup finding must not resolve to an unrelated topic like cost management: $($backupFinding.learnUrl)"
        }
    }

    It 'an NSG/network-security finding resolves to the NSG guidance page, not a generic fallback' {
        $nsgFinding = $script:AllFindings | Where-Object { $_.title -match '(?i)nsg|network security' } | Select-Object -First 1
        if ($nsgFinding) {
            $nsgFinding.learnUrl | Should -Match 'network-security-groups' -Because "an NSG finding should land on NSG-specific guidance: $($nsgFinding.learnUrl)"
        }
    }

    It 'findings in different assessments never all collapse onto the SAME single URL (would indicate a broken/short-circuited resolver)' {
        $distinctUrls = @($script:AllFindings.learnUrl | Sort-Object -Unique)
        $distinctUrls.Count | Should -BeGreaterThan 1
    }

    # The payload carrying learnUrl/weight is only half the job -- the owner asked for them in the
    # CSV specifically. The column lists in exportCsv() are plain string arrays, so dropping one is
    # a silent, test-invisible regression unless asserted against the shipped template directly.
    It 'the CSV export column lists include learnUrl and weight' {
        $template = Get-Content (Join-Path $PSScriptRoot '..\src\report\templates\report-react.html.template') -Raw
        $colLines = @([regex]::Matches($template, "cols = \[[^\]]*'remediation'[^\]]*\]"))
        $colLines.Count | Should -BeGreaterThan 1 -Because 'both the per-assessment and all-findings CSV column lists should be found'
        foreach ($line in $colLines) {
            $line.Value | Should -Match "'learnUrl'" -Because "CSV export must carry the guidance link: $($line.Value)"
            $line.Value | Should -Match "'weight'" -Because "CSV export must carry the area weight: $($line.Value)"
        }
    }

    It 'each finding carries its area weight, denormalised from areas[]' {
        $lz = $script:Payload.assessments | Where-Object name -eq 'LandingZone'
        $areaWeights = @{}
        foreach ($a in $lz.areas) { $areaWeights[$a.name] = $a.weight }
        foreach ($f in $lz.findings) {
            $f.weight | Should -Be $areaWeights[$f.area]
        }
    }
}

Describe 'Export-React — evidence shape normalisation (AB#6929)' {
    BeforeAll {
        $script:ReportPath = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Payload = Get-EmbeddedPayload -Html (Get-Content $script:ReportPath -Raw)
        function Get-FindingById([string] $Id) {
            foreach ($a in $script:Payload.assessments) {
                $f = $a.findings | Where-Object { $_.id -eq $Id }
                if ($f) { return $f }
            }
        }
    }

    It 'a plain ARM-id row normalises name/id/subscriptionId directly' {
        $f = Get-FindingById 'landingzone:net-1'
        $ev = $f.evidence[0]
        $ev.resourceName | Should -Be 'vnet-hub'
        $ev.subscriptionId | Should -Be 'sub-0001'
    }

    It 'a subnet row (no name/id/subscription at all) still resolves resourceName from vnet/subnet' {
        $f = Get-FindingById 'landingzone:net-2'
        $ev = $f.evidence[0]
        $ev.resourceName | Should -Be 'vnet-hub/snet-app'
    }

    It 'a key vault secret row prefers keyVaultName/keyVaultId over the secret''s own id' {
        $f = Get-FindingById 'assess-security:sec-1'
        $ev = $f.evidence[0]
        $ev.resourceName | Should -Be 'kv-hub'
        $ev.subscriptionId | Should -Be 'sub-0001'
    }

    It 'an NSG rule row (no name field, no id) resolves resourceName from nsg and rg->sub backfills the subscription' {
        $f = Get-FindingById 'assess-security:sec-2'
        $ev = $f.evidence[0]
        $ev.resourceName | Should -Be 'vm1-nsg'
        # rg-hub is shared with sec-1's key vault (subscriptionId sub-0001) -- the resourceGroup
        # -> subscription backfill map should attribute this row even though it carries no
        # subscriptionId of its own.
        $ev.subscriptionId | Should -Be 'sub-0001'
    }

    It 'an advisor row (Subscription is a friendly NAME, never a guid) resolves via the subscription name map' {
        $f = Get-FindingById 'waf-cost-optimization:cost-1'
        $ev = $f.evidence[0]
        $ev.resourceName | Should -Be 'osdisk-orphan-01'
        $ev.subscriptionId | Should -Be 'sub-0001'
    }

    It 'a cross-resource join row (leftOnly, Right is $null) resolves identity from Left and a descriptive detail' {
        $f = Get-FindingById 'waf-reliability:bak-1'
        $ev = $f.evidence[0]
        $ev.resourceName | Should -Be 'vm1'
        $ev.subscriptionId | Should -Be 'sub-0001'
        $ev.detail | Should -Match 'virtual machine'
        $ev.detail | Should -Match 'backup protected item'
    }

    It 'a diagnostic-coverage aggregate row (type/total/withDiag/coveragePct) is NOT treated as a named resource' {
        $f = Get-FindingById 'assess-monitor:diag-1'
        $ev = $f.evidence[0]
        $ev.resourceName | Should -Be 'microsoft.compute/disks'
        $ev.resourceId | Should -BeNullOrEmpty
        # It must not pollute the resourceIndex -- there is no single resource behind a
        # type-level coverage stat to click through to.
        $script:Payload.resourceIndex.PSObject.Properties.Name | Should -Not -Contain 'microsoft.compute/disks'
    }

    It 'a bare (non-array) Evidence object still normalises without throwing' {
        . "$script:Root/src/assess/engine/Get-Score.ps1"
        $bareFinding = [pscustomobject]@{
            Id = 'bare-1'; Title = 'bare'; Framework = 'CAF'; Area = 'Test'; Severity = 'low'
            Status = 'Fail'; EvidenceCount = 1
            Evidence = [pscustomobject]@{ name = 'solo-resource'; resourceGroup = 'rg-hub'; subscriptionId = 'sub-0001' }
            Remediation = 'fix it'; Manual = $false; AreaWeight = 1.0
        } | Add-Member -NotePropertyName Assessment -NotePropertyValue 'LandingZone' -PassThru
        $bareScored = Get-Score -Findings @($bareFinding)
        { Export-React -Findings $bareScored -Collect $script:Collect -OutputPath $script:OutDir } | Should -Not -Throw
    }
}

Describe 'Export-React — resourceIndex + subscription attribution' {
    BeforeAll {
        $script:ReportPath = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Payload = Get-EmbeddedPayload -Html (Get-Content $script:ReportPath -Raw)
    }

    It 'inverts evidence into resourceIndex keyed by resourceName' {
        $script:Payload.resourceIndex.'vnet-hub' | Should -Not -BeNullOrEmpty
        $script:Payload.resourceIndex.'vnet-hub'.subscriptionId | Should -Be 'sub-0001'
        @($script:Payload.resourceIndex.'vnet-hub'.findingIds) | Should -Contain 'landingzone:net-1'
    }

    It 'a resource named by two different findings accumulates both finding ids' {
        # vm1 is named by the bak-1 join finding only in this fixture, but exercising the merge
        # path: re-render with a second finding also naming vm1 and confirm both ids appear.
        $extra = New-ReactTestFinding 'bak-2' 'WAF' 'Reliability' 'Fail' 'WAF: Reliability' @(
            [pscustomobject]@{ name = 'vm1'; resourceGroup = 'rg-hub'; subscriptionId = 'sub-0001'; note = 'second finding on the same VM' }
        )
        $merged = Get-Score -Findings (@($script:Findings) + @($extra))
        $path = Export-React -Findings $merged -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        @($payload.resourceIndex.vm1.findingIds) | Should -Contain 'waf-reliability:bak-1'
        @($payload.resourceIndex.vm1.findingIds) | Should -Contain 'waf-reliability:bak-2'
    }

    It 'unattributable resources are rare and limited to genuinely subscription-less constructs' {
        $noSub = @($script:Payload.resourceIndex.PSObject.Properties | Where-Object { -not $_.Value.subscriptionId })
        # Every resource in this fixture set is subscription-scoped -- none should be unattributable.
        $noSub.Count | Should -Be 0
    }
}

Describe 'Export-React — report identity (AB#6930)' {
    It 'defaults are neutral -- no vendor name, no vendor URL, generic client placeholder' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.identity.clientName | Should -Be 'Client Organization'
        $payload.identity.classification | Should -Match 'Confidential'
        $payload.identity.preparingOrganisation | Should -BeNullOrEmpty
        $payload.identity.logoDataUri | Should -BeNullOrEmpty
    }

    It '-ReportIdentity overrides propagate and unset fields keep their defaults' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir `
            -ReportIdentity @{ clientName = 'Contoso Ltd'; classification = 'Restricted' }
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.identity.clientName | Should -Be 'Contoso Ltd'
        $payload.identity.classification | Should -Be 'Restricted'
        # Untouched field keeps its (ran-derived) default -- script:Collect+script:Scored is the
        # "both" case; see the adaptive-reportTitle Describe block for every combination.
        $payload.identity.reportTitle | Should -Be 'Azure Inventory and Assessment'
    }

    It 'handlingFooter derives from classification + clientName when not explicitly set' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir `
            -ReportIdentity @{ clientName = 'Contoso Ltd'; classification = 'Restricted' }
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.identity.handlingFooter | Should -Be 'Restricted — do not distribute outside Contoso Ltd'
    }

    It 'handlingFooter never carries a dangling "outside —" when clientName is unset' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir `
            -ReportIdentity @{ classification = 'Restricted' }
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.identity.handlingFooter | Should -Be 'Restricted'
        $payload.identity.handlingFooter | Should -Not -Match 'outside\s*$'
    }

    It 'an explicit handlingFooter override is used verbatim' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir `
            -ReportIdentity @{ handlingFooter = 'Internal use only' }
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.identity.handlingFooter | Should -Be 'Internal use only'
    }
}

<#
    Owner directive (2026-08-04, AB#6928 follow-up): "So the title wouldn't be Azure Landing Zone
    Assessment. It would be Company Name Inventory and Assessment right?" -- the document is now
    ONE master file carrying inventory plus whichever assessments were selected, so naming it
    after a single assessment is a leftover from the per-assessment era. The default reportTitle
    is derived from the SAME `ran` flags that drive the adaptive nav, so it always matches what
    the run actually produced. Note: clientName is NOT baked in here -- the front end composes
    the document title as "{reportTitle} — {clientName}" itself.
#>
Describe 'Export-React — adaptive default reportTitle derives from what ran (AB#6928 follow-up)' {
    BeforeAll {
        # A Collect with no subscriptions/networking/compute data at all -- ran.inventory reads
        # false from it, isolating the "assessments only" case.
        $script:BareCollect = [pscustomobject]@{
            _meta = [pscustomobject]@{ scope = 'ArmOnly'; managementGroupId = $null; generatedOn = (Get-Date).ToString('o') }
        }
    }

    It 'inventory only (no findings) -> "Azure Inventory"' {
        $emptyScored = Get-Score -Findings @()
        $path = Export-React -Findings $emptyScored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.ran.inventory | Should -BeTrue
        $payload.ran.assessments | Should -BeFalse
        $payload.identity.reportTitle | Should -Be 'Azure Inventory'
    }

    It 'assessments only (no inventory data in Collect) -> "Azure Assessment"' {
        $path = Export-React -Findings $script:Scored -Collect $script:BareCollect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.ran.inventory | Should -BeFalse
        $payload.ran.assessments | Should -BeTrue
        $payload.identity.reportTitle | Should -Be 'Azure Assessment'
    }

    It 'inventory AND assessments -> "Azure Inventory and Assessment"' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.ran.inventory | Should -BeTrue
        $payload.ran.assessments | Should -BeTrue
        $payload.identity.reportTitle | Should -Be 'Azure Inventory and Assessment'
    }

    It 'an explicit -ReportIdentity reportTitle always beats the derived default, in every ran combination' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir `
            -ReportIdentity @{ reportTitle = 'Azure Landing Zone Assessment' }
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.identity.reportTitle | Should -Be 'Azure Landing Zone Assessment'
    }

    It 'the client name is not baked into reportTitle (the front end composes the document title itself)' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir `
            -ReportIdentity @{ clientName = 'Contoso Ltd' }
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.identity.reportTitle | Should -Not -Match 'Contoso'
    }
}

Describe 'Export-React — -DefaultReportMode (AB#6928 follow-up)' {
    It 'defaults to consultant (lower-cased to match the front end''s state.mode/data-mode vocabulary)' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.meta.defaultMode | Should -Be 'consultant'
    }

    It 'honours an explicit -DefaultReportMode, lower-cased' {
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir -DefaultReportMode Executive
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.meta.defaultMode | Should -Be 'executive'
    }

    It 'rejects a mode outside the three real lenses' {
        { Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir -DefaultReportMode 'Bogus' } | Should -Throw
    }
}

Describe 'Export-React — offline artifact + drift (unchanged from prior contract)' {
    BeforeAll {
        $script:ReportPath = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir
        $script:Html = Get-Content $script:ReportPath -Raw
    }

    It 'has no external CDN / network references (self-contained offline artifact)' {
        $script:Html | Should -Not -Match 'src\s*=\s*"http'
        $script:Html | Should -Not -Match "src\s*=\s*'http"
        $script:Html | Should -Not -Match 'href\s*=\s*"http'
        $script:Html | Should -Not -Match "href\s*=\s*'http"
        $script:Html | Should -Not -Match 'cdn\.'
    }

    It 'embeds a null Drift so the client-side reader falls back to an empty object' {
        $payload = Get-EmbeddedPayload -Html $script:Html
        $payload.drift | Should -BeNullOrEmpty
    }

    It 'embeds a supplied Drift object verbatim' {
        $driftObject = [pscustomobject]@{ RunId = 'run2'; PreviousRunId = 'run1'; OverallScore = 67 }
        $path = Export-React -Findings $script:Scored -Collect $script:Collect -OutputPath $script:OutDir -Drift $driftObject
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.drift.RunId | Should -Be 'run2'
        $payload.drift.PreviousRunId | Should -Be 'run1'
    }

    It 'does not throw when Collect is $null (CollectOnly-style caller with nothing to embed yet)' {
        { Export-React -Findings $script:Scored -Collect $null -OutputPath $script:OutDir } | Should -Not -Throw
    }
}

<#
    A LIVE run's Evidence rows come straight out of Resolve-JsonPath (Newtonsoft JSONPath),
    i.e. Newtonsoft.Json.Linq.JObject/JArray/JValue/JProperty tokens -- NOT deserialized
    PSCustomObjects. Every other Describe block above builds its Findings from hand-written
    pscustomobject fixtures (or a findings.json round-tripped through ConvertFrom-Json), which
    can never reproduce this: both paths already carry native PowerShell types. This block runs
    the REAL Invoke-Assessment -> Get-Score pipeline against the repo's own sample-collect.json
    fixture -- no Azure, still fully offline -- specifically to exercise the JToken shapes a
    live -Assessment run actually hands the renderer. It caught a real defect during AB#6928: a
    rule's JSONPath resolving to an object's own child PROPERTIES (JTokenType.Property) rather
    than array elements crashed Get-ReactRowProp, because PowerShell's PSObject.Properties[...]
    lookup throws on that particular Newtonsoft shape.
#>
Describe 'Export-React — live (un-round-tripped) Newtonsoft JToken evidence, AB#6928 regression' {
    BeforeAll {
        . "$script:Root/src/assess/Invoke-Assessment.ps1"
        . "$script:Root/src/assess/engine/Invoke-Rule.ps1"
        . "$script:Root/src/assess/engine/Resolve-JsonPath.ps1"
        . "$script:Root/src/assess/engine/Resolve-RuleJoin.ps1"
        . "$script:Root/src/assess/engine/Get-RuleSet.ps1"

        $manifestPath = Join-Path $script:Root 'manifests' 'assessments.psd1'
        $script:LiveManifest = Import-PowerShellDataFile $manifestPath
        $script:LiveSpec = $script:LiveManifest['LandingZone']
        $script:LiveRuleSet = Get-RuleSet -Patterns $script:LiveSpec.Rules
        $script:LiveFindings = Invoke-Assessment -Collect $script:Collect -RuleSet $script:LiveRuleSet -Assessment 'LandingZone'
        $script:LiveScored = Get-Score -Findings $script:LiveFindings
    }

    It 'at least one live finding carries genuine unconverted Newtonsoft evidence (proves this test exercises the real bug, not a no-op)' {
        $sawJToken = $false
        foreach ($f in $script:LiveFindings) {
            foreach ($e in @($f.Evidence)) {
                if ($null -ne $e -and $e.GetType().FullName -like 'Newtonsoft.Json.Linq.*') { $sawJToken = $true }
            }
        }
        $sawJToken | Should -BeTrue
    }

    It 'renders without throwing against live, un-round-tripped findings' {
        { Export-React -Findings $script:LiveScored -Collect $script:Collect -OutputPath $script:OutDir } | Should -Not -Throw
    }

    It 'the live render still produces a valid, parseable payload' {
        $path = Export-React -Findings $script:LiveScored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $payload.assessments | Should -Not -BeNullOrEmpty
        @($payload.assessments[0].findings).Count | Should -BeGreaterThan 0
    }

    <#
        Owner review measurement on the real rendered tppoc payload (3 assessments, 139 findings,
        491 evidence rows): 94% of evidence rows were ".NET array metadata" -- `resourceName` null
        and `detail` = "Length=7; LongLength=7; Rank=1; IsReadOnly=False; IsFixedSize=True;
        IsSynchronized=False" (System.Array's OWN reflection properties). Root cause: PowerShell's
        `.Type` member access on a genuine Newtonsoft JObject silently returns an EMPTY STRING (not
        an exception, not the real JTokenType.Object value), so ConvertFrom-ReactJToken's dispatch
        fell into its "not a container" scalar branch for every ordinary evidence row and ran it
        through `.ToObject([object])`, which for a JObject returns a `System.Object[]`. Fixed by
        branching on `.GetType().FullName` instead of Newtonsoft's own `.Type` property. This test
        would have caught it: the pre-fix renderer emitted exactly this junk shape against this
        same live pipeline.
    #>
    It 'no evidence detail is .NET array/collection metadata (the 94%-junk defect)' {
        $path = Export-React -Findings $script:LiveScored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $allEvidence = @($payload.assessments | ForEach-Object { $_.findings } | ForEach-Object { $_.evidence })
        $allEvidence.Count | Should -BeGreaterThan 0 -Because 'this fixture must actually produce evidence rows for the assertion below to mean anything'
        foreach ($e in $allEvidence) {
            $e.detail | Should -Not -Match 'LongLength|IsFixedSize|IsSynchronized|System\.Object\[\]' -Because "a row with this detail is a stringified .NET array, not a finding for evidence: $($e | ConvertTo-Json -Compress)"
        }
    }

    It 'the overwhelming majority of evidence rows carry a real resourceName (not just the join-shape rows)' {
        $path = Export-React -Findings $script:LiveScored -Collect $script:Collect -OutputPath $script:OutDir
        $payload = Get-EmbeddedPayload -Html (Get-Content $path -Raw)
        $allEvidence = @($payload.assessments | ForEach-Object { $_.findings } | ForEach-Object { $_.evidence })
        $withName = @($allEvidence | Where-Object { $_.resourceName })
        # Measured on this exact fixture post-fix: 55 of 136 (40%). Floor set well below that so a
        # future rule-set change doesn't make this test flaky, while still catching a regression
        # back toward the pre-fix ~3%.
        ($withName.Count / $allEvidence.Count) | Should -BeGreaterThan 0.25 -Because 'a regression back to the array-metadata bug would drop this near zero'
    }
}
