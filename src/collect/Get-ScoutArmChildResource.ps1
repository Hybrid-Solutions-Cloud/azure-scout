#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Prefetch ARM child collections consumed by the declarative inventory collectors.

.DESCRIPTION
    Moves supported per-parent ARM calls out of collector row loops and into the collect phase.
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
            'BackupInstances',
            'ResourceDiagnosticSettings',
            'ReservationUtilization'
        )]
        [string[]]$Dataset = @('All')
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
        'BackupInstances',
        'ResourceDiagnosticSettings',
        'ReservationUtilization'
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
            [Parameter(Mandatory)][string]$ParentName
        )

        try {
            $Response = Invoke-AzRestMethod -Path $Path -Method GET -ErrorAction Stop
            if ($null -eq $Response) { return $null }

            $Status = $Response.PSObject.Properties['StatusCode']
            if ($null -ne $Status -and ([int]$Status.Value -lt 200 -or [int]$Status.Value -ge 300)) {
                throw "ARM returned status $($Status.Value)"
            }

            $Content = $Response.PSObject.Properties['Content']
            if ($null -eq $Content -or $null -eq $Content.Value) { return $null }
            if ($Content.Value -is [string]) {
                if ([string]::IsNullOrWhiteSpace($Content.Value)) { return $null }
                return ($Content.Value | ConvertFrom-Json)
            }
            return $Content.Value
        }
        catch {
            Write-Warning "Get-ScoutArmChildResource: '$DatasetName' failed for parent '$ParentName' at '$Path' -- skipping this child collection: $($_.Exception.Message)"
            return $null
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

            # --- Key Vault children (AB#6837 / Feature AB#6751) ------------------------------------
            #
            # THESE ARE CONTROL-PLANE CALLS AND THEY RETURN NO SECRET VALUES.
            # `Microsoft.KeyVault/vaults/secrets` and `/keys` are ARM resources: the list returns
            # metadata only -- id, contentType, and the `attributes` block carrying `enabled`, `exp`
            # and `nbf`. Reading a secret's VALUE is a data-plane operation against
            # `<vault>.vault.azure.net` and needs a Key Vault access policy or a Key Vault data
            # role; Scout does neither and must not. Reader on the vault is sufficient for these.
            #
            # Certificates have no ARM list endpoint of their own. A Key Vault certificate is
            # materialised as a secret whose `contentType` is `application/x-pkcs12` or
            # `application/x-pem-file`, and that secret's `attributes.exp` IS the certificate's
            # expiry -- so certificate expiry does come back here, under the secrets dataset, with
            # the content type identifying it. That is the honest control-plane answer; a separate
            # 'KeyVaultCertificates' dataset would have to go data-plane to add anything.
            'KeyVaultSecrets' {
                foreach ($Parent in $KeyVaultParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/secrets?api-version=2023-07-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'KeyVaultKeys' {
                foreach ($Parent in $KeyVaultParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/keys?api-version=2023-07-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
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
                    # Singleton, not a list: an account with no policy returns 404, which
                    # Get-ArmChildContent already degrades to a warning and $null. The absence IS
                    # the finding, and the cross-resource rules read it as such.
                    $Content = Get-ArmChildContent -Path "$Base/managementPolicies/default?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
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
        }
    }
}
