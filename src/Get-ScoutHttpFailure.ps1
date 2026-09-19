#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ScoutHttpFailure {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord, $Response)
    $status = $null
    $code = ''
    $message = if ($ErrorRecord) { $ErrorRecord.Exception.Message } else { '' }
    if ($null -eq $Response -and $ErrorRecord -and $ErrorRecord.Exception.PSObject.Properties['Response']) {
        $Response = $ErrorRecord.Exception.Response
    }
    if ($null -ne $Response -and $Response.PSObject.Properties['StatusCode']) {
        try { $status = [int]$Response.StatusCode } catch { $status = $null }
    }
    if ($null -eq $status -and $ErrorRecord -and $ErrorRecord.Exception.Data.Contains('StatusCode')) {
        $status = [int]$ErrorRecord.Exception.Data['StatusCode']
    }
    $content = if ($ErrorRecord -and $ErrorRecord.ErrorDetails) { $ErrorRecord.ErrorDetails.Message }
        elseif ($null -ne $Response -and $Response.PSObject.Properties['Content']) { $Response.Content }
        else { $null }
    if ($content) {
        try {
            $payload = if ($content -is [string]) { $content | ConvertFrom-Json -Depth 30 } else { $content }
            $detail = if ($payload.PSObject.Properties['error']) { $payload.error } else { $payload }
            if ($detail.PSObject.Properties['code']) { $code = [string]$detail.code }
            if ($detail.PSObject.Properties['message']) { $message = [string]$detail.message }
            # Some ARM providers put a second JSON error envelope inside error.message.
            for ($depth = 0; $depth -lt 3 -and $message.TrimStart().StartsWith('{'); $depth++) {
                $nested = $message | ConvertFrom-Json -Depth 30
                if (-not $nested.PSObject.Properties['error'] -or -not $nested.error.PSObject.Properties['message']) { break }
                if ($nested.error.PSObject.Properties['code']) { $code = [string]$nested.error.code }
                $message = [string]$nested.error.message
            }
        } catch { $null = $_ }
    }
    if ($null -eq $status -and $message -match '(?i)(?:HTTP|status(?:\s+code)?)\D{0,20}(?<status>[45]\d{2})(?!\d)') {
        $status = [int]$Matches.status
    }
    if ($null -eq $status) {
        if ($code -match '^(BadRequest|BadArgumentError|Request_BadRequest)$') { $status = 400 }
        elseif ($code -match '^(Forbidden|Authorization_RequestDenied|AuthorizationFailed|AccessDenied)$' -or $message -match '(?i)\bforbidden\b') { $status = 403 }
        elseif ($code -match '^(InvalidAuthenticationToken|Unauthorized)$') { $status = 401 }
    }
    if (Get-Command Protect-ScoutLogText -ErrorAction SilentlyContinue) { $message = Protect-ScoutLogText $message }
    [pscustomobject]@{
        StatusCode = $status
        Code = $code
        Message = $message
        Summary = ('HTTP {0}; {1}: {2}' -f $(if ($null -ne $status) { $status } else { 'unknown' }), $code, $message)
    }
}
