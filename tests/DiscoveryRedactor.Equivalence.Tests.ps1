#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300: the compiled discovery redactor (Initialize-ScoutDiscoveryRedactor) must produce
    exactly what the PowerShell walk in Protect-ScoutDiscoveryValue produces. Both run on the same
    shapes and their JSON is compared byte for byte.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . "$script:RepoRoot/src/pipeline/Get-ScoutResourceCompleteness.ps1"
    $script:Compiled = Initialize-ScoutDiscoveryRedactor

    function Get-RedactionPair {
        param($Value, [string] $PropertyName = 'properties', [int] $MaximumDepth = 60)
        $ps = Protect-ScoutDiscoveryValue -InputObject $Value -PropertyName $PropertyName -MaximumDepth $MaximumDepth -UsePowerShell
        $cs = Protect-ScoutDiscoveryValue -InputObject $Value -PropertyName $PropertyName -MaximumDepth $MaximumDepth
        [pscustomobject]@{
            PowerShell = ConvertTo-Json -InputObject $ps -Depth 100 -Compress -WarningAction SilentlyContinue
            Compiled   = ConvertTo-Json -InputObject $cs -Depth 100 -Compress -WarningAction SilentlyContinue
        }
    }
}

Describe 'Compiled discovery redactor' {
    It 'compiles in this session' {
        $script:Compiled | Should -BeTrue
    }

    It 'matches the PowerShell walk on <Case>' -ForEach @(
        @{ Case = 'sensitive names at every depth'; Value = ([pscustomobject]@{ adminPassword = 'p'; nested = [pscustomobject]@{ connectionString = 'c'; ok = 'v'; 'Shared-Key' = 'k'; tokens = @('t') }; credential = 'x'; credentials = 'y' }) }
        @{ Case = 'secure parameters'; Value = ([pscustomobject]@{ parameters = [pscustomobject]@{ adminLogin = [pscustomobject]@{ type = 'secureString'; defaultValue = 'dv'; value = 'v' }; plain = [pscustomobject]@{ type = 'string'; value = 'keep' } } }) }
        @{ Case = 'name-sensitive context objects'; Value = ([pscustomobject]@{ settings = @([pscustomobject]@{ name = 'ApiKey'; value = 'secret' }, [pscustomobject]@{ name = 'region'; value = 'eastus' }) }) }
        @{ Case = 'dictionaries, arrays and nulls'; Value = ([pscustomobject]@{ map = @{ a = 1; Password = 'p' }; list = @(1, $null, 'x', @(2, 3), [pscustomobject]@{ k = 'v' }); empty = @(); none = $null }) }
        @{ Case = 'dates, guids, numbers and booleans'; Value = ([pscustomobject]@{ when = [datetime]'2026-11-24T10:00:00Z'; whenOffset = [datetimeoffset]'2026-11-24T10:00:00+01:00'; id = [guid]'7a1e0c3c-1111-4222-8333-944455556666'; n = 42; d = [decimal]1.5; b = $true; f = 2.25 }) }
        @{ Case = 'empty objects'; Value = ([pscustomobject]@{ a = [pscustomobject]@{}; b = @{} }) }
        @{ Case = 'keys that differ only in case'; Value = ([pscustomobject]@{ Name = 'one'; inner = [ordered]@{ Key = 1; Other = 2 } }) }
        @{ Case = 'a bare array'; Value = @([pscustomobject]@{ secret = 's'; x = 1 }, 'plain') }
        @{ Case = 'a bare string'; Value = 'just text' }
    ) {
        $r = Get-RedactionPair -Value $Value
        $r.Compiled | Should -BeExactly $r.PowerShell
    }

    It 'redacts a value whose own property name is sensitive' {
        $r = Get-RedactionPair -Value 'secret-value' -PropertyName 'storageAccountKey'
        $r.Compiled | Should -BeExactly $r.PowerShell
        $r.Compiled | Should -Be '"[REDACTED]"'
    }

    It 'stops at the maximum depth the same way' {
        $deep = [pscustomobject]@{ l1 = [pscustomobject]@{ l2 = [pscustomobject]@{ l3 = [pscustomobject]@{ l4 = 'bottom' } } } }
        $r = Get-RedactionPair -Value $deep -MaximumDepth 3
        $r.Compiled | Should -BeExactly $r.PowerShell
        $r.Compiled | Should -Match 'REDACTED:MAXIMUM-DEPTH'
    }

    It 'returns null for null' {
        (Protect-ScoutDiscoveryValue -InputObject $null -PropertyName 'properties') | Should -BeNullOrEmpty
    }
}
