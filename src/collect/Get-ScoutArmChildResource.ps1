#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Prefetch ARM child collections and service metadata consumed by inventory collectors.

.DESCRIPTION
    Moves supported per-parent ARM and metadata-only service calls out of collector row loops and
    into the collect phase.
    Application Insights Continuous Export and Work Item Config endpoints are deliberately not
    represented: Azure retired them, so querying either would produce a permanent failure rather
    than inventory data. The function is intentionally isolated in this change: Invoke-Collect
    does not call it yet, and no existing collector or definition is modified.

    Each returned row preserves the child payload's top-level properties and adds a stable
    synthetic resource contract:

      TYPE             AZSC/ARMChild/<collector name>
      PARENTID         resource id of the parent
      PARENTTYPE       Resource Graph type of the parent
      PARENTNAME       Resource Graph name of the parent
      PARENTLOCATION   Resource Graph location of the parent (AB#6802 -- a singleton child
                       carries no location of its own, and a consumer that needs one, like
                       Compute/AVDAzureLocal's Azure Local branch, has nowhere else to read it)
      subscriptionId   inherited from the parent
      RESOURCEGROUP    inherited from the parent
      AZSC             metadata object with Dataset, ParentId, ParentType, ParentName,
                       SourceType, EndpointType, LatestVersion and DeploymentCount

    Dataset identifies the future consuming definition one-to-one. LatestVersion is populated for
    MLDatasets and MLModels. EndpointType and DeploymentCount are populated for MLEndpoints.

    Calls are independently non-fatal. A failed parent/dataset call emits a warning and only that
    child collection is omitted; other parents and datasets continue. Input order, canonical
    dataset order, endpoint-type order, and service response order are preserved.

.PARAMETER Resources
    Resource Graph rows containing the parent workspaces/accounts/application groups.

.PARAMETER Dataset
    Optional subset of the supported dataset names. Defaults to All.

.PARAMETER CollectionHealth
    Optional caller-owned list that receives one health record per child dataset that could not
    be read. Health records are never written to the function's output pipeline, so partial
    successful inventory rows retain their established shape.

.OUTPUTS
    PSCustomObject rows using the synthetic contract documented above.

.NOTES
    Proof-of-isolation implementation for Epic AB#5638. Integration into Invoke-Collect and
    conversion of the fourteen collectors are separate changes.
#>
function Get-ScoutArmChildResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources,

        [Parameter()]
        [ValidateSet(
            'All',
            'MLComputes',
            'MLDatasets',
            'MLDatastores',
            'MLEndpoints',
            'MLModels',
            'MLPipelines',
            'OpenAIDeployments',
            'SearchIndexes',
            'AVDApplications',
            'AppInsightsProactiveDetection',
            'LAWorkspaceLinkedServices',
            'LAWorkspaceSavedSearches',
            'KeyVaultSecrets',
            'KeyVaultKeys',
            'StorageBlobContainers',
            'StorageFileShares',
            'StorageLifecyclePolicies',
            'StorageQueues',
            'StorageTables',
            'BackupInstances',
            'ResourceDiagnosticSettings',
            'ReservationUtilization',
            'AzureLocalVirtualMachineInstances'
        )]
        [string[]]$Dataset = @('All'),

        [Parameter()]
        [AllowNull()]
        [System.Collections.IList]$CollectionHealth
    )

    $DatasetOrder = @(
        'MLComputes',
        'MLDatasets',
        'MLDatastores',
        'MLEndpoints',
        'MLModels',
        'MLPipelines',
        'OpenAIDeployments',
        'SearchIndexes',
        'AVDApplications',
        'AppInsightsProactiveDetection',
        'LAWorkspaceLinkedServices',
        'LAWorkspaceSavedSearches',
        'KeyVaultSecrets',
        'KeyVaultKeys',
        'StorageBlobContainers',
        'StorageFileShares',
        'StorageLifecyclePolicies',
        'StorageQueues',
        'StorageTables',
        'BackupInstances',
        'ResourceDiagnosticSettings',
        'ReservationUtilization',
        'AzureLocalVirtualMachineInstances'
    )

    # --- Diagnostic-settings parent scope (AB#6769) ---------------------------------------------
    #
    # Diagnostic settings can be attached to MOST Azure resource types, so the naive
    # implementation is one REST call per resource in the estate -- tens of thousands of calls on
    # a large tenant to fill one worksheet. That is not a trade worth making, so the sweep is
    # scoped to the types below: the ones whose platform logs are the evidence a security or
    # governance review actually asks for (who touched the vault, what the firewall allowed, what
    # the database did), and where the ABSENCE of a diagnostic setting is itself the finding.
    #
    # Deliberately NOT in this list, and this is where the saving comes from: virtual machines,
    # managed disks, network interfaces, public IP addresses, snapshots and VM extensions. They
    # are the highest-count types in any real estate by an order of magnitude, and a VM's guest
    # telemetry is configured through the Azure Monitor agent and data collection rules -- which
    # Scout already collects as their own resource types -- not through a diagnostic setting on
    # the VM. Including them would multiply this sweep's call count by 10-50x and add no finding.
    #
    # Adding a type here costs one ARM GET per instance of it, per run. Weigh it that way.
    $DiagnosticSettingParentTypes = @(
        'microsoft.keyvault/vaults'
        'microsoft.storage/storageaccounts'
        'microsoft.sql/servers'
        'microsoft.sql/servers/databases'
        'microsoft.dbforpostgresql/flexibleservers'
        'microsoft.dbformysql/flexibleservers'
        'microsoft.documentdb/databaseaccounts'
        'microsoft.containerservice/managedclusters'
        'microsoft.web/sites'
        'microsoft.network/networksecuritygroups'
        'microsoft.network/applicationgateways'
        'microsoft.network/azurefirewalls'
        'microsoft.network/frontdoors'
        'microsoft.cdn/profiles'
        'microsoft.apimanagement/service'
        'microsoft.eventhub/namespaces'
        'microsoft.servicebus/namespaces'
        'microsoft.operationalinsights/workspaces'
        'microsoft.recoveryservices/vaults'
        'microsoft.automation/automationaccounts'
    )

    $Selected = if ($Dataset -contains 'All') {
        $DatasetOrder
    }
    else {
        @($DatasetOrder | Where-Object { $Dataset -contains $_ })
    }

    $FailedHealthDatasets = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    function Get-ArmParentValue {
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

    function Get-ArmChildContent {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter(Mandatory)][string]$ParentName,
            [switch]$NotFoundIsEmpty
        )

        function Get-ArmChildHttpStatusCode {
            param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

            $ResponseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
            if ($ResponseProperty -and $null -ne $ResponseProperty.Value) {
                $StatusProperty = $ResponseProperty.Value.PSObject.Properties['StatusCode']
                if ($StatusProperty -and $null -ne $StatusProperty.Value) {
                    try { return [int]$StatusProperty.Value } catch { return $null }
                }
            }

            if ($ErrorRecord.Exception.Data -and $ErrorRecord.Exception.Data.Contains('StatusCode')) {
                try { return [int]$ErrorRecord.Exception.Data['StatusCode'] } catch { return $null }
            }

            $StatusMatch = [regex]::Match(
                [string]$ErrorRecord.Exception.Message,
                '(?i)(?:HTTP|status(?:\s+code)?)\D{0,20}(?<code>[1-5]\d{2})(?!\d)'
            )
            if ($StatusMatch.Success) { return [int]$StatusMatch.Groups['code'].Value }
            return $null
        }

        try {
            # ARM list endpoints may paginate even tiny-looking datasets. AB#7358's tenant
            # reconciliation exposed first-page-only handling while auditing child resources.
            # Follow nextLink here once for every ARM-child consumer instead of teaching each
            # dataset its own paging loop. Key Vault metadata uses the separate paged helper below.
            $Items = [System.Collections.Generic.List[object]]::new()
            $SeenPaths = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            $CurrentPath = $Path
            $IsPaged = $false

            while ($CurrentPath) {
                if (-not $SeenPaths.Add($CurrentPath)) {
                    throw "ARM returned a repeated nextLink '$CurrentPath'."
                }

                # Invoke-AzRestMethod returns a PSHttpResponse whose StatusCode can be inspected.
                # Unlike PowerShell's Invoke-RestMethod, the Az.Accounts cmdlet does not expose
                # -SkipHttpErrorCheck (including supported Az.Accounts 5.5.2). Expected singleton
                # 404s are therefore classified from either the response or the caught exception.
                $RestParameters = @{ Method = 'GET'; ErrorAction = 'Stop' }
                if ([uri]::IsWellFormedUriString($CurrentPath, [System.UriKind]::Absolute)) {
                    $RestParameters['Uri'] = $CurrentPath
                }
                else {
                    $RestParameters['Path'] = $CurrentPath
                }
                $Response = Invoke-AzRestMethod @RestParameters
                if ($null -eq $Response) { throw 'ARM returned no response.' }

                $Status = $Response.PSObject.Properties['StatusCode']
                if ($null -ne $Status -and [int]$Status.Value -eq 404 -and $NotFoundIsEmpty) {
                    return $null
                }
                if ($null -ne $Status -and ([int]$Status.Value -lt 200 -or [int]$Status.Value -ge 300)) {
                    throw "ARM returned status $($Status.Value)"
                }

                $ContentProperty = $Response.PSObject.Properties['Content']
                if ($null -eq $ContentProperty -or $null -eq $ContentProperty.Value) {
                    if ($IsPaged) { throw 'ARM returned no content for a continuation page.' }
                    return $null
                }
                $Content = $ContentProperty.Value
                if ($Content -is [string]) {
                    if ([string]::IsNullOrWhiteSpace($Content)) {
                        if ($IsPaged) { throw 'ARM returned empty content for a continuation page.' }
                        return $null
                    }
                    $Content = $Content | ConvertFrom-Json
                }

                # Bare arrays and singleton objects retain their exact historical shape. Only a
                # normal ARM list envelope (a `value` property) participates in pagination.
                $ValueProperty = $Content.PSObject.Properties['value']
                if ($null -eq $ValueProperty) { return $Content }
                foreach ($Item in @($ValueProperty.Value)) {
                    if ($null -ne $Item) { $Items.Add($Item) }
                }

                $NextLinkProperty = $Content.PSObject.Properties['nextLink']
                if ($NextLinkProperty -and -not [string]::IsNullOrWhiteSpace([string]$NextLinkProperty.Value)) {
                    $CurrentPath = [string]$NextLinkProperty.Value
                    $IsPaged = $true
                    continue
                }

                if (-not $IsPaged) { return $Content }
                return [pscustomobject]@{ value = @($Items) }
            }
        }
        catch {
            $StatusCode = Get-ArmChildHttpStatusCode -ErrorRecord $_
            if ($NotFoundIsEmpty -and $StatusCode -eq 404) { return $null }

            # Version/deployment lookups are sub-operations of the owning dataset. Reporting a
            # synthetic type such as AZSC/ARMChild/MLModels.LatestVersion would match no collector
            # and could let an assessment score partial evidence. Collapse health ownership to
            # the public dataset while preserving the exact failed operation for diagnostics.
            $HealthDatasetName = ([string]$DatasetName -split '\.', 2)[0]
            if ($null -ne $CollectionHealth -and $FailedHealthDatasets.Add($HealthDatasetName)) {
                [void]$CollectionHealth.Add([pscustomobject]@{
                        Dataset       = $HealthDatasetName
                        Operation     = $DatasetName
                        Status        = 'Unavailable'
                        Reason        = "Parent '$ParentName' at '$Path': $($_.Exception.Message)"
                        ResourceTypes = @("AZSC/ARMChild/$HealthDatasetName")
                    })
            }
            Write-Warning "Get-ScoutArmChildResource: '$DatasetName' failed for parent '$ParentName' at '$Path' -- skipping this child collection: $($_.Exception.Message)"
            return $null
        }
    }

    function Get-KeyVaultMetadataContent {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string]$VaultUri,
            [Parameter(Mandatory)][ValidateSet('secrets', 'keys')][string]$ObjectKind,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter(Mandatory)][string]$ParentName
        )

        function Get-KeyVaultHttpStatusCode {
            param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

            $ResponseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
            if ($ResponseProperty -and $null -ne $ResponseProperty.Value) {
                $StatusProperty = $ResponseProperty.Value.PSObject.Properties['StatusCode']
                if ($StatusProperty -and $null -ne $StatusProperty.Value) {
                    try { return [int]$StatusProperty.Value } catch { return $null }
                }
            }
            if ($ErrorRecord.Exception.Data -and $ErrorRecord.Exception.Data.Contains('StatusCode')) {
                try { return [int]$ErrorRecord.Exception.Data['StatusCode'] } catch { return $null }
            }
            $StatusMatch = [regex]::Match(
                [string]$ErrorRecord.Exception.Message,
                '(?i)(?:HTTP|status(?:\s+code)?)\D{0,20}(?<code>[1-5]\d{2})(?!\d)'
            )
            if ($StatusMatch.Success) { return [int]$StatusMatch.Groups['code'].Value }
            return $null
        }

        try {
            if ($KeyVaultTokenError) { throw $KeyVaultTokenError }
            if ($null -eq $KeyVaultToken) { throw 'Key Vault metadata token was not acquired.' }
            if ([string]::IsNullOrWhiteSpace($VaultUri)) { throw 'The vault metadata did not contain a vault URI.' }

            $BaseUri = $VaultUri.TrimEnd('/')
            $CurrentUri = "$BaseUri/${ObjectKind}?api-version=7.4&maxresults=25"

            $Items = [System.Collections.Generic.List[object]]::new()
            $SeenUris = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            while ($CurrentUri) {
                if (-not $SeenUris.Add($CurrentUri)) {
                    throw "Key Vault returned a repeated nextLink '$CurrentUri'."
                }

                # This is the Key Vault LIST operation, not GET-secret. Its response contains
                # names, tags and lifecycle attributes only. The whitelist in
                # ConvertTo-KeyVaultArmChild also intentionally discards any unrecognised field,
                # so a secret value can never enter the raw inventory even if an API changes.
                $Response = Invoke-WebRequest -Uri $CurrentUri -Method GET -Authentication Bearer `
                    -Token $KeyVaultToken -SkipHttpErrorCheck -ErrorAction Stop
                if ($null -eq $Response) { throw 'Key Vault returned no response.' }

                $Status = $Response.PSObject.Properties['StatusCode']
                if ($Status -and ([int]$Status.Value -lt 200 -or [int]$Status.Value -ge 300)) {
                    throw "Key Vault returned status $($Status.Value)"
                }
                $ContentProperty = $Response.PSObject.Properties['Content']
                if ($null -eq $ContentProperty -or [string]::IsNullOrWhiteSpace([string]$ContentProperty.Value)) {
                    throw 'Key Vault returned no content.'
                }
                $Content = if ($ContentProperty.Value -is [string]) {
                    $ContentProperty.Value | ConvertFrom-Json
                }
                else {
                    $ContentProperty.Value
                }
                $ValueProperty = $Content.PSObject.Properties['value']
                if ($null -eq $ValueProperty) { throw 'Key Vault list response did not contain a value collection.' }
                foreach ($Item in @($ValueProperty.Value)) {
                    if ($null -ne $Item) { $Items.Add($Item) }
                }

                $NextLinkProperty = $Content.PSObject.Properties['nextLink']
                $CurrentUri = if ($NextLinkProperty) { [string]$NextLinkProperty.Value } else { $null }
            }
            return [pscustomobject]@{ value = @($Items) }
        }
        catch {
            $StatusCode = Get-KeyVaultHttpStatusCode -ErrorRecord $_
            if ($null -ne $CollectionHealth -and $FailedHealthDatasets.Add($DatasetName)) {
                [void]$CollectionHealth.Add([pscustomobject]@{
                        Dataset       = $DatasetName
                        Operation     = "$DatasetName.MetadataList"
                        Status        = 'Unavailable'
                        Reason        = "Vault '$ParentName': $($_.Exception.Message)"
                        ResourceTypes = @("AZSC/ARMChild/$DatasetName")
                        HttpStatus    = $StatusCode
                    })
            }
            Write-Warning "Get-ScoutArmChildResource: '$DatasetName' metadata list failed for vault '$ParentName' -- skipping this vault: $($_.Exception.Message)"
            return $null
        }
    }

    function ConvertTo-KeyVaultArmChild {
        param(
            [Parameter(Mandatory)]$Metadata,
            [Parameter(Mandatory)]$Parent,
            [Parameter(Mandatory)][ValidateSet('secrets', 'keys')][string]$ObjectKind
        )

        $Identifier = if ($ObjectKind -eq 'keys' -and $Metadata.PSObject.Properties['kid']) {
            [string]$Metadata.kid
        }
        elseif ($Metadata.PSObject.Properties['id']) {
            [string]$Metadata.id
        }
        else {
            $null
        }
        if ([string]::IsNullOrWhiteSpace($Identifier)) { return $null }

        $IdentifierPath = if ([uri]::IsWellFormedUriString($Identifier, [System.UriKind]::Absolute)) {
            ([uri]$Identifier).AbsolutePath
        }
        else {
            $Identifier
        }
        $Segments = @($IdentifierPath.Trim('/') -split '/')
        $KindIndex = [array]::IndexOf($Segments, $ObjectKind)
        if ($KindIndex -lt 0 -or $KindIndex + 1 -ge $Segments.Count) { return $null }
        $Name = $Segments[$KindIndex + 1]
        $ParentId = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
        $ParentLocation = Get-ArmParentValue -InputObject $Parent -Name @('location', 'LOCATION')

        $Properties = [ordered]@{}
        foreach ($NameToCopy in 'attributes', 'contentType', 'managed', 'kty', 'keySize', 'curveName', 'rotationPolicy') {
            $Property = $Metadata.PSObject.Properties[$NameToCopy]
            if ($Property) { $Properties[$NameToCopy] = $Property.Value }
        }
        if ($ObjectKind -eq 'secrets') { $Properties['secretUri'] = $Identifier }
        else { $Properties['keyUri'] = $Identifier }

        $TagsProperty = $Metadata.PSObject.Properties['tags']
        return [pscustomobject][ordered]@{
            id         = "$ParentId/$ObjectKind/$Name"
            name       = $Name
            type       = "Microsoft.KeyVault/vaults/$ObjectKind"
            location   = $ParentLocation
            tags       = if ($TagsProperty) { $TagsProperty.Value } else { $null }
            properties = [pscustomobject]$Properties
        }
    }

    function Get-ArmChildItemSet {
        param([AllowNull()]$Content)

        if ($null -eq $Content) { return @() }
        $ValueProperty = $Content.PSObject.Properties['value']
        if ($null -ne $ValueProperty) { return @($ValueProperty.Value) }
        return @($Content)
    }

    function ConvertTo-ArmChildRow {
        param(
            [Parameter(Mandatory)]$Child,
            [Parameter(Mandatory)]$Parent,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter()][AllowNull()][string]$EndpointType,
            [Parameter()][AllowNull()]$LatestVersion,
            [Parameter()][AllowNull()][Nullable[int]]$DeploymentCount
        )

        $ParentId = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
        $ParentType = [string](Get-ArmParentValue -InputObject $Parent -Name @('type', 'TYPE'))
        $ParentName = [string](Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
        $ParentLocation = Get-ArmParentValue -InputObject $Parent -Name @('location', 'LOCATION')
        $SubscriptionId = Get-ArmParentValue -InputObject $Parent -Name @('subscriptionId', 'SubscriptionId')
        $ResourceGroup = Get-ArmParentValue -InputObject $Parent -Name @('resourceGroup', 'RESOURCEGROUP')

        $SourceType = $null
        $SourceTypeProperty = $Child.PSObject.Properties['type']
        if ($null -ne $SourceTypeProperty) { $SourceType = $SourceTypeProperty.Value }
        if ([string]::IsNullOrWhiteSpace([string]$SourceType)) {
            # Several legacy management endpoints return configuration objects without a type.
            # Preserve a useful provenance value by falling back to the resource type queried.
            $SourceType = $ParentType
        }

        $Reserved = @(
            'TYPE', 'PARENTID', 'PARENTTYPE', 'PARENTNAME',
            'subscriptionId', 'RESOURCEGROUP', 'AZSC'
        )
        $Row = [ordered]@{}
        foreach ($Property in $Child.PSObject.Properties) {
            if ($Reserved -contains $Property.Name) { continue }
            $Row[$Property.Name] = $Property.Value
        }

        $Row['TYPE'] = "AZSC/ARMChild/$DatasetName"
        $Row['PARENTID'] = $ParentId
        $Row['PARENTTYPE'] = $ParentType
        $Row['PARENTNAME'] = $ParentName
        $Row['PARENTLOCATION'] = $ParentLocation
        $Row['subscriptionId'] = $SubscriptionId
        $Row['RESOURCEGROUP'] = $ResourceGroup
        $Row['AZSC'] = [PSCustomObject][ordered]@{
            Dataset         = $DatasetName
            ParentId        = $ParentId
            ParentType      = $ParentType
            ParentName      = $ParentName
            SourceType      = $SourceType
            EndpointType    = $EndpointType
            LatestVersion   = $LatestVersion
            DeploymentCount = $DeploymentCount
        }

        return [PSCustomObject]$Row
    }

    $MachineLearningParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.machinelearningservices/workspaces' -and
        (Get-ArmParentValue -InputObject $_ -Name @('kind', 'KIND')) -notin @('Hub', 'Project')
    })
    $OpenAiParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.cognitiveservices/accounts' -and
        (Get-ArmParentValue -InputObject $_ -Name @('kind', 'KIND')) -ieq 'OpenAI'
    })
    $SearchParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.search/searchservices'
    })
    $AvdParents = @($Resources | Where-Object {
        $ParentType = Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')
        $ParentProperties = Get-ArmParentValue -InputObject $_ -Name @('properties', 'PROPERTIES')
        $ApplicationGroupType = if ($null -ne $ParentProperties) {
            Get-ArmParentValue -InputObject $ParentProperties -Name @('applicationGroupType', 'APPLICATIONGROUPTYPE')
        }
        $ParentType -ieq 'microsoft.desktopvirtualization/applicationgroups' -and
            $ApplicationGroupType -ieq 'RemoteApp'
    })
    $AppInsightsParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.insights/components'
    })
    $LogAnalyticsParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.operationalinsights/workspaces'
    })
    $KeyVaultParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.keyvault/vaults'
    })
    $StorageAccountParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.storage/storageaccounts'
    })
    $BackupVaultParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.dataprotection/backupvaults'
    })
    $ReservationParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.capacity/reservationorders/reservations'
    })
    $DiagnosticSettingParents = @($Resources | Where-Object {
        $DiagnosticSettingParentTypes -contains [string](Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE'))
    })
    # AB#6802. Every Arc-enabled server that is actually an Azure Local guest carries this
    # extension resource; every other Arc server (a bare-metal or VMware/SCVMM Arc machine) does
    # not, and the per-machine GET below degrades that absence to a non-fatal 404 -- the same
    # singleton pattern StorageLifecyclePolicies already uses. No `kind`/`vmId` pre-filter is
    # applied because Microsoft.HybridCompute/machines does not reliably expose which platform
    # provisioned it; the ARM response itself is the only trustworthy signal.
    $HybridComputeMachineParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.hybridcompute/machines'
    })

    $KeyVaultToken = $null
    $KeyVaultTokenError = $null
    $KeyVaultDnsSuffix = $null
    if ($KeyVaultParents.Count -gt 0 -and @($Selected | Where-Object { $_ -in @('KeyVaultSecrets', 'KeyVaultKeys') }).Count -gt 0) {
        try {
            $AzContext = Get-AzContext -ErrorAction Stop
            $EnvironmentName = [string]$AzContext.Environment.Name
            $AzEnvironment = Get-AzEnvironment -Name $EnvironmentName -ErrorAction Stop
            $KeyVaultDnsSuffix = [string]$AzEnvironment.AzureKeyVaultDnsSuffix
            $KeyVaultResourceUrl = [string]$AzEnvironment.AzureKeyVaultServiceEndpointResourceId
            if ([string]::IsNullOrWhiteSpace($KeyVaultResourceUrl)) {
                throw "Azure environment '$EnvironmentName' does not expose a Key Vault token resource."
            }
            $TokenResponse = Get-AzAccessToken -ResourceUrl $KeyVaultResourceUrl -AsSecureString `
                -InformationAction SilentlyContinue -WarningAction SilentlyContinue -ErrorAction Stop
            if ($null -eq $TokenResponse -or $TokenResponse.Token -isnot [securestring]) {
                throw 'Get-AzAccessToken returned no secure Key Vault token.'
            }
            $KeyVaultToken = $TokenResponse.Token
        }
        catch {
            $KeyVaultTokenError = $_
        }
    }

    foreach ($DatasetName in $Selected) {
        switch ($DatasetName) {
            'MLComputes' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/computes?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'MLDatasets' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/data?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        $VersionContent = Get-ArmChildContent `
                            -Path "$Base/data/$($Child.name)/versions?api-version=2023-04-01&`$orderby=createdTime desc&`$top=1" `
                            -DatasetName "$DatasetName.LatestVersion" `
                            -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                        $Latest = @(Get-ArmChildItemSet -Content $VersionContent | Select-Object -First 1)
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                            -LatestVersion $(if ($Latest.Count -gt 0) { $Latest[0] } else { $null })
                    }
                }
            }
            'MLDatastores' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/datastores?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'MLEndpoints' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    foreach ($EndpointType in @('onlineEndpoints', 'batchEndpoints')) {
                        $Content = Get-ArmChildContent -Path "$Base/$EndpointType`?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                            Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                        )
                        foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                            $DeploymentContent = Get-ArmChildContent `
                                -Path "$Base/$EndpointType/$($Child.name)/deployments?api-version=2023-04-01" `
                                -DatasetName "$DatasetName.Deployments" `
                                -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                            $Count = @(Get-ArmChildItemSet -Content $DeploymentContent).Count
                            ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                                -EndpointType $EndpointType -DeploymentCount $Count
                        }
                    }
                }
            }
            'MLModels' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/models?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        $VersionContent = Get-ArmChildContent `
                            -Path "$Base/models/$($Child.name)/versions?api-version=2023-04-01&`$orderby=createdTime desc&`$top=1" `
                            -DatasetName "$DatasetName.LatestVersion" `
                            -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                        $Latest = @(Get-ArmChildItemSet -Content $VersionContent | Select-Object -First 1)
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                            -LatestVersion $(if ($Latest.Count -gt 0) { $Latest[0] } else { $null })
                    }
                }
            }
            'MLPipelines' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent `
                        -Path "$Base/jobs?api-version=2023-04-01&`$filter=jobType eq 'Pipeline'" `
                        -DatasetName $DatasetName `
                        -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'OpenAIDeployments' {
                foreach ($Parent in $OpenAiParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/deployments?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'SearchIndexes' {
                foreach ($Parent in $SearchParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/indexes?api-version=2023-11-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'AVDApplications' {
                foreach ($Parent in $AvdParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/applications?api-version=2022-09-09" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'AppInsightsProactiveDetection' {
                foreach ($Parent in $AppInsightsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/ProactiveDetectionConfigs?api-version=2018-05-01-preview" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'LAWorkspaceLinkedServices' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/linkedServices?api-version=2020-08-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'LAWorkspaceSavedSearches' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/savedSearches?api-version=2020-08-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Key Vault children (AB#6837 / AB#7358 / Feature AB#6751) -------------------------
            #
            # These are metadata-only Key Vault LIST calls. Generic ARM child-resource listing
            # returns only secrets/keys created as ARM deployment resources and produced a
            # plausible but incomplete 9/150 result in AB#7358's tenant reconciliation. Key Vault
            # Reader supplies the list/readMetadata data actions without permission to read a
            # secret value. Scout never calls an individual secret URI and whitelists the list
            # response into the existing ARM-child contract below.
            #
            # Certificates are materialised as secrets whose `contentType` is
            # `application/x-pkcs12` or
            # `application/x-pem-file`, and that secret's `attributes.exp` IS the certificate's
            # expiry -- so certificate expiry does come back here, under the secrets dataset, with
            # the content type identifying it. A separate certificate dataset would add no signal
            # to the current expiry assessment and would require another metadata API operation.
            'KeyVaultSecrets' {
                foreach ($Parent in $KeyVaultParents) {
                    $ParentName = [string](Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                    $ParentProperties = Get-ArmParentValue -InputObject $Parent -Name @('properties', 'PROPERTIES')
                    $VaultUri = if ($ParentProperties) {
                        Get-ArmParentValue -InputObject $ParentProperties -Name @('vaultUri', 'VAULTURI')
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$VaultUri) -and -not [string]::IsNullOrWhiteSpace($KeyVaultDnsSuffix)) {
                        $VaultUri = "https://$ParentName.$KeyVaultDnsSuffix/"
                    }
                    $Content = Get-KeyVaultMetadataContent -VaultUri ([string]$VaultUri) -ObjectKind secrets `
                        -DatasetName $DatasetName -ParentName $ParentName
                    foreach ($Metadata in @(Get-ArmChildItemSet -Content $Content)) {
                        $Child = ConvertTo-KeyVaultArmChild -Metadata $Metadata -Parent $Parent -ObjectKind secrets
                        if ($Child) { ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName }
                    }
                }
            }
            'KeyVaultKeys' {
                foreach ($Parent in $KeyVaultParents) {
                    $ParentName = [string](Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                    $ParentProperties = Get-ArmParentValue -InputObject $Parent -Name @('properties', 'PROPERTIES')
                    $VaultUri = if ($ParentProperties) {
                        Get-ArmParentValue -InputObject $ParentProperties -Name @('vaultUri', 'VAULTURI')
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$VaultUri) -and -not [string]::IsNullOrWhiteSpace($KeyVaultDnsSuffix)) {
                        $VaultUri = "https://$ParentName.$KeyVaultDnsSuffix/"
                    }
                    $Content = Get-KeyVaultMetadataContent -VaultUri ([string]$VaultUri) -ObjectKind keys `
                        -DatasetName $DatasetName -ParentName $ParentName
                    foreach ($Metadata in @(Get-ArmChildItemSet -Content $Content)) {
                        $Child = ConvertTo-KeyVaultArmChild -Metadata $Metadata -Parent $Parent -ObjectKind keys
                        if ($Child) { ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName }
                    }
                }
            }

            # --- Storage children (AB#6834) --------------------------------------------------------
            #
            # Also control plane. `blobServices/default/containers` returns each container's
            # `publicAccess` level -- the property that answers "is anything in this account
            # anonymously reachable", which a storage-account list cannot. Listing containers is
            # `Microsoft.Storage/storageAccounts/blobServices/containers/read`, held by Reader.
            # Nothing here reads a blob, a file, or an account key.
            'StorageBlobContainers' {
                foreach ($Parent in $StorageAccountParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/blobServices/default/containers?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'StorageFileShares' {
                foreach ($Parent in $StorageAccountParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/fileServices/default/shares?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'StorageLifecyclePolicies' {
                foreach ($Parent in $StorageAccountParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    # Singleton, not a list: an account with no policy returns 404. That absence
                    # is ordinary empty data and must not become a warning/transcript error.
                    $Content = Get-ArmChildContent -Path "$Base/managementPolicies/default?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    ) -NotFoundIsEmpty
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Storage queues (AB#7087, Story AB#7059, Feature AB#7069, Epic AB#7099) -------------
            #
            # Same reasoning as StorageBlobContainers/StorageFileShares directly above: Queue
            # Storage has no Resource Graph table of its own -- `queueServices/default/queues` is
            # a control-plane list under the storage account, `Microsoft.Storage/storageAccounts/
            # queueServices/queues/read`, held by Reader. Returns metadata only (name + the
            # `metadata` key/value bag a caller attached); no queue message is ever read.
            'StorageQueues' {
                foreach ($Parent in $StorageAccountParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/queueServices/default/queues?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Table Storage (AB#7090, Story AB#7071/AB#7059, Feature AB#7069, Epic AB#7099) ------
            #
            # Same reasoning as StorageQueues directly above: Table Storage has no Resource Graph
            # table of its own -- `tableServices/default/tables` is a control-plane list under the
            # storage account, `Microsoft.Storage/storageAccounts/tableServices/tables/read`, held
            # by Reader. Returns table name and metadata only; no table entity/row is ever read.
            'StorageTables' {
                foreach ($Parent in $StorageAccountParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/tableServices/default/tables?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Backup vault instances (AB#6833) --------------------------------------------------
            #
            # Recovery Services vault protected items already arrive through Resource Graph's
            # `recoveryservicesresources` table (see Get-ScoutRawInventory's -IncludeBackupResources).
            # Backup vaults -- the newer `Microsoft.DataProtection` service that protects disks, blobs,
            # PostgreSQL and AKS -- are NOT in that table, so "which VMs have no backup" was wrong for
            # any estate using them. This closes that half.
            'BackupInstances' {
                foreach ($Parent in $BackupVaultParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/backupInstances?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Diagnostic settings (AB#6769) -----------------------------------------------------
            #
            # WHY THIS IS A REST CALL AND NOT A RESOURCE GRAPH ROW.
            # `microsoft.insights/diagnosticsettings` is an ARM EXTENSION resource: it has no
            # existence of its own, only an attachment to another resource's id, and Resource
            # Graph indexes it in no table. Monitor/ResourceDiagnosticSettings declared that type
            # and read the `resources` table, so it returned zero rows in every tenant at every
            # permission level. The only read that exists is per parent:
            #
            #   GET {resourceId}/providers/Microsoft.Insights/diagnosticSettings
            #       ?api-version=2021-05-01-preview
            #
            # 2021-05-01-preview is the current version and the one AVM pins; it is the first to
            # carry `marketplacePartnerId`, which the worksheet's "Destination: Partner" column
            # reads. Control plane, read-only -- `Microsoft.Insights/diagnosticSettings/read`,
            # which Reader holds. Nothing here reads a log, only where logs are sent.
            #
            # A parent with no diagnostic setting returns an empty `value` array, which produces
            # no row -- and that absence IS the finding the worksheet exists to show. See
            # $DiagnosticSettingParentTypes above for exactly which parents are swept and why the
            # list stops where it does.
            'ResourceDiagnosticSettings' {
                foreach ($Parent in $DiagnosticSettingParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Reservation utilization (AB#6829) -------------------------------------------------
            #
            # `Reservations` already lists WHAT was bought (Microsoft.Capacity/reservationOrders and
            # .../reservations, both indexed by Resource Graph). It cannot say whether any of it is
            # being used -- utilisation is served by a DIFFERENT resource provider,
            # Microsoft.Consumption, scoped per reservation:
            #
            #   GET {reservationOrderId}/reservations/{reservationId}
            #       /providers/Microsoft.Consumption/reservationSummaries?grain=monthly&api-version=2023-05-01
            #
            # This is NOT the billing-account permission system documented in the audit's "Cost and
            # billing" section (§9). Reservations are their own, SIXTH scope: a tenant-level resource
            # independent of subscription RBAC (see "Permissions to view and manage Azure
            # reservations" -- learn.microsoft.com/azure/cost-management-billing/reservations/
            # view-reservations). Microsoft's own guidance is that a built-in Reader role AT THE
            # RESERVATION SCOPE is sufficient to view utilisation; since the parent reservation
            # already came back from Resource Graph (which required exactly that visibility), no
            # additional grant is asked for here -- only the existing billing/cost gate this
            # function's neighbours already document, and even that is arguably not needed, because
            # Reservations Reader (or reservation-scoped Reader) is a distinct system from EA/MCA
            # billing roles.
            #
            # `grain=monthly` returns one row per calendar month; the most recent row is what the
            # collector reports, so a very new reservation with no month closed yet has no
            # utilisation row -- an absence, not a zero, and rendered as such.
            'ReservationUtilization' {
                foreach ($Parent in $ReservationParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/providers/Microsoft.Consumption/reservationSummaries?grain=monthly&api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    $Latest = @(Get-ArmChildItemSet -Content $Content |
                        Sort-Object -Property { [string](Get-ArmParentValue -InputObject $_ -Name @('properties', 'PROPERTIES') |
                            ForEach-Object { Get-ArmParentValue -InputObject $_ -Name @('usageDate', 'UsageDate') }) } -Descending |
                        Select-Object -First 1)
                    foreach ($Child in $Latest) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }

            # --- Azure Local virtual machine instances (AB#6802 / Feature AB#6747) -----------------
            #
            # WHY THIS IS A REST CALL AND NOT A RESOURCE GRAPH ROW.
            # `Microsoft.AzureStackHCI/virtualMachineInstances` is listed on Microsoft's own
            # "resource types that extend capabilities of other resources" page
            # (https://learn.microsoft.com/azure/azure-resource-manager/management/extension-resource-types#microsoftazurestackhci)
            # -- it is an ARM EXTENSION resource, scoped under a `Microsoft.HybridCompute/machines`
            # parent, not a standalone resource. Resource Graph's own supported-type reference
            # (https://learn.microsoft.com/azure/governance/resource-graph/reference/supported-tables-resources)
            # lists eleven other `microsoft.azurestackhci/*` types it indexes -- including the
            # confusingly similar `microsoft.azurestackhci/virtualmachines` (no "instances") --
            # but `virtualmachineinstances` is not one of them. The old declarative collector
            # queried the `resources` table for that exact type and could not have returned a row
            # in ANY tenant, deployed or not: it is the same defect class AB#6769 fixed for
            # ResourceDiagnosticSettings, not the "tenant just has none" verdict AB#6846 recorded
            # (see docs/audits/AZURE-SCOUT-AUDIT.md's revision of that verdict for the full
            # reasoning and citations).
            #
            # The instance is a SINGLETON named `default` under each machine -- there is no list
            # endpoint, matching the Bicep/ARM template reference's `name: 'default' (required)`.
            # A machine that is not an Azure Local guest returns 404, which Get-ArmChildContent
            # already degrades to a warning and $null, exactly like StorageLifecyclePolicies.
            #
            # Control plane, read-only -- `Microsoft.AzureStackHCI/virtualMachineInstances/read`,
            # which Reader's `*/read` wildcard already covers. No new permission is required.
            'AzureLocalVirtualMachineInstances' {
                foreach ($Parent in $HybridComputeMachineParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/providers/Microsoft.AzureStackHCI/virtualMachineInstances/default?api-version=2024-01-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    ) -NotFoundIsEmpty
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
        }
    }
}
