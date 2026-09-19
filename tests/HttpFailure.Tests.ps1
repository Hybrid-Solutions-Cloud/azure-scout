#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll { . "$PSScriptRoot/../src/Get-ScoutHttpFailure.ps1" }
Describe 'HTTP service failure details' {
    It 'unwraps nested ARM service errors while retaining the HTTP status' {
        $inner = @{ error = @{ code = 'BadRequest'; message = 'Workspace is not onboarded to Microsoft Sentinel.' } } | ConvertTo-Json -Compress
        $body = @{ error = @{ code = 'BadRequest'; message = $inner } } | ConvertTo-Json -Compress
        $result = Get-ScoutHttpFailure -Response ([pscustomobject]@{ StatusCode = 400; Content = $body })
        $result.StatusCode | Should -Be 400
        $result.Message | Should -Be 'Workspace is not onboarded to Microsoft Sentinel.'
    }
    It 'does not invent authorization status for an unknown transport failure' {
        try { throw 'Connection closed unexpectedly' } catch { $result = Get-ScoutHttpFailure -ErrorRecord $_ }
        $result.StatusCode | Should -BeNullOrEmpty
        $result.Message | Should -Be 'Connection closed unexpectedly'
    }
    It 'preserves a retryable status from a response-less exception' {
        $exception = [InvalidOperationException]::new('Throttled')
        $exception.Data['StatusCode'] = 429
        try { throw $exception } catch { $result = Get-ScoutHttpFailure -ErrorRecord $_ }
        $result.StatusCode | Should -Be 429
    }
}
