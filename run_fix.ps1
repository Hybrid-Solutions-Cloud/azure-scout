$ErrorActionPreference = 'Stop'
#Requires -Version 7.0
Set-StrictMode -Version Latest
$modulePath = "$HOME\Documents\PowerShell\Modules\PSScriptAnalyzer"
Import-Module -Name $modulePath -Force

$files = Get-ChildItem -Path . -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch '\\(output|node_modules|\.git|\.ai)\\' }

$files.FullName | Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Fix | Out-Null
Write-Output "Auto-fix complete."
