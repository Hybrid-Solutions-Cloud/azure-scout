#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Functions defined by a dot-sourced script do not retain a lexical $PSScriptRoot when they are
# later invoked from an interactive/module scope. Capture it while this file is loading so the
# optional standalone path can always find its sibling collector catalog loader.
$script:ScoutResourceCompletenessScriptRoot = $PSScriptRoot

<#
.SYNOPSIS
    Build the universal discovery index and relationship evidence for a Scout run.

.DESCRIPTION
    Specialized collectors deliberately flatten resource-provider payloads into useful report
    columns. That makes the report readable, but it cannot be the completeness boundary: a newly
    introduced or unsupported ARM type would otherwise exist only in raw-inventory.json.

    This function gives every discovered row a stable, machine-readable record. It retains the
    Resource Graph control-plane payload, names the specialized collectors that understand the
    type, correlates collection-health failures, classifies public/private exposure from direct
    evidence, and extracts ARM resource-id references into a generic relationship graph.

    It never calls Azure. The result is deterministic for a fixed resource set, collector catalog,
    and collection-health ledger.

.NOTES
    AB#7366 and AB#7367.
#>

function Get-ScoutResourceCompletenessValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Path
    )

    $current = $InputObject
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) { return $null }
        if ($current -is [System.Collections.IDictionary]) {
            $matchedKey = $null
            foreach ($key in $current.Keys) { if ([string]$key -ieq $segment) { $matchedKey = $key; break } }
            if ($null -eq $matchedKey) { return $null }
            $current = $current[$matchedKey]
            continue
        }
        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) { return $null }
        $current = $property.Value
    }
    return $current
}

function Test-ScoutDiscoverySensitiveName {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $normalized = ($Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    return $normalized -match '(password|passwd|pwd|secrets?|tokens?|sharedkey|privatekey|connectionstrings?|accountkey|accesskey|apikey|primarykey|secondarykey|masterkey|sastoken|saskey)$' -or
        $normalized -eq 'credential'
}

function Protect-ScoutDiscoveryValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$InputObject,
        [AllowNull()][string]$PropertyName = '',
        [ValidateRange(0, 100)][int]$Depth = 0,
        [ValidateRange(1, 100)][int]$MaximumDepth = 60
    )

    if ($null -eq $InputObject) { return $null }
    if (Test-ScoutDiscoverySensitiveName -Name $PropertyName) { return '[REDACTED]' }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive -or
        $InputObject -is [decimal] -or $InputObject -is [datetime] -or
        $InputObject -is [datetimeoffset] -or $InputObject -is [guid]) {
        return $InputObject
    }
    if ($Depth -ge $MaximumDepth) { return '[REDACTED:MAXIMUM-DEPTH]' }

    $contextName = [string](Get-ScoutResourceCompletenessValue -InputObject $InputObject -Path 'name')
    $contextType = [string](Get-ScoutResourceCompletenessValue -InputObject $InputObject -Path 'type')
    $protectContextValue = (Test-ScoutDiscoverySensitiveName -Name $contextName) -or $contextType -match '(?i)^secure(string|object)$'

    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $keyName = [string]$key
            $normalizedKey = ($keyName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
            if ((Test-ScoutDiscoverySensitiveName -Name $keyName) -or
                ($protectContextValue -and $normalizedKey -in @('value', 'defaultvalue'))) {
                $copy[$keyName] = '[REDACTED]'
            }
            else {
                $copy[$keyName] = Protect-ScoutDiscoveryValue -InputObject $InputObject[$key] `
                    -PropertyName $keyName -Depth ($Depth + 1) -MaximumDepth $MaximumDepth
            }
        }
        return [pscustomobject]$copy
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            $items.Add((Protect-ScoutDiscoveryValue -InputObject $item -PropertyName $PropertyName `
                    -Depth ($Depth + 1) -MaximumDepth $MaximumDepth))
        }
        return , $items.ToArray()
    }

    $properties = @($InputObject.PSObject.Properties | Where-Object {
            $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')
        })
    if ($properties.Count -eq 0) { return $InputObject }
    $copy = [ordered]@{}
    foreach ($property in $properties) {
        $propertyName = [string]$property.Name
        $normalizedName = ($propertyName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
        if ((Test-ScoutDiscoverySensitiveName -Name $propertyName) -or
            ($protectContextValue -and $normalizedName -in @('value', 'defaultvalue'))) {
            $copy[$propertyName] = '[REDACTED]'
        }
        else {
            $copy[$propertyName] = Protect-ScoutDiscoveryValue -InputObject $property.Value `
                -PropertyName $propertyName -Depth ($Depth + 1) -MaximumDepth $MaximumDepth
        }
    }
    return [pscustomobject]$copy
}

function Get-ScoutArmReferenceRelationshipType {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    switch -Regex ($Path) {
        '(?i)remoteVirtualNetwork\.id$'       { return 'VNetPeering' }
        '(?i)networkSecurityGroup\.id$'       { return 'NetworkSecurityGroup' }
        '(?i)routeTable\.id$'                 { return 'RouteTable' }
        '(?i)natGateway\.id$'                 { return 'NatGateway' }
        '(?i)subnet\.id$|subnets\[\d+\]\.id$' { return 'Subnet' }
        '(?i)publicIpAddress(?:es)?(?:\[\d+\])?\.id$' { return 'PublicIPAddress' }
        '(?i)privateEndpoint(?:s)?(?:\[\d+\])?\.id$'  { return 'PrivateEndpoint' }
        '(?i)networkInterface(?:s)?(?:\[\d+\])?\.id$' { return 'NetworkInterface' }
        '(?i)privateLinkServiceId$'            { return 'PrivateLinkTarget' }
        '(?i)privateDnsZone(?:Id)?$'            { return 'PrivateDnsZone' }
        '(?i)managedBy$'                       { return 'ManagedBy' }
        default                                { return 'ArmReference' }
    }
}

function Get-ScoutArmReference {
    [CmdletBinding()]
    param(
        [AllowNull()]$InputObject,
        [string]$Path = 'properties',
        [ValidateRange(1, 100)][int]$Depth = 1,
        [ValidateRange(1, 100)][int]$MaximumDepth = 40
    )

    if ($null -eq $InputObject -or $Depth -gt $MaximumDepth) { return }

    if ($InputObject -is [string]) {
        if ($InputObject -match '(?i)^/(subscriptions|providers)/[^\s]+$') {
            [pscustomobject]@{
                TargetId        = $InputObject
                PropertyPath    = $Path
                RelationshipType = Get-ScoutArmReferenceRelationshipType -Path $Path
            }
        }
        return
    }

    # Scalar values cannot contain ARM references. DateTime.Date returns another DateTime:
    # reflecting it recursively previously walked all the way to MaximumDepth (AB#9300).
    if ($InputObject.GetType().IsValueType -or $InputObject -is [uri]) { return }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in @($InputObject.Keys | Sort-Object { [string]$_ })) {
            Get-ScoutArmReference -InputObject $InputObject[$key] -Path "$Path.$key" -Depth ($Depth + 1) -MaximumDepth $MaximumDepth
        }
        return
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $InputObject) {
            Get-ScoutArmReference -InputObject $item -Path "$Path[$index]" -Depth ($Depth + 1) -MaximumDepth $MaximumDepth
            $index++
        }
        return
    }

    foreach ($property in @($InputObject.PSObject.Properties | Sort-Object Name)) {
        if ($property.MemberType -notin @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')) { continue }
        Get-ScoutArmReference -InputObject $property.Value -Path "$Path.$($property.Name)" -Depth ($Depth + 1) -MaximumDepth $MaximumDepth
    }
}

function Get-ScoutExposureEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Resource,
        [AllowNull()]$Relationships,
        [AllowNull()]$ProviderProperties
    )

    $resourceProperties = Get-ScoutResourceCompletenessValue -InputObject $Resource -Path 'properties'
    $properties = if ($null -ne $ProviderProperties) { $ProviderProperties } else { $resourceProperties }
    $type = [string](Get-ScoutResourceCompletenessValue -InputObject $Resource -Path 'type')
    $evidence = [System.Collections.Generic.List[string]]::new()
    $public = $false
    $private = $false
    $applicable = $false

    $publicNetworkAccess = Get-ScoutResourceCompletenessValue -InputObject $properties -Path 'publicNetworkAccess'
    if ($null -ne $publicNetworkAccess -and -not [string]::IsNullOrWhiteSpace([string]$publicNetworkAccess)) {
        $applicable = $true
        [void]$evidence.Add("publicNetworkAccess=$publicNetworkAccess")
        if ([string]$publicNetworkAccess -match '(?i)^(enabled|true|allow|all)$') { $public = $true }
        elseif ([string]$publicNetworkAccess -match '(?i)^(disabled|false|deny|none)$') { $private = $true }
    }

    foreach ($path in @('publicNetworkAccessForIngestion', 'publicNetworkAccessForQuery')) {
        $value = Get-ScoutResourceCompletenessValue -InputObject $properties -Path $path
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { continue }
        $applicable = $true
        [void]$evidence.Add("$path=$value")
        if ([string]$value -match '(?i)^(enabled|true|allow|all)$') { $public = $true }
        elseif ([string]$value -match '(?i)^(disabled|false|deny|none)$') { $private = $true }
    }

    $networkDefaultAction = Get-ScoutResourceCompletenessValue -InputObject $properties -Path 'networkAcls.defaultAction'
    if ($null -ne $networkDefaultAction -and -not [string]::IsNullOrWhiteSpace([string]$networkDefaultAction)) {
        $applicable = $true
        [void]$evidence.Add("networkAcls.defaultAction=$networkDefaultAction")
        if ([string]$networkDefaultAction -ieq 'Allow') { $public = $true }
        elseif ([string]$networkDefaultAction -ieq 'Deny') {
            $ipRules = @(Get-ScoutResourceCompletenessValue -InputObject $properties -Path 'networkAcls.ipRules')
            if (@($ipRules | Where-Object { $null -ne $_ }).Count -gt 0) {
                $public = $true
                [void]$evidence.Add("networkAcls.ipRules=$(@($ipRules | Where-Object { $null -ne $_ }).Count)")
            }
            else { $private = $true }
        }
    }

    $privateEndpointCount = @($Relationships | Where-Object RelationshipType -eq 'PrivateEndpoint').Count
    if ($privateEndpointCount -eq 0) {
        $privateEndpointCount = @(Get-ScoutResourceCompletenessValue -InputObject $properties -Path 'privateEndpointConnections' | Where-Object { $null -ne $_ }).Count
    }
    if ($privateEndpointCount -gt 0) {
        $applicable = $true
        $private = $true
        [void]$evidence.Add("privateEndpoints=$privateEndpointCount")
    }

    $publicIpReferences = @($Relationships | Where-Object RelationshipType -eq 'PublicIPAddress').Count
    if ($publicIpReferences -gt 0) {
        $applicable = $true
        $public = $true
        [void]$evidence.Add("publicIpReferences=$publicIpReferences")
    }
    if ($type -ieq 'microsoft.network/publicipaddresses') {
        $applicable = $true
        $ipAddress = Get-ScoutResourceCompletenessValue -InputObject $properties -Path 'ipAddress'
        if ($ipAddress) {
            $public = $true
            [void]$evidence.Add("publicIpAddress=$ipAddress")
        }
        else { [void]$evidence.Add('publicIpAddress=Unallocated') }
    }

    $classification = if (-not $applicable) { 'Unknown' }
        elseif ($public -and $private) { 'Mixed' }
        elseif ($public) { 'Public' }
        elseif ($private) { 'Private' }
        else { 'None' }

    [pscustomobject]@{
        Classification = $classification
        Evidence       = @($evidence | Sort-Object -Unique)
        Confidence     = if ($applicable) { 'DirectControlPlaneEvidence' } else { 'Unknown' }
    }
}

function New-ScoutDiscoveryContext {
    param([AllowNull()][object[]]$Resources)
    # Explicit run ownership: never reuse this context after mutating the inventory snapshot.
    # ConditionalWeakTable uses reference identity and is available on every supported PS7
    # runtime (ReferenceEqualityComparer is absent from the original PS7/.NET Core runtime).
    $members = [Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
    foreach ($resource in $Resources) {
        if ($null -eq $resource) { continue }
        $existing = $null
        if (-not $members.TryGetValue($resource, [ref]$existing)) { $members.Add($resource, $resource) }
    }
    [pscustomobject]@{ Resources = @($Resources); Members = $members; Base = $null; BuildCount = 0 }
}

function Get-ScoutResourceCompleteness {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Resources,
        [AllowNull()][object[]]$CollectionHealth = @(),
        [AllowNull()][object[]]$Collectors,
        [AllowNull()][string]$DefinitionRoot,
        [AllowNull()]$DiscoveryContext
    )
    if ($null -eq $DiscoveryContext) { $DiscoveryContext = New-ScoutDiscoveryContext -Resources $Resources }
    $viewIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($resource in $Resources) {
        if ($null -eq $resource) { continue }
        $member = $null
        if (-not $DiscoveryContext.Members.TryGetValue($resource, [ref]$member)) {
            throw 'Discovery context belongs to a different inventory snapshot.'
        }
        if ([string](Get-ScoutResourceCompletenessValue $resource 'type') -notlike 'AZSC/*') {
            [void]$viewIds.Add([string](Get-ScoutResourceCompletenessValue $resource 'id'))
        }
    }
    if ($null -eq $DiscoveryContext.Base) {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        if (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level DEBUG -Message ('Universal discovery build started: input rows={0}' -f $DiscoveryContext.Resources.Count)
        }
        $DiscoveryContext.Base = New-ScoutResourceDiscovery -Resources $DiscoveryContext.Resources
        $DiscoveryContext.BuildCount++
        if (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level DEBUG -Message ('Universal discovery build finished: resources={0}; elapsed={1}' -f $DiscoveryContext.Base.Summary.Resources, $timer.Elapsed)
        }
    }
    elseif (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue) {
        Write-AZSCLog -Level DEBUG -Message 'Universal discovery reused for the current inventory snapshot.'
    }

    if (-not $PSBoundParameters.ContainsKey('Collectors') -or $null -eq $Collectors) {
        $collectorArguments = @{ Category = @('All') }
        if ($DefinitionRoot) { $collectorArguments['DefinitionRoot'] = $DefinitionRoot }
        if (Get-Command Get-ScoutCollector -ErrorAction SilentlyContinue) {
            $Collectors = @(Get-ScoutCollector @collectorArguments)
        }
        else {
            $collectorFile = Join-Path $script:ScoutResourceCompletenessScriptRoot 'Get-ScoutCollector.ps1'
            if (Test-Path -LiteralPath $collectorFile -PathType Leaf) {
                # A function dot-sourced from inside this function exists only in this local
                # scope. Load and invoke it in one child scope, returning only its descriptors.
                $Collectors = @(& {
                        param($LoaderPath, $Arguments)
                        . $LoaderPath
                        Get-ScoutCollector @Arguments
                    } $collectorFile $collectorArguments)
            }
            else { $Collectors = @() }
        }
    }
    Write-Verbose ("Get-ScoutResourceCompleteness: collector descriptors={0}" -f @($Collectors).Count)

    $collectorTypeMap = @{}
    $collectorPatterns = [System.Collections.Generic.List[object]]::new()
    foreach ($collectorDescriptor in @($Collectors)) {
        if ($null -eq $collectorDescriptor) { continue }
        $collectorCategory = [string](Get-ScoutResourceCompletenessValue -InputObject $collectorDescriptor -Path 'FolderCategory')
        $collectorBaseName = [string](Get-ScoutResourceCompletenessValue -InputObject $collectorDescriptor -Path 'Name')
        $collectorName = '{0}/{1}' -f $collectorCategory, $collectorBaseName
        $resourceTypes = @((Get-ScoutResourceCompletenessValue -InputObject $collectorDescriptor -Path 'ResourceTypes') | Where-Object { $_ })
        $definitionPath = ''
        if ($resourceTypes.Count -eq 0) {
            $definitionPath = [string](Get-ScoutResourceCompletenessValue -InputObject $collectorDescriptor -Path 'DefinitionPath')
            if (-not [string]::IsNullOrWhiteSpace($definitionPath) -and (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
                $definition = Import-PowerShellDataFile -LiteralPath $definitionPath
                $resourceTypes = @((Get-ScoutResourceCompletenessValue -InputObject $definition -Path 'ResourceTypes') | Where-Object { $_ })
            }
        }
        foreach ($resourceType in $resourceTypes) {
            if ([string]::IsNullOrWhiteSpace([string]$resourceType)) { continue }
            $typeKey = ([string]$resourceType).ToLowerInvariant()
            if ($typeKey.Contains('*') -or $typeKey.Contains('?')) {
                $collectorPatterns.Add([pscustomobject]@{ Pattern = $typeKey; Collector = $collectorName })
                continue
            }
            if (-not $collectorTypeMap.ContainsKey($typeKey)) { $collectorTypeMap[$typeKey] = [System.Collections.Generic.List[string]]::new() }
            if (-not $collectorTypeMap[$typeKey].Contains($collectorName)) { $collectorTypeMap[$typeKey].Add($collectorName) }
        }
    }
    Write-Verbose ("Get-ScoutResourceCompleteness: exact resource-type mappings={0}; wildcard mappings={1}" -f $collectorTypeMap.Count, $collectorPatterns.Count)

    # Normalize coverage once, not once per resource. The base traversal is shared; each
    # caller still gets independent coverage/collector metadata and summary (AB#9302).
    $healthRows = @($CollectionHealth | Where-Object { $null -ne $_ })
    $healthIndex = foreach ($health in $healthRows) {
        [pscustomobject]@{
            Row = $health
            Collectors = @((Get-ScoutResourceCompletenessValue $health 'Collectors') | Where-Object { $_ })
            Types = @((Get-ScoutResourceCompletenessValue $health 'ResourceTypes') | Where-Object { $_ })
            Ids = @((Get-ScoutResourceCompletenessValue $health 'ResourceIds') | Where-Object { $_ })
            Reason = [string](Get-ScoutResourceCompletenessValue $health 'Reason')
        }
    }
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($baseRow in $DiscoveryContext.Base.Resources) {
        if (-not $viewIds.Contains($baseRow.Id)) { continue }
        $row = $baseRow.PSObject.Copy()
        $typeKey = $row.Type.ToLowerInvariant()
        $matches = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($collectorTypeMap.ContainsKey($typeKey)) {
            foreach ($name in $collectorTypeMap[$typeKey]) { [void]$matches.Add($name) }
        }
        foreach ($pattern in $collectorPatterns) {
            if ($typeKey -like $pattern.Pattern) { [void]$matches.Add($pattern.Collector) }
        }
        $rowHealth = [Collections.Generic.List[object]]::new()
        $reasons = [Collections.Generic.List[string]]::new()
        if ($matches.Count -eq 0) { $reasons.Add('No specialized collector declares this resource type; the complete Resource Graph row is retained generically.') }
        foreach ($entry in $healthIndex) {
            if ($entry.Ids.Count -gt 0 -and $entry.Ids -notcontains $row.Id) { continue }
            $applies = $false
            foreach ($name in $entry.Collectors) { if ($name -and $matches.Contains([string]$name)) { $applies = $true; break } }
            if (-not $applies) {
                foreach ($pattern in $entry.Types) { if ($pattern -and $typeKey -like [string]$pattern) { $applies = $true; break } }
            }
            if (-not $applies) { continue }
            $rowHealth.Add($entry.Row)
            if ($entry.Reason -and -not $reasons.Contains($entry.Reason)) { $reasons.Add($entry.Reason) }
        }
        if ($row.PropertyCount -eq 0) { $reasons.Add('Resource Graph returned no properties for this row.') }
        $row.SpecializedCollectors = @($matches | Sort-Object)
        $row.CollectionHealth = $rowHealth.ToArray()
        $row.DetailReasons = $reasons.ToArray()
        $row.DetailStatus = if ($rowHealth.Count -gt 0 -and $row.PropertyCount -eq 0) { 'Unavailable' }
            elseif ($rowHealth.Count -gt 0) { 'Partial' }
            elseif ($matches.Count -gt 0) { 'Detailed' }
            else { 'GenericOnly' }
        $rows.Add($row)
    }
    $result = $DiscoveryContext.Base.PSObject.Copy()
    $result.Resources = $rows.ToArray()
    $result.Relationships = @($DiscoveryContext.Base.Relationships | Where-Object { $viewIds.Contains($_.SourceId) })
    $result.CollectionHealth = $healthRows
    $result.Summary = $DiscoveryContext.Base.Summary.PSObject.Copy()
    $result.Summary.Resources = $rows.Count
    $result.Summary.Relationships = $result.Relationships.Count
    foreach ($status in @('Detailed', 'GenericOnly', 'Partial', 'Unavailable')) {
        $result.Summary.$status = @($rows | Where-Object DetailStatus -eq $status).Count
    }
    foreach ($exposure in @('Public', 'Private', 'Mixed', 'None', 'Unknown')) {
        $property = if ($exposure -in @('None', 'Unknown')) { 'Exposure' + $exposure } else { $exposure }
        $result.Summary.$property = @($rows | Where-Object Exposure -eq $exposure).Count
    }
    return $result
}

function New-ScoutResourceDiscovery {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][object[]]$Resources
    )

    $enrichmentById = @{}
    foreach ($candidate in @($Resources)) {
        if ($null -eq $candidate) { continue }
        $candidateType = [string](Get-ScoutResourceCompletenessValue -InputObject $candidate -Path 'type')
        $candidateId = [string](Get-ScoutResourceCompletenessValue -InputObject $candidate -Path 'id')
        if ($candidateType -notlike 'AZSC/*' -or [string]::IsNullOrWhiteSpace($candidateId)) { continue }
        $key = $candidateId.ToLowerInvariant()
        if (-not $enrichmentById.ContainsKey($key)) { $enrichmentById[$key] = [System.Collections.Generic.List[object]]::new() }
        $enrichmentById[$key].Add([pscustomobject]@{
                Type       = $candidateType
                Properties = Get-ScoutResourceCompletenessValue -InputObject $candidate -Path 'properties'
            })
    }
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $resourceRows = [System.Collections.Generic.List[object]]::new()
    $relationshipRows = [System.Collections.Generic.List[object]]::new()
    $progressTimer = [Diagnostics.Stopwatch]::StartNew()
    $lastProgress = 0L
    $processedRows = 0
    $canLogProgress = $null -ne (Get-Command Write-AZSCLog -ErrorAction SilentlyContinue)

    foreach ($resource in @($Resources)) {
        $processedRows++
        if ($canLogProgress -and ($processedRows % 100 -eq 0 -or ($progressTimer.ElapsedMilliseconds - $lastProgress) -ge 2000)) {
            Write-AZSCLog -Level DEBUG -Message ('Universal discovery progress: input={0}/{1}; indexed={2}; elapsed={3}' -f $processedRows, @($Resources).Count, $resourceRows.Count, $progressTimer.Elapsed)
            $lastProgress = $progressTimer.ElapsedMilliseconds
        }
        if ($null -eq $resource) { continue }
        $id = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'id')
        $type = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'type')
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($type)) { continue }
        if ($type -like 'AZSC/*' -and $enrichmentById.ContainsKey($id.ToLowerInvariant())) { continue }
        if (-not $seenIds.Add($id)) { continue }

        $properties = Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'properties'
        $enrichment = @()
        if ($enrichmentById.ContainsKey($id.ToLowerInvariant())) {
            $enrichment = @($enrichmentById[$id.ToLowerInvariant()])
        }
        $propertyCount = if ($null -eq $properties) { 0 } else { @($properties.PSObject.Properties).Count }
        $references = @(
            @(Get-ScoutArmReference -InputObject $properties -Path 'properties')
            for ($enrichmentIndex = 0; $enrichmentIndex -lt $enrichment.Count; $enrichmentIndex++) {
                $providerPayloadProperties = Get-ScoutResourceCompletenessValue -InputObject $enrichment[$enrichmentIndex] -Path 'Properties.Payload.properties'
                if ($null -ne $providerPayloadProperties) {
                    Get-ScoutArmReference -InputObject $providerPayloadProperties -Path "enrichment[$enrichmentIndex].properties"
                }
            }
            $managedBy = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'managedBy')
            if ($managedBy -match '(?i)^/(subscriptions|providers)/') {
                [pscustomobject]@{ TargetId = $managedBy; PropertyPath = 'managedBy'; RelationshipType = 'ManagedBy' }
            }
        )
        $referenceKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $uniqueReferences = [System.Collections.Generic.List[object]]::new()
        foreach ($reference in $references) {
            if ($null -eq $reference -or [string]$reference.TargetId -ieq $id) { continue }
            $key = '{0}|{1}|{2}' -f $reference.TargetId, $reference.PropertyPath, $reference.RelationshipType
            if (-not $referenceKeys.Add($key)) { continue }
            $edge = [pscustomobject]@{
                SourceId         = $id
                TargetId         = [string]$reference.TargetId
                RelationshipType = [string]$reference.RelationshipType
                PropertyPath     = [string]$reference.PropertyPath
            }
            $uniqueReferences.Add($edge)
            $relationshipRows.Add($edge)
        }

        $providerProperties = @($enrichment | ForEach-Object {
                Get-ScoutResourceCompletenessValue -InputObject $_ -Path 'Properties.Payload.properties'
            } | Where-Object { $null -ne $_ } | Select-Object -First 1)
        $providerExposureProperties = $null
        if ($providerProperties.Count -gt 0) {
            $providerExposureProperties = $providerProperties[0]
        }
        $exposure = Get-ScoutExposureEvidence -Resource $resource -Relationships @($uniqueReferences) `
            -ProviderProperties $providerExposureProperties
        $tags = Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'tags'
        $protectedProperties = Protect-ScoutDiscoveryValue -InputObject $properties -PropertyName 'properties'
        $protectedTags = Protect-ScoutDiscoveryValue -InputObject $tags -PropertyName 'tags'
        $protectedEnrichment = @(
            foreach ($enrichmentItem in $enrichment) {
                Protect-ScoutDiscoveryValue -InputObject $enrichmentItem -PropertyName 'enrichment'
            }
        )
        $sourceKind = if ($type -like 'Entra/*') { 'Entra' }
            elseif ($type -like 'AZSC/*') { 'Enrichment' }
            elseif ($id -match '(?i)^/(subscriptions|providers)/') { 'ARM' }
            else { 'Other' }

        $resourceRows.Add([pscustomobject]@{
            Id                 = $id
            Name               = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'name')
            Type               = $type
            SourceKind         = $sourceKind
            TenantId           = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'tenantId')
            SubscriptionId     = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'subscriptionId')
            ResourceGroup      = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'resourceGroup')
            Location           = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'location')
            Kind               = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'kind')
            ManagedBy          = [string](Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'managedBy')
            Sku                = Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'sku'
            Plan               = Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'plan'
            Identity           = Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'identity'
            Zones              = @(Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'zones')
            ExtendedLocation   = Get-ScoutResourceCompletenessValue -InputObject $resource -Path 'extendedLocation'
            Tags               = $protectedTags
            TagCount           = if ($null -eq $tags) { 0 } else { @($tags.PSObject.Properties).Count }
            Properties         = $protectedProperties
            Enrichment         = $protectedEnrichment
            PropertyCount      = $propertyCount
            DetailStatus       = 'GenericOnly'
            DetailReasons      = @()
            SpecializedCollectors = @()
            CollectionHealth   = @()
            Exposure           = $exposure.Classification
            ExposureConfidence = $exposure.Confidence
            ExposureEvidence   = @($exposure.Evidence)
            RelationshipCount  = $uniqueReferences.Count
        })
    }

    $orderedResources = @($resourceRows | Sort-Object Type, SubscriptionId, ResourceGroup, Name, Id)
    $orderedRelationships = @($relationshipRows | Sort-Object SourceId, RelationshipType, TargetId, PropertyPath -Unique)
    [pscustomobject]@{
        Schema      = 'azure-scout/discovery-completeness/v1'
        # Run timing lives in the report/run metadata. Keeping this index content-derived makes
        # Discovery.json byte-identical for the same resource set, like every other cache file.
        GeneratedAt = $null
        Summary     = [pscustomobject]@{
            Resources     = $orderedResources.Count
            Detailed      = @($orderedResources | Where-Object DetailStatus -eq 'Detailed').Count
            GenericOnly   = @($orderedResources | Where-Object DetailStatus -eq 'GenericOnly').Count
            Partial       = @($orderedResources | Where-Object DetailStatus -eq 'Partial').Count
            Unavailable   = @($orderedResources | Where-Object DetailStatus -eq 'Unavailable').Count
            Public        = @($orderedResources | Where-Object Exposure -eq 'Public').Count
            Private       = @($orderedResources | Where-Object Exposure -eq 'Private').Count
            Mixed         = @($orderedResources | Where-Object Exposure -eq 'Mixed').Count
            ExposureNone  = @($orderedResources | Where-Object Exposure -eq 'None').Count
            ExposureUnknown = @($orderedResources | Where-Object Exposure -eq 'Unknown').Count
            Relationships = $orderedRelationships.Count
        }
        Resources     = $orderedResources
        Relationships = $orderedRelationships
        CollectionHealth = @()
    }
}
