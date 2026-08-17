#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . "$PSScriptRoot/../src/collect/ConvertTo-ScoutDefenderDerivedEvidence.ps1"
}

Describe 'ConvertTo-ScoutDefenderDerivedEvidence' {
    It 'groups unhealthy assessments and links remaining secure-score impact without discarding source identifiers' {
        $sweep = [pscustomobject]@{
            type = 'AZSC/Subscription/SecurityPolicySweep'; subscriptionId = 'sub-1'
            properties = [pscustomobject]@{
                DefenderAssessments = @(
                    [pscustomobject]@{ Name='assessment-a'; DisplayName='Close management ports'; Status=[pscustomobject]@{Code='Unhealthy';Severity='High'}; ResourceDetails=[pscustomobject]@{Id='/vm/one'} },
                    [pscustomobject]@{ Name='assessment-a'; DisplayName='Close management ports'; Status=[pscustomobject]@{Code='Unhealthy';Severity='High'}; ResourceDetails=[pscustomobject]@{Id='/vm/two'} },
                    [pscustomobject]@{ Name='healthy'; DisplayName='Healthy item'; Status=[pscustomobject]@{Code='Healthy'} }
                )
                DefenderSecureScoreControls = @(
                    [pscustomobject]@{ DisplayName='Restrict access'; Score=[pscustomobject]@{Current=2;Max=8}; AssessmentDefinitions=@('/providers/Microsoft.Security/assessmentMetadata/assessment-a') }
                )
            }
        }

        $result = @(ConvertTo-ScoutDefenderDerivedEvidence -Resources @($sweep))
        $result.Count | Should -Be 1
        $result[0].properties.UnhealthyResourceCount | Should -Be 2
        $result[0].properties.PotentialScoreImpact | Should -Be 6
        $result[0].properties.ResourceIds | Should -Contain '/vm/one'
        $result[0].AZSC.SourceDatasets | Should -Contain 'DefenderAssessments'
    }

    It 'states that impact is unavailable when Azure omits the score-control mapping' {
        $sweep = [pscustomobject]@{
            type='AZSC/Subscription/SecurityPolicySweep'; subscriptionId='sub-2'
            properties=[pscustomobject]@{ DefenderAssessments=@([pscustomobject]@{Name='a';DisplayName='A';Status=[pscustomobject]@{Code='Unhealthy'}});DefenderSecureScoreControls=@() }
        }
        $result = @(ConvertTo-ScoutDefenderDerivedEvidence -Resources @($sweep))
        $result[0].properties.PotentialScoreImpact | Should -BeNullOrEmpty
        $result[0].properties.ScoreImpactStatus | Should -Match '^Unavailable:'
    }
}
