#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:RepoRoot -ChildPath 'scripts/CollectorGolden.Common.ps1')

    $script:TempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (
        'scout-golden-hash-' + [guid]::NewGuid().ToString('N')
    )
    $null = New-Item -Path $script:TempDir -ItemType Directory -Force
}

AfterAll {
    if ($script:TempDir -and (Test-Path -LiteralPath $script:TempDir)) {
        Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Collector golden fixture hashing' {
    It 'produces the same hash for equivalent LF and CRLF fixtures' {
        $LfPath = Join-Path -Path $script:TempDir -ChildPath 'lf.json'
        $CrLfPath = Join-Path -Path $script:TempDir -ChildPath 'crlf.json'
        $Encoding = [System.Text.UTF8Encoding]::new($false)

        [System.IO.File]::WriteAllText($LfPath, "{`n  `"value`": 1`n}`n", $Encoding)
        [System.IO.File]::WriteAllText($CrLfPath, "{`r`n  `"value`": 1`r`n}`r`n", $Encoding)

        Get-ScoutFixtureSha256 -Path $LfPath |
            Should -Be (Get-ScoutFixtureSha256 -Path $CrLfPath)
    }

    It 'preserves a UTF-8 BOM as part of the fixture identity' {
        $WithoutBomPath = Join-Path -Path $script:TempDir -ChildPath 'without-bom.json'
        $WithBomPath = Join-Path -Path $script:TempDir -ChildPath 'with-bom.json'
        $Content = "{`n  `"value`": 1`n}`n"

        [System.IO.File]::WriteAllText($WithoutBomPath, $Content, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($WithBomPath, $Content, [System.Text.UTF8Encoding]::new($true))

        Get-ScoutFixtureSha256 -Path $WithBomPath |
            Should -Not -Be (Get-ScoutFixtureSha256 -Path $WithoutBomPath)
    }

    It 'accepts a legacy CRLF golden hash for the same logical fixture' {
        $FixturePath = Join-Path -Path $script:TempDir -ChildPath 'legacy-fixture.json'
        $GoldenPath = Join-Path -Path $script:TempDir -ChildPath 'legacy-golden.json'
        [System.IO.File]::WriteAllText(
            $FixturePath,
            "{`n  `"value`": 1`n}`n",
            [System.Text.UTF8Encoding]::new($false)
        )

        $Golden = [ordered]@{
            SchemaVersion = 1
            Category      = 'Test'
            Name          = 'LegacyLineEndings'
            FixturePath   = 'legacy-fixture.json'
            FixtureSha256 = Get-ScoutFixtureSha256 -Path $FixturePath -LineEnding CRLF
            Rows           = @()
            Workbook       = @{ WithoutTags = @(); WithTags = @() }
        }
        $Golden | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $GoldenPath -Encoding utf8NoBOM

        { Import-ScoutGoldenOutput -Path $GoldenPath -FixturePath $FixturePath } |
            Should -Not -Throw
    }

    It 'keeps the committed DevOps fixture identity after a CRLF checkout' {
        $FixturePath = Join-Path -Path $script:RepoRoot -ChildPath 'tests/fixtures/collector-equivalence/DevOps.json'
        $CrLfPath = Join-Path -Path $script:TempDir -ChildPath 'DevOps-crlf.json'
        $ExpectedHash = '15ea3b37dc164eb395d5225a5a35231619190a77026731a196cde8b70c6301d7'
        $Content = [System.IO.File]::ReadAllText($FixturePath).Replace("`r`n", "`n").Replace("`r", "`n")
        [System.IO.File]::WriteAllText(
            $CrLfPath,
            $Content.Replace("`n", "`r`n"),
            [System.Text.UTF8Encoding]::new($false)
        )

        Get-ScoutFixtureSha256 -Path $FixturePath | Should -Be $ExpectedHash
        Get-ScoutFixtureSha256 -Path $CrLfPath | Should -Be $ExpectedHash
    }
}
