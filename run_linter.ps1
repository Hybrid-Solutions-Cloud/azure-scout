$ErrorActionPreference = 'Stop'
$modulePath = "$HOME\Documents\PowerShell\Modules\PSScriptAnalyzer"
Import-Module -Name $modulePath -Force

$files = Get-ChildItem -Path . -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch '\\(output|node_modules|\.git|\.ai)\\' }

$json = $files.FullName | Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 | Select-Object RuleName, Severity, ScriptName, Line, Message | ConvertTo-Json -Depth 3

if ($json) {
    $jsonObj = $json | ConvertFrom-Json
    $jsonObj | Group-Object RuleName | Select-Object Name, Count | Sort-Object Count -Descending | Format-Table -AutoSize
} else {
    Write-Output "No lint violations remaining!"
}
