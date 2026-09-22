#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Sentinel ingestion evidence' {
    BeforeAll {
        . "$PSScriptRoot/../src/collect/Get-ScoutArmChildResource.ps1"
        function global:Get-AzContext { [pscustomobject]@{ Environment = [pscustomobject]@{ Name='AzureCloud' } } }
        function global:Get-AzEnvironment { [pscustomobject]@{ AzureKeyVaultDnsSuffix='vault.azure.net'; AzureKeyVaultServiceEndpointResourceId='https://vault.azure.net' } }
        function global:Invoke-AzRestMethod { throw 'ARM should not be called by this dataset' }
        function global:Invoke-WebRequest { throw 'Key Vault should not be called by this dataset' }
    }
    AfterAll {
        foreach ($name in 'Get-AzContext','Get-AzEnvironment','Invoke-AzRestMethod','Invoke-WebRequest','Get-AzAccessToken','Invoke-RestMethod') {
            Remove-Item "function:global:$name" -ErrorAction SilentlyContinue
        }
    }
    BeforeEach {
        $script:parent = [pscustomobject]@{
            id='/subscriptions/sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law'
            type='microsoft.operationalinsights/workspaces'; name='law'; subscriptionId='sub'; resourceGroup='rg'; location='eastus'
            properties=[pscustomobject]@{customerId='workspace-guid'}
        }
        function global:Get-AzAccessToken { param($ResourceUrl,[switch]$AsSecureString,$ErrorAction) $null=$ResourceUrl,$AsSecureString,$ErrorAction; [pscustomobject]@{Token=[securestring]::new()} }
        function global:Invoke-RestMethod {
            param($Uri,$Method,$Authentication,$Token,$ContentType,$Body,$ErrorAction)
            $null=$Uri,$Method,$Authentication,$Token,$ContentType,$Body,$ErrorAction
            '{"tables":[{"columns":[{"name":"TableName"},{"name":"LastRecord"},{"name":"Count"}],"rows":[["SigninLogs","2026-08-15T00:00:00Z",42]]}]}' | ConvertFrom-Json
        }
    }

    It 'retains query results and exact authentication and query operations' {
        $operations=[System.Collections.Generic.List[object]]::new();$health=[System.Collections.Generic.List[object]]::new()
        $rows=@(Get-ScoutArmChildResource -Resources @($script:parent) -Dataset SentinelIngestion -SourceOperations $operations -CollectionHealth $health)
        $rows.Count | Should -Be 1
        $rows[0].TableName | Should -Be 'SigninLogs'
        @($operations | Where-Object Operation -eq 'Acquire Log Analytics query token').Status | Should -Be 'Success'
        @($operations | Where-Object Operation -eq 'POST query')[0].Count | Should -Be 1
        $rows[0].AZSC.Source | Should -Be 'Azure Monitor Logs Query API'
    }

    It 'records token failures without pretending that an empty query succeeded' {
        function global:Get-AzAccessToken { throw '403 token denied' }
        $operations=[System.Collections.Generic.List[object]]::new();$health=[System.Collections.Generic.List[object]]::new()
        $rows=@(Get-ScoutArmChildResource -Resources @($script:parent) -Dataset SentinelIngestion -SourceOperations $operations -CollectionHealth $health)
        $rows.Count | Should -Be 0
        $operations[0].Status | Should -Be 'Unavailable'
        $operations[0].Reason | Should -Match '403'
        $health[0].Status | Should -Be 'Unavailable'
    }

    It 'records a workspace without a query id as unavailable' {
        $script:parent.properties = [pscustomobject]@{}
        $operations=[System.Collections.Generic.List[object]]::new();$health=[System.Collections.Generic.List[object]]::new()
        $rows=@(Get-ScoutArmChildResource -Resources @($script:parent) -Dataset SentinelIngestion -SourceOperations $operations -CollectionHealth $health)
        $rows.Count | Should -Be 0
        @($operations | Where-Object Operation -eq 'POST query')[0].Status | Should -Be 'Unavailable'
        $health[0].Reason | Should -Match 'customerId'
    }
}
