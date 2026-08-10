$ErrorActionPreference = 'Stop'
#Requires -Version 7.0
Set-StrictMode -Version Latest
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$files = Get-ChildItem -Path . -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch '\\(output|node_modules|\.git|\.ai)\\' }

foreach ($f in $files) {
    $path = $f.FullName
    $text = [System.IO.File]::ReadAllText($path)
    $newText = [regex]::Replace($text, '(?m)[ \t]+(?=\r?$)', '')
    if ($text -cne $newText) {
        [System.IO.File]::WriteAllText($path, $newText, $utf8NoBom)
    }
}
Write-Output "Whitespace trimmed safely."
