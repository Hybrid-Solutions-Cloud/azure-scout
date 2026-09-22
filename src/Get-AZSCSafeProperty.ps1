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
present-and-null, on the (very common) resources that do not use it. The 174 declarative
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

.PARAMETER Enumerate
Reproduce PowerShell's MEMBER ENUMERATION for any intermediate segment whose value is a
collection, instead of treating the collection itself as the object to read from.

Without this switch, a path that crosses an array returns $null at that point: an array has no
NoteProperty called `properties`, so 'networkProfile.networkInterfaceConfigurations.properties.x'
stops dead. Unguarded PowerShell does NOT stop there -- it enumerates the array, reads the
segment off every element, and flattens the results (returning a bare scalar when exactly one
element yields a value). Several collectors depend on precisely that, so making their chains
StrictMode-safe without this switch would silently change the values they emit.

With the switch, each element is read explicitly and elements lacking the segment contribute
nothing, so an EMPTY collection -- or a collection where no element carries the key -- yields
$null rather than the
    The property 'x' cannot be found on this object.
that member enumeration throws under StrictMode when it yields nothing at all (AB#5633).

Off by default: single-object paths must not start silently enumerating.

.OUTPUTS
The value at the end of the path, or $null if $InputObject is $null, or any segment along the
way is absent, or any intermediate value is $null.

.EXAMPLE
Get-AZSCSafeProperty -InputObject $data -Path 'osProfile.windowsConfiguration.enableAutomaticUpdates'

.EXAMPLE
$data.PROPERTIES | Get-AZSCSafeProperty -Path 'storageProfile.osDisk.vhd.uri'

.EXAMPLE
# networkInterfaceConfigurations is an array -- without -Enumerate this returns $null even when
# every NIC config carries the field.
Get-AZSCSafeProperty -InputObject $data -Enumerate `
    -Path 'virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.networkSecurityGroup.id'

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
        [string]$Path,

        [Parameter()]
        [switch]$Enumerate
    )

    begin {
        # Local, not a second module-surface function: one segment read off one element for the
        # -Enumerate walk. It reports PRESENCE separately from VALUE, because member enumeration
        # distinguishes them -- an element carrying the key with a $null value contributes a $null
        # to the result, while an element missing the key contributes nothing at all.
        $ReadSegment = {
            param($Object, [string] $Name)

            if ($null -eq $Object) { return @{ Found = $false; Value = $null } }

            if ($Object -is [System.Collections.IDictionary]) {
                # .Contains rather than .ContainsKey: IDictionary guarantees the former.
                if ($Object.Contains($Name)) { return @{ Found = $true; Value = $Object[$Name] } }
                return @{ Found = $false; Value = $null }
            }

            # PSObject.Properties lookup never throws for an absent member, unlike $Object.$Name.
            $Property = $Object.PSObject.Properties[$Name]
            if ($Property) { return @{ Found = $true; Value = $Property.Value } }
            return @{ Found = $false; Value = $null }
        }
    }

    process {
        $Current = $InputObject

        foreach ($Segment in ($Path -split '\.')) {
            if ($null -eq $Current) { return $null }

            # A string is IEnumerable (over its characters) and a dictionary is IEnumerable (over
            # its entries); neither is what member enumeration means, so both are excluded.
            $IsCollection = $Current -is [System.Collections.IEnumerable] -and
                            $Current -isnot [string] -and
                            $Current -isnot [System.Collections.IDictionary]

            # PowerShell resolves a member on a collection against the COLLECTION'S OWN members
            # first and only falls back to member enumeration when there is no such member -- which
            # is why `$array.Count` is the length of the array and not a per-element read. Mirror
            # that precedence, or a path ending in .Count/.Length would silently change meaning.
            $OwnMember = $null
            if ($Enumerate -and $IsCollection) {
                $OwnMember = $Current.PSObject.Properties[$Segment]
            }

            if ($Enumerate -and $IsCollection -and -not $OwnMember) {
                # Member enumeration, done explicitly: read the segment off every element and
                # flatten. Elements that lack it contribute nothing (that is the part unguarded
                # PowerShell turns into a throw when NOTHING at all is contributed).
                $Collected = @(
                    foreach ($Element in $Current) {
                        $Read = & $ReadSegment $Element $Segment
                        # Emitted bare, not comma-wrapped: member enumeration FLATTENS, so an
                        # element whose value is itself an array contributes its elements.
                        if ($Read.Found) { $Read.Value }
                    }
                )
                # PowerShell unwraps a single-element enumeration result to a scalar; match that
                # exactly, or `.split('/')` on the result would start seeing an array.
                $Current = switch ($Collected.Count) {
                    0       { $null }
                    1       { $Collected[0] }
                    default { $Collected }
                }
                continue
            }

            if ($Current -is [System.Collections.IDictionary]) {
                if ($Current.Contains($Segment)) { $Current = $Current[$Segment] } else { return $null }
                continue
            }

            $Property = $Current.PSObject.Properties[$Segment]
            if ($Property) { $Current = $Property.Value } else { return $null }
        }

        return $Current
    }
}
