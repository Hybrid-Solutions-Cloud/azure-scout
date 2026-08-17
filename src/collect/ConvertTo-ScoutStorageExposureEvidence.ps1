#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#+
.SYNOPSIS
    Normalizes storage account network and authentication exposure from retained ARM evidence.

.DESCRIPTION
    This is a pure transform. It makes no Azure request and emits one evidence row per discovered
    storage account. Configured values are retained separately from effective defaults so an absent
    ARM property is never confused with a collector failure. Resource-group managedBy metadata and
    private-endpoint links are joined from the same raw inventory.
#>
function ConvertTo-ScoutStorageExposureEvidence {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]] $Resources = @(),

        [Parameter()]
        [AllowNull()]
        [object[]] $ResourceContainers = @()
    )

    function Get-StorageEvidenceValue {
        param([AllowNull()][object] $InputObject, [Parameter(Mandatory)][string] $Path)
        $current = $InputObject
        foreach ($segment in $Path.Split('.')) {
            if ($null -eq $current) { return $null }
            if ($current -is [System.Collections.IDictionary]) {
                $key = @($current.Keys | Where-Object { [string]$_ -ieq $segment } | Select-Object -First 1)
                if ($key.Count -eq 0) { return $null }
                $current = $current[$key[0]]
                continue
            }
            $property = @($current.PSObject.Properties | Where-Object Name -ieq $segment | Select-Object -First 1)
            if ($property.Count -eq 0) { return $null }
            $current = $property[0].Value
        }
        return $current
    }

    function Get-StorageEvidenceArray {
        param([AllowNull()][object] $Value)
        if ($null -eq $Value) { return @() }
        return @($Value | Where-Object { $null -ne $_ })
    }

    function Get-StorageEffectiveBoolean {
        param([AllowNull()][object] $ConfiguredValue, [bool] $DefaultValue)
        if ($null -eq $ConfiguredValue -or [string]::IsNullOrWhiteSpace([string]$ConfiguredValue)) {
            return $DefaultValue
        }
        if ($ConfiguredValue -is [bool]) { return [bool]$ConfiguredValue }
        return [string]$ConfiguredValue -ieq 'true'
    }

    $allResources = @($Resources | Where-Object { $null -ne $_ })
    $resourceGroupsById = @{}
    foreach ($container in @($ResourceContainers | Where-Object { $null -ne $_ })) {
        $type = [string](Get-StorageEvidenceValue -InputObject $container -Path 'type')
        if ($type -notin @('microsoft.resources/subscriptions/resourcegroups', 'microsoft.resources/resourcegroups')) { continue }
        $id = [string](Get-StorageEvidenceValue -InputObject $container -Path 'id')
        if (-not [string]::IsNullOrWhiteSpace($id)) { $resourceGroupsById[$id.ToLowerInvariant()] = $container }
    }

    $privateEndpointTargets = @{}
    foreach ($privateEndpoint in @($allResources | Where-Object {
                [string](Get-StorageEvidenceValue -InputObject $_ -Path 'type') -ieq 'microsoft.network/privateendpoints'
            })) {
        $privateEndpointId = [string](Get-StorageEvidenceValue -InputObject $privateEndpoint -Path 'id')
        $connections = @(
            Get-StorageEvidenceArray (Get-StorageEvidenceValue -InputObject $privateEndpoint -Path 'properties.privateLinkServiceConnections')
            Get-StorageEvidenceArray (Get-StorageEvidenceValue -InputObject $privateEndpoint -Path 'properties.manualPrivateLinkServiceConnections')
        )
        foreach ($connection in $connections) {
            $targetId = [string](Get-StorageEvidenceValue -InputObject $connection -Path 'properties.privateLinkServiceId')
            if ([string]::IsNullOrWhiteSpace($targetId)) { continue }
            $targetKey = $targetId.ToLowerInvariant()
            if (-not $privateEndpointTargets.ContainsKey($targetKey)) {
                $privateEndpointTargets[$targetKey] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
            if (-not [string]::IsNullOrWhiteSpace($privateEndpointId)) { [void]$privateEndpointTargets[$targetKey].Add($privateEndpointId) }
        }
    }

    foreach ($storage in @($allResources | Where-Object {
                [string](Get-StorageEvidenceValue -InputObject $_ -Path 'type') -ieq 'microsoft.storage/storageaccounts'
            })) {
        $id = [string](Get-StorageEvidenceValue -InputObject $storage -Path 'id')
        $name = [string](Get-StorageEvidenceValue -InputObject $storage -Path 'name')
        $subscriptionId = [string](Get-StorageEvidenceValue -InputObject $storage -Path 'subscriptionId')
        $resourceGroupName = [string](Get-StorageEvidenceValue -InputObject $storage -Path 'resourceGroup')
        $resourceGroupId = if ($subscriptionId -and $resourceGroupName) {
            "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"
        }
        else { $null }
        $resourceGroup = if ($resourceGroupId -and $resourceGroupsById.ContainsKey($resourceGroupId.ToLowerInvariant())) {
            $resourceGroupsById[$resourceGroupId.ToLowerInvariant()]
        }
        else { $null }

        $managedBy = [string](Get-StorageEvidenceValue -InputObject $resourceGroup -Path 'managedBy')
        if ([string]::IsNullOrWhiteSpace($managedBy)) {
            $managedBy = [string](Get-StorageEvidenceValue -InputObject $storage -Path 'managedBy')
        }

        $configuredPublicNetworkAccess = Get-StorageEvidenceValue -InputObject $storage -Path 'properties.publicNetworkAccess'
        $configuredDefaultAction = Get-StorageEvidenceValue -InputObject $storage -Path 'properties.networkAcls.defaultAction'
        $configuredBlobPublicAccess = Get-StorageEvidenceValue -InputObject $storage -Path 'properties.allowBlobPublicAccess'
        $configuredSharedKeyAccess = Get-StorageEvidenceValue -InputObject $storage -Path 'properties.allowSharedKeyAccess'
        $minimumTlsVersion = Get-StorageEvidenceValue -InputObject $storage -Path 'properties.minimumTlsVersion'

        $effectivePublicNetworkAccess = if ($null -eq $configuredPublicNetworkAccess -or [string]::IsNullOrWhiteSpace([string]$configuredPublicNetworkAccess)) { 'Enabled' } else { [string]$configuredPublicNetworkAccess }
        $effectiveDefaultAction = if ($null -eq $configuredDefaultAction -or [string]::IsNullOrWhiteSpace([string]$configuredDefaultAction)) { 'Allow' } else { [string]$configuredDefaultAction }
        $effectiveBlobPublicAccess = Get-StorageEffectiveBoolean -ConfiguredValue $configuredBlobPublicAccess -DefaultValue $true
        $effectiveSharedKeyAccess = Get-StorageEffectiveBoolean -ConfiguredValue $configuredSharedKeyAccess -DefaultValue $true

        $privateEndpointIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($connection in (Get-StorageEvidenceArray (Get-StorageEvidenceValue -InputObject $storage -Path 'properties.privateEndpointConnections'))) {
            $privateEndpointId = [string](Get-StorageEvidenceValue -InputObject $connection -Path 'properties.privateEndpoint.id')
            if ($privateEndpointId) { [void]$privateEndpointIds.Add($privateEndpointId) }
        }
        if ($id -and $privateEndpointTargets.ContainsKey($id.ToLowerInvariant())) {
            foreach ($privateEndpointId in $privateEndpointTargets[$id.ToLowerInvariant()]) { [void]$privateEndpointIds.Add($privateEndpointId) }
        }

        $publicOpen = $effectivePublicNetworkAccess -ieq 'Enabled' -and $effectiveDefaultAction -ieq 'Allow'
        $hasPrivateEndpoint = $privateEndpointIds.Count -gt 0
        $exposure = if ($publicOpen -and $hasPrivateEndpoint) { 'Mixed' }
        elseif ($publicOpen) { 'Public' }
        elseif ($effectivePublicNetworkAccess -ieq 'Disabled' -and $hasPrivateEndpoint) { 'Private' }
        elseif ($effectivePublicNetworkAccess -ieq 'Enabled') { 'Restricted public' }
        else { 'Unknown' }

        $verdict = if (-not [string]::IsNullOrWhiteSpace($managedBy) -or $name -like 'dbstorage*') {
            'Managed RG - by design, confirm'
        }
        elseif ($resourceGroupName -match '(?i)(migration-tmp|(^|-)mrg-)') {
            'Deployment/temp - candidate to delete'
        }
        elseif ($publicOpen) {
            'REAL exposure - remediate'
        }
        else {
            'Needs owner review'
        }

        [pscustomobject][ordered]@{
            id             = "$id/providers/AzureScout/storageExposure"
            name           = $name
            type           = 'AZSC/Derived/StorageExposure'
            subscriptionId = $subscriptionId
            resourceGroup  = $resourceGroupName
            location       = [string](Get-StorageEvidenceValue -InputObject $storage -Path 'location')
            PARENTID       = $id
            PARENTTYPE     = 'microsoft.storage/storageaccounts'
            PARENTNAME     = $name
            properties     = [pscustomobject][ordered]@{
                StorageAccountId                  = $id
                ManagedBy                         = $managedBy
                PublicNetworkAccessConfigured     = $configuredPublicNetworkAccess
                PublicNetworkAccessEffective      = $effectivePublicNetworkAccess
                NetworkDefaultActionConfigured    = $configuredDefaultAction
                NetworkDefaultActionEffective     = $effectiveDefaultAction
                AllowBlobPublicAccessConfigured   = $configuredBlobPublicAccess
                AllowBlobPublicAccessEffective    = $effectiveBlobPublicAccess
                AllowSharedKeyAccessConfigured    = $configuredSharedKeyAccess
                AllowSharedKeyAccessEffective     = $effectiveSharedKeyAccess
                MinimumTlsVersion                 = $minimumTlsVersion
                PrivateEndpointCount              = $privateEndpointIds.Count
                PrivateEndpointIds                = @($privateEndpointIds | Sort-Object)
                Exposure                          = $exposure
                Verdict                           = $verdict
            }
            AZSC           = [pscustomobject][ordered]@{
                Source         = 'Azure Scout derived evidence'
                Dataset        = 'StorageExposure'
                Operation      = 'Normalize and join retained ARM evidence'
                SourceDatasets = @('resources:microsoft.storage/storageaccounts', 'resourcecontainers:resourcegroups', 'resources:microsoft.network/privateendpoints')
                CollectedAt    = (Get-Date).ToString('o')
            }
        }
    }
}
