#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:CI = 'true'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'AzureScout.psd1') -Force
InModuleScope AzureScout {
Describe 'Customer multi-tenant recovery' {
    BeforeEach {
        Mock Get-AzContext { [pscustomobject]@{ Account=[pscustomobject]@{Id='operator@example.test'}; Tenant=[pscustomobject]@{Id='one'} } }
        Mock Set-AzContext {}
        Mock Connect-AZSCLoginSession { 'one' }
        Mock Get-AZSCAccessibleTenant { 1..5 | ForEach-Object { [pscustomobject]@{Id="tenant-$_";Name="Tenant $_"} } }
        $script:recoveryCalls = [Collections.Generic.List[string]]::new()
        $script:failFifth = $true
        $script:runner = {
            param($arguments)
            $id = [string]$arguments.TenantID[0]
            $script:recoveryCalls.Add($id)
            if (-not $arguments.NonInteractiveAuth) { throw 'Child must not initiate login.' }
            if ($id -eq 'tenant-5' -and $script:failFifth) { throw 'Synthetic fifth-tenant failure' }
            $report = Join-Path $arguments.ReportDir 'report-react.html'
            '<html>fixture</html>' | Set-Content $report
            New-AZSCRunResult -TenantId $id -ReactFile $report -OutputPath $arguments.ReportDir -ResourceCount 2
        }
    }
    It 'continues four tenants and retries only the fifth without modifying successful artifacts' {
        $result = Invoke-AZSCMultiTenantRun -InvocationParameters @{ ReportDir=$TestDrive; RunName='five'; Scope='All'; Secret='never-persist-this' } -AllAccessibleTenants -TenantRunner $script:runner
        $result.Status | Should -Be 'CompletedWithErrors'
        @($result.Tenants | Where-Object Status -eq Completed).Count | Should -Be 4
        $before = @(Get-ChildItem $result.OutputPath -Filter report-react.html -Recurse | Where-Object DirectoryName -ne $result.OutputPath | Get-FileHash)
        (Get-Content $result.Summary -Raw) | Should -Not -Match 'never-persist-this'
        $script:failFifth = $false
        $script:recoveryCalls.Clear()
        $retried = Invoke-AZSCMultiTenantRun -InvocationParameters @{} -ResumeRun $result.OutputPath -RetryFailed -TenantRunner $script:runner
        $retried.Status | Should -Be 'Completed'
        @($script:recoveryCalls) | Should -Be @('tenant-5')
        foreach ($file in $before) { (Get-FileHash $file.Path).Hash | Should -Be $file.Hash }
        @($retried.Tenants[4].Attempts).Count | Should -Be 2
    }
    It 'does not call a missing child result completed' {
        $result = Invoke-AZSCMultiTenantRun -InvocationParameters @{ ReportDir=$TestDrive; RunName='missing' } -RequestedTenantId @('tenant-1') -TenantRunner { param($arguments) }
        $result.Tenants[0].Status | Should -Be 'Failed'
        $result.Tenants[0].Error | Should -Match 'typed result'
    }
    It 'resumes an interrupted attempt and pending tenant in new directories' {
        $result = Invoke-AZSCMultiTenantRun -InvocationParameters @{ ReportDir=$TestDrive; RunName='interrupted' } -RequestedTenantId @('tenant-1','tenant-2') -TenantRunner $script:runner
        $checkpoint=Get-Content $result.Summary -Raw | ConvertFrom-Json -Depth 30
        $checkpoint.Tenants[0].Status='Running'; $checkpoint.Tenants[0].Attempts[-1].Status='Running'
        $checkpoint.Tenants[1].Status='Pending'
        $checkpoint | ConvertTo-Json -Depth 30 | Set-Content $result.Summary
        $script:recoveryCalls.Clear()
        $resumed=Invoke-AZSCMultiTenantRun -InvocationParameters @{} -ResumeRun $result.OutputPath -TenantRunner $script:runner
        @($script:recoveryCalls) | Should -Be @('tenant-1','tenant-2')
        $resumed.Tenants[0].Attempts[0].Status | Should -Be Interrupted
        $resumed.Tenants[0].Attempts[1].Status | Should -Be Completed
        $resumed.Tenants[0].Attempts[0].Folder | Should -Not -Be $resumed.Tenants[0].Attempts[1].Folder
    }
    It 'retries an explicitly selected tenant without executing other targets' {
        $result = Invoke-AZSCMultiTenantRun -InvocationParameters @{ ReportDir=$TestDrive; RunName='selected' } -RequestedTenantId @('tenant-1','tenant-2') -TenantRunner $script:runner
        $script:recoveryCalls.Clear()
        $resumed=Invoke-AZSCMultiTenantRun -InvocationParameters @{} -ResumeRun $result.OutputPath -RetryTenant tenant-2 -TenantRunner $script:runner
        @($script:recoveryCalls) | Should -Be @('tenant-2')
        @($resumed.Tenants[0].Attempts).Count | Should -Be 1
    }
    It 'rejects incompatible and corrupt checkpoints before starting a tenant' {
        $result=Invoke-AZSCMultiTenantRun -InvocationParameters @{ ReportDir=$TestDrive; RunName='corrupt' } -RequestedTenantId @('tenant-5') -TenantRunner $script:runner
        $checkpoint=Get-Content $result.Summary -Raw | ConvertFrom-Json -Depth 30
        $checkpoint.ModuleVersion='0.0.0'; $checkpoint | ConvertTo-Json -Depth 30 | Set-Content $result.Summary
        $script:recoveryCalls.Clear()
        { Invoke-AZSCMultiTenantRun -InvocationParameters @{} -ResumeRun $result.OutputPath -TenantRunner $script:runner } | Should -Throw '*module version*'
        '{broken' | Set-Content $result.Summary
        { Invoke-AZSCMultiTenantRun -InvocationParameters @{} -ResumeRun $result.OutputPath -TenantRunner $script:runner } | Should -Throw
        $script:recoveryCalls.Count | Should -Be 0
    }
    It 'preserves a partial child verdict and rejects mismatched identities' {
        $result = Invoke-AZSCMultiTenantRun -InvocationParameters @{ ReportDir=$TestDrive; RunName='partial' } -RequestedTenantId @('tenant-1','tenant-2') -TenantRunner {
            param($arguments)
            $report=Join-Path $arguments.ReportDir 'report-react.html'; 'fixture' | Set-Content $report
            $id=if($arguments.TenantID[0] -eq 'tenant-1'){'tenant-1'}else{'wrong-tenant'}
            New-AZSCRunResult -TenantId $id -Status Partial -ReactFile $report
        }
        $result.Tenants[0].Status | Should -Be 'Partial'
        $result.Tenants[1].Status | Should -Be 'Failed'
    }
    It 'rejects concurrent recovery, unknown tenants and changed settings' {
        $result = Invoke-AZSCMultiTenantRun -InvocationParameters @{ ReportDir=$TestDrive; RunName='locks' } -RequestedTenantId @('tenant-5') -TenantRunner $script:runner
        $lock=[IO.File]::Open((Join-Path $result.OutputPath '.run.lock'),'OpenOrCreate','ReadWrite','None')
        try { { Invoke-AZSCMultiTenantRun -InvocationParameters @{} -ResumeRun $result.OutputPath -TenantRunner $script:runner } | Should -Throw } finally { $lock.Dispose() }
        { Invoke-AZSCMultiTenantRun -InvocationParameters @{} -ResumeRun $result.OutputPath -RetryTenant 'absent' -TenantRunner $script:runner } | Should -Throw '*not in this checkpoint*'
        { Invoke-AZSCMultiTenantRun -InvocationParameters @{ Scope='EntraOnly' } -ResumeRun $result.OutputPath -TenantRunner $script:runner } | Should -Throw '*saved settings*'
    }
}
Describe 'Authentication reuse and Graph isolation' {
    BeforeEach {
        $script:_AZSCGraphTokenCache=@{}
        $script:activeTenant='tenant-a'
        Mock Get-AzContext { [pscustomobject]@{Account=[pscustomobject]@{Id='guest@example.test';Type='User'};Tenant=[pscustomobject]@{Id=$script:activeTenant};Environment=[pscustomobject]@{Name='AzureCloud'}} }
        Mock Get-AzAccessToken { [pscustomobject]@{Token="token-$TenantId";ExpiresOn=[DateTimeOffset]::UtcNow.AddHours(1)} }
        Mock Connect-AzAccount { throw 'Unexpected interactive login' }
        Mock Connect-MgGraph { throw 'Unexpected Graph login' }
        Mock Get-MgContext { $null }
    }
    It 'reuses a valid context even when device login was selected' {
        Connect-AZSCLoginSession -TenantID tenant-a -DeviceLogin -NonInteractive | Should -Be 'tenant-a'
        Should -Invoke Connect-AzAccount -Times 0
    }
    It 'creates contexts silently for five tenant switches' {
        Mock Get-AzContext -ParameterFilter {$ListAvailable} { @() }
        Mock Set-AzContext { $script:activeTenant=$Tenant; Get-AzContext }
        foreach($id in @('a','b','c','d','e')) { Connect-AZSCLoginSession -TenantID "tenant-$id" -DeviceLogin -NonInteractive | Should -Be "tenant-$id" }
        Should -Invoke Connect-AzAccount -Times 0
    }
    It 'reports interaction required without opening a prompt' {
        Mock Get-AzAccessToken { throw 'interaction_required' }
        { Connect-AZSCLoginSession -TenantID tenant-b -NonInteractive } | Should -Throw '*authentication before retry*'
        Should -Invoke Connect-AzAccount -Times 0
    }
    It 'does not return an SDK marker for A after the active SDK context changes to B' {
        $script:mgTenant='tenant-a'
        Mock Get-MgContext { [pscustomobject]@{TenantId=$script:mgTenant;Account='guest@example.test';Environment='Global';Scopes=@('Reports.Read.All')} }
        $first=Get-AZSCGraphToken -TenantID tenant-a -Scopes Reports.Read.All
        $first['X-AzureScout-GraphProvider'] | Should -Be 'Microsoft.Graph.Authentication'
        $script:mgTenant='tenant-b'
        $null=Get-AZSCGraphToken -TenantID tenant-b -Scopes Reports.Read.All
        $last=Get-AZSCGraphToken -TenantID tenant-a -Scopes Reports.Read.All
        $last.Authorization | Should -Be 'Bearer token-tenant-a'
        Should -Invoke Connect-MgGraph -Times 0
    }
    It 'uses the guest Az session for granular scopes without prompting for a customer account' {
        (Get-AZSCGraphToken -TenantID tenant-a -Scopes 'RoleEligibilitySchedule.Read.Directory').Authorization | Should -Be 'Bearer token-tenant-a'
        Should -Invoke Connect-MgGraph -Times 0
    }
    It 'prefers a newly consented matching SDK context over a previously cached Az token' {
        $null=Get-AZSCGraphToken -TenantID tenant-a -Scopes Reports.Read.All
        Mock Get-MgContext { [pscustomobject]@{TenantId='tenant-a';Account='guest@example.test';Environment='Global';Scopes=@('Reports.Read.All')} }
        (Get-AZSCGraphToken -TenantID tenant-a -Scopes Reports.Read.All)['X-AzureScout-GraphProvider'] | Should -Be 'Microsoft.Graph.Authentication'
    }
    It 'never uses a different account or cloud SDK context for the selected tenant' {
        Mock Get-MgContext { [pscustomobject]@{TenantId='tenant-a';Account='other@example.test';Environment='USGov';Scopes=@('Reports.Read.All')} }
        (Get-AZSCGraphToken -TenantID tenant-a -Scopes Reports.Read.All).Authorization | Should -Be 'Bearer token-tenant-a'
        Should -Invoke Connect-MgGraph -Times 0
    }
}
Describe 'Assessment-specific drift identities' {
    It 'retains different verdicts for the same rule in two assessments' {
        $findings=[pscustomobject]@{Findings=@(
            [pscustomobject]@{Id='shared-rule';Assessment='First';Status='Pass'},
            [pscustomobject]@{Id='shared-rule';Assessment='Second';Status='Fail'}
        );Areas=@()}
        $first=Get-ScoutDrift -Findings $findings -HistoryPath (Join-Path $TestDrive 'history') -RunId first
        @($first.Findings).Count | Should -Be 2
        $findings.Findings[1].Status='Pass'
        $second=Get-ScoutDrift -Findings $findings -HistoryPath (Join-Path $TestDrive 'history') -RunId second
        $second.Summary.Resolved | Should -Be 1
        $second.Summary.Unchanged | Should -Be 1
    }
}
Describe 'Normalization failure preserves evidence without scoring a substitute' {
    BeforeEach {
        Mock ConvertFrom-ScoutInventory { throw 'Index was outside the bounds of the array' }
        Mock Search-AzGraph { throw 'ARG must not substitute for failed normalization' }
    }
    It 'fails closed for assessment scoring' {
        $caught=$null
        try { Invoke-Collect -FromInventory ([pscustomobject]@{Resources=@();ResourceContainers=@()}) -Categories Compute } catch { $caught=$_ }
        $caught.Exception.Data['AzureScoutFailureKind'] | Should -Be 'AssessmentSourceUnavailable'
        Should -Invoke Search-AzGraph -Times 0
    }
    It 'retains identity and explicit failure health in offline inventory rendering' {
        $raw=[pscustomobject]@{Resources=@();ResourceContainers=@();EntraResources=@([pscustomobject]@{Name='retained identity'})}
        $collect=Invoke-Collect -FromInventory $raw -OfflineFromInventory -Categories Compute
        $collect.entraResources[0].Name | Should -Be 'retained identity'
        @($collect._meta.collectionHealth | Where-Object Dataset -eq AssessmentNormalization).Count | Should -Be 1
        Should -Invoke Search-AzGraph -Times 0
    }
}
}
