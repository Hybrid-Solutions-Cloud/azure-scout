#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5667 -- Get-AZSCSafeProperty is the single-object counterpart to Get-AZSCCollectedValue
    (see StrictModeMemberEnumeration.Tests.ps1): where that function protects a COLLECTION read
    from throwing when member enumeration yields nothing, this one protects a single object's
    property CHAIN from throwing when an intermediate segment is genuinely absent (not $null --
    absent). Real Azure API responses omit optional blocks (licenseType, availabilitySet,
    diagnosticsProfile...) entirely on resources that do not use them.
#>

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules/Private/Main/Get-AZSCSafeProperty.ps1')
}

Describe 'Get-AZSCSafeProperty' {

    It 'returns the value at the end of a path that is fully present' {
        Set-StrictMode -Version Latest
        $obj = [pscustomobject]@{ a = [pscustomobject]@{ b = [pscustomobject]@{ c = 'value' } } }
        Get-AZSCSafeProperty -InputObject $obj -Path 'a.b.c' | Should -Be 'value'
    }

    It 'returns $null, not a throw, when the final segment is absent' {
        Set-StrictMode -Version Latest
        $obj = [pscustomobject]@{ a = [pscustomobject]@{ b = [pscustomobject]@{} } }
        { Get-AZSCSafeProperty -InputObject $obj -Path 'a.b.c' } | Should -Not -Throw
        Get-AZSCSafeProperty -InputObject $obj -Path 'a.b.c' | Should -BeNullOrEmpty
    }

    It 'returns $null, not a throw, when an INTERMEDIATE segment is absent' {
        Set-StrictMode -Version Latest
        $obj = [pscustomobject]@{ a = [pscustomobject]@{} }
        { Get-AZSCSafeProperty -InputObject $obj -Path 'a.b.c.d' } | Should -Not -Throw
        Get-AZSCSafeProperty -InputObject $obj -Path 'a.b.c.d' | Should -BeNullOrEmpty
    }

    It 'returns $null, not a throw, when an intermediate value is explicitly $null' {
        Set-StrictMode -Version Latest
        $obj = [pscustomobject]@{ a = $null }
        { Get-AZSCSafeProperty -InputObject $obj -Path 'a.b.c' } | Should -Not -Throw
        Get-AZSCSafeProperty -InputObject $obj -Path 'a.b.c' | Should -BeNullOrEmpty
    }

    It 'returns $null, not a throw, when the input object itself is $null' {
        Set-StrictMode -Version Latest
        { Get-AZSCSafeProperty -InputObject $null -Path 'a.b.c' } | Should -Not -Throw
        Get-AZSCSafeProperty -InputObject $null -Path 'a.b.c' | Should -BeNullOrEmpty
    }

    It 'reads a single-segment path' {
        Set-StrictMode -Version Latest
        Get-AZSCSafeProperty -InputObject ([pscustomobject]@{ x = 42 }) -Path 'x' | Should -Be 42
    }

    It 'reads through a hashtable / IDictionary element' {
        Set-StrictMode -Version Latest
        $obj = @{ a = @{ b = 'from-hashtable' } }
        Get-AZSCSafeProperty -InputObject $obj -Path 'a.b' | Should -Be 'from-hashtable'
    }

    It 'preserves an explicit $false rather than treating it as absent' {
        Set-StrictMode -Version Latest
        $obj = [pscustomobject]@{ a = $false }
        Get-AZSCSafeProperty -InputObject $obj -Path 'a' | Should -BeExactly $false
    }

    It 'accepts the object from the pipeline' {
        Set-StrictMode -Version Latest
        ([pscustomobject]@{ a = 'piped' } | Get-AZSCSafeProperty -Path 'a') | Should -Be 'piped'
    }
}
