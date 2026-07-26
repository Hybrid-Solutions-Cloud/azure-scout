#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Counts error records added to $Error since a sentinel was captured.

.DESCRIPTION
    AB#402 detection used to compare $Error.Count before and after a phase. That is
    wrong for any long run: $Error is a fixed-size ring buffer (256 by default,
    $MaximumErrorCount). Once it saturates, .Count stops rising, the delta is always
    zero, and non-terminating errors stop being reported entirely -- silently, and
    exactly in the long runs where degraded datasets matter most.

    $Error is newest-first, so the reliable technique is to remember the record that
    was at the front before the phase and count how many records now sit ahead of it
    by reference identity.

    If the sentinel has aged out of the buffer, every record still visible arrived
    after it, so the whole buffer is new -- correct, and still non-zero, which is the
    property the caller actually depends on.

.PARAMETER Sentinel
    The record that was at $Error[0] before the phase, or $null if $Error was empty.

.OUTPUTS
    [int] The number of error records added since the sentinel was captured.
#>
function Get-ScoutNewErrorCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Sentinel
    )

    # $Error was empty when the sentinel was taken, so everything present is new.
    if ($null -eq $Sentinel) { return $Error.Count }

    $seen = 0
    foreach ($record in $Error) {
        if ([object]::ReferenceEquals($record, $Sentinel)) { return $seen }
        $seen++
    }

    # Sentinel aged out of the ring buffer: every visible record postdates it.
    return $Error.Count
}
