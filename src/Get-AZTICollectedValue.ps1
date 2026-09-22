#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
Reads one named value from every element of a collection, safely under StrictMode.

.DESCRIPTION
PowerShell's member enumeration ($collection.Name) is unsafe under
Set-StrictMode -Version Latest: when the enumeration yields nothing at all, PowerShell
reports the property as missing and throws

    The property 'Name' cannot be found on this object. Verify that the property exists.

A $null value on every element is fine - enumeration still yields one $null per element.
An EMPTY COLLECTION on every element is not: those flatten away, the overall result is
empty, and the read throws even though every element carries the key.

That distinction matters because an empty collection is a perfectly normal Azure API
response. A subscription with no reservation recommendations returns { "value": [] }, so a
healthy tenant was crashing the inventory run (AB#5633).

This function reads each element explicitly instead, and emits nothing when there is
nothing to emit - so `$Resources += Get-AZSCCollectedValue ...` adds nothing rather than
throwing. It handles both dictionary elements (the API result hashtables) and objects.

.PARAMETER InputObject
The collection to read from. $null and empty collections are accepted and yield nothing.

.PARAMETER Name
The key or property name to read from each element.

.EXAMPLE
$Resources += Get-AZSCCollectedValue -InputObject $APIResults -Name 'ReservationRecomen'

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC).
#>
function Get-AZSCCollectedValue {
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $InputObject) { return }

    foreach ($Element in @($InputObject)) {
        if ($null -eq $Element) { continue }

        if ($Element -is [System.Collections.IDictionary]) {
            # .Contains rather than .ContainsKey: IDictionary guarantees the former.
            if ($Element.Contains($Name)) { $Element[$Name] }
            continue
        }

        # PSObject.Properties lookup never throws for an absent member, unlike $Element.$Name.
        $Property = $Element.PSObject.Properties[$Name]
        if ($Property) { $Property.Value }
    }
}
