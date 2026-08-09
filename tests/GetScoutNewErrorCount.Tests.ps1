#Requires -Version 7.0

<#
    AB#402 non-terminating-error detection must survive $Error ring-buffer saturation.

    The original implementation compared $Error.Count before and after a phase. $Error is a
    fixed-size ring buffer ($MaximumErrorCount, 256 by default), so in any long run the count
    stops rising, the delta is permanently zero, and non-terminating errors stop being reported
    at all -- silently, and precisely in the long runs where degraded datasets matter most.

    These tests pin the identity-sentinel technique that replaced it.
#>

BeforeAll {
    . "$PSScriptRoot/../src/Get-ScoutNewErrorCount.ps1"
}

Describe 'Get-ScoutNewErrorCount (AB#402)' {

    BeforeEach {
        $Error.Clear()
    }

    It 'returns 0 when nothing new was recorded' {
        foreach ($i in 1..5) { try { throw "seed $i" } catch { $null = $_ } }
        $sentinel = $Error[0]

        Get-ScoutNewErrorCount $sentinel | Should -Be 0
    }

    It 'counts only the records added after the sentinel' {
        foreach ($i in 1..5) { try { throw "seed $i" } catch { $null = $_ } }
        $sentinel = $Error[0]
        foreach ($i in 1..3) { try { throw "new $i" } catch { $null = $_ } }

        Get-ScoutNewErrorCount $sentinel | Should -Be 3
    }

    It 'treats an empty starting buffer as "everything is new"' {
        Get-ScoutNewErrorCount $null | Should -Be 0

        try { throw 'first ever' } catch { $null = $_ }
        Get-ScoutNewErrorCount $null | Should -Be 1
    }

    It 'still detects a new error once the ring buffer has saturated' {
        # This is the case the count-delta technique got wrong.
        foreach ($i in 1..300) { try { throw "filler $i" } catch { $null = $_ } }
        $saturatedCount = $Error.Count
        $sentinel       = $Error[0]

        try { throw 'the error that must not be missed' } catch { $null = $_ }

        # The count cannot rise -- which is exactly why the old technique went blind.
        $Error.Count | Should -Be $saturatedCount
        ($Error.Count -gt $saturatedCount) | Should -BeFalse -Because 'the old count-delta technique is blind here'

        Get-ScoutNewErrorCount $sentinel | Should -BeGreaterThan 0
    }

    It 'reports the whole visible buffer when the sentinel has aged out' {
        try { throw 'about to age out' } catch { $null = $_ }
        $sentinel = $Error[0]

        foreach ($i in 1..300) { try { throw "flood $i" } catch { $null = $_ } }

        # Every record still visible postdates the sentinel, so all of them are new.
        Get-ScoutNewErrorCount $sentinel | Should -Be $Error.Count
    }
}
