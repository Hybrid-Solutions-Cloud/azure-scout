<#
.Synopsis
Reads a (possibly nested) property off a single object, safely under StrictMode.

.DESCRIPTION
PowerShell's member access ($object.Name) is unsafe under Set-StrictMode -Version Latest in a
way that is easy to miss: a $null VALUE is fine (the NoteProperty exists, it just holds
nothing), but an ABSENT property throws

    The property 'Name' cannot be found on this object. Verify that the property exists.

Real Azure API responses (Resource Graph's `properties` blob in particular) only include a
field when the resource actually has something to say about it -- an optional block like
`licenseType`, `availabilitySet` or `diagnosticsProfile` is simply missing from the JSON, not
present-and-null, on the (very common) resources that do not use it. The 176 InventoryModules
collectors were written and tested without StrictMode, so they read deep chains like
`$data.osProfile.windowsConfiguration.enableAutomaticUpdates` unconditionally; under
StrictMode the very first VM whose OS profile does not carry that block throws (AB#5667), and
because which field is missing depends on which resources a tenant actually has, the failure
is data-dependent and different on every estate -- the same shape of defect AB#5633 already
fixed for member ENUMERATION over a collection. This is its single-object counterpart.

This function walks a dotted path one segment at a time and returns $null the moment any
segment is missing or its value is $null, rather than letting the chain throw. It is a
read-only, side-effect-free helper -- nothing about a collector's output changes when every
field in the path is actually present.

.PARAMETER InputObject
The object to read from. $null is accepted and returns $null.

.PARAMETER Path
A dot-separated property path, e.g. 'osProfile.windowsConfiguration.enableAutomaticUpdates'.
Each segment is looked up case-insensitively, matching PowerShell's own member resolution.

.OUTPUTS
The value at the end of the path, or $null if $InputObject is $null, or any segment along the
way is absent, or any intermediate value is $null.

.EXAMPLE
Get-AZSCSafeProperty -InputObject $data -Path 'osProfile.windowsConfiguration.enableAutomaticUpdates'

.EXAMPLE
$data.PROPERTIES | Get-AZSCSafeProperty -Path 'storageProfile.osDisk.vhd.uri'

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).
#>
function Get-AZSCSafeProperty {
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process {
        $Current = $InputObject

        foreach ($Segment in ($Path -split '\.')) {
            if ($null -eq $Current) { return $null }

            if ($Current -is [System.Collections.IDictionary]) {
                # .Contains rather than .ContainsKey: IDictionary guarantees the former.
                if ($Current.Contains($Segment)) { $Current = $Current[$Segment] } else { return $null }
                continue
            }

            # PSObject.Properties lookup never throws for an absent member, unlike $Current.$Segment.
            $Property = $Current.PSObject.Properties[$Segment]
            if ($Property) { $Current = $Property.Value } else { return $null }
        }

        return $Current
    }
}
