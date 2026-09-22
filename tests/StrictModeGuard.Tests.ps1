#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#5672 -- the guard against reintroducing a StrictMode weakening.

    The scan itself lives in scripts/Test-StrictModeGuard.ps1, with the annotated allow-list of the
    twenty pre-existing sites and the reason each is still there. CI runs that script as its own step
    (.github/workflows/ci.yml) so a violation shows up as a GitHub annotation on the offending line;
    this file runs the same script so the check also fires in a local `Invoke-Pester -Path tests/`,
    which is where anyone adding a `Set-StrictMode -Off` will actually be at the time.

    One shared implementation deliberately, not two: a guard that can pass in one place and fail in
    the other is worse than no guard.
#>

Describe 'StrictMode weakening guard (AB#5672)' {

    BeforeAll {
        $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
        $script:GuardPath  = Join-Path -Path $script:RepoRoot -ChildPath 'scripts' -AdditionalChildPath 'Test-StrictModeGuard.ps1'
    }

    It 'the guard script exists and is where CI expects it' {
        Test-Path -LiteralPath $script:GuardPath | Should -BeTrue
    }

    It 'the shipped module introduces no StrictMode weakening outside the allow-list' {
        # Run out-of-process: the script calls `exit`, which would take the Pester run with it.
        $Output = & pwsh -NoProfile -File $script:GuardPath -RepoRoot $script:RepoRoot 2>&1
        $ExitCode = $LASTEXITCODE

        # Surfaced on failure so the reader sees WHICH site, not just that something failed.
        if ($ExitCode -ne 0) { Write-Host ($Output -join [Environment]::NewLine) }

        $ExitCode | Should -Be 0 -Because 'shipped module code must use Set-StrictMode -Version Latest; a new -Off, -Version 1.0/2.0/3.0 either needs removing or needs an allow-list entry with a written reason'
    }

    It 'requires PowerShell 7, StrictMode Latest, and terminating errors in every shipped script' {
        $Output = & pwsh -NoProfile -File $script:GuardPath -RepoRoot $script:RepoRoot 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host ($Output -join [Environment]::NewLine) }

        $LASTEXITCODE | Should -Be 0
    }

    It 'catches a weakening that is NOT on the allow-list' {
        # A guard nobody has ever seen fail is not known to work. This proves the teeth by adding a
        # violation to a throwaway copy of the repo layout rather than trusting the happy path.
        $Sandbox = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("AZSC_StrictModeGuard_" + [guid]::NewGuid().ToString('N'))
        try {
            $ModuleDir = Join-Path -Path $Sandbox -ChildPath 'Modules'
            New-Item -ItemType Directory -Path $ModuleDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $ModuleDir -ChildPath 'Offender.ps1') -Value @(
                'function Test-Offender {'
                '    Set-StrictMode -Off'
                '}'
            )

            $Output   = & pwsh -NoProfile -File $script:GuardPath -RepoRoot $Sandbox -IgnoreStaleAllowList 2>&1
            $ExitCode = $LASTEXITCODE

            $ExitCode | Should -Be 1 -Because 'a Set-StrictMode -Off in a file not on the allow-list has to fail the build'
            ($Output -join "`n") | Should -Match 'Offender\.ps1'
        }
        finally {
            if (Test-Path -LiteralPath $Sandbox) { Remove-Item -LiteralPath $Sandbox -Recurse -Force }
        }
    }

    It 'ignores the words "Set-StrictMode -Off" in a comment' {
        # The collectors are full of comments discussing this exact defect class, so a grep-based
        # guard would fire on prose. The scanner parses the AST for that reason.
        $Sandbox = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("AZSC_StrictModeGuard_" + [guid]::NewGuid().ToString('N'))
        try {
            $ModuleDir = Join-Path -Path $Sandbox -ChildPath 'Modules'
            New-Item -ItemType Directory -Path $ModuleDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $ModuleDir -ChildPath 'Innocent.ps1') -Value @(
                '# This used to call Set-StrictMode -Off, which is exactly the thing AB#5672 forbids.'
                'Set-StrictMode -Version Latest'
                '$Note = "do not Set-StrictMode -Off here"'
            )

            $null     = & pwsh -NoProfile -File $script:GuardPath -RepoRoot $Sandbox -IgnoreStaleAllowList 2>&1
            $ExitCode = $LASTEXITCODE

            $ExitCode | Should -Be 0 -Because 'prose and string literals are not calls; only a real CommandAst counts'
        }
        finally {
            if (Test-Path -LiteralPath $Sandbox) { Remove-Item -LiteralPath $Sandbox -Recurse -Force }
        }
    }

    It 'treats -Version 1.0 / 2.0 / 3.0 as weakenings, not just -Off' -ForEach @(
        @{ Argument = '-Version 1.0' }
        @{ Argument = '-Version 2.0' }
        @{ Argument = '-Version 3.0' }
    ) {
        # -Version 2.0 already catches unset variables, so it LOOKS strict enough. It does not catch
        # an out-of-range array index, which is the fault that emptied the Security worksheet.
        $Sandbox = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("AZSC_StrictModeGuard_" + [guid]::NewGuid().ToString('N'))
        try {
            $ModuleDir = Join-Path -Path $Sandbox -ChildPath 'Modules'
            New-Item -ItemType Directory -Path $ModuleDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $ModuleDir -ChildPath 'Downgrade.ps1') -Value "Set-StrictMode $Argument"

            $null     = & pwsh -NoProfile -File $script:GuardPath -RepoRoot $Sandbox -IgnoreStaleAllowList 2>&1
            $LASTEXITCODE | Should -Be 1 -Because "Set-StrictMode $Argument is weaker than Latest"
        }
        finally {
            if (Test-Path -LiteralPath $Sandbox) { Remove-Item -LiteralPath $Sandbox -Recurse -Force }
        }
    }

    It 'fails when an allow-list entry has gone stale' {
        # The allow-list can only be trusted if it cannot rot. The collector StrictMode baseline once
        # shipped EMPTY while 24 collectors were failing; an allow-list naming files that no longer
        # weaken anything is the same failure mode pointing the other way.
        $Sandbox = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("AZSC_StrictModeGuard_" + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path -Path $Sandbox -ChildPath 'Modules') -Force | Out-Null

            # An empty tree weakens nothing at all, so EVERY allow-list entry is stale. This is the
            # one sandbox case that must NOT pass -IgnoreStaleAllowList, since the stale check is
            # exactly what is under test here.
            $Output   = & pwsh -NoProfile -File $script:GuardPath -RepoRoot $Sandbox 2>&1
            $ExitCode = $LASTEXITCODE

            $ExitCode | Should -Be 1
            ($Output -join "`n") | Should -Match 'no longer weakens StrictMode'
        }
        finally {
            if (Test-Path -LiteralPath $Sandbox) { Remove-Item -LiteralPath $Sandbox -Recurse -Force }
        }
    }
}
