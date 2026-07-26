<#
.Synopsis
Reads one '/'-delimited segment out of an Azure resource id, safely under StrictMode.

.DESCRIPTION
Roughly thirty of the InventoryModules collectors pull a name out of a related resource's id with
a FIXED index -- `$data.networkSecurityGroup.id.split('/')[8]` for the NSG name,
`$1.MANAGEDBY.split('/')[8]` for the VM a disk is attached to, `($_.id -split '/')[10]` for a
subnet -- because the canonical resource id

    /subscriptions/{s}/resourceGroups/{rg}/providers/{Namespace}/{type}/{name}
     0  1           2  3               4  5         6           7      8

puts the name at index 8.

Plenty of real ids are shorter than that. A subscription-scoped id (a Defender or Security
assessment with no resource target, a subscription-level policy assignment) has five or six
segments; a `managedBy` can be a bare resource group id. Under Set-StrictMode -Version Latest an
out-of-range array index THROWS

    Index was outside the bounds of the array.

where without StrictMode it quietly returns $null (AB#5671) -- so the collectors were written
against the quiet behaviour and crash under the strict one. That is the third of the three
StrictMode defect classes in the collectors, alongside the absent-property read
(Get-AZSCSafeProperty) and the empty-collection member enumeration (Get-AZSCCollectedValue).

This function returns $null for an out-of-range index, a $null/empty id, or a non-string id,
which is exactly what the unguarded expression produced with StrictMode off. Nothing about a
collector's output changes for an id that IS long enough.

.PARAMETER Id
The resource id to split. $null, empty and non-string values are accepted and return $null.

.PARAMETER Index
The zero-based segment index. 8 is the resource name in a canonical resource id.

.OUTPUTS
The segment at that index, or $null if the id has too few segments.

.EXAMPLE
Get-AZSCIdSegment -Id $data.networkSecurityGroup.id -Index 8

.EXAMPLE
# The guarded form of ($_.id -split '/')[10] -- a subnet name.
Get-AZSCIdSegment -Id $_.id -Index 10

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).
#>
function Get-AZSCIdSegment {
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        $Id,

        [Parameter(Mandatory, Position = 1)]
        [int]$Index
    )

    process {
        if ($null -eq $Id) { return $null }

        # A member-enumeration result can arrive here as an array of ids; [string] on it matches
        # what the unguarded `$array.split('/')` chain degenerated to rather than inventing a new
        # answer, and the single-id case (every real caller) is unaffected.
        $Text = [string]$Id
        if ([string]::IsNullOrEmpty($Text)) { return $null }

        $Segments = @($Text -split '/')
        if ($Index -lt 0 -or $Index -ge $Segments.Count) { return $null }

        return $Segments[$Index]
    }
}
