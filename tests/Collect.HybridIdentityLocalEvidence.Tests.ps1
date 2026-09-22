#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll{$script:RepoRoot=Split-Path -Parent $PSScriptRoot;. (Join-Path $script:RepoRoot 'src/collect/Get-ScoutHybridIdentityLocalEvidence.ps1')}

Describe 'Get-ScoutHybridIdentityLocalEvidence' {
    BeforeEach{
        function global:Get-ADSyncScheduler{[pscustomobject]@{SyncCycleEnabled=$true;StagingModeEnabled=$false;NextSyncCyclePolicyType='Delta'}}
        function global:Get-ADSyncConnector{[pscustomobject]@{Name='contoso.com';ConnectorTypeName='AD'}}
        function global:Get-ADSyncGlobalSettings{[pscustomobject]@{Name='Global';Parameters=@()}}
        function global:Get-CimInstance{param($ClassName,$Filter);$null=$ClassName,$Filter;[pscustomobject]@{Name='ADSync';State='Running';PathName='C:\Program Files\Microsoft Azure AD Sync\Bin\miiserver.exe'}}
        function global:Get-Service{param($Name,$ErrorAction);$null=$Name,$ErrorAction;[pscustomobject]@{Name='AzureADConnectHealthSyncMonitor';Status='Running'}}
        function global:Get-ADForest{[pscustomobject]@{Name='contoso.com';ForestMode='Windows2016Forest';Domains=@('contoso.com')}}
        function global:Get-ADDomain{[pscustomobject]@{Name='contoso.com';DomainMode='Windows2016Domain'}}
        function global:Get-ADTrust{param($Filter);$null=$Filter;[pscustomobject]@{Name='fabrikam.com';Target='fabrikam.com';TrustType='External';Direction='Bidirectional'}}
    }
    AfterEach{foreach($name in 'Get-ADSyncScheduler','Get-ADSyncConnector','Get-ADSyncGlobalSettings','Get-CimInstance','Get-Service','Get-ADForest','Get-ADDomain','Get-ADTrust'){Remove-Item "Function:global:$name" -Force -ErrorAction SilentlyContinue}}

    It 'retains every local read-only command result and provenance' {
        $result=Get-ScoutHybridIdentityLocalEvidence
        @($result.Resources).Count|Should -Be 8
        @($result.SourceOperations|Where-Object Status -eq 'Success').Count|Should -Be 8
        @($result.CollectionHealth).Count|Should -Be 0
        @($result.Resources.type)|Should -Contain 'AZSC/HybridIdentity/ActiveDirectoryTrusts'
    }

    It 'marks a missing local capability NotAssessed instead of claiming no topology exists' {
        $result=Get-ScoutHybridIdentityLocalEvidence -CommandAvailability @{'Get-ADTrust'=$false}
        $health=@($result.CollectionHealth|Where-Object Dataset -eq 'HybridIdentity/ActiveDirectoryTrusts')
        $operation=@($result.SourceOperations|Where-Object Dataset -eq 'ActiveDirectoryTrusts')
        $health.Count|Should -Be 1
        $operation.Count|Should -Be 1
        $health[0].Status|Should -Be 'NotAssessed'
        $operation[0].Status|Should -Be 'NotAssessed'
    }

    It 'ships an importable local hybrid identity manifest' {
        {Import-PowerShellDataFile (Join-Path $script:RepoRoot 'manifests/collectors/Identity/HybridIdentityLocal.psd1')}|Should -Not -Throw
    }
}
