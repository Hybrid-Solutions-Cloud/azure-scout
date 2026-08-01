#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Materialize the AVD Azure Local/Arc session-host row set from already-collected resources.

.DESCRIPTION
    The legacy Compute/AVDAzureLocal collector built this three-part set inside its Processing
    branch: tagged Arc machines, tagged Azure Local VM instances, then AVD session-host records
    whose resource id points back to Arc or Azure Local.  It mutates the first two input objects
    with Add-Member before shaping report rows, which leaves no resource type a declarative
    collector can target.

    This pure transform preserves that composition order and the fields the worksheet reads while
    producing independent `AZSC/AVD/AzureLocalSessionHost` rows.  It performs no Azure call and
    never mutates an input row.
#>
function ConvertTo-ScoutAvdAzureLocalSessionHost {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources
    )

    function Get-AvdPropertyValue {
        param(
            [Parameter(Mandatory)]$InputObject,
            [Parameter(Mandatory)][string[]]$Name
        )

        foreach ($Candidate in $Name) {
            $Property = $InputObject.PSObject.Properties[$Candidate]
            if ($null -ne $Property) { return $Property.Value }
        }
        return $null
    }

    function Test-AvdSessionHostTag {
        param([AllowNull()]$Tags)

        if ($null -eq $Tags) { return $false }
        foreach ($Name in @('AvdSessionHost', 'avdsessionhost', 'AVDSessionHost')) {
            $Property = $Tags.PSObject.Properties[$Name]
            if ($null -ne $Property -and $Property.Value -eq 'true') { return $true }
        }
        return $false
    }

    function New-AvdSessionHostRow {
        param(
            [Parameter(Mandatory)]$Source,
            [Parameter(Mandatory)][string]$Platform,
            [AllowNull()][string]$VmId,
            [AllowNull()][string]$HostPool
        )

        $SourceProperties = Get-AvdPropertyValue -InputObject $Source -Name @('PROPERTIES', 'properties')
        $NormalizedProperties = [ordered]@{}
        if ($null -ne $SourceProperties) {
            foreach ($Property in $SourceProperties.PSObject.Properties) {
                $NormalizedProperties[$Property.Name] = $Property.Value
            }
        }
        # These are all field paths the legacy row shaper reads. The old non-StrictMode runtime
        # turned an absent member into $null; make that contract explicit on the new envelope so
        # the declarative interpreter can remain StrictMode Latest.
        foreach ($Name in @('hostPoolId', 'agentVersion', 'agentversion', 'osVersion', 'osversion',
                'lastStatusChange', 'status', 'allowNewSession', 'assignedUser', 'sessions')) {
            if (-not $NormalizedProperties.Contains($Name)) { $NormalizedProperties[$Name] = $null }
        }

        # AB#6802: an AzureLocalVirtualMachineInstances row is Get-ScoutArmChildResource's
        # synthetic envelope for a per-machine singleton named literally 'default', so its own
        # NAME/LOCATION are useless here. PARENTNAME/PARENTLOCATION carry the actual Arc
        # machine/Azure Local VM's identity and are preferred first; every other source (raw ARG
        # rows, AVD session-host records) has no PARENTNAME/PARENTLOCATION property, so this is a
        # no-op fallback to the prior behavior for them.
        [pscustomobject]@{
            TYPE           = 'AZSC/AVD/AzureLocalSessionHost'
            NAME           = Get-AvdPropertyValue -InputObject $Source -Name @('PARENTNAME', 'NAME', 'name')
            RESOURCEGROUP  = Get-AvdPropertyValue -InputObject $Source -Name @('RESOURCEGROUP', 'resourceGroup')
            LOCATION       = Get-AvdPropertyValue -InputObject $Source -Name @('PARENTLOCATION', 'LOCATION', 'location')
            subscriptionId = Get-AvdPropertyValue -InputObject $Source -Name @('subscriptionId', 'SubscriptionId')
            tags           = Get-AvdPropertyValue -InputObject $Source -Name @('tags', 'TAGS')
            PROPERTIES     = [pscustomobject]$NormalizedProperties
            id             = Get-AvdPropertyValue -InputObject $Source -Name @('id', 'ID')
            _Platform      = $Platform
            _VmId          = $VmId
            _HostPool      = $HostPool
        }
    }

    # This order is part of the legacy report's observable row order: Arc, Azure Local, then
    # session-host fallbacks. Do not merge the filters or sort the sources.
    foreach ($Resource in $Resources) {
        if ((Get-AvdPropertyValue -InputObject $Resource -Name @('TYPE', 'type')) -ieq 'microsoft.hybridcompute/machines' -and
            (Test-AvdSessionHostTag -Tags (Get-AvdPropertyValue -InputObject $Resource -Name @('tags', 'TAGS')))) {
            New-AvdSessionHostRow -Source $Resource -Platform 'Arc'
        }
    }

    # AB#6802: the declarative-collector conversion originally targeted a Resource Graph row of
    # type 'microsoft.azurestackhci/virtualmachineinstances' -- a type Resource Graph never
    # returns, because the resource is an ARM extension resource with no Graph table of its own
    # (see Get-ScoutArmChildResource.ps1's 'AzureLocalVirtualMachineInstances' dataset). The real
    # rows now arrive tagged 'AZSC/ARMChild/AzureLocalVirtualMachineInstances'.
    foreach ($Resource in $Resources) {
        if ((Get-AvdPropertyValue -InputObject $Resource -Name @('TYPE', 'type')) -ieq 'AZSC/ARMChild/AzureLocalVirtualMachineInstances' -and
            (Test-AvdSessionHostTag -Tags (Get-AvdPropertyValue -InputObject $Resource -Name @('tags', 'TAGS')))) {
            New-AvdSessionHostRow -Source $Resource -Platform 'AzureLocal'
        }
    }

    foreach ($SessionHost in $Resources) {
        if ((Get-AvdPropertyValue -InputObject $SessionHost -Name @('TYPE', 'type')) -ine 'microsoft.desktopvirtualization/hostpools/sessionhosts') { continue }
        $Properties = Get-AvdPropertyValue -InputObject $SessionHost -Name @('PROPERTIES', 'properties')
        $VmId = if ($null -ne $Properties) {
            $ResourceId = $Properties.PSObject.Properties['resourceId']
            $ObjectId = $Properties.PSObject.Properties['objectId']
            if ($null -ne $ResourceId -and $ResourceId.Value) { [string]$ResourceId.Value }
            elseif ($null -ne $ObjectId -and $ObjectId.Value) { [string]$ObjectId.Value }
            else { $null }
        }
        else { $null }

        if ($VmId -and ($VmId -like '*hybridCompute/*' -or $VmId -like '*AzureStackHCI/*')) {
            $Platform = if ($VmId -like '*hybridCompute/*') { 'Arc' } else { 'AzureLocal' }
            $SessionHostId = [string](Get-AvdPropertyValue -InputObject $SessionHost -Name @('id', 'ID'))
            $Segments = $SessionHostId -split '/'
            $HostPool = if ($Segments.Count -gt 8) { $Segments[8] } else { $null }
            New-AvdSessionHostRow -Source $SessionHost -Platform $Platform -VmId $VmId -HostPool $HostPool
        }
    }
}
