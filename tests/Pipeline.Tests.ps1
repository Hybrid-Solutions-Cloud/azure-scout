#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for the unattended pipeline wrapper (src/Invoke-ScoutPipeline.ps1).

.DESCRIPTION
    The internal assessment core (and, transitively, Test-ScoutPermission) is mocked
    throughout -- no Azure call is ever made. Validates:
      - pipeline-summary.json is written with the documented schema keys
      - outcome is computed correctly for Success / PartialSuccess (exporter
        throws mid-run, or the permission audit hard-fails) / Failed (the
        orchestrator returns nothing and creates no run folder)
      - Failed throws (and sets $global:LASTEXITCODE = 1); Success/PartialSuccess
        return the run folder normally
      - non-interactive preferences ($ConfirmPreference / $ProgressPreference) are
        set for the duration of the orchestrator call
      - -SkipPermissionAudit actually skips the -PermissionAudit call
      - -ManagementGroupId / -Category are threaded through to the orchestrator call

    Tracks ADO AB#5050.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    # Dot-source the real orchestrator purely so Mock has a command with a matching
    # parameter set to attach a proxy to -- its body is never actually executed here.
    . "$root/src/Invoke-ScoutAssessmentCore.ps1"
    . "$root/src/Get-ScoutNewErrorCount.ps1"
    . "$root/src/Invoke-ScoutPipeline.ps1"

    function Get-OkPermissionCheck {
        [pscustomobject]@{ Check = 'ARM Reader @ MG root'; Ok = $true; Fix = 'Assign Reader at the tenant root management group scope.' }
    }
    function Get-FailedPermissionCheck {
        [pscustomobject]@{ Check = 'ARM Reader @ MG root'; Ok = $false; Fix = 'Assign Reader at the tenant root management group scope.' }
    }
}

Describe 'Invoke-ScoutPipeline -- renderer contract' {
    It 'accepts every format exposed by the assessment core' {
        $pipeline = Get-Command Invoke-ScoutPipeline
        $core = Get-Command Invoke-ScoutAssessmentCore
        $pipelineValues = ($pipeline.Parameters.OutputFormat.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues
        $coreValues = ($core.Parameters.OutputFormat.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues

        foreach ($format in $coreValues) {
            $pipelineValues | Should -Contain $format
        }
    }

    It 'uses an explicit reserved run path instead of directory-delta recovery' {
        $source = Get-Content -LiteralPath (Join-Path $root 'src/Invoke-ScoutPipeline.ps1') -Raw
        $source | Should -Match '\$assessParams\.ReservedRunPath\s*=\s*\$runFolder'
        $source | Should -Not -Match '\$priorRunFolders|\$recovered\s*='
    }
}

Describe 'Invoke-ScoutPipeline -- effective output formats' {
    BeforeEach {
        $script:outPath = Join-Path -Path $TestDrive -ChildPath "output-$([guid]::NewGuid())"
        Mock Invoke-ScoutAssessmentCore {
            $folder = $ReservedRunPath
            '{}' | Out-File (Join-Path -Path $folder -ChildPath 'collect.json')
            return $folder
        }
        Mock Write-Warning
    }

    It 'expands All to exactly React, Json, and JsonEvidence in execution and summaries' {
        $runFolder = Invoke-ScoutPipeline -OutputFormat All -OutputPath $script:outPath -SkipPermissionAudit

        Should -Invoke Invoke-ScoutAssessmentCore -Times 1 -Exactly -ParameterFilter {
            -not $PermissionAudit -and @($OutputFormat).Count -eq 3 -and
                $OutputFormat[0] -eq 'React' -and $OutputFormat[1] -eq 'Json' -and
                $OutputFormat[2] -eq 'JsonEvidence'
        }
        $summary = Get-Content (Join-Path $runFolder 'pipeline-summary.json') -Raw | ConvertFrom-Json
        @($summary.requestedFormats) | Should -Be @('All')
        @($summary.formats) | Should -Be @('React', 'Json', 'JsonEvidence')
        Get-Content (Join-Path $runFolder 'pipeline-summary.md') -Raw |
            Should -Match '(?m)^- Formats: React, Json, JsonEvidence$'
    }

    It 'falls back from a held-only request to React and records the effective output' {
        $runFolder = Invoke-ScoutPipeline -OutputFormat Word -OutputPath $script:outPath -SkipPermissionAudit

        Should -Invoke Invoke-ScoutAssessmentCore -Times 1 -Exactly -ParameterFilter {
            -not $PermissionAudit -and @($OutputFormat).Count -eq 1 -and $OutputFormat[0] -eq 'React'
        }
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*on hold*Word*' }
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*every requested*React*' }
        $summary = Get-Content (Join-Path $runFolder 'pipeline-summary.json') -Raw | ConvertFrom-Json
        @($summary.requestedFormats) | Should -Be @('Word')
        @($summary.formats) | Should -Be @('React')
        Get-Content (Join-Path $runFolder 'pipeline-summary.md') -Raw |
            Should -Match '(?m)^- Formats: React$'
    }

    It 'drops held names from a mixed request and runs only the requested live format' {
        $runFolder = Invoke-ScoutPipeline -OutputFormat Excel,Json -OutputPath $script:outPath -SkipPermissionAudit

        Should -Invoke Invoke-ScoutAssessmentCore -Times 1 -Exactly -ParameterFilter {
            -not $PermissionAudit -and @($OutputFormat).Count -eq 1 -and $OutputFormat[0] -eq 'Json'
        }
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*on hold*Excel*' }
        $summary = Get-Content (Join-Path $runFolder 'pipeline-summary.json') -Raw | ConvertFrom-Json
        @($summary.requestedFormats) | Should -Be @('Excel', 'Json')
        @($summary.formats) | Should -Be @('Json')
        Get-Content (Join-Path $runFolder 'pipeline-summary.md') -Raw |
            Should -Match '(?m)^- Formats: Json$'
    }
}

Describe 'Invoke-ScoutPipeline -- Success path' {
    BeforeEach {
        # A unique folder name per test -- the mock below writes a fixed run-folder
        # name, and leftover folders from an earlier test in the same $TestDrive
        # would otherwise be mistaken for "already existed before this call" by the
        # exception-recovery directory scan.
        $script:outPath = Join-Path -Path $TestDrive -ChildPath "output-$([guid]::NewGuid())"
        $script:seenConfirm  = $null
        $script:seenProgress = $null

        Mock Invoke-ScoutAssessmentCore {
            if ($PermissionAudit) { return @(Get-OkPermissionCheck) }

            $script:seenConfirm  = $ConfirmPreference
            $script:seenProgress = $ProgressPreference

            $folder = $ReservedRunPath
            '{}' | Out-File (Join-Path -Path $folder -ChildPath 'collect.json')
            @{ Findings = @(@{ Status = 'Pass' }, @{ Status = 'Pass' }, @{ Status = 'Fail' }, @{ Status = 'Manual' }) } |
                ConvertTo-Json -Depth 5 | Out-File (Join-Path -Path $folder -ChildPath 'findings.json')
            return $folder
        }
    }

    It 'returns the run folder path' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        $runFolder | Should -Not -BeNullOrEmpty
        Test-Path $runFolder | Should -BeTrue
    }

    It 'writes pipeline-summary.json with every documented schema key' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        $summaryPath = Join-Path -Path $runFolder -ChildPath 'pipeline-summary.json'
        Test-Path $summaryPath | Should -BeTrue

        $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
        $keys = $summary.PSObject.Properties.Name
        foreach ($expected in 'schemaVersion', 'startedOn', 'finishedOn', 'elapsedSeconds',
                              'assessments', 'requestedFormats', 'formats', 'managementGroupId', 'runFolder',
                              'assessmentStatus', 'findingsByStatus', 'permissionAudit',
                              'assessmentError', 'outcome') {
            $keys | Should -Contain $expected
        }
    }

    It 'writes a human-readable pipeline-summary.md' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        Test-Path (Join-Path -Path $runFolder -ChildPath 'pipeline-summary.md') | Should -BeTrue
    }

    It 'computes outcome Success when the audit passes and the orchestrator returns cleanly' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        $summary = Get-Content (Join-Path -Path $runFolder -ChildPath 'pipeline-summary.json') -Raw | ConvertFrom-Json
        $summary.outcome | Should -Be 'Success'
        $summary.assessmentError | Should -BeNullOrEmpty
    }

    It 'computes findings counts by Status from findings.json' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        $summary = Get-Content (Join-Path -Path $runFolder -ChildPath 'pipeline-summary.json') -Raw | ConvertFrom-Json
        $summary.findingsByStatus.Pass   | Should -Be 2
        $summary.findingsByStatus.Fail   | Should -Be 1
        $summary.findingsByStatus.Manual | Should -Be 1
    }

    It 'sets non-interactive preferences for the duration of the orchestrator call' {
        Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath | Out-Null
        "$script:seenConfirm"  | Should -Be 'None'
        "$script:seenProgress" | Should -Be 'SilentlyContinue'
    }

    It 'does not throw' {
        { Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath } | Should -Not -Throw
    }

    It 'threads -ManagementGroupId and -Category through to the orchestrator call' {
        Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath -ManagementGroupId 'contoso-root-mg' -Category 'Security' | Out-Null
        Should -Invoke Invoke-ScoutAssessmentCore -ParameterFilter {
            -not $PermissionAudit -and $ManagementGroupId -eq 'contoso-root-mg' -and ($Category -contains 'Security')
        } -Times 1
    }
}

Describe 'Invoke-ScoutPipeline -- -SkipPermissionAudit' {
    BeforeEach {
        $script:outPath = Join-Path -Path $TestDrive -ChildPath "output-$([guid]::NewGuid())"
        Mock Invoke-ScoutAssessmentCore {
            if ($PermissionAudit) { return @(Get-OkPermissionCheck) }
            $folder = $ReservedRunPath
            '{}' | Out-File (Join-Path -Path $folder -ChildPath 'collect.json')
            return $folder
        }
    }

    It 'never calls the assessment core -PermissionAudit mode' {
        Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath -SkipPermissionAudit | Out-Null
        Should -Invoke Invoke-ScoutAssessmentCore -ParameterFilter { $PermissionAudit } -Times 0 -Exactly
    }

    It 'records the audit as Skipped in the summary' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath -SkipPermissionAudit
        $summary = Get-Content (Join-Path -Path $runFolder -ChildPath 'pipeline-summary.json') -Raw | ConvertFrom-Json
        $summary.permissionAudit.Skipped | Should -BeTrue
        $summary.permissionAudit.Ran     | Should -BeFalse
    }
}

Describe 'Invoke-ScoutPipeline -- PartialSuccess (exporter throws mid-run)' {
    BeforeEach {
        $script:outPath = Join-Path -Path $TestDrive -ChildPath "output-$([guid]::NewGuid())"
        Mock Invoke-ScoutAssessmentCore {
            if ($PermissionAudit) { return @(Get-OkPermissionCheck) }
            # Simulate the orchestrator getting partway through (collect.json written)
            # before an exporter throws -- the run folder exists but is incomplete.
            $folder = $ReservedRunPath
            '{}' | Out-File (Join-Path -Path $folder -ChildPath 'collect.json')
            throw 'Export-Pptx: simulated exporter failure'
        }
    }

    It 'does not throw -- degrades to PartialSuccess instead of killing the run' {
        { Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath } | Should -Not -Throw
    }

    It 'retains its reserved run folder when the orchestrator throws' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        $runFolder | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path -Path $runFolder -ChildPath 'collect.json') | Should -BeTrue
    }

    It 'computes outcome PartialSuccess and captures the error message' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        $summary = Get-Content (Join-Path -Path $runFolder -ChildPath 'pipeline-summary.json') -Raw | ConvertFrom-Json
        $summary.outcome | Should -Be 'PartialSuccess'
        $summary.assessmentError | Should -Match 'simulated exporter failure'
    }
}

Describe 'Invoke-ScoutPipeline -- PartialSuccess (permission audit hard failure)' {
    BeforeEach {
        $script:outPath = Join-Path -Path $TestDrive -ChildPath "output-$([guid]::NewGuid())"
        Mock Invoke-ScoutAssessmentCore {
            if ($PermissionAudit) { return @(Get-FailedPermissionCheck) }
            $folder = $ReservedRunPath
            '{}' | Out-File (Join-Path -Path $folder -ChildPath 'collect.json')
            @{ Findings = @(@{ Status = 'Pass' }) } | ConvertTo-Json -Depth 5 | Out-File (Join-Path -Path $folder -ChildPath 'findings.json')
            return $folder
        }
    }

    It 'does not throw even when the permission audit hard-fails' {
        { Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath } | Should -Not -Throw
    }

    It 'computes outcome PartialSuccess despite a clean orchestrator run' {
        $runFolder = Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath
        $summary = Get-Content (Join-Path -Path $runFolder -ChildPath 'pipeline-summary.json') -Raw | ConvertFrom-Json
        $summary.outcome | Should -Be 'PartialSuccess'
        $summary.permissionAudit.Ok | Should -BeFalse
    }
}

Describe 'Invoke-ScoutPipeline -- Failed (assess returns nothing)' {
    BeforeEach {
        $script:outPath = Join-Path -Path $TestDrive -ChildPath "output-$([guid]::NewGuid())"
        Mock Invoke-ScoutAssessmentCore {
            if ($PermissionAudit) { return @(Get-OkPermissionCheck) }
            # Simulate total failure: no folder created, nothing returned.
            return $null
        }
    }

    It 'throws' {
        { Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath } | Should -Throw
    }

    It 'sets $global:LASTEXITCODE to 1' {
        try { Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath }
        catch { Write-Verbose "Expected failure captured: $_" -Verbose:$false }
        $global:LASTEXITCODE | Should -Be 1
    }

    It 'the thrown message mentions the run produced no output' {
        { Invoke-ScoutPipeline -Assessment 'CAF: Azure Landing Zone' -OutputPath $script:outPath } | Should -Throw -ExpectedMessage '*produced no output*'
    }
}
