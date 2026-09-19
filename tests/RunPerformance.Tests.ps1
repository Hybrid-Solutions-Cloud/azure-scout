#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/src/assess/engine/Resolve-JsonPath.ps1"
    . "$root/src/assess/engine/Invoke-Rule.ps1"
    . "$root/src/assess/engine/Resolve-RuleJoin.ps1"
    . "$root/src/assess/Invoke-Assessment.ps1"
    . "$root/src/pipeline/Get-ScoutResourceCompleteness.ps1"
    . "$root/src/pipeline/diagram/New-ScoutUniversalRelationshipDiagram.ps1"
    function New-PerformanceRule {
        param([bool]$Manual = $false)
        [pscustomobject]@{
            id = 'PERF-1'; title = 'test'; severity = 'high'; manual = $Manual
            query = '$.rows[*]'; assert = [pscustomobject]@{ type = 'countEquals'; value = 0 }
            remediation = 'test'
        }
    }
}

Describe 'Run-owned assessment query index (AB#9303, AB#9304)' {
    It 'shares the index across assessment groups including prerequisite checks' {
        $inputData = [pscustomobject]@{ rows = @([pscustomobject]@{ name = 'one' }) }
        $context = New-ScoutQueryContext $inputData
        $set = [pscustomobject]@{
            Area = 'Test'; Framework = 'CAF'; Rules = @((New-PerformanceRule))
            Requires = @([pscustomobject]@{ path = '$.rows[*]'; description = 'Rows' })
        }
        foreach ($name in @('First', 'Second')) {
            $findings = @(Invoke-Assessment -Collect $inputData -RuleSet @($set) -Assessment $name -QueryContext $context)
            $findings.Count | Should -Be 1
            $findings[0].Status | Should -Be 'Fail'
            $findings[0].Assessment | Should -Be $name
        }
        $context.ParseCount | Should -Be 1
    }

    It 'parses once across queries and rules and detaches finding evidence from the root' {
        $inputData = [pscustomobject]@{ rows = @([pscustomobject]@{ name = 'one' }); unrelated = 'large branch' }
        $context = New-ScoutQueryContext $inputData
        (Resolve-JsonPath $inputData '' -QueryContext $context).Count | Should -Be 0
        $context.ParseCount | Should -Be 0
        (Resolve-JsonPath $inputData '$.rows[*]' -QueryContext $context).Count | Should -Be 1
        foreach ($manual in @($false, $true)) {
            $finding = Invoke-Rule -Rule (New-PerformanceRule $manual) -Collect $inputData -QueryContext $context
            $finding.EvidenceCount | Should -Be 1
            $finding.Evidence.Count | Should -Be 1
            $finding.Evidence[0].get_Parent() | Should -BeNullOrEmpty
            $finding.Evidence[0].ToString() | Should -Not -Match 'unrelated'
            $finding.Status | Should -Be $(if ($manual) { 'Manual' } else { 'Fail' })
        }
        $context.ParseCount | Should -Be 1
    }

    It 'rejects a context from another snapshot and keeps malformed paths as errors' {
        $inputData = [pscustomobject]@{ rows = @() }
        $context = New-ScoutQueryContext $inputData
        { Resolve-JsonPath ([pscustomobject]@{ rows = @() }) '$.rows[*]' -QueryContext $context } | Should -Throw '*different*'
        { Resolve-JsonPath $inputData '$.rows[?(' -QueryContext $context } | Should -Throw
        $next = New-ScoutQueryContext $inputData
        (Resolve-JsonPath $inputData '$.rows[*]' -QueryContext $next).Count | Should -Be 0
        $next.ParseCount | Should -Be 1
    }

    It 'preserves nested array evidence without retaining its parent collection' {
        $inputData = [pscustomobject]@{ rows = @(@{ children = @(1, 2) }, @{ children = @(3, 4) }) }
        $finding = Invoke-Rule -Rule (New-PerformanceRule) -Collect $inputData
        $finding.EvidenceCount | Should -Be 2
        $finding.Evidence.Count | Should -Be 2
        foreach ($row in $finding.Evidence) {
            $row.get_Parent() | Should -BeNullOrEmpty
            $row['children'].Count | Should -Be 2
        }
    }
}

Describe 'Run-owned discovery reuse (AB#9300, AB#9302)' {
    BeforeEach {
        $resource = [pscustomobject]@{
            id = '/subscriptions/test/resourceGroups/test/providers/Contoso/widgets/one'
            name = 'one'; type = 'Contoso/widgets'; properties = [pscustomobject]@{ enabled = $true }
        }
        $other = [pscustomobject]@{
            id = '/subscriptions/test/resourceGroups/test/providers/Contoso/widgets/two'
            name = 'two'; type = 'Contoso/widgets'; properties = [pscustomobject]@{ enabled = $true }
        }
        $collector = [pscustomobject]@{ FolderCategory = 'Test'; Name = 'Widgets'; ResourceTypes = @('Contoso/widgets') }
    }

    It 'builds once for multiple consumers while preserving independent coverage and resource views' {
        $context = New-ScoutDiscoveryContext @($resource, $other)
        $first = Get-ScoutResourceCompleteness @($resource) -Collectors @() -DiscoveryContext $context
        $health = [pscustomobject]@{ Collectors = @('Test/Widgets'); Reason = 'Forbidden' }
        $second = Get-ScoutResourceCompleteness @($resource, $other) -Collectors @($collector) -CollectionHealth @($health) -DiscoveryContext $context
        $third = Get-ScoutResourceCompleteness @($resource) -Collectors @($collector) -DiscoveryContext $context
        $context.BuildCount | Should -Be 1
        $first.Summary.Resources | Should -Be 1
        $first.Resources[0].DetailStatus | Should -Be 'GenericOnly'
        $second.Summary.Resources | Should -Be 2
        $second.Summary.Partial | Should -Be 2
        $second.Resources[0].DetailReasons | Should -Contain 'Forbidden'
        $third.Summary.Detailed | Should -Be 1
        $third.Resources[0].CollectionHealth.Count | Should -Be 0
        $standalone = Get-ScoutResourceCompleteness @($resource) -Collectors @($collector)
        ($third | ConvertTo-Json -Depth 30) | Should -Be ($standalone | ConvertTo-Json -Depth 30)
    }

    It 'rejects resources from another tenant or snapshot instead of silently reusing stale evidence' {
        $context = New-ScoutDiscoveryContext @($resource)
        { Get-ScoutResourceCompleteness @($other) -Collectors @() -DiscoveryContext $context } | Should -Throw '*different*'
    }

    It 'uses the same discovery index in the actual diagram renderer and later report view' {
        $resource.properties | Add-Member -NotePropertyName target -NotePropertyValue $other.id
        $context = New-ScoutDiscoveryContext @($resource, $other)
        $path = Join-Path $TestDrive 'relationships.drawio'
        $diagram = New-ScoutUniversalRelationshipDiagram -Resources @($resource, $other) -Path $path -DiscoveryContext $context
        $report = Get-ScoutResourceCompleteness @($resource, $other) -Collectors @($collector) -DiscoveryContext $context
        $context.BuildCount | Should -Be 1
        $diagram.Relationships | Should -Be 1
        $report.Summary.Relationships | Should -Be 1
        [xml]$xml = Get-Content $path -Raw
        @($xml.SelectNodes('//mxCell[@edge="1"]')).Count | Should -Be 1
    }

    It 'does not reflect into typed timestamps while still discovering sibling ARM references' {
        $script:timestampReads = 0
        $timestamp = [datetime]'2026-01-01T00:00:00Z'
        $timestamp | Add-Member -MemberType ScriptProperty -Name Probe -Value { $script:timestampReads++; return '/subscriptions/incorrect' }
        $payload = [pscustomobject]@{ created = $timestamp; target = $other.id }
        $references = @(Get-ScoutArmReference -InputObject $payload)
        $script:timestampReads | Should -Be 0
        $references.Count | Should -Be 1
        $references[0].TargetId | Should -Be $other.id
    }
}
