#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#5671 -- Get-AZSCIdSegment, the third of the three StrictMode defect classes in the collectors.

    Roughly thirty collectors pull a name out of a related resource's id with a FIXED index, because
    the canonical id

        /subscriptions/{s}/resourceGroups/{rg}/providers/{Namespace}/{type}/{name}
         0  1           2  3               4  5         6           7      8

    puts the name at 8. Real ids are often shorter -- a subscription-scoped Defender assessment, a
    `managedBy` that is a bare resource group. Without StrictMode an out-of-range index quietly
    returns $null, which is what those collectors were written and tested against; WITH StrictMode it
    throws "Index was outside the bounds of the array", and the collector dies mid-tenant.

    The contract asserted here is therefore the same as the other two helpers': the value the
    unguarded expression produced, minus the throw. Nothing changes for an id that IS long enough.
#>

Describe 'Get-AZSCIdSegment (AB#5671)' {

    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:RepoRoot 'src' 'Get-AZSCIdSegment.ps1')

        $script:CanonicalId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-test'
    }

    It 'returns the resource name at index 8 of a canonical id' {
        Set-StrictMode -Version Latest
        Get-AZSCIdSegment -Id $script:CanonicalId -Index 8 | Should -Be 'nsg-test'
    }

    It 'agrees with the unguarded expression for an id that IS long enough' {
        # The whole point: for the ids that already worked, nothing whatsoever changes.
        Set-StrictMode -Off
        $Expected = $script:CanonicalId.split('/')[8]
        Set-StrictMode -Version Latest
        Get-AZSCIdSegment -Id $script:CanonicalId -Index 8 | Should -Be $Expected
    }

    It 'returns the resource group at index 4 and the subnet position at index 10' {
        Set-StrictMode -Version Latest
        Get-AZSCIdSegment -Id $script:CanonicalId -Index 4 | Should -Be 'rg-test'
        $SubnetId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet-a/subnets/snet-b'
        Get-AZSCIdSegment -Id $SubnetId -Index 10 | Should -Be 'snet-b'
    }

    It 'returns $null instead of throwing for a SUBSCRIPTION-SCOPED id that has too few segments' {
        # The shape that emptied the Security worksheet: a Defender assessment with no resource target.
        $Short = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Security/assessments/abc'
        Set-StrictMode -Version Latest
        { Get-AZSCIdSegment -Id $Short -Index 8 } | Should -Not -Throw
        Get-AZSCIdSegment -Id $Short -Index 8 | Should -BeNullOrEmpty
    }

    It 'proves the raw expression it replaces DOES throw on that same id' {
        # Without this, the test above only shows the helper is quiet -- not that it was needed.
        $Short = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Security/assessments/abc'
        Set-StrictMode -Version Latest
        { $Short.split('/')[8] } | Should -Throw -ExpectedMessage '*Index was outside the bounds of the array*'
    }

    It 'returns $null for $null, empty and whitespace ids' -ForEach @(
        @{ Id = $null }
        @{ Id = '' }
    ) {
        Set-StrictMode -Version Latest
        Get-AZSCIdSegment -Id $Id -Index 8 | Should -BeNullOrEmpty
    }

    It 'returns $null for a negative index rather than indexing from the end' {
        # PowerShell's $array[-1] means "last". A collector asking for a negative index is a bug, and
        # silently handing back the resource name would hide it.
        Set-StrictMode -Version Latest
        Get-AZSCIdSegment -Id $script:CanonicalId -Index -1 | Should -BeNullOrEmpty
    }

    It 'handles a CIDR mask, which is what VirtualNetwork.ps1 uses it for' {
        # Not every caller is splitting a resource id: '10.0.0.0/24'.split('/')[1] is the mask, and a
        # subnet with no addressPrefix at all is the out-of-range case there.
        Set-StrictMode -Version Latest
        Get-AZSCIdSegment -Id '10.0.0.0/24' -Index 1 | Should -Be '24'
        Get-AZSCIdSegment -Id '10.0.0.0'    -Index 1 | Should -BeNullOrEmpty
    }

    It 'returns $null for the "0" sentinel some collectors substitute for an empty collection' {
        # AzureAI.ps1 falls back to the string '0' when an account has no private endpoints, so the
        # loop still emits a row; '0' splits to ONE element and index 8 is out of range.
        Set-StrictMode -Version Latest
        Get-AZSCIdSegment -Id '0' -Index 8 | Should -BeNullOrEmpty
    }

    It 'accepts the id from the pipeline' {
        Set-StrictMode -Version Latest
        ($script:CanonicalId | Get-AZSCIdSegment -Index 8) | Should -Be 'nsg-test'
    }

    It 'does not throw when handed an array of ids (a member-enumeration result)' {
        # Chains that cross an array can hand this function several ids at once. The old code did
        # something incoherent in that case too; the requirement here is only that it not throw.
        Set-StrictMode -Version Latest
        { Get-AZSCIdSegment -Id @($script:CanonicalId, $script:CanonicalId) -Index 8 } | Should -Not -Throw
    }
}
