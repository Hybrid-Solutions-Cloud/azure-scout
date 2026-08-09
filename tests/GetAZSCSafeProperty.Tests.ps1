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
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src/Get-AZSCSafeProperty.ps1')
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

Describe 'Get-AZSCSafeProperty -Enumerate reproduces member enumeration (AB#5671)' {

    # WHY THIS SWITCH EXISTS, and why every test below compares against the RAW chain rather than
    # against a hand-written expectation.
    #
    # Plenty of collector chains pass THROUGH an array:
    #   $data.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.nsg.id
    # Unguarded PowerShell enumerates that array, reads the segment off every element and flattens
    # the results. The plain single-object walk does not -- an array has no NoteProperty called
    # `properties`, so it returns $null. Converting such a chain WITHOUT -Enumerate would therefore
    # not be a StrictMode fix at all: it would silently start emitting $null where a populated
    # resource previously emitted a real value. That is a data regression, and a quiet one.
    #
    # So the assertion in each case is "identical to what the raw chain produces with StrictMode
    # off", because that is precisely the contract: same value, minus the throw.

    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path -Path $script:RepoRoot -ChildPath 'src' -AdditionalChildPath 'Get-AZSCSafeProperty.ps1')

        function Assert-SameAsRawChain {
            param(
                [Parameter(Mandatory)] $InputObject,
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [scriptblock] $RawChain
            )

            Set-StrictMode -Off
            $Expected = & $RawChain

            Set-StrictMode -Version Latest
            $Actual = Get-AZSCSafeProperty -InputObject $InputObject -Path $Path -Enumerate

            if ($null -eq $Expected) {
                $Actual | Should -BeNullOrEmpty
            } elseif ($Expected -is [array]) {
                @($Actual) | Should -Be @($Expected)
            } else {
                $Actual | Should -Be $Expected
            }
        }
    }

    It 'matches the raw chain for a single-element array in the middle of the path' {
        $o = [pscustomobject]@{ np = [pscustomobject]@{ nics = @(
            [pscustomobject]@{ properties = [pscustomobject]@{ nsg = [pscustomobject]@{ id = 'nsg-1' } } }
        ) } }
        # Note the SCALAR result: PowerShell unwraps a one-element enumeration, and so must this --
        # otherwise a caller's `.split('/')` starts seeing an array.
        Assert-SameAsRawChain -InputObject $o -Path 'np.nics.properties.nsg.id' -RawChain { $o.np.nics.properties.nsg.id }
    }

    It 'matches the raw chain for a multi-element array (both ids, in order)' {
        $o = [pscustomobject]@{ np = [pscustomobject]@{ nics = @(
            [pscustomobject]@{ properties = [pscustomobject]@{ nsg = [pscustomobject]@{ id = 'nsg-1' } } },
            [pscustomobject]@{ properties = [pscustomobject]@{ nsg = [pscustomobject]@{ id = 'nsg-2' } } }
        ) } }
        Assert-SameAsRawChain -InputObject $o -Path 'np.nics.properties.nsg.id' -RawChain { $o.np.nics.properties.nsg.id }
    }

    It 'returns $null instead of throwing when the intermediate array is EMPTY' {
        # THE defect class (AB#5633): an empty collection is not $null. The enumeration yields
        # nothing, and StrictMode reports that as the property being missing.
        $o = [pscustomobject]@{ np = [pscustomobject]@{ nics = @() } }
        Set-StrictMode -Version Latest
        { Get-AZSCSafeProperty -InputObject $o -Path 'np.nics.properties.nsg.id' -Enumerate } | Should -Not -Throw
        Get-AZSCSafeProperty -InputObject $o -Path 'np.nics.properties.nsg.id' -Enumerate | Should -BeNullOrEmpty
    }

    It 'skips elements missing the segment and still returns the ones that have it' {
        $o = [pscustomobject]@{ np = [pscustomobject]@{ nics = @(
            [pscustomobject]@{ properties = [pscustomobject]@{} },
            [pscustomobject]@{ properties = [pscustomobject]@{ nsg = [pscustomobject]@{ id = 'nsg-2' } } }
        ) } }
        Assert-SameAsRawChain -InputObject $o -Path 'np.nics.properties.nsg.id' -RawChain { $o.np.nics.properties.nsg.id }
    }

    It 'flattens an array-valued segment, as member enumeration does' {
        $o = [pscustomobject]@{ a = @(
            [pscustomobject]@{ b = @('x', 'y') },
            [pscustomobject]@{ b = @('z') }
        ) }
        Assert-SameAsRawChain -InputObject $o -Path 'a.b' -RawChain { $o.a.b }
    }

    It 'enumerates hashtable elements too' {
        $o = [pscustomobject]@{ a = @( @{ b = 'h1' }, @{ b = 'h2' } ) }
        Assert-SameAsRawChain -InputObject $o -Path 'a.b' -RawChain { $o.a.b }
    }

    It 'does not enumerate a string into its characters' {
        # A string is IEnumerable. Enumerating it would turn .Length into per-character nonsense.
        $o = [pscustomobject]@{ a = 'hello' }
        Assert-SameAsRawChain -InputObject $o -Path 'a.Length' -RawChain { $o.a.Length }
    }

    It "prefers the collection's OWN member over enumerating it, as PowerShell does" {
        # `$array.Count` is the length of the array, NOT a per-element read. Getting this precedence
        # wrong would silently change the meaning of any path ending in .Count or .Length.
        $o = [pscustomobject]@{ a = @(
            [pscustomobject]@{ Count = 'per-element' },
            [pscustomobject]@{ Count = 'per-element' }
        ) }
        Assert-SameAsRawChain -InputObject $o -Path 'a.Count' -RawChain { $o.a.Count }
        Get-AZSCSafeProperty -InputObject $o -Path 'a.Count' -Enumerate | Should -Be 2
    }

    It 'leaves the DEFAULT behaviour unchanged -- without the switch, an array stops the walk' {
        # The switch is opt-in precisely so that the single-object callers that shipped in v2.7.0
        # (VirtualMachine.ps1) keep behaving exactly as they were reviewed to behave.
        $o = [pscustomobject]@{ np = [pscustomobject]@{ nics = @(
            [pscustomobject]@{ properties = [pscustomobject]@{ nsg = [pscustomobject]@{ id = 'nsg-1' } } }
        ) } }
        Set-StrictMode -Version Latest
        Get-AZSCSafeProperty -InputObject $o -Path 'np.nics.properties.nsg.id' | Should -BeNullOrEmpty
    }

    It 'is identical to the plain walk for a pure single-object chain' {
        $o = [pscustomobject]@{ a = [pscustomobject]@{ b = [pscustomobject]@{ c = 'deep' } } }
        Set-StrictMode -Version Latest
        $Plain      = Get-AZSCSafeProperty -InputObject $o -Path 'a.b.c'
        $Enumerated = Get-AZSCSafeProperty -InputObject $o -Path 'a.b.c' -Enumerate
        $Enumerated | Should -Be $Plain
        $Enumerated | Should -Be 'deep'
    }
}
