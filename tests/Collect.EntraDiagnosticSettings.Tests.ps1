#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/collect/Get-ScoutEntraDiagnosticSettingEvidence.ps1')
}

Describe 'Get-ScoutEntraDiagnosticSettingEvidence' {
    AfterEach { Remove-Item Function:global:Invoke-AzRestMethod -Force -ErrorAction SilentlyContinue }

    It 'retains full tenant diagnostic settings with source provenance' {
        function global:Invoke-AzRestMethod {
            param($Path,$Method,$ErrorAction)
            $null=$Method,$ErrorAction
            $Path | Should -Be '/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01'
            [pscustomobject]@{StatusCode=200;Content=(@{value=@(@{id='/providers/microsoft.aadiam/diagnosticSettings/export';name='export';properties=@{workspaceId='/subscriptions/sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law';logs=@(@{category='SignInLogs';enabled=$true})}})}|ConvertTo-Json -Depth 10 -Compress)}
        }
        $result=Get-ScoutEntraDiagnosticSettingEvidence
        @($result.Resources).Count | Should -Be 1
        $result.Resources[0].properties.Raw.properties.logs[0].category | Should -Be 'SignInLogs'
        $result.Resources[0].AZSC.Uri | Should -Match 'microsoft.aadiam/diagnosticSettings'
        $result.SourceOperations[0].Status | Should -Be 'Success'
        @($result.CollectionHealth).Count | Should -Be 0
    }

    It 'records an authorization gap without claiming exports are absent' {
        function global:Invoke-AzRestMethod { throw 'HTTP 403 AuthorizationFailed' }
        $result=Get-ScoutEntraDiagnosticSettingEvidence
        @($result.Resources).Count | Should -Be 0
        $result.SourceOperations[0].Status | Should -Be 'Unavailable'
        $result.CollectionHealth[0].Status | Should -Be 'Unavailable'
    }

    It 'ships an importable Entra export manifest' {
        { Import-PowerShellDataFile (Join-Path $script:RepoRoot 'manifests/collectors/Identity/EntraDiagnosticSettings.psd1') } | Should -Not -Throw
    }
}
