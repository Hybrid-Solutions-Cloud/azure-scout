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

Describe 'Query context cost while a transcript is active (AB#9300)' {
    # Every scan starts a transcript (Start-AZSCRunLog). While one is active PowerShell stringifies
    # each argument a command is bound to: a [pscustomobject] argument has ToString() called on every
    # property value. Once the index is built the context's `Token` is the whole collect as a JToken,
    # so a [pscustomobject] context re-serialised the entire document on every Invoke-Rule,
    # Resolve-JsonPath and Resolve-RuleJoin call -- ~0.55 s each on a 30 MB collect, 426 s over 722
    # rule evaluations. The probe counts ToString() calls so the guard needs no timing threshold.
    BeforeAll {
        if (-not ('ScoutQueryContextProbe' -as [type])) {
            Add-Type -TypeDefinition @'
public sealed class ScoutQueryContextProbe
{
    public static int ToStringCalls;
    public override string ToString() { ToStringCalls++; return "probe"; }
}
'@
        }
        # Binding the argument is the whole point; the body only has to exist.
        function Invoke-ProbeBind { param($Argument) $null = $PSBoundParameters }

        # Runs $Action with a transcript active and returns how many times the probe was stringified.
        # $null means the host cannot transcribe, so the caller skips rather than passing vacuously.
        function Measure-ProbeUnderTranscript {
            param([scriptblock]$Action)
            $path = Join-Path $TestDrive ("transcript-{0}.log" -f [guid]::NewGuid().ToString('N'))
            try { $null = Start-Transcript -Path $path -Force }
            catch { return $null }
            try {
                [ScoutQueryContextProbe]::ToStringCalls = 0
                & $Action
                return [ScoutQueryContextProbe]::ToStringCalls
            }
            finally { $null = Stop-Transcript }
        }

        # The probe only proves something if this host really does stringify arguments under
        # transcription -- the old [pscustomobject] shape is the positive control.
        $script:ControlCalls = Measure-ProbeUnderTranscript {
            Invoke-ProbeBind -Argument ([pscustomobject]@{ Token = [ScoutQueryContextProbe]::new() })
        }
    }

    It 'builds the context as a hashtable carrying InputObject, Token and ParseCount' {
        $inputData = [pscustomobject]@{ rows = @() }
        $context = New-ScoutQueryContext $inputData
        $context | Should -BeOfType [hashtable]
        [object]::ReferenceEquals($context.InputObject, $inputData) | Should -BeTrue
        $context.Token | Should -BeNullOrEmpty
        $context.ParseCount | Should -Be 0
    }

    It 'does not stringify the index when the context is passed to a command' {
        if ($null -eq $script:ControlCalls) { Set-ItResult -Skipped -Because 'this host cannot start a transcript'; return }
        if ($script:ControlCalls -lt 1) { Set-ItResult -Skipped -Because 'this host does not stringify arguments under transcription, so the regression cannot be observed'; return }
        $context = New-ScoutQueryContext ([pscustomobject]@{ rows = @() })
        $context.Token = [ScoutQueryContextProbe]::new()
        $calls = Measure-ProbeUnderTranscript { Invoke-ProbeBind -Argument $context }
        $calls | Should -Be 0
    }

    It 'does not stringify the index on the per-rule path: Invoke-Rule, Resolve-JsonPath and Invoke-Assessment' {
        if ($null -eq $script:ControlCalls) { Set-ItResult -Skipped -Because 'this host cannot start a transcript'; return }
        if ($script:ControlCalls -lt 1) { Set-ItResult -Skipped -Because 'this host does not stringify arguments under transcription, so the regression cannot be observed'; return }
        $inputData = [pscustomobject]@{
            rows  = @([pscustomobject]@{ id = 'a'; name = 'one' }, [pscustomobject]@{ id = 'b'; name = 'two' })
            other = @([pscustomobject]@{ ref = 'a' })
        }
        # Token is the probe, not a real index: a manual rule with no query never reads Token, so
        # nothing but argument stringification can touch it.
        $probeContext = New-ScoutQueryContext $inputData
        $probeContext.Token = [ScoutQueryContextProbe]::new()
        $manual = [pscustomobject]@{
            id = 'PERF-M'; title = 't'; severity = 'low'; manual = $true; query = $null
            assert = [pscustomobject]@{ type = 'manual' }; remediation = 'r'
        }
        $set = [pscustomobject]@{ Area = 'Test'; Framework = 'CAF'; Rules = @($manual) }
        $calls = Measure-ProbeUnderTranscript {
            $null = Invoke-Rule -Rule $manual -Collect $inputData -QueryContext $probeContext
            $null = Resolve-JsonPath -InputObject $inputData -QueryContext $probeContext -Path ''
            $null = Invoke-Assessment -Collect $inputData -RuleSet @($set) -Assessment 'Probe' -QueryContext $probeContext
        }
        $calls | Should -Be 0
    }

    It 'produces identical findings with and without an active transcript' {
        $inputData = [pscustomobject]@{
            rows    = @([pscustomobject]@{ id = 'a'; public = $true }, [pscustomobject]@{ id = 'b'; public = $false }, [pscustomobject]@{ id = 'c'; public = $true })
            related = @([pscustomobject]@{ ref = 'a' })
        }
        $rules = @(
            [pscustomobject]@{ id = 'T-1'; title = 'exists'; severity = 'high'; manual = $false; query = '$.rows[?(@.public == true)]'; assert = [pscustomobject]@{ type = 'countEquals'; value = 0 }; remediation = 'fix' }
            [pscustomobject]@{ id = 'T-2'; title = 'percent'; severity = 'low'; manual = $false; query = '$.rows[?(@.public == false)]'; assert = [pscustomobject]@{ type = 'percentageAtLeast'; value = 50; denominatorQuery = '$.rows[*]' }; remediation = 'fix' }
            [pscustomobject]@{ id = 'T-3'; title = 'manual'; severity = 'low'; manual = $true; query = '$.rows[*]'; assert = [pscustomobject]@{ type = 'manual' }; remediation = 'review' }
            [pscustomobject]@{ id = 'T-4'; title = 'join'; severity = 'medium'; manual = $false; assert = [pscustomobject]@{ type = 'countEquals'; value = 0 }; remediation = 'link'
                join = [pscustomobject]@{ left = '$.rows[*]'; leftKey = 'id'; right = '$.related[*]'; rightKey = 'ref'; mode = 'leftOnly' } }
        )
        $set = [pscustomobject]@{ Area = 'Test'; Framework = 'CAF'; FrameworkVersion = '1'; Weight = 1.0; Rules = $rules }
        $project = {
            param($Findings)
            @($Findings | ForEach-Object {
                    $evidence = @($_.Evidence | ForEach-Object {
                            if ($_ -is [Newtonsoft.Json.Linq.JToken]) { $_.ToString([Newtonsoft.Json.Formatting]::None) }
                            else { $_ | ConvertTo-Json -Depth 10 -Compress }
                        })
                    '{0}|{1}|{2}|{3}|{4}' -f $_.Id, $_.Status, $_.EvidenceCount, $_.Assessment, ($evidence -join ',')
                })
        }
        $plain = & $project (Invoke-Assessment -Collect $inputData -RuleSet @($set) -Assessment 'Parity' -QueryContext (New-ScoutQueryContext $inputData))

        $path = Join-Path $TestDrive 'parity-transcript.log'
        try { $null = Start-Transcript -Path $path -Force } catch { Set-ItResult -Skipped -Because 'this host cannot start a transcript'; return }
        try { $transcribed = & $project (Invoke-Assessment -Collect $inputData -RuleSet @($set) -Assessment 'Parity' -QueryContext (New-ScoutQueryContext $inputData)) }
        finally { $null = Stop-Transcript }

        $plain.Count | Should -Be 4
        $transcribed | Should -Be $plain
        ($plain -join "`n") | Should -Match 'T-1\|Fail\|2\|Parity'
        ($plain -join "`n") | Should -Match 'T-4\|Fail\|2\|Parity'
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
